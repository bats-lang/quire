#!/usr/bin/env python3
"""Element ids, checked from the source: every element's id is made at
one place in the code, no numbered id (nid_make) can spell another id,
and every id the code names is one it makes.

Elements are made by ui.bats's constructors (ui_el, ui_add, ...), whose
second argument is the id, and by helpers that pass one of their own
parameters on to them (app.bats's _row, say): those are found here, so
a literal handed to a helper counts where the helper makes it. A harm's
menu item takes its id from ui_harm_id. Numbered ids are a prefix, a
number and an optional suffix (nid_make, nid_make2), so each prefix is a
family of ids, and neither a literal id nor another family may be one
of its members.

Ids are named (for a text, a class, a listener, a comparison with an
event's target) by the functions in NAMERS, and by helpers that pass a
parameter on to one; each named literal must be a made id, one of a
family's, or the page's own (bats-root). No id of pwa's page scripts
(pwa-*) is named: what they did is quire's own now (bats-lang/pwa#49).

usage: tests/static/ids.py <src-dir>...   (exit 1 on any finding)
"""
import re
import sys
from pathlib import Path

# constructor -> the positions of the ids it makes (its parent's is 0)
MAKERS = {name: (1,) for name in (
    'ui_el', 'ui_add', 'ui_text_btn', 'ui_icon_btn', 'ui_menuitem',
    'ui_field', 'ui_img', 'ui_file_input', 'ui_link_out', 'ui_link_out_https', 'ui_link_out_path', 'ui_tab',
)}
# a range row: its label, its input and its value
MAKERS['ui_range'] = (1, 3, 6)
# function -> the positions of its arguments that name an element
NAMERS = {name: (0,) for name in (
    'ui_clear', 'ui_attr', 'ui_attr_buf', 'ui_place', 'ui_class', 'ui_show',
    'ui_text', 'ui_text_buf', 'ui_text_long', 'ui_tone', 'ui_role',
    'ui_named', 'ui_measure', 'ui_focus', 'ui_harm_item', 'OnEl', 'OnPointer',
    'ui_pointer_capture',
    'ui_option', 'ui_src_empty',
)}
NAMERS['ui_labelled'] = (0, 2)
NAMERS['_is'] = (1,)
for maker in MAKERS:
    NAMERS[maker] = (0,)
# function -> the numbered ids it makes or names: each the position of
# its prefix argument, and its suffix (none, an argument's position, or
# the suffix itself); the family is all of prefix + number + suffix
NUMBERED = {'nid_make': [(0, None)], 'nid_make2': [(0, 2)], 'nid_pad3': [(0, None)]}
# prefix arguments compared with an event's target (a row's number is
# read after them)
PREFIX_NAMERS = {'_row_of': 1}
PAGE_IDS = {'bats-root'}

STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
DEFN = re.compile(r'^(?:#pub\s+)?(?:fn|fun)\s+(\w+)\s*((?:\{[^}]*\}\s*)*)\(', re.M)


def strip_comments(text):
    """The text with (* ... *) comments blanked (nested), strings kept."""
    out, i, depth, n = [], 0, 0, len(text)
    while i < n:
        if depth == 0 and text[i] == '"':
            m = STRING.match(text, i)
            if m:
                out.append(m.group(0))
                i = m.end()
                continue
        if text.startswith('(*', i):
            depth += 1
            out.append('  ')
            i += 2
        elif depth and text.startswith('*)', i):
            depth -= 1
            out.append('  ')
            i += 2
        else:
            out.append(text[i] if depth == 0 or text[i] == '\n' else ' ')
            i += 1
    return ''.join(out)


def args_at(text, i):
    """The arguments of the call whose '(' is at text[i], each stripped,
    and the index after its ')'; nested parentheses and strings kept."""
    args, depth, start, j = [], 0, i + 1, i
    while j < len(text):
        c = text[j]
        if c == '"':
            m = STRING.match(text, j)
            j = m.end() if m else j + 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                args.append(text[start:j].strip())
                return args, j + 1
        elif c == ',' and depth == 1:
            args.append(text[start:j].strip())
            start = j + 1
        j += 1
    return args, j


def literal(arg):
    m = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', arg)
    return m.group(1) if m else None


def calls(text, name):
    """(line, args) of each call of name in text."""
    for m in re.finditer(r'(?<![\w$.])' + re.escape(name) + r'\s*\(', text):
        args, _ = args_at(text, m.end() - 1)
        yield text.count('\n', 0, m.start()) + 1, args


def definitions(text):
    """(name, parameters, body) of each fn/fun in text."""
    found = list(DEFN.finditer(text))
    for k, m in enumerate(found):
        params_args, after = args_at(text, m.end() - 1)
        params = [p.split(':')[0].strip() for p in params_args]
        end = found[k + 1].start() if k + 1 < len(found) else len(text)
        yield m.group(1), params, text[after:end]


