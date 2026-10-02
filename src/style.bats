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
stadef HL2 = 17
#pub stadef NROLE = 18

#pub typedef role(r:int) = int(r)
#pub typedef role = [r:nat | r < NROLE] int r

(* Themes: 0 light, 1 sepia, 2 dark, 3 night (warm, low in blue, for
   reading in the dark), 4 grey *)

(* PAL(t, r, c): in theme t, role r is the colour 0xc *)
dataprop PAL(int, int, int) =
  | PAL0_bg(0, BG, 0xfaf8f5) | PAL1_bg(1, BG, 0xf0e6d2) | PAL2_bg(2, BG, 0x1e1e1e) | PAL3_bg(3, BG, 0x1f1a14) | PAL4_bg(4, BG, 0x3a3a3a)
  | PAL0_fg(0, FG, 0x2a2a2a) | PAL1_fg(1, FG, 0x3b2f22) | PAL2_fg(2, FG, 0xe2e2e2) | PAL3_fg(3, FG, 0xc2b296) | PAL4_fg(4, FG, 0xe2e2e2)
  | PAL0_muted(0, MUTED, 0x6b6b6b) | PAL1_muted(1, MUTED, 0x6e5e4a) | PAL2_muted(2, MUTED, 0xa0a0a0) | PAL3_muted(3, MUTED, 0x9a8a70) | PAL4_muted(4, MUTED, 0xb8b8b8)
  | PAL0_card(0, CARD, 0xffffff) | PAL1_card(1, CARD, 0xf7efdf) | PAL2_card(2, CARD, 0x2a2a2a) | PAL3_card(3, CARD, 0x2a231b) | PAL4_card(4, CARD, 0x444444)
  | PAL0_line(0, LINE, 0xdddddd) | PAL1_line(1, LINE, 0xd6c7a8) | PAL2_line(2, LINE, 0x3d3d3d) | PAL3_line(3, LINE, 0x3d342a) | PAL4_line(4, LINE, 0x4f4f4f)
  | PAL0_edge(0, EDGE, 0x8a8a8a) | PAL1_edge(1, EDGE, 0x8f7d62) | PAL2_edge(2, EDGE, 0x7a7a7a) | PAL3_edge(3, EDGE, 0x857560) | PAL4_edge(4, EDGE, 0x999999)
  | PAL0_bar(0, BAR, 0x333333) | PAL1_bar(1, BAR, 0x4a3b2a) | PAL2_bar(2, BAR, 0x111111) | PAL3_bar(3, BAR, 0x15110c) | PAL4_bar(4, BAR, 0x2a2a2a)
  | PAL0_barfg(0, BARFG, 0xffffff) | PAL1_barfg(1, BARFG, 0xf7efdf) | PAL2_barfg(2, BARFG, 0xe2e2e2) | PAL3_barfg(3, BARFG, 0xc2b296) | PAL4_barfg(4, BARFG, 0xe2e2e2)
  | PAL0_accent(0, ACCENT, 0x2f6f4f) | PAL1_accent(1, ACCENT, 0x7a4f1d) | PAL2_accent(2, ACCENT, 0x7fc49b) | PAL3_accent(3, ACCENT, 0xc9a36b) | PAL4_accent(4, ACCENT, 0x8fd0a8)
  | PAL0_accentfg(0, ACCENTFG, 0xffffff) | PAL1_accentfg(1, ACCENTFG, 0xffffff) | PAL2_accentfg(2, ACCENTFG, 0x10231a) | PAL3_accentfg(3, ACCENTFG, 0x1f1a14) | PAL4_accentfg(4, ACCENTFG, 0x10231a)
  (* a highlight, opaque: the old translucent yellows over each page *)
  | PAL0_hl(0, HL, 0xfde59a) | PAL1_hl(1, HL, 0xe6cf8a) | PAL2_hl(2, HL, 0x6d5e2f) | PAL3_hl(3, HL, 0x4f4318) | PAL4_hl(4, HL, 0x6d5e2f)
  | PAL0_barhi(0, BARHI, 0x4a4a4a) | PAL1_barhi(1, BARHI, 0x5e4c38) | PAL2_barhi(2, BARHI, 0x2e2e2e) | PAL3_barhi(3, BARHI, 0x342b21) | PAL4_barhi(4, BARHI, 0x3d3d3d)
  | PAL0_banner(0, BANNER, 0xfbe3e1) | PAL1_banner(1, BANNER, 0xfbe3e1) | PAL2_banner(2, BANNER, 0xfbe3e1) | PAL3_banner(3, BANNER, 0xfbe3e1) | PAL4_banner(4, BANNER, 0xfbe3e1)
  | PAL0_bannerfg(0, BANNERFG, 0x6b1d16) | PAL1_bannerfg(1, BANNERFG, 0x6b1d16) | PAL2_bannerfg(2, BANNERFG, 0x6b1d16) | PAL3_bannerfg(3, BANNERFG, 0x6b1d16) | PAL4_bannerfg(4, BANNERFG, 0x6b1d16)
  | PAL0_mark(0, MARK, 0xffb300) | PAL1_mark(1, MARK, 0xffb300) | PAL2_mark(2, MARK, 0xffb300) | PAL3_mark(3, MARK, 0xffb300) | PAL4_mark(4, MARK, 0xffb300)
  | PAL0_markfg(0, MARKFG, 0x000000) | PAL1_markfg(1, MARKFG, 0x000000) | PAL2_markfg(2, MARKFG, 0x000000) | PAL3_markfg(3, MARKFG, 0x000000) | PAL4_markfg(4, MARKFG, 0x000000)
  | PAL0_danger(0, DANGER, 0xb3261e) | PAL1_danger(1, DANGER, 0x9c2a1c) | PAL2_danger(2, DANGER, 0xffb4ab) | PAL3_danger(3, DANGER, 0xe8a598) | PAL4_danger(4, DANGER, 0xffb4ab)
  (* a second highlight, orange: the yellows' family, apart in hue *)
  | PAL0_hl2(0, HL2, 0xfbc58a) | PAL1_hl2(1, HL2, 0xe8b880) | PAL2_hl2(2, HL2, 0x7b5831) | PAL3_hl2(3, HL2, 0x5c3f1f) | PAL4_hl2(4, HL2, 0x7b5831)

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
prval L_fbc58a = $CT.LUMc($CT.LIN_fb(), $CT.LIN_c5(), $CT.LIN_8a())
prval L_e8b880 = $CT.LUMc($CT.LIN_e8(), $CT.LIN_b8(), $CT.LIN_80())
prval L_7b5831 = $CT.LUMc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31())
prval L_5c3f1f = $CT.LUMc($CT.LIN_5c(), $CT.LIN_3f(), $CT.LIN_1f())
prval L_e6cf8a = $CT.LUMc($CT.LIN_e6(), $CT.LIN_cf(), $CT.LIN_8a())
prval L_4f4318 = $CT.LUMc($CT.LIN_4f(), $CT.LIN_43(), $CT.LIN_18())
prval L_1f1a14 = $CT.LUMc($CT.LIN_1f(), $CT.LIN_1a(), $CT.LIN_14())
prval L_c2b296 = $CT.LUMc($CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96())
prval L_9a8a70 = $CT.LUMc($CT.LIN_9a(), $CT.LIN_8a(), $CT.LIN_70())
prval L_2a231b = $CT.LUMc($CT.LIN_2a(), $CT.LIN_23(), $CT.LIN_1b())
prval L_3d342a = $CT.LUMc($CT.LIN_3d(), $CT.LIN_34(), $CT.LIN_2a())
prval L_857560 = $CT.LUMc($CT.LIN_85(), $CT.LIN_75(), $CT.LIN_60())
prval L_15110c = $CT.LUMc($CT.LIN_15(), $CT.LIN_11(), $CT.LIN_0c())
prval L_c9a36b = $CT.LUMc($CT.LIN_c9(), $CT.LIN_a3(), $CT.LIN_6b())
prval L_4d3c1c = $CT.LUMc($CT.LIN_4d(), $CT.LIN_3c(), $CT.LIN_1c())
prval L_342b21 = $CT.LUMc($CT.LIN_34(), $CT.LIN_2b(), $CT.LIN_21())
prval L_e8a598 = $CT.LUMc($CT.LIN_e8(), $CT.LIN_a5(), $CT.LIN_98())
prval L_3a3a3a = $CT.LUMc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a())
prval L_b8b8b8 = $CT.LUMc($CT.LIN_b8(), $CT.LIN_b8(), $CT.LIN_b8())
prval L_444444 = $CT.LUMc($CT.LIN_44(), $CT.LIN_44(), $CT.LIN_44())
prval L_4f4f4f = $CT.LUMc($CT.LIN_4f(), $CT.LIN_4f(), $CT.LIN_4f())
prval L_999999 = $CT.LUMc($CT.LIN_99(), $CT.LIN_99(), $CT.LIN_99())
prval L_8fd0a8 = $CT.LUMc($CT.LIN_8f(), $CT.LIN_d0(), $CT.LIN_a8())

(* SURF(text, ground): text in role text on role ground is at least
   4.5:1 in every theme, and does not vibrate on it (one of them is
   calm); EDGEP(edge, ground): a control's edge in role edge on ground
   is at least 3:1 *)
dataprop SURF(int, int) =
  | {text,ground:int}
    {text_light,ground_light,
     text_sepia,ground_sepia,
     text_dark,ground_dark,
     text_night,ground_night,
     text_grey,ground_grey:int}
    SURFc(text, ground) of (
       PAL(0, text, text_light), PAL(0, ground, ground_light),
       $CT.CONTRAST(text_light, ground_light, 45), $H.NOVIB(text_light, ground_light),
       PAL(1, text, text_sepia), PAL(1, ground, ground_sepia),
       $CT.CONTRAST(text_sepia, ground_sepia, 45), $H.NOVIB(text_sepia, ground_sepia),
       PAL(2, text, text_dark), PAL(2, ground, ground_dark),
       $CT.CONTRAST(text_dark, ground_dark, 45), $H.NOVIB(text_dark, ground_dark),
       PAL(3, text, text_night), PAL(3, ground, ground_night),
       $CT.CONTRAST(text_night, ground_night, 45), $H.NOVIB(text_night, ground_night),
       PAL(4, text, text_grey), PAL(4, ground, ground_grey),
       $CT.CONTRAST(text_grey, ground_grey, 45), $H.NOVIB(text_grey, ground_grey))

dataprop EDGEP(int, int) =
  | {edge,ground:int}
    {edge_light,ground_light,
     edge_sepia,ground_sepia,
     edge_dark,ground_dark,
     edge_night,ground_night,
     edge_grey,ground_grey:int}
    EDGEc(edge, ground) of (
       PAL(0, edge, edge_light), PAL(0, ground, ground_light),
       $CT.CONTRAST(edge_light, ground_light, 30),
       PAL(1, edge, edge_sepia), PAL(1, ground, ground_sepia),
       $CT.CONTRAST(edge_sepia, ground_sepia, 30),
       PAL(2, edge, edge_dark), PAL(2, ground, ground_dark),
       $CT.CONTRAST(edge_dark, ground_dark, 30),
       PAL(3, edge, edge_night), PAL(3, ground, ground_night),
       $CT.CONTRAST(edge_night, ground_night, 30),
       PAL(4, edge, edge_grey), PAL(4, ground, ground_grey),
       $CT.CONTRAST(edge_grey, ground_grey, 30))

(* Each theme's hue families (css's harmony.bats): at most three arcs,
   none wider than 30 degrees. The first is the tint of its neutrals.
   Light: warm paper, a green accent, red for danger. Sepia: warm, its
   accent brown in the same family, red. Dark and grey: grey neutrals,
   the warm highlight, a green accent, red. Night: as sepia, on a dark
   ground. *)
