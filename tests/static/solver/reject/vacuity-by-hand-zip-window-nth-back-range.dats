#include "share/atspre_staload.hats"
(* zip src/lib.bats:2867 window_nth_back, by hand (a trusted import has no copy here): the streaming sink's count written is within [0, 2147483647]. Change: one more than the largest, false at the largest *)
prfn range {written,fill:nat | fill <= 65536; written <= 2147483647} (): [written + 1 <= 2147483647] void = ()
