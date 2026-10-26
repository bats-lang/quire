#include "share/atspre_staload.hats"
(* array src/lib.bats:704 iarr-get, by hand (a trusted import has no copy here): a cell read is a 32-bit int, within [-2147483648, 2147483647]. Control: the largest itself, accepted *)
prfn range {l:agz}{n,i:nat | i < n}{v:int | ~2147483648 <= v; v <= 2147483647} (): [v <= 2147483647] void = ()
