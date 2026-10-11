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
#use result as R
#use wasm.bats-packages.dev/dom as D
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload SCR = "wasm.bats-packages.dev/bridge/src/screen.sats"
staload SP = "wasm.bats-packages.dev/bridge/src/speech.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload AL = "wasm.bats-packages.dev/bridge/src/app_link.sats"
staload BB = "wasm.bats-packages.dev/bridge/src/back_button.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload ME = "wasm.bats-packages.dev/bridge/src/media.sats"
#use result as R
staload "mem.sats"
staload "unreadable.sats"

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

fn _add_in_document {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (parent_bytes: !$A.borrow(byte, parent_loc, parent_len), parent_len: int parent_len, id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, tag: $D.tag): void = let
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, tag)
in $D.destroy(document) end

(* The elements made from a plain tag. None of them takes input or is
   a target: a control (a button, a field, an image) is made only by the
   constructors further down, each of which gives it its accessible
   name, so no control can be made without one *)
#pub datatype tag = TDiv | TSpan | TH1 | TB | TStyle

fn _tag_name (element_tag: tag): $D.tag =
  case+ element_tag of
  | TDiv() => $D.Div() | TSpan() => $D.Span() | TH1() => $D.H1() | TB() => $D.B()
  | TStyle() => $D.Stylesheet($D.AppStylesheet())

fn _add_element {parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (parent: string parent_len, id: string id_len, tag: $D.tag): void = let
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

fn _set_attr_bytes {id_loc,value_loc:agz}{id_len:pos | id_len < 256}{value_len:pos}{offset,length:nat | offset + length <= value_len; length < 65536}
  (id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, name: $D.attribute,
   value_bytes: !$A.borrow(byte, value_loc, value_len), offset: int offset, length: int length): void = let
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_attr(document, id_bytes, id_len, name, value_bytes, offset, length)
in $D.destroy(document) end

(* Attribute name of element id: the literal value. The attributes that
   name an element (aria-label, aria-labelledby, alt, placeholder) or
   give it a role are not among the ones ui_attr sets: only the
   constructors set them *)
fn _set_attr {id_len:pos | id_len < 256}{value_len:pos | value_len < 256}
  (id: string id_len, name: $D.attribute, value: string value_len): void = let
  val id_len = _length(id) and value_len = _length(value)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(value_frozen, value_bytes) = $A.freeze<byte>(_literal_bytes(value, value_len))
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
in release_bytes(id_frozen, id_bytes) end

fn _set_attr_n {id_loc:agz}{id_len:pos | id_len < 256}{value_len:pos | value_len < 256}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, name: $D.attribute, value: string value_len): void = let
  val value_len = _length(value)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(_literal_bytes(value, value_len))
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
  val () = release_bytes(id_frozen, id_bytes)
in end

fn _set_attr_buf {id_len:pos | id_len < 256}{l:agz}{n:pos}{value_len:pos | value_len <= n; value_len < 65536}
  (id: string id_len, name: $D.attribute, value: $A.arr(byte, l, n), value_len: int value_len): void = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
in release_bytes(id_frozen, id_bytes) end

fn _set_attr_n_buf {id_loc:agz}{id_len:pos | id_len < 256}{value_loc:agz}{value_size:pos}{value_len:pos | value_len <= value_size; value_len < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, name: $D.attribute, value: $A.arr(byte, value_loc, value_size), value_len: int value_len): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val () = _set_attr_bytes(id_bytes, id_len, name, value_bytes, 0, value_len)
  val () = release_bytes(value_frozen, value_bytes)
  val () = release_bytes(id_frozen, id_bytes)
in end

(* URL attribute name of element id: value[0, value_len), which dom's
   set_url sets only when it is a URL that runs no script (the callers
   check for more: an https or http address) *)
fn _set_url_bytes {id_loc,value_loc:agz}{id_len:pos | id_len < 256}{value_len:pos}{length:nat | length <= value_len; length < 65536}
  (id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, name: $D.url_attribute,
   value_bytes: !$A.borrow(byte, value_loc, value_len), length: int length): void = let
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val _ = $D.set_url(document, id_bytes, id_len, name, value_bytes, 0, length)
in $D.destroy(document) end

fn _set_url_buf {id_len:pos | id_len < 256}{l:agz}{n:pos}{value_len:pos | value_len <= n; value_len < 65536}
  (id: string id_len, name: $D.url_attribute, value: $A.arr(byte, l, n), value_len: int value_len): void = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val () = _set_url_bytes(id_bytes, id_len, name, value_bytes, value_len)
  val () = release_bytes(value_frozen, value_bytes)
in release_bytes(id_frozen, id_bytes) end

fn _set_url_n_buf {id_loc:agz}{id_len:pos | id_len < 256}{value_loc:agz}{value_size:pos}{value_len:pos | value_len <= value_size; value_len < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, name: $D.url_attribute, value: $A.arr(byte, value_loc, value_size), value_len: int value_len): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val () = _set_url_bytes(id_bytes, id_len, name, value_bytes, value_len)
  val () = release_bytes(value_frozen, value_bytes)
in release_bytes(id_frozen, id_bytes) end

(* A copy of element source, made copy and put at the end of element
   parent's children, scrolled as scroll says: a picture of what
   source shows, which nothing can use. It is inert (no focus, no
   click, nothing read out inside it), and it has neither source's
   focus stop (tabindex) nor its gesture region; the elements inside
   have no ids (bridge's CLONE_NODE drops them: an id names one
   element). All of it goes in one flush, so the copy is never shown
   half made *)
#pub datavtype scrolled = ScrolledAcross of (int) | ScrolledDown of (int)

(* Element id scrolled in document, one axis *)
fn _scroll_in {doc_loc,id_loc:agz}{id_len:pos | id_len < 256}
  (document: !$D.document(doc_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, scroll: scrolled): void =
  case+ scroll of
  | ~ScrolledAcross(left) => $D.set_scroll_left(document, id_bytes, id_len, left)
  | ~ScrolledDown(top) => $D.set_scroll_top(document, id_bytes, id_len, top)

(* Element id scrolled back to its top *)
#pub fn ui_scroll_to_top {id_len:pos | id_len < 256} (id: string id_len): void
implement ui_scroll_to_top (id) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _scroll_in(document, id_bytes, id_len, ScrolledDown(0))
  val () = $D.destroy(document)
in release_bytes(id_frozen, id_bytes) end

#pub fn ui_copy_inert {source_len,parent_len,copy_len:pos | source_len < 256; parent_len < 256; copy_len < 256}
  (source: string source_len, parent: string parent_len, copy: string copy_len, scroll: scrolled): void
implement ui_copy_inert (source, parent, copy, scroll) = let
  val source_len = _length(source)
  val parent_len = _length(parent)
  val copy_len = _length(copy)
  val @(source_frozen, source_bytes) = $A.freeze<byte>(_literal_bytes(source, source_len))
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(_literal_bytes(parent, parent_len))
  val @(copy_frozen, copy_bytes) = $A.freeze<byte>(_literal_bytes(copy, copy_len))
  val empty = $A.alloc<byte>(1)
  val @(empty_frozen, empty_bytes) = $A.freeze<byte>(empty)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.clone_element(document, source_bytes, source_len, parent_bytes, parent_len, copy_bytes, copy_len)
  val () = $D.remove_attr(document, copy_bytes, copy_len, $D.Tabindex)
  val () = $D.remove_attr(document, copy_bytes, copy_len, $D.Data("gesture-region"))
  val () = $D.set_attr(document, copy_bytes, copy_len, $D.Inert, empty_bytes, 0, 0)
  val () = _scroll_in(document, copy_bytes, copy_len, scroll)
  val () = $D.destroy(document)
  val () = release_bytes(empty_frozen, empty_bytes)
  val () = release_bytes(source_frozen, source_bytes)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(copy_frozen, copy_bytes) end

(* The source of image id emptied: "data:,", an empty text, so it shows
   nothing until it is given one *)
#pub fn ui_src_empty {id_len:pos | id_len < 256} (id: string id_len): void
implement ui_src_empty (id) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_url_literal(document, id_bytes, id_len, $D.Src, $D.EmptyData)
  val () = $D.destroy(document)
in release_bytes(id_frozen, id_bytes) end

(* The attributes other code may set. There is no style: the inline
   styles are a place (ui_place) and a fixed page's box (ui_fixed_box_n),
   so nothing can set a colour or anything else the stylesheet proves *)
#pub datatype attr = AClass | ASelected | APressed | AValue | AControls
  | ATabindex | AValueNow | ACurrent | AGestureRegion | AHidden | ADescribedBy
  | AChecked | ADir | AExpanded

fn _attr_name (attribute: attr): $D.attribute =
  case+ attribute of
  | AClass() => $D.Class | ASelected() => $D.Aria("selected") | APressed() => $D.Aria("pressed")
  | AValue() => $D.Value | AControls() => $D.Aria("controls")
  | ATabindex() => $D.Tabindex | AValueNow() => $D.Aria("valuenow")
  | ACurrent() => $D.Aria("current") | AGestureRegion() => $D.Data("gesture-region")
  | AHidden() => $D.Aria("hidden") | ADescribedBy() => $D.Aria("describedby")
  | AChecked() => $D.Aria("checked") | ADir() => $D.Dir | AExpanded() => $D.Aria("expanded")

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
in _set_attr_buf(id, $D.Style, style, style_len) end

#pub fn ui_place_n {id_loc:agz}{id_len:pos | id_len < 256}{tenths:nat | tenths <= 1000}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, placement: place, tenths: int tenths): void

implement ui_place_n (id, id_len, placement, tenths) = let
  val style = $A.alloc<byte>(32)
  val style_len = _place_style(style, placement, tenths)
in _set_attr_n_buf(id, id_len, $D.Style, style, style_len) end

(* The selection toolbar's place (quire#428): where its top is and how
   tall it is, in CSS pixels, as the custom properties the stylesheet's
   `.seltb` rule reads and clamps to the window and the safe area:
   "--seltb-top:120px;--seltb-height:48px". Numbers alone, so no colour or
   anything else the stylesheet proves can be set from here *)
#pub fn ui_toolbar_at {top,height:nat | top <= 10000; height <= 10000} (top: int top, height: int height): void

implement ui_toolbar_at (top, height) = let
  val style = $A.alloc<byte>(64)
  val style_len = _put_text(style, 0, "--seltb-top:", 12, 0)
  val style_len = $S.int_to_str(style, style_len, 64, top)
  val style_len = _put_text(style, style_len, "px;--seltb-height:", 18, 0)
  val style_len = $S.int_to_str(style, style_len, 64, height)
  val style_len = _put_text(style, style_len, "px", 2, 0)
in _set_attr_buf("selection-toolbar", $D.Style, style, style_len) end

(* A fixed-layout page's box (reader.bats, made for each fixed page in
   the page): its width and height in CSS pixels and its zoom in
   thousandths, "width:600px;height:800px;zoom:62.5%". The one inline
   style besides a place, written from numbers alone, so it cannot set
   a colour or anything else the stylesheet proves; a zoom of 0 (which
   would hide the page) does not type-check *)
#pub fn ui_fixed_box_n {id_loc:agz}{id_len:pos | id_len < 256}{width,height:pos | width <= 10000; height <= 10000}{zoom:pos | zoom <= 10000}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, width: int width, height: int height, zoom: int zoom): void

implement ui_fixed_box_n (id, id_len, width, height, zoom) = let
  val style = $A.alloc<byte>(96)
  val style_len = _put_text(style, 0, "width:", 6, 0)
  val style_len = $S.int_to_str(style, style_len, 96, width)
  val style_len = _put_text(style, style_len, "px;height:", 10, 0)
  val style_len = $S.int_to_str(style, style_len, 96, height)
  val style_len = _put_text(style, style_len, "px;zoom:", 8, 0)
  val style_len = $S.int_to_str(style, style_len, 96, zoom / 10)
  val style_len = _put_text(style, style_len, ".", 1, 0)
  val style_len = $S.int_to_str(style, style_len, 96, zoom - (zoom / 10) * 10)
  val style_len = _put_text(style, style_len, "%", 1, 0)
in _set_attr_n_buf(id, id_len, $D.Style, style, style_len) end

(* The class of element id *)
#pub fn ui_class {id_len:pos | id_len < 256}{class_len:pos | class_len < 256} (id: string id_len, class_name: string class_len): void

implement ui_class(id, class_name) = _set_attr(id, $D.Class, class_name)

(* Whether element id is shown (hidden ones have data-hide="1", which the
   stylesheet does not display) *)
#pub fn ui_show {id_len:pos | id_len < 256} (id: string id_len, shown: bool): void

