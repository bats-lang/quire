#include "share/atspre_staload.hats"
(* quire src/text_relation.bats ENC, copied: see gen_guards.py.
   Redundant guard atom `0 <= high` of ENC_three: the others imply it (2048 <= point and point == 4096 * high + 64 * middle + low with middle, low <= 63 leave no high below 0), so the constructor is still made with it shifted to `0 <= (high) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop ENC(int, bytes) =
  | {point:int | 0 <= point; point < 128} ENC_one(point, bcons(point, bnil()))
  | {point,high,low:int | 2 <= high; high < 32; 0 <= low; low < 64; point == 64 * high + low}
    ENC_two(point, bcons(192 + high, bcons(128 + low, bnil())))
  | {point,high,middle,low:int | 0 <= high; high < 16; 0 <= middle; middle < 64; 0 <= low; low < 64; 2048 <= point; point == 4096 * high + 64 * middle + low}
    ENC_three(point, bcons(224 + high, bcons(128 + middle, bcons(128 + low, bnil()))))
  | {point,top,high,middle,low:int | 0 <= top; top < 5; 0 <= high; high < 64; 0 <= middle; middle < 64; 0 <= low; low < 64; 65536 <= point; point == 262144 * top + 4096 * high + 64 * middle + low}
    ENC_four(point, bcons(240 + top, bcons(128 + high, bcons(128 + middle, bcons(128 + low, bnil())))))

prfn probe_0_le_high {point,high,middle,low:int | 0 <= (high) + 1; high < 16; 0 <= middle; middle < 64; 0 <= low; low < 64; 2048 <= point; point == 4096 * high + 64 * middle + low} (): ENC(point, bcons(224 + high, bcons(128 + middle, bcons(128 + low, bnil())))) = ENC_three{point,high,middle,low}()
