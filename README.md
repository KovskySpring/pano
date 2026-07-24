# texture_packer

Multi-scale headless texture packing for the game's Phaser runtime.

For each atlas it packs the full-resolution source art once per output scale
with the headless libGDX `runnable-texturepacker.jar`, converts the libGDX
`.atlas` output to the Phaser multipack JSON the runtime already consumes
(`load.multiatlas`), and writes `<name>.png` + `<name>.json` into
`<target_dir>/<scale>/`.

## Usage

All configuration — paths, concurrency, scales, and the atlas registry —
lives in a `packs.toml` file, found in the current directory
by default:

```sh
gleam run                              # pack every atlas in ./packs.toml
gleam run -- --config=path/packs.toml  # explicit config location
```

Environment overrides: `GDX_OUT_ROOT` replaces every atlas's `target_dir`,
`GDX_CONCURRENCY` replaces `concurrency`.

## packs.toml schema

Relative paths resolve against the config file's directory.

```toml
jar = "path/to/texturepacker.jar"     # required
concurrency = 8                       # optional, default 8

[[atlases]]                           # at least one
name = "default-resources"            # required
source_dir = "images/default"         # required, the source image directory
target_dir = "textures"               # required, output root for this atlas
scales = [                            # required, at least one entry:
  { dir = "1x", factor = 0.3472 },    # `dir` = output subdirectory under
]                                     # target_dir, `factor` = downscale
                                      # factor (1.0 = full res)
indexed = true                        # optional, default true: page filenames
                                      # carry a -<index> suffix

# Optional libGDX TexturePacker overrides, all defaulting to the values
# below. See `src/cli/settings.gleam` for what each one does.
pot = false
padding_x = 2
padding_y = 2
edge_padding = true
duplicate_padding = true
rotation = false
strip_whitespace_x = true
strip_whitespace_y = true
alpha_threshold = 0
filter_min = "Linear"
filter_mag = "Linear"
format = "RGBA8888"
max_width = 2048
max_height = 2048
combine_subdirectories = true
flatten_paths = false
use_indexes = false
bleed = true
scale_resampling = "bicubic"
```

## Development

```sh
gleam test              # unit + birdie snapshot tests
gleam run -m birdie     # review changed snapshots
```