implement ui_show(id, shown) =
  if shown then _set_attr(id, $D.Data("hide"), "0") else _set_attr(id, $D.Data("hide"), "1")

#pub fn ui_show_n {id_loc:agz}{id_len:pos | id_len < 256} (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, shown: bool): void

implement ui_show_n(id, id_len, shown) =
  if shown then _set_attr_n(id, id_len, $D.Data("hide"), "0") else _set_attr_n(id, id_len, $D.Data("hide"), "1")

(* The file input id, made again (so a file chosen twice in a row is
   taken both times) as the one child of parent after its label: its
   change events are taken on parent. Its name is its label. *)
#pub fn ui_file_input {parent_len,id_len:pos | parent_len < 256; id_len < 256}{label_len,accept_len:pos | label_len < 256; accept_len < 256}
  (parent: string parent_len, id: string id_len, label: string label_len, accept: string accept_len, multiple: bool): void

implement ui_file_input(parent, id, label, accept, multiple) = let
  val () = ui_text(parent, label)
  val () = _add_element(parent, id, $D.Input)
  val () = _set_attr(id, $D.Type, "file")
  val () = _set_attr(id, $D.Accept, accept)
  val () = (if multiple then _set_attr(id, $D.Multiple, "multiple") else ())
in _set_attr(id, $D.Aria("label"), label) end

(* The row of a range input input_id from low to high at the value value[0, value_len):
   made again (a range the user has moved no longer follows its value
   attribute), with its label label_id and its value's text value_id after it.
   Its name is its label. *)
#pub fn ui_range {row_len,label_id_len,label_len,input_id_len,low_len,high_len,value_id_len:pos | row_len < 256; label_id_len < 256; label_len < 256; input_id_len < 256; low_len < 256; high_len < 256; value_id_len < 256}{l:agz}{n:pos}{value_len:pos | value_len <= n; value_len < 65536}
  (row: string row_len, label_id: string label_id_len, label: string label_len, input_id: string input_id_len, low: string low_len, high: string high_len, value_id: string value_id_len,
   value: $A.arr(byte, l, n), value_len: int value_len): void

implement ui_range(row, label_id, label, input_id, low, high, value_id, value, value_len) = let
  val () = ui_clear(row)
  val () = _add_element(row, label_id, $D.Span)
  val () = _set_attr(label_id, $D.Class, "slabel")
  val () = ui_text(label_id, label)
  val () = _add_element(row, input_id, $D.Input)
  val () = _set_attr(input_id, $D.Type, "range")
  val () = _set_attr(input_id, $D.Min, low)
  val () = _set_attr(input_id, $D.Max, high)
  val () = _set_attr_buf(input_id, $D.Value, value, value_len)
  val () = _set_attr(input_id, $D.Aria("label"), label)
  val () = _add_element(row, value_id, $D.Span)
in _set_attr(value_id, $D.Class, "sval") end


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
fn _document_attr {document_loc,id_loc:agz}{id_len:pos | id_len < 256}{value_len:pos | value_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, name: $D.attribute, value: string value_len): void = let
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
fn _document_empty_attr {document_loc,id_loc:agz}{id_len:pos | id_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, name: $D.attribute): void = let
  val @(value_frozen, value_bytes) = $A.freeze<byte>($A.alloc<byte>(1))
  val () = $D.set_attr(document, id_bytes, id_len, name, value_bytes, 0, 0)
in release_bytes(value_frozen, value_bytes) end

(* A button element id_bytes in parent_bytes, of class class_name *)
fn _document_button {document_loc,parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}
  (document: !$D.document(document_loc), parent_bytes: !$A.borrow(byte, parent_loc, parent_len), parent_len: int parent_len,
   id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len): void = let
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, $D.Button)
  val () = _document_attr(document, id_bytes, id_len, $D.Type, "button")
in _document_attr(document, id_bytes, id_len, $D.Class, class_name) end

