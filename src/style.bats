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

staload "page_size.sats"

(* ============================================================
   Roles and palette
   ============================================================ *)

(* A role is a custom property, --<name>, set per theme *)
datasort colour_role =
  | BG | FG | MUTED | CARD | LINE | EDGE | BAR | BARFG | ACCENT | ACCENTFG | HL | BARHI | BANNER | BANNERFG | MARK | MARKFG | DANGER | HL2

(* A role as a value, indexed by the role it is *)
datatype role_value(colour_role) =
  | RoleGround(BG) of ()
  | RoleText(FG) of ()
  | RoleMuted(MUTED) of ()
  | RoleCard(CARD) of ()
  | RoleLine(LINE) of ()
  | RoleEdge(EDGE) of ()
  | RoleBar(BAR) of ()
  | RoleBarText(BARFG) of ()
  | RoleAccent(ACCENT) of ()
  | RoleAccentText(ACCENTFG) of ()
  | RoleHighlight(HL) of ()
  | RoleBarHigh(BARHI) of ()
  | RoleBanner(BANNER) of ()
  | RoleBannerText(BANNERFG) of ()
  | RoleMark(MARK) of ()
  | RoleMarkText(MARKFG) of ()
  | RoleDanger(DANGER) of ()
  | RoleSecondHighlight(HL2) of ()

(* Themes: light, sepia, dark, night (warm, low in blue, for reading in
   the dark) and grey, each indexed by its number in the palette (PAL's
   first index): the one place a theme becomes that number *)
#pub datasort palette = PaletteLight | PaletteSepia | PaletteDark | PaletteNight | PaletteGrey
#pub datatype palette_theme(palette) =
  | Light(PaletteLight) of () | Sepia(PaletteSepia) of () | Dark(PaletteDark) of () | Night(PaletteNight) of () | Grey(PaletteGrey) of ()
#pub typedef theme = [which:palette] palette_theme(which)

(* A theme's number, as settings store it (after auto) *)
#pub fn theme_palette {which:palette} (which: palette_theme(which)): [number:nat | number < 5] int number
implement theme_palette (which) =
  case+ which of Light() => 0 | Sepia() => 1 | Dark() => 2 | Night() => 3 | Grey() => 4

(* The rule's selector of a theme (the light theme's is also the root's) *)
fn _theme_selector {which:palette} (which: palette_theme(which)): [length:nat | length <= 20] string length =
  case+ which of
  | Light() => ":root,.th-light" | Sepia() => ".th-sepia" | Dark() => ".th-dark" | Night() => ".th-night"
  | Grey() => ".th-grey"

(* PAL(t, r, c): in theme t, role r is the colour 0xc *)
dataprop PAL(palette, colour_role, int) =
  | PAL0_bg(PaletteLight, BG, 0xfaf8f5) | PAL1_bg(PaletteSepia, BG, 0xf0e6d2) | PAL2_bg(PaletteDark, BG, 0x1e1e1e) | PAL3_bg(PaletteNight, BG, 0x1f1a14) | PAL4_bg(PaletteGrey, BG, 0x3a3a3a)
  | PAL0_fg(PaletteLight, FG, 0x2a2a2a) | PAL1_fg(PaletteSepia, FG, 0x3b2f22) | PAL2_fg(PaletteDark, FG, 0xe2e2e2) | PAL3_fg(PaletteNight, FG, 0xc2b296) | PAL4_fg(PaletteGrey, FG, 0xe2e2e2)
  | PAL0_muted(PaletteLight, MUTED, 0x6b6b6b) | PAL1_muted(PaletteSepia, MUTED, 0x6e5e4a) | PAL2_muted(PaletteDark, MUTED, 0xa0a0a0) | PAL3_muted(PaletteNight, MUTED, 0x9a8a70) | PAL4_muted(PaletteGrey, MUTED, 0xb8b8b8)
  | PAL0_card(PaletteLight, CARD, 0xffffff) | PAL1_card(PaletteSepia, CARD, 0xf7efdf) | PAL2_card(PaletteDark, CARD, 0x2a2a2a) | PAL3_card(PaletteNight, CARD, 0x2a231b) | PAL4_card(PaletteGrey, CARD, 0x444444)
  | PAL0_line(PaletteLight, LINE, 0xdddddd) | PAL1_line(PaletteSepia, LINE, 0xd6c7a8) | PAL2_line(PaletteDark, LINE, 0x3d3d3d) | PAL3_line(PaletteNight, LINE, 0x3d342a) | PAL4_line(PaletteGrey, LINE, 0x4f4f4f)
  | PAL0_edge(PaletteLight, EDGE, 0x8a8a8a) | PAL1_edge(PaletteSepia, EDGE, 0x8f7d62) | PAL2_edge(PaletteDark, EDGE, 0x7a7a7a) | PAL3_edge(PaletteNight, EDGE, 0x857560) | PAL4_edge(PaletteGrey, EDGE, 0x999999)
  | PAL0_bar(PaletteLight, BAR, 0x333333) | PAL1_bar(PaletteSepia, BAR, 0x4a3b2a) | PAL2_bar(PaletteDark, BAR, 0x111111) | PAL3_bar(PaletteNight, BAR, 0x15110c) | PAL4_bar(PaletteGrey, BAR, 0x2a2a2a)
  | PAL0_barfg(PaletteLight, BARFG, 0xffffff) | PAL1_barfg(PaletteSepia, BARFG, 0xf7efdf) | PAL2_barfg(PaletteDark, BARFG, 0xe2e2e2) | PAL3_barfg(PaletteNight, BARFG, 0xc2b296) | PAL4_barfg(PaletteGrey, BARFG, 0xe2e2e2)
  | PAL0_accent(PaletteLight, ACCENT, 0x2f6f4f) | PAL1_accent(PaletteSepia, ACCENT, 0x7a4f1d) | PAL2_accent(PaletteDark, ACCENT, 0x7fc49b) | PAL3_accent(PaletteNight, ACCENT, 0xc9a36b) | PAL4_accent(PaletteGrey, ACCENT, 0x8fd0a8)
  | PAL0_accentfg(PaletteLight, ACCENTFG, 0xffffff) | PAL1_accentfg(PaletteSepia, ACCENTFG, 0xffffff) | PAL2_accentfg(PaletteDark, ACCENTFG, 0x10231a) | PAL3_accentfg(PaletteNight, ACCENTFG, 0x1f1a14) | PAL4_accentfg(PaletteGrey, ACCENTFG, 0x10231a)
  (* a highlight, opaque: the old translucent yellows over each page *)
  | PAL0_hl(PaletteLight, HL, 0xfde59a) | PAL1_hl(PaletteSepia, HL, 0xe6cf8a) | PAL2_hl(PaletteDark, HL, 0x6d5e2f) | PAL3_hl(PaletteNight, HL, 0x4f4318) | PAL4_hl(PaletteGrey, HL, 0x6d5e2f)
  | PAL0_barhi(PaletteLight, BARHI, 0x4a4a4a) | PAL1_barhi(PaletteSepia, BARHI, 0x5e4c38) | PAL2_barhi(PaletteDark, BARHI, 0x2e2e2e) | PAL3_barhi(PaletteNight, BARHI, 0x342b21) | PAL4_barhi(PaletteGrey, BARHI, 0x3d3d3d)
  | PAL0_banner(PaletteLight, BANNER, 0xfbe3e1) | PAL1_banner(PaletteSepia, BANNER, 0xfbe3e1) | PAL2_banner(PaletteDark, BANNER, 0xfbe3e1) | PAL3_banner(PaletteNight, BANNER, 0xfbe3e1) | PAL4_banner(PaletteGrey, BANNER, 0xfbe3e1)
  | PAL0_bannerfg(PaletteLight, BANNERFG, 0x6b1d16) | PAL1_bannerfg(PaletteSepia, BANNERFG, 0x6b1d16) | PAL2_bannerfg(PaletteDark, BANNERFG, 0x6b1d16) | PAL3_bannerfg(PaletteNight, BANNERFG, 0x6b1d16) | PAL4_bannerfg(PaletteGrey, BANNERFG, 0x6b1d16)
  | PAL0_mark(PaletteLight, MARK, 0xffb300) | PAL1_mark(PaletteSepia, MARK, 0xffb300) | PAL2_mark(PaletteDark, MARK, 0xffb300) | PAL3_mark(PaletteNight, MARK, 0xffb300) | PAL4_mark(PaletteGrey, MARK, 0xffb300)
  | PAL0_markfg(PaletteLight, MARKFG, 0x000000) | PAL1_markfg(PaletteSepia, MARKFG, 0x000000) | PAL2_markfg(PaletteDark, MARKFG, 0x000000) | PAL3_markfg(PaletteNight, MARKFG, 0x000000) | PAL4_markfg(PaletteGrey, MARKFG, 0x000000)
  | PAL0_danger(PaletteLight, DANGER, 0xb3261e) | PAL1_danger(PaletteSepia, DANGER, 0x9c2a1c) | PAL2_danger(PaletteDark, DANGER, 0xffb4ab) | PAL3_danger(PaletteNight, DANGER, 0xe8a598) | PAL4_danger(PaletteGrey, DANGER, 0xffb4ab)
  (* a second highlight, orange: the yellows' family, apart in hue *)
  | PAL0_hl2(PaletteLight, HL2, 0xfbc58a) | PAL1_hl2(PaletteSepia, HL2, 0xe8b880) | PAL2_hl2(PaletteDark, HL2, 0x7b5831) | PAL3_hl2(PaletteNight, HL2, 0x5c3f1f) | PAL4_hl2(PaletteGrey, HL2, 0x7b5831)

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
dataprop SURF(colour_role, colour_role) =
  | {text,ground:colour_role}
    {text_light,ground_light,
     text_sepia,ground_sepia,
     text_dark,ground_dark,
     text_night,ground_night,
     text_grey,ground_grey:int}
    SURFc(text, ground) of (
       PAL(PaletteLight, text, text_light), PAL(PaletteLight, ground, ground_light),
       $CT.CONTRAST(text_light, ground_light, 45), $H.NOVIB(text_light, ground_light),
       PAL(PaletteSepia, text, text_sepia), PAL(PaletteSepia, ground, ground_sepia),
       $CT.CONTRAST(text_sepia, ground_sepia, 45), $H.NOVIB(text_sepia, ground_sepia),
       PAL(PaletteDark, text, text_dark), PAL(PaletteDark, ground, ground_dark),
       $CT.CONTRAST(text_dark, ground_dark, 45), $H.NOVIB(text_dark, ground_dark),
       PAL(PaletteNight, text, text_night), PAL(PaletteNight, ground, ground_night),
       $CT.CONTRAST(text_night, ground_night, 45), $H.NOVIB(text_night, ground_night),
       PAL(PaletteGrey, text, text_grey), PAL(PaletteGrey, ground, ground_grey),
       $CT.CONTRAST(text_grey, ground_grey, 45), $H.NOVIB(text_grey, ground_grey))

dataprop EDGEP(colour_role, colour_role) =
  | {edge,ground:colour_role}
    {edge_light,ground_light,
     edge_sepia,ground_sepia,
     edge_dark,ground_dark,
     edge_night,ground_night,
     edge_grey,ground_grey:int}
    EDGEc(edge, ground) of (
       PAL(PaletteLight, edge, edge_light), PAL(PaletteLight, ground, ground_light),
       $CT.CONTRAST(edge_light, ground_light, 30),
       PAL(PaletteSepia, edge, edge_sepia), PAL(PaletteSepia, ground, ground_sepia),
       $CT.CONTRAST(edge_sepia, ground_sepia, 30),
       PAL(PaletteDark, edge, edge_dark), PAL(PaletteDark, ground, ground_dark),
       $CT.CONTRAST(edge_dark, ground_dark, 30),
       PAL(PaletteNight, edge, edge_night), PAL(PaletteNight, ground, ground_night),
       $CT.CONTRAST(edge_night, ground_night, 30),
       PAL(PaletteGrey, edge, edge_grey), PAL(PaletteGrey, ground, ground_grey),
       $CT.CONTRAST(edge_grey, ground_grey, 30))

(* Each theme's hue families (css's harmony.bats): at most three arcs,
   none wider than 30 degrees. The first is the tint of its neutrals.
   Light: warm paper, a green accent, red for danger. Sepia: warm, its
   accent brown in the same family, red. Dark and grey: grey neutrals,
   the warm highlight, a green accent, red. Night: as sepia, on a dark
   ground. *)
dataprop FAM(palette, int, int, int, int, int, int) =
  | FAM_light(PaletteLight, 25, 50, 135, 165, ~15, 15) of $H.FAMILIES(25, 50, 135, 165, ~15, 15)
  | FAM_sepia(PaletteSepia, 25, 50, 25, 50, ~15, 15) of $H.FAMILIES(25, 50, 25, 50, ~15, 15)
  | FAM_dark(PaletteDark, 25, 50, 130, 160, ~15, 15) of $H.FAMILIES(25, 50, 130, 160, ~15, 15)
  | FAM_night(PaletteNight, 25, 50, 25, 50, ~15, 15) of $H.FAMILIES(25, 50, 25, 50, ~15, 15)
  | FAM_grey(PaletteGrey, 25, 50, 130, 160, ~15, 15) of $H.FAMILIES(25, 50, 130, 160, ~15, 15)

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
dataprop HARMONY(palette) =
  | {theme_number:palette}{first_low,first_high,second_low,second_high,third_low,third_high:int}
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

(* The shade over the incoming page as a page turns (reader.bats) is
   black at some strength over the whole page, text and all. Browsers
   blend it in sRGB, channel by channel: SHADE(c, strength, s) says the
   colour c under black at strength percent is s, each channel rounded
   (the LIN witnesses pin the six channels). SHADED(t, text, ground,
   strength, k): in theme t, text on ground under that shade still
   reaches k / 10. VEILED(t, strength): every pair the page shows does,
   its text at 7:1 (HARMONY's at rest) and the rest at 4.5:1 (SURF's):
   links, the two highlights and the marks (search, reading aloud). So
   a shade is written only at a strength that leaves the page legible
   (_shade_rule) *)
dataprop SHADE(int, int, int) =
  | {r,g,b,shaded_r,shaded_g,shaded_b:nat | r < 256; g < 256; b < 256}{strength:nat | strength <= 100}
    {rl,rh,gl,gh,bl,bh,srl,srh,sgl,sgh,sbl,sbh:int |
     100 * shaded_r <= r * (100 - strength) + 50; r * (100 - strength) + 50 < 100 * shaded_r + 100;
     100 * shaded_g <= g * (100 - strength) + 50; g * (100 - strength) + 50 < 100 * shaded_g + 100;
     100 * shaded_b <= b * (100 - strength) + 50; b * (100 - strength) + 50 < 100 * shaded_b + 100}
    SHADEc(r * 65536 + g * 256 + b, strength, shaded_r * 65536 + shaded_g * 256 + shaded_b) of
      ($CT.LIN(r, rl, rh), $CT.LIN(g, gl, gh), $CT.LIN(b, bl, bh),
       $CT.LIN(shaded_r, srl, srh), $CT.LIN(shaded_g, sgl, sgh), $CT.LIN(shaded_b, sbl, sbh))

dataprop SHADED(palette, colour_role, colour_role, int, int) =
  | {t:palette}{text,ground:colour_role}{strength,k:int}{text_colour,ground_colour,text_shaded,ground_shaded:int}
    SHADEDc(t, text, ground, strength, k) of (
      PAL(t, text, text_colour), PAL(t, ground, ground_colour),
      SHADE(text_colour, strength, text_shaded), SHADE(ground_colour, strength, ground_shaded),
      $CT.CONTRAST(text_shaded, ground_shaded, k))

dataprop VEILED(palette, int) =
  | {t:palette}{strength:int}
    VEILEDc(t, strength) of (
      SHADED(t, FG, BG, strength, 70), SHADED(t, ACCENT, BG, strength, 45),
      SHADED(t, FG, HL, strength, 45), SHADED(t, FG, HL2, strength, 45),
      SHADED(t, MARKFG, MARK, strength, 45))

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
prval H_light: HARMONY(PaletteLight) = HARMONYc(
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
prval H_sepia: HARMONY(PaletteSepia) = HARMONYc(
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
prval H_dark: HARMONY(PaletteDark) = HARMONYc(
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
prval H_night: HARMONY(PaletteNight) = HARMONYc(
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
prval H_grey: HARMONY(PaletteGrey) = HARMONYc(
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
prval V_light_6: VEILED(PaletteLight, 6) = VEILEDc(
  SHADEDc(PAL0_fg(), PAL0_bg(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_27(), $CT.LIN_27(), $CT.LIN_27()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_eb(), $CT.LIN_e9(), $CT.LIN_e6()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_27(), $CT.LIN_27(), $CT.LIN_27()), $CT.LUMc($CT.LIN_eb(), $CT.LIN_e9(), $CT.LIN_e6()))),
  SHADEDc(PAL0_accent(), PAL0_bg(),
    SHADEc($CT.LIN_2f(), $CT.LIN_6f(), $CT.LIN_4f(), $CT.LIN_2c(), $CT.LIN_68(), $CT.LIN_4a()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_eb(), $CT.LIN_e9(), $CT.LIN_e6()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_2c(), $CT.LIN_68(), $CT.LIN_4a()), $CT.LUMc($CT.LIN_eb(), $CT.LIN_e9(), $CT.LIN_e6()))),
  SHADEDc(PAL0_fg(), PAL0_hl(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_27(), $CT.LIN_27(), $CT.LIN_27()),
    SHADEc($CT.LIN_fd(), $CT.LIN_e5(), $CT.LIN_9a(), $CT.LIN_ee(), $CT.LIN_d7(), $CT.LIN_91()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_27(), $CT.LIN_27(), $CT.LIN_27()), $CT.LUMc($CT.LIN_ee(), $CT.LIN_d7(), $CT.LIN_91()))),
  SHADEDc(PAL0_fg(), PAL0_hl2(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_27(), $CT.LIN_27(), $CT.LIN_27()),
    SHADEc($CT.LIN_fb(), $CT.LIN_c5(), $CT.LIN_8a(), $CT.LIN_ec(), $CT.LIN_b9(), $CT.LIN_82()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_27(), $CT.LIN_27(), $CT.LIN_27()), $CT.LUMc($CT.LIN_ec(), $CT.LIN_b9(), $CT.LIN_82()))),
  SHADEDc(PAL0_markfg(), PAL0_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_f0(), $CT.LIN_a8(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_f0(), $CT.LIN_a8(), $CT.LIN_00()))))
prval V_light_12: VEILED(PaletteLight, 12) = VEILEDc(
  SHADEDc(PAL0_fg(), PAL0_bg(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_25(), $CT.LIN_25(), $CT.LIN_25()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_dc(), $CT.LIN_da(), $CT.LIN_d8()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_25(), $CT.LIN_25(), $CT.LIN_25()), $CT.LUMc($CT.LIN_dc(), $CT.LIN_da(), $CT.LIN_d8()))),
  SHADEDc(PAL0_accent(), PAL0_bg(),
    SHADEc($CT.LIN_2f(), $CT.LIN_6f(), $CT.LIN_4f(), $CT.LIN_29(), $CT.LIN_62(), $CT.LIN_46()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_dc(), $CT.LIN_da(), $CT.LIN_d8()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_29(), $CT.LIN_62(), $CT.LIN_46()), $CT.LUMc($CT.LIN_dc(), $CT.LIN_da(), $CT.LIN_d8()))),
  SHADEDc(PAL0_fg(), PAL0_hl(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_25(), $CT.LIN_25(), $CT.LIN_25()),
    SHADEc($CT.LIN_fd(), $CT.LIN_e5(), $CT.LIN_9a(), $CT.LIN_df(), $CT.LIN_ca(), $CT.LIN_88()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_25(), $CT.LIN_25(), $CT.LIN_25()), $CT.LUMc($CT.LIN_df(), $CT.LIN_ca(), $CT.LIN_88()))),
  SHADEDc(PAL0_fg(), PAL0_hl2(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_25(), $CT.LIN_25(), $CT.LIN_25()),
    SHADEc($CT.LIN_fb(), $CT.LIN_c5(), $CT.LIN_8a(), $CT.LIN_dd(), $CT.LIN_ad(), $CT.LIN_79()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_25(), $CT.LIN_25(), $CT.LIN_25()), $CT.LUMc($CT.LIN_dd(), $CT.LIN_ad(), $CT.LIN_79()))),
  SHADEDc(PAL0_markfg(), PAL0_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_e0(), $CT.LIN_9e(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_e0(), $CT.LIN_9e(), $CT.LIN_00()))))
