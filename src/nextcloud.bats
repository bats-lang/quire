(* nextcloud -- signing in to a Nextcloud server with its Login Flow v2
   (https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html),
   which gives an app password through the server's own sign-in page,
   with no app registered anywhere. sync.bats keeps what it gives as a
   WebDAV store: the user's files folder, the login name and the app
   password.

   1. POST <server>/index.php/login/v2: the page to sign in on, and a
      token and an endpoint to poll (nextcloud_start).
   2. The reader signs in on that page, in a tab of its own.
   3. POST <endpoint> with token=<token>, every few seconds: 404 until
      the reader has signed in, then the server's address, the login
      name and an app password (nextcloud_poll). The token lasts 20
      minutes.
   4. GET <server>/ocs/v2.php/cloud/user, signed in with them: the
      user's id, which names their files folder,
      <server>/remote.php/dav/files/<id> (nextcloud_user_id; a login
      name can be an email address, which is not the id) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "jsonio.sats"
staload "mem.sats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* An address's, a token's, a name's or a password's most bytes *)
#pub stadef NEXTCLOUD_TEXT = 1024
#define TEXT_MAX 1024
(* A reply's most bytes: the flow's answers are a few hundred *)
#define REPLY_MAX 65536

(* Why a step failed: the server could not be reached (offline, or a
   browser refused it: CORS), it is not a Nextcloud server (or its
   answer cannot be read), it refused the credentials, or there was not
   the memory *)
#pub datatype nextcloud_failure =
  | NextcloudUnreachable
  | NextcloudNotNextcloud
  | NextcloudRefused
  | NextcloudMemory

(* What the flow's start gives: the page to sign in on, and the
   endpoint and token to poll *)
#pub datavtype login_started =
  | {login_loc,endpoint_loc,token_loc:agz}{login_len,endpoint_len,token_len:pos | login_len <= NEXTCLOUD_TEXT; endpoint_len <= NEXTCLOUD_TEXT; token_len <= NEXTCLOUD_TEXT}
    LoginStarted of ($A.arr(byte, login_loc, NEXTCLOUD_TEXT), int login_len,
                     $A.arr(byte, endpoint_loc, NEXTCLOUD_TEXT), int endpoint_len,
                     $A.arr(byte, token_loc, NEXTCLOUD_TEXT), int token_len)
  | LoginNotStarted of nextcloud_failure

(* What a poll gives: the reader signed in (the server's address, the
   login name and the app password), not yet, or a failure *)
#pub datavtype login_polled =
  | {server_loc,name_loc,password_loc:agz}{server_len,name_len,password_len:pos | server_len <= NEXTCLOUD_TEXT; name_len <= NEXTCLOUD_TEXT; password_len <= NEXTCLOUD_TEXT}
    LoginGranted of ($A.arr(byte, server_loc, NEXTCLOUD_TEXT), int server_len,
                     $A.arr(byte, name_loc, NEXTCLOUD_TEXT), int name_len,
                     $A.arr(byte, password_loc, NEXTCLOUD_TEXT), int password_len)
  | LoginNotYet of ()
  | LoginPollFailed of nextcloud_failure

(* The user's id, or why it could not be had *)
#pub datavtype user_found =
  | {id_loc:agz}{id_len:pos | id_len <= NEXTCLOUD_TEXT} UserFound of ($A.arr(byte, id_loc, NEXTCLOUD_TEXT), int id_len)
  | UserNotFound of nextcloud_failure

#pub fn login_started_free (started: login_started): void
#pub fn login_polled_free (polled: login_polled): void
#pub fn user_found_free (found: user_found): void

implement login_started_free (started) =
  case+ started of
  | ~LoginStarted(login, _, endpoint, _, token, _) => let
      val () = $A.free<byte>(login)
      val () = $A.free<byte>(endpoint)
    in $A.free<byte>(token) end
  | ~LoginNotStarted(_) => ()

implement login_polled_free (polled) =
  case+ polled of
  | ~LoginGranted(server, _, name, _, password, _) => let
      val () = $A.free<byte>(server)
      val () = $A.free<byte>(name)
    in $A.free<byte>(password) end
  | ~LoginNotYet() => ()
  | ~LoginPollFailed(_) => ()

implement user_found_free (found) =
  case+ found of
  | ~UserFound(id, _) => $A.free<byte>(id)
  | ~UserNotFound(_) => ()

implement $P.dispose<login_started>(started) = login_started_free(started)
implement $P.dispose<login_polled>(polled) = login_polled_free(polled)
implement $P.dispose<user_found>(found) = user_found_free(found)

(* ============================================================
   Requests
   ============================================================ *)

(* literal at out[position] *)
fn _put_literal {l:agz}{n:nat}{position:nat}{text_len:nat | position + text_len <= n}
  (out: !$A.arr(byte, l, n), position: int position, text: string text_len): int(position + text_len) = let
  val text_len = g1u2i(string1_length(text))
  val () = $A.write_text(out, position, $A.text_lit(text), text_len)
in position + text_len end

(* source[0, count) at out[position, position + count) *)
fun _put_bytes {source_loc,out_loc:agz}{source_size,out_size:nat}{count:nat | count <= source_size}{position:nat | position + count <= out_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arr(byte, out_loc, out_size), position: int position, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, position + j, $A.get<byte>(source, j))
  in _put_bytes(source, count, out, position, j + 1) end

(* The address without the slashes it ends with *)
fun _trimmed {l:agz}{n:nat}{address_len:nat | address_len <= n} .<address_len>.
  (address: !$A.arr(byte, l, n), address_len: int address_len): [kept:nat | kept <= address_len] int kept =
  if address_len <= 0 then 0
  else if byte2int0($A.get<byte>(address, address_len - 1)) = 47 then _trimmed(address, address_len - 1)
  else address_len

(* The method's request for url[0, url_len), with headers[0,
   headers_len) and body[0, body_len): what it came to *)
fn _request {method_len:pos | method_len <= 8}{url_loc,headers_loc,body_loc:agz}{url_size,headers_size,body_size:nat}
  {url_len:pos | url_len <= url_size; url_len <= 65536}{headers_len:nat | headers_len <= headers_size; headers_len < 65536}{body_len:nat | body_len <= body_size; body_len < 65536}
  (method: string method_len, url: !$A.arr(byte, url_loc, url_size), url_len: int url_len,
   headers: !$A.arr(byte, headers_loc, headers_size), headers_len: int headers_len,
   body: !$A.arr(byte, body_loc, body_size), body_len: int body_len): $P.promise($FE.fetched, $P.Chained) = let
  val method_len = g1u2i(string1_length(method))
  val method_bytes = $A.alloc<byte>(method_len)
  val () = $A.write_text(method_bytes, 0, $A.text_lit(method), method_len)
  val url_copy = $A.alloc<byte>(url_len)
  val () = _put_bytes(url, url_len, url_copy, 0, 0)
  val headers_copy = $A.alloc<byte>(headers_len + 1)
  val () = _put_bytes(headers, headers_len, headers_copy, 0, 0)
  val body_copy = $A.alloc<byte>(body_len + 1)
  val () = _put_bytes(body, body_len, body_copy, 0, 0)
  val @(method_frozen, method_borrow) = $A.freeze<byte>(method_bytes)
  val @(url_frozen, url_borrow) = $A.freeze<byte>(url_copy)
  val @(headers_frozen, headers_borrow) = $A.freeze<byte>(headers_copy)
  val @(body_frozen, body_borrow) = $A.freeze<byte>(body_copy)
  val pending = $FE.fetch_request(method_borrow, method_len, url_borrow, url_len, headers_borrow, headers_len, body_borrow, body_len)
  val () = release_bytes(body_frozen, body_borrow)
  val () = release_bytes(headers_frozen, headers_borrow)
  val () = release_bytes(url_frozen, url_borrow)
in let val () = release_bytes(method_frozen, method_borrow) in pending end end

(* A reply: its status and its body (at most REPLY_MAX bytes, in an
   array of its own size), or none when no response came *)
datavtype reply =
  | {l:agz}{n:pos | n <= REPLY_MAX} Reply of (Int, $A.arr(byte, l, n), int n)
  | NoReply of ()

(* How much of a reply of size bytes is read *)
fn _kept {size:nat} (size: int size): [kept:nat | kept <= REPLY_MAX; kept <= size] int kept =
  if size > REPLY_MAX then REPLY_MAX else size

fn _reply (got: $FE.fetched): reply =
  case+ got of
  | ~$FE.NoResponse() => NoReply()
  | ~$FE.Responded(response) => let
      val status = $FE.fetch_status(response)
      val body = $FE.fetch_body(response)
      val size = $BD.blob_len(body)
      val kept = _kept(size)
    in
      if kept <= 0 then let
        val () = $BD.blob_free(body)
      in Reply(status, $A.alloc<byte>(1), 1) end
      else let
        val buffer = $A.alloc<byte>(kept)
        val () = $BD.blob_read(body, 0, buffer, kept)
        val () = $BD.blob_free(body)
      in Reply(status, buffer, kept) end
    end

(* ============================================================
   Reading the replies' JSON
   ============================================================ *)

(* Where the value of the member key of the object at position starts,
   or none *)
fun _member_from {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}{key_len:nat} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: string key_len): $R.option([value:nat | value <= n] int value) = let
  val at = jr_ws(buf, n, position)
