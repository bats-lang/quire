(* dropbox -- the sync file in the reader's Dropbox app folder (#184)

   Quire's Dropbox app has App folder access: it sees Apps/<app name>/
   and nothing else, and its file is /quire-sync.json there. Signing in
   is OAuth with PKCE and no client secret (the app key is public, like
   any client ID): the page leaves for Dropbox's authorization page with
   a code challenge and a state, and comes back to its own address with
   a code, which is exchanged, with the verifier, for an access token
   (about four hours) and a refresh token (token_access_type=offline),
   which gets a new access token without the reader. A read downloads
   the file, its revision (rev) kept from Dropbox-API-Result; a write
   uploads it as an update of that revision, which Dropbox refuses as a
   conflict when another device wrote it meanwhile (409, path/conflict),
   or adds it when there was none. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use sha256 as SHA

staload "book.sats"
staload "mem.sats"
staload "jsonio.sats"
staload "drive.sats"
staload "web_request.sats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload RANDOM = "wasm.bats-packages.dev/bridge/src/random.sats"

(* An access token's, a refresh token's, a revision's, an app key's and
   a code's most bytes *)
#pub stadef DROPBOX_TOKEN_MAX = 4096
#pub stadef DROPBOX_REFRESH_MAX = 512
#define TOKEN_MAX 4096
#define REFRESH_MAX 512
#define REVISION_MAX 64
#define KEY_MAX 256
#define CODE_MAX 512
#define REDIRECT_MAX 512
(* A token's answer's, and an error's, most bytes *)
#define ANSWER_MAX 65536
#define FORM_MAX 2048
#define URL_MAX 1024
#define HEADERS_MAX 4600

(* Answers nobody took, freed: before their first use here *)
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

(* ============================================================
   PKCE: the verifier, its challenge, and the state
   ============================================================ *)

(* The base64url digit of value (6 bits) *)
fn _digit {value:nat | value < 64} (value: int value): [digit:nat | digit < 256] int digit =
  if value < 26 then 65 + value
  else if value < 52 then 71 + value
  else if value < 62 then value - 4
  else if value = 62 then 45
  else 95

fn _byte_at {l:agz}{n,i:nat | i < n} (bytes: !$A.arr(byte, l, n), i: int i): [v:nat | v < 256] int v =
  $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))

(* source[0, count) as base64url with no padding at out[0]: its length *)
fun _base64url {source_loc,out_loc:agz}{source_size,out_size:nat}{count:nat | count <= source_size; 2 * count <= out_size}{i:nat | i <= count}{at:nat | at <= 2 * i} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arr(byte, out_loc, out_size), i: int i, at: int at)
  : [stop:nat | stop <= 2 * count] int stop =
  if i >= count then at
  else let
    val first = _byte_at(source, i)
    val second = (if i + 1 < count then _byte_at(source, i + 1) else 0): [v:nat | v < 256] int v
    val third = (if i + 2 < count then _byte_at(source, i + 2) else 0): [v:nat | v < 256] int v
    val () = $A.write_byte(out, at, _digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(first, 2)), 63)))
    val () = $A.write_byte(out, at + 1, _digit($AR.band_g1($AR.low_byte($AR.bor_int_int($AR.bsl_int_int($AR.band_int_int(first, 3), 4), $AR.bsr_int_int(second, 4))), 63)))
  in
    if i + 1 >= count then at + 2
    else let
      val () = $A.write_byte(out, at + 2, _digit($AR.band_g1($AR.low_byte($AR.bor_int_int($AR.bsl_int_int($AR.band_int_int(second, 15), 2), $AR.bsr_int_int(third, 6))), 63)))
    in
      if i + 2 >= count then at + 3
      else let
        val () = $A.write_byte(out, at + 3, _digit($AR.band_g1(third, 63)))
      in _base64url(source, count, out, i + 3, at + 4) end
    end
  end

