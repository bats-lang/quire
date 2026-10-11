(* epub_xml -- EPUB/XML parsing helpers and array utilities *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use result as R
#use str as S
#use xml-tree as X

(* ============================================================
   Proven reads
   ============================================================ *)

(* A position in a buffer; indexed so a read at it can be proven. *)
#pub typedef pos_t = [position:int] int position

(* ============================================================
   Array to text conversion
   ============================================================ *)

fun _arr_to_text_loop
  {l:agz}{n:pos}{position:nat | position <= n} .<n - position>.
  (source: !$A.arr(byte, l, n), source_len: int n,
   builder: $A.text_builder(n, position), position: int position): $A.text_builder(n, n) =
  if position >= source_len then builder
  else let
    val byte_value = byte2int0($A.get<byte>(source, position))
    val builder = $A.text_putc(builder, position, $AR.byte_of_char(int2char0(byte_value)))
  in _arr_to_text_loop(source, source_len, builder, position + 1) end

#pub fn arr_to_text
  {l:agz}{n:pos}
  (source: !$A.arr(byte, l, n), source_len: int n): $A.text(n)

implement arr_to_text{l}{n}(source, source_len) = let
  val builder = $A.text_build(source_len)
  val builder = _arr_to_text_loop(source, source_len, builder, 0)
in $A.text_done(builder) end

(* ============================================================
   Spans of a parsed document
   ============================================================ *)

(* A span [offset, offset + span_len) of an n-byte document (from xml-tree, which proves
   it inside the document), or none. Linear: a datatype's cell is never
   freed (there is no GC), so each span is consumed by a ~ pattern or by
   xspan_free. *)
#pub datavtype xspan(n:int) =
  | {offset,span_len:nat | offset + span_len <= n} xspan_at(n) of (int offset, int span_len)
  | xspan_none(n) of ()

#pub fn xspan_free {n:int} (span: xspan(n)): void

implement xspan_free (span) =
  case+ span of
  | ~xspan_at(_, _) => ()
  | ~xspan_none() => ()

(* ============================================================
   XML name matching
   ============================================================ *)

fun _match_chars {l:agz}{n:pos}{offset:nat}{pattern_len:pos | offset + pattern_len <= n}{position:nat | position <= pattern_len} .<pattern_len - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, pattern: &(@[char][pattern_len]), pattern_len: int pattern_len, position: int position): bool =
  if position >= pattern_len then true
  else if byte2int0($A.read<byte>(data, offset + position)) <> char2int0(pattern.[position]) then false
  else _match_chars(data, offset, pattern, pattern_len, position + 1)

(* Whether the name at [offset, offset + name_len) is pattern *)
#pub fn xml_name_eq
  {l:agz}{n:pos}{offset,name_len:nat | offset + name_len <= n}{pattern_len:pos}
  (data: !$A.borrow(byte, l, n), offset: int offset, name_len: int name_len,
   pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool

implement xml_name_eq(data, offset, name_len, pattern, pattern_len) =
  if name_len <> pattern_len then false
  else _match_chars(data, offset, pattern, pattern_len, 0)

(* ============================================================
   XML attribute lookup (internal)
   ============================================================ *)

fun _find_attr_value
  {l:agz}{n:pos}{attr_count:nat}{attr_name_len:pos} .<attr_count>.
  (data: !$A.borrow(byte, l, n),
   attrs: !$X.xml_attr_list(n, attr_count),
   attr_name: &(@[char][attr_name_len]), attr_name_len: int attr_name_len): xspan(n) =
  case+ attrs of
  | $X.xml_attrs_cons(each_name_offset, each_name_len, value_offset, value_len, rest) =>
    if xml_name_eq(data, each_name_offset, each_name_len, attr_name, attr_name_len) then xspan_at(value_offset, value_len)
    else _find_attr_value(data, rest, attr_name, attr_name_len)
  | $X.xml_attrs_nil() => xspan_none()

(* The value of the attribute named attr_name among attrs, when there
   is one *)
#pub fn find_attr
  {l:agz}{n:pos}{attr_count:nat}{attr_name_len:pos}
  (data: !$A.borrow(byte, l, n),
   attrs: !$X.xml_attr_list(n, attr_count),
   attr_name: &(@[char][attr_name_len]), attr_name_len: int attr_name_len): xspan(n)

implement find_attr(data, attrs, attr_name, attr_name_len) = _find_attr_value(data, attrs, attr_name, attr_name_len)

(* ============================================================
   Container.xml: find rootfile full-path
   ============================================================ *)

fun _rootfile_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _rootfile_node(data, node) of
     | ~xspan_none() => _rootfile_nodes(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _rootfile_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var rootfile_chars = @[char][8]('r', 'o', 'o', 't', 'f', 'i', 'l', 'e')
    var full_path_chars = @[char][9]('f', 'u', 'l', 'l', '-', 'p', 'a', 't', 'h')
  in
    if xml_name_eq(data, tag_offset, tag_len, rootfile_chars, 8) then
      _find_attr_value(data, attrs, full_path_chars, 9)
    else _rootfile_nodes(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The full-path attribute of container.xml's first rootfile *)
#pub fn walk_rootfile_nodes
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n)

implement walk_rootfile_nodes(data, nodes) = _rootfile_nodes(data, nodes)

(* ============================================================
   OPF: extract title/author from metadata
   ============================================================ *)

fun _opf_metadata_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size),
   title: xspan(n), author: xspan(n)): @(xspan(n), xspan(n)) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(next_title, next_author) = _opf_metadata_node(data, node, title, author)
    in _opf_metadata_nodes(data, rest, next_title, next_author) end
  | $X.xml_nodes_nil() => @(title, author)

and _opf_metadata_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size),
   title: xspan(n), author: xspan(n)): @(xspan(n), xspan(n)) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, _, children) => let
    var title_chars = @[char][8]('d', 'c', ':', 't', 'i', 't', 'l', 'e')
    var creator_chars = @[char][10]('d', 'c', ':', 'c', 'r', 'e', 'a', 't', 'o', 'r')
  in
    if xml_name_eq(data, tag_offset, tag_len, title_chars, 8) then
      (* the first dc:title names the book (EPUB 3.3 §5.4: the first
         title is the main one, w3c/epub-tests pkg-title-order); a later
         one is left *)
      (case+ title of
       | ~xspan_none() => @(_get_first_text(children), author)
       | ~xspan_at(title_offset, title_len) => @(xspan_at(title_offset, title_len), author))
    else if xml_name_eq(data, tag_offset, tag_len, creator_chars, 10) then
      (* and the first dc:creator is the author (pkg-creator-order) *)
      (case+ author of
       | ~xspan_none() => @(title, _get_first_text(children))
       | ~xspan_at(author_offset, author_len) => @(title, xspan_at(author_offset, author_len)))
    else _opf_metadata_nodes(data, children, title, author)
  end
  | $X.xml_text(_, _) => @(title, author)

and _get_first_text
  {n:int}{tree_size:nat} .<tree_size, 0>.
  (children: !$X.xml_node_list(n, tree_size)): xspan(n) =
  case+ children of
  | $X.xml_nodes_cons(node, _) =>
    (case+ node of
     | $X.xml_text(text_offset, text_len) => xspan_at(text_offset, text_len)
     | $X.xml_element(_, _, _, _) => xspan_none())
  | $X.xml_nodes_nil() => xspan_none()

(* The text of the OPF's first dc:title and first dc:creator *)
#pub fn walk_opf_metadata
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): @(xspan(n), xspan(n))

implement walk_opf_metadata(data, nodes) =
  _opf_metadata_nodes(data, nodes, xspan_none(), xspan_none())

(* ============================================================
   OPF: the direction of the title and of the author (the `dir`
   attribute of dc:title, dc:creator and the package, EPUB 3.3 §5.2.1.1)
   ============================================================ *)

(* The `dir` of the first element named name among nodes and below: whether
   there is such an element, and its attribute's value if it has one *)
fun _element_dir_nodes
  {l:agz}{n:pos}{tree_size:nat}{name_len:pos} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size),
   name: &(@[char][name_len]), name_len: int name_len): @(bool, xspan(n)) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(found, value) = _element_dir_node(data, node, name, name_len)
    in
      if found then @(true, value)
      else let val () = xspan_free(value) in _element_dir_nodes(data, rest, name, name_len) end
    end
  | $X.xml_nodes_nil() => @(false, xspan_none())

and _element_dir_node
  {l:agz}{n:pos}{tree_size:pos}{name_len:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size),
   name: &(@[char][name_len]), name_len: int name_len): @(bool, xspan(n)) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) =>
    if xml_name_eq(data, tag_offset, tag_len, name, name_len) then let
    var dir_chars = @[char][3]('d', 'i', 'r')
    in @(true, _find_attr_value(data, attrs, dir_chars, 3)) end
    else _element_dir_nodes(data, children, name, name_len)
  | $X.xml_text(_, _) => @(false, xspan_none())

(* A direction's code from the value of a `dir` attribute: 0 none or not
   one, 1 ltr, 2 rtl, 3 auto *)
fn _direction_code {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), value: xspan(n)): int =
  case+ value of
  | ~xspan_none() => 0
  | ~xspan_at(offset, span_len) => let
    var ltr_chars = @[char][3]('l', 't', 'r')
    var rtl_chars = @[char][3]('r', 't', 'l')
    var auto_chars = @[char][4]('a', 'u', 't', 'o')
    in
      if xml_name_eq(data, offset, span_len, ltr_chars, 3) then 1
      else if xml_name_eq(data, offset, span_len, rtl_chars, 3) then 2
      else if xml_name_eq(data, offset, span_len, auto_chars, 4) then 3
      else 0
    end

(* The direction of the first element named name: its own `dir`, else the
   package's (root), as a code *)
fn _text_direction {l:agz}{n:pos}{tree_size:nat}{name_len:pos}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), name: &(@[char][name_len]), name_len: int name_len, root: int): int = let
  val @(_, value) = _element_dir_nodes(data, nodes, name, name_len)
  val own = _direction_code(data, value)
in if own > 0 then own else root end

(* The direction of the first dc:title and of the first dc:creator, as
   title + 4 * author, each 0 none, 1 ltr, 2 rtl, 3 auto: the element's own
   `dir`, else the package element's (the suite's pkg-dir_creator-rtl,
   pkg-dir_rtl-root-ltr, pkg-dir_rtl-root-unset, pkg-dir_unset-root-rtl) *)
#pub fn opf_text_directions
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): [code:int] int code

implement opf_text_directions(data, nodes) = let
    var package_chars = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
    var title_chars = @[char][8]('d', 'c', ':', 't', 'i', 't', 'l', 'e')
    var creator_chars = @[char][10]('d', 'c', ':', 'c', 'r', 'e', 'a', 't', 'o', 'r')
  val @(_, root_value) = _element_dir_nodes(data, nodes, package_chars, 7)
  val root = _direction_code(data, root_value)
  val title = _text_direction(data, nodes, title_chars, 8, root)
  val author = _text_direction(data, nodes, creator_chars, 10, root)
in g1ofg0(title + 4 * author) end

