(* annot -- the open book's bookmarks and highlights, with their notes:
   kept in order of place in the book, stored under the book's "a" key,
   shown in the reader, listed and exported as Markdown *)

(* A place is a content node's number (the reader numbers a chapter's
   nodes the same way each time it is shown) and an offset in its
   text. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use wasm.bats-packages.dev/decompress as DC

staload "book.sats"
staload "ui.sats"
staload "modal.sats"
staload "undo.sats"
staload "library.sats"
staload "toc.sats"
staload "jsonio.sats"
staload "mem.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* A quote's and a note's most bytes; the most annotations a book has;
   the bytes one takes when stored, at most *)
#define TEXT_MAX 400
#define NOTE_MAX 2000
#define ANNOTATIONS_MAX 400
#define STORED_MAX 2457
(* A print page's label's most bytes (the reader's, from the book's
   page-list) *)
#define LABEL_MAX 16

(* Each annotation: its kind (0 a bookmark; a highlight: 1 yellow, 2
   orange, 3 underlined), chapter, the
   node and offset it starts at and those it ends at, the page it was
   made on, when (epoch minutes), its text text[0, text_len) (a
   highlight's quote, a bookmark's first words), its note
   note[0, note_len) and the print page it was made on,
   label[0, label_len) (none, 0, when the chapter has no page-list
   break before it) *)
datavtype annotations(int) =
  | annotations_nil(0) of ()
  | {count:nat}{text_loc,note_loc,label_loc:agz}{text_len:nat | text_len <= TEXT_MAX}{note_len:nat | note_len <= NOTE_MAX}{label_len:nat | label_len <= LABEL_MAX}
    annotations_cons(count + 1) of (Int, Int, Int, Int, Int, Int, Int, Int,
      $A.arr(byte, text_loc, text_len + 1), int text_len, $A.arr(byte, note_loc, note_len + 1), int note_len,
      $A.arr(byte, label_loc, label_len + 1), int label_len, annotations(count))

fun annotations_free {count:nat} .<count>. (annotations: annotations(count)): void =
  case+ annotations of
  | ~annotations_nil() => ()
  | ~annotations_cons(_, _, _, _, _, _, _, _, text, _, note, _, label, _, rest) => let
      val () = $A.free<byte>(text)
      val () = $A.free<byte>(note)
      val () = $A.free<byte>(label)
    in annotations_free(rest) end

datavtype annotations_cell =
  | {count:nat | count <= ANNOTATIONS_MAX} AnnotationsCell of (annotations(count), int count)

val _cell = ref<annotations_cell>(AnnotationsCell(annotations_nil(), 0))
(* The book the annotations are of *)
val _book_id_high = ref<int>(0)
val _book_id_low = ref<int>(0)

(* The print page of the page shown (the reader's, from the book's
   page-list): the label a highlight or bookmark made now keeps *)
datavtype print_page =
  | NoPrintPage of ()
  | {label_loc:agz}{label_len:nat | label_len <= LABEL_MAX}
    PrintPage of ($A.arr(byte, label_loc, label_len + 1), int label_len)

val _print_page = ref<print_page>(NoPrintPage())

fn _print_page_swap (page: print_page): print_page = let
  var previous: print_page = page
  val () = ref_exch_elt<print_page>(_print_page, previous)
in previous end

fn _print_page_free (page: print_page): void =
  case+ page of
  | ~NoPrintPage() => ()
  | ~PrintPage(label, _) => $A.free<byte>(label)

fn _take (): annotations_cell = let
  var cell: annotations_cell = AnnotationsCell(annotations_nil(), 0)
  val () = ref_exch_elt<annotations_cell>(_cell, cell)
in cell end

fn _put (cell: annotations_cell): void = let
  var previous: annotations_cell = cell
  val () = ref_exch_elt<annotations_cell>(_cell, previous)
  val+ ~AnnotationsCell(annotations, _) = previous
in annotations_free(annotations) end

(* Whether an annotation of kind kind is a highlight *)
fn _is_highlight (kind: int): bool = kind >= 1

(* A highlight's style: 0 yellow, 1 orange, 2 underlined (a kind this
   version does not know is shown yellow) *)
fn _style_of (kind: int): [style:nat | style <= 2] int style =
  if kind = 2 then 1 else if kind = 3 then 2 else 0

(* The mark set a highlight of kind kind is shown in: the stylesheet's
   ::highlight(bats-mark-1), 3 or 4 (2 is the search's) *)
fn _mark_set (kind: int): int =
  if kind = 2 then 3 else if kind = 3 then 4 else 1

(* destination[j, count) := source[j, count) *)
fun _copy_bytes {source_loc,destination_loc:agz}{source_size,destination_size:pos}{count:nat | count <= source_size; count <= destination_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), destination: !$A.arr(byte, destination_loc, destination_size), count: int count, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(destination, j, $A.get<byte>(source, j))
  in _copy_bytes(source, destination, count, j + 1) end

(* A copy of source[0, source_len), in source_len + 1 bytes *)
fn _copy_prefix {l:agz}{n:pos}{source_len:nat | source_len < n; source_len < 1048576} (source: !$A.arr(byte, l, n), source_len: int source_len): [copy_loc:agz] $A.arr(byte, copy_loc, source_len + 1) = let
  val prefix_copy = $A.alloc<byte>(source_len + 1)
  val () = _copy_bytes(source, prefix_copy, source_len, 0)
in prefix_copy end

(* The page shown's print page is label[0, label_len) (none when
   label_len is 0) *)
#pub fn annot_print_page_set {l:agz}{n:pos}{label_len:nat | label_len <= 16; label_len < n}
  (label: !$A.arr(byte, l, n), label_len: int label_len): void

implement annot_print_page_set (label, label_len) =
  _print_page_free(_print_page_swap(PrintPage(_copy_prefix(label, label_len), label_len)))

(* A copy of the page shown's print page's label, with its length *)
fn _print_page_copy (): [label_loc:agz][label_len:nat | label_len <= LABEL_MAX] @($A.arr(byte, label_loc, label_len + 1), int label_len) =
  case+ _print_page_swap(NoPrintPage()) of
  | ~NoPrintPage() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  | ~PrintPage(label, label_len) => let
      val label_copy = _copy_prefix(label, label_len)
      val () = _print_page_free(_print_page_swap(PrintPage(label, label_len)))
    in @(label_copy, label_len) end

(* ============================================================
   Order: by chapter, node, offset
   ============================================================ *)

fn _before (chapter_a: int, node_a: int, offset_a: int, chapter_b: int, node_b: int, offset_b: int): bool =
  if chapter_a <> chapter_b then chapter_a < chapter_b
  else if node_a <> node_b then node_a < node_b
  else offset_a < offset_b

(* annotations with the annotation added in its place *)
fun _insert {count:nat}{text_loc,note_loc,label_loc:agz}{text_len:nat | text_len <= TEXT_MAX}{note_len:nat | note_len <= NOTE_MAX}{label_len:nat | label_len <= LABEL_MAX} .<count>.
  (kind: Int, chapter: Int, start_node: Int, start_offset: Int, end_node: Int, end_offset: Int, page: Int, made_at: Int,
   text: $A.arr(byte, text_loc, text_len + 1), text_len: int text_len, note: $A.arr(byte, note_loc, note_len + 1), note_len: int note_len,
   label: $A.arr(byte, label_loc, label_len + 1), label_len: int label_len,
   annotations: annotations(count)): annotations(count + 1) =
  case+ annotations of
  | ~annotations_nil() => annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, annotations_nil())
  | ~annotations_cons(other_kind, other_chapter, other_start_node, other_start_offset, other_end_node, other_end_offset, other_page, other_made_at, other_text, other_text_len, other_note, other_note_len, other_label, other_label_len, rest) =>
    if _before(chapter, start_node, start_offset, other_chapter, other_start_node, other_start_offset) then
      annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len,
        annotations_cons(other_kind, other_chapter, other_start_node, other_start_offset, other_end_node, other_end_offset, other_page, other_made_at, other_text, other_text_len, other_note, other_note_len, other_label, other_label_len, rest))
    else
      annotations_cons(other_kind, other_chapter, other_start_node, other_start_offset, other_end_node, other_end_offset, other_page, other_made_at, other_text, other_text_len, other_note, other_note_len, other_label, other_label_len,
        _insert(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, rest))

(* ============================================================
   Storage: the book's key 'a' and its id
   ============================================================ *)

(* "QA2\n", then each annotation: its eight numbers (i32), its text
   (u16 length, bytes), its note (u16 length, bytes) and its print
   page's label (u8 length, bytes): at most STORED_MAX bytes. "QA1"
   (written before print pages were kept) is the same without the
   label *)

fun _put_bytes {source_loc,out_loc:agz}{arena:addr}{source_size:pos}{count:nat | count <= source_size}{out_size:nat}{position:nat | position + count <= out_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arrx(byte, out_loc, out_size, arena), position: int position, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.write_byte(out, position + j, $AR.low_byte(byte2int0($A.get<byte>(source, j))))
  in _put_bytes(source, count, out, position, j + 1) end

fun _serialize {l:agz}{arena:addr}{n:int}{count:nat}{position:nat | position + STORED_MAX * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, arena), position: int position, annotations: !annotations(count)): [next:nat | next <= n] int next =
  case+ annotations of
  | annotations_nil() => position
  | @annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, rest) => let
      val () = $A.write_i32(out, position, kind)
      val () = $A.write_i32(out, position + 4, chapter)
      val () = $A.write_i32(out, position + 8, start_node)
      val () = $A.write_i32(out, position + 12, start_offset)
      val () = $A.write_i32(out, position + 16, end_node)
      val () = $A.write_i32(out, position + 20, end_offset)
      val () = $A.write_i32(out, position + 24, page)
      val () = $A.write_i32(out, position + 28, made_at)
      val () = $A.write_u16le(out, position + 32, text_len)
      val () = _put_bytes(text, text_len, out, position + 34, 0)
      val () = $A.write_u16le(out, position + 34 + text_len, note_len)
      val () = _put_bytes(note, note_len, out, position + 36 + text_len, 0)
      val label_at = position + 36 + text_len + note_len
      val () = $A.write_byte(out, label_at, label_len)
      val () = _put_bytes(label, label_len, out, label_at + 1, 0)
      val next = _serialize(out, label_at + 1 + label_len, rest)
      prval () = fold@(annotations)
    in next end

fn _key (): [l:agz] $A.arr(byte, l, 15) = lib_key(97, !_book_id_high, !_book_id_low)

