(* modal -- the one dialog: a title, a text and one or two buttons *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

staload "ui.sats"

(* What the dialog asks. Its buttons, their labels and whether the
   second one is marked as destructive follow from this alone, and the
   answer comes back with it (modal_answer), so an answer is always
   handled as an answer to the question that was asked, with what it
   was asked about (a book, an annotation): nothing is looked up in a
   variable that may have changed since. *)
#pub datatype ask =
  | AskNothing                  (* no dialog is open *)
  | AskInform                   (* a message: OK *)
  | AskDuplicate                (* a book already in the library: Skip, Replace *)
  | AskDeleteBook of ([i:int] int i)  (* library book i: Cancel, Delete *)
  | AskFactoryReset             (* everything: Cancel, Reset *)
  | AskResetSettings            (* the reading settings: Cancel, Reset *)
  | AskDeleteHighlight of ([i:int] int i)  (* annotation i: Cancel, Delete *)
  | AskDeleteBookmark of ([i:int] int i)   (* annotation i: Cancel, Delete *)
  | AskNote of (int, bool)      (* annotation i's note, and whether the
                                   highlight was made for it: Cancel, Save *)

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

(* The buttons' labels and the second one's tone for question a *)
fn _buttons (a: ask): @([k:pos | k < 256] string k, [k:pos | k < 256] string k, tone) =
  case+ a of
  | AskNothing() => @("OK", "-", Plain)
  | AskInform() => @("OK", "-", Plain)
  | AskDuplicate() => @("Skip", "Replace", Plain)
  | AskDeleteBook(_) => @("Cancel", "Delete", Danger)
  | AskFactoryReset() => @("Cancel", "Reset", Danger)
  | AskResetSettings() => @("Cancel", "Reset", Danger)
  | AskDeleteHighlight(_) => @("Cancel", "Delete", Danger)
  | AskDeleteBookmark(_) => @("Cancel", "Delete", Danger)
  | AskNote(_, _) => @("Cancel", "Save", Plain)

(* Opens the dialog asking a, with its title *)
#pub fn modal_open {nt:pos | nt < 256} (a: ask, title: string nt): void

implement modal_open (a, title) = let
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
