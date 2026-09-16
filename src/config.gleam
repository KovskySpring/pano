import filepath
import gleam/dict.{type Dict}
import gleam/int
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
  /// The Atlas config
  ///
  /// Note: `target_dir` is the root output directory for this atlas; each variant will
  /// be packed into a subdirectory of this directory, named after the variant. If
  /// `variants` is empty, the atlas will be packed directly into `target_dir`.
  ///
  /// `timeout` is in milliseconds
  Spec(
    name: String,
    source_dir: String,
    target_dir: String,
    variants: List(Variant),
    gdx_settings: Settings,
    timeout: Int,
  )
}

pub type Variant {
  Variant(
    name: String,
    scale_factor: Float,
    gdx_settings: Settings,
    timeout: Int,
  )
}

pub type Config {
  Config(
    jar: String,
    concurrency: Int,
    atlases: List(Atlas),
    gdx_settings: Settings,
    timeout: Int,
  )
}

pub type ParseError {
  InvalidPath(String)
  InvalidNumber(tom.Number)
  InvalidTimeout(Int)
  InvalidToml(tom.ParseError)
  GetError(tom.GetError)
  FileError(simplifile.FileError)
}

const default_max_job_count = 8

const default_timeout = 30_000

fn get_timeout(
  table: Dict(String, Toml),
  base: Int,
) -> Result(Int, ParseError) {
  use timeout <- result.try(
    tom.get_int(table, ["timeout"])
    |> tom_utils.with_fallback(base)
    |> result.map_error(GetError),
  )

  case timeout > 0 {
    True -> Ok(timeout)
    False -> Error(InvalidTimeout(timeout))
  }
}

fn get_variant_entry(
  entry: #(String, Toml),
  atlas_settings: Settings,
  atlas_timeout: Int,
) -> Result(Variant, ParseError) {
  let #(name, toml) = entry
  use vt <- result.try(
    tom.as_table(toml)
    |> result.map_error(GetError),
  )

  use factor <- result.try(
    tom.get_number(vt, ["scale_factor"])
    |> result.map_error(GetError),
  )

  use f_factor <- result.try(
    number_utils.to_finite_float(factor)
    |> result.map_error(InvalidNumber),
  )

  use gdx_settings <- result.try(get_gdx_settings(vt, atlas_settings))

  use timeout <- result.try(get_timeout(vt, atlas_timeout))

  Ok(Variant(name:, scale_factor: f_factor, gdx_settings:, timeout:))
}

