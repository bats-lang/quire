#include "share/atspre_staload.hats"
(* zip src/lib.bats:4510 INFLATE_OUTPUT_MOST (a stadef of 2147483647, the bound of an output's size), by hand: a size under the bound plus 2
   stays within it. Change: false at size 2147483646 *)
prfn step {size:nat | size <= 2147483647; size < 2147483647} ()
  : [size + 2 <= 2147483647] void = ()
