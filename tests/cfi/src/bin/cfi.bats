#target native

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use file as F
#use result as R
#use xml-tree as X

staload "xhtml_parse.sats"
staload "cfi.sats"

(* What the CFI module does that its types cannot say: the spec's own
   examples, the steps of every position of generated chapters against a
   generator that knows them, and the way back (keyword cfi, #901). *)

val _failures = ref<int>(0)

fn fail (what: string): void = let
  val () = println! ("FAIL ", what)
in !_failures := !_failures + 1 end

fn expect (ok: bool, what: string): void = if ok then () else fail(what)

(* ---------------- the places cfi_resolve answers ---------------- *)

(* What a check expects of a place; place_parts matches every constructor of
   cfi_place (case+), so a constructor added to it fails here *)
datatype place_kind = ElementKind | TextKind | EmptyTextKind | NoPlaceKind

fn place_parts (place: cfi_place): @(place_kind, Int) =
  case+ place of
  | ~CfiElement(offset) => @(ElementKind(), offset)
  | ~CfiText(offset) => @(TextKind(), offset)
  | ~CfiEmptyText(offset) => @(EmptyTextKind(), offset)
  | ~CfiNoPlace() => @(NoPlaceKind(), 0)

fn same_kind (found: place_kind, wanted: place_kind): bool =
  case+ found of
  | ElementKind() => (case+ wanted of | ElementKind() => true | TextKind() => false | EmptyTextKind() => false | NoPlaceKind() => false)
  | TextKind() => (case+ wanted of | ElementKind() => false | TextKind() => true | EmptyTextKind() => false | NoPlaceKind() => false)
  | EmptyTextKind() => (case+ wanted of | ElementKind() => false | TextKind() => false | EmptyTextKind() => true | NoPlaceKind() => false)
  | NoPlaceKind() => (case+ wanted of | ElementKind() => false | TextKind() => false | EmptyTextKind() => false | NoPlaceKind() => true)

fn is_no_place (kind: place_kind): bool = same_kind(kind, NoPlaceKind())
fn is_element (kind: place_kind): bool = same_kind(kind, ElementKind())
fn is_text (kind: place_kind): bool = same_kind(kind, TextKind())

(* What a check expects of a writer's answer; written_parts matches every
   constructor of cfi_written (case+), so a constructor added to it fails here *)
datatype written_kind = WrittenKind | NowhereKind | NoRoomKind

fn written_parts {bn:nat} (written: cfi_written(bn)): [length:nat | length <= bn] @(written_kind, int length) =
  case+ written of
  | ~CfiWritten(length) => @(WrittenKind(), length)
  | ~CfiNowhere() => @(NowhereKind(), 0)
  | ~CfiNoRoom() => @(NoRoomKind(), 0)

fn is_written (kind: written_kind): bool =
  case+ kind of | WrittenKind() => true | NowhereKind() => false | NoRoomKind() => false
fn is_nowhere (kind: written_kind): bool =
  case+ kind of | WrittenKind() => false | NowhereKind() => true | NoRoomKind() => false
fn is_no_room (kind: written_kind): bool =
  case+ kind of | WrittenKind() => false | NowhereKind() => false | NoRoomKind() => true

(* What cfi_put_spine answered: the length, or none when it did not fit *)
fn spine_written_length {bn:nat} (written: cfi_spine_written(bn)): [length:nat | length <= bn] @(bool, int length) =
  case+ written of
  | ~CfiSpineWritten(length) => @(true, length)
  | ~CfiSpineNoRoom() => @(false, 0)

fn same_side (found: cfi_side, wanted: cfi_side): bool =
  case+ found of
  | CfiSideNone() => (case+ wanted of | CfiSideNone() => true | CfiSideBefore() => false | CfiSideAfter() => false)
  | CfiSideBefore() => (case+ wanted of | CfiSideNone() => false | CfiSideBefore() => true | CfiSideAfter() => false)
  | CfiSideAfter() => (case+ wanted of | CfiSideNone() => false | CfiSideBefore() => false | CfiSideAfter() => true)

(* ---------------- text as bytes ---------------- *)

fun fill_bytes {l:agz}{n:pos}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (target: !$A.arr(byte, l, n), text: string m, m: int m, i: int i): void =
  if i >= m then ()
  else let
    val () = $A.write_byte(target, i, $AR.byte_of_char(string_get_at(text, i)))
  in fill_bytes(target, text, m, i + 1) end

(* Whether target[0, m) is text *)
fun same_bytes {l:agz}{n:pos}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (target: !$A.arr(byte, l, n), text: string m, m: int m, i: int i): bool =
  if i >= m then true
  else if byte2int0($A.get<byte>(target, i)) = $AR.byte_of_char(string_get_at(text, i)) then same_bytes(target, text, m, i + 1)
  else false

(* Whether first[0, m) and second[0, m) are the same bytes *)
fun same_arrays {l:agz}{k:agz}{n:pos}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (first: !$A.arr(byte, l, n), second: !$A.arr(byte, k, n), m: int m, i: int i): bool =
  if i >= m then true
  else if byte2int0($A.get<byte>(first, i)) = byte2int0($A.get<byte>(second, i)) then same_arrays(first, second, m, i + 1)
  else false

(* The first position at or after from where text is in data[0, size), or -1 *)
fun find_text {l:agz}{n:pos}{m:pos}{from:nat | from <= n} .<n - from>.
  (data: !$A.borrow(byte, l, n), size: int n, text: string m, m: int m, from: int from): Int =
  if from >= size then ~1
  else if from + m > size then ~1
  else let
    fun matches {k:nat | k <= m} .<m - k>. (data: !$A.borrow(byte, l, n), k: int k): bool =
      if k >= m then true
      else if from + k >= size then false
      else if byte2int0($A.read<byte>(data, from + k)) = $AR.byte_of_char(string_get_at(text, k)) then matches(data, k + 1)
      else false
  in
    if matches(data, 0) then from else find_text(data, size, text, m, from + 1)
  end

(* ---------------- checks against a chapter ---------------- *)

(* The steps of position are text *)
fn check_of {l:agz}{n:pos}{size:nat}{m:nat | m <= 255}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), position: Int, text: string m, m: int m, what: string): void = let
  val buf = $A.alloc<byte>(256)
  val clamped = (if position >= 0 then position else 0): Nat
  val @(kind, length) = written_parts(cfi_of(data, nodes, clamped, buf, 256))
  val same = same_bytes(buf, text, m, 0)
  val () = expect(is_written(kind) && length = m, what)
  val () = (if length = m then expect(same, what) else ())
  val () = $A.free<byte>(buf)
in end

(* The steps text lead to kind and position *)
fn check_resolve {l:agz}{n:pos}{size:nat}{m:pos | m <= 255}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), text: string m, m: int m, kind: place_kind, position: Int, what: string): void = let
  val steps = $A.alloc<byte>(256)
  val () = fill_bytes(steps, text, m, 0)
  val @(steps_frozen, steps_bytes) = $A.freeze<byte>(steps)
  val @(found_kind, found_position) = place_parts(cfi_resolve(data, nodes, steps_bytes, m, 0))
  val () = expect(same_kind(found_kind, kind), what)
  val () = (if is_no_place(kind) then () else expect(found_position = position, what))
  val () = $A.drop<byte>(steps_frozen, steps_bytes)
  val () = $A.free<byte>($A.thaw<byte>(steps_frozen))
