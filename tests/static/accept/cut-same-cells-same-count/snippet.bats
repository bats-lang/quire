(* Two counts of the pieces of one text, over the same cells, are equal *)
fn _static_same_count {l:agz}{n:pos}{cs:$A.cells}{offset,text_len:nat | offset + text_len <= n}
  (cells: !$A.cborrow(l, n, cs), offset: int offset, text_len: int text_len): [count:pos] (PIECES(cs, offset, text_len, count) | int count) = let
  val (first_proof | first) = pieces_find(cells, offset, text_len)
  val (second_proof | second) = pieces_find(cells, offset, text_len)
  prval () = pieces_functional(first_proof, second_proof)
in (first_proof | first) end