(* A hex digit's value *)
fn _hex (digit: int): [v:nat | v < 16] int v =
  if digit <= 57 then $AR.band_g1($AR.low_byte(digit - 48), 15)
  else $AR.band_g1($AR.low_byte(digit - 87), 15)

(* The 32 bytes of 64 hex digits *)
fun _unhex {hex_loc,out_loc:agz}{i:nat | i <= 32} .<32 - i>.
  (hex: !$A.arr(byte, hex_loc, 64), out: !$A.arr(byte, out_loc, 32), i: int i): void =
  if i >= 32 then ()
  else let
    val high = _hex(byte2int0($A.get<byte>(hex, 2 * i)))
    val low = _hex(byte2int0($A.get<byte>(hex, 2 * i + 1)))
    val () = $A.write_byte(out, i, high * 16 + low)
  in _unhex(hex, out, i + 1) end

(* A sign-in's secrets: the verifier (43 characters), its challenge (the
   SHA-256 of the verifier, 43 characters) and the state (22) *)
#pub datavtype pkce =
  | {verifier_loc,challenge_loc,state_loc:agz}
    Pkce of ($A.arr(byte, verifier_loc, 64), $A.arr(byte, challenge_loc, 64), $A.arr(byte, state_loc, 64))

#pub fn pkce_free (secrets: pkce): void

implement pkce_free (secrets) = let
  val+ ~Pkce(verifier, challenge, state) = secrets
  val () = $A.free<byte>(verifier)
  val () = $A.free<byte>(challenge)
in $A.free<byte>(state) end

(* New secrets, from the browser's cryptographic random source *)
#pub fn dropbox_pkce (): pkce

implement dropbox_pkce () = let
  val random = $A.alloc<byte>(32)
  val () = $RANDOM.random_bytes(random, 32)
  val verifier = $A.alloc<byte>(64)
  val _ = _base64url(random, 32, verifier, 0, 0)
  val () = $RANDOM.random_bytes(random, 32)
  val state = $A.alloc<byte>(64)
  val _ = _base64url(random, 16, state, 0, 0)
  val () = $A.free<byte>(random)
  val text = $A.alloc<byte>(43)
  val () = request_copy(verifier, 43, text, 0, 0)
  val hex = $A.alloc<byte>(64)
  val () = $SHA.hash(text, 43, hex)
  val () = $A.free<byte>(text)
  val digest = $A.alloc<byte>(32)
  val () = _unhex(hex, digest, 0)
  val () = $A.free<byte>(hex)
  val challenge = $A.alloc<byte>(64)
  val _ = _base64url(digest, 32, challenge, 0, 0)
  val () = $A.free<byte>(digest)
in Pkce(verifier, challenge, state) end

#pub stadef VERIFIER_LEN = 43
#pub stadef STATE_LEN = 22

(* ============================================================
   Encoding for a URL's query or a form
   ============================================================ *)

fn _unreserved (c: int): bool =
  if c >= 65 then (if c <= 90 then true else if c >= 97 then (if c <= 122 then true else c = 126) else c = 95)
  else if c >= 48 then c <= 57
  else if c = 45 then true
  else c = 46

fn _hex_digit {v:nat | v < 16} (v: int v): [d:nat | d < 256] int d =
  if v < 10 then 48 + v else 55 + v

(* source[0, count) percent-encoded at out[position]: where it ends, or
   -1 when out is too small *)
fun _encode {source_loc,out_loc:agz}{source_size,out_size:nat}{count:nat | count <= source_size}{i:nat | i <= count}{position:nat | position <= out_size} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arr(byte, out_loc, out_size), out_size: int out_size, i: int i, position: int position)
  : [stop:int | ~1 <= stop; stop <= out_size] int stop =
  if i >= count then position
  else let
    val c = _byte_at(source, i)
  in
    if _unreserved(c) then
      (if position + 1 > out_size then ~1
       else let val () = $A.write_byte(out, position, c) in _encode(source, count, out, out_size, i + 1, position + 1) end)
    else if position + 3 > out_size then ~1
    else let
      val () = $A.write_byte(out, position, 37)
      val () = $A.write_byte(out, position + 1, _hex_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(c, 4)), 15)))
      val () = $A.write_byte(out, position + 2, _hex_digit($AR.band_g1(c, 15)))
    in _encode(source, count, out, out_size, i + 1, position + 3) end
  end

