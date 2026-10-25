#include "share/atspre_staload.hats"
(* src/text_relation.bats DIFFFROM, copied: see gen_guards.py.
   Probe: every guard of DIFFFROM_head holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop LOWER(int, int) =
  | {raw:int | raw < 65 || 90 < raw} LOWER_same(raw, raw)
  | {raw:int | 65 <= raw; raw <= 90} LOWER_shift(raw, raw + 32)

dataprop DIFFFROM(cells, int, bytes) =
  | {cells:cells}{from:nat}{raw,low,expected:int | low != expected}{rest:bytes}
    DIFFFROM_head(cells, from, bcons(expected, rest)) of (NTH(cells, from, raw), LOWER(raw, low))
  | {cells:cells}{from:nat}{raw,expected:int}{rest:bytes}
    DIFFFROM_tail(cells, from, bcons(expected, rest)) of (NTH(cells, from, raw), LOWER(raw, expected), DIFFFROM(cells, from + 1, rest))

prfn satisfiable_difffrom_head {cells:cells}{from:nat}{raw,low,expected:int | low != expected}{rest:bytes} (): [1 == 2] void = ()
