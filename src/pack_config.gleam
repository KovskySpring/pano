//// libGDX TexturePacker settings for one pack pass. libGDX applies `scale` during
//// packing, so each scale variant is a separate pass with a single factor.
////
//// Every `TexturePacker.Settings` field is exposed except the ones pano's
//// pipeline depends on: `scale`/`scaleSuffix` (driven by variants),
//// `outputFormat`/`jpegQuality` (pages are PNG end to end),
//// `atlasExtension`/`legacyOutput`/`prettyPrint` (the `.atlas` parser reads the
//// legacy format at `<name>.atlas`) and `ignore` (skips the whole source
//// directory when set at the root).
////
//// `encode` writes the JSON that `pack` hands to the jar as its settings
//// file; each `default_*` constant is the fallback `packer/config` uses for
//// a key left out of `[atlases.gdx_settings]`.

import gleam/json

pub type Settings {
  Settings(
    pot: Bool,
    multiple_of_four: Bool,
    padding_x: Int,
    padding_y: Int,
    edge_padding: Bool,
    duplicate_padding: Bool,
    rotation: Bool,
    min_width: Int,
    min_height: Int,
    max_width: Int,
    max_height: Int,
    square: Bool,
    strip_whitespace_x: Bool,
    strip_whitespace_y: Bool,
    alpha_threshold: Int,
    filter_min: String,
    filter_mag: String,
    wrap_x: String,
    wrap_y: String,
    format: String,
    alias: Bool,
    ignore_blank_images: Bool,
    fast: Bool,
    debug: Bool,
    silent: Bool,
    combine_subdirectories: Bool,
    flatten_paths: Bool,
    premultiply_alpha: Bool,
    use_indexes: Bool,
    bleed: Bool,
    bleed_iterations: Int,
    limit_memory: Bool,
    grid: Bool,
    scale_resampling: String,
  )
}

pub const default_pot = False

pub const default_multiple_of_four = False

pub const default_padding_x = 2

pub const default_padding_y = 2

pub const default_edge_padding = True

pub const default_duplicate_padding = True

pub const default_rotation = False

pub const default_min_width = 16

pub const default_min_height = 16

pub const default_max_width = 2048

pub const default_max_height = 2048

pub const default_square = False

pub const default_strip_whitespace_x = True

pub const default_strip_whitespace_y = True

pub const default_alpha_threshold = 0

pub const default_filter_min = "Linear"

pub const default_filter_mag = "Linear"

pub const default_wrap_x = "ClampToEdge"

pub const default_wrap_y = "ClampToEdge"

pub const default_format = "RGBA8888"

pub const default_alias = True

pub const default_ignore_blank_images = True

pub const default_fast = False

pub const default_debug = False

pub const default_silent = False

pub const default_combine_subdirectories = True

pub const default_flatten_paths = False

pub const default_premultiply_alpha = False

pub const default_use_indexes = False

pub const default_bleed = True

pub const default_bleed_iterations = 2

pub const default_limit_memory = True

pub const default_grid = False

pub const default_scale_resampling = "bicubic"

pub fn default() -> Settings {
  Settings(
    pot: default_pot,
    multiple_of_four: default_multiple_of_four,
    padding_x: default_padding_x,
    padding_y: default_padding_y,
    edge_padding: default_edge_padding,
    duplicate_padding: default_duplicate_padding,
    rotation: default_rotation,
    min_width: default_min_width,
    min_height: default_min_height,
    max_width: default_max_width,
    max_height: default_max_height,
    square: default_square,
    strip_whitespace_x: default_strip_whitespace_x,
    strip_whitespace_y: default_strip_whitespace_y,
    alpha_threshold: default_alpha_threshold,
    filter_min: default_filter_min,
    filter_mag: default_filter_mag,
    wrap_x: default_wrap_x,
    wrap_y: default_wrap_y,
    format: default_format,
    alias: default_alias,
    ignore_blank_images: default_ignore_blank_images,
    fast: default_fast,
    debug: default_debug,
    silent: default_silent,
    combine_subdirectories: default_combine_subdirectories,
    flatten_paths: default_flatten_paths,
    premultiply_alpha: default_premultiply_alpha,
    use_indexes: default_use_indexes,
    bleed: default_bleed,
    bleed_iterations: default_bleed_iterations,
    limit_memory: default_limit_memory,
    grid: default_grid,
    scale_resampling: default_scale_resampling,
  )
}

pub fn encode(settings: Settings, scale scale: Float) -> String {
  json.to_string(
    json.object([
      #("pot", json.bool(settings.pot)),
      #("multipleOfFour", json.bool(settings.multiple_of_four)),
      #("paddingX", json.int(settings.padding_x)),
      #("paddingY", json.int(settings.padding_y)),
      #("edgePadding", json.bool(settings.edge_padding)),
      #("duplicatePadding", json.bool(settings.duplicate_padding)),
      #("rotation", json.bool(settings.rotation)),
      #("minWidth", json.int(settings.min_width)),
      #("minHeight", json.int(settings.min_height)),
      #("maxWidth", json.int(settings.max_width)),
      #("maxHeight", json.int(settings.max_height)),
      #("square", json.bool(settings.square)),
      #("stripWhitespaceX", json.bool(settings.strip_whitespace_x)),
      #("stripWhitespaceY", json.bool(settings.strip_whitespace_y)),
      #("alphaThreshold", json.int(settings.alpha_threshold)),
      #("filterMin", json.string(settings.filter_min)),
      #("filterMag", json.string(settings.filter_mag)),
      #("wrapX", json.string(settings.wrap_x)),
      #("wrapY", json.string(settings.wrap_y)),
      #("format", json.string(settings.format)),
      #("alias", json.bool(settings.alias)),
      #("ignoreBlankImages", json.bool(settings.ignore_blank_images)),
      #("fast", json.bool(settings.fast)),
      #("debug", json.bool(settings.debug)),
      #("silent", json.bool(settings.silent)),
      #("combineSubdirectories", json.bool(settings.combine_subdirectories)),
      #("flattenPaths", json.bool(settings.flatten_paths)),
      #("premultiplyAlpha", json.bool(settings.premultiply_alpha)),
      #("useIndexes", json.bool(settings.use_indexes)),
      #("bleed", json.bool(settings.bleed)),
      #("bleedIterations", json.int(settings.bleed_iterations)),
      #("limitMemory", json.bool(settings.limit_memory)),
      #("grid", json.bool(settings.grid)),
      #("scaleResampling", json.array([settings.scale_resampling], json.string)),
      #("scale", json.array([scale], json.float)),
    ]),
  )
}
