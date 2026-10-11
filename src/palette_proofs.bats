(* palette_proofs -- the proofs about the palette (palette.bats), checked by
   the solver: every pair of text and ground the sheet sets together,
   every control edge, each theme's harmony and the page turn's shade at
   each strength. The proofs between BEGIN and END are written by
   scripts/gen-harmony.py from PAL, which only picks which constructor
   applies to a colour: the solver checks every proof, so a palette that
   breaks a rule does not type-check. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use css as C
staload CT = "css/src/contrast.sats"
staload H = "css/src/harmony.sats"

staload "palette.sats"

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

(* BEGIN proofs: written by scripts/gen-harmony.py *)

#pub prval S_fg_bg: SURF(FG, BG)

primplement S_fg_bg = SURFc(
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

#pub prval S_fg_card: SURF(FG, CARD)

primplement S_fg_card = SURFc(
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

#pub prval S_fg_line: SURF(FG, LINE)

primplement S_fg_line = SURFc(
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

#pub prval S_fg_hl: SURF(FG, HL)

primplement S_fg_hl = SURFc(
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

#pub prval S_fg_hl2: SURF(FG, HL2)

primplement S_fg_hl2 = SURFc(
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

#pub prval S_muted_bg: SURF(MUTED, BG)

primplement S_muted_bg = SURFc(
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

#pub prval S_muted_card: SURF(MUTED, CARD)

primplement S_muted_card = SURFc(
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

#pub prval S_accent_bg: SURF(ACCENT, BG)

primplement S_accent_bg = SURFc(
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

#pub prval S_accent_card: SURF(ACCENT, CARD)

primplement S_accent_card = SURFc(
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

#pub prval S_accentfg_accent: SURF(ACCENTFG, ACCENT)

primplement S_accentfg_accent = SURFc(
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

#pub prval S_barfg_bar: SURF(BARFG, BAR)

primplement S_barfg_bar = SURFc(
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

#pub prval S_barfg_barhi: SURF(BARFG, BARHI)

primplement S_barfg_barhi = SURFc(
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

#pub prval S_bannerfg_banner: SURF(BANNERFG, BANNER)

primplement S_bannerfg_banner = SURFc(
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

#pub prval S_markfg_mark: SURF(MARKFG, MARK)

primplement S_markfg_mark = SURFc(
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

#pub prval S_danger_card: SURF(DANGER, CARD)

primplement S_danger_card = SURFc(
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

#pub prval S_danger_line: SURF(DANGER, LINE)

primplement S_danger_line = SURFc(
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

#pub prval E_edge_card: EDGEP(EDGE, CARD)

primplement E_edge_card = EDGEc(
  PAL0_edge(), PAL0_card(), $CT.CONTRAST_lighter_second(L_8a8a8a, L_ffffff),
  PAL1_edge(), PAL1_card(), $CT.CONTRAST_lighter_second(L_8f7d62, L_f7efdf),
  PAL2_edge(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7a7a7a, L_2a2a2a),
  PAL3_edge(), PAL3_card(), $CT.CONTRAST_lighter_first(L_857560, L_2a231b),
  PAL4_edge(), PAL4_card(), $CT.CONTRAST_lighter_first(L_999999, L_444444))

#pub prval E_accent_card: EDGEP(ACCENT, CARD)

primplement E_accent_card = EDGEc(
  PAL0_accent(), PAL0_card(), $CT.CONTRAST_lighter_second(L_2f6f4f, L_ffffff),
  PAL1_accent(), PAL1_card(), $CT.CONTRAST_lighter_second(L_7a4f1d, L_f7efdf),
  PAL2_accent(), PAL2_card(), $CT.CONTRAST_lighter_first(L_7fc49b, L_2a2a2a),
  PAL3_accent(), PAL3_card(), $CT.CONTRAST_lighter_first(L_c9a36b, L_2a231b),
  PAL4_accent(), PAL4_card(), $CT.CONTRAST_lighter_first(L_8fd0a8, L_444444))

#pub prval E_barfg_bar: EDGEP(BARFG, BAR)

primplement E_barfg_bar = EDGEc(
  PAL0_barfg(), PAL0_bar(), $CT.CONTRAST_lighter_first(L_ffffff, L_333333),
  PAL1_barfg(), PAL1_bar(), $CT.CONTRAST_lighter_first(L_f7efdf, L_4a3b2a),
  PAL2_barfg(), PAL2_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_111111),
  PAL3_barfg(), PAL3_bar(), $CT.CONTRAST_lighter_first(L_c2b296, L_15110c),
  PAL4_barfg(), PAL4_bar(), $CT.CONTRAST_lighter_first(L_e2e2e2, L_2a2a2a))

#pub prval H_light: HARMONY(PaletteLight)

primplement H_light = HARMONYc(
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

#pub prval H_sepia: HARMONY(PaletteSepia)

primplement H_sepia = HARMONYc(
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

#pub prval H_dark: HARMONY(PaletteDark)

primplement H_dark = HARMONYc(
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

#pub prval H_night: HARMONY(PaletteNight)

primplement H_night = HARMONYc(
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

#pub prval H_grey: HARMONY(PaletteGrey)

primplement H_grey = HARMONYc(
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

#pub prval V_light_6: VEILED(PaletteLight, 6)

primplement V_light_6 = VEILEDc(
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

#pub prval V_light_12: VEILED(PaletteLight, 12)

primplement V_light_12 = VEILEDc(
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

#pub prval V_light_18: VEILED(PaletteLight, 18)

primplement V_light_18 = VEILEDc(
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

#pub prval V_light_24: VEILED(PaletteLight, 24)

primplement V_light_24 = VEILEDc(
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

#pub prval V_sepia_5: VEILED(PaletteSepia, 5)

primplement V_sepia_5 = VEILEDc(
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

#pub prval V_sepia_10: VEILED(PaletteSepia, 10)

primplement V_sepia_10 = VEILEDc(
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

#pub prval V_sepia_15: VEILED(PaletteSepia, 15)

primplement V_sepia_15 = VEILEDc(
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

#pub prval V_sepia_20: VEILED(PaletteSepia, 20)

primplement V_sepia_20 = VEILEDc(
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

#pub prval V_dark_2: VEILED(PaletteDark, 2)

primplement V_dark_2 = VEILEDc(
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

#pub prval V_dark_4: VEILED(PaletteDark, 4)

primplement V_dark_4 = VEILEDc(
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

#pub prval V_dark_6: VEILED(PaletteDark, 6)

primplement V_dark_6 = VEILEDc(
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

#pub prval V_dark_8: VEILED(PaletteDark, 8)

primplement V_dark_8 = VEILEDc(
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

#pub prval V_night_0: VEILED(PaletteNight, 0)

primplement V_night_0 = VEILEDc(
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

#pub prval V_grey_2: VEILED(PaletteGrey, 2)

primplement V_grey_2 = VEILEDc(
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

#pub prval V_grey_4: VEILED(PaletteGrey, 4)

primplement V_grey_4 = VEILEDc(
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

#pub prval V_grey_6: VEILED(PaletteGrey, 6)

primplement V_grey_6 = VEILEDc(
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

#pub prval V_grey_8: VEILED(PaletteGrey, 8)

primplement V_grey_8 = VEILEDc(
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

end
