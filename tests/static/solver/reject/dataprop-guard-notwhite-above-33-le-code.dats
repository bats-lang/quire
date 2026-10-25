#include "share/atspre_staload.hats"
(* quire src/cut.bats NOTWHITE, copied: see gen_guards.py.
   False variant: the guard atom `33 <= code` of NOTWHITE_above shifted by 1: `33 <= (code) + 1` *)
dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

prfn probe_33_le_code {code:int | 33 <= (code) + 1} (): NOTWHITE(code) = NOTWHITE_above{code}()
