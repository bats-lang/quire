#include "share/atspre_staload.hats"
(* zip src/lib.bats:4510 INFLATE_OUTPUT_MOST, by hand (a trusted import has no copy here): the context of an output length within INFLATE_OUTPUT_MOST (n <= 2147483647) is satisfiable, so `[1 == 2] void` under it is rejected *)
prfn context {n:nat | n <= 2147483647} (): [1 == 2] void = ()
