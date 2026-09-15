//// Loader for `packs.toml` - the single input file that configures a pack
//// run: the TexturePacker jar, concurrency, the atlas registry, and each
//// atlas's libGDX settings and scale variants.
////
//// Schema:
////
//// ```toml
//// jar = "path/to/texturepacker.jar"  # required; relative paths resolve
////                                    # against the config file's directory.
//// concurrency = 8                    # optional, default 8
////
//// [[atlases]]
//// name = "default-resources"         # required
//// source_dir = "images/default"      # required, the source image directory
//// target_dir = "textures"            # required, output root for this atlas
////
//// [atlases.gdx_settings]             # optional; each key falls back to the
//// max_width = 4096                   # matching `packer/settings` default
////
//// [atlases.variants.1x]              # optional; absent = a single pack at
//// factor = 0.3472                    # factor 1.0 straight into target_dir
//// ```
////
//// Unknown keys are ignored.

import filepath
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import internal/number_utils
import internal/path_utils
import internal/tom_utils
import pack_config.{type Settings, Settings}
import simplifile
import tom.{type Toml}

pub type Atlas {
  Spec(
    name: String,
    /// Path to the atlas's source image directory.
    source_dir: String,
    /// Output root for this atlas.
    target_dir: String,
    /// Output variants: the atlas is packed once per variant at that
    /// variant's scale factor. Empty means pack once at factor 1.0,
    /// writing directly into `target_dir`.
    variants: List(Variant),
    /// libGDX TexturePacker settings for this atlas.
    gdx_settings: Settings,
  )
}

/// One output variant: a single named scale pass.
///
/// - `name` becomes a subdirectory of `target_dir` (e.g. `"1x"`).
/// - `scale_factor` is the downscale factor forwarded to libGDX
///   TexturePacker.
pub type Variant {
  Variant(name: String, scale_factor: Float)
}

pub type Config {
  Config(jar: String, concurrency: Int, atlases: List(Atlas))
}

pub type ParseError {
  InvalidPath(String)
  InvalidNumber(tom.Number)
  InvalidToml(tom.ParseError)
  GetError(tom.GetError)
  FileError(simplifile.FileError)
}

const default_max_job_count = 8

fn get_variant_entry(entry: #(String, Toml)) -> Result(Variant, ParseError) {
  let #(name, toml) = entry
  use vt <- result.try(
    tom.as_table(toml)
    |> result.map_error(GetError),
  )

  use factor <- result.try(
    tom.get_number(vt, ["factor"])
    |> result.map_error(GetError),
  )

  use f_factor <- result.try(
    number_utils.to_finite_float(factor)
    |> result.map_error(InvalidNumber),
  )

  Ok(Variant(name:, scale_factor: f_factor))
}

