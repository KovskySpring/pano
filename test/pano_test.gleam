import birdie
import config.{Spec, Variant}
import gleam/erlang/process
import gleam/list
import gleeunit
import internal/compat/gdx
import internal/compat/phaser
import internal/path_utils
import internal/pool
import pack_config.{Settings}

pub fn main() -> Nil {
  gleeunit.main()
}

// --- gdx_atlas ---------------------------------------------------------

/// A representative libGDX atlas: two pages, a trimmed region (offset y-flip),
/// an untrimmed region, and a rotated region.
const sample_atlas = "
default-resources.png
size: 2048, 1024
format: RGBA8888
filter: Linear, Linear
repeat: none
icons/star
  rotate: false
  xy: 2, 2
  size: 96, 92
  orig: 100, 100
  offset: 2, 4
  index: -1
blank
  rotate: false
  xy: 100, 2
  size: 100, 100
  orig: 100, 100
  offset: 0, 0
  index: -1

default-resources2.png
size: 512, 512
format: RGBA8888
filter: Linear, Linear
repeat: none
button/play
  rotate: true
  xy: 4, 4
  size: 200, 80
  orig: 200, 80
  offset: 0, 0
  index: -1
"

pub fn parse_pages_test() {
  let assert Ok([first, second]) = gdx.parse_gdx(sample_atlas)

  assert first.image == "default-resources.png"
  assert first.size == #(2048, 1024)
  assert first.format == "RGBA8888"

  let assert [star, blank] = first.frames
  assert star.filename == "icons/star"
  assert star.trimmed
  assert !star.rotated
  assert star.source_size == #(100, 100)
  // libGDX offset is bottom-left based: y = 100 - 4 - 92 = 4.
  assert star.sprite_source == #(2, 4, 96, 92)
  assert star.region == #(2, 2, 96, 92)

  assert blank.filename == "blank"
  assert !blank.trimmed
  assert blank.sprite_source == #(0, 0, 100, 100)

  let assert [play] = second.frames
  assert play.rotated
  assert !play.trimmed
}

/// `orig` and `offset` are absent in a `pma`-flavoured page, so they fall back
/// to the region size and origin, and the frame reads as untrimmed.
pub fn parse_defaults_missing_region_keys_test() {
  let atlas =
    "
page.png
size: 64, 64
format: RGBA8888
filter: Nearest, Nearest
repeat: none
pma: true
dot
  xy: 1, 2
  size: 8, 8
"
  let assert Ok([page]) = gdx.parse_gdx(atlas)
  let assert [dot] = page.frames

  assert dot.source_size == #(8, 8)
  assert dot.sprite_source == #(0, 0, 8, 8)
  assert dot.region == #(1, 2, 8, 8)
  assert !dot.trimmed
  assert !dot.rotated
}

pub fn parse_rejects_incomplete_header_test() {
  let assert Error(_) =
    gdx.parse_gdx("page.png\nsize: 64, 64\nname\n  xy: 0, 0\n  size: 1, 1\n")
}

pub fn parse_rejects_region_without_placement_test() {
  let assert Error(_) =
    gdx.parse_gdx(
      "page.png\nsize: 64, 64\nformat: RGBA8888\nname\n  index: -1\n",
    )
}

// --- phaser ------------------------------------------------------------

pub fn phaser_json_snapshot_test() {
  let assert Ok(pages) = gdx.parse_gdx(sample_atlas)
  let named = case pages {
    [first, second] -> [
      #("default-resources-0.png", first),
      #("default-resources-1.png", second),
    ]
    _ -> panic as "expected exactly two pages"
  }

  phaser.encode(named, 0.3472)
  |> birdie.snap(title: "gdx atlas converted to phaser multiatlas json")
}

// --- output naming ------------------------------------------------------------

