//// Parser for the legacy libGDX TexturePacker `.atlas` text format
//// Converts to Phaser-friendly `Page` and `Frame` structs.
////
////   <page-image.png>
////   size: W, H
////   format: RGBA8888
////   filter: Linear, Linear
////   repeat: none
////   <region-name>
////     rotate: false
////     xy: X, Y
////     size: W, H
////     orig: W, H
////     offset: X, Y
////     index: -1

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import snag

pub type Frame {
  Frame(
    filename: String,
    rotated: Bool,
    trimmed: Bool,
    /// Untrimmed source size (libGDX `orig`), as `#(w, h)`.
    source_size: #(Int, Int),
    /// Trimmed sprite placement within the source frame as `#(x, y, w, h)`.
    /// libGDX measures `offset` from the BOTTOM-left of the source frame while
    /// Phaser's `spriteSourceSize.y` is from the TOP-left, so `y` is flipped.
    sprite_source: #(Int, Int, Int, Int),
    /// Region rect within the page, as `#(x, y, w, h)`.
    region: #(Int, Int, Int, Int),
  )
}

pub type Page {
  Page(image: String, format: String, size: #(Int, Int), frames: List(Frame))
}

pub fn parse(text: String) -> snag.Result(List(Page)) {
  text
  |> string.split("\n")
  |> list.map(string.trim_end)
  |> parse_pages([])
}

fn parse_pages(
  lines: List(String),
  pages: List(Page),
) -> snag.Result(List(Page)) {
  case lines {
    [] -> Ok(list.reverse(pages))
    ["", ..rest] -> parse_pages(rest, pages)
    [image_line, ..rest] ->
      case build_page(image_line, rest) {
        Ok(#(page, rest)) -> parse_pages(rest, [page, ..pages])
        Error(e) -> Error(e)
      }
  }
}

/// Consume page-level key/value lines, keeping `size` and `format`.
fn parse_header(
  lines: List(String),
) -> Result(#(#(Int, Int), String, List(String)), snag.Snag) {
  parse_header_helper(lines, option.None, option.None)
}

fn parse_header_helper(
  lines: List(String),
  size: option.Option(#(Int, Int)),
  format: option.Option(String),
) -> Result(#(#(Int, Int), String, List(String)), snag.Snag) {
  case lines {
    [] -> parse_header_output(size, format, [])
    ["", ..rest] -> parse_header_output(size, format, rest)
    [line, ..rest] ->
      case string.trim(line) {
        "size:" <> value ->
          case parse_pair(value) {
            Error(e) -> Error(e)
            Ok(size) -> parse_header_helper(rest, option.Some(size), format)
          }
        "format:" <> value ->
          parse_header_helper(rest, size, option.Some(string.trim(value)))
        "filter:" <> _ | "repeat:" <> _ | "pma:" <> _ ->
          parse_header_helper(rest, size, format)
        _ -> parse_header_output(size, format, lines)
      }
  }
}

fn parse_header_output(
  size: option.Option(#(Int, Int)),
  format: option.Option(String),
  lines: List(String),
) {
  case size, format {
    option.Some(size), option.Some(format) -> Ok(#(size, format, lines))
    option.Some(_), option.None -> snag.error("missing `format` in page header")
    option.None, option.Some(_) -> snag.error("missing `size` in page header")
    option.None, option.None ->
      snag.error("missing `size` and `format` in page header")
  }
}

/// Consume regions until the next page (blank line) or EOF.
fn parse_regions(
  lines: List(String),
  frames: List(Frame),
) -> snag.Result(#(List(Frame), List(String))) {
  case lines {
    [] -> Ok(#(frames, []))
    ["", ..] -> Ok(#(frames, lines))
    [name_line, ..rest] -> {
      let filename = string.trim(name_line)
      let #(props, rest) = parse_props(rest, dict.new())
      let frame_result = build_frame(filename, props)
      case frame_result {
        Error(e) -> Error(e)
        Ok(frame) -> parse_regions(rest, [frame, ..frames])
      }
    }
  }
}

fn build_page(image_line: String, rest: List(String)) {
  use #(size, format, rest) <- result.try(parse_header(rest))
  use #(frames, rest) <- result.try(parse_regions(rest, []))
  Ok(#(
    Page(
      image: string.trim(image_line),
      format:,
      size:,
      frames: list.reverse(frames),
    ),
    rest,
  ))
}

/// Consume the indented `key: value` lines belonging to one region.
fn parse_props(
  lines: List(String),
  props: Dict(String, String),
) -> #(Dict(String, String), List(String)) {
  case lines {
    [] -> #(props, [])
    [line, ..rest] -> {
      let indented =
        string.starts_with(line, " ") || string.starts_with(line, "\t")
      case indented, string.split_once(line, ":") {
        False, _ | _, Error(_) -> #(props, lines)
        True, Ok(#(key, value)) ->
          parse_props(
            rest,
            dict.insert(props, string.trim(key), string.trim(value)),
          )
      }
    }
  }
}

fn build_frame(
  filename: String,
  props: Dict(String, String),
) -> snag.Result(Frame) {
  use #(frame_x, frame_y) <- result.try(require_pair(props, "xy", filename))
  use #(frame_w, frame_h) <- result.try(require_pair(props, "size", filename))
  use #(orig_w, orig_h) <- result.try(optional_pair(
    props,
    "orig",
    #(frame_w, frame_h),
    filename,
  ))
  use #(offset_x, offset_y) <- result.try(optional_pair(
    props,
    "offset",
    #(0, 0),
    filename,
  ))

  let rotated =
    dict.get(props, "rotate")
    |> result.map(string.trim)
    |> result.unwrap("false")
    == "true"

  let trimmed =
    orig_w != frame_w || orig_h != frame_h || offset_x != 0 || offset_y != 0

  Ok(
    Frame(
      filename:,
      rotated:,
      trimmed:,
      source_size: #(orig_w, orig_h),
      sprite_source: #(offset_x, orig_h - offset_y - frame_h, frame_w, frame_h),
      region: #(frame_x, frame_y, frame_w, frame_h),
    ),
  )
}

fn require_pair(
  props: Dict(String, String),
  key: String,
  filename: String,
) -> snag.Result(#(Int, Int)) {
  case dict.get(props, key) {
    Ok(value) -> parse_pair(value)
    Error(Nil) -> snag.error("missing `" <> key <> "`")
  }
  |> snag.context("region `" <> filename <> "`")
}

fn optional_pair(
  props: Dict(String, String),
  key: String,
  default: #(Int, Int),
  filename: String,
) -> snag.Result(#(Int, Int)) {
  case dict.get(props, key) {
    Ok(value) ->
      parse_pair(value) |> snag.context("region `" <> filename <> "`")
    Error(Nil) -> Ok(default)
  }
}

fn parse_pair(value: String) -> snag.Result(#(Int, Int)) {
  let parts =
    value
    |> string.split(",")
    |> list.map(string.trim)
    |> list.map(int.parse)

  case parts {
    [Ok(first), Ok(second)] -> Ok(#(first, second))
    _ -> snag.error("expected a `X, Y` number pair, got `" <> value <> "`")
  }
}
