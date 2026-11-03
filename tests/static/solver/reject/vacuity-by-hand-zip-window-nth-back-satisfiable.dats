#include "share/atspre_staload.hats"
(* zip src/lib.bats:2867 window_nth_back (the streaming sink's constructor), by hand: the context of the bounds written <= 2147483647 and
   fill <= 65536 is satisfiable, so `[1 == 2] void` under it is rejected *)
prfn context {written,fill:nat | fill <= 65536; written <= 2147483647} (): [1 == 2] void = ()
