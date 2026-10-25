#include "share/atspre_staload.hats"
(* quire src/schema.bats TAGDIFF, copied: see gen_guards.py.
   False variant: the guard atom `right_fourth < 256` of TAGDIFF_mk shifted by 1: `right_fourth < (256) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop TAGDIFF(bytes, bytes) =
  | {left_first,left_second,left_third,left_fourth,right_first,right_second,right_third,right_fourth:int | 0 <= left_first; left_first < 256; 0 <= left_second; left_second < 256; 0 <= left_third; left_third < 256; 0 <= left_fourth; left_fourth < 256;
       0 <= right_first; right_first < 256; 0 <= right_second; right_second < 256; 0 <= right_third; right_third < 256; 0 <= right_fourth; right_fourth < 256;
       left_first != right_first || left_second != right_second || left_third != right_third || left_fourth != right_fourth}
    TAGDIFF_mk(bcons(left_first, bcons(left_second, bcons(left_third, bcons(left_fourth, bnil())))), bcons(right_first, bcons(right_second, bcons(right_third, bcons(right_fourth, bnil())))))

prfn probe_right_fourth_lt_256 {left_first,left_second,left_third,left_fourth,right_first,right_second,right_third,right_fourth:int | 0 <= left_first; left_first < 256; 0 <= left_second; left_second < 256; 0 <= left_third; left_third < 256; 0 <= left_fourth; left_fourth < 256; 0 <= right_first; right_first < 256; 0 <= right_second; right_second < 256; 0 <= right_third; right_third < 256; 0 <= right_fourth; right_fourth < (256) + 1; left_first != right_first || left_second != right_second || left_third != right_third || left_fourth != right_fourth} (): TAGDIFF(bcons(left_first, bcons(left_second, bcons(left_third, bcons(left_fourth, bnil())))), bcons(right_first, bcons(right_second, bcons(right_third, bcons(right_fourth, bnil()))))) = TAGDIFF_mk{left_first,left_second,left_third,left_fourth,right_first,right_second,right_third,right_fourth}()