in
  if at >= n then $R.none()
  else if jr_is(buf, n, at, 125) then $R.none()
  else let
    val name = $A.alloc<byte>(64)
    val @(found, name_len, value_start) = jr_key(buf, n, at, name, 64)
    val named = jr_key_is(name, name_len, key)
    val matches = (if found then named else false): bool
    val () = $A.free<byte>(name)
  in
    if ~found then $R.none()
    else if matches then $R.some(value_start)
    else let
      val after = jr_ws(buf, n, jr_skip(buf, n, value_start))
    in
      if after >= n then $R.none()
      else if jr_is(buf, n, after, 44) then _member_from(buf, n, after + 1, key)
      else $R.none()
    end
  end
end

(* Where the value of the member key of the object at position starts *)
fn _member {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}{key_len:nat}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: string key_len): $R.option([value:nat | value <= n] int value) = let
  val at = jr_ws(buf, n, position)
in
  if at >= n then $R.none()
  else if jr_is(buf, n, at, 123) then _member_from(buf, n, at + 1, key)
  else $R.none()
end

(* A text of 1 to TEXT_MAX bytes *)
datavtype text = | {l:agz}{text_len:pos | text_len <= NEXTCLOUD_TEXT} Text of ($A.arr(byte, l, NEXTCLOUD_TEXT), int text_len) | NoText of ()

