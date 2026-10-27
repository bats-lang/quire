(* Where steps point, with a place in an element that has no text there
   left out: it would be read as nowhere (#901) *)
fn _static_place_offset (place: cfi_place): Int =
  case+ place of
  | ~CfiElement(offset) => offset
  | ~CfiText(offset) => offset
  | ~CfiNoPlace() => 0