prval V_light_18: VEILED(PaletteLight, 18) = VEILEDc(
  SHADEDc(PAL0_fg(), PAL0_bg(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_22(), $CT.LIN_22(), $CT.LIN_22()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_cd(), $CT.LIN_cb(), $CT.LIN_c9()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_22(), $CT.LIN_22(), $CT.LIN_22()), $CT.LUMc($CT.LIN_cd(), $CT.LIN_cb(), $CT.LIN_c9()))),
  SHADEDc(PAL0_accent(), PAL0_bg(),
    SHADEc($CT.LIN_2f(), $CT.LIN_6f(), $CT.LIN_4f(), $CT.LIN_27(), $CT.LIN_5b(), $CT.LIN_41()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_cd(), $CT.LIN_cb(), $CT.LIN_c9()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_27(), $CT.LIN_5b(), $CT.LIN_41()), $CT.LUMc($CT.LIN_cd(), $CT.LIN_cb(), $CT.LIN_c9()))),
  SHADEDc(PAL0_fg(), PAL0_hl(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_22(), $CT.LIN_22(), $CT.LIN_22()),
    SHADEc($CT.LIN_fd(), $CT.LIN_e5(), $CT.LIN_9a(), $CT.LIN_cf(), $CT.LIN_bc(), $CT.LIN_7e()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_22(), $CT.LIN_22(), $CT.LIN_22()), $CT.LUMc($CT.LIN_cf(), $CT.LIN_bc(), $CT.LIN_7e()))),
  SHADEDc(PAL0_fg(), PAL0_hl2(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_22(), $CT.LIN_22(), $CT.LIN_22()),
    SHADEc($CT.LIN_fb(), $CT.LIN_c5(), $CT.LIN_8a(), $CT.LIN_ce(), $CT.LIN_a2(), $CT.LIN_71()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_22(), $CT.LIN_22(), $CT.LIN_22()), $CT.LUMc($CT.LIN_ce(), $CT.LIN_a2(), $CT.LIN_71()))),
  SHADEDc(PAL0_markfg(), PAL0_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_d1(), $CT.LIN_93(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_d1(), $CT.LIN_93(), $CT.LIN_00()))))
prval V_light_24: VEILED(PaletteLight, 24) = VEILEDc(
  SHADEDc(PAL0_fg(), PAL0_bg(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_20(), $CT.LIN_20(), $CT.LIN_20()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_be(), $CT.LIN_bc(), $CT.LIN_ba()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_20(), $CT.LIN_20(), $CT.LIN_20()), $CT.LUMc($CT.LIN_be(), $CT.LIN_bc(), $CT.LIN_ba()))),
  SHADEDc(PAL0_accent(), PAL0_bg(),
    SHADEc($CT.LIN_2f(), $CT.LIN_6f(), $CT.LIN_4f(), $CT.LIN_24(), $CT.LIN_54(), $CT.LIN_3c()),
    SHADEc($CT.LIN_fa(), $CT.LIN_f8(), $CT.LIN_f5(), $CT.LIN_be(), $CT.LIN_bc(), $CT.LIN_ba()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_24(), $CT.LIN_54(), $CT.LIN_3c()), $CT.LUMc($CT.LIN_be(), $CT.LIN_bc(), $CT.LIN_ba()))),
  SHADEDc(PAL0_fg(), PAL0_hl(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_20(), $CT.LIN_20(), $CT.LIN_20()),
    SHADEc($CT.LIN_fd(), $CT.LIN_e5(), $CT.LIN_9a(), $CT.LIN_c0(), $CT.LIN_ae(), $CT.LIN_75()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_20(), $CT.LIN_20(), $CT.LIN_20()), $CT.LUMc($CT.LIN_c0(), $CT.LIN_ae(), $CT.LIN_75()))),
  SHADEDc(PAL0_fg(), PAL0_hl2(),
    SHADEc($CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_2a(), $CT.LIN_20(), $CT.LIN_20(), $CT.LIN_20()),
    SHADEc($CT.LIN_fb(), $CT.LIN_c5(), $CT.LIN_8a(), $CT.LIN_bf(), $CT.LIN_96(), $CT.LIN_69()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_20(), $CT.LIN_20(), $CT.LIN_20()), $CT.LUMc($CT.LIN_bf(), $CT.LIN_96(), $CT.LIN_69()))),
  SHADEDc(PAL0_markfg(), PAL0_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_c2(), $CT.LIN_88(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_c2(), $CT.LIN_88(), $CT.LIN_00()))))
prval V_sepia_5: VEILED(PaletteSepia, 5) = VEILEDc(
  SHADEDc(PAL1_fg(), PAL1_bg(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_38(), $CT.LIN_2d(), $CT.LIN_20()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_e4(), $CT.LIN_db(), $CT.LIN_c8()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_38(), $CT.LIN_2d(), $CT.LIN_20()), $CT.LUMc($CT.LIN_e4(), $CT.LIN_db(), $CT.LIN_c8()))),
  SHADEDc(PAL1_accent(), PAL1_bg(),
    SHADEc($CT.LIN_7a(), $CT.LIN_4f(), $CT.LIN_1d(), $CT.LIN_74(), $CT.LIN_4b(), $CT.LIN_1c()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_e4(), $CT.LIN_db(), $CT.LIN_c8()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_74(), $CT.LIN_4b(), $CT.LIN_1c()), $CT.LUMc($CT.LIN_e4(), $CT.LIN_db(), $CT.LIN_c8()))),
  SHADEDc(PAL1_fg(), PAL1_hl(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_38(), $CT.LIN_2d(), $CT.LIN_20()),
    SHADEc($CT.LIN_e6(), $CT.LIN_cf(), $CT.LIN_8a(), $CT.LIN_db(), $CT.LIN_c5(), $CT.LIN_83()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_38(), $CT.LIN_2d(), $CT.LIN_20()), $CT.LUMc($CT.LIN_db(), $CT.LIN_c5(), $CT.LIN_83()))),
  SHADEDc(PAL1_fg(), PAL1_hl2(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_38(), $CT.LIN_2d(), $CT.LIN_20()),
    SHADEc($CT.LIN_e8(), $CT.LIN_b8(), $CT.LIN_80(), $CT.LIN_dc(), $CT.LIN_af(), $CT.LIN_7a()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_38(), $CT.LIN_2d(), $CT.LIN_20()), $CT.LUMc($CT.LIN_dc(), $CT.LIN_af(), $CT.LIN_7a()))),
  SHADEDc(PAL1_markfg(), PAL1_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_f2(), $CT.LIN_aa(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_f2(), $CT.LIN_aa(), $CT.LIN_00()))))
prval V_sepia_10: VEILED(PaletteSepia, 10) = VEILEDc(
  SHADEDc(PAL1_fg(), PAL1_bg(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_35(), $CT.LIN_2a(), $CT.LIN_1f()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_d8(), $CT.LIN_cf(), $CT.LIN_bd()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_35(), $CT.LIN_2a(), $CT.LIN_1f()), $CT.LUMc($CT.LIN_d8(), $CT.LIN_cf(), $CT.LIN_bd()))),
  SHADEDc(PAL1_accent(), PAL1_bg(),
    SHADEc($CT.LIN_7a(), $CT.LIN_4f(), $CT.LIN_1d(), $CT.LIN_6e(), $CT.LIN_47(), $CT.LIN_1a()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_d8(), $CT.LIN_cf(), $CT.LIN_bd()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_6e(), $CT.LIN_47(), $CT.LIN_1a()), $CT.LUMc($CT.LIN_d8(), $CT.LIN_cf(), $CT.LIN_bd()))),
  SHADEDc(PAL1_fg(), PAL1_hl(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_35(), $CT.LIN_2a(), $CT.LIN_1f()),
    SHADEc($CT.LIN_e6(), $CT.LIN_cf(), $CT.LIN_8a(), $CT.LIN_cf(), $CT.LIN_ba(), $CT.LIN_7c()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_35(), $CT.LIN_2a(), $CT.LIN_1f()), $CT.LUMc($CT.LIN_cf(), $CT.LIN_ba(), $CT.LIN_7c()))),
  SHADEDc(PAL1_fg(), PAL1_hl2(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_35(), $CT.LIN_2a(), $CT.LIN_1f()),
    SHADEc($CT.LIN_e8(), $CT.LIN_b8(), $CT.LIN_80(), $CT.LIN_d1(), $CT.LIN_a6(), $CT.LIN_73()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_35(), $CT.LIN_2a(), $CT.LIN_1f()), $CT.LUMc($CT.LIN_d1(), $CT.LIN_a6(), $CT.LIN_73()))),
  SHADEDc(PAL1_markfg(), PAL1_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_e6(), $CT.LIN_a1(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_e6(), $CT.LIN_a1(), $CT.LIN_00()))))
prval V_sepia_15: VEILED(PaletteSepia, 15) = VEILEDc(
  SHADEDc(PAL1_fg(), PAL1_bg(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_32(), $CT.LIN_28(), $CT.LIN_1d()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_cc(), $CT.LIN_c4(), $CT.LIN_b3()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_32(), $CT.LIN_28(), $CT.LIN_1d()), $CT.LUMc($CT.LIN_cc(), $CT.LIN_c4(), $CT.LIN_b3()))),
  SHADEDc(PAL1_accent(), PAL1_bg(),
    SHADEc($CT.LIN_7a(), $CT.LIN_4f(), $CT.LIN_1d(), $CT.LIN_68(), $CT.LIN_43(), $CT.LIN_19()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_cc(), $CT.LIN_c4(), $CT.LIN_b3()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_68(), $CT.LIN_43(), $CT.LIN_19()), $CT.LUMc($CT.LIN_cc(), $CT.LIN_c4(), $CT.LIN_b3()))),
  SHADEDc(PAL1_fg(), PAL1_hl(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_32(), $CT.LIN_28(), $CT.LIN_1d()),
    SHADEc($CT.LIN_e6(), $CT.LIN_cf(), $CT.LIN_8a(), $CT.LIN_c4(), $CT.LIN_b0(), $CT.LIN_75()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_32(), $CT.LIN_28(), $CT.LIN_1d()), $CT.LUMc($CT.LIN_c4(), $CT.LIN_b0(), $CT.LIN_75()))),
  SHADEDc(PAL1_fg(), PAL1_hl2(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_32(), $CT.LIN_28(), $CT.LIN_1d()),
    SHADEc($CT.LIN_e8(), $CT.LIN_b8(), $CT.LIN_80(), $CT.LIN_c5(), $CT.LIN_9c(), $CT.LIN_6d()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_32(), $CT.LIN_28(), $CT.LIN_1d()), $CT.LUMc($CT.LIN_c5(), $CT.LIN_9c(), $CT.LIN_6d()))),
  SHADEDc(PAL1_markfg(), PAL1_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_d9(), $CT.LIN_98(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_d9(), $CT.LIN_98(), $CT.LIN_00()))))
