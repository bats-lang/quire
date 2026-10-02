(* reader -- Chapter rendering, pagination, navigation *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use xml-tree as X
#use wasm.bats-packages.dev/dom as D
#use widget as W

staload "epub_xml.sats"
staload "book.sats"
staload "pages.sats"
staload "paths.sats"
staload "ui.sats"
staload "notice.sats"
staload "layer.sats"
staload "library.sats"
staload "import.sats"
staload "toc.sats"
staload "settings.sats"
staload "stats.sats"
staload "annot.sats"
staload "entity.sats"
staload "mem.sats"
staload "clock.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload "storage.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload SC = "wasm.bats-packages.dev/bridge/src/scroll.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload SP = "wasm.bats-packages.dev/bridge/src/speech.sats"

fn _apply_diff_list(diffs: $W.diff_list): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.apply_list(doc, diffs)
  val () = $D.destroy(doc)
in end

fn _apply_diff(diff: $W.diff): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.apply(doc, diff)
  val () = $D.destroy(doc)
in end

(* ============================================================
   Pagination helpers
   ============================================================ *)

(* Stash slots: 21=current_page (0-indexed), 22=total_pages, 23=current_chapter (1-indexed), 24=total_chapters *)

(* text's bytes at buf[at, at + text_len) *)
fun _put_string {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (buf: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.set<byte>(buf, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_string(buf, at, text, text_len, i + 1) end

fn _put {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}
  (buf: !$A.arr(byte, l, n), at: int at, text: string text_len): int(at + text_len) =
  _put_string(buf, at, text, g1u2i(string1_length(text)), 0)

(* The text of buf[0, text_len); frees buf *)
fn _prefix_text {l:agz}{n:pos | n <= 1048576}{text_len:pos | text_len <= n}
  (buf: $A.arr(byte, l, n), n: int n, text_len: int text_len): $A.text(text_len) = let
  val exact = $A.alloc<byte>(text_len)
  val buf = $S.copy_arr_region(buf, 0, n, exact, text_len, text_len)
  val () = $A.free<byte>(buf)
  val text = arr_to_text(exact, text_len)
  val () = $A.free<byte>(exact)
in text end

(* id_prefix, then number's decimal digits zero-padded to at least width:
   an element id that stays distinct for every number *)
fn _number_id {prefix_len:pos | prefix_len <= 3}{number:nat}{width:int | width == 2 || width == 3}
  (id_prefix: string prefix_len, number: int number, width: int width): [l:agz][id_len:pos | id_len <= 16] @($A.arr(byte, l, id_len), int id_len) = let
  (* zero_count zeros at buf[at, at + zero_count) *)
  fun zeros {l:agz}{at,zero_count:nat | at + zero_count <= 16} .<zero_count>.
    (buf: !$A.arr(byte, l, 16), at: int at, zero_count: int zero_count): int(at + zero_count) =
    if zero_count = 0 then at
    else let val () = $A.set<byte>(buf, at, $A.int2byte(48)) in zeros(buf, at + 1, zero_count - 1) end
  val zero_count = (if number < 10 then width - 1 else if number < 100 then width - 2 else 0): [zero_count:nat | zero_count <= 2] int zero_count
  val buf = $A.alloc<byte>(16)
  val offset = _put(buf, 0, id_prefix)
  val offset = zeros(buf, offset, zero_count)
  val offset = $S.int_to_str(buf, offset, 16, number)
  val exact = $A.alloc<byte>(offset)
  val buf = $S.copy_arr_region(buf, 0, 16, exact, offset, offset)
  val () = $A.free<byte>(buf)
in @(exact, offset) end

(* The text of the element whose id is the literal id: buf[0, text_len), copied
   from the buffer (no text or diff is built, so nothing is allocated);
   frees buf *)
fn _set_text_of {id_len:pos | id_len < 256}{l:agz}{n:pos}{text_len:nat | text_len <= n; text_len < 65536}
  (id: string id_len, buf: $A.arr(byte, l, n), text_len: int text_len): void = let
  val id_len = g1u2i(string1_length(id))
  val id_buf = $A.alloc<byte>(id_len)
  val () = $A.write_text(id_buf, 0, $A.text_lit(id), id_len)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id_buf)
  val @(text_frozen, text_bytes) = $A.freeze<byte>(buf)
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_text(doc, id_bytes, id_len, text_bytes, 0, text_len)
  val () = $D.destroy(doc)
  val () = release_bytes(text_frozen, text_bytes)
in release_bytes(id_frozen, id_bytes) end

(* ============================================================
   Reading speed: minutes per page, learned from the pages turned on
   ============================================================ *)

(* The minutes and the pages counted: a page turned on within 3 minutes
   of the one before counts, with the minutes between them; a longer
   pause does not *)
val _speed_minutes = ref<Int>(0)
val _speed_pages = ref<Int>(0)
(* The minute of the last page turned on, or -1 *)
val _speed_last_minute = ref<Int>(~1)
(* The open book's minutes and pages read since its place was last kept *)
val _book_minutes = ref<Int>(0)
val _book_pages = ref<Int>(0)

(* Whether the speed is known: 10 pages over 2 minutes at least *)
fn _speed_known (): bool = !_speed_pages >= 10 && !_speed_minutes >= 2

(* The minutes page_count pages take, at the speed learned; -1 when it is not
   known *)
fn _minutes_for_pages (page_count: Int): Int = let
  val minutes = !_speed_minutes
  val pages = !_speed_pages
in
  if ~_speed_known() then ~1
  else if page_count <= 0 then 0
  else if pages <= 0 then ~1
  (* page_count * minutes fits an int: the minutes counted are at most 3 a page, and
     the pages at most 2000 *)
  else if page_count > 100000 then ~1
  else if minutes > 6000 then ~1
  else page_count * minutes / pages
end

fn _speed_key (): [l:agz] $A.arr(byte, l, 3) = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("spd"), 3)
  in key end

(* Stores the speed under "spd": the minutes and the pages, 4 bytes each *)
fn _speed_save (): void = let
  val data = $A.alloc<byte>(8)
  val () = $A.write_i32(data, 0, !_speed_minutes)
  val () = $A.write_i32(data, 4, !_speed_pages)
  val @(data_frozen, data_bytes) = $A.freeze<byte>(data)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_speed_key())
  (* ignored: a speed not stored only starts the time-left estimates
     over; never stored over one that could not be read (#174) *)
  val () = (if storage_savable(ReadingSpeedRecord()) then $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 3, data_bytes, 8), llam(_) => ()) else ())
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(data_frozen, data_bytes) end

(* A page turned on: counted, and every 10 pages kept. Past 2000 pages
   both halve, so the speed follows the reader's lately *)
fn _speed_turn (): void = let
  val now = $TM.epoch_minutes()
  val last = !_speed_last_minute
  val () = !_speed_last_minute := now
in
  if last < 0 then ()
  else if now < last then ()
  else if now - last > 3 then ()
  else let
    val () = !_speed_minutes := !_speed_minutes + (now - last)
    val () = !_speed_pages := !_speed_pages + 1
    (* the reading log's day, and the open book's time, kept with its
       place (_record_position) *)
    val () = stats_add(now - last)
    val () = !_book_minutes := !_book_minutes + (now - last)
    val () = !_book_pages := !_book_pages + 1
    val () = (if !_speed_pages > 2000 then let
        val () = !_speed_minutes := !_speed_minutes / 2
      in !_speed_pages := !_speed_pages / 2 end else ())
  in if !_speed_pages - (!_speed_pages / 10) * 10 = 0 then _speed_save() else () end
end

(* Whether the chapter is scrolled down (the Layout setting), not turned
   across in pages. Scrolled, a page is a screenful: a turn scrolls one
   down or up, and the reader's place, its anchor and the arenas' window
   count screenfuls as they count pages *)
fn _scrolled (): bool = set_flow_get() = 1

(* The page's height, as it was last measured *)
val _page_height = ref<int>(0)

(* Whether the book reads right to left *)
val _right_to_left = ref<bool>(false)

(* How far a turn scrolls: the page's height, less its paddings (84
   px) and a line's overlap, so no line is lost between screens *)
fn _step (): [step:pos] int step = let
  val height = g1ofg0(!_page_height)
in if height > 240 then height - 120 else 120 end

(* A content node of the chapter, and how far below the
   page's top it is when the chapter is scrolled to its top: where it is
   now says how far the chapter is scrolled, which the page does not
   tell *)
val _probe = ref<Int>(~1)
val _probe_offset = ref<Int>(0)

(* The minutes, as "<1 min", "12 min" or "3 h 20 min", at buf[at, end_at) *)
fn _put_duration {l:agz}{n:pos}{at:nat | at + 30 <= n}
  (buf: !$A.arr(byte, l, n), at: int at, n: int n, minutes: Int): [end_at:nat | end_at <= at + 30] int end_at =
  if minutes < 1 then _put(buf, at, "<1 min")
  else if minutes < 60 then let
    val offset = $S.int_to_str(buf, at, n, minutes)
  in _put(buf, offset, " min") end
  else let
    val offset = $S.int_to_str(buf, at, n, minutes / 60)
    val offset = _put(buf, offset, " h ")
    val offset = $S.int_to_str(buf, offset, n, minutes - (minutes / 60) * 60)
  in _put(buf, offset, " min") end

(* Where a page is in the book, by the chapters' sizes, in thousandths *)

fn _clamp1000 (value: Int): [clamped:nat | clamped <= 1000] int clamped =
  if value <= 0 then 0 else if value >= 1000 then 1000 else value

(* The thousandth of the book at a size position, of its total *)
fn _thousandth (position: Int, total: Int): [thousandth:nat | thousandth <= 1000] int thousandth =
  if total <= 0 then 0
  (* position * 1000 fits an int *)
  else if total < 2000000 then _clamp1000(position * 1000 / total)
  else _clamp1000(position / (total / 1000))

(* The size position of a thousandth of total *)
fn _of_thousandth (thousandth: Int, total: Int): Int =
  if total < 2000000 then total * thousandth / 1000 else (total / 1000) * thousandth

(* Where a page of page_count in a chapter (from 0) is in the book *)
fn _permille (chapter: Int, page: Int, page_count: Int): [thousandth:nat | thousandth <= 1000] int thousandth = let
  val @(size_before, chapter_size, book_size) = book_weights(book_serial(), chapter)
  val page_thousandth = (if page_count > 0 then page * 1000 / page_count else 0): Int
in _thousandth(size_before + _of_thousandth(page_thousandth, chapter_size), book_size) end

(* The pages of the rest of the book after a chapter (chapter_index), in
   its pages (page_count of them), by the chapters' sizes; -1 when that is not
   known *)
fn _rest_pages (chapter_index: Int, page_count: Int): Int = let
  val @(size_before, chapter_size, book_size) = book_weights(book_serial(), chapter_index)
  val size_after = book_size - size_before - chapter_size
in
  if chapter_size <= 0 then ~1 else if size_after <= 0 then 0
  (* size_after * page_count / chapter_size, in two steps so it fits *)
  else if size_after / chapter_size > 10000 then ~1
  else (size_after / chapter_size) * page_count + (size_after - (size_after / chapter_size) * chapter_size) * page_count / chapter_size
end

(* The footer's readouts (the setting rd), each naming its scope: 0 the
   pages left in the chapter, 1 the page of the chapter's pages, 2 the
   chapter of the book's, 3 the time left in the chapter, 4 in the book.
   The times are there only once the reading speed is known. *)
fn _readout_ok (readout: int, page: Int, page_count: Int, chapter_index: Int): bool =
  if readout = 3 then _speed_known()
  else if readout = 4 then (if _speed_known() then _rest_pages(chapter_index, page_count) >= 0 else false)
  else readout >= 0 && readout <= 2

(* The readout shown: the one chosen, or pages left when it cannot be *)
fn _readout_shown (page: Int, page_count: Int, chapter_index: Int): [readout:nat | readout <= 4] int readout = let
  val readout = set_rd_get()
in if _readout_ok(readout, page, page_count, chapter_index) then readout else 0 end

(* The readout after the one given: the next one that can be shown *)
fn _readout_after {readout:nat | readout <= 4} (readout: int readout, page: Int, page_count: Int, chapter_index: Int): [next_readout:nat | next_readout <= 4] int next_readout = let
  val next = (if readout < 4 then readout + 1 else 0): [next:nat | next <= 4] int next
in
  if _readout_ok(next, page, page_count, chapter_index) then next
  else let
    val after_next = (if next < 4 then next + 1 else 0): [after_next:nat | after_next <= 4] int after_next
  in if _readout_ok(after_next, page, page_count, chapter_index) then after_next else 0 end
end

(* " · " (5 bytes, from a no-break space, 0xC2 0xA0, since a space
   would be dropped at the start of its box, and the middle dot, 0xC2
   0xB7) at buf[at, at + 5) *)
fn _put_separator {l:agz}{n:pos}{at:nat | at + 5 <= n}
  (buf: !$A.arr(byte, l, n), at: int at): int(at + 5) = let
  val () = $A.set<byte>(buf, at, $A.int2byte(194))
  val () = $A.set<byte>(buf, at + 1, $A.int2byte(160))
  val () = $A.set<byte>(buf, at + 2, $A.int2byte(194))
  val () = $A.set<byte>(buf, at + 3, $A.int2byte(183))
in _put(buf, at + 4, " ") end

(* Measures element id: its box to the measure slots *)
fn _measure_literal {id_len:pos | id_len < 256} (id: string id_len): void = let
  val id_len = g1u2i(string1_length(id))
  val id_buf = $A.alloc<byte>(id_len)
  val () = $A.write_text(id_buf, 0, $A.text_lit(id), id_len)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id_buf)
  val _ = $DR.measure(id_bytes, id_len)
in release_bytes(id_frozen, id_bytes) end

(* Whether a screen shows two columns, a spread: the probe the
   typography's style shows then (settings.bats, _put_cols) *)
fn _spread (): bool = let
  val () = _measure_literal("spread-probe")
in $DR.get_measure_w() > 0 end

(* "13 of 75 in chapter", for a page (from 0) of page_count, at buf[at, end_at); for a
   spread, both of its pages: "25–26 of 150 in chapter" *)
fn _put_page_of {l:agz}{at:nat | at + 55 <= 96}
  (buf: !$A.arr(byte, l, 96), at: int at, page: Int, page_count: Int): [end_at:nat | end_at <= at + 55] int end_at =
  if _spread() then let
    val offset = $S.int_to_str(buf, at, 96, 2 * page + 1)
    (* an en dash *)
    val offset = _put(buf, offset, "\xE2\x80\x93")
    val offset = $S.int_to_str(buf, offset, 96, 2 * page + 2)
    val offset = _put(buf, offset, " of ")
    val offset = $S.int_to_str(buf, offset, 96, 2 * page_count)
  in _put(buf, offset, " in chapter") end
  else let
    val offset = $S.int_to_str(buf, at, 96, page + 1)
    val offset = _put(buf, offset, " of ")
    val offset = $S.int_to_str(buf, offset, 96, page_count)
  in _put(buf, offset, " in chapter") end

(* "34% of chapter", for a page (from 0) of page_count, at buf[at, end_at): scrolled,
   where the screenful shown is in the chapter *)
fn _put_chapter_percent {l:agz}{at:nat | at + 40 <= 96}
  (buf: !$A.arr(byte, l, 96), at: int at, page: Int, page_count: Int): [end_at:nat | end_at <= at + 26] int end_at = let
  val percent = (if page_count <= 1 then 100 else if page <= 0 then 0 else if page >= page_count - 1 then 100 else page * 100 / (page_count - 1)): Int
  val offset = $S.int_to_str(buf, at, 96, percent)
in _put(buf, offset, "% of chapter") end

(* The readout given, for a page of page_count in a chapter (from 1; 0 when none is
   known) of chapter_count, at buf[at, end_at) *)
fn _put_readout {l:agz}{at:nat | at + 70 <= 96}{readout:nat | readout <= 4}
  (buf: !$A.arr(byte, l, 96), at: int at, readout: int readout, page: Int, page_count: Int, chapter: Int, chapter_count: Int)
  : [end_at:nat | end_at <= at + 70] int end_at = let
  val chapter_index = (if chapter > 0 then chapter - 1 else 0): Int
  (* the screens after the one shown (the reading speed is by screens) *)
  val left = (if page_count > page + 1 then page_count - page - 1 else 0): Int
in
  (* scrolled, the chapter's pages are its screenfuls: where the one
     shown is says more than how many there are *)
  if (if readout <= 1 then _scrolled() else false) then _put_chapter_percent(buf, at, page, page_count)
  else if readout = 1 then (if _spread() then _put_page_of(buf, _put(buf, at, "pages "), page, page_count)
    else _put_page_of(buf, _put(buf, at, "page "), page, page_count))
  else if readout = 2 then let
    (* by the contents' top-level entries; by the spine's items when
       the contents have none *)
    val @(chapter_number, chapter_total) = toc_chapter_of(chapter_index)
    val @(chapter_number, chapter_total) = (if chapter_total > 0 then @(chapter_number, chapter_total) else @(chapter, chapter_count)): @(int, int)
    val chapter_number = g1ofg0(chapter_number)
    val chapter_total = g1ofg0(chapter_total)
  in
    if chapter_number <= 0 then let
      val offset = _put(buf, at, "before chapter 1 of ")
    in $S.int_to_str(buf, offset, 96, chapter_total) end
    else let
      val offset = _put(buf, at, "chapter ")
      val offset = $S.int_to_str(buf, offset, 96, chapter_number)
      val offset = _put(buf, offset, " of ")
    in $S.int_to_str(buf, offset, 96, chapter_total) end
  end
  else if readout = 3 then let
    val offset = _put_duration(buf, at, 96, _minutes_for_pages(left))
  in _put(buf, offset, " left in chapter") end
  else if readout = 4 then let
    val rest = _rest_pages(chapter_index, page_count)
    val more = (if rest > 0 then rest else 0): Int
    val offset = _put_duration(buf, at, 96, _minutes_for_pages(left + more))
  in _put(buf, offset, " left in book") end
  else if left = 0 then _put(buf, at, "last page in chapter")
  else let
    (* a spread's screens are two pages each *)
    val pages = (if _spread() then 2 * left else left): Int
    val offset = $S.int_to_str(buf, at, 96, pages)
  in
    if pages = 1 then _put(buf, offset, " page left in chapter")
    else _put(buf, offset, " pages left in chapter")
  end
end

(* The percentage of a thousandth at buf[at, end_at): "<1" rather than "0"
   once reading has begun *)
fn _put_percent {l:agz}{at:nat | at <= 5}{thousandth:nat | thousandth <= 1000}
  (buf: !$A.arr(byte, l, 32), at: int at, thousandth: int thousandth, begun: bool): [end_at:nat | end_at <= at + 11] int end_at =
  if thousandth >= 10 then $S.int_to_str(buf, at, 32, thousandth / 10)
  else if begun then _put(buf, at, "<1")
  else _put(buf, at, "0")

(* The running footer, shown while the bars are hidden, on one line: the
   chapter's title in footer-title; in footer-readout the readout, which a tap on it turns
   to the next; and in footer-book how far into the book the page is,
   never "0%" once reading has begun:
   "Title · 8 pages left in chapter · 32% of book" *)
fn _show_footer {current_page,total,chapter,chapter_count:nat} (current_page: int current_page, total: int total, chapter: int chapter, chapter_count: int chapter_count): void = let
  val () = (if chapter > 0 then toc_title_in("footer-title", chapter - 1) else ())
  val chapter_index = (if chapter > 0 then chapter - 1 else 0): Int
  val buf = $A.alloc<byte>(96)
  val offset = _put_separator(buf, 0)
  val offset = _put_readout(buf, offset, _readout_shown(current_page, total, chapter_index), current_page, total, chapter, chapter_count)
  val () = _set_text_of("footer-readout", buf, offset)
  val thousandth = _permille(chapter_index, current_page, total)
  (* " · ", the percentage (at most 11) and "% of book" *)
  val buf = $A.alloc<byte>(32)
  val offset = _put_separator(buf, 0)
  val offset = _put_percent(buf, offset, thousandth, chapter_index > 0 || current_page > 0)
  val offset = _put(buf, offset, "% of book")
in _set_text_of("footer-book", buf, offset) end

(* The page indicator: the chapter's title (its contents entry's label,
   else "Chapter" and its number) in indicator-title, then " · page " in indicator-label and
   "M of T in chapter" in indicator-pages, which always shows in full while a long
   title is cut *)
(* The indicator's place at buf[0, end_at): "12 of 75 in chapter", or
   scrolled, "34% of chapter" *)
fn _put_place {l:agz} (buf: !$A.arr(byte, l, 96), page: Int, page_count: Int): [end_at:nat | end_at <= 55] int end_at =
  if _scrolled() then _put_chapter_percent(buf, 0, page, page_count) else _put_page_of(buf, 0, page, page_count)

fn _show_indicator {current_page,total,chapter,chapter_count:nat} (current_page: int current_page, total: int total, chapter: int chapter, chapter_count: int chapter_count): void = let
  val () = (if chapter > 0 then toc_title_in("indicator-title", chapter - 1) else ())
  val () = (if _scrolled() then ui_text("indicator-label", "\xC2\xA0\xC2\xB7 ")
    else if _spread() then ui_text("indicator-label", "\xC2\xA0\xC2\xB7 pages ")
    else ui_text("indicator-label", "\xC2\xA0\xC2\xB7 page "))
  val buf = $A.alloc<byte>(96)
  val offset = _put_place(buf, current_page, total)
  val () = _set_text_of("indicator-pages", buf, offset)
in _show_footer(current_page, total, chapter, chapter_count) end

(* A tap on the footer's readout: the next one, which is kept with the
   settings *)
#pub fn reader_readout_next (): void

implement reader_readout_next () =
  case+ reading_get() of
  | @(page, page_count, chapter, chapter_count) => let
      val chapter_index = (if chapter > 0 then chapter - 1 else 0): Int
      val () = set_rd_set(_readout_after(_readout_shown(page, page_count, chapter_index), page, page_count, chapter_index))
    in _show_footer(page, page_count, chapter, chapter_count) end

fn _update_page_indicator(): void =
  case+ reading_get() of @(page, page_count, chapter, chapter_count) => _show_indicator(page, page_count, chapter, chapter_count)

(* The page's width, as it was last measured *)
val _page_width = ref<int>(0)



(* Measures a content node: whether it is in the page. The page answers
   1 for an element it measured and 0 for an id it has no element for (a
   text node's number), with every measure slot 0, so only 1 is one: a
   number with no element would otherwise start at the page's left edge,
   and a place anchored there would be the chapter's first page *)
fn _measure_node {node:nat} (node: int node): bool = let
  val @(node_id, node_id_len) = _number_id("c", node, 3)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(node_id)
  val measured = $DR.measure(id_bytes, node_id_len)
  val () = release_bytes(id_frozen, id_bytes)
in
  case+ measured of
  | $DR.Measured() => true
  | $DR.NoElement() => false
end

(* The content node at x, y (its number), or -1 *)
fn _node_at (x: int, y: int): [node:int | node >= ~1] int node =
  case+ $DR.element_at_point(x, y) of
  | ~$R.none() => ~1
  | ~$R.some(blob) => let
      val blob_len = $BD.blob_len(blob)
    in
      if blob_len <= 0 then let val () = $BD.blob_free(blob) in ~1 end
      else if blob_len > 16 then let val () = $BD.blob_free(blob) in ~1 end
      else let
        val id_text = $A.alloc<byte>(blob_len)
        val () = $BD.blob_read(blob, 0, id_text, blob_len)
        val () = $BD.blob_free(blob)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(id_text)
        val node = nid_parse(id_bytes, blob_len, 0, "c")
        val () = release_bytes(id_frozen, id_bytes)
      in node end
    end

(* The first content node down the middle of the page, from y, in steps
   of 40 px, tries more times *)
fun _node_down {tries:nat} .<tries>. (x: int, y: int, tries: int tries): [node:int | node >= ~1] int node = let
  val node = _node_at(x, y)
in if node >= 0 then node else if tries <= 0 then ~1 else _node_down(x, y + 40, tries - 1) end

(* The first of content nodes node to node + more that has an element *)
fun _first_element {node:nat}{more:nat} .<more>. (node: int node, more: int more): [node:int | node >= ~1] int node =
  if _measure_node(node) then node
  else if more <= 0 then ~1
  else _first_element(node + 1, more - 1)

(* The probe: the chapter's first content node with an element (found
   by its id, not by what is on top of the page, which may be a panel),
   and its offset below the page's top, measured with the chapter
   scrolled to its top *)
fn _probe_set (): void = let
  val () = _measure_literal("page")
  val page_top = $DR.get_measure_y()
  val node = _first_element(0, 60)
in
  if node < 0 then !_probe := ~1
  else if ~_measure_node(node) then !_probe := ~1
  else let
    val () = !_probe := node
  in !_probe_offset := $DR.get_measure_y() - page_top end
end

(* How far the chapter is scrolled down now: from where the probe is;
   the page's scroll for the page when there is no probe *)
fn _scroll_top (page: Int): Int = let
  val node = !_probe
in
  if node < 0 then page * _step()
  else let
    val () = _measure_literal("page")
    val page_top = $DR.get_measure_y()
    val node = (if node > 0 then node else 0): [node:nat] int node
  in
    if ~_measure_node(node) then page * _step()
    else !_probe_offset - ($DR.get_measure_y() - page_top)
  end
end

(* Whether a content node starts in [low, high) across the page (down it,
   scrolled): on the page shown, when that is the page's width *)
fn _starts_in {node:nat} (node: int node, low: int, high: int): bool =
  if ~_measure_node(node) then false
  else if _scrolled() then let val y = $DR.get_measure_y() in y >= low && y < high end
  (* right to left, a node starts at its right edge *)
  else if !_right_to_left then let
    val right_edge = $DR.get_measure_x() + $DR.get_measure_w()
  in right_edge > low + 1 && right_edge <= high + 1 end
  else let val x = $DR.get_measure_x() in x >= low && x < high end

(* The first of content nodes node to node + more that starts on the page, [low,
   high) across; -1 when none does *)
fun _first_start {node:nat}{more:nat} .<more>. (node: int node, more: int more, low: int, high: int): [node:int | node >= ~1] int node =
  if _starts_in(node, low, high) then node
  else if more <= 0 then ~1
  else _first_start(node + 1, more - 1, low, high)

(* The content node the page shown starts with (its number), or -1: the
   first element down the middle of the page from its first line, or,
   when that one began on a page before (a paragraph carried over), the
   first of the next 40 that begins on this one, so that the page it
   names is this page *)
fn _anchor_now (): [node:int | node >= ~1] int node = let
  val () = _measure_literal("page")
  val page_left = $DR.get_measure_x()
  val page_top = $DR.get_measure_y()
  val page_width = $DR.get_measure_w()
  val page_height = $DR.get_measure_h()
  (* the first column's middle: of a spread's two, the left one, or the
     right one in a book read right to left *)
  val x = (if _spread() then (if !_right_to_left then page_left + 3 * page_width / 4 else page_left + page_width / 4) else page_left + page_width / 2): int
  val node = _node_down(x, page_top + 24, 8)
  (* across the page, or down it when scrolled *)
  val low = (if _scrolled() then page_top - 1 else page_left - 1): int
  val high = (if _scrolled() then page_top + page_height else page_left + page_width): int
in
  if node < 0 then node
  else if _starts_in(node, low, high) then node
  else let
    val first_starting = _first_start(node + 1, 40, low, high)
  in if first_starting >= 0 then first_starting else node end
end

(* Scrolled, the screenful of page_count shown with the chapter scrolled down by
   top: the nearest whole step, and the last at the bottom, where the
   browser stops a scroll short of a whole step. A place kept, a hand
   scroll and a node's screen are all counted this way *)
fn _screen_at {page_count:pos} (top: Int, bottom: Int, page_count: int page_count): [screen:nat | screen < page_count] int screen = let
  val step = _step()
  val screen = (if top >= bottom - 2 then page_count - 1 else if top > 0 then (top + step / 2) / step else 0): Int
in if screen <= 0 then 0 else if screen >= page_count then page_count - 1 else screen end

(* Scrolled, how far down the chapter a content node starts (the page
   shown now is current), and how far the chapter can be scrolled: ~1 for
   the first when the node is not in the chapter *)
fn _node_down_by {node:int} (node: int node, current: Int): @(Int, Int) =
  if node < 0 then @(~1, 0)
  else if ~_measure_node(node) then @(~1, 0)
  else let
    val node_top = $DR.get_measure_y()
    val () = _measure_literal("page")
    val page_top = $DR.get_measure_y()
    (* the page's height as it is now, which its screens are counted by *)
    val () = !_page_height := $DR.get_measure_h()
    val bottom = $DR.get_measure_scroll_h() - $DR.get_measure_h()
    val offset = _scroll_top(current) + (node_top - page_top)
  in @((if offset > 0 then offset else 0), bottom) end

(* The page, of the chapter's page_count, that a content node is on (the page
   shown now is current); current when it is not in the chapter *)
fn _page_of_node {page_count:pos}{current:nat | current < page_count}{node:nat} (node: int node, page_count: int page_count, current: int current): [page:nat | page < page_count] int page =
  if _scrolled() then let
    val @(offset, bottom) = _node_down_by(node, current)
  in if offset < 0 then current else _screen_at(offset, bottom, page_count) end
  else if ~_measure_node(node) then current
  else let
    val node_left = $DR.get_measure_x()
    val node_right = node_left + $DR.get_measure_w()
    val () = _measure_literal("page")
    val page_left = $DR.get_measure_x()
    val page_width = $DR.get_measure_w()
  in
    if page_width <= 0 then current
    else let
      (* within a pixel or two of the page's edge is on it, as _anchor_now
         takes a node there (columns can fall between pixels); right to
         left, the pages go on to the left, and a node starts at its
         right edge *)
      val distance = (if !_right_to_left then page_left + page_width - node_right + 2 else node_left - page_left + 2): Int
      (* whole pages from the one shown, rounded down *)
      val pages_away = (if distance >= 0 then distance / page_width else ~((page_width - 1 - distance) / page_width)): Int
      val page = current + pages_away
    in if page < 0 then 0 else if page >= page_count then page_count - 1 else page end
  end

(* The content node at the top of the page last shown: what a new
   layout (another size or type, measured after it changed) keeps in
   view *)
val _anchor_last = ref<Int>(~1)

(* The chapter's pages as it is laid out (the page just measured):
   across, its scroll width over its width; scrolled, its screenfuls *)
fn _count_pages (): [count:int] int count =
  if _scrolled() then let
    val height = $DR.get_measure_h()
    val scroll_height = $DR.get_measure_scroll_h()
    val extra = scroll_height - height
    val step = _step()
  in if height <= 0 then 1 else if extra <= 0 then 1 else 1 + (extra + step - 1) / step end
  else let
    val page_width = $DR.get_measure_w()
    val scroll_width = $DR.get_measure_scroll_w()
    (* a spread's last screen can hold one column, half a screen: its
       screens are counted up, past a few pixels of rounding *)
  in if page_width > 8 then (scroll_width + page_width - 8) / page_width else 1 end

fn _measure_pagination(): void = let
  val page_id = $A.alloc<byte>(4)
  val () = $A.write_text(page_id, 0, $A.text_lit("page"), 4)
  val @(page_id_frozen, page_id_bytes) = $A.freeze<byte>(page_id)
  (* back to the first page, which the reading position now names *)
  (* both ways: a switch between pages and scrolled leaves the other *)
  val () = $SC.set_scroll_top(page_id_bytes, 4, 0)
  val () = $SC.set_scroll_left(page_id_bytes, 4, 0)
  val _ = $DR.measure(page_id_bytes, 4)
  val () = release_bytes(page_id_frozen, page_id_bytes)
  (* The page's widths, checked here: the chapter has scroll width /
     width pages, and at least one *)
  val page_width = $DR.get_measure_w()
  val () = !_page_width := page_width
  val () = !_page_height := $DR.get_measure_h()
  val total = _count_pages()
  val page_count = (if total > 1 then total else 1): [page_count:pos] int page_count
  val () = (if _scrolled() then _probe_set() else ())
  val () = (case+ reading_get() of
    | @(_, _, chapter, chapter_count) => reading_set(@(0, page_count, chapter, chapter_count)))
  val () = window_show(0, page_count)
in _update_page_indicator() end


(* The position read to the open book's record in the library, which is
   then stored *)
fn _record_position (): void = let
  val book_index = lib_index_of_key(open_key_get())
  val anchor = _anchor_now()
  val () = !_anchor_last := anchor
  val now = $TM.epoch_minutes()
in
  case+ reading_get() of
  | @(page, page_count, chapter, chapter_count) =>
    if book_index < 0 then ()
    else let
      val chapter_index = (if chapter > 0 then chapter - 1 else 0): Int
      val at_end = (if chapter_count > 0 then (if chapter >= chapter_count then page + 1 >= page_count else false) else false): bool
      val minutes_read = !_book_minutes
      val pages_read = !_book_pages
      val () = !_book_minutes := 0
      val () = !_book_pages := 0
      val () = (case+ lib_nums(book_index) of ~$R.none() => () | ~$R.some(record) => lib_nums_set(book_index, @{
        key = record.key, id_high = record.id_high, id_low = record.id_low, shelf = record.shelf, added = record.added, opened = now,
        chapter = chapter_index, chapters = (if chapter_count > 0 then (chapter_count: Int) else record.chapters), page = page, pages = page_count, anchor = anchor,
        file_size = record.file_size, cover = record.cover, done = (if at_end then 1 else record.done), series_number = record.series_number, collections = record.collections,
        minutes_read = record.minutes_read + minutes_read, pages_read = record.pages_read + pages_read, finished_at = (if at_end then (if record.finished_at > 0 then record.finished_at else now) else record.finished_at),
        shelf_modified = record.shelf_modified, collections_modified = record.collections_modified,
        (* finished now: a change sync passes on *)
        finished_modified = (if at_end then (if record.done = 0 then stamp_now() else record.finished_modified) else record.finished_modified),
        minutes_elsewhere = record.minutes_elsewhere, pages_elsewhere = record.pages_elsewhere }))
      val () = lib_touch(book_index)
    in lib_save() end
end

(* ============================================================
   The scrubber: where the page is in the book, by the chapters'
   sizes, in thousandths
   ============================================================ *)



(* The scrubber at thousandth: its thumb, its fill and the percentage *)
fn _scrub_at {thousandth:nat | thousandth <= 1000} (thousandth: int thousandth): void = let
  val () = ui_place("scrubber-thumb", PLeft, thousandth)
  val () = ui_place("scrubber-fill", PWidth, thousandth)
  val buf = $A.alloc<byte>(16)
  val offset = $S.int_to_str(buf, 0, 16, thousandth / 10)
  val offset = _put(buf, offset, "%")
  val () = ui_text_buf("scrubber-percent", buf, offset)
  val buf = $A.alloc<byte>(16)
  val offset = $S.int_to_str(buf, 0, 16, thousandth / 10)
in ui_attr_buf("scrubber-track", AValueNow, buf, offset) end

(* The scrubber at the page shown, its percentage with the time the rest
   of the book takes, when the speed is known: its pages are the pages
   left in this chapter, and the rest of the book's size in this
   chapter's pages *)
fn _scrub_show (): void =
  case+ reading_get() of
  | @(page, page_count, chapter, _) => let
      val chapter_index = (if chapter > 0 then chapter - 1 else 0): Int
      val thousandth = _permille(chapter_index, page, page_count)
      val () = _scrub_at(thousandth)
      val left = (if page + 1 < page_count then page_count - page - 1 else 0): Int
      val rest = _rest_pages(chapter_index, page_count)
      val minutes = (if rest < 0 then ~1 else _minutes_for_pages(left + rest)): Int
    in
      if minutes < 0 then ()
      else let
        val buf = $A.alloc<byte>(64)
        val offset = $S.int_to_str(buf, 0, 64, thousandth / 10)
        val offset = _put(buf, offset, "% \xC2\xB7 ")
        val offset = _put_duration(buf, offset, 64, minutes)
        val offset = _put(buf, offset, " left")
      in ui_text_buf("scrubber-percent", buf, offset) end
    end

(* A tick on the scrubber where each chapter after the first starts *)
fun _ticks {i,chapter_count:nat} .<max(chapter_count - i, 0)>. (i: int i, chapter_count: int chapter_count): void =
  if i >= chapter_count then ()
  else let
    val @(size_before, _, book_size) = book_weights(book_serial(), i)
    val @(tick_id, tick_id_len) = nid_make("scrubber-tick", i)
    val () = ui_add_n("scrubber-ticks", tick_id, tick_id_len, TDiv)
    val @(tick_id, tick_id_len) = nid_make("scrubber-tick", i)
    val () = ui_attr_n(tick_id, tick_id_len, AClass, "tick")
    val thousandth = _thousandth(size_before, book_size)
    val @(tick_id, tick_id_len) = nid_make("scrubber-tick", i)
    val () = ui_place_n(tick_id, tick_id_len, PLeft, thousandth)
  in _ticks(i + 1, chapter_count) end

fn _ticks_show {chapter_count:nat} (chapter_count: int chapter_count): void = let
  val () = ui_clear("scrubber-ticks")
in _ticks(1, chapter_count) end

(* The chapter, of chapter_count, at a thousandth of the book, and the thousandth
   of the chapter *)
fun _chapter_at {i,chapter_count:nat} .<max(chapter_count - i, 0)>. (thousandth: Int, i: int i, chapter_count: int chapter_count): @([chapter:nat] int chapter, [chapter_thousandth:nat | chapter_thousandth <= 1000] int chapter_thousandth) =
  if i >= chapter_count then @(0, 0)
  else let
    val @(size_before, chapter_size, book_size) = book_weights(book_serial(), i)
    val position = _of_thousandth(thousandth, book_size)
  in
    if (if position < size_before + chapter_size then true else i + 1 >= chapter_count) then
      @(i, _thousandth(position - size_before, chapter_size))
    else _chapter_at(thousandth, i + 1, chapter_count)
  end

(* The thousandth of the book at x on the scrubber's track *)
fn _track_at (x: Int): [thousandth:nat | thousandth <= 1000] int thousandth = let
  val () = _measure_literal("scrubber-track")
  val track_left = $DR.get_measure_x()
  val track_width = $DR.get_measure_w()
in if track_width <= 0 then 0 else _clamp1000((x - track_left) * 1000 / track_width) end

(* Shows page p of the chapter's t pages *)
(* The print pages' breaks in the chapter shown (epub:type pagebreak, or
   role doc-pagebreak), the latest first: each one's content node and its
   label, the page's number in print *)
datavtype breaks(int) =
  | breaks_nil(0) of ()
  | {count:nat}{node:nat}{l:agz}{label_len:pos | label_len <= 16} breaks_cons(count + 1) of (int node, $A.arr(byte, l, label_len), int label_len, breaks(count))

fun breaks_free {count:nat} .<count>. (entries: breaks(count)): void =
  case+ entries of
  | ~breaks_nil() => ()
  | ~breaks_cons(_, label, _, rest) => let val () = $A.free<byte>(label) in breaks_free(rest) end

datavtype breaks_cell = {count:nat} BreaksCell of breaks(count)

val _breaks = ref<breaks_cell>(BreaksCell(breaks_nil()))

fn _breaks_take (): breaks_cell = let
  var cell: breaks_cell = BreaksCell(breaks_nil())
  val () = ref_exch_elt<breaks_cell>(_breaks, cell)
in cell end

fn _breaks_put (new_cell: breaks_cell): void = let
  var cell: breaks_cell = new_cell
  val () = ref_exch_elt<breaks_cell>(_breaks, cell)
  val+ ~BreaksCell(old) = cell
in breaks_free(old) end

(* label[j, label_len) := data[start + j, start + label_len) *)
fun _copy_span {data_location,label_location:agz}{data_size,label_size:pos}{start,label_len:nat | start + label_len <= data_size; label_len <= label_size}{j:nat | j <= label_len} .<label_len - j>.
  (data: !$A.borrow(byte, data_location, data_size), start: int start, label: !$A.arr(byte, label_location, label_size), label_len: int label_len, j: int j): void =
  if j >= label_len then ()
  else let
    val () = $A.set<byte>(label, j, $A.read<byte>(data, start + j))
  in _copy_span(data, start, label, label_len, j + 1) end

(* A content node, when it is a print page's break, kept with its
   label (its title, else its aria-label; at most 16 bytes) *)
fn _break_check {l:agz}{n:pos}{attr_count:nat}{node:nat}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count), node: int node): void = let
  var _attr_type = @[char][9]('e', 'p', 'u', 'b', ':', 't', 'y', 'p', 'e')
  var _attr_role = @[char][4]('r', 'o', 'l', 'e')
  var _pagebreak_type = @[char][9]('p', 'a', 'g', 'e', 'b', 'r', 'e', 'a', 'k')
  var _pagebreak_role = @[char][9]('p', 'a', 'g', 'e', 'b', 'r', 'e', 'a', 'k')
  var _attr_title = @[char][5]('t', 'i', 't', 'l', 'e')
  var _attr_label = @[char][10]('a', 'r', 'i', 'a', '-', 'l', 'a', 'b', 'e', 'l')
  val is_break = (case+ find_attr(data, attrs, _attr_type, 9) of
    | ~xspan_at(start, span_len) => span_has(data, start, span_len, _pagebreak_type, 9)
    | ~xspan_none() => (case+ find_attr(data, attrs, _attr_role, 4) of
      | ~xspan_at(start, span_len) => span_has(data, start, span_len, _pagebreak_role, 9)
      | ~xspan_none() => false)): bool
in
  if ~is_break then ()
  else let
    val span = (case+ find_attr(data, attrs, _attr_title, 5) of
      | ~xspan_none() => find_attr(data, attrs, _attr_label, 10)
      | span => span): xspan(n)
  in
    case+ span of
    | ~xspan_none() => ()
    | ~xspan_at(start, span_len) =>
      if span_len < 1 then () else if span_len > 16 then ()
      else let
        val label = $A.alloc<byte>(span_len)
        val () = _copy_span(data, start, label, span_len, 0)
        val+ ~BreaksCell(older) = _breaks_take()
      in _breaks_put(BreaksCell(breaks_cons(node, label, span_len, older))) end
  end
end

(* target[at + j, at + label_len) := label[j, label_len) *)
fun _label_to {label_location,target_location:agz}{label_size,target_size:pos}{at:nat}{label_len:nat | label_len <= label_size; at + label_len <= target_size}{j:nat | j <= label_len} .<label_len - j>.
  (label: !$A.arr(byte, label_location, label_size), target: !$A.arr(byte, target_location, target_size), at: int at, label_len: int label_len, j: int j): void =
  if j >= label_len then ()
  else let
    val () = $A.set<byte>(target, at + j, $A.get<byte>(label, j))
  in _label_to(label, target, at, label_len, j + 1) end

(* The label of the latest break at or before page current of page_count, copied *)
fun _break_at {count:nat}{page_count:pos}{current:nat | current < page_count} .<count>. (break_list: !breaks(count), page_count: int page_count, current: int current): [l:agz][label_len:nat | label_len <= 16] @($A.arr(byte, l, label_len + 1), int label_len) =
  case+ break_list of
  | breaks_nil() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  | @breaks_cons(node, label, label_len, rest) =>
    if _page_of_node(node, page_count, current) <= current then let
      val copy = $A.alloc<byte>(label_len + 1)
      val () = _label_to(label, copy, 0, label_len, 0)
      val copy_len = label_len
      prval () = fold@(break_list)
    in @(copy, copy_len) end
    else let
      val found = _break_at(rest, page_count, current)
      prval () = fold@(break_list)
    in found end

(* " in print" after the label, which ends at buf[label_end]; the text's end, or
   0 (nothing shown) when there is no label *)
fn _in_print {l:agz}{label_end:nat | label_end <= 25}{label_len:nat}
  (buf: !$A.arr(byte, l, 40), label_end: int label_end, label_len: int label_len): [end_at:nat | end_at <= 40] int end_at =
  if label_len > 0 then _put(buf, label_end, " in print") else 0

(* The footer's print page: " · page 214 in print", from the latest break at
   or before the page shown; nothing in a chapter that has none *)
fn _show_print_page {page_count:pos}{current:nat | current < page_count} (page_count: int page_count, current: int current): void = let
  val cell = _breaks_take()
  val+ @BreaksCell(break_list) = cell
  val @(label, label_len) = _break_at(break_list, page_count, current)
  prval () = fold@(cell)
  val () = _breaks_put(cell)
  (* " · page " (9 bytes), the label (at most 16) and " in print" *)
  val buf = $A.alloc<byte>(40)
  val () = $A.set<byte>(buf, 0, $A.int2byte(32))
  val () = $A.set<byte>(buf, 1, $A.int2byte(194))
  val () = $A.set<byte>(buf, 2, $A.int2byte(183))
  val offset = _put(buf, 3, " page ")
  val () = _label_to(label, buf, offset, label_len, 0)
  (* the print page a highlight or bookmark made here cites *)
  val () = annot_print_page_set(label, label_len)
  val () = $A.free<byte>(label)
in _set_text_of("footer-page", buf, _in_print(buf, offset + label_len, label_len)) end

(* A page of page_count is the one shown: the reader's place, and everything that
   says it, without moving the page *)
fn _place_shown {page_count:pos}{page:nat | page < page_count}{chapter,chapter_count:nat}
  (page: int page, page_count: int page_count, chapter: int chapter, chapter_count: int chapter_count): void = let
  val () = reading_set(@(page, page_count, chapter, chapter_count))
  val () = window_show(page, page_count)
  val () = _update_page_indicator()
  val () = _show_print_page(page_count, page)
  val () = _scrub_show()
  val () = annot_star()
  (* scrolled, the last screen offers the next chapter *)
  val () = ui_show("next-chapter", (if _scrolled() then (if page + 1 >= page_count then chapter < chapter_count else false) else false))
in _record_position() end

(* Shows a page of page_count, scrolled down by top when scrolled (the page's
   own step otherwise) *)
fn _show_page_down {page_count:pos}{page:nat | page < page_count}{chapter,chapter_count:nat}
  (page: int page, page_count: int page_count, chapter: int chapter, chapter_count: int chapter_count, top: Int): void = let
  (* auto turns to Night when a page turned passes 22:00 *)
  val () = set_theme_recheck()
  val () = reading_set(@(page, page_count, chapter, chapter_count))
  val () = window_show(page, page_count)
  val page_id = $A.alloc<byte>(4)
  val () = $A.write_text(page_id, 0, $A.text_lit("page"), 4)
  val @(page_id_frozen, page_id_bytes) = $A.freeze<byte>(page_id)
  val _ = $DR.measure(page_id_bytes, 4)
  val page_width = $DR.get_measure_w()
  val () = !_page_width := page_width
  val () = !_page_height := $DR.get_measure_h()
  val () = (if _scrolled() then $SC.set_scroll_top(page_id_bytes, 4, (if top >= 0 then top else page * _step()))
    (* right to left, the pages go on to the left: a scroll below 0 *)
    else $SC.set_scroll_left(page_id_bytes, 4, (if !_right_to_left then ~(page * page_width) else page * page_width)))
  val () = release_bytes(page_id_frozen, page_id_bytes)
in _place_shown(page, page_count, chapter, chapter_count) end

fn _show_page {page_count:pos}{page:nat | page < page_count}{chapter,chapter_count:nat}
  (page: int page, page_count: int page_count, chapter: int chapter, chapter_count: int chapter_count): void = _show_page_down(page, page_count, chapter, chapter_count, ~1)

(* ============================================================
   Content tree rendering (XHTML → DOM nodes)
   ============================================================ *)

(* Content nodes are numbered from 0 in each chapter *)
val _content_count = ref<[count:nat] int count>(0)

(* Content node i's element: id "c" and i's digits, with op run on its
   id as a borrow *)
(* The id of a content node (or of the content area page, for ~1) in a
   fresh array; with its length *)
fn _node_id {node:int | node >= ~1} (node: int node): [l:agz][id_len:pos | id_len <= 16] @($A.arr(byte, l, id_len), int id_len) =
  if node < 0 then let
    val page_id = $A.alloc<byte>(4)
    val () = $A.write_text(page_id, 0, $A.text_lit("page"), 4)
  in @(page_id, 4) end
  else _number_id("c", node, 3)

(* A new element <tag> for a content node, the last child of the node parent *)
fn _add_node {doc_location:agz}{parent:int | parent >= ~1}{node:nat}
  (doc: !$D.document(doc_location), parent: int parent, node: int node, tag: $D.tag): void = let
  val @(parent_id, parent_id_len) = _node_id(parent)
  val @(node_id, node_id_len) = _node_id(node)
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(parent_id)
  val @(node_frozen, node_bytes) = $A.freeze<byte>(node_id)
  val () = $D.add_element(doc, parent_bytes, parent_id_len, node_bytes, node_id_len, tag)
  val () = release_bytes(node_frozen, node_bytes)
in release_bytes(parent_frozen, parent_bytes) end

(* Element id's text: data[offset, offset + text_len) decoded *)
fn _set_decoded {doc_location,id_location,data_location:agz}{id_len:pos | id_len < 256}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size; text_len < 65536; text_len > 0}
  (doc: !$D.document(doc_location), id_bytes: !$A.borrow(byte, id_location, id_len), id_len: int id_len,
   data: !$A.borrow(byte, data_location, data_size), offset: int offset, text_len: int text_len): void = let
  val buf = $A.alloc<byte>(text_len)
  val decoded_len = decode_text(data, offset, text_len, buf)
  val @(text_frozen, text_bytes) = $A.freeze<byte>(buf)
  val () = $D.set_text(doc, id_bytes, id_len, text_bytes, 0, decoded_len)
in release_bytes(text_frozen, text_bytes) end

(* A content node's text: data[offset, offset + text_len), its character
   references decoded *)
fn _node_text {doc_location,l:agz}{n:pos}{node:nat}{offset,text_len:nat | offset + text_len <= n; text_len < 65536}
  (doc: !$D.document(doc_location), node: int node, data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len): void = let
  val @(node_id, node_id_len) = _node_id(node)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(node_id)
  val () = (if text_len <= 0 then $D.set_text(doc, id_bytes, node_id_len, data, offset, text_len)
    else if has_reference(data, offset, text_len) then _set_decoded(doc, id_bytes, node_id_len, data, offset, text_len)
    else $D.set_text(doc, id_bytes, node_id_len, data, offset, text_len))
in release_bytes(id_frozen, id_bytes) end

(* Whether data[at] starts a UTF-8 character (is not 10xxxxxx) *)
fn _utf8_start {l:agz}{n:pos}{at:nat | at < n}
  (data: !$A.borrow(byte, l, n), at: int at): bool =
  $AR.band_int_int(byte2int0($A.read<byte>(data, at)), 192) <> 128

(* The length of the longest prefix of data[offset, offset + text_len), text_len of 64 KiB
   or more, under 64 KiB (a text op's limit) that ends before a UTF-8
   character's start, so no character is split; 65535 when the data is
   not UTF-8 there *)
fn _text_cut {l:agz}{n:pos}{offset,text_len:nat | offset + text_len <= n; text_len >= 65536}
  (data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len): [cut:int | 65533 <= cut; cut <= 65535] int cut =
  if _utf8_start(data, offset + 65535) then 65535
  else if _utf8_start(data, offset + 65534) then 65534
  else if _utf8_start(data, offset + 65533) then 65533
  else 65535

(* A content node's attribute name: data[offset, offset + value_len) *)
fn _node_attr {doc_location,l:agz}{n:pos}{node:nat}{offset,value_len:nat | offset + value_len <= n; value_len < 65536}
  (doc: !$D.document(doc_location), node: int node, name: $D.attribute, data: !$A.borrow(byte, l, n), offset: int offset, value_len: int value_len): void = let
  val @(node_id, node_id_len) = _node_id(node)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(node_id)
  val () = $D.set_attr(doc, id_bytes, node_id_len, name, data, offset, value_len)
in release_bytes(id_frozen, id_bytes) end

(* A content node's attribute name: the literal value *)
fn _node_attr_literal {doc_location:agz}{node:nat}{value_len:pos | value_len < 256}
  (doc: !$D.document(doc_location), node: int node, name: $D.attribute, value: string value_len): void = let
  val value_len = g1u2i(string1_length(value))
  val value_buf = $A.alloc<byte>(value_len)
  val () = $A.write_text(value_buf, 0, $A.text_lit(value), value_len)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value_buf)
  val () = _node_attr(doc, node, name, value_bytes, 0, value_len)
in release_bytes(value_frozen, value_bytes) end

(* A content node's URL attribute name: data[offset, offset + value_len),
   set only when dom's set_url finds it a URL that runs no script *)
fn _node_url {doc_location,l:agz}{n:pos}{node:nat}{offset,value_len:nat | offset + value_len <= n; value_len < 65536}
  (doc: !$D.document(doc_location), node: int node, name: $D.url_attribute, data: !$A.borrow(byte, l, n), offset: int offset, value_len: int value_len): void = let
  val @(node_id, node_id_len) = _node_id(node)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(node_id)
  val _ = $D.set_url(doc, id_bytes, node_id_len, name, data, offset, value_len)
in release_bytes(id_frozen, id_bytes) end

(* A content node's source emptied: "data:,", an empty text, until its
   image is read *)
fn _node_src_empty {doc_location:agz}{node:nat} (doc: !$D.document(doc_location), node: int node): void = let
  val @(node_id, node_id_len) = _node_id(node)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(node_id)
  val () = $D.set_url_literal(doc, id_bytes, node_id_len, $D.Src, $D.EmptyData)
in release_bytes(id_frozen, id_bytes) end

(* Content nodes are numbered from 0 in each chapter *)
val _content_count = ref<[count:nat] int count>(0)

(* Get next content node index and increment counter *)
fn _next_content_node(): [node:nat] int node = let
  val node = !_content_count
  val () = !_content_count := node + 1
in node end

(* Text data[offset, offset + text_len) as spans, the last children of content node
   parent: one span per piece under 64 KiB (a text op's limit), split
   where a UTF-8 character starts *)
fun _text_spans {doc_location,l:agz}{n:pos}{parent:int | parent >= ~1}{offset,text_len:nat | offset + text_len <= n} .<text_len>.
  (doc: !$D.document(doc_location), data: !$A.borrow(byte, l, n), parent: int parent, offset: int offset, text_len: int text_len): void = let
  val node = _next_content_node()
  val () = _add_node(doc, parent, node, $D.Span)
in
  if text_len < 65536 then _node_text(doc, node, data, offset, text_len)
  else let
    val cut = _text_cut(data, offset, text_len)
    val () = _node_text(doc, node, data, offset, cut)
  in _text_spans(doc, data, parent, offset + cut, text_len - cut) end
end

(* Whether data[offset + i, offset + text_len) is all white space *)
fun _blank {l:agz}{n:pos}{offset,text_len:nat | offset + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if byte2int0($A.read<byte>(data, offset + i)) > 32 then false
  else _blank(data, offset, text_len, i + 1)

(* The numbers _text_spans would give text of text_len bytes, taken *)
fun _skip_spans {text_len:nat} .<text_len>. (offset: int, text_len: int text_len): void = let
  val _ = _next_content_node()
in if text_len < 65536 then () else _skip_spans(offset, text_len - 65533) end

(* The tag an XHTML element is shown as: itself when it is one quire
   shows, a span for a, b, i, u and s, and a div for anything else *)
fn _tag_of
  {l:agz}{n:pos}{name_offset,name_len:nat | name_offset + name_len <= n}
  (data: !$A.borrow(byte, l, n), name_offset: int name_offset, name_len: int name_len): $D.tag = let
  fn is {pattern_len:pos} (data: !$A.borrow(byte, l, n), pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool =
    xml_name_eq(data, name_offset, name_len, pattern, pattern_len)
  var p_ = @[char][1]('p')
  var h1 = @[char][2]('h', '1')
  var h2 = @[char][2]('h', '2')
  var h3 = @[char][2]('h', '3')
  var h4 = @[char][2]('h', '4')
  var h5 = @[char][2]('h', '5')
  var h6 = @[char][2]('h', '6')
  var span = @[char][4]('s', 'p', 'a', 'n')
  var em = @[char][2]('e', 'm')
  var strong = @[char][6]('s', 't', 'r', 'o', 'n', 'g')
  var blockquote = @[char][10]('b', 'l', 'o', 'c', 'k', 'q', 'u', 'o', 't', 'e')
  var pre = @[char][3]('p', 'r', 'e')
  var code = @[char][4]('c', 'o', 'd', 'e')
  var ul = @[char][2]('u', 'l')
  var ol = @[char][2]('o', 'l')
  var li = @[char][2]('l', 'i')
  var section = @[char][7]('s', 'e', 'c', 't', 'i', 'o', 'n')
  var article = @[char][7]('a', 'r', 't', 'i', 'c', 'l', 'e')
  var small = @[char][5]('s', 'm', 'a', 'l', 'l')
  var mark = @[char][4]('m', 'a', 'r', 'k')
  var del = @[char][3]('d', 'e', 'l')
  var ins = @[char][3]('i', 'n', 's')
  var sub = @[char][3]('s', 'u', 'b')
  var sup = @[char][3]('s', 'u', 'p')
  var a_ = @[char][1]('a')
  var b_ = @[char][1]('b')
  var i_ = @[char][1]('i')
  var u_ = @[char][1]('u')
  var s_ = @[char][1]('s')
  var figure = @[char][6]('f', 'i', 'g', 'u', 'r', 'e')
  var figcaption = @[char][10]('f', 'i', 'g', 'c', 'a', 'p', 't', 'i', 'o', 'n')
  var table = @[char][5]('t', 'a', 'b', 'l', 'e')
  var tr = @[char][2]('t', 'r')
  var td = @[char][2]('t', 'd')
  var th = @[char][2]('t', 'h')
  var thead = @[char][5]('t', 'h', 'e', 'a', 'd')
  var tbody = @[char][5]('t', 'b', 'o', 'd', 'y')
  var q_ = @[char][1]('q')
  var cite = @[char][4]('c', 'i', 't', 'e')
  var abbr = @[char][4]('a', 'b', 'b', 'r')
  var kbd = @[char][3]('k', 'b', 'd')
  var dl = @[char][2]('d', 'l')
  var dt = @[char][2]('d', 't')
  var dd = @[char][2]('d', 'd')
  var caption = @[char][7]('c', 'a', 'p', 't', 'i', 'o', 'n')
  var tfoot = @[char][5]('t', 'f', 'o', 'o', 't')
  var samp = @[char][4]('s', 'a', 'm', 'p')
  var var_ = @[char][3]('v', 'a', 'r')
  var big = @[char][3]('b', 'i', 'g')
  var ruby = @[char][4]('r', 'u', 'b', 'y')
  var ruby_base = @[char][2]('r', 'b')
  var ruby_text = @[char][2]('r', 't')
  var ruby_text_container = @[char][3]('r', 't', 'c')
  var ruby_parenthesis = @[char][2]('r', 'p')
in
  if is(data, p_, 1) then $D.P
  else if is(data, h1, 2) then $D.H1 else if is(data, h2, 2) then $D.H2
  else if is(data, h3, 2) then $D.H3 else if is(data, h4, 2) then $D.H4
  else if is(data, h5, 2) then $D.H5 else if is(data, h6, 2) then $D.H6
  else if is(data, span, 4) then $D.Span else if is(data, em, 2) then $D.Em
  else if is(data, strong, 6) then $D.Strong else if is(data, blockquote, 10) then $D.Blockquote
  else if is(data, pre, 3) then $D.Pre else if is(data, code, 4) then $D.Code
  else if is(data, ul, 2) then $D.Ul else if is(data, ol, 2) then $D.Ol
  else if is(data, li, 2) then $D.Li else if is(data, section, 7) then $D.Section
  else if is(data, article, 7) then $D.Article else if is(data, small, 5) then $D.Small
  else if is(data, mark, 4) then $D.Mark else if is(data, del, 3) then $D.Del
  else if is(data, ins, 3) then $D.Ins else if is(data, sub, 3) then $D.Sub
  else if is(data, sup, 3) then $D.Sup
  else if is(data, a_, 1) then $D.A else if is(data, b_, 1) then $D.B
  else if is(data, i_, 1) then $D.I else if is(data, u_, 1) then $D.U
  else if is(data, s_, 1) then $D.S
  else if is(data, q_, 1) then $D.Q else if is(data, cite, 4) then $D.Cite
  else if is(data, abbr, 4) then $D.Abbr else if is(data, kbd, 3) then $D.Kbd
  else if is(data, dl, 2) then $D.Dl else if is(data, dt, 2) then $D.Dt
  else if is(data, dd, 2) then $D.Dd else if is(data, caption, 7) then $D.Caption
  else if is(data, tfoot, 5) then $D.Tfoot else if is(data, samp, 4) then $D.Samp
  else if is(data, var_, 3) then $D.Var else if is(data, big, 3) then $D.Span
  else if is(data, figure, 6) then $D.Figure else if is(data, figcaption, 10) then $D.Figcaption
  else if is(data, table, 5) then $D.Table else if is(data, tr, 2) then $D.Tr
  else if is(data, td, 2) then $D.Td else if is(data, th, 2) then $D.Th
  else if is(data, thead, 5) then $D.Thead else if is(data, tbody, 5) then $D.Tbody
  (* a ruby keeps its parts, so its annotations sit over its base *)
  else if is(data, ruby, 4) then $D.Ruby else if is(data, ruby_base, 2) then $D.Rb
  else if is(data, ruby_text, 2) then $D.Rt else if is(data, ruby_text_container, 3) then $D.Rtc
  else if is(data, ruby_parenthesis, 2) then $D.Rp
  else $D.Div
end

(* Whether a chapter of the open book has shown a ruby: the settings'
   Ruby row is offered from then on *)
val _ruby_seen = ref<bool>(false)

(* A ruby rendered: the Ruby row shown, the first time *)
fn _ruby_mark (): void =
  if !_ruby_seen then ()
  else let
    val () = !_ruby_seen := true
  in ui_show("ruby-row", true) end

(* A book opens: the Ruby row waits for its first ruby *)
#pub fn reader_ruby_forget (): void
implement reader_ruby_forget () = let
  val () = !_ruby_seen := false
in ui_show("ruby-row", false) end

(* The fragment a jump leads to: the id of an element of the chapter
   loading; its content node is found as the chapter is rendered *)
datavtype fragment =
  | {l:agz}{n,id_len:pos | id_len < n} FragmentSome of ($A.arr(byte, l, n), int id_len)
  | FragmentNone of ()

val _fragment = ref<fragment>(FragmentNone())
val _fragment_node = ref<Int>(~1)

fn _fragment_free (fragment: fragment): void =
  case+ fragment of
  | ~FragmentSome(id, _) => $A.free<byte>(id)
  | ~FragmentNone() => ()

fn _fragment_take (): fragment = let
  var cell: fragment = FragmentNone()
  val () = ref_exch_elt<fragment>(_fragment, cell)
in cell end

fn _fragment_put (fragment: fragment): void = let
  var cell: fragment = fragment
  val () = ref_exch_elt<fragment>(_fragment, cell)
in _fragment_free(cell) end

(* target[j, id_len) := source[j, id_len) *)
fun _fragment_duplicate {source_location,target_location:agz}{source_size,target_size:pos}{id_len:nat | id_len <= source_size; id_len <= target_size}{j:nat | j <= id_len} .<id_len - j>.
  (source: !$A.arr(byte, source_location, source_size), target: !$A.arr(byte, target_location, target_size), id_len: int id_len, j: int j): void =
  if j >= id_len then ()
  else let
    val () = $A.set<byte>(target, j, $A.get<byte>(source, j))
  in _fragment_duplicate(source, target, id_len, j + 1) end

(* Whether data[offset, offset + id_len) is id[0, id_len) *)
fun _same {data_location,id_location:agz}{data_size:pos}{id_size:pos}{offset,id_len:nat | offset + id_len <= data_size; id_len <= id_size}{i:nat | i <= id_len} .<id_len - i>.
  (data: !$A.borrow(byte, data_location, data_size), offset: int offset, id: !$A.arr(byte, id_location, id_size), id_len: int id_len, i: int i): bool =
  if i >= id_len then true
  else if byte2int0($A.read<byte>(data, offset + i)) <> byte2int0($A.get<byte>(id, i)) then false
  else _same(data, offset, id, id_len, i + 1)

(* Notes a content node as the fragment's, when its id is the fragment *)
fn _fragment_check {l:agz}{n:pos}{attr_count:nat}{node:nat}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count), fragment: !fragment, node: int node): void =
  case+ fragment of
  | FragmentNone() => ()
  | FragmentSome(id, id_len) => let
      var _attr_id = @[char][2]('i', 'd')
    in
      case+ find_attr(data, attrs, _attr_id, 2) of
      | ~xspan_at(start, span_len) =>
        if span_len <> id_len then ()
        else if _same(data, start, id, span_len, 0) then (if !_fragment_node < 0 then !_fragment_node := node else ())
        else ()
      | ~xspan_none() => ()
    end

(* The <img> elements of a chapter being rendered, count of them: each one's
   content node and its src attribute, the span [src_start, src_start + src_len) of the
   chapter's n bytes *)
datavtype images(n:int, int) =
  | images_nil(n, 0) of ()
  | {count:nat}{node:nat}{src_start,src_len:nat | src_start + src_len <= n}
    images_cons(n, count + 1) of (int node, int src_start, int src_len, images(n, count))
  (* A link within the book: the content nodes [first_node, end_node) it covers, its
     href [src_start, src_start + src_len), found once the chapter is shown, and whether it
     is a note's reference *)
  | {count:nat}{first_node,end_node:nat}{src_start,src_len:nat | src_start + src_len <= n}
    images_link(n, count + 1) of (int first_node, int end_node, int src_start, int src_len, bool, images(n, count))

(* The links of the chapter shown: the content nodes [first_node, end_node) each covers,
   the chapter (-1 for a link out of the book, which the browser opens)
   and fragment fragment[0, fragment_len) it leads to, and whether it is a note's
   reference (epub:type noteref, or role doc-noteref) *)
datavtype links(int) =
  | links_nil(0) of ()
  | {count:nat}{l:agz}{fragment_len:nat | fragment_len <= 200}
    links_cons(count + 1) of (Int, Int, Int, $A.arr(byte, l, fragment_len + 1), int fragment_len, bool, links(count))

fun links_free {count:nat} .<count>. (entries: links(count)): void =
  case+ entries of
  | ~links_nil() => ()
  | ~links_cons(_, _, _, fragment, _, _, rest) => let val () = $A.free<byte>(fragment) in links_free(rest) end

datavtype links_cell = {count:nat} LinksCell of links(count)

val _links = ref<links_cell>(LinksCell(links_nil()))

fn _links_take (): links_cell = let
  var cell: links_cell = LinksCell(links_nil())
  val () = ref_exch_elt<links_cell>(_links, cell)
in cell end

fn _links_put (new_cell: links_cell): void = let
  var cell: links_cell = new_cell
  val () = ref_exch_elt<links_cell>(_links, cell)
  val+ ~LinksCell(old) = cell
in links_free(old) end

fn _links_push {l:agz}{fragment_len:nat | fragment_len <= 200} (first_node: Int, end_node: Int, chapter: Int, fragment: $A.arr(byte, l, fragment_len + 1), fragment_len: int fragment_len, note: bool): void = let
  val+ ~LinksCell(rest) = _links_take()
in _links_put(LinksCell(links_cons(first_node, end_node, chapter, fragment, fragment_len, note, rest))) end

(* Whether data[offset, offset + span_len) starts with pattern *)
fn _starts {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{pattern_len:pos}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool =
  if span_len < pattern_len then false else xml_name_eq(data, offset, pattern_len, pattern, pattern_len)

(* The attributes of an XHTML element that are kept on its content node:
   dir, lang (and xml:lang), title, colspan and rowspan *)
fun _pass_attrs {doc_location,l:agz}{n:pos}{attr_count:nat}{node:nat} .<attr_count>.
  (doc: !$D.document(doc_location), data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count), node: int node): void =
  case+ attrs of
  | $X.xml_attrs_nil() => ()
  | $X.xml_attrs_cons(name_offset, name_len, value_offset, value_len, rest) => let
      var _dir = @[char][3]('d', 'i', 'r')
      var _lang = @[char][4]('l', 'a', 'n', 'g')
      var _xml_lang = @[char][8]('x', 'm', 'l', ':', 'l', 'a', 'n', 'g')
      var _title = @[char][5]('t', 'i', 't', 'l', 'e')
      var _colspan = @[char][7]('c', 'o', 'l', 's', 'p', 'a', 'n')
      var _rowspan = @[char][7]('r', 'o', 'w', 's', 'p', 'a', 'n')
      val () = (if value_len >= 65536 then ()
        else if xml_name_eq(data, name_offset, name_len, _dir, 3) then _node_attr(doc, node, $D.Dir, data, value_offset, value_len)
        else if xml_name_eq(data, name_offset, name_len, _lang, 4) then _node_attr(doc, node, $D.Lang, data, value_offset, value_len)
        else if xml_name_eq(data, name_offset, name_len, _xml_lang, 8) then _node_attr(doc, node, $D.Lang, data, value_offset, value_len)
        else if xml_name_eq(data, name_offset, name_len, _title, 5) then _node_attr(doc, node, $D.Title, data, value_offset, value_len)
        else if xml_name_eq(data, name_offset, name_len, _colspan, 7) then _node_attr(doc, node, $D.Colspan, data, value_offset, value_len)
        else if xml_name_eq(data, name_offset, name_len, _rowspan, 7) then _node_attr(doc, node, $D.Rowspan, data, value_offset, value_len)
        else ())
    in _pass_attrs(doc, data, rest, node) end

(* Whether an <a> is a note's reference: its epub:type names noteref, or
   its role is doc-noteref *)
fn _noteref {l:agz}{n:pos}{attr_count:nat}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count)): bool = let
  var _attr_type = @[char][9]('e', 'p', 'u', 'b', ':', 't', 'y', 'p', 'e')
  var _attr_role = @[char][4]('r', 'o', 'l', 'e')
  var _noteref_type = @[char][7]('n', 'o', 't', 'e', 'r', 'e', 'f')
  var _noteref_role = @[char][7]('n', 'o', 't', 'e', 'r', 'e', 'f')
  val by_type = (case+ find_attr(data, attrs, _attr_type, 9) of
    | ~xspan_none() => false
    | ~xspan_at(start, span_len) => span_has(data, start, span_len, _noteref_type, 7)): bool
in
  if by_type then true
  else (case+ find_attr(data, attrs, _attr_role, 4) of
    | ~xspan_none() => false
    | ~xspan_at(start, span_len) => span_has(data, start, span_len, _noteref_role, 7))
end

(* An <a> element, content nodes [first_node, end_node): a link out of the book (http,
   https, mailto) is made a real one, opened in a new tab; a link within
   it is kept in found, found once the chapter is shown *)
fn _link {doc_location,l:agz}{n:pos}{attr_count:nat}{first_node,end_node:nat}{found_count:nat}
  (doc: !$D.document(doc_location), data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count),
   first_node: int first_node, end_node: int end_node, found: images(n, found_count)): [new_count:nat] images(n, new_count) = let
  var _href = @[char][4]('h', 'r', 'e', 'f')
in
  case+ find_attr(data, attrs, _href, 4) of
  | ~xspan_none() => found
  | ~xspan_at(href_start, href_len) => let
      var _http = @[char][7]('h', 't', 't', 'p', ':', '/', '/')
      var _https = @[char][8]('h', 't', 't', 'p', 's', ':', '/', '/')
      var _mailto = @[char][7]('m', 'a', 'i', 'l', 't', 'o', ':')
      val outside = (if _starts(data, href_start, href_len, _http, 7) then true
        else if _starts(data, href_start, href_len, _https, 8) then true
        else _starts(data, href_start, href_len, _mailto, 7)): bool
    in
      if outside then
        (if href_len < 65536 then let
           val () = _node_url(doc, first_node, $D.Href, data, href_start, href_len)
           val () = _node_attr_literal(doc, first_node, $D.Target, "_blank")
           val () = _node_attr_literal(doc, first_node, $D.Rel, "noopener noreferrer")
           val () = _links_push(first_node, end_node, ~1, $A.alloc<byte>(1), 0, false)
         in found end
         else found)
      else let
        (* announced and reached from the keyboard as a link *)
        val () = _node_attr_literal(doc, first_node, $D.Role, "link")
        val () = _node_attr_literal(doc, first_node, $D.Tabindex, "0")
      in images_link(first_node, end_node, href_start, href_len, _noteref(data, attrs), found) end
    end
end

(* Whether data[offset + i, offset + tag_len) is letters, digits and hyphens *)
fun _tag_chars {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}{i:nat | i <= tag_len} .<tag_len - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len, i: int i): bool =
  if i >= tag_len then true
  else let
    val char_code = byte2int0($A.read<byte>(data, offset + i))
    val ok = (char_code >= 97 && char_code <= 122) || (char_code >= 65 && char_code <= 90) || (char_code >= 48 && char_code <= 57) || char_code = 45
  in if ok then _tag_chars(data, offset, tag_len, i + 1) else false end

(* Whether data[offset, offset + tag_len) is a plausible language tag *)
fn _lang_ok {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len): bool =
  if tag_len < 1 then false else if tag_len > 35 then false else _tag_chars(data, offset, tag_len, 0)

(* The page's lang: data[offset, offset + lang_len) *)
fn _page_lang {doc_location,l:agz}{n:pos}{offset,lang_len:nat | offset + lang_len <= n; lang_len < 65536}
  (doc: !$D.document(doc_location), data: !$A.borrow(byte, l, n), offset: int offset, lang_len: int lang_len): void = let
  val @(page_id, page_id_len) = _node_id(~1)
  val @(page_id_frozen, page_id_bytes) = $A.freeze<byte>(page_id)
  val () = $D.set_attr(doc, page_id_bytes, page_id_len, $D.Lang, data, offset, lang_len)
in release_bytes(page_id_frozen, page_id_bytes) end

(* An html or body element's language (xml:lang, else lang), when it has
   one, is the page's: the chapter's content goes into the page with no
   element of its own *)
fn _root_lang {doc_location,l:agz}{n:pos}{attr_count:nat}
  (doc: !$D.document(doc_location), data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count)): void = let
  var _attr_xml_lang = @[char][8]('x', 'm', 'l', ':', 'l', 'a', 'n', 'g')
  var _attr_lang = @[char][4]('l', 'a', 'n', 'g')
  val span = (case+ find_attr(data, attrs, _attr_xml_lang, 8) of
    | ~xspan_none() => find_attr(data, attrs, _attr_lang, 4)
    | span => span): xspan(n)
in
  case+ span of
  | ~xspan_none() => ()
  | ~xspan_at(start, span_len) => if _lang_ok(data, start, span_len) then (if span_len < 65536 then _page_lang(doc, data, start, span_len) else ()) else ()
end

(* Walk xml_node_list, rendering each node into parent (through doc's
   borrow operations: nothing is allocated for the page); the <img>
   elements met are added to found *)
fun _render_nodes
  {doc_location,l:agz}{n:pos}{tree_size:nat}{parent:int | parent >= ~1}{found_count:nat} .<tree_size, 1>.
  (doc: !$D.document(doc_location), data: !$A.borrow(byte, l, n), data_len: int n,
   parent: int parent, nodes: !$X.xml_node_list(n, tree_size), found: images(n, found_count), fragment: !fragment): [new_count:nat] images(n, new_count) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val found = _render_node(doc, data, data_len, parent, node, found, fragment)
    in _render_nodes(doc, data, data_len, parent, rest, found, fragment) end
  | $X.xml_nodes_nil() => found

and _render_node
  {doc_location,l:agz}{n:pos}{tree_size:pos}{parent:int | parent >= ~1}{found_count:nat} .<tree_size, 0>.
  (doc: !$D.document(doc_location), data: !$A.borrow(byte, l, n), data_len: int n,
   parent: int parent, node: !$X.xml_node(n, tree_size), found: images(n, found_count), fragment: !fragment): [new_count:nat] images(n, new_count) =
  case+ node of
  | $X.xml_text(offset, text_len) => let
      (* white space between the page's blocks takes its numbers but
         makes no element: it would be a line of its own *)
      val () = (if parent < 0 then (if _blank(data, offset, text_len, 0) then _skip_spans(offset, text_len)
          else _text_spans(doc, data, parent, offset, text_len))
        else _text_spans(doc, data, parent, offset, text_len))
    in found end
  | $X.xml_element(name_offset, name_len, attrs, children) => let
    var _tag_head = @[char][4]('h', 'e', 'a', 'd')
    var _tag_title = @[char][5]('t', 'i', 't', 'l', 'e')
    var _tag_meta = @[char][4]('m', 'e', 't', 'a')
    var _tag_link = @[char][4]('l', 'i', 'n', 'k')
    var _tag_style = @[char][5]('s', 't', 'y', 'l', 'e')
    var _tag_script = @[char][6]('s', 'c', 'r', 'i', 'p', 't')
    var _tag_html = @[char][4]('h', 't', 'm', 'l')
    var _tag_body = @[char][4]('b', 'o', 'd', 'y')
    var _tag_br = @[char][2]('b', 'r')
    var _tag_hr = @[char][2]('h', 'r')
    var _tag_img = @[char][3]('i', 'm', 'g')
    var _tag_image = @[char][5]('i', 'm', 'a', 'g', 'e')
  in
    (* Skipped: head, title, meta, link, style, script *)
    if xml_name_eq(data, name_offset, name_len, _tag_head, 4) then found
    else if xml_name_eq(data, name_offset, name_len, _tag_title, 5) then found
    else if xml_name_eq(data, name_offset, name_len, _tag_meta, 4) then found
    else if xml_name_eq(data, name_offset, name_len, _tag_link, 4) then found
    else if xml_name_eq(data, name_offset, name_len, _tag_style, 5) then found
    else if xml_name_eq(data, name_offset, name_len, _tag_script, 6) then found
    (* Transparent: html, body (their children go to the same parent);
       their language is the page's *)
    else if xml_name_eq(data, name_offset, name_len, _tag_html, 4) then let
      val () = _root_lang(doc, data, attrs)
    in _render_nodes(doc, data, data_len, parent, children, found, fragment) end
    else if xml_name_eq(data, name_offset, name_len, _tag_body, 4) then let
      val () = _root_lang(doc, data, attrs)
    in _render_nodes(doc, data, data_len, parent, children, found, fragment) end
    (* Void: br, hr, img *)
    else if xml_name_eq(data, name_offset, name_len, _tag_br, 2) then let
      val () = _add_node(doc, parent, _next_content_node(), $D.Br)
    in found end
    else if xml_name_eq(data, name_offset, name_len, _tag_hr, 2) then let
      val () = _add_node(doc, parent, _next_content_node(), $D.Hr)
    in found end
    else if xml_name_eq(data, name_offset, name_len, _tag_img, 3) then let
      (* An image: shown once its bytes are read from the book
         (_load_images); until then its src is an empty data URL *)
      val content_node = _next_content_node()
      val () = _add_node(doc, parent, content_node, $D.Img)
      val () = _node_src_empty(doc, content_node)
      var _attr_alt = @[char][3]('a', 'l', 't')
      val () = (case+ find_attr(data, attrs, _attr_alt, 3) of
        | ~xspan_at(alt_start, alt_len) =>
          if alt_len < 65536 then _node_attr(doc, content_node, $D.Alt, data, alt_start, alt_len)
          else _node_attr(doc, content_node, $D.Alt, data, alt_start, _text_cut(data, alt_start, alt_len))
        | ~xspan_none() => _node_attr_literal(doc, content_node, $D.Alt, "image")): void
      var _attr_src = @[char][3]('s', 'r', 'c')
    in
      case+ find_attr(data, attrs, _attr_src, 3) of
      | ~xspan_at(src_start, src_len) => images_cons(content_node, src_start, src_len, found)
      | ~xspan_none() => found
    end
    (* An SVG <image> (a cover page's usual form): shown as an <img>,
       its source xlink:href, or href *)
    else if xml_name_eq(data, name_offset, name_len, _tag_image, 5) then let
      val content_node = _next_content_node()
      val () = _add_node(doc, parent, content_node, $D.Img)
      val () = _node_src_empty(doc, content_node)
      val () = _node_attr_literal(doc, content_node, $D.Alt, "image")
      var _attr_xlink_href = @[char][10]('x', 'l', 'i', 'n', 'k', ':', 'h', 'r', 'e', 'f')
      var _attr_href = @[char][4]('h', 'r', 'e', 'f')
    in
      case+ find_attr(data, attrs, _attr_xlink_href, 10) of
      | ~xspan_at(src_start, src_len) => images_cons(content_node, src_start, src_len, found)
      | ~xspan_none() => (case+ find_attr(data, attrs, _attr_href, 4) of
        | ~xspan_at(src_start, src_len) => images_cons(content_node, src_start, src_len, found)
        | ~xspan_none() => found)
    end
    else let
      val content_node = _next_content_node()
      val () = _add_node(doc, parent, content_node, _tag_of(data, name_offset, name_len))
      val () = _fragment_check(data, attrs, fragment, content_node)
      val () = _pass_attrs(doc, data, attrs, content_node)
      val () = _break_check(data, attrs, content_node)
      var _tag_ruby = @[char][4]('r', 'u', 'b', 'y')
      val () = (if xml_name_eq(data, name_offset, name_len, _tag_ruby, 4) then _ruby_mark() else ())
      var _tag_a = @[char][1]('a')
    in
      if xml_name_eq(data, name_offset, name_len, _tag_a, 1) then let
        val found = _render_nodes(doc, data, data_len, content_node, children, found, fragment)
      in _link(doc, data, attrs, content_node, !_content_count, found) end
      else _render_nodes(doc, data, data_len, content_node, children, found, fragment)
    end
  end

(* The length of the directory part of the name [name_offset, name_offset + name_len) of the
   file: up to and including its last '/', 0 when it has none *)
fn _opf_prefix_len {file_size:pos}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
  (serial: int, file_size: int file_size, name_offset: int name_offset, name_len: int name_len): [dir_len:nat | dir_len <= name_len] int dir_len = let
  val buf = $A.alloc<byte>(name_len)
  val _ = book_read(serial, file_size, name_offset, buf, name_len)
  val dir_len = path_dir_end(buf, name_len)
  val () = $A.free<byte>(buf)
in dir_len end

(* ============================================================
   Images: read from the book, shown in the chapter's <img> elements
   ============================================================ *)

(* Counts chapter loads: an image whose bytes arrive after another
   chapter began loading is not shown (its element is gone) *)
val _load_generation = ref<int>(0)

(* The image viewer's image's id, "image-full" *)
fn _viewer_id (): [l:agz][id_len:pos | id_len <= 16] @($A.arr(byte, l, id_len), int id_len) = let
  val id = $A.alloc<byte>(10)
  val () = $A.write_text(id, 0, $A.text_lit("image-full"), 10)
in @(id, 10) end

(* The id of the image an image's bytes go to: the content node's, or
   the viewer's *)
fn _src_id {node:nat} (node: int node, in_viewer: bool): [l:agz][id_len:pos | id_len <= 16] @($A.arr(byte, l, id_len), int id_len) =
  if in_viewer then _viewer_id() else _number_id("c", node, 3)

(* The images of the chapter shown: each one's content node and the
   path of its entry in the book, path[0, path_len) *)
datavtype pictures(int) =
  | pictures_nil(0) of ()
  | {count:nat}{l:agz}{path_len:pos | path_len < 65536} pictures_cons(count + 1) of (int, $A.arr(byte, l, path_len), int path_len, pictures(count))

fun pictures_free {count:nat} .<count>. (entries: pictures(count)): void =
  case+ entries of
  | ~pictures_nil() => ()
  | ~pictures_cons(_, path, _, rest) => let val () = $A.free<byte>(path) in pictures_free(rest) end

datavtype pictures_cell = {count:nat} PicturesCell of pictures(count)

val _pictures = ref<pictures_cell>(PicturesCell(pictures_nil()))

fn _pictures_take (): pictures_cell = let
  var cell: pictures_cell = PicturesCell(pictures_nil())
  val () = ref_exch_elt<pictures_cell>(_pictures, cell)
in cell end

fn _pictures_put (new_cell: pictures_cell): void = let
  var cell: pictures_cell = new_cell
  val () = ref_exch_elt<pictures_cell>(_pictures, cell)
  val+ ~PicturesCell(old) = cell
in pictures_free(old) end

fn _pictures_push {l:agz}{path_len:pos | path_len < 65536} (node: int, path: $A.arr(byte, l, path_len), path_len: int path_len): void = let
  val+ ~PicturesCell(rest) = _pictures_take()
in _pictures_put(PicturesCell(pictures_cons(node, path, path_len, rest))) end

(* A content node's image (or the viewer's, when in_viewer): the n bytes of
   data, of type mime *)
fn _set_src {node:nat}{l:agz}{n:pos}{mime_len:pos | mime_len <= 24}
  (node: int node, in_viewer: bool, data: !$A.borrow(byte, l, n), n: int n, mime: string mime_len): void = let
  val mime_len = g1u2i(string1_length(mime))
  val mime_buf = $A.alloc<byte>(mime_len)
  val _ = _put(mime_buf, 0, mime)
  val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime_buf)
  (* the content node's image, or the image viewer's (image-full) *)
  val @(image_id, image_id_len) = _src_id(node, in_viewer)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(image_id)
  val () = $BDOM.set_image_src(id_bytes, image_id_len, data, n, mime_bytes, mime_len)
  val () = release_bytes(id_frozen, id_bytes)
in release_bytes(mime_frozen, mime_bytes) end

(* A content node's image, the entry named path[0, path_len) of the book's
   file_size-byte file (book serial): shown now when it is stored, once decompressed when it
   is deflated (unless chapter load generation is no longer the latest); not at
   all when it is missing *)
fn _show_image {file_size:pos}{node:nat}{l:agz}{path_len:pos}
  (serial: int, file_size: int file_size, node: int node, in_viewer: bool, generation: int,
   path: !$A.borrow(byte, l, path_len), path_len: int path_len): void = let
  val mime = mime_of(path, path_len)
in
  case+ book_zip_read(serial, file_size, path, path_len) of
  | ~ZipMissing() => ()
  | ~ZipGot(owner, compressed, compressed_size, method, _, _, _) =>
    if method = 0 then let
      val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
      val () = _set_src(node, in_viewer, compressed_bytes, compressed_size, mime)
      val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
    in piece_free(owner, $A.thaw<byte>(compressed_frozen)) end
    else let
      val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
      val decompressing = decompress(compressed_bytes, compressed_size, zip_compression(method))
      val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
      val () = piece_free(owner, $A.thaw<byte>(compressed_frozen))
      val decompressing = $P.vow(decompressing)
    in
      (* an image that cannot be read stays empty, as a browser leaves an
         image it cannot load: a book's images are decorative (alt="") *)
      $P.finish<Int>(decompressing, llam(handle) =>
        case+ take_content(handle) of
        | ~NoContentBytes() => ()
        | ~ContentBytes(content_owner, content, content_len) => let
            val @(content_frozen, content_bytes) = $A.freeze<byte>(content)
            val () = (if !_load_generation = generation then _set_src(node, in_viewer, content_bytes, content_len, mime) else ())
            val () = $A.drop<byte>(content_frozen, content_bytes)
          in piece_free(content_owner, $A.thaw<byte>(content_frozen)) end)
    end
end

(* The image of a content node, whose src is data[src_start, src_start + src_len): the
   entry that src names relative to the chapter's directory (the first
   dir_len bytes of the chapter's name, at name_offset in the file) *)
fn _load_image {file_size:pos}{name_offset,dir_len:nat | name_offset + dir_len <= file_size; dir_len < 65536}{l:agz}{n:pos}{src_start,src_len:nat | src_start + src_len <= n}{node:nat}
  (serial: int, file_size: int file_size, name_offset: int name_offset, dir_len: int dir_len,
   data: !$A.borrow(byte, l, n), n: int n, node: int node, src_start: int src_start, src_len: int src_len, generation: int): void = let
  val path_end = src_end(data, src_start, src_len)
in
  (* An src of 65536 bytes or more names no zip entry (a zip name is
     shorter): the book's data, checked here *)
  if path_end <= 0 then ()
  else if path_end >= 65536 then ()
  else let
    val joined_len = dir_len + path_end
    val buf = $A.alloc<byte>(joined_len)
    val _ = book_read(serial, file_size, name_offset, buf, dir_len)
    val () = $S.copy_from_borrow(data, src_start, n, buf, dir_len, joined_len, path_end)
    val path_len = path_norm(buf, joined_len)
  in
    if path_len <= 0 then $A.free<byte>(buf)
    else let
      val exact = $A.alloc<byte>(path_len)
      val buf = $S.copy_arr_region(buf, 0, joined_len, exact, path_len, path_len)
      val () = $A.free<byte>(buf)
      val @(path_frozen, path_bytes) = $A.freeze<byte>(exact)
      val () = _show_image(serial, file_size, node, false, generation, path_bytes, path_len)
      val () = $A.drop<byte>(path_frozen, path_bytes)
      (* kept, so the image can be shown again in the viewer *)
    in if path_len < 65536 then _pictures_push(node, $A.thaw<byte>(path_frozen), path_len) else $A.free<byte>($A.thaw<byte>(path_frozen)) end
  end
end

(* The length of the fragment after the '#' at path_end of an href of href_len
   bytes: 0 when there is none, or it is over 200 bytes *)
fn _fragment_len {href_len,path_end:nat | path_end <= href_len} (href_len: int href_len, path_end: int path_end): [fragment_len:nat | fragment_len <= 200; fragment_len == 0 || fragment_len == href_len - path_end - 1] int fragment_len =
  if href_len - path_end - 1 <= 0 then 0
  else if href_len - path_end - 1 > 200 then 0
  else href_len - path_end - 1

(* fragment[0, fragment_len) := data[href_start + path_end + 1, href_start + path_end + 1 + fragment_len) *)
fn _fragment_copy {data_location,fragment_location:agz}{data_size:pos}{href_start,path_end,fragment_len:nat | fragment_len == 0 || href_start + path_end + 1 + fragment_len <= data_size}
  (data: !$A.borrow(byte, data_location, data_size), data_size: int data_size, href_start: int href_start, path_end: int path_end, fragment: !$A.arr(byte, fragment_location, fragment_len + 1), fragment_len: int fragment_len): void =
  if fragment_len > 0 then $S.copy_from_borrow(data, href_start + path_end + 1, data_size, fragment, 0, fragment_len + 1, fragment_len) else ()

(* The link to data[href_start, href_start + href_len) from content nodes [first_node, end_node) of chapter
   current, whose directory is the first dir_len bytes of the name at name_offset: kept
   with the chapter and fragment it leads to *)
fn _link_resolve {file_size:pos}{name_offset,dir_len:nat | name_offset + dir_len <= file_size; dir_len < 65536}{l:agz}{n:pos}{href_start,href_len:nat | href_start + href_len <= n}
  (serial: int, file_size: int file_size, name_offset: int name_offset, dir_len: int dir_len, current: Int,
   data: !$A.borrow(byte, l, n), n: int n, first_node: Int, end_node: Int, href_start: int href_start, href_len: int href_len, note: bool): void = let
  val path_end = src_end(data, href_start, href_len)
  val chapter = (if path_end <= 0 then current
    else (case+ book_find_relative(serial, file_size, name_offset, dir_len, data, n, href_start, path_end) of
      | ~EntryHit(_, _, _, entry_name_offset, _) => book_chapter_of(serial, entry_name_offset)
      | ~EntryMiss() => ~1)): Int
  val fragment_len = _fragment_len(href_len, path_end)
  val fragment = $A.alloc<byte>(fragment_len + 1)
  val () = _fragment_copy(data, n, href_start, path_end, fragment, fragment_len)
in
  if chapter >= 0 then _links_push(first_node, end_node, chapter, fragment, fragment_len, note) else $A.free<byte>(fragment)
end

(* The images found of the chapter data[0, n), chapter current, and its links *)
fun _load_images {file_size:pos}{name_offset,dir_len:nat | name_offset + dir_len <= file_size; dir_len < 65536}{l:agz}{n:pos}{count:nat} .<count>.
  (serial: int, file_size: int file_size, name_offset: int name_offset, dir_len: int dir_len,
   data: !$A.borrow(byte, l, n), n: int n, found: images(n, count), generation: int, current: Int): void =
  case+ found of
  | ~images_nil() => ()
  | ~images_cons(node, src_start, src_len, rest) => let
      val () = _load_image(serial, file_size, name_offset, dir_len, data, n, node, src_start, src_len, generation)
    in _load_images(serial, file_size, name_offset, dir_len, data, n, rest, generation, current) end
  | ~images_link(first_node, end_node, src_start, src_len, note, rest) => let
      val () = _link_resolve(serial, file_size, name_offset, dir_len, current, data, n, first_node, end_node, src_start, src_len, note)
    in _load_images(serial, file_size, name_offset, dir_len, data, n, rest, generation, current) end

(* The chapters from spine itemref item down to the first, onto found: each
   href, after the OPF's directory (prefix_len bytes of the name at
   opf_name_offset), found in book serial's index; the OPF's data checked here, once *)
fun _spine_chapters {file_size:pos}{opf_name_offset:nat}{prefix_len:nat | opf_name_offset + prefix_len <= file_size; prefix_len < 65536}
  {l:agz}{n:pos}{tree_size:nat}{item:int | item >= ~1}{found_count:nat} .<item + 1>.
  (serial: int, file_size: int file_size, opf_name_offset: int opf_name_offset, prefix_len: int prefix_len,
   opf_bytes: !$A.borrow(byte, l, n), opf_size: int n, nodes: !$X.xml_node_list(n, tree_size),
   item: int item, found: book_chapters(file_size, found_count)): book_chapters(file_size, found_count + item + 1) =
  if item < 0 then found
  else let
    val chapters = (case+ find_chapter_href_n(opf_bytes, opf_size, nodes, item) of
      | ~xspan_none() => ChapterMissing(found)
      | ~xspan_at(href_offset, href_len) =>
        if href_len <= 0 then ChapterMissing(found)
        else if prefix_len + href_len > 1048576 then ChapterMissing(found)
        else let
          val path_len = prefix_len + href_len
          val path_buf = $A.alloc<byte>(path_len)
          (* The prefix read from the file at the OPF's name, then the
             chapter href from the OPF *)
          val _ = book_read(serial, file_size, opf_name_offset, path_buf, prefix_len)
          val () = $S.copy_from_borrow(opf_bytes, href_offset, opf_size,
                    path_buf, prefix_len, path_len, href_len)
          val @(path_frozen, path_bytes) = $A.freeze<byte>(path_buf)
          val hit = book_find_entry(serial, file_size, path_bytes, path_len)
          val () = release_bytes(path_frozen, path_bytes)
        in
          case+ hit of
          | ~EntryMiss() => ChapterMissing(found)
          | ~EntryHit(data_start, compressed_size, method, name_offset, name_len) =>
              Chapter(data_start, compressed_size, method, name_offset, name_len, _opf_prefix_len(serial, file_size, name_offset, name_len), found)
        end): book_chapters(file_size, found_count + 1)
  in _spine_chapters(serial, file_size, opf_name_offset, prefix_len, opf_bytes, opf_size, nodes, item - 1, chapters) end

(* ============================================================
   The book's own font, for the "Book" font setting
   ============================================================ *)


(* The book's language (its OPF's dc:language), when it is a plausible
   language tag: 1 to 35 letters, digits and hyphens *)
datavtype book_lang =
  | {l:agz}{lang_len:pos | lang_len <= 35} BookLang of ($A.arr(byte, l, 35), int lang_len)
  | NoBookLang of ()

val _book_lang = ref<book_lang>(NoBookLang())

fn _book_lang_put (lang: book_lang): void = let
  var cell: book_lang = lang
  val () = ref_exch_elt<book_lang>(_book_lang, cell)
in case+ cell of ~BookLang(tag, _) => $A.free<byte>(tag) | ~NoBookLang() => () end

fn _book_lang_take (): book_lang = let
  var cell: book_lang = NoBookLang()
  val () = ref_exch_elt<book_lang>(_book_lang, cell)
in cell end

(* lang[j, lang_len) := data[offset + j, offset + lang_len) *)
fun _lang_copy {data_location,lang_location:agz}{data_size:pos}{offset,lang_len:nat | offset + lang_len <= data_size; lang_len <= 35}{j:nat | j <= lang_len} .<lang_len - j>.
  (data: !$A.borrow(byte, data_location, data_size), offset: int offset, lang: !$A.arr(byte, lang_location, 35), lang_len: int lang_len, j: int j): void =
  if j >= lang_len then ()
  else let
    val () = $A.set<byte>(lang, j, $A.read<byte>(data, offset + j))
  in _lang_copy(data, offset, lang, lang_len, j + 1) end

(* Keeps the book's language, from its OPF opf_bytes's nodes *)
fn _lang_locate {l:agz}{n:pos}{tree_size:nat}
  (opf_bytes: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): void =
  case+ opf_language(opf_bytes, nodes) of
  | ~xspan_none() => _book_lang_put(NoBookLang())
  | ~xspan_at(offset, lang_len) =>
    if _lang_ok(opf_bytes, offset, lang_len) then
      (if lang_len >= 1 then (if lang_len <= 35 then let
         val lang = $A.alloc<byte>(35)
         val () = _lang_copy(opf_bytes, offset, lang, lang_len, 0)
       in _book_lang_put(BookLang(lang, lang_len)) end
       else _book_lang_put(NoBookLang()))
       else _book_lang_put(NoBookLang()))
    else _book_lang_put(NoBookLang())

(* The page's lang, before a chapter is shown: the book's, else "und"
   (undetermined: the app's own "en" is not the book's) *)
fn _page_book_lang {doc_location:agz} (doc: !$D.document(doc_location)): void =
  case+ _book_lang_take() of
  | ~NoBookLang() => let
      val undetermined = $A.alloc<byte>(3)
      val () = $A.write_text(undetermined, 0, $A.text_lit("und"), 3)
      val @(undetermined_frozen, undetermined_bytes) = $A.freeze<byte>(undetermined)
      val () = _page_lang(doc, undetermined_bytes, 0, 3)
      val () = release_bytes(undetermined_frozen, undetermined_bytes)
    in _book_lang_put(NoBookLang()) end
  | ~BookLang(lang, lang_len) => let
      val @(lang_frozen, lang_bytes) = $A.freeze<byte>(lang)
      val () = _page_lang(doc, lang_bytes, 0, lang_len)
      val () = $A.drop<byte>(lang_frozen, lang_bytes)
    in _book_lang_put(BookLang($A.thaw<byte>(lang_frozen), lang_len)) end

datavtype font_source =
  | {file_size:pos}{data_start:nat}{compressed_size:pos | data_start + compressed_size <= file_size; compressed_size <= 268435456}{method:int | method == 0 || method == 8}
    FontSource of (int file_size, int data_start, int compressed_size, int method)
  | FontNone of ()

val _font = ref<font_source>(FontNone())

fn _font_put (font: font_source): void = let
  var cell: font_source = font
  val () = ref_exch_elt<font_source>(_font, cell)
in case+ cell of ~FontSource(_, _, _, _) => () | ~FontNone() => () end

fn _font_take (): font_source = let
  var cell: font_source = FontNone()
  val () = ref_exch_elt<font_source>(_font, cell)
in cell end

(* The book's first embedded font, named in the OPF opf_bytes[0, n) (whose
   directory is the first dir_len bytes of the name at opf_name_offset) *)
fn _font_locate {file_size:pos}{opf_name_offset:nat}{dir_len:nat | opf_name_offset + dir_len <= file_size; dir_len < 65536}{l:agz}{n:pos}{tree_size:nat}
  (serial: int, file_size: int file_size, opf_name_offset: int opf_name_offset, dir_len: int dir_len,
   opf_bytes: !$A.borrow(byte, l, n), n: int n, nodes: !$X.xml_node_list(n, tree_size)): void =
  case+ find_font_href(opf_bytes, nodes) of
  | ~xspan_none() => _font_put(FontNone())
  | ~xspan_at(href_start, href_len) =>
    (case+ book_find_relative(serial, file_size, opf_name_offset, dir_len, opf_bytes, n, href_start, href_len) of
     | ~EntryHit(data_start, compressed_size, method, _, _) => _font_put(FontSource(file_size, data_start, compressed_size, method))
     | ~EntryMiss() => _font_put(FontNone()))

(* target[at + j, at + source_len) := source[j, source_len) *)
fun _copy_at {source_location,target_location:agz}{source_size,target_size:pos}{at:nat}{source_len:nat | source_len <= source_size; at + source_len <= target_size}{j:nat | j <= source_len} .<source_len - j>.
  (source: !$A.arr(byte, source_location, source_size), target: !$A.arr(byte, target_location, target_size), at: int at, source_len: int source_len, j: int j): void =
  if j >= source_len then ()
  else let
    val () = $A.set<byte>(target, at + j, $A.get<byte>(source, j))
  in _copy_at(source, target, at, source_len, j + 1) end

(* The style that names the font at the blob URL url[0, url_len) QuireBook, the
   family the "Book" setting asks for *)
fn _font_style {url_len:pos | url_len < 2000}{l:agz}{url_size:pos | url_len <= url_size} (url: !$A.arr(byte, l, url_size), url_len: int url_len): void = let
  val style_len = url_len + 80
  val style = $A.alloc<byte>(style_len)
  val offset = _put(style, 0, "@font-face{font-family:QuireBook;src:url(")
  val () = _copy_at(url, style, offset, url_len, 0)
  val offset = _put(style, offset + url_len, ")}.caf{--bookfont:QuireBook}")
in ui_text_buf("style-fonts", style, offset) end

(* Makes the font found by _font_locate the book font (or none) *)
fn _font_load (serial: int): $P.promise(int, $P.Chained) = let
  val () = ui_clear("style-fonts")
in
  case+ _font_take() of
  | ~FontNone() => $P.ret<int>(0)
  | ~FontSource(file_size, data_start, compressed_size, method) =>
    (case+ piece_new(compressed_size) of
     | ~NoPiece() => $P.ret<int>(0)
     | ~Piece(compressed_owner, compressed) => let
         val _ = book_read(serial, file_size, data_start, compressed, compressed_size)
         val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
         val decompressing = decompress(compressed_bytes, compressed_size, zip_compression(method))
         val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
         val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
       in
         $P.and_then<Int><int>($P.vow(decompressing), llam(handle) =>
           case+ take_content(handle) of
           | ~NoContentBytes() => $P.ret<int>(0)
           | ~ContentBytes(font_owner, font, font_len) => let
               val mime_buf = $A.alloc<byte>(8)
               val _ = _put(mime_buf, 0, "font/otf")
               val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime_buf)
               val @(font_frozen, font_bytes) = $A.freeze<byte>(font)
               val url_made = $BL.create_blob_url(font_bytes, font_len, mime_bytes, 8)
               val () = $A.drop<byte>(font_frozen, font_bytes)
               val () = piece_free(font_owner, $A.thaw<byte>(font_frozen))
               val () = release_bytes(mime_frozen, mime_bytes)
               val () = (case+ url_made of
                 | ~$R.none() => ()
                 | ~$R.some(url_blob) => let
                     val url_len = $BD.blob_len(url_blob)
                   in
                     (* the host's URL, checked here *)
                     if url_len <= 0 then $BD.blob_free(url_blob)
                     else if url_len >= 2000 then $BD.blob_free(url_blob)
                     else let
                       val url = $A.alloc<byte>(url_len)
                       val () = $BD.blob_read(url_blob, 0, url, url_len)
                       val () = $BD.blob_free(url_blob)
                       val () = _font_style(url, url_len)
                     in $A.free<byte>(url) end
                   end)
             in $P.ret<int>(0) end)
       end)
end

(* Finds book s's chapters from its OPF and keeps them in the book: its
   chapter count, or below 0 when the OPF cannot be read *)
fn _spine_build (serial: int): $P.promise(int, $P.Chained) =
  case+ book_meta_get() of
  | ~$R.none() => $P.ret<int>(~1)
  | ~$R.some(@(file_size, opf_data_start, opf_compressed_size, opf_method, opf_name_offset, opf_name_len)) =>
    (* The OPF's compressed bytes, read at their span into a piece *)
    (case+ piece_new(opf_compressed_size) of
     | ~NoPiece() => $P.ret<int>(~1)
     | ~Piece(compressed_owner, opf_compressed) => let
         val _ = book_read(serial, file_size, opf_data_start, opf_compressed, opf_compressed_size)
         val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(opf_compressed)
         val decompressing = decompress(compressed_bytes, opf_compressed_size, zip_compression(opf_method))
         val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
         val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
         val decompressing = $P.vow(decompressing)
       in
         $P.and_then<Int><int>(decompressing, llam(handle) =>
           case+ take_content(handle) of
           | ~NoContentBytes() => $P.ret<int>(~2)
           | ~ContentBytes(opf_owner, opf_buf, opf_size) => let
               val @(opf_frozen, opf_bytes) = $A.freeze<byte>(opf_buf)
               val opf_nodes = $X.parse_document(opf_bytes, opf_size)
               val total = count_spine_items(opf_bytes, opf_nodes)
               (* The OPF's directory, e.g. "OEBPS/" of "OEBPS/content.opf",
                  prefixes chapter hrefs *)
               val prefix_len = _opf_prefix_len(serial, file_size, opf_name_offset, opf_name_len)
               val chapters = _spine_chapters(serial, file_size, opf_name_offset, prefix_len,
                           opf_bytes, opf_size, opf_nodes, total - 1, ChaptersNil())
               val () = book_spine_set(serial, file_size, chapters, total)
               val () = toc_locate(serial, file_size, opf_name_offset, prefix_len, opf_bytes, opf_size, opf_nodes)
               val () = !_right_to_left := spine_rtl(opf_bytes, opf_nodes)
               val () = _lang_locate(opf_bytes, opf_nodes)
               val () = _font_locate(serial, file_size, opf_name_offset, prefix_len, opf_bytes, opf_size, opf_nodes)
               val () = $X.free_nodes(opf_nodes)
               val () = $A.drop<byte>(opf_frozen, opf_bytes)
               val () = piece_free(opf_owner, $A.thaw<byte>(opf_frozen))
             in $P.ret<int>(total) end)
       end)

(* Shows chapter chapter_index of book serial, from its chapters *)
fn _chapter_open {chapter_index:nat} (serial: int, chapter_index: int chapter_index, generation: int): $P.promise(int, $P.Chained) =
  case+ book_chapter_get(serial, chapter_index) of
  | ~ChaptersUnknown() => $P.ret<int>(~1)
  | ~ChapterNone(chapter_count) => let
      val () = (case+ reading_get() of
        | @(page, page_count, chapter, _) => reading_set(@(page, page_count, chapter, chapter_count)))
    in $P.ret<int>(~4) end
  | ~ChapterGot(file_size, chapter_start, compressed_size, method, chapter_name_offset, _, dir_len, chapter_count) => let
      val () = (case+ reading_get() of
        | @(page, page_count, chapter, _) => reading_set(@(page, page_count, chapter, chapter_count)))
    in
      case+ piece_new(compressed_size) of
      | ~NoPiece() => $P.ret<int>(~5)
      | ~Piece(compressed_owner, compressed) => let
              val _ = book_read(serial, file_size, chapter_start, compressed, compressed_size)
              val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
              val decompressing = decompress(compressed_bytes, compressed_size, zip_compression(method))
              val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
              val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))

              val decompressing = $P.vow(decompressing)
            in
              (* Stage 3: parse HTML and render *)
              $P.and_then<Int><int>(decompressing, llam(handle) => let
                val content = take_content(handle)
              in
                case+ content of
                | ~NoContentBytes() => $P.ret<int>(~6)
                | ~ContentBytes(xhtml_owner, xhtml, xhtml_size) => let

                  (* Parse XHTML with xml-tree *)
                  val @(xhtml_frozen, xhtml_bytes) = $A.freeze<byte>(xhtml)
                  val nodes = $X.parse_document(xhtml_bytes, xhtml_size)

                  (* Clear the content area, then render the XHTML tree
                     into it: one document for the chapter *)
                  val doc = $D.open_document($A.text_lit("bats-root"), 9)
                  val @(page_id, page_id_len) = _node_id(~1)
                  val @(page_id_frozen, page_id_bytes) = $A.freeze<byte>(page_id)
                  val () = $D.remove_children(doc, page_id_bytes, page_id_len)
                  val () = release_bytes(page_id_frozen, page_id_bytes)
                  val () = !_content_count := 0
                  val () = _links_put(LinksCell(links_nil()))
                  val () = _pictures_put(PicturesCell(pictures_nil()))
                  val () = _breaks_put(BreaksCell(breaks_nil()))
                  val () = (if !_right_to_left then ui_attr("page", AClass, "caf rtl") else ui_attr("page", AClass, "caf"))
                  val () = _page_book_lang(doc)
                  val fragment = _fragment_take()
                  val found = _render_nodes(doc, xhtml_bytes, xhtml_size, ~1, nodes, images_nil(), fragment)
                  val () = _fragment_put(fragment)
                  val () = $D.destroy(doc)
                  val () = $X.free_nodes(nodes)
                  (* Its images, named relative to the chapter's directory *)
                  val () = _load_images(serial, file_size, chapter_name_offset, dir_len, xhtml_bytes, xhtml_size, found, generation, chapter_index)
                  val () = $A.drop<byte>(xhtml_frozen, xhtml_bytes)
                  val () = piece_free(xhtml_owner, $A.thaw<byte>(xhtml_frozen))

                  val () = (case+ reading_get() of
                    | @(page, page_count, _, chapter_count) => reading_set(@(page, page_count, chapter_index + 1, chapter_count)))
                  (* The chapter's title in the top bar *)
                  val () = toc_title(chapter_index)
                  val () = (case+ reading_get() of @(_, _, _, chapter_count) => _ticks_show(chapter_count))
                  val () = _measure_pagination()
                  val () = annot_marks()
                in $P.ret<int>(0) end
              end)
            end
    end

(* Loads chapter chapter_index: first the book's chapters, from its OPF,
   when they are not found yet *)
fn _load_chapter {chapter_index:nat} (chapter_index: int chapter_index): $P.promise(int, $P.Chained) = let
  val serial = book_serial()
  val () = !_load_generation := !_load_generation + 1
  val generation = !_load_generation
in
  case+ book_chapter_get(serial, chapter_index) of
  | ~ChaptersUnknown() =>
    $P.and_then<int><int>(_spine_build(serial), llam(result) =>
      if result < 0 then $P.ret<int>(result)
      else $P.and_then<int><int>(toc_build(serial), llam(_) =>
        $P.and_then<int><int>(_font_load(serial), llam(_) => _chapter_open(serial, chapter_index, generation))))
  | ~ChapterNone(_) => _chapter_open(serial, chapter_index, generation)
  | ~ChapterGot(_, _, _, _, _, _, _, _) => _chapter_open(serial, chapter_index, generation)
end

(* Shows the page of the chapter just loaded that target names: the
   page content node anchor is on (anchor >= 0), else page page (the last
   when page is -1 or past the chapter's end) *)
fn _show_target (page: Int, anchor: Int): void =
  case+ reading_get() of
  | @(current, page_count, chapter, chapter_count) =>
    (* scrolled, the node itself at the top of the screen *)
    if anchor >= 0 then (if _scrolled() then let
        val @(offset, bottom) = _node_down_by(anchor, current)
      in
        if offset < 0 then _show_page(current, page_count, chapter, chapter_count)
        else _show_page_down(_screen_at(offset, bottom, page_count), page_count, chapter, chapter_count, (if offset < bottom then offset else bottom))
      end
      else _show_page(_page_of_node(anchor, page_count, current), page_count, chapter, chapter_count))
    else if page < 0 then _show_page(page_count - 1, page_count, chapter, chapter_count)
    else if page >= page_count then _show_page(page_count - 1, page_count, chapter, chapter_count)
    else _show_page(page, page_count, chapter, chapter_count)

(* ============================================================
   Settling: a chapter's layout can still change after its page is
   shown (a font arriving, an image loading), and with it the page its
   place is on. For a while after, the pages are counted again, and when
   they changed the place is found again: by the node the reader was
   taken to, until the reader turns a page
   ============================================================ *)

(* The node the place was restored to, or -1 once a page is turned *)
val _settle_anchor = ref<Int>(~1)
val _settle_generation = ref<int>(0)

(* What keeps the reader's place on page page of total when the chapter
   is laid out again, as _show_target takes it (a page, a node): the
   node the place was restored to, while it holds; scrolled, the
   chapter's end for a reader on its last screen past the first (the
   browser stops that screen short of a whole step, so the node at its
   top starts on the screen before); else the node at the page's top *)
fn _place_kept (page: Int, total: Int): @(Int, Int) =
  if !_settle_anchor >= 0 then @(page, !_settle_anchor)
  else if _scrolled() && page > 0 && page >= total - 1 then @(~1, ~1)
  else @(page, !_anchor_last)

(* How many pages the chapter has now, as it is laid out *)
fn _pages_now (): Int = let
  val () = _measure_literal("page")
  val page_width = $DR.get_measure_w()
in if page_width > 0 then _count_pages() else ~1 end

(* Every quarter second, so many more times, while no other chapter has been
   shown since (generation) *)
fun _settle {times:nat} .<times>. (generation: int, times: int times): void =
  if times <= 0 then ()
  else $P.finish<Int>($P.vow($TM.timer_set(250)), llam(_) =>
    if generation <> !_settle_generation then ()
    else let
      val () = (case+ reading_get() of
        | @(page, page_count, _, _) => let
            val count_now = _pages_now()
            val anchor = !_settle_anchor
            (* the node the reader was taken to, if it is no longer on
               the page shown *)
            val moved = (if anchor < 0 then false else if page >= page_count then false
              else _page_of_node(anchor, page_count, page) <> page): bool
          in
            if count_now <= 0 then ()
            else if count_now <> page_count then let
              val @(target_page, target_anchor) = _place_kept(page, page_count)
              val () = _measure_pagination()
            in _show_target(target_page, target_anchor) end
            else if moved then _show_target(page, anchor)
            else ()
          end)
    in _settle(generation, times - 1) end)

(* Starts settling the page just shown, which anchor (when >= 0) is on *)
fn _settle_start (anchor: Int): void = let
  val () = !_settle_anchor := anchor
  val () = !_settle_generation := !_settle_generation + 1
in _settle(!_settle_generation, 12) end

(* Loads a chapter (from 0) and shows its page, or the page of
   content node anchor (see _show_target); the promise resolves with 0,
   or below 0 when the chapter cannot be shown *)
fn _goto (chapter: Int, page: Int, anchor: Int): $P.promise(int, $P.Chained) = let
  val chapter = (if chapter >= 0 then chapter else 0): [chapter:nat] int chapter
in
  $P.and_then<int><int>(_load_chapter(chapter), llam(result) =>
    if result < 0 then $P.ret<int>(result)
    else let
      val () = _show_target(page, anchor)
      val () = _settle_start(anchor)
    in $P.ret<int>(0) end)
end

(* Loads a chapter and shows the page of its element whose id is
   fragment[0, fragment_len) (the first page when there is none); frees fragment *)
fn _goto_fragment {l:agz}{n:pos}{fragment_len:nat | fragment_len < n} (chapter: Int, fragment: $A.arr(byte, l, n), fragment_len: int fragment_len): $P.promise(int, $P.Chained) =
  if fragment_len <= 0 then let
    val () = $A.free<byte>(fragment)
  in _goto(chapter, 0, ~1) end
  else let
    val () = _fragment_put(FragmentSome(fragment, fragment_len))
    val () = !_fragment_node := ~1
    val chapter = (if chapter >= 0 then chapter else 0): [chapter:nat] int chapter
  in
    $P.and_then<int><int>(_load_chapter(chapter), llam(result) => let
      val () = _fragment_put(FragmentNone())
    in
      if result < 0 then $P.ret<int>(result)
      else let
        val anchor = !_fragment_node
        val () = _show_target(0, anchor)
        val () = _settle_start(anchor)
      in $P.ret<int>(0) end
    end)
  end

(* Ends a jump (or a turn into another chapter): when the chapter could
   not be shown (its result is below 0), the reader stays on the page it
   was on, shown again (a drag may have moved it), never a blank one,
   and the banner says why *)
fn _jump_checked (jumping: $P.promise(int, $P.Chained)): void =
  $P.finish<int>(jumping, llam(result) =>
    if result >= 0 then ()
    else let
      val () = (case+ reading_get() of
        | @(page, page_count, chapter, chapter_count) =>
          if chapter > 0 then _show_page(page, page_count, chapter, chapter_count) else ())
    in notice_part_unread() end)

(* The positions jumped away from (a contents entry, a link, a search
   result), the latest first: the back button returns to them *)
datavtype pstack(int) =
  | ps_nil(0) of ()
  | {count:nat} ps_cons(count + 1) of (Int, Int, Int, pstack(count))

fun ps_free {count:nat} .<count>. (positions: pstack(count)): void =
  case+ positions of
  | ~ps_nil() => ()
  | ~ps_cons(_, _, _, rest) => ps_free(rest)

(* The first kept of positions *)
fun ps_keep {count:nat}{kept:nat} .<count>. (positions: pstack(count), kept: int kept): [kept_count:nat] pstack(kept_count) =
  case+ positions of
  | ~ps_nil() => ps_nil()
  | ~ps_cons(chapter, page, anchor, rest) =>
    if kept <= 0 then let val () = ps_free(rest) in ps_nil() end
    else ps_cons(chapter, page, anchor, ps_keep(rest, kept - 1))

(* How long the back button stays after a jump, in milliseconds *)
#define BACK_SHOWN 10000

(* TIMED(timeout): the timeout of that number is armed, which will run the
   action _timed_arm was given, with the number. Its constructor is local
   to _timed_arm, so nothing else can make one *)
local
dataprop TIMED_(int) = {timeout:int} TimedArmed(timeout) of ()
in
stadef TIMED = TIMED_

fn _timed_arm {timeout:int} (timeout: int timeout, done: (Int) -<lincloptr1> void): (TIMED(timeout) | void) = let
  val () = $P.finish<Int>($P.and_then<Int><Int>($P.vow($TM.timer_set(BACK_SHOWN)), llam(_) => $P.ret<Int>(timeout)), done)
in (TimedArmed() | ()) end
end

(* The back button, in the type of what holds it: hidden, and then no
   position is kept; or shown, with at least one position and the proof
   that the timeout of the number it holds is armed. So the button is
   never shown without a pending timeout that takes it away *)
datavtype ps_cell =
  | PsHidden of ()
  | {count:pos}{timeout:int} PsShown of (TIMED(timeout) | int timeout, pstack(count))

val _ps = ref<ps_cell>(PsHidden())

(* The number of the last timeout armed *)
val _ps_timed = ref<Int>(0)

fn _ps_free (cell: ps_cell): void =
  case+ cell of
  | ~PsHidden() => ()
  | ~PsShown(_ | _, positions) => ps_free(positions)

fn _ps_take (): ps_cell = let
  var cell: ps_cell = PsHidden()
  val () = ref_exch_elt<ps_cell>(_ps, cell)
in cell end

(* Keeps the cell, and shows the button or hides it as the cell says: the only place
   that shows or hides it *)
fn _ps_put (cell: ps_cell): void = let
  val shown = (case+ cell of PsHidden() => false | PsShown(_ | _, _) => true): bool
  var old: ps_cell = cell
  val () = ref_exch_elt<ps_cell>(_ps, old)
  val () = _ps_free(old)
in ui_show("jump-back", shown) end

(* A timeout has run: the button goes, with the positions it offered,
   when it is still the one timeout that was armed for *)
fn _back_timeout (timeout: Int): void = let
  val cell = _ps_take()
  val due = (case+ cell of PsHidden() => false | PsShown(_ | armed, _) => armed = timeout): bool
in
  if due then let
    val () = _ps_free(cell)
  in _ps_put(PsHidden()) end
  else _ps_put(cell)
end

(* Arms a new timeout for the button, which takes it away *)
fn _back_arm (): [timeout:int] (TIMED(timeout) | int timeout) = let
  val timeout = !_ps_timed + 1
  val () = !_ps_timed := timeout
  val (armed | ()) = _timed_arm(timeout, llam(fired) => _back_timeout(fired))
in (armed | timeout) end

(* Shows the button offering the positions, with a new timeout *)
fn _back_offer {count:pos} (positions: pstack(count)): void = let
  val (armed | timeout) = _back_arm()
in _ps_put(PsShown(armed | timeout, positions)) end

(* Remembers where the reader is, before a jump *)
fn _push_position (): void = let
  val anchor = _anchor_now()
  val cell = _ps_take()
  val positions = (case+ cell of
    | ~PsHidden() => ps_nil()
    | ~PsShown(_ | _, positions) => positions): [count:nat] pstack(count)
  val positions = (case+ reading_get() of
    | @(page, _, chapter, _) => ps_cons((if chapter > 0 then chapter - 1 else 0), page, anchor, ps_keep(positions, 29))): [count:pos] pstack(count)
in _back_offer(positions) end

(* Returns to the position last jumped away from; the button stays, with
   a new timeout, while there are more *)
fn _pop_position (): void = let
  val cell = _ps_take()
in
  case+ cell of
  | ~PsHidden() => _ps_put(PsHidden())
  | ~PsShown(_ | _, positions) => let
      val+ ~ps_cons(chapter, page, anchor, rest) = positions
      val () = (case+ rest of
        | ~ps_nil() => _ps_put(PsHidden())
        | ps_cons(_, _, _, _) => _back_offer(rest))
    in _jump_checked(_goto(chapter, page, anchor)) end
end

(* Loads a chapter and shows its page at a thousandth of it *)
fn _goto_part (chapter: Int, thousandth: Int): $P.promise(int, $P.Chained) = let
  val chapter = (if chapter >= 0 then chapter else 0): [chapter:nat] int chapter
in
  $P.and_then<int><int>(_load_chapter(chapter), llam(result) =>
    if result < 0 then $P.ret<int>(result)
    else let
      val () = (case+ reading_get() of
        | @(_, page_count, _, _) => _show_target(thousandth * page_count / 1000, ~1))
    in $P.ret<int>(0) end)
end

(* The next page: in this chapter, else the next chapter's first *)
fn _page_next(): void = let
  val () = !_settle_anchor := ~1
in
  case+ reading_get() of
  | @(page, page_count, chapter, chapter_count) =>
    if page + 1 < page_count then let val () = _speed_turn() in _show_page(page + 1, page_count, chapter, chapter_count) end
    else if chapter < chapter_count then let val () = _speed_turn() in _jump_checked(_goto(chapter, 0, ~1)) end
    else _show_page(page, page_count, chapter, chapter_count)
end

(* The previous page: in this chapter, else the previous chapter's last *)
fn _page_previous(): void = let
  val () = !_settle_anchor := ~1
in
  case+ reading_get() of
  | @(page, page_count, chapter, chapter_count) =>
    if page > 0 then _show_page(page - 1, page_count, chapter, chapter_count)
    else if chapter > 1 then _jump_checked(_goto(chapter - 2, ~1, ~1))
    else _show_page(0, page_count, chapter, chapter_count)
end

(* Lays the chapter out again (the window or the type changed), keeping
   the page on which the content at the page's top is *)
fn _relayout (): void = let
  val @(page, anchor) = (case+ reading_get() of @(current, page_count, _, _) => _place_kept(current, page_count)): @(Int, Int)
  val () = _measure_pagination()
in _show_target(page, anchor) end

(* ============================================================
   Search: every chapter's text, for the query
   ============================================================ *)

(* A search walks each chapter as _render_nodes shows it, numbering its
   content nodes the same way (the two must stay in step), and finds the
   query in each text node's text as the page shows it (its references
   decoded), letters in any case. A hit is its chapter, content node and
   offset, with the text around it. *)

#define HIT_MAX 500

datavtype hits(int) =
  | hits_nil(0) of ()
  | {count:nat}{l:agz}{snippet_len:nat | snippet_len <= 206}
    hits_cons(count + 1) of (Int, Int, Int, $A.arr(byte, l, snippet_len + 1), int snippet_len, hits(count))

fun hits_free {count:nat} .<count>. (entries: hits(count)): void =
  case+ entries of
  | ~hits_nil() => ()
  | ~hits_cons(_, _, _, snippet, _, rest) => let val () = $A.free<byte>(snippet) in hits_free(rest) end

fun hits_reverse {count,reversed_count:nat} .<count>. (remaining: hits(count), reversed: hits(reversed_count)): hits(count + reversed_count) =
  case+ remaining of
  | ~hits_nil() => reversed
  | ~hits_cons(chapter, node, offset, snippet, snippet_len, rest) => hits_reverse(rest, hits_cons(chapter, node, offset, snippet, snippet_len, reversed))

(* The hits so far (the latest first while a search runs), their count,
   the query query[0, query_len) (lower case) and the search's number *)
datavtype search_cell =
  | {hit_count:nat | hit_count <= HIT_MAX}{l:agz}{query_len:pos | query_len <= 200} SearchCell of (hits(hit_count), int hit_count, $A.arr(byte, l, query_len), int query_len)
  | SearchNone of ()

val _search = ref<search_cell>(SearchNone())
val _search_generation = ref<int>(0)
(* The hit shown, and whether a hit was jumped to since the search opened *)
val _hit_current = ref<Int>(~1)
val _hit_jumped = ref<bool>(false)

fn _search_free (cell: search_cell): void =
  case+ cell of
  | ~SearchCell(found, _, query, _) => let val () = hits_free(found) in $A.free<byte>(query) end
  | ~SearchNone() => ()

fn _search_take (): search_cell = let
  var cell: search_cell = SearchNone()
  val () = ref_exch_elt<search_cell>(_search, cell)
in cell end

fn _search_put (new_cell: search_cell): void = let
  var cell: search_cell = new_cell
  val () = ref_exch_elt<search_cell>(_search, cell)
in _search_free(cell) end

(* A character's code, in lower case when it is an ASCII capital *)
fn _lower (char_code: int): int = if char_code >= 65 then (if char_code <= 90 then char_code + 32 else char_code) else char_code

(* Whether text[at, at + query_len) is query[0, query_len), letters in any case *)
fun _match_at {text_location,query_location:agz}{text_size,query_size:pos}{at:nat}{query_len:nat | query_len <= query_size; at + query_len <= text_size}{i:nat | i <= query_len} .<query_len - i>.
  (text: !$A.arr(byte, text_location, text_size), at: int at, query: !$A.arr(byte, query_location, query_size), query_len: int query_len, i: int i): bool =
  if i >= query_len then true
  else if _lower(byte2int0($A.get<byte>(text, at + i))) <> byte2int0($A.get<byte>(query, i)) then false
  else _match_at(text, at, query, query_len, i + 1)

(* The start of the UTF-8 character at or after at in text[0, n), no further
   than limit *)
fun _char_forward {l:agz}{n:pos}{at,limit:nat | at <= limit; limit <= n} .<limit - at>.
  (text: !$A.arr(byte, l, n), at: int at, limit: int limit): [start:nat | at <= start; start <= limit] int start =
  if at >= limit then limit
  else if $AR.band_int_int(byte2int0($A.get<byte>(text, at)), 192) <> 128 then at
  else _char_forward(text, at + 1, limit)

(* end_at, or less (no less than low), so that text[.., end_at) ends before a
   character's start *)
fun _char_back_loop {l:agz}{n:pos}{low,end_at:nat | low <= end_at; end_at <= n} .<end_at - low>.
  (text: !$A.arr(byte, l, n), n: int n, end_at: int end_at, low: int low): [cut:nat | low <= cut; cut <= end_at] int cut =
  if end_at <= low then low
  else if end_at >= n then end_at
  else if $AR.band_int_int(byte2int0($A.get<byte>(text, end_at)), 192) <> 128 then end_at
  else _char_back_loop(text, n, end_at - 1, low)

(* text[start, start + span_len) into snippet from at, its control characters as spaces *)
fun _snippet_copy {text_location,snippet_location:agz}{text_size,snippet_size:pos}{start,span_len:nat | start + span_len <= text_size}{at:nat | at + span_len < snippet_size}{i:nat | i <= span_len} .<span_len - i>.
  (text: !$A.arr(byte, text_location, text_size), start: int start, snippet: !$A.arr(byte, snippet_location, snippet_size), at: int at, span_len: int span_len, i: int i): void =
  if i >= span_len then ()
  else let
    val char_code = byte2int0($A.get<byte>(text, start + i))
    val () = $A.set<byte>(snippet, at + i, (if char_code < 32 then $A.int2byte(32) else $A.get<byte>(text, start + i)))
  in _snippet_copy(text, start, snippet, at, span_len, i + 1) end

(* An ellipsis (U+2026, 3 bytes) at buf[at, at + 3) *)
fn _ellipsis {l:agz}{n:pos}{at:nat | at + 3 <= n} (buf: !$A.arr(byte, l, n), at: int at): void = let
  val () = $A.set<byte>(buf, at, $A.int2byte(226))
  val () = $A.set<byte>(buf, at + 1, $A.int2byte(128))
in $A.set<byte>(buf, at + 2, $A.int2byte(166)) end

(* An ellipsis at buf[at, at + width) when width is 3; nothing when it is 0 *)
fn _ellipsis_if {l:agz}{n:pos}{at:nat}{width:int | width == 0 || width == 3; at + width <= n}
  (buf: !$A.arr(byte, l, n), at: int at, width: int width): void =
  if width > 0 then _ellipsis(buf, at) else ()

(* end_at - start, at most 200 *)
fn _span200 {start,end_at:nat | start <= end_at} (start: int start, end_at: int end_at): [span:nat | span <= 200; start + span <= end_at] int span =
  if end_at - start <= 200 then end_at - start else 200

(* The text around text[at, at + query_len) in text[0, text_len): some 40
   bytes before it and 80 after, whole characters, its line breaks as spaces, with an
   ellipsis on a side where the text goes on *)
fn _snippet {l:agz}{text_size:pos}{text_len:nat | text_len <= text_size}{at,query_len:nat | at + query_len <= text_len}
  (text: !$A.arr(byte, l, text_size), text_size: int text_size, text_len: int text_len, at: int at, query_len: int query_len): [snippet_location:agz][snippet_len:nat | snippet_len <= 206] @($A.arr(byte, snippet_location, snippet_len + 1), int snippet_len) = let
  val start_guess = (if at > 40 then at - 40 else 0): [start:nat | start <= at] int start
  val start = _char_forward(text, start_guess, at)
  val end_guess = (if at + query_len + 80 < text_len then at + query_len + 80 else text_len): [end_at:nat | at + query_len <= end_at; end_at <= text_len] int end_at
  val end_at = _char_back_loop(text, text_size, end_guess, at + query_len)
  val snippet_len = _span200(start, end_at)
  val ellipsis_before = (if start > 0 then 3 else 0): [width:int | width == 0 || width == 3] int width
  val ellipsis_after = (if start + snippet_len < text_len then 3 else 0): [width:int | width == 0 || width == 3] int width
  val snippet = $A.alloc<byte>(ellipsis_before + snippet_len + ellipsis_after + 1)
  val () = _ellipsis_if(snippet, 0, ellipsis_before)
  val () = _snippet_copy(text, start, snippet, ellipsis_before, snippet_len, 0)
  val () = _ellipsis_if(snippet, ellipsis_before + snippet_len, ellipsis_after)
in @(snippet, ellipsis_before + snippet_len + ellipsis_after) end

(* The hits of the query in text[at, text_len), a content node of a chapter,
   onto found, while there are fewer than HIT_MAX *)
fun _find_all {text_location,query_location:agz}{text_size,query_size:pos}{text_len:nat | text_len <= text_size}{query_len:pos | query_len <= query_size}{at:nat}{hit_count:nat | hit_count <= HIT_MAX} .<max(text_len - at, 0)>.
  (text: !$A.arr(byte, text_location, text_size), text_size: int text_size, text_len: int text_len, at: int at, query: !$A.arr(byte, query_location, query_size), query_len: int query_len,
   chapter: Int, node: Int, found: hits(hit_count), hit_count: int hit_count): [new_count:nat | new_count <= HIT_MAX] @(hits(new_count), int new_count) =
  if hit_count >= HIT_MAX then @(found, hit_count)
  else if at + query_len > text_len then @(found, hit_count)
  else if _match_at(text, at, query, query_len, 0) then let
    val @(snippet, snippet_len) = _snippet(text, text_size, text_len, at, query_len)
  in _find_all(text, text_size, text_len, at + query_len, query, query_len, chapter, node, hits_cons(chapter, node, at, snippet, snippet_len, found), hit_count + 1) end
  else _find_all(text, text_size, text_len, at + 1, query, query_len, chapter, node, found, hit_count)

(* The hits in text data[offset, offset + piece_len), a content node's, decoded *)
fn _scan_piece {data_location,query_location:agz}{data_size:pos}{offset,piece_len:nat | offset + piece_len <= data_size; piece_len < 65536}{query_size:pos}{query_len:pos | query_len <= query_size}{hit_count:nat | hit_count <= HIT_MAX}
  (data: !$A.borrow(byte, data_location, data_size), offset: int offset, piece_len: int piece_len, query: !$A.arr(byte, query_location, query_size), query_len: int query_len,
   chapter: Int, node: Int, found: hits(hit_count), hit_count: int hit_count): [new_count:nat | new_count <= HIT_MAX] @(hits(new_count), int new_count) =
  if piece_len <= 0 then @(found, hit_count)
  else let
    val text = $A.alloc<byte>(piece_len)
    val text_len = decode_text(data, offset, piece_len, text)
    val result = _find_all(text, piece_len, text_len, 0, query, query_len, chapter, node, found, hit_count)
    val () = $A.free<byte>(text)
  in result end

(* The pieces of text data[offset, offset + text_len), as _text_spans makes them,
   from a content node: their hits, and the next node's number *)
fun _scan_text {data_location,query_location:agz}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size}{query_size:pos}{query_len:pos | query_len <= query_size}{hit_count:nat | hit_count <= HIT_MAX} .<text_len>.
  (data: !$A.borrow(byte, data_location, data_size), offset: int offset, text_len: int text_len, query: !$A.arr(byte, query_location, query_size), query_len: int query_len,
   chapter: Int, node: Nat, found: hits(hit_count), hit_count: int hit_count): [new_count:nat | new_count <= HIT_MAX] @(Nat, hits(new_count), int new_count) =
  if text_len < 65536 then let
    val @(found_after, new_count) = _scan_piece(data, offset, text_len, query, query_len, chapter, node, found, hit_count)
  in @(node + 1, found_after, new_count) end
  else let
    val cut = _text_cut(data, offset, text_len)
    val @(found_after, new_count) = _scan_piece(data, offset, cut, query, query_len, chapter, node, found, hit_count)
  in _scan_text(data, offset + cut, text_len - cut, query, query_len, chapter, node + 1, found_after, new_count) end

(* The numbers _scan_text takes for text data[offset, offset + text_len),
   as _text_spans makes its pieces, with nothing searched *)
fun _text_count {data_location:agz}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size} .<text_len>.
  (data: !$A.borrow(byte, data_location, data_size), offset: int offset, text_len: int text_len, node: Nat): Nat =
  if text_len < 65536 then node + 1
  else let
    val cut = _text_cut(data, offset, text_len)
  in _text_count(data, offset + cut, text_len - cut, node + 1) end

(* The numbers _skip_spans takes for text_len bytes *)
fun _skip_count {text_len:nat} .<text_len>. (text_len: int text_len, node: Nat): Nat =
  if text_len < 65536 then node + 1 else _skip_count(text_len - 65533, node + 1)

fun _scan_nodes {data_location,query_location:agz}{data_size:pos}{tree_size:nat}{query_size:pos}{query_len:pos | query_len <= query_size}{hit_count:nat | hit_count <= HIT_MAX} .<tree_size, 1>.
  (data: !$A.borrow(byte, data_location, data_size), nodes: !$X.xml_node_list(data_size, tree_size), top: bool, searched: bool,
   query: !$A.arr(byte, query_location, query_size), query_len: int query_len, chapter: Int, content_node: Nat, found: hits(hit_count), hit_count: int hit_count)
  : [new_count:nat | new_count <= HIT_MAX] @(Nat, hits(new_count), int new_count) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(next_node, found_after, new_count) = _scan_node(data, node, top, searched, query, query_len, chapter, content_node, found, hit_count)
    in _scan_nodes(data, rest, top, searched, query, query_len, chapter, next_node, found_after, new_count) end
  | $X.xml_nodes_nil() => @(content_node, found, hit_count)

and _scan_node {data_location,query_location:agz}{data_size:pos}{tree_size:pos}{query_size:pos}{query_len:pos | query_len <= query_size}{hit_count:nat | hit_count <= HIT_MAX} .<tree_size, 0>.
  (data: !$A.borrow(byte, data_location, data_size), node: !$X.xml_node(data_size, tree_size), top: bool, searched: bool,
   query: !$A.arr(byte, query_location, query_size), query_len: int query_len, chapter: Int, content_node: Nat, found: hits(hit_count), hit_count: int hit_count)
  : [new_count:nat | new_count <= HIT_MAX] @(Nat, hits(new_count), int new_count) =
  case+ node of
  | $X.xml_text(offset, text_len) =>
    if (if top then _blank(data, offset, text_len, 0) else false) then @(_skip_count(text_len, content_node), found, hit_count)
    else if searched then _scan_text(data, offset, text_len, query, query_len, chapter, content_node, found, hit_count)
    else @(_text_count(data, offset, text_len, content_node), found, hit_count)
  | $X.xml_element(name_offset, name_len, _, children) => let
    var _tag_head = @[char][4]('h', 'e', 'a', 'd')
    var _tag_title = @[char][5]('t', 'i', 't', 'l', 'e')
    var _tag_meta = @[char][4]('m', 'e', 't', 'a')
    var _tag_link = @[char][4]('l', 'i', 'n', 'k')
    var _tag_style = @[char][5]('s', 't', 'y', 'l', 'e')
    var _tag_script = @[char][6]('s', 'c', 'r', 'i', 'p', 't')
    var _tag_html = @[char][4]('h', 't', 'm', 'l')
    var _tag_body = @[char][4]('b', 'o', 'd', 'y')
    var _tag_br = @[char][2]('b', 'r')
    var _tag_hr = @[char][2]('h', 'r')
    var _tag_img = @[char][3]('i', 'm', 'g')
    var _tag_image = @[char][5]('i', 'm', 'a', 'g', 'e')
    var _tag_ruby_text = @[char][2]('r', 't')
    var _tag_ruby_text_container = @[char][3]('r', 't', 'c')
    var _tag_ruby_parenthesis = @[char][2]('r', 'p')
    (* a ruby's annotations and parentheses are not searched (a search
       finds the base, not its reading), but their nodes are counted as
       render makes them *)
    val annotation = (if xml_name_eq(data, name_offset, name_len, _tag_ruby_text, 2) then true
      else if xml_name_eq(data, name_offset, name_len, _tag_ruby_text_container, 3) then true
      else xml_name_eq(data, name_offset, name_len, _tag_ruby_parenthesis, 2)): bool
  in
    if xml_name_eq(data, name_offset, name_len, _tag_head, 4) then @(content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_title, 5) then @(content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_meta, 4) then @(content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_link, 4) then @(content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_style, 5) then @(content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_script, 6) then @(content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_html, 4) then
      _scan_nodes(data, children, top, searched, query, query_len, chapter, content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_body, 4) then
      _scan_nodes(data, children, top, searched, query, query_len, chapter, content_node, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_br, 2) then @(content_node + 1, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_hr, 2) then @(content_node + 1, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_img, 3) then @(content_node + 1, found, hit_count)
    else if xml_name_eq(data, name_offset, name_len, _tag_image, 5) then @(content_node + 1, found, hit_count)
    else _scan_nodes(data, children, false, (if annotation then false else searched), query, query_len, chapter, content_node + 1, found, hit_count)
  end

(* The results list, or its state *)
fn _search_status {text_len:pos | text_len < 256} (text: string text_len): void = ui_text("search-status", text)

(* The heading of a chapter's results *)
fn _hit_heading {chapter:nat} (chapter: int chapter): void = let
  val @(group_id, group_id_len) = nid_make("search-group", chapter)
  val () = ui_add_n("search-results", group_id, group_id_len, TDiv)
  val @(group_id, group_id_len) = nid_make("search-group", chapter)
  val () = ui_attr_n(group_id, group_id_len, AClass, "grp")
  val @(label, label_len) = toc_label_of(chapter)
  val @(group_id, group_id_len) = nid_make("search-group", chapter)
in ui_text_n_buf(group_id, group_id_len, label, label_len) end

(* One row of the results: a hit, with its text (its chapter is the
   heading above it) *)
fn _hit_row {hit:nat}{l:agz}{n:pos}{snippet_len:nat | snippet_len < n; snippet_len < 65536}
  (hit: int hit, snippet: !$A.arr(byte, l, n), snippet_len: int snippet_len): void = let
  val @(row_id, row_id_len) = nid_make("search-hit", hit)
  val () = ui_btn_n("search-results", row_id, row_id_len, "pi hgo")
  val @(row_id, row_id_len) = nid_make("search-hit", hit)
  val @(text_id, text_id_len) = nid_make("search-hit-text", hit)
  val () = ui_add_nn(row_id, row_id_len, text_id, text_id_len, TSpan)
  val @(text_id, text_id_len) = nid_make("search-hit-text", hit)
  val () = ui_attr_n(text_id, text_id_len, AClass, "snip")
  val text = $A.alloc<byte>(snippet_len + 1)
  val () = _fragment_duplicate(snippet, text, snippet_len, 0)
  val @(text_id, text_id_len) = nid_make("search-hit-text", hit)
in ui_text_n_buf(text_id, text_id_len, text, snippet_len) end

(* The rows of the hits found, from a hit on, under a heading wherever the chapter
   changes from last *)
fun _hit_rows {count:nat}{hit:nat} .<count>. (found: !hits(count), hit: int hit, last: Int): void =
  case+ found of
  | hits_nil() => ()
  | @hits_cons(chapter, _, _, snippet, snippet_len, rest) => let
      val () = (if chapter >= 0 then let
          val () = (if chapter <> last then _hit_heading(chapter) else ())
        in _hit_row(hit, snippet, snippet_len) end else ())
      val this_chapter = chapter
      val () = _hit_rows(rest, hit + 1, this_chapter)
      prval () = fold@(found)
    in end

(* The search is done: the hits in order, listed *)
fn _search_done (generation: int): void =
  if generation <> !_search_generation then ()
  else (case+ _search_take() of
    | ~SearchNone() => ()
    | ~SearchCell(found, hit_count, query, query_len) => let
        val found = hits_reverse(found, hits_nil())
        val () = ui_clear("search-results")
        val () = _hit_rows(found, 0, ~1)
        val () = (if hit_count = 0 then _search_status("No results")
          else if hit_count = 1 then _search_status("1 result")
          else if hit_count >= HIT_MAX then _search_status("500 results or more")
          else let
            val buf = $A.alloc<byte>(24)
            val offset = $S.int_to_str(buf, 0, 24, hit_count)
            val offset = _put(buf, offset, " results")
          in ui_text_buf("search-status", buf, offset) end)
      in _search_put(SearchCell(found, hit_count, query, query_len)) end)

(* The hits of the chapter data[0, n) (the chapter given), added *)
fn _search_add {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), chapter: Int): void =
  case+ _search_take() of
  | ~SearchNone() => ()
  | ~SearchCell(found, hit_count, query, query_len) => let
      val @(_, found_after, count_after) = _scan_nodes(data, nodes, true, true, query, query_len, chapter, 0, found, hit_count)
    in _search_put(SearchCell(found_after, count_after, query, query_len)) end

fn _search_add_if {l:agz}{n:pos}{tree_size:nat}
  (generation: int, data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), chapter: Int): void =
  if generation = !_search_generation then _search_add(data, nodes, chapter) else ()

fn _search_full (): bool =
  case+ _search_take() of
  | ~SearchNone() => true
  | ~SearchCell(found, hit_count, query, query_len) => let
      val full = hit_count >= HIT_MAX
      val () = _search_put(SearchCell(found, hit_count, query, query_len))
    in full end

(* Searches chapters chapter to chapter_count - 1 of book serial, one after another, while
   search generation is the latest *)
fun _search_chapters {chapter,chapter_count:nat} .<max(chapter_count - chapter, 0)>. (serial: int, chapter: int chapter, chapter_count: int chapter_count, generation: int): void =
  if generation <> !_search_generation then ()
  else if chapter >= chapter_count then _search_done(generation)
  else if _search_full() then _search_done(generation)
  else (case+ book_chapter_get(serial, chapter) of
    | ~ChaptersUnknown() => _search_done(generation)
    | ~ChapterNone(_) => _search_chapters(serial, chapter + 1, chapter_count, generation)
    | ~ChapterGot(file_size, chapter_start, compressed_size, method, _, _, _, _) =>
      (case+ piece_new(compressed_size) of
       | ~NoPiece() => _search_chapters(serial, chapter + 1, chapter_count, generation)
       | ~Piece(compressed_owner, compressed) => let
           val _ = book_read(serial, file_size, chapter_start, compressed, compressed_size)
           val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
           val decompressing = decompress(compressed_bytes, compressed_size, zip_compression(method))
           val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
           val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
         in
           $P.finish<Int>($P.vow(decompressing), llam(handle) => let
             val () = (case+ take_content(handle) of
               | ~NoContentBytes() => ()
               | ~ContentBytes(xhtml_owner, xhtml, xhtml_size) => let
                   val @(xhtml_frozen, xhtml_bytes) = $A.freeze<byte>(xhtml)
                   val nodes = $X.parse_document(xhtml_bytes, xhtml_size)
                   val () = _search_add_if(generation, xhtml_bytes, nodes, chapter)
                   val () = $X.free_nodes(nodes)
                   val () = $A.drop<byte>(xhtml_frozen, xhtml_bytes)
                 in piece_free(xhtml_owner, $A.thaw<byte>(xhtml_frozen)) end)
           in _search_chapters(serial, chapter + 1, chapter_count, generation) end)
         end))

(* query[0, query_len) in lower case, in a new array *)
fun _lower_into {query_location,lower_location:agz}{query_size,lower_size:pos}{query_len:nat | query_len <= query_size; query_len <= lower_size}{i:nat | i <= query_len} .<query_len - i>.
  (query: !$A.arr(byte, query_location, query_size), lower: !$A.arr(byte, lower_location, lower_size), query_len: int query_len, i: int i): void =
  if i >= query_len then ()
  else let
    val () = $A.set<byte>(lower, i, $A.int2byte($AR.low_byte(_lower(byte2int0($A.get<byte>(query, i))))))
  in _lower_into(query, lower, query_len, i + 1) end

(* ============================================================
   Public API
   ============================================================ *)

#pub fun apply_diff_list(diffs: $W.diff_list): void
implement apply_diff_list(diffs) = _apply_diff_list(diffs)

#pub fun apply_diff(diff: $W.diff): void
implement apply_diff(diff) = _apply_diff(diff)


#pub fun measure_pagination(): void
implement measure_pagination() = _measure_pagination()

(* The page shown, shift px to the right of where it rests (a drag's
   preview; 0 puts it back) *)
#pub fun reader_pan(shift: int): void

implement reader_pan(shift) =
  (* scrolled, a drag across moves nothing: the turn scrolls *)
  if _scrolled() then ()
  else case+ reading_get() of
  | @(page, _, _, _) => let
      val page_id = $A.alloc<byte>(4)
      val () = $A.write_text(page_id, 0, $A.text_lit("page"), 4)
      val @(page_id_frozen, page_id_bytes) = $A.freeze<byte>(page_id)
      val scroll_left = (if !_right_to_left then ~(page * !_page_width) else page * !_page_width): int
      val () = $SC.set_scroll_left(page_id_bytes, 4, scroll_left - shift)
    in release_bytes(page_id_frozen, page_id_bytes) end

(* The page was scrolled (by a finger, the wheel, or a key the browser
   takes): scrolled, the place follows the screenful now shown *)
#pub fn reader_scrolled (): void

implement reader_scrolled () =
  if ~_scrolled() then ()
  else case+ reading_get() of
  | @(page, page_count, chapter, chapter_count) => let
      val top = _scroll_top(page)
      val () = _measure_literal("page")
      val bottom = $DR.get_measure_scroll_h() - $DR.get_measure_h()
      val screen = _screen_at(top, bottom, page_count)
    in
      if screen = page then ()
      (* the reader moved: a restored place no longer holds them *)
      else let val () = !_settle_anchor := ~1 in _place_shown(screen, page_count, chapter, chapter_count) end
    end

(* The reader turns the page on or back. Reading on from where a jump
   landed keeps that place: the positions jumped from are forgotten, and
   the back button goes *)
#pub fun page_next(): void
implement page_next() = let
  val () = reader_stack_clear()
in _page_next() end

#pub fun page_prev(): void
implement page_prev() = let
  val () = reader_stack_clear()
in _page_previous() end

#pub fun load_chapter {chapter_index:nat} (chapter_index: int chapter_index): $P.promise(int, $P.Chained)
implement load_chapter(chapter_index) = _load_chapter(chapter_index)








(* Loads a chapter and shows a page of it (the last for -1), or the
   page of content node anchor when anchor >= 0 *)
#pub fun reader_goto (chapter: Int, page: Int, anchor: Int): $P.promise(int, $P.Chained)
implement reader_goto (chapter, page, anchor) = _goto(chapter, page, anchor)

(* Jumps to a row of the contents list, remembering where the reader
   was *)
#pub fun reader_goto_entry (row: Int): void
implement reader_goto_entry (row) =
  case+ toc_dest_of(row) of
  | ~TocNoDest() => ()
  | ~TocDest(chapter, fragment, fragment_len) => let
      val () = _push_position()
    in _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) end

(* Goes to a print page, remembering where the reader was *)
#pub fun reader_goto_page (print_page: Int): void
implement reader_goto_page (print_page) =
  case+ toc_page_dest_of(print_page) of
  | ~TocNoDest() => ()
  | ~TocDest(chapter, fragment, fragment_len) => let
      val () = _push_position()
    in _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) end

(* Jumps to a chapter's element fragment[0, fragment_len), remembering where the reader
   was *)
#pub fun reader_jump {l:agz}{n:pos}{fragment_len:nat | fragment_len < n} (chapter: Int, fragment: $A.arr(byte, l, n), fragment_len: int fragment_len): void
implement reader_jump (chapter, fragment, fragment_len) = let
  val () = _push_position()
in _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) end

(* Jumps to a page of a chapter (the page of content node anchor, when
   it is not -1), remembering where the reader was *)
#pub fun reader_jump_to (chapter: Int, page: Int, anchor: Int): void
implement reader_jump_to (chapter, page, anchor) = let
  val () = _push_position()
in _jump_checked(_goto(chapter, page, anchor)) end

(* The back button: to the position last jumped away from *)
#pub fun reader_back (): void
implement reader_back () = _pop_position()

(* Forgets the positions jumped from, and the back button goes: a book
   is opened or closed, a page turned, or the bars brought up *)
#pub fun reader_stack_clear (): void
implement reader_stack_clear () = _ps_put(PsHidden())

(* A book opened: its first page is read from now, so the first turn
   counts the minutes since. Back in the library, nothing is being read
   until the next book opens. *)
#pub fn reader_timer_start (): void
implement reader_timer_start () = !_speed_last_minute := $TM.epoch_minutes()

#pub fn reader_timer_stop (): void
implement reader_timer_stop () = !_speed_last_minute := ~1

(* The scrubber dragged to x: the thumb there, and the title of the
   chapter there in its tip *)
#pub fun reader_scrub_preview (x: Int): void
implement reader_scrub_preview (x) = let
  val thousandth = _track_at(x)
  val () = _scrub_at(thousandth)
  val () = ui_place("scrubber-tip", PLeft, thousandth)
  val () = (case+ reading_get() of
    | @(_, _, _, chapter_count) => let
        val @(chapter, _) = _chapter_at(thousandth, 0, chapter_count)
      in toc_title_in("scrubber-tip", chapter) end)
in ui_show("scrubber-tip", true) end

(* The scrubber let go at x: to that place in the book, remembering
   where the reader was *)
#pub fun reader_scrub_go (x: Int): void
implement reader_scrub_go (x) = let
  val thousandth = _track_at(x)
  val () = ui_show("scrubber-tip", false)
in
  case+ reading_get() of
  | @(_, _, _, chapter_count) => let
      val @(chapter, chapter_thousandth) = _chapter_at(thousandth, 0, chapter_count)
      val () = _push_position()
    in _jump_checked(_goto_part(chapter, chapter_thousandth)) end
end

(* Stores where the reader is *)
#pub fun reader_save (): void
implement reader_save () = _record_position()

(* The content node at the top of the page shown, or -1 *)
#pub fun reader_anchor (): Int
implement reader_anchor () = _anchor_now()

(* The link covering a content node, if any: followed (a link within
   the book, remembering where the reader was); true when there is one,
   also for a link out of the book, which the browser opens *)
fun _link_find {count:nat} .<count>. (entries: !links(count), node: int): @(int, Int, bool, [l:agz][fragment_len:nat] @($A.arr(byte, l, fragment_len + 1), int fragment_len)) =
  case+ entries of
  | links_nil() => let val empty = $A.alloc<byte>(1) in @(0, 0, false, @(empty, 0)) end
  | @links_cons(first_node, end_node, chapter, fragment, fragment_len, note, rest) =>
    if (if first_node <= node then node < end_node else false) then let
      val found_chapter = chapter
      val found_note = note
      val copy = $A.alloc<byte>(fragment_len + 1)
      val () = _fragment_duplicate(fragment, copy, fragment_len + 1, 0)
      val copy_len = fragment_len
      prval () = fold@(entries)
    in @((if found_chapter < 0 then 2 else 1), found_chapter, found_note, @(copy, copy_len)) end
    else let
      val found = _link_find(rest, node)
      prval () = fold@(entries)
    in found end

(* The little-endian int at buf[at, at + 4) *)
fn _int32_at {l:agz}{n:pos}{at:nat | at + 4 <= n} (buf: !$A.arr(byte, l, n), at: int at): Int = let
  val byte0 = $AR.low_byte(byte2int0($A.get<byte>(buf, at)))
  val byte1 = $AR.low_byte(byte2int0($A.get<byte>(buf, at + 1)))
  val byte2 = $AR.low_byte(byte2int0($A.get<byte>(buf, at + 2)))
  val byte3 = $AR.low_byte(byte2int0($A.get<byte>(buf, at + 3)))
  val high = (if byte3 < 128 then byte3 else byte3 - 256): [high:int | ~128 <= high; high < 128] int high
in byte0 + byte1 * 256 + byte2 * 65536 + high * 16777216 end

(* Reads the reading speed kept under "spd" *)
#pub fun reader_speed_load (): $P.promise(int, $P.Chained)
implement reader_speed_load () = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_speed_key())
  val stored = $IDB.idb_get(key_bytes, 3)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><int>(stored, llam(found) =>
    case+ lookup_bytes(found) of
    | ~NothingStored() => $P.ret<int>(0)
    (* the default speed this session, and the one learned is kept *)
    | ~StoredUnreadable() => let val () = storage_unreadable(ReadingSpeedRecord()) in $P.ret<int>(0) end
    | ~StoredBytes(data, data_len) =>
      if data_len < 8 then let val () = $A.free<byte>(data) in $P.ret<int>(0) end
      else let
        val minutes = _int32_at(data, 0)
        val pages = _int32_at(data, 4)
        val () = $A.free<byte>(data)
        (* only a plausible count: both at least 0, the pages at most 2000 *)
        val () = (if minutes >= 0 then (if pages >= 0 then (if pages <= 2000 then let
            val () = !_speed_minutes := minutes
          in !_speed_pages := pages end else ()) else ()) else ())
      in $P.ret<int>(0) end)
end

(* ============================================================
   Notes: a note's reference opens the note over the page
   ============================================================ *)

(* The note shown over the page: its chapter and fragment, for "Go to
   note" *)
datavtype note_target =
  | {l:agz}{fragment_len:nat | fragment_len <= 200} NoteTarget of (Int, $A.arr(byte, l, fragment_len + 1), int fragment_len)
  | NoNoteTarget of ()

val _note_target = ref<note_target>(NoNoteTarget())

fn _note_target_put (target: note_target): void = let
  var cell: note_target = target
  val () = ref_exch_elt<note_target>(_note_target, cell)
in case+ cell of ~NoteTarget(_, fragment, _) => $A.free<byte>(fragment) | ~NoNoteTarget() => () end

fn _note_target_take (): note_target = let
  var cell: note_target = NoNoteTarget()
  val () = ref_exch_elt<note_target>(_note_target, cell)
in cell end

stadef NOTE_CAPACITY = 4096
macdef _NOTE_CAPACITY = 4096

(* buf[at, end_at) := data[offset + i, offset + text_len) with runs of white space made one
   space, and none first; at most NOTE_CAPACITY - 1 bytes in all *)
fun _note_put {data_location,note_location:agz}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size}{i:nat | i <= text_len}{at:nat | at <= NOTE_CAPACITY} .<text_len - i>.
  (data: !$A.borrow(byte, data_location, data_size), offset: int offset, text_len: int text_len, i: int i,
   buf: !$A.arr(byte, note_location, NOTE_CAPACITY), at: int at): [end_at:nat | end_at <= NOTE_CAPACITY] int end_at =
  if i >= text_len then at
  else if at >= _NOTE_CAPACITY - 1 then at
  else let
    val char_code = byte2int0($A.read<byte>(data, offset + i))
  in
    if char_code = 32 || char_code = 9 || char_code = 10 || char_code = 13 then
      (if at = 0 then _note_put(data, offset, text_len, i + 1, buf, at)
       else if byte2int0($A.get<byte>(buf, at - 1)) = 32 then _note_put(data, offset, text_len, i + 1, buf, at)
       else let val () = $A.set<byte>(buf, at, $A.int2byte(32)) in _note_put(data, offset, text_len, i + 1, buf, at + 1) end)
    else let
      val () = $A.set<byte>(buf, at, $A.read<byte>(data, offset + i))
    in _note_put(data, offset, text_len, i + 1, buf, at + 1) end
  end

(* A space at buf[at], unless the text so far ends in one: where a block
   of the note ends *)
fn _note_break {l:agz}{at:nat | at <= NOTE_CAPACITY} (buf: !$A.arr(byte, l, NOTE_CAPACITY), at: int at): [end_at:nat | end_at <= NOTE_CAPACITY] int end_at =
  if at = 0 then at
  else if at >= _NOTE_CAPACITY - 1 then at
  else if byte2int0($A.get<byte>(buf, at - 1)) = 32 then at
  else let val () = $A.set<byte>(buf, at, $A.int2byte(32)) in at + 1 end

(* The text of the element of nodes whose id is fragment[0, fragment_len), gathered into
   buf from at (inside: whether nodes are within it) *)
fun _note_nodes {data_location,fragment_location,note_location:agz}{data_size:pos}{tree_size:nat}{fragment_len:pos}{at:nat | at <= NOTE_CAPACITY} .<tree_size, 1>.
  (data: !$A.borrow(byte, data_location, data_size), nodes: !$X.xml_node_list(data_size, tree_size),
   fragment: !$A.arr(byte, fragment_location, fragment_len + 1), fragment_len: int fragment_len, inside: bool,
   buf: !$A.arr(byte, note_location, NOTE_CAPACITY), at: int at): [end_at:nat | end_at <= NOTE_CAPACITY] int end_at =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val at = _note_node(data, node, fragment, fragment_len, inside, buf, at)
    in _note_nodes(data, rest, fragment, fragment_len, inside, buf, at) end
  | $X.xml_nodes_nil() => at

and _note_node {data_location,fragment_location,note_location:agz}{data_size:pos}{tree_size:pos}{fragment_len:pos}{at:nat | at <= NOTE_CAPACITY} .<tree_size, 0>.
  (data: !$A.borrow(byte, data_location, data_size), node: !$X.xml_node(data_size, tree_size),
   fragment: !$A.arr(byte, fragment_location, fragment_len + 1), fragment_len: int fragment_len, inside: bool,
   buf: !$A.arr(byte, note_location, NOTE_CAPACITY), at: int at): [end_at:nat | end_at <= NOTE_CAPACITY] int end_at =
  case+ node of
  | $X.xml_text(offset, text_len) => if inside then _note_put(data, offset, text_len, 0, buf, at) else at
  | $X.xml_element(_, _, attrs, children) => let
      var _attr_id = @[char][2]('i', 'd')
      val here = (case+ find_attr(data, attrs, _attr_id, 2) of
        | ~xspan_none() => false
        | ~xspan_at(start, span_len) => if span_len = fragment_len then _same(data, start, fragment, span_len, 0) else false): bool
      val end_at = _note_nodes(data, children, fragment, fragment_len, (if inside then true else here), buf, at)
    in if inside then _note_break(buf, end_at) else end_at end

(* The note's text, decoded, shown in the note overlay, which opens *)
fn _note_show {l:agz}{text_len:nat | text_len <= NOTE_CAPACITY} (buf: $A.arr(byte, l, NOTE_CAPACITY), text_len: int text_len): void = let
  val text_len = (if text_len > 0 then (if byte2int0($A.get<byte>(buf, text_len - 1)) = 32 then text_len - 1 else text_len) else text_len): [text_len:nat | text_len <= NOTE_CAPACITY] int text_len
  val decoded = $A.alloc<byte>(_NOTE_CAPACITY)
  val @(note_frozen, note_bytes) = $A.freeze<byte>(buf)
  val decoded_len = decode_text(note_bytes, 0, text_len, decoded)
  val () = release_bytes(note_frozen, note_bytes)
  val () = ui_text_buf("footnote-text", decoded, decoded_len)
  val () = layer_open(LNote())
in ui_focus("footnote-close") end

(* The note kept in _note_target, found in its chapter's XHTML data[0, n):
   shown over the page, and kept for "Go to note"; when it has no text
   there, the link is followed instead *)
fn _note_found {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), n: int n): void =
  case+ _note_target_take() of
  | ~NoNoteTarget() => ()
  | ~NoteTarget(chapter, fragment, fragment_len) =>
    if fragment_len <= 0 then let
      val () = _push_position()
    in _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) end
    else let
      val buf = $A.alloc<byte>(_NOTE_CAPACITY)
      val nodes = $X.parse_document(data, n)
      val text_len = _note_nodes(data, nodes, fragment, fragment_len, false, buf, 0)
      val () = $X.free_nodes(nodes)
    in
      if text_len > 0 then let
        val () = _note_show(buf, text_len)
      in _note_target_put(NoteTarget(chapter, fragment, fragment_len)) end
      else let
        val () = $A.free<byte>(buf)
        val () = _push_position()
      in _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) end
    end

(* The note kept in _note_target followed as a link: its chapter could not
   be read *)
fn _note_follow (): void =
  case+ _note_target_take() of
  | ~NoNoteTarget() => ()
  | ~NoteTarget(chapter, fragment, fragment_len) => let
      val () = _push_position()
    in _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) end

(* Opens the note fragment[0, fragment_len) of a chapter over the page (found once its
   chapter is read); when it cannot be found, the link is followed *)
fn _note_open {l:agz}{fragment_len:pos | fragment_len <= 200} (chapter: Int, fragment: $A.arr(byte, l, fragment_len + 1), fragment_len: int fragment_len): void = let
  val () = _note_target_put(NoteTarget(chapter, fragment, fragment_len))
  val serial = book_serial()
  val chapter_index = (if chapter >= 0 then chapter else 0): [chapter_index:nat] int chapter_index
in
  case+ book_chapter_get(serial, chapter_index) of
  | ~ChaptersUnknown() => _note_follow()
  | ~ChapterNone(_) => _note_follow()
  | ~ChapterGot(file_size, chapter_start, compressed_size, method, _, _, _, _) =>
    (case+ piece_new(compressed_size) of
     | ~NoPiece() => _note_follow()
     | ~Piece(compressed_owner, compressed) => let
         val _ = book_read(serial, file_size, chapter_start, compressed, compressed_size)
         val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
         val decompressing = decompress(compressed_bytes, compressed_size, zip_compression(method))
         val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
         val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
       in
         $P.finish<Int>($P.vow(decompressing), llam(handle) => let
           val () = (case+ take_content(handle) of
             | ~NoContentBytes() => _note_follow()
             | ~ContentBytes(xhtml_owner, xhtml, xhtml_size) => let
                 val @(xhtml_frozen, xhtml_bytes) = $A.freeze<byte>(xhtml)
                 val () = _note_found(xhtml_bytes, xhtml_size)
                 val () = $A.drop<byte>(xhtml_frozen, xhtml_bytes)
               in piece_free(xhtml_owner, $A.thaw<byte>(xhtml_frozen)) end)
         in () end)
       end)
end

(* The path of a content node's image, copied; none when it has none *)
datavtype picture_path =
  | {l:agz}{path_len:pos | path_len < 65536} PicturePath of ($A.arr(byte, l, path_len), int path_len)
  | NoPicturePath of ()

fun _picture_find {count:nat} .<count>. (entries: !pictures(count), node: int): picture_path =
  case+ entries of
  | pictures_nil() => NoPicturePath()
  | @pictures_cons(entry_node, path, path_len, rest) =>
    if entry_node = node then let
      val copy = $A.alloc<byte>(path_len)
      val () = _fragment_duplicate(path, copy, path_len, 0)
      val copy_len = path_len
      prval () = fold@(entries)
    in PicturePath(copy, copy_len) end
    else let
      val found = _picture_find(rest, node)
      prval () = fold@(entries)
    in found end

(* Shows a content node's image in the image viewer, which opens; false
   when the node is not an image of the chapter *)
#pub fun reader_image_at (node: int): bool
implement reader_image_at (node) = let
  val cell = _pictures_take()
  val+ @PicturesCell(entries) = cell
  val found = _picture_find(entries, node)
  prval () = fold@(cell)
  val () = _pictures_put(cell)
in
  case+ found of
  | ~NoPicturePath() => false
  | ~PicturePath(path, path_len) =>
    (case+ book_meta_get() of
     | ~$R.none() => let val () = $A.free<byte>(path) in false end
     | ~$R.some(@(file_size, _, _, _, _, _)) => let
         val @(path_frozen, path_bytes) = $A.freeze<byte>(path)
         val () = _show_image(book_serial(), file_size, 0, true, !_load_generation, path_bytes, path_len)
         val () = release_bytes(path_frozen, path_bytes)
         val () = layer_open(LImage())
         val () = ui_focus("image-close")
       in true end)
end

(* The book's language's primary subtag ("fr" of "fr-CA"), lower case,
   in code[0, code_len) of 3 bytes: when it is 2 or 3 letters; else "en" *)
#pub fun reader_lang_code (): [l:agz][code_len:pos | code_len <= 3] @($A.arr(byte, l, 3), int code_len)

fun _subtag_len {l:agz}{n:pos}{lang_len:nat | lang_len <= n}{i:nat | i <= lang_len} .<lang_len - i>.
  (lang: !$A.arr(byte, l, n), lang_len: int lang_len, i: int i): [subtag_len:nat | subtag_len <= lang_len] int subtag_len =
  if i >= lang_len then i
  else if byte2int0($A.get<byte>(lang, i)) = 45 then i
  else _subtag_len(lang, lang_len, i + 1)

(* Byte i of lang[0, j), in lower case, when it is a letter; else -1 *)
fn _lower_letter {l:agz}{n:pos}{i:nat | i < n} (lang: !$A.arr(byte, l, n), i: int i): int = let
  val char_code = byte2int0($A.get<byte>(lang, i))
  val lower = (if char_code >= 65 then (if char_code <= 90 then char_code + 32 else char_code) else char_code): int
in if lower < 97 then ~1 else if lower > 122 then ~1 else lower end

implement reader_lang_code () = let
  val cell = _book_lang_take()
  (* the primary subtag's letters, lower case, and how many; 0 when it is
     not 2 or 3 letters *)
  val @(code_len, letter0, letter1, letter2) = (case+ cell of
    | @BookLang(lang, lang_len) => let
        val subtag_len = _subtag_len(lang, lang_len, 0)
        val letters = (if subtag_len < 2 then @(0, 0, 0, 0) else if subtag_len > 3 then @(0, 0, 0, 0)
          else let
            val lower0 = _lower_letter(lang, 0)
            val lower1 = _lower_letter(lang, 1)
            val lower2 = (if subtag_len = 3 then (if lang_len >= 3 then _lower_letter(lang, 2) else ~1) else 0): int
          in
            if lower0 < 0 then @(0, 0, 0, 0) else if lower1 < 0 then @(0, 0, 0, 0)
            else if lower2 < 0 then @(0, 0, 0, 0) else @(subtag_len, lower0, lower1, lower2)
          end): @(int, int, int, int)
        prval () = fold@(cell)
      in letters end
    | NoBookLang() => @(0, 0, 0, 0)): @(int, int, int, int)
  val () = _book_lang_put(cell)
  val code = $A.alloc<byte>(3)
  val () = $A.set<byte>(code, 0, $A.int2byte($AR.low_byte(if code_len >= 2 then letter0 else 101)))
  val () = $A.set<byte>(code, 1, $A.int2byte($AR.low_byte(if code_len >= 2 then letter1 else 110)))
  val () = $A.set<byte>(code, 2, $A.int2byte($AR.low_byte(if code_len = 3 then letter2 else 0)))
in if code_len = 3 then @(code, 3) else @(code, 2) end

#pub fun reader_link_at (node: int): bool
implement reader_link_at (node) = let
  val cell = _links_take()
  val+ @LinksCell(entries) = cell
  val @(kind, chapter, note, @(fragment, fragment_len)) = _link_find(entries, node)
  prval () = fold@(cell)
  val () = _links_put(cell)
in
  if kind = 1 then
    (* a note's reference to a note it names opens the note over the
       page; any other link is followed *)
    (if note then (if fragment_len > 0 then (if fragment_len <= 200 then let
        val () = _note_open(chapter, fragment, fragment_len)
      in true end
      else let val () = _push_position() val () = _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) in true end)
      else let val () = _push_position() val () = _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) in true end)
     else let
       val () = _push_position()
       val () = _jump_checked(_goto_fragment(chapter, fragment, fragment_len))
     in true end)
  else let val () = $A.free<byte>(fragment) in kind = 2 end
end

(* Goes to the note shown over the page, remembering where the reader
   was *)
#pub fun reader_note_go (): void
implement reader_note_go () =
  case+ _note_target_take() of
  | ~NoNoteTarget() => ()
  | ~NoteTarget(chapter, fragment, fragment_len) => let
      val () = _push_position()
    in _jump_checked(_goto_fragment(chapter, fragment, fragment_len)) end

(* Whether the open book reads right to left *)
#pub fun reader_rtl (): bool
implement reader_rtl () = !_right_to_left

(* A length, at most 200 *)
fn _query_len_of {length:pos} (length: int length): [query_len:pos | query_len <= 200; query_len <= length] int query_len = if length <= 200 then length else 200

(* Searches the open book for query[0, length): its hits are listed as they are
   found, chapter by chapter *)
#pub fun reader_search {l:agz}{n:pos}{length:nat | length <= n} (query: $A.arr(byte, l, n), length: int length): void
implement reader_search (query, length) = let
  val () = !_search_generation := !_search_generation + 1
  val generation = !_search_generation
  val () = $BDOM.clear_marks(2)
  val () = ui_clear("search-results")
  val () = ui_show("search-nav", false)
  val () = !_hit_current := ~1
in
  if length <= 0 then let
    val () = $A.free<byte>(query)
    val () = _search_put(SearchNone())
  in _search_status(" ") end
  else let
    val query_len = _query_len_of(length)
    val lowered = $A.alloc<byte>(query_len)
    val () = _lower_into(query, lowered, query_len, 0)
    val () = $A.free<byte>(query)
    val () = _search_put(SearchCell(hits_nil(), 0, lowered, query_len))
    val () = _search_status("Searching\xE2\x80\xA6")
  in
    case+ reading_get() of
    | @(_, _, _, chapter_count) => _search_chapters(book_serial(), 0, chapter_count, generation)
  end
end

fun _hit_at {count:nat} .<count>. (found: !hits(count), i: int): @(Int, Int, Int) =
  case+ found of
  | hits_nil() => @(~1, 0, 0)
  | @hits_cons(chapter, node, offset, _, _, rest) =>
    if i = 0 then let
      val hit = @(chapter, node, offset)
      prval () = fold@(found)
    in hit end
    else let
      val hit = _hit_at(rest, i - 1)
      prval () = fold@(found)
    in hit end

(* A hit, its count and the query's length; a chapter of -1 when there
   is none *)
fn _hit (hit: Int): @(Int, Int, Int, Int, Int) =
  case+ _search_take() of
  | ~SearchNone() => @(~1, 0, 0, 0, 0)
  | ~SearchCell(found, hit_count, query, query_len) => let
      val @(chapter, node, offset) = _hit_at(found, hit)
      val () = _search_put(SearchCell(found, hit_count, query, query_len))
    in @(chapter, node, offset, hit_count, query_len) end

(* "3 of 12": the hit's number of the hit count, under the results *)
fn _hit_count (hit: Int, hit_count: Int): void = let
  val buf = $A.alloc<byte>(40)
  val offset = $S.int_to_str(buf, 0, 40, (if hit >= 0 then hit + 1 else 0): Nat)
  val offset = _put(buf, offset, " of ")
  val offset = $S.int_to_str(buf, offset, 40, (if hit_count >= 0 then hit_count else 0): Nat)
in ui_text_buf("search-count", buf, offset) end

(* Opens a hit: its page, the match marked; the first one remembers where
   the reader was *)
#pub fun reader_search_go (hit: Int): void
implement reader_search_go (hit) = let
  val @(chapter, node, offset, hit_count, query_len) = _hit(hit)
in
  if chapter < 0 then ()
  else let
    val () = (if !_hit_jumped then () else let
        val () = _push_position()
      in !_hit_jumped := true end)
    val () = !_hit_current := hit
    val () = _hit_count(hit, hit_count)
    val () = ui_show("search-nav", true)
  in
    (* the hit is marked only once its chapter is shown; a failure is
       told by _jump_checked *)
    _jump_checked($P.and_then<int><int>(_goto(chapter, 0, node), llam(result) => let
      val () = (if result >= 0 then (if node >= 0 then let
          val () = $BDOM.clear_marks(2)
          val @(start_id, start_id_len) = nid_pad3("c", node)
          val @(end_id, end_id_len) = nid_pad3("c", node)
          val @(start_frozen, start_bytes) = $A.freeze<byte>(start_id)
          val @(end_frozen, end_bytes) = $A.freeze<byte>(end_id)
          val () = $BDOM.mark_range(2, start_bytes, start_id_len, offset, end_bytes, end_id_len, offset + query_len)
          val () = release_bytes(end_frozen, end_bytes)
        in release_bytes(start_frozen, start_bytes) end else ()) else ())
    in $P.ret<int>(result) end))
  end
end

(* The next (direction = 1) or previous (direction = -1) hit *)
#pub fun reader_search_step (direction: Int): void
implement reader_search_step (direction) = let
  val @(_, _, _, hit_count, _) = _hit(0)
in
  if hit_count <= 0 then ()
  else let
    val next = !_hit_current + direction
  in reader_search_go(if next < 0 then hit_count - 1 else if next >= hit_count then 0 else next) end
end

(* Stops the search, its hits and marks gone, where the reader is *)
#pub fun reader_search_stop (): void
implement reader_search_stop () = let
  val () = !_search_generation := !_search_generation + 1
  val () = $BDOM.clear_marks(2)
  val () = ui_show("search-nav", false)
  val () = ui_clear("search-results")
  val () = _search_status(" ")
  val () = _search_put(SearchNone())
  val () = !_hit_current := ~1
in !_hit_jumped := false end

(* Closes the search: its marks go, and the reader returns to where it
   was when it jumped to a hit *)
#pub fun reader_search_close (): void
implement reader_search_close () = let
  val jumped = !_hit_jumped
  val () = reader_search_stop()
in if jumped then _pop_position() else () end

#pub fun reader_relayout (): void
implement reader_relayout () = _relayout()

(* Shows a page of the chapter shown (clamped to its pages) *)
#pub fun reader_page (page: Int): void
implement reader_page (page) = let
  (* the reader moved: a restored place no longer holds them *)
  val () = !_settle_anchor := ~1
in case+ reading_get() of
  | @(_, page_count, chapter, chapter_count) => if page < 0 then _show_page(0, page_count, chapter, chapter_count) else if page >= page_count then _show_page(page_count - 1, page_count, chapter, chapter_count) else _show_page(page, page_count, chapter, chapter_count)
end

#pub fun update_page_indicator(): void
implement update_page_indicator() = _update_page_indicator()


#pub fun num_id {prefix_len:pos | prefix_len <= 3}{number:nat}{width:int | width == 2 || width == 3}
  (id_prefix: string prefix_len, number: int number, width: int width): [l:agz][id_len:pos | id_len <= 16] @($A.arr(byte, l, id_len), int id_len)
implement num_id(id_prefix, number, width) = _number_id(id_prefix, number, width)


(* ============================================================
   Reading aloud: the page turned on, and a chapter's sentences
   (read_aloud.bats reads them)
   ============================================================ *)

(* What a turn on did: the next page of the chapter shown, the next
   chapter's first page shown, or nothing (the book's last page, or a
   chapter that could not be shown) *)
#pub datatype turned = TurnedPage | TurnedChapter | NotTurned
implement $P.dispose<turned>(_) = ()

(* The page turned on, as the next page button turns it (into the next
   chapter too); the promise resolves once the page is shown *)
#pub fun reader_turn_on (): $P.promise(turned, $P.Chained)

implement reader_turn_on () = let
  val () = reader_stack_clear()
  val () = !_settle_anchor := ~1
in
  case+ reading_get() of
  | @(page, page_count, chapter, chapter_count) =>
    if page + 1 < page_count then let
      val () = _speed_turn()
      val () = _show_page(page + 1, page_count, chapter, chapter_count)
    in $P.ret<turned>(TurnedPage()) end
    else if chapter < chapter_count then let
      val () = _speed_turn()
    in
      $P.and_then<int><turned>(_goto(chapter, 0, ~1), llam(result) =>
        if result >= 0 then $P.ret<turned>(TurnedChapter())
        else let
          (* as _jump_checked: the page that was shown, and the banner
             says why *)
          val () = (case+ reading_get() of
            | @(page_now, page_count_now, chapter_now, chapter_count_now) =>
              if chapter_now > 0 then _show_page(page_now, page_count_now, chapter_now, chapter_count_now) else ())
          val () = notice_part_unread()
        in $P.ret<turned>(NotTurned()) end)
    end
    else $P.ret<turned>(NotTurned())
end

(* Whether the chapter is scrolled down rather than paged across *)
#pub fun reader_scrolls (): bool
implement reader_scrolls () = _scrolled()

(* The book's language tag (its OPF's dc:language) in tag[0, tag_len);
   tag_len is 0 when it has none *)
#pub fun reader_lang_tag (): [l:agz][tag_len:nat | tag_len <= 35] @($A.arr(byte, l, 36), int tag_len)

implement reader_lang_tag () = let
  val tag = $A.alloc<byte>(36)
in
  case+ _book_lang_take() of
  | ~NoBookLang() => let
      val () = _book_lang_put(NoBookLang())
    in @(tag, 0) end
  | ~BookLang(lang, lang_len) => let
      fun copy {lang_loc,tag_loc:agz}{lang_len:nat | lang_len <= 35}{i:nat | i <= lang_len} .<lang_len - i>.
        (lang: !$A.arr(byte, lang_loc, 35), tag: !$A.arr(byte, tag_loc, 36), lang_len: int lang_len, i: int i): void =
        if i >= lang_len then ()
        else let
          val () = $A.set<byte>(tag, i, $A.get<byte>(lang, i))
        in copy(lang, tag, lang_len, i + 1) end
      val () = copy(lang, tag, lang_len, 0)
      val () = _book_lang_put(BookLang(lang, lang_len))
    in @(tag, lang_len) end
end

(* The elements read aloud a block at a time: a paragraph, a heading, a
   list item, a quotation, a definition's term and description, a
   figure's caption, a table's cell and preformatted text *)
fn _block_tag {l:agz}{n:pos}{name_offset,name_len:nat | name_offset + name_len <= n}
  (data: !$A.borrow(byte, l, n), name_offset: int name_offset, name_len: int name_len): bool = let
  fn is {pattern_len:pos} (data: !$A.borrow(byte, l, n), pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool =
    xml_name_eq(data, name_offset, name_len, pattern, pattern_len)
  var paragraph = @[char][1]('p')
  var heading1 = @[char][2]('h', '1')
  var heading2 = @[char][2]('h', '2')
  var heading3 = @[char][2]('h', '3')
  var heading4 = @[char][2]('h', '4')
  var heading5 = @[char][2]('h', '5')
  var heading6 = @[char][2]('h', '6')
  var list_item = @[char][2]('l', 'i')
  var blockquote = @[char][10]('b', 'l', 'o', 'c', 'k', 'q', 'u', 'o', 't', 'e')
  var term = @[char][2]('d', 't')
  var description = @[char][2]('d', 'd')
  var figcaption = @[char][10]('f', 'i', 'g', 'c', 'a', 'p', 't', 'i', 'o', 'n')
  var cell = @[char][2]('t', 'd')
  var header_cell = @[char][2]('t', 'h')
  var preformatted = @[char][3]('p', 'r', 'e')
in
  if is(data, paragraph, 1) then true
  else if is(data, heading1, 2) then true else if is(data, heading2, 2) then true
  else if is(data, heading3, 2) then true else if is(data, heading4, 2) then true
  else if is(data, heading5, 2) then true else if is(data, heading6, 2) then true
  else if is(data, list_item, 2) then true else if is(data, blockquote, 10) then true
  else if is(data, term, 2) then true else if is(data, description, 2) then true
  else if is(data, figcaption, 10) then true else if is(data, cell, 2) then true
  else if is(data, header_cell, 2) then true
  else is(data, preformatted, 3)
end

(* Whether nodes hold a block element *)
fun _blocks_within {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): bool =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => if _block_within(data, node) then true else _blocks_within(data, rest)
  | $X.xml_nodes_nil() => false

and _block_within {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): bool =
  case+ node of
  | $X.xml_text(_, _) => false
  | $X.xml_element(name_offset, name_len, _, children) =>
    if _block_tag(data, name_offset, name_len) then true else _blocks_within(data, children)

(* The text read aloud, as the chapter's XHTML of n bytes has it: each
   text content node's text data[offset, offset + length) (not yet
   decoded), with its block's number and its content node's *)
datavtype text_runs(n:int, int) =
  | TextRunsEnd(n, 0) of ()
  | {count:nat}{offset,length:nat | offset + length <= n; length < 65536}
    TextRun(n, count + 1) of (Nat, Nat, int offset, int length, text_runs(n, count))

fun _text_runs_free {n:int}{count:nat} .<count>. (runs: text_runs(n, count)): void =
  case+ runs of
  | ~TextRunsEnd() => ()
  | ~TextRun(_, _, _, _, rest) => _text_runs_free(rest)

fun _text_runs_reverse {n:int}{count,reversed_count:nat} .<count>.
  (runs: text_runs(n, count), reversed: text_runs(n, reversed_count)): text_runs(n, count + reversed_count) =
  case+ runs of
  | ~TextRunsEnd() => reversed
  | ~TextRun(block, node, offset, length, rest) => _text_runs_reverse(rest, TextRun(block, node, offset, length, reversed))

(* The pieces of text data[offset, offset + text_len), as _text_spans
   makes them, from a content node on: as runs of block, and the next
   node's number *)
fun _runs_text {l:agz}{n:pos}{offset,text_len:nat | offset + text_len <= n}{count:nat} .<text_len>.
  (data: !$A.borrow(byte, l, n), offset: int offset, text_len: int text_len, block: Nat, node: Nat, found: text_runs(n, count))
  : [new_count:nat] @(Nat, text_runs(n, new_count)) =
  if text_len < 65536 then @(node + 1, TextRun(block, node, offset, text_len, found))
  else let
    val cut = _text_cut(data, offset, text_len)
  in _runs_text(data, offset + cut, text_len - cut, block, node + 1, TextRun(block, node, offset, cut, found)) end

(* A chapter's text read aloud: its nodes walked as _render_nodes shows
   them, numbering the content nodes the same way (as search does: the
   three must stay in step). A block element holding no other block
   starts a block (its number is blocks); text outside such a block is
   not read, nor a ruby's readings and parentheses (rt, rtc, rp), whose
   nodes are counted all the same. The next content node's number, the
   blocks' count, and the runs found (the latest first) *)
fun _runs_nodes {l:agz}{n:pos}{tree_size:nat}{count:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), top: bool, readable: bool,
   block: Int, blocks: Nat, content_node: Nat, found: text_runs(n, count))
  : [new_count:nat] @(Nat, Nat, text_runs(n, new_count)) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(next_node, next_blocks, found_after) = _runs_node(data, node, top, readable, block, blocks, content_node, found)
    in _runs_nodes(data, rest, top, readable, block, next_blocks, next_node, found_after) end
  | $X.xml_nodes_nil() => @(content_node, blocks, found)

and _runs_node {l:agz}{n:pos}{tree_size:pos}{count:nat} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), top: bool, readable: bool,
   block: Int, blocks: Nat, content_node: Nat, found: text_runs(n, count))
  : [new_count:nat] @(Nat, Nat, text_runs(n, new_count)) =
  case+ node of
  | $X.xml_text(offset, text_len) =>
    if (if top then _blank(data, offset, text_len, 0) else false) then @(_skip_count(text_len, content_node), blocks, found)
    else if (if readable then block >= 0 else false) then let
      val @(next_node, found_after) = _runs_text(data, offset, text_len, (if block >= 0 then block else 0): Nat, content_node, found)
    in @(next_node, blocks, found_after) end
    else @(_text_count(data, offset, text_len, content_node), blocks, found)
  | $X.xml_element(name_offset, name_len, _, children) => let
    var _tag_head = @[char][4]('h', 'e', 'a', 'd')
    var _tag_title = @[char][5]('t', 'i', 't', 'l', 'e')
    var _tag_meta = @[char][4]('m', 'e', 't', 'a')
    var _tag_link = @[char][4]('l', 'i', 'n', 'k')
    var _tag_style = @[char][5]('s', 't', 'y', 'l', 'e')
    var _tag_script = @[char][6]('s', 'c', 'r', 'i', 'p', 't')
    var _tag_html = @[char][4]('h', 't', 'm', 'l')
    var _tag_body = @[char][4]('b', 'o', 'd', 'y')
    var _tag_br = @[char][2]('b', 'r')
    var _tag_hr = @[char][2]('h', 'r')
    var _tag_img = @[char][3]('i', 'm', 'g')
    var _tag_image = @[char][5]('i', 'm', 'a', 'g', 'e')
    var _tag_ruby_text = @[char][2]('r', 't')
    var _tag_ruby_text_container = @[char][3]('r', 't', 'c')
    var _tag_ruby_parenthesis = @[char][2]('r', 'p')
    (* a ruby's readings and parentheses are not read (only its base
       is), but their nodes are counted as render makes them *)
    val annotation = (if xml_name_eq(data, name_offset, name_len, _tag_ruby_text, 2) then true
      else if xml_name_eq(data, name_offset, name_len, _tag_ruby_text_container, 3) then true
      else xml_name_eq(data, name_offset, name_len, _tag_ruby_parenthesis, 2)): bool
  in
    if xml_name_eq(data, name_offset, name_len, _tag_head, 4) then @(content_node, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_title, 5) then @(content_node, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_meta, 4) then @(content_node, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_link, 4) then @(content_node, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_style, 5) then @(content_node, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_script, 6) then @(content_node, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_html, 4) then
      _runs_nodes(data, children, top, readable, block, blocks, content_node, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_body, 4) then
      _runs_nodes(data, children, top, readable, block, blocks, content_node, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_br, 2) then @(content_node + 1, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_hr, 2) then @(content_node + 1, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_img, 3) then @(content_node + 1, blocks, found)
    else if xml_name_eq(data, name_offset, name_len, _tag_image, 5) then @(content_node + 1, blocks, found)
    else let
      (* a block holding no other block starts one of its own *)
      val starts = (if block >= 0 then false
        else if _block_tag(data, name_offset, name_len) then ~_blocks_within(data, children)
        else false): bool
      val inner_block = (if starts then (blocks: Int) else block): Int
      val inner_blocks = (if starts then blocks + 1 else blocks): Nat
    in _runs_nodes(data, children, false, (if annotation then false else readable), inner_block, inner_blocks, content_node + 1, found) end
  end

(* The runs' text placed in the script's text of size bytes: each run's
   block, content node, and where its decoded text is,
   [start, start + length) *)
datavtype placed_runs(size:int, int) =
  | PlacedEnd(size, 0) of ()
  | {count:nat}{start,length:nat | start + length <= size; length > 0}
    PlacedRun(size, count + 1) of (Nat, Nat, int start, int length, placed_runs(size, count))

fun _placed_free {size:int}{count:nat} .<count>. (runs: placed_runs(size, count)): void =
  case+ runs of
  | ~PlacedEnd() => ()
  | ~PlacedRun(_, _, _, _, rest) => _placed_free(rest)

fun _placed_reverse {size:int}{count,reversed_count:nat} .<count>.
  (runs: placed_runs(size, count), reversed: placed_runs(size, reversed_count)): placed_runs(size, count + reversed_count) =
  case+ runs of
  | ~PlacedEnd() => reversed
  | ~PlacedRun(block, node, start, length, rest) => _placed_reverse(rest, PlacedRun(block, node, start, length, reversed))

(* The bytes of the runs' text, before it is decoded (at least what it
   takes decoded) *)
fun _runs_total {n:int}{count:nat} .<count>. (runs: !text_runs(n, count), total: Nat): Nat =
  case+ runs of
  | TextRunsEnd() => total
  | TextRun(_, _, _, length, rest) => _runs_total(rest, total + length)

(* source[0, count) at target[at, at + count) *)
fun _bytes_into {source_loc,target_loc:agz}{owner:addr}{source_size,target_size:nat}{count:nat | count <= source_size}{at:nat | at + count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, target: !$A.arrx(byte, target_loc, target_size, owner), at: int at, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, at + i, $A.get<byte>(source, i))
  in _bytes_into(source, count, target, at, i + 1) end

(* Each run's text decoded into text[at, size), in order: where each
   went (the latest first) *)
fun _runs_write {l,text_loc:agz}{owner:addr}{n,size:pos}{count,placed_count:nat}{at:nat | at <= size} .<count>.
  (data: !$A.borrow(byte, l, n), runs: text_runs(n, count), text: !$A.arrx(byte, text_loc, size, owner), size: int size, at: int at, placed: placed_runs(size, placed_count))
  : [new_count:nat] placed_runs(size, new_count) =
  case+ runs of
  | ~TextRunsEnd() => placed
  | ~TextRun(block, node, offset, length, rest) =>
    if length <= 0 then _runs_write(data, rest, text, size, at, placed)
    else let
      val decoded = $A.alloc<byte>(length)
      val decoded_len = decode_text(data, offset, length, decoded)
    in
      if decoded_len <= 0 then let
        val () = $A.free<byte>(decoded)
      in _runs_write(data, rest, text, size, at, placed) end
      else if at + decoded_len > size then let
        val () = $A.free<byte>(decoded)
        val () = _text_runs_free(rest)
      in placed end
      else let
        val () = _bytes_into(decoded, decoded_len, text, at, 0)
        val () = $A.free<byte>(decoded)
      in _runs_write(data, rest, text, size, at + decoded_len, PlacedRun(block, node, at, decoded_len, placed)) end
    end

(* The runs of block at the head of runs (in order), and those after *)
fun _block_split {size:int}{count:nat} .<count>. (runs: placed_runs(size, count), block: Nat)
  : [taken,left:nat | taken + left == count] @(placed_runs(size, taken), placed_runs(size, left)) =
  case+ runs of
  | ~PlacedEnd() => @(PlacedEnd(), PlacedEnd())
  | ~PlacedRun(run_block, node, start, length, rest) =>
    if run_block <> block then @(PlacedEnd(), PlacedRun(run_block, node, start, length, rest))
    else let
      val @(taken, left) = _block_split(rest, block)
    in @(PlacedRun(run_block, node, start, length, taken), left) end

(* Where the last of the runs ends, at least at *)
fun _runs_end {size:int}{count:nat}{at:nat | at <= size} .<count>. (runs: !placed_runs(size, count), at: int at): [end_at:nat | at <= end_at; end_at <= size] int end_at =
  case+ runs of
  | PlacedEnd() => at
  | PlacedRun(_, _, start, length, rest) =>
    if start + length >= at then _runs_end(rest, start + length) else _runs_end(rest, at)

(* The UTF-16 units of text[from, until), as the page counts a text
   node's offsets: one for each character, two for one past U+FFFF (a
   4-byte character) *)
fun _utf16_units {l:agz}{owner:addr}{size:nat}{from,until:nat | from <= until; until <= size} .<until - from>.
  (text: !$A.arrx(byte, l, size, owner), from: int from, until: int until, units: Nat): Nat =
  if from >= until then units
  else let
    val code = byte2int0($A.get<byte>(text, from))
    val more = (if code >= 240 then 2 else if $AR.band_int_int(code, 192) = 128 then 0 else 1): Nat
  in _utf16_units(text, from + 1, until, units + more) end

(* The content node and offset where text[at] is: in the run that holds
   it; -1 when none does *)
fun _point_from {l:agz}{owner:addr}{size:int}{count:nat} .<count>.
  (runs: !placed_runs(size, count), text: !$A.arrx(byte, l, size, owner), at: Int): @(Int, Int) =
  case+ runs of
  | PlacedEnd() => @(~1, 0)
  | PlacedRun(_, node, start, length, rest) =>
    if at < start then _point_from(rest, text, at)
    else if at >= start + length then _point_from(rest, text, at)
    else @(node, _utf16_units(text, start, at, 0))

(* The content node and offset where text[.., at) ends: in the run whose
   text it ends in; -1 when none *)
fun _point_until {l:agz}{owner:addr}{size:int}{count:nat} .<count>.
  (runs: !placed_runs(size, count), text: !$A.arrx(byte, l, size, owner), at: Int): @(Int, Int) =
  case+ runs of
  | PlacedEnd() => @(~1, 0)
  | PlacedRun(_, node, start, length, rest) =>
    if at <= start then _point_until(rest, text, at)
    else if at > start + length then _point_until(rest, text, at)
    else @(node, _utf16_units(text, start, at, 0))

(* A chapter's sentences, each its text in the script's text of size
   bytes, [start, start + length), and where it is on the page: from
   offset start_offset (UTF-16 units) of content node start_node to
   end_offset of end_node *)
#pub datavtype sentences_of(size:int, int) =
  | SentencesNone(size, 0) of ()
  | {count:nat}{start,length:nat | start + length <= size; length > 0}
    SentenceOf(size, count + 1) of (int start, int length, Int, Int, Int, Int, sentences_of(size, count))

fun _sentences_of_free {size:int}{count:nat} .<count>. (sentences: sentences_of(size, count)): void =
  case+ sentences of
  | ~SentencesNone() => ()
  | ~SentenceOf(_, _, _, _, _, _, rest) => _sentences_of_free(rest)

fun _sentences_of_reverse {size:int}{count,reversed_count:nat} .<count>.
  (sentences: sentences_of(size, count), reversed: sentences_of(size, reversed_count)): sentences_of(size, count + reversed_count) =
  case+ sentences of
  | ~SentencesNone() => reversed
  | ~SentenceOf(start, length, start_node, start_offset, end_node, end_offset, rest) =>
    _sentences_of_reverse(rest, SentenceOf(start, length, start_node, start_offset, end_node, end_offset, reversed))

(* Whether a byte is white space *)
fn _white (code: int): bool = if code = 32 then true else if code = 9 then true else if code = 10 then true else code = 13

fun _skip_white {l:agz}{owner:addr}{size:nat}{at,until:nat | at <= until; until <= size} .<until - at>.
  (text: !$A.arrx(byte, l, size, owner), at: int at, until: int until): [first:nat | at <= first; first <= until] int first =
  if at >= until then until
  else if _white(byte2int0($A.get<byte>(text, at))) then _skip_white(text, at + 1, until)
  else at

fun _trim_white {l:agz}{owner:addr}{size:nat}{low,until:nat | low <= until; until <= size} .<until - low>.
  (text: !$A.arrx(byte, l, size, owner), low: int low, until: int until): [last:nat | low <= last; last <= until] int last =
  if until <= low then low
  else if _white(byte2int0($A.get<byte>(text, until - 1))) then _trim_white(text, low, until - 1)
  else until

(* The sentence text[from, until) of a block whose runs are runs, its
   white space at either end left out, added to found (when it says
   anything) *)
fn _sentence_add {l:agz}{owner:addr}{size:nat}{runs_count,count:nat}
  (runs: !placed_runs(size, runs_count), text: !$A.arrx(byte, l, size, owner), size: int size, from: Int, until: Int,
   found: sentences_of(size, count), count: int count)
  : [new_count:nat] @(sentences_of(size, new_count), int new_count) =
  if from < 0 then @(found, count)
  else if until > size then @(found, count)
  else if from >= until then @(found, count)
  else let
    val first = _skip_white(text, from, until)
    val last = _trim_white(text, first, until)
  in
    if first >= last then @(found, count)
    else let
      val @(start_node, start_offset) = _point_from(runs, text, first)
      val @(end_node, end_offset) = _point_until(runs, text, last)
    in
      if start_node < 0 then @(found, count)
      else if end_node < 0 then @(found, count)
      else @(SentenceOf(first, last - first, start_node, start_offset, end_node, end_offset, found), count + 1)
    end
  end

(* The sentences segment_sentences found in a block's text, which is
   text[block_start, block_start + block_len), added to found *)
fun _starts_add {l:agz}{owner:addr}{size:nat}{runs_count,count:nat}{block_len:pos}{first:nat | first <= block_len}{block_start:nat} .<block_len - first>.
  (starts: $SP.sentences(block_len, first), block_len: int block_len, block_start: int block_start,
   runs: !placed_runs(size, runs_count), text: !$A.arrx(byte, l, size, owner), size: int size,
   found: sentences_of(size, count), count: int count)
  : [new_count:nat] @(sentences_of(size, new_count), int new_count) =
  case+ starts of
  | ~$SP.SentencesEnd() => @(found, count)
  | ~$SP.Sentence(start, rest) => let
      val next = (case+ rest of
        | $SP.SentencesEnd() => block_len
        | $SP.Sentence(next_start, _) => next_start): Int
      val @(found_after, count_after) = _sentence_add(runs, text, size, block_start + start, block_start + next, found, count)
    in _starts_add(rest, block_len, block_start, runs, text, size, found_after, count_after) end

(* text[from, from + count) into copy *)
fun _bytes_out {l,copy_loc:agz}{owner,copy_owner:addr}{size,copy_size:nat}{from,count:nat | from + count <= size; count <= copy_size}{i:nat | i <= count} .<count - i>.
  (text: !$A.arrx(byte, l, size, owner), from: int from, count: int count, copy: !$A.arrx(byte, copy_loc, copy_size, copy_owner), i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(copy, i, $A.get<byte>(text, from + i))
  in _bytes_out(text, from, count, copy, i + 1) end

(* A block's sentences (its runs are runs, in order), in the book's
   language lang[0, lang_len), added to found: as segment_sentences
   finds them, or the block whole when it cannot *)
fn _block_sentences {l,lang_loc:agz}{owner:addr}{size:nat}{runs_count:pos}{count:nat}{lang_len:nat | lang_len <= 36}
  (runs: !placed_runs(size, runs_count), text: !$A.arrx(byte, l, size, owner), size: int size,
   lang: !$A.borrow(byte, lang_loc, 36), lang_len: int lang_len,
   found: sentences_of(size, count), count: int count)
  : [new_count:nat] @(sentences_of(size, new_count), int new_count) = let
  val block_start = (case+ runs of PlacedRun(_, _, start, _, _) => start | PlacedEnd() => 0): [start:nat | start <= size] int start
  val block_end = _runs_end(runs, block_start)
  val block_len = block_end - block_start
in
  if block_len <= 0 then @(found, count)
  else if block_len > 268435456 then @(found, count)
  else case+ piece_new(block_len) of
  | ~NoPiece() => @(found, count)
  | ~Piece(copy_owner, copy) => let
      val () = _bytes_out(text, block_start, block_len, copy, 0)
      val @(copy_frozen, copy_bytes) = $A.freeze<byte>(copy)
      val segmented = $SP.segment_sentences(copy_bytes, block_len, lang, lang_len)
      val () = $A.drop<byte>(copy_frozen, copy_bytes)
      val () = piece_free(copy_owner, $A.thaw<byte>(copy_frozen))
    in
      case+ segmented of
      | ~$R.some(starts) => _starts_add(starts, block_len, block_start, runs, text, size, found, count)
      | ~$R.none() => _sentence_add(runs, text, size, block_start, block_end, found, count)
    end
end

(* Every block's sentences, the blocks' runs being runs (in order),
   added to found *)
fun _blocks_sentences {l,lang_loc:agz}{owner:addr}{size:nat}{runs_count,count:nat}{lang_len:nat | lang_len <= 36} .<runs_count>.
  (runs: placed_runs(size, runs_count), text: !$A.arrx(byte, l, size, owner), size: int size,
   lang: !$A.borrow(byte, lang_loc, 36), lang_len: int lang_len,
   found: sentences_of(size, count), count: int count)
  : [new_count:nat] @(sentences_of(size, new_count), int new_count) =
  case+ runs of
  | ~PlacedEnd() => @(found, count)
  | ~PlacedRun(block, node, start, length, rest) => let
      val @(same, others) = _block_split(rest, block)
      val this_block = PlacedRun(block, node, start, length, same)
      val @(found_after, count_after) = _block_sentences(this_block, text, size, lang, lang_len, found, count)
      val () = _placed_free(this_block)
    in _blocks_sentences(others, text, size, lang, lang_len, found_after, count_after) end

(* A chapter's sentences, read aloud one after another: its text read
   aloud (the text of its blocks, decoded, a piece of book content held
   while it is read), its sentences, how many, and the chapter's index
   (from 0); none when it has nothing to read *)
#pub datavtype script =
  | {arena_loc,piece_loc:agz}{size:pos}{count:pos}
    Script of (piece_owner(size, arena_loc), $A.arrx(byte, piece_loc, size, arena_loc), sentences_of(size, count), int count, Nat)
  | NoScript of ()

#pub fun script_free (script: script): void
implement script_free (script) =
  case+ script of
  | ~NoScript() => ()
  | ~Script(owner, text, sentences, _, _) => let
      val () = _sentences_of_free(sentences)
    in piece_free(owner, text) end
implement $P.dispose<script>(script) = script_free(script)

(* The script of the chapter data[0, n), whose nodes are nodes, of
   index chapter *)
fn _script_make {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), chapter: Nat): script = let
  val @(_, _, found) = _runs_nodes(data, nodes, true, true, ~1, 0, 0, TextRunsEnd())
  val runs = _text_runs_reverse(found, TextRunsEnd())
  val total = _runs_total(runs, 0)
in
  if total <= 0 then let val () = _text_runs_free(runs) in NoScript() end
  else if total > 268435456 then let val () = _text_runs_free(runs) in NoScript() end
  else case+ piece_new(total) of
  | ~NoPiece() => let val () = _text_runs_free(runs) in NoScript() end
  | ~Piece(owner, text) => let
      val placed = _placed_reverse(_runs_write(data, runs, text, total, 0, PlacedEnd()), PlacedEnd())
      val @(lang, lang_len) = reader_lang_tag()
      val @(lang_frozen, lang_bytes) = $A.freeze<byte>(lang)
      val @(found_sentences, count) = _blocks_sentences(placed, text, total, lang_bytes, lang_len, SentencesNone(), 0)
      val () = release_bytes(lang_frozen, lang_bytes)
      val sentences = _sentences_of_reverse(found_sentences, SentencesNone())
    in
      if count <= 0 then let
        val () = _sentences_of_free(sentences)
        val () = piece_free(owner, text)
      in NoScript() end
      else Script(owner, text, sentences, count, chapter)
    end
end

(* Reads chapter chapter (from 0) of the open book, and makes its
   script: the promise resolves with it (NoScript when the chapter
   cannot be read) *)
#pub fun reader_script_load {chapter:nat} (chapter: int chapter): $P.promise(script, $P.Chained)

implement reader_script_load (chapter) = let
  val serial = book_serial()
in
  case+ book_chapter_get(serial, chapter) of
  | ~ChaptersUnknown() => $P.ret<script>(NoScript())
  | ~ChapterNone(_) => $P.ret<script>(NoScript())
  | ~ChapterGot(file_size, chapter_start, compressed_size, method, _, _, _, _) =>
    (case+ piece_new(compressed_size) of
     | ~NoPiece() => $P.ret<script>(NoScript())
     | ~Piece(compressed_owner, compressed) => let
         val _ = book_read(serial, file_size, chapter_start, compressed, compressed_size)
         val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
         val decompressing = decompress(compressed_bytes, compressed_size, zip_compression(method))
         val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
         val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
       in
         $P.and_then<Int><script>($P.vow(decompressing), llam(handle) =>
           case+ take_content(handle) of
           | ~NoContentBytes() => $P.ret<script>(NoScript())
           | ~ContentBytes(xhtml_owner, xhtml, xhtml_size) => let
               val @(xhtml_frozen, xhtml_bytes) = $A.freeze<byte>(xhtml)
               val nodes = $X.parse_document(xhtml_bytes, xhtml_size)
               val script = _script_make(xhtml_bytes, nodes, chapter)
               val () = $X.free_nodes(nodes)
               val () = $A.drop<byte>(xhtml_frozen, xhtml_bytes)
               val () = piece_free(xhtml_owner, $A.thaw<byte>(xhtml_frozen))
             in $P.ret<script>(script) end)
       end)
end

(* Sentence index of a script: where it is on the page, @(start node,
   start offset, end node, end offset); a start node of -1 when there is
   no such sentence *)
fun _sentence_place {size:int}{count:nat} .<count>. (sentences: !sentences_of(size, count), index: int): @(Int, Int, Int, Int) =
  case+ sentences of
  | SentencesNone() => @(~1, 0, ~1, 0)
  | SentenceOf(_, _, start_node, start_offset, end_node, end_offset, rest) =>
    if index <= 0 then @(start_node, start_offset, end_node, end_offset)
    else _sentence_place(rest, index - 1)

#pub fun script_place (script: !script, index: int): @(Int, Int, Int, Int)
implement script_place (script, index) =
  case+ script of
  | NoScript() => @(~1, 0, ~1, 0)
  | Script(_, _, sentences, _, _) => _sentence_place(sentences, index)

(* How many sentences a script has, and its chapter's index; -1 for none *)
#pub fun script_count (script: !script): Nat
implement script_count (script) =
  case+ script of
  | NoScript() => 0
  | Script(_, _, _, count, _) => count

#pub fun script_chapter (script: !script): Int
implement script_chapter (script) =
  case+ script of
  | NoScript() => ~1
  | Script(_, _, _, _, chapter) => chapter

(* Where sentence index's text is in the script's text, and how long *)
fun _sentence_span {size:nat}{count:nat} .<count>. (sentences: !sentences_of(size, count), index: int)
  : [start,length:nat | start + length <= size] @(int start, int length) =
  case+ sentences of
  | SentencesNone() => @(0, 0)
  | SentenceOf(start, length, _, _, _, _, rest) =>
    if index <= 0 then @(start, length) else _sentence_span(rest, index - 1)

(* Sentence index's text, in a piece of its own (book content), and its
   length; none when there is no such sentence or no memory for it *)
#pub datavtype sentence_text =
  | {arena_loc,piece_loc:agz}{length:pos}
    SentenceText of (piece_owner(length, arena_loc), $A.arrx(byte, piece_loc, length, arena_loc), int length)
  | NoSentenceText of ()

#pub fun script_text (script: !script, index: int): sentence_text
implement script_text (script, index) =
  case+ script of
  | NoScript() => NoSentenceText()
  | Script(_, text, sentences, _, _) => let
      val @(start, length) = _sentence_span(sentences, index)
    in
      if length <= 0 then NoSentenceText()
      else if length > 268435456 then NoSentenceText()
      else case+ piece_new(length) of
      | ~NoPiece() => NoSentenceText()
      | ~Piece(copy_owner, copy) => let
          val () = _bytes_out(text, start, length, copy, 0)
        in SentenceText(copy_owner, copy, length) end
    end

end (* #target wasm *)
