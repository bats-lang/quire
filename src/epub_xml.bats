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
#pub typedef pos_t = [p:int] int p

(* ============================================================
   Array to text conversion
   ============================================================ *)

fun _arr_to_text_loop
  {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (src: !$A.arr(byte, l, n), len: int n,
   tb: $A.text_builder(n, i), pos: int i): $A.text_builder(n, n) =
  if pos >= len then tb
  else let
    val b = byte2int0($A.get<byte>(src, pos))
    val tb = $A.text_putc(tb, pos, $AR.byte_of_char(int2char0(b)))
  in _arr_to_text_loop(src, len, tb, pos + 1) end

#pub fn arr_to_text
  {l:agz}{n:pos}
  (src: !$A.arr(byte, l, n), len: int n): $A.text(n)

implement arr_to_text{l}{n}(src, len) = let
  val tb = $A.text_build(len)
  val tb = _arr_to_text_loop(src, len, tb, 0)
in $A.text_done(tb) end

(* ============================================================
   Spans of a parsed document
   ============================================================ *)

(* A span [o, o + k) of an n-byte document (from xml-tree, which proves
   it inside the document), or none. Linear: a datatype's cell is never
   freed (there is no GC), so each span is consumed by a ~ pattern or by
   xspan_free. *)
#pub datavtype xspan(n:int) =
  | {o,k:nat | o + k <= n} xspan_at(n) of (int o, int k)
  | xspan_none(n) of ()

#pub fn xspan_free {n:int} (s: xspan(n)): void

implement xspan_free (s) =
  case+ s of
  | ~xspan_at(_, _) => ()
  | ~xspan_none() => ()

(* ============================================================
   XML name matching
   ============================================================ *)

fun _match_chars {lb:agz}{n:pos}{o:nat}{np:pos | o + np <= n}{i:nat | i <= np} .<np - i>.
  (data: !$A.borrow(byte, lb, n), o: int o, pat: &(@[char][np]), plen: int np, i: int i): bool =
  if i >= plen then true
  else if byte2int0($A.read<byte>(data, o + i)) <> char2int0(pat.[i]) then false
  else _match_chars(data, o, pat, plen, i + 1)

(* Whether the name at [o, o + k) is pat *)
#pub fn xml_name_eq
  {lb:agz}{n:pos}{o,k:nat | o + k <= n}{np:pos}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k,
   pat: &(@[char][np]), plen: int np): bool

implement xml_name_eq(data, o, k, pat, plen) =
  if k <> plen then false
  else _match_chars(data, o, pat, plen, 0)

(* ============================================================
   XML attribute lookup (internal)
   ============================================================ *)

fun _find_attr_val
  {lb:agz}{n:pos}{sa:nat}{np:pos} .<sa>.
  (data: !$A.borrow(byte, lb, n),
   attrs: !$X.xml_attr_list(n, sa),
   aname: &(@[char][np]), alen: int np): xspan(n) =
  case+ attrs of
  | $X.xml_attrs_cons(aname_off, aname_len, val_off, val_len, rest) =>
    if xml_name_eq(data, aname_off, aname_len, aname, alen) then xspan_at(val_off, val_len)
    else _find_attr_val(data, rest, aname, alen)
  | $X.xml_attrs_nil() => xspan_none()

(* The value of the attribute named aname among attrs, when there is one *)
#pub fn find_attr
  {lb:agz}{n:pos}{sa:nat}{np:pos}
  (data: !$A.borrow(byte, lb, n),
   attrs: !$X.xml_attr_list(n, sa),
   aname: &(@[char][np]), alen: int np): xspan(n)

implement find_attr(data, attrs, aname, alen) = _find_attr_val(data, attrs, aname, alen)

(* ============================================================
   Container.xml: find rootfile full-path
   ============================================================ *)

fun _walk_rootfile_nodes_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _walk_rootfile_node(data, node) of
     | ~xspan_none() => _walk_rootfile_nodes_r(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _walk_rootfile_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz)): xspan(n) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_rootfile = @[char][8]('r', 'o', 'o', 't', 'f', 'i', 'l', 'e')
    var _c_fp = @[char][9]('f', 'u', 'l', 'l', '-', 'p', 'a', 't', 'h')
  in
    if xml_name_eq(data, name_off, name_len, _c_rootfile, 8) then
      _find_attr_val(data, attrs, _c_fp, 9)
    else _walk_rootfile_nodes_r(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The full-path attribute of container.xml's first rootfile *)
#pub fn walk_rootfile_nodes
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n)

