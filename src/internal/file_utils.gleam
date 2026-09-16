import gleam/result
import simplifile
import snag

pub fn with_snag_error(
  context context: String,
  outcome outcome: Result(a, simplifile.FileError),
) -> snag.Result(a) {
  outcome
  |> result.map_error(simplifile.describe_error)
  |> result.map_error(snag.new)
  |> snag.context(context)
}