in end

(* ---------------- a chapter parsed for a check ---------------- *)

(* Text as a chapter in an array of 4096 bytes (the rest zero), parsed, the
   tree freed after the checks of the three that follow it *)
fn check_spine {l:agz}{n:pos}{size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), digits: Int, yyy: Int): void = let
  val idref = $A.alloc<byte>(16)
  val () = fill_bytes(idref, "chap01ref", 9, 0)
  val @(idref_frozen, idref_bytes) = $A.freeze<byte>(idref)
  val made = $A.alloc<byte>(256)
  val position = (if digits >= 0 then digits + 10 else 0): Nat
  val @(made_kind, length) = written_parts(cfi_make(data, nodes, position, 1, idref_bytes, 0, 9, made, 256))
  val () = expect(is_written(made_kind) && length = 51, "make: the length of the whole identifier")
  val whole = same_bytes(made, "epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:10)", 51, 0)
  val () = expect(whole, "make: epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:10)")
  val () = $A.free<byte>(made)
  (* a range: the second y of yyy through the digit 3, as the specification's own *)
  val range = $A.alloc<byte>(256)
  val range_start = (if yyy >= 0 then yyy + 1 else 0): Nat
  val range_end = (if digits >= 0 then digits + 4 else 0): Nat
  val @(range_kind, range_len) = written_parts(cfi_make_range(data, nodes, range_start, range_end, 1, idref_bytes, 0, 9, range, 256))
  val () = expect(is_written(range_kind) && range_len = 58, "range: the length")
  val range_same = same_bytes(range, "epubcfi(/6/4[chap01ref]!/4[body01]/10[para05],/2/1:1,/3:4)", 58, 0)
  val () = expect(range_same, "range: epubcfi(/6/4[chap01ref]!/4[body01]/10[para05],/2/1:1,/3:4)")
  val () = $A.free<byte>(range)
  (* the other two answers of each writer: a position that is nowhere, a buffer too small *)
  val small = $A.alloc<byte>(12)
  val @(small_kind, _) = written_parts(cfi_of(data, nodes, position, small, 12))
  val () = expect(is_no_room(small_kind), "of: the steps do not fit in 12 bytes")
  val @(small_make_kind, _) = written_parts(cfi_make(data, nodes, position, 1, idref_bytes, 0, 9, small, 12))
  val () = expect(is_no_room(small_make_kind), "make: the spine step does not fit in 12 bytes")
  val () = $A.free<byte>(small)
  val spine_buf = $A.alloc<byte>(8)
  val @(spine_fits, _) = spine_written_length(cfi_put_spine(spine_buf, 8, 0, 1, idref_bytes, 0, 9))
  val () = expect(not(spine_fits), "put_spine: the spine step does not fit in 8 bytes")
  val () = $A.free<byte>(spine_buf)
  val spine_room = $A.alloc<byte>(32)
  val @(spine_fits_room, spine_length) = spine_written_length(cfi_put_spine(spine_room, 32, 0, 1, idref_bytes, 0, 9))
  val () = expect(spine_fits_room && spine_length = 16, "put_spine: /6/4[chap01ref]! is 16 bytes")
  val () = $A.free<byte>(spine_room)
  val tight = $A.alloc<byte>(24)
  val @(tight_kind, _) = written_parts(cfi_make(data, nodes, position, 1, idref_bytes, 0, 9, tight, 24))
  val () = expect(is_no_room(tight_kind), "make: the identifier does not fit in 24 bytes")
  val roomy = $A.alloc<byte>(256)
  val @(nowhere_kind, _) = written_parts(cfi_make(data, nodes, 4090, 1, idref_bytes, 0, 9, roomy, 256))
  val () = expect(is_nowhere(nowhere_kind), "make: a position past the chapter is nowhere")
  val @(range_nowhere_kind, _) = written_parts(cfi_make_range(data, nodes, 4090, range_end, 1, idref_bytes, 0, 9, roomy, 256))
  val () = expect(is_nowhere(range_nowhere_kind), "range: a start past the chapter is nowhere")
  val @(range_nowhere_end_kind, _) = written_parts(cfi_make_range(data, nodes, range_start, 4090, 1, idref_bytes, 0, 9, roomy, 256))
  val () = expect(is_nowhere(range_nowhere_end_kind), "range: an end past the chapter is nowhere")
  val @(range_tight_kind, _) = written_parts(cfi_make_range(data, nodes, range_start, range_end, 1, idref_bytes, 0, 9, tight, 24))
  val () = expect(is_no_room(range_tight_kind), "range: the range does not fit in 24 bytes")
  val () = $A.free<byte>(roomy)
  val () = $A.free<byte>(tight)
  val () = $A.drop<byte>(idref_frozen, idref_bytes)
  val () = $A.free<byte>($A.thaw<byte>(idref_frozen))
in end

(* The places of the identifier text, a range or one place *)
fn check_range {l:agz}{n:pos}{size:nat}{m:pos | m <= 255}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), text: string m, m: int m,
   start_kind: place_kind, start: Int, finish_kind: place_kind, finish: Int, what: string): void = let
  val steps = $A.alloc<byte>(256)
  val () = fill_bytes(steps, text, m, 0)
  val @(steps_frozen, steps_bytes) = $A.freeze<byte>(steps)
  val @(found_start_place, found_finish_place) = cfi_resolve_range(data, nodes, steps_bytes, m)
  val @(found_start_kind, found_start) = place_parts(found_start_place)
  val @(found_finish_kind, found_finish) = place_parts(found_finish_place)
  val () = expect(same_kind(found_start_kind, start_kind), what)
  val () = expect(found_start = start, what)
  val () = expect(same_kind(found_finish_kind, finish_kind), what)
  val () = expect(found_finish = finish, what)
  val () = $A.drop<byte>(steps_frozen, steps_bytes)
  val () = $A.free<byte>($A.thaw<byte>(steps_frozen))
in end

(* cfi_body, cfi_spine and cfi_terminal on text *)
fn check_parts {m:pos | m <= 255}
  (text: string m, m: int m, body_start: Int, body_stop: Int, spine_is_item: bool, spine_item: Int, side: cfi_side, what: string): void = let
  val steps = $A.alloc<byte>(256)
  val () = fill_bytes(steps, text, m, 0)
  val @(steps_frozen, steps_bytes) = $A.freeze<byte>(steps)
  val @(start, stop) = cfi_body(steps_bytes, m)
  val () = expect(start = body_start, what)
  val () = expect(stop = body_stop, what)
  val @(step, _) = cfi_spine(steps_bytes, start, stop)
  val @(found_is_item, found_item) = (case+ step of
    | ~CfiSpineItem(item) => @(true, item)
    | ~CfiNotSpine() => @(false, 0)): @(bool, Int)
  val () = expect(found_is_item = spine_is_item, what)
  val () = (if spine_is_item then expect(found_item = spine_item, what) else ())
  val @(found_side, _, _, _, _) = cfi_terminal(steps_bytes, start, stop)
  val () = expect(same_side(found_side, side), what)
  val () = $A.drop<byte>(steps_frozen, steps_bytes)
  val () = $A.free<byte>($A.thaw<byte>(steps_frozen))
