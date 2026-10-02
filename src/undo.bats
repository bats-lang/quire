(* undo -- the Undo toast: what was just done, and a way back *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P

staload "ui.sats"
staload "book.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

typedef act = () -<cloref1> void

(* The offer shown: its number, what undoes it, and what makes it final
   (once the toast goes, or another offer takes its place). An action
   that can be undone is done at once and offered here; undo is run only
   from the toast's own button, whose listener this module registers
   (undo_listen), and each offer is made final exactly once *)
datatype offer =
  | Offer of (int, act, act)
  | NoOffer

val _offer = ref<offer>(NoOffer())
val _serial = ref<int>(0)

(* How long the toast stays, in milliseconds *)
#define SHOWN 8000

fn _hide (): void = ui_show("undo-toast", false)

(* The offer shown, made final *)
fn _settle (): void =
  case+ !_offer of
  | NoOffer() => ()
  | Offer(_, _, final) => let
      val () = !_offer := NoOffer()
    in final() end

(* Offers to undo what was just done, saying text: undo undoes it;
   final runs when the toast goes without being used. An earlier offer
   still shown is made final first *)
#pub fn undo_offer {text_len:pos | text_len < 256} (text: string text_len, undo: () -<cloref1> void, final: () -<cloref1> void): void

implement undo_offer (text, undo, final) = let
  val () = _settle()
  val serial = !_serial + 1
  val () = !_serial := serial
  val () = !_offer := Offer(serial, undo, final)
  val () = ui_text("undo-text", text)
  val () = ui_show("undo-toast", true)
in
  $P.finish<Int>($P.vow($TM.timer_set(SHOWN)), llam(_) =>
    case+ !_offer of
    | Offer(shown_serial, _, _) =>
      if shown_serial = serial then let
        val () = _settle()
      in _hide() end
      else ()
    | NoOffer() => ())
end

(* The offer shown, made final and taken away: for what makes an undo
   moot (emptying the Trash deletes what it would put back) *)
#pub fn undo_close (): void
implement undo_close () = let
  val () = _settle()
in _hide() end

(* The offer shown, undone *)
fn _undo (): void =
  case+ !_offer of
  | NoOffer() => ()
  | Offer(_, undo, _) => let
      val () = !_offer := NoOffer()
      val () = _hide()
    in undo() end

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
