#include "share/atspre_staload.hats"
(* css:src/harmony.bats RGB, copied: see gen_guards.py.
   Probe: every guard of RGBc holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop RGB(int, int, int, int) =
  | {r,g,b:nat | r < 256; g < 256; b < 256} RGBc(r * 65536 + g * 256 + b, r, g, b)

prfn satisfiable_rgbc {r,g,b:nat | r < 256; g < 256; b < 256} (): [1 == 2] void = ()