pub fn page_image_name_test() {
  assert path_utils.page_image_filename("default-resources", 0)
    == "default-resources-0.png"
  assert path_utils.page_image_filename("default-resources-32", 1)
    == "default-resources-32-1.png"
  assert path_utils.page_image_filename("cities-resources-germany", 0)
    == "cities-resources-germany-0.png"
}

pub fn json_name_test() {
  assert path_utils.atlas_json_filename("default-resources")
    == "default-resources.json"
  assert path_utils.atlas_json_filename("cities-resources-germany-32")
    == "cities-resources-germany-32.json"
}

// --- settings ----------------------------------------------------------

pub fn settings_json_snapshot_test() {
  pack_config.encode(pack_config.default(), scale: 0.69444)
  |> birdie.snap(title: "libgdx pack settings for one scale pass")
}

// --- config ------------------------------------------------------------

const sample_config = "
jar = \"vendor/packer.jar\"

[atlases.default-resources]
source_dir = \"art/default\"
target_dir = \"/absolute/textures\"

[atlases.default-resources.variants.1x]
scale_factor = 0.5

[atlases.default-resources.variants.2x]
scale_factor = 1

[atlases.cities-resources-brazil]
source_dir = \"art/cities/brazil\"
target_dir = \"textures\"

[atlases.cities-resources-brazil.variants.1x]
scale_factor = 0.5
"

pub fn config_parse_test() {
  let assert Ok(parsed) = config.parse_config(sample_config, base_dir: "repo")

  // Relative paths resolve against the config's directory; absolute don't.
  assert parsed.jar == "repo/vendor/packer.jar"
  // Missing `concurrency` and `timeout` fall back to their defaults.
  assert parsed.concurrency == 8
  assert parsed.timeout == 30_000

  // Atlases are sorted by name.
  let assert [brazil, default] = parsed.atlases
  assert default
    == Spec(
      name: "default-resources",
      source_dir: "repo/art/default",
      target_dir: "/absolute/textures",
      // Variants are sorted by name, and an int `scale_factor` widens to a
      // float. Neither variant overrides anything, so both inherit the
      // atlas's settings.
      variants: [
        Variant("1x", 0.5, pack_config.default(), 30_000),
        Variant("2x", 1.0, pack_config.default(), 30_000),
      ],
      gdx_settings: pack_config.default(),
      timeout: 30_000,
    )

  assert brazil.name == "cities-resources-brazil"
  assert brazil.source_dir == "repo/art/cities/brazil"
  assert brazil.target_dir == "repo/textures"
  assert brazil.variants == [Variant("1x", 0.5, pack_config.default(), 30_000)]
}

/// An atlas without a `[atlases.<name>.variants.*]` table packs once at factor 1.0
/// directly into `target_dir`, which `pack` represents as no variants at all.
pub fn config_without_variants_test() {
  let text =
    "jar = \"c\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n"
  let assert Ok(parsed) = config.parse_config(text, base_dir: "/")
  let assert [atlas] = parsed.atlases

  assert atlas.variants == []
}

/// `tom` parses `0.3472` into a drifted double; `config` rounds it back.
pub fn config_rounds_variant_factor_test() {
  let text =
    "jar = \"c\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n[atlases.x.variants.1x]\nscale_factor = 0.3472\n"
  let assert Ok(parsed) = config.parse_config(text, base_dir: "/")
  let assert [atlas] = parsed.atlases
  let assert [variant] = atlas.variants

  assert variant.scale_factor == 0.3472
}

pub fn config_rejects_non_finite_factor_test() {
  let text =
    "jar = \"c\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n[atlases.x.variants.1x]\nscale_factor = nan\n"
  let assert Error(_) = config.parse_config(text, base_dir: "/")
}

pub fn config_rejects_missing_jar_test() {
  let text = "[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n"
  let assert Error(_) = config.parse_config(text, base_dir: "/")
}

