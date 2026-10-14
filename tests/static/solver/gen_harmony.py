#!/usr/bin/env python3
"""Writes the harmony fixtures (accept/harmony-boundaries.dats, reject/harmony-*.dats) from css's
harmony.bats (an archive or the file): HUE, CHROMA, CALM and SATNEAR claims at the exact boundary
computed here (accepted) and one step past it (rejected), for random colours.
usage: gen_harmony.py <css archive or harmony.bats> (run from here)"""
import math
import random
import re
import sys
import zipfile

path = sys.argv[1]
src = zipfile.ZipFile(path).read('src/harmony.bats').decode() if zipfile.is_zipfile(path) else open(path).read()
a = src.index('#pub dataprop RGB')
b = src.index('(* FAMILIES(')
body = src[a:b].replace('#pub ', '')
body = re.sub(r'\(\* LIGHTER.*?\n\n', '', body, flags=re.S)
body = re.sub(r'dataprop LIGHTER.*?\n\n', '', body, flags=re.S)


def n(x):
    return str(x) if x >= 0 else f'(0 - {-x})'

head = '#include "share/atspre_staload.hats"\n(* css harmony (RGB .. HUE), copied: see gen_harmony.py *)\n' + body + '\n'

rng = random.Random(594)


def hue(r, g, b):
    """(constructor, numerator, denominator) with hue = numerator / denominator degrees, as the constructors write it."""
    if r >= g >= b and r > b:
        return 'HUE_r_g_b', 60 * (g - b), r - b
    if g >= r >= b and g > b:
        return 'HUE_g_r_b', 120 * (g - b) - 60 * (r - b), g - b
    if g >= b >= r and g > r:
        return 'HUE_g_b_r', 120 * (g - r) + 60 * (b - r), g - r
    if b >= g >= r and b > r:
        return 'HUE_b_g_r', 240 * (b - r) - 60 * (g - r), b - r
    if b >= r >= g and b > g:
        return 'HUE_b_r_g', 240 * (b - g) + 60 * (r - g), b - g
    if r >= b >= g and r > g:
        return 'HUE_r_b_g', 360 * (r - g) - 60 * (b - g), r - g
    return None


accept, rejected = [], {'hue': 0, 'chroma': 0, 'satnear': 0, 'calm': 0}
for _ in range(60):
    c = rng.randrange(1 << 24)
    r, g, bl = c >> 16, (c >> 8) & 255, c & 255
    mx, mn = max(r, g, bl), min(r, g, bl)
    rgb = f'RGBc{{{r},{g},{bl}}}()'
    h = hue(r, g, bl)
    if h:
        ctor, num, den = h
        lo, hi = num // den, -(-num // den)   # the smallest interval holding the hue
        accept.append(f'prval _ : HUE({c}, {n(lo)}, {n(hi)}) = {ctor}({rgb})')
        if rejected['hue'] < 14:
            # the hue is not in [hi + 1, hi + 20] (or [lo - 20, lo - 1])
            bad = (hi + 1, hi + 20) if rng.random() < 0.5 else (lo - 20, lo - 1)
            open(f'reject/harmony-hue-{c:06x}-claims-{bad[0]}-{bad[1]}.dats'.replace('--', '-minus-'), 'w').write(
                head + f'prval _ : HUE({c}, {n(bad[0])}, {n(bad[1])}) = {ctor}({rgb})\n')
            rejected['hue'] += 1
    k = mx - mn
    accept.append(f'prval _ : CHROMA({c}, {k}) = CHROMAc(MXMN_{"rgb"}({rgb}))'.replace('MXMN_rgb', 'MXMN_' + ''.join(sorted('rgb', key=lambda ch: -[r, g, bl]['rgb'.index(ch)]))) if False else '')
    # CHROMA / CALM need the MXMN constructor of the channel order: pick it
    order = ''.join(sorted('rgb', key=lambda ch: (-[r, g, bl]['rgb'.index(ch)], 'rgb'.index(ch))))
    mxmn = f'MXMN_{order}({rgb})'
    accept = [x for x in accept if x]
    accept.append(f'prval _ : CHROMA({c}, {k}) = CHROMAc({mxmn})')
    if k > 0 and rejected['chroma'] < 10:
        open(f'reject/harmony-chroma-{c:06x}-claims-{k - 1}.dats', 'w').write(head + f'prval _ : CHROMA({c}, {k - 1}) = CHROMAc({mxmn})\n')
        rejected['chroma'] += 1
    calm = mx > 0 and 2 * (mx - mn) <= mx
    if calm:
        accept.append(f'prval _ : CALM({c}) = CALMc({mxmn})')
    elif rejected['calm'] < 8:
        open(f'reject/harmony-calm-{c:06x}-saturated.dats', 'w').write(head + f'prval _ : CALM({c}) = CALMc({mxmn})\n')
        rejected['calm'] += 1
# SATNEAR pairs
for _ in range(40):
    ca, cb = rng.randrange(1 << 24), rng.randrange(1 << 24)
    ch = lambda c: (c >> 16, (c >> 8) & 255, c & 255)
    ra, rb = ch(ca), ch(cb)
    amx, amn, bmx, bmn = max(ra), min(ra), max(rb), min(rb)
    if amx == 0 or bmx == 0:
        continue
    gap = abs((amx - amn) * bmx - (bmx - bmn) * amx)
    dmin = -(-100 * gap // (amx * bmx))

    def mx_of(c):
        r, g, bl = ch(c)
        order = ''.join(sorted('rgb', key=lambda x: (-[r, g, bl]['rgb'.index(x)], 'rgb'.index(x))))
        return f'MXMN_{order}(RGBc{{{r},{g},{bl}}}())'
    accept.append(f'prval _ : SATNEAR({ca}, {cb}, {dmin}) = SATNEARc({mx_of(ca)}, {mx_of(cb)})')
    if dmin >= 1 and rejected['satnear'] < 10:
        open(f'reject/harmony-satnear-{ca:06x}-{cb:06x}-claims-{dmin - 1}.dats', 'w').write(
            head + f'prval _ : SATNEAR({ca}, {cb}, {dmin - 1}) = SATNEARc({mx_of(ca)}, {mx_of(cb)})\n')
        rejected['satnear'] += 1
open('accept/harmony-boundaries.dats', 'w').write(head + '\n'.join(accept) + '\n')
print(len(accept), rejected)
