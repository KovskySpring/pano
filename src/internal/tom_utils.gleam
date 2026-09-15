import tom

/// Treat an absent key as `fallback`, while still surfacing a key that is
/// present but of the wrong type.
pub fn recover_from_not_found(value: Result(a, tom.GetError), fallback: a) {
  case value {
    Error(tom.NotFound(_)) -> Ok(fallback)
    i -> i
  }
}
