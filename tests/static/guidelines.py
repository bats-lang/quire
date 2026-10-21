#!/usr/bin/env python3
"""Lint of what agents write and of the guidelines they follow (quire#751).

The same classes of mistake came back because a guideline could be read to allow
them, and nothing refused the text that made them. This checks, without a compiler:

* the guideline files (CLAUDE.md and every .claude/**/*.md): none holds a phrase of
  tests/static/guidelines/phrases.tsv outside a code span (an exit clause, a rule the
  owner never wrote, a sentence that contradicts the owner's), and no sentence holds the
  words "all" and "data" together (name the sample and why it suffices); the reviewer's
  tool list holds no tool that runs anything (row 1);
* `--text FILE`: a brief, a ticket, a hand-back, a comment: the same phrases, anywhere;
* `--pr-body FILE --head SHA`: the above, and the body's form: it starts "Fixes #N" for
  one ticket (one ticket, one PR), names the head it describes (a body that went stale
  after a push is refused), holds an Evidence section with a command and its output,
  and ends with the generated line;
* `--review FILE`: the above for a review comment: its first line, the head SHA it
  reviewed, and, in the gate's form of bridge, pwa and capacitor-plugins, exactly one
  line with "Reviewed:" and exactly one with "Verdict:" (bridge#200);
* `--github`: what the text-lint workflow runs, from the event's payload: the PR's body
  against its head, and the newest review comment, set as the commit status `text-lint` on the
  head (a ticket's body: a comment on it); a bot's PR and a relock branch are exempt;
* `--brief FILE --ticket FILE`: the text rules, and that every line of the ticket's
  Done-when is in the brief word for word (a brief never restates it).

Stopgap (CLAUDE.md, "Pipeline and tooling improvements belong in bats or pwa"): a second
bats app would copy this lint and the workflow that runs it (the text-lint workflow),
so they move to bats (bats-lang/bats#431); the avenue exhausted for non-bats code
(quire#646): bats has no command that reads markdown or a comment's text, and this has to
run in the `plan`-like jobs that have no compiler.

usage: python3 tests/static/guidelines.py [ROOT]
       python3 tests/static/guidelines.py --text FILE
       python3 tests/static/guidelines.py --pr-body FILE --head SHA
       python3 tests/static/guidelines.py --review FILE [--gate-form]
       python3 tests/static/guidelines.py --brief FILE --ticket FILE
       python3 tests/static/guidelines.py --github        (in a workflow: GITHUB_EVENT_NAME, GITHUB_EVENT_PATH)
Exit 0 when clean, 1 with one line for each finding.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PHRASES = os.path.join(HERE, 'guidelines', 'phrases.tsv')

GENERATED = (
    '🤖 Generated with [Claude Code](https://claude.ai/code)',
    '🤖 Generated with [Claude Code](https://claude.com/claude-code)',
)
# the tools that run, build, measure or change something: a reviewer holds none (row 1)
RUNNING_TOOLS = {'bash', 'edit', 'write', 'notebookedit', 'monitor', 'taskstop', 'skill', 'agent'}
SHA = re.compile(r'\b[0-9a-f]{40}\b')
FIXES = re.compile(r'\bFixes\s+((?:[\w.-]+/[\w.-]+)?#\d+)', re.IGNORECASE)


def load_phrases(path=PHRASES):
    found = []
    with open(path, encoding='utf-8') as handle:
        for number, line in enumerate(handle, 1):
            if not line.strip() or line.startswith('#'):
                continue
            scope, row, regex, example, reason = line.rstrip('\n').split('\t')
            found.append((scope, row, re.compile(regex, re.IGNORECASE), reason, example))
    return found


def strip_code(text):
    """The text without its fenced blocks and code spans: a guideline quotes a phrase there."""
    text = re.sub(r'^(```|~~~).*?^\1[^\n]*$', ' ', text, flags=re.MULTILINE | re.DOTALL)
    return re.sub(r'`[^`\n]*`', ' ', text)


def sentences(text):
    return [part for part in re.split(r'(?<=[.!?])\s+|\n', text) if part.strip()]


def lint_text(text, name, phrases, guide=False, notes=False):
    """Findings for a text: the `text` phrases (and, for a guideline, the `guide` ones). An area
    note (.claude/rules, which holds technical findings: a load average is "contention") is
    held to the `guide` ones only."""
    if guide:
        text = strip_code(text)
    findings = []
    for number, line in enumerate(text.split('\n'), 1):
        for scope, row, regex, reason, _example in phrases:
            if scope == 'guide' and not guide:
                continue
            if scope == 'text' and notes:
                continue
            found = regex.search(line)
            if found:
                findings.append(f'{name}:{number}: row {row}: "{found.group(0)}": {reason}')
    for sentence in sentences(text):
        if re.search(r'\ball\b', sentence, re.IGNORECASE) and re.search(r'\bdata\b', sentence, re.IGNORECASE):
            findings.append(f'{name}: "all" and "data" in one sentence: name the sample and why it suffices: {sentence.strip()[:80]}')
    return findings


def frontmatter(text):
    found = re.match(r'---\n(.*?)\n---\n', text, re.DOTALL)
    fields = {}
    if found:
        for line in found.group(1).split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                fields[key.strip()] = value.strip()
    return fields


def lint_reviewer_tools(text, name):
    """Row 1: the reviewer's tools are an allowlist with nothing that runs."""
    tools = frontmatter(text).get('tools')
    if tools is None:
        return [f'{name}: the frontmatter has no `tools:` list: a reviewer holds only the tools that read and post (row 1)']
    held = [tool.strip() for tool in tools.split(',') if tool.strip()]
    return [f'{name}: `tools:` holds {tool}, which runs or changes something: a reviewer runs nothing (row 1)'
            for tool in held if tool.lower() in RUNNING_TOOLS]


