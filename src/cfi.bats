(* cfi -- EPUB Canonical Fragment Identifiers over a chapter's parsed tree
   (keyword cfi, #901; the rules and the research: .claude/rules/cfi.md).

   A position in a chapter is a byte position in its source: an element is
   its name_offset, a text is any byte boundary of a character inside a text
   node (or its end). cfi_of writes the in-document steps of that position
   (/4[body01]/10[para05]/3:10); cfi_resolve reads steps and gives the
   position back. The chapter's tree is xhtml_parse's, read and never
   changed or freed here. The spine step and the "!" are cfi_put_spine's and
   cfi_split's, since the package, not the chapter, says which item it is. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use str as S
#use xml-tree as X

staload "entity.sats"

(* ============================================================
   What the readers answer (keyword cfi, #901)
   ============================================================ *)

(* Where steps point in the chapter: an element (its name offset), a place
   in text (a byte position), a place in an element that has no text there
   (the element's name offset: an empty chunk at offset 0, or the step
   after the last element), or nowhere. Linear: a caller matches every
   constructor with case+. *)
#pub datavtype cfi_place =
  | CfiElement of (Int)
  | CfiText of (Int)
  | CfiEmptyText of (Int)
  | CfiNoPlace

(* Which side of a location a reader prefers ("[;s=b]", "[;s=a]") *)
#pub datatype cfi_side = CfiSideNone | CfiSideBefore | CfiSideAfter

(* Whether steps begin with the spine item step "/6/N[idref]!": the N, or
   not a spine step *)
#pub datavtype cfi_spine_step =
  | CfiSpineItem of (Int)
  | CfiNotSpine

(* How far a walk of the steps got, inside this module: the three places
   and nowhere as cfi_place has them, and an [id] to look for in the whole
   chapter (see _settle), which no reader answers *)
datatype walk_kind = WalkElement | WalkText | WalkEmptyText | WalkNothing | WalkLookForId

(* ============================================================
   Characters and UTF-16 units
   ============================================================ *)

fn _byte {l:agz}{n:pos}{i:nat | i < n} (data: !$A.borrow(byte, l, n), i: int i): [v:nat | v < 256] int v =
  $AR.low_byte(byte2int0($A.read<byte>(data, i)))

(* The bytes of the UTF-8 character that starts with lead (a stray
   continuation byte is a character of its own) *)
fn _char_width (lead: int): [w:int | 1 <= w; w <= 4] int w =
  if lead < 192 then 1 else if lead < 224 then 2 else if lead < 240 then 3 else 4

(* Where the character reference whose '&' is at data[from] ends: past its
   ';' within 32 bytes, else past the '&' (entity.bats decodes the same) *)
fun _reference_end {l:agz}{n:pos}{limit:nat | limit <= n}{from:nat | from < limit}{reach:nat | reach <= 32} .<32 - reach>.
  (data: !$A.borrow(byte, l, n), limit: int limit, from: int from, reach: int reach)
  : [stop:int | from < stop; stop <= limit; stop <= from + 34] int stop =
  if from + 1 + reach >= limit then from + 1
  else if reach >= 32 then from + 1
  else if _byte(data, from + 1 + reach) = 59 then from + 2 + reach
  else _reference_end(data, limit, from, reach + 1)

(* The UTF-16 units of the UTF-8 bytes out[at, until) *)
fun _units_of_decoded {l:agz}{size:pos}{until:nat | until <= size}{at:nat | at <= until} .<until - at>.
  (out: !$A.arr(byte, l, size), until: int until, at: int at, units: Nat): Nat =
  if at >= until then units
  else let
    val lead = byte2int0($A.get<byte>(out, at))
    val more = (if lead >= 240 then 2 else if lead >= 128 && lead < 192 then 0 else 1): Nat
  in _units_of_decoded(out, until, at + 1, units + more) end

(* The units of the reference data[from, stop), as the page counts the
   text that entity.bats decodes it to (an unknown reference stays as it
   is, and counts its bytes) *)
fn _reference_units {l:agz}{n:pos}{from,stop:nat | from < stop; stop <= n; stop <= from + 34}
  (data: !$A.borrow(byte, l, n), from: int from, stop: int stop): Nat = let
  val out = $A.alloc<byte>(34)
  val decoded_len = decode_text(data, from, stop - from, out)
  val units = _units_of_decoded(out, decoded_len, 0, 0)
  val () = $A.free<byte>(out)
in units end

(* One step of text data[from, limit): the character (or reference) that
   starts at from, where it ends and the UTF-16 units it is: a character
   outside the BMP is two *)
fn _unit_step {l:agz}{n:pos}{limit:nat | limit <= n}{from:nat | from < limit}
  (data: !$A.borrow(byte, l, n), limit: int limit, from: int from)
  : [stop:int | from < stop; stop <= limit] @(int stop, Nat) = let
  val lead = _byte(data, from)
in
  if lead = 38 then let
    val stop = _reference_end(data, limit, from, 0)
    val units = _reference_units(data, from, stop)
  in @(stop, units) end
  else let
    val width = _char_width(lead)
    val stop = (if from + width <= limit then from + width else limit): [s:int | from < s; s <= limit] int s
  in @(stop, (if width >= 4 then 2 else 1): Nat) end
end

(* The UTF-16 units of text data[from, until) (a reference or a character
   that starts before until is counted whole) *)
fun _units {l:agz}{n:pos}{limit,until:nat | until <= limit; limit <= n}{from:nat | from <= limit} .<limit - from>.
  (data: !$A.borrow(byte, l, n), limit: int limit, until: int until, from: int from, units: Nat): Nat =
  if from >= until then units
  else let
    val @(stop, step_units) = _unit_step(data, limit, from)
  in _units(data, limit, until, stop, units + step_units) end

(* The byte position in data[from, limit] that is target units on from
   units so far; -1 when the text ends first. A target in the middle of a
   pair is the pair's start. *)
fun _position_of_units {l:agz}{n:pos}{limit:nat | limit <= n}{from:nat | from <= limit} .<limit - from>.
  (data: !$A.borrow(byte, l, n), limit: int limit, from: int from, units: Nat, target: Int)
  : [at:int | ~1 <= at; at <= limit] int at =
  if units >= target then from
  else if from >= limit then ~1
  else let
    val @(stop, step_units) = _unit_step(data, limit, from)
  in
    if units + step_units > target then from
    else _position_of_units(data, limit, stop, units + step_units, target)
  end

(* ============================================================
   The tree
   ============================================================ *)

(* Where a node starts: a text's offset, an element's name *)
fn _start_of {n:int}{size:pos} (node: !$X.xml_node(n, size)): int =
  case+ node of
  | $X.xml_text(offset, _) => offset
  | $X.xml_element(name_offset, _, _, _) => name_offset

(* Whether the first of nodes starts at or before position *)
fn _starts_by {n:int}{size:nat} (nodes: !$X.xml_node_list(n, size), position: int): bool =
  case+ nodes of
  | $X.xml_nodes_cons(node, _) => _start_of(node) <= position
  | $X.xml_nodes_nil() => false

(* The value of the attribute named id in attrs as its span (0, 0 when it
   has none or an empty one) *)
fun _id_of {l:agz}{n:pos}{size:nat} .<size>.
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, size)): [offset,value_len:nat | offset + value_len <= n] @(int offset, int value_len) =
  case+ attrs of
  | $X.xml_attrs_nil() => @(0, 0)
  | $X.xml_attrs_cons(name_offset, name_len, value_offset, value_len, rest) =>
    if name_len = 2 then
      (if _byte(data, name_offset) = 105 then
        (if _byte(data, name_offset + 1) = 100 then @(value_offset, value_len) else _id_of(data, rest))
       else _id_of(data, rest))
    else _id_of(data, rest)

(* ============================================================
   Writing
   ============================================================ *)

(* A byte at buf[at]; at is bn + 1 once the buffer was full, and stays so *)
fn _put {bl:agz}{bn:pos}{at:nat | at <= bn + 1}
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, value: [v:nat | v < 256] int v): [next:nat | next <= bn + 1] int next =
  if at < cap then let val () = $A.write_byte(buf, at, value) in at + 1 end
  else cap + 1

fn _put_number {bl:agz}{bn:pos}{at:nat | at <= bn + 1}
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, value: Nat): [next:nat | next <= bn + 1] int next =
  if at + 11 <= cap then $S.int_to_str(buf, at, cap, value) else cap + 1

