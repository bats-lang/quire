(* backup -- the library's state in one JSON file: the settings, and
   each book's id, title, author, shelf, dates, reading position and
   annotations (not its file, which the user has). Restoring it puts
   that state back; a book not in the library keeps its record, and its
   annotations, until it is imported again. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "ui.sats"
staload "notice.sats"
staload "modal.sats"
staload "book.sats"
staload "library.sats"
staload "settings.sats"
staload "annot.sats"
staload "jsonio.sats"
staload "mem.sats"
staload "stats.sats"
staload "app.sats"
staload "dictionary.sats"
staload "clock.sats"
staload "catalogues.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* A backup's most bytes *)
#define BACKUP_MAX_BYTES 268435456

(* The file, made a chunk at a time *)
val _file = ref<jfile(BACKUP_MAX_BYTES)>(jfile_new{BACKUP_MAX_BYTES}())

fn _file_take (): jfile(BACKUP_MAX_BYTES) = let
  var file: jfile(BACKUP_MAX_BYTES) = jfile_new{BACKUP_MAX_BYTES}()
  val () = ref_exch_elt<jfile(BACKUP_MAX_BYTES)>(_file, file)
in file end

fn _file_put (file: jfile(BACKUP_MAX_BYTES)): void = let
  var current: jfile(BACKUP_MAX_BYTES) = file
  val () = ref_exch_elt<jfile(BACKUP_MAX_BYTES)>(_file, current)
in jfile_free(current) end

(* Adds chunk after the chunks so far *)
fn _push (chunk: jchunk): void = _file_put(jfile_push(_file_take(), BACKUP_MAX_BYTES, chunk))

(* ============================================================
   Export
   ============================================================ *)

fn _say {text_len:pos | text_len < 256} (text: string text_len): void = let
  val () = modal_inform("Backup")
in modal_text_lit(text) end

(* The file's start: its settings, and the books' opening bracket *)
fn _settings_chunk (): jchunk =
  case+ piece_new(576) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => let
      val next = jw_lit(out, 0, "{\"quire\":1,\"settings\":{\"size\":")
      val next = jw_int(out, next, set_size_get())
      val next = jw_lit(out, next, ",\"lineHeight\":")
      val next = jw_int(out, next, set_lh_get())
      val next = jw_lit(out, next, ",\"margins\":")
      val next = jw_int(out, next, set_margin_get())
      val next = jw_lit(out, next, ",\"font\":")
      val next = jw_int(out, next, set_font_get())
      val next = jw_lit(out, next, ",\"theme\":")
      val next = jw_int(out, next, set_theme_get())
      val next = jw_lit(out, next, ",\"align\":")
      val next = jw_int(out, next, set_align_get())
      val next = jw_lit(out, next, ",\"hyphens\":")
      val next = jw_int(out, next, set_hyph_get())
      val next = jw_lit(out, next, ",\"paragraphSpacing\":")
      val next = jw_int(out, next, set_ps_get())
      val next = jw_lit(out, next, ",\"letterSpacing\":")
      val next = jw_int(out, next, set_ls_get())
      val next = jw_lit(out, next, ",\"wordSpacing\":")
      val next = jw_int(out, next, set_ws_get())
      val next = jw_lit(out, next, ",\"dimImages\":")
      val next = jw_int(out, next, set_dim_get())
      val next = jw_lit(out, next, ",\"tapZones\":")
      val next = jw_int(out, next, set_taps_get())
      val next = jw_lit(out, next, ",\"volumeKeys\":")
      val next = jw_int(out, next, set_vol_get())
      val next = jw_lit(out, next, ",\"footerReadout\":")
      val next = jw_int(out, next, set_rd_get())
      val next = jw_lit(out, next, ",\"scrolled\":")
      val next = jw_int(out, next, set_flow_get())
      val next = jw_lit(out, next, ",\"columns\":")
      val next = jw_int(out, next, set_cols_get())
      val next = jw_lit(out, next, ",\"ruby\":")
      val next = jw_int(out, next, set_ruby_get())
      val next = jw_lit(out, next, ",\"sort\":")
      val next = jw_int(out, next, lib_sort_get())
      val next = jw_lit(out, next, ",\"libraryGrid\":")
      val next = jw_int(out, next, lib_grid_get())
      val next = jw_lit(out, next, ",\"libraryFilter\":")
      val next = jw_int(out, next, lib_filter_get())
      val next = jw_lit(out, next, ",\"dailyGoal\":")
      val next = jw_int(out, next, stats_goal_get())
      val next = jw_lit(out, next, "}")
    in JChunk(owner, out, next) end

(* The collections' names, from collection on of count, each after a
   comma but the first; at most 243 bytes each *)
fun _names_json {l:agz}{owner:addr}{n:nat}{collection:nat | collection <= 8}
  {position:nat | position + 250 * (8 - collection) + 32 <= n} .<8 - collection>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, collection: int collection, count: int)
  : [stop:nat | stop + 32 <= n] int stop =
  if collection >= 8 then position
  else if collection >= count then position
  else let
    val after_comma = (if collection > 0 then jw_lit(out, position, ",") else position)
      : [after:nat | position <= after; after <= position + 1] int after
    val @(name, name_len) = lib_coll_name_copy(collection)
    val after_name = jw_str(out, after_comma, name, name_len)
    val () = $A.free<byte>(name)
  in _names_json(out, after_name, collection + 1, count) end

(* The reading log's days from entries, as [day, minutes] pairs (days
   since 1970-01-01, local), each after a comma but the first *)
fun _days_json {l:agz}{owner:addr}{n:nat}{count:nat}{position:nat | position + 26 * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, entries: !days(count), first: bool)
  : [stop:nat | stop <= position + 26 * count] int stop =
  case+ entries of
  | DaysNil() => position
  | DaysCons(day, minutes, rest) => let
      val opened = (if first then jw_lit(out, position, "[") else jw_lit(out, position, ",["))
        : [after:int | position < after; after <= position + 2] int after
      val after_day = jw_int(out, opened, day)
      val after_comma = jw_lit(out, after_day, ",")
      val after_minutes = jw_int(out, after_comma, minutes)
      val closed = jw_lit(out, after_minutes, "]")
    in _days_json(out, closed, rest, false) end

(* The reading log, after the settings *)
fn _log_chunk (): jchunk =
  case+ piece_new(26 * 400 + 32) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => let
      val @(entries, _) = stats_days()
      val next = jw_lit(out, 0, ",\"readingLog\":[")
      val next = _days_json(out, next, entries, true)
      val () = stats_days_free(entries)
      val next = jw_lit(out, next, "]")
    in JChunk(owner, out, next) end

(* The collections, after the settings, and the books' opening bracket *)
fn _collections_chunk (): jchunk =
  case+ piece_new(2100) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => let
      val next = jw_lit(out, 0, ",\"collections\":[")
      val next = _names_json(out, next, 0, lib_coll_count())
      val next = jw_lit(out, next, "],\"books\":[")
    in JChunk(owner, out, next) end

(* ============================================================
   A book's numbers, as a backup (or sync's file) has them
   ============================================================ *)

(* numbers[0, 3) its id (numbers[2] is 1 once read); numbers[3, 12) its
   shelf, when it was added and opened, its place (chapter, chapters,
   page, pages, anchor) and whether it is done; numbers[12] the
   collections it is in (bit j for the file's collection j); numbers[13,
   16) its minutes read, the pages turned on them and when it was
   finished; numbers[16, 19) when its shelf, collections and being
   finished last changed (stamps, clock.bats); numbers[19] its file's
   size. A number a file does not give is -1 (0 for those before the
   anchor, and for done) *)
#pub stadef BOOK_NUMBERS = 20