dataprop FAM(int, int, int, int, int, int, int) =
  | FAM_light(0, 25, 50, 135, 165, ~15, 15) of $H.FAMILIES(25, 50, 135, 165, ~15, 15)
  | FAM_sepia(1, 25, 50, 25, 50, ~15, 15) of $H.FAMILIES(25, 50, 25, 50, ~15, 15)
  | FAM_dark(2, 25, 50, 130, 160, ~15, 15) of $H.FAMILIES(25, 50, 130, 160, ~15, 15)
  | FAM_night(3, 25, 50, 25, 50, ~15, 15) of $H.FAMILIES(25, 50, 25, 50, ~15, 15)
  | FAM_grey(4, 25, 50, 130, 160, ~15, 15) of $H.FAMILIES(25, 50, 130, 160, ~15, 15)

(* A theme with dark text on a light ground asks nothing more; one with
   light text on a dark ground (Material's dark theme) has a ground that
   is not black, text that is not pure white, and an accent, a danger
   colour and control edges that are desaturated (calm) *)
dataprop MODE(int, int, int, int, int, int) =
  | {ground,text,bar_text,accent,danger,edge:int} MODE_light(ground, text, bar_text, accent, danger, edge) of $H.LIGHTER(ground, text)
  | {ground,text,bar_text,accent,danger,edge:int} MODE_dark(ground, text, bar_text, accent, danger, edge) of
      ($H.LIGHTER(text, ground), $H.PEAK(ground, 18, 255), $H.PEAK(text, 0, 232), $H.PEAK(bar_text, 0, 232),
       $H.CALM(accent), $H.CALM(danger), $H.CALM(edge))

(* HARMONY(t): theme t follows the harmony rules. A theme is written only
   with this proof (theme), over the colours it writes (PAL):
   * its hues are at most three families (FAM);
   * its surfaces, bars, edges and text are neutrals of its first
     family: grey, or tinted with its hue and chroma at most 48;
   * every other colour is grey or in one of its families;
   * danger, and the error banner, are red; the highlights (yellow and
     orange) and a search mark are yellow to orange (30 to 60 degrees);
   * the accent and the danger colour are as saturated, within 0.3;
   * a card is lighter than the page;
   * body text is at least 7:1 (WCAG AAA), as a reader's should be;
   * a dark theme follows MODE_dark. *)
dataprop HARMONY(int) =
  | {theme_number,first_low,first_high,second_low,second_high,third_low,third_high:int}
    {ground,text,muted,card,line,edge,bar,bar_text,accent,accent_text,
     highlight,bar_high,banner,banner_text,mark,mark_text,danger,second_highlight:int}
    HARMONYc(theme_number) of (
      PAL(theme_number, BG, ground), PAL(theme_number, FG, text), PAL(theme_number, MUTED, muted),
      PAL(theme_number, CARD, card), PAL(theme_number, LINE, line), PAL(theme_number, EDGE, edge),
      PAL(theme_number, BAR, bar), PAL(theme_number, BARFG, bar_text), PAL(theme_number, ACCENT, accent),
      PAL(theme_number, ACCENTFG, accent_text), PAL(theme_number, HL, highlight), PAL(theme_number, BARHI, bar_high),
      PAL(theme_number, BANNER, banner), PAL(theme_number, BANNERFG, banner_text), PAL(theme_number, MARK, mark),
      PAL(theme_number, MARKFG, mark_text), PAL(theme_number, DANGER, danger), PAL(theme_number, HL2, second_highlight),
      FAM(theme_number, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.NEUTRAL(ground, 48, first_low, first_high), $H.NEUTRAL(text, 48, first_low, first_high),
      $H.NEUTRAL(muted, 48, first_low, first_high), $H.NEUTRAL(card, 48, first_low, first_high),
      $H.NEUTRAL(line, 48, first_low, first_high), $H.NEUTRAL(edge, 48, first_low, first_high),
      $H.NEUTRAL(bar, 48, first_low, first_high), $H.NEUTRAL(bar_text, 48, first_low, first_high),
      $H.NEUTRAL(bar_high, 48, first_low, first_high),
      $H.IN3(accent, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(accent_text, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(highlight, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(banner, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(banner_text, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(mark, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(mark_text, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(danger, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.IN3(second_highlight, first_low, first_high, second_low, second_high, third_low, third_high),
      $H.HUE(danger, ~15, 15), $H.HUE(banner, ~15, 15), $H.HUE(banner_text, ~15, 15),
      $H.HUE(highlight, 30, 60), $H.HUE(mark, 30, 60), $H.HUE(second_highlight, 30, 60),
      $H.SATNEAR(accent, danger, 30),
      $H.LIGHTER(card, ground),
      $CT.CONTRAST(text, ground, 70),
      MODE(ground, text, bar_text, accent, danger, edge))

(* dark text on a light ground in the first two themes, light on dark
   in the others *)

(* BEGIN proofs: written by scripts/gen-harmony.py *)
prval S_fg_bg = SURFc(
  PAL0_fg(), PAL0_bg(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_faf8f5),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_bg(), $CT.CONTRAST_lighter_second(L_3b2f22, L_f0e6d2),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_bg(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_1e1e1e),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  PAL3_fg(), PAL3_bg(), $CT.CONTRAST_lighter_first(L_c2b296, L_1f1a14),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}()))),
  PAL4_fg(), PAL4_bg(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_3a3a3a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_fg_card = SURFc(
  PAL0_fg(), PAL0_card(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_ffffff),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_card(), $CT.CONTRAST_lighter_second(L_3b2f22, L_f7efdf),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_card(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  PAL3_fg(), PAL3_card(), $CT.CONTRAST_lighter_first(L_c2b296, L_2a231b),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}()))),
  PAL4_fg(), PAL4_card(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_444444),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_fg_line = SURFc(
  PAL0_fg(), PAL0_line(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_dddddd),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_line(), $CT.CONTRAST_lighter_second(L_3b2f22, L_d6c7a8),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_line(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_3d3d3d),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  PAL3_fg(), PAL3_line(), $CT.CONTRAST_lighter_first(L_c2b296, L_3d342a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}()))),
  PAL4_fg(), PAL4_line(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_4f4f4f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_fg_hl = SURFc(
  PAL0_fg(), PAL0_hl(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_fde59a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_hl(), $CT.CONTRAST_lighter_second(L_3b2f22, L_e6cf8a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_hl(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_6d5e2f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  PAL3_fg(), PAL3_hl(), $CT.CONTRAST_lighter_first(L_c2b296, L_4f4318),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}()))),
  PAL4_fg(), PAL4_hl(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_6d5e2f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_fg_hl2 = SURFc(
  PAL0_fg(), PAL0_hl2(), $CT.CONTRAST_lighter_second(L_2a2a2a, L_fbc58a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  PAL1_fg(), PAL1_hl2(), $CT.CONTRAST_lighter_second(L_3b2f22, L_e8b880),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x3b,0x2f,0x22}()))),
  PAL2_fg(), PAL2_hl2(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_7b5831),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  PAL3_fg(), PAL3_hl2(), $CT.CONTRAST_lighter_first(L_c2b296, L_5c3f1f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}()))),
  PAL4_fg(), PAL4_hl2(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_7b5831),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_muted_bg = SURFc(
  PAL0_muted(), PAL0_bg(), $CT.CONTRAST_lighter_second(L_6b6b6b, L_faf8f5),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6b,0x6b,0x6b}()))),
  PAL1_muted(), PAL1_bg(), $CT.CONTRAST_lighter_second(L_6e5e4a, L_f0e6d2),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6e,0x5e,0x4a}()))),
  PAL2_muted(), PAL2_bg(), $CT.CONTRAST_lighter_first(L_a0a0a0, L_1e1e1e),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xa0,0xa0,0xa0}()))),
  PAL3_muted(), PAL3_bg(), $CT.CONTRAST_lighter_first(L_9a8a70, L_1f1a14),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x9a,0x8a,0x70}()))),
  PAL4_muted(), PAL4_bg(), $CT.CONTRAST_lighter_first(L_b8b8b8, L_3a3a3a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xb8,0xb8,0xb8}()))))
prval S_muted_card = SURFc(
  PAL0_muted(), PAL0_card(), $CT.CONTRAST_lighter_second(L_6b6b6b, L_ffffff),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6b,0x6b,0x6b}()))),
  PAL1_muted(), PAL1_card(), $CT.CONTRAST_lighter_second(L_6e5e4a, L_f7efdf),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x6e,0x5e,0x4a}()))),
  PAL2_muted(), PAL2_card(), $CT.CONTRAST_lighter_first(L_a0a0a0, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xa0,0xa0,0xa0}()))),
  PAL3_muted(), PAL3_card(), $CT.CONTRAST_lighter_first(L_9a8a70, L_2a231b),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x9a,0x8a,0x70}()))),
  PAL4_muted(), PAL4_card(), $CT.CONTRAST_lighter_first(L_b8b8b8, L_444444),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xb8,0xb8,0xb8}()))))
prval S_accent_bg = SURFc(
  PAL0_accent(), PAL0_bg(), $CT.CONTRAST_lighter_second(L_2f6f4f, L_faf8f5),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfa,0xf8,0xf5}()))),
  PAL1_accent(), PAL1_bg(), $CT.CONTRAST_lighter_second(L_7a4f1d, L_f0e6d2),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xf0,0xe6,0xd2}()))),
  PAL2_accent(), PAL2_bg(), $CT.CONTRAST_lighter_first(L_7fc49b, L_1e1e1e),
    $H.NOVIB_text($H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()))),
  PAL3_accent(), PAL3_bg(), $CT.CONTRAST_lighter_first(L_c9a36b, L_1f1a14),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc9,0xa3,0x6b}()))),
  PAL4_accent(), PAL4_bg(), $CT.CONTRAST_lighter_first(L_8fd0a8, L_3a3a3a),
    $H.NOVIB_text($H.CALMc($H.MXMN_gbr($H.RGBc{0x8f,0xd0,0xa8}()))))
prval S_accent_card = SURFc(
  PAL0_accent(), PAL0_card(), $CT.CONTRAST_lighter_second(L_2f6f4f, L_ffffff),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_accent(), PAL1_card(), $CT.CONTRAST_lighter_second(L_7a4f1d, L_f7efdf),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_accent(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7fc49b, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()))),
  PAL3_accent(), PAL3_card(), $CT.CONTRAST_lighter_first(L_c9a36b, L_2a231b),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc9,0xa3,0x6b}()))),
  PAL4_accent(), PAL4_card(), $CT.CONTRAST_lighter_first(L_8fd0a8, L_444444),
    $H.NOVIB_text($H.CALMc($H.MXMN_gbr($H.RGBc{0x8f,0xd0,0xa8}()))))
prval S_accentfg_accent = SURFc(
  PAL0_accentfg(), PAL0_accent(), $CT.CONTRAST_lighter_first(L_ffffff, L_2f6f4f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_accentfg(), PAL1_accent(), $CT.CONTRAST_lighter_first(L_ffffff, L_7a4f1d),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL2_accentfg(), PAL2_accent(), $CT.CONTRAST_lighter_second(L_10231a, L_7fc49b),
    $H.NOVIB_ground($H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()))),
  PAL3_accentfg(), PAL3_accent(), $CT.CONTRAST_lighter_second(L_1f1a14, L_c9a36b),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x1f,0x1a,0x14}()))),
  PAL4_accentfg(), PAL4_accent(), $CT.CONTRAST_lighter_second(L_10231a, L_8fd0a8),
    $H.NOVIB_ground($H.CALMc($H.MXMN_gbr($H.RGBc{0x8f,0xd0,0xa8}()))))
prval S_barfg_bar = SURFc(
  PAL0_barfg(), PAL0_bar(), $CT.CONTRAST_lighter_first(L_ffffff, L_333333),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_barfg(), PAL1_bar(), $CT.CONTRAST_lighter_first(L_f7efdf, L_4a3b2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_barfg(), PAL2_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_111111),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  PAL3_barfg(), PAL3_bar(), $CT.CONTRAST_lighter_first(L_c2b296, L_15110c),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}()))),
  PAL4_barfg(), PAL4_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_barfg_barhi = SURFc(
  PAL0_barfg(), PAL0_barhi(), $CT.CONTRAST_lighter_first(L_ffffff, L_4a4a4a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_barfg(), PAL1_barhi(), $CT.CONTRAST_lighter_first(L_f7efdf, L_5e4c38),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_barfg(), PAL2_barhi(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_2e2e2e),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  PAL3_barfg(), PAL3_barhi(), $CT.CONTRAST_lighter_first(L_c2b296, L_342b21),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}()))),
  PAL4_barfg(), PAL4_barhi(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_3d3d3d),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))))
