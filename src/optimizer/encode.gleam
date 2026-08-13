//// Re-encodes an image to a given output path by shelling out to the `vips`
//// CLI.

import filepath
import gleam/int
import gleam/string
import optimizer/spec.{type Format, Png}
import optimizer/vips/png/options as png_options
import shellout
import snag

/// Re-encode `source` into `path`, applying `format`'s encoder options.
pub fn write(
  from source: String,
  to path: String,
  format format: Format,
  using vips: String,
) -> snag.Result(Nil) {
  // The vips bracket suffix, omitted entirely when no options are set so the
  // target stays a plain filename rather than an empty `[]`.
  let suffix = case options(format) {
    "" -> ""
    options -> "[" <> options <> "]"
  }

  let target = filepath.strip_extension(path) <> extension(format) <> suffix

  let outcome =
    shellout.command(
      run: vips,
      with: ["copy", source, target],
      in: ".",
      opt: [],
    )

  case outcome {
    // vips is silent on success. An out-of-range option value only produces a
    // GLib warning and still exits 0, so treat any output as a failure -
    // otherwise a typo in `packs.toml` silently ships an unoptimised page.
    Ok(output) ->
      case string.trim(output) {
        "" -> Ok(Nil)
        warning -> snag.error("vips warned: " <> warning)
      }
    Error(#(status, output)) ->
      snag.error(
        "vips exited with status "
        <> int.to_string(status)
        <> ": "
        <> string.trim(output),
      )
  }
  |> snag.context("encoding " <> path)
}

fn extension(format: Format) -> String {
  case format {
    Png(_) -> ".png"
  }
}

fn options(format: Format) -> String {
  case format {
    Png(options: opts) -> png_options.to_vips_string(opts)
  }
}
