#!/usr/bin/env python3
"""Writes the contrast fixtures (accept/contrast-boundaries.dats, reject/contrast-*.dats) from css's
table (a css archive or contrast.bats): for each colour pair the largest ratio (in tenths) the
constructors of CONTRAST admit, computed here with the same interval arithmetic, is claimed
(accept), and one tenth more (reject). usage: gen_contrast.py <css archive or contrast.bats> (run from here)"""
import random
import re
import sys
import zipfile

path = sys.argv[1]
src = zipfile.ZipFile(path).read('src/contrast.bats').decode() if zipfile.is_zipfile(path) else open(path).read()
lin = re.findall(r'\| LIN_([0-9a-f]{2})\((\d+), (\d+), (\d+)\)', src)
assert len(lin) == 256
table = {int(v): (int(lo), int(hi)) for _, v, lo, hi in lin}
hats = ('dataprop LIN(int, int, int) =\n' + '\n'.join(f'  | LIN_{h}({v}, {lo}, {hi})' for h, v, lo, hi in lin) + '''

dataprop LUM(int, int, int) =
  | {r,g,b:nat | r < 256; g < 256; b < 256}{rl,rh,gl,gh,bl,bh:int}
    LUMc(r * 65536 + g * 256 + b,
         2126 * rl + 7152 * gl + 722 * bl, 2126 * rh + 7152 * gh + 722 * bh) of
      (LIN(r, rl, rh), LIN(g, gl, gh), LIN(b, bl, bh))

dataprop CONTRAST(int, int, int) =
  | {a,b,k:int}{alo,ahi,blo,bhi:int | 10 * (alo + 50000000) >= k * (bhi + 50000000)}
    CONTRAST_lighter_first(a, b, k) of (LUM(a, alo, ahi), LUM(b, blo, bhi))
  | {a,b,k:int}{alo,ahi,blo,bhi:int | 10 * (blo + 50000000) >= k * (ahi + 50000000)}
    CONTRAST_lighter_second(a, b, k) of (LUM(a, alo, ahi), LUM(b, blo, bhi))
''')


def lum(c):
    r, g, b = c >> 16, (c >> 8) & 255, c & 255
    return (2126 * table[r][0] + 7152 * table[g][0] + 722 * table[b][0],
            2126 * table[r][1] + 7152 * table[g][1] + 722 * table[b][1])


def kmax(a, b):
    alo, ahi = lum(a)
    blo, bhi = lum(b)
    k1 = (10 * (alo + 50000000)) // (bhi + 50000000)
    k2 = (10 * (blo + 50000000)) // (ahi + 50000000)
    return (k1, 'first') if k1 >= k2 else (k2, 'second')


def term(c):
    return f'LUMc(LIN_{c >> 16:02x}(), LIN_{(c >> 8) & 255:02x}(), LIN_{c & 255:02x}())'


def stmt(a, b, k, which):
    return f'prval _ : CONTRAST({a}, {b}, {k}) = CONTRAST_lighter_{which}({term(a)}, {term(b)})'


rng = random.Random(594)
pairs = [(0xffffff, 0x000000), (0x2a2a2a, 0xfaf8f5), (0xe2e2e2, 0x1e1e1e), (0x777777, 0xffffff),
         (0x767676, 0xffffff), (0xb3261e, 0xffffff), (0x6b6b6b, 0xfaf8f5), (0x808080, 0x7f7f7f)]
while len(pairs) < 40:
    pairs.append((rng.randrange(1 << 24), rng.randrange(1 << 24)))
head = '#include "share/atspre_staload.hats"\n(* css CONTRAST, copied: see gen_contrast.py *)\n' + hats + '\n'
accept, rejected = [], 0
for a, b in pairs:
    k, which = kmax(a, b)
    if k < 0 or k > 400:
        continue
    accept.append(stmt(a, b, k, which))
    if rejected < 24:
        open(f'reject/contrast-{a:06x}-on-{b:06x}-claims-{k + 1}.dats', 'w').write(head + stmt(a, b, k + 1, which) + '\n')
        rejected += 1
open('accept/contrast-boundaries.dats', 'w').write(head + '\n'.join(accept) + '\n')
