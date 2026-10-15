(* A cut after white space that is the cell before the one looked at *)
prfn _static_another_cell {cs:$A.cells}{offset:nat}
  (cell: $A.NTH(cs, offset + 65533, 32)): BREAKBACK(cs, offset, 65534, 65022, 65535) =
  BREAKBACK_white(cell, WHITE_space())