(* '^' before each of [ ] ( ) , ; = and ^ *)
fn _is_special (c: int): bool =
  c = 91 || c = 93 || c = 40 || c = 41 || c = 44 || c = 59 || c = 61 || c = 94

fun _put_value {l:agz}{n:pos}{bl:agz}{bn:pos}{offset,value_len:nat | offset + value_len <= n}{at:nat | at <= bn + 1}{i:nat | i <= value_len} .<value_len - i>.
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, data: !$A.borrow(byte, l, n), offset: int offset, value_len: int value_len, i: int i)
  : [next:nat | next <= bn + 1] int next =
  if i >= value_len then at
  else let
    val c = _byte(data, offset + i)
    val at2 = (if _is_special(c) then _put(buf, cap, at, 94) else at): [a:nat | a <= bn + 1] int a
    val at3 = _put(buf, cap, at2, $AR.low_byte(c))
  in _put_value(buf, cap, at3, data, offset, value_len, i + 1) end

(* "[id]" for an element that has an id *)
fn _put_assertion {l:agz}{n:pos}{bl:agz}{bn:pos}{size:nat}{at:nat | at <= bn + 1}
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, size))
  : [next:nat | next <= bn + 1] int next = let
  val @(value_offset, value_len) = _id_of(data, attrs)
in
  if value_len <= 0 then at
  else let
    val at1 = _put(buf, cap, at, 91)
    val at2 = _put_value(buf, cap, at1, data, value_offset, value_len, 0)
  in _put(buf, cap, at2, 93) end
end

(* ============================================================
   cfi_of: the steps to a position
   ============================================================ *)

(* The steps to byte position in the children nodes of an element: the
   child that starts last at or before the position is the one it is in.
   elements are the elements passed, chunk_units the units of the text
   since the last of them (the text between two elements is one chunk,
   though a comment may have split it in the tree). Returns where the
   writing ended in buf, -1 when the position is in no text and is no
   element's name. *)
fun _of_list {l:agz}{n:pos}{bl:agz}{bn:pos}{size:nat}{position,elements:nat}{at:nat | at <= bn + 1} .<size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), position: int position, elements: int elements, chunk_units: Nat,
   buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at): [next:int | ~1 <= next; next <= bn + 1] int next =
  case+ nodes of
  | $X.xml_nodes_nil() => ~1
  | $X.xml_nodes_cons(node, rest) =>
    if _start_of(node) > position then ~1
    else if _starts_by(rest, position) then
      (case+ node of
       | $X.xml_text(offset, text_len) =>
         _of_list(data, rest, position, elements, chunk_units + _units(data, offset + text_len, offset + text_len, offset, 0), buf, cap, at)
       | $X.xml_element(_, _, _, _) => _of_list(data, rest, position, elements + 1, 0, buf, cap, at))
    else _of_node(data, node, position, elements, chunk_units, buf, cap, at)

and _of_node {l:agz}{n:pos}{bl:agz}{bn:pos}{size:pos}{position,elements:nat}{at:nat | at <= bn + 1} .<size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, size), position: int position, elements: int elements, chunk_units: Nat,
   buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at): [next:int | ~1 <= next; next <= bn + 1] int next =
  case+ node of
  | $X.xml_text(offset, text_len) =>
    if position > offset + text_len then ~1
    else let
      val at1 = _put(buf, cap, at, 47)
      val at2 = _put_number(buf, cap, at1, 2 * elements + 1)
      val at3 = _put(buf, cap, at2, 58)
    in _put_number(buf, cap, at3, chunk_units + _units(data, offset + text_len, position, offset, 0)) end
  | $X.xml_element(name_offset, _, attrs, children) =>
    if position < name_offset then ~1
    else let
      val at1 = _put(buf, cap, at, 47)
      val at2 = _put_number(buf, cap, at1, 2 * (elements + 1))
      val at3 = _put_assertion(buf, cap, at2, data, attrs)
    in
      if position = name_offset then at3
      else _of_list(data, children, position, 0, 0, buf, cap, at3)
    end

