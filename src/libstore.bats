(* libstore -- the library in storage: one checksummed record for each book
   ("library/book/<id>", 14 hex digits), one for the collections
   ("library/index"). A book is read from its record, damage to one
   record costs that book and not the library, and a record is changed
   only by an update that reads it in the same transaction (#354) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P

staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload "bytes.sats"
staload "crc.sats"
staload "fields.sats"
staload "schema.sats"
staload "record.sats"
staload "bytesarr.sats"
staload "bookrec.sats"
staload "bookimage.sats"
staload "indexrec.sats"
staload "indeximage.sats"
staload "book.sats"
staload "mem.sats"

implement $P.dispose<$IDB.stored>(_) = ()

(* A record longer than this is not one of the library's *)
#define RECORD_MAX 65536

(* The books a library holds at most (library.bats's LIB_MAX) *)
#pub stadef STORED_MAX = 100000

(* ============================================================
   Keys
   ============================================================ *)

fn _hex_digit {value:nat | value < 16} (value: int value): [digit:nat | digit < 256] int digit =
  if value < 10 then 48 + value else 87 + value

(* The 7 hex digits of half (its low 28 bits) at buf[offset, offset + 7) *)
fn _put_seven_hex {l:agz}{owner:addr}{n:nat}{offset:nat | offset + 7 <= n}
  (buf: !$A.arrx(byte, l, n, owner), offset: int offset, half: int): void = let
  fn digit_at {i:nat | i < 7} (half: int, i: int i): [digit:nat | digit < 256] int digit =
    _hex_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(half, 4 * (6 - i))), 15))
  val () = $A.write_byte(buf, offset, digit_at(half, 0))
  val () = $A.write_byte(buf, offset + 1, digit_at(half, 1))
  val () = $A.write_byte(buf, offset + 2, digit_at(half, 2))
  val () = $A.write_byte(buf, offset + 3, digit_at(half, 3))
  val () = $A.write_byte(buf, offset + 4, digit_at(half, 4))
  val () = $A.write_byte(buf, offset + 5, digit_at(half, 5))
in $A.write_byte(buf, offset + 6, digit_at(half, 6)) end

(* The 4 hex digits of half (its low 16 bits) at buf[offset, offset + 4) *)
fn _put_four_hex {l:agz}{owner:addr}{n:nat}{offset:nat | offset + 4 <= n}
  (buf: !$A.arrx(byte, l, n, owner), offset: int offset, half: int): void = let
  fn digit_at {i:nat | i < 4} (half: int, i: int i): [digit:nat | digit < 256] int digit =
    _hex_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(half, 4 * (3 - i))), 15))
  val () = $A.write_byte(buf, offset, digit_at(half, 0))
  val () = $A.write_byte(buf, offset + 1, digit_at(half, 1))
  val () = $A.write_byte(buf, offset + 2, digit_at(half, 2))
in $A.write_byte(buf, offset + 3, digit_at(half, 3)) end

