#!/usr/bin/env python3
"""No e2e spec makes a raw pointer event (#630): every `page.mouse` (a
click, a move, a press, a wheel) goes through `rawMouse` in e2e/helpers.js,
which calls releaseClick first. A timed-out locator click can leave
Playwright's hit-target interceptor in the page, which stops every trusted
pointer event not on its element, so a raw event made after one never
reaches the app (quire#600). Prints each line of the .js files under the
given directory that names `.mouse` (as `page.mouse` or `page['mouse']`)
outside that one helper, and fails when there is one.

usage: mouse.py <e2e-dir>
"""
import os
import re
import sys

# `.mouse` as a member: `page.mouse`, `page.mouse.click`, `page['mouse']`
MOUSE = re.compile(r"\.mouse\b|\[\s*['\"]mouse['\"]\s*\]")
# the one file that may name it: the helper, at the top of the directory
HELPER = 'helpers.js'


def main(root):
    found = 0
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if not name.endswith('.js'):
                continue
            path = os.path.join(directory, name)
            if os.path.relpath(path, root) == HELPER:
                continue
            with open(path, encoding='utf-8') as source:
                for number, line in enumerate(source, 1):
                    if MOUSE.search(line):
                        print(f'{path}:{number}: a raw pointer event, not through rawMouse: {line.strip()}')
                        found += 1
    print(f'{found} raw page.mouse use(s) outside rawMouse')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