(* Stores annotations under the key of book id_high, id_low *)
fn _store {count:nat | count <= ANNOTATIONS_MAX} (id_high: int, id_low: int, annotations: !annotations(count), count: int count): void = let
  val piece_size = 4 + STORED_MAX * count
in
  case+ piece_new(piece_size) of
  | ~NoPiece() => ()
  | ~Piece(owner, out) => let
      val () = $A.write_text(out, 0, $A.text_lit("QA2"), 3)
      val () = $A.write_byte(out, 3, 10)
      val used_len = _serialize(out, 4, annotations)
      val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(out_frozen, out_bytes, used_len)
      val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(97, id_high, id_low))
      val () = $P.discard<Int>($IDB.idb_put(key_bytes, 15, used, used_len))
      val () = release_bytes(key_frozen, key_bytes)
      val out_bytes = $A.borrow_join<byte>(out_frozen, used, rest)
      val () = $A.drop<byte>(out_frozen, out_bytes)
    in piece_free(owner, $A.thaw<byte>(out_frozen)) end
end

fn _save (): void = let
  val cell = _take()
  val+ @AnnotationsCell(annotations, count) = cell
  val () = _store(!_book_id_high, !_book_id_low, annotations, count)
  prval () = fold@(cell)
in _put(cell) end

(* The little-endian numbers at stored[position] *)
fn _read_i32 {l:agz}{arena:addr}{n:nat}{position:nat | position + 4 <= n}
  (stored: !$A.arrx(byte, l, n, arena), position: int position): Int = let
  val byte0 = $AR.low_byte(byte2int0($A.get<byte>(stored, position)))
  val byte1 = $AR.low_byte(byte2int0($A.get<byte>(stored, position + 1)))
  val byte2 = $AR.low_byte(byte2int0($A.get<byte>(stored, position + 2)))
  val byte3 = $AR.low_byte(byte2int0($A.get<byte>(stored, position + 3)))
  val high = (if byte3 < 128 then byte3 else byte3 - 256): [high:int | ~128 <= high; high < 128] int high
in byte0 + byte1 * 256 + byte2 * 65536 + high * 16777216 end

fn _read_u16 {l:agz}{arena:addr}{n:nat}{position:nat | position + 2 <= n}
  (stored: !$A.arrx(byte, l, n, arena), position: int position): [value:nat | value < 65536] int value = let
  val byte0 = $AR.low_byte(byte2int0($A.get<byte>(stored, position)))
  val byte1 = $AR.low_byte(byte2int0($A.get<byte>(stored, position + 1)))
in byte0 + byte1 * 256 end

(* out[j, count) := stored[position + j, position + count) *)
fun _bytes_of {stored_loc:agz}{arena:addr}{stored_size:nat}{position,count:nat | position + count <= stored_size}{out_loc:agz}{out_size:pos | count <= out_size}{j:nat | j <= count} .<count - j>.
  (stored: !$A.arrx(byte, stored_loc, stored_size, arena), position: int position, count: int count, out: !$A.arr(byte, out_loc, out_size), j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(stored, position + j))
  in _bytes_of(stored, position, count, out, j + 1) end

(* The version of the record stored[0, n): 2 ("QA2", with print pages),
   1 ("QA1", without), or 0 when it is neither *)
fn _version {l:agz}{arena:addr}{n:nat} (stored: !$A.arrx(byte, l, n, arena), n: int n): [version:nat | version <= 2; version == 0 || n >= 4] int version =
  if n < 4 then 0
  else if byte2int0($A.get<byte>(stored, 0)) <> 81 then 0
  else if byte2int0($A.get<byte>(stored, 1)) <> 65 then 0
  else let
    val digit = byte2int0($A.get<byte>(stored, 2))
  in if digit = 50 then 2 else if digit = 49 then 1 else 0 end

(* The print page's label of the annotation whose label is stored at
   stored[position] in a record of version version (none in a "QA1"
   record): whether it is there whole, where its bytes start and its
   length *)
fn _stored_label {l:agz}{arena:addr}{n:nat}{position:nat | position <= n}
  (stored: !$A.arrx(byte, l, n, arena), n: int n, position: int position, version: int)
  : [bytes_at:nat | position <= bytes_at][label_len:nat | label_len <= LABEL_MAX; bytes_at + label_len <= n] @(bool, int bytes_at, int label_len) =
  if version < 2 then @(true, position, 0)
  else if position + 1 > n then @(false, position, 0)
  else let
    val label_len = $AR.low_byte(byte2int0($A.get<byte>(stored, position)))
  in
    if label_len > LABEL_MAX then @(false, position, 0)
    else if position + 1 + label_len > n then @(false, position, 0)
    else @(true, position + 1, label_len)
  end

(* The annotations stored in stored[position, n), a record of version
   version, onto annotations: read as they were stored (the book's
   data, checked here once) *)
fun _parse {l:agz}{arena:addr}{n:nat}{position:nat | position <= n}{count:nat | count <= ANNOTATIONS_MAX} .<n - position>.
  (stored: !$A.arrx(byte, l, n, arena), n: int n, position: int position, version: int, annotations: annotations(count), count: int count)
  : [total:nat | total <= ANNOTATIONS_MAX] @(annotations(total), int total) =
  if count >= ANNOTATIONS_MAX then @(annotations, count)
  else if position + 36 > n then @(annotations, count)
  else let
    val text_len = _read_u16(stored, position + 32)
  in
    if text_len > TEXT_MAX then @(annotations, count)
    else if position + 36 + text_len > n then @(annotations, count)
    else let
      val note_len = _read_u16(stored, position + 34 + text_len)
    in
      if note_len > NOTE_MAX then @(annotations, count)
      else if position + 36 + text_len + note_len > n then @(annotations, count)
      else let
        val label_at = position + 36 + text_len + note_len
        val @(whole, label_bytes_at, label_len) = _stored_label(stored, n, label_at, version)
      in
        if ~whole then @(annotations, count)
        else let
          val text = $A.alloc<byte>(text_len + 1)
          val () = _bytes_of(stored, position + 34, text_len, text, 0)
          val note = $A.alloc<byte>(note_len + 1)
          val () = _bytes_of(stored, position + 36 + text_len, note_len, note, 0)
          val label = $A.alloc<byte>(label_len + 1)
          val () = _bytes_of(stored, label_bytes_at, label_len, label, 0)
          val added = _insert(_read_i32(stored, position), _read_i32(stored, position + 4), _read_i32(stored, position + 8), _read_i32(stored, position + 12),
                        _read_i32(stored, position + 16), _read_i32(stored, position + 20), _read_i32(stored, position + 24), _read_i32(stored, position + 28),
                        text, text_len, note, note_len, label, label_len, annotations)
        in _parse(stored, n, label_bytes_at + label_len, version, added, count + 1) end
      end
    end
  end

(* Reads the annotations of the book whose id is id_high, id_low *)
#pub fn annot_load (id_high: int, id_low: int): $P.promise(int, $P.Chained)

implement annot_load (id_high, id_low) = let
  val () = !_book_id_high := id_high
  val () = !_book_id_low := id_low
  val () = _put(AnnotationsCell(annotations_nil(), 0))
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_key())
  val loaded = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<Int><int>($P.vow(loaded), lam(handle) =>
    case+ take_content(handle) of
    | ~NoContentBytes() => $P.ret<int>(0)
    | ~ContentBytes(owner, stored, stored_size) =>
      let
        val version = _version(stored, stored_size)
      in
      if version = 0 then let val () = piece_free(owner, stored) in $P.ret<int>(0) end
      else let
        val @(annotations, count) = _parse(stored, stored_size, 4, version, annotations_nil(), 0)
        val () = piece_free(owner, stored)
        (* only while the same book is open *)
      in
        if !_book_id_high = id_high then (if !_book_id_low = id_low then let
            val () = _put(AnnotationsCell(annotations, count))
          in $P.ret<int>(count) end
          else let val () = annotations_free(annotations) in $P.ret<int>(0) end)
        else let val () = annotations_free(annotations) in $P.ret<int>(0) end
      end
      end)
end

(* ============================================================
   In the reader
   ============================================================ *)

(* Marks the highlights of chapter shown_chapter *)
fun _marks {count:nat} .<count>. (annotations: !annotations(count), shown_chapter: int): void =
  case+ annotations of
  | annotations_nil() => ()
  | @annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, _, _, _, _, _, _, _, _, rest) => let
      val () = (if _is_highlight(kind) then (if chapter = shown_chapter then
        (if start_node >= 0 then (if end_node >= 0 then let
           val @(start_id, start_id_len) = nid_pad3("c", start_node)
           val @(end_id, end_id_len) = nid_pad3("c", end_node)
           val @(start_frozen, start_bytes) = $A.freeze<byte>(start_id)
           val @(end_frozen, end_bytes) = $A.freeze<byte>(end_id)
           val () = $BDOM.mark_range(_mark_set(kind), start_bytes, start_id_len, start_offset, end_bytes, end_id_len, end_offset)
           val () = release_bytes(end_frozen, end_bytes)
         in release_bytes(start_frozen, start_bytes) end else ()) else ()) else ()) else ())
      val () = _marks(rest, shown_chapter)
      prval () = fold@(annotations)
    in end

(* The chapter the reader is in (from 0) *)
fn _chapter (): [chapter:nat] int chapter =
  case+ reading_get() of @(_, _, chapter, _) => (if chapter > 0 then chapter - 1 else 0)

(* Shows the highlights of the chapter shown *)
#pub fn annot_marks (): void

implement annot_marks () = let
  val () = $BDOM.clear_marks(1)
  val () = $BDOM.clear_marks(3)
  val () = $BDOM.clear_marks(4)
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val () = _marks(annotations, _chapter())
  prval () = fold@(cell)
in _put(cell) end

(* Whether content node node is on the page shown (the page measures 1
   for an element, and 0 for a number with no element, which is on no
   page) *)
fn _on_page (node: Int): bool =
  if node < 0 then false
  else let
    val @(node_id, node_id_len) = nid_pad3("c", node)
    val @(node_frozen, node_bytes) = $A.freeze<byte>(node_id)
    val measured = $DR.measure(node_bytes, node_id_len)
    val () = release_bytes(node_frozen, node_bytes)
  in
    case+ measured of
    | ~$R.err(_) => false
    | ~$R.ok(found) => if found <= 0 then false else let
        val node_x = $DR.get_measure_x()
        val () = ui_measure("page")
        val page_x = $DR.get_measure_x()
        val page_width = $DR.get_measure_w()
      in if node_x >= page_x then node_x < page_x + page_width else false end
  end

