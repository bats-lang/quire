#!/usr/bin/env python3
"""The proofs of the modules and locked packages, as standalone ATS (quire#837, piece of #594).

The fixtures of tests/static/solver/ are generated from the text of the proofs, not retyped: a
fixture holds the declarations a proof uses (`closure`), as the module states them, so a change
to a lemma or a dataprop changes what the fixture says and the generator's --check fails until
the fixture is written again. This file reads `.bats` text into top-level declaration blocks
(the heads proofs_audit.py knows), follows the names a block mentions, and writes the blocks as
a `.dats` that needs only the prelude (`dats_text`).

A name used as `$A.cells` (a package alias) is looked up in the package `PROVIDERS` names, so
that a fixture holds array's `cells` and `NTH` and css's `LIN` as the locked packages state them.
"""
import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from proofs_audit import strip  # noqa: E402  (comments and strings blanked, lines kept)

# the alias a module gives a package -> the package and the file of it whose declarations it names
PROVIDERS = {
    'A': ('array', 'src/lib.bats'),
    'AR': ('arith', 'src/lib.bats'),
    'CT': ('css', 'src/contrast.bats'),
    'H': ('css', 'src/harmony.bats'),
}
HEAD = re.compile(
    r"^(?P<pub>#pub\s+)?(?P<kind>datasort|sortdef|dataprop|dataview|prfun|prfn|primplement|praxi|stadef|propdef|absprop)\s+"
    r"(?:\{[^{}]*\}\s*)*(?P<name>[A-Za-z_][\w']*)")
CONTINUATION = re.compile(r'^(?:in|end|and|then|else|with)\b')
TOKEN = re.compile(r"(?<![\w'$])\$?[A-Za-z_][\w']*(?:\.[A-Za-z_][\w']*)?")


class Block:
    """One top-level declaration: its kind, name, text, where it is, and whether it is a #pub prfun
    or prfn (a declaration whose body is the primplement of the same name)."""

    def __init__(self, source, kind, name, first_line, text, pub):
        self.source, self.kind, self.name, self.first_line, self.text, self.pub = source, kind, name, first_line, text, pub

    @property
    def key(self):
        return (self.source, self.kind, self.name, self.first_line)

    def is_declaration(self):
        return self.pub and self.kind in ('prfun', 'prfn')


def blocks_of(source, text):
    """The top-level declaration blocks of a .bats text (comments blanked), in order."""
    lines = strip(text).split('\n')
    out, index = [], 0
    while index < len(lines):
        m = HEAD.match(lines[index])
        if not m:
            index += 1
            continue
        end = index + 1
        while end < len(lines) and (not lines[end].strip() or lines[end][0] in ' \t|' or CONTINUATION.match(lines[end])):
            end += 1
        last = end
        while last > index + 1 and not lines[last - 1].strip():
            last -= 1
        out.append(Block(source, m.group('kind'), m.group('name'), index + 1, '\n'.join(lines[index:last]), bool(m.group('pub'))))
        index = end
    return out


def package_text(lock, repository, package, member):
    """The text of src file `member` of the locked version of `package` (a zip in the repository)."""
    for entry in Path(lock).read_text().split('\n'):
        parts = entry.split()
        if len(parts) >= 2 and parts[0].split('/')[-1] == package:
            name, version = parts[0], parts[1]
            flat = name.replace('/', '_')
            for candidate in (Path(repository) / name.split('/')[0] / name.split('/')[-1] / f'{flat}_{version}.bats',
                              Path(repository) / name.split('/')[-1] / f'{flat}_{version}.bats',
                              Path(repository) / f'{flat}_{version}.bats'):
                if candidate.exists():
                    return zipfile.ZipFile(candidate).read(member).decode()
    raise KeyError(f'{package} is not locked in {lock} or not in {repository}')


class World:
    """The blocks of the quire modules (root/src/*.bats) and of the packages the providers name."""

    def __init__(self, root, lock=None, repository=None):
        self.root = Path(root)
        self.by_name = {}
        self.modules = {}
        for path in sorted((self.root / 'src').glob('*.bats')):
            self.add(f'src/{path.name}', path.read_text())
        self.packages = {}
        if lock and repository:
            for alias, (package, member) in PROVIDERS.items():
                label = f'{package}:{member}'
                if label not in self.modules:
                    self.add(label, package_text(lock, repository, package, member), alias)
        self.lock, self.repository = lock, repository

    def add(self, source, text, alias=None):
        blocks = blocks_of(source, text)
        self.modules[source] = blocks
        for block in blocks:
            self.by_name.setdefault((alias, block.name), []).append(block)
            if alias:
                # a package's own declarations name each other without the alias
                self.by_name.setdefault((None, block.name), []).append(block)
        return blocks

    def find(self, name, alias, source):
        """The blocks that declare `name` as used in `source`, written with the package alias, if any."""
        if alias:
            return self.by_name.get((alias, name), [])
        own = [b for b in self.by_name.get((None, name), []) if b.source == source]
        if own:
            return own
        # a quire module names quire's declarations, a package's file those of its package
        home = source.split(':')[0] if ':' in source else 'src/'
        found = [b for b in self.by_name.get((None, name), []) if b.source.startswith(home)]
        sources = {b.source for b in found}
        if len(sources) > 1:
            raise KeyError(f'{name} is declared in more than one module: {sorted(sources)}')
        return found

    def uses(self, block):
        """The blocks the text of `block` mentions (itself and its own name's other blocks excluded,
        except the declaration of a primplement)."""
        found = []
        for m in TOKEN.finditer(block.text):
            token = m.group(0)
            alias, name = None, token
            if token.startswith('$') and '.' in token:
                alias, name = token[1:].split('.', 1)
            elif token.startswith('$'):
                continue
            for other in self.find(name, alias, block.source):
                if other is block:
                    continue
                if other.kind == 'primplement':
                    continue
                if other not in found:
                    found.append(other)
        if block.kind == 'primplement':
            for other in self.by_name.get((None, block.name), []):
                if other.is_declaration() and other.source == block.source and other not in found:
                    found.append(other)
        return found

    def implementations(self, block):
        return [b for b in self.by_name.get((None, block.name), [])
                if b.kind == 'primplement' and b.source == block.source] if block.is_declaration() else []

    def closure(self, roots):
        """The blocks `roots` need, each after what it uses; a declaration's primplement is a need."""
        order, state = [], {}

        def visit(block):
            if state.get(block.key):
                return
            state[block.key] = 1
            for other in self.uses(block):
                visit(other)
            order.append(block)
            state[block.key] = 2
            for implementation in self.implementations(block):
                visit(implementation)

        for root in roots:
            visit(root)
        return order

    def named(self, name, source):
        return [b for b in self.modules[source] if b.name == name]


def dats_text(block):
    """The block as a line of a .dats: `#pub prfun f` is `extern prfun f`, a `$A.` alias is dropped."""
    text = block.text
    if block.pub:
        text = re.sub(r'^#pub\s+', 'extern ' if block.is_declaration() else '', text)
    return re.sub(r'\$[A-Z]+\.', '', text)


def fixture_text(world, roots, header='', replacements=()):
    """A .dats holding `roots` (blocks) and what they need, under a `header` comment. `replacements`
    are (old, new, count) applied to the declarations, each old exactly `count` times."""
    body = '\n\n'.join(dats_text(b) for b in world.closure(roots)) + '\n'
    for old, new, count in replacements:
        if body.count(old) != count:
            raise ValueError(f'{old!r} occurs {body.count(old)} times, not {count}')
        body = body.replace(old, new)
    return '#include "share/atspre_staload.hats"\n' + header + body