#define SLOT_SHELF 3
#define SLOT_ADDED 4
#define SLOT_OPENED 5
#define SLOT_CHAPTER 6
#define SLOT_CHAPTERS 7
#define SLOT_PAGE 8
#define SLOT_PAGES 9
#define SLOT_ANCHOR 10
#define SLOT_DONE 11
#define SLOT_COLLECTIONS 12
#define SLOT_MINUTES 13
#define SLOT_PAGES_READ 14
#define SLOT_FINISHED 15
#define SLOT_SHELF_MODIFIED 16
#define SLOT_COLLECTIONS_MODIFIED 17
#define SLOT_FINISHED_MODIFIED 18
#define SLOT_SIZE 19

(* A book's numbers, before its members are read *)
fun _clear_numbers {numbers_loc:agz}{i:nat | i <= BOOK_NUMBERS} .<BOOK_NUMBERS - i>.
  (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), i: int i): void =
  if i >= 20 then ()
  else let
    val () = $A.set<Int>(numbers, i, (if i = SLOT_ANCHOR then ~1 else if i >= SLOT_COLLECTIONS then ~1 else 0))
  in _clear_numbers(numbers, i + 1) end

#pub fn backup_numbers_clear {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void
implement backup_numbers_clear (numbers) = _clear_numbers(numbers, 0)

(* A book's numbers, cleared *)
#pub fn backup_numbers_new (): [numbers_loc:agz] $A.arr(Int, numbers_loc, BOOK_NUMBERS)
implement backup_numbers_new () = let
  val numbers = $A.alloc<Int>(20)
  val () = _clear_numbers(numbers, 0)
in numbers end

(* A library book's numbers (its collections as the library numbers
   them) *)
#pub fn backup_numbers_of {numbers_loc:agz} (nums: bnums, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void
implement backup_numbers_of (nums, numbers) = let
  val () = $A.set<Int>(numbers, 0, nums.id_high)
  val () = $A.set<Int>(numbers, 1, nums.id_low)
  val () = $A.set<Int>(numbers, 2, 1)
  val () = $A.set<Int>(numbers, SLOT_SHELF, nums.shelf)
  val () = $A.set<Int>(numbers, SLOT_ADDED, nums.added)
  val () = $A.set<Int>(numbers, SLOT_OPENED, nums.opened)
  val () = $A.set<Int>(numbers, SLOT_CHAPTER, nums.chapter)
  val () = $A.set<Int>(numbers, SLOT_CHAPTERS, nums.chapters)
  val () = $A.set<Int>(numbers, SLOT_PAGE, nums.page)
  val () = $A.set<Int>(numbers, SLOT_PAGES, nums.pages)
  val () = $A.set<Int>(numbers, SLOT_ANCHOR, nums.anchor)
  val () = $A.set<Int>(numbers, SLOT_DONE, nums.done)
  val () = $A.set<Int>(numbers, SLOT_COLLECTIONS, nums.collections)
  val () = $A.set<Int>(numbers, SLOT_MINUTES, nums.minutes_read)
  val () = $A.set<Int>(numbers, SLOT_PAGES_READ, nums.pages_read)
  val () = $A.set<Int>(numbers, SLOT_FINISHED, nums.finished_at)
  val () = $A.set<Int>(numbers, SLOT_SHELF_MODIFIED, nums.shelf_modified)
  val () = $A.set<Int>(numbers, SLOT_COLLECTIONS_MODIFIED, nums.collections_modified)
  val () = $A.set<Int>(numbers, SLOT_FINISHED_MODIFIED, nums.finished_modified)
in $A.set<Int>(numbers, SLOT_SIZE, nums.file_size) end

(* The book's id, when the numbers have one *)
#pub fn backup_numbers_id {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): @(bool, Int, Int)
implement backup_numbers_id (numbers) =
  @($A.get<Int>(numbers, 2) = 1, $A.get<Int>(numbers, 0), $A.get<Int>(numbers, 1))

(* The collections the book is in: mask, bit j for collection j *)
#pub fn backup_numbers_collections {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), mask: Int): void
implement backup_numbers_collections (numbers, mask) = $A.set<Int>(numbers, SLOT_COLLECTIONS, mask)

(* The book's place: its chapter, page and anchor *)
#pub fn backup_numbers_place {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): @(Int, Int, Int)
implement backup_numbers_place (numbers) =
  @($A.get<Int>(numbers, SLOT_CHAPTER), $A.get<Int>(numbers, SLOT_PAGE), $A.get<Int>(numbers, SLOT_ANCHOR))

(* The minutes the book has been read and the pages turned on them, as
   the numbers give them: minutes and pages, or (-1) not given *)
#pub fn backup_numbers_reading {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), minutes: Int, pages: Int): void
implement backup_numbers_reading (numbers, minutes, pages) = let
  val () = $A.set<Int>(numbers, SLOT_MINUTES, minutes)
in $A.set<Int>(numbers, SLOT_PAGES_READ, pages) end

(* Whether place (chapter, page of pages) is further in the book than
   other: a later chapter, or further through the same one *)
fn _further (chapter: Int, page: Int, pages: Int, other_chapter: Int, other_page: Int, other_pages: Int): bool =
  if chapter <> other_chapter then chapter > other_chapter
  else let
    val page = (if page > 0 then page else 0): Int
    val other_page = (if other_page > 0 then other_page else 0): Int
    val pages = (if pages > 0 then pages else 1): Int
    val other_pages = (if other_pages > 0 then other_pages else 1): Int
  in page * other_pages > other_page * pages end

(* Whether the place numbers give is further than other's *)
#pub fn backup_numbers_further {numbers_loc,other_loc:agz}
  (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), other: !$A.arr(Int, other_loc, BOOK_NUMBERS)): bool
implement backup_numbers_further (numbers, other) =
  _further($A.get<Int>(numbers, SLOT_CHAPTER), $A.get<Int>(numbers, SLOT_PAGE), $A.get<Int>(numbers, SLOT_PAGES),
    $A.get<Int>(other, SLOT_CHAPTER), $A.get<Int>(other, SLOT_PAGE), $A.get<Int>(other, SLOT_PAGES))

(* numbers[first, first + count) := other's *)
fun _take_slots {numbers_loc,other_loc:agz}{first,count:nat | first + count <= BOOK_NUMBERS} .<count>.
  (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), other: !$A.arr(Int, other_loc, BOOK_NUMBERS), first: int first, count: int count): void =
  if count <= 0 then ()
  else let
    val () = $A.set<Int>(numbers, first, $A.get<Int>(other, first))
  in _take_slots(numbers, other, first + 1, count - 1) end

(* Whether other's change of a value (value and stamp at its slots) is
   the later of the two: the later stamp, or the greater value when two
   devices made theirs at the same stamp (an order both agree on) *)
fn _later {numbers_loc,other_loc:agz}{value_slot,stamp_slot:nat | value_slot < BOOK_NUMBERS; stamp_slot < BOOK_NUMBERS}
  (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), other: !$A.arr(Int, other_loc, BOOK_NUMBERS), value_slot: int value_slot, stamp_slot: int stamp_slot): bool = let
  val stamp = $A.get<Int>(numbers, stamp_slot)
  val other_stamp = $A.get<Int>(other, stamp_slot)
in
  if other_stamp < 0 then false
  else if other_stamp > stamp then true
  else if other_stamp < stamp then false
  else $A.get<Int>(other, value_slot) > $A.get<Int>(numbers, value_slot)
end

(* numbers merged with other's (the same book's on another device, both
   with their collections numbered alike): the furthest place, unless
   keep_place (the book is open here: the reader is offered the other
   place instead); the shelf, the collections and being finished of the
   later change; when it was added, the earliest; opened, the latest *)
