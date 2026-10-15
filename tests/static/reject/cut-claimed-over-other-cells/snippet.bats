(* A cut found in some cells is claimed to be the cut of other cells *)
prfn _static_other_cells {cs,other:$A.cells}{offset:nat}{text_len,cut:int}
  (proof: CUTC(cs, offset, text_len, cut)): CUTC(other, offset, text_len, cut) = proof
