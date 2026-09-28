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
