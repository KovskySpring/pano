//// Re-encodes an image to a given output path using
//// ansel (libvips).

import ansel.{type Image}
import ansel/image
import filepath
import gleam/result
import optimizer/spec.{type Format, Png}
import optimizer/vips/png/options as png_options
import snag

/// Write `loaded` to `path`
pub fn write(
  loaded: Image,
  to path: String,
  format format: Format,
) -> snag.Result(Nil) {
  image.write(
    loaded,
    to: filepath.strip_extension(path),
    in: image.Custom(extension: extension(format), format: options(format)),
  )
  |> result.replace(Nil)
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
