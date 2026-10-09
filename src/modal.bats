(* modal -- the one dialog: a title, a text and one or two buttons *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use promise as P

staload "ui.sats"
staload "book.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload "mem.sats"
staload "back.sats"
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
datavtype ask =
  | Harmless of question
  | Harmful of harm

fn _ask_free (asked: ask): void =
  case+ asked of
  | ~Harmless(_) => ()
  | ~Harmful(_) => ()

(* The answer a dialog was given: its second button (Accepted), or its
   first, Escape or a click outside (Declined) *)
#pub datatype reply = Accepted | Declined

implement $P.dispose<reply>(_) = ()

(* The open question, with the resolver its answer resolves. Nothing
   outside this module can answer Accepted: only the second button's
   click does, whose listener this module registers (modal_listen), in
   _answer, which is not exported. That is how what deletes or resets
   stays behind a question: the modules that own those operations keep
   them private, and do them only when the promise modal_confirm returns
   resolves with Accepted. What a dialog leads to is a closure handed to
   that promise, which runs it once and frees it. *)
datavtype pending =
  | NoPending of ()
  | Pending of (ask, $P.resolver(reply))

val _pending = ref<pending>(NoPending())

fn _pending_swap (next: pending): pending = let
  var previous: pending = next
  val () = ref_exch_elt<pending>(_pending, previous)
in previous end

(* The question pending, answered Declined: one a new question takes
   the place of is closed as Escape closes it *)
fn _pending_decline (previous: pending): void =
  case+ previous of
  | ~NoPending() => ()
  | ~Pending(asked, resolver) => let
      val () = _ask_free(asked)
    in $P.resolve<reply>(resolver, Declined()) end

fn _pending_put (next: pending): void = _pending_decline(_pending_swap(next))

fn _is_open (current: !pending): bool =
  case+ current of
  | NoPending() => false
  | Pending(_, _) => true

(* Whether a dialog is open *)
#pub fn modal_open_now (): bool
implement modal_open_now () = let
  val current = _pending_swap(NoPending())
  val open = _is_open(current)
  val () = _pending_put(current)
in open end

typedef lit = [length:pos | length < 256] string length

(* A harm's title, text and the verb of the button that does it *)
fn _harm_words (the_harm: harm): @(lit, lit, lit) =
  case+ the_harm of
  | HEmptyTrash() => @("Empty the Trash?", "Every book in the Trash is deleted, with its reading position and annotations. This cannot be undone.", "Empty")

(* The buttons' labels and the second one's tone for question asked:
   Danger(the_harm) exactly when asked is Harmful(the_harm) *)
fn _buttons (asked: !ask): @(lit, lit, tone) =
  case+ asked of
  | Harmless(QInform()) => @("OK", "-", Plain)
  | Harmless(QDuplicate()) => @("Skip", "Replace", Plain)
  | Harmless(QNote()) => @("Cancel", "Save", Plain)
  | Harmless(QNewCollection()) => @("Cancel", "Create", Plain)
  | Harmless(QRenameCollection()) => @("Cancel", "Rename", Plain)
  | Harmful(the_harm) => let val @(_, _, verb) = _harm_words(the_harm) in @("Cancel", verb, Danger(the_harm)) end

fn _show {title_len:pos | title_len < 256} (asked: ask, title: string title_len): $P.promise(reply, $P.Pending) = let
  val @(first_label, second_label, second_tone) = _buttons(asked)
  val @(answered, resolver) = $P.create<reply>()
  val () = _pending_put(Pending(asked, resolver))
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
  val () = ui_focus("dialog-button1")
  val () = back_dialog_set(Shown())
in answered end

(* Opens the dialog asking the question asked, with its title: the
   promise resolves with its answer, Accepted for its second button,
   Declined for its first (or Escape, or a click outside) *)
#pub fn modal_open {title_len:pos | title_len < 256} (asked: question, title: string title_len): $P.promise(reply, $P.Pending)
implement modal_open (asked, title) = _show(Harmless(asked), title)

(* A message with its title: OK *)
#pub fn modal_inform {title_len:pos | title_len < 256} (title: string title_len): void
(* its one button, OK, answers nothing: the answer is let go *)
implement modal_inform (title) = $P.finish<reply>(_show(Harmless(QInform()), title), llam(_) => ())

(* Asks whether to do the_harm (dictionaries: how many the Trash holds, for the words that name them): the_harm's title, text and red button.
   The promise resolves Accepted only from that button *)
#pub fn modal_confirm (the_harm: harm, dictionaries: int): $P.promise(reply, $P.Pending)
implement modal_confirm (the_harm, dictionaries) = let
  val @(title, text, _) = _harm_words(the_harm)
  val answered = _show(Harmful(the_harm), title)
  val () = (if dictionaries > 0 then
    (case+ the_harm of
     | HEmptyTrash() => ui_text("dialog-text", "Every book in the Trash is deleted, with its reading position and annotations, and so is every dictionary in it, with its files. This cannot be undone."))
    else ui_text("dialog-text", text))
in answered end

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
  val () = ui_form_field("dialog-name-box", "dialog-name-label", "dialog-name", FormName, "mname", "Name", "A name for it")
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

(* Closes the dialog and resolves its promise with its answer: Accepted
   for the second button (second), Declined otherwise *)
fn _answer (second: bool): void =
  case+ _pending_swap(NoPending()) of
  | ~NoPending() => ()
  | ~Pending(asked, resolver) => let
      val () = _ask_free(asked)
      val () = ui_show("dialog", false)
      val () = back_dialog_set(NotShown())
    in $P.resolve<reply>(resolver, (if second then Accepted() else Declined()): reply) end

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
fn _names (current: !pending): bool =
  case+ current of
  | Pending(Harmless(QNewCollection()), _) => true
  | Pending(Harmless(QRenameCollection()), _) => true
  | _ => false

fn _asks_name (): bool = let
  val current = _pending_swap(NoPending())
  val names = _names(current)
  val () = _pending_put(current)
in names end

(* The dialog's listeners: its buttons and a click outside its box; and
   Enter in its name field, which answers as its second button does
   (only a question asking for a name has that field) *)
#pub fn modal_listen {count:nat} (listeners: regs(count)): regs(count + 2)
implement modal_listen (listeners) = let
  val listeners = RCons(listeners, OnEl("dialog-name-box"), "keydown", llam(h) =>
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
in RCons(listeners, OnEl("dialog"), "click", llam(h) =>
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
