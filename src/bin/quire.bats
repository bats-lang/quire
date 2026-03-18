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
staload "epub_xml.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload SC = "wasm.bats-packages.dev/bridge/src/scroll.sats"

(* EPUB XML helpers are in epub_xml module *)

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

fn _find_chapter_href_n
  {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), len: int n,
   nodes: !$X.xml_node_list(sz),
   chapter_idx: int): @(int, int) = let
  val idref = find_nth_idref(data, len, nodes, chapter_idx)
in
  if idref.0 >= 0 then
    find_manifest_href(data, len, nodes, idref.0, idref.1)
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

(* ============================================================
   Persistence helpers (IDB)
   ============================================================ *)

(* Save reading position to IDB: 4 bytes = u16 chapter + u16 page *)
fn _save_position(): void = let
  val ch = $ST.stash_get_int(23)
  val pg = $ST.stash_get_int(21)
  val buf = $A.alloc<byte>(4)
  val () = $A.set<byte>(buf, 0, int2byte0(ch mod 256))
  val () = $A.set<byte>(buf, 1, int2byte0(ch / 256))
  val () = $A.set<byte>(buf, 2, int2byte0(pg mod 256))
  val () = $A.set<byte>(buf, 3, int2byte0(pg / 256))
  val @(bf, bb) = $A.freeze<byte>(buf)
  var k = @[char][3]('p', 'o', 's')
  val ka = $A.alloc<byte>(3)
  val () = $A.set<byte>(ka, 0, int2byte0(112))
  val () = $A.set<byte>(ka, 1, int2byte0(111))
  val () = $A.set<byte>(ka, 2, int2byte0(115))
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_put(kb, 3, bb, 4)
  val () = $P.discard<int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
in end

(* Save EPUB file bytes to IDB *)
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
      val ka = $A.alloc<byte>(4)
      val () = $A.set<byte>(ka, 0, int2byte0(98))  (* b *)
      val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 2, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 3, int2byte0(107)) (* k *)
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
  fun _write_slot {l:agz}{n:pos}{s:nat}{fuel:nat} .<fuel>.
    (buf: !$A.arr(byte, l, n), max: int n,
     slot: int s, off: int, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if slot >= 32 then ()
    else if off < 0 then ()
    else if off + 3 >= max then ()
    else let
      val v = $ST.stash_get_int(slot)
      val () = $A.set<byte>(buf, $AR.checked_idx(off, max), int2byte0(v mod 256))
      val () = $A.set<byte>(buf, $AR.checked_idx(off + 1, max), int2byte0((v / 256) mod 256))
      val () = $A.set<byte>(buf, $AR.checked_idx(off + 2, max), int2byte0((v / 65536) mod 256))
      val () = $A.set<byte>(buf, $AR.checked_idx(off + 3, max), int2byte0((v / 16777216) mod 256))
    in _write_slot(buf, max, slot + 1, off + 4, fuel - 1) end
  val () = _write_slot(buf, 36, 10, 0, 9)
  val @(bf, bb) = $A.freeze<byte>(buf)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(109)) (* m *)
  val () = $A.set<byte>(ka, 1, int2byte0(101)) (* e *)
  val () = $A.set<byte>(ka, 2, int2byte0(116)) (* t *)
  val () = $A.set<byte>(ka, 3, int2byte0(97))  (* a *)
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

(* Stash slots: 21=current_page (0-indexed), 22=total_pages, 23=current_chapter (1-indexed), 24=total_chapters *)

(* Write an integer into a byte buffer at offset, return new offset *)
fun _write_int_digits
  {l:agz}{n:pos}{v:nat}{fuel:nat} .<fuel>.
  (buf: !$A.arr(byte, l, n), max: int n,
   off: int, value: int v, fuel: int fuel): int =
  if fuel <= 0 then off
  else if value < 10 then
    if off >= 0 then
      if off < max then let
        val () = $A.set<byte>(buf, $AR.checked_idx(off, max), int2byte0(48 + value))
      in off + 1 end
      else off
    else off
  else let
    val new_off = _write_int_digits(buf, max, off, value / 10, fuel - 1)
  in
    if new_off >= 0 then
      if new_off < max then let
        val () = $A.set<byte>(buf, $AR.checked_idx(new_off, max),
          int2byte0(48 + (value - (value / 10) * 10)))
      in new_off + 1 end
      else new_off
    else new_off
  end

fn _set_byte
  {l:agz}{n:pos}
  (buf: !$A.arr(byte, l, n), max: int n, off: int, b: int): int =
  if off >= 0 then
    if off < max then let
      val () = $A.set<byte>(buf, $AR.checked_idx(off, max), int2byte0(b))
    in off + 1 end
    else off
  else off

(* Apply font size to content area via dynamic style element *)
(* Writes ".caf{font-size:NNpx}" to style element qfss *)
fn _apply_font_size(size: int): void = let
  val sz = (if size < 8 then 8 else if size > 48 then 48 else size): int
  val () = $ST.stash_set_int(25, sz)
  (* Build CSS string ".caf{font-size:NNpx}" — max 22 bytes *)
  val buf = $A.alloc<byte>(22)
  val off = _set_byte(buf, 22, 0, 46)   (* . *)
  val off = _set_byte(buf, 22, off, 99)  (* c *)
  val off = _set_byte(buf, 22, off, 97)  (* a *)
  val off = _set_byte(buf, 22, off, 102) (* f *)
  val off = _set_byte(buf, 22, off, 123) (* { *)
  val off = _set_byte(buf, 22, off, 102) (* f *)
  val off = _set_byte(buf, 22, off, 111) (* o *)
  val off = _set_byte(buf, 22, off, 110) (* n *)
  val off = _set_byte(buf, 22, off, 116) (* t *)
  val off = _set_byte(buf, 22, off, 45)  (* - *)
  val off = _set_byte(buf, 22, off, 115) (* s *)
  val off = _set_byte(buf, 22, off, 105) (* i *)
  val off = _set_byte(buf, 22, off, 122) (* z *)
  val off = _set_byte(buf, 22, off, 101) (* e *)
  val off = _set_byte(buf, 22, off, 58)  (* : *)
  val off = _write_int_digits(buf, 22, off, $AR.checked_nat(sz), 3)
  val off = _set_byte(buf, 22, off, 112) (* p *)
  val off = _set_byte(buf, 22, off, 120) (* x *)
  val off = _set_byte(buf, 22, off, 125) (* } *)
in
  if off > 0 then
    if off <= 22 then let
      val tsz = $AR.checked_text_size(off)
      val exact = $A.alloc<byte>(tsz)
      fun _fcopy {la:agz}{na:pos}{lb:agz}{nb:pos}{i:nat | i <= na} .<na - i>.
        (src: !$A.arr(byte, la, na), dst: !$A.arr(byte, lb, nb),
         max_s: int na, max_d: int nb, i: int i): void =
        if i >= max_s then ()
        else if i >= max_d then ()
        else let
          val b = $A.get<byte>(src, $AR.checked_idx(i, max_s))
          val () = $A.set<byte>(dst, $AR.checked_idx(i, max_d), b)
        in _fcopy(src, dst, max_s, max_d, i + 1) end
      val () = _fcopy(buf, exact, 22, tsz, 0)
      val () = $A.free<byte>(buf)
      val txt = arr_to_text(exact, tsz)
      val () = $A.free<byte>(exact)
      var fs_c = @[char][4]('q', 'f', 's', 's')
      val fs_id = $W.Generated($S.text_of_chars(fs_c, 4), 4)
      val () = _apply_diff($W.SetTextContent(fs_id, txt, tsz))
    in end
    else $A.free<byte>(buf)
  else $A.free<byte>(buf)