(* The document element is the first element of the top level *)
fun _of_root {l:agz}{n:pos}{bl:agz}{bn:pos}{size:nat}{position:nat}{at:nat | at <= bn + 1} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), position: int position,
   buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at): [next:int | ~1 <= next; next <= bn + 1] int next =
  case+ nodes of
  | $X.xml_nodes_nil() => ~1
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(_, _) => _of_root(data, rest, position, buf, cap, at)
     | $X.xml_element(name_offset, _, _, children) =>
       if position = name_offset then at
       else if position > name_offset then _of_list(data, children, position, 0, 0, buf, cap, at)
       else ~1)

(* The steps (from the document element, "/4[body01]/10[para05]/3:10") to
   byte position in the chapter, written at buf[at, length); -1 when the
   position is no element's name and in no text, or the steps do not fit in
   cap bytes (keep 11 bytes of room: a number is written whole or not) *)
#pub fn cfi_of_at {l:agz}{n:pos}{size:nat}{bl:agz}{bn:pos}{at:nat | at <= bn}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), position: Nat,
   buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at): [length:int | ~1 <= length; length <= bn] int length

implement cfi_of_at (data, nodes, position, buf, cap, at) = let
  val next = _of_root(data, nodes, position, buf, cap, at)
in if next > cap then ~1 else next end

#pub fn cfi_of {l:agz}{n:pos}{size:nat}{bl:agz}{bn:pos}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), position: Nat,
   buf: !$A.arr(byte, bl, bn), cap: int bn): [length:int | ~1 <= length; length <= bn] int length

implement cfi_of (data, nodes, position, buf, cap) = cfi_of_at(data, nodes, position, buf, cap, 0)

(* ============================================================
   Reading the steps
   ============================================================ *)

(* The number whose digits start at c[at, until) (saturating at 10^8) and
   where its digits end *)
fun _number {cl:agz}{cn:pos}{until:nat | until <= cn}{at:nat | at <= until} .<until - at>.
  (cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at, value: Nat)
  : [stop:int | at <= stop; stop <= until] @(Nat, int stop) =
  if at >= until then @(value, at)
  else let val digit = _byte(cfi, at) in
    if digit < 48 then @(value, at)
    else if digit > 57 then @(value, at)
    else _number(cfi, until, at + 1, (if value < 100000000 then value * 10 + (digit - 48) else value))
  end

(* Just past the ']' that closes the assertion whose '[' is before at
   (a '^' escapes the byte after it), or until *)
fun _assertion_close {cl:agz}{cn:pos}{until:nat | until <= cn}{at:nat | at <= until} .<until - at>.
  (cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at): [stop:int | at <= stop; stop <= until] int stop =
  if at >= until then at
  else let val c = _byte(cfi, at) in
    if c = 94 then (if at + 1 < until then _assertion_close(cfi, until, at + 2) else until)
    else if c = 93 then at + 1
    else _assertion_close(cfi, until, at + 1)
  end

(* The end of an assertion's value that starts at at: its first ';' or ']'
   that is not escaped, or until *)
fun _value_end {cl:agz}{cn:pos}{until:nat | until <= cn}{at:nat | at <= until} .<until - at>.
  (cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at): [stop:int | at <= stop; stop <= until] int stop =
  if at >= until then at
  else let val c = _byte(cfi, at) in
    if c = 94 then (if at + 1 < until then _value_end(cfi, until, at + 2) else until)
    else if c = 59 || c = 93 then at
    else _value_end(cfi, until, at + 1)
  end

(* Whether the attribute value data[offset, offset + value_len) is the
   assertion's value cfi[at, until), '^' taken off *)
fun _same_value {l:agz}{n:pos}{cl:agz}{cn:pos}{offset,value_len:nat | offset + value_len <= n}{until:nat | until <= cn}{at:nat | at <= until}{k:nat | k <= value_len} .<until - at>.
  (data: !$A.borrow(byte, l, n), offset: int offset, value_len: int value_len, k: int k,
   cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at): bool =
  if at >= until then k = value_len
  else if k >= value_len then false
  else let
    val c = _byte(cfi, at)
  in
    if c = 94 then
      (if at + 1 < until then
        (if _byte(cfi, at + 1) = _byte(data, offset + k) then _same_value(data, offset, value_len, k + 1, cfi, until, at + 2) else false)
       else false)
    else if c = _byte(data, offset + k) then _same_value(data, offset, value_len, k + 1, cfi, until, at + 1)
    else false
  end

(* Position of text: the position after offset units into chunk chunk of
   the children nodes. WalkText and the byte position; WalkEmptyText and the
   element's name offset when the chunk is empty and the offset 0; else
   WalkNothing. elements are those passed, remaining the units still to go. *)
fun _in_chunk {l:agz}{n:pos}{size:nat}{chunk,elements:nat} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), chunk: int chunk, elements: int elements,
   remaining: Nat, self: Int): @(walk_kind, Int) =
  case+ nodes of
  | $X.xml_nodes_nil() => if elements = chunk then (if remaining = 0 then @(WalkEmptyText(), self) else @(WalkNothing(), 0)) else @(WalkNothing(), 0)
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(offset, text_len) =>
       if elements = chunk then let
         val total = _units(data, offset + text_len, offset + text_len, offset, 0)
       in
         if remaining <= total then @(WalkText(), _position_of_units(data, offset + text_len, offset, 0, remaining))
         else _in_chunk(data, rest, chunk, elements, remaining - total, self)
       end
       else _in_chunk(data, rest, chunk, elements, remaining, self)
     | $X.xml_element(_, _, _, _) =>
       if elements = chunk then (if remaining = 0 then @(WalkEmptyText(), self) else @(WalkNothing(), 0))
       else _in_chunk(data, rest, chunk, elements + 1, remaining, self))