(* The text of the OPF's first dc:language *)
fun _opf_language_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val language = _opf_language_node(data, node)
    in
      case+ language of
      | ~xspan_none() => _opf_language_nodes(data, rest)
      | _ => language
    end
  | $X.xml_nodes_nil() => xspan_none()

and _opf_language_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, _, children) => let
    var language_chars = @[char][11]('d', 'c', ':', 'l', 'a', 'n', 'g', 'u', 'a', 'g', 'e')
  in
    if xml_name_eq(data, tag_offset, tag_len, language_chars, 11) then _get_first_text(children)
    else _opf_language_nodes(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

#pub fn opf_language
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n)

implement opf_language(data, nodes) = _opf_language_nodes(data, nodes)

(* ============================================================
   Accessibility metadata (EPUB Accessibility 1.1): the OPF's
   schema.org and dcterms:conformsTo properties, as flags
   ============================================================ *)

(* A book's accessibility metadata, each feature a bit of the flags
   stored with it (MetadataKnown when any of them is in the OPF) *)
#pub datatype a11y_feature =
  | Transformable (* accessibilityFeature displayTransformability *)
  | AlternativeText (* alternativeText *)
  | LongDescription (* longDescription *)
  | SufficientText (* accessModeSufficient textual *)
  | TextualMode (* accessMode textual *)
  | VisualMode (* accessMode visual *)
  | NoHazards (* accessibilityHazard none *)
  | Flashing (* flashing *)
  | MotionSimulation (* motionSimulation *)
  | Sound (* sound *)
  | NoFlashingHazard (* noFlashingHazard *)
  | NoMotionHazard (* noMotionSimulationHazard *)
  | NoSoundHazard (* noSoundHazard *)
  | HazardsUnknown (* unknown *)
  | TableOfContents (* tableOfContents *)
  | TermIndex (* index *)
  | StructuralNavigation (* structuralNavigation *)
  | PageNavigation (* pageNavigation *)
  | MathMarkup (* MathML *)
  | Transcript (* transcript *)
  | Captions (* captions or closedCaptions *)
  | MetadataKnown (* any of these in the OPF *)

(* The WCAG level conformsTo names *)
#pub datatype wcag_level = NoLevel | LevelA | LevelAA | LevelAAA

(* A feature's bit in the stored flags: the one place it is made *)
#pub fn a11y_bit (feature: a11y_feature): int
implement a11y_bit (feature) =
  case+ feature of
  | Transformable() => 1
  | AlternativeText() => 2
  | LongDescription() => 4
  | SufficientText() => 8
  | TextualMode() => 16
  | VisualMode() => 32
  | NoHazards() => 64
  | Flashing() => 128
  | MotionSimulation() => 256
  | Sound() => 512
  | NoFlashingHazard() => 1024
  | NoMotionHazard() => 2048
  | NoSoundHazard() => 4096
  | HazardsUnknown() => 8192
  | TableOfContents() => 16384
  | TermIndex() => 32768
  | StructuralNavigation() => 65536
  | PageNavigation() => 131072
  | MathMarkup() => 262144
  | Transcript() => 524288
  | Captions() => 1048576
  | MetadataKnown() => 2097152

(* A level's bits in the stored flags: times 4194304, 1 A, 2 AA, 3 AAA *)
fn _level_bits (level: wcag_level): int =
  case+ level of NoLevel() => 0 | LevelA() => 4194304 | LevelAA() => 8388608 | LevelAAA() => 12582912

(* Whether the flags have feature *)
#pub fn a11y_has (flags: int, feature: a11y_feature): bool
implement a11y_has (flags, feature) = $AR.band_int_int(flags, a11y_bit(feature)) <> 0

(* The WCAG level the flags hold *)
#pub fn a11y_level (flags: int): wcag_level
implement a11y_level (flags) = let
  val level = $AR.band_int_int(flags / 4194304, 3)
in if level = 3 then LevelAAA() else if level = 2 then LevelAA() else if level = 1 then LevelA() else NoLevel() end

(* Whether data[offset, offset + span_len) is text, from position *)
fun _span_is_from {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{text_len:nat}{position:nat | position <= text_len} .<text_len - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, text: string text_len, text_len: int text_len, position: int position): bool =
  if position >= text_len then true
  else if position >= span_len then false
  else if byte2int0($A.read<byte>(data, offset + position)) <> char2int0(string_get_at(text, position)) then false
  else _span_is_from(data, offset, span_len, text, text_len, position + 1)

fn _span_is {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{text_len:nat}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, text: string text_len): bool = let
  val text_len = g1u2i(string1_length(text))
in if span_len <> text_len then false else _span_is_from(data, offset, span_len, text, text_len, 0) end

(* data[offset, offset + span_len) without the white space around it *)
fun _trim_front {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n} .<span_len>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): [trimmed_offset,trimmed_len:nat | trimmed_offset + trimmed_len <= n] @(int trimmed_offset, int trimmed_len) =
  if span_len <= 0 then @(offset, span_len)
  else if byte2int0($A.read<byte>(data, offset)) <= 32 then _trim_front(data, offset + 1, span_len - 1)
  else @(offset, span_len)

fun _trim_back {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n} .<span_len>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): [trimmed_len:nat | trimmed_len <= span_len] int trimmed_len =
  if span_len <= 0 then span_len
  else if byte2int0($A.read<byte>(data, offset + span_len - 1)) <= 32 then _trim_back(data, offset, span_len - 1)
  else span_len

fn _trim {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len)
  : [trimmed_offset,trimmed_len:nat | trimmed_offset + trimmed_len <= n] @(int trimmed_offset, int trimmed_len) = let
  val @(trimmed_offset, front_len) = _trim_front(data, offset, span_len)
  val trimmed_len = _trim_back(data, trimmed_offset, front_len)
in @(trimmed_offset, trimmed_len) end

(* Whether data[start, start + text_len), in lower case, is text (lower
   case), from position *)
fun _lowercase_from {l:agz}{n:pos}{text_len:pos}{start:nat | start + text_len <= n}{position:nat | position <= text_len} .<text_len - position>.
  (data: !$A.borrow(byte, l, n), start: int start, text: string text_len, text_len: int text_len, position: int position): bool =
  if position >= text_len then true
  else let
    val letter = byte2int0($A.read<byte>(data, start + position))
    val letter = (if letter >= 65 then (if letter <= 90 then letter + 32 else letter) else letter): int
  in if letter <> char2int0(string_get_at(text, position)) then false else _lowercase_from(data, start, text, text_len, position + 1) end

(* Whether data[offset, offset + span_len), in lower case, has text
   (lower case) from position *)
fun _has_lowercase {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{text_len:pos}{position:nat} .<max(span_len - position, 0)>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, text: string text_len, text_len: int text_len, position: int position): bool =
  if position + text_len > span_len then false
  else if _lowercase_from(data, offset + position, text, text_len, 0) then true
  else _has_lowercase(data, offset, span_len, text, text_len, position + 1)

fn _bit_or (left: int, right: int): int = $AR.bor_int_int(left, right)

(* The WCAG level a conformance statement or URL names *)
fn _wcag_level {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): wcag_level =
  if _has_lowercase(data, offset, span_len, "aaa", 3, 0) then LevelAAA()
  else if _has_lowercase(data, offset, span_len, "level aa", 8, 0) then LevelAA()
  else if _has_lowercase(data, offset, span_len, "wcag-aa", 7, 0) then LevelAA()
  else if _has_lowercase(data, offset, span_len, "level a", 7, 0) then LevelA()
  else if _has_lowercase(data, offset, span_len, "wcag-a", 6, 0) then LevelA()
  else NoLevel()

(* flags, with the bit that says the book has accessibility metadata *)
fn _known (flags: int): int = _bit_or(flags, a11y_bit(MetadataKnown()))

(* The flag a property's value sets *)
fn _a11y_value {l:agz}{n:pos}{property_offset,property_len,value_offset,value_len:nat | property_offset + property_len <= n; value_offset + value_len <= n}
  (data: !$A.borrow(byte, l, n), property_offset: int property_offset, property_len: int property_len, value_offset: int value_offset, value_len: int value_len): int = let
  val @(value_offset, value_len) = _trim(data, value_offset, value_len)
in
  if _span_is(data, property_offset, property_len, "schema:accessibilityFeature") then
    _known(if _span_is(data, value_offset, value_len, "displayTransformability") then a11y_bit(Transformable())
     else if _span_is(data, value_offset, value_len, "alternativeText") then a11y_bit(AlternativeText())
     else if _span_is(data, value_offset, value_len, "longDescription") then a11y_bit(LongDescription())
     else if _span_is(data, value_offset, value_len, "tableOfContents") then a11y_bit(TableOfContents())
     else if _span_is(data, value_offset, value_len, "index") then a11y_bit(TermIndex())
     else if _span_is(data, value_offset, value_len, "structuralNavigation") then a11y_bit(StructuralNavigation())
     else if _span_is(data, value_offset, value_len, "pageNavigation") then a11y_bit(PageNavigation())
     else if _span_is(data, value_offset, value_len, "MathML") then a11y_bit(MathMarkup())
     else if _span_is(data, value_offset, value_len, "transcript") then a11y_bit(Transcript())
     else if _span_is(data, value_offset, value_len, "closedCaptions") then a11y_bit(Captions())
     else if _span_is(data, value_offset, value_len, "captions") then a11y_bit(Captions())
     else 0)
  else if _span_is(data, property_offset, property_len, "schema:accessMode") then
    _known(if _span_is(data, value_offset, value_len, "textual") then a11y_bit(TextualMode())
     else if _span_is(data, value_offset, value_len, "visual") then a11y_bit(VisualMode())
     else 0)
  else if _span_is(data, property_offset, property_len, "schema:accessModeSufficient") then
    _known(if _span_is(data, value_offset, value_len, "textual") then a11y_bit(SufficientText()) else 0)
  else if _span_is(data, property_offset, property_len, "schema:accessibilityHazard") then
    _known(if _span_is(data, value_offset, value_len, "none") then a11y_bit(NoHazards())
     else if _span_is(data, value_offset, value_len, "flashing") then a11y_bit(Flashing())
     else if _span_is(data, value_offset, value_len, "motionSimulation") then a11y_bit(MotionSimulation())
     else if _span_is(data, value_offset, value_len, "sound") then a11y_bit(Sound())
     else if _span_is(data, value_offset, value_len, "noFlashingHazard") then a11y_bit(NoFlashingHazard())
     else if _span_is(data, value_offset, value_len, "noMotionSimulationHazard") then a11y_bit(NoMotionHazard())
     else if _span_is(data, value_offset, value_len, "noSoundHazard") then a11y_bit(NoSoundHazard())
     else if _span_is(data, value_offset, value_len, "unknown") then a11y_bit(HazardsUnknown())
     else 0)
  else if _span_is(data, property_offset, property_len, "dcterms:conformsTo") then
    _known(_level_bits(_wcag_level(data, value_offset, value_len)))
  else if _span_is(data, property_offset, property_len, "schema:accessibilitySummary") then _known(0)
  else 0
end

(* The flags of nodes, or'd onto flags, and the summary (the first one) *)
fun _a11y_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), flags: int, summary: xspan(n)): @(int, xspan(n)) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(flags, summary) = _a11y_node(data, node, flags, summary)
    in _a11y_nodes(data, rest, flags, summary) end
  | $X.xml_nodes_nil() => @(flags, summary)

