#include "share/atspre_staload.hats"
(* src/text_relation.bats LABELDIFF, copied: see gen_guards.py.
   Probe: every guard of LABELDIFF_length holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

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

dataprop LABELDIFF(cells, int, int, bytes) =
  | {cells:cells}{from,count:nat}{label:bytes}{label_count:nat | label_count != count}
    LABELDIFF_length(cells, from, count, label) of LEN(label, label_count)
  | {cells:cells}{from,count:nat}{label:bytes}
    LABELDIFF_byte(cells, from, count, label) of DIFFFROM(cells, from, label)

prfn satisfiable_labeldiff_length {cells:cells}{from,count:nat}{label:bytes}{label_count:nat | label_count != count} (): [1 == 2] void = ()