def guideline_files(root):
    found = []
    if os.path.exists(os.path.join(root, 'CLAUDE.md')):
        found.append('CLAUDE.md')
    base = os.path.join(root, '.claude')
    for directory, names, files in os.walk(base):
        names.sort()
        for name in sorted(files):
            if name.endswith('.md'):
                found.append(os.path.relpath(os.path.join(directory, name), root))
    return found


def lint_guidelines(root, phrases):
    findings = []
    for relative in guideline_files(root):
        with open(os.path.join(root, relative), encoding='utf-8') as handle:
            text = handle.read()
        findings += lint_text(text, relative, phrases, guide=True, notes=relative.startswith('.claude/rules/'))
        if relative == '.claude/agents/reviewer.md':
            findings += lint_reviewer_tools(text, relative)
    return findings


def lint_pr_body(text, head, phrases):
    findings = lint_text(text, 'PR body', phrases)
    lines = [line for line in text.split('\n') if line.strip()]
    if not lines or not FIXES.match(lines[0]):
        findings.append('PR body: the first line is "Fixes #N" for the ticket; a PR that does not meet its Done-when as written is not opened as Refs (rows 2, 3)')
    tickets = {found.upper() for found in FIXES.findall(text)}
    if len(tickets) > 1:
        findings.append(f'PR body: Fixes names {len(tickets)} tickets ({", ".join(sorted(tickets))}): one ticket, one PR; a dependency is its own ticket and PR (row 17)')
    named = re.findall(r'^Head:\s*([0-9a-f]{40})\s*$', text, re.MULTILINE)
    if not named:
        findings.append('PR body: no line "Head: <40-character SHA>": the body names the head it describes (row 11)')
    elif head and named[-1] != head:
        findings.append(f'PR body: it describes head {named[-1]} but the head is {head}: rewrite the body for the head (row 11)')
    if not re.search(r'^#+\s*Evidence\b', text, re.MULTILINE | re.IGNORECASE):
        findings.append('PR body: no "Evidence" heading: every claim has its command and raw output (row 7)')
    elif not re.search(r'^(```|~~~)[^\n]*\n\$ ', text, re.MULTILINE):
        findings.append('PR body: no fenced block that starts with "$ <command>" and holds its raw output (row 7)')
    if not any(line.strip() in GENERATED for line in lines[-3:]):
        findings.append('PR body: it does not end with the generated line "🤖 Generated with [Claude Code](https://claude.ai/code)"')
    return findings


