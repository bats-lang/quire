(* unreadable -- why a record could not be read, and what the reader can
   do about it (#374, P2-A of #293). Bridge's IndexedDB read says why it
   failed (browser_reason: the DOMException's name, decoded there once);
   this module turns that into the one datatype the screens match, and
   says which kinds have hope: only those a second read could change.

   A failure is a kind indexed by its sort, so a proof can be about one
   kind: HOPE(failure) has a constructor only for the kinds that have
   hope, and a Try again carries it (TryAgain), so a Try again for any
   other kind does not type-check. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"

(* The ways a read of the library failed *)
#pub datasort failure =
  | FTransient of ()        (* UnknownError: the operation failed for transient reasons unrelated to the database itself *)
  | FStorageBlocked of ()   (* SecurityError: no storage key can be obtained (a private window, site data blocked) *)
  | FNewerVersion of ()     (* VersionError: the stored database is newer than the code asked for *)
  | FAborted of ()          (* AbortError: the request was aborted *)
  | FNoReasonGiven of ()    (* the browser gave no error to name *)
  | FBytesUnreadable of ()  (* the bytes were read but could not be taken into memory, or are not a library *)
  | FUnexpected of ()       (* a name or an answer bridge does not recognise *)

(* Why a read failed, as the screens match it: a choice, copied freely
   (kinds are flat; failure_is is the same choice as a static fact, which
   a proof can be about) *)
#pub datatype failure_kind =
  | KindTransient
  | KindStorageBlocked
  | KindNewerVersion
  | KindAborted
  | KindNoReasonGiven
  | KindBytesUnreadable
  | KindUnexpected

#pub datatype failure_is(failure) =
  | IsTransient(FTransient) of ()
  | IsStorageBlocked(FStorageBlocked) of ()
  | IsNewerVersion(FNewerVersion) of ()
  | IsAborted(FAborted) of ()
  | IsNoReasonGiven(FNoReasonGiven) of ()
  | IsBytesUnreadable(FBytesUnreadable) of ()
  | IsUnexpected(FUnexpected) of ()

(* HOPE(kind): reading again could change the outcome. Only a transient
   failure has it. The decision, by research (#374):

   - UnknownError is the one name the IndexedDB specification defines as
     transient ("the operation failed for transient reasons unrelated to
     the database itself or not covered by any other error").
   - SecurityError (no storage key: a private window, site data blocked)
     and VersionError (the stored database is newer than the code) are
     states of the browser and of the stored data, which a second read
     in the same session finds as they were.
   - AbortError ("a request was aborted", specification section 3) is
     raised when a transaction is aborted: by abort(), or after a failed
     request nothing handled. Quire's read never aborts, so something
     else did, and nothing says that is transient: Dexie's page on
     AbortError says only that it "happens when the transaction was
     aborted" and gives no advice to retry; localForage reconnects and
     retries once, but only when a transaction cannot be created
     (InvalidStateError, NotFoundError), not on AbortError. So no
     source called it worth a retry: it has no hope, and the screen
     tells the reader to reopen Quire.
   - No error given, bytes that could not be taken and an unexpected
     name are unknown causes: an unknown cause has no known hope. *)
#pub dataprop HOPE(failure) =
  | HopeTransient(FTransient)

(* What the screen offers the reader: Try again, with the proof that the
   kind has hope; or nothing to press. The one match that makes the
   proof, total over the kinds *)
#pub datavtype remedy =
  | {f:failure} TryAgain of (HOPE(f) | failure_is(f))
  | NoRemedy of ()

#pub fn remedy_free (remedy: remedy): void

implement remedy_free (remedy) =
  case+ remedy of
  | ~TryAgain(pf | _) => let prval HopeTransient() = pf in () end
  | ~NoRemedy() => ()

#pub fn remedy_of (kind: failure_kind): remedy

implement remedy_of (kind) =
  case+ kind of
  | KindTransient() => TryAgain(HopeTransient() | IsTransient())
  | KindStorageBlocked() => NoRemedy()
  | KindNewerVersion() => NoRemedy()
  | KindAborted() => NoRemedy()
  | KindNoReasonGiven() => NoRemedy()
  | KindBytesUnreadable() => NoRemedy()
  | KindUnexpected() => NoRemedy()

(* Whether reading again could change the outcome *)
#pub datatype hope =
  | Hope
  | NoHope

#pub fn retry_hope (kind: failure_kind): hope

implement retry_hope (kind) =
  case+ remedy_of(kind) of
  | ~TryAgain(pf | _) => let prval HopeTransient() = pf in Hope() end
  | ~NoRemedy() => NoHope()

(* What an unexpected failure said, kept as text so that it is never
   lost: the bytes, how many are kept, and how many there were (a text
   over MAX_UNEXPECTED_TEXT is cut) *)
#define MAX_UNEXPECTED_TEXT 4096
stadef MAX_TEXT = 4096

#pub datavtype unexpected_text =
  | NoUnexpectedText of ()
  | {l:agz}{size:pos}{n:nat | n <= size} UnexpectedText of ($A.arr(byte, l, size), int n, int)

#pub fn unexpected_text_free (text: unexpected_text): void

implement unexpected_text_free (text) =
  case+ text of
  | ~NoUnexpectedText() => ()
  | ~UnexpectedText(bytes, _, _) => $A.free<byte>(bytes)

(* Why a read failed: the kind and, for an unexpected one, what it said *)
#pub datavtype failure_found =
  | FailureFound of (failure_kind, unexpected_text)

#pub fn failure_found_free (found: failure_found): void

implement failure_found_free (found) =
  case+ found of
  | ~FailureFound(_, text) => unexpected_text_free(text)

#pub fn failure_found_kind (found: !failure_found): failure_kind

implement failure_found_kind (found) =
  case+ found of
  | FailureFound(kind, _) => kind

(* A failure's own words, a literal *)
#pub fn unexpected_literal {n:pos | n < 256} (text: string n): unexpected_text

implement unexpected_literal (text) = let
  val n = g1u2i(string1_length(text))
  val bytes = $A.alloc<byte>(n)
  val () = $A.write_text(bytes, 0, $A.text_lit(text), n)
in UnexpectedText(bytes, n, n) end

fn _cut {n:pos} (n: int n): [k:pos | k <= n; k <= MAX_TEXT] int k =
  if n >= MAX_UNEXPECTED_TEXT then MAX_UNEXPECTED_TEXT else n

(* The text a blob holds (the name, a line feed, the message), the blob freed *)
fn _text_of_blob {n:nat} (blob: $BD.dblob(n)): unexpected_text = let
  val whole = $BD.blob_len(blob)
in
  if whole <= 0 then let val () = $BD.blob_free(blob) in NoUnexpectedText() end
  else let
    val kept = _cut(whole)
    val bytes = $A.alloc<byte>(kept)
    val () = $BD.blob_read(blob, 0, bytes, kept)
    val () = $BD.blob_free(blob)
  in UnexpectedText(bytes, kept, whole) end
end

fun _digits_put {l:agz}{at:pos | at <= 12} .<at>. (out: !$A.arr(byte, l, 12), at: int at, v: int): [start:nat | start < at] int start = let
  val rest = v - (v / 10) * 10
  val digit = (if rest < 0 then 0 - rest else rest): int
  val () = $A.set<byte>(out, at - 1, int2byte0(48 + digit))
in if at <= 1 then at - 1 else if v / 10 = 0 then at - 1 else _digits_put(out, at - 1, v / 10) end

fun _copy_digits {l,d:agz}{at:nat | at <= 48}{j:nat | j <= 12} .<12 - j>.
  (out: !$A.arr(byte, l, 48), at: int at, digits: !$A.arr(byte, d, 12), j: int j): [stop:nat | at <= stop; stop <= 48] int stop =
  if j >= 12 then at
  else if at >= 48 then at
  else let
    val () = $A.set<byte>(out, at, $A.get<byte>(digits, j))
  in _copy_digits(out, at + 1, digits, j + 1) end

fn _put_literal {l:agz}{n:pos}{at:nat | at <= 48}
  (out: !$A.arr(byte, l, 48), at: int at, text: string n): [stop:nat | at <= stop; stop <= 48] int stop = let
  val n = g1u2i(string1_length(text))
in
  if at + n > 48 then at
  else let
    val () = $A.write_text(out, at, $A.text_lit(text), n)
  in at + n end
end

fn _put_sign {l:agz}{at:nat | at <= 48}
  (out: !$A.arr(byte, l, 48), at: int at, negative: bool): [stop:nat | at <= stop; stop <= 48] int stop =
  if negative then _put_literal(out, at, "-") else at

fn _put_name {l:agz} (out: !$A.arr(byte, l, 48), which: $IDB.idb_unexpected): [stop:nat | stop <= 48] int stop =
  case+ which of
  | $IDB.UnknownCode() => _put_literal(out, 0, "UnknownCode ")
  | $IDB.UnclaimedHandle() => _put_literal(out, 0, "UnclaimedHandle ")

(* What an answer bridge does not recognise says: its name and the code, "UnknownCode 7" *)
fn _text_of_code (which: $IDB.idb_unexpected, code: int): unexpected_text = let
  val out = $A.alloc<byte>(48)
  val named = _put_name(out, which)
  val digits = $A.alloc<byte>(12)
  val start = _digits_put(digits, 12, code)
  val signed = _put_sign(out, named, code < 0)
  val stop = _copy_digits(out, signed, digits, start)
  val () = $A.free<byte>(digits)
in UnexpectedText(out, stop, stop) end

fn _of_reason (reason: $IDB.browser_reason): failure_found =
  case+ reason of
  | ~$IDB.Transient() => FailureFound(KindTransient(), NoUnexpectedText())
  | ~$IDB.StorageBlocked() => FailureFound(KindStorageBlocked(), NoUnexpectedText())
  | ~$IDB.NewerVersion() => FailureFound(KindNewerVersion(), NoUnexpectedText())
  | ~$IDB.Aborted() => FailureFound(KindAborted(), NoUnexpectedText())
  | ~$IDB.NoErrorGiven() => FailureFound(KindNoReasonGiven(), NoUnexpectedText())
  | ~$IDB.BrowserUnexpected(blob) => FailureFound(KindUnexpected(), _text_of_blob(blob))

(* Why bridge's read failed, decoded once and every case kept apart
   (no case is folded into another) *)
#pub fn failure_of_cause (cause: $IDB.unreadable_cause): failure_found

implement failure_of_cause (cause) =
  case+ cause of
  | ~$IDB.NoDatabase(reason) => _of_reason(reason)
  | ~$IDB.ReadFailed(reason) => _of_reason(reason)
  | ~$IDB.UnreadableUnexpected(which, code) => FailureFound(KindUnexpected(), _text_of_code(which, code))

end (* #target wasm *)
