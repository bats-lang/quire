(* style -- quire's stylesheet, built so that what it guarantees is
   checked by the type checker:

   * Legible text. A colour can only be set together with the
     background it is drawn on (surf), and every such pair carries a
     proof that it meets 4.5:1 in each of the three themes (SURF). So
     for any element, the colour it inherits and the background painted
     behind it come from the same rule, and that rule is proven. Text
     fields' borders are proven 3:1 against their fill, as WCAG 1.4.11
     asks of a control's boundary. Backgrounds with no proven text
     colour (fills: bars, tracks, placeholders) set font-size 0, and
     the overlay's veil sets colour transparent, so no text can sit on
     them unproven.

   * Harmony. Each theme is written only with a proof that it follows
     css's harmony rules (HARMONY, from harmony.bats): at most three hue
     families; neutral surfaces, bars, edges and text in the first;
     danger red and highlights yellow; accent and danger as saturated;
     a card lighter than the page; body text at 7:1; and, for a dark
     theme, no black ground, no pure white text and calm colours. No
     text/ground pair vibrates (SURF). The proofs are written by
     scripts/gen-harmony.py from PAL, and checked by the solver.

   * Targets. Every interactive element (a button, an input, or
     anything given an interactive role) is at least 44 by 44 CSS
     pixels: the base rules say so with !important, and nothing else in
     the sheet can be !important (layout values and selectors lose any
     '!', ';', '{' and '}'), so no later rule can make one smaller.
     min-height and min-width win over height and max-height in CSS.

   * Focus. A focused control is ringed 2px inside its edge in its own
     text colour, which is proven against the background behind it.

   * Text fields use 16px type, so iOS does not zoom into them.

   The palette's colours enter once, in PAL, with the luminance of each
   (from css's contrast table); the themes' custom properties are
   written from the same table, so the colours the page uses are the
   colours proven. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use css as C

staload CT = "css/src/contrast.sats"
staload H = "css/src/harmony.sats"
staload GT = "gestures/src/tracker.sats"

(* ============================================================
   Roles and palette
   ============================================================ *)

(* A role is a custom property, --<name>, set per theme *)
stadef BG = 0
stadef FG = 1
stadef MUTED = 2
stadef CARD = 3
stadef LINE = 4
stadef EDGE = 5
stadef BAR = 6
stadef BARFG = 7
stadef ACCENT = 8
stadef ACCENTFG = 9
stadef HL = 10
stadef BARHI = 11
stadef BANNER = 12
stadef BANNERFG = 13
stadef MARK = 14
stadef MARKFG = 15
stadef DANGER = 16
#pub stadef NROLE = 17

#pub typedef role(r:int) = int(r)
#pub typedef role = [r:nat | r < NROLE] int r

(* Themes: 0 light, 1 sepia, 2 dark *)

(* PAL(t, r, c): in theme t, role r is the colour 0xc *)
dataprop PAL(int, int, int) =
  | PAL0_bg(0, BG, 0xfaf8f5) | PAL1_bg(1, BG, 0xf0e6d2) | PAL2_bg(2, BG, 0x1e1e1e)
  | PAL0_fg(0, FG, 0x2a2a2a) | PAL1_fg(1, FG, 0x3b2f22) | PAL2_fg(2, FG, 0xe2e2e2)
  | PAL0_muted(0, MUTED, 0x6b6b6b) | PAL1_muted(1, MUTED, 0x6e5e4a) | PAL2_muted(2, MUTED, 0xa0a0a0)
  | PAL0_card(0, CARD, 0xffffff) | PAL1_card(1, CARD, 0xf7efdf) | PAL2_card(2, CARD, 0x2a2a2a)
  | PAL0_line(0, LINE, 0xdddddd) | PAL1_line(1, LINE, 0xd6c7a8) | PAL2_line(2, LINE, 0x3d3d3d)
  | PAL0_edge(0, EDGE, 0x8a8a8a) | PAL1_edge(1, EDGE, 0x8f7d62) | PAL2_edge(2, EDGE, 0x7a7a7a)
  | PAL0_bar(0, BAR, 0x333333) | PAL1_bar(1, BAR, 0x4a3b2a) | PAL2_bar(2, BAR, 0x111111)
  | PAL0_barfg(0, BARFG, 0xffffff) | PAL1_barfg(1, BARFG, 0xf7efdf) | PAL2_barfg(2, BARFG, 0xe2e2e2)
  | PAL0_accent(0, ACCENT, 0x2f6f4f) | PAL1_accent(1, ACCENT, 0x7a4f1d) | PAL2_accent(2, ACCENT, 0x7fc49b)
  | PAL0_accentfg(0, ACCENTFG, 0xffffff) | PAL1_accentfg(1, ACCENTFG, 0xffffff) | PAL2_accentfg(2, ACCENTFG, 0x10231a)
  (* a highlight, opaque: the old translucent yellows over each page *)
  | PAL0_hl(0, HL, 0xfde59a) | PAL1_hl(1, HL, 0xe4c68e) | PAL2_hl(2, HL, 0x6d5e2f)
  | PAL0_barhi(0, BARHI, 0x4a4a4a) | PAL1_barhi(1, BARHI, 0x5e4c38) | PAL2_barhi(2, BARHI, 0x2e2e2e)
  | PAL0_banner(0, BANNER, 0xfbe3e1) | PAL1_banner(1, BANNER, 0xfbe3e1) | PAL2_banner(2, BANNER, 0xfbe3e1)
  | PAL0_bannerfg(0, BANNERFG, 0x6b1d16) | PAL1_bannerfg(1, BANNERFG, 0x6b1d16) | PAL2_bannerfg(2, BANNERFG, 0x6b1d16)
  | PAL0_mark(0, MARK, 0xffb300) | PAL1_mark(1, MARK, 0xffb300) | PAL2_mark(2, MARK, 0xffb300)
  | PAL0_markfg(0, MARKFG, 0x000000) | PAL1_markfg(1, MARKFG, 0x000000) | PAL2_markfg(2, MARKFG, 0x000000)
  | PAL0_danger(0, DANGER, 0xb3261e) | PAL1_danger(1, DANGER, 0x9c2a1c) | PAL2_danger(2, DANGER, 0xffb4ab)

(* Luminance of each palette colour, from css's table *)
prval L_faf8f5 = $CT.LUMc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5())
prval L_f0e6d2 = $CT.LUMc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2())
prval L_1e1e1e = $CT.LUMc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e())
prval L_2a2a2a = $CT.LUMc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a())
prval L_3b2f22 = $CT.LUMc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22())
prval L_e2e2e2 = $CT.LUMc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2())
prval L_6b6b6b = $CT.LUMc($CT.LIN_6b(), $CT.LIN_6b(), $CT.LIN_6b())
prval L_6e5e4a = $CT.LUMc($CT.LIN_6e(), $CT.LIN_5e(), $CT.LIN_4a())
prval L_a0a0a0 = $CT.LUMc($CT.LIN_a0(), $CT.LIN_a0(), $CT.LIN_a0())
prval L_ffffff = $CT.LUMc($CT.LIN_ff(), $CT.LIN_ff(), $CT.LIN_ff())
prval L_f7efdf = $CT.LUMc($CT.LIN_f7(), $CT.LIN_ef(), $CT.LIN_df())
prval L_dddddd = $CT.LUMc($CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd())
prval L_d6c7a8 = $CT.LUMc($CT.LIN_d6(), $CT.LIN_c7(), $CT.LIN_a8())
prval L_3d3d3d = $CT.LUMc($CT.LIN_3d(), $CT.LIN_3d(), $CT.LIN_3d())
prval L_8a8a8a = $CT.LUMc($CT.LIN_8a(), $CT.LIN_8a(), $CT.LIN_8a())
prval L_8f7d62 = $CT.LUMc($CT.LIN_8f(), $CT.LIN_7d(), $CT.LIN_62())
prval L_7a7a7a = $CT.LUMc($CT.LIN_7a(), $CT.LIN_7a(), $CT.LIN_7a())
prval L_333333 = $CT.LUMc($CT.LIN_33(), $CT.LIN_33(), $CT.LIN_33())
prval L_4a3b2a = $CT.LUMc($CT.LIN_4a(), $CT.LIN_3b(), $CT.LIN_2a())
prval L_111111 = $CT.LUMc($CT.LIN_11(), $CT.LIN_11(), $CT.LIN_11())
prval L_2f6f4f = $CT.LUMc($CT.LIN_2f(), $CT.LIN_6f(), $CT.LIN_4f())
prval L_7a4f1d = $CT.LUMc($CT.LIN_7a(), $CT.LIN_4f(), $CT.LIN_1d())
prval L_7fc49b = $CT.LUMc($CT.LIN_7f(), $CT.LIN_c4(), $CT.LIN_9b())
prval L_10231a = $CT.LUMc($CT.LIN_10(), $CT.LIN_23(), $CT.LIN_1a())
prval L_fde59a = $CT.LUMc($CT.LIN_fd(), $CT.LIN_e5(), $CT.LIN_9a())
prval L_e4c68e = $CT.LUMc($CT.LIN_e4(), $CT.LIN_c6(), $CT.LIN_8e())
prval L_6d5e2f = $CT.LUMc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f())
prval L_4a4a4a = $CT.LUMc($CT.LIN_4a(), $CT.LIN_4a(), $CT.LIN_4a())
prval L_5e4c38 = $CT.LUMc($CT.LIN_5e(), $CT.LIN_4c(), $CT.LIN_38())
prval L_2e2e2e = $CT.LUMc($CT.LIN_2e(), $CT.LIN_2e(), $CT.LIN_2e())
prval L_fbe3e1 = $CT.LUMc($CT.LIN_fb(), $CT.LIN_e3(), $CT.LIN_e1())
prval L_6b1d16 = $CT.LUMc($CT.LIN_6b(), $CT.LIN_1d(), $CT.LIN_16())
prval L_ffb300 = $CT.LUMc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00())
prval L_000000 = $CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00())
prval L_b3261e = $CT.LUMc($CT.LIN_b3(), $CT.LIN_26(), $CT.LIN_1e())
prval L_9c2a1c = $CT.LUMc($CT.LIN_9c(), $CT.LIN_2a(), $CT.LIN_1c())
prval L_ffb4ab = $CT.LUMc($CT.LIN_ff(), $CT.LIN_b4(), $CT.LIN_ab())

