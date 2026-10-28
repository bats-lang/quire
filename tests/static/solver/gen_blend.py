#!/usr/bin/env python3
"""Writes the reading ruler's veil fixtures (accept/blend-boundaries.dats, reject/blend-*.dats): quire's
BLEND (src/palette.bats, the rounding of (c * (100 - strength) + v * strength) / 100, a colour under a
veil of the page's ground v) at the exact value (accepted) and one more or less (rejected). Needs accept/contrast-boundaries.dats (gen_contrast.py) for the LIN table.
usage: gen_blend.py (run from here)"""
import random
import re

t = open('accept/contrast-boundaries.dats').read()
lin = t[t.index('dataprop LIN'):t.index('dataprop LUM')]
shade = '''dataprop BLEND(int, int, int, int) =
  | {r,g,b,vr,vg,vb,blended_r,blended_g,blended_b:nat | r < 256; g < 256; b < 256; vr < 256; vg < 256; vb < 256}{strength:nat | strength <= 100}
    {rl,rh,gl,gh,bl,bh,vrl,vrh,vgl,vgh,vbl,vbh,srl,srh,sgl,sgh,sbl,sbh:int |
     100 * blended_r <= r * (100 - strength) + vr * strength + 50; r * (100 - strength) + vr * strength + 50 < 100 * blended_r + 100;
     100 * blended_g <= g * (100 - strength) + vg * strength + 50; g * (100 - strength) + vg * strength + 50 < 100 * blended_g + 100;
     100 * blended_b <= b * (100 - strength) + vb * strength + 50; b * (100 - strength) + vb * strength + 50 < 100 * blended_b + 100}
    BLENDc(r * 65536 + g * 256 + b, vr * 65536 + vg * 256 + vb, strength, blended_r * 65536 + blended_g * 256 + blended_b) of
      (LIN(r, rl, rh), LIN(g, gl, gh), LIN(b, bl, bh),
       LIN(vr, vrl, vrh), LIN(vg, vgl, vgh), LIN(vb, vbl, vbh),
       LIN(blended_r, srl, srh), LIN(blended_g, sgl, sgh), LIN(blended_b, sbl, sbh))
'''
head = '#include "share/atspre_staload.hats"\n(* quire BLEND, copied: see gen_blend.py *)\n' + lin + shade + '\n'


def lin_(v):
    return f'LIN_{v:02x}()'


def stmt(c, v, s, sc):
    r, g, b = c >> 16, (c >> 8) & 255, c & 255
    vr, vg, vb = v >> 16, (v >> 8) & 255, v & 255
    sr, sg, sb = sc >> 16, (sc >> 8) & 255, sc & 255
    return (f'prval _ : BLEND({c}, {v}, {s}, {sc}) = BLENDc({lin_(r)}, {lin_(g)}, {lin_(b)}, '
            f'{lin_(vr)}, {lin_(vg)}, {lin_(vb)}, {lin_(sr)}, {lin_(sg)}, {lin_(sb)})')


rng = random.Random(566)
accept, rejected = [], 0
for _ in range(60):
    c, v, s = rng.randrange(1 << 24), rng.randrange(1 << 24), rng.choice([0, 10, 25, 33, 50, 70, 90, 100])
    ch = [c >> 16, (c >> 8) & 255, c & 255]
    vh = [v >> 16, (v >> 8) & 255, v & 255]
    sh = [(x * (100 - s) + y * s + 50) // 100 for x, y in zip(ch, vh)]
    sc = sh[0] * 65536 + sh[1] * 256 + sh[2]
    accept.append(stmt(c, v, s, sc))
    if rejected < 16:
        i = rng.randrange(3)
        bad = list(sh)
        bad[i] = bad[i] + 1 if bad[i] < 255 else bad[i] - 1
        open(f'reject/blend-{c:06x}-under-{v:06x}-at-{s}-channel{i}-off-by-one.dats', 'w').write(
            head + stmt(c, v, s, bad[0] * 65536 + bad[1] * 256 + bad[2]) + '\n')
        rejected += 1
open('accept/blend-boundaries.dats', 'w').write(head + '\n'.join(accept) + '\n')
