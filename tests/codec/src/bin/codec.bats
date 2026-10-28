#target native

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR

staload "bytes.sats"
staload "bytesarr.sats"
staload "crc.sats"
staload "schema.sats"
staload "record.sats"
staload "bookrec.sats"
staload "bookimage.sats"
staload "wordrec.sats"
staload "wordimage.sats"

(* What the codec's proofs cannot say, and the app's callers rely on:
   the checksum is the CRC-32 everyone knows, the numbers at the edge of
   32 bits are kept as they are, a record is read back as it was
   written and written again as it was read, and no damage to it gives a
   record that is not the one written. *)

val _failures = ref<int>(0)

fn fail (what: string): void = let
  val () = println! ("FAIL ", what)
in !_failures := !_failures + 1 end

fn expect (ok: bool, what: string): void = if ok then () else fail(what)

(* ---------------- a sixteen bit generator ---------------- *)

val _state = ref<[seed:nat | seed < 65536] int seed>(12345)

(* the next number under 65536 (the generator with multiplier 25173 and
   increment 13849 visits every one of them) *)
fn next_number (): [value:nat | value < 65536] int value = let
  val state = !_state
  val product = $AR.mul_g1(state, 25173)
  val next = $AR.band_g1($AR.add_g1(product, 13849), 65535)
  val () = !_state := next
in next end

(* ---------------- a book image from a number ---------------- *)

fn numbers_with (value: Int, progress: Int, directions: Int, series: Int): book_numbers = @{
  id_high = value, id_low = value, collections = value, collections_modified = value, minutes_elsewhere = value,
  pages_elsewhere = value, finished_at = value, finished_modified = value, chapter = value, chapters = value,
  page = value, pages = value, anchor = value, place_modified = value, place_declined = value, position = value,
  series_number = value, shelf = value, added = value, opened = value, shelf_modified = value, file_size = value,
  cover = value, done = value, minutes_read = value, pages_read = value, progress_weighted = progress, text_directions = directions, series_position = series
}

fn numbers_of (value: Int): book_numbers = numbers_with(value, value, value, value)

fn text_of {n:nat | n < 256} (len: int n, letter: int): [l:agz] $A.arr(byte, l, n + 1) = let
  val text = $A.alloc<byte>(len + 1)
  fun fill {l:agz}{i:nat | i <= n} .<n - i>. (text: !$A.arr(byte, l, n + 1), i: int i): void =
    if i >= len then ()
    else let
      val () = $A.set<byte>(text, i, $A.int2byte($AR.band_g1($AR.add_g1(i, 65 + 256 * 4), 127)))
    in fill(text, i + 1) end
  val () = fill(text, 0)
in text end

(* An image of some book *)
datavtype tested =
  | {contents:bookx} Tested of book_image(contents)
  | NoTested of ()

fn image_of {title_n,author_n,series_n:nat | title_n < 256; author_n < 256; series_n < 256} (value: Int, title_len: int title_n, author_len: int author_n, series_len: int series_n): tested =
  case+ book_image_make(numbers_of(value), text_of(author_len, 1), author_len, text_of(series_len, 2), series_len, text_of(title_len, 3), title_len) of
  | ~BookImaged(image) => Tested(image)
  | ~BookNotImaged() => let val () = fail("an image of a number of 32 bits") in NoTested() end

(* ---------------- bytes in arrays ---------------- *)

(* the record of an image, written: its bytes and their count *)
fn encode {contents:bookx} (image: !book_image(contents)): [l:agz][n:pos | n <= 1048576] @($A.arr(byte, l, n), int n) = let
  val record = book_record_new(image)
  val (_ | list) = book_record_write(record)
  val () = book_record_free(record)
  val (_ | count) = blist_len(list)
in
  if count >= 1 then
    (if count <= 1048576 then let
       val bytes = blist_to_buffer(list, count)
       val () = blist_free(list)
     in @(bytes, count) end
     else let val () = blist_free(list) val one = $A.alloc<byte>(1) in @(one, 1) end)
  else let val () = blist_free(list) val one = $A.alloc<byte>(1) in @(one, 1) end
end

fn copy_of {l:agz}{n:pos | n <= 1048576} (bytes: !$A.arr(byte, l, n), n: int n): [copy_l:agz] $A.arr(byte, copy_l, n) = let
  val copy = $A.alloc<byte>(n)
  fun copy_byte {copy_l:agz}{i:nat | i <= n} .<n - i>. (bytes: !$A.arr(byte, l, n), copy: !$A.arr(byte, copy_l, n), i: int i): void =
    if i >= n then ()
    else let val () = $A.set<byte>(copy, i, $A.get<byte>(bytes, i)) in copy_byte(bytes, copy, i + 1) end
  val () = copy_byte(bytes, copy, 0)
in copy end

fun equal_prefix {first_l,second_l:agz}{first_n,second_n:pos}{i:nat | i <= first_n; first_n == second_n} .<first_n - i>.
  (first: !$A.arr(byte, first_l, first_n), second: !$A.arr(byte, second_l, second_n), n: int first_n, i: int i): bool =
  if i >= n then true
  else if byte2int0($A.get<byte>(first, i)) <> byte2int0($A.get<byte>(second, i)) then false
  else equal_prefix(first, second, n, i + 1)

(* ---------------- reading, and what the reading comes to ---------------- *)

(* 0 whole and the same image, 1 whole but another image, 2 lost a group,
   3 not a record, 4 newer, 5 damaged; and, for a whole record, whether it
   is written again as the bytes it was read from *)
fn classify {l:agz}{n:pos | n <= 1048576}{contents:bookx} (bytes: !$A.arr(byte, l, n), n: int n, original: !book_image(contents)): @(int, bool) = let
  val list = blist_of_array(bytes, 0, n)
  val (_ | read) = book_record_read(list)
in
  case+ read of
  | ~BR_ok(record) => let
      val back = book_record_image(record)
      val same = (book_image_diff(original, back) = 0)
      val () = book_image_free(back)
      val (_ | again) = book_record_write(record)
      val (_ | count) = blist_len(again)
      val written = (if count = n then let
          val rewritten = blist_to_buffer(again, n)
          val equal = equal_prefix(bytes, rewritten, n, 0)
          val () = $A.free<byte>(rewritten)
        in equal end else false): bool
      val () = blist_free(again)
      val () = book_record_free(record)
    in @(if same then 0 else 1, written) end
  | ~BR_loss(record, lost) => let
      val () = lostv_free(lost)
      val () = book_record_free(record)
    in @(2, true) end
  | ~BR_notquire() => @(3, true)
  | ~BR_newer() => @(4, true)
  | ~BR_damaged() => @(5, true)
end

