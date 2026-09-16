import tom

pub fn with_fallback(value: Result(a, tom.GetError), fallback: a) {
  case value {
    Error(tom.NotFound(_)) -> Ok(fallback)
    i -> i
  }
}