in end

(* The spans cfi_terminal gives for the text assertion of text are before and after *)
fn check_assertion {m:pos | m <= 255}{b,a:nat | b <= 8; a <= 8}
  (text: string m, m: int m, before: string b, b: int b, after: string a, a: int a, what: string): void = let
  val steps = $A.alloc<byte>(256)
  val () = fill_bytes(steps, text, m, 0)
  val @(steps_frozen, steps_bytes) = $A.freeze<byte>(steps)
  val @(start, stop) = cfi_body(steps_bytes, m)
  val @(_, before_lo, before_hi, after_lo, after_hi) = cfi_terminal(steps_bytes, start, stop)
  val () = expect(before_hi - before_lo = b, what)
  val () = expect(after_hi - after_lo = a, what)
  val () = $A.drop<byte>(steps_frozen, steps_bytes)
  val () = $A.free<byte>($A.thaw<byte>(steps_frozen))
in end

(* ---------------- every position of a chapter ---------------- *)

(* Every byte position of the chapter that has steps: the steps resolve to a
   place, and the steps of that place are the same (the place is the position
   itself in a chapter with no comment inside a text); how many there were is
   returned, with the failures in _failures *)
fun round_trip_all {l:agz}{n:pos}{size:nat}{position:nat | position <= n} .<n - position>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), size: int n, position: int position, count: Nat): Nat =
  if position >= size then count
  else let
    val made = $A.alloc<byte>(256)
    val @(made_kind, used) = written_parts(cfi_of(data, nodes, position, made, 256))
    val length_made = is_written(made_kind)
    val again = $A.alloc<byte>(256)
    val @(made_frozen, made_bytes) = $A.freeze<byte>(made)
    val @(kind, found) = place_parts(cfi_resolve(data, nodes, made_bytes, used, 0))
    val found_nat = (if found >= 0 then found else 0): Nat
    val @(again_kind, again_length) = written_parts(cfi_of(data, nodes, found_nat, again, 256))
    val () = $A.drop<byte>(made_frozen, made_bytes)
    val made_back = $A.thaw<byte>(made_frozen)
    val identical = same_arrays(made_back, again, used, 0)
    val lead = byte2int0($A.read<byte>(data, position))
    val inside_character = lead >= 128 && lead < 192
    val () = (if length_made then (expect(is_element(kind) || is_text(kind), "round trip: the steps resolve to a place");
                                   expect(inside_character || found = position, "round trip: the place is the position");
                                   expect(is_written(again_kind) && again_length = used, "round trip: the same length of steps");
                                   expect(identical, "round trip: the same steps")) else ())
    val () = $A.free<byte>(made_back)
    val () = $A.free<byte>(again)
  in round_trip_all(data, nodes, size, position + 1, (if length_made then count + 1 else count)) end

(* ---------------- the spec's chapter ---------------- *)

(* chapter01.xhtml of the specification (https://idpf.org/epub/linking/cfi/,
   "Examples"): <body id="body01">, its fifth element the paragraph
   para05, "xxx", <em>yyy</em>, "0123456789", and its eighth the image svgimg *)
#define SPEC_DOC "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>t</title></head><body id=\"body01\"><h1>a</h1><p>b</p><p>c</p><p>d</p><p id=\"para05\">xxx<em>yyy</em>0123456789</p><p>e</p><p>f</p><img id=\"svgimg\" src=\"x.png\"/></body></html>"

fn check_spec (): void = let
  val doc = $A.alloc<byte>(4096)
  val () = fill_bytes(doc, SPEC_DOC, 228, 0)
  val @(doc_frozen, data) = $A.freeze<byte>(doc)
  val nodes = xhtml_parse(data, 4096)
  val digits = find_text(data, 4096, "0123456789", 10, 0)
  val xxx = find_text(data, 4096, "xxx", 3, 0)
  val yyy = find_text(data, 4096, "yyy", 3, 0)
  val image = find_text(data, 4096, "img id", 6, 0)
  val body = find_text(data, 4096, "body id", 7, 0)
  val () = check_of(data, nodes, digits + 10, "/4[body01]/10[para05]/3:10", 26, "spec: right after the digit 9")
  val () = check_of(data, nodes, image, "/4[body01]/16[svgimg]", 21, "spec: the image")
  val () = check_of(data, nodes, xxx, "/4[body01]/10[para05]/1:0", 25, "spec: just before xxx")
  val () = check_of(data, nodes, yyy, "/4[body01]/10[para05]/2/1:0", 27, "spec: just before yyy")
  val () = check_of(data, nodes, yyy + 3, "/4[body01]/10[para05]/2/1:3", 27, "spec: just after yyy")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/3:10", 26, TextKind(), digits + 10, "spec: resolve the 9")
  val () = check_resolve(data, nodes, "/4[body01]/16[svgimg]", 21, ElementKind(), image, "spec: resolve the image")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/1:0", 25, TextKind(), xxx, "spec: resolve before xxx")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/2/1:0", 27, TextKind(), yyy, "spec: resolve before yyy")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/2/1:3", 27, TextKind(), yyy + 3, "spec: resolve after yyy")
  (* the ids correct a path: step 12 is not para05, the id is *)
  val () = check_resolve(data, nodes, "/4[body01]/12[para05]/3:10", 26, TextKind(), digits + 10, "an id that is not where the step says is looked for")
  val () = check_resolve(data, nodes, "/4[body01]/12[nowhere]/3:10", 27, NoPlaceKind(), 0, "an id that is nowhere is no place")
  val () = check_resolve(data, nodes, "/4[bogus]/10[para05]/3:10", 25, NoPlaceKind(), 0, "an id nowhere in the chapter is a place of another version of it, no place")
  (* a step past the elements, and the chunk of no text *)
  val () = check_resolve(data, nodes, "/4[body01]/18", 13, EmptyTextKind(), body, "the step after the last element is a place in the body")
  val () = check_resolve(data, nodes, "/4[body01]/20", 13, NoPlaceKind(), 0, "two past the last element is nothing")
  val () = check_resolve(data, nodes, "/4[body01]/1:0", 14, EmptyTextKind(), body, "an empty first chunk")
  val () = check_resolve(data, nodes, "/4[body01]/1:1", 14, NoPlaceKind(), 0, "an offset into an empty chunk")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/3:11", 26, NoPlaceKind(), 0, "an offset past the end of the text")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/3:0", 25, TextKind(), digits, "the start of a text")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/0", 23, TextKind(), xxx, "the virtual step 0")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]!/4", 24, NoPlaceKind(), 0, "an indirection inside the chapter")
  val () = check_resolve(data, nodes, "/4[body01]/10:3", 15, NoPlaceKind(), 0, "an offset on an element")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/3:4[012,456;s=a]", 38, TextKind(), digits + 4, "assertions and side bias are not used to find the place")
  val () = check_resolve(data, nodes, "/4[body01]/10[para05]/2/1:3[;s=b]", 33, TextKind(), yyy + 3, "side bias after an offset")
  val () = check_resolve(data, nodes, "/4[body01]/16[svgimg]~23.5@97.6", 31, ElementKind(), image, "a temporal and spatial offset after an element")
  val () = check_resolve(data, nodes, "/6/4[chap01ref]!/4", 18, NoPlaceKind(), 0, "the spine step is not the chapter's steps")
  val () = check_spine(data, nodes, digits, yyy)
  val () = check_range(data, nodes, "epubcfi(/6/4[chap01ref]!/4[body01]/10[para05],/2/1:1,/3:4)", 58, TextKind(), yyy + 1, TextKind(), digits + 4, "the specification's range")
  val () = check_range(data, nodes, "epubcfi(/6/4[chap01ref]!/4[body01]/10[para05],/3:4)", 51, NoPlaceKind(), 0, NoPlaceKind(), 0, "one comma is not a range")
  val () = check_range(data, nodes, "epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:10)", 51, TextKind(), digits + 10, TextKind(), digits + 10, "one place is both ends")
  val () = check_range(data, nodes, "epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/2,/1:1,/1:2)", 58, TextKind(), yyy + 1, TextKind(), yyy + 2, "a range inside one element")
  val () = check_parts("epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:10)", 51, 8, 50, true, 4, CfiSideNone(), "the parts of an identifier")
  val () = check_parts("/4[body01]/10[para05]/2/1:3[;s=b]", 33, 0, 33, false, 0, CfiSideBefore(), "side bias before")
  val () = check_parts("/4[body01]/10[para05]/2/1:3[;s=a]", 33, 0, 33, false, 0, CfiSideAfter(), "side bias after")
  val () = check_parts("/4[body01]/10[para05]/3:4[012,456]", 34, 0, 34, false, 0, CfiSideNone(), "no side bias")
  val () = check_assertion("/4[body01]/10[para05]/3:4[012,456]", 34, "012", 3, "456", 3, "the text before and after")
  val spec_positions = round_trip_all(data, nodes, 4096, 0, 0)
  val () = expect(spec_positions > 40, "round trip: the specification's chapter has more than forty positions")
  val () = println! ("the specification's chapter: ", spec_positions, " positions round trip")
  val () = check_assertion("/4[body01]/10[para05]/3:4[,456]", 31, "", 0, "456", 3, "the text after only")
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, data)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in end

