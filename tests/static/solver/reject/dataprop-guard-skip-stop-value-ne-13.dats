#include "share/atspre_staload.hats"
(* quire src/text_relation.bats SKIP, copied: see gen_guards.py.
   False variant: the guard atom `value != 13` of SKIP_stop shifted by 1: `dropped` *)
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

dataprop CLEN(cells, int) =
  | CLEN_nil(cnil(), 0)
  | {c:int}{cs:cells}{n:nat} CLEN_cons(ccons(c, cs), n + 1) of CLEN(cs, n)

dataprop BYTEAT(cells, int, int) =
  | {cells:cells}{i:nat}{value:int} BYTEAT_in(cells, i, value) of NTH(cells, i, value)
  | {cells:cells}{i:int | i < 0} BYTEAT_before(cells, i, ~1)
  | {cells:cells}{n:nat}{i:int | i >= n} BYTEAT_after(cells, i, ~1) of CLEN(cells, n)

dataprop SKIP(cells, int, int) =
  | {cells:cells}{from,to:nat}{value:int | value != 32; value != 9; value != 10; value != 13}
    SKIP_stop(cells, from, to) of (BLANKS(cells, from, to), BYTEAT(cells, to, value))

prfn probe_value_ne_13 {cells:cells}{from,to:nat}{value:int | value != 32; value != 9; value != 10} (premise1: BLANKS(cells, from, to), premise2: BYTEAT(cells, to, value)): SKIP(cells, from, to) = SKIP_stop{cells}{from,to}{value}(premise1, premise2)
