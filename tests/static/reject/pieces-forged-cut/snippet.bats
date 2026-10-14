(* Three pieces of a text of 100 bytes, which is one piece, with no cut to show for them *)
fn _static_no_cut (): [count:pos] (PIECES(0, 100, count) | int count) = (PiecesLast() | 3)
