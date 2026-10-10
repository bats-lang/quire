(* zipcheck -- the two things in a zip that EPUB's OCF (EPUB 3.3 §4.1.2)
   forbids and that the zip package, which reads what it can, passes over:
   an archive split into segments, and an entry compressed by anything but
   Deflate (or stored). The zip package leaves such an entry out of its
   references, so without this the book would open with a chapter gone
   (quire#419, the suite's ocf-zip-mult and ocf-zip-comp: "MUST treat any
   OCF ZIP container that ... as in error"). It reads the end record and
   the central directory's own fields, which the zip package has read
   once already. *)

#include "share/atspre_staload.hats"
#use array as A

(* Why an archive is refused: nothing is wrong with it (that this checks),
   it is split into segments, or an entry uses a method other than 0 or 8 *)
#pub datatype zip_refusal = ZipAllowed | ZipSplit | ZipOtherCompression

(* The byte at i of data, or -1 outside it *)
fn _byte_at {l:agz}{n:pos}{i:int} (data: !$A.arr(byte, l, n), n: int n, i: int i): int =
  if i < 0 then ~1
  else if i >= n then ~1
  else byte2int0($A.get<byte>(data, i))

(* The little endian 16 bit number at i of data, or -1 outside it *)
fn _u16 {l:agz}{n:pos}{i:int} (data: !$A.arr(byte, l, n), n: int n, i: int i): [v:int] int v = let
  val low = _byte_at(data, n, i)
  val high = _byte_at(data, n, i + 1)
in if low < 0 then ~1 else if high < 0 then ~1 else g1ofg0(low + 256 * high) end

(* The position of the end record that ends exactly at the end of
   tail[0, n) (its comment's length says so), looking back from p; -1 *)
fun _end_record {l:agz}{n:pos}{p:int | p <= n} .<max(p + 1, 0)>.
  (tail: !$A.arr(byte, l, n), n: int n, p: int p): [q:int | ~1 <= q; q <= n] int q =
  if p < 0 then ~1
  else if _byte_at(tail, n, p) = 80 && _byte_at(tail, n, p + 1) = 75 && _byte_at(tail, n, p + 2) = 5 && _byte_at(tail, n, p + 3) = 6
          && _u16(tail, n, p + 20) = n - (p + 22) then p
  else _end_record(tail, n, p - 1)

(* Whether the end record in tail[0, n) names this one disk as the archive's
   only: its disk number and the disk the directory starts on are 0, and
   the entries on this disk are all of them *)
#pub fn zip_end_refusal {l:agz}{n:pos} (tail: !$A.arr(byte, l, n), n: int n): zip_refusal

implement zip_end_refusal (tail, n) = let
  val p = _end_record(tail, n, n - 22)
in
  if p < 0 then ZipAllowed()
  else if _u16(tail, n, p + 4) <> 0 then ZipSplit()
  else if _u16(tail, n, p + 6) <> 0 then ZipSplit()
  else if _u16(tail, n, p + 8) <> _u16(tail, n, p + 10) then ZipSplit()
  else ZipAllowed()
end

(* The method of each entry of the central directory directory[c, n) *)
fun _methods {l:agz}{n:pos}{c:nat | c <= n} .<n - c>.
  (directory: !$A.arr(byte, l, n), n: int n, c: int c): zip_refusal =
  if c + 46 > n then ZipAllowed()
  else if _byte_at(directory, n, c) <> 80 || _byte_at(directory, n, c + 1) <> 75 || _byte_at(directory, n, c + 2) <> 1 || _byte_at(directory, n, c + 3) <> 2 then ZipAllowed()
  else let
    val method = _u16(directory, n, c + 10)
    val next = c + 46 + _u16(directory, n, c + 28) + _u16(directory, n, c + 30) + _u16(directory, n, c + 32)
  in
    if method <> 0 && method <> 8 then ZipOtherCompression()
    else if next <= c then ZipAllowed()
    else if next > n then ZipAllowed()
    else _methods(directory, n, next)
  end

(* Whether an entry of the central directory in directory[0, n) is
   compressed by a method other than stored or Deflate *)
#pub fn zip_directory_refusal {l:agz}{n:pos} (directory: !$A.arr(byte, l, n), n: int n): zip_refusal

implement zip_directory_refusal (directory, n) =
  _methods(directory, n, 0)