def lint_review(text, phrases, gate_form=False):
    findings = lint_text(text, 'review', phrases)
    lines = [line for line in text.split('\n') if line.strip()]
    first = lines[0].strip() if lines else ''
    if gate_form or first == '## Adversarial review':
        if first != '## Adversarial review':
            findings.append('review: the gate wants the first line to be exactly "## Adversarial review"')
        verdicts = [line for line in lines if 'Verdict:' in line]
        reviewed = [line for line in lines if 'Reviewed:' in line]
        if len(verdicts) != 1 or verdicts[0] not in ('Verdict: approved', 'Verdict: changes needed'):
            findings.append(f'review: exactly one line holds "Verdict:", and it is exactly "Verdict: approved" or "Verdict: changes needed" (found {len(verdicts)}; bridge#200)')
        if len(reviewed) != 1 or not re.fullmatch(r'Reviewed: [0-9a-f]{40}', reviewed[0]):
            findings.append(f'review: exactly one line holds "Reviewed:", and it is "Reviewed: <40-character SHA>" (found {len(reviewed)}; bridge#200): do not write the word in any other line')
    else:
        if first not in ('approved', 'changes needed'):
            findings.append('review: the first line is "approved" or "changes needed"')
        if not SHA.search(text):
            findings.append('review: it names the head SHA reviewed as the full 40-character SHA')
    return findings


def done_when(ticket):
    found = re.search(r'^#+\s*Done when\b[^\n]*\n(.*?)(?=^#+\s|\Z)', ticket, re.MULTILINE | re.DOTALL | re.IGNORECASE)
    return [line.strip() for line in found.group(1).split('\n') if line.strip()] if found else None


def lint_brief(brief, ticket, phrases):
    findings = lint_text(brief, 'brief', phrases)
    lines = done_when(ticket)
    if lines is None:
        findings.append('ticket: it has no "Done when" section: add it before the brief (the Done-when is what the work is measured by)')
    else:
        for line in lines:
            if line not in brief:
                findings.append(f'brief: the ticket\'s Done-when line is not in the brief word for word (row 21): {line[:80]}')
    return findings


TRUSTED = ('OWNER', 'MEMBER', 'COLLABORATOR')
MARKER = '<!-- text-lint -->'
EXEMPT_BRANCHES = ('relock/', 'dependabot/')
REVIEW_FIRST_LINES = ('approved', 'changes needed', '## Adversarial review')


def gh_api(path, method='GET', fields=None):
    """The GitHub REST API through the runner's `gh`; JSON back, None for an empty answer."""
    import json
    import subprocess
    command = ['gh', 'api', '-X', method, path]
    for key, value in (fields or {}).items():
        command += ['-f', f'{key}={value}']
    done = subprocess.run(command, capture_output=True, text=True, check=True)
    return json.loads(done.stdout) if done.stdout.strip() else None


def newest_review(comments):
    """The newest comment of a trusted author that is a review (its first line says so)."""
    found = None
    for comment in comments:
        if comment.get('author_association') not in TRUSTED:
            continue
        lines = [line for line in (comment.get('body') or '').split('\n') if line.strip()]
        if lines and lines[0].strip() in REVIEW_FIRST_LINES:
            found = comment
    return found


def all_pages(api, path):
    found, page = [], 1
    while True:
        part = api(f'{path}{"&" if "?" in path else "?"}per_page=100&page={page}')
        found += part
        if len(part) < 100:
            return found
        page += 1


