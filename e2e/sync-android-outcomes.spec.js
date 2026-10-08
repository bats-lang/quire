
import { test, expect, clientsServed } from './fixtures.js';
import { epubFile, importFiles, chapters, dialog, librarySearch, librarySettings, settingsButton, settingsScreen } from './helpers.js';
import { drive, CLIENT, capacitorPlayed } from './sync-stores.js';

async function device(browser, server) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const { google } = await capacitorPlayed(context, { mode: 'consent', token: server.token });
  await context.route('https://www.googleapis.com/**', server.handle);
  await context.route('https://oauth2.googleapis.com/revoke', server.revoke);
  await clientsServed(context, { googleWebClient: CLIENT });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  await page.goto('/');
  await expect(librarySearch(page)).toBeVisible();
  return { context, page, google, errors };
}

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const banner = page => page.getByRole('alert');
const useAndroid = page => panel(page).getByRole('button', { name: 'Use Android' });
async function chooseAndroid(page) {
  await panel(page).getByRole('button', { name: 'Google Drive ›' }).click();
  await useAndroid(page).click();
}
const row = page => settingsScreen(page).getByRole('group', { name: 'Sync' }).getByRole('status');
const clipboard = page => page.evaluate(() => navigator.clipboard.readText());
const VERSION = /^Quire \d{4}\.\d{1,2}\.\d{1,2}\.\d+ \([0-9a-f]{7,}\)\n/;

async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync ›').click();
  await expect(panel(page)).toBeVisible();
}

async function dismiss(page) {
  await banner(page).getByRole('button', { name: 'Dismiss' }).click();
  await expect(banner(page)).toBeHidden();
}

async function saidWithDetails(page, text, head, answer) {
  await expect(banner(page)).toHaveText(new RegExp('^' + escape(text)));
  await expect(banner(page).getByRole('link', { name: 'Report' })).toHaveAttribute('href', 'https://github.com/bats-lang/quire/issues');
  await page.evaluate(() => navigator.clipboard.writeText(''));
  await banner(page).getByRole('button', { name: 'Copy details' }).click();
  await expect(page.getByText('Copied', { exact: true })).toBeVisible();
  await expect.poll(() => clipboard(page)).toMatch(VERSION);
  const copy = (await clipboard(page)).replace(VERSION, '');
  const at = copy.indexOf('\nAnswer');
  expect(copy.slice(0, at)).toBe(head);
  const line = copy.slice(at + 1);
  if (answer === null) expect(line).toBe('Answer: none');
  else if ('json' in answer) {
    expect(line.startsWith('Answer, as JSON: ')).toBe(true);
    expect(JSON.parse(line.slice('Answer, as JSON: '.length))).toEqual(answer.json);
  } else expect(line).toBe(`Answer, ${answer.form}: ${answer.text}`);
  return copy;
}

const rejection = (message, code) => ({ name: 'Error', stack: 'the plugin', message, ...(code === undefined ? {} : { code }) });

