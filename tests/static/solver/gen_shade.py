#!/usr/bin/env python3
"""Writes the page-turn shade fixtures (accept/shade-boundaries.dats, reject/shade-*.dats): quire's
SHADE (src/palette.bats, the rounding of r * (100 - strength) / 100) at the exact value (accepted)
and one more or less (rejected). Needs accept/contrast-boundaries.dats (gen_contrast.py) for the LIN table.
usage: gen_shade.py (run from here)"""
import random
import re

t = open('accept/contrast-boundaries.dats').read()
lin = t[t.index('dataprop LIN'):t.index('dataprop LUM')]
shade = '''dataprop SHADE(int, int, int) =
  | {r,g,b,shaded_r,shaded_g,shaded_b:nat | r < 256; g < 256; b < 256}{strength:nat | strength <= 100}
    {rl,rh,gl,gh,bl,bh,srl,srh,sgl,sgh,sbl,sbh:int |
     100 * shaded_r <= r * (100 - strength) + 50; r * (100 - strength) + 50 < 100 * shaded_r + 100;
     100 * shaded_g <= g * (100 - strength) + 50; g * (100 - strength) + 50 < 100 * shaded_g + 100;
     100 * shaded_b <= b * (100 - strength) + 50; b * (100 - strength) + 50 < 100 * shaded_b + 100}
    SHADEc(r * 65536 + g * 256 + b, strength, shaded_r * 65536 + shaded_g * 256 + shaded_b) of
      (LIN(r, rl, rh), LIN(g, gl, gh), LIN(b, bl, bh),
       LIN(shaded_r, srl, srh), LIN(shaded_g, sgl, sgh), LIN(shaded_b, sbl, sbh))
'''
head = '#include "share/atspre_staload.hats"\n(* quire SHADE, copied: see gen_shade.py *)\n' + lin + shade + '\n'


def lin_(v):
    return f'LIN_{v:02x}()'


def stmt(c, s, sc):
    r, g, b = c >> 16, (c >> 8) & 255, c & 255
    sr, sg, sb = sc >> 16, (sc >> 8) & 255, sc & 255
    return (f'prval _ : SHADE({c}, {s}, {sc}) = SHADEc({lin_(r)}, {lin_(g)}, {lin_(b)}, '
            f'{lin_(sr)}, {lin_(sg)}, {lin_(sb)})')


rng = random.Random(594)
accept, rejected = [], 0
for _ in range(60):
    c, s = rng.randrange(1 << 24), rng.choice([0, 10, 25, 33, 50, 70, 90, 100])
    ch = [c >> 16, (c >> 8) & 255, c & 255]
    sh = [(x * (100 - s) + 50) // 100 for x in ch]
    sc = sh[0] * 65536 + sh[1] * 256 + sh[2]
    accept.append(stmt(c, s, sc))
    if rejected < 16:
        i = rng.randrange(3)
        bad = list(sh)
        bad[i] = bad[i] + 1 if bad[i] < 255 else bad[i] - 1
        open(f'reject/shade-{c:06x}-at-{s}-channel{i}-off-by-one.dats', 'w').write(
            head + stmt(c, s, bad[0] * 65536 + bad[1] * 256 + bad[2]) + '\n')
        rejected += 1
open('accept/shade-boundaries.dats', 'w').write(head + '\n'.join(accept) + '\n')