#pub fn backup_numbers_merge {numbers_loc,other_loc:agz}
  (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), other: !$A.arr(Int, other_loc, BOOK_NUMBERS), keep_place: bool): void
implement backup_numbers_merge (numbers, other, keep_place) = let
  val () = (if keep_place then () else if backup_numbers_further(other, numbers) then _take_slots(numbers, other, SLOT_CHAPTER, 5) else ())
  val () = (if _later(numbers, other, SLOT_SHELF, SLOT_SHELF_MODIFIED) then let
      val () = $A.set<Int>(numbers, SLOT_SHELF, $A.get<Int>(other, SLOT_SHELF))
    in $A.set<Int>(numbers, SLOT_SHELF_MODIFIED, $A.get<Int>(other, SLOT_SHELF_MODIFIED)) end else ())
  val () = (if _later(numbers, other, SLOT_COLLECTIONS, SLOT_COLLECTIONS_MODIFIED) then let
      val () = $A.set<Int>(numbers, SLOT_COLLECTIONS, $A.get<Int>(other, SLOT_COLLECTIONS))
    in $A.set<Int>(numbers, SLOT_COLLECTIONS_MODIFIED, $A.get<Int>(other, SLOT_COLLECTIONS_MODIFIED)) end else ())
  val () = (if _later(numbers, other, SLOT_DONE, SLOT_FINISHED_MODIFIED) then let
      val () = $A.set<Int>(numbers, SLOT_DONE, $A.get<Int>(other, SLOT_DONE))
      val () = $A.set<Int>(numbers, SLOT_FINISHED, $A.get<Int>(other, SLOT_FINISHED))
    in $A.set<Int>(numbers, SLOT_FINISHED_MODIFIED, $A.get<Int>(other, SLOT_FINISHED_MODIFIED)) end else ())
  val added = $A.get<Int>(numbers, SLOT_ADDED)
  val other_added = $A.get<Int>(other, SLOT_ADDED)
  val () = (if other_added > 0 then (if added <= 0 then $A.set<Int>(numbers, SLOT_ADDED, other_added)
    else if other_added < added then $A.set<Int>(numbers, SLOT_ADDED, other_added) else ()) else ())
in
  if $A.get<Int>(other, SLOT_OPENED) > $A.get<Int>(numbers, SLOT_OPENED) then $A.set<Int>(numbers, SLOT_OPENED, $A.get<Int>(other, SLOT_OPENED))
  else ()
end

(* Every stamp of numbers, seen: what this device changes next is later
   than them *)
#pub fn backup_numbers_seen {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void
implement backup_numbers_seen (numbers) = let
  val () = stamp_seen($A.get<Int>(numbers, SLOT_SHELF_MODIFIED))
  val () = stamp_seen($A.get<Int>(numbers, SLOT_COLLECTIONS_MODIFIED))
in stamp_seen($A.get<Int>(numbers, SLOT_FINISHED_MODIFIED)) end

(* The numbers of the collections a book is in (the bits of
   collections), from collection on, each after a comma but the first:
   at most 31 of them *)
fun _collection_numbers_json {l:agz}{owner:addr}{n:nat}{collection:nat | collection <= 31}
  {position:nat | position + 3 * (31 - collection) <= n} .<31 - collection>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, collection: int collection,
   collections: int, first: bool)
  : [stop:nat | stop <= position + 3 * (31 - collection)] int stop =
  if collection >= 31 then position
  else if $AR.band_int_int(collections, $AR.bsl_int_int(1, collection)) = 0 then
    _collection_numbers_json(out, position, collection + 1, collections, first)
  else let
    val after_comma = (if first then position else jw_lit(out, position, ",")): [after:nat | position <= after; after <= position + 1] int after
    val stop = (if collection >= 10 then let
        val () = $A.write_byte(out, after_comma, $AR.low_byte(48 + collection / 10))
        val () = $A.write_byte(out, after_comma + 1, $AR.low_byte(48 + collection - 10 * (collection / 10)))
      in after_comma + 2 end
      else let
        val () = $A.write_byte(out, after_comma, 48 + collection)
      in after_comma + 1 end): [stop:nat | stop <= position + 3] int stop
  in _collection_numbers_json(out, stop, collection + 1, collections, false) end

fn _text_chunk {text_len:pos | text_len <= 16} (text: string text_len): jchunk =
  case+ piece_new(16) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => JChunk(owner, out, jw_lit(out, 0, text))

(* A number of numbers, or 0 when the file did not give it *)
fn _given {numbers_loc:agz}{slot:nat | slot < BOOK_NUMBERS} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), slot: int slot): Int = let
  val value = $A.get<Int>(numbers, slot)
in if value < 0 then 0 else value end

(* Book book_index's members (its title and author the library's, its
   numbers numbers), up to its annotations' value; after another book's
   closing brace when it is not the first *)
#pub fn backup_book_chunk {book_index:int}{numbers_loc:agz}
  (book_index: int book_index, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), first: bool): jchunk
implement backup_book_chunk (book_index, numbers, first) =
  case+ piece_new(4096) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => let
      val @(title, title_len) = lib_text(book_index, 0)
      val @(author, author_len) = lib_text(book_index, 1)
      val next = (if first then jw_lit(out, 0, "{\"id\":") else jw_lit(out, 0, "},{\"id\":"))
        : [after:int | 6 <= after; after <= 8] int after
      val next = jw_id(out, next, $A.get<Int>(numbers, 0), $A.get<Int>(numbers, 1))
      val next = jw_lit(out, next, ",\"title\":")
      val next = jw_str(out, next, title, title_len)
      val next = jw_lit(out, next, ",\"author\":")
      val next = jw_str(out, next, author, author_len)
      val () = $A.free<byte>(title)
      val () = $A.free<byte>(author)
      val next = jw_lit(out, next, ",\"shelf\":")
      val next = jw_int(out, next, _given(numbers, SLOT_SHELF))
      val next = jw_lit(out, next, ",\"added\":")
      val next = jw_int(out, next, _given(numbers, SLOT_ADDED))
      val next = jw_lit(out, next, ",\"opened\":")
      val next = jw_int(out, next, _given(numbers, SLOT_OPENED))
      val next = jw_lit(out, next, ",\"chapter\":")
      val next = jw_int(out, next, _given(numbers, SLOT_CHAPTER))
      val next = jw_lit(out, next, ",\"chapters\":")
      val next = jw_int(out, next, _given(numbers, SLOT_CHAPTERS))
      val next = jw_lit(out, next, ",\"page\":")
      val next = jw_int(out, next, _given(numbers, SLOT_PAGE))
      val next = jw_lit(out, next, ",\"pages\":")
      val next = jw_int(out, next, _given(numbers, SLOT_PAGES))
      val next = jw_lit(out, next, ",\"anchor\":")
      val next = jw_int(out, next, $A.get<Int>(numbers, SLOT_ANCHOR))
      val next = jw_lit(out, next, ",\"size\":")
      val next = jw_int(out, next, _given(numbers, SLOT_SIZE))
      val next = jw_lit(out, next, ",\"done\":")
      val next = jw_int(out, next, _given(numbers, SLOT_DONE))
      val next = jw_lit(out, next, ",\"collections\":[")
      val next = _collection_numbers_json(out, next, 0, _given(numbers, SLOT_COLLECTIONS), true)
      val next = jw_lit(out, next, "]")
      val next = jw_lit(out, next, ",\"readMinutes\":")
      val next = jw_int(out, next, _given(numbers, SLOT_MINUTES))
      val next = jw_lit(out, next, ",\"readPages\":")
      val next = jw_int(out, next, _given(numbers, SLOT_PAGES_READ))
      val next = jw_lit(out, next, ",\"finished\":")
      val next = jw_int(out, next, _given(numbers, SLOT_FINISHED))
      val next = jw_lit(out, next, ",\"shelfModified\":")
      val next = jw_stamp(out, next, _given(numbers, SLOT_SHELF_MODIFIED))
      val next = jw_lit(out, next, ",\"collectionsModified\":")
      val next = jw_stamp(out, next, _given(numbers, SLOT_COLLECTIONS_MODIFIED))
      val next = jw_lit(out, next, ",\"finishedModified\":")
      val next = jw_stamp(out, next, _given(numbers, SLOT_FINISHED_MODIFIED))
      val next = jw_lit(out, next, ",\"annotations\":")
    in JChunk(owner, out, next) end