(* ---------------- a chapter of another reading system ---------------- *)

(* Whether data[at, at + m) is text *)
fun bytes_are {l:agz}{n:pos}{m:nat}{i:nat | i <= m} .<m - i>.
  (data: !$A.borrow(byte, l, n), size: int n, at: Int, text: string m, m: int m, i: int i): bool =
  if i >= m then true
  else if at + i < 0 then false
  else if at + i >= size then false
  else if byte2int0($A.read<byte>(data, at + i)) = $AR.byte_of_char(string_get_at(text, i)) then bytes_are(data, size, at, text, m, i + 1)
  else false

fn close_result (closed: $R.result(int, $F.io_error)): void =
  case+ closed of
  | ~$R.ok(_) => ()
  | ~$R.err(_) => ()

(* The file at path into doc (32768 bytes); the bytes read, 0 when it cannot be *)
fn load_file {l:agz}{m:pos | m < 1048576} (doc: !$A.arr(byte, l, 32768), path: string m, m: int m): Nat = let
  val name = $A.alloc<byte>(m)
  val () = fill_bytes(name, path, m, 0)
  val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
  val opened = $F.file_open(name_bytes, m, $F.ReadOnly(), $F.OpenExisting(), 0)
  val () = $A.drop<byte>(name_frozen, name_bytes)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in
  case+ opened of
  | ~$R.err(_) => 0
  | ~$R.ok(file) => let
      val read = $F.file_read(file, doc, 32768)
      val count = (case+ read of
        | ~$R.ok(k) => k
        | ~$R.err(_) => 0): Nat
      val () = close_result($F.file_close(file))
    in count end
end

(* epub.js's test/epubcfi.js asserts these CFIs for its chapter1.xhtml (the
   fixture is copied as tests/cfi/fixtures/epubjs-chapter1.xhtml): the
   span c001p0004 and the span c001p0007 *)
fn check_epubjs (): void = let
  val doc = $A.alloc<byte>(32768)
  val count = load_file(doc, "fixtures/epubjs-chapter1.xhtml", 30)
  val () = expect(count > 13000, "epub.js: the fixture was read")
  val @(doc_frozen, data) = $A.freeze<byte>(doc)
  val nodes = xhtml_parse(data, 32768)
  val first = find_text(data, 32768, "id=\"c001p0004\">", 15, 0)
  val second = find_text(data, 32768, "id=\"c001p0007\">", 15, 0)
  val first_span = find_text(data, 32768, "<span class=\"audio\" id=\"c001p0004\"", 34, 0)
  val first_text = first + 15
  val second_text = second + 15
  (* "epubcfi(/6/4[chap01ref]!/4/2/10/2[c001p0004]/1:6)": "But lo|ok! here" *)
  val () = check_resolve(data, nodes, "/4/2/10/2[c001p0004]/1:6", 24, TextKind(), first_text + 6, "epub.js: a collapsed range")
  val () = expect(bytes_are(data, 32768, first_text + 6, "ok! here", 8, 0), "epub.js: the text there is ok! here")
  val () = check_of(data, nodes, first_text + 6, "/4/2/10/2[c001p0004]/1:6", 24, "epub.js: the steps of a position in the span")
  (* fromNode: the element, and its text node (no offset) *)
  val () = check_resolve(data, nodes, "/4/2/10/2[c001p0004]", 20, ElementKind(), first_span + 1, "epub.js: the element")
  val () = check_of(data, nodes, first_span + 1, "/4/2/10/2[c001p0004]", 20, "epub.js: the steps of the element")
  val () = check_resolve(data, nodes, "/4/2/10/2[c001p0004]/1", 22, TextKind(), first_text, "epub.js: the text node without an offset")
  (* the range of #fromRange(): epubcfi(/6/4[chap01ref]!/4/2,/10/2[c001p0004]/1:6,/16/2[c001p0007]/1:27) *)
  val () = check_range(data, nodes, "epubcfi(/6/4[chap01ref]!/4/2,/10/2[c001p0004]/1:6,/16/2[c001p0007]/1:27)", 72, TextKind(), first_text + 6, TextKind(), second_text + 27, "epub.js: a range across two paragraphs")
  val idref = $A.alloc<byte>(16)
  val () = fill_bytes(idref, "chap01ref", 9, 0)
  val @(idref_frozen, idref_bytes) = $A.freeze<byte>(idref)
  val made = $A.alloc<byte>(256)
  val start_position = (if first >= 0 then first + 15 + 6 else 0): Nat
  val end_position = (if second >= 0 then second + 15 + 27 else 0): Nat
  val @(made_kind, length) = written_parts(cfi_make_range(data, nodes, start_position, end_position, 1, idref_bytes, 0, 9, made, 256))
  val same = same_bytes(made, "epubcfi(/6/4[chap01ref]!/4/2,/10/2[c001p0004]/1:6,/16/2[c001p0007]/1:27)", 72, 0)
  val () = expect(is_written(made_kind) && length = 72, "epub.js: the range made is the one epub.js makes (length)")
  val () = expect(same, "epub.js: the range made is the one epub.js makes")
  val () = $A.free<byte>(made)
  val () = $A.drop<byte>(idref_frozen, idref_bytes)
  val () = $A.free<byte>($A.thaw<byte>(idref_frozen))
  (* a range inside one paragraph, as epub.js writes it with offset 0: epubcfi(...10/2[c001p0004],/1:0,/1:1) *)
  val () = check_range(data, nodes, "epubcfi(/6/4[chap01ref]!/4/2/10/2[c001p0004],/1:0,/1:1)", 55, TextKind(), first_text, TextKind(), first_text + 1, "epub.js: a range with offset 0")
  val fixture_positions = round_trip_all(data, nodes, 32768, 0, 0)
  val () = expect(fixture_positions > 10000, "epub.js: more than ten thousand positions of the chapter have steps")
  val () = println! ("epub.js's chapter: ", fixture_positions, " positions round trip")
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, data)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in end

