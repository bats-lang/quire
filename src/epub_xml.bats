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
    if xml_name_eq(data, tag_offset, tag_len, title_chars, 8) then let
      val () = xspan_free(title)
    in @(_get_first_text(children), author) end
    else if xml_name_eq(data, tag_offset, tag_len, creator_chars, 10) then let
      val () = xspan_free(author)
    in @(title, _get_first_text(children)) end
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

(* The text of the OPF's dc:title and dc:creator *)
#pub fn walk_opf_metadata
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): @(xspan(n), xspan(n))

implement walk_opf_metadata(data, nodes) =
  _opf_metadata_nodes(data, nodes, xspan_none(), xspan_none())

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

(* The flags, a bit each (A11Y_KNOWN when any of these is in the OPF) *)
#pub macdef A11Y_TRANSFORM = 1        (* accessibilityFeature displayTransformability *)
#pub macdef A11Y_ALT = 2              (* alternativeText *)
#pub macdef A11Y_LONGDESC = 4         (* longDescription *)
#pub macdef A11Y_SUFF_TEXT = 8        (* accessModeSufficient textual *)
#pub macdef A11Y_MODE_TEXT = 16       (* accessMode textual *)
#pub macdef A11Y_MODE_VISUAL = 32     (* accessMode visual *)
#pub macdef A11Y_HZ_NONE = 64         (* accessibilityHazard none *)
#pub macdef A11Y_HZ_FLASH = 128       (* flashing *)
#pub macdef A11Y_HZ_MOTION = 256      (* motionSimulation *)
#pub macdef A11Y_HZ_SOUND = 512       (* sound *)
#pub macdef A11Y_HZ_NOFLASH = 1024    (* noFlashingHazard *)
#pub macdef A11Y_HZ_NOMOTION = 2048   (* noMotionSimulationHazard *)
#pub macdef A11Y_HZ_NOSOUND = 4096    (* noSoundHazard *)
#pub macdef A11Y_HZ_UNKNOWN = 8192    (* unknown *)
#pub macdef A11Y_TOC = 16384          (* tableOfContents *)
#pub macdef A11Y_INDEX = 32768        (* index *)
#pub macdef A11Y_STRUCT = 65536       (* structuralNavigation *)
#pub macdef A11Y_PAGES = 131072       (* pageNavigation *)
#pub macdef A11Y_MATHML = 262144      (* MathML *)
#pub macdef A11Y_TRANSCRIPT = 524288  (* transcript *)
#pub macdef A11Y_CAPTIONS = 1048576   (* captions or closedCaptions *)
#pub macdef A11Y_KNOWN = 2097152
(* the WCAG level conformsTo names, times A11Y_LEVEL: 1 A, 2 AA, 3 AAA *)
#pub macdef A11Y_LEVEL = 4194304

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

(* The WCAG level a conformance statement or URL names: 3 AAA, 2 AA,
   1 A, 0 none *)
fn _wcag_level {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len): int =
  if _has_lowercase(data, offset, span_len, "aaa", 3, 0) then 3
  else if _has_lowercase(data, offset, span_len, "level aa", 8, 0) then 2
  else if _has_lowercase(data, offset, span_len, "wcag-aa", 7, 0) then 2
  else if _has_lowercase(data, offset, span_len, "level a", 7, 0) then 1
  else if _has_lowercase(data, offset, span_len, "wcag-a", 6, 0) then 1
  else 0

(* flags, with the bit that says the book has accessibility metadata *)
fn _known (flags: int): int = _bit_or(flags, A11Y_KNOWN)

