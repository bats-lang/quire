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
staload BACKUP = "wasm.bats-packages.dev/bridge/src/backup_file.sats"
staload "drive.sats"
staload "sync_clients.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"

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
   access token kept only while the app runs (_token) *)
datavtype store =
  | NoStore of ()
  | {url_loc,user_loc,password_loc:agz}{url_len:pos | url_len <= URL_MAX}{user_len:nat | user_len <= USER_MAX}{password_len:nat | password_len <= PASSWORD_MAX}
    WebDav of ($A.arr(byte, url_loc, URL_MAX), int url_len, $A.arr(byte, user_loc, USER_MAX), int user_len,
               $A.arr(byte, password_loc, PASSWORD_MAX), int password_len)
  | {account_loc:agz}{account_len:nat | account_len <= ACCOUNT_MAX}
    Android of ($A.arr(byte, account_loc, ACCOUNT_MAX), int account_len)

fn _store_free (held: store): void =
  case+ held of
  | ~NoStore() => ()
  | ~WebDav(url, _, user, _, password, _) => let
      val () = $A.free<byte>(url)
      val () = $A.free<byte>(user)
    in $A.free<byte>(password) end
  | ~Android(account, _) => $A.free<byte>(account)

val _store = ref<store>(NoStore())
(* The store turned off, while its Undo is offered *)
val _store_off = ref<store>(NoStore())

fn _store_swap (cell: ref(store), held: store): store = let
  var previous: store = held
  val () = ref_exch_elt<store>(cell, previous)
in previous end

fn _store_on (): bool = let
  val held = _store_swap(_store, NoStore())
  val configured = (case+ held of WebDav(_, _, _, _, _, _) => true | Android(_, _) => true | NoStore() => false): bool
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
   registered for this app), the reader said no *)
datatype sync_result =
  | NotSyncedYet | Synced | Unreachable | WrongCredentials | FolderNotFound | KeptChanging | ServerError
  | TooLarge | Damaged | NoMemory | Blocked | Syncing | NoAddress
  | SignInAgain | NoGoogleAccount | NotSetUp | GoogleRefused | SignInCanceled

(* A result as "sync-state" stores it, and back: decoded once, as it is
   read (an unknown number is not synced yet) *)
fn _result_code (result: sync_result): [code:nat | code <= 17] int code =
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
  else NotSyncedYet()

(* How the last sync ended *)
val _last_result = ref<sync_result>(NotSyncedYet())

(* The store chosen, under "sync": "QS2\n" and its kind's byte
   (_kind_code); each kind's credentials under a key of its own,
   "sync-webdav", "sync-android". With none chosen, the app keeps the
   file for Android's Auto Backup (BackupKind): the merge is written
   to a backed-up file, and the file a reinstall restored is merged *)
datatype store_kind = WebDavKind | AndroidKind | BackupKind | NoStoreKind

fn _kind_code (kind: store_kind): [code:nat | code <= 3] int code =
  case+ kind of WebDavKind() => 1 | AndroidKind() => 2 | BackupKind() => 3 | NoStoreKind() => 0

fn _kind_of_code (code: int): store_kind =
  if code = 1 then WebDavKind() else if code = 2 then AndroidKind() else if code = 3 then BackupKind() else NoStoreKind()

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

(* The store's kind: the one chosen, else the backed-up file where the
   app has one (BackupKind), else none *)
fn _store_kind (): store_kind = let
  val held = _store_swap(_store, NoStore())
  val kind = (case+ held of WebDav(_, _, _, _, _, _) => WebDavKind() | Android(_, _) => AndroidKind() | NoStore() => NoStoreKind()): store_kind
  val () = _store_free(_store_swap(_store, held))
in
  case+ kind of
  | NoStoreKind() => if $BACKUP.backup_file_available() then BackupKind() else NoStoreKind()
  | WebDavKind() => kind
  | AndroidKind() => kind
  | BackupKind() => kind
end

(* Whether a sync runs: to a store chosen, or to the backed-up file *)
fn _syncing (): bool = case+ _store_kind() of NoStoreKind() => false | WebDavKind() => true | AndroidKind() => true | BackupKind() => true

