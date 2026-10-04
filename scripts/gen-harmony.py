#!/usr/bin/env python3
"""Writes the palette's proofs into src/style.bats, between the BEGIN and
END proofs markers: SURF and EDGEP for the text/ground and edge pairs
the sheet uses, and HARMONY for each theme. The colours are read from
PAL in the same file. This script only picks which constructor applies
to each colour, and writes one even for a colour that breaks a rule:
the constraint solver checks every proof, so such a palette does not
type-check, whatever this script writes."""
import os, re
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "src", "style.bats")
src = open(path).read()

pal = {}
for t, role, c in re.findall(r"PAL(\d)_(\w+)\(\w+, \w+, 0x([0-9a-f]{6})\)", src):
    pal[(int(t), role)] = int(c, 16)
THEMES = (0, 1, 2, 3, 4)
NAMES = {0: "light", 1: "sepia", 2: "dark", 3: "night", 4: "grey"}
# each theme's index in the palette datasort
PALETTES = {0: "PaletteLight", 1: "PaletteSepia", 2: "PaletteDark", 3: "PaletteNight", 4: "PaletteGrey"}

# Text on a ground (SURF, 4.5:1) and control edges (EDGEP, 3:1)
SURFS = [("fg", "bg"), ("fg", "card"), ("fg", "line"), ("fg", "hl"), ("fg", "hl2"), ("muted", "bg"),
         ("muted", "card"), ("accent", "bg"), ("accent", "card"), ("accentfg", "accent"),
         ("barfg", "bar"), ("barfg", "barhi"), ("bannerfg", "banner"), ("markfg", "mark"),
         ("danger", "card"), ("danger", "line")]
EDGES = [("edge", "card"), ("accent", "card"), ("barfg", "bar")]

# Each theme's hue families: the first is its neutrals' tint
FAM = {0: ((25, 50), (135, 165), (-15, 15)),
       1: ((25, 50), (25, 50), (-15, 15)),
       2: ((25, 50), (130, 160), (-15, 15)),
       3: ((25, 50), (25, 50), (-15, 15)),
       4: ((25, 50), (130, 160), (-15, 15))}
NEUTRALS = ["bg", "fg", "muted", "card", "line", "edge", "bar", "barfg", "barhi"]
OTHERS = ["accent", "accentfg", "hl", "banner", "bannerfg", "mark", "markfg", "danger", "hl2"]
ROLES = ["bg", "fg", "muted", "card", "line", "edge", "bar", "barfg", "accent", "accentfg",
         "hl", "barhi", "banner", "bannerfg", "mark", "markfg", "danger", "hl2"]

def ch(c): return (c >> 16) & 255, (c >> 8) & 255, c & 255
def chroma(c): v = ch(c); return max(v) - min(v)
def calm(c): v = ch(c); return 2 * (max(v) - min(v)) <= max(v)
def sint(n): return str(n) if n >= 0 else f"~{-n}"
def rgb(c): r, g, b = ch(c); return f"$H.RGBc{{0x{r:02x},0x{g:02x},0x{b:02x}}}()"
ORD = [("rgb", 0, 1, 2), ("rbg", 0, 2, 1), ("grb", 1, 0, 2), ("gbr", 1, 2, 0), ("brg", 2, 0, 1), ("bgr", 2, 1, 0)]
def mxmn(c):
    v = ch(c)
    for o, x, y, z in ORD:
        if v[x] >= v[y] >= v[z]: return f"$H.MXMN_{o}({rgb(c)})"
