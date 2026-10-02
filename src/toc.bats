(* toc -- the open book's table of contents: read once from its nav
   document (EPUB 3) or NCX (EPUB 2), shown in the contents panel, and
   giving each chapter its title *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use str as S
#use xml-tree as X

staload "epub_xml.sats"
staload "book.sats"
staload "paths.sats"
staload "ui.sats"
staload "mem.sats"

(* A label's and a fragment's most bytes *)
#define LABEL_MAX 200
#define FRAGMENT_MAX 200

(* The entries, in document order: each one's label
   label_bytes[0, label_len), level (0 the top, at most 3), chapter (-1
   when its href names none) and the fragment fragment_bytes[0,
   fragment_len) its href ends with (the id after '#', when
   fragment_len > 0; fragment_bytes has fragment_len + 1 bytes) *)
datavtype toc(int) =
  | toc_nil(0) of ()
  | {count:nat}{label_loc,fragment_loc:agz}{label_len:pos | label_len <= LABEL_MAX}{fragment_len:nat | fragment_len <= FRAGMENT_MAX}{level:nat | level <= 3}{chapter:int | chapter >= ~1}
    toc_cons(count + 1) of ($A.arr(byte, label_loc, label_len), int label_len, int level, int chapter, $A.arr(byte, fragment_loc, fragment_len + 1), int fragment_len, toc(count))

fun toc_free {count:nat} .<count>. (entries: toc(count)): void =
  case+ entries of
  | ~toc_nil() => ()
  | ~toc_cons(label_bytes, _, _, _, fragment_bytes, _, rest) => let
      val () = $A.free<byte>(label_bytes)
      val () = $A.free<byte>(fragment_bytes)
    in toc_free(rest) end

(* destination[i, count) := source[i, count) *)
fun _copy_bytes {source_loc,destination_loc:agz}{source_size,destination_size:pos}{count:nat | count <= source_size; count <= destination_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), destination: !$A.arr(byte, destination_loc, destination_size), count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(destination, i, $A.get<byte>(source, i))
  in _copy_bytes(source, destination, count, i + 1) end

datavtype toc_cell =
  | {count:nat} TocCell of (toc(count), int count)

val _contents_cell = ref<toc_cell>(TocCell(toc_nil(), 0))
(* The book's print pages (its page-list), entries as the contents' *)
val _pages_cell = ref<toc_cell>(TocCell(toc_nil(), 0))

fn _pages_take (): toc_cell = let
  var cell: toc_cell = TocCell(toc_nil(), 0)
  val () = ref_exch_elt<toc_cell>(_pages_cell, cell)
in cell end

fn _pages_put (cell: toc_cell): void = let
  var previous: toc_cell = cell
  val () = ref_exch_elt<toc_cell>(_pages_cell, previous)
  val+ ~TocCell(entries, _) = previous
in toc_free(entries) end

fn _contents_take (): toc_cell = let
  var cell: toc_cell = TocCell(toc_nil(), 0)
  val () = ref_exch_elt<toc_cell>(_contents_cell, cell)
in cell end

fn _contents_put (cell: toc_cell): void = let
  var previous: toc_cell = cell
  val () = ref_exch_elt<toc_cell>(_contents_cell, previous)
  val+ ~TocCell(entries, _) = previous
in toc_free(entries) end

(* The document the entries are read from: an entry of the
   file_size-byte file, its data [data_offset, data_offset + data_size)
   with compression method method and its name [name_offset, name_offset +
   name_len); ncx when it is an NCX *)
datavtype toc_source =
  | {file_size:pos}{data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{method:int | method == 0 || method == 8}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
    TocSource of (int file_size, int data_offset, int data_size, int method, int name_offset, int name_len, bool)
  | TocNone of ()

val _source = ref<toc_source>(TocNone())

fn _source_take (): toc_source = let
  var source: toc_source = TocNone()
  val () = ref_exch_elt<toc_source>(_source, source)
in source end

fn _source_put (source: toc_source): void = let
  var previous: toc_source = source
  val () = ref_exch_elt<toc_source>(_source, previous)
in
  case+ previous of
  | ~TocSource(_, _, _, _, _, _, _) => ()
  | ~TocNone() => ()
end

(* ============================================================
   Finding the document, in the OPF
   ============================================================ *)

(* The entry of book serial (file_size bytes) named name[0, name_len);
   frees name *)
fn _find_entry {file_size:pos}{name_loc:agz}{name_size:pos | name_size <= 1048576}{name_len:nat | name_len <= name_size}
  (serial: int, file_size: int file_size, name: $A.arr(byte, name_loc, name_size), name_size: int name_size, name_len: int name_len): entry_hit(file_size) =
  if name_len <= 0 then let val () = $A.free<byte>(name) in EntryMiss() end
  else let
    val exact = $A.alloc<byte>(name_len)
    val name = $S.copy_arr_region(name, 0, name_size, exact, name_len, name_len)
    val () = $A.free<byte>(name)
    val @(exact_frozen, exact_bytes) = $A.freeze<byte>(exact)
    val hit = book_find_entry(serial, file_size, exact_bytes, name_len)
    val () = release_bytes(exact_frozen, exact_bytes)
  in hit end

(* The entry of book serial (file_size bytes) that href
   opf_bytes[href_offset, href_offset + href_len) names, after the OPF's
   directory (opf_dir_len bytes of the name at opf_name_offset) *)
fn _opf_entry {file_size:pos}{opf_name_offset:nat}{opf_dir_len:nat | opf_name_offset + opf_dir_len <= file_size; opf_dir_len < 65536}{opf_loc:agz}{opf_size:pos}{href_offset,href_len:nat | href_offset + href_len <= opf_size}
  (serial: int, file_size: int file_size, opf_name_offset: int opf_name_offset, opf_dir_len: int opf_dir_len, opf_bytes: !$A.borrow(byte, opf_loc, opf_size), opf_size: int opf_size,
   href_offset: int href_offset, href_len: int href_len): entry_hit(file_size) =
  if href_len <= 0 then EntryMiss()
  else if opf_dir_len + href_len > 1048576 then EntryMiss()
  else let
    val path_size = opf_dir_len + href_len
    val path = $A.alloc<byte>(path_size)
    val _ = book_read(serial, file_size, opf_name_offset, path, opf_dir_len)
    val () = $S.copy_from_borrow(opf_bytes, href_offset, opf_size, path, opf_dir_len, path_size, href_len)
    val path_len = path_norm(path, path_size)
  in _find_entry(serial, file_size, path, path_size, path_len) end

fn _source_of {file_size:pos} (file_size: int file_size, hit: entry_hit(file_size), ncx: bool): toc_source =
  case+ hit of
  | ~EntryHit(data_offset, data_size, method, name_offset, name_len) => TocSource(file_size, data_offset, data_size, method, name_offset, name_len, ncx)
  | ~EntryMiss() => TocNone()

(* Finds, in the OPF opf_bytes[0, opf_size) of book serial, the document
   the table of contents is read from: the manifest item with property
   nav, else the NCX the spine names *)
#pub fn toc_locate {file_size:pos}{opf_name_offset:nat}{opf_dir_len:nat | opf_name_offset + opf_dir_len <= file_size; opf_dir_len < 65536}{opf_loc:agz}{opf_size:pos}{nodes_size:nat}
  (serial: int, file_size: int file_size, opf_name_offset: int opf_name_offset, opf_dir_len: int opf_dir_len,
   opf_bytes: !$A.borrow(byte, opf_loc, opf_size), opf_size: int opf_size, nodes: !$X.xml_node_list(opf_size, nodes_size)): void

implement toc_locate (serial, file_size, opf_name_offset, opf_dir_len, opf_bytes, opf_size, nodes) = let
  var _c_nav = @[char][3]('n', 'a', 'v')
  val nav_source = (case+ find_item_with_prop(opf_bytes, nodes, _c_nav, 3) of
    | ~xspan_at(href_offset, href_len) => _source_of(file_size, _opf_entry(serial, file_size, opf_name_offset, opf_dir_len, opf_bytes, opf_size, href_offset, href_len), false)
    | ~xspan_none() => TocNone()): toc_source
  val source = (case+ nav_source of
    | TocSource(_, _, _, _, _, _, _) => nav_source
    | ~TocNone() => (case+ find_ncx_href(opf_bytes, opf_size, nodes) of
      | ~xspan_at(href_offset, href_len) => _source_of(file_size, _opf_entry(serial, file_size, opf_name_offset, opf_dir_len, opf_bytes, opf_size, href_offset, href_len), true)
      | ~xspan_none() => TocNone())): toc_source
in _source_put(source) end

(* ============================================================
   Reading the entries
   ============================================================ *)

(* An entry as read: its label label_bytes[0, label_len), level, and href
   data[href_offset, href_offset + href_len) (none when href_len is 0) *)
datavtype raw(data_size:int, int) =
  | raw_nil(data_size, 0) of ()
  | {count:nat}{label_loc:agz}{label_len:pos | label_len <= LABEL_MAX}{level:nat | level <= 3}{href_offset,href_len:nat | href_offset + href_len <= data_size}
    raw_cons(data_size, count + 1) of ($A.arr(byte, label_loc, label_len), int label_len, int level, int href_offset, int href_len, raw(data_size, count))

(* Whether data[offset + i, offset + i + pattern_len) is pattern, within
   data[offset, offset + text_len) *)
fn _matches_at {data_loc:agz}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size}{i:nat}{pattern_len:pos}
  (data: !$A.borrow(byte, data_loc, data_size), offset: int offset, text_len: int text_len, i: int i, pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool =
  if i + pattern_len > text_len then false else xml_name_eq(data, offset + i, pattern_len, pattern, pattern_len)

(* A byte at label_buffer[label_len] (while there is room), unless it is
   a space that would start the label or follow another *)
fn _label_add {label_loc:agz}{label_len:nat | label_len <= LABEL_MAX}
  (label_buffer: !$A.arr(byte, label_loc, LABEL_MAX), label_len: int label_len, code: int): [new_len:nat | new_len <= LABEL_MAX] int new_len =
  if label_len >= LABEL_MAX then label_len
  else if code = 32 then
    (if label_len = 0 then label_len
     else if byte2int0($A.get<byte>(label_buffer, label_len - 1)) = 32 then label_len
     else let val () = $A.set<byte>(label_buffer, label_len, $A.int2byte(32)) in label_len + 1 end)
  else let
    val () = $A.set<byte>(label_buffer, label_len, $A.int2byte($AR.low_byte(code)))
  in label_len + 1 end

(* i + width, or text_len when that is past text_len *)
fn _advance {i,text_len:nat | i < text_len}{width:pos} (i: int i, text_len: int text_len, width: int width): [j:int | i < j; j <= text_len] int j =
  if i + width <= text_len then i + width else text_len

(* The text data[offset + i, offset + text_len) added to the label
   label_buffer[0, label_len): white space as one space, and the five
   XML entities (and &nbsp;) decoded *)
fun _copy_text {data_loc,label_loc:agz}{data_size:pos}{offset,text_len:nat | offset + text_len <= data_size}{i:nat | i <= text_len}{label_len:nat | label_len <= LABEL_MAX} .<text_len - i>.
  (data: !$A.borrow(byte, data_loc, data_size), offset: int offset, text_len: int text_len, i: int i,
   label_buffer: !$A.arr(byte, label_loc, LABEL_MAX), label_len: int label_len): [new_len:nat | new_len <= LABEL_MAX] int new_len =
  if i >= text_len then label_len
  else let
    val code = byte2int0($A.read<byte>(data, offset + i))
  in
    if code = 9 then _copy_text(data, offset, text_len, _advance(i, text_len, 1), label_buffer, _label_add(label_buffer, label_len, 32))
    else if code = 10 then _copy_text(data, offset, text_len, _advance(i, text_len, 1), label_buffer, _label_add(label_buffer, label_len, 32))
    else if code = 13 then _copy_text(data, offset, text_len, _advance(i, text_len, 1), label_buffer, _label_add(label_buffer, label_len, 32))
    else if code = 38 then let
      var amp = @[char][4]('a', 'm', 'p', ';')
      var lt = @[char][3]('l', 't', ';')
      var gt = @[char][3]('g', 't', ';')
      var quot = @[char][5]('q', 'u', 'o', 't', ';')
      var apos = @[char][5]('a', 'p', 'o', 's', ';')
      var nbsp = @[char][5]('n', 'b', 's', 'p', ';')
    in
      if _matches_at(data, offset, text_len, i + 1, amp, 4) then _copy_text(data, offset, text_len, _advance(i, text_len, 5), label_buffer, _label_add(label_buffer, label_len, 38))
      else if _matches_at(data, offset, text_len, i + 1, lt, 3) then _copy_text(data, offset, text_len, _advance(i, text_len, 4), label_buffer, _label_add(label_buffer, label_len, 60))
      else if _matches_at(data, offset, text_len, i + 1, gt, 3) then _copy_text(data, offset, text_len, _advance(i, text_len, 4), label_buffer, _label_add(label_buffer, label_len, 62))
      else if _matches_at(data, offset, text_len, i + 1, quot, 5) then _copy_text(data, offset, text_len, _advance(i, text_len, 6), label_buffer, _label_add(label_buffer, label_len, 34))
      else if _matches_at(data, offset, text_len, i + 1, apos, 5) then _copy_text(data, offset, text_len, _advance(i, text_len, 6), label_buffer, _label_add(label_buffer, label_len, 39))
      else if _matches_at(data, offset, text_len, i + 1, nbsp, 5) then _copy_text(data, offset, text_len, _advance(i, text_len, 6), label_buffer, _label_add(label_buffer, label_len, 32))
      else _copy_text(data, offset, text_len, _advance(i, text_len, 1), label_buffer, _label_add(label_buffer, label_len, code))
    end
    else _copy_text(data, offset, text_len, _advance(i, text_len, 1), label_buffer, _label_add(label_buffer, label_len, code))
  end

(* The text of nodes, added to the label label_buffer[0, label_len) *)
fun _gather_nodes {data_loc,label_loc:agz}{data_size:pos}{nodes_size:nat}{label_len:nat | label_len <= LABEL_MAX} .<nodes_size, 1>.
  (data: !$A.borrow(byte, data_loc, data_size), nodes: !$X.xml_node_list(data_size, nodes_size),
   label_buffer: !$A.arr(byte, label_loc, LABEL_MAX), label_len: int label_len): [new_len:nat | new_len <= LABEL_MAX] int new_len =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => _gather_nodes(data, rest, label_buffer, _gather_node(data, node, label_buffer, label_len))
  | $X.xml_nodes_nil() => label_len

and _gather_node {data_loc,label_loc:agz}{data_size:pos}{node_size:pos}{label_len:nat | label_len <= LABEL_MAX} .<node_size, 0>.
  (data: !$A.borrow(byte, data_loc, data_size), node: !$X.xml_node(data_size, node_size),
   label_buffer: !$A.arr(byte, label_loc, LABEL_MAX), label_len: int label_len): [new_len:nat | new_len <= LABEL_MAX] int new_len =
  case+ node of
  | $X.xml_text(text_offset, text_len) => _copy_text(data, text_offset, text_len, 0, label_buffer, label_len)
  | $X.xml_element(_, _, _, children) => _gather_nodes(data, children, label_buffer, label_len)

(* The text of the first child element of nodes named element_name,
   added to the label label_buffer[0, label_len) *)
fun _child_text {data_loc,label_loc:agz}{data_size:pos}{nodes_size:nat}{element_name_len:pos}{label_len:nat | label_len <= LABEL_MAX} .<nodes_size>.
  (data: !$A.borrow(byte, data_loc, data_size), nodes: !$X.xml_node_list(data_size, nodes_size), element_name: &(@[char][element_name_len]), element_name_len: int element_name_len,
   label_buffer: !$A.arr(byte, label_loc, LABEL_MAX), label_len: int label_len): [new_len:nat | new_len <= LABEL_MAX] int new_len =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, _, children) =>
       if xml_name_eq(data, name_offset, name_len, element_name, element_name_len) then _gather_nodes(data, children, label_buffer, label_len)
       else _child_text(data, rest, element_name, element_name_len, label_buffer, label_len)
     | $X.xml_text(_, _) => _child_text(data, rest, element_name, element_name_len, label_buffer, label_len))
  | $X.xml_nodes_nil() => label_len

