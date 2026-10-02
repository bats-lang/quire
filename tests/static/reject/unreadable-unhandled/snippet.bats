(* A read of storage whose failure is left out: it would be taken for
   nothing stored, and what is saved next would go over it (#174) *)
fn _static_unhandled (found: $IDB.lookup): void =
  case+ lookup_content(found) of
  | ~NoStoredContent() => ()
  | ~StoredContent(owner, piece, _) => piece_free(owner, piece)
