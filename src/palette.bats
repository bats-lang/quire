(* palette -- the stylesheet's roles and colours, and what is proven of them

   A role is a custom property set per theme; PAL says which colour a
   theme gives a role (the one place the palette's colours enter: the
   themes' custom properties are written from it), and the proofs about
   the pairs the sheet uses are statements over it: SURF (text on its
   ground, 4.5:1 and not vibrating), EDGEP (a control's edge, 3:1),
   HARMONY (a theme follows css's harmony rules), VEILED (the page
   turn's shade leaves the page legible). They are stated here and
   proven in palette_proofs.bats, which scripts/gen-harmony.py writes, so
   a change to the sheet's rules re-checks none of it, and a snippet put
   in this module (a static fixture about the roles) costs only this
   module. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use css as C
staload CT = "css/src/contrast.sats"
staload H = "css/src/harmony.sats"

(* A role is a custom property, --<name>, set per theme *)
#pub datasort colour_role =
  | BG | FG | MUTED | CARD | LINE | EDGE | BAR | BARFG | ACCENT | ACCENTFG | HL | BARHI | BANNER | BANNERFG | MARK | MARKFG | DANGER | HL2

(* A role as a value, indexed by the role it is *)
#pub datatype role_value(colour_role) =
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

(* A role's custom property, --<name> *)
#pub fn role_name {role:colour_role} (role: role_value(role)): [length:pos | length <= 9] string length

implement role_name (role) =
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

(* PAL(t, r, c): in theme t, role r is the colour 0xc *)
#pub dataprop PAL(palette, colour_role, int) =
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

(* SURF(text, ground): text in role text on role ground is at least
   4.5:1 in every theme, and does not vibrate on it (one of them is
   calm); EDGEP(edge, ground): a control's edge in role edge on ground
   is at least 3:1 *)
#pub dataprop SURF(colour_role, colour_role) =
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

#pub dataprop EDGEP(colour_role, colour_role) =
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
#pub dataprop FAM(palette, int, int, int, int, int, int) =
  | FAM_light(PaletteLight, 25, 50, 135, 165, ~15, 15) of $H.FAMILIES(25, 50, 135, 165, ~15, 15)
  | FAM_sepia(PaletteSepia, 25, 50, 25, 50, ~15, 15) of $H.FAMILIES(25, 50, 25, 50, ~15, 15)
  | FAM_dark(PaletteDark, 25, 50, 130, 160, ~15, 15) of $H.FAMILIES(25, 50, 130, 160, ~15, 15)
  | FAM_night(PaletteNight, 25, 50, 25, 50, ~15, 15) of $H.FAMILIES(25, 50, 25, 50, ~15, 15)
  | FAM_grey(PaletteGrey, 25, 50, 130, 160, ~15, 15) of $H.FAMILIES(25, 50, 130, 160, ~15, 15)

(* A theme with dark text on a light ground asks nothing more; one with
   light text on a dark ground (Material's dark theme) has a ground that
   is not black, text that is not pure white, and an accent, a danger
   colour and control edges that are desaturated (calm) *)
#pub dataprop MODE(int, int, int, int, int, int) =
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
#pub dataprop HARMONY(palette) =
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
   (shade_rule) *)
#pub dataprop SHADE(int, int, int) =
  | {r,g,b,shaded_r,shaded_g,shaded_b:nat | r < 256; g < 256; b < 256}{strength:nat | strength <= 100}
    {rl,rh,gl,gh,bl,bh,srl,srh,sgl,sgh,sbl,sbh:int |
     100 * shaded_r <= r * (100 - strength) + 50; r * (100 - strength) + 50 < 100 * shaded_r + 100;
     100 * shaded_g <= g * (100 - strength) + 50; g * (100 - strength) + 50 < 100 * shaded_g + 100;
     100 * shaded_b <= b * (100 - strength) + 50; b * (100 - strength) + 50 < 100 * shaded_b + 100}
    SHADEc(r * 65536 + g * 256 + b, strength, shaded_r * 65536 + shaded_g * 256 + shaded_b) of
      ($CT.LIN(r, rl, rh), $CT.LIN(g, gl, gh), $CT.LIN(b, bl, bh),
       $CT.LIN(shaded_r, srl, srh), $CT.LIN(shaded_g, sgl, sgh), $CT.LIN(shaded_b, sbl, sbh))

#pub dataprop SHADED(palette, colour_role, colour_role, int, int) =
  | {t:palette}{text,ground:colour_role}{strength,k:int}{text_colour,ground_colour,text_shaded,ground_shaded:int}
    SHADEDc(t, text, ground, strength, k) of (
      PAL(t, text, text_colour), PAL(t, ground, ground_colour),
      SHADE(text_colour, strength, text_shaded), SHADE(ground_colour, strength, ground_shaded),
      $CT.CONTRAST(text_shaded, ground_shaded, k))

#pub dataprop VEILED(palette, int) =
  | {t:palette}{strength:int}
    VEILEDc(t, strength) of (
      SHADED(t, FG, BG, strength, 70), SHADED(t, ACCENT, BG, strength, 45),
      SHADED(t, FG, HL, strength, 45), SHADED(t, FG, HL2, strength, 45),
      SHADED(t, MARKFG, MARK, strength, 45))

end
