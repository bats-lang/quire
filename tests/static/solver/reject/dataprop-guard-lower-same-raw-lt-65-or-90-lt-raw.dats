#include "share/atspre_staload.hats"
(* quire src/text_relation.bats LOWER, copied: see gen_guards.py.
   False variant: the guard atom `raw < 65 || 90 < raw` of LOWER_same shifted by 1: `dropped` *)
dataprop LOWER(int, int) =
  | {raw:int | raw < 65 || 90 < raw} LOWER_same(raw, raw)
  | {raw:int | 65 <= raw; raw <= 90} LOWER_shift(raw, raw + 32)

prfn probe_raw_lt_65_or_90_lt_raw {raw:int} (): LOWER(raw, raw) = LOWER_same{raw}()
