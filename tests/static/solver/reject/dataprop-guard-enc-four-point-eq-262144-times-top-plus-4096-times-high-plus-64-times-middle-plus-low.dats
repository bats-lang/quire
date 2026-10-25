#include "share/atspre_staload.hats"
(* quire src/text_relation.bats ENC, copied: see gen_guards.py.
   False variant: the guard atom `point == 262144 * top + 4096 * high + 64 * middle + low` of ENC_four shifted by 1: `point <= (262144 * top + 4096 * high + 64 * middle + low) + 1` *)
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

prfn probe_point_eq_262144_times_top_plus_4096_times_high_plus_64_times_middle_plus_low {point,top,high,middle,low:int | 0 <= top; top < 5; 0 <= high; high < 64; 0 <= middle; middle < 64; 0 <= low; low < 64; 65536 <= point; point <= (262144 * top + 4096 * high + 64 * middle + low) + 1} (): ENC(point, bcons(240 + top, bcons(128 + high, bcons(128 + middle, bcons(128 + low, bnil()))))) = ENC_four{point,top,high,middle,low}()
