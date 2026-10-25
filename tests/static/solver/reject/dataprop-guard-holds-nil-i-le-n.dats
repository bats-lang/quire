#include "share/atspre_staload.hats"
(* quire src/bytesarr.bats HOLDS, copied: see gen_guards.py.
   False variant: the guard atom `i <= n` of HOLDS_nil shifted by 1: `i <= (n) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop CLEN(cells, int) =
  | CLEN_nil(cnil(), 0)
  | {c:int}{cs:cells}{n:nat} CLEN_cons(ccons(c, cs), n + 1) of CLEN(cs, n)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop HOLDS(cells, int, bytes, int) =
  | {cells:cells}{i:nat}{n:nat | i <= n} HOLDS_nil(cells, i, bnil(), 0) of CLEN(cells, n)
  | {cells:cells}{i:nat}{byte_value:int}{rest:bytes}{byte_count:nat}
    HOLDS_cons(cells, i, bcons(byte_value, rest), byte_count + 1) of (NTH(cells, i, byte_value), HOLDS(cells, i + 1, rest, byte_count))

prfn probe_i_le_n {cells:cells}{i:nat}{n:nat | i <= (n) + 1} (premise1: CLEN(cells, n)): HOLDS(cells, i, bnil(), 0) = HOLDS_nil{cells}{i}{n}(premise1)
