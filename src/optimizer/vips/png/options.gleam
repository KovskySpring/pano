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
import gleam/option.{type Option, None, Some}
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
    /// vips defaults to 6.
    compression: Option(Int),
    /// Write as an interlaced (Adam7) PNG (requires the full image in
    /// memory). vips defaults to `false`.
    interlace: Option(Bool),
    /// libpng row-filter flags applied per row before compression. A set:
    /// encoded as `filter=sub:up`. `FilterNone` is absorbing.
    /// vips defaults to `none`.
    filter: Option(List(PngFilter)),
    /// Quantise to a palette (indexed) PNG via libimagequant.
    /// vips defaults to `false`.
    palette: Option(Bool),
    /// Quantisation quality, 0–100 (meaningful when `palette = Some(True)`).
    /// vips defaults to 100.
    q: Option(Int),
    /// Dithering strength, 0.0–1.0 (meaningful when `palette = Some(True)`).
    /// vips defaults to 1.0.
    dither: Option(Float),
    /// Output bit depth. vips accepts only 1, 2, 4, 8 or 16 and errors on any
    /// other value rather than clamping. vips defaults to 8.
    bitdepth: Option(Int),
    /// CPU effort for palette quantisation, 1–10. Higher = better quality,
    /// slower. vips defaults to 7.
    effort: Option(Int),
    /// Which metadata blocks to retain on write. A set: encoded as
    /// `keep=exif:icc`. `KeepNone` and `KeepAll` are absorbing.
    /// vips defaults to is every block.
    keep: Option(List(Keep)),
    /// Background colour (RGBA or RGB components) used when flattening alpha.
    background: Option(List(Float)),
    /// Page height for multi-page saves, in pixels, 0–100000000.
    /// vips defaults to 0.
    page_height: Option(Int),
    /// ICC profile to embed: either a built-in name (`srgb`, `p3`, `cmyk`) or
    /// a filesystem path to a profile.
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
    flags("filter", opts.filter, filter_name),
    option.map(opts.palette, bool_pair("palette", _)),
    option.map(opts.q, int_pair("Q", _)),
    option.map(opts.dither, float_pair("dither", _)),
    option.map(opts.bitdepth, int_pair("bitdepth", _)),
    option.map(opts.effort, int_pair("effort", _)),
    flags("keep", opts.keep, keep_name),
    option.map(opts.background, fn(bg) {
      "background=" <> string.join(list.map(bg, float.to_string), " ")
    }),
    option.map(opts.page_height, int_pair("page-height", _)),
    option.map(opts.profile, fn(p) { "profile=" <> p }),
  ]

  string.join(option.values(options), ",")
}

fn flags(
  key: String,
  values: Option(List(a)),
  name: fn(a) -> String,
) -> Option(String) {
  case values {
    None | Some([]) -> None
    Some(values) -> Some(key <> "=" <> string.join(list.map(values, name), ":"))
  }
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

/// Every `VipsForeignPngFilter` flag name, for error messages.
pub const filter_names = ["none", "sub", "up", "avg", "paeth", "all"]

/// Parse a `VipsForeignPngFilter` flag name, the inverse of `filter_name`.
pub fn filter_from_name(name: String) -> Result(PngFilter, Nil) {
  case name {
    "none" -> Ok(FilterNone)
    "sub" -> Ok(FilterSub)
    "up" -> Ok(FilterUp)
    "avg" -> Ok(FilterAvg)
    "paeth" -> Ok(FilterPaeth)
    "all" -> Ok(FilterAll)
    _ -> Error(Nil)
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

/// Every `VipsForeignKeep` flag name, for error messages.
pub const keep_names = [
  "none", "exif", "xmp", "iptc", "icc", "other", "gainmap", "all",
]

/// Parse a `VipsForeignKeep` flag name, the inverse of `keep_name`.
pub fn keep_from_name(name: String) -> Result(Keep, Nil) {
  case name {
    "none" -> Ok(KeepNone)
    "exif" -> Ok(KeepExif)
    "xmp" -> Ok(KeepXmp)
    "iptc" -> Ok(KeepIptc)
    "icc" -> Ok(KeepIcc)
    "other" -> Ok(KeepOther)
    "gainmap" -> Ok(KeepGainmap)
    "all" -> Ok(KeepAll)
    _ -> Error(Nil)
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