(* Whether the store is the Android one *)
fn _is_android (): bool = case+ _store_kind() of AndroidKind() => true | WebDavKind() => false | BackupKind() => false | NoStoreKind() => false

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

(* No store chosen, and the WebDAV credentials and the Android account
   forgotten *)
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
in release_bytes(android_frozen, android_bytes) end

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
  | SignInAgain() => _put_literal(out, position, "Tap Sync now to sign in to Google again.")
  | NoGoogleAccount() => _put_literal(out, position, "Android sync needs a Google account on this device.")
  | NotSetUp() =>
    if $BAPP.is_native_platform() then _put_literal(out, position, "Android sync isn't set up in this build of Quire.")
    else _put_literal(out, position, "Google Drive sync isn't set up in this build of Quire.")
  | GoogleRefused() => _put_literal(out, position, "Google refused: this build of Quire isn't registered with it.")
  | SignInCanceled() => _put_literal(out, position, "Google sign-in was canceled.")
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
  | NotSyncedYet() => false | Synced() => false | Unreachable() => false | WrongCredentials() => false
  | FolderNotFound() => false | KeptChanging() => false | ServerError() => false | TooLarge() => false
  | Damaged() => false | NoMemory() => false | Blocked() => false | Syncing() => false | NoAddress() => false
  | SignInAgain() => false

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
  | SignInAgain() => _put_literal(out, position, "tap Sync now to sign in")
  | GoogleRefused() => _put_literal(out, position, "Google refused")
  | NoGoogleAccount() => _put_literal(out, position, "No Google account")
  | NotSetUp() => _put_literal(out, position, "Not set up in this build")
  | SignInCanceled() => _put_literal(out, position, "Sign-in canceled")
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
  if ~_store_on() then _put_literal(out, 0, "Off")
  else let
    val after = (if ~_is_android() then _put_literal(out, 0, "WebDAV \xC2\xB7 ")
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
    | SignInAgain() => _result_short(out, 0, result, !_last_status)
    | NoGoogleAccount() => _result_short(out, 0, result, !_last_status)
    | NotSetUp() => _result_short(out, 0, result, !_last_status)
    | GoogleRefused() => _result_short(out, 0, result, !_last_status)
    | SignInCanceled() => _result_short(out, 0, result, !_last_status)
  end
end

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
  val () = ui_text_buf("sync-status", out, stop)
in sync_summary_show() end

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

(* The WebDAV store's file's URL in url and the Authorization header in
   authorization: their lengths *)
fn _request_parts {url_loc,authorization_loc:agz}
  (url: !$A.arr(byte, url_loc, 1041), authorization: !$A.arr(byte, authorization_loc, 700))
  : [url_len:pos | url_len <= 1041][authorization_len:nat | authorization_len <= 700] @(int url_len, int authorization_len) =
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => let val _ = _put_literal(url, 0, "/") in @(1, 0) end
  | ~Android(account, account_len) => let
      val _ = _put_literal(url, 0, "/")
      val () = _store_free(_store_swap(_store, Android(account, account_len)))
    in @(1, 0) end
  | ~WebDav(folder, folder_len, user, user_len, password, password_len) => let
      val url_len = _file_url(folder, folder_len, url)
      val authorization_len = _authorization(user, user_len, password, password_len, authorization)
      val () = _store_free(_store_swap(_store, WebDav(folder, folder_len, user, user_len, password, password_len)))
    in @(url_len, authorization_len) end

(* The WebDAV store's file's URL in out: its length, 0 for none *)
fn _store_url {l:agz} (out: !$A.arr(byte, l, 1041)): [length:nat | length <= 1041] int length =
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => 0
  | ~Android(account, account_len) => let
      val () = _store_free(_store_swap(_store, Android(account, account_len)))
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

(* Sends method for the file, with body[0, body_len) (none when 0), and
   If-Match the ETag read when with_match; the promise resolves as
   fetch's does *)
fn _send {method_len:pos | method_len <= 16}{body_loc:agz}{body_size:nat}{body_len:nat | body_len <= body_size}
  (method: string method_len, body: !$A.borrow(byte, body_loc, body_size), body_len: int body_len, with_match: bool): $P.promise($FE.fetched, $P.Chained) = let
  val method_len = g1u2i(string1_length(method))
  val method_bytes = $A.alloc<byte>(method_len)
  val () = $A.write_text(method_bytes, 0, $A.text_lit(method), method_len)
  val url = $A.alloc<byte>(1041)
  val authorization = $A.alloc<byte>(700)
  val @(url_len, authorization_len) = _request_parts(url, authorization)
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

(* What a status a store refused with says: the credentials, the place
   the file is kept, or the server *)
fn _failure_kind (answer: http_answer): sync_result =
  case+ answer of
  | HttpRefused() => WrongCredentials()
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
fn _read_failed {n:nat}{l:agz} (body: $BD.dblob(n), etag: $A.arr(byte, l, ETAG_MAX), status: Int): read_answer = let
  val () = $BD.blob_free(body)
  val () = $A.free<byte>(etag)
in ReadFailed(_failure_kind(_http_answer(status)), status) end

(* WebDAV: GET the file; its ETag is its version, and 404 is no file yet *)
fn _webdav_read (): $P.promise(read_answer, $P.Chained) = let
  val empty = $A.alloc<byte>(1)
  val @(empty_frozen, empty_bytes) = $A.freeze<byte>(empty)
  val pending = _send("GET", empty_bytes, 0, false)
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
        | HttpRefused() => _read_failed(body, etag, status)
        | HttpNoFolder() => _read_failed(body, etag, status)
        | HttpChanged() => _read_failed(body, etag, status)
        | HttpOther() => _read_failed(body, etag, status))): read_answer
  in $P.ret<read_answer>(answer) end)
