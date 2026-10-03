(* web_request -- requests to a web service's API, as the sync stores
   make them (drive.bats, dropbox.bats): a method, a URL, headers as
   "Name: value" lines, a body; the answer's status, one header and its
   body, read into a piece *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R

staload "book.sats"
staload "mem.sats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A request's URL's and its headers' most bytes *)
#pub stadef REQUEST_URL_MAX = 1024
#pub stadef REQUEST_HEADERS_MAX = 4600

(* literal at out[position] *)
#pub fn request_text {l:agz}{n:nat}{position:nat}{text_len:nat | position + text_len <= n}
  (out: !$A.arr(byte, l, n), position: int position, text: string text_len): int(position + text_len)

implement request_text (out, position, text) = let
  val text_len = g1u2i(string1_length(text))
  val () = $A.write_text(out, position, $A.text_lit(text), text_len)
in position + text_len end

(* source[0, count) at out[position], from j on *)
#pub fun request_copy {source_loc,out_loc:agz}{source_size,out_size:nat}{count:nat | count <= source_size}{position:nat | position + count <= out_size}{j:nat | j <= count}
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arr(byte, out_loc, out_size), position: int position, j: int j): void

fun _copy {source_loc,out_loc:agz}{source_size,out_size:nat}{count:nat | count <= source_size}{position:nat | position + count <= out_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arr(byte, out_loc, out_size), position: int position, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, position + j, $A.get<byte>(source, j))
  in _copy(source, count, out, position, j + 1) end

implement request_copy (source, count, out, position, j) = _copy(source, count, out, position, j)

(* method for url[0, url_len), with the headers and body[0, body_len) *)
#pub fn request_send {method_len:pos | method_len <= 8}{url_loc:agz}{url_len:pos | url_len <= REQUEST_URL_MAX}{headers_loc:agz}{headers_len:nat | headers_len <= REQUEST_HEADERS_MAX}{body_loc:agz}{body_size:nat}{body_len:nat | body_len <= body_size}
  (method: string method_len, url: $A.arr(byte, url_loc, REQUEST_URL_MAX), url_len: int url_len,
   headers: $A.arr(byte, headers_loc, REQUEST_HEADERS_MAX), headers_len: int headers_len,
   body: !$A.borrow(byte, body_loc, body_size), body_len: int body_len): $P.promise($FE.fetched, $P.Chained)

implement request_send (method, url, url_len, headers, headers_len, body, body_len) = let
  val method_len = g1u2i(string1_length(method))
  val method_bytes = $A.alloc<byte>(method_len)
  val () = $A.write_text(method_bytes, 0, $A.text_lit(method), method_len)
  val @(method_frozen, method_borrow) = $A.freeze<byte>(method_bytes)
  val @(url_frozen, url_borrow) = $A.freeze<byte>(url)
  val @(url_used, url_rest) = $A.borrow_split<byte>(url_frozen, url_borrow, url_len)
  val @(headers_frozen, headers_borrow) = $A.freeze<byte>(headers)
  val pending = $FE.fetch_request(method_borrow, method_len, url_used, url_len, headers_borrow, headers_len, body, body_len)
  val () = release_bytes(headers_frozen, headers_borrow)
  val url_borrow = $A.borrow_join<byte>(url_frozen, url_used, url_rest)
  val () = release_bytes(url_frozen, url_borrow)
  val () = release_bytes(method_frozen, method_borrow)
in pending end

(* method for url[0, url_len) with no body *)
#pub fn request_send_empty {method_len:pos | method_len <= 8}{url_loc:agz}{url_len:pos | url_len <= REQUEST_URL_MAX}{headers_loc:agz}{headers_len:nat | headers_len <= REQUEST_HEADERS_MAX}
  (method: string method_len, url: $A.arr(byte, url_loc, REQUEST_URL_MAX), url_len: int url_len,
   headers: $A.arr(byte, headers_loc, REQUEST_HEADERS_MAX), headers_len: int headers_len): $P.promise($FE.fetched, $P.Chained)

implement request_send_empty (method, url, url_len, headers, headers_len) = let
  val empty = $A.alloc<byte>(1)
  val @(empty_frozen, empty_borrow) = $A.freeze<byte>(empty)
  val pending = request_send(method, url, url_len, headers, headers_len, empty_borrow, 0)
  val () = release_bytes(empty_frozen, empty_borrow)
in pending end

(* A response's status and body; none when no response came *)
#pub datavtype answered =
  | {n:nat} Answered of ([s:int] int s, $BD.dblob(n))
  | Unanswered of ()

#pub fn request_answered (got: $FE.fetched): answered

implement request_answered (got) =
  case+ got of
  | ~$FE.NoResponse() => Unanswered()
  | ~$FE.Responded(response) => let
      val status = $FE.fetch_status(response)
    in Answered(status, $FE.fetch_body(response)) end

(* request_answered, with the response's header name[0, name_len)
   written to out: its length (0 when it has none) *)
#pub fn request_answered_with {name_loc,out_loc:agz}{name_len:pos}{out_size:pos}
  (got: $FE.fetched, name: !$A.borrow(byte, name_loc, name_len), name_len: int name_len,
   out: !$A.arr(byte, out_loc, out_size), out_size: int out_size): @(answered, [k:nat | k <= out_size] int k)

implement request_answered_with {name_loc,out_loc}{name_len}{out_size} (got, name, name_len, out, out_size) =
  case+ got of
  | ~$FE.NoResponse() => @(Unanswered(), 0)
  | ~$FE.Responded(response) => let
      val found = $FE.fetch_header(response, name, name_len, out, out_size)
      val length = (case+ found of ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= out_size] int k
      val status = $FE.fetch_status(response)
    in @(Answered(status, $FE.fetch_body(response)), length) end

(* A body of at most most bytes, in a piece; failed with -1 when it is
   larger, -2 when there is no memory for it *)
#pub datavtype body_read =
  | {owner,l:agz}{n:pos | n <= 268435456} BodyRead of (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int n)
  | BodyEmpty of ()
  | BodyFailed of (Int)

#pub fn request_body {n:nat}{most:pos | most <= 268435456} (blob: $BD.dblob(n), most: int most): body_read

implement request_body (blob, most) = let
  val size = $BD.blob_len(blob)
in
  if size <= 0 then let val () = $BD.blob_free(blob) in BodyEmpty() end
  else if size > most then let val () = $BD.blob_free(blob) in BodyFailed(~1) end
  else (case+ piece_new(size) of
    | ~NoPiece() => let val () = $BD.blob_free(blob) in BodyFailed(~2) end
    | ~Piece(owner, bytes) => let
        val () = $BD.blob_read(blob, 0, bytes, size)
        val () = $BD.blob_free(blob)
      in BodyRead(owner, bytes, size) end)
end

end (* #target wasm *)
