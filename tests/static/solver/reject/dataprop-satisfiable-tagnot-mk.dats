#include "share/atspre_staload.hats"
(* src/seq.bats TAGNOT, copied: see gen_guards.py.
   Probe: every guard of TAGNOT_mk holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop TAGNOT(bytes) =
  | {tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte:int | 0 <= tag_first_byte; tag_first_byte < 256; 0 <= tag_second_byte; tag_second_byte < 256; 0 <= tag_third_byte; tag_third_byte < 256; 0 <= tag_fourth_byte; tag_fourth_byte < 256;
       tag_first_byte != 73 || tag_second_byte != 69 || tag_third_byte != 78 || tag_fourth_byte != 68}
    TAGNOT_mk(bcons(tag_first_byte, bcons(tag_second_byte, bcons(tag_third_byte, bcons(tag_fourth_byte, bnil())))))

prfn satisfiable_tagnot_mk {tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte:int | 0 <= tag_first_byte; tag_first_byte < 256; 0 <= tag_second_byte; tag_second_byte < 256; 0 <= tag_third_byte; tag_third_byte < 256; 0 <= tag_fourth_byte; tag_fourth_byte < 256; tag_first_byte != 73 || tag_second_byte != 69 || tag_third_byte != 78 || tag_fourth_byte != 68} (): [1 == 2] void = ()