end

(* Save font size to IDB *)
fn _save_font_size(): void = let
  val sz = $ST.stash_get_int(25)
  val buf = $A.alloc<byte>(2)
  val () = $A.set<byte>(buf, 0, int2byte0(sz mod 256))
  val () = $A.set<byte>(buf, 1, int2byte0(sz / 256))
  val @(bf, bb) = $A.freeze<byte>(buf)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(102)) (* f *)
  val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 2, int2byte0(110)) (* n *)
  val () = $A.set<byte>(ka, 3, int2byte0(116)) (* t *)
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

fn _update_page_indicator(): void = let
  val cur_page = $ST.stash_get_int(21)
  val total = $ST.stash_get_int(22)
  val chapter = $ST.stash_get_int(23)
  (* Build "Ch N · p. M/T" in a 24-byte buffer *)
  val tbuf = $A.alloc<byte>(24)
  val off = _set_byte(tbuf, 24, 0, 67)  (* C *)
  val off = _set_byte(tbuf, 24, off, 104) (* h *)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _write_int_digits(tbuf, 24, off, $AR.checked_nat(chapter), 3)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _set_byte(tbuf, 24, off, 194) (* 0xC2 = first byte of · *)
  val off = _set_byte(tbuf, 24, off, 183) (* 0xB7 = second byte of · *)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _set_byte(tbuf, 24, off, 112) (* p *)
  val off = _set_byte(tbuf, 24, off, 46)  (* . *)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _write_int_digits(tbuf, 24, off, $AR.checked_nat(cur_page + 1), 3)
  val off = _set_byte(tbuf, 24, off, 47)  (* / *)
  val off = _write_int_digits(tbuf, 24, off, $AR.checked_nat(total), 3)
in
  if off > 0 then
    if off < 24 then let
      (* Copy to exact-size buffer for text conversion *)
      val tsz = $AR.checked_text_size(off)
      val exact = $A.alloc<byte>(tsz)
      fun _copy {la:agz}{na:pos}{lb:agz}{nb:pos}{i:nat | i <= na} .<na - i>.
        (src: !$A.arr(byte, la, na), dst: !$A.arr(byte, lb, nb),
         max_s: int na, max_d: int nb, i: int i): void =
        if i >= max_s then ()
        else if i >= max_d then ()
        else let
          val b = $A.get<byte>(src, $AR.checked_idx(i, max_s))
          val () = $A.set<byte>(dst, $AR.checked_idx(i, max_d), b)
        in _copy(src, dst, max_s, max_d, i + 1) end
      val () = _copy(tbuf, exact, 24, tsz, 0)
      val () = $A.free<byte>(tbuf)
      val txt = arr_to_text(exact, tsz)
      val () = $A.free<byte>(exact)
      var pi_c = @[char][4]('q', 'p', 'g', 'i')
      val pi_id = $W.Generated($S.text_of_chars(pi_c, 4), 4)
      val () = _apply_diff($W.SetTextContent(pi_id, txt, tsz))
    in end
    else let
      val () = $A.free<byte>(tbuf)
    in end
  else let
    val () = $A.free<byte>(tbuf)
  in end
end

fn _measure_pagination(): void = let
  val cnt_narr = $A.alloc<byte>(4)
  val () = $A.set<byte>(cnt_narr, 0, int2byte0(113))
  val () = $A.set<byte>(cnt_narr, 1, int2byte0(99))
  val () = $A.set<byte>(cnt_narr, 2, int2byte0(110))
  val () = $A.set<byte>(cnt_narr, 3, int2byte0(116))
  val @(cnt_f, cnt_b) = $A.freeze<byte>(cnt_narr)
  val mr = $DR.measure(cnt_b, 4)
  val () = $A.drop<byte>(cnt_f, cnt_b)
  val cnt_tmp = $A.thaw<byte>(cnt_f)
  val () = $A.free<byte>(cnt_tmp)
  val _ = $R.discard<int><int>(mr)
  val cw = $DR.get_measure_w()
  val sw = $DR.get_measure_scroll_w()
in
  if cw > 0 then let
    val total = sw / cw
    val total_p = (if total < 1 then 1 else total): int
    val () = $ST.stash_set_int(21, 0)
    val () = $ST.stash_set_int(22, total_p)
    val () = _update_page_indicator()
  in end
  else let
    val () = $ST.stash_set_int(21, 0)
    val () = $ST.stash_set_int(22, 1)
    val () = _update_page_indicator()
  in end
end

fn _scroll_to_page(page: int): void = let
  val () = $ST.stash_set_int(21, page)
  val cnt_narr = $A.alloc<byte>(4)
  val () = $A.set<byte>(cnt_narr, 0, int2byte0(113))
  val () = $A.set<byte>(cnt_narr, 1, int2byte0(99))
  val () = $A.set<byte>(cnt_narr, 2, int2byte0(110))
  val () = $A.set<byte>(cnt_narr, 3, int2byte0(116))
  val @(cnt_f, cnt_b) = $A.freeze<byte>(cnt_narr)
  val mr = $DR.measure(cnt_b, 4)
  val _ = $R.discard<int><int>(mr)
  val cw = $DR.get_measure_w()
  val scroll_x = page * cw
  val () = $SC.set_scroll_left(cnt_b, 4, scroll_x)
  val () = $A.drop<byte>(cnt_f, cnt_b)
  val cnt_tmp = $A.thaw<byte>(cnt_f)
  val () = $A.free<byte>(cnt_tmp)
  val () = _update_page_indicator()
  val () = _save_position()
in end

(* ============================================================
   Content tree rendering (XHTML → DOM nodes)
   ============================================================ *)

(* Stash slot 28: content node counter *)

(* Generate widget_id for content node at index *)
fn _content_wid(idx: int): $W.widget_id = let
  val n = idx - (idx / 1000) * 1000
  val d2 = n / 100
  val r2 = n - d2 * 100
  val d1 = r2 / 10
  val d0 = r2 - d1 * 10
  val buf = $A.alloc<byte>(4)
  val () = $A.set<byte>(buf, 0, int2byte0(99))
  val () = $A.set<byte>(buf, 1, int2byte0(48 + d2))
  val () = $A.set<byte>(buf, 2, int2byte0(48 + d1))
  val () = $A.set<byte>(buf, 3, int2byte0(48 + d0))
  val txt = arr_to_text(buf, 4)
  val () = $A.free<byte>(buf)
in $W.Generated(txt, 4) end

