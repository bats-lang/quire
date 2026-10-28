(* The side bias of a location, every side matched *)
fn _static_side_said (side: cfi_side): string =
  case+ side of
  | CfiSideNone() => "none"
  | CfiSideBefore() => "before"
  | CfiSideAfter() => "after"
