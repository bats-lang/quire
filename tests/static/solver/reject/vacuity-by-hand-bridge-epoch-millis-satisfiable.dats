#include "share/atspre_staload.hats"
(* bridge src/timer.bats:25 epoch_millis, by hand (a wasm import has no copy here): the context of the bound low < 1073741824 is
   satisfiable, so `[1 == 2] void` under it is rejected *)
prfn context {high:nat}{low:nat | low < 1073741824} (): [1 == 2] void = ()
