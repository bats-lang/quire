#!/usr/bin/env python3
"""Writes a reject fixture for each guard of each dataprop constructor of src/ (quire#839, piece of #594).

A dataprop is a statement the compiler trusts as it is written: the guard of a constructor
(`{octet:int | 0 <= octet; octet < 256}`) is what the solver must prove wherever the constructor is
used. `mutation_check.py` mutates lemmas, so a guard that someone loosened, or dropped, would change
what every proof built on it says and nothing would fail. For each atom of each guard (`octet < 256`)
the fixture is the dataprop, with what it uses, copied from the module (proof_sources.py), and a probe

    prfn probe_<atom> {the constructor's variables, that atom shifted by one} (its premises): <its result> = <constructor>(premises)

which states the constructor under a guard that is weaker by one (`octet < 257`; `a <= b` becomes
`a <= b + 1`, `a > b` becomes `a + 1 > b`, an `==` becomes `<=` one more, an atom with `!=` or `||`
is dropped; `2*low_half + 1 < 65536` moves by two, as its left side steps by two and one more
would leave the same integers). The constructor still needs the real atom, so the solver must reject the probe. One
atom is shifted in each fixture and the others stay, so a guard that is loosened or an atom that
is dropped from the dataprop makes the probe of that atom type-check, and the fixture fails.
patsopt reports the first unsolved constraint of a file only, so each probe is a file of its own
(reject/dataprop-guard-<constructor>-<atom>.dats, with its .expect). FALSEP's constructor, whose two
atoms exclude each other, is covered by reject/falsep-made-at-*.dats, which make it at the
values next to the guard.

usage: gen_guards.py [--list [--atoms]] [--check] [--lock bats.lock] [--repository DIR]
  --list   the dataprop constructors of src/ with a guard, their atoms and fixtures
  --check  writes nothing; fails when a fixture differs from what the modules give now, is missing,
           or belongs to no atom
"""
import argparse
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
import proof_sources as sources  # noqa: E402

# the constructors whose atoms exclude each other: no single shift makes them satisfiable
COVERED_ELSEWHERE = {'FALSEP_mk': 'falsep-made-at-zero, falsep-made-at-one, falsep-made-at-wide-value'}
# an atom whose left side steps by two (2*low_half + 1) has the same integers when its bound moves by one (accept/by-hand-step1-odd-parity.dats): it moves by two
SHIFT_BY = {('STEP1_odd', '2*low_half + 1 < 65536'): 2}
# an atom the others imply (the solver, with the atom one weaker, still proves the constructor's own atom): the probe
# is accepted, so it is written to accept/ as the proof that the atom is redundant, not to reject/ as a false variant
REDUNDANT = {
    ('ENC_three', '0 <= high'): '2048 <= point and point == 4096 * high + 64 * middle + low with middle, low <= 63 leave no high below 0',
    ('ENC_four', '0 <= top'): '65536 <= point and point == 262144 * top + 4096 * high + 64 * middle + low with high, middle, low <= 63 leave no top below 0',
}
OPERATORS = [('<=', 'le'), ('>=', 'ge'), ('==', 'eq'), ('!=', 'ne'), ('<', 'lt'), ('>', 'gt')]


