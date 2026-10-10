(* page_size -- the page is a whole number of pixels wide and high

   The reader scrolls to page n by n times the page's width (its height,
   down) and counts the pages as the chapter's scroll width over it, and
   the size it is told is a whole number: the bridge's measure rounds, and
   so does the scroll width. A window whose size is a fraction of a pixel
   (a Pixel 9 is 1080 by 2424 device pixels at 2.625 a CSS pixel, 411.43
   by 923.43) made the page as large as that fraction, so each page's
   offset was out by 0.43 px more than the one before it: a chapter of
   19 pages or more was counted a page too many, and that page, past the
   end of what scrolls, showed what the one before it did (the last page
   of every chapter, doubled), while the pages before it began in the
   previous page's last letters.

   Columns of a page's width (a vertical page's, its height) are the
   page's size exactly when it is whole, so the stylesheet states the
   page's width and height only as an extent of the first kind, indexed
   by whether it is whole, so one that is a fraction does not type-check
   (tests/static/reject/page-width-fraction, page-height-fraction).
   What stays outside the proof is the browser: that a column is as wide
   as the page it is in, and that round() rounds, which the e2e suite
   plays in a window of a fraction's width (e2e/fractional-window.spec.js) *)

#include "share/atspre_staload.hats"

(* An extent the stylesheet may give the page: indexed by whether it is a
   whole number of pixels (1) or may be a fraction (0) *)
#pub datatype page_extent(int) =
  | ContainerLessInsets(0) of ()
  | RoundedDown(1) of ()

(* The declaration of the page's height, a vertical page's column and the
   pages down a scrolled chapter, rounded down to a whole pixel: only a
   whole extent gives one *)
#pub fn page_height_rule (extent: page_extent(1)): [text_len:pos | text_len <= 40] string text_len

implement page_height_rule (extent) =
  case+ extent of
  | RoundedDown() => "max-height:round(down,100%,1px);"

(* The declaration of the page's width: the container's less the safe
   area's insets at the sides, rounded down to a whole pixel *)
#pub fn page_width_rule (extent: page_extent(1)): [text_len:pos | text_len <= 100] string text_len

implement page_width_rule (extent) =
  case+ extent of
  | RoundedDown() => "max-width:round(down,calc(100% - env(safe-area-inset-left) - env(safe-area-inset-right)),1px);"

(* The two rules above are all this module holds *)
