#include "share/atspre_staload.hats"
(* quire src/record.bats MAGICDIFF, copied: see gen_guards.py.
   False variant: the guard atom `0 <= magic2` of MAGICDIFF_mk shifted by 1: `0 <= (magic2) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop MAGICDIFF(bytes) =
  | {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= magic2; magic2 < 256; 0 <= magic3; magic3 < 256;
       magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67}
    MAGICDIFF_mk(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil())))))

prfn probe_0_le_magic2 {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= (magic2) + 1; magic2 < 256; 0 <= magic3; magic3 < 256; magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67} (): MAGICDIFF(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil()))))) = MAGICDIFF_mk{magic0,magic1,magic2,magic3}()