fn get_gdx_settings_helper(
  table: Dict(String, Toml),
) -> Result(Settings, tom.GetError) {
  use pot <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["pot"]),
    pack_config.default_pot,
  ))

  use multiple_of_four <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["multiple_of_four"]),
    pack_config.default_multiple_of_four,
  ))

  use padding_x <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["padding_x"]),
    pack_config.default_padding_x,
  ))

  use padding_y <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["padding_y"]),
    pack_config.default_padding_y,
  ))

  use edge_padding <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["edge_padding"]),
    pack_config.default_edge_padding,
  ))

  use duplicate_padding <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["duplicate_padding"]),
    pack_config.default_duplicate_padding,
  ))

  use rotation <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["rotation"]),
    pack_config.default_rotation,
  ))

  use min_width <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["min_width"]),
    pack_config.default_min_width,
  ))

  use min_height <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["min_height"]),
    pack_config.default_min_height,
  ))

  use max_width <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["max_width"]),
    pack_config.default_max_width,
  ))

  use max_height <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["max_height"]),
    pack_config.default_max_height,
  ))

  use square <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["square"]),
    pack_config.default_square,
  ))

  use strip_whitespace_x <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["strip_whitespace_x"]),
    pack_config.default_strip_whitespace_x,
  ))

  use strip_whitespace_y <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["strip_whitespace_y"]),
    pack_config.default_strip_whitespace_y,
  ))

  use alpha_threshold <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["alpha_threshold"]),
    pack_config.default_alpha_threshold,
  ))

  use filter_min <- result.try(tom_utils.recover_from_not_found(
    tom.get_string(table, ["filter_min"]),
    pack_config.default_filter_min,
  ))

  use filter_mag <- result.try(tom_utils.recover_from_not_found(
    tom.get_string(table, ["filter_mag"]),
    pack_config.default_filter_mag,
  ))

  use wrap_x <- result.try(tom_utils.recover_from_not_found(
    tom.get_string(table, ["wrap_x"]),
    pack_config.default_wrap_x,
  ))

  use wrap_y <- result.try(tom_utils.recover_from_not_found(
    tom.get_string(table, ["wrap_y"]),
    pack_config.default_wrap_y,
  ))

  use format <- result.try(tom_utils.recover_from_not_found(
    tom.get_string(table, ["format"]),
    pack_config.default_format,
  ))

  use alias <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["alias"]),
    pack_config.default_alias,
  ))

  use ignore_blank_images <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["ignore_blank_images"]),
    pack_config.default_ignore_blank_images,
  ))

  use fast <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["fast"]),
    pack_config.default_fast,
  ))

  use debug <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["debug"]),
    pack_config.default_debug,
  ))

  use silent <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["silent"]),
    pack_config.default_silent,
  ))

  use combine_subdirectories <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["combine_subdirectories"]),
    pack_config.default_combine_subdirectories,
  ))

  use flatten_paths <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["flatten_paths"]),
    pack_config.default_flatten_paths,
  ))

  use premultiply_alpha <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["premultiply_alpha"]),
    pack_config.default_premultiply_alpha,
  ))

  use use_indexes <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["use_indexes"]),
    pack_config.default_use_indexes,
  ))

  use bleed <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["bleed"]),
    pack_config.default_bleed,
  ))

  use bleed_iterations <- result.try(tom_utils.recover_from_not_found(
    tom.get_int(table, ["bleed_iterations"]),
    pack_config.default_bleed_iterations,
  ))

  use limit_memory <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["limit_memory"]),
    pack_config.default_limit_memory,
  ))

  use grid <- result.try(tom_utils.recover_from_not_found(
    tom.get_bool(table, ["grid"]),
    pack_config.default_grid,
  ))

  use scale_resampling <- result.try(tom_utils.recover_from_not_found(
    tom.get_string(table, ["scale_resampling"]),
    pack_config.default_scale_resampling,
  ))

  Ok(Settings(
    pot:,
    multiple_of_four:,
    padding_x:,
    padding_y:,
    edge_padding:,
    duplicate_padding:,
    rotation:,
    min_width:,
    min_height:,
    max_width:,
    max_height:,
    square:,
    strip_whitespace_x:,
    strip_whitespace_y:,
    alpha_threshold:,
    filter_min:,
    filter_mag:,
    wrap_x:,
    wrap_y:,
    format:,
    alias:,
    ignore_blank_images:,
    fast:,
    debug:,
    silent:,
    combine_subdirectories:,
    flatten_paths:,
    premultiply_alpha:,
    use_indexes:,
    bleed:,
    bleed_iterations:,
    limit_memory:,
    grid:,
    scale_resampling:,
  ))
}

fn get_gdx_settings(table: Dict(String, Toml)) -> Result(Settings, ParseError) {
  case tom.get_table(table, ["gdx_settings"]) {
    Error(tom.NotFound(_)) -> Ok(pack_config.default())
    Error(error) -> Error(GetError(error))
    Ok(settings_table) ->
      get_gdx_settings_helper(settings_table)
      |> result.map_error(GetError)
  }
}

