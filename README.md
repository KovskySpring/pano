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

### Top-level keys

| Key           | Type   | Required | Default | Description                                   |
| ------------- | ------ | -------- | ------- | --------------------------------------------- |
| `jar`         | string | ✓        | —       | Path to the runnable `texturepacker.jar`.     |
| `concurrency` | int    |          | `8`     | Maximum number of atlases packed in parallel. |

### `[[atlases]]`

Each entry in the `[[atlases]]` array defines one atlas to pack.

| Key          | Type   | Required | Default | Description                                                                                                                     |
| ------------ | ------ | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `name`       | string | ✓        | —       | Atlas name. Used as the base filename for all outputs (`<name>.json`, `<name>.png`, …).                                         |
| `source_dir` | string | ✓        | —       | Directory containing the source images to pack.                                                                                 |
| `target_dir` | string | ✓        | —       | Root output directory for this atlas.                                                                                           |
| `indexed`    | bool   |          | `true`  | When `true`, page image files carry a `-<index>` numeric suffix (e.g. `atlas-0.png`). Set to `false` to get a bare `atlas.png`. |

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

| Key           | Type  | Default | Description                                                                                                            |
| ------------- | ----- | ------- | ---------------------------------------------------------------------------------------------------------------------- |
| `depth`       | int   | —       | Bit depth. `≤ 8` enables palette quantisation (libimagequant); absent or `> 8` uses full-colour with all zlib filters. |
| `quality`     | int   | `100`   | PNG quality / quantisation quality (0–100).                                                                            |
| `dither`      | float | `1.0`   | Dithering strength for palette quantisation (0.0–1.0).                                                                 |
| `compression` | int   | `9`     | zlib compression level (0–9).                                                                                          |
| `strip`       | bool  | `true`  | Strip all metadata from output images when `true`.                                                                     |

### Annotated example

```toml
jar = "vendor/runnable-texturepacker.jar"
concurrency = 4

[[atlases]]
name       = "ui-resources"
source_dir = "assets/images/ui"
target_dir = "assets/textures"
# indexed = true  # default; produces ui-resources-0.png, ui-resources-1.png, …

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
strip       = true

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
