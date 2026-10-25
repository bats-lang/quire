#include "share/atspre_staload.hats"
(* quire src/schema.bats CRIT, copied: see gen_guards.py.
   False variant: the guard atom `fourth_letter < 256` of CRIT_mk shifted by 1: `fourth_letter < (256) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop CRIT(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 0 <= first_letter; first_letter < 97; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    CRIT_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

prfn probe_fourth_letter_lt_256 {first_letter,second_letter,third_letter,fourth_letter:int | 0 <= first_letter; first_letter < 97; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < (256) + 1} (): CRIT(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil()))))) = CRIT_mk{first_letter,second_letter,third_letter,fourth_letter}()