fn get_atlas(item: Toml, base_dir: String) -> Result(Atlas, ParseError) {
  use table <- result.try(
    tom.as_table(item)
    |> result.map_error(GetError),
  )

  use name <- result.try(
    tom.get_string(table, ["name"])
    |> result.map_error(GetError),
  )

  use source_dir_path <- result.try(
    tom.get_string(table, ["source_dir"])
    |> result.map_error(GetError),
  )

  use source_dir <- result.try(
    path_utils.resolve(base_dir, source_dir_path)
    |> result.map_error(InvalidPath),
  )

  use target_dir_path <- result.try(
    tom.get_string(table, ["target_dir"])
    |> result.map_error(GetError),
  )

  use target_dir <- result.try(
    path_utils.resolve(base_dir, target_dir_path)
    |> result.map_error(InvalidPath),
  )

  use variants <- result.try(case tom.get_table(table, ["variants"]) {
    Error(tom.NotFound(_)) -> Ok([])
    Error(error) -> Error(GetError(error))
    Ok(variants_table) ->
      variants_table
      |> dict.to_list
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.try_map(get_variant_entry)
  })

  use gdx_settings <- result.try(get_gdx_settings(table))

  Ok(Spec(name:, source_dir:, target_dir:, variants:, gdx_settings:))
}

fn get_atlases(
  doc: Dict(String, Toml),
  base_dir: String,
) -> Result(List(Atlas), ParseError) {
  use items <- result.try(
    tom.get_array(doc, ["atlases"])
    |> result.map_error(GetError),
  )

  use atlases <- result.try(list.try_map(items, get_atlas(_, base_dir)))

  Ok(atlases)
}

/// Parse a config document. Relative `jar` and per-atlas
/// `source_dir`/`target_dir` paths are resolved against `base_dir` (the
/// directory the config file sits in).
pub fn parse_config(
  text: String,
  base_dir base_dir: String,
) -> Result(Config, ParseError) {
  use doc <- result.try(
    tom.parse(text)
    |> result.map_error(InvalidToml),
  )

  use jar_path <- result.try(
    tom.get_string(doc, ["jar"])
    |> result.map_error(GetError),
  )

  use jar <- result.try(
    path_utils.resolve(base_dir, jar_path)
    |> result.map_error(InvalidPath),
  )

  use concurrency <- result.try(case tom.get_int(doc, ["concurrency"]) {
    Ok(value) -> Ok(value)
    Error(tom.NotFound(_)) -> Ok(default_max_job_count)
    Error(error) -> Error(GetError(error))
  })

  use atlases <- result.try(get_atlases(doc, base_dir))

  Ok(Config(jar:, concurrency:, atlases:))
}

/// Read and parse a config file, resolving its relative paths against the
/// directory the file sits in.
pub fn load_config(path: String) -> Result(Config, ParseError) {
  simplifile.read(path)
  |> result.map_error(FileError)
  |> result.try(parse_config(_, base_dir: filepath.directory_name(path)))
}

pub fn describe_parse_error(error: ParseError) -> String {
  case error {
    InvalidPath(path) -> "invalid path: " <> path
    InvalidNumber(number) ->
      "invalid number: " <> number_utils.tom_number_to_string(number)
    InvalidToml(tom.Unexpected(got, expected)) ->
      "invalid TOML: expected " <> expected <> ", got " <> got
    InvalidToml(tom.KeyAlreadyInUse(path)) ->
      "invalid TOML: key `" <> string.join(path, ".") <> "` used twice"
    GetError(tom.NotFound(path)) ->
      "missing key `" <> string.join(path, ".") <> "`"
    GetError(tom.WrongType(path, expected, got)) ->
      "key `"
      <> string.join(path, ".")
      <> "` should be of type "
      <> expected
      <> ", got "
      <> got
    FileError(error) -> "file error: " <> simplifile.describe_error(error)
  }
}
