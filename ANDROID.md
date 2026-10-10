# Android app

CI builds Quire's Android app (a Capacitor shell around the PWA) on every
push to main and every pull request: the `android` job of
`.github/workflows/check.yml`. It runs the pwa package's reusable
workflow (`bats-lang/pwa/.github/workflows/android.yml`) on the project
`gen-pwa` writes to `dist/android`. Every run builds and signs the app
the same way, and checks that the AAB and the APK are both signed with
the release key (their signer's SHA-256 fingerprint is the keystore's).
A push to main also uploads them, as two artifacts:

* `release-aab`: the Android App Bundle, for Google Play;
* `release-apk`: the APK, for installing directly.

A third job, `smoke-test`, installs the APK on an Android emulator
(API 34), launches it and waits for the library's "Import EPUB" button,
which only the wasm renders; it fails if that never shows, the app
crashes, or the page logs a console error. Its artifact
`android-smoke-test` has a screenshot of the running app, the UI dump
and the logcat.

The smoke test then shares an EPUB with the running app, as another app
would (it is put in the app's cache and sent with SEND), and waits for
the book's title in the library.

The app opens EPUBs from other apps (VIEW, for `application/epub+zip`)
and takes EPUBs shared to it (SEND, SEND_MULTIPLE): its activity, written
by the pwa package, copies each file to the app's cache and hands it to
the page, which imports it. Its launcher icon is the PWA's
`icon-512.png`.

The app id is `dev.middlefield.quire`, the one Quire is published under.
The version name and code come from the commit (CLAUDE.md, "The version
is the commit's"): the name is `YEAR.MONTH.DAY.SECONDS (sha)`, and the code
is the commit's time in minutes since 2025, so it grows from release to
release as Google Play needs.

## Signing secrets

The release build is signed with a keystore that CI reads from four
repository secrets. The job requires them (`require-signed`): without
them it fails rather than build unsigned, so a pull request from a fork,
which gets no secrets, fails its `android` job.

| Secret              | Value                                   |
|---------------------|-----------------------------------------|
| `KEYSTORE_BASE64`   | the keystore file (`.jks`), base64      |
| `KEYSTORE_PASSWORD` | the keystore's password                 |
| `KEY_ALIAS`         | the alias of the signing key in it      |
| `KEY_PASSWORD`      | the signing key's password              |

The keystore and passwords never enter the repository or the build
output: the workflow decodes the keystore to a temporary file, Gradle
reads the passwords from the environment, and both are removed after the
build.

### 1. Have the keystore

Use the keystore Quire's earlier builds were signed with: Google Play
accepts only updates signed with the app's upload key. If you have none
yet (a new app), make one, and keep it and its passwords somewhere safe,
outside the repository:

```sh
keytool -genkeypair -v -keystore release.jks -alias quire \
  -keyalg RSA -keysize 2048 -validity 10000
```

`keytool` (part of any JDK) asks for the keystore password, your name
and so on, and the key password.

### 2. Encode it

```sh
base64 -w0 release.jks > release.jks.b64            # Linux
base64 -i release.jks | tr -d '\n' > release.jks.b64 # macOS
```

### 3. Store the secrets in bats-lang/quire

With the GitHub CLI, from any directory:

```sh
gh secret set KEYSTORE_BASE64 --repo bats-lang/quire < release.jks.b64
gh secret set KEYSTORE_PASSWORD --repo bats-lang/quire   # prompts for the value
gh secret set KEY_ALIAS --repo bats-lang/quire
gh secret set KEY_PASSWORD --repo bats-lang/quire
rm release.jks.b64
```

Or on github.com: the repository's Settings → Secrets and variables →
Actions → New repository secret, once per secret, pasting the contents
of `release.jks.b64` as `KEYSTORE_BASE64`.

They are repository (or organization) secrets, not environment secrets:
the job passes them to the reusable workflow with `secrets: inherit`,
which does not carry environment secrets.

### 4. Build

Push to main. The `check` workflow's `android` job builds and signs the
AAB and APK and uploads them as the run's `release-aab` and
`release-apk` artifacts.

### 5. Release: internal testing first, then production

Every release goes through Play's **internal testing** track before
production, and every push to main that passes the whole check gets
there by itself (#308): the `check` workflow's `play-internal` job,
after the e2e groups and the Android build and smoke test pass, sends
that run's `release-aab` to the internal track as a completed release
(`scripts/play-release.sh`, the Play Developer API's edits). Play names
the release by its versionName, the commit's version; its notes are the
commit's subject (cut to Play's 500 characters). An edit is committed
with `ERROR_IF_IN_REVIEW`, so a change in review is never cancelled by
it; that release fails instead, and the next push to main tries again.
`tests/play-release/run.sh` checks the script against a stub of Play.

The job signs in by Workload Identity Federation, so no key is stored:
GitHub's OIDC token is exchanged for a token of the service account
`quire-play-release` (Google Cloud project "Quire",
`spring-duality-395520`), which has no Cloud role and only Play's
**Release apps to testing tracks** for Quire. The provider admits only a
push to main of bats-lang/quire (`assertion.repository ==
'bats-lang/quire' && assertion.ref == 'refs/heads/main' &&
assertion.event_name == 'push'`). Its name and the account's address are
public, committed in `scripts/play-release.env`.

Then:

1. Install the release from Play on a test device, as a tester, not by
   sideloading. A device that has the production app installed needs no
   uninstall: Play updates it in place.
2. Check what the release changed on that device. Play signs it with the
   app signing key, as production is, so Google sign-in, Drive sync and
   anything else tied to the signing certificate behave as they will in
   production. A sideloaded `release-apk` is signed with the upload key
   instead, and Google refuses its sign-in (`DEVELOPER_ERROR`): Quire's
   Android OAuth client is registered with Play's app signing SHA-1
   (`scripts/sync-clients.env`).
3. Then promote that same release to production, in the Play Console.

The `release-apk` artifact stays for quick checks that don't involve
anything tied to the signing key.

## Building locally

`bats build` then `dist/debug/gen-pwa` writes `dist/pwa` and
`dist/android`. With Node 22 or 24 (the script runs pnpm through the
corepack they ship; Node 25 ships none), a JDK 21 and the Android SDK
(`ANDROID_HOME`):

```sh
ANDROID_KEYSTORE=/path/to/release.jks \
ANDROID_KEYSTORE_PASSWORD=... ANDROID_KEY_ALIAS=... ANDROID_KEY_PASSWORD=... \
sh dist/android/build-android.sh
```

Leave `ANDROID_KEYSTORE` unset for an unsigned build. The outputs are in
`dist/android/android/app/build/outputs/{bundle,apk}/release/`.
