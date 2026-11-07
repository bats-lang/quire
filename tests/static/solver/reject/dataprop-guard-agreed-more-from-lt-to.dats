#include "share/atspre_staload.hats"
(* quire src/text_proved.bats AGREED, copied: see gen_guards.py.
   False variant: the guard atom `from < to` of AGREED_more shifted by 1: `from < (to) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop AGREED(cells, cells, int, int) =
  | {first,second:cells}{to:nat} AGREED_end(first, second, to, to)
  | {first,second:cells}{from,to:nat | from < to}{value:int}
    AGREED_more(first, second, from, to) of (NTH(first, from, value), NTH(second, from, value), AGREED(first, second, from + 1, to))

prfn probe_from_lt_to {first,second:cells}{from,to:nat | from < (to) + 1}{value:int} (premise1: NTH(first, from, value), premise2: NTH(second, from, value), premise3: AGREED(first, second, from + 1, to)): AGREED(first, second, from, to) = AGREED_more{first,second}{from,to}{value}(premise1, premise2, premise3)
