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


prval _ : HUE(4219963, 112, 113) = HUE_g_r_b(RGBc{64,100,59}())
prval _ : CHROMA(4219963, 41) = CHROMAc(MXMN_grb(RGBc{64,100,59}()))
prval _ : CALM(4219963) = CALMc(MXMN_grb(RGBc{64,100,59}()))
prval _ : HUE(6487227, 154, 155) = HUE_g_b_r(RGBc{98,252,187}())
prval _ : CHROMA(6487227, 154) = CHROMAc(MXMN_gbr(RGBc{98,252,187}()))
prval _ : HUE(1543623, 199, 200) = HUE_b_g_r(RGBc{23,141,199}())
prval _ : CHROMA(1543623, 176) = CHROMAc(MXMN_bgr(RGBc{23,141,199}()))
prval _ : HUE(15157691, 316, 317) = HUE_r_b_g(RGBc{231,73,187}())
prval _ : CHROMA(15157691, 158) = CHROMAc(MXMN_rbg(RGBc{231,73,187}()))
prval _ : HUE(222850, 193, 194) = HUE_b_g_r(RGBc{3,102,130}())
prval _ : CHROMA(222850, 127) = CHROMAc(MXMN_bgr(RGBc{3,102,130}()))
prval _ : HUE(5937563, 181, 182) = HUE_b_g_r(RGBc{90,153,155}())
prval _ : CHROMA(5937563, 65) = CHROMAc(MXMN_bgr(RGBc{90,153,155}()))
prval _ : CALM(5937563) = CALMc(MXMN_bgr(RGBc{90,153,155}()))
prval _ : HUE(1810447, 115, 116) = HUE_g_r_b(RGBc{27,160,15}())
prval _ : CHROMA(1810447, 145) = CHROMAc(MXMN_grb(RGBc{27,160,15}()))
prval _ : HUE(11655244, 76, 77) = HUE_g_r_b(RGBc{177,216,76}())
prval _ : CHROMA(11655244, 140) = CHROMAc(MXMN_grb(RGBc{177,216,76}()))
prval _ : HUE(14158182, 333, 334) = HUE_r_b_g(RGBc{216,9,102}())
prval _ : CHROMA(14158182, 207) = CHROMAc(MXMN_rbg(RGBc{216,9,102}()))
prval _ : HUE(5713622, 254, 255) = HUE_b_r_g(RGBc{87,46,214}())
prval _ : CHROMA(5713622, 168) = CHROMAc(MXMN_brg(RGBc{87,46,214}()))
prval _ : HUE(16277304, 12, 13) = HUE_r_g_b(RGBc{248,95,56}())
prval _ : CHROMA(16277304, 192) = CHROMAc(MXMN_rgb(RGBc{248,95,56}()))
prval _ : HUE(10140533, 88, 89) = HUE_g_r_b(RGBc{154,187,117}())
prval _ : CHROMA(10140533, 70) = CHROMAc(MXMN_grb(RGBc{154,187,117}()))
prval _ : CALM(10140533) = CALMc(MXMN_grb(RGBc{154,187,117}()))
prval _ : HUE(11765571, 36, 37) = HUE_r_g_b(RGBc{179,135,67}())
prval _ : CHROMA(11765571, 112) = CHROMAc(MXMN_rgb(RGBc{179,135,67}()))
prval _ : HUE(12588896, 334, 335) = HUE_r_b_g(RGBc{192,23,96}())
prval _ : CHROMA(12588896, 169) = CHROMAc(MXMN_rbg(RGBc{192,23,96}()))
prval _ : HUE(13713643, 290, 291) = HUE_b_r_g(RGBc{209,64,235}())
prval _ : CHROMA(13713643, 171) = CHROMAc(MXMN_brg(RGBc{209,64,235}()))
prval _ : HUE(6426417, 335, 336) = HUE_r_b_g(RGBc{98,15,49}())
prval _ : CHROMA(6426417, 83) = CHROMAc(MXMN_rbg(RGBc{98,15,49}()))
prval _ : HUE(14802953, 59, 60) = HUE_r_g_b(RGBc{225,224,9}())
prval _ : CHROMA(14802953, 216) = CHROMAc(MXMN_rgb(RGBc{225,224,9}()))
prval _ : HUE(412930, 116, 117) = HUE_g_r_b(RGBc{6,77,2}())
prval _ : CHROMA(412930, 75) = CHROMAc(MXMN_grb(RGBc{6,77,2}()))
prval _ : HUE(9787696, 24, 25) = HUE_r_g_b(RGBc{149,89,48}())
prval _ : CHROMA(9787696, 101) = CHROMAc(MXMN_rgb(RGBc{149,89,48}()))
prval _ : HUE(12867806, 288, 289) = HUE_b_r_g(RGBc{196,88,222}())
prval _ : CHROMA(12867806, 134) = CHROMAc(MXMN_brg(RGBc{196,88,222}()))
prval _ : HUE(8311379, 99, 100) = HUE_g_r_b(RGBc{126,210,83}())
prval _ : CHROMA(8311379, 127) = CHROMAc(MXMN_grb(RGBc{126,210,83}()))
prval _ : HUE(4793863, 28, 29) = HUE_r_g_b(RGBc{73,38,7}())
prval _ : CHROMA(4793863, 66) = CHROMAc(MXMN_rgb(RGBc{73,38,7}()))
prval _ : HUE(3150979, 255, 256) = HUE_b_r_g(RGBc{48,20,131}())
prval _ : CHROMA(3150979, 111) = CHROMAc(MXMN_brg(RGBc{48,20,131}()))
prval _ : HUE(3732831, 132, 133) = HUE_g_b_r(RGBc{56,245,95}())
prval _ : CHROMA(3732831, 189) = CHROMAc(MXMN_gbr(RGBc{56,245,95}()))
prval _ : HUE(3379573, 162, 163) = HUE_g_b_r(RGBc{51,145,117}())
prval _ : CHROMA(3379573, 94) = CHROMAc(MXMN_gbr(RGBc{51,145,117}()))
prval _ : HUE(4111168, 120, 121) = HUE_g_b_r(RGBc{62,187,64}())
prval _ : CHROMA(4111168, 125) = CHROMAc(MXMN_gbr(RGBc{62,187,64}()))
prval _ : HUE(8140976, 274, 274) = HUE_b_r_g(RGBc{124,56,176}())
prval _ : CHROMA(8140976, 120) = CHROMAc(MXMN_brg(RGBc{124,56,176}()))
prval _ : HUE(2239828, 226, 227) = HUE_b_g_r(RGBc{34,45,84}())
prval _ : CHROMA(2239828, 50) = CHROMAc(MXMN_bgr(RGBc{34,45,84}()))
prval _ : HUE(5705567, 294, 294) = HUE_b_r_g(RGBc{87,15,95}())
prval _ : CHROMA(5705567, 80) = CHROMAc(MXMN_brg(RGBc{87,15,95}()))
prval _ : HUE(7803368, 268, 269) = HUE_b_r_g(RGBc{119,17,232}())
prval _ : CHROMA(7803368, 215) = CHROMAc(MXMN_brg(RGBc{119,17,232}()))
prval _ : HUE(10514192, 39, 40) = HUE_r_g_b(RGBc{160,111,16}())
prval _ : CHROMA(10514192, 144) = CHROMAc(MXMN_rgb(RGBc{160,111,16}()))
prval _ : HUE(8494979, 124, 124) = HUE_g_b_r(RGBc{129,159,131}())
prval _ : CHROMA(8494979, 30) = CHROMAc(MXMN_gbr(RGBc{129,159,131}()))
prval _ : CALM(8494979) = CALMc(MXMN_gbr(RGBc{129,159,131}()))
prval _ : HUE(478013, 167, 168) = HUE_g_b_r(RGBc{7,75,61}())
prval _ : CHROMA(478013, 68) = CHROMAc(MXMN_gbr(RGBc{7,75,61}()))
prval _ : HUE(16766652, 23, 24) = HUE_r_g_b(RGBc{255,214,188}())
prval _ : CHROMA(16766652, 67) = CHROMAc(MXMN_rgb(RGBc{255,214,188}()))
prval _ : CALM(16766652) = CALMc(MXMN_rgb(RGBc{255,214,188}()))
prval _ : HUE(14180428, 8, 9) = HUE_r_g_b(RGBc{216,96,76}())
prval _ : CHROMA(14180428, 140) = CHROMAc(MXMN_rgb(RGBc{216,96,76}()))
prval _ : HUE(11575695, 32, 33) = HUE_r_g_b(RGBc{176,161,143}())
prval _ : CHROMA(11575695, 33) = CHROMAc(MXMN_rgb(RGBc{176,161,143}()))
prval _ : CALM(11575695) = CALMc(MXMN_rgb(RGBc{176,161,143}()))
prval _ : HUE(10040275, 278, 279) = HUE_b_r_g(RGBc{153,51,211}())
prval _ : CHROMA(10040275, 160) = CHROMAc(MXMN_brg(RGBc{153,51,211}()))
prval _ : HUE(7204355, 92, 93) = HUE_g_r_b(RGBc{109,238,3}())
prval _ : CHROMA(7204355, 235) = CHROMAc(MXMN_grb(RGBc{109,238,3}()))
prval _ : HUE(6493762, 325, 326) = HUE_r_b_g(RGBc{99,22,66}())
prval _ : CHROMA(6493762, 77) = CHROMAc(MXMN_rbg(RGBc{99,22,66}()))
prval _ : HUE(11169120, 10, 11) = HUE_r_g_b(RGBc{170,109,96}())
prval _ : CHROMA(11169120, 74) = CHROMAc(MXMN_rgb(RGBc{170,109,96}()))
prval _ : CALM(11169120) = CALMc(MXMN_rgb(RGBc{170,109,96}()))
prval _ : HUE(9398348, 25, 26) = HUE_r_g_b(RGBc{143,104,76}())
prval _ : CHROMA(9398348, 67) = CHROMAc(MXMN_rgb(RGBc{143,104,76}()))
prval _ : CALM(9398348) = CALMc(MXMN_rgb(RGBc{143,104,76}()))
prval _ : HUE(8988647, 270, 271) = HUE_b_r_g(RGBc{137,39,231}())
prval _ : CHROMA(8988647, 192) = CHROMAc(MXMN_brg(RGBc{137,39,231}()))
prval _ : HUE(10557905, 284, 285) = HUE_b_r_g(RGBc{161,25,209}())
prval _ : CHROMA(10557905, 184) = CHROMAc(MXMN_brg(RGBc{161,25,209}()))
prval _ : HUE(139650, 225, 226) = HUE_b_g_r(RGBc{2,33,130}())
prval _ : CHROMA(139650, 128) = CHROMAc(MXMN_bgr(RGBc{2,33,130}()))
prval _ : HUE(8621490, 227, 228) = HUE_b_g_r(RGBc{131,141,178}())
prval _ : CHROMA(8621490, 47) = CHROMAc(MXMN_bgr(RGBc{131,141,178}()))
prval _ : CALM(8621490) = CALMc(MXMN_bgr(RGBc{131,141,178}()))
prval _ : HUE(11169028, 37, 38) = HUE_r_g_b(RGBc{170,109,4}())
prval _ : CHROMA(11169028, 166) = CHROMAc(MXMN_rgb(RGBc{170,109,4}()))
prval _ : HUE(843739, 178, 179) = HUE_g_b_r(RGBc{12,223,219}())
prval _ : CHROMA(843739, 211) = CHROMAc(MXMN_gbr(RGBc{12,223,219}()))
prval _ : HUE(6781117, 228, 229) = HUE_b_g_r(RGBc{103,120,189}())
prval _ : CHROMA(6781117, 86) = CHROMAc(MXMN_bgr(RGBc{103,120,189}()))
prval _ : CALM(6781117) = CALMc(MXMN_bgr(RGBc{103,120,189}()))
prval _ : HUE(10763368, 334, 335) = HUE_r_b_g(RGBc{164,60,104}())
prval _ : CHROMA(10763368, 104) = CHROMAc(MXMN_rbg(RGBc{164,60,104}()))
prval _ : HUE(7949716, 277, 278) = HUE_b_r_g(RGBc{121,77,148}())
prval _ : CHROMA(7949716, 71) = CHROMAc(MXMN_brg(RGBc{121,77,148}()))
prval _ : CALM(7949716) = CALMc(MXMN_brg(RGBc{121,77,148}()))
prval _ : HUE(12463474, 331, 332) = HUE_r_b_g(RGBc{190,45,114}())
prval _ : CHROMA(12463474, 145) = CHROMAc(MXMN_rbg(RGBc{190,45,114}()))
prval _ : HUE(16128062, 349, 350) = HUE_r_b_g(RGBc{246,24,62}())
prval _ : CHROMA(16128062, 222) = CHROMAc(MXMN_rbg(RGBc{246,24,62}()))
prval _ : HUE(6788855, 220, 221) = HUE_b_g_r(RGBc{103,150,247}())
prval _ : CHROMA(6788855, 144) = CHROMAc(MXMN_bgr(RGBc{103,150,247}()))
prval _ : HUE(8344919, 357, 358) = HUE_r_b_g(RGBc{127,85,87}())
prval _ : CHROMA(8344919, 42) = CHROMAc(MXMN_rbg(RGBc{127,85,87}()))
prval _ : CALM(8344919) = CALMc(MXMN_rbg(RGBc{127,85,87}()))
prval _ : HUE(11449494, 72, 72) = HUE_g_r_b(RGBc{174,180,150}())
prval _ : CHROMA(11449494, 30) = CHROMAc(MXMN_grb(RGBc{174,180,150}()))
prval _ : CALM(11449494) = CALMc(MXMN_grb(RGBc{174,180,150}()))
prval _ : HUE(3868736, 294, 295) = HUE_b_r_g(RGBc{59,8,64}())
prval _ : CHROMA(3868736, 56) = CHROMAc(MXMN_brg(RGBc{59,8,64}()))
prval _ : HUE(2688241, 249, 250) = HUE_b_r_g(RGBc{41,4,241}())
prval _ : CHROMA(2688241, 237) = CHROMAc(MXMN_brg(RGBc{41,4,241}()))
prval _ : HUE(7383999, 195, 196) = HUE_b_g_r(RGBc{112,171,191}())
prval _ : CHROMA(7383999, 79) = CHROMAc(MXMN_bgr(RGBc{112,171,191}()))
prval _ : CALM(7383999) = CALMc(MXMN_bgr(RGBc{112,171,191}()))
prval _ : HUE(9470730, 54, 55) = HUE_r_g_b(RGBc{144,131,10}())
prval _ : CHROMA(9470730, 134) = CHROMAc(MXMN_rgb(RGBc{144,131,10}()))
prval _ : HUE(10829019, 279, 280) = HUE_b_r_g(RGBc{165,60,219}())
prval _ : CHROMA(10829019, 159) = CHROMAc(MXMN_brg(RGBc{165,60,219}()))
prval _ : SATNEAR(12230678, 6880874, 30) = SATNEARc(MXMN_rgb(RGBc{186,160,22}()), MXMN_gbr(RGBc{104,254,106}()))
prval _ : SATNEAR(347734, 8928997, 22) = SATNEARc(MXMN_bgr(RGBc{5,78,86}()), MXMN_brg(RGBc{136,62,229}()))
prval _ : SATNEAR(595497, 9893808, 39) = SATNEARc(MXMN_bgr(RGBc{9,22,41}()), MXMN_gbr(RGBc{150,247,176}()))
prval _ : SATNEAR(4097845, 12952438, 21) = SATNEARc(MXMN_grb(RGBc{62,135,53}()), MXMN_rgb(RGBc{197,163,118}()))
prval _ : SATNEAR(4540963, 13009615, 16) = SATNEARc(MXMN_grb(RGBc{69,74,35}()), MXMN_brg(RGBc{198,130,207}()))
prval _ : SATNEAR(11736180, 6140337, 42) = SATNEARc(MXMN_rbg(RGBc{179,20,116}()), MXMN_gbr(RGBc{93,177,177}()))
prval _ : SATNEAR(14853470, 13493135, 22) = SATNEARc(MXMN_rgb(RGBc{226,165,94}()), MXMN_grb(RGBc{205,227,143}()))
prval _ : SATNEAR(9711613, 12550227, 25) = SATNEARc(MXMN_brg(RGBc{148,47,253}()), MXMN_rgb(RGBc{191,128,83}()))
prval _ : SATNEAR(7870161, 9463498, 40) = SATNEARc(MXMN_brg(RGBc{120,22,209}()), MXMN_brg(RGBc{144,102,202}()))
prval _ : SATNEAR(7652058, 6102127, 28) = SATNEARc(MXMN_bgr(RGBc{116,194,218}()), MXMN_brg(RGBc{93,28,111}()))
prval _ : SATNEAR(3747246, 7236365, 15) = SATNEARc(MXMN_brg(RGBc{57,45,174}()), MXMN_rgb(RGBc{110,107,13}()))
prval _ : SATNEAR(14400733, 10851228, 5) = SATNEARc(MXMN_brg(RGBc{219,188,221}()), MXMN_rbg(RGBc{165,147,156}()))
prval _ : SATNEAR(8871296, 519221, 66) = SATNEARc(MXMN_rbg(RGBc{135,93,128}()), MXMN_gbr(RGBc{7,236,53}()))
prval _ : SATNEAR(4877615, 13468832, 22) = SATNEARc(MXMN_grb(RGBc{74,109,47}()), MXMN_rbg(RGBc{205,132,160}()))
prval _ : SATNEAR(14581921, 15027261, 32) = SATNEARc(MXMN_rbg(RGBc{222,128,161}()), MXMN_rgb(RGBc{229,76,61}()))
prval _ : SATNEAR(869724, 7952976, 52) = SATNEARc(MXMN_bgr(RGBc{13,69,92}()), MXMN_rgb(RGBc{121,90,80}()))
prval _ : SATNEAR(5887287, 10871365, 5) = SATNEARc(MXMN_grb(RGBc{89,213,55}()), MXMN_grb(RGBc{165,226,69}()))
prval _ : SATNEAR(5159803, 10105617, 31) = SATNEARc(MXMN_gbr(RGBc{78,187,123}()), MXMN_rgb(RGBc{154,51,17}()))
prval _ : SATNEAR(15172801, 5887396, 16) = SATNEARc(MXMN_rbg(RGBc{231,132,193}()), MXMN_gbr(RGBc{89,213,164}()))
prval _ : SATNEAR(1094080, 15504570, 55) = SATNEARc(MXMN_bgr(RGBc{16,177,192}()), MXMN_rbg(RGBc{236,148,186}()))
prval _ : SATNEAR(13977967, 8205979, 1) = SATNEARc(MXMN_rbg(RGBc{213,73,111}()), MXMN_brg(RGBc{125,54,155}()))
prval _ : SATNEAR(4620925, 9136680, 26) = SATNEARc(MXMN_gbr(RGBc{70,130,125}()), MXMN_rgb(RGBc{139,106,40}()))
prval _ : SATNEAR(14918441, 3863261, 6) = SATNEARc(MXMN_rgb(RGBc{227,163,41}()), MXMN_gbr(RGBc{58,242,221}()))
prval _ : SATNEAR(3491416, 8843156, 5) = SATNEARc(MXMN_bgr(RGBc{53,70,88}()), MXMN_gbr(RGBc{134,239,148}()))
prval _ : SATNEAR(4143302, 8979789, 25) = SATNEARc(MXMN_brg(RGBc{63,56,198}()), MXMN_rbg(RGBc{137,5,77}()))
prval _ : SATNEAR(13279778, 16294293, 44) = SATNEARc(MXMN_rgb(RGBc{202,162,34}()), MXMN_rgb(RGBc{248,161,149}()))
prval _ : SATNEAR(5978335, 14626397, 5) = SATNEARc(MXMN_brg(RGBc{91,56,223}()), MXMN_rbg(RGBc{223,46,93}()))
prval _ : SATNEAR(2714197, 3467815, 23) = SATNEARc(MXMN_gbr(RGBc{41,106,85}()), MXMN_grb(RGBc{52,234,39}()))
prval _ : SATNEAR(7379092, 3182173, 40) = SATNEARc(MXMN_gbr(RGBc{112,152,148}()), MXMN_gbr(RGBc{48,142,93}()))
prval _ : SATNEAR(13307798, 8341772, 3) = SATNEARc(MXMN_rbg(RGBc{203,15,150}()), MXMN_rgb(RGBc{127,73,12}()))
prval _ : SATNEAR(1936891, 3393734, 14) = SATNEARc(MXMN_bgr(RGBc{29,141,251}()), MXMN_gbr(RGBc{51,200,198}()))
prval _ : SATNEAR(10728749, 1007860, 19) = SATNEARc(MXMN_grb(RGBc{163,181,45}()), MXMN_bgr(RGBc{15,96,244}()))
prval _ : SATNEAR(11528637, 13878627, 29) = SATNEARc(MXMN_gbr(RGBc{175,233,189}()), MXMN_rgb(RGBc{211,197,99}()))
prval _ : SATNEAR(4206826, 2749565, 4) = SATNEARc(MXMN_brg(RGBc{64,48,234}()), MXMN_gbr(RGBc{41,244,125}()))
prval _ : SATNEAR(269668, 15357729, 11) = SATNEARc(MXMN_bgr(RGBc{4,29,100}()), MXMN_rgb(RGBc{234,87,33}()))
prval _ : SATNEAR(15369251, 12748278, 40) = SATNEARc(MXMN_rgb(RGBc{234,132,35}()), MXMN_brg(RGBc{194,133,246}()))
prval _ : SATNEAR(752366, 2973213, 27) = SATNEARc(MXMN_bgr(RGBc{11,122,238}()), MXMN_grb(RGBc{45,94,29}()))
prval _ : SATNEAR(7865583, 3260844, 24) = SATNEARc(MXMN_brg(RGBc{120,4,239}()), MXMN_gbr(RGBc{49,193,172}()))
prval _ : SATNEAR(841587, 8500365, 67) = SATNEARc(MXMN_gbr(RGBc{12,215,115}()), MXMN_gbr(RGBc{129,180,141}()))
prval _ : SATNEAR(15127746, 15440837, 19) = SATNEARc(MXMN_rgb(RGBc{230,212,194}()), MXMN_rbg(RGBc{235,155,197}()))
