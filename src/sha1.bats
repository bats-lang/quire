(* sha1 -- SHA-1 (FIPS 180-4) of a byte string, for the one thing in an
   EPUB that needs it: the key of the font obfuscation the EPUB OCF
   names (http://www.idpf.org/2008/embedding), the SHA-1 of the package's
   unique identifier. It is not used to keep anything secret (SHA-1 is not
   fit for that), only to undo a mask the publisher applied. Pure ATS2,
   as the sha256 package is written (no C, no $UNSAFE): 32-bit words are
   uint, whose arithmetic wraps modulo 2^32 by definition, and every array
   index is proven inside its array. *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

(* The SHA-1 of data[0, data_len) as its 20 bytes, in out *)
#pub fn sha1_digest {l:agz}{n:pos}{data_len:pos | data_len <= n}{lo:agz}
  (data: !$A.borrow(byte, l, n), data_len: int data_len, out: !$A.arr(byte, lo, 20)): void

fn _rotl {k:int | 0 < k; k < 32} (x: uint, k: int k): uint =
  (x << k) lor (x >> (32 - k))

fn _word (x: int): uint = g0int2uint_int_uint(x)

(* The low byte of x *)
fn _byte (x: uint): [v:nat | v < 256] int v =
  $AR.low_byte(g0uint2int_uint_int(x land 0xffu))

(* The constant of round t (FIPS 180-4, section 4.2.1) *)
fn _constant {t:nat | t < 80} (t: int t): uint =
  if t < 20 then 0x5a827999u
  else if t < 40 then 0x6ed9eba1u
  else if t < 60 then 0x8f1bbcdcu
  else 0xca62c1d6u

(* The function of round t (section 4.1.1) *)
fn _mix {t:nat | t < 80} (t: int t, b: uint, c: uint, d: uint): uint =
  if t < 20 then (b land c) lor ((lnot b) land d)
  else if t < 40 then b lxor c lxor d
  else if t < 60 then (b land c) lor (b land d) lor (c land d)
  else b lxor c lxor d

(* The five words of the hash state *)
typedef state = @(uint, uint, uint, uint, uint)

(* Processes the block data[block_at, block_at + 64) into the state, with w as the
   message schedule (section 6.1.2) *)
fn _compress {ld:agz}{nd:pos}{block_at:nat | block_at + 64 <= nd}{lw:agz}
  (data: !$A.arr(byte, ld, nd), block_at: int block_at,
   w: !$A.arr(uint, lw, 80), h: state): state = let
  fun load {t:nat | t <= 16} .<16 - t>.
    (data: !$A.arr(byte, ld, nd), w: !$A.arr(uint, lw, 80), t: int t): void =
    if t >= 16 then ()
    else let
      val at = block_at + 4 * t
      val byte0 = _word(byte2int0($A.get<byte>(data, at)))
      val byte1 = _word(byte2int0($A.get<byte>(data, at + 1)))
      val byte2 = _word(byte2int0($A.get<byte>(data, at + 2)))
      val byte3 = _word(byte2int0($A.get<byte>(data, at + 3)))
      val () = $A.set<uint>(w, t, (byte0 << 24) lor (byte1 << 16) lor (byte2 << 8) lor byte3)
    in load(data, w, t + 1) end
  fun expand {t:int | 16 <= t; t <= 80} .<80 - t>.
    (w: !$A.arr(uint, lw, 80), t: int t): void =
    if t >= 80 then ()
    else let
      val mixed = $A.get<uint>(w, t - 3) lxor $A.get<uint>(w, t - 8) lxor $A.get<uint>(w, t - 14) lxor $A.get<uint>(w, t - 16)
      val () = $A.set<uint>(w, t, _rotl(mixed, 1))
    in expand(w, t + 1) end
  fun rounds {t:nat | t <= 80} .<80 - t>.
    (w: !$A.arr(uint, lw, 80), t: int t, a: uint, b: uint, c: uint, d: uint, e: uint): state =
    if t >= 80 then @(a, b, c, d, e)
    else let
      val temporary = _rotl(a, 5) + _mix(t, b, c, d) + e + _constant(t) + $A.get<uint>(w, t)
    in rounds(w, t + 1, temporary, a, _rotl(b, 30), c, d) end
  val () = load(data, w, 0)
  val () = expand(w, 16)
  val @(h0, h1, h2, h3, h4) = h
  val @(a, b, c, d, e) = rounds(w, 0, h0, h1, h2, h3, h4)
in @(h0 + a, h1 + b, h2 + c, h3 + d, h4 + e) end

(* data[from, stop) appended to the block in block[0, filled), each block
   compressed as it fills; the bytes left in the block, and the state *)
fun _fill {lw,lb,ld:agz}{n:pos}{stop:nat | stop <= n}{from:nat | from <= stop}{filled:nat | filled < 64} .<stop - from>.
  (h: state, w: !$A.arr(uint, lw, 80), block: !$A.arr(byte, lb, 64),
   data: !$A.borrow(byte, ld, n), stop: int stop, from: int from, filled: int filled): @([left:nat | left < 64] int left, state) =
  if from >= stop then @(filled, h)
  else let
    val () = $A.set<byte>(block, filled, $A.read<byte>(data, from))
  in
    if filled + 1 >= 64 then let
      val next = _compress(block, 0, w, h)
    in _fill(next, w, block, data, stop, from + 1, 0) end
    else _fill(h, w, block, data, stop, from + 1, filled + 1)
  end

(* The word x as four bytes at out[at, at + 4), the high one first *)
fn _put_word {lo:agz}{at:nat | at + 4 <= 20} (out: !$A.arr(byte, lo, 20), at: int at, x: uint): void = let
  val () = $A.set<byte>(out, at, $A.int2byte(_byte(x >> 24)))
  val () = $A.set<byte>(out, at + 1, $A.int2byte(_byte(x >> 16)))
  val () = $A.set<byte>(out, at + 2, $A.int2byte(_byte(x >> 8)))
in $A.set<byte>(out, at + 3, $A.int2byte(_byte(x))) end

(* The one or two blocks of padding in padding[0, last), compressed into the state *)
fn _compress_padding {lp,lw:agz}{last:int | last == 64 || last == 128}
  (padding: !$A.arr(byte, lp, 128), last: int last, w: !$A.arr(uint, lw, 80), h: state): state = let
  val first = _compress(padding, 0, w, h)
in if last = 128 then _compress(padding, 64, w, first) else first end

(* The buffers of a digest given back *)
fn _release {lp,lb,lw:agz} (padding: $A.arr(byte, lp, 128), block: $A.arr(byte, lb, 64), w: $A.arr(uint, lw, 80)): void = let
  val () = $A.free<byte>(padding)
  val () = $A.free<byte>(block)
in $A.free<uint>(w) end

fn _digest {l:agz}{n:pos}{data_len:pos | data_len <= n}{lo:agz}
  (data: !$A.borrow(byte, l, n), data_len: int data_len, out: !$A.arr(byte, lo, 20)): void = let
  val w = $A.alloc<uint>(80): [lw:agz] $A.arr(uint, lw, 80)
  val block = $A.alloc<byte>(64): [lb:agz] $A.arr(byte, lb, 64)
  val initial = @(0x67452301u, 0xefcdab89u, 0x98badcfeu, 0x10325476u, 0xc3d2e1f0u): state
  val @(tail, filled_state) = _fill(initial, w, block, data, data_len, 0, 0)
  (* the tail, 0x80, zeros and the length in bits as 64 bits, big endian,
     in one block or two (alloc zeroes what it gives) *)
  val padding = $A.alloc<byte>(128): [lp:agz] $A.arr(byte, lp, 128)
  fun copy {lp,lb:agz}{tail:nat | tail < 64}{i:nat | i <= tail} .<tail - i>.
    (block: !$A.arr(byte, lb, 64), padding: !$A.arr(byte, lp, 128), tail: int tail, i: int i): void =
    if i >= tail then ()
    else let
      val () = $A.set<byte>(padding, i, $A.get<byte>(block, i))
    in copy(block, padding, tail, i + 1) end
  val () = copy(block, padding, tail, 0)
  val () = $A.set<byte>(padding, tail, $A.int2byte(128))
  val last = (if tail + 9 > 64 then 128 else 64): [last:int | last == 64 || last == 128] int last
  val length = _word(data_len)
  val bits_high = length >> 29
  val bits_low = length << 3
  val () = $A.set<byte>(padding, last - 8, $A.int2byte(_byte(bits_high >> 24)))
  val () = $A.set<byte>(padding, last - 7, $A.int2byte(_byte(bits_high >> 16)))
  val () = $A.set<byte>(padding, last - 6, $A.int2byte(_byte(bits_high >> 8)))
  val () = $A.set<byte>(padding, last - 5, $A.int2byte(_byte(bits_high)))
  val () = $A.set<byte>(padding, last - 4, $A.int2byte(_byte(bits_low >> 24)))
  val () = $A.set<byte>(padding, last - 3, $A.int2byte(_byte(bits_low >> 16)))
  val () = $A.set<byte>(padding, last - 2, $A.int2byte(_byte(bits_low >> 8)))
  val () = $A.set<byte>(padding, last - 1, $A.int2byte(_byte(bits_low)))
  val @(h0, h1, h2, h3, h4) = _compress_padding(padding, last, w, filled_state)
  val () = _put_word(out, 0, h0)
  val () = _put_word(out, 4, h1)
  val () = _put_word(out, 8, h2)
  val () = _put_word(out, 12, h3)
  val () = _put_word(out, 16, h4)
in _release(padding, block, w) end

implement sha1_digest (data, data_len, out) = _digest(data, data_len, out)
