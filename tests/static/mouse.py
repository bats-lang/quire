#!/usr/bin/env python3
"""No e2e spec makes a raw pointer event (#630): every `page.mouse` (a
click, a move, a press, a wheel) goes through `rawMouse` in e2e/helpers.js,
which calls releaseClick first. A timed-out locator click can leave
Playwright's hit-target interceptor in the page, which stops every trusted
pointer event not on its element, so a raw event made after one never
reaches the app (quire#600). Prints each use of `mouse` in the .js files
under the given directory outside that one helper, and fails when there is
one: a member (`page.mouse`, `page?.mouse`, a member split over lines), a
bracket key (`page['mouse']`), or a destructured key (`const {mouse} = page`,
`{mouse: m}`, over several lines). The source is read as tokens, so a
comment or a string that names `.mouse` is not a use.

usage: mouse.py <e2e-dir>
"""
import os
import sys

# the one file that may name it: the helper, at the top of the directory
HELPER = 'helpers.js'
# a `/` after one of these starts a regular expression, not a division
REGEX_AFTER = {'(', ',', '=', ':', '[', '!', '&', '|', '?', '{', ';', '+', '-',
               '*', '%', '<', '>', '~', '^', '=>', '==', '===', '!=', '!==', '&&',
               '||', '??', '+=', '-=', '*=', '/=', '%=', '...'}
REGEX_AFTER_WORDS = {'return', 'typeof', 'case', 'do', 'else', 'in', 'of', 'new',
                     'delete', 'void', 'throw', 'instanceof', 'yield', 'await'}
# the operators of more than one character, longest first
OPERATORS = ['...', '===', '!==', '**=', '??=', '||=', '&&=', '=>', '==', '!=',
             '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=', '*=',
             '/=', '%=', '**', '<<', '>>']
OPENERS = {'(', '[', '{'}
CLOSERS = {')', ']', '}'}


def tokenize(source):
    """The tokens of a .js source as (kind, value, line): 'ident', 'str' (a
    string's text, or a template's text between its substitutions), 'num',
    'regex' (its value left empty) and 'punct'. Comments are dropped. This is
    not a parser: it reads a regular expression by the token before it, as
    JavaScript's own grammar does for the usual cases."""
    tokens = []
    line = 1
    i = 0
    n = len(source)
    subs = []     # the brace depth at each open `${`, innermost last
    depth = 0     # braces of code open now

    def template(start, line):
        """The template text from `start` (just after a backtick or a `}`
        that closes a substitution): its token, the index after it, and
        whether it stopped at a `${`."""
        j = start
        while j < n:
            if source[j] == '\\':
                j += 2
            elif source[j] == '`':
                tokens.append(('str', source[start:j], line))
                return j + 1, False
            elif source.startswith('${', j):
                tokens.append(('str', source[start:j], line))
                return j + 2, True
            else:
                j += 1
        tokens.append(('str', source[start:n], line))
        return n, False

    while i < n:
        c = source[i]
        start = i
        if c == '\n':
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif source.startswith('//', i):
            end = source.find('\n', i)
            i = n if end < 0 else end
        elif source.startswith('/*', i):
            end = source.find('*/', i + 2)
            i = n if end < 0 else end + 2
            line += source.count('\n', start, i)
        elif c in '\'"':
            j = i + 1
            while j < n and source[j] != c and source[j] != '\n':
                j += 2 if source[j] == '\\' else 1
            tokens.append(('str', source[i + 1:j], line))
            i = j + 1
        elif c == '`':
            i, opened = template(i + 1, line)
            if opened:
                subs.append(depth)
            line += source.count('\n', start, i)
        elif c == '}' and subs and subs[-1] == depth:
            subs.pop()
            tokens.append(('punct', '}', line))
            i, opened = template(i + 1, line)
            if opened:
                subs.append(depth)
            line += source.count('\n', start, i)
        elif c == '/' and (not tokens or (
                tokens[-1][0] == 'punct' and tokens[-1][1] in REGEX_AFTER) or (
                tokens[-1][0] == 'ident' and tokens[-1][1] in REGEX_AFTER_WORDS)):
            j = i + 1
            in_class = False
            while j < n and source[j] != '\n':
                if source[j] == '\\':
                    j += 2
                    continue
                if source[j] == '[':
                    in_class = True
                elif source[j] == ']':
                    in_class = False
                elif source[j] == '/' and not in_class:
                    break
                j += 1
            j += 1
            while j < n and source[j].isalpha():
                j += 1
            tokens.append(('regex', '', line))
            i = min(j, n)
        elif c.isalpha() or c in '_$':
            j = i
            while j < n and (source[j].isalnum() or source[j] in '_$'):
                j += 1
            tokens.append(('ident', source[i:j], line))
            i = j
        elif c.isdigit():
            j = i
            while j < n and (source[j].isalnum() or source[j] in '._'):
                j += 1
            tokens.append(('num', source[i:j], line))
            i = j
        else:
            op = next((o for o in OPERATORS if source.startswith(o, i)), c)
            if op == '{':
                depth += 1
            elif op == '}':
                depth -= 1
            tokens.append(('punct', op, line))
            i += len(op)
    return tokens


def brace_keys(tokens, opener):
    """The lines of a `mouse` key among the properties of the brace opened at
    `opener`, at its own level (a nested brace's keys are that brace's own)."""
    lines = []
    level = 0
    for k in range(opener + 1, len(tokens)):
        kind, value, line = tokens[k]
        if kind == 'punct' and value in OPENERS:
            level += 1
        elif kind == 'punct' and value in CLOSERS:
            if level == 0:
                break
            level -= 1
        elif level == 0 and value == 'mouse' and kind in ('ident', 'str'):
            before = tokens[k - 1]
            after = tokens[k + 1] if k + 1 < len(tokens) else ('', '', 0)
            if before[:2] in (('punct', '{'), ('punct', ',')) \
                    and after[0] == 'punct' and after[1] in (',', '}', ':', '='):
                lines.append(line)
    return lines


def mouse_lines(source):
    """The line of each use of `mouse` in a .js source, in order."""
    tokens = tokenize(source)
    lines = []
    for k, (kind, value, line) in enumerate(tokens):
        if kind == 'punct' and value in ('.', '?.') and k + 1 < len(tokens) \
                and tokens[k + 1][:2] == ('ident', 'mouse'):
            lines.append(tokens[k + 1][2])
        elif kind == 'punct' and value == '[' and k + 2 < len(tokens) \
                and tokens[k + 1][:2] == ('str', 'mouse') and tokens[k + 2][:2] == ('punct', ']'):
            lines.append(tokens[k + 1][2])
        elif kind == 'punct' and value == '{':
            lines.extend(brace_keys(tokens, k))
    return sorted(lines)


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
                text = source.read()
            lines = text.split('\n')
            for number in mouse_lines(text):
                print(f'{path}:{number}: a raw pointer event, not through rawMouse: {lines[number - 1].strip()}')
                found += 1
    print(f'{found} raw page.mouse use(s) outside rawMouse')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