pub fn config_rejects_missing_atlas_key_test() {
  let text = "jar = \"c\"\n[atlases.x]\ntarget_dir = \"o\"\n"
  let assert Error(_) = config.parse_config(text, base_dir: "/")
}

/// `..` is resolved away while it has a parent segment to consume; a path that
/// would climb above the config's own directory is rejected.
pub fn config_path_traversal_test() {
  let cfg = fn(jar) {
    "jar = \""
    <> jar
    <> "\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n"
  }

  let assert Ok(parsed) =
    config.parse_config(cfg("../vendor/p.jar"), base_dir: "cfg")
  assert parsed.jar == "vendor/p.jar"

  let assert Error(config.InvalidPath(_)) =
    config.parse_config(cfg("../../vendor/p.jar"), base_dir: "cfg")
}

// --- config: libGDX settings -------------------------------------------

/// Every libGDX key set to a non-default value, so a key the loader silently
/// ignores shows up as a mismatch here.
const overridden_gdx_config = "
jar = \"c\"

[atlases.x]
source_dir = \"x\"
target_dir = \"o\"

pot = true
multiple_of_four = true
padding_x = 4
padding_y = 6
edge_padding = false
duplicate_padding = false
rotation = true
min_width = 64
min_height = 32
max_width = 4096
max_height = 1024
square = true
strip_whitespace_x = false
strip_whitespace_y = false
alpha_threshold = 10
filter_min = \"Nearest\"
filter_mag = \"MipMapLinearLinear\"
wrap_x = \"Repeat\"
wrap_y = \"MirroredRepeat\"
format = \"RGB565\"
alias = false
ignore_blank_images = false
fast = true
debug = true
silent = true
combine_subdirectories = false
flatten_paths = true
premultiply_alpha = true
use_indexes = true
bleed = false
bleed_iterations = 8
limit_memory = false
grid = true
scale_resampling = \"nearest\"
"

pub fn gdx_settings_override_test() {
  let assert Ok(parsed) =
    config.parse_config(overridden_gdx_config, base_dir: "/")
  let assert [atlas] = parsed.atlases

  assert atlas.gdx_settings
    == Settings(
      pot: True,
      multiple_of_four: True,
      padding_x: 4,
      padding_y: 6,
      edge_padding: False,
      duplicate_padding: False,
      rotation: True,
      min_width: 64,
      min_height: 32,
      max_width: 4096,
      max_height: 1024,
      square: True,
      strip_whitespace_x: False,
      strip_whitespace_y: False,
      alpha_threshold: 10,
      filter_min: "Nearest",
      filter_mag: "MipMapLinearLinear",
      wrap_x: "Repeat",
      wrap_y: "MirroredRepeat",
      format: "RGB565",
      alias: False,
      ignore_blank_images: False,
      fast: True,
      debug: True,
      silent: True,
      combine_subdirectories: False,
      flatten_paths: True,
      premultiply_alpha: True,
      use_indexes: True,
      bleed: False,
      bleed_iterations: 8,
      limit_memory: False,
      grid: True,
      scale_resampling: "nearest",
    )
}

/// A partial set of libGDX keys leaves every key it omits at its default.
pub fn gdx_settings_partial_override_test() {
  let text =
    "jar = \"c\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\nmax_width = 4096\n"
  let assert Ok(parsed) = config.parse_config(text, base_dir: "/")
  let assert [atlas] = parsed.atlases

  assert atlas.gdx_settings
    == Settings(..pack_config.default(), max_width: 4096)
}

pub fn gdx_settings_wrong_type_test() {
  let bad =
    "jar = \"c\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\nalias = \"no\"\n"
  let assert Error(_) = config.parse_config(bad, base_dir: "/")
}

/// A libGDX key in a variant wins over the atlas's, which wins over the
/// default. Keys the variant leaves out fall through to whichever layer sets
/// them.
const layered_gdx_config = "
jar = \"c\"