fn get_gdx_settings_helper(
  table: Dict(String, Toml),
  base: Settings,
) -> Result(Settings, tom.GetError) {
  use pot <- result.try(
    tom.get_bool(table, ["pot"])
    |> tom_utils.with_fallback(base.pot),
  )

  use multiple_of_four <- result.try(
    tom.get_bool(table, ["multiple_of_four"])
    |> tom_utils.with_fallback(base.multiple_of_four),
  )

  use padding_x <- result.try(
    tom.get_int(table, ["padding_x"])
    |> tom_utils.with_fallback(base.padding_x),
  )

  use padding_y <- result.try(
    tom.get_int(table, ["padding_y"])
    |> tom_utils.with_fallback(base.padding_y),
  )

  use edge_padding <- result.try(
    tom.get_bool(table, ["edge_padding"])
    |> tom_utils.with_fallback(base.edge_padding),
  )

  use duplicate_padding <- result.try(
    tom.get_bool(table, ["duplicate_padding"])
    |> tom_utils.with_fallback(base.duplicate_padding),
  )

  use rotation <- result.try(
    tom.get_bool(table, ["rotation"])
    |> tom_utils.with_fallback(base.rotation),
  )

  use min_width <- result.try(
    tom.get_int(table, ["min_width"])
    |> tom_utils.with_fallback(base.min_width),
  )

  use min_height <- result.try(
    tom.get_int(table, ["min_height"])
    |> tom_utils.with_fallback(base.min_height),
  )

  use max_width <- result.try(
    tom.get_int(table, ["max_width"])
    |> tom_utils.with_fallback(base.max_width),
  )

  use max_height <- result.try(
    tom.get_int(table, ["max_height"])
    |> tom_utils.with_fallback(base.max_height),
  )

  use square <- result.try(
    tom.get_bool(table, ["square"])
    |> tom_utils.with_fallback(base.square),
  )

  use strip_whitespace_x <- result.try(
    tom.get_bool(table, ["strip_whitespace_x"])
    |> tom_utils.with_fallback(base.strip_whitespace_x),
  )

  use strip_whitespace_y <- result.try(
    tom.get_bool(table, ["strip_whitespace_y"])
    |> tom_utils.with_fallback(base.strip_whitespace_y),
  )

  use alpha_threshold <- result.try(
    tom.get_int(table, ["alpha_threshold"])
    |> tom_utils.with_fallback(base.alpha_threshold),
  )

  use filter_min <- result.try(
    tom.get_string(table, ["filter_min"])
    |> tom_utils.with_fallback(base.filter_min),
  )

  use filter_mag <- result.try(
    tom.get_string(table, ["filter_mag"])
    |> tom_utils.with_fallback(base.filter_mag),
  )

  use wrap_x <- result.try(
    tom.get_string(table, ["wrap_x"])
    |> tom_utils.with_fallback(base.wrap_x),
  )

  use wrap_y <- result.try(
    tom.get_string(table, ["wrap_y"])
    |> tom_utils.with_fallback(base.wrap_y),
  )

  use format <- result.try(
    tom.get_string(table, ["format"])
    |> tom_utils.with_fallback(base.format),
  )

  use alias <- result.try(
    tom.get_bool(table, ["alias"])
    |> tom_utils.with_fallback(base.alias),
  )

  use ignore_blank_images <- result.try(
    tom.get_bool(table, ["ignore_blank_images"])
    |> tom_utils.with_fallback(base.ignore_blank_images),
  )

  use fast <- result.try(
    tom.get_bool(table, ["fast"])
    |> tom_utils.with_fallback(base.fast),
  )

  use debug <- result.try(
    tom.get_bool(table, ["debug"])
    |> tom_utils.with_fallback(base.debug),
  )

  use silent <- result.try(
    tom.get_bool(table, ["silent"])
    |> tom_utils.with_fallback(base.silent),
  )

  use combine_subdirectories <- result.try(
    tom.get_bool(table, ["combine_subdirectories"])
    |> tom_utils.with_fallback(base.combine_subdirectories),
  )

  use flatten_paths <- result.try(
    tom.get_bool(table, ["flatten_paths"])
    |> tom_utils.with_fallback(base.flatten_paths),
  )

  use premultiply_alpha <- result.try(
    tom.get_bool(table, ["premultiply_alpha"])
    |> tom_utils.with_fallback(base.premultiply_alpha),
  )

  use use_indexes <- result.try(
    tom.get_bool(table, ["use_indexes"])
    |> tom_utils.with_fallback(base.use_indexes),
  )

  use bleed <- result.try(
    tom.get_bool(table, ["bleed"])
    |> tom_utils.with_fallback(base.bleed),
  )

  use bleed_iterations <- result.try(
    tom.get_int(table, ["bleed_iterations"])
    |> tom_utils.with_fallback(base.bleed_iterations),
  )

  use limit_memory <- result.try(
    tom.get_bool(table, ["limit_memory"])
    |> tom_utils.with_fallback(base.limit_memory),
  )

  use grid <- result.try(
    tom.get_bool(table, ["grid"])
    |> tom_utils.with_fallback(base.grid),
  )

  use scale_resampling <- result.try(
    tom.get_string(table, ["scale_resampling"])
    |> tom_utils.with_fallback(base.scale_resampling),
  )

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

fn get_gdx_settings(
  table: Dict(String, Toml),
  base: Settings,
) -> Result(Settings, ParseError) {
  get_gdx_settings_helper(table, base)
  |> result.map_error(GetError)
}

fn get_atlas(
  entry: #(String, Toml),
  base_dir: String,
  root_settings: Settings,
  root_timeout: Int,
) -> Result(Atlas, ParseError) {
  let #(name, item) = entry
  use table <- result.try(
    tom.as_table(item)
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

  use gdx_settings <- result.try(get_gdx_settings(table, root_settings))

  use timeout <- result.try(get_timeout(table, root_timeout))

  use variants <- result.try(case tom.get_table(table, ["variants"]) {
    Error(tom.NotFound(_)) -> Ok([])
    Error(error) -> Error(GetError(error))
    Ok(variants_table) ->
      variants_table
      |> dict.to_list
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.try_map(get_variant_entry(_, gdx_settings, timeout))
  })

  Ok(Spec(name:, source_dir:, target_dir:, variants:, gdx_settings:, timeout:))
}

fn get_atlases(
  doc: Dict(String, Toml),
  base_dir: String,
  root_settings: Settings,
  root_timeout: Int,
) -> Result(List(Atlas), ParseError) {
  use items <- result.try(
    tom.get_table(doc, ["atlases"])
    |> result.map_error(GetError),
  )

  use atlases <- result.try(
    items
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.try_map(get_atlas(_, base_dir, root_settings, root_timeout)),
  )

  Ok(atlases)
}

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

  use gdx_settings <- result.try(get_gdx_settings(doc, pack_config.default()))

  use timeout <- result.try(get_timeout(doc, default_timeout))

  use atlases <- result.try(get_atlases(doc, base_dir, gdx_settings, timeout))

  Ok(Config(jar:, concurrency:, atlases:, gdx_settings:, timeout:))
}

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
    InvalidTimeout(milliseconds) ->
      "invalid timeout: "
      <> int.to_string(milliseconds)
      <> "ms, must be at least 1ms"
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