SEXT = [("r_g_b", lambda r, g, b: r >= g >= b and r > b, lambda r, g, b: (r - b, 60 * (g - b))),
        ("g_r_b", lambda r, g, b: g >= r >= b and g > b, lambda r, g, b: (g - b, 120 * (g - b) - 60 * (r - b))),
        ("g_b_r", lambda r, g, b: g >= b >= r and g > r, lambda r, g, b: (g - r, 120 * (g - r) + 60 * (b - r))),
        ("b_g_r", lambda r, g, b: b >= g >= r and b > r, lambda r, g, b: (b - r, 240 * (b - r) - 60 * (g - r))),
        ("b_r_g", lambda r, g, b: b >= r >= g and b > g, lambda r, g, b: (b - g, 240 * (b - g) + 60 * (r - g))),
        ("r_b_g", lambda r, g, b: r >= b >= g and r > g, lambda r, g, b: (r - g, 360 * (r - g) - 60 * (b - g)))]
def fits(c, lo, hi):
    r, g, b = ch(c)
    for n, ok, f in SEXT:
        if ok(r, g, b):
            C, HC = f(r, g, b)
            if any(lo * C <= HC + o * C <= hi * C for o in (0, -360, 360)): return True
    return False
def hue(c, lo, hi):
    r, g, b = ch(c)
    for n, ok, f in SEXT:
        if not ok(r, g, b): continue
        C, HC = f(r, g, b)
        for off, tag in ((0, ""), (-360, "_down"), (360, "_up")):
            if lo * C <= HC + off * C <= hi * C:
                return f"$H.HUE_{n}{tag}{{0x{c:06x},0x{r:02x},0x{g:02x},0x{b:02x},{sint(lo)},{sint(hi)}}}({rgb(c)})"
    # none fits: the solver rejects the base form
    for n, ok, f in SEXT:
        if ok(r, g, b):
            return f"$H.HUE_{n}{{0x{c:06x},0x{r:02x},0x{g:02x},0x{b:02x},{sint(lo)},{sint(hi)}}}({rgb(c)})"
    return f"$H.HUE_r_g_b{{0x{c:06x},0x{r:02x},0x{g:02x},0x{b:02x},{sint(lo)},{sint(hi)}}}({rgb(c)})"