(* Library book book_index's members, up to its annotations' value *)
fn _book_chunk {book_index:int} (book_index: int book_index, nums: bnums, first: bool): jchunk = let
  val numbers = backup_numbers_new()
  val () = backup_numbers_of(nums, numbers)
  val chunk = backup_book_chunk(book_index, numbers, first)
  val () = $A.free<Int>(numbers)
in chunk end

(* Downloads the chunks as one file *)
fn _export_finish (): void =
  case+ jfile_join(_file_take()) of
  | ~JNoWhole() => _say("The backup could not be made: there is not enough memory.")
  | ~JWhole(owner, out, total) => let
      val @(file_frozen, file_bytes) = $A.freeze<byte>(out)
      val mime = $A.alloc<byte>(16)
      val () = $A.write_text(mime, 0, $A.text_lit("application/json"), 16)
      val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime)
      val file_name = $A.alloc<byte>(17)
      val () = $A.write_text(file_name, 0, $A.text_lit("quire-backup.json"), 17)
      val @(name_frozen, name_bytes) = $A.freeze<byte>(file_name)
      val () = $BL.download_blob(file_bytes, total, mime_bytes, 16, name_bytes, 17)
      val () = release_bytes(name_frozen, name_bytes)
      val () = release_bytes(mime_frozen, mime_bytes)
      val () = $A.drop<byte>(file_frozen, file_bytes)
    in piece_free(owner, $A.thaw<byte>(file_frozen)) end

(* Books book_index to count - 1, one after another (each one's
   annotations are read from storage); then the file is downloaded *)
fun _export_books {book_index,count:nat | book_index <= count} .<count - book_index>.
  (book_index: int book_index, count: int count, first: bool): void =
  if book_index >= count then let
    val () = (if first then _push(_text_chunk("]}")) else _push(_text_chunk("}]}")))
  in _export_finish() end
  else (case+ lib_nums(book_index) of
    | ~$R.none() => _export_books(book_index + 1, count, first)
    | ~$R.some(numbers) => let
        val () = _push(_book_chunk(book_index, numbers, first))
        val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(97, numbers.id_high, numbers.id_low))
        val pending = $IDB.idb_get(key_bytes, 15)
        val () = release_bytes(key_frozen, key_bytes)
      in
        $P.finish<$IDB.lookup>(pending, llam(found) =>
          case+ lookup_content(found) of
          | ~NoStoredContent() => let
              val () = _push(_text_chunk("[]"))
            in _export_books(book_index + 1, count, false) end
          (* a backup that looks whole but lost a book's notes is worse
             than none: it is not made (#174) *)
          | ~ContentUnreadable() => let
              val () = _file_put(jfile_new{BACKUP_MAX_BYTES}())
            in _say("The backup could not be made: a book's notes could not be read. Try again.") end
          | ~StoredContent(content_owner, content, content_len) => let
              val annotations = annot_json(content, content_len)
              val () = piece_free(content_owner, content)
              val () = (case+ annotations of
                | ~JNone() => _push(_text_chunk("[]"))
                | ~JChunk(annotations_owner, annotations_bytes, annotations_len) =>
                  _push(JChunk(annotations_owner, annotations_bytes, annotations_len)))
            in _export_books(book_index + 1, count, false) end)
      end)

(* Downloads the backup, quire-backup.json *)
#pub fn backup_export (): void

implement backup_export () = let
  val () = _file_put(jfile_new{BACKUP_MAX_BYTES}())
  val () = _push(_settings_chunk())
  val () = _push(_log_chunk())
  val () = _push(dict_backup_json())
  val () = _push(catalogue_backup_json())
  val () = _push(_collections_chunk())
in _export_books(0, lib_count(), true) end

(* ============================================================
   A book's record kept for later: "o" and its id
   ============================================================ *)

(* The record's numbers, in order: shelf, added, opened, chapter,
   chapters, page, pages, anchor, done, collections (as the library
   numbers them), minutes read, pages turned on them, finished, and when
   the shelf, the collections and being finished last changed. A record
   kept by an earlier version has the first 9 (RECORD_NUMBERS_FIRST), 10
   or 13 of them. *)
#define RECORD_NUMBERS 16
#define RECORD_NUMBERS_FIRST 9

fun _orphan_write {record_loc,numbers_loc:agz}{i:nat | i <= RECORD_NUMBERS} .<RECORD_NUMBERS - i>.
  (record: !$A.arr(byte, record_loc, 4 + 4 * RECORD_NUMBERS),
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), i: int i): void =
  if i >= RECORD_NUMBERS then ()
  else let
    val () = $A.write_i32(record, 4 + 4 * i, $A.get<Int>(numbers, 3 + i))
  in _orphan_write(record, numbers, i + 1) end

(* numbers[3 + i, 3 + count) := the count numbers at
   record[4 + 4 * i, 4 + 4 * count) *)
fun _orphan_read_numbers {record_loc,numbers_loc:agz}{count:nat | count <= RECORD_NUMBERS}
  {n:int | n >= 4 + 4 * count}{i:nat | i <= count} .<count - i>.
  (record: !$A.arr(byte, record_loc, n), count: int count,
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), i: int i): void =
  if i >= count then ()
  else let
    val offset = 4 + 4 * i
    val lowest = $AR.low_byte(byte2int0($A.get<byte>(record, offset)))
    val second = $AR.low_byte(byte2int0($A.get<byte>(record, offset + 1)))
    val third = $AR.low_byte(byte2int0($A.get<byte>(record, offset + 2)))
    val highest = $AR.low_byte(byte2int0($A.get<byte>(record, offset + 3)))
    val signed_highest = (if highest < 128 then highest else highest - 256): Int
    val () = $A.set<Int>(numbers, 3 + i, lowest + second * 256 + third * 65536 + signed_highest * 16777216)
  in _orphan_read_numbers(record, count, numbers, i + 1) end

(* A kept record's numbers, record[0, n), into numbers: RECORD_NUMBERS
   of them, or as many as an earlier version kept *)
fn _orphan_read {record_loc,numbers_loc:agz}{n:int | n >= 4 + 4 * RECORD_NUMBERS_FIRST}
  (record: !$A.arr(byte, record_loc, n), n: int n, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void =
  if n >= 4 + 4 * RECORD_NUMBERS then _orphan_read_numbers(record, RECORD_NUMBERS, numbers, 0)
  else if n >= 4 + 4 * 13 then _orphan_read_numbers(record, 13, numbers, 0)
  else if n >= 4 + 4 * 10 then _orphan_read_numbers(record, 10, numbers, 0)
  else _orphan_read_numbers(record, RECORD_NUMBERS_FIRST, numbers, 0)

(* Keeps numbers[3, 19) (a book's numbers from a backup or from sync,
   its collections as the library numbers them) under its "o" key, for
   when the book is imported *)
#pub fn backup_orphan_put {numbers_loc:agz}
  (id_high: int, id_low: int, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void
implement backup_orphan_put (id_high, id_low, numbers) = let
  val record = $A.alloc<byte>(4 + 4 * RECORD_NUMBERS)
  val () = $A.write_text(record, 0, $A.text_lit("QO1"), 3)
  val () = $A.write_byte(record, 3, 10)
  val () = _orphan_write(record, numbers, 0)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(111, id_high, id_low))
  val () = save_checked($IDB.idb_put(key_bytes, 15, record_bytes, 4 + 4 * RECORD_NUMBERS))
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* value in [low, high], or fallback *)
fn _in_range (value: Int, low: Int, high: Int, fallback: Int): Int =
  if value < low then fallback else if value > high then fallback else value