(* The attribute attribute_name of the first child element of nodes named
   element_name *)
fun _child_attr {data_loc:agz}{data_size:pos}{nodes_size:nat}{element_name_len,attribute_name_len:pos} .<nodes_size>.
  (data: !$A.borrow(byte, data_loc, data_size), nodes: !$X.xml_node_list(data_size, nodes_size), element_name: &(@[char][element_name_len]), element_name_len: int element_name_len,
   attribute_name: &(@[char][attribute_name_len]), attribute_name_len: int attribute_name_len): xspan(data_size) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, attributes, _) =>
       if xml_name_eq(data, name_offset, name_len, element_name, element_name_len) then find_attr(data, attributes, attribute_name, attribute_name_len)
       else _child_attr(data, rest, element_name, element_name_len, attribute_name, attribute_name_len)
     | $X.xml_text(_, _) => _child_attr(data, rest, element_name, element_name_len, attribute_name, attribute_name_len))
  | $X.xml_nodes_nil() => xspan_none()

(* The label of a nav <li>: the text of its <a>, else of its <span> *)
fn _li_label {data_loc,label_loc:agz}{data_size:pos}{nodes_size:nat}
  (data: !$A.borrow(byte, data_loc, data_size), children: !$X.xml_node_list(data_size, nodes_size),
   label_buffer: !$A.arr(byte, label_loc, LABEL_MAX)): [label_len:nat | label_len <= LABEL_MAX] int label_len = let
  var _c_a = @[char][1]('a')
  var _c_span = @[char][4]('s', 'p', 'a', 'n')
  val label_len = _child_text(data, children, _c_a, 1, label_buffer, 0)
