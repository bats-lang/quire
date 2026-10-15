(* The pieces counted in one array's cells, claimed to be the pieces of another's *)
fn _static_other_cells {l:agz}{n:pos}{cs,other:$A.cells}{offset,text_len:nat | offset + text_len <= n}
  (bytes: !$A.cborrow(l, n, cs), offset: int offset, text_len: int text_len): [count:pos] (PIECES(other, offset, text_len, count) | int count) =
  pieces_find(bytes, offset, text_len)
