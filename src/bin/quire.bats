#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use css as C
#use promise as P
#use result as R
#use sha256 as SHA
#use str as S
#use xml-tree as X
#use zip as Z
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/dom as D
#use wasm.bats-packages.dev/file-input as FI
#use wasm.bats-packages.dev/html as H
#use widget as W

staload "state.sats"
staload "theme.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"

(* ============================================================
   EPUB import helpers
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

fn _xml_name_eq
  {lb:agz}{n:pos}{np:pos}
  (data: !$A.borrow(byte, lb, n), len: int n,
   name_off: int, name_len: int,
   pat: &(@[char][np]), plen: int np): bool =
  if name_len != plen then false
  else if name_off < 0 then false
  else if name_off + name_len > len then false
  else _match_chars(data, len, name_off, pat, plen, 0)

fun _walk_rootfile_nodes
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz)): @(int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _walk_rootfile_node(data, len, node)
    in
      if r.0 >= 0 then r
      else _walk_rootfile_nodes(data, len, rest)
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
    if _xml_name_eq(data, len, name_off, name_len, _c_rootfile, 8) then
      _find_full_path(data, len, attrs)
    else _walk_rootfile_nodes(data, len, children)
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
    if _xml_name_eq(data, len, aname_off, aname_len, _c_fp, 9) then
      @(val_off, val_len)
    else _find_full_path(data, len, rest)
  end
  | $X.xml_attrs_nil() => @(~1, 0)

fun _walk_opf_metadata
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   t_off: int, t_len: int,
   a_off: int, a_len: int): @(int, int, int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _walk_opf_node(data, len, node, t_off, t_len, a_off, a_len)
    in
      _walk_opf_metadata(data, len, rest, r.0, r.1, r.2, r.3)
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
    if _xml_name_eq(data, len, name_off, name_len, _c_title, 8) then
      let val txt = _get_first_text(children)
      in @(txt.0, txt.1, a_off, a_len) end
    else if _xml_name_eq(data, len, name_off, name_len, _c_creator, 10) then
      let val txt = _get_first_text(children)
      in @(t_off, t_len, txt.0, txt.1) end
    else _walk_opf_metadata(data, len, children, t_off, t_len, a_off, a_len)
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

(* Compare two regions within the same borrow *)
fun _borrow_region_eq
  {lb:agz}{n:pos}{fuel:nat} .<fuel>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   off_a: int, off_b: int, count: int fuel): bool =
  if count <= 0 then true
  else if off_a < 0 then false
  else if off_b < 0 then false
  else if off_a >= len then false
  else if off_b >= len then false
  else let
    val a = byte2int0($A.read<byte>(data, $AR.checked_idx(off_a, len)))
    val b = byte2int0($A.read<byte>(data, $AR.checked_idx(off_b, len)))
  in
    if a != b then false
    else _borrow_region_eq(data, len, off_a + 1, off_b + 1, count - 1)
  end

(* Find first <itemref idref="..."> in <spine> *)
fun _find_first_idref
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz)): @(int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _check_itemref(data, len, node)
    in
      if r.0 >= 0 then r
      else _find_first_idref(data, len, rest)
    end
  | $X.xml_nodes_nil() => @(~1, 0)

and _check_itemref
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   node: !$X.xml_node(sz)): @(int, int) =
  case+ node of
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _c_itemref = @[char][7]('i', 't', 'e', 'm', 'r', 'e', 'f')
    var _c_spine = @[char][5]('s', 'p', 'i', 'n', 'e')
    var _c_idref = @[char][5]('i', 'd', 'r', 'e', 'f')
  in
    if _xml_name_eq(data, len, name_off, name_len, _c_itemref, 7) then
      _find_attr_val(data, len, attrs, _c_idref, 5)
    else if _xml_name_eq(data, len, name_off, name_len, _c_spine, 5) then
      _find_first_idref(data, len, children)
    else _find_first_idref(data, len, children)
  end
  | $X.xml_text(_, _) => @(~1, 0)

and _find_attr_val
  {lb:agz}{n:pos}{sa:nat}{np:pos} .<sa, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   attrs: !$X.xml_attr_list(sa),
   aname: &(@[char][np]), alen: int np): @(int, int) =
  case+ attrs of
  | $X.xml_attrs_cons(aname_off, aname_len, val_off, val_len, rest) =>
    if _xml_name_eq(data, len, aname_off, aname_len, aname, alen) then
      @(val_off, val_len)
    else _find_attr_val(data, len, rest, aname, alen)
  | $X.xml_attrs_nil() => @(~1, 0)