prval V_sepia_20: VEILED(PaletteSepia, 20) = VEILEDc(
  SHADEDc(PAL1_fg(), PAL1_bg(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_2f(), $CT.LIN_26(), $CT.LIN_1b()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_c0(), $CT.LIN_b8(), $CT.LIN_a8()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_2f(), $CT.LIN_26(), $CT.LIN_1b()), $CT.LUMc($CT.LIN_c0(), $CT.LIN_b8(), $CT.LIN_a8()))),
  SHADEDc(PAL1_accent(), PAL1_bg(),
    SHADEc($CT.LIN_7a(), $CT.LIN_4f(), $CT.LIN_1d(), $CT.LIN_62(), $CT.LIN_3f(), $CT.LIN_17()),
    SHADEc($CT.LIN_f0(), $CT.LIN_e6(), $CT.LIN_d2(), $CT.LIN_c0(), $CT.LIN_b8(), $CT.LIN_a8()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_62(), $CT.LIN_3f(), $CT.LIN_17()), $CT.LUMc($CT.LIN_c0(), $CT.LIN_b8(), $CT.LIN_a8()))),
  SHADEDc(PAL1_fg(), PAL1_hl(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_2f(), $CT.LIN_26(), $CT.LIN_1b()),
    SHADEc($CT.LIN_e6(), $CT.LIN_cf(), $CT.LIN_8a(), $CT.LIN_b8(), $CT.LIN_a6(), $CT.LIN_6e()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_2f(), $CT.LIN_26(), $CT.LIN_1b()), $CT.LUMc($CT.LIN_b8(), $CT.LIN_a6(), $CT.LIN_6e()))),
  SHADEDc(PAL1_fg(), PAL1_hl2(),
    SHADEc($CT.LIN_3b(), $CT.LIN_2f(), $CT.LIN_22(), $CT.LIN_2f(), $CT.LIN_26(), $CT.LIN_1b()),
    SHADEc($CT.LIN_e8(), $CT.LIN_b8(), $CT.LIN_80(), $CT.LIN_ba(), $CT.LIN_93(), $CT.LIN_66()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_2f(), $CT.LIN_26(), $CT.LIN_1b()), $CT.LUMc($CT.LIN_ba(), $CT.LIN_93(), $CT.LIN_66()))),
  SHADEDc(PAL1_markfg(), PAL1_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_cc(), $CT.LIN_8f(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_cc(), $CT.LIN_8f(), $CT.LIN_00()))))
prval V_dark_2: VEILED(PaletteDark, 2) = VEILEDc(
  SHADEDc(PAL2_fg(), PAL2_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()), $CT.LUMc($CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()))),
  SHADEDc(PAL2_accent(), PAL2_bg(),
    SHADEc($CT.LIN_7f(), $CT.LIN_c4(), $CT.LIN_9b(), $CT.LIN_7c(), $CT.LIN_c0(), $CT.LIN_98()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_7c(), $CT.LIN_c0(), $CT.LIN_98()), $CT.LUMc($CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()))),
  SHADEDc(PAL2_fg(), PAL2_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_6b(), $CT.LIN_5c(), $CT.LIN_2e()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()), $CT.LUMc($CT.LIN_6b(), $CT.LIN_5c(), $CT.LIN_2e()))),
  SHADEDc(PAL2_fg(), PAL2_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_79(), $CT.LIN_56(), $CT.LIN_30()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()), $CT.LUMc($CT.LIN_79(), $CT.LIN_56(), $CT.LIN_30()))),
  SHADEDc(PAL2_markfg(), PAL2_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_fa(), $CT.LIN_af(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_fa(), $CT.LIN_af(), $CT.LIN_00()))))
prval V_dark_4: VEILED(PaletteDark, 4) = VEILEDc(
  SHADEDc(PAL2_fg(), PAL2_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()), $CT.LUMc($CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()))),
  SHADEDc(PAL2_accent(), PAL2_bg(),
    SHADEc($CT.LIN_7f(), $CT.LIN_c4(), $CT.LIN_9b(), $CT.LIN_7a(), $CT.LIN_bc(), $CT.LIN_95()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_7a(), $CT.LIN_bc(), $CT.LIN_95()), $CT.LUMc($CT.LIN_1d(), $CT.LIN_1d(), $CT.LIN_1d()))),
  SHADEDc(PAL2_fg(), PAL2_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_69(), $CT.LIN_5a(), $CT.LIN_2d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()), $CT.LUMc($CT.LIN_69(), $CT.LIN_5a(), $CT.LIN_2d()))),
  SHADEDc(PAL2_fg(), PAL2_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_76(), $CT.LIN_54(), $CT.LIN_2f()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()), $CT.LUMc($CT.LIN_76(), $CT.LIN_54(), $CT.LIN_2f()))),
  SHADEDc(PAL2_markfg(), PAL2_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_f5(), $CT.LIN_ac(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_f5(), $CT.LIN_ac(), $CT.LIN_00()))))
prval V_dark_6: VEILED(PaletteDark, 6) = VEILEDc(
  SHADEDc(PAL2_fg(), PAL2_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()), $CT.LUMc($CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()))),
  SHADEDc(PAL2_accent(), PAL2_bg(),
    SHADEc($CT.LIN_7f(), $CT.LIN_c4(), $CT.LIN_9b(), $CT.LIN_77(), $CT.LIN_b8(), $CT.LIN_92()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_77(), $CT.LIN_b8(), $CT.LIN_92()), $CT.LUMc($CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()))),
  SHADEDc(PAL2_fg(), PAL2_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_66(), $CT.LIN_58(), $CT.LIN_2c()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()), $CT.LUMc($CT.LIN_66(), $CT.LIN_58(), $CT.LIN_2c()))),
  SHADEDc(PAL2_fg(), PAL2_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_74(), $CT.LIN_53(), $CT.LIN_2e()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()), $CT.LUMc($CT.LIN_74(), $CT.LIN_53(), $CT.LIN_2e()))),
  SHADEDc(PAL2_markfg(), PAL2_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_f0(), $CT.LIN_a8(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_f0(), $CT.LIN_a8(), $CT.LIN_00()))))
prval V_dark_8: VEILED(PaletteDark, 8) = VEILEDc(
  SHADEDc(PAL2_fg(), PAL2_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()), $CT.LUMc($CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()))),
  SHADEDc(PAL2_accent(), PAL2_bg(),
    SHADEc($CT.LIN_7f(), $CT.LIN_c4(), $CT.LIN_9b(), $CT.LIN_75(), $CT.LIN_b4(), $CT.LIN_8f()),
    SHADEc($CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1e(), $CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_75(), $CT.LIN_b4(), $CT.LIN_8f()), $CT.LUMc($CT.LIN_1c(), $CT.LIN_1c(), $CT.LIN_1c()))),
  SHADEDc(PAL2_fg(), PAL2_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_64(), $CT.LIN_56(), $CT.LIN_2b()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()), $CT.LUMc($CT.LIN_64(), $CT.LIN_56(), $CT.LIN_2b()))),
  SHADEDc(PAL2_fg(), PAL2_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_71(), $CT.LIN_51(), $CT.LIN_2d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()), $CT.LUMc($CT.LIN_71(), $CT.LIN_51(), $CT.LIN_2d()))),
  SHADEDc(PAL2_markfg(), PAL2_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_eb(), $CT.LIN_a5(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_eb(), $CT.LIN_a5(), $CT.LIN_00()))))
prval V_night_0: VEILED(PaletteNight, 0) = VEILEDc(
  SHADEDc(PAL3_fg(), PAL3_bg(),
    SHADEc($CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96(), $CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96()),
    SHADEc($CT.LIN_1f(), $CT.LIN_1a(), $CT.LIN_14(), $CT.LIN_1f(), $CT.LIN_1a(), $CT.LIN_14()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96()), $CT.LUMc($CT.LIN_1f(), $CT.LIN_1a(), $CT.LIN_14()))),
  SHADEDc(PAL3_accent(), PAL3_bg(),
    SHADEc($CT.LIN_c9(), $CT.LIN_a3(), $CT.LIN_6b(), $CT.LIN_c9(), $CT.LIN_a3(), $CT.LIN_6b()),
    SHADEc($CT.LIN_1f(), $CT.LIN_1a(), $CT.LIN_14(), $CT.LIN_1f(), $CT.LIN_1a(), $CT.LIN_14()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_c9(), $CT.LIN_a3(), $CT.LIN_6b()), $CT.LUMc($CT.LIN_1f(), $CT.LIN_1a(), $CT.LIN_14()))),
  SHADEDc(PAL3_fg(), PAL3_hl(),
    SHADEc($CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96(), $CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96()),
    SHADEc($CT.LIN_4f(), $CT.LIN_43(), $CT.LIN_18(), $CT.LIN_4f(), $CT.LIN_43(), $CT.LIN_18()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96()), $CT.LUMc($CT.LIN_4f(), $CT.LIN_43(), $CT.LIN_18()))),
  SHADEDc(PAL3_fg(), PAL3_hl2(),
    SHADEc($CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96(), $CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96()),
    SHADEc($CT.LIN_5c(), $CT.LIN_3f(), $CT.LIN_1f(), $CT.LIN_5c(), $CT.LIN_3f(), $CT.LIN_1f()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_c2(), $CT.LIN_b2(), $CT.LIN_96()), $CT.LUMc($CT.LIN_5c(), $CT.LIN_3f(), $CT.LIN_1f()))),
  SHADEDc(PAL3_markfg(), PAL3_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00()))))
prval V_grey_2: VEILED(PaletteGrey, 2) = VEILEDc(
  SHADEDc(PAL4_fg(), PAL4_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_39(), $CT.LIN_39(), $CT.LIN_39()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()), $CT.LUMc($CT.LIN_39(), $CT.LIN_39(), $CT.LIN_39()))),
  SHADEDc(PAL4_accent(), PAL4_bg(),
    SHADEc($CT.LIN_8f(), $CT.LIN_d0(), $CT.LIN_a8(), $CT.LIN_8c(), $CT.LIN_cc(), $CT.LIN_a5()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_39(), $CT.LIN_39(), $CT.LIN_39()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_8c(), $CT.LIN_cc(), $CT.LIN_a5()), $CT.LUMc($CT.LIN_39(), $CT.LIN_39(), $CT.LIN_39()))),
  SHADEDc(PAL4_fg(), PAL4_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_6b(), $CT.LIN_5c(), $CT.LIN_2e()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()), $CT.LUMc($CT.LIN_6b(), $CT.LIN_5c(), $CT.LIN_2e()))),
  SHADEDc(PAL4_fg(), PAL4_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_79(), $CT.LIN_56(), $CT.LIN_30()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_dd(), $CT.LIN_dd(), $CT.LIN_dd()), $CT.LUMc($CT.LIN_79(), $CT.LIN_56(), $CT.LIN_30()))),
  SHADEDc(PAL4_markfg(), PAL4_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_fa(), $CT.LIN_af(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_fa(), $CT.LIN_af(), $CT.LIN_00()))))
prval V_grey_4: VEILED(PaletteGrey, 4) = VEILEDc(
  SHADEDc(PAL4_fg(), PAL4_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_38(), $CT.LIN_38(), $CT.LIN_38()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()), $CT.LUMc($CT.LIN_38(), $CT.LIN_38(), $CT.LIN_38()))),
  SHADEDc(PAL4_accent(), PAL4_bg(),
    SHADEc($CT.LIN_8f(), $CT.LIN_d0(), $CT.LIN_a8(), $CT.LIN_89(), $CT.LIN_c8(), $CT.LIN_a1()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_38(), $CT.LIN_38(), $CT.LIN_38()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_89(), $CT.LIN_c8(), $CT.LIN_a1()), $CT.LUMc($CT.LIN_38(), $CT.LIN_38(), $CT.LIN_38()))),
  SHADEDc(PAL4_fg(), PAL4_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_69(), $CT.LIN_5a(), $CT.LIN_2d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()), $CT.LUMc($CT.LIN_69(), $CT.LIN_5a(), $CT.LIN_2d()))),
  SHADEDc(PAL4_fg(), PAL4_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_76(), $CT.LIN_54(), $CT.LIN_2f()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d9(), $CT.LIN_d9(), $CT.LIN_d9()), $CT.LUMc($CT.LIN_76(), $CT.LIN_54(), $CT.LIN_2f()))),
  SHADEDc(PAL4_markfg(), PAL4_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_f5(), $CT.LIN_ac(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_f5(), $CT.LIN_ac(), $CT.LIN_00()))))
prval V_grey_6: VEILED(PaletteGrey, 6) = VEILEDc(
  SHADEDc(PAL4_fg(), PAL4_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_37(), $CT.LIN_37(), $CT.LIN_37()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()), $CT.LUMc($CT.LIN_37(), $CT.LIN_37(), $CT.LIN_37()))),
  SHADEDc(PAL4_accent(), PAL4_bg(),
    SHADEc($CT.LIN_8f(), $CT.LIN_d0(), $CT.LIN_a8(), $CT.LIN_86(), $CT.LIN_c4(), $CT.LIN_9e()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_37(), $CT.LIN_37(), $CT.LIN_37()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_86(), $CT.LIN_c4(), $CT.LIN_9e()), $CT.LUMc($CT.LIN_37(), $CT.LIN_37(), $CT.LIN_37()))),
  SHADEDc(PAL4_fg(), PAL4_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_66(), $CT.LIN_58(), $CT.LIN_2c()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()), $CT.LUMc($CT.LIN_66(), $CT.LIN_58(), $CT.LIN_2c()))),
  SHADEDc(PAL4_fg(), PAL4_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_74(), $CT.LIN_53(), $CT.LIN_2e()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d4(), $CT.LIN_d4(), $CT.LIN_d4()), $CT.LUMc($CT.LIN_74(), $CT.LIN_53(), $CT.LIN_2e()))),
  SHADEDc(PAL4_markfg(), PAL4_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_f0(), $CT.LIN_a8(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_f0(), $CT.LIN_a8(), $CT.LIN_00()))))
prval V_grey_8: VEILED(PaletteGrey, 8) = VEILEDc(
  SHADEDc(PAL4_fg(), PAL4_bg(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_35(), $CT.LIN_35(), $CT.LIN_35()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()), $CT.LUMc($CT.LIN_35(), $CT.LIN_35(), $CT.LIN_35()))),
  SHADEDc(PAL4_accent(), PAL4_bg(),
    SHADEc($CT.LIN_8f(), $CT.LIN_d0(), $CT.LIN_a8(), $CT.LIN_84(), $CT.LIN_bf(), $CT.LIN_9b()),
    SHADEc($CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_3a(), $CT.LIN_35(), $CT.LIN_35(), $CT.LIN_35()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_84(), $CT.LIN_bf(), $CT.LIN_9b()), $CT.LUMc($CT.LIN_35(), $CT.LIN_35(), $CT.LIN_35()))),
  SHADEDc(PAL4_fg(), PAL4_hl(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()),
    SHADEc($CT.LIN_6d(), $CT.LIN_5e(), $CT.LIN_2f(), $CT.LIN_64(), $CT.LIN_56(), $CT.LIN_2b()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()), $CT.LUMc($CT.LIN_64(), $CT.LIN_56(), $CT.LIN_2b()))),
  SHADEDc(PAL4_fg(), PAL4_hl2(),
    SHADEc($CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_e2(), $CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()),
    SHADEc($CT.LIN_7b(), $CT.LIN_58(), $CT.LIN_31(), $CT.LIN_71(), $CT.LIN_51(), $CT.LIN_2d()),
    $CT.CONTRAST_lighter_first($CT.LUMc($CT.LIN_d0(), $CT.LIN_d0(), $CT.LIN_d0()), $CT.LUMc($CT.LIN_71(), $CT.LIN_51(), $CT.LIN_2d()))),
  SHADEDc(PAL4_markfg(), PAL4_mark(),
    SHADEc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()),
    SHADEc($CT.LIN_ff(), $CT.LIN_b3(), $CT.LIN_00(), $CT.LIN_eb(), $CT.LIN_a5(), $CT.LIN_00()),
    $CT.CONTRAST_lighter_second($CT.LUMc($CT.LIN_00(), $CT.LIN_00(), $CT.LIN_00()), $CT.LUMc($CT.LIN_eb(), $CT.LIN_a5(), $CT.LIN_00()))))
(* END proofs *)

(* ============================================================
   The sheet: a builder with a budget of bytes left, so the whole
   sheet is proven to fit the style element (under 65536 bytes); and
   whether a rule or an @media block is open
   ============================================================ *)

stadef BUDGET = 60000

(* sheet(left, media, open): left bytes left; whether an @media block is
   open, and whether a rule is *)