def balanced(text, start):
    """The index after the group that opens at text[start]."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] in '({[':
            depth += 1
        elif text[index] in ')}]':
            depth -= 1
            if depth == 0:
                return index + 1
    raise ValueError(f'unbalanced: {text[start:start + 60]!r}')


def split_top(text, separator):
    """The pieces of text at the separator outside any bracket (a `||` is not a `|`)."""
    pieces, depth, current = [], 0, ''
    index = 0
    while index < len(text):
        c = text[index]
        if c in '({[':
            depth += 1
        elif c in ')}]':
            depth -= 1
        if c == separator and depth == 0 and text[index:index + 2] != separator * 2 and text[index - 1:index + 1] != separator * 2:
            pieces.append(current)
            current = ''
        else:
            current += c
        index += 1
    pieces.append(current)
    return pieces


def constructors(block):
    """[(dataprop, name, groups, indices, premises)] of a dataprop block and the `and` dataprops after it;
    a group is (variables, [atoms], opening, closing)."""
    out = []
    sections = re.split(r'(?m)^and\s+(?=\w+\s*\()', block.text)
    for number, section in enumerate(sections):
        m = re.match(r'\s*(?:#pub\s+)?(?:dataprop\s+)?(\w+)\s*(?:\([^)]*\))?\s*=' if number else
                     r'\s*(?:#pub\s+)?dataprop\s+(\w+)\s*(?:\([^)]*\))?\s*=', section)
        out += constructors_of(m.group(1), section[m.end():])
    return out


def constructors_of(dataprop, body):
    out = []
    for text in split_top(body, '|')[1:]:
        text, groups, index = text.strip(), [], 0
        while index < len(text) and text[index] in '{[':
            end = balanced(text, index)
            inner = text[index + 1:end - 1]
            parts = split_top(inner, '|')
            atoms = [a.strip() for a in split_top(parts[1], ';') if a.strip()] if len(parts) > 1 else []
            groups.append((text[index] + parts[0].strip(), atoms, text[index], text[end - 1]))
            index = end
            while index < len(text) and text[index].isspace():
                index += 1
        name = re.match(r"[A-Za-z_][\w']*", text[index:]).group(0)
        index += len(name)
        indices = text[index:balanced(text, index)] if text[index:index + 1] == '(' else '()'
        index += len(indices)
        rest = text[index:].strip()
        premises = []
        if rest.startswith('of'):
            rest = rest[2:].strip()
            if rest.startswith('(') and balanced(rest, 0) == len(rest):
                premises = [p.strip() for p in split_top(rest[1:-1], ',') if p.strip()]
            else:
                premises = [rest]
        out.append((dataprop, name, groups, indices, premises))
    return out


def weaken(atom, amount=1):
    """The atom one weaker, or None when it has no bound to shift."""
    if '||' in atom or '&&' in atom or '!=' in atom:
        return None
    for symbol, _ in OPERATORS:
        parts = split_top_operator(atom, symbol)
        if parts:
            left, right = parts
            if symbol in ('<', '<=', '=='):
                return f'{left} {"<=" if symbol == "==" else symbol} ({right}) + {amount}'
            return f'({left}) + {amount} {symbol} {right}'
    raise ValueError(f'no comparison in {atom!r}')


def split_top_operator(atom, symbol):
    depth = 0
    for index in range(len(atom)):
        if atom[index] in '({[':
            depth += 1
        elif atom[index] in ')}]':
            depth -= 1
        elif depth == 0 and atom.startswith(symbol, index):
            # `<` must not be the start of `<=`, nor `>` of `>=`
            if symbol in '<>' and atom[index + 1:index + 2] == '=':
                continue
            return atom[:index].strip(), atom[index + len(symbol):].strip()
    return None


def slug(atom):
    words = atom
    for symbol, word in OPERATORS:
        words = words.replace(symbol, f' {word} ')
    words = re.sub(r'[^A-Za-z0-9]+', '-', words.replace('||', ' or ').replace('+', ' plus ').replace('*', ' times ').replace('-', ' minus ')).strip('-')
    return re.sub(r'-+', '-', words).lower()


def probes(world, prefixes=('src/',)):
    """[(fixture name, module, block, constructor, atom, text, dataprop, control)]"""
    out = []
    for source in sorted(world.modules):
        if not source.startswith(prefixes):
            continue
        for block in world.modules[source]:
            if block.kind != 'dataprop':
                continue
            for dataprop, name, groups, indices, premises in constructors(block):
                if not any(atoms for _, atoms, _, _ in groups):
                    continue
                if name in COVERED_ELSEWHERE:
                    out.append((None, source, block, name, None, None, dataprop, None))
                    continue
                seen = {}
                for g, (variables, atoms, opening, closing) in enumerate(groups):
                    for a, atom in enumerate(atoms):
                        amount = SHIFT_BY.get((name, atom), 1)
                        weak = weaken(atom, amount)
                        shifted = []
                        for h, (vs, ats, op, cl) in enumerate(groups):
                            kept = [(weak if (h, i) == (g, a) else x) for i, x in enumerate(ats)]
                            kept = [x for x in kept if x]
                            shifted.append(vs + (' | ' + '; '.join(kept) if kept else '') + cl)
                        control_groups = ''.join(vs + (' | ' + '; '.join(ats) if ats else '') + cl for vs, ats, op, cl in groups)
                        arguments = ', '.join(f'premise{i}: {p}' for i, p in enumerate(premises, 1))
                        explicit = ''.join('{' + vs[1:].split(':')[0].strip() + '}' for vs, ats, op, cl in groups)
                        applied = f'{name}{explicit}({", ".join(f"premise{i}" for i in range(1, len(premises) + 1))})'
                        probe_name = 'probe_' + slug(atom).replace('-', '_')
                        text = (f'prfn {probe_name} {"".join(shifted)} ({arguments}): {dataprop}{indices} = {applied}')
                        control = f'prfn control_{name.lower()} {control_groups} ({arguments}): {dataprop}{indices} = {applied}'
                        base = f'dataprop-guard-{name.lower().replace("_", "-")}-{slug(atom)}'
                        seen[base] = seen.get(base, 0) + 1
                        fixture = base if seen[base] == 1 else f'{base}-{seen[base]}'
                        out.append((fixture, source, block, name, atom, text, dataprop, control))
    return out


def satisfiable(world, prefixes):
    """[(fixture name, module, block, dataprop, constructor, text)]: the constructor's guards, all of
    them, hold of some values: `[1 == 2] void` under them must be rejected."""
    out = []
    for source in sorted(world.modules):
        if not source.startswith(prefixes):
            continue
        for block in world.modules[source]:
            if block.kind != 'dataprop':
                continue
            for dataprop, name, groups, indices, premises in constructors(block):
                if name in COVERED_ELSEWHERE or not any(atoms for _, atoms, _, _ in groups):
                    continue
                shown = ''.join(vs + (' | ' + '; '.join(ats) if ats else '') + cl for vs, ats, op, cl in groups)
                text = f'prfn satisfiable_{name.lower()} {shown} (): [1 == 2] void = ()'
                out.append((f'dataprop-satisfiable-{name.lower().replace("_", "-")}', source, block, dataprop, name, text))
    return out


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--lock', default=str(ROOT / 'bats.lock'))
    parser.add_argument('--repository', default=os.environ.get('BATS_REPOSITORY'))
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--atoms', action='store_true', help='with --list: each atom and its fixture')
    args = parser.parse_args(argv)
    world = sources.World(ROOT, args.lock, args.repository)
    files, constructors_seen = {}, 0
    listing, satisfiable_listing = [], []
    last = None
    controls = {}
    for fixture, source, block, name, atom, text, dataprop, control in probes(world):
        if (source, dataprop, name) != last:
            constructors_seen += 1
            last = (source, dataprop, name)
            listing.append([source, block.first_line, dataprop, name, []])
        if fixture is None:
            continue
        controls.setdefault((source, block.first_line), (block, [], dataprop))[1].append(control)
        listing[-1][4].append((atom, weaken(atom, SHIFT_BY.get((name, atom), 1)), fixture))
        redundant = REDUNDANT.get((name, atom))
        if redundant:
            header = (f'(* quire {source} {dataprop}, copied: see gen_guards.py.\n'
                      f'   Redundant guard atom `{atom}` of {name}: the others imply it ({redundant}), so the constructor is still made with it shifted to `{weaken(atom)}` *)\n')
        else:
            header = (f'(* quire {source} {dataprop}, copied: see gen_guards.py.\n'
                      f'   False variant: the guard atom `{atom}` of {name} shifted by {SHIFT_BY.get((name, atom), 1)}: `{weaken(atom, SHIFT_BY.get((name, atom), 1)) or "dropped"}` *)\n')
        body = sources.fixture_text(world, [block], header)
        files[HERE / ('accept' if redundant else 'reject') / f'{fixture}.dats'] = body + '\n' + re.sub(r'\$[A-Z]+\.', '', text) + '\n'
    satisfiable_seen = 0
    for fixture, source, block, dataprop, name, text in satisfiable(world, ('src/', 'css:')):
        satisfiable_seen += 1
        satisfiable_listing.append((source, block.first_line, dataprop, name, fixture))
        header = (f'(* {source} {dataprop}, copied: see gen_guards.py.\n'
                  f'   Probe: every guard of {name} holds of some values, so `[1 == 2] void` under them is false and rejected *)\n')
        files[HERE / 'reject' / f'{fixture}.dats'] = sources.fixture_text(world, [block], header) + '\n' + re.sub(r'\$[A-Z]+\.', '', text) + '\n'
    for (source, _), (block, texts, dataprop) in controls.items():
        header = (f'(* quire {source} {block.name}, copied: see gen_guards.py.\n'
                  f'   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)\n')
        unique = list(dict.fromkeys(texts))
        files[HERE / 'accept' / f'dataprop-guard-{block.name.lower()}-constructors.dats'] = (
            sources.fixture_text(world, [block], header) + '\n' + '\n'.join(re.sub(r'\$[A-Z]+\.', '', t) for t in unique) + '\n')
    if args.list:
        for source, line, dataprop, name, atoms in listing:
            where = COVERED_ELSEWHERE.get(name)
            print(f'{source}:{line} dataprop {dataprop} constructor {name}: '
                  + (f'its guard atoms exclude each other; covered by reject/{where}' if where else f'{len(atoms)} guard atoms'))
            if args.atoms:
                for atom, weak, fixture in atoms:
                    print(f'    {atom!r} shifted to {weak!r} -> reject/{fixture}.dats')
        if args.atoms:
            for source, line, dataprop, name, fixture in satisfiable_listing:
                print(f'    satisfiable: {source}:{line} {dataprop} {name} -> reject/{fixture}.dats')
        print(f'{constructors_seen} dataprop constructors with a guard in src/, {len(files) - len(controls) - satisfiable_seen} guard atoms, {len(files) - len(controls)} reject fixtures (with {satisfiable_seen} satisfiability probes) and {len(controls)} accept controls')
        return 0
    bad = 0
    for path, text in sorted(files.items()):
        if args.check:
            if not path.exists() or path.read_text() != text:
                print(f'FAIL {path.relative_to(ROOT)} is not what the modules give now: run gen_guards.py')
                bad += 1
        else:
            path.write_text(text)
    if args.check:
        for path in sorted(list((HERE / 'reject').glob('dataprop-*.dats')) + list((HERE / 'accept').glob('dataprop-*.dats'))):
            if path not in files:
                print(f'FAIL {path.relative_to(ROOT)} is the fixture of no guard atom')
                bad += 1
        print(f'{constructors_seen} dataprop constructors, {len(files)} fixtures checked, {bad} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
