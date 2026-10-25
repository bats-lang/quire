#include "share/atspre_staload.hats"
(* quire src/text_relation.bats UNIT16, copied: see gen_guards.py.
   False variant: the guard atom `second < 256` of UNIT16_be shifted by 1: `second < (256) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

datasort byteorder = LittleEndian of () | BigEndian of ()

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop UNIT16(cells, byteorder, int, int) =
  | {cells:cells}{i:nat}{first,second:int | 0 <= first; first < 256; 0 <= second; second < 256}
    UNIT16_le(cells, LittleEndian(), i, first + 256 * second) of (NTH(cells, i, first), NTH(cells, i + 1, second))
  | {cells:cells}{i:nat}{first,second:int | 0 <= first; first < 256; 0 <= second; second < 256}
    UNIT16_be(cells, BigEndian(), i, 256 * first + second) of (NTH(cells, i, first), NTH(cells, i + 1, second))

prfn probe_second_lt_256 {cells:cells}{i:nat}{first,second:int | 0 <= first; first < 256; 0 <= second; second < (256) + 1} (premise1: NTH(cells, i, first), premise2: NTH(cells, i + 1, second)): UNIT16(cells, BigEndian(), i, 256 * first + second) = UNIT16_be{cells}{i}{first,second}(premise1, premise2)
