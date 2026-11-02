#include "share/atspre_staload.hats"
(* zip src/lib.bats:2867 window_nth_back, by hand (a trusted import has no copy here): the context of the streaming sink's bounds (fill <= 65536; written <= 2147483647) is satisfiable, so `[1 == 2] void` under it is rejected *)
prfn context {written,fill:nat | fill <= 65536; written <= 2147483647} (): [1 == 2] void = ()
