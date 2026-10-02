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
  | LStats         (* the reading statistics *)
  | LDictionaries  (* the dictionaries: imported, listed and removed *)
  | LDictionary    (* a word looked up in a dictionary *)
  | LCatalogues    (* the catalogues: listed, added and removed *)
  | LCatalogue     (* a catalogue's pages, browsed *)
  | LSync          (* sync between devices: its folder, and how it went *)
  | LSettings      (* the Settings screen: sync, dictionaries, backup, goal, resets *)

fn _element_id (overlay: layer): [id_len:pos | id_len < 256] string id_len =
  case+ overlay of
  | LBookMenu() => "card-menu" | LLibraryMenu() => "library-menu" | LBookInfo() => "book-info"
  | LContents() => "contents-panel" | LTypography() => "typography-panel" | LSearch() => "search-panel"
  | LAnnotations() => "annotations-panel" | LNote() => "footnote" | LImage() => "image-viewer"
  | LCollections() => "collections-menu" | LStats() => "stats-panel"
  | LDictionaries() => "dictionaries-panel" | LDictionary() => "dictionary-panel"
  | LCatalogues() => "catalogues-panel" | LCatalogue() => "catalogue-panel"
  | LSync() => "sync-screen" | LSettings() => "settings-screen"

fn _number (overlay: layer): int =
  case+ overlay of
  | LBookMenu() => 0 | LLibraryMenu() => 1 | LBookInfo() => 2 | LContents() => 3
  | LTypography() => 4 | LSearch() => 5 | LAnnotations() => 6 | LNote() => 7 | LImage() => 8
  | LCollections() => 9 | LStats() => 10 | LDictionaries() => 11 | LDictionary() => 12
  | LCatalogues() => 13 | LCatalogue() => 14
  | LSync() => 15 | LSettings() => 16

(* The open overlays, the last opened first *)
datavtype layers(int) =
  | LNil(0) of ()
  | {count:nat} LCons(count + 1) of (layer, layers(count))

val _open = ref<[count:nat] layers(count)>(LNil())

fn _open_take (): [count:nat] layers(count) = let
  var taken: [count:nat] layers(count) = LNil()
  val () = ref_exch_elt<[count:nat] layers(count)>(_open, taken)
in taken end

fun _layers_free {count:nat} .<count>. (overlays: layers(count)): void =
  case+ overlays of
  | ~LNil() => ()
  | ~LCons(_, rest) => _layers_free(rest)

fn _open_put {count:nat} (overlays: layers(count)): void = let
  var previous: [count:nat] layers(count) = overlays
  val () = ref_exch_elt<[count:nat] layers(count)>(_open, previous)
in _layers_free(previous) end

(* overlays without overlay *)
fun _without {count:nat} .<count>. (overlays: layers(count), overlay: layer): [left:nat | left <= count] layers(left) =
  case+ overlays of
  | ~LNil() => LNil()
  | ~LCons(first, rest) => if _number(first) = _number(overlay) then _without(rest, overlay) else LCons(first, _without(rest, overlay))

fun _has {count:nat} .<count>. (overlays: !layers(count), overlay: layer): bool =
  case+ overlays of
  | LNil() => false
  | LCons(first, rest) => if _number(first) = _number(overlay) then true else _has(rest, overlay)

(* Opens overlay on top of the others (moving it there if it was open) *)
#pub fn layer_open (overlay: layer): void
implement layer_open (overlay) = let
  val () = _open_put(LCons(overlay, _without(_open_take(), overlay)))
in ui_show(_element_id(overlay), true) end

(* Closes overlay *)
#pub fn layer_close (overlay: layer): void
implement layer_close (overlay) = let
  val () = _open_put(_without(_open_take(), overlay))
in ui_show(_element_id(overlay), false) end

(* Whether overlay is open *)
#pub fn layer_is_open (overlay: layer): bool
implement layer_is_open (overlay) = let
  val overlays = _open_take()
  val open = _has(overlays, overlay)
  val () = _open_put(overlays)
in open end

fun _close_each {count:nat} .<count>. (overlays: layers(count)): void =
  case+ overlays of
  | ~LNil() => ()
  | ~LCons(first, rest) => let val () = ui_show(_element_id(first), false) in _close_each(rest) end

(* Closes every overlay; true when one was open *)
#pub fn layer_close_all (): bool
implement layer_close_all () = let
  val overlays = _open_take()
  val any = (case+ overlays of LNil() => false | LCons(_, _) => true): bool
  val () = _close_each(overlays)
in any end

(* The answer to Escape: the overlay opened last is closed, and returned *)
#pub datavtype escaped = Escaped of layer | NothingOpen of ()

#pub fn layer_escape (): escaped
implement layer_escape () =
  case+ _open_take() of
  | ~LNil() => NothingOpen()
  | ~LCons(overlay, rest) => let
      val () = _open_put(rest)
      val () = ui_show(_element_id(overlay), false)
    in Escaped(overlay) end

end (* #target wasm *)
