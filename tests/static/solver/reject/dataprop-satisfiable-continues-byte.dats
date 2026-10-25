#include "share/atspre_staload.hats"
(* src/cut.bats CONTINUES, copied: see gen_guards.py.
   Probe: every guard of CONTINUES_byte holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop CONTINUES(int) =
  | {code:int | 128 <= code; code < 192} CONTINUES_byte(code)

prfn satisfiable_continues_byte {code:int | 128 <= code; code < 192} (): [1 == 2] void = ()
