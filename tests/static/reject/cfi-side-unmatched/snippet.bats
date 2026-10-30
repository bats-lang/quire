(* The side bias of a location, with after left out: "[;s=a]" would be read
   as no bias (#901) *)
fn _static_side_said (side: cfi_side): string =
  case+ side of
  | CfiSideNone() => "none"