(* The flag a property's value sets *)
fn _a11y_value {l:agz}{n:pos}{property_offset,property_len,value_offset,value_len:nat | property_offset + property_len <= n; value_offset + value_len <= n}
  (data: !$A.borrow(byte, l, n), property_offset: int property_offset, property_len: int property_len, value_offset: int value_offset, value_len: int value_len): int = let
  val @(value_offset, value_len) = _trim(data, value_offset, value_len)
in
  if _span_is(data, property_offset, property_len, "schema:accessibilityFeature") then
    _known(if _span_is(data, value_offset, value_len, "displayTransformability") then A11Y_TRANSFORM
     else if _span_is(data, value_offset, value_len, "alternativeText") then A11Y_ALT
     else if _span_is(data, value_offset, value_len, "longDescription") then A11Y_LONGDESC
     else if _span_is(data, value_offset, value_len, "tableOfContents") then A11Y_TOC
     else if _span_is(data, value_offset, value_len, "index") then A11Y_INDEX
     else if _span_is(data, value_offset, value_len, "structuralNavigation") then A11Y_STRUCT
     else if _span_is(data, value_offset, value_len, "pageNavigation") then A11Y_PAGES
     else if _span_is(data, value_offset, value_len, "MathML") then A11Y_MATHML
     else if _span_is(data, value_offset, value_len, "transcript") then A11Y_TRANSCRIPT
     else if _span_is(data, value_offset, value_len, "closedCaptions") then A11Y_CAPTIONS
     else if _span_is(data, value_offset, value_len, "captions") then A11Y_CAPTIONS
     else 0)
  else if _span_is(data, property_offset, property_len, "schema:accessMode") then
    _known(if _span_is(data, value_offset, value_len, "textual") then A11Y_MODE_TEXT
     else if _span_is(data, value_offset, value_len, "visual") then A11Y_MODE_VISUAL
     else 0)
  else if _span_is(data, property_offset, property_len, "schema:accessModeSufficient") then
    _known(if _span_is(data, value_offset, value_len, "textual") then A11Y_SUFF_TEXT else 0)
  else if _span_is(data, property_offset, property_len, "schema:accessibilityHazard") then
    _known(if _span_is(data, value_offset, value_len, "none") then A11Y_HZ_NONE
     else if _span_is(data, value_offset, value_len, "flashing") then A11Y_HZ_FLASH
     else if _span_is(data, value_offset, value_len, "motionSimulation") then A11Y_HZ_MOTION
     else if _span_is(data, value_offset, value_len, "sound") then A11Y_HZ_SOUND
     else if _span_is(data, value_offset, value_len, "noFlashingHazard") then A11Y_HZ_NOFLASH
     else if _span_is(data, value_offset, value_len, "noMotionSimulationHazard") then A11Y_HZ_NOMOTION
     else if _span_is(data, value_offset, value_len, "noSoundHazard") then A11Y_HZ_NOSOUND
     else if _span_is(data, value_offset, value_len, "unknown") then A11Y_HZ_UNKNOWN
     else 0)
  else if _span_is(data, property_offset, property_len, "dcterms:conformsTo") then
    _known(_wcag_level(data, value_offset, value_len) * A11Y_LEVEL)
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

(* The OPF's accessibility metadata: its flags (the A11Y_ bits), and its
   accessibilitySummary's text, if any *)
#pub fn opf_a11y
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): @(int, xspan(n))

implement opf_a11y(data, nodes) = _a11y_nodes(data, nodes, 0, xspan_none())

(* ============================================================
   Series: EPUB 3's belongs-to-collection and group-position, or
   Calibre's calibre:series and calibre:series_index
   ============================================================ *)

(* The whole number at data[offset, offset + span_len) (digits before
   any '.'), its digits after those of number; 0 when there is none; at
   most 99999 *)
fun _whole_number {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n} .<span_len>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, number: int): int =
  if span_len <= 0 then number
  else let
    val digit_byte = byte2int0($A.read<byte>(data, offset))
  in
    if digit_byte = 32 then (if number = 0 then _whole_number(data, offset + 1, span_len - 1, number) else number)
    else if digit_byte < 48 then number
    else if digit_byte > 57 then number
    else if number > 9999 then number
    else _whole_number(data, offset + 1, span_len - 1, number * 10 + (digit_byte - 48))
  end

(* The series found in nodes so far: its name, and its number *)
fun _series_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), name: xspan(n), number: int): @(xspan(n), int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(name, number) = _series_node(data, node, name, number)
    in _series_nodes(data, rest, name, number) end
  | $X.xml_nodes_nil() => @(name, number)

and _series_node
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), name: xspan(n), number: int): @(xspan(n), int) =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var meta_chars = @[char][4]('m', 'e', 't', 'a')
    var property_chars = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
    var name_chars = @[char][4]('n', 'a', 'm', 'e')
    var content_chars = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
  in
    if xml_name_eq(data, tag_offset, tag_len, meta_chars, 4) then
      (case+ _find_attr_value(data, attrs, property_chars, 8) of
       | ~xspan_at(property_offset, property_len) =>
         (case+ _get_first_text(children) of
          | ~xspan_at(value_offset, value_len) =>
            if _span_is(data, property_offset, property_len, "belongs-to-collection") then
              (case+ name of
               | xspan_none() => let val () = xspan_free(name) in @(xspan_at(value_offset, value_len), number) end
               | _ => @(name, number))
            else if _span_is(data, property_offset, property_len, "group-position") then
              @(name, (if number = 0 then _whole_number(data, value_offset, value_len, 0) else number))
            else @(name, number)
          | ~xspan_none() => @(name, number))
       | ~xspan_none() =>
         (case+ _find_attr_value(data, attrs, name_chars, 4) of
          | ~xspan_at(property_offset, property_len) =>
            (case+ _find_attr_value(data, attrs, content_chars, 7) of
             | ~xspan_at(value_offset, value_len) =>
               if _span_is(data, property_offset, property_len, "calibre:series") then
                 (case+ name of
                  | xspan_none() => let val () = xspan_free(name) in @(xspan_at(value_offset, value_len), number) end
                  | _ => @(name, number))
               else if _span_is(data, property_offset, property_len, "calibre:series_index") then
                 @(name, (if number = 0 then _whole_number(data, value_offset, value_len, 0) else number))
               else @(name, number)
             | ~xspan_none() => @(name, number))
          | ~xspan_none() => @(name, number)))
    else _series_nodes(data, children, name, number)
  end
  | $X.xml_text(_, _) => @(name, number)

