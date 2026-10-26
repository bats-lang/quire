(* A backup read's answer with the code bridge never gives left out:
   an unexpected answer would be dropped unsaid (keyword: backup-read-answer) *)
fn _static_backup_answer (answer: $BACKUP.backup_read_answer): bool =
  case+ answer of
  | ~$BACKUP.BackupReadFound(blob) => let val () = $BD.blob_free(blob) in true end
  | ~$BACKUP.BackupReadNone() => false
  | ~$BACKUP.BackupReadNotHere() => false
  | ~$BACKUP.BackupReadEmpty() => false
  | ~$BACKUP.BackupReadRejected(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)
  | ~$BACKUP.BackupReadThrown(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)

