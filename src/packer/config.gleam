//// Loader for `packs.toml` - the single input file that configures a pack
//// run: tool paths, concurrency, scale variants, and the atlas registry
//// (previously hardcoded in `spec.gleam`).
////
//// Schema:
////
//// ```toml
//// jar = "path/to/texturepacker.jar"  # required; relative paths resolve
//// concurrency = 8                    # against the config file's directory
////                                    # (concurrency optional, default 8)
////
//// [[atlases]]
//// name = "default-resources"         # required
//// source_dir = "images/default"      # required, the source image directory
//// target_dir = "textures"            # required, output root for this atlas
//// [variants.1x]                       # optional; absent = single pack
////   factor = 0.3472                   # at 1.0 directly into target_dir
////                                     #
//// [variants.1x.compression.8bit]      # optional per variant; absent =
////   depth = 8                         # skip re-encoding; key = subdir
//// ```
////
//// Environment overrides (applied by `load`, kept for CI parity with the old
//// pipeline): `GDX_OUT_ROOT` replaces every atlas's `target_dir`,
//// `GDX_CONCURRENCY` replaces `concurrency`.

import envoy
import filepath
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import optimizer/spec.{Png} as _
import optimizer/vips/png/toml as png_toml
import packer/settings.{type Settings, Settings}
import packer/spec.{
  type Compression, type Spec, type Variant, Compression, Spec, Variant,
}
import simplifile
import snag
import tom.{type Toml}

pub type Config {
  Config(jar: String, concurrency: Int, atlases: List(Spec))
}

const default_concurrency = 8

/// Read and parse a config file, then apply the environment overrides.
pub fn load(path: String) -> snag.Result(Config) {
  simplifile.read(path)
  |> result.map_error(fn(error) {
    snag.new("could not read file: " <> simplifile.describe_error(error))
  })
  |> result.try(parse(_, base_dir: filepath.directory_name(path)))
  |> result.map(apply_env_overrides)
  |> snag.context("loading config " <> path)
}

/// Parse a config document. Relative `jar` and per-atlas
/// `source_dir`/`target_dir` paths are resolved against `base_dir` (the
/// directory the config file sits in).
pub fn parse(text: String, base_dir base_dir: String) -> snag.Result(Config) {
  use doc <- result.try(result.map_error(tom.parse(text), parse_error_to_snag))
  use jar <- result.try(get_path(doc, "jar", base_dir))
  use concurrency <- result.try(optional(
    tom.get_int(doc, ["concurrency"]),
    default_concurrency,
  ))
  use atlases <- result.try(get_atlases(doc, base_dir))
  Ok(Config(jar:, concurrency:, atlases:))
}

fn apply_env_overrides(config: Config) -> Config {
  let atlases = case envoy.get("GDX_OUT_ROOT") {
    Ok(target_dir) ->
      list.map(config.atlases, fn(atlas) { Spec(..atlas, target_dir:) })
    Error(Nil) -> config.atlases
  }

  let concurrency =
    envoy.get("GDX_CONCURRENCY")
    |> result.try(int.parse)
    |> result.unwrap(config.concurrency)

  Config(..config, atlases:, concurrency:)
}

fn get_path(
  doc: Dict(String, Toml),
  key: String,
  base_dir: String,
) -> snag.Result(String) {
  use path <- result.try(required(tom.get_string(doc, [key])))
  Ok(resolve(path, base_dir))
}

fn resolve(path: String, base_dir: String) -> String {
  case base_dir == "" || filepath.is_absolute(path) {
    True -> path
    False -> filepath.join(base_dir, path)
  }
}

fn get_variants(table: Dict(String, Toml)) -> snag.Result(List(Variant)) {
  case tom.get_table(table, ["variants"]) {
    Error(tom.NotFound(_)) -> Ok([])
    Error(error) -> Error(get_error_to_snag(error))
    Ok(variants_table) ->
      variants_table
      |> dict.to_list
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.try_map(get_variant_entry)
  }
}