datavtype sheet(int, bool, bool) =
  | {written,left:nat | written + left <= BUDGET}{media,open:bool} Sheet(left, media, open) of ($B.builder(written))

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
fn plain {left:nat}{media,open:bool}{length:nat | length <= left}
  (sheet: !sheet(left, media, open) >> sheet(left - length, media, open), text: string length): void = let
  val+ @Sheet(builder) = sheet
  val () = _put_plain(builder, text, g1u2i(string1_length(text)), 0)
  prval () = fold@(sheet)
in end

(* text as written: only this module's fixed text *)
fn raw {left:nat}{media,open:bool}{length:nat | length <= left}
  (sheet: !sheet(left, media, open) >> sheet(left - length, media, open), text: string length): void = let
  val+ @Sheet(builder) = sheet
  val () = $B.bput(builder, text)
  prval () = fold@(sheet)
in end

fn _colour {left:nat | left >= 7}{media,open:bool}{colour:nat | colour < 16777216}
  (sheet: !sheet(left, media, open) >> sheet(left - 7, media, open), colour: int colour): void = let
  val+ @Sheet(builder) = sheet
  val () = $CT.put_rgb(builder, colour)
  prval () = fold@(sheet)
in end

(* a small number (at most 11 bytes) *)
fn _number {left:nat | left >= 11}{media,open:bool}
  (sheet: sheet(left, media, open), value: int): sheet(left - 11, media, open) = let
  val+ ~Sheet(builder) = sheet
  val () = $B.put_int(builder, value)
in Sheet(builder) end

fn _role_name {role:colour_role} (role: role_value(role)): [length:pos | length <= 9] string length =
  case+ role of
  | RoleGround() => "bg"
  | RoleText() => "fg"
  | RoleMuted() => "muted"
  | RoleCard() => "card"
  | RoleLine() => "line"
  | RoleEdge() => "edge"
  | RoleBar() => "bar"
  | RoleBarText() => "barfg"
  | RoleAccent() => "accent"
  | RoleAccentText() => "accentfg"
  | RoleHighlight() => "hl"
  | RoleBarHigh() => "barhi"
  | RoleBanner() => "banner"
  | RoleBannerText() => "bannerfg"
  | RoleMark() => "mark"
  | RoleMarkText() => "markfg"
  | RoleDanger() => "danger"
  | RoleSecondHighlight() => "hl2"

(* var(--<role>) *)
fn _role_variable {left:nat | left >= 16}{media,open:bool}{role:colour_role}
  (sheet: !sheet(left, media, open) >> [after:nat | after >= left - 16] sheet(after, media, open), role: role_value(role)): void = let
  val () = raw(sheet, "var(--")
  val () = raw(sheet, _role_name(role))
in raw(sheet, ")") end

(* ============================================================
   Rules
   ============================================================ *)


(* selector { *)
fn rule {left:nat}{media:bool}{length:nat | length + 1 <= left}
  (sheet: sheet(left, media, false), selector: string length): sheet(left - length - 1, media, true) = let
  val () = plain(sheet, selector)
  val () = raw(sheet, "{")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

(* } *)
fn close {left:pos}{media:bool}
  (sheet: sheet(left, media, true)): sheet(left - 1, media, false) = let
  val () = raw(sheet, "}")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

(* @media condition { *)
fn media {left:nat}{length:nat | length + 8 <= left}
  (sheet: sheet(left, false, false), condition: string length): sheet(left - length - 8, true, false) = let
  val () = raw(sheet, "@media ")
  val () = plain(sheet, condition)
  val () = raw(sheet, "{")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

fn media_end {left:pos} (sheet: sheet(left, true, false)): sheet(left - 1, false, false) = let
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
  | Margin | MarginTop | MarginBottom | MarginLeft | MarginRight | MarginBlock | MarginInline
  | Width | MaxWidth | MinWidth | Height | MaxHeight | MinHeight | BoxSizing
  | FontFamily | FontSize | FontWeight | FontStyle | Font | LineHeight
  | LetterSpacing | TextTransform | TextAlign | TextOverflow | TextDecoration
  | WhiteSpace | Hyphens | Direction | WritingMode
  | Overflow | OverflowX | Position | Top | Bottom | Left | Right | Inset
  | ZIndex | Cursor | PointerEvents | TouchAction | ObjectFit
  | BorderRadius | BorderCollapse | BoxShadow | Outline | OutlineOffset
  | ColumnFill | ColumnGap | ColumnWidth | BreakAfter | BreakInside | GridTemplate | AspectRatio
  | Appearance | ContainerType | UserSelect | Transition | Visibility | GridArea
  (* the reader's own variables: the page's top and bottom paddings and
     the running footer's place, each given once (_reader) *)
  | PageTopVariable | PageBottomVariable | FooterBottomVariable | FooterHeightVariable

fn _property_name (property: prop): [length:pos | length <= 16] string length =
  case+ property of
  | Display() => "display" | FlexDirection() => "flex-direction" | Flex() => "flex"
  | FlexWrap() => "flex-wrap" | FlexBasis() => "flex-basis" | AlignItems() => "align-items"
  | AlignSelf() => "align-self" | JustifyContent() => "justify-content" | Gap() => "gap"
  | Order() => "order" | Padding() => "padding" | PaddingTop() => "padding-top"
  | PaddingBottom() => "padding-bottom" | PaddingLeft() => "padding-left"
  | PaddingRight() => "padding-right" | Margin() => "margin" | MarginTop() => "margin-top"
  | MarginBottom() => "margin-bottom" | MarginLeft() => "margin-left"
  | MarginRight() => "margin-right" | MarginBlock() => "margin-block"
  | MarginInline() => "margin-inline" | Width() => "width" | MaxWidth() => "max-width"
  | MinWidth() => "min-width" | Height() => "height" | MaxHeight() => "max-height"
  | MinHeight() => "min-height" | BoxSizing() => "box-sizing" | FontFamily() => "font-family"
  | FontSize() => "font-size" | FontWeight() => "font-weight" | FontStyle() => "font-style"
  | Font() => "font" | LineHeight() => "line-height" | LetterSpacing() => "letter-spacing"
  | TextTransform() => "text-transform" | TextAlign() => "text-align"
  | TextOverflow() => "text-overflow" | TextDecoration() => "text-decoration"
  | WhiteSpace() => "white-space" | Hyphens() => "hyphens" | Direction() => "direction"
  | WritingMode() => "writing-mode"
  | Overflow() => "overflow" | OverflowX() => "overflow-x" | Position() => "position"
  | Top() => "top" | Bottom() => "bottom" | Left() => "left" | Right() => "right"
  | Inset() => "inset" | ZIndex() => "z-index" | Cursor() => "cursor"
  | PointerEvents() => "pointer-events" | TouchAction() => "touch-action"
  | ObjectFit() => "object-fit" | BorderRadius() => "border-radius"
  | BorderCollapse() => "border-collapse" | BoxShadow() => "box-shadow"
  | Outline() => "outline" | OutlineOffset() => "outline-offset"
  | ColumnFill() => "column-fill" | ColumnGap() => "column-gap"
  | ColumnWidth() => "column-width" | BreakAfter() => "break-after"
  | BreakInside() => "break-inside" | Appearance() => "appearance" | ContainerType() => "container-type" | UserSelect() => "user-select"
  | Transition() => "transition" | Visibility() => "visibility"
  | GridTemplate() => "grid-template" | AspectRatio() => "aspect-ratio"
  | GridArea() => "grid-area"
  | PageTopVariable() => "--page-top" | PageBottomVariable() => "--page-bottom"
  | FooterBottomVariable() => "--footer-bottom" | FooterHeightVariable() => "--footer-height"

(* prop:value; *)
fn lay {left:nat}{media:bool}{value_len:nat | value_len + 18 <= left}
  (sheet: sheet(left, media, true), property: prop, value: string value_len): [after:nat | after >= left - value_len - 18] sheet(after, media, true) = let
  val () = raw(sheet, _property_name(property))
  val () = raw(sheet, ":")
  val () = plain(sheet, value)
  val () = raw(sheet, ";")
in sheet end

(* ============================================================
   The spacing scale (#331): Material's grid (8 px between and around
   components, 4 px within them; 16 px a compact screen's margins and a
   list item's insets, 24 px a dialog's), one length a step. The
   paddings, margins and gaps of the screens, sheets, menus and dialogs
   are written from it (spaced, spaced_pair), not chosen rule by rule.
   A step is indexed by its length, so a rule can be asked to prove a
   length at least the least inset (#332 builds on it)
   ============================================================ *)

#pub datatype space(int) =
  | SpaceTight(4) of ()
  | SpaceSmall(8) of ()
  | SpaceMedium(12) of ()
  | SpaceLarge(16) of ()
  | SpaceExtraLarge(24) of ()

(* The least a control keeps from its container's edges: Material's
   least space between two targets. The page gives it as --space-inset
   (_spacing), which the e2e layout walk checks every control against *)
stadef SPACE_INSET = 8

(* The step that is the least inset: a step of another length does not
   type-check here *)
fn space_inset (): space(SPACE_INSET) = SpaceSmall()

fn _space_length {length:int} (step: space(length)): [text_len:pos | text_len <= 4] string text_len =
  case+ step of
  | SpaceTight() => "4px"
  | SpaceSmall() => "8px"
  | SpaceMedium() => "12px"
  | SpaceLarge() => "16px"
  | SpaceExtraLarge() => "24px"

(* prop:<step>; *)
fn spaced {left:nat | left >= 22}{media:bool}{length:int}
  (sheet: sheet(left, media, true), property: prop, step: space(length)): [after:nat | after >= left - 22] sheet(after, media, true) =
  lay(sheet, property, _space_length(step))

(* prop:<block> <inline>; (the top and bottom, then the sides) *)
fn spaced_pair {left:nat | left >= 28}{media:bool}{block,inline:int}
  (sheet: sheet(left, media, true), property: prop, block: space(block), inline: space(inline)): [after:nat | after >= left - 28] sheet(after, media, true) = let
  val () = raw(sheet, _property_name(property))
  val () = raw(sheet, ":")
  val () = raw(sheet, _space_length(block))
  val () = raw(sheet, " ")
  val () = raw(sheet, _space_length(inline))
  val () = raw(sheet, ";")
in sheet end

(* color:var(--text);background-color:var(--ground); : text on ground,
   proven *)
fn surf {left:nat | left >= 60}{media:bool}{text,ground:colour_role}
  (legible: SURF(text, ground) | sheet: sheet(left, media, true), text: role_value(text), ground: role_value(ground)): [after:nat | after >= left - 60] sheet(after, media, true) = let
  val () = raw(sheet, "color:")
  val () = _role_variable(sheet, text)
  val () = raw(sheet, ";background-color:")
  val () = _role_variable(sheet, ground)
  val () = raw(sheet, ";")
in sheet end

(* A ground with no text: a bar, a track, a placeholder *)
fn fill {left:nat | left >= 50}{media:bool}{ground:colour_role}
  (sheet: sheet(left, media, true), ground: role_value(ground)): [after:nat | after >= left - 50] sheet(after, media, true) = let
  val () = raw(sheet, "background-color:")
  val () = _role_variable(sheet, ground)
  val () = raw(sheet, ";font-size:0;")
in sheet end

(* A ground of white or black at alpha percent, with no text *)
fn tint {left:nat | left >= 60}{media:bool}{alpha:nat | alpha <= 100}
  (sheet: sheet(left, media, true), white: bool, alpha: int alpha): [after:nat | after >= left - 60] sheet(after, media, true) = let
  val () = raw(sheet, (if white then "background-color:rgba(255,255,255," else "background-color:rgba(0,0,0,"): [length:pos | length <= 34] string length)
  val sheet = _number(sheet, alpha)
  val () = raw(sheet, "%);font-size:0;")
in sheet end

(* The veil behind a menu or dialog: dark, and its own text (none)
   transparent, so only what sits on it in a proven surface shows *)
fn veil {left:nat | left >= 60}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 60] sheet(after, media, true) =
  let val () = raw(sheet, "background-color:rgba(0,0,0,.5);color:transparent;") in sheet end

(* A decorative line in a role (a card's outline, a separator): not
   what identifies a control, which the base rules give text fields *)
#pub datatype side = AllSides | TopSide | BottomSide | LeftSide

fn line {left:nat | left >= 60}{media:bool}{width:pos | width <= 9}{role:colour_role}
  (sheet: sheet(left, media, true), side: side, width: int width, role: role_value(role)): [after:nat | after >= left - 60] sheet(after, media, true) = let
  val () = raw(sheet, (case+ side of AllSides() => "border:" | TopSide() => "border-top:"
    | BottomSide() => "border-bottom:" | LeftSide() => "border-left:"): [length:pos | length <= 14] string length)
  val sheet = _number(sheet, width)
  val () = raw(sheet, "px solid ")
  val () = _role_variable(sheet, role)
  val () = raw(sheet, ";")
in sheet end

fn no_line {left:nat | left >= 12}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 12] sheet(after, media, true) =
  let val () = raw(sheet, "border:none;") in sheet end

(* A control's accent (a slider's fill and thumb) in role edge on
   ground *)
fn accent {left:nat | left >= 40}{media:bool}{edge,ground:colour_role}
  (visible: EDGEP(edge, ground) | sheet: sheet(left, media, true), edge: role_value(edge), ground: role_value(ground)): [after:nat | after >= left - 40] sheet(after, media, true) = let
  val () = raw(sheet, "accent-color:")
  val () = _role_variable(sheet, edge)
  val () = raw(sheet, ";")
in sheet end

(* A chosen state's underline (a selected tab's) in role edge on ground:
   a 3px inset line along the foot, 3:1 against the ground (EDGEP, as an
   accent), so a chosen state is told apart by more than a tint
   (quire#358, WCAG 1.4.11; Material 3: an underline and a colour change
   on the active tab) *)
fn underline {left:nat | left >= 48}{media:bool}{edge,ground:colour_role}
  (visible: EDGEP(edge, ground) | sheet: sheet(left, media, true), edge: role_value(edge), ground: role_value(ground)): [after:nat | after >= left - 48] sheet(after, media, true) = let
  val () = raw(sheet, "box-shadow:inset 0 -3px 0 ")
  val () = _role_variable(sheet, edge)
  val () = raw(sheet, ";")
in sheet end

(* translateX(-50%): the only transform, which moves and never scales *)
fn centre_x {left:nat | left >= 32}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 32] sheet(after, media, true) =
  let val () = raw(sheet, "transform:translateX(-50%);") in sheet end

(* opacity 0: an invisible target over a visible one (a file input) *)
fn invisible {left:nat | left >= 12}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 12] sheet(after, media, true) =
  let val () = raw(sheet, "opacity:0;") in sheet end

(* ============================================================
   The themes and the base rules
   ============================================================ *)

fn _declare_role {left:nat | left >= 30}{role:colour_role}{colour:nat | colour < 16777216}
  (sheet: sheet(left, false, true), role: role_value(role), colour: int colour): [after:nat | after >= left - 30] sheet(after, false, true) = let
  val () = raw(sheet, "--")
  val () = raw(sheet, _role_name(role))
  val () = raw(sheet, ":")
  val () = _colour(sheet, colour)
  val () = raw(sheet, ";")
in sheet end

