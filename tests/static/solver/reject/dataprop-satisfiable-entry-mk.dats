#include "share/atspre_staload.hats"
(* src/crc.bats ENTRY, copied: see gen_guards.py.
   Probe: every guard of ENTRY_mk holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop ENTRY(cells, int, int, int) =
  | {ct:cells}{k:nat}{low0,low1,high0,high1:int | 0 <= low0; low0 < 256; 0 <= low1; low1 < 256; 0 <= high0; high0 < 256; 0 <= high1; high1 < 256}
    ENTRY_mk(ct, k, high0 + 256*high1, low0 + 256*low1)
      of (NTH(ct, 4*k, low0), NTH(ct, 4*k + 1, low1), NTH(ct, 4*k + 2, high0), NTH(ct, 4*k + 3, high1))

prfn satisfiable_entry_mk {ct:cells}{k:nat}{low0,low1,high0,high1:int | 0 <= low0; low0 < 256; 0 <= low1; low1 < 256; 0 <= high0; high0 < 256; 0 <= high1; high1 < 256} (): [1 == 2] void = ()
