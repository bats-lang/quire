(* The one count: _text_pieces, which cuts by _text_cut *)
fn _static_count {l:agz}{n:pos}{offset,text_len:nat | offset + text_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len): int = let
  val (_ | count) = _text_pieces(data, offset, text_len)
in count end
