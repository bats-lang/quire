#include "share/atspre_staload.hats"
(* quire src/text_relation.bats UTF8SCAN, copied: see gen_guards.py.
   False variant: the guard atom `from <= n` of UTF8SCAN_ascii shifted by 1: `from <= (n) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

datasort scanned = ScannedRefused of () | ScannedAscii of () | ScannedWide of ()

dataprop CLEN(cells, int) =
  | CLEN_nil(cnil(), 0)
  | {c:int}{cs:cells}{n:nat} CLEN_cons(ccons(c, cs), n + 1) of CLEN(cs, n)

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

dataprop UTF8SCAN(cells, int, scanned) =
  | {cells:cells}{from,n:nat | from <= n}
    UTF8SCAN_ascii(cells, from, ScannedAscii()) of (CLEN(cells, n), UTF8RUN(cells, from, n, SpreadAscii()))
  | {cells:cells}{from,n:nat | from <= n}
    UTF8SCAN_wide(cells, from, ScannedWide()) of (CLEN(cells, n), UTF8RUN(cells, from, n, SpreadWide()))
  | {cells:cells}{from,bad_at:nat | from <= bad_at}{leading_spread:spread}
    UTF8SCAN_bad(cells, from, ScannedRefused()) of (UTF8RUN(cells, from, bad_at, leading_spread), UTF8BAD(cells, bad_at))

prfn probe_from_le_n {cells:cells}{from,n:nat | from <= (n) + 1} (premise1: CLEN(cells, n), premise2: UTF8RUN(cells, from, n, SpreadAscii())): UTF8SCAN(cells, from, ScannedAscii()) = UTF8SCAN_ascii{cells}{from,n}(premise1, premise2)
