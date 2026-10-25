#include "share/atspre_staload.hats"
(* src/text_relation.bats ISENCODING, copied: see gen_guards.py.
   Probe: every guard of ISENCODING_no holds of some values, so `[1 == 2] void` under them is false and rejected *)
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

prfn satisfiable_isencoding_no {cells:cells}{i:nat}{b0,b1,b2,b3,b4,b5,b6,b7:int | b0 != 101 || b1 != 110 || b2 != 99 || b3 != 111 || b4 != 100 || b5 != 105 || b6 != 110 || b7 != 103} (): [1 == 2] void = ()
