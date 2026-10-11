#!/usr/bin/env python3
"""Fails when a group of the stored records is added in a way an old record cannot read (quire#515).

A group added to the format after records were written must be "added"
(scripts/record_tables.py): a record written before it has no such chunk,
and a group of any other mode makes that record damaged (quire#506). So:

* the groups of the first table (the ones below) keep their modes, and no
  other group is "req" or "opt";
* every "added" group is named once in RELEASES, in the order it was added,
  with the commit that added it;
* e2e/old-library.spec.js opens a library of every table that ever
  shipped: one of the first table's groups alone, and one more for each
  group of RELEASES, written `groups: [...]` in its SHAPES, so adding a
  group without adding the library of the table before it fails here.

usage: tests/static/groups.py <root>   (a checkout with scripts/record_tables.py
       and e2e/old-library.spec.js)
"""
import importlib.util
import re
import sys
from pathlib import Path

FIRST_BOOK = {
    "AUTH": "req", "BOOK": "req", "COLL": "opt", "ELSE": "opt", "FNSH": "opt", "ORDR": "opt",
    "PLCE": "opt", "SERI": "opt", "SHLF": "opt", "SIZE": "opt", "TIME": "opt", "TITL": "req",
}
FIRST_INDEX = {"LEGA": "opt", "NAMS": "req"}


def load(root):
    spec = importlib.util.spec_from_file_location("record_tables", Path(root) / "scripts" / "record_tables.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def shapes_in(root):
    text = (Path(root) / "e2e" / "old-library.spec.js").read_text()
    block = re.search(r'const SHAPES = \[(.*?)\n\];', text, re.S)
    if not block:
        return None
    found = []
    for match in re.finditer(r'groups:\s*\[([^\]]*)\]', block.group(1)):
        found.append([name.strip().strip("'\"") for name in match.group(1).split(",") if name.strip()])
    return found


def main(root):
    tables = load(root)
    problems = []
    for label, groups, first in (("book", tables.BOOK_GROUPS, FIRST_BOOK), ("index", tables.INDEX_GROUPS, FIRST_INDEX)):
        seen = {}
        for tag, mode, _ in groups:
            seen[tag] = mode
        for tag, mode in first.items():
            if seen.get(tag) != mode:
                problems.append(f"{label} group {tag} of the first table must stay {mode}, it is {seen.get(tag)}")
        for tag, mode in seen.items():
            if tag not in first and mode != "added":
                problems.append(f"{label} group {tag} is {mode}: a group added after records were written must be \"added\" (quire#506)")
    added = [tag for tag, mode, _ in tables.BOOK_GROUPS + tables.INDEX_GROUPS if mode == "added"]
    released = [tag for tag, _ in tables.RELEASES]
    if sorted(released) != sorted(added) or len(set(released)) != len(released):
        problems.append(f"RELEASES names {released}, the added groups are {sorted(added)}: each once")
    for tag, commit in tables.RELEASES:
        if not re.fullmatch(r"[0-9a-f]{7,40}", commit):
            problems.append(f"RELEASES: {tag} has no commit")
    shapes = shapes_in(root)
    if shapes is None:
        problems.append("e2e/old-library.spec.js has no `const SHAPES = [ ... ];`")
    else:
        want = [released[:count] for count in range(len(released) + 1)]
        if shapes != want:
            problems.append(f"e2e/old-library.spec.js SHAPES has the groups {shapes}, the tables that shipped are {want}")
    for problem in problems:
        print(problem)
    print(f"{len(problems)} problem(s) in the record tables" if problems else f"the record tables: {len(released)} added group(s), {len(released) + 1} table(s) with a library each")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
