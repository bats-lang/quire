#include "share/atspre_staload.hats"
(* src/text_relation.bats LOWER, copied: see gen_guards.py.
   Probe: every guard of LOWER_same holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop LOWER(int, int) =
  | {raw:int | raw < 65 || 90 < raw} LOWER_same(raw, raw)
  | {raw:int | 65 <= raw; raw <= 90} LOWER_shift(raw, raw + 32)

prfn satisfiable_lower_same {raw:int | raw < 65 || 90 < raw} (): [1 == 2] void = ()