(* The string at position, when there is one and it is not empty *)
fn _string_at {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position): text =
  if position >= n then NoText()
  else let
    val out = $A.alloc<byte>(TEXT_MAX)
    val @(found, text_len, _) = jr_str(buf, n, position, out, TEXT_MAX)
  in
    if ~found then let val () = $A.free<byte>(out) in NoText() end
    else if text_len <= 0 then let val () = $A.free<byte>(out) in NoText() end
    else if text_len >= TEXT_MAX then let val () = $A.free<byte>(out) in NoText() end
    else Text(out, text_len)
  end

(* The string member key of the object at position *)
fn _string_member {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}{key_len:nat}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: string key_len): text =
  case+ _member(buf, n, position, key) of
  | ~$R.some(value) => _string_at(buf, n, value)
  | ~$R.none() => NoText()

(* ============================================================
   The flow
   ============================================================ *)

(* Starts the flow on the server at address[0, address_len) *)
#pub fn nextcloud_start {l:agz}{n:nat}{address_len:pos | address_len <= n; address_len <= NEXTCLOUD_TEXT}
  (address: !$A.arr(byte, l, n), address_len: int address_len): $P.promise(login_started, $P.Chained)

implement nextcloud_start (address, address_len) = let
  val kept = _trimmed(address, address_len)
  val url = $A.alloc<byte>(TEXT_MAX + 20)
  val () = _put_bytes(address, kept, url, 0, 0)
  val url_len = _put_literal(url, kept, "/index.php/login/v2")
  (* Nextcloud names the app password it makes by the User-Agent, which
     a browser sets itself *)
  val headers = $A.alloc<byte>(1)
  val body = $A.alloc<byte>(1)
  val pending = _request("POST", url, url_len, headers, 0, body, 0)
  val () = $A.free<byte>(url)
  val () = $A.free<byte>(headers)
  val () = $A.free<byte>(body)