(* SURF(f, b): text in role f on role b is at least 4.5:1 in every
   theme, and does not vibrate on it (one of them is calm); EDGEP(e, b): a control's edge in role e on b is at least 3:1 *)
dataprop SURF(int, int) =
  | {f,b:int}{f0,b0,f1,b1,f2,b2:int}
    SURFc(f, b) of (PAL(0, f, f0), PAL(0, b, b0), $CT.CONTRAST(f0, b0, 45), $H.NOVIB(f0, b0),
                    PAL(1, f, f1), PAL(1, b, b1), $CT.CONTRAST(f1, b1, 45), $H.NOVIB(f1, b1),
                    PAL(2, f, f2), PAL(2, b, b2), $CT.CONTRAST(f2, b2, 45), $H.NOVIB(f2, b2))

dataprop EDGEP(int, int) =
  | {e,b:int}{e0,b0,e1,b1,e2,b2:int}
    EDGEc(e, b) of (PAL(0, e, e0), PAL(0, b, b0), $CT.CONTRAST(e0, b0, 30),
                    PAL(1, e, e1), PAL(1, b, b1), $CT.CONTRAST(e1, b1, 30),
                    PAL(2, e, e2), PAL(2, b, b2), $CT.CONTRAST(e2, b2, 30))

(* Each theme's hue families (css's harmony.bats): at most three arcs,
   none wider than 30 degrees. The first is the tint of its neutrals.
   Light: warm paper, a green accent, red for danger. Sepia: warm, its
   accent brown in the same family, red. Dark: grey neutrals, the warm
   highlight, a green accent, red. *)
dataprop FAM(int, int, int, int, int, int, int) =
  | FAM_light(0, 25, 50, 135, 165, ~15, 15) of $H.FAMILIES(25, 50, 135, 165, ~15, 15)
  | FAM_sepia(1, 25, 50, 25, 50, ~15, 15) of $H.FAMILIES(25, 50, 25, 50, ~15, 15)
  | FAM_dark(2, 25, 50, 130, 160, ~15, 15) of $H.FAMILIES(25, 50, 130, 160, ~15, 15)

(* A theme with dark text on a light ground asks nothing more; one with
   light text on a dark ground (Material's dark theme) has a ground that
   is not black, text that is not pure white, and an accent, a danger
   colour and control edges that are desaturated (calm) *)
dataprop MODE(int, int, int, int, int, int) =
  | {bg,fg,bf,ac,dg,ed:int} MODE_light(bg, fg, bf, ac, dg, ed) of $H.LIGHTER(bg, fg)
  | {bg,fg,bf,ac,dg,ed:int} MODE_dark(bg, fg, bf, ac, dg, ed) of
      ($H.LIGHTER(fg, bg), $H.PEAK(bg, 18, 255), $H.PEAK(fg, 0, 232), $H.PEAK(bf, 0, 232),
       $H.CALM(ac), $H.CALM(dg), $H.CALM(ed))

(* HARMONY(t): theme t follows the harmony rules. A theme is written only
   with this proof (theme), over the colours it writes (PAL):
   * its hues are at most three families (FAM);
   * its surfaces, bars, edges and text are neutrals of its first
     family: grey, or tinted with its hue and chroma at most 48;
   * every other colour is grey or in one of its families;
   * danger, and the error banner, are red; a highlight and a search
     mark are yellow;
   * the accent and the danger colour are as saturated, within 0.3;
   * a card is lighter than the page;
   * body text is at least 7:1 (WCAG AAA), as a reader's should be;
   * a dark theme follows MODE_dark. *)
dataprop HARMONY(int) =
  | {t,l1,h1,l2,h2,l3,h3:int}
    {bg,fg,mu,ca,li,ed,ba,bf,ac,af,hl,bh,bn,bnf,mk,mkf,dg:int}
    HARMONYc(t) of (
      PAL(t, BG, bg), PAL(t, FG, fg), PAL(t, MUTED, mu), PAL(t, CARD, ca),
      PAL(t, LINE, li), PAL(t, EDGE, ed), PAL(t, BAR, ba), PAL(t, BARFG, bf),
      PAL(t, ACCENT, ac), PAL(t, ACCENTFG, af), PAL(t, HL, hl), PAL(t, BARHI, bh),
      PAL(t, BANNER, bn), PAL(t, BANNERFG, bnf), PAL(t, MARK, mk), PAL(t, MARKFG, mkf),
      PAL(t, DANGER, dg),
      FAM(t, l1, h1, l2, h2, l3, h3),
      $H.NEUTRAL(bg, 48, l1, h1), $H.NEUTRAL(fg, 48, l1, h1), $H.NEUTRAL(mu, 48, l1, h1),
      $H.NEUTRAL(ca, 48, l1, h1), $H.NEUTRAL(li, 48, l1, h1), $H.NEUTRAL(ed, 48, l1, h1),
      $H.NEUTRAL(ba, 48, l1, h1), $H.NEUTRAL(bf, 48, l1, h1), $H.NEUTRAL(bh, 48, l1, h1),
      $H.IN3(ac, l1, h1, l2, h2, l3, h3), $H.IN3(af, l1, h1, l2, h2, l3, h3),
      $H.IN3(hl, l1, h1, l2, h2, l3, h3), $H.IN3(bn, l1, h1, l2, h2, l3, h3),
      $H.IN3(bnf, l1, h1, l2, h2, l3, h3), $H.IN3(mk, l1, h1, l2, h2, l3, h3),
      $H.IN3(mkf, l1, h1, l2, h2, l3, h3), $H.IN3(dg, l1, h1, l2, h2, l3, h3),
      $H.HUE(dg, ~15, 15), $H.HUE(bn, ~15, 15), $H.HUE(bnf, ~15, 15),
      $H.HUE(hl, 30, 60), $H.HUE(mk, 30, 60),
      $H.SATNEAR(ac, dg, 30),
      $H.LIGHTER(ca, bg),
      $CT.CONTRAST(fg, bg, 70),
      MODE(bg, fg, bf, ac, dg, ed))

(* dark text on a light ground in the first two themes, light on dark
   in the third *)

(* BEGIN proofs: written by scripts/gen-harmony.py *)
prval S_fg_bg = SURFc(
  PAL0_fg(), PAL0_bg(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_faf8f5),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_bg(), $CT.CONTRAST_lighter_second(L_3b2f22, L_f0e6d2),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_bg(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_1e1e1e),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_fg_card = SURFc(
  PAL0_fg(), PAL0_card(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_ffffff),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_card(), $CT.CONTRAST_lighter_second(L_3b2f22, L_f7efdf),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_card(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_fg_line = SURFc(
  PAL0_fg(), PAL0_line(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_dddddd),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_line(), $CT.CONTRAST_lighter_second(L_3b2f22, L_d6c7a8),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_line(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_3d3d3d),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_fg_hl = SURFc(
  PAL0_fg(), PAL0_hl(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_fde59a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_hl(), $CT.CONTRAST_lighter_second(L_3b2f22, L_e4c68e),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_hl(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_6d5e2f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_muted_bg = SURFc(
  PAL0_muted(), PAL0_bg(), $CT.CONTRAST_lighter_second(L_6b6b6b, L_faf8f5),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6b,0x6b,0x6b}()))),
  PAL1_muted(), PAL1_bg(), $CT.CONTRAST_lighter_second(L_6e5e4a, L_f0e6d2),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6e,0x5e,0x4a}()))),
  PAL2_muted(), PAL2_bg(), $CT.CONTRAST_lighter_first(L_a0a0a0, L_1e1e1e),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xa0,0xa0,0xa0}()))))
prval S_muted_card = SURFc(
  PAL0_muted(), PAL0_card(), $CT.CONTRAST_lighter_second(L_6b6b6b, L_ffffff),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6b,0x6b,0x6b}()))),
  PAL1_muted(), PAL1_card(), $CT.CONTRAST_lighter_second(L_6e5e4a, L_f7efdf),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6e,0x5e,0x4a}()))),
  PAL2_muted(), PAL2_card(), $CT.CONTRAST_lighter_first(L_a0a0a0, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xa0,0xa0,0xa0}()))))
prval S_accent_bg = SURFc(
  PAL0_accent(), PAL0_bg(), $CT.CONTRAST_lighter_second(L_2f6f4f, L_faf8f5),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfa,0xf8,0xf5}()))),
  PAL1_accent(), PAL1_bg(), $CT.CONTRAST_lighter_second(L_7a4f1d, L_f0e6d2),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xf0,0xe6,0xd2}()))),
  PAL2_accent(), PAL2_bg(), $CT.CONTRAST_lighter_first(L_7fc49b, L_1e1e1e),
    $H.NOVIB_text($H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()))))
prval S_accent_card = SURFc(
  PAL0_accent(), PAL0_card(), $CT.CONTRAST_lighter_second(L_2f6f4f, L_ffffff),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_accent(), PAL1_card(), $CT.CONTRAST_lighter_second(L_7a4f1d, L_f7efdf),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_accent(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7fc49b, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()))))
prval S_accentfg_accent = SURFc(
  PAL0_accentfg(), PAL0_accent(), $CT.CONTRAST_lighter_first(L_ffffff, L_2f6f4f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_accentfg(), PAL1_accent(), $CT.CONTRAST_lighter_first(L_ffffff, L_7a4f1d),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL2_accentfg(), PAL2_accent(), $CT.CONTRAST_lighter_second(L_10231a, L_7fc49b),
    $H.NOVIB_ground($H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()))))
prval S_barfg_bar = SURFc(
  PAL0_barfg(), PAL0_bar(), $CT.CONTRAST_lighter_first(L_ffffff, L_333333),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_barfg(), PAL1_bar(), $CT.CONTRAST_lighter_first(L_f7efdf, L_4a3b2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_barfg(), PAL2_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_111111),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_barfg_barhi = SURFc(
  PAL0_barfg(), PAL0_barhi(), $CT.CONTRAST_lighter_first(L_ffffff, L_4a4a4a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_barfg(), PAL1_barhi(), $CT.CONTRAST_lighter_first(L_f7efdf, L_5e4c38),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_barfg(), PAL2_barhi(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_2e2e2e),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_bannerfg_banner = SURFc(
  PAL0_bannerfg(), PAL0_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))),
  PAL1_bannerfg(), PAL1_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))),
  PAL2_bannerfg(), PAL2_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))))
prval S_markfg_mark = SURFc(
  PAL0_markfg(), PAL0_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  PAL1_markfg(), PAL1_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  PAL2_markfg(), PAL2_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))))
prval S_danger_card = SURFc(
  PAL0_danger(), PAL0_card(), $CT.CONTRAST_lighter_second(L_b3261e, L_ffffff),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_danger(), PAL1_card(), $CT.CONTRAST_lighter_second(L_9c2a1c, L_f7efdf),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_danger(), PAL2_card(), $CT.CONTRAST_lighter_first(L_ffb4ab, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}()))))
prval S_danger_line = SURFc(
  PAL0_danger(), PAL0_line(), $CT.CONTRAST_lighter_second(L_b3261e, L_dddddd),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xdd,0xdd,0xdd}()))),
  PAL1_danger(), PAL1_line(), $CT.CONTRAST_lighter_second(L_9c2a1c, L_d6c7a8),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xd6,0xc7,0xa8}()))),
  PAL2_danger(), PAL2_line(), $CT.CONTRAST_lighter_first(L_ffb4ab, L_3d3d3d),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}()))))