def github(event_name, event, repository, api, phrases, run_url=''):
    """Lint what the event is about and report it; the exit code is 1 when something is wrong."""
    if event_name == 'issues':
        issue = event['issue']
        # a table row quotes the mistakes it catalogues (quire#751 itself), so rows and code spans are not linted
        body = '\n'.join(line for line in (issue.get('body') or '').split('\n') if not line.lstrip().startswith('|'))
        findings = lint_text(strip_code(body), f'ticket #{issue["number"]}', phrases)
        comments = all_pages(api, f'repos/{repository}/issues/{issue["number"]}/comments')
        mine = [comment for comment in comments if (comment.get('body') or '').startswith(MARKER)]
        if findings:
            body = MARKER + '\ntext-lint: the ticket text holds phrases that always mean narrowing or waiting (quire#751):\n\n' + '\n'.join(f'* {finding}' for finding in findings)
            if mine:
                api(f'repos/{repository}/issues/comments/{mine[0]["id"]}', 'PATCH', {'body': body})
            else:
                api(f'repos/{repository}/issues/{issue["number"]}/comments', 'POST', {'body': body})
        else:
            for comment in mine:
                api(f'repos/{repository}/issues/comments/{comment["id"]}', 'DELETE')
        return findings
    if event_name == 'issue_comment':
        if 'pull_request' not in event['issue']:
            return []
        pull = api(f'repos/{repository}/pulls/{event["issue"]["number"]}')
    else:
        pull = event['pull_request']
    head, number = pull['head']['sha'], pull['number']
    if pull['user']['login'].endswith('[bot]') or pull['head']['ref'].startswith(EXEMPT_BRANCHES):
        findings = []
        description = 'exempt: a bot or a relock branch'
    else:
        findings = lint_pr_body(pull.get('body') or '', head, phrases)
        review = newest_review(all_pages(api, f'repos/{repository}/issues/{number}/comments'))
        if review:
            findings += [f'{finding} (the review comment {review["html_url"]})' for finding in lint_review(review['body'], phrases)]
        description = (findings[0] if findings else 'the PR body and the newest review are in form')[:140]
    api(f'repos/{repository}/statuses/{head}', 'POST', {
        'state': 'failure' if findings else 'success', 'context': 'text-lint',
        'description': description, 'target_url': run_url})
    return findings


def read(path):
    if path == '-':
        return sys.stdin.read()
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def option(arguments, name):
    return arguments[arguments.index(name) + 1] if name in arguments else None


def main(arguments):
    phrases = load_phrases()
    if '--github' in arguments:
        import json
        with open(os.environ['GITHUB_EVENT_PATH'], encoding='utf-8') as handle:
            event = json.load(handle)
        server = os.environ.get('GITHUB_SERVER_URL', 'https://github.com')
        repository = os.environ['GITHUB_REPOSITORY']
        findings = github(os.environ['GITHUB_EVENT_NAME'], event, repository, gh_api, phrases,
                          f'{server}/{repository}/actions/runs/{os.environ.get("GITHUB_RUN_ID", "")}')
    elif '--text' in arguments:
        findings = lint_text(read(option(arguments, '--text')), 'text', phrases)
    elif '--pr-body' in arguments:
        findings = lint_pr_body(read(option(arguments, '--pr-body')), option(arguments, '--head'), phrases)
    elif '--review' in arguments:
        findings = lint_review(read(option(arguments, '--review')), phrases, '--gate-form' in arguments)
    elif '--brief' in arguments:
        findings = lint_brief(read(option(arguments, '--brief')), read(option(arguments, '--ticket')), phrases)
    else:
        findings = lint_guidelines(arguments[0] if arguments else ROOT, phrases)
    for finding in findings:
        print(finding)
    if not findings:
        print(f'ok: {len(phrases)} phrases' if not arguments or arguments[0] not in ('--text', '--pr-body', '--review', '--brief', '--github') else 'ok')
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
