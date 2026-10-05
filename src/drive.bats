(* drive -- the sync file in Google Drive's app data folder (#184)

   The file quire-sync.json in the app data folder of the reader's
   Google Drive (appDataFolder: hidden, quire's own, the scope
   drive.appdata), read and written with an access token through
   bridge's fetch. A read lists the folder for the file (its id and
   version), then gets its bytes. A write is a change of the version
   read: when the file's version is no longer the one read, another
   device wrote it meanwhile (DriveChanged); else its bytes are
   replaced. With no file read, the file is made. Drive's API has no
   conditional write, so the check and the write are two requests:
   a write made between them by another device is lost to the next
   sync's merge, never to the file's shape. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "book.sats"
staload "mem.sats"
staload "jsonio.sats"
staload "web_request.sats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A file id's and a version's most bytes *)
#define ID_MAX 128
#define VERSION_MAX 32
(* A listing's (or a version's) most bytes *)
#define LISTING_MAX 65536
(* An access token's most bytes *)
#define TOKEN_MAX 4096
(* A URL's and the headers' most bytes *)
#define URL_MAX 1024
#define HEADERS_MAX 4600

(* ============================================================
   What a read and a write come to
   ============================================================ *)

(* The file read (its bytes in a piece), none yet, or how it failed:
   the server's status, 0 when no response came, -1 too large, -2 out
   of memory, -3 an answer that is not Drive's *)
#pub datavtype drive_got =
  | {owner,l:agz}{n:pos | n <= 268435456} DriveGot of (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int n)
  | DriveNothing of ()
  | DriveFailed of (Int)

(* The file written, changed by another device since it was read, or
   how the write failed (as DriveFailed's) *)
#pub datavtype drive_put = DrivePut of () | DriveChanged of () | DrivePutFailed of (Int)

#define TOO_LARGE ~1
#define MEMORY ~2
#define NOT_UNDERSTOOD ~3

implement $P.dispose<drive_got>(got) =
  case+ got of
  | ~DriveGot(owner, file, _) => piece_free(owner, file)
  | ~DriveNothing() => ()
  | ~DriveFailed(_) => ()

implement $P.dispose<drive_put>(put) =
  case+ put of
  | ~DrivePut() => ()
  | ~DriveChanged() => ()
  | ~DrivePutFailed(_) => ()

(* Reads the file, most bytes at most, with the access token
   token[0, token_len) *)
#pub fn drive_read {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= 4096}{most:pos | most <= 268435456}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len, most: int most): $P.promise(drive_got, $P.Chained)

(* Writes body[0, body_size) as the file, a change of the version read *)
#pub fn drive_write {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= 4096}{body_loc:agz}{body_size:pos | body_size <= 16777216}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len,
   body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(drive_put, $P.Chained)

(* The file read: its id and version, kept from the read for the write *)
datavtype drive_file =
  | NoDriveFile of ()
  | {id_loc,version_loc:agz}{id_len:pos | id_len <= ID_MAX}{version_len:nat | version_len <= VERSION_MAX}
    DriveFile of ($A.arr(byte, id_loc, ID_MAX), int id_len, $A.arr(byte, version_loc, VERSION_MAX), int version_len)

fn _file_free (file: drive_file): void =
  case+ file of
  | ~NoDriveFile() => ()
  | ~DriveFile(id, _, version, _) => let
      val () = $A.free<byte>(id)
    in $A.free<byte>(version) end

val _file = ref<drive_file>(NoDriveFile())

fn _file_swap (file: drive_file): drive_file = let
  var previous: drive_file = file
  val () = ref_exch_elt<drive_file>(_file, previous)
in previous end

(* The headers: the token as Authorization, and content_type (none when
   empty) as Content-Type *)
fn _headers {token_loc:agz}{token_size:nat}{token_len:nat | token_len <= token_size; token_len <= TOKEN_MAX}{type_len:nat | type_len <= 100}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len, content_type: string type_len)
  : [l:agz][headers_len:nat | headers_len <= HEADERS_MAX] @($A.arr(byte, l, HEADERS_MAX), int headers_len) = let
  val headers = $A.alloc<byte>(HEADERS_MAX)
  val after = request_text(headers, 0, "Authorization: Bearer ")
  val () = request_copy(token, token_len, headers, after, 0)
  val after = after + token_len
  val type_len = g1u2i(string1_length(content_type))
in
  if type_len <= 0 then @(headers, after)
  else let
    val after = request_text(headers, after, "\nContent-Type: ")
    val () = $A.write_text(headers, after, $A.text_lit(content_type), type_len)
  in @(headers, after + type_len) end
end

(* ============================================================
   Reading Drive's JSON
   ============================================================ *)

(* The string at position (a member's value), into out *)
fn _string_at {l,out_loc:agz}{owner:addr}{n:nat}{at:int | ~1 <= at; at < n}{capacity:nat}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, at: int at, out: !$A.arr(byte, out_loc, capacity), capacity: int capacity)
  : [length:nat | length <= capacity] @(bool, int length) =
  if at < 0 then @(false, 0)
  else let
    val @(found, length, _) = jr_str(buf, n, at, out, capacity)
  in @(found, length) end

(* A listing of the folder for the file: its first file (id and
   version), none, or (false) not a listing *)
fn _listed_by {l,key_loc:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n, key: !$A.arr(byte, key_loc, 16)): @(bool, drive_file) = let
  val members = (if n > 0 then jr_object(buf, n, 0) else ~1): [inside:int | ~1 <= inside; inside <= n] int inside
  val files_at = (if members >= 0 then jr_member(buf, n, members, key, "files") else ~1): [at:int | ~1 <= at; at < n] int at
  val listed = (if files_at < 0 then @(false, NoDriveFile())
    else if ~jr_is(buf, n, files_at, 91) then @(false, NoDriveFile())
    else let
      val first = jr_ws(buf, n, files_at + 1)
    in
      if first >= n then @(false, NoDriveFile())
      else if jr_is(buf, n, first, 93) then @(true, NoDriveFile())
      else if ~jr_is(buf, n, first, 123) then @(false, NoDriveFile())
      else let
        val id_at = jr_member(buf, n, first + 1, key, "id")
        val version_at = jr_member(buf, n, first + 1, key, "version")
        val id = $A.alloc<byte>(ID_MAX)
        val @(id_found, id_len) = _string_at(buf, n, id_at, id, ID_MAX)
        val version = $A.alloc<byte>(VERSION_MAX)
        val @(_, version_len) = _string_at(buf, n, version_at, version, VERSION_MAX)
      in
        if ~id_found then let
          val () = $A.free<byte>(id)
          val () = $A.free<byte>(version)
        in @(false, NoDriveFile()) end
        else if id_len <= 0 then let
          val () = $A.free<byte>(id)
          val () = $A.free<byte>(version)
        in @(false, NoDriveFile()) end
        else @(true, DriveFile(id, id_len, version, version_len))
      end
    end): @(bool, drive_file)
in listed end

fn _listed {l:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n): @(bool, drive_file) = let
  val key = $A.alloc<byte>(16)
  val listed = _listed_by(buf, n, key)
  val () = $A.free<byte>(key)
in listed end

(* Where a file's metadata has its version *)
fn _version_at {l,key_loc:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n, key: !$A.arr(byte, key_loc, 16))
  : [at:int | ~1 <= at; at < n] int at = let
  val members = (if n > 0 then jr_object(buf, n, 0) else ~1): [inside:int | ~1 <= inside; inside <= n] int inside
in if members >= 0 then jr_member(buf, n, members, key, "version") else ~1 end

(* A file's version, from its metadata ({"version": "..."}), into out *)
fn _version_of {l,out_loc:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n, out: !$A.arr(byte, out_loc, VERSION_MAX))
  : [length:nat | length <= VERSION_MAX] @(bool, int length) = let
  val key = $A.alloc<byte>(16)
  val version_at = _version_at(buf, n, key)
  val () = $A.free<byte>(key)
in _string_at(buf, n, version_at, out, VERSION_MAX) end

(* Whether a[0, a_len) is b[0, b_len) *)
fun _same {a_loc,b_loc:agz}{a_size,b_size:nat}{a_len:nat | a_len <= a_size}{b_len:nat | b_len <= b_size}{j:nat | j <= a_len} .<a_len - j>.
  (a: !$A.arr(byte, a_loc, a_size), a_len: int a_len, b: !$A.arr(byte, b_loc, b_size), b_len: int b_len, j: int j): bool =
  if a_len <> b_len then false
  else if j >= a_len then true
  else if j >= b_len then false
  else if byte2int0($A.get<byte>(a, j)) <> byte2int0($A.get<byte>(b, j)) then false
  else _same(a, a_len, b, b_len, j + 1)

(* Whether a file's metadata gives the version version[0, version_len) *)
fn _unchanged {l,version_loc:agz}{owner:addr}{n:nat}{version_len:nat | version_len <= VERSION_MAX}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, version: !$A.arr(byte, version_loc, VERSION_MAX), version_len: int version_len): bool = let
  val now = $A.alloc<byte>(VERSION_MAX)
  val @(found, now_len) = _version_of(buf, n, now)
  val same = _same(now, now_len, version, version_len, 0)
  val () = $A.free<byte>(now)
in if found then same else false end

(* ============================================================
   The URLs
   ============================================================ *)

(* The listing of the app data folder for the file *)
fn _listing_url (): [l:agz] @($A.arr(byte, l, URL_MAX), [n:pos | n <= URL_MAX] int n) = let
  val url = $A.alloc<byte>(URL_MAX)
  val after = request_text(url, 0, "https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=name%3D%27quire-sync.json%27%20and%20trashed%3Dfalse&fields=files(id%2Cversion)&orderBy=createdTime")
in @(url, after) end

(* <before><id><after> *)
fn _id_url {id_loc:agz}{id_len:pos | id_len <= ID_MAX}{before_len,after_len:nat | before_len + after_len <= 200}
  (before: string before_len, id: !$A.arr(byte, id_loc, ID_MAX), id_len: int id_len, after: string after_len)
  : [l:agz] @($A.arr(byte, l, URL_MAX), [n:pos | n <= URL_MAX] int n) = let
  val url = $A.alloc<byte>(URL_MAX)
  val position = request_text(url, 0, before)
  val () = request_copy(id, id_len, url, position, 0)
  val stop = request_text(url, position + id_len, after)
in @(url, stop) end

(* ============================================================
   Read
   ============================================================ *)

(* The file's bytes, once its listing found it *)
fn _media {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= TOKEN_MAX}{most:pos | most <= 268435456}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len, most: int most): $P.promise(drive_got, $P.Chained) =
  case+ _file_swap(NoDriveFile()) of
  | ~NoDriveFile() => $P.ret<drive_got>(DriveNothing())
  | ~DriveFile(id, id_len, version, version_len) => let
      val @(url, url_len) = _id_url("https://www.googleapis.com/drive/v3/files/", id, id_len, "?alt=media")
      val () = _file_free(_file_swap(DriveFile(id, id_len, version, version_len)))
      val @(headers, headers_len) = _headers(token, token_len, "")
      val pending = request_send_empty("GET", url, url_len, headers, headers_len)
    in
      $P.and_then<$FE.fetched><drive_got>(pending, llam(got) =>
        case+ request_answered(got) of
        | ~Unanswered() => $P.ret<drive_got>(DriveFailed(0))
        | ~Answered(status, blob) =>
          if (if status < 200 then true else status >= 300) then let
            val () = $BD.blob_free(blob)
          in $P.ret<drive_got>(DriveFailed(status)) end
          else (case+ request_body(blob, most) of
            | ~BodyRead(owner, bytes, n) => $P.ret<drive_got>(DriveGot(owner, bytes, n))
            | ~BodyEmpty() => $P.ret<drive_got>(DriveNothing())
            | ~BodyFailed(why) => $P.ret<drive_got>(DriveFailed(why))))
    end

implement drive_read (token, token_len, most) = let
  val () = _file_free(_file_swap(NoDriveFile()))
  val @(url, url_len) = _listing_url()
  val @(headers, headers_len) = _headers(token, token_len, "")
  val pending = request_send_empty("GET", url, url_len, headers, headers_len)
  (* the token again, for the second request: the first's copy is in
     its headers, sent *)
  val again = $A.alloc<byte>(TOKEN_MAX)
  val () = request_copy(token, token_len, again, 0, 0)
  val listed = $P.and_then<$FE.fetched><drive_got>(pending, llam(got) =>
    case+ request_answered(got) of
    | ~Unanswered() => let val () = $A.free<byte>(again) in $P.ret<drive_got>(DriveFailed(0)) end
    | ~Answered(status, blob) =>
      if (if status < 200 then true else status >= 300) then let
        val () = $BD.blob_free(blob)
        val () = $A.free<byte>(again)
      in $P.ret<drive_got>(DriveFailed(status)) end
      else (case+ request_body(blob, LISTING_MAX) of
        | ~BodyFailed(why) => let val () = $A.free<byte>(again) in $P.ret<drive_got>(DriveFailed(why)) end
        | ~BodyEmpty() => let val () = $A.free<byte>(again) in $P.ret<drive_got>(DriveFailed(NOT_UNDERSTOOD)) end
        | ~BodyRead(owner, bytes, n) => let
            val @(understood, file) = _listed(bytes, n)
            val () = piece_free(owner, bytes)
          in
            if ~understood then let
              val () = _file_free(file)
              val () = $A.free<byte>(again)
            in $P.ret<drive_got>(DriveFailed(NOT_UNDERSTOOD)) end
            else let
              val () = _file_free(_file_swap(file))
              val media = _media(again, token_len, most)
              val () = $A.free<byte>(again)
            in media end
          end))
in listed end

(* ============================================================
   Write
   ============================================================ *)

(* Bytes copied to a piece, to be sent once an earlier request is
   answered *)
datavtype piece_made =
  | {owner,l:agz}{n:pos | n <= 268435456} PieceMade of (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int n)
  | PieceNone of ()

(* The multipart body that makes the file: its metadata (its name, in
   the app data folder), then body[0, body_size) *)
fn _made {body_loc:agz}{body_size:pos | body_size <= 16777216}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): piece_made = let
  val head = "--quire-sync-part\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{\"name\":\"quire-sync.json\",\"parents\":[\"appDataFolder\"]}\r\n--quire-sync-part\r\nContent-Type: application/json\r\n\r\n"
  val tail = "\r\n--quire-sync-part--\r\n"
  val head_len = g1u2i(string1_length(head))
  val tail_len = g1u2i(string1_length(tail))
  val size = head_len + body_size + tail_len
in
  case+ piece_new(size) of
  | ~NoPiece() => PieceNone()
  | ~Piece(owner, bytes) => let
      val () = $A.write_text(bytes, 0, $A.text_lit(head), head_len)
      val () = $A.write_borrow(bytes, head_len, body, body_size)
      val () = $A.write_text(bytes, head_len + body_size, $A.text_lit(tail), tail_len)
    in PieceMade(owner, bytes, size) end
end

(* body[0, body_size), copied *)
fn _copied {body_loc:agz}{body_size:pos | body_size <= 16777216}
  (body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): piece_made =
  case+ piece_new(body_size) of
  | ~NoPiece() => PieceNone()
  | ~Piece(owner, bytes) => let
      val () = $A.write_borrow(bytes, 0, body, body_size)
    in PieceMade(owner, bytes, body_size) end

(* The upload that makes the file *)
fn _created_url (): [l:agz] @($A.arr(byte, l, URL_MAX), [n:pos | n <= URL_MAX] int n) = let
  val url = $A.alloc<byte>(URL_MAX)
  val after = request_text(url, 0, "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id%2Cversion")
in @(url, after) end

fn _made_free (made: piece_made): void =
  case+ made of
  | ~PieceNone() => ()
  | ~PieceMade(owner, bytes, _) => piece_free(owner, bytes)

(* What a write's response came to *)
fn _put_answer (got: $FE.fetched): drive_put =
  case+ request_answered(got) of
  | ~Unanswered() => DrivePutFailed(0)
  | ~Answered(status, blob) => let
      val () = $BD.blob_free(blob)
    in if (if status >= 200 then status < 300 else false) then DrivePut() else DrivePutFailed(status) end

(* method for url[0, url_len) with the piece made as its body, of type
   content_type *)
fn _send_made {method_len:pos | method_len <= 8}{url_loc:agz}{url_len:pos | url_len <= URL_MAX}{token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= TOKEN_MAX}{type_len:nat | type_len <= 100}
  (method: string method_len, url: $A.arr(byte, url_loc, URL_MAX), url_len: int url_len,
   token: !$A.arr(byte, token_loc, token_size), token_len: int token_len, content_type: string type_len, made: piece_made)
  : $P.promise(drive_put, $P.Chained) =
  case+ made of
  | ~PieceNone() => let val () = $A.free<byte>(url) in $P.ret<drive_put>(DrivePutFailed(MEMORY)) end
  | ~PieceMade(owner, bytes, size) => let
      val @(headers, headers_len) = _headers(token, token_len, content_type)
      val @(frozen, borrowed) = $A.freeze<byte>(bytes)
      val pending = request_send(method, url, url_len, headers, headers_len, borrowed, size)
      val () = $A.drop<byte>(frozen, borrowed)
      val () = piece_free(owner, $A.thaw<byte>(frozen))
    in $P.and_then<$FE.fetched><drive_put>(pending, llam(got) => $P.ret<drive_put>(_put_answer(got))) end

implement drive_write (token, token_len, body, body_size) =
  case+ _file_swap(NoDriveFile()) of
  | ~NoDriveFile() => let
      val @(url, url_len) = _created_url()
    in _send_made("POST", url, url_len, token, token_len, "multipart/related; boundary=quire-sync-part", _made(body, body_size)) end
  | ~DriveFile(id, id_len, version, version_len) => let
      (* the version now: another device's write since the read changed it *)
      val @(url, url_len) = _id_url("https://www.googleapis.com/drive/v3/files/", id, id_len, "?fields=version")
      val @(headers, headers_len) = _headers(token, token_len, "")
      val pending = request_send_empty("GET", url, url_len, headers, headers_len)
      val made = _copied(body, body_size)
      val again = $A.alloc<byte>(TOKEN_MAX)
      val () = request_copy(token, token_len, again, 0, 0)
    in
      $P.and_then<$FE.fetched><drive_put>(pending, llam(got) =>
        case+ request_answered(got) of
        | ~Unanswered() => let
            val () = _made_free(made)
            val () = $A.free<byte>(again)
            val () = _file_free(DriveFile(id, id_len, version, version_len))
          in $P.ret<drive_put>(DrivePutFailed(0)) end
        | ~Answered(status, blob) =>
          if (if status < 200 then true else status >= 300) then let
            val () = $BD.blob_free(blob)
            val () = _made_free(made)
            val () = $A.free<byte>(again)
            val () = _file_free(DriveFile(id, id_len, version, version_len))
          in $P.ret<drive_put>(DrivePutFailed(status)) end
          else (case+ request_body(blob, LISTING_MAX) of
            | ~BodyRead(owner, bytes, n) => let
                val unchanged = _unchanged(bytes, n, version, version_len)
                val () = piece_free(owner, bytes)
              in
                if ~unchanged then let
                  val () = _made_free(made)
                  val () = $A.free<byte>(again)
                  val () = _file_free(DriveFile(id, id_len, version, version_len))
                in $P.ret<drive_put>(DriveChanged()) end
                else let
                  val @(update, update_len) = _id_url("https://www.googleapis.com/upload/drive/v3/files/", id, id_len, "?uploadType=media")
                  val () = _file_free(DriveFile(id, id_len, version, version_len))
                  val sent = _send_made("PATCH", update, update_len, again, token_len, "application/json", made)
                  val () = $A.free<byte>(again)
                in sent end
              end
            | ~BodyEmpty() => let
                val () = _made_free(made)
                val () = $A.free<byte>(again)
                val () = _file_free(DriveFile(id, id_len, version, version_len))
              in $P.ret<drive_put>(DrivePutFailed(NOT_UNDERSTOOD)) end
            | ~BodyFailed(why) => let
                val () = _made_free(made)
                val () = $A.free<byte>(again)
                val () = _file_free(DriveFile(id, id_len, version, version_len))
              in $P.ret<drive_put>(DrivePutFailed(why)) end))
    end

(* ============================================================
   The account's address, and the grant taken back
   ============================================================ *)

(* The account's address as Drive gives it (about.get's
   user.emailAddress, which drive.appdata may read), or none: Drive
   leaves it out "if the user has not made their email address visible
   to the requester", and a request that fails gives none *)
#pub datavtype drive_address =
  | {l:agz}{n:pos | n <= 256} DriveAddress of ($A.arr(byte, l, 256), int n)
  | DriveNoAddress of ()

implement $P.dispose<drive_address>(found) =
  case+ found of
  | ~DriveAddress(address, _) => $A.free<byte>(address)
  | ~DriveNoAddress() => ()

(* The address of the account the access token token[0, token_len) is
   for *)
#pub fn drive_account_address {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= 4096}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len): $P.promise(drive_address, $P.Chained)

(* The grant the access token token[0, token_len) belongs to taken back
   (Google's OAuth revocation endpoint, RFC 7009, which revokes the
   whole grant an access token is part of): resolves 0 when Google took
   it *)
#pub fn drive_grant_revoke {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= 4096}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len): $P.promise(int, $P.Chained)

(* about.get's answer, {"user": {"emailAddress": "..."}}: the address *)
fn _address_by {l,key_loc:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n, key: !$A.arr(byte, key_loc, 16)): drive_address = let
  val members = (if n > 0 then jr_object(buf, n, 0) else ~1): [inside:int | ~1 <= inside; inside <= n] int inside
  val user_at = (if members >= 0 then jr_member(buf, n, members, key, "user") else ~1): [at:int | ~1 <= at; at < n] int at
  val user_members = jr_object(buf, n, user_at)
  val address_at = (if user_members >= 0 then jr_member(buf, n, user_members, key, "emailAddress") else ~1): [at:int | ~1 <= at; at < n] int at
  val address = $A.alloc<byte>(256)
  val @(found, address_len) = _string_at(buf, n, address_at, address, 256)
in
  if ~found then let val () = $A.free<byte>(address) in DriveNoAddress() end
  else if address_len <= 0 then let val () = $A.free<byte>(address) in DriveNoAddress() end
  else DriveAddress(address, address_len)
end

fn _address_in {l:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n): drive_address = let
  val key = $A.alloc<byte>(16)
  val found = _address_by(buf, n, key)
  val () = $A.free<byte>(key)
in found end

implement drive_account_address (token, token_len) = let
  val url = $A.alloc<byte>(URL_MAX)
  val url_len = request_text(url, 0, "https://www.googleapis.com/drive/v3/about?fields=user%2FemailAddress")
  val @(headers, headers_len) = _headers(token, token_len, "")
  val pending = request_send_empty("GET", url, url_len, headers, headers_len)
in
  $P.and_then<$FE.fetched><drive_address>(pending, llam(got) =>
    case+ request_answered(got) of
    | ~Unanswered() => $P.ret<drive_address>(DriveNoAddress())
    | ~Answered(status, blob) =>
      if (if status < 200 then true else status >= 300) then let
        val () = $BD.blob_free(blob)
      in $P.ret<drive_address>(DriveNoAddress()) end
      else (case+ request_body(blob, LISTING_MAX) of
        | ~BodyRead(owner, bytes, n) => let
            val found = _address_in(bytes, n)
            val () = piece_free(owner, bytes)
          in $P.ret<drive_address>(found) end
        | ~BodyEmpty() => $P.ret<drive_address>(DriveNoAddress())
        | ~BodyFailed(_) => $P.ret<drive_address>(DriveNoAddress())))
end

(* Whether a byte is one a form's value carries as itself (RFC 3986's
   unreserved: letters, digits, "-", ".", "_", "~") *)
fn _unreserved (b: int): bool =
  if b >= 65 then (if b <= 90 then true else if b >= 97 then (if b <= 122 then true else b = 126) else b = 95)
  else if b >= 48 then b <= 57
  else if b = 45 then true
  else b = 46

(* A hexadecimal digit's byte, for d in [0, 16) *)
fn _hex_digit {d:nat | d < 16} (d: int d): int = if d < 10 then 48 + d else 55 + d

(* token[j, token_len), percent-encoded, at form[position]: where it
   ends *)
fun _form_encoded {token_loc,form_loc:agz}{token_size:nat}{token_len:nat | token_len <= token_size; token_len <= 4096}{j:nat | j <= token_len}{position:nat | position <= 6 + 3 * j} .<token_len - j>.
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len, form: !$A.arr(byte, form_loc, 12294), position: int position, j: int j)
  : [stop:nat | stop <= 6 + 3 * token_len] int stop =
  if j >= token_len then position
  else let
    val b = g1ofg0(byte2int0($A.get<byte>(token, j)))
  in
    if _unreserved(b) then let
      val () = $A.set<byte>(form, position, int2byte0(b))
    in _form_encoded(token, token_len, form, position + 1, j + 1) end
    else let
      val b = (if b >= 0 then (if b < 256 then b else 0) else 0): [b:nat | b < 256] int b
      val () = $A.set<byte>(form, position, int2byte0(37))
      val () = $A.set<byte>(form, position + 1, int2byte0(_hex_digit(b / 16)))
      val () = $A.set<byte>(form, position + 2, int2byte0(_hex_digit(b - (b / 16) * 16)))
    in _form_encoded(token, token_len, form, position + 3, j + 1) end
  end

implement drive_grant_revoke (token, token_len) = let
  val url = $A.alloc<byte>(URL_MAX)
  val url_len = request_text(url, 0, "https://oauth2.googleapis.com/revoke")
  val headers = $A.alloc<byte>(HEADERS_MAX)
  val headers_len = request_text(headers, 0, "Content-Type: application/x-www-form-urlencoded")
  val form = $A.alloc<byte>(12294)
  val () = $A.write_text(form, 0, $A.text_lit("token="), 6)
  val form_len = _form_encoded(token, token_len, form, 6, 0)
  val @(form_frozen, form_bytes) = $A.freeze<byte>(form)
  val pending = request_send("POST", url, url_len, headers, headers_len, form_bytes, form_len)
  val () = release_bytes(form_frozen, form_bytes)
in
  $P.and_then<$FE.fetched><int>(pending, llam(got) =>
    case+ request_answered(got) of
    | ~Unanswered() => $P.ret<int>(1)
    | ~Answered(status, blob) => let
        val () = $BD.blob_free(blob)
      in $P.ret<int>(if status = 200 then 0 else 1) end)
end

end (* #target wasm *)
