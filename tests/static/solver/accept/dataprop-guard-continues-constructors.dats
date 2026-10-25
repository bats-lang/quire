#include "share/atspre_staload.hats"
(* quire src/cut.bats CONTINUES, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
dataprop CONTINUES(int) =
  | {code:int | 128 <= code; code < 192} CONTINUES_byte(code)

prfn control_continues_byte {code:int | 128 <= code; code < 192} (): CONTINUES(code) = CONTINUES_byte{code}()
