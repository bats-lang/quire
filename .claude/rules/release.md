---
paths:
  - src/version.bats
  - src/bin/gen-pwa.bats
  - tests/version/**
  - .github/workflows/check.yml
  - ANDROID.md
---

# The version and the Play release

## The version is the commit's

Quire's version (#219) is the committer date of the commit in UTC,
`YEAR.MONTH.DAY.SECONDS` (seconds since midnight), and the short SHA, `2026.10.2.61373
(f95ce82)`. bats writes the commit's facts as a module (`build/src/_bats_facts`, from the
commit `BATS_COMMIT` names, else HEAD) and `src/version.bats` words them (`quire_version`,
`quire_commit_short`, `quire_version_text`, `quire_version_code`). The app and gen-pwa compile
them in: About shows the text, a backup records it (`appVersion`), and gen-pwa appends it to
the Android project's `android-release.gradle` as `versionName`, with `versionCode` the same
time in minutes since 2025. CI names a pull request's own head (`BATS_COMMIT`, set by bats's
setup action: the merge's second parent, hence `fetch-depth: 2`) and for a merge group the
group's own commit (`github.sha`). Outside a git repository a build fails and says so;
`tests/static/run.sh` points git at the checkout's repository (`GIT_DIR`).
`tests/version/same.sh` checks that the facts are the same in other time zones, name the
commit, and that the Android project carries the version and its code.

## Main goes to Play's internal testing (#308)

Every push to main that passes the whole check is released to Google Play's internal testing
track by `check.yml`'s `play-internal` job, which calls pwa's reusable workflow
`play-release.yml` by commit (the script, its stub of Play and its test live in pwa): the
run's own `release-aab`, the commit's first line as its notes. The caller passes its own `play-release.yml` pin commit as `pwa-ref` (the relock moves both together, area pwa-ref, #851, ci.md,
"CI is pinned"), and its public names as `with:` inputs. It signs in
by Workload Identity Federation, whose provider admits only a push to main of this
repository, so no key exists and no other run can release. Production is a promotion in the
Play Console; ANDROID.md says how.