end

(* WebDAV: PUT the file, If-Match the ETag read (unconditional when
   there was none); 412 is a conflict *)
fn _webdav_write {body_loc:agz}{body_size:pos}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(write_answer, $P.Chained) = let
  val pending = _send("PUT", body, body_size, true)
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
          | HttpRefused() => WriteFailed(WrongCredentials(), status)
          | HttpNotFound() => WriteFailed(FolderNotFound(), status)
          | HttpNoFolder() => WriteFailed(FolderNotFound(), status)
          | HttpOther() => WriteFailed(ServerError(), status)
        end): write_answer
  in $P.ret<write_answer>(answer) end)
end

(* The access token for the Android store's account: asked for when the
   reader acts (Use Android, Sync now), kept only while the app runs,
   and forgotten when Drive refuses it (it lasts about an hour). A sync
   the app starts by itself never asks for one: asking shows Google's
   sheet *)
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

(* What a Drive status says: 401 is a token Drive no longer takes (it is
   forgotten), -1 to -3 drive.bats' own *)
fn _drive_failure (status: Int): sync_result =
  if status = 401 then let
    val () = _token_free(_token_swap(NoToken()))
  in SignInAgain() end
  else if status = 0 then Unreachable()
  else if status = ~1 then TooLarge()
  else if status = ~2 then NoMemory()
  else if status = ~3 then Damaged()
  else if status = 403 then GoogleRefused()
  else ServerError()

(* The Android store: the file in the account's Drive *)
fn _android_read (): $P.promise(read_answer, $P.Chained) =
  case+ _token_swap(NoToken()) of
  | ~NoToken() => $P.ret<read_answer>(ReadFailed(SignInAgain(), 0))
  | ~Token(token, token_len) => let
      val pending = drive_read(token, token_len, SYNC_MAX_BYTES)
      val () = _token_free(_token_swap(Token(token, token_len)))
    in
      $P.and_then<drive_got><read_answer>(pending, llam(got) =>
        case+ got of
        | ~DriveGot(owner, file, n) => $P.ret<read_answer>(ReadFile(owner, file, n))
        | ~DriveNothing() => $P.ret<read_answer>(ReadNothing())
        | ~DriveFailed(status) => $P.ret<read_answer>(ReadFailed(_drive_failure(status), status)))
    end

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
        | ~DrivePutFailed(status) => $P.ret<write_answer>(WriteFailed(_drive_failure(status), status)))
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

(* Reads the file from the store *)
fn store_read (): $P.promise(read_answer, $P.Chained) =
  case+ _store_kind() of
  | WebDavKind() => _webdav_read()
  | AndroidKind() => _android_read()
  | BackupKind() => _backup_read()
  | NoStoreKind() => $P.ret<read_answer>(ReadFailed(NotSyncedYet(), 0))

(* Writes body[0, body_size) to the store, as a change of the version
   read; once a store's write is done, the app's backed-up file is
   written too, for Auto Backup *)
fn store_write {body_loc:agz}{body_size:pos}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(write_answer, $P.Chained) = let
  val kind = _store_kind()
  val backed_up = (case+ kind of WebDavKind() => true | AndroidKind() => true | BackupKind() => false | NoStoreKind() => false): bool
  val () = (if ~backed_up then ()
    else if ~$BACKUP.backup_file_available() then ()
    (* ignored: the backed-up file is a safety net; one not written
       now is written at the next sync *)
    else $P.finish<write_answer>(_backup_write(body, body_size), llam(_) => ()))
in
  case+ kind of
  | WebDavKind() => _webdav_write(body, body_size)
  | AndroidKind() =>
    if body_size > 16777216 then $P.ret<write_answer>(WriteFailed(TooLarge(), 0)) else _android_write(body, body_size)
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
(* The further place offered for it: chapter (-1 none), page, anchor *)
val _further_chapter = ref<Int>(~1)
val _further_page = ref<Int>(0)
val _further_anchor = ref<Int>(~1)
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

(* Offers the open book's further place: the toast's button names its
   chapter *)
fn _offer (chapter: Int, page: Int, anchor: Int): void = let
  val () = !_further_chapter := chapter
  val () = !_further_page := page
  val () = !_further_anchor := anchor
  val label = $A.alloc<byte>(64)
  val after = _put_literal(label, 0, "Go to the furthest place (chapter ")
  val chapter_number = (if chapter >= 0 then chapter + 1 else 1): Int
  val after = $S.int_to_str(label, after, 64, chapter_number)
  val after = _put_literal(label, after, ")")
  val () = ui_text_buf("sync-go", label, after)
in ui_show("sync-toast", true) end

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

(* The file's numbers of the book id_high, id_low, taken: a library
   book's merged with its own (the open book's place offered, not
   taken); one this device does not have, kept for when it is imported *)
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
        val further = backup_numbers_further(numbers, own)
        val @(chapter, page, anchor) = backup_numbers_place(numbers)
        val () = (if is_open then (if further then _offer(chapter, page, anchor) else ()) else ())
        val () = backup_numbers_merge(own, numbers, is_open)
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

