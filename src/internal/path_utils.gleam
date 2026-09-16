import filepath
import gleam/int
import gleam/result

fn resolve_base_dir(base_dir: String) -> Result(String, String) {
  case base_dir {
    "" -> Error(base_dir)
    path ->
      case filepath.is_absolute(path) {
        True -> Ok(path)
        False ->
          filepath.expand(path)
          |> result.replace_error(path)
      }
  }
}

pub fn resolve(base_dir: String, path: String) -> Result(String, String) {
  case filepath.is_absolute(path) {
    True -> Ok(path)
    False -> {
      use resolved_base_dir <- result.try(resolve_base_dir(base_dir))
      resolved_base_dir
      |> filepath.join(path)
      |> filepath.expand
      |> result.replace_error(path)
    }
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
