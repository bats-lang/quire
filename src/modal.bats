(* modal -- the one dialog: a title, a text and up to three buttons *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

staload "ui.sats"

(* What the open dialog asks: 0 none, 1 a duplicate import (Skip,
   Replace), 2 delete a book (Cancel, Delete), 3 factory reset (Cancel,
   Reset), 4 library menu (Export backup, Import backup, Reset), 5 a
   note (Cancel, Save) *)
val _kind = ref<int>(0)

#pub fn modal_kind (): int
implement modal_kind () = !_kind

(* Opens the dialog of kind k with its title and buttons (a button whose
   label is "-" is not shown) *)
#pub fn modal_open {nt,n1,n2,n3:pos | nt < 256; n1 < 256; n2 < 256; n3 < 256}
  (k: int, title: string nt, b1: string n1, b2: string n2, b3: string n3): void

implement modal_open (k, title, b1, b2, b3) = let
  val () = !_kind := k
  val () = ui_text("qmtt", title)
  val () = ui_text("qmb1", b1)
  val () = ui_text("qmb2", b2)
  val () = ui_text("qmb3", b3)
  val () = ui_show("qmb1", string_get_at(b1, 0) <> '-')
  val () = ui_show("qmb2", string_get_at(b2, 0) <> '-')
  val () = ui_show("qmb3", string_get_at(b3, 0) <> '-')
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

#pub fn modal_close (): void
implement modal_close () = let
  val () = !_kind := 0
in ui_show("qmod", false) end

end (* #target wasm *)
