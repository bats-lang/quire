(* layer -- the overlays over the library and the reader, and which of
   them are open, in the order they were opened *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "ui.sats"

(* The overlays. Each is one element, whose id only this module knows,
   so an overlay is shown or hidden only here, and the stack below is
   always the overlays that are open, the last opened on top. (The
   dialog, src/modal.bats, is above them all and keeps its own state.) *)
#pub datatype layer =
  | LBookMenu      (* a book's menu *)
  | LLibraryMenu   (* the library menu *)
  | LBookInfo      (* a book's info *)
  | LContents      (* contents and bookmarks *)
  | LTypography    (* typography and theme *)
  | LSearch        (* search in the book *)
  | LAnnotations   (* highlights and notes *)
  | LNote          (* a note, opened from its reference *)
  | LImage         (* a book's image, full screen *)
  | LCollections   (* a book's collections *)

fn _id (l: layer): [k:pos | k < 256] string k =
  case+ l of
  | LBookMenu() => "card-menu" | LLibraryMenu() => "library-menu" | LBookInfo() => "book-info"
  | LContents() => "contents-panel" | LTypography() => "typography-panel" | LSearch() => "search-panel"
  | LAnnotations() => "annotations-panel" | LNote() => "footnote" | LImage() => "image-viewer"
  | LCollections() => "collections-menu"

fn _n (l: layer): int =
  case+ l of
  | LBookMenu() => 0 | LLibraryMenu() => 1 | LBookInfo() => 2 | LContents() => 3
  | LTypography() => 4 | LSearch() => 5 | LAnnotations() => 6 | LNote() => 7 | LImage() => 8
  | LCollections() => 9

(* The open overlays, the last opened first *)
datatype layers(int) =
  | LNil(0)
  | {n:nat} LCons(n + 1) of (layer, layers(n))

val _open = ref<[n:nat] layers(n)>(LNil())

(* ls without l *)
fun _without {n:nat} .<n>. (ls: layers(n), l: layer): [m:nat | m <= n] layers(m) =
  case+ ls of
  | LNil() => LNil()
  | LCons(x, rest) => if _n(x) = _n(l) then _without(rest, l) else LCons(x, _without(rest, l))

fun _has {n:nat} .<n>. (ls: layers(n), l: layer): bool =
  case+ ls of
  | LNil() => false
  | LCons(x, rest) => if _n(x) = _n(l) then true else _has(rest, l)

(* Opens l on top of the others (moving it there if it was open) *)
#pub fn layer_open (l: layer): void
implement layer_open (l) = let
  val () = !_open := LCons(l, _without(!_open, l))
in ui_show(_id(l), true) end

(* Closes l *)
#pub fn layer_close (l: layer): void
implement layer_close (l) = let
  val () = !_open := _without(!_open, l)
in ui_show(_id(l), false) end

(* Whether l is open *)
#pub fn layer_is_open (l: layer): bool
implement layer_is_open (l) = _has(!_open, l)

fun _close_each {n:nat} .<n>. (ls: layers(n)): void =
  case+ ls of
  | LNil() => ()
  | LCons(x, rest) => let val () = ui_show(_id(x), false) in _close_each(rest) end

(* Closes every overlay; true when one was open *)
#pub fn layer_close_all (): bool
implement layer_close_all () = let
  val ls = !_open
  val () = !_open := LNil()
  val () = _close_each(ls)
in case+ ls of LNil() => false | LCons(_, _) => true end

(* The answer to Escape: the overlay opened last is closed, and returned *)
#pub datatype escaped = Escaped of layer | NothingOpen

#pub fn layer_escape (): escaped
implement layer_escape () =
  case+ !_open of
  | LNil() => NothingOpen()
  | LCons(l, rest) => let
      val () = !_open := rest
      val () = ui_show(_id(l), false)
    in Escaped(l) end

end (* #target wasm *)
