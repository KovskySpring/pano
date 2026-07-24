import birdie
import cli/config
import cli/gdx_atlas
import cli/phaser
import cli/settings.{Settings}
import cli/spec.{Scale, Spec}
import gleam/list
import gleeunit

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

const cities_spec = Spec(
  name: "cities-resources-germany",
  source_dir: "images/cities/germany",
  target_dir: "textures",
  scales: [Scale("1x", 0.3472)],
  indexed: False,
  gdx_settings: default_gdx_settings,
)

const default_spec = Spec(
  name: "default-resources",
  source_dir: "images/default",
  target_dir: "textures",
  scales: [Scale("1x", 0.3472)],
  indexed: True,
  gdx_settings: default_gdx_settings,
)

pub fn page_image_name_test() {
  // Indexed atlases always carry the page index, even single-page.
  assert spec.page_image_name(default_spec, 0) == "default-resources-0.png"
  assert spec.page_image_name(default_spec, 1) == "default-resources-1.png"

  // Un-indexed atlases carry no page index.
  assert spec.page_image_name(cities_spec, 0) == "cities-resources-germany.png"
}

pub fn json_name_test() {
  assert spec.json_name(default_spec) == "default-resources.json"
  assert spec.json_name(cities_spec) == "cities-resources-germany.json"
}

const sample_config = "
jar = \"vendor/packer.jar\"

[[atlases]]
name = \"default-resources\"
source_dir = \"art/default\"
target_dir = \"/absolute/textures\"
scales = [{ dir = \"1x\", factor = 0.5 }, { dir = \"2x\", factor = 1 }]

[[atlases]]
name = \"cities-resources-brazil\"
source_dir = \"art/cities/brazil\"
target_dir = \"textures\"
scales = [{ dir = \"1x\", factor = 0.5 }]
indexed = false
"

pub fn config_parse_test() {
  let assert Ok(parsed) = config.parse(sample_config, base_dir: "repo")

  // Relative paths resolve against the config's directory; absolute don't.
  assert parsed.jar == "repo/vendor/packer.jar"
  // Missing `concurrency` falls back to the default.
  assert parsed.concurrency == 8

  let assert [default, brazil] = parsed.atlases
  // Optional fields default to: indexed, the fixed gdx_settings template. An
  // integer `factor = 1` is accepted alongside floats.
  assert default
    == Spec(
      name: "default-resources",
      source_dir: "repo/art/default",
      target_dir: "/absolute/textures",
      scales: [Scale("1x", 0.5), Scale("2x", 1.0)],
      indexed: True,
      gdx_settings: default_gdx_settings,
    )

  assert brazil.name == "cities-resources-brazil"
  assert brazil.source_dir == "repo/art/cities/brazil"
  assert brazil.target_dir == "repo/textures"
  assert brazil.scales == [Scale("1x", 0.5)]
  assert !brazil.indexed
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
  assert list.length(germany.scales) == 3
  assert !germany.indexed
}
