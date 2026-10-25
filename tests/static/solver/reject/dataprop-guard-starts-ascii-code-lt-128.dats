#include "share/atspre_staload.hats"
(* quire src/cut.bats STARTS, copied: see gen_guards.py.
   False variant: the guard atom `code < 128` of STARTS_ascii shifted by 1: `code < (128) + 1` *)
dataprop STARTS(int) =
  | {code:int | code < 128} STARTS_ascii(code)
  | {code:int | 192 <= code} STARTS_lead(code)

prfn probe_code_lt_128 {code:int | code < (128) + 1} (): STARTS(code) = STARTS_ascii{code}()