(* literal at out[position] when it fits: where it ends, or -1 *)
fn _literal {l:agz}{out_size:nat}{position:int | ~1 <= position; position <= out_size}{text_len:nat}
  (out: !$A.arr(byte, l, out_size), out_size: int out_size, position: int position, text: string text_len)
  : [stop:int | ~1 <= stop; stop <= out_size] int stop = let
  val text_len = g1u2i(string1_length(text))
in
  if position < 0 then ~1
  else if position + text_len > out_size then ~1
  else request_text(out, position, text)
end

(* source[0, count) percent-encoded at out[position] when it all fits *)
fn _encoded {source_loc,out_loc:agz}{source_size,out_size:nat}{count:nat | count <= source_size}{position:int | ~1 <= position; position <= out_size}
  (out: !$A.arr(byte, out_loc, out_size), out_size: int out_size, position: int position, source: !$A.arr(byte, source_loc, source_size), count: int count)
  : [stop:int | ~1 <= stop; stop <= out_size] int stop =
  if position < 0 then ~1 else _encode(source, count, out, out_size, 0, position)

(* The address of Dropbox's authorization page for the app key
   key[0, key_len), coming back to redirect[0, redirect_len), with the
   secrets' challenge and state; its length, 0 when it does not fit *)
#pub fn dropbox_authorize_url {key_loc,redirect_loc:agz}{key_size,redirect_size:nat}{key_len:nat | key_len <= key_size}{redirect_len:nat | redirect_len <= redirect_size}
  (key: !$A.arr(byte, key_loc, key_size), key_len: int key_len, redirect: !$A.arr(byte, redirect_loc, redirect_size), redirect_len: int redirect_len,
   secrets: !pkce): [l:agz][url_len:nat | url_len <= REQUEST_URL_MAX] @($A.arr(byte, l, REQUEST_URL_MAX), int url_len)

implement dropbox_authorize_url (key, key_len, redirect, redirect_len, secrets) = let
  val+ @Pkce(verifier, challenge, state) = secrets
  val url = $A.alloc<byte>(URL_MAX)
  val at = _literal(url, URL_MAX, 0, "https://www.dropbox.com/oauth2/authorize?response_type=code&token_access_type=offline&code_challenge_method=S256&scope=files.content.read%20files.content.write&client_id=")
  val at = _encoded(url, URL_MAX, at, key, key_len)
  val at = _literal(url, URL_MAX, at, "&redirect_uri=")
  val at = _encoded(url, URL_MAX, at, redirect, redirect_len)
  val at = _literal(url, URL_MAX, at, "&code_challenge=")
  val at = _encoded(url, URL_MAX, at, challenge, 43)
  val at = _literal(url, URL_MAX, at, "&state=")
  val at = _encoded(url, URL_MAX, at, state, 22)
  prval () = fold@(secrets)
in if at > 0 then @(url, at) else @(url, 0) end

(* ============================================================
   Tokens
   ============================================================ *)

(* The string at at (a member's value; -1 none) into out *)
fn _string_at {l,out_loc:agz}{owner:addr}{n:nat}{at:int | ~1 <= at; at < n}{capacity:nat}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, at: int at, out: !$A.arr(byte, out_loc, capacity), capacity: int capacity)
  : [length:nat | length <= capacity] @(bool, int length) =
  if at < 0 then @(false, 0)
  else let
    val @(found, length, _) = jr_str(buf, n, at, out, capacity)
  in @(found, length) end

(* What a token request came to: the access token, and the refresh token
   (0 long when the answer has none: a refresh's), or the status Dropbox
   refused with (0 when none came; 400 when the code or the refresh
   token is no longer good) *)
#pub datavtype dropbox_tokens =
  | {access_loc,refresh_loc:agz}{access_len:pos | access_len <= DROPBOX_TOKEN_MAX}{refresh_len:nat | refresh_len <= DROPBOX_REFRESH_MAX}
    DropboxTokens of ($A.arr(byte, access_loc, DROPBOX_TOKEN_MAX), int access_len, $A.arr(byte, refresh_loc, DROPBOX_REFRESH_MAX), int refresh_len)
  | DropboxRefused of (Int)

implement $P.dispose<dropbox_tokens>(tokens) =
  case+ tokens of
  | ~DropboxTokens(access, _, refresh, _) => let
      val () = $A.free<byte>(access)
    in $A.free<byte>(refresh) end
  | ~DropboxRefused(_) => ()

(* The tokens in a token answer buf[0, n) *)
fn _tokens_of {l,key_loc:agz}{owner:addr}{n:nat}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, key: !$A.arr(byte, key_loc, 16)): dropbox_tokens = let
  val members = (if n > 0 then jr_object(buf, n, 0) else ~1): [inside:int | ~1 <= inside; inside <= n] int inside
  val access_at = (if members >= 0 then jr_member(buf, n, members, key, "access_token") else ~1): [at:int | ~1 <= at; at < n] int at
  val refresh_at = (if members >= 0 then jr_member(buf, n, members, key, "refresh_token") else ~1): [at:int | ~1 <= at; at < n] int at
  val access = $A.alloc<byte>(TOKEN_MAX)
  val @(access_found, access_len) = _string_at(buf, n, access_at, access, TOKEN_MAX)
  val refresh = $A.alloc<byte>(REFRESH_MAX)
  val @(refresh_found, refresh_found_len) = _string_at(buf, n, refresh_at, refresh, REFRESH_MAX)
  val refresh_len = (if refresh_found then refresh_found_len else 0): [k:nat | k <= REFRESH_MAX] int k
in
  if ~access_found then let
    val () = $A.free<byte>(access)
    val () = $A.free<byte>(refresh)
  in DropboxRefused(~3) end
  else if access_len <= 0 then let
    val () = $A.free<byte>(access)
    val () = $A.free<byte>(refresh)
  in DropboxRefused(~3) end
  else DropboxTokens(access, access_len, refresh, refresh_len)
end

(* What a token request's response came to *)
fn _tokens_answer (got: $FE.fetched): dropbox_tokens =
  case+ request_answered(got) of
  | ~Unanswered() => DropboxRefused(0)
  | ~Answered(status, blob) =>
    if (if status < 200 then true else status >= 300) then let
      val () = $BD.blob_free(blob)
    in DropboxRefused(status) end
    else (case+ request_body(blob, ANSWER_MAX) of
      | ~BodyEmpty() => DropboxRefused(~3)
      | ~BodyFailed(why) => DropboxRefused(why)
      | ~BodyRead(owner, bytes, n) => let
          val key = $A.alloc<byte>(16)
          val tokens = _tokens_of(bytes, n, key)
          val () = $A.free<byte>(key)
          val () = piece_free(owner, bytes)
        in tokens end)

(* The form form[0, form_len) to the token endpoint *)
fn _token_request {form_loc:agz}{form_len:pos | form_len <= FORM_MAX}
  (form: $A.arr(byte, form_loc, FORM_MAX), form_len: int form_len): $P.promise(dropbox_tokens, $P.Chained) = let
  val url = $A.alloc<byte>(URL_MAX)
  val url_len = request_text(url, 0, "https://api.dropboxapi.com/oauth2/token")
  val headers = $A.alloc<byte>(HEADERS_MAX)
  val headers_len = request_text(headers, 0, "Content-Type: application/x-www-form-urlencoded")
  val @(form_frozen, form_borrow) = $A.freeze<byte>(form)
  val @(form_used, form_rest) = $A.borrow_split<byte>(form_frozen, form_borrow, form_len)
  val pending = request_send("POST", url, url_len, headers, headers_len, form_used, form_len)
  val form_borrow = $A.borrow_join<byte>(form_frozen, form_used, form_rest)
  val () = release_bytes(form_frozen, form_borrow)
in $P.and_then<$FE.fetched><dropbox_tokens>(pending, llam(got) => $P.ret<dropbox_tokens>(_tokens_answer(got))) end

(* The tokens for the code code[0, code_len) the authorization page
   gave, with the verifier of the secrets it was asked with, for the
   app key and the redirect address it was asked with *)
#pub fn dropbox_exchange {key_loc,redirect_loc,code_loc,verifier_loc:agz}{key_size,redirect_size,code_size,verifier_size:nat}
  {key_len:nat | key_len <= key_size}{redirect_len:nat | redirect_len <= redirect_size}{code_len:nat | code_len <= code_size}{verifier_len:nat | verifier_len <= verifier_size}
  (key: !$A.arr(byte, key_loc, key_size), key_len: int key_len, redirect: !$A.arr(byte, redirect_loc, redirect_size), redirect_len: int redirect_len,
   code: !$A.arr(byte, code_loc, code_size), code_len: int code_len, verifier: !$A.arr(byte, verifier_loc, verifier_size), verifier_len: int verifier_len)
  : $P.promise(dropbox_tokens, $P.Chained)

implement dropbox_exchange (key, key_len, redirect, redirect_len, code, code_len, verifier, verifier_len) = let
  val form = $A.alloc<byte>(FORM_MAX)
  val at = _literal(form, FORM_MAX, 0, "grant_type=authorization_code&code=")
  val at = _encoded(form, FORM_MAX, at, code, code_len)
  val at = _literal(form, FORM_MAX, at, "&code_verifier=")
  val at = _encoded(form, FORM_MAX, at, verifier, verifier_len)
  val at = _literal(form, FORM_MAX, at, "&client_id=")
  val at = _encoded(form, FORM_MAX, at, key, key_len)
  val at = _literal(form, FORM_MAX, at, "&redirect_uri=")
  val at = _encoded(form, FORM_MAX, at, redirect, redirect_len)
in
  if at <= 0 then let val () = $A.free<byte>(form) in $P.ret<dropbox_tokens>(DropboxRefused(~3)) end
  else _token_request(form, at)
end

(* A new access token for the refresh token refresh[0, refresh_len) *)
#pub fn dropbox_refresh {key_loc,refresh_loc:agz}{key_size,refresh_size:nat}{key_len:nat | key_len <= key_size}{refresh_len:nat | refresh_len <= refresh_size}
  (key: !$A.arr(byte, key_loc, key_size), key_len: int key_len, refresh: !$A.arr(byte, refresh_loc, refresh_size), refresh_len: int refresh_len)
  : $P.promise(dropbox_tokens, $P.Chained)

implement dropbox_refresh (key, key_len, refresh, refresh_len) = let
  val form = $A.alloc<byte>(FORM_MAX)
  val at = _literal(form, FORM_MAX, 0, "grant_type=refresh_token&refresh_token=")
  val at = _encoded(form, FORM_MAX, at, refresh, refresh_len)
  val at = _literal(form, FORM_MAX, at, "&client_id=")
  val at = _encoded(form, FORM_MAX, at, key, key_len)
in
  if at <= 0 then let val () = $A.free<byte>(form) in $P.ret<dropbox_tokens>(DropboxRefused(~3)) end
  else _token_request(form, at)
end

(* ============================================================
   The file
   ============================================================ *)

(* The revision of the file read: kept from the read for the write
   (none: there was no file) *)
datavtype revision_cell =
  | {l:agz}{revision_len:nat | revision_len <= REVISION_MAX} RevisionCell of ($A.arr(byte, l, REVISION_MAX), int revision_len)

val _revision = ref<revision_cell>(RevisionCell($A.alloc<byte>(REVISION_MAX), 0))

fn _revision_set {l:agz}{revision_len:nat | revision_len <= REVISION_MAX} (revision: $A.arr(byte, l, REVISION_MAX), revision_len: int revision_len): void = let
  var previous: revision_cell = RevisionCell(revision, revision_len)
  val () = ref_exch_elt<revision_cell>(_revision, previous)
  val+ ~RevisionCell(old, _) = previous
in $A.free<byte>(old) end

(* The headers of a request to the file: the access token, the
   Dropbox-API-Arg arg[0, arg_len), and content_type (none when empty) *)
fn _file_headers {token_loc,arg_loc:agz}{token_size,arg_size:nat}{token_len:nat | token_len <= token_size; token_len <= TOKEN_MAX}{arg_len:nat | arg_len <= arg_size; arg_len <= 256}{type_len:nat | type_len <= 40}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len, arg: !$A.arr(byte, arg_loc, arg_size), arg_len: int arg_len, content_type: string type_len)
  : [l:agz][headers_len:nat | headers_len <= HEADERS_MAX] @($A.arr(byte, l, HEADERS_MAX), int headers_len) = let
  val headers = $A.alloc<byte>(HEADERS_MAX)
  val at = request_text(headers, 0, "Authorization: Bearer ")
  val () = request_copy(token, token_len, headers, at, 0)
  val at = request_text(headers, at + token_len, "\nDropbox-API-Arg: ")
  val () = request_copy(arg, arg_len, headers, at, 0)
  val at = at + arg_len
  val type_len = g1u2i(string1_length(content_type))
in
  if type_len <= 0 then @(headers, at)
  else let
    val at = request_text(headers, at, "\nContent-Type: ")
    val () = $A.write_text(headers, at, $A.text_lit(content_type), type_len)
  in @(headers, at + type_len) end
end

(* Whether buf[0, n) holds text *)
fun _same_at {l:agz}{owner:addr}{n:nat}{text_len:pos}{i:nat}{j:nat | j <= text_len} .<text_len - j>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, text: string text_len, text_len: int text_len, i: int i, j: int j): bool =
  if j >= text_len then true
  else if i + j >= n then false
  else if $AR.low_byte(byte2int0($A.get<byte>(buf, i + j))) <> $AR.byte_of_char(string_get_at(text, j)) then false
  else _same_at(buf, n, text, text_len, i, j + 1)

fun _holds {l:agz}{owner:addr}{n:nat}{text_len:pos}{i:nat} .<max(n - i, 0)>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, text: string text_len, text_len: int text_len, i: int i): bool =
  if i + text_len > n then false
  else if _same_at(buf, n, text, text_len, i, 0) then true
  else _holds(buf, n, text, text_len, i + 1)