(* Library book book_index's numbers set from numbers (its collections
   as the library numbers them), each one the numbers do not give left
   as it is: a shelf up to shelf_most (2 from a backup, which puts
   nothing in the Trash; 3 from sync) *)
#pub fn backup_apply_numbers {book_index:int}{numbers_loc:agz}
  (book_index: int book_index, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), shelf_most: int): void
implement backup_apply_numbers (book_index, numbers, shelf_most) = let
  val shelf = _in_range($A.get<Int>(numbers, SLOT_SHELF), 0, g1ofg0(shelf_most), 0)
  val added = $A.get<Int>(numbers, SLOT_ADDED)
  val opened = _in_range($A.get<Int>(numbers, SLOT_OPENED), 0, 2147483647, 0)
  val chapter = _in_range($A.get<Int>(numbers, SLOT_CHAPTER), 0, 2147483647, 0)
  val chapters = _in_range($A.get<Int>(numbers, SLOT_CHAPTERS), 0, 2147483647, 0)
  val page = _in_range($A.get<Int>(numbers, SLOT_PAGE), 0, 2147483647, 0)
  val pages = _in_range($A.get<Int>(numbers, SLOT_PAGES), 0, 2147483647, 0)
  val anchor = _in_range($A.get<Int>(numbers, SLOT_ANCHOR), ~1, 2147483647, ~1)
  val done = _in_range($A.get<Int>(numbers, SLOT_DONE), 0, 1, 0)
  (* the collections, when the file says which: of those there are *)
  val collections = $A.get<Int>(numbers, SLOT_COLLECTIONS)
  val collections = (if collections >= 0
    then g1ofg0($AR.band_int_int(collections, $AR.bsl_int_int(1, lib_coll_count()) - 1)) else ~1): Int
  (* its reading statistics, when the file has them *)
  val minutes = _in_range($A.get<Int>(numbers, SLOT_MINUTES), ~1, 2147483647, ~1)
  val pages_turned = _in_range($A.get<Int>(numbers, SLOT_PAGES_READ), ~1, 2147483647, ~1)
  val finished = _in_range($A.get<Int>(numbers, SLOT_FINISHED), ~1, 2147483647, ~1)
  (* when they changed, when the file says *)
  val shelf_modified = _in_range($A.get<Int>(numbers, SLOT_SHELF_MODIFIED), ~1, 2147483647, ~1)
  val collections_modified = _in_range($A.get<Int>(numbers, SLOT_COLLECTIONS_MODIFIED), ~1, 2147483647, ~1)
  val finished_modified = _in_range($A.get<Int>(numbers, SLOT_FINISHED_MODIFIED), ~1, 2147483647, ~1)
in
  (case+ lib_nums(book_index) of ~$R.none() => () | ~$R.some(before) => lib_nums_set(book_index, @{
    key = before.key, id_high = before.id_high, id_low = before.id_low, shelf = shelf,
    added = (if added > 0 then added else before.added), opened = opened,
    chapter = chapter, chapters = chapters, page = page, pages = pages, anchor = anchor,
    file_size = before.file_size, cover = before.cover, done = done, series_number = before.series_number,
    collections = (if collections >= 0 then collections else before.collections),
    minutes_read = (if minutes >= 0 then minutes else before.minutes_read),
    pages_read = (if pages_turned >= 0 then pages_turned else before.pages_read),
    finished_at = (if finished >= 0 then finished else before.finished_at),
    shelf_modified = (if shelf_modified >= 0 then shelf_modified else before.shelf_modified),
    collections_modified = (if collections_modified >= 0 then collections_modified else before.collections_modified),
    finished_modified = (if finished_modified >= 0 then finished_modified else before.finished_modified),
    minutes_elsewhere = before.minutes_elsewhere, pages_elsewhere = before.pages_elsewhere }))
end

(* Library book id_high, id_low (when it is there) takes the numbers *)
fn _claim_apply {numbers_loc:agz} (id_high: Int, id_low: Int, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void = let
  val book_index = lib_find(id_high, id_low)
in
  if book_index >= 0 then let
    val () = backup_apply_numbers(book_index, numbers, 3)
    val () = lib_save()
  in lib_render() end
  else ()
end

(* A book just imported takes the record a backup (or sync) kept for
   it *)
#pub fn backup_claim (id_high: Int, id_low: Int): void

implement backup_claim (id_high, id_low) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(111, id_high, id_low))
  val pending = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.finish<$IDB.lookup>(pending, llam(found) =>
    case+ lookup_bytes(found) of
    | ~NothingStored() => ()
    (* kept, claimed on a later import: nothing is lost by waiting *)
    | ~StoredUnreadable() => ()
    | ~StoredBytes(record, n) =>
      if n < 4 + 4 * RECORD_NUMBERS_FIRST then $A.free<byte>(record)
      else if byte2int0($A.get<byte>(record, 1)) <> 79 then $A.free<byte>(record)
      else let
        val numbers = backup_numbers_new()
        val () = _orphan_read(record, n, numbers)
        val () = $A.free<byte>(record)
        val () = _claim_apply(id_high, id_low, numbers)
        val () = $A.free<Int>(numbers)
        val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(111, id_high, id_low))
        (* ignored: a record not deleted is applied again only if the
           book is imported again, which is harmless *)
        val () = $P.finish<$IDB.stored>($IDB.idb_delete(key_bytes, 15), llam(_) => ())
      in release_bytes(key_frozen, key_bytes) end)
end

(* ============================================================
   Restore
   ============================================================ *)

(* A member's key's most bytes: the longest a book's numbers have is
   "collectionsModified" *)
#define KEY_BYTES 24

(* The number a book member's key names, its slot in numbers; -1 for
   any other *)
fn _number_slot {key_loc:agz}{key_len:nat | key_len <= KEY_BYTES} (key: !$A.arr(byte, key_loc, KEY_BYTES), key_len: int key_len)
  : [slot:int | ~1 <= slot; slot < BOOK_NUMBERS; slot <> SLOT_COLLECTIONS] int slot =
  if jr_key_is(key, key_len, "shelf") then SLOT_SHELF
  else if jr_key_is(key, key_len, "added") then SLOT_ADDED
  else if jr_key_is(key, key_len, "opened") then SLOT_OPENED
  else if jr_key_is(key, key_len, "chapter") then SLOT_CHAPTER
  else if jr_key_is(key, key_len, "chapters") then SLOT_CHAPTERS
  else if jr_key_is(key, key_len, "page") then SLOT_PAGE
  else if jr_key_is(key, key_len, "pages") then SLOT_PAGES
  else if jr_key_is(key, key_len, "anchor") then SLOT_ANCHOR
  else if jr_key_is(key, key_len, "done") then SLOT_DONE
  else if jr_key_is(key, key_len, "readMinutes") then SLOT_MINUTES
  else if jr_key_is(key, key_len, "readPages") then SLOT_PAGES_READ
  else if jr_key_is(key, key_len, "finished") then SLOT_FINISHED
  else if jr_key_is(key, key_len, "size") then SLOT_SIZE
  else ~1

(* The stamp a book member's key names, its slot in numbers; -1 for any
   other *)
