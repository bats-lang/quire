#include "share/atspre_staload.hats"
(* css:src/harmony.bats MXMN, copied: see gen_guards.py.
   Probe: every guard of MXMN_grb holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop RGB(int, int, int, int) =
  | {r,g,b:nat | r < 256; g < 256; b < 256} RGBc(r * 65536 + g * 256 + b, r, g, b)

dataprop MXMN(int, int, int) =
  | {c,r,g,b:int | r >= g; g >= b} MXMN_rgb(c, r, b) of RGB(c, r, g, b)
  | {c,r,g,b:int | r >= b; b >= g} MXMN_rbg(c, r, g) of RGB(c, r, g, b)
  | {c,r,g,b:int | g >= r; r >= b} MXMN_grb(c, g, b) of RGB(c, r, g, b)
  | {c,r,g,b:int | g >= b; b >= r} MXMN_gbr(c, g, r) of RGB(c, r, g, b)
  | {c,r,g,b:int | b >= r; r >= g} MXMN_brg(c, b, g) of RGB(c, r, g, b)
  | {c,r,g,b:int | b >= g; g >= r} MXMN_bgr(c, b, r) of RGB(c, r, g, b)

prfn satisfiable_mxmn_grb {c,r,g,b:int | g >= r; r >= b} (): [1 == 2] void = ()
