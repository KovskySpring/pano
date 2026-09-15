import gleam/float
import gleam/int
import tom

/// Parse a toml number into a finite float.
///
/// tom parses float literals with accumulating arithmetic, so `0.3472`
/// arrives as the drifted double 0.34720000000000006. Rounding back to
/// 10 decimal places recovers the intended value exactly for any
/// human-authored factor.
pub fn to_finite_float(number: tom.Number) -> Result(Float, tom.Number) {
  case number {
    tom.NumberFloat(value) -> Ok(float.to_precision(value, 10))
    tom.NumberInt(value) -> Ok(int.to_float(value))
    tom.NumberInfinity(_) -> Error(number)
    tom.NumberNan(_) -> Error(number)
  }
}

pub fn tom_number_to_string(num: tom.Number) -> String {
  case num {
    tom.NumberInt(i) -> int.to_string(i)
    tom.NumberFloat(f) -> float.to_string(f)
    tom.NumberInfinity(tom.Positive) -> "inf"
    tom.NumberInfinity(tom.Negative) -> "inf"
    tom.NumberNan(_) -> "nan"
  }
}
