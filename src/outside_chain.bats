(* outside_chain -- a book's bytes from outside the program to the renderer, with OUTSIDE_READ (keyword: outside-chain).
   The fetch of a catalogue body, and a decompressed entry, are read as cells of outside bytes and given
   to text_proved's take_text_outside_sum. Additive: the old chain stays beside it until its dependents move. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use promise as P
#use zip as Z
#use xml-tree as X

staload "book.sats"
staload "ui.sats"
staload "book_tags.sats"
staload "text_proved.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DB = "wasm.bats-packages.dev/dom/src/book.sats"
staload BO = "wasm.bats-packages.dev/bridge/src/outside.sats"
staload CB = "css/src/book.sats"
#use css as C

(* An entry's text from the browser's decompression: its cells are outside bytes, with their proofs (keyword: outside-chain) *)
#pub datavtype outside_text =
  | {cs:$A.cells} OutsideText of (outside_taken(cs))
  | OutsideTextNone of ()

(* The entry's decompressed bytes read as outside cells, checked against the sum the archive states, and taken as text; none
   when the decompression failed, the entry is empty or over 1 MiB, or the sum is not the entry's *)
#pub fn take_outside_text_sum (inflated: $BO.decompressed_outside, sum: entry_sum): outside_text

implement take_outside_text_sum (inflated, sum) =
  case+ inflated of
  | ~$BO.DecompressFailedOutside() => let
      val () = (case+ sum of ~SumKnown(_, _) => () | ~SumUnknown() => ())
    in OutsideTextNone() end
  | ~$BO.DecompressedOutside(blob) => let
      val n = $BO.blob_len_outside(blob)
    in
      if n <= 0 then let
        val () = $BO.blob_free_outside(blob)
        val () = (case+ sum of ~SumKnown(_, _) => () | ~SumUnknown() => ())
      in OutsideTextNone() end
      else if n > 1048576 then let
        val () = $BO.blob_free_outside(blob)
        val () = (case+ sum of ~SumKnown(_, _) => () | ~SumUnknown() => ())
      in OutsideTextNone() end
      else let
        val out = $A.alloc<byte>(n)
        val (read, length, lent | cells) = $BO.blob_read_outside(blob, out, n)
        val () = $BO.blob_free_outside(blob)
      in
        case+ sum of
        | ~SumUnknown() => let
            val () = $A.free<byte>($A.barr_to_arrx(lent | cells))
          in OutsideTextNone() end
        | ~SumKnown(want_high, want_low) => let
            val @(back, taken) = take_text_outside_sum(read, length | cells, n, want_high, want_low)
            val () = $A.free<byte>($A.barr_to_arrx(lent | back))
          in OutsideText(taken) end
      end
    end

(* An outside text not wanted *)
#pub fn outside_text_free (text: outside_text): void

implement outside_text_free (text) =
  case+ text of
  | ~OutsideText(taken) => outside_taken_free(taken)
  | ~OutsideTextNone() => ()

(* A promise of an outside text nobody took frees it (the orphan rule: outside_text is this package's own type) *)
implement $P.dispose<outside_text>(text) = outside_text_free(text)

(* A fetched body (a catalogue's book) held by JS as a file of outside bytes: the blob read as cells, which file_store_outside
   takes with their proof; none when it is empty or over 1 MiB *)
#pub datavtype outside_file =
  | {n:pos} OutsideFile of ($BO.infile_outside(n))
  | OutsideFileNone of ()

#pub fn outside_file_of_fetched (got: $BO.fetched_outside): outside_file

implement outside_file_of_fetched (got) =
  case+ got of
  | ~$BO.NotFetchedOutside() => OutsideFileNone()
  | ~$BO.FetchedOutside(blob) => let
      val n = $BO.blob_len_outside(blob)
    in
      if n <= 0 then let val () = $BO.blob_free_outside(blob) in OutsideFileNone() end
      else if n > 1048576 then let val () = $BO.blob_free_outside(blob) in OutsideFileNone() end
      else let
        val out = $A.alloc<byte>(n)
        val (read, length, lent | cells) = $BO.blob_read_outside(blob, out, n)
        val () = $BO.blob_free_outside(blob)
        val @(frozen, view) = $A.barr_freeze(cells)
        val file = $BO.file_store_outside(read | view, n)
        val () = $A.cborrow_drop(frozen, view)
        val () = $A.free<byte>($A.barr_to_arrx(lent | $A.barr_thaw(frozen)))
      in OutsideFile(file) end
    end

(* The file given back *)
#pub fn outside_file_free (file: outside_file): void

implement outside_file_free (file) =
  case+ file of
  | ~OutsideFile(held) => $BO.file_close_outside(held)
  | ~OutsideFileNone() => ()


(* ===== the open book's outside copy (keyword: outside-chain) ===== *)

(* The picked, dropped or stored file of the book in hand, as outside bytes: held by JS in its own table (not the book cell's file) *)
datavtype outside_slot =
  | {n:nat} OutsideHeld of ($BO.infile_outside(n), int n)
  | OutsideEmpty of ()

val _slot = ref<outside_slot>(OutsideEmpty())

fn _slot_take (): outside_slot = let
  var held: outside_slot = OutsideEmpty()
  val () = ref_exch_elt<outside_slot>(_slot, held)
in held end

(* Puts held in the slot; what was there is closed *)
fn _slot_replace (held: outside_slot): void = let
  var previous: outside_slot = held
  val () = ref_exch_elt<outside_slot>(_slot, previous)
in
  case+ previous of
  | ~OutsideHeld(old, _) => $BO.file_close_outside(old)
  | ~OutsideEmpty() => ()
end

fn _slot_set {n:nat} (file: $BO.infile_outside(n)): void = let
  val size = $BO.file_size_outside(file)
in _slot_replace(OutsideHeld(file, size)) end

(* No book's file in the slot: a book that has no outside copy must not be read from another's (keyword: outside-chain) *)
#pub fn outside_slot_clear (): void

implement outside_slot_clear () = _slot_replace(OutsideEmpty())

fn _after_open (opened: $BO.opened_outside): bool =
  case+ opened of
  | ~$BO.OpenedOutside(file) => let val () = _slot_set(file) in true end
  | ~$BO.NotOpenedOutside() => let val () = _slot_replace(OutsideEmpty()) in false end
  | ~$BO.OpenFailedOutside() => let val () = _slot_replace(OutsideEmpty()) in false end

(* The file the reader picked (kind 0: the import input, 1: the empty library's input) or dropped (kind 2 and over), file_index of
   them, opened as outside bytes into the slot: whether it was *)
#pub fn outside_book_pick (kind: int, file_index: int): $P.promise(bool, $P.Chained)

implement outside_book_pick (kind, file_index) =
  if kind >= 2 then
    $P.and_then<$BO.opened_outside><bool>($BO.dropped_open_at_outside(file_index), llam(opened) => $P.ret<bool>(_after_open(opened)))
  else if kind = 1 then let
    val input_id = $A.alloc<byte>(17)
    val () = $A.write_text(input_id, 0, $A.text_lit("empty-import-file"), 17)
    val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
    val opening = $BO.file_open_at_outside(id_bytes, 17, file_index)
    val () = $A.drop<byte>(id_frozen, id_bytes)
    val () = $A.free<byte>($A.thaw<byte>(id_frozen))
  in $P.and_then<$BO.opened_outside><bool>(opening, llam(opened) => $P.ret<bool>(_after_open(opened))) end
  else let
    val input_id = $A.alloc<byte>(11)
    val () = $A.write_text(input_id, 0, $A.text_lit("import-file"), 11)
    val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
    val opening = $BO.file_open_at_outside(id_bytes, 11, file_index)
    val () = $A.drop<byte>(id_frozen, id_bytes)
    val () = $A.free<byte>($A.thaw<byte>(id_frozen))
  in $P.and_then<$BO.opened_outside><bool>(opening, llam(opened) => $P.ret<bool>(_after_open(opened))) end

(* Whether the slot's file was stored in the second IndexedDB database (a type of this package's own, so a promise of it is
   disposed here, not by an implement for bridge's stored) *)
#pub datatype outside_put =
  | OutsidePutStored of ()
  | OutsidePutNot of ()

implement $P.dispose<outside_put>(_) = ()

(* The slot's file stored in the second IndexedDB database under key *)
#pub fn outside_book_idb_put {key_loc:agz}{key_size:pos}
  (key: !$A.borrow(byte, key_loc, key_size), key_size: int key_size): $P.promise(outside_put, $P.Chained)

implement outside_book_idb_put (key, key_size) = let
  val held = _slot_take()
in
  case+ held of
  | @OutsideHeld(file, _) => let
      val stored = $BO.file_idb_put_outside(key, key_size, file)
      prval () = fold@(held)
      val () = _slot_replace(held)
    in
      $P.and_then<$IDB.stored><outside_put>(stored, llam(status) =>
        case+ status of
        | $IDB.Stored() => $P.ret<outside_put>(OutsidePutStored())
        | $IDB.NotStored() => $P.ret<outside_put>(OutsidePutNot()))
    end
  | ~OutsideEmpty() => $P.ret<outside_put>(OutsidePutNot())
end

(* The file stored under key in the second IndexedDB database, into the slot: whether it was found *)
#pub fn outside_book_idb_get {key_loc:agz}{key_size:pos}
  (key: !$A.borrow(byte, key_loc, key_size), key_size: int key_size): $P.promise(bool, $P.Chained)

implement outside_book_idb_get (key, key_size) =
  $P.and_then<$BO.file_lookup_outside><bool>($BO.file_idb_get_outside(key, key_size), llam(found) =>
    case+ found of
    | ~$BO.FoundOutside(file) => let val () = _slot_set(file) in $P.ret<bool>(true) end
    | ~$BO.NotFoundOutside() => let val () = outside_slot_clear() in $P.ret<bool>(false) end
    | ~$BO.LookupFailedOutside() => let val () = outside_slot_clear() in $P.ret<bool>(false) end)

(* An entry of the file in the slot, [offset, offset + size) of it, read as outside cells, decompressed by the browser when method says
   and taken as text against the sum (want_high, want_low); none when there is no slot file of file_size bytes, or the entry is over 1 MiB *)
fn _chapter_read {n:nat}{f:nat}{k:pos | f + k <= n; k <= 1048576}
  (file: !$BO.infile_outside(n), offset: int f, size: int k, stored: bool, want_high: int, want_low: int)
  : $P.promise(outside_text, $P.Chained) = let
  val out = $A.alloc<byte>(size)
  val (read, length, lent | cells) = $BO.file_read_outside(file, offset, out, size)
in
  if stored then let
    val @(back, taken) = take_text_outside_sum(read, length | cells, size, want_high, want_low)
    val () = $A.free<byte>($A.barr_to_arrx(lent | back))
  in $P.ret<outside_text>(OutsideText(taken)) end
  else let
    val @(frozen, view) = $A.barr_freeze(cells)
    val deciding = $BO.decompress_outside(read | view, size, $BD.DeflateRaw())
    val () = $A.cborrow_drop(frozen, view)
    val () = $A.free<byte>($A.barr_to_arrx(lent | $A.barr_thaw(frozen)))
  in
    $P.and_then<$BO.decompressed_outside><outside_text>(deciding, llam(inflated) =>
      $P.ret<outside_text>(take_outside_text_sum(inflated, SumKnown(want_high, want_low))))
  end
end

#pub fn outside_chapter_text {f,k:int}
  (file_size: int, offset: int f, size: int k, method: $Z.compression, want_high: int, want_low: int): $P.promise(outside_text, $P.Chained)

implement outside_chapter_text {f,k} (file_size, offset, size, method, want_high, want_low) = let
  val held = _slot_take()
in
  case+ held of
  | @OutsideHeld(file, held_size) =>
    if held_size = file_size then
      (if offset >= 0 then
        (if size > 0 then
          (if size <= 1048576 then
            (if offset + size <= held_size then let
               val stored = (case+ method of $Z.Stored() => true | $Z.Deflated() => false)
               val got = _chapter_read(file, offset, size, stored, want_high, want_low)
               prval () = fold@(held)
               val () = _slot_replace(held)
             in got end
             else let prval () = fold@(held); val () = _slot_replace(held) in $P.ret<outside_text>(OutsideTextNone()) end)
           else let prval () = fold@(held); val () = _slot_replace(held) in $P.ret<outside_text>(OutsideTextNone()) end)
         else let prval () = fold@(held); val () = _slot_replace(held) in $P.ret<outside_text>(OutsideTextNone()) end)
       else let prval () = fold@(held); val () = _slot_replace(held) in $P.ret<outside_text>(OutsideTextNone()) end)
    else let prval () = fold@(held); val () = _slot_replace(held) in $P.ret<outside_text>(OutsideTextNone()) end
  | ~OutsideEmpty() => $P.ret<outside_text>(OutsideTextNone())
end


(* ===== the book's container (keyword: book container) ===== *)

(* Where the root tag of the document in the cells is, scanning from i *)
datavtype root_found(cs: $A.cells) =
  | {o:nat} RootFound(cs) of ($DB.ROOT_TAG(cs, o) | int o)
  | RootNone(cs) of ()

fun _find_root {l:agz}{n:pos}{cs:$A.cells}{i:nat | i <= n} .<n - i>.
  (src: !$A.cborrow(l, n, cs), n: int n, i: int i): root_found(cs) =
  if i >= n then RootNone()
  else let
    val (found_tag | found) = $DB.book_root_scan(src, n, i)
  in
    if found then let
      prval $DB.ROOT_TAG_yes(tag) = found_tag
    in RootFound(tag | i) end
    else _find_root(src, n, i + 1)
  end

(* The chapter's container and its document, held while the walk of the chapter makes its elements (keyword: book container) *)
datavtype book_sink =
  | BookSinkNone of ()
  | BookSinkOpen of ($DB.book_document(1), $DB.book_container(1))

val _sink = ref<book_sink>(BookSinkNone())

fn _sink_take (): book_sink = let
  var held: book_sink = BookSinkNone()
  val () = ref_exch_elt<book_sink>(_sink, held)
in held end

(* Puts held in the sink; what was there is closed *)
fn _sink_put (held: book_sink): void = let
  var previous: book_sink = held
  val () = ref_exch_elt<book_sink>(_sink, previous)
in
  case+ previous of
  | ~BookSinkOpen(doc, container) => let
      val () = $DB.close_book_container(container)
    in $DB.close_book_document(doc) end
  | ~BookSinkNone() => ()
end

(* The container of the chapter, as a child of the page, made from the outside cells; false when the document has no root tag
   or the bridge refuses the id (the chapter is then rendered as an app's, with no container) *)
#pub fn outside_sink_open {l:agz}{n:pos}{cs:$A.cells}
  (from: $BO.OUTSIDE_READ(cs) | src: !$A.cborrow(l, n, cs), n: int n): bool

implement outside_sink_open {l}{n}{cs} (from | src, n) =
  case+ _find_root(src, n, 0) of
  | ~RootNone() => false
  | ~RootFound(tag | at) => let
      val doc = $DB.open_book_document(1)
      val parent = $A.alloc<byte>(4)
      val () = $A.write_text(parent, 0, $A.text_lit("page"), 4)
      val @(parent_frozen, parent_bytes) = $A.freeze<byte>(parent)
      val name = $A.alloc<byte>(14)
      val () = $A.write_text(name, 0, $A.text_lit("book-container"), 14)
      val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
      val made = $DB.add_book_container(from, tag | doc, src, at, parent_bytes, 4, name_bytes, 14)
      val () = $A.drop<byte>(parent_frozen, parent_bytes)
      val () = $A.free<byte>($A.thaw<byte>(parent_frozen))
      val () = $A.drop<byte>(name_frozen, name_bytes)
      val () = $A.free<byte>($A.thaw<byte>(name_frozen))
    in
      case+ made of
      | ~$DB.BookContainerMade(container) => let
          val () = $DB.close_book_document(doc)
          val doc = $DB.open_book_document(1)
          val () = _sink_put(BookSinkOpen(doc, container))
        in true end
      | ~$DB.BookContainerRefused() => let
          val () = $DB.close_book_document(doc)
        in false end
    end

(* A book element of the open container, named by the book's own name (data-book-element); an image whatever its name when as_image
   (an inline svg is drawn as one); false when there is no container *)
#pub fn outside_sink_element {l:agz}{n:pos}{cs:$A.cells}{li:agz}{ni:pos | ni <= 1024}{lp:agz}{np:pos | np <= 1024}{o,k:nat | o + k <= n; k <= 255}
  (from: $BO.OUTSIDE_READ(cs) | src: !$A.cborrow(l, n, cs),
   id: !$A.borrow(byte, li, ni), id_len: int ni, parent: !$A.borrow(byte, lp, np), parent_len: int np,
   as_image: bool, name_offset: int o, name_len: int k): bool

implement outside_sink_element {l}{n}{cs}{li}{ni}{lp}{np}{o,k} (from | src, id, id_len, parent, parent_len, as_image, name_offset, name_len) =
  case+ _sink_take() of
  | ~BookSinkNone() => false
  | ~BookSinkOpen(doc, container) => let
      val tag = (if as_image then $DB.BookTagImg()
        else (case+ book_tag_of(src, name_offset, name_len) of
          | ~TagFound(found) => found
          | ~TagNone() => $DB.BookTagSpan())): $DB.book_tag
      val () = $DB.add_book_element(from | doc, container, id, id_len, parent, parent_len, tag, src, name_offset, name_len)
      (* the stream is applied now, so the ordinary operations that follow (text, attributes, urls, spans) find the element:
         the two streams are flushed on their own and the ordinary one would otherwise run first (keyword: book stream order) *)
      val () = $DB.close_book_document(doc)
      val doc = $DB.open_book_document(1)
      val () = _sink_put(BookSinkOpen(doc, container))
    in true end

(* The class names (kind 1), id (2) or epub:type (3) of a book element of the open container, from the text of the chapter (keyword: book names);
   false when there is no container *)
#pub fn outside_sink_names {l:agz}{n:pos}{cs:$A.cells}{li:agz}{ni:pos | ni <= 1024}{kind:int | 1 <= kind; kind <= 3}{o,k:nat | o + k <= n; k <= 65535}
  (from: $BO.OUTSIDE_READ(cs) | src: !$A.cborrow(l, n, cs), id: !$A.borrow(byte, li, ni), id_len: int ni,
   kind: int kind, off: int o, len: int k): bool

implement outside_sink_names {l}{n}{cs}{li}{ni}{kind}{o,k} (from | src, id, id_len, kind, off, len) =
  case+ _sink_take() of
  | ~BookSinkNone() => false
  | ~BookSinkOpen(doc, container) => let
      val () = $DB.set_book_names(from | doc, container, id, id_len, kind, src, off, len)
      val () = $DB.close_book_document(doc)
      val doc = $DB.open_book_document(1)
      val () = _sink_put(BookSinkOpen(doc, container))
    in true end

(* An app's element (a span, br, hr or img by kind 0, 1, 2, 3) of the open container, the last child of parent, applied at once as a book
   element is (keyword: book stream order); false when there is no container *)
#pub fn outside_sink_app_element {li:agz}{ni:pos | ni <= 1024}{lp:agz}{np:pos | np <= 1024}
  (id: !$A.borrow(byte, li, ni), id_len: int ni, parent: !$A.borrow(byte, lp, np), parent_len: int np, kind: int): bool

implement outside_sink_app_element {li}{ni}{lp}{np} (id, id_len, parent, parent_len, kind) =
  case+ _sink_take() of
  | ~BookSinkNone() => false
  | ~BookSinkOpen(doc, container) => let
      val tag = (if kind = 1 then $DB.BookTagBr()
        else if kind = 2 then $DB.BookTagHr()
        else if kind >= 3 then $DB.BookTagImg()
        else $DB.BookTagSpan()): $DB.book_tag
      val () = $DB.add_book_app_element(doc, id, id_len, parent, parent_len, tag)
      val () = $DB.close_book_document(doc)
      val doc = $DB.open_book_document(1)
      val () = _sink_put(BookSinkOpen(doc, container))
    in true end

(* Whether a container is open *)
#pub fn outside_sink_is_open (): bool

implement outside_sink_is_open () =
  case+ _sink_take() of
  | ~BookSinkNone() => false
  | ~BookSinkOpen(doc, container) => let val () = _sink_put(BookSinkOpen(doc, container)) in true end

(* The container of the chapter last shown, kept after its walk for the sheets and faces that are read later (keyword: book sheets) *)
datavtype held_container =
  | HeldNone of ()
  | HeldOpen of $DB.book_container(1)

val _held = ref<held_container>(HeldNone())

fn _held_take (): held_container = let
  var held: held_container = HeldNone()
  val () = ref_exch_elt<held_container>(_held, held)
in held end

(* Puts held away; what was there is closed *)
fn _held_put (held: held_container): void = let
  var previous: held_container = held
  val () = ref_exch_elt<held_container>(_held, previous)
in
  case+ previous of
  | ~HeldOpen(container) => $DB.close_book_container(container)
  | ~HeldNone() => ()
end

(* The document closed: the book's operations are flushed. Its container is kept for the sheets, or none is when the chapter had none *)
#pub fn outside_sink_close (): void

implement outside_sink_close () =
  case+ _sink_take() of
  | ~BookSinkNone() => _held_put(HeldNone())
  | ~BookSinkOpen(doc, container) => let
      val () = $DB.close_book_document(doc)
    in _held_put(HeldOpen(container)) end

(* The chapter last shown has its container still *)
#pub fn outside_sheet_ready (): bool

implement outside_sheet_ready () =
  case+ _held_take() of
  | ~HeldNone() => false
  | ~HeldOpen(container) => let val () = _held_put(HeldOpen(container)) in true end

(* A sheet of the book, read by css from outside cells, added to the container of the chapter last shown; false when it has none *)
#pub fn outside_sheet_add {l:agz}{n:pos}{cs:$A.cells}
  (from: $BO.OUTSIDE_READ(cs) | src: !$A.cborrow(l, n, cs), read: !$CB.book_read(cs, n, 1)): bool

implement outside_sheet_add {l}{n}{cs} (from | src, read) =
  case+ _held_take() of
  | ~HeldNone() => false
  | ~HeldOpen(container) => let
      val doc = $DB.open_book_document(1)
      val () = $DB.add_book_sheet(from | doc, container, src, read)
      val () = $DB.close_book_document(doc)
      val () = _held_put(HeldOpen(container))
    in true end

(* A face of the book, its bytes outside cells, added to the container of the chapter last shown *)
#pub fn outside_face_add {l:agz}{n:nat}{cs:$A.cells}{o:nat}{k:pos | o + k <= n}{face:nat | face < 32}{weight:int | 1 <= weight; weight <= 1000}{style:int | 0 <= style; style <= 2}
  (from: $BO.OUTSIDE_READ(cs) | src: !$A.cborrow(l, n, cs), off: int o, len: int k, face: int face, weight: int weight, style: int style): bool

implement outside_face_add {l}{n}{cs}{o}{k}{face}{weight}{style} (from | src, off, len, face, weight, style) =
  case+ _held_take() of
  | ~HeldNone() => false
  | ~HeldOpen(container) => let
      val doc = $DB.open_book_document(1)
      val () = $DB.add_book_font(from | doc, container, src, off, len, face, weight, style)
      val () = $DB.close_book_document(doc)
      val () = _held_put(HeldOpen(container))
    in true end

end (* #target wasm *)
