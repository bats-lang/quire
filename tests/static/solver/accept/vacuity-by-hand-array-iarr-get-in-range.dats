#include "share/atspre_staload.hats"
(* array src/lib.bats:714 iarr-get-in, by hand (a trusted import has no copy here): a cell of cells within [lo, hi] is within them, and the bounds are 32-bit ints. Control: the largest itself, accepted *)
prfn range {l:agz}{n,i:nat | i < n}{lo,hi:int | ~2147483648 <= lo; hi <= 2147483647}{v:int | lo <= v; v <= hi} (): [v <= hi] void = ()
