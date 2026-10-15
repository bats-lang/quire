(* A cut after the byte 65 ("A"), claimed to be after white space *)
prfn _static_after_a_letter {cs:$A.cells}{offset:nat}
  (cell: $A.NTH(cs, offset + 65534, 65)): BREAKBACK(cs, offset, 65534, 65022, 65535) =
  BREAKBACK_white(cell, WHITE_space())
