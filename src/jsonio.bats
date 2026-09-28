(* jsonio -- JSON written into and read from byte buffers (the backup's):
   writes are in range by type, and reads check the bytes they are
   given (a file the user picked), once, as they go *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

staload "book.sats"

(* ============================================================
   Writing
   ============================================================ *)

(* JSON text in a piece: its bytes out[0, m) *)
#pub datavtype jchunk =
  | {la,l:agz}{n:pos}{m:nat | m <= n} JChunk of (piece_owner(n, la), $A.arrx(byte, l, n, la), int m)
  | JNone of ()

#pub fn jchunk_free (c: jchunk): void

implement jchunk_free (c) = case+ c of
  | ~JChunk(ow, out, _) => piece_free(ow, out)
  | ~JNone() => ()

fun _lit {l:agz}{la:addr}{n:nat}{sn:nat}{p:nat | p + sn <= n}{i:nat | i <= sn} .<sn - i>.
  (out: !$A.arrx(byte, l, n, la), p: int p, s: string sn, sl: int sn, i: int i): int(p + sn) =
  if i >= sl then p + sl
  else let
    val () = $A.write_byte(out, p + i, $AR.byte_of_char(string_get_at(s, i)))
  in _lit(out, p, s, sl, i + 1) end

(* s, at out[p, p + |s|) *)
#pub fn jw_lit {l:agz}{la:addr}{n:nat}{sn:nat}{p:nat | p + sn <= n}
  (out: !$A.arrx(byte, l, n, la), p: int p, s: string sn): int(p + sn)

implement jw_lit (out, p, s) = _lit(out, p, s, g1u2i(string1_length(s)), 0)

(* The decimal digits of -w, for w <= 0: how many there are (w's
   quotients by 10 are taken toward 0, so the smallest int has them
   too) *)
fun _ndig {d:int | 1 <= d; d <= 10} .<10 - d>. (w: int, d: int d): [e:int | 1 <= e; e <= 10] int e =
  if d >= 10 then d
  else if w / 10 = 0 then d
  else _ndig(w / 10, d + 1)

(* -w's digits at out[p, p + i + 1), the last at p + i *)
fun _digits {l:agz}{la:addr}{n:nat}{p:nat}{i:int | ~1 <= i; p + i < n} .<i + 1>.
  (out: !$A.arrx(byte, l, n, la), p: int p, i: int i, w: int): void =
  if i < 0 then ()
  else let
    val r = (w / 10) * 10 - w
    val () = $A.write_byte(out, p + i, $AR.low_byte(48 + r))
  in _digits(out, p, i - 1, w / 10) end

(* v in decimal at out[p, q) *)
#pub fn jw_int {l:agz}{la:addr}{n:nat}{p:nat | p + 11 <= n}
  (out: !$A.arrx(byte, l, n, la), p: int p, v: int): [q:int | p < q; q <= p + 11] int q

implement jw_int (out, p, v) =
  if v < 0 then let
    val () = $A.write_byte(out, p, 45)
    val d = _ndig(v, 1)
    val () = _digits(out, p + 1, d - 1, v)
  in p + 1 + d end
  else let
    val w = ~v
    val d = _ndig(w, 1)
    val () = _digits(out, p, d - 1, w)
  in p + d end

fn _hexd {v:nat | v < 16} (v: int v): [c:nat | c < 256] int c =
  if v < 10 then 48 + v else 87 + v

(* The escaped bytes of src[j, k), at out[q, ...) *)
fun _esc {l,ls:agz}{la,ows:addr}{n,ms:nat}{k:nat | k <= ms}{j:nat | j <= k}{q:nat | q + 6 * (k - j) <= n} .<k - j>.
  (out: !$A.arrx(byte, l, n, la), q: int q, src: !$A.arrx(byte, ls, ms, ows), k: int k, j: int j)
  : [r:nat | r <= q + 6 * (k - j)] int r =
  if j >= k then q
  else let
    val c = $AR.low_byte(byte2int0($A.get<byte>(src, j)))
  in
    if c = 34 then let
      val () = $A.write_byte(out, q, 92)
      val () = $A.write_byte(out, q + 1, 34)
    in _esc(out, q + 2, src, k, j + 1) end
    else if c = 92 then let
      val () = $A.write_byte(out, q, 92)
      val () = $A.write_byte(out, q + 1, 92)
    in _esc(out, q + 2, src, k, j + 1) end
    else if c = 10 then let
      val () = $A.write_byte(out, q, 92)
      val () = $A.write_byte(out, q + 1, 110)
    in _esc(out, q + 2, src, k, j + 1) end
    else if c = 9 then let
      val () = $A.write_byte(out, q, 92)
      val () = $A.write_byte(out, q + 1, 116)
    in _esc(out, q + 2, src, k, j + 1) end
    else if c < 32 then let
      val q2 = _lit(out, q, "\\u00", 4, 0)
      val () = $A.write_byte(out, q2, _hexd($AR.band_g1($AR.low_byte($AR.bsr_int_int(c, 4)), 15)))
      val () = $A.write_byte(out, q2 + 1, _hexd($AR.band_g1(c, 15)))
    in _esc(out, q + 6, src, k, j + 1) end
    else let
      val () = $A.write_byte(out, q, c)
    in _esc(out, q + 1, src, k, j + 1) end
  end

(* src[0, k) as a JSON string, quoted and escaped, at out[p, q) *)
#pub fn jw_str {l,ls:agz}{la,ows:addr}{n,ms:nat}{k:nat | k <= ms}{p:nat | p + 2 + 6 * k <= n}
  (out: !$A.arrx(byte, l, n, la), p: int p, src: !$A.arrx(byte, ls, ms, ows), k: int k)
  : [q:nat | q <= p + 2 + 6 * k] int q

implement jw_str (out, p, src, k) = let
  val () = $A.write_byte(out, p, 34)
  val q = _esc(out, p + 1, src, k, 0)
  val () = $A.write_byte(out, q, 34)
in q + 1 end

(* ============================================================
   Reading
   ============================================================ *)

fn _at {l:agz}{la:addr}{n:nat}{p:nat | p < n} (buf: !$A.arrx(byte, l, n, la), p: int p): [c:nat | c < 256] int c =
  $AR.low_byte(byte2int0($A.get<byte>(buf, p)))

(* Past the white space at p *)
#pub fun jr_ws {l:agz}{la:addr}{n:nat}{p:nat | p <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p): [q:int | p <= q; q <= n] int q

fun _ws {l:agz}{la:addr}{n:nat}{q:nat | q <= n} .<n - q>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, q: int q): [r:int | q <= r; r <= n] int r =
  if q >= n then q
  else let val c = _at(buf, q) in
    if c = 32 then _ws(buf, n, q + 1)
    else if c = 10 then _ws(buf, n, q + 1)
    else if c = 13 then _ws(buf, n, q + 1)
    else if c = 9 then _ws(buf, n, q + 1)
    else q
  end

implement jr_ws (buf, n, p) = _ws(buf, n, p)

(* Whether the byte at p is c *)
#pub fn jr_is {l:agz}{la:addr}{n:nat}{p:nat | p <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, c: int): bool

implement jr_is (buf, n, p, c) = if p < n then _at(buf, p) = c else false

fun _digs {l:agz}{la:addr}{n:nat}{p:nat | p <= n}{d:nat | d <= 9} .<9 - d>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, d: int d, acc: Int)
  : [q:int | p <= q; q <= n] @(int, Int, int q) =
  if d >= 9 then @(d, acc, p)
  else if p >= n then @(d, acc, p)
  else let val c = _at(buf, p) in
    if c < 48 then @(d, acc, p)
    else if c > 57 then @(d, acc, p)
    else _digs(buf, n, p + 1, d + 1, acc * 10 + (c - 48))
  end

(* An integer of at most 9 digits at p: whether there is one, its value
   and where it ends *)
#pub fn jr_int {l:agz}{la:addr}{n:nat}{p:nat | p <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p): [q:int | p <= q; q <= n] @(bool, Int, int q)

(* Whether the number ends at q: no more digits, no fraction, no
   exponent *)
fn _num_end {l:agz}{la:addr}{n:nat}{q:nat | q <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, q: int q): bool =
  if q >= n then true
  else let val c = _at(buf, q) in
    if c >= 48 then c > 57 else c <> 46
  end && ~jr_is(buf, n, q, 101) && ~jr_is(buf, n, q, 69)

implement jr_int (buf, n, p) =
  if p >= n then @(false, 0, p)
  else if _at(buf, p) = 45 then let
    val @(d, v, q) = _digs(buf, n, p + 1, 0, 0)
  in @(d > 0 && _num_end(buf, n, q), ~v, q) end
  else let
    val @(d, v, q) = _digs(buf, n, p, 0, 0)
  in @(d > 0 && _num_end(buf, n, q), v, q) end

fn _hexv (c: int): int =
  if c >= 48 then (if c <= 57 then c - 48
    else if c >= 97 then (if c <= 102 then c - 87 else ~1)
    else if c >= 65 then (if c <= 70 then c - 55 else ~1) else ~1)
  else ~1

(* The 4 hex digits at p, or -1 *)
fn _hex4 {l:agz}{la:addr}{n:nat}{p:nat | p <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p): int =
  if p + 4 > n then ~1
  else let
    val a = _hexv(_at(buf, p))
    val b = _hexv(_at(buf, p + 1))
    val c = _hexv(_at(buf, p + 2))
    val d = _hexv(_at(buf, p + 3))
  in if a < 0 || b < 0 || c < 0 || d < 0 then ~1 else ((a * 16 + b) * 16 + c) * 16 + d end

(* The UTF-8 of code point u at out[j, ...) when it fits in cap: the
   new length, or j when it does not fit *)
fn _utf8 {lo:agz}{cap:nat}{j:nat | j <= cap}
  (out: !$A.arr(byte, lo, cap), cap: int cap, j: int j, u: int): [r:int | j <= r; r <= cap] int r =
  if u < 128 then
    (if j + 1 <= cap then let
       val () = $A.write_byte(out, j, $AR.low_byte(u))
     in j + 1 end else j)
  else if u < 2048 then
    (if j + 2 <= cap then let
       val () = $A.write_byte(out, j, $AR.low_byte(192 + u / 64))
       val () = $A.write_byte(out, j + 1, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(u), 63)))
     in j + 2 end else j)
  else if u < 65536 then
    (if j + 3 <= cap then let
       val () = $A.write_byte(out, j, $AR.low_byte(224 + u / 4096))
       val () = $A.write_byte(out, j + 1, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(u / 64), 63)))
       val () = $A.write_byte(out, j + 2, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(u), 63)))
     in j + 3 end else j)
  else
    (if j + 4 <= cap then let
       val () = $A.write_byte(out, j, $AR.low_byte(240 + u / 262144))
       val () = $A.write_byte(out, j + 1, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(u / 4096), 63)))
       val () = $A.write_byte(out, j + 2, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(u / 64), 63)))
       val () = $A.write_byte(out, j + 3, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(u), 63)))
     in j + 4 end else j)

