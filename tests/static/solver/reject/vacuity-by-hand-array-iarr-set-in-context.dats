#include "share/atspre_staload.hats"
(* array src/lib.bats:719 iarr-set-in, by hand (a trusted import has no copy here): the context of the int range (~2147483648 <= lo; hi <= 2147483647; lo <= v <= hi) is satisfiable, so `[1 == 2] void` under it is rejected *)
prfn context {l:agz}{n,i:nat | i < n}{lo,hi:int | ~2147483648 <= lo; hi <= 2147483647}{v:int | lo <= v; v <= hi} (): [1 == 2] void = ()
