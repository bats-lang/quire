#!/usr/bin/env python3
"""Writes src/theme.bats from css/app.css: the stylesheet as one string
literal (joined into a line; the CSS uses no double quotes or
backslashes, so the literal needs no escapes)."""
import os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
css = open(os.path.join(root, 'css', 'app.css')).read()
css = ''.join(l.strip() for l in css.splitlines())
assert '"' not in css and '\\' not in css
n = len(css.encode('utf-8'))
assert n < 65536
open(os.path.join(root, 'src', 'theme.bats'), 'w').write(f'''(* theme -- quire's stylesheet (generated from css/app.css by
   scripts/gen-theme.py: edit the CSS and run the script) *)

#include "share/atspre_staload.hats"

#pub fun app_css (): string({n})

implement app_css () = "{css}"
''')
print(n)
