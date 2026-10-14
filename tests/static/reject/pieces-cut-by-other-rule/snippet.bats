(* A step of any other length than _text_cut's (65533, as _skip_spans took) has no CUT proof *)
fn _static_old_skip (): [count:pos] (PIECES(0, 131069, count) | int count) =
  (PiecesMore(CutOf(), PiecesLast()) | 2)
