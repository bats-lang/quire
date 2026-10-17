---
paths:
  - src/backup.bats
  - src/notice.bats
  - src/import.bats
  - src/opds.bats
  - e2e/backup*
  - e2e/notice*
  - e2e/drm*
---

# Backup and errors

## Backup: Export says it saved, Restore says what it did and can be undone (#362)

A restore overwrites, from the file, the settings (the device's own too), the
books it has in the library (shelf, place when the file's is later,
collections, finished, minutes), the notes of each book it names (the stored
array is replaced, deletions dropped), the reading log's missing days and the
collections it names; a book the library does not have keeps its record as an
orphan ("o").

What is in the library is kept first as a backup file in memory
(`backup_snapshot`, linear: the same file Export makes, into an `export_sink`),
then the file is restored, `_restored(restore_report)` says it (`_restored(1)`
does not type-check: `tests/static/reject/restored-bare-count`), and
`undo_offer(BackupRestored())` is made: `Undone` puts the snapshot back
(`PutBack`: shelf, place and Trash exactly as they were, the reading log
replaced, not merged), `Final` frees it, so an unconsumed snapshot is a type
error (`snapshot-not-handed-on`). A restore whose snapshot cannot be made is
not made; a file found damaged midway is put back at once. An Undo leaves a
collection the restore made (empty) and orphan records until the books are
imported.

Export says how it ended (`export_outcome`, `case+`: `tests/static/reject/
export-unmatched`): in a browser the file is downloaded; in the app a blob
download does nothing in the WebView, so it goes to Android's share sheet
(bridge's `share_file`). Settings says what a backup holds and that the books'
files are not in it.

## Every error says what to do (#360)

The error banner (`error-banner`, `src/notice.bats`) says a failure and a next
step, made in one place from data: `notice_say(failure)`, `notice_say_part`
(a chapter) and `notice_say_named(name, name_len, named_failure)` (a file or
book). The words come from two total `case+` matches, `_what_put` (per `host`:
`InBrowser | InApp`, so the app never says "browser") and `remedy_of` /
`named_remedy_of` (a `remedy`), so a failure added without words or without a
next step does not type-check (`tests/static/reject/notice-without-remedy`).

* Where reopening is the step the banner has Reopen Quire (`error-reopen`). A
  step is words, not a Try again button: no failure has data to retry from, and
  a retry would be a closure (linear).
* A chapter's failure does not say "import the book again" alone (that meets
  the duplicate dialog): it also says to choose Replace.
* `notice_error` is private; `tests/static/notice.py` rejects `notice_error(`
  outside `notice.bats` and a wildcard in a match of `ArchiveFailed(_)`. Import's
  causes are matched one by one (`_archive_named`). A sync's result texts go
  through `notice_sync_said`.
* `expectBannerSaysWhatToDo` (`e2e/helpers.js`) checks a banner has a Reopen
  Quire button or words naming the step, and in the android project no
  "browser".
* **Copy details and Report on every read failure (#507).** A failure about
  stored data or a book that could not be read offers Copy details and a Report
  link, as `notice_unexpected` does, and keeps the details for About's Copy last
  error details. The details are built in one place (`_report_make`): version,
  platform, `_failure_name`, a chapter's number or a file name's length, a line
  saying what they hold ("no book text, titles or passwords"), and for records a
  line for each of the first 16 unusable ones (`record_note`: id, why, size, first
  12 bytes). `detail_source_of` is a total match (`FromFailureAlone`,
  `FromRecordNotes`, `NothingToReport`), so a failure added without saying does
  not type-check (`tests/static/reject/notice-without-details`). A later field is
  one more field of `record_note` and a line of `_put_note`.
  `e2e/notice-details.spec.js`.

## A book that declares its protection is refused, named (#427)

A file that *declares* its encryption is refused at import, before its
container.xml is read (`_protection_check` in `src/import.bats`, import only),
with the scheme named, and not added. In order: `META-INF/license.lcpl`
(`ProtectedByLcp`), `sinf.xml` (`ProtectedByFairPlay`), `rights.xml`
(`ProtectedByAdept`); then `encryption.xml` by `encryption_of`
(`src/epub_xml.bats`): ADEPT's and LCP's namespaces, `kobo.com` or
`kobobooks.com` (`ProtectedByKobo`: a guess at the namespace, no Kobo book was
available), else any `EncryptionMethod` that is neither IDPF's nor Adobe's font
obfuscation (undone by Quire, no DRM) is `ProtectedUnknown`. Each is a
`named_failure` and an `archive_failure`, matched with `case+`. **A damaged
book that declares nothing, or whose encryption.xml cannot be read, stays
"damaged": DRM is never guessed from damage.**

Quire has no client for any scheme, so its words name the scheme (as Thorium
names LCP), say it cannot open it and that the book was not imported, and give
the next step: read it in the app it came from or get a copy without DRM
(`ReadWhereItCameFrom`). It points to no way of removing DRM. The test books
are made by `e2e/drm-books.js`, played by `e2e/drm.spec.js`.

An OPDS entry whose acquisition link is `application/vnd.adobe.adept+xml` or
`application/vnd.readium.lcp.license.v1.0+json` is an `acquiring`
(`AdeptAcquisition`, `LcpAcquisition`, `src/opds.bats`): with no EPUB link of
its own the row says it is protected in place of Get and the licence is never
fetched (`e2e/drm-catalogue.spec.js`).
