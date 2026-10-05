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
The version code is the workflow's run number plus 1 (Google Play needs
each upload's to be higher than the last).

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

Push to main. When the `check` workflow's `android` job is done,
download `release-aab` from the run's artifacts
and upload the `.aab` inside to the Google Play Console.

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
