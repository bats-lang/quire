(* modal -- the one dialog: a title, a text and one or two buttons *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use result as R

staload "ui.sats"
staload "book.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload "mem.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

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

typedef lit = [length:pos | length < 256] string length

(* A harm's title, text and the verb of the button that does it *)
fn _harm_words (the_harm: harm): @(lit, lit, lit) =
  case+ the_harm of
  | HEmptyTrash() => @("Empty the Trash?", "Every book in the Trash is deleted, with its reading position and annotations. This cannot be undone.", "Empty")

(* The buttons' labels and the second one's tone for question asked:
   Danger(the_harm) exactly when asked is Harmful(the_harm) *)
fn _buttons (asked: ask): @(lit, lit, tone) =
  case+ asked of
  | AskNothing() => @("OK", "-", Plain)
  | Harmless(QInform()) => @("OK", "-", Plain)
  | Harmless(QDuplicate()) => @("Skip", "Replace", Plain)
  | Harmless(QNote()) => @("Cancel", "Save", Plain)
  | Harmless(QNewCollection()) => @("Cancel", "Create", Plain)
  | Harmless(QRenameCollection()) => @("Cancel", "Rename", Plain)
  | Harmful(the_harm) => let val @(_, _, verb) = _harm_words(the_harm) in @("Cancel", verb, Danger(the_harm)) end

fn _show {title_len:pos | title_len < 256} (asked: ask, title: string title_len, yes: act, no: act): void = let
  val () = !_pending := Pending(asked, yes, no)
  val @(first_label, second_label, second_tone) = _buttons(asked)
  val () = ui_text("dialog-title", title)
  val () = ui_text("dialog-button1", first_label)
  val () = ui_text("dialog-button2", second_label)
  val () = (case+ second_tone of
    | Danger(_) => ui_class("dialog-button2", "btn")
    | Plain() => ui_class("dialog-button2", "btn btn-p"))
  val () = ui_tone("dialog-button2", second_tone)
  val () = ui_show("dialog-button2", string_get_at(second_label, 0) <> '-')
  val () = ui_show("dialog-text", true)
  val () = ui_show("dialog-note", false)
  val () = ui_show("dialog-name-box", false)
  val () = ui_show("dialog", true)
in ui_focus("dialog-button1") end

(* Opens the dialog asking the question asked, with its title: yes runs on its second
   button, no on its first (or Escape, or a click outside) *)
#pub fn modal_open {title_len:pos | title_len < 256} (asked: question, title: string title_len, yes: () -<cloref1> void, no: () -<cloref1> void): void
implement modal_open (asked, title, yes, no) = _show(Harmless(asked), title, yes, no)

(* A message with its title: OK *)
#pub fn modal_inform {title_len:pos | title_len < 256} (title: string title_len): void
implement modal_inform (title) = _show(Harmless(QInform()), title, _none, _none)

(* Asks whether to do the_harm, which yes does: the_harm's title, text and red button *)
#pub fn modal_confirm (the_harm: harm, yes: () -<cloref1> void): void
implement modal_confirm (the_harm, yes) = let
  val @(title, text, _) = _harm_words(the_harm)
  val () = _show(Harmful(the_harm), title, yes, _none)
in ui_text("dialog-text", text) end

(* The dialog's text: buf[0, text_len) *)
#pub fn modal_text {l:agz}{n:pos}{text_len:nat | text_len <= n; text_len < 65536} (buf: $A.arr(byte, l, n), text_len: int text_len): void
implement modal_text (buf, text_len) = ui_text_buf("dialog-text", buf, text_len)

#pub fn modal_text_lit {text_len:pos | text_len < 256} (text: string text_len): void
implement modal_text_lit (text) = ui_text("dialog-text", text)

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

(* The name field holding name[0, name_len) *)
#pub fn modal_name_set {l:agz}{n:pos}{name_len:pos | name_len <= n; name_len < 65536} (name: $A.arr(byte, l, n), name_len: int name_len): void
implement modal_name_set (name, name_len) = ui_attr_buf("dialog-name", AValue, name, name_len)

(* What the name field holds: its bytes (at most 1024) and how many *)
#pub fn modal_name_read (): [l:agz][n:pos][name_len:nat | name_len <= n] @($A.arr(byte, l, n), int name_len)
implement modal_name_read () = let
  val field_id = $A.alloc<byte>(11)
  val () = $A.write_text(field_id, 0, $A.text_lit("dialog-name"), 11)
  val @(field_id_frozen, field_id_bytes) = $A.freeze<byte>(field_id)
  val value_read = $DR.read_input_value(field_id_bytes, 11)
  val () = release_bytes(field_id_frozen, field_id_bytes)
in
  case+ value_read of
  | ~$R.none() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  | ~$R.some(value) => let
      val value_len = $BD.blob_len(value)
    in
      if value_len <= 0 then let val () = $BD.blob_free(value) in let val empty = $A.alloc<byte>(1) in @(empty, 0) end end
      else if value_len > 1024 then let val () = $BD.blob_free(value) in let val empty = $A.alloc<byte>(1) in @(empty, 0) end end
      else let
        val name = $A.alloc<byte>(value_len)
        val () = $BD.blob_read(value, 0, name, value_len)
        val () = $BD.blob_free(value)
      in @(name, value_len) end
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

(* Whether event_bytes[10, n), a pointer event's target id, is id *)
fun _id_is {l:agz}{n:nat}{id_len:nat}{i:nat | i <= id_len} .<id_len - i>.
  (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len, id_len: int id_len, i: int i): bool =
  if i >= id_len then 10 + id_len = n
  else if 10 + i >= n then false
  else if byte2int0($A.get<byte>(event_bytes, 10 + i)) <> char2int0(string_get_at(id, i)) then false
  else _id_is(event_bytes, n, id, id_len, i + 1)

fn _target_is {l:agz}{n:nat}{id_len:nat} (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len): bool =
  _id_is(event_bytes, n, id, g1u2i(string1_length(id)), 0)

(* Whether a key event's bytes key_bytes[0, n) (the key's name, after its
   length) are Enter's *)
fn _enter {l:agz}{n:nat} (key_bytes: !$A.arr(byte, l, n), n: int n): bool =
  if n <> 7 then false
  else if byte2int0($A.get<byte>(key_bytes, 0)) <> 5 then false
  else if byte2int0($A.get<byte>(key_bytes, 1)) <> 69 then false
  else if byte2int0($A.get<byte>(key_bytes, 2)) <> 110 then false
  else if byte2int0($A.get<byte>(key_bytes, 3)) <> 116 then false
  else if byte2int0($A.get<byte>(key_bytes, 4)) <> 101 then false
  else byte2int0($A.get<byte>(key_bytes, 5)) = 114

(* Whether the open question asks for a name *)
fn _asks_name (): bool =
  case+ !_pending of
  | Pending(Harmless(QNewCollection()), _, _) => true
  | Pending(Harmless(QRenameCollection()), _, _) => true
  | _ => false

(* The dialog's listeners: its buttons and a click outside its box; and
   Enter in its name field, which answers as its second button does
   (only a question asking for a name has that field) *)
#pub fn modal_listen {count:nat} (listeners: regs(count)): regs(count + 2)
implement modal_listen (listeners) = let
  val listeners = RCons(listeners, OnEl("dialog-name-box"), "keydown", lam(h) =>
    case+ take_blob(h) of
    | ~NoBlobBytes() => 0
    | ~BlobBytes(event_bytes, n) => let
        val enter = _enter(event_bytes, n)
        val () = $A.free<byte>(event_bytes)
      in
        if enter && _asks_name() then let
          val () = $EV.prevent_default()
          val () = _answer(true)
        in 0 end
        else 0
      end)
in RCons(listeners, OnEl("dialog"), "click", lam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(event_bytes, n) => let
      val second = _target_is(event_bytes, n, "dialog-button2")
      val first = (if _target_is(event_bytes, n, "dialog-button1") then true else _target_is(event_bytes, n, "dialog")): bool
      val () = $A.free<byte>(event_bytes)
    in
      if second then let val () = _answer(true) in 0 end
      else if first then let val () = _answer(false) in 0 end
      else 0
    end) end

end (* #target wasm *)