(* The icons: each a glyph of the bundled subset of Material Symbols
   (assets/fonts/material-symbols-subset.woff2, made by
   scripts/icon-font.py; Apache-2.0), at its code point in the Private
   Use Area. One monochrome set, drawn in the control's own text colour
   (so the stylesheet's proven pairs cover it), never an emoji, which
   a platform may draw as a colour picture (#274). Every control that
   shows one is marked data-icon (_control's CIcon), which alone the
   stylesheet gives the icon face (#295) *)
#pub datatype icon = IcBack | IcClose | IcGear | IcBookmark | IcBookmarked | IcSearch | IcPrev | IcNext
  | IcContents | IcNotes | IcFont | IcMore | IcSpeak | IcPhrasePrevious | IcPhraseNext
  | IcAdd | IcSort

fn _glyph (the_icon: icon): [glyph_len:pos | glyph_len < 256] string glyph_len =
  case+ the_icon of
  | IcBack() => "\xEE\x97\x84"               (* arrow_back *)
  | IcClose() => "\xEE\x97\x8D"              (* close *)
  | IcGear() => "\xEE\xA2\xB8"               (* settings *)
  | IcBookmark() => "\xEE\x96\x98"           (* bookmark_add *)
  | IcBookmarked() => "\xEE\x96\x99"         (* bookmark_added *)
  | IcSearch() => "\xEE\xA2\xB6"             (* search *)
  | IcPrev() => "\xEE\x97\x8B"               (* chevron_left *)
  | IcNext() => "\xEE\x97\x8C"               (* chevron_right *)
  | IcContents() => "\xEE\xA3\x9E"           (* toc *)
  | IcNotes() => "\xEE\x9D\x85"              (* edit_note *)
  | IcFont() => "\xEF\x9B\xB1"               (* match_case: "Aa" *)
  | IcMore() => "\xEE\x97\x94"               (* more_vert *)
  | IcSpeak() => "\xEE\x81\x90"              (* volume_up *)
  | IcPhrasePrevious() => "\xEE\x81\x85"     (* skip_previous *)
  | IcPhraseNext() => "\xEE\x81\x84"         (* skip_next *)
  | IcAdd() => "\xEE\x85\x85"               (* add *)
  | IcSort() => "\xEE\x85\xA4"              (* sort *)

(* A highlight's style, and its one name (quire#378): the selection's
   swatches, the annotations' list and its filter all say a style by
   style_label *)
#pub datatype highlight_style = Yellow | Orange | Underlined

#pub fn style_label (style: highlight_style): [label_len:pos | label_len < 256] string label_len
implement style_label (style) =
  case+ style of Yellow() => "Yellow" | Orange() => "Orange" | Underlined() => "Underlined"

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
#pub datavtype tone = Plain | Danger of harm

(* The kinds of control, each carrying what names it *)
datavtype control =
  | {class_len,label_len:pos | class_len < 256; label_len < 256} CText of (string class_len, string label_len)
  | {class_len,name_len:pos | class_len < 256; name_len < 256} CIcon of (string class_len, icon, string name_len)
  | {class_len:pos | class_len < 256} CNamedByContent of (string class_len)
  (* a button that is a colour and no words, named by name (aria-label) *)
  | {class_len,name_len:pos | class_len < 256; name_len < 256} CSwatch of (string class_len, string name_len)
  | {label_len:pos | label_len < 256} CMenuItem of (string label_len)
  | {label_len:pos | label_len < 256} CMenuChoice of (string label_len)
  | CHarmItem of harm
  | {label_len,controls_len:pos | label_len < 256; controls_len < 256} CTab of (string label_len, string controls_len, bool)
  (* a link out of the app, named by its text, opened in a new tab and
     told nothing of the app; its href is set by ui_https_href *)
  | {class_len,label_len:pos | class_len < 256; label_len < 256} CLinkOut of (string class_len, string label_len)
  (* a link that downloads what it points at (a book a catalogue's
     page does not let the app read), named by its text, opened in a new
     tab; its href is set by ui_web_href_n *)
  | {class_len,label_len:pos | class_len < 256; label_len < 256} CDownload of (string class_len, string label_len)

(* Control the_control as element id_bytes, the last child of parent_bytes *)
fn _control {document_loc,parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (document: !$D.document(document_loc), parent_bytes: !$A.borrow(byte, parent_loc, parent_len), parent_len: int parent_len,
   id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, the_control: control): void =
  case+ the_control of
  | ~CText(class_name, label) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, class_name)
    in _document_text(document, id_bytes, id_len, label) end
  | ~CIcon(class_name, the_icon, name) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, class_name)
      (* the icon face (the stylesheet's [data-icon]): the icon's own
         mark, whatever class the caller gives the button, and kept when
         a class is set again, so no icon is drawn in another face, which
         has no glyph for it (#295) *)
      val () = _document_attr(document, id_bytes, id_len, $D.Data("icon"), "y")
      val () = _document_attr(document, id_bytes, id_len, $D.Aria("label"), name)
    in _document_text(document, id_bytes, id_len, _glyph(the_icon)) end
  | ~CNamedByContent(class_name) => _document_button(document, parent_bytes, parent_len, id_bytes, id_len, class_name)
  | ~CSwatch(class_name, name) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, class_name)
    in _document_attr(document, id_bytes, id_len, $D.Aria("label"), name) end
  | ~CLinkOut(class_name, label) => let
      val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, $D.A)
      val () = _document_attr(document, id_bytes, id_len, $D.Class, class_name)
      val () = _document_attr(document, id_bytes, id_len, $D.Target, "_blank")
      val () = _document_attr(document, id_bytes, id_len, $D.Rel, "noopener noreferrer")
    in _document_text(document, id_bytes, id_len, label) end
  | ~CDownload(class_name, label) => let
      val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, $D.A)
      val () = _document_attr(document, id_bytes, id_len, $D.Class, class_name)
      val () = _document_empty_attr(document, id_bytes, id_len, $D.Download)
      val () = _document_attr(document, id_bytes, id_len, $D.Target, "_blank")
      val () = _document_attr(document, id_bytes, id_len, $D.Rel, "noopener noreferrer")
    in _document_text(document, id_bytes, id_len, label) end
  | ~CMenuItem(label) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, "mi")
      val () = _document_attr(document, id_bytes, id_len, $D.Role, "menuitem")
    in _document_text(document, id_bytes, id_len, label) end
  | ~CMenuChoice(label) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, "mi")
      val () = _document_attr(document, id_bytes, id_len, $D.Role, "menuitemradio")
      val () = _document_attr(document, id_bytes, id_len, $D.Aria("checked"), "false")
    in _document_text(document, id_bytes, id_len, label) end
  | ~CHarmItem(the_harm) => let
      val @(_, label) = _harm_item(the_harm)
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, "mi")
      val () = _document_attr(document, id_bytes, id_len, $D.Role, "menuitem")
      val () = _document_attr(document, id_bytes, id_len, $D.Data("harm"), "y")
    in _document_text(document, id_bytes, id_len, label) end
  | ~CTab(label, controls, selected) => let
      val () = _document_button(document, parent_bytes, parent_len, id_bytes, id_len, "tab")
      val () = _document_attr(document, id_bytes, id_len, $D.Role, "tab")
      val () = _document_attr(document, id_bytes, id_len, $D.Aria("controls"), controls)
      val () = _document_attr(document, id_bytes, id_len, $D.Aria("selected"), (if selected then "true" else "false"): [value_len:pos | value_len < 256] string value_len)
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
in _set_attr(id, $D.Class, class_name) end

(* A button named by the text it shows *)
#pub fn ui_text_btn {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}
  (parent: string parent_len, id: string id_len, class_name: string class_len, label: string label_len): void

implement ui_text_btn(parent, id, class_name, label) = _control_literal(parent, id, CText(class_name, label))

(* A button that is a swatch of a colour (the stylesheet draws it by its
   class) and shows no words: named name *)
#pub fn ui_swatch_btn {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{name_len:pos | name_len < 256}
  (parent: string parent_len, id: string id_len, class_name: string class_len, name: string name_len): void

implement ui_swatch_btn(parent, id, class_name, name) = _control_literal(parent, id, CSwatch(class_name, name))

(* A button showing icon the_icon, named name *)
#pub fn ui_icon_btn {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{name_len:pos | name_len < 256}
  (parent: string parent_len, id: string id_len, class_name: string class_len, the_icon: icon, name: string name_len): void

implement ui_icon_btn(parent, id, class_name, the_icon, name) = _control_literal(parent, id, CIcon(class_name, the_icon, name))

(* An import's file input in the icon button parent, which shows the_icon
   (the parent is marked data-icon, as an icon button is); the input's
   name is label, and it lies over the button, invisible, so a tap on the
   button is a tap on the input (a page cannot open the picker itself) *)
#pub fn ui_file_input_icon {parent_len,id_len:pos | parent_len < 256; id_len < 256}{label_len,accept_len:pos | label_len < 256; accept_len < 256}
  (parent: string parent_len, id: string id_len, the_icon: icon, label: string label_len, accept: string accept_len, multiple: bool): void

implement ui_file_input_icon(parent, id, the_icon, label, accept, multiple) = let
  val () = _set_attr(parent, $D.Data("icon"), "y")
  val () = ui_text(parent, _glyph(the_icon))
  val () = _add_element(parent, id, $D.Input)
  val () = _set_attr(id, $D.Type, "file")
  val () = _set_attr(id, $D.Accept, accept)
  val () = (if multiple then _set_attr(id, $D.Multiple, "multiple") else ())
in _set_attr(id, $D.Aria("label"), label) end

(* Icon button id shows the_icon instead (its name stays: a state it
   shows, such as being pressed, is said by its own attribute) *)
#pub fn ui_icon_set {id_len:pos | id_len < 256} (id: string id_len, the_icon: icon): void

implement ui_icon_set(id, the_icon) = ui_text(id, _glyph(the_icon))

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
  if _is_https(url, url_len) then _set_url_buf(id, $D.Href, url, url_len) else $A.free<byte>(url)

(* A link out of the app (ui_link_out) to a fixed https address:
   https:// and then address, set by dom's set_url_literal, whose
   scheme is its constructor's *)
#pub fn ui_link_out_https {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}{address_len:pos | address_len < 240}
  (parent: string parent_len, id: string id_len, class_name: string class_len, label: string label_len, address: string address_len): void

implement ui_link_out_https(parent, id, class_name, label, address) = let
  val () = ui_link_out(parent, id, class_name, label)
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_url_literal(document, id_bytes, id_len, $D.Href, $D.Https(address))
  val () = $D.destroy(document)
in release_bytes(id_frozen, id_bytes) end

(* A link out of the app (ui_link_out) to a fixed path beside it: ./
   and then path, relative to the app's own address, set by dom's
   set_url_literal *)
#pub fn ui_link_out_path {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}{path_len:pos | path_len < 240}
  (parent: string parent_len, id: string id_len, class_name: string class_len, label: string label_len, path: string path_len): void

implement ui_link_out_path(parent, id, class_name, label, path) = let
  val () = ui_link_out(parent, id, class_name, label)
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_url_literal(document, id_bytes, id_len, $D.Href, $D.Path(path))
  val () = $D.destroy(document)
in release_bytes(id_frozen, id_bytes) end

(* A numbered download link (ui_download_nn), showing label (its name) *)
#pub fn ui_download_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len, label: string label_len): void

implement ui_download_nn(parent, parent_len, id, id_len, class_name, label) = _control_nn(parent, parent_len, id, id_len, CDownload(class_name, label))

(* Whether url[0, url_len) starts with "http://" *)
fn _is_http {l:agz}{n:pos}{url_len:nat | url_len <= n} (url: !$A.arr(byte, l, n), url_len: int url_len): bool =
  if url_len < 7 then false
  else _starts_with(url, "http://", 7, 0)

(* The href of the numbered download link id: url[0, url_len), only
   when it is an http or https address; otherwise the link is left as
   it was *)
#pub fn ui_web_href_n {id_loc:agz}{id_len:pos | id_len < 256}{l:agz}{n:pos}{url_len:pos | url_len <= n; url_len < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, url: $A.arr(byte, l, n), url_len: int url_len): void

implement ui_web_href_n (id, id_len, url, url_len) =
  if _is_https(url, url_len) || _is_http(url, url_len) then _set_url_n_buf(id, id_len, $D.Href, url, url_len)
  else let
    val () = $A.free<byte>(id)
  in $A.free<byte>(url) end

(* The source of the numbered image id (ui_img_nn): url[0, url_len),
   only when it is an http or https address *)
#pub fn ui_web_src_n {id_loc:agz}{id_len:pos | id_len < 256}{l:agz}{n:pos}{url_len:pos | url_len <= n; url_len < 65536}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, url: $A.arr(byte, l, n), url_len: int url_len): void

implement ui_web_src_n (id, id_len, url, url_len) =
  if _is_https(url, url_len) || _is_http(url, url_len) then _set_url_n_buf(id, id_len, $D.Src, url, url_len)
  else let
    val () = $A.free<byte>(id)
  in $A.free<byte>(url) end

(* An item of a menu, named by its label *)
#pub fn ui_menuitem {parent_len,id_len:pos | parent_len < 256; id_len < 256}{label_len:pos | label_len < 256}
  (parent: string parent_len, id: string id_len, label: string label_len): void

implement ui_menuitem(parent, id, label) = _control_literal(parent, id, CMenuItem(label))

(* A menu item that is one of a group of choices, of which the current
   one is checked (ui_attr AChecked): WAI-ARIA's menuitemradio, drawn
   with a check mark by the stylesheet while it is checked *)
#pub fn ui_menu_choice {parent_len,id_len:pos | parent_len < 256; id_len < 256}{label_len:pos | label_len < 256}
  (parent: string parent_len, id: string id_len, label: string label_len): void

implement ui_menu_choice(parent, id, label) = _control_literal(parent, id, CMenuChoice(label))

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
  | ~Danger(_) => _set_attr(id, $D.Data("harm"), "y")
  | ~Plain() => _set_attr(id, $D.Data("harm"), "n")

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
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, $D.Img)
  val () = _document_attr(document, id_bytes, id_len, $D.Class, class_name)
  val () = _document_empty_attr(document, id_bytes, id_len, $D.Alt)
  val () = $D.destroy(document)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

#pub fn ui_img_nn {parent_loc,id_loc:agz}{parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}
  (parent: $A.arr(byte, parent_loc, parent_len), parent_len: int parent_len, id: $A.arr(byte, id_loc, id_len), id_len: int id_len, class_name: string class_len): void

implement ui_img_nn(parent, parent_len, id, id_len, class_name) = let
  val @(parent_frozen, parent_bytes) = $A.freeze<byte>(parent)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(document, parent_bytes, parent_len, id_bytes, id_len, $D.Img)
  val () = _document_attr(document, id_bytes, id_len, $D.Class, class_name)
  val () = _document_empty_attr(document, id_bytes, id_len, $D.Alt)
  val () = $D.destroy(document)
  val () = release_bytes(parent_frozen, parent_bytes)
in release_bytes(id_frozen, id_bytes) end

(* An audio element with no controls, hidden from assistive technology:
   it is not a control, so it needs no name (the buttons that play it
   have theirs), and the tags plain elements are made from stay closed
   to controls *)
#pub fn ui_audio {parent_len,id_len:pos | parent_len < 256; id_len < 256}
  (parent: string parent_len, id: string id_len): void

implement ui_audio(parent, id) = let
  val () = _add_element(parent, id, $D.Audio)
in _set_attr(id, $D.Aria("hidden"), "true") end

(* The source of audio id: url[0, url_len), only when it is a blob: URL
   (one the app made of a book's bytes); otherwise it is left as it
   was *)
#pub fn ui_audio_src {id_len:pos | id_len < 256}{l:agz}{n:pos}{url_len:pos | url_len <= n; url_len < 65536}
  (id: string id_len, url: $A.arr(byte, l, n), url_len: int url_len): void

implement ui_audio_src (id, url, url_len) =
  if url_len < 6 then $A.free<byte>(url)
  else if _starts_with(url, "blob:", 5, 0) then _set_url_buf(id, $D.Src, url, url_len)
  else $A.free<byte>(url)

(* A text field named name, which is also what it shows while empty.
   Search (type=search) or a multi-line text area. *)
(* A search field, a text area, or one line of text (a name) *)
#pub datatype field = FSearch | FText | FLine
  | FChoice   (* a choice among options (ui_option) *)

(* A web address, a user name and a password, as a sign-in form has
   them: the browser's password manager can fill them. Their fields are
   made only by ui_form_field, which names each by a visible label, so a
   name does not vanish as the field is typed in (WCAG 3.3.2, 1.3.1;
   quire#361) *)
#pub datatype form_kind = FormUrl | FormUser | FormPassword | FormName

#pub fn ui_field {parent_len,id_len:pos | parent_len < 256; id_len < 256}{class_len:pos | class_len < 256}{name_len:pos | name_len < 256}
  (parent: string parent_len, id: string id_len, field_kind: field, class_name: string class_len, name: string name_len): void

implement ui_field(parent, id, field_kind, class_name, name) = let
  val () = (case+ field_kind of
    | FSearch() => let
        val () = _add_element(parent, id, $D.Input)
      in _set_attr(id, $D.Type, "search") end
    | FText() => _add_element(parent, id, $D.Textarea)
    | FChoice() => _add_element(parent, id, $D.Select)
    | FLine() => let
        val () = _add_element(parent, id, $D.Input)
        val () = _set_attr(id, $D.Type, "text")
        val () = _set_attr(id, $D.Autocomplete, "off")
      in _set_attr(id, $D.Enterkeyhint, "done") end)
  val () = _set_attr(id, $D.Class, class_name)
  val () = _set_attr(id, $D.Placeholder, name)
in _set_attr(id, $D.Aria("label"), name) end

(* A sign-in form's field of the kind, named by a visible label above it
   (a <label for>, label_id its element, saying label), and showing hint
   while empty: an example, never the name *)
#pub fn ui_form_field {parent_len,label_id_len,id_len:pos | parent_len < 256; label_id_len < 256; id_len < 256}{class_len,label_len,hint_len:pos | class_len < 256; label_len < 256; hint_len < 256}
  (parent: string parent_len, label_id: string label_id_len, id: string id_len, form_field: form_kind, class_name: string class_len, label: string label_len, hint: string hint_len): void

implement ui_form_field(parent, label_id, id, form_field, class_name, label, hint) = let
  val () = _add_element(parent, label_id, $D.Label)
  val () = _set_attr(label_id, $D.For, id)
  val () = _set_attr(label_id, $D.Class, "stext")
  val () = ui_text(label_id, label)
  val () = (case+ form_field of
    | FormUrl() => let
        val () = _add_element(parent, id, $D.Input)
        val () = _set_attr(id, $D.Type, "url")
        val () = _set_attr(id, $D.Autocomplete, "url")
        val () = _set_attr(id, $D.Autocapitalize, "none")
      in _set_attr(id, $D.Spellcheck, "false") end
    | FormUser() => let
        val () = _add_element(parent, id, $D.Input)
        val () = _set_attr(id, $D.Type, "text")
        val () = _set_attr(id, $D.Autocomplete, "username")
        val () = _set_attr(id, $D.Autocapitalize, "none")
      in _set_attr(id, $D.Spellcheck, "false") end
    | FormPassword() => let
        val () = _add_element(parent, id, $D.Input)
        val () = _set_attr(id, $D.Type, "password")
      in _set_attr(id, $D.Autocomplete, "current-password") end
    | FormName() => let
        val () = _add_element(parent, id, $D.Input)
        val () = _set_attr(id, $D.Type, "text")
        val () = _set_attr(id, $D.Autocomplete, "off")
      in _set_attr(id, $D.Enterkeyhint, "done") end)
  val () = _set_attr(id, $D.Class, class_name)
in _set_attr(id, $D.Placeholder, hint) end

(* In document: option id_bytes chosen, when selected *)
fn _document_selected {document_loc,id_loc:agz}{id_len:pos | id_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, selected: bool): void =
  if selected then _document_attr(document, id_bytes, id_len, $D.Selected, "selected") else ()

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
  val () = $D.add_element(document, select_bytes, select_len, id_bytes, id_len, $D.Option)
  val () = $D.set_attr(document, id_bytes, id_len, $D.Value, value_bytes, 0, value_len)
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
  | RMain() => _set_attr(id, $D.Role, "main")
  | RStatus() => _set_attr(id, $D.Role, "status")
  | RAlert() => _set_attr(id, $D.Role, "alert")
  | RTooltip() => _set_attr(id, $D.Role, "tooltip")
  | RHeading() => let
      val () = _set_attr(id, $D.Role, "heading")
    in _set_attr(id, $D.Aria("level"), "1") end

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
  | NModal() => _set_attr(id, $D.Aria("modal"), "true")
  | _ => ()

fn _document_modal {document_loc,id_loc:agz}{id_len:pos | id_len < 256}
  (document: !$D.document(document_loc), id_bytes: !$A.borrow(byte, id_loc, id_len), id_len: int id_len, the_role: named): void =
  case+ the_role of
  | NModal() => _document_attr(document, id_bytes, id_len, $D.Aria("modal"), "true")
  | _ => ()

(* Role the_role for element id, named name *)
#pub fn ui_named {id_len:pos | id_len < 256}{name_len:pos | name_len < 256} (id: string id_len, the_role: named, name: string name_len): void

implement ui_named(id, the_role, name) = let
  val () = _set_attr(id, $D.Role, _named_role(the_role))
  val () = _named_modal(id, the_role)
in _set_attr(id, $D.Aria("label"), name) end

(* Role the_role for numbered element id, named by the text of numbered
   element by *)
#pub fn ui_labelled_nn {id_loc,by_loc:agz}{id_len,by_len:pos | id_len < 256; by_len < 256}
  (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, the_role: named, by: $A.arr(byte, by_loc, by_len), by_len: int by_len): void

implement ui_labelled_nn(id, id_len, the_role, by, by_len) = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(by_frozen, by_bytes) = $A.freeze<byte>(by)
  val document = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _document_attr(document, id_bytes, id_len, $D.Role, _named_role(the_role))
  val () = _document_modal(document, id_bytes, id_len, the_role)
  val () = $D.set_attr(document, id_bytes, id_len, $D.Aria("labelledby"), by_bytes, 0, by_len)
  val () = $D.destroy(document)
  val () = release_bytes(by_frozen, by_bytes)
in release_bytes(id_frozen, id_bytes) end

(* Role the_role for element id, named by the text of element by *)
#pub fn ui_labelled {id_len:pos | id_len < 256}{by_len:pos | by_len < 256} (id: string id_len, the_role: named, by: string by_len): void

implement ui_labelled(id, the_role, by) = let
  val () = _set_attr(id, $D.Role, _named_role(the_role))
  val () = _named_modal(id, the_role)
in _set_attr(id, $D.Aria("labelledby"), by) end


(* ============================================================
   Events and focus
   ============================================================ *)

(* What a listener listens on *)
#pub datavtype on =
  | {id_len:pos | id_len < 256} OnEl of (string id_len)
  | OnDocument
  | OnWindow
  (* pointer events under an element, one raw record each, for the
     gestures package's pointer source (bridge's listen_pointer) *)
  | {id_len:pos | id_len < 256} OnPointer of (string id_len)

(* The app's listeners, as one table: the last added is at its head.
   A listener's id is its position in the table (the first added is 0),
   so no two listeners share an id, and the table's length, which its
   type carries, bounds the ids below MEDIA_LISTENER, the last of the
   bridge's 128 slots, which is the media query listener's (listen_media
   shares the slots). The table is registered at once by ui_listen_all;
   there is no other way to register a listener. Besides the page's
   events (RCons), the platform's, each decoded by bridge into its
   datatype, take a slot of the table each: full screen entered or
   left (RFullscreen), reading aloud's events (RSpeech) and the
   browser's offer to install the app coming and going
   (RInstallOffer), the addresses the native app is opened at
   (RAppLink: a sign-in in the system's browser coming back), a load
   of the page's fonts ending (RFonts), and the app's system bars as its
   native side reports them (RSystemBars: a swipe from the screen's edge
   brings hidden ones back), and Android's Back in the native app
   (RBackButton). *)
#pub datavtype regs(int) =
  | RNil(0)
  | {count:nat}{event_len:pos | event_len < 256} RCons(count + 1) of
      (regs(count), on, string event_len, ($EV.event_payload) -<lincloptr1> int)
  | {count:nat} RFullscreen(count + 1) of (regs(count), ($SCR.fullscreen_change) -<lincloptr1> void)
  | {count:nat} RSpeech(count + 1) of (regs(count), ($SP.speech_event) -<lincloptr1> void)
  | {count:nat} RInstallOffer(count + 1) of (regs(count), ($BAPP.install_offer) -<lincloptr1> void)
  | {count:nat} RAppLink(count + 1) of (regs(count), ([k:pos] $BD.dblob(k)) -<lincloptr1> void)
  | {count:nat} RFonts(count + 1) of (regs(count), ($ME.fonts_status) -<lincloptr1> void)
  | {count:nat} RSystemBars(count + 1) of (regs(count), ($SCR.system_bars) -<lincloptr1> void)
  | {count:nat} RBackButton(count + 1) of (regs(count), () -<lincloptr1> void)

fn _listen_one {event_len:pos | event_len < 256}
  (target: on, event: string event_len, listener: $EV.listener_id, callback: ($EV.event_payload) -<lincloptr1> int): void = let
  val event_len = _length(event)
  val @(event_frozen, event_bytes) = $A.freeze<byte>(_literal_bytes(event, event_len))
  val () = (case+ target of
    | ~OnEl(id) => let
        val id_len = _length(id)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
        val () = $EV.listen(id_bytes, id_len, event_bytes, event_len, listener, callback)
      in release_bytes(id_frozen, id_bytes) end
    | ~OnDocument() => $EV.listen_document(event_bytes, event_len, listener, callback)
    | ~OnWindow() => $EV.listen_window(event_bytes, event_len, listener, callback)
    | ~OnPointer(id) => let
        val id_len = _length(id)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
        val () = $EV.listen_pointer(id_bytes, id_len, listener, callback)
      in release_bytes(id_frozen, id_bytes) end)
in release_bytes(event_frozen, event_bytes) end

(* Registers the listeners, each with its position as its id; the
   number registered *)
fun _listen_all {count:nat | count <= 127} .<count>. (listeners: regs(count)): int count =
  case+ listeners of
  | ~RNil() => 0
  | ~RCons(rest, target, event, callback) => let
      val position = _listen_all(rest)
      val () = _listen_one(target, event, position, callback)
    in position + 1 end
  | ~RFullscreen(rest, callback) => let
      val position = _listen_all(rest)
      val () = $SCR.listen_fullscreen(position, callback)
    in position + 1 end
  | ~RSystemBars(rest, callback) => let
      val position = _listen_all(rest)
      val () = $SCR.listen_system_bars(position, callback)
    in position + 1 end
  | ~RSpeech(rest, callback) => let
      val position = _listen_all(rest)
      val () = $SP.listen_speech(position, callback)
    in position + 1 end
  | ~RInstallOffer(rest, callback) => let
      val position = _listen_all(rest)
      val () = $BAPP.listen_install_prompt(position, callback)
    in position + 1 end
  | ~RAppLink(rest, callback) => let
      val position = _listen_all(rest)
      val () = $AL.listen_app_link(position, callback)
    in position + 1 end
  | ~RFonts(rest, callback) => let
      val position = _listen_all(rest)
      val () = $ME.listen_fonts_loaded(position, callback)
    in position + 1 end
  | ~RBackButton(rest, callback) => let
      val position = _listen_all(rest)
      val () = $BB.listen_back_button(position, callback)
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
  val _ = $DR.measure(id_bytes, id_len)
in release_bytes(id_frozen, id_bytes) end

#pub fn ui_focus {id_len:pos | id_len < 256} (id: string id_len): void

implement ui_focus(id) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val () = $BDOM.focus_node(id_bytes, id_len)
in release_bytes(id_frozen, id_bytes) end

(* Element id made inert (no focus, no click or pointer event, nothing
   read out inside it), or not *)
#pub fn ui_inert {id_len:pos | id_len < 256} (id: string id_len, inert: bool): void

implement ui_inert(id, inert) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val empty = $A.alloc<byte>(1)
  val @(empty_frozen, empty_bytes) = $A.freeze<byte>(empty)
  val () = (if inert then let
      val document = $D.open_document($A.text_lit("bats-root"), 9)
      val () = $D.set_attr(document, id_bytes, id_len, $D.Inert, empty_bytes, 0, 0)
    in $D.destroy(document) end
    else let
      val document = $D.open_document($A.text_lit("bats-root"), 9)
      val () = $D.remove_attr(document, id_bytes, id_len, $D.Inert)
    in $D.destroy(document) end)
  val () = release_bytes(empty_frozen, empty_bytes)
in release_bytes(id_frozen, id_bytes) end

(* Where the focus goes back to when an overlay closes: the element
   that had it when the overlay opened, by its id, or none *)
#pub datavtype focus_return =
  | NoFocusReturn of ()
  | {l:agz}{n:pos | n < 256} FocusReturn of ($A.arr(byte, l, n), int n)

#pub fn ui_focus_return_free (back: focus_return): void
implement ui_focus_return_free (back) =
  case+ back of
  | ~NoFocusReturn() => ()
  | ~FocusReturn(id, _) => $A.free<byte>(id)

(* The id of the first element selector[0, selector_len) matches *)
fn _query {l:agz}{n:pos} (selector: $A.arr(byte, l, n), selector_len: int n): focus_return = let
  val @(selector_frozen, selector_bytes) = $A.freeze<byte>(selector)
  val found = $DR.query_selector(selector_bytes, selector_len)
  val () = release_bytes(selector_frozen, selector_bytes)
in
  case+ found of
  | ~$R.none() => NoFocusReturn()
  | ~$R.some(found_id) => let
      val found_len = $BD.blob_len(found_id)
    in
      if found_len <= 0 then let val () = $BD.blob_free(found_id) in NoFocusReturn() end
      else if found_len >= 256 then let val () = $BD.blob_free(found_id) in NoFocusReturn() end
      else let
        val id = $A.alloc<byte>(found_len)
        val () = $BD.blob_read(found_id, 0, id, found_len)
        val () = $BD.blob_free(found_id)
      in FocusReturn(id, found_len) end
    end
end

(* The element that has the focus now, if it has an id *)
#pub fn ui_focused (): focus_return
implement ui_focused () = let
  val selector = $A.alloc<byte>(6)
  val _ = _put_text(selector, 0, ":focus", 6, 0)
in _query(selector, 6) end

(* Focus to element id[0, id_len) *)
fn _focus_bytes {l:agz}{n:pos | n < 256} (id: $A.arr(byte, l, n), id_len: int n): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val () = $BDOM.focus_node(id_bytes, id_len)
in release_bytes(id_frozen, id_bytes) end

(* The focus back where back says, when that element is still shown;
   else to element fallback *)
#pub fn ui_focus_back {fallback_len:pos | fallback_len < 256} (back: focus_return, fallback: string fallback_len): void
implement ui_focus_back (back, fallback) =
  case+ back of
  | ~NoFocusReturn() => ui_focus(fallback)
  | ~FocusReturn(id, id_len) => let
      val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
      val _ = $DR.measure(id_bytes, id_len)
      val () = $A.drop<byte>(id_frozen, id_bytes)
      val id = $A.thaw<byte>(id_frozen)
    in
      if $DR.get_measure_w() > 0 then _focus_bytes(id, id_len)
      else let val () = $A.free<byte>(id) in ui_focus(fallback) end
    end

(* What can take the focus by Tab and is shown: a control, a link or a
   focus stop, not disabled and not hidden (data-hide, which is how an
   element is hidden, ui_show) *)
#define FOCUSABLE ":is(button,input,select,textarea,a[href],[tabindex='0']):not(:disabled,[data-hide='1'],[data-hide='1'] *)"
#define FOCUSABLE_LEN 105

(* The focus to the first element of element id that can take it *)
#pub fn ui_focus_first_in {id_len:pos | id_len < 128} (id: string id_len): void
implement ui_focus_first_in (id) = let
  val id_len = _length(id)
  val selector_len = 2 + id_len + FOCUSABLE_LEN
  val selector = $A.alloc<byte>(selector_len)
  val at = _put_text(selector, 0, "#", 1, 0)
  val at = _put_text(selector, at, id, id_len, 0)
  val at = _put_text(selector, at, " ", 1, 0)
  val _ = _put_text(selector, at, FOCUSABLE, FOCUSABLE_LEN, 0)
in
  case+ _query(selector, selector_len) of
  | ~NoFocusReturn() => ()
  | ~FocusReturn(found, found_len) => _focus_bytes(found, found_len)
end

(* The focus to the last element of element id that can take it: one
   with nothing that can take it after it inside id, neither among its
   following siblings (or inside them) nor after any element it is in *)
#pub fn ui_focus_last_in {id_len:pos | id_len < 128} (id: string id_len): void
implement ui_focus_last_in (id) = let
  val id_len = _length(id)
  (* the selector: #id, then F not followed by an F sibling or a
     sibling holding one, and not inside an element of #id so followed *)
  val selector_len = 1 + id_len + 1 + FOCUSABLE_LEN + 12 + FOCUSABLE_LEN + 5 + FOCUSABLE_LEN + 8
    + id_len + 8 + FOCUSABLE_LEN + 5 + FOCUSABLE_LEN + 4
  val selector = $A.alloc<byte>(selector_len)
  val at = _put_text(selector, 0, "#", 1, 0)
  val at = _put_text(selector, at, id, id_len, 0)
  val at = _put_text(selector, at, " ", 1, 0)
  val at = _put_text(selector, at, FOCUSABLE, FOCUSABLE_LEN, 0)
  val at = _put_text(selector, at, ":not(:has(~ ", 12, 0)
  val at = _put_text(selector, at, FOCUSABLE, FOCUSABLE_LEN, 0)
  val at = _put_text(selector, at, ",~ * ", 5, 0)
  val at = _put_text(selector, at, FOCUSABLE, FOCUSABLE_LEN, 0)
  val at = _put_text(selector, at, ")):not(#", 8, 0)
  val at = _put_text(selector, at, id, id_len, 0)
  val at = _put_text(selector, at, " :has(~ ", 8, 0)
  val at = _put_text(selector, at, FOCUSABLE, FOCUSABLE_LEN, 0)
  val at = _put_text(selector, at, ",~ * ", 5, 0)
  val at = _put_text(selector, at, FOCUSABLE, FOCUSABLE_LEN, 0)
  val _ = _put_text(selector, at, ") *)", 4, 0)
in
  case+ _query(selector, selector_len) of
  | ~NoFocusReturn() => ()
  | ~FocusReturn(found, found_len) => _focus_bytes(found, found_len)
end

(* Captures pointer pointer_id to element id (as the gestures package's
   pointer source asks, once a mouse has moved) *)
#pub fn ui_pointer_capture {id_len:pos | id_len < 256} (id: string id_len, pointer_id: int): void

implement ui_pointer_capture(id, pointer_id) = let
  val id_len = _length(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_literal_bytes(id, id_len))
  val () = $EV.pointer_capture(id_bytes, id_len, pointer_id)
in release_bytes(id_frozen, id_bytes) end

(* ============================================================
   Controls: what a click's target is, decoded once
   ============================================================ *)

(* Whether bytes[at, n) is text, whole *)
fun _id_is {l:agz}{n:nat}{at:nat}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (bytes: !$A.arr(byte, l, n), n: int n, at: int at, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then at + text_len = n
  else if at + i >= n then false
  else if byte2int0($A.get<byte>(bytes, at + i)) <> char2int0(string_get_at(text, i)) then false
  else _id_is(bytes, n, at, text, text_len, i + 1)

(* The Settings screen's controls, each by its element's id (settings_control_id) *)
#pub datatype settings_control =
  | SettingsGoalOff
  | SettingsGoalTen
  | SettingsGoalTwenty
  | SettingsGoalThirty
  | SettingsGoalSixty
  | SettingsSync
  | SettingsDictionaries
  | SettingsExportBackup
  | SettingsSetAside
  | SettingsResetSettings
  | SettingsFactoryReset
  | SettingsAbout
  | SettingsDone

#pub fn settings_control_id (control: settings_control): [id_len:pos | id_len < 256] string id_len
implement settings_control_id (control) =
  case+ control of
  | SettingsGoalOff() => "settings-goal-off"
  | SettingsGoalTen() => "settings-goal-10"
  | SettingsGoalTwenty() => "settings-goal-20"
  | SettingsGoalThirty() => "settings-goal-30"
  | SettingsGoalSixty() => "settings-goal-60"
  | SettingsSync() => "settings-sync"
  | SettingsDictionaries() => "settings-dictionaries"
  | SettingsExportBackup() => "settings-export-backup"
  | SettingsSetAside() => "settings-set-aside"
  | SettingsResetSettings() => "settings-reset-settings"
  | SettingsFactoryReset() => "settings-factory-reset"
  | SettingsAbout() => "settings-about"
  | SettingsDone() => "settings-done"

(* The control after control, in the order the decoder tries them *)
fn _settings_control_after (control: settings_control): $R.option(settings_control) =
  case+ control of
  | SettingsGoalOff() => $R.some(SettingsGoalTen())
  | SettingsGoalTen() => $R.some(SettingsGoalTwenty())
  | SettingsGoalTwenty() => $R.some(SettingsGoalThirty())
  | SettingsGoalThirty() => $R.some(SettingsGoalSixty())
  | SettingsGoalSixty() => $R.some(SettingsSync())
  | SettingsSync() => $R.some(SettingsDictionaries())
  | SettingsDictionaries() => $R.some(SettingsExportBackup())
  | SettingsExportBackup() => $R.some(SettingsSetAside())
  | SettingsSetAside() => $R.some(SettingsResetSettings())
  | SettingsResetSettings() => $R.some(SettingsFactoryReset())
  | SettingsFactoryReset() => $R.some(SettingsAbout())
  | SettingsAbout() => $R.some(SettingsDone())
  | SettingsDone() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _settings_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: settings_control, fuel: int fuel): $R.option(settings_control) = let
  val id = settings_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _settings_control_after(control) of
    | ~$R.some(next) => _settings_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_settings_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(settings_control)
implement ui_settings_control (bytes, n, at) = _settings_control_from(bytes, n, at, SettingsGoalOff(), 12)

(* The library view's filters, layouts and collections' buttons, each by its element's id (library_view_control_id) *)
#pub datatype library_view_control =
  | FilterBooksAll
  | FilterUnread
  | FilterReading
  | FilterFinished
  | CollectionAll
  | CollectionRename
  | CollectionDelete

#pub fn library_view_control_id (control: library_view_control): [id_len:pos | id_len < 256] string id_len
implement library_view_control_id (control) =
  case+ control of
  | FilterBooksAll() => "filter-books-all"
  | FilterUnread() => "filter-unread"
  | FilterReading() => "filter-reading"
  | FilterFinished() => "filter-finished"
  | CollectionAll() => "collection-all"
  | CollectionRename() => "collection-rename"
  | CollectionDelete() => "collection-delete"

(* The control after control, in the order the decoder tries them *)
fn _library_view_control_after (control: library_view_control): $R.option(library_view_control) =
  case+ control of
  | FilterBooksAll() => $R.some(FilterUnread())
  | FilterUnread() => $R.some(FilterReading())
  | FilterReading() => $R.some(FilterFinished())
  | FilterFinished() => $R.some(CollectionAll())
  | CollectionAll() => $R.some(CollectionRename())
  | CollectionRename() => $R.some(CollectionDelete())
  | CollectionDelete() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _library_view_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: library_view_control, fuel: int fuel): $R.option(library_view_control) = let
  val id = library_view_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _library_view_control_after(control) of
    | ~$R.some(next) => _library_view_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_library_view_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(library_view_control)
implement ui_library_view_control (bytes, n, at) = _library_view_control_from(bytes, n, at, FilterBooksAll(), 9)

(* The button that reads the library again, by its element's id (retry_control_id) *)
#pub datatype retry_control =
  | RetryRead

#pub fn retry_control_id (control: retry_control): [id_len:pos | id_len < 256] string id_len
implement retry_control_id (control) =
  case+ control of
  | RetryRead() => "library-try-again"

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_retry_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(retry_control)
implement ui_retry_control (bytes, n, at) = let
  val id = retry_control_id(RetryRead())
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(RetryRead()) else $R.none()
end

(* Try again is shown only with the proof that the failure has hope
   (unreadable.bats's HOPE): for any other failure this does not
   type-check *)
#pub fn ui_try_again_show {f:failure} (hope: HOPE(f) | ): void
implement ui_try_again_show (hope | ) = let
  prval HopeTransient() = hope
in ui_show("library-try-again", true) end

#pub fn ui_try_again_hide (): void
implement ui_try_again_hide () = ui_show("library-try-again", false)

(* A book's menu's items, each by its element's id (card_menu_control_id) *)
#pub datatype card_menu_control =
  | CardMenuInfo
  | CardMenuCollections
  | CardMenuHide
  | CardMenuArchive
  | CardMenuTrash

#pub fn card_menu_control_id (control: card_menu_control): [id_len:pos | id_len < 256] string id_len
implement card_menu_control_id (control) =
  case+ control of
  | CardMenuInfo() => "card-menu-info"
  | CardMenuCollections() => "card-menu-collections"
  | CardMenuHide() => "card-menu-hide"
  | CardMenuArchive() => "card-menu-archive"
  | CardMenuTrash() => "card-menu-trash"

(* The control after control, in the order the decoder tries them *)
fn _card_menu_control_after (control: card_menu_control): $R.option(card_menu_control) =
  case+ control of
  | CardMenuInfo() => $R.some(CardMenuCollections())
  | CardMenuCollections() => $R.some(CardMenuHide())
  | CardMenuHide() => $R.some(CardMenuArchive())
  | CardMenuArchive() => $R.some(CardMenuTrash())
  | CardMenuTrash() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _card_menu_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: card_menu_control, fuel: int fuel): $R.option(card_menu_control) = let
  val id = card_menu_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _card_menu_control_after(control) of
    | ~$R.some(next) => _card_menu_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_card_menu_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(card_menu_control)
implement ui_card_menu_control (bytes, n, at) = _card_menu_control_from(bytes, n, at, CardMenuInfo(), 5)

(* A book's collections' menu: a new one, done, or its backdrop, each by its element's id (collections_control_id) *)
#pub datatype collections_control =
  | CollectionsNew
  | CollectionsDone
  | CollectionsMenu

#pub fn collections_control_id (control: collections_control): [id_len:pos | id_len < 256] string id_len
implement collections_control_id (control) =
  case+ control of
  | CollectionsNew() => "collections-new"
  | CollectionsDone() => "collections-done"
  | CollectionsMenu() => "collections-menu"

(* The control after control, in the order the decoder tries them *)
fn _collections_control_after (control: collections_control): $R.option(collections_control) =
  case+ control of
  | CollectionsNew() => $R.some(CollectionsDone())
  | CollectionsDone() => $R.some(CollectionsMenu())
  | CollectionsMenu() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _collections_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: collections_control, fuel: int fuel): $R.option(collections_control) = let
  val id = collections_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _collections_control_after(control) of
    | ~$R.some(next) => _collections_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_collections_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(collections_control)
implement ui_collections_control (bytes, n, at) = _collections_control_from(bytes, n, at, CollectionsNew(), 3)

(* Book info's buttons, each by its element's id (book_info_control_id) *)
#pub datatype book_info_control =
  | BookInfoBack
  | BookInfoHide
  | BookInfoArchive
  | BookInfoTrash

#pub fn book_info_control_id (control: book_info_control): [id_len:pos | id_len < 256] string id_len
implement book_info_control_id (control) =
  case+ control of
  | BookInfoBack() => "book-info-back"
  | BookInfoHide() => "book-info-hide"
  | BookInfoArchive() => "book-info-archive"
  | BookInfoTrash() => "book-info-trash"

(* The control after control, in the order the decoder tries them *)
fn _book_info_control_after (control: book_info_control): $R.option(book_info_control) =
  case+ control of
  | BookInfoBack() => $R.some(BookInfoHide())
  | BookInfoHide() => $R.some(BookInfoArchive())
  | BookInfoArchive() => $R.some(BookInfoTrash())
  | BookInfoTrash() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _book_info_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: book_info_control, fuel: int fuel): $R.option(book_info_control) = let
  val id = book_info_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _book_info_control_after(control) of
    | ~$R.some(next) => _book_info_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_book_info_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(book_info_control)
implement ui_book_info_control (bytes, n, at) = _book_info_control_from(bytes, n, at, BookInfoBack(), 4)

(* The library search's clear button, each by its element's id (library_search_control_id) *)
#pub datatype library_search_control =
  | LibrarySearchClear

#pub fn library_search_control_id (control: library_search_control): [id_len:pos | id_len < 256] string id_len
implement library_search_control_id (control) =
  case+ control of
  | LibrarySearchClear() => "library-search-clear"

(* The control after control, in the order the decoder tries them *)
fn _library_search_control_after (control: library_search_control): $R.option(library_search_control) =
  case+ control of
  | LibrarySearchClear() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _library_search_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: library_search_control, fuel: int fuel): $R.option(library_search_control) = let
  val id = library_search_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _library_search_control_after(control) of
    | ~$R.some(next) => _library_search_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_library_search_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(library_search_control)
implement ui_library_search_control (bytes, n, at) = _library_search_control_from(bytes, n, at, LibrarySearchClear(), 1)

(* The library menu's items, and its backdrop, each by its element's id (library_menu_control_id) *)
#pub datatype library_menu_control =
  | MenuSettings
  | MenuAbout
  | MenuInstall
  | MenuStats
  | MenuCatalogues
  | MenuHidden
  | MenuArchived
  | MenuTrash
  | MenuClose
  | LibraryMenu

#pub fn library_menu_control_id (control: library_menu_control): [id_len:pos | id_len < 256] string id_len
implement library_menu_control_id (control) =
  case+ control of
  | MenuSettings() => "menu-settings"
  | MenuAbout() => "menu-about"
  | MenuInstall() => "menu-install"
  | MenuStats() => "menu-stats"
  | MenuCatalogues() => "menu-catalogues"
  | MenuHidden() => "menu-hidden"
  | MenuArchived() => "menu-archived"
  | MenuTrash() => "menu-trash"
  | MenuClose() => "menu-close"
  | LibraryMenu() => "library-menu"

(* The control after control, in the order the decoder tries them *)
fn _library_menu_control_after (control: library_menu_control): $R.option(library_menu_control) =
  case+ control of
  | MenuSettings() => $R.some(MenuAbout())
  | MenuAbout() => $R.some(MenuInstall())
  | MenuInstall() => $R.some(MenuStats())
  | MenuStats() => $R.some(MenuCatalogues())
  | MenuCatalogues() => $R.some(MenuHidden())
  | MenuHidden() => $R.some(MenuArchived())
  | MenuArchived() => $R.some(MenuTrash())
  | MenuTrash() => $R.some(MenuClose())
  | MenuClose() => $R.some(LibraryMenu())
  | LibraryMenu() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _library_menu_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: library_menu_control, fuel: int fuel): $R.option(library_menu_control) = let
  val id = library_menu_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _library_menu_control_after(control) of
    | ~$R.some(next) => _library_menu_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_library_menu_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(library_menu_control)
implement ui_library_menu_control (bytes, n, at) = _library_menu_control_from(bytes, n, at, MenuSettings(), 10)

(* The sort and view menu's choices, done, and its backdrop, each by its element's id (sort_menu_control_id) *)
#pub datatype sort_menu_control =
  | SortByLastOpened
  | SortByTitle
  | SortByAuthor
  | SortByDateAdded
  | SortBySeries
  | ViewList
  | ViewGrid
  | SortMenuDone
  | SortMenu

#pub fn sort_menu_control_id (control: sort_menu_control): [id_len:pos | id_len < 256] string id_len
implement sort_menu_control_id (control) =
  case+ control of
  | SortByLastOpened() => "sort-last-opened"
  | SortByTitle() => "sort-title"
  | SortByAuthor() => "sort-author"
  | SortByDateAdded() => "sort-date-added"
  | SortBySeries() => "sort-series"
  | ViewList() => "view-list"
  | ViewGrid() => "view-grid"
  | SortMenuDone() => "sort-menu-done"
  | SortMenu() => "sort-menu"

(* The control after control, in the order the decoder tries them *)
fn _sort_menu_control_after (control: sort_menu_control): $R.option(sort_menu_control) =
  case+ control of
  | SortByLastOpened() => $R.some(SortByTitle())
  | SortByTitle() => $R.some(SortByAuthor())
  | SortByAuthor() => $R.some(SortByDateAdded())
  | SortByDateAdded() => $R.some(SortBySeries())
  | SortBySeries() => $R.some(ViewList())
  | ViewList() => $R.some(ViewGrid())
  | ViewGrid() => $R.some(SortMenuDone())
  | SortMenuDone() => $R.some(SortMenu())
  | SortMenu() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _sort_menu_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: sort_menu_control, fuel: int fuel): $R.option(sort_menu_control) = let
  val id = sort_menu_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _sort_menu_control_after(control) of
    | ~$R.some(next) => _sort_menu_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_sort_menu_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(sort_menu_control)
implement ui_sort_menu_control (bytes, n, at) = _sort_menu_control_from(bytes, n, at, SortByLastOpened(), 9)

(* The reading statistics' goals, done, and its backdrop, each by its element's id (stats_control_id) *)
#pub datatype stats_control =
  | StatsGoalOff
  | StatsGoalTen
  | StatsGoalTwenty
  | StatsGoalThirty
  | StatsGoalSixty
  | StatsDone
  | StatsPanel

#pub fn stats_control_id (control: stats_control): [id_len:pos | id_len < 256] string id_len
implement stats_control_id (control) =
  case+ control of
  | StatsGoalOff() => "stats-goal-off"
  | StatsGoalTen() => "stats-goal-10"
  | StatsGoalTwenty() => "stats-goal-20"
  | StatsGoalThirty() => "stats-goal-30"
  | StatsGoalSixty() => "stats-goal-60"
  | StatsDone() => "stats-done"
  | StatsPanel() => "stats-panel"

(* The control after control, in the order the decoder tries them *)
fn _stats_control_after (control: stats_control): $R.option(stats_control) =
  case+ control of
  | StatsGoalOff() => $R.some(StatsGoalTen())
  | StatsGoalTen() => $R.some(StatsGoalTwenty())
  | StatsGoalTwenty() => $R.some(StatsGoalThirty())
  | StatsGoalThirty() => $R.some(StatsGoalSixty())
  | StatsGoalSixty() => $R.some(StatsDone())
  | StatsDone() => $R.some(StatsPanel())
  | StatsPanel() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _stats_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: stats_control, fuel: int fuel): $R.option(stats_control) = let
  val id = stats_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _stats_control_after(control) of
    | ~$R.some(next) => _stats_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_stats_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(stats_control)
implement ui_stats_control (bytes, n, at) = _stats_control_from(bytes, n, at, StatsGoalOff(), 7)

(* The dictionaries' done, and its backdrop, each by its element's id (dictionaries_control_id) *)
#pub datatype dictionaries_control =
  | DictionariesDone
  | DictionariesPanel

#pub fn dictionaries_control_id (control: dictionaries_control): [id_len:pos | id_len < 256] string id_len
implement dictionaries_control_id (control) =
  case+ control of
  | DictionariesDone() => "dictionaries-done"
  | DictionariesPanel() => "dictionaries-panel"

(* The control after control, in the order the decoder tries them *)
fn _dictionaries_control_after (control: dictionaries_control): $R.option(dictionaries_control) =
  case+ control of
  | DictionariesDone() => $R.some(DictionariesPanel())
  | DictionariesPanel() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _dictionaries_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: dictionaries_control, fuel: int fuel): $R.option(dictionaries_control) = let
  val id = dictionaries_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _dictionaries_control_after(control) of
    | ~$R.some(next) => _dictionaries_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_dictionaries_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(dictionaries_control)
implement ui_dictionaries_control (bytes, n, at) = _dictionaries_control_from(bytes, n, at, DictionariesDone(), 2)

(* The sync screen's buttons, each by its element's id (sync_screen_control_id) *)
#pub datatype sync_screen_control =
  | SyncNow
  | SyncAndroid
  | SyncGoogle
  | SyncFastmail
  | NextcloudSignIn
  | SyncDropbox
  | SyncOff
  | SyncDone
  (* the services' rows (#331), each opening its own sign-in step *)
  | SyncRowGoogle
  | SyncRowDropbox
  | SyncRowFastmail
  | SyncRowNextcloud
  | SyncRowWebDav
  (* the WebDAV step's own button, and the step's Cancel *)
  | SyncWebDav
  | SyncStepCancel
  (* the status card's, while Google's consent screen is awaited (#340) *)
  | SyncStop

#pub fn sync_screen_control_id (control: sync_screen_control): [id_len:pos | id_len < 256] string id_len
implement sync_screen_control_id (control) =
  case+ control of
  | SyncNow() => "sync-now"
  | SyncAndroid() => "sync-android"
  | SyncGoogle() => "sync-google"
  | SyncFastmail() => "sync-fastmail"
  | NextcloudSignIn() => "nextcloud-sign-in"
  | SyncDropbox() => "sync-dropbox"
  | SyncOff() => "sync-off"
  | SyncDone() => "sync-done"
  | SyncRowGoogle() => "sync-row-google"
  | SyncRowDropbox() => "sync-row-dropbox"
  | SyncRowFastmail() => "sync-row-fastmail"
  | SyncRowNextcloud() => "sync-row-nextcloud"
  | SyncRowWebDav() => "sync-row-webdav"
  | SyncWebDav() => "sync-webdav"
  | SyncStepCancel() => "sync-step-cancel"
  | SyncStop() => "sync-stop"

(* The control after control, in the order the decoder tries them *)
fn _sync_screen_control_after (control: sync_screen_control): $R.option(sync_screen_control) =
  case+ control of
  | SyncNow() => $R.some(SyncAndroid())
  | SyncAndroid() => $R.some(SyncGoogle())
  | SyncGoogle() => $R.some(SyncFastmail())
  | SyncFastmail() => $R.some(NextcloudSignIn())
  | NextcloudSignIn() => $R.some(SyncDropbox())
  | SyncDropbox() => $R.some(SyncOff())
  | SyncOff() => $R.some(SyncDone())
  | SyncDone() => $R.some(SyncRowGoogle())
  | SyncRowGoogle() => $R.some(SyncRowDropbox())
  | SyncRowDropbox() => $R.some(SyncRowFastmail())
  | SyncRowFastmail() => $R.some(SyncRowNextcloud())
  | SyncRowNextcloud() => $R.some(SyncRowWebDav())
  | SyncRowWebDav() => $R.some(SyncWebDav())
  | SyncWebDav() => $R.some(SyncStepCancel())
  | SyncStepCancel() => $R.some(SyncStop())
  | SyncStop() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _sync_screen_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: sync_screen_control, fuel: int fuel): $R.option(sync_screen_control) = let
  val id = sync_screen_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _sync_screen_control_after(control) of
    | ~$R.some(next) => _sync_screen_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_sync_screen_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(sync_screen_control)
implement ui_sync_screen_control (bytes, n, at) = _sync_screen_control_from(bytes, n, at, SyncNow(), 15)

(* The buttons of sync's offer of a place, each by its element's id (sync_offer_control_id) *)
#pub datatype sync_offer_control =
  | SyncGo
  | SyncOfferClose

#pub fn sync_offer_control_id (control: sync_offer_control): [id_len:pos | id_len < 256] string id_len
implement sync_offer_control_id (control) =
  case+ control of
  | SyncGo() => "sync-go"
  | SyncOfferClose() => "sync-offer-close"

(* The control after control, in the order the decoder tries them *)
fn _sync_offer_control_after (control: sync_offer_control): $R.option(sync_offer_control) =
  case+ control of
  | SyncGo() => $R.some(SyncOfferClose())
  | SyncOfferClose() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _sync_offer_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: sync_offer_control, fuel: int fuel): $R.option(sync_offer_control) = let
  val id = sync_offer_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _sync_offer_control_after(control) of
    | ~$R.some(next) => _sync_offer_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_sync_offer_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(sync_offer_control)
implement ui_sync_offer_control (bytes, n, at) = _sync_offer_control_from(bytes, n, at, SyncGo(), 2)

(* The reading settings sheet's choices and buttons, each by its
   element's id (typography_control_id) *)
#pub datatype typography_control =
  | FontLiterata
  | FontInter
  | FontBook
  | FontAtkinson
  | ThemeAuto
  | ThemeLight
  | ThemeSepia
  | ThemeDark
  | ThemeNight
  | ThemeGrey
  | LayoutPages
  | LayoutScroll
  | ColumnsAuto
  | ColumnsOne
  | ColumnsTwo
  | JustifySwitch
  | HyphenationSwitch
  | RubyShow
  | RubyHide
  | DimImagesSwitch
  | TapsSides
  | TapsForward
  | TapsOneHand
  | VolumeKeysTurn
  | NarrationSkip
  | NarrationRead
  | TypographyReset
  | TypographyClose
  | ScreenFullscreen
  | ScreenLock
  | ScreenBrightnessSystem

#pub fn typography_control_id (control: typography_control): [id_len:pos | id_len < 256] string id_len
implement typography_control_id (control) =
  case+ control of
  | FontLiterata() => "font-literata"
  | FontInter() => "font-inter"
  | FontBook() => "font-book"
  | FontAtkinson() => "font-atkinson"
  | ThemeAuto() => "theme-auto"
  | ThemeLight() => "theme-light"
  | ThemeSepia() => "theme-sepia"
  | ThemeDark() => "theme-dark"
  | ThemeNight() => "theme-night"
  | ThemeGrey() => "theme-grey"
  | LayoutPages() => "layout-pages"
  | LayoutScroll() => "layout-scroll"
  | ColumnsAuto() => "columns-auto"
  | ColumnsOne() => "columns-one"
  | ColumnsTwo() => "columns-two"
  | JustifySwitch() => "justify-switch"
  | HyphenationSwitch() => "hyphenation-switch"
  | RubyShow() => "ruby-show"
  | RubyHide() => "ruby-hide"
  | DimImagesSwitch() => "dim-images-switch"
  | TapsSides() => "taps-sides"
  | TapsForward() => "taps-forward"
  | TapsOneHand() => "taps-one-hand"
  | VolumeKeysTurn() => "volume-keys-turn"
  | NarrationSkip() => "narration-skip"
  | NarrationRead() => "narration-read"
  | TypographyReset() => "typography-reset"
  | TypographyClose() => "typography-close"
  | ScreenFullscreen() => "screen-fullscreen"
  | ScreenLock() => "screen-lock"
  | ScreenBrightnessSystem() => "screen-brightness-system"

(* The control after control, in the order the decoder tries them *)
fn _typography_control_after (control: typography_control): $R.option(typography_control) =
  case+ control of
  | FontLiterata() => $R.some(FontInter())
  | FontInter() => $R.some(FontBook())
  | FontBook() => $R.some(FontAtkinson())
  | FontAtkinson() => $R.some(ThemeAuto())
  | ThemeAuto() => $R.some(ThemeLight())
  | ThemeLight() => $R.some(ThemeSepia())
  | ThemeSepia() => $R.some(ThemeDark())
  | ThemeDark() => $R.some(ThemeNight())
  | ThemeNight() => $R.some(ThemeGrey())
  | ThemeGrey() => $R.some(LayoutPages())
  | LayoutPages() => $R.some(LayoutScroll())
  | LayoutScroll() => $R.some(ColumnsAuto())
  | ColumnsAuto() => $R.some(ColumnsOne())
  | ColumnsOne() => $R.some(ColumnsTwo())
  | ColumnsTwo() => $R.some(JustifySwitch())
  | JustifySwitch() => $R.some(HyphenationSwitch())
  | HyphenationSwitch() => $R.some(RubyShow())
  | RubyShow() => $R.some(RubyHide())
  | RubyHide() => $R.some(DimImagesSwitch())
  | DimImagesSwitch() => $R.some(TapsSides())
  | TapsSides() => $R.some(TapsForward())
  | TapsForward() => $R.some(TapsOneHand())
  | TapsOneHand() => $R.some(VolumeKeysTurn())
  | VolumeKeysTurn() => $R.some(NarrationSkip())
  | NarrationSkip() => $R.some(NarrationRead())
  | NarrationRead() => $R.some(TypographyReset())
  | TypographyReset() => $R.some(TypographyClose())
  | TypographyClose() => $R.some(ScreenFullscreen())
  | ScreenFullscreen() => $R.some(ScreenLock())
  | ScreenLock() => $R.some(ScreenBrightnessSystem())
  | ScreenBrightnessSystem() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _typography_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: typography_control, fuel: int fuel): $R.option(typography_control) = let
  val id = typography_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _typography_control_after(control) of
    | ~$R.some(next) => _typography_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_typography_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(typography_control)
implement ui_typography_control (bytes, n, at) = _typography_control_from(bytes, n, at, FontLiterata(), 30)

(* The reading settings sheet's tabs (#288), each by its tab's id
   (sheet_tab_control_id); sheet_tab_panel_id is the panel it shows *)
#pub datatype sheet_tab = LookTab | PageTab | TurningTab | AloudTab

#pub fn sheet_tab_control_id (tab: sheet_tab): [id_len:pos | id_len < 256] string id_len
implement sheet_tab_control_id (tab) =
  case+ tab of
  | LookTab() => "typography-look-tab"
  | PageTab() => "typography-page-tab"
  | TurningTab() => "typography-turning-tab"
  | AloudTab() => "typography-aloud-tab"

#pub fn sheet_tab_panel_id (tab: sheet_tab): [id_len:pos | id_len < 256] string id_len
implement sheet_tab_panel_id (tab) =
  case+ tab of
  | LookTab() => "typography-look"
  | PageTab() => "typography-page"
  | TurningTab() => "typography-turning"
  | AloudTab() => "typography-aloud"

(* Whether bytes[at, n) is tab's id *)
fn _sheet_tab_is {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at, tab: sheet_tab): bool = let
  val id = sheet_tab_control_id(tab)
in _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) end

(* The tab whose id is bytes[at, n), if it is one *)
#pub fn ui_sheet_tab {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(sheet_tab)
implement ui_sheet_tab (bytes, n, at) =
  if _sheet_tab_is(bytes, n, at, LookTab()) then $R.some(LookTab())
  else if _sheet_tab_is(bytes, n, at, PageTab()) then $R.some(PageTab())
  else if _sheet_tab_is(bytes, n, at, TurningTab()) then $R.some(TurningTab())
  else if _sheet_tab_is(bytes, n, at, AloudTab()) then $R.some(AloudTab())
  else $R.none()

(* The catalogues' add and done, and its backdrop, each by its element's id (catalogues_control_id) *)
#pub datatype catalogues_control =
  | CatalogueAdd
  | CataloguesDone
  | CataloguesPanel

#pub fn catalogues_control_id (control: catalogues_control): [id_len:pos | id_len < 256] string id_len
implement catalogues_control_id (control) =
  case+ control of
  | CatalogueAdd() => "catalogue-add"
  | CataloguesDone() => "catalogues-done"
  | CataloguesPanel() => "catalogues-panel"

(* The control after control, in the order the decoder tries them *)
fn _catalogues_control_after (control: catalogues_control): $R.option(catalogues_control) =
  case+ control of
  | CatalogueAdd() => $R.some(CataloguesDone())
  | CataloguesDone() => $R.some(CataloguesPanel())
  | CataloguesPanel() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _catalogues_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: catalogues_control, fuel: int fuel): $R.option(catalogues_control) = let
  val id = catalogues_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _catalogues_control_after(control) of
    | ~$R.some(next) => _catalogues_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_catalogues_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(catalogues_control)
implement ui_catalogues_control (bytes, n, at) = _catalogues_control_from(bytes, n, at, CatalogueAdd(), 3)

(* A catalogue's buttons, each by its element's id (catalogue_control_id) *)
#pub datatype catalogue_control =
  | CatalogueBack
  | CatalogueClose
  | CatalogueNext
  | CataloguePrevious
  | CatalogueSearchGo

#pub fn catalogue_control_id (control: catalogue_control): [id_len:pos | id_len < 256] string id_len
implement catalogue_control_id (control) =
  case+ control of
  | CatalogueBack() => "catalogue-back"
  | CatalogueClose() => "catalogue-close"
  | CatalogueNext() => "catalogue-next"
  | CataloguePrevious() => "catalogue-previous"
  | CatalogueSearchGo() => "catalogue-search-go"

(* The control after control, in the order the decoder tries them *)
fn _catalogue_control_after (control: catalogue_control): $R.option(catalogue_control) =
  case+ control of
  | CatalogueBack() => $R.some(CatalogueClose())
  | CatalogueClose() => $R.some(CatalogueNext())
  | CatalogueNext() => $R.some(CataloguePrevious())
  | CataloguePrevious() => $R.some(CatalogueSearchGo())
  | CatalogueSearchGo() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _catalogue_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: catalogue_control, fuel: int fuel): $R.option(catalogue_control) = let
  val id = catalogue_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _catalogue_control_after(control) of
    | ~$R.some(next) => _catalogue_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_catalogue_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(catalogue_control)
