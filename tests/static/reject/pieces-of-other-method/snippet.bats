(* The pieces of the texts of one entry taken by two methods (stored and deflated) are claimed to be counted alike *)
prfn _static_other_method {compressed,first_text,second_text:$A.cells}{first_count,second_count:nat}
  {offset,text_len:nat | offset + text_len <= first_count}{first,second:int}
  (first_taken: TAKEN($Z.inflate_stored(), compressed, first_text, first_count), second_taken: TAKEN($Z.inflate_deflated(), compressed, second_text, second_count),
   first_pieces: PIECES(first_text, offset, text_len, first), second_pieces: PIECES(second_text, offset, text_len, second)): [first == second] void =
  pieces_of_taken_functional(first_taken, second_taken, first_pieces, second_pieces)
