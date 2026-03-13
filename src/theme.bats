(* theme -- CSS class indices and stylesheet for quire *)

#include "share/atspre_staload.hats"

(* Class indices — css.class_text maps: 0->caa, 1->cab, 2->cac *)

#pub fun cls_library_list(): int

implement cls_library_list() = 0

#pub fun cls_empty_lib(): int

implement cls_empty_lib() = 1

#pub fun cls_import_btn(): int

implement cls_import_btn() = 2

#pub fun cls_reader_view(): int

implement cls_reader_view() = 3

#pub fun cls_back_btn(): int

implement cls_back_btn() = 4

#pub fun cls_content_area(): int

implement cls_content_area() = 5

(* ============================================================
   Stylesheet
   ============================================================ *)

#pub fun theme_css(): string

implement theme_css() = "[hidden]{display:none!important}.caa{display:flex;flex-direction:column;padding:16px}.cab{text-align:center;color:#888;padding:32px}.cac{display:inline-block;padding:8px 16px;background:#4a90d9;color:#fff;border-radius:4px;cursor:pointer}.cad{display:flex;flex-direction:column;height:100vh}.cae{padding:8px 16px;background:#333;color:#fff;cursor:pointer;align-self:flex-start}.caf{flex:1;padding:16px;overflow-y:auto}"