(* The page shown *)
fn _page (): int = case+ reading_get() of @(page, _, _, _) => page

(* The index of the bookmark of the page shown, or -1 *)
fun _bookmark_here {count:nat} .<count>. (annotations: !annotations(count), shown_chapter: int, i: int): int =
  case+ annotations of
  | annotations_nil() => ~1
  | @annotations_cons(kind, chapter, start_node, _, _, _, page, _, _, _, _, _, _, _, rest) =>
    if (if kind = 0 then (if chapter = shown_chapter then (if start_node >= 0 then _on_page(start_node) else page = _page()) else false) else false) then let
      prval () = fold@(annotations)
    in i end
    else let
      val found = _bookmark_here(rest, shown_chapter, i + 1)
      prval () = fold@(annotations)
    in found end

fn _here (): int = let
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val found = _bookmark_here(annotations, _chapter(), 0)
  prval () = fold@(cell)
  val () = _put(cell)
in found end

(* The bookmark button: filled when the page shown has a bookmark *)
#pub fn annot_star (): void

implement annot_star () =
  if _here() >= 0 then let
    val () = ui_text("bookmark-button", "\xE2\x98\x85")
  in ui_attr("bookmark-button", APressed, "true") end
  else let
    val () = ui_text("bookmark-button", "\xE2\x98\x86")
  in ui_attr("bookmark-button", APressed, "false") end

(* annotations without its i-th annotation *)
fun _remove {count:nat} .<count>. (annotations: annotations(count), i: int): [kept_count:nat | kept_count <= count] @(annotations(kept_count), int kept_count) =
  case+ annotations of
  | ~annotations_nil() => @(annotations_nil(), 0)
  | ~annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, rest) =>
    if i = 0 then let
      val () = $A.free<byte>(text)
      val () = $A.free<byte>(note)
      val () = $A.free<byte>(label)
      val @(kept, kept_count) = _count(rest)
    in @(kept, kept_count) end
    else let
      val @(kept, kept_count) = _remove(rest, i - 1)
    in @(annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, kept), kept_count + 1) end

and _count {count:nat} .<count>. (annotations: annotations(count)): @(annotations(count), int count) =
  case+ annotations of
  | ~annotations_nil() => @(annotations_nil(), 0)
  | ~annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, rest) => let
      val @(counted, rest_count) = _count(rest)
    in @(annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, counted), rest_count + 1) end

fn _delete (index: int): void = let
  val+ ~AnnotationsCell(annotations, _) = _take()
  val @(kept, kept_count) = _remove(annotations, index)
  val () = _put(AnnotationsCell(kept, kept_count))
in _save() end