(* The record of bytes, read and written again: whether it is read whole and written as other, other_n bytes *)
fn rewritten_as {l:agz}{n:pos | n <= 1048576}{other_l:agz}{other_n:pos | other_n <= 1048576}
  (bytes: !$A.arr(byte, l, n), n: int n, other: !$A.arr(byte, other_l, other_n), other_n: int other_n): bool = let
  val list = blist_of_array(bytes, 0, n)
  val (_ | read) = book_record_read(list)
in
  case+ read of
  | ~BR_ok(record) => let
      val (_ | again) = book_record_write(record)
      val (_ | count) = blist_len(again)
      val equal = (if count = other_n then let
          val rewritten = blist_to_buffer(again, other_n)
          val same = equal_prefix(other, rewritten, other_n, 0)
          val () = $A.free<byte>(rewritten)
        in same end else false): bool
      val () = blist_free(again)
      val () = book_record_free(record)
    in equal end
  | ~BR_loss(record, lost) => let
      val () = lostv_free(lost)
      val () = book_record_free(record)
    in false end
  | ~BR_notquire() => false
  | ~BR_newer() => false
  | ~BR_damaged() => false
end

(* ---------------- groups added later, absent from a record (#497) ---------------- *)

(* a byte of the array, or 0 outside it *)
fn byte_at {l:agz}{n:pos}{i:int} (bytes: !$A.arr(byte, l, n), n: int n, i: int i): int =
  if i >= 0 then (if i < n then byte2int0($A.get<byte>(bytes, i)) else 0) else 0

(* bytes[from, to) put into dst from at on; the next place *)
fun put_span {l:agz}{n:pos}{dl:agz}{dn:pos}{from,to,at:nat | from <= to; to <= n} .<to - from>.
  (bytes: !$A.arr(byte, l, n), n: int n, dst: !$A.arr(byte, dl, dn), dn: int dn, from: int from, to: int to, at: int at): [r:nat] int r =
  if from >= to then at
  else let
    val () = (if at < dn then $A.set<byte>(dst, at, $A.get<byte>(bytes, from)) else ())
  in put_span(bytes, n, dst, dn, from + 1, to, at + 1) end

(* the same, unless the group is dropped *)
fn put_span_unless {l:agz}{n:pos}{dl:agz}{dn:pos}{from,to,at:nat | from <= to; to <= n}
  (drop: bool, bytes: !$A.arr(byte, l, n), n: int n, dst: !$A.arr(byte, dl, dn), dn: int dn, from: int from, to: int to, at: int at): [r:nat] int r =
  if drop then at else put_span(bytes, n, dst, dn, from, to, at)

(* the size of the record without the groups dropped, each 16 bytes *)
fn kept_size {n:pos | n >= 60} (n: int n, drop_prog: bool, drop_snum: bool, drop_tdir: bool): [k:int | k >= 12; k <= n] int k =
  if drop_prog then
    (if drop_snum then (if drop_tdir then n - 48 else n - 32) else (if drop_tdir then n - 32 else n - 16))
  else
    (if drop_snum then (if drop_tdir then n - 32 else n - 16) else (if drop_tdir then n - 16 else n))

(* the record without the added groups it is told to drop. The groups are the last three before the end chunk
   (prog, snum, tdir, each 16 bytes: a four byte number), and the end chunk is 12 bytes. *)
fn without_added {l:agz}{n:pos | n >= 60; n <= 1048576} (bytes: !$A.arr(byte, l, n), n: int n, drop_prog: bool, drop_snum: bool, drop_tdir: bool)
  : [m:pos | m <= 1048576] @([copy_l:agz] $A.arr(byte, copy_l, m), int m) = let
  val kept = kept_size(n, drop_prog, drop_snum, drop_tdir)
  val copy = $A.alloc<byte>(kept)
  val at = put_span(bytes, n, copy, kept, 0, n - 60, 0)
  val at = put_span_unless(drop_prog, bytes, n, copy, kept, n - 60, n - 44, at)
  val at = put_span_unless(drop_snum, bytes, n, copy, kept, n - 44, n - 28, at)
  val at = put_span_unless(drop_tdir, bytes, n, copy, kept, n - 28, n - 12, at)
  val _ = put_span(bytes, n, copy, kept, n - 12, n, at)
in @(copy, kept) end

fn image_defaulted (drop_prog: bool, drop_snum: bool, drop_tdir: bool): tested = let
  val numbers = numbers_with(31337, (if drop_prog then 0 else 31337), (if drop_tdir then 0 else 31337), (if drop_snum then 0 else 31337))
in
  case+ book_image_make(numbers, text_of(7, 1), 7, text_of(5, 2), 5, text_of(9, 3), 9) of
  | ~BookImaged(image) => Tested(image)
  | ~BookNotImaged() => let val () = fail("an image of a number of 32 bits") in NoTested() end
end

(* A record written before some of the added groups existed is read whole, with their defaults, and is
   written with all of them: the record of the image holding those defaults *)
fn check_absent_added (drop_prog: bool, drop_snum: bool, drop_tdir: bool): void =
  case+ image_of(31337, 9, 7, 5) of
  | ~NoTested() => ()
  | ~Tested(full) =>
    (case+ image_defaulted(drop_prog, drop_snum, drop_tdir) of
     | ~NoTested() => book_image_free(full)
     | ~Tested(expected) => let
         val @(bytes, n) = encode(full)
         val @(expected_bytes, expected_n) = encode(expected)
         val any = (drop_prog || drop_snum || drop_tdir)
         val () = (if n >= 60 then (if n <= 1048576 then let
             (* the layout this relies on: prog, snum, tdir, then IEND *)
             val () = expect(byte_at(bytes, n, n - 60 + 4) = 112 && byte_at(bytes, n, n - 44 + 4) = 115 && byte_at(bytes, n, n - 28 + 4) = 116 && byte_at(bytes, n, n - 12 + 4) = 73, "the added groups are the last before IEND")
             val @(cut, m) = without_added(bytes, n, drop_prog, drop_snum, drop_tdir)
             val @(code, written) = classify(cut, m, expected)
             val () = expect(code = 0, "a record without added groups is read whole, with their defaults")
             val () = expect((if any then (not written) else written), "a record without added groups is written with them; one with all of them as it was")
             val () = expect(rewritten_as(cut, m, expected_bytes, expected_n), "a record without added groups is written as the record of their defaults")
             val () = $A.free<byte>(cut)
           in () end else fail("a record of a sensible size")) else fail("a record of a sensible size"))
         val () = $A.free<byte>(expected_bytes)
         val () = $A.free<byte>(bytes)
         val () = book_image_free(expected)
       in book_image_free(full) end)

fn check_absent (): void = let
  val () = check_absent_added(false, false, false)
  val () = check_absent_added(true, false, false)
  val () = check_absent_added(false, true, false)
  val () = check_absent_added(false, false, true)
  val () = check_absent_added(true, true, false)
  val () = check_absent_added(true, false, true)
  val () = check_absent_added(false, true, true)
in check_absent_added(true, true, true) end

(* ---------------- chunks in any order, a tag twice (#510) ---------------- *)

(* The record of image_of(_, 9, 7, 5) is 339 bytes: a header of 7, then the chunks AUTH BOOK COLL ELSE FNSH (20 each),
   ORDR 16, PLCE 40, SERI 22, SHLF 28, SIZE 24, TIME 20, TITL 22, prog snum tdir (16 each) and the end chunk, 12; they
   start at 7 27 47 67 87 107 123 163 185 213 237 257 279 295 311 327. *)

(* the record with the chunks between its header and its end chunk in the opposite order *)
fn reversed_chunks {l:agz}{n:pos | n == 339} (bytes: !$A.arr(byte, l, n), n: int n): [copy_l:agz] $A.arr(byte, copy_l, n) = let
  val copy = $A.alloc<byte>(n)
  (* a chunk [from, to) goes where the same distance from the end of the chunks is *)
  val _ = put_span(bytes, n, copy, n, 0, 7, 0)
  val _ = put_span(bytes, n, copy, n, 327, 339, 327)
  val _ = put_span(bytes, n, copy, n, 7, 27, 307)
  val _ = put_span(bytes, n, copy, n, 27, 47, 287)
  val _ = put_span(bytes, n, copy, n, 47, 67, 267)
  val _ = put_span(bytes, n, copy, n, 67, 87, 247)
  val _ = put_span(bytes, n, copy, n, 87, 107, 227)
  val _ = put_span(bytes, n, copy, n, 107, 123, 211)
  val _ = put_span(bytes, n, copy, n, 123, 163, 171)
  val _ = put_span(bytes, n, copy, n, 163, 185, 149)
  val _ = put_span(bytes, n, copy, n, 185, 213, 121)
  val _ = put_span(bytes, n, copy, n, 213, 237, 97)
  val _ = put_span(bytes, n, copy, n, 237, 257, 77)
  val _ = put_span(bytes, n, copy, n, 257, 279, 55)
  val _ = put_span(bytes, n, copy, n, 279, 295, 39)
  val _ = put_span(bytes, n, copy, n, 295, 311, 23)
  val _ = put_span(bytes, n, copy, n, 311, 327, 7)
in copy end

(* the record with the BOOK chunk (the second) of another record of the same shape put in front of its own chunks: a
   tag twice, the later one the record's own *)
fn with_stale_chunk_first {l:agz}{other_l:agz}{n:pos | n == 339} (bytes: !$A.arr(byte, l, n), other: !$A.arr(byte, other_l, n), n: int n)
  : [copy_l:agz] $A.arr(byte, copy_l, 359) = let
  val copy = $A.alloc<byte>(359)
  val _ = put_span(bytes, n, copy, 359, 0, 7, 0)
  val _ = put_span(other, n, copy, 359, 27, 47, 7)
  val _ = put_span(bytes, n, copy, 359, 7, 339, 27)
in copy end

(* a record read whole or with a loss, and the image it is: 0 whole and the same, 1 whole and another, 2 with a loss and the same,
   3 with a loss and another, 4 not read; and whether it is written again as other, other_n bytes *)
fn written_as {other_l:agz}{other_n:pos | other_n <= 1048576}{record_contents:bookx}{format_version,least_version:int}{kept_extras:extras}
  (record: !bookrecord(record_contents, format_version, least_version, kept_extras), other: !$A.arr(byte, other_l, other_n), other_n: int other_n): bool = let
  val (_ | again) = book_record_write(record)
  val (_ | count) = blist_len(again)
  val equal = (if count = other_n then let
      val rewritten = blist_to_buffer(again, other_n)
      val same = equal_prefix(other, rewritten, other_n, 0)
      val () = $A.free<byte>(rewritten)
    in same end else false): bool
  val () = blist_free(again)
in equal end

fn classify_same {l:agz}{n:pos | n <= 1048576}{contents:bookx}{other_l:agz}{other_n:pos | other_n <= 1048576}
  (bytes: !$A.arr(byte, l, n), n: int n, original: !book_image(contents), other: !$A.arr(byte, other_l, other_n), other_n: int other_n): @(int, bool) = let
  val list = blist_of_array(bytes, 0, n)
  val (_ | read) = book_record_read(list)
in
  case+ read of
  | ~BR_ok(record) => let
      val back = book_record_image(record)
      val same = (book_image_diff(original, back) = 0)
      val () = book_image_free(back)
      val written = written_as(record, other, other_n)
      val () = book_record_free(record)
    in @(if same then 0 else 1, written) end
  | ~BR_loss(record, lost) => let
      val back = book_record_image(record)
      val same = (book_image_diff(original, back) = 0)
      val () = book_image_free(back)
      val written = written_as(record, other, other_n)
      val () = lostv_free(lost)
      val () = book_record_free(record)
    in @(if same then 2 else 3, written) end
  | ~BR_notquire() => @(4, false)
  | ~BR_newer() => @(4, false)
  | ~BR_damaged() => @(4, false)
end

fn check_any_order (): void =
  case+ image_of(31337, 9, 7, 5) of
  | ~NoTested() => ()
  | ~Tested(image) =>
    (case+ image_of(4242, 9, 7, 5) of
     | ~NoTested() => book_image_free(image)
     | ~Tested(other_image) => let
         val @(bytes, n) = encode(image)
         val @(other_bytes, other_n) = encode(other_image)
         val () = (if n = 339 then (if other_n = 339 then let
             val () = expect(byte_at(bytes, n, 7 + 4) = 65 && byte_at(bytes, n, 327 + 4) = 73 && byte_at(bytes, n, 311 + 4) = 116, "the layout the order tests rely on")
             (* the chunks in the opposite order are the same record, and saving writes them in ascending order *)
             val reversed = reversed_chunks(bytes, n)
             val @(code, written) = classify_same(reversed, n, image, bytes, n)
             val () = expect(code = 0, "a record with its chunks in the opposite order is read whole, as the same record")
             val () = expect(written, "a record with its chunks in the opposite order is written in ascending order")
             val () = $A.free<byte>(reversed)
             (* a tag twice: the later chunk wins, the record is read with a loss, and written once for each tag *)
             val doubled = with_stale_chunk_first(bytes, other_bytes, n)
             val @(code, written) = classify_same(doubled, 359, image, bytes, n)
             val () = expect(code = 2, "a group twice: the record is read with a loss, as the same record (the later chunk wins)")
             val () = expect(written, "a group twice is written once")
             val () = $A.free<byte>(doubled)
             (* and whichever it is that comes last wins *)
             val doubled_other = with_stale_chunk_first(other_bytes, bytes, n)
             val @(code, written) = classify_same(doubled_other, 359, other_image, other_bytes, n)
             val () = expect(code = 2, "a group twice: the later chunk wins, whichever it is")
             val () = expect(written, "a group twice, the other way, is written once")
             val () = $A.free<byte>(doubled_other)
           in () end else fail("a record of the shape the order tests rely on")) else fail("a record of the shape the order tests rely on"))
         val () = $A.free<byte>(other_bytes)
         val () = $A.free<byte>(bytes)
         val () = book_image_free(other_image)
       in book_image_free(image) end)

(* ---------------- a group the record needs, lost (#510) ---------------- *)

(* the size of the record without the chunks of the groups it is told to drop (AUTH 20 bytes, BOOK 20, TITL 22) *)
fn needed_size (drop_auth: bool, drop_book: bool, drop_titl: bool): [k:pos | k <= 339] int k =
  if drop_auth then
    (if drop_book then (if drop_titl then 277 else 299) else (if drop_titl then 297 else 319))
  else
    (if drop_book then (if drop_titl then 297 else 319) else (if drop_titl then 317 else 339))

(* the record without the chunks of the groups it is told to drop (AUTH 7..27, BOOK 27..47, TITL 257..279) *)
fn without_needed {l:agz}{n:pos | n == 339} (bytes: !$A.arr(byte, l, n), n: int n, drop_auth: bool, drop_book: bool, drop_titl: bool)
  : [m:pos | m <= 339] @([copy_l:agz] $A.arr(byte, copy_l, m), int m) = let
  val kept = needed_size(drop_auth, drop_book, drop_titl)
  val copy = $A.alloc<byte>(kept)
  val at = put_span(bytes, n, copy, kept, 0, 7, 0)
  val at = put_span_unless(drop_auth, bytes, n, copy, kept, 7, 27, at)
  val at = put_span_unless(drop_book, bytes, n, copy, kept, 27, 47, at)
  val at = put_span(bytes, n, copy, kept, 47, 257, at)
  val at = put_span_unless(drop_titl, bytes, n, copy, kept, 257, 279, at)
  val _ = put_span(bytes, n, copy, kept, 279, 339, at)
in @(copy, kept) end

(* a copy of the record, with the byte at a place changed (so that the CRC of its chunk no longer holds) when it is told to *)
fn copy_spoiled {l:agz}{n:pos | n == 339}{at:nat | at < 339} (bytes: !$A.arr(byte, l, n), n: int n, spoil: bool, at: int at): [copy_l:agz] $A.arr(byte, copy_l, n) = let
  val copy = copy_of(bytes, n)
  val () = (if spoil then $A.set<byte>(copy, at, $A.int2byte($AR.band_g1($AR.add_g1($AR.low_byte(byte2int0($A.get<byte>(bytes, at))), 90), 255))) else ())
in copy end

(* the record with a byte of the data of each group it is told to damage changed (AUTH, BOOK, TITL) *)
fn damaged_needed {l:agz}{n:pos | n == 339} (bytes: !$A.arr(byte, l, n), n: int n, damage_auth: bool, damage_book: bool, damage_titl: bool)
  : [copy_l:agz] $A.arr(byte, copy_l, n) = let
  val first = copy_spoiled(bytes, n, damage_auth, 15)
  val second = copy_spoiled(first, n, damage_book, 35)
  val () = $A.free<byte>(first)
  val third = copy_spoiled(second, n, damage_titl, 265)
  val () = $A.free<byte>(second)
in third end

fn tested_of {contents:bookx} (made: book_imaged(contents)): tested =
  case+ made of
  | ~BookImaged(image) => Tested(image)
  | ~BookNotImaged() => let val () = fail("an image of a number of 32 bits") in NoTested() end

(* the image of the record without those groups: their substitutes stand in *)
fn image_lacking (drop_auth: bool, drop_book: bool, drop_titl: bool): tested = let
  val numbers = numbers_of(31337)
  val numbers = @{id_high = (if drop_book then 0 else numbers.id_high), id_low = (if drop_book then 0 else numbers.id_low), collections = numbers.collections,
    collections_modified = numbers.collections_modified, minutes_elsewhere = numbers.minutes_elsewhere, pages_elsewhere = numbers.pages_elsewhere,
    finished_at = numbers.finished_at, finished_modified = numbers.finished_modified, chapter = numbers.chapter, chapters = numbers.chapters,
    page = numbers.page, pages = numbers.pages, anchor = numbers.anchor, place_modified = numbers.place_modified, place_declined = numbers.place_declined,
    position = numbers.position, series_number = numbers.series_number, shelf = numbers.shelf, added = numbers.added, opened = numbers.opened,
    shelf_modified = numbers.shelf_modified, file_size = numbers.file_size, cover = numbers.cover, done = numbers.done, minutes_read = numbers.minutes_read,
    pages_read = numbers.pages_read, progress_weighted = numbers.progress_weighted, text_directions = numbers.text_directions, series_position = numbers.series_position}: book_numbers
  val untitled = $A.alloc<byte>(9)
  val () = $A.set<byte>(untitled, 0, $A.int2byte(85))
  val () = $A.set<byte>(untitled, 1, $A.int2byte(110))
  val () = $A.set<byte>(untitled, 2, $A.int2byte(116))
  val () = $A.set<byte>(untitled, 3, $A.int2byte(105))
  val () = $A.set<byte>(untitled, 4, $A.int2byte(116))
  val () = $A.set<byte>(untitled, 5, $A.int2byte(108))
  val () = $A.set<byte>(untitled, 6, $A.int2byte(101))
  val () = $A.set<byte>(untitled, 7, $A.int2byte(100))
  val () = $A.set<byte>(untitled, 8, $A.int2byte(0))
  val nothing = $A.alloc<byte>(1)
  val () = $A.set<byte>(nothing, 0, $A.int2byte(0))
in
  if drop_auth then
    (if drop_titl then tested_of(book_image_make(numbers, nothing, 0, text_of(5, 2), 5, untitled, 8))
     else let val () = $A.free<byte>(untitled) in tested_of(book_image_make(numbers, nothing, 0, text_of(5, 2), 5, text_of(9, 3), 9)) end)
  else
    (if drop_titl then let val () = $A.free<byte>(nothing) in tested_of(book_image_make(numbers, text_of(7, 1), 7, text_of(5, 2), 5, untitled, 8)) end
     else let
       val () = $A.free<byte>(nothing)
       val () = $A.free<byte>(untitled)
     in tested_of(book_image_make(numbers, text_of(7, 1), 7, text_of(5, 2), 5, text_of(9, 3), 9)) end)
end

(* read with a loss, as the image whose substitutes stand in, and written as the record of that image *)
fn expect_lost (code: int, written: bool): void = let
  val () = expect(code = 2, "a record that lost a group it needs is used, with the group's substitute, and the loss is said")
in expect(written, "a record that lost a group it needs is written whole") end

fn check_needed_lost_with (drop_auth: bool, drop_book: bool, drop_titl: bool, damage: bool): void =
  case+ image_of(31337, 9, 7, 5) of
  | ~NoTested() => ()
  | ~Tested(full) =>
    (case+ image_lacking(drop_auth, drop_book, drop_titl) of
     | ~NoTested() => book_image_free(full)
     | ~Tested(expected) => let
         val @(bytes, n) = encode(full)
         val @(expected_bytes, expected_n) = encode(expected)
         val () = (if n = 339 then let
             val () = (if damage then let
                 val spoiled = damaged_needed(bytes, n, drop_auth, drop_book, drop_titl)
                 val @(code, written) = classify_same(spoiled, n, expected, expected_bytes, expected_n)
                 val () = expect_lost(code, written)
               in $A.free<byte>(spoiled) end else let
                 val @(cut, m) = without_needed(bytes, n, drop_auth, drop_book, drop_titl)
                 val @(code, written) = classify_same(cut, m, expected, expected_bytes, expected_n)
                 val () = expect_lost(code, written)
               in $A.free<byte>(cut) end)
           in () end else fail("a record of the shape these tests rely on"))
         val () = $A.free<byte>(expected_bytes)
         val () = $A.free<byte>(bytes)
         val () = book_image_free(expected)
       in book_image_free(full) end)

fn check_needed_lost (): void = let
  val () = check_needed_lost_with(true, false, false, false)
  val () = check_needed_lost_with(false, true, false, false)
  val () = check_needed_lost_with(false, false, true, false)
  val () = check_needed_lost_with(true, true, true, false)
  val () = check_needed_lost_with(true, false, false, true)
  val () = check_needed_lost_with(false, true, false, true)
  val () = check_needed_lost_with(false, false, true, true)
in check_needed_lost_with(true, true, true, true) end

(* ---------------- a record cut in its framing (#614) ---------------- *)

(* The record of image_of(31337, 9, 7, 5) is 339 bytes: the 7 byte header, the chunks, and the end chunk, 12 bytes. A record cut anywhere
   after its header (bytes missing, a length past the end or over the limit, bytes after the end chunk) keeps the chunks that were whole
   before the cut, loses the groups after them (their substitutes stand in) and is used: it reads as the record of its whole chunks
   and the end chunk, with a loss said. *)

(* where the chunk that is cut at length begins: the chunks of the record before it are whole *)
fun chunk_boundary {l:agz}{n:pos | n <= 1048576}{o:nat | o <= n} .<n - o>.
  (bytes: !$A.arr(byte, l, n), n: int n, length: int, o: int o): [b:nat | b <= n] int b =
  if o + 4 >= n then o
  else let
    val size = 12 + $AR.low_byte(byte2int0($A.get<byte>(bytes, o))) + 256 * $AR.low_byte(byte2int0($A.get<byte>(bytes, o + 1)))
  in
    if o + size <= length then (if o + size <= n then chunk_boundary(bytes, n, length, o + size) else o)
    else o
  end

(* the chunks of the record before b, and its end chunk *)
fn closed_at {l:agz}{n:pos | n == 339}{b:nat | b <= 327} (bytes: !$A.arr(byte, l, n), n: int n, b: int b): [copy_l:agz] $A.arr(byte, copy_l, b + 12) = let
  val copy = $A.alloc<byte>(b + 12)
  val at = put_span(bytes, n, copy, b + 12, 0, b, 0)
  val _ = put_span(bytes, n, copy, b + 12, 327, 339, at)
in copy end

(* the first length bytes of the record *)
fn prefix_of {l:agz}{n:pos | n <= 1048576}{length:pos | length <= n} (bytes: !$A.arr(byte, l, n), n: int n, length: int length): [copy_l:agz] $A.arr(byte, copy_l, length) = let
  val copy = $A.alloc<byte>(length)
  val _ = put_span(bytes, n, copy, length, 0, length, 0)
in copy end

(* the record with the byte at a place set to a value *)
fn with_byte {l:agz}{n:pos | n <= 1048576}{at:nat | at < n} (bytes: !$A.arr(byte, l, n), n: int n, at: int at, value: int): [copy_l:agz] $A.arr(byte, copy_l, n) = let
  val copy = copy_of(bytes, n)
  val () = $A.set<byte>(copy, at, $A.int2byte($AR.low_byte(value)))
in copy end

(* the record with bytes after its end chunk *)
fn with_trailing {l:agz}{n:pos | n <= 1048576 - 4} (bytes: !$A.arr(byte, l, n), n: int n): [copy_l:agz] $A.arr(byte, copy_l, n + 4) = let
  val copy = $A.alloc<byte>(n + 4)
  val _ = put_span(bytes, n, copy, n + 4, 0, n, 0)
  val () = $A.set<byte>(copy, n, $A.int2byte(1))
  val () = $A.set<byte>(copy, n + 1, $A.int2byte(2))
  val () = $A.set<byte>(copy, n + 2, $A.int2byte(3))
  val () = $A.set<byte>(copy, n + 3, $A.int2byte(4))
in copy end

(* the image a record reads as, with a loss or not, and its bytes as they are written *)
fn read_as_image {l:agz}{n:pos | n <= 1048576} (bytes: !$A.arr(byte, l, n), n: int n): tested = let
  val list = blist_of_array(bytes, 0, n)
  val (_ | read) = book_record_read(list)
in
  case+ read of
  | ~BR_ok(record) => let
      val image = book_record_image(record)
      val () = book_record_free(record)
    in Tested(image) end
  | ~BR_loss(record, lost) => let
      val image = book_record_image(record)
      val () = lostv_free(lost)
      val () = book_record_free(record)
    in Tested(image) end
  | ~BR_notquire() => NoTested()
  | ~BR_newer() => NoTested()
  | ~BR_damaged() => NoTested()
end

(* the cut record is used with a loss said, as the image of the record of its whole chunks and the end chunk, and written whole as that
   record is *)
fn check_cut_like {l:agz}{n:pos | n <= 1048576}{closed_l:agz}{closed_n:pos | closed_n <= 1048576}
  (cut: !$A.arr(byte, l, n), n: int n, closed: !$A.arr(byte, closed_l, closed_n), closed_n: int closed_n, what: string): void =
  case+ read_as_image(closed, closed_n) of
  | ~NoTested() => fail("the record of the chunks before the cut is a record")
  | ~Tested(kept) => let
      val @(kept_bytes, kept_n) = encode(kept)
      val @(code, written) = classify_same(cut, n, kept, kept_bytes, kept_n)
      val () = expect(code = 2, what)
      val () = expect(written, "a record cut in its framing is written whole")
      val () = $A.free<byte>(kept_bytes)
    in book_image_free(kept) end

fn check_cut_at {l:agz}{n:pos | n == 339}{length:nat | 7 <= length; length < n} (bytes: !$A.arr(byte, l, n), n: int n, length: int length): void = let
  val boundary = chunk_boundary(bytes, n, length, 7)
in
  if boundary <= 327 then let
    val closed = closed_at(bytes, n, boundary)
    val shortened = prefix_of(bytes, n, length)
    val () = check_cut_like(shortened, length, closed, boundary + 12, "a record cut short keeps the chunks before the cut and loses the groups after them")
    val () = $A.free<byte>(shortened)
  in $A.free<byte>(closed) end
  else fail("a cut inside the chunks")
end

fun check_cuts {l:agz}{n:pos | n == 339}{length:nat | length <= n} .<n - length>. (bytes: !$A.arr(byte, l, n), n: int n, length: int length): void =
  if length >= n then ()
  else if length < 7 then check_cuts(bytes, n, 7)
  else let
    val () = check_cut_at(bytes, n, length)
  in check_cuts(bytes, n, length + 1) end

fn check_cut (): void =
  case+ image_of(31337, 9, 7, 5) of
  | ~NoTested() => ()
  | ~Tested(image) => let
      val @(bytes, n) = encode(image)
      val () = book_image_free(image)
    in
      if n = 339 then let
        (* cut anywhere after the header (the end chunk missing or part of a chunk gone too): the chunks before the cut are kept *)
        val () = check_cuts(bytes, n, 0)
        (* a length past the end of the record: the chunk and what follows it are lost (TITL begins at 257) *)
        val past_end = with_byte(bytes, n, 258, 255)
        val closed = closed_at(bytes, n, 257)
        val () = check_cut_like(past_end, n, closed, 269, "a chunk whose length runs past the end of the record is a cut")
        val () = $A.free<byte>(past_end)
        (* a length over the limit of a chunk *)
        val over_limit = with_byte(bytes, n, 260, 127)
        val () = check_cut_like(over_limit, n, closed, 269, "a chunk whose length is over the limit is a cut")
        val () = $A.free<byte>(over_limit)
        val () = $A.free<byte>(closed)
        (* bytes after the end chunk: every group is read, the extra bytes are said *)
        val trailing = with_trailing(bytes, n)
        val () = check_cut_like(trailing, n + 4, bytes, n, "bytes after the end chunk are a cut")
        val () = $A.free<byte>(trailing)
      in $A.free<byte>(bytes) end
      else let val () = fail("a record of the shape these tests rely on") in $A.free<byte>(bytes) end
    end

(* ---------------- the checksum ---------------- *)

fn check_crc (): void = let
  val digits = $A.alloc<byte>(9)
  val () = $A.set<byte>(digits, 0, $A.int2byte(49))
  val () = $A.set<byte>(digits, 1, $A.int2byte(50))
  val () = $A.set<byte>(digits, 2, $A.int2byte(51))
  val () = $A.set<byte>(digits, 3, $A.int2byte(52))
  val () = $A.set<byte>(digits, 4, $A.int2byte(53))
  val () = $A.set<byte>(digits, 5, $A.int2byte(54))
  val () = $A.set<byte>(digits, 6, $A.int2byte(55))
  val () = $A.set<byte>(digits, 7, $A.int2byte(56))
  val () = $A.set<byte>(digits, 8, $A.int2byte(57))
  val list = blist_of_array(digits, 0, 9)
  val (_ | high, low) = crcfrom(65535, 65535, list)
  val () = blist_free(list)
  (* the CRC-32 of "123456789" is 0xCBF43926 *)
  val () = expect(65535 - high = 52212, "the CRC-32 of 123456789, high half")
  val () = expect(65535 - low = 14630, "the CRC-32 of 123456789, low half")
  (* and over an array whose cells are in its type (crc_of_cborrow, proved) *)
  val (cells_len | cells_array) = $A.barr_of_arr(digits)
  val @(cells_frozen, cells_borrowed) = $A.barr_freeze(cells_array)
  val (_, _ | @(proved_high, proved_low)) = crc_of_cborrow(cells_len | cells_borrowed, 9)
  val () = $A.cborrow_drop(cells_frozen, cells_borrowed)
  val () = $A.free<byte>($A.barr_to_arr($A.barr_thaw(cells_frozen)))
  val () = expect(proved_high = 52212, "the CRC-32 of 123456789 over an array of cells, high half")
in expect(proved_low = 14630, "the CRC-32 of 123456789 over an array of cells, low half") end

(* crc_of_cborrow, which is proved to be the fold crcfrom makes, is checked against it here too, as a check of the boundaries: arrays of every length from 1 to
   300, with every byte value among them, and one of 4000 bytes *)
fn check_crc_array_length (length: int): void =
  if length <= 0 then ()
  else let
    val count = g1ofg0(length)
  in
    if count <= 0 then ()
    else if count > 10000 then ()
    else let
      val data = $A.alloc<byte>(count)
      fun fill {l:agz}{n:pos}{i:nat | i <= n} .<n - i>. (data: !$A.arr(byte, l, n), n: int n, i: int i): void =
        if i >= n then ()
        else let
          val () = $A.set<byte>(data, i, $A.int2byte($AR.low_byte((i % 256) * 37 + (n % 256) * 11)))
        in fill(data, n, i + 1) end
      val () = fill(data, count, 0)
      val list = blist_of_array(data, 0, count)
      val (_ | list_high, list_low) = crcfrom(65535, 65535, list)
      val () = blist_free(list)
      val (cells_len | cells_array) = $A.barr_of_arr(data)
      val @(cells_frozen, cells_borrowed) = $A.barr_freeze(cells_array)
      val (_, _ | @(proved_high, proved_low)) = crc_of_cborrow(cells_len | cells_borrowed, count)
      val () = $A.cborrow_drop(cells_frozen, cells_borrowed)
      val () = $A.free<byte>($A.barr_to_arr($A.barr_thaw(cells_frozen)))
      val () = expect(proved_high = 65535 - list_high && proved_low = 65535 - list_low, "crc_of_cborrow is the fold of crcfrom")
    in () end
  end

fn check_crc_arrays (): void = let
  fun go {length:nat | length <= 301} .<301 - length>. (length: int length): void =
    if length > 300 then ()
    else let val () = check_crc_array_length(length) in go(length + 1) end
  val () = go(1)
in check_crc_array_length(4000) end

(* ---------------- the edge of 32 bits ---------------- *)

fn edge (i: int): Int =
  if i = 0 then ~2147483647 - 1
  else if i = 1 then ~2147483647
  else if i = 2 then ~268435457
  else if i = 3 then ~268435456
  else if i = 4 then ~1
  else if i = 5 then 0
  else if i = 6 then 1
  else if i = 7 then 255
  else if i = 8 then 256
  else if i = 9 then 65535
  else if i = 10 then 65536
  else if i = 11 then 16777215
  else if i = 12 then 16777216
  else if i = 13 then 268435455
  else if i = 14 then 268435456
  else if i = 15 then 536870911
  else if i = 16 then 536870912
  else if i = 17 then 1073741823
  else if i = 18 then 1073741824
  else 2147483647

fun check_edges {i:nat | i <= 20} .<20 - i>. (i: int i): void =
  if i >= 20 then ()
  else let
    val () = (case+ image_of(edge(i), 5, 4, 0) of
      | ~NoTested() => ()
      | ~Tested(image) => let
          val @(bytes, n) = encode(image)
          val @(code, written) = classify(bytes, n, image)
          val () = expect(code = 0, "an edge number is read back as it was written")
          val () = expect(written, "an edge number is written again as it was read")
          val () = $A.free<byte>(bytes)
        in book_image_free(image) end)
  in check_edges(i + 1) end

(* ---------------- strings of every length that matters ---------------- *)

fn check_strings (): void = let
  fun each_length {length:nat | length <= 256} .<256 - length>. (length: int length): void =
    if length >= 256 then ()
    else if length <> 0 && length <> 1 && length <> 2 && length <> 127 && length <> 128 && length <> 254 && length <> 255 then each_length(length + 1)
    else let
      val () = (case+ image_of(length + 1000, length, 255 - length, length) of
        | ~NoTested() => ()
        | ~Tested(image) => let
            val @(bytes, n) = encode(image)
            val @(code, written) = classify(bytes, n, image)
            val () = expect(code = 0, "strings of any length are read back as they were written")
            val () = expect(written, "strings of any length are written again as they were read")
            val () = $A.free<byte>(bytes)
          in book_image_free(image) end)
    in each_length(length + 1) end
in each_length(0) end

(* ---------------- damage ---------------- *)

(* every byte of a record changed to each of a few other values, and every
   shortened of it: nothing is read as another record *)
fn damage_with {image_contents:bookx} (image: book_image(image_contents)): void = let
  val @(bytes, n) = encode(image)
  fun flip {l:agz}{n:pos | n <= 1048576}{contents:bookx}{i:nat | i <= n} .<n - i>.
    (bytes: !$A.arr(byte, l, n), n: int n, original: !book_image(contents), i: int i): void =
    if i >= n then ()
    else let
      val copy = copy_of(bytes, n)
      val kept = $A.get<byte>(copy, i)
      fun values {copy_l:agz}{contents:bookx}{step:nat | step <= 3} .<3 - step>. (copy: !$A.arr(byte, copy_l, n), original: !book_image(contents), i: int i, kept: byte, step: int step): void =
        if step >= 3 then ()
        else let
          val change = (if step = 0 then 1 else if step = 1 then 128 else 255): [change:nat | change < 256] int change
          val flipped = $AR.band_g1($AR.add_g1($AR.low_byte(byte2int0(kept)), change), 255)
          val () = $A.set<byte>(copy, i, $A.int2byte(flipped))
          val @(code, written) = classify(copy, n, original)
          val () = expect(code <> 1, "damage to a byte gave another record")
          val () = expect(written, "a damaged record that was read is not written as it was read")
          val () = $A.set<byte>(copy, i, kept)
        in values(copy, original, i, kept, step + 1) end
      val () = values(copy, original, i, kept, 0)
      val () = $A.free<byte>(copy)
    in flip(bytes, n, original, i + 1) end
  val () = flip(bytes, n, image, 0)
  (* the bytes cut off anywhere *)
  fun cut {l:agz}{n:pos | n <= 1048576}{contents:bookx}{length:nat | length <= n} .<n - length>. (bytes: !$A.arr(byte, l, n), n: int n, original: !book_image(contents), length: int length): void =
    if length >= n then ()
    else if length <= 0 then cut(bytes, n, original, length + 1)
    else let
      val shortened = $A.alloc<byte>(length)
      fun copy_prefix {shortened_l:agz}{i:nat | i <= length} .<length - i>. (bytes: !$A.arr(byte, l, n), shortened: !$A.arr(byte, shortened_l, length), i: int i): void =
        if i >= length then ()
        else let val () = $A.set<byte>(shortened, i, $A.get<byte>(bytes, i)) in copy_prefix(bytes, shortened, i + 1) end
      val () = copy_prefix(bytes, shortened, 0)
      val @(code, _) = classify(shortened, length, original)
      (* cut inside its header it is not a record; cut after, it is used with a loss (#614) *)
      val () = (if length < 7 then expect(code >= 3, "a record cut inside its header is not a record") else expect(code = 2, "a record cut short is used with a loss"))
      val () = $A.free<byte>(shortened)
    in cut(bytes, n, original, length + 1) end
  val () = cut(bytes, n, image, 0)
  val () = $A.free<byte>(bytes)
  val () = book_image_free(image)
in () end

fn check_damage (): void =
  case+ image_of(31337, 9, 7, 5) of
  | ~NoTested() => ()
  | ~Tested(image) => damage_with(image)

(* ---------------- fuzz ---------------- *)

(* a record changed in a few places, many times; and bytes of no record *)
fn fuzz_with {image_contents,other_contents:bookx}{rounds:nat} (image: book_image(image_contents), other: book_image(other_contents), rounds: int rounds): void = let
  val @(bytes, n) = encode(image)
  fun round {l:agz}{n:pos | n <= 1048576}{contents:bookx}{left:nat} .<left>. (bytes: !$A.arr(byte, l, n), n: int n, original: !book_image(contents), left: int left): void =
    if left <= 0 then ()
    else let
      val copy = copy_of(bytes, n)
      val changes = $AR.add_g1(1, $AR.band_g1(next_number(), 3))
      fun change {copy_l:agz}{remaining:nat} .<remaining>. (copy: !$A.arr(byte, copy_l, n), remaining: int remaining): void =
        if remaining <= 0 then ()
        else let
          val raw = next_number()
          val at = (if $AR.lt_g1(raw, n) then raw else 0): [at:nat | at < n] int at
          val () = $A.set<byte>(copy, at, $A.int2byte($AR.band_g1(next_number(), 255)))
        in change(copy, remaining - 1) end
      val () = change(copy, changes)
      val @(code, written) = classify(copy, n, original)
      val () = expect(code <> 1, "fuzz: damage gave another record")
      val () = expect(written, "fuzz: a record that was read is not written as it was read")
      val () = $A.free<byte>(copy)
    in round(bytes, n, original, left - 1) end
  val () = round(bytes, n, image, rounds)
  val () = $A.free<byte>(bytes)
  val () = book_image_free(image)
  (* bytes of no record *)
  fn junk_read {len:pos | len <= 64}{contents:bookx} (original: !book_image(contents), length: int len): void = let
    val junk = $A.alloc<byte>(length)
    fun fill {junk_l:agz}{i:nat | i <= 64} .<64 - i>. (junk: !$A.arr(byte, junk_l, len), i: int i): void =
      if i >= length then ()
      else if i >= 64 then ()
      else let val () = $A.set<byte>(junk, i, $A.int2byte($AR.band_g1(next_number(), 255))) in fill(junk, i + 1) end
    val () = fill(junk, 0)
    val @(code, written) = classify(junk, length, original)
    val () = expect(code >= 2, "fuzz: noise was read as a whole record")
    val () = expect(written, "fuzz: noise that was read is not written as it was read")
    val () = $A.free<byte>(junk)
  in () end
  fun noise {remaining:nat}{contents:bookx} .<remaining>. (original: !book_image(contents), remaining: int remaining): void =
    if remaining <= 0 then ()
    else let
      val length = $AR.add_g1(1, $AR.band_g1(next_number(), 63)): [length:pos | length <= 64] int length
      val () = junk_read(original, length)
    in noise(original, remaining - 1) end
  val () = noise(other, rounds)
  val () = book_image_free(other)
in () end

fn check_fuzz {rounds:nat} (rounds: int rounds): void =
  case+ image_of(2718281, 12, 6, 3) of
  | ~NoTested() => ()
  | ~Tested(image) =>
    (case+ image_of(1, 1, 1, 0) of
     | ~NoTested() => book_image_free(image)
     | ~Tested(other) => fuzz_with(image, other, rounds))

(* ---------------- the words looked up (quire#565) ---------------- *)

fn word_numbers_with (value: Int): word_numbers = @{
  book_high = value, book_low = value, lookups = value, first_minute = value, last_minute = value, modified = value, deleted = value,
  chapter = value, node = value, offset = value, mastered = value, streak = value, due = value
}

datavtype word_tested =
  | {contents:wordx} WordTested of word_image(contents)
  | WordNoTested of ()

fn word_image_of {head_n,tail_n,word_n:nat | head_n < 256; tail_n < 256; word_n < 256} (value: Int, head_len: int head_n, tail_len: int tail_n, word_len: int word_n): word_tested =
  case+ word_image_make(word_numbers_with(value), text_of(2, 1), 2, text_of(head_len, 2), head_len, text_of(tail_len, 3), tail_len, text_of(word_len, 4), word_len) of
  | ~WordImaged(image) => WordTested(image)
  | ~WordNotImaged() => let val () = fail("an image of a word of numbers of 32 bits") in WordNoTested() end

fn word_encode {contents:wordx} (image: !word_image(contents)): [l:agz][n:pos | n <= 1048576] @($A.arr(byte, l, n), int n) = let
  val record = word_record_new(image)
  val (_ | list) = word_record_write(record)
  val () = word_record_free(record)
  val (_ | count) = blist_len(list)
in
  if count >= 1 then
    (if count <= 1048576 then let
       val bytes = blist_to_buffer(list, count)
       val () = blist_free(list)
     in @(bytes, count) end
     else let val () = blist_free(list) val one = $A.alloc<byte>(1) in @(one, 1) end)
  else let val () = blist_free(list) val one = $A.alloc<byte>(1) in @(one, 1) end
end

(* 0 whole and the same word, 1 whole but another word, 2 lost a group, 3 not a record, 4 newer, 5 damaged *)
fn word_classify {l:agz}{n:pos | n <= 1048576}{contents:wordx} (bytes: !$A.arr(byte, l, n), n: int n, original: !word_image(contents)): int = let
  val list = blist_of_array(bytes, 0, n)
  val (_ | read) = word_record_read(list)
in
  case+ read of
  | ~WR_ok(record) => let
      val back = word_record_image(record)
      val same = (word_image_diff(original, back) = 0)
      val () = word_image_free(back)
      val () = word_record_free(record)
    in if same then 0 else 1 end
  | ~WR_loss(record, lost) => let
      val () = lostv_free(lost)
      val () = word_record_free(record)
    in 2 end
  | ~WR_notquire() => 3
  | ~WR_newer() => 4
  | ~WR_damaged() => 5
end

(* every prefix of the record is a cut: never the word as it was, nor another one read whole *)
fun word_prefixes {l:agz}{n:pos | n <= 1048576}{contents:wordx}{length:nat | length <= n} .<n - length>.
  (bytes: !$A.arr(byte, l, n), n: int n, original: !word_image(contents), length: int length): void =
  if length >= n then ()
  else if length < 1 then word_prefixes(bytes, n, original, 1)
  else let
    val cut_bytes = prefix_of(bytes, n, length)
    val code = word_classify(cut_bytes, length, original)
    val () = expect(code >= 2, "a cut word record was read whole")
    val () = $A.free<byte>(cut_bytes)
  in word_prefixes(bytes, n, original, length + 1) end

(* every byte changed, one at a time: the word read is never another word *)
fun word_damage {l:agz}{n:pos | n <= 1048576}{contents:wordx}{at:nat | at <= n} .<n - at>.
  (bytes: !$A.arr(byte, l, n), n: int n, original: !word_image(contents), at: int at): void =
  if at >= n then ()
  else let
    val copy = with_byte(bytes, n, at, 1 + byte_at(bytes, n, at))
    val code = word_classify(copy, n, original)
    val () = expect(code <> 1, "damage to a word record gave another word")
    val () = $A.free<byte>(copy)
  in word_damage(bytes, n, original, at + 1) end

fn check_word_at (value: Int): void =
  case+ word_image_of(value, 200, 100, 9) of
  | ~WordNoTested() => ()
  | ~WordTested(image) => let
      val @(bytes, n) = word_encode(image)
      val whole = word_classify(bytes, n, image)
      val () = expect(whole = 0, "a word record is read back as the word written")
      val () = word_prefixes(bytes, n, image, 0)
      val () = word_damage(bytes, n, image, 0)
      val () = $A.free<byte>(bytes)
    in word_image_free(image) end

fn check_words (): void = let
  val () = check_word_at(0)
  val () = check_word_at(31337)
  val () = check_word_at(2147483647)
in check_word_at(~2147483647) end

implement main0 () = let
  val () = check_crc()
  val () = check_crc_arrays()
  val () = check_edges(0)
  val () = check_strings()
  val () = check_damage()
  val () = check_cut()
  val () = check_absent()
  val () = check_any_order()
  val () = check_needed_lost()
  val () = check_words()
  val () = check_fuzz(20000)
in
  if !_failures = 0 then println! ("all ok")
  else println! (!_failures, " failures")
end