in
  if label_len > 0 then label_len else _child_text(data, children, _c_span, 4, label_buffer, 0)
end

(* An entry with the label label_buffer[0, label_len) (a placeholder
   when it is empty), level level and href href, onto entries; frees
   label_buffer *)
fn _entry {label_loc:agz}{data_size:pos}{label_len:nat | label_len <= LABEL_MAX}{count:nat}
  (label_buffer: $A.arr(byte, label_loc, LABEL_MAX), label_len: int label_len, level: Int, href: xspan(data_size), entries: raw(data_size, count)): raw(data_size, count + 1) = let
  val level = (if level < 0 then 0 else if level > 3 then 3 else level): [clamped:nat | clamped <= 3] int clamped
  (* trailing space *)
  val label_len = (if label_len > 0 then (if byte2int0($A.get<byte>(label_buffer, label_len - 1)) = 32 then label_len - 1 else label_len) else label_len): [trimmed:nat | trimmed <= LABEL_MAX] int trimmed
  val @(href_offset, href_len) = (case+ href of
    | ~xspan_at(span_offset, span_len) => @(span_offset, span_len)
    | ~xspan_none() => @(0, 0)): [span_offset,span_len:nat | span_offset + span_len <= data_size] @(int span_offset, int span_len)
in
  if label_len <= 0 then let
    val () = $A.free<byte>(label_buffer)
    val label_bytes = $A.alloc<byte>(8)
    val () = $A.write_text(label_bytes, 0, $A.text_lit("Untitled"), 8)
  in raw_cons(label_bytes, 8, level, href_offset, href_len, entries) end
  else let
    val label_bytes = $A.alloc<byte>(label_len)
    val label_buffer = $S.copy_arr_region(label_buffer, 0, LABEL_MAX, label_bytes, label_len, label_len)
    val () = $A.free<byte>(label_buffer)
  in raw_cons(label_bytes, label_len, level, href_offset, href_len, entries) end
