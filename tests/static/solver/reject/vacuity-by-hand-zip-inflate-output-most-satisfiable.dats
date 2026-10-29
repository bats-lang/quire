#include "share/atspre_staload.hats"
(* zip src/lib.bats:4510 INFLATE_OUTPUT_MOST, by hand: the context of the bound size <= 2147483647 is satisfiable, so `[1 == 2] void` under it
   is rejected *)
prfn context {size:nat | size <= 2147483647} (): [1 == 2] void = ()
