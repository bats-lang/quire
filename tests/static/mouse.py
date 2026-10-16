#!/usr/bin/env python3
"""No e2e spec makes a raw pointer event (#630): every `page.mouse` (a
click, a move, a press, a wheel) goes through `rawMouse` in e2e/helpers.js,
which calls releaseClick first. A timed-out locator click can leave
Playwright's hit-target interceptor in the page, which stops every trusted
pointer event not on its element, so a raw event made after one never
reaches the app (quire#600). Prints each use of `mouse` in the .js files
under the given directory outside that one helper, and fails when there is
one. A use is:

- a member: `page.mouse`, `page?.mouse`, also when the member is split over
  lines;
- a bracket key: `page['mouse']`;
- a shorthand key: `{ mouse }`, anywhere (it names the mouse object);
- a `mouse:` key of a destructuring pattern, a declaration's
  (`const {mouse: m} = page`), an assignment's, a parameter's, or nested in
  one, over several lines. A `mouse:` key of an object literal is not a use:
  `{ mouse: true }` passes.

The source is read as tokens, so a comment or a string that names `.mouse` is
not a use. Where the grammar leaves a `/` open (after a `}` that closes an
object or a block that the reader cannot tell from one, after a `:`), the
file is read both ways, with the `/` as a division and as a regular
expression, and a use in either reading is a use. A `/` after a `)` is a
regular expression only when the `)` closes an `if`, `while`, `for` or `with`
head; after the other `)`s, and after a `}` that closes an object, it is a
division.

usage: mouse.py <e2e-dir>
"""
import os
import sys
from collections import Counter

# the one file that may name it: the helper, at the top of the directory
HELPER = 'helpers.js'
# after one of these tokens a `/` starts a regular expression, not a division
REGEX_AFTER = {'(', ',', '=', ':', '[', '!', '&', '|', '?', '{', ';', '+', '-',
               '*', '%', '<', '>', '~', '^', '=>', '==', '===', '!=', '!==', '&&',
               '||', '??', '+=', '-=', '*=', '/=', '%=', '...'}
REGEX_AFTER_WORDS = {'return', 'typeof', 'case', 'do', 'else', 'in', 'of', 'new',
                     'delete', 'void', 'throw', 'instanceof', 'yield', 'await'}
# the words whose `(` makes its `)` the end of a statement's head
HEAD_WORDS = {'if', 'while', 'for', 'with'}
# the words after which a `{` opens a block, and those before which it opens an expression
BLOCK_AFTER_WORDS = {'else', 'do', 'try', 'finally'}
EXPRESSION_WORDS = {'return', 'typeof', 'void', 'delete', 'in', 'of', 'case',
                    'throw', 'yield', 'await', 'new', 'instanceof'}
# the operators of more than one character, longest first
OPERATORS = ['...', '===', '!==', '**=', '??=', '||=', '&&=', '=>', '==', '!=',
             '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=', '*=',
             '/=', '%=', '**', '<<', '>>']


def brace_kind(previous):
    """What a `{` after the token `previous` opens: 'block' (a statement's),
    'object' (an expression's), or 'unknown' (after a `:`, which may be a
    label, a case or an object's property: the grammar leaves it open)."""
    if previous is None:
        return 'block'
    kind, value = previous[0], previous[1]
    if kind == 'punct':
        if value in (')', ';', '{', '}', '=>'):
            return 'block'
        return 'unknown' if value == ':' else 'object'
    if kind == 'ident':
        if value in BLOCK_AFTER_WORDS:
            return 'block'
        return 'object' if value in EXPRESSION_WORDS else 'block'
    return 'object'


def regex_end(source, start):
    """Where the regular expression that starts with the `/` at `start` ends
    (after its flags), or None when no `/` closes it on its line."""
    n = len(source)
    j = start + 1
    in_class = False
    while j < n and source[j] != '\n':
        c = source[j]
        if c == '\\':
            j += 2
            continue
        if c == '[':
            in_class = True
        elif c == ']':
            in_class = False
        elif c == '/' and not in_class:
            j += 1
            while j < n and source[j].isalpha():
                j += 1
            return j
        j += 1
    return None


