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

Quire's version is the date of the commit it is built from, never of the build, so the same
commit always gives the same version (#219): the committer date in UTC,
`YEAR.MONTH.DAY.SECONDS` (seconds since midnight), and the short SHA, `2026.10.2.61373
(f95ce82)`. bats writes the commit's facts as a module (`build/src/_bats_facts`, from the
commit `BATS_COMMIT` names, else HEAD) and `src/version.bats` words them (`quire_version`,
`quire_commit_short`, `quire_version_text`, `quire_version_code`). The app and gen-pwa compile
them in: About shows the text, a backup records it (`appVersion`), and gen-pwa appends it to
the Android project's `android-release.gradle` as `versionName`, with `versionCode` the
commit count plus an offset (next section). CI names a pull request's own head (`BATS_COMMIT`, set by bats's
setup action: the merge's second parent, so a job that builds checks out at least `fetch-depth: 2`, and
check.yml `build` the whole history, `fetch-depth: 0`, next section) and for a merge group the
group's own commit (`github.sha`). Outside a git repository a build fails and says so;
`tests/static/run.sh` points git at the checkout's repository (`GIT_DIR`).
`tests/version/same.sh` checks that the facts are the same in other time zones, name the
commit, and that the Android project carries the version and its code.

## The version code is the commit count plus an offset (#989, #979)

Keyword: version code. `quire_version_code` is `bats_commit_count()` (the commits reachable from the
built commit, bats#574) plus `VERSION_CODE_OFFSET` (1000000, the one literal of `src/version.bats`: the
private `_version_code_offset` is typed by it, so the compiler holds the two equal). The minutes scheme it replaces (the committer time less the
start of 2025, in minutes) gave two merges a minute apart one code, 955894, and Play refused the
second (run 7, #889 and #886). A count only grows along main, so the code is above its parent's; the
offset is above the highest code Play holds, not only above the code of the failed run (955894): main kept
releasing under the minutes scheme until this merges (run 41112273987 released 961586 on 2026-10-30, and
the scheme adds 1440 a day), so 955000 would have been refused and 1000000 leaves about 28 days. It
never changes afterwards, so one commit always gives one code. **Re-check the offset right before merge**:
read the newest `play-internal` run's "released to the internal track: version code N" on main; the offset
must be above N, else raise it (here, `tests/version/same.sh`'s `HIGHEST_RELEASED`, ANDROID.md) before merging. A shallow clone cannot count: the facts
say so (`CommitHistoryShallow`), `quire_version_code` answers `VersionCodeShallow`, and gen-pwa appends
no versionCode block and exits 1. `dist/pwa` and `dist/android` are already written by then (pwa's
`create_pwa_opening` and `create_android_locked` run first), and the Android project keeps pwa's
fallback `versionCode Integer.parseInt(System.getenv('ANDROID_VERSION_CODE') ?: '1')`; the job fails
before anything is built or released, so a wrong code is never released. The ticket asks only that the
versionCode block be refused, so the statement is what changed, not the order of the writes. Every job that runs gen-pwa to generate
(check.yml `build`, deploy.yml) checks out with `fetch-depth: 0`; the static and e2e jobs never call
it. pwa's release script refuses a code not above the highest on Play (pwa#258).
`tests/version/same.sh` reads the offset from `src/version.bats`, checks the count is git's, the offset and the code are above `HIGHEST_RELEASED` (the highest code released to Play) and the code above the parent's, and
the Android project carries it. `tests/static/guidelines.py` (`lint_version_code`) refuses the minutes
scheme in `src/version.bats` (the committer time or 1735689600) and demands `bats_commit_count`.

## Main goes to Play's internal testing (#308)

Every push to main that passes the whole check is released to Google Play's internal testing
track by `check.yml`'s `play-internal` job, which calls pwa's reusable workflow
`play-release.yml` by commit (the script, its stub of Play and its test live in pwa): the
run's own `release-aab`, the commit's first line as its notes. The caller passes its own `play-release.yml` pin commit as `pwa-ref` (the relock moves both together, area pwa-ref, #851, ci.md,
"CI is pinned"), and its public names as `with:` inputs. It signs in
by Workload Identity Federation, whose provider admits only a push to main of this
repository, so no key exists and no other run can release. Production is a promotion in the
Play Console; ANDROID.md says how.
