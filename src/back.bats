(* back -- what Back goes back from: the history entry a browser's Back
   takes while there is anything to go back from (quire#333)

   One back model, Android's (its back stack: Back closes what is on
   top, a dialog, a sheet or a screen, then goes back a view, and at the
   app's root leaves it): the dialog, then the overlay opened last
   (layer.bats' stack), then the reader for the library. What Back does
   is the app's own (src/bin/quire.bats, _go_back); this module keeps
   what a browser's Back needs for it.

   A browser's Back is the session's history. Once there is anything to
   go back from (a dialog, an overlay, the reader), one entry of the
   page's own (the guard, at the page's own address, so the address
   shown never changes) is pushed above the entry the page opened at,
   so Back takes the guard (popstate) and stays on the page; the app
   then goes one step back, and the guard is pushed again if there is
   still something to go back from. A guard is never taken back by the
   app on its own (history.back() is asynchronous, and would race a
   push, a reload or a link): when what was open closed another way,
   the guard stays, and a Back that takes it with nothing to go back
   from is the platform's Back, so the app goes on back past its own
   entry (bridge's history_back) and the page is left, at once, as
   Android leaves an app at its root. The page restores its own scroll
   (history_scroll_restoration), so going back over a guard never moves
   the library. In the Android app Back is heard by bridge's
   back_button (quire.bats), and the history is not used for it. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

staload "mem.sats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.sats"

(* The view: the library, or a book in the reader *)
#pub datatype back_view = AtLibrary | InReader

(* Whether a dialog or an overlay is open *)
#pub datatype shown = Shown | NotShown

(* Whether the guard is above the page's own entry *)
datatype guard = GuardUp | GuardDown

val _view = ref<back_view>(AtLibrary())
val _overlays = ref<shown>(NotShown())
val _dialog = ref<shown>(NotShown())
val _guard = ref<guard>(GuardDown())

fn _is_shown (state: shown): bool = case+ state of Shown() => true | NotShown() => false

(* Whether Back has anything to go back from *)
fn _wanted (): bool =
  if _is_shown(!_dialog) then true
  else if _is_shown(!_overlays) then true
  else case+ !_view of InReader() => true | AtLibrary() => false

(* The guard: an entry at the page's own address (an empty URL is the
   document's own, without a fragment) *)
fn _guard_push (): void = let
  val none = $A.alloc<byte>(1)
  val @(none_frozen, none_bytes) = $A.freeze<byte>(none)
  val @(empty, rest) = $A.borrow_split<byte>(none_frozen, none_bytes, 0)
  val () = $NAV.push_state(empty, 0)
  val none_bytes = $A.borrow_join<byte>(none_frozen, empty, rest)
in release_bytes(none_frozen, none_bytes) end

(* The guard pushed when there is something to go back from and it is
   not up *)
#pub fn back_sync (): void
implement back_sync () =
  case+ !_guard of
  | GuardUp() => ()
  | GuardDown() =>
    if ~_wanted() then ()
    else let
      val () = !_guard := GuardUp()
    in _guard_push() end

#pub fn back_view_set (view: back_view): void
implement back_view_set (view) = let
  val () = !_view := view
in back_sync() end

#pub fn back_overlays_set (state: shown): void
implement back_overlays_set (state) = let
  val () = !_overlays := state
in back_sync() end

#pub fn back_dialog_set (state: shown): void
implement back_dialog_set (state) = let
  val () = !_dialog := state
in back_sync() end

(* What a popstate was: the reader's Back, which took the guard; or a
   move elsewhere in the history with no guard up (Forward, or Back over
   an entry an earlier run of the page left, or the app's own going on
   back past its entry), which changes nothing here *)
#pub datatype popped = PoppedByBack | PoppedElsewhere

#pub fn back_popped (): popped
implement back_popped () =
  case+ !_guard of
  | GuardUp() => let
      val () = !_guard := GuardDown()
    in PoppedByBack() end
  | GuardDown() => PoppedElsewhere()

(* The reader's Back took the guard with nothing to go back from: it is
   the platform's Back, and the page is left, back past its own entry *)
#pub fn back_leave (): void
implement back_leave () = $NAV.history_back()

(* As the page opens: the page restores its own scroll, so going back
   over a guard never moves what it shows *)
#pub fn back_start (): void
implement back_start () = $NAV.history_scroll_restoration($NAV.ScrollManual())

end (* #target wasm *)
