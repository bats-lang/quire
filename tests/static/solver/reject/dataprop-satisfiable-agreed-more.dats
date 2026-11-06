#include "share/atspre_staload.hats"
(* src/text_proved.bats AGREED, copied: see gen_guards.py.
   Probe: every guard of AGREED_more holds of some values, so `[1 == 2] void` under them is false and rejected *)
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

prfn satisfiable_agreed_more {first,second:cells}{from,to:nat | from < to}{value:int} (): [1 == 2] void = ()
