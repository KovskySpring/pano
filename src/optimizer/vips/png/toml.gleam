//// TOML deserialiser for `PngOptions` - parses the fields of a single
//// `compression` table entry (from `packs.toml`) into a `PngOptions` record.
////
//// Field mapping from TOML keys to `PngOptions` fields:
////
////   `depth`       → `bitdepth`   (forwarded verbatim to vips; not validated)
////   `quality`     → `q`
////   `dither`      → `dither`     (accepts an int or float literal)
////   `compression` → `compression`
////   `strip`       → `keep`       (`true` → `KeepNone`, `false` → `None`)
////
//// When `depth ≤ 8`, `palette = true` is set (libimagequant quantisation).
//// When `depth` is absent or `> 8`, `filter = all` is set instead.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import optimizer/vips/png/options.{type PngOptions, PngOptions}
import snag
import tom.{type Toml}

/// Parse a single `compression` TOML table into a `PngOptions` record.
/// Depths of 8 or less mean palette quantisation; otherwise use all
/// filters to give zlib the best chance at compression.
pub fn from_toml(table: Dict(String, Toml)) -> snag.Result(PngOptions) {
  use depth <- result.try(get_depth(table))
  use quality <- result.try(optional(tom.get_int(table, ["quality"]), 100))
  use dither <- result.try(get_dither(table))
  use compression <- result.try(optional(tom.get_int(table, ["compression"]), 9))
  use strip <- result.try(optional(tom.get_bool(table, ["strip"]), True))

  let keep = case strip {
    True -> Some(options.KeepNone)
    False -> None
  }

  let opts =
    PngOptions(
      ..options.none(),
      bitdepth: depth,
      q: Some(quality),
      dither: Some(dither),
      compression: Some(compression),
      keep:,
    )

  let opts = case depth {
    Some(d) if d <= 8 -> PngOptions(..opts, palette: Some(True))
    _ -> PngOptions(..opts, filter: Some(options.FilterAll))
  }

  Ok(opts)
}

fn get_depth(table: Dict(String, Toml)) -> snag.Result(Option(Int)) {
  case tom.get_int(table, ["depth"]) {
    Ok(depth) -> Ok(Some(depth))
    Error(tom.NotFound(_)) -> Ok(None)
    Error(error) -> Error(get_error_to_snag(error))
  }
}

/// `dither` accepts either an int or float TOML literal (`1` or `1.0`).
fn get_dither(table: Dict(String, Toml)) -> snag.Result(Float) {
  case tom.get_number(table, ["dither"]) {
    Ok(number) -> to_float(number)
    Error(tom.NotFound(_)) -> Ok(1.0)
    Error(error) -> Error(get_error_to_snag(error))
  }
}

fn to_float(number: tom.Number) -> snag.Result(Float) {
  // ! tom parses float literals with accumulating arithmetic, so `0.3472`
  // ! arrives as the drifted double 0.34720000000000006. Rounding back to
  // ! 10 decimal places recovers the intended value exactly for any
  // ! human-authored factor.
  case number {
    tom.NumberFloat(value) -> Ok(float.to_precision(value, 10))
    tom.NumberInt(value) -> Ok(int.to_float(value))
    tom.NumberInfinity(_) | tom.NumberNan(_) ->
      snag.error("`dither` must be a finite number")
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