end

(* The entries of nodes, onto entries (newest first): the <li> of a nav
   whose epub:type has toc (mode 0), or each navPoint (mode 1); each one
   level deeper than the entry it is in. With page_list, the print pages
   instead: the <li> of a nav whose epub:type has page-list, or each
   pageTarget *)
fun _walk_nodes {data_loc:agz}{data_size:pos}{nodes_size:nat}{count:nat} .<nodes_size, 1>.
  (data: !$A.borrow(byte, data_loc, data_size), nodes: !$X.xml_node_list(data_size, nodes_size),
   ncx: bool, page_list: bool, in_toc: bool, level: Int, entries: raw(data_size, count)): [new_count:nat] raw(data_size, new_count) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    _walk_nodes(data, rest, ncx, page_list, in_toc, level, _walk_node(data, node, ncx, page_list, in_toc, level, entries))
  | $X.xml_nodes_nil() => entries

and _walk_node {data_loc:agz}{data_size:pos}{node_size:pos}{count:nat} .<node_size, 0>.
  (data: !$A.borrow(byte, data_loc, data_size), node: !$X.xml_node(data_size, node_size),
   ncx: bool, page_list: bool, in_toc: bool, level: Int, entries: raw(data_size, count)): [new_count:nat] raw(data_size, new_count) =
  case+ node of
  | $X.xml_text(_, _) => entries
  | $X.xml_element(name_offset, name_len, attributes, children) => let
      var _c_nav = @[char][3]('n', 'a', 'v')
      var _c_li = @[char][2]('l', 'i')
      var _c_a = @[char][1]('a')
      var _c_span = @[char][4]('s', 'p', 'a', 'n')
      var _c_href = @[char][4]('h', 'r', 'e', 'f')
      var _c_epub_type = @[char][9]('e', 'p', 'u', 'b', ':', 't', 'y', 'p', 'e')
      var _c_toc = @[char][3]('t', 'o', 'c')
      var _c_nav_point = @[char][8]('n', 'a', 'v', 'P', 'o', 'i', 'n', 't')
      var _c_nav_label = @[char][8]('n', 'a', 'v', 'L', 'a', 'b', 'e', 'l')
      var _c_content = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
      var _c_src = @[char][3]('s', 'r', 'c')
      var _c_page_list = @[char][8]('p', 'a', 'g', 'e', 'L', 'i', 's', 't')
      var _c_page_target = @[char][10]('p', 'a', 'g', 'e', 'T', 'a', 'r', 'g', 'e', 't')
      var _c_page_list_type = @[char][9]('p', 'a', 'g', 'e', '-', 'l', 'i', 's', 't')
    in
      if ncx then
        (if (if page_list then false else xml_name_eq(data, name_offset, name_len, _c_nav_point, 8)) then let
           val label_buffer = $A.alloc<byte>(LABEL_MAX)
           val label_len = _child_text(data, children, _c_nav_label, 8, label_buffer, 0)
           val href = _child_attr(data, children, _c_content, 7, _c_src, 3)
           val entries = _entry(label_buffer, label_len, level, href, entries)
         in _walk_nodes(data, children, ncx, page_list, in_toc, level + 1, entries) end
         else if (if page_list then xml_name_eq(data, name_offset, name_len, _c_page_target, 10) else false) then let
           val label_buffer = $A.alloc<byte>(LABEL_MAX)
           val label_len = _child_text(data, children, _c_nav_label, 8, label_buffer, 0)
           val href = _child_attr(data, children, _c_content, 7, _c_src, 3)
         in _entry(label_buffer, label_len, 0, href, entries) end
         else if (if page_list then false else xml_name_eq(data, name_offset, name_len, _c_page_list, 8)) then entries
         else _walk_nodes(data, children, ncx, page_list, in_toc, level, entries))
      else if xml_name_eq(data, name_offset, name_len, _c_nav, 3) then
        (case+ find_attr(data, attributes, _c_epub_type, 9) of
         | ~xspan_at(type_offset, type_len) =>
           if (if page_list then span_has(data, type_offset, type_len, _c_page_list_type, 9) else span_has(data, type_offset, type_len, _c_toc, 3)) then
             _walk_nodes(data, children, ncx, page_list, true, level, entries)
           else entries
         | ~xspan_none() => entries)
      else if (if in_toc then xml_name_eq(data, name_offset, name_len, _c_li, 2) else false) then let
        val label_buffer = $A.alloc<byte>(LABEL_MAX)
        val label_len = _li_label(data, children, label_buffer)
        val href = _child_attr(data, children, _c_a, 1, _c_href, 4)
        val entries = _entry(label_buffer, label_len, level, href, entries)
      in _walk_nodes(data, children, ncx, page_list, in_toc, level + 1, entries) end
      else _walk_nodes(data, children, ncx, page_list, in_toc, level, entries)
    end

