#include "share/atspre_staload.hats"
(* quire src/text_relation.bats UTF8STEP, copied: see gen_guards.py.
   False variant: the guard atom `lead < 128` of UTF8STEP_one shifted by 1: `lead < (128) + 1` *)
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

prfn probe_lead_lt_128 {cells:cells}{i:nat}{lead:int | 0 <= lead; lead < (128) + 1} (premise1: NTH(cells, i, lead)): UTF8STEP(cells, i, i + 1, SpreadAscii()) = UTF8STEP_one{cells}{i}{lead}(premise1)