and _a11y_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), flags: int, summary: xspan(n)): @(int, xspan(n)) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var link_chars = @[char][4]('l', 'i', 'n', 'k')
    var property_chars = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
    var name_chars = @[char][4]('n', 'a', 'm', 'e')
    var content_chars = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
    var rel_chars = @[char][3]('r', 'e', 'l')
    var href_chars = @[char][4]('h', 'r', 'e', 'f')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (* EPUB 3: <meta property="p">v</meta>; EPUB 2: <meta name="p" content="v"/> *)
      (case+ _find_attr_value(data, attrs, property_chars, 8) of
       | ~xspan_at(property_offset, property_len) =>
         (case+ _get_first_text(children) of
          | ~xspan_at(value_offset, value_len) => let
              val flag = _a11y_value(data, property_offset, property_len, value_offset, value_len)
              val is_summary = _span_is(data, property_offset, property_len, "schema:accessibilitySummary")
            in
              case+ summary of
              | xspan_none() => if is_summary then let
                    val () = xspan_free(summary)
                  in @(_bit_or(flags, flag), xspan_at(value_offset, value_len)) end
                  else @(_bit_or(flags, flag), summary)
              | _ => @(_bit_or(flags, flag), summary)
            end
          | ~xspan_none() => @(flags, summary))
       | ~xspan_none() =>
         (case+ _find_attr_value(data, attrs, name_chars, 4) of
          | ~xspan_at(property_offset, property_len) =>
            (case+ _find_attr_value(data, attrs, content_chars, 7) of
             | ~xspan_at(value_offset, value_len) => let
                 val flag = _a11y_value(data, property_offset, property_len, value_offset, value_len)
                 val is_summary = _span_is(data, property_offset, property_len, "schema:accessibilitySummary")
               in
                 case+ summary of
                 | xspan_none() => if is_summary then let
                       val () = xspan_free(summary)
                     in @(_bit_or(flags, flag), xspan_at(value_offset, value_len)) end
                     else @(_bit_or(flags, flag), summary)
                 | _ => @(_bit_or(flags, flag), summary)
               end
             | ~xspan_none() => @(flags, summary))
          | ~xspan_none() => @(flags, summary)))
    else if xml_name_eq(data, tag_offset, tag_len, link_chars, 4) then
      (case+ _find_attr_value(data, attrs, rel_chars, 3) of
       | ~xspan_at(rel_offset, rel_len) =>
         (case+ _find_attr_value(data, attrs, href_chars, 4) of
          | ~xspan_at(href_offset, href_len) => @(_bit_or(flags, _a11y_value(data, rel_offset, rel_len, href_offset, href_len)), summary)
          | ~xspan_none() => @(flags, summary))
       | ~xspan_none() => @(flags, summary))
    else _a11y_nodes(data, children, flags, summary)
  end
  | $X.xml_text(_, _) => @(flags, summary)

(* The OPF's accessibility metadata: its flags (a11y_bit's bits), and its
   accessibilitySummary's text, if any *)
#pub fn opf_a11y
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): @(int, xspan(n))

implement opf_a11y(data, nodes) = _a11y_nodes(data, nodes, 0, xspan_none())

(* ============================================================
   Series: EPUB 3's belongs-to-collection and group-position, or
   Calibre's calibre:series and calibre:series_index
   ============================================================ *)

(* A series position is kept in hundredths (2.5 is 250, "-1" is -100),
   from -99999.99 to 99999.99, as the number Calibre keeps as a float
   (calibre:series_index) read to two places, and told apart from no
   position at all: the stored number is 0 for none, else the hundredths
   plus SERIES_ZERO, so 0 ("a prequel") is a position and sorts first *)
#pub fn series_position_of (hundredths: int): [position:int] int position
implement series_position_of (hundredths) =
  if hundredths < 0 - 9999999 then 0
  else if hundredths > 9999999 then 0
  else g1ofg0(hundredths + 10000001)

(* A series position in the text at data[offset, offset + span_len): a
   number with an optional sign, digits, and a '.' or ',' (as some locales
   write it) with digits after it, the white space around it ignored; the
   hundredths past two places are cut. Anything else ("II", "Part Two",
   "2 5", "1e2", empty) has no position (0), and so has a whole part over
   99999. *)
fun _number_scan {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n} .<span_len>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len,
   started: bool, negative: bool, ended: bool, frac_digits: int, whole: int, frac: int, digits: int): int =
  if span_len <= 0 then
    (if digits <= 0 then 0
     else let
       val fraction: int = (if frac_digits = 1 then $AR.mul_int_int(frac, 10) else frac)
       val hundredths: int = $AR.add_int_int($AR.mul_int_int(whole, 100), fraction)
     in series_position_of((if negative then 0 - hundredths else hundredths)) end)
  else let
    val byte_value = byte2int0($A.read<byte>(data, offset))
  in
    if byte_value = 32 then
      (if started then _number_scan(data, offset + 1, span_len - 1, started, negative, true, frac_digits, whole, frac, digits)
       else _number_scan(data, offset + 1, span_len - 1, started, negative, ended, frac_digits, whole, frac, digits))
    else if byte_value = 9 then
      (if started then _number_scan(data, offset + 1, span_len - 1, started, negative, true, frac_digits, whole, frac, digits)
       else _number_scan(data, offset + 1, span_len - 1, started, negative, ended, frac_digits, whole, frac, digits))
    else if byte_value = 10 then
      (if started then _number_scan(data, offset + 1, span_len - 1, started, negative, true, frac_digits, whole, frac, digits)
       else _number_scan(data, offset + 1, span_len - 1, started, negative, ended, frac_digits, whole, frac, digits))
    else if byte_value = 13 then
      (if started then _number_scan(data, offset + 1, span_len - 1, started, negative, true, frac_digits, whole, frac, digits)
       else _number_scan(data, offset + 1, span_len - 1, started, negative, ended, frac_digits, whole, frac, digits))
    else if ended then 0
    else if byte_value = 45 then
      (if started then 0 else _number_scan(data, offset + 1, span_len - 1, true, true, ended, frac_digits, whole, frac, digits))
    else if byte_value = 43 then
      (if started then 0 else _number_scan(data, offset + 1, span_len - 1, true, false, ended, frac_digits, whole, frac, digits))
    else if byte_value = 46 then
      (if frac_digits >= 0 then 0 else _number_scan(data, offset + 1, span_len - 1, true, negative, ended, 0, whole, frac, digits))
    else if byte_value = 44 then
      (if frac_digits >= 0 then 0 else _number_scan(data, offset + 1, span_len - 1, true, negative, ended, 0, whole, frac, digits))
    else if byte_value < 48 then 0
    else if byte_value > 57 then 0
    else if frac_digits < 0 then
      (if whole > 9999 then 0
       else _number_scan(data, offset + 1, span_len - 1, true, negative, ended, frac_digits, whole * 10 + (byte_value - 48), frac, digits + 1))
    else if frac_digits < 2 then
      _number_scan(data, offset + 1, span_len - 1, true, negative, ended, frac_digits + 1, whole, frac * 10 + (byte_value - 48), digits + 1)
    else _number_scan(data, offset + 1, span_len - 1, true, negative, ended, frac_digits, whole, frac, digits + 1)
  end

fn _series_value {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): int =
  _number_scan(data, offset, span_len, false, false, false, ~1, 0, 0, 0)

(* Whether data[first, first + len) and data[second, second + len) are the
   same bytes, from position *)
fun _same_bytes {l:agz}{n:pos}{first,second,len:nat | first + len <= n; second + len <= n}{position:nat | position <= len} .<len - position>.
  (data: !$A.borrow(byte, l, n), first: int first, second: int second, len: int len, position: int position): bool =
  if position >= len then true
  else if byte2int0($A.read<byte>(data, first + position)) <> byte2int0($A.read<byte>(data, second + position)) then false
  else _same_bytes(data, first, second, len, position + 1)

(* Whether a meta's refines attribute is "#" and the id at
   data[id_offset, id_offset + id_len) *)
fn _refines_id {l:agz}{n:pos}{attr_count:nat}{id_offset,id_len:nat | id_offset + id_len <= n}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count), id_offset: int id_offset, id_len: int id_len): bool = let
  var refines_chars = @[char][7]('r', 'e', 'f', 'i', 'n', 'e', 's')
in
  case+ _find_attr_value(data, attrs, refines_chars, 7) of
  | ~xspan_at(refines_offset, refines_len) =>
    if refines_len <> id_len + 1 then false
    else if refines_len <= 0 then false
    else if byte2int0($A.read<byte>(data, refines_offset)) <> 35 then false
    else _same_bytes(data, refines_offset + 1, id_offset, id_len, 0)
  | ~xspan_none() => false
end

(* Whether some meta of nodes refines the id at data[id_offset, id_offset +
   id_len) with a collection-type that is not "series" ("set" is the other
   type EPUB defines) *)
fun _other_type_nodes
  {l:agz}{n:pos}{tree_size:nat}{id_offset,id_len:nat | id_offset + id_len <= n} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), id_offset: int id_offset, id_len: int id_len): bool =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    if _other_type_node(data, node, id_offset, id_len) then true
    else _other_type_nodes(data, rest, id_offset, id_len)
  | $X.xml_nodes_nil() => false

and _other_type_node
  {l:agz}{n:pos}{tree_size:pos}{id_offset,id_len:nat | id_offset + id_len <= n} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), id_offset: int id_offset, id_len: int id_len): bool =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var property_chars = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (if _refines_id(data, attrs, id_offset, id_len) then
         (case+ _find_attr_value(data, attrs, property_chars, 8) of
          | ~xspan_at(property_offset, property_len) =>
            if _span_is(data, property_offset, property_len, "collection-type") then
              (case+ _get_first_text(children) of
               | ~xspan_at(value_offset, value_len) => let
                   val @(trimmed_offset, trimmed_len) = _trim(data, value_offset, value_len)
                 in ~_span_is(data, trimmed_offset, trimmed_len, "series") end
               | ~xspan_none() => false)
            else false
          | ~xspan_none() => false)
       else false)
    else _other_type_nodes(data, children, id_offset, id_len)
  end
  | $X.xml_text(_, _) => false

(* The belongs-to-collection of nodes that comes after skip others: its name and its id (none when it has
   none), and how many remain to skip *)
fun _collection_nth_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), skip: int): @(xspan(n), xspan(n), int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(name, id, left) = _collection_nth_node(data, node, skip)
    in
      case+ name of
      | ~xspan_none() => let val () = xspan_free(id) in _collection_nth_nodes(data, rest, left) end
      | _ => @(name, id, left)
    end
  | $X.xml_nodes_nil() => @(xspan_none(), xspan_none(), skip)

and _collection_nth_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), skip: int): @(xspan(n), xspan(n), int) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var property_chars = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
    var id_chars = @[char][2]('i', 'd')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (case+ _find_attr_value(data, attrs, property_chars, 8) of
       | ~xspan_at(property_offset, property_len) =>
         if _span_is(data, property_offset, property_len, "belongs-to-collection") then
           (case+ _get_first_text(children) of
            | ~xspan_at(value_offset, value_len) =>
              if skip > 0 then @(xspan_none(), xspan_none(), skip - 1)
              else
                (case+ _find_attr_value(data, attrs, id_chars, 2) of
                 | ~xspan_at(id_offset, id_len) => @(xspan_at(value_offset, value_len), xspan_at(id_offset, id_len), 0)
                 | ~xspan_none() => @(xspan_at(value_offset, value_len), xspan_none(), 0))
            | ~xspan_none() => @(xspan_none(), xspan_none(), skip))
         else @(xspan_none(), xspan_none(), skip)
       | ~xspan_none() => @(xspan_none(), xspan_none(), skip))
    else _collection_nth_nodes(data, children, skip)
  end
  | $X.xml_text(_, _) => @(xspan_none(), xspan_none(), skip)

