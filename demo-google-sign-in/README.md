# Google sign-in `authorize()` demo (#316)

This branch is not for merging. It holds the device demo of the
`authorize()` method proposed to Capawesome's
`@capawesome/capacitor-google-sign-in` (0.1.4), so nothing is lost:

- `patches/0001-feat-google-sign-in-add-authorize-method.patch`: the
  change to send upstream, on `capawesome-team/capacitor-plugins` at
  `efa37da2` (the plugin on Android, iOS and Web, a `patch` changeset with
  `@since 0.1.5`, the README, and the example's new buttons and log).
- `patches/0002-chore-google-sign-in-demo-build-of-the-example-not-f.patch`:
  demo only, never upstream: package `io.github.batslang.googlesignindemo`,
  Quire's Web client ID and the `drive.appdata` scope, and the debug build
  signed with `demo.jks`.
- `app-debug.apk`: the example built from both patches.
- `demo.jks`: the throwaway demo keystore.

## The keystore

A throwaway key made only for this demo (it signs nothing else):

- file `demo.jks` (PKCS12), alias `demo`
- store password and key password: `g5jwKdpyVSP_qUndX1wglzKQ`
- DN `CN=Quire sign-in demo`, valid 2026-10-05 to 2036-10-02
- SHA-1 `7F:D1:24:96:68:77:49:DE:90:B0:BB:22:D0:4E:60:67:BB:61:80:B9`
- SHA-256 `42:3B:47:08:7C:29:7E:DD:ED:CF:C7:50:F6:FC:B9:B8:60:BB:18:1E:75:C1:5D:6D:58:43:C8:4A:2F:33:DB:40`

The APK gets tokens only once the Android OAuth client for that package
and SHA-1 exists in project `162611675413` (#320).

## Rebuilding the APK

```sh
git clone https://github.com/capawesome-team/capacitor-plugins
cd capacitor-plugins
git checkout efa37da2
git am --keep-cr /path/to/demo-google-sign-in/patches/*.patch
npm ci --workspace @capawesome/capacitor-google-sign-in --include-workspace-root --ignore-scripts
npx patch-package
cd packages/google-sign-in
npm run build
cd example
npm ci
npm run build
npx cap sync android
cd android
ANDROID_HOME=<sdk with platforms;android-36 and build-tools;36.0.0> ./gradlew assembleDebug
```

The APK is `android/app/build/outputs/apk/debug/app-debug.apk`. Check it:

```sh
apksigner verify --print-certs app-debug.apk   # SHA-1 7fd12496687749de90b0bb22d04e6067bb6180b9
aapt dump badging app-debug.apk | head -1      # package io.github.batslang.googlesignindemo
```

## What was checked

- `npm run build` (docgen README, tsc, rollup), `eslint` and
  `prettier --check` in `packages/google-sign-in`: pass.
- `./gradlew clean build test` in `packages/google-sign-in/android` (the
  package's `verify:android`): pass.
- The APK: signed by the key above (APK Signature Scheme v2), package
  `io.github.batslang.googlesignindemo`, and it carries the example's
  `authorize({ interactive: false })` and `authorize({ interactive: true })`
  buttons and the plugin's `NEEDS_INTERACTION`.
- Not run here (no macOS): SwiftLint, `pod install` and the iOS
  `xcodebuild` (`verify:ios`). Not run either: the APK on a device, which
  needs the OAuth client of #320.

## Recording

The steps to record are in #316's demo plan, "Owner: the recording".
