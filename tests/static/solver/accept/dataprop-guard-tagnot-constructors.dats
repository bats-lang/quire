#include "share/atspre_staload.hats"
(* quire src/seq.bats TAGNOT, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop TAGNOT(bytes) =
  | {tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte:int | 0 <= tag_first_byte; tag_first_byte < 256; 0 <= tag_second_byte; tag_second_byte < 256; 0 <= tag_third_byte; tag_third_byte < 256; 0 <= tag_fourth_byte; tag_fourth_byte < 256;
       tag_first_byte != 73 || tag_second_byte != 69 || tag_third_byte != 78 || tag_fourth_byte != 68}
    TAGNOT_mk(bcons(tag_first_byte, bcons(tag_second_byte, bcons(tag_third_byte, bcons(tag_fourth_byte, bnil())))))

prfn control_tagnot_mk {tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte:int | 0 <= tag_first_byte; tag_first_byte < 256; 0 <= tag_second_byte; tag_second_byte < 256; 0 <= tag_third_byte; tag_third_byte < 256; 0 <= tag_fourth_byte; tag_fourth_byte < 256; tag_first_byte != 73 || tag_second_byte != 69 || tag_third_byte != 78 || tag_fourth_byte != 68} (): TAGNOT(bcons(tag_first_byte, bcons(tag_second_byte, bcons(tag_third_byte, bcons(tag_fourth_byte, bnil()))))) = TAGNOT_mk{tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte}()
