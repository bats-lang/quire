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

(* Byte at p, or 0 outside [0, n). *)
#pub fn peek {l:agz}{n:pos}{p:int}
  (src: !$A.borrow(byte, l, n), p: int p, n: int n): int

implement peek (src, p, n) =
  if p < 0 then 0
  else if p >= n then 0
  else byte2int0($A.read<byte>(src, p))

(* An offset from zip (find_eocd, get_data_offset), or ~1 if none. *)
#pub fn zip_off (o: $R.option([o:nat] int o)): pos_t

implement zip_off (o) =
  case+ o of
  | ~$R.some(v) => v
  | ~$R.none() => ~1

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
   Borrow copy utilities
   ============================================================ *)

(* To do: zip offsets are not yet proven inside the file (the zip
   package returns unindexed ints), so this copy still checks each
   position; it goes when zip returns proven regions. *)
fun _copy_from_borrow_r
  {lb:agz}{nb:pos}{la:agz}{na:pos}{fuel:nat}{do_:int} .<fuel>.
  (src: !$A.borrow(byte, lb, nb), src_off: pos_t, src_max: int nb,
   dst: !$A.arr(byte, la, na), dst_off: int do_, dst_max: int na,
   count: int, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if count <= 0 then ()
  else if src_off < 0 then ()
  else if dst_off < 0 then ()
  else if src_off >= src_max then ()
  else if dst_off >= dst_max then ()
  else let
    val b = peek(src, src_off, src_max)
    val () = $A.set<byte>(dst, dst_off, int2byte0(b))
  in
    _copy_from_borrow_r(src, src_off + 1, src_max, dst, dst_off + 1, dst_max, count - 1, fuel - 1)
  end

(* To do: used only for the chapter path in reader, whose prefix length
   still comes from the stash unindexed; it goes with the typed reader
   state. *)
#pub fn copy_from_borrow
  {lb:agz}{nb:pos}{la:agz}{na:pos}{do_:int}
  (src: !$A.borrow(byte, lb, nb), src_off: pos_t, src_max: int nb,
   dst: !$A.arr(byte, la, na), dst_off: int do_, dst_max: int na,
   count: int): void

implement copy_from_borrow(src, src_off, src_max, dst, dst_off, dst_max, count) =
  _copy_from_borrow_r(src, src_off, src_max, dst, dst_off, dst_max, count, src_max)

#pub fn copy_arr_region
  {ls:agz}{ns:pos}{ld:agz}{nd:pos}
  (src: $A.arr(byte, ls, ns), src_off: pos_t, src_max: int ns,
   dst: !$A.arr(byte, ld, nd), dst_max: int nd,
   count: int): $A.arr(byte, ls, ns)

implement copy_arr_region(src, src_off, src_max, dst, dst_max, count) = let
  val @(frozen, borrow) = $A.freeze<byte>(src)
  val () = _copy_from_borrow_r(borrow, src_off, src_max,
                             dst, 0, dst_max, count, src_max)
  val () = $A.drop<byte>(frozen, borrow)
in $A.thaw<byte>(frozen) end

(* ============================================================
   Spans of a parsed document
   ============================================================ *)

(* A span [o, o + k) of an n-byte document (from xml-tree, which proves
   it inside the document), or none *)
#pub datatype xspan(n:int) =
  | {o,k:nat | o + k <= n} xspan_at(n) of (int o, int k)
  | xspan_none(n) of ()

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

(* ============================================================
   Container.xml: find rootfile full-path
   ============================================================ *)

fun _walk_rootfile_nodes_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ _walk_rootfile_node(data, node) of
     | xspan_none() => _walk_rootfile_nodes_r(data, rest)
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
    if xml_name_eq(data, name_off, name_len, _c_title, 8) then
      @(_get_first_text(children), author)
    else if xml_name_eq(data, name_off, name_len, _c_creator, 10) then
      @(title, _get_first_text(children))
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
      | xspan_none() => _find_nth_idref_r(data, rest, left)
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
     | xspan_none() => _find_manifest_href_r(data, len, rest, idref_off, idref_len)
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
      | xspan_at(id_off, id_len) =>
        if id_len <> idref_len then xspan_none()
        else if $S.borrow_region_eq(data, len, id_off, idref_off, idref_len) then let
          var _c_href = @[char][4]('h', 'r', 'e', 'f')
        in _find_attr_val(data, attrs, _c_href, 4) end
        else xspan_none()
      | xspan_none() => xspan_none()
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
  | xspan_at(o, k) => _find_manifest_href_r(data, len, nodes, o, k)
  | xspan_none() => xspan_none()
end
