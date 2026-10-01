(* entity -- XHTML text with its character references decoded *)

(* A book's text is XML, so "&amp;", "&#233;" and the like stand for
   characters. They are decoded here into UTF-8: the five XML entities,
   the common HTML ones and numeric references. Anything else, or an
   ill-formed reference, is kept as it is. A decoded reference is never
   longer than its source, so the text never grows. *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

staload "epub_xml.sats"

(* The bytes UTF-8 needs for code_point *)
fn _utf8_len (code_point: int): int =
  if code_point < 128 then 1 else if code_point < 2048 then 2 else if code_point < 65536 then 3 else 4

(* A reference found at data[offset + start]: its length ref_len (from
   '&' to ';') and the code point it stands for, which encodes in no more bytes than
   that; or none *)
datavtype ref_hit(text_len:int, start:int) =
  | {ref_len:pos | start + ref_len <= text_len}{code_point:nat | code_point < 1114112} RefHit(text_len, start) of (int ref_len, int code_point)
  | RefMiss(text_len, start) of ()

(* The value of the hex digit digit_byte, or -1 *)
fn _hex_value (digit_byte: Int): Int =
  if digit_byte >= 48 then (if digit_byte <= 57 then digit_byte - 48
    else if digit_byte >= 97 then (if digit_byte <= 102 then digit_byte - 87 else ~1)
    else if digit_byte >= 65 then (if digit_byte <= 70 then digit_byte - 55 else ~1) else ~1)
  else ~1

(* The number in data[offset + position, offset + stop) in base 16
   (hex) or 10, from total:
   -1 when a byte is no digit or it exceeds U+10FFFF *)
fun _number {l:agz}{n:pos}{offset,stop:nat | offset + stop <= n}{position:nat | position <= stop} .<stop - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, position: int position, stop: int stop, hex: bool, total: Int): Int =
  if position >= stop then total
  else let
    val digit_byte = $AR.low_byte(byte2int0($A.read<byte>(data, offset + position)))
    val digit = (if hex then _hex_value(digit_byte) else if digit_byte >= 48 then (if digit_byte <= 57 then digit_byte - 48 else ~1) else ~1): Int
  in
    if digit < 0 then ~1
    else let
      val value = (if hex then total * 16 + digit else total * 10 + digit): Int
    in if value > 1114111 then ~1 else _number(data, offset, position + 1, stop, hex, value) end
  end

(* The code point of the named reference
   data[offset + name_start, offset + name_end), or -1 *)