prval E_edge_card = EDGEc(
  PAL0_edge(), PAL0_card(), $CT.CONTRAST_lighter_second(L_8a8a8a, L_ffffff),
  PAL1_edge(), PAL1_card(), $CT.CONTRAST_lighter_second(L_8f7d62, L_f7efdf),
  PAL2_edge(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7a7a7a, L_2a2a2a))
prval E_accent_card = EDGEc(
  PAL0_accent(), PAL0_card(), $CT.CONTRAST_lighter_second(L_2f6f4f, L_ffffff),
  PAL1_accent(), PAL1_card(), $CT.CONTRAST_lighter_second(L_7a4f1d, L_f7efdf),
  PAL2_accent(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7fc49b, L_2a2a2a))
prval E_barfg_bar = EDGEc(
  PAL0_barfg(), PAL0_bar(), $CT.CONTRAST_lighter_first(L_ffffff, L_333333),
  PAL1_barfg(), PAL1_bar(), $CT.CONTRAST_lighter_first(L_f7efdf, L_4a3b2a),
  PAL2_barfg(), PAL2_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_111111))
prval H_light: HARMONY(0) = HARMONYc(
  PAL0_bg(), PAL0_fg(), PAL0_muted(), PAL0_card(), PAL0_line(), PAL0_edge(), PAL0_bar(), PAL0_barfg(), PAL0_accent(), PAL0_accentfg(), PAL0_hl(), PAL0_barhi(), PAL0_banner(), PAL0_bannerfg(), PAL0_mark(), PAL0_markfg(), PAL0_danger(),
  FAM_light($H.FAMILIESc()),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xfa,0xf8,0xf5}())), $H.HUE_r_g_b{0xfaf8f5,0xfa,0xf8,0xf5,25,50}($H.RGBc{0xfa,0xf8,0xf5}())),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x6b,0x6b,0x6b}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xdd,0xdd,0xdd}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x8a,0x8a,0x8a}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x33,0x33,0x33}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x4a,0x4a,0x4a}()))),
  $H.IN3_2($H.FAMILIESc(), $H.HUE_g_b_r{0x2f6f4f,0x2f,0x6f,0x4f,135,165}($H.RGBc{0x2f,0x6f,0x4f}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xfde59a,0xfd,0xe5,0x9a,25,50}($H.RGBc{0xfd,0xe5,0x9a}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,25,50}($H.RGBc{0xff,0xb3,0x00}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xb3261e,0xb3,0x26,0x1e,~15,15}($H.RGBc{0xb3,0x26,0x1e}())),
  $H.HUE_r_g_b{0xb3261e,0xb3,0x26,0x1e,~15,15}($H.RGBc{0xb3,0x26,0x1e}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0xfde59a,0xfd,0xe5,0x9a,30,60}($H.RGBc{0xfd,0xe5,0x9a}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.SATNEARc($H.MXMN_gbr($H.RGBc{0x2f,0x6f,0x4f}()), $H.MXMN_rgb($H.RGBc{0xb3,0x26,0x1e}())),
  $H.LIGHTERc(L_ffffff, L_faf8f5),
  $CT.CONTRAST_lighter_second(L_2a2a2a, L_faf8f5),
  MODE_light($H.LIGHTERc(L_faf8f5, L_2a2a2a)))
prval H_sepia: HARMONY(1) = HARMONYc(
  PAL1_bg(), PAL1_fg(), PAL1_muted(), PAL1_card(), PAL1_line(), PAL1_edge(), PAL1_bar(), PAL1_barfg(), PAL1_accent(), PAL1_accentfg(), PAL1_hl(), PAL1_barhi(), PAL1_banner(), PAL1_bannerfg(), PAL1_mark(), PAL1_markfg(), PAL1_danger(),
  FAM_sepia($H.FAMILIESc()),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xf0,0xe6,0xd2}())), $H.HUE_r_g_b{0xf0e6d2,0xf0,0xe6,0xd2,25,50}($H.RGBc{0xf0,0xe6,0xd2}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}())), $H.HUE_r_g_b{0x3b2f22,0x3b,0x2f,0x22,25,50}($H.RGBc{0x3b,0x2f,0x22}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x6e,0x5e,0x4a}())), $H.HUE_r_g_b{0x6e5e4a,0x6e,0x5e,0x4a,25,50}($H.RGBc{0x6e,0x5e,0x4a}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}())), $H.HUE_r_g_b{0xf7efdf,0xf7,0xef,0xdf,25,50}($H.RGBc{0xf7,0xef,0xdf}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xd6,0xc7,0xa8}())), $H.HUE_r_g_b{0xd6c7a8,0xd6,0xc7,0xa8,25,50}($H.RGBc{0xd6,0xc7,0xa8}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x8f,0x7d,0x62}())), $H.HUE_r_g_b{0x8f7d62,0x8f,0x7d,0x62,25,50}($H.RGBc{0x8f,0x7d,0x62}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x4a,0x3b,0x2a}())), $H.HUE_r_g_b{0x4a3b2a,0x4a,0x3b,0x2a,25,50}($H.RGBc{0x4a,0x3b,0x2a}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}())), $H.HUE_r_g_b{0xf7efdf,0xf7,0xef,0xdf,25,50}($H.RGBc{0xf7,0xef,0xdf}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x5e,0x4c,0x38}())), $H.HUE_r_g_b{0x5e4c38,0x5e,0x4c,0x38,25,50}($H.RGBc{0x5e,0x4c,0x38}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x7a4f1d,0x7a,0x4f,0x1d,25,50}($H.RGBc{0x7a,0x4f,0x1d}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xe4c68e,0xe4,0xc6,0x8e,25,50}($H.RGBc{0xe4,0xc6,0x8e}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,25,50}($H.RGBc{0xff,0xb3,0x00}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x9c2a1c,0x9c,0x2a,0x1c,~15,15}($H.RGBc{0x9c,0x2a,0x1c}())),
  $H.HUE_r_g_b{0x9c2a1c,0x9c,0x2a,0x1c,~15,15}($H.RGBc{0x9c,0x2a,0x1c}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0xe4c68e,0xe4,0xc6,0x8e,30,60}($H.RGBc{0xe4,0xc6,0x8e}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.SATNEARc($H.MXMN_rgb($H.RGBc{0x7a,0x4f,0x1d}()), $H.MXMN_rgb($H.RGBc{0x9c,0x2a,0x1c}())),
  $H.LIGHTERc(L_f7efdf, L_f0e6d2),
  $CT.CONTRAST_lighter_second(L_3b2f22, L_f0e6d2),
  MODE_light($H.LIGHTERc(L_f0e6d2, L_3b2f22)))
prval H_dark: HARMONY(2) = HARMONYc(
  PAL2_bg(), PAL2_fg(), PAL2_muted(), PAL2_card(), PAL2_line(), PAL2_edge(), PAL2_bar(), PAL2_barfg(), PAL2_accent(), PAL2_accentfg(), PAL2_hl(), PAL2_barhi(), PAL2_banner(), PAL2_bannerfg(), PAL2_mark(), PAL2_markfg(), PAL2_danger(),
  FAM_dark($H.FAMILIESc()),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x1e,0x1e,0x1e}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xa0,0xa0,0xa0}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x3d,0x3d,0x3d}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x7a,0x7a,0x7a}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x11,0x11,0x11}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x2e,0x2e,0x2e}()))),
  $H.IN3_2($H.FAMILIESc(), $H.HUE_g_b_r{0x7fc49b,0x7f,0xc4,0x9b,130,160}($H.RGBc{0x7f,0xc4,0x9b}())),
  $H.IN3_2($H.FAMILIESc(), $H.HUE_g_b_r{0x10231a,0x10,0x23,0x1a,130,160}($H.RGBc{0x10,0x23,0x1a}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x6d5e2f,0x6d,0x5e,0x2f,25,50}($H.RGBc{0x6d,0x5e,0x2f}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,25,50}($H.RGBc{0xff,0xb3,0x00}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xffb4ab,0xff,0xb4,0xab,~15,15}($H.RGBc{0xff,0xb4,0xab}())),
  $H.HUE_r_g_b{0xffb4ab,0xff,0xb4,0xab,~15,15}($H.RGBc{0xff,0xb4,0xab}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0x6d5e2f,0x6d,0x5e,0x2f,30,60}($H.RGBc{0x6d,0x5e,0x2f}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.SATNEARc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()), $H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}())),
  $H.LIGHTERc(L_2a2a2a, L_1e1e1e),
  $CT.CONTRAST_lighter_first(L_e2e2e2, L_1e1e1e),
  MODE_dark($H.LIGHTERc(L_e2e2e2, L_1e1e1e), $H.PEAKc($H.MXMN_rgb($H.RGBc{0x1e,0x1e,0x1e}())),
    $H.PEAKc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}())), $H.PEAKc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}())),
    $H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0x7a,0x7a,0x7a}()))))
(* END proofs *)

(* ============================================================
   The sheet: a builder with a budget of bytes left, so the whole
   sheet is proven to fit the style element (under 65536 bytes); and
   whether a rule or an @media block is open
   ============================================================ *)

stadef BUDGET = 60000

(* st: 0 top level, 1 in a rule, 2 in @media, 3 in a rule in @media *)
datavtype sheet(int, int) =
  | {n,r:nat | n + r <= BUDGET}{st:nat | st < 4} Sheet(r, st) of ($B.builder(n))

(* Bytes a selector or layout value may not hold: none of them can end
   a declaration or a rule, or make one !important *)
fn _plain {v:nat | v < 256} (v: int v): bool =
  v <> 59 && v <> 123 && v <> 125 && v <> 33

fun _put_plain {sn:nat}{i:nat | i <= sn}{n:nat | n + sn - i <= BUDGET} .<sn - i>.
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + sn - i] $B.builder(m),
   s: string sn, sl: int sn, i: int i): void =
  if i >= sl then ()
  else let
    val c = char2int1(string_get_at(s, i))
    val v = (if c >= 0 then (if c < 256 then c else 32) else 32): [v:nat | v < 256] int v
  in
    if _plain(v) then let val () = $B.put_char(b, v) in _put_plain(b, s, sl, i + 1) end
    else _put_plain(b, s, sl, i + 1)
  end

(* s, with any of ; { } ! dropped *)
fn plain {r:nat}{st:nat}{sn:nat | sn <= r}
  (sh: !sheet(r, st) >> sheet(r - sn, st), s: string sn): void = let
  val+ @Sheet(b) = sh
  val () = _put_plain(b, s, g1u2i(string1_length(s)), 0)
  prval () = fold@(sh)
in end