prval S_bannerfg_banner = SURFc(
  PAL0_bannerfg(), PAL0_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))),
  PAL1_bannerfg(), PAL1_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))),
  PAL2_bannerfg(), PAL2_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))),
  PAL3_bannerfg(), PAL3_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))),
  PAL4_bannerfg(), PAL4_banner(), $CT.CONTRAST_lighter_second(L_6b1d16, L_fbe3e1),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xfb,0xe3,0xe1}()))))
prval S_markfg_mark = SURFc(
  PAL0_markfg(), PAL0_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  PAL1_markfg(), PAL1_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  PAL2_markfg(), PAL2_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  PAL3_markfg(), PAL3_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  PAL4_markfg(), PAL4_mark(), $CT.CONTRAST_lighter_second(L_000000, L_ffb300),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))))
prval S_danger_card = SURFc(
  PAL0_danger(), PAL0_card(), $CT.CONTRAST_lighter_second(L_b3261e, L_ffffff),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xff,0xff}()))),
  PAL1_danger(), PAL1_card(), $CT.CONTRAST_lighter_second(L_9c2a1c, L_f7efdf),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xf7,0xef,0xdf}()))),
  PAL2_danger(), PAL2_card(), $CT.CONTRAST_lighter_first(L_ffb4ab, L_2a2a2a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}()))),
  PAL3_danger(), PAL3_card(), $CT.CONTRAST_lighter_first(L_e8a598, L_2a231b),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe8,0xa5,0x98}()))),
  PAL4_danger(), PAL4_card(), $CT.CONTRAST_lighter_first(L_ffb4ab, L_444444),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}()))))
prval S_danger_line = SURFc(
  PAL0_danger(), PAL0_line(), $CT.CONTRAST_lighter_second(L_b3261e, L_dddddd),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xdd,0xdd,0xdd}()))),
  PAL1_danger(), PAL1_line(), $CT.CONTRAST_lighter_second(L_9c2a1c, L_d6c7a8),
    $H.NOVIB_ground($H.CALMc($H.MXMN_rgb($H.RGBc{0xd6,0xc7,0xa8}()))),
  PAL2_danger(), PAL2_line(), $CT.CONTRAST_lighter_first(L_ffb4ab, L_3d3d3d),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}()))),
  PAL3_danger(), PAL3_line(), $CT.CONTRAST_lighter_first(L_e8a598, L_3d342a),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xe8,0xa5,0x98}()))),
  PAL4_danger(), PAL4_line(), $CT.CONTRAST_lighter_first(L_ffb4ab, L_4f4f4f),
    $H.NOVIB_text($H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}()))))
prval E_edge_card = EDGEc(
  PAL0_edge(), PAL0_card(), $CT.CONTRAST_lighter_second(L_8a8a8a, L_ffffff),
  PAL1_edge(), PAL1_card(), $CT.CONTRAST_lighter_second(L_8f7d62, L_f7efdf),
  PAL2_edge(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7a7a7a, L_2a2a2a),
  PAL3_edge(), PAL3_card(), $CT.CONTRAST_lighter_first(L_857560, L_2a231b),
  PAL4_edge(), PAL4_card(), $CT.CONTRAST_lighter_first(L_999999, L_444444))
prval E_accent_card = EDGEc(
  PAL0_accent(), PAL0_card(), $CT.CONTRAST_lighter_second(L_2f6f4f, L_ffffff),
  PAL1_accent(), PAL1_card(), $CT.CONTRAST_lighter_second(L_7a4f1d, L_f7efdf),
  PAL2_accent(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7fc49b, L_2a2a2a),
  PAL3_accent(), PAL3_card(), $CT.CONTRAST_lighter_first(L_c9a36b, L_2a231b),
  PAL4_accent(), PAL4_card(), $CT.CONTRAST_lighter_first(L_8fd0a8, L_444444))
prval E_barfg_bar = EDGEc(
  PAL0_barfg(), PAL0_bar(), $CT.CONTRAST_lighter_first(L_ffffff, L_333333),
  PAL1_barfg(), PAL1_bar(), $CT.CONTRAST_lighter_first(L_f7efdf, L_4a3b2a),
  PAL2_barfg(), PAL2_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_111111),
  PAL3_barfg(), PAL3_bar(), $CT.CONTRAST_lighter_first(L_c2b296, L_15110c),
  PAL4_barfg(), PAL4_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_2a2a2a))
prval H_light: HARMONY(0) = HARMONYc(
  PAL0_bg(), PAL0_fg(), PAL0_muted(), PAL0_card(), PAL0_line(), PAL0_edge(), PAL0_bar(), PAL0_barfg(), PAL0_accent(), PAL0_accentfg(), PAL0_hl(), PAL0_barhi(), PAL0_banner(), PAL0_bannerfg(), PAL0_mark(), PAL0_markfg(), PAL0_danger(), PAL0_hl2(),
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
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xfbc58a,0xfb,0xc5,0x8a,25,50}($H.RGBc{0xfb,0xc5,0x8a}())),
  $H.HUE_r_g_b{0xb3261e,0xb3,0x26,0x1e,~15,15}($H.RGBc{0xb3,0x26,0x1e}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0xfde59a,0xfd,0xe5,0x9a,30,60}($H.RGBc{0xfd,0xe5,0x9a}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.HUE_r_g_b{0xfbc58a,0xfb,0xc5,0x8a,30,60}($H.RGBc{0xfb,0xc5,0x8a}()),
  $H.SATNEARc($H.MXMN_gbr($H.RGBc{0x2f,0x6f,0x4f}()), $H.MXMN_rgb($H.RGBc{0xb3,0x26,0x1e}())),
  $H.LIGHTERc(L_ffffff, L_faf8f5),
  $CT.CONTRAST_lighter_second(L_2a2a2a, L_faf8f5),
  MODE_light($H.LIGHTERc(L_faf8f5, L_2a2a2a)))
prval H_sepia: HARMONY(1) = HARMONYc(
  PAL1_bg(), PAL1_fg(), PAL1_muted(), PAL1_card(), PAL1_line(), PAL1_edge(), PAL1_bar(), PAL1_barfg(), PAL1_accent(), PAL1_accentfg(), PAL1_hl(), PAL1_barhi(), PAL1_banner(), PAL1_bannerfg(), PAL1_mark(), PAL1_markfg(), PAL1_danger(), PAL1_hl2(),
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
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xe6cf8a,0xe6,0xcf,0x8a,25,50}($H.RGBc{0xe6,0xcf,0x8a}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,25,50}($H.RGBc{0xff,0xb3,0x00}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x9c2a1c,0x9c,0x2a,0x1c,~15,15}($H.RGBc{0x9c,0x2a,0x1c}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xe8b880,0xe8,0xb8,0x80,25,50}($H.RGBc{0xe8,0xb8,0x80}())),
  $H.HUE_r_g_b{0x9c2a1c,0x9c,0x2a,0x1c,~15,15}($H.RGBc{0x9c,0x2a,0x1c}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0xe6cf8a,0xe6,0xcf,0x8a,30,60}($H.RGBc{0xe6,0xcf,0x8a}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.HUE_r_g_b{0xe8b880,0xe8,0xb8,0x80,30,60}($H.RGBc{0xe8,0xb8,0x80}()),
  $H.SATNEARc($H.MXMN_rgb($H.RGBc{0x7a,0x4f,0x1d}()), $H.MXMN_rgb($H.RGBc{0x9c,0x2a,0x1c}())),
  $H.LIGHTERc(L_f7efdf, L_f0e6d2),
  $CT.CONTRAST_lighter_second(L_3b2f22, L_f0e6d2),
  MODE_light($H.LIGHTERc(L_f0e6d2, L_3b2f22)))
prval H_dark: HARMONY(2) = HARMONYc(
  PAL2_bg(), PAL2_fg(), PAL2_muted(), PAL2_card(), PAL2_line(), PAL2_edge(), PAL2_bar(), PAL2_barfg(), PAL2_accent(), PAL2_accentfg(), PAL2_hl(), PAL2_barhi(), PAL2_banner(), PAL2_bannerfg(), PAL2_mark(), PAL2_markfg(), PAL2_danger(), PAL2_hl2(),
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
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x7b5831,0x7b,0x58,0x31,25,50}($H.RGBc{0x7b,0x58,0x31}())),
  $H.HUE_r_g_b{0xffb4ab,0xff,0xb4,0xab,~15,15}($H.RGBc{0xff,0xb4,0xab}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0x6d5e2f,0x6d,0x5e,0x2f,30,60}($H.RGBc{0x6d,0x5e,0x2f}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.HUE_r_g_b{0x7b5831,0x7b,0x58,0x31,30,60}($H.RGBc{0x7b,0x58,0x31}()),
  $H.SATNEARc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}()), $H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}())),
  $H.LIGHTERc(L_2a2a2a, L_1e1e1e),
  $CT.CONTRAST_lighter_first(L_e2e2e2, L_1e1e1e),
  MODE_dark($H.LIGHTERc(L_e2e2e2, L_1e1e1e), $H.PEAKc($H.MXMN_rgb($H.RGBc{0x1e,0x1e,0x1e}())),
    $H.PEAKc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}())), $H.PEAKc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}())),
    $H.CALMc($H.MXMN_gbr($H.RGBc{0x7f,0xc4,0x9b}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0x7a,0x7a,0x7a}()))))
prval H_night: HARMONY(3) = HARMONYc(
  PAL3_bg(), PAL3_fg(), PAL3_muted(), PAL3_card(), PAL3_line(), PAL3_edge(), PAL3_bar(), PAL3_barfg(), PAL3_accent(), PAL3_accentfg(), PAL3_hl(), PAL3_barhi(), PAL3_banner(), PAL3_bannerfg(), PAL3_mark(), PAL3_markfg(), PAL3_danger(), PAL3_hl2(),
  FAM_night($H.FAMILIESc()),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x1f,0x1a,0x14}())), $H.HUE_r_g_b{0x1f1a14,0x1f,0x1a,0x14,25,50}($H.RGBc{0x1f,0x1a,0x14}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}())), $H.HUE_r_g_b{0xc2b296,0xc2,0xb2,0x96,25,50}($H.RGBc{0xc2,0xb2,0x96}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x9a,0x8a,0x70}())), $H.HUE_r_g_b{0x9a8a70,0x9a,0x8a,0x70,25,50}($H.RGBc{0x9a,0x8a,0x70}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x2a,0x23,0x1b}())), $H.HUE_r_g_b{0x2a231b,0x2a,0x23,0x1b,25,50}($H.RGBc{0x2a,0x23,0x1b}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x3d,0x34,0x2a}())), $H.HUE_r_g_b{0x3d342a,0x3d,0x34,0x2a,25,50}($H.RGBc{0x3d,0x34,0x2a}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x85,0x75,0x60}())), $H.HUE_r_g_b{0x857560,0x85,0x75,0x60,25,50}($H.RGBc{0x85,0x75,0x60}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x15,0x11,0x0c}())), $H.HUE_r_g_b{0x15110c,0x15,0x11,0x0c,25,50}($H.RGBc{0x15,0x11,0x0c}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}())), $H.HUE_r_g_b{0xc2b296,0xc2,0xb2,0x96,25,50}($H.RGBc{0xc2,0xb2,0x96}())),
  $H.NEUTRAL_tint($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x34,0x2b,0x21}())), $H.HUE_r_g_b{0x342b21,0x34,0x2b,0x21,25,50}($H.RGBc{0x34,0x2b,0x21}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xc9a36b,0xc9,0xa3,0x6b,25,50}($H.RGBc{0xc9,0xa3,0x6b}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x1f1a14,0x1f,0x1a,0x14,25,50}($H.RGBc{0x1f,0x1a,0x14}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x4f4318,0x4f,0x43,0x18,25,50}($H.RGBc{0x4f,0x43,0x18}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,25,50}($H.RGBc{0xff,0xb3,0x00}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xe8a598,0xe8,0xa5,0x98,~15,15}($H.RGBc{0xe8,0xa5,0x98}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x5c3f1f,0x5c,0x3f,0x1f,25,50}($H.RGBc{0x5c,0x3f,0x1f}())),
  $H.HUE_r_g_b{0xe8a598,0xe8,0xa5,0x98,~15,15}($H.RGBc{0xe8,0xa5,0x98}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0x4f4318,0x4f,0x43,0x18,30,60}($H.RGBc{0x4f,0x43,0x18}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.HUE_r_g_b{0x5c3f1f,0x5c,0x3f,0x1f,30,60}($H.RGBc{0x5c,0x3f,0x1f}()),
  $H.SATNEARc($H.MXMN_rgb($H.RGBc{0xc9,0xa3,0x6b}()), $H.MXMN_rgb($H.RGBc{0xe8,0xa5,0x98}())),
  $H.LIGHTERc(L_2a231b, L_1f1a14),
  $CT.CONTRAST_lighter_first(L_c2b296, L_1f1a14),
  MODE_dark($H.LIGHTERc(L_c2b296, L_1f1a14), $H.PEAKc($H.MXMN_rgb($H.RGBc{0x1f,0x1a,0x14}())),
    $H.PEAKc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}())), $H.PEAKc($H.MXMN_rgb($H.RGBc{0xc2,0xb2,0x96}())),
    $H.CALMc($H.MXMN_rgb($H.RGBc{0xc9,0xa3,0x6b}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0xe8,0xa5,0x98}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0x85,0x75,0x60}()))))
