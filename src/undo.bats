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

fn _hide (): void = ui_show("qund", false)

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
#pub fn undo_offer {nt:pos | nt < 256} (text: string nt, undo: () -<cloref1> void, final: () -<cloref1> void): void

implement undo_offer (text, undo, final) = let
  val () = _settle()
  val s = !_serial + 1
  val () = !_serial := s
  val () = !_offer := Offer(s, undo, final)
  val () = ui_text("qunt", text)
  val () = ui_show("qund", true)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(SHOWN)), lam(_) =>
    case+ !_offer of
    | Offer(s2, _, _) =>
      if s2 = s then let
        val () = _settle()
        val () = _hide()
      in $P.ret<int>(0) end
      else $P.ret<int>(0)
    | NoOffer() => $P.ret<int>(0)))
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

(* Whether b[10, n), a pointer event's target id, is id *)
fun _id_is {l:agz}{n:nat}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (b: !$A.arr(byte, l, n), n: int n, s: string sn, sl: int sn, i: int i): bool =
  if i >= sl then 10 + sl = n
  else if 10 + i >= n then false
  else if byte2int0($A.get<byte>(b, 10 + i)) <> char2int0(string_get_at(s, i)) then false
  else _id_is(b, n, s, sl, i + 1)

(* The toast's listener: its Undo button *)
#pub fn undo_listen {n:nat} (r: regs(n)): regs(n + 1)
implement undo_listen (r) = RCons(r, OnEl("qund"), "click", lam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(b, n) => let
      val hit = _id_is(b, n, "qunb", 4, 0)
      val () = $A.free<byte>(b)
    in if hit then let val () = _undo() in 0 end else 0 end)

end (* #target wasm *)