(* s as written: only this module's fixed text *)
fn raw {r:nat}{st:nat}{sn:nat | sn <= r}
  (sh: !sheet(r, st) >> sheet(r - sn, st), s: string sn): void = let
  val+ @Sheet(b) = sh
  val () = $B.bput(b, s)
  prval () = fold@(sh)
in end

fn _rgb {r:nat | r >= 7}{st:nat}{c:nat | c < 16777216}
  (sh: !sheet(r, st) >> sheet(r - 7, st), c: int c): void = let
  val+ @Sheet(b) = sh
  val () = $CT.put_rgb(b, c)
  prval () = fold@(sh)
in end

(* a small number (at most 11 bytes) *)
fn _int {r:nat | r >= 11}{st:nat}
  (sh: sheet(r, st), v: int): sheet(r - 11, st) = let
  val+ ~Sheet(b) = sh
  val () = $B.put_int(b, v)
in Sheet(b) end

fn _role_name {r:nat | r < NROLE} (r: int r): [k:pos | k <= 9] string k =
  case+ r of
  | 0 => "bg" | 1 => "fg" | 2 => "muted" | 3 => "card" | 4 => "line"
  | 5 => "edge" | 6 => "bar" | 7 => "barfg" | 8 => "accent" | 9 => "accentfg"
  | 10 => "hl" | 11 => "barhi" | 12 => "banner" | 13 => "bannerfg"
  | 14 => "mark" | 15 => "markfg" | _ => "danger"

(* var(--<role>) *)
fn _var {r:nat | r >= 16}{st:nat}{ro:nat | ro < NROLE}
  (sh: !sheet(r, st) >> [q:nat | q >= r - 16] sheet(q, st), ro: int ro): void = let
  val () = raw(sh, "var(--")
  val () = raw(sh, _role_name(ro))
in raw(sh, ")") end

(* ============================================================
   Rules
   ============================================================ *)


(* sel { *)
fn rule {r:nat}{st:nat | st == 0 || st == 2}{sn:nat | sn + 1 <= r}
  (sh: sheet(r, st), sel: string sn): sheet(r - sn - 1, st + 1) = let
  val () = plain(sh, sel)
  val () = raw(sh, "{")
  val+ ~Sheet(b) = sh
in Sheet(b) end

(* } *)
fn close {r:pos}{st:nat | st == 1 || st == 3}
  (sh: sheet(r, st)): sheet(r - 1, st - 1) = let
  val () = raw(sh, "}")
  val+ ~Sheet(b) = sh
in Sheet(b) end

(* @media cond { *)
fn media {r:nat}{sn:nat | sn + 8 <= r}
  (sh: sheet(r, 0), cond: string sn): sheet(r - sn - 8, 2) = let
  val () = raw(sh, "@media ")
  val () = plain(sh, cond)
  val () = raw(sh, "{")
  val+ ~Sheet(b) = sh
in Sheet(b) end

fn media_end {r:pos} (sh: sheet(r, 2)): sheet(r - 1, 0) = let
  val () = raw(sh, "}")
  val+ ~Sheet(b) = sh
in Sheet(b) end

(* ============================================================
   Declarations. Layout properties take any value (plain); the
   properties the guarantees rest on have no such door: colour and
   background come only from surf, fill and veil, borders of text
   fields only from the base rules, opacity only as 0.
   ============================================================ *)

#pub datatype prop =
  | Display | FlexDirection | Flex | FlexWrap | FlexBasis | AlignItems
  | AlignSelf | JustifyContent | Gap | Order
  | Padding | PaddingTop | PaddingBottom | PaddingLeft | PaddingRight
  | Margin | MarginTop | MarginBottom | MarginLeft | MarginRight
  | Width | MaxWidth | MinWidth | Height | MaxHeight | MinHeight | BoxSizing
  | FontFamily | FontSize | FontWeight | FontStyle | Font | LineHeight
  | LetterSpacing | TextTransform | TextAlign | TextOverflow | TextDecoration
  | WhiteSpace | Hyphens | Direction
  | Overflow | OverflowX | Position | Top | Bottom | Left | Right | Inset
  | ZIndex | Cursor | PointerEvents | TouchAction | ObjectFit
  | BorderRadius | BorderCollapse | BoxShadow | Outline | OutlineOffset
  | ColumnFill | ColumnGap | ColumnWidth | BreakAfter | BreakInside
  | Appearance

fn _prop_name (p: prop): [k:pos | k <= 16] string k =
  case+ p of
  | Display() => "display" | FlexDirection() => "flex-direction" | Flex() => "flex"
  | FlexWrap() => "flex-wrap" | FlexBasis() => "flex-basis" | AlignItems() => "align-items"
  | AlignSelf() => "align-self" | JustifyContent() => "justify-content" | Gap() => "gap"
  | Order() => "order" | Padding() => "padding" | PaddingTop() => "padding-top"
  | PaddingBottom() => "padding-bottom" | PaddingLeft() => "padding-left"
  | PaddingRight() => "padding-right" | Margin() => "margin" | MarginTop() => "margin-top"
  | MarginBottom() => "margin-bottom" | MarginLeft() => "margin-left"
  | MarginRight() => "margin-right" | Width() => "width" | MaxWidth() => "max-width"
  | MinWidth() => "min-width" | Height() => "height" | MaxHeight() => "max-height"
  | MinHeight() => "min-height" | BoxSizing() => "box-sizing" | FontFamily() => "font-family"
  | FontSize() => "font-size" | FontWeight() => "font-weight" | FontStyle() => "font-style"
  | Font() => "font" | LineHeight() => "line-height" | LetterSpacing() => "letter-spacing"
  | TextTransform() => "text-transform" | TextAlign() => "text-align"
  | TextOverflow() => "text-overflow" | TextDecoration() => "text-decoration"
  | WhiteSpace() => "white-space" | Hyphens() => "hyphens" | Direction() => "direction"
  | Overflow() => "overflow" | OverflowX() => "overflow-x" | Position() => "position"
  | Top() => "top" | Bottom() => "bottom" | Left() => "left" | Right() => "right"
  | Inset() => "inset" | ZIndex() => "z-index" | Cursor() => "cursor"
  | PointerEvents() => "pointer-events" | TouchAction() => "touch-action"
  | ObjectFit() => "object-fit" | BorderRadius() => "border-radius"
  | BorderCollapse() => "border-collapse" | BoxShadow() => "box-shadow"
  | Outline() => "outline" | OutlineOffset() => "outline-offset"
  | ColumnFill() => "column-fill" | ColumnGap() => "column-gap"
  | ColumnWidth() => "column-width" | BreakAfter() => "break-after"
  | BreakInside() => "break-inside" | Appearance() => "appearance"

(* prop:value; *)
fn lay {r:nat}{st:nat | st == 1 || st == 3}{sv:nat | sv + 18 <= r}
  (sh: sheet(r, st), p: prop, v: string sv): [q:nat | q >= r - sv - 18] sheet(q, st) = let
  val () = raw(sh, _prop_name(p))
  val () = raw(sh, ":")
  val () = plain(sh, v)
  val () = raw(sh, ";")
in sh end

(* color:var(--f);background-color:var(--b); : text f on b, proven *)
fn surf {r:nat | r >= 60}{st:nat | st == 1 || st == 3}{f,b:nat | f < NROLE; b < NROLE}
  (pf: SURF(f, b) | sh: sheet(r, st), f: int f, b: int b): [q:nat | q >= r - 60] sheet(q, st) = let
  val () = raw(sh, "color:")
  val () = _var(sh, f)
  val () = raw(sh, ";background-color:")
  val () = _var(sh, b)
  val () = raw(sh, ";")
in sh end

(* A ground with no text: a bar, a track, a placeholder *)
fn fill {r:nat | r >= 50}{st:nat | st == 1 || st == 3}{b:nat | b < NROLE}
  (sh: sheet(r, st), b: int b): [q:nat | q >= r - 50] sheet(q, st) = let
  val () = raw(sh, "background-color:")
  val () = _var(sh, b)
  val () = raw(sh, ";font-size:0;")
in sh end

(* A ground of white or black at alpha a%, with no text *)
fn tint {r:nat | r >= 60}{st:nat | st == 1 || st == 3}{a:nat | a <= 100}
  (sh: sheet(r, st), white: bool, a: int a): [q:nat | q >= r - 60] sheet(q, st) = let
  val () = raw(sh, (if white then "background-color:rgba(255,255,255," else "background-color:rgba(0,0,0,"): [k:pos | k <= 34] string k)
  val sh = _int(sh, a)
  val () = raw(sh, "%);font-size:0;")
in sh end

(* The veil behind a menu or dialog: dark, and its own text (none)
   transparent, so only what sits on it in a proven surface shows *)
fn veil {r:nat | r >= 60}{st:nat | st == 1 || st == 3}
  (sh: sheet(r, st)): [q:nat | q >= r - 60] sheet(q, st) =
  let val () = raw(sh, "background-color:rgba(0,0,0,.5);color:transparent;") in sh end

(* A decorative line in role ro (a card's outline, a separator): not
   what identifies a control, which the base rules give text fields *)
#pub datatype side = AllSides | TopSide | BottomSide | LeftSide

fn line {r:nat | r >= 60}{st:nat | st == 1 || st == 3}{w:pos | w <= 9}{ro:nat | ro < NROLE}
  (sh: sheet(r, st), s: side, w: int w, ro: int ro): [q:nat | q >= r - 60] sheet(q, st) = let
  val () = raw(sh, (case+ s of AllSides() => "border:" | TopSide() => "border-top:"
    | BottomSide() => "border-bottom:" | LeftSide() => "border-left:"): [k:pos | k <= 14] string k)
  val sh = _int(sh, w)
  val () = raw(sh, "px solid ")
  val () = _var(sh, ro)
  val () = raw(sh, ";")
in sh end

fn no_line {r:nat | r >= 12}{st:nat | st == 1 || st == 3}
  (sh: sheet(r, st)): [q:nat | q >= r - 12] sheet(q, st) =
  let val () = raw(sh, "border:none;") in sh end

(* A control's accent (a slider's fill and thumb) in role a on b *)
fn accent {r:nat | r >= 40}{st:nat | st == 1 || st == 3}{a,b:nat | a < NROLE; b < NROLE}
  (pf: EDGEP(a, b) | sh: sheet(r, st), a: int a, b: int b): [q:nat | q >= r - 40] sheet(q, st) = let
  val () = raw(sh, "accent-color:")
  val () = _var(sh, a)
  val () = raw(sh, ";")
in sh end

(* translateX(-50%): the only transform, which moves and never scales *)
fn centre_x {r:nat | r >= 32}{st:nat | st == 1 || st == 3}
  (sh: sheet(r, st)): [q:nat | q >= r - 32] sheet(q, st) =
  let val () = raw(sh, "transform:translateX(-50%);") in sh end

(* opacity 0: an invisible target over a visible one (a file input) *)
fn invisible {r:nat | r >= 12}{st:nat | st == 1 || st == 3}
  (sh: sheet(r, st)): [q:nat | q >= r - 12] sheet(q, st) =
  let val () = raw(sh, "opacity:0;") in sh end

(* ============================================================
   The themes and the base rules
   ============================================================ *)

fn _decl_rgb {r:nat | r >= 30}{ro:nat | ro < NROLE}{c:nat | c < 16777216}
  (sh: sheet(r, 1), ro: int ro, c: int c): [q:nat | q >= r - 30] sheet(q, 1) = let
  val () = raw(sh, "--")
  val () = raw(sh, _role_name(ro))
  val () = raw(sh, ":")
  val () = _rgb(sh, c)
  val () = raw(sh, ";")
in sh end

(* .th-<name>{--role:#rrggbb;...} for theme t: each colour is the one
   PAL gives, so the proofs above are about these *)
fn theme {t:int}{r:nat | r >= 700}{sn:nat | sn <= 20}
  {c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,c16:nat |
   c0 < 16777216; c1 < 16777216; c2 < 16777216; c3 < 16777216; c4 < 16777216;
   c5 < 16777216; c6 < 16777216; c7 < 16777216; c8 < 16777216; c9 < 16777216;
   c10 < 16777216; c11 < 16777216; c12 < 16777216; c13 < 16777216; c14 < 16777216;
   c15 < 16777216; c16 < 16777216}
  (p0: PAL(t, BG, c0), p1: PAL(t, FG, c1), p2: PAL(t, MUTED, c2), p3: PAL(t, CARD, c3),
   p4: PAL(t, LINE, c4), p5: PAL(t, EDGE, c5), p6: PAL(t, BAR, c6), p7: PAL(t, BARFG, c7),
   p8: PAL(t, ACCENT, c8), p9: PAL(t, ACCENTFG, c9), p10: PAL(t, HL, c10),
   p11: PAL(t, BARHI, c11), p12: PAL(t, BANNER, c12), p13: PAL(t, BANNERFG, c13),
   p14: PAL(t, MARK, c14), p15: PAL(t, MARKFG, c15), p16: PAL(t, DANGER, c16),
   ph: HARMONY(t) |
   sh: sheet(r, 0), sel: string sn,
   c0: int c0, c1: int c1, c2: int c2, c3: int c3, c4: int c4, c5: int c5, c6: int c6,
   c7: int c7, c8: int c8, c9: int c9, c10: int c10, c11: int c11, c12: int c12,
   c13: int c13, c14: int c14, c15: int c15, c16: int c16): [q:nat | q >= r - 700] sheet(q, 0) = let
  val sh = rule(sh, sel)
  val sh = _decl_rgb(sh, 0, c0)
  val sh = _decl_rgb(sh, 1, c1)
  val sh = _decl_rgb(sh, 2, c2)
  val sh = _decl_rgb(sh, 3, c3)
  val sh = _decl_rgb(sh, 4, c4)
  val sh = _decl_rgb(sh, 5, c5)
  val sh = _decl_rgb(sh, 6, c6)
  val sh = _decl_rgb(sh, 7, c7)
  val sh = _decl_rgb(sh, 8, c8)
  val sh = _decl_rgb(sh, 9, c9)
  val sh = _decl_rgb(sh, 10, c10)
  val sh = _decl_rgb(sh, 11, c11)
  val sh = _decl_rgb(sh, 12, c12)
  val sh = _decl_rgb(sh, 13, c13)
  val sh = _decl_rgb(sh, 14, c14)
  val sh = _decl_rgb(sh, 15, c15)
  val sh = _decl_rgb(sh, 16, c16)
in close(sh) end

(* The rules the guarantees rest on; the only !important in the sheet *)
fn _base {r:nat | r >= 1400} (sh: sheet(r, 0)): [q:nat | q >= r - 1400] sheet(q, 0) = let
  val () = raw(sh, "[data-hide='1'],[hidden]{display:none!important}")
  (* 44 x 44 targets: every button and field, and everything given a
     control's role; links in a book's text are inline targets, which
     WCAG leaves to the text they sit in *)
  val () = raw(sh, "button,input,select,textarea,[role=button],[role=menuitem],[role=tab],[role=slider],[role=option],[role=switch]")
  val () = raw(sh, "{min-height:44px!important;min-width:44px!important;box-sizing:border-box}")
  (* 16px in text fields, so iOS does not zoom into them *)
  val () = raw(sh, "input,select,textarea{font-size:16px!important}")
  (* focus: 2px inside the edge in the control's own proven colour *)
  val () = raw(sh, ":focus-visible{outline:2px solid currentColor!important;outline-offset:-2px!important}")
  (* text fields: fg on card with a 3:1 edge (S_fg_card, E_edge_card) *)
  prval _ = S_fg_card
  prval _ = E_edge_card
  val () = raw(sh, "input:not([type=range]):not([type=file]),textarea,select")
  val () = raw(sh, "{color:var(--fg)!important;background-color:var(--card)!important;border:1px solid var(--edge)!important}")
  (* a search field's own clear button is too small a target *)
  val () = raw(sh, "input[type=search]::-webkit-search-cancel-button{display:none}")
  (* a button is a surface like any other: fg on card until a rule
     says otherwise *)
  prval _ = S_fg_card
  val () = raw(sh, "button{font:inherit;cursor:pointer;color:var(--fg);background-color:var(--card);border:0}")
in sh end

(* ============================================================
   The stylesheet
   ============================================================ *)

fn _g_0_fonts {r:nat | r >= 403} (sh: sheet(r, 0)): [q:nat | q >= r - 403] sheet(q, 0) = let
  val () = raw(sh, "@font-face{font-family:Literata;src:url(literata-latin.woff2) format('woff2');font-style:normal;font-weight:200 900;font-display:swap}")
  val () = raw(sh, "@font-face{font-family:Literata;src:url(literata-italic-latin.woff2) format('woff2');font-style:italic;font-weight:200 900;font-display:swap}")
  val () = raw(sh, "@font-face{font-family:Inter;src:url(inter-latin.woff2) format('woff2');font-style:normal;font-weight:100 900;font-display:swap}")
in sh end

fn _g_1_shell {r:nat | r >= 4429} (sh: sheet(r, 0)): [q:nat | q >= r - 4429] sheet(q, 0) = let
  val sh = rule(sh, "body")
  val sh = lay(sh, Margin(), "0")
  val sh = surf(S_fg_bg | sh, 1, 0)
  val sh = close(sh)
  val sh = rule(sh, ".app")
  val sh = lay(sh, MinHeight(), "100vh")
  val sh = surf(S_fg_bg | sh, 1, 0)
  val sh = lay(sh, FontFamily(), "Inter,system-ui,sans-serif")
  val sh = lay(sh, FontSize(), "16px")
  val sh = lay(sh, LineHeight(), "1.4")
  val sh = close(sh)
  val sh = rule(sh, ".lib")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexDirection(), "column")
  val sh = lay(sh, MaxWidth(), "800px")
  val sh = lay(sh, Margin(), "0 auto")
  val sh = lay(sh, Padding(), "max(12px,env(safe-area-inset-top)) 16px 24px")
  val sh = lay(sh, BoxSizing(), "border-box")
  val sh = lay(sh, MinHeight(), "100vh")
  val sh = close(sh)
  val sh = rule(sh, ".lib.drag")
  val sh = lay(sh, Outline(), "3px dashed var(--accent)")
  val sh = lay(sh, OutlineOffset(), "-8px")
  val sh = close(sh)
  val sh = rule(sh, ".bar")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexWrap(), "wrap")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Gap(), "8px")
  val sh = lay(sh, Padding(), "8px 0")
  val sh = line(sh, BottomSide(), 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".ttl")
  val sh = lay(sh, FontFamily(), "Literata,Georgia,serif")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = lay(sh, FontSize(), "22px")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, Margin(), "0")
  val sh = close(sh)
  val sh = rule(sh, ".btn")
  val sh = lay(sh, Display(), "inline-flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, JustifyContent(), "center")
  val sh = lay(sh, Padding(), "8px 14px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = line(sh, AllSides(), 1, 4)
  val sh = lay(sh, FontSize(), "15px")
  val sh = lay(sh, Position(), "relative")
  val sh = lay(sh, Overflow(), "hidden")
  val sh = close(sh)
  val sh = rule(sh, ".btn-p")
  val sh = surf(S_accentfg_accent | sh, 9, 8)
  val sh = line(sh, AllSides(), 1, 8)
  val sh = close(sh)
  val sh = rule(sh, ".btn input[type=file]")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Top(), "0")
  val sh = lay(sh, Left(), "0")
  val sh = lay(sh, Width(), "100%")
  val sh = lay(sh, Height(), "100%")
  val sh = invisible(sh)
  val sh = lay(sh, Cursor(), "pointer")
  val sh = lay(sh, FontSize(), "0")
  val sh = close(sh)
  val sh = rule(sh, ".ibtn")
  val sh = lay(sh, FontSize(), "20px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = surf(S_fg_bg | sh, 1, 0)
  val sh = close(sh)
  val sh = rule(sh, ".sfield")
  val sh = lay(sh, FlexBasis(), "100%")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Gap(), "4px")
  val sh = close(sh)
  val sh = rule(sh, ".search")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, MinWidth(), "0")
  val sh = lay(sh, Padding(), "6px 10px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = close(sh)
  val sh = rule(sh, ".banner")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "8px")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Margin(), "8px 0")
  val sh = lay(sh, Padding(), "10px 12px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = surf(S_bannerfg_banner | sh, 13, 12)
  val sh = close(sh)
  val sh = rule(sh, ".banner .ibtn")
  val sh = surf(S_bannerfg_banner | sh, 13, 12)
  val sh = close(sh)
  val sh = rule(sh, ".banner span")
  val sh = lay(sh, Flex(), "1")
  val sh = close(sh)
  val sh = rule(sh, ".imp")
  val sh = lay(sh, Margin(), "8px 0")
  val sh = lay(sh, Padding(), "10px 12px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = line(sh, AllSides(), 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".imp-n")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = lay(sh, Overflow(), "hidden")
  val sh = lay(sh, TextOverflow(), "ellipsis")
  val sh = lay(sh, WhiteSpace(), "nowrap")
  val sh = close(sh)
  val sh = rule(sh, ".imp-s")
  val sh = surf(S_muted_card | sh, 2, 3)
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
  val sh = rule(sh, ".imp-bar")
  val sh = lay(sh, Height(), "6px")
  val sh = fill(sh, 4)
  val sh = lay(sh, BorderRadius(), "3px")
  val sh = lay(sh, MarginTop(), "6px")
  val sh = lay(sh, Overflow(), "hidden")
  val sh = close(sh)
  val sh = rule(sh, ".imp-fill")
  val sh = lay(sh, Height(), "100%")
  val sh = fill(sh, 8)
  val sh = lay(sh, Width(), "0")
  val sh = close(sh)
  val sh = rule(sh, ".list")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexDirection(), "column")
  val sh = close(sh)
  val sh = rule(sh, ".cardrow")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "stretch")
  val sh = lay(sh, Gap(), "6px")
  val sh = lay(sh, Margin(), "6px 0")
  val sh = close(sh)
  val sh = rule(sh, ".card")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, MinWidth(), "0")
  val sh = lay(sh, TextAlign(), "left")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "12px")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Padding(), "10px")
  val sh = line(sh, AllSides(), 1, 4)
  val sh = lay(sh, BorderRadius(), "8px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = lay(sh, Cursor(), "pointer")
  val sh = close(sh)
  val sh = rule(sh, ".card *")
  val sh = lay(sh, PointerEvents(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".cmore")
  val sh = lay(sh, FontSize(), "22px")
  val sh = lay(sh, BorderRadius(), "8px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = line(sh, AllSides(), 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".cov")
  val sh = lay(sh, Width(), "48px")
  val sh = lay(sh, Height(), "72px")
  val sh = lay(sh, ObjectFit(), "cover")
  val sh = lay(sh, BorderRadius(), "3px")
  val sh = lay(sh, Flex(), "none")
  val sh = fill(sh, 4)
  val sh = close(sh)
  val sh = rule(sh, ".cinfo")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, MinWidth(), "0")
  val sh = close(sh)
  val sh = rule(sh, ".bt")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = lay(sh, FontSize(), "16px")
  val sh = lay(sh, Overflow(), "hidden")
  val sh = lay(sh, TextOverflow(), "ellipsis")
  val sh = close(sh)
  val sh = rule(sh, ".ba")
  val sh = surf(S_muted_card | sh, 2, 3)
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
  val sh = rule(sh, ".prog")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Gap(), "8px")
  val sh = surf(S_muted_card | sh, 2, 3)
  val sh = lay(sh, FontSize(), "13px")
  val sh = lay(sh, MarginTop(), "4px")
  val sh = close(sh)
  val sh = rule(sh, ".pbar")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, MaxWidth(), "160px")
  val sh = lay(sh, Height(), "5px")
  val sh = fill(sh, 4)
  val sh = lay(sh, BorderRadius(), "3px")
  val sh = lay(sh, Overflow(), "hidden")
  val sh = close(sh)
  val sh = rule(sh, ".pfill")
  val sh = lay(sh, Height(), "100%")
  val sh = fill(sh, 8)
  val sh = close(sh)
  val sh = rule(sh, ".empty")
  val sh = lay(sh, TextAlign(), "center")
  val sh = surf(S_muted_bg | sh, 2, 0)
  val sh = lay(sh, Padding(), "16px")
  val sh = lay(sh, MarginTop(), "15vh")
  val sh = lay(sh, FontSize(), "18px")
  val sh = lay(sh, FontStyle(), "italic")
  val sh = close(sh)
