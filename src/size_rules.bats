(* size_rules -- the sizes a book's elements are given (quire#431)

   An element the book's publisher gave a size has a data-fs of its step
   (reader.bats's _size_mark), from 10 to 60 twentieths of the reader's
   size, as css_size's `proportion` holds: half to three times, so no
   text is under the readable floor nor so large that a word is wider than
   the page (as Readium CSS clamps). The rule for a step sets the font
   size to that many twentieths of --reading-size, which settings.bats
   writes with the reader's size. They are a style element of their own
   (style-sizes), after the sheet's, so a book's size outranks the reader's
   own for its element (an h1 at 2em of the book's) and no other rule can
   outrank a step: the selectors are all of one specificity, and the
   steps different. Each rule is a selector of 19 bytes and a value of
   30, so a step cannot name a rule that is not written, and the sheet's
   budget is proven to hold all 51.

   The same style element holds the alignments (keyword: publisher
   alignment, #868): a element of a table the publisher aligned has a
   data-align of left, right or center (reader.bats's _align_mark), and the
   rule for it sets the text-align (text-align, then justify-items); an element has one data-align,
   so no two of the rules reach the same element *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use builder as B

staload "css_size.sats"
staload "sheet.sats"

(* The selector of a step: every one has 19 bytes *)
fn _selector (step: proportion): string(19) =
  case+ step of
  | 10 => ".caf [data-fs=\"10\"]"
  | 11 => ".caf [data-fs=\"11\"]"
  | 12 => ".caf [data-fs=\"12\"]"
  | 13 => ".caf [data-fs=\"13\"]"
  | 14 => ".caf [data-fs=\"14\"]"
  | 15 => ".caf [data-fs=\"15\"]"
  | 16 => ".caf [data-fs=\"16\"]"
  | 17 => ".caf [data-fs=\"17\"]"
  | 18 => ".caf [data-fs=\"18\"]"
  | 19 => ".caf [data-fs=\"19\"]"
  | 20 => ".caf [data-fs=\"20\"]"
  | 21 => ".caf [data-fs=\"21\"]"
  | 22 => ".caf [data-fs=\"22\"]"
  | 23 => ".caf [data-fs=\"23\"]"
  | 24 => ".caf [data-fs=\"24\"]"
  | 25 => ".caf [data-fs=\"25\"]"
  | 26 => ".caf [data-fs=\"26\"]"
  | 27 => ".caf [data-fs=\"27\"]"
  | 28 => ".caf [data-fs=\"28\"]"
  | 29 => ".caf [data-fs=\"29\"]"
  | 30 => ".caf [data-fs=\"30\"]"
  | 31 => ".caf [data-fs=\"31\"]"
  | 32 => ".caf [data-fs=\"32\"]"
  | 33 => ".caf [data-fs=\"33\"]"
  | 34 => ".caf [data-fs=\"34\"]"
  | 35 => ".caf [data-fs=\"35\"]"
  | 36 => ".caf [data-fs=\"36\"]"
  | 37 => ".caf [data-fs=\"37\"]"
  | 38 => ".caf [data-fs=\"38\"]"
  | 39 => ".caf [data-fs=\"39\"]"
  | 40 => ".caf [data-fs=\"40\"]"
  | 41 => ".caf [data-fs=\"41\"]"
  | 42 => ".caf [data-fs=\"42\"]"
  | 43 => ".caf [data-fs=\"43\"]"
  | 44 => ".caf [data-fs=\"44\"]"
  | 45 => ".caf [data-fs=\"45\"]"
  | 46 => ".caf [data-fs=\"46\"]"
  | 47 => ".caf [data-fs=\"47\"]"
  | 48 => ".caf [data-fs=\"48\"]"
  | 49 => ".caf [data-fs=\"49\"]"
  | 50 => ".caf [data-fs=\"50\"]"
  | 51 => ".caf [data-fs=\"51\"]"
  | 52 => ".caf [data-fs=\"52\"]"
  | 53 => ".caf [data-fs=\"53\"]"
  | 54 => ".caf [data-fs=\"54\"]"
  | 55 => ".caf [data-fs=\"55\"]"
  | 56 => ".caf [data-fs=\"56\"]"
  | 57 => ".caf [data-fs=\"57\"]"
  | 58 => ".caf [data-fs=\"58\"]"
  | 59 => ".caf [data-fs=\"59\"]"
  | _ => ".caf [data-fs=\"60\"]"

(* The size of a step: the reader's size times the step in twentieths, every
   one of 30 bytes *)
fn _size (step: proportion): string(30) =
  case+ step of
  | 10 => "calc(var(--reading-size)*0.50)"
  | 11 => "calc(var(--reading-size)*0.55)"
  | 12 => "calc(var(--reading-size)*0.60)"
  | 13 => "calc(var(--reading-size)*0.65)"
  | 14 => "calc(var(--reading-size)*0.70)"
  | 15 => "calc(var(--reading-size)*0.75)"
  | 16 => "calc(var(--reading-size)*0.80)"
  | 17 => "calc(var(--reading-size)*0.85)"
  | 18 => "calc(var(--reading-size)*0.90)"
  | 19 => "calc(var(--reading-size)*0.95)"
  | 20 => "calc(var(--reading-size)*1.00)"
  | 21 => "calc(var(--reading-size)*1.05)"
  | 22 => "calc(var(--reading-size)*1.10)"
  | 23 => "calc(var(--reading-size)*1.15)"
  | 24 => "calc(var(--reading-size)*1.20)"
  | 25 => "calc(var(--reading-size)*1.25)"
  | 26 => "calc(var(--reading-size)*1.30)"
  | 27 => "calc(var(--reading-size)*1.35)"
  | 28 => "calc(var(--reading-size)*1.40)"
  | 29 => "calc(var(--reading-size)*1.45)"
  | 30 => "calc(var(--reading-size)*1.50)"
  | 31 => "calc(var(--reading-size)*1.55)"
  | 32 => "calc(var(--reading-size)*1.60)"
  | 33 => "calc(var(--reading-size)*1.65)"
  | 34 => "calc(var(--reading-size)*1.70)"
  | 35 => "calc(var(--reading-size)*1.75)"
  | 36 => "calc(var(--reading-size)*1.80)"
  | 37 => "calc(var(--reading-size)*1.85)"
  | 38 => "calc(var(--reading-size)*1.90)"
  | 39 => "calc(var(--reading-size)*1.95)"
  | 40 => "calc(var(--reading-size)*2.00)"
  | 41 => "calc(var(--reading-size)*2.05)"
  | 42 => "calc(var(--reading-size)*2.10)"
  | 43 => "calc(var(--reading-size)*2.15)"
  | 44 => "calc(var(--reading-size)*2.20)"
  | 45 => "calc(var(--reading-size)*2.25)"
  | 46 => "calc(var(--reading-size)*2.30)"
  | 47 => "calc(var(--reading-size)*2.35)"
  | 48 => "calc(var(--reading-size)*2.40)"
  | 49 => "calc(var(--reading-size)*2.45)"
  | 50 => "calc(var(--reading-size)*2.50)"
  | 51 => "calc(var(--reading-size)*2.55)"
  | 52 => "calc(var(--reading-size)*2.60)"
  | 53 => "calc(var(--reading-size)*2.65)"
  | 54 => "calc(var(--reading-size)*2.70)"
  | 55 => "calc(var(--reading-size)*2.75)"
  | 56 => "calc(var(--reading-size)*2.80)"
  | 57 => "calc(var(--reading-size)*2.85)"
  | 58 => "calc(var(--reading-size)*2.90)"
  | 59 => "calc(var(--reading-size)*2.95)"
  | _ => "calc(var(--reading-size)*3.00)"

(* The rules of the steps from step to the last (60) *)
fun _rules_from {left:nat}{step:int | 10 <= step; step <= 61 ; 69 * (61 - step) <= left} .<61 - step>.
  (sheet: sheet(left, false, false), step: int step): [after:nat | after >= left - 69 * (61 - step)] sheet(after, false, false) =
  if step >= 61 then sheet
  else let
    val sheet = rule(sheet, _selector(step))
    val sheet = lay(sheet, FontSize(), _size(step))
    val sheet = close(sheet)
  in _rules_from(sheet, step + 1) end

(* The rules of the alignments: left, right and center, each a selector and
   the text-align a table cell takes, then the justify-items a MathML cell
   takes (Chromium leaves the content of an mtd where it was for a plain
   text-align; the book's own sheet writes both) *)
fn _align_rules {left:nat | 336 <= left} (sheet: sheet(left, false, false)): [after:nat | after >= left - 336] sheet(after, false, false) = let
  val sheet = rule(sheet, ".caf [data-align=\"left\"]")
  val sheet = lay(sheet, TextAlign(), "left")
  val sheet = lay(sheet, JustifyItems(), "start")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf [data-align=\"right\"]")
  val sheet = lay(sheet, TextAlign(), "right")
  val sheet = lay(sheet, JustifyItems(), "end")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf [data-align=\"center\"]")
  val sheet = lay(sheet, TextAlign(), "center")
  val sheet = lay(sheet, JustifyItems(), "center")
  val sheet = close(sheet)
in sheet end

(* The style sheet of the sizes: one rule for each step, and the alignments *)
#pub fn size_style (): [l:agz][k:nat | k < 65536] @($A.arr(byte, l, $B.BUILDER_CAP), int k)

implement size_style () = let
  val builder = $B.create()
  val sheet: sheet(BUDGET, false, false) = Sheet(builder)
  val sheet = _rules_from(sheet, 10)
  val sheet = _align_rules(sheet)
  val+ ~Sheet(builder) = sheet
  val @(bytes, length) = $B.to_arr(builder)
in @(bytes, length) end

end
