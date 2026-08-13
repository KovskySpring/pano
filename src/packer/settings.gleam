//// libGDX TexturePacker settings for one pack pass. libGDX applies `scale` during
//// packing, so each scale variant is a separate pass with a single factor.

import gleam/json

pub type Settings {
  Settings(
    pot: Bool,
    padding_x: Int,
    padding_y: Int,
    edge_padding: Bool,
    duplicate_padding: Bool,
    rotation: Bool,
    strip_whitespace_x: Bool,
    strip_whitespace_y: Bool,
    alpha_threshold: Int,
    filter_min: String,
    filter_mag: String,
    format: String,
    max_width: Int,
    max_height: Int,
    combine_subdirectories: Bool,
    flatten_paths: Bool,
    use_indexes: Bool,
    bleed: Bool,
    scale_resampling: String,
  )
}

pub fn default() -> Settings {
  Settings(
    pot: False,
    padding_x: 2,
    padding_y: 2,
    edge_padding: True,
    duplicate_padding: True,
    rotation: False,
    strip_whitespace_x: True,
    strip_whitespace_y: True,
    alpha_threshold: 0,
    filter_min: "Linear",
    filter_mag: "Linear",
    format: "RGBA8888",
    max_width: 2048,
    max_height: 2048,
    combine_subdirectories: True,
    flatten_paths: False,
    use_indexes: False,
    bleed: True,
    scale_resampling: "bicubic",
  )
}

pub fn encode(settings: Settings, scale scale: Float) -> String {
  json.object([
    #("pot", json.bool(settings.pot)),
    #("paddingX", json.int(settings.padding_x)),
    #("paddingY", json.int(settings.padding_y)),
    #("edgePadding", json.bool(settings.edge_padding)),
    #("duplicatePadding", json.bool(settings.duplicate_padding)),
    #("rotation", json.bool(settings.rotation)),
    #("stripWhitespaceX", json.bool(settings.strip_whitespace_x)),
    #("stripWhitespaceY", json.bool(settings.strip_whitespace_y)),
    #("alphaThreshold", json.int(settings.alpha_threshold)),
    #("filterMin", json.string(settings.filter_min)),
    #("filterMag", json.string(settings.filter_mag)),
    #("format", json.string(settings.format)),
    #("maxWidth", json.int(settings.max_width)),
    #("maxHeight", json.int(settings.max_height)),
    #("combineSubdirectories", json.bool(settings.combine_subdirectories)),
    #("flattenPaths", json.bool(settings.flatten_paths)),
    #("useIndexes", json.bool(settings.use_indexes)),
    #("bleed", json.bool(settings.bleed)),
    #("scaleResampling", json.array([settings.scale_resampling], json.string)),
    #("scale", json.array([scale], json.float)),
  ])
  |> json.to_string
}