(* The chapter the href data[href_offset, href_offset + path_len) names,
   after the document's directory (the first dir_len bytes of its name,
   at name_offset in the file); the chapter of the document itself when
   path_len is 0 *)
fn _chapter_of {file_size:pos}{name_offset,dir_len:nat | name_offset + dir_len <= file_size; dir_len < 65536}{data_loc:agz}{data_size:pos}{href_offset,path_len:nat | href_offset + path_len <= data_size}
  (serial: int, file_size: int file_size, name_offset: int name_offset, dir_len: int dir_len, self: int,
   data: !$A.borrow(byte, data_loc, data_size), data_size: int data_size, href_offset: int href_offset, path_len: int path_len): [chapter:int | chapter >= ~1] int chapter =
  if path_len <= 0 then book_chapter_of(serial, self)
  (* an href of 64 KiB or more names no zip entry: the book's data,
     checked here *)
  else if path_len >= 65536 then ~1
  else let
    val path_size = dir_len + path_len
    val path = $A.alloc<byte>(path_size)
    val _ = book_read(serial, file_size, name_offset, path, dir_len)
    val () = $S.copy_from_borrow(data, href_offset, data_size, path, dir_len, path_size, path_len)
    val normal_len = path_norm(path, path_size)
  in
    case+ _find_entry(serial, file_size, path, path_size, normal_len) of
    | ~EntryHit(_, _, _, entry_name_offset, _) => book_chapter_of(serial, entry_name_offset)
    | ~EntryMiss() => ~1
  end

(* The length of the href data[href_offset, href_offset + href_len)
   before its '#' *)
fn _href_end {data_loc:agz}{data_size:pos}{href_offset,href_len:nat | href_offset + href_len <= data_size}
  (data: !$A.borrow(byte, data_loc, data_size), href_offset: int href_offset, href_len: int href_len): [path_len:nat | path_len <= href_len] int path_len =
  if href_len > 0 then src_end(data, href_offset, href_len) else 0

(* The length of the fragment after the '#' at path_len of an href of
   href_len bytes: 0 when there is none, or it is over FRAGMENT_MAX bytes *)
fn _fragment_len {href_len,path_len:nat | path_len <= href_len} (href_len: int href_len, path_len: int path_len): [fragment_len:nat | fragment_len <= FRAGMENT_MAX; fragment_len == 0 || fragment_len == href_len - path_len - 1] int fragment_len =
  if href_len - path_len - 1 <= 0 then 0
  else if href_len - path_len - 1 > FRAGMENT_MAX then 0
  else href_len - path_len - 1

(* fragment_bytes[0, fragment_len) := data[href_offset + path_len + 1,
   href_offset + path_len + 1 + fragment_len) *)
fn _fragment_copy {data_loc,fragment_loc:agz}{data_size:pos}{href_offset,path_len,fragment_len:nat | fragment_len == 0 || href_offset + path_len + 1 + fragment_len <= data_size}
  (data: !$A.borrow(byte, data_loc, data_size), data_size: int data_size, href_offset: int href_offset, path_len: int path_len, fragment_bytes: !$A.arr(byte, fragment_loc, fragment_len + 1), fragment_len: int fragment_len): void =
  if fragment_len > 0 then $S.copy_from_borrow(data, href_offset + path_len + 1, data_size, fragment_bytes, 0, fragment_len + 1, fragment_len) else ()