def lin(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
def lum(c): r, g, b = ch(c); return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
def L(c): return f"L_{c:06x}"
def contrast(a, b):
    side = "first" if lum(a) > lum(b) else "second"
    return f"$CT.CONTRAST_lighter_{side}({L(a)}, {L(b)})"
def novib(f, b):
    if calm(f): return f"$H.NOVIB_text($H.CALMc({mxmn(f)}))"
    # neither is calm: the solver rejects this
    return f"$H.NOVIB_ground($H.CALMc({mxmn(b)}))"

out = []
for f, b in SURFS:
    parts = []
    for t in THEMES:
        fc, bc = pal[(t, f)], pal[(t, b)]
        parts.append(f"PAL{t}_{f}(), PAL{t}_{b}(), {contrast(fc, bc)},\n    {novib(fc, bc)}")
    out.append(f"prval S_{f}_{b} = SURFc(\n  " + ",\n  ".join(parts) + ")")
for e, b in EDGES:
    parts = [f"PAL{t}_{e}(), PAL{t}_{b}(), {contrast(pal[(t, e)], pal[(t, b)])}" for t in THEMES]
    out.append(f"prval E_{e}_{b} = EDGEc(\n  " + ",\n  ".join(parts) + ")")

for t in THEMES:
    P = lambda r: pal[(t, r)]
    fam = FAM[t]
    (l1, h1) = fam[0]
    arcs = ", ".join(f"{sint(lo)}, {sint(hi)}" for lo, hi in fam)
    args = [", ".join(f"PAL{t}_{r}()" for r in ROLES)]
    args.append(f"FAM_{NAMES[t]}($H.FAMILIESc())")
    for r in NEUTRALS:
        c = P(r)
        args.append(f"$H.NEUTRAL_grey($H.CHROMAc({mxmn(c)}))" if chroma(c) <= 4 else
                    f"$H.NEUTRAL_tint($H.CHROMAc({mxmn(c)}), {hue(c, l1, h1)})")
    for r in OTHERS:
        c = P(r)
        if chroma(c) <= 4:
            args.append(f"$H.IN3_grey($H.CHROMAc({mxmn(c)}))"); continue
        # the family it is in; in none, the solver rejects the first
        i = next((i for i, a in enumerate(fam) if fits(c, *a)), 0)
        args.append(f"$H.IN3_{i + 1}($H.FAMILIESc(), {hue(c, *fam[i])})")
    for r, lo, hi in [("danger", -15, 15), ("banner", -15, 15), ("bannerfg", -15, 15), ("hl", 30, 60), ("mark", 30, 60), ("hl2", 30, 60)]:
        args.append(hue(P(r), lo, hi))
    args.append(f"$H.SATNEARc({mxmn(P('accent'))}, {mxmn(P('danger'))})")
    args.append(f"$H.LIGHTERc({L(P('card'))}, {L(P('bg'))})")
    args.append(contrast(P("fg"), P("bg")))
    if lum(P("fg")) > lum(P("bg")):
        args.append(f"MODE_dark($H.LIGHTERc({L(P('fg'))}, {L(P('bg'))}), $H.PEAKc({mxmn(P('bg'))}),\n    "
                    f"$H.PEAKc({mxmn(P('fg'))}), $H.PEAKc({mxmn(P('barfg'))}),\n    "
                    f"$H.CALMc({mxmn(P('accent'))}), $H.CALMc({mxmn(P('danger'))}), $H.CALMc({mxmn(P('edge'))}))")
    else:
        args.append(f"MODE_light($H.LIGHTERc({L(P('bg'))}, {L(P('fg'))}))")
    out.append(f"prval H_{NAMES[t]}: HARMONY({PALETTES[t]}) = HARMONYc(\n  " + ",\n  ".join(args) + ")")

# The page turn's shade: black at each strength over the page (its
# four levels' strengths, the strongest last) leaves every pair the
# page shows legible (VEILED): its text at 7:1, the rest at 4.5:1
SHADES = {0: (6, 12, 18, 24), 1: (5, 10, 15, 20), 2: (2, 4, 6, 8), 3: (0,), 4: (2, 4, 6, 8)}
VEILED = [("fg", "bg", 70), ("accent", "bg", 45), ("fg", "hl", 45), ("fg", "hl2", 45), ("markfg", "mark", 45)]
ROLE_STATIC = {"fg": "FG", "bg": "BG", "accent": "ACCENT", "hl": "HL", "hl2": "HL2", "markfg": "MARKFG", "mark": "MARK"}
def shaded(c, strength):
    return sum(((v * (100 - strength) + 50) // 100) << s for v, s in zip(ch(c), (16, 8, 0)))
def lin_of(v): return f"$CT.LIN_{v:02x}()"
def lum_of(c): return "$CT.LUMc(" + ", ".join(lin_of(v) for v in ch(c)) + ")"
def shade_proof(c, strength):
    return "SHADEc(" + ", ".join(lin_of(v) for v in ch(c) + ch(shaded(c, strength))) + ")"
for t in THEMES:
    for strength in SHADES[t]:
        parts = []
        for f, b, k in VEILED:
            fs, bs = shaded(pal[(t, f)], strength), shaded(pal[(t, b)], strength)
            side = "first" if lum(fs) > lum(bs) else "second"
            parts.append(f"SHADEDc(PAL{t}_{f}(), PAL{t}_{b}(),\n    {shade_proof(pal[(t, f)], strength)},\n    "
                         f"{shade_proof(pal[(t, b)], strength)},\n    $CT.CONTRAST_lighter_{side}({lum_of(fs)}, {lum_of(bs)}))")
        out.append(f"prval V_{NAMES[t]}_{strength}: VEILED({t}, {strength}) = VEILEDc(\n  " + ",\n  ".join(parts) + ")")

begin = "(* BEGIN proofs: written by scripts/gen-harmony.py *)"
end = "(* END proofs *)"
i, j = src.index(begin), src.index(end)
src = src[:i + len(begin)] + "\n" + "\n".join(out) + "\n" + src[j:]
open(path, "w").write(src)
