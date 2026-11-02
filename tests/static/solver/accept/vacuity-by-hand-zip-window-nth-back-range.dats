#include "share/atspre_staload.hats"
(* zip src/lib.bats:2867 window_nth_back, by hand (a trusted import has no copy here): the streaming sink's count written is within [0, 2147483647], the fill within [0, 65536]. Control: the largest itself, accepted *)
prfn range {written,fill:nat | fill <= 65536; written <= 2147483647} (): [written <= 2147483647] void = ()