fn _stamp_slot {key_loc:agz}{key_len:nat | key_len <= KEY_BYTES} (key: !$A.arr(byte, key_loc, KEY_BYTES), key_len: int key_len)
  : [slot:int | ~1 <= slot; slot < BOOK_NUMBERS] int slot =
  if jr_key_is(key, key_len, "shelfModified") then SLOT_SHELF_MODIFIED
  else if jr_key_is(key, key_len, "collectionsModified") then SLOT_COLLECTIONS_MODIFIED
  else if jr_key_is(key, key_len, "finishedModified") then SLOT_FINISHED_MODIFIED
  else ~1

(* A number (or true or false) at value_start, kept in numbers[slot] *)
fn _number_at {l,numbers_loc:agz}{owner:addr}{n:nat}{value_start:nat | value_start <= n}{slot:nat | slot < BOOK_NUMBERS}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, value_start: int value_start,
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), slot: int slot)
  : [stop:int | value_start <= stop; stop <= n] int stop = let
  val @(is_int, value, after_int) = jr_int(buf, n, value_start)
in
  if is_int then let val () = $A.set<Int>(numbers, slot, value) in after_int end
  else let
    val @(is_bool, truth, after_bool) = jr_bool(buf, n, value_start)
  in
    if is_bool then let val () = $A.set<Int>(numbers, slot, (if truth then 1 else 0)) in after_bool end
    else jr_skip(buf, n, value_start)
  end
end

(* A stamp at value_start, kept in numbers[slot] *)
fn _stamp_at {l,numbers_loc:agz}{owner:addr}{n:nat}{value_start:nat | value_start <= n}{slot:nat | slot < BOOK_NUMBERS}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, value_start: int value_start,
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), slot: int slot)
  : [stop:int | value_start <= stop; stop <= n] int stop = let
  val @(is_stamp, stamp, after_stamp) = jr_stamp(buf, n, value_start)
in
  if is_stamp then let val () = $A.set<Int>(numbers, slot, stamp) in after_stamp end
  else jr_skip(buf, n, value_start)
end

(* The id member's value at value_start: numbers[0], numbers[1] and
   numbers[2] (1 when read) *)
fn _id_at {l,numbers_loc:agz}{owner:addr}{n:nat}{value_start:nat | value_start < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, value_start: int value_start,
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS))
  : [stop:int | value_start <= stop; stop <= n] int stop = let
  val @(found, id_high, id_low, stop) = jr_id(buf, n, value_start)
in
  if ~found then stop
  else let
    val () = $A.set<Int>(numbers, 0, id_high)
    val () = $A.set<Int>(numbers, 1, id_low)
    val () = $A.set<Int>(numbers, 2, 1)
  in stop end
end

(* The collections of a book's array from position, to its closing
   bracket: mask with bit j for the file's collection j (j below 31) *)
fun _collection_items {l:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, mask: int)
  : [stop:int | position <= stop; stop <= n] @(bool, int, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, mask, n)
  else if jr_is(buf, n, next, 93) then @(true, mask, next + 1)
  else if jr_is(buf, n, next, 44) then _collection_items(buf, n, next + 1, mask)
  else let
    val @(is_int, collection, stop) = jr_int(buf, n, next)
  in
    if ~is_int then @(false, mask, stop)
    else if stop <= next then @(false, mask, stop)
    else let
      val mask = (if collection >= 0 then
        (if collection < 31 then $AR.bor_int_int(mask, $AR.bsl_int_int(1, collection)) else mask)
        else mask): int
    in _collection_items(buf, n, stop, mask) end
  end
end

(* The library's numbers of a file's collections: map[j] for the file's
   collection j (-1 none) *)
#pub stadef MAP_SIZE = 31

(* No collection of the file's known yet *)
fun _unmapped {map_loc:agz}{collection:nat | collection <= MAP_SIZE} .<MAP_SIZE - collection>.
  (map: !$A.arr(Int, map_loc, MAP_SIZE), collection: int collection): void =
  if collection >= 31 then ()
  else let
    val () = $A.set<Int>(map, collection, ~1)
  in _unmapped(map, collection + 1) end

#pub fn backup_map_new (): [map_loc:agz] $A.arr(Int, map_loc, MAP_SIZE)
implement backup_map_new () = let
  val map = $A.alloc<Int>(31)
  val () = _unmapped(map, 0)
in map end

(* mask (bit j for collection j) as map numbers them, from collection
   on, onto mapped *)
fun _mapped {map_loc:agz}{collection:nat | collection <= MAP_SIZE} .<MAP_SIZE - collection>.
  (map: !$A.arr(Int, map_loc, MAP_SIZE), mask: int, collection: int collection, mapped: int): int =
  if collection >= 31 then mapped
  else if $AR.band_int_int(mask, $AR.bsl_int_int(1, collection)) = 0 then _mapped(map, mask, collection + 1, mapped)
  else let
    val number = $A.get<Int>(map, collection)
  in
    if number < 0 then _mapped(map, mask, collection + 1, mapped)
    else if number >= 31 then _mapped(map, mask, collection + 1, mapped)
    else _mapped(map, mask, collection + 1, $AR.bor_int_int(mapped, $AR.bsl_int_int(1, number)))
  end

(* A book's collections (numbers[12], when given) as map numbers them *)
#pub fn backup_map_collections {numbers_loc,map_loc:agz}
  (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), map: !$A.arr(Int, map_loc, MAP_SIZE)): void
implement backup_map_collections (numbers, map) = let
  val mask = $A.get<Int>(numbers, SLOT_COLLECTIONS)
in
  if mask < 0 then ()
  else $A.set<Int>(numbers, SLOT_COLLECTIONS, g1ofg0(_mapped(map, mask, 0, 0)))
end

(* The file's collections from position, to their array's closing
   bracket, from its collection-th: each found in the library by its
   name, or made there, and its number there kept in map[collection] *)
fun _collection_names_at {l,map_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{collection:nat}
  .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   map: !$A.arr(Int, map_loc, MAP_SIZE), collection: int collection)
  : [stop:int | position <= stop; stop <= n] @(bool, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, n)
  else if jr_is(buf, n, next, 93) then @(true, next + 1)
  else if jr_is(buf, n, next, 44) then _collection_names_at(buf, n, next + 1, map, collection)
  else let
    val name = $A.alloc<byte>(256)
    val @(found, name_len, stop) = jr_str(buf, n, next, name, 256)
  in
    if ~found then let val () = $A.free<byte>(name) in @(false, stop) end
    else let
      val library_number = lib_coll_find_or_add(name, name_len)
      val () = (if collection < 31 then $A.set<Int>(map, collection, g1ofg0(library_number)) else ())
    in _collection_names_at(buf, n, stop, map, collection + 1) end
  end
end

(* The library's numbers of the file's collections, the array at
   position: found by name, or made; whether it was read whole, and
   where it ends *)
#pub fn backup_collections_map {l,map_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, map: !$A.arr(Int, map_loc, MAP_SIZE))
  : [stop:int | position <= stop; stop <= n] @(bool, int stop)
implement backup_collections_map (buf, n, position, map) =
  if position >= n then @(false, position)
  else if jr_is(buf, n, position, 91) then _collection_names_at(buf, n, position + 1, map, 0)
  else let val stop = jr_skip(buf, n, position) in @(false, stop) end

(* A book object's members from position, to its closing brace: its
   numbers into numbers (its collections as the file numbers them), and
   where its annotations' array is, and its deleted annotations' (sync's
   "deleted"), each -1 when it has none *)
fun _book_members {l,key_loc,numbers_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  {annotations_start,deleted_start:int | ~1 <= annotations_start; annotations_start <= n; ~1 <= deleted_start; deleted_start <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, KEY_BYTES),
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), annotations: int annotations_start, deleted: int deleted_start)
  : [stop:int | position <= stop; stop <= n][found_at,deleted_at:int | ~1 <= found_at; found_at <= n; ~1 <= deleted_at; deleted_at <= n]
    @(bool, int found_at, int deleted_at, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, annotations, deleted, n)
  else if jr_is(buf, n, next, 125) then @(true, annotations, deleted, next + 1)
  else if jr_is(buf, n, next, 44) then _book_members(buf, n, next + 1, key, numbers, annotations, deleted)
  else let
    val @(found, key_len, value_start) = jr_key(buf, n, next, key, KEY_BYTES)
  in
    if ~found then @(false, annotations, deleted, value_start)
    else if value_start >= n then @(false, annotations, deleted, value_start)
    else if jr_key_is(key, key_len, "id") then
      _book_members(buf, n, _id_at(buf, n, value_start, numbers), key, numbers, annotations, deleted)
    else if jr_key_is(key, key_len, "annotations") then
      _book_members(buf, n, jr_skip(buf, n, value_start), key, numbers, value_start, deleted)
    else if jr_key_is(key, key_len, "deleted") then
      _book_members(buf, n, jr_skip(buf, n, value_start), key, numbers, annotations, value_start)
    else if jr_key_is(key, key_len, "collections") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, mask, stop) = _collection_items(buf, n, value_start + 1, 0)
         val () = $A.set<Int>(numbers, SLOT_COLLECTIONS, g1ofg0(mask))
       in if closed then _book_members(buf, n, stop, key, numbers, annotations, deleted) else @(false, annotations, deleted, stop) end
       else _book_members(buf, n, jr_skip(buf, n, value_start), key, numbers, annotations, deleted))
    else let
      val slot = _number_slot(key, key_len)
    in
      if slot >= 0 then _book_members(buf, n, _number_at(buf, n, value_start, numbers, slot), key, numbers, annotations, deleted)
      else let
        val stamp_slot = _stamp_slot(key, key_len)
      in
        if stamp_slot >= 0 then _book_members(buf, n, _stamp_at(buf, n, value_start, numbers, stamp_slot), key, numbers, annotations, deleted)
        else _book_members(buf, n, jr_skip(buf, n, value_start), key, numbers, annotations, deleted)
      end
    end
  end
