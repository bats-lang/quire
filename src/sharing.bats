(* sharing -- the system's share sheet: a selection with its citation,
   and the annotations as a Markdown file *)

(* Bridge's share_text and share_file: Web Share in a browser, the
   Share plugin in the app. Share is offered only where text can be
   shared (share_available); a file is shared as one where files can be
   (share_file_available), and as its text where they cannot, or where
   this one was refused as a file (FilesNotShareable). Each share is
   started from a click's listener, as a browser asks. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "ui.sats"
staload "mem.sats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* Share, shown only where something can be shared *)
#pub fn sharing_show (): void

implement sharing_show () = let
  val shareable = $SH.share_available()
  val () = ui_show("selection-share", shareable)
in ui_show("annotations-share", shareable) end

(* How a file is shared: as a file, or as its text *)
#pub datatype share_as = AsFile | AsText

#pub fn share_as_now (): share_as
implement share_as_now () = if $SH.share_file_available() then AsFile() else AsText()

(* A string's bytes, at out[at, at + |text|) *)
fun _put_from {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (out: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.set<byte>(out, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_from(out, at, text, text_len, i + 1) end

(* A string as a fresh array, with its length *)
fn _bytes_of {text_len:pos | text_len < 256} (text: string text_len): [l:agz] @($A.arr(byte, l, text_len), int text_len) = let
  val text_len = g1u2i(string1_length(text))
  val bytes = $A.alloc<byte>(text_len)
  val _ = _put_from(bytes, 0, text, text_len, 0)
in @(bytes, text_len) end

(* The Markdown file bytes[0, len), named quire-annotations.md, shared:
   as a file (AsFile), or as its text, titled by its name (AsText);
   as_text runs when the file is refused as one (the platform cannot
   share it), to share its text instead *)
#pub fn share_markdown {l:agz}{len:pos} (bytes: !$A.borrow(byte, l, len), len: int len, way: share_as, as_text: () -<cloref1> void): void

implement share_markdown (bytes, len, way, as_text) = let
  val @(name, name_len) = _bytes_of("quire-annotations.md")
  val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
in
  case+ way of
  | AsFile() => let
      val @(mime, mime_len) = _bytes_of("text/markdown")
      val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime)
      val sharing = $SH.share_file(name_bytes, name_len, bytes, len, mime_bytes, mime_len)
      val () = release_bytes(mime_frozen, mime_bytes)
      val () = release_bytes(name_frozen, name_bytes)
    in
      $P.finish<$SH.file_share_outcome>(sharing, lam(outcome) =>
        case+ outcome of
        | $SH.FilesNotShareable() => as_text()
        | $SH.FileShared() => ()
        | $SH.FileShareCancelled() => ()
        | $SH.FileShareFailed() => ())
    end
  | AsText() => let
      val sharing = $SH.share_text(name_bytes, name_len, bytes, len)
      val () = release_bytes(name_frozen, name_bytes)
    in
      (* how it ended is the share sheet's to show *)
      $P.finish<$SH.share_outcome>(sharing, lam(_) => ())
    end
end

(* ============================================================
   A selection, quoted and cited
   ============================================================ *)

(* Whether a byte is white space (space, tab, line breaks) *)
fn _space (code: int): bool = if code = 32 then true else if code = 9 then true else if code = 10 then true else code = 13

fun _first_text {l:agz}{n:pos}{at:nat | at <= n} .<n - at>. (text: !$A.arr(byte, l, n), n: int n, at: int at): [first:nat | first <= n] int first =
  if at >= n then n
  else if _space(byte2int0($A.get<byte>(text, at))) then _first_text(text, n, at + 1)
  else at

fun _text_end {l:agz}{n:pos}{low:nat}{stop:nat | low <= stop; stop <= n} .<stop - low>. (text: !$A.arr(byte, l, n), low: int low, stop: int stop): [end_at:nat | low <= end_at; end_at <= stop] int end_at =
  if stop <= low then low
  else if _space(byte2int0($A.get<byte>(text, stop - 1))) then _text_end(text, low, stop - 1)
  else stop

fun _copy {source_loc,out_loc:agz}{source_size,out_size:pos}{from,count:nat | from + count <= source_size}{at:nat | at + count <= out_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), from: int from, count: int count, out: !$A.arr(byte, out_loc, out_size), at: int at, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(out, at + i, $A.get<byte>(source, from + i))
  in _copy(source, from, count, out, at, i + 1) end

(* The selection shared, quoted ("…" with typographic quotes) and, when
   there is one, cited on a line of its own after a dash:
   citation[0, citation_len) ("Author, Title"). Frees citation *)
#pub fn share_selection {l:agz}{n:pos}{citation_len:nat | citation_len <= n; citation_len <= 1024}
  (citation: $A.arr(byte, l, n), citation_len: int citation_len): void

implement share_selection (citation, citation_len) =
  case+ $DR.get_selection_text() of
  | ~$R.none() => $A.free<byte>(citation)
  | ~$R.some(selection) => let
      val selection_len = $BD.blob_len(selection)
    in
      if selection_len <= 0 then let
        val () = $BD.blob_free(selection)
      in $A.free<byte>(citation) end
      else if selection_len > 1040000 then let
        val () = $BD.blob_free(selection)
      in $A.free<byte>(citation) end
      else let
        val text = $A.alloc<byte>(selection_len)
        val () = $BD.blob_read(selection, 0, text, selection_len)
        val () = $BD.blob_free(selection)
        val first = _first_text(text, selection_len, 0)
        val last = _text_end(text, first, selection_len)
        val quoted_len = last - first
      in
        if quoted_len <= 0 then let
          val () = $A.free<byte>(text)
        in $A.free<byte>(citation) end
        else let
          (* the quotes and the dash are 3 bytes each in UTF-8, the line
             break and the space after the dash 1 *)
          val out_size = 3 + quoted_len + 3 + 1 + 3 + 1 + citation_len
          val out_len = (if citation_len > 0 then out_size else 3 + quoted_len + 3): Int
          val [out_loc:addr] out = $A.alloc<byte>(out_size)
          val at = _put_from(out, 0, "\xE2\x80\x9C", 3, 0)
          val () = _copy(text, first, quoted_len, out, at, 0)
          val at = _put_from(out, at + quoted_len, "\xE2\x80\x9D", 3, 0)
          val () = (if citation_len > 0 then let
              val at = _put_from(out, at, "\n\xE2\x80\x94 ", 5, 0)
            in _copy(citation, 0, citation_len, out, at, 0) end else ())
          val () = $A.free<byte>(text)
          val () = $A.free<byte>(citation)
        in
          if out_len <= 0 then $A.free<byte>(out)
          else if out_len > out_size then let val () = $A.free<byte>(out) in () end
          else let
          val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
          val @(shared, rest) = $A.borrow_split<byte>(out_frozen, out_bytes, out_len)
          val title = $A.alloc<byte>(1)
          val @(title_frozen, title_bytes) = $A.freeze<byte>(title)
          val sharing = $SH.share_text(title_bytes, 0, shared, out_len)
          val () = release_bytes(title_frozen, title_bytes)
          val out_bytes = $A.borrow_join<byte>(out_frozen, shared, rest)
          val () = release_bytes(out_frozen, out_bytes)
        in
          (* how it ended is the share sheet's to show *)
          $P.finish<$SH.share_outcome>(sharing, lam(_) => ())
        end
        end
      end
    end

end (* #target wasm *)