(* The first belongs-to-collection of nodes that is a series, from the skip-th on: its name, and its id (none
   when it has none). A collection another meta refines as a "set" is not one. *)
fun _collection_pick
  {l:agz}{n:pos}{tree_size:nat}{skip:nat | skip <= 64} .<64 - skip>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), skip: int skip): @(xspan(n), xspan(n)) =
  if skip >= 64 then @(xspan_none(), xspan_none())
  else let
    val @(name, id, _) = _collection_nth_nodes(data, nodes, skip)
  in
    case+ name of
    | ~xspan_none() => let val () = xspan_free(id) in @(xspan_none(), xspan_none()) end
    | _ => let
        val other = (case+ id of
          | xspan_at(id_offset, id_len) => _other_type_nodes(data, nodes, id_offset, id_len)
          | xspan_none() => false)
      in
        if other then let
            val () = xspan_free(name)
            val () = xspan_free(id)
          in _collection_pick(data, nodes, skip + 1) end
        else @(name, id)
      end
  end

(* The position of nodes' first group-position that refines the id (any
   group-position when the collection has no id), 0 when none *)
fun _position_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), id: !xspan(n)): int =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val found = _position_node(data, node, id)
    in if found <> 0 then found else _position_nodes(data, rest, id) end
  | $X.xml_nodes_nil() => 0

and _position_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), id: !xspan(n)): int =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var property_chars = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (case+ _find_attr_value(data, attrs, property_chars, 8) of
       | ~xspan_at(property_offset, property_len) =>
         if _span_is(data, property_offset, property_len, "group-position") then
           (case+ _get_first_text(children) of
            | ~xspan_at(value_offset, value_len) =>
              (case+ id of
               | xspan_at(id_offset, id_len) =>
                 if _refines_id(data, attrs, id_offset, id_len) then _series_value(data, value_offset, value_len) else 0
               | xspan_none() => _series_value(data, value_offset, value_len))
            | ~xspan_none() => 0)
         else 0
       | ~xspan_none() => 0)
    else _position_nodes(data, children, id)
  end
  | $X.xml_text(_, _) => 0

(* Calibre's series (calibre:series) and its position (the first
   calibre:series_index that is a number) in nodes *)
fun _calibre_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), name: xspan(n), number: int): @(xspan(n), int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(name, number) = _calibre_node(data, node, name, number)
    in _calibre_nodes(data, rest, name, number) end
  | $X.xml_nodes_nil() => @(name, number)

and _calibre_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), name: xspan(n), number: int): @(xspan(n), int) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var name_chars = @[char][4]('n', 'a', 'm', 'e')
    var content_chars = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (case+ _find_attr_value(data, attrs, name_chars, 4) of
       | ~xspan_at(property_offset, property_len) =>
         (case+ _find_attr_value(data, attrs, content_chars, 7) of
          | ~xspan_at(value_offset, value_len) =>
            if _span_is(data, property_offset, property_len, "calibre:series") then
              (case+ name of
               | xspan_none() => let val () = xspan_free(name) in @(xspan_at(value_offset, value_len), number) end
               | _ => @(name, number))
            else if _span_is(data, property_offset, property_len, "calibre:series_index") then
              @(name, (if number = 0 then _series_value(data, value_offset, value_len) else number))
            else @(name, number)
          | ~xspan_none() => @(name, number))
       | ~xspan_none() => @(name, number))
    else _calibre_nodes(data, children, name, number)
  end
  | $X.xml_text(_, _) => @(name, number)

(* The book's series (its name, when it has one) and its position in it
   (series_position_of's number, 0 when none is given): the first series
   collection of EPUB 3, whose group-position refines it, else Calibre's *)
#pub fn opf_series
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): @(xspan(n), int)

implement opf_series(data, nodes) = let
  val @(name, id) = _collection_pick(data, nodes, 0)
in
  case+ name of
  | ~xspan_none() => let
      val () = xspan_free(id)
    in _calibre_nodes(data, nodes, xspan_none(), 0) end
  | _ => let
      val position = _position_nodes(data, nodes, id)
      val () = xspan_free(id)
    in @(name, position) end
end

(* ============================================================
   Spine: find Nth idref
   ============================================================ *)

(* The idref of the itemref after skip others, or how many remain to
   skip *)
fun _nth_idref_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size),
   skip: int): @(xspan(n), int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(idref, left) = _nth_idref_node(data, node, skip)
    in
      case+ idref of
      | ~xspan_none() => _nth_idref_nodes(data, rest, left)
      | _ => @(idref, left)
    end
  | $X.xml_nodes_nil() => @(xspan_none(), skip)

and _nth_idref_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size),
   skip: int): @(xspan(n), int) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var itemref_chars = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
    var idref_chars = @[char][5]('i', 'd', 'r', 'e', 'f')
  in
    if xml_name_eq(data, tag_offset, tag_len, itemref_chars, 7) then
      if skip <= 0 then @(_find_attr_value(data, attrs, idref_chars, 5), 0)
      else @(xspan_none(), skip - 1)
    else _nth_idref_nodes(data, children, skip)
  end
  | $X.xml_text(_, _) => @(xspan_none(), skip)

(* ============================================================
   Spine: count items
   ============================================================ *)

fun _count_itemref_nodes
  {l:agz}{n:pos}{tree_size:nat}{count:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size),
   count: int count): [total:nat] int total =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
      _count_itemref_nodes(data, rest, _count_itemref_node(data, node, count))
  | $X.xml_nodes_nil() => count

and _count_itemref_node
  {l:agz}{n:pos}{tree_size:pos}{count:nat} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size),
   count: int count): [total:nat] int total =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, _, children) => let
    var itemref_chars = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
  in
    if xml_name_eq(data, tag_offset, tag_len, itemref_chars, 7) then count + 1
    else _count_itemref_nodes(data, children, count)
  end
  | $X.xml_text(_, _) => count

(* Number of itemref elements *)
#pub fn count_spine_items
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): [count:nat] int count

implement count_spine_items(data, nodes) = _count_itemref_nodes(data, nodes, 0)

(* ============================================================
   Manifest: find href by idref
   ============================================================ *)

fun _manifest_href_nodes
  {l:agz}{n:pos}{tree_size:nat}{idref_offset,idref_len:nat | idref_offset + idref_len <= n} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _manifest_href_node(data, data_len, node, idref_offset, idref_len) of
     | ~xspan_none() => _manifest_href_nodes(data, data_len, rest, idref_offset, idref_len)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _manifest_href_node
  {l:agz}{n:pos}{tree_size:pos}{idref_offset,idref_len:nat | idref_offset + idref_len <= n} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), data_len: int n, node: !$X.xml_node(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var item_chars = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, tag_offset, tag_len, item_chars, 4) then let
      var id_chars = @[char][2]('i', 'd')
    in
      case+ _find_attr_value(data, attrs, id_chars, 2) of
      | ~xspan_at(id_offset, id_len) =>
        if id_len <> idref_len then xspan_none()
        else if $S.borrow_region_eq(data, data_len, id_offset, idref_offset, idref_len) then let
          var href_chars = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_value(data, attrs, href_chars, 4) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _manifest_href_nodes(data, data_len, children, idref_offset, idref_len)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the manifest item for the chapter_index-th spine itemref *)
#pub fn find_chapter_href_n
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), data_len: int n,
   nodes: !$X.xml_node_list(n, tree_size), chapter_index: int): xspan(n)

implement find_chapter_href_n(data, data_len, nodes, chapter_index) = let
  val @(idref, _) = _nth_idref_nodes(data, nodes, chapter_index)
in
  case+ idref of
  | ~xspan_at(idref_offset, idref_len) => _manifest_href_nodes(data, data_len, nodes, idref_offset, idref_len)
  | ~xspan_none() => xspan_none()
end

(* The attribute attr of the manifest item whose id is
   data[idref_offset, idref_offset + idref_len) *)
fun _manifest_attr_nodes
  {l:agz}{n:pos}{tree_size:nat}{idref_offset,idref_len:nat | idref_offset + idref_len <= n}{attr_len:pos} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len, attr: &(@[char][attr_len]), attr_len: int attr_len): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _manifest_attr_node(data, data_len, node, idref_offset, idref_len, attr, attr_len) of
     | ~xspan_none() => _manifest_attr_nodes(data, data_len, rest, idref_offset, idref_len, attr, attr_len)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _manifest_attr_node
  {l:agz}{n:pos}{tree_size:pos}{idref_offset,idref_len:nat | idref_offset + idref_len <= n}{attr_len:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), data_len: int n, node: !$X.xml_node(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len, attr: &(@[char][attr_len]), attr_len: int attr_len): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var item_chars = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, tag_offset, tag_len, item_chars, 4) then let
      var id_chars = @[char][2]('i', 'd')
    in
      case+ _find_attr_value(data, attrs, id_chars, 2) of
      | ~xspan_at(id_offset, id_len) =>
        if id_len <> idref_len then xspan_none()
        else if $S.borrow_region_eq(data, data_len, id_offset, idref_offset, idref_len) then _find_attr_value(data, attrs, attr, attr_len)
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _manifest_attr_nodes(data, data_len, children, idref_offset, idref_len, attr, attr_len)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the Media Overlay (a SMIL document) of the
   chapter_index-th spine itemref: its manifest item's media-overlay
   names another item, whose href this is *)
#pub fn find_chapter_overlay_href_n
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), data_len: int n,
   nodes: !$X.xml_node_list(n, tree_size), chapter_index: int): xspan(n)

implement find_chapter_overlay_href_n(data, data_len, nodes, chapter_index) = let
  val @(idref, _) = _nth_idref_nodes(data, nodes, chapter_index)
in
  case+ idref of
  | ~xspan_at(idref_offset, idref_len) => let
      var media_overlay_chars = @[char][13]('m', 'e', 'd', 'i', 'a', '-', 'o', 'v', 'e', 'r', 'l', 'a', 'y')
    in
      case+ _manifest_attr_nodes(data, data_len, nodes, idref_offset, idref_len, media_overlay_chars, 13) of
      | ~xspan_at(overlay_offset, overlay_len) => _manifest_href_nodes(data, data_len, nodes, overlay_offset, overlay_len)
      | ~xspan_none() => xspan_none()
    end
  | ~xspan_none() => xspan_none()
end

(* ============================================================
   Manifest: items by property, meta by name
   ============================================================ *)

(* Whether data[offset, offset + span_len) has pattern[0, pattern_len)
   in it at or after position *)
fun _span_has {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{pattern_len:pos}{position:nat} .<max(span_len - position + 1, 0)>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, pattern: &(@[char][pattern_len]), pattern_len: int pattern_len, position: int position): bool =
  if position + pattern_len > span_len then false
  else if _match_chars(data, offset + position, pattern, pattern_len, 0) then true
  else _span_has(data, offset, span_len, pattern, pattern_len, position + 1)

