#include "share/atspre_staload.hats"
(* quire src/cut.bats STARTS, copied: see gen_guards.py.
   False variant: the guard atom `192 <= code` of STARTS_lead shifted by 1: `192 <= (code) + 1` *)
dataprop STARTS(int) =
  | {code:int | code < 128} STARTS_ascii(code)
  | {code:int | 192 <= code} STARTS_lead(code)

prfn probe_192_le_code {code:int | 192 <= (code) + 1} (): STARTS(code) = STARTS_lead{code}()
