//// Output format descriptions for the atlas re-encoder.

import optimizer/vips/png/options as png_options

/// Supported output formats. Each constructor carries the full option record
/// for its encoder so the rest of the pipeline stays format-agnostic.
pub type Format {
  /// PNG via libvips `pngsave`. Options map 1-to-1 to vips fields;
  /// `None` on any option defers to vips' own default.
  Png(options: png_options.PngOptions)
}
