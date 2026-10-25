#include "share/atspre_staload.hats"
(* src/cut.bats BREAKBACK, copied: see gen_guards.py.
   Probe: every guard of BREAKBACK_other holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop WHITE(int) =
  | WHITE_space(32)
  | WHITE_tab(9)
  | WHITE_line_feed(10)

dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

dataprop BREAKBACK(cells, int, int, int, int) =
  | {cs:cells}{offset,floor:int} BREAKBACK_start(cs, offset, 0, floor, ~1)
  | {cs:cells}{offset,at,floor:int | 1 <= at; at <= floor} BREAKBACK_floor(cs, offset, at, floor, ~1)
  | {cs:cells}{offset:nat}{at,floor,code:int | 1 <= at; floor < at}
    BREAKBACK_white(cs, offset, at, floor, at + 1) of (NTH(cs, offset + at, code), WHITE(code))
  | {cs:cells}{offset:nat}{at,floor,code,back:int | 1 <= at; floor < at}
    BREAKBACK_other(cs, offset, at, floor, back) of (NTH(cs, offset + at, code), NOTWHITE(code), BREAKBACK(cs, offset, at - 1, floor, back))

prfn satisfiable_breakback_other {cs:cells}{offset:nat}{at,floor,code,back:int | 1 <= at; floor < at} (): [1 == 2] void = ()