implement walk_rootfile_nodes(data, nodes) = _walk_rootfile_nodes_r(data, nodes)

(* ============================================================
   OPF: extract title/author from metadata
   ============================================================ *)

fun _walk_opf_metadata_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz),
   title: xspan(n), author: xspan(n)): @(xspan(n), xspan(n)) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(t, a) = _walk_opf_node(data, node, title, author)
    in _walk_opf_metadata_r(data, rest, t, a) end
  | $X.xml_nodes_nil() => @(title, author)

and _walk_opf_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz),
   title: xspan(n), author: xspan(n)): @(xspan(n), xspan(n)) =
  case+ node of
  | $X.xml_element(name_off, name_len, _, children) => let
    var _c_title = @[char][8]('d', 'c', ':', 't', 'i', 't', 'l', 'e')
    var _c_creator = @[char][10]('d', 'c', ':', 'c', 'r', 'e', 'a', 't', 'o', 'r')
  in
    if xml_name_eq(data, name_off, name_len, _c_title, 8) then let
      val () = xspan_free(title)
    in @(_get_first_text(children), author) end
    else if xml_name_eq(data, name_off, name_len, _c_creator, 10) then let
      val () = xspan_free(author)
    in @(title, _get_first_text(children)) end
    else _walk_opf_metadata_r(data, children, title, author)
  end
  | $X.xml_text(_, _) => @(title, author)

and _get_first_text
  {n:int}{sz:nat} .<sz, 0>.
  (children: !$X.xml_node_list(n, sz)): xspan(n) =
  case+ children of
  | $X.xml_nodes_cons(node, _) =>
    (case+ node of
     | $X.xml_text(off, tlen) => xspan_at(off, tlen)
     | $X.xml_element(_, _, _, _) => xspan_none())
  | $X.xml_nodes_nil() => xspan_none()

(* The text of the OPF's dc:title and dc:creator *)
#pub fn walk_opf_metadata
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): @(xspan(n), xspan(n))

implement walk_opf_metadata(data, nodes) =
  _walk_opf_metadata_r(data, nodes, xspan_none(), xspan_none())

(* The text of the OPF's first dc:language *)
fun _opf_lang_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _opf_lang_node(data, node)
    in
      case+ r of
      | ~xspan_none() => _opf_lang_r(data, rest)
      | _ => r
    end
  | $X.xml_nodes_nil() => xspan_none()

and _opf_lang_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz)): xspan(n) =
  case+ node of
  | $X.xml_element(name_off, name_len, _, children) => let
    var _c_lang = @[char][11]('d', 'c', ':', 'l', 'a', 'n', 'g', 'u', 'a', 'g', 'e')
  in
    if xml_name_eq(data, name_off, name_len, _c_lang, 11) then _get_first_text(children)
    else _opf_lang_r(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

#pub fn opf_language
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n)

implement opf_language(data, nodes) = _opf_lang_r(data, nodes)

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

(* Whether data[o, o + k) is s *)
fun _span_is_at {lb:agz}{n:pos}{o,k:nat | o + k <= n}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, s: string sn, sl: int sn, i: int i): bool =
  if i >= sl then true
  else if i >= k then false
  else if byte2int0($A.read<byte>(data, o + i)) <> char2int0(string_get_at(s, i)) then false
  else _span_is_at(data, o, k, s, sl, i + 1)

fn _span_is {lb:agz}{n:pos}{o,k:nat | o + k <= n}{sn:nat}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, s: string sn): bool = let
  val sl = g1u2i(string1_length(s))
in if k <> sl then false else _span_is_at(data, o, k, s, sl, 0) end

(* data[o, o + k) without the white space around it *)
fun _trim_front {lb:agz}{n:pos}{o,k:nat | o + k <= n} .<k>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k): [o2,k2:nat | o2 + k2 <= n] @(int o2, int k2) =
  if k <= 0 then @(o, k)
  else if byte2int0($A.read<byte>(data, o)) <= 32 then _trim_front(data, o + 1, k - 1)
  else @(o, k)

