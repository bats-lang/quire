#include "share/atspre_staload.hats"
(* quire src/record.bats MAGICDIFF, copied: see gen_guards.py.
   False variant: the guard atom `magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67` of MAGICDIFF_mk shifted by 1: `dropped` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop MAGICDIFF(bytes) =
  | {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= magic2; magic2 < 256; 0 <= magic3; magic3 < 256;
       magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67}
    MAGICDIFF_mk(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil())))))

prfn probe_magic0_ne_81_or_magic1_ne_82_or_magic2_ne_69_or_magic3_ne_67 {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= magic2; magic2 < 256; 0 <= magic3; magic3 < 256} (): MAGICDIFF(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil()))))) = MAGICDIFF_mk{magic0,magic1,magic2,magic3}()