(* The assertion that may start at cfi[at]: for a '[' at at, its value
   cfi[value_start, value_end) (up to a ';') and the place past its ']';
   else nothing, three times at *)
fn _assertion_at {cl:agz}{cn:pos}{until:nat | until <= cn}{at:nat | at <= until}
  (cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at)
  : [value_start,value_end,stop:int | at <= value_start; value_start <= value_end; value_end <= stop; stop <= until] @(int value_start, int value_end, int stop) =
  if at >= until then @(at, at, at)
  else if _byte(cfi, at) = 91 then let
    val stop = _assertion_close(cfi, until, at + 1)
    val value_end = _value_end(cfi, until, at + 1)
  in if value_end <= stop then @(at + 1, value_end, stop) else @(at + 1, stop, stop) end
  else @(at, at, at)

(* Whether element attrs has the id the assertion cfi[value_start, value_end) names *)
fn _has_id {l:agz}{n:pos}{cl:agz}{cn:pos}{size:nat}{until:nat | until <= cn}{value_start,value_end:nat | value_start <= value_end; value_end <= until}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, size), cfi: !$A.borrow(byte, cl, cn), until: int until,
   value_start: int value_start, value_end: int value_end): bool = let
  val @(value_offset, value_len) = _id_of(data, attrs)
in _same_value(data, value_offset, value_len, 0, cfi, value_end, value_start) end

(* Past the '^' at at and the byte it escapes *)
fn _skip_pair {stop:nat}{at:nat | at < stop} (stop: int stop, at: int at): [next:int | at < next; next <= stop] int next =
  if at + 1 < stop then at + 2 else stop

(* The offset ":" and its digits at cfi[at], else 0 *)
fn _offset_at {cl:agz}{cn:pos}{until:nat | until <= cn}{at:nat | at <= until}
  (cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at): Nat =
  if at >= until then 0
  else if _byte(cfi, at) = 58 then let val @(offset, _) = _number(cfi, until, at + 1, 0) in offset end
  else 0

(* The path cfi[at, until) from the element self, whose children are nodes.
   An [id] that is not the one of the element a step reaches is a result of
   WalkLookForId and the assertion's start, for cfi_resolve to look for. A step is "/" and a number, then "[id]" for an element or
   ":" and an offset, then "[before,after]" and "[;s=b]" for text, which
   are read and ignored. *)
fun _resolve_list {l:agz}{n:pos}{cl:agz}{cn:pos}{size:nat}{until:nat | until <= cn}{at:nat | at <= until} .<until - at, 3, size, 0>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), self: Int,
   cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at): @(walk_kind, Int) =
  if at >= until then @(WalkElement(), self)
  else let val c = _byte(cfi, at) in
    if c = 47 then let
      val @(step, stop1) = _number(cfi, until, at + 1, 0)
      val @(value_start, value_end, stop2) = _assertion_at(cfi, until, stop1)
    in
      if nmod(step, 2) = 0 && step >= 2 then
        _resolve_element(data, nodes, self, ndiv(step, 2), value_start, value_end, stop2, cfi, until, at)
      else _in_chunk(data, nodes, (if step >= 1 then ndiv(step - 1, 2) else 0): Nat, 0, _offset_at(cfi, until, stop2), self)
    end
    else if c = 33 then @(WalkNothing(), 0)
    else if c = 58 then @(WalkNothing(), 0)
    else @(WalkElement(), self)
  end

(* The element number index (counting from 1) of nodes, and the rest of
   the steps from it; the number just past the last is the virtual place
   after it *)
and _resolve_element {l:agz}{n:pos}{cl:agz}{cn:pos}{size:nat}{until:nat | until <= cn}{at:nat | at < until}{after:int | at < after; after <= until}{index:nat}{value_start,value_end:nat | value_start <= value_end; value_end <= after} .<until - at, 2, size, 0>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), self: Int, index: int index,
   value_start: int value_start, value_end: int value_end, after: int after, cfi: !$A.borrow(byte, cl, cn), until: int until, at: int at): @(walk_kind, Int) =
  case+ nodes of
  | $X.xml_nodes_nil() => if index = 1 then (if after >= until then @(WalkEmptyText(), self) else @(WalkNothing(), 0)) else @(WalkNothing(), 0)
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(_, _) => _resolve_element(data, rest, self, index, value_start, value_end, after, cfi, until, at)
     | $X.xml_element(name_offset, _, attrs, children) =>
       if index > 1 then _resolve_element(data, rest, self, index - 1, value_start, value_end, after, cfi, until, at)
       else if value_end <= value_start then _resolve_list(data, children, name_offset, cfi, until, after)
       else if _has_id(data, attrs, cfi, until, value_start, value_end) then _resolve_list(data, children, name_offset, cfi, until, after)
       else @(WalkLookForId(), value_start))

(* Whether a walk found something (a place or an id to look for) *)
fn _walk_found (kind: walk_kind): bool =
  case+ kind of
  | WalkElement() => true
  | WalkText() => true
  | WalkEmptyText() => true
  | WalkLookForId() => true
  | WalkNothing() => false

(* The first element of nodes, in document order and inside, whose id is
   the assertion cfi[value_start, value_end): the steps from it are
   cfi[after, until). A result of WalkLookForId is returned as it is: the steps
   after the element found have an id of their own to look for. *)
fun _find_id_list {l:agz}{n:pos}{cl:agz}{cn:pos}{size:nat}{until:nat | until <= cn}{after:nat | after <= until}{value_start,value_end:nat | value_start <= value_end; value_end <= after} .<size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size),
   cfi: !$A.borrow(byte, cl, cn), until: int until, after: int after, value_start: int value_start, value_end: int value_end): @(walk_kind, Int) =
  case+ nodes of
  | $X.xml_nodes_nil() => @(WalkNothing(), 0)
  | $X.xml_nodes_cons(node, rest) => let
      val found = _find_id_node(data, node, cfi, until, after, value_start, value_end)
    in
      if _walk_found(found.0) then found
      else _find_id_list(data, rest, cfi, until, after, value_start, value_end)
    end

