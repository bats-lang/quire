#include "share/atspre_staload.hats"
(* quire src/cut.bats CONTINUES, copied: see gen_guards.py.
   False variant: the guard atom `code < 192` of CONTINUES_byte shifted by 1: `code < (192) + 1` *)
dataprop CONTINUES(int) =
  | {code:int | 128 <= code; code < 192} CONTINUES_byte(code)

prfn probe_code_lt_192 {code:int | 128 <= code; code < (192) + 1} (): CONTINUES(code) = CONTINUES_byte{code}()
