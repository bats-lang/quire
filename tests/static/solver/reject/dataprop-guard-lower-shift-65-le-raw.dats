#include "share/atspre_staload.hats"
(* quire src/text_relation.bats LOWER, copied: see gen_guards.py.
   False variant: the guard atom `65 <= raw` of LOWER_shift shifted by 1: `65 <= (raw) + 1` *)
dataprop LOWER(int, int) =
  | {raw:int | raw < 65 || 90 < raw} LOWER_same(raw, raw)
  | {raw:int | 65 <= raw; raw <= 90} LOWER_shift(raw, raw + 32)

prfn probe_65_le_raw {raw:int | 65 <= (raw) + 1; raw <= 90} (): LOWER(raw, raw + 32) = LOWER_shift{raw}()
