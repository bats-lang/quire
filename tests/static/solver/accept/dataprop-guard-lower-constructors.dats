#include "share/atspre_staload.hats"
(* quire src/text_relation.bats LOWER, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
dataprop LOWER(int, int) =
  | {raw:int | raw < 65 || 90 < raw} LOWER_same(raw, raw)
  | {raw:int | 65 <= raw; raw <= 90} LOWER_shift(raw, raw + 32)

prfn control_lower_same {raw:int | raw < 65 || 90 < raw} (): LOWER(raw, raw) = LOWER_same{raw}()
prfn control_lower_shift {raw:int | 65 <= raw; raw <= 90} (): LOWER(raw, raw + 32) = LOWER_shift{raw}()