prval H_grey: HARMONY(4) = HARMONYc(
  PAL4_bg(), PAL4_fg(), PAL4_muted(), PAL4_card(), PAL4_line(), PAL4_edge(), PAL4_bar(), PAL4_barfg(), PAL4_accent(), PAL4_accentfg(), PAL4_hl(), PAL4_barhi(), PAL4_banner(), PAL4_bannerfg(), PAL4_mark(), PAL4_markfg(), PAL4_danger(), PAL4_hl2(),
  FAM_grey($H.FAMILIESc()),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x3a,0x3a,0x3a}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xb8,0xb8,0xb8}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x44,0x44,0x44}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x4f,0x4f,0x4f}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x99,0x99,0x99}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x2a,0x2a,0x2a}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}()))),
  $H.NEUTRAL_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x3d,0x3d,0x3d}()))),
  $H.IN3_2($H.FAMILIESc(), $H.HUE_g_b_r{0x8fd0a8,0x8f,0xd0,0xa8,130,160}($H.RGBc{0x8f,0xd0,0xa8}())),
  $H.IN3_2($H.FAMILIESc(), $H.HUE_g_b_r{0x10231a,0x10,0x23,0x1a,130,160}($H.RGBc{0x10,0x23,0x1a}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x6d5e2f,0x6d,0x5e,0x2f,25,50}($H.RGBc{0x6d,0x5e,0x2f}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}())),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,25,50}($H.RGBc{0xff,0xb3,0x00}())),
  $H.IN3_grey($H.CHROMAc($H.MXMN_rgb($H.RGBc{0x00,0x00,0x00}()))),
  $H.IN3_3($H.FAMILIESc(), $H.HUE_r_g_b{0xffb4ab,0xff,0xb4,0xab,~15,15}($H.RGBc{0xff,0xb4,0xab}())),
  $H.IN3_1($H.FAMILIESc(), $H.HUE_r_g_b{0x7b5831,0x7b,0x58,0x31,25,50}($H.RGBc{0x7b,0x58,0x31}())),
  $H.HUE_r_g_b{0xffb4ab,0xff,0xb4,0xab,~15,15}($H.RGBc{0xff,0xb4,0xab}()),
  $H.HUE_r_g_b{0xfbe3e1,0xfb,0xe3,0xe1,~15,15}($H.RGBc{0xfb,0xe3,0xe1}()),
  $H.HUE_r_g_b{0x6b1d16,0x6b,0x1d,0x16,~15,15}($H.RGBc{0x6b,0x1d,0x16}()),
  $H.HUE_r_g_b{0x6d5e2f,0x6d,0x5e,0x2f,30,60}($H.RGBc{0x6d,0x5e,0x2f}()),
  $H.HUE_r_g_b{0xffb300,0xff,0xb3,0x00,30,60}($H.RGBc{0xff,0xb3,0x00}()),
  $H.HUE_r_g_b{0x7b5831,0x7b,0x58,0x31,30,60}($H.RGBc{0x7b,0x58,0x31}()),
  $H.SATNEARc($H.MXMN_gbr($H.RGBc{0x8f,0xd0,0xa8}()), $H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}())),
  $H.LIGHTERc(L_444444, L_3a3a3a),
  $CT.CONTRAST_lighter_first(L_e2e2e2, L_3a3a3a),
  MODE_dark($H.LIGHTERc(L_e2e2e2, L_3a3a3a), $H.PEAKc($H.MXMN_rgb($H.RGBc{0x3a,0x3a,0x3a}())),
    $H.PEAKc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}())), $H.PEAKc($H.MXMN_rgb($H.RGBc{0xe2,0xe2,0xe2}())),
    $H.CALMc($H.MXMN_gbr($H.RGBc{0x8f,0xd0,0xa8}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0xff,0xb4,0xab}())), $H.CALMc($H.MXMN_rgb($H.RGBc{0x99,0x99,0x99}()))))
(* END proofs *)

(* ============================================================
   The sheet: a builder with a budget of bytes left, so the whole
   sheet is proven to fit the style element (under 65536 bytes); and
   whether a rule or an @media block is open
   ============================================================ *)

stadef BUDGET = 60000

(* state: 0 top level, 1 in a rule, 2 in @media, 3 in a rule in @media *)
datavtype sheet(int, int) =
  | {written,left:nat | written + left <= BUDGET}{state:nat | state < 4} Sheet(left, state) of ($B.builder(written))

(* Bytes a selector or layout value may not hold: none of them can end
   a declaration or a rule, or make one !important *)
fn _is_plain {byte_value:nat | byte_value < 256} (byte_value: int byte_value): bool =
  byte_value <> 59 && byte_value <> 123 && byte_value <> 125 && byte_value <> 33

fun _put_plain {length:nat}{i:nat | i <= length}{written:nat | written + length - i <= BUDGET} .<length - i>.
  (builder: !$B.builder(written) >> [written_after:nat | written <= written_after; written_after <= written + length - i] $B.builder(written_after),
   text: string length, text_len: int length, i: int i): void =
  if i >= text_len then ()
  else let
    val code = char2int1(string_get_at(text, i))
    val byte_value = (if code >= 0 then (if code < 256 then code else 32) else 32): [byte_value:nat | byte_value < 256] int byte_value
  in
    if _is_plain(byte_value) then let val () = $B.put_char(builder, byte_value) in _put_plain(builder, text, text_len, i + 1) end
    else _put_plain(builder, text, text_len, i + 1)
  end

(* text, with any of ; { } ! dropped *)
fn plain {left:nat}{state:nat}{length:nat | length <= left}
  (sheet: !sheet(left, state) >> sheet(left - length, state), text: string length): void = let
  val+ @Sheet(builder) = sheet
  val () = _put_plain(builder, text, g1u2i(string1_length(text)), 0)
  prval () = fold@(sheet)
in end

