(* Two cuts of the same cells and offset are claimed to differ *)
prfn _static_two_lengths {cs:$A.cells}{offset:nat}{text_len,first,second:int}
  (first_proof: CUTC(cs, offset, text_len, first), second_proof: CUTC(cs, offset, text_len, second)): [first != second] void = ()
