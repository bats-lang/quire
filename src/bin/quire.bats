#target wasm binary
#include "share/atspre_staload.hats"
#use css as C
#use str as S
#use wasm.bats-packages.dev/dom as D
#use widget as W

(* Class indices — class_text maps: 0->caa, 1->cab, 2->cac *)
macdef CLS_LIBRARY_LIST = 0
macdef CLS_EMPTY_LIB = 1
macdef CLS_IMPORT_BTN = 2

implement main0 () = let
  var tag = @[char][3]('d', 'i', 'v')
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val doc = $D.create_document($S.text_of_chars(tag, 3), 3, $S.text_of_chars(mid, 9), 9)

  (* Root element *)
  val root = $W.Element($W.ElementNode($W.Root(), $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))

  (* Inject CSS stylesheet *)
  var si_c = @[char][4]('q', 'c', 's', 's')
  val si_id = $W.Generated($S.text_of_chars(si_c, 4), 4)
  val @(root, css_diffs) = $W.inject_css(root, si_id, ".caa{display:flex;flex-direction:column;padding:16px}.cab{text-align:center;color:#888;padding:32px}.cac{display:inline-block;padding:8px 16px;background:#4a90d9;color:#fff;border-radius:4px;cursor:pointer}")
  val () = $D.apply_list(doc, css_diffs)

  (* library-list container *)
  var ll_c = @[char][4]('q', 'l', 'l', 'c')
  val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
  val ll = $W.Element($W.ElementNode(ll_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(root, diff) = $W.add_child(root, ll)
  val () = $D.apply(doc, diff)
  val @(ll, diff) = $W.set_class(ll, CLS_LIBRARY_LIST)
  val () = $D.apply(doc, diff)

  (* empty-lib message *)
  var el_c = @[char][4]('q', 'e', 'l', 'b')
  val el_id = $W.Generated($S.text_of_chars(el_c, 4), 4)
  val el = $W.Element($W.ElementNode(el_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(ll, el)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(el, CLS_EMPTY_LIB)
  val () = $D.apply(doc, diff)
  val () = $D.apply(doc, $W.set_text_content(el_id, "Your library is empty"))

  (* import button *)
  var ib_c = @[char][4]('q', 'i', 'b', 'n')
  val ib_id = $W.Generated($S.text_of_chars(ib_c, 4), 4)
  val ib = $W.Element($W.ElementNode(ib_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(ll, ib)
  val () = $D.apply(doc, diff)
  val @(_, diff) = $W.set_class(ib, CLS_IMPORT_BTN)
  val () = $D.apply(doc, diff)
  val () = $D.apply(doc, $W.set_text_content(ib_id, "Import EPUB"))

  (* hidden file input inside import button *)
  var fi_c = @[char][4]('q', 'f', 'i', 'n')
  val fi_id = $W.Generated($S.text_of_chars(fi_c, 4), 4)
  val fi = $W.Element($W.ElementNode(fi_id, $W.Void($W.HtmlInput($W.InputFile(), $W.NoneStr(), $W.NoneStr(), 0, 0, 0)), ~1, 1, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(ib, fi)
  val () = $D.apply(doc, diff)

  val () = $D.destroy(doc)
in end