(* Whether an error's body (a 409's) names the error text *)
fn _error_is {n:nat}{text_len:pos} (blob: $BD.dblob(n), text: string text_len): bool =
  case+ request_body(blob, ANSWER_MAX) of
  | ~BodyRead(owner, bytes, size) => let
      val found = _holds(bytes, size, text, g1u2i(string1_length(text)), 0)
      val () = piece_free(owner, bytes)
    in found end
  | ~BodyEmpty() => false
  | ~BodyFailed(_) => false

(* source[0, count) into out, from j on *)
fun _into {source_loc,out_loc:agz}{owner:addr}{count:nat | count <= 4096}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, 4096), count: int count, out: !$A.arrx(byte, out_loc, count, owner), j: int j): void =
  if j >= count then ()
  else let
    val () = $A.write_byte(out, j, _byte_at(source, j))
  in _into(source, count, out, j + 1) end

(* The revision in a Dropbox-API-Result buf[0, n) *)
fn _revision_in {l,key_loc,revision_loc:agz}{owner:addr}{n:pos}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, key: !$A.arr(byte, key_loc, 16), revision: !$A.arr(byte, revision_loc, REVISION_MAX))
  : [k:nat | k <= REVISION_MAX] int k = let
  val members = jr_object(buf, n, 0)
  val revision_at = (if members >= 0 then jr_member(buf, n, members, key, "rev") else ~1): [at:int | ~1 <= at; at < n] int at
  val @(found, length) = _string_at(buf, n, revision_at, revision, REVISION_MAX)
