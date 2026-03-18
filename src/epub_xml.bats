(* epub_xml -- helper for converting array regions to text *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use str as S

fun _arr_to_text_loop
  {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (src: !$A.arr(byte, l, n), len: int n,
   tb: $A.text_builder(n, i), pos: int i): $A.text_builder(n, n) =
  if pos >= len then tb
  else let
    val b = byte2int0($A.get<byte>(src, $AR.checked_idx(pos, len)))
    val tb = $A.text_putc(tb, pos, $AR.checked_byte(b))
  in _arr_to_text_loop(src, len, tb, pos + 1) end

#pub fn arr_to_text
  {l:agz}{n:pos}
  (src: !$A.arr(byte, l, n), len: int n): $A.text(n)

implement arr_to_text{l}{n}(src, len) = let
  val tb = $A.text_build(len)
  val tb = _arr_to_text_loop(src, len, tb, 0)
in $A.text_done(tb) end
