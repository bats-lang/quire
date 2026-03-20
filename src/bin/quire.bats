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

  (* App title *)
  var at_c = @[char][4]('q', 'a', 't', 'l')
  val at_id = $W.Generated($S.text_of_chars(at_c, 4), 4)
  val at = $W.Element($W.ElementNode(at_id, $W.Normal($W.H1()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(ll, at)
  val () = $D.apply(doc, diff)
  var qt = @[char][5]('Q', 'u', 'i', 'r', 'e')
  val () = $D.apply(doc, $W.set_text_content(at_id, $S.text_of_chars(qt, 5), 5))

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

    (* Library toolbar *)
    var tb_c = @[char][4]('q', 'l', 't', 'b')
    val tb_id = $W.Generated($S.text_of_chars(tb_c, 4), 4)
    val tb = $W.Element($W.ElementNode(tb_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ll, tb)
    val () = $D.apply(doc, diff)
    val @(_, diff) = $W.set_class(tb, cls_lib_toolbar())
    val () = $D.apply(doc, diff)

    (* Import button in toolbar *)
    var ib_c = @[char][4]('q', 'i', 'b', 'n')
    val ib_id = $W.Generated($S.text_of_chars(ib_c, 4), 4)
    val ib = $W.Element($W.ElementNode(ib_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(tb, ib)
    val () = $D.apply(doc, diff)
    val @(_, diff) = $W.set_class(ib, cls_import_btn())
    val () = $D.apply(doc, diff)
    var ie_c = @[char][11]('I', 'm', 'p', 'o', 'r', 't', ' ', 'E', 'P', 'U', 'B')
    val () = $D.apply(doc, $W.set_text_content(ib_id, $S.text_of_chars(ie_c, 11), 11))

    var fi_c = @[char][4]('q', 'f', 'i', 'n')
    val fi_id = $W.Generated($S.text_of_chars(fi_c, 4), 4)
    val fi = $W.Element($W.ElementNode(fi_id, $W.Void($W.HtmlInput($W.InputFile(), $W.NoneStr(), $W.NoneStr(), 0, 0, 0)), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ib, fi)
    val () = $D.apply(doc, diff)

    (* Sort button in toolbar *)
    var sr_c = @[char][4]('q', 's', 'r', 't')
    val sr_id = $W.Generated($S.text_of_chars(sr_c, 4), 4)
    val sr = $W.Element($W.ElementNode(sr_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(tb, sr)
    val () = $D.apply(doc, diff)
    var srt = @[char][4]('S', 'o', 'r', 't')
    val () = $D.apply(doc, $W.set_text_content(sr_id, $S.text_of_chars(srt, 4), 4))

    (* Context menu overlay — hidden initially *)
    var ctx_c = @[char][4]('q', 'c', 't', 'x')
    val ctx_id = $W.Generated($S.text_of_chars(ctx_c, 4), 4)
    val ctx = $W.Element($W.ElementNode(ctx_id, $W.Normal($W.Div()), ~1, 1, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ll, ctx)
    val () = $D.apply(doc, diff)
    val @(_, diff) = $W.set_class(ctx, cls_ctx_overlay())
    val () = $D.apply(doc, diff)
    (* Context menu box *)
    var cmb_c = @[char][4]('q', 'c', 'm', 'b')
    val cmb_id = $W.Generated($S.text_of_chars(cmb_c, 4), 4)
    val cmb = $W.Element($W.ElementNode(cmb_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(ctx, cmb)
    val () = $D.apply(doc, diff)
    val @(_, diff) = $W.set_class(cmb, cls_ctx_menu())
    val () = $D.apply(doc, diff)
    (* Archive button *)
    var ab_c = @[char][4]('q', 'a', 'r', 'b')
    val ab_id = $W.Generated($S.text_of_chars(ab_c, 4), 4)
    val ab = $W.Element($W.ElementNode(ab_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(cmb, ab)
    val () = $D.apply(doc, diff)
    var abt = @[char][7]('A', 'r', 'c', 'h', 'i', 'v', 'e')
    val () = $D.apply(doc, $W.set_text_content(ab_id, $S.text_of_chars(abt, 7), 7))
    (* Hide button *)
    var hb_c = @[char][4]('q', 'h', 'i', 'b')
    val hb_id = $W.Generated($S.text_of_chars(hb_c, 4), 4)
    val hb = $W.Element($W.ElementNode(hb_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
    val @(_, diff) = $W.add_child(cmb, hb)
    val () = $D.apply(doc, diff)
    var hbt = @[char][4]('H', 'i', 'd', 'e')
    val () = $D.apply(doc, $W.set_text_content(hb_id, $S.text_of_chars(hbt, 4), 4))

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
        val p = import_epub(fb, 4)
        val p2 = $P.and_then<int><int>(p, lam(result) =>
          if result = 0 then let
            (* Import succeeded — book card already created by _add_book_card *)
            val () = save_epub_to_idb()
            val () = save_metadata_to_idb()
          in $P.ret<int>(0) end
          else let
            var cnt2_c = @[char][4]('q', 'c', 'n', 't')
            val cnt2_id = $W.Generated($S.text_of_chars(cnt2_c, 4), 4)
          in
            if result = ~1 then let
              var e1 = @[char][4]('E', 'R', 'R', '1')
              val () = apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e1, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~2 then let
              var e2 = @[char][4]('E', 'R', 'R', '2')
              val () = apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e2, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~3 then let
              var e3 = @[char][4]('E', 'R', 'R', '3')
              val () = apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e3, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~4 then let
              var e4 = @[char][4]('E', 'R', 'R', '4')
              val () = apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e4, 4), 4))
            in $P.ret<int>(result) end
            else if result = ~5 then let
              var e5 = @[char][4]('E', 'R', 'R', '5')
              val () = apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(e5, 4), 4))
            in $P.ret<int>(result) end
            else let
              var eu = @[char][4]('E', 'R', 'R', 'X')
              val () = apply_diff($W.SetTextContent(cnt2_id, $S.text_of_chars(eu, 4), 4))
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
      lam(_pl: int): int => let
        (* Hide the card and close context menu *)
        var card_c = @[char][5]('q', 'b', 'c', '0', '0')
        val card_id = $W.Generated($S.text_of_chars(card_c, 5), 5)
        val () = apply_diff($W.SetHidden(card_id, 1))
        var ctx_c = @[char][4]('q', 'c', 't', 'x')
        val ctx_id = $W.Generated($S.text_of_chars(ctx_c, 4), 4)
        val () = apply_diff($W.SetHidden(ctx_id, 1))
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
      lam(_pl: int): int => let
        (* Hide the card and close context menu *)
        var card_c = @[char][5]('q', 'b', 'c', '0', '0')
        val card_id = $W.Generated($S.text_of_chars(card_c, 5), 5)
        val () = apply_diff($W.SetHidden(card_id, 1))
        var ctx_c = @[char][4]('q', 'c', 't', 'x')
        val ctx_id = $W.Generated($S.text_of_chars(ctx_c, 4), 4)
        val () = apply_diff($W.SetHidden(ctx_id, 1))
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
      lam(_payload_len: int): int => let
        (* Show library, hide reader *)
        var ll2_c = @[char][4]('q', 'l', 'l', 'c')
        val ll2_id = $W.Generated($S.text_of_chars(ll2_c, 4), 4)
        var rv2_c = @[char][4]('q', 'r', 'v', 'w')
        val rv2_id = $W.Generated($S.text_of_chars(rv2_c, 4), 4)
        val () = apply_diff($W.SetHidden(ll2_id, 0))
        val () = apply_diff($W.SetHidden(rv2_id, 1))
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
      in go_to_page(cur - 1); 0 end)
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
      in go_to_page(cur + 1); 0 end)
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
      in go_to_page(cur - 1); 0 end)
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
      in go_to_page(cur + 1); 0 end)
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
              in go_to_page(cur + 1); 0 end
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
              in go_to_page(cur - 1); 0 end
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
            in go_to_page(cur + 1); 0 end
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
        val () = apply_diff($W.SetHidden(sp_id, 0))
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
          val () = apply_font_size(next)
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
      lam(_payload_len: int): int => let
        val cur = $ST.stash_get_int(25)
        val next = cur + 2
      in
        if next <= 48 then let
          val () = apply_font_size(next)
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
      lam(_payload_len: int): int => let
        var sp_c = @[char][4]('q', 's', 'p', 'n')
        val sp_id = $W.Generated($S.text_of_chars(sp_c, 4), 4)
        val () = apply_diff($W.SetHidden(sp_id, 1))
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
    val () = restore_font_size()
    val () = restore_from_idb()
  in end
  else let
    val nid = $D.get_next_id(doc)
    val () = $ST.stash_set_int(20, nid)
    val () = $D.destroy(doc)
  in end
end
