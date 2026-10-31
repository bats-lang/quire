(* A backup read's code bridge never gives left out would be dropped unsaid (keyword: backup-read-answer) *)
fn _static_backup_answer (answer: $BACKUP.backup_read_answer): read_answer =
  case+ answer of
  | ~$BACKUP.BackupReadNone() => ReadBackupNone()