(* The entries raw_entries, resolved onto entries (so in document order
   again) *)
fun _resolve {file_size:pos}{name_offset,dir_len:nat | name_offset + dir_len <= file_size; dir_len < 65536}{data_loc:agz}{data_size:pos}{raw_count,count:nat} .<raw_count>.
  (serial: int, file_size: int file_size, name_offset: int name_offset, dir_len: int dir_len, self: int,
   data: !$A.borrow(byte, data_loc, data_size), data_size: int data_size, raw_entries: raw(data_size, raw_count), entries: toc(count), count: int count): [total:nat] @(toc(total), int total) =
  case+ raw_entries of
  | ~raw_nil() => @(entries, count)
  | ~raw_cons(label_bytes, label_len, level, href_offset, href_len, rest) => let
      val path_len = _href_end(data, href_offset, href_len)
      val chapter = _chapter_of(serial, file_size, name_offset, dir_len, self, data, data_size, href_offset, path_len)
      val fragment_len = _fragment_len(href_len, path_len)
      val fragment_bytes = $A.alloc<byte>(fragment_len + 1)
      val () = _fragment_copy(data, data_size, href_offset, path_len, fragment_bytes, fragment_len)
    in _resolve(serial, file_size, name_offset, dir_len, self, data, data_size, rest, toc_cons(label_bytes, label_len, level, chapter, fragment_bytes, fragment_len, entries), count + 1) end

(* The length of the directory part of the name [name_offset,
   name_offset + name_len) *)
fn _dir_len {file_size:pos}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
  (serial: int, file_size: int file_size, name_offset: int name_offset, name_len: int name_len): [dir_len:nat | dir_len <= name_len] int dir_len = let
  val name = $A.alloc<byte>(name_len)
  val _ = book_read(serial, file_size, name_offset, name, name_len)
  val dir_len = path_dir_end(name, name_len)
  val () = $A.free<byte>(name)
in dir_len end

(* Reads the entries of book serial from the document toc_locate found;
   the promise resolves with their count (0 when there is none) *)
#pub fn toc_build (serial: int): $P.promise(int, $P.Chained)

implement toc_build (serial) = let
  val () = _contents_put(TocCell(toc_nil(), 0))
  val () = _pages_put(TocCell(toc_nil(), 0))
in
  case+ _source_take() of
  | ~TocNone() => $P.ret<int>(0)
  | ~TocSource(file_size, data_offset, data_size, method, name_offset, name_len, ncx) =>
    (case+ piece_new(data_size) of
     | ~NoPiece() => $P.ret<int>(0)
     | ~Piece(compressed_owner, compressed) => let
         val _ = book_read(serial, file_size, data_offset, compressed, data_size)
         val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
         val decompressed = decompress(compressed_bytes, data_size, method)
         val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
         val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
         val decompressed = $P.vow(decompressed)
       in
         $P.and_then<Int><int>(decompressed, llam(handle) =>
           case+ take_content(handle) of
           | ~NoContentBytes() => $P.ret<int>(0)
           | ~ContentBytes(content_owner, content, content_size) => let
               val @(content_frozen, content_bytes) = $A.freeze<byte>(content)
               val nodes = $X.parse_document(content_bytes, content_size)
               val contents_raw = _walk_nodes(content_bytes, nodes, ncx, false, false, 0, raw_nil())
               val pages_raw = _walk_nodes(content_bytes, nodes, ncx, true, false, 0, raw_nil())
               val () = $X.free_nodes(nodes)
               val dir_len = _dir_len(serial, file_size, name_offset, name_len)
               val @(contents, contents_count) = _resolve(serial, file_size, name_offset, dir_len, name_offset, content_bytes, content_size, contents_raw, toc_nil(), 0)
               val @(pages, pages_count) = _resolve(serial, file_size, name_offset, dir_len, name_offset, content_bytes, content_size, pages_raw, toc_nil(), 0)
               val () = _pages_put(TocCell(pages, pages_count))
               val () = $A.drop<byte>(content_frozen, content_bytes)
               val () = piece_free(content_owner, $A.thaw<byte>(content_frozen))
               val () = _contents_put(TocCell(contents, contents_count))
             in $P.ret<int>(contents_count) end)
       end)
end

(* ============================================================
   Showing it
   ============================================================ *)

(* The index of the entry of chapter chapter the reader is in: the first
   one of the chapter, else the last one before it; -1 when none is *)
fun _current {count:nat} .<count>. (entries: !toc(count), chapter: int, i: int, best: int): int =
  case+ entries of
  | toc_nil() => best
  | @toc_cons(_, _, _, entry_chapter, _, _, rest) =>
    if entry_chapter = chapter then let prval () = fold@(entries) in i end
    else if entry_chapter < chapter then let
      val found = _current(rest, chapter, i + 1, (if entry_chapter >= 0 then i else best))
      prval () = fold@(entries)
    in found end
    else let prval () = fold@(entries) in best end

fn _level_class {level:nat | level <= 3} (level: int level): [class_len:pos | class_len < 256] string class_len =
  if level = 0 then "pi" else if level = 1 then "pi pi1" else if level = 2 then "pi pi2" else "pi pi3"

(* A row of the list: button toc-row<i> with the label
   label_bytes[0, label_len) *)