def regex_allowed(tokens, unknown_regex):
    """Whether a `/` after the tokens so far starts a regular expression. The
    last token's close says what a `)` or `}` closed; `unknown_regex` is the
    reading of a `}` whose brace is unknown."""
    if not tokens:
        return True
    kind, value, _, close = tokens[-1]
    if kind == 'punct':
        if value == ')':
            return close == 'head'
        if value == '}':
            return close == 'block' or (close == 'unknown' and unknown_regex)
        return value in REGEX_AFTER
    if kind == 'ident':
        return value in REGEX_AFTER_WORDS
    return False


def tokenize(source, unknown_regex):
    """(tokens, unknown): the tokens of a .js source as (kind, value, line,
    close), kind 'ident', 'str' (a string's text, or a template's text between
    its substitutions), 'num', 'regex' (its value left empty) or 'punct'.
    `close` is set on a `)` ('head' or 'expr') and on a `}` ('block', 'object'
    or 'unknown'), and is None otherwise. Comments are dropped. `unknown` says
    a `/` came after an unknown brace, so the file must be read both ways.
    This is not a parser: it follows the usual grammar of `/` and `{`."""
    tokens = []
    unknown = False
    parens = []   # for each open `(`: whether it follows a head word
    braces = []   # for each open `{`: its brace_kind
    subs = []     # the brace depth at each open `${`, innermost last
    depth = 0
    line = 1
    i = 0
    n = len(source)

    def template(start, line):
        """The template text from `start` (just after a backtick or the `}`
        of a substitution): the index after it, and whether it stopped at `${`."""
        j = start
        while j < n:
            if source[j] == '\\':
                j += 2
            elif source[j] == '`':
                tokens.append(('str', source[start:j], line, None))
                return j + 1, False
            elif source.startswith('${', j):
                tokens.append(('str', source[start:j], line, None))
                return j + 2, True
            else:
                j += 1
        tokens.append(('str', source[start:n], line, None))
        return n, False

    while i < n:
        c = source[i]
        start = i
        if c == '/' and tokens and tokens[-1][3] == 'unknown' and not source.startswith(('//', '/*'), i):
            unknown = True
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
            tokens.append(('str', source[i + 1:j], line, None))
            i = j + 1
        elif c == '`':
            i, opened = template(i + 1, line)
            if opened:
                subs.append(depth)
            line += source.count('\n', start, i)
        elif c == '}' and subs and subs[-1] == depth:
            subs.pop()
            tokens.append(('punct', '}', line, None))
            i, opened = template(i + 1, line)
            if opened:
                subs.append(depth)
            line += source.count('\n', start, i)
        elif c == '/' and (end := regex_end(source, i)) is not None \
                and regex_allowed(tokens, unknown_regex):
            tokens.append(('regex', '', line, None))
            i = end
        elif c.isalpha() or c in '_$':
            j = i
            while j < n and (source[j].isalnum() or source[j] in '_$'):
                j += 1
            tokens.append(('ident', source[i:j], line, None))
            i = j
        elif c.isdigit():
            j = i
            while j < n and (source[j].isalnum() or source[j] in '._'):
                j += 1
            tokens.append(('num', source[i:j], line, None))
            i = j
        else:
            op = next((o for o in OPERATORS if source.startswith(o, i)), c)
            if op == '(':
                previous = tokens[-1] if tokens else None
                parens.append(previous is not None and previous[0] == 'ident'
                              and previous[1] in HEAD_WORDS)
                tokens.append(('punct', op, line, None))
            elif op == ')':
                head = parens.pop() if parens else False
                tokens.append(('punct', op, line, 'head' if head else 'expr'))
            elif op == '{':
                braces.append(brace_kind(tokens[-1] if tokens else None))
                depth += 1
                tokens.append(('punct', op, line, None))
            elif op == '}':
                depth -= 1
                kind = braces.pop() if braces else 'block'
                tokens.append(('punct', op, line, kind))
            else:
                tokens.append(('punct', op, line, None))
            i += len(op)
    return tokens, unknown


