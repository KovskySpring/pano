//// Multi-variant headless texture packing with the libGDX
//// runnable-texturepacker.jar.
////
//// For each atlas × variant it runs one headless JVM pack pass over the
//// source folder, converts the libGDX `.atlas` text output to the Phaser
//// multipack JSON the runtime already loads, then re-encodes each page with
//// the `vips` CLI into every compression output defined for that variant.
////
//// Output directory layout mirrors `packer/spec`:
////   no variants   → `<target_dir>/`
////   has variants  → `<target_dir>/<variant.name>/`
////   + compression → `<target_dir>/<variant.name>/<compression.name>/`

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
  use _ <- result.try(check_java())
  use _ <- result.try(case uses_compression(config) {
    True -> check_vips(config.vips)
    False -> Ok(Nil)
  })

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

/// libvips is user-installed, so fail once up front with an actionable message
/// rather than once per page from deep inside the pool. The version is printed
/// because the palette quantiser differs between libvips builds, so a build log
/// that records it is the only way to explain a change in output size.
fn check_vips(vips: String) -> snag.Result(Nil) {
  use output <- result.try(
    shellout.command(run: vips, with: ["--version"], in: ".", opt: [])
    |> result.replace_error(snag.new(
      "could not run `"
      <> vips
      <> "`; pano needs the libvips CLI (`brew install vips`, `apt install"
      <> " libvips-tools`), or set `vips` in packs.toml to its path",
    )),
  )

  let version = string.trim(output)
  use _ <- result.try(case parse_version(version) {
    // `keep=` replaced `strip=` in libvips 8.15; older builds reject it
    // outright, which would fail on every page instead of once here.
    Ok(#(major, minor)) ->
      case major > 8 || { major == 8 && minor >= 15 } {
        True -> Ok(Nil)
        False ->
          snag.error("libvips 8.15 or newer is required, found " <> version)
      }
    Error(Nil) -> Ok(Nil)
  })

  io.println("Using " <> version)
  Ok(Nil)
}

/// `vips --version` prints `vips-8.18.5`.
fn parse_version(version: String) -> Result(#(Int, Int), Nil) {
  case string.split(string.replace(version, "vips-", ""), ".") {
    [major, minor, ..] -> {
      use major <- result.try(int.parse(major))
      use minor <- result.try(int.parse(minor))
      Ok(#(major, minor))
    }
    _ -> Error(Nil)
  }
}

/// `vips` is only ever shelled out to for atlases/variants that declare a
/// `[compression]` table (see `write_pages`), so a config with none never
/// needs libvips installed at all.
fn uses_compression(config: Config) -> Bool {
  list.any(config.atlases, fn(atlas) {
    list.any(atlas.variants, fn(v) { v.compression != [] })
  })
}

/// A JVM is user-installed, so fail once up front with an actionable message
/// rather than once per atlas from deep inside the pool.
fn check_java() -> snag.Result(Nil) {
  use output <- result.try(
    shellout.command(run: "java", with: ["-version"], in: ".", opt: [])
    |> result.replace_error(snag.new(
      "could not run `java`; pano needs a JVM to run libGDX TexturePacker"
      <> " (install a JRE/JDK 8+)",
    )),
  )

  let version = string.trim(output)
  use _ <- result.try(case parse_java_version(version) {
    Ok(major) ->
      case major >= 8 {
        True -> Ok(Nil)
        False -> snag.error("Java 8 or newer is required, found " <> version)
      }
    // A version string in an unrecognised shape shouldn't block a pack run;
    // it just means the message below can't confirm the version.
    Error(Nil) -> Ok(Nil)
  })

  io.println("Using " <> version)
  Ok(Nil)
}

/// `java -version` writes its first line to stderr (merged into `output` by
/// `shellout`), e.g. `openjdk version "17.0.8" 2023-07-18` or, pre-JEP 223,
/// `java version "1.8.0_311"`. Versions before 9 are prefixed with `1.`, so
/// `1.8.0_311` means major version 8, not 1.
fn parse_java_version(output: String) -> Result(Int, Nil) {
  use line <- result.try(list.first(string.split(output, "\n")))
  use #(_, after_quote) <- result.try(string.split_once(line, "\""))
  use #(version, _) <- result.try(string.split_once(after_quote, "\""))
  case string.split(version, ".") {
    ["1", minor, ..] -> int.parse(minor)
    [major, ..] -> int.parse(major)
    _ -> Error(Nil)
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
    config.vips,
  ))

  log_pack(job, pages)
  Ok(Nil)
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
  vips: String,
) -> snag.Result(Nil) {
  case compression {
    [] -> Ok(Nil)
    items -> {
      use _ <- result.try(
        list.try_map(items, fn(compression) {
          let comp_dir = filepath.join(out_dir, compression.name)
          let create_result =
            simplifile.create_directory_all(comp_dir)
            |> fs("creating " <> comp_dir)
          use _ <- result.try(create_result)
          write_variant(
            atlas,
            pages,
            pack_dir,
            compression,
            comp_dir,
            factor,
            vips,
          )
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
  pages: List(Page),
  pack_dir: String,
  compression: Compression,
  out_dir: String,
  factor: Float,
  vips: String,
) -> snag.Result(Nil) {
  let named =
    list.index_map(pages, fn(page, index) {
      let name = spec.page_image_name(atlas.name, index)
      #(name, page)
    })

  use _ <- result.try(
    list.try_map(named, fn(named_page) {
      let #(name, page) = named_page
      encode.write(
        from: filepath.join(pack_dir, page.image),
        to: filepath.join(out_dir, name),
        format: compression.format,
        using: vips,
      )
    }),
  )

  let json = spec.json_name(atlas.name)

  let phaser_json =
    simplifile.write(filepath.join(out_dir, json), phaser.encode(named, factor))

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
