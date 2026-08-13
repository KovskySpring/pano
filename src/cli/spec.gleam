//// Atlas and variant descriptions plus the output naming rules. The registry
//// itself lives in `packs.toml` (decoded by `cli/config`), not in source code.
////
//// Output directory layout:
////   no variants   → `<target_dir>/`
////   has variants  → `<target_dir>/<variant.name>/`
////   + compression → `<target_dir>/<variant.name>/<compression.name>/`

import cli/settings.{type Settings}
import gleam/int
import optimizer/spec.{type Format}

pub type Spec {
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
    /// Whether page filenames carry a `-<index>` suffix.
    indexed: Bool,
    /// libGDX TexturePacker settings for this atlas.
    gdx_settings: Settings,
  )
}

/// One output variant: a named scale pass with optional compression outputs.
///
/// - `name` becomes a subdirectory of `target_dir` (e.g. `"1x"`).
/// - `factor` is the downscale factor forwarded to libGDX TexturePacker.
/// - `compression` lists re-encoding outputs. Empty skips re-encoding.
pub type Variant {
  Variant(name: String, factor: Float, compression: List(Compression))
}

/// One compression output within a variant.
///
/// - `name` becomes a subdirectory under the variant's output directory.
/// - `format` carries the encoder options for that output.
pub type Compression {
  Compression(name: String, format: Format)
}

/// Page output filename for the given atlas name, page index, and indexed flag.
/// e.g. `page_image_name("atlas", True, 0)` → `"atlas-0.png"`.
pub fn page_image_name(
  atlas_name: String,
  indexed: Bool,
  index: Int,
) -> String {
  let page_index = case indexed {
    True -> "-" <> int.to_string(index)
    False -> ""
  }
  atlas_name <> page_index <> ".png"
}

/// JSON output filename for the atlas (e.g. `"atlas.json"`).
pub fn json_name(atlas_name: String) -> String {
  atlas_name <> ".json"
}
