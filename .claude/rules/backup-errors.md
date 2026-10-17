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

# Backup, errors and outcomes

## Backup: Export says it saved, Restore says what it did and can be undone (#362)

A restore overwrites, from the file, the settings (the device's own too:
brightness, rotation lock, full screen, voices, sort order), the books it
has in the library (shelf, place when the file's is later, collections,
finished, minutes), the notes of each book it names (the book's stored
array is replaced, deletions dropped), the reading log's missing days,
and the collections it names (made when missing); a book the library
does not have keeps its record as an orphan ("o"). Nothing went to the
Trash, so the Undo rule was not met: nothing was offered back.

Now what is in the library is kept first, as a backup file in memory
(`backup_snapshot`, linear: the same file Export makes, made by the same
code into an `export_sink`, `IntoReader` or `IntoSnapshot`), then the
file is restored, `_restored(restore_report)` says it (books, notes,
settings, days, and the books the backup knows that this library lacks:
`_restored(1)` does not type-check, `tests/static/reject/restored-bare-count`),
and `undo_offer(BackupRestored())` is made; its `Undone` puts the snapshot
back (`PutBack`: shelf, place and Trash exactly as they were, the reading
log replaced, not merged), its `Final` frees it, so a snapshot unconsumed
is a type error (`snapshot-not-handed-on`). A restore whose snapshot
cannot be made (memory, a book's notes unreadable) is not made; a file
found damaged midway is put back at once. Left behind by an Undo: a
collection the restore made stays, empty, and orphan records a restore
kept for books not in the library stay until they are imported.

Export says how it ended (`export_outcome`, matched with `case+`:
`tests/static/reject/export-unmatched`): in a browser the file is
downloaded and the dialog says it is in the downloads; in the app a
blob download does nothing in the WebView, so the file goes to Android's
share sheet (bridge's `share_file`) and the dialog says it was shared,
a closed sheet or a failure is said too. Settings says under Backup,
browser and app alike, what a backup holds and that the books' files are
not in it.

## Every error says what to do (#360)

The error banner (`error-banner`, `src/notice.bats`) says a failure and
a next step, made in one place from data: `notice_say(failure)` for a
fault (`SettingsNotRead`, `BookFileLost`, `StorageFull`,
`RotationNotLockable`, ...; `notice_say_part(chapter)` for a chapter
that could not be read, which it names), and `notice_say_named(name,
name_len, named_failure)` for a file or book that has a name
(`NotAnEpub`, `PackageDamaged`, `FileEmpty`, `BookFileNotStored`, ...).
The words come from two total `case+` matches, `_what_put` (what
happened, per `host`: `InBrowser | InApp`, so the app never says
"browser") and `remedy_of` / `named_remedy_of` (the next step, a
`remedy`: `ReopenQuire`, `ImportAgain`, `OtherChapterOrReplace`,
`ChooseAnotherFile`, `UpdateQuire`, `FreeSpace`, `OpenAgain`,
`RemoveGrantByHand`, `UseDeviceRotation`, `CopyByHand`, `RestoreBackup`,
`TryNextPhrase`), so a failure added without words or without a next
step does not type-check (`tests/static/reject/notice-without-remedy`).
Where reopening is the step, the banner has a Reopen Quire button
(`error-reopen`, a reload). A step is words, not a Try again button: no
failure has data to retry from, and a retry would be a closure (linear).
A chapter's failure does not say "import the book again" alone: that
meets the duplicate dialog, so it also says to choose Replace.
`notice_error` is private; `tests/static/notice.py` (in
`tests/static/run.sh`) rejects `notice_error(` outside `notice.bats` and
a wildcard in a match of `ArchiveFailed(_)` (`tests/static/notice/reject`).
Import's causes are matched one by one (`_archive_named`); only a book
that declares its protection is blamed on DRM (below), never a damaged one. A sync's result texts, made by
`sync.bats` from its `sync_result`, go through `notice_sync_said`.
`expectBannerSaysWhatToDo` (`e2e/helpers.js`) checks a banner has a
Reopen Quire button or words naming the step, and in the android project
no "browser".

## A book that declares its protection is refused, named (#427)

A file that *declares* its encryption is not a guess, so it is refused at
import, before its container.xml is read (`_protection_check` in
`src/import.bats`, only for an import, since a stored book was checked
then), with the scheme named and not added to the library. What it looks
for, in this order: `META-INF/license.lcpl` (Readium LCP,
`ProtectedByLcp`), `META-INF/sinf.xml` (Apple FairPlay,
`ProtectedByFairPlay`), `META-INF/rights.xml` (Adobe ADEPT,
`ProtectedByAdept`); then `META-INF/encryption.xml` read by
`encryption_of` (`src/epub_xml.bats`): `ns.adobe.com/adept` (ADEPT),
`readium.org/2014/01/lcp` (LCP), `kobo.com` or `kobobooks.com` (Kobo,
`ProtectedByKobo`), else any `EncryptionMethod` whose `Algorithm` is
neither font obfuscation (IDPF's `http://www.idpf.org/2008/embedding`,
Adobe's `http://ns.adobe.com/pdf/enc#RC`: undone by a reading system,
no DRM, and not refused) is `ProtectedUnknown`. Each is a
`named_failure` and an `archive_failure` (`DrmAdept`, ...), matched with
`case+`, so a scheme added without words does not type-check. A damaged
book that declares nothing, or whose encryption.xml cannot be read, stays
"damaged": DRM is never guessed from damage.

By research (Thorium, Calibre, Readium's docs): Thorium, which has an LCP
client, only says what is missing ("This publication needs an LCP
passphrase", and, for an encrypted publication with no licence,
"Publication is encrypted but lacks an LCP license!"); Calibre, which has
none for the schemes it cannot open, says the book is locked by DRM and
points the reader to its manual's DRM page, offering no way round it.
Quire has no client for any scheme, so its words name the scheme (as
Thorium names LCP), say it cannot open it and that the book was not
imported, and give the next step, which is to read it in the app it came
from or get a copy without DRM (`ReadWhereItCameFrom`); it points to no
way of removing DRM. A build that one day has a client for a scheme
changes only that scheme's case. Kobo's check is a guess at its
namespace (the issue names `http://www.kobo.com/...`; no Kobo book was
available to look at), written in one place. The books the tests use are
made by `e2e/drm-books.js` (chapter bytes replaced by random ones, the
encryption.xml and licence files written), registered in
`e2e/epubcheck.spec.js`, and played by `e2e/drm.spec.js`.

An OPDS entry whose acquisition link has type
`application/vnd.adobe.adept+xml` or
`application/vnd.readium.lcp.license.v1.0+json` is an `acquiring`
(`AdeptAcquisition`, `LcpAcquisition`, in `src/opds.bats`, kept over the
entry's other acquisitions): with no EPUB link of the entry's own, the
row says "Protected by Adobe DRM: Quire cannot open it, so it cannot be
got here" (or Readium LCP) in place of Get and the licence is never
fetched; an entry that also has an EPUB is got as ever
(`e2e/drm-catalogue.spec.js`).

**Copy details and Report on every read failure (#507).** A failure
whose banner is about stored data or a book that could not be read
offers Copy details and a Report link, as `notice_unexpected` does, and
keeps the details for About's Copy last error details. The details are
data built in one place (`_report_make` in `src/notice.bats`): Quire's
version, the platform, the failure's name (`_failure_name`, a total
match), a chapter's number or the length of a file's name, a line saying
what the details hold ("no book text, titles or passwords") so the
reader sees it before sending (Firefox's about:support and Signal's
debug log both say what they hold, and hold none of the user's content),
and, for a failure of records, how many the last read could not use and a
line for each of the first 16 (`record_note`: the record's id, which is
the hash of a file and not a title, why it cannot be used, its size and
its first 12 bytes, which are the format's magic, kind and versions, as
a crash report keeps a file's header and not its content). The library's
read notes them (`libstore_read`) and the failure that says so takes
them. Which failures have details is `detail_source_of`, a total match
(`FromFailureAlone`, `FromRecordNotes`, `NothingToReport`, the last for a
platform's refusal of a copy, a selection, a rotation lock, a grant or a
narration, which leaves the details of the failure before it in
place), so a failure added without saying does not type-check
(`tests/static/reject/notice-without-details`). A later field (the groups
lost, each one's CRC: #510) is one more field of `record_note` and one
more line of `_put_note`. `e2e/notice-details.spec.js` checks each kind
of record, annotations and settings: the buttons, the fields, no book
text, and About.

## Every outcome is said, and the unexpected as such

After #334, where a Google error that ended the consent screen reached
quire as the reader backing out, and was said only on a line of the
Sync screen:

* The plugin and bridge report every error and unexpected condition as
  an outcome of its own, never folded into another. What they do not
  recognise is an explicit `...Unexpected` constructor, carrying which
  case it was as a datatype (bridge's `google_unexpected`) and the
  answer as bridge's JS wrote it.
* quire matches every answer with `case+` and handles every
  constructor visibly: google_authorize's `AuthorizeRefused` by each
  `google_status` (`_refusal_result` in `src/sync.bats`), a cancel the
  reader made noted on the Sync screen, every other end of a sign-in
  or sync the reader started said in the error banner (`_reader_told`).
* An `...Unexpected` outcome goes through `notice_unexpected`
  (`src/notice.bats`): the error banner says an unexpected error
  occurred while doing what it was doing, with Copy details (Quire's
  version, the platform, what was being done, the call, the case, and
  the answer as the atom kept it, an access token's value written as
  its length) and a Report link to Quire's GitHub issues. A refusal
  with a code is said the same way (`notice_failure`), the code in its
  text ("Details: DEVELOPER_ERROR (10)").
* An e2e test passes through every constructor of every answer quire
  handles (`e2e/sync-android-outcomes.spec.js` for google_authorize);
  an answer bridge's JS never gives is passed through by bridge's own
  dynamic test.
* A call that never answers is an outcome too (#340): no call to Google
  is left pending with nothing shown. A call that shows nothing
  (`authorizationForScopes`, `clearAuthorizationToken`, `revokeAccess`)
  is ended after 30 s (`GOOGLE_ANSWER_MS`: Play services documents no
  timeout, so it is chosen from what comparable software does: OkHttp
  ends a request at 10 s each for connect, read and write; Firebase
  Auth's own 3 minutes is the length developers call too long, and
  Flutter developers who bound a hanging `signIn()` themselves use
  about 30 s; Google's Tasks guide says to bound a wait and gives no
  value, only a 500 ms example; and Nielsen's 10 s is the limit of a
  reader's attention, a sync saying "Syncing..." meanwhile) as `GoogleNoAnswer`: "Google didn't
  answer. Check the connection, then try again." (a revoke's, in the
  banner, with where to take the grant back by hand). The consent screen
  (`authorizeScopes`) is the reader's to take as long as they like, so
  no timer ends it: while it is awaited (`GoogleAsking`) the status card
  says "Waiting for Google's consent screen. Finish it there, or stop
  waiting." and shows Stop waiting (`sync-stop`, `sync_stop`) in place
  of Sync now and Turn off; it ends the ask as the reader's cancel, as
  backing out of Google's screen does, and a second ask meanwhile is
  said as the consent screen already open. Each such call is the
  promise of a resolver kept in a cell with the call's number
  (`answer_wait`, `consent_wait` in `src/sync.bats`): the plugin's
  answer and the timer or Stop waiting each settle that number, the
  first resolves it, and what comes after (the answer of a call already
  ended) is dropped, so it changes nothing, keeps no token and asks
  Google nothing more (`_authorization_late`: a late answer that logged
  the reader in after they were told Google did not answer is what
  Flutter developers who time out Firebase's sign-in found).
  `e2e/sync-android-hang.spec.js` leaves each call pending (`hold` in
  `e2e/sync-stores.js`) and settles it late.
