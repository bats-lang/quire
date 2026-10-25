#include "share/atspre_staload.hats"
(* src/cut.bats NOTWHITE, copied: see gen_guards.py.
   Probe: every guard of NOTWHITE_below holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

prfn satisfiable_notwhite_below {code:int | code <= 8} (): [1 == 2] void = ()