[atlases.x]
source_dir = \"x\"
target_dir = \"o\"
max_width = 4096
max_height = 4096
rotation = true

[atlases.x.variants.1x]
scale_factor = 0.5
max_width = 1024
grid = true

[atlases.x.variants.2x]
scale_factor = 1.0
"

pub fn gdx_settings_variant_override_test() {
  let assert Ok(parsed) = config.parse_config(layered_gdx_config, base_dir: "/")
  let assert [atlas] = parsed.atlases
  let assert [one_x, two_x] = atlas.variants

  assert atlas.gdx_settings
    == Settings(
      ..pack_config.default(),
      max_width: 4096,
      max_height: 4096,
      rotation: True,
    )

  // `max_width` from the variant, `max_height`/`rotation` from the atlas,
  // `grid` set only here, everything else still default.
  assert one_x.gdx_settings
    == Settings(..atlas.gdx_settings, max_width: 1024, grid: True)

  // A variant that overrides nothing inherits the atlas's settings whole.
  assert two_x.gdx_settings == atlas.gdx_settings
}

/// Root-level libGDX keys are the base every atlas overrides, and an atlas
/// that overrides nothing inherits them whole.
const root_gdx_config = "
jar = \"c\"
max_width = 4096
rotation = true

[atlases.inherits]
source_dir = \"x\"
target_dir = \"o\"

[atlases.overrides]
source_dir = \"x\"
target_dir = \"o\"
max_width = 2048

[atlases.overrides.variants.1x]
scale_factor = 0.5
max_width = 1024
"

pub fn gdx_settings_root_override_test() {
  let assert Ok(parsed) = config.parse_config(root_gdx_config, base_dir: "/")
  let assert [inherits, overrides] = parsed.atlases

  let root = Settings(..pack_config.default(), max_width: 4096, rotation: True)
  assert parsed.gdx_settings == root

  assert inherits.gdx_settings == root

  // The atlas's `max_width` wins over the root's; `rotation` still falls
  // through from the root.
  assert overrides.gdx_settings == Settings(..root, max_width: 2048)

  // And the variant's wins over both.
  let assert [one_x] = overrides.variants
  assert one_x.gdx_settings == Settings(..root, max_width: 1024)
}

/// Root-level libGDX keys are type-checked the same as an atlas's.
pub fn gdx_settings_root_wrong_type_test() {
  let bad =
    "jar = \"c\"\nalias = \"no\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n"
  let assert Error(_) = config.parse_config(bad, base_dir: "/")
}

/// A variant's libGDX keys are type-checked the same as an atlas's.
pub fn gdx_settings_variant_wrong_type_test() {
  let bad =
    "jar = \"c\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n[atlases.x.variants.1x]\nscale_factor = 0.5\nalias = \"no\"\n"
  let assert Error(_) = config.parse_config(bad, base_dir: "/")
}

// --- config: the shipped packs.toml ------------------------------------

