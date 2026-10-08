(* A sync's end in a word with the blocked request forgotten: a server
   that lets no browser in would be named as no failure *)
fn _static_failed (result: sync_result): bool =
  case+ result of
  | NotSyncedYet() => false | Synced() => false | Syncing() => false
  | Unreachable() => true | WrongCredentials() => true | FolderNotFound() => true
  | KeptChanging() => true | ServerError() => true | TooLarge() => true
  | Damaged() => true | NoMemory() => true | NoAddress() => true
  | SignInAgain() => true | NoGoogleAccount() => true | NotSetUp() => true
  | GoogleRefused() => true | SignInCanceled() => true
  | DropboxSignInAgain() => true | DropboxNotSetUp() => true
  | DropboxSignInRefused() => true | DropboxSignInCanceled() => true
  | FastmailRefused() => true | GoogleSignInFailed() => true | GoogleAccountNeeded() => true
  | GoogleUnreachable() => true | GoogleConsentShowing() => true | GoogleUnexpected() => true
  | GoogleNoAnswer() => true | GoogleAsking() => false
