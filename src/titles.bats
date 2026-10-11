(* titles -- a book's title as a sentence names it: in quotes, and cut
   when it is long (the Undo toast, the Empty Trash question) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

(* Where a cut of text[0, n) falls, at most at cut: the byte at the
   cut does not continue a character (UTF-8's 0x80 to 0xBF), so the cut
   never splits one *)
fun _whole_char {l:agz}{n:nat}{cut:nat | cut < n} .<cut>.
  (text: !$A.arr(byte, l, n), cut: int cut): [kept:nat | kept <= cut] int kept =
  if cut <= 0 then 0
  else let
    val next = byte2int0($A.get<byte>(text, cut))
  in
    if next >= 128 then (if next < 192 then _whole_char(text, cut - 1) else cut)
    else cut
  end

(* text[0, shown) at buffer[at, at + shown) *)
fun _copy_bytes {l:agz}{n:nat}{buffer_loc:agz}{size:nat}{shown:nat | shown <= n}{at:nat | at + shown <= size}{j:nat | j <= shown} .<shown - j>.
  (text: !$A.arr(byte, l, n), buffer: !$A.arr(byte, buffer_loc, size), at: int at, shown: int shown, j: int j): void =
  if j >= shown then ()
  else let val () = $A.set<byte>(buffer, at + j, $A.get<byte>(text, j)) in _copy_bytes(text, buffer, at, shown, j + 1) end

(* text[0, text_len) at buffer[at, at + text_len) *)
#pub fn bytes_put {l:agz}{n:nat}{buffer_loc:agz}{size:nat}{text_len:nat | text_len <= n}{at:nat | at + text_len <= size}
  (text: !$A.arr(byte, l, n), text_len: int text_len, buffer: !$A.arr(byte, buffer_loc, size), at: int at): int(at + text_len)

implement bytes_put (text, text_len, buffer, at) = let
  val () = _copy_bytes(text, buffer, at, text_len, 0)
in at + text_len end

(* The title title[0, title_len) in single quotes at buffer[at, at + 65): at
   most 60 bytes of it, cut at a whole character and followed by an
   ellipsis when it is longer, and "Untitled" for none. Answers where
   what it wrote ends *)
#pub fn title_put {l:agz}{title_len:nat | title_len < 256}{buffer_loc:agz}{size:nat}{at:nat | at + 65 <= size}
  (title: !$A.arr(byte, l, title_len + 1), title_len: int title_len, buffer: !$A.arr(byte, buffer_loc, size), at: int at)
  : [ended:nat | at < ended; ended <= at + 65] int ended

implement title_put (title, title_len, buffer, at) =
  if title_len <= 0 then let
    val () = $A.write_text(buffer, at, $A.text_lit("'Untitled'"), 10)
  in at + 10 end
  else if title_len <= 60 then let
    val () = $A.write_text(buffer, at, $A.text_lit("'"), 1)
    val () = _copy_bytes(title, buffer, at + 1, title_len, 0)
    val after = at + 1 + title_len
    val () = $A.write_text(buffer, after, $A.text_lit("'"), 1)
  in after + 1 end
  else let
    val () = $A.write_text(buffer, at, $A.text_lit("'"), 1)
    val shown = _whole_char(title, 60)
    val () = _copy_bytes(title, buffer, at + 1, shown, 0)
    val after = at + 1 + shown
    val () = $A.set<byte>(buffer, after, $A.int2byte(226))
    val () = $A.set<byte>(buffer, after + 1, $A.int2byte(128))
    val () = $A.set<byte>(buffer, after + 2, $A.int2byte(166))
    val () = $A.write_text(buffer, after + 3, $A.text_lit("'"), 1)
  in after + 4 end

end (* #target wasm *)
