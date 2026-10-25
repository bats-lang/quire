#include "share/atspre_staload.hats"
(* src/schema.bats CRIT, copied: see gen_guards.py.
   Probe: every guard of CRIT_mk holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop CRIT(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 0 <= first_letter; first_letter < 97; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    CRIT_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

prfn satisfiable_crit_mk {first_letter,second_letter,third_letter,fourth_letter:int | 0 <= first_letter; first_letter < 97; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256} (): [1 == 2] void = ()
