(* The spine step of an identifier, with "not a spine step" left out: a
   chapter would be looked for in a spine item that is not named (#901) *)
fn _static_spine_item (step: cfi_spine_step): Int =
  case+ step of
  | ~CfiSpineItem(item) => item