(* The key of a book's record: "library/book/" and its 14 hex digits *)
#pub fn libstore_book_key (id_high: int, id_low: int): [l:agz] $A.arr(byte, l, 27)

implement libstore_book_key (id_high, id_low) = let
  val key = $A.alloc<byte>(27)
  val () = $A.write_text(key, 0, $A.text_lit("library/book/"), 13)
  val () = _put_seven_hex(key, 13, id_high)
  val () = _put_seven_hex(key, 20, id_low)
in key end

(* The key of the collections' record *)
#pub fn libstore_index_key (): [l:agz] $A.arr(byte, l, 13)

implement libstore_index_key () = let
  val key = $A.alloc<byte>(13)
  val () = $A.write_text(key, 0, $A.text_lit("library/index"), 13)
in key end

(* The key a damaged record is kept under before it is repaired:
   "library/damaged/", the book's 14 hex digits, "/" and the checksum of
   the bytes it held (8 hex digits), so that the same damage is kept
   once *)
fn _damaged_key (id_high: int, id_low: int, sum_high: int, sum_low: int): [l:agz] $A.arr(byte, l, 39) = let
  val key = $A.alloc<byte>(39)
  val () = $A.write_text(key, 0, $A.text_lit("library/damaged/"), 16)
  val () = _put_seven_hex(key, 16, id_high)
  val () = _put_seven_hex(key, 23, id_low)
  val () = $A.write_byte(key, 30, 47)
  val () = _put_four_hex(key, 31, sum_high)
  val () = _put_four_hex(key, 35, sum_low)
in key end

(* ============================================================
   What the library holds, read
   ============================================================ *)

(* Why a record cannot be used. Its bytes are not touched. *)
#pub datatype unusable =
  | UnusableDamaged       (* it is not whole *)
  | UnusableNewer         (* a newer Quire wrote it, and this one cannot read it *)
  | UnusableNotQuire      (* it is not a record of Quire's *)

(* A book of the library as stored: its id and what it holds *)
#pub datavtype stored_book =
  | {x:bookx} WholeBook of (Int, Int, book_image(x))
  | {x:bookx} LossyBook of (Int, Int, book_image(x))    (* a group that may be lost was: the defaults stand in for it until the book is next saved *)
  | UnusableBook of (Int, Int, unusable)

#pub datavtype stored_books(int) =
  | StoredNone(0) of ()
  | {count:nat} StoredSome(count + 1) of (stored_book, stored_books(count))

(* The collections' record as stored *)
#pub datavtype stored_index =
  | IndexNone of ()                         (* none yet: the library is new, or it is not converted *)
  | {x:indexx} WholeIndex of (index_image(x))
  | {x:indexx} LossyIndex of (index_image(x))
  | UnusableIndex of (unusable)

(* What reading the library came to *)
#pub datavtype library_read =
  | ReadNothing of ()                       (* nothing is stored under "library/" *)
  | ReadFailed of ()                        (* it could not be read: nothing may be written over it *)
  | {count:nat} ReadLibrary of (stored_index, stored_books(count), int count)

#pub fun stored_book_free (book: stored_book): void

implement stored_book_free (book) =
  case+ book of
  | ~WholeBook(_, _, image) => book_image_free(image)
  | ~LossyBook(_, _, image) => book_image_free(image)
  | ~UnusableBook(_, _, _) => ()

#pub fun stored_books_free {count:nat} (books: stored_books(count)): void

implement stored_books_free {count} (books) = let
  fun go {count:nat} .<count>. (books: stored_books(count)): void =
    case+ books of
    | ~StoredNone() => ()
    | ~StoredSome(book, rest) => let val () = stored_book_free(book) in go(rest) end
in go(books) end

#pub fun stored_index_free (index: stored_index): void

implement stored_index_free (index) =
  case+ index of
  | ~IndexNone() => ()
  | ~WholeIndex(image) => index_image_free(image)
  | ~LossyIndex(image) => index_image_free(image)
  | ~UnusableIndex(_) => ()

#pub fun library_read_free (read: library_read): void

implement library_read_free (read) =
  case+ read of
  | ~ReadNothing() => ()
  | ~ReadFailed() => ()
  | ~ReadLibrary(index, books, _) => let
      val () = stored_index_free(index)
    in stored_books_free(books) end

implement $P.dispose<library_read>(read) = library_read_free(read)

(* A hex digit's value, or -1 *)
fn _hex_value {byte_value:nat | byte_value < 256} (byte_value: int byte_value): [value:int | ~1 <= value; value < 16] int value =
  if byte_value >= 48 then (if byte_value <= 57 then byte_value - 48
    else if byte_value >= 97 then (if byte_value <= 102 then byte_value - 87 else ~1) else ~1)
  else ~1

(* The 7 hex digits at buf[at, at + 7) as a number, or -1 when one is not a digit *)
fn _seven_hex_at {l:agz}{owner:addr}{n:nat}{at:nat | at + 7 <= n}
  (buf: !$A.arrx(byte, l, n, owner), at: int at): [v:int | ~1 <= v] int v = let
  fun go {i:nat | i <= 7}{total:nat} .<7 - i>. (buf: !$A.arrx(byte, l, n, owner), i: int i, total: int total): [v:int | ~1 <= v] int v =
    if i >= 7 then total
    else let
      val digit = _hex_value($AR.low_byte(byte2int0($A.get<byte>(buf, at + i))))
    in
      if digit < 0 then ~1 else go(buf, i + 1, total * 16 + digit)
    end
in go(buf, 0, 0) end

(* The little-endian u16 at buf[at, at + 2) *)
fn _u16_at {l:agz}{owner:addr}{n:nat}{at:nat | at + 2 <= n}
  (buf: !$A.arrx(byte, l, n, owner), at: int at): [v:nat | v < 65536] int v =
  $AR.low_byte(byte2int0($A.get<byte>(buf, at))) + 256 * $AR.low_byte(byte2int0($A.get<byte>(buf, at + 1)))

(* The little-endian u32 at buf[at, at + 4), or -1 when it is 2 to the 28 or more *)
fn _u32_at {l:agz}{owner:addr}{n:nat}{at:nat | at + 4 <= n}
  (buf: !$A.arrx(byte, l, n, owner), at: int at): [v:int | ~1 <= v; v < 268435456] int v = let
  val b0 = $AR.low_byte(byte2int0($A.get<byte>(buf, at)))
  val b1 = $AR.low_byte(byte2int0($A.get<byte>(buf, at + 1)))
  val b2 = $AR.low_byte(byte2int0($A.get<byte>(buf, at + 2)))
  val b3 = $AR.low_byte(byte2int0($A.get<byte>(buf, at + 3)))
in
  if b3 >= 16 then ~1 else b0 + 256 * (b1 + 256 * (b2 + 256 * b3))
end

(* Whether byte buf[at] is value *)
fn _byte_is {l:agz}{owner:addr}{n:nat}{at:nat | at < n}
  (buf: !$A.arrx(byte, l, n, owner), at: int at, value: int): bool =
  byte2int0($A.get<byte>(buf, at)) = value

(* What a key in storage is, by its bytes buf[at, at + len) *)
datavtype key_kind =
  | KeyBook of (Int, Int)      (* a book's record: its id *)
  | KeyIndex of ()             (* the collections' record *)
  | KeyOther of ()             (* anything else (a damaged record kept, ...) *)

fn _key_kind {l:agz}{owner:addr}{n:nat}{at,len:nat | at + len <= n}
  (buf: !$A.arrx(byte, l, n, owner), at: int at, len: int len): key_kind =
  (* "library/" *)
  if len < 13 then KeyOther()
  else if ~_byte_is(buf, at, 108) then KeyOther()
  else if ~_byte_is(buf, at + 1, 105) then KeyOther()
  else if ~_byte_is(buf, at + 2, 98) then KeyOther()
  else if ~_byte_is(buf, at + 3, 114) then KeyOther()
  else if ~_byte_is(buf, at + 4, 97) then KeyOther()
  else if ~_byte_is(buf, at + 5, 114) then KeyOther()
  else if ~_byte_is(buf, at + 6, 121) then KeyOther()
  else if ~_byte_is(buf, at + 7, 47) then KeyOther()
  (* "index" *)
  else if _byte_is(buf, at + 8, 105) then
    (if len = 13 then
       (if _byte_is(buf, at + 9, 110) then
          (if _byte_is(buf, at + 10, 100) then
             (if _byte_is(buf, at + 11, 101) then
                (if _byte_is(buf, at + 12, 120) then KeyIndex() else KeyOther())
              else KeyOther())
           else KeyOther())
        else KeyOther())
     else KeyOther())
  (* "book/" and 14 hex digits *)
  else if _byte_is(buf, at + 8, 98) then
    (if len = 27 then
       (if _byte_is(buf, at + 9, 111) then
          (if _byte_is(buf, at + 10, 111) then
             (if _byte_is(buf, at + 11, 107) then
                (if _byte_is(buf, at + 12, 47) then let
                   val id_high = _seven_hex_at(buf, at + 13)
                   val id_low = _seven_hex_at(buf, at + 20)
                 in
                   if id_high < 0 then KeyOther()
                   else if id_low < 0 then KeyOther()
                   else KeyBook(id_high, id_low)
                 end
                 else KeyOther())
              else KeyOther())
           else KeyOther())
        else KeyOther())
     else KeyOther())
  else KeyOther()


(* A book's record at piece[at, at + len) read *)
fn _read_book {l:agz}{owner:addr}{n:nat}{at,len:nat | at + len <= n}
  (piece: !$A.arrx(byte, l, n, owner), at: int at, len: int len, id_high: Int, id_low: Int): stored_book =
  if len <= 0 then UnusableBook(id_high, id_low, UnusableDamaged())
  else if len > RECORD_MAX then UnusableBook(id_high, id_low, UnusableDamaged())
  else let
    val list = blist_of_array(piece, at, len)
    val (_ | read) = book_record_read(list)
  in
    case+ read of
    | ~BR_ok(record) => let
        val image = book_record_image(record)
        val () = book_record_free(record)
        val numbers = book_image_numbers(image)
      in
        if numbers.id_high = id_high then
          (if numbers.id_low = id_low then WholeBook(id_high, id_low, image)
           else let val () = book_image_free(image) in UnusableBook(id_high, id_low, UnusableDamaged()) end)
        else let val () = book_image_free(image) in UnusableBook(id_high, id_low, UnusableDamaged()) end
      end
    | ~BR_loss(record, lost) => let
        val image = book_record_image(record)
        val () = book_record_free(record)
        val () = lostv_free(lost)
        val numbers = book_image_numbers(image)
      in
        if numbers.id_high = id_high then
          (if numbers.id_low = id_low then LossyBook(id_high, id_low, image)
           else let val () = book_image_free(image) in UnusableBook(id_high, id_low, UnusableDamaged()) end)
        else let val () = book_image_free(image) in UnusableBook(id_high, id_low, UnusableDamaged()) end
      end
    | ~BR_notquire() => UnusableBook(id_high, id_low, UnusableNotQuire())
    | ~BR_newer() => UnusableBook(id_high, id_low, UnusableNewer())
    | ~BR_damaged() => UnusableBook(id_high, id_low, UnusableDamaged())
  end

(* The collections' record at piece[at, at + len) read *)
fn _read_index {l:agz}{owner:addr}{n:nat}{at,len:nat | at + len <= n}
  (piece: !$A.arrx(byte, l, n, owner), at: int at, len: int len): stored_index =
  if len <= 0 then UnusableIndex(UnusableDamaged())
  else if len > RECORD_MAX then UnusableIndex(UnusableDamaged())
  else let
    val list = blist_of_array(piece, at, len)
    val (_ | read) = index_record_read(list)
  in
    case+ read of
    | ~IR_ok(record) => let
        val image = index_record_image(record)
        val () = index_record_free(record)
      in WholeIndex(image) end
    | ~IR_loss(record, lost) => let
        val image = index_record_image(record)
        val () = index_record_free(record)
        val () = lostv_free(lost)
      in LossyIndex(image) end
    | ~IR_notquire() => UnusableIndex(UnusableNotQuire())
    | ~IR_newer() => UnusableIndex(UnusableNewer())
    | ~IR_damaged() => UnusableIndex(UnusableDamaged())
  end

(* The entries of the blob get_prefix gave, from at on: the collections'
   record and the books', each key checked. The books are read onto
   books, count of them *)
fun _read_entries {l:agz}{owner:addr}{n:nat}{at:nat | at <= n}{count:nat | count <= STORED_MAX} .<n - at>.
  (piece: !$A.arrx(byte, l, n, owner), size: int n, at: int at, index: stored_index, books: stored_books(count), count: int count)
  : [total:nat | total <= STORED_MAX] @(stored_index, stored_books(total), int total) =
  if at + 2 > size then @(index, books, count)
  else let
    val key_len = _u16_at(piece, at)
    val key_at = at + 2
  in
    if key_at + key_len + 4 > size then @(index, books, count)
    else let
      val value_len = _u32_at(piece, key_at + key_len)
      val value_at = key_at + key_len + 4
    in
      if value_len < 0 then @(index, books, count)
      else if value_at + value_len > size then @(index, books, count)
      else let
        val next = value_at + value_len
        val kind = _key_kind(piece, key_at, key_len)
      in
        case+ kind of
        | ~KeyBook(id_high, id_low) =>
          if count >= 100000 then @(index, books, count)
          else let
            val book = _read_book(piece, value_at, value_len, id_high, id_low)
          in _read_entries(piece, size, next, index, StoredSome(book, books), count + 1) end
        | ~KeyIndex() => let
            val read = _read_index(piece, value_at, value_len)
            val () = stored_index_free(index)
          in _read_entries(piece, size, next, read, books, count) end
        | ~KeyOther() => _read_entries(piece, size, next, index, books, count)
      end
    end
  end


(* The library, read: every record under "library/" in one view *)
#pub fun libstore_read (): $P.promise(library_read, $P.Chained)

implement libstore_read () = let
  val key_prefix = $A.alloc<byte>(8)
  val () = $A.write_text(key_prefix, 0, $A.text_lit("library/"), 8)
  val @(key_prefix_frozen, key_prefix_bytes) = $A.freeze<byte>(key_prefix)
  val stored = $IDB.idb_get_prefix(key_prefix_bytes, 8)
  val () = release_bytes(key_prefix_frozen, key_prefix_bytes)
in
  $P.and_then<$IDB.lookup><library_read>(stored, llam(found) =>
    case+ lookup_content(found) of
    | ~NoStoredContent() => $P.ret<library_read>(ReadNothing())
    | ~ContentUnreadable() => $P.ret<library_read>(ReadFailed())
    | ~StoredContent(owner, piece, size) => let
        val @(index, books, count) = _read_entries(piece, size, 0, IndexNone(), StoredNone(), 0)
        val () = piece_free(owner, piece)
      in $P.ret<library_read>(ReadLibrary(index, books, count)) end)
end

(* ============================================================
   Saving a book: an update that reads the record first
   ============================================================ *)

(* What saving a book came to *)
#pub datavtype book_saved =
  | BookSaved of ()                   (* the record is stored with the groups put in *)
  | BookRefused of (unusable)         (* the stored record is not one this Quire can change: nothing was written *)
  | BookNotSaved of ()                (* it could not be read or written: nothing was kept *)

#pub fun book_saved_free (saved: book_saved): void

implement book_saved_free (saved) =
  case+ saved of
  | ~BookSaved() => ()
  | ~BookRefused(_) => ()
  | ~BookNotSaved() => ()

implement $P.dispose<book_saved>(saved) = book_saved_free(saved)

(* u16 little-endian *)
fn _put_u16 {l:agz}{owner:addr}{n:nat}{at:nat | at + 2 <= n}
  (out: !$A.arrx(byte, l, n, owner), at: int at, value: int): void = let
  val () = $A.write_byte(out, at, $AR.low_byte(value))
in $A.write_byte(out, at + 1, $AR.low_byte($AR.bsr_int_int(value, 8))) end

(* u32 little-endian *)
fn _put_u32 {l:agz}{owner:addr}{n:nat}{at:nat | at + 4 <= n}
  (out: !$A.arrx(byte, l, n, owner), at: int at, value: int): void = let
  val () = _put_u16(out, at, value)
in _put_u16(out, at + 2, $AR.bsr_int_int(value, 16)) end

(* The bytes of src[0, count) at out[at, at + count) *)
fn _put_bytes {sl,ol:agz}{oo:addr}{sn,on:nat}{count,at:nat | count <= sn; at + count <= on}
  (out: !$A.arrx(byte, ol, on, oo), at: int at, src: !$A.arr(byte, sl, sn), count: int count): void = let
  fun go {i:nat | i <= count} .<count - i>. (out: !$A.arrx(byte, ol, on, oo), src: !$A.arr(byte, sl, sn), i: int i): void =
    if i >= count then ()
    else let
      val () = $A.set<byte>(out, at + i, $A.get<byte>(src, i))
    in go(out, src, i + 1) end
in go(out, src, 0) end

(* One put of a batch: op 1, the key, the value *)
fn _put_operation {ol,kl,vl:agz}{oo:addr}{on,kn,vn:nat}{at:nat | at + 7 + kn + vn <= on}
  (out: !$A.arrx(byte, ol, on, oo), at: int at, key: !$A.arr(byte, kl, kn), key_len: int kn, value: !$A.arr(byte, vl, vn), value_len: int vn): void = let
  val () = $A.write_byte(out, at, 1)
  val () = _put_u16(out, at + 1, key_len)
  val () = _put_bytes(out, at + 3, key, key_len)
  val () = _put_u32(out, at + 3 + key_len, value_len)
in _put_bytes(out, at + 7 + key_len, value, value_len) end

(* A book image as a record's bytes, in an array (with its length), with the
   proof that they are its record: none when the record would not fit *)
datavtype record_bytes =
  | {l:agz}{n:pos | n <= 65536} RecordBytes of ($A.arr(byte, l, n), int n)
  | NoRecordBytes of ()

fn _bytes_of_record {x:bookx}{ver,minver:int}{e:extras} (record: !bookrecord(x, ver, minver, e)): record_bytes = let
  val (_ | list) = book_record_write(record)
  val (_ | count) = blist_len(list)
in
  if count <= 0 then let val () = blist_free(list) in NoRecordBytes() end
  else if count > 65536 then let val () = blist_free(list) in NoRecordBytes() end
  else let
    val bytes = blist_to_buffer(list, count)
    val () = blist_free(list)
  in RecordBytes(bytes, count) end
end

(* The CRC-32 of array[0, count), as its high and low halves *)
fn _crc_of {l:agz}{n,count:nat | count <= n} (array: !$A.arr(byte, l, n), count: int count): @(int, int) = let
  val list = blist_of_array(array, 0, count)
  val (_ | high, low) = crcfrom(65535, 65535, list)
  val () = blist_free(list)
in @(65535 - high, 65535 - low) end

(* What an update of a book's record decides, from what it read.
   Closed over the image to put in, the groups of it to take, and the
   resolver of the answer *)
fn _decide_book {x:bookx} (found: $IDB.lookup, id_high: Int, id_low: Int, mask: int, image: book_image(x), answer: $P.resolver(book_saved)): $IDB.writeback =
  case+ found of
  | ~$IDB.Unreadable(cause) => let
      val () = $IDB.unreadable_cause_free(cause)
      val () = book_image_free(image)
      val () = $P.resolve<book_saved>(answer, BookNotSaved())
    in $IDB.Keep() end
  | ~$IDB.Absent() => let
      val record = book_record_new(image)
      val () = book_image_free(image)
    in
      case+ _bytes_of_record(record) of
      | ~RecordBytes(bytes, count) => let
          val () = book_record_free(record)
          val () = $P.resolve<book_saved>(answer, BookSaved())
        in $IDB.Write(bytes, count) end
      | ~NoRecordBytes() => let
          val () = book_record_free(record)
          val () = $P.resolve<book_saved>(answer, BookNotSaved())
        in $IDB.Keep() end
    end
  | ~$IDB.Found(blob) => let
      val size = $BD.blob_len(blob)
    in
      if size <= 0 then let
        val () = $BD.blob_free(blob)
        val () = book_image_free(image)
        val () = $P.resolve<book_saved>(answer, BookRefused(UnusableDamaged()))
      in $IDB.Keep() end
      else if size > 65536 then let
        val () = $BD.blob_free(blob)
        val () = book_image_free(image)
        val () = $P.resolve<book_saved>(answer, BookRefused(UnusableDamaged()))
      in $IDB.Keep() end
      else let
        val old = $A.alloc<byte>(size)
        val () = $BD.blob_read(blob, 0, old, size)
        val () = $BD.blob_free(blob)
        val list = blist_of_array(old, 0, size)
        val (_ | read) = book_record_read(list)
      in
        case+ read of
        | ~BR_ok(record) => let
            val patched = book_record_patch(record, image, mask)
            val () = book_image_free(image)
            val () = $A.free<byte>(old)
          in
            case+ _bytes_of_record(patched) of
            | ~RecordBytes(bytes, count) => let
                val () = book_record_free(patched)
                val () = $P.resolve<book_saved>(answer, BookSaved())
              in $IDB.Write(bytes, count) end
            | ~NoRecordBytes() => let
                val () = book_record_free(patched)
                val () = $P.resolve<book_saved>(answer, BookNotSaved())
              in $IDB.Keep() end
          end
        | ~BR_loss(record, lost) => let
            (* a group was lost: the old bytes are kept under another key,
               in the same transaction as the repaired record *)
            val () = lostv_free(lost)
            val patched = book_record_patch(record, image, mask)
            val () = book_image_free(image)
          in
            case+ _bytes_of_record(patched) of
            | ~RecordBytes(bytes, count) => let
                val () = book_record_free(patched)
                val @(sum_high, sum_low) = _crc_of(old, size)
                val damaged_key = _damaged_key(id_high, id_low, sum_high, sum_low)
                val key = libstore_book_key(id_high, id_low)
                val batch_size = 7 + 39 + size + 7 + 27 + count
                val batch = $A.alloc<byte>(batch_size)
                val () = _put_operation(batch, 0, damaged_key, 39, old, size)
                val () = _put_operation(batch, 7 + 39 + size, key, 27, bytes, count)
                val () = $A.free<byte>(damaged_key)
                val () = $A.free<byte>(key)
                val () = $A.free<byte>(old)
                val () = $A.free<byte>(bytes)
                val () = $P.resolve<book_saved>(answer, BookSaved())
              in $IDB.WriteBatch(batch, batch_size) end
            | ~NoRecordBytes() => let
                val () = book_record_free(patched)
                val () = $A.free<byte>(old)
                val () = $P.resolve<book_saved>(answer, BookNotSaved())
              in $IDB.Keep() end
          end
        | ~BR_notquire() => let
            val () = book_image_free(image)
            val () = $A.free<byte>(old)
            val () = $P.resolve<book_saved>(answer, BookRefused(UnusableNotQuire()))
          in $IDB.Keep() end
        | ~BR_newer() => let
            val () = book_image_free(image)
            val () = $A.free<byte>(old)
            val () = $P.resolve<book_saved>(answer, BookRefused(UnusableNewer()))
          in $IDB.Keep() end
        | ~BR_damaged() => let
            val () = book_image_free(image)
            val () = $A.free<byte>(old)
            val () = $P.resolve<book_saved>(answer, BookRefused(UnusableDamaged()))
          in $IDB.Keep() end
      end
    end

(* An answer whose update did not commit is not the answer *)
fn _unsaved (answer: $P.promise(book_saved, $P.Pending)): $P.promise(book_saved, $P.Chained) =
  $P.and_then<book_saved><book_saved>(answer, llam(saved) => let
    val () = book_saved_free(saved)
  in $P.ret<book_saved>(BookNotSaved()) end)

(* The groups of image in mask (see book_group_all) saved into the book's record:
   the record is read in the same transaction, the groups put into it and the
   rest left as it is, with the chunks a newer Quire added. A book with no
   record is made. A record that cannot be read, or is not one Quire can
   change, is not written over *)
#pub fun libstore_save_book {x:bookx} (id_high: Int, id_low: Int, mask: int, image: !book_image(x)): $P.promise(book_saved, $P.Chained)

implement libstore_save_book {x} (id_high, id_low, mask, image) = let
  val key = libstore_book_key(id_high, id_low)
  val copy = book_image_copy(image)
  val @(answer, resolver) = $P.create<book_saved>()
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val updating = $IDB.idb_update(key_bytes, 27, llam(found) => _decide_book(found, id_high, id_low, mask, copy, resolver))
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.updated><book_saved>(updating, llam(updated) =>
    case+ updated of
    | ~$IDB.Updated() => $P.vow(answer)
    | ~$IDB.KeptAsRead() => $P.vow(answer)
    | ~$IDB.UpdateUnreadable(cause) => let val () = $IDB.unreadable_cause_free(cause) in _unsaved(answer) end
    | ~$IDB.NotUpdated(cause) => let val () = $IDB.write_failure_free(cause) in _unsaved(answer) end)
end


(* ============================================================
   Deleting a book, saving the collections
   ============================================================ *)

(* What deleting a book's record came to *)
#pub datatype book_deleted =
  | BookDeleted        (* its record is gone, or there was none *)
  | BookNotDeleted     (* it could not be read or deleted: nothing was kept *)

implement $P.dispose<book_deleted>(_) = ()

fn _decide_delete (found: $IDB.lookup, id_high: Int, id_low: Int): $IDB.writeback =
  case+ found of
  | ~$IDB.Unreadable(cause) => let val () = $IDB.unreadable_cause_free(cause) in $IDB.Keep() end
  | ~$IDB.Absent() => $IDB.Keep()
  | ~$IDB.Found(blob) => let
      val () = $BD.blob_free(blob)
      val key = libstore_book_key(id_high, id_low)
      val batch = $A.alloc<byte>(30)
      val () = $A.write_byte(batch, 0, 2)
      val () = _put_u16(batch, 1, 27)
      val () = _put_bytes(batch, 3, key, 27)
      val () = $A.free<byte>(key)
    in $IDB.WriteBatch(batch, 30) end

(* A book's record deleted, after it is read in the same transaction *)
#pub fun libstore_delete_book (id_high: Int, id_low: Int): $P.promise(book_deleted, $P.Chained)

implement libstore_delete_book (id_high, id_low) = let
  val key = libstore_book_key(id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val updating = $IDB.idb_update(key_bytes, 27, llam(found) => _decide_delete(found, id_high, id_low))
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.updated><book_deleted>(updating, llam(updated) =>
    case+ updated of
    | ~$IDB.Updated() => $P.ret<book_deleted>(BookDeleted())
    | ~$IDB.KeptAsRead() => $P.ret<book_deleted>(BookDeleted())
    | ~$IDB.UpdateUnreadable(cause) => let val () = $IDB.unreadable_cause_free(cause) in $P.ret<book_deleted>(BookNotDeleted()) end
    | ~$IDB.NotUpdated(cause) => let val () = $IDB.write_failure_free(cause) in $P.ret<book_deleted>(BookNotDeleted()) end)
end

(* What saving the collections came to *)
#pub datavtype index_saved =
  | IndexSaved of ()
  | IndexRefused of (unusable)
  | IndexNotSaved of ()

#pub fun index_saved_free (saved: index_saved): void

implement index_saved_free (saved) =
  case+ saved of
  | ~IndexSaved() => ()
  | ~IndexRefused(_) => ()
  | ~IndexNotSaved() => ()

implement $P.dispose<index_saved>(saved) = index_saved_free(saved)

fn _index_bytes_of {x:indexx}{ver,minver:int}{e:extras} (record: !indexrecord(x, ver, minver, e)): record_bytes = let
  val (_ | list) = index_record_write(record)
  val (_ | count) = blist_len(list)
in
  if count <= 0 then let val () = blist_free(list) in NoRecordBytes() end
  else if count > 65536 then let val () = blist_free(list) in NoRecordBytes() end
  else let
    val bytes = blist_to_buffer(list, count)
    val () = blist_free(list)
  in RecordBytes(bytes, count) end
end

fn _decide_index {x:indexx} (found: $IDB.lookup, mask: int, image: index_image(x), answer: $P.resolver(index_saved)): $IDB.writeback =
  case+ found of
  | ~$IDB.Unreadable(cause) => let
      val () = $IDB.unreadable_cause_free(cause)
      val () = index_image_free(image)
      val () = $P.resolve<index_saved>(answer, IndexNotSaved())
    in $IDB.Keep() end
  | ~$IDB.Absent() => let
      val record = index_record_new(image)
      val () = index_image_free(image)
    in
      case+ _index_bytes_of(record) of
      | ~RecordBytes(bytes, count) => let
          val () = index_record_free(record)
          val () = $P.resolve<index_saved>(answer, IndexSaved())
        in $IDB.Write(bytes, count) end
      | ~NoRecordBytes() => let
          val () = index_record_free(record)
          val () = $P.resolve<index_saved>(answer, IndexNotSaved())
        in $IDB.Keep() end
    end
  | ~$IDB.Found(blob) => let
      val size = $BD.blob_len(blob)
    in
      if size <= 0 then let
        val () = $BD.blob_free(blob)
        val () = index_image_free(image)
        val () = $P.resolve<index_saved>(answer, IndexRefused(UnusableDamaged()))
      in $IDB.Keep() end
      else if size > 65536 then let
        val () = $BD.blob_free(blob)
        val () = index_image_free(image)
        val () = $P.resolve<index_saved>(answer, IndexRefused(UnusableDamaged()))
      in $IDB.Keep() end
      else let
        val old = $A.alloc<byte>(size)
        val () = $BD.blob_read(blob, 0, old, size)
        val () = $BD.blob_free(blob)
        val list = blist_of_array(old, 0, size)
        val (_ | read) = index_record_read(list)
      in
        case+ read of
        | ~IR_ok(record) => let
            val patched = index_record_patch(record, image, mask)
            val () = index_image_free(image)
            val () = $A.free<byte>(old)
          in
            case+ _index_bytes_of(patched) of
            | ~RecordBytes(bytes, count) => let
                val () = index_record_free(patched)
                val () = $P.resolve<index_saved>(answer, IndexSaved())
              in $IDB.Write(bytes, count) end
            | ~NoRecordBytes() => let
                val () = index_record_free(patched)
                val () = $P.resolve<index_saved>(answer, IndexNotSaved())
              in $IDB.Keep() end
          end
        | ~IR_loss(record, lost) => let
            val () = lostv_free(lost)
            val patched = index_record_patch(record, image, mask)
            val () = index_image_free(image)
          in
            case+ _index_bytes_of(patched) of
            | ~RecordBytes(bytes, count) => let
                val () = index_record_free(patched)
                val @(sum_high, sum_low) = _crc_of(old, size)
                val damaged_key = _damaged_key(0, 0, sum_high, sum_low)
                val key = libstore_index_key()
                val batch_size = 7 + 39 + size + 7 + 13 + count
                val batch = $A.alloc<byte>(batch_size)
                val () = _put_operation(batch, 0, damaged_key, 39, old, size)
                val () = _put_operation(batch, 7 + 39 + size, key, 13, bytes, count)
                val () = $A.free<byte>(damaged_key)
                val () = $A.free<byte>(key)
                val () = $A.free<byte>(old)
                val () = $A.free<byte>(bytes)
                val () = $P.resolve<index_saved>(answer, IndexSaved())
              in $IDB.WriteBatch(batch, batch_size) end
            | ~NoRecordBytes() => let
                val () = index_record_free(patched)
                val () = $A.free<byte>(old)
                val () = $P.resolve<index_saved>(answer, IndexNotSaved())
              in $IDB.Keep() end
          end
        | ~IR_notquire() => let
            val () = index_image_free(image)
            val () = $A.free<byte>(old)
            val () = $P.resolve<index_saved>(answer, IndexRefused(UnusableNotQuire()))
          in $IDB.Keep() end
        | ~IR_newer() => let
            val () = index_image_free(image)
            val () = $A.free<byte>(old)
            val () = $P.resolve<index_saved>(answer, IndexRefused(UnusableNewer()))
          in $IDB.Keep() end
        | ~IR_damaged() => let
            val () = index_image_free(image)
            val () = $A.free<byte>(old)
            val () = $P.resolve<index_saved>(answer, IndexRefused(UnusableDamaged()))
          in $IDB.Keep() end
      end
    end

fn _index_unsaved (answer: $P.promise(index_saved, $P.Pending)): $P.promise(index_saved, $P.Chained) =
  $P.and_then<index_saved><index_saved>(answer, llam(saved) => let
    val () = index_saved_free(saved)
  in $P.ret<index_saved>(IndexNotSaved()) end)

(* The groups of image in mask (see index_group_all) saved into the collections'
   record, as a book's are *)
#pub fun libstore_save_index {x:indexx} (mask: int, image: !index_image(x)): $P.promise(index_saved, $P.Chained)

implement libstore_save_index {x} (mask, image) = let
  val key = libstore_index_key()
  val copy = index_image_copy(image)
  val @(answer, resolver) = $P.create<index_saved>()
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val updating = $IDB.idb_update(key_bytes, 13, llam(found) => _decide_index(found, mask, copy, resolver))
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.updated><index_saved>(updating, llam(updated) =>
    case+ updated of
    | ~$IDB.Updated() => $P.vow(answer)
    | ~$IDB.KeptAsRead() => $P.vow(answer)
    | ~$IDB.UpdateUnreadable(cause) => let val () = $IDB.unreadable_cause_free(cause) in _index_unsaved(answer) end
    | ~$IDB.NotUpdated(cause) => let val () = $IDB.write_failure_free(cause) in _index_unsaved(answer) end)
end


(* ============================================================
   Writing the whole library at once (the conversion)
   ============================================================ *)

(* The puts of a batch, to be written all or none *)
#pub datavtype batch(int) =
  | BatchNone(0) of ()
  | {kl,vl:agz}{kn:pos | kn < 65536}{vn:pos | vn <= 65536}{count:nat}
    BatchSome(count + 1) of ($A.arr(byte, kl, kn), int kn, $A.arr(byte, vl, vn), int vn, batch(count))

(* A put of the book's record added to a batch; the batch as it was when the
   record would not fit *)
#pub fun batch_add_book {count:nat}{x:bookx} (batch: batch(count), id_high: Int, id_low: Int, image: !book_image(x))
  : [more:nat] batch(more)

implement batch_add_book {count}{x} (batch, id_high, id_low, image) = let
  val record = book_record_new(image)
in
  case+ _bytes_of_record(record) of
  | ~RecordBytes(bytes, size) => let
      val () = book_record_free(record)
      val key = libstore_book_key(id_high, id_low)
    in BatchSome(key, 27, bytes, size, batch) end
  | ~NoRecordBytes() => let val () = book_record_free(record) in batch end
end

(* The same for the collections' record *)
#pub fun batch_add_index {count:nat}{x:indexx} (batch: batch(count), image: !index_image(x)): [more:nat] batch(more)

implement batch_add_index {count}{x} (batch, image) = let
  val record = index_record_new(image)
in
  case+ _index_bytes_of(record) of
  | ~RecordBytes(bytes, size) => let
      val () = index_record_free(record)
      val key = libstore_index_key()
    in BatchSome(key, 13, bytes, size, batch) end
  | ~NoRecordBytes() => let val () = index_record_free(record) in batch end
end

(* The bytes of a batch's operations *)
fun _batch_size {count:nat} .<count>. (batch: !batch(count)): [size:nat] int size =
  case+ batch of
  | BatchNone() => 0
  | BatchSome(_, key_size, _, value_size, rest) => 7 + key_size + value_size + _batch_size(rest)

fun _batch_fill {l:agz}{owner:addr}{n:nat}{count:nat}{at:nat | at <= n} .<count>.
  (out: !$A.arrx(byte, l, n, owner), size: int n, at: int at, batch: !batch(count)): void =
  case+ batch of
  | BatchNone() => ()
  | BatchSome(key, key_size, value, value_size, rest) =>
    if at + 7 + key_size + value_size > size then ()
    else let
      val () = _put_operation(out, at, key, key_size, value, value_size)
    in _batch_fill(out, size, at + 7 + key_size + value_size, rest) end

#pub fun batch_free {count:nat} (batch: batch(count)): void

implement batch_free {count} (batch) = let
  fun go {count:nat} .<count>. (batch: batch(count)): void =
    case+ batch of
    | ~BatchNone() => ()
    | ~BatchSome(key, _, value, _, rest) => let
        val () = $A.free<byte>(key)
        val () = $A.free<byte>(value)
      in go(rest) end
in go(batch) end

(* A batch written in one transaction: all of it or none *)
#pub fun batch_commit {count:nat} (batch: batch(count)): $P.promise($IDB.stored, $P.Chained)

implement batch_commit {count} (batch) = let
  val size = _batch_size(batch)
in
  if size <= 0 then let val () = batch_free(batch) in $P.ret<$IDB.stored>($IDB.Stored()) end
  else if size > 268435456 then let val () = batch_free(batch) in $P.ret<$IDB.stored>($IDB.NotStored()) end
  else (case+ piece_new(size) of
    | ~NoPiece() => let val () = batch_free(batch) in $P.ret<$IDB.stored>($IDB.NotStored()) end
    | ~Piece(owner, out) => let
        val () = _batch_fill(out, size, 0, batch)
        val () = batch_free(batch)
        val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
        val stored = $IDB.idb_write_all(out_bytes, size)
        val () = $A.drop<byte>(out_frozen, out_bytes)
        val () = piece_free(owner, $A.thaw<byte>(out_frozen))
      in stored end)
end

end
