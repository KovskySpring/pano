import child_process
import child_process/stdio
import config.{type Atlas, type Config}
import filepath
import gleam/erlang/process
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
import pack_config.{type Settings}
import simplifile
import snag
import temporary

const timeout_grace = 5000

type Job {
  Job(
    spec: Atlas,
    label: String,
    factor: Float,
    settings: Settings,
    out_dir: String,
    timeout: Int,
  )
}

fn describe(job: Job) -> String {
  job.spec.name
  <> case job.label {
    "" -> ""
    l -> " [" <> l <> "]"
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
  |> snag.context("packing " <> describe(job))
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
      simplifile.copy_file(at: from, to: to)
      |> file_utils.with_snag_error(context: "copying " <> from <> " to " <> to)
    }),
  )

  let json = filepath.join(out_dir, path_utils.atlas_json_filename(name))

  simplifile.write(json, phaser.encode(named, scale))
  |> file_utils.with_snag_error(context: "writing " <> json)
}

fn run_packer(job: Job, arguments: List(String)) -> snag.Result(Nil) {
  let exited = process.new_subject()

  use packer <- result.try(
    child_process.from_name("java")
    |> child_process.args(arguments)
    |> child_process.spawn(
      stdio: stdio.collect(fn(output, status) {
        process.send(exited, #(status, output))
      }),
    )
    |> result.map_error(fn(error) {
      snag.new(
        "could not start java: " <> child_process.describe_start_error(error),
      )
    }),
  )

  case process.receive(exited, within: job.timeout) {
    Ok(#(0, _)) -> Ok(Nil)
    Ok(#(status, output)) ->
      snag.error(
        "java exited with status "
        <> int.to_string(status)
        <> ": "
        <> string.trim(output),
      )
    Error(Nil) -> {
      child_process.kill(packer)
      snag.error("timed out after " <> int.to_string(job.timeout) <> "ms")
    }
  }
}

fn pack_in_scratch(
  job: Job,
  config: Config,
  scratch: String,
) -> snag.Result(Nil) {
  let atlas = job.spec

  let source_dir = atlas.source_dir

  use source_exists <- result.try({
    simplifile.is_directory(source_dir)
    |> file_utils.with_snag_error(context: "checking " <> source_dir)
  })

  use _ <- result.try(case source_exists {
    True -> Ok(Nil)
    False -> snag.error("source dir " <> source_dir <> " does not exist")
  })

  let settings_path = filepath.join(scratch, "pack.json")

  use _ <- result.try({
    simplifile.write(
      settings_path,
      pack_config.encode(job.settings, scale: job.factor),
    )
    |> file_utils.with_snag_error(
      context: "writing pack settings to " <> settings_path,
    )
  })

  let pack_dir = filepath.join(scratch, "out")

  use _ <- result.try({
    simplifile.create_directory_all(pack_dir)
    |> file_utils.with_snag_error(context: "creating pack dir " <> pack_dir)
  })

  // `-Djava.awt.headless=true` stops the JVM from initializing macOS AppKit
  // (TexturePacker uses AWT for image IO), which otherwise steals window
  // focus. Must precede `-jar` to reach the JVM, not the app.
  use _ <- result.try(
    run_packer(job, [
      "-Djava.awt.headless=true",
      "-jar",
      config.jar,
      source_dir,
      pack_dir,
      atlas.name,
      settings_path,
    ]),
  )

  let atlas_path = filepath.join(pack_dir, atlas.name <> ".atlas")

  use atlas_text <- result.try({
    simplifile.read(atlas_path)
    |> file_utils.with_snag_error(context: "reading " <> atlas_path)
  })

  use pages <- result.try(
    gdx.parse_gdx(atlas_text) |> snag.context("parsing " <> atlas_path),
  )

  use _ <- result.try({
    simplifile.create_directory_all(job.out_dir)
    |> file_utils.with_snag_error(context: "creating " <> job.out_dir)
  })

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
  let jobs =
    list.flat_map(config.atlases, fn(atlas) {
      case atlas.variants {
        // No variants: one job at factor 1.0, output directly to target_dir.
        [] -> [
          Job(
            spec: atlas,
            label: "",
            factor: 1.0,
            settings: atlas.gdx_settings,
            out_dir: atlas.target_dir,
            timeout: atlas.timeout,
          ),
        ]
        vs ->
          list.map(vs, fn(v) {
            Job(
              spec: atlas,
              label: v.name,
              factor: v.scale_factor,
              settings: v.gdx_settings,
              out_dir: filepath.join(atlas.target_dir, v.name),
              timeout: v.timeout,
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
    pool.exec(
      jobs,
      limit: config.concurrency,
      timeout: fn(job) { job.timeout + timeout_grace },
      run: run_job(_, config),
    )

  let #(_, errors) =
    list.zip(jobs, results)
    |> list.map(fn(entry) {
      let #(job, outcome) = entry
      case outcome {
        pool.Finished(result) -> result
        pool.TimedOut ->
          snag.error(
            "The packer timed out after "
            <> int.to_string(job.timeout + timeout_grace)
            <> "ms",
          )
          |> snag.context("packing " <> describe(job))
      }
    })
    |> result.partition

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