and _find_id_node {l:agz}{n:pos}{cl:agz}{cn:pos}{size:pos}{until:nat | until <= cn}{after:nat | after <= until}{value_start,value_end:nat | value_start <= value_end; value_end <= after} .<size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, size),
   cfi: !$A.borrow(byte, cl, cn), until: int until, after: int after, value_start: int value_start, value_end: int value_end): @(walk_kind, Int) =
  case+ node of
  | $X.xml_text(_, _) => @(WalkNothing(), 0)
  | $X.xml_element(name_offset, _, attrs, children) =>
    if _has_id(data, attrs, cfi, until, value_start, value_end) then let
      val here = _resolve_list(data, children, name_offset, cfi, until, after)
    in
      if _walk_found(here.0) then here
      else _find_id_list(data, children, cfi, until, after, value_start, value_end)
    end
    else _find_id_list(data, children, cfi, until, after, value_start, value_end)

(* The first element of the top level is the document element: the steps
   start in it *)
fun _resolve_root {l:agz}{n:pos}{cl:agz}{cn:pos}{size:nat}{until:nat | until <= cn}{from:nat | from <= until} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size),
   cfi: !$A.borrow(byte, cl, cn), until: int until, from: int from): @(walk_kind, Int) =
  case+ nodes of
  | $X.xml_nodes_nil() => @(WalkNothing(), 0)
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(_, _) => _resolve_root(data, rest, cfi, until, from)
     | $X.xml_element(name_offset, _, _, children) => _resolve_list(data, children, name_offset, cfi, until, from))

(* A result of WalkLookForId looks for the id and goes on from there, again for
   each id that does not match; each time the steps are further on, so
   fuel (the length of the steps) is enough *)
fun _settle {l:agz}{n:pos}{cl:agz}{cn:pos}{size:nat}{until:nat | until <= cn}{fuel:nat} .<fuel>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), cfi: !$A.borrow(byte, cl, cn), until: int until,
   kind: walk_kind, place: Int, fuel: int fuel): cfi_place =
  case+ kind of
  | WalkElement() => CfiElement(place)
  | WalkText() => CfiText(place)
  | WalkEmptyText() => CfiEmptyText(place)
  | WalkNothing() => CfiNoPlace()
  | WalkLookForId() =>
    if fuel <= 0 then CfiNoPlace()
    else if place < 1 then CfiNoPlace()
    else if place > until then CfiNoPlace()
    else let
      val @(value_start, value_end, after) = _assertion_at(cfi, until, place - 1)
      val @(again_kind, again_place) = _find_id_list(data, nodes, cfi, until, after, value_start, value_end)
    in _settle(data, nodes, cfi, until, again_kind, again_place, fuel - 1) end

(* The position of the steps cfi[from, until) in the chapter (a "!"
   before from is the caller's: cfi_split): CfiElement and an element's name
   offset, CfiText and a byte position in text, CfiEmptyText and the name offset
   of the element when the steps point at no text of it, CfiNoPlace when
   they point at nothing (no such step, an offset past the text, an
   indirection or an offset on an element). An [id] that is not the one of
   the element its step reaches is looked for in the chapter, and the
   steps after it go on from the element found. Text assertions, side
   bias and spatial or temporal offsets are not used to find the place. *)
#pub fn cfi_resolve {l:agz}{n:pos}{cl:agz}{cn:pos}{size:nat}{until:nat | until <= cn}{from:nat | from <= until}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), cfi: !$A.borrow(byte, cl, cn), until: int until, from: int from): cfi_place

implement cfi_resolve (data, nodes, cfi, until, from) =
  let val @(kind, place) = _resolve_root(data, nodes, cfi, until, from) in _settle(data, nodes, cfi, until, kind, place, until) end

(* ============================================================
   The whole identifier: wrapper, spine step, ranges
   ============================================================ *)

(* Text t at buf[at..) *)
fun _put_text {bl:agz}{bn:pos}{m:nat}{at:nat | at <= bn + 1}{i:nat | i <= m} .<m - i>.
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, text: string m, m: int m, i: int i): [next:nat | next <= bn + 1] int next =
  if i >= m then at
  else _put_text(buf, cap, _put(buf, cap, at, $AR.byte_of_char(string_get_at(text, i))), text, m, i + 1)

(* "/6/", the spine item's step 2 * (index + 1), its idref as an
   assertion when it has one (idref data[offset, offset + idref_len)), and
   "!": the part of a CFI that names the chapter. The package holds the
   idref and the index (the spine is its third child: metadata, manifest,
   spine, as EPUB's package document orders them). -1 when it does not fit. *)
(* "[idref]" unless it is empty *)
fn _put_idref {bl:agz}{bn:pos}{l:agz}{n:pos}{offset,idref_len:nat | offset + idref_len <= n}{at:nat | at <= bn + 1}
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, idref: !$A.borrow(byte, l, n), offset: int offset, idref_len: int idref_len)
  : [next:nat | next <= bn + 1] int next =
  if idref_len <= 0 then at
  else let
    val at_open = _put(buf, cap, at, 91)
    val at_value = _put_value(buf, cap, at_open, idref, offset, idref_len, 0)
  in _put(buf, cap, at_value, 93) end

#pub fn cfi_put_spine {bl:agz}{bn:pos}{l:agz}{n:pos}{offset,idref_len:nat | offset + idref_len <= n}{at:nat | at <= bn}
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, index: Nat, idref: !$A.borrow(byte, l, n), offset: int offset, idref_len: int idref_len)
  : [next:int | ~1 <= next; next <= bn] int next

