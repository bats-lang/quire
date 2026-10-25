#include "share/atspre_staload.hats"
(* quire src/text_relation.bats BLANKS, copied: see gen_guards.py.
   False variant: the guard atom `i < to` of BLANKS_more shifted by 1: `i < (to) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop BLANKS(cells, int, int) =
  | {cells:cells}{i:nat} BLANKS_none(cells, i, i)
  | {cells:cells}{i,to:nat | i < to}{value:int | value == 32 || value == 9 || value == 10 || value == 13}
    BLANKS_more(cells, i, to) of (NTH(cells, i, value), BLANKS(cells, i + 1, to))

prfn probe_i_lt_to {cells:cells}{i,to:nat | i < (to) + 1}{value:int | value == 32 || value == 9 || value == 10 || value == 13} (premise1: NTH(cells, i, value), premise2: BLANKS(cells, i + 1, to)): BLANKS(cells, i, to) = BLANKS_more{cells}{i,to}{value}(premise1, premise2)