in if found then length else 0 end

(* The revision in a Dropbox-API-Result result[0, result_len) *)
fn _revision_of {l:agz}{result_len:nat | result_len <= 4096} (result: !$A.arr(byte, l, 4096), result_len: int result_len): void =
  if result_len <= 0 then _revision_set($A.alloc<byte>(REVISION_MAX), 0)
  else (case+ piece_new(result_len) of
    | ~NoPiece() => _revision_set($A.alloc<byte>(REVISION_MAX), 0)
    | ~Piece(owner, bytes) => let
        val () = _into(result, result_len, bytes, 0)
        val key = $A.alloc<byte>(16)
        val revision = $A.alloc<byte>(REVISION_MAX)
        val revision_len = _revision_in(bytes, result_len, key, revision)
        val () = $A.free<byte>(key)
        val () = piece_free(owner, bytes)
      in _revision_set(revision, revision_len) end)

(* The file read, most bytes at most, with the access token *)
#pub fn dropbox_read {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= DROPBOX_TOKEN_MAX}{most:pos | most <= 268435456}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len, most: int most): $P.promise(drive_got, $P.Chained)

implement dropbox_read (token, token_len, most) = let
  val () = _revision_set($A.alloc<byte>(REVISION_MAX), 0)
  val url = $A.alloc<byte>(URL_MAX)
  val url_len = request_text(url, 0, "https://content.dropboxapi.com/2/files/download")
  val arg = $A.alloc<byte>(256)
  val arg_len = request_text(arg, 0, "{\"path\":\"/quire-sync.json\"}")
  val @(headers, headers_len) = _file_headers(token, token_len, arg, arg_len, "")
  val () = $A.free<byte>(arg)
  val pending = request_send_empty("POST", url, url_len, headers, headers_len)
