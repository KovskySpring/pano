//// Multi-variant headless texture packing with the libGDX
//// runnable-texturepacker.jar.
////
//// For each atlas × variant it runs one headless JVM pack pass over the
//// source folder into a scratch directory, parses the libGDX `.atlas` text
//// output, then copies the pages into the job's output directory under
//// pano's `<name>-<index>.png` naming alongside the Phaser multipack JSON
//// the runtime loads.
////
//// Jobs run through `packer/pool` at the config's `concurrency`; a failing
//// job doesn't stop the others, and `run` reports every failure at the end.
////
//// Output directory layout:
////   no variants   → `<target_dir>/`
////   has variants  → `<target_dir>/<variant.name>/`

import config.{type Atlas, type Config}
import filepath
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import internal/compat/gdx.{type Page}
import internal/compat/phaser
import internal/file_utils
import internal/path_utils
import internal/pool
import pack_config
import shellout
import simplifile
import snag
import temporary

/// One unit of work for the pool: one atlas packed at one variant's scale.
type Job {
  Job(
    spec: Atlas,
    /// Variant name used for logging; empty string for the no-variants case.
    label: String,
    factor: Float,
    /// Resolved output directory for this job (`target_dir[/variant.name]`).
    out_dir: String,
  )
}

/// A JVM is user-installed, so fail once up front with an actionable message
/// rather than once per atlas from deep inside the pool.
fn check_java() -> snag.Result(Nil) {
  use java_output <- result.try(
    shellout.command(run: "java", with: ["-version"], in: ".", opt: [])
    |> result.replace_error(snag.new(
      "could not run `java`; pano needs a JVM to run libGDX TexturePacker"
      <> " (install a JRE/JDK 8+)",
    )),
  )

  let version = string.trim(java_output)
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

/// `java -version` writes its first line to stderr (merged into the string
/// `shellout` returns), e.g. `openjdk version "17.0.8" 2023-07-18` or, pre-JEP 223,
/// `java version "1.8.0_311"`. Versions before 9 are prefixed with `1.`, so
/// `1.8.0_311` means major version 8, not 1.
fn parse_java_version(java_output: String) -> Result(Int, Nil) {
  use line <- result.try(list.first(string.split(java_output, "\n")))
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

/// Copy every packed page from `from` into `to` under pano's own naming, then
/// write the Phaser multiatlas JSON that indexes them. `scale` is the
/// variant's factor, recorded per texture.
///
/// `from` is the pack job's scratch directory, deleted once the job returns,
/// so anything not copied here is lost. `to` must already exist, and pages
/// left behind by an earlier run with more pages are not removed.
fn write(
  name: String,
  pages: List(Page),
  from pack_dir: String,
  to out_dir: String,
  scale scale: Float,
) -> snag.Result(Nil) {
  let named =
    list.index_map(pages, fn(page, index) {
      #(path_utils.page_image_filename(name, index), page)
    })

  use _ <- result.try(
    list.try_each(named, fn(entry) {
      let #(image, page) = entry
      let from = filepath.join(pack_dir, page.image)
      let to = filepath.join(out_dir, image)
      file_utils.context(
        simplifile.copy_file(at: from, to: to),
        while: "copying " <> from <> " to " <> to,
      )
    }),
  )

  let json = filepath.join(out_dir, path_utils.atlas_json_filename(name))
  file_utils.context(
    simplifile.write(json, phaser.encode(named, scale)),
    while: "writing " <> json,
  )
}

fn pack_in_scratch(
  job: Job,
  config: Config,
  scratch: String,
) -> snag.Result(Nil) {
  let atlas = job.spec

  let source_dir = atlas.source_dir
  use source_exists <- result.try(file_utils.context(
    simplifile.is_directory(source_dir),
    "checking " <> source_dir,
  ))
  use _ <- result.try(case source_exists {
    True -> Ok(Nil)
    False -> snag.error("source dir " <> source_dir <> " does not exist")
  })

  let settings_path = filepath.join(scratch, "pack.json")
  use _ <- result.try(file_utils.context(
    simplifile.write(
      settings_path,
      pack_config.encode(atlas.gdx_settings, scale: job.factor),
    ),
    "writing pack settings",
  ))

  let pack_dir = filepath.join(scratch, "out")
  use _ <- result.try(file_utils.context(
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

  use atlas_text <- result.try(file_utils.context(
    simplifile.read(atlas_path),
    "reading " <> atlas_path,
  ))

  use pages <- result.try(
    gdx.parse_gdx(atlas_text) |> snag.context("parsing " <> atlas_path),
  )

  use _ <- result.try(file_utils.context(
    simplifile.create_directory_all(job.out_dir),
    "creating " <> job.out_dir,
  ))

  use _ <- result.try(write(
    atlas.name,
    pages,
    from: pack_dir,
    to: job.out_dir,
    scale: job.factor,
  ))

  log_pack(job, pages)
  Ok(Nil)
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

pub fn pack(config: Config) -> snag.Result(Nil) {
  use _ <- result.try(check_java())

  let jobs =
    list.flat_map(config.atlases, fn(atlas) {
      case atlas.variants {
        // No variants: one job at factor 1.0, output directly to target_dir.
        [] -> [
          Job(spec: atlas, label: "", factor: 1.0, out_dir: atlas.target_dir),
        ]
        vs ->
          list.map(vs, fn(v) {
            Job(
              spec: atlas,
              label: v.name,
              factor: v.scale_factor,
              out_dir: filepath.join(atlas.target_dir, v.name),
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
