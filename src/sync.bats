(* sync -- the reader's places, shelves, collections, annotations and
   reading time, the same on each of their devices: one file,
   quire-sync.json, in a WebDAV folder the reader names (with its user
   name and password, kept only on this device). A sync reads the file
   (GET), merges it with what this device has, and writes the merge back
   (PUT, If-Match the ETag it read, so a write made meanwhile by another
   device is not lost: the sync starts again, up to TRIES times); only
   once the file is written does this device take the merge, so a sync
   that fails changes nothing here. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use json as J
#use str as S

staload "ui.sats"
staload "notice.sats"
staload "layer.sats"
staload "undo.sats"
staload "book.sats"
staload "library.sats"
staload "annot.sats"
staload "stats.sats"
staload "backup.sats"
staload "jsonio.sats"
staload "mem.sats"
staload "clock.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload "storage.sats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload GOOGLE = "wasm.bats-packages.dev/bridge/src/google_account.sats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"
staload BACKUP = "wasm.bats-packages.dev/bridge/src/backup_file.sats"
staload "drive.sats"
staload "sync_clients.sats"
staload "dropbox.sats"
staload "web_request.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload AL = "wasm.bats-packages.dev/bridge/src/app_link.sats"
staload BT = "wasm.bats-packages.dev/bridge/src/browser_tab.sats"
staload "nextcloud.sats"

(* Whether this app can sign in to Dropbox through the system's browser:
   it opens Dropbox's page in a tab over the app (bridge's Browser
   plugin) and is told the address Dropbox sends the reader back to (its
   App plugin). Both are needed: quire's own sequencing of the two *)
fn _round_trip_available (): bool =
  $BT.browser_tab_available() && $AL.app_link_available()

(* The sync file's most bytes: a larger one is refused *)
#define SYNC_MAX_BYTES 16777216
(* The folder's URL's, the user name's and the password's most bytes *)
#define URL_MAX 1024
#define USER_MAX 256
#define PASSWORD_MAX 256
(* An ETag's most bytes *)
#define ETAG_MAX 256
(* The tries of a sync whose write another device's beat (412) *)
#define TRIES 3
(* The Google account's address's and an access token's most bytes *)
#define ACCOUNT_MAX 256
#define TOKEN_MAX 4096
(* A Dropbox refresh token's most bytes *)
#define REFRESH_MAX 512

(* ============================================================
   The store the file is kept in, and its credentials: on this device
   only
   ============================================================ *)

(* Where the sync file is kept. Each kind is a constructor, with its own
   credentials and its own read and write (store_read, store_write):
   the merge and its tries call only those. WebDAV: the folder's URL,
   the user name and the password. Android (the app): the Google account
   on the device, its address kept for the screen; the file is in its
   Drive's app data folder (drive.bats), read and written with an
   access token kept on this device (_token, _google_token_save) *)
datavtype store =
  | NoStore of ()
  | {url_loc,user_loc,password_loc:agz}{url_len:pos | url_len <= URL_MAX}{user_len:nat | user_len <= USER_MAX}{password_len:nat | password_len <= PASSWORD_MAX}
    WebDav of ($A.arr(byte, url_loc, URL_MAX), int url_len, $A.arr(byte, user_loc, USER_MAX), int user_len,
               $A.arr(byte, password_loc, PASSWORD_MAX), int password_len)
  | {account_loc:agz}{account_len:nat | account_len <= ACCOUNT_MAX}
    Android of ($A.arr(byte, account_loc, ACCOUNT_MAX), int account_len)
  | {refresh_loc:agz}{refresh_len:pos | refresh_len <= REFRESH_MAX}
    Dropbox of ($A.arr(byte, refresh_loc, REFRESH_MAX), int refresh_len)
  (* Fastmail: its files over WebDAV, in the folder quire of the
     account's own (FASTMAIL_FOLDER), with the Fastmail address and an
     app password that may reach Files *)
  | {user_loc,password_loc:agz}{user_len:pos | user_len <= USER_MAX}{password_len:pos | password_len <= PASSWORD_MAX}
    Fastmail of ($A.arr(byte, user_loc, USER_MAX), int user_len, $A.arr(byte, password_loc, PASSWORD_MAX), int password_len)

fn _store_free (held: store): void =
  case+ held of
  | ~NoStore() => ()
  | ~WebDav(url, _, user, _, password, _) => let
      val () = $A.free<byte>(url)
      val () = $A.free<byte>(user)
    in $A.free<byte>(password) end
  | ~Android(account, _) => $A.free<byte>(account)
  | ~Dropbox(refresh, _) => $A.free<byte>(refresh)
  | ~Fastmail(user, _, password, _) => let
      val () = $A.free<byte>(user)
    in $A.free<byte>(password) end

val _store = ref<store>(NoStore())
(* The store turned off, while its Undo is offered *)
val _store_off = ref<store>(NoStore())

fn _store_swap (cell: ref(store), held: store): store = let
  var previous: store = held
  val () = ref_exch_elt<store>(cell, previous)
in previous end

fn _store_on (): bool = let
  val held = _store_swap(_store, NoStore())
  val configured = (case+ held of WebDav(_, _, _, _, _, _) => true | Android(_, _) => true | Dropbox(_, _) => true | Fastmail(_, _, _, _) => true | NoStore() => false): bool
  val () = _store_free(_store_swap(_store, held))
in configured end

(* This device's number in the sync file (0 until it has one), the
   minute of the last sync, and,
   when the server answered with an error, its status *)
val _device = ref<Int>(0)
val _last_minutes = ref<Int>(0)
val _last_status = ref<Int>(0)

(* How a sync ended: not yet; synced; the server not reached, or (from
   another origin) refused by the browser; the credentials refused; the
   folder not found; the file kept changing; another error from the
   server; the file too large, or not one Quire can read; no memory for
   it; under way; or no folder's address. Android: no token (one is
   asked for when the reader acts), no Google account on the device, no
   client ID in this build, Google refused (the build's clients not
   registered for this app), the reader said no. Dropbox: its sign-in no
   longer good (the reader took the app's access away), no app key in
   this build, a sign-in Dropbox or the page refused (a state that is
   not the one sent), the reader said no. Fastmail: its address or app
   password refused. Google, in the app (each of Play services' answers
   handled as its own, #334): the sign-in failed for another reason
   (GoogleSignInFailed), the device's Google account must be signed in
   to again (SIGN_IN_REQUIRED, INVALID_ACCOUNT), Google not reached
   (NETWORK_ERROR, TIMEOUT), another consent screen open, an answer not
   recognised (GoogleUnexpected, said in the banner with its details) *)
datatype sync_result =
  | NotSyncedYet | Synced | Unreachable | WrongCredentials | FolderNotFound | KeptChanging | ServerError
  | TooLarge | Damaged | NoMemory | Blocked | Syncing | NoAddress
  | SignInAgain | NoGoogleAccount | NotSetUp | GoogleRefused | SignInCanceled
  | DropboxSignInAgain | DropboxNotSetUp | DropboxSignInRefused | DropboxSignInCanceled
  | FastmailRefused
  | GoogleSignInFailed | GoogleAccountNeeded | GoogleUnreachable | GoogleConsentShowing | GoogleUnexpected
  | GoogleNoAnswer | GoogleAsking

(* A result as "sync-state" stores it, and back: decoded once, as it is
   read (an unknown number is not synced yet) *)
fn _result_code (result: sync_result): [code:nat | code <= 29] int code =
  case+ result of
  | NotSyncedYet() => 0
  | Synced() => 1
  | Unreachable() => 2
  | WrongCredentials() => 3
  | FolderNotFound() => 4
  | KeptChanging() => 5
  | ServerError() => 6
  | TooLarge() => 7
  | Damaged() => 8
  | NoMemory() => 9
  | Blocked() => 10
  | Syncing() => 11
  | NoAddress() => 12
  | SignInAgain() => 13
  | NoGoogleAccount() => 14
  | NotSetUp() => 15
  | GoogleRefused() => 16
  | SignInCanceled() => 17
  | DropboxSignInAgain() => 18
  | DropboxNotSetUp() => 19
  | DropboxSignInRefused() => 20
  | DropboxSignInCanceled() => 21
  | FastmailRefused() => 22
  | GoogleSignInFailed() => 23
  | GoogleAccountNeeded() => 24
  | GoogleUnreachable() => 25
  | GoogleConsentShowing() => 26
  | GoogleUnexpected() => 27
  | GoogleNoAnswer() => 28
  | GoogleAsking() => 29

fn _result_of_code (code: int): sync_result =
  if code = 1 then Synced()
  else if code = 2 then Unreachable()
  else if code = 3 then WrongCredentials()
  else if code = 4 then FolderNotFound()
  else if code = 5 then KeptChanging()
  else if code = 6 then ServerError()
  else if code = 7 then TooLarge()
  else if code = 8 then Damaged()
  else if code = 9 then NoMemory()
  else if code = 10 then Blocked()
  else if code = 11 then Syncing()
  else if code = 12 then NoAddress()
  else if code = 13 then SignInAgain()
  else if code = 14 then NoGoogleAccount()
  else if code = 15 then NotSetUp()
  else if code = 16 then GoogleRefused()
  else if code = 17 then SignInCanceled()
  else if code = 18 then DropboxSignInAgain()
  else if code = 19 then DropboxNotSetUp()
  else if code = 20 then DropboxSignInRefused()
  else if code = 21 then DropboxSignInCanceled()
  else if code = 22 then FastmailRefused()
  else if code = 23 then GoogleSignInFailed()
  else if code = 24 then GoogleAccountNeeded()
  else if code = 25 then GoogleUnreachable()
  else if code = 26 then GoogleConsentShowing()
  else if code = 27 then GoogleUnexpected()
  else if code = 28 then GoogleNoAnswer()
  else if code = 29 then GoogleAsking()
  else NotSyncedYet()

(* How the last sync ended *)
val _last_result = ref<sync_result>(NotSyncedYet())

(* The store chosen, under "sync": "QS2\n" and its kind's byte
   (_kind_code); each kind's credentials under a key of its own,
   "sync-webdav", "sync-android", "sync-dropbox", "sync-fastmail". With none chosen, the app keeps the
   file for Android's Auto Backup (BackupKind): the merge is written
   to a backed-up file, and the file a reinstall restored is merged *)
datatype store_kind = WebDavKind | AndroidKind | BackupKind | DropboxKind | FastmailKind | NoStoreKind

fn _kind_code (kind: store_kind): [code:nat | code <= 5] int code =
  case+ kind of WebDavKind() => 1 | AndroidKind() => 2 | BackupKind() => 3 | DropboxKind() => 4 | FastmailKind() => 5 | NoStoreKind() => 0

fn _kind_of_code (code: int): store_kind =
  if code = 1 then WebDavKind() else if code = 2 then AndroidKind() else if code = 3 then BackupKind()
  else if code = 4 then DropboxKind() else if code = 5 then FastmailKind() else NoStoreKind()

fn _choice_key (): [l:agz] $A.arr(byte, l, 4) = let
  val key = $A.alloc<byte>(4)
  val () = $A.write_text(key, 0, $A.text_lit("sync"), 4)
in key end

fn _webdav_key (): [l:agz] $A.arr(byte, l, 11) = let
  val key = $A.alloc<byte>(11)
  val () = $A.write_text(key, 0, $A.text_lit("sync-webdav"), 11)
in key end

fn _android_key (): [l:agz] $A.arr(byte, l, 12) = let
  val key = $A.alloc<byte>(12)
  val () = $A.write_text(key, 0, $A.text_lit("sync-android"), 12)
in key end

(* Dropbox's refresh token, and a sign-in under way (its verifier and
   state, kept while the page is away at Dropbox) *)
fn _dropbox_key (): [l:agz] $A.arr(byte, l, 12) = let
  val key = $A.alloc<byte>(12)
  val () = $A.write_text(key, 0, $A.text_lit("sync-dropbox"), 12)
in key end

(* Fastmail's address and app password *)
fn _fastmail_key (): [l:agz] $A.arr(byte, l, 13) = let
  val key = $A.alloc<byte>(13)
  val () = $A.write_text(key, 0, $A.text_lit("sync-fastmail"), 13)
in key end

(* The Google store's access token, kept on this device (#304) *)
fn _google_token_key (): [l:agz] $A.arr(byte, l, 17) = let
  val key = $A.alloc<byte>(17)
  val () = $A.write_text(key, 0, $A.text_lit("sync-google-token"), 17)
in key end

fn _dropbox_sign_in_key (): [l:agz] $A.arr(byte, l, 20) = let
  val key = $A.alloc<byte>(20)
  val () = $A.write_text(key, 0, $A.text_lit("sync-dropbox-sign-in"), 20)
in key end

(* The store's kind: the one chosen, else the backed-up file where the
   app has one (BackupKind), else none *)
fn _store_kind (): store_kind = let
  val held = _store_swap(_store, NoStore())
  val kind = (case+ held of WebDav(_, _, _, _, _, _) => WebDavKind() | Android(_, _) => AndroidKind() | Dropbox(_, _) => DropboxKind()
    | Fastmail(_, _, _, _) => FastmailKind() | NoStore() => NoStoreKind()): store_kind
  val () = _store_free(_store_swap(_store, held))
in
  case+ kind of
  | NoStoreKind() => if $BACKUP.backup_file_available() then BackupKind() else NoStoreKind()
  | WebDavKind() => kind
  | AndroidKind() => kind
  | DropboxKind() => kind
  | FastmailKind() => kind
  | BackupKind() => kind
end

(* Whether a sync runs: to a store chosen, or to the backed-up file *)
fn _syncing (): bool = case+ _store_kind() of NoStoreKind() => false | WebDavKind() => true | AndroidKind() => true | DropboxKind() => true | FastmailKind() => true | BackupKind() => true

(* Whether the store is the Android one *)
fn _is_android (): bool = case+ _store_kind() of AndroidKind() => true | WebDavKind() => false | DropboxKind() => false | FastmailKind() => false | BackupKind() => false | NoStoreKind() => false

(* Whether the store is the Dropbox one *)
fn _store_kind_is_dropbox (): bool = case+ _store_kind() of DropboxKind() => true | AndroidKind() => false | WebDavKind() => false | FastmailKind() => false | BackupKind() => false | NoStoreKind() => false

(* Whether the store is the Fastmail one *)
fn _store_kind_is_fastmail (): bool = case+ _store_kind() of FastmailKind() => true | DropboxKind() => false | AndroidKind() => false | WebDavKind() => false | BackupKind() => false | NoStoreKind() => false

fn _state_key (): [l:agz] $A.arr(byte, l, 10) = let
  val key = $A.alloc<byte>(10)
  val () = $A.write_text(key, 0, $A.text_lit("sync-state"), 10)
in key end

(* source[0, count) at out[position, position + count) *)
fun _put_bytes {source_loc,out_loc:agz}{owner:addr}{source_size:nat}{count:nat | count <= source_size}{out_size:nat}{position:nat | position + count <= out_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arrx(byte, out_loc, out_size, owner), position: int position, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.write_byte(out, position + j, $AR.low_byte(byte2int0($A.get<byte>(source, j))))
  in _put_bytes(source, count, out, position, j + 1) end

(* The choice of the store of kind, under "sync" *)
fn _choice_save (kind: store_kind): void = let
  val choice = $A.alloc<byte>(5)
  val () = $A.write_text(choice, 0, $A.text_lit("QS2"), 3)
  val () = $A.write_byte(choice, 3, 10)
  val () = $A.write_byte(choice, 4, _kind_code(kind))
  val @(choice_frozen, choice_bytes) = $A.freeze<byte>(choice)
  val @(choice_key_frozen, choice_key_bytes) = $A.freeze<byte>(_choice_key())
  val () = save_checked($IDB.idb_put(choice_key_bytes, 4, choice_bytes, 5))
  val () = release_bytes(choice_key_frozen, choice_key_bytes)
in release_bytes(choice_frozen, choice_bytes) end

(* The WebDAV store's credentials: "QS1\n", then the folder's URL, the
   user name and the password (each a u16 length and its bytes), under
   "sync-webdav"; the Android store's: "QS1\n", then the account's
   address (a u16 length and its bytes), under "sync-android"; and the
   choice of it, under "sync" *)
fn _store_save (): void =
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => ()
  (* Fastmail's: "QS1\n", then the address and the app password (each
     a u16 length and its bytes), under "sync-fastmail" *)
  | ~Fastmail(user, user_len, password, password_len) => let
      val record_len = 8 + user_len + password_len
      val record = $A.alloc<byte>(8 + USER_MAX + PASSWORD_MAX)
      val () = $A.write_text(record, 0, $A.text_lit("QS1"), 3)
      val () = $A.write_byte(record, 3, 10)
      val () = $A.write_u16le(record, 4, user_len)
      val () = _put_bytes(user, user_len, record, 6, 0)
      val () = $A.write_u16le(record, 6 + user_len, password_len)
      val () = _put_bytes(password, password_len, record, 8 + user_len, 0)
      val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
      val @(used, rest) = $A.borrow_split<byte>(record_frozen, record_bytes, record_len)
      val @(key_frozen, key_bytes) = $A.freeze<byte>(_fastmail_key())
      val () = save_checked($IDB.idb_put(key_bytes, 13, used, record_len))
      val () = release_bytes(key_frozen, key_bytes)
      val record_bytes = $A.borrow_join<byte>(record_frozen, used, rest)
      val () = release_bytes(record_frozen, record_bytes)
      val () = _choice_save(FastmailKind())
    in _store_free(_store_swap(_store, Fastmail(user, user_len, password, password_len))) end
  | ~Dropbox(refresh, refresh_len) => let
      val record = $A.alloc<byte>(6 + REFRESH_MAX)
      val () = $A.write_text(record, 0, $A.text_lit("QS1"), 3)
      val () = $A.write_byte(record, 3, 10)
      val () = $A.write_u16le(record, 4, refresh_len)
      val () = _put_bytes(refresh, refresh_len, record, 6, 0)
      val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
      val @(used, rest) = $A.borrow_split<byte>(record_frozen, record_bytes, 6 + refresh_len)
      val @(key_frozen, key_bytes) = $A.freeze<byte>(_dropbox_key())
      val () = save_checked($IDB.idb_put(key_bytes, 12, used, 6 + refresh_len))
      val () = release_bytes(key_frozen, key_bytes)
      val record_bytes = $A.borrow_join<byte>(record_frozen, used, rest)
      val () = release_bytes(record_frozen, record_bytes)
      val () = _choice_save(DropboxKind())
    in _store_free(_store_swap(_store, Dropbox(refresh, refresh_len))) end
  | ~Android(account, account_len) => let
      val record = $A.alloc<byte>(6 + ACCOUNT_MAX)
      val () = $A.write_text(record, 0, $A.text_lit("QS1"), 3)
      val () = $A.write_byte(record, 3, 10)
      val () = $A.write_u16le(record, 4, account_len)
      val () = _put_bytes(account, account_len, record, 6, 0)
      val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
      val @(used, rest) = $A.borrow_split<byte>(record_frozen, record_bytes, 6 + account_len)
      val @(key_frozen, key_bytes) = $A.freeze<byte>(_android_key())
      val () = save_checked($IDB.idb_put(key_bytes, 12, used, 6 + account_len))
      val () = release_bytes(key_frozen, key_bytes)
      val record_bytes = $A.borrow_join<byte>(record_frozen, used, rest)
      val () = release_bytes(record_frozen, record_bytes)
      val () = _choice_save(AndroidKind())
    in _store_free(_store_swap(_store, Android(account, account_len))) end
  | ~WebDav(url, url_len, user, user_len, password, password_len) => let
      val record_len = 10 + url_len + user_len + password_len
      val record = $A.alloc<byte>(10 + URL_MAX + USER_MAX + PASSWORD_MAX)
      val () = $A.write_text(record, 0, $A.text_lit("QS1"), 3)
      val () = $A.write_byte(record, 3, 10)
      val () = $A.write_u16le(record, 4, url_len)
      val () = _put_bytes(url, url_len, record, 6, 0)
      val () = $A.write_u16le(record, 6 + url_len, user_len)
      val () = _put_bytes(user, user_len, record, 8 + url_len, 0)
      val () = $A.write_u16le(record, 8 + url_len + user_len, password_len)
      val () = _put_bytes(password, password_len, record, 10 + url_len + user_len, 0)
      val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
      val @(used, rest) = $A.borrow_split<byte>(record_frozen, record_bytes, record_len)
      val @(key_frozen, key_bytes) = $A.freeze<byte>(_webdav_key())
      val () = save_checked($IDB.idb_put(key_bytes, 11, used, record_len))
      val () = release_bytes(key_frozen, key_bytes)
      val record_bytes = $A.borrow_join<byte>(record_frozen, used, rest)
      val () = release_bytes(record_frozen, record_bytes)
      val () = _choice_save(WebDavKind())
    in _store_free(_store_swap(_store, WebDav(url, url_len, user, user_len, password, password_len))) end

(* No store chosen, and every store's credentials forgotten *)
fn _store_forget (): void = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_choice_key())
  (* checked as a save: a delete that failed would bring the store
     back next run, with the credentials the reader asked to forget *)
  val () = save_checked($IDB.idb_delete(key_bytes, 4))
  val () = release_bytes(key_frozen, key_bytes)
  val @(webdav_frozen, webdav_bytes) = $A.freeze<byte>(_webdav_key())
  val () = save_checked($IDB.idb_delete(webdav_bytes, 11))
  val () = release_bytes(webdav_frozen, webdav_bytes)
  val @(android_frozen, android_bytes) = $A.freeze<byte>(_android_key())
  val () = save_checked($IDB.idb_delete(android_bytes, 12))
  val () = release_bytes(android_frozen, android_bytes)
  val @(dropbox_frozen, dropbox_bytes) = $A.freeze<byte>(_dropbox_key())
  val () = save_checked($IDB.idb_delete(dropbox_bytes, 12))
  val () = release_bytes(dropbox_frozen, dropbox_bytes)
  val @(fastmail_frozen, fastmail_bytes) = $A.freeze<byte>(_fastmail_key())
  val () = save_checked($IDB.idb_delete(fastmail_bytes, 13))
  val () = release_bytes(fastmail_frozen, fastmail_bytes)
  val @(google_frozen, google_bytes) = $A.freeze<byte>(_google_token_key())
  val () = save_checked($IDB.idb_delete(google_bytes, 17))
in release_bytes(google_frozen, google_bytes) end

(* "QS1\n", this device's number, the last sync's minute, result and
   status (4 x i32), under "sync-state" *)
fn _state_save (): void = let
  val record = $A.alloc<byte>(20)
  val () = $A.write_text(record, 0, $A.text_lit("QS1"), 3)
  val () = $A.write_byte(record, 3, 10)
  val () = $A.write_i32(record, 4, !_device)
  val () = $A.write_i32(record, 8, !_last_minutes)
  val () = $A.write_i32(record, 12, _result_code(!_last_result))
  val () = $A.write_i32(record, 16, !_last_status)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_state_key())
  (* never over a state that could not be read (#174) *)
  val () = (if storage_savable(SyncStateRecord()) then save_checked($IDB.idb_put(key_bytes, 10, record_bytes, 20)) else ())
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* The little-endian int at bytes[position, position + 4) *)
fn _i32_at {l:agz}{n:nat}{position:nat | position + 4 <= n} (bytes: !$A.arr(byte, l, n), position: int position): Int = let
  val lowest = $AR.low_byte(byte2int0($A.get<byte>(bytes, position)))
  val second = $AR.low_byte(byte2int0($A.get<byte>(bytes, position + 1)))
  val third = $AR.low_byte(byte2int0($A.get<byte>(bytes, position + 2)))
  val highest = $AR.low_byte(byte2int0($A.get<byte>(bytes, position + 3)))
  val signed_highest = (if highest < 128 then highest else highest - 256): Int
in lowest + second * 256 + third * 65536 + signed_highest * 16777216 end

fn _u16_at {l:agz}{n:nat}{position:nat | position + 2 <= n} (bytes: !$A.arr(byte, l, n), position: int position): [value:nat | value < 65536] int value = let
  val lowest = $AR.low_byte(byte2int0($A.get<byte>(bytes, position)))
  val highest = $AR.low_byte(byte2int0($A.get<byte>(bytes, position + 1)))
in lowest + highest * 256 end

(* out[j, count) := bytes[position + j, position + count) *)
fun _bytes_from {l,out_loc:agz}{n,out_size:nat}{position,count:nat | position + count <= n; count <= out_size}{j:nat | j <= count} .<count - j>.
  (bytes: !$A.arr(byte, l, n), position: int position, count: int count, out: !$A.arr(byte, out_loc, out_size), j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(bytes, position + j))
  in _bytes_from(bytes, position, count, out, j + 1) end

(* The WebDAV store's credentials stored in record[0, n) (checked here,
   once) *)
fn _store_of_record {l:agz}{n:nat} (record: !$A.arr(byte, l, n), n: int n): store =
  if n < 10 then NoStore()
  else if byte2int0($A.get<byte>(record, 1)) <> 83 then NoStore()
  else let
    val url_len = _u16_at(record, 4)
  in
    if url_len <= 0 then NoStore()
    else if url_len > URL_MAX then NoStore()
    else if 10 + url_len > n then NoStore()
    else let
      val user_len = _u16_at(record, 6 + url_len)
    in
      if user_len > USER_MAX then NoStore()
      else if 10 + url_len + user_len > n then NoStore()
      else let
        val password_len = _u16_at(record, 8 + url_len + user_len)
      in
        if password_len > PASSWORD_MAX then NoStore()
        else if 10 + url_len + user_len + password_len > n then NoStore()
        else let
          val url = $A.alloc<byte>(URL_MAX)
          val () = _bytes_from(record, 6, url_len, url, 0)
          val user = $A.alloc<byte>(USER_MAX)
          val () = _bytes_from(record, 8 + url_len, user_len, user, 0)
          val password = $A.alloc<byte>(PASSWORD_MAX)
          val () = _bytes_from(record, 10 + url_len + user_len, password_len, password, 0)
        in WebDav(url, url_len, user, user_len, password, password_len) end
      end
    end
  end

(* The Android store kept in record[0, n) (checked here, once) *)
fn _android_of_record {l:agz}{n:nat} (record: !$A.arr(byte, l, n), n: int n): store =
  if n < 6 then NoStore()
  else if byte2int0($A.get<byte>(record, 1)) <> 83 then NoStore()
  else let
    val account_len = _u16_at(record, 4)
  in
    if account_len > ACCOUNT_MAX then NoStore()
    else if 6 + account_len > n then NoStore()
    else let
      val account = $A.alloc<byte>(ACCOUNT_MAX)
      val () = _bytes_from(record, 6, account_len, account, 0)
    in Android(account, account_len) end
  end

(* ============================================================
   The screen's words
   ============================================================ *)

(* The Dropbox store kept in record[0, n) (checked here, once) *)
fn _dropbox_of_record {l:agz}{n:nat} (record: !$A.arr(byte, l, n), n: int n): store =
  if n < 6 then NoStore()
  else if byte2int0($A.get<byte>(record, 1)) <> 83 then NoStore()
  else let
    val refresh_len = _u16_at(record, 4)
  in
    if refresh_len <= 0 then NoStore()
    else if refresh_len > REFRESH_MAX then NoStore()
    else if 6 + refresh_len > n then NoStore()
    else let
      val refresh = $A.alloc<byte>(REFRESH_MAX)
      val () = _bytes_from(record, 6, refresh_len, refresh, 0)
    in Dropbox(refresh, refresh_len) end
  end

(* The Fastmail store kept in record[0, n) (checked here, once) *)
fn _fastmail_of_record {l:agz}{n:nat} (record: !$A.arr(byte, l, n), n: int n): store =
  if n < 8 then NoStore()
  else if byte2int0($A.get<byte>(record, 1)) <> 83 then NoStore()
  else let
    val user_len = _u16_at(record, 4)
  in
    if user_len <= 0 then NoStore()
    else if user_len > USER_MAX then NoStore()
    else if 8 + user_len > n then NoStore()
    else let
      val password_len = _u16_at(record, 6 + user_len)
    in
      if password_len <= 0 then NoStore()
      else if password_len > PASSWORD_MAX then NoStore()
      else if 8 + user_len + password_len > n then NoStore()
      else let
        val user = $A.alloc<byte>(USER_MAX)
        val () = _bytes_from(record, 6, user_len, user, 0)
        val password = $A.alloc<byte>(PASSWORD_MAX)
        val () = _bytes_from(record, 8 + user_len, password_len, password, 0)
      in Fastmail(user, user_len, password, password_len) end
    end
  end

(* literal at out[position] *)
fn _put_literal {l:agz}{n:nat}{position:nat}{text_len:nat | position + text_len <= n}
  (out: !$A.arr(byte, l, n), position: int position, text: string text_len): int(position + text_len) = let
  val text_len = g1u2i(string1_length(text))
  val () = $A.write_text(out, position, $A.text_lit(text), text_len)
in position + text_len end

(* "The server answered with an error (status).", at out[position] *)
fn _server_error {l:agz}{position:nat | position + 200 <= 512} (out: !$A.arr(byte, l, 512), position: int position, status: Int)
  : [stop:nat | stop <= position + 200] int stop = let
  val after = _put_literal(out, position, "The server answered with an error (")
  val after = $S.int_to_str(out, after, 512, status)
in _put_literal(out, after, ").") end

(* What a sync's end says (at most 200 bytes), at out[position] *)
fn _result_text {l:agz}{position:nat | position + 200 <= 512} (out: !$A.arr(byte, l, 512), position: int position, result: sync_result, status: Int)
  : [stop:nat | stop <= position + 200] int stop =
  case+ result of
  | Unreachable() => _put_literal(out, position, "Can't reach the server.")
  | Blocked() =>
    _put_literal(out, position, "Can't reach the server, or it doesn't let a browser in (CORS): Quire works on without it; to sync, allow this app's origin on the server.")
  | WrongCredentials() => _put_literal(out, position, "The user name or password is wrong.")
  | FolderNotFound() => _put_literal(out, position, "The folder wasn't found.")
  | KeptChanging() => _put_literal(out, position, "The file kept changing on the server. Try again.")
  | TooLarge() => _put_literal(out, position, "The sync file is over 16 MB.")
  | Damaged() => _put_literal(out, position, "The sync file isn't one Quire can read.")
  | NoMemory() => _put_literal(out, position, "There isn't enough memory to sync.")
  | NoAddress() => _put_literal(out, position, "Enter the folder's address, starting with https://.")
  | SignInAgain() => _put_literal(out, position, "Sync paused: tap Sync now to sign in to Google again. What changes here meanwhile is kept.")
  | NoGoogleAccount() => _put_literal(out, position, "Android sync needs a Google account on this device.")
  | NotSetUp() =>
    if $BAPP.is_native_platform() then _put_literal(out, position, "Android sync isn't set up in this build of Quire.")
    else _put_literal(out, position, "Google Drive sync isn't set up in this build of Quire.")
  | GoogleRefused() => _put_literal(out, position, "Google refused: this build of Quire isn't registered with it. Copy the details and post them in a report.")
  | SignInCanceled() => _put_literal(out, position, "Google sign-in was canceled.")
  | GoogleSignInFailed() => _put_literal(out, position, "Google sign-in failed. Try again; if it fails again, copy the details and post them in a report.")
  | GoogleAccountNeeded() => _put_literal(out, position, "Google asks you to sign in to the Google account on this device again: open Android's Settings, then Google, then try again.")
  | GoogleUnreachable() => _put_literal(out, position, "Can't reach Google. Check the connection, then try again.")
  | GoogleConsentShowing() => _put_literal(out, position, "Google's consent screen is already open: finish it, then try again.")
  | GoogleUnexpected() => _put_literal(out, position, "An unexpected error occurred while signing in to Google.")
  | GoogleNoAnswer() => _put_literal(out, position, "Google didn't answer. Check the connection, then try again.")
  | GoogleAsking() => _put_literal(out, position, "Waiting for Google's consent screen. Finish it there, or stop waiting.")
  | DropboxSignInAgain() => _put_literal(out, position, "Dropbox no longer lets Quire in. Tap Dropbox to sign in again.")
  | DropboxNotSetUp() => _put_literal(out, position, "Dropbox sync isn't set up in this build of Quire.")
  | DropboxSignInRefused() => _put_literal(out, position, "Dropbox didn't sign Quire in. Try again.")
  | DropboxSignInCanceled() => _put_literal(out, position, "Dropbox sign-in was canceled.")
  | FastmailRefused() => _put_literal(out, position, "The Fastmail address or app password is wrong.")
  | ServerError() => _server_error(out, position, status)
  (* not failures: their own lines are _status_text's *)
  | NotSyncedYet() => _put_literal(out, position, "Not synced yet.")
  | Synced() => _put_literal(out, position, "Synced.")
  | Syncing() => _put_literal(out, position, "Syncing...")

(* minutes (since the epoch) as the local date and time, "2026-10-01 at
   14:05", at out[position] *)
fn _when_text {l:agz}{position:nat | position + 48 <= 512} (out: !$A.arr(byte, l, 512), position: int position, minutes: Int)
  : [stop:nat | stop <= position + 48] int stop = let
  val local_minutes = minutes + g1ofg0(stats_offset())
  val date = $A.alloc<byte>(32)
  val date_len = date_text(date, local_minutes)
  fun copy {date_loc,out_loc:agz}{count:nat | count <= 32}{at:nat | at + count <= 512}{j:nat | j <= count} .<count - j>.
    (date: !$A.arr(byte, date_loc, 32), count: int count, out: !$A.arr(byte, out_loc, 512), at: int at, j: int j): void =
    if j >= count then ()
    else let val () = $A.set<byte>(out, at + j, $A.get<byte>(date, j)) in copy(date, count, out, at, j + 1) end
  val () = copy(date, date_len, out, position, 0)
  val () = $A.free<byte>(date)
  val after = _put_literal(out, position + date_len, " at ")
  val of_day = (if local_minutes > 0 then local_minutes - (local_minutes / 1440) * 1440 else 0): Int
  val of_day = (if of_day >= 0 then (if of_day < 1440 then of_day else 0) else 0): [of_day:nat | of_day < 1440] int of_day
  val hours = of_day / 60
  val minute = of_day - hours * 60
  val () = $A.write_byte(out, after, $AR.low_byte(48 + hours / 10))
  val () = $A.write_byte(out, after + 1, $AR.low_byte(48 + hours - (hours / 10) * 10))
  val () = $A.write_byte(out, after + 2, 58)
  val () = $A.write_byte(out, after + 3, $AR.low_byte(48 + minute / 10))
  val () = $A.write_byte(out, after + 4, $AR.low_byte(48 + minute - (minute / 10) * 10))
in after + 5 end

(* How a sync failed, and when it was tried *)
fn _tried {l:agz} (out: !$A.arr(byte, l, 512), result: sync_result): [stop:nat | stop <= 512] int stop = let
  val after = _result_text(out, 0, result, !_last_status)
  val after = _put_literal(out, after, " (Sync tried on ")
  val after = _when_text(out, after, !_last_minutes)
in _put_literal(out, after, ".)") end

(* Whether a result is said even with sync off: why Use Android could
   not turn it on *)
fn _said_when_off (result: sync_result): bool =
  case+ result of
  | NoGoogleAccount() => true
  | NotSetUp() => true
  | GoogleRefused() => true
  | SignInCanceled() => true
  | GoogleSignInFailed() => true
  | GoogleAccountNeeded() => true
  | GoogleUnreachable() => true
  | GoogleConsentShowing() => true
  | GoogleUnexpected() => true
  | GoogleNoAnswer() => true
  | GoogleAsking() => true
  | DropboxNotSetUp() => true
  | DropboxSignInRefused() => true
  | DropboxSignInCanceled() => true
  | DropboxSignInAgain() => false
  | FastmailRefused() => false
  | NotSyncedYet() => false | Synced() => false | Unreachable() => false | WrongCredentials() => false
  | FolderNotFound() => false | KeptChanging() => false | ServerError() => false | TooLarge() => false
  | Damaged() => false | NoMemory() => false | Blocked() => false | Syncing() => false | NoAddress() => false
  | SignInAgain() => false

fn _google_refusal (result: sync_result): bool =
  case+ result of
  | NoGoogleAccount() => true
  | NotSetUp() => true
  | GoogleRefused() => true
  | GoogleSignInFailed() => true
  | GoogleAccountNeeded() => true
  | GoogleUnreachable() => true
  | GoogleConsentShowing() => true
  | GoogleUnexpected() => true
  | GoogleNoAnswer() => false
  | GoogleAsking() => false
  | SignInCanceled() => false
  | NotSyncedYet() => false | Synced() => false | Unreachable() => false | WrongCredentials() => false
  | FolderNotFound() => false | KeptChanging() => false | ServerError() => false | TooLarge() => false
  | Damaged() => false | NoMemory() => false | Blocked() => false | Syncing() => false | NoAddress() => false
  | SignInAgain() => false | DropboxSignInAgain() => false | DropboxNotSetUp() => false
  | DropboxSignInRefused() => false | DropboxSignInCanceled() => false | FastmailRefused() => false

fn _told_in_banner (result: sync_result): bool =
  case+ result of
  | Synced() => false
  | NotSyncedYet() => false
  | Syncing() => false
  | SignInCanceled() => false
  | DropboxSignInCanceled() => false
  | GoogleUnexpected() => false
  | GoogleAsking() => false
  | GoogleNoAnswer() => true
  | Unreachable() => true | WrongCredentials() => true | FolderNotFound() => true | KeptChanging() => true
  | ServerError() => true | TooLarge() => true | Damaged() => true | NoMemory() => true | Blocked() => true
  | NoAddress() => true | SignInAgain() => true | NoGoogleAccount() => true | NotSetUp() => true
  | GoogleRefused() => true | DropboxSignInAgain() => true | DropboxNotSetUp() => true
  | DropboxSignInRefused() => true | FastmailRefused() => true | GoogleSignInFailed() => true
  | GoogleAccountNeeded() => true | GoogleUnreachable() => true | GoogleConsentShowing() => true

datavtype refusal_kept =
  | NoRefusalKept
  | {call_len:pos | call_len < 64} RefusalKept of ($GA.google_status, string call_len, answer_shown)

fn _refusal_free (kept: refusal_kept): void =
  case+ kept of
  | ~NoRefusalKept() => ()
  | ~RefusalKept(_, _, answer) => answer_shown_free(answer)

val _refusal = ref<refusal_kept>(NoRefusalKept())

fn _refusal_swap (kept: refusal_kept): refusal_kept = let
  var previous: refusal_kept = kept
  val () = ref_exch_elt<refusal_kept>(_refusal, previous)
in previous end

fn _refusal_forget (): void = _refusal_free(_refusal_swap(NoRefusalKept()))

fn _status_detail {l:agz}{position:nat | position + 80 <= 512}
  (out: !$A.arr(byte, l, 512), position: int position, status: $GA.google_status)
  : [stop:nat | stop <= position + 80] int stop = let
  val after = _put_literal(out, position, "Details: ")
  val after = _put_literal(out, after, $GA.google_status_name(status))
  val after = _put_literal(out, after, " (")
  val number = $GA.google_status_number(status)
  val after = (if number >= 10 then let
      val () = $A.write_byte(out, after, $AR.low_byte(48 + number / 10))
    in after + 1 end else after): [after:nat | after <= position + 76] int after
  val () = $A.write_byte(out, after, $AR.low_byte(48 + number - (number / 10) * 10))
in _put_literal(out, after + 1, ")") end

fn _detail_put {l:agz}{position:nat | position + 80 <= 512} (out: !$A.arr(byte, l, 512), position: int position)
  : [stop:nat | stop <= position + 80] int stop =
  case+ _refusal_swap(NoRefusalKept()) of
  | ~NoRefusalKept() => position
  | ~RefusalKept(status, call, answer) => let
      val stop = _status_detail(out, position, status)
      val () = _refusal_free(_refusal_swap(RefusalKept(status, call, answer)))
    in stop end

fn _with_detail {l:agz}{stop:nat | stop <= 512} (out: !$A.arr(byte, l, 512), stop: int stop, result: sync_result)
  : [after:nat | after <= 512] int after =
  if ~_google_refusal(result) then stop
  else if stop + 81 > 512 then stop
  else let
    val with_space = _put_literal(out, stop, " ")
    val detail_stop = _detail_put(out, with_space)
  in if detail_stop > with_space then detail_stop else stop end

(* The screen's status line: syncing, or how the last sync ended and
   when *)
fn _status_text {l:agz} (out: !$A.arr(byte, l, 512)): [stop:nat | stop <= 512] int stop = let
  val result = !_last_result
in
  if ~_store_on() then
    (if _said_when_off(result) then _result_text(out, 0, result, 0) else _put_literal(out, 0, "Sync is off."))
  else case+ result of
    | Syncing() => _put_literal(out, 0, "Syncing...")
    | NotSyncedYet() => _put_literal(out, 0, "Not synced yet.")
    | NoAddress() => _result_text(out, 0, result, 0)
    | Synced() => let
      val after = _put_literal(out, 0, "Last synced on ")
      val after = _when_text(out, after, !_last_minutes)
    in _put_literal(out, after, ".") end
    | Unreachable() => _tried(out, result)
    | Blocked() => _tried(out, result)
    | WrongCredentials() => _tried(out, result)
    | FolderNotFound() => _tried(out, result)
    | KeptChanging() => _tried(out, result)
    | ServerError() => _tried(out, result)
    | TooLarge() => _tried(out, result)
    | Damaged() => _tried(out, result)
    | NoMemory() => _tried(out, result)
    | SignInAgain() => _tried(out, result)
    | NoGoogleAccount() => _tried(out, result)
    | NotSetUp() => _tried(out, result)
    | GoogleRefused() => _tried(out, result)
    | SignInCanceled() => _tried(out, result)
    | GoogleSignInFailed() => _tried(out, result)
    | GoogleAccountNeeded() => _tried(out, result)
    | GoogleUnreachable() => _tried(out, result)
    | GoogleConsentShowing() => _tried(out, result)
    | GoogleUnexpected() => _tried(out, result)
    | GoogleNoAnswer() => _tried(out, result)
    | GoogleAsking() => _result_text(out, 0, result, 0)
    | DropboxSignInAgain() => _tried(out, result)
    | DropboxNotSetUp() => _tried(out, result)
    | DropboxSignInRefused() => _tried(out, result)
    | DropboxSignInCanceled() => _tried(out, result)
    | FastmailRefused() => _tried(out, result)
end

(* How the last sync failed, in a few words (at most 40 bytes), at
   out[position] *)
fn _result_short {l:agz}{position:nat | position + 64 <= 512} (out: !$A.arr(byte, l, 512), position: int position, result: sync_result, status: Int)
  : [stop:nat | stop <= position + 64] int stop =
  case+ result of
  | Unreachable() => _put_literal(out, position, "Can't reach the server")
  | Blocked() => _put_literal(out, position, "Can't reach the server")
  | WrongCredentials() => _put_literal(out, position, "Wrong user name or password")
  | FolderNotFound() => _put_literal(out, position, "Folder not found")
  | KeptChanging() => _put_literal(out, position, "The file kept changing")
  | TooLarge() => _put_literal(out, position, "The sync file is over 16 MB")
  | Damaged() => _put_literal(out, position, "The sync file can't be read")
  | NoMemory() => _put_literal(out, position, "Not enough memory")
  | NoAddress() => _put_literal(out, position, "No folder address")
  | SignInAgain() => _put_literal(out, position, "paused, tap Sync now")
  | GoogleRefused() => _put_literal(out, position, "Google sign-in failed")
  | GoogleSignInFailed() => _put_literal(out, position, "Google sign-in failed")
  | GoogleAccountNeeded() => _put_literal(out, position, "Sign in to Google on this device")
  | GoogleUnreachable() => _put_literal(out, position, "Can't reach Google")
  | GoogleConsentShowing() => _put_literal(out, position, "Google's consent screen is open")
  | GoogleUnexpected() => _put_literal(out, position, "Google sign-in failed")
  | GoogleNoAnswer() => _put_literal(out, position, "Google didn't answer")
  | GoogleAsking() => _put_literal(out, position, "waiting for Google")
  | NoGoogleAccount() => _put_literal(out, position, "No Google account")
  | NotSetUp() => _put_literal(out, position, "Not set up in this build")
  | SignInCanceled() => _put_literal(out, position, "Sign-in canceled")
  | DropboxSignInAgain() => _put_literal(out, position, "sign in to Dropbox again")
  | DropboxNotSetUp() => _put_literal(out, position, "Not set up in this build")
  | DropboxSignInRefused() => _put_literal(out, position, "Dropbox refused")
  | DropboxSignInCanceled() => _put_literal(out, position, "Sign-in canceled")
  | FastmailRefused() => _put_literal(out, position, "Wrong Fastmail address or app password")
  | ServerError() => let
      val after = _put_literal(out, position, "Server error (")
      val after = $S.int_to_str(out, after, 512, status)
    in _put_literal(out, after, ")") end
  (* not failures: _summary_text says them *)
  | NotSyncedYet() => _put_literal(out, position, "not synced yet")
  | Synced() => _put_literal(out, position, "synced")
  | Syncing() => _put_literal(out, position, "syncing...")

(* The Settings screen's Sync row's state: "Off", the store and how long
   ago it last synced ("WebDAV \xC2\xB7 synced 2 min ago"), or how the
   last sync failed, in short *)
fn _summary_text {l:agz} (out: !$A.arr(byte, l, 512)): [stop:nat | stop <= 512] int stop = let
  val result = !_last_result
in
  if ~_store_on() then
    (if _google_refusal(result) then _result_short(out, _put_literal(out, 0, "Off \xC2\xB7 "), result, 0)
    else _put_literal(out, 0, "Off"))
  else let
    val after = (if _store_kind_is_dropbox() then _put_literal(out, 0, "Dropbox \xC2\xB7 ")
      else if _store_kind_is_fastmail() then _put_literal(out, 0, "Fastmail \xC2\xB7 ")
      else if ~_is_android() then _put_literal(out, 0, "WebDAV \xC2\xB7 ")
      else if $BAPP.is_native_platform() then _put_literal(out, 0, "Android \xC2\xB7 ")
      else _put_literal(out, 0, "Google Drive \xC2\xB7 ")): [after:nat | after <= 20] int after
  in
    case+ result of
    | Syncing() => _put_literal(out, after, "syncing...")
    | NotSyncedYet() => _put_literal(out, after, "not synced yet")
    | Synced() => let
      val elapsed = $TM.epoch_minutes() - !_last_minutes
    in
      if elapsed < 1 then _put_literal(out, after, "synced just now")
      else if elapsed < 60 then let
        val after = _put_literal(out, after, "synced ")
        val after = $S.int_to_str(out, after, 512, elapsed)
      in _put_literal(out, after, " min ago") end
      else if elapsed < 1440 then let
        val after = _put_literal(out, after, "synced ")
        val after = $S.int_to_str(out, after, 512, elapsed / 60)
      in _put_literal(out, after, " h ago") end
      else let
        val after = _put_literal(out, after, "synced on ")
      in _when_text(out, after, !_last_minutes) end
    end
    | Unreachable() => _result_short(out, 0, result, !_last_status)
    | Blocked() => _result_short(out, 0, result, !_last_status)
    | WrongCredentials() => _result_short(out, 0, result, !_last_status)
    | FolderNotFound() => _result_short(out, 0, result, !_last_status)
    | KeptChanging() => _result_short(out, 0, result, !_last_status)
    | ServerError() => _result_short(out, 0, result, !_last_status)
    | TooLarge() => _result_short(out, 0, result, !_last_status)
    | Damaged() => _result_short(out, 0, result, !_last_status)
    | NoMemory() => _result_short(out, 0, result, !_last_status)
    | NoAddress() => _result_short(out, 0, result, !_last_status)
    (* paused, not failed: said after the store's name *)
    | SignInAgain() => _result_short(out, after, result, !_last_status)
    | NoGoogleAccount() => _result_short(out, 0, result, !_last_status)
    | NotSetUp() => _result_short(out, 0, result, !_last_status)
    | GoogleRefused() => _result_short(out, 0, result, !_last_status)
    | SignInCanceled() => _result_short(out, 0, result, !_last_status)
    | GoogleSignInFailed() => _result_short(out, 0, result, !_last_status)
    | GoogleAccountNeeded() => _result_short(out, 0, result, !_last_status)
    | GoogleUnreachable() => _result_short(out, 0, result, !_last_status)
    | GoogleConsentShowing() => _result_short(out, 0, result, !_last_status)
    | GoogleUnexpected() => _result_short(out, 0, result, !_last_status)
    | GoogleNoAnswer() => _result_short(out, 0, result, !_last_status)
    | GoogleAsking() => _result_short(out, after, result, !_last_status)
    | DropboxSignInAgain() => _result_short(out, 0, result, !_last_status)
    | DropboxNotSetUp() => _result_short(out, 0, result, !_last_status)
    | DropboxSignInRefused() => _result_short(out, 0, result, !_last_status)
    | DropboxSignInCanceled() => _result_short(out, 0, result, !_last_status)
    | FastmailRefused() => _result_short(out, 0, result, !_last_status)
  end
end

(* Counts sign-ins: a poll an earlier one started (or one Turn off
   ended) stops *)
val _sign_in_generation = ref<int>(0)

(* A service the Sync screen lists (#331): Google Drive (in the app,
   the Google account on the phone: Use Android), Dropbox, Fastmail,
   Nextcloud and any WebDAV folder. Each is a row of the screen, and
   each row opens the service's own sign-in step *)
#pub datatype sync_service =
  | ServiceGoogle
  | ServiceDropbox
  | ServiceFastmail
  | ServiceNextcloud
  | ServiceWebDav

(* A service's row's button, and its state beside it *)
fn _row_id (service: sync_service): [id_len:pos | id_len < 256] string id_len =
  case+ service of
  | ServiceGoogle() => "sync-row-google"
  | ServiceDropbox() => "sync-row-dropbox"
  | ServiceFastmail() => "sync-row-fastmail"
  | ServiceNextcloud() => "sync-row-nextcloud"
  | ServiceWebDav() => "sync-row-webdav"

fn _row_state_id (service: sync_service): [id_len:pos | id_len < 256] string id_len =
  case+ service of
  | ServiceGoogle() => "sync-google-state"
  | ServiceDropbox() => "sync-dropbox-state"
  | ServiceFastmail() => "sync-fastmail-state"
  | ServiceNextcloud() => "sync-nextcloud-state"
  | ServiceWebDav() => "sync-webdav-state"

(* A service's part of the sign-in step: what it does and asks for,
   and its own button *)
fn _step_part_id (service: sync_service): [id_len:pos | id_len < 256] string id_len =
  case+ service of
  | ServiceGoogle() => "sync-step-google"
  | ServiceDropbox() => "sync-step-dropbox"
  | ServiceFastmail() => "fastmail-form"
  | ServiceNextcloud() => "nextcloud-box"
  | ServiceWebDav() => "sync-step-webdav"

(* A service's name, as its row and its step's title say it *)
fn service_title (service: sync_service): [name_len:pos | name_len < 64] string name_len =
  case+ service of
  | ServiceGoogle() => "Google Drive"
  | ServiceDropbox() => "Dropbox"
  | ServiceFastmail() => "Fastmail"
  | ServiceNextcloud() => "Nextcloud"
  | ServiceWebDav() => "WebDAV"

(* The one verb of a service's step button, whichever the service: the
   name says where to (quire#361; the app's Google account is Google
   Drive's sign-in too) *)
fn sign_in_label (service: sync_service): [label_len:pos | label_len < 64] string label_len =
  case+ service of
  | ServiceGoogle() => "Sign in to Google Drive"
  | ServiceDropbox() => "Sign in to Dropbox"
  | ServiceFastmail() => "Sign in to Fastmail"
  | ServiceNextcloud() => "Sign in to Nextcloud"
  | ServiceWebDav() => "Sign in to WebDAV"

(* Whether a folder's URL is a Nextcloud user's files folder, as its
   sign-in makes it (nextcloud_folder: <server>/remote.php/dav/files/<id>) *)
fun _holds {l:agz}{n:nat}{text_len:nat | text_len <= n}{part_len:pos}{at:nat | at <= text_len} .<text_len - at>.
  (text: !$A.arr(byte, l, n), text_len: int text_len, part: string part_len, part_len: int part_len, at: int at): bool = let
  fun same {j:nat | j <= part_len} .<part_len - j>. (text: !$A.arr(byte, l, n), j: int j): bool =
    if j >= part_len then true
    else if at + j >= text_len then false
    else if byte2int0($A.get<byte>(text, at + j)) <> char2int0(string_get_at(part, j)) then false
    else same(text, j + 1)
in
  if at + part_len > text_len then false
  else if same(text, 0) then true
  else _holds(text, text_len, part, part_len, at + 1)
end

(* The service the store chosen is, if one is: a WebDAV folder a
   Nextcloud sign-in made is Nextcloud's *)
fn _store_is (service: sync_service): bool = let
  val held = _store_swap(_store, NoStore())
  val nextcloud = (case+ held of
    | WebDav(url, url_len, _, _, _, _) => _holds(url, url_len, "/remote.php/dav/files/", 22, 0)
    | Android(_, _) => false | Dropbox(_, _) => false | Fastmail(_, _, _, _) => false | NoStore() => false): bool
  val webdav = (case+ held of
    | WebDav(_, _, _, _, _, _) => true
    | Android(_, _) => false | Dropbox(_, _) => false | Fastmail(_, _, _, _) => false | NoStore() => false): bool
  val () = _store_free(_store_swap(_store, held))
in
  case+ service of
  | ServiceGoogle() => _is_android()
  | ServiceDropbox() => _store_kind_is_dropbox()
  | ServiceFastmail() => _store_kind_is_fastmail()
  | ServiceNextcloud() => nextcloud
  | ServiceWebDav() => if webdav then ~nextcloud else false
end

(* A row's state, in a word or two (Android's settings show a setting's
   state, not a description of it): the store's own row says whether it
   syncs, is paused for a sign-in, or does not sync; the others say
   nothing *)
fn _row_show (service: sync_service): void =
  if ~_store_is(service) then ui_show(_row_state_id(service), false)
  else let
    val () = (case+ !_last_result of
      | Synced() => ui_text(_row_state_id(service), "Connected")
      | Syncing() => ui_text(_row_state_id(service), "Connected")
      | NotSyncedYet() => ui_text(_row_state_id(service), "Connected")
      | SignInAgain() => ui_text(_row_state_id(service), "Paused")
      | Unreachable() => ui_text(_row_state_id(service), "Not syncing")
      | WrongCredentials() => ui_text(_row_state_id(service), "Not syncing")
      | FolderNotFound() => ui_text(_row_state_id(service), "Not syncing")
      | KeptChanging() => ui_text(_row_state_id(service), "Not syncing")
      | ServerError() => ui_text(_row_state_id(service), "Not syncing")
      | TooLarge() => ui_text(_row_state_id(service), "Not syncing")
      | Damaged() => ui_text(_row_state_id(service), "Not syncing")
      | NoMemory() => ui_text(_row_state_id(service), "Not syncing")
      | Blocked() => ui_text(_row_state_id(service), "Not syncing")
      | NoAddress() => ui_text(_row_state_id(service), "Not syncing")
      | NoGoogleAccount() => ui_text(_row_state_id(service), "Not syncing")
      | NotSetUp() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleRefused() => ui_text(_row_state_id(service), "Not syncing")
      | SignInCanceled() => ui_text(_row_state_id(service), "Not syncing")
      | DropboxSignInAgain() => ui_text(_row_state_id(service), "Not syncing")
      | DropboxNotSetUp() => ui_text(_row_state_id(service), "Not syncing")
      | DropboxSignInRefused() => ui_text(_row_state_id(service), "Not syncing")
      | DropboxSignInCanceled() => ui_text(_row_state_id(service), "Not syncing")
      | FastmailRefused() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleSignInFailed() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleAccountNeeded() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleUnreachable() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleConsentShowing() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleUnexpected() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleNoAnswer() => ui_text(_row_state_id(service), "Not syncing")
      | GoogleAsking() => ui_text(_row_state_id(service), "Connected"))
  in ui_show(_row_state_id(service), true) end

(* The status card's head: where sync is kept, when it is on *)
fn _where_show (): void =
  if ~_store_on() then ui_show("sync-where", false)
  else let
    val () = (if _store_is(ServiceNextcloud()) then ui_text("sync-where", "Nextcloud")
      else if _store_kind_is_dropbox() then ui_text("sync-where", "Dropbox")
      else if _store_kind_is_fastmail() then ui_text("sync-where", "Fastmail")
      else if ~_is_android() then ui_text("sync-where", "WebDAV")
      else ui_text("sync-where", "Google Drive"))
  in ui_show("sync-where", true) end

(* The screen's rows and its status card's head, as the store and the
   last sync are *)
fn _rows_show (): void = let
  val () = _row_show(ServiceGoogle())
  val () = _row_show(ServiceDropbox())
  val () = _row_show(ServiceFastmail())
  val () = _row_show(ServiceNextcloud())
  val () = _row_show(ServiceWebDav())
in _where_show() end

(* Whether Google's consent screen is awaited (see consent_wait) *)
val _consent_open = ref<bool>(false)

(* Sync now and Turn off: in the status card, while a store is chosen;
   while Google's consent screen is awaited, Stop waiting in their place
   (#340) *)
fn _actions_show (on: bool): void = let
  val asking = !_consent_open
  val () = ui_show("sync-off", if asking then false else on)
  val () = ui_show("sync-now", if asking then false else on)
in ui_show("sync-stop", asking) end

(* The Settings screen's Sync row's state, as it is now *)
#pub fn sync_summary_show (): void
implement sync_summary_show () = let
  val summary = $A.alloc<byte>(512)
  val summary_stop = _summary_text(summary)
in ui_text_buf("settings-sync-state", summary, summary_stop) end

(* The sync screen's status line and the Settings screen's Sync row *)
fn _status_show (): void = let
  val out = $A.alloc<byte>(512)
  val stop = _status_text(out)
  val stop = _with_detail(out, stop, !_last_result)
  val () = ui_text_buf("sync-status", out, stop)
  val () = _rows_show()
in sync_summary_show() end

(* The error banner says how a sync or sign-in the reader started
   ended: the reader may be far from the screen's status line, or on
   another screen (#334). A refusal Google gave is said with its
   details, for Copy details *)
fn _banner_say (result: sync_result): void = let
  val out = $A.alloc<byte>(512)
  val stop = _result_text(out, 0, result, !_last_status)
  val stop = _with_detail(out, stop, result)
in
  if ~_google_refusal(result) then notice_error_buf(out, stop)
  else case+ _refusal_swap(NoRefusalKept()) of
    | ~NoRefusalKept() => notice_error_buf(out, stop)
    | ~RefusalKept(status, call, answer) => let
        val () = notice_failure(out, stop, "signing in to Google", call, $GA.google_status_name(status), answer)
      in _refusal_free(_refusal_swap(RefusalKept(status, call, NoAnswer()))) end
end

val _reader_waits = ref<bool>(false)

fn _reader_told (result: sync_result): void =
  if ~(!_reader_waits) then ()
  else let
    val () = !_reader_waits := false
  in if _told_in_banner(result) then _banner_say(result) else () end

(* ============================================================
   The request: GET or PUT of <folder>/quire-sync.json
   ============================================================ *)

(* The digit of value (6 bits) in base64 *)
fn _base64_digit {value:nat | value < 64} (value: int value): [digit:nat | digit < 256] int digit =
  if value < 26 then 65 + value
  else if value < 52 then 71 + value
  else if value < 62 then value - 4
  else if value = 62 then 43
  else 47

(* source[3 * group, len) in base64 at out[6 + 4 * group): where it ends *)
fun _base64 {source_loc,out_loc:agz}{len:nat | len <= 513}{group:nat | 3 * group <= len + 2} .<len + 3 - 3 * group>.
  (source: !$A.arr(byte, source_loc, 513), len: int len, group: int group, out: !$A.arr(byte, out_loc, 700))
  : [stop:nat | stop <= 700] int stop =
  if 3 * group >= len then 6 + 4 * group
  else let
    val first = $AR.low_byte(byte2int0($A.get<byte>(source, 3 * group)))
    val second = (if 3 * group + 1 < len then $AR.low_byte(byte2int0($A.get<byte>(source, 3 * group + 1))) else 0): [v:nat | v < 256] int v
    val third = (if 3 * group + 2 < len then $AR.low_byte(byte2int0($A.get<byte>(source, 3 * group + 2))) else 0): [v:nat | v < 256] int v
    val at = 6 + 4 * group
    val () = $A.write_byte(out, at, _base64_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(first, 2)), 63)))
    val () = $A.write_byte(out, at + 1, _base64_digit($AR.band_g1($AR.low_byte($AR.bor_int_int($AR.bsl_int_int($AR.band_int_int(first, 3), 4), $AR.bsr_int_int(second, 4))), 63)))
    val () = (if 3 * group + 1 < len then
      $A.write_byte(out, at + 2, _base64_digit($AR.band_g1($AR.low_byte($AR.bor_int_int($AR.bsl_int_int($AR.band_int_int(second, 15), 2), $AR.bsr_int_int(third, 6))), 63)))
      else $A.write_byte(out, at + 2, 61))
    val () = (if 3 * group + 2 < len then $A.write_byte(out, at + 3, _base64_digit($AR.band_g1(third, 63)))
      else $A.write_byte(out, at + 3, 61))
  in _base64(source, len, group + 1, out) end

(* "Basic " and base64(user:password) in out: its length *)
fn _authorization {user_loc,password_loc,out_loc:agz}{user_len:nat | user_len <= USER_MAX}{password_len:nat | password_len <= PASSWORD_MAX}
  (user: !$A.arr(byte, user_loc, USER_MAX), user_len: int user_len, password: !$A.arr(byte, password_loc, PASSWORD_MAX), password_len: int password_len,
   out: !$A.arr(byte, out_loc, 700)): [stop:nat | stop <= 700] int stop = let
  val pair = $A.alloc<byte>(513)
  fun copy {source_loc,pair_loc:agz}{source_size:nat}{count:nat | count <= source_size}{at:nat | at + count <= 513}{j:nat | j <= count} .<count - j>.
    (source: !$A.arr(byte, source_loc, source_size), count: int count, pair: !$A.arr(byte, pair_loc, 513), at: int at, j: int j): void =
    if j >= count then ()
    else let val () = $A.set<byte>(pair, at + j, $A.get<byte>(source, j)) in copy(source, count, pair, at, j + 1) end
  val () = copy(user, user_len, pair, 0, 0)
  val () = $A.write_byte(pair, user_len, 58)
  val () = copy(password, password_len, pair, user_len + 1, 0)
  val () = $A.write_text(out, 0, $A.text_lit("Basic "), 6)
  val stop = _base64(pair, user_len + 1 + password_len, 0, out)
  val () = $A.free<byte>(pair)
in stop end

(* The folder's URL without the slashes it ends with *)
fun _trimmed {l:agz}{url_len:nat | url_len <= URL_MAX} .<url_len>. (url: !$A.arr(byte, l, URL_MAX), url_len: int url_len): [kept:nat | kept <= url_len] int kept =
  if url_len <= 0 then 0
  else if byte2int0($A.get<byte>(url, url_len - 1)) = 47 then _trimmed(url, url_len - 1)
  else url_len

(* <folder>/quire-sync.json in out (the folder's URL and the file's name
   joined by exactly one slash): its length *)
fn _file_url {url_loc,out_loc:agz}{url_len:pos | url_len <= URL_MAX}
  (url: !$A.arr(byte, url_loc, URL_MAX), url_len: int url_len, out: !$A.arr(byte, out_loc, 1041)): [stop:pos | stop <= 1041] int stop = let
  val kept = _trimmed(url, url_len)
  fun copy {source_loc,copy_loc:agz}{count:nat | count <= URL_MAX}{j:nat | j <= count} .<count - j>.
    (source: !$A.arr(byte, source_loc, URL_MAX), count: int count, out: !$A.arr(byte, copy_loc, 1041), j: int j): void =
    if j >= count then ()
    else let val () = $A.set<byte>(out, j, $A.get<byte>(source, j)) in copy(source, count, out, j + 1) end
  val () = copy(url, kept, out, 0)
in _put_literal(out, kept, "/quire-sync.json") end

(* <folder>/ in out: its length *)
fn _folder_url {url_loc,out_loc:agz}{url_len:pos | url_len <= URL_MAX}
  (url: !$A.arr(byte, url_loc, URL_MAX), url_len: int url_len, out: !$A.arr(byte, out_loc, 1041)): [stop:pos | stop <= 1041] int stop = let
  val kept = _trimmed(url, url_len)
  fun copy {source_loc,copy_loc:agz}{count:nat | count <= URL_MAX}{j:nat | j <= count} .<count - j>.
    (source: !$A.arr(byte, source_loc, URL_MAX), count: int count, out: !$A.arr(byte, copy_loc, 1041), j: int j): void =
    if j >= count then ()
    else let val () = $A.set<byte>(out, j, $A.get<byte>(source, j)) in copy(source, count, out, j + 1) end
  val () = copy(url, kept, out, 0)
in _put_literal(out, kept, "/") end

(* What a request is for: the sync file, or the folder it is kept in
   (made with MKCOL where it is missing) *)
datatype target = TheFile | TheFolder

(* Fastmail's file, or its folder: quire, in the account's own files *)
fn _fastmail_url {l:agz} (out: !$A.arr(byte, l, 1041), aim: target): [stop:pos | stop <= 1041] int stop =
  case+ aim of
  | TheFile() => _put_literal(out, 0, "https://myfiles.fastmail.com/quire/quire-sync.json")
  | TheFolder() => _put_literal(out, 0, "https://myfiles.fastmail.com/quire/")

(* The WebDAV store's file's (or folder's) URL in url and the
   Authorization header in authorization: their lengths *)
fn _request_parts {url_loc,authorization_loc:agz}
  (url: !$A.arr(byte, url_loc, 1041), authorization: !$A.arr(byte, authorization_loc, 700), aim: target)
  : [url_len:pos | url_len <= 1041][authorization_len:nat | authorization_len <= 700] @(int url_len, int authorization_len) =
  case+ _store_swap(_store, NoStore()) of
  | ~Fastmail(user, user_len, password, password_len) => let
      val url_len = _fastmail_url(url, aim)
      val authorization_len = _authorization(user, user_len, password, password_len, authorization)
      val () = _store_free(_store_swap(_store, Fastmail(user, user_len, password, password_len)))
    in @(url_len, authorization_len) end
  | ~NoStore() => let val _ = _put_literal(url, 0, "/") in @(1, 0) end
  | ~Android(account, account_len) => let
      val _ = _put_literal(url, 0, "/")
      val () = _store_free(_store_swap(_store, Android(account, account_len)))
    in @(1, 0) end
  | ~Dropbox(refresh, refresh_len) => let
      val _ = _put_literal(url, 0, "/")
      val () = _store_free(_store_swap(_store, Dropbox(refresh, refresh_len)))
    in @(1, 0) end
  | ~WebDav(folder, folder_len, user, user_len, password, password_len) => let
      val url_len = (case+ aim of TheFile() => _file_url(folder, folder_len, url) | TheFolder() => _folder_url(folder, folder_len, url)): [stop:pos | stop <= 1041] int stop
      val authorization_len = _authorization(user, user_len, password, password_len, authorization)
      val () = _store_free(_store_swap(_store, WebDav(folder, folder_len, user, user_len, password, password_len)))
    in @(url_len, authorization_len) end

(* The WebDAV store's file's URL in out: its length, 0 for none *)
fn _store_url {l:agz} (out: !$A.arr(byte, l, 1041)): [length:nat | length <= 1041] int length =
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => 0
  | ~Fastmail(user, user_len, password, password_len) => let
      val length = _fastmail_url(out, TheFile())
      val () = _store_free(_store_swap(_store, Fastmail(user, user_len, password, password_len)))
    in length end
  | ~Android(account, account_len) => let
      val () = _store_free(_store_swap(_store, Android(account, account_len)))
    in 0 end
  | ~Dropbox(refresh, refresh_len) => let
      val () = _store_free(_store_swap(_store, Dropbox(refresh, refresh_len)))
    in 0 end
  | ~WebDav(url, url_len, user, user_len, password, password_len) => let
      val length = _file_url(url, url_len, out)
      val () = _store_free(_store_swap(_store, WebDav(url, url_len, user, user_len, password, password_len)))
    in length end

(* The ETag of the file read, sent back as If-Match with its write *)
datavtype etag_cell = | {l:agz}{etag_len:nat | etag_len <= ETAG_MAX} EtagCell of ($A.arr(byte, l, ETAG_MAX), int etag_len)
val _etag = ref<etag_cell>(EtagCell($A.alloc<byte>(ETAG_MAX), 0))

fn _etag_swap (held: etag_cell): etag_cell = let
  var previous: etag_cell = held
  val () = ref_exch_elt<etag_cell>(_etag, previous)
in previous end

fn _etag_set {l:agz}{etag_len:nat | etag_len <= ETAG_MAX} (etag: $A.arr(byte, l, ETAG_MAX), etag_len: int etag_len): void = let
  val+ ~EtagCell(old, _) = _etag_swap(EtagCell(etag, etag_len))
in $A.free<byte>(old) end

(* Sends method for the file (or its folder, as aim says), with
   body[0, body_len) (none when 0), and If-Match the ETag read when
   with_match; the promise resolves as fetch's does *)
fn _send {method_len:pos | method_len <= 16}{body_loc:agz}{body_size:nat}{body_len:nat | body_len <= body_size}
  (method: string method_len, body: !$A.borrow(byte, body_loc, body_size), body_len: int body_len, with_match: bool, aim: target): $P.promise($FE.fetched, $P.Chained) = let
  val method_len = g1u2i(string1_length(method))
  val method_bytes = $A.alloc<byte>(method_len)
  val () = $A.write_text(method_bytes, 0, $A.text_lit(method), method_len)
  val url = $A.alloc<byte>(1041)
  val authorization = $A.alloc<byte>(700)
  val @(url_len, authorization_len) = _request_parts(url, authorization, aim)
  val+ ~EtagCell(etag, etag_len) = _etag_swap(EtagCell($A.alloc<byte>(ETAG_MAX), 0))
  val match_len = (if with_match then etag_len else 0): [match_len:nat | match_len <= ETAG_MAX] int match_len
  val @(method_frozen, method_borrow) = $A.freeze<byte>(method_bytes)
  val @(url_frozen, url_borrow) = $A.freeze<byte>(url)
  val @(url_used, url_rest) = $A.borrow_split<byte>(url_frozen, url_borrow, url_len)
  val @(authorization_frozen, authorization_borrow) = $A.freeze<byte>(authorization)
  val @(etag_frozen, etag_borrow) = $A.freeze<byte>(etag)
  val pending = $FE.fetch_send(method_borrow, method_len, url_used, url_len, authorization_borrow, authorization_len,
    etag_borrow, match_len, body, body_len)
  val () = $A.drop<byte>(etag_frozen, etag_borrow)
  val etag = $A.thaw<byte>(etag_frozen)
  val () = _etag_set(etag, etag_len)
  val () = release_bytes(authorization_frozen, authorization_borrow)
  val url_borrow = $A.borrow_join<byte>(url_frozen, url_used, url_rest)
  val () = release_bytes(url_frozen, url_borrow)
in let val () = release_bytes(method_frozen, method_borrow) in pending end end

(* Whether the folder is on another origin than the app's: then a fetch
   that fails may be the server's refusal (CORS), which a browser does
   not tell from being offline *)
fn _origin_end {l:agz}{size,n:nat | n <= size} (url: !$A.arr(byte, l, size), n: int n): [stop:nat | stop <= n] int stop = let
  fun find {l:agz}{size,n:nat | n <= size}{i:nat | i <= n} .<n - i>. (url: !$A.arr(byte, l, size), n: int n, i: int i, slashes: int): [stop:nat | stop <= n] int stop =
    if i >= n then n
    else if byte2int0($A.get<byte>(url, i)) = 47 then (if slashes >= 2 then i else find(url, n, i + 1, slashes + 1))
    else find(url, n, i + 1, slashes)
in find(url, n, 0, 0) end

fn _shorter {first,second:nat} (first: int first, second: int second): [shorter:nat | shorter <= first; shorter <= second] int shorter =
  if first <= second then first else second

fn _cross_origin (): bool = let
  val page = $A.alloc<byte>(2048)
  val page_len = $NAV.get_url(page, 2048)
  val page_origin = _origin_end(page, page_len)
  val folder = $A.alloc<byte>(1041)
  val folder_len = _store_url(folder)
  val folder_origin = _origin_end(folder, folder_len)
  fun same {page_loc,folder_loc:agz}{page_size,folder_size:nat}{count:nat | count <= page_size; count <= folder_size}{j:nat | j <= count} .<count - j>.
    (page: !$A.arr(byte, page_loc, page_size), folder: !$A.arr(byte, folder_loc, folder_size), count: int count, j: int j): bool =
    if j >= count then true
    else if byte2int0($A.get<byte>(page, j)) <> byte2int0($A.get<byte>(folder, j)) then false
    else same(page, folder, count, j + 1)
  val shorter = _shorter(page_origin, folder_origin)
  val same_start = same(page, folder, shorter, 0)
  val cross = (if page_origin <> folder_origin then true else ~same_start): bool
  val () = $A.free<byte>(page)
  val () = $A.free<byte>(folder)
in cross end

(* ============================================================
   The store's operations: read and write the file
   ============================================================ *)

(* What a read gives: the file (its bytes in a piece, its version kept
   for the write), none yet, or how it failed (and the server's status) *)
datavtype read_answer =
  | {owner,l:agz}{n:pos | n <= 268435456} ReadFile of (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int n)
  | ReadNothing of ()
  | ReadFailed of (sync_result, Int)

(* What a write gives: written, a conflict (another device wrote the
   file since its version was read), or how it failed *)
datavtype write_answer = Written of () | WriteConflict of () | WriteFailed of (sync_result, Int)

(* An answer nobody took (its promise let go), freed *)
implement $P.dispose<read_answer>(answer) =
  case+ answer of
  | ~ReadFile(owner, file, _) => piece_free(owner, file)
  | ~ReadNothing() => ()
  | ~ReadFailed(_, _) => ()

(* a Dropbox read, made in this module when no token is held *)
implement $P.dispose<drive_got>(got) =
  case+ got of
  | ~DriveGot(owner, file, _) => piece_free(owner, file)
  | ~DriveNothing() => ()
  | ~DriveFailed(_) => ()

implement $P.dispose<write_answer>(answer) =
  case+ answer of
  | ~Written() => ()
  | ~WriteConflict() => ()
  | ~WriteFailed(_, _) => ()

(* An HTTP status, read once: success (2xx); 401 or 403, the credentials
   refused; 404, not found; 409, the folder missing (a PUT into one that
   is not there); 412, the version changed; or another *)
datatype http_answer = HttpSuccess | HttpRefused | HttpNotFound | HttpNoFolder | HttpChanged | HttpOther

fn _http_answer (status: Int): http_answer =
  if status >= 200 then (if status < 300 then HttpSuccess()
    else if status = 401 then HttpRefused() else if status = 403 then HttpRefused()
    else if status = 404 then HttpNotFound() else if status = 409 then HttpNoFolder()
    else if status = 412 then HttpChanged() else HttpOther())
  else HttpOther()

(* What a status a store refused with says: the credentials (as the
   store says it, refused), the place the file is kept, or the server *)
fn _failure_kind (answer: http_answer, refused: sync_result): sync_result =
  case+ answer of
  | HttpRefused() => refused
  | HttpNotFound() => FolderNotFound()
  | HttpNoFolder() => FolderNotFound()
  | HttpSuccess() => ServerError()
  | HttpChanged() => ServerError()
  | HttpOther() => ServerError()

(* What a request came to, with the response's ETag written to etag:
   its status, the tag's length (0 when it has none) and its body; none
   when no response came *)
fn _tagged {l:agz}{etag_size:pos}
  (got: $FE.fetched, etag: !$A.arr(byte, l, etag_size), etag_size: int etag_size)
  : $R.option(@([s:int] int s, [k:nat | k <= etag_size] int k, [n:nat] $BD.dblob(n))) =
  case+ got of
  | ~$FE.NoResponse() => $R.none()
  | ~$FE.Responded(response) => let
      val name = $A.alloc<byte>(4)
      val () = $A.write_text(name, 0, $A.text_lit("ETag"), 4)
      val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
      val found = $FE.fetch_header(response, name_bytes, 4, etag, etag_size)
      val () = release_bytes(name_frozen, name_bytes)
      val etag_len = (case+ found of ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= etag_size] int k
      val status = $FE.fetch_status(response)
    in $R.some(@(status, etag_len, $FE.fetch_body(response))) end

(* A request that never reached the store: offline, or (another origin)
   refused by the browser *)
fn _unreached (): sync_result = if _cross_origin() then Blocked() else Unreachable()

(* A read the server refused with status *)
fn _read_failed {n:nat}{l:agz} (body: $BD.dblob(n), etag: $A.arr(byte, l, ETAG_MAX), status: Int, refused: sync_result): read_answer = let
  val () = $BD.blob_free(body)
  val () = $A.free<byte>(etag)
in ReadFailed(_failure_kind(_http_answer(status), refused), status) end

(* WebDAV: GET the file; its ETag is its version, and 404 is no file
   yet. Credentials refused are said as refused *)
fn _webdav_read (refused: sync_result): $P.promise(read_answer, $P.Chained) = let
  val empty = $A.alloc<byte>(1)
  val @(empty_frozen, empty_bytes) = $A.freeze<byte>(empty)
  val pending = _send("GET", empty_bytes, 0, false, TheFile())
  val () = release_bytes(empty_frozen, empty_bytes)
in
  $P.and_then<$FE.fetched><read_answer>(pending, llam(got) => let
    val etag = $A.alloc<byte>(ETAG_MAX)
    val answer = (case+ _tagged(got, etag, ETAG_MAX) of
      | ~$R.none() => let val () = $A.free<byte>(etag) in ReadFailed(_unreached(), 0) end
      | ~$R.some(@(status, etag_len, body)) =>
        (case+ _http_answer(status) of
        | HttpNotFound() => let
          val () = $BD.blob_free(body)
          (* no file yet: it is written without a version to match *)
          val () = _etag_set(etag, 0)
        in ReadNothing() end
        | HttpSuccess() => let
          val size = $BD.blob_len(body)
          val () = _etag_set(etag, etag_len)
        in
          if size > SYNC_MAX_BYTES then let val () = $BD.blob_free(body) in ReadFailed(TooLarge(), 0) end
          else if size <= 0 then let val () = $BD.blob_free(body) in ReadNothing() end
          else (case+ piece_new(size) of
            | ~NoPiece() => let val () = $BD.blob_free(body) in ReadFailed(NoMemory(), 0) end
            | ~Piece(owner, file) => let
                val () = $BD.blob_read(body, 0, file, size)
                val () = $BD.blob_free(body)
              in ReadFile(owner, file, size) end)
        end
        | HttpRefused() => _read_failed(body, etag, status, refused)
        | HttpNoFolder() => _read_failed(body, etag, status, refused)
        | HttpChanged() => _read_failed(body, etag, status, refused)
        | HttpOther() => _read_failed(body, etag, status, refused))): read_answer
  in $P.ret<read_answer>(answer) end)
end

(* WebDAV: PUT the file, If-Match the ETag read (unconditional when
   there was none); 412 is a conflict. Credentials refused are said as
   refused *)
fn _webdav_write {body_loc:agz}{body_size:pos}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size, refused: sync_result): $P.promise(write_answer, $P.Chained) = let
  val pending = _send("PUT", body, body_size, true, TheFile())
in
  $P.and_then<$FE.fetched><write_answer>(pending, llam(got) => let
    val etag = $A.alloc<byte>(ETAG_MAX)
    val answer = (case+ _tagged(got, etag, ETAG_MAX) of
      | ~$R.none() => let val () = $A.free<byte>(etag) in WriteFailed(_unreached(), 0) end
      | ~$R.some(@(status, _, reply)) => let
          val () = $A.free<byte>(etag)
          val () = $BD.blob_free(reply)
        in
          case+ _http_answer(status) of
          | HttpChanged() => WriteConflict()
          | HttpSuccess() => Written()
          | HttpRefused() => WriteFailed(refused, status)
          | HttpNotFound() => WriteFailed(FolderNotFound(), status)
          | HttpNoFolder() => WriteFailed(FolderNotFound(), status)
          | HttpOther() => WriteFailed(ServerError(), status)
        end): write_answer
  in $P.ret<write_answer>(answer) end)
end

(* A response not looked at, let go *)
fn _fetched_free (got: $FE.fetched): void =
  case+ got of
  | ~$FE.NoResponse() => ()
  | ~$FE.Responded(response) => $BD.blob_free($FE.fetch_body(response))

(* Fastmail: the WebDAV read, its refusal said as Fastmail's; with no
   file yet, its folder is made (MKCOL), so the first write has one to
   go in. A folder already there answers 405 and is left as it is; one
   that could not be made makes the write fail, and says why *)
fn _fastmail_read (): $P.promise(read_answer, $P.Chained) =
  $P.and_then<read_answer><read_answer>(_webdav_read(FastmailRefused()), llam(answer) =>
    case+ answer of
    | ~ReadNothing() => let
        val empty = $A.alloc<byte>(1)
        val @(empty_frozen, empty_bytes) = $A.freeze<byte>(empty)
        val pending = _send("MKCOL", empty_bytes, 0, false, TheFolder())
        val () = release_bytes(empty_frozen, empty_bytes)
      in
        $P.and_then<$FE.fetched><read_answer>(pending, llam(got) => let
          val () = _fetched_free(got)
        in $P.ret<read_answer>(ReadNothing()) end)
      end
    | read => $P.ret<read_answer>(read))

(* The access token for the Android store's account (Dropbox's store
   holds its own here), kept on this device (_google_token_save) so the
   syncs the app makes by itself go on after it is opened again, and
   forgotten when Drive refuses it (it lasts about an hour). In the app
   (#321) a sync gets one with nothing shown (Play services'
   AuthorizationClient, bridge's google_authorization_for_scopes) once
   the reader has granted access, and Use Android and Sync now may show
   Google's consent (google_authorize_scopes); only a grant taken back
   pauses sync (SignInAgain) until Sync now. In a browser it is asked
   for only when the reader acts (Use Android, Sync now): Google
   Identity Services opens a window, which a page may do only at a tap,
   so with none sync is paused until Sync now (#304) *)
datavtype token_cell =
  | NoToken of ()
  | {l:agz}{token_len:pos | token_len <= TOKEN_MAX} Token of ($A.arr(byte, l, TOKEN_MAX), int token_len)

fn _token_free (cell: token_cell): void =
  case+ cell of
  | ~NoToken() => ()
  | ~Token(token, _) => $A.free<byte>(token)

val _token = ref<token_cell>(NoToken())

fn _token_swap (cell: token_cell): token_cell = let
  var previous: token_cell = cell
  val () = ref_exch_elt<token_cell>(_token, previous)
in previous end

(* Whether a token is held *)
fn _token_held (): bool = let
  val held = _token_swap(NoToken())
  val have = (case+ held of Token(_, _) => true | NoToken() => false): bool
  val () = _token_free(_token_swap(held))
in have end

(* The Google store's token kept: "QS1\n", then the token (a u16 length
   and its bytes), under "sync-google-token" *)
fn _google_token_save {l:agz}{token_len:pos | token_len <= TOKEN_MAX}
  (token: !$A.arr(byte, l, TOKEN_MAX), token_len: int token_len): void = let
  val record = $A.alloc<byte>(6 + TOKEN_MAX)
  val () = $A.write_text(record, 0, $A.text_lit("QS1"), 3)
  val () = $A.write_byte(record, 3, 10)
  val () = $A.write_u16le(record, 4, token_len)
  val () = _put_bytes(token, token_len, record, 6, 0)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(used, rest) = $A.borrow_split<byte>(record_frozen, record_bytes, 6 + token_len)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_google_token_key())
  val () = save_checked($IDB.idb_put(key_bytes, 17, used, 6 + token_len))
  val () = release_bytes(key_frozen, key_bytes)
  val record_bytes = $A.borrow_join<byte>(record_frozen, used, rest)
in release_bytes(record_frozen, record_bytes) end

(* The Google store's token forgotten, here and where it is kept *)
fn _google_token_forget (): void = let
  val () = _token_free(_token_swap(NoToken()))
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_google_token_key())
  val () = save_checked($IDB.idb_delete(key_bytes, 17))
in release_bytes(key_frozen, key_bytes) end

(* The Google store's token kept in record[0, n) (checked here, once) *)
fn _google_token_of_record {l:agz}{n:nat} (record: !$A.arr(byte, l, n), n: int n): token_cell =
  if n < 6 then NoToken()
  else if byte2int0($A.get<byte>(record, 1)) <> 83 then NoToken()
  else let
    val token_len = _u16_at(record, 4)
  in
    if token_len <= 0 then NoToken()
    else if token_len > TOKEN_MAX then NoToken()
    else if 6 + token_len > n then NoToken()
    else let
      val token = $A.alloc<byte>(TOKEN_MAX)
      val () = _bytes_from(record, 6, token_len, token, 0)
    in Token(token, token_len) end
  end

(* length, or 0 when it is over most *)
fn _within {length:nat}{most:nat} (length: int length, most: int most): [kept:nat | kept <= length; kept <= most] int kept =
  if length <= most then length else 0

(* Whether text[0, text_len) starts with beginning *)
fun _starts {l:agz}{n:nat}{text_len:nat | text_len <= n}{beginning_len:nat}{j:nat | j <= beginning_len} .<beginning_len - j>.
  (text: !$A.arr(byte, l, n), text_len: int text_len, beginning: string beginning_len, beginning_len: int beginning_len, j: int j): bool =
  if j >= beginning_len then true
  else if j >= text_len then false
  else if byte2int0($A.get<byte>(text, j)) <> char2int0(string_get_at(beginning, j)) then false
  else _starts(text, text_len, beginning, beginning_len, j + 1)

(* A blob's bytes, at most most of them, in an array of most *)
fn _blob_bytes {n:nat}{most:pos | most <= 4096} (blob: $BD.dblob(n), most: int most): [l:agz][kept:nat | kept <= most] @($A.arr(byte, l, most), int kept) = let
  val out = $A.alloc<byte>(most)
  val size = $BD.blob_len(blob)
  val kept = _within(size, most)
  val () = $BD.blob_read(blob, 0, out, kept)
  val () = $BD.blob_free(blob)
in @(out, kept) end

(* The account's address Google gave (empty when it gave none) *)
fn _address_of (account: $R.option([k:pos] $BD.dblob(k))): [l:agz][kept:nat | kept <= ACCOUNT_MAX] @($A.arr(byte, l, ACCOUNT_MAX), int kept) =
  case+ account of
  | ~$R.some(blob) => _blob_bytes(blob, ACCOUNT_MAX)
  | ~$R.none() => let
      val empty = $A.alloc<byte>(ACCOUNT_MAX)
    in @(empty, 0) end

(* The token Google gave, kept *)
fn _token_keep {n:pos} (blob: $BD.dblob(n)): bool = let
  val @(token, token_len) = _blob_bytes(blob, TOKEN_MAX)
in
  if token_len <= 0 then let val () = $A.free<byte>(token) in false end
  else let
    val () = _google_token_save(token, token_len)
    val () = _token_free(_token_swap(Token(token, token_len)))
  in true end
end

fn _text_token_keep (token: $GA.google_text): bool = let
  val @(bytes, n) = $GA.google_text_bytes(token)
in
  if n > TOKEN_MAX then let val () = $A.free<byte>(bytes) in false end
  else let
    val out = $A.alloc<byte>(TOKEN_MAX)
    val @(frozen, borrowed) = $A.freeze<byte>(bytes)
    val () = $A.write_borrow(out, 0, borrowed, n)
    val () = release_bytes(frozen, borrowed)
    val () = _google_token_save(out, n)
    val () = _token_free(_token_swap(Token(out, n)))
  in true end
end

fn _text_address_of (account: $R.option($GA.google_text)): [l:agz][kept:nat | kept <= ACCOUNT_MAX] @($A.arr(byte, l, ACCOUNT_MAX), int kept) = let
  val out = $A.alloc<byte>(ACCOUNT_MAX)
in
  case+ account of
  | ~$R.none() => @(out, 0)
  | ~$R.some(named) => let
      val @(bytes, n) = $GA.google_text_bytes(named)
    in
      if n > ACCOUNT_MAX then let val () = $A.free<byte>(bytes) in @(out, 0) end
      else let
        val @(frozen, borrowed) = $A.freeze<byte>(bytes)
        val () = $A.write_borrow(out, 0, borrowed, n)
        val () = release_bytes(frozen, borrowed)
      in @(out, n) end
    end
end

fn _said_free (said: $R.option($GA.google_said)): void =
  case+ said of ~$R.some(kept) => $GA.google_said_free(kept) | ~$R.none() => ()

(* Whether an access token is held for the store (Google's or
   Dropbox's), or why none could be got *)
datavtype token_access = AccessHeld of () | AccessFailed of (sync_result)

implement $P.dispose<token_access>(access) =
  case+ access of
  | ~AccessHeld() => ()
  | ~AccessFailed(_) => ()

(* The one scope the Google store asks for: drive.appdata, the app data
   folder of the account's Drive *)
#define SCOPE_LEN 45
fn _scope (): [l:agz] $A.arr(byte, l, SCOPE_LEN) = let
  val scope = $A.alloc<byte>(SCOPE_LEN)
  val () = $A.write_text(scope, 0, $A.text_lit("https://www.googleapis.com/auth/drive.appdata"), SCOPE_LEN)
in scope end


fn _form_label (form: $GA.google_form): [f:pos | f < 64] string f =
  case+ form of
  | $GA.AsJson() => "as JSON"
  | $GA.AsString() => "as String gives it"
  | $GA.AsType() => "as its type"
  | $GA.AsTypeTextUnkept() => "as its type, its text not kept"

fn _shown_length {n:nat} (n: int n): [size:nat | size <= n; size <= 1048576] int size =
  if n <= 1048576 then n else 1048576

fn _room {size:nat | size <= 1048576} (size: int size): [room:pos | size <= room; room <= 1048576] int room =
  if size > 0 then size else 1

fn _blob_shown {n:nat}{f:pos | f < 64} (form: string f, blob: $BD.dblob(n)): answer_shown = let
  val n = $BD.blob_len(blob)
  val size = _shown_length(n)
  val out = $A.alloc<byte>(_room(size))
  val () = $BD.blob_read(blob, 0, out, size)
  val () = $BD.blob_free(blob)
in if size < n then AnswerCut(form, out, size, n) else AnswerShown(form, out, size) end

fn _text_shown (text: $R.option($GA.google_raw)): answer_shown =
  case+ text of
  | ~$R.some(~$GA.RawWhole(blob)) => _blob_shown("its form unknown", blob)
  | ~$R.some(~$GA.RawCut(whole, first)) => AnswerCut("its form unknown", first, 1048576, whole)
  | ~$R.none() => NoAnswer()

fn _said_shown (said: $GA.google_said): answer_shown = let
  val ~$GA.GoogleSaid(form, text) = said
in _blob_shown(_form_label(form), text) end

fn _cut_shown (cut: $GA.google_cut): answer_shown = let
  val ~$GA.GoogleCut(form, whole, first) = cut
in AnswerCut(_form_label(form), first, 1048576, whole) end

fn _refusal_result (status: $GA.google_status): sync_result =
  case+ status of
  | $GA.StatusNetworkError() => GoogleUnreachable()
  | $GA.StatusTimeout() => GoogleUnreachable()
  | $GA.StatusSignInRequired() => GoogleAccountNeeded()
  | $GA.StatusInvalidAccount() => GoogleAccountNeeded()
  | $GA.StatusDeveloperError() => GoogleRefused()
  | $GA.StatusServiceVersionUpdateRequired() => GoogleSignInFailed()
  | $GA.StatusServiceDisabled() => GoogleSignInFailed()
  | $GA.StatusResolutionRequired() => GoogleSignInFailed()
  | $GA.StatusInternalError() => GoogleSignInFailed()
  | $GA.StatusError() => GoogleSignInFailed()
  | $GA.StatusInterrupted() => GoogleSignInFailed()
  | $GA.StatusCanceled() => GoogleSignInFailed()
  | $GA.StatusApiNotConnected() => GoogleSignInFailed()
  | $GA.StatusDeadClient() => GoogleSignInFailed()
  | $GA.StatusRemoteException() => GoogleSignInFailed()
  | $GA.StatusConnectionSuspendedDuringCall() => GoogleSignInFailed()
  | $GA.StatusReconnectionTimedOutDuringUpdate() => GoogleSignInFailed()
  | $GA.StatusReconnectionTimedOut() => GoogleSignInFailed()

(* Whether bytes[at, n) holds the registration status's name from at on:
   Play services names it in its message (`[8] Unknown error
   [status=UNREGISTERED_ON_API_CONSOLE]`) under a code (INTERNAL_ERROR)
   that says only that something failed *)
#define UNREGISTERED_LEN 27
fun _unregistered_same {l,p:agz}{size:pos}{n:nat | n <= size}{at,j:nat | j <= UNREGISTERED_LEN; at + UNREGISTERED_LEN <= n} .<UNREGISTERED_LEN - j>.
  (bytes: !$A.arr(byte, l, size), pattern: !$A.arr(byte, p, UNREGISTERED_LEN), n: int n, at: int at, j: int j): bool =
  if j >= UNREGISTERED_LEN then true
  else if byte2int0($A.get<byte>(bytes, at + j)) = byte2int0($A.get<byte>(pattern, j)) then _unregistered_same(bytes, pattern, n, at, j + 1)
  else false

fun _unregistered_from {l,p:agz}{size:pos}{n:nat | n <= size}{at:nat | at <= n} .<n - at>.
  (bytes: !$A.arr(byte, l, size), pattern: !$A.arr(byte, p, UNREGISTERED_LEN), n: int n, at: int at): bool =
  if at + UNREGISTERED_LEN > n then false
  else if _unregistered_same(bytes, pattern, n, at, 0) then true
  else _unregistered_from(bytes, pattern, n, at + 1)

(* Whether Play services' answer says this build is not registered with
   Google, in the answer as the reader's report shows it *)
fn _unregistered_name (): [l:agz] $A.arr(byte, l, UNREGISTERED_LEN) = let
  val name = $A.alloc<byte>(UNREGISTERED_LEN)
  val () = $A.write_text(name, 0, $A.text_lit("UNREGISTERED_ON_API_CONSOLE"), UNREGISTERED_LEN)
in name end

fn _bytes_unregistered {l:agz}{size:pos}{n:nat | n <= size} (bytes: !$A.arr(byte, l, size), n: int n): bool = let
  val pattern = _unregistered_name()
  val found = _unregistered_from(bytes, pattern, n, 0)
  val () = $A.free<byte>(pattern)
in found end

fn _answer_unregistered (answer: !answer_shown): bool =
  case+ answer of
  | @NoAnswer() => let prval () = fold@(answer) in false end
  | @AnswerShown(_, bytes, n) => let
      val found = _bytes_unregistered(bytes, n)
      prval () = fold@(answer)
    in found end
  | @AnswerCut(_, bytes, n, _) => let
      val found = _bytes_unregistered(bytes, n)
      prval () = fold@(answer)
    in found end

(* What a refusal means: a status that is a code for any failure
   (INTERNAL_ERROR, ERROR) is the build's registration when Play
   services' message names it, and no try again helps with that *)
fn _authorize_refused {call_len:pos | call_len < 64}
  (call: string call_len, status: $GA.google_status, said: $GA.google_said): sync_result = let
  val answer = _said_shown(said)
  val result = (if _answer_unregistered(answer) then GoogleRefused() else _refusal_result(status)): sync_result
  val () = _refusal_free(_refusal_swap(RefusalKept(status, call, answer)))
in result end

fn _unparsed {n:pos | n < 64} (name: string n, error: $J.parse_error): unexpected_case =
  case+ error of
  | ~$J.UnexpectedEnd(at) => CaseUnparsed(name, "UnexpectedEnd", at)
  | ~$J.UnexpectedByte(at) => CaseUnparsed(name, "UnexpectedByte", at)
  | ~$J.BadNumber(at) => CaseUnparsed(name, "BadNumber", at)
  | ~$J.NumberTooLong(at) => CaseUnparsed(name, "NumberTooLong", at)
  | ~$J.StringTooLong(at) => CaseUnparsed(name, "StringTooLong", at)
  | ~$J.ControlInString(at) => CaseUnparsed(name, "ControlInString", at)
  | ~$J.BadEscape(at) => CaseUnparsed(name, "BadEscape", at)
  | ~$J.BadHex(at) => CaseUnparsed(name, "BadHex", at)
  | ~$J.InvalidUtf8(at) => CaseUnparsed(name, "InvalidUtf8", at)
  | ~$J.TooDeep(at) => CaseUnparsed(name, "TooDeep", at)
  | ~$J.TrailingData(at) => CaseUnparsed(name, "TrailingData", at)

fn _kind_name (kind: $GA.json_kind): [n:pos | n < 64] string n =
  case+ kind of
  | $GA.KindNull() => "KindNull" | $GA.KindBool() => "KindBool" | $GA.KindNumber() => "KindNumber"
  | $GA.KindString() => "KindString" | $GA.KindArray() => "KindArray" | $GA.KindObject() => "KindObject"

fn _authorization_flaw_name (flaw: $GA.authorization_flaw): [n:pos | n < 64] string n =
  case+ flaw of
  | $GA.AuthorizationMissing() => "AuthorizationMissing"
  | $GA.AuthorizationNull() => "AuthorizationNull"
  | $GA.AuthorizationNotObject() => "AuthorizationNotObject"

fn _text_flaw_name (flaw: $GA.text_flaw): [n:pos | n < 64] string n =
  case+ flaw of
  | $GA.TextMissing() => "TextMissing" | $GA.TextNotString() => "TextNotString"
  | $GA.TextEmpty() => "TextEmpty" | $GA.TextNotPrintable() => "TextNotPrintable"

fn _scopes_flaw_name (flaw: $GA.scopes_flaw): [n:pos | n < 64] string n =
  case+ flaw of
  | $GA.ScopesMissing() => "ScopesMissing" | $GA.ScopesNotList() => "ScopesNotList"
  | $GA.ScopesEmpty() => "ScopesEmpty" | $GA.ScopeNotString() => "ScopeNotString"
  | $GA.ScopeEmpty() => "ScopeEmpty" | $GA.ScopeNotPrintable() => "ScopeNotPrintable"
  | $GA.ScopesTooLong() => "ScopesTooLong"

fn _code_name (code: $GA.rejection_code): [n:pos | n < 64] string n =
  case+ code of
  | $GA.CodeUnexpected() => "CodeUnexpected" | $GA.CodeInvalidOptions() => "CodeInvalidOptions"
  | $GA.CodeSuccess() => "CodeSuccess" | $GA.CodeSuccessCache() => "CodeSuccessCache"
  | $GA.CodeConsentShowing() => "CodeConsentShowing" | $GA.CodeUnknown() => "CodeUnknown"
  | $GA.CodeEmpty() => "CodeEmpty" | $GA.CodeNull() => "CodeNull" | $GA.CodeMissing() => "CodeMissing"

fn _throw_name (what: $GA.google_throw): [n:pos | n < 64] string n =
  case+ what of
  | $GA.LookupThrew() => "LookupThrew" | $GA.ArgumentsThrew() => "ArgumentsThrew" | $GA.MethodThrew() => "MethodThrew"

fn _stage_name (stage: $GA.google_stage): [n:pos | n < 64] string n =
  case+ stage of
  | $GA.StageResolved() => "StageResolved" | $GA.StageRejected() => "StageRejected"
  | $GA.StageLookup() => "StageLookup" | $GA.StageArguments() => "StageArguments" | $GA.StageMethod() => "StageMethod"
  | $GA.StageReturned() => "StageReturned"

fn _unexpected_said {doing_len:pos | doing_len < 128}{call_len:pos | call_len < 64}
  (doing: string doing_len, call: string call_len, unexpected: $GA.google_unexpected): void =
  case+ unexpected of
  | ~$GA.AnswerUndefined() => notice_unexpected(doing, call, CaseNamed("AnswerUndefined"), NoAnswer())
  | ~$GA.AnswerNotJson(said) => notice_unexpected(doing, call, CaseNamed("AnswerNotJson"), _said_shown(said))
  | ~$GA.AnswerUnparsed(said, error) => notice_unexpected(doing, call, _unparsed("AnswerUnparsed", error), _said_shown(said))
  | ~$GA.AnswerTooLarge(cut) => notice_unexpected(doing, call, CaseNamed("AnswerTooLarge"), _cut_shown(cut))
  | ~$GA.AnswerNotObject(kind, said) => notice_unexpected(doing, call, CaseFlawed("AnswerNotObject", _kind_name(kind)), _said_shown(said))
  | ~$GA.NoAuthorization(flaw, said) => notice_unexpected(doing, call, CaseFlawed("NoAuthorization", _authorization_flaw_name(flaw)), _said_shown(said))
  | ~$GA.TokenUnusable(flaw, said) => notice_unexpected(doing, call, CaseFlawed("TokenUnusable", _text_flaw_name(flaw)), _said_shown(said))
  | ~$GA.ScopesUnusable(flaw, said) => notice_unexpected(doing, call, CaseFlawed("ScopesUnusable", _scopes_flaw_name(flaw)), _said_shown(said))
  | ~$GA.AccountUnusable(flaw, said) => notice_unexpected(doing, call, CaseFlawed("AccountUnusable", _text_flaw_name(flaw)), _said_shown(said))
  | ~$GA.ChangeResolvedWith(said) => notice_unexpected(doing, call, CaseNamed("ChangeResolvedWith"), _said_shown(said))
  | ~$GA.RejectionUndefined() => notice_unexpected(doing, call, CaseNamed("RejectionUndefined"), NoAnswer())
  | ~$GA.RejectionNotJson(said) => notice_unexpected(doing, call, CaseNamed("RejectionNotJson"), _said_shown(said))
  | ~$GA.RejectionUnparsed(said, error) => notice_unexpected(doing, call, _unparsed("RejectionUnparsed", error), _said_shown(said))
  | ~$GA.RejectionTooLarge(cut) => notice_unexpected(doing, call, CaseNamed("RejectionTooLarge"), _cut_shown(cut))
  | ~$GA.RejectionNotObject(kind, said) => notice_unexpected(doing, call, CaseFlawed("RejectionNotObject", _kind_name(kind)), _said_shown(said))
  | ~$GA.CodeNotText(kind, said) => notice_unexpected(doing, call, CaseFlawed("CodeNotText", _kind_name(kind)), _said_shown(said))
  | ~$GA.RejectedOther(code, said) => notice_unexpected(doing, call, CaseFlawed("RejectedOther", _code_name(code)), _said_shown(said))
  | ~$GA.Thrown(what, said) => notice_unexpected(doing, call, CaseFlawed("Thrown", _throw_name(what)), _said_shown(said))
  | ~$GA.ThrownUndefined(what) => notice_unexpected(doing, call, CaseFlawed("ThrownUndefined", _throw_name(what)), NoAnswer())
  | ~$GA.ThrownTooLarge(what, cut) => notice_unexpected(doing, call, CaseFlawed("ThrownTooLarge", _throw_name(what)), _cut_shown(cut))
  | ~$GA.NotAPromise(said) => notice_unexpected(doing, call, CaseNamed("NotAPromise"), _said_shown(said))
  | ~$GA.NotAPromiseUndefined() => notice_unexpected(doing, call, CaseNamed("NotAPromiseUndefined"), NoAnswer())
  | ~$GA.NotAPromiseTooLarge(cut) => notice_unexpected(doing, call, CaseNamed("NotAPromiseTooLarge"), _cut_shown(cut))
  | ~$GA.NothingKept(stage) => notice_unexpected(doing, call, CaseFlawed("NothingKept", _stage_name(stage)), NoAnswer())
  | ~$GA.OddAnswer(number, text) => notice_unexpected(doing, call, CaseNumbered("OddAnswer", number), _text_shown(text))

fn _authorize_present (): bool =
  case+ $GA.google_authorize_available() of
  | ~$GA.PluginPresent() => true
  | ~$GA.PluginAbsent() => false
  | ~$GA.PluginUnexpected(unexpected) => let
      val () = _unexpected_said("looking for Google's authorization in the app", "GoogleAuthorize lookup", unexpected)
    in false end

(* How this platform gets the Google store's token: in the app, Play
   services' authorization (bridge's google_authorize: a token with
   nothing shown once access is granted, Google's consent screen before
   that); in a browser, Google Identity Services (bridge's
   google_account: a window at a tap, a token for an hour); or neither.
   Capawesome's Google Sign-In, which google_account uses in the app, is
   not used: it shows Google's sheet each time (#321) *)
datatype google_way = AppAuthorization | BrowserIdentity | NoGoogleWay

(* The way here. In a browser this loads Google's script, so it is asked
   only where a Google store is offered or chosen *)
fn _google_way (): google_way =
  if $BAPP.is_native_platform() then
    (if _authorize_present() then AppAuthorization() else NoGoogleWay())
  else if $GOOGLE.google_token_available() then BrowserIdentity()
  else NoGoogleWay()

fn _authorize_unexpected {doing_len:pos | doing_len < 128}{call_len:pos | call_len < 64}
  (doing: string doing_len, call: string call_len, unexpected: $GA.google_unexpected): sync_result = let
  val () = _refusal_forget()
  val () = _unexpected_said(doing, call, unexpected)
in GoogleUnexpected() end

fn _drive_scopes (): $R.option($GA.google_scopes(45)) =
  case+ $GA.google_scope_of("https://www.googleapis.com/auth/drive.appdata") of
  | ~$R.some(scope) => $R.some($GA.OneScope(scope))
  | ~$R.none() => $R.none()

fn _not_a_scope {doing_len:pos | doing_len < 128} (doing: string doing_len): sync_result = let
  val () = _refusal_forget()
  val () = notice_unexpected(doing, "google_scope_of", CaseNamed("NotAScope"), NoAnswer())
in GoogleUnexpected() end

(* A call to Google that may never answer (#340). The plugin's promise
   ends the call only when it settles, and a plugin that never settles it
   would leave the reader with nothing shown and nothing that ends. A call
   that shows nothing (authorizationForScopes, clearAuthorizationToken)
   is answered, at the latest, by a timer: GOOGLE_ANSWER_MS, and said
   as GoogleNoAnswer. Play services documents no timeout for these
   calls, so the 30 s is chosen from what comparable software does:
   OkHttp ends a request at 10 s each for connect, read and write,
   Firebase Auth's 3 minutes is called too long, Flutter developers
   who bound a hanging signIn() use about 30 s, and Nielsen's 10 s is
   about the limit of a reader's attention (a sync says "Syncing..."
   meanwhile). An answer after the call ended keeps nothing
   (_authorization_late). The consent screen
   (authorizeScopes) is the reader's to take as long as they like, so no
   timer ends it: while it is pending the status card says so and has
   Stop waiting (sync_stop). Each call's outcome is the promise of a
   resolver kept in a cell with the call's number: the plugin's answer and
   the timer (or Stop waiting) each settle that number, the first
   resolves it, and whatever comes after finds another number and is
   dropped *)
#define GOOGLE_ANSWER_MS 30000

(* An answer that came after its call ended (the timer, or Stop waiting):
   nothing is kept from it, no token and no sign-in, so what the reader
   was told (that Google did not answer, or that they stopped waiting)
   stays true. One that is unexpected is still said, as every outcome is *)
fn _authorization_late {w:$GA.asking} (answer: $GA.google_authorization(w)): void =
  case+ answer of
  | ~$GA.Authorized(token, granted, account, said) => let
      val () = $GA.google_text_free(token)
      val () = $GA.google_granted_free(granted)
      val () = $GA.google_said_free(said)
    in (case+ account of ~$R.some(named) => $GA.google_text_free(named) | ~$R.none() => ()) end
  | ~$GA.NotAuthorized(said) => $GA.google_said_free(said)
  | ~$GA.AuthorizeCanceled(said) => $GA.google_said_free(said)
  | ~$GA.ConsentShowing(said) => $GA.google_said_free(said)
  | ~$GA.AuthorizeRefused(_, said) => $GA.google_said_free(said)
  | ~$GA.AuthorizeUnavailable(said) => _said_free(said)
  | ~$GA.AuthorizeUnexpected(unexpected) =>
    _unexpected_said("a call to Google that had ended", "a late answer", unexpected)

datavtype answer_wait =
  | NoAnswerWait of ()
  | AnswerWait of $P.resolver(token_access)

val _silent_wait = ref<answer_wait>(NoAnswerWait())
val _silent_number = ref<int>(0)
val _renewal_wait = ref<answer_wait>(NoAnswerWait())
val _renewal_number = ref<int>(0)

fn _wait_swap (cell: ref(answer_wait), next: answer_wait): answer_wait = let
  var previous: answer_wait = next
  val () = ref_exch_elt<answer_wait>(cell, previous)
in previous end

(* A call begins: its number, its outcome the promise returned *)
fn _wait_begin (cell: ref(answer_wait), number: ref(int), resolver: $P.resolver(token_access)): int = let
  val () = !number := !number + 1
  (* a call still waiting when another begins (none does: each caller
     waits for its call) is told it was not answered *)
  val () = (case+ _wait_swap(cell, AnswerWait(resolver)) of
    | ~NoAnswerWait() => ()
    | ~AnswerWait(old) => $P.resolve<token_access>(old, AccessFailed(GoogleNoAnswer())))
in !number end

(* The call numbered number ends as access, when it is the one waiting:
   the first to settle it resolves it, a later one is dropped *)
fn _wait_settle (cell: ref(answer_wait), number: ref(int), which: int, access: token_access): void =
  if which <> !number then $P.dispose<token_access>(access)
  else let
    val () = !number := !number + 1
  in case+ _wait_swap(cell, NoAnswerWait()) of
    | ~NoAnswerWait() => $P.dispose<token_access>(access)
    | ~AnswerWait(resolver) => $P.resolve<token_access>(resolver, access)
  end

(* An access token for drive.appdata, in the app, given with nothing
   shown (bridge's google_authorization_for_scopes, Play services'
   AuthorizationClient) once the reader has granted it: kept, here and
   on the device. None when the reader must consent first (the grant
   taken back in the Google account): sync pauses until Sync now. Not
   answered within GOOGLE_ANSWER_MS is GoogleNoAnswer *)
fn _silent_access (answer: $GA.google_authorization($GA.Silently)): token_access =
  case+ answer of
  | ~$GA.Authorized(token, granted, account, said) => let
      val () = $GA.google_granted_free(granted)
      val () = $GA.google_said_free(said)
      val () = (case+ account of ~$R.some(named) => $GA.google_text_free(named) | ~$R.none() => ())
    in
      if _text_token_keep(token) then AccessHeld()
      else AccessFailed(GoogleRefused())
    end
  | ~$GA.NotAuthorized(said) => let
      val () = $GA.google_said_free(said)
    in AccessFailed(SignInAgain()) end
  | ~$GA.AuthorizeRefused(status, said) =>
    AccessFailed(_authorize_refused("authorizationForScopes", status, said))
  (* asked only where google_authorize_available: a plugin gone is
     one this build is not set up with *)
  | ~$GA.AuthorizeUnavailable(said) => let
      val () = _said_free(said)
    in AccessFailed(NotSetUp()) end
  | ~$GA.AuthorizeUnexpected(unexpected) =>
    AccessFailed(_authorize_unexpected("syncing with Google", "authorizationForScopes", unexpected))

fn _google_silently (): $P.promise(token_access, $P.Chained) =
  case+ _drive_scopes() of
  | ~$R.none() => $P.ret<token_access>(AccessFailed(_not_a_scope("syncing with Google")))
  | ~$R.some(scopes) => let
  val pending = $GA.google_authorization_for_scopes(scopes)
  val @(outcome, resolver) = $P.create<token_access>()
  val number = _wait_begin(_silent_wait, _silent_number, resolver)
  val () = $P.finish<$GA.google_authorization($GA.Silently)>(pending, llam(answer) =>
    if number <> !_silent_number then _authorization_late(answer)
    else _wait_settle(_silent_wait, _silent_number, number, _silent_access(answer)))
  val () = $P.finish<Int>($P.vow($TM.timer_set(GOOGLE_ANSWER_MS)), llam(_) =>
    _wait_settle(_silent_wait, _silent_number, number, AccessFailed(GoogleNoAnswer())))
in $P.vow(outcome) end

(* The Google store's access token: the one held; else, in the app, one
   given with nothing shown. In a browser none is asked for here: Google
   Identity Services opens its window only at a tap, so sync pauses
   until Sync now *)
fn _google_access (): $P.promise(token_access, $P.Chained) =
  if _token_held() then $P.ret<token_access>(AccessHeld())
  else if _authorize_present() then _google_silently()
  else $P.ret<token_access>(AccessFailed(SignInAgain()))

fn _cleared (change: $GA.google_authorization_change): void =
  case+ change of
  | ~$GA.Changed() => ()
  | ~$GA.ChangeRefused(_, said) => $GA.google_said_free(said)
  | ~$GA.ChangeUnavailable(said) => _said_free(said)
  | ~$GA.ChangeUnexpected(unexpected) =>
    _unexpected_said("clearing a token Google Drive refused", "clearAuthorizationToken", unexpected)

fn _revoked (change: $GA.google_authorization_change): void =
  case+ change of
  | ~$GA.Changed() => ()
  | ~$GA.ChangeRefused(status, rejection) => let
      val said = $A.alloc<byte>(512)
      val stop = _put_literal(said, 0, "Google didn't take back Quire's access to Drive: remove it in your Google account, under Security, Your connections to third-party apps. ")
      val stop = _status_detail(said, stop, status)
    in notice_failure(said, stop, "taking back Quire's access to Google Drive", "revokeAccess", $GA.google_status_name(status), _said_shown(rejection)) end
  | ~$GA.ChangeUnavailable(said) => let
      val () = _said_free(said)
    in notice_error("Google didn't take back Quire's access to Drive: remove it in your Google account, under Security, Your connections to third-party apps.") end
  | ~$GA.ChangeUnexpected(unexpected) =>
    _unexpected_said("taking back Quire's access to Google Drive", "revokeAccess", unexpected)

(* The token Drive refused (401: its hour is up, or the grant was taken
   back) forgotten, here and where it is kept. In the app it is also
   taken out of Play services' cache (google_clear_token), which would
   otherwise give it again, and one is asked for once, with nothing
   shown; in a browser, sync pauses until Sync now *)
fn _google_renewed (): $P.promise(token_access, $P.Chained) = let
  val refused = _token_swap(NoToken())
  val () = _google_token_forget()
in
  if ~_authorize_present() then let
    val () = _token_free(refused)
  in $P.ret<token_access>(AccessFailed(SignInAgain())) end
  else case+ refused of
    | ~NoToken() => _google_silently()
    | ~Token(token, token_len) => let
        val @(token_frozen, token_bytes) = $A.freeze<byte>(token)
        val @(used, rest) = $A.borrow_split<byte>(token_frozen, token_bytes, token_len)
        val text = $GA.google_text_of(used, token_len)
        val token_bytes = $A.borrow_join<byte>(token_frozen, used, rest)
        val () = release_bytes(token_frozen, token_bytes)
      in
        case+ text of
        (* a token with no visible character is none Play services gave:
           there is nothing to clear, and one is asked for *)
        | ~$R.none() => _google_silently()
        | ~$R.some(token) =>
          let
            val pending = $GA.google_clear_token(token)
            val @(outcome, resolver) = $P.create<token_access>()
            val number = _wait_begin(_renewal_wait, _renewal_number, resolver)
            val () = $P.finish<$GA.google_authorization_change>(pending, llam(change) => let
              (* cleared or not, one is asked for: should Play services give
                 the refused one again, Drive's second 401 pauses sync; but
                 not when the clear's answer comes after its timer (#340) *)
              val () = _cleared(change)
            in
              if number <> !_renewal_number then ()
              else $P.finish<token_access>(_google_silently(), llam(access) =>
                _wait_settle(_renewal_wait, _renewal_number, number, access))
            end)
            val () = $P.finish<Int>($P.vow($TM.timer_set(GOOGLE_ANSWER_MS)), llam(_) =>
              _wait_settle(_renewal_wait, _renewal_number, number, AccessFailed(GoogleNoAnswer())))
          in $P.vow(outcome) end
      end
end

(* What a Drive status says: 401 is a token Drive no longer takes (it is
   forgotten, and sync paused until Sync now signs in again), -1 to -3
   drive.bats' own *)
fn _drive_failure (status: Int): sync_result =
  if status = 401 then let
    val () = _google_token_forget()
  in SignInAgain() end
  else if status = 0 then Unreachable()
  else if status = ~1 then TooLarge()
  else if status = ~2 then NoMemory()
  else if status = ~3 then Damaged()
  else if status = 403 then GoogleRefused()
  else ServerError()

(* The file read from the account's Drive with the token held *)
fn _drive_read_held (): $P.promise(drive_got, $P.Chained) =
  case+ _token_swap(NoToken()) of
  | ~NoToken() => $P.ret<drive_got>(DriveFailed(401))
  | ~Token(token, token_len) => let
      val pending = drive_read(token, token_len, SYNC_MAX_BYTES)
      val () = _token_free(_token_swap(Token(token, token_len)))
    in pending end

fn _drive_answer (got: drive_got): read_answer =
  case+ got of
  | ~DriveGot(owner, file, n) => ReadFile(owner, file, n)
  | ~DriveNothing() => ReadNothing()
  | ~DriveFailed(status) => ReadFailed(_drive_failure(status), status)

(* The Android store: the file in the account's Drive, with the token
   held or one given with nothing shown; a token Drive refuses is
   replaced once (_google_renewed) *)
fn _android_read (): $P.promise(read_answer, $P.Chained) =
  $P.and_then<token_access><read_answer>(_google_access(), llam(access) =>
    case+ access of
    | ~AccessFailed(why) => $P.ret<read_answer>(ReadFailed(why, 0))
    | ~AccessHeld() => $P.and_then<drive_got><read_answer>(_drive_read_held(), llam(got) =>
      case+ got of
      | ~DriveFailed(status) =>
        if status = 401 then
          $P.and_then<token_access><read_answer>(_google_renewed(), llam(again) =>
            case+ again of
            | ~AccessFailed(why) => $P.ret<read_answer>(ReadFailed(why, 401))
            | ~AccessHeld() => $P.and_then<drive_got><read_answer>(_drive_read_held(), llam(got) =>
              $P.ret<read_answer>(_drive_answer(got))))
        else $P.ret<read_answer>(ReadFailed(_drive_failure(status), status))
      | other => $P.ret<read_answer>(_drive_answer(other))))

(* The write, with the token the read had. A token Drive refuses now
   (its hour ran out since the read) is replaced as a read's is, and the
   round reads, merges and writes again, as after another device's
   write *)
fn _android_write {body_loc:agz}{body_size:pos | body_size <= 16777216}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(write_answer, $P.Chained) =
  case+ _token_swap(NoToken()) of
  | ~NoToken() => $P.ret<write_answer>(WriteFailed(SignInAgain(), 0))
  | ~Token(token, token_len) => let
      val pending = drive_write(token, token_len, body, body_size)
      val () = _token_free(_token_swap(Token(token, token_len)))
    in
      $P.and_then<drive_put><write_answer>(pending, llam(put) =>
        case+ put of
        | ~DrivePut() => $P.ret<write_answer>(Written())
        | ~DriveChanged() => $P.ret<write_answer>(WriteConflict())
        | ~DrivePutFailed(status) =>
          if status = 401 then
            $P.and_then<token_access><write_answer>(_google_renewed(), llam(again) =>
              case+ again of
              | ~AccessHeld() => $P.ret<write_answer>(WriteConflict())
              | ~AccessFailed(why) => $P.ret<write_answer>(WriteFailed(why, 401)))
          else $P.ret<write_answer>(WriteFailed(_drive_failure(status), status)))
    end

(* The backed-up file's name: in bridge's backup directory, which
   Android's Auto Backup keeps *)
fn _backup_name (): [l:agz] $A.arr(byte, l, 15) = let
  val name = $A.alloc<byte>(15)
  val () = $A.write_text(name, 0, $A.text_lit("quire-sync.json"), 15)
in name end

(* The backed-up file: the merge as it was last written here, or, after
   a reinstall, as Auto Backup restored it *)
fn _backup_read (): $P.promise(read_answer, $P.Chained) = let
  val @(name_frozen, name_bytes) = $A.freeze<byte>(_backup_name())
  val pending = $BACKUP.backup_file_read(name_bytes, 15)
  val () = release_bytes(name_frozen, name_bytes)
in
  $P.and_then<$BACKUP.backup_found><read_answer>(pending, llam(found) =>
    case+ found of
    | ~$BACKUP.BackupNone() => $P.ret<read_answer>(ReadNothing())
    | ~$BACKUP.BackupUnreadable() => $P.ret<read_answer>(ReadFailed(Damaged(), 0))
    | ~$BACKUP.BackupFound(blob) => let
        val size = $BD.blob_len(blob)
      in
        if size > SYNC_MAX_BYTES then let val () = $BD.blob_free(blob) in $P.ret<read_answer>(ReadFailed(TooLarge(), 0)) end
        else (case+ piece_new(size) of
          | ~NoPiece() => let val () = $BD.blob_free(blob) in $P.ret<read_answer>(ReadFailed(NoMemory(), 0)) end
          | ~Piece(owner, file) => let
              val () = $BD.blob_read(blob, 0, file, size)
              val () = $BD.blob_free(blob)
            in $P.ret<read_answer>(ReadFile(owner, file, size)) end)
      end)
end

(* body[0, body_size) as the backed-up file *)
fn _backup_write {body_loc:agz}{body_size:pos}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(write_answer, $P.Chained) = let
  val @(name_frozen, name_bytes) = $A.freeze<byte>(_backup_name())
  val pending = $BACKUP.backup_file_write(name_bytes, 15, body, body_size)
  val () = release_bytes(name_frozen, name_bytes)
in
  $P.and_then<$BACKUP.backup_written><write_answer>(pending, llam(written) =>
    case+ written of
    | $BACKUP.BackupWritten() => $P.ret<write_answer>(Written())
    | $BACKUP.BackupNotWritten() => $P.ret<write_answer>(WriteFailed(NoMemory(), 0)))
end

(* The Dropbox store: an access token, kept, or got anew with the
   refresh token kept (no sheet, no page: Dropbox's token endpoint) *)
fn _dropbox_access (): $P.promise(token_access, $P.Chained) = let
  val held = _token_swap(NoToken())
  val have = (case+ held of Token(_, _) => true | NoToken() => false): bool
  val () = _token_free(_token_swap(held))
in
  if have then $P.ret<token_access>(AccessHeld())
  else let
    val key = $A.alloc<byte>(256)
    val key_len = sync_clients_dropbox(key)
  in
    if key_len <= 0 then let
      val () = $A.free<byte>(key)
    in $P.ret<token_access>(AccessFailed(DropboxNotSetUp())) end
    else (case+ _store_swap(_store, NoStore()) of
      | ~Dropbox(refresh, refresh_len) => let
          val pending = dropbox_refresh(key, key_len, refresh, refresh_len)
          val () = $A.free<byte>(key)
          val () = _store_free(_store_swap(_store, Dropbox(refresh, refresh_len)))
        in
          $P.and_then<dropbox_tokens><token_access>(pending, llam(tokens) =>
            case+ tokens of
            | ~DropboxTokens(access, access_len, refresh, _) => let
                val () = $A.free<byte>(refresh)
                val () = _token_free(_token_swap(Token(access, access_len)))
              in $P.ret<token_access>(AccessHeld()) end
            | ~DropboxRefused(status) =>
              $P.ret<token_access>(AccessFailed(if status = 0 then Unreachable()
                else if status = 400 then DropboxSignInAgain()
                else if status = 401 then DropboxSignInAgain()
                else ServerError())))
        end
      | other => let
          val () = $A.free<byte>(key)
          val () = _store_free(_store_swap(_store, other))
        in $P.ret<token_access>(AccessFailed(NotSyncedYet())) end)
  end
end

(* What a Dropbox status says: 401 is an access token Dropbox no longer
   takes (it is forgotten; the next sync gets another) *)
fn _dropbox_failure (status: Int): sync_result =
  if status = 401 then let
    val () = _token_free(_token_swap(NoToken()))
  in DropboxSignInAgain() end
  else if status = 0 then Unreachable()
  else if status = ~1 then TooLarge()
  else if status = ~2 then NoMemory()
  else if status = ~3 then Damaged()
  else ServerError()

(* The file read with the access token kept *)
fn _dropbox_read_kept (): $P.promise(drive_got, $P.Chained) =
  case+ _token_swap(NoToken()) of
  | ~NoToken() => $P.ret<drive_got>(DriveFailed(401))
  | ~Token(token, token_len) => let
      val pending = dropbox_read(token, token_len, SYNC_MAX_BYTES)
      val () = _token_free(_token_swap(Token(token, token_len)))
    in pending end

fn _dropbox_answer (got: drive_got): read_answer =
  case+ got of
  | ~DriveGot(owner, file, n) => ReadFile(owner, file, n)
  | ~DriveNothing() => ReadNothing()
  | ~DriveFailed(status) => ReadFailed(_dropbox_failure(status), status)

(* The file read: with the access token, or one got anew; an access
   token Dropbox no longer takes (it expires after hours) is replaced
   once, with no sign-in *)
fn _dropbox_read (): $P.promise(read_answer, $P.Chained) =
  $P.and_then<token_access><read_answer>(_dropbox_access(), llam(access) =>
    case+ access of
    | ~AccessFailed(why) => $P.ret<read_answer>(ReadFailed(why, 0))
    | ~AccessHeld() => $P.and_then<drive_got><read_answer>(_dropbox_read_kept(), llam(got) =>
      case+ got of
      | ~DriveFailed(status) =>
        if status = 401 then let
          val () = _token_free(_token_swap(NoToken()))
        in
          $P.and_then<token_access><read_answer>(_dropbox_access(), llam(again) =>
            case+ again of
            | ~AccessFailed(why) => $P.ret<read_answer>(ReadFailed(why, 0))
            | ~AccessHeld() => $P.and_then<drive_got><read_answer>(_dropbox_read_kept(), llam(got) =>
              $P.ret<read_answer>(_dropbox_answer(got))))
        end
        else $P.ret<read_answer>(ReadFailed(_dropbox_failure(status), status))
      | other => $P.ret<read_answer>(_dropbox_answer(other))))

fn _dropbox_write {body_loc:agz}{body_size:pos}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(write_answer, $P.Chained) =
  case+ _token_swap(NoToken()) of
  | ~NoToken() => $P.ret<write_answer>(WriteFailed(DropboxSignInAgain(), 0))
  | ~Token(token, token_len) => let
      val pending = dropbox_write(token, token_len, body, body_size)
      val () = _token_free(_token_swap(Token(token, token_len)))
    in
      $P.and_then<drive_put><write_answer>(pending, llam(put) =>
        case+ put of
        | ~DrivePut() => $P.ret<write_answer>(Written())
        | ~DriveChanged() => $P.ret<write_answer>(WriteConflict())
        | ~DrivePutFailed(status) => $P.ret<write_answer>(WriteFailed(_dropbox_failure(status), status)))
    end

(* Reads the file from the store *)
fn store_read (): $P.promise(read_answer, $P.Chained) =
  case+ _store_kind() of
  | WebDavKind() => _webdav_read(WrongCredentials())
  | FastmailKind() => _fastmail_read()
  | AndroidKind() => _android_read()
  | DropboxKind() => _dropbox_read()
  | BackupKind() => _backup_read()
  | NoStoreKind() => $P.ret<read_answer>(ReadFailed(NotSyncedYet(), 0))

(* Writes body[0, body_size) to the store, as a change of the version
   read; once a store's write is done, the app's backed-up file is
   written too, for Auto Backup *)
fn store_write {body_loc:agz}{body_size:pos}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(write_answer, $P.Chained) = let
  val kind = _store_kind()
  val backed_up = (case+ kind of WebDavKind() => true | AndroidKind() => true | DropboxKind() => true | FastmailKind() => true | BackupKind() => false | NoStoreKind() => false): bool
  val () = (if ~backed_up then ()
    else if ~$BACKUP.backup_file_available() then ()
    (* ignored: the backed-up file is a safety net; one not written
       now is written at the next sync *)
    else $P.finish<write_answer>(_backup_write(body, body_size), llam(_) => ()))
in
  case+ kind of
  | WebDavKind() => _webdav_write(body, body_size, WrongCredentials())
  | FastmailKind() => _webdav_write(body, body_size, FastmailRefused())
  | AndroidKind() =>
    if body_size > 16777216 then $P.ret<write_answer>(WriteFailed(TooLarge(), 0)) else _android_write(body, body_size)
  | DropboxKind() => _dropbox_write(body, body_size)
  | BackupKind() => _backup_write(body, body_size)
  | NoStoreKind() => $P.ret<write_answer>(WriteFailed(NotSyncedYet(), 0))
end

(* ============================================================
   A sync file, read: where its books and devices are
   ============================================================ *)

(* The objects of a file's array, each its id (a book's two halves; a
   device's number, and 0) and where it is, file[start, stop) *)
datavtype spans(int, int) =
  | {n:int} SpansNil(n, 0) of ()
  | {n:int}{count:nat}{start,stop:nat | start < stop; stop <= n} SpansCons(n, count + 1) of (Int, Int, int start, int stop, spans(n, count))

(* A sync file in a piece, file[0, n): where its collections' array is
   (-1 none), and its books and devices *)
datavtype held =
  | NoHeld of ()
  | {owner,l:agz}{n:pos | n <= 268435456}{names_at:int | ~1 <= names_at; names_at <= n}{books_count,devices_count:nat}
    Held of (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int n, int names_at, spans(n, books_count), spans(n, devices_count))

fun _spans_free {n:int}{count:nat} .<count>. (spans: spans(n, count)): void =
  case+ spans of
  | ~SpansNil() => ()
  | ~SpansCons(_, _, _, _, rest) => _spans_free(rest)

fn _held_free (file: held): void =
  case+ file of
  | ~NoHeld() => ()
  | ~Held(owner, bytes, _, _, books, devices) => let
      val () = _spans_free(books)
      val () = _spans_free(devices)
    in piece_free(owner, bytes) end

(* The file read (while the merge is made), and the file written (until
   it is taken here) *)
val _remote = ref<held>(NoHeld())
val _written = ref<held>(NoHeld())

fn _held_swap (cell: ref(held), file: held): held = let
  var previous: held = file
  val () = ref_exch_elt<held>(cell, previous)
in previous end

(* The id an object's members give (from position, past its brace):
   its "id" (a book's, which_id true) or its "device" number *)
fun _object_id {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16), which_id: bool)
  : @(bool, Int, Int) = let
  val next = jr_ws(file, n, position)
in
  if next >= n then @(false, 0, 0)
  else if jr_is(file, n, next, 125) then @(false, 0, 0)
  else if jr_is(file, n, next, 44) then _object_id(file, n, next + 1, key, which_id)
  else let
    val @(found, key_len, value_at) = jr_key(file, n, next, key, 16)
  in
    if ~found then @(false, 0, 0)
    else if (if which_id then jr_key_is(key, key_len, "id") else false) then let
      val @(id_found, id_high, id_low, _) = jr_id(file, n, value_at)
    in @(id_found, id_high, id_low) end
    else if (if which_id then false else jr_key_is(key, key_len, "device")) then let
      val @(number_found, number, _) = jr_int(file, n, value_at)
    in @(number_found, number, 0) end
    else _object_id(file, n, jr_skip(file, n, value_at), key, which_id)
  end
end

(* The objects of an array from position, to its closing bracket, onto
   spans *)
fun _objects {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{count:nat} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16), which_id: bool, spans: spans(n, count))
  : [stop:int | position <= stop; stop <= n][total:nat] @(bool, spans(n, total), int stop) = let
  val next = jr_ws(file, n, position)
in
  if next >= n then @(false, spans, n)
  else if jr_is(file, n, next, 93) then @(true, spans, next + 1)
  else if jr_is(file, n, next, 44) then _objects(file, n, next + 1, key, which_id, spans)
  else if jr_is(file, n, next, 123) then let
    val stop = jr_skip(file, n, next)
  in
    if stop <= next then @(false, spans, stop)
    else let
      val @(found, high, low) = _object_id(file, n, next + 1, key, which_id)
    in
      if found then _objects(file, n, stop, key, which_id, SpansCons(high, low, next, stop, spans))
      else _objects(file, n, stop, key, which_id, spans)
    end
  end
  else @(false, spans, next)
end

(* The members of a sync file's object from position, to its closing
   brace: whether it is one ("quire" 1), where its collections are, its
   books and devices *)
fun _top {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{names_at:int | ~1 <= names_at; names_at <= n}{books_count,devices_count:nat} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   quire: bool, names_at: int names_at, books: spans(n, books_count), devices: spans(n, devices_count))
  : [found_at:int | ~1 <= found_at; found_at <= n][books_total,devices_total:nat] @(bool, int found_at, spans(n, books_total), spans(n, devices_total)) = let
  val next = jr_ws(file, n, position)
in
  if next >= n then @(false, names_at, books, devices)
  else if jr_is(file, n, next, 125) then @(quire, names_at, books, devices)
  else if jr_is(file, n, next, 44) then _top(file, n, next + 1, key, quire, names_at, books, devices)
  else let
    val @(found, key_len, value_at) = jr_key(file, n, next, key, 16)
  in
    if ~found then @(false, names_at, books, devices)
    else if value_at >= n then @(false, names_at, books, devices)
    else if jr_key_is(key, key_len, "quire") then let
      val @(is_int, version, stop) = jr_int(file, n, value_at)
    in _top(file, n, stop, key, (if is_int then version = 1 else false), names_at, books, devices) end
    else if jr_key_is(key, key_len, "collections") then
      (if jr_is(file, n, value_at, 91) then _top(file, n, jr_skip(file, n, value_at), key, quire, value_at, books, devices)
       else _top(file, n, jr_skip(file, n, value_at), key, quire, ~1, books, devices))
    else if jr_key_is(key, key_len, "books") then
      (if jr_is(file, n, value_at, 91) then let
         val @(closed, found_books, stop) = _objects(file, n, value_at + 1, key, true, books)
       in if closed then _top(file, n, stop, key, quire, names_at, found_books, devices) else @(false, names_at, found_books, devices) end
       else _top(file, n, jr_skip(file, n, value_at), key, quire, names_at, books, devices))
    else if jr_key_is(key, key_len, "devices") then
      (if jr_is(file, n, value_at, 91) then let
         val @(closed, found_devices, stop) = _objects(file, n, value_at + 1, key, false, devices)
       in if closed then _top(file, n, stop, key, quire, names_at, books, found_devices) else @(false, names_at, books, found_devices) end
       else _top(file, n, jr_skip(file, n, value_at), key, quire, names_at, books, devices))
    else _top(file, n, jr_skip(file, n, value_at), key, quire, names_at, books, devices)
  end
end

(* A sync file in a piece, read (its bytes checked here, once): held,
   or none when it is not one *)
fn _hold {owner,l:agz}{n:pos | n <= 268435456} (owner: piece_owner(n, owner), file: $A.arrx(byte, l, n, owner), n: int n): held = let
  val start = jr_ws(file, n, 0)
in
  if start >= n then let val () = piece_free(owner, file) in NoHeld() end
  else if ~jr_is(file, n, start, 123) then let val () = piece_free(owner, file) in NoHeld() end
  else let
    val key = $A.alloc<byte>(16)
    val @(whole, names_at, books, devices) = _top(file, n, start + 1, key, false, ~1, SpansNil(), SpansNil())
    val () = $A.free<byte>(key)
  in
    if whole then Held(owner, file, n, names_at, books, devices)
    else let
      val () = _spans_free(books)
      val () = _spans_free(devices)
      val () = piece_free(owner, file)
    in NoHeld() end
  end
end

(* An empty file: "{}" *)
fn _empty (): held =
  case+ piece_new(2) of
  | ~NoPiece() => NoHeld()
  | ~Piece(owner, file) => let
      val () = $A.write_byte(file, 0, 123)
      val () = $A.write_byte(file, 1, 125)
    in Held(owner, file, 2, ~1, SpansNil(), SpansNil()) end

(* Where the book id_high, id_low starts in the file, or -1 *)
fun _book_start {n:nat}{count:nat} .<count>. (spans: !spans(n, count), id_high: Int, id_low: Int): [start:int | ~1 <= start; start < n] int start =
  case+ spans of
  | SpansNil() => ~1
  | SpansCons(high, low, start, _, rest) =>
    if high = id_high then (if low = id_low then start else _book_start(rest, id_high, id_low))
    else _book_start(rest, id_high, id_low)

(* Whether a device is numbered device in spans *)
fun _has_device {n:int}{count:nat} .<count>. (spans: !spans(n, count), device: Int): bool =
  case+ spans of
  | SpansNil() => false
  | SpansCons(number, _, _, _, rest) => if number = device then true else _has_device(rest, device)

(* A copy of spans in the order of the file (they are found the last
   first), onto reversed *)
fun _reversed {n:int}{count,reversed_count:nat} .<count>. (spans: !spans(n, count), reversed: spans(n, reversed_count)): spans(n, count + reversed_count) =
  case+ spans of
  | SpansNil() => reversed
  | SpansCons(high, low, start, stop, rest) => _reversed(rest, SpansCons(high, low, start, stop, reversed))

(* ============================================================
   The collections: the file's, by name
   ============================================================ *)

(* The file's collections are numbered as its array lists them; the
   merge writes the file's first, then this device's it does not have.
   numbering: each of this device's collections (as the library numbers
   them) and its number in the file *)
datavtype numbering(int) =
  | NumberingNil(0) of ()
  | {count:nat} NumberingCons(count + 1) of (int, int, numbering(count))

val _numbering = ref<[count:nat] numbering(count)>(NumberingNil())

fun _numbering_free {count:nat} .<count>. (numbering: numbering(count)): void =
  case+ numbering of
  | ~NumberingNil() => ()
  | ~NumberingCons(_, _, rest) => _numbering_free(rest)

fn _numbering_take (): [count:nat] numbering(count) = let
  var taken: [count:nat] numbering(count) = NumberingNil()
  val () = ref_exch_elt<[count:nat] numbering(count)>(_numbering, taken)
in taken end

fn _numbering_put {count:nat} (numbering: numbering(count)): void = let
  var previous: [count:nat] numbering(count) = numbering
  val () = ref_exch_elt<[count:nat] numbering(count)>(_numbering, previous)
in _numbering_free(previous) end

fun _file_number {count:nat} .<count>. (numbering: !numbering(count), collection: int): int =
  case+ numbering of
  | NumberingNil() => ~1
  | NumberingCons(here, there, rest) => if here = collection then there else _file_number(rest, collection)

(* A library mask as the file numbers its collections *)
fun _to_file {collection:nat | collection <= 8} .<8 - collection>. (mask: int, collection: int collection, mapped: int): int =
  if collection >= 8 then mapped
  else if $AR.band_int_int(mask, $AR.bsl_int_int(1, collection)) = 0 then _to_file(mask, collection + 1, mapped)
  else let
    val numbering = _numbering_take()
    val there = _file_number(numbering, collection)
    val () = _numbering_put(numbering)
  in
    if there < 0 then _to_file(mask, collection + 1, mapped)
    else if there >= 31 then _to_file(mask, collection + 1, mapped)
    else _to_file(mask, collection + 1, $AR.bor_int_int(mapped, $AR.bsl_int_int(1, there)))
  end

(* Whether name[0, name_len) is buffer[0, buffer_len) *)
fun _same_name {name_loc,buffer_loc:agz}{name_size,buffer_size:nat}{name_len:nat | name_len <= name_size}{buffer_len:nat | buffer_len <= buffer_size}{j:nat | j <= name_len} .<name_len - j>.
  (name: !$A.arr(byte, name_loc, name_size), name_len: int name_len, buffer: !$A.arr(byte, buffer_loc, buffer_size), buffer_len: int buffer_len, j: int j): bool =
  if name_len <> buffer_len then false
  else if j >= name_len then true
  else if j >= buffer_len then false
  else if byte2int0($A.get<byte>(name, j)) <> byte2int0($A.get<byte>(buffer, j)) then false
  else _same_name(name, name_len, buffer, buffer_len, j + 1)

(* The number in the file's collections (the array's items from
   position, from number on) of the one named name[0, name_len), or
   -1; and how many there are *)
fun _name_number {l,name_loc,buffer_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{name_size:nat}{name_len:nat | name_len <= name_size} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position, name: !$A.arr(byte, name_loc, name_size), name_len: int name_len,
   buffer: !$A.arr(byte, buffer_loc, 256), number: int, found: int): @(int, int) = let
  val next = jr_ws(file, n, position)
in
  if next >= n then @(found, number)
  else if jr_is(file, n, next, 93) then @(found, number)
  else if jr_is(file, n, next, 44) then _name_number(file, n, next + 1, name, name_len, buffer, number, found)
  else let
    val @(read, buffer_len, stop) = jr_str(file, n, next, buffer, 256)
  in
    if ~read then @(found, number)
    else _name_number(file, n, stop, name, name_len, buffer, number + 1,
      (if found >= 0 then found else if _same_name(name, name_len, buffer, buffer_len, 0) then number else ~1))
  end
end

(* The number of the file's collection named name[0, name_len), or -1 *)
fn _name_in_file {file_loc,name_loc:agz}{file_owner:addr}{file_size:nat}{names_at:int | ~1 <= names_at; names_at <= file_size}
  {name_size:nat}{name_len:nat | name_len <= name_size}
  (file: !$A.arrx(byte, file_loc, file_size, file_owner), file_size: int file_size, names_at: int names_at,
   name: !$A.arr(byte, name_loc, name_size), name_len: int name_len): int =
  if names_at < 0 then ~1
  else if names_at >= file_size then ~1
  else let
    val buffer = $A.alloc<byte>(256)
    val @(found, _) = _name_number(file, file_size, names_at + 1, name, name_len, buffer, 0, ~1)
    val () = $A.free<byte>(buffer)
  in found end

(* The library's collections from collection on: each numbered as the
   file has it, or after the file's (extra of them so far), and the
   names the file does not have after a comma at out[position] *)
fun _numbering_make {l,file_loc:agz}{owner,file_owner:addr}{n,file_size:nat}{collection:nat | collection <= 8}
  {position:nat | position + 250 * (8 - collection) <= n}{names_at:int | ~1 <= names_at; names_at <= file_size} .<8 - collection>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, file: !$A.arrx(byte, file_loc, file_size, file_owner), file_size: int file_size,
   names_at: int names_at, file_count: int, collection: int collection, extra: int, numbering: [count:nat] numbering(count), first: bool)
  : [stop:nat | stop <= position + 250 * (8 - collection)][total:nat] @(int stop, numbering(total)) =
  if collection >= 8 then @(position, numbering)
  else if collection >= lib_coll_count() then @(position, numbering)
  else let
    val @(name, name_len) = lib_coll_name_copy(collection)
    val found = _name_in_file(file, file_size, names_at, name, name_len)
  in
    if found >= 0 then let
      val () = $A.free<byte>(name)
    in _numbering_make(out, position, file, file_size, names_at, file_count, collection + 1, extra, NumberingCons(collection, found, numbering), first) end
    else let
      val after_comma = (if first then position else jw_lit(out, position, ",")): [after:nat | position <= after; after <= position + 1] int after
      val after_name = jw_str(out, after_comma, name, name_len)
      val () = $A.free<byte>(name)
    in _numbering_make(out, after_name, file, file_size, names_at, file_count, collection + 1, extra + 1, NumberingCons(collection, file_count + extra, numbering), false) end
  end

(* How many collections the file's array (from position) has *)
fn _names_count {l:agz}{owner:addr}{n:nat}{names_at:int | ~1 <= names_at; names_at <= n}
  (file: !$A.arrx(byte, l, n, owner), n: int n, names_at: int names_at): int =
  if names_at < 0 then 0
  else if names_at >= n then 0
  else let
    val empty = $A.alloc<byte>(1)
    val buffer = $A.alloc<byte>(256)
    val @(_, count) = _name_number(file, n, names_at + 1, empty, 0, buffer, 0, ~1)
    val () = $A.free<byte>(empty)
    val () = $A.free<byte>(buffer)
  in count end

(* ============================================================
   A sync's state
   ============================================================ *)

(* The file made, a chunk at a time *)
val _out = ref<jfile(SYNC_MAX_BYTES)>(jfile_new{SYNC_MAX_BYTES}())

fn _out_take (): jfile(SYNC_MAX_BYTES) = let
  var file: jfile(SYNC_MAX_BYTES) = jfile_new{SYNC_MAX_BYTES}()
  val () = ref_exch_elt<jfile(SYNC_MAX_BYTES)>(_out, file)
in file end

fn _out_put (file: jfile(SYNC_MAX_BYTES)): void = let
  var current: jfile(SYNC_MAX_BYTES) = file
  val () = ref_exch_elt<jfile(SYNC_MAX_BYTES)>(_out, current)
in jfile_free(current) end

fn _push (chunk: jchunk): void = _out_put(jfile_push(_out_take(), SYNC_MAX_BYTES, chunk))

fn _text_chunk {text_len:pos | text_len <= 64} (text: string text_len): jchunk =
  case+ piece_new(64) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => JChunk(owner, out, jw_lit(out, 0, text))

(* This device's number for this sync: its own, or the minute it first
   syncs (the next one free in the file) *)
val _device_now = ref<Int>(0)
(* Whether a book of the file's (or of this device's) has been written
   yet *)
val _books_written = ref<bool>(false)
(* The open book's key (0 none): its place is offered, not taken *)
val _open_key = ref<Int>(0)
(* The place another device read offered for it: chapter (-1 none),
   page, anchor, and when that device read it (its stamp) *)
val _further_chapter = ref<Int>(~1)
val _further_page = ref<Int>(0)
val _further_anchor = ref<Int>(~1)
val _further_stamp = ref<Int>(0)
(* Whether a sync is under way, whether another was asked for meanwhile,
   and the tries of this one *)
val _busy = ref<bool>(false)
val _again = ref<bool>(false)
val _tries = ref<int>(0)
(* How a round of a sync (the file read, merged and written) ended: the
   sync ended (RoundEnded), or another device wrote the file first, and
   it is read and merged again (RoundConflict). The round under way
   holds the resolver of the promise sync_run's rounds wait on: the
   code that ends a round comes before sync_run's, and calls it only
   through that promise, so no function calls itself, and the rounds
   are counted (_rounds' metric) *)
datatype round_end = RoundEnded | RoundConflict

implement $P.dispose<round_end>(_) = ()

datavtype round =
  | NoRound of ()
  | Round of $P.resolver(round_end)

val _round = ref<round>(NoRound())

fn _round_swap (next: round): round = let
  var previous: round = next
  val () = ref_exch_elt<round>(_round, previous)
in previous end

(* The round under way, ended as how *)
fn _round_settle (how: round_end): void =
  case+ _round_swap(NoRound()) of
  | ~NoRound() => ()
  | ~Round(resolver) => $P.resolve<round_end>(resolver, how)

(* The end of a sync: how it ended, kept and shown; its round ended
   (another starts when one was asked for meanwhile) *)
fn _end (result: sync_result, status: Int): void = let
  val () = _held_free(_held_swap(_remote, NoHeld()))
  val () = _held_free(_held_swap(_written, NoHeld()))
  val () = _out_put(jfile_new{SYNC_MAX_BYTES}())
  val () = !_last_result := result
  val () = !_last_status := status
  val () = !_last_minutes := $TM.epoch_minutes()
  val () = _state_save()
  val () = _status_show()
  val () = _reader_told(result)
  val () = !_busy := false
in _round_settle(RoundEnded()) end

fn _fail (result: sync_result, status: Int): void = _end(result, status)

fn _done (): void = let
  (* this device's number is its own once the file has it *)
  val () = (if !_device <= 0 then !_device := !_device_now else ())
in _end(Synced(), 0) end

(* ============================================================
   The merge, taken: once the file is written
   ============================================================ *)

(* Offers the open book's place another device read, dated stamp: the
   offer's button names its chapter *)
fn _offer (chapter: Int, page: Int, anchor: Int, stamp: Int): void = let
  val () = !_further_chapter := chapter
  val () = !_further_page := page
  val () = !_further_anchor := anchor
  val () = !_further_stamp := stamp
  val label = $A.alloc<byte>(64)
  val after = _put_literal(label, 0, "Go to where you were on another device (chapter ")
  val chapter_number = (if chapter >= 0 then chapter + 1 else 1): Int
  val after = $S.int_to_str(label, after, 64, chapter_number)
  val after = _put_literal(label, after, ")")
  val () = ui_text_buf("sync-go", label, after)
in ui_show("sync-offer", true) end

(* A device's reading log's [day, minutes] pairs from position, to the
   array's closing bracket: added to the days read elsewhere *)
fun _days_at {l:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position): void = let
  val next = jr_ws(file, n, position)
in
  if next >= n then ()
  else if jr_is(file, n, next, 93) then ()
  else if jr_is(file, n, next, 44) then _days_at(file, n, next + 1)
  else if ~jr_is(file, n, next, 91) then ()
  else let
    val @(day_found, day, after_day) = jr_int(file, n, jr_ws(file, n, next + 1))
    val comma = jr_ws(file, n, after_day)
  in
    if ~day_found then ()
    else if ~jr_is(file, n, comma, 44) then ()
    else if comma >= n then ()
    else let
      val @(minutes_found, minutes, after_minutes) = jr_int(file, n, jr_ws(file, n, comma + 1))
      val close = jr_ws(file, n, after_minutes)
    in
      if ~minutes_found then ()
      else if ~jr_is(file, n, close, 93) then ()
      else if close >= n then ()
      else let
        val () = stats_elsewhere_add(day, minutes)
      in _days_at(file, n, close + 1) end
    end
  end
end

(* A device's book entry's members from position: its id, minutes and
   pages *)
fun _reading_members {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   found: bool, id_high: Int, id_low: Int, minutes: Int, pages: Int)
  : [stop:int | position <= stop; stop <= n] @(bool, Int, Int, Int, Int, int stop) = let
  val next = jr_ws(file, n, position)
in
  if next >= n then @(false, id_high, id_low, minutes, pages, n)
  else if jr_is(file, n, next, 125) then @(found, id_high, id_low, minutes, pages, next + 1)
  else if jr_is(file, n, next, 44) then _reading_members(file, n, next + 1, key, found, id_high, id_low, minutes, pages)
  else let
    val @(key_found, key_len, value_at) = jr_key(file, n, next, key, 16)
  in
    if ~key_found then @(false, id_high, id_low, minutes, pages, value_at)
    else if jr_key_is(key, key_len, "id") then let
      val @(id_found, high, low, after) = jr_id(file, n, value_at)
    in _reading_members(file, n, after, key, id_found, high, low, minutes, pages) end
    else if jr_key_is(key, key_len, "readMinutes") then let
      val @(read, value, after) = jr_int(file, n, value_at)
    in
      if read then _reading_members(file, n, after, key, found, id_high, id_low, value, pages)
      else _reading_members(file, n, jr_skip(file, n, value_at), key, found, id_high, id_low, minutes, pages)
    end
    else if jr_key_is(key, key_len, "readPages") then let
      val @(read, value, after) = jr_int(file, n, value_at)
    in
      if read then _reading_members(file, n, after, key, found, id_high, id_low, minutes, value)
      else _reading_members(file, n, jr_skip(file, n, value_at), key, found, id_high, id_low, minutes, pages)
    end
    else _reading_members(file, n, jr_skip(file, n, value_at), key, found, id_high, id_low, minutes, pages)
  end
end

(* A device's books' entries from position, to the array's closing
   bracket: each one's time added to the library book's read elsewhere *)
fun _reading_at {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16)): void = let
  val next = jr_ws(file, n, position)
in
  if next >= n then ()
  else if jr_is(file, n, next, 93) then ()
  else if jr_is(file, n, next, 44) then _reading_at(file, n, next + 1, key)
  else if ~jr_is(file, n, next, 123) then ()
  else let
    val @(found, id_high, id_low, minutes, pages, stop) = _reading_members(file, n, next + 1, key, false, 0, 0, 0, 0)
    val book_index = (if found then lib_find(id_high, id_low) else ~1): [index:int | index >= ~1] int index
    val () = (if book_index >= 0 then (if minutes > 0 then lib_elsewhere_add(book_index, minutes, pages) else ()) else ())
  in _reading_at(file, n, stop, key) end
end

(* Another device's entry's members from position: its reading log and
   its books' time, added to what was read elsewhere *)
fun _device_members {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (file: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16)): void = let
  val next = jr_ws(file, n, position)
in
  if next >= n then ()
  else if jr_is(file, n, next, 125) then ()
  else if jr_is(file, n, next, 44) then _device_members(file, n, next + 1, key)
  else let
    val @(found, key_len, value_at) = jr_key(file, n, next, key, 16)
  in
    if ~found then ()
    else if value_at >= n then ()
    else let
      val () = (if jr_key_is(key, key_len, "readingLog") then (if jr_is(file, n, value_at, 91) then _days_at(file, n, value_at + 1) else ())
        else if jr_key_is(key, key_len, "books") then (if jr_is(file, n, value_at, 91) then _reading_at(file, n, value_at + 1, key) else ())
        else ())
    in _device_members(file, n, jr_skip(file, n, value_at), key) end
  end
end

fun _devices_take {l,key_loc:agz}{owner:addr}{n:nat}{count:nat} .<count>. (file: !$A.arrx(byte, l, n, owner), n: int n, devices: !spans(n, count), device: Int, key: !$A.arr(byte, key_loc, 16)): void =
  case+ devices of
  | SpansNil() => ()
  | SpansCons(number, _, start, _, rest) => let
      val () = (if number <> device then _device_members(file, n, start + 1, key) else ())
    in _devices_take(file, n, rest, device, key) end

(* The place numbers give (another device's, dated stamp) offered for
   the open book when asked, unless it is its own place (own's) *)
fn _offer_other {own_loc,numbers_loc:agz}
  (own: !$A.arr(Int, own_loc, BOOK_NUMBERS), numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), asked: bool, stamp: Int): void =
  if ~asked then ()
  else if backup_numbers_place_same(own, numbers) then ()
  else let
    val @(chapter, page, anchor) = backup_numbers_place(numbers)
  in _offer(chapter, page, anchor, stamp) end

(* The file's numbers of the book id_high, id_low, taken: a library
   book's merged with its own; one this device does not have, kept for
   when it is imported. The file's place is taken when it is the later
   change (#302), unless the reader declined it here; for the open book
   it is offered instead, and only when another device read it: this
   device's own place, written to the file, is never offered back *)
fn _book_take {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), id_high: Int, id_low: Int): void = let
  val book_index = lib_find(id_high, id_low)
in
  if book_index < 0 then backup_orphan_put(id_high, id_low, numbers)
  else (case+ lib_nums(book_index) of
    | ~$R.none() => ()
    | ~$R.some(nums) => let
        val own = backup_numbers_new()
        val () = backup_numbers_of(nums, own)
        val is_open = (nums.key = !_open_key)
        val @(stamp, device) = backup_numbers_place_change(numbers)
        val wanted = (if backup_numbers_place_later(own, numbers) then stamp > nums.place_declined else false): bool
        val elsewhere = (if device > 0 then device <> !_device_now else false): bool
        val () = _offer_other(own, numbers, (if is_open then (if wanted then elsewhere else false) else false), stamp)
        val () = backup_numbers_merge(own, numbers, (if is_open then true else ~wanted))
        val () = backup_numbers_reading(own, ~1, ~1)
        val () = backup_apply_numbers(book_index, own, true)
      in $A.free<Int>(own) end)
end

(* The book at file[start] read into numbers and taken *)
fn _book_read_take {l,numbers_loc,map_loc:agz}{owner:addr}{n:nat}{start:nat | start < n}
  (file: !$A.arrx(byte, l, n, owner), n: int n, start: int start, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS),
   map: !$A.arr(Int, map_loc, MAP_SIZE), id_high: Int, id_low: Int): void = let
  val @(closed, _, _, _) = backup_book_members(file, n, start, numbers)
  val () = backup_map_collections(numbers, map)
  (* each device's time is read from its entry *)
  val () = backup_numbers_reading(numbers, ~1, ~1)
in
  if closed then let
    val () = backup_numbers_seen(numbers)
  in _book_take(numbers, id_high, id_low) end
  else ()
end

(* The file's books' numbers, taken: a library book's merged with its
   own (the open book's place offered, not taken); one this device does
   not have, kept for when it is imported *)
fun _books_take {l,map_loc:agz}{owner:addr}{n:nat}{count:nat} .<count>. (file: !$A.arrx(byte, l, n, owner), n: int n, books: !spans(n, count), map: !$A.arr(Int, map_loc, MAP_SIZE)): void =
  case+ books of
  | SpansNil() => ()
  | SpansCons(id_high, id_low, start, _, rest) => let
      val numbers = backup_numbers_new()
      val () = _book_read_take(file, n, start, numbers, map, id_high, id_low)
      val () = $A.free<Int>(numbers)
    in _books_take(file, n, rest, map) end

fun _spans_count {n:int}{count:nat} .<count>. (spans: !spans(n, count)): int count =
  case+ spans of
  | SpansNil() => 0
  | SpansCons(_, _, _, _, rest) => 1 + _spans_count(rest)

(* The k-th of spans: its id, and where it starts (-1 none) *)
fun _span_at {n:nat}{count:nat} .<count>. (spans: !spans(n, count), k: int): [start:int | ~1 <= start; start < n] @(Int, Int, int start) =
  case+ spans of
  | SpansNil() => @(0, 0, ~1)
  | SpansCons(id_high, id_low, start, _, rest) => if k <= 0 then @(id_high, id_low, start) else _span_at(rest, k - 1)

(* What a read of a stored record found, as its content: none when
   there is none, or it could not be read (the callers tell which) *)
fn _content_of (stored: stored_content): content_bytes =
  case+ stored of
  | ~StoredContent(owner, piece, size) => ContentBytes(owner, piece, size)
  | ~NoStoredContent() => NoContentBytes()
  | ~ContentUnreadable() => NoContentBytes()

(* A stored record's content, let go of *)
fn _content_free (content: content_bytes): void =
  case+ content of
  | ~NoContentBytes() => ()
  | ~ContentBytes(owner, stored, _) => piece_free(owner, stored)

(* The file's books' annotations from the k-th on, each merged with
   those stored here (read from storage) *)
fun _annotations_take {left:nat} .<left>. (k: int, left: int left): void =
  case+ _held_swap(_written, NoHeld()) of
  | ~NoHeld() => _done()
  | ~Held(owner, file, n, names_at, books, devices) => let
      val @(id_high, id_low, start) = _span_at(books, k)
      val () = _held_free(_held_swap(_written, Held(owner, file, n, names_at, books, devices)))
    in
      if start < 0 then _done()
      else if left <= 0 then _done()
      else let
        val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(97, id_high, id_low))
        val pending = $IDB.idb_get(key_bytes, 15)
        val () = release_bytes(key_frozen, key_bytes)
      in
        $P.finish<$IDB.lookup>(pending, llam(found) => let
          val stored = lookup_content(found)
          val readable = (case+ stored of ContentUnreadable() => false | _ => true): bool
          val own = _content_of(stored)
          (* a record that could not be read is left as it is *)
          val () = (if ~readable then _content_free(own)
            else (case+ _held_swap(_written, NoHeld()) of
              | ~NoHeld() => _content_free(own)
              | ~Held(file_owner, bytes, size, names_at, books, devices) => let
                  val @(_, _, book_start) = _span_at(books, k)
                  val () = (if book_start >= 0 then let
                      val numbers = backup_numbers_new()
                      val @(_, annotations_at, deleted_at, _) = backup_book_members(bytes, size, book_start, numbers)
                      val () = $A.free<Int>(numbers)
                    in annot_sync_store(own, bytes, size, annotations_at, deleted_at, id_high, id_low) end
                    else _content_free(own))
                in _held_free(_held_swap(_written, Held(file_owner, bytes, size, names_at, books, devices))) end))
        in _annotations_take(k + 1, left - 1) end)
      end
    end

(* The library's numbers of the file's collections (its array at
   names_at, -1 none), found by name or made, in map *)
fn _names_map {l,map_loc:agz}{owner:addr}{n:nat}{names_at:int | ~1 <= names_at; names_at <= n}
  (file: !$A.arrx(byte, l, n, owner), n: int n, names_at: int names_at, map: !$A.arr(Int, map_loc, MAP_SIZE)): void =
  if names_at < 0 then ()
  else let val @(_, _) = backup_collections_map(file, n, names_at, map) in end

(* The file written, taken here: the collections it names, the time
   read on the other devices, the books' numbers, then their
   annotations *)
fn _take (): void =
  case+ _held_swap(_written, NoHeld()) of
  | ~NoHeld() => _done()
  | ~Held(owner, file, n, names_at, books, devices) => let
      val map = backup_map_new()
      val () = _names_map(file, n, names_at, map)
      (* the time read on the other devices, summed anew *)
      val () = stats_elsewhere_clear()
      val () = lib_elsewhere_clear()
      val key = $A.alloc<byte>(16)
      val () = _devices_take(file, n, devices, !_device_now, key)
      val () = $A.free<byte>(key)
      val () = stats_elsewhere_keep()
      val () = _books_take(file, n, books, map)
      val () = $A.free<Int>(map)
      val () = lib_save()
      val () = lib_render()
      val count = _spans_count(books)
      val () = _held_free(_held_swap(_written, Held(owner, file, n, names_at, books, devices)))
    in _annotations_take(0, count) end

(* ============================================================
   The merge, written
   ============================================================ *)

(* Writes the file made (held in _written) to the store: taken here
   once it is written; on a conflict (another device wrote it since it
   was read), read and merged again, up to TRIES times *)
fn _write (): void =
  case+ _held_swap(_written, NoHeld()) of
  | ~NoHeld() => _fail(NoMemory(), 0)
  | ~Held(owner, file, n, names_at, books, devices) => let
      val @(file_frozen, file_bytes) = $A.freeze<byte>(file)
      val () = $P.finish<write_answer>(store_write(file_bytes, n), llam(answer) =>
        case+ answer of
        | ~Written() => _take()
        | ~WriteConflict() => let
            val () = _held_free(_held_swap(_written, NoHeld()))
            val () = !_tries := !_tries + 1
          in if !_tries >= TRIES then _fail(KeptChanging(), 412) else _round_settle(RoundConflict()) end
        | ~WriteFailed(kind, status) => _fail(kind, status))
      val () = $A.drop<byte>(file_frozen, file_bytes)
      val file = $A.thaw<byte>(file_frozen)
    in _held_free(_held_swap(_written, Held(owner, file, n, names_at, books, devices))) end

(* This device's number when it has none: the minute, or the next one
   free in the file *)
fun _free_number {n:int}{count:nat}{left:nat} .<left>. (devices: !spans(n, count), number: Int, left: int left): Int =
  if left <= 0 then number
  else if _has_device(devices, number) then _free_number(devices, number + 1, left - 1)
  else number

(* The reading log's days from entries, as [day, minutes] pairs, each
   after a comma but the first *)
fun _days_json {l:agz}{owner:addr}{n:nat}{count:nat}{position:nat | position + 26 * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, entries: !days(count), first: bool)
  : [stop:nat | stop <= position + 26 * count] int stop =
  case+ entries of
  | DaysNil() => position
  | DaysCons(day, minutes, rest) => let
      val opened = (if first then jw_lit(out, position, "[") else jw_lit(out, position, ",["))
        : [after:int | position < after; after <= position + 2] int after
      val after_day = jw_int(out, opened, day)
      val after_comma = jw_lit(out, after_day, ",")
      val after_minutes = jw_int(out, after_comma, minutes)
      val closed = jw_lit(out, after_minutes, "]")
    in _days_json(out, closed, rest, false) end

(* Each library book read here from book_index on, as {"id",
   "readMinutes", "readPages"}, after a comma but the first *)
fun _reading_json {l:agz}{owner:addr}{n:nat}{book_index,count:nat | book_index <= count}{position:nat | position + 80 * (count - book_index) <= n} .<count - book_index>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, book_index: int book_index, count: int count, first: bool)
  : [stop:nat | stop <= position + 80 * (count - book_index)] int stop =
  if book_index >= count then position
  else (case+ lib_nums(book_index) of
    | ~$R.none() => _reading_json(out, position, book_index + 1, count, first)
    | ~$R.some(nums) =>
      if nums.minutes_read <= 0 then _reading_json(out, position, book_index + 1, count, first)
      else let
        val opened = (if first then jw_lit(out, position, "{\"id\":") else jw_lit(out, position, ",{\"id\":"))
          : [after:int | position < after; after <= position + 7] int after
        val after_id = jw_id(out, opened, nums.id_high, nums.id_low)
        val minutes_at = jw_lit(out, after_id, ",\"readMinutes\":")
        val after_minutes = jw_int(out, minutes_at, nums.minutes_read)
        val pages_at = jw_lit(out, after_minutes, ",\"readPages\":")
        val after_pages = jw_int(out, pages_at, nums.pages_read)
        val closed = jw_lit(out, after_pages, "}")
      in _reading_json(out, closed, book_index + 1, count, false) end)

(* This device's entry: its number, its reading log, and each book's
   time read here *)
fn _device_chunk (device: Int): jchunk = let
  val count = lib_count()
in
  case+ piece_new(64 + 26 * 400 + 80 * count) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => let
      val next = jw_lit(out, 0, "{\"device\":")
      val next = jw_int(out, next, device)
      val next = jw_lit(out, next, ",\"readingLog\":[")
      val @(entries, _) = stats_days()
      val next = _days_json(out, next, entries, true)
      val () = stats_days_free(entries)
      val next = jw_lit(out, next, "],\"books\":[")
      val next = _reading_json(out, next, 0, count, true)
      val next = jw_lit(out, next, "]}")
    in JChunk(owner, out, next) end
end

(* The file's other devices' entries, each after a comma *)
fun _other_devices {l:agz}{owner:addr}{n:nat | n <= 268435456}{count:nat} .<count>. (file: !$A.arrx(byte, l, n, owner), devices: !spans(n, count), device: Int): void =
  case+ devices of
  | SpansNil() => ()
  | SpansCons(number, _, start, stop, rest) => let
      val () = (if number <> device then let
          val () = _push(_text_chunk(","))
        in _push(jchunk_copy(file, start, stop)) end else ())
    in _other_devices(file, rest, device) end

(* The names of the file's collections' array at names_at, as it has
   them *)
fn _names_push {l:agz}{owner:addr}{n:nat}{names_at:int | ~1 <= names_at; names_at <= n}
  (file: !$A.arrx(byte, l, n, owner), n: int n, names_at: int names_at): void =
  if names_at < 0 then ()
  else if names_at >= n then ()
  else let
    val names_end = jr_skip(file, n, names_at)
  in
    if names_end - 1 <= names_at + 1 then ()
    else if names_end - names_at > SYNC_MAX_BYTES then ()
    else _push(jchunk_copy(file, names_at + 1, names_end - 1))
  end

(* The head of the file: what it is, its collections (the file's, then
   this device's it does not have), its devices (this one's entry, then
   the others'), and the books' opening bracket *)
fn _head (): void = let
  val () = _push(_text_chunk("{\"quire\":1,\"sync\":1,\"collections\":["))
in
  case+ _held_swap(_remote, NoHeld()) of
  | ~NoHeld() => _push(JNone())
  | ~Held(owner, file, n, names_at, books, devices) => let
      (* the file's collections, as its array has them *)
      val () = _names_push(file, n, names_at)
      val file_count = _names_count(file, n, names_at)
      (* this device's that it does not have *)
      val () = (case+ piece_new(2100) of
        | ~NoPiece() => _push(JNone())
        | ~Piece(piece_owner, out) => let
            val @(stop, numbering) = _numbering_make(out, 0, file, n, names_at, file_count, 0, 0, NumberingNil(), file_count = 0)
            val () = _numbering_put(numbering)
          in
            if stop > 0 then _push(JChunk(piece_owner, out, stop)) else piece_free(piece_owner, out)
          end)
      (* the devices: this one's number (the first sync's minute, or
         the next free, when it has none) *)
      val device = (if !_device > 0 then !_device else _free_number(devices, $TM.epoch_minutes(), 1000)): Int
      val () = !_device_now := device
      val () = _push(_text_chunk("],\"devices\":["))
      val () = _push(_device_chunk(device))
      val () = _other_devices(file, devices, device)
      val () = _push(_text_chunk("],\"books\":["))
    in _held_free(_held_swap(_remote, Held(owner, file, n, names_at, books, devices))) end
end

(* The numbers of the book at file[start] (other's) merged into
   numbers *)
fn _merge_other {l,numbers_loc,other_loc:agz}{owner:addr}{n:nat}{start:nat | start < n}
  (file: !$A.arrx(byte, l, n, owner), n: int n, start: int start,
   numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), other: !$A.arr(Int, other_loc, BOOK_NUMBERS)): void = let
  val @(closed, _, _, _) = backup_book_members(file, n, start, other)
in if closed then backup_numbers_merge(numbers, other, false) else () end

(* The numbers of the book at file[start] (none for -1) merged into
   numbers *)
fn _merge_from {l,numbers_loc:agz}{owner:addr}{n:nat}{start:int | ~1 <= start; start < n}
  (file: !$A.arrx(byte, l, n, owner), n: int n, start: int start, numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS)): void =
  if start < 0 then ()
  else let
    val other = backup_numbers_new()
    val () = _merge_other(file, n, start, numbers, other)
  in $A.free<Int>(other) end

(* The file's copy of the book id_high, id_low's numbers merged into
   numbers (this device's), when the file has it *)
fn _merge_remote {numbers_loc:agz} (numbers: !$A.arr(Int, numbers_loc, BOOK_NUMBERS), id_high: Int, id_low: Int): void =
  case+ _held_swap(_remote, NoHeld()) of
  | ~NoHeld() => ()
  | ~Held(owner, file, n, names_at, books, devices) => let
      val start = _book_start(books, id_high, id_low)
      val () = _merge_from(file, n, start, numbers)
    in _held_free(_held_swap(_remote, Held(owner, file, n, names_at, books, devices))) end

(* The annotations of book id_high, id_low: those stored here (own,
   its "a" key's content) merged with the file's *)
fn _annotations_chunk (own: content_bytes, id_high: Int, id_low: Int): jchunk =
  case+ _held_swap(_remote, NoHeld()) of
  | ~NoHeld() => let val () = _content_free(own) in JNone() end
  | ~Held(owner, file, n, names_at, books, devices) => let
      val start = _book_start(books, id_high, id_low)
      val chunk = (if start >= 0 then let
          val other = backup_numbers_new()
          val @(_, annotations_at, deleted_at, _) = backup_book_members(file, n, start, other)
          val () = $A.free<Int>(other)
        in annot_sync_json(own, file, n, annotations_at, deleted_at) end
        else annot_sync_json(own, file, n, ~1, ~1)): jchunk
      val () = _held_free(_held_swap(_remote, Held(owner, file, n, names_at, books, devices)))
    in chunk end

(* The file's books this device does not have, each as the file has
   it, after a comma but the first *)
fun _remote_books {l:agz}{owner:addr}{n:nat | n <= 268435456}{count:nat} .<count>. (file: !$A.arrx(byte, l, n, owner), books: !spans(n, count), first: bool): void =
  case+ books of
  | SpansNil() => ()
  | SpansCons(id_high, id_low, start, stop, rest) =>
    if lib_find(id_high, id_low) >= 0 then _remote_books(file, rest, first)
    else let
      val () = (if first then () else _push(_text_chunk(",")))
      val () = _push(jchunk_copy(file, start, stop))
    in _remote_books(file, rest, false) end

(* The file's end: its books this device does not have, then the
   closing brackets; then it is written *)
fn _tail (): void = let
  val written = !_books_written
  val () = (if written then _push(_text_chunk("}")) else ())
  val () = (case+ _held_swap(_remote, NoHeld()) of
    | ~NoHeld() => ()
    | ~Held(owner, file, n, names_at, books, devices) => let
        val in_order = _reversed(books, SpansNil())
        val () = _remote_books(file, in_order, ~written)
        val () = _spans_free(in_order)
      in _held_free(Held(owner, file, n, names_at, books, devices)) end)
  val () = _push(_text_chunk("]}"))
in
  case+ jfile_join(_out_take()) of
  | ~JNoWhole() => _fail(NoMemory(), 0)
  | ~JWhole(owner, file, n) =>
    (case+ _hold(owner, file, n) of
     | ~NoHeld() => _fail(NoMemory(), 0)
     | ~Held(file_owner, bytes, size, names_at, books, devices) => let
         val () = _held_free(_held_swap(_written, Held(file_owner, bytes, size, names_at, books, devices)))
       in _write() end)
end

(* This device's books from book_index on, each merged with the file's
   copy: its numbers, then its annotations (read from storage) *)
fun _books {book_index,count:nat | book_index <= count} .<count - book_index>. (book_index: int book_index, count: int count): void =
  if book_index >= count then _tail()
  else (case+ lib_nums(book_index) of
    | ~$R.none() => _books(book_index + 1, count)
    | ~$R.some(nums) => let
        val id_high = nums.id_high
        val id_low = nums.id_low
        val numbers = backup_numbers_new()
        val () = backup_numbers_of(nums, numbers)
        (* its collections as the file numbers them *)
        val () = backup_numbers_collections(numbers, g1ofg0(_to_file(nums.collections, 0, 0)))
        (* its place this device's, unless the file's is the later *)
        val () = backup_numbers_place_device(numbers, !_device_now)
        val () = _merge_remote(numbers, id_high, id_low)
        (* its reading here and elsewhere, for a reader of the file (sync
           reads each device's from its entry) *)
        val () = backup_numbers_reading(numbers, nums.minutes_read + nums.minutes_elsewhere, nums.pages_read + nums.pages_elsewhere)
        val () = _push(backup_book_chunk(book_index, numbers, ~(!_books_written)))
        val () = !_books_written := true
        val () = $A.free<Int>(numbers)
        val @(key_frozen, key_bytes) = $A.freeze<byte>(lib_key(97, id_high, id_low))
        val pending = $IDB.idb_get(key_bytes, 15)
        val () = release_bytes(key_frozen, key_bytes)
      in
        $P.finish<$IDB.lookup>(pending, llam(found) => let
          (* a record that could not be read is not taken for none: the
             file's annotations go back as they are *)
          val own = _content_of(lookup_content(found))
          val () = _push(_annotations_chunk(own, id_high, id_low))
        in _books(book_index + 1, count) end)
      end)

(* The merge of the file read (held in _remote) and this device's,
   made *)
fn _merge (): void = let
  val () = _out_put(jfile_new{SYNC_MAX_BYTES}())
  val () = !_books_written := false
  val () = _head()
in _books(0, lib_count()) end

(* ============================================================
   The file, read
   ============================================================ *)

(* The file read in a piece, held as _remote, merged *)
fn _merge_held (file: held): void =
  case+ file of
  | ~NoHeld() => _fail(NoMemory(), 0)
  | ~Held(owner, bytes, n, names_at, books, devices) => let
      val () = _held_free(_held_swap(_remote, Held(owner, bytes, n, names_at, books, devices)))
    in _merge() end

(* Reads the file from the store, and merges it *)
fn _read (): void = $P.finish<read_answer>(store_read(), llam(answer) =>
  case+ answer of
  | ~ReadNothing() => _merge_held(_empty())
  | ~ReadFailed(kind, status) => _fail(kind, status)
  | ~ReadFile(owner, file, size) =>
    (case+ _hold(owner, file, size) of
     | ~NoHeld() => _fail(Damaged(), 0)
     | ~Held(file_owner, bytes, n, names_at, books, devices) => _merge_held(Held(file_owner, bytes, n, names_at, books, devices))))

(* A sync begun: under way, with no try made yet *)
fn _run_begin (): void = let
  val () = _refusal_forget()
  val () = !_busy := true
  val () = !_tries := 0
  val () = !_last_result := Syncing()
in _status_show() end

(* The most rounds one sync_run makes: each sync's tries, for each of
   the syncs asked for while the one before was under way, one after
   another. A sync asked for after them is made at the next one asked
   for (it is kept asked for, in _again) *)
#define ROUNDS_MOST 300

(* The rounds of a sync from now, left more at most: the file read and
   merged again after a conflict; another sync made when one was asked
   for meanwhile *)
fun _rounds {left:nat} .<left>. (left: int left): void = let
  val @(ended, resolver) = $P.create<round_end>()
  val () = (case+ _round_swap(Round(resolver)) of
    | ~NoRound() => ()
    | ~Round(previous) => $P.resolve<round_end>(previous, RoundEnded()))
  val () = _read()
in
  $P.finish<round_end>(ended, llam(how) =>
    if left <= 0 then (case+ how of
      | RoundConflict() => _fail(KeptChanging(), 412)
      | RoundEnded() => ())
    else (case+ how of
      | RoundConflict() => _rounds(left - 1)
      | RoundEnded() =>
        if ~(!_again) then ()
        else let
          val () = !_again := false
        in
          if ~_syncing() then ()
          else let val () = _run_begin() in _rounds(left - 1) end
        end))
end

(* Whether sync is paused for the reader: in a browser, the Google store
   with no token, its last sync already paused for one (SignInAgain,
   which says Sync now signs in). Another try without a token would only
   say so again, and a relaunch, which holds no more token than before
   it, changes nothing *)
fn _paused (): bool =
  if ~_is_android() then false
  else if _token_held() then false
  (* in the app a token is asked for with nothing shown, so each sync
     point tries: a grant given back since (another Sync now, or Google's
     own settings) ends the pause at once *)
  else if _authorize_present() then false
  else case+ !_last_result of
    | SignInAgain() => true
    | NotSyncedYet() => false | Synced() => false | Unreachable() => false | WrongCredentials() => false
    | FolderNotFound() => false | KeptChanging() => false | ServerError() => false | TooLarge() => false
    | Damaged() => false | NoMemory() => false | Blocked() => false | Syncing() => false | NoAddress() => false
    | NoGoogleAccount() => false | NotSetUp() => false | GoogleRefused() => false | SignInCanceled() => false
    | DropboxSignInAgain() => false | DropboxNotSetUp() => false | DropboxSignInRefused() => false
    | DropboxSignInCanceled() => false | FastmailRefused() => false
    | GoogleSignInFailed() => false | GoogleAccountNeeded() => false | GoogleUnreachable() => false
    | GoogleConsentShowing() => false | GoogleUnexpected() => false
    | GoogleNoAnswer() => false | GoogleAsking() => false

(* Syncs, when sync is on: at once, or once the sync under way ends; not
   while it is paused for a sign-in *)
#pub fn sync_run (): void
implement sync_run () =
  if ~_syncing() then ()
  else if !_busy then !_again := true
  else if _paused() then ()
  else let
    val () = _run_begin()
  in _rounds(ROUNDS_MOST) end

(* Reads the state and the store kept, then syncs (when sync is on):
   once the library is read *)
#pub fn sync_start (): void
(* A book opened in the reader (its library key): sync, to bring its
   place and annotations from the other devices *)
#pub fn sync_book_opened (key: Int): void
implement sync_book_opened (key) = let
  val () = !_open_key := key
in sync_run() end

(* Back in the library: no book's place is offered *)
#pub fn sync_book_closed (): void
implement sync_book_closed () = let
  val () = !_open_key := 0
  val () = !_further_chapter := ~1
in ui_show("sync-offer", false) end

(* The place offered, taken (the offer's button): its chapter (-1 when
   none is offered), page and anchor. Going there is a move of the
   reader's, the latest *)
#pub fn sync_further_take (): @(Int, Int, Int)
implement sync_further_take () = let
  val chapter = !_further_chapter
  val () = !_further_chapter := ~1
  val () = ui_show("sync-offer", false)
in @(chapter, !_further_page, !_further_anchor) end

(* The offer dismissed: the place stays, and the place offered is
   declined, so it is neither offered nor taken again (a place the
   other device reads later is) *)
#pub fn sync_further_dismiss (): void
implement sync_further_dismiss () = let
  val () = (if !_further_chapter >= 0 then lib_place_decline(!_open_key, !_further_stamp) else ())
  val () = !_further_chapter := ~1
in ui_show("sync-offer", false) end

(* The screen's fields, empty: the folder's URL, the user name and the
   password (made again to be emptied) *)
fn _fields_make (): void = let
  val () = ui_clear("sync-fields")
  val () = ui_form_field("sync-fields", "sync-url-label", "sync-url", FormUrl, "mname", "Folder URL", "https://example.com/dav/quire/")
  val () = ui_form_field("sync-fields", "sync-user-label", "sync-user", FormUser, "mname", "User name", "you")
in ui_form_field("sync-fields", "sync-password-label", "sync-password", FormPassword, "mname", "Password", "An app password") end

(* Fastmail's fields, empty: its address and an app password (made
   again to be emptied) *)
fn _fastmail_fields_make (): void = let
  val () = ui_clear("fastmail-fields")
  val () = ui_form_field("fastmail-fields", "fastmail-user-label", "fastmail-user", FormUser, "mname", "Fastmail address", "you@fastmail.com")
in ui_form_field("fastmail-fields", "fastmail-password-label", "fastmail-password", FormPassword, "mname", "Fastmail app password", "An app password") end

(* A service's row: its name, a button that opens its step, and its
   state beside it *)
fn _row_make {row_len,button_len,state_len,label_len:pos | row_len < 256; button_len < 256; state_len < 256; label_len < 256}
  (row: string row_len, button: string button_len, state: string state_len, label: string label_len): void = let
  val () = ui_el("sync-services", row, TDiv, "srow")
  val () = ui_text_btn(row, button, "btn rowbtn chev", label)
  val () = ui_add(row, state, TSpan)
in ui_show(state, false) end

(* The sync screen (#331, from Material's settings and Android's own
   Backup and Add account screens, written on the issue): a status card
   at its top (where sync is kept, how the last sync went or what it
   needs, and Sync now and Turn off while it is on), then the services
   that can be used here, a row each with its name and, for the one
   chosen, its state, then a line on what sync keeps; and Done. A row
   opens its service's own sign-in step in the screen's place (LSyncStep,
   whose element comes first, so the stylesheet hides what follows it
   while it is shown): what the service does and asks for, its fields,
   its own button, and Cancel. Also the offer of the place another
   device read in the open book *)
#pub fn sync_screen_make (): void
implement sync_screen_make () = let
  val () = ui_el("bats-root", "sync-screen", TDiv, "info")
  val () = ui_labelled("sync-screen", NDialog, "sync-title")
  val () = ui_el("sync-screen", "sync-box", TDiv, "info-in")
  (* the sign-in step, one service's part of it shown at a time *)
  val () = ui_el("sync-box", "sync-step", TDiv, "sstep")
  val () = ui_el("sync-step", "sync-step-title", TDiv, "mtitle")
  (* Google Drive: the Google account on the phone in the app, Google's
     window in a browser *)
  val () = ui_el("sync-step", "sync-step-google", TDiv, "sfields")
  val () = ui_el("sync-step-google", "sync-android-about", TDiv, "stext")
  val () = ui_el("sync-step", "sync-step-dropbox", TDiv, "sfields")
  val () = ui_el("sync-step-dropbox", "sync-dropbox-about", TDiv, "stext")
  (* Fastmail, in the app only: its files over WebDAV, with its address
     and an app password, which Fastmail's settings make (the link and
     the steps). Fastmail's WebDAV sends no CORS headers (checked
     2026-10-01 and 2026-10-04: its preflight answers 401 with none), so
     a browser page can't reach it, and a browser lists no Fastmail; the
     app's requests are native, and can *)
  val () = ui_el("sync-step", "fastmail-form", TDiv, "sfields")
  val () = ui_el("fastmail-form", "sync-fastmail-about", TDiv, "stext")
  val () = ui_text_long("sync-fastmail-about", "Syncs through Fastmail's Files, in a folder named quire, with your Fastmail address and an app password.")
  val () = ui_el("fastmail-form", "fastmail-fields", TDiv, "sfields")
  val () = _fastmail_fields_make()
  val () = ui_el("fastmail-form", "fastmail-steps", TDiv, "stext")
  val () = ui_text_long("fastmail-steps", "Make an app password in Fastmail's Settings, under Privacy & Security: choose Manage app passwords, give the new one access to Files (WebDAV), then copy it here.")
  val () = ui_link_out_https("fastmail-form", "fastmail-app-password", "btn linkout", "Make an app password", "app.fastmail.com/settings/security")
  (* Nextcloud: its address, then its own sign-in page (Login Flow v2),
     which gives an app password *)
  val () = ui_el("sync-step", "nextcloud-box", TDiv, "sfields")
  val () = ui_el("nextcloud-box", "nextcloud-about", TDiv, "stext")
  val () = ui_text_long("nextcloud-about", "Your Nextcloud's address. Its own sign-in page then gives Quire an app password.")
  val () = ui_form_field("nextcloud-box", "nextcloud-server-label", "nextcloud-server", FormUrl, "mname", "Nextcloud server", "https://cloud.example.com")
  val () = ui_link_out("nextcloud-box", "nextcloud-page", "btn linkout", "Open Nextcloud's sign-in page")
  val () = ui_show("nextcloud-page", false)
  (* any WebDAV folder *)
  val () = ui_el("sync-step", "sync-step-webdav", TDiv, "sfields")
  val () = ui_el("sync-step-webdav", "sync-webdav-about", TDiv, "stext")
  val () = ui_text("sync-webdav-about", "Any WebDAV folder (ownCloud, a NAS): its address, a user name and an app password.")
  val () = ui_el("sync-step-webdav", "sync-fields", TDiv, "sfields")
  val () = _fields_make()
  (* what the step says of itself: a field left empty, a sign-in's
     progress *)
  val () = ui_el("sync-step", "sync-step-status", TDiv, "sstatus")
  val () = ui_role("sync-step-status", RStatus)
  (* Cancel, then the service's own button (Material's dialog: the
     confirming action last, at the end) *)
  val () = ui_el("sync-step", "sync-step-buttons", TDiv, "mbtns")
  val () = ui_text_btn("sync-step-buttons", "sync-step-cancel", "btn", "Cancel")
  val () = ui_text_btn("sync-step-buttons", "sync-android", "btn btn-p", sign_in_label(ServiceGoogle()))
  val () = ui_text_btn("sync-step-buttons", "sync-google", "btn btn-p", sign_in_label(ServiceGoogle()))
  val () = ui_text_btn("sync-step-buttons", "sync-dropbox", "btn btn-p", sign_in_label(ServiceDropbox()))
  val () = ui_text_btn("sync-step-buttons", "sync-fastmail", "btn btn-p", sign_in_label(ServiceFastmail()))
  val () = ui_text_btn("sync-step-buttons", "nextcloud-sign-in", "btn btn-p", sign_in_label(ServiceNextcloud()))
  val () = ui_text_btn("sync-step-buttons", "sync-webdav", "btn btn-p", sign_in_label(ServiceWebDav()))
  val () = ui_show("sync-step", false)
  (* the screen *)
  val () = ui_el("sync-box", "sync-title", TDiv, "mtitle")
  val () = ui_text("sync-title", "Sync")
  (* its status: where, how it went, and the actions while it is on *)
  val () = ui_el("sync-box", "sync-card", TDiv, "scard")
  val () = ui_el("sync-card", "sync-where", TDiv, "swhere")
  val () = ui_show("sync-where", false)
  val () = ui_el("sync-card", "sync-status", TDiv, "sstatus")
  val () = ui_role("sync-status", RStatus)
  val () = ui_el("sync-card", "sync-buttons", TDiv, "mbtns")
  val () = ui_text_btn("sync-buttons", "sync-off", "btn", "Turn off")
  val () = ui_text_btn("sync-buttons", "sync-now", "btn btn-p", "Sync now")
  val () = ui_text_btn("sync-buttons", "sync-stop", "btn btn-p", "Stop waiting")
  val () = _actions_show(false)
  (* the services, each shown only where it can be used *)
  val () = ui_el("sync-box", "sync-services-title", TDiv, "a11yg")
  val () = ui_text("sync-services-title", "Sync with")
  val () = ui_el("sync-box", "sync-services", TDiv, "sgroup")
  val () = ui_named("sync-services", NGroup, "Sync with")
  val () = _row_make("sync-google-row", "sync-row-google", "sync-google-state", service_title(ServiceGoogle()))
  val () = _row_make("sync-dropbox-row", "sync-row-dropbox", "sync-dropbox-state", service_title(ServiceDropbox()))
  val () = _row_make("sync-fastmail-row", "sync-row-fastmail", "sync-fastmail-state", service_title(ServiceFastmail()))
  val () = _row_make("sync-nextcloud-row", "sync-row-nextcloud", "sync-nextcloud-state", service_title(ServiceNextcloud()))
  val () = _row_make("sync-webdav-row", "sync-row-webdav", "sync-webdav-state", service_title(ServiceWebDav()))
  val () = ui_show("sync-google-row", false)
  val () = ui_show("sync-dropbox-row", false)
  val () = ui_show("sync-fastmail-row", false)
  (* what sync keeps, in a line (the services' own steps say the rest) *)
  val () = ui_el("sync-box", "sync-about", TDiv, "snote")
  val () = ui_text_long("sync-about", "Keeps places, shelves, collections, highlights, notes and reading time the same on your devices. Books' files are not synced, and sign-ins stay on this device.")
  val () = ui_el("sync-box", "sync-done-row", TDiv, "mbtns")
  val () = ui_text_btn("sync-done-row", "sync-done", "btn", "Done")
  val () = ui_show("sync-screen", false)
  (* the offer of the place another device read: a row of the reader's
     bottom bar, over its progress, so it covers no text the bars do
     not (#302); it is there whenever the bars are, until it is
     answered or the book closed *)
  val () = ui_el("reader-bottom-bar", "sync-offer", TDiv, "soffer")
  val () = ui_role("sync-offer", RStatus)
  val () = ui_text_btn("sync-offer", "sync-go", "btn", "Go to where you were on another device")
  val () = ui_icon_btn("sync-offer", "sync-offer-close", "ibtn", IcClose, "Dismiss")
in ui_show("sync-offer", false) end

(* The fields, made again, with what is kept *)
fn _fields_show (): void = let
  val () = _fields_make()
  val () = _fastmail_fields_make()
in
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => ()
  | ~Fastmail(user, user_len, password, password_len) => let
      fn copy {source_loc:agz}{size:pos}{count:pos | count <= size; count <= 1024} (source: !$A.arr(byte, source_loc, size), count: int count): [l:agz] $A.arr(byte, l, count) = let
        val out = $A.alloc<byte>(count)
        fun fill {out_loc:agz}{j:nat | j <= count} .<count - j>. (source: !$A.arr(byte, source_loc, size), out: !$A.arr(byte, out_loc, count), j: int j): void =
          if j >= count then () else let val () = $A.set<byte>(out, j, $A.get<byte>(source, j)) in fill(source, out, j + 1) end
        val () = fill(source, out, 0)
      in out end
      val () = ui_attr_buf("fastmail-user", AValue, copy(user, user_len), user_len)
      val () = ui_attr_buf("fastmail-password", AValue, copy(password, password_len), password_len)
    in _store_free(_store_swap(_store, Fastmail(user, user_len, password, password_len))) end
  | ~Android(account, account_len) => _store_free(_store_swap(_store, Android(account, account_len)))
  | ~Dropbox(refresh, refresh_len) => _store_free(_store_swap(_store, Dropbox(refresh, refresh_len)))
  | ~WebDav(url, url_len, user, user_len, password, password_len) => let
      fn copy {source_loc:agz}{size:pos}{count:pos | count <= size; count <= 1024} (source: !$A.arr(byte, source_loc, size), count: int count): [l:agz] $A.arr(byte, l, count) = let
        val out = $A.alloc<byte>(count)
        fun fill {out_loc:agz}{j:nat | j <= count} .<count - j>. (source: !$A.arr(byte, source_loc, size), out: !$A.arr(byte, out_loc, count), j: int j): void =
          if j >= count then () else let val () = $A.set<byte>(out, j, $A.get<byte>(source, j)) in fill(source, out, j + 1) end
        val () = fill(source, out, 0)
      in out end
      val () = ui_attr_buf("sync-url", AValue, copy(url, url_len), url_len)
      val () = (if user_len > 0 then ui_attr_buf("sync-user", AValue, copy(user, user_len), user_len) else ())
      val () = (if password_len > 0 then ui_attr_buf("sync-password", AValue, copy(password, password_len), password_len) else ())
    in _store_free(_store_swap(_store, WebDav(url, url_len, user, user_len, password, password_len))) end
end

(* The step left (Cancel, Escape, its sign-in begun, or the screen
   opened again): the link to a Nextcloud sign-in page goes, and the
   list is shown again *)
fn _step_close (): void = let
  val () = (if layer_is_open(LSyncStep()) then layer_close(LSyncStep()) else ())
in ui_show("nextcloud-page", false) end

(* Opens the sync screen: its rows, each only where its service can be
   used here, and its status *)
#pub fn sync_screen_open (): void
implement sync_screen_open () = let
  val () = _step_close()
  (* Google Drive: a build with no client to sign in with lists it
     neither in the app nor in a browser, and Google's script is loaded
     only when there is one *)
  val client = $A.alloc<byte>(256)
  val client_len = sync_clients_google(client)
  val () = $A.free<byte>(client)
  val google = (if client_len <= 0 then false
    else case+ _google_way() of AppAuthorization() => true | BrowserIdentity() => true | NoGoogleWay() => false): bool
  val () = ui_show("sync-google-row", google)
  (* Dropbox: in a browser, its page signs the reader in in place of
     this one; in the app, in the system's browser over it (an app
     without that browser does not list it); a build with no key to
     sign in with does not list it *)
  val app = $BAPP.is_native_platform()
  val key = $A.alloc<byte>(256)
  val key_len = sync_clients_dropbox(key)
  val () = $A.free<byte>(key)
  val dropbox = (if key_len <= 0 then false else if app then _round_trip_available() else true): bool
  val () = ui_show("sync-dropbox-row", dropbox)
  (* Fastmail: in the app only *)
  val () = ui_show("sync-fastmail-row", app)
  val () = _fields_show()
  val () = _status_show()
  val () = _actions_show(_store_on())
  val () = layer_open(LSync())
in ui_focus("sync-done") end

(* A service's own sign-in step, opened from its row over the list:
   only its part, its button and Cancel shown, its fields as kept *)
#pub fn sync_step_open (service: sync_service): void
implement sync_step_open (service) = let
  val app = $BAPP.is_native_platform()
  val () = ui_text("sync-step-title", service_title(service))
  val () = ui_text("sync-step-status", " ")
  val () = ui_show("sync-step-google", false)
  val () = ui_show("sync-step-dropbox", false)
  val () = ui_show("fastmail-form", false)
  val () = ui_show("nextcloud-box", false)
  val () = ui_show("sync-step-webdav", false)
  val () = ui_show(_step_part_id(service), true)
  val () = ui_show("sync-android", false)
  val () = ui_show("sync-google", false)
  val () = ui_show("sync-dropbox", false)
  val () = ui_show("sync-fastmail", false)
  val () = ui_show("nextcloud-sign-in", false)
  val () = ui_show("sync-webdav", false)
  val () = _fields_show()
  val () = layer_open(LSyncStep())
in
  case+ service of
  | ServiceGoogle() => let
      val () = (if app then ui_text_long("sync-android-about", "Syncs through the Google account on this phone, in a folder of its Google Drive that only Quire sees.")
        else ui_text_long("sync-android-about", "Syncs through your Google account, in a folder of its Google Drive that only Quire sees. Google signs you in for an hour at a time: after that, Sync now asks again."))
      val () = ui_show("sync-android", app)
      val () = ui_show("sync-google", ~app)
    in if app then ui_focus("sync-android") else ui_focus("sync-google") end
  | ServiceDropbox() => let
      val () = (if app then ui_text_long("sync-dropbox-about", "Syncs through your Dropbox account, in a folder of its own (Apps, then Quire) that only Quire sees. Dropbox's page opens in your browser to sign you in, then brings you back here.")
        else ui_text_long("sync-dropbox-about", "Syncs through your Dropbox account, in a folder of its own (Apps, then Quire) that only Quire sees. Dropbox's page signs you in, then brings you back here."))
      val () = ui_show("sync-dropbox", true)
    in ui_focus("sync-dropbox") end
  | ServiceFastmail() => let
      val () = ui_show("sync-fastmail", true)
    in ui_focus("fastmail-user") end
  | ServiceNextcloud() => let
      val () = ui_show("nextcloud-sign-in", true)
    in ui_focus("nextcloud-server") end
  | ServiceWebDav() => let
      val () = ui_show("sync-webdav", true)
    in ui_focus("sync-url") end
end

(* Cancel, or Escape: the step closed, a sign-in under way stopped, and
   the focus back on the list *)
#pub fn sync_step_cancel (): void
implement sync_step_cancel () = let
  val () = !_sign_in_generation := !_sign_in_generation + 1
  val () = _step_close()
in ui_focus("sync-done") end

(* What the step says: a field left empty *)
fn _step_says {text_len:pos | text_len < 65536} (text: string text_len): void = ui_text_long("sync-step-status", text)


(* The field id's value, at most most bytes of it, in an array of most *)
fn _field_value {id_len:pos | id_len < 256}{most:pos | most <= 1024} (id: string id_len, most: int most)
  : [l:agz][value_len:nat | value_len <= most] @($A.arr(byte, l, most), int value_len) = let
  val id_len = g1u2i(string1_length(id))
  val id_bytes = $A.alloc<byte>(id_len)
  val () = $A.write_text(id_bytes, 0, $A.text_lit(id), id_len)
  val @(id_frozen, id_borrow) = $A.freeze<byte>(id_bytes)
  val value = $DR.read_input_value(id_borrow, id_len)
  val () = release_bytes(id_frozen, id_borrow)
  val out = $A.alloc<byte>(most)
in
  case+ value of
  | ~$R.none() => @(out, 0)
  | ~$R.some(blob) => let
      val blob_len = $BD.blob_len(blob)
      val value_len = _within(blob_len, most)
      val () = $BD.blob_read(blob, 0, out, value_len)
      val () = $BD.blob_free(blob)
    in @(out, value_len) end
end

(* What asking for a token came to: the account's address (the token is
   kept, in _token), or how it failed (a sync_result) *)
datavtype asked =
  | {l:agz}{account_len:nat | account_len <= ACCOUNT_MAX} Asked of ($A.arr(byte, l, ACCOUNT_MAX), int account_len)
  | AskFailed of (sync_result)

implement $P.dispose<asked>(answer) =
  case+ answer of
  | ~Asked(account, _) => $A.free<byte>(account)
  | ~AskFailed(_) => ()

(* The account's address as Drive gives it, with the token held (empty
   when Drive gives none) *)
fn _drive_address (): $P.promise(asked, $P.Chained) =
  case+ _token_swap(NoToken()) of
  | ~NoToken() => $P.ret<asked>(Asked($A.alloc<byte>(ACCOUNT_MAX), 0))
  | ~Token(token, token_len) => let
      val pending = drive_account_address(token, token_len)
      val () = _token_free(_token_swap(Token(token, token_len)))
    in
      $P.and_then<drive_address><asked>(pending, llam(found) =>
        case+ found of
        | ~DriveAddress(address, address_len) => $P.ret<asked>(Asked(address, address_len))
        | ~DriveNoAddress() => $P.ret<asked>(Asked($A.alloc<byte>(ACCOUNT_MAX), 0)))
    end

(* The consent screen is the reader's to take as long as they like, so
   nothing ends a wait for it but its answer or the reader's Stop waiting
   (#340): while it is pending the status card says so and shows Stop
   waiting, which ends the ask as a cancel, and the answer that comes
   after it is dropped. The ask's outcome is the promise of the resolver
   kept here (see answer_wait) *)
datavtype consent_wait =
  | NoConsentWait of ()
  | ConsentWait of $P.resolver(asked)

val _consent_wait = ref<consent_wait>(NoConsentWait())
val _consent_number = ref<int>(0)

fn _consent_swap (next: consent_wait): consent_wait = let
  var previous: consent_wait = next
  val () = ref_exch_elt<consent_wait>(_consent_wait, previous)
in previous end

(* The ask begins: the card says Google's screen is awaited, with Stop
   waiting in place of the actions; the number of the ask is returned *)
fn _consent_begin (resolver: $P.resolver(asked)): int = let
  val () = !_consent_number := !_consent_number + 1
  val () = !_consent_open := true
  val () = (case+ _consent_swap(ConsentWait(resolver)) of
    | ~NoConsentWait() => ()
    | ~ConsentWait(old) => $P.resolve<asked>(old, AskFailed(SignInCanceled())))
  val () = !_last_result := GoogleAsking()
  val () = _status_show()
  val () = _actions_show(_store_on())
in !_consent_number end

(* The ask numbered number ends as answer, when it is the one awaited:
   the first to settle it resolves it, a later answer is dropped *)
fn _consent_settle (which: int, answer: asked): void =
  if which <> !_consent_number then $P.dispose<asked>(answer)
  else let
    val () = !_consent_number := !_consent_number + 1
    val () = !_consent_open := false
    val () = _actions_show(_store_on())
  in case+ _consent_swap(NoConsentWait()) of
    | ~NoConsentWait() => $P.dispose<asked>(answer)
    | ~ConsentWait(resolver) => $P.resolve<asked>(resolver, answer)
  end

(* Stop waiting (the status card's button): the ask ends as the reader's
   cancel, said quietly on the status line as a cancel is *)
#pub fn sync_stop (): void
implement sync_stop () =
  if ~(!_consent_open) then ()
  else _consent_settle(!_consent_number, AskFailed(SignInCanceled()))

(* What Google's answer to the consent screen makes of the ask *)
fn _consent_answer (answer: $GA.google_authorization($GA.MayAsk)): $P.promise(asked, $P.Chained) =
  case+ answer of
  | ~$GA.Authorized(token, granted, account, said) => let
      val () = $GA.google_granted_free(granted)
      val () = $GA.google_said_free(said)
      val kept = _text_token_keep(token)
      val @(address, address_len) = _text_address_of(account)
    in
      if ~kept then let val () = $A.free<byte>(address) in $P.ret<asked>(AskFailed(GoogleRefused())) end
      else if address_len > 0 then $P.ret<asked>(Asked(address, address_len))
      else let val () = $A.free<byte>(address) in _drive_address() end
    end
  (* the reader backed out (or Play services said CANCELED before any
     screen, which nothing tells apart, bats-lang/capacitor-plugins#8):
     noted on the screen's status line, quietly; its message is
     Google's wording, not the reader's to read *)
  | ~$GA.AuthorizeCanceled(said) => let
      val () = $GA.google_said_free(said)
    in $P.ret<asked>(AskFailed(SignInCanceled())) end
  | ~$GA.ConsentShowing(said) => let
      val () = $GA.google_said_free(said)
    in $P.ret<asked>(AskFailed(GoogleConsentShowing())) end
  | ~$GA.AuthorizeRefused(status, said) =>
    $P.ret<asked>(AskFailed(_authorize_refused("authorizeScopes", status, said)))
  | ~$GA.AuthorizeUnavailable(said) => let
      val () = _said_free(said)
    in $P.ret<asked>(AskFailed(NotSetUp())) end
  | ~$GA.AuthorizeUnexpected(unexpected) =>
    $P.ret<asked>(AskFailed(_authorize_unexpected("signing in to Google", "authorizeScopes", unexpected)))

(* In the app: a token for drive.appdata, Google's consent screen shown
   when the reader has not granted it (bridge's google_authorize_scopes),
   and the account's address: the one the authorization names, else
   Drive's (about.get), else none (Turn off then takes the grant back
   with the token) *)
fn _authorized_ask (): $P.promise(asked, $P.Chained) =
  (* a second ask while the screen is awaited: it is the one open *)
  if !_consent_open then $P.ret<asked>(AskFailed(GoogleConsentShowing()))
  else case+ _drive_scopes() of
  | ~$R.none() => $P.ret<asked>(AskFailed(_not_a_scope("signing in to Google")))
  | ~$R.some(scopes) => let
    val pending = $GA.google_authorize_scopes(scopes)
    val @(outcome, resolver) = $P.create<asked>()
    val number = _consent_begin(resolver)
    val () = $P.finish<$GA.google_authorization($GA.MayAsk)>(pending, llam(answer) =>
      if number <> !_consent_number then _authorization_late(answer)
      else $P.finish<asked>(_consent_answer(answer), llam(done) => _consent_settle(number, done)))
  in $P.vow(outcome) end

(* In a browser: a token for drive.appdata from Google Identity
   Services, its window opened at the reader's tap *)
fn _identity_ask {client_loc:agz}{client_len:pos | client_len <= 256}
  (client: $A.arr(byte, client_loc, 256), client_len: int client_len): $P.promise(asked, $P.Chained) = let
  val @(scope_frozen, scope_bytes) = $A.freeze<byte>(_scope())
  val @(client_frozen, client_bytes) = $A.freeze<byte>(client)
  val @(client_used, client_rest) = $A.borrow_split<byte>(client_frozen, client_bytes, client_len)
  val pending = $GOOGLE.google_token_get(client_used, client_len, scope_bytes, SCOPE_LEN)
  val client_bytes = $A.borrow_join<byte>(client_frozen, client_used, client_rest)
  val () = release_bytes(client_frozen, client_bytes)
  val () = release_bytes(scope_frozen, scope_bytes)
in
  $P.and_then<$GOOGLE.google_token><asked>(pending, llam(answer) =>
    case+ answer of
    | ~$GOOGLE.GoogleToken(token, account) => let
        val kept = _token_keep(token)
        val @(address, address_len) = _address_of(account)
      in
        if kept then $P.ret<asked>(Asked(address, address_len))
        else let val () = $A.free<byte>(address) in $P.ret<asked>(AskFailed(GoogleRefused())) end
      end
    | ~$GOOGLE.GoogleNoAccount() => $P.ret<asked>(AskFailed(NoGoogleAccount()))
    | ~$GOOGLE.GoogleCanceled() => $P.ret<asked>(AskFailed(SignInCanceled()))
    | ~$GOOGLE.GoogleRefused() => $P.ret<asked>(AskFailed(GoogleRefused()))
    | ~$GOOGLE.GoogleUnavailable() => $P.ret<asked>(AskFailed(NotSetUp())))
end

(* Asks Google for a token for drive.appdata, for the reader's account:
   its consent the first time (in the app), its window each time (in a
   browser). Only when the reader acts (Use Android, Sync now); a build
   with no client offers neither *)
fn _token_ask (): $P.promise(asked, $P.Chained) = let
  val () = _refusal_forget()
  val client = $A.alloc<byte>(256)
  val client_len = sync_clients_google(client)
in
  if client_len <= 0 then let
    val () = $A.free<byte>(client)
  in $P.ret<asked>(AskFailed(NotSetUp())) end
  else case+ _google_way() of
    | AppAuthorization() => let val () = $A.free<byte>(client) in _authorized_ask() end
    | BrowserIdentity() => _identity_ask(client, client_len)
    | NoGoogleWay() => let val () = $A.free<byte>(client) in $P.ret<asked>(AskFailed(NotSetUp())) end
end

fn _ask_failed (result: sync_result): void = let
  val () = !_last_result := result
  val () = !_last_status := 0
  val () = !_last_minutes := $TM.epoch_minutes()
  val () = _status_show()
  val () = !_reader_waits := true
in _reader_told(result) end

(* The Android store with the account signed in, chosen and kept, then
   a sync *)
fn _android_chosen {l:agz}{account_len:nat | account_len <= ACCOUNT_MAX} (account: $A.arr(byte, l, ACCOUNT_MAX), account_len: int account_len): void = let
  val () = _store_free(_store_swap(_store, Android(account, account_len)))
  val () = _store_save()
  (* not synced to it yet: a sync of the backed-up file's does not count *)
  val () = !_last_result := NotSyncedYet()
  val () = (if layer_is_open(LSync()) then let
      val () = _fields_show()
    in _actions_show(true) end else ())
  val () = !_reader_waits := true
in sync_run() end

(* Use Android (the screen's button, in the app; Google Drive in a
   browser): Google's consent for the account on the device the first
   time (its window, in a browser), then sync through its Drive *)
#pub fn sync_android (): void
implement sync_android () = let
  (* the step's part is done: Google's own sheet (or window) asks the
     rest, and the status card says how it went *)
  val () = _step_close()
in
  $P.finish<asked>(_token_ask(), llam(answer) =>
    case+ answer of
    | ~Asked(account, account_len) => _android_chosen(account, account_len)
    | ~AskFailed(result) => _ask_failed(result))
end

(* Sync now with the Android store: with the token kept, or one asked
   for (Google's consent, when access was taken back; Google's window,
   in a browser) *)
fn _android_now (): void = let
  val held = _token_swap(NoToken())
  val have = (case+ held of Token(_, _) => true | NoToken() => false): bool
  val () = _token_free(_token_swap(held))
in
  if have then let
    val () = !_reader_waits := true
  in sync_run() end
  else $P.finish<asked>(_token_ask(), llam(answer) =>
    case+ answer of
    | ~Asked(account, account_len) => _android_chosen(account, account_len)
    | ~AskFailed(result) => _ask_failed(result))
end

(* Sync now (the status card's button, while a store is chosen): the
   Android store's with its token (or one asked for), any other's at
   once *)
#pub fn sync_now (): void
implement sync_now () =
  if _is_android() then _android_now()
  else if _store_on() then sync_run()
  else let
    val () = !_last_result := NoAddress()
  in _status_show() end

(* Sync with this folder (the WebDAV step's button): the folder's
   address, user name and password kept, then a sync; an address that is
   not a web one is asked for again *)
#pub fn sync_webdav (): void
implement sync_webdav () = let
  val @(url, url_len) = _field_value("sync-url", URL_MAX)
  val @(user, user_len) = _field_value("sync-user", USER_MAX)
  val @(password, password_len) = _field_value("sync-password", PASSWORD_MAX)
  val web = (if _starts(url, url_len, "https://", 8, 0) then true else _starts(url, url_len, "http://", 7, 0)): bool
in
  if url_len <= 0 then let
    val () = $A.free<byte>(url)
    val () = $A.free<byte>(user)
    val () = $A.free<byte>(password)
  in _step_says("Enter the folder's address, starting with https://.") end
  else if ~web then let
    val () = $A.free<byte>(url)
    val () = $A.free<byte>(user)
    val () = $A.free<byte>(password)
  in _step_says("Enter the folder's address, starting with https://.") end
  else let
    val () = _step_close()
    val () = _store_free(_store_swap(_store, WebDav(url, url_len, user, user_len, password, password_len)))
    val () = _store_save()
    val () = _actions_show(true)
    (* not synced to it yet, while a sync of the backed-up file's ends *)
    val () = (if !_busy then !_last_result := NotSyncedYet() else ())
    val () = _status_show()
  in sync_run() end
end

(* Sync with Fastmail (its step's button): its address and app password
   kept, then a sync *)
#pub fn sync_fastmail (): void
implement sync_fastmail () = let
  val @(user, user_len) = _field_value("fastmail-user", USER_MAX)
  val @(password, password_len) = _field_value("fastmail-password", PASSWORD_MAX)
in
  if user_len <= 0 then let
    val () = $A.free<byte>(user)
    val () = $A.free<byte>(password)
  in _step_says("Enter your Fastmail address and an app password.") end
  else if password_len <= 0 then let
    val () = $A.free<byte>(user)
    val () = $A.free<byte>(password)
  in _step_says("Enter your Fastmail address and an app password.") end
  else let
    val () = _step_close()
    val () = _store_free(_store_swap(_store, Fastmail(user, user_len, password, password_len)))
    val () = _store_save()
    val () = _fields_show()
    val () = _actions_show(true)
    (* not synced to it yet, while a sync of the backed-up file's ends *)
    val () = (if !_busy then !_last_result := NotSyncedYet() else ())
    val () = _status_show()
  in sync_run() end
end

(* Turned off: Dropbox's grant to Quire given back (its refresh token
   gets an access token, which revokes them both), so the app's access
   is not left on the reader's account *)
fn _dropbox_revoke {refresh_loc:agz}{refresh_len:pos | refresh_len <= REFRESH_MAX}
  (refresh: $A.arr(byte, refresh_loc, REFRESH_MAX), refresh_len: int refresh_len): void = let
  val key = $A.alloc<byte>(256)
  val key_len = sync_clients_dropbox(key)
  val pending = dropbox_refresh(key, key_len, refresh, refresh_len)
  val () = $A.free<byte>(key)
  val () = $A.free<byte>(refresh)
in
  $P.finish<dropbox_tokens>(pending, llam(tokens) =>
    case+ tokens of
    | ~DropboxTokens(access, access_len, refresh, _) => let
        val () = $A.free<byte>(refresh)
        val revoking = dropbox_revoke(access, access_len)
        val () = $A.free<byte>(access)
        (* ignored: sync is off here whatever Dropbox says; the grant is
           listed in the account's connected apps to remove by hand *)
      in $P.finish<int>(revoking, llam(_) => ()) end
    (* none got: the grant is already gone, or Dropbox is not reached;
       either way sync is off here *)
    | ~DropboxRefused(_) => ())
end

(* ============================================================
   Nextcloud: signing in with its Login Flow v2 (nextcloud.bats),
   which ends in a WebDAV store of the user's files folder, the login
   name and an app password
   ============================================================ *)


(* The polls a sign-in makes, a few seconds apart: the flow's token
   lasts 20 minutes *)
#define POLLS 400
#define POLL_MILLISECONDS 3000

(* A sign-in's progress, in the screen's status line *)
fn _sign_in_says {text_len:pos | text_len < 65536} (text: string text_len): void = _step_says(text)

(* What a failed step says *)
fn _sign_in_failed (failure: nextcloud_failure): void = let
  val () = ui_show("nextcloud-page", false)
in
  case+ failure of
  | NextcloudUnreachable() => _sign_in_says("Can't reach the server, or it doesn't let a browser in (CORS). The Quire app can sign in; in a browser, the server must allow this app's origin.")
  | NextcloudNotNextcloud() => _sign_in_says("That address isn't a Nextcloud server, or it didn't answer as one.")
  | NextcloudRefused() => _sign_in_says("Nextcloud refused the app password it gave. Sign in again.")
  | NextcloudMemory() => _sign_in_says("There isn't enough memory to sign in.")
end

(* A user's id nobody took (its promise let go), freed *)
implement $P.dispose<user_found>(found) = user_found_free(found)

(* The user's id asked for, signed in with the authorization made *)
fn _user_id_asked {server_loc,authorization_loc:agz}{server_len:pos | server_len <= 1024}{authorization_len:nat | authorization_len <= 700}
  (server: !$A.arr(byte, server_loc, 1024), server_len: int server_len,
   authorization: !$A.arr(byte, authorization_loc, 700), authorization_len: int authorization_len): $P.promise(user_found, $P.Chained) =
  if authorization_len > 0 then nextcloud_user_id(server, server_len, authorization, authorization_len)
  else $P.ret<user_found>(UserNotFound(NextcloudNotNextcloud()))

(* Signed in: the folder of the user's files found by their id, and
   kept as the WebDAV store, then a sync *)
fn _sign_in_granted {server_loc,name_loc,password_loc:agz}{server_len,name_len,password_len:pos | server_len <= 1024; name_len <= 1024; password_len <= 1024}
  (generation: int, server: $A.arr(byte, server_loc, 1024), server_len: int server_len,
   name: $A.arr(byte, name_loc, 1024), name_len: int name_len,
   password: $A.arr(byte, password_loc, 1024), password_len: int password_len): void =
  if name_len > USER_MAX then let
    val () = $A.free<byte>(server)
    val () = $A.free<byte>(name)
    val () = $A.free<byte>(password)
  in _sign_in_failed(NextcloudNotNextcloud()) end
  else if password_len > PASSWORD_MAX then let
    val () = $A.free<byte>(server)
    val () = $A.free<byte>(name)
    val () = $A.free<byte>(password)
  in _sign_in_failed(NextcloudNotNextcloud()) end
  else let
    val user = $A.alloc<byte>(USER_MAX)
    val () = _bytes_from(name, 0, name_len, user, 0)
    val secret = $A.alloc<byte>(PASSWORD_MAX)
    val () = _bytes_from(password, 0, password_len, secret, 0)
    val () = $A.free<byte>(name)
    val () = $A.free<byte>(password)
    val authorization = $A.alloc<byte>(700)
    val authorization_len = _authorization(user, name_len, secret, password_len, authorization)
    val pending = _user_id_asked(server, server_len, authorization, authorization_len)
    val () = $A.free<byte>(authorization)
  in
    $P.finish<user_found>(pending, llam(found) =>
      if generation <> !_sign_in_generation then let
        val () = user_found_free(found)
        val () = $A.free<byte>(server)
        val () = $A.free<byte>(user)
      in $A.free<byte>(secret) end
      else case+ found of
      | ~UserNotFound(failure) => let
          val () = $A.free<byte>(server)
          val () = $A.free<byte>(user)
          val () = $A.free<byte>(secret)
        in _sign_in_failed(failure) end
      | ~UserFound(id, id_len) => let
          val folder = $A.alloc<byte>(4 * 1024 + 32)
          val folder_len = nextcloud_folder(server, server_len, id, id_len, folder)
          val () = $A.free<byte>(server)
          val () = $A.free<byte>(id)
        in
          if folder_len > URL_MAX then let
            val () = $A.free<byte>(folder)
            val () = $A.free<byte>(user)
            val () = $A.free<byte>(secret)
          in _sign_in_failed(NextcloudNotNextcloud()) end
          else let
            val url = $A.alloc<byte>(URL_MAX)
            val () = _bytes_from(folder, 0, folder_len, url, 0)
            val () = $A.free<byte>(folder)
            val () = _store_free(_store_swap(_store, WebDav(url, folder_len, user, name_len, secret, password_len)))
            val () = _store_save()
            (* signed in: the step is done, and the status card says
               how the sync goes *)
            val () = _step_close()
            val () = _fields_show()
            val () = _actions_show(true)
          in sync_run() end
        end)
  end

(* Waits, then asks the flow's endpoint whether the reader has signed
   in, polls left more times *)
fun _sign_in_wait {endpoint_loc,token_loc:agz}{endpoint_len,token_len:pos | endpoint_len <= 1024; token_len <= 1024}{polls:nat} .<polls>.
  (generation: int, endpoint: $A.arr(byte, endpoint_loc, 1024), endpoint_len: int endpoint_len,
   token: $A.arr(byte, token_loc, 1024), token_len: int token_len, polls: int polls): void =
  if polls <= 0 then let
    val () = $A.free<byte>(endpoint)
    val () = $A.free<byte>(token)
    val () = ui_show("nextcloud-page", false)
  in _sign_in_says("The sign-in timed out. Sign in with Nextcloud again.") end
  else $P.finish<Int>($P.vow($TM.timer_set(POLL_MILLISECONDS)), llam(_) =>
    if generation <> !_sign_in_generation then let
      val () = $A.free<byte>(endpoint)
    in $A.free<byte>(token) end
    else $P.finish<login_polled>(nextcloud_poll(endpoint, endpoint_len, token, token_len), llam(polled) =>
      if generation <> !_sign_in_generation then let
        val () = login_polled_free(polled)
        val () = $A.free<byte>(endpoint)
      in $A.free<byte>(token) end
      else case+ polled of
      | ~LoginNotYet() => _sign_in_wait(generation, endpoint, endpoint_len, token, token_len, polls - 1)
      | ~LoginPollFailed(failure) => let
          val () = $A.free<byte>(endpoint)
          val () = $A.free<byte>(token)
        in _sign_in_failed(failure) end
      | ~LoginGranted(server, server_len, name, name_len, password, password_len) => let
          val () = $A.free<byte>(endpoint)
          val () = $A.free<byte>(token)
          val () = _sign_in_says("Signed in. Finding your files...")
        in _sign_in_granted(generation, server, server_len, name, name_len, password, password_len) end))

(* Sign in with Nextcloud (the screen's button): the flow started on the
   server named, its sign-in page offered as a link (opened by the
   reader's own tap, so no browser blocks it), and polled *)
#pub fn sync_nextcloud_sign_in (): void
implement sync_nextcloud_sign_in () = let
  val @(address, address_len) = _field_value("nextcloud-server", 1024)
  val () = !_sign_in_generation := !_sign_in_generation + 1
  val generation = !_sign_in_generation
  val () = ui_show("nextcloud-page", false)
  (* https only: an app password is sent over it *)
  val secure = _starts(address, address_len, "https://", 8, 0)
in
  if address_len <= 0 then let
    val () = $A.free<byte>(address)
  in _sign_in_says("Enter your Nextcloud's address, starting with https://.") end
  else if ~secure then let
    val () = $A.free<byte>(address)
  in _sign_in_says("Enter your Nextcloud's address, starting with https://.") end
  else let
    val () = _sign_in_says("Asking the server...")
    val pending = nextcloud_start(address, address_len)
    val () = $A.free<byte>(address)
  in
    $P.finish<login_started>(pending, llam(started) =>
      if generation <> !_sign_in_generation then login_started_free(started)
      else case+ started of
      | ~LoginNotStarted(failure) => _sign_in_failed(failure)
      | ~LoginStarted(login, login_len, endpoint, endpoint_len, token, token_len) => let
          val () = ui_https_href("nextcloud-page", login, login_len)
          val () = ui_show("nextcloud-page", true)
          val () = _sign_in_says("Open Nextcloud's sign-in page, sign in and grant access; Quire waits here for it.")
        in _sign_in_wait(generation, endpoint, endpoint_len, token, token_len, POLLS) end)
  end
end

(* A token held for an Undo, put back: here and where it is kept *)
fn _token_restored (held: token_cell): void =
  case+ held of
  | ~NoToken() => ()
  | ~Token(token, token_len) => let
      val () = _google_token_save(token, token_len)
    in _token_free(_token_swap(Token(token, token_len))) end

val _revoke_number = ref<int>(0)

(* Turn off, made final, in the app: the reader's grant taken back from
   Google, so the next Use Android asks for consent again. By the
   account (google_revoke_access, Play services' revokeAccess), else
   with the token (Google's revocation endpoint, drive_grant_revoke).
   With neither there is nothing here to take it back with, and the
   grant stays listed in the Google account's third-party connections,
   where the reader can remove it *)
fn _google_revoke {l:agz}{account_len:nat | account_len <= ACCOUNT_MAX}
  (account: $A.arr(byte, l, ACCOUNT_MAX), account_len: int account_len, held: token_cell): void =
  if account_len > 0 then let
    val () = _token_free(held)
    val @(account_frozen, account_bytes) = $A.freeze<byte>(account)
    val @(used, rest) = $A.borrow_split<byte>(account_frozen, account_bytes, account_len)
    val () = (case+ $GA.google_text_of(used, account_len) of
      | ~$R.none() => notice_error("Google didn't take back Quire's access to Drive: remove it in your Google account, under Security, Your connections to third-party apps.")
      | ~$R.some(text) => (case+ _drive_scopes() of
        | ~$R.none() => let
            val () = $GA.google_text_free(text)
            val _ = _not_a_scope("taking back Quire's access to Google Drive")
          in () end
        | ~$R.some(scopes) => let
            val () = !_revoke_number := !_revoke_number + 1
            val number = !_revoke_number
            val () = $P.finish<$GA.google_authorization_change>($GA.google_revoke_access(text, scopes), llam(change) => let
              (* said whenever it comes, after the timer's word too *)
              val () = !_revoke_number := !_revoke_number + 1
            in _revoked(change) end)
          in
            $P.finish<Int>($P.vow($TM.timer_set(GOOGLE_ANSWER_MS)), llam(_) =>
              if number <> !_revoke_number then ()
              else let
                val () = !_revoke_number := !_revoke_number + 1
              in notice_error("Google didn't answer when Quire took back its access to Drive: remove it in your Google account, under Security, Your connections to third-party apps.") end)
          end))
    val account_bytes = $A.borrow_join<byte>(account_frozen, used, rest)
  in release_bytes(account_frozen, account_bytes) end
  else let
    val () = $A.free<byte>(account)
  in
    case+ held of
    | ~NoToken() => ()
    | ~Token(token, token_len) => let
        val pending = drive_grant_revoke(token, token_len)
        val () = $A.free<byte>(token)
        (* ignored: sync is off here whatever Google says *)
      in $P.finish<int>(pending, llam(_) => ()) end
  end

(* Turn off (the screen's button): the folder, user name and password
   forgotten at once (they are kept only for the Undo offered) *)
#pub fn sync_off (): void
implement sync_off () = let
  (* a sign-in under way stops *)
  val () = !_sign_in_generation := !_sign_in_generation + 1
  val () = ui_show("nextcloud-page", false)
in
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => ()
  | ~Android(account, account_len) => let
      val () = _store_free(_store_swap(_store_off, Android(account, account_len)))
      val () = _store_forget()
      (* the token: in the app, held for the Undo and to take the grant
         back with once Turn off is final; in a browser, Google Identity
         Services' token revoked at once (ignored: revoked or not, the
         token is forgotten here, and the next Google Drive asks again) *)
      val app = _authorize_present()
      val held = _token_swap(NoToken())
      val held = (if app then held else let
          val () = _token_free(held)
          val () = $P.finish<$GOOGLE.google_signed_out>($GOOGLE.google_sign_out(), llam(_) => ())
        in NoToken() end): token_cell
      val () = _fields_show()
      val () = _status_show()
      val () = _actions_show(false)
    in
      $P.finish<settled>(undo_offer(SyncTurnedOff()), llam(how) =>
        case+ how of
        | Undone() => let
            val () = _store_free(_store_swap(_store, _store_swap(_store_off, NoStore())))
            val () = _store_save()
            val () = _token_restored(held)
          in
            if layer_is_open(LSync()) then let
              val () = _fields_show()
              val () = _actions_show(true)
            in _status_show() end else ()
          end
        (* made final: in the app, the grant taken back from Google *)
        | Final() => (case+ _store_swap(_store_off, NoStore()) of
          | ~Android(account, account_len) =>
            if app then _google_revoke(account, account_len, held)
            else let
              val () = $A.free<byte>(account)
            in _token_free(held) end
          | other => let
              val () = _store_free(other)
            in _token_free(held) end))
    end
  | ~Dropbox(refresh, refresh_len) => let
      val () = _store_free(_store_swap(_store_off, Dropbox(refresh, refresh_len)))
      val () = _store_forget()
      val () = _token_free(_token_swap(NoToken()))
      val () = _fields_show()
      val () = _status_show()
      val () = _actions_show(false)
    in
      $P.finish<settled>(undo_offer(SyncTurnedOff()), llam(how) =>
        case+ how of
        | Undone() => let
            val () = _store_free(_store_swap(_store, _store_swap(_store_off, NoStore())))
            val () = _store_save()
          in
            if layer_is_open(LSync()) then let
              val () = _fields_show()
              val () = _actions_show(true)
            in _status_show() end else ()
          end
        (* made final: Dropbox's grant given back *)
        | Final() => (case+ _store_swap(_store_off, NoStore()) of
          | ~Dropbox(refresh, refresh_len) => _dropbox_revoke(refresh, refresh_len)
          | other => _store_free(other)))
    end
  | ~Fastmail(user, user_len, password, password_len) => let
      val () = _store_free(_store_swap(_store_off, Fastmail(user, user_len, password, password_len)))
      val () = _store_forget()
      val () = _fields_show()
      val () = _status_show()
      val () = _actions_show(false)
    in
      $P.finish<settled>(undo_offer(SyncTurnedOff()), llam(how) =>
        case+ how of
        | Undone() => let
            val () = _store_free(_store_swap(_store, _store_swap(_store_off, NoStore())))
            val () = _store_save()
          in
            if layer_is_open(LSync()) then let
              val () = _fields_show()
              val () = _actions_show(true)
            in _status_show() end else ()
          end
        | Final() => _store_free(_store_swap(_store_off, NoStore())))
    end
  | ~WebDav(url, url_len, user, user_len, password, password_len) => let
      val () = _store_free(_store_swap(_store_off, WebDav(url, url_len, user, user_len, password, password_len)))
      val () = _store_forget()
      val () = _fields_show()
      val () = _status_show()
      val () = _actions_show(false)
    in
      $P.finish<settled>(undo_offer(SyncTurnedOff()), llam(how) =>
        case+ how of
        | Undone() => let
            val () = _store_free(_store_swap(_store, _store_swap(_store_off, NoStore())))
            val () = _store_save()
          in
            if layer_is_open(LSync()) then let
              val () = _fields_show()
              val () = _actions_show(true)
            in _status_show() end else ()
          end
        | Final() => _store_free(_store_swap(_store_off, NoStore())))
    end
end

(* The store chosen, read with its credentials, then a sync *)
fn _stores_load (): $P.promise(int, $P.Chained) = let
    val @(choice_frozen, choice_bytes) = $A.freeze<byte>(_choice_key())
    val choice_pending = $IDB.idb_get(choice_bytes, 4)
    val () = release_bytes(choice_frozen, choice_bytes)
  in
    $P.and_then<$IDB.lookup><int>(choice_pending, llam(found) => let
      (* the store chosen: its kind (none, and sync off, when it could
         not be read) *)
      val kind = (case+ lookup_bytes(found) of
        | ~NothingStored() => NoStoreKind()
        | ~StoredUnreadable() => NoStoreKind()
        | ~StoredBytes(record, n) => let
            val kind = (if n >= 5 then (if byte2int0($A.get<byte>(record, 1)) = 83 then _kind_of_code(byte2int0($A.get<byte>(record, 4))) else NoStoreKind()) else NoStoreKind()): store_kind
            val () = $A.free<byte>(record)
          in kind end): store_kind
    in
      case+ kind of
      | AndroidKind() => let
        val @(android_frozen, android_bytes) = $A.freeze<byte>(_android_key())
        val android_pending = $IDB.idb_get(android_bytes, 12)
        val () = release_bytes(android_frozen, android_bytes)
      in
        $P.and_then<$IDB.lookup><int>(android_pending, llam(found) => let
          val () = (case+ lookup_bytes(found) of
            | ~NothingStored() => ()
            (* no store: sync stays off this session *)
            | ~StoredUnreadable() => ()
            | ~StoredBytes(record, n) => let
                val read = _android_of_record(record, n)
                val () = $A.free<byte>(record)
              in _store_free(_store_swap(_store, read)) end)
          (* and the token kept, so this sync goes on with it *)
          val @(token_key_frozen, token_key_bytes) = $A.freeze<byte>(_google_token_key())
          val token_pending = $IDB.idb_get(token_key_bytes, 17)
          val () = release_bytes(token_key_frozen, token_key_bytes)
        in
          $P.and_then<$IDB.lookup><int>(token_pending, llam(token_found) => let
            val () = (case+ lookup_bytes(token_found) of
              (* none kept, or none read: sync pauses until Sync now *)
              | ~NothingStored() => ()
              | ~StoredUnreadable() => ()
              | ~StoredBytes(record, n) => let
                  val read = _google_token_of_record(record, n)
                  val () = $A.free<byte>(record)
                in _token_free(_token_swap(read)) end)
            val () = sync_run()
          in $P.ret<int>(0) end)
        end)
      end
      | DropboxKind() => let
        val @(dropbox_frozen, dropbox_bytes) = $A.freeze<byte>(_dropbox_key())
        val dropbox_pending = $IDB.idb_get(dropbox_bytes, 12)
        val () = release_bytes(dropbox_frozen, dropbox_bytes)
      in
        $P.and_then<$IDB.lookup><int>(dropbox_pending, llam(found) => let
          val () = (case+ lookup_bytes(found) of
            | ~NothingStored() => ()
            (* no store: sync stays off this session *)
            | ~StoredUnreadable() => ()
            | ~StoredBytes(record, n) => let
                val read = _dropbox_of_record(record, n)
                val () = $A.free<byte>(record)
              in _store_free(_store_swap(_store, read)) end)
          val () = sync_run()
        in $P.ret<int>(0) end)
      end
      | FastmailKind() => let
        val @(fastmail_frozen, fastmail_bytes) = $A.freeze<byte>(_fastmail_key())
        val fastmail_pending = $IDB.idb_get(fastmail_bytes, 13)
        val () = release_bytes(fastmail_frozen, fastmail_bytes)
      in
        $P.and_then<$IDB.lookup><int>(fastmail_pending, llam(found) => let
          val () = (case+ lookup_bytes(found) of
            | ~NothingStored() => ()
            (* no store: sync stays off this session *)
            | ~StoredUnreadable() => ()
            | ~StoredBytes(record, n) => let
                val read = _fastmail_of_record(record, n)
                val () = $A.free<byte>(record)
              in _store_free(_store_swap(_store, read)) end)
          val () = sync_run()
        in $P.ret<int>(0) end)
      end
      (* no store chosen: the app's backed-up file, where it has one *)
      | NoStoreKind() => let
        val () = sync_run()
      in $P.ret<int>(0) end
      | BackupKind() => let
        val () = sync_run()
      in $P.ret<int>(0) end
      | WebDavKind() => let
        val @(webdav_frozen, webdav_bytes) = $A.freeze<byte>(_webdav_key())
        val webdav_pending = $IDB.idb_get(webdav_bytes, 11)
        val () = release_bytes(webdav_frozen, webdav_bytes)
      in
        $P.and_then<$IDB.lookup><int>(webdav_pending, llam(found) => let
          val () = (case+ lookup_bytes(found) of
            | ~NothingStored() => ()
            (* no store: sync stays off this session *)
            | ~StoredUnreadable() => ()
            | ~StoredBytes(record, n) => let
                val read = _store_of_record(record, n)
                val () = $A.free<byte>(record)
              in _store_free(_store_swap(_store, read)) end)
          val () = sync_run()
        in $P.ret<int>(0) end)
      end
    end)
end

(* ============================================================
   Dropbox: its sign-in, a page away and back
   ============================================================ *)

(* Where a URL's query or fragment starts in url[0, n): n for neither *)
fn _query_start {l:agz}{size,n:nat | n <= size} (url: !$A.arr(byte, l, size), n: int n): [stop:nat | stop <= n] int stop = let
  fun find {i:nat | i <= n} .<n - i>. (url: !$A.arr(byte, l, size), n: int n, i: int i): [stop:nat | stop <= n] int stop =
    if i >= n then n
    else let
      val b = byte2int0($A.get<byte>(url, i))
    in if b = 63 then i else if b = 35 then i else find(url, n, i + 1) end
in find(url, n, 0) end

(* Whether url[stop - 10, stop) is "index.html" *)
fn _ends_index {l:agz}{size,stop:nat | stop <= size} (url: !$A.arr(byte, l, size), stop: int stop): bool =
  if stop < 10 then false
  else let
    fun same {end_at:int | end_at >= 10; end_at <= size}{j:nat | j <= 10} .<10 - j>. (url: !$A.arr(byte, l, size), stop: int end_at, j: int j): bool =
      if j >= 10 then true
      else if byte2int0($A.get<byte>(url, stop - 10 + j)) <> char2int0(string_get_at("index.html", j)) then false
      else same(url, stop, j + 1)
  in same(url, stop, 0) end

(* Where url[0, n)'s query or fragment starts, before an "index.html" *)
fn _redirect_base {l:agz}{size,n:nat | n <= size} (url: !$A.arr(byte, l, size), n: int n): [base:nat | base <= n] int base = let
  val base = _query_start(url, n)
in
  if base < 10 then base
  else if _ends_index(url, base) then base - 10
  else base
end

(* The address Dropbox sends the reader back to: in a browser, the
   page's own, without its query, fragment or "index.html", and
   "?oauth=dropbox"; in the app, its own scheme's, which opens it again
   from the system's browser (RFC 8252). The addresses registered for
   the app's key are these (sync-identity.yml) *)
fn _redirect {l:agz} (out: !$A.arr(byte, l, 2100)): [length:nat | length <= 2100] int length =
  if $BAPP.is_native_platform() then _put_literal(out, 0, "quire://oauth/dropbox")
  else let
    val page = $A.alloc<byte>(2048)
    val page_len = $NAV.get_url(page, 2048)
    val base = _redirect_base(page, page_len)
    val () = _bytes_from(page, 0, base, out, 0)
    val () = $A.free<byte>(page)
  in _put_literal(out, base, "?oauth=dropbox") end

(* Whether url[position, n) starts with name *)
fun _name_at {l:agz}{size,n:nat | n <= size}{position:int}{name_len:nat}{j:nat | j <= name_len} .<name_len - j>.
  (url: !$A.arr(byte, l, size), n: int n, position: int position, name: string name_len, name_len: int name_len, j: int j): bool =
  if j >= name_len then true
  else let
    val at = position + j
  in
    if at < 0 then false
    else if at >= n then false
    else if byte2int0($A.get<byte>(url, at)) <> char2int0(string_get_at(name, j)) then false
    else _name_at(url, n, position, name, name_len, j + 1)
  end

(* Whether b is unreserved in a URL (RFC 3986): all a code, a state or
   an error name from Dropbox holds *)
fn _unreserved (b: int): bool =
  if b >= 97 then b <= 122 || b = 126
  else if b >= 65 then b <= 90 || b = 95
  else if b >= 48 then b <= 57
  else b = 45 || b = 46

(* out[k, ...) := url[i, ...) up to "&", "#" or the end: its length, 0
   when it is too long or holds what a value of Dropbox's does not *)
fun _value_copy {l,out_loc:agz}{size,n:nat | n <= size}{i:nat | i <= n}{k:nat | k <= 512} .<n - i>.
  (url: !$A.arr(byte, l, size), n: int n, i: int i, out: !$A.arr(byte, out_loc, 512), k: int k): [kept:nat | kept <= 512] int kept =
  if i >= n then k
  else let
    val b = byte2int0($A.get<byte>(url, i))
  in
    if b = 38 then k
    else if b = 35 then k
    else if ~_unreserved(b) then 0
    else if k >= 512 then 0
    else let
      val () = $A.set<byte>(out, k, $A.get<byte>(url, i))
    in _value_copy(url, n, i + 1, out, k + 1) end
  end

(* The query parameter name's value in out: its length, 0 for none *)
fn _parameter {l,out_loc:agz}{size,n:nat | n <= size}{name_len:pos}
  (url: !$A.arr(byte, l, size), n: int n, name: string name_len, name_len: int name_len, out: !$A.arr(byte, out_loc, 512)): [kept:nat | kept <= 512] int kept = let
  fun find {i:nat | i <= n} .<n - i>. (url: !$A.arr(byte, l, size), n: int n, i: int i, out: !$A.arr(byte, out_loc, 512)): [kept:nat | kept <= 512] int kept =
    if i >= n then 0
    else let
      val b = byte2int0($A.get<byte>(url, i))
    in
      if b = 35 then 0
      else if (b = 63 || b = 38) && _name_at(url, n, i + 1, name, name_len, 0) && _name_at(url, n, i + 1 + name_len, "=", 1, 0) then let
        val from = i + 2 + name_len
      in if from <= n then _value_copy(url, n, from, out, 0) else 0 end
      else find(url, n, i + 1, out)
    end
in find(url, n, 0, out) end

(* Whether text[0, text_len) is word *)
fn _is_word {l:agz}{n:nat}{text_len:nat | text_len <= n}{word_len:nat}
  (text: !$A.arr(byte, l, n), text_len: int text_len, word: string word_len, word_len: int word_len): bool =
  if text_len <> word_len then false
  else _starts(text, text_len, word, word_len, 0)

(* What the address said as the page opened: nothing of Dropbox's, its
   code and the state sent with the reader, or that it signed no one in
   (the reader said no, or it refused) *)
datavtype dropbox_return =
  | NotReturned of ()
  | {code_loc,state_loc:agz}{code_len,state_len:pos | code_len <= 512; state_len <= 512}
    ReturnedCode of ($A.arr(byte, code_loc, 512), int code_len, $A.arr(byte, state_loc, 512), int state_len)
  | ReturnedRefused of (bool)

val _returned = ref<dropbox_return>(NotReturned())
val _returning = ref<bool>(false)

fn _returned_swap (cell: dropbox_return): dropbox_return = let
  var previous: dropbox_return = cell
  val () = ref_exch_elt<dropbox_return>(_returned, previous)
in previous end

fn _returned_free (cell: dropbox_return): void =
  case+ cell of
  | ~NotReturned() => ()
  | ~ReturnedCode(code, _, state, _) => let
      val () = $A.free<byte>(code)
    in $A.free<byte>(state) end
  | ~ReturnedRefused(_) => ()

fn _returned_of {l:agz}{size,n:nat | n <= size} (page: !$A.arr(byte, l, size), n: int n): dropbox_return = let
  val code = $A.alloc<byte>(512)
  val code_len = _parameter(page, n, "code", 4, code)
  val state = $A.alloc<byte>(512)
  val state_len = _parameter(page, n, "state", 5, state)
  val error = $A.alloc<byte>(512)
  val error_len = _parameter(page, n, "error", 5, error)
  val canceled = _is_word(error, error_len, "access_denied", 13)
  val () = $A.free<byte>(error)
in
  if code_len > 0 then
    (if state_len > 0 then ReturnedCode(code, code_len, state, state_len)
     else let
       val () = $A.free<byte>(code)
       val () = $A.free<byte>(state)
     in ReturnedRefused(false) end)
  else let
    val () = $A.free<byte>(code)
    val () = $A.free<byte>(state)
  in ReturnedRefused(canceled) end
end

(* The page's address as it opened: a return from Dropbox's sign-in
   ("?oauth=dropbox&code=...&state=..." or "&error=...") is kept, and
   the address is put back to the page's own, so the code is neither
   bookmarked, nor kept in the history, nor taken again on a reload *)
fn _dropbox_return_take (): void = let
  val page = $A.alloc<byte>(2048)
  val page_len = $NAV.get_url(page, 2048)
  val oauth = $A.alloc<byte>(512)
  val oauth_len = _parameter(page, page_len, "oauth", 5, oauth)
  val dropbox = _is_word(oauth, oauth_len, "dropbox", 7)
  val () = $A.free<byte>(oauth)
in
  if ~dropbox then $A.free<byte>(page)
  else let
    val () = _returned_free(_returned_swap(_returned_of(page, page_len)))
    val () = !_returning := true
    val base = _query_start(page, page_len)
    val @(page_frozen, page_bytes) = $A.freeze<byte>(page)
    val @(used, rest) = $A.borrow_split<byte>(page_frozen, page_bytes, base)
    val () = $NAV.replace_state(used, base)
    val page_bytes = $A.borrow_join<byte>(page_frozen, used, rest)
  in release_bytes(page_frozen, page_bytes) end
end

(* Whether the page opened on a return from Dropbox's sign-in: the app
   opens Settings then, and the sync screen comes over it *)
#pub fn sync_returning (): bool
implement sync_returning () = !_returning

(* An address the app was opened at (bridge's listen_app_link): Dropbox's
   sign-in coming back from the system browser's tab,
   "quire://oauth/dropbox?code=...&state=..." (or "?error=..."), is
   taken as a browser takes it from its address, and the tab closed; any
   other address is not sync's *)
#pub fn sync_app_link {k:pos} (link: $BD.dblob(k)): void

(* When a return from Dropbox's sign-in is taken: as the page opens (the
   stores are not loaded yet: they are loaded with it), or while the app
   runs (the system's browser brought the app back) *)
datatype return_moment = AtStart | WhileOpen

(* The stores loaded, when they are not yet *)
fn _after_stores (moment: return_moment): $P.promise(int, $P.Chained) =
  case+ moment of
  | AtStart() => _stores_load()
  | WhileOpen() => $P.ret<int>(0)

(* A Dropbox sign-in that failed, said on the sync screen *)
fn _dropbox_failed (result: sync_result): void = let
  val () = (if layer_is_open(LSync()) then () else sync_screen_open())
in _ask_failed(result) end

(* The Dropbox store, signed in: kept and chosen, then a sync *)
fn _dropbox_chosen {refresh_loc,access_loc:agz}{refresh_len:pos | refresh_len <= REFRESH_MAX}{access_len:pos | access_len <= TOKEN_MAX}
  (refresh: $A.arr(byte, refresh_loc, REFRESH_MAX), refresh_len: int refresh_len, access: $A.arr(byte, access_loc, TOKEN_MAX), access_len: int access_len): void = let
  val () = _store_free(_store_swap(_store, Dropbox(refresh, refresh_len)))
  val () = _token_free(_token_swap(Token(access, access_len)))
  val () = _store_save()
  (* not synced to it yet *)
  val () = !_last_result := NotSyncedYet()
  val () = !_last_status := 0
  val () = (if layer_is_open(LSync()) then () else sync_screen_open())
  val () = _actions_show(true)
in sync_run() end

(* Whether a[0, n) and b[0, n) hold the same bytes *)
fun _same_bytes {a_loc,b_loc:agz}{a_size,b_size:nat}{n:nat | n <= a_size; n <= b_size}{j:nat | j <= n} .<n - j>.
  (a: !$A.arr(byte, a_loc, a_size), b: !$A.arr(byte, b_loc, b_size), n: int n, j: int j): bool =
  if j >= n then true
  else if byte2int0($A.get<byte>(a, j)) <> byte2int0($A.get<byte>(b, j)) then false
  else _same_bytes(a, b, n, j + 1)

(* Whether the state that came back, given[0, given_len), is the one
   sent, sent[0, SIGN_IN_STATE) *)
fn _same_state {sent_loc,given_loc:agz}{given_len:nat | given_len <= 512}
  (sent: !$A.arr(byte, sent_loc, 22), given: !$A.arr(byte, given_loc, 512), given_len: int given_len): bool =
  if given_len <> 22 then false
  else _same_bytes(sent, given, 22, 0)

(* The sign-in under way kept as the page left: its verifier, record[0,
   SIGN_IN_VERIFIER), and state, record[SIGN_IN_VERIFIER, SIGN_IN_VERIFIER +
   SIGN_IN_STATE) *)
#define SIGN_IN_VERIFIER 43
#define SIGN_IN_STATE 22
#define SIGN_IN_LEN 65

(* Dropbox's code taken back: the state checked against the one sent
   (another's is refused), then the code exchanged for tokens, with the
   verifier kept as the page left *)
fn _dropbox_exchanged {code_loc,state_loc:agz}{code_len,state_len:pos | code_len <= 512; state_len <= 512}
  (code: $A.arr(byte, code_loc, 512), code_len: int code_len, state: $A.arr(byte, state_loc, 512), state_len: int state_len,
   moment: return_moment): $P.promise(int, $P.Chained) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_dropbox_sign_in_key())
  val pending = $IDB.idb_get(key_bytes, 20)
  (* the sign-in is taken once: a reload does not take it again *)
  val () = save_checked($IDB.idb_delete(key_bytes, 20))
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><int>(pending, llam(found) =>
    case+ lookup_bytes(found) of
    | ~StoredBytes(record, n) =>
      if n <> SIGN_IN_LEN then let
        val () = $A.free<byte>(record)
        val () = $A.free<byte>(code)
        val () = $A.free<byte>(state)
      in $P.and_then<int><int>(_after_stores(moment), llam(_) => let
          val () = _dropbox_failed(DropboxSignInRefused())
        in $P.ret<int>(0) end) end
      else let
        val sent = $A.alloc<byte>(SIGN_IN_STATE)
        val () = _bytes_from(record, SIGN_IN_VERIFIER, SIGN_IN_STATE, sent, 0)
        val same = _same_state(sent, state, state_len)
        val () = $A.free<byte>(sent)
        val () = $A.free<byte>(state)
        val key = $A.alloc<byte>(256)
        val key_len = sync_clients_dropbox(key)
      in
        if ~same then let
          val () = $A.free<byte>(record)
          val () = $A.free<byte>(code)
          val () = $A.free<byte>(key)
        in $P.and_then<int><int>(_after_stores(moment), llam(_) => let
            val () = _dropbox_failed(DropboxSignInRefused())
          in $P.ret<int>(0) end) end
        else if key_len <= 0 then let
          val () = $A.free<byte>(record)
          val () = $A.free<byte>(code)
          val () = $A.free<byte>(key)
        in $P.and_then<int><int>(_after_stores(moment), llam(_) => let
            val () = _dropbox_failed(DropboxNotSetUp())
          in $P.ret<int>(0) end) end
        else let
          val redirect = $A.alloc<byte>(2100)
          val redirect_len = _redirect(redirect)
          val exchanging = dropbox_exchange(key, key_len, redirect, redirect_len, code, code_len, record, SIGN_IN_VERIFIER)
          val () = $A.free<byte>(redirect)
          val () = $A.free<byte>(key)
          val () = $A.free<byte>(record)
          val () = $A.free<byte>(code)
        in
          $P.and_then<dropbox_tokens><int>(exchanging, llam(tokens) =>
            case+ tokens of
            | ~DropboxTokens(access, access_len, refresh, refresh_len) =>
              if refresh_len > 0 then let
                val () = _dropbox_chosen(refresh, refresh_len, access, access_len)
              in $P.ret<int>(0) end
              else let
                val () = $A.free<byte>(access)
                val () = $A.free<byte>(refresh)
              in $P.and_then<int><int>(_after_stores(moment), llam(_) => let
                  val () = _dropbox_failed(DropboxSignInRefused())
                in $P.ret<int>(0) end) end
            | ~DropboxRefused(status) =>
              $P.and_then<int><int>(_after_stores(moment), llam(_) => let
                val () = _dropbox_failed(if status = 0 then Unreachable() else DropboxSignInRefused())
              in $P.ret<int>(0) end))
        end
      end
    | ~NothingStored() => let
        val () = $A.free<byte>(code)
        val () = $A.free<byte>(state)
      in
        case+ moment of
        | AtStart() => $P.and_then<int><int>(_after_stores(moment), llam(_) => let
            val () = _dropbox_failed(DropboxSignInRefused())
          in $P.ret<int>(0) end)
        (* no sign-in under way while the app runs: a return already
           taken, opened again from the system's browser (its page kept
           or reloaded), is not a new sign-in, and nothing is said *)
        | WhileOpen() => $P.ret<int>(0)
      end
    | ~StoredUnreadable() => let
        val () = $A.free<byte>(code)
        val () = $A.free<byte>(state)
      in $P.and_then<int><int>(_after_stores(moment), llam(_) => let
          val () = _dropbox_failed(DropboxSignInRefused())
        in $P.ret<int>(0) end) end)
end

(* The address url[0, url_len) of Dropbox's sign-in page, opened: in the
   app, in the system browser's tab over it (Dropbox sends the reader
   back to the app's own address, sync_app_link); in a browser, the page
   left for it *)
fn _dropbox_page_open {l:agz}{url_len:pos | url_len <= REQUEST_URL_MAX} (url: $A.arr(byte, l, REQUEST_URL_MAX), url_len: int url_len): void = let
  val @(url_frozen, url_bytes) = $A.freeze<byte>(url)
  val @(used, rest) = $A.borrow_split<byte>(url_frozen, url_bytes, url_len)
in
  if _round_trip_available() then let
    val opening = $BT.browser_tab_open(used, url_len)
    val url_bytes = $A.borrow_join<byte>(url_frozen, used, rest)
    val () = release_bytes(url_frozen, url_bytes)
  in
    $P.finish<$BT.tab_opened>(opening, llam(opened) =>
      case+ opened of
      | $BT.TabOpened() => ()
      | $BT.TabNotOpened() => _ask_failed(DropboxSignInRefused()))
  end
  else let
    val left = $NAV.navigate_away(used, url_len)
    val url_bytes = $A.borrow_join<byte>(url_frozen, used, rest)
    val () = release_bytes(url_frozen, url_bytes)
  in if left then () else _ask_failed(DropboxSignInRefused()) end
end

(* Dropbox (the screen's button): the sign-in under way kept, then
   Dropbox's page opened, which sends the reader back to this page (in
   the app, to the app) with a code (PKCE: no secret in the app) *)
#pub fn sync_dropbox (): void
implement sync_dropbox () = let
  (* Dropbox's own page asks the rest, and the status card says how it
     went *)
  val () = _step_close()
  val key = $A.alloc<byte>(256)
  val key_len = sync_clients_dropbox(key)
in
  if key_len <= 0 then let
    val () = $A.free<byte>(key)
  in _ask_failed(DropboxNotSetUp()) end
  else let
    val secrets = dropbox_pkce()
    val redirect = $A.alloc<byte>(2100)
    val redirect_len = _redirect(redirect)
    val @(url, url_len) = dropbox_authorize_url(key, key_len, redirect, redirect_len, secrets)
    val () = $A.free<byte>(redirect)
    val () = $A.free<byte>(key)
    val record = $A.alloc<byte>(SIGN_IN_LEN)
    val+ @Pkce(verifier, _, state) = secrets
    val () = _bytes_from(verifier, 0, SIGN_IN_VERIFIER, record, 0)
    fun put {state_loc,record_loc:agz}{j:nat | j <= SIGN_IN_STATE} .<SIGN_IN_STATE - j>.
      (state: !$A.arr(byte, state_loc, 64), record: !$A.arr(byte, record_loc, SIGN_IN_LEN), j: int j): void =
      if j >= SIGN_IN_STATE then ()
      else let
        val () = $A.set<byte>(record, SIGN_IN_VERIFIER + j, $A.get<byte>(state, j))
      in put(state, record, j + 1) end
    val () = put(state, record, 0)
    prval () = fold@(secrets)
    val () = pkce_free(secrets)
    val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
    val @(key_frozen, key_bytes) = $A.freeze<byte>(_dropbox_sign_in_key())
    val saving = $IDB.idb_put(key_bytes, 20, record_bytes, SIGN_IN_LEN)
    val () = release_bytes(key_frozen, key_bytes)
    val () = release_bytes(record_frozen, record_bytes)
  in
    if url_len <= 0 then let
      val () = $A.free<byte>(url)
      (* ignored: nothing was sent, and the next sign-in writes it again *)
      val () = $P.finish<$IDB.stored>(saving, llam(_) => ())
    in _ask_failed(DropboxSignInRefused()) end
    else $P.finish<$IDB.stored>(saving, llam(status) =>
      case+ status of
      | $IDB.Stored() => _dropbox_page_open(url, url_len)
      | $IDB.NotStored() => let
          val () = $A.free<byte>(url)
        in _ask_failed(NoMemory()) end)
  end
end

(* How far sync_start is: still loading (a return from Dropbox's sign-in
   that the app is given waits for it), done, or done without the sync
   state, which leaves sync off this session (a return is dropped) *)
datatype start_state = StartUnderWay | Started | StartedUnreadable

val _start = ref<start_state>(StartUnderWay())

(* A return from Dropbox's sign-in taken: its code exchanged (the state
   checked), or why it signed no one in said *)
fn _returned_handle (returned: dropbox_return, moment: return_moment): $P.promise(int, $P.Chained) =
  case+ returned of
  | ~NotReturned() => _after_stores(moment)
  | ~ReturnedCode(code, code_len, state, state_len) => _dropbox_exchanged(code, code_len, state, state_len, moment)
  | ~ReturnedRefused(canceled) => let
    (* the sign-in under way is over *)
    val @(key_frozen, key_bytes) = $A.freeze<byte>(_dropbox_sign_in_key())
    val () = save_checked($IDB.idb_delete(key_bytes, 20))
    val () = release_bytes(key_frozen, key_bytes)
  in
    $P.and_then<int><int>(_after_stores(moment), llam(_) => let
      val () = _dropbox_failed(if canceled then DropboxSignInCanceled() else DropboxSignInRefused())
    in $P.ret<int>(0) end)
  end

(* A return the app was given, taken now that sync has started *)
fn _returned_pending (): void =
  case+ !_start of
  | StartUnderWay() => ()
  | StartedUnreadable() => _returned_free(_returned_swap(NotReturned()))
  (* ignored: the return's own chain says how it ended *)
  | Started() => $P.finish<int>(_returned_handle(_returned_swap(NotReturned()), WhileOpen()), llam(_) => ())

(* Whether link[0, n) is Dropbox's return to the app:
   "quire://oauth/dropbox", then its query or nothing *)
fn _dropbox_link {l:agz}{size,n:nat | n <= size} (link: !$A.arr(byte, l, size), n: int n): bool =
  if ~_name_at(link, n, 0, "quire://oauth/dropbox", 21, 0) then false
  else if n = 21 then true
  else _name_at(link, n, 21, "?", 1, 0)

implement sync_app_link (link) = let
  val n = $BD.blob_len(link)
in
  if n > 2048 then $BD.blob_free(link)
  else let
    val page = $A.alloc<byte>(2048)
    val () = $BD.blob_read(link, 0, page, n)
    val () = $BD.blob_free(link)
  in
    if ~_dropbox_link(page, n) then $A.free<byte>(page)
    else let
      (* the tab over the app went as the app came forward (its activity
         is singleTask, bats-lang/bridge#135) *)
      val () = _returned_free(_returned_swap(_returned_of(page, n)))
      val () = $A.free<byte>(page)
    in _returned_pending() end
  end
end

implement sync_start () = let
  (* a return from Dropbox's sign-in page, taken from the address *)
  val () = _dropbox_return_take()
  val @(state_frozen, state_bytes) = $A.freeze<byte>(_state_key())
  val state_pending = $IDB.idb_get(state_bytes, 10)
  val () = release_bytes(state_frozen, state_bytes)
  val state_read = $P.and_then<$IDB.lookup><bool>(state_pending, llam(found) => let
    val readable = (case+ lookup_bytes(found) of
      | ~NothingStored() => true
      | ~StoredUnreadable() => let val () = storage_unreadable(SyncStateRecord()) in false end
      | ~StoredBytes(record, n) =>
        if n < 20 then let val () = $A.free<byte>(record) in true end
        else let
          val () = !_device := _i32_at(record, 4)
          val () = !_last_minutes := _i32_at(record, 8)
          (* a sync the last run left under way did not end *)
          val () = !_last_result := (case+ _result_of_code(g0ofg1(_i32_at(record, 12))) of
            | Syncing() => NotSyncedYet()
            | GoogleAsking() => NotSyncedYet()
            | result => result)
          val () = !_last_status := _i32_at(record, 16)
          val () = $A.free<byte>(record)
        in true end): bool
  in $P.ret<bool>(readable) end)
  (* the clients are read first: Dropbox's key is needed to finish its
     sign-in, and Use Android is listed only when there are some *)
  val clients_read = $P.and_then<bool><bool>(state_read, llam(readable) =>
    $P.and_then<int><bool>(sync_clients_load(), llam(_) => $P.ret<bool>(readable)))
  (* a state that could not be read leaves sync off this session: a
     sync would save this device's state over it (its number, #174) *)
  val started = $P.and_then<bool><bool>(clients_read, llam(readable) =>
    if readable then $P.and_then<int><bool>(_returned_handle(_returned_swap(NotReturned()), AtStart()), llam(_) => $P.ret<bool>(true))
    else let
      val () = _returned_free(_returned_swap(NotReturned()))
    in $P.ret<bool>(false) end)
in
  (* ignored: each read in the chain deals with its own value (none read
     leaves sync off, as at its first run) *)
  $P.finish<bool>(started, llam(readable) => let
    val () = !_start := (if readable then Started() else StartedUnreadable())
    (* a return the app was given meanwhile *)
  in _returned_pending() end)
end

end (* #target wasm *)
