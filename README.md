# pano - Multi-threaded wrapper for libGDX's TexturePacker, outputting to Phaser 3 multiatlas.json

## Prerequisites

- Erlang/OTP 27+ (for running the `pano` escript). The install script checks this.
- A JVM (Java 8+) on `PATH` as `java` (for libGDX's TexturePacker).
- `runnable-texturepacker.jar` (for libGDX's TexturePacker). See [libGDX's TexturePacker](https://libgdx.com/wiki/tools/texture-packer).

## Installation

Run the install script to download the latest `pano` binaries and place it in `~/.local/bin/pano`
(or `$PANO_BIN_DIR/pano` if you set that environment variable). The script checks for Erlang/OTP 27+
and a JVM on `PATH`.

```sh
curl -fsSL https://raw.githubusercontent.com/KovskySpring/pano/main/scripts/install.sh | sh
```

Or, download the latest release from [GitHub](https://github.com/KovskySpring/pano/releases),
place it wherever you'd like to.

`pano` is a single escript with BEAM bytecode, as long as you have an `erlang` runtime installed,
it will run on any platform (Linux, macOS, Windows).

## Usage

All configuration lives in a `packs.toml` file.

```sh
# pack every atlas in ./packs.toml
pano

# explicit config location
pano --config=path/to/packs.toml

# view the help message
pano --help
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
Relative paths in the file always resolve against the directory that contains it.
TexturePacker itself is run from that directory too.

### Editor intellisense

[`./editors/schema.json`](editors/schema.json) documents the full shape of `packs.toml` and can be
wired up to editors that support JSON Schema for TOML for autocomplete, inline docs,
and validation.

### Top-level keys

| Key           | Type   | Required | Default | Description                                                                                                |
| ------------- | ------ | -------- | ------- | ---------------------------------------------------------------------------------------------------------- |
| `jar`         | string | ✓        | -       | Path to the runnable `texturepacker.jar`.                                                                  |
| `concurrency` | int    |          | `8`     | Maximum number of pack jobs run in parallel. Values below 1 are clamped to 1.                              |
| `timeout`     | int    |          | `30000` | Milliseconds a single pack job may run for before it is killed and reported as failed. Must be at least 1. |

Any [libGDX setting](#libgdx-settings) may also sit here, applying to every atlas.
Unknown keys are ignored.

> TOML puts bare keys into whichever table header precedes them, so root-level
> settings must be written **above** the first `[atlases.<name>]` header.

### `[atlases.<name>]`

Each `[atlases.<name>]` table defines one atlas to pack. The `<name>` key is the atlas
name, used as the base filename for all outputs (`<name>.json`, `<name>-0.png`, `<name>-1.png`, …).

| Key          | Type   | Required | Default | Description                                                              |
| ------------ | ------ | -------- | ------- | ------------------------------------------------------------------------ |
| `source_dir` | string | ✓        | -       | Directory containing the source images to pack.                          |
| `target_dir` | string | ✓        | -       | Root output directory for this atlas.                                    |
| `timeout`    | int    |          | root's  | Milliseconds one pack job of this atlas may run for. Must be at least 1. |

### Job timeouts

Every pack job runs with a deadline. `timeout` resolves the same way the libGDX
settings do:

```
variant → atlas → root → 30000 (30 seconds)
```

A job that exceeds its budget is killed and reported as a failure alongside any
other failed jobs, rather than hanging the whole run. Raise it for large atlases
downscaled at several factors; the packer is single-threaded per job and a
thousand-sprite source can take minutes.

When the deadline passes pano kills that job's JVM (`SIGKILL`), so a runaway
TexturePacker does not keep holding the cores the remaining jobs need. A job
wedged somewhere other than the packer is abandoned a few seconds later.

### libGDX settings

Every key below is optional and maps to a libGDX TexturePacker setting forwarded
verbatim to the packer. They are written as plain keys in one of three places:

| Where                                 | Applies to                  |
| ------------------------------------- | --------------------------- |
| the root of the file                  | every atlas                 |
| `[atlases.<name>]`                    | one atlas                   |
| `[atlases.<name>.variants.<variant>]` | one atlas at one scale pass |

Each key resolves independently, so an atlas that overrides `max_width` still inherits
the root's `rotation`:

```
variant → atlas → root → default
```

The `Default` column below is what a key resolves to when no layer sets it.

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

Note: The properties `scale` and `scaleSuffix` from GDX's Texture Packer are managed by `pano`'s
atlas variants so they are not exposed. `outputFormat` and `jpegQuality` are not supported yet.
`atlasExtension`, `legacyOutput`, `prettyPrint` are hidden because `pano` will always reads the
legacy format and writes to Phaser's multiatlas format.

### `[atlases.<name>.variants.<variant>]`

Variants produce one scaled output per entry.
When no variants are declared the atlas is packed once at factor `1.0` directly into `target_dir`.
When variants are present each one writes into `<target_dir>/<variant>/`.

The `<variant>` key is arbitrary and becomes the subdirectory name (e.g. `1x`, `2x`).

| Key            | Type   | Required | Description                                                                                                                 |
| -------------- | ------ | -------- | --------------------------------------------------------------------------------------------------------------------------- |
| `scale_factor` | number | ✓        | Scale factor applied to the source images for this pass (e.g. `0.5` for half-size). Int or float; `inf`/`nan` are rejected. |
| `timeout`      | int    |          | Milliseconds this pass may run for, overriding the atlas's. Must be at least 1.                                             |

Any [libGDX setting](#libgdx-settings) may also be listed here to override the atlas's
value for this pass only. Useful when a downscaled variant needs different limits, e.g.
a smaller `max_width` or more `bleed_iterations`.

### Annotated example

```toml
jar = "vendor/runnable-texturepacker.jar"
concurrency = 4
timeout     = 120_000

# Root-level libGDX settings, applying to every atlas below
bleed_iterations = 4
rotation         = true

[atlases.ui-resources]
source_dir = "assets/images/ui"
target_dir = "assets/textures"

# Overrides for this atlas; `bleed_iterations` and `rotation` still come from the root
max_width  = 4096
max_height = 4096

[atlases.ui-resources.variants.1x]
scale_factor = 0.5
timeout    = 240_000  # this pass downscales the most, so give it longer
max_width  = 2048   # overrides the atlas's 4096 for this pass only
max_height = 2048

[atlases.ui-resources.variants.2x]
scale_factor = 1.0  # inherits the atlas's settings whole
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

Drop the `[atlases.<name>.variants.*]` tables and the atlas is packed once at factor `1.0`,
writing `ui-resources-0.png` and `ui-resources.json` straight into `assets/textures/`.

## License

Apache 2.0, see [LICENSE](LICENSE) for details.
