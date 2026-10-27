---
paths:
  - src/sync.bats
  - tests/static/reject/backup-write-answer*
  - tests/static/reject/sync-result-unmatched/*
---

# The answer of writing the Auto Backup file (keyword: backup-write-answer, #934)

`_backup_write` in `src/sync.bats` writes the file Android's Auto Backup restores after a
reinstall with bridge's `backup_file_write_answer`, and matches every constructor of
`backup_write_answer` with `case+` (bridge's rule: every outcome is distinct, the unexpected is
said as such; quire#334).

## What each outcome shows

* `BackupWriteDone`: the write is `Written`, nothing is shown.
* `BackupWriteNotHere` (no such file store in this build): `BackupUnavailable`, "This build of
  Quire can't keep the backup file Android restores after a reinstall."
* `BackupWriteRejected` (Android refused the write): `BackupRejected`, "Android refused to write
  the backup file ... Free some space on the device, then try again."
* `BackupWriteThrown` (the call threw): `BackupThrown`, "Writing the backup file ... failed. Try
  again."
* `BackupWriteUnexpected` (an answer bridge does not know): `notice_unexpected` (Copy details and
  the Report link, the case `BackupWriteUnexpected` with its code) and `BackupUnexpected`.

Before #934 all four were `NoMemory`, which was wrong for each.

## Why the refused and thrown text is dropped

Bridge keeps the platform's text with a refused or thrown write. The banner already names the
outcome, and the text may hold the platform's own wording or a path, so it is freed
(`_backup_text_free`) and not shown. Copy details is for the unexpected case, which has no
outcome to name. This is the one thing not carried over from the answer.

## Stored codes

The four constructors of `sync_result` are stored as 34 to 37 (`BackupUnavailable` 34,
`BackupRejected` 35, `BackupThrown` 36, `BackupUnexpected` 37). The number is the stored value
of "sync-state", so it is a stored format and never renumbered; the bound of `_result_code` is
37. #933 (30 to 33) and #935 (38 to 41) add their own, in any order.

## Guards

`tests/static/reject/backup-write-answer-unexpected-unmatched` is the match without
`BackupWriteUnexpected`, and `reject/sync-result-unmatched` a match over `sync_result` without the
new constructors; patsopt must reject both as nonexhaustive.