(* out[0, count) := the blob's first count bytes *)
fn _blob_read {blob_size:nat}{l:agz}{n:pos}{count:nat | count <= blob_size; count <= n} (blob: !$BD.dblob(blob_size), out: !$A.arr(byte, l, n), count: int count): void =
  if count > 0 then $DC.blob_read(blob, 0, out, count) else ()

(* text_len, or less, so that text[0, text_len) ends before a
   character's start *)
fn _utf8_cut {l:agz}{n:pos}{text_len:nat | text_len < n} (text: !$A.arr(byte, l, n), text_len: int text_len): [cut_len:nat | cut_len <= text_len] int cut_len =
  if text_len <= 0 then 0
  else if $AR.band_int_int(byte2int0($A.get<byte>(text, text_len)), 192) <> 128 then text_len
  else if text_len >= 2 then (if $AR.band_int_int(byte2int0($A.get<byte>(text, text_len - 1)), 192) <> 128 then text_len - 1
    else if $AR.band_int_int(byte2int0($A.get<byte>(text, text_len - 2)), 192) <> 128 then text_len - 2
    else if text_len >= 3 then text_len - 3 else 0)
  else 0

(* The first bytes of a blob's text (at most most of them, cut before
   a UTF-8 character's start) in a new array of most + 1 bytes, with
   their count *)
fn _blob_text {blob_size:nat}{most:pos | most <= 2000} (blob: $BD.dblob(blob_size), most: int most): [l:agz][text_len:nat | text_len <= most] @($A.arr(byte, l, most + 1), int text_len) = let
  val blob_len = $DC.blob_len(blob)
  val read_len = (if blob_len < most then blob_len else most): [read_len:nat | read_len <= most; read_len <= blob_size] int read_len
  val text = $A.alloc<byte>(most + 1)
  val () = _blob_read(blob, text, read_len)
  val () = $DC.blob_free(blob)
  val text_len = _utf8_cut(text, read_len)
in @(text, text_len) end

(* The first words of content node node *)
fn _node_words (node: Int): [l:agz][words_len:nat | words_len <= 120] @($A.arr(byte, l, 121), int words_len) =
  if node < 0 then let val empty = $A.alloc<byte>(121) in @(empty, 0) end
  else let
    val @(node_id, node_id_len) = nid_pad3("c", node)
    val @(node_frozen, node_bytes) = $A.freeze<byte>(node_id)
    val content = $DR.read_text_content(node_bytes, node_id_len)
    val () = release_bytes(node_frozen, node_bytes)
  in
    case+ content of
    | ~$R.none() => let val empty = $A.alloc<byte>(121) in @(empty, 0) end
    | ~$R.some(blob) => _blob_text(blob, 120)
  end

fn _add {text_loc,note_loc:agz}{text_len:nat | text_len <= TEXT_MAX}{note_len:nat | note_len <= NOTE_MAX}
  (kind: Int, chapter: Int, start_node: Int, start_offset: Int, end_node: Int, end_offset: Int, page: Int,
   text: $A.arr(byte, text_loc, text_len + 1), text_len: int text_len, note: $A.arr(byte, note_loc, note_len + 1), note_len: int note_len): void = let
  val+ ~AnnotationsCell(annotations, count) = _take()
in
  if count >= ANNOTATIONS_MAX then let
    val () = $A.free<byte>(text)
    val () = $A.free<byte>(note)
  in _put(AnnotationsCell(annotations, count)) end
  else let
    (* made on the page shown, it keeps that page's print page *)
    val @(label, label_len) = _print_page_copy()
    val () = _put(AnnotationsCell(_insert(kind, chapter, start_node, start_offset, end_node, end_offset, page, $TM.epoch_minutes(), text, text_len, note, note_len, label, label_len, annotations), count + 1))
  in _save() end
end

(* The page shown's bookmark: removed when it has one, else added, at
   content node anchor (the page's top) *)
#pub fn annot_bookmark_toggle (anchor: Int): void

implement annot_bookmark_toggle (anchor) = let
  val index = _here()
in
  if index >= 0 then let
    val () = _delete(index)
  in annot_star() end
  else let
    val page = (case+ reading_get() of @(shown_page, _, _, _) => shown_page): Int
    val @(words, words_len) = _node_words(anchor)
    val words_copy = _copy_prefix(words, words_len)
    val () = $A.free<byte>(words)
    val () = _add(0, _chapter(), anchor, 0, anchor, 0, page, words_copy, words_len, $A.alloc<byte>(1), 0)
  in annot_star() end
end

(* The number of a content node id id[0, id_len) ("c" and digits), or
   -1 *)
fn _node_number {blob_size:nat} (blob: $BD.dblob(blob_size)): [number:int | number >= ~1] int number = let
  val id_len = $DC.blob_len(blob)
in
  if id_len <= 1 then let val () = $DC.blob_free(blob) in ~1 end
  else if id_len > 16 then let val () = $DC.blob_free(blob) in ~1 end
  else let
    val id = $A.alloc<byte>(id_len)
    val () = $DC.blob_read(blob, 0, id, id_len)
    val () = $DC.blob_free(blob)
    val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
    val number = nid_parse(id_bytes, id_len, 0, "c")
    val () = release_bytes(id_frozen, id_bytes)
  in number end
end

fn _node_number_of (selected: $R.option([blob_size:nat] $BD.dblob(blob_size))): [number:int | number >= ~1] int number =
  case+ selected of
  | ~$R.none() => ~1
  | ~$R.some(blob) => _node_number(blob)

(* The index of the annotation at chapter chapter, node start_node,
   offset start_offset *)
fn _index_of (chapter: Int, start_node: Int, start_offset: Int): int = let
  fun find {count:nat} .<count>. (annotations: !annotations(count), i: int): int =
    case+ annotations of
    | annotations_nil() => ~1
    | @annotations_cons(_, entry_chapter, node, offset, _, _, _, _, _, _, _, _, _, _, rest) =>
      if (if entry_chapter = chapter then (if node = start_node then offset = start_offset else false) else false) then let
        prval () = fold@(annotations)
      in i end
      else let
        val found = find(rest, i + 1)
        prval () = fold@(annotations)
      in found end
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val found = find(annotations, 0)
  prval () = fold@(cell)
  val () = _put(cell)
in found end

(* The selection, as a highlight of the chapter shown in style (0
   yellow, 1 orange, 2 underlined): its index, or -1 when nothing is
   selected in the chapter's text *)
#pub fn annot_highlight {style:nat | style <= 2} (style: int style): int

implement annot_highlight (style) = let
  val @(start_blob, end_blob) = $DR.get_selection_range()
  val start_offset = $DR.get_measure_x()
  val end_offset = $DR.get_measure_y()
  val start_node = _node_number_of(start_blob)
  val end_node = _node_number_of(end_blob)
in
  if start_node < 0 then ~1
  else if end_node < 0 then ~1
  else if (if start_node = end_node then start_offset >= end_offset else start_node > end_node) then ~1
  else (case+ $DR.get_selection_text() of
    | ~$R.none() => ~1
    | ~$R.some(blob) => let
        val @(selected, text_len) = _blob_text(blob, TEXT_MAX)
        val text = _copy_prefix(selected, text_len)
        val () = $A.free<byte>(selected)
        val chapter = _chapter()
        val page = (case+ reading_get() of @(shown_page, _, _, _) => shown_page): Int
        val () = _add(1 + style, chapter, start_node, start_offset, end_node, end_offset, page, text, text_len, $A.alloc<byte>(1), 0)
        val () = annot_marks()
      in _index_of(chapter, start_node, start_offset) end)
end

(* ============================================================
   Notes
   ============================================================ *)

fun _set_note {count:nat}{l:agz}{note_len:nat | note_len <= NOTE_MAX} .<count>.
  (annotations: !annotations(count), i: int, note: $A.arr(byte, l, note_len + 1), note_len: int note_len): void =
  case+ annotations of
  | annotations_nil() => $A.free<byte>(note)
  | @annotations_cons(_, _, _, _, _, _, _, _, _, _, old_note, old_note_len, _, _, rest) =>
    if i = 0 then let
      val () = $A.free<byte>(old_note)
      val () = old_note := note
      val () = old_note_len := note_len
      prval () = fold@(annotations)
    in end
    else let
      val () = _set_note(rest, i - 1, note, note_len)
      prval () = fold@(annotations)
    in end

(* How much of text[0, text_len) a note keeps: all of it, or its first
   NOTE_MAX bytes (fewer, not to cut a character) *)
fn _note_len {l:agz}{n:pos}{text_len:nat | text_len <= n} (text: !$A.arr(byte, l, n), text_len: int text_len): [kept:nat | kept <= text_len; kept <= NOTE_MAX] int kept =
  if text_len <= NOTE_MAX then text_len else _utf8_cut(text, NOTE_MAX)

(* The note of annotation index: text[0, text_len), at most NOTE_MAX
   bytes of it *)
#pub fn annot_note_set {l:agz}{n:pos}{text_len:nat | text_len <= n} (index: int, text: $A.arr(byte, l, n), text_len: int text_len): void

implement annot_note_set (index, text, text_len) = let
  val note_len = _note_len(text, text_len)
  val note = $A.alloc<byte>(note_len + 1)
  val () = _copy_bytes(text, note, note_len, 0)
  val () = $A.free<byte>(text)
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val () = _set_note(annotations, index, note, note_len)
  prval () = fold@(cell)
  val () = _put(cell)
in _save() end

fun _note_at {count:nat} .<count>. (annotations: !annotations(count), i: int): [l:agz][note_len:nat | note_len <= NOTE_MAX] @($A.arr(byte, l, note_len + 1), int note_len) =
  case+ annotations of
  | annotations_nil() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  | @annotations_cons(_, _, _, _, _, _, _, _, _, _, note, note_len, _, _, rest) =>
    if i = 0 then let
      val note_copy = _copy_prefix(note, note_len)
      val copy_len = note_len
      prval () = fold@(annotations)
    in @(note_copy, copy_len) end
    else let
      val found = _note_at(rest, i - 1)
      prval () = fold@(annotations)
    in found end

(* The note of annotation index, in the dialog's text area *)
#pub fn annot_note_show (index: int): void

implement annot_note_show (index) = let
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val @(note, note_len) = _note_at(annotations, index)
  prval () = fold@(cell)
  val () = _put(cell)
in ui_text_buf("dialog-note", note, note_len) end

(* Deletes annotation index. Private: outside this module an annotation
   goes only by annot_delete_highlight or annot_delete_bookmark, which
   offer it back, or as the no of a note begun from a selection
   (annot_ask_note) *)
fn _drop (index: int): void = let
  val () = _delete(index)
  val () = annot_marks()
in annot_star() end

(* An annotation taken out of the list, kept while its removal can be
   undone: the offer's number, then the annotation as annotations_cons
   holds it *)
datavtype removed =
  | NoRemoved of ()
  | {text_loc,note_loc,label_loc:agz}{text_len:nat | text_len <= TEXT_MAX}{note_len:nat | note_len <= NOTE_MAX}{label_len:nat | label_len <= LABEL_MAX}
    Removed of (int, Int, Int, Int, Int, Int, Int, Int, Int,
      $A.arr(byte, text_loc, text_len + 1), int text_len, $A.arr(byte, note_loc, note_len + 1), int note_len,
      $A.arr(byte, label_loc, label_len + 1), int label_len)

fn _removed_free (held: removed): void =
  case+ held of
  | ~NoRemoved() => ()
  | ~Removed(_, _, _, _, _, _, _, _, _, text, _, note, _, label, _) => let
      val () = $A.free<byte>(text)
      val () = $A.free<byte>(note)
    in $A.free<byte>(label) end

val _held = ref<removed>(NoRemoved())
val _held_serial = ref<int>(0)

fn _held_swap (held: removed): removed = let
  var previous: removed = held
  val () = ref_exch_elt<removed>(_held, previous)
in previous end

(* annotations without its i-th annotation, which is returned (numbered
   offer) *)
fun _pull {count:nat} .<count>. (annotations: annotations(count), i: int, offer: int): [kept_count:nat | kept_count <= count] @(annotations(kept_count), int kept_count, removed) =
  case+ annotations of
  | ~annotations_nil() => @(annotations_nil(), 0, NoRemoved())
  | ~annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, rest) =>
    if i = 0 then let
      val @(kept, kept_count) = _count(rest)
    in @(kept, kept_count, Removed(offer, kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len)) end
    else let
      val @(kept, kept_count, pulled) = _pull(rest, i - 1, offer)
    in @(annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, kept), kept_count + 1, pulled) end

(* The annotation held under number offer, put back in its place *)
fn _put_back (offer: int): void =
  case+ _held_swap(NoRemoved()) of
  | ~NoRemoved() => ()
  | ~Removed(held_offer, kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len) =>
    if held_offer <> offer then _removed_free(_held_swap(Removed(held_offer, kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len)))
    else let
      val+ ~AnnotationsCell(annotations, count) = _take()
    in
      if count >= ANNOTATIONS_MAX then let
        val () = $A.free<byte>(text)
        val () = $A.free<byte>(note)
        val () = $A.free<byte>(label)
      in _put(AnnotationsCell(annotations, count)) end
      else let
        val () = _put(AnnotationsCell(_insert(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, annotations), count + 1))
        val () = _save()
        val () = annot_marks()
      in annot_star() end
    end

(* The annotation held under number offer, let go of *)
fn _let_go (offer: int): void =
  case+ _held_swap(NoRemoved()) of
  | ~NoRemoved() => ()
  | ~Removed(held_offer, kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len) =>
    if held_offer <> offer then _removed_free(_held_swap(Removed(held_offer, kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len)))
    else let
      val () = $A.free<byte>(text)
      val () = $A.free<byte>(note)
    in $A.free<byte>(label) end

(* Deletes annotation index at once, offering it back: Undo puts it
   back, and then again runs shown (which shows the list it was in) *)
fn _delete_undoable {text_len:pos | text_len < 256} (index: int, text: string text_len, shown: () -<cloref1> void): void = let
  val offer = !_held_serial + 1
  val () = !_held_serial := offer
  val+ ~AnnotationsCell(annotations, _) = _take()
  val @(kept, kept_count, pulled) = _pull(annotations, index, offer)
  val () = _put(AnnotationsCell(kept, kept_count))
  val () = _save()
  val () = annot_marks()
  val () = annot_star()
  val () = _removed_free(_held_swap(pulled))
  val () = shown()
in undo_offer(text, lam () => let val () = _put_back(offer) in shown() end, lam () => _let_go(offer)) end

(* Deletes highlight index, offering Undo *)
#pub fn annot_delete_highlight {index:int} (index: int index): void

implement annot_delete_highlight (index) =
  _delete_undoable(index, "Highlight deleted", lam () => annot_render())

(* Deletes bookmark index, offering Undo *)
#pub fn annot_delete_bookmark {index:int} (index: int index): void

implement annot_delete_bookmark (index) =
  _delete_undoable(index, "Bookmark deleted", lam () => annot_render_bookmarks())

(* Both lists, after a note changed: the highlights' and the bookmarks' *)
fn _lists_render (): void = let
  val () = annot_render()
in annot_render_bookmarks() end

(* The note in the dialog's text area, kept as annotation index's *)
fn _note_save (index: int): void = let
  val id = $A.alloc<byte>(11)
  val () = $A.write_text(id, 0, $A.text_lit("dialog-note"), 11)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val value = $DR.read_input_value(id_bytes, 11)
  val () = release_bytes(id_frozen, id_bytes)
in
  case+ value of
  | ~$R.none() => let
      val empty = $A.alloc<byte>(1)
      val () = annot_note_set(index, empty, 0)
    in _lists_render() end
  | ~$R.some(blob) => let
      val value_len = $DC.blob_len(blob)
    in
      if value_len <= 0 then let
        val () = $DC.blob_free(blob)
        val empty = $A.alloc<byte>(1)
        val () = annot_note_set(index, empty, 0)
      in _lists_render() end
      else if value_len > 65536 then let
        val () = $DC.blob_free(blob)
      in end
      else let
        val value_bytes = $A.alloc<byte>(value_len)
        val () = $DC.blob_read(blob, 0, value_bytes, value_len)
        val () = $DC.blob_free(blob)
        val () = annot_note_set(index, value_bytes, value_len)
      in _lists_render() end
    end
end

(* The note dialog for annotation index: Save keeps the note. When
   fresh, the highlight was made for this note (from a selection), and
   cancelling it (by button, Escape or a click outside) takes the
   highlight away again *)
#pub fn annot_ask_note (index: int, fresh: bool): void

implement annot_ask_note (index, fresh) =
  if index < 0 then ()
  else let
    val () = modal_open(QNote(), "Note", lam () => _note_save(index),
      lam () => if fresh then let val () = _drop(index) in _lists_render() end else ())
    val () = modal_textarea()
  in annot_note_show(index) end

(* ============================================================
   Where one leads
   ============================================================ *)

fun _dest_at {count:nat} .<count>. (annotations: !annotations(count), i: int): @(Int, Int, Int) =
  case+ annotations of
  | annotations_nil() => @(~1, 0, ~1)
  | @annotations_cons(_, chapter, start_node, _, _, _, page, _, _, _, _, _, _, _, rest) =>
    if i = 0 then let
      val dest_chapter = chapter
      val dest_page = page
      val dest_node = start_node
      prval () = fold@(annotations)
    in @((if dest_chapter >= 0 then dest_chapter else 0), (if dest_page >= 0 then dest_page else 0), (if dest_node >= 0 then dest_node else ~1)) end
    else let
      val found = _dest_at(rest, i - 1)
      prval () = fold@(annotations)
    in found end

(* Annotation index's chapter, page and content node; a chapter of -1
   when there is no annotation index *)
#pub fn annot_dest (index: int): @(Int, Int, Int)

implement annot_dest (index) = let
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val dest = _dest_at(annotations, index)
  prval () = fold@(cell)
  val () = _put(cell)
in dest end

(* ============================================================
   The lists
   ============================================================ *)

(* A child element of numbered parent parent_prefix<i>, numbered
   child_prefix<i> *)
fn _child {parent_prefix_len,child_prefix_len:pos | parent_prefix_len <= 16; child_prefix_len <= 16}{i:nat}{class_len:pos | class_len < 256}
  (parent_prefix: string parent_prefix_len, child_prefix: string child_prefix_len, i: int i, element_tag: tag, class_name: string class_len): void = let
  val @(parent_id, parent_id_len) = nid_make(parent_prefix, i)
  val @(child_id, child_id_len) = nid_make(child_prefix, i)
  val () = ui_add_nn(parent_id, parent_id_len, child_id, child_id_len, element_tag)
  val @(child_id, child_id_len) = nid_make(child_prefix, i)
in ui_attr_n(child_id, child_id_len, AClass, class_name) end

(* A button child named by what is put in it *)
fn _child_button {parent_prefix_len,child_prefix_len:pos | parent_prefix_len <= 16; child_prefix_len <= 16}{i:nat}{class_len:pos | class_len < 256}
  (parent_prefix: string parent_prefix_len, child_prefix: string child_prefix_len, i: int i, class_name: string class_len): void = let
  val @(parent_id, parent_id_len) = nid_make(parent_prefix, i)
  val @(child_id, child_id_len) = nid_make(child_prefix, i)
in ui_btn_nn(parent_id, parent_id_len, child_id, child_id_len, class_name) end

(* A button child named by its label *)
fn _child_text_button {parent_prefix_len,child_prefix_len:pos | parent_prefix_len <= 16; child_prefix_len <= 16}{i:nat}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}
  (parent_prefix: string parent_prefix_len, child_prefix: string child_prefix_len, i: int i, class_name: string class_len, label: string label_len): void = let
  val @(parent_id, parent_id_len) = nid_make(parent_prefix, i)
  val @(child_id, child_id_len) = nid_make(child_prefix, i)
in ui_text_btn_nn(parent_id, parent_id_len, child_id, child_id_len, class_name, label) end

(* Element id_prefix<i>'s text: text[0, text_len) *)
fn _text_of {id_prefix_len:pos | id_prefix_len <= 16}{i:nat}{l:agz}{n:pos}{text_len:nat | text_len < n; text_len < 65536}
  (id_prefix: string id_prefix_len, i: int i, text: !$A.arr(byte, l, n), text_len: int text_len): void = let
  val text_copy = $A.alloc<byte>(text_len + 1)
  val () = _copy_bytes(text, text_copy, text_len, 0)
  val @(element_id, element_id_len) = nid_make(id_prefix, i)
in ui_text_n_buf(element_id, element_id_len, text_copy, text_len) end

(* The heading of chapter chapter's annotations, in the list list_id *)
fn _heading {list_id_len:pos | list_id_len < 256}{chapter:nat} (list_id: string list_id_len, chapter: int chapter): void = let
  val @(group_id, group_id_len) = nid_make("annot-group", chapter)
  val () = ui_add_n(list_id, group_id, group_id_len, TDiv)
  val @(group_id, group_id_len) = nid_make("annot-group", chapter)
  val () = ui_attr_n(group_id, group_id_len, AClass, "grp")
  val @(label_bytes, label_len) = toc_label_of(chapter)
  val @(group_id, group_id_len) = nid_make("annot-group", chapter)
in ui_text_n_buf(group_id, group_id_len, label_bytes, label_len) end

(* One row of the annotations list: highlight i *)
fn _highlight_row {i:nat}{style:nat | style <= 2}{text_loc,note_loc:agz}{text_size,note_size:pos}{text_len:nat | text_len < text_size; text_len < 65536}{note_len:nat | note_len < note_size; note_len < 65536}
  (i: int i, style: int style, text: !$A.arr(byte, text_loc, text_size), text_len: int text_len, note: !$A.arr(byte, note_loc, note_size), note_len: int note_len): void = let
  val @(row_id, row_id_len) = nid_make("highlight-row", i)
  val () = ui_add_n("annotations-list", row_id, row_id_len, TDiv)
  val @(row_id, row_id_len) = nid_make("highlight-row", i)
  val () = ui_attr_n(row_id, row_id_len, AClass, "hrow")
  val () = _child_button("highlight-row", "highlight-go", i, "hgo")
  (* its style, in words (not by colour alone), then its quote as it
     is marked on the page *)
  val () = _child("highlight-go", "highlight-style", i, TSpan, "hstyle")
  val @(style_id, style_id_len) = nid_make("highlight-style", i)
  val () = (if style = 1 then ui_text_n(style_id, style_id_len, "Orange")
    else if style = 2 then ui_text_n(style_id, style_id_len, "Underlined")
    else ui_text_n(style_id, style_id_len, "Yellow"))
  val () = (if style = 1 then _child("highlight-go", "highlight-quote", i, TSpan, "hq hq-orange")
    else if style = 2 then _child("highlight-go", "highlight-quote", i, TSpan, "hq hq-under")
    else _child("highlight-go", "highlight-quote", i, TSpan, "hq hq-yellow"))
  val () = _text_of("highlight-quote", i, text, text_len)
  val () = (if note_len > 0 then let
      val () = _child("highlight-go", "highlight-note", i, TSpan, "hn")
    in _text_of("highlight-note", i, note, note_len) end else ())
  val () = _child("highlight-row", "highlight-tools", i, TDiv, "hbtns")
  val () = (if note_len > 0 then _child_text_button("highlight-tools", "highlight-edit", i, "hbtn", "Edit note")
    else _child_text_button("highlight-tools", "highlight-edit", i, "hbtn", "Add note"))
in _child_text_button("highlight-tools", "highlight-delete", i, "hbtn", "Delete") end

(* The style the annotations list shows: -1 every one, else 0 yellow,
   1 orange, 2 underlined *)
val _filter = ref<int>(~1)

(* Whether a highlight of kind kind is listed *)
fn _listed (kind: int): bool =
  if ~_is_highlight(kind) then false
  else if !_filter < 0 then true
  else _style_of(kind) = !_filter

fun _highlight_rows {count:nat}{i:nat} .<count>. (annotations: !annotations(count), i: int i, last_chapter: Int): int =
  case+ annotations of
  | annotations_nil() => i
  | @annotations_cons(kind, chapter, _, _, _, _, _, _, text, text_len, note, note_len, _, _, rest) => let
      val shown = _listed(kind)
      val () = (if shown then let
          val () = (if chapter <> last_chapter then (if chapter >= 0 then _heading("annotations-list", chapter) else ()) else ())
        in _highlight_row(i, _style_of(kind), text, text_len, note, note_len) end else ())
      val new_last_chapter = (if shown then chapter else last_chapter): Int
      val rows_end = _highlight_rows(rest, i + 1, new_last_chapter)
      prval () = fold@(annotations)
    in rows_end end

(* How many of annotations pass keep *)
fun _count_where {count:nat} .<count>. (annotations: !annotations(count), keep: int -<cloref1> bool): int =
  case+ annotations of
  | annotations_nil() => 0
  | @annotations_cons(kind, _, _, _, _, _, _, _, _, _, _, _, _, _, rest) => let
      val kind_copy = kind
      val counted = _count_where(rest, keep)
      prval () = fold@(annotations)
    in if keep(kind_copy) then counted + 1 else counted end

(* The filter's buttons, pressed as it is *)
fn _pressed {id_len:pos | id_len < 256} (id: string id_len, on: bool): void =
  if on then ui_attr(id, APressed, "true") else ui_attr(id, APressed, "false")

fn _filter_show (): void = let
  val shown_style = !_filter
  val () = _pressed("filter-all", shown_style < 0)
  val () = _pressed("filter-yellow", shown_style = 0)
  val () = _pressed("filter-orange", shown_style = 1)
in _pressed("filter-underlined", shown_style = 2) end

(* The list's message when it shows no highlight *)
fn _annotations_empty {n:pos | n < 256} (message: string n): void = let
  val () = ui_add("annotations-list", "annotations-empty", TDiv)
  val () = ui_class("annotations-empty", "empty")
in ui_text("annotations-empty", message) end

(* Fills the annotations list: the highlights of the style shown, by
   chapter *)
#pub fn annot_render (): void

implement annot_render () = let
  val () = ui_clear("annotations-list")
  val () = _filter_show()
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val highlight_count = _count_where(annotations, lam (kind) => _is_highlight(kind))
  val listed_count = _count_where(annotations, lam (kind) => _listed(kind))
  val _ = _highlight_rows(annotations, 0, ~1)
  prval () = fold@(cell)
  val () = _put(cell)
in
  if highlight_count = 0 then _annotations_empty("No highlights yet. Select text to highlight it.")
  else if listed_count = 0 then _annotations_empty("No highlights in this style.")
  else ()
end

(* Lists only the highlights of style style (0 yellow, 1 orange, 2
   underlined), or every one (-1) *)
#pub fn annot_filter_set (style: int): void

implement annot_filter_set (style) = let
  val () = !_filter := (if style >= 0 then (if style <= 2 then style else ~1) else ~1)
in annot_render() end

(* One row of the bookmarks list: bookmark i *)
fn _bookmark_row {i:nat}{chapter:nat}{text_loc,note_loc:agz}{text_size,note_size:pos}{text_len:nat | text_len < text_size; text_len < 65536}{note_len:nat | note_len < note_size; note_len < 65536}
  (i: int i, chapter: int chapter, text: !$A.arr(byte, text_loc, text_size), text_len: int text_len, note: !$A.arr(byte, note_loc, note_size), note_len: int note_len): void = let
  val @(row_id, row_id_len) = nid_make("bookmark-row", i)
  val () = ui_add_n("bookmarks-list", row_id, row_id_len, TDiv)
  val @(row_id, row_id_len) = nid_make("bookmark-row", i)
  val () = ui_attr_n(row_id, row_id_len, AClass, "hrow")
  val () = _child_button("bookmark-row", "bookmark-go", i, "hgo")
  val () = _child("bookmark-go", "bookmark-title", i, TSpan, "bt")
  val @(label_bytes, label_len) = toc_label_of(chapter)
  val @(title_id, title_id_len) = nid_make("bookmark-title", i)
  val () = ui_text_n_buf(title_id, title_id_len, label_bytes, label_len)
  val () = (if text_len > 0 then let
      val () = _child("bookmark-go", "bookmark-snippet", i, TSpan, "snip")
    in _text_of("bookmark-snippet", i, text, text_len) end else ())
  val () = (if note_len > 0 then let
      val () = _child("bookmark-go", "bookmark-note", i, TSpan, "hn")
    in _text_of("bookmark-note", i, note, note_len) end else ())
  val () = _child("bookmark-row", "bookmark-tools", i, TDiv, "hbtns")
  val () = (if note_len > 0 then _child_text_button("bookmark-tools", "bookmark-edit", i, "hbtn", "Edit note")
    else _child_text_button("bookmark-tools", "bookmark-edit", i, "hbtn", "Add note"))
in _child_text_button("bookmark-tools", "bookmark-delete", i, "hbtn", "Delete") end

fun _bookmark_rows {count:nat}{i:nat} .<count>. (annotations: !annotations(count), i: int i): void =
  case+ annotations of
  | annotations_nil() => ()
  | @annotations_cons(kind, chapter, _, _, _, _, _, _, text, text_len, note, note_len, _, _, rest) => let
      val () = (if kind = 0 then (if chapter >= 0 then _bookmark_row(i, chapter, text, text_len, note, note_len) else ()) else ())
      val () = _bookmark_rows(rest, i + 1)
      prval () = fold@(annotations)
    in end

(* Fills the bookmarks list *)
#pub fn annot_render_bookmarks (): void

implement annot_render_bookmarks () = let
  val () = ui_clear("bookmarks-list")
  val cell = _take()
  val+ @AnnotationsCell(annotations, _) = cell
  val bookmark_count = _count_where(annotations, lam (kind) => kind = 0)
  val () = _bookmark_rows(annotations, 0)
  prval () = fold@(cell)
  val () = _put(cell)
in
  if bookmark_count = 0 then let
    val () = ui_add("bookmarks-list", "bookmarks-empty", TDiv)
    val () = ui_class("bookmarks-empty", "empty")
  in ui_text("bookmarks-empty", "No bookmarks yet. Tap the star to add one.") end
  else ()
end

(* ============================================================
   Export: Markdown
   ============================================================ *)

(* The literal literal at out[position] *)
fun _literal_at {l:agz}{arena:addr}{n:nat}{literal_len:nat}{position:nat | position + literal_len <= n}{j:nat | j <= literal_len} .<literal_len - j>.
  (out: !$A.arrx(byte, l, n, arena), position: int position, literal: string literal_len, literal_len: int literal_len, j: int j): int(position + literal_len) =
  if j >= literal_len then position + literal_len
  else let
    val () = $A.write_byte(out, position + j, $AR.byte_of_char(string_get_at(literal, j)))
  in _literal_at(out, position, literal, literal_len, j + 1) end

fn _literal {l:agz}{arena:addr}{n:nat}{literal_len:nat}{position:nat | position + literal_len <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, literal: string literal_len): int(position + literal_len) =
  _literal_at(out, position, literal, g1u2i(string1_length(literal)), 0)

fn _flat {code:nat | code < 256} (code: int code): [flat:nat | flat < 256] int flat =
  if code = 10 then 32 else if code = 13 then 32 else code

(* source[0, count) at out[position], with its line breaks as spaces *)
fun _flat_at {source_loc,out_loc:agz}{arena:addr}{source_size:pos}{count:nat | count <= source_size}{out_size:nat}{position:nat | position + count <= out_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arrx(byte, out_loc, out_size, arena), position: int position, j: int j): void =
  if j >= count then ()
  else let
    val code = $AR.low_byte(byte2int0($A.get<byte>(source, j)))
    val () = $A.write_byte(out, position + j, _flat(code))
  in _flat_at(source, count, out, position, j + 1) end

fn _markdown_heading {l:agz}{arena:addr}{n:int}{position:nat | position + 206 <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, chapter: Int): [next:nat | position <= next; next <= position + 206] int next =
  if chapter < 0 then position
  else let
    val @(label_bytes, label_len) = toc_label_of(chapter)
    val label_at = _literal(out, position, "### ")
    val () = _flat_at(label_bytes, label_len, out, label_at, 0)
    val () = $A.free<byte>(label_bytes)
  in _literal(out, label_at + label_len, "\n\n") end

fn _markdown_note {out_loc:agz}{arena:addr}{out_size:int}{position:nat | position + 2012 <= out_size}{note_loc:agz}{note_size:pos}{note_len:nat | note_len < note_size; note_len <= NOTE_MAX}
  (out: !$A.arrx(byte, out_loc, out_size, arena), position: int position, note: !$A.arr(byte, note_loc, note_size), note_len: int note_len): [next:nat | position <= next; next <= position + 2012] int next =
  if note_len <= 0 then position
  else let
    val note_at = _literal(out, position, "**Note:** ")
    val () = _flat_at(note, note_len, out, note_at, 0)
  in _literal(out, note_at + note_len, "\n\n") end

fn _markdown_heading_if_new {l:agz}{arena:addr}{n:int}{position:nat | position + 206 <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, chapter: Int, last_chapter: Int): [next:nat | position <= next; next <= position + 206] int next =
  if chapter <> last_chapter then _markdown_heading(out, position, chapter) else position

(* A highlight's style after its quote, unless yellow, the usual one *)
fn _markdown_style {l:agz}{arena:addr}{n:int}{position:nat | position + 22 <= n}{style:nat | style <= 2}
  (out: !$A.arrx(byte, l, n, arena), position: int position, style: int style): [next:nat | position <= next; next <= position + 22] int next =
  if style = 1 then _literal(out, position, "*Orange highlight*\n\n")
  else if style = 2 then _literal(out, position, "*Underlined*\n\n")
  else position

(* The highlights as Markdown at out[position]: each after its chapter's
   heading when it is the chapter's first *)
(* A highlight's source, after its quote: "— Author, *Title*, Chapter,
   page 214", from the book's author author[0, author_len) and title
   title[0, title_len) and the print page the highlight was made on,
   label[0, label_len) (no ", page" when it has none) *)
(* ", Chapter" in a citation, unless the highlight has no chapter *)
fn _cite_chapter {l:agz}{arena:addr}{n:int}{position:nat | position + 202 <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, chapter: Int): [next:nat | position <= next; next <= position + 202] int next =
  if chapter < 0 then position
  else let
    val @(chapter_label, chapter_label_len) = toc_label_of(chapter)
    val chapter_label_at = _literal(out, position, ", ")
    val () = _flat_at(chapter_label, chapter_label_len, out, chapter_label_at, 0)
    val () = $A.free<byte>(chapter_label)
  in chapter_label_at + chapter_label_len end

(* ", page 214" in a citation, from the print page's label
   label[0, label_len); nothing when it has none *)
fn _cite_page {out_loc,label_loc:agz}{arena:addr}{out_size:int}{position:nat | position + 7 + LABEL_MAX <= out_size}{label_size:pos}{label_len:nat | label_len < label_size; label_len <= LABEL_MAX}
  (out: !$A.arrx(byte, out_loc, out_size, arena), position: int position, label: !$A.arr(byte, label_loc, label_size), label_len: int label_len)
  : [next:nat | position <= next; next <= position + 7 + LABEL_MAX] int next =
  if label_len <= 0 then position
  else let
    val label_at = _literal(out, position, ", page ")
    val () = _flat_at(label, label_len, out, label_at, 0)
  in label_at + label_len end

fn _markdown_cite {out_loc,title_loc,author_loc,label_loc:agz}{arena:addr}{out_size:int}{position:nat | position + 750 <= out_size}{title_size,author_size,label_size:pos}{title_len:nat | title_len < title_size; title_len < 256}{author_len:nat | author_len < author_size; author_len < 256}{label_len:nat | label_len < label_size; label_len <= LABEL_MAX}
  (out: !$A.arrx(byte, out_loc, out_size, arena), position: int position, chapter: Int,
   title: !$A.arr(byte, title_loc, title_size), title_len: int title_len, author: !$A.arr(byte, author_loc, author_size), author_len: int author_len,
   label: !$A.arr(byte, label_loc, label_size), label_len: int label_len): [next:nat | position <= next; next <= position + 750] int next = let
  val author_at = _literal(out, position, "\xE2\x80\x94 ")
  val () = _flat_at(author, author_len, out, author_at, 0)
  val title_at = _literal(out, author_at + author_len, ", *")
  val () = _flat_at(title, title_len, out, title_at, 0)
  val after_title = _literal(out, title_at + title_len, "*")
  val after_chapter = _cite_chapter(out, after_title, chapter)
  val after_page = _cite_page(out, after_chapter, label, label_len)
in _literal(out, after_page, "\n\n") end

fun _markdown {out_loc,title_loc,author_loc:agz}{arena:addr}{out_size:int}{count:nat}{position:nat | position + 3600 * count + 64 <= out_size}{title_size,author_size:pos}{title_len:nat | title_len < title_size; title_len < 256}{author_len:nat | author_len < author_size; author_len < 256} .<count>.
  (out: !$A.arrx(byte, out_loc, out_size, arena), position: int position, annotations: !annotations(count), last_chapter: Int,
   title: !$A.arr(byte, title_loc, title_size), title_len: int title_len, author: !$A.arr(byte, author_loc, author_size), author_len: int author_len): [next:nat | next + 64 <= out_size] int next =
  case+ annotations of
  | annotations_nil() => position
  | @annotations_cons(kind, chapter, _, _, _, _, _, _, text, text_len, note, note_len, label, label_len, rest) =>
    (* a bookmark is exported when it has a note *)
    if kind = 0 then (if note_len > 0 then let
      val after_heading = _markdown_heading_if_new(out, position, chapter, last_chapter)
      val text_at = _literal(out, after_heading, "**Bookmark:** ")
      val () = _flat_at(text, text_len, out, text_at, 0)
      val after_text = _literal(out, text_at + text_len, "\n\n")
      val after_note = _markdown_note(out, after_text, note, note_len)
      val next = _markdown(out, after_note, rest, chapter, title, title_len, author, author_len)
      prval () = fold@(annotations)
    in next end
    else let
      val next = _markdown(out, position, rest, last_chapter, title, title_len, author, author_len)
      prval () = fold@(annotations)
    in next end)
    else if ~_is_highlight(kind) then let
      val next = _markdown(out, position, rest, last_chapter, title, title_len, author, author_len)
      prval () = fold@(annotations)
    in next end
    else let
      val after_heading = _markdown_heading_if_new(out, position, chapter, last_chapter)
      val quote_at = _literal(out, after_heading, "> ")
      val () = _flat_at(text, text_len, out, quote_at, 0)
      val after_quote = _literal(out, quote_at + text_len, "\n\n")
      (* the style, unless yellow, the usual one *)
      val style = _style_of(kind)
      val after_style = _markdown_style(out, after_quote, style)
      val after_cite = _markdown_cite(out, after_style, chapter, title, title_len, author, author_len, label, label_len)
      val after_note = _markdown_note(out, after_cite, note, note_len)
      val next = _markdown(out, after_note, rest, chapter, title, title_len, author, author_len)
      prval () = fold@(annotations)
    in next end

(* The Markdown file used[0, used_len) downloaded *)
fn _markdown_download {used_loc:agz}{used_len:pos} (used: !$A.borrow(byte, used_loc, used_len), used_len: int used_len): void = let
  val mime = $A.alloc<byte>(13)
  val () = $A.write_text(mime, 0, $A.text_lit("text/markdown"), 13)
  val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime)
  val name = $A.alloc<byte>(20)
  val () = $A.write_text(name, 0, $A.text_lit("quire-annotations.md"), 20)
  val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
  val () = $BL.download_blob(used, used_len, mime_bytes, 13, name_bytes, 20)
  val () = release_bytes(name_frozen, name_bytes)
in release_bytes(mime_frozen, mime_bytes) end

(* The Markdown file used[0, used_len) put where the page's script
   shares it from (annotations-share-text), when it fits; else
   downloaded *)
fn _markdown_share {used_loc:agz}{used_len:pos} (used: !$A.borrow(byte, used_loc, used_len), used_len: int used_len): void =
  if used_len >= 65536 then _markdown_download(used, used_len)
  else let
    val id = $A.alloc<byte>(22)
    val () = $A.write_text(id, 0, $A.text_lit("annotations-share-text"), 22)
  in ui_text_n_b(id, 22, used, 0, used_len) end

(* The highlights and notes as a Markdown file, headed by the book's
   title title[0, title_len) and author author[0, author_len):
   downloaded, or, to be shared, put where the page's script shares it
   from *)
#pub fn annot_export {title_loc,author_loc:agz}{title_size,author_size:pos}{title_len:nat | title_len < title_size; title_len < 256}{author_len:nat | author_len < author_size; author_len < 256}
  (title: $A.arr(byte, title_loc, title_size), title_len: int title_len, author: $A.arr(byte, author_loc, author_size), author_len: int author_len, share: bool): void

implement annot_export (title, title_len, author, author_len, share) = let
  val cell = _take()
  val+ @AnnotationsCell(annotations, count) = cell
  val piece_size = 1024 + 3600 * count
in
  case+ piece_new(piece_size) of
  | ~NoPiece() => let
      prval () = fold@(cell)
      val () = _put(cell)
      val () = $A.free<byte>(title)
    in $A.free<byte>(author) end
  | ~Piece(owner, out) => let
      val title_at = _literal(out, 0, "# ")
      val () = _flat_at(title, title_len, out, title_at, 0)
      val author_at = _literal(out, title_at + title_len, "\n## ")
      val () = _flat_at(author, author_len, out, author_at, 0)
      val list_at = _literal(out, author_at + author_len, "\n\n")
      val list_end = _markdown(out, list_at, annotations, ~1, title, title_len, author, author_len)
      val () = $A.free<byte>(title)
      val () = $A.free<byte>(author)
      prval () = fold@(cell)
      val () = _put(cell)
      val file_end = _literal(out, list_end, "---\n*Exported from Quire*\n")
      val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(out_frozen, out_bytes, file_end)
      val () = (if share then _markdown_share(used, file_end) else _markdown_download(used, file_end))
      val out_bytes = $A.borrow_join<byte>(out_frozen, used, rest)
      val () = $A.drop<byte>(out_frozen, out_bytes)
    in piece_free(owner, $A.thaw<byte>(out_frozen)) end
end

(* ============================================================
   Backup: a book's annotations as JSON
   ============================================================ *)

(* The bytes one annotation takes in JSON, at most *)
#define JSON_MAX 15000

fn _kind_json {l:agz}{arena:addr}{n:nat}{position:nat | position + 44 <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, kind: int): [next:int | position < next; next <= position + 44] int next =
  if ~_is_highlight(kind) then jw_lit(out, position, "{\"kind\":\"bookmark\"")
  else let
    val style = _style_of(kind)
  in
    if style = 1 then jw_lit(out, position, "{\"kind\":\"highlight\",\"style\":\"orange\"")
    else if style = 2 then jw_lit(out, position, "{\"kind\":\"highlight\",\"style\":\"underline\"")
    else jw_lit(out, position, "{\"kind\":\"highlight\",\"style\":\"yellow\"")
  end

(* An annotation's print page, ',"printPage":"214"', when it has one *)
fn _print_page_json {l,label_loc:agz}{arena:addr}{n:int}{label_size:pos}{label_len:nat | label_len < label_size; label_len <= LABEL_MAX}{position:nat | position + 15 + 6 * LABEL_MAX <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, label: !$A.arr(byte, label_loc, label_size), label_len: int label_len)
  : [next:nat | next <= position + 15 + 6 * LABEL_MAX] int next =
  if label_len <= 0 then position
  else let
    val print_page_at = jw_lit(out, position, ",\"printPage\":")
  in jw_str(out, print_page_at, label, label_len) end

fun _json_annotations {l:agz}{arena:addr}{n:int}{count:nat}{position:nat | position + JSON_MAX * count + 1 <= n} .<count>.
  (out: !$A.arrx(byte, l, n, arena), position: int position, annotations: !annotations(count), first: bool): [next:nat | next + 1 <= n] int next =
  case+ annotations of
  | annotations_nil() => position
  | @annotations_cons(kind, chapter, start_node, start_offset, end_node, end_offset, page, made_at, text, text_len, note, note_len, label, label_len, rest) => let
      val after_comma = (if first then position else jw_lit(out, position, ",")): [after:int | position <= after; after <= position + 1] int after
      val after_kind = _kind_json(out, after_comma, kind)
      val chapter_at = jw_lit(out, after_kind, ",\"chapter\":")
      val after_chapter = jw_int(out, chapter_at, chapter)
      val node_at = jw_lit(out, after_chapter, ",\"node\":")
      val after_node = jw_int(out, node_at, start_node)
      val offset_at = jw_lit(out, after_node, ",\"offset\":")
      val after_offset = jw_int(out, offset_at, start_offset)
      val end_node_at = jw_lit(out, after_offset, ",\"endNode\":")
      val after_end_node = jw_int(out, end_node_at, end_node)
      val end_offset_at = jw_lit(out, after_end_node, ",\"endOffset\":")
      val after_end_offset = jw_int(out, end_offset_at, end_offset)
      val page_at = jw_lit(out, after_end_offset, ",\"page\":")
      val after_page = jw_int(out, page_at, page)
      val time_at = jw_lit(out, after_page, ",\"time\":")
      val after_time = jw_int(out, time_at, made_at)
      val text_at = jw_lit(out, after_time, ",\"text\":")
      val after_text = jw_str(out, text_at, text, text_len)
      val note_at = jw_lit(out, after_text, ",\"note\":")
      val after_note = jw_str(out, note_at, note, note_len)
      (* the print page, when it was made on one *)
      val after_print_page = _print_page_json(out, after_note, label, label_len)
      val after_brace = jw_lit(out, after_print_page, "}")
      val next = _json_annotations(out, after_brace, rest, false)
      prval () = fold@(annotations)
    in next end

(* The annotations stored in stored[0, n) (a book's "a" record) as a
   JSON array; none when they cannot be read or the memory cannot be had *)
#pub fn annot_json {l:agz}{arena:addr}{n:nat} (stored: !$A.arrx(byte, l, n, arena), n: int n): jchunk

implement annot_json (stored, n) =
  let
    val version = _version(stored, n)
  in
  if version = 0 then JNone()
  else let
    val @(annotations, count) = _parse(stored, n, 4, version, annotations_nil(), 0)
  in
    case+ piece_new(2 + JSON_MAX * count) of
    | ~NoPiece() => let val () = annotations_free(annotations) in JNone() end
    | ~Piece(owner, out) => let
        val () = $A.write_byte(out, 0, 91)
        val array_end = _json_annotations(out, 1, annotations, true)
        val () = $A.write_byte(out, array_end, 93)
        val () = annotations_free(annotations)
      in JChunk(owner, out, array_end + 1) end
  end
  end

(* A copy of source[0, source_len), in source_len + 1 bytes *)
fn _copy_prefix_or_whole {l:agz}{n:pos}{source_len:nat | source_len <= n; source_len < 1048576} (source: !$A.arr(byte, l, n), source_len: int source_len): [copy_loc:agz] $A.arr(byte, copy_loc, source_len + 1) = let
  val prefix_copy = $A.alloc<byte>(source_len + 1)
  val () = _copy_bytes(source, prefix_copy, source_len, 0)
in prefix_copy end

(* The number a member's key names: 1 chapter, 2 node, 3 offset, 4
   endNode, 5 endOffset, 6 page, 7 time; -1 for any other *)
fn _number_member {key_loc:agz}{key_len:nat | key_len <= 16} (key: !$A.arr(byte, key_loc, 16), key_len: int key_len): [member:int | ~1 <= member; member < 8] int member =
  if jr_key_is(key, key_len, "chapter") then 1
  else if jr_key_is(key, key_len, "node") then 2
  else if jr_key_is(key, key_len, "offset") then 3
  else if jr_key_is(key, key_len, "endNode") then 4
  else if jr_key_is(key, key_len, "endOffset") then 5
  else if jr_key_is(key, key_len, "page") then 6
  else if jr_key_is(key, key_len, "time") then 7
  else ~1

(* A number member's value at value_at, kept in values[member] *)
fn _number_member_at {json_loc,values_loc:agz}{arena:addr}{json_size:nat}{value_at:nat | value_at <= json_size}{member:nat | member < 8}
  (json: !$A.arrx(byte, json_loc, json_size, arena), json_size: int json_size, value_at: int value_at, values: !$A.arr(Int, values_loc, 9), member: int member): [next:int | value_at <= next; next <= json_size] int next = let
  val @(ok, value, next) = jr_int(json, json_size, value_at)
in
  if ok then let val () = $A.set<Int>(values, member, value) in next end
  else jr_skip(json, json_size, value_at)
end

(* The kind member's value at value_at ("highlight" or 1 for a
   highlight) *)
fn _kind_member_at {json_loc,key_loc,values_loc:agz}{arena:addr}{json_size:nat}{value_at:nat | value_at < json_size}
  (json: !$A.arrx(byte, json_loc, json_size, arena), json_size: int json_size, value_at: int value_at, key: !$A.arr(byte, key_loc, 16), values: !$A.arr(Int, values_loc, 9)): [next:int | value_at < next; next <= json_size] int next =
  if jr_is(json, json_size, value_at, 34) then let
    val @(ok, kind_len, next) = jr_str(json, json_size, value_at, key, 16)
    val () = $A.set<Int>(values, 0, (if ok then (if jr_key_is(key, kind_len, "highlight") then 1 else 0) else 0))
  in next end
  else let
    val @(ok, kind_number, next) = jr_int(json, json_size, value_at)
    val () = $A.set<Int>(values, 0, (if ok then (if kind_number = 1 then 1 else 0) else 0))
  in if next > value_at then next else jr_skip(json, json_size, value_at + 1) end

(* A highlight's style member's value at value_at, kept in values[8]: 0
   yellow (and any other), 1 orange, 2 underline *)
fn _style_member_at {json_loc,key_loc,values_loc:agz}{arena:addr}{json_size:nat}{value_at:nat | value_at < json_size}
  (json: !$A.arrx(byte, json_loc, json_size, arena), json_size: int json_size, value_at: int value_at, key: !$A.arr(byte, key_loc, 16), values: !$A.arr(Int, values_loc, 9)): [next:int | value_at <= next; next <= json_size] int next =
  if jr_is(json, json_size, value_at, 34) then let
    val @(ok, style_len, next) = jr_str(json, json_size, value_at, key, 16)
    val () = $A.set<Int>(values, 8, (if ok then (if jr_key_is(key, style_len, "orange") then 1
      else if jr_key_is(key, style_len, "underline") then 2 else 0) else 0))
  in next end
  else jr_skip(json, json_size, value_at)

(* The members of an annotation's object from position, to its closing
   brace: its numbers (and a highlight's style) into values, its text
   into text_buffer[0, text_len), its note into note_buffer[0, note_len)
   and its print page into label_buffer[0, label_len) (a label longer
   than LABEL_MAX is not one the reader makes, and is left out) *)
fun _members {json_loc,key_loc,text_loc,note_loc,label_loc,values_loc:agz}{arena:addr}{json_size:nat}{position:nat | position <= json_size}{text_len:nat | text_len <= TEXT_MAX}{note_len:nat | note_len <= NOTE_MAX}{label_len:nat | label_len <= LABEL_MAX} .<json_size - position>.
  (json: !$A.arrx(byte, json_loc, json_size, arena), json_size: int json_size, position: int position, key: !$A.arr(byte, key_loc, 16),
   text_buffer: !$A.arr(byte, text_loc, TEXT_MAX), note_buffer: !$A.arr(byte, note_loc, NOTE_MAX), label_buffer: !$A.arr(byte, label_loc, LABEL_MAX + 1), values: !$A.arr(Int, values_loc, 9), text_len: int text_len, note_len: int note_len, label_len: int label_len)
  : [next:int | position <= next; next <= json_size][new_text_len:nat | new_text_len <= TEXT_MAX][new_note_len:nat | new_note_len <= NOTE_MAX][new_label_len:nat | new_label_len <= LABEL_MAX] @(bool, int new_text_len, int new_note_len, int new_label_len, int next) = let
  val member_at = jr_ws(json, json_size, position)
in
  if member_at >= json_size then @(false, text_len, note_len, label_len, json_size)
  else if jr_is(json, json_size, member_at, 125) then @(true, text_len, note_len, label_len, member_at + 1)
  else if jr_is(json, json_size, member_at, 44) then _members(json, json_size, member_at + 1, key, text_buffer, note_buffer, label_buffer, values, text_len, note_len, label_len)
  else let
    val @(ok, key_len, value_at) = jr_key(json, json_size, member_at, key, 16)
  in
    if ~ok then @(false, text_len, note_len, label_len, value_at)
    else if value_at >= json_size then @(false, text_len, note_len, label_len, value_at)
    else if jr_key_is(key, key_len, "text") then let
      val @(read_ok, read_text_len, after) = jr_str(json, json_size, value_at, text_buffer, TEXT_MAX)
    in if read_ok then _members(json, json_size, after, key, text_buffer, note_buffer, label_buffer, values, read_text_len, note_len, label_len) else @(false, text_len, note_len, label_len, after) end
    else if jr_key_is(key, key_len, "note") then let
      val @(read_ok, read_note_len, after) = jr_str(json, json_size, value_at, note_buffer, NOTE_MAX)
    in if read_ok then _members(json, json_size, after, key, text_buffer, note_buffer, label_buffer, values, text_len, read_note_len, label_len) else @(false, text_len, note_len, label_len, after) end
    else if jr_key_is(key, key_len, "printPage") then let
      val @(read_ok, read_label_len, after) = jr_str(json, json_size, value_at, label_buffer, LABEL_MAX + 1)
    in
      if ~read_ok then @(false, text_len, note_len, label_len, after)
      else if read_label_len > LABEL_MAX then _members(json, json_size, after, key, text_buffer, note_buffer, label_buffer, values, text_len, note_len, 0)
      else _members(json, json_size, after, key, text_buffer, note_buffer, label_buffer, values, text_len, note_len, read_label_len)
    end
    else if jr_key_is(key, key_len, "kind") then _members(json, json_size, _kind_member_at(json, json_size, value_at, key, values), key, text_buffer, note_buffer, label_buffer, values, text_len, note_len, label_len)
    else if jr_key_is(key, key_len, "style") then _members(json, json_size, _style_member_at(json, json_size, value_at, key, values), key, text_buffer, note_buffer, label_buffer, values, text_len, note_len, label_len)
    else let
      val member = _number_member(key, key_len)
    in
      if member >= 0 then _members(json, json_size, _number_member_at(json, json_size, value_at, values, member), key, text_buffer, note_buffer, label_buffer, values, text_len, note_len, label_len)
      else _members(json, json_size, jr_skip(json, json_size, value_at), key, text_buffer, note_buffer, label_buffer, values, text_len, note_len, label_len)
    end
  end
end

fun _zero_values {values_loc:agz}{i:nat | i <= 9} .<9 - i>. (values: !$A.arr(Int, values_loc, 9), i: int i): void =
  if i >= 9 then () else let val () = $A.set<Int>(values, i, 0) in _zero_values(values, i + 1) end

(* The annotations of a JSON array's items from position, to its closing
   bracket, onto annotations (at most ANNOTATIONS_MAX) *)
fun _items {json_loc,key_loc,text_loc,note_loc,label_loc,values_loc:agz}{arena:addr}{json_size:nat}{position:nat | position <= json_size}{count:nat | count <= ANNOTATIONS_MAX} .<json_size - position>.
  (json: !$A.arrx(byte, json_loc, json_size, arena), json_size: int json_size, position: int position, key: !$A.arr(byte, key_loc, 16),
   text_buffer: !$A.arr(byte, text_loc, TEXT_MAX), note_buffer: !$A.arr(byte, note_loc, NOTE_MAX), label_buffer: !$A.arr(byte, label_loc, LABEL_MAX + 1), values: !$A.arr(Int, values_loc, 9), annotations: annotations(count), count: int count)
  : [total:nat | total <= ANNOTATIONS_MAX] @(bool, annotations(total), int total) = let
  val item_at = jr_ws(json, json_size, position)
in
  if item_at >= json_size then @(false, annotations, count)
  else if jr_is(json, json_size, item_at, 93) then @(true, annotations, count)
  else if jr_is(json, json_size, item_at, 44) then _items(json, json_size, item_at + 1, key, text_buffer, note_buffer, label_buffer, values, annotations, count)
  else if jr_is(json, json_size, item_at, 123) then let
    val () = _zero_values(values, 0)
    val @(ok, text_len, note_len, label_len, after) = _members(json, json_size, item_at + 1, key, text_buffer, note_buffer, label_buffer, values, 0, 0, 0)
  in
    if ~ok then @(false, annotations, count)
    else if count >= ANNOTATIONS_MAX then _items(json, json_size, after, key, text_buffer, note_buffer, label_buffer, values, annotations, count)
    else let
      val text = _copy_prefix_or_whole(text_buffer, text_len)
      val note = _copy_prefix_or_whole(note_buffer, note_len)
      val label = _copy_prefix_or_whole(label_buffer, label_len)
      (* a highlight's kind is its style's *)
      val kind = $A.get<Int>(values, 0)
      val kind = (if kind = 1 then 1 + $A.get<Int>(values, 8) else kind): Int
      val added = _insert(kind, $A.get<Int>(values, 1), $A.get<Int>(values, 2), $A.get<Int>(values, 3),
                    $A.get<Int>(values, 4), $A.get<Int>(values, 5), $A.get<Int>(values, 6), $A.get<Int>(values, 7),
                    text, text_len, note, note_len, label, label_len, annotations)
    in _items(json, json_size, after, key, text_buffer, note_buffer, label_buffer, values, added, count + 1) end
  end
  else @(false, annotations, count)
end

(* Stores the annotations of the JSON array at position (in a backup the
   user picked, checked here as it is read) as book id_high, id_low's;
   how many, or -1 when the array cannot be read *)
#pub fn annot_json_store {json_loc:agz}{arena:addr}{json_size:nat}{position:nat | position <= json_size}
  (json: !$A.arrx(byte, json_loc, json_size, arena), json_size: int json_size, position: int position, id_high: int, id_low: int): int

implement annot_json_store (json, json_size, position, id_high, id_low) =
  if position >= json_size then ~1
  else if ~jr_is(json, json_size, position, 91) then ~1
  else let
    val key = $A.alloc<byte>(16)
    val text_buffer = $A.alloc<byte>(TEXT_MAX)
    val note_buffer = $A.alloc<byte>(NOTE_MAX)
    val label_buffer = $A.alloc<byte>(LABEL_MAX + 1)
    val values = $A.alloc<Int>(9)
    val @(ok, annotations, count) = _items(json, json_size, position + 1, key, text_buffer, note_buffer, label_buffer, values, annotations_nil(), 0)
    val () = $A.free<byte>(key)
    val () = $A.free<byte>(text_buffer)
    val () = $A.free<byte>(note_buffer)
    val () = $A.free<byte>(label_buffer)
    val () = $A.free<Int>(values)
  in
    if ok then let
      val () = _store(id_high, id_low, annotations, count)
      val () = annotations_free(annotations)
    in count end
    else let val () = annotations_free(annotations) in ~1 end
  end

end (* #target wasm *)
