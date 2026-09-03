//// TOML deserialiser for `PngOptions` - parses the fields of a single
//// `compression` table entry (from `packs.toml`) into a `PngOptions` record.
////
////
////   `depth`       → `bitdepth`
////   `quality`     → `Q`
////   `strip`       → `keep`       (`true` → `["none"]`, shorthand for `keep`)
////   `dither`      → `dither`     (accepts an int or float literal)
////   `compression` → `compression`
////   `interlace`   → `interlace`
////   `filter`      → `filter`     (array of flag names)
////   `palette`     → `palette`
////   `effort`      → `effort`
////   `keep`        → `keep`       (array of flag names)
////   `background`  → `background` (array of numbers)
////   `page_height` → `page-height`
////   `profile`     → `profile`
////
//// `quality`, `dither`, `compression` and `strip` carry pano defaults. The
//// rest are omitted when absent, leaving vips its own default.
////
//// `palette` and `filter` are derived from `depth` unless set explicitly:
//// `depth <= 8` selects palette quantisation (libimagequant), otherwise all
//// row filters are used to give zlib the best chance at compression.

import filepath
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import optimizer/vips/png/options.{type PngOptions, PngOptions}
import snag
import tom.{type Toml}

/// Parse a single `compression` TOML table into a `PngOptions` record.
/// `base_dir` resolves a `profile` given as a path; see `get_profile`.
pub fn from_toml(
  table: Dict(String, Toml),
  base_dir base_dir: String,
) -> snag.Result(PngOptions) {
  use depth <- result.try(get_optional_int(table, "depth"))
  use quality <- result.try(optional(tom.get_int(table, ["quality"]), 100))
  use dither <- result.try(get_dither(table))
  use compression <- result.try(optional(tom.get_int(table, ["compression"]), 9))
  use keep <- result.try(get_keep(table))
  use interlace <- result.try(get_optional_bool(table, "interlace"))
  use palette <- result.try(get_optional_bool(table, "palette"))
  use effort <- result.try(get_optional_int(table, "effort"))
  use page_height <- result.try(get_optional_int(table, "page_height"))
  use background <- result.try(get_background(table))
  use profile <- result.try(get_profile(table, base_dir))
  use filter <- result.try(get_flags(
    table,
    "filter",
    options.filter_from_name,
    options.filter_names,
  ))

  Ok(PngOptions(
    bitdepth: depth,
    q: Some(quality),
    dither: Some(dither),
    compression: Some(compression),
    keep:,
    interlace:,
    effort:,
    page_height:,
    background:,
    profile:,
    palette: derive_palette(palette, depth),
    filter: derive_filter(filter, depth),
  ))
}

/// `palette` defaults to on for a depth vips can quantise to, and is left to
/// vips otherwise. An explicit key always wins.
fn derive_palette(explicit: Option(Bool), depth: Option(Int)) -> Option(Bool) {
  case explicit {
    Some(_) -> explicit
    None ->
      case is_palette_depth(depth) {
        True -> Some(True)
        False -> None
      }
  }
}

/// Without palette quantisation, use every row filter so zlib has the best
/// chance at compression. An explicit key always wins, including an empty
/// array, which omits the option.
fn derive_filter(
  explicit: Option(List(options.PngFilter)),
  depth: Option(Int),
) -> Option(List(options.PngFilter)) {
  case explicit {
    Some(_) -> explicit
    None ->
      case is_palette_depth(depth) {
        True -> None
        False -> Some([options.FilterAll])
      }
  }
}

fn is_palette_depth(depth: Option(Int)) -> Bool {
  case depth {
    Some(d) -> d <= 8
    None -> False
  }
}

/// `strip` is a shorthand for the common `keep = ["none"]` case. Accepting
/// both for the same vips option would make precedence guesswork, so it is
/// rejected instead.
fn get_keep(
  table: Dict(String, Toml),
) -> snag.Result(Option(List(options.Keep))) {
  let has_strip = dict.has_key(table, "strip")
  let has_keep = dict.has_key(table, "keep")

  case has_strip, has_keep {
    True, True ->
      snag.error(
        "`strip` and `keep` both set the same vips option; use one or the other",
      )
    False, True ->
      get_flags(table, "keep", options.keep_from_name, options.keep_names)
    _, False -> {
      use strip <- result.try(optional(tom.get_bool(table, ["strip"]), True))
      case strip {
        True -> Ok(Some([options.KeepNone]))
        False -> Ok(None)
      }
    }
  }
}