end

(* The members of the book object whose opening brace is at position:
   its numbers into numbers (cleared first; its collections as the file
   numbers them), whether it closed, where its annotations' array and
   its deleted annotations' are (-1 none), and where it ends *)
#pub fn backup_book_members {l,numbers_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS))
  : [stop:int | position < stop; stop <= n][found_at,deleted_at:int | ~1 <= found_at; found_at <= n; ~1 <= deleted_at; deleted_at <= n]
    @(bool, int found_at, int deleted_at, int stop)
implement backup_book_members (buf, n, position, numbers) = let
  val () = _clear_numbers(numbers, 0)
  val key = $A.alloc<byte>(KEY_BYTES)
  val @(closed, annotations, deleted, stop) = _book_members(buf, n, position + 1, key, numbers, ~1, ~1)
  val () = $A.free<byte>(key)
in @(closed, annotations, deleted, stop) end

(* The changes a backup's book does not date, dated now: a restore is
   a change of the user's, which sync passes on *)
fn _dated {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void = let
  val () = (if $A.get<Int>(numbers, SLOT_SHELF_MODIFIED) < 0 then $A.set<Int>(numbers, SLOT_SHELF_MODIFIED, stamp_now()) else ())
  val () = (if $A.get<Int>(numbers, SLOT_COLLECTIONS_MODIFIED) < 0 then $A.set<Int>(numbers, SLOT_COLLECTIONS_MODIFIED, stamp_now()) else ())
in if $A.get<Int>(numbers, SLOT_FINISHED_MODIFIED) < 0 then $A.set<Int>(numbers, SLOT_FINISHED_MODIFIED, stamp_now()) else () end

(* Puts a book's state back from numbers: into the library when the
   book is there, else kept under its "o" key; its annotations from the
   array at annotations *)
fn _restore_book {l,numbers_loc,map_loc:agz}{owner:addr}{n:nat}{annotations_start:int | ~1 <= annotations_start; annotations_start <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS),
   map: !$A.arr(Int, map_loc, MAP_SIZE), annotations: int annotations_start): bool =
  if $A.get<Int>(numbers, 2) <> 1 then false
  else let
    val id_high = $A.get<Int>(numbers, 0)
    val id_low = $A.get<Int>(numbers, 1)
    val () = backup_map_collections(numbers, map)
    val () = _dated(numbers)
    val book_index = lib_find(id_high, id_low)
    val () = (if book_index >= 0 then backup_apply_numbers(book_index, numbers, 2) else backup_orphan_put(id_high, id_low, numbers))
    val () = (if annotations >= 0 then let
        val _ = annot_json_store(buf, n, annotations, id_high, id_low)
      in () end else ())
  in true end

(* The books of the array's items from position, to its closing
   bracket, put back one by one; how many *)
fun _book_items {l,numbers_loc,map_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), map: !$A.arr(Int, map_loc, MAP_SIZE), restored: int)
  : [stop:int | position <= stop; stop <= n] @(bool, int, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, restored, n)
  else if jr_is(buf, n, next, 93) then @(true, restored, next + 1)
  else if jr_is(buf, n, next, 44) then _book_items(buf, n, next + 1, numbers, map, restored)
  else if jr_is(buf, n, next, 123) then let
    val @(closed, annotations, _, stop) = backup_book_members(buf, n, next, numbers)
  in
    if ~closed then @(false, restored, stop)
    else if _restore_book(buf, n, numbers, map, annotations) then _book_items(buf, n, stop, numbers, map, restored + 1)
    else _book_items(buf, n, stop, numbers, map, restored)
  end
  else @(false, restored, next)
end

(* The settings object's members from position, to its closing brace,
   each applied when it is in range; the library's sort order *)
fun _settings_members {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16), sort: int)
  : [stop:int | position <= stop; stop <= n] @(bool, int, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, sort, n)
  else if jr_is(buf, n, next, 125) then @(true, sort, next + 1)
  else if jr_is(buf, n, next, 44) then _settings_members(buf, n, next + 1, key, sort)
  else let
    val @(found, key_len, value_start) = jr_key(buf, n, next, key, 16)
  in
    if ~found then @(false, sort, value_start)
    else let
      val @(is_int, value, stop) = jr_int(buf, n, value_start)
    in
      if ~is_int then _settings_members(buf, n, jr_skip(buf, n, value_start), key, sort)
      else if jr_key_is(key, key_len, "size") then let
        val () = (if value >= 12 then (if value <= 32 then set_size_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "lineHeight") then let
        val () = (if value >= 12 then (if value <= 24 then set_lh_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "margins") then let
        val () = (if value >= 0 then (if value <= 4 then set_margin_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "font") then let
        val () = (if value >= 0 then (if value <= 3 then set_font_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "theme") then let
        val () = (if value >= 0 then (if value <= 5 then set_theme_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "align") then let
        val () = (if value >= 0 then (if value <= 1 then set_align_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "hyphens") then let
        val () = (if value >= 0 then (if value <= 1 then set_hyph_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "paragraphSpacing") then let
        val () = (if value >= 0 then (if value <= 20 then set_ps_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "letterSpacing") then let
        val () = (if value >= 0 then (if value <= 12 then set_ls_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "libraryGrid") then let
        val () = (if value >= 0 then (if value <= 1 then
          lib_state_set(lib_sort_get() + 8 * value + 16 * lib_filter_get()) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "libraryFilter") then let
        val () = (if value >= 0 then (if value <= 3 then
          lib_state_set(lib_sort_get() + 8 * lib_grid_get() + 16 * value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "dailyGoal") then let
        val () = (if value >= 0 then (if value <= 600 then stats_goal_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "ruby") then let
        val () = (if value >= 0 then (if value <= 1 then set_ruby_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "columns") then let
        val () = (if value >= 0 then (if value <= 2 then set_cols_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "scrolled") then let
        val () = (if value >= 0 then (if value <= 1 then set_flow_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "footerReadout") then let
        val () = (if value >= 0 then (if value <= 4 then set_rd_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "volumeKeys") then let
        val () = (if value >= 0 then (if value <= 1 then set_vol_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "tapZones") then let
        val () = (if value >= 0 then (if value <= 2 then set_taps_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "dimImages") then let
        val () = (if value >= 0 then (if value <= 1 then set_dim_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "wordSpacing") then let
        val () = (if value >= 0 then (if value <= 16 then set_ws_set(value) else ()) else ())
      in _settings_members(buf, n, stop, key, sort) end
      else if jr_key_is(key, key_len, "sort") then
        _settings_members(buf, n, stop, key, (if value >= 0 then (if value <= 4 then value else sort) else sort))
      else _settings_members(buf, n, stop, key, sort)
    end
  end
end

(* The reading log's [day, minutes] pairs from position, to its array's
   closing bracket: each put back where the log has none for its day *)
fun _log_at {l:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] @(bool, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, n)
  else if jr_is(buf, n, next, 93) then @(true, next + 1)
  else if jr_is(buf, n, next, 44) then _log_at(buf, n, next + 1)
  else if ~jr_is(buf, n, next, 91) then @(false, next)
  else let
    val @(day_found, day, after_day) = jr_int(buf, n, jr_ws(buf, n, next + 1))
    val comma = jr_ws(buf, n, after_day)
  in
    if ~day_found then @(false, comma)
    else if comma >= n then @(false, comma)
    else if ~jr_is(buf, n, comma, 44) then @(false, comma)
    else let
      val @(minutes_found, minutes, after_minutes) = jr_int(buf, n, jr_ws(buf, n, comma + 1))
      val close = jr_ws(buf, n, after_minutes)
    in
      if ~minutes_found then @(false, close)
      else if close >= n then @(false, close)
      else if ~jr_is(buf, n, close, 93) then @(false, close)
      else let
        val () = stats_restore_day(day, minutes)
      in _log_at(buf, n, close + 1) end
    end
  end
end

(* The backup's members from position: whether it is one (its "quire"
   is 1), the books put back, and the sort order *)
fun _top_members {l,key_loc,numbers_loc,map_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), map: !$A.arr(Int, map_loc, MAP_SIZE), quire: bool, books: int, sort: int)
  : @(bool, int, int) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, books, sort)
  else if jr_is(buf, n, next, 125) then @(quire, books, sort)
  else if jr_is(buf, n, next, 44) then _top_members(buf, n, next + 1, key, numbers, map, quire, books, sort)
  else let
    val @(found, key_len, value_start) = jr_key(buf, n, next, key, 16)
  in
    if ~found then @(false, books, sort)
    else if value_start >= n then @(false, books, sort)
    else if jr_key_is(key, key_len, "quire") then let
      val @(is_int, version, stop) = jr_int(buf, n, value_start)
    in
      if is_int then _top_members(buf, n, stop, key, numbers, map, version = 1, books, sort)
      else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, map, false, books, sort)
    end
    else if ~quire then @(false, books, sort)
    else if jr_key_is(key, key_len, "settings") then
      (if jr_is(buf, n, value_start, 123) then let
         val @(closed, new_sort, stop) = _settings_members(buf, n, value_start + 1, key, sort)
       in
         if closed then _top_members(buf, n, stop, key, numbers, map, quire, books, new_sort)
         else @(false, books, sort)
       end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, map, quire, books, sort))
    else if jr_key_is(key, key_len, "readingLog") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, stop) = _log_at(buf, n, value_start + 1)
         val () = stats_restored()
       in if closed then _top_members(buf, n, stop, key, numbers, map, quire, books, sort) else @(false, books, sort) end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, map, quire, books, sort))
    else if jr_key_is(key, key_len, "collections") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, stop) = _collection_names_at(buf, n, value_start + 1, map, 0)
       in if closed then _top_members(buf, n, stop, key, numbers, map, quire, books, sort) else @(false, books, sort) end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, map, quire, books, sort))
    else if jr_key_is(key, key_len, "books") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, restored, stop) = _book_items(buf, n, value_start + 1, numbers, map, books)
       in
         if closed then _top_members(buf, n, stop, key, numbers, map, quire, restored, sort)
         else @(false, restored, sort)
       end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, map, quire, books, sort))
    else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, map, quire, books, sort)
  end
end

fn _restored (count: int): void = let
  val () = modal_inform("Backup restored")
  val buf = $A.alloc<byte>(64)
  val () = $A.write_text(buf, 0, $A.text_lit("Books restored: "), 16)
  val stop = jw_int(buf, 16, count)
in modal_text(buf, stop) end

(* Puts back the backup in buf[0, n) *)
fn _restore {l:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n): void = let
  val start = jr_ws(buf, n, 0)
in
  if start >= n then _say("This file is not a Quire backup.")
  else if ~jr_is(buf, n, start, 123) then _say("This file is not a Quire backup.")
  else let
    val key = $A.alloc<byte>(16)
    val numbers = backup_numbers_new()
    val map = backup_map_new()
    val @(complete, restored, sort) = _top_members(buf, n, start + 1, key, numbers, map, false, 0, lib_sort_get())
    val () = $A.free<byte>(key)
    val () = $A.free<Int>(numbers)
    val () = $A.free<Int>(map)
    val () = lib_sort(sort)
    val () = lib_sort_label(sort)
    val () = set_apply(lib_state_get())
    val () = set_sliders()
    val () = lib_save()
    val () = lib_render()
  in
    if complete then _restored(restored)
    else if restored > 0 then _restored(restored)
    else _say("This file is not a Quire backup, or it is damaged.")
  end
end

(* The file input backup-file's file count, or the open promise of its first *)
fn _backup_file_count (): int = let
  val input_id = $A.alloc<byte>(11)
  val () = $A.write_text(input_id, 0, $A.text_lit("backup-file"), 11)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
  val count = $BF.file_count(id_bytes, 11)
  val () = release_bytes(id_frozen, id_bytes)
in count end

fn _backup_file_open (): $P.promise_pending(Int) = let
  val input_id = $A.alloc<byte>(11)
  val () = $A.write_text(input_id, 0, $A.text_lit("backup-file"), 11)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
  val pending = $BF.file_open_at(id_bytes, 11, 0)
  val () = release_bytes(id_frozen, id_bytes)
in pending end

(* Restores the backup picked in the file input backup-file *)
#pub fn backup_import (): void

implement backup_import () =
  if _backup_file_count() <= 0 then ()
  else $P.finish<Int>($P.vow(_backup_file_open()), llam(handle) => let
    (* the file is taken from the input: its choice is cleared *)
    val () = app_backup_input()
  in
    case+ $BF.file_claim(handle) of
    | ~$R.none() =>
      _say("The backup could not be read.")
    | ~$R.some(file) => let
        val file_size = $BF.file_size(file)
      in
        if file_size <= 0 then let
          val () = $BF.file_close(file)
        in _say("This file is not a Quire backup.") end
        else if file_size > BACKUP_MAX_BYTES then let
          val () = $BF.file_close(file)
        in _say("This file is too large to be a Quire backup.") end
        else (case+ piece_new(file_size) of
          | ~NoPiece() => let
              val () = $BF.file_close(file)
            in _say("The backup could not be read: there is not enough memory.") end
          | ~Piece(owner, out) => let
              val () = $BF.file_read(file, 0, out, file_size)
              val () = $BF.file_close(file)
              val () = _restore(out, file_size)
            in piece_free(owner, out) end)
      end
  end)

end (* #target wasm *)