fn get_variant_entry(entry: #(String, Toml)) -> snag.Result(Variant) {
  let #(name, toml) = entry
  let variant = {
    use vt <- result.try(required(tom.as_table(toml)))
    use factor <- result.try(required(tom.get_number(vt, ["factor"])))
    use f_factor <- result.try(to_float(factor))
    use compression <- result.try(get_compression(vt))
    Ok(Variant(name:, factor: f_factor, compression:))
  }
  snag.context(variant, "in variant `" <> name <> "`")
}

fn get_atlases(
  doc: Dict(String, Toml),
  base_dir: String,
) -> snag.Result(List(Spec)) {
  use items <- result.try(required(tom.get_array(doc, ["atlases"])))
  use atlases <- result.try(list.try_map(items, get_atlas(_, base_dir)))
  case atlases {
    [] -> snag.error("`atlases` must have at least one entry")
    _ -> Ok(atlases)
  }
}

/// Decode one `[[atlases]]` entry.
fn get_atlas(item: Toml, base_dir: String) -> snag.Result(Spec) {
  use table <- result.try(snag.context(
    required(tom.as_table(item)),
    "in an `atlases` entry",
  ))
  use name <- result.try(required(tom.get_string(table, ["name"])))
  use source_dir <- result.try(get_path(table, "source_dir", base_dir))
  use target_dir <- result.try(get_path(table, "target_dir", base_dir))
  use variants <- result.try(get_variants(table))
  use indexed <- result.try(optional(tom.get_bool(table, ["indexed"]), True))
  use gdx_settings <- result.try(get_gdx_settings(table))

  let spec =
    Ok(Spec(name:, source_dir:, target_dir:, variants:, indexed:, gdx_settings:))

  snag.context(spec, "in atlas `" <> name <> "`")
}

fn get_compression(
  table: Dict(String, Toml),
) -> snag.Result(List(Compression)) {
  case tom.get_table(table, ["compression"]) {
    Error(tom.NotFound(_)) -> Ok([])
    Error(error) -> Error(get_error_to_snag(error))
    Ok(compression_table) ->
      compression_table
      |> dict.to_list
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.try_map(get_compression_entry)
  }
}

fn get_compression_entry(entry: #(String, Toml)) -> snag.Result(Compression) {
  let #(name, toml) = entry
  let compression = {
    use ct <- result.try(required(tom.as_table(toml)))
    use png_opts <- result.try(png_toml.from_toml(ct))
    Ok(Compression(name:, format: Png(options: png_opts)))
  }
  snag.context(compression, "in compression `" <> name <> "`")
}

