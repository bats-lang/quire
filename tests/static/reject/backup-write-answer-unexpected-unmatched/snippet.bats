(* A backup write's answer with the code bridge never gives left out:
   an unexpected answer would be dropped unsaid (keyword: backup-write-answer) *)
fn _static_backup_answer (answer: $BACKUP.backup_write_answer): bool =
  case+ answer of
  | ~$BACKUP.BackupWriteDone() => true
