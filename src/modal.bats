(* modal -- the one dialog: a title, a text and one or two buttons *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/decompress as DC

staload "ui.sats"
staload "book.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload "mem.sats"

(* The questions that lose nothing *)
#pub datatype question =
  | QInform                  (* a message: OK *)
  | QDuplicate               (* a book already in the library: Skip, Replace *)
  | QNote                    (* a note: Cancel, Save *)
  | QNewCollection           (* a new collection's name: Cancel, Create *)
  | QRenameCollection        (* a collection's name: Cancel, Rename *)

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
  | HEmptyTrash() => @("Empty the Trash?", "Every book in the Trash is deleted, with its reading position and annotations. This cannot be undone.", "Empty")

(* The buttons' labels and the second one's tone for question a:
   Danger(h) exactly when a is Harmful(h) *)
fn _buttons (a: ask): @(lit, lit, tone) =
  case+ a of
  | AskNothing() => @("OK", "-", Plain)
  | Harmless(QInform()) => @("OK", "-", Plain)
  | Harmless(QDuplicate()) => @("Skip", "Replace", Plain)
  | Harmless(QNote()) => @("Cancel", "Save", Plain)
  | Harmless(QNewCollection()) => @("Cancel", "Create", Plain)
  | Harmless(QRenameCollection()) => @("Cancel", "Rename", Plain)
  | Harmful(h) => let val @(_, _, verb) = _harm_words(h) in @("Cancel", verb, Danger(h)) end

fn _show {nt:pos | nt < 256} (a: ask, title: string nt, yes: act, no: act): void = let
  val () = !_pending := Pending(a, yes, no)
  val @(b1, b2, t) = _buttons(a)
  val () = ui_text("dialog-title", title)
  val () = ui_text("dialog-button1", b1)
  val () = ui_text("dialog-button2", b2)
  val () = (case+ t of
    | Danger(_) => ui_class("dialog-button2", "btn")
    | Plain() => ui_class("dialog-button2", "btn btn-p"))
  val () = ui_tone("dialog-button2", t)
  val () = ui_show("dialog-button2", string_get_at(b2, 0) <> '-')
  val () = ui_show("dialog-text", true)
  val () = ui_show("dialog-note", false)
  val () = ui_show("dialog-name-box", false)
  val () = ui_show("dialog", true)
in ui_focus("dialog-button1") end

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
in ui_text("dialog-text", text) end

(* The dialog's text: buf[0, k) *)
#pub fn modal_text {l:agz}{n:pos}{k:nat | k <= n; k < 65536} (buf: $A.arr(byte, l, n), k: int k): void
implement modal_text (buf, k) = ui_text_buf("dialog-text", buf, k)

#pub fn modal_text_lit {nt:pos | nt < 256} (t: string nt): void
implement modal_text_lit (t) = ui_text("dialog-text", t)

(* Shows the dialog's text area (for a note) instead of its text *)
#pub fn modal_textarea (): void
implement modal_textarea () = let
  val () = ui_show("dialog-text", false)
  val () = ui_show("dialog-note", true)
in ui_focus("dialog-note") end

(* Shows the dialog's name field (for a collection's name), empty,
   instead of its text. The field is made anew, so nothing typed into
   an earlier one is left in it *)
#pub fn modal_name_field (): void
implement modal_name_field () = let
  val () = ui_show("dialog-text", false)
  val () = ui_clear("dialog-name-box")
  val () = ui_field("dialog-name-box", "dialog-name", FLine, "mname", "Name")
  val () = ui_show("dialog-name-box", true)
in ui_focus("dialog-name") end

(* The name field holding b[0, k) *)
#pub fn modal_name_set {l:agz}{n:pos}{k:pos | k <= n; k < 65536} (b: $A.arr(byte, l, n), k: int k): void
implement modal_name_set (b, k) = ui_attr_buf("dialog-name", AValue, b, k)

(* What the name field holds: its bytes (at most 1024) and how many *)
#pub fn modal_name_read (): [l:agz][m:pos][k:nat | k <= m] @($A.arr(byte, l, m), int k)
implement modal_name_read () = let
  val a = $A.alloc<byte>(11)
  val () = $A.write_text(a, 0, $A.text_lit("dialog-name"), 11)
  val @(f, b) = $A.freeze<byte>(a)
  val r = $DR.read_input_value(b, 11)
  val () = release_bytes(f, b)
in
  case+ r of
  | ~$R.none() => let val a0 = $A.alloc<byte>(1) in @(a0, 0) end
  | ~$R.some(v) => let
      val n = $DC.blob_len(v)
    in
      if n <= 0 then let val () = $DC.blob_free(v) in let val a0 = $A.alloc<byte>(1) in @(a0, 0) end end
      else if n > 1024 then let val () = $DC.blob_free(v) in let val a0 = $A.alloc<byte>(1) in @(a0, 0) end end
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(v, 0, a, n)
        val () = $DC.blob_free(v)
      in @(a, n) end
    end
end

(* Closes the dialog and runs what its answer does: yes for the second
   button (second), no otherwise *)
fn _answer (second: bool): void = let
  val+ Pending(_, yes, no) = !_pending
  val () = !_pending := Pending(AskNothing(), _none, _none)
  val () = ui_show("dialog", false)
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

(* Whether a key event's bytes b[0, n) (the key's name, after its
   length) are Enter's *)
fn _enter {l:agz}{n:nat} (b: !$A.arr(byte, l, n), n: int n): bool =
  if n <> 7 then false
  else if byte2int0($A.get<byte>(b, 0)) <> 5 then false
  else if byte2int0($A.get<byte>(b, 1)) <> 69 then false
  else if byte2int0($A.get<byte>(b, 2)) <> 110 then false
  else if byte2int0($A.get<byte>(b, 3)) <> 116 then false
  else if byte2int0($A.get<byte>(b, 4)) <> 101 then false
  else byte2int0($A.get<byte>(b, 5)) = 114

(* Whether the open question asks for a name *)
fn _asks_name (): bool =
  case+ !_pending of
  | Pending(Harmless(QNewCollection()), _, _) => true
  | Pending(Harmless(QRenameCollection()), _, _) => true
  | _ => false

(* The dialog's listeners: its buttons and a click outside its box; and
   Enter in its name field, which answers as its second button does
   (only a question asking for a name has that field) *)
#pub fn modal_listen {n:nat} (r: regs(n)): regs(n + 2)
implement modal_listen (r) = let
  val r = RCons(r, OnEl("dialog-name-box"), "keydown", lam(h) =>
    case+ take_blob(h) of
    | ~NoBlobBytes() => 0
    | ~BlobBytes(b, n) => let
        val enter = _enter(b, n)
        val () = $A.free<byte>(b)
      in
        if enter && _asks_name() then let
          val () = $EV.prevent_default()
          val () = _answer(true)
        in 0 end
        else 0
      end)
in RCons(r, OnEl("dialog"), "click", lam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(b, n) => let
      val second = _target_is(b, n, "dialog-button2")
      val first = (if _target_is(b, n, "dialog-button1") then true else _target_is(b, n, "dialog")): bool
      val () = $A.free<byte>(b)
    in
      if second then let val () = _answer(true) in 0 end
      else if first then let val () = _answer(false) in 0 end
      else 0
    end) end

end (* #target wasm *)