(* ---------------- generated chapters ---------------- *)

val _doc_len = ref<Nat>(0)
val _log_len = ref<Nat>(0)
val _path_len = ref<Nat>(0)
val _ids = ref<Nat>(0)
val _random = ref<[r:nat | r < 65536] int r>(1)

(* the counts of what the log held, for the summary *)
val _elements_checked = ref<Nat>(0)
val _text_checked = ref<Nat>(0)
val _after_comment_checked = ref<Nat>(0)
val _outside_checked = ref<Nat>(0)

(* a sixteen bit generator that visits every number (as the codec test's) *)
fn next_random (): [value:nat | value < 65536] int value = let
  val state = !_random
  val product = $AR.mul_g1(state, 25173)
  val next = $AR.band_g1($AR.add_g1(product, 13849), 65535)
  val () = !_random := next
in next end

fn choose {bound:pos} (bound: int bound): [chosen:nat | chosen < bound] int chosen = nmod(next_random(), bound)

fn emit {l:agz} (doc: !$A.arr(byte, l, 4096), value: Nat): void = let
  val at = !_doc_len
in
  if at < 4096 then let
    val () = $A.write_byte(doc, at, $AR.low_byte(value))
  in !_doc_len := at + 1 end
  else ()
end

fun emit_text {l:agz}{m:nat}{i:nat | i <= m} .<m - i>.
  (doc: !$A.arr(byte, l, 4096), text: string m, m: int m, i: int i): void =
  if i >= m then ()
  else let
    val () = emit(doc, $AR.byte_of_char(string_get_at(text, i)))
  in emit_text(doc, text, m, i + 1) end

fn log_byte {l:agz} (log: !$A.arr(byte, l, 32768), value: Nat): void = let
  val at = !_log_len
in
  if at < 32768 then let
    val () = $A.write_byte(log, at, $AR.low_byte(value))
  in !_log_len := at + 1 end
  else ()
end

(* value in decimal; value under 10^6 *)
fun log_digits {l:agz}{value:nat}{fuel:nat} .<fuel>.
  (log: !$A.arr(byte, l, 32768), value: int value, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if value < 10 then log_byte(log, 48 + value)
  else let
    val () = log_digits(log, ndiv(value, 10), fuel - 1)
  in log_byte(log, 48 + nmod(value, 10)) end

fn path_byte {l:agz} (path: !$A.arr(byte, l, 512), value: Nat): void = let
  val at = !_path_len
in
  if at < 512 then let
    val () = $A.write_byte(path, at, $AR.low_byte(value))
  in !_path_len := at + 1 end
  else ()
end

fun path_digits {l:agz}{value:nat}{fuel:nat} .<fuel>.
  (path: !$A.arr(byte, l, 512), value: int value, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if value < 10 then path_byte(path, 48 + value)
  else let
    val () = path_digits(path, ndiv(value, 10), fuel - 1)
  in path_byte(path, 48 + nmod(value, 10)) end

(* The path so far into the log *)
fun log_path {ll:agz}{lp:agz}{i:nat | i <= 512} .<512 - i>.
  (log: !$A.arr(byte, ll, 32768), path: !$A.arr(byte, lp, 512), i: int i): void =
  if i >= 512 then ()
  else if i >= !_path_len then ()
  else let
    val () = log_byte(log, $AR.low_byte(byte2int0($A.get<byte>(path, i))))
  in log_path(log, path, i + 1) end

(* An entry of the log: its kind, the position (two bytes), a byte for the
   length of the steps that follow, patched by log_end; where it starts *)
fn log_begin {ll:agz} (log: !$A.arr(byte, ll, 32768), kind: Nat, position: Nat): Nat = let
  val start = !_log_len
  val () = log_byte(log, kind)
  val () = log_byte(log, ndiv(position, 256))
  val () = log_byte(log, nmod(position, 256))
  val () = log_byte(log, 0)
in start end

fn log_end {ll:agz} (log: !$A.arr(byte, ll, 32768), start: Nat): void =
  if start + 3 < 32768 then
    (if !_log_len >= start + 4 then $A.write_byte(log, start + 3, $AR.low_byte(!_log_len - start - 4)) else ())
  else ()

(* the steps of the element at position: the path, which holds its own step *)
fn log_element {ll,lp:agz} (log: !$A.arr(byte, ll, 32768), path: !$A.arr(byte, lp, 512), position: Nat): void = let
  val start = log_begin(log, 1, position)
  val () = log_path(log, path, 0)
in log_end(log, start) end

(* a position in text: the path, the chunk (2 * elements + 1) and the units *)
fn log_text {ll,lp:agz} (log: !$A.arr(byte, ll, 32768), path: !$A.arr(byte, lp, 512), position: Nat, elements: Nat, units: Nat, after_comment: bool): void = let
  val start = log_begin(log, (if after_comment then 3 else 2), position)
  val () = log_path(log, path, 0)
  val () = log_byte(log, 47)
  val () = log_digits(log, 2 * elements + 1, 6)
  val () = log_byte(log, 58)
  val () = log_digits(log, units, 6)
in log_end(log, start) end

fn log_outside {ll:agz} (log: !$A.arr(byte, ll, 32768), position: Nat): void = let
  val start = log_begin(log, 9, position)
in log_end(log, start) end

(* step n of an element on the path, with its id when it has one *)
fn push_step {lp:agz} (path: !$A.arr(byte, lp, 512), step: Nat, id: Nat): void = let
  val () = path_byte(path, 47)
  val () = path_digits(path, step, 6)
in
  if id > 0 then let
    val () = path_byte(path, 91)
    val () = path_byte(path, 105)
    val () = path_digits(path, id, 6)
  in path_byte(path, 93) end
  else ()
end

(* the characters of a text, each a token: its bytes and its UTF-16 units *)
fn emit_token {l:agz} (doc: !$A.arr(byte, l, 4096), token: Nat): Nat =
  if token = 0 then let val () = emit(doc, 97) in 1 end
  else if token = 1 then let val () = emit(doc, 98) in 1 end
  else if token = 2 then let val () = emit(doc, 32) in 1 end
  else if token = 3 then let (* e acute, two bytes *)
    val () = emit(doc, 195)
    val () = emit(doc, 169)
  in 1 end
  else if token = 4 then let (* a character outside the BMP, four bytes and two units *)
    val () = emit(doc, 240)
    val () = emit(doc, 159)
    val () = emit(doc, 152)
    val () = emit(doc, 128)
  in 2 end
  else if token = 5 then let val () = emit_text(doc, "&amp;", 5, 0) in 1 end
  else if token = 6 then let val () = emit_text(doc, "&#x1F600;", 9, 0) in 2 end
  else if token = 7 then let val () = emit_text(doc, "&#233;", 6, 0) in 1 end
  else let val () = emit_text(doc, "&nosuch;", 8, 0) in 8 end

(* count tokens of text in the chunk of elements, after units: each place
   between two tokens is a position; the units after *)
fun gen_text {ld,ll,lp:agz}{count:nat} .<count>.
  (doc: !$A.arr(byte, ld, 4096), log: !$A.arr(byte, ll, 32768), path: !$A.arr(byte, lp, 512), count: int count, elements: Nat, units: Nat): Nat =
  if count <= 0 then units
  else let
    val units_after = units + emit_token(doc, choose(9))
    val () = log_text(log, path, !_doc_len, elements, units_after, false)
  in gen_text(doc, log, path, count - 1, elements, units_after) end

fn emit_name {l:agz} (doc: !$A.arr(byte, l, 4096), name: Nat): void =
  if name = 0 then emit(doc, 112)
  else if name = 1 then let val () = emit(doc, 101) in emit(doc, 109) end
  else if name = 2 then emit(doc, 98)
  else let
    val () = emit(doc, 115)
    val () = emit(doc, 112)
    val () = emit(doc, 97)
  in emit(doc, 110) end

(* count more things in an element at depth: text, elements, comments *)
fun gen_children {ld,ll,lp:agz}{depth,count:nat} .<depth, count>.
  (doc: !$A.arr(byte, ld, 4096), log: !$A.arr(byte, ll, 32768), path: !$A.arr(byte, lp, 512),
   depth: int depth, count: int count, elements: Nat, units: Nat, after_comment: bool): void =
  if count <= 0 then ()
  else if !_doc_len > 3000 then ()
  else let
    val which = choose(9)
  in
    if which <= 2 then let
      (* the first position of a text that follows a comment in a chunk that has text is kind 3 *)
      val () = log_text(log, path, !_doc_len, elements, units, (if units > 0 then after_comment else false))
      val units_after = gen_text(doc, log, path, 1 + choose(5), elements, units)
    in gen_children(doc, log, path, depth, count - 1, elements, units_after, false) end
    else if which <= 4 then
      (if depth >= 1 then let
        val () = gen_element(doc, log, path, depth - 1, elements)
       in gen_children(doc, log, path, depth, count - 1, elements + 1, 0, false) end
       else gen_children(doc, log, path, depth, count - 1, elements, units, after_comment))
    else if which = 5 then let
      val () = emit_text(doc, "<!--", 4, 0)
      val () = log_outside(log, !_doc_len)
      val () = emit_text(doc, "c-->", 4, 0)
    in gen_children(doc, log, path, depth, count - 1, elements, units, true) end
    else if which = 6 then let
      (* white space between elements is a chunk of its own *)
      val () = log_text(log, path, !_doc_len, elements, units, (if units > 0 then after_comment else false))
      val () = emit(doc, 10)
      val () = log_text(log, path, !_doc_len, elements, units + 1, false)
    in gen_children(doc, log, path, depth, count - 1, elements, units + 1, false) end
    else if which = 7 then let
      (* an element with no content *)
      val () = emit(doc, 60)
      val at = !_doc_len
      val () = emit_text(doc, "br/>", 4, 0)
      val saved = !_path_len
      val () = push_step(path, 2 * (elements + 1), 0)
      val () = log_element(log, path, at)
      val () = !_path_len := saved
    in gen_children(doc, log, path, depth, count - 1, elements + 1, 0, false) end
    else gen_children(doc, log, path, depth, count - 1, elements, units, after_comment)
  end

and gen_element {ld,ll,lp:agz}{depth:nat} .<depth, 10000>.
  (doc: !$A.arr(byte, ld, 4096), log: !$A.arr(byte, ll, 32768), path: !$A.arr(byte, lp, 512), depth: int depth, elements: Nat): void = let
  val name = choose(4)
  val id = (if choose(3) = 0 then 1 + choose(9) else 0): Nat
  val () = emit(doc, 60)
  val at = !_doc_len
  val () = emit_name(doc, name)
  val () = (if id > 0 then let
      val () = emit_text(doc, " id=\"i", 6, 0)
      val () = emit(doc, 48 + id)
    in emit(doc, 34) end else ())
  val () = log_outside(log, !_doc_len)
  val () = emit(doc, 62)
  val saved = !_path_len
  val () = push_step(path, 2 * (elements + 1), id)
  val () = log_element(log, path, at)
  val () = gen_children(doc, log, path, depth, 1 + choose(6), 0, 0, false)
  val () = emit(doc, 60)
  val () = log_outside(log, !_doc_len)
  val () = emit(doc, 47)
  val () = emit_name(doc, name)
  val () = emit(doc, 62)
  val () = !_path_len := saved
in end

(* ---------------- chapters built to a shape ---------------- *)

val _first_a = ref<Nat>(0)
val _first_b = ref<Nat>(0)
val _first_c = ref<Nat>(0)
val _first_d = ref<Nat>(0)
val _first_e = ref<Nat>(0)
val _first_f = ref<Nat>(0)

(* thirty-one characters, so that a place in them is told by its offset *)
fn emit_letters {l:agz} (doc: !$A.arr(byte, l, 4096)): void =
  emit_text(doc, "0123456789012345678901234567890", 31, 0)

(* item k (1 to 41) of the division of a chapter shaped as the one KOReader's
   highlight tests are made in (spec/unit/readerhighlight_spec.lua): the 37th
   holds, in a paragraph, text, <b>, text, <i>, text, each of 31 characters;
   the 38th, the 40th and the 41st hold one text of 31 characters in theirs; the
   others are small *)
fun emit_items {l:agz}{k:nat | k <= 42} .<42 - k>. (doc: !$A.arr(byte, l, 4096), k: int k): void =
  if k > 41 then ()
  else let
    val () = emit_text(doc, "<blockquote><p>", 15, 0)
    val () = (if k = 37 then let
        val () = !_first_a := !_doc_len
        val () = emit_letters(doc)
        val () = emit_text(doc, "<b>b</b>", 8, 0)
        val () = !_first_b := !_doc_len
        val () = emit_letters(doc)
        val () = emit_text(doc, "<i>i</i>", 8, 0)
        val () = !_first_c := !_doc_len
      in emit_letters(doc) end
      else if k = 38 then let val () = !_first_d := !_doc_len in emit_letters(doc) end
      else if k = 40 then let val () = !_first_e := !_doc_len in emit_letters(doc) end
      else if k = 41 then let val () = !_first_f := !_doc_len in emit_letters(doc) end
      else emit(doc, 120))
    val () = emit_text(doc, "</p></blockquote>", 17, 0)
  in emit_items(doc, k + 1) end

fn check_made {l:agz}{n:pos}{size:nat}{m:pos | m <= 255}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), start: Nat, finish: Nat, text: string m, m: int m, what: string): void = let
  val idref = $A.alloc<byte>(16)
  val @(idref_frozen, idref_bytes) = $A.freeze<byte>(idref)
  val made = $A.alloc<byte>(256)
  val @(made_kind, length) = written_parts(cfi_make_range(data, nodes, start, finish, 4, idref_bytes, 0, 0, made, 256))
  val same = same_bytes(made, text, m, 0)
  val () = expect(is_written(made_kind) && length = m, what)
  val () = (if length = m then expect(same, what) else ())
  val () = $A.free<byte>(made)
  val () = $A.drop<byte>(idref_frozen, idref_bytes)
  val () = $A.free<byte>($A.thaw<byte>(idref_frozen))
in end

(* The CFIs KOReader's tests assert for its highlights (koreader/koreader
   spec/unit/readerhighlight_spec.lua at c07752e8c8575ff83888347b96b74586337bc093,
   whose epub is not copied): the steps they name are read in a chapter shaped
   to have them, and the ranges made from the places found are theirs *)
fn check_koreader (): void = let
  val doc = $A.alloc<byte>(4096)
  val () = !_doc_len := 0
  val () = emit_text(doc, "<html><head><title>t</title></head><body><div><div id=\"section_77306\"><h1>a</h1><div>", 85, 0)
  val () = emit_items(doc, 1)
  val () = emit_text(doc, "</div></div></div></body></html>", 32, 0)
  val first_a = !_first_a
  val first_b = !_first_b
  val first_c = !_first_c
  val first_d = !_first_d
  val first_e = !_first_e
  val first_f = !_first_f
  val @(doc_frozen, data) = $A.freeze<byte>(doc)
  val nodes = xhtml_parse(data, 4096)
  val () = expect(first_f > 0, "KOReader: the chapter was built")
  (* a word: "thy" in a paragraph: P,S,E with S and E in the same text *)
  val () = check_range(data, nodes, "epubcfi(/6/10!/4/2/2[section_77306]/4/74/2,/3:28,/3:31)", 55, TextKind(), first_b + 28, TextKind(), first_b + 31, "KOReader: a word")
  val () = check_made(data, nodes, first_b + 28, first_b + 31, "epubcfi(/6/10!/4/2/2[section_77306]/4/74/2,/3:28,/3:31)", 55, "KOReader: a word, made")
  val () = check_range(data, nodes, "epubcfi(/6/10!/4/2/2[section_77306]/4,/74/2/5:25,/76/2/1:7)", 59, TextKind(), first_c + 25, TextKind(), first_d + 7, "KOReader: a text across two blockquotes")
  val () = check_made(data, nodes, first_c + 25, first_d + 7, "epubcfi(/6/10!/4/2/2[section_77306]/4,/74/2/5:25,/76/2/1:7)", 59, "KOReader: a text across two blockquotes, made")
  val () = check_range(data, nodes, "epubcfi(/6/10!/4/2/2[section_77306]/4,/80/2/1:0,/82/2/1:27)", 59, TextKind(), first_e, TextKind(), first_f + 27, "KOReader: a tap")
  val () = check_made(data, nodes, first_e, first_f + 27, "epubcfi(/6/10!/4/2/2[section_77306]/4,/80/2/1:0,/82/2/1:27)", 59, "KOReader: a tap, made")
  val () = check_parts("epubcfi(/6/10!/4/2/2[section_77306]/4,/80/2/1:0,/82/2/1:27)", 59, 8, 58, true, 10, CfiSideNone(), "KOReader: the spine step")
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, data)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in end

