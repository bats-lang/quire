(* A piece is lent as a barr, frozen, and its cut found from its cells while the
   plain borrow of the same bytes is read through the view *)
fn _static_cut_found {l:agz}{n:pos}{owner:addr}{offset,text_len:nat | offset + text_len <= n; text_len >= 65536}
  (piece: $A.arrx(byte, l, n, owner), offset: int offset, text_len: int text_len, n: int n)
  : @($A.arrx(byte, l, n, owner), int) = let
  val (cells_len, lent | lent_bytes) = $A.barr_of_arrx(piece)
  val @(frozen, cells) = $A.barr_freeze(lent_bytes)
  val view = $A.cborrow_view(frozen, cells)
  val (cut_proof | cut) = cut_find(cells, offset, text_len)
  val first = $A.read<byte>(view, offset)
  val () = $A.cborrow_view_drop(frozen, view)
  val () = $A.cborrow_drop(frozen, cells)
  val piece = $A.barr_to_arrx(lent | $A.barr_thaw(frozen))
in @(piece, cut + byte2int0(first)) end