(* u's UTF-8 at out[j, ...) unless the string is already full *)
fn _emit {lo:agz}{cap:nat}{j:nat | j <= cap}
  (full: bool, out: !$A.arr(byte, lo, cap), cap: int cap, j: int j, u: int): [r:int | j <= r; r <= cap] int r =
  if full then j else _utf8(out, cap, j, u)

(* The bytes a UTF-8 sequence led by c takes *)
fn _seq_len (c: int): [k:int | 1 <= k; k <= 4] int k =
  if c >= 240 then 4 else if c >= 224 then 3 else if c >= 192 then 2 else 1

(* A string's contents from q (past its opening quote), decoded into
   out[j, cap): once out is full the rest is read and dropped, a
   character at a time. Whether it closed, its length, where it ends. *)
fun _str {l,lo:agz}{la:addr}{n,cap:nat}{q:nat | q <= n}{j:nat | j <= cap} .<n - q>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, q: int q, out: !$A.arr(byte, lo, cap), cap: int cap, j: int j, full: bool)
  : [r:int | q <= r; r <= n][k:nat | k <= cap] @(bool, int k, int r) =
  if q >= n then @(false, j, q)
  else let val c = _at(buf, q) in
    if c = 34 then @(true, j, q + 1)
    else if c = 92 then
      (if q + 1 >= n then @(false, j, n)
       else let val e = _at(buf, q + 1) in
         if e = 117 then
           (if q + 6 > n then @(false, j, n)
           else let
           val u = _hex4(buf, n, q + 2)
         in
           if u < 0 then @(false, j, n)
           else if (if u >= 55296 then u <= 56319 else false) then
             (* a high surrogate: its low one follows *)
             (if q + 12 > n then @(false, j, n)
              else if (if _at(buf, q + 6) = 92 then _at(buf, q + 7) = 117 else false) then let
                val v = _hex4(buf, n, q + 8)
              in
                if (if v >= 56320 then v <= 57343 else false) then let
                  val j2 = _emit(full, out, cap, j, 65536 + (u - 55296) * 1024 + (v - 56320))
                in _str(buf, n, q + 12, out, cap, j2, full || (j2 = j)) end
                else @(false, j, n)
              end
              else @(false, j, n))
           else let
             val j2 = _emit(full, out, cap, j, u)
           in _str(buf, n, q + 6, out, cap, j2, full || (j2 = j)) end
         end)
         else let
           val d = (if e = 110 then 10 else if e = 116 then 9 else if e = 114 then 13
             else if e = 98 then 8 else if e = 102 then 12 else e): int
           val j2 = _emit(full, out, cap, j, d)
         in _str(buf, n, q + 2, out, cap, j2, full || (j2 = j)) end
       end)
    else if c < 128 then let
      val j2 = _emit(full, out, cap, j, c)
    in _str(buf, n, q + 1, out, cap, j2, full || (j2 = j)) end
    else if c < 192 then
      (* a continuation byte: kept when its sequence's lead was *)
      (if full then _str(buf, n, q + 1, out, cap, j, full)
       else if j < cap then let
         val () = $A.write_byte(out, j, c)
       in _str(buf, n, q + 1, out, cap, j + 1, full) end
       else _str(buf, n, q + 1, out, cap, j, true))
    else
      (* a lead byte: kept when its whole sequence fits *)
      (if full then _str(buf, n, q + 1, out, cap, j, full)
       else if j + _seq_len(c) <= cap then let
         val () = $A.write_byte(out, j, c)
       in _str(buf, n, q + 1, out, cap, j + 1, full) end
       else _str(buf, n, q + 1, out, cap, j, true))
  end

(* The string at p, decoded into out[0, cap) (cut at a character when
   it is longer): whether there is one, its length and where it ends *)
#pub fn jr_str {l,lo:agz}{la:addr}{n,cap:nat}{p:nat | p < n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, out: !$A.arr(byte, lo, cap), cap: int cap)
  : [q:int | p < q; q <= n][k:nat | k <= cap] @(bool, int k, int q)

implement jr_str (buf, n, p, out, cap) =
  if _at(buf, p) = 34 then _str(buf, n, p + 1, out, cap, 0, false)
  else @(false, 0, p + 1)

(* Whether the literal s is at p, and where it ends *)
fun _word {l:agz}{la:addr}{n:nat}{p:nat | p <= n}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, s: string sn, sl: int sn, i: int i): bool =
  if i >= sl then true
  else if p + i >= n then false
  else if _at(buf, p + i) <> $AR.byte_of_char(string_get_at(s, i)) then false
  else _word(buf, n, p, s, sl, i + 1)

