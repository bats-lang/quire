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
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/dom as D
#use wasm.bats-packages.dev/file-input as FI
#use widget as W

staload "book.sats"
staload "pages.sats"
staload "theme.sats"
staload "epub_xml.sats"
staload "reader.sats"
staload "book_cards.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload SC = "wasm.bats-packages.dev/bridge/src/scroll.sats"

(* EPUB XML helpers are in epub_xml module *)

(* ============================================================
   App entry point
   ============================================================ *)

(* Whether a tap on the content hid the reader's nav bar *)
val _nav_hidden = ref<bool>(false)

(* A childless element with id t[0, 4) *)
fn _el (t: $A.text(4), top: $W.html_top, cls: $W.class_opt, hidden: bool): $W.widget =
  $W.Element($W.ElementNode($W.Generated(t, 4), top, cls, hidden, $W.NoneInt(), $W.NoneStr(), $W.WNil()))

implement main0 () = let

  val doc = $D.create_document($A.text_lit("div"), 3, $A.text_lit("bats-root"), 9)

  val root = $W.Element($W.ElementNode($W.Root(), $W.Normal($W.Div()), $W.NoClass(), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))

  val si_id = $W.Generated($A.text_lit("qcss"), 4)
  val @(css_t, css_l) = theme_css()
  val @(root, css_diffs) = $W.inject_css(root, si_id, css_t, css_l)
  val () = $D.apply_list(doc, css_diffs)

  (* Font size style element — dynamic CSS for font size override *)
  val fs_id = $W.Generated($A.text_lit("qfss"), 4)
  val @(root, fs_diffs) = $W.inject_css(root, fs_id, $A.text_lit(".caf{font-size:16px}"), 20)
  val () = $D.apply_list(doc, fs_diffs)
  (* The tree is not read again: every later change is a diff by id *)
  val () = $W.widget_free(root)

  (* Each element is built with its class and hidden flag, and added under
     its parent by id; apply consumes the element *)
  (* Library list *)
  val () = $D.apply(doc, $W.AddChild($W.Root(),
    _el($A.text_lit("qllc"), $W.Normal($W.Div()), $W.ClassIdx(cls_library_list()), false)))
  (* App title *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qllc"), 4),
    _el($A.text_lit("qatl"), $W.Normal($W.H1()), $W.NoClass(), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qatl"), 4), $A.text_lit("Quire"), 5))
  (* Reader view — hidden initially *)
  val () = $D.apply(doc, $W.AddChild($W.Root(),
    _el($A.text_lit("qrvw"), $W.Normal($W.Div()), $W.ClassIdx(cls_reader_view()), true)))
  (* Nav bar inside reader view *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrvw"), 4),
    _el($A.text_lit("qrnv"), $W.Normal($W.Div()), $W.ClassIdx(cls_nav_bar()), false)))
  (* Back button inside nav bar: U+2190 = ← = 0xE2 0x86 0x90 *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrnv"), 4),
    _el($A.text_lit("qbbk"), $W.Normal($W.Div()), $W.ClassIdx(cls_back_btn()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qbbk"), 4), $A.text_lit("\xE2\x86\x90"), 3))
  (* Chapter title *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrnv"), 4),
    _el($A.text_lit("qcht"), $W.Normal($W.Div()), $W.ClassIdx(cls_chapter_title()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qcht"), 4), $A.text_lit("Chapter 1"), 9))
  (* Page info *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrnv"), 4),
    _el($A.text_lit("qpgi"), $W.Normal($W.Div()), $W.ClassIdx(cls_page_info()), false)))
  (* Prev button — U+2039 = ‹ = 0xE2 0x80 0xB9 *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrnv"), 4),
    _el($A.text_lit("qprv"), $W.Normal($W.Div()), $W.ClassIdx(cls_nav_button()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qprv"), 4), $A.text_lit("\xE2\x80\xB9"), 3))
  (* Next button — U+203A = › = 0xE2 0x80 0xBA *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrnv"), 4),
    _el($A.text_lit("qnxt"), $W.Normal($W.Div()), $W.ClassIdx(cls_nav_button()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qnxt"), 4), $A.text_lit("\xE2\x80\xBA"), 3))
  (* Settings gear button — U+2699 = ⚙ = 0xE2 0x9A 0x99 *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrnv"), 4),
    _el($A.text_lit("qset"), $W.Normal($W.Div()), $W.ClassIdx(cls_nav_button()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qset"), 4), $A.text_lit("\xE2\x9A\x99"), 3))
  (* Content area inside reader view *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrvw"), 4),
    _el($A.text_lit("qcnt"), $W.Normal($W.Div()), $W.ClassIdx(cls_content_area()), false)))
  (* Click zones — transparent overlays for page navigation *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrvw"), 4),
    _el($A.text_lit("qczl"), $W.Normal($W.Div()), $W.ClassIdx(cls_zone_left()), false)))
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrvw"), 4),
    _el($A.text_lit("qczr"), $W.Normal($W.Div()), $W.ClassIdx(cls_zone_right()), false)))
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qrvw"), 4),
    _el($A.text_lit("qczc"), $W.Normal($W.Div()), $W.ClassIdx(cls_zone_center()), false)))
  (* Settings panel — hidden overlay *)
  val () = $D.apply(doc, $W.AddChild($W.Root(),
    _el($A.text_lit("qspn"), $W.Normal($W.Div()), $W.ClassIdx(cls_settings_panel()), true)))
  (* "Font Size" label *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qspn"), 4),
    _el($A.text_lit("qsfl"), $W.Normal($W.Div()), $W.NoClass(), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qsfl"), 4), $A.text_lit("Font Size"), 9))
  (* A- button (decrease font) *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qspn"), 4),
    _el($A.text_lit("qfsm"), $W.Normal($W.Div()), $W.ClassIdx(cls_settings_btn()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qfsm"), 4), $A.text_lit("A-"), 2))
  (* A+ button (increase font) *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qspn"), 4),
    _el($A.text_lit("qfsp"), $W.Normal($W.Div()), $W.ClassIdx(cls_settings_btn()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qfsp"), 4), $A.text_lit("A+"), 2))
  (* Close button *)
  val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qspn"), 4),
    _el($A.text_lit("qscl"), $W.Normal($W.Div()), $W.ClassIdx(cls_settings_btn()), false)))
  val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qscl"), 4), $A.text_lit("Close"), 5))

in
  (* The library starts empty: books are imported into it *)
  let
    (* Library toolbar — above empty state message *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qllc"), 4),
      _el($A.text_lit("qltb"), $W.Normal($W.Div()), $W.ClassIdx(cls_lib_toolbar()), false)))
    (* App title in toolbar *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qltb"), 4),
      _el($A.text_lit("qatl"), $W.Normal($W.Div()), $W.ClassIdx(cls_app_title()), false)))
    val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qatl"), 4), $A.text_lit("Quire"), 5))

    (* Empty state message *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qllc"), 4),
      _el($A.text_lit("qelb"), $W.Normal($W.Div()), $W.ClassIdx(cls_empty_lib()), false)))
    val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qelb"), 4), $A.text_lit("Import an EPUB file to start reading ..."), 40))

    (* Import button in toolbar *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qltb"), 4),
      _el($A.text_lit("qibn"), $W.Normal($W.Div()), $W.ClassIdx(cls_import_btn()), false)))
    val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qibn"), 4), $A.text_lit("Import EPUB"), 11))
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qibn"), 4),
      _el($A.text_lit("qfin"), $W.Void($W.HtmlInput($W.InputFile(), $W.NoneStr(), $W.NoneStr(), false, false, false)), $W.NoClass(), false)))

    (* Sort button in toolbar *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qltb"), 4),
      _el($A.text_lit("qsrt"), $W.Normal($W.Div()), $W.NoClass(), false)))
    val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qsrt"), 4), $A.text_lit("Sort"), 4))

    (* Context menu overlay — hidden initially *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qllc"), 4),
      _el($A.text_lit("qctx"), $W.Normal($W.Div()), $W.ClassIdx(cls_ctx_overlay()), true)))
    (* Context menu box *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qctx"), 4),
      _el($A.text_lit("qcmb"), $W.Normal($W.Div()), $W.ClassIdx(cls_ctx_menu()), false)))
    (* Archive button *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qcmb"), 4),
      _el($A.text_lit("qarb"), $W.Normal($W.Div()), $W.NoClass(), false)))
    val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qarb"), 4), $A.text_lit("Archive"), 7))
    (* Hide button *)
    val () = $D.apply(doc, $W.AddChild($W.Generated($A.text_lit("qcmb"), 4),
      _el($A.text_lit("qhib"), $W.Normal($W.Div()), $W.NoClass(), false)))
    val () = $D.apply(doc, $W.set_text_content($W.Generated($A.text_lit("qhib"), 4), $A.text_lit("Hide"), 4))

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
      lam(_payload_len: $EV.event_payload): int => let
        (* Show importing indicator *)
        val elb_id = $W.Generated($A.text_lit("qelb"), 4)
        val () = apply_diff($W.SetHidden(elb_id, false))
        val () = apply_diff($W.SetTextContent(elb_id, $A.text_lit("Importing EPUB"), 14))
        val fa = $A.alloc<byte>(4)
        val () = $A.set<byte>(fa, 0, int2byte0(113))
        val () = $A.set<byte>(fa, 1, int2byte0(102))
        val () = $A.set<byte>(fa, 2, int2byte0(105))
        val () = $A.set<byte>(fa, 3, int2byte0(110))
        val @(ff, fb) = $A.freeze<byte>(fa)
        val p = import_epub(fb, 4)
        val p2 = $P.and_then<int><int>(p, lam(result) =>
          if result = 0 then let
            (* Import succeeded — book card already created by _add_book_card *)
            val () = save_epub_to_idb()
            val () = save_metadata_to_idb()
          in $P.ret<int>(0) end
          else let
            val cnt2_id = $W.Generated($A.text_lit("qcnt"), 4)
          in
            if result = ~1 then let
              val () = apply_diff($W.SetTextContent(cnt2_id, $A.text_lit("ERR1"), 4))
            in $P.ret<int>(result) end
            else if result = ~2 then let
              val () = apply_diff($W.SetTextContent(cnt2_id, $A.text_lit("ERR2"), 4))
            in $P.ret<int>(result) end
            else if result = ~3 then let
              val () = apply_diff($W.SetTextContent(cnt2_id, $A.text_lit("ERR3"), 4))
            in $P.ret<int>(result) end
            else if result = ~4 then let
              val () = apply_diff($W.SetTextContent(cnt2_id, $A.text_lit("ERR4"), 4))
            in $P.ret<int>(result) end
            else if result = ~5 then let
              val () = apply_diff($W.SetTextContent(cnt2_id, $A.text_lit("ERR5"), 4))
            in $P.ret<int>(result) end
            else let
              val () = apply_diff($W.SetTextContent(cnt2_id, $A.text_lit("ERRX"), 4))
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

    (* Wire Archive button click — listener 12 *)
    val ab_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(ab_narr, 0, int2byte0(113))
    val () = $A.set<byte>(ab_narr, 1, int2byte0(97))
    val () = $A.set<byte>(ab_narr, 2, int2byte0(114))
    val () = $A.set<byte>(ab_narr, 3, int2byte0(98))
    val @(ab_nf, ab_nb) = $A.freeze<byte>(ab_narr)
    var abck_c = @[char][5]('c', 'l', 'i', 'c', 'k')
    val abck_arr = $S.from_char_array(abck_c, 5)
    val @(abck_f, abck_b) = $A.freeze<byte>(abck_arr)
    val () = $EV.listen(ab_nb, 4, abck_b, 5, 12,
      lam(_pl: $EV.event_payload): int => let
        (* Hide the card and close context menu *)
        val card_id = $W.Generated($A.text_lit("qbc00"), 5)
        val () = apply_diff($W.SetHidden(card_id, true))
        val ctx_id = $W.Generated($A.text_lit("qctx"), 4)
        val () = apply_diff($W.SetHidden(ctx_id, true))
      in 0 end)
    val () = $A.drop<byte>(ab_nf, ab_nb)
    val () = $A.free<byte>($A.thaw<byte>(ab_nf))
    val () = $A.drop<byte>(abck_f, abck_b)
    val () = $A.free<byte>($A.thaw<byte>(abck_f))

    (* Wire Hide button click — listener 13 *)
    val hb_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(hb_narr, 0, int2byte0(113))
    val () = $A.set<byte>(hb_narr, 1, int2byte0(104))
    val () = $A.set<byte>(hb_narr, 2, int2byte0(105))
    val () = $A.set<byte>(hb_narr, 3, int2byte0(98))
    val @(hb_nf, hb_nb) = $A.freeze<byte>(hb_narr)
    var hbck_c = @[char][5]('c', 'l', 'i', 'c', 'k')
    val hbck_arr = $S.from_char_array(hbck_c, 5)
    val @(hbck_f, hbck_b) = $A.freeze<byte>(hbck_arr)
    val () = $EV.listen(hb_nb, 4, hbck_b, 5, 13,
      lam(_pl: $EV.event_payload): int => let
        (* Hide the card and close context menu *)
        val card_id = $W.Generated($A.text_lit("qbc00"), 5)
        val () = apply_diff($W.SetHidden(card_id, true))
        val ctx_id = $W.Generated($A.text_lit("qctx"), 4)
        val () = apply_diff($W.SetHidden(ctx_id, true))
      in 0 end)
    val () = $A.drop<byte>(hb_nf, hb_nb)
    val () = $A.free<byte>($A.thaw<byte>(hb_nf))
    val () = $A.drop<byte>(hbck_f, hbck_b)
    val () = $A.free<byte>($A.thaw<byte>(hbck_f))

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
      lam(_payload_len: $EV.event_payload): int => let
        (* Show library, hide reader *)
        val ll2_id = $W.Generated($A.text_lit("qllc"), 4)
        val rv2_id = $W.Generated($A.text_lit("qrvw"), 4)
        val () = apply_diff($W.SetHidden(ll2_id, false))
        val () = apply_diff($W.SetHidden(rv2_id, true))
        (* The book is closed: its pages' arenas are released *)
        val () = window_close()
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
      lam(_payload_len: $EV.event_payload): int => let
        val () = page_prev()
      in 0 end)
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
      lam(_payload_len: $EV.event_payload): int => let
        val () = page_next()
      in 0 end)
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
      lam(_payload_len: $EV.event_payload): int => let
        val () = page_prev()
      in 0 end)
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
      lam(_payload_len: $EV.event_payload): int => let
        val () = page_next()
      in 0 end)
    val () = $A.drop<byte>(zr_nf, zr_nb)
    val zr_ntmp = $A.thaw<byte>(zr_nf)
    val () = $A.free<byte>(zr_ntmp)
    val () = $A.drop<byte>(ck5_f, ck5_b)
    val ck5_tmp = $A.thaw<byte>(ck5_f)
    val () = $A.free<byte>(ck5_tmp)

    (* Wire center click zone — listener 14: toggle chrome *)
    val zc_narr = $A.alloc<byte>(4)
    val () = $A.set<byte>(zc_narr, 0, int2byte0(113))  (* q *)
    val () = $A.set<byte>(zc_narr, 1, int2byte0(99))   (* c *)
    val () = $A.set<byte>(zc_narr, 2, int2byte0(122))  (* z *)
    val () = $A.set<byte>(zc_narr, 3, int2byte0(99))   (* c *)
    val @(zc_nf, zc_nb) = $A.freeze<byte>(zc_narr)
    var zcck_c = @[char][5]('c', 'l', 'i', 'c', 'k')
    val zcck_arr = $S.from_char_array(zcck_c, 5)
    val @(zcck_f, zcck_b) = $A.freeze<byte>(zcck_arr)
    val () = $EV.listen(zc_nb, 4, zcck_b, 5, 14,
      lam(_pl: $EV.event_payload): int => let
        (* Toggle nav bar visibility *)
        val nv_id = $W.Generated($A.text_lit("qrnv"), 4)
        val hidden = !_nav_hidden
      in
        if hidden then let
          val () = !_nav_hidden := false
          val () = apply_diff($W.SetHidden(nv_id, false))
        in 0 end
        else let
          val () = !_nav_hidden := true
          val () = apply_diff($W.SetHidden(nv_id, true))
        in 0 end
      end)
    val () = $A.drop<byte>(zc_nf, zc_nb)
    val () = $A.free<byte>($A.thaw<byte>(zc_nf))
    val () = $A.drop<byte>(zcck_f, zcck_b)
    val () = $A.free<byte>($A.thaw<byte>(zcck_f))

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
      lam(payload_h: $EV.event_payload): int =>
        case+ take_blob(payload_h) of
        | ~NoBlobBytes() => 0
        | ~BlobBytes(payload, payload_sz) => let
          val key_len = byte2int0($A.get<byte>(payload, 0))
        in
          if payload_sz <= 2 then let val () = $A.free<byte>(payload) in 0 end
          else let
          (* ArrowRight = 10 bytes, ArrowLeft = 9 bytes, Space = 1 byte " " *)
          val b1 = byte2int0($A.get<byte>(payload, 1))
          val b2 = byte2int0($A.get<byte>(payload, 2))
        in
          if key_len = 10 then
            (* Check for "ArrowRight" *)
            if b1 = 65 then
              if b2 = 114 then let
                (* ArrowRight → next page *)
                val () = $A.free<byte>(payload)
                val () = page_next()
              in 0 end
              else let val () = $A.free<byte>(payload) in 0 end
            else let val () = $A.free<byte>(payload) in 0 end
          else if key_len = 9 then
            (* Check for "ArrowLeft" *)
            if b1 = 65 then
              if b2 = 114 then let
                (* ArrowLeft → prev page *)
                val () = $A.free<byte>(payload)
                val () = page_prev()
              in 0 end
              else let val () = $A.free<byte>(payload) in 0 end
            else let val () = $A.free<byte>(payload) in 0 end
          else if key_len = 1 then
            if b1 = 32 then let
              (* Space → next page *)
              val () = $A.free<byte>(payload)
              val () = page_next()
            in 0 end
            else let val () = $A.free<byte>(payload) in 0 end
          else let val () = $A.free<byte>(payload) in 0 end
          end
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
      lam(_payload_len: $EV.event_payload): int => let
        val sp_id = $W.Generated($A.text_lit("qspn"), 4)
        val () = apply_diff($W.SetHidden(sp_id, false))
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
      lam(_payload_len: $EV.event_payload): int => let
        val cur = font_get()
      in
        if cur >= 10 then let
          val () = apply_font_size(cur - 2)
          val () = save_font_size()
          val () = measure_pagination()
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
      lam(_payload_len: $EV.event_payload): int => let
        val cur = font_get()
      in
        if cur <= 46 then let
          val () = apply_font_size(cur + 2)
          val () = save_font_size()
          val () = measure_pagination()
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
      lam(_payload_len: $EV.event_payload): int => let
        val sp_id = $W.Generated($A.text_lit("qspn"), 4)
        val () = apply_diff($W.SetHidden(sp_id, true))
      in 0 end)
    val () = $A.drop<byte>(sc_nf, sc_nb)
    val sc_ntmp = $A.thaw<byte>(sc_nf)
    val () = $A.free<byte>(sc_ntmp)
    val () = $A.drop<byte>(ck11_f, ck11_b)
    val ck11_tmp = $A.thaw<byte>(ck11_f)
    val () = $A.free<byte>(ck11_tmp)

    val () = $D.destroy(doc)
    (* Restore font size and saved book from IDB *)
    val () = restore_font_size()
    val () = restore_from_idb()
  in end
end
