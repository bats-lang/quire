(* sync_clients -- the OAuth clients this build signs in with (#184)

   A client ID is public: it ships in the app, and it is not a secret.
   It is not compiled in: scripts/sync-clients.sh writes the build's
   (from the repository's variables, checked there) into
   sync-clients.json beside the app, {"googleWebClient": "<id>"}, and
   it is read here once, as the app starts. A build without one (a
   fork's, a local one) has an empty ID, and what needs it says it is
   not set up. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P

staload "book.sats"
staload "mem.sats"
staload "jsonio.sats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A client ID's most bytes, and the file's *)
#define CLIENT_MAX 256
#define FILE_MAX 4096

datavtype client_cell =
  | {l:agz}{client_len:nat | client_len <= CLIENT_MAX} ClientCell of ($A.arr(byte, l, CLIENT_MAX), int client_len)

val _google = ref<client_cell>(ClientCell($A.alloc<byte>(CLIENT_MAX), 0))
val _dropbox = ref<client_cell>(ClientCell($A.alloc<byte>(CLIENT_MAX), 0))

fn _client_swap (cell: ref(client_cell), client: client_cell): client_cell = let
  var previous: client_cell = client
  val () = ref_exch_elt<client_cell>(cell, previous)
in previous end

fn _google_swap (cell: client_cell): client_cell = let
  var previous: client_cell = cell
  val () = ref_exch_elt<client_cell>(_google, previous)
in previous end


(* The client ID the file buf[0, n) names name, kept in cell *)
fn _client_of {l,key_loc:agz}{owner:addr}{n:nat}{name_len:pos}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, key: !$A.arr(byte, key_loc, 16), name: string name_len, cell: ref(client_cell)): void = let
  val members = (if n > 0 then jr_object(buf, n, 0) else ~1): [inside:int | ~1 <= inside; inside <= n] int inside
  val at = (if members >= 0 then jr_member(buf, n, members, key, name) else ~1): [at:int | ~1 <= at; at < n] int at
  val client = $A.alloc<byte>(CLIENT_MAX)
in
  if at < 0 then $A.free<byte>(client)
  else let
    val @(found, client_len, _) = jr_str(buf, n, at, client, CLIENT_MAX)
  in
    if found then let
      val+ ~ClientCell(previous, _) = _client_swap(cell, ClientCell(client, client_len))
    in $A.free<byte>(previous) end
    else $A.free<byte>(client)
  end
end

(* Reads sync-clients.json, once, as the app starts; resolves when it is
   read, or found not there (0) *)
#pub fn sync_clients_load (): $P.promise(int, $P.Chained)

implement sync_clients_load () = let
  val name = $A.alloc<byte>(17)
  val () = $A.write_text(name, 0, $A.text_lit("sync-clients.json"), 17)
  val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
  val pending = $FE.fetch(name_bytes, 17)
  val () = release_bytes(name_frozen, name_bytes)
in
  $P.and_then<$FE.fetched><int>(pending, llam(got) =>
    case+ got of
    | ~$FE.NoResponse() => $P.ret<int>(0)
    | ~$FE.Responded(response) => let
        val status = $FE.fetch_status(response)
        val body = $FE.fetch_body(response)
        val size = $BD.blob_len(body)
      in
        if status <> 200 then let val () = $BD.blob_free(body) in $P.ret<int>(0) end
        else if size <= 0 then let val () = $BD.blob_free(body) in $P.ret<int>(0) end
        else if size > FILE_MAX then let val () = $BD.blob_free(body) in $P.ret<int>(0) end
        else (case+ piece_new(size) of
          | ~NoPiece() => let val () = $BD.blob_free(body) in $P.ret<int>(0) end
          | ~Piece(owner, file) => let
              val () = $BD.blob_read(body, 0, file, size)
              val () = $BD.blob_free(body)
              val key = $A.alloc<byte>(16)
              val () = _client_of(file, size, key, "googleWebClient", _google)
              val () = _client_of(file, size, key, "dropboxClient", _dropbox)
              val () = $A.free<byte>(key)
              val () = piece_free(owner, file)
            in $P.ret<int>(0) end)
      end)
end

(* The Google web client's ID (empty when this build has none), at
   out[0, its length) *)
#pub fn sync_clients_google {l:agz} (out: !$A.arr(byte, l, 256)): [client_len:nat | client_len <= 256] int client_len

fun _copy {source_loc,out_loc:agz}{count:nat | count <= 256}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, CLIENT_MAX), count: int count, out: !$A.arr(byte, out_loc, 256), j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(source, j))
  in _copy(source, count, out, j + 1) end

(* Dropbox's app key (empty when this build has none), as
   sync_clients_google *)
#pub fn sync_clients_dropbox {l:agz} (out: !$A.arr(byte, l, 256)): [client_len:nat | client_len <= 256] int client_len

implement sync_clients_dropbox (out) = let
  val+ ~ClientCell(client, client_len) = _client_swap(_dropbox, ClientCell($A.alloc<byte>(CLIENT_MAX), 0))
  val () = _copy(client, client_len, out, 0)
  val+ ~ClientCell(empty, _) = _client_swap(_dropbox, ClientCell(client, client_len))
  val () = $A.free<byte>(empty)
in client_len end

implement sync_clients_google (out) = let
  val+ ~ClientCell(client, client_len) = _google_swap(ClientCell($A.alloc<byte>(CLIENT_MAX), 0))
  val () = _copy(client, client_len, out, 0)
  val+ ~ClientCell(empty, _) = _google_swap(ClientCell(client, client_len))
  val () = $A.free<byte>(empty)
in client_len end

end (* #target wasm *)
