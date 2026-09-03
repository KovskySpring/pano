import birdie
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import optimizer/spec as optimizer_spec
import optimizer/vips/png/options as png_options
import packer/config
import packer/gdx_atlas
import packer/phaser
import packer/settings.{Settings}
import packer/spec.{Compression, Spec, Variant}

pub fn main() -> Nil {
  gleeunit.main()
}

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
  let assert Ok([first, second]) = gdx_atlas.parse(sample_atlas)

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

pub fn phaser_json_snapshot_test() {
  let assert Ok(pages) = gdx_atlas.parse(sample_atlas)
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

pub fn settings_json_snapshot_test() {
  settings.encode(settings.default(), scale: 0.69444)
  |> birdie.snap(title: "libgdx pack settings for one scale pass")
}

const default_gdx_settings = Settings(
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

pub fn page_image_name_test() {
  assert spec.page_image_name("default-resources", 0)
    == "default-resources-0.png"
  assert spec.page_image_name("default-resources-32", 1)
    == "default-resources-32-1.png"

  assert spec.page_image_name("cities-resources-germany", 0)
    == "cities-resources-germany-0.png"
}

pub fn json_name_test() {
  assert spec.json_name("default-resources") == "default-resources.json"
  assert spec.json_name("cities-resources-germany-32")
    == "cities-resources-germany-32.json"
}

const sample_config = "
jar = \"vendor/packer.jar\"

[[atlases]]
name = \"default-resources\"
source_dir = \"art/default\"
target_dir = \"/absolute/textures\"

[atlases.variants.1x]
factor = 0.5

[atlases.variants.2x]
factor = 1

[[atlases]]
name = \"cities-resources-brazil\"
source_dir = \"art/cities/brazil\"
target_dir = \"textures\"

[atlases.variants.1x]
factor = 0.5
"

pub fn config_parse_test() {
  let assert Ok(parsed) = config.parse(sample_config, base_dir: "repo")

  // Relative paths resolve against the config's directory; absolute don't.
  assert parsed.jar == "repo/vendor/packer.jar"
  // Missing `concurrency` falls back to the default.
  assert parsed.concurrency == 8

  let assert [default, brazil] = parsed.atlases
  assert default
    == Spec(
      name: "default-resources",
      source_dir: "repo/art/default",
      target_dir: "/absolute/textures",
      variants: [Variant("1x", 0.5, []), Variant("2x", 1.0, [])],
      gdx_settings: default_gdx_settings,
    )

  assert brazil.name == "cities-resources-brazil"
  assert brazil.source_dir == "repo/art/cities/brazil"
  assert brazil.target_dir == "repo/textures"
  assert brazil.variants == [Variant("1x", 0.5, [])]
}

const compression_config = "
jar = \"c\"

[[atlases]]
name = \"x\"
source_dir = \"x\"
target_dir = \"o\"

[atlases.variants.1x]
factor = 1.0

[atlases.variants.1x.compression.x]
depth = 8
quality = 90
dither = 0.4

[atlases.variants.1x.compression.x-32]
compression = 6
strip = false
"

pub fn config_parses_compression_test() {
  let assert Ok(parsed) = config.parse(compression_config, base_dir: "")
  let assert [atlas] = parsed.atlases

  let assert [variant] = atlas.variants
  assert variant.compression
    == [
      Compression(
        name: "x",
        format: optimizer_spec.Png(
          options: png_options.PngOptions(
            ..png_options.none(),
            bitdepth: Some(8),
            palette: Some(True),
            q: Some(90),
            dither: Some(0.4),
            compression: Some(9),
            keep: Some([png_options.KeepNone]),
          ),
        ),
      ),
      Compression(
        name: "x-32",
        format: optimizer_spec.Png(
          options: png_options.PngOptions(
            ..png_options.none(),
            filter: Some([png_options.FilterAll]),
            q: Some(100),
            dither: Some(1.0),
            compression: Some(6),
          ),
        ),
      ),
    ]
}

pub fn config_rejects_wrong_type_compression_depth_test() {
  let bad =
    "
jar = \"c\"

[[atlases]]
name = \"x\"
source_dir = \"x\"
target_dir = \"o\"

[atlases.variants.1x]
factor = 1.0

[atlases.variants.1x.compression.x]
depth = \"eight\"
"
  let assert Error(_) = config.parse(bad, base_dir: "")
}

pub fn shipped_config_test() {
  // `gleam test` runs from the package root, next to the shipped packs.toml.
  let assert Ok(loaded) = config.load("test/packs.toml")

  // 6 simple + 6 cities + 7 tournament themes.
  assert list.length(loaded.atlases) == 19

  let names = list.map(loaded.atlases, fn(atlas) { atlas.name })
  assert list.contains(names, "default-resources")

  let assert Ok(germany) =
    list.find(loaded.atlases, fn(atlas) {
      atlas.name == "cities-resources-germany"
    })
  assert germany.source_dir
    == "test/../../assets/original/images/cities/germany"
  assert list.length(germany.variants) == 3
}

pub fn vips_string_joins_flag_sets_test() {
  let opts =
    png_options.PngOptions(
      ..png_options.none(),
      filter: Some([png_options.FilterSub, png_options.FilterUp]),
      keep: Some([png_options.KeepExif, png_options.KeepIcc]),
    )

  assert png_options.to_vips_string(opts) == "filter=sub:up,keep=exif:icc"
}

pub fn vips_string_omits_empty_flag_sets_test() {
  let opts =
    png_options.PngOptions(
      ..png_options.none(),
      filter: Some([]),
      keep: Some([]),
      compression: Some(9),
    )

  assert png_options.to_vips_string(opts) == "compression=9"
}

pub fn vips_string_round_trips_every_flag_name_test() {
  let filters =
    list.map(png_options.filter_names, fn(name) {
      let assert Ok(flag) = png_options.filter_from_name(name)
      flag
    })
  let keeps =
    list.map(png_options.keep_names, fn(name) {
      let assert Ok(flag) = png_options.keep_from_name(name)
      flag
    })

  let opts =
    png_options.PngOptions(
      ..png_options.none(),
      filter: Some(filters),
      keep: Some(keeps),
    )

  assert png_options.to_vips_string(opts)
    == "filter=none:sub:up:avg:paeth:all,keep=none:exif:xmp:iptc:icc:other:gainmap:all"
}

const every_option_config = "
jar = \"c\"

[[atlases]]
name = \"x\"
source_dir = \"x\"
target_dir = \"o\"

[atlases.variants.1x]
factor = 1.0

[atlases.variants.1x.compression.full]
depth = 16
quality = 80
dither = 0.5
compression = 3
interlace = true
palette = false
effort = 4
filter = [\"sub\", \"paeth\"]
keep = [\"exif\", \"icc\"]
background = [255, 128, 0.5]
page_height = 64
profile = \"srgb\"
"

pub fn config_parses_every_vips_option_test() {
  let assert Ok(parsed) = config.parse(every_option_config, base_dir: "")
  let assert [atlas] = parsed.atlases
  let assert [variant] = atlas.variants
  let assert [compression] = variant.compression
  let optimizer_spec.Png(options: opts) = compression.format

  assert opts.bitdepth == Some(16)
  assert opts.q == Some(80)
  assert opts.dither == Some(0.5)
  assert opts.compression == Some(3)
  assert opts.interlace == Some(True)
  assert opts.palette == Some(False)
  assert opts.effort == Some(4)
  assert opts.filter == Some([png_options.FilterSub, png_options.FilterPaeth])
  assert opts.keep == Some([png_options.KeepExif, png_options.KeepIcc])
  assert opts.background == Some([255.0, 128.0, 0.5])
  assert opts.page_height == Some(64)
  assert opts.profile == Some("srgb")
}

pub fn every_option_vips_string_snapshot_test() {
  let assert Ok(parsed) = config.parse(every_option_config, base_dir: "")
  let assert [atlas] = parsed.atlases
  let assert [variant] = atlas.variants
  let assert [compression] = variant.compression
  let optimizer_spec.Png(options: opts) = compression.format

  png_options.to_vips_string(opts)
  |> birdie.snap("every vips png option encoded as a bracket string")
}

/// An explicit `palette`/`filter` overrides what `depth` would imply.
pub fn compression_derives_palette_from_depth_test() {
  let derived =
    "
jar = \"c\"

[[atlases]]
name = \"x\"
source_dir = \"x\"
target_dir = \"o\"

[atlases.variants.1x]
factor = 1.0

[atlases.variants.1x.compression.low]
depth = 8

[atlases.variants.1x.compression.high]
depth = 16
"
  let assert Ok(parsed) = config.parse(derived, base_dir: "")
  let assert [atlas] = parsed.atlases
  let assert [variant] = atlas.variants
  let assert [high, low] = variant.compression

  let optimizer_spec.Png(options: low_opts) = low.format
  assert low_opts.palette == Some(True)
  assert low_opts.filter == None

  let optimizer_spec.Png(options: high_opts) = high.format
  assert high_opts.palette == None
  assert high_opts.filter == Some([png_options.FilterAll])
}

pub fn compression_rejects_strip_and_keep_together_test() {
  let bad =
    "
jar = \"c\"

[[atlases]]
name = \"x\"
source_dir = \"x\"
target_dir = \"o\"

[atlases.variants.1x]
factor = 1.0

[atlases.variants.1x.compression.x]
strip = true
keep = [\"exif\"]
"
  let assert Error(_) = config.parse(bad, base_dir: "")
}

pub fn compression_rejects_unknown_flag_name_test() {
  let bad =
    "
jar = \"c\"

[[atlases]]
name = \"x\"
source_dir = \"x\"
target_dir = \"o\"

[atlases.variants.1x]
factor = 1.0

[atlases.variants.1x.compression.x]
keep = [\"exif\", \"bogus\"]
"
  let assert Error(_) = config.parse(bad, base_dir: "")
}

/// A `profile` path resolves against the config's directory, a built-in name
/// does not.
pub fn compression_resolves_profile_path_test() {
  let cfg = fn(profile) { "
jar = \"c\"

[[atlases]]
name = \"x\"
source_dir = \"x\"
target_dir = \"o\"

[atlases.variants.1x]
factor = 1.0

[atlases.variants.1x.compression.x]
profile = \"" <> profile <> "\"
" }

  let profile_of = fn(text) {
    let assert Ok(parsed) = config.parse(text, base_dir: "cfgdir")
    let assert [atlas] = parsed.atlases
    let assert [variant] = atlas.variants
    let assert [compression] = variant.compression
    let optimizer_spec.Png(options: opts) = compression.format
    opts.profile
  }

  assert profile_of(cfg("profiles/custom.icc"))
    == Some("cfgdir/profiles/custom.icc")
  assert profile_of(cfg("srgb")) == Some("srgb")
}