implement cfi_put_spine (buf, cap, at, index, idref, offset, idref_len) = let
  val at1 = _put_text(buf, cap, at, "/6/", 3, 0)
  val at2 = _put_number(buf, cap, at1, 2 * (index + 1))
  val at3 = _put_idref(buf, cap, at2, idref, offset, idref_len)
  val at4 = _put(buf, cap, at3, 33)
in if at4 > cap then ~1 else at4 end

(* "epubcfi(", the spine step, the steps to position and ")": the CFI of a
   place, written at buf[0, length); -1 when the position is nowhere or
   the identifier does not fit *)
#pub fn cfi_make {l:agz}{n:pos}{size:nat}{bl:agz}{bn:pos}{il:agz}{idref_size:pos}{offset,idref_len:nat | offset + idref_len <= idref_size}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), position: Nat, index: Nat,
   idref: !$A.borrow(byte, il, idref_size), offset: int offset, idref_len: int idref_len, buf: !$A.arr(byte, bl, bn), cap: int bn)
  : [length:int | ~1 <= length; length <= bn] int length

implement cfi_make (data, nodes, position, index, idref, offset, idref_len, buf, cap) = let
  val at1 = _put_text(buf, cap, 0, "epubcfi(", 8, 0)
in
  if at1 > cap then ~1
  else let
    val at2 = cfi_put_spine(buf, cap, at1, index, idref, offset, idref_len)
  in
    if at2 < 0 then ~1
    else let
      val at3 = cfi_of_at(data, nodes, position, buf, cap, at2)
    in
      if at3 < 0 then ~1
      else let val at4 = _put(buf, cap, at3, 41) in if at4 > cap then ~1 else at4 end
    end
  end
end

(* buf[at..) := source[from, until) *)
fun _put_array {bl:agz}{bn:pos}{sl:agz}{sn:pos}{until:nat | until <= sn}{at:nat | at <= bn + 1}{from:nat | from <= until} .<until - from>.
  (buf: !$A.arr(byte, bl, bn), cap: int bn, at: int at, source: !$A.arr(byte, sl, sn), until: int until, from: int from)
  : [next:nat | next <= bn + 1] int next =
  if from >= until then at
  else _put_array(buf, cap, _put(buf, cap, at, $AR.low_byte(byte2int0($A.get<byte>(source, from)))), source, until, from + 1)

(* How many bytes the two arrays share from the start, up to limit *)
fun _common {al:agz}{an:pos}{bl:agz}{bn:pos}{limit:nat | limit <= an; limit <= bn}{i:nat | i <= limit} .<limit - i>.
  (first: !$A.arr(byte, al, an), second: !$A.arr(byte, bl, bn), limit: int limit, i: int i): [stop:nat | i <= stop; stop <= limit] int stop =
  if i >= limit then i
  else if byte2int0($A.get<byte>(first, i)) = byte2int0($A.get<byte>(second, i)) then _common(first, second, limit, i + 1)
  else i

(* The last '/' of first[0, from) at or before from - 1, or 0 *)
fun _last_slash {al:agz}{an:pos}{from:nat | from <= an}{i:nat | i <= from} .<i>.
  (first: !$A.arr(byte, al, an), from: int from, i: int i): [stop:nat | stop <= from] int stop =
  if i <= 0 then 0
  else if byte2int0($A.get<byte>(first, i - 1)) = 47 then i - 1
  else _last_slash(first, from, i - 1)

(* "epubcfi(P,S,E)" for a selection from start to end in the chapter: P
   the spine step and the steps the two share, S the rest of the start's
   steps and E the rest of the end's (the specification's range, which
   is what Readium's annotations hold too, the wrapper and the spine step
   taken off). cap is at most 1048576 for the two paths made on the way;
   -1 as cfi_make. *)
#pub fn cfi_make_range {l:agz}{n:pos}{size:nat}{bl:agz}{bn:pos | bn <= 1048576}{il:agz}{idref_size:pos}{offset,idref_len:nat | offset + idref_len <= idref_size}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), start: Nat, finish: Nat, index: Nat,
   idref: !$A.borrow(byte, il, idref_size), offset: int offset, idref_len: int idref_len, buf: !$A.arr(byte, bl, bn), cap: int bn)
  : [length:int | ~1 <= length; length <= bn] int length

(* len, or 0 for -1 (a path that was not made) *)
fn _non_negative {len,cap:int | ~1 <= len; len <= cap; 0 <= cap} (len: int len, cap: int cap): [k:nat | k <= cap] int k =
  if len >= 0 then len else 0

fn _range_into {bl:agz}{bn:pos}{il:agz}{idref_size:pos}{sl:agz}{fl:agz}{offset,idref_len:nat | offset + idref_len <= idref_size}
  {start_len,finish_len:nat | start_len <= bn; finish_len <= bn}
  (buf: !$A.arr(byte, bl, bn), cap: int bn, index: Nat, idref: !$A.borrow(byte, il, idref_size), offset: int offset, idref_len: int idref_len,
   start_steps: !$A.arr(byte, sl, bn), start_len: int start_len, finish_steps: !$A.arr(byte, fl, bn), finish_len: int finish_len)
  : [length:int | ~1 <= length; length <= bn] int length = let
  val limit = (if start_len <= finish_len then start_len else finish_len): [m:nat | m <= start_len; m <= finish_len] int m
  val shared = _common(start_steps, finish_steps, limit, 0)
  (* the shared bytes end at a step when each of the two ends or goes on with '/' *)
  val at_step = (if shared >= start_len then true else byte2int0($A.get<byte>(start_steps, shared)) = 47)
  val at_step_finish = (if shared >= finish_len then true else byte2int0($A.get<byte>(finish_steps, shared)) = 47)
  val split = (if at_step && at_step_finish then shared else _last_slash(start_steps, start_len, shared)): Nat
  val split_start = (if split <= start_len then split else start_len): [s:nat | s <= start_len] int s
  val split_finish = (if split <= finish_len then split else finish_len): [s:nat | s <= finish_len] int s
  val at1 = _put_text(buf, cap, 0, "epubcfi(", 8, 0)
