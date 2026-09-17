import gleam/int
import gleam/result
import gleam/string
import simplifile

pub type AbsolutePath {
  AbsolutePath(raw: String)
}

pub type AnyPath {
  AnyPath(value: String)
  ResolvedPath(AbsolutePath)
}

const separator = "/"

pub fn join_nominal(
  base: AbsolutePath,
  nominal_fragments: List(String),
) -> AbsolutePath {
  AbsolutePath(
    base.raw <> separator <> string.join(nominal_fragments, separator),
  )
}

pub fn resolve(path: String) -> Result(AbsolutePath, String) {
  simplifile.resolve(path)
  |> result.map(AbsolutePath)
  |> result.replace_error(path)
}

pub fn resolve_dirname(path: String) -> Result(AbsolutePath, String) {
  simplifile.resolve(path)
  |> result.map(dirname)
  |> result.map(AbsolutePath)
  |> result.replace_error(path)
}

pub fn join_and_resolve(
  dir dir: AbsolutePath,
  path path: String,
) -> Result(AbsolutePath, String) {
  let combined = case path {
    "/" <> _ | "\\" <> _ -> path
    _ -> dir.raw <> separator <> path
  }

  resolve(combined)
  |> result.replace_error(path)
}

/// Return the directory name of `path`, or `.` if it has no directory component.
@external(erlang, "filename", "dirname")
pub fn dirname(path: String) -> String

/// The output filename for the `index`-th page of `name`, 0-based.
pub fn page_image_filename(name: String, index: Int) -> String {
  name <> "-" <> int.to_string(index) <> ".png"
}

/// The output filename for the Phaser multiatlas descriptor of `name`.
pub fn atlas_json_filename(name: String) -> String {
  name <> ".json"
}