/// Read an array of vips flag names, e.g. `keep = ["exif", "icc"]`.
fn get_flags(
  table: Dict(String, Toml),
  key: String,
  parse: fn(String) -> Result(a, Nil),
  valid: List(String),
) -> snag.Result(Option(List(a))) {
  case tom.get_array(table, [key]) {
    Error(tom.NotFound(_)) -> Ok(None)
    Error(error) -> Error(get_error_to_snag(error))
    Ok(items) -> {
      use names <- result.try(
        list.try_map(items, tom.as_string)
        |> result.map_error(get_error_to_snag),
      )
      use parsed <- result.try(
        list.try_map(names, fn(name) {
          parse(name)
          |> result.replace_error(snag.new(
            "`"
            <> key
            <> "` has no flag `"
            <> name
            <> "`, expected one of: "
            <> string.join(valid, ", "),
          ))
        }),
      )
      Ok(Some(parsed))
    }
  }
}

/// `background` is a vips array of doubles, e.g. `background = [255, 255, 255]`.
/// Ints and floats both work, as with `dither`.
fn get_background(
  table: Dict(String, Toml),
) -> snag.Result(Option(List(Float))) {
  case tom.get_array(table, ["background"]) {
    Error(tom.NotFound(_)) -> Ok(None)
    Error(error) -> Error(get_error_to_snag(error))
    Ok(items) -> {
      use numbers <- result.try(
        list.try_map(items, tom.as_number)
        |> result.map_error(get_error_to_snag),
      )
      use components <- result.try(
        list.try_map(numbers, to_float(_, "background")),
      )
      Ok(Some(components))
    }
  }
}

/// An ICC profile is either a built-in name (`srgb`, `p3`, `cmyk`) or a path
/// to a profile file, which resolves against the config file's directory like
/// every other path. Resolving a bare name would break the built-in lookup.
fn get_profile(
  table: Dict(String, Toml),
  base_dir: String,
) -> snag.Result(Option(String)) {
  case tom.get_string(table, ["profile"]) {
    Error(tom.NotFound(_)) -> Ok(None)
    Error(error) -> Error(get_error_to_snag(error))
    Ok(profile) ->
      case string.contains(profile, "/") && base_dir != "" {
        True -> Ok(Some(filepath.join(base_dir, profile)))
        False -> Ok(Some(profile))
      }
  }
}

fn get_optional_int(
  table: Dict(String, Toml),
  key: String,
) -> snag.Result(Option(Int)) {
  case tom.get_int(table, [key]) {
    Ok(value) -> Ok(Some(value))
    Error(tom.NotFound(_)) -> Ok(None)
    Error(error) -> Error(get_error_to_snag(error))
  }
}

fn get_optional_bool(
  table: Dict(String, Toml),
  key: String,
) -> snag.Result(Option(Bool)) {
  case tom.get_bool(table, [key]) {
    Ok(value) -> Ok(Some(value))
    Error(tom.NotFound(_)) -> Ok(None)
    Error(error) -> Error(get_error_to_snag(error))
  }
}

/// `dither` accepts either an int or float TOML literal (`1` or `1.0`).
fn get_dither(table: Dict(String, Toml)) -> snag.Result(Float) {
  case tom.get_number(table, ["dither"]) {
    Ok(number) -> to_float(number, "dither")
    Error(tom.NotFound(_)) -> Ok(1.0)
    Error(error) -> Error(get_error_to_snag(error))
  }
}

fn to_float(number: tom.Number, key: String) -> snag.Result(Float) {
  // ! tom parses float literals with accumulating arithmetic, so `0.3472`
  // ! arrives as the drifted double 0.34720000000000006. Rounding back to
  // ! 10 decimal places recovers the intended value exactly for any
  // ! human-authored factor.
  case number {
    tom.NumberFloat(value) -> Ok(float.to_precision(value, 10))
    tom.NumberInt(value) -> Ok(int.to_float(value))
    tom.NumberInfinity(_) | tom.NumberNan(_) ->
      snag.error("`" <> key <> "` must be a finite number")
  }
}

fn optional(outcome: Result(a, tom.GetError), default: a) -> snag.Result(a) {
  case outcome {
    Ok(value) -> Ok(value)
    Error(tom.NotFound(_)) -> Ok(default)
    Error(error) -> Error(get_error_to_snag(error))
  }
}

fn get_error_to_snag(error: tom.GetError) -> snag.Snag {
  case error {
    tom.NotFound(key) ->
      snag.new("missing key `" <> string.join(key, ".") <> "`")
    tom.WrongType(key, expected, got) ->
      snag.new(
        "key `"
        <> string.join(key, ".")
        <> "` should be of type "
        <> expected
        <> ", got "
        <> got,
      )
  }
}
