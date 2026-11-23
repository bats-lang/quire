(* book_rules: the reader's settings over a book's CSS (keyword: book css) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use builder as B

staload "sheet.sats"

(* the overrides, a rule for each row of the design (keyword: book css) *)
fn _overrides {left:nat | left >= 4400} (sheet: sheet(left, false, false)): [after:nat | after >= left - 4400] sheet(after, false, false) = let
  (* the order of the layers, reader-base then book (keyword: book css) *)
  val () = raw(sheet, "@layer reader-base,book;")
  (* size: the reader's size times the book's dominant-size measure (#431) *)
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element=\"body\"]{font-size:calc(var(--reading-size)*var(--book-size-factor,1))!important}")
  (* font, line spacing, letter and word spacing: the container's own, which the settings write *)
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element]:not(code,pre,kbd,samp,tt){font-family:inherit!important}")
  val () = raw(sheet, "[data-book-layout=\"1\"] :is([data-book-element=\"body\"],[data-book-element=\"p\"],[data-book-element=\"li\"],[data-book-element=\"dd\"],[data-book-element=\"blockquote\"]){line-height:inherit!important}")
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element]{letter-spacing:inherit!important;word-spacing:inherit!important}")
  (* justify, hyphenation: body text only (keyword: book css, #868) *)
  val () = raw(sheet, "[data-book-layout=\"1\"] :is([data-book-element=\"body\"],[data-book-element=\"li\"],[data-book-element=\"dd\"],[data-book-element=\"p\"]:not(:is([data-book-element=\"blockquote\"],[data-book-element=\"header\"])>*)){text-align:var(--reader-align,start)!important;text-align-last:auto!important;hyphens:var(--reader-hyphens,manual)!important}")
  (* margins: the reader's setting is the only horizontal margin (keyword: book css) *)
  val () = raw(sheet, "[data-book-layout=\"1\"] [data-book-element=\"body\"]{margin-inline:0!important;padding-inline:0!important}")
  (* theme colours: the theme's own, pseudo-elements too (keyword: book css) *)
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
