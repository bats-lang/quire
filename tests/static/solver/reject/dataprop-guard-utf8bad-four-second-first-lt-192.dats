#include "share/atspre_staload.hats"
(* quire src/text_relation.bats UTF8BAD, copied: see gen_guards.py.
   False variant: the guard atom `first < 192` of UTF8BAD_four_second shifted by 1: `first < (192) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop CLEN(cells, int) =
  | CLEN_nil(cnil(), 0)
  | {c:int}{cs:cells}{n:nat} CLEN_cons(ccons(c, cs), n + 1) of CLEN(cs, n)

dataprop BYTEAT(cells, int, int) =
  | {cells:cells}{i:nat}{value:int} BYTEAT_in(cells, i, value) of NTH(cells, i, value)
  | {cells:cells}{i:int | i < 0} BYTEAT_before(cells, i, ~1)
  | {cells:cells}{n:nat}{i:int | i >= n} BYTEAT_after(cells, i, ~1) of CLEN(cells, n)

dataprop UTF8BAD(cells, int) =
  | {cells:cells}{i:nat}{lead:int | 128 <= lead; lead < 194 || 245 <= lead}
    UTF8BAD_lead(cells, i) of NTH(cells, i, lead)
  | {cells:cells}{i:nat}{lead,first:int | 194 <= lead; lead < 224; first < 128 || 192 <= first}
    UTF8BAD_two(cells, i) of (NTH(cells, i, lead), BYTEAT(cells, i + 1, first))
  | {cells:cells}{i:nat}{lead,first:int | 224 <= lead; lead < 240;
        first < 128 || 192 <= first || (lead == 224 && first < 160) || (lead == 237 && 160 <= first)}
    UTF8BAD_three_first(cells, i) of (NTH(cells, i, lead), BYTEAT(cells, i + 1, first))
  | {cells:cells}{i:nat}{lead,first,second:int | 224 <= lead; lead < 240; 128 <= first; first < 192;
        lead != 224 || 160 <= first; lead != 237 || first < 160; second < 128 || 192 <= second}
    UTF8BAD_three_second(cells, i) of (NTH(cells, i, lead), NTH(cells, i + 1, first), BYTEAT(cells, i + 2, second))
  | {cells:cells}{i:nat}{lead,first:int | 240 <= lead; lead < 245;
        first < 128 || 192 <= first || (lead == 240 && first < 144) || (lead == 244 && 144 <= first)}
    UTF8BAD_four_first(cells, i) of (NTH(cells, i, lead), BYTEAT(cells, i + 1, first))
  | {cells:cells}{i:nat}{lead,first,second:int | 240 <= lead; lead < 245; 128 <= first; first < 192;
        lead != 240 || 144 <= first; lead != 244 || first < 144; second < 128 || 192 <= second}
    UTF8BAD_four_second(cells, i) of (NTH(cells, i, lead), NTH(cells, i + 1, first), BYTEAT(cells, i + 2, second))
  | {cells:cells}{i:nat}{lead,first,second,third:int | 240 <= lead; lead < 245; 128 <= first; first < 192;
        lead != 240 || 144 <= first; lead != 244 || first < 144; 128 <= second; second < 192; third < 128 || 192 <= third}
    UTF8BAD_four_third(cells, i) of (NTH(cells, i, lead), NTH(cells, i + 1, first), NTH(cells, i + 2, second), BYTEAT(cells, i + 3, third))

prfn probe_first_lt_192 {cells:cells}{i:nat}{lead,first,second:int | 240 <= lead; lead < 245; 128 <= first; first < (192) + 1; lead != 240 || 144 <= first; lead != 244 || first < 144; second < 128 || 192 <= second} (premise1: NTH(cells, i, lead), premise2: NTH(cells, i + 1, first), premise3: BYTEAT(cells, i + 2, second)): UTF8BAD(cells, i) = UTF8BAD_four_second{cells}{i}{lead,first,second}(premise1, premise2, premise3)
