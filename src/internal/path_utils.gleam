import filepath
import gleam/int
import gleam/result

/// Resolve a config-relative `path` against `base_dir`, normalising away `.`
/// and `..`. An absolute `path`, or an empty `base_dir`, is returned as-is.
///
/// A `path` with more `..` segments than `base_dir` has parents would escape
/// the config's own directory; that is an `Error` holding the offending path.
pub fn resolve(base_dir: String, path: String) -> Result(String, String) {
  case base_dir == "" || filepath.is_absolute(path) {
    True -> Ok(path)
    False ->
      filepath.join(base_dir, path)
      |> filepath.expand
      |> result.replace_error(path)
  }
}

/// The output filename for the `index`-th page of `name`, 0-based.
pub fn page_image_filename(name: String, index: Int) -> String {
  name <> "-" <> int.to_string(index) <> ".png"
}

/// The output filename for the Phaser multiatlas descriptor of `name`.
pub fn atlas_json_filename(name: String) -> String {
  name <> ".json"
}
