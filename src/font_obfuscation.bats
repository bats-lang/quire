(* font_obfuscation -- the two ways an EPUB masks a font that its
   publisher does not want copied out of the book, which a reading system
   with a viewport must undo (EPUB OCF 3.3 section 4.1.2, "Font
   obfuscation"): both xor the first bytes of the font with a key made of
   the package's unique identifier.

   * IDPF (http://www.idpf.org/2008/embedding): the key is the SHA-1 of
     the identifier with its white space (U+0020, U+0009, U+000D, U+000A)
     taken out, 20 bytes, and the first 1040 bytes are xored with it.
   * Adobe (http://ns.adobe.com/pdf/enc#RC): the key is the 16 bytes of
     the identifier's UUID (urn:uuid:, its dashes taken out, 32 hex
     digits), and the first 1024 bytes are xored with it.

   Neither keeps anything secret (the key is in the book), so this only
   undoes a mask. Xor is its own inverse: the same function masks. *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use sha256 as SHA


(* How many bytes of the font each algorithm masks *)
#pub fn idpf_masked_bytes (): int
#pub fn adobe_masked_bytes (): int

implement idpf_masked_bytes () = 1040
implement adobe_masked_bytes () = 1024

fn _word (x: int): uint = g0int2uint_int_uint(x)

(* The low byte of x *)
fn _byte (x: uint): [v:nat | v < 256] int v =
  $AR.low_byte(g0uint2int_uint_int(x land 0xffu))

(* Whether b is one of the four white space characters of XML *)
fn _is_space (b: int): bool = b = 32 || b = 9 || b = 13 || b = 10

(* clean[0, kept) := the bytes of identifier[0, n) that are not white space; how many *)
fun _strip {l,lc:agz}{n:pos | n <= 4096}{i:nat | i <= n}{kept:nat | kept <= i} .<n - i>.
  (identifier: !$A.borrow(byte, l, n), n: int n, clean: !$A.arr(byte, lc, n), i: int i, kept: int kept): [count:nat | count <= n] int count =
  if i >= n then kept
  else let
    val b = $A.read<byte>(identifier, i)
  in
    if _is_space(byte2int0(b)) then _strip(identifier, n, clean, i + 1, kept)
    else let
      val () = $A.set<byte>(clean, kept, b)
    in _strip(identifier, n, clean, i + 1, kept + 1) end
  end

(* The IDPF key of the unique identifier identifier[0, n): key[0, 20) := the
   SHA-1 of it without its white space; false when nothing is left of it *)
#pub fn idpf_key {l:agz}{n:pos | n <= 4096}{lk:agz}
  (identifier: !$A.borrow(byte, l, n), n: int n, key: !$A.arr(byte, lk, 20)): bool

implement idpf_key (identifier, n, key) = let
  val clean = $A.alloc<byte>(n)
  val kept = _strip(identifier, n, clean, 0, 0)
in
  if kept <= 0 then let val () = $A.free<byte>(clean) in false end
  else let
    val @(clean_frozen, clean_bytes) = $A.freeze<byte>(clean)
    val () = $SHA.sha1_digest(clean_bytes, kept, key)
    val () = $A.drop<byte>(clean_frozen, clean_bytes)
    val () = $A.free<byte>($A.thaw<byte>(clean_frozen))
  in true end
end

(* The value of the hex digit c, or -1 *)
fn _hex_value {c:int} (c: int c): [d:int | ~1 <= d; d < 16] int d =
  if c < 48 then ~1
  else if c <= 57 then c - 48
  else if c < 65 then ~1
  else if c <= 70 then c - 55
  else if c < 97 then ~1
  else if c <= 102 then c - 87
  else ~1

(* Where the UUID begins in the identifier: after its last colon (urn:uuid:), else at its start *)
fun _uuid_start {l:agz}{n:pos}{i:nat | i <= n}{start:nat | start <= n} .<n - i>.
  (identifier: !$A.borrow(byte, l, n), n: int n, i: int i, start: int start): [s:nat | s <= n] int s =
  if i >= n then start
  else if byte2int0($A.read<byte>(identifier, i)) = 58 then _uuid_start(identifier, n, i + 1, i + 1)
  else _uuid_start(identifier, n, i + 1, start)

(* key[0, 16) := the hex digits of identifier[i, n) in pairs, its dashes passed over;
   whether there were exactly 32 of them and nothing else *)
fun _uuid_digits {l,lk:agz}{n:pos}{i:nat | i <= n}{done:nat | done <= 16}{half:nat | half < 2}{pending:nat | pending <= 240} .<n - i>.
  (identifier: !$A.borrow(byte, l, n), n: int n, key: !$A.arr(byte, lk, 16), i: int i, done: int done, half: int half, pending: int pending): bool =
  if i >= n then (done = 16 && half = 0)
  else let
    val c = byte2int0($A.read<byte>(identifier, i))
  in
    if c = 45 then _uuid_digits(identifier, n, key, i + 1, done, half, pending)
    else let
      val d = _hex_value(g1ofg0(c))
    in
      if d < 0 then false
      else if done >= 16 then false
      else if half = 0 then _uuid_digits(identifier, n, key, i + 1, done, 1, d * 16)
      else let
        val () = $A.set<byte>(key, done, $A.int2byte(pending + d))
      in _uuid_digits(identifier, n, key, i + 1, done + 1, 0, 0) end
    end
  end

(* The Adobe key of the unique identifier identifier[0, n): key[0, 16) := the
   bytes of its UUID; false when it is not one *)
#pub fn adobe_key {l:agz}{n:pos}{lk:agz}
  (identifier: !$A.borrow(byte, l, n), n: int n, key: !$A.arr(byte, lk, 16)): bool

implement adobe_key (identifier, n, key) =
  _uuid_digits(identifier, n, key, _uuid_start(identifier, n, 0, 0), 0, 0, 0)

(* font[at, stop) xored with the key, which goes round, from its place j *)
fun _unmask {l,lk:agz}{o:addr}{n:pos}{k:pos}{stop:nat | stop <= n}{at:nat | at <= stop}{j:nat | j < k} .<stop - at>.
  (font: !$A.arrx(byte, l, n, o), key: !$A.arr(byte, lk, k), key_len: int k, stop: int stop, at: int at, j: int j): void =
  if at >= stop then ()
  else let
    val masked = _word(byte2int0($A.get<byte>(font, at)))
    val mask = _word(byte2int0($A.get<byte>(key, j)))
    val () = $A.set<byte>(font, at, $A.int2byte(_byte(masked lxor mask)))
    val next = (if j + 1 >= key_len then 0 else j + 1): [next:nat | next < k] int next
  in _unmask(font, key, key_len, stop, at + 1, next) end

(* The first masked bytes of font[0, font_len) xored with key[0, key_len), which goes
   round (a font shorter than that has all of its bytes xored) *)
#pub fn font_unmask {l,lk:agz}{o:addr}{n:pos}{k:pos}
  (font: !$A.arrx(byte, l, n, o), font_len: int n, key: !$A.arr(byte, lk, k), key_len: int k, masked: int): void

implement font_unmask {l,lk}{o}{n}{k} (font, font_len, key, key_len, masked) = let
  val limit = g1ofg0(masked)
  val stop = (if limit < font_len then (if limit < 0 then 0 else limit) else font_len): [stop:nat | stop <= n] int stop
in _unmask(font, key, key_len, stop, 0, 0) end
