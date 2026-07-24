//// Encoder for the Phaser 3 multipack JSON format consumed by
//// `load.multiatlas` (the `textures[]` / `frames[]`

import cli/gdx_atlas.{type Frame, type Page}
import gleam/float
import gleam/int
import gleam/json.{type Json}

pub const meta_app = "https://github.com/libgdx/libgdx (runnable-texturepacker)"

/// Encode pages, each paired with its final output image filename, as a
/// Phaser multiatlas JSON string. `scale` is the downscale factor this pack
/// pass was rendered at (recorded per texture, as Phaser expects).
pub fn encode(pages: List(#(String, Page)), scale: Float) -> String {
  json.object([
    #("textures", json.array(pages, texture_to_json(_, scale))),
    #(
      "meta",
      json.object([
        #("app", json.string(meta_app)),
        #("version", json.string("3.0")),
      ]),
    ),
  ])
  |> json.to_string
}

fn texture_to_json(named_page: #(String, Page), scale: Float) -> Json {
  let #(image, page) = named_page
  json.object([
    #("image", json.string(image)),
    #("format", json.string(page.format)),
    #("size", size_to_json(page.size)),
    #("scale", scale_to_json(scale)),
    #("frames", json.array(page.frames, frame_to_json)),
  ])
}

fn frame_to_json(frame: Frame) -> Json {
  json.object([
    #("filename", json.string(frame.filename)),
    #("rotated", json.bool(frame.rotated)),
    #("trimmed", json.bool(frame.trimmed)),
    #("sourceSize", size_to_json(frame.source_size)),
    #("spriteSourceSize", rect_to_json(frame.sprite_source)),
    #("frame", rect_to_json(frame.region)),
  ])
}

/// Whole factors are emitted as JSON ints
fn scale_to_json(scale: Float) -> Json {
  let truncated = float.truncate(scale)
  case int.to_float(truncated) == scale {
    True -> json.int(truncated)
    False -> json.float(scale)
  }
}

fn size_to_json(size: #(Int, Int)) -> Json {
  json.object([#("w", json.int(size.0)), #("h", json.int(size.1))])
}

fn rect_to_json(rect: #(Int, Int, Int, Int)) -> Json {
  json.object([
    #("x", json.int(rect.0)),
    #("y", json.int(rect.1)),
    #("w", json.int(rect.2)),
    #("h", json.int(rect.3)),
  ])
}