implement ui_catalogue_control (bytes, n, at) = _catalogue_control_from(bytes, n, at, CatalogueBack(), 5)

(* The contents panel's close and tabs, each by its element's id (contents_control_id) *)
#pub datatype contents_control =
  | ContentsClose
  | ContentsTab
  | BookmarksTab
  | PagesTab

#pub fn contents_control_id (control: contents_control): [id_len:pos | id_len < 256] string id_len
implement contents_control_id (control) =
  case+ control of
  | ContentsClose() => "contents-close"
  | ContentsTab() => "contents-tab"
  | BookmarksTab() => "bookmarks-tab"
  | PagesTab() => "pages-tab"

(* The control after control, in the order the decoder tries them *)
fn _contents_control_after (control: contents_control): $R.option(contents_control) =
  case+ control of
  | ContentsClose() => $R.some(ContentsTab())
  | ContentsTab() => $R.some(BookmarksTab())
  | BookmarksTab() => $R.some(PagesTab())
  | PagesTab() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _contents_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: contents_control, fuel: int fuel): $R.option(contents_control) = let
  val id = contents_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _contents_control_after(control) of
    | ~$R.some(next) => _contents_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_contents_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(contents_control)
implement ui_contents_control (bytes, n, at) = _contents_control_from(bytes, n, at, ContentsClose(), 4)