fun _trim_back {lb:agz}{n:pos}{o,k:nat | o + k <= n} .<k>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k): [k2:nat | k2 <= k] int k2 =
  if k <= 0 then k
  else if byte2int0($A.read<byte>(data, o + k - 1)) <= 32 then _trim_back(data, o, k - 1)
  else k

fn _trim {lb:agz}{n:pos}{o,k:nat | o + k <= n}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k): [o2,k2:nat | o2 + k2 <= n] @(int o2, int k2) = let
  val @(o2, k2) = _trim_front(data, o, k)
  val k3 = _trim_back(data, o2, k2)
in @(o2, k3) end

(* Whether data[p, p + sl), in lower case, is s (lower case), from j *)
fun _lower_from {lb:agz}{n:pos}{sn:pos}{p:nat | p + sn <= n}{j:nat | j <= sn} .<sn - j>.
  (data: !$A.borrow(byte, lb, n), p: int p, s: string sn, sl: int sn, j: int j): bool =
  if j >= sl then true
  else let
    val c = byte2int0($A.read<byte>(data, p + j))
    val c = (if c >= 65 then (if c <= 90 then c + 32 else c) else c): int
  in if c <> char2int0(string_get_at(s, j)) then false else _lower_from(data, p, s, sl, j + 1) end

(* Whether data[o, o + k), in lower case, has s (lower case) from i *)
fun _has_lower {lb:agz}{n:pos}{o,k:nat | o + k <= n}{sn:pos}{i:nat} .<max(k - i, 0)>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, s: string sn, sl: int sn, i: int i): bool =
  if i + sl > k then false
  else if _lower_from(data, o + i, s, sl, 0) then true
  else _has_lower(data, o, k, s, sl, i + 1)

fn _bor (a: int, b: int): int = $AR.bor_int_int(a, b)

(* The WCAG level a conformance statement or URL names: 3 AAA, 2 AA,
   1 A, 0 none *)
fn _wcag_level {lb:agz}{n:pos}{o,k:nat | o + k <= n}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k): int =
  if _has_lower(data, o, k, "aaa", 3, 0) then 3
  else if _has_lower(data, o, k, "level aa", 8, 0) then 2
  else if _has_lower(data, o, k, "wcag-aa", 7, 0) then 2
  else if _has_lower(data, o, k, "level a", 7, 0) then 1
  else if _has_lower(data, o, k, "wcag-a", 6, 0) then 1
  else 0

(* v, with the bit that says the book has accessibility metadata *)
fn _known (v: int): int = _bor(v, A11Y_KNOWN)

(* The flag a property's value v sets *)
fn _a11y_value {lb:agz}{n:pos}{po,pk,vo,vk:nat | po + pk <= n; vo + vk <= n}
  (data: !$A.borrow(byte, lb, n), po: int po, pk: int pk, vo: int vo, vk: int vk): int = let
  val @(vo, vk) = _trim(data, vo, vk)
in
  if _span_is(data, po, pk, "schema:accessibilityFeature") then
    _known(if _span_is(data, vo, vk, "displayTransformability") then A11Y_TRANSFORM
     else if _span_is(data, vo, vk, "alternativeText") then A11Y_ALT
     else if _span_is(data, vo, vk, "longDescription") then A11Y_LONGDESC
     else if _span_is(data, vo, vk, "tableOfContents") then A11Y_TOC
     else if _span_is(data, vo, vk, "index") then A11Y_INDEX
     else if _span_is(data, vo, vk, "structuralNavigation") then A11Y_STRUCT
     else if _span_is(data, vo, vk, "pageNavigation") then A11Y_PAGES
     else if _span_is(data, vo, vk, "MathML") then A11Y_MATHML
     else if _span_is(data, vo, vk, "transcript") then A11Y_TRANSCRIPT
     else if _span_is(data, vo, vk, "closedCaptions") then A11Y_CAPTIONS
     else if _span_is(data, vo, vk, "captions") then A11Y_CAPTIONS
     else 0)
  else if _span_is(data, po, pk, "schema:accessMode") then
    _known(if _span_is(data, vo, vk, "textual") then A11Y_MODE_TEXT
     else if _span_is(data, vo, vk, "visual") then A11Y_MODE_VISUAL
     else 0)
  else if _span_is(data, po, pk, "schema:accessModeSufficient") then
    _known(if _span_is(data, vo, vk, "textual") then A11Y_SUFF_TEXT else 0)
  else if _span_is(data, po, pk, "schema:accessibilityHazard") then
    _known(if _span_is(data, vo, vk, "none") then A11Y_HZ_NONE
     else if _span_is(data, vo, vk, "flashing") then A11Y_HZ_FLASH
     else if _span_is(data, vo, vk, "motionSimulation") then A11Y_HZ_MOTION
     else if _span_is(data, vo, vk, "sound") then A11Y_HZ_SOUND
     else if _span_is(data, vo, vk, "noFlashingHazard") then A11Y_HZ_NOFLASH
     else if _span_is(data, vo, vk, "noMotionSimulationHazard") then A11Y_HZ_NOMOTION
     else if _span_is(data, vo, vk, "noSoundHazard") then A11Y_HZ_NOSOUND
     else if _span_is(data, vo, vk, "unknown") then A11Y_HZ_UNKNOWN
     else 0)
  else if _span_is(data, po, pk, "dcterms:conformsTo") then
    _known(_wcag_level(data, vo, vk) * A11Y_LEVEL)
  else if _span_is(data, po, pk, "schema:accessibilitySummary") then _known(0)
  else 0
end

(* The flags of nodes, or'd onto acc, and the summary (the first one) *)
fun _a11y_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz), acc: int, summary: xspan(n)): @(int, xspan(n)) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(acc, summary) = _a11y_node(data, node, acc, summary)
    in _a11y_r(data, rest, acc, summary) end
  | $X.xml_nodes_nil() => @(acc, summary)

