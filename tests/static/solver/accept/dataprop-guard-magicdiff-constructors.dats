#include "share/atspre_staload.hats"
(* quire src/record.bats MAGICDIFF, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop MAGICDIFF(bytes) =
  | {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= magic2; magic2 < 256; 0 <= magic3; magic3 < 256;
       magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67}
    MAGICDIFF_mk(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil())))))

prfn control_magicdiff_mk {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= magic2; magic2 < 256; 0 <= magic3; magic3 < 256; magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67} (): MAGICDIFF(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil()))))) = MAGICDIFF_mk{magic0,magic1,magic2,magic3}()