(* Find <item id="idref_val" href="..."> in <manifest> *)
fun _find_manifest_href
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   idref_off: int, idref_len: int): @(int, int) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val r = _check_manifest_item(data, len, node, idref_off, idref_len)
    in
      if r.0 >= 0 then r
      else _find_manifest_href(data, len, rest, idref_off, idref_len)
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
    if _xml_name_eq(data, len, name_off, name_len, _c_item, 4) then let
      var _c_id = @[char][2]('i', 'd')
      val id_r = _find_attr_val(data, len, attrs, _c_id, 2)
    in
      if id_r.0 >= 0 then
        if id_r.1 = idref_len then
          if _borrow_region_eq(data, len, id_r.0, idref_off, $AR.checked_nat(idref_len)) then let
            var _c_href = @[char][4]('h', 'r', 'e', 'f')
          in _find_attr_val(data, len, attrs, _c_href, 4) end
          else @(~1, 0)
        else @(~1, 0)
      else @(~1, 0)
    end
    else _find_manifest_href(data, len, children, idref_off, idref_len)
  end
  | $X.xml_text(_, _) => @(~1, 0)

fun _copy_from_borrow
  {lb:agz}{nb:pos}{la:agz}{na:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, lb, nb), src_off: int, src_max: int nb,
   dst: !$A.arr(byte, la, na), dst_off: int, dst_max: int na,
   count: int fuel): void =
  if count <= 0 then ()
  else if src_off < 0 then ()
  else if dst_off < 0 then ()
  else if src_off >= src_max then ()
  else if dst_off >= dst_max then ()
  else let
    val b = $A.read<byte>(src, $AR.checked_idx(src_off, src_max))
    val () = $A.set<byte>(dst, $AR.checked_idx(dst_off, dst_max), b)
  in
    _copy_from_borrow(src, src_off + 1, src_max, dst, dst_off + 1, dst_max, count - 1)
  end

fn _copy_arr_region
  {ls:agz}{ns:pos}{ld:agz}{nd:pos}
  (src: $A.arr(byte, ls, ns), src_off: int, src_max: int ns,
   dst: !$A.arr(byte, ld, nd), dst_max: int nd,
   count: int): $A.arr(byte, ls, ns) = let
  val @(frozen, borrow) = $A.freeze<byte>(src)
  val () = _copy_from_borrow(borrow, src_off, src_max,
                             dst, 0, dst_max, $AR.checked_nat(count))
  val () = $A.drop<byte>(frozen, borrow)
in $A.thaw<byte>(frozen) end

fn _import_epub
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni
  ): $P.promise(int, $P.Chained) = let
  val p = $FI.open(node_id, id_len)
  val p = $P.vow(p)