(* Syncs, when sync is on: at once, or once the sync under way ends *)
#pub fn sync_run (): void
implement sync_run () =
  if ~_syncing() then ()
  else if !_busy then !_again := true
  else let
    val () = _run_begin()
  in _rounds(ROUNDS_MOST) end

(* Reads the state and the store kept, then syncs (when sync is on):
   once the library is read *)
#pub fn sync_start (): void
implement sync_start () = let
  (* ignored: the clients are read for Use Android, which says it is not
     set up while there are none *)
  val () = $P.finish<int>(sync_clients_load(), llam(_) => ())
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
            | result => result)
          val () = !_last_status := _i32_at(record, 16)
          val () = $A.free<byte>(record)
        in true end): bool
  in $P.ret<bool>(readable) end)
in
  (* ignored: each read in the chain deals with its own value (none read
     leaves sync off, as at its first run) *)
  $P.finish<int>($P.and_then<bool><int>(state_read, llam(readable) =>
    (* a state that could not be read leaves sync off this session: a
       sync would save this device's state over it (its number, #174) *)
    if ~readable then $P.ret<int>(0)
    else let
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
  end), llam(_) => ())
end

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
in ui_show("sync-toast", false) end

(* The further place offered, taken (the toast's button): its chapter
   (-1 when none is offered), page and anchor *)
#pub fn sync_further_take (): @(Int, Int, Int)
implement sync_further_take () = let
  val chapter = !_further_chapter
  val () = !_further_chapter := ~1
  val () = ui_show("sync-toast", false)
in @(chapter, !_further_page, !_further_anchor) end

(* The toast dismissed: the place stays *)
#pub fn sync_further_dismiss (): void
implement sync_further_dismiss () = let
  val () = !_further_chapter := ~1
in ui_show("sync-toast", false) end

(* The screen's fields, empty: the folder's URL, the user name and the
   password (made again to be emptied) *)
fn _fields_make (): void = let
  val () = ui_clear("sync-fields")
  val () = ui_field("sync-fields", "sync-url", FUrl, "mname", "Folder URL")
  val () = ui_field("sync-fields", "sync-user", FUser, "mname", "User name")
in ui_field("sync-fields", "sync-password", FPassword, "mname", "Password") end

(* The sync screen: what sync keeps the same, the WebDAV folder's URL,
   user name and password (kept on this device only), how the last sync
   went, and Turn off, Sync now and Done; and the toast that offers the
   open book's further place *)
#pub fn sync_screen_make (): void
implement sync_screen_make () = let
  val () = ui_el("bats-root", "sync-screen", TDiv, "info")
  val () = ui_labelled("sync-screen", NDialog, "sync-title")
  val () = ui_el("sync-screen", "sync-box", TDiv, "info-in")
  val () = ui_el("sync-box", "sync-title", TDiv, "mtitle")
  val () = ui_text("sync-title", "Sync")
  val () = ui_el("sync-box", "sync-about", TDiv, "sabout")
  val () = ui_text_long("sync-about", "Keeps your places, shelves, collections, highlights, notes and reading time the same on your devices, through a file in a WebDAV folder (Nextcloud, ownCloud, a NAS). Use an app password if your server offers one: it is kept on this device only, never in a backup. Your books' files are not synced.")
  val () = ui_el("sync-box", "sync-android-row", TDiv, "sfields")
  val () = ui_text_btn("sync-android-row", "sync-android", "btn", "Use Android")
  val () = ui_text_btn("sync-android-row", "sync-google", "btn", "Google Drive")
  val () = ui_el("sync-android-row", "sync-android-about", TDiv, "sabout")
  val () = ui_show("sync-android-row", false)
  val () = ui_el("sync-box", "sync-fields", TDiv, "sfields")
  val () = _fields_make()
  val () = ui_el("sync-box", "sync-status", TDiv, "cnone")
  val () = ui_role("sync-status", RStatus)
  val () = ui_el("sync-box", "sync-buttons", TDiv, "mbtns")
  val () = ui_text_btn("sync-buttons", "sync-off", "btn", "Turn off")
  val () = ui_text_btn("sync-buttons", "sync-now", "btn btn-p", "Sync now")
  val () = ui_text_btn("sync-buttons", "sync-done", "btn", "Done")
  val () = ui_show("sync-screen", false)
  val () = ui_el("bats-root", "sync-toast", TDiv, "toast tup")
  val () = ui_role("sync-toast", RStatus)
  val () = ui_text_btn("sync-toast", "sync-go", "btn", "Go to the furthest place")
  val () = ui_icon_btn("sync-toast", "sync-toast-close", "ibtn", IcClose, "Dismiss")
in ui_show("sync-toast", false) end

(* The fields, made again, with what is kept *)
fn _fields_show (): void = let
  val () = _fields_make()
in
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => ()
  | ~Android(account, account_len) => _store_free(_store_swap(_store, Android(account, account_len)))
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

(* Opens the sync screen *)
#pub fn sync_screen_open (): void
implement sync_screen_open () = let
  (* Use Android in the app, Google Drive in a browser: what it does, or
     (in the app) that this build has no client to sign in with *)
  val app = $BAPP.is_native_platform()
  val client = $A.alloc<byte>(256)
  val client_len = sync_clients_google(client)
  val () = $A.free<byte>(client)
  (* in a browser, a build with no client lists no Google Drive, and
     Google's script is loaded only when there is one *)
  val android = (if app then $GOOGLE.google_token_available()
    else if client_len > 0 then $GOOGLE.google_token_available() else false): bool
  val () = ui_show("sync-android-row", android)
  val () = ui_show("sync-android", app)
  val () = ui_show("sync-google", ~app)
  val () = (if ~android then ()
    else if client_len <= 0 then ui_text_long("sync-android-about", "Android sync isn't set up in this build of Quire.")
    else if app then ui_text_long("sync-android-about", "Syncs through the Google account on this phone, in a folder of its Google Drive that only Quire sees. The WebDAV folder below is the other way.")
    else ui_text_long("sync-android-about", "Syncs through your Google account, in a folder of its Google Drive that only Quire sees. Google signs you in for an hour at a time: after that, Sync now asks again. The WebDAV folder below is the other way."))
  val () = _fields_show()
  val () = _status_show()
  val () = ui_show("sync-off", _store_on())
  val () = layer_open(LSync())
in ui_focus("sync-url") end

(* length, or 0 when it is over most *)
fn _within {length:nat}{most:nat} (length: int length, most: int most): [kept:nat | kept <= length; kept <= most] int kept =
  if length <= most then length else 0

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

(* Whether text[0, text_len) starts with beginning *)
fun _starts {l:agz}{n:nat}{text_len:nat | text_len <= n}{beginning_len:nat}{j:nat | j <= beginning_len} .<beginning_len - j>.
  (text: !$A.arr(byte, l, n), text_len: int text_len, beginning: string beginning_len, beginning_len: int beginning_len, j: int j): bool =
  if j >= beginning_len then true
  else if j >= text_len then false
  else if byte2int0($A.get<byte>(text, j)) <> char2int0(string_get_at(beginning, j)) then false
  else _starts(text, text_len, beginning, beginning_len, j + 1)

(* What asking for a token came to: the account's address (the token is
   kept, in _token), or how it failed (a sync_result) *)
datavtype asked =
  | {l:agz}{account_len:nat | account_len <= ACCOUNT_MAX} Asked of ($A.arr(byte, l, ACCOUNT_MAX), int account_len)
  | AskFailed of (sync_result)

implement $P.dispose<asked>(answer) =
  case+ answer of
  | ~Asked(account, _) => $A.free<byte>(account)
  | ~AskFailed(_) => ()

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
  else let val () = _token_free(_token_swap(Token(token, token_len))) in true end
end

(* Asks Google for a token for drive.appdata, for the account on the
   device: its sheet the first time, its consent the first time ever.
   Only when the reader acts (Use Android, Sync now) *)
fn _token_ask (): $P.promise(asked, $P.Chained) = let
  val client = $A.alloc<byte>(256)
  val client_len = sync_clients_google(client)
in
  if client_len <= 0 then let
    val () = $A.free<byte>(client)
  in $P.ret<asked>(AskFailed(NotSetUp())) end
  else let
    val scope = $A.alloc<byte>(45)
    val () = $A.write_text(scope, 0, $A.text_lit("https://www.googleapis.com/auth/drive.appdata"), 45)
    val @(scope_frozen, scope_bytes) = $A.freeze<byte>(scope)
    val @(client_frozen, client_bytes) = $A.freeze<byte>(client)
    val @(client_used, client_rest) = $A.borrow_split<byte>(client_frozen, client_bytes, client_len)
    val pending = $GOOGLE.google_token_get(client_used, client_len, scope_bytes, 45)
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
end

(* A sign-in that failed, said on the screen *)
fn _ask_failed (result: sync_result): void = let
  val () = !_last_result := result
  val () = !_last_status := 0
  val () = !_last_minutes := $TM.epoch_minutes()
in _status_show() end

(* The Android store with the account signed in, chosen and kept, then
   a sync *)
fn _android_chosen {l:agz}{account_len:nat | account_len <= ACCOUNT_MAX} (account: $A.arr(byte, l, ACCOUNT_MAX), account_len: int account_len): void = let
  val () = _store_free(_store_swap(_store, Android(account, account_len)))
  val () = _store_save()
  (* not synced to it yet: a sync of the backed-up file's does not count *)
  val () = !_last_result := NotSyncedYet()
  val () = (if layer_is_open(LSync()) then let
      val () = _fields_show()
    in ui_show("sync-off", true) end else ())
in sync_run() end

(* Use Android (the screen's button, in the app): Google's sheet for the
   account on the device, then sync through its Drive *)
#pub fn sync_android (): void
implement sync_android () =
  if ~$GOOGLE.google_token_available() then ()
  else $P.finish<asked>(_token_ask(), llam(answer) =>
    case+ answer of
    | ~Asked(account, account_len) => _android_chosen(account, account_len)
    | ~AskFailed(result) => _ask_failed(result))

(* Sync now with the Android store: with the token kept, or one asked
   for (Google's sheet) *)
fn _android_now (): void = let
  val held = _token_swap(NoToken())
  val have = (case+ held of Token(_, _) => true | NoToken() => false): bool
  val () = _token_free(_token_swap(held))
in
  if have then sync_run()
  else $P.finish<asked>(_token_ask(), llam(answer) =>
    case+ answer of
    | ~Asked(account, account_len) => _android_chosen(account, account_len)
    | ~AskFailed(result) => _ask_failed(result))
end

(* Sync now (the screen's button): the fields kept, then a sync *)
#pub fn sync_now (): void
implement sync_now () = let
  val @(url, url_len) = _field_value("sync-url", URL_MAX)
  val @(user, user_len) = _field_value("sync-user", USER_MAX)
  val @(password, password_len) = _field_value("sync-password", PASSWORD_MAX)
  val web = (if _starts(url, url_len, "https://", 8, 0) then true else _starts(url, url_len, "http://", 7, 0)): bool
in
  if url_len <= 0 then let
    val () = $A.free<byte>(url)
    val () = $A.free<byte>(user)
    val () = $A.free<byte>(password)
  in
    (* no folder given: the Android store's sync, when it is the one *)
    if _is_android() then _android_now()
    else let
      val () = !_last_result := NoAddress()
    in _status_show() end
  end
  else if ~web then let
    val () = $A.free<byte>(url)
    val () = $A.free<byte>(user)
    val () = $A.free<byte>(password)
    val () = !_last_result := NoAddress()
  in _status_show() end
  else let
    val () = _store_free(_store_swap(_store, WebDav(url, url_len, user, user_len, password, password_len)))
    val () = _store_save()
    val () = ui_show("sync-off", true)
    (* not synced to it yet, while a sync of the backed-up file's ends *)
    val () = (if !_busy then !_last_result := NotSyncedYet() else ())
  in sync_run() end
end

(* Turn off (the screen's button): the folder, user name and password
   forgotten at once (they are kept only for the Undo offered) *)
#pub fn sync_off (): void
implement sync_off () =
  case+ _store_swap(_store, NoStore()) of
  | ~NoStore() => ()
  | ~Android(account, account_len) => let
      val () = _store_free(_store_swap(_store_off, Android(account, account_len)))
      val () = _store_forget()
      val () = _token_free(_token_swap(NoToken()))
      (* ignored: signed out or not, the token is forgotten here, and
         the next Use Android asks again *)
      val () = $P.finish<$GOOGLE.google_signed_out>($GOOGLE.google_sign_out(), llam(_) => ())
      val () = _fields_show()
      val () = _status_show()
      val () = ui_show("sync-off", false)
    in
      $P.finish<settled>(undo_offer("Sync turned off"), llam(how) =>
        case+ how of
        | Undone() => let
            val () = _store_free(_store_swap(_store, _store_swap(_store_off, NoStore())))
            val () = _store_save()
          in
            if layer_is_open(LSync()) then let
              val () = _fields_show()
              val () = ui_show("sync-off", true)
            in _status_show() end else ()
          end
        | Final() => _store_free(_store_swap(_store_off, NoStore())))
    end
  | ~WebDav(url, url_len, user, user_len, password, password_len) => let
      val () = _store_free(_store_swap(_store_off, WebDav(url, url_len, user, user_len, password, password_len)))
      val () = _store_forget()
      val () = _fields_show()
      val () = _status_show()
      val () = ui_show("sync-off", false)
    in
      $P.finish<settled>(undo_offer("Sync turned off"), llam(how) =>
        case+ how of
        | Undone() => let
            val () = _store_free(_store_swap(_store, _store_swap(_store_off, NoStore())))
            val () = _store_save()
          in
            if layer_is_open(LSync()) then let
              val () = _fields_show()
              val () = ui_show("sync-off", true)
            in _status_show() end else ()
          end
        | Final() => _store_free(_store_swap(_store_off, NoStore())))
    end

end (* #target wasm *)