and _a11y_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz), acc: int, summary: xspan(n)): @(int, xspan(n)) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_meta = @[char][4]('m', 'e', 't', 'a')
    var _c_link = @[char][4]('l', 'i', 'n', 'k')
    var _c_property = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
    var _c_name = @[char][4]('n', 'a', 'm', 'e')
    var _c_content = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
    var _c_rel = @[char][3]('r', 'e', 'l')
    var _c_href = @[char][4]('h', 'r', 'e', 'f')
  in
    if xml_name_eq(data, name_off, name_len, _c_meta, 4) then
      (* EPUB 3: <meta property="p">v</meta>; EPUB 2: <meta name="p" content="v"/> *)
      (case+ _find_attr_val(data, attrs, _c_property, 8) of
       | ~xspan_at(po, pk) =>
         (case+ _get_first_text(children) of
          | ~xspan_at(vo, vk) => let
              val f = _a11y_value(data, po, pk, vo, vk)
              val is_summary = _span_is(data, po, pk, "schema:accessibilitySummary")
            in
              case+ summary of
              | xspan_none() => if is_summary then let
                    val () = xspan_free(summary)
                  in @(_bor(acc, f), xspan_at(vo, vk)) end
                  else @(_bor(acc, f), summary)
              | _ => @(_bor(acc, f), summary)
            end
          | ~xspan_none() => @(acc, summary))
       | ~xspan_none() =>
         (case+ _find_attr_val(data, attrs, _c_name, 4) of
          | ~xspan_at(po, pk) =>
            (case+ _find_attr_val(data, attrs, _c_content, 7) of
             | ~xspan_at(vo, vk) => let
                 val f = _a11y_value(data, po, pk, vo, vk)
                 val is_summary = _span_is(data, po, pk, "schema:accessibilitySummary")
               in
                 case+ summary of
                 | xspan_none() => if is_summary then let
                       val () = xspan_free(summary)
                     in @(_bor(acc, f), xspan_at(vo, vk)) end
                     else @(_bor(acc, f), summary)
                 | _ => @(_bor(acc, f), summary)
               end
             | ~xspan_none() => @(acc, summary))
          | ~xspan_none() => @(acc, summary)))
    else if xml_name_eq(data, name_off, name_len, _c_link, 4) then
      (case+ _find_attr_val(data, attrs, _c_rel, 3) of
       | ~xspan_at(ro, rk) =>
         (case+ _find_attr_val(data, attrs, _c_href, 4) of
          | ~xspan_at(ho, hk) => @(_bor(acc, _a11y_value(data, ro, rk, ho, hk)), summary)
          | ~xspan_none() => @(acc, summary))
       | ~xspan_none() => @(acc, summary))
    else _a11y_r(data, children, acc, summary)
  end
  | $X.xml_text(_, _) => @(acc, summary)