fn _named {l:agz}{n:pos}{offset,name_start,name_end:nat | name_start <= name_end; offset + name_end <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, name_start: int name_start, name_end: int name_end): Int = let
  fn name_is {pattern_len:pos} (data: !$A.borrow(byte, l, n), pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool =
    xml_name_eq(data, offset + name_start, name_end - name_start, pattern, pattern_len)
  var amp = @[char][3]('a', 'm', 'p')
  var lt = @[char][2]('l', 't')
  var gt = @[char][2]('g', 't')
  var quot = @[char][4]('q', 'u', 'o', 't')
  var apos = @[char][4]('a', 'p', 'o', 's')
  var nbsp = @[char][4]('n', 'b', 's', 'p')
  var mdash = @[char][5]('m', 'd', 'a', 's', 'h')
  var ndash = @[char][5]('n', 'd', 'a', 's', 'h')
  var hellip = @[char][6]('h', 'e', 'l', 'l', 'i', 'p')
  var lsquo = @[char][5]('l', 's', 'q', 'u', 'o')
  var rsquo = @[char][5]('r', 's', 'q', 'u', 'o')
  var ldquo = @[char][5]('l', 'd', 'q', 'u', 'o')
  var rdquo = @[char][5]('r', 'd', 'q', 'u', 'o')
  var laquo = @[char][5]('l', 'a', 'q', 'u', 'o')
  var raquo = @[char][5]('r', 'a', 'q', 'u', 'o')
  var copy = @[char][4]('c', 'o', 'p', 'y')
  var reg = @[char][3]('r', 'e', 'g')
  var trade = @[char][5]('t', 'r', 'a', 'd', 'e')
  var shy = @[char][3]('s', 'h', 'y')
  var middot = @[char][6]('m', 'i', 'd', 'd', 'o', 't')
  var bull = @[char][4]('b', 'u', 'l', 'l')
  var sect = @[char][4]('s', 'e', 'c', 't')
  var deg = @[char][3]('d', 'e', 'g')
  var eacute = @[char][6]('e', 'a', 'c', 'u', 't', 'e')
  var egrave = @[char][6]('e', 'g', 'r', 'a', 'v', 'e')
  var aacute = @[char][6]('a', 'a', 'c', 'u', 't', 'e')
  var agrave = @[char][6]('a', 'g', 'r', 'a', 'v', 'e')
  var ccedil = @[char][6]('c', 'c', 'e', 'd', 'i', 'l')
  var ouml = @[char][4]('o', 'u', 'm', 'l')
  var uuml = @[char][4]('u', 'u', 'm', 'l')
  var auml = @[char][4]('a', 'u', 'm', 'l')
  var szlig = @[char][5]('s', 'z', 'l', 'i', 'g')
  var thinsp = @[char][6]('t', 'h', 'i', 'n', 's', 'p')
  var ensp = @[char][4]('e', 'n', 's', 'p')
  var emsp = @[char][4]('e', 'm', 's', 'p')
in
  if name_is(data, amp, 3) then 38 else if name_is(data, lt, 2) then 60
  else if name_is(data, gt, 2) then 62 else if name_is(data, quot, 4) then 34
  else if name_is(data, apos, 4) then 39 else if name_is(data, nbsp, 4) then 160
  else if name_is(data, mdash, 5) then 8212 else if name_is(data, ndash, 5) then 8211
  else if name_is(data, hellip, 6) then 8230 else if name_is(data, lsquo, 5) then 8216
  else if name_is(data, rsquo, 5) then 8217 else if name_is(data, ldquo, 5) then 8220
  else if name_is(data, rdquo, 5) then 8221 else if name_is(data, laquo, 5) then 171
  else if name_is(data, raquo, 5) then 187 else if name_is(data, copy, 4) then 169
  else if name_is(data, reg, 3) then 174 else if name_is(data, trade, 5) then 8482
  else if name_is(data, shy, 3) then 173 else if name_is(data, middot, 6) then 183
  else if name_is(data, bull, 4) then 8226 else if name_is(data, sect, 4) then 167
  else if name_is(data, deg, 3) then 176 else if name_is(data, eacute, 6) then 233
  else if name_is(data, egrave, 6) then 232 else if name_is(data, aacute, 6) then 225
  else if name_is(data, agrave, 6) then 224 else if name_is(data, ccedil, 6) then 231
  else if name_is(data, ouml, 4) then 246 else if name_is(data, uuml, 4) then 252
  else if name_is(data, auml, 4) then 228 else if name_is(data, szlig, 5) then 223
  else if name_is(data, thinsp, 6) then 8201 else if name_is(data, ensp, 4) then 8194
  else if name_is(data, emsp, 4) then 8195
  else ~1
end

(* The first ';' in data[offset + position, offset + stop), or stop *)
fun _semicolon {l:agz}{n:pos}{offset,stop:nat | offset + stop <= n}{position:nat | position <= stop} .<stop - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, position: int position, stop: int stop): [found:nat | position <= found; found <= stop] int found =
  if position >= stop then stop
  else if byte2int0($A.read<byte>(data, offset + position)) = 59 then position
  else _semicolon(data, offset, position + 1, stop)

(* The reference at data[offset + start] (a '&'), within
   data[offset, offset + text_len) *)
fn _reference {l:agz}{n:pos}{offset,text_len:nat | offset + text_len <= n}{start:nat | start < text_len}
  (data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len, start: int start): ref_hit(text_len, start) = let
  (* a reference is at most 12 bytes long *)
  val stop = (if start + 12 < text_len then start + 12 else text_len): [stop:int | start < stop; stop <= text_len] int stop
  val semicolon = _semicolon(data, offset, start + 1, stop)
in
  if semicolon >= stop then RefMiss()
  else if semicolon <= start + 1 then RefMiss()
  else let
    val ref_len = semicolon + 1 - start
    val code_point = (if byte2int0($A.read<byte>(data, offset + start + 1)) = 35 then
        (if semicolon > start + 2 then
           (if $AR.bor_int_int(byte2int0($A.read<byte>(data, offset + start + 2)), 32) = 120 then
              (if semicolon > start + 3 then _number(data, offset, start + 3, semicolon, true, 0) else ~1)
            else _number(data, offset, start + 2, semicolon, false, 0))
         else ~1)
      else _named(data, offset, start + 1, semicolon)): Int
  in
    (* no NUL, no surrogate, and no longer than its source *)
    if code_point <= 0 then RefMiss()
    else if code_point > 1114111 then RefMiss()
    else if (if code_point >= 55296 then code_point <= 57343 else false) then RefMiss()
    else if _utf8_len(code_point) > ref_len then RefMiss()
    else RefHit(ref_len, code_point)
  end
end