in
  $P.and_then<int><int>(p, lam(file_handle) => let
    val file_size = $FI.get_size()
  in
    if file_size <= 0 then let
      val () = $FI.close(file_handle)
    in $P.ret<int>(~1) end
    else if file_size > 1048576 then let
      val () = $FI.close(file_handle)
    in $P.ret<int>(~1) end
    else let
      val file_size_s = $AR.checked_arr_size(file_size)
      val file_buf = $A.alloc<byte>(file_size_s)
      val rd_res = $FI.file_read(file_handle, 0, file_buf, file_size_s)
      val () = $R.discard<int><int>(rd_res)

      val eocd_opt = $Z.find_eocd(file_buf, file_size_s)
      val eocd_off = $R.option_unwrap_or<int>(eocd_opt, ~1)
    in
      if eocd_off < 0 then let
        val () = $A.free<byte>(file_buf)
        val () = $FI.close(file_handle)
      in $P.ret<int>(~2) end
      else let
        val @(cd_off, cd_count) = $Z.parse_eocd(file_buf, file_size_s, eocd_off)
        var _cont_chars = @[char][22]('M', 'E', 'T', 'A', '-', 'I', 'N', 'F', '/', 'c', 'o', 'n', 't', 'a', 'i', 'n', 'e', 'r', '.', 'x', 'm', 'l')
        val _cont_arr = $S.from_char_array(_cont_chars, 22)
        val @(_cont_f, _cont_b) = $A.freeze<byte>(_cont_arr)
        val cont = $Z.find_entry_by_name(file_buf, file_size_s, cd_off,
                    $AR.checked_nat(cd_count),
                    _cont_b, 22)
        val () = $A.drop<byte>(_cont_f, _cont_b)
        val _cont_t = $A.thaw<byte>(_cont_f)
        val () = $A.free<byte>(_cont_t)
      in
        if cont.name_offset < 0 then let
          val () = $A.free<byte>(file_buf)
          val () = $FI.close(file_handle)
        in $P.ret<int>(~3) end
        else let
          val doff_opt = $Z.get_data_offset(file_buf, file_size_s,
                          cont.local_header_offset)
          val doff = $R.option_unwrap_or<int>(doff_opt, ~1)
        in
          if doff < 0 then let
            val () = $A.free<byte>(file_buf)
            val () = $FI.close(file_handle)
          in $P.ret<int>(~4) end
          else if cont.compressed_size <= 0 then let
            val () = $A.free<byte>(file_buf)
            val () = $FI.close(file_handle)
          in $P.ret<int>(~4) end
          else if cont.compressed_size > 1048576 then let
            val () = $A.free<byte>(file_buf)
            val () = $FI.close(file_handle)
          in $P.ret<int>(~4) end
          else let
            val csz = $AR.checked_arr_size(cont.compressed_size)
            val comp_buf = $A.alloc<byte>(csz)
            val file_buf = _copy_arr_region(file_buf, doff, file_size_s,
                                      comp_buf, csz, csz)
            (* Free file_buf now — we will re-read in stage 2 *)
            val () = $A.free<byte>(file_buf)

            val @(cf, cb) = $A.freeze<byte>(comp_buf)
            val dc_p = $DC.decompress(cb, csz, cont.compression)
            val () = $A.drop<byte>(cf, cb)
            val comp_buf2 = $A.thaw<byte>(cf)
            val () = $A.free<byte>(comp_buf2)

            val dc_p = $P.vow(dc_p)
          in
            (* Stage 2: parse container.xml, re-read file for OPF lookup *)
            $P.and_then<int><int>(dc_p, lam(dc_handle) => let
              val dc_len = $DC.get_len()
            in
              if dc_len <= 0 then let
                val () = $DC.blob_free(dc_handle)
                val () = $FI.close(file_handle)
              in $P.ret<int>(~5) end
              else if dc_len > 1048576 then let
                val () = $DC.blob_free(dc_handle)
                val () = $FI.close(file_handle)
              in $P.ret<int>(~5) end
              else let
                val dc_sz = $AR.checked_arr_size(dc_len)
                val dc_buf = $A.alloc<byte>(dc_sz)
                val br_res = $DC.blob_read(dc_handle, 0, dc_buf, dc_sz)
                val () = $R.discard<int><int>(br_res)
                val () = $DC.blob_free(dc_handle)

                val @(dc_frozen, dc_borrow) = $A.freeze<byte>(dc_buf)
                val nodes = $X.parse_document(dc_borrow, dc_sz)
                val opf_path = _walk_rootfile_nodes(dc_borrow, dc_sz, nodes)
                val opf_off = opf_path.0
                val opf_len = opf_path.1
              in
                if opf_off < 0 then let
                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(dc_frozen, dc_borrow)
                  val dc_buf2 = $A.thaw<byte>(dc_frozen)
                  val () = $A.free<byte>(dc_buf2)
                  val () = $FI.close(file_handle)
                in $P.ret<int>(~6) end
                else if opf_len <= 0 then let
                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(dc_frozen, dc_borrow)
                  val dc_buf2 = $A.thaw<byte>(dc_frozen)
                  val () = $A.free<byte>(dc_buf2)
                  val () = $FI.close(file_handle)
                in $P.ret<int>(~6) end
                else if opf_len > 1048576 then let
                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(dc_frozen, dc_borrow)
                  val dc_buf2 = $A.thaw<byte>(dc_frozen)
                  val () = $A.free<byte>(dc_buf2)
                  val () = $FI.close(file_handle)
                in $P.ret<int>(~6) end
                else let
                  val opf_path_sz = $AR.checked_arr_size(opf_len)
                  val opf_path_buf = $A.alloc<byte>(opf_path_sz)
                  val () = _copy_from_borrow(dc_borrow, opf_off, dc_sz,
                            opf_path_buf, 0, opf_path_sz,
                            $AR.checked_nat(opf_len))

                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(dc_frozen, dc_borrow)
                  val dc_buf2 = $A.thaw<byte>(dc_frozen)
                  val () = $A.free<byte>(dc_buf2)

                  (* Re-read file for OPF entry lookup *)
                  val file_size_s2 = $AR.checked_arr_size(file_size)
                  val file_buf2 = $A.alloc<byte>(file_size_s2)
                  val () = $R.discard($FI.file_read(file_handle, 0, file_buf2, file_size_s2))

                  val @(opf_frozen, opf_borrow) = $A.freeze<byte>(opf_path_buf)
                  val opf_entry = $Z.find_entry_by_name(
                    file_buf2, file_size_s2, cd_off,
                    $AR.checked_nat(cd_count),
                    opf_borrow, opf_path_sz)
                  val () = $A.drop<byte>(opf_frozen, opf_borrow)
                  val opf_path_buf2 = $A.thaw<byte>(opf_frozen)
                  val () = $A.free<byte>(opf_path_buf2)
                in
                  if opf_entry.name_offset < 0 then let
                    val () = $A.free<byte>(file_buf2)
                  in $P.ret<int>(~7) end
                  else let
                    val opf_doff_opt = $Z.get_data_offset(file_buf2, file_size_s2,
                                        opf_entry.local_header_offset)
                    val opf_doff = $R.option_unwrap_or<int>(opf_doff_opt, ~1)
                  in
                    if opf_doff < 0 then let
                      val () = $A.free<byte>(file_buf2)
                    in $P.ret<int>(~8) end
                    else if opf_entry.compressed_size <= 0 then let
                      val () = $A.free<byte>(file_buf2)
                    in $P.ret<int>(~8) end
                    else if opf_entry.compressed_size > 1048576 then let
                      val () = $A.free<byte>(file_buf2)
                    in $P.ret<int>(~8) end
                    else let
                      val opf_csz = $AR.checked_arr_size(opf_entry.compressed_size)
                      val opf_comp = $A.alloc<byte>(opf_csz)
                      val file_buf2 = _copy_arr_region(file_buf2, opf_doff, file_size_s2,
                                                opf_comp, opf_csz, opf_csz)
                      val () = $A.free<byte>(file_buf2)

                      val @(ocf, ocb) = $A.freeze<byte>(opf_comp)
                      val dc2_p = $DC.decompress(ocb, opf_csz, opf_entry.compression)
                      val () = $A.drop<byte>(ocf, ocb)
                      val opf_comp2 = $A.thaw<byte>(ocf)
                      val () = $A.free<byte>(opf_comp2)

                      val dc2_p = $P.vow(dc2_p)
                    in
                      (* Stage 3: parse OPF metadata *)
                      $P.and_then<int><int>(dc2_p, lam(dc2_handle) => let
                        val dc2_len = $DC.get_len()
                      in
                        if dc2_len <= 0 then let
                          val () = $DC.blob_free(dc2_handle)
                        in $P.ret<int>(~9) end
                        else if dc2_len > 1048576 then let
                          val () = $DC.blob_free(dc2_handle)
                        in $P.ret<int>(~9) end
                        else let
                          val dc2_sz = $AR.checked_arr_size(dc2_len)
                          val opf_buf = $A.alloc<byte>(dc2_sz)
                          val () = $R.discard($DC.blob_read(dc2_handle, 0, opf_buf, dc2_sz))
                          val () = $DC.blob_free(dc2_handle)

                          val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
                          val opf_nodes = $X.parse_document(opf_b, dc2_sz)
                          val meta = _walk_opf_metadata(opf_b, dc2_sz, opf_nodes,
                                      ~1, 0, ~1, 0)

                          val () = $X.free_nodes(opf_nodes)
                          val () = $A.drop<byte>(opf_f, opf_b)
                          val opf_buf2 = $A.thaw<byte>(opf_f)
                          val () = $A.free<byte>(opf_buf2)

                          (* Stash file info for chapter loading *)
                          val () = $ST.stash_set_int(10, file_handle)
                          val () = $ST.stash_set_int(11, file_size)
                          val () = $ST.stash_set_int(12, cd_off)
                          val () = $ST.stash_set_int(13, cd_count)
                          (* Stash OPF entry info *)
                          val () = $ST.stash_set_int(14, opf_doff)
                          val () = $ST.stash_set_int(15, opf_entry.compressed_size)
                          val () = $ST.stash_set_int(16, opf_entry.compression)
                          (* Stash OPF name in central directory for path prefix *)
                          val () = $ST.stash_set_int(17, opf_entry.name_offset)
                          val () = $ST.stash_set_int(18, opf_entry.name_len)
                        in $P.ret<int>(0) end
                      end)
                    end
                  end
                end
              end
            end)
          end
        end
      end
    end
  end)