(* The selection toolbar's buttons, each by its element's id
   (selection_control_id). A colour is a control for each style, flat:
   a constructor that carried the style would make the control linear
   (quire#378) *)
#pub datatype selection_control =
  | SelectionHighlight
  | SelectionYellow
  | SelectionOrange
  | SelectionUnderlined
  | SelectionNote
  | SelectionCopy
  | SelectionSearch
  | SelectionDefine
  | SelectionLookup
  | SelectionRead
  | SelectionShare
  | SelectionMore

#pub fn selection_control_id (control: selection_control): [id_len:pos | id_len < 256] string id_len
implement selection_control_id (control) =
  case+ control of
  | SelectionHighlight() => "selection-highlight"
  | SelectionYellow() => "selection-yellow"
  | SelectionOrange() => "selection-orange"
  | SelectionUnderlined() => "selection-underlined"
  | SelectionNote() => "selection-note"
  | SelectionCopy() => "selection-copy"
  | SelectionSearch() => "selection-search"
  | SelectionDefine() => "selection-define"
  | SelectionLookup() => "selection-lookup"
  | SelectionRead() => "selection-read"
  | SelectionShare() => "selection-share"
  | SelectionMore() => "selection-more"

(* Where a control is: on the toolbar's first row, or behind More. The
   match is total, so a control added without a tier does not type-check
   (quire#378) *)
#pub datatype selection_tier = Primary | Overflow

#pub fn selection_tier_of (control: selection_control): selection_tier
implement selection_tier_of (control) =
  case+ control of
  | SelectionHighlight() => Primary()
  | SelectionNote() => Primary()
  | SelectionCopy() => Primary()
  | SelectionDefine() => Primary()
  | SelectionLookup() => Primary()
  | SelectionShare() => Primary()
  | SelectionMore() => Primary()
  | SelectionYellow() => Overflow()
  | SelectionOrange() => Overflow()
  | SelectionUnderlined() => Overflow()
  | SelectionSearch() => Overflow()
  | SelectionRead() => Overflow()

(* The element that holds a tier's controls (More itself is on the toolbar) *)
#pub fn selection_tier_id (tier: selection_tier): [id_len:pos | id_len < 256] string id_len
implement selection_tier_id (tier) =
  case+ tier of Primary() => "selection-primary" | Overflow() => "selection-overflow"

(* Which tier the toolbar shows: More turns one into the other, so the
   toolbar is never more than the first row's wrap, whichever it shows *)
#pub datatype selection_view = ShowingPrimary | ShowingOverflow

#pub fn selection_view_show (view: selection_view): void
implement selection_view_show (view) = let
  val () = ui_show(selection_tier_id(Primary()), (case+ view of ShowingPrimary() => true | ShowingOverflow() => false))
  val () = ui_show(selection_tier_id(Overflow()), (case+ view of ShowingPrimary() => false | ShowingOverflow() => true))
in ui_attr(selection_control_id(SelectionMore()), AExpanded, (case+ view of ShowingPrimary() => "false" | ShowingOverflow() => "true"): [n:pos | n < 256] string n) end

(* The control after control, in the order the decoder tries them *)
fn _selection_control_after (control: selection_control): $R.option(selection_control) =
  case+ control of
  | SelectionHighlight() => $R.some(SelectionYellow())
  | SelectionYellow() => $R.some(SelectionOrange())
  | SelectionOrange() => $R.some(SelectionUnderlined())
  | SelectionUnderlined() => $R.some(SelectionNote())
  | SelectionNote() => $R.some(SelectionCopy())
  | SelectionCopy() => $R.some(SelectionSearch())
  | SelectionSearch() => $R.some(SelectionDefine())
  | SelectionDefine() => $R.some(SelectionLookup())
  | SelectionLookup() => $R.some(SelectionRead())
  | SelectionRead() => $R.some(SelectionShare())
  | SelectionShare() => $R.some(SelectionMore())
  | SelectionMore() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _selection_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: selection_control, fuel: int fuel): $R.option(selection_control) = let
  val id = selection_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _selection_control_after(control) of
    | ~$R.some(next) => _selection_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_selection_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(selection_control)
implement ui_selection_control (bytes, n, at) = _selection_control_from(bytes, n, at, SelectionHighlight(), 11)

(* A word's dictionary entry's buttons, each by its element's id (dictionary_control_id) *)
#pub datatype dictionary_control =
  | DictionaryClose
  | DictionaryOnline

#pub fn dictionary_control_id (control: dictionary_control): [id_len:pos | id_len < 256] string id_len
implement dictionary_control_id (control) =
  case+ control of
  | DictionaryClose() => "dictionary-close"
  | DictionaryOnline() => "dictionary-online"

(* The control after control, in the order the decoder tries them *)
fn _dictionary_control_after (control: dictionary_control): $R.option(dictionary_control) =
  case+ control of
  | DictionaryClose() => $R.some(DictionaryOnline())
  | DictionaryOnline() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _dictionary_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: dictionary_control, fuel: int fuel): $R.option(dictionary_control) = let
  val id = dictionary_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _dictionary_control_after(control) of
    | ~$R.some(next) => _dictionary_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_dictionary_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(dictionary_control)
implement ui_dictionary_control (bytes, n, at) = _dictionary_control_from(bytes, n, at, DictionaryClose(), 2)

(* The annotations panel's buttons and filters, each by its element's id (annotations_control_id) *)
#pub datatype annotations_control =
  | AnnotationsClose
  | AnnotationsExport
  | AnnotationsShare
  | FilterAll
  | FilterYellow
  | FilterOrange
  | FilterUnderlined

#pub fn annotations_control_id (control: annotations_control): [id_len:pos | id_len < 256] string id_len
implement annotations_control_id (control) =
  case+ control of
  | AnnotationsClose() => "annotations-close"
  | AnnotationsExport() => "annotations-export"
  | AnnotationsShare() => "annotations-share"
  | FilterAll() => "filter-all"
  | FilterYellow() => "filter-yellow"
  | FilterOrange() => "filter-orange"
  | FilterUnderlined() => "filter-underlined"

(* The control after control, in the order the decoder tries them *)
fn _annotations_control_after (control: annotations_control): $R.option(annotations_control) =
  case+ control of
  | AnnotationsClose() => $R.some(AnnotationsExport())
  | AnnotationsExport() => $R.some(AnnotationsShare())
  | AnnotationsShare() => $R.some(FilterAll())
  | FilterAll() => $R.some(FilterYellow())
  | FilterYellow() => $R.some(FilterOrange())
  | FilterOrange() => $R.some(FilterUnderlined())
  | FilterUnderlined() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _annotations_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: annotations_control, fuel: int fuel): $R.option(annotations_control) = let
  val id = annotations_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _annotations_control_after(control) of
    | ~$R.some(next) => _annotations_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_annotations_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(annotations_control)
implement ui_annotations_control (bytes, n, at) = _annotations_control_from(bytes, n, at, AnnotationsClose(), 7)

(* A note over the page's buttons, each by its element's id (footnote_control_id) *)
#pub datatype footnote_control =
  | FootnoteGo
  | FootnoteClose

#pub fn footnote_control_id (control: footnote_control): [id_len:pos | id_len < 256] string id_len
implement footnote_control_id (control) =
  case+ control of
  | FootnoteGo() => "footnote-go"
  | FootnoteClose() => "footnote-close"

(* The control after control, in the order the decoder tries them *)
fn _footnote_control_after (control: footnote_control): $R.option(footnote_control) =
  case+ control of
  | FootnoteGo() => $R.some(FootnoteClose())
  | FootnoteClose() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _footnote_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: footnote_control, fuel: int fuel): $R.option(footnote_control) = let
  val id = footnote_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _footnote_control_after(control) of
    | ~$R.some(next) => _footnote_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_footnote_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(footnote_control)
implement ui_footnote_control (bytes, n, at) = _footnote_control_from(bytes, n, at, FootnoteGo(), 2)

(* The search panel's close, each by its element's id (search_panel_control_id) *)
#pub datatype search_panel_control =
  | SearchClose

#pub fn search_panel_control_id (control: search_panel_control): [id_len:pos | id_len < 256] string id_len
implement search_panel_control_id (control) =
  case+ control of
  | SearchClose() => "search-close"

(* The control after control, in the order the decoder tries them *)
fn _search_panel_control_after (control: search_panel_control): $R.option(search_panel_control) =
  case+ control of
  | SearchClose() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _search_panel_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: search_panel_control, fuel: int fuel): $R.option(search_panel_control) = let
  val id = search_panel_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _search_panel_control_after(control) of
    | ~$R.some(next) => _search_panel_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_search_panel_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(search_panel_control)
implement ui_search_panel_control (bytes, n, at) = _search_panel_control_from(bytes, n, at, SearchClose(), 1)

(* The search bar's buttons, each by its element's id (search_nav_control_id) *)
#pub datatype search_nav_control =
  | SearchPrevious
  | SearchNext
  | SearchNavClose

#pub fn search_nav_control_id (control: search_nav_control): [id_len:pos | id_len < 256] string id_len
implement search_nav_control_id (control) =
  case+ control of
  | SearchPrevious() => "search-previous"
  | SearchNext() => "search-next"
  | SearchNavClose() => "search-nav-close"

(* The control after control, in the order the decoder tries them *)
fn _search_nav_control_after (control: search_nav_control): $R.option(search_nav_control) =
  case+ control of
  | SearchPrevious() => $R.some(SearchNext())
  | SearchNext() => $R.some(SearchNavClose())
  | SearchNavClose() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _search_nav_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: search_nav_control, fuel: int fuel): $R.option(search_nav_control) = let
  val id = search_nav_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _search_nav_control_after(control) of
    | ~$R.some(next) => _search_nav_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_search_nav_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(search_nav_control)
implement ui_search_nav_control (bytes, n, at) = _search_nav_control_from(bytes, n, at, SearchPrevious(), 3)

(* The image viewer's close, each by its element's id (image_viewer_control_id) *)
#pub datatype image_viewer_control =
  | ImageClose

#pub fn image_viewer_control_id (control: image_viewer_control): [id_len:pos | id_len < 256] string id_len
implement image_viewer_control_id (control) =
  case+ control of
  | ImageClose() => "image-close"

(* The control after control, in the order the decoder tries them *)
fn _image_viewer_control_after (control: image_viewer_control): $R.option(image_viewer_control) =
  case+ control of
  | ImageClose() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _image_viewer_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: image_viewer_control, fuel: int fuel): $R.option(image_viewer_control) = let
  val id = image_viewer_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _image_viewer_control_after(control) of
    | ~$R.some(next) => _image_viewer_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_image_viewer_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(image_viewer_control)
