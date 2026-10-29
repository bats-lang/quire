(* undo -- the Undo toast: what was just done, and a way back *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P

staload "ui.sats"
staload "book.sats"
staload "titles.sats"

(* How an offer ended: undone from the toast's button (Undone), or made
   final, once the toast went or another offer took its place (Final) *)
#pub datatype settled = Undone | Final

implement $P.dispose<settled>(_) = ()

(* How long an offer lasts. An offer with an action stays until it is
   used, dismissed, or another offer takes its place (Material 3's
   snackbar with an action; WCAG 2.2.1: a reader who needs more time has
   it), so `UntilDismissed` is the only life undo_offer takes. `Brief`
   is for a message with no action, which goes by itself (quire#364) *)
#pub datasort offer_life = Brief | UntilDismissed

(* Where the sync file is, which Turn off leaves there: the toast says it
   stays (#389; Android's "Remove account" says what happens to the
   account's data) *)
#pub datatype sync_file_place =
  | FileInGoogleDrive | FileInDropbox | FileInFastmail | FileOnServer

(* What is offered back, each by its own words: the toast says what an
   Undo would undo. Its life is in its type *)
#pub datavtype offered(offer_life) =
  (* the book's title (an empty one is said as "Book"): the toast names
     what was moved (quire#385: Material 3's snackbar says what
     happened; Gmail's says which conversation) *)
  | {title_loc:agz}{title_len:nat | title_len < 256}
    MovedToTrash(UntilDismissed) of ($A.arr(byte, title_loc, title_len + 1), int title_len)
  | HighlightDeleted(UntilDismissed) of ()
  | HighlightRangeChanged(UntilDismissed) of ()
  | BookmarkDeleted(UntilDismissed) of ()
  | LibraryTrashed(UntilDismissed) of ()
  | BooksRestored(UntilDismissed) of ()
  | SettingsReset(UntilDismissed) of ()
  | SyncTurnedOff(UntilDismissed) of (sync_file_place)
  | CatalogueRemoved(UntilDismissed) of ()
  | DictionaryRemoved(UntilDismissed) of ()
  | CollectionDeleted(UntilDismissed) of ()
  | BookArchived(UntilDismissed) of ()
  | BookHidden(UntilDismissed) of ()
  | BookUnhidden(UntilDismissed) of ()
  | BackupRestored(UntilDismissed) of ()
  | WordDeleted(UntilDismissed) of ()
  | PlainMessage(Brief) of ()

(* "'" title "' moved to Trash", the title cut when it is long *)
fn _moved_text {title_loc:agz}{title_len:nat | title_len < 256}
  (title: !$A.arr(byte, title_loc, title_len + 1), title_len: int title_len): void = let
  val buf = $A.alloc<byte>(81)
  val ended = title_put(title, title_len, buf, 0)
  val () = $A.write_text(buf, ended, $A.text_lit(" moved to Trash"), 15)
in ui_text_buf("undo-text", buf, ended + 15) end

(* What the toast says of an offer, and the offer consumed *)
fn _offered_show {life:offer_life} (what: offered(life)): void =
  case+ what of
  | ~MovedToTrash(title, title_len) => let
      val () = _moved_text(title, title_len)
    in $A.free<byte>(title) end
  | ~HighlightDeleted() => ui_text("undo-text", "Highlight deleted")
  | ~HighlightRangeChanged() => ui_text("undo-text", "Highlight changed")
  | ~BookmarkDeleted() => ui_text("undo-text", "Bookmark deleted")
  | ~LibraryTrashed() => ui_text("undo-text", "Library moved to the Trash, settings reset")
  | ~BooksRestored() => ui_text("undo-text", "Books restored from the Trash")
  | ~SettingsReset() => ui_text("undo-text", "Settings reset")
  | ~SyncTurnedOff(place) =>
    (case+ place of
    | FileInGoogleDrive() => ui_text("undo-text", "Sync turned off. The file stays in your Google Drive.")
    | FileInDropbox() => ui_text("undo-text", "Sync turned off. The file stays in your Dropbox.")
    | FileInFastmail() => ui_text("undo-text", "Sync turned off. The file stays in your Fastmail Files.")
    | FileOnServer() => ui_text("undo-text", "Sync turned off. The file stays in your folder on the server."))
  | ~CatalogueRemoved() => ui_text("undo-text", "Catalogue removed")
  | ~DictionaryRemoved() => ui_text("undo-text", "Dictionary removed")
  | ~CollectionDeleted() => ui_text("undo-text", "Collection deleted")
  | ~BookArchived() => ui_text("undo-text", "Book archived")
  | ~BookHidden() => ui_text("undo-text", "Book hidden")
  | ~BookUnhidden() => ui_text("undo-text", "Book unhidden")
  | ~BackupRestored() => ui_text("undo-text", "Backup restored")
  | ~WordDeleted() => ui_text("undo-text", "Word deleted")
  | ~PlainMessage() => ui_text("undo-text", "Done")

(* The offer shown: the resolver of the promise undo_offer returned. An action that can be undone is done at once
   and offered here; Undone comes only from the toast's own button,
   whose listener this module registers (undo_listen), and each offer is
   settled exactly once: its resolver is linear, so it is resolved once,
   and what it leads to (a closure handed to its promise) runs once and
   is freed by the promise *)
datavtype offer =
  | Offer of ($P.resolver(settled))
  | NoOffer of ()

val _offer = ref<offer>(NoOffer())

fn _offer_swap (next: offer): offer = let
  var previous: offer = next
  val () = ref_exch_elt<offer>(_offer, previous)
in previous end

fn _hide (): void = ui_show("undo-toast", false)

(* An offer taken out of the cell, made final (there is none: _settle
   has emptied it, and the cell only ever holds the offer shown) *)
fn _settle_previous (previous: offer): void =
  case+ previous of
  | ~NoOffer() => ()
  | ~Offer(resolver) => $P.resolve<settled>(resolver, Final())

(* The offer shown, made final *)
fn _settle (): void =
  case+ _offer_swap(NoOffer()) of
  | ~NoOffer() => ()
  | ~Offer(resolver) => $P.resolve<settled>(resolver, Final())

(* Offers to undo what was just done, saying what it was. The promise
   resolves Undone when the toast's button is used, Final when the offer
   is dismissed, or another offer takes its place (the earlier one is
   made final at once). The toast stays until then; only an offer that
   lasts until it is dismissed type-checks here *)
#pub fn undo_offer (what: offered(UntilDismissed)): $P.promise(settled, $P.Pending)

implement undo_offer (what) = let
  val () = _settle()
  val @(settling, resolver) = $P.create<settled>()
  val () = _settle_previous(_offer_swap(Offer(resolver)))
  val () = _offered_show(what)
  val () = ui_show("undo-toast", true)
in settling end

(* The offer shown, made final and taken away: for what makes an undo
   moot (emptying the Trash deletes what it would put back) *)
#pub fn undo_close (): void
implement undo_close () = let
  val () = _settle()
in _hide() end

(* The offer shown, undone *)
fn _undo (): void =
  case+ _offer_swap(NoOffer()) of
  | ~NoOffer() => ()
  | ~Offer(resolver) => let
      val () = _hide()
    in $P.resolve<settled>(resolver, Undone()) end

(* Whether event_bytes[10, n), a pointer event's target id, is id *)
fun _id_is {l:agz}{n:nat}{id_len:nat}{i:nat | i <= id_len} .<id_len - i>.
  (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len, id_len: int id_len, i: int i): bool =
  if i >= id_len then 10 + id_len = n
  else if 10 + i >= n then false
  else if byte2int0($A.get<byte>(event_bytes, 10 + i)) <> char2int0(string_get_at(id, i)) then false
  else _id_is(event_bytes, n, id, id_len, i + 1)

(* fixture: the-toast-s-listener-its-undo *)
(* The toast's listener: its Undo button, and Dismiss *)
#pub fn undo_listen {count:nat} (listeners: regs(count)): regs(count + 1)
implement undo_listen (listeners) = RCons(listeners, OnEl("undo-toast"), "click", llam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(event_bytes, n) => let
      val undo_hit = _id_is(event_bytes, n, "undo-button", 11, 0)
      val dismiss_hit = _id_is(event_bytes, n, "undo-dismiss", 12, 0)
      val () = $A.free<byte>(event_bytes)
    in
      if undo_hit then let val () = _undo() in 0 end
      else if dismiss_hit then let val () = undo_close() in 0 end
      else 0
    end)

end (* #target wasm *)