(* ============================================================
   Spine: the manifest item a spine itemref shows (EPUB 3.3 §3.1, §3.3)
   ============================================================ *)

(* Whether the media type of the manifest item whose id is
   data[idref_offset, idref_offset + idref_len) is one a content document
   has: XHTML, SVG, HTML, and the EPUB 2 documents Quire reads through
   (OEB 1 and DTBook, quire#416); an item with no media-type is taken to
   be one *)
fn _type_shown
  {l:agz}{n:pos}{tree_size:nat}{idref_offset,idref_len:nat | idref_offset + idref_len <= n}
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len): bool = let
    var media_type_chars = @[char][10]('m', 'e', 'd', 'i', 'a', '-', 't', 'y', 'p', 'e')
in
  case+ _manifest_attr_nodes(data, data_len, nodes, idref_offset, idref_len, media_type_chars, 10) of
  | ~xspan_none() => true
  | ~xspan_at(type_offset, type_len) => let
    var xhtml_chars = @[char][21]('a', 'p', 'p', 'l', 'i', 'c', 'a', 't', 'i', 'o', 'n', '/', 'x', 'h', 't', 'm', 'l', '+', 'x', 'm', 'l')
    var svg_chars = @[char][13]('i', 'm', 'a', 'g', 'e', '/', 's', 'v', 'g', '+', 'x', 'm', 'l')
    var html_chars = @[char][9]('t', 'e', 'x', 't', '/', 'h', 't', 'm', 'l')
    var oeb1_chars = @[char][20]('t', 'e', 'x', 't', '/', 'x', '-', 'o', 'e', 'b', '1', '-', 'd', 'o', 'c', 'u', 'm', 'e', 'n', 't')
    var dtbook_chars = @[char][24]('a', 'p', 'p', 'l', 'i', 'c', 'a', 't', 'i', 'o', 'n', '/', 'x', '-', 'd', 't', 'b', 'o', 'o', 'k', '+', 'x', 'm', 'l')
    in
      xml_name_eq(data, type_offset, type_len, xhtml_chars, 21)
      || xml_name_eq(data, type_offset, type_len, svg_chars, 13)
      || xml_name_eq(data, type_offset, type_len, html_chars, 9)
      || xml_name_eq(data, type_offset, type_len, oeb1_chars, 20)
      || xml_name_eq(data, type_offset, type_len, dtbook_chars, 24)
    end
end

(* Whether the manifest item whose id is data[idref_offset, ...) has the
   property scripted *)
fn _item_scripted
  {l:agz}{n:pos}{tree_size:nat}{idref_offset,idref_len:nat | idref_offset + idref_len <= n}
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len): bool = let
    var properties_chars = @[char][10]('p', 'r', 'o', 'p', 'e', 'r', 't', 'i', 'e', 's')
in
  case+ _manifest_attr_nodes(data, data_len, nodes, idref_offset, idref_len, properties_chars, 10) of
  | ~xspan_none() => false
  | ~xspan_at(properties_offset, properties_len) => let
    var scripted_chars = @[char][8]('s', 'c', 'r', 'i', 'p', 't', 'e', 'd')
    in _span_has(data, properties_offset, properties_len, scripted_chars, 8, 0) end
end

(* The href of the item shown for the manifest item whose id is
   data[idref_offset, ...): the item itself when it is a content
   document (and not scripted with a fallback to use instead), else the
   item its fallback names, and so on down the chain for at most steps
   items (a chain that loops ends there); none when none of them is one.
   An item that is not a content document is never read as one: a
   reader that cannot show it shows its fallback (EPUB 3.3 §3.3), else
   skips it, as Thorium and Readium do *)
fun _shown_href
  {l:agz}{n:pos}{tree_size:nat}{idref_offset,idref_len:nat | idref_offset + idref_len <= n}{steps:nat} .<steps>.
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len, steps: int steps): xspan(n) =
  if steps <= 0 then xspan_none()
  else let
    val shown = _type_shown(data, data_len, nodes, idref_offset, idref_len)
    var fallback_chars = @[char][8]('f', 'a', 'l', 'l', 'b', 'a', 'c', 'k')
  in
    case+ _manifest_attr_nodes(data, data_len, nodes, idref_offset, idref_len, fallback_chars, 8) of
    | ~xspan_none() =>
      if shown then _manifest_href_nodes(data, data_len, nodes, idref_offset, idref_len)
      else xspan_none()
    | ~xspan_at(fallback_offset, fallback_len) =>
      if shown && ~_item_scripted(data, data_len, nodes, idref_offset, idref_len) then
        _manifest_href_nodes(data, data_len, nodes, idref_offset, idref_len)
      else _shown_href(data, data_len, nodes, fallback_offset, fallback_len, steps - 1)
  end

(* The href of the manifest item shown for the chapter_index-th spine
   itemref (find_chapter_href_n is the itemref's own item), none when
   neither it nor anything on its fallback chain is a content document *)
#pub fn find_chapter_shown_href_n
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), data_len: int n,
   nodes: !$X.xml_node_list(n, tree_size), chapter_index: int): xspan(n)

implement find_chapter_shown_href_n(data, data_len, nodes, chapter_index) = let
  val @(idref, _) = _nth_idref_nodes(data, nodes, chapter_index)
in
  case+ idref of
  | ~xspan_at(idref_offset, idref_len) => _shown_href(data, data_len, nodes, idref_offset, idref_len, 16)
  | ~xspan_none() => xspan_none()
end

(* ============================================================
   Manifest: the fallback of an image the reader cannot show
   ============================================================ *)

(* Whether the media type data[type_offset, type_offset + type_len) is
   one of the core image types a browser draws (EPUB 3.3 §3.2 and AVIF) *)
fn _type_is_core_image
  {l:agz}{n:pos}{type_offset,type_len:nat | type_offset + type_len <= n}
  (data: !$A.borrow(byte, l, n), type_offset: int type_offset, type_len: int type_len): bool = let
    var gif_chars = @[char][9]('i', 'm', 'a', 'g', 'e', '/', 'g', 'i', 'f')
    var jpeg_chars = @[char][10]('i', 'm', 'a', 'g', 'e', '/', 'j', 'p', 'e', 'g')
    var png_chars = @[char][9]('i', 'm', 'a', 'g', 'e', '/', 'p', 'n', 'g')
    var svg_chars = @[char][13]('i', 'm', 'a', 'g', 'e', '/', 's', 'v', 'g', '+', 'x', 'm', 'l')
    var webp_chars = @[char][10]('i', 'm', 'a', 'g', 'e', '/', 'w', 'e', 'b', 'p')
    var avif_chars = @[char][10]('i', 'm', 'a', 'g', 'e', '/', 'a', 'v', 'i', 'f')
in
  xml_name_eq(data, type_offset, type_len, gif_chars, 9)
  || xml_name_eq(data, type_offset, type_len, jpeg_chars, 10)
  || xml_name_eq(data, type_offset, type_len, png_chars, 9)
  || xml_name_eq(data, type_offset, type_len, svg_chars, 13)
  || xml_name_eq(data, type_offset, type_len, webp_chars, 10)
  || xml_name_eq(data, type_offset, type_len, avif_chars, 10)
end

(* The href of the first item, from the manifest item whose id is
   data[idref_offset, ...) down its chain of fallbacks (at most steps
   items), whose media type is a core image type; none when there is no
   such item *)
fun _image_target
  {l:agz}{n:pos}{tree_size:nat}{idref_offset,idref_len:nat | idref_offset + idref_len <= n}{steps:nat} .<steps>.
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len, steps: int steps): xspan(n) =
  if steps <= 0 then xspan_none()
  else let
    var media_type_chars = @[char][10]('m', 'e', 'd', 'i', 'a', '-', 't', 'y', 'p', 'e')
    var fallback_chars = @[char][8]('f', 'a', 'l', 'l', 'b', 'a', 'c', 'k')
  in
    case+ _manifest_attr_nodes(data, data_len, nodes, idref_offset, idref_len, media_type_chars, 10) of
    | ~xspan_at(type_offset, type_len) =>
      if _type_is_core_image(data, type_offset, type_len) then _manifest_href_nodes(data, data_len, nodes, idref_offset, idref_len)
      else (case+ _manifest_attr_nodes(data, data_len, nodes, idref_offset, idref_len, fallback_chars, 8) of
        | ~xspan_at(fallback_offset, fallback_len) => _image_target(data, data_len, nodes, fallback_offset, fallback_len, steps - 1)
        | ~xspan_none() => xspan_none())
    | ~xspan_none() => xspan_none()
  end

(* An image item of the manifest that has a fallback: the span of its
   href and of its fallback's id; or how many such items are left to skip *)
#pub datavtype image_fallback(n:int) =
  | {item_offset,item_len,fallback_offset,fallback_len:nat | item_offset + item_len <= n; fallback_offset + fallback_len <= n}
    ImageFallback(n) of (int item_offset, int item_len, int fallback_offset, int fallback_len)
  | ImageFallbackSkip(n) of (int)

fun _image_fallback_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), data_len: int n,
   nodes: !$X.xml_node_list(n, tree_size), skip: int): image_fallback(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _image_fallback_node(data, data_len, node, skip) of
     | ~ImageFallbackSkip(left) => _image_fallback_nodes(data, data_len, rest, left)
     | found => found)
  | $X.xml_nodes_nil() => ImageFallbackSkip(skip)

and _image_fallback_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), data_len: int n,
   node: !$X.xml_node(n, tree_size), skip: int): image_fallback(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var item_chars = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, tag_offset, tag_len, item_chars, 4) then let
    var href_chars = @[char][4]('h', 'r', 'e', 'f')
    var media_type_chars = @[char][10]('m', 'e', 'd', 'i', 'a', '-', 't', 'y', 'p', 'e')
    var fallback_chars = @[char][8]('f', 'a', 'l', 'l', 'b', 'a', 'c', 'k')
    in
      case+ _find_attr_value(data, attrs, href_chars, 4) of
      | ~xspan_none() => ImageFallbackSkip(skip)
      | ~xspan_at(href_offset, href_len) =>
        (case+ _find_attr_value(data, attrs, media_type_chars, 10) of
         | ~xspan_none() => ImageFallbackSkip(skip)
         | ~xspan_at(type_offset, type_len) =>
           if _type_is_core_image(data, type_offset, type_len) then ImageFallbackSkip(skip)
           else (case+ _find_attr_value(data, attrs, fallback_chars, 8) of
             | ~xspan_none() => ImageFallbackSkip(skip)
             | ~xspan_at(fallback_offset, fallback_len) =>
               if skip <= 0 then ImageFallback(href_offset, href_len, fallback_offset, fallback_len)
               else ImageFallbackSkip(skip - 1)))
    end
    else _image_fallback_nodes(data, data_len, children, skip)
  end
  | $X.xml_text(_, _) => ImageFallbackSkip(skip)

(* The skip-th (from 0) manifest item that is not a core image type and
   has a fallback: an <img> that names it is shown as the image its
   fallbacks lead to (find_image_target; the suite's pub-foreign_image) *)
#pub fn find_image_fallback_n
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), data_len: int n,
   nodes: !$X.xml_node_list(n, tree_size), skip: int): image_fallback(n)

implement find_image_fallback_n(data, data_len, nodes, skip) =
  _image_fallback_nodes(data, data_len, nodes, skip)

