#include "share/atspre_staload.hats"
(* quire src/text_relation.bats BYTEAT, copied: see gen_guards.py.
   False variant: the guard atom `i >= n` of BYTEAT_after shifted by 1: `(i) + 1 >= n` *)
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

prfn probe_i_ge_n {cells:cells}{n:nat}{i:int | (i) + 1 >= n} (premise1: CLEN(cells, n)): BYTEAT(cells, i, ~1) = BYTEAT_after{cells}{n}{i}(premise1)
