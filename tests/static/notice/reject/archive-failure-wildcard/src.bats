(* An archive that did not open, whatever the cause: a new cause would
   be said as the old ones, with no words of its own *)
fn _static_archive_cause (outcome: archive_outcome): void =
  case+ outcome of
  | ~BookAdded(_) => ()
  | ~BookReopened() => ()
  | ~ArchiveFailed(_) => notice_say(LibraryNotRead())
