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

fn _after_open (opened: $BO.opened_outside): bool =
  case+ opened of
  | ~$BO.OpenedOutside(file) => let val () = _slot_set(file) in true end
  | ~$BO.NotOpenedOutside() => false
  | ~$BO.OpenFailedOutside() => false

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
    | ~$BO.NotFoundOutside() => $P.ret<bool>(false)
    | ~$BO.LookupFailedOutside() => $P.ret<bool>(false))

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

val _book_count = ref<Nat>(0)

(* A paragraph of the chapter as a book element of the container: its id is a number of its own (keyword: book container) *)
fn _add_paragraph {l:agz}{n:pos}{cs:$A.cells}{g:int}{o,k:nat | o + k <= n; k <= 255}
  (from: $BO.OUTSIDE_READ(cs) | doc: !$DB.book_document(g), container: !$DB.book_container(g), bytes: !$A.cborrow(l, n, cs),
   name_offset: int o, name_len: int k): void = let
  val number = !_book_count
  val () = !_book_count := number + 1
  val @(id, id_len) = nid_make("book-p", number)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val parent = $A.alloc<byte>(14)
  val () = $A.write_text(parent, 0, $A.text_lit("book-container"), 14)
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(parent)
  val () = $DB.add_book_element(from | doc, container, id_bytes, id_len, parent_bytes, 14, $DB.BookTagP(), bytes, name_offset, name_len)
  val () = $A.drop<byte>(parent_frozen, parent_bytes)
  val () = $A.free<byte>($A.thaw<byte>(parent_frozen))
  val () = $A.drop<byte>(id_frozen, id_bytes)
in $A.free<byte>($A.thaw<byte>(id_frozen)) end

fun _walk_nodes {l:agz}{n:pos}{cs:$A.cells}{g:int}{tree_size:nat} .<tree_size, 1>.
  (from: $BO.OUTSIDE_READ(cs) | doc: !$DB.book_document(g), container: !$DB.book_container(g), bytes: !$A.cborrow(l, n, cs),
   nodes: !$X.xml_node_list(n, tree_size)): void =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val () = _walk_node(from | doc, container, bytes, node)
    in _walk_nodes(from | doc, container, bytes, rest) end
  | $X.xml_nodes_nil() => ()

and _walk_node {l:agz}{n:pos}{cs:$A.cells}{g:int}{tree_size:pos} .<tree_size, 0>.
  (from: $BO.OUTSIDE_READ(cs) | doc: !$DB.book_document(g), container: !$DB.book_container(g), bytes: !$A.cborrow(l, n, cs),
   node: !$X.xml_node(n, tree_size)): void =
  case+ node of
  | $X.xml_text(_, _) => ()
  | $X.xml_element(name_offset, name_len, _, children) => let
      val () = (if name_len <= 255 then
        (case+ book_tag_of(bytes, name_offset, name_len) of
         | ~TagFound(tag) =>
           (case+ tag of
            | $DB.BookTagP() => _add_paragraph(from | doc, container, bytes, name_offset, name_len)
            | _ => ())
         | ~TagNone() => ())
        else ())
    in _walk_nodes(from | doc, container, bytes, children) end

(* The container of a book of document layout g, as a child of the page: made on the document's stream from the outside cells
   of the chapter, whose root tag it finds, with the chapter's paragraphs in it; whether it was made. The stream is flushed by
   the document's close *)
#pub fn outside_container_paragraphs {l:agz}{n:pos}{cs:$A.cells}{g:int | g == 1 || g == 2}{tree_size:nat}
  (from: $BO.OUTSIDE_READ(cs) | doc: !$DB.book_document(g), src: !$A.cborrow(l, n, cs), n: int n,
   nodes: !$X.xml_node_list(n, tree_size)): bool

implement outside_container_paragraphs {l}{n}{cs}{g}{tree_size} (from | doc, src, n, nodes) =
  case+ _find_root(src, n, 0) of
  | ~RootNone() => false
  | ~RootFound(tag | at) => let
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
          val () = _walk_nodes(from | doc, container, src, nodes)
          val () = $DB.close_book_container(container)
        in true end
      | ~$DB.BookContainerRefused() => false
    end

end (* #target wasm *)