(* The book's series (its name, when it has one) and its number in it
   (0 when none is given) *)
#pub fn opf_series
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): @(xspan(n), int)

implement opf_series(data, nodes) = _series_nodes(data, nodes, xspan_none(), 0)

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

(* Whether data[offset, offset + span_len) has pattern[0, pattern_len)
   in it *)
#pub fn span_has {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{pattern_len:pos}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len, pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool

implement span_has (data, offset, span_len, pattern, pattern_len) = _span_has(data, offset, span_len, pattern, pattern_len, 0)

(* Whether the first <spine> reads right to left *)
fun _spine_rtl_nodes
  {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): int =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val direction = _spine_rtl(data, node)
    in if direction >= 0 then direction else _spine_rtl_nodes(data, rest) end
  | $X.xml_nodes_nil() => ~1

(* At a <spine>: 1 right to left, 0 left to right, 2 when it does not
   say (or says "default"); -1 when the node has none *)
and _spine_rtl
  {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size)): int =
  case+ node of
  | $X.xml_element(tag_offset, tag_len, attrs, children) => let
    var spine_chars = @[char][5]('s', 'p', 'i', 'n', 'e')
  in
    if xml_name_eq(data, tag_offset, tag_len, spine_chars, 5) then let
      var page_progression_chars = @[char][26]('p', 'a', 'g', 'e', '-', 'p', 'r', 'o', 'g', 'r', 'e', 's', 's', 'i', 'o', 'n', '-', 'd', 'i', 'r', 'e', 'c', 't', 'i', 'o', 'n')
      var rtl_chars = @[char][3]('r', 't', 'l')
      var ltr_chars = @[char][3]('l', 't', 'r')
    in
      (* 2: none said, or "default" *)
      case+ _find_attr_value(data, attrs, page_progression_chars, 26) of
      | ~xspan_at(value_offset, value_len) => if xml_name_eq(data, value_offset, value_len, rtl_chars, 3) then 1
          else if xml_name_eq(data, value_offset, value_len, ltr_chars, 3) then 0 else 2
      | ~xspan_none() => 2
    end
    else _spine_rtl_nodes(data, children)
  end
  | $X.xml_text(_, _) => ~1

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

implement spine_rtl (data, nodes) = let
  val direction = _spine_rtl_nodes(data, nodes)
in
  if direction = 1 then true
  else if direction = 0 then false
  else case+ _opf_language_nodes(data, nodes) of
    | ~xspan_at(language_offset, language_len) => _language_rtl(data, language_offset, language_len)
    | ~xspan_none() => false
end

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

(* How the book is set, as Readium decides it from its OPF (the book's
   own CSS is not used): 1 vertically with its lines going on to the
   left (vertical-rl), when its spine reads right to left and its
   language is Chinese, Japanese or Korean; 2 vertically with its lines
   going on to the right (vertical-lr), when it is Mongolian in its
   traditional script and its spine does not read right to left; else 0,
   horizontally *)
#pub fn spine_vertical
  {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): int

implement spine_vertical (data, nodes) = let
  val direction = _spine_rtl_nodes(data, nodes)
in
  case+ _opf_language_nodes(data, nodes) of
  | ~xspan_at(language_offset, language_len) =>
    if direction = 1 then (if _language_east_asian(data, language_offset, language_len) then 1 else 0)
    else if _language_mongolian_script(data, language_offset, language_len) then 2
    else 0
  | ~xspan_none() => 0
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
