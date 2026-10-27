(* A backup read's code bridge never gives left out would be dropped unsaid (keyword: backup-read-answer) *)
fn _static_backup_answer (answer: $BACKUP.backup_read_answer): read_answer =
  case+ answer of
  | ~$BACKUP.BackupReadFound(blob) => let val () = $BD.blob_free(blob) in ReadFailed(Damaged(), 0) end
  | ~$BACKUP.BackupReadNone() => ReadBackupNone()
  | ~$BACKUP.BackupReadEmpty() => ReadBackupEmpty()
  | ~$BACKUP.BackupReadNotHere() => ReadFailed(BackupReadUnavailable(), 0)
  | ~$BACKUP.BackupReadRejected(text) => let val () = _backup_read_text_free(text) in ReadFailed(BackupReadRejected(), 0) end
  | ~$BACKUP.BackupReadThrown(text) => let val () = _backup_read_text_free(text) in ReadFailed(BackupReadThrown(), 0) end
