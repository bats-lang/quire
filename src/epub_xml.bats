(* epub_xml -- EPUB/XML parsing helpers and array utilities *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use str as S
#use xml-tree as X

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

fun _copy_from_borrow_r
  {lb:agz}{nb:pos}{la:agz}{na:pos}{fuel:nat}{do_:int} .<fuel>.
  (src: !$A.borrow(byte, lb, nb), src_off: int, src_max: int nb,
   dst: !$A.arr(byte, la, na), dst_off: int do_, dst_max: int na,
   count: int fuel): void =
  if count <= 0 then ()
  else if src_off < 0 then ()
  else if dst_off < 0 then ()
  else if src_off >= src_max then ()
  else if dst_off >= dst_max then ()
  else let
    val b = $S.borrow_byte(src, src_off, src_max)
    val () = $A.set<byte>(dst, dst_off, int2byte0(b))
  in
    _copy_from_borrow_r(src, src_off + 1, src_max, dst, dst_off + 1, dst_max, count - 1)
  end

#pub fn copy_from_borrow
  {lb:agz}{nb:pos}{la:agz}{na:pos}{fuel:nat}{do_:int}
  (src: !$A.borrow(byte, lb, nb), src_off: int, src_max: int nb,
   dst: !$A.arr(byte, la, na), dst_off: int do_, dst_max: int na,
   count: int fuel): void

implement copy_from_borrow(src, src_off, src_max, dst, dst_off, dst_max, count) =
  _copy_from_borrow_r(src, src_off, src_max, dst, dst_off, dst_max, count)

#pub fn copy_arr_region
  {ls:agz}{ns:pos}{ld:agz}{nd:pos}{c:nat}
  (src: $A.arr(byte, ls, ns), src_off: int, src_max: int ns,
   dst: !$A.arr(byte, ld, nd), dst_max: int nd,
   count: int c): $A.arr(byte, ls, ns)

implement copy_arr_region(src, src_off, src_max, dst, dst_max, count) = let
  val @(frozen, borrow) = $A.freeze<byte>(src)
  val () = copy_from_borrow(borrow, src_off, src_max,
                             dst, 0, dst_max, count)
  val () = $A.drop<byte>(frozen, borrow)
in $A.thaw<byte>(frozen) end

(* ============================================================
   XML name matching (internal)
   ============================================================ *)

fun _match_chars {lb:agz}{n:pos}{np:pos}{k:nat | k <= np} .<np - k>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   off: int, pat: &(@[char][np]), plen: int np,
   i: int k): bool =
  if i >= plen then true
  else let
    val db = $S.borrow_byte(data, off + i, len)
    val pb = char2int0(pat.[i])
  in
    if db != pb then false
    else _match_chars(data, len, off, pat, plen, i + 1)
  end

#pub fn xml_name_eq
  {lb:agz}{n:pos}{np:pos}
  (data: !$A.borrow(byte, lb, n), len: int n,
   name_off: int, name_len: int,
   pat: &(@[char][np]), plen: int np): bool

implement xml_name_eq(data, len, name_off, name_len, pat, plen) =
  if name_len != plen then false
  else if name_off < 0 then false
  else if name_off + name_len > len then false
  else _match_chars(data, len, name_off, pat, plen, 0)

(* ============================================================
   Borrow region comparison
   ============================================================ *)

fun _borrow_region_eq_r
  {lb:agz}{n:pos}{fuel:nat} .<fuel>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   off_a: int, off_b: int, count: int fuel): bool =
  if count <= 0 then true
  else if off_a < 0 then false
  else if off_b < 0 then false
  else if off_a >= len then false
  else if off_b >= len then false
  else let
    val a = $S.borrow_byte(data, off_a, len)
    val b = $S.borrow_byte(data, off_b, len)
  in
    if a != b then false
    else _borrow_region_eq_r(data, len, off_a + 1, off_b + 1, count - 1)
  end

#pub fn borrow_region_eq
  {lb:agz}{n:pos}{fuel:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   off_a: int, off_b: int, count: int fuel): bool

implement borrow_region_eq(data, len, off_a, off_b, count) =
  _borrow_region_eq_r(data, len, off_a, off_b, count)

(* ============================================================
   XML attribute lookup (internal)
   ============================================================ *)

fun _find_attr_val
  {lb:agz}{n:pos}{sa:nat}{np:pos} .<sa, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   attrs: !$X.xml_attr_list(sa),
   aname: &(@[char][np]), alen: int np): @(int, int) =
  case+ attrs of
  | $X.xml_attrs_cons(aname_off, aname_len, val_off, val_len, rest) =>
    if xml_name_eq(data, len, aname_off, aname_len, aname, alen) then
      @(val_off, val_len)
    else _find_attr_val(data, len, rest, aname, alen)
  | $X.xml_attrs_nil() => @(~1, 0)