in
  $P.and_then<$FE.fetched><drive_got>(pending, llam(got) => let
    val name = $A.alloc<byte>(18)
    val () = $A.write_text(name, 0, $A.text_lit("Dropbox-API-Result"), 18)
    val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
    val result = $A.alloc<byte>(4096)
    val @(answer, result_len) = request_answered_with(got, name_bytes, 18, result, 4096)
    val () = release_bytes(name_frozen, name_bytes)
  in
    case+ answer of
    | ~Unanswered() => let val () = $A.free<byte>(result) in $P.ret<drive_got>(DriveFailed(0)) end
    | ~Answered(status, blob) =>
      if status = 409 then let
        val () = $A.free<byte>(result)
        (* no file yet: added, not updated, at the write *)
        val missing = _error_is(blob, "not_found")
      in if missing then $P.ret<drive_got>(DriveNothing()) else $P.ret<drive_got>(DriveFailed(409)) end
      else if (if status < 200 then true else status >= 300) then let
        val () = $A.free<byte>(result)
        val () = $BD.blob_free(blob)
      in $P.ret<drive_got>(DriveFailed(status)) end
      else let
        val () = _revision_of(result, result_len)
        val () = $A.free<byte>(result)
      in
        case+ request_body(blob, most) of
        | ~BodyRead(owner, bytes, n) => $P.ret<drive_got>(DriveGot(owner, bytes, n))
        | ~BodyEmpty() => $P.ret<drive_got>(DriveNothing())
        | ~BodyFailed(why) => $P.ret<drive_got>(DriveFailed(why))
      end
  end)