implement ui_image_viewer_control (bytes, n, at) = _image_viewer_control_from(bytes, n, at, ImageClose(), 1)

(* The About screen's buttons, each by its element's id (about_control_id) *)
#pub datatype about_control =
  | AboutDone
  | AboutCopyErrorDetails

#pub fn about_control_id (control: about_control): [id_len:pos | id_len < 256] string id_len
implement about_control_id (control) =
  case+ control of
  | AboutDone() => "about-done"
  | AboutCopyErrorDetails() => "about-error-copy"

(* The control after control, in the order the decoder tries them *)
fn _about_control_after (control: about_control): $R.option(about_control) =
  case+ control of
  | AboutDone() => $R.some(AboutCopyErrorDetails())
  | AboutCopyErrorDetails() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _about_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: about_control, fuel: int fuel): $R.option(about_control) = let
  val id = about_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _about_control_after(control) of
    | ~$R.some(next) => _about_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_about_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(about_control)
implement ui_about_control (bytes, n, at) = _about_control_from(bytes, n, at, AboutDone(), 2)

(* The update toast's buttons, each by its element's id (update_control_id) *)
#pub datatype update_control =
  | UpdateReload
  | UpdateDismiss

#pub fn update_control_id (control: update_control): [id_len:pos | id_len < 256] string id_len
implement update_control_id (control) =
  case+ control of
  | UpdateReload() => "update-reload"
  | UpdateDismiss() => "update-dismiss"

