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
#use wasm.bats-packages.dev/file-input as FI

staload "ui.sats"
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
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* A backup's most bytes *)
#define BACKUP_MAX_BYTES 268435456

(* ============================================================
   The file, in chunks: count chunks of total bytes, the last one first
   ============================================================ *)

datavtype chunks(int, int) =
  | chunks_nil(0, 0) of ()
  | {count,total:nat}{owner,l:agz}{n:pos}{length:nat | length <= n}
    chunks_cons(count + 1, total + length) of
      (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int length, chunks(count, total))

fun chunks_free {count,total:nat} .<count>. (pieces: chunks(count, total)): void =
  case+ pieces of
  | ~chunks_nil() => ()
  | ~chunks_cons(owner, bytes, _, rest) => let val () = piece_free(owner, bytes) in chunks_free(rest) end

(* The chunks so far; whether each could be made *)
datavtype chunk_cell =
  | {count,total:nat | total <= BACKUP_MAX_BYTES} ChunkCell of (chunks(count, total), int total, bool)

val _chunks = ref<chunk_cell>(ChunkCell(chunks_nil(), 0, true))

fn _chunks_take (): chunk_cell = let
  var cell: chunk_cell = ChunkCell(chunks_nil(), 0, true)
  val () = ref_exch_elt<chunk_cell>(_chunks, cell)
in cell end

fn _chunks_put (cell: chunk_cell): void = let
  var current: chunk_cell = cell
  val () = ref_exch_elt<chunk_cell>(_chunks, current)
  val+ ~ChunkCell(pieces, _, _) = current
in chunks_free(pieces) end

(* Adds chunk after the chunks so far *)
fn _push (chunk: jchunk): void = let
  val+ ~ChunkCell(pieces, total, complete) = _chunks_take()
in
  case+ chunk of
  | ~JNone() => _chunks_put(ChunkCell(pieces, total, false))
  | ~JChunk(owner, bytes, length) =>
    if total + length > BACKUP_MAX_BYTES then let
      val () = piece_free(owner, bytes)
    in _chunks_put(ChunkCell(pieces, total, false)) end
    else _chunks_put(ChunkCell(chunks_cons(owner, bytes, length, pieces), total + length, complete))
end

(* out[start, start + length) := source[0, length) *)
fun _copy_at {l,source_loc:agz}{owner,source_owner:addr}{out_size,n:nat}{length:nat | length <= n}
  {start:nat | start + length <= out_size}{i:nat | i <= length} .<length - i>.
  (out: !$A.arrx(byte, l, out_size, owner), start: int start,
   source: !$A.arrx(byte, source_loc, n, source_owner), length: int length, i: int i): void =
  if i >= length then ()
  else let
    val () = $A.write_byte(out, start + i, $AR.low_byte(byte2int0($A.get<byte>(source, i))))
  in _copy_at(out, start, source, length, i + 1) end

(* The chunks, the last first, at out[0, total) in order *)
fun _join {l:agz}{owner:addr}{out_size:nat}{count,total:nat | total <= out_size} .<count>.
  (out: !$A.arrx(byte, l, out_size, owner), pieces: chunks(count, total), total: int total): void =
  case+ pieces of
  | ~chunks_nil() => ()
  | ~chunks_cons(owner, bytes, length, rest) => let
      val () = _copy_at(out, total - length, bytes, length, 0)
      val () = piece_free(owner, bytes)
    in _join(out, rest, total - length) end

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
  (out: !$A.arrx(byte, l, n, owner), position: int position, entries: days(count), first: bool)
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

(* The numbers of the collections a book is in (the bits of
   collections), from collection on, each after a comma but the first *)
