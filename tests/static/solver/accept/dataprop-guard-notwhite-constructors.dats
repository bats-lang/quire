#include "share/atspre_staload.hats"
(* quire src/cut.bats NOTWHITE, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

prfn control_notwhite_below {code:int | code <= 8} (): NOTWHITE(code) = NOTWHITE_below{code}()
prfn control_notwhite_middle {code:int | 11 <= code; code <= 31} (): NOTWHITE(code) = NOTWHITE_middle{code}()
prfn control_notwhite_above {code:int | 33 <= code} (): NOTWHITE(code) = NOTWHITE_above{code}()
