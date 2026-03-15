(* book_cards -- Book card UI, EPUB import, IDB persistence *)

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

(* ============================================================
   Book card helper — generates a card widget ID from index
   ============================================================ *)

fn _idx_to_chars(prefix_a: char, prefix_b: char, idx: int):
  @[char][5] = let
  val zero = char2int0('0')
  val tens = idx / 10
  val ones = idx - tens * 10
in @[char][5]('q', prefix_a, prefix_b, int2char0(zero + tens), int2char0(zero + ones)) end

fn _card_wid(idx: int): $W.widget_id = let
  var c = _idx_to_chars('b', 'c', idx)
  val buf = $S.from_char_array(c, 5)
  val txt = arr_to_text(buf, 5)
  val () = $A.free<byte>(buf)
in $W.Generated(txt, 5) end

fn _card_title_wid(idx: int): $W.widget_id = let
  var c = _idx_to_chars('t', 'c', idx)
  val buf = $S.from_char_array(c, 5)
  val txt = arr_to_text(buf, 5)
  val () = $A.free<byte>(buf)
in $W.Generated(txt, 5) end

fn _card_author_wid(idx: int): $W.widget_id = let
  var c = _idx_to_chars('a', 'c', idx)
  val buf = $S.from_char_array(c, 5)
  val txt = arr_to_text(buf, 5)
  val () = $A.free<byte>(buf)
in $W.Generated(txt, 5) end

fn _card_id_arr(idx: int): [l:agz] $A.arr(byte, l, 5) = let
  var c = _idx_to_chars('b', 'c', idx)
in $S.from_char_array(c, 5) end

(* Add a book card to the library list *)

