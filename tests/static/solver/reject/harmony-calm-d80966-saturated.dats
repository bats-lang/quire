#include "share/atspre_staload.hats"
(* css harmony (RGB .. HUE), copied: see gen_harmony.py *)
dataprop RGB(int, int, int, int) =
  | {r,g,b:nat | r < 256; g < 256; b < 256} RGBc(r * 65536 + g * 256 + b, r, g, b)

(* MXMN(c, mx, mn): c's brightest and darkest channels *)
dataprop MXMN(int, int, int) =
  | {c,r,g,b:int | r >= g; g >= b} MXMN_rgb(c, r, b) of RGB(c, r, g, b)
  | {c,r,g,b:int | r >= b; b >= g} MXMN_rbg(c, r, g) of RGB(c, r, g, b)
  | {c,r,g,b:int | g >= r; r >= b} MXMN_grb(c, g, b) of RGB(c, r, g, b)
  | {c,r,g,b:int | g >= b; b >= r} MXMN_gbr(c, g, r) of RGB(c, r, g, b)
  | {c,r,g,b:int | b >= r; r >= g} MXMN_brg(c, b, g) of RGB(c, r, g, b)
  | {c,r,g,b:int | b >= g; g >= r} MXMN_bgr(c, b, r) of RGB(c, r, g, b)

(* CHROMA(c, k): c's chroma is at most k (of 255) *)
dataprop CHROMA(int, int) =
  | {c,mx,mn,k:int | mx - mn <= k} CHROMAc(c, k) of MXMN(c, mx, mn)

(* CALM(c): c's saturation is at most 1/2 *)
dataprop CALM(int) =
  | {c,mx,mn:int | 2 * (mx - mn) <= mx} CALMc(c) of MXMN(c, mx, mn)

(* SATNEAR(a, b, d): a's and b's saturations are within d / 100 *)
dataprop SATNEAR(int, int, int) =
  | {a,b,d,amx,amn,bmx,bmn:int | amx > 0; bmx > 0;
      100 * ((amx - amn) * bmx - (bmx - bmn) * amx) <= d * amx * bmx;
      100 * ((bmx - bmn) * amx - (amx - amn) * bmx) <= d * amx * bmx}
    SATNEARc(a, b, d) of (MXMN(a, amx, amn), MXMN(b, bmx, bmn))

(* PEAK(c, lo, hi): c's brightest channel is in [lo, hi] *)
dataprop PEAK(int, int, int) =
  | {c,mx,mn,lo,hi:int | lo <= mx; mx <= hi} PEAKc(c, lo, hi) of MXMN(c, mx, mn)

(* HUE(c, lo, hi): c has a hue, and it is in [lo, hi] degrees. An arc
   may reach past 0 or 360 (a red is in [~15, 15]): the _down and _up
   forms take the hue as h - 360 and h + 360 *)
dataprop HUE(int, int, int) =
  | {c,r,g,b,lo,hi:int | r >= g; g >= b; r > b;
      lo * (r - b) <= 60 * (g - b); 60 * (g - b) <= hi * (r - b)}
    HUE_r_g_b(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | r >= g; g >= b; r > b;
      lo * (r - b) <= 60 * (g - b) - 360 * (r - b); 60 * (g - b) - 360 * (r - b) <= hi * (r - b)}
    HUE_r_g_b_down(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | r >= g; g >= b; r > b;
      lo * (r - b) <= 60 * (g - b) + 360 * (r - b); 60 * (g - b) + 360 * (r - b) <= hi * (r - b)}
    HUE_r_g_b_up(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | g >= r; r >= b; g > b;
      lo * (g - b) <= 120 * (g - b) - 60 * (r - b); 120 * (g - b) - 60 * (r - b) <= hi * (g - b)}
    HUE_g_r_b(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | g >= r; r >= b; g > b;
      lo * (g - b) <= 120 * (g - b) - 60 * (r - b) - 360 * (g - b); 120 * (g - b) - 60 * (r - b) - 360 * (g - b) <= hi * (g - b)}
    HUE_g_r_b_down(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | g >= r; r >= b; g > b;
      lo * (g - b) <= 120 * (g - b) - 60 * (r - b) + 360 * (g - b); 120 * (g - b) - 60 * (r - b) + 360 * (g - b) <= hi * (g - b)}
    HUE_g_r_b_up(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | g >= b; b >= r; g > r;
      lo * (g - r) <= 120 * (g - r) + 60 * (b - r); 120 * (g - r) + 60 * (b - r) <= hi * (g - r)}
    HUE_g_b_r(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | g >= b; b >= r; g > r;
      lo * (g - r) <= 120 * (g - r) + 60 * (b - r) - 360 * (g - r); 120 * (g - r) + 60 * (b - r) - 360 * (g - r) <= hi * (g - r)}
    HUE_g_b_r_down(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | g >= b; b >= r; g > r;
      lo * (g - r) <= 120 * (g - r) + 60 * (b - r) + 360 * (g - r); 120 * (g - r) + 60 * (b - r) + 360 * (g - r) <= hi * (g - r)}
    HUE_g_b_r_up(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | b >= g; g >= r; b > r;
      lo * (b - r) <= 240 * (b - r) - 60 * (g - r); 240 * (b - r) - 60 * (g - r) <= hi * (b - r)}
    HUE_b_g_r(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | b >= g; g >= r; b > r;
      lo * (b - r) <= 240 * (b - r) - 60 * (g - r) - 360 * (b - r); 240 * (b - r) - 60 * (g - r) - 360 * (b - r) <= hi * (b - r)}
    HUE_b_g_r_down(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | b >= g; g >= r; b > r;
      lo * (b - r) <= 240 * (b - r) - 60 * (g - r) + 360 * (b - r); 240 * (b - r) - 60 * (g - r) + 360 * (b - r) <= hi * (b - r)}
    HUE_b_g_r_up(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | b >= r; r >= g; b > g;
      lo * (b - g) <= 240 * (b - g) + 60 * (r - g); 240 * (b - g) + 60 * (r - g) <= hi * (b - g)}
    HUE_b_r_g(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | b >= r; r >= g; b > g;
      lo * (b - g) <= 240 * (b - g) + 60 * (r - g) - 360 * (b - g); 240 * (b - g) + 60 * (r - g) - 360 * (b - g) <= hi * (b - g)}
    HUE_b_r_g_down(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | b >= r; r >= g; b > g;
      lo * (b - g) <= 240 * (b - g) + 60 * (r - g) + 360 * (b - g); 240 * (b - g) + 60 * (r - g) + 360 * (b - g) <= hi * (b - g)}
    HUE_b_r_g_up(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | r >= b; b >= g; r > g;
      lo * (r - g) <= 360 * (r - g) - 60 * (b - g); 360 * (r - g) - 60 * (b - g) <= hi * (r - g)}
    HUE_r_b_g(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | r >= b; b >= g; r > g;
      lo * (r - g) <= 360 * (r - g) - 60 * (b - g) - 360 * (r - g); 360 * (r - g) - 60 * (b - g) - 360 * (r - g) <= hi * (r - g)}
    HUE_r_b_g_down(c, lo, hi) of RGB(c, r, g, b)
  | {c,r,g,b,lo,hi:int | r >= b; b >= g; r > g;
      lo * (r - g) <= 360 * (r - g) - 60 * (b - g) + 360 * (r - g); 360 * (r - g) - 60 * (b - g) + 360 * (r - g) <= hi * (r - g)}
    HUE_r_b_g_up(c, lo, hi) of RGB(c, r, g, b)


prval _ : CALM(14158182) = CALMc(MXMN_rbg(RGBc{216,9,102}()))
