import gleam/result
import simplifile
import snag

/// Turn a `simplifile` failure into a `snag` carrying what was being attempted,
/// so the error reads as `<doing>: <reason>` rather than a bare file error.
pub fn context(
  outcome: Result(a, simplifile.FileError),
  while doing: String,
) -> snag.Result(a) {
  result.map_error(outcome, fn(error) {
    snag.new(doing <> ": " <> simplifile.describe_error(error))
  })
}
