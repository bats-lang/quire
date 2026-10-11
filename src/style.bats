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
   colours proven.

   The sheet is written by modules, each with its own .sats, so a change
   (or a static fixture put into a module) re-checks that module and
   what stages after it, not the whole: palette.bats (the roles and the
   statements of what is proven), palette_proofs.bats (the proofs,
   written by scripts/gen-harmony.py), sheet.bats (the builder, rules,
   layout declarations and the spacing scale), declarations.bats (the
   declarations that name a colour, under their proofs), theme_rules.bats
   (the themes and the base rules), and the screens' rules
   (shell_rules, overlay_rules, reader_rules, page_turn_rules,
   panel_rules, reading_settings_rules, adaptive_rules). This module
   puts them in order. *)


#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use builder as B

staload GT = "gestures/src/tracker.sats"

staload "palette.sats"
staload "palette_proofs.sats"
staload "sheet.sats"
staload "declarations.sats"
staload "theme_rules.sats"
staload "shell_rules.sats"
staload "overlay_rules.sats"
staload "reader_rules.sats"
staload "page_turn_rules.sats"
staload "panel_rules.sats"
staload "reading_settings_rules.sats"
staload "adaptive_rules.sats"

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
  val sheet = theme_rule(PAL0_bg(), PAL0_fg(), PAL0_muted(), PAL0_card(), PAL0_line(), PAL0_edge(),
    PAL0_bar(), PAL0_barfg(), PAL0_accent(), PAL0_accentfg(), PAL0_hl(), PAL0_barhi(),
    PAL0_banner(), PAL0_bannerfg(), PAL0_mark(), PAL0_markfg(), PAL0_danger(), PAL0_hl2(), H_light |
    sheet, Light(), 0xfaf8f5, 0x2a2a2a, 0x6b6b6b, 0xffffff, 0xdddddd, 0x8a8a8a,
    0x333333, 0xffffff, 0x2f6f4f, 0xffffff, 0xfde59a, 0x4a4a4a, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xb3261e, 0xfbc58a)
  val sheet = theme_rule(PAL1_bg(), PAL1_fg(), PAL1_muted(), PAL1_card(), PAL1_line(), PAL1_edge(),
    PAL1_bar(), PAL1_barfg(), PAL1_accent(), PAL1_accentfg(), PAL1_hl(), PAL1_barhi(),
    PAL1_banner(), PAL1_bannerfg(), PAL1_mark(), PAL1_markfg(), PAL1_danger(), PAL1_hl2(), H_sepia |
    sheet, Sepia(), 0xf0e6d2, 0x3b2f22, 0x6e5e4a, 0xf7efdf, 0xd6c7a8, 0x8f7d62,
    0x4a3b2a, 0xf7efdf, 0x7a4f1d, 0xffffff, 0xe6cf8a, 0x5e4c38, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0x9c2a1c, 0xe8b880)
  val sheet = theme_rule(PAL2_bg(), PAL2_fg(), PAL2_muted(), PAL2_card(), PAL2_line(), PAL2_edge(),
    PAL2_bar(), PAL2_barfg(), PAL2_accent(), PAL2_accentfg(), PAL2_hl(), PAL2_barhi(),
    PAL2_banner(), PAL2_bannerfg(), PAL2_mark(), PAL2_markfg(), PAL2_danger(), PAL2_hl2(), H_dark |
    sheet, Dark(), 0x1e1e1e, 0xe2e2e2, 0xa0a0a0, 0x2a2a2a, 0x3d3d3d, 0x7a7a7a,
    0x111111, 0xe2e2e2, 0x7fc49b, 0x10231a, 0x6d5e2f, 0x2e2e2e, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xffb4ab, 0x7b5831)
  val sheet = theme_rule(PAL3_bg(), PAL3_fg(), PAL3_muted(), PAL3_card(), PAL3_line(), PAL3_edge(),
    PAL3_bar(), PAL3_barfg(), PAL3_accent(), PAL3_accentfg(), PAL3_hl(), PAL3_barhi(),
    PAL3_banner(), PAL3_bannerfg(), PAL3_mark(), PAL3_markfg(), PAL3_danger(), PAL3_hl2(), H_night |
    sheet, Night(), 0x1f1a14, 0xc2b296, 0x9a8a70, 0x2a231b, 0x3d342a, 0x857560,
    0x15110c, 0xc2b296, 0xc9a36b, 0x1f1a14, 0x4f4318, 0x342b21, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xe8a598, 0x5c3f1f)
  val sheet = theme_rule(PAL4_bg(), PAL4_fg(), PAL4_muted(), PAL4_card(), PAL4_line(), PAL4_edge(),
    PAL4_bar(), PAL4_barfg(), PAL4_accent(), PAL4_accentfg(), PAL4_hl(), PAL4_barhi(),
    PAL4_banner(), PAL4_bannerfg(), PAL4_mark(), PAL4_markfg(), PAL4_danger(), PAL4_hl2(), H_grey |
    sheet, Grey(), 0x3a3a3a, 0xe2e2e2, 0xb8b8b8, 0x444444, 0x4f4f4f, 0x999999,
    0x2a2a2a, 0xe2e2e2, 0x8fd0a8, 0x10231a, 0x6d5e2f, 0x3d3d3d, 0xfbe3e1, 0x6b1d16,
    0xffb300, 0x000000, 0xffb4ab, 0x7b5831)
  val sheet = base_rules(sheet)
  val sheet = shell_rules(sheet)
  val sheet = overlay_rules(sheet)
  val sheet = reader_rules(sheet)
  val sheet = page_turn_rules(sheet)
  val sheet = panel_rules(sheet)
  val sheet = reading_settings_rules(sheet)
  val sheet = switch_rules(sheet)
  val sheet = spacing_rules(sheet)
  val sheet = under_480px_rules(sheet)
  val sheet = under_600px_rules(sheet)
  val sheet = rule(sheet, ".caf")
  val sheet = lay(sheet, TouchAction(), $GT.touch_action(page_turn_axes(), false))
  val sheet = close(sheet)
  val+ ~Sheet(builder) = sheet
  val @(bytes, length) = $B.to_arr(builder)
in @(bytes, length) end

end