(* The OPF's accessibility metadata: its flags (the A11Y_ bits), and its
   accessibilitySummary's text, if any *)
#pub fn opf_a11y
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): @(int, xspan(n))

implement opf_a11y(data, nodes) = _a11y_r(data, nodes, 0, xspan_none())

(* ============================================================
   Series: EPUB 3's belongs-to-collection and group-position, or
   Calibre's calibre:series and calibre:series_index
   ============================================================ *)

(* The whole number at data[o, o + k) (digits before any '.'), 0 when
   there is none; at most 99999 *)
fun _whole {lb:agz}{n:pos}{o,k:nat | o + k <= n} .<k>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, acc: int): int =
  if k <= 0 then acc
  else let
    val c = byte2int0($A.read<byte>(data, o))
  in
    if c = 32 then (if acc = 0 then _whole(data, o + 1, k - 1, acc) else acc)
    else if c < 48 then acc
    else if c > 57 then acc
    else if acc > 9999 then acc
    else _whole(data, o + 1, k - 1, acc * 10 + (c - 48))
  end

(* The series found in nodes so far: its name, and its number *)
fun _series_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz), name: xspan(n), num: int): @(xspan(n), int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(name, num) = _series_node(data, node, name, num)
    in _series_r(data, rest, name, num) end
  | $X.xml_nodes_nil() => @(name, num)

and _series_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz), name: xspan(n), num: int): @(xspan(n), int) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_meta = @[char][4]('m', 'e', 't', 'a')
    var _c_property = @[char][8]('p', 'r', 'o', 'p', 'e', 'r', 't', 'y')
    var _c_name = @[char][4]('n', 'a', 'm', 'e')
    var _c_content = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
  in
    if xml_name_eq(data, name_off, name_len, _c_meta, 4) then
      (case+ _find_attr_val(data, attrs, _c_property, 8) of
       | ~xspan_at(po, pk) =>
         (case+ _get_first_text(children) of
          | ~xspan_at(vo, vk) =>
            if _span_is(data, po, pk, "belongs-to-collection") then
              (case+ name of
               | xspan_none() => let val () = xspan_free(name) in @(xspan_at(vo, vk), num) end
               | _ => @(name, num))
            else if _span_is(data, po, pk, "group-position") then
              @(name, (if num = 0 then _whole(data, vo, vk, 0) else num))
            else @(name, num)
          | ~xspan_none() => @(name, num))
       | ~xspan_none() =>
         (case+ _find_attr_val(data, attrs, _c_name, 4) of
          | ~xspan_at(po, pk) =>
            (case+ _find_attr_val(data, attrs, _c_content, 7) of
             | ~xspan_at(vo, vk) =>
               if _span_is(data, po, pk, "calibre:series") then
                 (case+ name of
                  | xspan_none() => let val () = xspan_free(name) in @(xspan_at(vo, vk), num) end
                  | _ => @(name, num))
               else if _span_is(data, po, pk, "calibre:series_index") then
                 @(name, (if num = 0 then _whole(data, vo, vk, 0) else num))
               else @(name, num)
             | ~xspan_none() => @(name, num))
          | ~xspan_none() => @(name, num)))
    else _series_r(data, children, name, num)
  end
  | $X.xml_text(_, _) => @(name, num)

(* The book's series (its name, when it has one) and its number in it
   (0 when none is given) *)
#pub fn opf_series
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): @(xspan(n), int)

implement opf_series(data, nodes) = _series_r(data, nodes, xspan_none(), 0)

(* ============================================================
   Spine: find Nth idref
   ============================================================ *)

(* The idref of the itemref after skip others, or how many remain to
   skip *)
fun _find_nth_idref_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz),
   skip: int): @(xspan(n), int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(r, left) = _check_itemref_nth(data, node, skip)
    in
      case+ r of
      | ~xspan_none() => _find_nth_idref_r(data, rest, left)
      | _ => @(r, left)
    end
  | $X.xml_nodes_nil() => @(xspan_none(), skip)

and _check_itemref_nth
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz),
   skip: int): @(xspan(n), int) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_itemref = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
    var _c_idref = @[char][5]('i', 'd', 'r', 'e', 'f')
  in
    if xml_name_eq(data, name_off, name_len, _c_itemref, 7) then
      if skip <= 0 then @(_find_attr_val(data, attrs, _c_idref, 5), 0)
      else @(xspan_none(), skip - 1)
    else _find_nth_idref_r(data, children, skip)
  end
  | $X.xml_text(_, _) => @(xspan_none(), skip)

