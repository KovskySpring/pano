//// Atlas and scale descriptions plus the output naming rules. The registry
//// itself lives in `packs.toml` (decoded by `cli/config`), not in
//// source code.

import cli/settings.{type Settings}
import gleam/int

pub type Spec {
  Spec(
    name: String,
    /// Path to the atlas's source image directory.
    source_dir: String,
    /// Output root; pages and JSON land in `<target_dir>/<scale dir>/`.
    target_dir: String,
    /// Output scales: the atlas is packed once per scale.
    scales: List(Scale),
    /// Whether page filenames carry a `-<index>` suffix. True for old
    /// MultiPackAuto atlases (always suffixed, even single-page), false for
    /// MultiPackOff atlases (e.g. gameplay-pwf, cities, tournament themes).
    indexed: Bool,
    /// libGDX TexturePacker settings for this atlas, defaulting to
    /// `cli/settings.default()` (the old fixed template).
    gdx_settings: Settings,
  )
}

/// One output scale: art is packed once per scale into `<target_dir>/<dir>/`.
pub type Scale {
  Scale(dir: String, factor: Float)
}

/// libGDX page index -> the runtime's expected page filename. Layout:
/// `<name><-index if indexed>.png`, e.g. `cities-resources-germany.png`,
/// `default-resources-0.png`.
pub fn page_image_name(spec: Spec, index: Int) -> String {
  let page_index = case spec.indexed {
    True -> "-" <> int.to_string(index)
    False -> ""
  }
  spec.name <> page_index <> ".png"
}

/// Atlas JSON filename, mirroring `page_image_name` without the page index.
pub fn json_name(spec: Spec) -> String {
  spec.name <> ".json"
}
