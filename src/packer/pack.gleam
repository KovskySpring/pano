//// Multi-variant headless texture packing with the libGDX
//// runnable-texturepacker.jar.
////
//// For each atlas × variant it runs one headless JVM pack pass over the
//// source folder, converts the libGDX `.atlas` text output to the Phaser
//// multipack JSON the runtime already loads, then re-encodes each page with
//// ansel/libvips into every compression output defined for that variant.
////
//// Output directory layout mirrors `packer/spec`:
////   no variants   → `<target_dir>/`
////   has variants  → `<target_dir>/<variant.name>/`
////   + compression → `<target_dir>/<variant.name>/<compression.name>/`

import ansel.{type Image}
import ansel/image
import filepath
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import optimizer/encode
import packer/config.{type Config}
import packer/gdx_atlas.{type Page}
import packer/phaser
import packer/pool
import packer/settings
import packer/spec.{type Compression, type Spec}
import shellout
import simplifile
import snag
import temporary

/// One unit of work for the pool: one atlas packed at one variant's scale.
type Job {
  Job(
    spec: Spec,
    /// Variant name used for logging; empty string for the no-variants case.
    label: String,
    factor: Float,
    /// Resolved output directory for this job (`target_dir[/variant.name]`).
    out_dir: String,
    compression: List(Compression),
  )
}

pub fn run(config: Config) -> snag.Result(Nil) {
  let jobs =
    list.flat_map(config.atlases, fn(atlas) {
      case atlas.variants {
        // No variants: one job at factor 1.0, output directly to target_dir.
        [] -> [
          Job(
            spec: atlas,
            label: "",
            factor: 1.0,
            out_dir: atlas.target_dir,
            compression: [],
          ),
        ]
        vs ->
          list.map(vs, fn(v) {
            Job(
              spec: atlas,
              label: v.name,
              factor: v.factor,
              out_dir: filepath.join(atlas.target_dir, v.name),
              compression: v.compression,
            )
          })
      }
    })

  io.println(
    "Packing "
    <> int.to_string(list.length(config.atlases))
    <> " atlas(es) as "
    <> int.to_string(list.length(jobs))
    <> " pack job(s), "
    <> int.to_string(config.concurrency)
    <> " at a time…",
  )

  let results =
    pool.map(jobs, limit: config.concurrency, run: run_job(_, config))
  let #(_, errors) = result.partition(results)

  case errors {
    [] -> {
      io.println(
        "\nDone: "
        <> int.to_string(list.length(config.atlases))
        <> " atlas(es).",
      )
      Ok(Nil)
    }
    _ -> {
      let issues =
        errors
        |> list.map(snag.pretty_print)
        |> string.join("\n")
      io.println_error(issues)
      snag.error(int.to_string(list.length(errors)) <> " pack job(s) failed")
    }
  }
}

fn run_job(job: Job, config: Config) -> snag.Result(Nil) {
  let scratch =
    temporary.directory()
    |> temporary.with_prefix("gdxpack-")

  case temporary.create(scratch, run: pack_in_scratch(job, config, _)) {
    Ok(outcome) -> outcome
    Error(error) ->
      snag.error(
        "could not create temp dir: " <> simplifile.describe_error(error),
      )
  }
  |> snag.context(
    "packing "
    <> job.spec.name
    <> case job.label {
      "" -> ""
      l -> " [" <> l <> "]"
    },
  )
}

fn pack_in_scratch(
  job: Job,
  config: Config,
  scratch: String,
) -> snag.Result(Nil) {
  let atlas = job.spec

  let source_dir = atlas.source_dir
  use source_exists <- result.try(fs(
    simplifile.is_directory(source_dir),
    "checking " <> source_dir,
  ))
  use _ <- result.try(case source_exists {
    True -> Ok(Nil)
    False -> snag.error("source dir " <> source_dir <> " does not exist")
  })

  let settings_path = filepath.join(scratch, "pack.json")
  use _ <- result.try(fs(
    simplifile.write(
      settings_path,
      settings.encode(atlas.gdx_settings, scale: job.factor),
    ),
    "writing pack settings",
  ))

  let pack_dir = filepath.join(scratch, "out")
  use _ <- result.try(fs(
    simplifile.create_directory_all(pack_dir),
    "creating pack dir",
  ))

  // `-Djava.awt.headless=true` stops the JVM from initializing macOS AppKit
  // (TexturePacker uses AWT for image IO), which otherwise steals window
  // focus. Must precede `-jar` to reach the JVM, not the app.
  use _ <- result.try(
    shellout.command(
      run: "java",
      with: [
        "-Djava.awt.headless=true",
        "-jar",
        config.jar,
        source_dir,
        pack_dir,
        atlas.name,
        settings_path,
      ],
      in: ".",
      opt: [],
    )
    |> result.map_error(fn(error) {
      snag.new(
        "java exited with status "
        <> int.to_string(error.0)
        <> ": "
        <> string.trim(error.1),
      )
    }),
  )

  let atlas_path = filepath.join(pack_dir, atlas.name <> ".atlas")
  use atlas_text <- result.try(fs(
    simplifile.read(atlas_path),
    "reading " <> atlas_path,
  ))
  use pages <- result.try(
    gdx_atlas.parse(atlas_text) |> snag.context("parsing " <> atlas_path),
  )
  use _ <- result.try(check_page_count(atlas, pages))

  use _ <- result.try(fs(
    simplifile.create_directory_all(job.out_dir),
    "creating " <> job.out_dir,
  ))

  use _ <- result.try(write_pages(
    atlas,
    pages,
    pack_dir,
    job.out_dir,
    job.compression,
    job.factor,
  ))

  log_pack(job, pages)
  Ok(Nil)
}