end

(* The upload's Dropbox-API-Arg in arg: an update of the revision
   revision[0, revision_len), or, with none, a new file *)
fn _upload_arg {arg_loc,revision_loc:agz}{revision_len:nat | revision_len <= REVISION_MAX}
  (arg: !$A.arr(byte, arg_loc, 256), revision: !$A.arr(byte, revision_loc, REVISION_MAX), revision_len: int revision_len): [k:nat | k <= 256] int k = let
  val at = request_text(arg, 0, "{\"path\":\"/quire-sync.json\",\"autorename\":false,\"mute\":true,\"mode\":")
in
  if revision_len <= 0 then request_text(arg, at, "\"add\"}")
  else let
    val at = request_text(arg, at, "{\".tag\":\"update\",\"update\":\"")
    val () = request_copy(revision, revision_len, arg, at, 0)
  in request_text(arg, at + revision_len, "\"}}") end
end

(* body[0, body_size) as the file: an update of the revision read, or,
   with none read, a new file; another device's write since the read is
   DriveChanged *)
#pub fn dropbox_write {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= DROPBOX_TOKEN_MAX}{body_loc:agz}{body_size:pos}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len,
   body: !$A.borrow(byte, body_loc, body_size), body_size: int body_size): $P.promise(drive_put, $P.Chained)

