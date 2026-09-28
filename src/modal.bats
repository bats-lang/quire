(* modal -- the one dialog: a title, a text and one or two buttons *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

staload "ui.sats"

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
  | QNote of (int, bool)     (* annotation i's note, and whether its
                                highlight was made for it: Cancel, Save *)

(* What the dialog asks. A Harmful question's title, text, second
   button and its red marking all come from its harm (_harm_words,
   _buttons), so a red button is always one that would lose what the
   dialog names, and nothing else is red. The answer comes back with
   the question (modal_answer), so what is lost is what was asked
   about. *)
#pub datatype ask =
  | AskNothing               (* no dialog is open *)
  | Harmless of question
  | Harmful of harm

(* The answer: the second button (Confirmed), or the first, Escape or
   a click outside (Dismissed) *)
#pub datatype answer =
  | Confirmed of ask
  | Dismissed of ask

val _asked = ref<ask>(AskNothing())

(* Whether a dialog is open *)
#pub fn modal_open_now (): bool
implement modal_open_now () =
  case+ !_asked of
  | AskNothing() => false
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
  | Harmless(QNote(_, _)) => @("Cancel", "Save", Plain)
  | Harmful(h) => let val @(_, _, verb) = _harm_words(h) in @("Cancel", verb, Danger) end

fn _show {nt:pos | nt < 256} (a: ask, title: string nt): void = let
  val () = !_asked := a
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

(* Opens the dialog asking q, with its title *)
#pub fn modal_open {nt:pos | nt < 256} (q: question, title: string nt): void
implement modal_open (q, title) = _show(Harmless(q), title)

(* Asks whether to do h: its title, text and red button are h's *)
#pub fn modal_confirm (h: harm): void
implement modal_confirm (h) = let
  val @(title, text, _) = _harm_words(h)
  val () = _show(Harmful(h), title)
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

(* Closes the dialog; the answer, second is whether its second button
   was chosen, with the question it answers *)
#pub fn modal_answer (second: bool): answer
implement modal_answer (second) = let
  val a = !_asked
  val () = !_asked := AskNothing()
  val () = ui_show("qmod", false)
in if second then Confirmed(a) else Dismissed(a) end

end (* #target wasm *)