def find_helpers(sources):
    """Adds to MAKERS, NAMERS and NUMBERED the helpers that pass a
    parameter on to one of them, until nothing changes."""
    changed = True
    while changed:
        changed = False
        for _, text in sources:
            for name, params, body in definitions(text):
                if name.startswith('ui_') or name in ('nid_make', 'nid_make2', 'nid_pad3'):
                    continue
                made, named, numbered = set(), set(), set()

                def param_at(args, pos):
                    if pos is not None and len(args) > pos and args[pos] in params:
                        return params.index(args[pos])
                    return None
                for fn, poss in list(MAKERS.items()):
                    for _, args in calls(body, fn):
                        made |= {param_at(args, pos) for pos in poss} - {None}
                for fn, poss in list(NAMERS.items()):
                    for _, args in calls(body, fn):
                        named |= {param_at(args, pos) for pos in poss} - {None}
                for fn, specs in list(NUMBERED.items()):
                    for _, args in calls(body, fn):
                        for pre, suf in specs:
                            if param_at(args, pre) is None:
                                continue
                            if isinstance(suf, int):
                                lit = literal(args[suf]) if len(args) > suf else None
                                suf = lit if lit is not None else param_at(args, suf)
                            numbered.add((param_at(args, pre), suf))
                named -= made
                if made and MAKERS.get(name) != tuple(sorted(made)):
                    MAKERS[name] = tuple(sorted(made))
                    changed = True
                if named and NAMERS.get(name) != tuple(sorted(named)):
                    NAMERS[name] = tuple(sorted(named))
                    changed = True
                if numbered and set(NUMBERED.get(name, [])) != numbered:
                    NUMBERED[name] = sorted(numbered, key=repr)
                    changed = True


def harm_ids(sources):
    """The ids ui_harm_id gives."""
    for _, text in sources:
        for name, _, body in definitions(text):
            if name in ('_harm_id', 'ui_harm_id'):
                for m in re.finditer(r'=>\s*"([^"]+)"', body):
                    yield m.group(1)


def family_regex(prefix, suffix):
    return re.compile(re.escape(prefix) + r'[0-9]+' + re.escape(suffix or '') + r'\Z')


def main(dirs):
    files = [p for d in dirs for p in sorted(Path(d).rglob('*.bats'))]
    sources = [(p, strip_comments(p.read_text())) for p in files]
    find_helpers(sources)
    problems = []

    made = {}  # id -> [where]
    for path, text in sources:
        for fn, poss in MAKERS.items():
            for line, args in calls(text, fn):
                for pos in poss:
                    if len(args) > pos and literal(args[pos]) is not None:
                        made.setdefault(literal(args[pos]), []).append(f'{path}:{line}')
    for h in harm_ids(sources):
        made.setdefault(h, []).append('ui_harm_id')

    families = {}  # (prefix, suffix) -> first place
    for path, text in sources:
        for fn, specs in NUMBERED.items():
            for line, args in calls(text, fn):
                for pre_pos, suf in specs:
                    if len(args) <= pre_pos or literal(args[pre_pos]) is None:
                        continue
                    if isinstance(suf, int):
                        suf = literal(args[suf]) if len(args) > suf else None
                        if suf is None:
                            continue
                    families.setdefault((literal(args[pre_pos]), suf or ''), f'{path}:{line}')

    for ident, where in sorted(made.items()):
        if len(where) > 1:
            problems.append(f'id "{ident}" is made at {len(where)} places: {", ".join(where)}')
        if ident in PAGE_IDS:
            problems.append(f'id "{ident}" is the page\'s own, made at {where[0]}')
        for (pre, suf), fwhere in families.items():
            if family_regex(pre, suf).match(ident):
                problems.append(f'id "{ident}" ({where[0]}) is a numbered id of "{pre}"+n+"{suf}" ({fwhere})')

    fams = sorted(families)
    for a in range(len(fams)):
        for b in range(len(fams)):
            if a == b:
                continue
            (pa, sa), (pb, sb) = fams[a], fams[b]
            other = family_regex(pb, sb)
            if any(other.match(f'{pa}{k}{sa}') for k in range(1000)):
                if a < b or not any(family_regex(pa, sa).match(f'{pb}{k}{sb}') for k in range(1000)):
                    problems.append(f'numbered ids "{pa}"+n+"{sa}" ({families[fams[a]]}) and '
                                    f'"{pb}"+n+"{sb}" ({families[fams[b]]}) can be the same')

    def known(ident):
        return (ident in made or ident in PAGE_IDS
                or any(family_regex(p, s).match(ident) for p, s in families))

    for path, text in sources:
        for fn, poss in NAMERS.items():
            for line, args in calls(text, fn):
                for pos in poss:
                    if len(args) > pos and literal(args[pos]) is not None and not known(literal(args[pos])):
                        problems.append(f'{path}:{line}: {fn} names "{literal(args[pos])}", which no element has')
        for fn, pos in PREFIX_NAMERS.items():
            for line, args in calls(text, fn):
                if len(args) > pos and literal(args[pos]) is not None:
                    pre = literal(args[pos])
                    if not any(p == pre for p, _ in families):
                        problems.append(f'{path}:{line}: {fn} reads rows "{pre}"+n, which no numbered id has')

    for p in sorted(set(problems)):
        print(p)
    print(f'{len(made)} ids made, {len(families)} numbered families, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:] or ['src']))