(* An id with the characters that are escaped: <p id="a,b[c]^d"> *)
fn check_escapes (): void = let
  val doc = $A.alloc<byte>(4096)
  val () = !_doc_len := 0
  val () = emit_text(doc, "<html><body><p id=\"a,b[c]^d=e;f(g)\">x</p><p id=\"b\">y</p></body></html>", 70, 0)
  val @(doc_frozen, data) = $A.freeze<byte>(doc)
  val nodes = xhtml_parse(data, 4096)
  val first = find_text(data, 4096, "p id=\"a,b", 9, 0)
  val () = check_of(data, nodes, first, "/2/2[a^,b^[c^]^^d^=e^;f^(g^)]", 29, "escapes: an id is written with ^ before each special character")
  val () = check_resolve(data, nodes, "/2/2[a^,b^[c^]^^d^=e^;f^(g^)]", 29, ElementKind(), first, "escapes: and read back")
  val x_at = find_text(data, 4096, "x</p>", 5, 0)
  val y_at = find_text(data, 4096, "y</p>", 5, 0)
  val () = check_resolve(data, nodes, "/2/4[a^,b^[c^]^^d^=e^;f^(g^)]/1:1", 33, TextKind(), x_at + 1, "escapes: the id of the first paragraph on the second step is looked for")
  val () = check_resolve(data, nodes, "/2/4[b]/1:0", 11, TextKind(), y_at, "escapes: a plain id")
  val () = check_resolve(data, nodes, "/2/2[b]/1:0", 11, TextKind(), y_at, "escapes: an id that is another element's is looked for")
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, data)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in end