const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const FAILED = "Google sign-in failed. Try again; if it fails again, copy the details and post them in a report.";
const STATUSES = [
  ['SERVICE_VERSION_UPDATE_REQUIRED', 2, FAILED],
  ['SERVICE_DISABLED', 3, FAILED],
  ['SIGN_IN_REQUIRED', 4, "Google asks you to sign in to the Google account on this device again: open Android's Settings, then Google, then try again."],
  ['INVALID_ACCOUNT', 5, "Google asks you to sign in to the Google account on this device again: open Android's Settings, then Google, then try again."],
  ['RESOLUTION_REQUIRED', 6, FAILED],
  ['NETWORK_ERROR', 7, "Can't reach Google. Check the connection, then try again."],
  ['INTERNAL_ERROR', 8, FAILED],
  ['DEVELOPER_ERROR', 10, "Google refused: this build of Quire isn't registered with it. Copy the details and post them in a report."],
  ['ERROR', 13, FAILED],
  ['INTERRUPTED', 14, FAILED],
  ['TIMEOUT', 15, "Can't reach Google. Check the connection, then try again."],
  ['API_NOT_CONNECTED', 17, FAILED],
  ['DEAD_CLIENT', 18, FAILED],
  ['REMOTE_EXCEPTION', 19, FAILED],
  ['CONNECTION_SUSPENDED_DURING_CALL', 20, FAILED],
  ['RECONNECTION_TIMED_OUT_DURING_UPDATE', 21, FAILED],
  ['RECONNECTION_TIMED_OUT', 22, FAILED],
];
const UNREGISTERED = "Google refused: this build of Quire isn't registered with it. Copy the details and post them in a report.";
// Play services says the build is not registered in its message, under a code that says only that something failed
const REGISTRATION = [
  ['INTERNAL_ERROR', 8, UNREGISTERED, '[8] Unknown error [status=UNREGISTERED_ON_API_CONSOLE]'],
  ['ERROR', 13, UNREGISTERED, '[13] Unknown error [status=UNREGISTERED_ON_API_CONSOLE]'],
  ['DEVELOPER_ERROR', 10, UNREGISTERED, '[10] [status=UNREGISTERED_ON_API_CONSOLE]'],
];
const SHORT = {
  [FAILED]: 'Google sign-in failed',
  "Can't reach Google. Check the connection, then try again.": "Can't reach Google",
  "Google asks you to sign in to the Google account on this device again: open Android's Settings, then Google, then try again.": 'Sign in to Google on this device',
  "Google refused: this build of Quire isn't registered with it. Copy the details and post them in a report.": 'Google sign-in failed',
};

const UNEXPECTED = 'An unexpected error occurred while signing in to Google. Copy the details and post them in a report.';

test('Use Android: each answer of Google\'s consent is said where the reader is', async ({ browser }) => {
  test.setTimeout(180000);
  const server = drive();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile({ title: 'Outcomes', author: 'Sync Tests', chapters: 2, rawChapters: chapters(2) })], 1);
  await openSync(a.page);

  for (const [name, number, said, named] of [...STATUSES, ...REGISTRATION]) {
    const message = named || `${number}: from Play services`;
    a.google.outcomes.authorizeScopes = [{ error: name, message }];
    await chooseAndroid(a.page);
    const text = `${said} Details: ${name} (${number})`;
    await saidWithDetails(a.page, text,
      `Platform: Android app\nWhile: signing in to Google\nCall: authorizeScopes\nCode: ${name}`,
      { json: rejection(message, name) });
    await expect(status(a.page)).toHaveText(text);
    await dismiss(a.page);
    await a.page.keyboard.press('Escape');
    await expect(row(a.page)).toHaveText(`Off · ${SHORT[said]}`);
    await settingsButton(a.page, 'Sync ›').click();
  }

  a.google.outcomes.authorizeScopes = [{ error: 'CONSENT_SHOWING', message: "Another call's consent screen is showing" }];
  await chooseAndroid(a.page);
  await expect(banner(a.page)).toHaveText(/^Google's consent screen is already open: finish it, then try again\./);
  await expect(banner(a.page).getByRole('button', { name: 'Copy details' })).toBeHidden();
  await expect(status(a.page)).toHaveText("Google's consent screen is already open: finish it, then try again.");
  await dismiss(a.page);

  a.google.outcomes.authorizeScopes = [{ error: 'UNIMPLEMENTED', message: 'Not implemented' }];
  await chooseAndroid(a.page);
  await expect(banner(a.page)).toHaveText(/^Android sync isn't set up in this build of Quire\./);
  await dismiss(a.page);

  a.google.outcomes.authorizeScopes = [{ error: 'CANCELED', message: 'The reader backed out of the consent screen' }];
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText('Google sign-in was canceled.');
  await expect(banner(a.page)).toBeHidden();
  await a.page.keyboard.press('Escape');
  await expect(row(a.page)).toHaveText('Off');
  await settingsButton(a.page, 'Sync ›').click();

  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  await expect(banner(a.page)).toBeHidden();
  expect(a.errors).toEqual([]);
  await a.context.close();
});

