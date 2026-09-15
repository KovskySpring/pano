# pano - Phaser Pack N' Optimize

Multi-threaded texture packer for Phaser 3,
using libGDX's TexturePacker under the hood.

## Prerequisites

- Erlang/OTP 27+ (for running the `pano` escript). Checked at startup; older releases are rejected.
- A JVM (Java 8+) on `PATH` as `java` (for libGDX's TexturePacker). Checked before packing.
- `runnable-texturepacker.jar` (for libGDX's TexturePacker). See [libGDX's TexturePacker](https://libgdx.com/wiki/tools/texture-packer).

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
pano --config=path/to/packs.toml
```

Because `pano` uses libGDX's TexturePacker standalone jar,
you must have it installed and referenced in your `packs.toml` file.

## Development

See [mise.toml](mise.toml) for the development configuration.
`pano` is written in gleam and built for the `erlang` target.

You can run it with `gleam run` or build it with `gleam build`.

Tests use `gleeunit`, with `birdie` for the JSON snapshots. Run `gleam test`.
Review a changed snapshot with `gleam run -m birdie`.

## packs.toml

All configuration lives in a single `packs.toml` file.
Relative paths in the file always resolve against the directory that contains it,
and may not climb above it — `../` is rejected when there is no parent segment left
to consume.

### Editor intellisense

[`./editors/schema.json`](editors/schema.json) documents the full shape of `packs.toml` and can be
wired up to editors that support JSON Schema for TOML for autocomplete, inline docs,
and validation.

### Top-level keys

| Key           | Type   | Required | Default | Description                                                                |
| ------------- | ------ | -------- | ------- | -------------------------------------------------------------------------- |
| `jar`         | string | ✓        | -       | Path to the runnable `texturepacker.jar`.                                  |
| `concurrency` | int    |          | `8`     | Maximum number of pack jobs run in parallel. Values below 1 are clamped to 1. |

### `[[atlases]]`

Each entry in the `[[atlases]]` array defines one atlas to pack.

| Key          | Type   | Required | Default | Description                                                                             |
| ------------ | ------ | -------- | ------- | --------------------------------------------------------------------------------------- |
| `name`       | string | ✓        | -       | Atlas name. Used as the base filename for all outputs (`<name>.json`, `<name>.png`, …). |
| `source_dir` | string | ✓        | -       | Directory containing the source images to pack.                                         |
| `target_dir` | string | ✓        | -       | Root output directory for this atlas.                                                   |

### `[atlases.gdx_settings]`

Every key in this table is optional and maps to a libGDX TexturePacker setting,
forwarded verbatim to the packer. Omit the table entirely to pack with the defaults
below; include it to override only the keys you list.

| Key                      | Type   | Default         | Description                                                                      |
| ------------------------ | ------ | --------------- | -------------------------------------------------------------------------------- |
| `pot`                    | bool   | `false`         | Force power-of-two page dimensions.                                              |
| `multiple_of_four`       | bool   | `false`         | Force page dimensions to a multiple of four (needed by some compressed formats). |
| `padding_x`              | int    | `2`             | Pixels of padding added to the left and right of each sprite.                    |
| `padding_y`              | int    | `2`             | Pixels of padding added to the top and bottom of each sprite.                    |
| `edge_padding`           | bool   | `true`          | Add padding around the edges of each page.                                       |
| `duplicate_padding`      | bool   | `true`          | Duplicate pixels into the padding region to reduce texture bleeding.             |
| `rotation`               | bool   | `false`         | Allow sprites to be rotated 90° to improve packing.                              |
| `min_width`              | int    | `16`            | Minimum page width in pixels.                                                    |
| `min_height`             | int    | `16`            | Minimum page height in pixels.                                                   |
| `max_width`              | int    | `2048`          | Maximum page width in pixels.                                                    |
| `max_height`             | int    | `2048`          | Maximum page height in pixels.                                                   |
| `square`                 | bool   | `false`         | Force every page to be square.                                                   |
| `strip_whitespace_x`     | bool   | `true`          | Strip transparent pixels from the left and right sides of sprites.               |
| `strip_whitespace_y`     | bool   | `true`          | Strip transparent pixels from the top and bottom sides of sprites.               |
| `alpha_threshold`        | int    | `0`             | Pixels with alpha ≤ this value are treated as fully transparent.                 |
| `filter_min`             | string | `"Linear"`      | Minification filter (`Linear`, `Nearest`, …).                                    |
| `filter_mag`             | string | `"Linear"`      | Magnification filter (`Linear`, `Nearest`, …).                                   |
| `wrap_x`                 | string | `"ClampToEdge"` | Horizontal wrap mode written to the atlas (`ClampToEdge`, `Repeat`, …).          |
| `wrap_y`                 | string | `"ClampToEdge"` | Vertical wrap mode written to the atlas (`ClampToEdge`, `Repeat`, …).            |
| `format`                 | string | `"RGBA8888"`    | Pixel format passed to the packer (e.g. `RGBA8888`, `RGB888`).                   |
| `alias`                  | bool   | `true`          | Pack pixel-identical images once; duplicates become aliases of the same region.  |
| `ignore_blank_images`    | bool   | `true`          | Skip fully transparent source images instead of adding an empty region.          |
| `fast`                   | bool   | `false`         | Pack much faster with less efficient page layouts.                               |
| `debug`                  | bool   | `false`         | Draw the bounds of every packed sprite onto the pages.                           |
| `silent`                 | bool   | `false`         | Suppress the packer's own progress output.                                       |
| `combine_subdirectories` | bool   | `true`          | Treat all subdirectories of `source_dir` as part of the same atlas.              |
| `flatten_paths`          | bool   | `false`         | Strip directory prefixes from sprite names in the atlas.                         |
| `premultiply_alpha`      | bool   | `false`         | Multiply RGB by alpha in the output pages.                                       |
| `use_indexes`            | bool   | `false`         | Append a numeric index to sprite names for animation frames.                     |
| `bleed`                  | bool   | `true`          | Extend the border pixels of sprites into the padding to avoid colour fringing.   |
| `bleed_iterations`       | int    | `2`             | Bleed passes; raise to 4 or 8 if downscaled sprites show dark fringes.           |
| `limit_memory`           | bool   | `true`          | Keep one source image in memory at a time (reads each twice).                    |
| `grid`                   | bool   | `false`         | Place sprites in a uniform grid, in order, instead of bin packing.               |
| `scale_resampling`       | string | `"bicubic"`     | Resampling algorithm used when downscaling (`bicubic`, `bilinear`, `nearest`).   |

Not exposed, because pano's pipeline depends on them: `scale`/`scaleSuffix` (driven by
`[atlases.variants]`), `outputFormat`/`jpegQuality` (pages are PNG end to end),
`atlasExtension`/`legacyOutput`/`prettyPrint` (the `.atlas` parser reads the legacy format)
and `ignore` (skips the whole source directory when set at the root).

### `[atlases.variants.<name>]`

Variants produce one scaled output per entry.
When no variants are declared the atlas is packed once at factor `1.0` directly into `target_dir`.
When variants are present each one writes into `<target_dir>/<variant-name>/`.

The `<name>` key is arbitrary and becomes the subdirectory name (e.g. `1x`, `2x`).

| Key      | Type  | Required | Description                                                                         |
| -------- | ----- | -------- | ----------------------------------------------------------------------------------- |
| `factor` | float | ✓        | Scale factor applied to the source images for this pass (e.g. `0.5` for half-size). |

### Annotated example

```toml
jar = "vendor/runnable-texturepacker.jar"
concurrency = 4

[[atlases]]
name       = "ui-resources"
source_dir = "assets/images/ui"
target_dir = "assets/textures"

# libGDX settings override (the whole table is optional, as is every key in it)
[atlases.gdx_settings]
max_width  = 4096
max_height = 4096
rotation   = true

[atlases.variants.1x]
factor = 0.5

[atlases.variants.2x]
factor = 1.0
```

Output layout for the example above:

```
assets/textures/
  1x/
    ui-resources-0.png          # half-size pages
    ui-resources.json           # Phaser multiatlas descriptor
  2x/
    ui-resources-0.png          # full-size pages
    ui-resources.json
```

Drop the `[atlases.variants.*]` tables and the atlas is packed once at factor `1.0`,
writing `ui-resources-0.png` and `ui-resources.json` straight into `assets/textures/`.

## License

Apache 2.0, see [LICENSE](LICENSE) for details.
