#include "share/atspre_staload.hats"
(* quire src/text_relation.bats NOQUOTE, copied: see gen_guards.py.
   False variant: the guard atom `value != quote` of NOQUOTE_more shifted by 1: `dropped` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop NOQUOTE(cells, int, int, int) =
  | {cells:cells}{quote:int}{i:nat} NOQUOTE_none(cells, quote, i, i)
  | {cells:cells}{quote:int}{i,to:nat | i < to}{value:int | value != quote}
    NOQUOTE_more(cells, quote, i, to) of (NTH(cells, i, value), NOQUOTE(cells, quote, i + 1, to))

prfn probe_value_ne_quote {cells:cells}{quote:int}{i,to:nat | i < to}{value:int} (premise1: NTH(cells, i, value), premise2: NOQUOTE(cells, quote, i + 1, to)): NOQUOTE(cells, quote, i, to) = NOQUOTE_more{cells}{quote}{i,to}{value}(premise1, premise2)
