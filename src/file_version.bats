(* file_version -- which file a book's id stands for, so a tab that has
   a book open learns that another tab replaced it (quire#425).

   A book's id is the SHA-256 of the file it was imported from, and
   Replace keeps the id when a corrected file takes the old one's place
   (src/import.bats). The file stored under the book's key 'b' then has
   another id than the book: its own, kept under the key 'v' as two
   numbers (a record only while they differ, so a book never replaced
   by a corrected file has none). A tab remembers the file it opened
   (file_version_remember) and asks again when the page is shown again
   (file_version_changed): a different file is a book to leave, not one
   to go on reading from the file it opened.

   Why a question at the page's return and no message between the
   tabs: bridge offers no channel between tabs, a hidden tab is not
   running anything for the reader to see, and what a reader's app does
   when it is shown again (sync, a reload of the library) is the same
   moment. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P

staload "book.sats"
staload "mem.sats"
staload "library.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"

(* The book the tab opened and the file it opened (the halves of the
   file's id) *)
val _book_high = ref<Int>(0)
val _book_low = ref<Int>(0)
val _file_high = ref<Int>(0)
val _file_low = ref<Int>(0)
(* Whether a book is remembered: a book opened while this is false has its read
   still to come *)
val _remembered = ref<bool>(false)

(* The number at record[at, at + 4), little endian, as write_i32 wrote it *)
fn _int32_at {l:agz}{n:nat}{at:nat | at + 4 <= n} (record: !$A.arr(byte, l, n), at: int at): Int = let
  val byte0 = $AR.low_byte(byte2int0($A.get<byte>(record, at)))
  val byte1 = $AR.low_byte(byte2int0($A.get<byte>(record, at + 1)))
  val byte2 = $AR.low_byte(byte2int0($A.get<byte>(record, at + 2)))
  val byte3 = $AR.low_byte(byte2int0($A.get<byte>(record, at + 3)))
  val high = (if byte3 < 128 then byte3 else byte3 - 256): [signed:int | ~128 <= signed; signed < 128] int signed
in byte0 + byte1 * 256 + byte2 * 65536 + high * 16777216 end

(* The file the stored version names, as two halves: the book's own when
   none is kept *)
fn _file_of (found: $IDB.lookup, book_high: Int, book_low: Int): @(Int, Int) =
  case+ lookup_bytes(found) of
  | ~NothingStored() => @(book_high, book_low)
  (* a read that failed says nothing of the file: the tab goes on *)
  | ~StoredUnreadable() => @(book_high, book_low)
  | ~StoredBytes(record, size) =>
    if size < 8 then let val () = $A.free<byte>(record) in @(book_high, book_low) end
    else let
      val high = _int32_at(record, 0)
      val low = _int32_at(record, 4)
      val () = $A.free<byte>(record)
    in @(high, low) end

fn _key_of (id_high: Int, id_low: Int): [l:agz] $A.arr(byte, l, 15) = lib_key(118, id_high, id_low)

(* The book (id_high, id_low) is open: remembers the file it was opened from *)
#pub fn file_version_remember (id_high: Int, id_low: Int): void

implement file_version_remember (id_high, id_low) = let
  val () = !_book_high := id_high
  val () = !_book_low := id_low
  val () = !_file_high := id_high
  val () = !_file_low := id_low
  val () = !_remembered := true
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_key_of(id_high, id_low))
  val stored = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.finish<$IDB.lookup>(stored, llam(found) => let
    val @(file_high, file_low) = _file_of(found, id_high, id_low)
  in
    (* only while the same book is the one remembered *)
    if !_book_high = id_high then (if !_book_low = id_low then let
        val () = !_file_high := file_high
      in !_file_low := file_low end else ())
    else ()
  end)
end

(* No book is open *)
#pub fn file_version_forget (): void

implement file_version_forget () = !_remembered := false

(* Whether the file stored for the book remembered is another than the
   one it was opened from: the promise resolves with 1 when it is, else 0 *)
#pub fn file_version_changed (): $P.promise(int, $P.Chained)

implement file_version_changed () =
  if ~(!_remembered) then $P.ret<int>(0)
  else let
    val id_high = !_book_high
    val id_low = !_book_low
    val opened_high = !_file_high
    val opened_low = !_file_low
    val @(key_frozen, key_bytes) = $A.freeze<byte>(_key_of(id_high, id_low))
    val stored = $IDB.idb_get(key_bytes, 15)
    val () = release_bytes(key_frozen, key_bytes)
  in
    $P.and_then<$IDB.lookup><int>(stored, llam(found) => let
      val @(file_high, file_low) = _file_of(found, id_high, id_low)
    in
      (* the book that is open may be another by now, and then there is nothing to say *)
      if ~(!_remembered) then $P.ret<int>(0)
      else if !_book_high <> id_high then $P.ret<int>(0)
      else if !_book_low <> id_low then $P.ret<int>(0)
      else if file_high = opened_high then (if file_low = opened_low then $P.ret<int>(0) else $P.ret<int>(1))
      else $P.ret<int>(1)
    end)
  end

(* Stores the record of the book (id_high, id_low): the halves of its file's id *)
fn _write (id_high: Int, id_low: Int, file_high: Int, file_low: Int): void = let
  val record = $A.alloc<byte>(8)
  val () = $A.write_i32(record, 0, file_high)
  val () = $A.write_i32(record, 4, file_low)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_key_of(id_high, id_low))
  (* ignored: a record not kept leaves another tab reading the old file until
     it is reopened, which is the state before this record *)
  val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 15, record_bytes, 8), llam(_) => ())
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* Keeps the book (id_high, id_low) as made from the file with the id
   (file_high, file_low): a record when the file is not the one the book is
   named for, else none (a record kept before is deleted) *)
#pub fn file_version_store (id_high: Int, id_low: Int, file_high: Int, file_low: Int): void

implement file_version_store (id_high, id_low, file_high, file_low) =
  if id_high = file_high then (if id_low = file_low then let
      val @(key_frozen, key_bytes) = $A.freeze<byte>(_key_of(id_high, id_low))
      (* ignored: a record not deleted names the file the book was replaced with
         before, and a tab then leaves a book it need not *)
      val () = $P.finish<$IDB.stored>($IDB.idb_delete(key_bytes, 15), llam(_) => ())
    in release_bytes(key_frozen, key_bytes) end
    else _write(id_high, id_low, file_high, file_low))
  else _write(id_high, id_low, file_high, file_low)

end (* #target wasm *)