(* text as written: only this module's fixed text *)
fn raw {left:nat}{state:nat}{length:nat | length <= left}
  (sheet: !sheet(left, state) >> sheet(left - length, state), text: string length): void = let
  val+ @Sheet(builder) = sheet
  val () = $B.bput(builder, text)
  prval () = fold@(sheet)
in end

fn _colour {left:nat | left >= 7}{state:nat}{colour:nat | colour < 16777216}
  (sheet: !sheet(left, state) >> sheet(left - 7, state), colour: int colour): void = let
  val+ @Sheet(builder) = sheet
  val () = $CT.put_rgb(builder, colour)
  prval () = fold@(sheet)
in end

(* a small number (at most 11 bytes) *)
fn _number {left:nat | left >= 11}{state:nat}
  (sheet: sheet(left, state), value: int): sheet(left - 11, state) = let
  val+ ~Sheet(builder) = sheet
  val () = $B.put_int(builder, value)
in Sheet(builder) end

fn _role_name {role:nat | role < NROLE} (role: int role): [length:pos | length <= 9] string length =
  case+ role of
  | 0 => "bg" | 1 => "fg" | 2 => "muted" | 3 => "card" | 4 => "line"
  | 5 => "edge" | 6 => "bar" | 7 => "barfg" | 8 => "accent" | 9 => "accentfg"
  | 10 => "hl" | 11 => "barhi" | 12 => "banner" | 13 => "bannerfg"
  | 14 => "mark" | 15 => "markfg" | 16 => "danger" | _ => "hl2"

(* var(--<role>) *)
fn _role_variable {left:nat | left >= 16}{state:nat}{role:nat | role < NROLE}
  (sheet: !sheet(left, state) >> [after:nat | after >= left - 16] sheet(after, state), role: int role): void = let
  val () = raw(sheet, "var(--")
  val () = raw(sheet, _role_name(role))
in raw(sheet, ")") end

(* ============================================================
   Rules
   ============================================================ *)


(* selector { *)
fn rule {left:nat}{state:nat | state == 0 || state == 2}{length:nat | length + 1 <= left}
  (sheet: sheet(left, state), selector: string length): sheet(left - length - 1, state + 1) = let
  val () = plain(sheet, selector)
  val () = raw(sheet, "{")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

(* } *)
fn close {left:pos}{state:nat | state == 1 || state == 3}
  (sheet: sheet(left, state)): sheet(left - 1, state - 1) = let
  val () = raw(sheet, "}")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

(* @media condition { *)
fn media {left:nat}{length:nat | length + 8 <= left}
  (sheet: sheet(left, 0), condition: string length): sheet(left - length - 8, 2) = let
  val () = raw(sheet, "@media ")
  val () = plain(sheet, condition)
  val () = raw(sheet, "{")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

fn media_end {left:pos} (sheet: sheet(left, 2)): sheet(left - 1, 0) = let
  val () = raw(sheet, "}")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

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
  | ColumnFill | ColumnGap | ColumnWidth | BreakAfter | BreakInside | GridTemplate | AspectRatio
  | Appearance

fn _property_name (property: prop): [length:pos | length <= 16] string length =
  case+ property of
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
  | GridTemplate() => "grid-template" | AspectRatio() => "aspect-ratio"

(* prop:value; *)
fn lay {left:nat}{state:nat | state == 1 || state == 3}{value_len:nat | value_len + 18 <= left}
  (sheet: sheet(left, state), property: prop, value: string value_len): [after:nat | after >= left - value_len - 18] sheet(after, state) = let
  val () = raw(sheet, _property_name(property))
  val () = raw(sheet, ":")
  val () = plain(sheet, value)
  val () = raw(sheet, ";")
in sheet end

(* color:var(--text);background-color:var(--ground); : text on ground,
   proven *)
fn surf {left:nat | left >= 60}{state:nat | state == 1 || state == 3}{text,ground:nat | text < NROLE; ground < NROLE}
  (legible: SURF(text, ground) | sheet: sheet(left, state), text: int text, ground: int ground): [after:nat | after >= left - 60] sheet(after, state) = let
  val () = raw(sheet, "color:")
  val () = _role_variable(sheet, text)
  val () = raw(sheet, ";background-color:")
  val () = _role_variable(sheet, ground)
  val () = raw(sheet, ";")
in sheet end

(* A ground with no text: a bar, a track, a placeholder *)
fn fill {left:nat | left >= 50}{state:nat | state == 1 || state == 3}{ground:nat | ground < NROLE}
  (sheet: sheet(left, state), ground: int ground): [after:nat | after >= left - 50] sheet(after, state) = let
  val () = raw(sheet, "background-color:")
  val () = _role_variable(sheet, ground)
  val () = raw(sheet, ";font-size:0;")
in sheet end

(* A ground of white or black at alpha percent, with no text *)
fn tint {left:nat | left >= 60}{state:nat | state == 1 || state == 3}{alpha:nat | alpha <= 100}
  (sheet: sheet(left, state), white: bool, alpha: int alpha): [after:nat | after >= left - 60] sheet(after, state) = let
  val () = raw(sheet, (if white then "background-color:rgba(255,255,255," else "background-color:rgba(0,0,0,"): [length:pos | length <= 34] string length)
  val sheet = _number(sheet, alpha)
  val () = raw(sheet, "%);font-size:0;")
in sheet end

(* The veil behind a menu or dialog: dark, and its own text (none)
   transparent, so only what sits on it in a proven surface shows *)
fn veil {left:nat | left >= 60}{state:nat | state == 1 || state == 3}
  (sheet: sheet(left, state)): [after:nat | after >= left - 60] sheet(after, state) =
  let val () = raw(sheet, "background-color:rgba(0,0,0,.5);color:transparent;") in sheet end

(* A decorative line in a role (a card's outline, a separator): not
   what identifies a control, which the base rules give text fields *)
#pub datatype side = AllSides | TopSide | BottomSide | LeftSide

fn line {left:nat | left >= 60}{state:nat | state == 1 || state == 3}{width:pos | width <= 9}{role:nat | role < NROLE}
  (sheet: sheet(left, state), side: side, width: int width, role: int role): [after:nat | after >= left - 60] sheet(after, state) = let
  val () = raw(sheet, (case+ side of AllSides() => "border:" | TopSide() => "border-top:"
    | BottomSide() => "border-bottom:" | LeftSide() => "border-left:"): [length:pos | length <= 14] string length)
  val sheet = _number(sheet, width)
  val () = raw(sheet, "px solid ")
  val () = _role_variable(sheet, role)
  val () = raw(sheet, ";")
in sheet end

fn no_line {left:nat | left >= 12}{state:nat | state == 1 || state == 3}
  (sheet: sheet(left, state)): [after:nat | after >= left - 12] sheet(after, state) =
  let val () = raw(sheet, "border:none;") in sheet end

(* A control's accent (a slider's fill and thumb) in role edge on
   ground *)
fn accent {left:nat | left >= 40}{state:nat | state == 1 || state == 3}{edge,ground:nat | edge < NROLE; ground < NROLE}
  (visible: EDGEP(edge, ground) | sheet: sheet(left, state), edge: int edge, ground: int ground): [after:nat | after >= left - 40] sheet(after, state) = let
  val () = raw(sheet, "accent-color:")
  val () = _role_variable(sheet, edge)
  val () = raw(sheet, ";")
in sheet end

(* translateX(-50%): the only transform, which moves and never scales *)
fn centre_x {left:nat | left >= 32}{state:nat | state == 1 || state == 3}
  (sheet: sheet(left, state)): [after:nat | after >= left - 32] sheet(after, state) =
  let val () = raw(sheet, "transform:translateX(-50%);") in sheet end

(* opacity 0: an invisible target over a visible one (a file input) *)
fn invisible {left:nat | left >= 12}{state:nat | state == 1 || state == 3}
  (sheet: sheet(left, state)): [after:nat | after >= left - 12] sheet(after, state) =
  let val () = raw(sheet, "opacity:0;") in sheet end

(* ============================================================
   The themes and the base rules
   ============================================================ *)

fn _declare_role {left:nat | left >= 30}{role:nat | role < NROLE}{colour:nat | colour < 16777216}
  (sheet: sheet(left, 1), role: int role, colour: int colour): [after:nat | after >= left - 30] sheet(after, 1) = let
  val () = raw(sheet, "--")
  val () = raw(sheet, _role_name(role))
  val () = raw(sheet, ":")
  val () = _colour(sheet, colour)
  val () = raw(sheet, ";")
in sheet end

(* .th-<name>{--role:#rrggbb;...} for a theme: each colour is the one
   PAL gives, so the proofs above are about these *)
fn theme {theme_number:int}{left:nat | left >= 740}{length:nat | length <= 20}
  {bg_colour,fg_colour,muted_colour,card_colour,line_colour,
   edge_colour,bar_colour,barfg_colour,accent_colour,accentfg_colour,
   hl_colour,barhi_colour,banner_colour,bannerfg_colour,mark_colour,
   markfg_colour,danger_colour,hl2_colour:nat |
   bg_colour < 16777216; fg_colour < 16777216; muted_colour < 16777216;
   card_colour < 16777216; line_colour < 16777216; edge_colour < 16777216;
   bar_colour < 16777216; barfg_colour < 16777216; accent_colour < 16777216;
   accentfg_colour < 16777216; hl_colour < 16777216; barhi_colour < 16777216;
   banner_colour < 16777216; bannerfg_colour < 16777216; mark_colour < 16777216;
   markfg_colour < 16777216; danger_colour < 16777216; hl2_colour < 16777216}
  (bg_from_pal: PAL(theme_number, BG, bg_colour), fg_from_pal: PAL(theme_number, FG, fg_colour),
   muted_from_pal: PAL(theme_number, MUTED, muted_colour), card_from_pal: PAL(theme_number, CARD, card_colour),
   line_from_pal: PAL(theme_number, LINE, line_colour), edge_from_pal: PAL(theme_number, EDGE, edge_colour),
   bar_from_pal: PAL(theme_number, BAR, bar_colour), barfg_from_pal: PAL(theme_number, BARFG, barfg_colour),
   accent_from_pal: PAL(theme_number, ACCENT, accent_colour), accentfg_from_pal: PAL(theme_number, ACCENTFG, accentfg_colour),
   hl_from_pal: PAL(theme_number, HL, hl_colour), barhi_from_pal: PAL(theme_number, BARHI, barhi_colour),
   banner_from_pal: PAL(theme_number, BANNER, banner_colour), bannerfg_from_pal: PAL(theme_number, BANNERFG, bannerfg_colour),
   mark_from_pal: PAL(theme_number, MARK, mark_colour), markfg_from_pal: PAL(theme_number, MARKFG, markfg_colour),
   danger_from_pal: PAL(theme_number, DANGER, danger_colour), hl2_from_pal: PAL(theme_number, HL2, hl2_colour),
   harmony: HARMONY(theme_number) |
   sheet: sheet(left, 0), selector: string length,
   bg_colour: int bg_colour, fg_colour: int fg_colour, muted_colour: int muted_colour,
   card_colour: int card_colour, line_colour: int line_colour, edge_colour: int edge_colour,
   bar_colour: int bar_colour, barfg_colour: int barfg_colour, accent_colour: int accent_colour,
   accentfg_colour: int accentfg_colour, hl_colour: int hl_colour, barhi_colour: int barhi_colour,
   banner_colour: int banner_colour, bannerfg_colour: int bannerfg_colour, mark_colour: int mark_colour,
   markfg_colour: int markfg_colour, danger_colour: int danger_colour, hl2_colour: int hl2_colour): [after:nat | after >= left - 740] sheet(after, 0) = let
  val sheet = rule(sheet, selector)
  val sheet = _declare_role(sheet, 0, bg_colour)
  val sheet = _declare_role(sheet, 1, fg_colour)
  val sheet = _declare_role(sheet, 2, muted_colour)
  val sheet = _declare_role(sheet, 3, card_colour)
  val sheet = _declare_role(sheet, 4, line_colour)
  val sheet = _declare_role(sheet, 5, edge_colour)
  val sheet = _declare_role(sheet, 6, bar_colour)
  val sheet = _declare_role(sheet, 7, barfg_colour)
  val sheet = _declare_role(sheet, 8, accent_colour)
  val sheet = _declare_role(sheet, 9, accentfg_colour)
  val sheet = _declare_role(sheet, 10, hl_colour)
  val sheet = _declare_role(sheet, 11, barhi_colour)
  val sheet = _declare_role(sheet, 12, banner_colour)
  val sheet = _declare_role(sheet, 13, bannerfg_colour)
  val sheet = _declare_role(sheet, 14, mark_colour)
  val sheet = _declare_role(sheet, 15, markfg_colour)
  val sheet = _declare_role(sheet, 16, danger_colour)
  val sheet = _declare_role(sheet, 17, hl2_colour)
in close(sheet) end

(* The rules the guarantees rest on; the only !important in the sheet *)
fn _base {left:nat | left >= 1400} (sheet: sheet(left, 0)): [after:nat | after >= left - 1400] sheet(after, 0) = let
  val () = raw(sheet, "[data-hide='1'],[hidden]{display:none!important}")
  (* 44 x 44 targets: every button and field, everything given a
     control's role, and the app's links out (ui_link_out); links in a
     book's text are inline targets, which WCAG leaves to the text they
     sit in *)
  val () = raw(sheet, "button,input,select,textarea,[role=button],[role=menuitem],[role=tab],[role=slider],[role=option],[role=switch],.linkout")
  val () = raw(sheet, "{min-height:44px!important;min-width:44px!important;box-sizing:border-box}")
  (* 16px in text fields, so iOS does not zoom into them *)
  val () = raw(sheet, "input,select,textarea{font-size:16px!important}")
  (* focus: 2px inside the edge in the control's own proven colour *)
  val () = raw(sheet, ":focus-visible{outline:2px solid currentColor!important;outline-offset:-2px!important}")
  (* text fields: fg on card with a 3:1 edge (S_fg_card, E_edge_card) *)
  prval _ = S_fg_card
  prval _ = E_edge_card
  val () = raw(sheet, "input:not([type=range]):not([type=file]),textarea,select")
  val () = raw(sheet, "{color:var(--fg)!important;background-color:var(--card)!important;border:1px solid var(--edge)!important}")
  (* a search field's own clear button is too small a target *)
  val () = raw(sheet, "input[type=search]::-webkit-search-cancel-button{display:none}")
  (* a button is a surface like any other: fg on card until a rule
     says otherwise *)
  prval _ = S_fg_card
  val () = raw(sheet, "button{font:inherit;cursor:pointer;color:var(--fg);background-color:var(--card);border:0}")
in sheet end

(* ============================================================
   The stylesheet
   ============================================================ *)

fn _fonts {left:nat | left >= 1010} (sheet: sheet(left, 0)): [after:nat | after >= left - 1010] sheet(after, 0) = let
  val () = raw(sheet, "@font-face{font-family:Literata;src:url(literata-latin.woff2) format('woff2');font-style:normal;font-weight:200 900;font-display:swap}")
  val () = raw(sheet, "@font-face{font-family:Literata;src:url(literata-italic-latin.woff2) format('woff2');font-style:italic;font-weight:200 900;font-display:swap}")
  val () = raw(sheet, "@font-face{font-family:Inter;src:url(inter-latin.woff2) format('woff2');font-style:normal;font-weight:100 900;font-display:swap}")
  (* fetched only when chosen: a face is loaded once text uses it *)
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-400-normal.woff2) format('woff2');font-style:normal;font-weight:400;font-display:swap}")
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-700-normal.woff2) format('woff2');font-style:normal;font-weight:700;font-display:swap}")
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-400-italic.woff2) format('woff2');font-style:italic;font-weight:400;font-display:swap}")
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-700-italic.woff2) format('woff2');font-style:italic;font-weight:700;font-display:swap}")
in sheet end

