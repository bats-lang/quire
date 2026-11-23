(* a walk of an outside text holds the proof of its cells (keyword: outside-text) *)
prfn _static_outside_cells {output,text:$A.cells}{count:int}
  (taken: OUTSIDE_TAKEN(output, text, count)): $BO.OUTSIDE_READ(output) = let
  prval OUTSIDE_TAKEN_of(from, _, _) = taken
in from end

(* an outside text matched whole and given back (keyword: outside-text) *)
fn _static_taken {cs:$A.cells} (taken: outside_taken(cs)): bool =
  case+ taken of
  | ~OutsideTaken(_, _, _, _ | owner, array, _) => let
      val () = text_give_back(owner, array)
    in true end
  | ~OutsideTakenAsIs(_, _, _, _ | owner, array, _) => let
      val () = text_give_back(owner, array)
    in true end
  | ~OutsideRefused(_, _ | ) => false
  | ~OutsideMalformed() => false
  | ~OutsideTooLarge() => false