(* true or false at p: whether it is either, its value, where it ends *)
#pub fn jr_bool {l:agz}{la:addr}{n:nat}{p:nat | p <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p): [q:int | p <= q; q <= n] @(bool, bool, int q)

implement jr_bool (buf, n, p) =
  if _word(buf, n, p, "true", 4, 0) then (if p + 4 <= n then @(true, true, p + 4) else @(false, false, p))
  else if _word(buf, n, p, "false", 5, 0) then (if p + 5 <= n then @(true, false, p + 5) else @(false, false, p))
  else @(false, false, p)

(* Skipping a value: a value at p ends past p (or at n when it is cut
   short or nested more than 64 deep) *)
fun _skip {l:agz}{la:addr}{n:nat}{p:nat | p < n} .<n - p, 0>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, depth: int): [q:int | p < q; q <= n] int q = let
  val c = _at(buf, p)
in
  if c = 34 then let
    val a = $A.alloc<byte>(1)
    val @(ok, _, q) = _str(buf, n, p + 1, a, 1, 0, true)
    val () = $A.free<byte>(a)
  in if ok then q else n end
  else if c = 91 then (if depth >= 64 then n else _items(buf, n, p + 1, depth + 1, 93))
  else if c = 123 then (if depth >= 64 then n else _items(buf, n, p + 1, depth + 1, 125))
  else _scalar(buf, n, p + 1)