(* code_point as UTF-8 at out[write_at], in utf8_len bytes *)
fn _put_utf8 {l:agz}{out_size:nat}{write_at:nat}{utf8_len:int | utf8_len >= 1; utf8_len <= 4; write_at + utf8_len <= out_size}
  (out: !$A.arr(byte, l, out_size), write_at: int write_at, code_point: int, utf8_len: int utf8_len): void =
  if utf8_len = 1 then $A.set<byte>(out, write_at, $A.int2byte($AR.low_byte(code_point)))
  else if utf8_len = 2 then let
    val () = $A.set<byte>(out, write_at, $A.int2byte($AR.low_byte(192 + code_point / 64)))
  in $A.set<byte>(out, write_at + 1, $A.int2byte($AR.low_byte(128 + code_point - (code_point / 64) * 64))) end
  else if utf8_len = 3 then let
    val () = $A.set<byte>(out, write_at, $A.int2byte($AR.low_byte(224 + code_point / 4096)))
    val () = $A.set<byte>(out, write_at + 1, $A.int2byte($AR.low_byte(128 + (code_point / 64) - (code_point / 4096) * 64)))
  in $A.set<byte>(out, write_at + 2, $A.int2byte($AR.low_byte(128 + code_point - (code_point / 64) * 64))) end
  else let
    val () = $A.set<byte>(out, write_at, $A.int2byte($AR.low_byte(240 + code_point / 262144)))
    val () = $A.set<byte>(out, write_at + 1, $A.int2byte($AR.low_byte(128 + (code_point / 4096) - (code_point / 262144) * 64)))
    val () = $A.set<byte>(out, write_at + 2, $A.int2byte($AR.low_byte(128 + (code_point / 64) - (code_point / 4096) * 64)))
  in $A.set<byte>(out, write_at + 3, $A.int2byte($AR.low_byte(128 + code_point - (code_point / 64) * 64))) end

(* The UTF-8 length of code_point, as a static bound: no more than
   ref_len *)
fn _utf8_len_within {ref_len:pos} (code_point: int, ref_len: int ref_len): [utf8_len:int | utf8_len >= 1; utf8_len <= 4; utf8_len <= ref_len] int utf8_len = let
  val utf8_len = _utf8_len(code_point)
in
  if utf8_len <= 1 then 1
  else if utf8_len = 2 then (if ref_len >= 2 then 2 else 1)
  else if utf8_len = 3 then (if ref_len >= 3 then 3 else 1)
  else if ref_len >= 4 then 4 else 1
end

fun _decode {data_loc,out_loc:agz}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size}{out_size:nat | text_len <= out_size}{read_at:nat | read_at <= text_len}{write_at:nat | write_at <= read_at} .<text_len - read_at>.
  (data: !$A.borrow(byte, data_loc, data_size), offset: int offset, text_len: int text_len, read_at: int read_at,
   out: !$A.arr(byte, out_loc, out_size), write_at: int write_at): [decoded_len:nat | decoded_len <= text_len] int decoded_len =
  if read_at >= text_len then write_at
  else let
    val next_byte = $A.read<byte>(data, offset + read_at)
  in
    if byte2int0(next_byte) <> 38 then let
      val () = $A.set<byte>(out, write_at, next_byte)
    in _decode(data, offset, text_len, read_at + 1, out, write_at + 1) end
    else (case+ _reference(data, offset, text_len, read_at) of
      | ~RefMiss() => let
          val () = $A.set<byte>(out, write_at, next_byte)
        in _decode(data, offset, text_len, read_at + 1, out, write_at + 1) end
      | ~RefHit(ref_len, code_point) => let
          val utf8_len = _utf8_len_within(code_point, ref_len)
          val () = _put_utf8(out, write_at, code_point, utf8_len)
        in _decode(data, offset, text_len, read_at + ref_len, out, write_at + utf8_len) end)
  end

(* out[0, decoded_len) := data[offset, offset + text_len) with its
   references decoded; decoded_len <= text_len *)
#pub fn decode_text {data_loc,out_loc:agz}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size}{out_size:nat | text_len <= out_size}
  (data: !$A.borrow(byte, data_loc, data_size), offset: int offset, text_len: int text_len, out: !$A.arr(byte, out_loc, out_size)): [decoded_len:nat | decoded_len <= text_len] int decoded_len

implement decode_text (data, offset, text_len, out) = _decode(data, offset, text_len, 0, out, 0)

(* Whether data[offset, offset + text_len) has a '&' at or after
   position *)
fun _has_ampersand {l:agz}{n:pos}{offset,text_len:nat | offset + text_len <= n}{position:nat | position <= text_len} .<text_len - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len, position: int position): bool =
  if position >= text_len then false
  else if byte2int0($A.read<byte>(data, offset + position)) = 38 then true
  else _has_ampersand(data, offset, text_len, position + 1)

#pub fn has_reference {l:agz}{n:pos}{offset,text_len:nat | offset + text_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len): bool

implement has_reference (data, offset, text_len) = _has_ampersand(data, offset, text_len, 0)
