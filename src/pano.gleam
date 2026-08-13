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
import glint
import packer/config
import packer/pack
import shellout
import snag

pub fn main() {
  glint.new()
  |> glint.with_name("pano")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: pack_command())
  |> glint.run(argv.load().arguments)
}

fn pack_command() -> glint.Command(Nil) {
  use <- glint.command_help(
    "Multi-threaded texture packer for Phaser 3,
    using libGDX's TexturePacker under the hood.",
  )
  use config_flag <- glint.flag(
    glint.string_flag("config")
    |> glint.flag_default("packs.toml")
    |> glint.flag_help(
      "Path to the packs.toml config (default: packs.toml in the current"
      <> " directory)",
    ),
  )
  use _, _, flags <- glint.command()

  let assert Ok(config_path) = config_flag(flags)
  case config.load(config_path) {
    Error(issue) -> fail(issue)
    Ok(loaded) ->
      case pack.run(loaded) {
        Ok(Nil) -> Nil
        Error(issue) -> fail(issue)
      }
  }
}

fn fail(issue: snag.Snag) -> Nil {
  io.println_error(snag.pretty_print(issue))
  shellout.exit(1)
}
