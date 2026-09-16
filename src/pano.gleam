//// CLI for the GDX texture build.
////
//// All configuration (paths, concurrency, scales, libGDX settings, and the
//// atlas registry) comes from a `packs.toml` file, found in the current
//// directory by default or given via `--config`:
////
////   gleam run                              # pack every atlas in ./packs.toml
////   gleam run -- --config=path/packs.toml  # explicit config location

import argv
import child_process.{Output}
import config
import gleam/int
import gleam/io
import gleam/result
import gleam/string
import glint
import pack
import snag

const app_name = "pano"

const flag_config = "config"

const default_config_filename = "packs.toml"

const message_about = "Multi-threaded texture packer for Phaser 3, using libGDX's TexturePacker under the hood."

const message_help_config = "Path to the packs.toml config (default: packs.toml in the current directory)"

pub fn main() {
  glint.new()
  |> glint.with_name(app_name)
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: receive_pack_command())
  |> glint.run(argv.load().arguments)
}

fn load_config(path: String) -> snag.Result(config.Config) {
  config.load_config(path)
  |> result.map_error(config.describe_parse_error)
  |> result.map_error(snag.new)
}

fn check_java() -> snag.Result(String) {
  let outcome = child_process.exec(run: "java", with: ["-version"], in: ".")
  case outcome {
    Ok(Output(status_code: 0, output:)) -> Ok("Using " <> string.trim(output))
    Ok(Output(status_code:, output:)) ->
      Error(snag.new(
        "java exited with status "
        <> int.to_string(status_code)
        <> ": "
        <> string.trim(output),
      ))
    Error(error) -> Error(snag.new(child_process.describe_start_error(error)))
  }
  |> snag.context(
    "Checking for `java` (`pano` needs a JVM - JRE/JDK 8+ to run libGDX TexturePacker)",
  )
}

fn check_runtime() -> snag.Result(Nil) {
  use msg <- result.map(check_java())
  io.println(msg)
  Nil
}

fn run_pack(path: String) -> snag.Result(Nil) {
  use _ <- result.try(check_runtime())
  use config <- result.try(load_config(path))
  pack.pack(config)
}

fn receive_pack_command() -> glint.Command(Nil) {
  use <- glint.command_help(message_about)

  use parse_flag <- glint.flag(
    glint.string_flag(flag_config)
    |> glint.flag_default(default_config_filename)
    |> glint.flag_help(message_help_config),
  )

  use _, _, flags <- glint.command()

  let outcome =
    flags
    |> parse_flag
    |> result.try(run_pack)

  case outcome {
    Ok(_) -> Nil
    Error(issue) -> fail(issue)
  }
}

fn fail(issue: snag.Snag) -> Nil {
  io.println_error(snag.pretty_print(issue))
  halt(1)
}

@external(erlang, "pano_ffi", "halt")
fn halt(status: Int) -> Nil
