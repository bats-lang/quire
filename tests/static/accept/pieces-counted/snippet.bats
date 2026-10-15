(* The one count: pieces_find, which cuts by cut_find over the text's cells *)
fn _static_count {l:agz}{n:pos}{cs:$A.cells}{offset,text_len:nat | offset + text_len <= n}
  (bytes: !$A.cborrow(l, n, cs), offset: int offset, text_len: int text_len): int = let
  val (_ | count) = pieces_find(bytes, offset, text_len)
in count end
