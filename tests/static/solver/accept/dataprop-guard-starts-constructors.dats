#include "share/atspre_staload.hats"
(* quire src/cut.bats STARTS, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
dataprop STARTS(int) =
  | {code:int | code < 128} STARTS_ascii(code)
  | {code:int | 192 <= code} STARTS_lead(code)

prfn control_starts_ascii {code:int | code < 128} (): STARTS(code) = STARTS_ascii{code}()
prfn control_starts_lead {code:int | 192 <= code} (): STARTS(code) = STARTS_lead{code}()