end

fn _find_chapter_href
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz)): @(int, int) = let
  val idref = _find_first_idref(data, len, nodes)
in
  if idref.0 >= 0 then
    _find_manifest_href(data, len, nodes, idref.0, idref.1)
  else @(~1, 0)
end

fn _apply_diff_list(dl: $W.diff_list): void = let
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val nid = $ST.stash_get_int(20)
  val doc = $D.open_document($S.text_of_chars(mid, 9), 9, nid)
  val () = $D.apply_list(doc, dl)
  val nid2 = $D.get_next_id(doc)
  val () = $ST.stash_set_int(20, nid2)
  val () = $D.destroy(doc)
in end

fn _apply_diff(d: $W.diff): void = let
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val nid = $ST.stash_get_int(20)
  val doc = $D.open_document($S.text_of_chars(mid, 9), 9, nid)
  val () = $D.apply(doc, d)
  val nid2 = $D.get_next_id(doc)
  val () = $ST.stash_set_int(20, nid2)
  val () = $D.destroy(doc)
in end

fn _load_first_chapter(): $P.promise(int, $P.Chained) = let
  val fh = $ST.stash_get_int(10)
  val fsz = $ST.stash_get_int(11)
  val cd_off = $ST.stash_get_int(12)
  val cd_cnt = $ST.stash_get_int(13)
  val opf_doff = $ST.stash_get_int(14)
  val opf_csz = $ST.stash_get_int(15)
  val opf_comp = $ST.stash_get_int(16)