end

(* The items of an array (or members of an object: key, colon and
   value are skipped as three items) from p to the closing byte e *)
and _items {l:agz}{la:addr}{n:nat}{p:nat | p <= n} .<n - p, 1>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, depth: int, e: int): [q:int | p <= q; q <= n] int q = let
  val q = jr_ws(buf, n, p)
in
  if q >= n then n
  else let val c = _at(buf, q) in
    if c = e then q + 1
    else if c = 44 then _items(buf, n, q + 1, depth, e)
    else if c = 58 then _items(buf, n, q + 1, depth, e)
    else _items(buf, n, _skip(buf, n, q, depth), depth, e)
  end
end

(* A number, true, false or null: to the next delimiter *)
and _scalar {l:agz}{la:addr}{n:nat}{p:nat | p <= n} .<n - p, 2>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p): [q:int | p <= q; q <= n] int q =
  if p >= n then p
  else let val c = _at(buf, p) in
    if c = 44 || c = 93 || c = 125 || c = 58 || c = 32 || c = 10 || c = 13 || c = 9 then p
    else _scalar(buf, n, p + 1)
  end

(* Past the value at p *)
#pub fn jr_skip {l:agz}{la:addr}{n:nat}{p:nat | p <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p): [q:int | p <= q; q <= n] int q

