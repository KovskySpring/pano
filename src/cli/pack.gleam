//// Multi-scale headless texture packing with the libGDX
//// runnable-texturepacker.jar.
////
//// For each atlas x scale it runs one headless JVM pack pass straight over
//// the source folder (sources are only ever read), converts the libGDX
//// `.atlas` text output to the Phaser multipack JSON the runtime already
//// loads, and writes the pages and JSON exactly as libGDX rendered them
//// into `<out>/<scale>/`.

import cli/config.{type Config}
import cli/gdx_atlas.{type Page}
import cli/phaser
import cli/pool
import cli/settings
import cli/spec.{type Scale, type Spec}
import filepath
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import shellout
import simplifile
import snag
import temporary

/// One unit of work for the pool: a single atlas packed at a single scale.
type Job {
  Job(spec: Spec, scale: Scale)
}

pub fn run(config: Config) -> snag.Result(Nil) {
  let jobs =
    list.flat_map(config.atlases, fn(atlas) {
      list.map(atlas.scales, Job(spec: atlas, scale: _))
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
  |> snag.context("packing " <> job.spec.name <> " [" <> job.scale.dir <> "]")
}

fn pack_in_scratch(
  job: Job,
  config: Config,
  scratch: String,
) -> snag.Result(Nil) {
  let Job(spec: atlas, scale:) = job

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
      settings.encode(atlas.gdx_settings, scale: scale.factor),
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

  let out_dir = filepath.join(atlas.target_dir, scale.dir)
  use _ <- result.try(fs(
    simplifile.create_directory_all(out_dir),
    "creating " <> out_dir,
  ))

  use _ <- result.try(write_pages(atlas, pages, pack_dir, out_dir, scale))

  log_pack(atlas, scale, pages)
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

/// Copy every libGDX page out under its final name, plus the atlas's Phaser
/// multiatlas JSON referencing those names.
fn write_pages(
  atlas: Spec,
  pages: List(Page),
  pack_dir: String,
  out_dir: String,
  scale: Scale,
) -> snag.Result(Nil) {
  let named =
    list.index_map(pages, fn(page, index) {
      #(spec.page_image_name(atlas, index), page)
    })

  use _ <- result.try(
    list.try_map(named, fn(named_page) {
      let #(final_name, page) = named_page
      let target = filepath.join(out_dir, final_name)
      fs(
        simplifile.copy_file(filepath.join(pack_dir, page.image), target),
        "copying " <> target,
      )
    }),
  )

  let json_name = spec.json_name(atlas)
  use _ <- result.try(fs(
    simplifile.write(
      filepath.join(out_dir, json_name),
      phaser.encode(named, scale.factor),
    ),
    "writing " <> json_name,
  ))

  Ok(Nil)
}

fn log_pack(atlas: Spec, scale: Scale, pages: List(Page)) -> Nil {
  let frames =
    list.fold(pages, 0, fn(total, page) { total + list.length(page.frames) })
  io.println(
    "  ["
    <> scale.dir
    <> "] "
    <> atlas.name
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
