(* layer -- the overlays over the library and the reader, and which of
   them are open, in the order they were opened *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "ui.sats"
staload "back.sats"

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
  | LAbout         (* the About screen: the app's name, and links to its pages and source *)
  | LSyncStep      (* a sync service's own sign-in step, over the Sync screen's list (#331) *)
  | LSortMenu      (* the sort and view menu (#377, #404) *)
  | LShelf         (* a shelf's own screen over the library: Hidden, Archived or Trash (#404) *)

fn _element_id (overlay: layer): [id_len:pos | id_len < 128] string id_len =
  case+ overlay of
  | LBookMenu() => "card-menu" | LLibraryMenu() => "library-menu" | LBookInfo() => "book-info"
  | LContents() => "contents-panel" | LTypography() => "typography-panel" | LSearch() => "search-panel"
  | LAnnotations() => "annotations-panel" | LNote() => "footnote" | LImage() => "image-viewer"
  | LCollections() => "collections-menu" | LStats() => "stats-panel"
  | LDictionaries() => "dictionaries-panel" | LDictionary() => "dictionary-panel"
  | LCatalogues() => "catalogues-panel" | LCatalogue() => "catalogue-panel"
  | LSync() => "sync-screen" | LSettings() => "settings-screen"
  | LAbout() => "about-screen"
  | LSyncStep() => "sync-step"
  | LSortMenu() => "sort-menu"
  | LShelf() => "shelf-header"

fn _number (overlay: layer): int =
  case+ overlay of
  | LBookMenu() => 0 | LLibraryMenu() => 1 | LBookInfo() => 2 | LContents() => 3
  | LTypography() => 4 | LSearch() => 5 | LAnnotations() => 6 | LNote() => 7 | LImage() => 8
  | LCollections() => 9 | LStats() => 10 | LDictionaries() => 11 | LDictionary() => 12
  | LCatalogues() => 13 | LCatalogue() => 14
  | LSync() => 15 | LSettings() => 16 | LAbout() => 17
  | LSyncStep() => 18 | LSortMenu() => 19 | LShelf() => 20

(* The reader's panels, which are modal (Material 3's modal bottom
   sheet, WAI-ARIA's modal dialog): while one is open, a scrim covers the
   reader, a tap on it closes the panel, the reader view is inert (no
   tap, drag, key or focus reaches the page), Tab keeps to the panel,
   and the focus goes back where it was when the panel closes. The
   other overlays are menus and screens that keep their own ways. *)
fn _over_reader (overlay: layer): bool =
  case+ overlay of
  | LContents() => true | LTypography() => true | LSearch() => true
  | LAnnotations() => true | LNote() => true | LImage() => true
  | LDictionary() => true
  | LBookMenu() => false | LLibraryMenu() => false | LBookInfo() => false
  | LCollections() => false | LStats() => false | LDictionaries() => false
  | LCatalogues() => false | LCatalogue() => false | LSync() => false
  | LSettings() => false | LAbout() => false
  | LSyncStep() => false | LSortMenu() => false | LShelf() => false

(* Whether a reader panel dims the reader behind it. A panel that explains
   a place in the text (a note, a word looked up) does not: the scrim
   would dim the very words it is about, so it leaves the reader as it
   is and places itself clear of them (ui_sheet_place; quire#387, HIG:
   "a popover doesn't cover the element that revealed it") *)
datatype scrim = Veils | Clear

fn _scrim_of (overlay: layer): scrim =
  case+ overlay of
  | LNote() => Clear()
  | LDictionary() => Clear()
  | LContents() => Veils() | LTypography() => Veils() | LSearch() => Veils()
  | LAnnotations() => Veils() | LImage() => Veils()
  | LBookMenu() => Veils() | LLibraryMenu() => Veils() | LBookInfo() => Veils()
  | LCollections() => Veils() | LStats() => Veils() | LDictionaries() => Veils()
  | LCatalogues() => Veils() | LCatalogue() => Veils() | LSync() => Veils()
  | LSettings() => Veils() | LAbout() => Veils()
  | LSyncStep() => Veils() | LSortMenu() => Veils() | LShelf() => Veils()

(* The open overlays, the last opened first, each with where the focus
   goes back to when it closes *)
datavtype layers(int) =
  | LNil(0) of ()
  | {count:nat} LCons(count + 1) of (layer, focus_return, layers(count))

val _open = ref<[count:nat] layers(count)>(LNil())

fn _open_take (): [count:nat] layers(count) = let
  var taken: [count:nat] layers(count) = LNil()
  val () = ref_exch_elt<[count:nat] layers(count)>(_open, taken)
in taken end

fun _layers_free {count:nat} .<count>. (overlays: layers(count)): void =
  case+ overlays of
  | ~LNil() => ()
  | ~LCons(_, back, rest) => let val () = ui_focus_return_free(back) in _layers_free(rest) end

(* The top reader panel open, if any *)
datavtype top_panel = NoPanel of () | PanelOnTop of layer

fun _top_panel {count:nat} .<count>. (overlays: !layers(count)): top_panel =
  case+ overlays of
  | LNil() => NoPanel()
  | LCons(first, _, rest) => if _over_reader(first) then PanelOnTop(first) else _top_panel(rest)

fn _blocked {count:nat} (overlays: !layers(count)): bool =
  case+ _top_panel(overlays) of ~PanelOnTop(_) => true | ~NoPanel() => false

(* The scrim and the reader's inertness, as the open overlays say: both
   exactly while a reader panel is open, and the focus guards (the
   stops before and after the panels, focus-wrap-start and
   focus-wrap-end) take the focus only then *)
fn _modality_show {count:nat} (overlays: !layers(count)): void = let
  val blocked = _blocked(overlays)
  val veiled = (case+ _top_panel(overlays) of
    | ~NoPanel() => false
    | ~PanelOnTop(top) => (case+ _scrim_of(top) of Veils() => true | Clear() => false)): bool
  val () = ui_show("panel-scrim", veiled)
  val () = ui_inert("reader", blocked)
in
  if blocked then let
    val () = ui_attr("focus-wrap-start", ATabindex, "0")
  in ui_attr("focus-wrap-end", ATabindex, "0") end
  else let
    val () = ui_attr("focus-wrap-start", ATabindex, "-1")
  in ui_attr("focus-wrap-end", ATabindex, "-1") end
end

fn _open_put {count:nat} (overlays: layers(count)): void = let
  var previous: [count:nat] layers(count) = overlays
  val () = ref_exch_elt<[count:nat] layers(count)>(_open, previous)
in _layers_free(previous) end

(* The open overlays changed: the scrim and the reader follow, and what
   Back has to go back from (back.bats) *)
fn _open_set {count:nat} (overlays: layers(count)): void = let
  val () = _modality_show(overlays)
  val any = (case+ overlays of LNil() => NotShown() | LCons(_, _, _) => Shown()): shown
  val () = _open_put(overlays)
in back_overlays_set(any) end

(* overlays without overlay, and where the focus went back to from it *)
fun _without {count:nat} .<count>. (overlays: layers(count), overlay: layer, back: focus_return): [left:nat | left <= count] @(layers(left), focus_return) =
  case+ overlays of
  | ~LNil() => @(LNil(), back)
  | ~LCons(first, first_back, rest) =>
    if _number(first) = _number(overlay) then let
      val () = ui_focus_return_free(back)
    in _without(rest, overlay, first_back) end
    else let
      val @(left, found) = _without(rest, overlay, back)
    in @(LCons(first, first_back, left), found) end

fun _has {count:nat} .<count>. (overlays: !layers(count), overlay: layer): bool =
  case+ overlays of
  | LNil() => false
  | LCons(first, _, rest) => if _number(first) = _number(overlay) then true else _has(rest, overlay)

(* The focus back where it was when overlay opened, for a reader panel
   (the page, when that is gone) *)
fn _focus_back (overlay: layer, back: focus_return): void =
  if _over_reader(overlay) then ui_focus_back(back, "page") else ui_focus_return_free(back)

(* Opens overlay on top of the others (moving it there if it was open).
   A reader panel keeps the element that has the focus, to give it back *)
#pub fn layer_open (overlay: layer): void
implement layer_open (overlay) = let
  val back = (if _over_reader(overlay) then ui_focused() else NoFocusReturn()): focus_return
  val @(rest, earlier) = _without(_open_take(), overlay, NoFocusReturn())
  val () = ui_focus_return_free(earlier)
  val () = ui_show(_element_id(overlay), true)
in _open_set(LCons(overlay, back, rest)) end

(* Closes overlay; a reader panel gives the focus back *)
#pub fn layer_close (overlay: layer): void
implement layer_close (overlay) = let
  val @(rest, back) = _without(_open_take(), overlay, NoFocusReturn())
  val () = ui_show(_element_id(overlay), false)
  val () = _open_set(rest)
in _focus_back(overlay, back) end

(* Whether overlay is open *)
#pub fn layer_is_open (overlay: layer): bool
implement layer_is_open (overlay) = let
  val overlays = _open_take()
  val open = _has(overlays, overlay)
  val () = _open_put(overlays)
in open end

(* Whether a reader panel is open: the page then takes no tap, drag or
   key *)
#pub fn layer_reader_blocked (): bool
implement layer_reader_blocked () = let
  val overlays = _open_take()
  val blocked = _blocked(overlays)
  val () = _open_put(overlays)
in blocked end

fun _close_each {count:nat} .<count>. (overlays: layers(count)): void =
  case+ overlays of
  | ~LNil() => ()
  | ~LCons(first, back, rest) => let
      val () = ui_focus_return_free(back)
      val () = ui_show(_element_id(first), false)
    in _close_each(rest) end

(* Closes every overlay; true when one was open *)
#pub fn layer_close_all (): bool
implement layer_close_all () = let
  val overlays = _open_take()
  val any = (case+ overlays of LNil() => false | LCons(_, _, _) => true): bool
  val () = _close_each(overlays)
  val () = _open_set(LNil())
in any end

(* The answer to Escape: the overlay opened last is closed, and returned *)
#pub datavtype escaped = Escaped of layer | NothingOpen of ()

#pub fn layer_escape (): escaped
implement layer_escape () =
  case+ _open_take() of
  | ~LNil() => let val () = _open_put(LNil()) in NothingOpen() end
  | ~LCons(overlay, back, rest) => let
      val () = ui_show(_element_id(overlay), false)
      val () = _open_set(rest)
      val () = _focus_back(overlay, back)
    in Escaped(overlay) end

(* The page under a reader panel's scrim, seen through for a hit test
   (the place's anchor, reader.bats' _anchor_now): the scrim hidden and
   the reader no longer inert until layer_see_through_end puts them back.
   Both happen in one run of wasm, so nothing is painted or tapped in
   between *)
#pub datavtype see_through = SeenThrough of () | NothingOver of ()

#pub fn layer_see_through (): see_through
implement layer_see_through () =
  if layer_reader_blocked() then let
    val () = ui_show("panel-scrim", false)
    val () = ui_inert("reader", false)
  in SeenThrough() end
  else NothingOver()

#pub fn layer_see_through_end (seen: see_through): void
implement layer_see_through_end (seen) =
  case+ seen of
  | ~NothingOver() => ()
  | ~SeenThrough() => let
      val () = ui_inert("reader", true)
    in ui_show("panel-scrim", true) end

(* A tap on the scrim: the reader panel on top closes, as Escape closes
   it *)
#pub fn layer_scrim_tapped (): void
implement layer_scrim_tapped () = let
  val overlays = _open_take()
  val top = _top_panel(overlays)
  val () = _open_put(overlays)
in
  case+ top of
  | ~PanelOnTop(panel) => layer_close(panel)
  | ~NoPanel() => ()
end

(* The focus reached a guard, past the top reader panel's last element
   (forward) or before its first (backward): it goes round to the
   panel's first or last *)
#pub datatype wrapped = WrappedForward | WrappedBackward

#pub fn layer_focus_wrap (direction: wrapped): void
implement layer_focus_wrap (direction) = let
  val overlays = _open_take()
  val top = _top_panel(overlays)
  val () = _open_put(overlays)
in
  case+ top of
  | ~NoPanel() => ()
  | ~PanelOnTop(panel) => (case+ direction of
    | WrappedForward() => ui_focus_first_in(_element_id(panel))
    | WrappedBackward() => ui_focus_last_in(_element_id(panel)))
end

end (* #target wasm *)