test('every answer bridge does not recognise is said as unexpected, with which case it was and the answer whole', async ({ browser }) => {
  test.setTimeout(300000);
  const server = drive();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile({ title: 'Outcomes', author: 'Sync Tests', chapters: 2, rawChapters: chapters(2) })], 1);
  await openSync(a.page);

  const scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  const hidden = n => `[hidden, ${n} bytes]`;
  const granted = (fields) => ({ authorization: { accessToken: 'SECRET-TOKEN-1', grantedScopes: scopes, account: null, ...fields } });
  const shownGranted = (fields) => ({ json: { authorization: { accessToken: hidden(14), grantedScopes: scopes, account: null, ...fields } } });
  const thrown = { json: rejection('it threw') };
  const rows = [
    [{ error: 'UNEXPECTED', message: 'IllegalStateException: odd' }, 'RejectedOther, CodeUnexpected', { json: rejection('IllegalStateException: odd', 'UNEXPECTED') }],
    [{ error: 'INVALID_OPTIONS', message: 'no scopes' }, 'RejectedOther, CodeInvalidOptions', { json: rejection('no scopes', 'INVALID_OPTIONS') }],
    [{ error: 'SUCCESS', message: 'success' }, 'RejectedOther, CodeSuccess', { json: rejection('success', 'SUCCESS') }],
    [{ error: 'SUCCESS_CACHE', message: 'cached' }, 'RejectedOther, CodeSuccessCache', { json: rejection('cached', 'SUCCESS_CACHE') }],
    [{ error: 'SOMETHING_NEW', message: 'new in Play services' }, 'RejectedOther, CodeUnknown', { json: rejection('new in Play services', 'SOMETHING_NEW') }],
    [{ error: '', message: 'an empty code' }, 'RejectedOther, CodeEmpty', { json: rejection('an empty code', '') }],
    [{ reject: { code: null, message: 'a null code' } }, 'RejectedOther, CodeNull', { json: { code: null, message: 'a null code' } }],
    [{ error: null, message: 'no code given' }, 'RejectedOther, CodeMissing', { json: rejection('no code given') }],
    [{ reject: 'refused as a string' }, 'RejectionNotObject, KindString', { json: 'refused as a string' }],
    [{ reject: null }, 'RejectionNotObject, KindNull', { json: null }],
    [{ reject: 42 }, 'RejectionNotObject, KindNumber', { json: 42 }],
    [{ reject: true }, 'RejectionNotObject, KindBool', { json: true }],
    [{ reject: [] }, 'RejectionNotObject, KindArray', { json: [] }],
    [{ reject: { code: 7, message: '7: offline' } }, 'CodeNotText, KindNumber', { json: { code: 7, message: '7: offline' } }],
    [{ reject: { code: true } }, 'CodeNotText, KindBool', { json: { code: true } }],
    [{ reject: { code: [] } }, 'CodeNotText, KindArray', { json: { code: [] } }],
    [{ reject: { code: {} } }, 'CodeNotText, KindObject', { json: { code: {} } }],
    [{ rejectMade: 'undefined' }, 'RejectionUndefined', null],
    [{ resolveMade: 'undefined' }, 'AnswerUndefined', null],
    [{ resolveMade: 'null' }, 'AnswerNotObject, KindNull', { json: null }],
    [{ resolveMade: 'true' }, 'AnswerNotObject, KindBool', { json: true }],
    [{ resolveMade: 'number' }, 'AnswerNotObject, KindNumber', { json: 42 }],
    [{ resolveMade: 'text' }, 'AnswerNotObject, KindString', { json: 'text' }],
    [{ resolveMade: 'array' }, 'AnswerNotObject, KindArray', { json: [] }],
    [{ odd: 1 }, 'NoAuthorization, AuthorizationMissing', { json: { odd: 1 } }],
    [{ authorization: null }, 'NoAuthorization, AuthorizationNull', { json: { authorization: null } }],
    [{ authorization: 5 }, 'NoAuthorization, AuthorizationNotObject', { json: { authorization: 5 } }],
    [{ authorization: { grantedScopes: scopes, account: null } }, 'TokenUnusable, TextMissing', { json: { authorization: { grantedScopes: scopes, account: null } } }],
    [granted({ accessToken: 42 }), 'TokenUnusable, TextNotString', shownGranted({ accessToken: 42 })],
    [granted({ accessToken: '' }), 'TokenUnusable, TextEmpty', shownGranted({ accessToken: hidden(0) })],
    [granted({ accessToken: 'tok en' }), 'TokenUnusable, TextNotPrintable', shownGranted({ accessToken: hidden(6) })],
    [{ authorization: { accessToken: 'SECRET-TOKEN-1', account: null } }, 'ScopesUnusable, ScopesMissing', { json: { authorization: { accessToken: hidden(14), account: null } } }],
    [granted({ grantedScopes: 'scope-a' }), 'ScopesUnusable, ScopesNotList', shownGranted({ grantedScopes: 'scope-a' })],
    [granted({ grantedScopes: [] }), 'ScopesUnusable, ScopesEmpty', shownGranted({ grantedScopes: [] })],
    [granted({ grantedScopes: [42] }), 'ScopesUnusable, ScopeNotString', shownGranted({ grantedScopes: [42] })],
    [granted({ grantedScopes: [''] }), 'ScopesUnusable, ScopeEmpty', shownGranted({ grantedScopes: [''] })],
    [granted({ grantedScopes: ['scope a'] }), 'ScopesUnusable, ScopeNotPrintable', shownGranted({ grantedScopes: ['scope a'] })],
    [{ authorization: { accessToken: 'SECRET-TOKEN-1', grantedScopes: scopes } }, 'AccountUnusable, TextMissing', { json: { authorization: { accessToken: hidden(14), grantedScopes: scopes } } }],
    [granted({ account: 42 }), 'AccountUnusable, TextNotString', shownGranted({ account: 42 })],
    [granted({ account: '' }), 'AccountUnusable, TextEmpty', shownGranted({ account: '' })],
    [granted({ account: 'a b' }), 'AccountUnusable, TextNotPrintable', shownGranted({ account: 'a b' })],
    [{ resolveMade: 'cycle' }, 'AnswerNotJson', { form: 'as String gives it', text: '[object Object]' }],
    [{ resolveMade: 'unwritable' }, 'AnswerNotJson', { form: 'as its type', text: 'object' }],
    [{ rejectMade: 'cycle' }, 'RejectionNotJson', { form: 'as String gives it', text: '[object Object]' }],
    [{ rejectMade: 'unwritable' }, 'RejectionNotJson', { form: 'as its type', text: 'object' }],
    [{ resolveMade: 'deep' }, 'AnswerUnparsed, json: TooDeep at 512', { form: 'as JSON', text: '['.repeat(513) + ']'.repeat(513) }],
    [{ rejectMade: 'deep' }, 'RejectionUnparsed, json: TooDeep at 512', { form: 'as JSON', text: '['.repeat(513) + ']'.repeat(513) }],
    [{ arms: [{ at: 'lookup', value: 'error' }] }, 'Thrown, LookupThrew', thrown],
    [{ arms: [{ at: 'arguments', value: 'error' }] }, 'Thrown, ArgumentsThrew', thrown],
    [{ arms: [{ at: 'method', value: 'error' }] }, 'Thrown, MethodThrew', thrown],
    [{ arms: [{ at: 'lookup', value: 'undefined' }] }, 'ThrownUndefined, LookupThrew', null],
    [{ arms: [{ at: 'arguments', value: 'undefined' }] }, 'ThrownUndefined, ArgumentsThrew', null],
    [{ arms: [{ at: 'method', value: 'undefined' }] }, 'ThrownUndefined, MethodThrew', null],
    [{ arms: [{ at: 'returns', value: 'error' }] }, 'NotAPromise', thrown],
    [{ arms: [{ at: 'returns', value: 'undefined' }] }, 'NotAPromiseUndefined', null],
    [{ arms: [{ at: 'returns', value: 'error' }, { at: 'keep', value: 'error', count: 2 }] }, 'NothingKept, StageReturned', null],
    [{ arms: [{ at: 'keep', value: 'error', count: 1 }] }, 'AnswerNotJson', { form: 'as its type, its text not kept', text: 'object' }],
    [{ error: 'NETWORK_ERROR', message: '7: offline', arms: [{ at: 'keep', value: 'error', count: 1 }] }, 'RejectionNotJson', { form: 'as its type, its text not kept', text: 'object' }],
    [{ arms: [{ at: 'keep', value: 'error', count: 2 }] }, 'NothingKept, StageResolved', null],
    [{ error: 'NETWORK_ERROR', message: '7: offline', arms: [{ at: 'keep', value: 'error', count: 2 }] }, 'NothingKept, StageRejected', null],
    [{ arms: [{ at: 'lookup', value: 'error' }, { at: 'keep', value: 'error', count: 2 }] }, 'NothingKept, StageLookup', null],
    [{ arms: [{ at: 'arguments', value: 'error' }, { at: 'keep', value: 'error', count: 2 }] }, 'NothingKept, StageArguments', null],
    [{ arms: [{ at: 'method', value: 'error' }, { at: 'keep', value: 'error', count: 2 }] }, 'NothingKept, StageMethod', null],
  ];
  for (const [row, which, shown] of rows) {
    const { arms, ...answer } = row;
    a.google.outcomes.authorizeScopes = [Object.keys(answer).length || !arms ? answer : undefined].filter(x => x !== undefined);
    if (arms) await a.page.evaluate(list => { window.__googleThrows = list; }, arms);
    await chooseAndroid(a.page);
    const copy = await saidWithDetails(a.page, UNEXPECTED,
      `Platform: Android app\nWhile: signing in to Google\nCall: authorizeScopes\nCase: ${which}`, shown);
    expect(copy).not.toContain('SECRET-TOKEN');
    expect(copy).not.toContain('tok en');
    await expect(status(a.page)).toHaveText('An unexpected error occurred while signing in to Google.');
    await dismiss(a.page);
    a.google.outcomes.authorizeScopes = [];
  }

  const huge = '{"pad":"' + 'x'.repeat(1048577) + '"}';
  const large = [
    [{ resolveMade: 'huge' }, 'AnswerTooLarge'],
    [{ rejectMade: 'huge' }, 'RejectionTooLarge'],
    [{ arms: [{ at: 'lookup', value: 'huge' }] }, 'ThrownTooLarge, LookupThrew'],
    [{ arms: [{ at: 'arguments', value: 'huge' }] }, 'ThrownTooLarge, ArgumentsThrew'],
    [{ arms: [{ at: 'method', value: 'huge' }] }, 'ThrownTooLarge, MethodThrew'],
    [{ arms: [{ at: 'returns', value: 'huge' }] }, 'NotAPromiseTooLarge'],
  ];
  for (const [row, which] of large) {
    const { arms, ...answer } = row;
    a.google.outcomes.authorizeScopes = arms ? [] : [answer];
    if (arms) await a.page.evaluate(list => { window.__googleThrows = list; }, arms);
    await chooseAndroid(a.page);
    await expect(banner(a.page)).toHaveText(new RegExp('^' + escape(UNEXPECTED)));
    await banner(a.page).getByRole('button', { name: 'Copy details' }).click();
    await expect.poll(() => clipboard(a.page)).toMatch(VERSION);
    const copy = (await clipboard(a.page)).replace(VERSION, '');
    const head = `Platform: Android app\nWhile: signing in to Google\nCall: authorizeScopes\nCase: ${which}\n`
      + `Answer, as JSON, cut: its first 1048576 bytes of ${huge.length}: `;
    const cut = '\n[the details are cut here: they hold 1 MiB]';
    expect(copy.startsWith(head)).toBe(true);
    expect(copy.endsWith(cut)).toBe(true);
    expect(copy.slice(head.length, copy.length - cut.length)).toBe(huge.slice(0, copy.length - cut.length - head.length));
    await dismiss(a.page);
  }

  await a.page.keyboard.press('Escape');
  await a.page.evaluate(() => { window.__googleThrows = [{ at: 'presence', value: 'error' }]; });
  await settingsButton(a.page, 'Sync ›').click();
  await expect(panel(a.page).getByRole('button', { name: 'Google Drive ›' })).toBeHidden();
  await saidWithDetails(a.page, "An unexpected error occurred while looking for Google's authorization in the app. Copy the details and post them in a report.",
    "Platform: Android app\nWhile: looking for Google's authorization in the app\nCall: GoogleAuthorize lookup\nCase: Thrown, LookupThrew", thrown);
  await dismiss(a.page);
  expect(a.errors).toEqual([]);
  await a.context.close();
});

