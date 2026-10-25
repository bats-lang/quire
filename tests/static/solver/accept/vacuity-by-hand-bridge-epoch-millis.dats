#include "share/atspre_staload.hats"
(* bridge src/timer.bats:25 epoch_millis, by hand (a wasm import has no copy here): the milliseconds are high * 2^30 + low with
   low < 1073741824. Control: they stay below the next high *)
prfn millis {high:nat}{low:nat | low < 1073741824} ()
  : [high * 1073741824 + low < (high + 1) * 1073741824] void = ()
