(* Two counts of the pieces of the same cells and text are claimed to differ *)
prfn _static_two_counts {cs:$A.cells}{offset:nat}{text_len:nat}{first,second:int}
  (first_proof: PIECES(cs, offset, text_len, first), second_proof: PIECES(cs, offset, text_len, second)): [first != second] void = ()
