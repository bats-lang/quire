#include "share/atspre_staload.hats"
(* quire src/crc.bats ENTRY, copied: see gen_guards.py.
   False variant: the guard atom `0 <= high0` of ENTRY_mk shifted by 1: `0 <= (high0) + 1` *)
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

prfn probe_0_le_high0 {ct:cells}{k:nat}{low0,low1,high0,high1:int | 0 <= low0; low0 < 256; 0 <= low1; low1 < 256; 0 <= (high0) + 1; high0 < 256; 0 <= high1; high1 < 256} (premise1: NTH(ct, 4*k, low0), premise2: NTH(ct, 4*k + 1, low1), premise3: NTH(ct, 4*k + 2, high0), premise4: NTH(ct, 4*k + 3, high1)): ENTRY(ct, k, high0 + 256*high1, low0 + 256*low1) = ENTRY_mk{ct}{k}{low0,low1,high0,high1}(premise1, premise2, premise3, premise4)