(* A text of a character outside the BMP and a reference: <p>x[4 bytes]y&amp;z</p> *)
fn check_astral (): void = let
  val doc = $A.alloc<byte>(4096)
  val () = !_doc_len := 0
  val () = emit_text(doc, "<html><body><p>x", 16, 0)
  val emoji = !_doc_len
  val _ = emit_token(doc, 4)
  val after_emoji = !_doc_len
  val () = emit_text(doc, "y&amp;z</p></body></html>", 25, 0)
  val @(doc_frozen, data) = $A.freeze<byte>(doc)
  val nodes = xhtml_parse(data, 4096)
  val () = check_of(data, nodes, emoji, "/2/2/1:1", 8, "astral: before the character")
  val () = check_of(data, nodes, after_emoji, "/2/2/1:3", 8, "astral: after the character, which is two units")
  val () = check_of(data, nodes, after_emoji + 1, "/2/2/1:4", 8, "astral: after y")
  val () = check_of(data, nodes, after_emoji + 6, "/2/2/1:5", 8, "astral: after the reference, which is one unit")
  val () = check_resolve(data, nodes, "/2/2/1:3", 8, TextKind(), after_emoji, "astral: resolve after the character")
  val () = check_resolve(data, nodes, "/2/2/1:2", 8, TextKind(), emoji, "astral: an offset between the two units is the character's start")
  val () = check_resolve(data, nodes, "/2/2/1:6", 8, TextKind(), after_emoji + 7, "astral: the end of the text")
  val () = check_resolve(data, nodes, "/2/2/1:7", 8, NoPlaceKind(), 0, "astral: past the end of the text")
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, data)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in end

