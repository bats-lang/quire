#!/usr/bin/env python3
"""Makes assets/fonts/material-symbols-subset.woff2, the icons' face.

Material Symbols Outlined (Apache-2.0) from the npm package
material-symbols at VERSION, set at its default style (no fill, weight
400, grade 0, 24 px optical size) and cut to the glyphs ui.bats's
_glyph shows, at their code points in the Private Use Area; no
ligatures. Needs fonttools and brotli (pip install fonttools brotli).

    python3 scripts/icon-font.py
"""
import io, os, subprocess, tarfile, tempfile
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

VERSION = '0.47.6'
# ui.bats's _glyph: each icon's Material Symbols name and code point
ICONS = {
    'arrow_back': 0xe5c4, 'close': 0xe5cd, 'settings': 0xe8b8,
    'bookmark_add': 0xe598, 'bookmark_added': 0xe599, 'search': 0xe8b6,
    'chevron_left': 0xe5cb, 'chevron_right': 0xe5cc, 'toc': 0xe8de,
    'edit_note': 0xe745, 'match_case': 0xf6f1, 'more_vert': 0xe5d4,
    'volume_up': 0xe050, 'skip_previous': 0xe045, 'skip_next': 0xe044,
    'add': 0xe145, 'sort': 0xe164,
}
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts', 'material-symbols-subset.woff2')

with tempfile.TemporaryDirectory() as work:
    subprocess.run(['npm', 'pack', f'material-symbols@{VERSION}', '--pack-destination', work], check=True, capture_output=True)
    with tarfile.open(os.path.join(work, f'material-symbols-{VERSION}.tgz')) as package:
        data = package.extractfile('package/material-symbols-outlined.woff2').read()
font = TTFont(io.BytesIO(data))
font = instancer.instantiateVariableFont(font, {'FILL': 0, 'GRAD': 0, 'opsz': 24, 'wght': 400})
options = subset.Options()
options.layout_features = []
options.flavor = 'woff2'
options.name_IDs = ['*']
options.notdef_outline = True
options.desubroutinize = True
subsetter = subset.Subsetter(options)
subsetter.populate(unicodes=list(ICONS.values()))
subsetter.subset(font)
missing = [name for name, code in ICONS.items() if code not in font.getBestCmap()]
assert not missing, f'not in the font: {missing}'
subset.save_font(font, OUT, options)
print(OUT, os.path.getsize(OUT), 'bytes')
