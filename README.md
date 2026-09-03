# pano - Phaser Pack N' Optimize

Multi-threaded texture packer for Phaser 3,
using libGDX's TexturePacker and `libvips` under the hood.

## Prerequisites

- Erlang/OTP 27+ (for running the `pano` escript). Checked at startup; older releases are rejected.
- A JVM (Java 8+) on `PATH` as `java` (for libGDX's TexturePacker). Checked before packing.
- `runnable-texturepacker.jar` (for libGDX's TexturePacker). See [libGDX's TexturePacker](https://libgdx.com/wiki/tools/texture-packer).
- libvips 8.15+ CLI on `PATH` as `vips` (for PNG compression, `keep=` option requires 8.15+). Checked before packing, but only if any `[compression]` table is configured.

## Installation

```sh
curl -fsSL https://raw.githubusercontent.com/KovskySpring/pano/main/scripts/install.sh | sh
```

`pano` is a single escript, installed to `~/.local/bin/pano` (overridable with
`PANO_BIN_DIR`). It is pure BEAM bytecode, so the same file runs on every OS
and architecture.

## Usage

All configuration lives in a `packs.toml` file.

```sh
# pack every atlas in ./packs.toml
pano
# explicit config location
pano --config path/to/packs.toml
```

Because `pano` uses libGDX's TexturePacker standalone jar,
you must have it installed and referenced in your `packs.toml` file.
libGDX's TexturePacker reads environment overrides:
`GDX_OUT_ROOT` to replace every atlas's `target_dir` and
`GDX_CONCURRENCY` to replaces `concurrency`. `pano` respects
these overrides but it is recommended to set them in your `packs.toml` file instead.

## Development

See [mise.toml](mise.toml) for the development configuration.
`pano` is written in gleam and built for the `erlang` target.

You can run it with `gleam run` or build it with `gleam build`.

Testing is done with `birdie`, run `gleam test` to run the tests.

## packs.toml

All configuration lives in a single `packs.toml` file.
Relative paths in the file always resolve against the directory that contains it.

### Editor intellisense

[`./editors/schema.json`](schema.json) documents the full shape of `packs.toml` and can be
wired up to editors that support JSON Schema for TOML for autocomplete, inline docs,
and validation.

### Top-level keys

| Key           | Type   | Required | Default  | Description                                                                                                               |
| ------------- | ------ | -------- | -------- | ------------------------------------------------------------------------------------------------------------------------- |
| `jar`         | string | ✓        | -        | Path to the runnable `texturepacker.jar`.                                                                                 |
| `vips`        | string |          | `"vips"` | The `vips` executable. A bare name is looked up on `PATH`; a value containing `/` resolves against this file's directory. |
| `concurrency` | int    |          | `8`      | Maximum number of atlases packed in parallel. Values below 1 are clamped to 1.                                            |

### `[[atlases]]`

Each entry in the `[[atlases]]` array defines one atlas to pack.

| Key          | Type   | Required | Default | Description                                                                             |
| ------------ | ------ | -------- | ------- | --------------------------------------------------------------------------------------- |
| `name`       | string | ✓        | -       | Atlas name. Used as the base filename for all outputs (`<name>.json`, `<name>.png`, …). |
| `source_dir` | string | ✓        | -       | Directory containing the source images to pack.                                         |
| `target_dir` | string | ✓        | -       | Root output directory for this atlas.                                                   |

#### libGDX TexturePacker settings

All of the following keys are optional and sit directly inside an `[[atlases]]` entry.
They map to libGDX TexturePacker settings and are forwarded verbatim to the packer.

| Key                      | Type   | Default      | Description                                                                    |
| ------------------------ | ------ | ------------ | ------------------------------------------------------------------------------ |
| `pot`                    | bool   | `false`      | Force power-of-two page dimensions.                                            |
| `padding_x`              | int    | `2`          | Pixels of padding added to the left and right of each sprite.                  |
| `padding_y`              | int    | `2`          | Pixels of padding added to the top and bottom of each sprite.                  |
| `edge_padding`           | bool   | `true`       | Add padding around the edges of each page.                                     |
| `duplicate_padding`      | bool   | `true`       | Duplicate pixels into the padding region to reduce texture bleeding.           |
| `rotation`               | bool   | `false`      | Allow sprites to be rotated 90° to improve packing.                            |
| `strip_whitespace_x`     | bool   | `true`       | Strip transparent pixels from the left and right sides of sprites.             |
| `strip_whitespace_y`     | bool   | `true`       | Strip transparent pixels from the top and bottom sides of sprites.             |
| `alpha_threshold`        | int    | `0`          | Pixels with alpha ≤ this value are treated as fully transparent.               |
| `filter_min`             | string | `"Linear"`   | Minification filter (`Linear`, `Nearest`, …).                                  |
| `filter_mag`             | string | `"Linear"`   | Magnification filter (`Linear`, `Nearest`, …).                                 |
| `format`                 | string | `"RGBA8888"` | Pixel format passed to the packer (e.g. `RGBA8888`, `RGB888`).                 |
| `max_width`              | int    | `2048`       | Maximum page width in pixels.                                                  |
| `max_height`             | int    | `2048`       | Maximum page height in pixels.                                                 |
| `combine_subdirectories` | bool   | `true`       | Treat all subdirectories of `source_dir` as part of the same atlas.            |
| `flatten_paths`          | bool   | `false`      | Strip directory prefixes from sprite names in the atlas.                       |
| `use_indexes`            | bool   | `false`      | Append a numeric index to sprite names for animation frames.                   |
| `bleed`                  | bool   | `true`       | Extend the border pixels of sprites into the padding to avoid colour fringing. |
| `scale_resampling`       | string | `"bicubic"`  | Resampling algorithm used when downscaling (`bicubic`, `bilinear`, `nearest`). |

### `[atlases.variants.<name>]`

Variants produce one scaled output per entry.
When no variants are declared the atlas is packed once at factor `1.0` directly into `target_dir`.
When variants are present each one writes into `<target_dir>/<variant-name>/`.

The `<name>` key is arbitrary and becomes the subdirectory name (e.g. `1x`, `2x`).

| Key      | Type  | Required | Description                                                                         |
| -------- | ----- | -------- | ----------------------------------------------------------------------------------- |
| `factor` | float | ✓        | Scale factor applied to the source images for this pass (e.g. `0.5` for half-size). |

### `[atlases.variants.<name>.compression.<name>]`

Each compression entry re-encodes the variant's output pages with `libvips`.
The `<name>` key is arbitrary and becomes a subdirectory under the variant's output (`<target_dir>/<variant>/<compression>/`).
When no compression entries are declared the variant's raw packer output is kept as-is.

Every option `vips pngsave` accepts is available here, so you should not need to go
looking through the vips docs. Each key names the vips option it maps to; the four
with a pano default are always sent, and any key you leave out is omitted from the
vips call entirely, leaving vips its own default.

| Key           | Type     | vips option   | pano default | vips default | Description                                                                                                                   |
| ------------- | -------- | ------------- | ------------ | ------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `depth`       | int      | `bitdepth`    | -            | `8`          | Bit depth, one of `1`, `2`, `4`, `8`, `16`. `≤ 8` selects palette quantisation (libimagequant), larger uses every row filter. |
| `quality`     | int      | `Q`           | `100`        | `100`        | Quantisation quality, 0–100. Always sent, but only meaningful when palette quantisation is active.                            |
| `dither`      | float    | `dither`      | `1.0`        | `1.0`        | Dithering strength for palette quantisation, 0.0–1.0.                                                                         |
| `compression` | int      | `compression` | `9`          | `6`          | zlib compression level, 0–9. Higher is smaller and slower.                                                                    |
| `strip`       | bool     | `keep`        | `true`       | -            | Shorthand: `true` sends `keep = ["none"]`, `false` keeps everything. Cannot be combined with `keep`.                          |
| `keep`        | string[] | `keep`        | -            | all blocks   | Metadata blocks to retain: `none`, `exif`, `xmp`, `iptc`, `icc`, `other`, `gainmap`, `all`. Cannot be combined with `strip`.  |
| `filter`      | string[] | `filter`      | see note     | `none`       | Row filters: `none`, `sub`, `up`, `avg`, `paeth`, `all`. Defaults to `["all"]` unless `depth` selects palette quantisation.   |
| `palette`     | bool     | `palette`     | see note     | `false`      | Quantise to a palette (indexed) PNG. Defaults to on when `depth ≤ 8`; set it to override.                                     |
| `effort`      | int      | `effort`      | -            | `7`          | CPU effort for palette quantisation, 1–10. Higher is better quality and slower.                                               |
| `interlace`   | bool     | `interlace`   | -            | `false`      | Write an interlaced (Adam7) PNG. Requires the full image in memory.                                                           |
| `background`  | number[] | `background`  | -            | -            | Background colour used when flattening alpha, e.g. `[255, 255, 255]`.                                                         |
| `page_height` | int      | `page-height` | -            | `0`          | Page height for a multi-page save, in pixels.                                                                                 |
| `profile`     | string   | `profile`     | -            | -            | ICC profile to embed: a built-in name (`srgb`, `p3`, `cmyk`) or a path, resolved against the config's directory.              |

`keep` and `filter` are flag _sets_ - pass an array and pano joins it with `:` for vips
(`keep = ["exif", "icc"]` becomes `keep=exif:icc`). For both, `none` is absorbing, as is
`all` for `keep`. An empty array omits the option.

Two things to know about ranges. vips **clamps** out-of-range numbers instead of
rejecting them, so `quality = 101` silently becomes `100` - the bounds above are worth
respecting even though nothing errors. `depth` is the exception: vips accepts only
`1`, `2`, `4`, `8` or `16` and fails on anything else.

### Annotated example

```toml
jar = "vendor/runnable-texturepacker.jar"
concurrency = 4

[[atlases]]
name       = "ui-resources"
source_dir = "assets/images/ui"
target_dir = "assets/textures"

# libGDX settings override (all optional)
max_width  = 4096
max_height = 4096
rotation   = true

[atlases.variants.1x]
factor = 0.5

[atlases.variants.1x.compression.8bit]
# depth ≤ 8 → palette quantisation via libimagequant
depth       = 8
quality     = 85
dither      = 0.8
compression = 9
effort      = 10          # only meaningful while quantising
strip       = true

[atlases.variants.1x.compression.archival]
# full colour, keeping the colour profile and choosing filters by hand
depth   = 16
filter  = ["sub", "paeth"]
keep    = ["icc"]
profile = "srgb"

[atlases.variants.2x]
factor = 1.0
# no compression block → keep the packer's raw output
```

Output layout for the example above:

```
assets/textures/
  1x/
    ui-resources-0.png          # raw packer output
    8bit/
      ui-resources-0.png        # palette-quantised copy
    archival/
      ui-resources-0.png        # 16-bit copy with an embedded profile
  2x/
    ui-resources-0.png          # raw packer output
  ui-resources.json             # Phaser multiatlas descriptor
```

### Environment overrides

| Variable          | Overrides                                   |
| ----------------- | ------------------------------------------- |
| `GDX_OUT_ROOT`    | Replaces `target_dir` for every atlas.      |
| `GDX_CONCURRENCY` | Replaces the top-level `concurrency` value. |

## License

Apache 2.0, see [LICENSE](LICENSE) for details.
