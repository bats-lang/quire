#include "share/atspre_staload.hats"
(* quire src/cut.bats CONTINUES, copied: see gen_guards.py.
   False variant: the guard atom `128 <= code` of CONTINUES_byte shifted by 1: `128 <= (code) + 1` *)
dataprop CONTINUES(int) =
  | {code:int | 128 <= code; code < 192} CONTINUES_byte(code)

prfn probe_128_le_code {code:int | 128 <= (code) + 1; code < 192} (): CONTINUES(code) = CONTINUES_byte{code}()
