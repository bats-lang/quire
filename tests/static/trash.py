#!/usr/bin/env python3
"""A dictionary's files are deleted only by Empty Trash (quire#396), as a
book's are: `dict_trash_empty(` may be called only in src/bin/quire.bats,
in the branch where lib_ask_harm's promise resolves Accepted, and nowhere
else. Prints each other call in the .bats files under the given directory
and fails when there is one. This is a scan of the source, not a type: the
proof that only an answered dialog deletes them is still owed (the harm
dialog is in library.bats, which dictionary.bats cannot be staloaded by).

usage: trash.py <dir>
"""
import os
import re
import sys

CALL = re.compile(r'\bdict_trash_empty\(')


def main(root):
    found = 0
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if not name.endswith('.bats'):
                continue
            if name in ('dictionary.bats', 'quire.bats'):
                continue
            path = os.path.join(directory, name)
            with open(path, encoding='utf-8') as source:
                for number, line in enumerate(source, 1):
                    if CALL.search(line):
                        print(f'{path}:{number}: dictionaries deleted outside Empty Trash: {line.strip()}')
                        found += 1
    print(f'{found} deletion(s) of dictionaries outside Empty Trash')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