(* ---------------- checking a log against a chapter ---------------- *)

fn log_get {l:agz} (log: !$A.arr(byte, l, 32768), at: Int): [v:nat | v < 256] int v =
  if at < 0 then 0 else if at >= 32768 then 0 else $AR.low_byte(byte2int0($A.get<byte>(log, at)))

(* whether buf[0, length) is log[from, from + length) *)
fun same_as_log {lb:agz}{ll:agz}{n:nat}{i:nat | i <= n} .<n - i>.
  (buf: !$A.arr(byte, lb, 256), log: !$A.arr(byte, ll, 32768), from: Int, n: int n, i: int i): bool =
  if i >= n then true
  else if i >= 256 then false
  else if byte2int0($A.get<byte>(buf, i)) = log_get(log, from + i) then same_as_log(buf, log, from, n, i + 1)
  else false

fun log_into {lb:agz}{ll:agz}{n:nat}{i:nat | i <= n} .<n - i>.
  (buf: !$A.arr(byte, lb, 256), log: !$A.arr(byte, ll, 32768), from: Int, n: int n, i: int i): void =
  if i >= n then ()
  else if i >= 256 then ()
  else let
    val () = $A.write_byte(buf, i, log_get(log, from + i))
  in log_into(buf, log, from, n, i + 1) end

(* One entry of the log, in the chapter parsed as nodes *)
fn check_entry {l:agz}{n:pos}{size:nat}{ll:agz}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), log: !$A.arr(byte, ll, 32768), at: Int, seed: Int): void = let
  val kind = log_get(log, at)
  val position = log_get(log, at + 1) * 256 + log_get(log, at + 2)
  val length = log_get(log, at + 3)
  val made = $A.alloc<byte>(256)
  val @(produced_kind, produced) = written_parts(cfi_of(data, nodes, position, made, 256))
  val steps = $A.alloc<byte>(256)
  val () = log_into(steps, log, at + 4, length, 0)
  val same = same_as_log(made, log, at + 4, length, 0)
  val () = (if kind = 9 then expect(is_nowhere(produced_kind), "outside: no steps for a position in a tag or a comment")
    else if kind = 1 then expect(is_written(produced_kind) && produced = length && same, "an element's steps")
    else expect(is_written(produced_kind) && produced = length && same, "a text position's steps"))
  val @(steps_frozen, steps_bytes) = $A.freeze<byte>(steps)
  val @(found_kind, found_position) = place_parts(cfi_resolve(data, nodes, steps_bytes, length, 0))
  val () = (if kind = 1 then (expect(is_element(found_kind), "an element's steps resolve to an element"); expect(found_position = position, "an element's steps resolve to the element")) else ())
  val () = (if kind = 2 then (expect(is_text(found_kind), "a text position's steps resolve to text"); expect(found_position = position, "a text position's steps resolve to it")) else ())
  val () = (if kind = 3 then expect(is_text(found_kind), "a text position after a comment resolves to text") else ())
  (* and the position found has the same steps *)
  val again = $A.alloc<byte>(256)
  val found_nat = (if found_position >= 0 then found_position else 0): Nat
  val @(again_kind, again_length) = written_parts(cfi_of(data, nodes, found_nat, again, 256))
  val () = (if kind = 3 then (if is_text(found_kind) then expect(is_written(again_kind) && again_length = length, "the position found after a comment has the same steps") else ()) else ())
  val again_same = same_as_log(again, log, at + 4, length, 0)
  val () = (if kind = 3 then (if is_text(found_kind) then expect(again_same, "the position found after a comment has the same steps (bytes)") else ()) else ())
  val () = $A.drop<byte>(steps_frozen, steps_bytes)
  val () = $A.free<byte>($A.thaw<byte>(steps_frozen))
  val () = $A.free<byte>(again)
  val () = $A.free<byte>(made)
  val () = (if kind = 1 then !_elements_checked := !_elements_checked + 1
    else if kind = 2 then !_text_checked := !_text_checked + 1
    else if kind = 3 then !_after_comment_checked := !_after_comment_checked + 1
    else !_outside_checked := !_outside_checked + 1)
in end

fun check_log {l:agz}{n:pos}{size:nat}{ll:agz}{fuel:nat} .<fuel>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), log: !$A.arr(byte, ll, 32768), at: Int, stop: Int, seed: Int, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if at + 4 > stop then ()
  else let
    val () = check_entry(data, nodes, log, at, seed)
  in check_log(data, nodes, log, at + 4 + log_get(log, at + 3), stop, seed, fuel - 1) end

(* The chapter made with seed, every position the generator recorded checked *)
fn check_generated (seed: [s:nat | s < 65536] int s): void = let
  val doc = $A.alloc<byte>(4096)
  val log = $A.alloc<byte>(32768)
  val path = $A.alloc<byte>(512)
  val () = !_doc_len := 0
  val () = !_log_len := 0
  val () = !_path_len := 0
  val () = !_ids := 0
  val () = !_random := seed
  val () = emit_text(doc, "<?xml version=\"1.0\"?>\n<!DOCTYPE html>\n<", 39, 0)
  val html_at = !_doc_len
  val () = emit_text(doc, "html>", 5, 0)
  val () = log_element(log, path, html_at)
  val () = gen_children(doc, log, path, 3, 12, 0, 0, false)
  val () = emit_text(doc, "</html>", 7, 0)
  val @(doc_frozen, data) = $A.freeze<byte>(doc)
  val nodes = xhtml_parse(data, 4096)
  val () = check_log(data, nodes, log, 0, !_log_len, seed, 4000)
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, data)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
  val () = $A.free<byte>(log)
  val () = $A.free<byte>(path)
in end

fun check_seeds {from:nat | from <= 400} .<400 - from>. (from: int from): void =
  if from >= 400 then ()
  else let
    val () = check_generated(from)
  in check_seeds(from + 1) end

implement main0 () = let
  val () = check_spec()
  val () = check_epubjs()
  val () = check_koreader()
  val () = check_astral()
  val () = check_escapes()
  val () = check_seeds(1)
  val () = println! ("generated chapters: seeds 1 to 399; positions checked: ", !_elements_checked, " elements, ", !_text_checked, " in text, ", !_after_comment_checked, " in text after a comment, ", !_outside_checked, " outside")
  val () = if !_failures > 0 then println! ("failures: ", !_failures) else println! ("all ok")
in () end
