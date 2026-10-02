(* platform -- what the platform offers the library: installing the app,
   and keeping its storage *)

(* Installing: Chrome and Edge offer to install the app
   (beforeinstallprompt, which bridge keeps from the page's start, the
   browser's own banner held back); the library menu's Install Quire is
   shown only while there is such an offer, and asks it on a click
   (web.dev/articles/promote-install). iOS Safari has none: the library's
   hint to add Quire to the Home Screen is shown there instead
   (library.bats, is_ios_browser).

   Storage: what the app keeps (IndexedDB) is best effort until it is
   made persistent, and under storage pressure the browser may clear it.
   It is asked for once, after the first book is imported, the moment
   the storage holds something of the reader's: Chrome grants it by the
   site's engagement without asking, Firefox asks the reader, so it is
   not asked before (web.dev/articles/persistent-storage). The library
   menu says which it is: kept, or at risk; the app's own storage
   (Capacitor) is always kept. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use promise as P

staload "ui.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload STORE = "wasm.bats-packages.dev/bridge/src/storage.sats"

(* ============================================================
   Installing
   ============================================================ *)

(* Install Quire, shown while the browser offers to install it *)
#pub fn platform_install_show (offer: $BAPP.install_offer): void

implement platform_install_show (offer) =
  case+ offer of
  | $BAPP.InstallOffered() => ui_show("menu-install", true)
  | $BAPP.InstallWithdrawn() => ui_show("menu-install", false)

(* The offer, as it is now *)
fn _install_now (): $BAPP.install_offer =
  if $BAPP.install_prompt_available() then $BAPP.InstallOffered() else $BAPP.InstallWithdrawn()

(* Install Quire clicked: the browser's offer shown. How it ends is the
   browser's to show; the offer is used up either way (bridge's listener
   withdraws it) *)
#pub fn platform_install (): void

implement platform_install () =
  $P.finish<$BAPP.install_outcome>($BAPP.install_prompt(), lam(outcome) =>
    case+ outcome of
    | $BAPP.InstallAccepted() => ()
    | $BAPP.InstallDismissed() => ()
    | $BAPP.InstallUnavailable() => platform_install_show(_install_now()))

(* ============================================================
   Keeping the storage
   ============================================================ *)

(* Whether the browser keeps what the app stores, as last found *)
datatype kept =
  | KeptUnknown     (* not asked yet, or it cannot be made persistent here *)
  | KeptPersisted   (* kept until the reader removes it *)
  | KeptAtRisk      (* the browser may clear it *)

fn _kept_show (state: kept): void =
  case+ state of
  | KeptUnknown() => let
      val () = ui_show("menu-storage-kept", false)
    in ui_show("menu-storage-at-risk", false) end
  | KeptPersisted() => let
      val () = ui_show("menu-storage-kept", true)
    in ui_show("menu-storage-at-risk", false) end
  | KeptAtRisk() => let
      val () = ui_show("menu-storage-kept", false)
    in ui_show("menu-storage-at-risk", true) end

fn _kept_of (outcome: $STORE.persist_outcome): kept =
  case+ outcome of
  | $STORE.Persisted() => KeptPersisted()
  | $STORE.NotPersisted() => KeptAtRisk()

(* Whether persistence has been asked for in this run *)
datatype asked = NotAsked | Asked

val _asked = ref<asked>(NotAsked())

(* A book was imported: the storage is asked to be kept, the first time
   in this run *)
#pub fn platform_keep_storage (): void

implement platform_keep_storage () =
  case+ !_asked of
  | Asked() => ()
  | NotAsked() =>
    if ~($STORE.storage_available()) then ()
    else let
      val () = !_asked := Asked()
    in $P.finish<$STORE.persist_outcome>($STORE.storage_persist(), lam(outcome) => _kept_show(_kept_of(outcome))) end

(* ============================================================
   Startup
   ============================================================ *)

(* What the platform offers now: Install Quire while there is an offer,
   and whether the storage is kept, without asking *)
#pub fn platform_start (): void

implement platform_start () = let
  val () = platform_install_show(_install_now())
  val () = _kept_show(KeptUnknown())
in
  if ~($STORE.storage_available()) then ()
  else $P.finish<$STORE.persist_outcome>($STORE.storage_persisted(), lam(outcome) => _kept_show(_kept_of(outcome)))
end

end (* #target wasm *)