(* ============================================================
   Container.xml: find rootfile full-path
   ============================================================ *)

fun _walk_rootfile_nodes_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz)): @(int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _walk_rootfile_node(data, len, node)
    in
      if r.0 >= 0 then r
      else _walk_rootfile_nodes_r(data, len, rest)
    end
  | $X.xml_nodes_nil() => @(~1, 0)

and _walk_rootfile_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   node: !$X.xml_node(sz)): @(int, int) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_rootfile = @[char][8]('r', 'o', 'o', 't', 'f', 'i', 'l', 'e')
  in
    if xml_name_eq(data, len, name_off, name_len, _c_rootfile, 8) then
      _find_full_path(data, len, attrs)
    else _walk_rootfile_nodes_r(data, len, children)
  end
  | $X.xml_text(_, _) => @(~1, 0)

and _find_full_path
  {lb:agz}{n:pos}{sa:nat} .<sa, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   attrs: !$X.xml_attr_list(sa)): @(int, int) =
  case+ attrs of
  | $X.xml_attrs_cons(aname_off, aname_len, val_off, val_len, rest) => let
    var _c_fp = @[char][9]('f', 'u', 'l', 'l', '-', 'p', 'a', 't', 'h')
  in
    if xml_name_eq(data, len, aname_off, aname_len, _c_fp, 9) then
      @(val_off, val_len)
    else _find_full_path(data, len, rest)
  end
  | $X.xml_attrs_nil() => @(~1, 0)

#pub fn walk_rootfile_nodes
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz)): @(int, int)

implement walk_rootfile_nodes{lb}{n}{sz}(data, len, nodes) =
  _walk_rootfile_nodes_r(data, len, nodes)

(* ============================================================
   OPF: extract title/author from metadata
   ============================================================ *)

fun _walk_opf_metadata_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   t_off: int, t_len: int,
   a_off: int, a_len: int): @(int, int, int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _walk_opf_node(data, len, node, t_off, t_len, a_off, a_len)
    in
      _walk_opf_metadata_r(data, len, rest, r.0, r.1, r.2, r.3)
    end
  | $X.xml_nodes_nil() => @(t_off, t_len, a_off, a_len)

and _walk_opf_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   node: !$X.xml_node(sz),
   t_off: int, t_len: int,
   a_off: int, a_len: int): @(int, int, int, int) =
  case+ node of
  | $X.xml_element(name_off, name_len, _, children) => let
    var _c_title = @[char][8]('d', 'c', ':', 't', 'i', 't', 'l', 'e')
    var _c_creator = @[char][10]('d', 'c', ':', 'c', 'r', 'e', 'a', 't', 'o', 'r')
  in
    if xml_name_eq(data, len, name_off, name_len, _c_title, 8) then
      let val txt = _get_first_text(children)
      in @(txt.0, txt.1, a_off, a_len) end
    else if xml_name_eq(data, len, name_off, name_len, _c_creator, 10) then
      let val txt = _get_first_text(children)
      in @(t_off, t_len, txt.0, txt.1) end
    else _walk_opf_metadata_r(data, len, children, t_off, t_len, a_off, a_len)
  end
  | $X.xml_text(_, _) => @(t_off, t_len, a_off, a_len)

and _get_first_text
  {sz:nat} .<sz, 0>.
  (children: !$X.xml_node_list(sz)): @(int, int) =
  case+ children of
  | $X.xml_nodes_cons(node, _) =>
    (case+ node of
     | $X.xml_text(off, tlen) => @(off, tlen)
     | $X.xml_element(_, _, _, _) => @(~1, 0))
  | $X.xml_nodes_nil() => @(~1, 0)

#pub fn walk_opf_metadata
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   t_off: int, t_len: int,
   a_off: int, a_len: int): @(int, int, int, int)

implement walk_opf_metadata{lb}{n}{sz}(data, len, nodes, t_off, t_len, a_off, a_len) =
  _walk_opf_metadata_r(data, len, nodes, t_off, t_len, a_off, a_len)

(* ============================================================
   Spine: find Nth idref
   ============================================================ *)

