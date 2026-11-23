(* book_rules -- the rules that keep the reader's settings over a book's own CSS
   (quire#1065, umbrella quire#1063 of the design, section 4; keyword: book css)

   A chapter's book CSS is adopted by bridge into `@layer book`; the reader's own content
   rules are in `@layer reader-base`, so the order of the two layers is declared first. What the
   reader still overrides is unlayered `!important`, which beats every normal declaration of the
   book (its sheets, in a layer, and its style attributes, element-attached) and, the book's own
   `!important` being dropped by the narrowing, every important one too. Each rule is keyed on
   the reflow container, `[data-book-layout="1"]`, which only bridge's opcode 13 sets, and on
   `[data-book-element]`, which only the book opcodes set, so no app element is matched. A fixed
   layout (`data-book-layout="2"`) has none of these (design section 5).

   style-book is static; style-book-vars (the reader's justify and hyphenation, which a rule of
   the page's own sets on `.caf p` only) is written by settings.bats's `_apply_type`. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use builder as B

staload "sheet.sats"

(* The overrides of design section 4, one for each row of its table that is a rule *)
fn _overrides {left:nat | left >= 4400} (sheet: sheet(left, false, false)): [after:nat | after >= left - 4400] sheet(after, false, false) = let
  (* the order of the layers: the reader's defaults, then the book's *)
  val () = raw(sheet, "@layer reader-base,book;")
  (* size: the reader's size times the book's dominant-size measure (#431) *)
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element=\"body\"]{font-size:calc(var(--reading-size)*var(--book-size-factor,1))!important}")
  (* font, line spacing, letter and word spacing: the container's own, which the settings write *)
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element]:not(code,pre,kbd,samp,tt){font-family:inherit!important}")
  val () = raw(sheet, "[data-book-layout=\"1\"] :is([data-book-element=\"body\"],[data-book-element=\"p\"],[data-book-element=\"li\"],[data-book-element=\"dd\"],[data-book-element=\"blockquote\"]){line-height:inherit!important}")
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element]{letter-spacing:inherit!important;word-spacing:inherit!important}")
  (* justify and hyphenation: not headings, tables, pre, figcaption, nor a p in a blockquote or header (Readium's textAlign_pref, #868) *)
  val () = raw(sheet, "[data-book-layout=\"1\"] :is([data-book-element=\"body\"],[data-book-element=\"li\"],[data-book-element=\"dd\"],[data-book-element=\"p\"]:not(:is([data-book-element=\"blockquote\"],[data-book-element=\"header\"])>*)){text-align:var(--reader-align,start)!important;text-align-last:auto!important;hyphens:var(--reader-hyphens,manual)!important}")
  (* margins: the reader's margin setting (the container's padding) is the only horizontal margin; block margins stay the book's *)
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element=\"body\"]{margin-inline:0!important;padding-inline:0!important}")
  (* theme colours: in Dark, Night and Grey the book's text colour is the theme's, in every pseudo-element a colour can come from *)
  val () = raw(sheet, ":is(.th-dark,.th-night,.th-grey) [data-book-layout=\"1\"] [data-book-element],")
  val () = raw(sheet, ":is(.th-dark,.th-night,.th-grey) [data-book-layout=\"1\"] [data-book-element]::before,")
  val () = raw(sheet, ":is(.th-dark,.th-night,.th-grey) [data-book-layout=\"1\"] [data-book-element]::after,")
  val () = raw(sheet, ":is(.th-dark,.th-night,.th-grey) [data-book-layout=\"1\"] [data-book-element]::first-letter,")
  val () = raw(sheet, ":is(.th-dark,.th-night,.th-grey) [data-book-layout=\"1\"] [data-book-element]::first-line,")
  val () = raw(sheet, ":is(.th-dark,.th-night,.th-grey) [data-book-layout=\"1\"] [data-book-element]::marker{color:inherit!important}")
  (* images, tables and pre: as wide as the column and no taller than the page (#413) *)
  val () = raw(sheet, "[data-book-layout=\"1\"] :is([data-book-element=\"img\"],[data-book-element=\"svg\"],[data-book-element=\"video\"]){max-width:100%!important;max-height:calc(100vh - var(--page-top,0px) - var(--page-bottom,0px))!important;object-fit:contain!important}")
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element=\"table\"]{overflow:auto!important;max-width:100%!important}")
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element=\"pre\"]{white-space:pre-wrap!important}")
  (* what the book hid stays hidden (#411) *)
  val () = raw(sheet, "[data-book-layout=\"1\"] .hidden-by-book{display:none!important}")
in sheet end

(* The style sheet of the overrides *)
#pub fn book_style (): [l:agz][k:nat | k < 65536] @($A.arr(byte, l, $B.BUILDER_CAP), int k)

implement book_style () = let
  val builder = $B.create()
  val sheet: sheet(BUDGET, false, false) = Sheet(builder)
  val sheet = _overrides(sheet)
  val+ ~Sheet(builder) = sheet
  val @(bytes, length) = $B.to_arr(builder)
in @(bytes, length) end

end