in
  if at1 > cap then ~1
  else let
    val at2 = cfi_put_spine(buf, cap, at1, index, idref, offset, idref_len)
  in
  if at2 < 0 then ~1
  else let
    val at3 = _put_array(buf, cap, at2, start_steps, split_start, 0)
    val at4 = _put(buf, cap, at3, 44)
    val at5 = _put_array(buf, cap, at4, start_steps, start_len, split_start)
    val at6 = _put(buf, cap, at5, 44)
    val at7 = _put_array(buf, cap, at6, finish_steps, finish_len, split_finish)
    val at8 = _put(buf, cap, at7, 41)
  in if at8 > cap then ~1 else at8 end
  end
end

implement cfi_make_range (data, nodes, start, finish, index, idref, offset, idref_len, buf, cap) = let
  val start_steps = $A.alloc<byte>(cap)
  val finish_steps = $A.alloc<byte>(cap)
  val start_len = cfi_of(data, nodes, start, start_steps, cap)
  val finish_len = cfi_of(data, nodes, finish, finish_steps, cap)
  val length = _range_into(buf, cap, index, idref, offset, idref_len, start_steps, _non_negative(start_len, cap), finish_steps, _non_negative(finish_len, cap))
  val length = (if start_len < 0 then ~1 else if finish_len < 0 then ~1 else length)
  val () = $A.free<byte>(start_steps)
  val () = $A.free<byte>(finish_steps)
in length end

(* ---------------- reading an identifier ---------------- *)

(* The steps inside "epubcfi(" and ")" (all of cfi[0, len) when it has no
   wrapper) as [start, stop) *)
#pub fn cfi_body {cl:agz}{cn:pos}{len:nat | len <= cn}
  (cfi: !$A.borrow(byte, cl, cn), len: int len): [start,stop:nat | start <= stop; stop <= len] @(int start, int stop)

implement cfi_body (cfi, len) =
  if len < 9 then @(0, len)
  else if _byte(cfi, 0) = 101 && _byte(cfi, 1) = 112 && _byte(cfi, 2) = 117 && _byte(cfi, 3) = 98
    && _byte(cfi, 4) = 99 && _byte(cfi, 5) = 102 && _byte(cfi, 6) = 105 && _byte(cfi, 7) = 40 then
    (if _byte(cfi, len - 1) = 41 then @(8, len - 1) else @(0, len))
  else @(0, len)

(* The spine item step of cfi[start, stop): "/6/N", an assertion and "!"
   give N (the item is N / 2 - 1 of the spine, counting from 0) and the
   place after the "!"; any other beginning gives CfiNotSpine and start *)
#pub fn cfi_spine {cl:agz}{cn:pos}{stop:nat | stop <= cn}{start:nat | start <= stop}
  (cfi: !$A.borrow(byte, cl, cn), start: int start, stop: int stop): [after:int | start <= after; after <= stop] @(cfi_spine_step, int after)

implement cfi_spine (cfi, start, stop) =
  if start + 3 > stop then @(CfiNotSpine(), start)
  else if _byte(cfi, start) <> 47 then @(CfiNotSpine(), start)
  else if _byte(cfi, start + 1) <> 54 then @(CfiNotSpine(), start)
  else if _byte(cfi, start + 2) <> 47 then @(CfiNotSpine(), start)
  else let
    val @(step, stop1) = _number(cfi, stop, start + 3, 0)
    val @(_, _, stop2) = _assertion_at(cfi, stop, stop1)
  in
    if stop2 < stop then (if _byte(cfi, stop2) = 33 then @(CfiSpineItem(step), stop2 + 1) else @(CfiNotSpine(), start)) else @(CfiNotSpine(), start)
  end

(* The two commas of "P,S,E" that are not in an assertion or escaped, as
   their places in cfi[start, stop); -1 for one that is not there *)
fun _commas {cl:agz}{cn:pos}{stop:nat | stop <= cn}{at:nat | at <= stop} .<stop - at>.
  (cfi: !$A.borrow(byte, cl, cn), stop: int stop, at: int at, first: Int): @(Int, Int) =
  if at >= stop then @(first, ~1)
  else let val c = _byte(cfi, at) in
    if c = 94 then _commas(cfi, stop, _skip_pair(stop, at), first)
    else if c = 91 then _commas(cfi, stop, _assertion_close(cfi, stop, at + 1), first)
    else if c = 44 then (if first < 0 then _commas(cfi, stop, at + 1, at) else @(first, at))
    else _commas(cfi, stop, at + 1, first)
  end

(* cfi[from, until) is copied to joined[at..) *)
fun _copy_into {jl:agz}{jn:pos}{cl:agz}{cn:pos}{until:nat | until <= cn}{at:nat | at <= jn}{from:nat | from <= until} .<until - from>.
  (joined: !$A.arr(byte, jl, jn), size: int jn, at: int at, cfi: !$A.borrow(byte, cl, cn), until: int until, from: int from): [next:nat | next <= jn] int next =
  if from >= until then at
  else if at >= size then at
  else let val () = $A.write_byte(joined, at, _byte(cfi, from)) in _copy_into(joined, size, at + 1, cfi, until, from + 1) end

(* The place of the steps of cfi[first_lo, first_hi) and then cfi[second_lo, second_hi) joined *)
fn _resolve_joined {l:agz}{n:pos}{size:nat}{cl:agz}{cn:pos}{len:pos | len <= cn; len <= 1048576}{first_lo,first_hi,second_lo,second_hi:nat | first_lo <= first_hi; first_hi <= len; second_lo <= second_hi; second_hi <= len}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), cfi: !$A.borrow(byte, cl, cn), len: int len,
   first_lo: int first_lo, first_hi: int first_hi, second_lo: int second_lo, second_hi: int second_hi): cfi_place = let
  val joined = $A.alloc<byte>(len)
  val first_end = _copy_into(joined, len, 0, cfi, first_hi, first_lo)
  val joined_len = _copy_into(joined, len, first_end, cfi, second_hi, second_lo)
  val @(joined_frozen, joined_bytes) = $A.freeze<byte>(joined)
  val @(spine, after) = cfi_spine(joined_bytes, 0, joined_len)
  val () = (case+ spine of ~CfiSpineItem(_) => () | ~CfiNotSpine() => ())
  val found = cfi_resolve(data, nodes, joined_bytes, joined_len, after)
  val () = $A.drop<byte>(joined_frozen, joined_bytes)
  val () = $A.free<byte>($A.thaw<byte>(joined_frozen))
