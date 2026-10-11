(* locator -- where a place is, as a reader is told it beside a chapter's
   hit or contents entry (#381, #383). A page number depends on the font
   and the columns and is unknown for a chapter that is not laid out, so
   a place is what stays the same when the layout changes, as Kindle's
   Location does: how far into the book it is, in thousandths by the
   chapters' sizes (the footer's "% of book"), or, in a fixed-layout book,
   where a spine item is a page, that page. There is no empty case. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use str as S

(* A locator is a kind and a number, a flat pair (a constructor carrying
   data would make it linear, and a hit's is set after the hit is made):
   ByPage, the page, or ByPercent, the thousandths of the book *)
#pub datatype locator_kind =
  | ByPage
  | ByPercent

(* The thousandth of the book at a size position, of its total: the one
   rule behind the footer, the scrubber, Contents and the search results *)
#pub fn locator_thousandth (position: Int, total: Int): [thousandth:nat | thousandth <= 1000] int thousandth

implement locator_thousandth (position, total) = let
  fn clamp (value: Int): [clamped:nat | clamped <= 1000] int clamped =
    if value <= 0 then 0 else if value >= 1000 then 1000 else value
in
  if total <= 0 then 0
  (* position * 1000 fits an int *)
  else if total < 2000000 then clamp(position * 1000 / total)
  else clamp(position / (total / 1000))
end

fun _put_text {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (buf: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.set<byte>(buf, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_text(buf, at, text, text_len, i + 1) end

(* A locator's words at buf[at, end_at): "p. 12", "34%", or "<1%" for
   less than a percent of the book, "0%" at its very start *)
#pub fn locator_put {l:agz}{at:nat | at <= 5}
  (buf: !$A.arr(byte, l, 32), at: int at, kind: locator_kind, number: Int): [end_at:nat | end_at <= at + 14] int end_at

implement locator_put (buf, at, kind, number) =
  case+ kind of
  | ByPage() => let
      val offset = _put_text(buf, at, "p. ", 3, 0)
    in $S.int_to_str(buf, offset, 32, (if number > 0 then number else 0): Nat) end
  | ByPercent() =>
    if number >= 10 then let
      val offset = $S.int_to_str(buf, at, 32, (if number <= 1000 then number / 10 else 100): Nat)
    in _put_text(buf, offset, "%", 1, 0) end
    else if number > 0 then _put_text(buf, at, "<1%", 3, 0)
    else _put_text(buf, at, "0%", 2, 0)
