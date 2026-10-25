#include "share/atspre_staload.hats"
(* css:src/harmony.bats SATNEAR, copied: see gen_guards.py.
   Probe: every guard of SATNEARc holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop RGB(int, int, int, int) =
  | {r,g,b:nat | r < 256; g < 256; b < 256} RGBc(r * 65536 + g * 256 + b, r, g, b)

dataprop MXMN(int, int, int) =
  | {c,r,g,b:int | r >= g; g >= b} MXMN_rgb(c, r, b) of RGB(c, r, g, b)
  | {c,r,g,b:int | r >= b; b >= g} MXMN_rbg(c, r, g) of RGB(c, r, g, b)
  | {c,r,g,b:int | g >= r; r >= b} MXMN_grb(c, g, b) of RGB(c, r, g, b)
  | {c,r,g,b:int | g >= b; b >= r} MXMN_gbr(c, g, r) of RGB(c, r, g, b)
  | {c,r,g,b:int | b >= r; r >= g} MXMN_brg(c, b, g) of RGB(c, r, g, b)
  | {c,r,g,b:int | b >= g; g >= r} MXMN_bgr(c, b, r) of RGB(c, r, g, b)

dataprop SATNEAR(int, int, int) =
  | {a,b,d,amx,amn,bmx,bmn:int | amx > 0; bmx > 0;
      100 * ((amx - amn) * bmx - (bmx - bmn) * amx) <= d * amx * bmx;
      100 * ((bmx - bmn) * amx - (amx - amn) * bmx) <= d * amx * bmx}
    SATNEARc(a, b, d) of (MXMN(a, amx, amn), MXMN(b, bmx, bmn))

prfn satisfiable_satnearc {a,b,d,amx,amn,bmx,bmn:int | amx > 0; bmx > 0; 100 * ((amx - amn) * bmx - (bmx - bmn) * amx) <= d * amx * bmx; 100 * ((bmx - bmn) * amx - (amx - amn) * bmx) <= d * amx * bmx} (): [1 == 2] void = ()