(* ============================================================
   Spine: count items
   ============================================================ *)

fun _count_spine_items_r
  {lb:agz}{n:pos}{sz:nat}{c:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz),
   acc: int c): [d:nat] int d =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
      _count_spine_items_r(data, rest, _count_itemref(data, node, acc))
  | $X.xml_nodes_nil() => acc

and _count_itemref
  {lb:agz}{n:pos}{sz:pos}{c:nat} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz),
   acc: int c): [d:nat] int d =
  case+ node of
  | $X.xml_element(name_off, name_len, _, children) => let
    var _c_itemref = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
  in
    if xml_name_eq(data, name_off, name_len, _c_itemref, 7) then acc + 1
    else _count_spine_items_r(data, children, acc)
  end
  | $X.xml_text(_, _) => acc

(* Number of itemref elements *)
#pub fn count_spine_items
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): [c:nat] int c

implement count_spine_items(data, nodes) = _count_spine_items_r(data, nodes, 0)

(* ============================================================
   Manifest: find href by idref
   ============================================================ *)

fun _find_manifest_href_r
  {lb:agz}{n:pos}{sz:nat}{io,ik:nat | io + ik <= n} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n, nodes: !$X.xml_node_list(n, sz),
   idref_off: int io, idref_len: int ik): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _check_manifest_item(data, len, node, idref_off, idref_len) of
     | ~xspan_none() => _find_manifest_href_r(data, len, rest, idref_off, idref_len)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _check_manifest_item
  {lb:agz}{n:pos}{sz:pos}{io,ik:nat | io + ik <= n} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n, node: !$X.xml_node(n, sz),
   idref_off: int io, idref_len: int ik): xspan(n) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_item = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, name_off, name_len, _c_item, 4) then let
      var _c_id = @[char][2]('i', 'd')
    in
      case+ _find_attr_val(data, attrs, _c_id, 2) of
      | ~xspan_at(id_off, id_len) =>
        if id_len <> idref_len then xspan_none()
        else if $S.borrow_region_eq(data, len, id_off, idref_off, idref_len) then let
          var _c_href = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_val(data, attrs, _c_href, 4) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _find_manifest_href_r(data, len, children, idref_off, idref_len)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the manifest item for the chapter_idx-th spine itemref *)
#pub fn find_chapter_href_n
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(n, sz), chapter_idx: int): xspan(n)

implement find_chapter_href_n(data, len, nodes, chapter_idx) = let
  val @(idref, _) = _find_nth_idref_r(data, nodes, chapter_idx)
in
  case+ idref of
  | ~xspan_at(o, k) => _find_manifest_href_r(data, len, nodes, o, k)
  | ~xspan_none() => xspan_none()
end

(* ============================================================
   Manifest: items by property, meta by name
   ============================================================ *)

(* Whether data[o, o + k) has pat[0, np) in it at or after i *)
fun _span_has {lb:agz}{n:pos}{o,k:nat | o + k <= n}{np:pos}{i:nat} .<max(k - i + 1, 0)>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, pat: &(@[char][np]), np: int np, i: int i): bool =
  if i + np > k then false
  else if _match_chars(data, o + i, pat, np, 0) then true
  else _span_has(data, o, k, pat, np, i + 1)

(* The href of the first manifest item whose properties have prop *)
fun _item_with_prop_r
  {lb:agz}{n:pos}{sz:nat}{np:pos} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz),
   prop: &(@[char][np]), np: int np): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _item_with_prop(data, node, prop, np) of
     | ~xspan_none() => _item_with_prop_r(data, rest, prop, np)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _item_with_prop
  {lb:agz}{n:pos}{sz:pos}{np:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz),
   prop: &(@[char][np]), np: int np): xspan(n) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_item = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, name_off, name_len, _c_item, 4) then let
      var _c_props = @[char][10]('p', 'r', 'o', 'p', 'e', 'r', 't', 'i', 'e', 's')
    in
      case+ _find_attr_val(data, attrs, _c_props, 10) of
      | ~xspan_at(po, pk) =>
        if _span_has(data, po, pk, prop, np, 0) then let
          var _c_href = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_val(data, attrs, _c_href, 4) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _item_with_prop_r(data, children, prop, np)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The content of the first <meta name="cover"> *)
