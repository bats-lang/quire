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

(* The bytes UTF-8 needs for code point c *)
fn _enc_len (c: int): int =
  if c < 128 then 1 else if c < 2048 then 2 else if c < 65536 then 3 else 4

(* A reference found at data[o + i]: its length (from '&' to ';') and
   the code point it stands for, which encodes in no more bytes than
   that; or none *)
datavtype ref_hit(k:int, i:int) =
  | {l:pos | i + l <= k}{c:nat | c < 1114112} RefHit(k, i) of (int l, int c)
  | RefMiss(k, i) of ()

(* The value of the hex digit b, or -1 *)
fn _hexv (b: Int): Int =
  if b >= 48 then (if b <= 57 then b - 48
    else if b >= 97 then (if b <= 102 then b - 87 else ~1)
    else if b >= 65 then (if b <= 70 then b - 55 else ~1) else ~1)
  else ~1

(* The number in data[o + j, o + e) in base 16 (hex) or 10, from acc:
   -1 when a byte is no digit or it exceeds U+10FFFF *)
fun _num {lb:agz}{n:pos}{o,e:nat | o + e <= n}{j:nat | j <= e} .<e - j>.
  (data: !$A.borrow(byte, lb, n), o: int o, j: int j, e: int e, hex: bool, acc: Int): Int =
  if j >= e then acc
  else let
    val b = $AR.low_byte(byte2int0($A.read<byte>(data, o + j)))
    val d = (if hex then _hexv(b) else if b >= 48 then (if b <= 57 then b - 48 else ~1) else ~1): Int
  in
    if d < 0 then ~1
    else let
      val v = (if hex then acc * 16 + d else acc * 10 + d): Int
    in if v > 1114111 then ~1 else _num(data, o, j + 1, e, hex, v) end
  end

(* The code point of the named reference data[o + s, o + e), or -1 *)
fn _named {lb:agz}{n:pos}{o,s,e:nat | s <= e; o + e <= n}
  (data: !$A.borrow(byte, lb, n), o: int o, s: int s, e: int e): Int = let
  fn is {np:pos} (data: !$A.borrow(byte, lb, n), pat: &(@[char][np]), np: int np): bool =
    xml_name_eq(data, o + s, e - s, pat, np)
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
  if is(data, amp, 3) then 38 else if is(data, lt, 2) then 60
  else if is(data, gt, 2) then 62 else if is(data, quot, 4) then 34
  else if is(data, apos, 4) then 39 else if is(data, nbsp, 4) then 160
  else if is(data, mdash, 5) then 8212 else if is(data, ndash, 5) then 8211
  else if is(data, hellip, 6) then 8230 else if is(data, lsquo, 5) then 8216
  else if is(data, rsquo, 5) then 8217 else if is(data, ldquo, 5) then 8220
  else if is(data, rdquo, 5) then 8221 else if is(data, laquo, 5) then 171
  else if is(data, raquo, 5) then 187 else if is(data, copy, 4) then 169
  else if is(data, reg, 3) then 174 else if is(data, trade, 5) then 8482
  else if is(data, shy, 3) then 173 else if is(data, middot, 6) then 183
  else if is(data, bull, 4) then 8226 else if is(data, sect, 4) then 167
  else if is(data, deg, 3) then 176 else if is(data, eacute, 6) then 233
  else if is(data, egrave, 6) then 232 else if is(data, aacute, 6) then 225
  else if is(data, agrave, 6) then 224 else if is(data, ccedil, 6) then 231
  else if is(data, ouml, 4) then 246 else if is(data, uuml, 4) then 252
  else if is(data, auml, 4) then 228 else if is(data, szlig, 5) then 223
  else if is(data, thinsp, 6) then 8201 else if is(data, ensp, 4) then 8194
  else if is(data, emsp, 4) then 8195
  else ~1
end

(* The first ';' in data[o + j, o + e), or e *)
fun _semi {lb:agz}{n:pos}{o,e:nat | o + e <= n}{j:nat | j <= e} .<e - j>.
  (data: !$A.borrow(byte, lb, n), o: int o, j: int j, e: int e): [r:nat | j <= r; r <= e] int r =
  if j >= e then e
  else if byte2int0($A.read<byte>(data, o + j)) = 59 then j
  else _semi(data, o, j + 1, e)

(* The reference at data[o + i] (a '&'), within data[o, o + k) *)
fn _ref {lb:agz}{n:pos}{o,k:nat | o + k <= n}{i:nat | i < k}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, i: int i): ref_hit(k, i) = let
  (* a reference is at most 12 bytes long *)
  val e = (if i + 12 < k then i + 12 else k): [e:int | i < e; e <= k] int e
  val sc = _semi(data, o, i + 1, e)
