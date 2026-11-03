#include "share/atspre_staload.hats"
(* zip src/lib.bats:4510 INFLATE_OUTPUT_MOST, by hand (a trusted import has no copy here): an output length is within [0, 2147483647]. Change: one more than the largest, false at the largest *)
prfn range {n:nat | n <= 2147483647} (): [n + 1 <= 2147483647] void = ()