fn _shell {left:nat | left >= 6600} (sheet: sheet(left, 0)): [after:nat | after >= left - 6600] sheet(after, 0) = let
  val sheet = rule(sheet, "body")
  val sheet = lay(sheet, Margin(), "0")
  val sheet = surf(S_fg_bg | sheet, 1, 0)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".app")
  val sheet = lay(sheet, MinHeight(), "100vh")
  val sheet = surf(S_fg_bg | sheet, 1, 0)
  val sheet = lay(sheet, FontFamily(), "Inter,system-ui,sans-serif")
  val sheet = lay(sheet, FontSize(), "16px")
  val sheet = lay(sheet, LineHeight(), "1.4")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".lib")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, MaxWidth(), "800px")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, Padding(), "max(12px,env(safe-area-inset-top)) 16px 24px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, MinHeight(), "100vh")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".lib.drag")
  val sheet = lay(sheet, Outline(), "3px dashed var(--accent)")
  val sheet = lay(sheet, OutlineOffset(), "-8px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bar")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = line(sheet, BottomSide(), 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ttl")
  val sheet = lay(sheet, FontFamily(), "Literata,Georgia,serif")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = lay(sheet, FontSize(), "22px")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Margin(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".btn")
  val sheet = lay(sheet, Display(), "inline-flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, Padding(), "8px 14px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = line(sheet, AllSides(), 1, 4)
  val sheet = lay(sheet, FontSize(), "15px")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".btn-p")
  val sheet = surf(S_accentfg_accent | sheet, 9, 8)
  val sheet = line(sheet, AllSides(), 1, 8)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".btn input[type=file]")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, Height(), "100%")
  val sheet = invisible(sheet)
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ibtn")
  val sheet = lay(sheet, FontSize(), "20px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_bg | sheet, 1, 0)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sfield")
  val sheet = lay(sheet, FlexBasis(), "100%")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".search")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = lay(sheet, Padding(), "6px 10px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = close(sheet)
  (* the error banner: at the top of the screen, over the library and
     the reader (and over the overlays and toasts) until dismissed *)
  val sheet = rule(sheet, ".banner")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Top(), "max(8px,env(safe-area-inset-top))")
  val sheet = lay(sheet, Left(), "50%")
  val sheet = centre_x(sheet)
  val sheet = lay(sheet, ZIndex(), "22")
  val sheet = lay(sheet, Width(), "calc(100% - 32px)")
  val sheet = lay(sheet, MaxWidth(), "640px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Padding(), "10px 12px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 12px rgba(0,0,0,.35)")
  val sheet = surf(S_bannerfg_banner | sheet, 13, 12)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".banner .ibtn")
  val sheet = surf(S_bannerfg_banner | sheet, 13, 12)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".banner span")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp")
  val sheet = lay(sheet, Margin(), "8px 0")
  val sheet = lay(sheet, Padding(), "10px 12px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = line(sheet, AllSides(), 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-n")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, TextOverflow(), "ellipsis")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-s")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-bar")
  val sheet = lay(sheet, Height(), "6px")
  val sheet = fill(sheet, 4)
  val sheet = lay(sheet, BorderRadius(), "3px")
  val sheet = lay(sheet, MarginTop(), "6px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-fill")
  val sheet = lay(sheet, Height(), "100%")
  val sheet = fill(sheet, 8)
  val sheet = lay(sheet, Width(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".list")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = close(sheet)
  (* the library's view controls: which books, list or grid *)
  val sheet = rule(sheet, ".lview")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, Margin(), "8px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg.vseg")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* reading aloud, sharing and the screen's controls are shown only
     where the platform has them: by their elements' data-hide
     (read_aloud.bats, sharing.bats, screen_controls.bats) *)
  val sheet = rule(sheet, ".ssel")
  val sheet = lay(sheet, Font(), "inherit")
  val sheet = lay(sheet, Padding(), "6px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, MaxWidth(), "12em")
  val sheet = close(sheet)
  (* the hint for iOS Safari, shown (on) only there (library.bats);
     Install Quire and the storage notes are shown by their elements'
     data-hide (platform.bats) *)
  val sheet = rule(sheet, ".ihint")
  val sheet = lay(sheet, Display(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ihint.on")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Padding(), "12px")
  val sheet = lay(sheet, Margin(), "8px 0")
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  (* the collections, a row of their own under the view's controls *)
  val sheet = rule(sheet, ".crow")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, Gap(), "6px")
  val sheet = lay(sheet, Flex(), "1 1 100%")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".conth")
  val sheet = lay(sheet, FontWeight(), "600")
  val sheet = lay(sheet, MarginTop(), "8px")
  val sheet = close(sheet)
  (* a grid of covers, the title and progress under each *)
  val sheet = rule(sheet, ".list.grid")
  val sheet = lay(sheet, Display(), "grid")
  (* no rows given, the columns as many as fit *)
  val sheet = lay(sheet, GridTemplate(), "none/repeat(auto-fill,minmax(150px,1fr))")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grid .cardrow")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Margin(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grid .card")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, AlignItems(), "stretch")
  val sheet = lay(sheet, TextAlign(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grid .cov")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, Height(), "auto")
  val sheet = lay(sheet, AspectRatio(), "2/3")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grid .cmore")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "6px")
  val sheet = lay(sheet, Right(), "6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grid .pbar")
  val sheet = lay(sheet, MaxWidth(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grid .prog")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".cardrow")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "stretch")
  val sheet = lay(sheet, Gap(), "6px")
  val sheet = lay(sheet, Margin(), "6px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".card")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = lay(sheet, TextAlign(), "left")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Padding(), "10px")
  val sheet = line(sheet, AllSides(), 1, 4)
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".card *")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".cmore")
  val sheet = lay(sheet, FontSize(), "22px")
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = line(sheet, AllSides(), 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".cov")
  val sheet = lay(sheet, Width(), "48px")
  val sheet = lay(sheet, Height(), "72px")
  val sheet = lay(sheet, ObjectFit(), "cover")
  val sheet = lay(sheet, BorderRadius(), "3px")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = fill(sheet, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".cinfo")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bt")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = lay(sheet, FontSize(), "16px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, TextOverflow(), "ellipsis")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ba")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  (* a book's series and number *)
  val sheet = rule(sheet, ".bser")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".prog")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, MarginTop(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pbar")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, MaxWidth(), "160px")
  val sheet = lay(sheet, Height(), "5px")
  val sheet = fill(sheet, 4)
  val sheet = lay(sheet, BorderRadius(), "3px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pfill")
  val sheet = lay(sheet, Height(), "100%")
  val sheet = fill(sheet, 8)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".empty")
  val sheet = lay(sheet, TextAlign(), "center")
  val sheet = surf(S_muted_bg | sheet, 2, 0)
  val sheet = lay(sheet, Padding(), "16px")
  val sheet = lay(sheet, MarginTop(), "15vh")
  val sheet = lay(sheet, FontSize(), "18px")
  val sheet = lay(sheet, FontStyle(), "italic")
  val sheet = close(sheet)
in sheet end

fn _overlays {left:nat | left >= 4500} (sheet: sheet(left, 0)): [after:nat | after >= left - 4500] sheet(after, 0) = let
  (* a book's image, full screen, on the page's ground; the fingers zoom
     and pan it *)
  val sheet = rule(sheet, ".imview")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, ZIndex(), "14")
  val sheet = fill(sheet, 0)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imbox")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, Height(), "100%")
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, TouchAction(), "pinch-zoom pan-x pan-y")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imimg")
  val sheet = lay(sheet, MaxWidth(), "100%")
  val sheet = lay(sheet, MaxHeight(), "100%")
  val sheet = lay(sheet, ObjectFit(), "contain")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imclose")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "max(8px,env(safe-area-inset-top))")
  val sheet = lay(sheet, Right(), "8px")
  val sheet = surf(S_barfg_bar | sheet, 7, 6)
  val sheet = lay(sheet, BorderRadius(), "50%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".toast")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Left(), "50%")
  val sheet = lay(sheet, Bottom(), "calc(env(safe-area-inset-bottom) + 112px)")
  val sheet = centre_x(sheet)
  (* over the overlays (a panel that removes something offers it back
     here, while it is still open) *)
  val sheet = lay(sheet, ZIndex(), "21")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = surf(S_barfg_bar | sheet, 7, 6)
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = lay(sheet, Padding(), "4px 4px 4px 16px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 12px rgba(0,0,0,.35)")
  val sheet = lay(sheet, Width(), "max-content")
  val sheet = lay(sheet, MaxWidth(), "min(92vw,420px)")
  val sheet = close(sheet)
  (* sync's toast, above the Undo toast *)
  val sheet = rule(sheet, ".toast.tup")
  val sheet = lay(sheet, Bottom(), "calc(env(safe-area-inset-bottom) + 168px)")
  val sheet = close(sheet)
  (* the copy status, above sync's: text alone, with no button *)
  val sheet = rule(sheet, ".toast.tcopy")
  val sheet = lay(sheet, Bottom(), "calc(env(safe-area-inset-bottom) + 224px)")
  val sheet = lay(sheet, Padding(), "10px 16px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ovl")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = veil(sheet)
  val sheet = lay(sheet, ZIndex(), "20")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".menu,.mbox")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = lay(sheet, Padding(), "8px")
  val sheet = lay(sheet, MinWidth(), "200px")
  val sheet = lay(sheet, MaxWidth(), "min(92vw,420px)")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, BoxShadow(), "0 4px 24px rgba(0,0,0,.3)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi")
  val sheet = lay(sheet, TextAlign(), "left")
  val sheet = lay(sheet, Padding(), "12px 14px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi:hover")
  val sheet = surf(S_fg_line | sheet, 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi[data-harm=y]")
  val sheet = surf(S_danger_card | sheet, 16, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi[data-harm=y]:hover")
  val sheet = surf(S_danger_line | sheet, 16, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".menu .mi.btn")
  val sheet = no_line(sheet)
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = lay(sheet, JustifyContent(), "flex-start")
  val sheet = lay(sheet, Padding(), "12px 14px")
  val sheet = lay(sheet, FontSize(), "inherit")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mbox")
  val sheet = lay(sheet, Padding(), "16px")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mtitle")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = lay(sheet, FontSize(), "18px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mname")
  val sheet = lay(sheet, Font(), "inherit")
  val sheet = lay(sheet, Padding(), "8px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = close(sheet)
  (* the sync panel: what it does, then its fields, one a line *)
  val sheet = rule(sheet, ".sabout")
  val sheet = lay(sheet, Padding(), "4px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sfields")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, Margin(), "8px 0")
  val sheet = close(sheet)
  (* a book's collections, one toggle a line *)
  val sheet = rule(sheet, ".seg.cseg")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Margin(), "8px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".cnone")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = lay(sheet, FontStyle(), "italic")
  val sheet = close(sheet)
  (* the reading statistics: a label and its number a line *)
  val sheet = rule(sheet, ".srow")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, JustifyContent(), "space-between")
  val sheet = lay(sheet, Gap(), "16px")
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow b")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mta")
  val sheet = lay(sheet, MinHeight(), "120px")
  val sheet = lay(sheet, Font(), "inherit")
  val sheet = lay(sheet, Padding(), "8px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mbtns")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, JustifyContent(), "flex-end")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".btn[data-harm=y]")
  val sheet = surf(S_danger_card | sheet, 16, 3)
  val sheet = line(sheet, AllSides(), 1, 16)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = lay(sheet, ZIndex(), "15")
  val sheet = surf(S_fg_bg | sheet, 1, 0)
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = lay(sheet, Padding(), "max(12px,env(safe-area-inset-top)) 16px 24px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info-in")
  val sheet = lay(sheet, MaxWidth(), "600px")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info-in>.btn")
  val sheet = lay(sheet, AlignSelf(), "flex-start")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".icov")
  val sheet = lay(sheet, Width(), "160px")
  val sheet = lay(sheet, MaxWidth(), "50vw")
  val sheet = lay(sheet, MaxHeight(), "300px")
  val sheet = lay(sheet, ObjectFit(), "contain")
  val sheet = lay(sheet, AlignSelf(), "center")
  val sheet = lay(sheet, BorderRadius(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".it")
  val sheet = lay(sheet, FontFamily(), "Literata,Georgia,serif")
  val sheet = lay(sheet, FontSize(), "22px")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = close(sheet)
  (* Book info's accessibility section: its title, and each group's *)
  val sheet = rule(sheet, ".a11y")
  val sheet = lay(sheet, MarginTop(), "16px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".a11yt")
  val sheet = lay(sheet, FontWeight(), "600")
  val sheet = lay(sheet, FontSize(), "18px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".a11yg")
  val sheet = lay(sheet, FontWeight(), "600")
  val sheet = lay(sheet, MarginTop(), "10px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".irow")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, JustifyContent(), "space-between")
  val sheet = line(sheet, BottomSide(), 1, 4)
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = surf(S_muted_bg | sheet, 2, 0)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".irow b")
  val sheet = surf(S_fg_bg | sheet, 1, 0)
  val sheet = lay(sheet, FontWeight(), "normal")
  val sheet = close(sheet)
in sheet end

fn _reader {left:nat | left >= 7000} (sheet: sheet(left, 0)): [after:nat | after >= left - 7000] sheet(after, 0) = let
  val sheet = rule(sheet, ".rv")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Height(), "100vh")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = surf(S_fg_bg | sheet, 1, 0)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top,.bot")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = lay(sheet, Padding(), "2px 6px")
  val sheet = surf(S_barfg_bar | sheet, 7, 6)
  val sheet = lay(sheet, ZIndex(), "3")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, PaddingTop(), "max(2px,env(safe-area-inset-top))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bot")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, PaddingBottom(), "max(2px,env(safe-area-inset-bottom))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top .ibtn,.bot .ibtn,.snavf .ibtn")
  val sheet = surf(S_barfg_bar | sheet, 7, 6)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top .ibtn:hover,.bot .ibtn:hover,.snavf .ibtn:hover")
  val sheet = surf(S_barfg_barhi | sheet, 7, 11)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ctitle")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, TextOverflow(), "ellipsis")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pinfo")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = close(sheet)
  (* a long chapter title is cut, and the page numbers after it are not *)
  val sheet = rule(sheet, ".pgt")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, TextOverflow(), "ellipsis")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pgn,.pgw")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = lay(sheet, WhiteSpace(), "pre")
  val sheet = close(sheet)
  (* the footer's readout, the one part of it a tap reaches: a tap on
     it shows the next *)
  val sheet = rule(sheet, ".rdo")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = lay(sheet, PointerEvents(), "auto")
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = close(sheet)
  (* a link out of the app, in a bar: a control's box, not a text link *)
  val sheet = rule(sheet, ".linkout")
  val sheet = lay(sheet, Display(), "inline-flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, TextDecoration(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".chrome-off .top,.chrome-off .bot")
  val sheet = lay(sheet, Display(), "none")
  val sheet = close(sheet)
  (* the running footer, in the page's bottom margin while the bars are
     hidden; taps go through it to the page *)
  val sheet = rule(sheet, ".foot")
  val sheet = lay(sheet, Display(), "none")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, Bottom(), "max(8px,env(safe-area-inset-bottom))")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, Padding(), "0 24px")
  val sheet = lay(sheet, FontSize(), "12px")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = surf(S_muted_bg | sheet, 2, 0)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".chrome-off .foot")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, PaddingTop(), "max(48px,env(safe-area-inset-top))")
  val sheet = lay(sheet, PaddingBottom(), "max(36px,env(safe-area-inset-bottom))")
  val sheet = lay(sheet, ColumnFill(), "auto")
  val sheet = lay(sheet, ColumnGap(), "0")
  val sheet = lay(sheet, ColumnWidth(), "100vw")
  val sheet = lay(sheet, FontFamily(), "Literata,Georgia,serif")
  val sheet = lay(sheet, FontSize(), "18px")
  val sheet = lay(sheet, LineHeight(), "1.6")
  val sheet = lay(sheet, Outline(), "none")
  val sheet = close(sheet)
  (* shown only by the typography's style, for a spread; a point the
     reader measures, never seen *)
  val sheet = rule(sheet, ".sprobe")
  val sheet = lay(sheet, Display(), "none")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Width(), "1px")
  val sheet = lay(sheet, Height(), "1px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf>*")
  val sheet = lay(sheet, MaxWidth(), "38rem")
  val sheet = lay(sheet, MarginLeft(), "auto")
  val sheet = lay(sheet, MarginRight(), "auto")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = close(sheet)
  (* a paragraph's alignment, hyphenation and the space after it are
     the reader's settings (settings.bats, in style-type) *)
  val sheet = rule(sheet, ".caf p")
  val sheet = lay(sheet, Margin(), "0 auto .8em")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf h1,.caf h2,.caf h3")
  val sheet = lay(sheet, TextAlign(), "center")
  val sheet = lay(sheet, MarginTop(), "1.5em")
  val sheet = lay(sheet, MarginBottom(), ".5em")
  val sheet = lay(sheet, BreakAfter(), "avoid")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf hr")
  val sheet = no_line(sheet)
  val sheet = line(sheet, TopSide(), 1, 4)
  val sheet = lay(sheet, Margin(), "2em auto")
  val sheet = lay(sheet, MaxWidth(), "200px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf img")
  val sheet = lay(sheet, MaxWidth(), "100%")
  val sheet = lay(sheet, MaxHeight(), "calc(100vh - 110px)")
  val sheet = lay(sheet, ObjectFit(), "contain")
  val sheet = lay(sheet, Height(), "auto")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, BreakInside(), "avoid")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf table")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, OverflowX(), "auto")
  val sheet = lay(sheet, MaxWidth(), "100%")
  val sheet = lay(sheet, BorderCollapse(), "collapse")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf td,.caf th")
  val sheet = line(sheet, AllSides(), 1, 4)
  val sheet = lay(sheet, Padding(), "2px 6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf a,.caf [role=link]")
  val sheet = surf(S_accent_bg | sheet, 8, 0)
  val sheet = lay(sheet, TextDecoration(), "underline")
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf pre")
  val sheet = lay(sheet, WhiteSpace(), "pre-wrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf blockquote")
  val sheet = lay(sheet, Margin(), "1em auto")
  val sheet = lay(sheet, FontStyle(), "italic")
  val sheet = close(sheet)
  (* right to left, the page itself: its columns go on to the left, and
     a spread's first page is the right one *)
  val sheet = rule(sheet, ".caf.rtl")
  val sheet = lay(sheet, Direction(), "rtl")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf figure")
  val sheet = lay(sheet, Margin(), "1em auto")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf sup,.caf sub")
  val sheet = lay(sheet, LineHeight(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, "::highlight(bats-mark-1)")
  val sheet = surf(S_fg_hl | sheet, 1, 10)
  val sheet = close(sheet)
  val sheet = rule(sheet, "::highlight(bats-mark-2)")
  val sheet = surf(S_markfg_mark | sheet, 15, 14)
  val sheet = close(sheet)
  (* the orange highlight; and the underline, in the text's own colour
     (so its contrast is the text's), thick enough to tell from a link's *)
  val sheet = rule(sheet, "::highlight(bats-mark-3)")
  val sheet = surf(S_fg_hl2 | sheet, 1, 17)
  val sheet = close(sheet)
  (* the sentence read aloud (read_aloud.bats) *)
  val sheet = rule(sheet, "::highlight(bats-mark-5)")
  val sheet = surf(S_markfg_mark | sheet, 15, 14)
  val sheet = close(sheet)
  val sheet = rule(sheet, "::highlight(bats-mark-4)")
  val sheet = lay(sheet, TextDecoration(), "underline 3px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".scr")
  val sheet = lay(sheet, FlexBasis(), "100%")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, Padding(), "0 6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".trk")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Height(), "44px")
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = lay(sheet, TouchAction(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".trk-l")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, Top(), "20px")
  val sheet = lay(sheet, Height(), "4px")
  val sheet = tint(sheet, true, 30)
  val sheet = lay(sheet, BorderRadius(), "2px")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".trk-f")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Top(), "20px")
  val sheet = lay(sheet, Height(), "4px")
  val sheet = fill(sheet, 7)
  val sheet = lay(sheet, BorderRadius(), "2px")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tick")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "16px")
  val sheet = lay(sheet, Width(), "2px")
  val sheet = lay(sheet, Height(), "12px")
  val sheet = tint(sheet, true, 60)
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".thumb")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "10px")
  val sheet = lay(sheet, Width(), "24px")
  val sheet = lay(sheet, Height(), "24px")
  val sheet = lay(sheet, MarginLeft(), "-12px")
  val sheet = lay(sheet, BorderRadius(), "50%")
  val sheet = fill(sheet, 7)
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tip")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Bottom(), "46px")
  val sheet = centre_x(sheet)
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = lay(sheet, Padding(), "2px 8px")
  val sheet = lay(sheet, BorderRadius(), "4px")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pct")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, MinWidth(), "3em")
  val sheet = lay(sheet, TextAlign(), "right")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pback")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "12px")
  val sheet = lay(sheet, Bottom(), "106px")
  val sheet = lay(sheet, ZIndex(), "4")
  val sheet = surf(S_accentfg_accent | sheet, 9, 8)
  val sheet = lay(sheet, BorderRadius(), "22px")
  val sheet = lay(sheet, Padding(), "8px 16px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sheet = close(sheet)
  (* scrolled, on the chapter's last screen: at the right, apart from
     Back at the left *)
  (* the hint on turning pages, over the page's middle *)
  val sheet = rule(sheet, ".hint")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "16px")
  val sheet = lay(sheet, Right(), "16px")
  val sheet = lay(sheet, Top(), "45%")
  val sheet = lay(sheet, Width(), "fit-content")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, ZIndex(), "4")
  val sheet = surf(S_accentfg_accent | sheet, 9, 8)
  val sheet = lay(sheet, BorderRadius(), "22px")
  val sheet = lay(sheet, Padding(), "10px 18px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".nextch")
  val sheet = lay(sheet, Left(), "auto")
  val sheet = lay(sheet, Right(), "12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seltb")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "50%")
  val sheet = lay(sheet, Bottom(), "106px")
  val sheet = centre_x(sheet)
  val sheet = lay(sheet, ZIndex(), "5")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = surf(S_barfg_bar | sheet, 7, 6)
  val sheet = lay(sheet, BorderRadius(), "10px")
  val sheet = lay(sheet, Padding(), "4px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  (* no wider than the screen: its items go on a second row instead *)
  val sheet = lay(sheet, Width(), "max-content")
  val sheet = lay(sheet, MaxWidth(), "calc(100vw - 16px)")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seltb button,.seltb a")
  val sheet = lay(sheet, Padding(), "8px 14px")
  val sheet = surf(S_barfg_bar | sheet, 7, 6)
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seltb button:hover,.seltb a:hover")
  val sheet = surf(S_barfg_barhi | sheet, 7, 11)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".snavf")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "50%")
  val sheet = lay(sheet, Top(), "max(56px,calc(env(safe-area-inset-top) + 54px))")
  val sheet = centre_x(sheet)
  val sheet = lay(sheet, ZIndex(), "6")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "6px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = surf(S_barfg_bar | sheet, 7, 6)
  val sheet = lay(sheet, BorderRadius(), "24px")
  val sheet = lay(sheet, Padding(), "2px 8px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".snavf span")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, Padding(), "0 4px")
  val sheet = close(sheet)
in sheet end

fn _panels {left:nat | left >= 5400} (sheet: sheet(left, 0)): [after:nat | after >= left - 5400] sheet(after, 0) = let
  val sheet = rule(sheet, ".panel")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Width(), "min(420px,100vw)")
  val sheet = lay(sheet, ZIndex(), "12")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, BoxShadow(), "2px 0 16px rgba(0,0,0,.3)")
  val sheet = lay(sheet, PaddingTop(), "env(safe-area-inset-top)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".panel-r")
  val sheet = lay(sheet, Left(), "auto")
  val sheet = lay(sheet, Right(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ph")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "6px")
  val sheet = lay(sheet, Padding(), "6px 8px")
  val sheet = line(sheet, BottomSide(), 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ph .grow")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ph .ibtn")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabs")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tab")
  val sheet = lay(sheet, Padding(), "8px 12px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tab[aria-selected=true]")
  val sheet = surf(S_fg_line | sheet, 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".plist")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = lay(sheet, Padding(), "4px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, TextAlign(), "left")
  val sheet = lay(sheet, Padding(), "10px 14px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = line(sheet, BottomSide(), 1, 4)
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi[aria-current=true]")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = surf(S_fg_line | sheet, 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi1")
  val sheet = lay(sheet, PaddingLeft(), "30px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi2")
  val sheet = lay(sheet, PaddingLeft(), "46px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi3")
  val sheet = lay(sheet, PaddingLeft(), "62px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".snip")
  val sheet = lay(sheet, Display(), "block")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, MarginTop(), "2px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hq")
  val sheet = lay(sheet, Display(), "block")
  val sheet = line(sheet, LeftSide(), 3, 8)
  val sheet = lay(sheet, PaddingLeft(), "8px")
  val sheet = lay(sheet, FontStyle(), "italic")
  val sheet = close(sheet)
  (* a highlight's quote, marked as it is on the page, after its style's
     name *)
  val sheet = rule(sheet, ".hq-yellow")
  val sheet = surf(S_fg_hl | sheet, 1, 10)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hq-orange")
  val sheet = surf(S_fg_hl2 | sheet, 1, 17)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hq-under")
  val sheet = lay(sheet, TextDecoration(), "underline 3px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hstyle")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, FontSize(), "12px")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg.afilter")
  val sheet = lay(sheet, Margin(), "8px 12px")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hn")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, MarginTop(), "4px")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hbtns")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, MarginTop(), "6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hbtns button")
  val sheet = lay(sheet, Padding(), "4px 12px")
  val sheet = line(sheet, AllSides(), 1, 4)
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hrow")
  val sheet = line(sheet, BottomSide(), 1, 4)
  val sheet = lay(sheet, Padding(), "8px 12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hgo")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, TextAlign(), "left")
  val sheet = lay(sheet, Padding(), "4px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hgo *")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi.hgo")
  val sheet = lay(sheet, Padding(), "10px 14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi.hgo .snip")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = lay(sheet, MarginTop(), "0")
  val sheet = lay(sheet, LineHeight(), "1.45")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grp")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = lay(sheet, Padding(), "12px 12px 4px")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, LetterSpacing(), ".04em")
  val sheet = lay(sheet, TextTransform(), "uppercase")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sheet")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, ZIndex(), "12")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = lay(sheet, Padding(), "12px 16px max(16px,env(safe-area-inset-bottom))")
  val sheet = lay(sheet, BoxShadow(), "0 -2px 16px rgba(0,0,0,.3)")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "10px")
  val sheet = lay(sheet, MaxWidth(), "520px")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, BorderRadius(), "12px 12px 0 0")
  (* taller than a short screen allows: it scrolls *)
  val sheet = lay(sheet, MaxHeight(), "85vh")
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = close(sheet)
  (* its rows keep their height, and the sheet scrolls instead *)
  val sheet = rule(sheet, ".sheet>*")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* a note's text, over the page: a long one scrolls *)
  val sheet = rule(sheet, ".fntext")
  val sheet = lay(sheet, MaxHeight(), "50vh")
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = lay(sheet, LineHeight(), "1.5")
  val sheet = close(sheet)
  (* a dictionary's article, as text: its line breaks kept *)
  val sheet = rule(sheet, ".dart")
  val sheet = lay(sheet, WhiteSpace(), "pre-wrap")
  val sheet = close(sheet)
  (* a catalogue's book: its cover, title and author, and Get *)
  val sheet = rule(sheet, ".bkrow")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = lay(sheet, Padding(), "10px 14px")
  val sheet = line(sheet, BottomSide(), 1, 4)
  val sheet = close(sheet)
  (* the fields that add a catalogue *)
  val sheet = rule(sheet, ".cform")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "10px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".slabel")
  val sheet = lay(sheet, Width(), "7em")
  val sheet = surf(S_muted_card | sheet, 2, 3)
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow input[type=range]")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = accent(E_accent_card | sheet, 8, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sval")
  val sheet = lay(sheet, Width(), "3em")
  val sheet = lay(sheet, TextAlign(), "right")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "6px")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg button")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Padding(), "8px 6px")
  val sheet = line(sheet, AllSides(), 1, 4)
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = surf(S_fg_card | sheet, 1, 3)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg button[aria-pressed=true]")
  val sheet = surf(S_accentfg_accent | sheet, 9, 8)
  val sheet = line(sheet, AllSides(), 1, 8)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sfoot")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, JustifyContent(), "space-between")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".link")
  val sheet = surf(S_accent_card | sheet, 8, 3)
  val sheet = lay(sheet, TextDecoration(), "underline")
  val sheet = lay(sheet, Padding(), "6px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sbar")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "6px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Padding(), "6px 8px")
  val sheet = line(sheet, BottomSide(), 1, 4)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sbar input")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Padding(), "6px 10px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, Font(), "inherit")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".snav")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, Padding(), "6px")
  val sheet = line(sheet, TopSide(), 1, 4)
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
in sheet end

