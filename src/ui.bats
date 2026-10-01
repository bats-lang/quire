(* ui -- the app's elements, made and changed by id *)

(* Every element quire makes has an id; ids are literals (the app's
   fixed elements) or made from a prefix and a number (cards, list rows,
   content nodes). Each operation here copies its ids and texts into the
   dom package's buffer (nothing is allocated for them) and flushes it. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use str as S
#use wasm.bats-packages.dev/dom as D
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
#use result as R
staload "mem.sats"

(* ============================================================
   Ids
   ============================================================ *)

(* A string literal's bytes in a fresh array *)
fn _literal_bytes {n:pos | n < 256} (text: string n, n: int n): [l:agz] $A.arr(byte, l, n) = let
  val bytes = $A.alloc<byte>(n)
  val () = $A.write_text(bytes, 0, $A.text_lit(text), n)
in bytes end

fn _length {n:pos | n < 256} (text: string n): int n = g1u2i(string1_length(text))

(* text's bytes at buffer[at, at + text_len) *)
fun _put_text {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (buffer: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.set<byte>(buffer, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_text(buffer, at, text, text_len, i + 1) end

(* A numbered id: id_prefix (a word, up to 16 bytes, so an id says what it
   is) and number's decimal digits *)
#pub fn nid_make {prefix_len:pos | prefix_len <= 16}{number:nat} (id_prefix: string prefix_len, number: int number)
  : [id_loc:agz][id_len:pos | id_len <= 32] @($A.arr(byte, id_loc, id_len), int id_len)

implement nid_make(id_prefix, number) = let
  val buffer = $A.alloc<byte>(32)
  val id_len = _put_text(buffer, 0, id_prefix, g1u2i(string1_length(id_prefix)), 0)
  val id_len = $S.int_to_str(buffer, id_len, 32, number)
  val id = $A.alloc<byte>(id_len)
  val buffer = $S.copy_arr_region(buffer, 0, 32, id, id_len, id_len)
  val () = $A.free<byte>(buffer)
in @(id, id_len) end

(* The zeros before number's digits at buffer[at], to make them three *)
fn _pad_to_three {l:agz}{at:nat | at <= 3}{number:nat} (buffer: !$A.arr(byte, l, 16), at: int at, number: int number): [padded:nat | padded <= at + 2] int padded =
  if number < 10 then let
    val () = $A.set<byte>(buffer, at, $A.int2byte(48))
    val () = $A.set<byte>(buffer, at + 1, $A.int2byte(48))
  in at + 2 end
  else if number < 100 then let
    val () = $A.set<byte>(buffer, at, $A.int2byte(48))
  in at + 1 end
  else at

(* A content node's id: id_prefix and number's digits, zero-padded to three (as
   the reader numbers its content nodes) *)
#pub fn nid_pad3 {prefix_len:pos | prefix_len <= 3}{number:nat} (id_prefix: string prefix_len, number: int number)
  : [id_loc:agz][id_len:pos | id_len <= 16] @($A.arr(byte, id_loc, id_len), int id_len)

implement nid_pad3(id_prefix, number) = let
  val buffer = $A.alloc<byte>(16)
  val id_len = _put_text(buffer, 0, id_prefix, g1u2i(string1_length(id_prefix)), 0)
  val id_len = _pad_to_three(buffer, id_len, number)
  val id_len = $S.int_to_str(buffer, id_len, 16, number)
  val id = $A.alloc<byte>(id_len)
  val buffer = $S.copy_arr_region(buffer, 0, 16, id, id_len, id_len)
  val () = $A.free<byte>(buffer)
in @(id, id_len) end

(* A numbered id with a suffix: id_prefix, number's digits, then suffix *)
#pub fn nid_make2 {prefix_len:pos | prefix_len <= 16}{number:nat}{suffix_len:pos | suffix_len <= 12}
  (id_prefix: string prefix_len, number: int number, suffix: string suffix_len)
  : [id_loc:agz][id_len:pos | id_len <= 40] @($A.arr(byte, id_loc, id_len), int id_len)

implement nid_make2(id_prefix, number, suffix) = let
  val buffer = $A.alloc<byte>(40)
  val id_len = _put_text(buffer, 0, id_prefix, g1u2i(string1_length(id_prefix)), 0)
  val id_len = $S.int_to_str(buffer, id_len, 40, number)
  val id_len = _put_text(buffer, id_len, suffix, g1u2i(string1_length(suffix)), 0)
  val id = $A.alloc<byte>(id_len)
  val buffer = $S.copy_arr_region(buffer, 0, 40, id, id_len, id_len)
  val () = $A.free<byte>(buffer)
in @(id, id_len) end

(* The number an id prefix<digits> names, from bytes the host passed (an
   event's target): checked here, once; -1 when it is not such an id *)
fun _digits {l:agz}{n:nat}{i:nat | i <= n} .<n - i>.
  (bytes: !$A.borrow(byte, l, n), n: int n, i: int i, number: [so_far:nat | so_far <= 99999999] int so_far): [parsed:int | parsed >= ~1] int parsed =
  if i >= n then number
  else let
    val code = $AR.low_byte(byte2int0($A.read<byte>(bytes, i)))
  in
    if code < 48 then ~1
    else if code > 57 then ~1
    else if number > 9999999 then ~1
    else _digits(bytes, n, i + 1, number * 10 + (code - 48))
  end

fun _prefix_at {l:agz}{n:nat}{prefix_len:nat}{at:nat}{i:nat | i <= prefix_len} .<prefix_len - i>.
  (bytes: !$A.borrow(byte, l, n), n: int n, at: int at, id_prefix: string prefix_len, prefix_len: int prefix_len, i: int i): bool =
  if i >= prefix_len then true
  else if at + i >= n then false
  else if byte2int0($A.read<byte>(bytes, at + i)) <> char2int0(string_get_at(id_prefix, i)) then false
  else _prefix_at(bytes, n, at, id_prefix, prefix_len, i + 1)

#pub fn nid_parse {l:agz}{n:nat}{at:nat}{prefix_len:pos | prefix_len <= 16}
  (bytes: !$A.borrow(byte, l, n), n: int n, at: int at, id_prefix: string prefix_len): [parsed:int | parsed >= ~1] int parsed

implement nid_parse{l}{n}{at}{prefix_len}(bytes, n, at, id_prefix) = let
  val prefix_len = g1u2i(string1_length(id_prefix))
in
  if ~_prefix_at(bytes, n, at, id_prefix, prefix_len, 0) then ~1
  else if at + prefix_len >= n then ~1
  else _digits(bytes, n, at + prefix_len, 0)
end

(* ============================================================
   Elements
   ============================================================ *)

fn _add_in_document {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{tag_len:pos | tag_len < 256}
  (parent_bytes: !$A.borrow(byte, parent_loc, parent_len), parent_len: int parent_len, id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, tag: string tag_len): void = let
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, tag)
in $D.destroy(document) end

(* The elements made from a plain tag. None of them takes input or is
   a target: a control (a button, a field, an image) is made only by the
   constructors further down, each of which gives it its accessible
   name, so no control can be made without one *)
#pub datatype tag = TDiv | TSpan | TH1 | TB | TStyle

fn _tag_name (element_tag: tag): [name_len:pos | name_len < 256] string name_len =
  case+ element_tag of
  | TDiv() => "div" | TSpan() => "span" | TH1() => "h1" | TB() => "b" | TStyle() => "style"

fn _add_element {parent_len,id_len:pos | parent_len < 256; id_len < 256}{tag_len:pos | tag_len < 256}
  (parent: string parent_len, id: string id_len, tag: string tag_len): void = let
  val parent_len = _length(parent) and id_len = _length(id)
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(_literal_bytes(parent, parent_len))
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val () = _add_in_document(parent_bytes, parent_len, id_bytes, id_len, tag)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

(* A new element <tag id=id> as the last child of parent *)
#pub fn ui_add {parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (parent: string parent_len, id: string id_len, element_tag: tag): void

implement ui_add(parent, id, element_tag) = _add_element(parent, id, _tag_name(element_tag))

(* A new element with a numbered id under a fixed parent. The functions
   taking ids or texts in arrays consume (free) them. *)
#pub fn ui_add_n {parent_len:pos | parent_len < 256}{id_loc:agz}{id_len:pos | id_len < 256}
  (parent: string parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, element_tag: tag): void

implement ui_add_n(parent, id, id_len, element_tag) = let
  val parent_len = _length(parent)
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(_literal_bytes(parent, parent_len))
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val () = _add_in_document(parent_bytes, parent_len, id_bytes, id_len, _tag_name(element_tag))
  val () = release_bytes(id_frozen, id_bytes)
in release_bytes(parent_frozen, parent_bytes) end

(* A new element with a numbered id under a numbered parent *)
#pub fn ui_add_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, element_tag: tag): void

implement ui_add_nn(parent, parent_len, id, id_len, element_tag) = let
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(parent)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val () = _add_in_document(parent_bytes, parent_len, id_bytes, id_len, _tag_name(element_tag))
  val () = release_bytes(id_frozen, id_bytes)
  val () = release_bytes(parent_frozen, parent_bytes)
in end


(* Removes every child of element id *)
#pub fn ui_clear {id_len:pos | id_len < 256} (id: string id_len): void

implement ui_clear(id) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.remove_children(document, id_bytes, id_len)
  val () = $D.destroy(document)
in release_bytes(id_frozen, id_bytes) end

(* ============================================================
   Attributes
   ============================================================ *)

fn _set_attr_bytes {id_loc,value_loc:agz}{id_len:pos | id_len < 256}{name_len:pos | name_len < 256}{value_len:pos}{offset,length:nat | offset + length <= value_len; length < 65536}
  (id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, name: string name_len,
   value_bytes: !$A.borrow(byte, value_loc, value_len), offset: int offset, length: int length): void = let
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_attr(document, id_bytes, id_len, name, value_bytes, offset, length)
in $D.destroy(document) end

(* Attribute name of element id: the literal value. The attributes that
   name an element (aria-label, aria-labelledby, alt, placeholder) or
   give it a role are not among the ones ui_attr sets: only the
   constructors set them *)
fn _set_attr {id_len:pos | id_len < 256}{name_len:pos | name_len < 256}{value_len:pos | value_len < 256}
  (id: string id_len, name: string name_len, value: string value_len): void = let
  val id_len = _length(id) and value_len = _length(value)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(value_frozen, value_bytes) = $A.freeze<byte>(_literal_bytes(value, value_len))
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
in release_bytes(id_frozen, id_bytes) end

fn _set_attr_n {id_loc:agz}{id_len:pos | id_len < 256}{name_len:pos | name_len < 256}{value_len:pos | value_len < 256}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, name: string name_len, value: string value_len): void = let
  val value_len = _length(value)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(_literal_bytes(value, value_len))
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
  val () = release_bytes(id_frozen, id_bytes)
in end

fn _set_attr_buf {id_len:pos | id_len < 256}{name_len:pos | name_len < 256}{l:agz}{n:pos}{value_len:pos | value_len <= n; value_len < 65536}
  (id: string id_len, name: string name_len, value: $A.arr(byte, l, n), value_len: int value_len): void = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
in release_bytes(id_frozen, id_bytes) end

fn _set_attr_n_buf {id_loc:agz}{id_len:pos | id_len < 256}{name_len:pos | name_len < 256}{value_loc:agz}{value_size:pos}{value_len:pos | value_len <= value_size; value_len < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, name: string name_len, value: $A.arr(byte, value_loc, value_size), value_len: int value_len): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
  val () = release_bytes(id_frozen, id_bytes)
in end

(* The attributes other code may set. There is no style: the one inline
   style is a place (ui_place), so nothing can set a colour, a size or
   anything else the stylesheet proves *)
#pub datatype attr = AClass | ASelected | APressed | AValue | AControls
  | ATabindex | ASrc | AValueNow | ACurrent | AGestureRegion | AHidden
  | APwaInstall   (* a click on it asks the browser to install the app (the page's script) *)
  (* reading aloud, by the page's script: a click on APwaSpeak reads the
     element it names from its page, or pauses; on APwaSpeakSelection,
     from the selection; APwaSpeechNext is clicked to turn the page, and
     the page's script fills and keeps the speed and voice choices *)
  | APwaSpeak | APwaSpeakSelection | APwaSpeechNext | APwaSpeechRate | APwaSpeechVoice
  (* sharing, by the page's script: the selection, cited by the element
     named; or the element named's text as a file, named *)
  | APwaShareSelection | APwaShareFile | APwaShareName
  (* the screen and the system, by the page's script: full screen, the
     rotation locked, the brightness chosen; and where the files the
     system opens with the app, or shares with it, are dropped *)
  | APwaFullscreen | APwaOrientationLock | APwaBrightness | APwaFileDrop

fn _attr_name (attribute: attr): [name_len:pos | name_len < 256] string name_len =
  case+ attribute of
  | AClass() => "class" | ASelected() => "aria-selected" | APressed() => "aria-pressed"
  | AValue() => "value" | AControls() => "aria-controls"
  | ATabindex() => "tabindex" | ASrc() => "src" | AValueNow() => "aria-valuenow"
  | ACurrent() => "aria-current" | AGestureRegion() => "data-gesture-region"
  | AHidden() => "aria-hidden" | APwaInstall() => "data-pwa-install"
  | APwaSpeak() => "data-pwa-speak" | APwaSpeakSelection() => "data-pwa-speak-selection"
  | APwaSpeechNext() => "data-pwa-speech-next" | APwaSpeechRate() => "data-pwa-speech-rate"
  | APwaSpeechVoice() => "data-pwa-speech-voice"
  | APwaShareSelection() => "data-pwa-share-selection" | APwaShareFile() => "data-pwa-share-file"
  | APwaShareName() => "data-pwa-share-name"
  | APwaFullscreen() => "data-pwa-fullscreen" | APwaOrientationLock() => "data-pwa-orientation-lock"
  | APwaBrightness() => "data-pwa-brightness" | APwaFileDrop() => "data-pwa-file-drop"

(* The attribute of element id: the literal value (non-empty) *)
#pub fn ui_attr {id_len:pos | id_len < 256}{value_len:pos | value_len < 256}
  (id: string id_len, attribute: attr, value: string value_len): void

implement ui_attr(id, attribute, value) = _set_attr(id, _attr_name(attribute), value)

#pub fn ui_attr_n {id_loc:agz}{id_len:pos | id_len < 256}{value_len:pos | value_len < 256}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, attribute: attr, value: string value_len): void

implement ui_attr_n(id, id_len, attribute, value) = _set_attr_n(id, id_len, _attr_name(attribute), value)

(* The attribute of element id: value[0, value_len) *)
#pub fn ui_attr_buf {id_len:pos | id_len < 256}{l:agz}{n:pos}{value_len:pos | value_len <= n; value_len < 65536}
  (id: string id_len, attribute: attr, value: $A.arr(byte, l, n), value_len: int value_len): void

implement ui_attr_buf(id, attribute, value, value_len) = _set_attr_buf(id, _attr_name(attribute), value, value_len)

#pub fn ui_attr_n_buf {id_loc:agz}{id_len:pos | id_len < 256}{value_loc:agz}{value_size:pos}{value_len:pos | value_len <= value_size; value_len < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, attribute: attr, value: $A.arr(byte, value_loc, value_size), value_len: int value_len): void

implement ui_attr_n_buf(id, id_len, attribute, value, value_len) = _set_attr_n_buf(id, id_len, _attr_name(attribute), value, value_len)

(* Where an element sits along its track (PLeft) or how much of it it
   fills (PWidth) *)
#pub datatype place = PLeft | PWidth

(* "left:" or "width:", then tenths / 10 with one decimal, then "%" *)
fn _place_style {l:agz}{tenths:nat | tenths <= 1000} (style: !$A.arr(byte, l, 32), placement: place, tenths: int tenths): [style_len:pos | style_len <= 32] int style_len = let
  val style_len = (case+ placement of
    | PLeft() => _put_text(style, 0, "left:", 5, 0)
    | PWidth() => _put_text(style, 0, "width:", 6, 0)): [written:pos | written <= 6] int written
  val style_len = $S.int_to_str(style, style_len, 32, tenths / 10)
  val style_len = _put_text(style, style_len, ".", 1, 0)
  val style_len = $S.int_to_str(style, style_len, 32, tenths - (tenths / 10) * 10)
in _put_text(style, style_len, "%", 1, 0) end

(* Element id's place, in tenths of a percent of its track *)
#pub fn ui_place {id_len:pos | id_len < 256}{tenths:nat | tenths <= 1000} (id: string id_len, placement: place, tenths: int tenths): void

implement ui_place (id, placement, tenths) = let
  val style = $A.alloc<byte>(32)
  val style_len = _place_style(style, placement, tenths)
in _set_attr_buf(id, "style", style, style_len) end

#pub fn ui_place_n {id_loc:agz}{id_len:pos | id_len < 256}{tenths:nat | tenths <= 1000}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, placement: place, tenths: int tenths): void

implement ui_place_n (id, id_len, placement, tenths) = let
  val style = $A.alloc<byte>(32)
  val style_len = _place_style(style, placement, tenths)
in _set_attr_n_buf(id, id_len, "style", style, style_len) end

(* The class of element id *)
#pub fn ui_class {id_len:pos | id_len < 256}{class_len:pos | class_len < 256} (id: string id_len, class_name: string class_len): void

implement ui_class(id, class_name) = _set_attr(id, "class", class_name)

(* Whether element id is shown (hidden ones have data-hide="1", which the
   stylesheet does not display) *)
#pub fn ui_show {id_len:pos | id_len < 256} (id: string id_len, shown: bool): void

implement ui_show(id, shown) =
  if shown then _set_attr(id, "data-hide", "0") else _set_attr(id, "data-hide", "1")

#pub fn ui_show_n {id_loc:agz}{id_len:pos | id_len < 256} (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, shown: bool): void

implement ui_show_n(id, id_len, shown) =
  if shown then _set_attr_n(id, id_len, "data-hide", "0") else _set_attr_n(id, id_len, "data-hide", "1")

(* The file input id, made again (so a file chosen twice in a row is
   taken both times) as the one child of parent after its label: its
   change events are taken on parent. Its name is its label. *)
#pub fn ui_file_input {parent_len,id_len:pos | parent_len < 256; id_len < 256}{label_len,accept_len:pos | label_len < 256; accept_len < 256}
  (parent: string parent_len, id: string id_len, label: string label_len, accept: string accept_len, multiple: bool): void

implement ui_file_input(parent, id, label, accept, multiple) = let
  val () = ui_text(parent, label)
  val () = _add_element(parent, id, "input")
  val () = _set_attr(id, "type", "file")
  val () = _set_attr(id, "accept", accept)
  val () = (if multiple then _set_attr(id, "multiple", "multiple") else ())
in _set_attr(id, "aria-label", label) end

(* The row of a range input input_id from low to high at the value value[0, value_len):
   made again (a range the user has moved no longer follows its value
   attribute), with its label label_id and its value's text value_id after it.
   Its name is its label. *)
#pub fn ui_range {row_len,label_id_len,label_len,input_id_len,low_len,high_len,value_id_len:pos | row_len < 256; label_id_len < 256; label_len < 256; input_id_len < 256; low_len < 256; high_len < 256; value_id_len < 256}{l:agz}{n:pos}{value_len:pos | value_len <= n; value_len < 65536}
  (row: string row_len, label_id: string label_id_len, label: string label_len, input_id: string input_id_len, low: string low_len, high: string high_len, value_id: string value_id_len,
   value: $A.arr(byte, l, n), value_len: int value_len): void

implement ui_range(row, label_id, label, input_id, low, high, value_id, value, value_len) = let
  val () = ui_clear(row)
  val () = _add_element(row, label_id, "span")
  val () = _set_attr(label_id, "class", "slabel")
  val () = ui_text(label_id, label)
  val () = _add_element(row, input_id, "input")
  val () = _set_attr(input_id, "type", "range")
  val () = _set_attr(input_id, "min", low)
  val () = _set_attr(input_id, "max", high)
  val () = _set_attr_buf(input_id, "value", value, value_len)
  val () = _set_attr(input_id, "aria-label", label)
  val () = _add_element(row, value_id, "span")
in _set_attr(value_id, "class", "sval") end


(* ============================================================
   Text
   ============================================================ *)

fn _set_text_bytes {id_loc,text_loc:agz}{id_len:pos | id_len < 256}{text_size:pos}{offset,length:nat | offset + length <= text_size; length < 65536}
  (id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, text_bytes: !$A.borrow(byte, text_loc, text_size), offset: int offset, length: int length): void = let
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_text(document, id_bytes, id_len, text_bytes, offset, length)
in $D.destroy(document) end

(* The text of element id: the literal text *)
#pub fn ui_text {id_len:pos | id_len < 256}{text_len:pos | text_len < 256} (id: string id_len, text: string text_len): void

implement ui_text(id, text) = let
  val id_len = _length(id) and text_len = _length(text)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(text_frozen, text_bytes) = $A.freeze<byte>(_literal_bytes(text, text_len))
  val () = _set_text_bytes(id_bytes, id_len, text_bytes, 0, text_len)
  val () = release_bytes(text_frozen, text_bytes)
in release_bytes(id_frozen, id_bytes) end

#pub fn ui_text_n {id_loc:agz}{id_len:pos | id_len < 256}{text_len:pos | text_len < 256} (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, text: string text_len): void

implement ui_text_n(id, id_len, text) = let
  val text_len = _length(text)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(text_frozen, text_bytes) = $A.freeze<byte>(_literal_bytes(text, text_len))
  val () = _set_text_bytes(id_bytes, id_len, text_bytes, 0, text_len)
  val () = release_bytes(text_frozen, text_bytes)
  val () = release_bytes(id_frozen, id_bytes)
in end

(* The text of element id: text[0, text_len) *)
#pub fn ui_text_buf {id_len:pos | id_len < 256}{l:agz}{n:pos}{text_len:nat | text_len <= n; text_len < 65536}
  (id: string id_len, text: $A.arr(byte, l, n), text_len: int text_len): void

implement ui_text_buf(id, text, text_len) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(text_frozen, text_bytes) = $A.freeze<byte>(text)
  val () = _set_text_bytes(id_bytes, id_len, text_bytes, 0, text_len)
  val () = release_bytes(text_frozen, text_bytes)
in release_bytes(id_frozen, id_bytes) end

#pub fn ui_text_n_buf {id_loc:agz}{id_len:pos | id_len < 256}{text_loc:agz}{text_size:pos}{text_len:nat | text_len <= text_size; text_len < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, text: $A.arr(byte, text_loc, text_size), text_len: int text_len): void

implement ui_text_n_buf(id, id_len, text, text_len) = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(text_frozen, text_bytes) = $A.freeze<byte>(text)
  val () = _set_text_bytes(id_bytes, id_len, text_bytes, 0, text_len)
  val () = release_bytes(text_frozen, text_bytes)
  val () = release_bytes(id_frozen, id_bytes)
in end

(* The text of element id: data[offset, offset + length) of a borrow *)
#pub fn ui_text_n_b {id_loc:agz}{id_len:pos | id_len < 256}{text_loc:agz}{text_size:pos}{offset,length:nat | offset + length <= text_size; length < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, text_bytes: !$A.borrow(byte, text_loc, text_size), offset: int offset, length: int length): void

implement ui_text_n_b(id, id_len, text_bytes, offset, length) = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val () = _set_text_bytes(id_bytes, id_len, text_bytes, offset, length)
  val () = release_bytes(id_frozen, id_bytes)
in end

(* The text of element id: a long literal (under 64 KiB) *)
#pub fn ui_text_long {id_len:pos | id_len < 256}{text_len:pos | text_len < 65536} (id: string id_len, text: string text_len): void

implement ui_text_long(id, text) = let
  val id_len = _length(id)
  val text_len = g1u2i(string1_length(text))
  val text_array = $A.alloc<byte>(text_len)
  val () = $A.write_text(text_array, 0, $A.text_lit(text), text_len)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(text_frozen, text_bytes) = $A.freeze<byte>(text_array)
  val () = _set_text_bytes(id_bytes, id_len, text_bytes, 0, text_len)
  val () = release_bytes(text_frozen, text_bytes)
in release_bytes(id_frozen, id_bytes) end

(* ============================================================
   Controls, images and roles. These are the only ways to make a
   button, a field or an image, or to give an element a role or a
   name, so each rule below holds for every one the app makes:

   * a button that shows text is named by that text alone (nothing
     can give it another name, so its name holds what it shows);
   * a button that shows an icon has a name, given with it;
   * an image is decorative (alt="") unless given its text;
   * a role that needs a name (a dialog, a region, a toolbar, ...)
     is given one with it.
   ============================================================ *)

(* In document: attribute name of element id_bytes, the literal value; or its text *)
fn _document_attr {document_loc,id_loc:agz}{id_len:pos | id_len < 256}{name_len:pos | name_len < 256}{value_len:pos | value_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, name: string name_len, value: string value_len): void = let
  val value_len = _length(value)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(_literal_bytes(value, value_len))
  val () = $D.set_attr(document, id_bytes, id_len, name, value_bytes, 0, value_len)
in release_bytes(value_frozen, value_bytes) end

fn _document_text {document_loc,id_loc:agz}{id_len:pos | id_len < 256}{text_len:pos | text_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, text: string text_len): void = let
  val text_len = _length(text)
  val @(text_frozen, text_bytes) = $A.freeze<byte>(_literal_bytes(text, text_len))
  val () = $D.set_text(document, id_bytes, id_len, text_bytes, 0, text_len)
in release_bytes(text_frozen, text_bytes) end

(* An attribute with the empty value (alt="") *)
fn _document_empty_attr {document_loc,id_loc:agz}{id_len:pos | id_len < 256}{name_len:pos | name_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, name: string name_len): void = let
  val @(value_frozen, value_bytes) = $A.freeze<byte>($A.alloc<byte>(1))
  val () = $D.set_attr(document, id_bytes, id_len, name, value_bytes, 0, 0)
in release_bytes(value_frozen, value_bytes) end

(* A button element id_bytes in parent_bytes, of class class_name *)
fn _document_button {document_loc,parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}
  (document: !$D.document(document_loc), parent_bytes: !$A.borrow(byte, parent_loc, parent_len), parent_len: int parent_len,
   id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len): void = let
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, "button")
  val () = _document_attr(document, id_bytes, id_len, "type", "button")
in _document_attr(document, id_bytes, id_len, "class", class_name) end

#pub datatype icon = IcBack | IcClose | IcGear | IcStar | IcSearch | IcPrev | IcNext
  | IcContents | IcNotes | IcFont | IcMore | IcSpeak

fn _glyph (the_icon: icon): [glyph_len:pos | glyph_len < 256] string glyph_len =
  case+ the_icon of
  | IcBack() => "\xE2\x86\x90" | IcClose() => "\xE2\x9C\x95" | IcGear() => "\xE2\x9A\x99"
  | IcStar() => "\xE2\x98\x86" | IcSearch() => "\xF0\x9F\x94\x8D" | IcPrev() => "\xE2\x80\xB9"
  | IcNext() => "\xE2\x80\xBA" | IcContents() => "\xE2\x98\xB0" | IcNotes() => "\xE2\x9C\x8E"
  | IcFont() => "Aa" | IcMore() => "\xE2\x8B\xAE" | IcSpeak() => "\xF0\x9F\x94\x8A"

(* What would be lost for good. Only emptying the Trash cannot be
   undone (everything else is done at once and offered back: undo.bats),
   so it is the one harm *)
#pub datatype harm =
  | HEmptyTrash                           (* every book in the Trash *)

(* The menu item that asks about the_harm: its id and its label *)
fn _harm_item (the_harm: harm): @([id_len:pos | id_len < 256] string id_len, [label_len:pos | label_len < 256] string label_len) =
  case+ the_harm of
  | HEmptyTrash() => @("menu-empty-trash", "Empty Trash")

(* The id of the_harm's menu item, for its click: the item asks about the_harm *)
#pub fn ui_harm_id (the_harm: harm): [id_len:pos | id_len < 256] string id_len
implement ui_harm_id (the_harm) = let val @(id, _) = _harm_item(the_harm) in id end

(* What a dialog's button does: Danger(the_harm) for the one that does the_harm. Red
   is the stylesheet's mark for [data-harm], which only this module
   sets, and only from a harm: on the_harm's menu item (ui_harm_item) and on
   the button that does the_harm (ui_tone) *)
#pub datatype tone = Plain | Danger of harm

(* The kinds of control, each carrying what names it *)
datatype control =
  | {class_len,label_len:pos | class_len < 256; label_len < 256} CText of (string class_len, string label_len)
  | {class_len,name_len:pos | class_len < 256; name_len < 256} CIcon of (string class_len, icon, string name_len)
  | {class_len:pos | class_len < 256} CNamedByContent of (string class_len)
  | {label_len:pos | label_len < 256} CMenuItem of (string label_len)
  | CHarmItem of harm
  | {label_len,controls_len:pos | label_len < 256; controls_len < 256} CTab of (string label_len, string controls_len, bool)
  (* a link out of the app, named by its text, opened in a new tab and
     told nothing of the app; its href is set by ui_https_href *)
  | {class_len,label_len:pos | class_len < 256; label_len < 256} CLinkOut of (string class_len, string label_len)

(* Control the_control as element id_bytes, the last child of parent_bytes *)
fn _control {document_loc,parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (document: !$D.document(document_loc), parent_bytes: !$A.borrow(byte, parent_loc, parent_len), parent_len: int parent_len,
   id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, the_control: control): void =
  case+ the_control of
  | CText(class_name, label) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, class_name)
    in _document_text(document, id_bytes, id_len, label) end
  | CIcon(class_name, the_icon, name) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, class_name)
      val () = _document_attr(document, id_bytes, id_len, "aria-label", name)
    in _document_text(document, id_bytes, id_len, _glyph(the_icon)) end
  | CNamedByContent(class_name) => _document_button(document, parent_bytes, parent_len, id_bytes, id_len, class_name)
  | CLinkOut(class_name, label) => let
      val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, "a")
      val () = _document_attr(document, id_bytes, id_len, "class", class_name)
      val () = _document_attr(document, id_bytes, id_len, "target", "_blank")
      val () = _document_attr(document, id_bytes, id_len, "rel", "noopener noreferrer")
    in _document_text(document, id_bytes, id_len, label) end
  | CMenuItem(label) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, "mi")
      val () = _document_attr(document, id_bytes, id_len, "role", "menuitem")
    in _document_text(document, id_bytes, id_len, label) end
  | CHarmItem(the_harm) => let
      val @(_, label) = _harm_item(the_harm)
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, "mi")
      val () = _document_attr(document, id_bytes, id_len, "role", "menuitem")
      val () = _document_attr(document, id_bytes, id_len, "data-harm", "y")
    in _document_text(document, id_bytes, id_len, label) end
  | CTab(label, controls, selected) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, "tab")
      val () = _document_attr(document, id_bytes, id_len, "role", "tab")
      val () = _document_attr(document, id_bytes, id_len, "aria-controls", controls)
      val () = _document_attr(document, id_bytes, id_len, "aria-selected", (if selected then "true" else "false"): [value_len:pos | value_len < 256] string value_len)
    in _document_text(document, id_bytes, id_len, label) end

fn _control_literal {parent_len,id_len:pos | parent_len < 256; id_len < 256} (parent: string parent_len, id: string id_len, the_control: control): void = let
  val parent_len = _length(parent) and id_len = _length(id)
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(_literal_bytes(parent, parent_len))
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _control(document, parent_bytes, parent_len, id_bytes, id_len, the_control)
  val () = $D.destroy(document)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

fn _control_n {parent_len:pos | parent_len < 256}{id_loc:agz}{id_len:pos | id_len < 256}
  (parent: string parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, the_control: control): void = let
  val parent_len = _length(parent)
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(_literal_bytes(parent, parent_len))
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _control(document, parent_bytes, parent_len, id_bytes, id_len, the_control)
  val () = $D.destroy(document)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

fn _control_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, the_control: control): void = let
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(parent)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _control(document, parent_bytes, parent_len, id_bytes, id_len, the_control)
  val () = $D.destroy(document)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

(* A new element with its class *)
#pub fn ui_el {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}
  (parent: string parent_len, id: string id_len, element_tag: tag, class_name: string class_len): void

implement ui_el(parent, id, element_tag, class_name) = let
  val () = ui_add(parent, id, element_tag)
in _set_attr(id, "class", class_name) end

(* A button named by the text it shows *)
#pub fn ui_text_btn {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}
  (parent: string parent_len, id: string id_len, class_name: string class_len, label: string label_len): void

implement ui_text_btn(parent, id, class_name, label) = _control_literal(parent, id, CText(class_name, label))

(* A button showing icon the_icon, named name *)
#pub fn ui_icon_btn {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{name_len:pos | name_len < 256}
  (parent: string parent_len, id: string id_len, class_name: string class_len, the_icon: icon, name: string name_len): void

implement ui_icon_btn(parent, id, class_name, the_icon, name) = _control_literal(parent, id, CIcon(class_name, the_icon, name))

#pub fn ui_icon_btn_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{name_len:pos | name_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len,
   class_name: string class_len, the_icon: icon, name: string name_len): void

implement ui_icon_btn_nn(parent, parent_len, id, id_len, class_name, the_icon, name) = _control_nn(parent, parent_len, id, id_len, CIcon(class_name, the_icon, name))

(* A numbered button named by what is put in it (a book's title, a
   chapter's, a result's text) *)
#pub fn ui_btn_n {parent_len:pos | parent_len < 256}{id_loc:agz}{id_len:pos | id_len < 256}{class_len:pos | class_len < 256}
  (parent: string parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len): void

implement ui_btn_n(parent, id, id_len, class_name) = _control_n(parent, id, id_len, CNamedByContent(class_name))

#pub fn ui_btn_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len): void

implement ui_btn_nn(parent, parent_len, id, id_len, class_name) = _control_nn(parent, parent_len, id, id_len, CNamedByContent(class_name))

(* A numbered button named by the text it shows *)
#pub fn ui_text_btn_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len, label: string label_len): void

implement ui_text_btn_nn(parent, parent_len, id, id_len, class_name, label) = _control_nn(parent, parent_len, id, id_len, CText(class_name, label))

(* A link out of the app, showing label (its name) *)
#pub fn ui_link_out {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}
  (parent: string parent_len, id: string id_len, class_name: string class_len, label: string label_len): void

implement ui_link_out(parent, id, class_name, label) = _control_literal(parent, id, CLinkOut(class_name, label))

(* Whether bytes[i, expected_len) is expected[i, expected_len) (bytes has at least expected_len bytes) *)
fun _starts_with {l:agz}{n:pos}{expected_len:nat | expected_len <= n}{i:nat | i <= expected_len} .<expected_len - i>.
  (bytes: !$A.arr(byte, l, n), expected: string expected_len, expected_len: int expected_len, i: int i): bool =
  if i >= expected_len then true
  else if byte2int0($A.get<byte>(bytes, i)) <> char2int0(string_get_at(expected, i)) then false
  else _starts_with(bytes, expected, expected_len, i + 1)

(* Whether url[0, url_len) starts with "https://" *)
fn _is_https {l:agz}{n:pos}{url_len:nat | url_len <= n} (url: !$A.arr(byte, l, n), url_len: int url_len): bool =
  if url_len < 8 then false
  else _starts_with(url, "https://", 8, 0)

(* The href of a link out (ui_link_out) id: url[0, url_len), only when it is an
   https URL; otherwise the link is left as it was *)
#pub fn ui_https_href {id_len:pos | id_len < 256}{l:agz}{n:pos}{url_len:pos | url_len <= n; url_len < 65536}
  (id: string id_len, url: $A.arr(byte, l, n), url_len: int url_len): void

implement ui_https_href (id, url, url_len) =
  if _is_https(url, url_len) then _set_attr_buf(id, "href", url, url_len) else $A.free<byte>(url)

(* An item of a menu, named by its label *)
#pub fn ui_menuitem {parent_len,id_len:pos | parent_len < 256; id_len < 256}{label_len:pos | label_len < 256}
  (parent: string parent_len, id: string id_len, label: string label_len): void

implement ui_menuitem(parent, id, label) = _control_literal(parent, id, CMenuItem(label))

(* The menu item that asks about the_harm, marked as losing what it names: its
   id and label are the_harm's *)
#pub fn ui_harm_item {parent_len:pos | parent_len < 256} (parent: string parent_len, the_harm: harm): void

implement ui_harm_item(parent, the_harm) = let
  val @(id, _) = _harm_item(the_harm)
in _control_literal(parent, id, CHarmItem(the_harm)) end

(* Button id's tone: marked when it does a harm *)
#pub fn ui_tone {id_len:pos | id_len < 256} (id: string id_len, button_tone: tone): void

implement ui_tone(id, button_tone) =
  case+ button_tone of
  | Danger(_) => _set_attr(id, "data-harm", "y")
  | Plain() => _set_attr(id, "data-harm", "n")

(* A tab named by its label, controlling the panel controls *)
#pub fn ui_tab {parent_len,id_len:pos | parent_len < 256; id_len < 256}{label_len:pos | label_len < 256}{controls_len:pos | controls_len < 256}
  (parent: string parent_len, id: string id_len, label: string label_len, controls: string controls_len, selected: bool): void

implement ui_tab(parent, id, label, controls, selected) = _control_literal(parent, id, CTab(label, controls, selected))

(* A decorative image (alt=""): the text beside it says what it shows *)
#pub fn ui_img {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}
  (parent: string parent_len, id: string id_len, class_name: string class_len): void

implement ui_img(parent, id, class_name) = let
  val parent_len = _length(parent) and id_len = _length(id)
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(_literal_bytes(parent, parent_len))
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, "img")
  val () = _document_attr(document, id_bytes, id_len, "class", class_name)
  val () = _document_empty_attr(document, id_bytes, id_len, "alt")
  val () = $D.destroy(document)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

#pub fn ui_img_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len): void

implement ui_img_nn(parent, parent_len, id, id_len, class_name) = let
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(parent)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, "img")
  val () = _document_attr(document, id_bytes, id_len, "class", class_name)
  val () = _document_empty_attr(document, id_bytes, id_len, "alt")
  val () = $D.destroy(document)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

(* A text field named name, which is also what it shows while empty.
   Search (type=search) or a multi-line text area. *)
(* A search field, a text area, or one line of text (a name) *)
#pub datatype field = FSearch | FText | FLine
  | FChoice   (* a choice among options the page's script puts in it *)

#pub fn ui_field {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{name_len:pos | name_len < 256}
  (parent: string parent_len, id: string id_len, field_kind: field, class_name: string class_len, name: string name_len): void

implement ui_field(parent, id, field_kind, class_name, name) = let
  val () = (case+ field_kind of
    | FSearch() => let
        val () = _add_element(parent, id, "input")
      in _set_attr(id, "type", "search") end
    | FText() => _add_element(parent, id, "textarea")
    | FChoice() => _add_element(parent, id, "select")
    | FLine() => let
        val () = _add_element(parent, id, "input")
        val () = _set_attr(id, "type", "text")
        val () = _set_attr(id, "autocomplete", "off")
      in _set_attr(id, "enterkeyhint", "done") end)
  val () = _set_attr(id, "class", class_name)
  val () = _set_attr(id, "placeholder", name)
in _set_attr(id, "aria-label", name) end

(* In document: option id_bytes chosen, when selected *)
fn _document_selected {document_loc,id_loc:agz}{id_len:pos | id_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, selected: bool): void =
  if selected then _document_attr(document, id_bytes, id_len, "selected", "selected") else ()

(* An option of the choice (FChoice) select_id, as its last: its value
   value[0, value_len), named by the label it shows,
   label[0, label_len); chosen when selected *)
#pub fn ui_option {select_len:pos | select_len < 256}{id_loc,value_loc,label_loc:agz}{id_len:pos | id_len < 256}
  {value_size,label_size:pos}{value_len:pos | value_len <= value_size; value_len < 256}{label_len:pos | label_len <= label_size; label_len < 256}
  (select_id: string select_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len,
   value: $A.arr(byte, value_loc, value_size), value_len: int value_len,
   label: $A.arr(byte, label_loc, label_size), label_len: int label_len, selected: bool): void

implement ui_option(select_id, id, id_len, value, value_len, label, label_len, selected) = let
  val select_len = _length(select_id)
  val @(select_frozen, select_bytes) = $A.freeze<byte>(_literal_bytes(select_id, select_len))
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val @(label_frozen, label_bytes) = $A.freeze<byte>(label)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(document, select_bytes, select_len, id_bytes, id_len, "option")
  val () = $D.set_attr(document, id_bytes, id_len, "value", value_bytes, 0, value_len)
  val () = $D.set_text(document, id_bytes, id_len, label_bytes, 0, label_len)
  val () = _document_selected(document, id_bytes, id_len, selected)
  val () = $D.destroy(document)
  val () = release_bytes(label_frozen, label_bytes)
  val () = release_bytes(value_frozen, value_bytes)
  val () = release_bytes(id_frozen, id_bytes)
in release_bytes(select_frozen, select_bytes) end

(* Roles that need no name *)
#pub datatype role = RMain | RStatus | RAlert | RTooltip | RHeading

#pub fn ui_role {id_len:pos | id_len < 256} (id: string id_len, the_role: role): void

implement ui_role(id, the_role) =
  case+ the_role of
  | RMain() => _set_attr(id, "role", "main")
  | RStatus() => _set_attr(id, "role", "status")
  | RAlert() => _set_attr(id, "role", "alert")
  | RTooltip() => _set_attr(id, "role", "tooltip")
  | RHeading() => let
      val () = _set_attr(id, "role", "heading")
    in _set_attr(id, "aria-level", "1") end

(* Roles that need a name: given here, with the role *)
#pub datatype named = NRegion | NToolbar | NDialog | NModal | NNavigation | NDocument
  | NSlider | NTablist | NTabpanel | NMenu | NStatus | NGroup

fn _named_role (the_role: named): [role_len:pos | role_len < 256] string role_len =
  case+ the_role of
  | NRegion() => "region" | NToolbar() => "toolbar" | NDialog() => "dialog"
  | NModal() => "dialog" | NNavigation() => "navigation" | NDocument() => "document"
  | NSlider() => "slider" | NTablist() => "tablist" | NTabpanel() => "tabpanel"
  | NMenu() => "menu" | NStatus() => "status" | NGroup() => "group"

fn _named_modal {id_len:pos | id_len < 256} (id: string id_len, the_role: named): void =
  case+ the_role of
  | NModal() => _set_attr(id, "aria-modal", "true")
  | _ => ()

fn _document_modal {document_loc,id_loc:agz}{id_len:pos | id_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, the_role: named): void =
  case+ the_role of
  | NModal() => _document_attr(document, id_bytes, id_len, "aria-modal", "true")
  | _ => ()

(* Role the_role for element id, named name *)
#pub fn ui_named {id_len:pos | id_len < 256}{name_len:pos | name_len < 256} (id: string id_len, the_role: named, name: string name_len): void

implement ui_named(id, the_role, name) = let
  val () = _set_attr(id, "role", _named_role(the_role))
  val () = _named_modal(id, the_role)
in _set_attr(id, "aria-label", name) end

(* Role the_role for numbered element id, named by the text of numbered
   element by *)
#pub fn ui_labelled_nn {id_loc,by_loc:agz}{id_len,by_len:pos | id_len < 256; by_len < 256}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, the_role: named, by: $A.arr(byte, by_loc, by_len), by_len: int by_len): void

implement ui_labelled_nn(id, id_len, the_role, by, by_len) = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(by_frozen, by_bytes) = $A.freeze<byte>(by)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _document_attr(document, id_bytes, id_len, "role", _named_role(the_role))
  val () = _document_modal(document, id_bytes, id_len, the_role)
  val () = $D.set_attr(document, id_bytes, id_len, "aria-labelledby", by_bytes, 0, by_len)
  val () = $D.destroy(document)
  val () = release_bytes(by_frozen, by_bytes)
in release_bytes(id_frozen, id_bytes) end

(* Role the_role for element id, named by the text of element by *)
#pub fn ui_labelled {id_len:pos | id_len < 256}{by_len:pos | by_len < 256} (id: string id_len, the_role: named, by: string by_len): void

implement ui_labelled(id, the_role, by) = let
  val () = _set_attr(id, "role", _named_role(the_role))
  val () = _named_modal(id, the_role)
in _set_attr(id, "aria-labelledby", by) end


(* ============================================================
   Events and focus
   ============================================================ *)

(* What a listener listens on *)
#pub datatype on =
  | {id_len:pos | id_len < 256} OnEl of (string id_len)
  | OnDocument
  | OnWindow
  | OnExternalFiles   (* files handed to the app from outside it *)
  (* pointer events under an element, for the gestures package (bridge's
     listen_gestures) *)
  | {id_len:pos | id_len < 256} OnGestures of (string id_len)

(* The app's listeners, as one table: the last added is at its head.
   A listener's id is its position in the table (the first added is 0),
   so no two listeners share an id, and the table's length, which its
   type carries, bounds the ids below MEDIA_LISTENER, the last of the
   bridge's 128 slots, which is the media query listener's (listen_media
   shares the slots). The table is registered at once by ui_listen_all;
   there is no other way to register a listener. *)
#pub datatype regs(int) =
  | RNil(0)
  | {count:nat}{event_len:pos | event_len < 256} RCons(count + 1) of
      (regs(count), on, string event_len, ($EV.event_payload) -<cloref1> int)

fn _listen_one {event_len:pos | event_len < 256}
  (target: on, event: string event_len, listener: $EV.listener_id, callback: ($EV.event_payload) -<cloref1> int): void = let
  val event_len = _length(event)
  val @(event_frozen, event_bytes) = $A.freeze<byte>(_literal_bytes(event, event_len))
  val () = (case+ target of
    | OnEl(id) => let
        val id_len = _length(id)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
        val () = $EV.listen(id_bytes, id_len, event_bytes, event_len, listener, callback)
      in release_bytes(id_frozen, id_bytes) end
    | OnDocument() => $EV.listen_document(event_bytes, event_len, listener, callback)
    | OnWindow() => $EV.listen_window(event_bytes, event_len, listener, callback)
    | OnExternalFiles() => $EV.listen_external_files(listener, callback)
    | OnGestures(id) => let
        val id_len = _length(id)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
        val () = $EV.listen_gestures(id_bytes, id_len, listener, callback)
      in release_bytes(id_frozen, id_bytes) end)
in release_bytes(event_frozen, event_bytes) end

(* Registers the listeners, each with its position as its id; the
   number registered *)
fun _listen_all {count:nat | count <= 127} .<count>. (listeners: regs(count)): int count =
  case+ listeners of
  | RNil() => 0
  | RCons(rest, target, event, callback) => let
      val position = _listen_all(rest)
      val () = _listen_one(target, event, position, callback)
    in position + 1 end

(* The media query listener's slot (settings' system dark mode): the
   bridge's last, which no listener of the table can have *)
#pub fn ui_media_listener (): int 127
implement ui_media_listener () = 127

#pub fn ui_listen_all {count:nat | count <= 127} (listeners: regs(count)): void

implement ui_listen_all (listeners) = let val _ = _listen_all(listeners) in end

(* Measures element id: its box goes to dom_read's measure slots *)
#pub fn ui_measure {id_len:pos | id_len < 256} (id: string id_len): void

implement ui_measure(id) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val _ = $R.discard<int><int>($DR.measure(id_bytes, id_len))
in release_bytes(id_frozen, id_bytes) end

#pub fn ui_focus {id_len:pos | id_len < 256} (id: string id_len): void

implement ui_focus(id) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val () = $BDOM.focus_node(id_bytes, id_len)
in release_bytes(id_frozen, id_bytes) end

end (* #target wasm *)