fun _find_nth_idref_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   skip: int): @(int, int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _check_itemref_nth(data, len, node, skip)
    in
      if r.0 >= 0 then r
      else _find_nth_idref_r(data, len, rest, r.2)
    end
  | $X.xml_nodes_nil() => @(~1, 0, skip)

and _check_itemref_nth
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   node: !$X.xml_node(sz),
   skip: int): @(int, int, int) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_itemref = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
    var _c_spine = @[char][5]('s', 'p', 'i', 'n', 'e')
    var _c_idref = @[char][5]('i', 'd', 'r', 'e', 'f')
  in
    if xml_name_eq(data, len, name_off, name_len, _c_itemref, 7) then
      if skip <= 0 then let
        val av = _find_attr_val(data, len, attrs, _c_idref, 5)
      in @(av.0, av.1, 0) end
      else @(~1, 0, skip - 1)
    else if xml_name_eq(data, len, name_off, name_len, _c_spine, 5) then
      _find_nth_idref_r(data, len, children, skip)
    else _find_nth_idref_r(data, len, children, skip)
  end
  | $X.xml_text(_, _) => @(~1, 0, skip)

#pub fn find_nth_idref
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   skip: int): @(int, int, int)

implement find_nth_idref{lb}{n}{sz}(data, len, nodes, skip) =
  _find_nth_idref_r(data, len, nodes, skip)

(* ============================================================
   Spine: count items
   ============================================================ *)

fun _count_spine_items_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   acc: int): int =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val c = _count_itemref(data, len, node, acc)
    in _count_spine_items_r(data, len, rest, c) end
  | $X.xml_nodes_nil() => acc

and _count_itemref
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   node: !$X.xml_node(sz),
   acc: int): int =
  case+ node of
  | $X.xml_element(name_off, name_len, _, children) => let
    var _c_itemref = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
    var _c_spine = @[char][5]('s', 'p', 'i', 'n', 'e')
  in
    if xml_name_eq(data, len, name_off, name_len, _c_itemref, 7) then
      acc + 1
    else if xml_name_eq(data, len, name_off, name_len, _c_spine, 5) then
      _count_spine_items_r(data, len, children, acc)
    else _count_spine_items_r(data, len, children, acc)
  end
  | $X.xml_text(_, _) => acc

#pub fn count_spine_items
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   acc: int): int

implement count_spine_items{lb}{n}{sz}(data, len, nodes, acc) =
  _count_spine_items_r(data, len, nodes, acc)

(* ============================================================
   Manifest: find href by idref
   ============================================================ *)

fun _find_manifest_href_r
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   idref_off: int, idref_len: int): @(int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _check_manifest_item(data, len, node, idref_off, idref_len)
    in
      if r.0 >= 0 then r
      else _find_manifest_href_r(data, len, rest, idref_off, idref_len)
    end
  | $X.xml_nodes_nil() => @(~1, 0)

and _check_manifest_item
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   node: !$X.xml_node(sz),
   idref_off: int, idref_len: int): @(int, int) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_item = @[char][4]('i', 't', 'e', 'm')
  in
    if xml_name_eq(data, len, name_off, name_len, _c_item, 4) then let
      var _c_id = @[char][2]('i', 'd')
      val id_r = _find_attr_val(data, len, attrs, _c_id, 2)
      fun _cmp_bytes {lb:agz}{n:pos}{k:nat} .<k>.
        (d: !$A.borrow(byte, lb, n), mx: int n,
         a: int, b: int, fuel: int k): bool =
        if fuel <= 0 then true
        else if $S.borrow_byte(d, a, mx) != $S.borrow_byte(d, b, mx) then false
        else _cmp_bytes(d, mx, a + 1, b + 1, fuel - 1)
    in
      if id_r.0 >= 0 then
        if id_r.1 = idref_len then
          if _cmp_bytes(data, len, id_r.0, idref_off, len) then let
            var _c_href = @[char][4]('h', 'r', 'e', 'f')
          in _find_attr_val(data, len, attrs, _c_href, 4) end
          else @(~1, 0)
        else @(~1, 0)
      else @(~1, 0)
    end
    else _find_manifest_href_r(data, len, children, idref_off, idref_len)
  end
  | $X.xml_text(_, _) => @(~1, 0)

#pub fn find_manifest_href
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   idref_off: int, idref_len: int): @(int, int)

implement find_manifest_href{lb}{n}{sz}(data, len, nodes, idref_off, idref_len) =
  _find_manifest_href_r(data, len, nodes, idref_off, idref_len)

(* Find chapter href by index *)
#pub fn find_chapter_href_n
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   chapter_idx: int): @(int, int)

implement find_chapter_href_n(data, len, nodes, chapter_idx) = let
  val idref = find_nth_idref(data, len, nodes, chapter_idx)
in
  if idref.0 >= 0 then
    find_manifest_href(data, len, nodes, idref.0, idref.1)
  else @(~1, 0)
end
