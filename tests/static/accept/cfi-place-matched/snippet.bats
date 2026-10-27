(* Where steps point, every place matched *)
fn _static_place_offset (place: cfi_place): Int =
  case+ place of
  | ~CfiElement(offset) => offset
  | ~CfiText(offset) => offset
  | ~CfiEmptyText(offset) => offset
  | ~CfiNoPlace() => 0