fun _collection_numbers_json {l:agz}{owner:addr}{n:nat}{collection:nat | collection <= 8}
  {position:nat | position + 2 * (8 - collection) <= n} .<8 - collection>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, collection: int collection,
   collections: int, first: bool)
  : [stop:nat | stop <= position + 2 * (8 - collection)] int stop =
  if collection >= 8 then position
  else if $AR.band_int_int(collections, $AR.bsl_int_int(1, collection)) = 0 then
    _collection_numbers_json(out, position, collection + 1, collections, first)
  else if first then let
    val () = $A.write_byte(out, position, 48 + collection)
  in _collection_numbers_json(out, position + 1, collection + 1, collections, false) end
  else let
    val () = $A.write_byte(out, position, 44)
    val () = $A.write_byte(out, position + 1, 48 + collection)
  in _collection_numbers_json(out, position + 2, collection + 1, collections, false) end

fn _text_chunk {text_len:pos | text_len <= 16} (text: string text_len): jchunk =
  case+ piece_new(16) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => JChunk(owner, out, jw_lit(out, 0, text))

(* out[position + 1 + digit, position + 15) := key[1 + digit, 15) *)
fun _copy_id_digits {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position + 16 <= n}{digit:nat | digit <= 14}
  .<14 - digit>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, key: !$A.arr(byte, key_loc, 15), digit: int digit)
  : void =
  if digit >= 14 then ()
  else let
    val () = $A.write_byte(out, position + 1 + digit, $AR.low_byte(byte2int0($A.get<byte>(key, digit + 1))))
  in _copy_id_digits(out, position, key, digit + 1) end