fun _meta_cover_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _meta_cover(data, node) of
     | ~xspan_none() => _meta_cover_r(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _meta_cover
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz)): xspan(n) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_meta = @[char][4]('m', 'e', 't', 'a')
  in
    if xml_name_eq(data, name_off, name_len, _c_meta, 4) then let
      var _c_name = @[char][4]('n', 'a', 'm', 'e')
      var _c_cover = @[char][5]('c', 'o', 'v', 'e', 'r')
    in
      case+ _find_attr_val(data, attrs, _c_name, 4) of
      | ~xspan_at(no, nk) =>
        if xml_name_eq(data, no, nk, _c_cover, 5) then let
          var _c_content = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
        in _find_attr_val(data, attrs, _c_content, 7) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _meta_cover_r(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the book's cover image: the manifest item with property
   cover-image (EPUB 3), else the item a <meta name="cover"> names
   (EPUB 2) *)
#pub fn find_cover_href
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n, nodes: !$X.xml_node_list(n, sz)): xspan(n)

implement find_cover_href (data, len, nodes) = let
  var _c_ci = @[char][11]('c', 'o', 'v', 'e', 'r', '-', 'i', 'm', 'a', 'g', 'e')
in
  case+ _item_with_prop_r(data, nodes, _c_ci, 11) of
  | ~xspan_none() =>
    (case+ _meta_cover_r(data, nodes) of
     | ~xspan_at(io, ik) => _find_manifest_href_r(data, len, nodes, io, ik)
     | ~xspan_none() => xspan_none())
  | found => found
end

(* The href of the manifest item with property prop (such as "nav") *)
#pub fn find_item_with_prop
  {lb:agz}{n:pos}{sz:nat}{np:pos}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz),
   prop: &(@[char][np]), np: int np): xspan(n)

implement find_item_with_prop (data, nodes, prop, np) = _item_with_prop_r(data, nodes, prop, np)

(* The href of the manifest item with id data[io, io + ik) *)
#pub fn find_manifest_href
  {lb:agz}{n:pos}{sz:nat}{io,ik:nat | io + ik <= n}
  (data: !$A.borrow(byte, lb, n), len: int n, nodes: !$X.xml_node_list(n, sz),
   io: int io, ik: int ik): xspan(n)

implement find_manifest_href (data, len, nodes, io, ik) = _find_manifest_href_r(data, len, nodes, io, ik)

(* The toc attribute of the first <spine> *)
fun _spine_toc_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _spine_toc(data, node) of
     | ~xspan_none() => _spine_toc_r(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _spine_toc
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz)): xspan(n) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_spine = @[char][5]('s', 'p', 'i', 'n', 'e')
  in
    if xml_name_eq(data, name_off, name_len, _c_spine, 5) then let
      var _c_toc = @[char][3]('t', 'o', 'c')
    in _find_attr_val(data, attrs, _c_toc, 3) end
    else _spine_toc_r(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the NCX (EPUB 2's table of contents): the manifest item
   the spine's toc attribute names *)
#pub fn find_ncx_href
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n, nodes: !$X.xml_node_list(n, sz)): xspan(n)

implement find_ncx_href (data, len, nodes) =
  case+ _spine_toc_r(data, nodes) of
  | ~xspan_at(io, ik) => _find_manifest_href_r(data, len, nodes, io, ik)
  | ~xspan_none() => xspan_none()

(* Whether data[o, o + k) has pat[0, np) in it *)
#pub fn span_has {lb:agz}{n:pos}{o,k:nat | o + k <= n}{np:pos}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, pat: &(@[char][np]), np: int np): bool

implement span_has (data, o, k, pat, np) = _span_has(data, o, k, pat, np, 0)

(* Whether the first <spine> reads right to left *)
fun _spine_rtl_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): int =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _spine_rtl(data, node)
    in if r >= 0 then r else _spine_rtl_r(data, rest) end
  | $X.xml_nodes_nil() => ~1

(* At a <spine>: 1 right to left, 0 left to right, 2 when it does not
   say (or says "default"); -1 when the node has none *)
