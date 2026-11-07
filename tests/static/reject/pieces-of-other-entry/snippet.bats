(* The pieces of the texts of two entries are claimed to be counted alike *)
prfn _static_other_entry {kind:$Z.inflate_kind}{first_compressed,second_compressed,first_text,second_text:$A.cells}{first_count,second_count:nat}
  {offset,text_len:nat | offset + text_len <= first_count}{first,second:int}
  (first_taken: TAKEN(kind, first_compressed, first_text, first_count), second_taken: TAKEN(kind, second_compressed, second_text, second_count),
   first_pieces: PIECES(first_text, offset, text_len, first), second_pieces: PIECES(second_text, offset, text_len, second)): [first == second] void =
  pieces_of_taken_functional(first_taken, second_taken, first_pieces, second_pieces)
