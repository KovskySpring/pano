//// CLI for the GDX texture build - a drop-in replacement for the packing
//// half of the old `management/textures/build.ts` + `gdxPack.ts`.
////
//// All configuration (paths, concurrency, scales, and the atlas registry)
//// comes from a `packs.toml` file, found in the current directory by default
//// or given via `--config`:
////
////   gleam run                              # pack every atlas in ./packs.toml
////   gleam run -- --config=path/packs.toml  # explicit config location

import argv
import gleam/io
import gleam/result
import glint
import packer/config
import packer/pack
import shellout
import snag

const app_name = "pano"

const flag_config = "config"

const default_config_filename = "packs.toml"

const message_about = "Multi-threaded texture packer for Phaser 3, using libGDX's TexturePacker and libvips under the hood."

const message_help_config = "Path to the packs.toml config (default: packs.toml in the current directory)"

pub fn main() {
  glint.new()
  |> glint.with_name(app_name)
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: pack_command())
  |> glint.run(argv.load().arguments)
}

fn pack_command() -> glint.Command(Nil) {
  use <- glint.command_help(message_about)

  use config_flag <- glint.flag(
    glint.string_flag(flag_config)
    |> glint.flag_default(default_config_filename)
    |> glint.flag_help(message_help_config),
  )

  use _, _, flags <- glint.command()

  let outcome =
    config_flag(flags)
    |> result.try(config.load)
    |> result.map(pack.run)

  case outcome {
    Ok(_) -> Nil
    Error(issue) -> fail(issue)
  }
}

fn fail(issue: snag.Snag) -> Nil {
  io.println_error(snag.pretty_print(issue))
  shellout.exit(1)
}
