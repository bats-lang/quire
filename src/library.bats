(* library -- the books quire keeps: their records, stored and shown *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S

staload "ui.sats"
staload "notice.sats"
staload "book.sats"
staload "modal.sats"
staload "undo.sats"
staload "epub_xml.sats"
staload "mem.sats"
staload "clock.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload "storage.sats"
staload "paths.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"

implement $P.dispose<reply>(_) = ()

(* ============================================================
   Records
   ============================================================ *)

(* Where a book is kept: on the shelf, hidden, archived, or in the
   Trash *)
#pub datatype shelf = OnShelf | Hidden | Archived | Trash

(* Whether two shelves are the same *)
#pub fn same_shelf (a: shelf, b: shelf): bool

implement same_shelf (a, b) =
  case+ (a, b) of
  | (OnShelf(), OnShelf()) => true | (Hidden(), Hidden()) => true
  | (Archived(), Archived()) => true | (Trash(), Trash()) => true
  | (_, _) => false

(* A shelf as the library and backups store it: 0 the shelf, 1 hidden,
   2 archived, 3 the Trash *)
#pub fn shelf_code (s: shelf): [code:nat | code <= 3] int code

implement shelf_code (s) =
  case+ s of OnShelf() => 0 | Hidden() => 1 | Archived() => 2 | Trash() => 3

(* The shelf a stored code stands for (shelf_code); the shelf for any
   other *)
#pub fn shelf_of_code (code: int): shelf

implement shelf_of_code (code) =
  if code = 1 then Hidden() else if code = 2 then Archived() else if code = 3 then Trash() else OnShelf()

(* A book's numbers. Its id is the first 14 hex digits of its file's
   SHA-256, as two 28-bit halves (id_high the first 7 digits, id_low
   the last 7); its key numbers it in this run (it is not stored).
   Times are minutes since the epoch. *)
#pub typedef bnums = @{
  key = Int,
  id_high = Int, id_low = Int,
  shelf = shelf,
  added = Int,
  opened = Int,         (* 0 when never read *)
  chapter = Int,        (* the chapter read last, from 0 *)
  chapters = Int,       (* the book's chapters, 0 when not known yet *)
  page = Int,           (* the page read last, of pages in that chapter *)
  pages = Int,
  anchor = Int,         (* the content node at that page's start, -1 none *)
  file_size = Int,      (* the file's bytes *)
  cover = image_type,   (* the cover image's type, NotAnImage when none *)
  done = Int,           (* 1 when the last page was reached *)
  series_number = Int,  (* its number in its series, 0 when none is given *)
  collections = Int,    (* the collections it is in: collection j is bit j *)
  minutes_read = Int,   (* the minutes it has been read (a page turned on
                           within 3 minutes of the one before counts its
                           minutes) *)
  pages_read = Int,     (* the pages turned on those minutes counted *)
  finished_at = Int,    (* when its last page was first reached, 0 when
                           not known *)
  (* when the shelf, the collections it is in and its being finished
     (done and finished_at) last changed: stamps (clock.bats), 0 never,
     which sync compares (the latest change wins) *)
  shelf_modified = Int,
  collections_modified = Int,
  finished_modified = Int,
  (* the minutes it has been read and the pages turned on them on the
     other devices sync knows of, as it last saw them *)
  minutes_elsewhere = Int,
  pages_elsewhere = Int
}

(* A book: its title and author (1 to 255 bytes), its series' name (0
   to 255 bytes, in an array one longer) and its numbers *)
#pub datavtype book =
  | {title_loc,author_loc,series_loc:agz}{title_len,author_len:pos | title_len < 256; author_len < 256}
    {series_len:nat | series_len < 256}
    Book of ($A.arr(byte, title_loc, title_len), int title_len, $A.arr(byte, author_loc, author_len), int author_len,
             $A.arr(byte, series_loc, series_len + 1), int series_len, bnums)

#pub stadef LIB_MAX = 100000

#pub datavtype books(int) =
  | books_nil(0) of ()
  | {count:nat} books_cons(count + 1) of (book, books(count))

fn book_free (book: book): void = let
  val+ ~Book(title, _, author, _, series, _, _) = book
  val () = $A.free<byte>(title)
  val () = $A.free<byte>(series)
in $A.free<byte>(author) end

fun books_free {count:nat} .<count>. (books: books(count)): void =
  case+ books of
  | ~books_nil() => ()
  | ~books_cons(book, rest) => let val () = book_free(book) in books_free(rest) end

(* ============================================================
   The library, and what the library view shows of it
   ============================================================ *)

datavtype lib_cell =
  | {count:nat | count <= LIB_MAX} LibCell of (books(count), int count)

val _lib = ref<lib_cell>(LibCell(books_nil(), 0))
val _next_key = ref<Int>(1)

(* The orders the library sorts its books in *)
#pub datatype sort_order = LastOpened | ByTitle | ByAuthor | DateAdded | BySeries

(* The next order the sort button gives *)
#pub fn sort_next (order: sort_order): sort_order

implement sort_next (order) =
  case+ order of
  | LastOpened() => ByTitle() | ByTitle() => ByAuthor() | ByAuthor() => DateAdded()
  | DateAdded() => BySeries() | BySeries() => LastOpened()

(* An order as backups and the settings keep it: 0 last opened, 1 title,
   2 author, 3 date added, 4 series *)
#pub fn sort_code (order: sort_order): [code:nat | code <= 4] int code

implement sort_code (order) =
  case+ order of
  | LastOpened() => 0 | ByTitle() => 1 | ByAuthor() => 2 | DateAdded() => 3 | BySeries() => 4

(* The order a kept code stands for (sort_code); last opened for any
   other *)
#pub fn sort_of_code (code: int): sort_order

implement sort_of_code (code) =
  if code = 1 then ByTitle() else if code = 2 then ByAuthor() else if code = 3 then DateAdded()
  else if code = 4 then BySeries() else LastOpened()

val _sort_order = ref<sort_order>(LastOpened())
val _shelf = ref<shelf>(OnShelf())
(* The library view's render: an image that arrives after another
   render is not shown *)
val _render_gen = ref<int>(0)

(* The search query, lowercased *)
datavtype query =
  | {l:agz}{n:pos | n < 256} QuerySome of ($A.arr(byte, l, n), int n)
  | QueryNone of ()

val _query = ref<query>(QueryNone())

fn lib_take (): lib_cell = let
  var cell: lib_cell = LibCell(books_nil(), 0)
  val () = ref_exch_elt<lib_cell>(_lib, cell)
in cell end

fn lib_put (cell: lib_cell): void = let
  var current: lib_cell = cell
  val () = ref_exch_elt<lib_cell>(_lib, current)
  val+ ~LibCell(books, _) = current
in books_free(books) end

fn query_take (): query = let
  var taken: query = QueryNone()
  val () = ref_exch_elt<query>(_query, taken)
in taken end

fn query_put (query: query): void = let
  var current: query = query
  val () = ref_exch_elt<query>(_query, current)
in
  case+ current of
  | ~QuerySome(query_bytes, _) => $A.free<byte>(query_bytes)
  | ~QueryNone() => ()
end

#pub fn lib_count (): [count:nat | count <= LIB_MAX] int count

implement lib_count () = let
  val cell = lib_take()
  val+ LibCell(_, count) = cell
  val () = lib_put(cell)
in count end

#pub fn lib_sort_get (): sort_order
implement lib_sort_get () = !_sort_order

#pub fn lib_shelf_get (): shelf
implement lib_shelf_get () = !_shelf

(* ============================================================
   Ids and keys
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

(* The storage key of a book's file ('b'), cover ('c') or annotations
   ('a'): the letter and the book's 14 hex digits *)
#pub fn lib_key {letter:nat | letter < 256} (letter: int letter, id_high: int, id_low: int): [l:agz] $A.arr(byte, l, 15)

implement lib_key (letter, id_high, id_low) = let
  val key = $A.alloc<byte>(15)
  val () = $A.write_byte(key, 0, letter)
  val () = _put_seven_hex(key, 1, id_high)
  val () = _put_seven_hex(key, 8, id_low)
in key end

(* The value of hex digit byte_value (0 for any other byte) *)
fn _hex_value {byte_value:nat | byte_value < 256} (byte_value: int byte_value): [value:nat | value < 16] int value =
  if byte_value >= 48 then (if byte_value <= 57 then byte_value - 48
    else if byte_value >= 97 then (if byte_value <= 102 then byte_value - 87 else 0) else 0)
  else 0

fn _hex_at {l:agz}{i:nat | i < 64} (digest: !$A.arr(byte, l, 64), i: int i): [value:nat | value < 16] int value =
  _hex_value($AR.low_byte(byte2int0($A.get<byte>(digest, i))))

(* The 7 hex digits digest[start, start + 7) *)
fn _seven_hex {l:agz}{start:nat | start + 7 <= 64} (digest: !$A.arr(byte, l, 64), start: int start): Int =
  ((((((_hex_at(digest, start) * 16 + _hex_at(digest, start + 1)) * 16 + _hex_at(digest, start + 2)) * 16
    + _hex_at(digest, start + 3)) * 16 + _hex_at(digest, start + 4)) * 16 + _hex_at(digest, start + 5)) * 16
    + _hex_at(digest, start + 6))

(* A book's id from its SHA-256 in hex *)
#pub fn lib_id_of_hex {l:agz} (digest: !$A.arr(byte, l, 64)): @(Int, Int)

implement lib_id_of_hex (digest) = @(_seven_hex(digest, 0), _seven_hex(digest, 7))

(* ============================================================
   Finding books
   ============================================================ *)

fun _find {count:nat}{i:nat} .<count>. (books: !books(count), id_high: int, id_low: int, i: int i): [found:int | found >= ~1] int found =
  case+ books of
  | books_nil() => ~1
  | books_cons(book, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = book
    in if nums.id_high = id_high then (if nums.id_low = id_low then i else _find(rest, id_high, id_low, i + 1))
       else _find(rest, id_high, id_low, i + 1) end

(* The index of the book with this id, or -1 *)
#pub fn lib_find (id_high: int, id_low: int): [found:int | found >= ~1] int found

implement lib_find (id_high, id_low) = let
  val cell = lib_take()
  val+ @LibCell(books, _) = cell
  val found = _find(books, id_high, id_low, 0)
  prval () = fold@(cell)
  val () = lib_put(cell)
in found end

fun _find_key {count:nat}{i:nat} .<count>. (books: !books(count), key: int, i: int i): [found:int | found >= ~1] int found =
  case+ books of
  | books_nil() => ~1
  | books_cons(book, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = book
    in if nums.key = key then i else _find_key(rest, key, i + 1) end

#pub fn lib_index_of_key (key: int): [found:int | found >= ~1] int found

implement lib_index_of_key (key) = let
  val cell = lib_take()
  val+ @LibCell(books, _) = cell
  val found = _find_key(books, key, 0)
  prval () = fold@(cell)
  val () = lib_put(cell)
in found end

(* The numbers of the book at index (when there is one) *)
fun _nums_at {count:nat}{index:nat} .<count>. (books: !books(count), index: int index): $R.option(bnums) =
  case+ books of
  | books_nil() => $R.none()
  | books_cons(book, rest) =>
    if index = 0 then let val+ Book(_, _, _, _, _, _, nums) = book in $R.some(nums) end
    else _nums_at(rest, index - 1)

#pub fn lib_nums {index:int} (index: int index): $R.option(bnums)

implement lib_nums (index) =
  if index < 0 then $R.none()
  else let
    val cell = lib_take()
    val+ @LibCell(books, _) = cell
    val nums = _nums_at(books, index)
    prval () = fold@(cell)
    val () = lib_put(cell)
  in nums end

(* Sets the numbers of the book at index to changed *)
fun _set_at {count:nat}{index:nat} .<count>. (books: !books(count), index: int index, changed: bnums): void =
  case+ books of
  | books_nil() => ()
  | @books_cons(book, rest) =>
    if index = 0 then let
      val+ @Book(_, _, _, _, _, _, nums) = book
      val () = nums := changed
      prval () = fold@(book)
      prval () = fold@(books)
    in end
    else let
      val () = _set_at(rest, index - 1, changed)
      prval () = fold@(books)
    in end

(* The numbers of the book at index set to changed (a change made from
   what lib_nums read) *)
#pub fn lib_nums_set {index:int} (index: int index, changed: bnums): void

implement lib_nums_set (index, changed) =
  if index < 0 then ()
  else let
    val cell = lib_take()
    val+ @LibCell(books, _) = cell
    val () = _set_at(books, index, changed)
    prval () = fold@(cell)
  in lib_put(cell) end

(* The reading on other devices (sync's) of every book, forgotten: what
   sync reads next is summed anew *)
fun _elsewhere_clear {count:nat} .<count>. (books: !books(count)): void =
  case+ books of
  | books_nil() => ()
  | @books_cons(book, rest) => let
      val+ @Book(_, _, _, _, _, _, nums) = book
      val () = nums := @{
        key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = nums.shelf, added = nums.added, opened = nums.opened,
        chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
        file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number, collections = nums.collections, minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
        shelf_modified = nums.shelf_modified, collections_modified = nums.collections_modified,
        finished_modified = nums.finished_modified, minutes_elsewhere = 0, pages_elsewhere = 0 }
      prval () = fold@(book)
      val () = _elsewhere_clear(rest)
      prval () = fold@(books)
    in end

#pub fn lib_elsewhere_clear (): void
implement lib_elsewhere_clear () = let
  val cell = lib_take()
  val+ @LibCell(books, _) = cell
  val () = _elsewhere_clear(books)
  prval () = fold@(cell)
in lib_put(cell) end

(* minutes more read, and pages turned on them, on another device of
   the book at index *)
#pub fn lib_elsewhere_add {index:int} (index: int index, minutes: Int, pages: Int): void
implement lib_elsewhere_add (index, minutes, pages) =
  if minutes <= 0 then ()
  else (case+ lib_nums(index) of ~$R.none() => () | ~$R.some(nums) => lib_nums_set(index, @{
    key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = nums.shelf, added = nums.added, opened = nums.opened,
    chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
    file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number, collections = nums.collections, minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
    shelf_modified = nums.shelf_modified, collections_modified = nums.collections_modified,
    finished_modified = nums.finished_modified, minutes_elsewhere = nums.minutes_elsewhere + minutes,
    pages_elsewhere = nums.pages_elsewhere + ((if pages > 0 then pages else 0): Int) }))

(* source[j, source_len) into dest[start + j, start + source_len) *)
fun _copy {source_loc,dest_loc:agz}{source_len,source_size,dest_size:nat | source_len <= source_size}
  {start:nat | start + source_len <= dest_size}{j:nat | j <= source_len} .<source_len - j>.
  (source: !$A.arr(byte, source_loc, source_size), source_len: int source_len,
   dest: !$A.arr(byte, dest_loc, dest_size), start: int start, j: int j): void =
  if j >= source_len then ()
  else let
    val () = $A.set<byte>(dest, start + j, $A.get<byte>(source, j))
  in _copy(source, source_len, dest, start, j + 1) end

(* Which text of a book: its title or its author *)
#pub datatype book_text = TitleText | AuthorText

(* The title or author (which) of the book at index, in a fresh array *)
fun _text_at {count:nat}{index:nat} .<count>. (books: !books(count), index: int index, which: book_text)
  : [l:agz][n:nat | n < 256] @($A.arr(byte, l, n + 1), int n) =
  case+ books of
  | books_nil() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  | books_cons(book, rest) =>
    if index = 0 then let
      val+ Book(title, title_len, author, author_len, _, _, _) = book
    in
      case+ which of
      | TitleText() => let
          val text = $A.alloc<byte>(title_len + 1)
          val () = _copy(title, title_len, text, 0, 0)
        in @(text, title_len) end
      | AuthorText() => let
          val text = $A.alloc<byte>(author_len + 1)
          val () = _copy(author, author_len, text, 0, 0)
        in @(text, author_len) end
    end
    else _text_at(rest, index - 1, which)

(* The title or author (which) of the book at index: the bytes and their
   count (0 when there is no such book) in an array one longer *)
#pub fn lib_text {index:int} (index: int index, which: book_text): [l:agz][n:nat | n < 256] @($A.arr(byte, l, n + 1), int n)

implement lib_text (index, which) =
  if index < 0 then let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  else let
    val cell = lib_take()
    val+ @LibCell(books, _) = cell
    val text = _text_at(books, index, which)
    prval () = fold@(cell)
    val () = lib_put(cell)
  in text end

(* ============================================================
   Adding and removing
   ============================================================ *)

(* A book from span [title_start, title_start + title_span) and
   [author_start, author_start + author_span) of data for its title and
   author: the fallbacks when a span is empty or too long *)
fun _series_copy {data_loc,series_loc:agz}{data_len,series_size:pos}{start:nat}
  {series_len:nat | series_len < series_size; start + series_len <= data_len}{j:nat | j <= series_len} .<series_len - j>.
  (data: !$A.borrow(byte, data_loc, data_len), start: int start,
   series: !$A.arr(byte, series_loc, series_size), series_len: int series_len, j: int j): void =
  if j >= series_len then ()
  else let
    val () = $A.set<byte>(series, j, $A.read<byte>(data, start + j))
  in _series_copy(data, start, series, series_len, j + 1) end

(* A series' name from data[start, start + span_len), at most 255 bytes,
   in an array one longer; empty when there is none *)
(* " · N" after the name at text[0, name_len) *)
fn _series_num {l:agz}{name_len:nat} (text: !$A.arr(byte, l, name_len + 20), name_len: int name_len, number: Int)
  : [text_len:nat | text_len <= name_len + 20] int text_len =
  if number <= 0 then name_len
  else if number > 99999 then name_len
  else let
  val () = $A.set<byte>(text, name_len, $A.int2byte(32))
  val () = $A.set<byte>(text, name_len + 1, $A.int2byte(194))
  val () = $A.set<byte>(text, name_len + 2, $A.int2byte(183))
  val () = $A.set<byte>(text, name_len + 3, $A.int2byte(32))
in $S.int_to_str(text, name_len + 4, name_len + 20, number) end

fn _series_arr {data_loc:agz}{data_len:pos}{start,span_len:nat | start + span_len <= data_len}
  (data: !$A.borrow(byte, data_loc, data_len), data_len: int data_len, start: int start, span_len: int span_len)
  : [l:agz][name_len:nat | name_len < 256] @($A.arr(byte, l, name_len + 1), int name_len) = let
  val name_len = (if span_len > 255 then 255 else span_len): [name_len:nat | name_len <= span_len; name_len < 256] int name_len
  val name = $A.alloc<byte>(name_len + 1)
  val () = _series_copy(data, start, name, name_len, 0)
in @(name, name_len) end

fn _span_arr {data_loc:agz}{data_len:pos}{start,span_len:nat | start + span_len <= data_len}{fallback_len:pos | fallback_len < 256}
  (data: !$A.borrow(byte, data_loc, data_len), data_len: int data_len, start: int start, span_len: int span_len,
   fallback: string fallback_len)
  : [l:agz][text_len:pos | text_len < 256] @($A.arr(byte, l, text_len), int text_len) =
  if span_len <= 0 then let
    val fallback_len = g1u2i(string1_length(fallback))
    val text = $A.alloc<byte>(fallback_len)
    val () = $A.write_text(text, 0, $A.text_lit(fallback), fallback_len)
  in @(text, fallback_len) end
  else if span_len >= 256 then let
    val text = $A.alloc<byte>(255)
    val () = $S.copy_from_borrow(data, start, data_len, text, 0, 255, 255)
  in @(text, 255) end
  else let
    val text = $A.alloc<byte>(span_len)
    val () = $S.copy_from_borrow(data, start, data_len, text, 0, span_len, span_len)
  in @(text, span_len) end

(* Adds a book: its id, title and author (spans of data), file size and
   cover type; its key. None when the library is full. *)
#pub fn lib_add {data_loc:agz}{data_len:pos}
  {title_start,title_span,author_start,author_span,series_start,series_span:nat |
   title_start + title_span <= data_len; author_start + author_span <= data_len; series_start + series_span <= data_len}
  (id_high: Int, id_low: Int, data: !$A.borrow(byte, data_loc, data_len), data_len: int data_len,
   title_start: int title_start, title_span: int title_span, author_start: int author_start, author_span: int author_span,
   series_start: int series_start, series_span: int series_span, series_index: Int,
   file_size: Int, cover: image_type, now: Int): Int

implement lib_add (id_high, id_low, data, data_len, title_start, title_span, author_start, author_span,
                   series_start, series_span, series_index, file_size, cover, now) = let
  val cell = lib_take()
  val+ ~LibCell(books, count) = cell
in
  if count >= 100000 then let
    val () = lib_put(LibCell(books, count))
  in ~1 end
  else let
    val key = !_next_key
    val () = !_next_key := key + 1
    val @(title, title_len) = _span_arr(data, data_len, title_start, title_span, "Imported Book")
    val @(author, author_len) = _span_arr(data, data_len, author_start, author_span, "Unknown Author")
    val @(series, series_len) = _series_arr(data, data_len, series_start, series_span)
    val nums = @{
      key = key, id_high = id_high, id_low = id_low, shelf = OnShelf(), added = now, opened = 0,
      chapter = 0, chapters = 0, page = 0, pages = 0, anchor = ~1, file_size = file_size, cover = cover, done = 0,
      series_number = series_index, collections = 0, minutes_read = 0, pages_read = 0, finished_at = 0,
      shelf_modified = 0, collections_modified = 0, finished_modified = 0, minutes_elsewhere = 0, pages_elsewhere = 0
    }: bnums
    val () = lib_put(LibCell(books_cons(Book(title, title_len, author, author_len, series, series_len, nums), books), count + 1))
  in key end
end

fun _remove_at {count:pos}{index:nat | index < count} .<count>. (books: books(count), index: int index): books(count - 1) = let
  val+ ~books_cons(book, rest) = books
in
  if index = 0 then let val () = book_free(book) in rest end
  else books_cons(book, _remove_at(rest, index - 1))
end

fun _pull {count:pos}{index:nat | index < count} .<count>. (books: books(count), index: int index): @(book, books(count - 1)) = let
  val+ ~books_cons(book, rest) = books
in
  if index = 0 then @(book, rest)
  else let
    val @(pulled, others) = _pull(rest, index - 1)
  in @(pulled, books_cons(book, others)) end
end

(* The series' name of the book at index, from data[start, start +
   span_len) (its file was imported again) *)
fun _series_set_at {count:nat}{data_loc:agz}{data_len:pos}{start,span_len:nat | start + span_len <= data_len} .<count>.
  (books: books(count), index: int, data: !$A.borrow(byte, data_loc, data_len), data_len: int data_len,
   start: int start, span_len: int span_len): books(count) =
  case+ books of
  | ~books_nil() => books_nil()
  | ~books_cons(book, rest) =>
    if index = 0 then let
      val+ ~Book(title, title_len, author, author_len, series, _, nums) = book
      val () = $A.free<byte>(series)
      val @(new_series, new_series_len) = _series_arr(data, data_len, start, span_len)
    in books_cons(Book(title, title_len, author, author_len, new_series, new_series_len, nums), rest) end
    else books_cons(book, _series_set_at(rest, index - 1, data, data_len, start, span_len))

#pub fn lib_series_set {data_loc:agz}{data_len:pos}{start,span_len:nat | start + span_len <= data_len}
  (index: int, data: !$A.borrow(byte, data_loc, data_len), data_len: int data_len, start: int start, span_len: int span_len): void

implement lib_series_set (index, data, data_len, start, span_len) = let
  val cell = lib_take()
  val+ ~LibCell(books, count) = cell
in lib_put(LibCell(_series_set_at(books, index, data, data_len, start, span_len), count)) end

(* Moves the book at index to the front of the library: the sort is
   stable, so of the books opened in the same minute, the one opened
   last comes first *)
#pub fn lib_touch {index:int} (index: int index): void

implement lib_touch (index) = let
  val cell = lib_take()
  val+ ~LibCell(books, count) = cell
in
  if index <= 0 then lib_put(LibCell(books, count))
  else if index >= count then lib_put(LibCell(books, count))
  else let
    val @(pulled, rest) = _pull(books, index)
  in lib_put(LibCell(books_cons(pulled, rest), count)) end
end

(* Removes the book at index from the library. Private: a book is
   removed only when the Trash is emptied, once the dialog lib_ask_harm
   opens is answered Accepted *)
fn _remove {index:int} (index: int index): void = let
  val cell = lib_take()
  val+ ~LibCell(books, count) = cell
in
  if index < 0 then lib_put(LibCell(books, count))
  else if count <= 0 then lib_put(LibCell(books, count))
  else if index >= count then lib_put(LibCell(books, count))
  else lib_put(LibCell(_remove_at(books, index), count - 1))
end

(* Deletes the stored data under the key with this letter of book
   (id_high, id_low) *)
fn _idb_delete {letter:nat | letter < 256} (letter: int letter, id_high: int, id_low: int): void = let
  val key = lib_key(letter, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  (* ignored: a delete that fails leaves bytes nothing reads *)
  val () = $P.finish<$IDB.stored>($IDB.idb_delete(key_bytes, 15), llam(_) => ())
in release_bytes(key_frozen, key_bytes) end

(* Sets the shelf of the book at index, and keeps and shows the
   library *)
#pub fn lib_set_shelf {index:int} (index: int index, shelf: shelf): void

implement lib_set_shelf (index, shelf) = let
  val () = (case+ lib_nums(index) of ~$R.none() => () | ~$R.some(nums) => lib_nums_set(index, @{
    key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = shelf, added = nums.added, opened = nums.opened,
    chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
    file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number, collections = nums.collections, minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
    shelf_modified = stamp_now(), collections_modified = nums.collections_modified, finished_modified = nums.finished_modified,
    minutes_elsewhere = nums.minutes_elsewhere, pages_elsewhere = nums.pages_elsewhere }))
  val () = lib_save()
in lib_render() end

(* Moves the book at index to the Trash at once: nothing of it is lost,
   and Undo (or Restore, from the Trash) puts it back on the shelf it
   was on *)
#pub fn lib_trash {index:int} (index: int index): void

implement lib_trash (index) =
  case+ lib_nums(index) of
  | ~$R.none() => ()
  | ~$R.some(nums) => let
      val key = nums.key
      val old_shelf = nums.shelf
      val () = lib_set_shelf(index, Trash())
    in
      $P.finish<settled>(undo_offer("Moved to Trash"), llam(how) =>
        case+ how of
        | Undone() => let
            val index_now = lib_index_of_key(key)
          in if index_now >= 0 then lib_set_shelf(index_now, old_shelf) else () end
        | Final() => ())
    end

(* The book at index and everything stored for it, deleted *)
fn _delete_book {index:int} (index: int index): void =
  case+ lib_nums(index) of
  | ~$R.none() => ()
  | ~$R.some(nums) => let
      val () = _idb_delete(98, nums.id_high, nums.id_low)
      val () = _idb_delete(99, nums.id_high, nums.id_low)
      val () = _idb_delete(97, nums.id_high, nums.id_low)
      val () = _idb_delete(121, nums.id_high, nums.id_low)
    in _remove(index) end

(* The index of the first book in the Trash from i on, or -1 *)
fun _first_trashed {i,count:nat | i <= count} .<count - i>. (i: int i, count: int count): [found:int | found >= ~1] int found =
  if i >= count then ~1
  else (case+ lib_nums(i) of
    | ~$R.none() => _first_trashed(i + 1, count)
    | ~$R.some(nums) => if same_shelf(nums.shelf, Trash()) then i else _first_trashed(i + 1, count))

(* Deletes the books in the Trash, at most left of them *)
fun _empty_trash {left:nat} .<left>. (left: int left): void =
  if left <= 0 then ()
  else let
    val index = _first_trashed(0, lib_count())
  in
    if index < 0 then () else let val () = _delete_book(index) in _empty_trash(left - 1) end
  end

(* Asks about harm, with the action that does it; if the answer is yes
   (Accepted), it is done. The promise resolves with the answer once
   that is done. HEmptyTrash: every book in the Trash and everything
   stored for it go (and any Undo offer, which could only put back what
   is gone) *)
#pub fn lib_ask_harm (harm: harm): $P.promise(reply, $P.Chained)

implement lib_ask_harm (harm) =
  case+ harm of
  | HEmptyTrash() => $P.and_then<reply><reply>(modal_confirm(harm), llam(answer) =>
    case+ answer of
    | Accepted() => let
        val () = undo_close()
        val () = _empty_trash(lib_count())
      in $P.ret<reply>(Accepted()) end
    | Declined() => $P.ret<reply>(Declined()))

(* Each book's key and the shelf it was on *)
#pub datavtype shelved_list(int) =
  | ShelvedNil(0) of ()
  | {count:nat} ShelvedCons(count + 1) of (int, shelf, shelved_list(count))

#pub vtypedef shelved = [count:nat] shelved_list(count)

fun _shelves {i,count:nat | i <= count}{so_far:nat} .<count - i>. (i: int i, count: int count, shelved: shelved_list(so_far))
  : [total:nat] shelved_list(total) =
  if i >= count then shelved
  else (case+ lib_nums(i) of
    | ~$R.none() => _shelves(i + 1, count, shelved)
    | ~$R.some(nums) => _shelves(i + 1, count, ShelvedCons(nums.key, nums.shelf, shelved)))

(* Every book moved to the Trash (nothing of any is lost) *)
fun _trash_all {i,count:nat | i <= count} .<count - i>. (i: int i, count: int count): void =
  if i >= count then ()
  else let
    val () = (case+ lib_nums(i) of ~$R.none() => () | ~$R.some(nums) => lib_nums_set(i, @{
      key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = Trash(), added = nums.added, opened = nums.opened,
      chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
      file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number, collections = nums.collections, minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
      shelf_modified = stamp_now(), collections_modified = nums.collections_modified, finished_modified = nums.finished_modified,
      minutes_elsewhere = nums.minutes_elsewhere, pages_elsewhere = nums.pages_elsewhere }))
  in _trash_all(i + 1, count) end

(* Each book of shelved put back on its shelf *)
fun _unshelve {count:nat} .<count>. (shelved: shelved_list(count)): void =
  case+ shelved of
  | ~ShelvedNil() => ()
  | ~ShelvedCons(key, shelf, rest) => let
      val index = lib_index_of_key(key)
      val () = (if index >= 0 then (case+ lib_nums(index) of ~$R.none() => () | ~$R.some(nums) => lib_nums_set(index, @{
          key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = shelf, added = nums.added, opened = nums.opened,
          chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
          file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number, collections = nums.collections, minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
          shelf_modified = stamp_now(), collections_modified = nums.collections_modified, finished_modified = nums.finished_modified,
          minutes_elsewhere = nums.minutes_elsewhere, pages_elsewhere = nums.pages_elsewhere })) else ())
    in _unshelve(rest) end

(* A factory reset's part in the library: every book moved to the Trash,
   where it can still be restored. What it returns is each book's shelf
   before, which lib_untrash_all puts back, or lib_shelved_free lets go *)
#pub fn lib_trash_all (): shelved

implement lib_trash_all () = let
  val count = lib_count()
  val shelved = _shelves(0, count, ShelvedNil())
  val () = _trash_all(0, count)
  val () = lib_save()
  val () = lib_render()
in shelved end

(* Each book of shelved put back on its shelf *)
#pub fn lib_untrash_all (shelved: shelved): void
implement lib_untrash_all (shelved) = let
  val () = _unshelve(shelved)
  val () = lib_save()
in lib_render() end

fun _shelved_free {count:nat} .<count>. (shelved: shelved_list(count)): void =
  case+ shelved of
  | ~ShelvedNil() => ()
  | ~ShelvedCons(_, _, rest) => _shelved_free(rest)

(* shelved, let go: the reset was not undone *)
#pub fn lib_shelved_free (shelved: shelved): void
implement lib_shelved_free (shelved) = _shelved_free(shelved)

(* ============================================================
   Sorting
   ============================================================ *)

fn _lower (byte_value: int): int =
  if byte_value >= 65 then (if byte_value <= 90 then byte_value + 32 else byte_value) else byte_value

(* How one text compares with another *)
datatype comparison = Before | Same | After

(* first[0, first_len) before second[0, second_len), letters in any case *)
fun _less {first_loc,second_loc:agz}{first_len,second_len:nat}
  {first_size,second_size:nat | first_len <= first_size; second_len <= second_size}{i:nat | i <= first_len} .<first_len - i>.
  (first: !$A.arr(byte, first_loc, first_size), first_len: int first_len,
   second: !$A.arr(byte, second_loc, second_size), second_len: int second_len, i: int i): comparison =
  if i >= first_len then (if i >= second_len then Same() else Before())
  else if i >= second_len then After()
  else let
    val first_byte = _lower(byte2int0($A.get<byte>(first, i)))
    val second_byte = _lower(byte2int0($A.get<byte>(second, i)))
  in if first_byte < second_byte then Before() else if first_byte > second_byte then After()
     else _less(first, first_len, second, second_len, i + 1) end

fn _is_before (c: comparison): bool = case+ c of Before() => true | _ => false

(* Whether first comes before second in order *)
fn _before (first: !book, second: !book, order: sort_order): bool = let
  val+ Book(first_title, first_title_len, first_author, first_author_len, first_series, first_series_len, first_nums) = first
  val+ Book(second_title, second_title_len, second_author, second_author_len, second_series, second_series_len, second_nums) = second
in
  (* by series: each series together, in its numbers' order, then the
     books of none, by title *)
  case+ order of
  | BySeries() => (if first_series_len > 0 then (if second_series_len > 0 then
      (case+ _less(first_series, first_series_len, second_series, second_series_len, 0) of
       | Before() => true
       | After() => false
       | Same() =>
         if first_nums.series_number <> second_nums.series_number then first_nums.series_number < second_nums.series_number
         else _is_before(_less(first_title, first_title_len, second_title, second_title_len, 0)))
      else true)
    else (if second_series_len > 0 then false else _is_before(_less(first_title, first_title_len, second_title, second_title_len, 0))))
  | ByTitle() => _is_before(_less(first_title, first_title_len, second_title, second_title_len, 0))
  | ByAuthor() =>
    (case+ _less(first_author, first_author_len, second_author, second_author_len, 0) of
     | Before() => true
     | After() => false
     | Same() => _is_before(_less(first_title, first_title_len, second_title, second_title_len, 0)))
  | DateAdded() => first_nums.added > second_nums.added
  | LastOpened() => (if first_nums.opened <> second_nums.opened then first_nums.opened > second_nums.opened
        else first_nums.added > second_nums.added)
end

fun _insert {count:nat} .<count>. (book: book, books: books(count), order: sort_order): books(count + 1) =
  case+ books of
  | ~books_nil() => books_cons(book, books_nil())
  | ~books_cons(other, rest) =>
    if _before(book, other, order) then books_cons(book, books_cons(other, rest))
    else books_cons(other, _insert(book, rest, order))

fun _sort {count,sorted_count:nat} .<count>. (books: books(count), sorted: books(sorted_count), order: sort_order)
  : books(count + sorted_count) =
  case+ books of
  | ~books_nil() => sorted
  | ~books_cons(book, rest) => _sort(rest, _insert(book, sorted, order), order)

(* Sorts the library in order (and keeps order for later sorts) *)
#pub fn lib_sort (order: sort_order): void

implement lib_sort (order) = let
  val () = !_sort_order := order
  val cell = lib_take()
  val+ ~LibCell(books, count) = cell
in lib_put(LibCell(_sort(books, books_nil(), order), count)) end

(* ============================================================
   Collections: a reader's own groups of books
   ============================================================ *)

(* At most COLL_MAX collections, each named by 1 to COLL_NAME bytes (in
   an array one longer). A book is in collection j when bit j of its
   cols is set, and can be in any number of them *)
#pub stadef COLL_MAX = 8
#pub stadef COLL_NAME = 40

datavtype colls(int) =
  | colls_nil(0) of ()
  | {count:nat}{name_loc:agz}{name_len:pos | name_len <= COLL_NAME}
    colls_cons(count + 1) of ($A.arr(byte, name_loc, name_len + 1), int name_len, colls(count))

datavtype coll_cell =
  | {count:nat | count <= COLL_MAX} CollCell of (colls(count), int count)

val _colls = ref<coll_cell>(CollCell(colls_nil(), 0))

(* The collection the library view shows, -1 for none: every book *)
val _coll_shown = ref<int>(~1)

fun colls_free {count:nat} .<count>. (collections: colls(count)): void =
  case+ collections of
  | ~colls_nil() => ()
  | ~colls_cons(name, _, rest) => let val () = $A.free<byte>(name) in colls_free(rest) end

fn colls_take (): coll_cell = let
  var cell: coll_cell = CollCell(colls_nil(), 0)
  val () = ref_exch_elt<coll_cell>(_colls, cell)
in cell end

fn colls_put (cell: coll_cell): void = let
  var current: coll_cell = cell
  val () = ref_exch_elt<coll_cell>(_colls, current)
  val+ ~CollCell(collections, _) = current
in colls_free(collections) end

#pub fn lib_coll_count (): [count:nat | count <= COLL_MAX] int count
implement lib_coll_count () = let
  val cell = colls_take()
  val+ CollCell(_, count) = cell
  val () = colls_put(cell)
in count end

(* Where a name typed into typed[0, typed_len) starts: past the spaces
   before it *)
fun _name_start {l:agz}{size:pos}{typed_len:nat | typed_len <= size}{i:nat | i <= typed_len} .<typed_len - i>.
  (typed: !$A.arr(byte, l, size), typed_len: int typed_len, i: int i): [start:nat | i <= start; start <= typed_len] int start =
  if i >= typed_len then i
  else if byte2int0($A.get<byte>(typed, i)) <= 32 then _name_start(typed, typed_len, i + 1)
  else i

(* Where it ends: before the spaces after it *)
fun _name_end {l:agz}{size:pos}{start,stop:nat | start <= stop; stop <= size} .<stop - start>.
  (typed: !$A.arr(byte, l, size), start: int start, stop: int stop): [found:nat | start <= found; found <= stop] int found =
  if stop <= start then stop
  else if byte2int0($A.get<byte>(typed, stop - 1)) <= 32 then _name_end(typed, start, stop - 1)
  else stop

(* kept, or fewer, so that the kept bytes from start (of total there) do
   not end inside a letter: the byte after them does not continue one *)
fun _name_cut {l:agz}{size:pos}{start,kept,total:nat | kept <= total; start + total <= size} .<kept>.
  (typed: !$A.arr(byte, l, size), start: int start, kept: int kept, total: int total): [cut:nat | cut <= kept] int cut =
  if kept >= total then kept
  else if kept <= 0 then 0
  else let
    val next_byte = byte2int0($A.get<byte>(typed, start + kept))
  in if next_byte >= 128 && next_byte < 192 then _name_cut(typed, start, kept - 1, total) else kept end

(* source[start + j, start + count) into dest[j, count) *)
fun _copy_from {source_loc,dest_loc:agz}{source_size,dest_size:nat}
  {start,count:nat | start + count <= source_size; count <= dest_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), start: int start, count: int count,
   dest: !$A.arr(byte, dest_loc, dest_size), j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(dest, j, $A.get<byte>(source, start + j))
  in _copy_from(source, start, count, dest, j + 1) end

(* total bytes, or a name's most *)
fn _most {total:nat} (total: int total): [kept:nat | kept <= total; kept <= COLL_NAME] int kept =
  if total > 40 then 40 else total

(* The name typed into typed[0, typed_len), made a collection's: without
   the spaces around it, and cut to COLL_NAME bytes between letters; 0
   bytes when nothing is left *)
fn _coll_name {l:agz}{size:pos}{typed_len:nat | typed_len <= size} (typed: !$A.arr(byte, l, size), typed_len: int typed_len)
  : [name_loc:agz][name_len:nat | name_len <= COLL_NAME] @($A.arr(byte, name_loc, name_len + 1), int name_len) = let
  val start = _name_start(typed, typed_len, 0)
  val stop = _name_end(typed, start, typed_len)
  val total = stop - start
  val name_len = _name_cut(typed, start, _most(total), total)
  val name = $A.alloc<byte>(name_len + 1)
  val () = _copy_from(typed, start, name_len, name, 0)
in @(name, name_len) end

fun _colls_insert {count:nat}{name_loc:agz}{name_len:pos | name_len <= COLL_NAME} .<count>.
  (collections: colls(count), position: int, name: $A.arr(byte, name_loc, name_len + 1), name_len: int name_len)
  : colls(count + 1) =
  if position <= 0 then colls_cons(name, name_len, collections)
  else case+ collections of
  | ~colls_nil() => colls_cons(name, name_len, colls_nil())
  | ~colls_cons(other, other_len, rest) => colls_cons(other, other_len, _colls_insert(rest, position - 1, name, name_len))

(* collections without its collection at position, and that
   collection's name *)
fun _colls_remove {count:pos}{position:nat | position < count} .<count>. (collections: colls(count), position: int position)
  : [name_loc:agz][name_len:pos | name_len <= COLL_NAME] @(colls(count - 1), $A.arr(byte, name_loc, name_len + 1), int name_len) = let
  val+ ~colls_cons(first, first_len, rest) = collections
in
  if position = 0 then @(rest, first, first_len)
  else let
    val @(others, name, name_len) = _colls_remove(rest, position - 1)
  in @(colls_cons(first, first_len, others), name, name_len) end
end

(* collections with the collection at position named name[0, name_len)
   instead *)
fun _colls_rename {count:nat}{name_loc:agz}{name_len:pos | name_len <= COLL_NAME} .<count>.
  (collections: colls(count), position: int, name: $A.arr(byte, name_loc, name_len + 1), name_len: int name_len): colls(count) =
  case+ collections of
  | ~colls_nil() => let val () = $A.free<byte>(name) in colls_nil() end
  | ~colls_cons(other, other_len, rest) =>
    if position = 0 then let val () = $A.free<byte>(other) in colls_cons(name, name_len, rest) end
    else colls_cons(other, other_len, _colls_rename(rest, position - 1, name, name_len))

(* The books in collection: their collections changed now (the
   collection was renamed: by name, which sync goes by, they are in
   another one) *)
fun _stamp_members {count:nat} .<count>. (books: !books(count), collection: int): void =
  case+ books of
  | books_nil() => ()
  | @books_cons(book, rest) => let
      val+ @Book(_, _, _, _, _, _, nums) = book
      val () = (if $AR.band_int_int(nums.collections, $AR.bsl_int_int(1, collection)) <> 0 then nums := @{
        key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = nums.shelf, added = nums.added, opened = nums.opened,
        chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
        file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number, collections = nums.collections, minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
        shelf_modified = nums.shelf_modified, collections_modified = stamp_now(),
        finished_modified = nums.finished_modified, minutes_elsewhere = nums.minutes_elsewhere, pages_elsewhere = nums.pages_elsewhere } else ())
      prval () = fold@(book)
      val () = _stamp_members(rest, collection)
      prval () = fold@(books)
    in end

(* The bit of collection *)
fn _collection_bit (collection: int): Int = g1ofg0($AR.bsl_int_int(1, collection))

(* The bits of membership below collection's *)
fn _below (membership: int, collection: int): int =
  $AR.band_int_int(membership, $AR.sub_int_int($AR.bsl_int_int(1, collection), 1))

(* membership without collection's bit, the bits above it moved down one *)
fn _drop_bit (membership: Int, collection: int): Int = let
  val bits = g0ofg1(membership)
  val above = $AR.bsl_int_int($AR.bsr_int_int(bits, collection + 1), collection)
in g1ofg0($AR.add_int_int(_below(bits, collection), above)) end

(* membership with a bit for collection put in (set when on), the bits
   from it moved up one *)
fn _put_bit (membership: Int, collection: int, on: bool): Int = let
  val bits = g0ofg1(membership)
  val above = $AR.bsl_int_int($AR.bsr_int_int(bits, collection), collection + 1)
  val bit = (if on then $AR.bsl_int_int(1, collection) else 0): int
in g1ofg0($AR.add_int_int($AR.add_int_int(_below(bits, collection), above), bit)) end

(* The keys of the books in a collection, onto keys *)
datavtype keys(int) =
  | KeysNil(0) of ()
  | {count:nat} KeysCons(count + 1) of (Int, keys(count))

fun _keys_in {count:nat}{so_far:nat} .<count>. (books: !books(count), collection: int, keys: keys(so_far)): [total:nat] keys(total) =
  case+ books of
  | books_nil() => keys
  | books_cons(book, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = book
    in
      if $AR.band_int_int(nums.collections, _collection_bit(collection)) <> 0 then _keys_in(rest, collection, KeysCons(nums.key, keys))
      else _keys_in(rest, collection, keys)
    end

fun _keys_free {count:nat} .<count>. (keys: keys(count)): void =
  case+ keys of
  | ~KeysNil() => ()
  | ~KeysCons(_, rest) => _keys_free(rest)

fun _keys_has {count:nat} .<count>. (keys: !keys(count), key: Int): bool =
  case+ keys of
  | KeysNil() => false
  | KeysCons(listed, rest) => if listed = key then true else _keys_has(rest, key)

(* How a collection's deletion changes each book's collections: its
   bit dropped (the bits above moved down), or, when it is put back,
   its bit put in again, set for the books whose keys it kept *)
datavtype regroup =
  | DropCollection of (int)
  | {count:nat} PutCollection of (int, keys(count))

fn _regroup_free (change: regroup): void =
  case+ change of
  | ~DropCollection(_) => ()
  | ~PutCollection(_, keys) => _keys_free(keys)

(* The collections of the book whose key is key, which were membership,
   changed by change *)
fn _regrouped (change: !regroup, key: Int, membership: Int): Int =
  case+ change of
  | DropCollection(collection) => _drop_bit(membership, collection)
  | PutCollection(collection, keys) => _put_bit(membership, collection, _keys_has(keys, key))

(* Every book's collections, as change makes them from its key and its
   collections now *)
fun _map_collections {count:nat} .<count>. (books: !books(count), change: !regroup): void =
  case+ books of
  | books_nil() => ()
  | @books_cons(book, rest) => let
      val+ @Book(_, _, _, _, _, _, nums) = book
      val membership = _regrouped(change, nums.key, nums.collections)
      val () = nums := @{
        key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = nums.shelf, added = nums.added, opened = nums.opened,
        chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
        file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number, collections = membership, minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
        shelf_modified = nums.shelf_modified,
        collections_modified = (if membership <> nums.collections then stamp_now() else nums.collections_modified),
        finished_modified = nums.finished_modified, minutes_elsewhere = nums.minutes_elsewhere, pages_elsewhere = nums.pages_elsewhere }
      prval () = fold@(book)
      val () = _map_collections(rest, change)
      prval () = fold@(books)
    in end

fn _map_all_collections (change: !regroup): void = let
  val cell = lib_take()
  val+ @LibCell(books, _) = cell
  val () = _map_collections(books, change)
  prval () = fold@(cell)
in lib_put(cell) end

(* The collection the library view shows, or -1 *)
#pub fn lib_coll_shown (): int
implement lib_coll_shown () = !_coll_shown

(* Whether book numbers nums are in the collection shown (in any, when
   none is) *)
fn _in_shown (nums: bnums): bool = let
  val shown = !_coll_shown
in if shown < 0 then true else $AR.band_int_int(nums.collections, _collection_bit(shown)) <> 0 end

(* The name of a collection just deleted, while its Undo is offered *)
datavtype coll_gone =
  | {name_loc:agz}{name_len:pos | name_len <= COLL_NAME} CollGone of ($A.arr(byte, name_loc, name_len + 1), int name_len)
  | CollNotGone of ()

val _coll_gone = ref<coll_gone>(CollNotGone())
(* Whether _coll_gone holds a name *)
val _coll_gone_held = ref<bool>(false)

fn _gone_take (): coll_gone = let
  val () = !_coll_gone_held := false
  var gone: coll_gone = CollNotGone()
  val () = ref_exch_elt<coll_gone>(_coll_gone, gone)
in gone end

fn _gone_free (gone: coll_gone): void =
  case+ gone of
  | ~CollGone(name, _) => $A.free<byte>(name)
  | ~CollNotGone() => ()

fn _gone_put (gone: coll_gone): void = let
  val () = !_coll_gone_held := (case+ gone of CollGone(_, _) => true | CollNotGone() => false)
  var current: coll_gone = gone
  val () = ref_exch_elt<coll_gone>(_coll_gone, current)
in _gone_free(current) end

(* Makes a collection named by what was typed, typed[0, typed_len) (see
   _coll_name): its number, or -1 when there are COLL_MAX already or no
   name is left *)
#pub fn lib_coll_add {l:agz}{size:pos}{typed_len:nat | typed_len <= size} (typed: $A.arr(byte, l, size), typed_len: int typed_len): int

implement lib_coll_add (typed, typed_len) = let
  val @(name, name_len) = _coll_name(typed, typed_len)
  val () = $A.free<byte>(typed)
  (* a deleted collection's Undo would put it back among numbers that
     have moved on: it is made final first *)
  val () = (if !_coll_gone_held then undo_close() else ())
  val cell = colls_take()
  val+ ~CollCell(collections, count) = cell
in
  if name_len <= 0 then let
    val () = $A.free<byte>(name)
    val () = colls_put(CollCell(collections, count))
  in ~1 end
  else if count >= 8 then let
    val () = $A.free<byte>(name)
    val () = colls_put(CollCell(collections, count))
  in ~1 end
  else let
    val () = colls_put(CollCell(_colls_insert(collections, count, name, name_len), count + 1))
    val () = lib_save()
  in count end
end

(* Names collection by what was typed, typed[0, typed_len) (kept when no
   name is left) *)
#pub fn lib_coll_rename {l:agz}{size:pos}{typed_len:nat | typed_len <= size}
  (collection: int, typed: $A.arr(byte, l, size), typed_len: int typed_len): void

implement lib_coll_rename (collection, typed, typed_len) = let
  val @(name, name_len) = _coll_name(typed, typed_len)
  val () = $A.free<byte>(typed)
in
  if name_len <= 0 then $A.free<byte>(name)
  else let
    val cell = colls_take()
    val+ ~CollCell(collections, count) = cell
    val () = colls_put(CollCell(_colls_rename(collections, collection, name, name_len), count))
    val library = lib_take()
    val+ @LibCell(books, _) = library
    val () = (if collection >= 0 then (if collection < 8 then _stamp_members(books, collection) else ()) else ())
    prval () = fold@(library)
    val () = lib_put(library)
    val () = lib_save()
  in lib_render() end
end

(* Whether first[0, len) and second[0, len) are the same bytes *)
fun _same {first_loc,second_loc:agz}{first_size,second_size:nat}{len:nat | len <= first_size; len <= second_size}
  {j:nat | j <= len} .<len - j>.
  (first: !$A.arr(byte, first_loc, first_size), second: !$A.arr(byte, second_loc, second_size), len: int len, j: int j): bool =
  if j >= len then true
  else if byte2int0($A.get<byte>(first, j)) <> byte2int0($A.get<byte>(second, j)) then false
  else _same(first, second, len, j + 1)

(* The number of the collection named name[0, name_len) in collections
   (from number on), or -1 *)
fun _colls_find {count:nat}{l:agz}{name_len:nat} .<count>.
  (collections: !colls(count), name: !$A.arr(byte, l, name_len + 1), name_len: int name_len, number: int): int =
  case+ collections of
  | colls_nil() => ~1
  | @colls_cons(other, other_len, rest) => let
      val hit = (if other_len = name_len then _same(other, name, name_len, 0) else false): bool
      val found = (if hit then number else _colls_find(rest, name, name_len, number + 1)): int
      prval () = fold@(collections)
    in found end

(* The collection named by typed[0, typed_len) (as a name typed is, see
   _coll_name): its number, made when there is none so named and there
   is room; -1 when there is no room or no name. For a backup's
   collections *)
#pub fn lib_coll_find_or_add {l:agz}{size:pos}{typed_len:nat | typed_len <= size} (typed: $A.arr(byte, l, size), typed_len: int typed_len): int

implement lib_coll_find_or_add (typed, typed_len) = let
  val @(name, name_len) = _coll_name(typed, typed_len)
  val cell = colls_take()
  val+ @CollCell(collections, _) = cell
  val found = (if name_len > 0 then _colls_find(collections, name, name_len, 0) else ~1): int
  prval () = fold@(cell)
  val () = colls_put(cell)
  val () = $A.free<byte>(name)
in if found >= 0 then let val () = $A.free<byte>(typed) in found end else lib_coll_add(typed, typed_len) end

(* The name of the collection at position: its bytes (one more) and how
   many; 0 when there is no such collection *)
fun _name_copy {count:nat} .<count>. (collections: !colls(count), position: int)
  : [l:agz][n:nat | n <= COLL_NAME] @($A.arr(byte, l, n + 1), int n) =
  case+ collections of
  | colls_nil() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  | @colls_cons(name, name_len, rest) =>
    if position = 0 then let
      val name_copy = $A.alloc<byte>(name_len + 1)
      val () = _copy(name, name_len, name_copy, 0, 0)
      val copy_len = name_len
      prval () = fold@(collections)
    in @(name_copy, copy_len) end
    else let
      val found = _name_copy(rest, position - 1)
      prval () = fold@(collections)
    in found end

#pub fn lib_coll_name_copy (collection: int): [l:agz][n:nat | n <= COLL_NAME] @($A.arr(byte, l, n + 1), int n)

implement lib_coll_name_copy (collection) = let
  val cell = colls_take()
  val+ @CollCell(collections, _) = cell
  val name_copy = _name_copy(collections, collection)
  prval () = fold@(cell)
  val () = colls_put(cell)
in name_copy end

(* Whether the book at index is in collection *)
#pub fn lib_coll_has {index:int} (index: int index, collection: int): bool

implement lib_coll_has (index, collection) =
  if collection < 0 then false
  else case+ lib_nums(index) of
  | ~$R.none() => false
  | ~$R.some(nums) => $AR.band_int_int(nums.collections, _collection_bit(collection)) <> 0

(* Puts the book at index in collection, or takes it out when it is in
   it *)
#pub fn lib_coll_toggle {index:int} (index: int index, collection: int): void

implement lib_coll_toggle (index, collection) =
  if collection < 0 then ()
  else if collection >= lib_coll_count() then ()
  else let
    val on = lib_coll_has(index, collection)
    val () = (case+ lib_nums(index) of ~$R.none() => () | ~$R.some(nums) => lib_nums_set(index, @{
      key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = nums.shelf, added = nums.added, opened = nums.opened,
      chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages, anchor = nums.anchor,
      file_size = nums.file_size, cover = nums.cover, done = nums.done, series_number = nums.series_number,
      collections = (if on then nums.collections - _collection_bit(collection) else nums.collections + _collection_bit(collection)), minutes_read = nums.minutes_read, pages_read = nums.pages_read, finished_at = nums.finished_at,
      shelf_modified = nums.shelf_modified, collections_modified = stamp_now(), finished_modified = nums.finished_modified,
      minutes_elsewhere = nums.minutes_elsewhere, pages_elsewhere = nums.pages_elsewhere }))
  in lib_save() end

(* Collection deleted, with an Undo offer that puts it back: its books
   stay where they are, only the group goes *)
#pub fn lib_coll_delete (collection: int): void

(* Puts collection back (named as it was), with the books whose keys
   are keys in it *)
fn _coll_restore (collection: int, keys: [count:nat] keys(count)): void =
  case+ _gone_take() of
  | ~CollNotGone() => _keys_free(keys)
  | ~CollGone(name, name_len) => let
      val cell = colls_take()
      val+ ~CollCell(collections, count) = cell
    in
      if count >= 8 then let
        val () = $A.free<byte>(name)
        val () = _keys_free(keys)
      in colls_put(CollCell(collections, count)) end
      else let
        val () = colls_put(CollCell(_colls_insert(collections, collection, name, name_len), count + 1))
        val change = PutCollection(collection, keys)
        val () = _map_all_collections(change)
        val () = _regroup_free(change)
        val () = lib_save()
      in lib_render() end
    end

implement lib_coll_delete (collection) = let
  val collection = g1ofg0(collection)
  val cell = colls_take()
  val+ ~CollCell(collections, count) = cell
in
  if collection < 0 then colls_put(CollCell(collections, count))
  else if collection >= count then colls_put(CollCell(collections, count))
  else let
    val @(rest, name, name_len) = _colls_remove(collections, collection)
    val () = colls_put(CollCell(rest, count - 1))
    val library = lib_take()
    val+ @LibCell(books, _) = library
    val keys = _keys_in(books, collection, KeysNil())
    prval () = fold@(library)
    val () = lib_put(library)
    val change = DropCollection(collection)
    val () = _map_all_collections(change)
    val () = _regroup_free(change)
    val shown = !_coll_shown
    val () = !_coll_shown := (if shown = collection then ~1 else if shown > collection then shown - 1 else shown)
    val () = _gone_put(CollGone(name, name_len))
    val () = lib_save()
    val () = lib_render()
  in $P.finish<settled>(undo_offer("Collection deleted"), llam(how) =>
    case+ how of
    | Undone() => _coll_restore(collection, keys)
    | Final() => let val () = _keys_free(keys) in _gone_put(CollNotGone()) end) end
end

(* Shows the books of collection only, or every book for -1 *)
#pub fn lib_coll_show (collection: int): void

implement lib_coll_show (collection) = let
  val () = !_coll_shown := (if collection >= 0 then (if collection < lib_coll_count() then collection else ~1) else ~1)
in lib_render() end

(* The library's collection chips: each collection, pressed when it is
   the one shown *)
fun _chips {count:nat}{j:nat} .<count>. (collections: !colls(count), j: int j, shown: int): void =
  case+ collections of
  | colls_nil() => ()
  | @colls_cons(name, name_len, rest) => let
      val number = j
      val @(chip_id, chip_id_len) = nid_make("collection", number)
      val () = ui_btn_n("collection-chips", chip_id, chip_id_len, "sbtn")
      val text = $A.alloc<byte>(name_len + 1)
      val () = _copy(name, name_len, text, 0, 0)
      val @(chip_id, chip_id_len) = nid_make("collection", number)
      val () = ui_text_n_buf(chip_id, chip_id_len, text, name_len)
      val @(chip_id, chip_id_len) = nid_make("collection", number)
      val () = (if j = shown then ui_attr_n(chip_id, chip_id_len, APressed, "true") else ui_attr_n(chip_id, chip_id_len, APressed, "false"))
      val () = _chips(rest, j + 1, shown)
      prval () = fold@(collections)
    in end

(* The collection row: shown when there is a collection, with every
   book's chip and each collection's; renaming and deleting are offered
   for the one shown *)
fn _coll_row (): void = let
  val () = ui_clear("collection-chips")
  val cell = colls_take()
  val+ @CollCell(collections, collection_count) = cell
  val shown = !_coll_shown
  val () = ui_text_btn("collection-chips", "collection-all", "sbtn", "All books")
  val () = (if shown < 0 then ui_attr("collection-all", APressed, "true") else ui_attr("collection-all", APressed, "false"))
  val () = _chips(collections, 0, shown)
  val count = collection_count
  prval () = fold@(cell)
  val () = colls_put(cell)
  val () = ui_show("collection-row", count > 0)
  val () = ui_show("collection-rename", shown >= 0)
in ui_show("collection-delete", shown >= 0) end

(* The collections panel's toggles for a book in the collections
   membership says *)
fun _toggles {count:nat}{j:nat} .<count>. (collections: !colls(count), j: int j, membership: Int): void =
  case+ collections of
  | colls_nil() => ()
  | @colls_cons(name, name_len, rest) => let
      val number = j
      val @(toggle_id, toggle_id_len) = nid_make("collection-put", number)
      val () = ui_btn_n("collections-list", toggle_id, toggle_id_len, "sbtn")
      val text = $A.alloc<byte>(name_len + 1)
      val () = _copy(name, name_len, text, 0, 0)
      val @(toggle_id, toggle_id_len) = nid_make("collection-put", number)
      val () = ui_text_n_buf(toggle_id, toggle_id_len, text, name_len)
      val @(toggle_id, toggle_id_len) = nid_make("collection-put", number)
      val () = (if $AR.band_int_int(membership, _collection_bit(j)) <> 0 then ui_attr_n(toggle_id, toggle_id_len, APressed, "true")
                else ui_attr_n(toggle_id, toggle_id_len, APressed, "false"))
      val () = _toggles(rest, j + 1, membership)
      prval () = fold@(collections)
    in end

(* The collections panel for the book at index: a toggle for each
   collection, pressed when the book is in it *)
#pub fn lib_coll_panel {index:int} (index: int index): void

implement lib_coll_panel (index) = let
  val () = ui_clear("collections-list")
  val membership = (case+ lib_nums(index) of ~$R.none() => 0 | ~$R.some(nums) => nums.collections): Int
  val cell = colls_take()
  val+ @CollCell(collections, collection_count) = cell
  val () = _toggles(collections, 0, membership)
  val count = collection_count
  prval () = fold@(cell)
  val () = colls_put(cell)
  val () = ui_show("collections-new", count < 8)
in ui_show("collections-none", count = 0) end

(* The name of the collection at position, in the dialog's name field *)
fun _name_at {count:nat} .<count>. (collections: !colls(count), position: int): void =
  case+ collections of
  | colls_nil() => ()
  | @colls_cons(name, name_len, rest) =>
    if position = 0 then let
      val text = $A.alloc<byte>(name_len + 1)
      val () = _copy(name, name_len, text, 0, 0)
      val () = modal_name_set(text, name_len)
      prval () = fold@(collections)
    in end
    else let
      val () = _name_at(rest, position - 1)
      prval () = fold@(collections)
    in end

#pub fn lib_coll_name_show (collection: int): void

implement lib_coll_name_show (collection) = let
  val cell = colls_take()
  val+ @CollCell(collections, _) = cell
  val () = _name_at(collections, collection)
  prval () = fold@(cell)
in colls_put(cell) end

(* ============================================================
   Storage: key "lib"
   ============================================================ *)

(* "QLB4", the collections (u8 count, then each name: u8 length,
   bytes), then each book: id (2 x i32), title (u8 length, bytes),
   author (u8 length, bytes), then 10 x i32: shelf, added, opened, ch,
   tch, pg, pgs, anchor, fsz, cover | done << 8; its series (u8 length,
   bytes) and its number in it (i32); the collections it is in (i32);
   the minutes it has been read, the pages turned on them, and when it
   was finished (3 x i32); when its shelf, collections and being
   finished last changed (3 stamps, i32), and the minutes it has been
   read on other devices and the pages turned on them (2 x i32). At
   most 856 bytes a book. QLB4 has none of the last five, QLB3 none of
   the last eight. QLB2 has no collections, before or in the
   books; QLB1 has no series either. *)



fun _put_bytes {source_loc,out_loc:agz}{owner:addr}{source_len,source_size:nat | source_len <= source_size}{out_size:nat}
  {start:nat | start + source_len <= out_size}{j:nat | j <= source_len} .<source_len - j>.
  (source: !$A.arr(byte, source_loc, source_size), source_len: int source_len,
   out: !$A.arrx(byte, out_loc, out_size, owner), start: int start, j: int j): void =
  if j >= source_len then ()
  else let
    val () = $A.write_byte(out, start + j, $AR.low_byte(byte2int0($A.get<byte>(source, j))))
  in _put_bytes(source, source_len, out, start, j + 1) end

fun _write_names {l:agz}{owner:addr}{n:int}{count:nat}{start:nat | start + 41 * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, owner), start: int start, collections: !colls(count))
  : [stop:nat | stop <= start + 41 * count] int stop =
  case+ collections of
  | colls_nil() => start
  | @colls_cons(name, name_len, rest) => let
      val () = $A.write_byte(out, start, name_len)
      val () = _put_bytes(name, name_len, out, start + 1, 0)
      val stop = _write_names(out, start + 1 + name_len, rest)
      prval () = fold@(collections)
    in stop end

fun _write_books {l:agz}{owner:addr}{n:int}{count:nat}{start:nat | start + 856 * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, owner), start: int start, books: !books(count)): [stop:nat | stop <= n] int stop =
  case+ books of
  | books_nil() => start
  | books_cons(book, rest) => let
      val+ Book(title, title_len, author, author_len, series, series_len, nums) = book
      val () = $A.write_i32(out, start, nums.id_high)
      val () = $A.write_i32(out, start + 4, nums.id_low)
      val () = $A.write_byte(out, start + 8, title_len)
      val () = _put_bytes(title, title_len, out, start + 9, 0)
      val author_at = start + 9 + title_len
      val () = $A.write_byte(out, author_at, author_len)
      val () = _put_bytes(author, author_len, out, author_at + 1, 0)
      val numbers_at = author_at + 1 + author_len
      val () = $A.write_i32(out, numbers_at, shelf_code(nums.shelf))
      val () = $A.write_i32(out, numbers_at + 4, nums.added)
      val () = $A.write_i32(out, numbers_at + 8, nums.opened)
      val () = $A.write_i32(out, numbers_at + 12, nums.chapter)
      val () = $A.write_i32(out, numbers_at + 16, nums.chapters)
      val () = $A.write_i32(out, numbers_at + 20, nums.page)
      val () = $A.write_i32(out, numbers_at + 24, nums.pages)
      val () = $A.write_i32(out, numbers_at + 28, nums.anchor)
      val () = $A.write_i32(out, numbers_at + 32, nums.file_size)
      val () = $A.write_i32(out, numbers_at + 36, image_code(nums.cover) + nums.done * 256)
      (* QLB2: the series' name and the book's number in it *)
      val series_at = numbers_at + 40
      val () = $A.write_byte(out, series_at, series_len)
      val () = _put_bytes(series, series_len, out, series_at + 1, 0)
      val () = $A.write_i32(out, series_at + 1 + series_len, nums.series_number)
      (* QLB3: the collections it is in *)
      val () = $A.write_i32(out, series_at + 5 + series_len, nums.collections)
      (* QLB4: how long it has been read, and when it was finished *)
      val () = $A.write_i32(out, series_at + 9 + series_len, nums.minutes_read)
      val () = $A.write_i32(out, series_at + 13 + series_len, nums.pages_read)
      val () = $A.write_i32(out, series_at + 17 + series_len, nums.finished_at)
      (* QLB5: when its shelf, collections and being finished changed,
         and its reading on other devices *)
      val () = $A.write_i32(out, series_at + 21 + series_len, nums.shelf_modified)
      val () = $A.write_i32(out, series_at + 25 + series_len, nums.collections_modified)
      val () = $A.write_i32(out, series_at + 29 + series_len, nums.finished_modified)
      val () = $A.write_i32(out, series_at + 33 + series_len, nums.minutes_elsewhere)
      val () = $A.write_i32(out, series_at + 37 + series_len, nums.pages_elsewhere)
    in _write_books(out, series_at + 41 + series_len, rest) end

(* Stores the library under "lib" *)
#pub fn lib_save (): void

implement lib_save () = let
  val library = lib_take()
  val+ @LibCell(books, count) = library
  val collections_cell = colls_take()
  val+ @CollCell(collections, collection_count) = collections_cell
  val size = 333 + 856 * count
in
  case+ piece_new(size) of
  | ~NoPiece() => let
      prval () = fold@(collections_cell)
      val () = colls_put(collections_cell)
      prval () = fold@(library)
    in lib_put(library) end
  | ~Piece(owner, out) => let
      val () = $A.write_text(out, 0, $A.text_lit("QLB5"), 4)
      val () = $A.write_byte(out, 4, collection_count)
      val books_at = _write_names(out, 5, collections)
      prval () = fold@(collections_cell)
      val () = colls_put(collections_cell)
      val stop = _write_books(out, books_at, books)
      prval () = fold@(library)
      val () = lib_put(library)
      val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(out_frozen, out_bytes, stop)
      val key = $A.alloc<byte>(3)
      val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
      val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
      (* never over a library that could not be read *)
      val () = (if storage_savable(LibraryRecord()) then save_checked($IDB.idb_put(key_bytes, 3, used, stop)) else ())
      val () = release_bytes(key_frozen, key_bytes)
      val out_bytes = $A.borrow_join<byte>(out_frozen, used, rest)
      val () = $A.drop<byte>(out_frozen, out_bytes)
    in piece_free(owner, $A.thaw<byte>(out_frozen)) end
end

(* The little-endian int at buf[start, start + 4) *)
fn _int32_at {l:agz}{owner:addr}{n:nat}{start:nat | start + 4 <= n}
  (buf: !$A.arrx(byte, l, n, owner), start: int start): Int = let
  val byte0 = $AR.low_byte(byte2int0($A.get<byte>(buf, start)))
  val byte1 = $AR.low_byte(byte2int0($A.get<byte>(buf, start + 1)))
  val byte2 = $AR.low_byte(byte2int0($A.get<byte>(buf, start + 2)))
  val byte3 = $AR.low_byte(byte2int0($A.get<byte>(buf, start + 3)))
  val high = (if byte3 < 128 then byte3 else byte3 - 256): [high:int | ~128 <= high; high < 128] int high
in byte0 + byte1 * 256 + byte2 * 65536 + high * 16777216 end

(* buf[start, start + count) into out[0, count), out being longer *)
fun _bytes_of_into {l:agz}{owner:addr}{n:nat}{start,count:nat | start + count <= n}{out_loc:agz}{out_size:pos | count < out_size}
  {j:nat | j <= count} .<count - j>.
  (buf: !$A.arrx(byte, l, n, owner), start: int start, count: int count, out: !$A.arr(byte, out_loc, out_size), j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(buf, start + j))
  in _bytes_of_into(buf, start, count, out, j + 1) end

fun _bytes_of {l:agz}{owner:addr}{n:nat}{start,count:nat | start + count <= n}{out_loc:agz}{j:nat | j <= count} .<count - j>.
  (buf: !$A.arrx(byte, l, n, owner), start: int start, count: int count, out: !$A.arr(byte, out_loc, count), j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(buf, start + j))
  in _bytes_of(buf, start, count, out, j + 1) end

(* The books stored in buf[start, n), read from an earlier run's bytes
   and checked here, once; onto books, parsed so far (at most
   LIB_MAX) *)
fun _parse_books {l:agz}{owner:addr}{n:nat}{start:nat | start <= n}{parsed:nat | parsed <= LIB_MAX} .<n - start>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, start: int start, books: books(parsed), parsed: int parsed, version: int)
  : [count:nat | count <= LIB_MAX] @(books(count), int count) =
  if parsed >= 100000 then @(books, parsed)
  else if start + 9 > n then @(books, parsed)
  else let
    val id_high = _int32_at(buf, start)
    val id_low = _int32_at(buf, start + 4)
    val title_len = $AR.low_byte(byte2int0($A.get<byte>(buf, start + 8)))
  in
    if title_len <= 0 then @(books, parsed)
    else if start + 9 + title_len + 1 > n then @(books, parsed)
    else let
      val author_at = start + 9 + title_len
      val author_len = $AR.low_byte(byte2int0($A.get<byte>(buf, author_at)))
    in
      if author_len <= 0 then @(books, parsed)
      else if author_at + 1 + author_len + 40 > n then @(books, parsed)
      else let
        val title = $A.alloc<byte>(title_len)
        val () = _bytes_of(buf, start + 9, title_len, title, 0)
        val author = $A.alloc<byte>(author_len)
        val () = _bytes_of(buf, author_at + 1, author_len, author, 0)
        val numbers_at = author_at + 1 + author_len
        val key = !_next_key
        val () = !_next_key := key + 1
        val cover_done = _int32_at(buf, numbers_at + 36)
        val nums = @{
          key = key, id_high = id_high, id_low = id_low,
          shelf = shelf_of_code(_int32_at(buf, numbers_at)), added = _int32_at(buf, numbers_at + 4), opened = _int32_at(buf, numbers_at + 8),
          chapter = _int32_at(buf, numbers_at + 12), chapters = _int32_at(buf, numbers_at + 16), page = _int32_at(buf, numbers_at + 20),
          pages = _int32_at(buf, numbers_at + 24), anchor = _int32_at(buf, numbers_at + 28), file_size = _int32_at(buf, numbers_at + 32),
          cover = image_of_code($AR.low_byte(cover_done)), done = $AR.band_g1($AR.low_byte($AR.bsr_int_int(cover_done, 8)), 1),
          series_number = 0, collections = 0, minutes_read = 0, pages_read = 0, finished_at = 0,
          shelf_modified = 0, collections_modified = 0, finished_modified = 0, minutes_elsewhere = 0, pages_elsewhere = 0
        }: bnums
        (* QLB2 has the series after; QLB3, then the collections; QLB1,
           neither *)
        val series_at = numbers_at + 40
        val series_len = (if version >= 2 then (if series_at < n then $AR.low_byte(byte2int0($A.get<byte>(buf, series_at))) else 0) else 0)
          : [series_len:nat | series_len < 256] int series_len
        val tail = (if version >= 5 then 41 else if version >= 4 then 21 else if version >= 3 then 9 else 5): [tail:int | tail == 5 || tail == 9 || tail == 21 || tail == 41] int tail
      in
        if version < 2 then _parse_books(buf, n, series_at, books_cons(Book(title, title_len, author, author_len, $A.alloc<byte>(1), 0, nums), books), parsed + 1, version)
        else if series_at + tail + series_len > n then let
          val () = $A.free<byte>(title)
          val () = $A.free<byte>(author)
        in @(books, parsed) end
        else let
          val series = $A.alloc<byte>(series_len + 1)
          val () = _bytes_of_into(buf, series_at + 1, series_len, series, 0)
          val nums = @{
            key = nums.key, id_high = nums.id_high, id_low = nums.id_low, shelf = nums.shelf, added = nums.added,
            opened = nums.opened, chapter = nums.chapter, chapters = nums.chapters, page = nums.page, pages = nums.pages,
            anchor = nums.anchor, file_size = nums.file_size, cover = nums.cover, done = nums.done,
            series_number = _int32_at(buf, series_at + 1 + series_len),
            collections = (if version >= 3 then (if series_at + 9 + series_len <= n then g1ofg0($AR.band_int_int(_int32_at(buf, series_at + 5 + series_len), 255)) else 0) else 0): Int,
            (* QLB4: how long it has been read, and when it was finished *)
            minutes_read = (if version >= 4 then (if series_at + 21 + series_len <= n then _int32_at(buf, series_at + 9 + series_len) else 0) else 0): Int,
            pages_read = (if version >= 4 then (if series_at + 21 + series_len <= n then _int32_at(buf, series_at + 13 + series_len) else 0) else 0): Int,
            finished_at = (if version >= 4 then (if series_at + 21 + series_len <= n then _int32_at(buf, series_at + 17 + series_len) else 0) else 0): Int,
            (* QLB5: when its shelf, collections and being finished
               changed, and its reading on other devices *)
            shelf_modified = (if version >= 5 then (if series_at + 41 + series_len <= n then _int32_at(buf, series_at + 21 + series_len) else 0) else 0): Int,
            collections_modified = (if version >= 5 then (if series_at + 41 + series_len <= n then _int32_at(buf, series_at + 25 + series_len) else 0) else 0): Int,
            finished_modified = (if version >= 5 then (if series_at + 41 + series_len <= n then _int32_at(buf, series_at + 29 + series_len) else 0) else 0): Int,
            minutes_elsewhere = (if version >= 5 then (if series_at + 41 + series_len <= n then _int32_at(buf, series_at + 33 + series_len) else 0) else 0): Int,
            pages_elsewhere = (if version >= 5 then (if series_at + 41 + series_len <= n then _int32_at(buf, series_at + 37 + series_len) else 0) else 0): Int
          }: bnums
        in _parse_books(buf, n, series_at + tail + series_len,
             books_cons(Book(title, title_len, author, author_len, series, series_len, nums), books), parsed + 1, version) end
      end
    end
  end

(* The collections stored in buf[start, n), left of them still to read,
   after the count in collections: where the books start, and the
   collections *)
fun _parse_names {l:agz}{owner:addr}{n:nat}{start:nat | start <= n}{count:nat | count <= COLL_MAX} .<COLL_MAX - count>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, start: int start, left: int, collections: colls(count), count: int count)
  : [books_at:nat | books_at <= n][total:nat | total <= COLL_MAX] @(int books_at, colls(total), int total) =
  if left <= 0 then @(start, collections, count)
  else if count >= 8 then @(start, collections, count)
  else if start + 1 > n then @(start, collections, count)
  else let
    val name_len = $AR.low_byte(byte2int0($A.get<byte>(buf, start)))
  in
    if name_len <= 0 then @(start, collections, count)
    else if name_len > 40 then @(start, collections, count)
    else if start + 1 + name_len > n then @(start, collections, count)
    else let
      val name = $A.alloc<byte>(name_len + 1)
      val () = _bytes_of_into(buf, start + 1, name_len, name, 0)
    in _parse_names(buf, n, start + 1 + name_len, left - 1, _colls_insert(collections, count, name, name_len), count + 1) end
  end

(* The collections of a library stored as version in buf[0, n), and
   where its books start *)
fn _names_of {l:agz}{owner:addr}{n:nat | n >= 4}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, version: int)
  : [books_at:nat | books_at <= n][total:nat | total <= COLL_MAX] @(int books_at, colls(total), int total) =
  if version < 3 then @(4, colls_nil(), 0)
  else if n <= 4 then @(n, colls_nil(), 0)
  else _parse_names(buf, n, 5, byte2int0($A.get<byte>(buf, 4)), colls_nil(), 0)

(* Reads the library stored under "lib"; the promise resolves with the
   number of books *)
#pub fn lib_load (): $P.promise(int, $P.Chained)

implement lib_load () = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val stored = $IDB.idb_get(key_bytes, 3)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><int>(stored, llam(found) =>
    case+ lookup_content(found) of
    | ~NoStoredContent() => $P.ret<int>(0)
    (* shown as it can be read (empty), and never saved over (#174) *)
    | ~ContentUnreadable() => let val () = storage_unreadable(LibraryRecord()) in $P.ret<int>(0) end
    | ~StoredContent(owner, buf, n) =>
      if n < 4 then let val () = piece_free(owner, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 0)) <> 81 then let val () = piece_free(owner, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 3)) < 49 then let val () = piece_free(owner, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 3)) > 53 then let val () = piece_free(owner, buf) in $P.ret<int>(0) end
      else let
        val version = byte2int0($A.get<byte>(buf, 3)) - 48
        val @(books_at, collections, collection_count) = _names_of(buf, n, version)
        val () = colls_put(CollCell(collections, collection_count))
        val @(books, count) = _parse_books(buf, n, books_at, books_nil(), 0, version)
        val () = piece_free(owner, buf)
        val () = lib_put(LibCell(_sort(books, books_nil(), !_sort_order), count))
      in $P.ret<int>(count) end)
end

(* ============================================================
   The search query
   ============================================================ *)

(* The library view shows only the books whose title or author has
   query[0, query_len) in it (letters in any case); an empty query shows
   all *)
#pub fn lib_query_set {l:agz}{size:pos}{query_len:nat | query_len <= size} (query: $A.arr(byte, l, size), query_len: int query_len): void

fun _lower_copy {source_loc,dest_loc:agz}{size,len:nat | len <= size}{i:nat | i <= len} .<len - i>.
  (source: !$A.arr(byte, source_loc, size), dest: !$A.arr(byte, dest_loc, len), len: int len, i: int i): void =
  if i >= len then ()
  else let
    val byte_value = $AR.low_byte(byte2int0($A.get<byte>(source, i)))
    val lowered = (if byte_value >= 65 then (if byte_value <= 90 then byte_value + 32 else byte_value) else byte_value)
      : [lowered:nat | lowered < 256] int lowered
    val () = $A.set<byte>(dest, i, $A.int2byte(lowered))
  in _lower_copy(source, dest, len, i + 1) end

implement lib_query_set (query, query_len) =
  if query_len <= 0 then let val () = $A.free<byte>(query) in query_put(QueryNone()) end
  else if query_len >= 256 then let val () = $A.free<byte>(query) in query_put(QueryNone()) end
  else let
    val lowered = $A.alloc<byte>(query_len)
    val () = _lower_copy(query, lowered, query_len, 0)
    val () = $A.free<byte>(query)
  in query_put(QuerySome(lowered, query_len)) end

(* Whether query[0, query_len) is in text[0, text_len) at or after i,
   letters in any case *)
fun _matches_at {text_loc,query_loc:agz}{text_len,query_len:pos}{i:nat | i + query_len <= text_len}{j:nat | j <= query_len} .<query_len - j>.
  (text: !$A.arr(byte, text_loc, text_len), text_len: int text_len,
   query: !$A.arr(byte, query_loc, query_len), query_len: int query_len, i: int i, j: int j): bool =
  if j >= query_len then true
  else if _lower(byte2int0($A.get<byte>(text, i + j))) <> byte2int0($A.get<byte>(query, j)) then false
  else _matches_at(text, text_len, query, query_len, i, j + 1)

fun _contains {text_loc,query_loc:agz}{text_len,query_len:pos}{i:nat} .<max(text_len - i + 1, 0)>.
  (text: !$A.arr(byte, text_loc, text_len), text_len: int text_len,
   query: !$A.arr(byte, query_loc, query_len), query_len: int query_len, i: int i): bool =
  if i + query_len > text_len then false
  else if _matches_at(text, text_len, query, query_len, i, 0) then true
  else _contains(text, text_len, query, query_len, i + 1)

fn _matches (book: !book, query: !query): bool =
  case+ query of
  | QueryNone() => true
  | QuerySome(query_bytes, query_len) => let
      val+ Book(title, title_len, author, author_len, _, _, _) = book
    in if _contains(title, title_len, query_bytes, query_len, 0) then true
       else _contains(author, author_len, query_bytes, query_len, 0) end

(* ============================================================
   The library view
   ============================================================ *)

(* "N%" for percent (0 to 100) in buf, from 0; its length *)
fn _percent {l:agz} (buf: !$A.arr(byte, l, 16), percent: [percent:nat | percent <= 100] int percent)
  : [text_len:pos | text_len <= 16] int text_len = let
  val digits_end = $S.int_to_str(buf, 0, 16, percent)
  val () = $A.set<byte>(buf, digits_end, $A.int2byte(37))
in digits_end + 1 end

(* How far through the book with numbers nums is, in percent *)
fn _progress (nums: bnums): [percent:nat | percent <= 100] int percent = let
  val chapters = nums.chapters
  val stored_chapter = nums.chapter
  val stored_pages = nums.pages
  val stored_page = nums.page
in
  if nums.done > 0 then 100
  else if chapters <= 0 then 0
  (* a count stored by an earlier run: past these, no book has them *)
  else if chapters > 1000000 then 0
  else if stored_pages > 1000000 then 0
  else let
    val chapter = (if stored_chapter >= 0 then (if stored_chapter < chapters then stored_chapter else chapters - 1) else 0)
      : [chapter:nat | chapter < 1000000] int chapter
    val pages = (if stored_pages > 0 then stored_pages else 1): [pages:pos | pages <= 1000000] int pages
    val page = (if stored_page >= 0 then (if stored_page < pages then stored_page else pages - 1) else 0)
      : [page:nat | page < 1000000] int page
    val percent = (chapter * 100 + (page * 100) / pages) / chapters
    val percent = (if percent >= 0 then (if percent <= 100 then percent else 100) else 0): [percent:nat | percent <= 100] int percent
  in percent end
end

#pub fn lib_progress (nums: bnums): [percent:nat | percent <= 100] int percent
implement lib_progress (nums) = _progress(nums)

(* Shows the cover of the book with this id (stored under 'c') in
   element base<index>-cover, unless the view was rendered again since
   generation *)
fn _show_cover {base_len:pos | base_len <= 16}{index:nat}
  (base: string base_len, index: int index, id_high: int, id_low: int, cover: image_type, generation: int): void = let
  val key = lib_key(99, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val stored = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.finish<$IDB.lookup>(stored, llam(found) =>
    case+ lookup_content(found) of
    | ~NoStoredContent() => ()
    (* the placeholder, as for a book without a cover *)
    | ~ContentUnreadable() => ()
    | ~StoredContent(owner, buf, n) =>
      if !_render_gen <> generation then piece_free(owner, buf)
      else let
        val mime = image_mime(cover)
        val mime_len = g1u2i(string1_length(mime))
        val mime_text = $A.alloc<byte>(mime_len)
        val () = $A.write_text(mime_text, 0, $A.text_lit(mime), mime_len)
        val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime_text)
        val @(cover_id, cover_id_len) = nid_make2(base, index, "-cover")
        val @(id_frozen, id_bytes) = $A.freeze<byte>(cover_id)
        val @(data_frozen, data_bytes) = $A.freeze<byte>(buf)
        val () = $BDOM.set_image_src(id_bytes, cover_id_len, data_bytes, n, mime_bytes, mime_len)
        val () = $A.drop<byte>(data_frozen, data_bytes)
        val () = piece_free(owner, $A.thaw<byte>(data_frozen))
        val () = release_bytes(id_frozen, id_bytes)
      in release_bytes(mime_frozen, mime_bytes) end)
end

(* ============================================================
   Book info's accessibility section: the book's metadata (stored under
   'y' at import) in the W3C Publishing Community Group's display
   guidelines' words and order
   ============================================================ *)

(* Whether a level is the one given *)
fn _is_level (level: wcag_level, wanted: wcag_level): bool = let
  fn rank (level: wcag_level): int = case+ level of NoLevel() => 0 | LevelA() => 1 | LevelAA() => 2 | LevelAAA() => 3
in rank(level) = rank(wanted) end

(* Line number line of the section, with text; the next line's number *)
fn _a11y_line {line:nat}{text_len:pos | text_len < 256} (line: int line, text: string text_len): [next:nat] int next = let
  val @(line_id, line_id_len) = nid_make("a11y-line", line)
  val () = ui_add_n("book-info-a11y-list", line_id, line_id_len, TDiv)
  val @(line_id, line_id_len) = nid_make("a11y-line", line)
  val () = ui_text_n(line_id, line_id_len, text)
in line + 1 end

(* A group's heading, as line number line *)
fn _a11y_group {line:nat}{text_len:pos | text_len < 256} (line: int line, text: string text_len): [next:nat] int next = let
  val next = _a11y_line(line, text)
  val @(line_id, line_id_len) = nid_make("a11y-line", line)
  val () = ui_attr_n(line_id, line_id_len, AClass, "a11yg")
in next end

fn _line_if {line:nat}{text_len:pos | text_len < 256} (on: bool, line: int line, text: string text_len): [next:nat] int next =
  if on then _a11y_line(line, text) else line

fn _group_if {line:nat}{text_len:pos | text_len < 256} (on: bool, line: int line, text: string text_len): [next:nat] int next =
  if on then _a11y_group(line, text) else line

(* The line for the first of first, second that holds, else the last *)
fn _line_of2 {line:nat}{first_len,second_len:pos | first_len < 256; second_len < 256}
  (first: bool, line: int line, first_text: string first_len, second_text: string second_len): [next:nat] int next =
  if first then _a11y_line(line, first_text) else _a11y_line(line, second_text)

fn _line_of3 {line:nat}{first_len,second_len,third_len:pos | first_len < 256; second_len < 256; third_len < 256}
  (first: bool, second: bool, line: int line,
   first_text: string first_len, second_text: string second_len, third_text: string third_len): [next:nat] int next =
  if first then _a11y_line(line, first_text) else _line_of2(second, line, second_text, third_text)

fn _line_of4 {line:nat}{first_len,second_len,third_len,fourth_len:pos | first_len < 256; second_len < 256; third_len < 256; fourth_len < 256}
  (first: bool, second: bool, third: bool, line: int line,
   first_text: string first_len, second_text: string second_len, third_text: string third_len, fourth_text: string fourth_len)
  : [next:nat] int next =
  if first then _a11y_line(line, first_text) else _line_of3(second, third, line, second_text, third_text, fourth_text)

(* The statements for flags, from line number line *)
fn _a11y_lines {line:nat} (flags: int, line: int line): [next:nat] int next = let
  (* Ways of reading and Conformance are shown even with no metadata *)
  val line = _a11y_group(line, "Ways of reading")
  val line = _line_of2(a11y_has(flags, Transformable()), line, "Appearance can be modified",
    "No information about appearance modifiability is available")
  val readable = a11y_has(flags, SufficientText()) || (a11y_has(flags, TextualMode()) && ~a11y_has(flags, VisualMode()))
  val line = _line_of3(readable, a11y_has(flags, VisualMode()), line, "Readable in read aloud or dynamic braille",
    "Not fully readable in read aloud or dynamic braille", "No information about nonvisual reading is available")
  val line = _line_if(a11y_has(flags, AlternativeText()), line, "Has alternative text")
  val line = _a11y_group(line, "Conformance")
  val level = a11y_level(flags)
  val line = _line_of4(_is_level(level, LevelAAA()), _is_level(level, LevelAA()), _is_level(level, LevelA()), line,
    "This publication exceeds accepted accessibility standards",
    "This publication meets accepted accessibility standards",
    "This publication meets minimum accessibility standards", "No information is available")
  val navigation = a11y_has(flags, TableOfContents()) || a11y_has(flags, TermIndex())
    || a11y_has(flags, StructuralNavigation()) || a11y_has(flags, PageNavigation())
  val line = _group_if(navigation, line, "Navigation")
  val line = _line_if(a11y_has(flags, TableOfContents()), line, "Table of contents")
  val line = _line_if(a11y_has(flags, TermIndex()), line, "Index")
  val line = _line_if(a11y_has(flags, StructuralNavigation()), line, "Headings")
  val line = _line_if(a11y_has(flags, PageNavigation()), line, "Go to page")
  val rich = a11y_has(flags, MathMarkup()) || a11y_has(flags, LongDescription())
    || a11y_has(flags, Transcript()) || a11y_has(flags, Captions())
  val line = _group_if(rich, line, "Rich content")
  val line = _line_if(a11y_has(flags, MathMarkup()), line, "Math as MathML")
  val line = _line_if(a11y_has(flags, LongDescription()), line, "Information-rich images are described by extended descriptions")
  val line = _line_if(a11y_has(flags, Transcript()), line, "Transcript(s) provided")
  val line = _line_if(a11y_has(flags, Captions()), line, "Videos have closed captions")
  val hazards = a11y_has(flags, NoHazards()) || a11y_has(flags, Flashing()) || a11y_has(flags, MotionSimulation())
    || a11y_has(flags, Sound()) || a11y_has(flags, NoFlashingHazard()) || a11y_has(flags, NoMotionHazard())
    || a11y_has(flags, NoSoundHazard()) || a11y_has(flags, HazardsUnknown())
  val line = _group_if(hazards, line, "Hazards")
  val line = _line_if(a11y_has(flags, NoHazards()), line, "No hazards")
  val line = _line_if(a11y_has(flags, Flashing()), line, "Flashing content")
  val line = _line_if(a11y_has(flags, MotionSimulation()), line, "Motion simulation")
  val line = _line_if(a11y_has(flags, Sound()), line, "Sounds")
  val line = _line_if(a11y_has(flags, NoFlashingHazard()), line, "No flashing hazards")
  val line = _line_if(a11y_has(flags, NoMotionHazard()), line, "No motion simulation hazards")
  val line = _line_if(a11y_has(flags, NoSoundHazard()), line, "No sound hazards")
in _line_if(a11y_has(flags, HazardsUnknown()), line, "The presence of hazards is unknown") end

(* source[6 + j, 6 + count) into dest[j, count) *)
fun _summary_copy {source_loc,dest_loc:agz}{owner:addr}{source_size:nat}{count:nat | count + 6 <= source_size}
  {dest_size:pos | count <= dest_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arrx(byte, source_loc, source_size, owner), dest: !$A.arr(byte, dest_loc, dest_size), count: int count, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(dest, j, $A.get<byte>(source, 6 + j))
  in _summary_copy(source, dest, count, j + 1) end

(* Fills Book info's accessibility section for book (id_high, id_low) *)
#pub fn lib_a11y_show (id_high: int, id_low: int): void

implement lib_a11y_show (id_high, id_low) = let
  val () = ui_clear("book-info-a11y-list")
  val key = lib_key(121, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val stored = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.finish<$IDB.lookup>(stored, llam(found) =>
    case+ lookup_content(found) of
    | ~NoStoredContent() => let
        (* imported before this was read *)
        val _ = _a11y_line(0, "Import this book's file again to see its accessibility information.")
      in () end
    (* no summary: importing again is not what would mend it *)
    | ~ContentUnreadable() => ()
    | ~StoredContent(owner, buf, n) =>
      if n < 6 then piece_free(owner, buf)
      else let
        val flags = _int32_at(buf, 2)
        val line = _a11y_lines(flags, 0)
        val summary_len = n - 6
        val () = (if summary_len > 0 then (if summary_len < 65536 then let
            val line = _a11y_group(line, "Accessibility summary")
            val summary = $A.alloc<byte>(summary_len)
            val () = _summary_copy(buf, summary, summary_len, 0)
            val @(line_id, line_id_len) = nid_make("a11y-line", line)
            val () = ui_add_n("book-info-a11y-list", line_id, line_id_len, TDiv)
            val @(line_id, line_id_len) = nid_make("a11y-line", line)
          in ui_text_n_buf(line_id, line_id_len, summary, summary_len) end else ()) else ())
      in piece_free(owner, buf) end)
end

#pub fn lib_show_cover_in {id_len:pos | id_len < 256} (id: string id_len, id_high: int, id_low: int, cover: image_type): void

implement lib_show_cover_in (id, id_high, id_low, cover) = let
  val key = lib_key(99, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val stored = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.finish<$IDB.lookup>(stored, llam(found) =>
    case+ lookup_content(found) of
    | ~NoStoredContent() => ()
    | ~ContentUnreadable() => ()
    | ~StoredContent(owner, buf, n) => let
        val mime = image_mime(cover)
        val mime_len = g1u2i(string1_length(mime))
        val mime_text = $A.alloc<byte>(mime_len)
        val () = $A.write_text(mime_text, 0, $A.text_lit(mime), mime_len)
        val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime_text)
        val id_len = g1u2i(string1_length(id))
        val id_text = $A.alloc<byte>(id_len)
        val () = $A.write_text(id_text, 0, $A.text_lit(id), id_len)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(id_text)
        val @(data_frozen, data_bytes) = $A.freeze<byte>(buf)
        val () = $BDOM.set_image_src(id_bytes, id_len, data_bytes, n, mime_bytes, mime_len)
        val () = $A.drop<byte>(data_frozen, data_bytes)
        val () = piece_free(owner, $A.thaw<byte>(data_frozen))
        val () = release_bytes(id_frozen, id_bytes)
      in release_bytes(mime_frozen, mime_bytes) end)
end

(* The series line of card index: the series' name, and " · N" *)
fn _card_series {base_len:pos | base_len <= 16}{index:nat}{l:agz}{size:pos}{series_len:pos | series_len < size; series_len < 256}
  (base: string base_len, index: int index, series: !$A.arr(byte, l, size), series_len: int series_len, series_index: Int): void = let
  val @(info_id, info_id_len) = nid_make2(base, index, "-info")
  val @(series_id, series_id_len) = nid_make2(base, index, "-series")
  val () = ui_add_nn(info_id, info_id_len, series_id, series_id_len, TDiv)
  val @(series_id, series_id_len) = nid_make2(base, index, "-series")
  val () = ui_attr_n(series_id, series_id_len, AClass, "bser")
  val text = $A.alloc<byte>(series_len + 20)
  val () = _copy(series, series_len, text, 0, 0)
  val text_len = _series_num(text, series_len, series_index)
  val @(series_id, series_id_len) = nid_make2(base, index, "-series")
in ui_text_n_buf(series_id, series_id_len, text, text_len) end

(* Card index for book: cover, title, author, progress; its elements'
   ids are base<index> (the card), base<index>-cover and so on, in row
   row_prefix<index> under parent, with its More button
   (more_prefix<index>) when more *)
fn _card {index:nat}{base_len,row_len,more_len,parent_len:pos | base_len <= 16; row_len <= 16; more_len <= 16; parent_len < 256}
  (book: !book, index: int index, generation: int, base: string base_len, row_prefix: string row_len, more_prefix: string more_len,
   parent: string parent_len, more: bool): void = let
  val+ Book(title, title_len, author, author_len, series, series_len, nums) = book
  (* the row: the card, which opens the book, then its More button,
     which opens the book menu; the row is named by the book's title *)
  val @(row_id, row_id_len) = nid_make(row_prefix, index)
  val () = ui_add_n(parent, row_id, row_id_len, TDiv)
  val @(row_id, row_id_len) = nid_make(row_prefix, index)
  val () = ui_attr_n(row_id, row_id_len, AClass, "cardrow")
  val @(parent_id, parent_id_len) = nid_make(row_prefix, index)
  val @(card_id, card_id_len) = nid_make(base, index)
  val () = ui_btn_nn(parent_id, parent_id_len, card_id, card_id_len, "card")
  val () = (if more then let
      val @(parent_id, parent_id_len) = nid_make(row_prefix, index)
      val @(more_id, more_id_len) = nid_make(more_prefix, index)
    in ui_icon_btn_nn(parent_id, parent_id_len, more_id, more_id_len, "cmore", IcMore, "Book menu") end else ())
  val @(row_id, row_id_len) = nid_make(row_prefix, index)
  val @(title_id, title_id_len) = nid_make2(base, index, "-title")
  val () = ui_labelled_nn(row_id, row_id_len, NGroup, title_id, title_id_len)
  (* cover: decorative, the title is beside it *)
  val @(parent_id, parent_id_len) = nid_make(base, index)
  val @(cover_id, cover_id_len) = nid_make2(base, index, "-cover")
  val () = ui_img_nn(parent_id, parent_id_len, cover_id, cover_id_len, (if is_image(nums.cover) then "cov" else "cov cov0"): [class_len:pos | class_len < 256] string class_len)
  val () = (if is_image(nums.cover) then _show_cover(base, index, nums.id_high, nums.id_low, nums.cover, generation) else ())
  (* title, author *)
  val @(parent_id, parent_id_len) = nid_make(base, index)
  val @(info_id, info_id_len) = nid_make2(base, index, "-info")
  val () = ui_add_nn(parent_id, parent_id_len, info_id, info_id_len, TDiv)
  val @(info_id, info_id_len) = nid_make2(base, index, "-info")
  val () = ui_attr_n(info_id, info_id_len, AClass, "cinfo")
  val @(parent_id, parent_id_len) = nid_make2(base, index, "-info")
  val @(title_id, title_id_len) = nid_make2(base, index, "-title")
  val () = ui_add_nn(parent_id, parent_id_len, title_id, title_id_len, TDiv)
  val @(title_id, title_id_len) = nid_make2(base, index, "-title")
  val () = ui_attr_n(title_id, title_id_len, AClass, "bt")
  val title_text = $A.alloc<byte>(title_len)
  val () = _copy(title, title_len, title_text, 0, 0)
  val @(title_id, title_id_len) = nid_make2(base, index, "-title")
  val () = ui_text_n_buf(title_id, title_id_len, title_text, title_len)
  val @(parent_id, parent_id_len) = nid_make2(base, index, "-info")
  val @(author_id, author_id_len) = nid_make2(base, index, "-author")
  val () = ui_add_nn(parent_id, parent_id_len, author_id, author_id_len, TDiv)
  val @(author_id, author_id_len) = nid_make2(base, index, "-author")
  val () = ui_attr_n(author_id, author_id_len, AClass, "ba")
  val author_text = $A.alloc<byte>(author_len)
  val () = _copy(author, author_len, author_text, 0, 0)
  val @(author_id, author_id_len) = nid_make2(base, index, "-author")
  val () = ui_text_n_buf(author_id, author_id_len, author_text, author_len)
  (* its series, and its number in it: "Foundation · 2" *)
  val () = (if series_len > 0 then _card_series(base, index, series, series_len, nums.series_number) else ())
  (* progress *)
  val @(parent_id, parent_id_len) = nid_make2(base, index, "-info")
  val @(progress_id, progress_id_len) = nid_make2(base, index, "-progress")
  val () = ui_add_nn(parent_id, parent_id_len, progress_id, progress_id_len, TDiv)
  val @(progress_id, progress_id_len) = nid_make2(base, index, "-progress")
  val () = ui_attr_n(progress_id, progress_id_len, AClass, "prog")
  val percent = _progress(nums)
in
  if nums.done > 0 then let
    val @(progress_id, progress_id_len) = nid_make2(base, index, "-progress")
  in ui_text_n(progress_id, progress_id_len, "Done") end
  else if nums.opened <= 0 then let
    val @(progress_id, progress_id_len) = nid_make2(base, index, "-progress")
  in ui_text_n(progress_id, progress_id_len, "New") end
  else let
    val @(parent_id, parent_id_len) = nid_make2(base, index, "-progress")
    val @(bar_id, bar_id_len) = nid_make2(base, index, "-bar")
    val () = ui_add_nn(parent_id, parent_id_len, bar_id, bar_id_len, TDiv)
    val @(bar_id, bar_id_len) = nid_make2(base, index, "-bar")
    val () = ui_attr_n(bar_id, bar_id_len, AClass, "pbar")
    val @(parent_id, parent_id_len) = nid_make2(base, index, "-bar")
    val @(fill_id, fill_id_len) = nid_make2(base, index, "-fill")
    val () = ui_add_nn(parent_id, parent_id_len, fill_id, fill_id_len, TDiv)
    val @(fill_id, fill_id_len) = nid_make2(base, index, "-fill")
    val () = ui_attr_n(fill_id, fill_id_len, AClass, "pfill")
    val @(fill_id, fill_id_len) = nid_make2(base, index, "-fill")
    val () = ui_place_n(fill_id, fill_id_len, PWidth, percent * 10)
    val @(parent_id, parent_id_len) = nid_make2(base, index, "-progress")
    val @(percent_id, percent_id_len) = nid_make2(base, index, "-percent")
    val () = ui_add_nn(parent_id, parent_id_len, percent_id, percent_id_len, TSpan)
    val percent_text = $A.alloc<byte>(16)
    val percent_len = _percent(percent_text, percent)
    val @(percent_id, percent_id_len) = nid_make2(base, index, "-percent")
  in ui_text_n_buf(percent_id, percent_id_len, percent_text, percent_len) end
end

(* How the library's cards are laid out: a list, or a grid of covers *)
#pub datatype layout = ListLayout | GridLayout

(* Which books the library shows *)
#pub datatype book_filter = AllBooks | Unread | BeingRead | Finished

val _grid = ref<layout>(ListLayout())
val _filter = ref<book_filter>(AllBooks())

(* Whether a book with numbers nums passes the filter *)
fn _passes (nums: bnums): bool =
  case+ !_filter of
  | Unread() => nums.opened <= 0
  | BeingRead() => (if nums.opened > 0 then nums.done <= 0 else false)
  | Finished() => nums.done > 0
  | AllBooks() => true

(* The cards of the books shown, but for the book to continue (index
   continued, or -1), which its own card shows above *)
fun _cards {count:nat}{i:nat} .<count>. (books: !books(count), i: int i, continued: int, shelf: shelf, query: !query, generation: int, shown: int): int =
  case+ books of
  | books_nil() => shown
  | books_cons(book, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = book
      val visible = (if i = continued then false else if same_shelf(nums.shelf, shelf) then (if _passes(nums) then (if _in_shown(nums) then _matches(book, query) else false) else false) else false): bool
      val () = (if visible then _card(book, i, generation, "book", "book-row", "book-more", "book-list", true) else ())
    in _cards(rest, i + 1, continued, shelf, query, generation, (if visible then shown + 1 else shown)) end

(* The book to continue: the one on the shelf opened last and not
   finished: its index, or -1 (best is the one so far, opened at
   latest_opened) *)
fun _latest {count:nat}{i:nat} .<count>. (books: !books(count), i: int i, best: int, latest_opened: Int): int =
  case+ books of
  | books_nil() => best
  | books_cons(book, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = book
      val better = (if same_shelf(nums.shelf, OnShelf()) then (if nums.done <= 0 then (if nums.opened > 0 then nums.opened > latest_opened else false) else false) else false): bool
    in if better then _latest(rest, i + 1, i, nums.opened) else _latest(rest, i + 1, best, latest_opened) end

(* Card want of books, into the Continue reading section, with the
   same More button as the list's cards (the list leaves it out) *)
fun _continue_card {count:nat}{i:nat} .<count>. (books: !books(count), i: int i, want: int, generation: int): void =
  case+ books of
  | books_nil() => ()
  | books_cons(book, rest) =>
    if i = want then _card(book, i, generation, "continue", "continue-row", "continue-more", "continue-list", true)
    else _continue_card(rest, i + 1, want, generation)

(* The view's controls, pressed as the view is *)
fn _pressed {id_len:pos | id_len < 256} (id: string id_len, pressed: bool): void =
  if pressed then ui_attr(id, APressed, "true") else ui_attr(id, APressed, "false")

fn _view_show (): void = let
  val is_grid = (case+ !_grid of GridLayout() => true | ListLayout() => false): bool
  val filter = !_filter
  val () = (if is_grid then ui_attr("book-list", AClass, "list grid") else ui_attr("book-list", AClass, "list"))
  val () = _pressed("view-grid", is_grid)
  val () = _pressed("view-list", ~is_grid)
  val () = _pressed("filter-books-all", (case+ filter of AllBooks() => true | _ => false))
  val () = _pressed("filter-unread", (case+ filter of Unread() => true | _ => false))
  val () = _pressed("filter-reading", (case+ filter of BeingRead() => true | _ => false))
in _pressed("filter-finished", (case+ filter of Finished() => true | _ => false)) end

(* A layout as backups and the settings keep it: 0 a list, 1 a grid *)
#pub fn layout_code (l: layout): [code:nat | code <= 1] int code
implement layout_code (l) = case+ l of ListLayout() => 0 | GridLayout() => 1

#pub fn layout_of_code (code: int): layout
implement layout_of_code (code) = if code = 1 then GridLayout() else ListLayout()

(* A filter as backups and the settings keep it: 0 all, 1 unread, 2
   being read, 3 finished *)
#pub fn filter_code (f: book_filter): [code:nat | code <= 3] int code
implement filter_code (f) = case+ f of AllBooks() => 0 | Unread() => 1 | BeingRead() => 2 | Finished() => 3

#pub fn filter_of_code (code: int): book_filter
implement filter_of_code (code) =
  if code = 1 then Unread() else if code = 2 then BeingRead() else if code = 3 then Finished() else AllBooks()

(* The library's view as the settings keep it: its sort order (below
   8), plus 8 for a grid, plus 16 times the filter; packed only to be
   saved *)
#pub fn lib_state_get (): int
implement lib_state_get () = sort_code(!_sort_order) + 8 * layout_code(!_grid) + 16 * filter_code(!_filter)

(* The sort order a kept state holds *)
#pub fn lib_state_sort (state: int): sort_order
implement lib_state_sort (state) =
  if state >= 0 then (if state < 64 then sort_of_code($AR.band_int_int(state, 7)) else LastOpened()) else LastOpened()

(* Sets the view from a kept state (sorts, but does not render) *)
#pub fn lib_state_set (state: int): void
implement lib_state_set (state) = let
  val state = (if state >= 0 then (if state < 64 then state else 0) else 0): int
  val () = !_grid := layout_of_code($AR.band_int_int(state / 8, 1))
  val () = !_filter := filter_of_code($AR.band_int_int(state / 16, 3))
  val () = _view_show()
in lib_sort(sort_of_code($AR.band_int_int(state, 7))) end

(* Sets the layout and the filter (does not render) *)
#pub fn lib_view_set (grid: layout, filter: book_filter): void
implement lib_view_set (grid, filter) = let
  val () = !_grid := grid
  val () = !_filter := filter
in _view_show() end

#pub fn lib_grid_set (grid: layout): void
implement lib_grid_set (grid) = let
  val () = !_grid := grid
  val () = _view_show()
in lib_render() end

#pub fn lib_filter_set (filter: book_filter): void
implement lib_filter_set (filter) = let
  val () = !_filter := filter
  val () = _view_show()
in lib_render() end

#pub fn lib_grid_get (): layout
implement lib_grid_get () = !_grid
#pub fn lib_filter_get (): book_filter
implement lib_filter_get () = !_filter

(* ============================================================
   The hint to add Quire to the Home Screen
   ============================================================ *)

(* On iOS Safari there is no install prompt, and what a page keeps is
   cleared after 7 days without a visit, but not for an app on the Home
   Screen. The hint is offered there (bridge's is_ios_browser: iOS
   Safari, not the Home Screen) once the library has a book, until it is
   dismissed; dismissed until the last run's answer is read, so it never
   shows twice *)
val _install_hint_dismissed = ref<bool>(true)

fn _install_hint_key (): [l:agz] $A.arr(byte, l, 12) = let
  val key = $A.alloc<byte>(12)
  val () = $A.write_text(key, 0, $A.text_lit("install-hint"), 12)
in key end

fn _install_hint_show (): void =
  if !_install_hint_dismissed then ui_attr("install-hint", AClass, "ihint")
  else if ~($BAPP.is_ios_browser()) then ui_attr("install-hint", AClass, "ihint")
  else if lib_count() > 0 then ui_attr("install-hint", AClass, "ihint on")
  else ui_attr("install-hint", AClass, "ihint")

(* Reads whether the hint was dismissed in an earlier run *)
#pub fn lib_install_hint_load (): void
implement lib_install_hint_load () = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_install_hint_key())
  val stored = $IDB.idb_get(key_bytes, 12)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.finish<$IDB.lookup>(stored, llam(found) => let
    val () = (case+ lookup_bytes(found) of
      | ~NothingStored() => !_install_hint_dismissed := false
      (* taken as dismissed: a hint each session would nag *)
      | ~StoredUnreadable() => !_install_hint_dismissed := true
      | ~StoredBytes(blob, _) => $A.free<byte>(blob))
  in _install_hint_show() end)
end

(* The hint dismissed, for good *)
#pub fn lib_install_hint_dismiss (): void
implement lib_install_hint_dismiss () = let
  val () = !_install_hint_dismissed := true
  val value = $A.alloc<byte>(1)
  val () = $A.write_byte(value, 0, 1)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_install_hint_key())
  (* ignored: a dismissal not stored only shows the hint once more *)
  val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 12, value_bytes, 1), llam(_) => ())
  val () = release_bytes(key_frozen, key_bytes)
  val () = release_bytes(value_frozen, value_bytes)
in _install_hint_show() end

(* Renders the library view: the cards of the shelf shown whose title
   or author matches the query, in the sort order *)
#pub fn lib_render (): void

implement lib_render () = let
  val () = !_render_gen := !_render_gen + 1
  val generation = !_render_gen
  val () = ui_clear("book-list")
  val () = ui_clear("continue-list")
  val () = _view_show()
  val shelf = !_shelf
  val query = query_take()
  val has_query = (case+ query of QuerySome(_, _) => true | QueryNone() => false): bool
  val library = lib_take()
  val+ @LibCell(books, _) = library
  (* the book to continue, above the rest: on the shelf, unsearched, in
     no one collection, and unless only unread or finished books are
     shown. It is shown once: its card there, not again in the list
     (quire#273), whatever the sort *)
  val shows_reading = (case+ !_filter of AllBooks() => true | BeingRead() => true | _ => false): bool
  val want = (if same_shelf(shelf, OnShelf()) then (if ~has_query then (if !_coll_shown < 0 then (if shows_reading then _latest(books, 0, ~1, 0) else ~1) else ~1) else ~1) else ~1): int
  val () = (if want >= 0 then _continue_card(books, 0, want, generation) else ())
  val listed = _cards(books, 0, want, shelf, query, generation, 0)
  val shown = (if want >= 0 then listed + 1 else listed): int
  prval () = fold@(library)
  val () = lib_put(library)
  val () = ui_show("continue-reading", want >= 0)
  val () = query_put(query)
  val () = ui_show("library-empty", shown = 0)
  val () = _coll_row()
  val () = _install_hint_show()
in
  if shown > 0 then ()
  else if has_query then ui_text("library-empty", "No books match")
  else if !_coll_shown >= 0 then ui_text("library-empty", "No books in this collection")
  else (case+ !_filter of
    | Unread() => ui_text("library-empty", "No unread books")
    | BeingRead() => ui_text("library-empty", "No books being read")
    | Finished() => ui_text("library-empty", "No finished books")
    | AllBooks() => (case+ shelf of
      | Hidden() => ui_text("library-empty", "No hidden books")
      | Archived() => ui_text("library-empty", "No archived books")
      | Trash() => ui_text("library-empty", "The Trash is empty")
      | OnShelf() => ui_text("library-empty", "Import an EPUB file to start reading.")))
end

(* Shows shelf *)
#pub fn lib_shelf_set (shelf: shelf): void

implement lib_shelf_set (shelf) = let
  val () = !_shelf := shelf
in
  case+ shelf of
  | Hidden() => ui_text("shelf-button", "Hidden")
  | Archived() => ui_text("shelf-button", "Archived")
  | Trash() => ui_text("shelf-button", "Trash")
  | OnShelf() => ui_text("shelf-button", "Library")
end

(* The next shelf the shelf button shows *)
#pub fn shelf_next (shelf: shelf): shelf
implement shelf_next (shelf) =
  case+ shelf of OnShelf() => Hidden() | Hidden() => Archived() | Archived() => Trash() | Trash() => OnShelf()

(* The sort button's label for order *)
#pub fn lib_sort_label (order: sort_order): void

implement lib_sort_label (order) =
  case+ order of
  | ByTitle() => ui_text("sort-button", "Sort: Title")
  | ByAuthor() => ui_text("sort-button", "Sort: Author")
  | DateAdded() => ui_text("sort-button", "Sort: Date added")
  | BySeries() => ui_text("sort-button", "Sort: Series")
  | LastOpened() => ui_text("sort-button", "Sort: Last opened")

(* ============================================================
   Dates and sizes, as text
   ============================================================ *)

(* value as two digits at buf[start, start + 2) (value from 0 to 99) *)
fn _two_digits {l:agz}{n:pos}{start:nat | start + 2 <= n}{value:nat | value < 100} (buf: !$A.arr(byte, l, n), start: int start, value: int value): void = let
  val () = $A.set<byte>(buf, start, $A.int2byte(48 + value / 10))
in $A.set<byte>(buf, start + 1, $A.int2byte(48 + value - (value / 10) * 10)) end

(* The day minutes (minutes since the epoch, UTC) falls on, as
   YYYY-MM-DD in buf (its length); a civil date by Howard Hinnant's
   days_from_civil inverse (its z, doe, yoe, doy and mp are shifted_days,
   day_of_era, year_of_era, day_of_year and month_from_march here) *)
#pub fn date_text {l:agz} (buf: !$A.arr(byte, l, 32), minutes: Int): [text_len:nat | text_len <= 32] int text_len

implement date_text (buf, minutes) = let
  val days = (if minutes > 0 then minutes / 1440 else 0): [days:nat] int days
  (* days up to year 9999, past which no clock this app runs on goes *)
  val days = (if days > 2932896 then 2932896 else days): [days:nat | days <= 2932896] int days
  val shifted_days = days + 719468
  val era = shifted_days / 146097
  val day_of_era = shifted_days - era * 146097
  val year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365
  val year = year_of_era + era * 400
  val day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  val month_from_march = (5 * day_of_year + 2) / 153
  val day = day_of_year - (153 * month_from_march + 2) / 5 + 1
  val month = (if month_from_march < 10 then month_from_march + 3 else month_from_march - 9): Int
  val year = (if month <= 2 then year + 1 else year): Int
  val year_end = $S.int_to_str(buf, 0, 32, year)
  val month = (if month >= 1 then (if month <= 12 then month else 12) else 1): [month:nat | month < 100] int month
  val day = (if day >= 1 then (if day <= 31 then day else 31) else 1): [day:nat | day < 100] int day
  val () = $A.set<byte>(buf, year_end, $A.int2byte(45))
  val () = _two_digits(buf, year_end + 1, month)
  val () = $A.set<byte>(buf, year_end + 3, $A.int2byte(45))
  val () = _two_digits(buf, year_end + 4, day)
in year_end + 6 end

(* The year day (days since 1970-01-01) falls in, by the same inverse
   of days_from_civil *)
#pub fn year_of_day (day: Int): Int

implement year_of_day (day) = let
  val days = (if day > 0 then (if day > 2932896 then 2932896 else day) else 0): [days:nat | days <= 2932896] int days
  val shifted_days = days + 719468
  val era = shifted_days / 146097
  val day_of_era = shifted_days - era * 146097
  val year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365
  val day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  val month_from_march = (5 * day_of_year + 2) / 153
in if month_from_march >= 10 then year_of_era + era * 400 + 1 else year_of_era + era * 400 end

(* How many books were finished in year, their days local by offset
   minutes east of UTC *)
fun _finished_in {count:nat} .<count>. (books: !books(count), year: Int, offset: Int, finished: int): int =
  case+ books of
  | books_nil() => finished
  | books_cons(book, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = book
      val in_year = (if nums.finished_at > 0 then year_of_day((nums.finished_at + offset) / 1440) = year else false): bool
    in _finished_in(rest, year, offset, (if in_year then finished + 1 else finished)) end

#pub fn lib_finished_in (year: Int, offset: Int): int

implement lib_finished_in (year, offset) = let
  val library = lib_take()
  val+ @LibCell(books, _) = library
  val finished = _finished_in(books, year, offset, 0)
  prval () = fold@(library)
  val () = lib_put(library)
in finished end

(* bytes as "N KB" or "N.N MB" in buf (its length) *)
#pub fn size_text {l:agz} (buf: !$A.arr(byte, l, 32), bytes: Int): [text_len:nat | text_len <= 32] int text_len

implement size_text (buf, bytes) =
  if bytes < 1048576 then let
    val kilobytes = (if bytes > 0 then (bytes + 1023) / 1024 else 0): Int
    val digits_end = $S.int_to_str(buf, 0, 32, kilobytes)
    val () = $A.set<byte>(buf, digits_end, $A.int2byte(32))
    val () = $A.set<byte>(buf, digits_end + 1, $A.int2byte(75))
    val () = $A.set<byte>(buf, digits_end + 2, $A.int2byte(66))
  in digits_end + 3 end
  else let
    val tenths = bytes / 104858
    val digits_end = $S.int_to_str(buf, 0, 32, tenths / 10)
    val () = $A.set<byte>(buf, digits_end, $A.int2byte(46))
    val tenth = tenths - (tenths / 10) * 10
    val tenth = (if tenth >= 0 then (if tenth <= 9 then tenth else 9) else 0): [tenth:nat | tenth <= 9] int tenth
    val () = $A.set<byte>(buf, digits_end + 1, $A.int2byte(48 + tenth))
    val () = $A.set<byte>(buf, digits_end + 2, $A.int2byte(32))
    val () = $A.set<byte>(buf, digits_end + 3, $A.int2byte(77))
    val () = $A.set<byte>(buf, digits_end + 4, $A.int2byte(66))
  in digits_end + 5 end

end (* #target wasm *)