(* The href of the core image the fallbacks of the manifest item whose id
   is data[idref_offset, ...) lead to, none when they lead to none *)
#pub fn find_image_target
  {l:agz}{n:pos}{tree_size:nat}{idref_offset,idref_len:nat | idref_offset + idref_len <= n}
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   idref_offset: int idref_offset, idref_len: int idref_len): xspan(n)

implement find_image_target(data, data_len, nodes, idref_offset, idref_len) =
  _image_target(data, data_len, nodes, idref_offset, idref_len, 16)

(* The href of the first manifest item whose properties have property *)
fun _item_with_property_nodes
  {l:agz}{n:pos}{tree_size:nat}{property_len:pos} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size),
   property: &(@[char][property_len]), property_len: int property_len): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _item_with_property(data, node, property, property_len) of
     | ~xspan_none() => _item_with_property_nodes(data, rest, property, property_len)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _item_with_property
  {l:agz}{n:pos}{tree_size:pos}{property_len:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size),
   property: &(@[char][property_len]), property_len: int property_len): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var item_chars = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, tag_offset, tag_len, item_chars, 4) then let
      var properties_chars = @[char][10]('p', 'r', 'o', 'p', 'e', 'r', 't', 'i', 'e', 's')
    in
      case+ _find_attr_value(data, attrs, properties_chars, 10) of
      | ~xspan_at(properties_offset, properties_len) =>
        if _span_has(data, properties_offset, properties_len, property, property_len, 0) then let
          var href_chars = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_value(data, attrs, href_chars, 4) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _item_with_property_nodes(data, children, property, property_len)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The content of the first <meta name="cover"> *)
fun _meta_cover_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _meta_cover(data, node) of
     | ~xspan_none() => _meta_cover_nodes(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _meta_cover
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then let
      var name_chars = @[char][4]('n', 'a', 'm', 'e')
      var cover_chars = @[char][5]('c', 'o', 'v', 'e', 'r')
    in
      case+ _find_attr_value(data, attrs, name_chars, 4) of
      | ~xspan_at(meta_name_offset, meta_name_len) =>
        if xml_name_eq(data, meta_name_offset, meta_name_len, cover_chars, 5) then let
          var content_chars = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
        in _find_attr_value(data, attrs, content_chars, 7) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _meta_cover_nodes(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the book's cover image: the manifest item with property
   cover-image (EPUB 3), else the item a <meta name="cover"> names
   (EPUB 2) *)
#pub fn find_cover_href
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size)): xspan(n)

implement find_cover_href (data, data_len, nodes) = let
  var cover_image_chars = @[char][11]('c', 'o', 'v', 'e', 'r', '-', 'i', 'm', 'a', 'g', 'e')
in
  case+ _item_with_property_nodes(data, nodes, cover_image_chars, 11) of
  | ~xspan_none() =>
    (case+ _meta_cover_nodes(data, nodes) of
     | ~xspan_at(id_offset, id_len) => _manifest_href_nodes(data, data_len, nodes, id_offset, id_len)
     | ~xspan_none() => xspan_none())
  | found => found
end

(* The href of the manifest item with property `property` (such as
   "nav") *)
#pub fn find_item_with_prop
  {l:agz}{n:pos}{tree_size:nat}{property_len:pos}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size),
   property: &(@[char][property_len]), property_len: int property_len): xspan(n)

implement find_item_with_prop (data, nodes, property, property_len) = _item_with_property_nodes(data, nodes, property, property_len)

(* The href of the manifest item with id data[id_offset, id_offset + id_len) *)
#pub fn find_manifest_href
  {l:agz}{n:pos}{tree_size:nat}{id_offset,id_len:nat | id_offset + id_len <= n}
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   id_offset: int id_offset, id_len: int id_len): xspan(n)

implement find_manifest_href (data, data_len, nodes, id_offset, id_len) = _manifest_href_nodes(data, data_len, nodes, id_offset, id_len)

(* The toc attribute of the first <spine> *)
fun _spine_toc_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _spine_toc(data, node) of
     | ~xspan_none() => _spine_toc_nodes(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _spine_toc
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var spine_chars = @[char][5]('s', 'p', 'i', 'n', 'e')
  in
    if xml_name_eq(data, tag_offset, tag_len, spine_chars, 5) then let
      var toc_chars = @[char][3]('t', 'o', 'c')
    in _find_attr_value(data, attrs, toc_chars, 3) end
    else _spine_toc_nodes(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the NCX (EPUB 2's table of contents): the manifest item
   the spine's toc attribute names *)
#pub fn find_ncx_href
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size)): xspan(n)

implement find_ncx_href (data, data_len, nodes) =
  case+ _spine_toc_nodes(data, nodes) of
  | ~xspan_at(id_offset, id_len) => _manifest_href_nodes(data, data_len, nodes, id_offset, id_len)
  | ~xspan_none() => xspan_none()

(* The href of the first <reference type="text"> of the OPF's <guide>
   (EPUB 2: the first page of the main content) *)
fun _guide_text_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _guide_text(data, node) of
     | ~xspan_none() => _guide_text_nodes(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _guide_text
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var reference_chars = @[char][9]('r', 'e', 'f', 'e', 'r', 'e', 'n', 'c', 'e')
  in
    if xml_name_eq(data, tag_offset, tag_len, reference_chars, 9) then let
      var type_chars = @[char][4]('t', 'y', 'p', 'e')
      var text_chars = @[char][4]('t', 'e', 'x', 't')
    in
      case+ _find_attr_value(data, attrs, type_chars, 4) of
      | ~xspan_at(type_offset, type_len) =>
        if xml_name_eq(data, type_offset, type_len, text_chars, 4) then let
          var href_chars = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_value(data, attrs, href_chars, 4) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _guide_text_nodes(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the guide's text reference: where an EPUB 2 book says
   reading starts *)
#pub fn find_guide_text
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n)

implement find_guide_text (data, nodes) = _guide_text_nodes(data, nodes)

(* Whether data[offset, offset + span_len) has pattern[0, pattern_len)
   in it *)
#pub fn span_has {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{pattern_len:pos}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool

implement span_has (data, offset, span_len, pattern, pattern_len) = _span_has(data, offset, span_len, pattern, pattern_len, 0)

(* What the first <spine>'s page-progression-direction says: right to
   left, left to right, or nothing (absent, or "default": the reading
   system's choice); NoSpine where there is no spine *)
datatype spine_progression =
  | NoSpine
  | SpineRightToLeft
  | SpineLeftToRight
  | SpineDefault

fun _spine_rtl_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): spine_progression =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => (case+ _spine_rtl(data, node) of
    | NoSpine() => _spine_rtl_nodes(data, rest)
    | SpineRightToLeft() => SpineRightToLeft()
    | SpineLeftToRight() => SpineLeftToRight()
    | SpineDefault() => SpineDefault())
  | $X.xml_nodes_nil() => NoSpine()

(* At a node: what its <spine> (it, or one in it) says *)
and _spine_rtl
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): spine_progression =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var spine_chars = @[char][5]('s', 'p', 'i', 'n', 'e')
  in
    if xml_name_eq(data, tag_offset, tag_len, spine_chars, 5) then let
      var page_progression_chars = @[char][26]('p', 'a', 'g', 'e', '-', 'p', 'r', 'o', 'g', 'r', 'e', 's', 's', 'i', 'o', 'n', '-', 'd', 'i', 'r', 'e', 'c', 't', 'i', 'o', 'n')
      var rtl_chars = @[char][3]('r', 't', 'l')
      var ltr_chars = @[char][3]('l', 't', 'r')
    in
      case+ _find_attr_value(data, attrs, page_progression_chars, 26) of
      | ~xspan_at(value_offset, value_len) => if xml_name_eq(data, value_offset, value_len, rtl_chars, 3) then SpineRightToLeft()
          else if xml_name_eq(data, value_offset, value_len, ltr_chars, 3) then SpineLeftToRight() else SpineDefault()
      | ~xspan_none() => SpineDefault()
    end
    else _spine_rtl_nodes(data, children)
  end
  | $X.xml_text(_, _) => NoSpine()

(* Where a language tag's primary subtag ends in
   data[offset, offset + language_len): at its first '-' or '_' at or
   after position *)
fun _subtag_end {l:agz}{n:pos}{offset,language_len:nat | offset + language_len <= n}{position:nat | position <= language_len} .<language_len - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, language_len: int language_len, position: int position): [subtag_len:nat | subtag_len <= language_len] int subtag_len =
  if position >= language_len then language_len
  else let
    val letter = byte2int0($A.read<byte>(data, offset + position))
  in if letter = 45 || letter = 95 then position else _subtag_end(data, offset, language_len, position + 1) end

(* Whether the language tag data[offset, offset + language_len) is of a
   language written right to left: Arabic, Hebrew (and its old code iw), Persian, Urdu,
   Yiddish (and ji), Pashto, Sindhi, Uyghur, Dhivehi, Kashmiri, Central
   Kurdish, Syriac, Aramaic *)
fn _language_rtl {l:agz}{n:pos}{offset,language_len:nat | offset + language_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, language_len: int language_len): bool = let
  val @(offset, language_len) = _trim_front(data, offset, language_len)
  val subtag_len = _subtag_end(data, offset, language_len, 0)
in
  _span_is(data, offset, subtag_len, "ar") || _span_is(data, offset, subtag_len, "he") || _span_is(data, offset, subtag_len, "iw")
  || _span_is(data, offset, subtag_len, "fa") || _span_is(data, offset, subtag_len, "ur") || _span_is(data, offset, subtag_len, "yi")
  || _span_is(data, offset, subtag_len, "ji") || _span_is(data, offset, subtag_len, "ps") || _span_is(data, offset, subtag_len, "sd")
  || _span_is(data, offset, subtag_len, "ug") || _span_is(data, offset, subtag_len, "dv") || _span_is(data, offset, subtag_len, "ks")
  || _span_is(data, offset, subtag_len, "ckb") || _span_is(data, offset, subtag_len, "syr") || _span_is(data, offset, subtag_len, "arc")
end

(* Whether the book reads right to left: as its spine's
   page-progression-direction says; when that says nothing, or
   "default" (the reading system's choice), when its language is
   written right to left, as Readium does *)
#pub fn spine_rtl
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): bool