(* Generate widget_id for parent: -1 = qcnt, >= 0 = content node *)
fn _parent_wid(pidx: int): $W.widget_id =
  if pidx < 0 then let
    var c = @[char][4]('q', 'c', 'n', 't')
  in $W.Generated($S.text_of_chars(c, 4), 4) end
  else _content_wid(pidx)

(* Get next content node index and increment counter *)
fn _next_content_idx(): int = let
  val n = $ST.stash_get_int(28)
  val () = $ST.stash_set_int(28, n + 1)
in n end

(* Match XHTML tag name to widget html_normal type *)
fn _match_tag_to_normal
  {lb:agz}{n:pos}
  (data: !$A.borrow(byte, lb, n), len: int n,
   name_off: int, name_len: int): $W.html_normal = let
  var _t_p = @[char][1]('p')
  var _t_h1 = @[char][2]('h', '1')
  var _t_h2 = @[char][2]('h', '2')
  var _t_h3 = @[char][2]('h', '3')
  var _t_h4 = @[char][2]('h', '4')
  var _t_h5 = @[char][2]('h', '5')
  var _t_h6 = @[char][2]('h', '6')
  var _t_div = @[char][3]('d', 'i', 'v')
  var _t_span = @[char][4]('s', 'p', 'a', 'n')
  var _t_em = @[char][2]('e', 'm')
  var _t_strong = @[char][6]('s', 't', 'r', 'o', 'n', 'g')
  var _t_bq = @[char][10]('b', 'l', 'o', 'c', 'k', 'q', 'u', 'o', 't', 'e')
  var _t_pre = @[char][3]('p', 'r', 'e')
  var _t_code = @[char][4]('c', 'o', 'd', 'e')
  var _t_ul = @[char][2]('u', 'l')
  var _t_ol = @[char][2]('o', 'l')
  var _t_li = @[char][2]('l', 'i')
  var _t_section = @[char][7]('s', 'e', 'c', 't', 'i', 'o', 'n')
  var _t_article = @[char][7]('a', 'r', 't', 'i', 'c', 'l', 'e')
  var _t_small = @[char][5]('s', 'm', 'a', 'l', 'l')
  var _t_mark = @[char][4]('m', 'a', 'r', 'k')
  var _t_del = @[char][3]('d', 'e', 'l')
  var _t_ins = @[char][3]('i', 'n', 's')
  var _t_sub = @[char][3]('s', 'u', 'b')
  var _t_sup = @[char][3]('s', 'u', 'p')
  var _t_a = @[char][1]('a')
  var _t_b = @[char][1]('b')
  var _t_i = @[char][1]('i')
  var _t_u = @[char][1]('u')
  var _t_s = @[char][1]('s')
  var _t_figure = @[char][6]('f', 'i', 'g', 'u', 'r', 'e')
  var _t_figcap = @[char][10]('f', 'i', 'g', 'c', 'a', 'p', 't', 'i', 'o', 'n')
  var _t_table = @[char][5]('t', 'a', 'b', 'l', 'e')
  var _t_tr = @[char][2]('t', 'r')
  var _t_td = @[char][2]('t', 'd')
  var _t_th = @[char][2]('t', 'h')
  var _t_thead = @[char][5]('t', 'h', 'e', 'a', 'd')
  var _t_tbody = @[char][5]('t', 'b', 'o', 'd', 'y')
in
  if xml_name_eq(data, len, name_off, name_len, _t_p, 1) then $W.P()
  else if xml_name_eq(data, len, name_off, name_len, _t_h1, 2) then $W.H1()
  else if xml_name_eq(data, len, name_off, name_len, _t_h2, 2) then $W.H2()
  else if xml_name_eq(data, len, name_off, name_len, _t_h3, 2) then $W.H3()
  else if xml_name_eq(data, len, name_off, name_len, _t_h4, 2) then $W.H4()
  else if xml_name_eq(data, len, name_off, name_len, _t_h5, 2) then $W.H5()
  else if xml_name_eq(data, len, name_off, name_len, _t_h6, 2) then $W.H6()
  else if xml_name_eq(data, len, name_off, name_len, _t_div, 3) then $W.Div()
  else if xml_name_eq(data, len, name_off, name_len, _t_span, 4) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_em, 2) then $W.Em()
  else if xml_name_eq(data, len, name_off, name_len, _t_strong, 6) then $W.Strong()
  else if xml_name_eq(data, len, name_off, name_len, _t_bq, 10) then $W.Blockquote()
  else if xml_name_eq(data, len, name_off, name_len, _t_pre, 3) then $W.Pre()
  else if xml_name_eq(data, len, name_off, name_len, _t_code, 4) then $W.HtmlCode()
  else if xml_name_eq(data, len, name_off, name_len, _t_ul, 2) then $W.Ul()
  else if xml_name_eq(data, len, name_off, name_len, _t_ol, 2) then $W.Ol($W.NoneInt())
  else if xml_name_eq(data, len, name_off, name_len, _t_li, 2) then $W.Li()
  else if xml_name_eq(data, len, name_off, name_len, _t_section, 7) then $W.Section()
  else if xml_name_eq(data, len, name_off, name_len, _t_article, 7) then $W.Article()
  else if xml_name_eq(data, len, name_off, name_len, _t_small, 5) then $W.Small()
  else if xml_name_eq(data, len, name_off, name_len, _t_mark, 4) then $W.Mark()
  else if xml_name_eq(data, len, name_off, name_len, _t_del, 3) then $W.Del()
  else if xml_name_eq(data, len, name_off, name_len, _t_ins, 3) then $W.Ins()
  else if xml_name_eq(data, len, name_off, name_len, _t_sub, 3) then $W.HtmlSub()
  else if xml_name_eq(data, len, name_off, name_len, _t_sup, 3) then $W.Sup()
  else if xml_name_eq(data, len, name_off, name_len, _t_a, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_b, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_i, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_u, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_s, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_figure, 6) then $W.Figure()
  else if xml_name_eq(data, len, name_off, name_len, _t_figcap, 10) then $W.Figcaption()
  else if xml_name_eq(data, len, name_off, name_len, _t_table, 5) then $W.Table()
  else if xml_name_eq(data, len, name_off, name_len, _t_tr, 2) then $W.Tr()
  else if xml_name_eq(data, len, name_off, name_len, _t_td, 2) then $W.Td(1, 1)
  else if xml_name_eq(data, len, name_off, name_len, _t_th, 2) then $W.Th(1, 1, $W.NoneInt())
  else if xml_name_eq(data, len, name_off, name_len, _t_thead, 5) then $W.Thead()
  else if xml_name_eq(data, len, name_off, name_len, _t_tbody, 5) then $W.Tbody()
  else $W.Div()
end

(* Walk xml_node_list, rendering each node into parent *)
fun _render_nodes
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int, nodes: !$X.xml_node_list(sz)): void =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val () = _render_node(data, len, pidx, node)
    in _render_nodes(data, len, pidx, rest) end
  | $X.xml_nodes_nil() => ()