in sh end

fn _g_2_overlays {r:nat | r >= 2793} (sh: sheet(r, 0)): [q:nat | q >= r - 2793] sheet(q, 0) = let
  val sh = rule(sh, ".toast")
  val sh = lay(sh, Position(), "fixed")
  val sh = lay(sh, Left(), "50%")
  val sh = lay(sh, Bottom(), "calc(env(safe-area-inset-bottom) + 112px)")
  val sh = centre_x(sh)
  val sh = lay(sh, ZIndex(), "18")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "12px")
  val sh = lay(sh, AlignItems(), "center")
  val sh = surf(S_barfg_bar | sh, 7, 6)
  val sh = lay(sh, BorderRadius(), "8px")
  val sh = lay(sh, Padding(), "4px 4px 4px 16px")
  val sh = lay(sh, BoxShadow(), "0 2px 12px rgba(0,0,0,.35)")
  val sh = lay(sh, Width(), "max-content")
  val sh = lay(sh, MaxWidth(), "min(92vw,420px)")
  val sh = close(sh)
  val sh = rule(sh, ".ovl")
  val sh = lay(sh, Position(), "fixed")
  val sh = lay(sh, Inset(), "0")
  val sh = veil(sh)
  val sh = lay(sh, ZIndex(), "20")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, JustifyContent(), "center")
  val sh = close(sh)
  val sh = rule(sh, ".menu,.mbox")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = lay(sh, BorderRadius(), "8px")
  val sh = lay(sh, Padding(), "8px")
  val sh = lay(sh, MinWidth(), "200px")
  val sh = lay(sh, MaxWidth(), "min(92vw,420px)")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexDirection(), "column")
  val sh = lay(sh, BoxShadow(), "0 4px 24px rgba(0,0,0,.3)")
  val sh = close(sh)
  val sh = rule(sh, ".mi")
  val sh = lay(sh, TextAlign(), "left")
  val sh = lay(sh, Padding(), "12px 14px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = close(sh)
  val sh = rule(sh, ".mi:hover")
  val sh = surf(S_fg_line | sh, 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".mi[data-harm=y]")
  val sh = surf(S_danger_card | sh, 16, 3)
  val sh = close(sh)
  val sh = rule(sh, ".mi[data-harm=y]:hover")
  val sh = surf(S_danger_line | sh, 16, 4)
  val sh = close(sh)
  val sh = rule(sh, ".menu .mi.btn")
  val sh = no_line(sh)
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = lay(sh, JustifyContent(), "flex-start")
  val sh = lay(sh, Padding(), "12px 14px")
  val sh = lay(sh, FontSize(), "inherit")
  val sh = close(sh)
  val sh = rule(sh, ".mbox")
  val sh = lay(sh, Padding(), "16px")
  val sh = lay(sh, Gap(), "12px")
  val sh = close(sh)
  val sh = rule(sh, ".mtitle")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = lay(sh, FontSize(), "18px")
  val sh = close(sh)
  val sh = rule(sh, ".mta")
  val sh = lay(sh, MinHeight(), "120px")
  val sh = lay(sh, Font(), "inherit")
  val sh = lay(sh, Padding(), "8px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = close(sh)
  val sh = rule(sh, ".mbtns")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "8px")
  val sh = lay(sh, JustifyContent(), "flex-end")
  val sh = lay(sh, FlexWrap(), "wrap")
  val sh = close(sh)
  val sh = rule(sh, ".btn[data-harm=y]")
  val sh = surf(S_danger_card | sh, 16, 3)
  val sh = line(sh, AllSides(), 1, 16)
  val sh = close(sh)
  val sh = rule(sh, ".info")
  val sh = lay(sh, Position(), "fixed")
  val sh = lay(sh, Inset(), "0")
  val sh = lay(sh, ZIndex(), "15")
  val sh = surf(S_fg_bg | sh, 1, 0)
  val sh = lay(sh, Overflow(), "auto")
  val sh = lay(sh, Padding(), "max(12px,env(safe-area-inset-top)) 16px 24px")
  val sh = close(sh)
  val sh = rule(sh, ".info-in")
  val sh = lay(sh, MaxWidth(), "600px")
  val sh = lay(sh, Margin(), "0 auto")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexDirection(), "column")
  val sh = lay(sh, Gap(), "8px")
  val sh = close(sh)
  val sh = rule(sh, ".info-in>.btn")
  val sh = lay(sh, AlignSelf(), "flex-start")
  val sh = close(sh)
  val sh = rule(sh, ".icov")
  val sh = lay(sh, Width(), "160px")
  val sh = lay(sh, MaxWidth(), "50vw")
  val sh = lay(sh, MaxHeight(), "300px")
  val sh = lay(sh, ObjectFit(), "contain")
  val sh = lay(sh, AlignSelf(), "center")
  val sh = lay(sh, BorderRadius(), "4px")
  val sh = close(sh)
  val sh = rule(sh, ".it")
  val sh = lay(sh, FontFamily(), "Literata,Georgia,serif")
  val sh = lay(sh, FontSize(), "22px")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = close(sh)
  val sh = rule(sh, ".irow")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, JustifyContent(), "space-between")
  val sh = line(sh, BottomSide(), 1, 4)
  val sh = lay(sh, Padding(), "8px 0")
  val sh = surf(S_muted_bg | sh, 2, 0)
  val sh = close(sh)
  val sh = rule(sh, ".irow b")
  val sh = surf(S_fg_bg | sh, 1, 0)
  val sh = lay(sh, FontWeight(), "normal")
  val sh = close(sh)