(* The book's language says, when its spine does not *)
fn _language_says_rtl {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): bool =
  case+ _opf_language_nodes(data, nodes) of
  | ~xspan_at(language_offset, language_len) => _language_rtl(data, language_offset, language_len)
  | ~xspan_none() => false

implement spine_rtl (data, nodes) =
  case+ _spine_rtl_nodes(data, nodes) of
  | SpineRightToLeft() => true
  | SpineLeftToRight() => false
  | SpineDefault() => _language_says_rtl(data, nodes)
  | NoSpine() => _language_says_rtl(data, nodes)

(* Whether the language tag data[offset, offset + language_len) is
   Chinese, Japanese or Korean, which a book read right to left sets
   vertically *)
fn _language_east_asian {l:agz}{n:pos}{offset,language_len:nat | offset + language_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, language_len: int language_len): bool = let
  val @(offset, language_len) = _trim_front(data, offset, language_len)
  val subtag_len = _subtag_end(data, offset, language_len, 0)
in _span_is(data, offset, subtag_len, "ja") || _span_is(data, offset, subtag_len, "zh") || _span_is(data, offset, subtag_len, "ko") end

(* Whether the language tag data[offset, offset + language_len) is
   Mongolian in its traditional script (mn-Mong), which is set
   vertically, its lines going on to the right *)
fn _language_mongolian_script {l:agz}{n:pos}{offset,language_len:nat | offset + language_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, language_len: int language_len): bool = let
  val @(offset, language_len) = _trim_front(data, offset, language_len)
  val subtag_len = _subtag_end(data, offset, language_len, 0)
in
  if ~_span_is(data, offset, subtag_len, "mn") then false
  else if subtag_len + 5 > language_len then false
  else let
    val script_offset = offset + subtag_len + 1
    val script_end = _subtag_end(data, script_offset, language_len - subtag_len - 1, 0)
  in
    _span_is(data, script_offset, script_end, "Mong") || _span_is(data, script_offset, script_end, "mong") || _span_is(data, script_offset, script_end, "MONG")
  end
end

(* How a book is set: horizontally; vertically, its lines going on to
   the left (vertical-rl); or vertically, its lines going on to the
   right (vertical-lr) *)
#pub datatype writing_mode =
  | Horizontal
  | VerticalRightToLeft
  | VerticalLeftToRight

(* How the book is set, as Readium decides it from its OPF (the book's
   own CSS is not used): vertical-rl when its spine reads right to left
   and its language is Chinese, Japanese or Korean; vertical-lr when it
   is Mongolian in its traditional script and its spine does not read
   right to left; else horizontally *)
#pub fn spine_vertical
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): writing_mode

implement spine_vertical (data, nodes) = let
  val right_to_left = (case+ _spine_rtl_nodes(data, nodes) of
    | SpineRightToLeft() => true
    | SpineLeftToRight() => false
    | SpineDefault() => false
    | NoSpine() => false): bool
in
  case+ _opf_language_nodes(data, nodes) of
  | ~xspan_at(language_offset, language_len) =>
    if right_to_left then
      (if _language_east_asian(data, language_offset, language_len) then VerticalRightToLeft() else Horizontal())
    else if _language_mongolian_script(data, language_offset, language_len) then VerticalLeftToRight()
    else Horizontal()
  | ~xspan_none() => Horizontal()
end

(* The href of the first manifest item that is a font *)
fun _font_item_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _font_item(data, node) of
     | ~xspan_none() => _font_item_nodes(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _font_item
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): xspan(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var item_chars = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, tag_offset, tag_len, item_chars, 4) then let
      var media_type_chars = @[char][10]('m', 'e', 'd', 'i', 'a', '-', 't', 'y', 'p', 'e')
      var font_chars = @[char][4]('f', 'o', 'n', 't')
      var opentype_chars = @[char][8]('o', 'p', 'e', 'n', 't', 'y', 'p', 'e')
    in
      case+ _find_attr_value(data, attrs, media_type_chars, 10) of
      | ~xspan_at(media_type_offset, media_type_len) =>
        if (if _span_has(data, media_type_offset, media_type_len, font_chars, 4, 0) then true else _span_has(data, media_type_offset, media_type_len, opentype_chars, 8, 0)) then let
          var href_chars = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_value(data, attrs, href_chars, 4) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _font_item_nodes(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the book's first embedded font *)
#pub fn find_font_href
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): xspan(n)

implement find_font_href (data, nodes) = _font_item_nodes(data, nodes)

(* ============================================================
   Fixed layout (EPUB 3.3 §8.2): the OPF's rendition:layout, each
   itemref's own, and a page's viewport meta
   ============================================================ *)

(* How a book, or one of its spine items, is laid out: reflowed (the
   reader's pages and typography), or pre-paginated (fixed layout: each
   spine item one page of its own size, scaled to fit) *)
#pub datatype rendition_layout =
  | Reflowable
  | PrePaginated

(* What a <meta property="rendition:layout"> says, or that none is met *)
datatype layout_said =
  | LayoutUnsaid
  | LayoutSaysReflowable
  | LayoutSaysPrePaginated

(* What the meta's value says: pre-paginated, or (anything else, as
   "reflowable", the default) reflowable *)
fn _layout_of_value {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): layout_said = let
  val @(value_offset, value_len) = _trim(data, offset, span_len)
in if _span_is(data, value_offset, value_len, "pre-paginated") then LayoutSaysPrePaginated() else LayoutSaysReflowable() end

fun _layout_meta_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): layout_said =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => (case+ _layout_meta(data, node) of
    | LayoutUnsaid() => _layout_meta_nodes(data, rest)
    | LayoutSaysReflowable() => LayoutSaysReflowable()
    | LayoutSaysPrePaginated() => LayoutSaysPrePaginated())
  | $X.xml_nodes_nil() => LayoutUnsaid()

and _layout_meta
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): layout_said =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var property_chars = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (case+ _find_attr_value(data, attrs, property_chars, 8) of
       | ~xspan_at(property_offset, property_len) =>
         if _span_is(data, property_offset, property_len, "rendition:layout") then
           (case+ _get_first_text(children) of
            | ~xspan_at(value_offset, value_len) => _layout_of_value(data, value_offset, value_len)
            | ~xspan_none() => LayoutUnsaid())
         else LayoutUnsaid()
       | ~xspan_none() => LayoutUnsaid())
    else _layout_meta_nodes(data, children)
  end
  | $X.xml_text(_, _) => LayoutUnsaid()

(* The book's layout: its OPF's rendition:layout meta, reflowable when
   it has none *)
#pub fn opf_layout
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): rendition_layout

implement opf_layout (data, nodes) =
  case+ _layout_meta_nodes(data, nodes) of
  | LayoutSaysPrePaginated() => PrePaginated()
  | LayoutSaysReflowable() => Reflowable()
  | LayoutUnsaid() => Reflowable()

(* The search for an itemref: the properties of the one sought (none
   when it has no properties attribute), or how many itemrefs are left
   to skip after the nodes searched *)
datavtype itemref_search(n:int) =
  | ItemrefFound(n) of xspan(n)
  | ItemrefAfter(n) of int

fun _itemref_properties_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), skip: int): itemref_search(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => (case+ _itemref_properties_node(data, node, skip) of
    | ~ItemrefAfter(left) => _itemref_properties_nodes(data, rest, left)
    | found => found)
  | $X.xml_nodes_nil() => ItemrefAfter(skip)

and _itemref_properties_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), skip: int): itemref_search(n) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var itemref_chars = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
    var properties_chars = @[char][10]('p', 'r', 'o', 'p', 'e', 'r', 't', 'i', 'e', 's')
  in
    if xml_name_eq(data, tag_offset, tag_len, itemref_chars, 7) then
      if skip <= 0 then ItemrefFound(_find_attr_value(data, attrs, properties_chars, 10))
      else ItemrefAfter(skip - 1)
    else _itemref_properties_nodes(data, children, skip)
  end
  | $X.xml_text(_, _) => ItemrefAfter(skip)

(* The layout of spine item item_index: its itemref's
   rendition:layout-pre-paginated or rendition:layout-reflowable
   property, else the book's *)
#pub fn itemref_layout_n
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), item_index: int, book_layout: rendition_layout): rendition_layout

implement itemref_layout_n (data, nodes, item_index, book_layout) =
  case+ _itemref_properties_nodes(data, nodes, item_index) of
  | ~ItemrefAfter(_) => book_layout
  | ~ItemrefFound(properties) => (case+ properties of
    | ~xspan_none() => book_layout
    | ~xspan_at(properties_offset, properties_len) => let
        var pre_paginated_chars = @[char][30]('r', 'e', 'n', 'd', 'i', 't', 'i', 'o', 'n', ':', 'l', 'a', 'y', 'o', 'u', 't', '-', 'p', 'r', 'e', '-', 'p', 'a', 'g', 'i', 'n', 'a', 't', 'e', 'd')
        var reflowable_chars = @[char][27]('r', 'e', 'n', 'd', 'i', 't', 'i', 'o', 'n', ':', 'l', 'a', 'y', 'o', 'u', 't', '-', 'r', 'e', 'f', 'l', 'o', 'w', 'a', 'b', 'l', 'e')
      in
        if _span_has(data, properties_offset, properties_len, pre_paginated_chars, 30, 0) then PrePaginated()
        else if _span_has(data, properties_offset, properties_len, reflowable_chars, 27, 0) then Reflowable()
        else book_layout
      end)

(* A fixed-layout page's size in CSS pixels, its initial containing
   block (EPUB RS 3.3 §8.1.2): the width and height its viewport meta
   gives, each 1 to 10000; or none, when it has no viewport meta or
   either is missing, not a number, or out of that range *)
#pub datavtype viewport =
  | {width,height:pos | width <= 10000; height <= 10000} Viewport of (int width, int height)
  | NoViewport of ()

#pub fn viewport_free (size: viewport): void

implement viewport_free (size) =
  case+ size of
  | ~Viewport(_, _) => ()
  | ~NoViewport() => ()