(* The id's 14 hex digits, quoted, at out[position, position + 16) *)
fn _id_json {l:agz}{owner:addr}{n:nat}{position:nat | position + 16 <= n}
  (out: !$A.arrx(byte, l, n, owner), position: int position, id_high: int, id_low: int): int(position + 16) = let
  val key = lib_key(105, id_high, id_low)
  val () = $A.write_byte(out, position, 34)
  val () = _copy_id_digits(out, position, key, 0)
  val () = $A.free<byte>(key)
  val () = $A.write_byte(out, position + 15, 34)
in position + 16 end

(* Book book_index's members, up to its annotations' value; after
   another book's closing brace when it is not the first *)
fn _book_chunk {book_index:int} (book_index: int book_index, numbers: bnums, first: bool): jchunk =
  case+ piece_new(4096) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => let
      val @(title, title_len) = lib_text(book_index, 0)
      val @(author, author_len) = lib_text(book_index, 1)
      val next = (if first then jw_lit(out, 0, "{\"id\":") else jw_lit(out, 0, "},{\"id\":"))
        : [after:int | 6 <= after; after <= 8] int after
      val next = _id_json(out, next, numbers.id_high, numbers.id_low)
      val next = jw_lit(out, next, ",\"title\":")
      val next = jw_str(out, next, title, title_len)
      val next = jw_lit(out, next, ",\"author\":")
      val next = jw_str(out, next, author, author_len)
      val () = $A.free<byte>(title)
      val () = $A.free<byte>(author)
      val next = jw_lit(out, next, ",\"shelf\":")
      val next = jw_int(out, next, numbers.shelf)
      val next = jw_lit(out, next, ",\"added\":")
      val next = jw_int(out, next, numbers.added)
      val next = jw_lit(out, next, ",\"opened\":")
      val next = jw_int(out, next, numbers.opened)
      val next = jw_lit(out, next, ",\"chapter\":")
      val next = jw_int(out, next, numbers.chapter)
      val next = jw_lit(out, next, ",\"chapters\":")
      val next = jw_int(out, next, numbers.chapters)
      val next = jw_lit(out, next, ",\"page\":")
      val next = jw_int(out, next, numbers.page)
      val next = jw_lit(out, next, ",\"pages\":")
      val next = jw_int(out, next, numbers.pages)
      val next = jw_lit(out, next, ",\"anchor\":")
      val next = jw_int(out, next, numbers.anchor)
      val next = jw_lit(out, next, ",\"size\":")
      val next = jw_int(out, next, numbers.file_size)
      val next = jw_lit(out, next, ",\"done\":")
      val next = jw_int(out, next, numbers.done)
      val next = jw_lit(out, next, ",\"collections\":[")
      val next = _collection_numbers_json(out, next, 0, numbers.collections, true)
      val next = jw_lit(out, next, "]")
      val next = jw_lit(out, next, ",\"readMinutes\":")
      val next = jw_int(out, next, numbers.minutes_read)
      val next = jw_lit(out, next, ",\"readPages\":")
      val next = jw_int(out, next, numbers.pages_read)
      val next = jw_lit(out, next, ",\"finished\":")
      val next = jw_int(out, next, numbers.finished_at)
      val next = jw_lit(out, next, ",\"annotations\":")
    in JChunk(owner, out, next) end

(* Downloads the chunks as one file *)
fn _export_finish (): void = let
  val+ ~ChunkCell(pieces, total, complete) = _chunks_take()
in
  if ~complete then let
    val () = chunks_free(pieces)
  in _say("The backup could not be made: there is not enough memory.") end
  else if total <= 0 then chunks_free(pieces)
  else (case+ piece_new(total) of
    | ~NoPiece() => let
        val () = chunks_free(pieces)
      in _say("The backup could not be made: there is not enough memory.") end
    | ~Piece(owner, out) => let
        val () = _join(out, pieces, total)
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
      in piece_free(owner, $A.thaw<byte>(file_frozen)) end)
end

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
        $P.discard<int>($P.and_then<Int><int>($P.vow(pending), lam(handle) => let
          val () = (case+ take_content(handle) of
            | ~NoContentBytes() => _push(_text_chunk("[]"))
            | ~ContentBytes(content_owner, content, content_len) => let
                val annotations = annot_json(content, content_len)
                val () = piece_free(content_owner, content)
              in
                case+ annotations of
                | ~JNone() => _push(_text_chunk("[]"))
                | ~JChunk(annotations_owner, annotations_bytes, annotations_len) =>
                  _push(JChunk(annotations_owner, annotations_bytes, annotations_len))
              end)
          val () = _export_books(book_index + 1, count, false)
        in $P.ret<int>(0) end))
      end)

(* Downloads the backup, quire-backup.json *)
#pub fn backup_export (): void

implement backup_export () = let
  val () = _chunks_put(ChunkCell(chunks_nil(), 0, true))
  val () = _push(_settings_chunk())
  val () = _push(_log_chunk())
  val () = _push(dict_backup_json())
  val () = _push(_collections_chunk())
in _export_books(0, lib_count(), true) end

(* ============================================================
   A book's record kept for later: "o" and its id
   ============================================================ *)

(* A book's numbers as a backup is read: numbers[0, 3) its id
   (numbers[2] is 1 once read), numbers[3, 12) its shelf, dates and
   place (_number_slot), numbers[12] the collections it is in, as the
   library numbers them (-1 when the backup does not say), numbers[13,
   16) its minutes read, pages turned on them and when it was finished
   (each -1 when the backup does not say); numbers[16 + j] the library's
   number of the backup's collection j (-1 none) *)
#define NUMBER_SLOTS 24
#define COLLECTION_SLOTS 16

(* A book's numbers, before its members are read *)
fun _clear_numbers {numbers_loc:agz}{i:nat | i <= COLLECTION_SLOTS} .<COLLECTION_SLOTS - i>.
  (numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), i: int i): void =
  if i >= COLLECTION_SLOTS then ()
  else let
    val () = $A.set<Int>(numbers, i, (if i = 10 then ~1 else if i >= 12 then ~1 else 0))
  in _clear_numbers(numbers, i + 1) end

(* The record's numbers, in order: shelf, added, opened, chapter,
   chapters, page, pages, anchor, done, collections, minutes read, pages
   turned on them, finished. A record kept by an earlier version has the
   first 9 (RECORD_NUMBERS_FIRST) or 10 of them. *)
#define RECORD_NUMBERS 13
#define RECORD_NUMBERS_FIRST 9

fun _orphan_write {record_loc,numbers_loc:agz}{i:nat | i <= RECORD_NUMBERS} .<RECORD_NUMBERS - i>.
  (record: !$A.arr(byte, record_loc, 4 + 4 * RECORD_NUMBERS),
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), i: int i): void =
  if i >= RECORD_NUMBERS then ()
  else let
    val () = $A.write_i32(record, 4 + 4 * i, $A.get<Int>(numbers, 3 + i))
  in _orphan_write(record, numbers, i + 1) end

(* numbers[3 + i, 3 + count) := the count numbers at
   record[4 + 4 * i, 4 + 4 * count) *)
fun _orphan_read_numbers {record_loc,numbers_loc:agz}{count:nat | count <= RECORD_NUMBERS}
  {n:int | n >= 4 + 4 * count}{i:nat | i <= count} .<count - i>.
  (record: !$A.arr(byte, record_loc, n), count: int count,
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), i: int i): void =
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
  (record: !$A.arr(byte, record_loc, n), n: int n, numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS)): void =
  if n >= 4 + 4 * RECORD_NUMBERS then _orphan_read_numbers(record, RECORD_NUMBERS, numbers, 0)
  else if n >= 4 + 4 * 10 then _orphan_read_numbers(record, 10, numbers, 0)
  else _orphan_read_numbers(record, RECORD_NUMBERS_FIRST, numbers, 0)

