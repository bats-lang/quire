(* undo -- the Undo toast: what was just done, and a way back *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P

staload "ui.sats"
staload "book.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* How an offer ended: undone from the toast's button (Undone), or made
   final, once the toast went or another offer took its place (Final) *)
#pub datatype settled = Undone | Final

implement $P.dispose<settled>(_) = ()

(* The offer shown: its number, and the resolver of the promise
   undo_offer returned. An action that can be undone is done at once
   and offered here; Undone comes only from the toast's own button,
   whose listener this module registers (undo_listen), and each offer is
   settled exactly once: its resolver is linear, so it is resolved once,
   and what it leads to (a closure handed to its promise) runs once and
   is freed by the promise *)
datavtype offer =
  | Offer of (int, $P.resolver(settled))
  | NoOffer of ()

val _offer = ref<offer>(NoOffer())
val _serial = ref<int>(0)

fn _offer_swap (next: offer): offer = let
  var previous: offer = next
  val () = ref_exch_elt<offer>(_offer, previous)
in previous end

(* How long the toast stays, in milliseconds *)
#define SHOWN 8000

fn _hide (): void = ui_show("undo-toast", false)

(* An offer taken out of the cell, made final (there is none: _settle
   has emptied it, and the cell only ever holds the offer shown) *)
fn _settle_previous (previous: offer): void =
  case+ previous of
  | ~NoOffer() => ()
  | ~Offer(_, resolver) => $P.resolve<settled>(resolver, Final())

(* The offer shown, made final *)
fn _settle (): void =
  case+ _offer_swap(NoOffer()) of
  | ~NoOffer() => ()
  | ~Offer(_, resolver) => $P.resolve<settled>(resolver, Final())

(* Offers to undo what was just done, saying text. The promise resolves
   Undone when the toast's button is used, Final when the toast goes
   without being used. An earlier offer still shown is made final first *)
#pub fn undo_offer {text_len:pos | text_len < 256} (text: string text_len): $P.promise(settled, $P.Pending)

implement undo_offer (text) = let
  val () = _settle()
  val serial = !_serial + 1
  val () = !_serial := serial
  val @(settling, resolver) = $P.create<settled>()
  val () = _settle_previous(_offer_swap(Offer(serial, resolver)))
  val () = ui_text("undo-text", text)
  val () = ui_show("undo-toast", true)
  val () = $P.finish<Int>($P.vow($TM.timer_set(SHOWN)), llam(_) =>
    case+ _offer_swap(NoOffer()) of
    | ~NoOffer() => ()
    | ~Offer(shown_serial, shown_resolver) =>
      if shown_serial = serial then let
        val () = _hide()
      in $P.resolve<settled>(shown_resolver, Final()) end
      else _settle_previous(_offer_swap(Offer(shown_serial, shown_resolver))))
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
  | ~Offer(_, resolver) => let
      val () = _hide()
    in $P.resolve<settled>(resolver, Undone()) end

(* Whether event_bytes[10, n), a pointer event's target id, is id *)
fun _id_is {l:agz}{n:nat}{id_len:nat}{i:nat | i <= id_len} .<id_len - i>.
  (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len, id_len: int id_len, i: int i): bool =
  if i >= id_len then 10 + id_len = n
  else if 10 + i >= n then false
  else if byte2int0($A.get<byte>(event_bytes, 10 + i)) <> char2int0(string_get_at(id, i)) then false
  else _id_is(event_bytes, n, id, id_len, i + 1)

(* The toast's listener: its Undo button *)
#pub fn undo_listen {count:nat} (listeners: regs(count)): regs(count + 1)
implement undo_listen (listeners) = RCons(listeners, OnEl("undo-toast"), "click", llam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(event_bytes, n) => let
      val hit = _id_is(event_bytes, n, "undo-button", 11, 0)
      val () = $A.free<byte>(event_bytes)
    in if hit then let val () = _undo() in 0 end else 0 end)

end (* #target wasm *)
