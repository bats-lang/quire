(* book_cards -- EPUB import pipeline *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use xml-tree as X
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/dom as D
#use wasm.bats-packages.dev/file-input as FI
#use widget as W

staload "theme.sats"
staload "book.sats"
staload "epub_xml.sats"
staload "reader.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"

(* Show the span of data as wid's text; false when there is none, or it
   is empty or 256 bytes or more (the book's title or author, from its
   OPF: a longer one is not shown). *)
fn _set_meta_text
  {lb:agz}{nb:pos}
  (data: !$A.borrow(byte, lb, nb), len: int nb,
   wid: $W.widget_id, span: xspan(nb)): bool =
  case+ span of
  | xspan_none() => false
  | xspan_at(off, n) =>
    if n <= 0 then false
    else if n >= 256 then false
    else let
      val tbuf = $A.alloc<byte>(n)
      val () = $S.copy_from_borrow(data, off, len, tbuf, 0, n, n)
      val txt = arr_to_text(tbuf, n)
      val () = $A.free<byte>(tbuf)
      val () = apply_diff($W.SetTextContent(wid, txt, n))
    in true end

(* Book cards are numbered from 0 *)
val _cards = ref<[n:nat] int n>(0)

fn _add_book_card
  {lb:agz}{nb:pos}
  (data: !$A.borrow(byte, lb, nb), len: int nb,
   title: xspan(nb), author: xspan(nb)): void = let
  (* Hide empty message and create card *)
  var elb_c = @[char][4]('q', 'e', 'l', 'b')
  val elb_id = $W.Generated($S.text_of_chars(elb_c, 4), 4)
  val () = apply_diff($W.SetHidden(elb_id, true))
  val idx = !_cards
  val () = !_cards := idx + 1
  val card_id = num_wid("qbc", idx, 2)
  var ll_c = @[char][4]('q', 'l', 'l', 'c')
  val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
  val card = $W.Element($W.ElementNode(card_id,
    $W.Normal($W.Div()), $W.ClassIdx(cls_book_card()), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(card, cls_diff) = $W.set_class(card, cls_book_card())
  val () = apply_diff($W.AddChild(ll_id, card))
  val () = apply_diff(cls_diff)
  (* Title div *)
  val tc_id = num_wid("qtc", idx, 2)
  val td = $W.Element($W.ElementNode(tc_id,
    $W.Normal($W.Div()), $W.ClassIdx(cls_book_title()), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(td, cls_d) = $W.set_class(td, cls_book_title())
  val () = apply_diff($W.AddChild(card_id, td))
  val () = apply_diff(cls_d)
  (* Set title — try metadata, fall back to "Imported Book" *)
  val () = (if _set_meta_text(data, len, tc_id, title) then ()
  else let
    var fb = @[char][13]('I', 'm', 'p', 'o', 'r', 't', 'e', 'd', ' ', 'B', 'o', 'o', 'k')
  in apply_diff($W.SetTextContent(tc_id, $S.text_of_chars(fb, 13), 13)) end)
  (* Author div *)
  val ac_id = num_wid("qac", idx, 2)
  val ad = $W.Element($W.ElementNode(ac_id,
    $W.Normal($W.Div()), $W.ClassIdx(cls_book_author()), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(ad, cls_a) = $W.set_class(ad, cls_book_author())
  val () = apply_diff($W.AddChild(card_id, ad))
  val () = apply_diff(cls_a)
  val () = (if _set_meta_text(data, len, ac_id, author) then ()
  else let
    var fb = @[char][14]('U', 'n', 'k', 'n', 'o', 'w', 'n', ' ', 'A', 'u', 't', 'h', 'o', 'r')
  in apply_diff($W.SetTextContent(ac_id, $S.text_of_chars(fb, 14), 14)) end)
  (* Status label — "New" for freshly imported books *)
  val sc_id = num_wid("qst", idx, 2)
  val sd = $W.Element($W.ElementNode(sc_id,
    $W.Normal($W.Div()), $W.ClassIdx(cls_book_author()), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(sd, cls_s) = $W.set_class(sd, cls_book_author())
  val () = apply_diff($W.AddChild(card_id, sd))
  val () = apply_diff(cls_s)
  var nw = @[char][3]('N', 'e', 'w')
  val () = apply_diff($W.SetTextContent(sc_id, $S.text_of_chars(nw, 3), 3))
  (* Wire click handler: card click opens reader *)
  val @(ci_arr, ci_len) = num_id("qbc", idx, 2)
  val @(ci_f, ci_b) = $A.freeze<byte>(ci_arr)
  var ck_c = @[char][5]('c', 'l', 'i', 'c', 'k')
  val ck_arr = $S.from_char_array(ck_c, 5)
  val @(ck_f, ck_b) = $A.freeze<byte>(ck_arr)
  val () = $EV.listen(ci_b, ci_len, ck_b, 5, 100,
    lam(_pl: $EV.event_payload): int => let
      var ll_c = @[char][4]('q', 'l', 'l', 'c')
      val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
      var rv_c = @[char][4]('q', 'r', 'v', 'w')
      val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
      val () = apply_diff($W.SetHidden(ll_id, true))
      val () = apply_diff($W.SetHidden(rv_id, false))
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
  val () = $EV.listen(cm_b, 5, ct_b, 11, 15,
    lam(_pl: $EV.event_payload): int => let
      val () = $EV.prevent_default()
      (* Show context menu overlay *)
      var ctx_c = @[char][4]('q', 'c', 't', 'x')
      val ctx_id = $W.Generated($S.text_of_chars(ctx_c, 4), 4)
      val () = apply_diff($W.SetHidden(ctx_id, false))
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
  $P.and_then<Int><int>(p, lam(opened) =>
  case+ $FI.claim(opened) of
  | ~$R.none() => $P.ret<int>(~1)
  | ~$R.some(file_handle) => let
    (* The picked file's size, checked here once *)
    val file_size = $FI.size(file_handle)
  in
    if file_size <= 0 then let
      val () = $FI.close(file_handle)
    in $P.ret<int>(~1) end
    else let
      var _cont_chars = @[char][22]('M', 'E', 'T', 'A', '-', 'I', 'N', 'F', '/', 'c', 'o', 'n', 't', 'a', 'i', 'n', 'e', 'r', '.', 'x', 'm', 'l')
      val _cont_arr = $S.from_char_array(_cont_chars, 22)
      val @(_cont_f, _cont_b) = $A.freeze<byte>(_cont_arr)
      val cont = zip_read(file_handle, file_size, _cont_b, 22)
      val () = $A.drop<byte>(_cont_f, _cont_b)
      val () = $A.free<byte>($A.thaw<byte>(_cont_f))
    in
      case+ cont of
      | ~ZipMissing() => let
        val () = $FI.close(file_handle)
      in $P.ret<int>(~3) end
      | ~ZipGot(car, comp_buf, csz, method, _, _, _) => let
        val @(cf, cb) = $A.freeze<byte>(comp_buf)
        val dc_p = $DC.decompress(cb, csz, method)
        val () = $A.drop<byte>(cf, cb)
        val () = piece_free(car, $A.thaw<byte>(cf))
        val dc_p = $P.vow(dc_p)
      in
        (* Stage 2: parse container.xml, read the OPF it names *)
        $P.and_then<Int><int>(dc_p, lam(dc_handle) => let
          val dc = take_content(dc_handle)
        in
          case+ dc of
          | ~NoContentBytes() => let
            val () = $FI.close(file_handle)
          in $P.ret<int>(~5) end
          | ~ContentBytes(dar, dc_buf, dc_sz) => let
            val @(dc_frozen, dc_borrow) = $A.freeze<byte>(dc_buf)
            val nodes = $X.parse_document(dc_borrow, dc_sz)
            val opf_path = walk_rootfile_nodes(dc_borrow, nodes)
          in
            case+ opf_path of
            | xspan_none() => let
              val () = $X.free_nodes(nodes)
              val () = $A.drop<byte>(dc_frozen, dc_borrow)
              val () = piece_free(dar, $A.thaw<byte>(dc_frozen))
              val () = $FI.close(file_handle)
            in $P.ret<int>(~6) end
            | xspan_at(opf_off, opf_len) =>
            (* The OPF's path names a zip entry, so it is shorter than
               65536 bytes (a zip name's limit) *)
            if opf_len <= 0 then let
              val () = $X.free_nodes(nodes)
              val () = $A.drop<byte>(dc_frozen, dc_borrow)
              val () = piece_free(dar, $A.thaw<byte>(dc_frozen))
              val () = $FI.close(file_handle)
            in $P.ret<int>(~6) end
            else if opf_len >= 65536 then let
              val () = $X.free_nodes(nodes)
              val () = $A.drop<byte>(dc_frozen, dc_borrow)
              val () = piece_free(dar, $A.thaw<byte>(dc_frozen))
              val () = $FI.close(file_handle)
            in $P.ret<int>(~6) end
            else let
              val opf_path_buf = $A.alloc<byte>(opf_len)
              val () = $S.copy_from_borrow(dc_borrow, opf_off, dc_sz,
                        opf_path_buf, 0, opf_len, opf_len)
              val () = $X.free_nodes(nodes)
              val () = $A.drop<byte>(dc_frozen, dc_borrow)
              val () = piece_free(dar, $A.thaw<byte>(dc_frozen))
              val @(opf_frozen, opf_borrow) = $A.freeze<byte>(opf_path_buf)
              val opf_entry = zip_read(file_handle, file_size, opf_borrow, opf_len)
              val () = $A.drop<byte>(opf_frozen, opf_borrow)
              val () = $A.free<byte>($A.thaw<byte>(opf_frozen))
            in
              case+ opf_entry of
              | ~ZipMissing() => $P.ret<int>(~7)
              | ~ZipGot(oar, opf_comp, opf_csz, opf_method, opf_doff, opf_name_off, opf_name_len) => let
                val @(ocf, ocb) = $A.freeze<byte>(opf_comp)
                val dc2_p = $DC.decompress(ocb, opf_csz, opf_method)
                val () = $A.drop<byte>(ocf, ocb)
                val () = piece_free(oar, $A.thaw<byte>(ocf))
                val dc2_p = $P.vow(dc2_p)
              in
                (* Stage 3: parse OPF metadata *)
                $P.and_then<Int><int>(dc2_p, lam(dc2_handle) => let
                  val dc2 = take_content(dc2_handle)
                in
                  case+ dc2 of
                  | ~NoContentBytes() => $P.ret<int>(~9)
                  | ~ContentBytes(par, opf_buf, dc2_sz) => let
                    val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
                    val opf_nodes = $X.parse_document(opf_b, dc2_sz)
                    val @(title, author) = walk_opf_metadata(opf_b, opf_nodes)

                    (* Create card with metadata *)
                    val () = _add_book_card(opf_b, dc2_sz, title, author)

                    val () = $X.free_nodes(opf_nodes)
                    val () = $A.drop<byte>(opf_f, opf_b)
                    val () = piece_free(par, $A.thaw<byte>(opf_f))

                    (* The open book, for chapter loading *)
                    val () = book_set(OpenBook(file_handle, file_size, opf_doff, opf_csz,
                               opf_method, opf_name_off, opf_name_len))
                  in $P.ret<int>(0) end
                end)
              end
            end
          end
        end)
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

