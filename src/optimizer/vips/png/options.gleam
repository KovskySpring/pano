//// Raw libvips `pngsave` options - every field maps directly to a vips
//// option of the same name. All fields are `Option`; `None` means "let
//// vips use its own default" and the option is omitted from the encoded
//// string entirely.
////
//// Use `none()` as a blank base, override only the fields you need, then
//// call `to_vips_string` to produce the comma-separated key=value pairs
//// suitable for vips bracket-string notation (e.g. `output.png[Q=80,…]`).

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/string

/// libpng row-filter strategy (`VipsForeignPngFilter`).
pub type PngFilter {
  FilterNone
  FilterSub
  FilterUp
  FilterAvg
  FilterPaeth
  FilterAll
}

/// Metadata retention policy (`VipsForeignKeep`).
pub type Keep {
  KeepNone
  KeepExif
  KeepXmp
  KeepIptc
  KeepIcc
  KeepOther
  KeepGainmap
  KeepAll
}

pub type PngOptions {
  PngOptions(
    /// zlib compression level, 0–9. Higher = smaller file, slower.
    compression: Option(Int),
    /// Write as an interlaced (Adam7) PNG (requires full image in memory).
    interlace: Option(Bool),
    /// libpng row-filter strategy applied per row before compression.
    filter: Option(PngFilter),
    /// Quantise to an 8-bit palette (indexed) PNG via libimagequant.
    palette: Option(Bool),
    /// Quantisation quality, 1–100 (meaningful when `palette = Some(True)`).
    q: Option(Int),
    /// Dithering strength, 0.0–1.0 (meaningful when `palette = Some(True)`).
    dither: Option(Float),
    /// Output bit depth: 1, 2, 4, 8, or 16. Forwarded verbatim to vips.
    bitdepth: Option(Int),
    /// CPU effort for palette quantisation; higher = better quality, slower.
    effort: Option(Int),
    /// Which metadata blocks to retain on write.
    keep: Option(Keep),
    /// Background colour (RGBA or RGB components) used when flattening alpha.
    background: Option(List(Float)),
    /// Page height for multi-page saves, in pixels.
    page_height: Option(Int),
    /// Filesystem path to an ICC profile to embed in the output.
    profile: Option(String),
  )
}

pub fn none() -> PngOptions {
  PngOptions(
    compression: None,
    interlace: None,
    filter: None,
    palette: None,
    q: None,
    dither: None,
    bitdepth: None,
    effort: None,
    keep: None,
    background: None,
    page_height: None,
    profile: None,
  )
}

/// Encode `opts` as a comma-separated key=value string for vips bracket
/// notation. `None` fields are omitted entirely.
/// The returned string contains no leading or trailing comma.
///
/// Example output: `"compression=6,palette=true,Q=80,dither=0.5"`
pub fn to_vips_string(opts: PngOptions) -> String {
  let options = [
    option.map(opts.compression, int_pair("compression", _)),
    option.map(opts.interlace, bool_pair("interlace", _)),
    option.map(opts.filter, fn(f) { "filter=" <> filter_name(f) }),
    option.map(opts.palette, bool_pair("palette", _)),
    option.map(opts.q, int_pair("Q", _)),
    option.map(opts.dither, float_pair("dither", _)),
    option.map(opts.bitdepth, int_pair("bitdepth", _)),
    option.map(opts.effort, int_pair("effort", _)),
    option.map(opts.keep, fn(k) { "keep=" <> keep_name(k) }),
    option.map(opts.background, fn(bg) {
      "background=" <> string.join(list.map(bg, float.to_string), " ")
    }),
    option.map(opts.page_height, int_pair("page-height", _)),
    option.map(opts.profile, fn(p) { "profile=" <> p }),
  ]

  string.join(option.values(options), ",")
}

fn filter_name(f: PngFilter) -> String {
  case f {
    FilterNone -> "none"
    FilterSub -> "sub"
    FilterUp -> "up"
    FilterAvg -> "avg"
    FilterPaeth -> "paeth"
    FilterAll -> "all"
  }
}

fn keep_name(k: Keep) -> String {
  case k {
    KeepNone -> "none"
    KeepExif -> "exif"
    KeepXmp -> "xmp"
    KeepIptc -> "iptc"
    KeepIcc -> "icc"
    KeepOther -> "other"
    KeepGainmap -> "gainmap"
    KeepAll -> "all"
  }
}

fn int_pair(key: String, value: Int) -> String {
  key <> "=" <> int.to_string(value)
}

fn float_pair(key: String, value: Float) -> String {
  key <> "=" <> float.to_string(value)
}

fn bool_pair(key: String, value: Bool) -> String {
  let str_value = case value {
    True -> "true"
    False -> "false"
  }
  key <> "=" <> str_value
}
