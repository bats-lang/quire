#include "share/atspre_staload.hats"
(* array src/lib.bats:704 iarr-get, by hand (a trusted import has no copy here): the context of the int range (~2147483648 <= v; v <= 2147483647) is satisfiable, so `[1 == 2] void` under it is rejected *)
prfn context {l:agz}{n,i:nat | i < n}{v:int | ~2147483648 <= v; v <= 2147483647} (): [1 == 2] void = ()