pub fn shipped_config_test() {
  // `gleam test` runs from the package root, so the fixture's own directory
  // (`test/`) is what its relative paths resolve against.
  let assert Ok(loaded) = config.load_config("test/packs.toml")

  assert loaded.jar == "vendor/runnable-texturepacker.jar"
  // 6 simple + 6 cities + 7 tournament themes.
  assert list.length(loaded.atlases) == 19
  assert loaded.concurrency == 8
  assert loaded.timeout == 120_000

  let root =
    Settings(
      ..pack_config.default(),
      max_width: 4096,
      max_height: 4096,
      bleed_iterations: 4,
    )
  assert loaded.gdx_settings == root

  let names = list.map(loaded.atlases, fn(atlas) { atlas.name })
  assert list.contains(names, "default-resources")

  // An atlas that overrides nothing inherits the root's settings whole.
  let assert Ok(default_resources) =
    list.find(loaded.atlases, fn(atlas) { atlas.name == "default-resources" })
  assert default_resources.gdx_settings == root
  assert default_resources.timeout == 120_000

  let assert Ok(germany) =
    list.find(loaded.atlases, fn(atlas) {
      atlas.name == "cities-resources-germany"
    })
  assert germany.source_dir == "assets/original/images/cities/germany"
  assert germany.timeout == 300_000
  assert list.map(germany.variants, fn(variant) { variant.timeout })
    == [300_000, 300_000, 300_000]
  assert list.map(germany.variants, fn(variant) { variant.name })
    == ["1x", "2_88x", "2x"]

  // Germany narrows `max_width`, and its 1x pass narrows it again; the other
  // two passes stop at the atlas's value. `max_height`/`bleed_iterations`
  // fall through from the root at every layer.
  assert germany.gdx_settings == Settings(..root, max_width: 2048)
  assert list.map(germany.variants, fn(variant) {
      variant.gdx_settings.max_width
    })
    == [1024, 2048, 2048]
  assert list.map(germany.variants, fn(variant) {
      #(variant.gdx_settings.max_height, variant.gdx_settings.bleed_iterations)
    })
    == [#(4096, 4), #(4096, 4), #(4096, 4)]
}

// --- config: timeouts --------------------------------------------------

/// `timeout` resolves like the libGDX settings: variant, then atlas, then
/// root, then the 30s default.
const layered_timeout_config = "
jar = \"c\"
timeout = 120_000

[atlases.x]
source_dir = \"x\"
target_dir = \"o\"
timeout = 60_000

[atlases.x.variants.1x]
scale_factor = 0.5
timeout = 5000

[atlases.x.variants.2x]
scale_factor = 1.0

[atlases.y]
source_dir = \"y\"
target_dir = \"o\"
"

pub fn config_timeout_layers_test() {
  let assert Ok(parsed) =
    config.parse_config(layered_timeout_config, base_dir: "/")
  let assert [x, y] = parsed.atlases
  let assert [one_x, two_x] = x.variants

  assert parsed.timeout == 120_000
  // The atlas overrides the root, and the variant overrides the atlas.
  assert x.timeout == 60_000
  assert one_x.timeout == 5000
  assert two_x.timeout == 60_000
  // An atlas that sets nothing inherits the root's.
  assert y.timeout == 120_000
}

/// A timeout of zero or less would fail every job before it started.
pub fn config_rejects_non_positive_timeout_test() {
  let text =
    "jar = \"c\"\ntimeout = 0\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n"
  let assert Error(config.InvalidTimeout(0)) =
    config.parse_config(text, base_dir: "/")

  let variant =
    "jar = \"c\"\n[atlases.x]\nsource_dir = \"x\"\ntarget_dir = \"o\"\n[atlases.x.variants.1x]\nscale_factor = 0.5\ntimeout = -1\n"
  let assert Error(config.InvalidTimeout(-1)) =
    config.parse_config(variant, base_dir: "/")
}

// --- pool ---------------------------------------------------------------

/// An item that outruns its timeout reports `TimedOut` without holding up the
/// items beside it, and its work is killed rather than left running.
pub fn pool_times_out_slow_item_test() {
  let escaped = process.new_subject()

  let results =
    pool.exec(
      [#(0, 10), #(1, 2000), #(2, 10)],
      limit: 3,
      timeout: fn(item) {
        case item {
          #(1, _) -> 100
          _ -> 5000
        }
      },
      run: fn(item) {
        let #(index, nap) = item
        process.sleep(nap)
        // Only reached by an item that was not killed.
        process.send(escaped, index)
        index
      },
    )

  assert results == [pool.Finished(0), pool.TimedOut, pool.Finished(2)]

  // The two that finished reported in; the killed one never does.
  let assert Ok(_) = process.receive(escaped, within: 100)
  let assert Ok(_) = process.receive(escaped, within: 100)
  let assert Error(Nil) = process.receive(escaped, within: 2500)
}