(* .th-<name>{--role:#rrggbb;...} for a theme: each colour is the one
   PAL gives, so the proofs above are about these *)
fn theme {theme_number:palette}{left:nat | left >= 740}
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
   sheet: sheet(left, false, false), which: palette_theme(theme_number),
   bg_colour: int bg_colour, fg_colour: int fg_colour, muted_colour: int muted_colour,
   card_colour: int card_colour, line_colour: int line_colour, edge_colour: int edge_colour,
   bar_colour: int bar_colour, barfg_colour: int barfg_colour, accent_colour: int accent_colour,
   accentfg_colour: int accentfg_colour, hl_colour: int hl_colour, barhi_colour: int barhi_colour,
   banner_colour: int banner_colour, bannerfg_colour: int bannerfg_colour, mark_colour: int mark_colour,
   markfg_colour: int markfg_colour, danger_colour: int danger_colour, hl2_colour: int hl2_colour): [after:nat | after >= left - 740] sheet(after, false, false) = let
  val sheet = rule(sheet, _theme_selector(which))
  val sheet = _declare_role(sheet, RoleGround(), bg_colour)
  val sheet = _declare_role(sheet, RoleText(), fg_colour)
  val sheet = _declare_role(sheet, RoleMuted(), muted_colour)
  val sheet = _declare_role(sheet, RoleCard(), card_colour)
  val sheet = _declare_role(sheet, RoleLine(), line_colour)
  val sheet = _declare_role(sheet, RoleEdge(), edge_colour)
  val sheet = _declare_role(sheet, RoleBar(), bar_colour)
  val sheet = _declare_role(sheet, RoleBarText(), barfg_colour)
  val sheet = _declare_role(sheet, RoleAccent(), accent_colour)
  val sheet = _declare_role(sheet, RoleAccentText(), accentfg_colour)
  val sheet = _declare_role(sheet, RoleHighlight(), hl_colour)
  val sheet = _declare_role(sheet, RoleBarHigh(), barhi_colour)
  val sheet = _declare_role(sheet, RoleBanner(), banner_colour)
  val sheet = _declare_role(sheet, RoleBannerText(), bannerfg_colour)
  val sheet = _declare_role(sheet, RoleMark(), mark_colour)
  val sheet = _declare_role(sheet, RoleMarkText(), markfg_colour)
  val sheet = _declare_role(sheet, RoleDanger(), danger_colour)
  val sheet = _declare_role(sheet, RoleSecondHighlight(), hl2_colour)
in close(sheet) end