/// Optional per-atlas libGDX TexturePacker overrides - see
/// `packer/settings` for what each field does and its default.
fn get_gdx_settings(table: Dict(String, Toml)) -> snag.Result(Settings) {
  let default = settings.default()
  use pot <- result.try(optional(tom.get_bool(table, ["pot"]), default.pot))
  use padding_x <- result.try(optional(
    tom.get_int(table, ["padding_x"]),
    default.padding_x,
  ))
  use padding_y <- result.try(optional(
    tom.get_int(table, ["padding_y"]),
    default.padding_y,
  ))
  use edge_padding <- result.try(optional(
    tom.get_bool(table, ["edge_padding"]),
    default.edge_padding,
  ))
  use duplicate_padding <- result.try(optional(
    tom.get_bool(table, ["duplicate_padding"]),
    default.duplicate_padding,
  ))
  use rotation <- result.try(optional(
    tom.get_bool(table, ["rotation"]),
    default.rotation,
  ))
  use strip_whitespace_x <- result.try(optional(
    tom.get_bool(table, ["strip_whitespace_x"]),
    default.strip_whitespace_x,
  ))
  use strip_whitespace_y <- result.try(optional(
    tom.get_bool(table, ["strip_whitespace_y"]),
    default.strip_whitespace_y,
  ))
  use alpha_threshold <- result.try(optional(
    tom.get_int(table, ["alpha_threshold"]),
    default.alpha_threshold,
  ))
  use filter_min <- result.try(optional(
    tom.get_string(table, ["filter_min"]),
    default.filter_min,
  ))
  use filter_mag <- result.try(optional(
    tom.get_string(table, ["filter_mag"]),
    default.filter_mag,
  ))
  use format <- result.try(optional(
    tom.get_string(table, ["format"]),
    default.format,
  ))
  use max_width <- result.try(optional(
    tom.get_int(table, ["max_width"]),
    default.max_width,
  ))
  use max_height <- result.try(optional(
    tom.get_int(table, ["max_height"]),
    default.max_height,
  ))
  use combine_subdirectories <- result.try(optional(
    tom.get_bool(table, ["combine_subdirectories"]),
    default.combine_subdirectories,
  ))
  use flatten_paths <- result.try(optional(
    tom.get_bool(table, ["flatten_paths"]),
    default.flatten_paths,
  ))
  use use_indexes <- result.try(optional(
    tom.get_bool(table, ["use_indexes"]),
    default.use_indexes,
  ))
  use bleed <- result.try(optional(
    tom.get_bool(table, ["bleed"]),
    default.bleed,
  ))
  use scale_resampling <- result.try(optional(
    tom.get_string(table, ["scale_resampling"]),
    default.scale_resampling,
  ))

  Ok(Settings(
    pot:,
    padding_x:,
    padding_y:,
    edge_padding:,
    duplicate_padding:,
    rotation:,
    strip_whitespace_x:,
    strip_whitespace_y:,
    alpha_threshold:,
    filter_min:,
    filter_mag:,
    format:,
    max_width:,
    max_height:,
    combine_subdirectories:,
    flatten_paths:,
    use_indexes:,
    bleed:,
    scale_resampling:,
  ))
}

fn to_float(number: tom.Number) -> snag.Result(Float) {
  case number {
    // ! tom parses float literals with accumulating arithmetic, so `0.3472`
    // ! arrives as the drifted double 0.34720000000000006. Rounding back to
    // ! 10 decimal places recovers the intended value exactly for any
    // ! human-authored factor.
    tom.NumberFloat(value) -> Ok(float.to_precision(value, 10))
    tom.NumberInt(value) -> Ok(int.to_float(value))
    tom.NumberInfinity(_) | tom.NumberNan(_) ->
      snag.error("`factor` must be a finite number")
  }
}

fn required(outcome: Result(a, tom.GetError)) -> snag.Result(a) {
  result.map_error(outcome, get_error_to_snag)
}

/// Fall back to a default when the key is absent, but still fail loudly when
/// it is present with the wrong type.
fn optional(outcome: Result(a, tom.GetError), default: a) -> snag.Result(a) {
  case outcome {
    Ok(value) -> Ok(value)
    Error(tom.NotFound(_)) -> Ok(default)
    Error(error) -> Error(get_error_to_snag(error))
  }
}

fn get_error_to_snag(error: tom.GetError) -> snag.Snag {
  case error {
    tom.NotFound(key) -> snag.new("missing key `" <> key_path(key) <> "`")
    tom.WrongType(key, expected, got) ->
      snag.new(
        "key `"
        <> key_path(key)
        <> "` should be of type "
        <> expected
        <> ", got "
        <> got,
      )
  }
}

fn key_path(key: List(String)) -> String {
  string.join(key, ".")
}

fn parse_error_to_snag(error: tom.ParseError) -> snag.Snag {
  case error {
    tom.Unexpected(got, expected) ->
      snag.new("invalid TOML: expected " <> expected <> ", got " <> got)
    tom.KeyAlreadyInUse(key) ->
      snag.new("invalid TOML: key `" <> key_path(key) <> "` used twice")
  }
}