in
  if sc >= e then RefMiss()
  else if sc <= i + 1 then RefMiss()
  else let
    val l = sc + 1 - i
    val c = (if byte2int0($A.read<byte>(data, o + i + 1)) = 35 then
        (if sc > i + 2 then
           (if $AR.bor_int_int(byte2int0($A.read<byte>(data, o + i + 2)), 32) = 120 then
              (if sc > i + 3 then _num(data, o, i + 3, sc, true, 0) else ~1)
            else _num(data, o, i + 2, sc, false, 0))
         else ~1)
      else _named(data, o, i + 1, sc)): Int
  in
    (* no NUL, no surrogate, and no longer than its source *)
    if c <= 0 then RefMiss()
    else if c > 1114111 then RefMiss()
    else if (if c >= 55296 then c <= 57343 else false) then RefMiss()
    else if _enc_len(c) > l then RefMiss()
    else RefHit(l, c)
  end
end

(* Code point c as UTF-8 at out[p], in e bytes *)
fn _put_utf8 {l:agz}{m:nat}{p:nat}{e:int | e >= 1; e <= 4; p + e <= m}
  (out: !$A.arr(byte, l, m), p: int p, c: int, e: int e): void =
  if e = 1 then $A.set<byte>(out, p, $A.int2byte($AR.low_byte(c)))
  else if e = 2 then let
    val () = $A.set<byte>(out, p, $A.int2byte($AR.low_byte(192 + c / 64)))
  in $A.set<byte>(out, p + 1, $A.int2byte($AR.low_byte(128 + c - (c / 64) * 64))) end
  else if e = 3 then let
    val () = $A.set<byte>(out, p, $A.int2byte($AR.low_byte(224 + c / 4096)))
    val () = $A.set<byte>(out, p + 1, $A.int2byte($AR.low_byte(128 + (c / 64) - (c / 4096) * 64)))
  in $A.set<byte>(out, p + 2, $A.int2byte($AR.low_byte(128 + c - (c / 64) * 64))) end
  else let
    val () = $A.set<byte>(out, p, $A.int2byte($AR.low_byte(240 + c / 262144)))
    val () = $A.set<byte>(out, p + 1, $A.int2byte($AR.low_byte(128 + (c / 4096) - (c / 262144) * 64)))
    val () = $A.set<byte>(out, p + 2, $A.int2byte($AR.low_byte(128 + (c / 64) - (c / 4096) * 64)))
  in $A.set<byte>(out, p + 3, $A.int2byte($AR.low_byte(128 + c - (c / 64) * 64))) end

(* The UTF-8 length of c, as a static bound: no more than l *)
fn _len_of {l:pos} (c: int, l: int l): [e:int | e >= 1; e <= 4; e <= l] int e = let
  val e = _enc_len(c)
in
  if e <= 1 then 1
  else if e = 2 then (if l >= 2 then 2 else 1)
  else if e = 3 then (if l >= 3 then 3 else 1)
  else if l >= 4 then 4 else 1
end

fun _dec {lb,l:agz}{n:pos}{o,k:nat | o + k <= n}{m:nat | k <= m}{i:nat | i <= k}{p:nat | p <= i} .<k - i>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, i: int i,
   out: !$A.arr(byte, l, m), p: int p): [q:nat | q <= k] int q =
  if i >= k then p
  else let
    val b = $A.read<byte>(data, o + i)
  in
    if byte2int0(b) <> 38 then let
      val () = $A.set<byte>(out, p, b)
    in _dec(data, o, k, i + 1, out, p + 1) end
    else (case+ _ref(data, o, k, i) of
      | ~RefMiss() => let
          val () = $A.set<byte>(out, p, b)
        in _dec(data, o, k, i + 1, out, p + 1) end
      | ~RefHit(len, c) => let
          val e = _len_of(c, len)
          val () = _put_utf8(out, p, c, e)
        in _dec(data, o, k, i + len, out, p + e) end)
  end

(* out[0, q) := data[o, o + k) with its references decoded; q <= k *)
#pub fn decode_text {lb,l:agz}{n:pos}{o,k:nat | o + k <= n}{m:nat | k <= m}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, out: !$A.arr(byte, l, m)): [q:nat | q <= k] int q

implement decode_text (data, o, k, out) = _dec(data, o, k, 0, out, 0)

(* Whether data[o, o + k) has a '&' at or after i *)
fun _has_amp {lb:agz}{n:pos}{o,k:nat | o + k <= n}{i:nat | i <= k} .<k - i>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, i: int i): bool =
  if i >= k then false
  else if byte2int0($A.read<byte>(data, o + i)) = 38 then true
  else _has_amp(data, o, k, i + 1)

#pub fn has_reference {lb:agz}{n:pos}{o,k:nat | o + k <= n}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k): bool

implement has_reference (data, o, k) = _has_amp(data, o, k, 0)