and _render_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int, node: !$X.xml_node(sz)): void =
  case+ node of
  | $X.xml_text(off, tlen) =>
    if tlen > 0 then
      if tlen < 65536 then let
        val tsz = $AR.checked_text_size(tlen)
        val tbuf = $A.alloc<byte>(tsz)
        val () = copy_from_borrow(data, off, len, tbuf, 0, tsz, $AR.checked_nat(tlen))
        val txt = arr_to_text(tbuf, tsz)
        val () = $A.free<byte>(tbuf)
        val idx = _next_content_idx()
        val w = $W.Element($W.ElementNode(_content_wid(idx),
          $W.Normal($W.Span()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
        val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        val () = _apply_diff($W.SetTextContent(_content_wid(idx), txt, tsz))
      in end
      else ()
    else ()
  | $X.xml_element(name_off, name_len, _, children) => let
    (* Skip tags: head, title, meta, link, style, script *)
    var _t_head = @[char][4]('h', 'e', 'a', 'd')
    var _t_title = @[char][5]('t', 'i', 't', 'l', 'e')
    var _t_meta = @[char][4]('m', 'e', 't', 'a')
    var _t_link = @[char][4]('l', 'i', 'n', 'k')
    var _t_style = @[char][5]('s', 't', 'y', 'l', 'e')
    var _t_script = @[char][6]('s', 'c', 'r', 'i', 'p', 't')
  in
    if xml_name_eq(data, len, name_off, name_len, _t_head, 4) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_title, 5) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_meta, 4) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_link, 4) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_style, 5) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_script, 6) then ()
    else let
      (* Transparent tags: html, body — render children with same parent *)
      var _t_html = @[char][4]('h', 't', 'm', 'l')
      var _t_body = @[char][4]('b', 'o', 'd', 'y')
    in
      if xml_name_eq(data, len, name_off, name_len, _t_html, 4) then
        _render_nodes(data, len, pidx, children)
      else if xml_name_eq(data, len, name_off, name_len, _t_body, 4) then
        _render_nodes(data, len, pidx, children)
      else let
        (* Void tags: br, hr *)
        var _t_br = @[char][2]('b', 'r')
        var _t_hr = @[char][2]('h', 'r')
      in
        if xml_name_eq(data, len, name_off, name_len, _t_br, 2) then let
          val idx = _next_content_idx()
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Void($W.Br()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        in end
        else if xml_name_eq(data, len, name_off, name_len, _t_hr, 2) then let
          val idx = _next_content_idx()
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Void($W.Hr()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        in end
        else let
          (* Normal element: match tag name, create element, recurse *)
          val idx = _next_content_idx()
          val tag = _match_tag_to_normal(data, len, name_off, name_len)
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Normal(tag), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
          val () = _render_nodes(data, len, idx, children)
        in end
      end
    end
  end

fn _load_chapter(chapter_idx: int): $P.promise(int, $P.Chained) = let
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
    val fbuf2 = copy_arr_region(fbuf2, opf_doff, fsz_s,
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

        (* Count spine items and store total chapters *)
        val total_ch = count_spine_items(opf_b, dc_sz, opf_nodes, 0)
        val () = $ST.stash_set_int(24, total_ch)

        (* Find Nth spine itemref → manifest item href *)
        val ch_href = _find_chapter_href_n(opf_b, dc_sz, opf_nodes, chapter_idx)
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
          val () = copy_from_borrow(opf_b, ch_off, dc_sz,
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
                  val ch_xhtml = $A.alloc<byte>(ch_dc_sz)
                  val () = $R.discard($DC.blob_read(ch_dc_handle, 0, ch_xhtml, ch_dc_sz))
                  val () = $DC.blob_free(ch_dc_handle)

                  (* Parse XHTML with xml-tree *)
                  val @(xf, xb) = $A.freeze<byte>(ch_xhtml)
                  val nodes = $X.parse_document(xb, ch_dc_sz)

                  (* Clear content area *)
                  var cnt_c = @[char][4]('q', 'c', 'n', 't')
                  val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
                  val () = _apply_diff($W.RemoveAllChildren(cnt_id))
                  val () = $ST.stash_set_int(28, 0)

                  (* Render XHTML tree into content area *)
                  val () = _render_nodes(xb, ch_dc_sz, ~1, nodes)
                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(xf, xb)
                  val ch_xhtml2 = $A.thaw<byte>(xf)
                  val () = $A.free<byte>(ch_xhtml2)

                  val () = $ST.stash_set_int(23, chapter_idx + 1)
                  val () = _measure_pagination()
                  val () = _save_position()
                in $P.ret<int>(0) end
              end)
            end
          end
        end
      end
    end)
  end
end

fn _go_to_page(page: int): void = let
  val total = $ST.stash_get_int(22)
  val cur_ch = $ST.stash_get_int(23)
  val total_ch = $ST.stash_get_int(24)
in
  if page >= total then
    if cur_ch < total_ch then let
      val ch_p = _load_chapter(cur_ch)
      val () = $P.discard<int>(ch_p)
    in end
    else _scroll_to_page(total - 1)
  else if page < 0 then
    if cur_ch > 1 then let
      val ch_p = _load_chapter(cur_ch - 2)
      val () = $P.discard<int>(ch_p)
    in end
    else _scroll_to_page(0)
  else _scroll_to_page(page)
end

(* Restore font size from IDB on startup *)
fn _restore_font_size(): void = let
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(102)) (* f *)
  val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 2, int2byte0(110)) (* n *)
  val () = $A.set<byte>(ka, 3, int2byte0(116)) (* t *)
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
          val () = _apply_font_size(sz)
        in $P.ret<int>(0) end
        else $P.ret<int>(~1)
      else $P.ret<int>(~1)
    end)
  val () = $P.discard<int>(p2)
in end

