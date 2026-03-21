(* book_cards -- EPUB import pipeline *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use xml-tree as X
#use zip as Z
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/dom as D
#use wasm.bats-packages.dev/file-input as FI
#use widget as W

staload "theme.sats"
staload "epub_xml.sats"
staload "reader.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"

fn _add_book_card
  {lb:agz}{nb:pos}{tl:int}{al:int}
  (data: !$A.borrow(byte, lb, nb), len: int nb,
   t_off: int, t_len: int tl,
   a_off: int, a_len: int al): void = let
  (* Hide empty message and create card *)
  var elb_c = @[char][4]('q', 'e', 'l', 'b')
  val elb_id = $W.Generated($S.text_of_chars(elb_c, 4), 4)
  val () = apply_diff($W.SetHidden(elb_id, 1))
  val idx = $ST.stash_get_int(29)
  val () = $ST.stash_set_int(29, idx + 1)
  val tens = idx / 10
  val ones = idx - tens * 10
  var card_c = @[char][5]('q', 'b', 'c', int2char0(48 + tens), int2char0(48 + ones))
  val card_id = $W.Generated($S.text_of_chars(card_c, 5), 5)
  var ll_c = @[char][4]('q', 'l', 'l', 'c')
  val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
  val card = $W.Element($W.ElementNode(card_id,
    $W.Normal($W.Div()), cls_book_card(), 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(card, cls_diff) = $W.set_class(card, cls_book_card())
  val () = apply_diff($W.AddChild(ll_id, card))
  val () = apply_diff(cls_diff)
  (* Title div *)
  var tc = @[char][5]('q', 't', 'c', '0', '0')
  val tc_id = $W.Generated($S.text_of_chars(tc, 5), 5)
  val td = $W.Element($W.ElementNode(tc_id,
    $W.Normal($W.Div()), cls_book_title(), 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(td, cls_d) = $W.set_class(td, cls_book_title())
  val () = apply_diff($W.AddChild(card_id, td))
  val () = apply_diff(cls_d)
  (* Set title — try metadata, fall back to "Imported Book" *)
  val () = (if t_off >= 0 then
    if t_len > 0 then
      if t_len < 256 then let
        val tbuf = $A.alloc<byte>(t_len)
        val () = copy_from_borrow(data, t_off, len, tbuf, 0, t_len, t_len)
        val txt = arr_to_text(tbuf, t_len)
        val () = $A.free<byte>(tbuf)
      in apply_diff($W.SetTextContent(tc_id, txt, t_len)) end
      else let
        var fb = @[char][13]('I', 'm', 'p', 'o', 'r', 't', 'e', 'd', ' ', 'B', 'o', 'o', 'k')
      in apply_diff($W.SetTextContent(tc_id, $S.text_of_chars(fb, 13), 13)) end
    else let
      var fb = @[char][13]('I', 'm', 'p', 'o', 'r', 't', 'e', 'd', ' ', 'B', 'o', 'o', 'k')
    in apply_diff($W.SetTextContent(tc_id, $S.text_of_chars(fb, 13), 13)) end
  else let
    var fb = @[char][13]('I', 'm', 'p', 'o', 'r', 't', 'e', 'd', ' ', 'B', 'o', 'o', 'k')
  in apply_diff($W.SetTextContent(tc_id, $S.text_of_chars(fb, 13), 13)) end)
  (* Author div *)
  var ac = @[char][5]('q', 'a', 'c', '0', '0')
  val ac_id = $W.Generated($S.text_of_chars(ac, 5), 5)
  val ad = $W.Element($W.ElementNode(ac_id,
    $W.Normal($W.Div()), cls_book_author(), 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(ad, cls_a) = $W.set_class(ad, cls_book_author())
  val () = apply_diff($W.AddChild(card_id, ad))
  val () = apply_diff(cls_a)
  val () = (if a_off >= 0 then
    if a_len > 0 then
      if a_len < 256 then let
        val abuf = $A.alloc<byte>(a_len)
        val () = copy_from_borrow(data, a_off, len, abuf, 0, a_len, a_len)
        val txt = arr_to_text(abuf, a_len)
        val () = $A.free<byte>(abuf)
      in apply_diff($W.SetTextContent(ac_id, txt, a_len)) end
      else let
        var fb = @[char][14]('U', 'n', 'k', 'n', 'o', 'w', 'n', ' ', 'A', 'u', 't', 'h', 'o', 'r')
      in apply_diff($W.SetTextContent(ac_id, $S.text_of_chars(fb, 14), 14)) end
    else let
      var fb = @[char][14]('U', 'n', 'k', 'n', 'o', 'w', 'n', ' ', 'A', 'u', 't', 'h', 'o', 'r')
    in apply_diff($W.SetTextContent(ac_id, $S.text_of_chars(fb, 14), 14)) end
  else let
    var fb = @[char][14]('U', 'n', 'k', 'n', 'o', 'w', 'n', ' ', 'A', 'u', 't', 'h', 'o', 'r')
  in apply_diff($W.SetTextContent(ac_id, $S.text_of_chars(fb, 14), 14)) end)
  (* Progress badge — "New" for newly imported books *)
  var pb_c = @[char][5]('q', 'p', 'b', int2char0(48 + tens), int2char0(48 + ones))
  val pb_id = $W.Generated($S.text_of_chars(pb_c, 5), 5)
  val pb = $W.Element($W.ElementNode(pb_id,
    $W.Normal($W.Div()), cls_progress_badge(), 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(pb, cls_p) = $W.set_class(pb, cls_progress_badge())
  val () = apply_diff($W.AddChild(card_id, pb))
  val () = apply_diff(cls_p)
  var new_c = @[char][3]('N', 'e', 'w')
  val () = apply_diff($W.SetTextContent(pb_id, $S.text_of_chars(new_c, 3), 3))
  (* Wire click handler: card click opens reader *)
  var ci_c = @[char][5]('q', 'b', 'c', int2char0(48 + tens), int2char0(48 + ones))
  val ci_arr = $S.from_char_array(ci_c, 5)
  val @(ci_f, ci_b) = $A.freeze<byte>(ci_arr)
  var ck_c = @[char][5]('c', 'l', 'i', 'c', 'k')
  val ck_arr = $S.from_char_array(ck_c, 5)
  val @(ck_f, ck_b) = $A.freeze<byte>(ck_arr)
  val () = $EV.listen(ci_b, 5, ck_b, 5, 100,
    lam(_pl: int): int => let
      var ll_c = @[char][4]('q', 'l', 'l', 'c')
      val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
      var rv_c = @[char][4]('q', 'r', 'v', 'w')
      val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
      val () = apply_diff($W.SetHidden(ll_id, 1))
      val () = apply_diff($W.SetHidden(rv_id, 0))
      var cnt_c = @[char][4]('q', 'c', 'n', 't')
      val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
      var lc = @[char][18]('L', 'o', 'a', 'd', 'i', 'n', 'g', ' ', 'c', 'h', 'a', 'p', 't', 'e', 'r', '.', '.', '.')
      val () = apply_diff($W.SetTextContent(cnt_id, $S.text_of_chars(lc, 18), 18))
      val ch_p = load_chapter(0)
      val () = $P.discard<int>(ch_p)
    in 0 end)
  val () = $A.drop<byte>(ci_f, ci_b)
  val () = $A.free<byte>($A.thaw<byte>(ci_f))
  val () = $A.drop<byte>(ck_f, ck_b)
  val () = $A.free<byte>($A.thaw<byte>(ck_f))

  (* Wire contextmenu handler: right-click shows context menu *)
  var cm_c = @[char][5]('q', 'b', 'c', '0', '0')
  val cm_arr = $S.from_char_array(cm_c, 5)
  val @(cm_f, cm_b) = $A.freeze<byte>(cm_arr)
  var ct_c = @[char][11]('c', 'o', 'n', 't', 'e', 'x', 't', 'm', 'e', 'n', 'u')
  val ct_arr = $S.from_char_array(ct_c, 11)
  val @(ct_f, ct_b) = $A.freeze<byte>(ct_arr)
  val () = $EV.listen(cm_b, 5, ct_b, 11, 200,
    lam(_pl: int): int => let
      val () = $EV.prevent_default()
      (* Show context menu overlay *)
      var ctx_c = @[char][4]('q', 'c', 't', 'x')
      val ctx_id = $W.Generated($S.text_of_chars(ctx_c, 4), 4)
      val () = apply_diff($W.SetHidden(ctx_id, 0))
    in 0 end)
  val () = $A.drop<byte>(cm_f, cm_b)
  val () = $A.free<byte>($A.thaw<byte>(cm_f))
  val () = $A.drop<byte>(ct_f, ct_b)
  val () = $A.free<byte>($A.thaw<byte>(ct_f))
in end

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
    else if file_size > 31457280 then let
      val () = $FI.close(file_handle)
    in $P.ret<int>(~1) end
    else let
      val file_buf = $A.alloc<byte>(file_size)
      val rd_res = $FI.file_read(file_handle, 0, file_buf, file_size)
      val () = $R.discard<int><int>(rd_res)

      val eocd_opt = $Z.find_eocd(file_buf, file_size)
      val eocd_off = $R.option_unwrap_or<int>(eocd_opt, ~1)
    in
      if eocd_off < 0 then let
        val () = $A.free<byte>(file_buf)
        val () = $FI.close(file_handle)
      in $P.ret<int>(~2) end
      else let
        val @(cd_off, cd_count) = $Z.parse_eocd(file_buf, file_size, eocd_off)
        var _cont_chars = @[char][22]('M', 'E', 'T', 'A', '-', 'I', 'N', 'F', '/', 'c', 'o', 'n', 't', 'a', 'i', 'n', 'e', 'r', '.', 'x', 'm', 'l')
        val _cont_arr = $S.from_char_array(_cont_chars, 22)
        val @(_cont_f, _cont_b) = $A.freeze<byte>(_cont_arr)
        val cont = $Z.find_entry_by_name(file_buf, file_size_s, cd_off,
                    cd_count,
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
          else if cont.compressed_size > 31457280 then let
            val () = $A.free<byte>(file_buf)
            val () = $FI.close(file_handle)
          in $P.ret<int>(~4) end
          else let
            val csz = cont.compressed_size
            val comp_buf = $A.alloc<byte>(csz)
            val file_buf = copy_arr_region(file_buf, doff, file_size_s,
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
              else if dc_len > 31457280 then let
                val () = $DC.blob_free(dc_handle)
                val () = $FI.close(file_handle)
              in $P.ret<int>(~5) end
              else let
                val dc_sz = dc_len
                val dc_buf = $A.alloc<byte>(dc_sz)
                val br_res = $DC.blob_read(dc_handle, 0, dc_buf, dc_sz)
                val () = $R.discard<int><int>(br_res)
                val () = $DC.blob_free(dc_handle)

                val @(dc_frozen, dc_borrow) = $A.freeze<byte>(dc_buf)
                val nodes = $X.parse_document(dc_borrow, dc_sz)
                val opf_path = walk_rootfile_nodes(dc_borrow, dc_sz, nodes)
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
                else if opf_len > 31457280 then let
                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(dc_frozen, dc_borrow)
                  val dc_buf2 = $A.thaw<byte>(dc_frozen)
                  val () = $A.free<byte>(dc_buf2)
                  val () = $FI.close(file_handle)
                in $P.ret<int>(~6) end
                else let
                  val opf_path_sz = opf_len
                  val opf_path_buf = $A.alloc<byte>(opf_path_sz)
                  val () = copy_from_borrow(dc_borrow, opf_off, dc_sz,
                            opf_path_buf, 0, opf_path_sz,
                            opf_len)

                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(dc_frozen, dc_borrow)
                  val dc_buf2 = $A.thaw<byte>(dc_frozen)
                  val () = $A.free<byte>(dc_buf2)

                  (* Re-read file for OPF entry lookup *)
                  val file_size_s2 = file_size
                  val file_buf2 = $A.alloc<byte>(file_size_s2)
                  val () = $R.discard($FI.file_read(file_handle, 0, file_buf2, file_size_s2))

                  val @(opf_frozen, opf_borrow) = $A.freeze<byte>(opf_path_buf)
                  val opf_entry = $Z.find_entry_by_name(
                    file_buf2, file_size_s2, cd_off,
                    cd_count,
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
                    else if opf_entry.compressed_size > 31457280 then let
                      val () = $A.free<byte>(file_buf2)
                    in $P.ret<int>(~8) end
                    else let
                      val opf_csz = opf_entry.compressed_size
                      val opf_comp = $A.alloc<byte>(opf_csz)
                      val file_buf2 = copy_arr_region(file_buf2, opf_doff, file_size_s2,
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
                        else if dc2_len > 31457280 then let
                          val () = $DC.blob_free(dc2_handle)
                        in $P.ret<int>(~9) end
                        else let
                          val dc2_sz = dc2_len
                          val opf_buf = $A.alloc<byte>(dc2_sz)
                          val () = $R.discard($DC.blob_read(dc2_handle, 0, opf_buf, dc2_sz))
                          val () = $DC.blob_free(dc2_handle)

                          val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
                          val opf_nodes = $X.parse_document(opf_b, dc2_sz)
                          val meta = walk_opf_metadata(opf_b, dc2_sz, opf_nodes,
                                      ~1, 0, ~1, 0)

                          (* Create card with metadata *)
                          val () = _add_book_card(opf_b, dc2_sz,
                                    meta.0, meta.1, meta.2, meta.3)

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



#pub fn import_epub
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni
  ): $P.promise(int, $P.Chained)

implement import_epub(node_id, id_len) = _import_epub(node_id, id_len)

end (* #target wasm *)

(* _add_book_card stub for future use — not yet wired *)