in found end

(* A place as both ends of a range *)
fn _twice (place: cfi_place): @(cfi_place, cfi_place) =
  case+ place of
  | ~CfiElement(offset) => @(CfiElement(offset), CfiElement(offset))
  | ~CfiText(offset) => @(CfiText(offset), CfiText(offset))
  | ~CfiEmptyText(offset) => @(CfiEmptyText(offset), CfiEmptyText(offset))
  | ~CfiNoPlace() => @(CfiNoPlace(), CfiNoPlace())

(* The places of a CFI in the chapter its spine step names (the caller
   found the chapter by cfi_spine): the start and the end of a range
   "P,S,E" as a cfi_place each (cfi_resolve's), or twice the place of
   a CFI that is not a range. A CFI over 1048576 bytes is not read. *)
#pub fn cfi_resolve_range {l:agz}{n:pos}{size:nat}{cl:agz}{cn:pos}{len:pos | len <= cn}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), cfi: !$A.borrow(byte, cl, cn), len: int len): @(cfi_place, cfi_place)

implement cfi_resolve_range (data, nodes, cfi, len) =
  if len > 1048576 then @(CfiNoPlace(), CfiNoPlace())
  else let
    val @(start, stop) = cfi_body(cfi, len)
    val @(first, second) = _commas(cfi, stop, start, ~1)
  in
    if first < start then let
      val only = _resolve_joined(data, nodes, cfi, len, start, stop, stop, stop)
    in _twice(only) end
    else if second <= first then @(CfiNoPlace(), CfiNoPlace())
    else if second >= stop then @(CfiNoPlace(), CfiNoPlace())
    else let
      val start_place = _resolve_joined(data, nodes, cfi, len, start, first, first + 1, second)
      val finish_place = _resolve_joined(data, nodes, cfi, len, start, first, second + 1, stop)
    in @(start_place, finish_place) end
  end

(* ---------------- the text assertion and the side bias ---------------- *)

(* Index of the '[' of the assertion that follows the offset ":N" in
   cfi[at, stop), or -1; after_offset says the last thing read was one *)
fun _terminal {cl:agz}{cn:pos}{stop:nat | stop <= cn}{at:nat | at <= stop} .<stop - at>.
  (cfi: !$A.borrow(byte, cl, cn), stop: int stop, at: int at, after_offset: bool): [found:int | ~1 <= found; found < stop] int found =
  if at >= stop then ~1
  else let val c = _byte(cfi, at) in
    if c = 94 then _terminal(cfi, stop, _skip_pair(stop, at), false)
    else if c = 91 then
      (if after_offset then at else _terminal(cfi, stop, _assertion_close(cfi, stop, at + 1), false))
    else if c = 58 then let val @(_, digits_end) = _number(cfi, stop, at + 1, 0) in _terminal(cfi, stop, digits_end, true) end
    else _terminal(cfi, stop, at + 1, false)
  end

(* The first unescaped ',' of cfi[at, stop), or -1 *)
fun _comma_in {cl:agz}{cn:pos}{stop:nat | stop <= cn}{at:nat | at <= stop} .<stop - at>.
  (cfi: !$A.borrow(byte, cl, cn), stop: int stop, at: int at): [found:int | ~1 <= found; found < stop] int found =
  if at >= stop then ~1
  else let val c = _byte(cfi, at) in
    if c = 94 then _comma_in(cfi, stop, _skip_pair(stop, at))
    else if c = 44 then at
    else _comma_in(cfi, stop, at + 1)
  end

(* The text assertion and the side bias at the end of cfi[start, stop), such as
   "[xx,y]" and "[;s=b]" after ":3" (read and kept, never made): the side bias
   (CfiSideNone, CfiSideBefore for "s=b", CfiSideAfter for "s=a"), and the text before
   and after the location as [before_lo, before_hi) and [after_lo,
   after_hi) of cfi (escapes "^" still in); the spans of what is not
   there are empty, at the start *)
#pub fn cfi_terminal {cl:agz}{cn:pos}{stop:nat | stop <= cn}{start:nat | start <= stop}
  (cfi: !$A.borrow(byte, cl, cn), start: int start, stop: int stop)
  : [before_lo,before_hi,after_lo,after_hi:int | start <= before_lo; before_lo <= before_hi; before_hi <= stop; start <= after_lo; after_lo <= after_hi; after_hi <= stop]
    @(cfi_side, int before_lo, int before_hi, int after_lo, int after_hi)

implement cfi_terminal (cfi, start, stop) = let
  val open_at = _terminal(cfi, stop, start, false)
in
  if open_at < start then @(CfiSideNone(), start, start, start, start)
  else if open_at >= stop then @(CfiSideNone(), start, start, start, start)
  else let
    val value_start = open_at + 1
    val close = _assertion_close(cfi, stop, value_start)
    val text_end = _value_end(cfi, stop, value_start)
    val comma = _comma_in(cfi, text_end, value_start)
    val params = text_end + 1
    val side = (if params + 2 < close then
        (if _byte(cfi, params) = 115 then
          (if _byte(cfi, params + 1) = 61 then
            (if _byte(cfi, params + 2) = 98 then CfiSideBefore() else if _byte(cfi, params + 2) = 97 then CfiSideAfter() else CfiSideNone())
           else CfiSideNone())
         else CfiSideNone())
      else CfiSideNone()): cfi_side
  in
    if comma >= value_start then @(side, value_start, comma, comma + 1, text_end)
    else @(side, value_start, text_end, start, start)
  end
end
