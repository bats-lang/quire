#include "share/atspre_staload.hats"
(* quire src/chunk.bats LENBIG, copied: see gen_guards.py.
   False variant: the guard atom `length_top > 0 || length_high >= 16` of LENBIG_mk shifted by 1: `dropped` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LENBIG(bytes) =
  | {length_low,length_middle,length_high,length_top:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 256; 0 <= length_top; length_top < 256; length_top > 0 || length_high >= 16}
    LENBIG_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(length_top, bnil())))))

prfn probe_length_top_gt_0_or_length_high_ge_16 {length_low,length_middle,length_high,length_top:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 256; 0 <= length_top; length_top < 256} (): LENBIG(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(length_top, bnil()))))) = LENBIG_mk{length_low,length_middle,length_high,length_top}()