fn _add_book_card
  {nt:pos | nt < 65536}{na:pos | na < 65536}
  (title_txt: $A.text(nt), title_len: int nt,
   author_txt: $A.text(na), author_len: int na,
   fh: int, fsz: int, cdo: int, cdc: int,
   opf_do: int, opf_cs: int, opf_cm: int,
   opf_no: int, opf_nl: int): void = let
  val idx = $ST.stash_get_int(29)
  val () = $ST.stash_set_int(29, idx + 1)

  (* Hide empty library message *)
  var elb_c = @[char][4]('q', 'e', 'l', 'b')
  val elb_id = $W.Generated($S.text_of_chars(elb_c, 4), 4)
  val () = apply_diff($W.SetHidden(elb_id, 1))

  (* Create card div *)
  var ll_c = @[char][4]('q', 'l', 'l', 'c')
  val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
  val card = $W.Element($W.ElementNode(_card_wid(idx),
    $W.Normal($W.Div()), cls_book_card(), 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val () = apply_diff($W.AddChild(ll_id, card))

  (* Create title div inside card *)
  val td = $W.Element($W.ElementNode(_card_title_wid(idx),
    $W.Normal($W.Div()), cls_book_title(), 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val () = apply_diff($W.AddChild(_card_wid(idx), td))
  val () = apply_diff($W.SetTextContent(_card_title_wid(idx), title_txt, title_len))

  (* Create author div inside card *)
  val ad = $W.Element($W.ElementNode(_card_author_wid(idx),
    $W.Normal($W.Div()), cls_book_author(), 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val () = apply_diff($W.AddChild(_card_wid(idx), ad))
  val () = apply_diff($W.SetTextContent(_card_author_wid(idx), author_txt, author_len))

  (* Wire click event on card to open reader *)
  val cn_arr = _card_id_arr(idx)
  val @(cn_f, cn_b) = $A.freeze<byte>(cn_arr)
  var ck_c = @[char][5]('c', 'l', 'i', 'c', 'k')
  val ck_arr = $S.from_char_array(ck_c, 5)
  val @(ck_f, ck_b) = $A.freeze<byte>(ck_arr)
  val listener_id = 12 + idx * 2
  val () = $EV.listen(cn_b, 5, ck_b, 5, listener_id,
    lam(_payload_len: int): int => let
      (* Set stash to this book's data *)
      val () = $ST.stash_set_int(10, fh)
      val () = $ST.stash_set_int(11, fsz)
      val () = $ST.stash_set_int(12, cdo)
      val () = $ST.stash_set_int(13, cdc)
      val () = $ST.stash_set_int(14, opf_do)
      val () = $ST.stash_set_int(15, opf_cs)
      val () = $ST.stash_set_int(16, opf_cm)
      val () = $ST.stash_set_int(17, opf_no)
      val () = $ST.stash_set_int(18, opf_nl)
      (* Hide library, show reader *)
      var ll2_c = @[char][4]('q', 'l', 'l', 'c')
      val ll2_id = $W.Generated($S.text_of_chars(ll2_c, 4), 4)
      var rv2_c = @[char][4]('q', 'r', 'v', 'w')
      val rv2_id = $W.Generated($S.text_of_chars(rv2_c, 4), 4)
      val () = apply_diff($W.SetHidden(ll2_id, 1))
      val () = apply_diff($W.SetHidden(rv2_id, 0))
      (* Load first chapter *)
      var cnt_c = @[char][4]('q', 'c', 'n', 't')
      val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
      var lc_c = @[char][18]('L', 'o', 'a', 'd', 'i', 'n', 'g', ' ', 'c', 'h', 'a', 'p', 't', 'e', 'r', '.', '.', '.')
      val () = apply_diff($W.SetTextContent(cnt_id, $S.text_of_chars(lc_c, 18), 18))
      val ch_p = load_chapter(0)
      val () = $P.discard<int>(ch_p)
    in 0 end)
  val () = $A.drop<byte>(cn_f, cn_b)
  val cn_tmp = $A.thaw<byte>(cn_f)
  val () = $A.free<byte>(cn_tmp)
  val () = $A.drop<byte>(ck_f, ck_b)
  val ck_tmp = $A.thaw<byte>(ck_f)
  val () = $A.free<byte>(ck_tmp)
in end


fn _save_epub_to_idb(): void = let
  val fh = $ST.stash_get_int(10)
  val fsz = $ST.stash_get_int(11)
in
  if fsz > 0 then
    if fsz <= 1048576 then let
      val fsz_s = $AR.checked_arr_size(fsz)
      val fbuf = $A.alloc<byte>(fsz_s)
      val () = $R.discard($FI.file_read(fh, 0, fbuf, fsz_s))
      val @(ff, fb) = $A.freeze<byte>(fbuf)
      var book_c = @[char][4]('b', 'o', 'o', 'k')
      val ka = $S.from_char_array(book_c, 4)
      val @(kf, kb) = $A.freeze<byte>(ka)
      val p = $IDB.idb_put(kb, 4, fb, fsz_s)
      val () = $P.discard<int>(p)
      val () = $A.drop<byte>(kf, kb)
      val kt = $A.thaw<byte>(kf)
      val () = $A.free<byte>(kt)
      val () = $A.drop<byte>(ff, fb)
      val ft = $A.thaw<byte>(ff)
      val () = $A.free<byte>(ft)
    in end
    else ()
  else ()
end

(* Save stash metadata to IDB: slots 10-18 as 9 x 4-byte ints *)

fn _save_metadata_to_idb(): void = let
  val buf = $A.alloc<byte>(36)
  fun _write_slot {l:agz}{n:pos}{s:nat}{off:nat | off + 4 <= n}{fuel:nat} .<fuel>.
    (buf: !$A.arr(byte, l, n), max: int n,
     slot: int s, off: int off, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if slot >= 32 then ()
    else let
      val v = $ST.stash_get_int(slot)
      val () = $A.write_i32(buf, off, v)
    in
      if off + 8 <= max then
        _write_slot(buf, max, slot + 1, off + 4, fuel - 1)
      else ()
    end
  val () = _write_slot(buf, 36, 10, 0, 9)
  val @(bf, bb) = $A.freeze<byte>(buf)
  var meta_c = @[char][4]('m', 'e', 't', 'a')
  val ka = $S.from_char_array(meta_c, 4)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_put(kb, 4, bb, 36)
  val () = $P.discard<int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
in end

(* ============================================================
   Pagination helpers
   ============================================================ *)


(* Save font size to IDB *)
fn _save_font_size(): void = let
  val sz = $ST.stash_get_int(25)
  val buf = $A.alloc<byte>(2)
  val () = $A.set<byte>(buf, 0, int2byte0(sz mod 256))
  val () = $A.set<byte>(buf, 1, int2byte0(sz / 256))
  val @(bf, bb) = $A.freeze<byte>(buf)
  var font_c = @[char][4]('f', 'o', 'n', 't')
  val ka = $S.from_char_array(font_c, 4)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_put(kb, 4, bb, 2)
  val () = $P.discard<int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
in end


fn _extract_author_and_card
  {nt:pos | nt < 65536}{l:agz}{nb:pos}
  (title_txt: $A.text(nt), title_len: int nt,
   opf_b: $A.borrow(byte, l, nb),
   opf_f: $A.frozen(byte, l, nb, 1),
   dc_sz: int nb,
   a_off: int, a_len: int,
   fh: int, fsz: int, cdo: int, cdc: int,
   opf_do: int, opf_cs: int, opf_cm: int,
   opf_no: int, opf_nl: int): $P.promise(int, $P.Chained) =
  if a_off >= 0 then
    if a_len > 0 then
      if a_len < 256 then let
        val asz = $AR.checked_text_size(a_len)
        val abuf = $A.alloc<byte>(asz)
        val () = copy_from_borrow(opf_b, a_off, dc_sz, abuf, 0, asz, $AR.checked_nat(a_len))
        val author_txt = arr_to_text(abuf, asz)
        (* Save author to IDB *)
        val @(af, ab) = $A.freeze<byte>(abuf)
        var auth_c = @[char][4]('a', 'u', 't', 'h')
        val ak = $S.from_char_array(auth_c, 4)
        val @(akf, akb) = $A.freeze<byte>(ak)
        val ap = $IDB.idb_put(akb, 4, ab, asz)
        val () = $P.discard<int>(ap)
        val () = $A.drop<byte>(akf, akb)
        val akt = $A.thaw<byte>(akf)
        val () = $A.free<byte>(akt)
        val () = $A.drop<byte>(af, ab)
        val at2 = $A.thaw<byte>(af)
        val () = $A.free<byte>(at2)
        val () = $A.drop<byte>(opf_f, opf_b)
        val opf_tmp = $A.thaw<byte>(opf_f)
        val () = $A.free<byte>(opf_tmp)
        val () = _add_book_card(title_txt, title_len, author_txt, asz,
          fh, fsz, cdo, cdc, opf_do, opf_cs, opf_cm, opf_no, opf_nl)
      in $P.ret<int>(0) end
      else let
        val () = $A.drop<byte>(opf_f, opf_b)
        val opf_tmp = $A.thaw<byte>(opf_f)
        val () = $A.free<byte>(opf_tmp)
        var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
        val () = _add_book_card(title_txt, title_len, $S.text_of_chars(unk_c, 7), 7,
          fh, fsz, cdo, cdc, opf_do, opf_cs, opf_cm, opf_no, opf_nl)
      in $P.ret<int>(0) end
    else let
      val () = $A.drop<byte>(opf_f, opf_b)
      val opf_tmp = $A.thaw<byte>(opf_f)
      val () = $A.free<byte>(opf_tmp)
      var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
      val () = _add_book_card(title_txt, title_len, $S.text_of_chars(unk_c, 7), 7,
        fh, fsz, cdo, cdc, opf_do, opf_cs, opf_cm, opf_no, opf_nl)
    in $P.ret<int>(0) end
  else let
    val () = $A.drop<byte>(opf_f, opf_b)
    val opf_tmp = $A.thaw<byte>(opf_f)
    val () = $A.free<byte>(opf_tmp)
    var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
    val () = _add_book_card(title_txt, title_len, $S.text_of_chars(unk_c, 7), 7,
      fh, fsz, cdo, cdc, opf_do, opf_cs, opf_cm, opf_no, opf_nl)
  in $P.ret<int>(0) end

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
                  val () = copy_from_borrow(dc_borrow, opf_off, dc_sz,
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
                          val meta = walk_opf_metadata(opf_b, dc2_sz, opf_nodes,
                                      ~1, 0, ~1, 0)

                          (* Extract title and author text *)
                          val t_off = meta.0
                          val t_len = meta.1
                          val a_off = meta.2
                          val a_len = meta.3

                          val () = $X.free_nodes(opf_nodes)

                        in
                          if t_off >= 0 then
                            if t_len > 0 then
                              if t_len < 256 then let
                                val tsz = $AR.checked_text_size(t_len)
                                val tbuf = $A.alloc<byte>(tsz)
                                val () = copy_from_borrow(opf_b, t_off, dc2_sz, tbuf, 0, tsz, $AR.checked_nat(t_len))
                                val title_txt = arr_to_text(tbuf, tsz)
                                (* Save title to IDB *)
                                val @(tf, tb) = $A.freeze<byte>(tbuf)
                                var titl_c = @[char][4]('t', 'i', 't', 'l')
                                val tk = $S.from_char_array(titl_c, 4)
                                val @(tkf, tkb) = $A.freeze<byte>(tk)
                                val tp = $IDB.idb_put(tkb, 4, tb, tsz)
                                val () = $P.discard<int>(tp)
                                val () = $A.drop<byte>(tkf, tkb)
                                val tkt = $A.thaw<byte>(tkf)
                                val () = $A.free<byte>(tkt)
                                val () = $A.drop<byte>(tf, tb)
                                val tt = $A.thaw<byte>(tf)
                                val () = $A.free<byte>(tt)
                              in _extract_author_and_card(title_txt, tsz,
                                  opf_b, opf_f, dc2_sz, a_off, a_len,
                                  file_handle, file_size, cd_off, cd_count,
                                  opf_doff, opf_entry.compressed_size,
                                  opf_entry.compression,
                                  opf_entry.name_offset, opf_entry.name_len) end
                              else let
                                var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
                              in _extract_author_and_card($S.text_of_chars(unk_c, 7), 7,
                                  opf_b, opf_f, dc2_sz, a_off, a_len,
                                  file_handle, file_size, cd_off, cd_count,
                                  opf_doff, opf_entry.compressed_size,
                                  opf_entry.compression,
                                  opf_entry.name_offset, opf_entry.name_len) end
                            else let
                              var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
                            in _extract_author_and_card($S.text_of_chars(unk_c, 7), 7,
                                opf_b, opf_f, dc2_sz, a_off, a_len,
                                file_handle, file_size, cd_off, cd_count,
                                opf_doff, opf_entry.compressed_size,
                                opf_entry.compression,
                                opf_entry.name_offset, opf_entry.name_len) end
                          else let
                            var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
                          in _extract_author_and_card($S.text_of_chars(unk_c, 7), 7,
                              opf_b, opf_f, dc2_sz, a_off, a_len,
                              file_handle, file_size, cd_off, cd_count,
                              opf_doff, opf_entry.compressed_size,
                              opf_entry.compression,
                              opf_entry.name_offset, opf_entry.name_len) end
                        end
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


fn _restore_font_size(): void = let
  var font_c = @[char][4]('f', 'o', 'n', 't')
  val ka = $S.from_char_array(font_c, 4)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val font_p = $IDB.idb_get(kb, 4)
  val () = $A.drop<byte>(kf, kb)
  val ktmp = $A.thaw<byte>(kf)
  val () = $A.free<byte>(ktmp)
  val font_p = $P.vow(font_p)
  val p2 = $P.and_then<int><int>(font_p, lam(font_len) =>
    if font_len <> 2 then $P.ret<int>(~1)
    else let
      val fdata = $IDB.idb_get_result(2)
      val lo = byte2int0($A.get<byte>(fdata, 0))
      val hi = byte2int0($A.get<byte>(fdata, 1))
      val () = $A.free<byte>(fdata)
      val sz = lo + hi * 256
    in
      if sz >= 8 then
        if sz <= 48 then let
          val () = apply_font_size(sz)
        in $P.ret<int>(0) end
        else $P.ret<int>(~1)
      else $P.ret<int>(~1)
    end)
  val () = $P.discard<int>(p2)
in end

(* Restore: get author from IDB, then create book card *)
fn _restore_make_card
  {nt:pos | nt < 65536}{na:pos | na < 65536}
  (title_txt: $A.text(nt), title_len: int nt,
   author_txt: $A.text(na), author_len: int na,
   fh: int, book_len: int): $P.promise(int, $P.Chained) = let
  val () = _add_book_card(title_txt, title_len, author_txt, author_len,
    fh, book_len,
    $ST.stash_get_int(12), $ST.stash_get_int(13),
    $ST.stash_get_int(14), $ST.stash_get_int(15),
    $ST.stash_get_int(16), $ST.stash_get_int(17),
    $ST.stash_get_int(18))
in $P.ret<int>(0) end

fn _restore_get_author
  {nt:pos | nt < 65536}
  (title_txt: $A.text(nt), title_len: int nt,
   fh: int, book_len: int): $P.promise(int, $P.Chained) = let
  var auth_c = @[char][4]('a', 'u', 't', 'h')
  val aka = $S.from_char_array(auth_c, 4)
  val @(akf, akb) = $A.freeze<byte>(aka)
  val auth_p = $IDB.idb_get(akb, 4)
  val () = $A.drop<byte>(akf, akb)
  val akt = $A.thaw<byte>(akf)
  val () = $A.free<byte>(akt)
  val auth_p = $P.vow(auth_p)
in
  $P.and_then<int><int>(auth_p, lam(auth_len) =>
    if auth_len > 0 then
      if auth_len < 256 then let
        val asz = $AR.checked_text_size(auth_len)
        val abuf = $IDB.idb_get_result(asz)
        val atxt = arr_to_text(abuf, asz)
        val () = $A.free<byte>(abuf)
      in _restore_make_card(title_txt, title_len, atxt, asz, fh, book_len) end
      else let
        var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
      in _restore_make_card(title_txt, title_len, $S.text_of_chars(unk_c, 7), 7, fh, book_len) end
    else let
      var unk_c = @[char][7]('U', 'n', 'k', 'n', 'o', 'w', 'n')
    in _restore_make_card(title_txt, title_len, $S.text_of_chars(unk_c, 7), 7, fh, book_len) end)
end

(* Restore reading state from IDB on startup *)
fn _restore_from_idb(): void = let
  (* Step 1: get "book" from IDB *)
  var book_c = @[char][4]('b', 'o', 'o', 'k')
  val ka = $S.from_char_array(book_c, 4)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val book_p = $IDB.idb_get(kb, 4)
  val () = $A.drop<byte>(kf, kb)
  val ktmp = $A.thaw<byte>(kf)
  val () = $A.free<byte>(ktmp)
  val book_p = $P.vow(book_p)
  val p2 = $P.and_then<int><int>(book_p, lam(book_len) =>
    if book_len <= 0 then $P.ret<int>(~1)
    else if book_len > 1048576 then $P.ret<int>(~1)
    else let
      (* Read EPUB bytes from IDB result *)
      val bsz = $AR.checked_arr_size(book_len)
      val book_data = $IDB.idb_get_result(bsz)
      (* Store into file cache *)
      val @(bf, bb) = $A.freeze<byte>(book_data)
      val fh = $FI.file_store(bb, bsz)
      val () = $A.drop<byte>(bf, bb)
      val btmp = $A.thaw<byte>(bf)
      val () = $A.free<byte>(btmp)
      val () = $ST.stash_set_int(10, fh)
      val () = $ST.stash_set_int(11, book_len)

      (* Step 2: get "meta" from IDB *)
      var meta_c = @[char][4]('m', 'e', 't', 'a')
      val ma = $S.from_char_array(meta_c, 4)
      val @(mf, mb) = $A.freeze<byte>(ma)
      val meta_p = $IDB.idb_get(mb, 4)
      val () = $A.drop<byte>(mf, mb)
      val mtmp = $A.thaw<byte>(mf)
      val () = $A.free<byte>(mtmp)
      val meta_p = $P.vow(meta_p)
    in
      $P.and_then<int><int>(meta_p, lam(meta_len) =>
        if meta_len <> 36 then $P.ret<int>(~2)
        else let
          (* Read 9 x 4-byte ints = stash slots 10-18 *)
          val meta_data = $IDB.idb_get_result(36)
          fun _read_slot {l:agz}{n:pos}{s:nat}{off:nat | off + 4 <= n}{fuel:nat} .<fuel>.
            (buf: !$A.arr(byte, l, n), max: int n,
             slot: int s, off: int off, fuel: int fuel): void =
            if fuel <= 0 then ()
            else if slot >= 32 then ()
            else let
              val b0 = byte2int0($A.get<byte>(buf, off))
              val b1 = byte2int0($A.get<byte>(buf, off + 1))
              val b2 = byte2int0($A.get<byte>(buf, off + 2))
              val b3 = byte2int0($A.get<byte>(buf, off + 3))
              val v = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
              val () = $ST.stash_set_int(slot, v)
            in
              if off + 8 <= max then
                _read_slot(buf, max, slot + 1, off + 4, fuel - 1)
              else ()
            end
          val () = _read_slot(meta_data, 36, 10, 0, 9)
          val () = $A.free<byte>(meta_data)
          (* Override slot 10 with the new file handle from file_store *)
          val () = $ST.stash_set_int(10, fh)

          (* Step 3: get "titl" from IDB for book card *)
          var titl_c = @[char][4]('t', 'i', 't', 'l')
          val tka = $S.from_char_array(titl_c, 4)
          val @(tkf, tkb) = $A.freeze<byte>(tka)
          val titl_p = $IDB.idb_get(tkb, 4)
          val () = $A.drop<byte>(tkf, tkb)
          val tkt = $A.thaw<byte>(tkf)
          val () = $A.free<byte>(tkt)
          val titl_p = $P.vow(titl_p)
        in
          $P.and_then<int><int>(titl_p, lam(titl_len) =>
            if titl_len > 0 then
              if titl_len < 256 then let
                val tsz = $AR.checked_text_size(titl_len)
                val tbuf = $IDB.idb_get_result(tsz)
                val txt = arr_to_text(tbuf, tsz)
                val () = $A.free<byte>(tbuf)
              in _restore_get_author(txt, tsz, fh, book_len) end
              else let
                var unk_c = @[char][10]('S', 'a', 'v', 'e', 'd', ' ', 'B', 'o', 'o', 'k')
              in _restore_get_author($S.text_of_chars(unk_c, 10), 10, fh, book_len) end
            else let
              var unk_c = @[char][10]('S', 'a', 'v', 'e', 'd', ' ', 'B', 'o', 'o', 'k')
            in _restore_get_author($S.text_of_chars(unk_c, 10), 10, fh, book_len) end)
        end)
    end)
  val () = $P.discard<int>(p2)
in end


(* Public API *)

#pub fun import_epub
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni
  ): $P.promise(int, $P.Chained)

implement import_epub(node_id, id_len) = _import_epub(node_id, id_len)

#pub fun save_epub_to_idb(): void
implement save_epub_to_idb() = _save_epub_to_idb()

#pub fun save_metadata_to_idb(): void
implement save_metadata_to_idb() = _save_metadata_to_idb()

#pub fun save_font_size(): void
implement save_font_size() = _save_font_size()

#pub fun restore_font_size(): void
implement restore_font_size() = _restore_font_size()

#pub fun restore_from_idb(): void
implement restore_from_idb() = _restore_from_idb()