def is_pattern(tokens, opener, closer):
    """Whether the braces opened at `opener` and closed at `closer` are a
    destructuring pattern: a declaration's (after const, let or var), an
    assignment's or a loop head's (closed by `=`, `of` or `in`), or a
    parameter's (closed by `)` before `=>` or the body)."""
    if opener and tokens[opener - 1][:2] in (('ident', 'const'), ('ident', 'let'), ('ident', 'var')):
        return True
    after = tokens[closer + 1][:2] if closer + 1 < len(tokens) else ('', '')
    if after in (('punct', '='), ('ident', 'of'), ('ident', 'in')):
        return True
    return after == ('punct', ')') and closer + 2 < len(tokens) \
        and tokens[closer + 2][:2] in (('punct', '=>'), ('punct', '{'))


def key_uses(tokens):
    """The lines of a `mouse` key of a brace. A shorthand (`{ mouse }`) names
    the mouse object, so it is a use wherever it is. A `mouse:` (or `mouse =`)
    key is one only in a pattern, the braces of a pattern's own level and of
    any brace nested in one (a default's object is counted too, which the
    lint takes as the price)."""
    opens = []
    close_of = {}
    for k, (kind, value, _, close) in enumerate(tokens):
        if kind != 'punct':
            continue
        if value == '{':
            opens.append(k)
        elif value == '}' and close is not None and opens:
            close_of[opens.pop()] = k
    pattern = {}
    spans = []    # (closer, pattern) of the braces open around the one read next
    for k in sorted(close_of):
        while spans and spans[-1][0] < k:
            spans.pop()
        pattern[k] = any(p for _, p in spans) or is_pattern(tokens, k, close_of[k])
        spans.append((close_of[k], pattern[k]))
    lines = []
    for k, closer in close_of.items():
        level = 0
        for m in range(k + 1, closer):
            kind, value, line, _ = tokens[m]
            if kind == 'punct' and value in ('{', '[', '('):
                level += 1
            elif kind == 'punct' and value in ('}', ']', ')'):
                level -= 1
            elif level == 0 and kind in ('ident', 'str') and value == 'mouse':
                before, after = tokens[m - 1][:2], tokens[m + 1][:2]
                if before not in (('punct', '{'), ('punct', ',')) or after[0] != 'punct':
                    continue
                if after[1] in (',', '}') or (after[1] in (':', '=') and pattern[k]):
                    lines.append(line)
    return lines


def mouse_uses(tokens):
    """The line of each use of `mouse` in a token list."""
    lines = []
    for k, (kind, value, _, _) in enumerate(tokens):
        if kind == 'punct' and value in ('.', '?.') and k + 1 < len(tokens) \
                and tokens[k + 1][:2] == ('ident', 'mouse'):
            lines.append(tokens[k + 1][2])
        elif kind == 'punct' and value == '[' and k + 2 < len(tokens) \
                and tokens[k + 1][:2] == ('str', 'mouse') and tokens[k + 2][:2] == ('punct', ']'):
            lines.append(tokens[k + 1][2])
    return lines + key_uses(tokens)


def mouse_lines(source):
    """The line of each use of `mouse` in a .js source, in order. Read both
    ways where a `/` is open (see tokenize): a line counts the larger number of
    its uses in the two readings."""
    tokens, unknown = tokenize(source, False)
    lines = Counter(mouse_uses(tokens))
    if unknown:
        lines = lines | Counter(mouse_uses(tokenize(source, True)[0]))
    return sorted(lines.elements())


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
