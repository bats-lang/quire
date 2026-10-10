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

fn numbers_of (value: Int): book_numbers = @{
  id_high = value, id_low = value, collections = value, collections_modified = value, minutes_elsewhere = value,
  pages_elsewhere = value, finished_at = value, finished_modified = value, chapter = value, chapters = value,
  page = value, pages = value, anchor = value, place_modified = value, place_declined = value, position = value,
  series_number = value, shelf = value, added = value, opened = value, shelf_modified = value, file_size = value,
  cover = value, done = value, minutes_read = value, pages_read = value, progress_weighted = value
}

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
  val () = $A.free<byte>(digits)
  (* the CRC-32 of "123456789" is 0xCBF43926 *)
  val () = expect(65535 - high = 52212, "the CRC-32 of 123456789, high half")
in expect(65535 - low = 14630, "the CRC-32 of 123456789, low half") end

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
      val () = expect(code >= 3, "a record cut short is not a record")
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

implement main0 () = let
  val () = check_crc()
  val () = check_edges(0)
  val () = check_strings()
  val () = check_damage()
  val () = check_fuzz(20000)
in
  if !_failures = 0 then println! ("all ok")
  else println! (!_failures, " failures")
end