in
  $P.and_then<$FE.fetched><login_started>(pending, llam(got) =>
    case+ _reply(got) of
    | ~NoReply() => $P.ret<login_started>(LoginNotStarted(NextcloudUnreachable()))
    | ~Reply(status, buffer, size) =>
      if status <> 200 then let val () = $A.free<byte>(buffer) in $P.ret<login_started>(LoginNotStarted(NextcloudNotNextcloud())) end
      else let
        val login = _string_member(buffer, size, 0, "login")
        val @(endpoint, token) = (case+ _member(buffer, size, 0, "poll") of
          | ~$R.some(poll) => @(_string_member(buffer, size, poll, "endpoint"), _string_member(buffer, size, poll, "token"))
          | ~$R.none() => @(NoText(), NoText())): @(text, text)
        val () = $A.free<byte>(buffer)
      in
        case+ login of
        | ~NoText() => let
            val () = (case+ endpoint of ~Text(e, _) => $A.free<byte>(e) | ~NoText() => ())
            val () = (case+ token of ~Text(t, _) => $A.free<byte>(t) | ~NoText() => ())
          in $P.ret<login_started>(LoginNotStarted(NextcloudNotNextcloud())) end
        | ~Text(login, login_len) => (case+ endpoint of
          | ~NoText() => let
              val () = $A.free<byte>(login)
              val () = (case+ token of ~Text(t, _) => $A.free<byte>(t) | ~NoText() => ())
            in $P.ret<login_started>(LoginNotStarted(NextcloudNotNextcloud())) end
          | ~Text(endpoint, endpoint_len) => (case+ token of
            | ~NoText() => let
                val () = $A.free<byte>(login)
                val () = $A.free<byte>(endpoint)
              in $P.ret<login_started>(LoginNotStarted(NextcloudNotNextcloud())) end
            | ~Text(token, token_len) => $P.ret<login_started>(LoginStarted(login, login_len, endpoint, endpoint_len, token, token_len))))
      end)
end

(* Asks the endpoint[0, endpoint_len) whether the reader has signed in,
   with token[0, token_len) *)
#pub fn nextcloud_poll {endpoint_loc,token_loc:agz}{endpoint_len,token_len:pos | endpoint_len <= NEXTCLOUD_TEXT; token_len <= NEXTCLOUD_TEXT}
  (endpoint: !$A.arr(byte, endpoint_loc, NEXTCLOUD_TEXT), endpoint_len: int endpoint_len,
   token: !$A.arr(byte, token_loc, NEXTCLOUD_TEXT), token_len: int token_len): $P.promise(login_polled, $P.Chained)

implement nextcloud_poll (endpoint, endpoint_len, token, token_len) = let
  val headers = $A.alloc<byte>(64)
  val headers_len = _put_literal(headers, 0, "Content-Type: application/x-www-form-urlencoded")
  (* the token is hex, so it needs no escaping in the form *)
  val body = $A.alloc<byte>(TEXT_MAX + 6)
  val body_len = _put_literal(body, 0, "token=")
  val () = _put_bytes(token, token_len, body, body_len, 0)
  val pending = _request("POST", endpoint, endpoint_len, headers, headers_len, body, body_len + token_len)
  val () = $A.free<byte>(headers)
  val () = $A.free<byte>(body)
