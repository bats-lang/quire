(* The spine step of an identifier, both answers matched *)
fn _static_spine_item (step: cfi_spine_step): Int =
  case+ step of
  | ~CfiSpineItem(item) => item
  | ~CfiNotSpine() => ~1
