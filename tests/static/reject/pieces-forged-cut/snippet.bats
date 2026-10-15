(* Three pieces of a text of 100 bytes, which is one piece, with no cut to show for them *)
fn _static_no_cut {cs:$A.cells}{offset:nat} (): [count:pos] (PIECES(cs, offset, 100, count) | int count) = (PIECES_last() | 3)