fn _row {label_loc:agz}{label_size:pos}{label_len:pos | label_len <= LABEL_MAX; label_len <= label_size}{i:nat}{level:nat | level <= 3}
  (i: int i, level: int level, label_bytes: !$A.arr(byte, label_loc, label_size), label_len: int label_len, current: bool): void = let
  val @(row_id, row_id_len) = nid_make("toc-row", i)
  val () = ui_btn_n("contents-list", row_id, row_id_len, _level_class(level))
  val @(row_id, row_id_len) = nid_make("toc-row", i)
  val () = (if current then ui_attr_n(row_id, row_id_len, ACurrent, "true") else ui_attr_n(row_id, row_id_len, ACurrent, "false"))
  val label_copy = $A.alloc<byte>(label_len)
  val () = _copy_bytes(label_bytes, label_copy, label_len, 0)
  val @(row_id, row_id_len) = nid_make("toc-row", i)
in ui_text_n_buf(row_id, row_id_len, label_copy, label_len) end

fun _rows {count:nat}{i:nat} .<count>. (entries: !toc(count), i: int i, current: int): void =
  case+ entries of
  | toc_nil() => ()
  | @toc_cons(label_bytes, label_len, level, _, _, _, rest) => let
      val () = _row(i, level, label_bytes, label_len, i = current)
      val () = _rows(rest, i + 1, current)
      prval () = fold@(entries)
    in end

(* "Chapter " and number *)
fn _chapter_label {number:nat} (number: int number): [l:agz][label_len:pos | label_len <= 19] @($A.arr(byte, l, 19), int label_len) = let
  val label_bytes = $A.alloc<byte>(19)
  val () = $A.write_text(label_bytes, 0, $A.text_lit("Chapter "), 8)
  val label_len = $S.int_to_str(label_bytes, 8, 19, number)
in @(label_bytes, label_len) end

(* One row per chapter, for a book with no table of contents *)
fun _chapter_rows {i,chapter_count:nat} .<max(chapter_count - i, 0)>. (i: int i, chapter_count: int chapter_count, current: int): void =
  if i >= chapter_count then ()
  else let
    val @(label_bytes, label_len) = _chapter_label(i + 1)
    val () = _row(i, 0, label_bytes, label_len, i = current)
    val () = $A.free<byte>(label_bytes)
  in _chapter_rows(i + 1, chapter_count, current) end

(* Fills the contents list: the book's entries, the reader being in
   chapter chapter (from 0) of its chapter_count; one row per chapter
   when the book has no entries *)
#pub fn toc_render {chapter_count:nat} (chapter: int, chapter_count: int chapter_count): void

implement toc_render (chapter, chapter_count) = let
  val () = ui_clear("contents-list")
  val cell = _contents_take()
  val+ @TocCell(entries, count) = cell
  val current = _current(entries, chapter, 0, ~1)
  val () = (if count > 0 then _rows(entries, 0, current) else _chapter_rows(0, chapter_count, chapter))
  prval () = fold@(cell)
in _contents_put(cell) end

(* Where entry i leads *)
#pub datavtype toc_dest =
  | {l:agz}{f:nat | f <= 200} TocDest of (Int, $A.arr(byte, l, f + 1), int f)
  | TocNoDest of ()

fun _dest_at {count:nat} .<count>. (entries: !toc(count), i: int): toc_dest =
  case+ entries of
  | toc_nil() => TocNoDest()
  | @toc_cons(_, _, _, chapter, fragment_bytes, fragment_len, rest) =>
    if i > 0 then let
      val dest = _dest_at(rest, i - 1)
      prval () = fold@(entries)
    in dest end
    else if chapter < 0 then let prval () = fold@(entries) in TocNoDest() end
    else let
      val fragment_copy = $A.alloc<byte>(fragment_len + 1)
      val () = _copy_bytes(fragment_bytes, fragment_copy, fragment_len + 1, 0)
      val dest = TocDest(chapter, fragment_copy, fragment_len)
      prval () = fold@(entries)
    in dest end

(* The chapter and fragment row i of the list leads to *)
#pub fn toc_dest_of (i: Int): toc_dest

implement toc_dest_of (i) = let
  val cell = _contents_take()
  val+ @TocCell(entries, count) = cell
  val dest = (if count > 0 then _dest_at(entries, i)
              else if i >= 0 then let val no_fragment = $A.alloc<byte>(1) in TocDest(i, no_fragment, 0) end
              else TocNoDest()): toc_dest
  prval () = fold@(cell)
  val () = _contents_put(cell)
in dest end

(* ============================================================
   Which chapter of how many: by the contents' top-level entries
   ============================================================ *)

(* The top-level entries of entries (top_count of them before), and the
   ordinal (from 1) of the last one at or before chapter chapter: its
   entry leads to a chapter at or before chapter; 0 when none does *)
fun _top_entries {count:nat} .<count>. (entries: !toc(count), chapter: int, top_count: int, ordinal: int): @(int, int) =
  case+ entries of
  | toc_nil() => @(top_count, ordinal)
  | @toc_cons(_, _, level, entry_chapter, _, _, rest) =>
    if level = 0 then let
      val new_ordinal = (if entry_chapter >= 0 then (if entry_chapter <= chapter then top_count + 1 else ordinal) else ordinal): int
      val result = _top_entries(rest, chapter, top_count + 1, new_ordinal)
      prval () = fold@(entries)
    in result end
    else let
      val result = _top_entries(rest, chapter, top_count, ordinal)
      prval () = fold@(entries)
    in result end

(* The chapter chapter (from 0) is in, as the contents' top-level entry
   it is under (from 1; 0 before the first), and how many there are *)
#pub fn toc_chapter_of (chapter: int): @(int, int)

implement toc_chapter_of (chapter) = let
  val cell = _contents_take()
  val+ @TocCell(entries, _) = cell
  val @(top_count, ordinal) = _top_entries(entries, chapter, 0, 0)
  prval () = fold@(cell)
  val () = _contents_put(cell)
