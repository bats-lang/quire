#include "share/atspre_staload.hats"
(* quire src/cut.bats NOTWHITE, copied: see gen_guards.py.
   False variant: the guard atom `code <= 31` of NOTWHITE_middle shifted by 1: `code <= (31) + 1` *)
dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

prfn probe_code_le_31 {code:int | 11 <= code; code <= (31) + 1} (): NOTWHITE(code) = NOTWHITE_middle{code}()