(* Restore reading state from IDB on startup *)
fn _restore_from_idb(): void = let
  (* Step 1: get "book" from IDB *)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(98))  (* b *)
  val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 2, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 3, int2byte0(107)) (* k *)
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
      val ma = $A.alloc<byte>(4)
      val () = $A.set<byte>(ma, 0, int2byte0(109)) (* m *)
      val () = $A.set<byte>(ma, 1, int2byte0(101)) (* e *)
      val () = $A.set<byte>(ma, 2, int2byte0(116)) (* t *)
      val () = $A.set<byte>(ma, 3, int2byte0(97))  (* a *)
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
          fun _read_slot {l:agz}{n:pos}{s:nat}{fuel:nat} .<fuel>.
            (buf: !$A.arr(byte, l, n), max: int n,
             slot: int s, off: int, fuel: int fuel): void =
            if fuel <= 0 then ()
            else if slot >= 32 then ()
            else if off < 0 then ()
            else if off + 3 >= max then ()
            else let
              val b0 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off, max)))
              val b1 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off + 1, max)))
              val b2 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off + 2, max)))
              val b3 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off + 3, max)))
              val v = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
              val () = $ST.stash_set_int(slot, v)
            in _read_slot(buf, max, slot + 1, off + 4, fuel - 1) end
          val () = _read_slot(meta_data, 36, 10, 0, 9)
          val () = $A.free<byte>(meta_data)
          (* Override slot 10 with the new file handle from file_store *)
          val () = $ST.stash_set_int(10, fh)

          (* Step 3: get "pos" from IDB *)
          val pa = $A.alloc<byte>(3)
          val () = $A.set<byte>(pa, 0, int2byte0(112)) (* p *)
          val () = $A.set<byte>(pa, 1, int2byte0(111)) (* o *)
          val () = $A.set<byte>(pa, 2, int2byte0(115)) (* s *)
          val @(pf, pb) = $A.freeze<byte>(pa)
          val pos_p = $IDB.idb_get(pb, 3)
          val () = $A.drop<byte>(pf, pb)
          val ptmp = $A.thaw<byte>(pf)
          val () = $A.free<byte>(ptmp)
          val pos_p = $P.vow(pos_p)
        in
          $P.and_then<int><int>(pos_p, lam(pos_len) =>
            if pos_len <> 4 then let
              (* No saved position — just load chapter 0 *)
              (* Show reader, hide library *)
              var ll_c = @[char][4]('q', 'l', 'l', 'c')
              val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
              var rv_c = @[char][4]('q', 'r', 'v', 'w')
              val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
              val () = _apply_diff($W.SetHidden(ll_id, 1))
              val () = _apply_diff($W.SetHidden(rv_id, 0))
              val ch_p = _load_chapter(0)
              val () = $P.discard<int>(ch_p)
            in $P.ret<int>(0) end
            else let
              val pos_data = $IDB.idb_get_result(4)
              val ch_lo = byte2int0($A.get<byte>(pos_data, 0))
              val ch_hi = byte2int0($A.get<byte>(pos_data, 1))
              val pg_lo = byte2int0($A.get<byte>(pos_data, 2))
              val pg_hi = byte2int0($A.get<byte>(pos_data, 3))
              val () = $A.free<byte>(pos_data)
              val saved_ch = ch_lo + ch_hi * 256
              val saved_pg = pg_lo + pg_hi * 256
              (* Show reader, hide library *)
              var ll_c = @[char][4]('q', 'l', 'l', 'c')
              val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
              var rv_c = @[char][4]('q', 'r', 'v', 'w')
              val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
              val () = _apply_diff($W.SetHidden(ll_id, 1))
              val () = _apply_diff($W.SetHidden(rv_id, 0))
              (* Load the saved chapter (1-indexed → 0-indexed) *)
              val ch_idx = (if saved_ch > 0 then saved_ch - 1 else 0): int
              val ch_p = _load_chapter(ch_idx)
              (* After chapter loads, scroll to saved page *)
              val ch_p2 = $P.and_then<int><int>(ch_p, lam(result) =>
                if result = 0 then let
                  val () = _scroll_to_page(saved_pg)
                in $P.ret<int>(0) end
                else $P.ret<int>(result))
              val () = $P.discard<int>(ch_p2)
            in $P.ret<int>(0) end)
        end)
    end)
  val () = $P.discard<int>(p2)