/// Un-indexed page names have no `-<index>` marker, so a multi-page pack
/// would silently overwrite its own pages.
fn check_page_count(atlas: Spec, pages: List(Page)) -> snag.Result(Nil) {
  case atlas.indexed, pages {
    False, [_, _, ..] ->
      snag.error(
        "atlas overflowed onto "
        <> int.to_string(list.length(pages))
        <> " pages but its filenames are un-indexed; pages would overwrite"
        <> " each other. Mark it indexed or shrink the source art.",
      )
    _, _ -> Ok(Nil)
  }
}

/// Re-encode every libGDX page into each compression output, each written
/// into its own subdirectory under `out_dir`.
fn write_pages(
  atlas: Spec,
  pages: List(Page),
  pack_dir: String,
  out_dir: String,
  compression: List(Compression),
  factor: Float,
) -> snag.Result(Nil) {
  case compression {
    [] -> Ok(Nil)
    items -> {
      use loaded <- result.try(
        list.try_map(pages, fn(page) {
          image.read(from: filepath.join(pack_dir, page.image))
          |> snag.context("reading " <> page.image)
          |> result.map(fn(i) { #(i, page) })
        }),
      )

      use _ <- result.try(
        list.try_map(items, fn(compression) {
          let comp_dir = filepath.join(out_dir, compression.name)
          let create_result =
            simplifile.create_directory_all(comp_dir)
            |> fs("creating " <> comp_dir)
          use _ <- result.try(create_result)
          write_variant(atlas, loaded, compression, comp_dir, factor)
        }),
      )

      Ok(Nil)
    }
  }
}

/// Write one compression output: every page re-encoded into `out_dir`,
/// plus the Phaser multiatlas JSON.
fn write_variant(
  atlas: Spec,
  loaded_pages: List(#(Image, Page)),
  compression: Compression,
  out_dir: String,
  factor: Float,
) -> snag.Result(Nil) {
  let named =
    list.index_map(loaded_pages, fn(loaded_page, index) {
      let #(data, page) = loaded_page
      let name = spec.page_image_name(atlas.name, atlas.indexed, index)
      #(data, name, page)
    })

  use _ <- result.try(
    list.try_map(named, fn(named_page) {
      let #(loaded, name, _) = named_page
      encode.write(
        loaded,
        to: filepath.join(out_dir, name),
        format: compression.format,
      )
    }),
  )

  let json_pages =
    list.map(named, fn(named_page) {
      let #(_, name, page) = named_page
      #(name, page)
    })

  let json = spec.json_name(atlas.name)

  let phaser_json =
    simplifile.write(
      filepath.join(out_dir, json),
      phaser.encode(json_pages, factor),
    )

  fs(phaser_json, "writing " <> json)
}

fn log_pack(job: Job, pages: List(Page)) -> Nil {
  let frames =
    list.fold(pages, 0, fn(total, page) { total + list.length(page.frames) })
  let label = case job.label {
    "" -> ""
    l -> "[" <> l <> "] "
  }
  io.println(
    "  "
    <> label
    <> job.spec.name
    <> ": "
    <> int.to_string(list.length(pages))
    <> " page(s), "
    <> int.to_string(frames)
    <> " frames",
  )
}

fn fs(
  outcome: Result(a, simplifile.FileError),
  while doing: String,
) -> snag.Result(a) {
  result.map_error(outcome, fn(error) {
    snag.new(doing <> ": " <> simplifile.describe_error(error))
  })
}