(* Stores numbers[3, 16) (a book's numbers from a backup) under its "o"
   key *)
fn _orphan_put {numbers_loc:agz}
  (id_high: int, id_low: int, numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS)): void = let
  val record = $A.alloc<byte>(4 + 4 * RECORD_NUMBERS)
  val () = $A.write_text(record, 0, $A.text_lit("QO1"), 3)
  val () = $A.write_byte(record, 3, 10)
  val () = _orphan_write(record, numbers, 0)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(111, id_high, id_low))
  val () = $P.discard<Int>($IDB.idb_put(key_bytes, 15, record_bytes, 4 + 4 * RECORD_NUMBERS))
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* value in [low, high], or fallback *)
fn _in_range (value: Int, low: Int, high: Int, fallback: Int): Int =
  if value < low then fallback else if value > high then fallback else value

(* Library book book_index's numbers set from numbers[3, 12) *)
fn _apply_numbers {book_index:int}{numbers_loc:agz}
  (book_index: int book_index, numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS)): void = let
  val shelf = _in_range($A.get<Int>(numbers, 3), 0, 2, 0)
  val added = $A.get<Int>(numbers, 4)
  val opened = _in_range($A.get<Int>(numbers, 5), 0, 2147483647, 0)
  val chapter = _in_range($A.get<Int>(numbers, 6), 0, 2147483647, 0)
  val chapters = _in_range($A.get<Int>(numbers, 7), 0, 2147483647, 0)
  val page = _in_range($A.get<Int>(numbers, 8), 0, 2147483647, 0)
  val pages = _in_range($A.get<Int>(numbers, 9), 0, 2147483647, 0)
  val anchor = _in_range($A.get<Int>(numbers, 10), ~1, 2147483647, ~1)
  val done = _in_range($A.get<Int>(numbers, 11), 0, 1, 0)
  (* the collections, when the backup says which: of those there are *)
  val collections = $A.get<Int>(numbers, 12)
  val collections = (if collections >= 0
    then g1ofg0($AR.band_int_int(collections, $AR.bsl_int_int(1, lib_coll_count()) - 1)) else ~1): Int
  (* its reading statistics, when the backup has them *)
  val minutes = _in_range($A.get<Int>(numbers, 13), ~1, 2147483647, ~1)
  val pages_turned = _in_range($A.get<Int>(numbers, 14), ~1, 2147483647, ~1)
  val finished = _in_range($A.get<Int>(numbers, 15), ~1, 2147483647, ~1)
