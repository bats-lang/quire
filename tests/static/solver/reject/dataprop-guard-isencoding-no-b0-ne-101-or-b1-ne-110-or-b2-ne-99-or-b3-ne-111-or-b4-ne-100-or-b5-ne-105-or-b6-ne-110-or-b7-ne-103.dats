#include "share/atspre_staload.hats"
(* quire src/text_relation.bats ISENCODING, copied: see gen_guards.py.
   False variant: the guard atom `b0 != 101 || b1 != 110 || b2 != 99 || b3 != 111 || b4 != 100 || b5 != 105 || b6 != 110 || b7 != 103` of ISENCODING_no shifted by 1: `dropped` *)
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

dataprop ISENCODING(cells, int, bool) =
  | {cells:cells}{i:nat}
    ISENCODING_yes(cells, i, true) of (NTH(cells, i, 101), NTH(cells, i + 1, 110), NTH(cells, i + 2, 99), NTH(cells, i + 3, 111),
      NTH(cells, i + 4, 100), NTH(cells, i + 5, 105), NTH(cells, i + 6, 110), NTH(cells, i + 7, 103))
  | {cells:cells}{i:nat}{b0,b1,b2,b3,b4,b5,b6,b7:int | b0 != 101 || b1 != 110 || b2 != 99 || b3 != 111 || b4 != 100 || b5 != 105 || b6 != 110 || b7 != 103}
    ISENCODING_no(cells, i, false) of (BYTEAT(cells, i, b0), BYTEAT(cells, i + 1, b1), BYTEAT(cells, i + 2, b2), BYTEAT(cells, i + 3, b3),
      BYTEAT(cells, i + 4, b4), BYTEAT(cells, i + 5, b5), BYTEAT(cells, i + 6, b6), BYTEAT(cells, i + 7, b7))

prfn probe_b0_ne_101_or_b1_ne_110_or_b2_ne_99_or_b3_ne_111_or_b4_ne_100_or_b5_ne_105_or_b6_ne_110_or_b7_ne_103 {cells:cells}{i:nat}{b0,b1,b2,b3,b4,b5,b6,b7:int} (premise1: BYTEAT(cells, i, b0), premise2: BYTEAT(cells, i + 1, b1), premise3: BYTEAT(cells, i + 2, b2), premise4: BYTEAT(cells, i + 3, b3), premise5: BYTEAT(cells, i + 4, b4), premise6: BYTEAT(cells, i + 5, b5), premise7: BYTEAT(cells, i + 6, b6), premise8: BYTEAT(cells, i + 7, b7)): ISENCODING(cells, i, false) = ISENCODING_no{cells}{i}{b0,b1,b2,b3,b4,b5,b6,b7}(premise1, premise2, premise3, premise4, premise5, premise6, premise7, premise8)
