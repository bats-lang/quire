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
#use widget as W

staload "state.sats"
staload "theme.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"

(* ============================================================
   EPUB import helpers
   ============================================================ *)

fn _xml_name_eq
  {lb:agz}{n:pos}{sn:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   name_off: int, name_len: int,
   pat: string sn, plen: int sn): bool =
  if name_len != plen then false
  else if name_off < 0 then false
  else if name_off + name_len > len then false
  else $S.chars_match_borrow(data, name_off, len, pat, 0, plen)

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
  | $X.xml_element(name_off, name_len, attrs, children) =>
    if _xml_name_eq(data, len, name_off, name_len, "rootfile", 8) then
      _find_full_path(data, len, attrs)
    else _walk_rootfile_nodes(data, len, children)
  | $X.xml_text(_, _) => @(~1, 0)

and _find_full_path
  {lb:agz}{n:pos}{sa:nat} .<sa, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   attrs: !$X.xml_attr_list(sa)): @(int, int) =
  case+ attrs of
  | $X.xml_attrs_cons(aname_off, aname_len, val_off, val_len, rest) =>
    if _xml_name_eq(data, len, aname_off, aname_len, "full-path", 9) then
      @(val_off, val_len)
    else _find_full_path(data, len, rest)
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
  | $X.xml_element(name_off, name_len, _, children) =>
    if _xml_name_eq(data, len, name_off, name_len, "dc:title", 8) then
      let val txt = _get_first_text(children)
      in @(txt.0, txt.1, a_off, a_len) end
    else if _xml_name_eq(data, len, name_off, name_len, "dc:creator", 10) then
      let val txt = _get_first_text(children)
      in @(t_off, t_len, txt.0, txt.1) end
    else _walk_opf_metadata(data, len, children, t_off, t_len, a_off, a_len)
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

fun _arr_borrow_eq
  {l:agz}{n:pos}{lb:agz}{nb:pos}{fuel:nat} .<fuel>.
  (arr: !$A.arr(byte, l, n), a_off: int, a_max: int n,
   bv: !$A.borrow(byte, lb, nb), b_off: int, b_max: int nb,
   count: int fuel): bool =
  if count <= 0 then true
  else if a_off < 0 then false
  else if b_off < 0 then false
  else if a_off >= a_max then false
  else if b_off >= b_max then false
  else let
    val ab = byte2int0($A.get<byte>(arr, $AR.checked_idx(a_off, a_max)))
    val bb = byte2int0($A.read<byte>(bv, $AR.checked_idx(b_off, b_max)))
  in
    if ab != bb then false
    else _arr_borrow_eq(arr, a_off + 1, a_max, bv, b_off + 1, b_max, count - 1)
  end

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

fun _find_zip_entry
  {l:agz}{n:pos}{fuel:nat}{sn:nat} .<fuel>.
  (data: !$A.arr(byte, l, n), len: int n,
   cd_offset: int, remaining: int fuel,
   target: string sn, target_len: int sn): $Z.zip_entry =
  if remaining <= 0 then
    @{name_offset= ~1, name_len= 0, compression= 0,
      compressed_size= 0, uncompressed_size= 0,
      local_header_offset= 0}
  else let
    val @(entry, next_off) = $Z.parse_cd_entry(data, len, cd_offset)
  in
    if entry.name_len = target_len then
      if $S.chars_match(data, entry.name_offset, len, target, 0, target_len) then
        entry
      else _find_zip_entry(data, len, next_off, remaining - 1, target, target_len)
    else _find_zip_entry(data, len, next_off, remaining - 1, target, target_len)
  end

fun _find_zip_entry_borrow
  {l:agz}{n:pos}{lb:agz}{nb:pos}{fuel:nat} .<fuel>.
  (data: !$A.arr(byte, l, n), len: int n,
   cd_offset: int, remaining: int fuel,
   name_buf: !$A.borrow(byte, lb, nb), name_len: int nb): $Z.zip_entry =
  if remaining <= 0 then
    @{name_offset= ~1, name_len= 0, compression= 0,
      compressed_size= 0, uncompressed_size= 0,
      local_header_offset= 0}
  else let
    val @(entry, next_off) = $Z.parse_cd_entry(data, len, cd_offset)
  in
    if entry.name_len = name_len then
      if _arr_borrow_eq(data, entry.name_offset, len,
                        name_buf, 0, name_len, name_len) then
        entry
      else _find_zip_entry_borrow(data, len, next_off, remaining - 1, name_buf, name_len)
    else _find_zip_entry_borrow(data, len, next_off, remaining - 1, name_buf, name_len)
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
        val cont = _find_zip_entry(file_buf, file_size_s, cd_off,
                    $AR.checked_nat(cd_count),
                    "META-INF/container.xml", 22)
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
                  val () = $FI.close(file_handle)

                  val @(opf_frozen, opf_borrow) = $A.freeze<byte>(opf_path_buf)
                  val opf_entry = _find_zip_entry_borrow(
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
  val @(root, css_diffs) = $W.inject_css(root, si_id, theme_css())
  val () = $D.apply_list(doc, css_diffs)

  var ll_c = @[char][4]('q', 'l', 'l', 'c')
  val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
  val ll = $W.Element($W.ElementNode(ll_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(root, diff) = $W.add_child(root, ll)
  val () = $D.apply(doc, diff)
  val @(ll, diff) = $W.set_class(ll, cls_library_list())
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
    val () = $D.apply(doc, $W.set_text_content(el_id, "Your library is empty"))

    var ib_c = @[char][4]('q', 'i', 'b', 'n')
    val ib_id = $W.Generated($S.text_of_chars(ib_c, 4), 4)
    val ib = $W.Element($W.ElementNode(ib_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ll, ib)
    val () = $D.apply(doc, diff)
    val @(_, diff) = $W.set_class(ib, cls_import_btn())
    val () = $D.apply(doc, diff)
    val () = $D.apply(doc, $W.set_text_content(ib_id, "Import EPUB"))

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
        val () = $P.discard<int>(p)
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

    val () = $D.destroy(doc)
  in end
  else let
    val () = $D.destroy(doc)
  in end
end