in
  lib_update(book_index, lam(before) => @{
    key = before.key, id_high = before.id_high, id_low = before.id_low, shelf = shelf,
    added = (if added > 0 then added else before.added), opened = opened,
    chapter = chapter, chapters = chapters, page = page, pages = pages, anchor = anchor,
    file_size = before.file_size, cover = before.cover, done = done, series_number = before.series_number,
    collections = (if collections >= 0 then collections else before.collections),
    minutes_read = (if minutes >= 0 then minutes else before.minutes_read),
    pages_read = (if pages_turned >= 0 then pages_turned else before.pages_read),
    finished_at = (if finished >= 0 then finished else before.finished_at) })
end

(* Library book id_high, id_low (when it is there) takes the numbers
   numbers[3, 12) *)
fn _claim_apply {numbers_loc:agz} (id_high: Int, id_low: Int, numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS)): void = let
  val book_index = lib_find(id_high, id_low)
in
  if book_index >= 0 then let
    val () = _apply_numbers(book_index, numbers)
    val () = lib_save()
  in lib_render() end
  else ()
end

(* A book just imported takes the record a backup kept for it *)
#pub fn backup_claim (id_high: Int, id_low: Int): void

implement backup_claim (id_high, id_low) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(111, id_high, id_low))
  val pending = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(pending), lam(handle) =>
    case+ take_blob(handle) of
    | ~NoBlobBytes() => $P.ret<int>(0)
    | ~BlobBytes(record, n) =>
      if n < 4 + 4 * RECORD_NUMBERS_FIRST then let val () = $A.free<byte>(record) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(record, 1)) <> 79 then let val () = $A.free<byte>(record) in $P.ret<int>(0) end
      else let
        val numbers = $A.alloc<Int>(NUMBER_SLOTS)
        val () = _clear_numbers(numbers, 0)
        val () = _orphan_read(record, n, numbers)
        val () = $A.free<byte>(record)
        val () = _claim_apply(id_high, id_low, numbers)
        val () = $A.free<Int>(numbers)
        val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(111, id_high, id_low))
        val () = $P.discard<Int>($IDB.idb_delete(key_bytes, 15))
        val () = release_bytes(key_frozen, key_bytes)
      in $P.ret<int>(0) end))
end

(* ============================================================
   Restore
   ============================================================ *)

(* The value of hex digit character, or -1 *)
fn _hex_value (character: Int): Int =
  if character >= 48 then (if character <= 57 then character - 48
    else if character >= 97 then (if character <= 102 then character - 87 else ~1)
    else if character >= 65 then (if character <= 70 then character - 55 else ~1) else ~1)
  else ~1

(* The 7 hex digits key[start, start + 7), or -1 *)
fun _seven_hex {key_loc:agz}{start:nat | start <= 16}{i:nat | i <= 7; start + 7 <= 16} .<7 - i>.
  (key: !$A.arr(byte, key_loc, 16), start: int start, i: int i, value: Int): Int =
  if i >= 7 then value
  else let
    val digit = _hex_value($AR.low_byte(byte2int0($A.get<byte>(key, start + i))))
  in if digit < 0 then ~1 else _seven_hex(key, start, i + 1, value * 16 + digit) end

(* The number a book member's key names, its slot in numbers: 3 shelf,
   4 added, 5 opened, 6 chapter, 7 chapters, 8 page, 9 pages, 10 anchor,
   11 done, 13 readMinutes, 14 readPages, 15 finished; -1 for any other *)
fn _number_slot {key_loc:agz}{key_len:nat | key_len <= 16} (key: !$A.arr(byte, key_loc, 16), key_len: int key_len)
  : [slot:int | ~1 <= slot; slot < COLLECTION_SLOTS; slot <> 12] int slot =
  if jr_key_is(key, key_len, "shelf") then 3
  else if jr_key_is(key, key_len, "added") then 4
  else if jr_key_is(key, key_len, "opened") then 5
  else if jr_key_is(key, key_len, "chapter") then 6
  else if jr_key_is(key, key_len, "chapters") then 7
  else if jr_key_is(key, key_len, "page") then 8
  else if jr_key_is(key, key_len, "pages") then 9
  else if jr_key_is(key, key_len, "anchor") then 10
  else if jr_key_is(key, key_len, "done") then 11
  else if jr_key_is(key, key_len, "readMinutes") then 13
  else if jr_key_is(key, key_len, "readPages") then 14
  else if jr_key_is(key, key_len, "finished") then 15
  else ~1