in sh end

fn _g_3_reader {r:nat | r >= 5447} (sh: sheet(r, 0)): [q:nat | q >= r - 5447] sheet(q, 0) = let
  val sh = rule(sh, ".rv")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexDirection(), "column")
  val sh = lay(sh, Height(), "100vh")
  val sh = lay(sh, Position(), "relative")
  val sh = surf(S_fg_bg | sh, 1, 0)
  val sh = close(sh)
  val sh = rule(sh, ".top,.bot")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Gap(), "4px")
  val sh = lay(sh, Padding(), "2px 6px")
  val sh = surf(S_barfg_bar | sh, 7, 6)
  val sh = lay(sh, ZIndex(), "3")
  val sh = close(sh)
  val sh = rule(sh, ".top")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Top(), "0")
  val sh = lay(sh, Left(), "0")
  val sh = lay(sh, Right(), "0")
  val sh = lay(sh, PaddingTop(), "max(2px,env(safe-area-inset-top))")
  val sh = close(sh)
  val sh = rule(sh, ".bot")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Bottom(), "0")
  val sh = lay(sh, Left(), "0")
  val sh = lay(sh, Right(), "0")
  val sh = lay(sh, FlexWrap(), "wrap")
  val sh = lay(sh, PaddingBottom(), "max(2px,env(safe-area-inset-bottom))")
  val sh = close(sh)
  val sh = rule(sh, ".top .ibtn,.bot .ibtn,.snavf .ibtn")
  val sh = surf(S_barfg_bar | sh, 7, 6)
  val sh = close(sh)
  val sh = rule(sh, ".top .ibtn:hover,.bot .ibtn:hover,.snavf .ibtn:hover")
  val sh = surf(S_barfg_barhi | sh, 7, 11)
  val sh = close(sh)
  val sh = rule(sh, ".ctitle")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, FontSize(), "14px")
  val sh = lay(sh, Overflow(), "hidden")
  val sh = lay(sh, WhiteSpace(), "nowrap")
  val sh = lay(sh, TextOverflow(), "ellipsis")
  val sh = close(sh)
  val sh = rule(sh, ".pinfo")
  val sh = lay(sh, FontSize(), "13px")
  val sh = lay(sh, WhiteSpace(), "nowrap")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, TextAlign(), "center")
  val sh = close(sh)
  val sh = rule(sh, ".chrome-off .top,.chrome-off .bot")
  val sh = lay(sh, Display(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".caf")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, Overflow(), "hidden")
  val sh = lay(sh, BoxSizing(), "border-box")
  val sh = lay(sh, PaddingTop(), "max(48px,env(safe-area-inset-top))")
  val sh = lay(sh, PaddingBottom(), "max(36px,env(safe-area-inset-bottom))")
  val sh = lay(sh, ColumnFill(), "auto")
  val sh = lay(sh, ColumnGap(), "0")
  val sh = lay(sh, ColumnWidth(), "100vw")
  val sh = lay(sh, FontFamily(), "Literata,Georgia,serif")
  val sh = lay(sh, FontSize(), "18px")
  val sh = lay(sh, LineHeight(), "1.6")
  val sh = lay(sh, Outline(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".caf>*")
  val sh = lay(sh, MaxWidth(), "38rem")
  val sh = lay(sh, MarginLeft(), "auto")
  val sh = lay(sh, MarginRight(), "auto")
  val sh = lay(sh, BoxSizing(), "border-box")
  val sh = close(sh)
  (* a paragraph's alignment, hyphenation and the space after it are
     the reader's settings (settings.bats, in qdyn) *)
  val sh = rule(sh, ".caf p")
  val sh = lay(sh, Margin(), "0 auto .8em")
  val sh = close(sh)
  val sh = rule(sh, ".caf h1,.caf h2,.caf h3")
  val sh = lay(sh, TextAlign(), "center")
  val sh = lay(sh, MarginTop(), "1.5em")
  val sh = lay(sh, MarginBottom(), ".5em")
  val sh = lay(sh, BreakAfter(), "avoid")
  val sh = close(sh)
  val sh = rule(sh, ".caf hr")
  val sh = no_line(sh)
  val sh = line(sh, TopSide(), 1, 4)
  val sh = lay(sh, Margin(), "2em auto")
  val sh = lay(sh, MaxWidth(), "200px")
  val sh = close(sh)
  val sh = rule(sh, ".caf img")
  val sh = lay(sh, MaxWidth(), "100%")
  val sh = lay(sh, MaxHeight(), "calc(100vh - 110px)")
  val sh = lay(sh, ObjectFit(), "contain")
  val sh = lay(sh, Height(), "auto")
  val sh = lay(sh, Display(), "block")
  val sh = lay(sh, Margin(), "0 auto")
  val sh = lay(sh, BreakInside(), "avoid")
  val sh = close(sh)
  val sh = rule(sh, ".caf table")
  val sh = lay(sh, Display(), "block")
  val sh = lay(sh, OverflowX(), "auto")
  val sh = lay(sh, MaxWidth(), "100%")
  val sh = lay(sh, BorderCollapse(), "collapse")
  val sh = close(sh)
  val sh = rule(sh, ".caf td,.caf th")
  val sh = line(sh, AllSides(), 1, 4)
  val sh = lay(sh, Padding(), "2px 6px")
  val sh = close(sh)
  val sh = rule(sh, ".caf a,.caf [role=link]")
  val sh = surf(S_accent_bg | sh, 8, 0)
  val sh = lay(sh, TextDecoration(), "underline")
  val sh = lay(sh, Cursor(), "pointer")
  val sh = close(sh)
  val sh = rule(sh, ".caf pre")
  val sh = lay(sh, WhiteSpace(), "pre-wrap")
  val sh = close(sh)
  val sh = rule(sh, ".caf blockquote")
  val sh = lay(sh, Margin(), "1em auto")
  val sh = lay(sh, FontStyle(), "italic")
  val sh = close(sh)
  val sh = rule(sh, ".caf.rtl>*")
  val sh = lay(sh, Direction(), "rtl")
  val sh = close(sh)
  val sh = rule(sh, ".caf figure")
  val sh = lay(sh, Margin(), "1em auto")
  val sh = close(sh)
  val sh = rule(sh, ".caf sup,.caf sub")
  val sh = lay(sh, LineHeight(), "0")
  val sh = close(sh)
  val sh = rule(sh, "::highlight(bats-mark-1)")
  val sh = surf(S_fg_hl | sh, 1, 10)
  val sh = close(sh)
  val sh = rule(sh, "::highlight(bats-mark-2)")
  val sh = surf(S_markfg_mark | sh, 15, 14)
  val sh = close(sh)
  val sh = rule(sh, ".scr")
  val sh = lay(sh, FlexBasis(), "100%")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Gap(), "8px")
  val sh = lay(sh, Padding(), "0 6px")
  val sh = close(sh)
  val sh = rule(sh, ".trk")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, Position(), "relative")
  val sh = lay(sh, Height(), "44px")
  val sh = lay(sh, Cursor(), "pointer")
  val sh = lay(sh, TouchAction(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".trk-l")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Left(), "0")
  val sh = lay(sh, Right(), "0")
  val sh = lay(sh, Top(), "20px")
  val sh = lay(sh, Height(), "4px")
  val sh = tint(sh, true, 30)
  val sh = lay(sh, BorderRadius(), "2px")
  val sh = lay(sh, PointerEvents(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".trk-f")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Left(), "0")
  val sh = lay(sh, Top(), "20px")
  val sh = lay(sh, Height(), "4px")
  val sh = fill(sh, 7)
  val sh = lay(sh, BorderRadius(), "2px")
  val sh = lay(sh, PointerEvents(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".tick")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Top(), "16px")
  val sh = lay(sh, Width(), "2px")
  val sh = lay(sh, Height(), "12px")
  val sh = tint(sh, true, 60)
  val sh = lay(sh, PointerEvents(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".thumb")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Top(), "10px")
  val sh = lay(sh, Width(), "24px")
  val sh = lay(sh, Height(), "24px")
  val sh = lay(sh, MarginLeft(), "-12px")
  val sh = lay(sh, BorderRadius(), "50%")
  val sh = fill(sh, 7)
  val sh = lay(sh, PointerEvents(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".tip")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Bottom(), "46px")
  val sh = centre_x(sh)
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = lay(sh, Padding(), "2px 8px")
  val sh = lay(sh, BorderRadius(), "4px")
  val sh = lay(sh, FontSize(), "13px")
  val sh = lay(sh, WhiteSpace(), "nowrap")
  val sh = lay(sh, PointerEvents(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".pct")
  val sh = lay(sh, FontSize(), "13px")
  val sh = lay(sh, MinWidth(), "3em")
  val sh = lay(sh, TextAlign(), "right")
  val sh = close(sh)
  val sh = rule(sh, ".pback")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Left(), "12px")
  val sh = lay(sh, Bottom(), "106px")
  val sh = lay(sh, ZIndex(), "4")
  val sh = surf(S_accentfg_accent | sh, 9, 8)
  val sh = lay(sh, BorderRadius(), "22px")
  val sh = lay(sh, Padding(), "8px 16px")
  val sh = lay(sh, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sh = close(sh)
  val sh = rule(sh, ".seltb")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Left(), "50%")
  val sh = lay(sh, Bottom(), "106px")
  val sh = centre_x(sh)
  val sh = lay(sh, ZIndex(), "5")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "4px")
  val sh = surf(S_barfg_bar | sh, 7, 6)
  val sh = lay(sh, BorderRadius(), "10px")
  val sh = lay(sh, Padding(), "4px")
  val sh = lay(sh, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sh = close(sh)
  val sh = rule(sh, ".seltb button")
  val sh = lay(sh, Padding(), "8px 14px")
  val sh = surf(S_barfg_bar | sh, 7, 6)
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = close(sh)
  val sh = rule(sh, ".seltb button:hover")
  val sh = surf(S_barfg_barhi | sh, 7, 11)
  val sh = close(sh)
  val sh = rule(sh, ".snavf")
  val sh = lay(sh, Position(), "absolute")
  val sh = lay(sh, Left(), "50%")
  val sh = lay(sh, Top(), "max(56px,calc(env(safe-area-inset-top) + 54px))")
  val sh = centre_x(sh)
  val sh = lay(sh, ZIndex(), "6")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "6px")
  val sh = lay(sh, AlignItems(), "center")
  val sh = surf(S_barfg_bar | sh, 7, 6)
  val sh = lay(sh, BorderRadius(), "24px")
  val sh = lay(sh, Padding(), "2px 8px")
  val sh = lay(sh, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
  val sh = rule(sh, ".snavf span")
  val sh = lay(sh, WhiteSpace(), "nowrap")
  val sh = lay(sh, Padding(), "0 4px")
  val sh = close(sh)
in sh end

fn _g_4_panels {r:nat | r >= 4611} (sh: sheet(r, 0)): [q:nat | q >= r - 4611] sheet(q, 0) = let
  val sh = rule(sh, ".panel")
  val sh = lay(sh, Position(), "fixed")
  val sh = lay(sh, Top(), "0")
  val sh = lay(sh, Bottom(), "0")
  val sh = lay(sh, Left(), "0")
  val sh = lay(sh, Width(), "min(420px,100vw)")
  val sh = lay(sh, ZIndex(), "12")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexDirection(), "column")
  val sh = lay(sh, BoxShadow(), "2px 0 16px rgba(0,0,0,.3)")
  val sh = lay(sh, PaddingTop(), "env(safe-area-inset-top)")
  val sh = close(sh)
  val sh = rule(sh, ".panel-r")
  val sh = lay(sh, Left(), "auto")
  val sh = lay(sh, Right(), "0")
  val sh = close(sh)
  val sh = rule(sh, ".ph")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Gap(), "6px")
  val sh = lay(sh, Padding(), "6px 8px")
  val sh = line(sh, BottomSide(), 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".ph .grow")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = close(sh)
  val sh = rule(sh, ".ph .ibtn")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = close(sh)
  val sh = rule(sh, ".tabs")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "4px")
  val sh = close(sh)
  val sh = rule(sh, ".tab")
  val sh = lay(sh, Padding(), "8px 12px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = close(sh)
  val sh = rule(sh, ".tab[aria-selected=true]")
  val sh = surf(S_fg_line | sh, 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".plist")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, Overflow(), "auto")
  val sh = lay(sh, Padding(), "4px 0")
  val sh = close(sh)
  val sh = rule(sh, ".pi")
  val sh = lay(sh, Display(), "block")
  val sh = lay(sh, Width(), "100%")
  val sh = lay(sh, TextAlign(), "left")
  val sh = lay(sh, Padding(), "10px 14px")
  val sh = lay(sh, BoxSizing(), "border-box")
  val sh = line(sh, BottomSide(), 1, 4)
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = close(sh)
  val sh = rule(sh, ".pi[aria-current=true]")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = surf(S_fg_line | sh, 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".pi1")
  val sh = lay(sh, PaddingLeft(), "30px")
  val sh = close(sh)
  val sh = rule(sh, ".pi2")
  val sh = lay(sh, PaddingLeft(), "46px")
  val sh = close(sh)
  val sh = rule(sh, ".pi3")
  val sh = lay(sh, PaddingLeft(), "62px")
  val sh = close(sh)
  val sh = rule(sh, ".snip")
  val sh = lay(sh, Display(), "block")
  val sh = surf(S_muted_card | sh, 2, 3)
  val sh = lay(sh, FontSize(), "13px")
  val sh = lay(sh, MarginTop(), "2px")
  val sh = close(sh)
  val sh = rule(sh, ".hq")
  val sh = lay(sh, Display(), "block")
  val sh = line(sh, LeftSide(), 3, 8)
  val sh = lay(sh, PaddingLeft(), "8px")
  val sh = lay(sh, FontStyle(), "italic")
  val sh = close(sh)
  val sh = rule(sh, ".hn")
  val sh = lay(sh, Display(), "block")
  val sh = lay(sh, MarginTop(), "4px")
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
  val sh = rule(sh, ".hbtns")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "8px")
  val sh = lay(sh, MarginTop(), "6px")
  val sh = close(sh)
  val sh = rule(sh, ".hbtns button")
  val sh = lay(sh, Padding(), "4px 12px")
  val sh = line(sh, AllSides(), 1, 4)
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = lay(sh, FontSize(), "14px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = close(sh)
  val sh = rule(sh, ".hrow")
  val sh = line(sh, BottomSide(), 1, 4)
  val sh = lay(sh, Padding(), "8px 12px")
  val sh = close(sh)
  val sh = rule(sh, ".hgo")
  val sh = lay(sh, Display(), "block")
  val sh = lay(sh, Width(), "100%")
  val sh = lay(sh, TextAlign(), "left")
  val sh = lay(sh, Padding(), "4px 0")
  val sh = close(sh)
  val sh = rule(sh, ".hgo *")
  val sh = lay(sh, PointerEvents(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".pi.hgo")
  val sh = lay(sh, Padding(), "10px 14px")
  val sh = close(sh)
  val sh = rule(sh, ".pi.hgo .snip")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = lay(sh, FontSize(), "14px")
  val sh = lay(sh, MarginTop(), "0")
  val sh = lay(sh, LineHeight(), "1.45")
  val sh = close(sh)
  val sh = rule(sh, ".grp")
  val sh = lay(sh, FontWeight(), "bold")
  val sh = lay(sh, Padding(), "12px 12px 4px")
  val sh = surf(S_muted_card | sh, 2, 3)
  val sh = lay(sh, FontSize(), "13px")
  val sh = lay(sh, LetterSpacing(), ".04em")
  val sh = lay(sh, TextTransform(), "uppercase")
  val sh = close(sh)
  val sh = rule(sh, ".sheet")
  val sh = lay(sh, Position(), "fixed")
  val sh = lay(sh, Left(), "0")
  val sh = lay(sh, Right(), "0")
  val sh = lay(sh, Bottom(), "0")
  val sh = lay(sh, ZIndex(), "12")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = lay(sh, Padding(), "12px 16px max(16px,env(safe-area-inset-bottom))")
  val sh = lay(sh, BoxShadow(), "0 -2px 16px rgba(0,0,0,.3)")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, FlexDirection(), "column")
  val sh = lay(sh, Gap(), "10px")
  val sh = lay(sh, MaxWidth(), "520px")
  val sh = lay(sh, Margin(), "0 auto")
  val sh = lay(sh, BorderRadius(), "12px 12px 0 0")
  (* taller than a short screen allows: it scrolls *)
  val sh = lay(sh, MaxHeight(), "85vh")
  val sh = lay(sh, Overflow(), "auto")
  val sh = close(sh)
  (* its rows keep their height, and the sheet scrolls instead *)
  val sh = rule(sh, ".sheet>*")
  val sh = lay(sh, Flex(), "none")
  val sh = close(sh)
  val sh = rule(sh, ".srow")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Gap(), "10px")
  val sh = close(sh)
  val sh = rule(sh, ".slabel")
  val sh = lay(sh, Width(), "7em")
  val sh = surf(S_muted_card | sh, 2, 3)
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
  val sh = rule(sh, ".srow input[type=range]")
  val sh = lay(sh, Flex(), "1")
  val sh = accent(E_accent_card | sh, 8, 3)
  val sh = close(sh)
  val sh = rule(sh, ".sval")
  val sh = lay(sh, Width(), "3em")
  val sh = lay(sh, TextAlign(), "right")
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
  val sh = rule(sh, ".seg")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "6px")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, FlexWrap(), "wrap")
  val sh = close(sh)
  val sh = rule(sh, ".seg button")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, Padding(), "8px 6px")
  val sh = line(sh, AllSides(), 1, 4)
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = lay(sh, FontSize(), "14px")
  val sh = surf(S_fg_card | sh, 1, 3)
  val sh = close(sh)
  val sh = rule(sh, ".seg button[aria-pressed=true]")
  val sh = surf(S_accentfg_accent | sh, 9, 8)
  val sh = line(sh, AllSides(), 1, 8)
  val sh = close(sh)
  val sh = rule(sh, ".sfoot")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "8px")
  val sh = lay(sh, JustifyContent(), "space-between")
  val sh = lay(sh, AlignItems(), "center")
  val sh = close(sh)
  val sh = rule(sh, ".link")
  val sh = surf(S_accent_card | sh, 8, 3)
  val sh = lay(sh, TextDecoration(), "underline")
  val sh = lay(sh, Padding(), "6px 0")
  val sh = close(sh)
  val sh = rule(sh, ".sbar")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, Gap(), "6px")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, Padding(), "6px 8px")
  val sh = line(sh, BottomSide(), 1, 4)
  val sh = close(sh)
  val sh = rule(sh, ".sbar input")
  val sh = lay(sh, Flex(), "1")
  val sh = lay(sh, Padding(), "6px 10px")
  val sh = lay(sh, BorderRadius(), "6px")
  val sh = lay(sh, Font(), "inherit")
  val sh = close(sh)
  val sh = rule(sh, ".snav")
  val sh = lay(sh, Display(), "flex")
  val sh = lay(sh, AlignItems(), "center")
  val sh = lay(sh, JustifyContent(), "center")
  val sh = lay(sh, Gap(), "8px")
  val sh = lay(sh, Padding(), "6px")
  val sh = line(sh, TopSide(), 1, 4)
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
in sh end

