#include "share/atspre_staload.hats"
(* quire src/text_relation.bats UTF8RUN, copied: see gen_guards.py.
   False variant: the guard atom `next <= to` of UTF8RUN_wide shifted by 1: `next <= (to) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

datasort spread = SpreadAscii of () | SpreadWide of ()

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop UTF8STEP(cells, int, int, spread) =
  | {cells:cells}{i:nat}{lead:int | 0 <= lead; lead < 128}
    UTF8STEP_one(cells, i, i + 1, SpreadAscii()) of NTH(cells, i, lead)
  | {cells:cells}{i:nat}{lead,first:int | 194 <= lead; lead < 224; 128 <= first; first < 192}
    UTF8STEP_two(cells, i, i + 2, SpreadWide()) of (NTH(cells, i, lead), NTH(cells, i + 1, first))
  | {cells:cells}{i:nat}{lead,first,second:int | 224 <= lead; lead < 240; 128 <= first; first < 192;
        lead != 224 || 160 <= first; lead != 237 || first < 160; 128 <= second; second < 192}
    UTF8STEP_three(cells, i, i + 3, SpreadWide()) of (NTH(cells, i, lead), NTH(cells, i + 1, first), NTH(cells, i + 2, second))
  | {cells:cells}{i:nat}{lead,first,second,third:int | 240 <= lead; lead < 245; 128 <= first; first < 192;
        lead != 240 || 144 <= first; lead != 244 || first < 144; 128 <= second; second < 192; 128 <= third; third < 192}
    UTF8STEP_four(cells, i, i + 4, SpreadWide()) of (NTH(cells, i, lead), NTH(cells, i + 1, first), NTH(cells, i + 2, second), NTH(cells, i + 3, third))

dataprop UTF8RUN(cells, int, int, spread) =
  | {cells:cells}{i:nat} UTF8RUN_empty(cells, i, i, SpreadAscii())
  | {cells:cells}{i,next,to:nat | i < next; next <= to}{spread:spread}
    UTF8RUN_ascii(cells, i, to, spread) of (UTF8STEP(cells, i, next, SpreadAscii()), UTF8RUN(cells, next, to, spread))
  | {cells:cells}{i,next,to:nat | i < next; next <= to}{rest_spread:spread}
    UTF8RUN_wide(cells, i, to, SpreadWide()) of (UTF8STEP(cells, i, next, SpreadWide()), UTF8RUN(cells, next, to, rest_spread))

prfn probe_next_le_to {cells:cells}{i,next,to:nat | i < next; next <= (to) + 1}{rest_spread:spread} (premise1: UTF8STEP(cells, i, next, SpreadWide()), premise2: UTF8RUN(cells, next, to, rest_spread)): UTF8RUN(cells, i, to, SpreadWide()) = UTF8RUN_wide{cells}{i,next,to}{rest_spread}(premise1, premise2)