in
  $P.and_then<$FE.fetched><login_polled>(pending, llam(got) =>
    case+ _reply(got) of
    | ~NoReply() => $P.ret<login_polled>(LoginPollFailed(NextcloudUnreachable()))
    | ~Reply(status, buffer, size) =>
      if status = 404 then let val () = $A.free<byte>(buffer) in $P.ret<login_polled>(LoginNotYet()) end
      else if status <> 200 then let val () = $A.free<byte>(buffer) in $P.ret<login_polled>(LoginPollFailed(NextcloudNotNextcloud())) end
      else let
        val server = _string_member(buffer, size, 0, "server")
        val name = _string_member(buffer, size, 0, "loginName")
        val password = _string_member(buffer, size, 0, "appPassword")
        val () = $A.free<byte>(buffer)
      in
        case+ server of
        | ~NoText() => let
            val () = (case+ name of ~Text(t, _) => $A.free<byte>(t) | ~NoText() => ())
            val () = (case+ password of ~Text(t, _) => $A.free<byte>(t) | ~NoText() => ())
          in $P.ret<login_polled>(LoginPollFailed(NextcloudNotNextcloud())) end
        | ~Text(server, server_len) => (case+ name of
          | ~NoText() => let
              val () = $A.free<byte>(server)
              val () = (case+ password of ~Text(t, _) => $A.free<byte>(t) | ~NoText() => ())
            in $P.ret<login_polled>(LoginPollFailed(NextcloudNotNextcloud())) end
          | ~Text(name, name_len) => (case+ password of
            | ~NoText() => let
                val () = $A.free<byte>(server)
                val () = $A.free<byte>(name)
              in $P.ret<login_polled>(LoginPollFailed(NextcloudNotNextcloud())) end
            | ~Text(password, password_len) => $P.ret<login_polled>(LoginGranted(server, server_len, name, name_len, password, password_len))))
      end)
end