fn _g_5_media {r:nat | r >= 284} (sh: sheet(r, 0)): [q:nat | q >= r - 284] sheet(q, 0) = let
  val sh = media(sh, "(max-width:480px)")
  val sh = rule(sh, ".lib")
  val sh = lay(sh, PaddingLeft(), "10px")
  val sh = lay(sh, PaddingRight(), "10px")
  val sh = close(sh)
  val sh = rule(sh, ".ttl")
  val sh = lay(sh, FontSize(), "20px")
  val sh = lay(sh, Flex(), "1 1 calc(100% - 60px)")
  val sh = close(sh)
  val sh = rule(sh, ".bar>.ibtn")
  val sh = lay(sh, Order(), "1")
  val sh = close(sh)
  val sh = rule(sh, ".bar>.btn")
  val sh = lay(sh, Order(), "2")
  val sh = lay(sh, Padding(), "8px 9px")
  val sh = lay(sh, FontSize(), "14px")
  val sh = close(sh)
  val sh = rule(sh, ".bar>.sfield")
  val sh = lay(sh, Order(), "3")
  val sh = close(sh)
  val sh = media_end(sh)
in sh end

fn _g_6_media {r:nat | r >= 57} (sh: sheet(r, 0)): [q:nat | q >= r - 57] sheet(q, 0) = let
  val sh = media(sh, "(max-width:600px)")
  val sh = rule(sh, ".caf p")
  val sh = lay(sh, TextAlign(), "start")
  val sh = close(sh)
  val sh = media_end(sh)
