#include "share/atspre_staload.hats"
(* zip src/lib.bats:4510 INFLATE_OUTPUT_MOST, by hand (a trusted import has no copy here): an output length within INFLATE_OUTPUT_MOST = 2147483647, the largest 32-bit int. Control: the largest itself, accepted *)
prfn range {n:nat | n <= 2147483647} (): [n <= 2147483647] void = ()