implement dropbox_write (token, token_len, body, body_size) = let
  var held: revision_cell = RevisionCell($A.alloc<byte>(REVISION_MAX), 0)
  val () = ref_exch_elt<revision_cell>(_revision, held)
  val+ ~RevisionCell(revision, revision_len) = held
  val arg = $A.alloc<byte>(256)
  val arg_len = _upload_arg(arg, revision, revision_len)
  val () = _revision_set(revision, revision_len)
  val url = $A.alloc<byte>(URL_MAX)
  val url_len = request_text(url, 0, "https://content.dropboxapi.com/2/files/upload")
  val @(headers, headers_len) = _file_headers(token, token_len, arg, arg_len, "application/octet-stream")
  val () = $A.free<byte>(arg)
  val pending = request_send("POST", url, url_len, headers, headers_len, body, body_size)
in
  $P.and_then<$FE.fetched><drive_put>(pending, llam(got) =>
    case+ request_answered(got) of
    | ~Unanswered() => $P.ret<drive_put>(DrivePutFailed(0))
    | ~Answered(status, blob) =>
      if status = 409 then
        (if _error_is(blob, "conflict") then $P.ret<drive_put>(DriveChanged()) else $P.ret<drive_put>(DrivePutFailed(409)))
      else let
        val () = $BD.blob_free(blob)
      in
        if (if status >= 200 then status < 300 else false) then $P.ret<drive_put>(DrivePut())
        else $P.ret<drive_put>(DrivePutFailed(status))
      end)
end

(* The access token revoked (Turn off): its refresh token goes with it;
   resolves 0 when Dropbox took it *)
#pub fn dropbox_revoke {token_loc:agz}{token_size:nat}{token_len:pos | token_len <= token_size; token_len <= DROPBOX_TOKEN_MAX}
  (token: !$A.arr(byte, token_loc, token_size), token_len: int token_len): $P.promise(int, $P.Chained)

implement dropbox_revoke (token, token_len) = let
  val url = $A.alloc<byte>(URL_MAX)
  val url_len = request_text(url, 0, "https://api.dropboxapi.com/2/auth/token/revoke")
  val headers = $A.alloc<byte>(HEADERS_MAX)
  val at = request_text(headers, 0, "Authorization: Bearer ")
  val () = request_copy(token, token_len, headers, at, 0)
  val pending = request_send_empty("POST", url, url_len, headers, at + token_len)
in
  $P.and_then<$FE.fetched><int>(pending, llam(got) =>
    case+ request_answered(got) of
    | ~Unanswered() => $P.ret<int>(1)
    | ~Answered(status, blob) => let
        val () = $BD.blob_free(blob)
      in $P.ret<int>(if status = 200 then 0 else 1) end)
end

end (* #target wasm *)
