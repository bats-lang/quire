(* back -- what Back goes back from: the history entry a browser's Back
   takes while there is anything to go back from (quire#333)

   One back model, Android's (its back stack: Back closes what is on
   top, a dialog, a sheet or a screen, then goes back a view, and at the
   app's root leaves it): the dialog, then the overlay opened last
   (layer.bats' stack), then the reader for the library. What Back does
   is the app's own (src/bin/quire.bats, _go_back); this module keeps
   what a browser's Back needs for it.

   A browser's Back is the session's history. While there is anything
   to go back from (a dialog, an overlay, the reader), exactly one entry
   of the page's own (the guard, at "#r") is above the entry the page
   opened at, so Back takes the guard (popstate) and stays on the page;
   the app then goes one step back, and the guard is pushed again if
   there is still something to go back from. When the last thing closes
   another way (Done, Close, a click outside), the guard is taken back
   (bridge's history_back), so at the library, with nothing open, the
   browser's Back leaves the page at once. The pops this module causes
   are counted, so they are not taken for the reader's Back. In the
   Android app Back is heard by bridge's back_button (quire.bats), and
   the history is not used for it. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use promise as P

staload "mem.sats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

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
(* How many popstates the guard's own taking back has still to cause *)
val _own_pops = ref<int>(0)

fn _is_shown (state: shown): bool = case+ state of Shown() => true | NotShown() => false

(* Whether Back has anything to go back from *)
fn _wanted (): bool =
  if _is_shown(!_dialog) then true
  else if _is_shown(!_overlays) then true
  else case+ !_view of InReader() => true | AtLibrary() => false

(* The guard's address, "#r" *)
fn _guard_push (): void = let
  val hash = $A.alloc<byte>(2)
  val () = $A.write_byte(hash, 0, 35)
  val () = $A.write_byte(hash, 1, 114)
  val @(hash_frozen, hash_bytes) = $A.freeze<byte>(hash)
  val () = $NAV.push_state(hash_bytes, 2)
in release_bytes(hash_frozen, hash_bytes) end

(* Whether the guard's taking back is waiting for the click's handling
   to end *)
datatype taking = TakingWaits | NotTaking

val _taking = ref<taking>(NotTaking())

(* The guard taken back, if there is still nothing to go back from *)
fn _take_back (): void = let
  val () = !_taking := NotTaking()
in
  case+ !_guard of
  | GuardDown() => ()
  | GuardUp() =>
    if _wanted() then ()
    else let
      val () = !_guard := GuardDown()
      val () = !_own_pops := !_own_pops + 1
    in $NAV.history_back() end
end

(* The guard as what Back has to go back from says: pushed at once when
   there is something and it is not up; taken back when there is
   nothing and it is, once the handling under way has ended (a menu
   item closes its menu and then opens its screen: history.back() is
   asynchronous, and the screen's guard would be pushed before it) *)
#pub fn back_sync (): void
implement back_sync () =
  case+ !_guard of
  | GuardUp() =>
    if _wanted() then ()
    else (case+ !_taking of
      | TakingWaits() => ()
      | NotTaking() => let
          val () = !_taking := TakingWaits()
        in $P.finish<Int>($P.vow($TM.timer_set(0)), llam(_) => _take_back()) end)
  | GuardDown() =>
    if _wanted() then let
      val () = !_guard := GuardUp()
    in _guard_push() end
    else ()

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

(* What a popstate was: the reader's Back, which took the guard; the
   guard's own taking back; or the browser's Forward, onto the guard
   again *)
#pub datatype popped = PoppedByBack | PoppedOwn | PoppedForward

(* Whether bytes[0, n) end with the guard's "#r" *)
fn _ends_at_guard {l:agz}{size,n:nat | n <= size} (bytes: !$A.arr(byte, l, size), n: int n): bool =
  if n < 2 then false
  else byte2int0($A.get<byte>(bytes, n - 2)) = 35 && byte2int0($A.get<byte>(bytes, n - 1)) = 114

fn _at_guard (url: $R.option([k:nat] $BD.dblob(k))): bool =
  case+ url of
  | ~$R.none() => false
  | ~$R.some(blob) => let
      val n = $BD.blob_len(blob)
    in
      if n < 2 then let val () = $BD.blob_free(blob) in false end
      else if n > 4096 then let val () = $BD.blob_free(blob) in false end
      else let
        val copy = $A.alloc<byte>(n)
        val () = $BD.blob_read(blob, 0, copy, n)
        val () = $BD.blob_free(blob)
        val at = _ends_at_guard(copy, n)
        val () = $A.free<byte>(copy)
      in at end
    end

(* A popstate, at url: what it was. The guard is no longer up after
   Back or the guard's taking back, and is up again after Forward *)
#pub fn back_popped (url: $R.option([k:nat] $BD.dblob(k))): popped
implement back_popped (url) =
  if _at_guard(url) then let
    val () = !_guard := GuardUp()
  in PoppedForward() end
  else if !_own_pops > 0 then let
    val () = !_own_pops := !_own_pops - 1
  in PoppedOwn() end
  else let
    val () = !_guard := GuardDown()
  in PoppedByBack() end

(* As the page opens: an address left at the guard's (a reload while
   something was open) is put back to the page's own, so a later Back
   onto it is not taken for Forward *)
#pub fn back_start (): void
implement back_start () = let
  val page = $A.alloc<byte>(2048)
  val page_len = $NAV.get_url(page, 2048)
in
  if page_len < 2 then $A.free<byte>(page)
  else if ~_ends_at_guard(page, page_len) then $A.free<byte>(page)
  else let
    val own = page_len - 2
    val @(page_frozen, page_bytes) = $A.freeze<byte>(page)
    val @(used, rest) = $A.borrow_split<byte>(page_frozen, page_bytes, own)
    val () = $NAV.replace_state(used, own)
    val page_bytes = $A.borrow_join<byte>(page_frozen, used, rest)
  in release_bytes(page_frozen, page_bytes) end
end

end (* #target wasm *)