(* The rules the guarantees rest on; the only !important in the sheet *)
fn _base {left:nat | left >= 1700} (sheet: sheet(left, false, false)): [after:nat | after >= left - 1700] sheet(after, false, false) = let
  val () = raw(sheet, "[data-hide='1'],[hidden]{display:none!important}")
  (* 44 x 44 targets: every button and field, everything given a
     control's role, and the app's links out (ui_link_out); links in a
     book's text are inline targets, which WCAG leaves to the text they
     sit in *)
  val () = raw(sheet, "button,input,select,textarea,[role=button],[role=menuitem],[role=tab],[role=slider],[role=option],[role=switch],.linkout")
  val () = raw(sheet, "{min-height:48px!important;min-width:48px!important;box-sizing:border-box}")
  (* 16px in text fields, so iOS does not zoom into them *)
  val () = raw(sheet, "input,select,textarea{font-size:16px!important}")
  (* focus: 2px inside the edge in the control's own proven colour *)
  val () = raw(sheet, ":focus-visible{outline:2px solid currentColor!important;outline-offset:-2px!important}")
  (* text fields: fg on card with a 3:1 edge (S_fg_card, E_edge_card) *)
  prval _ = S_fg_card
  prval _ = E_edge_card
  val () = raw(sheet, "input:not([type=range]):not([type=file]),textarea,select")
  val () = raw(sheet, "{color:var(--fg)!important;background-color:var(--card)!important;border:1px solid var(--edge)!important}")
  (* a placeholder is text like any other (quire#357): muted on the
     field's own card, proven in every theme (SURF), and drawn in full,
     where a browser's default fades it below the proof *)
  val sheet = rule(sheet, "input::placeholder,textarea::placeholder")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val () = raw(sheet, "opacity:1;")
  val sheet = close(sheet)
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

(* The faces a page can be set in (Literata, Inter, Atkinson
   Hyperlegible; Inter is the interface's too) are block, not swap
   (#328): a page painted in a fallback and then again in its face as it
   comes in is laid out twice (its page count and place move with it),
   and the renderer could leave a few pixels of the fallback's glyphs at
   the column's edges. Its text shows only in its own face: invisible
   while the face loads (from the app's own files, a moment; at most the
   block period, about 3 s, before a fallback is shown after all) *)
fn _fonts {left:nat | left >= 1170} (sheet: sheet(left, false, false)): [after:nat | after >= left - 1170] sheet(after, false, false) = let
  val () = raw(sheet, "@font-face{font-family:Literata;src:url(literata-latin.woff2) format('woff2');font-style:normal;font-weight:200 900;font-display:block}")
  val () = raw(sheet, "@font-face{font-family:Literata;src:url(literata-italic-latin.woff2) format('woff2');font-style:italic;font-weight:200 900;font-display:block}")
  val () = raw(sheet, "@font-face{font-family:Inter;src:url(inter-latin.woff2) format('woff2');font-style:normal;font-weight:100 900;font-display:block}")
  (* fetched only when chosen: a face is loaded once text uses it *)
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-400-normal.woff2) format('woff2');font-style:normal;font-weight:400;font-display:block}")
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-700-normal.woff2) format('woff2');font-style:normal;font-weight:700;font-display:block}")
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-400-italic.woff2) format('woff2');font-style:italic;font-weight:400;font-display:block}")
  val () = raw(sheet, "@font-face{font-family:'Atkinson Hyperlegible';src:url(atkinson-700-italic.woff2) format('woff2');font-style:italic;font-weight:700;font-display:block}")
  (* the icons (ui.bats's _glyph): a subset of Material Symbols, its
     glyphs in the Private Use Area; block, so an icon never shows as a
     fallback's box while the face loads *)
  val () = raw(sheet, "@font-face{font-family:'Material Symbols';src:url(material-symbols-subset.woff2) format('woff2');font-weight:400;font-display:block}")
in sheet end

fn _shell {left:nat | left >= 8300} (sheet: sheet(left, false, false)): [after:nat | after >= left - 8300] sheet(after, false, false) = let
  val sheet = rule(sheet, "body")
  val sheet = lay(sheet, Margin(), "0")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".app")
  val sheet = lay(sheet, MinHeight(), "100vh")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = lay(sheet, FontFamily(), "Inter,system-ui,sans-serif")
  val sheet = lay(sheet, FontSize(), "16px")
  val sheet = lay(sheet, LineHeight(), "1.4")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".lib")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, MaxWidth(), "800px")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, Padding(), "max(12px,var(--safe-top)) max(16px,var(--safe-right)) max(24px,var(--safe-bottom)) max(16px,var(--safe-left))")
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
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
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
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = lay(sheet, FontSize(), "15px")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".btn-p")
  val sheet = surf(S_accentfg_accent | sheet, RoleAccentText(), RoleAccent())
  val sheet = line(sheet, AllSides(), 1, RoleAccent())
  val sheet = close(sheet)
  (* Import while the library cannot be read (its input is inert,
     #374): not the accent's call to act but the muted text on the card,
     a pair proven in every theme, with a cursor that says no (Material 3
     draws a disabled button with its container and text faded) *)
  val sheet = rule(sheet, "#import-button:has(input[inert]),#empty-import:has(input[inert])")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, Cursor(), "not-allowed")
  val sheet = close(sheet)
  (* the bar's Import is an icon button (a plus) with the file input
     over it: a div, since a page cannot open the picker itself (#404) *)
  val sheet = rule(sheet, "#import-button")
  val sheet = lay(sheet, Display(), "inline-flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, MinWidth(), "48px")
  val sheet = lay(sheet, MinHeight(), "48px")
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = close(sheet)
  (* the empty library's message and what it offers, centred *)
  val sheet = rule(sheet, ".eacts")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = lay(sheet, MarginTop(), "8px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".btn input[type=file],.ibtn input[type=file]")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, Height(), "100%")
  val sheet = invisible(sheet)
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = close(sheet)
  (* every icon (ui.bats's CIcon marks it data-icon, whatever its
     class: .ibtn, .cmore) is a glyph of the icon face, in the control's
     own text colour (#295) *)
  val sheet = rule(sheet, "[data-icon]")
  val sheet = lay(sheet, FontFamily(), "'Material Symbols',Inter,system-ui,sans-serif")
  val sheet = close(sheet)
  (* an icon button; text it shows (Skip table) is in the app's face *)
  val sheet = rule(sheet, ".ibtn")
  val sheet = lay(sheet, FontSize(), "24px")
  val sheet = lay(sheet, LineHeight(), "1")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
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
  val sheet = lay(sheet, Top(), "max(8px,var(--safe-top))")
  val sheet = lay(sheet, Left(), "50%")
  val sheet = centre_x(sheet)
  val sheet = lay(sheet, ZIndex(), "22")
  val sheet = lay(sheet, Width(), "calc(100% - 2*max(16px,var(--safe-left),var(--safe-right)))")
  val sheet = lay(sheet, MaxWidth(), "640px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Padding(), "10px 12px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 12px rgba(0,0,0,.35)")
  val sheet = surf(S_bannerfg_banner | sheet, RoleBannerText(), RoleBanner())
  val sheet = close(sheet)
  (* over the library the banner is part of the page, above the header,
     and pushes it down (#374): Material 3 puts a banner under the top app
     bar and moves the content, so nothing is under it. A fixed banner at
     the top hid the title, Import and the menu; one at the foot hid Try
     again on a short phone, because the library's own height is not
     known to it (the app bar wraps to five rows at 320px). The base
     rule's left 50% and translateX(-50%) still centre it when it is
     relative instead of fixed. Over the reader it stays fixed at the
     top while the bars are away (the reader's own bars hide) *)
  val sheet = rule(sheet, "#bats-root:has(#library:not([data-hide='1'])) .banner")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Top(), "auto")
  val sheet = lay(sheet, Margin(), "8px 0 0")
  val sheet = close(sheet)
  (* While the reader's bars are up the banner sits under the top bar
     (#374): the bar is the top app bar, and Material 3 puts a banner
     under it (material.io's banners, Flutter's MaterialBanner, Zebra's
     Zeta banner all sit under the app bar; none draws over it); the bar is its safe inset (at least 2px),
     a 44px control and 2px below, and the banner 8px under it. The
     bottom bar is at the other edge, out of its way *)
  val sheet = rule(sheet, "#bats-root:has(.rv:not(.chrome-off):not([data-hide='1'])) .banner")
  val sheet = lay(sheet, Top(), "calc(max(2px,var(--safe-top)) + 54px)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".banner .ibtn")
  val sheet = surf(S_bannerfg_banner | sheet, RoleBannerText(), RoleBanner())
  val sheet = close(sheet)
  (* the message takes the row and the buttons wrap under it on a narrow
     window, rather than Report being squeezed until its text is cut *)
  val sheet = rule(sheet, ".banner span")
  val sheet = lay(sheet, Flex(), "1 1 12em")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp")
  val sheet = lay(sheet, Margin(), "8px 0")
  val sheet = lay(sheet, Padding(), "10px 12px")
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-n")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, TextOverflow(), "ellipsis")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-s")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-bar")
  val sheet = lay(sheet, Height(), "6px")
  val sheet = fill(sheet, RoleLine())
  val sheet = lay(sheet, BorderRadius(), "3px")
  val sheet = lay(sheet, MarginTop(), "6px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".imp-fill")
  val sheet = lay(sheet, Height(), "100%")
  val sheet = fill(sheet, RoleAccent())
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
  (* which books takes its labels' width: when it and List and Grid do
     not fit one line (320 px, #265), List and Grid go to the next *)
  val sheet = rule(sheet, ".lview>.seg")
  val sheet = lay(sheet, Flex(), "1 1 auto")
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
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
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
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, Cursor(), "pointer")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".card *")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".cmore")
  val sheet = lay(sheet, FontSize(), "22px")
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".cov")
  val sheet = lay(sheet, Width(), "48px")
  val sheet = lay(sheet, Height(), "72px")
  val sheet = lay(sheet, ObjectFit(), "cover")
  val sheet = lay(sheet, BorderRadius(), "3px")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = fill(sheet, RoleLine())
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
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  (* a book's series and number *)
  val sheet = rule(sheet, ".bser")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".prog")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, MarginTop(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pbar")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, MaxWidth(), "160px")
  val sheet = lay(sheet, Height(), "5px")
  val sheet = fill(sheet, RoleLine())
  val sheet = lay(sheet, BorderRadius(), "3px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pfill")
  val sheet = lay(sheet, Height(), "100%")
  val sheet = fill(sheet, RoleAccent())
  val sheet = close(sheet)
  val sheet = rule(sheet, "#library-try-again")
  val sheet = lay(sheet, AlignSelf(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".empty")
  val sheet = lay(sheet, TextAlign(), "center")
  val sheet = surf(S_muted_bg | sheet, RoleMuted(), RoleGround())
  val sheet = lay(sheet, Padding(), "16px")
  val sheet = lay(sheet, MarginTop(), "15vh")
  val sheet = lay(sheet, FontSize(), "18px")
  val sheet = lay(sheet, FontStyle(), "italic")
  val sheet = close(sheet)
in sheet end

fn _overlays {left:nat | left >= 5900} (sheet: sheet(left, false, false)): [after:nat | after >= left - 5900] sheet(after, false, false) = let
  (* a book's image, full screen, on the page's ground; the fingers zoom
     and pan it *)
  val sheet = rule(sheet, ".imview")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, ZIndex(), "14")
  val sheet = fill(sheet, RoleGround())
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
  val sheet = lay(sheet, Top(), "max(8px,var(--safe-top))")
  val sheet = lay(sheet, Right(), "max(8px,var(--safe-right))")
  val sheet = surf(S_barfg_bar | sheet, RoleBarText(), RoleBar())
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
  val sheet = surf(S_barfg_bar | sheet, RoleBarText(), RoleBar())
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = spaced(sheet, Padding(), SpaceSmall())
  val sheet = spaced(sheet, PaddingLeft(), SpaceLarge())
  val sheet = spaced(sheet, PaddingRight(), SpaceMedium())
  val sheet = lay(sheet, BoxShadow(), "0 2px 12px rgba(0,0,0,.35)")
  val sheet = lay(sheet, Width(), "max-content")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, MaxWidth(), "min(420px,100vw - 2*max(16px,var(--safe-left),var(--safe-right)))")
  val sheet = close(sheet)
  (* a toast's words wrap, its buttons keep their width (the Undo toast
     has Undo and Dismiss beside its words) *)
  val sheet = rule(sheet, ".toast > span")
  val sheet = lay(sheet, Flex(), "1 1 auto")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".toast > button")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* the copy status, above the Undo toast: text alone, with no button *)
  val sheet = rule(sheet, ".toast.tcopy")
  val sheet = lay(sheet, Bottom(), "calc(env(safe-area-inset-bottom) + 168px)")
  val sheet = lay(sheet, Padding(), "10px 16px")
  val sheet = close(sheet)
  (* the offer of a new version, above the copy status *)
  val sheet = rule(sheet, ".toast.tnew")
  val sheet = lay(sheet, Bottom(), "calc(env(safe-area-inset-bottom) + 224px)")
  val sheet = close(sheet)
  (* the scrim under a reader panel (.panel, .sheet, at 12), over the
     reader and its bars: a ground with no text, as the dialog's veil *)
  val sheet = rule(sheet, ".scrim")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = veil(sheet)
  val sheet = lay(sheet, ZIndex(), "11")
  val sheet = close(sheet)
  (* the focus stops around the reader's panels: fixed, so the focus
     coming to one scrolls nothing, and empty *)
  val sheet = rule(sheet, ".fstop")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ovl")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = lay(sheet, Padding(), "var(--safe-top) var(--safe-right) var(--safe-bottom) var(--safe-left)")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = veil(sheet)
  val sheet = lay(sheet, ZIndex(), "20")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".menu,.mbox")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = spaced(sheet, Padding(), SpaceSmall())
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
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  (* a menu of choices (the sort and view menu): the group's name, and the
     current choice checked by a mark drawn in the item's own text colour
     (the checkbox of Material's menus) *)
  val sheet = rule(sheet, ".mgroup")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mhead")
  val sheet = lay(sheet, FontWeight(), "600")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = lay(sheet, Padding(), "8px 14px 4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi[role=menuitemradio]")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, PaddingLeft(), "40px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi[aria-checked=true]::before")
  val () = raw(sheet, "content:\"\";position:absolute;left:18px;top:50%;width:6px;height:12px;margin-top:-9px;border:solid currentColor;border-width:0 2px 2px 0;transform:rotate(45deg);")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi:hover")
  val sheet = surf(S_fg_line | sheet, RoleText(), RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi[data-harm=y]")
  val sheet = surf(S_danger_card | sheet, RoleDanger(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".mi[data-harm=y]:hover")
  val sheet = surf(S_danger_line | sheet, RoleDanger(), RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".menu .mi.btn")
  val sheet = no_line(sheet)
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, JustifyContent(), "flex-start")
  val sheet = lay(sheet, Padding(), "12px 14px")
  val sheet = lay(sheet, FontSize(), "inherit")
  val sheet = close(sheet)
  (* a dialog: Material's 24 px round it, 16 px between its parts *)
  val sheet = rule(sheet, ".mbox")
  val sheet = spaced(sheet, Padding(), SpaceExtraLarge())
  val sheet = spaced(sheet, Gap(), SpaceLarge())
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
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = lay(sheet, FontStyle(), "italic")
  val sheet = close(sheet)
  (* the reading statistics: a label and its number a line *)
  val sheet = rule(sheet, ".srow")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, JustifyContent(), "space-between")
  val sheet = lay(sheet, Gap(), "16px")
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow b")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
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
  val sheet = surf(S_danger_card | sheet, RoleDanger(), RoleCard())
  val sheet = line(sheet, AllSides(), 1, RoleDanger())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = lay(sheet, ZIndex(), "15")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = lay(sheet, Padding(), "max(12px,var(--safe-top)) max(16px,var(--safe-right)) max(24px,var(--safe-bottom)) max(16px,var(--safe-left))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info-in")
  val sheet = lay(sheet, MaxWidth(), "600px")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = spaced(sheet, Gap(), SpaceSmall())
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
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = surf(S_muted_bg | sheet, RoleMuted(), RoleGround())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".irow b")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = lay(sheet, FontWeight(), "normal")
  val sheet = close(sheet)
in sheet end

fn _reader {left:nat | left >= 10300} (sheet: sheet(left, false, false)): [after:nat | after >= left - 10300] sheet(after, false, false) = let
  (* the reader is the window, whatever a viewport unit says (in an
     Android WebView 100vh can be taller than what is shown, so the page
     and a sheet's bottom could pass the screen's edge, #275): fixed to
     the layout viewport, nothing behind it scrolls *)
  val sheet = rule(sheet, ".rv")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Inset(), "0")
  (* The visible reading area, given once here: what the page's
     paddings keep clear (its columns are the page's height less them,
     so the column is exactly that area), the running footer's place,
     and a vertical page's column gap (#296). The footer sits 8px above
     the screen's bottom inset (Android's navigation bar, which an app
     drawn edge to edge has under it), 16px tall, and the text keeps
     half a line (at least 12px) clear of the footer below and of the
     top inset (the status bar) above: Material 3 spaces on 4dp steps
     and pads what the system bars would cover by their insets.
     A line-height unit (lh) in a variable is the line of the element
     that uses it: the page's *)
  val sheet = lay(sheet, FooterBottomVariable(), "calc(env(safe-area-inset-bottom) + 8px)")
  val sheet = lay(sheet, FooterHeightVariable(), "16px")
  val sheet = lay(sheet, PageTopVariable(), "max(48px,calc(env(safe-area-inset-top) + max(12px,.5lh)))")
  val sheet = lay(sheet, PageBottomVariable(), "calc(var(--footer-bottom) + var(--footer-height) + max(12px,.5lh))")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top,.bot")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = lay(sheet, Padding(), "2px max(6px,var(--safe-right)) 2px max(6px,var(--safe-left))")
  val sheet = surf(S_barfg_bar | sheet, RoleBarText(), RoleBar())
  val sheet = lay(sheet, ZIndex(), "3")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, PaddingTop(), "max(2px,var(--safe-top))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bot")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, PaddingBottom(), "max(2px,var(--safe-bottom))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top .ibtn,.bot .ibtn,.snavf .ibtn")
  val sheet = surf(S_barfg_bar | sheet, RoleBarText(), RoleBar())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".top .ibtn:hover,.bot .ibtn:hover,.snavf .ibtn:hover")
  val sheet = surf(S_barfg_barhi | sheet, RoleBarText(), RoleBarHigh())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ctitle")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, TextOverflow(), "ellipsis")
  val sheet = close(sheet)
  (* the bottom bar's progress row: the label, a line of its own over
     the scrubber, whole (#274): it wraps before the percentage rather
     than cut anything *)
  (* the offer of the place another device read (sync.bats): a row of
     its own, the bar's first, over the progress row *)
  val sheet = rule(sheet, ".soffer")
  val sheet = lay(sheet, FlexBasis(), "100%")
  val sheet = lay(sheet, Order(), "-1")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, PaddingTop(), "6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".plab")
  val sheet = lay(sheet, FlexBasis(), "100%")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, AlignItems(), "baseline")
  val sheet = lay(sheet, Gap(), "0 6px")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = lay(sheet, PaddingTop(), "6px")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, TextAlign(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pinfo")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, Flex(), "0 1 auto")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".psep")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* the tools row: each tool a 48 px target, spread evenly; the
     narration's group goes to a line of its own where the row has no
     room for it *)
  val sheet = rule(sheet, ".tools")
  val sheet = lay(sheet, FlexBasis(), "100%")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, JustifyContent(), "space-evenly")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tools .ibtn")
  val sheet = lay(sheet, Width(), "48px")
  val sheet = lay(sheet, Height(), "48px")
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
  val sheet = lay(sheet, Bottom(), "var(--footer-bottom)")
  val sheet = lay(sheet, Height(), "var(--footer-height)")
  val sheet = lay(sheet, LineHeight(), "var(--footer-height)")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, Padding(), "0 24px")
  val sheet = lay(sheet, FontSize(), "12px")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = surf(S_muted_bg | sheet, RoleMuted(), RoleGround())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".chrome-off .foot")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = close(sheet)
  (* the page keeps out of the screen's cutouts and rounded corners
     (the safe area) on every side, in or out of full screen: above and
     below in its paddings (the reading area's, .rv, which keep the
     running footer clear too, #296), and at its sides (a cutout there in
     landscape) in its margins, so its columns, a page each, are the
     safe width (#275) *)
  val sheet = rule(sheet, ".caf")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  (* the page's width and height, whole pixels: only a page_extent(1) gives their text (page_size.bats) *)
  val () = raw(sheet, page_width_rule(RoundedDown()))
  val () = raw(sheet, page_height_rule(RoundedDown()))
  val sheet = lay(sheet, MarginLeft(), "env(safe-area-inset-left)")
  val sheet = lay(sheet, MarginRight(), "env(safe-area-inset-right)")
  val sheet = lay(sheet, PaddingTop(), "var(--page-top)")
  val sheet = lay(sheet, PaddingBottom(), "var(--page-bottom)")
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
     the reader's settings (settings.bats, in style-type). Its margins
     are logical: the space after it is below it in horizontal text,
     and beside it (between its columns of lines) in vertical text,
     where a margin below would shorten its lines *)
  val sheet = rule(sheet, ".caf p")
  val sheet = lay(sheet, MarginBlock(), "0 .8em")
  val sheet = lay(sheet, MarginInline(), "auto")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf h1,.caf h2,.caf h3")
  val sheet = lay(sheet, TextAlign(), "center")
  val sheet = lay(sheet, MarginBlock(), "1.5em .5em")
  val sheet = lay(sheet, BreakAfter(), "avoid")
  val sheet = close(sheet)
  (* an element the book marks hidden stays hidden (#411) *)
  val sheet = rule(sheet, ".caf .hidden-by-book")
  val sheet = lay(sheet, Display(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf hr")
  val sheet = no_line(sheet)
  val sheet = line(sheet, TopSide(), 1, RoleLine())
  val sheet = lay(sheet, Margin(), "2em auto")
  val sheet = lay(sheet, MaxWidth(), "200px")
  val sheet = close(sheet)
  (* a picture is at most a column's height: the window's less the
     page's paddings *)
  val sheet = rule(sheet, ".caf img")
  val sheet = lay(sheet, MaxWidth(), "100%")
  val sheet = lay(sheet, MaxHeight(), "calc(100dvh - var(--page-top) - var(--page-bottom))")
  val sheet = lay(sheet, ObjectFit(), "contain")
  val sheet = lay(sheet, Height(), "auto")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, BreakInside(), "avoid")
  val sheet = close(sheet)
  (* a table is a scroll container, as wide as the column and as tall as its
     height at most (#413): a block that scrolls cannot be split between
     columns, so one taller than the page would lose the rows past the
     page's foot *)
  val sheet = rule(sheet, ".caf table")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = lay(sheet, MaxWidth(), "100%")
  val sheet = lay(sheet, MaxHeight(), "calc(100dvh - var(--page-top) - var(--page-bottom))")
  val sheet = lay(sheet, BorderCollapse(), "collapse")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf td,.caf th")
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = lay(sheet, Padding(), "2px 6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf a,.caf [role=link]")
  val sheet = surf(S_accent_bg | sheet, RoleAccent(), RoleGround())
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
  (* set vertically (a Chinese, Japanese or Korean book read right to
     left; Mongolian in its script, its lines going on to the right):
     the columns follow the inline axis, down the page, so a page is one
     column and the gap between two, the page's top and bottom paddings
     (.caf), and a turn is exactly the page's height. Always paged, one
     column a screen: these outrank the typography's .caf (style-type,
     settings.bats), whose columns and scroll they replace *)
  val sheet = rule(sheet, ".caf.vertical,.caf.vertical-lr")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, ColumnWidth(), "100vh")
  val sheet = lay(sheet, ColumnGap(), "calc(var(--page-top) + var(--page-bottom))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf.vertical")
  val sheet = lay(sheet, WritingMode(), "vertical-rl")
  (* Latin and digits are turned, the default (text-orientation:mixed):
     JLREQ has an English word rotated 90 degrees and only a short number
     or acronym upright, which text-combine-upright:all gives a wrapped
     run (quire#391); upright on the page set every Latin word upright
     too, which no source supports *)
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf.vertical-lr")
  val sheet = lay(sheet, WritingMode(), "vertical-lr")
  val sheet = close(sheet)
  (* the lines are the column's height, and the margins' setting is not
     offered (the typography's paddings on the page's children): a
     block takes the page's width, and its lines its height *)
  val sheet = rule(sheet, ".caf.vertical>*,.caf.vertical-lr>*")
  val sheet = lay(sheet, MaxWidth(), "none")
  val sheet = lay(sheet, PaddingLeft(), "0")
  val sheet = lay(sheet, PaddingRight(), "0")
  val sheet = close(sheet)
  (* a fixed-layout page: the page is the whole reader view (the bars
     over it, as they are over a reflowed page), with no columns,
     scroll or paddings, and its box (reader.bats's page-box) centred
     in it, its own size scaled to fit (its inline style, ui_fixed_box_n,
     from _fixed_fit). Not restyled: these outrank the typography's .caf
     and .caf>* (style-type, settings.bats). What is outside the box is
     cut off, as EPUB RS 3.3 says, and its images fit it (the book's
     own CSS, which would size them, is not used) *)
  val sheet = rule(sheet, ".caf.fixed")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = lay(sheet, Padding(), "0")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, ColumnWidth(), "auto")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf.fixed>*")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = lay(sheet, MaxWidth(), "none")
  val sheet = lay(sheet, Margin(), "0")
  val sheet = lay(sheet, Padding(), "0")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, ContainerType(), "size")
  val sheet = close(sheet)
  (* a spread's facing page is shown, not marked: what is selected,
     highlighted or read aloud is the page's *)
  val sheet = rule(sheet, ".caf .facing")
  val sheet = lay(sheet, UserSelect(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf.fixed img")
  val sheet = lay(sheet, MaxWidth(), "100cqw")
  val sheet = lay(sheet, MaxHeight(), "100cqh")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf figure")
  val sheet = lay(sheet, Margin(), "1em auto")
  val sheet = close(sheet)
  (* an audio or video element, not played: a line says so before its
     fallback content (#424) *)
  val sheet = rule(sheet, ".caf .media-fallback::before")
  val () = raw(sheet, "content:\"Audio or video: Quire does not play it.\";display:block;font-style:italic;")
  val sheet = close(sheet)
  (* a note's text and a caption are set smaller than the text round them,
     and scale with it (#422) *)
  val sheet = rule(sheet, ".caf .note-text,.caf figcaption")
  val sheet = lay(sheet, FontSize(), ".875em")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".caf sup,.caf sub")
  val sheet = lay(sheet, LineHeight(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, "::highlight(bats-mark-1)")
  val sheet = surf(S_fg_hl | sheet, RoleText(), RoleHighlight())
  val sheet = close(sheet)
  val sheet = rule(sheet, "::highlight(bats-mark-2)")
  val sheet = surf(S_markfg_mark | sheet, RoleMarkText(), RoleMark())
  val sheet = close(sheet)
  (* the orange highlight; and the underline, in the text's own colour
     (so its contrast is the text's), thick enough to tell from a link's *)
  val sheet = rule(sheet, "::highlight(bats-mark-3)")
  val sheet = surf(S_fg_hl2 | sheet, RoleText(), RoleSecondHighlight())
  val sheet = close(sheet)
  (* the sentence read aloud (read_aloud.bats) *)
  val sheet = rule(sheet, "::highlight(bats-mark-5)")
  val sheet = surf(S_markfg_mark | sheet, RoleMarkText(), RoleMark())
  val sheet = close(sheet)
  val sheet = rule(sheet, "::highlight(bats-mark-4)")
  val sheet = lay(sheet, TextDecoration(), "underline 3px")
  val sheet = close(sheet)
  (* the text a book's narration reads (narration.bats): the same proven
     pair as the sentence read aloud *)
  val sheet = rule(sheet, "::highlight(bats-mark-5)")
  val sheet = surf(S_markfg_mark | sheet, RoleMarkText(), RoleMark())
  val sheet = close(sheet)
  (* the narration's controls, in the bottom bar's row *)
  val sheet = rule(sheet, ".ngrp")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tools .nleave")
  val sheet = lay(sheet, Width(), "auto")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = lay(sheet, Padding(), "0 8px")
  val sheet = close(sheet)
  (* the scrubber, between the page turns *)
  val sheet = rule(sheet, ".scr")
  val sheet = lay(sheet, Flex(), "1 1 0")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, Padding(), "0 6px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".trk")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Height(), "48px")
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
  (* a book read right to left: the bar follows (reader.bats'
     _direction_set, quire#359): the fill from the right, and the page
     turns on the other sides of the scrubber *)
  val sheet = rule(sheet, ".trk.rtl .trk-f")
  val sheet = lay(sheet, Left(), "auto")
  val sheet = lay(sheet, Right(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bot.rtl .pnext")
  val sheet = lay(sheet, Order(), "1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bot.rtl .scr")
  val sheet = lay(sheet, Order(), "2")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bot.rtl .pprev")
  val sheet = lay(sheet, Order(), "3")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bot.rtl .tools")
  val sheet = lay(sheet, Order(), "4")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".trk-f")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Top(), "20px")
  val sheet = lay(sheet, Height(), "4px")
  val sheet = fill(sheet, RoleBarText())
  val sheet = lay(sheet, BorderRadius(), "2px")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tick")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "18px")
  val sheet = lay(sheet, Width(), "2px")
  val sheet = lay(sheet, Height(), "8px")
  val sheet = tint(sheet, true, 45)
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".thumb")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Top(), "10px")
  val sheet = lay(sheet, Width(), "24px")
  val sheet = lay(sheet, Height(), "24px")
  val sheet = lay(sheet, MarginLeft(), "-12px")
  val sheet = lay(sheet, BorderRadius(), "50%")
  val sheet = fill(sheet, RoleBarText())
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tip")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Bottom(), "46px")
  val sheet = centre_x(sheet)
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, Padding(), "2px 8px")
  val sheet = lay(sheet, BorderRadius(), "4px")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pct")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pback")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "max(12px,var(--safe-left))")
  val sheet = lay(sheet, Bottom(), "106px")
  val sheet = lay(sheet, ZIndex(), "4")
  val sheet = surf(S_accentfg_accent | sheet, RoleAccentText(), RoleAccent())
  val sheet = lay(sheet, BorderRadius(), "22px")
  val sheet = lay(sheet, Padding(), "8px 16px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sheet = close(sheet)
  (* scrolled, on the chapter's last screen: at the right, apart from
     Back at the left *)
  (* the hint on turning pages, over the page's middle *)
  val sheet = rule(sheet, ".hint")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "max(16px,var(--safe-left))")
  val sheet = lay(sheet, Right(), "max(16px,var(--safe-right))")
  val sheet = lay(sheet, Top(), "45%")
  val sheet = lay(sheet, Width(), "fit-content")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, ZIndex(), "4")
  val sheet = surf(S_accentfg_accent | sheet, RoleAccentText(), RoleAccent())
  val sheet = lay(sheet, BorderRadius(), "22px")
  val sheet = lay(sheet, Padding(), "10px 18px")
  val sheet = lay(sheet, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".nextch")
  val sheet = lay(sheet, Left(), "auto")
  val sheet = lay(sheet, Right(), "max(12px,var(--safe-right))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seltb")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "50%")
  (* the top comes from the selection (ui_toolbar_at): above it, else
     below its end handle, kept in the window and the safe area *)
  val sheet = lay(sheet, Top(), "min(max(var(--seltb-top,40%),max(8px,var(--safe-top))),calc(100% - max(8px,var(--safe-bottom)) - var(--seltb-height,56px)))")
  val sheet = centre_x(sheet)
  val sheet = lay(sheet, ZIndex(), "5")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = surf(S_barfg_bar | sheet, RoleBarText(), RoleBar())
  val sheet = lay(sheet, BorderRadius(), "10px")
  val sheet = spaced(sheet, Padding(), SpaceSmall())
  val sheet = lay(sheet, BoxShadow(), "0 2px 8px rgba(0,0,0,.3)")
  (* no wider than the screen: its items go on a second row instead *)
  val sheet = lay(sheet, Width(), "max-content")
  val sheet = lay(sheet, MaxWidth(), "calc(100vw - 2*max(8px,var(--safe-left),var(--safe-right)))")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, JustifyContent(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seltb button,.seltb a")
  val sheet = lay(sheet, Padding(), "8px 14px")
  val sheet = surf(S_barfg_bar | sheet, RoleBarText(), RoleBar())
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, WhiteSpace(), "nowrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seltb button:hover,.seltb a:hover")
  val sheet = surf(S_barfg_barhi | sheet, RoleBarText(), RoleBarHigh())
  val sheet = close(sheet)
  (* a probe as tall as the least distance the toolbar keeps from the
     window's top (the safe area), for the code to measure (quire#428) *)
  val sheet = rule(sheet, ".seltbfloor")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Width(), "0")
  val sheet = lay(sheet, Height(), "max(8px,var(--safe-top))")
  val sheet = lay(sheet, Visibility(), "hidden")
  val sheet = lay(sheet, PointerEvents(), "none")
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
  val sheet = surf(S_barfg_bar | sheet, RoleBarText(), RoleBar())
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

fn _panels {left:nat | left >= 6700} (sheet: sheet(left, false, false)): [after:nat | after >= left - 6700] sheet(after, false, false) = let
  val sheet = rule(sheet, ".panel")
  val sheet = lay(sheet, Position(), "fixed")
  val sheet = lay(sheet, Top(), "0")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, Left(), "0")
  (* a modal side panel leaves a strip of the scrim, a tap on which
     closes it: as wide as the screen less 56 px, as Material's modal
     navigation drawer *)
  val sheet = lay(sheet, Width(), "min(420px,calc(100vw - 56px))")
  val sheet = lay(sheet, ZIndex(), "12")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, BoxShadow(), "2px 0 16px rgba(0,0,0,.3)")
  val sheet = lay(sheet, Padding(), "var(--safe-top) 0 var(--safe-bottom) var(--safe-left)")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".panel-r")
  val sheet = lay(sheet, Left(), "auto")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, PaddingLeft(), "0")
  val sheet = lay(sheet, PaddingRight(), "var(--safe-right)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ph")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = spaced(sheet, Padding(), SpaceSmall())
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ph .grow")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ph .ibtn")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  (* three tabs and Close fit the panel's head at 320px: the tabs are at
     least 48px tall (the base rule), so their sides give the room *)
  val sheet = rule(sheet, ".ph .tab")
  val sheet = spaced_pair(sheet, Padding(), SpaceSmall(), SpaceTight())
  val sheet = close(sheet)
  (* a header's buttons keep their whole text: the title gives way *)
  val sheet = rule(sheet, ".ph .btn")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = spaced(sheet, Padding(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabs")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tab")
  val sheet = spaced(sheet, Padding(), SpaceSmall())
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  (* the chosen tab keeps the card and is told apart by an underline in
     the accent, proven 3:1 on the card (quire#358) *)
  val sheet = rule(sheet, ".tab[aria-selected=true]")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = underline(E_accent_card | sheet, RoleAccent(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".plist")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, Overflow(), "auto")
  (* its rows inset from the panel's sides, as Material's navigation
     drawer insets its items *)
  val sheet = spaced_pair(sheet, Padding(), SpaceTight(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, TextAlign(), "left")
  val sheet = spaced_pair(sheet, Padding(), SpaceMedium(), SpaceLarge())
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".pi[aria-current=true]")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = surf(S_fg_line | sheet, RoleText(), RoleLine())
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
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, MarginTop(), "2px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hq")
  val sheet = lay(sheet, Display(), "block")
  val sheet = line(sheet, LeftSide(), 3, RoleAccent())
  val sheet = lay(sheet, PaddingLeft(), "8px")
  val sheet = lay(sheet, FontStyle(), "italic")
  val sheet = close(sheet)
  (* a highlight's quote, marked as it is on the page, after its style's
     name *)
  val sheet = rule(sheet, ".hq-yellow")
  val sheet = surf(S_fg_hl | sheet, RoleText(), RoleHighlight())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hq-orange")
  val sheet = surf(S_fg_hl2 | sheet, RoleText(), RoleSecondHighlight())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hq-under")
  val sheet = lay(sheet, TextDecoration(), "underline 3px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hstyle")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, FontSize(), "12px")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
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
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".hrow")
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
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
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = lay(sheet, MarginTop(), "0")
  val sheet = lay(sheet, LineHeight(), "1.45")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".grp")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = lay(sheet, Padding(), "12px 12px 4px")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
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
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, Padding(), "12px max(16px,var(--safe-right)) 0 max(16px,var(--safe-left))")
  val sheet = lay(sheet, BoxShadow(), "0 -2px 16px rgba(0,0,0,.3)")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "10px")
  val sheet = lay(sheet, MaxWidth(), "520px")
  val sheet = lay(sheet, Margin(), "0 auto")
  val sheet = lay(sheet, BorderRadius(), "12px 12px 0 0")
  (* taller than a short screen allows: it scrolls, within the height
     shown (dvh: in full screen, and in a WebView, vh can be more) *)
  val sheet = lay(sheet, MaxHeight(), "85dvh")
  val sheet = lay(sheet, Overflow(), "auto")
  val sheet = close(sheet)
  (* a sheet's head, its Close in it: held at the sheet's top as the
     rest scrolls, so Close is always in reach (as Apple Books' sheet
     keeps its close at its top) *)
  val sheet = rule(sheet, ".shead")
  val sheet = lay(sheet, Position(), "sticky")
  val sheet = lay(sheet, Top(), "-12px")
  val sheet = lay(sheet, ZIndex(), "1")
  val sheet = lay(sheet, Margin(), "-12px -16px 0")
  val sheet = lay(sheet, Padding(), "12px 16px 6px")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".shead .grow")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = close(sheet)
  (* its rows keep their height, and the sheet scrolls instead *)
  val sheet = rule(sheet, ".sheet>*")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* its foot pads the sheet's bottom and is held there as the rest
     scrolls, on the sheet's ground, so nothing scrolls under the
     navigation bar (#341) *)
  val sheet = rule(sheet, ".sheet>.sfoot")
  val sheet = lay(sheet, Position(), "sticky")
  val sheet = lay(sheet, Bottom(), "0")
  val sheet = lay(sheet, ZIndex(), "1")
  val sheet = lay(sheet, PaddingBottom(), "max(16px,var(--safe-bottom))")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  (* a note's text, over the page: a long one scrolls *)
  val sheet = rule(sheet, ".fntext")
  val sheet = lay(sheet, MaxHeight(), "50dvh")
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
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
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
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow input[type=range]")
  val sheet = lay(sheet, Flex(), "1")
  val sheet = accent(E_accent_card | sheet, RoleAccent(), RoleCard())
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
  (* a segment is never narrower than its label (the 44 px minimum
     would let it shrink under it and cut it, #265): the segments that
     do not fit go to the next line, and a label wider than the line
     wraps in its segment *)
  val sheet = rule(sheet, ".seg button")
  val sheet = lay(sheet, Flex(), "1 0 auto")
  val sheet = lay(sheet, MaxWidth(), "100%")
  val sheet = lay(sheet, Padding(), "8px 6px")
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = lay(sheet, BorderRadius(), "6px")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg button[aria-pressed=true]")
  val sheet = surf(S_accentfg_accent | sheet, RoleAccentText(), RoleAccent())
  val sheet = line(sheet, AllSides(), 1, RoleAccent())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sfoot")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Gap(), "8px")
  val sheet = lay(sheet, JustifyContent(), "space-between")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".link")
  val sheet = surf(S_accent_card | sheet, RoleAccent(), RoleCard())
  val sheet = lay(sheet, TextDecoration(), "underline")
  val sheet = lay(sheet, Padding(), "6px 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sbar")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = spaced(sheet, Padding(), SpaceSmall())
  val sheet = line(sheet, BottomSide(), 1, RoleLine())
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
  val sheet = spaced(sheet, Padding(), SpaceSmall())
  val sheet = line(sheet, TopSide(), 1, RoleLine())
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
in sheet end

(* The reading settings' switches and stacked rows (quire#300): a
   switch is a button the row's width, its name at the start and a drawn
   track at the end, whose knob sits at the start, in the edge's colour,
   while it is off, and at the end, in the accent's text colour on a
   track filled with the accent, while it is on (aria-pressed), so its
   state shows in its look, not only to assistive technology (WCAG
   1.4.1). Track and knob are graphics that say a state, so each keeps
   3:1 against what is around it (WCAG 1.4.11): the edge on the card
   (E_edge_card), the accent on the card (E_accent_card), the knob on
   the accent (S_accentfg_accent). A bar's toggle on is marked too. A
   stacked row puts a label, its
   control the whole width (a select is never cut to "Syste...") and a
   line saying what it does, one under another *)
fn _switches {left:nat | left >= 2000} (sheet: sheet(left, false, false)): [after:nat | after >= left - 2000] sheet(after, false, false) = let
  prval _ = E_edge_card
  prval _ = E_accent_card
  val sheet = rule(sheet, ".sgroup")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow.stack")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, AlignItems(), "stretch")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".stack .slabel")
  val sheet = lay(sheet, Width(), "auto")
  val sheet = close(sheet)
  (* a select is never narrower than its chosen option: in a row too
     narrow for its label and its selects (Speed and voice at 320 px),
     the last ones go to the next line instead *)
  val sheet = rule(sheet, ".srow:has(>.ssel)")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ssel")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* a list row's button (a dictionary's or a catalogue's Remove) keeps
     its word whole; the name beside it wraps instead (320 px) *)
  val sheet = rule(sheet, ".srow>.btn")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".stack .ssel")
  val sheet = lay(sheet, MaxWidth(), "none")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sabout")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sbtn.switch")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "space-between")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = lay(sheet, TextAlign(), "start")
  val sheet = lay(sheet, FontSize(), "15px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch .track")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Width(), "44px")
  val sheet = lay(sheet, Height(), "24px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, BorderRadius(), "12px")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = fill(sheet, RoleCard())
  val sheet = line(sheet, AllSides(), 2, RoleEdge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch .knob")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Top(), "3px")
  val sheet = lay(sheet, Left(), "3px")
  val sheet = lay(sheet, Width(), "14px")
  val sheet = lay(sheet, Height(), "14px")
  val sheet = lay(sheet, BorderRadius(), "50%")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = fill(sheet, RoleEdge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch[aria-pressed=true] .track")
  val sheet = fill(sheet, RoleAccent())
  val sheet = line(sheet, AllSides(), 2, RoleAccent())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch[aria-pressed=true] .knob")
  val sheet = lay(sheet, Left(), "23px")
  val sheet = fill(sheet, RoleAccentText())
  val sheet = close(sheet)
  (* a bar's toggle (Read aloud, the narration's, the bookmark) on: the
     bar's highlight, as under a finger, and a bar of its text's colour
     under it, which a hover does not have *)
  val sheet = rule(sheet, ".top .ibtn[aria-pressed=true],.bot .ibtn[aria-pressed=true]")
  val sheet = surf(S_barfg_barhi | sheet, RoleBarText(), RoleBarHigh())
  val sheet = line(sheet, BottomSide(), 3, RoleBarText())
  val sheet = close(sheet)
in sheet end

(* The spacing scale on the screens (#331): the least inset given to the
   page (--space-inset, the e2e walk's minimum); a full screen's rows and
   notes drawn as cards (Material's list item: 8 px above and below, 16
   px at the sides, so no button touches a card's edge) that wrap
   rather than cut a button; a panel opened as a dialog 16 px round
   its content. And the Sync screen's parts: its status card (where,
   how it went, its actions), its footer note, and its sign-in step,
   which hides the screen's list while it is shown *)
fn _spacing {left:nat | left >= 1600} (sheet: sheet(left, false, false)): [after:nat | after >= left - 1600] sheet(after, false, false) = let
  val sheet = rule(sheet, ":root")
  val () = raw(sheet, "--space-inset:")
  val () = raw(sheet, _space_length(space_inset()))
  val () = raw(sheet, ";")
  (* each side's safe area (the system's bars and a cutout over the
     page, #341) and the least inset beyond it, or nothing where the
     side has none: what a screen, panel, sheet or bar pads that side
     by, so nothing of it comes near a bar *)
  val () = raw(sheet, "--safe-top:min(env(safe-area-inset-top)*1000,env(safe-area-inset-top) + var(--space-inset));")
  val () = raw(sheet, "--safe-right:min(env(safe-area-inset-right)*1000,env(safe-area-inset-right) + var(--space-inset));")
  val () = raw(sheet, "--safe-bottom:min(env(safe-area-inset-bottom)*1000,env(safe-area-inset-bottom) + var(--space-inset));")
  val () = raw(sheet, "--safe-left:min(env(safe-area-inset-left)*1000,env(safe-area-inset-left) + var(--space-inset));")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".menu[role=dialog]")
  val sheet = spaced(sheet, Padding(), SpaceLarge())
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info .srow")
  val sheet = spaced_pair(sheet, Padding(), SpaceSmall(), SpaceLarge())
  val sheet = lay(sheet, BorderRadius(), "12px")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info-in>.sabout,.info-in>.cnone,.scard")
  val sheet = spaced_pair(sheet, Padding(), SpaceMedium(), SpaceLarge())
  val sheet = lay(sheet, BorderRadius(), "12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".scard")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".swhere")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = close(sheet)
  (* a sign-in step's words, on the screen's own ground *)
  val sheet = rule(sheet, ".stext")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".snote")
  val sheet = surf(S_muted_bg | sheet, RoleMuted(), RoleGround())
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = spaced_pair(sheet, Padding(), SpaceTight(), SpaceLarge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sstep")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sstep:not([data-hide='1'])~*")
  val sheet = lay(sheet, Display(), "none")
  val sheet = close(sheet)
in sheet end

fn _under_480px {left:nat | left >= 480} (sheet: sheet(left, false, false)): [after:nat | after >= left - 480] sheet(after, false, false) = let
  val sheet = media(sheet, "(max-width:480px)")
  val sheet = rule(sheet, ".lib")
  val sheet = lay(sheet, PaddingLeft(), "max(10px,var(--safe-left))")
  val sheet = lay(sheet, PaddingRight(), "max(10px,var(--safe-right))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ttl")
  val sheet = lay(sheet, FontSize(), "20px")
  val sheet = lay(sheet, Flex(), "1 1 0")
  val sheet = lay(sheet, MinWidth(), "0")
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

fn _under_600px {left:nat | left >= 57} (sheet: sheet(left, false, false)): [after:nat | after >= left - 57] sheet(after, false, false) = let
  val sheet = media(sheet, "(max-width:600px)")
  val sheet = rule(sheet, ".caf p")
  val sheet = lay(sheet, TextAlign(), "start")
  val sheet = close(sheet)
  val sheet = media_end(sheet)
in sheet end

(* The selector of a page turn's shade at a level in a theme (the
   light theme's is also the default) *)
fn _shade_selector {number:palette}{level:pos | level <= 4} (which: palette_theme(number), level: int level): [length:pos | length <= 40] string length =
  case+ which of
  | Light() => (case+ level of 1 => ".shade.s1,.th-light .shade.s1" | 2 => ".shade.s2,.th-light .shade.s2"
    | 3 => ".shade.s3,.th-light .shade.s3" | _ => ".shade.s4,.th-light .shade.s4")
  | Sepia() => (case+ level of 1 => ".th-sepia .shade.s1" | 2 => ".th-sepia .shade.s2"
    | 3 => ".th-sepia .shade.s3" | _ => ".th-sepia .shade.s4")
  | Dark() => (case+ level of 1 => ".th-dark .shade.s1" | 2 => ".th-dark .shade.s2"
    | 3 => ".th-dark .shade.s3" | _ => ".th-dark .shade.s4")
  | Night() => (case+ level of 1 => ".th-night .shade.s1" | 2 => ".th-night .shade.s2"
    | 3 => ".th-night .shade.s3" | _ => ".th-night .shade.s4")
  | Grey() => (case+ level of 1 => ".th-grey .shade.s1" | 2 => ".th-grey .shade.s2"
    | 3 => ".th-grey .shade.s3" | _ => ".th-grey .shade.s4")

(* The shade at a level (1 to 4, the strongest last) in a theme: black
   at strength percent, a ground with no text, at a strength proven to
   leave every pair the page shows legible under it (VEILED) *)
fn _shade_rule {number:palette}{strength:nat | strength <= 100}{level:pos | level <= 4}{left:nat | left >= 120}
  (veiled: VEILED(number, strength) | sheet: sheet(left, false, false), which: palette_theme(number), level: int level, strength: int strength)
  : [after:nat | after >= left - 120] sheet(after, false, false) = let
  val sheet = rule(sheet, _shade_selector(which, level))
  val () = raw(sheet, "background-color:rgba(0,0,0,")
  val sheet = _number(sheet, strength)
  val () = raw(sheet, "%);font-size:0;")
in close(sheet) end

(* A page turn (reader.bats): the shade over the incoming page, and
   over it page-turn, where the page being left (a copy, in .leaf, on
   the page's own ground, proven) slides off, the gap it leaves showing
   the page beneath (blank, a ground with no text, while a drag holds a
   chapter's first or last page). Its edge casts a shadow on the page
   beneath. Neither takes a tap, which goes through to the page. The
   shade is strongest in the light themes, where a shadow shows; in the
   dark ones it is weaker (Night's highlight is 4.70:1 at rest, so
   there no shade at all leaves it at 4.5:1), and the shadow and the
   slide carry the turn *)
fn _page_turn {left:nat | left >= 3600} (sheet: sheet(left, false, false)): [after:nat | after >= left - 3600] sheet(after, false, false) = let
  val sheet = rule(sheet, ".shade")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = lay(sheet, ZIndex(), "1")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = lay(sheet, Transition(), "background-color 80ms linear")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".turn")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = lay(sheet, ZIndex(), "2")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  (* idle, between turns: laid out (its copy ready) but not seen *)
  val sheet = rule(sheet, ".turn.idle")
  val sheet = lay(sheet, Visibility(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".turn.to-up,.turn.to-down")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".leaf")
  val sheet = lay(sheet, Flex(), "0 0 100%")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = lay(sheet, MinHeight(), "0")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = lay(sheet, BoxShadow(), "0 0 24px rgba(0,0,0,.4)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tgap")
  val sheet = lay(sheet, Flex(), "0 0 100%")
  val sheet = close(sheet)
  (* sliding right or down, the gap is first: the sheet rests at the
     strip's end *)
  val sheet = rule(sheet, ".turn.to-right .tgap,.turn.to-down .tgap")
  val sheet = lay(sheet, Order(), "-1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".turn.blank .tgap")
  val sheet = fill(sheet, RoleGround())
  val sheet = close(sheet)
  val sheet = _shade_rule(V_light_6 | sheet, Light(), 1, 6)
  val sheet = _shade_rule(V_light_12 | sheet, Light(), 2, 12)
  val sheet = _shade_rule(V_light_18 | sheet, Light(), 3, 18)
  val sheet = _shade_rule(V_light_24 | sheet, Light(), 4, 24)
  val sheet = _shade_rule(V_sepia_5 | sheet, Sepia(), 1, 5)
  val sheet = _shade_rule(V_sepia_10 | sheet, Sepia(), 2, 10)
  val sheet = _shade_rule(V_sepia_15 | sheet, Sepia(), 3, 15)
  val sheet = _shade_rule(V_sepia_20 | sheet, Sepia(), 4, 20)
  val sheet = _shade_rule(V_dark_2 | sheet, Dark(), 1, 2)
  val sheet = _shade_rule(V_dark_4 | sheet, Dark(), 2, 4)
  val sheet = _shade_rule(V_dark_6 | sheet, Dark(), 3, 6)
  val sheet = _shade_rule(V_dark_8 | sheet, Dark(), 4, 8)
  val sheet = _shade_rule(V_night_0 | sheet, Night(), 1, 0)
  val sheet = _shade_rule(V_night_0 | sheet, Night(), 2, 0)
  val sheet = _shade_rule(V_night_0 | sheet, Night(), 3, 0)
  val sheet = _shade_rule(V_night_0 | sheet, Night(), 4, 0)
  val sheet = _shade_rule(V_grey_2 | sheet, Grey(), 1, 2)
  val sheet = _shade_rule(V_grey_4 | sheet, Grey(), 2, 4)
  val sheet = _shade_rule(V_grey_6 | sheet, Grey(), 3, 6)
  val sheet = _shade_rule(V_grey_8 | sheet, Grey(), 4, 8)
in sheet end

(* The reading settings' sheet's tabs (app.bats's _settings), a line of
   their own under its title and Close, sharing it by their names'
   widths, and its panels, a column of rows as the sheet is; and its
   choices of where taps turn pages: a line each, a drawing of the
   page's zones beside the choice's name and what it does. The drawing is the
   page's ground framed by an edge, the back zone the line's colour and
   the forward zone the accent (no text: their font size is 0); a book
   read right to left has it mirrored (.taps.rtl). The drawing and the
   line take no taps, so a tap on them is the button's *)
fn _reading_settings {left:nat | left >= 4800} (sheet: sheet(left, false, false)): [after:nat | after >= left - 4800] sheet(after, false, false) = let
  val sheet = rule(sheet, ".shead")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".shead .tabs")
  val sheet = lay(sheet, Flex(), "1 0 100%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".shead .tab")
  val sheet = lay(sheet, Flex(), "1 1 auto")
  val sheet = lay(sheet, Padding(), "8px 4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabpanel")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "10px")
  val sheet = close(sheet)
  (* the panels, one over another in one cell, as tall as the tallest
     (#301): the one not chosen keeps its room, unseen, and so is
     neither focused nor read out *)
  val sheet = rule(sheet, ".tabpanels")
  val sheet = lay(sheet, Display(), "grid")
  val sheet = lay(sheet, GridTemplate(), "auto/minmax(0,1fr)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabpanels>.tabpanel")
  val sheet = lay(sheet, GridArea(), "1/1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabpanel.unchosen")
  val sheet = lay(sheet, Visibility(), "hidden")
  val sheet = close(sheet)
  (* a Settings row's button keeps its name on one line, and the state
     beside it (the Sync row's) wraps instead *)
  val sheet = rule(sheet, ".srow>.rowbtn")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* a row that opens a screen ends in a chevron, drawn and not part of its
     name (the empty alternative text), so the name is the row's words
     alone (WCAG 2.5.3, quire#361) *)
  val sheet = rule(sheet, ".chev::after")
  val () = raw(sheet, "content:\"\\203A\" / \"\";margin-left:8px;")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow.tapsrow")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, AlignItems(), "stretch")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tapsrow .slabel")
  val sheet = lay(sheet, Width(), "auto")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg.taps")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg button.tapbtn")
  val sheet = lay(sheet, Display(), "grid")
  val sheet = lay(sheet, GridTemplate(), "\"m n\" auto \"m a\" auto/32px 1fr")
  val sheet = lay(sheet, Gap(), "2px 12px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, TextAlign(), "start")
  val sheet = lay(sheet, Padding(), "8px 12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tapmap")
  val sheet = lay(sheet, GridArea(), "m")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Width(), "32px")
  val sheet = lay(sheet, Height(), "48px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, BorderRadius(), "4px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = fill(sheet, RoleGround())
  val sheet = line(sheet, AllSides(), 1, RoleEdge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tzb,.tzf")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tzb")
  val sheet = fill(sheet, RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tzf")
  val sheet = fill(sheet, RoleAccent())
  val sheet = close(sheet)
  (* sides: a quarter at each side, the middle the bars' *)
  val sheet = rule(sheet, ".sides .tzb")
  val sheet = lay(sheet, Inset(), "0 75% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sides .tzf")
  val sheet = lay(sheet, Inset(), "0 0 0 75%")
  val sheet = close(sheet)
  (* forward: under the top eighth (the bars'), a quarter back, the
     rest forward *)
  val sheet = rule(sheet, ".forward .tzb")
  val sheet = lay(sheet, Inset(), "12.5% 75% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".forward .tzf")
  val sheet = lay(sheet, Inset(), "12.5% 0 0 25%")
  val sheet = close(sheet)
  (* one hand: the top third back, the bottom third forward *)
  val sheet = rule(sheet, ".onehand .tzb")
  val sheet = lay(sheet, Inset(), "0 0 66.6% 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".onehand .tzf")
  val sheet = lay(sheet, Inset(), "66.6% 0 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .sides .tzb")
  val sheet = lay(sheet, Inset(), "0 0 0 75%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .sides .tzf")
  val sheet = lay(sheet, Inset(), "0 75% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .forward .tzb")
  val sheet = lay(sheet, Inset(), "12.5% 0 0 75%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .forward .tzf")
  val sheet = lay(sheet, Inset(), "12.5% 25% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tapabout")
  val sheet = lay(sheet, GridArea(), "a")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
in sheet end

(* The axes the page turn (gestures region 1, on .caf) owns: the
   stylesheet's touch-action for .caf comes from them, so the browser
   leaves exactly that axis to the recognizer *)
#pub fn page_turn_axes (): $GT.axes

implement page_turn_axes () = $GT.AxH()

#pub fn app_style (): [l:agz][k:nat | k < 65536] @($A.arr(byte, l, $B.BUILDER_CAP), int k)

implement app_style () = let
  val builder = $B.create()
  val sheet: sheet(BUDGET, false, false) = Sheet(builder)
  val sheet = _fonts(sheet)
  (* the light theme is also the root's, so the page behind the app has
     the palette too *)
  val sheet = theme(PAL0_bg(), PAL0_fg(), PAL0_muted(), PAL0_card(), PAL0_line(), PAL0_edge(),
    PAL0_bar(), PAL0_barfg(), PAL0_accent(), PAL0_accentfg(), PAL0_hl(), PAL0_barhi(),
    PAL0_banner(), PAL0_bannerfg(), PAL0_mark(), PAL0_markfg(), PAL0_danger(), PAL0_hl2(), H_light |
    sheet, Light(), 0xfaf8f5, 0x2a2a2a, 0x6b6b6b, 0xffffff, 0xdddddd, 0x8a8a8a,
    0x333333, 0xffffff, 0x2f6f4f, 0xffffff, 0xfde59a, 0x4a4a4a, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xb3261e, 0xfbc58a)
  val sheet = theme(PAL1_bg(), PAL1_fg(), PAL1_muted(), PAL1_card(), PAL1_line(), PAL1_edge(),
    PAL1_bar(), PAL1_barfg(), PAL1_accent(), PAL1_accentfg(), PAL1_hl(), PAL1_barhi(),
    PAL1_banner(), PAL1_bannerfg(), PAL1_mark(), PAL1_markfg(), PAL1_danger(), PAL1_hl2(), H_sepia |
    sheet, Sepia(), 0xf0e6d2, 0x3b2f22, 0x6e5e4a, 0xf7efdf, 0xd6c7a8, 0x8f7d62,
    0x4a3b2a, 0xf7efdf, 0x7a4f1d, 0xffffff, 0xe6cf8a, 0x5e4c38, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0x9c2a1c, 0xe8b880)
  val sheet = theme(PAL2_bg(), PAL2_fg(), PAL2_muted(), PAL2_card(), PAL2_line(), PAL2_edge(),
    PAL2_bar(), PAL2_barfg(), PAL2_accent(), PAL2_accentfg(), PAL2_hl(), PAL2_barhi(),
    PAL2_banner(), PAL2_bannerfg(), PAL2_mark(), PAL2_markfg(), PAL2_danger(), PAL2_hl2(), H_dark |
    sheet, Dark(), 0x1e1e1e, 0xe2e2e2, 0xa0a0a0, 0x2a2a2a, 0x3d3d3d, 0x7a7a7a,
    0x111111, 0xe2e2e2, 0x7fc49b, 0x10231a, 0x6d5e2f, 0x2e2e2e, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xffb4ab, 0x7b5831)
  val sheet = theme(PAL3_bg(), PAL3_fg(), PAL3_muted(), PAL3_card(), PAL3_line(), PAL3_edge(),
    PAL3_bar(), PAL3_barfg(), PAL3_accent(), PAL3_accentfg(), PAL3_hl(), PAL3_barhi(),
    PAL3_banner(), PAL3_bannerfg(), PAL3_mark(), PAL3_markfg(), PAL3_danger(), PAL3_hl2(), H_night |
    sheet, Night(), 0x1f1a14, 0xc2b296, 0x9a8a70, 0x2a231b, 0x3d342a, 0x857560,
    0x15110c, 0xc2b296, 0xc9a36b, 0x1f1a14, 0x4f4318, 0x342b21, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xe8a598, 0x5c3f1f)
  val sheet = theme(PAL4_bg(), PAL4_fg(), PAL4_muted(), PAL4_card(), PAL4_line(), PAL4_edge(),
    PAL4_bar(), PAL4_barfg(), PAL4_accent(), PAL4_accentfg(), PAL4_hl(), PAL4_barhi(),
    PAL4_banner(), PAL4_bannerfg(), PAL4_mark(), PAL4_markfg(), PAL4_danger(), PAL4_hl2(), H_grey |
    sheet, Grey(), 0x3a3a3a, 0xe2e2e2, 0xb8b8b8, 0x444444, 0x4f4f4f, 0x999999,
    0x2a2a2a, 0xe2e2e2, 0x8fd0a8, 0x10231a, 0x6d5e2f, 0x3d3d3d, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xffb4ab, 0x7b5831)
  val sheet = _base(sheet)
  val sheet = _shell(sheet)
  val sheet = _overlays(sheet)
  val sheet = _reader(sheet)
  val sheet = _page_turn(sheet)
  val sheet = _panels(sheet)
  val sheet = _reading_settings(sheet)
  val sheet = _switches(sheet)
  val sheet = _spacing(sheet)
  val sheet = _under_480px(sheet)
  val sheet = _under_600px(sheet)
  val sheet = rule(sheet, ".caf")
  val sheet = lay(sheet, TouchAction(), $GT.touch_action(page_turn_axes(), false))
  val sheet = close(sheet)
  val+ ~Sheet(builder) = sheet
  val @(bytes, length) = $B.to_arr(builder)
in @(bytes, length) end

end