in sh end

(* The axes the page turn (gestures region 1, on .caf) owns: the
   stylesheet's touch-action for .caf comes from them, so the browser
   leaves exactly that axis to the recognizer *)
#pub fn page_turn_axes (): $GT.axes

implement page_turn_axes () = $GT.AxH()

#pub fn app_style (): [l:agz][k:nat | k < 65536] @($A.arr(byte, l, $B.BUILDER_CAP), int k)

implement app_style () = let
  val b = $B.create()
  val sh: sheet(BUDGET, 0) = Sheet(b)
  val sh = _g_0_fonts(sh)
  (* the light theme is also the root's, so the page behind the app has
     the palette too *)
  val sh = theme(PAL0_bg(), PAL0_fg(), PAL0_muted(), PAL0_card(), PAL0_line(), PAL0_edge(),
    PAL0_bar(), PAL0_barfg(), PAL0_accent(), PAL0_accentfg(), PAL0_hl(), PAL0_barhi(),
    PAL0_banner(), PAL0_bannerfg(), PAL0_mark(), PAL0_markfg(), PAL0_danger(), H_light |
    sh, ":root,.th-light", 0xfaf8f5, 0x2a2a2a, 0x6b6b6b, 0xffffff, 0xdddddd, 0x8a8a8a,
    0x333333, 0xffffff, 0x2f6f4f, 0xffffff, 0xfde59a, 0x4a4a4a, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xb3261e)
  val sh = theme(PAL1_bg(), PAL1_fg(), PAL1_muted(), PAL1_card(), PAL1_line(), PAL1_edge(),
    PAL1_bar(), PAL1_barfg(), PAL1_accent(), PAL1_accentfg(), PAL1_hl(), PAL1_barhi(),
    PAL1_banner(), PAL1_bannerfg(), PAL1_mark(), PAL1_markfg(), PAL1_danger(), H_sepia |
    sh, ".th-sepia", 0xf0e6d2, 0x3b2f22, 0x6e5e4a, 0xf7efdf, 0xd6c7a8, 0x8f7d62,
    0x4a3b2a, 0xf7efdf, 0x7a4f1d, 0xffffff, 0xe4c68e, 0x5e4c38, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0x9c2a1c)
  val sh = theme(PAL2_bg(), PAL2_fg(), PAL2_muted(), PAL2_card(), PAL2_line(), PAL2_edge(),
    PAL2_bar(), PAL2_barfg(), PAL2_accent(), PAL2_accentfg(), PAL2_hl(), PAL2_barhi(),
    PAL2_banner(), PAL2_bannerfg(), PAL2_mark(), PAL2_markfg(), PAL2_danger(), H_dark |
    sh, ".th-dark", 0x1e1e1e, 0xe2e2e2, 0xa0a0a0, 0x2a2a2a, 0x3d3d3d, 0x7a7a7a,
    0x111111, 0xe2e2e2, 0x7fc49b, 0x10231a, 0x6d5e2f, 0x2e2e2e, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xffb4ab)
  val sh = _base(sh)
  val sh = _g_1_shell(sh)
  val sh = _g_2_overlays(sh)
  val sh = _g_3_reader(sh)
  val sh = _g_4_panels(sh)
  val sh = _g_5_media(sh)
  val sh = _g_6_media(sh)
  val sh = rule(sh, ".caf")
  val sh = lay(sh, TouchAction(), $GT.touch_action(page_turn_axes(), false))
  val sh = close(sh)
  val+ ~Sheet(b) = sh
  val @(a, n) = $B.to_arr(b)
in @(a, n) end

end