(* One of the viewport's sizes, or none *)
datavtype dimension =
  | {size:pos | size <= 10000} Dimension of int size
  | NoDimension of ()

(* The first position at or after position in data[offset, offset +
   span_len) that is not white space *)
fun _skip_spaces {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{position:nat | position <= span_len} .<span_len - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, position: int position): [after:nat | after <= span_len] int after =
  if position >= span_len then position
  else if byte2int0($A.read<byte>(data, offset + position)) <= 32 then _skip_spaces(data, offset, span_len, position + 1)
  else position

(* value, then the decimal digits from position on (a unit after them,
   such as "px", is the number's end); past 100000 it stops growing *)
fun _digits_value {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{position:nat | position <= span_len} .<span_len - position>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, position: int position, value: int): int =
  if position >= span_len then value
  else let
    val digit = byte2int0($A.read<byte>(data, offset + position)) - 48
  in
    if digit < 0 then value
    else if digit > 9 then value
    else if value > 100000 then value
    else _digits_value(data, offset, span_len, position + 1, value * 10 + digit)
  end

(* Whether the byte before position (when there is one) ends a
   viewport key: the content's start, white space, ',' or ';' *)
fn _key_starts {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{position:nat | position <= span_len}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, position: int position): bool =
  if position <= 0 then true
  else let
    val before = byte2int0($A.read<byte>(data, offset + position - 1))
  in before <= 32 || before = 44 || before = 59 end

(* The number given to key ("width" or "height") in the viewport
   meta's content data[offset, offset + span_len), from position on:
   key, then '=' (white space around it allowed), then its digits *)
fun _viewport_dimension {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{key_len:pos}{position:nat} .<max(span_len - position, 0)>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, key: string key_len, key_len: int key_len, position: int position): dimension =
  if position + key_len > span_len then NoDimension()
  else if (if _key_starts(data, offset, span_len, position) then _lowercase_from(data, offset + position, key, key_len, 0) else false) then let
    val after_key = _skip_spaces(data, offset, span_len, position + key_len)
  in
    if after_key >= span_len then NoDimension()
    else if byte2int0($A.read<byte>(data, offset + after_key)) <> 61 then
      _viewport_dimension(data, offset, span_len, key, key_len, position + 1)
    else let
      val value = g1ofg0(_digits_value(data, offset, span_len, _skip_spaces(data, offset, span_len, after_key + 1), 0))
    in if value <= 0 then NoDimension() else if value > 10000 then NoDimension() else Dimension(value) end
  end
  else _viewport_dimension(data, offset, span_len, key, key_len, position + 1)

(* The viewport the content data[offset, offset + span_len) of a
   viewport meta gives *)
fn _viewport_of {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): viewport =
  case+ _viewport_dimension(data, offset, span_len, "width", 5, 0) of
  | ~NoDimension() => NoViewport()
  | ~Dimension(width) => (case+ _viewport_dimension(data, offset, span_len, "height", 6, 0) of
    | ~NoDimension() => NoViewport()
    | ~Dimension(height) => Viewport(width, height))

fun _viewport_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): viewport =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => (case+ _viewport_node(data, node) of
    | ~NoViewport() => _viewport_nodes(data, rest)
    | found => found)
  | $X.xml_nodes_nil() => NoViewport()

and _viewport_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): viewport =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var name_chars = @[char][4]('n', 'a', 'm', 'e')
    var content_chars = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
    var body_chars = @[char][4]('b', 'o', 'd', 'y')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (case+ _find_attr_value(data, attrs, name_chars, 4) of
       | ~xspan_at(meta_name_offset, meta_name_len) =>
         if _span_is(data, meta_name_offset, meta_name_len, "viewport") then
           (case+ _find_attr_value(data, attrs, content_chars, 7) of
            | ~xspan_at(content_offset, content_len) => _viewport_of(data, content_offset, content_len)
            | ~xspan_none() => NoViewport())
         else NoViewport()
       | ~xspan_none() => NoViewport())
    (* the viewport meta is in the head: the body is not searched *)
    else if xml_name_eq(data, tag_offset, tag_len, body_chars, 4) then NoViewport()
    else _viewport_nodes(data, children)
  end
  | $X.xml_text(_, _) => NoViewport()

(* The viewport of a fixed-layout page: its XHTML's first viewport
   meta, read as EPUB RS 3.3 §8.1.2 says *)
#pub fn xhtml_viewport
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): viewport

implement xhtml_viewport (data, nodes) = _viewport_nodes(data, nodes)

(* ============================================================
   Spreads (EPUB 3.3 §8.2.2): the OPF's rendition:spread, and each
   itemref's page-spread-* property
   ============================================================ *)

(* When fixed pages are shown two at a time: never, only when the view
   is wider than tall, always, or as the reader thinks best (which
   quire takes as landscape, as Apple Books and Thorium do).
   "portrait", deprecated, is read as both, as EPUB 3.3 says *)
#pub datatype rendition_spread =
  | SpreadNone
  | SpreadLandscape
  | SpreadBoth
  | SpreadAuto

(* What a <meta property="rendition:spread"> says, or that none is met *)
datatype spread_said =
  | SpreadUnsaid
  | SpreadSaysNone
  | SpreadSaysLandscape
  | SpreadSaysBoth
  | SpreadSaysAuto

fn _spread_of_value {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): spread_said = let
  val @(value_offset, value_len) = _trim(data, offset, span_len)
in
  if _span_is(data, value_offset, value_len, "none") then SpreadSaysNone()
  else if _span_is(data, value_offset, value_len, "landscape") then SpreadSaysLandscape()
  else if _span_is(data, value_offset, value_len, "both") then SpreadSaysBoth()
  else if _span_is(data, value_offset, value_len, "portrait") then SpreadSaysBoth()
  else SpreadSaysAuto()
end

fun _spread_meta_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): spread_said =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => (case+ _spread_meta(data, node) of
    | SpreadUnsaid() => _spread_meta_nodes(data, rest)
    | SpreadSaysNone() => SpreadSaysNone()
    | SpreadSaysLandscape() => SpreadSaysLandscape()
    | SpreadSaysBoth() => SpreadSaysBoth()
    | SpreadSaysAuto() => SpreadSaysAuto())
  | $X.xml_nodes_nil() => SpreadUnsaid()

and _spread_meta
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): spread_said =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var property_chars = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (case+ _find_attr_value(data, attrs, property_chars, 8) of
       | ~xspan_at(property_offset, property_len) =>
         if _span_is(data, property_offset, property_len, "rendition:spread") then
           (case+ _get_first_text(children) of
            | ~xspan_at(value_offset, value_len) => _spread_of_value(data, value_offset, value_len)
            | ~xspan_none() => SpreadUnsaid())
         else SpreadUnsaid()
       | ~xspan_none() => SpreadUnsaid())
    else _spread_meta_nodes(data, children)
  end
  | $X.xml_text(_, _) => SpreadUnsaid()

(* The book's rendition:spread, auto when it has none *)
#pub fn opf_spread
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): rendition_spread

implement opf_spread (data, nodes) =
  case+ _spread_meta_nodes(data, nodes) of
  | SpreadSaysNone() => SpreadNone()
  | SpreadSaysLandscape() => SpreadLandscape()
  | SpreadSaysBoth() => SpreadBoth()
  | SpreadSaysAuto() => SpreadAuto()
  | SpreadUnsaid() => SpreadAuto()

(* Which side of a spread a spine item asks for: either (none asked),
   the left, the right, or the centre (a page shown alone, across both) *)
#pub datatype page_spread =
  | SpreadSlotAny
  | SpreadSlotLeft
  | SpreadSlotRight
  | SpreadSlotCenter

(* The side of a spread spine item item_index asks for: its itemref's
   rendition:page-spread-left, -right or -center property, or the older
   page-spread-left or -right (which those end with) *)
#pub fn itemref_spread_n
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), item_index: int): page_spread

implement itemref_spread_n (data, nodes, item_index) =
  case+ _itemref_properties_nodes(data, nodes, item_index) of
  | ~ItemrefAfter(_) => SpreadSlotAny()
  | ~ItemrefFound(properties) => (case+ properties of
    | ~xspan_none() => SpreadSlotAny()
    | ~xspan_at(properties_offset, properties_len) => let
        var left_chars = @[char][16]('p', 'a', 'g', 'e', '-', 's', 'p', 'r', 'e', 'a', 'd', '-', 'l', 'e', 'f', 't')
        var right_chars = @[char][17]('p', 'a', 'g', 'e', '-', 's', 'p', 'r', 'e', 'a', 'd', '-', 'r', 'i', 'g', 'h', 't')
        var center_chars = @[char][18]('p', 'a', 'g', 'e', '-', 's', 'p', 'r', 'e', 'a', 'd', '-', 'c', 'e', 'n', 't', 'e', 'r')
      in
        if _span_has(data, properties_offset, properties_len, left_chars, 16, 0) then SpreadSlotLeft()
        else if _span_has(data, properties_offset, properties_len, right_chars, 17, 0) then SpreadSlotRight()
        else if _span_has(data, properties_offset, properties_len, center_chars, 18, 0) then SpreadSlotCenter()
        else SpreadSlotAny()
      end)

(* ============================================================
   META-INF/encryption.xml: what a book declares to be encrypted with
   (quire#427)
   ============================================================ *)

(* What an encryption.xml declares. EncryptionNone: nothing, or only
   the two font obfuscations a reading system undoes itself (IDPF's
   http://www.idpf.org/2008/embedding and Adobe's
   http://ns.adobe.com/pdf/enc#RC), which are no DRM. The others are a
   protection Quire has no client for: Adobe's ADEPT (its namespace),
   Readium LCP (its profile), Kobo's (kobo.com or kobobooks.com in a namespace), or an
   EncryptionMethod whose Algorithm is neither obfuscation *)
#pub datatype encryption_found =
  | EncryptionNone
  | EncryptionAdept
  | EncryptionLcp
  | EncryptionKobo
  | EncryptionUnknownAlgorithm

(* Whether the algorithm named at data[offset, offset + name_len) is
   one of the two font obfuscations *)
fn _is_obfuscation {l:agz}{n:pos}{offset,name_len:nat | offset + name_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, name_len: int name_len): bool = let
  var idpf_chars = @[char][34]('h', 't', 't', 'p', ':', '/', '/', 'w', 'w', 'w', '.', 'i', 'd', 'p', 'f', '.', 'o', 'r', 'g', '/', '2', '0', '0', '8', '/', 'e', 'm', 'b', 'e', 'd', 'd', 'i', 'n', 'g')
  var adobe_chars = @[char][30]('h', 't', 't', 'p', ':', '/', '/', 'n', 's', '.', 'a', 'd', 'o', 'b', 'e', '.', 'c', 'o', 'm', '/', 'p', 'd', 'f', '/', 'e', 'n', 'c', '#', 'R', 'C')
in
  if xml_name_eq(data, offset, name_len, idpf_chars, 34) then true
  else xml_name_eq(data, offset, name_len, adobe_chars, 30)
end

(* Whether an EncryptionMethod anywhere in nodes names an algorithm
   that is not a font obfuscation (or names none) *)
fun _unknown_algorithm_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): bool =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    if _unknown_algorithm_node(data, node) then true
    else _unknown_algorithm_nodes(data, rest)
  | $X.xml_nodes_nil() => false

and _unknown_algorithm_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): bool =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var method_chars = @[char][16]('E', 'n', 'c', 'r', 'y', 'p', 't', 'i', 'o', 'n', 'M', 'e', 't', 'h', 'o', 'd')
  in
    if _span_has(data, tag_offset, tag_len, method_chars, 16, 0) then let
      var algorithm_chars = @[char][9]('A', 'l', 'g', 'o', 'r', 'i', 't', 'h', 'm')
    in
      case+ _find_attr_value(data, attrs, algorithm_chars, 9) of
      | ~xspan_at(algorithm_offset, algorithm_len) => ~_is_obfuscation(data, algorithm_offset, algorithm_len)
      | ~xspan_none() => true
    end
    else _unknown_algorithm_nodes(data, children)
  end
  | $X.xml_text(_, _) => false

(* What the encryption.xml data[0, n), parsed as nodes, declares *)
#pub fn encryption_of
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), n: int n, nodes: !$X.xml_node_list(n, tree_size)): encryption_found

implement encryption_of (data, n, nodes) = let
  var adept_chars = @[char][18]('n', 's', '.', 'a', 'd', 'o', 'b', 'e', '.', 'c', 'o', 'm', '/', 'a', 'd', 'e', 'p', 't')
  var lcp_chars = @[char][23]('r', 'e', 'a', 'd', 'i', 'u', 'm', '.', 'o', 'r', 'g', '/', '2', '0', '1', '4', '/', '0', '1', '/', 'l', 'c', 'p')
  var kobo_chars = @[char][8]('k', 'o', 'b', 'o', '.', 'c', 'o', 'm')
  var kobobooks_chars = @[char][13]('k', 'o', 'b', 'o', 'b', 'o', 'o', 'k', 's', '.', 'c', 'o', 'm')
in
  if _span_has(data, 0, n, adept_chars, 18, 0) then EncryptionAdept()
  else if _span_has(data, 0, n, lcp_chars, 23, 0) then EncryptionLcp()
  else if _span_has(data, 0, n, kobo_chars, 8, 0) then EncryptionKobo()
  else if _span_has(data, 0, n, kobobooks_chars, 13, 0) then EncryptionKobo()
  else if _unknown_algorithm_nodes(data, nodes) then EncryptionUnknownAlgorithm()
  else EncryptionNone()
end