test('a sync the app makes by itself, and Turn off, say each answer of Google\'s', async ({ browser }) => {
  test.setTimeout(180000);
  const server = drive();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile({ title: 'Outcomes', author: 'Sync Tests', chapters: 2, rawChapters: chapters(2) })], 1);
  await openSync(a.page);
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText(/^Last synced on /);

  async function regrant(given, refused) {
    a.google.cached = null;
    server.token = a.google.token = given;
    await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
    await expect.poll(() => server.accepted.includes(given)).toBe(true);
    await expect(status(a.page)).toHaveText(/^Last synced on /);
    server.token = a.google.token = refused;
  }

  server.token = a.google.token = 'token-2';
  a.google.cached = null;
  a.google.outcomes.clearAuthorizationToken = [{ error: 'UNEXPECTED', message: 'NullPointerException: null' }];
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect.poll(() => server.accepted.includes('token-2')).toBe(true);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  await saidWithDetails(a.page, 'An unexpected error occurred while clearing a token Google Drive refused. Copy the details and post them in a report.',
    'Platform: Android app\nWhile: clearing a token Google Drive refused\nCall: clearAuthorizationToken\nCase: RejectedOther, CodeUnexpected',
    { json: rejection('NullPointerException: null', 'UNEXPECTED') });
  await dismiss(a.page);

  server.token = a.google.token = 'token-3';
  a.google.outcomes.authorizationForScopes = [{ error: 'NETWORK_ERROR', message: '7: offline' }];
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await saidWithDetails(a.page, "Can't reach Google. Check the connection, then try again. Details: NETWORK_ERROR (7)",
    'Platform: Android app\nWhile: signing in to Google\nCall: authorizationForScopes\nCode: NETWORK_ERROR',
    { json: rejection('7: offline', 'NETWORK_ERROR') });
  await expect(status(a.page)).toHaveText(/^Can't reach Google\. Check the connection, then try again\. \(Sync tried on .*\.\) Details: NETWORK_ERROR \(7\)$/);
  await dismiss(a.page);

  await regrant('token-4', 'token-5');
  a.google.outcomes.clearAuthorizationToken = [{ error: 'INTERNAL_ERROR', message: '8: failed' }];
  a.google.outcomes.authorizationForScopes = [{ error: 'CONSENT_SHOWING', message: 'a screen is showing' }];
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await saidWithDetails(a.page, 'An unexpected error occurred while syncing with Google. Copy the details and post them in a report.',
    'Platform: Android app\nWhile: syncing with Google\nCall: authorizationForScopes\nCase: RejectedOther, CodeConsentShowing',
    { json: rejection('a screen is showing', 'CONSENT_SHOWING') });
  await expect(status(a.page)).toContainText('An unexpected error occurred while signing in to Google.');
  await dismiss(a.page);

  await regrant('token-6', 'token-7');
  a.google.outcomes.clearAuthorizationToken = [{ error: 'UNIMPLEMENTED', message: 'Not implemented' }];
  a.google.outcomes.authorizationForScopes = [{ error: 'UNIMPLEMENTED', message: 'Not implemented' }];
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(banner(a.page)).toHaveText(/^Android sync isn't set up in this build of Quire\./);
  await expect(status(a.page)).toContainText("Android sync isn't set up in this build of Quire.");
  await dismiss(a.page);

  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  const revokes = [
    [{ error: 'NETWORK_ERROR', message: '7: offline' }, async () => {
      await saidWithDetails(a.page,
        "Google didn't take back Quire's access to Drive: remove it in your Google account, under Security, Your connections to third-party apps. Details: NETWORK_ERROR (7)",
        "Platform: Android app\nWhile: taking back Quire's access to Google Drive\nCall: revokeAccess\nCode: NETWORK_ERROR",
        { json: rejection('7: offline', 'NETWORK_ERROR') });
    }],
    [{ error: 'UNIMPLEMENTED', message: 'Not implemented' }, async () => {
      await expect(banner(a.page)).toHaveText(/^Google didn't take back Quire's access to Drive: remove it in your Google account, under Security, Your connections to third-party apps\./);
      await expect(banner(a.page).getByRole('button', { name: 'Copy details' })).toBeHidden();
    }],
    [{ error: 'UNEXPECTED', message: 'IllegalStateException: odd' }, async () => {
      await saidWithDetails(a.page, "An unexpected error occurred while taking back Quire's access to Google Drive. Copy the details and post them in a report.",
        "Platform: Android app\nWhile: taking back Quire's access to Google Drive\nCall: revokeAccess\nCase: RejectedOther, CodeUnexpected",
        { json: rejection('IllegalStateException: odd', 'UNEXPECTED') });
    }],
    [{ odd: 'resolved with something' }, async () => {
      await saidWithDetails(a.page, "An unexpected error occurred while taking back Quire's access to Google Drive. Copy the details and post them in a report.",
        "Platform: Android app\nWhile: taking back Quire's access to Google Drive\nCall: revokeAccess\nCase: ChangeResolvedWith",
        { json: { odd: 'resolved with something' } });
    }],
    [undefined, async () => {
      await expect(banner(a.page)).toBeHidden();
    }],
  ];
  for (const [answer, said] of revokes) {
    a.google.outcomes.authorizeScopes = [];
    if (!(await panel(a.page).getByRole('button', { name: 'Turn off' }).isVisible())) {
      await chooseAndroid(a.page);
      await expect(status(a.page)).toHaveText(/^Last synced on /);
    }
    a.google.outcomes.revokeAccess = [answer];
    const asked = a.google.asked('revokeAccess').length;
    await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
    await expect(status(a.page)).toHaveText('Sync is off.');
    // the offer stays until it is dismissed (quire#364); made final, it takes the grant back
    await a.page.getByRole('status').filter({ hasText: 'Sync turned off' }).getByRole('button', { name: 'Dismiss' }).click();
    await expect.poll(() => a.google.asked('revokeAccess').length, { timeout: 15000 }).toBe(asked + 1);
    await said();
    if (await banner(a.page).isVisible()) await dismiss(a.page);
  }
  expect(a.errors).toEqual([]);
  await a.context.close();
});
