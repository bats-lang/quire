#include "share/atspre_staload.hats"
(* quire src/cut.bats NOTWHITE, copied: see gen_guards.py.
   False variant: the guard atom `11 <= code` of NOTWHITE_middle shifted by 1: `11 <= (code) + 1` *)
dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

prfn probe_11_le_code {code:int | 11 <= (code) + 1; code <= 31} (): NOTWHITE(code) = NOTWHITE_middle{code}()
