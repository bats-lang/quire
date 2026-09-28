(* modal -- the one dialog: a title, a text and one or two buttons *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

staload "ui.sats"
staload "book.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"

(* What a destructive question is about: what would be lost *)
#pub datatype harm =
  | HDeleteBook of ([i:int] int i)       (* library book i *)
  | HFactoryReset                         (* every book, place and setting *)
  | HResetSettings                        (* the reading settings *)
  | HDeleteHighlight of ([i:int] int i)  (* annotation i *)
  | HDeleteBookmark of ([i:int] int i)   (* annotation i *)

(* The questions that lose nothing *)
#pub datatype question =
  | QInform                  (* a message: OK *)
  | QDuplicate               (* a book already in the library: Skip, Replace *)
  | QNote                    (* a note: Cancel, Save *)

(* What the dialog asks. A Harmful question's title, text, second
   button and its red marking all come from its harm (_harm_words,
   _buttons), so a red button is always one that would lose what the
   dialog names, and nothing else is red. *)
datatype ask =
  | AskNothing
  | Harmless of question
  | Harmful of harm

typedef act = () -<cloref1> void

(* The open question with what its second button does (yes) and what
   its first, Escape or a click outside do (no). Nothing outside this
   module can run yes: it runs only from the second button's click,
   whose listener this module registers (modal_listen), in _answer,
   which is not exported. That is how what deletes or resets stays
   behind a question: the modules that own those operations keep them
   private and hand them to modal_confirm as yes. *)
datatype pending = Pending of (ask, act, act)

val _none: act = lam () =<cloref1> ()
val _pending = ref<pending>(Pending(AskNothing(), _none, _none))

(* Whether a dialog is open *)
#pub fn modal_open_now (): bool
implement modal_open_now () =
  case+ !_pending of
  | Pending(AskNothing(), _, _) => false
  | _ => true

typedef lit = [k:pos | k < 256] string k

(* A harm's title, text and the verb of the button that does it *)
fn _harm_words (h: harm): @(lit, lit, lit) =
  case+ h of
  | HDeleteBook(_) => @("Delete book?", "The book, its reading position and its annotations are removed.", "Delete")
  | HFactoryReset() => @("Factory reset?", "Every book, position, annotation and setting is deleted.", "Reset")
  | HResetSettings() => @("Reset to defaults?", "Font, size, spacing, margins and theme go back to their defaults.", "Reset")
  | HDeleteHighlight(_) => @("Delete highlight?", "The highlight and its note are removed.", "Delete")
  | HDeleteBookmark(_) => @("Delete bookmark?", "The bookmark is removed.", "Delete")

(* The buttons' labels and the second one's tone for question a: Danger
   exactly when a is Harmful *)
fn _buttons (a: ask): @(lit, lit, tone) =
  case+ a of
  | AskNothing() => @("OK", "-", Plain)
  | Harmless(QInform()) => @("OK", "-", Plain)
  | Harmless(QDuplicate()) => @("Skip", "Replace", Plain)
  | Harmless(QNote()) => @("Cancel", "Save", Plain)
  | Harmful(h) => let val @(_, _, verb) = _harm_words(h) in @("Cancel", verb, Danger) end

fn _show {nt:pos | nt < 256} (a: ask, title: string nt, yes: act, no: act): void = let
  val () = !_pending := Pending(a, yes, no)
  val @(b1, b2, t) = _buttons(a)
  val () = ui_text("qmtt", title)
  val () = ui_text("qmb1", b1)
  val () = ui_text("qmb2", b2)
  val () = (case+ t of
    | Danger() => ui_class("qmb2", "btn danger")
    | Plain() => ui_class("qmb2", "btn btn-p"))
  val () = ui_show("qmb2", string_get_at(b2, 0) <> '-')
  val () = ui_show("qmtx", true)
  val () = ui_show("qmta", false)
  val () = ui_show("qmod", true)
in ui_focus("qmb1") end

(* Opens the dialog asking q, with its title: yes runs on its second
   button, no on its first (or Escape, or a click outside) *)
#pub fn modal_open {nt:pos | nt < 256} (q: question, title: string nt, yes: () -<cloref1> void, no: () -<cloref1> void): void
implement modal_open (q, title, yes, no) = _show(Harmless(q), title, yes, no)

(* A message with its title: OK *)
#pub fn modal_inform {nt:pos | nt < 256} (title: string nt): void
implement modal_inform (title) = _show(Harmless(QInform()), title, _none, _none)

(* Asks whether to do h, which yes does: h's title, text and red button *)
#pub fn modal_confirm (h: harm, yes: () -<cloref1> void): void
implement modal_confirm (h, yes) = let
  val @(title, text, _) = _harm_words(h)
  val () = _show(Harmful(h), title, yes, _none)
in ui_text("qmtx", text) end

(* The dialog's text: buf[0, k) *)
#pub fn modal_text {l:agz}{n:pos}{k:nat | k <= n; k < 65536} (buf: $A.arr(byte, l, n), k: int k): void
implement modal_text (buf, k) = ui_text_buf("qmtx", buf, k)

#pub fn modal_text_lit {nt:pos | nt < 256} (t: string nt): void
implement modal_text_lit (t) = ui_text("qmtx", t)

(* Shows the dialog's text area (for a note) instead of its text *)
#pub fn modal_textarea (): void
implement modal_textarea () = let
  val () = ui_show("qmtx", false)
  val () = ui_show("qmta", true)
in ui_focus("qmta") end

(* Closes the dialog and runs what its answer does: yes for the second
   button (second), no otherwise *)
fn _answer (second: bool): void = let
  val+ Pending(_, yes, no) = !_pending
  val () = !_pending := Pending(AskNothing(), _none, _none)
  val () = ui_show("qmod", false)
in if second then yes() else no() end

(* Closes the dialog as Escape does: its first answer (no), never its
   second *)
#pub fn modal_dismiss (): void
implement modal_dismiss () = if modal_open_now() then _answer(false) else ()

(* Whether b[10, n), a pointer event's target id, is id *)
fun _id_is {l:agz}{n:nat}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (b: !$A.arr(byte, l, n), n: int n, s: string sn, sl: int sn, i: int i): bool =
  if i >= sl then 10 + sl = n
  else if 10 + i >= n then false
  else if byte2int0($A.get<byte>(b, 10 + i)) <> char2int0(string_get_at(s, i)) then false
  else _id_is(b, n, s, sl, i + 1)

fn _target_is {l:agz}{n:nat}{sn:nat} (b: !$A.arr(byte, l, n), n: int n, s: string sn): bool =
  _id_is(b, n, s, g1u2i(string1_length(s)), 0)

(* The dialog's listener: its buttons and a click outside its box *)
#pub fn modal_listen {n:nat} (r: regs(n)): regs(n + 1)
implement modal_listen (r) = RCons(r, OnEl("qmod"), "click", lam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(b, n) => let
      val second = _target_is(b, n, "qmb2")
      val first = (if _target_is(b, n, "qmb1") then true else _target_is(b, n, "qmod")): bool
      val () = $A.free<byte>(b)
    in
      if second then let val () = _answer(true) in 0 end
      else if first then let val () = _answer(false) in 0 end
      else 0
    end)

end (* #target wasm *)