(* The control after control, in the order the decoder tries them *)
fn _update_control_after (control: update_control): $R.option(update_control) =
  case+ control of
  | UpdateReload() => $R.some(UpdateDismiss())
  | UpdateDismiss() => $R.none()

(* The first of control and the controls after it (fuel of them at
   most) whose id is bytes[at, n) *)
fun _update_control_from {l:agz}{n:nat}{at:nat}{fuel:nat} .<fuel>. (bytes: !$A.arr(byte, l, n), n: int n, at: int at, control: update_control, fuel: int fuel): $R.option(update_control) = let
  val id = update_control_id(control)
in
  if _id_is(bytes, n, at, id, g1u2i(string1_length(id)), 0) then $R.some(control)
  else if fuel <= 0 then $R.none()
  else case+ _update_control_after(control) of
    | ~$R.some(next) => _update_control_from(bytes, n, at, next, fuel - 1)
    | ~$R.none() => $R.none()
end

(* The control whose id is bytes[at, n), if it is one *)
#pub fn ui_update_control {l:agz}{n:nat}{at:nat} (bytes: !$A.arr(byte, l, n), n: int n, at: int at): $R.option(update_control)
implement ui_update_control (bytes, n, at) = _update_control_from(bytes, n, at, UpdateReload(), 2)