implement jr_skip (buf, n, p) = if p < n then _skip(buf, n, p, 0) else p

(* A member's key at p (after white space): whether there is one (read
   into out[0, cap), cut when longer), its length, and where its value
   starts (past the colon and white space) *)
#pub fn jr_key {l,lo:agz}{la:addr}{n,cap:nat}{p:nat | p < n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, out: !$A.arr(byte, lo, cap), cap: int cap)
  : [q:int | p < q; q <= n][k:nat | k <= cap] @(bool, int k, int q)

implement jr_key (buf, n, p, out, cap) = let
  val @(ok, k, q) = jr_str(buf, n, p, out, cap)
in
  if ~ok then @(false, k, q)
  else let
    val q2 = jr_ws(buf, n, q)
  in
    if q2 >= n then @(false, k, q2)
    else if _at(buf, q2) = 58 then let
      val r = jr_ws(buf, n, q2 + 1)
    in @(true, k, r) end
    else @(false, k, q2)
  end
end

fun _key_eq {lo:agz}{cap:nat}{k:nat | k <= cap}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (a: !$A.arr(byte, lo, cap), k: int k, s: string sn, sl: int sn, i: int i): bool =
  if i >= sl then true
  else if i >= k then false
  else if $AR.low_byte(byte2int0($A.get<byte>(a, i))) <> $AR.byte_of_char(string_get_at(s, i)) then false
  else _key_eq(a, k, s, sl, i + 1)

(* Whether a[0, k) is s *)
#pub fn jr_key_is {lo:agz}{cap:nat}{k:nat | k <= cap}{sn:nat}
  (a: !$A.arr(byte, lo, cap), k: int k, s: string sn): bool

implement jr_key_is (a, k, s) = let
  val sl = g1u2i(string1_length(s))
in if k <> sl then false else _key_eq(a, k, s, sl, 0) end

end (* #target wasm *)