in
  if fsz <= 0 then $P.ret<int>(~1)
  else if fsz > 1048576 then $P.ret<int>(~1)
  else if opf_csz <= 0 then $P.ret<int>(~1)
  else if opf_csz > 1048576 then $P.ret<int>(~1)
  else let
    (* Read full file *)
    val fsz_s = $AR.checked_arr_size(fsz)
    val fbuf2 = $A.alloc<byte>(fsz_s)
    val () = $R.discard($FI.file_read(fh, 0, fbuf2, fsz_s))

    val opf_csz_s = $AR.checked_arr_size(opf_csz)
    val opf_cbuf = $A.alloc<byte>(opf_csz_s)
    val fbuf2 = _copy_arr_region(fbuf2, opf_doff, fsz_s,
                                  opf_cbuf, opf_csz_s, opf_csz_s)
    val () = $A.free<byte>(fbuf2)

    val @(ocf, ocb) = $A.freeze<byte>(opf_cbuf)
    val dc_p = $DC.decompress(ocb, opf_csz_s, opf_comp)
    val () = $A.drop<byte>(ocf, ocb)
    val opf_cbuf2 = $A.thaw<byte>(ocf)
    val () = $A.free<byte>(opf_cbuf2)

    val dc_p = $P.vow(dc_p)
  in
    (* Stage 2: parse OPF to find first chapter href *)
    $P.and_then<int><int>(dc_p, lam(dc_handle) => let
      val dc_len = $DC.get_len()
    in
      if dc_len <= 0 then let
        val () = $DC.blob_free(dc_handle)
      in $P.ret<int>(~2) end
      else if dc_len > 1048576 then let
        val () = $DC.blob_free(dc_handle)
      in $P.ret<int>(~2) end
      else let
        val dc_sz = $AR.checked_arr_size(dc_len)
        val opf_buf = $A.alloc<byte>(dc_sz)
        val () = $R.discard($DC.blob_read(dc_handle, 0, opf_buf, dc_sz))
        val () = $DC.blob_free(dc_handle)

        val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
        val opf_nodes = $X.parse_document(opf_b, dc_sz)

        (* Find first spine itemref → manifest item href *)
        val ch_href = _find_chapter_href(opf_b, dc_sz, opf_nodes)
        val ch_off = ch_href.0
        val ch_len = ch_href.1
      in
        if ch_off < 0 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        else if ch_len <= 0 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        else if ch_len > 1048576 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        else let
          (* Re-read file now so we can access the OPF name
             in the central directory for path prefix resolution *)
          val fsz_s3 = $AR.checked_arr_size(fsz)
          val fbuf3 = $A.alloc<byte>(fsz_s3)
          val () = $R.discard($FI.file_read(fh, 0, fbuf3, fsz_s3))

          (* Find directory prefix from OPF name in central directory.
             The OPF path e.g. "OEBPS/content.opf" tells us the
             directory prefix "OEBPS/" to prepend to chapter hrefs. *)
          val opf_name_off = $ST.stash_get_int(17)
          val opf_name_len = $ST.stash_get_int(18)
          fun _find_last_slash
            {l:agz}{n:pos}{k:int}{e:int}{la:int}{fuel:nat} .<fuel>.
            (buf: !$A.arr(byte, l, n), max: int n,
             pos: int k, endp: int e, last_after: int la,
             fuel: int fuel): int =
            if fuel <= 0 then last_after
            else if pos < 0 then last_after
            else if pos >= max then last_after
            else if pos >= endp then last_after
            else let
              val b = byte2int0($A.get<byte>(buf, pos))
            in
              if b = 47 then
                _find_last_slash(buf, max, pos + 1, endp, pos + 1, fuel - 1)
              else
                _find_last_slash(buf, max, pos + 1, endp, last_after, fuel - 1)
            end
          val opf_off_g1 = g1ofg0_int(opf_name_off)
          val opf_len_g1 = g1ofg0_int(opf_name_len)
          val prefix_end = _find_last_slash(fbuf3, fsz_s3,
            opf_off_g1, opf_off_g1 + opf_len_g1, opf_off_g1,
            $AR.checked_nat(opf_name_len))
          val prefix_len = prefix_end - opf_name_off

          (* Build full path: prefix + href *)
          val full_len = prefix_len + ch_len
          val full_len_s = $AR.checked_arr_size(full_len)
          val ch_buf = $A.alloc<byte>(full_len_s)
          (* Copy prefix from file buffer *)
          fun _copy_arr_region
            {la:agz}{na:pos}{lb:agz}{nb:pos}{i:int}{j:int}{fuel:nat} .<fuel>.
            (src: !$A.arr(byte, la, na), s_off: int i, s_max: int na,
             dst: !$A.arr(byte, lb, nb), d_off: int j, d_max: int nb,
             fuel: int fuel): void =
            if fuel <= 0 then ()
            else if s_off < 0 then ()
            else if d_off < 0 then ()
            else if s_off >= s_max then ()
            else if d_off >= d_max then ()
            else let
              val b = $A.get<byte>(src, s_off)
              val () = $A.set<byte>(dst, d_off, b)
            in _copy_arr_region(src, s_off + 1, s_max, dst, d_off + 1, d_max, fuel - 1) end
          val () = _copy_arr_region(fbuf3, opf_off_g1, fsz_s3,
                    ch_buf, 0, full_len_s,
                    $AR.checked_nat(prefix_len))
          (* Copy chapter href from OPF borrow *)
          val () = _copy_from_borrow(opf_b, ch_off, dc_sz,
                    ch_buf, prefix_len, full_len_s,
                    $AR.checked_nat(ch_len))

          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)

          val @(chf, chb) = $A.freeze<byte>(ch_buf)
          val ch_entry = $Z.find_entry_by_name(
            fbuf3, fsz_s3, cd_off,
            $AR.checked_nat(cd_cnt),
            chb, full_len_s)
          val () = $A.drop<byte>(chf, chb)
          val ch_buf2 = $A.thaw<byte>(chf)
          val () = $A.free<byte>(ch_buf2)
        in
          if ch_entry.name_offset < 0 then let
            val () = $A.free<byte>(fbuf3)
          in $P.ret<int>(~4) end
          else let
            val ch_doff_opt = $Z.get_data_offset(fbuf3, fsz_s3,
                                ch_entry.local_header_offset)
            val ch_doff = $R.option_unwrap_or<int>(ch_doff_opt, ~1)
          in
            if ch_doff < 0 then let
              val () = $A.free<byte>(fbuf3)
            in $P.ret<int>(~5) end
            else if ch_entry.compressed_size <= 0 then let
              val () = $A.free<byte>(fbuf3)
            in $P.ret<int>(~5) end
            else if ch_entry.compressed_size > 1048576 then let
              val () = $A.free<byte>(fbuf3)
            in $P.ret<int>(~5) end
            else let
              val ch_csz = $AR.checked_arr_size(ch_entry.compressed_size)
              val ch_comp = $A.alloc<byte>(ch_csz)
              val () = _copy_arr_region(fbuf3, g1ofg0_int(ch_doff), fsz_s3,
                                        ch_comp, 0, ch_csz, ch_csz)
              val () = $A.free<byte>(fbuf3)

              val @(ccf, ccb) = $A.freeze<byte>(ch_comp)
              val ch_dc_p = $DC.decompress(ccb, ch_csz, ch_entry.compression)
              val () = $A.drop<byte>(ccf, ccb)
              val ch_comp2 = $A.thaw<byte>(ccf)
              val () = $A.free<byte>(ch_comp2)

              val ch_dc_p = $P.vow(ch_dc_p)
            in
              (* Stage 3: parse HTML and render *)
              $P.and_then<int><int>(ch_dc_p, lam(ch_dc_handle) => let
                val ch_dc_len = $DC.get_len()
              in
                if ch_dc_len <= 0 then let
                  val () = $DC.blob_free(ch_dc_handle)
                in $P.ret<int>(~6) end
                else if ch_dc_len > 1048576 then let
                  val () = $DC.blob_free(ch_dc_handle)
                in $P.ret<int>(~6) end
                else let
                  val ch_dc_sz = $AR.checked_arr_size(ch_dc_len)
                  val ch_html = $A.alloc<byte>(ch_dc_sz)
                  val () = $R.discard($DC.blob_read(ch_dc_handle, 0, ch_html, ch_dc_sz))
                  val () = $DC.blob_free(ch_dc_handle)

                  (* Parse HTML *)
                  val @(hf, hb) = $A.freeze<byte>(ch_html)
                  val parse_res = $H.parse_html(hb, ch_dc_sz)
                  val () = $A.drop<byte>(hf, hb)
                  val ch_html2 = $A.thaw<byte>(hf)
                  val () = $A.free<byte>(ch_html2)

                  val parse_len = $R.unwrap_or<int><int>(parse_res, ~1)
                in
                  if parse_len <= 0 then let
                    var cnt_c = @[char][4]('q', 'c', 'n', 't')
                    val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
                    var fpc_c = @[char][23]('F', 'a', 'i', 'l', 'e', 'd', ' ', 't', 'o', ' ', 'p', 'a', 'r', 's', 'e', ' ', 'c', 'h', 'a', 'p', 't', 'e', 'r')
                    val () = _apply_diff($W.SetTextContent(cnt_id, $S.text_of_chars(fpc_c, 23), 23))
                  in $P.ret<int>(~7) end
                  else if parse_len > 1048576 then $P.ret<int>(~7)
                  else let
                    val psz = $AR.checked_arr_size(parse_len)
                    val pbuf = $H.get_result(psz)
                    val () = $A.free<byte>(pbuf)
                    (* TODO: render chapter content — needs safe borrow→string *)
                    var cnt_c = @[char][4]('q', 'c', 'n', 't')
                    val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
                    var cl_c = @[char][14]('C', 'h', 'a', 'p', 't', 'e', 'r', ' ', 'l', 'o', 'a', 'd', 'e', 'd')
                    val () = _apply_diff($W.SetTextContent(cnt_id, $S.text_of_chars(cl_c, 14), 14))
                  in $P.ret<int>(0) end
                end
              end)
            end
          end
        end
      end
    end)
  end