(* ============================================================
   Keys: a key event's name and modifiers, decoded once
   ============================================================ *)

(* The keys quire answers (a letter in either case), and any other *)
#pub datatype key =
  | ArrowRight
  | ArrowLeft
  | PageDown
  | PageUp
  | SpaceBar
  | VolumeDown
  | VolumeUp
  | MediaNext
  | MediaPrevious
  | HomeKey
  | EndKey
  | LetterB
  | LetterT
  | LetterF
  | Slash
  | EnterKey
  | EscapeKey
  | OtherKey

(* The modifiers held with a key: Shift, and Ctrl or Cmd *)
#pub typedef modifiers = @{ shift = bool, command = bool }

(* Whether key_bytes[1, 1 + name_len) is name, from i *)
fun _name_at {l:agz}{n:nat}{name_len:nat}{i:nat | i <= name_len} .<name_len - i>.
  (key_bytes: !$A.arr(byte, l, n), n: int n, name: string name_len, name_len: int name_len, i: int i): bool =
  if i >= name_len then true
  else if 1 + i >= n then false
  else if byte2int0($A.get<byte>(key_bytes, 1 + i)) <> char2int0(string_get_at(name, i)) then false
  else _name_at(key_bytes, n, name, name_len, i + 1)

(* Whether a key event's bytes (its name's length, its name, its
   modifiers' byte) name the key name *)
fn _key_named {l:agz}{n:nat}{name_len:pos} (key_bytes: !$A.arr(byte, l, n), n: int n, name: string name_len): bool = let
  val name_len = g1u2i(string1_length(name))
in
  if n <> name_len + 2 then false
  else if byte2int0($A.get<byte>(key_bytes, 0)) <> name_len then false
  else _name_at(key_bytes, n, name, name_len, 0)
end

(* The key a key event's bytes name *)
#pub fn ui_key {l:agz}{n:nat} (key_bytes: !$A.arr(byte, l, n), n: int n): key
implement ui_key (key_bytes, n) =
  if _key_named(key_bytes, n, "ArrowRight") then ArrowRight()
  else if _key_named(key_bytes, n, "ArrowLeft") then ArrowLeft()
  else if _key_named(key_bytes, n, "PageDown") then PageDown()
  else if _key_named(key_bytes, n, "PageUp") then PageUp()
  else if _key_named(key_bytes, n, " ") then SpaceBar()
  else if _key_named(key_bytes, n, "AudioVolumeDown") then VolumeDown()
  else if _key_named(key_bytes, n, "AudioVolumeUp") then VolumeUp()
  else if _key_named(key_bytes, n, "MediaTrackNext") then MediaNext()
  else if _key_named(key_bytes, n, "MediaTrackPrevious") then MediaPrevious()
  else if _key_named(key_bytes, n, "Home") then HomeKey()
  else if _key_named(key_bytes, n, "End") then EndKey()
  else if _key_named(key_bytes, n, "b") then LetterB()
  else if _key_named(key_bytes, n, "B") then LetterB()
  else if _key_named(key_bytes, n, "t") then LetterT()
  else if _key_named(key_bytes, n, "T") then LetterT()
  else if _key_named(key_bytes, n, "f") then LetterF()
  else if _key_named(key_bytes, n, "/") then Slash()
  else if _key_named(key_bytes, n, "Enter") then EnterKey()
  else if _key_named(key_bytes, n, "Escape") then EscapeKey()
  else OtherKey()

(* The modifiers of a key event's bytes: its last byte's bits, 1 Shift,
   2 Ctrl and 8 Cmd *)
#pub fn ui_modifiers {l:agz}{n:nat} (key_bytes: !$A.arr(byte, l, n), n: int n): modifiers
implement ui_modifiers (key_bytes, n) =
  if n < 2 then @{ shift = false, command = false }
  else let
    val bits = $AR.low_byte(byte2int0($A.get<byte>(key_bytes, n - 1)))
  in @{ shift = $AR.band_g1(bits, 1) = 1, command = $AR.band_g1(bits, 10) >= 2 } end

end (* #target wasm *)