and _spine_rtl
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz)): int =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_spine = @[char][5]('s', 'p', 'i', 'n', 'e')
  in
    if xml_name_eq(data, name_off, name_len, _c_spine, 5) then let
      var _c_ppd = @[char][26]('p', 'a', 'g', 'e', '-', 'p', 'r', 'o', 'g', 'r', 'e', 's', 's', 'i', 'o', 'n', '-', 'd', 'i', 'r', 'e', 'c', 't', 'i', 'o', 'n')
      var _c_rtl = @[char][3]('r', 't', 'l')
      var _c_ltr = @[char][3]('l', 't', 'r')
    in
      (* 2: none said, or "default" *)
      case+ _find_attr_val(data, attrs, _c_ppd, 26) of
      | ~xspan_at(vo, vk) => if xml_name_eq(data, vo, vk, _c_rtl, 3) then 1
          else if xml_name_eq(data, vo, vk, _c_ltr, 3) then 0 else 2
      | ~xspan_none() => 2
    end
    else _spine_rtl_r(data, children)
  end
  | $X.xml_text(_, _) => ~1

(* Where a language tag's primary subtag ends in data[o, o + k): at its
   first '-' or '_' *)
fun _subtag_end {lb:agz}{n:pos}{o,k:nat | o + k <= n}{j:nat | j <= k} .<k - j>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, j: int j): [e:nat | e <= k] int e =
  if j >= k then k
  else let
    val c = byte2int0($A.read<byte>(data, o + j))
  in if c = 45 || c = 95 then j else _subtag_end(data, o, k, j + 1) end

(* Whether the language tag data[o, o + k) is of a language written right
   to left: Arabic, Hebrew (and its old code iw), Persian, Urdu,
   Yiddish (and ji), Pashto, Sindhi, Uyghur, Dhivehi, Kashmiri, Central
   Kurdish, Syriac, Aramaic *)
fn _lang_rtl {lb:agz}{n:pos}{o,k:nat | o + k <= n}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k): bool = let
  val @(o, k) = _trim_front(data, o, k)
  val e = _subtag_end(data, o, k, 0)
in
  _span_is(data, o, e, "ar") || _span_is(data, o, e, "he") || _span_is(data, o, e, "iw")
  || _span_is(data, o, e, "fa") || _span_is(data, o, e, "ur") || _span_is(data, o, e, "yi")
  || _span_is(data, o, e, "ji") || _span_is(data, o, e, "ps") || _span_is(data, o, e, "sd")
  || _span_is(data, o, e, "ug") || _span_is(data, o, e, "dv") || _span_is(data, o, e, "ks")
  || _span_is(data, o, e, "ckb") || _span_is(data, o, e, "syr") || _span_is(data, o, e, "arc")
end

(* Whether the book reads right to left: as its spine's
   page-progression-direction says; when that says nothing, or
   "default" (the reading system's choice), when its language is
   written right to left, as Readium does *)
#pub fn spine_rtl
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): bool

implement spine_rtl (data, nodes) = let
  val r = _spine_rtl_r(data, nodes)
in
  if r = 1 then true
  else if r = 0 then false
  else case+ _opf_lang_r(data, nodes) of
    | ~xspan_at(o, k) => _lang_rtl(data, o, k)
    | ~xspan_none() => false
end

(* The href of the first manifest item that is a font *)
fun _font_item_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _font_item(data, node) of
     | ~xspan_none() => _font_item_r(data, rest)
     | found => found)
  | $X.xml_nodes_nil() => xspan_none()

and _font_item
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz)): xspan(n) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_item = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, name_off, name_len, _c_item, 4) then let
      var _c_mt = @[char][10]('m', 'e', 'd', 'i', 'a', '-', 't', 'y', 'p', 'e')
      var _c_font = @[char][4]('f', 'o', 'n', 't')
      var _c_otf = @[char][8]('o', 'p', 'e', 'n', 't', 'y', 'p', 'e')
    in
      case+ _find_attr_val(data, attrs, _c_mt, 10) of
      | ~xspan_at(mo, mk) =>
        if (if _span_has(data, mo, mk, _c_font, 4, 0) then true else _span_has(data, mo, mk, _c_otf, 8, 0)) then let
          var _c_href = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_val(data, attrs, _c_href, 4) end
        else xspan_none()
      | ~xspan_none() => xspan_none()
    end
    else _font_item_r(data, children)
  end
  | $X.xml_text(_, _) => xspan_none()

(* The href of the book's first embedded font *)
#pub fn find_font_href
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n)

implement find_font_href (data, nodes) = _font_item_r(data, nodes)