in @(ordinal, top_count) end

(* ============================================================
   The print pages
   ============================================================ *)

(* How many print pages the book lists *)
#pub fn toc_pages_count (): int

implement toc_pages_count () = let
  val cell = _pages_take()
  val+ @TocCell(_, count) = cell
  val pages_count = count
  prval () = fold@(cell)
  val () = _pages_put(cell)
in pages_count end

(* Print page i's row: a button page-row<i> in pages-list, labelled with the page *)
fn _page_row {label_loc:agz}{label_size:pos}{label_len:pos | label_len <= LABEL_MAX; label_len <= label_size}{i:nat}
  (i: int i, label_bytes: !$A.arr(byte, label_loc, label_size), label_len: int label_len): void = let
  val @(row_id, row_id_len) = nid_make("page-row", i)
  val () = ui_btn_n("pages-list", row_id, row_id_len, _level_class(0))
  val label_copy = $A.alloc<byte>(label_len)
  val () = _copy_bytes(label_bytes, label_copy, label_len, 0)
  val @(row_id, row_id_len) = nid_make("page-row", i)
in ui_text_n_buf(row_id, row_id_len, label_copy, label_len) end

fun _page_rows {count:nat}{i:nat} .<count>. (entries: !toc(count), i: int i): void =
  case+ entries of
  | toc_nil() => ()
  | @toc_cons(label_bytes, label_len, _, _, _, _, rest) => let
      val () = _page_row(i, label_bytes, label_len)
      val () = _page_rows(rest, i + 1)
      prval () = fold@(entries)
    in end

(* The print pages, listed in the contents panel's Pages tab *)
#pub fn toc_pages_render (): void

implement toc_pages_render () = let
  val () = ui_clear("pages-list")
  val cell = _pages_take()
  val+ @TocCell(entries, _) = cell
  val () = _page_rows(entries, 0)
  prval () = fold@(cell)
in _pages_put(cell) end

(* Where print page i is *)
#pub fn toc_page_dest_of (i: Int): toc_dest

implement toc_page_dest_of (i) = let
  val cell = _pages_take()
  val+ @TocCell(entries, _) = cell
  val dest = _dest_at(entries, i)
  prval () = fold@(cell)
  val () = _pages_put(cell)
in dest end

(* The label of entry i *)
fun _title_at {count:nat}{id_len:pos | id_len < 256} .<count>. (entries: !toc(count), i: int, id: string id_len): bool =
  case+ entries of
  | toc_nil() => false
  | @toc_cons(label_bytes, label_len, _, _, _, _, rest) =>
    if i > 0 then let
      val shown = _title_at(rest, i - 1, id)
      prval () = fold@(entries)
    in shown end
    else let
      val label_copy = $A.alloc<byte>(label_len)
      val () = _copy_bytes(label_bytes, label_copy, label_len, 0)
      val () = ui_text_buf(id, label_copy, label_len)
      prval () = fold@(entries)
    in true end

(* Shows chapter chapter's title (from 0) as the text of element id: its
   entry's label, else "Chapter" and its number *)
#pub fn toc_title_in {chapter:nat}{id_len:pos | id_len < 256} (id: string id_len, chapter: int chapter): void

implement toc_title_in (id, chapter) = let
  val cell = _contents_take()
  val+ @TocCell(entries, _) = cell
  val current = _current(entries, chapter, 0, ~1)
  val shown = _title_at(entries, current, id)
  prval () = fold@(cell)
  val () = _contents_put(cell)
in
  if shown then ()
  else let
    val @(label_bytes, label_len) = _chapter_label(chapter + 1)
  in ui_text_buf(id, label_bytes, label_len) end
end

(* The chapter's title in the reader's top bar *)
#pub fn toc_title {chapter:nat} (chapter: int chapter): void

implement toc_title (chapter) = toc_title_in("chapter-title", chapter)

(* The label of the entry at index i of entries, copied; none when there
   is no such entry *)
datavtype label =
  | {l:agz}{label_len:pos | label_len <= LABEL_MAX} Label of ($A.arr(byte, l, label_len), int label_len)
  | NoLabel of ()

fun _label_at {count:nat} .<count>. (entries: !toc(count), i: int): label =
  case+ entries of
  | toc_nil() => NoLabel()
  | @toc_cons(label_bytes, label_len, _, _, _, _, rest) =>
    if i > 0 then let
      val found = _label_at(rest, i - 1)
      prval () = fold@(entries)
    in found end
    else let
      val label_copy = $A.alloc<byte>(label_len)
      val () = _copy_bytes(label_bytes, label_copy, label_len, 0)
      val copy_len = label_len
      prval () = fold@(entries)
    in Label(label_copy, copy_len) end

(* Chapter chapter's title (from 0), as toc_title shows it, in a new
   array *)
#pub fn toc_label_of {chapter:nat} (chapter: int chapter): [l:agz][label_len:pos | label_len <= 200] @($A.arr(byte, l, label_len), int label_len)

implement toc_label_of (chapter) = let
  val cell = _contents_take()
  val+ @TocCell(entries, _) = cell
  val current = _current(entries, chapter, 0, ~1)
  val found = _label_at(entries, current)
  prval () = fold@(cell)
  val () = _contents_put(cell)
in
  case+ found of
  | ~Label(label_bytes, label_len) => @(label_bytes, label_len)
  | ~NoLabel() => let
      val @(number_label, label_len) = _chapter_label(chapter + 1)
      val label_copy = $A.alloc<byte>(label_len)
      val () = _copy_bytes(number_label, label_copy, label_len, 0)
      val () = $A.free<byte>(number_label)
    in @(label_copy, label_len) end
end

end (* #target wasm *)