(* The user's id, from the server at server[0, server_len), signed in
   with authorization[0, authorization_len) (a Basic header's value) *)
#pub fn nextcloud_user_id {server_loc,authorization_loc:agz}{server_size,authorization_size:nat}
  {server_len:pos | server_len <= server_size; server_len <= NEXTCLOUD_TEXT}{authorization_len:pos | authorization_len <= authorization_size; authorization_len <= 1024}
  (server: !$A.arr(byte, server_loc, server_size), server_len: int server_len,
   authorization: !$A.arr(byte, authorization_loc, authorization_size), authorization_len: int authorization_len): $P.promise(user_found, $P.Chained)

implement nextcloud_user_id (server, server_len, authorization, authorization_len) = let
  val kept = _trimmed(server, server_len)
  val url = $A.alloc<byte>(TEXT_MAX + 40)
  val () = _put_bytes(server, kept, url, 0, 0)
  val url_len = _put_literal(url, kept, "/ocs/v2.php/cloud/user?format=json")
  val headers = $A.alloc<byte>(1100)
  val headers_len = _put_literal(headers, 0, "OCS-APIRequest: true\nAuthorization: ")
  val () = _put_bytes(authorization, authorization_len, headers, headers_len, 0)
  val body = $A.alloc<byte>(1)
  val pending = _request("GET", url, url_len, headers, headers_len + authorization_len, body, 0)
  val () = $A.free<byte>(url)
  val () = $A.free<byte>(headers)
  val () = $A.free<byte>(body)
in
  $P.and_then<$FE.fetched><user_found>(pending, llam(got) =>
    case+ _reply(got) of
    | ~NoReply() => $P.ret<user_found>(UserNotFound(NextcloudUnreachable()))
    | ~Reply(status, buffer, size) =>
      if (if status = 401 then true else status = 403) then let val () = $A.free<byte>(buffer) in $P.ret<user_found>(UserNotFound(NextcloudRefused())) end
      else if status <> 200 then let val () = $A.free<byte>(buffer) in $P.ret<user_found>(UserNotFound(NextcloudNotNextcloud())) end
      else let
        val id = (case+ _member(buffer, size, 0, "ocs") of
          | ~$R.none() => NoText()
          | ~$R.some(ocs) => (case+ _member(buffer, size, ocs, "data") of
            | ~$R.none() => NoText()
            | ~$R.some(data) => _string_member(buffer, size, data, "id"))): text
        val () = $A.free<byte>(buffer)
      in
        case+ id of
        | ~Text(id, id_len) => $P.ret<user_found>(UserFound(id, id_len))
        | ~NoText() => $P.ret<user_found>(UserNotFound(NextcloudNotNextcloud()))
      end)
end

(* The hex digit of value (4 bits), upper case *)
fn _hex_digit {value:nat | value < 16} (value: int value): [digit:nat | digit < 256] int digit =
  if value < 10 then 48 + value else 55 + value

(* Whether the byte is one a path segment keeps as it is: a letter, a
   digit, or - . _ ~ (RFC 3986's unreserved) *)
fn _unreserved (byte: int): bool =
  if byte >= 97 then byte <= 122 || byte = 126
  else if byte >= 65 then byte <= 90 || byte = 95
  else if byte >= 48 then byte <= 57
  else byte = 45 || byte = 46

(* id[j, id_len) percent-encoded at out[position]: where it ends *)
fun _encode {id_loc,out_loc:agz}{id_len:nat | id_len <= NEXTCLOUD_TEXT}{j:nat | j <= id_len}{position:nat | position + 3 * (id_len - j) <= 4 * NEXTCLOUD_TEXT} .<id_len - j>.
  (id: !$A.arr(byte, id_loc, NEXTCLOUD_TEXT), id_len: int id_len, out: !$A.arr(byte, out_loc, 4 * NEXTCLOUD_TEXT), position: int position, j: int j)
  : [stop:nat | stop <= position + 3 * (id_len - j)] int stop =
  if j >= id_len then position
  else let
    val byte = $AR.low_byte(byte2int0($A.get<byte>(id, j)))
  in
    if _unreserved(byte) then let
      val () = $A.write_byte(out, position, byte)
    in _encode(id, id_len, out, position + 1, j + 1) end
    else let
      val () = $A.write_byte(out, position, 37)
      val () = $A.write_byte(out, position + 1, _hex_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(byte, 4)), 15)))
      val () = $A.write_byte(out, position + 2, _hex_digit($AR.band_g1(byte, 15)))
    in _encode(id, id_len, out, position + 3, j + 1) end
  end

(* The user's files folder, <server>/remote.php/dav/files/<id> (the id
   percent-encoded), in out: its length *)
#pub fn nextcloud_folder {server_loc,id_loc,out_loc:agz}{server_len:pos | server_len <= NEXTCLOUD_TEXT}{id_len:pos | id_len <= NEXTCLOUD_TEXT}
  (server: !$A.arr(byte, server_loc, NEXTCLOUD_TEXT), server_len: int server_len,
   id: !$A.arr(byte, id_loc, NEXTCLOUD_TEXT), id_len: int id_len, out: !$A.arr(byte, out_loc, 4 * NEXTCLOUD_TEXT + 32))
  : [stop:pos | stop <= 4 * NEXTCLOUD_TEXT + 32] int stop

implement nextcloud_folder (server, server_len, id, id_len, out) = let
  val kept = _trimmed(server, server_len)
  val () = _put_bytes(server, kept, out, 0, 0)
  val after = _put_literal(out, kept, "/remote.php/dav/files/")
  val encoded = $A.alloc<byte>(4 * TEXT_MAX)
  val encoded_len = _encode(id, id_len, encoded, 0, 0)
  val () = _put_bytes(encoded, encoded_len, out, after, 0)
  val () = $A.free<byte>(encoded)
in after + encoded_len end

end (* #target wasm *)