(* A number (or true or false) at value_start, kept in numbers[slot] *)
fn _number_at {l,numbers_loc:agz}{owner:addr}{n:nat}{value_start:nat | value_start <= n}{slot:nat | slot < COLLECTION_SLOTS}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, value_start: int value_start,
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), slot: int slot)
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

(* The id member's value at value_start: numbers[0], numbers[1] and
   numbers[2] (1 when read) *)
fn _id_at {l,key_loc,numbers_loc:agz}{owner:addr}{n:nat}{value_start:nat | value_start < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, value_start: int value_start,
   key: !$A.arr(byte, key_loc, 16), numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS))
  : [stop:int | value_start < stop; stop <= n] int stop = let
  val @(found, id_len, stop) = jr_str(buf, n, value_start, key, 16)
in
  if ~found then stop
  else if id_len <> 14 then stop
  else let
    val id_high = _seven_hex(key, 0, 0, 0)
    val id_low = _seven_hex(key, 7, 0, 0)
  in
    if id_high < 0 then stop
    else if id_low < 0 then stop
    else let
      val () = $A.set<Int>(numbers, 0, id_high)
      val () = $A.set<Int>(numbers, 1, id_low)
      val () = $A.set<Int>(numbers, 2, 1)
    in stop end
  end
end

(* The collections of a book's array from position, to its closing
   bracket: mask with each one's bit, as the library numbers them
   (numbers[COLLECTION_SLOTS + j] for the backup's collection j) *)
fun _collection_items {l,numbers_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), mask: int)
  : [stop:int | position <= stop; stop <= n] @(bool, int, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, mask, n)
  else if jr_is(buf, n, next, 93) then @(true, mask, next + 1)
  else if jr_is(buf, n, next, 44) then _collection_items(buf, n, next + 1, numbers, mask)
  else let
    val @(is_int, collection, stop) = jr_int(buf, n, next)
  in
    if ~is_int then @(false, mask, stop)
    else if stop <= next then @(false, mask, stop)
    else let
      val library_number = (if collection >= 0 then
        (if collection < 8 then $A.get<Int>(numbers, COLLECTION_SLOTS + collection) else ~1) else ~1): Int
      val mask = (if library_number >= 0 then
        (if library_number < 8 then $AR.bor_int_int(mask, $AR.bsl_int_int(1, library_number)) else mask)
        else mask): int
    in _collection_items(buf, n, stop, numbers, mask) end
  end
end

(* The backup's collections from position, to their array's closing
   bracket, from its collection-th: each found in the library by its
   name, or made there, and its number there kept in
   numbers[COLLECTION_SLOTS + collection] *)
fun _collection_names_at {l,numbers_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{collection:nat}
  .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), collection: int collection)
  : [stop:int | position <= stop; stop <= n] @(bool, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, n)
  else if jr_is(buf, n, next, 93) then @(true, next + 1)
  else if jr_is(buf, n, next, 44) then _collection_names_at(buf, n, next + 1, numbers, collection)
  else let
    val name = $A.alloc<byte>(256)
    val @(found, name_len, stop) = jr_str(buf, n, next, name, 256)
  in
    if ~found then let val () = $A.free<byte>(name) in @(false, stop) end
    else let
      val library_number = lib_coll_find_or_add(name, name_len)
      val () = (if collection < 8 then $A.set<Int>(numbers, COLLECTION_SLOTS + collection, g1ofg0(library_number)) else ())
    in _collection_names_at(buf, n, stop, numbers, collection + 1) end
  end
end