fn _under_480px {left:nat | left >= 430} (sheet: sheet(left, 0)): [after:nat | after >= left - 430] sheet(after, 0) = let
  val sheet = media(sheet, "(max-width:480px)")
  val sheet = rule(sheet, ".lib")
  val sheet = lay(sheet, PaddingLeft(), "10px")
  val sheet = lay(sheet, PaddingRight(), "10px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ttl")
  val sheet = lay(sheet, FontSize(), "20px")
  val sheet = lay(sheet, Flex(), "1 1 calc(100% - 60px)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bar>.ibtn")
  val sheet = lay(sheet, Order(), "1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bar>.btn")
  val sheet = lay(sheet, Order(), "2")
  val sheet = lay(sheet, Padding(), "8px 9px")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bar>.sfield")
  val sheet = lay(sheet, Order(), "3")
  val sheet = close(sheet)
  (* the page indicator's title and " · page ": read out, not shown
     (the title is in the top bar, and the pages show in full, "1 of 12
     in chapter") *)
  val sheet = rule(sheet, ".pinfo .pgt,.pgw")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Width(), "1px")
  val sheet = lay(sheet, Height(), "1px")
  val sheet = lay(sheet, Margin(), "-1px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = media_end(sheet)
in sheet end

fn _under_600px {left:nat | left >= 57} (sheet: sheet(left, 0)): [after:nat | after >= left - 57] sheet(after, 0) = let
  val sheet = media(sheet, "(max-width:600px)")
  val sheet = rule(sheet, ".caf p")
  val sheet = lay(sheet, TextAlign(), "start")
  val sheet = close(sheet)
  val sheet = media_end(sheet)
in sheet end

(* The axes the page turn (gestures region 1, on .caf) owns: the
   stylesheet's touch-action for .caf comes from them, so the browser
   leaves exactly that axis to the recognizer *)
#pub fn page_turn_axes (): $GT.axes

implement page_turn_axes () = $GT.AxH()

#pub fn app_style (): [l:agz][k:nat | k < 65536] @($A.arr(byte, l, $B.BUILDER_CAP), int k)

implement app_style () = let
  val builder = $B.create()
  val sheet: sheet(BUDGET, 0) = Sheet(builder)
  val sheet = _fonts(sheet)
  (* the light theme is also the root's, so the page behind the app has
     the palette too *)
  val sheet = theme(PAL0_bg(), PAL0_fg(), PAL0_muted(), PAL0_card(), PAL0_line(), PAL0_edge(),
    PAL0_bar(), PAL0_barfg(), PAL0_accent(), PAL0_accentfg(), PAL0_hl(), PAL0_barhi(),
    PAL0_banner(), PAL0_bannerfg(), PAL0_mark(), PAL0_markfg(), PAL0_danger(), PAL0_hl2(), H_light |
    sheet, ":root,.th-light", 0xfaf8f5, 0x2a2a2a, 0x6b6b6b, 0xffffff, 0xdddddd, 0x8a8a8a,
    0x333333, 0xffffff, 0x2f6f4f, 0xffffff, 0xfde59a, 0x4a4a4a, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xb3261e, 0xfbc58a)
  val sheet = theme(PAL1_bg(), PAL1_fg(), PAL1_muted(), PAL1_card(), PAL1_line(), PAL1_edge(),
    PAL1_bar(), PAL1_barfg(), PAL1_accent(), PAL1_accentfg(), PAL1_hl(), PAL1_barhi(),
    PAL1_banner(), PAL1_bannerfg(), PAL1_mark(), PAL1_markfg(), PAL1_danger(), PAL1_hl2(), H_sepia |
    sheet, ".th-sepia", 0xf0e6d2, 0x3b2f22, 0x6e5e4a, 0xf7efdf, 0xd6c7a8, 0x8f7d62,
    0x4a3b2a, 0xf7efdf, 0x7a4f1d, 0xffffff, 0xe6cf8a, 0x5e4c38, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0x9c2a1c, 0xe8b880)
  val sheet = theme(PAL2_bg(), PAL2_fg(), PAL2_muted(), PAL2_card(), PAL2_line(), PAL2_edge(),
    PAL2_bar(), PAL2_barfg(), PAL2_accent(), PAL2_accentfg(), PAL2_hl(), PAL2_barhi(),
    PAL2_banner(), PAL2_bannerfg(), PAL2_mark(), PAL2_markfg(), PAL2_danger(), PAL2_hl2(), H_dark |
    sheet, ".th-dark", 0x1e1e1e, 0xe2e2e2, 0xa0a0a0, 0x2a2a2a, 0x3d3d3d, 0x7a7a7a,
    0x111111, 0xe2e2e2, 0x7fc49b, 0x10231a, 0x6d5e2f, 0x2e2e2e, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xffb4ab, 0x7b5831)
  val sheet = theme(PAL3_bg(), PAL3_fg(), PAL3_muted(), PAL3_card(), PAL3_line(), PAL3_edge(),
    PAL3_bar(), PAL3_barfg(), PAL3_accent(), PAL3_accentfg(), PAL3_hl(), PAL3_barhi(),
    PAL3_banner(), PAL3_bannerfg(), PAL3_mark(), PAL3_markfg(), PAL3_danger(), PAL3_hl2(), H_night |
    sheet, ".th-night", 0x1f1a14, 0xc2b296, 0x9a8a70, 0x2a231b, 0x3d342a, 0x857560,
    0x15110c, 0xc2b296, 0xc9a36b, 0x1f1a14, 0x4f4318, 0x342b21, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xe8a598, 0x5c3f1f)
  val sheet = theme(PAL4_bg(), PAL4_fg(), PAL4_muted(), PAL4_card(), PAL4_line(), PAL4_edge(),
    PAL4_bar(), PAL4_barfg(), PAL4_accent(), PAL4_accentfg(), PAL4_hl(), PAL4_barhi(),
    PAL4_banner(), PAL4_bannerfg(), PAL4_mark(), PAL4_markfg(), PAL4_danger(), PAL4_hl2(), H_grey |
    sheet, ".th-grey", 0x3a3a3a, 0xe2e2e2, 0xb8b8b8, 0x444444, 0x4f4f4f, 0x999999,
    0x2a2a2a, 0xe2e2e2, 0x8fd0a8, 0x10231a, 0x6d5e2f, 0x3d3d3d, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xffb4ab, 0x7b5831)
  val sheet = _base(sheet)
  val sheet = _shell(sheet)
  val sheet = _overlays(sheet)
  val sheet = _reader(sheet)
  val sheet = _panels(sheet)
  val sheet = _under_480px(sheet)
  val sheet = _under_600px(sheet)
  val sheet = rule(sheet, ".caf")
  val sheet = lay(sheet, TouchAction(), $GT.touch_action(page_turn_axes(), false))
  val sheet = close(sheet)
  val+ ~Sheet(builder) = sheet
  val @(bytes, length) = $B.to_arr(builder)
in @(bytes, length) end

end