end

(* ============================================================
   App entry point
   ============================================================ *)

implement main0 () = let
  val st = empty_state()

  var tag = @[char][3]('d', 'i', 'v')
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val doc = $D.create_document($S.text_of_chars(tag, 3), 3, $S.text_of_chars(mid, 9), 9)

  val root = $W.Element($W.ElementNode($W.Root(), $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))

  var si_c = @[char][4]('q', 'c', 's', 's')
  val si_id = $W.Generated($S.text_of_chars(si_c, 4), 4)
  val @(css_t, css_l) = theme_css()
  val @(root, css_diffs) = $W.inject_css(root, si_id, css_t, css_l)
  val () = $D.apply_list(doc, css_diffs)

  var ll_c = @[char][4]('q', 'l', 'l', 'c')
  val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
  val ll = $W.Element($W.ElementNode(ll_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(root, diff) = $W.add_child(root, ll)
  val () = $D.apply(doc, diff)
  val @(ll, diff) = $W.set_class(ll, cls_library_list())
  val () = $D.apply(doc, diff)

  (* Reader view — hidden initially *)
  var rv_c = @[char][4]('q', 'r', 'v', 'w')
  val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
  val rv = $W.Element($W.ElementNode(rv_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(root, diff) = $W.add_child(root, rv)
  val () = $D.apply(doc, diff)
  val @(rv, diff) = $W.set_class(rv, cls_reader_view())
  val () = $D.apply(doc, diff)
  val @(rv, diff) = $W.set_hidden(rv, 1)
  val () = $D.apply(doc, diff)

  (* Back button inside reader view *)
  var bb_c = @[char][4]('q', 'b', 'b', 'k')
  val bb_id = $W.Generated($S.text_of_chars(bb_c, 4), 4)
  val bb = $W.Element($W.ElementNode(bb_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(rv, diff) = $W.add_child(rv, bb)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(bb, cls_back_btn())
  val () = $D.apply(doc, diff)
  var back_c = @[char][4]('B', 'a', 'c', 'k')
  val () = $D.apply(doc, $W.set_text_content(bb_id, $S.text_of_chars(back_c, 4), 4))

  (* Content area inside reader view *)
  var ca_c = @[char][4]('q', 'c', 'n', 't')
  val ca_id = $W.Generated($S.text_of_chars(ca_c, 4), 4)
  val ca = $W.Element($W.ElementNode(ca_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(rv, ca)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(ca, cls_content_area())
  val () = $D.apply(doc, diff)
in
  if is_library_empty(st) then let
    var el_c = @[char][4]('q', 'e', 'l', 'b')
    val el_id = $W.Generated($S.text_of_chars(el_c, 4), 4)
    val el = $W.Element($W.ElementNode(el_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ll, el)
    val () = $D.apply(doc, diff)
    val @(_, diff) = $W.set_class(el, cls_empty_lib())
    val () = $D.apply(doc, diff)
    var yle_c = @[char][21]('Y', 'o', 'u', 'r', ' ', 'l', 'i', 'b', 'r', 'a', 'r', 'y', ' ', 'i', 's', ' ', 'e', 'm', 'p', 't', 'y')
    val () = $D.apply(doc, $W.set_text_content(el_id, $S.text_of_chars(yle_c, 21), 21))

    var ib_c = @[char][4]('q', 'i', 'b', 'n')
    val ib_id = $W.Generated($S.text_of_chars(ib_c, 4), 4)
    val ib = $W.Element($W.ElementNode(ib_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ll, ib)
    val () = $D.apply(doc, diff)
    val @(_, diff) = $W.set_class(ib, cls_import_btn())
    val () = $D.apply(doc, diff)
    var ie_c = @[char][11]('I', 'm', 'p', 'o', 'r', 't', ' ', 'E', 'P', 'U', 'B')
    val () = $D.apply(doc, $W.set_text_content(ib_id, $S.text_of_chars(ie_c, 11), 11))

    var fi_c = @[char][4]('q', 'f', 'i', 'n')
    val fi_id = $W.Generated($S.text_of_chars(fi_c, 4), 4)
    val fi = $W.Element($W.ElementNode(fi_id, $W.Void($W.HtmlInput($W.InputFile(), $W.NoneStr(), $W.NoneStr(), 0, 0, 0)), ~1, 1, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ib, fi)
    val () = $D.apply(doc, diff)

    (* Wire file input change event to epub import *)
    val fi_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(fi_narr, 0, int2byte0(113))
    val () = $A.set<byte>(fi_narr, 1, int2byte0(102))
    val () = $A.set<byte>(fi_narr, 2, int2byte0(105))
    val () = $A.set<byte>(fi_narr, 3, int2byte0(110))
    val @(fi_nf, fi_nb) = $A.freeze<byte>(fi_narr)
    val ch_arr = $A.alloc<byte>(6)
    val () = $A.set<byte>(ch_arr, 0, int2byte0(99))
    val () = $A.set<byte>(ch_arr, 1, int2byte0(104))
    val () = $A.set<byte>(ch_arr, 2, int2byte0(97))
    val () = $A.set<byte>(ch_arr, 3, int2byte0(110))
    val () = $A.set<byte>(ch_arr, 4, int2byte0(103))
    val () = $A.set<byte>(ch_arr, 5, int2byte0(101))
    val @(ch_f, ch_b) = $A.freeze<byte>(ch_arr)
    val () = $EV.listen(fi_nb, 4, ch_b, 6, 1,
      lam(_payload_len: int): int => let
        val fa = $A.alloc<byte>(4)
        val () = $A.set<byte>(fa, 0, int2byte0(113))
        val () = $A.set<byte>(fa, 1, int2byte0(102))
        val () = $A.set<byte>(fa, 2, int2byte0(105))
        val () = $A.set<byte>(fa, 3, int2byte0(110))
        val @(ff, fb) = $A.freeze<byte>(fa)
        val p = _import_epub(fb, 4)
        val p2 = $P.and_then<int><int>(p, lam(result) =>
          if result = 0 then let
            (* Import succeeded — show reader, hide library *)
            var ll3_c = @[char][4]('q', 'l', 'l', 'c')
            val ll3_id = $W.Generated($S.text_of_chars(ll3_c, 4), 4)
            var rv3_c = @[char][4]('q', 'r', 'v', 'w')
            val rv3_id = $W.Generated($S.text_of_chars(rv3_c, 4), 4)
            val () = _apply_diff($W.SetHidden(ll3_id, 1))
            val () = _apply_diff($W.SetHidden(rv3_id, 0))
            (* Set loading text and load first chapter *)
            var cnt_c = @[char][4]('q', 'c', 'n', 't')
            val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
            var lc_c = @[char][18]('L', 'o', 'a', 'd', 'i', 'n', 'g', ' ', 'c', 'h', 'a', 'p', 't', 'e', 'r', '.', '.', '.')
            val () = _apply_diff($W.SetTextContent(cnt_id, $S.text_of_chars(lc_c, 18), 18))
            val ch_p = _load_first_chapter()
            val () = $P.discard<int>(ch_p)
          in $P.ret<int>(0) end
          else let
            var cnt2_c = @[char][4]('q', 'c', 'n', 't')
            val cnt2_id = $W.Generated($S.text_of_chars(cnt2_c, 4), 4)
          in
            if result = ~1 then let
              var e1 = @[char][4]('E', 'R', 'R', '1')
              val () = _apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e1, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~2 then let
              var e2 = @[char][4]('E', 'R', 'R', '2')
              val () = _apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e2, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~3 then let
              var e3 = @[char][4]('E', 'R', 'R', '3')
              val () = _apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e3, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~4 then let
              var e4 = @[char][4]('E', 'R', 'R', '4')
              val () = _apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e4, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~5 then let
              var e5 = @[char][4]('E', 'R', 'R', '5')
              val () = _apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e5, 4), 4))
            in $P.ret<int>(result) end
            else let
              var eu = @[char][4]('E', 'R', 'R', 'X')
              val () = _apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(eu, 4), 4))
            in $P.ret<int>(result) end
          end)
        val () = $P.discard<int>(p2)
        val () = $A.drop<byte>(ff, fb)
        val tmp = $A.thaw<byte>(ff)
        val () = $A.free<byte>(tmp)
      in 0 end)
    val () = $A.drop<byte>(fi_nf, fi_nb)
    val fi_ntmp = $A.thaw<byte>(fi_nf)
    val () = $A.free<byte>(fi_ntmp)
    val () = $A.drop<byte>(ch_f, ch_b)
    val ch_tmp = $A.thaw<byte>(ch_f)
    val () = $A.free<byte>(ch_tmp)

    (* Wire back button click *)
    val bb_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(bb_narr, 0, int2byte0(113))
    val () = $A.set<byte>(bb_narr, 1, int2byte0(98))
    val () = $A.set<byte>(bb_narr, 2, int2byte0(98))
    val () = $A.set<byte>(bb_narr, 3, int2byte0(107))
    val @(bb_nf, bb_nb) = $A.freeze<byte>(bb_narr)
    val ck_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck_arr, 0, int2byte0(99))
    val () = $A.set<byte>(ck_arr, 1, int2byte0(108))
    val () = $A.set<byte>(ck_arr, 2, int2byte0(105))
    val () = $A.set<byte>(ck_arr, 3, int2byte0(99))
    val () = $A.set<byte>(ck_arr, 4, int2byte0(107))
    val @(ck_f, ck_b) = $A.freeze<byte>(ck_arr)
    val () = $EV.listen(bb_nb, 4, ck_b, 5, 2,
      lam(_payload_len: int): int => let
        (* Show library, hide reader *)
        var ll2_c = @[char][4]('q', 'l', 'l', 'c')
        val ll2_id = $W.Generated($S.text_of_chars(ll2_c, 4), 4)
        var rv2_c = @[char][4]('q', 'r', 'v', 'w')
        val rv2_id = $W.Generated($S.text_of_chars(rv2_c, 4), 4)
        val () = _apply_diff($W.SetHidden(ll2_id, 0))
        val () = _apply_diff($W.SetHidden(rv2_id, 1))
      in 0 end)
    val () = $A.drop<byte>(bb_nf, bb_nb)
    val bb_ntmp = $A.thaw<byte>(bb_nf)
    val () = $A.free<byte>(bb_ntmp)
    val () = $A.drop<byte>(ck_f, ck_b)
    val ck_tmp = $A.thaw<byte>(ck_f)
    val () = $A.free<byte>(ck_tmp)

    val nid = $D.get_next_id(doc)
    val () = $ST.stash_set_int(20, nid)
    val () = $D.destroy(doc)
  in end
  else let
    val nid = $D.get_next_id(doc)
    val () = $ST.stash_set_int(20, nid)
    val () = $D.destroy(doc)
  in end
end
