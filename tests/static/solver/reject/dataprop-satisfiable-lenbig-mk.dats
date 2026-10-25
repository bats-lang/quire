#include "share/atspre_staload.hats"
(* src/chunk.bats LENBIG, copied: see gen_guards.py.
   Probe: every guard of LENBIG_mk holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LENBIG(bytes) =
  | {length_low,length_middle,length_high,length_top:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 256; 0 <= length_top; length_top < 256; length_top > 0 || length_high >= 16}
    LENBIG_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(length_top, bnil())))))

prfn satisfiable_lenbig_mk {length_low,length_middle,length_high,length_top:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 256; 0 <= length_top; length_top < 256; length_top > 0 || length_high >= 16} (): [1 == 2] void = ()
