#include "share/atspre_staload.hats"
(* src/cut.bats STARTS, copied: see gen_guards.py.
   Probe: every guard of STARTS_ascii holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop STARTS(int) =
  | {code:int | code < 128} STARTS_ascii(code)
  | {code:int | 192 <= code} STARTS_lead(code)

prfn satisfiable_starts_ascii {code:int | code < 128} (): [1 == 2] void = ()