(* No collection of the backup's known yet *)
fun _unmapped {numbers_loc:agz}{collection:nat | collection <= 8} .<8 - collection>.
  (numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), collection: int collection): void =
  if collection >= 8 then ()
  else let
    val () = $A.set<Int>(numbers, COLLECTION_SLOTS + collection, ~1)
  in _unmapped(numbers, collection + 1) end

(* A book object's members from position, to its closing brace: its
   numbers into numbers, and where its annotations' array is (-1 none) *)
fun _book_members {l,key_loc,numbers_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  {annotations_start:int | ~1 <= annotations_start; annotations_start <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), annotations: int annotations_start)
  : [stop:int | position <= stop; stop <= n][found_at:int | ~1 <= found_at; found_at <= n]
    @(bool, int found_at, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, annotations, n)
  else if jr_is(buf, n, next, 125) then @(true, annotations, next + 1)
  else if jr_is(buf, n, next, 44) then _book_members(buf, n, next + 1, key, numbers, annotations)
  else let
    val @(found, key_len, value_start) = jr_key(buf, n, next, key, 16)
  in
    if ~found then @(false, annotations, value_start)
    else if value_start >= n then @(false, annotations, value_start)
    else if jr_key_is(key, key_len, "id") then
      _book_members(buf, n, _id_at(buf, n, value_start, key, numbers), key, numbers, annotations)
    else if jr_key_is(key, key_len, "annotations") then
      _book_members(buf, n, jr_skip(buf, n, value_start), key, numbers, value_start)
    else if jr_key_is(key, key_len, "collections") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, mask, stop) = _collection_items(buf, n, value_start + 1, numbers, 0)
         val () = $A.set<Int>(numbers, 12, g1ofg0(mask))
       in if closed then _book_members(buf, n, stop, key, numbers, annotations) else @(false, annotations, stop) end
       else _book_members(buf, n, jr_skip(buf, n, value_start), key, numbers, annotations))
    else let
      val slot = _number_slot(key, key_len)
    in
      if slot >= 0 then _book_members(buf, n, _number_at(buf, n, value_start, numbers, slot), key, numbers, annotations)
      else _book_members(buf, n, jr_skip(buf, n, value_start), key, numbers, annotations)
    end
  end
end

(* Puts a book's state back from numbers: into the library when the
   book is there, else kept under its "o" key; its annotations from the
   array at annotations *)
fn _restore_book {l,numbers_loc:agz}{owner:addr}{n:nat}{annotations_start:int | ~1 <= annotations_start; annotations_start <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS),
   annotations: int annotations_start): bool =
  if $A.get<Int>(numbers, 2) <> 1 then false
  else let
    val id_high = $A.get<Int>(numbers, 0)
    val id_low = $A.get<Int>(numbers, 1)
    val book_index = lib_find(id_high, id_low)
    val () = (if book_index >= 0 then _apply_numbers(book_index, numbers) else _orphan_put(id_high, id_low, numbers))
    val () = (if annotations >= 0 then let
        val _ = annot_json_store(buf, n, annotations, id_high, id_low)
      in () end else ())
  in true end

(* The books of the array's items from position, to its closing
   bracket, put back one by one; how many *)
