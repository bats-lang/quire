(* views -- all UI rendering via widget/dom diff *)

#include "share/atspre_staload.hats"

#use str as S
#use widget as W
#use wasm.bats-packages.dev/dom as D

(* ============================================================
   Library view: empty state with import button
   ============================================================ *)

#pub fn render_library_empty
  {l:agz}
  (doc: !$D.document(l),
   lib_id: $W.widget_id,
   empty_id: $W.widget_id,
   imp_id: $W.widget_id): void

(* ============================================================
   Implementations
   ============================================================ *)

implement render_library_empty (doc, lib_id, empty_id, imp_id) = let
  val lib_el = $W.Element($W.ElementNode(lib_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val empty_el = $W.Element($W.ElementNode(empty_id, $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val imp_el = $W.Element($W.ElementNode(imp_id, $W.Normal($W.Label($W.NoneStr())), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))

  val () = $D.apply(doc, $W.AddChild($W.Root(), lib_el))
  val () = $D.apply(doc, $W.set_class_name(lib_id, "library-list"))

  val () = $D.apply(doc, $W.AddChild(lib_id, empty_el))
  val () = $D.apply(doc, $W.set_class_name(empty_id, "empty-lib"))
  val () = $D.apply(doc, $W.set_text_content(empty_id, "No books yet"))

  val () = $D.apply(doc, $W.AddChild(lib_id, imp_el))
  val () = $D.apply(doc, $W.set_class_name(imp_id, "import-btn"))
  val () = $D.apply(doc, $W.set_text_content(imp_id, "Import EPUB"))
in end