in end

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

  (* Font size style element — dynamic CSS for font size override *)
  var fs_c = @[char][4]('q', 'f', 's', 's')
  val fs_id = $W.Generated($S.text_of_chars(fs_c, 4), 4)
  var fs_init = @[char][20]('\x2E', 'c', 'a', 'f', '\x7B', 'f', 'o', 'n', 't', '-', 's', 'i', 'z', 'e', ':', '1', '6', 'p', 'x', '\x7D')
  val @(root, fs_diffs) = $W.inject_css(root, fs_id, $S.text_of_chars(fs_init, 20), 20)
  val () = $D.apply_list(doc, fs_diffs)
  val () = $ST.stash_set_int(25, 16)

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

  (* Nav bar inside reader view *)
  var nv_c = @[char][4]('q', 'r', 'n', 'v')
  val nv_id = $W.Generated($S.text_of_chars(nv_c, 4), 4)
  val nv = $W.Element($W.ElementNode(nv_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(rv, diff) = $W.add_child(rv, nv)
  val () = $D.apply(doc, diff)
  val @(nv, diff) = $W.set_class(nv, cls_nav_bar())
  val () = $D.apply(doc, diff)

  (* Back button inside nav bar *)
  var bb_c = @[char][4]('q', 'b', 'b', 'k')
  val bb_id = $W.Generated($S.text_of_chars(bb_c, 4), 4)
  val bb = $W.Element($W.ElementNode(bb_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(nv, diff) = $W.add_child(nv, bb)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(bb, cls_back_btn())
  val () = $D.apply(doc, diff)
  (* U+2190 = ← = 0xE2 0x86 0x90 *)
  var back_c = @[char][3]('\xE2', '\x86', '\x90')
  val () = $D.apply(doc, $W.set_text_content(bb_id, $S.text_of_chars(back_c, 3), 3))

  (* Chapter title *)
  var ct_c = @[char][4]('q', 'c', 'h', 't')
  val ct_id = $W.Generated($S.text_of_chars(ct_c, 4), 4)
  val ct = $W.Element($W.ElementNode(ct_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(nv, diff) = $W.add_child(nv, ct)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(ct, cls_chapter_title())
  val () = $D.apply(doc, diff)
  var cht_txt = @[char][9]('C', 'h', 'a', 'p', 't', 'e', 'r', ' ', '1')
  val () = $D.apply(doc, $W.set_text_content(ct_id, $S.text_of_chars(cht_txt, 9), 9))

  (* Page info *)
  var pi_c = @[char][4]('q', 'p', 'g', 'i')
  val pi_id = $W.Generated($S.text_of_chars(pi_c, 4), 4)
  val pi = $W.Element($W.ElementNode(pi_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(nv, diff) = $W.add_child(nv, pi)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(pi, cls_page_info())
  val () = $D.apply(doc, diff)

  (* Prev button — U+2039 = ‹ = 0xE2 0x80 0xB9 *)
  var pv_c = @[char][4]('q', 'p', 'r', 'v')
  val pv_id = $W.Generated($S.text_of_chars(pv_c, 4), 4)
  val pv = $W.Element($W.ElementNode(pv_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(nv, diff) = $W.add_child(nv, pv)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(pv, cls_nav_button())
  val () = $D.apply(doc, diff)
  var prev_c = @[char][3]('\xE2', '\x80', '\xB9')
  val () = $D.apply(doc, $W.set_text_content(pv_id, $S.text_of_chars(prev_c, 3), 3))

  (* Next button — U+203A = › = 0xE2 0x80 0xBA *)
  var nx_c = @[char][4]('q', 'n', 'x', 't')
  val nx_id = $W.Generated($S.text_of_chars(nx_c, 4), 4)
  val nx = $W.Element($W.ElementNode(nx_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(nv, nx)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(nx, cls_nav_button())
  val () = $D.apply(doc, diff)
  var next_c = @[char][3]('\xE2', '\x80', '\xBA')
  val () = $D.apply(doc, $W.set_text_content(nx_id, $S.text_of_chars(next_c, 3), 3))

  (* Settings gear button — U+2699 = ⚙ = 0xE2 0x9A 0x99 *)
  var sg_c = @[char][4]('q', 's', 'e', 't')
  val sg_id = $W.Generated($S.text_of_chars(sg_c, 4), 4)
  val sg = $W.Element($W.ElementNode(sg_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(nv, sg)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(sg, cls_nav_button())
  val () = $D.apply(doc, diff)
  var gear_c = @[char][3]('\xE2', '\x9A', '\x99')
  val () = $D.apply(doc, $W.set_text_content(sg_id, $S.text_of_chars(gear_c, 3), 3))

  (* Content area inside reader view *)
  var ca_c = @[char][4]('q', 'c', 'n', 't')
  val ca_id = $W.Generated($S.text_of_chars(ca_c, 4), 4)
  val ca = $W.Element($W.ElementNode(ca_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(rv, diff) = $W.add_child(rv, ca)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(ca, cls_content_area())
  val () = $D.apply(doc, diff)

  (* Click zones — transparent overlays for page navigation *)
  var zl_c = @[char][4]('q', 'c', 'z', 'l')
  val zl_id = $W.Generated($S.text_of_chars(zl_c, 4), 4)
  val zl = $W.Element($W.ElementNode(zl_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(rv, diff) = $W.add_child(rv, zl)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(zl, cls_zone_left())
  val () = $D.apply(doc, diff)

  var zr_c = @[char][4]('q', 'c', 'z', 'r')
  val zr_id = $W.Generated($S.text_of_chars(zr_c, 4), 4)
  val zr = $W.Element($W.ElementNode(zr_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(rv, diff) = $W.add_child(rv, zr)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(zr, cls_zone_right())
  val () = $D.apply(doc, diff)

  var zc_c = @[char][4]('q', 'c', 'z', 'c')
  val zc_id = $W.Generated($S.text_of_chars(zc_c, 4), 4)
  val zc = $W.Element($W.ElementNode(zc_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(rv, zc)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(zc, cls_zone_center())
  val () = $D.apply(doc, diff)

  (* Settings panel — hidden overlay *)
  var sp_c = @[char][4]('q', 's', 'p', 'n')
  val sp_id = $W.Generated($S.text_of_chars(sp_c, 4), 4)
  val sp = $W.Element($W.ElementNode(sp_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(root, diff) = $W.add_child(root, sp)
  val () = $D.apply(doc, diff)
  val @(sp, diff) = $W.set_class(sp, cls_settings_panel())
  val () = $D.apply(doc, diff)
  val @(sp, diff) = $W.set_hidden(sp, 1)
  val () = $D.apply(doc, diff)

  (* "Font Size" label *)
  var fl_c = @[char][4]('q', 's', 'f', 'l')
  val fl_id = $W.Generated($S.text_of_chars(fl_c, 4), 4)
  val fl = $W.Element($W.ElementNode(fl_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(sp, diff) = $W.add_child(sp, fl)
  val () = $D.apply(doc, diff)
  var fsz_c = @[char][9]('F', 'o', 'n', 't', ' ', 'S', 'i', 'z', 'e')
  val () = $D.apply(doc, $W.set_text_content(fl_id, $S.text_of_chars(fsz_c, 9), 9))

  (* A- button (decrease font) *)
  var am_c = @[char][4]('q', 'f', 's', 'm')
  val am_id = $W.Generated($S.text_of_chars(am_c, 4), 4)
  val am = $W.Element($W.ElementNode(am_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(sp, diff) = $W.add_child(sp, am)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(am, cls_settings_btn())
  val () = $D.apply(doc, diff)
  var amin_c = @[char][2]('A', '-')
  val () = $D.apply(doc, $W.set_text_content(am_id, $S.text_of_chars(amin_c, 2), 2))

  (* A+ button (increase font) *)
  var ap_c = @[char][4]('q', 'f', 's', 'p')
  val ap_id = $W.Generated($S.text_of_chars(ap_c, 4), 4)
  val ap = $W.Element($W.ElementNode(ap_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(sp, diff) = $W.add_child(sp, ap)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(ap, cls_settings_btn())
  val () = $D.apply(doc, diff)
  var aplus_c = @[char][2]('A', '+')
  val () = $D.apply(doc, $W.set_text_content(ap_id, $S.text_of_chars(aplus_c, 2), 2))

  (* Close button *)
  var sc_c = @[char][4]('q', 's', 'c', 'l')
  val sc_id = $W.Generated($S.text_of_chars(sc_c, 4), 4)
  val scl = $W.Element($W.ElementNode(sc_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(sp, scl)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(scl, cls_settings_btn())
  val () = $D.apply(doc, diff)
  var close_c = @[char][5]('C', 'l', 'o', 's', 'e')
  val () = $D.apply(doc, $W.set_text_content(sc_id, $S.text_of_chars(close_c, 5), 5))

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
            val () = _save_epub_to_idb()
            val () = _save_metadata_to_idb()
            val ch_p = _load_chapter(0)
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

    (* Wire prev button click — listener 3 *)
    val pv_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(pv_narr, 0, int2byte0(113))
    val () = $A.set<byte>(pv_narr, 1, int2byte0(112))
    val () = $A.set<byte>(pv_narr, 2, int2byte0(114))
    val () = $A.set<byte>(pv_narr, 3, int2byte0(118))
    val @(pv_nf, pv_nb) = $A.freeze<byte>(pv_narr)
    val ck2_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck2_arr, 0, int2byte0(99))
    val () = $A.set<byte>(ck2_arr, 1, int2byte0(108))
    val () = $A.set<byte>(ck2_arr, 2, int2byte0(105))
    val () = $A.set<byte>(ck2_arr, 3, int2byte0(99))
    val () = $A.set<byte>(ck2_arr, 4, int2byte0(107))
    val @(ck2_f, ck2_b) = $A.freeze<byte>(ck2_arr)
    val () = $EV.listen(pv_nb, 4, ck2_b, 5, 3,
      lam(_payload_len: int): int => let
        val cur = $ST.stash_get_int(21)
      in _go_to_page(cur - 1); 0 end)
    val () = $A.drop<byte>(pv_nf, pv_nb)
    val pv_ntmp = $A.thaw<byte>(pv_nf)
    val () = $A.free<byte>(pv_ntmp)
    val () = $A.drop<byte>(ck2_f, ck2_b)
    val ck2_tmp = $A.thaw<byte>(ck2_f)
    val () = $A.free<byte>(ck2_tmp)

    (* Wire next button click — listener 4 *)
    val nx_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(nx_narr, 0, int2byte0(113))
    val () = $A.set<byte>(nx_narr, 1, int2byte0(110))
    val () = $A.set<byte>(nx_narr, 2, int2byte0(120))
    val () = $A.set<byte>(nx_narr, 3, int2byte0(116))
    val @(nx_nf, nx_nb) = $A.freeze<byte>(nx_narr)
    val ck3_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck3_arr, 0, int2byte0(99))
    val () = $A.set<byte>(ck3_arr, 1, int2byte0(108))
    val () = $A.set<byte>(ck3_arr, 2, int2byte0(105))
    val () = $A.set<byte>(ck3_arr, 3, int2byte0(99))
    val () = $A.set<byte>(ck3_arr, 4, int2byte0(107))
    val @(ck3_f, ck3_b) = $A.freeze<byte>(ck3_arr)
    val () = $EV.listen(nx_nb, 4, ck3_b, 5, 4,
      lam(_payload_len: int): int => let
        val cur = $ST.stash_get_int(21)
      in _go_to_page(cur + 1); 0 end)
    val () = $A.drop<byte>(nx_nf, nx_nb)
    val nx_ntmp = $A.thaw<byte>(nx_nf)
    val () = $A.free<byte>(nx_ntmp)
    val () = $A.drop<byte>(ck3_f, ck3_b)
    val ck3_tmp = $A.thaw<byte>(ck3_f)
    val () = $A.free<byte>(ck3_tmp)

    (* Wire left click zone — listener 5: prev page *)
    val zl_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(zl_narr, 0, int2byte0(113))
    val () = $A.set<byte>(zl_narr, 1, int2byte0(99))
    val () = $A.set<byte>(zl_narr, 2, int2byte0(122))
    val () = $A.set<byte>(zl_narr, 3, int2byte0(108))
    val @(zl_nf, zl_nb) = $A.freeze<byte>(zl_narr)
    val ck4_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck4_arr, 0, int2byte0(99))
    val () = $A.set<byte>(ck4_arr, 1, int2byte0(108))
    val () = $A.set<byte>(ck4_arr, 2, int2byte0(105))
    val () = $A.set<byte>(ck4_arr, 3, int2byte0(99))
    val () = $A.set<byte>(ck4_arr, 4, int2byte0(107))
    val @(ck4_f, ck4_b) = $A.freeze<byte>(ck4_arr)
    val () = $EV.listen(zl_nb, 4, ck4_b, 5, 5,
      lam(_payload_len: int): int => let
        val cur = $ST.stash_get_int(21)
      in _go_to_page(cur - 1); 0 end)
    val () = $A.drop<byte>(zl_nf, zl_nb)
    val zl_ntmp = $A.thaw<byte>(zl_nf)
    val () = $A.free<byte>(zl_ntmp)
    val () = $A.drop<byte>(ck4_f, ck4_b)
    val ck4_tmp = $A.thaw<byte>(ck4_f)
    val () = $A.free<byte>(ck4_tmp)

    (* Wire right click zone — listener 6: next page *)
    val zr_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(zr_narr, 0, int2byte0(113))
    val () = $A.set<byte>(zr_narr, 1, int2byte0(99))
    val () = $A.set<byte>(zr_narr, 2, int2byte0(122))
    val () = $A.set<byte>(zr_narr, 3, int2byte0(114))
    val @(zr_nf, zr_nb) = $A.freeze<byte>(zr_narr)
    val ck5_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck5_arr, 0, int2byte0(99))
    val () = $A.set<byte>(ck5_arr, 1, int2byte0(108))
    val () = $A.set<byte>(ck5_arr, 2, int2byte0(105))
    val () = $A.set<byte>(ck5_arr, 3, int2byte0(99))
    val () = $A.set<byte>(ck5_arr, 4, int2byte0(107))
    val @(ck5_f, ck5_b) = $A.freeze<byte>(ck5_arr)
    val () = $EV.listen(zr_nb, 4, ck5_b, 5, 6,
      lam(_payload_len: int): int => let
        val cur = $ST.stash_get_int(21)
      in _go_to_page(cur + 1); 0 end)
    val () = $A.drop<byte>(zr_nf, zr_nb)
    val zr_ntmp = $A.thaw<byte>(zr_nf)
    val () = $A.free<byte>(zr_ntmp)
    val () = $A.drop<byte>(ck5_f, ck5_b)
    val ck5_tmp = $A.thaw<byte>(ck5_f)
    val () = $A.free<byte>(ck5_tmp)

    (* Wire keyboard navigation — listener 7: document keydown *)
    val kd_arr = $A.alloc<byte>(7)
    val () = $A.set<byte>(kd_arr, 0, int2byte0(107)) (* k *)
    val () = $A.set<byte>(kd_arr, 1, int2byte0(101)) (* e *)
    val () = $A.set<byte>(kd_arr, 2, int2byte0(121)) (* y *)
    val () = $A.set<byte>(kd_arr, 3, int2byte0(100)) (* d *)
    val () = $A.set<byte>(kd_arr, 4, int2byte0(111)) (* o *)
    val () = $A.set<byte>(kd_arr, 5, int2byte0(119)) (* w *)
    val () = $A.set<byte>(kd_arr, 6, int2byte0(110)) (* n *)
    val @(kd_f, kd_b) = $A.freeze<byte>(kd_arr)
    val () = $EV.listen_document(kd_b, 7, 7,
      lam(payload_len: int): int =>
        if payload_len <= 0 then 0
        else let
          (* Keydown payload: 1 byte key_len, key bytes, 1 byte flags *)
          val payload_sz = $AR.checked_arr_size(payload_len)
          val payload = $EV.get_payload(payload_sz)
          val key_len = byte2int0($A.get<byte>(payload, 0))
        in
          (* ArrowRight = 10 bytes, ArrowLeft = 9 bytes, Space = 1 byte " " *)
          if key_len = 10 then let
            (* Check for "ArrowRight" *)
            val b1 = byte2int0($A.get<byte>(payload, $AR.checked_idx(1, payload_sz)))
            val b2 = byte2int0($A.get<byte>(payload, $AR.checked_idx(2, payload_sz)))
          in
            if b1 = 65 then
              if b2 = 114 then let
                (* ArrowRight → next page *)
                val () = $A.free<byte>(payload)
                val cur = $ST.stash_get_int(21)
              in _go_to_page(cur + 1); 0 end
              else let val () = $A.free<byte>(payload) in 0 end
            else let val () = $A.free<byte>(payload) in 0 end
          end
          else if key_len = 9 then let
            (* Check for "ArrowLeft" *)
            val b1 = byte2int0($A.get<byte>(payload, $AR.checked_idx(1, payload_sz)))
            val b2 = byte2int0($A.get<byte>(payload, $AR.checked_idx(2, payload_sz)))
          in
            if b1 = 65 then
              if b2 = 114 then let
                (* ArrowLeft → prev page *)
                val () = $A.free<byte>(payload)
                val cur = $ST.stash_get_int(21)
              in _go_to_page(cur - 1); 0 end
              else let val () = $A.free<byte>(payload) in 0 end
            else let val () = $A.free<byte>(payload) in 0 end
          end
          else if key_len = 1 then let
            val b1 = byte2int0($A.get<byte>(payload, $AR.checked_idx(1, payload_sz)))
          in
            if b1 = 32 then let
              (* Space → next page *)
              val () = $A.free<byte>(payload)
              val cur = $ST.stash_get_int(21)
            in _go_to_page(cur + 1); 0 end
            else let val () = $A.free<byte>(payload) in 0 end
          end
          else let val () = $A.free<byte>(payload) in 0 end
        end)
    val () = $A.drop<byte>(kd_f, kd_b)
    val kd_tmp = $A.thaw<byte>(kd_f)
    val () = $A.free<byte>(kd_tmp)

    (* Wire settings gear button click — listener 8: toggle settings panel *)
    val sg_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(sg_narr, 0, int2byte0(113)) (* q *)
    val () = $A.set<byte>(sg_narr, 1, int2byte0(115)) (* s *)
    val () = $A.set<byte>(sg_narr, 2, int2byte0(101)) (* e *)
    val () = $A.set<byte>(sg_narr, 3, int2byte0(116)) (* t *)
    val @(sg_nf, sg_nb) = $A.freeze<byte>(sg_narr)
    val ck8_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck8_arr, 0, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck8_arr, 1, int2byte0(108)) (* l *)
    val () = $A.set<byte>(ck8_arr, 2, int2byte0(105)) (* i *)
    val () = $A.set<byte>(ck8_arr, 3, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck8_arr, 4, int2byte0(107)) (* k *)
    val @(ck8_f, ck8_b) = $A.freeze<byte>(ck8_arr)
    val () = $EV.listen(sg_nb, 4, ck8_b, 5, 8,
      lam(_payload_len: int): int => let
        var sp_c = @[char][4]('q', 's', 'p', 'n')
        val sp_id = $W.Generated($S.text_of_chars(sp_c, 4), 4)
        val () = _apply_diff($W.SetHidden(sp_id, 0))
      in 0 end)
    val () = $A.drop<byte>(sg_nf, sg_nb)
    val sg_ntmp = $A.thaw<byte>(sg_nf)
    val () = $A.free<byte>(sg_ntmp)
    val () = $A.drop<byte>(ck8_f, ck8_b)
    val ck8_tmp = $A.thaw<byte>(ck8_f)
    val () = $A.free<byte>(ck8_tmp)

    (* Wire A- button click — listener 9: decrease font size *)
    val am_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(am_narr, 0, int2byte0(113)) (* q *)
    val () = $A.set<byte>(am_narr, 1, int2byte0(102)) (* f *)
    val () = $A.set<byte>(am_narr, 2, int2byte0(115)) (* s *)
    val () = $A.set<byte>(am_narr, 3, int2byte0(109)) (* m *)
    val @(am_nf, am_nb) = $A.freeze<byte>(am_narr)
    val ck9_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck9_arr, 0, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck9_arr, 1, int2byte0(108)) (* l *)
    val () = $A.set<byte>(ck9_arr, 2, int2byte0(105)) (* i *)
    val () = $A.set<byte>(ck9_arr, 3, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck9_arr, 4, int2byte0(107)) (* k *)
    val @(ck9_f, ck9_b) = $A.freeze<byte>(ck9_arr)
    val () = $EV.listen(am_nb, 4, ck9_b, 5, 9,
      lam(_payload_len: int): int => let
        val cur = $ST.stash_get_int(25)
        val next = cur - 2
      in
        if next >= 8 then let
          val () = _apply_font_size(next)
          val () = _save_font_size()
          val () = _measure_pagination()
        in 0 end
        else 0
      end)
    val () = $A.drop<byte>(am_nf, am_nb)
    val am_ntmp = $A.thaw<byte>(am_nf)
    val () = $A.free<byte>(am_ntmp)
    val () = $A.drop<byte>(ck9_f, ck9_b)
    val ck9_tmp = $A.thaw<byte>(ck9_f)
    val () = $A.free<byte>(ck9_tmp)

    (* Wire A+ button click — listener 10: increase font size *)
    val ap_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(ap_narr, 0, int2byte0(113)) (* q *)
    val () = $A.set<byte>(ap_narr, 1, int2byte0(102)) (* f *)
    val () = $A.set<byte>(ap_narr, 2, int2byte0(115)) (* s *)
    val () = $A.set<byte>(ap_narr, 3, int2byte0(112)) (* p *)
    val @(ap_nf, ap_nb) = $A.freeze<byte>(ap_narr)
    val ck10_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck10_arr, 0, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck10_arr, 1, int2byte0(108)) (* l *)
    val () = $A.set<byte>(ck10_arr, 2, int2byte0(105)) (* i *)
    val () = $A.set<byte>(ck10_arr, 3, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck10_arr, 4, int2byte0(107)) (* k *)
    val @(ck10_f, ck10_b) = $A.freeze<byte>(ck10_arr)
    val () = $EV.listen(ap_nb, 4, ck10_b, 5, 10,
      lam(_payload_len: int): int => let
        val cur = $ST.stash_get_int(25)
        val next = cur + 2
      in
        if next <= 48 then let
          val () = _apply_font_size(next)
          val () = _save_font_size()
          val () = _measure_pagination()
        in 0 end
        else 0
      end)
    val () = $A.drop<byte>(ap_nf, ap_nb)
    val ap_ntmp = $A.thaw<byte>(ap_nf)
    val () = $A.free<byte>(ap_ntmp)
    val () = $A.drop<byte>(ck10_f, ck10_b)
    val ck10_tmp = $A.thaw<byte>(ck10_f)
    val () = $A.free<byte>(ck10_tmp)

    (* Wire close button click — listener 11: hide settings panel *)
    val sc_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(sc_narr, 0, int2byte0(113)) (* q *)
    val () = $A.set<byte>(sc_narr, 1, int2byte0(115)) (* s *)
    val () = $A.set<byte>(sc_narr, 2, int2byte0(99))  (* c *)
    val () = $A.set<byte>(sc_narr, 3, int2byte0(108)) (* l *)
    val @(sc_nf, sc_nb) = $A.freeze<byte>(sc_narr)
    val ck11_arr = $A.alloc<byte>(5)
    val () = $A.set<byte>(ck11_arr, 0, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck11_arr, 1, int2byte0(108)) (* l *)
    val () = $A.set<byte>(ck11_arr, 2, int2byte0(105)) (* i *)
    val () = $A.set<byte>(ck11_arr, 3, int2byte0(99))  (* c *)
    val () = $A.set<byte>(ck11_arr, 4, int2byte0(107)) (* k *)
    val @(ck11_f, ck11_b) = $A.freeze<byte>(ck11_arr)
    val () = $EV.listen(sc_nb, 4, ck11_b, 5, 11,
      lam(_payload_len: int): int => let
        var sp_c = @[char][4]('q', 's', 'p', 'n')
        val sp_id = $W.Generated($S.text_of_chars(sp_c, 4), 4)
        val () = _apply_diff($W.SetHidden(sp_id, 1))
      in 0 end)
    val () = $A.drop<byte>(sc_nf, sc_nb)
    val sc_ntmp = $A.thaw<byte>(sc_nf)
    val () = $A.free<byte>(sc_ntmp)
    val () = $A.drop<byte>(ck11_f, ck11_b)
    val ck11_tmp = $A.thaw<byte>(ck11_f)
    val () = $A.free<byte>(ck11_tmp)

    val nid = $D.get_next_id(doc)
    val () = $ST.stash_set_int(20, nid)
    val () = $D.destroy(doc)
    (* Restore font size and saved book from IDB *)
    val () = _restore_font_size()
    val () = _restore_from_idb()
  in end
  else let
    val nid = $D.get_next_id(doc)
    val () = $ST.stash_set_int(20, nid)
    val () = $D.destroy(doc)
  in end
end