fun _book_items {l,key_loc,numbers_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), restored: int)
  : [stop:int | position <= stop; stop <= n] @(bool, int, int stop) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, restored, n)
  else if jr_is(buf, n, next, 93) then @(true, restored, next + 1)
  else if jr_is(buf, n, next, 44) then _book_items(buf, n, next + 1, key, numbers, restored)
  else if jr_is(buf, n, next, 123) then let
    val () = _clear_numbers(numbers, 0)
    val @(closed, annotations, stop) = _book_members(buf, n, next + 1, key, numbers, ~1)
  in
    if ~closed then @(false, restored, stop)
    else if _restore_book(buf, n, numbers, annotations) then _book_items(buf, n, stop, key, numbers, restored + 1)
    else _book_items(buf, n, stop, key, numbers, restored)
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
fun _top_members {l,key_loc,numbers_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   numbers: !$A.arr(Int, numbers_loc, NUMBER_SLOTS), quire: bool, books: int, sort: int)
  : @(bool, int, int) = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then @(false, books, sort)
  else if jr_is(buf, n, next, 125) then @(quire, books, sort)
  else if jr_is(buf, n, next, 44) then _top_members(buf, n, next + 1, key, numbers, quire, books, sort)
  else let
    val @(found, key_len, value_start) = jr_key(buf, n, next, key, 16)
  in
    if ~found then @(false, books, sort)
    else if value_start >= n then @(false, books, sort)
    else if jr_key_is(key, key_len, "quire") then let
      val @(is_int, version, stop) = jr_int(buf, n, value_start)
    in
      if is_int then _top_members(buf, n, stop, key, numbers, version = 1, books, sort)
      else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, false, books, sort)
    end
    else if ~quire then @(false, books, sort)
    else if jr_key_is(key, key_len, "settings") then
      (if jr_is(buf, n, value_start, 123) then let
         val @(closed, new_sort, stop) = _settings_members(buf, n, value_start + 1, key, sort)
       in
         if closed then _top_members(buf, n, stop, key, numbers, quire, books, new_sort)
         else @(false, books, sort)
       end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, quire, books, sort))
    else if jr_key_is(key, key_len, "readingLog") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, stop) = _log_at(buf, n, value_start + 1)
         val () = stats_restored()
       in if closed then _top_members(buf, n, stop, key, numbers, quire, books, sort) else @(false, books, sort) end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, quire, books, sort))
    else if jr_key_is(key, key_len, "collections") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, stop) = _collection_names_at(buf, n, value_start + 1, numbers, 0)
       in if closed then _top_members(buf, n, stop, key, numbers, quire, books, sort) else @(false, books, sort) end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, quire, books, sort))
    else if jr_key_is(key, key_len, "books") then
      (if jr_is(buf, n, value_start, 91) then let
         val @(closed, restored, stop) = _book_items(buf, n, value_start + 1, key, numbers, books)
       in
         if closed then _top_members(buf, n, stop, key, numbers, quire, restored, sort)
         else @(false, restored, sort)
       end
       else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, quire, books, sort))
    else _top_members(buf, n, jr_skip(buf, n, value_start), key, numbers, quire, books, sort)
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
    val numbers = $A.alloc<Int>(NUMBER_SLOTS)
    val () = _unmapped(numbers, 0)
    val @(complete, restored, sort) = _top_members(buf, n, start + 1, key, numbers, false, 0, lib_sort_get())
    val () = $A.free<byte>(key)
    val () = $A.free<Int>(numbers)
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
  else $P.discard<int>($P.and_then<Int><int>($P.vow(_backup_file_open()), lam(handle) => let
    (* the file is taken from the input: its choice is cleared *)
    val () = app_backup_input()
  in
    case+ $FI.claim(handle) of
    | ~$R.none() => let
        val () = _say("The backup could not be read.")
      in $P.ret<int>(0) end
    | ~$R.some(file) => let
        val file_size = $FI.size(file)
      in
        if file_size <= 0 then let
          val () = $FI.close(file)
          val () = _say("This file is not a Quire backup.")
        in $P.ret<int>(0) end
        else if file_size > BACKUP_MAX_BYTES then let
          val () = $FI.close(file)
          val () = _say("This file is too large to be a Quire backup.")
        in $P.ret<int>(0) end
        else (case+ piece_new(file_size) of
          | ~NoPiece() => let
              val () = $FI.close(file)
              val () = _say("The backup could not be read: there is not enough memory.")
            in $P.ret<int>(0) end
          | ~Piece(owner, out) => let
              val () = $FI.file_read(file, 0, out, file_size)
              val () = $FI.close(file)
              val () = _restore(out, file_size)
              val () = piece_free(owner, out)
            in $P.ret<int>(0) end)
      end
  end))

end (* #target wasm *)
