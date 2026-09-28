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

(* ============================================================
   Ids
   ============================================================ *)

(* A string literal's bytes in a fresh array *)
fn _lit {n:pos | n < 256} (s: string n, n: int n): [l:agz] $A.arr(byte, l, n) = let
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

fn _len {n:pos | n < 256} (s: string n): int n = g1u2i(string1_length(s))

(* s's bytes at buf[p, p + sn) *)
fun _put_str {l:agz}{n:pos}{sn:nat}{p:nat | p + sn <= n}{i:nat | i <= sn} .<sn - i>.
  (buf: !$A.arr(byte, l, n), p: int p, s: string sn, sl: int sn, i: int i): int(p + sn) =
  if i >= sl then p + sl
  else let
    val () = $A.set<byte>(buf, p + i, $A.int2byte($AR.byte_of_char(string_get_at(s, i))))
  in _put_str(buf, p, s, sl, i + 1) end

(* A numbered id: pre and i's decimal digits *)
#pub fn nid_make {sn:pos | sn <= 4}{i:nat} (pre: string sn, i: int i)
  : [l:agz][k:pos | k <= 16] @($A.arr(byte, l, k), int k)

implement nid_make(pre, i) = let
  val buf = $A.alloc<byte>(16)
  val off = _put_str(buf, 0, pre, g1u2i(string1_length(pre)), 0)
  val off = $S.int_to_str(buf, off, 16, i)
  val exact = $A.alloc<byte>(off)
  val buf = $S.copy_arr_region(buf, 0, 16, exact, off, off)
  val () = $A.free<byte>(buf)
in @(exact, off) end

(* A numbered id with a suffix: pre, i's digits, then suf *)
#pub fn nid_make2 {sn:pos | sn <= 4}{i:nat}{un:pos | un <= 4}
  (pre: string sn, i: int i, suf: string un)
  : [l:agz][k:pos | k <= 24] @($A.arr(byte, l, k), int k)

implement nid_make2(pre, i, suf) = let
  val buf = $A.alloc<byte>(24)
  val off = _put_str(buf, 0, pre, g1u2i(string1_length(pre)), 0)
  val off = $S.int_to_str(buf, off, 24, i)
  val off = _put_str(buf, off, suf, g1u2i(string1_length(suf)), 0)
  val exact = $A.alloc<byte>(off)
  val buf = $S.copy_arr_region(buf, 0, 24, exact, off, off)
  val () = $A.free<byte>(buf)
in @(exact, off) end

(* The number an id pre<digits> names, from bytes the host passed (an
   event's target): checked here, once; -1 when it is not such an id *)
fun _digits {lb:agz}{n:nat}{i:nat | i <= n} .<n - i>.
  (b: !$A.borrow(byte, lb, n), n: int n, i: int i, acc: [a:nat | a <= 99999999] int a): [v:int | v >= ~1] int v =
  if i >= n then acc
  else let
    val c = $AR.low_byte(byte2int0($A.read<byte>(b, i)))
  in
    if c < 48 then ~1
    else if c > 57 then ~1
    else if acc > 9999999 then ~1
    else _digits(b, n, i + 1, acc * 10 + (c - 48))
  end

fun _prefix_is {lb:agz}{n:nat}{sn:nat}{o:nat}{i:nat | i <= sn} .<sn - i>.
  (b: !$A.borrow(byte, lb, n), n: int n, o: int o, pre: string sn, sl: int sn, i: int i): bool =
  if i >= sl then true
  else if o + i >= n then false
  else if byte2int0($A.read<byte>(b, o + i)) <> char2int0(string_get_at(pre, i)) then false
  else _prefix_is(b, n, o, pre, sl, i + 1)

#pub fn nid_parse {lb:agz}{n:nat}{o:nat}{sn:pos | sn <= 4}
  (b: !$A.borrow(byte, lb, n), n: int n, off: int o, pre: string sn): [v:int | v >= ~1] int v

implement nid_parse{lb}{n}{o}{sn}(b, n, off, pre) = let
  val sl = g1u2i(string1_length(pre))
in
  if ~_prefix_is(b, n, off, pre, sl, 0) then ~1
  else if off + sl >= n then ~1
  else _digits(b, n, off + sl, 0)
end

(* ============================================================
   Elements
   ============================================================ *)

fn _with_doc {lp,li:agz}{np,ni:pos | np < 256; ni < 256}{tl:pos | tl < 256}
  (pb: !$A.borrow(byte, lp, np), pn: int np, ib: !$A.borrow(byte, li, ni), inn: int ni, tag: string tl): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(doc, pb, pn, ib, inn, tag)
in $D.destroy(doc) end

(* A new element <tag id=id> as the last child of parent *)
#pub fn ui_add {np,ni:pos | np < 256; ni < 256}{tl:pos | tl < 256}
  (parent: string np, id: string ni, tag: string tl): void

implement ui_add(parent, id, tag) = let
  val pn = _len(parent) and inn = _len(id)
  val @(pf, pb) = $A.freeze<byte>(_lit(parent, pn))
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val () = _with_doc(pb, pn, ib, inn, tag)
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

(* A new element with a numbered id under a fixed parent. The functions
   taking ids or texts in arrays consume (free) them. *)
#pub fn ui_add_n {np:pos | np < 256}{l:agz}{ni:pos | ni < 256}{tl:pos | tl < 256}
  (parent: string np, id: $A.arr(byte, l, ni), inn: int ni, tag: string tl): void

implement ui_add_n(parent, id, inn, tag) = let
  val pn = _len(parent)
  val @(pf, pb) = $A.freeze<byte>(_lit(parent, pn))
  val @(if_, ib) = $A.freeze<byte>(id)
  val () = _with_doc(pb, pn, ib, inn, tag)
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
  val () = $A.drop<byte>(pf, pb)
in $A.free<byte>($A.thaw<byte>(pf)) end

(* A new element with a numbered id under a numbered parent *)
#pub fn ui_add_nn {lp,l:agz}{np,ni:pos | np < 256; ni < 256}{tl:pos | tl < 256}
  (parent: $A.arr(byte, lp, np), pn: int np, id: $A.arr(byte, l, ni), inn: int ni, tag: string tl): void

implement ui_add_nn(parent, pn, id, inn, tag) = let
  val @(pf, pb) = $A.freeze<byte>(parent)
  val @(if_, ib) = $A.freeze<byte>(id)
  val () = _with_doc(pb, pn, ib, inn, tag)
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
in end

(* Removes every child of element id *)
#pub fn ui_clear {ni:pos | ni < 256} (id: string ni): void

implement ui_clear(id) = let
  val inn = _len(id)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.remove_children(doc, ib, inn)
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

(* ============================================================
   Attributes
   ============================================================ *)

fn _attr_b {li,lv:agz}{ni:pos | ni < 256}{nl:pos | nl < 256}{nv:pos}{o,k:nat | o + k <= nv; k < 65536}
  (ib: !$A.borrow(byte, li, ni), inn: int ni, name: string nl,
   vb: !$A.borrow(byte, lv, nv), off: int o, k: int k): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_attr(doc, ib, inn, name, vb, off, k)
in $D.destroy(doc) end

(* Attribute name of element id: the literal v (non-empty) *)
#pub fn ui_attr {ni:pos | ni < 256}{nl:pos | nl < 256}{nv:pos | nv < 256}
  (id: string ni, name: string nl, v: string nv): void

implement ui_attr(id, name, v) = let
  val inn = _len(id) and vn = _len(v)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(vf, vb) = $A.freeze<byte>(_lit(v, vn))
  val () = _attr_b(ib, inn, name, vb, 0, vn)
  val () = $A.drop<byte>(vf, vb)
  val () = $A.free<byte>($A.thaw<byte>(vf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

#pub fn ui_attr_n {l:agz}{ni:pos | ni < 256}{nl:pos | nl < 256}{nv:pos | nv < 256}
  (id: $A.arr(byte, l, ni), inn: int ni, name: string nl, v: string nv): void

implement ui_attr_n(id, inn, name, v) = let
  val vn = _len(v)
  val @(if_, ib) = $A.freeze<byte>(id)
  val @(vf, vb) = $A.freeze<byte>(_lit(v, vn))
  val () = _attr_b(ib, inn, name, vb, 0, vn)
  val () = $A.drop<byte>(vf, vb)
  val () = $A.free<byte>($A.thaw<byte>(vf))
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
in end

(* Attribute name of element id: buf[0, k) *)
#pub fn ui_attr_buf {ni:pos | ni < 256}{nl:pos | nl < 256}{l:agz}{n:pos}{k:pos | k <= n; k < 65536}
  (id: string ni, name: string nl, buf: $A.arr(byte, l, n), k: int k): void

implement ui_attr_buf(id, name, buf, k) = let
  val inn = _len(id)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(bf, bb) = $A.freeze<byte>(buf)
  val () = _attr_b(ib, inn, name, bb, 0, k)
  val () = $A.drop<byte>(bf, bb)
  val () = $A.free<byte>($A.thaw<byte>(bf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

#pub fn ui_attr_n_buf {li:agz}{ni:pos | ni < 256}{nl:pos | nl < 256}{l:agz}{n:pos}{k:pos | k <= n; k < 65536}
  (id: $A.arr(byte, li, ni), inn: int ni, name: string nl, buf: $A.arr(byte, l, n), k: int k): void

implement ui_attr_n_buf(id, inn, name, buf, k) = let
  val @(if_, ib) = $A.freeze<byte>(id)
  val @(bf, bb) = $A.freeze<byte>(buf)
  val () = _attr_b(ib, inn, name, bb, 0, k)
  val () = $A.drop<byte>(bf, bb)
  val () = $A.free<byte>($A.thaw<byte>(bf))
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
in end

(* The class of element id *)
#pub fn ui_class {ni:pos | ni < 256}{nv:pos | nv < 256} (id: string ni, cls: string nv): void

implement ui_class(id, cls) = ui_attr(id, "class", cls)

(* Whether element id is shown (hidden ones have data-hide="1", which the
   stylesheet does not display) *)
#pub fn ui_show {ni:pos | ni < 256} (id: string ni, shown: bool): void

implement ui_show(id, shown) =
  if shown then ui_attr(id, "data-hide", "0") else ui_attr(id, "data-hide", "1")

#pub fn ui_show_n {l:agz}{ni:pos | ni < 256} (id: $A.arr(byte, l, ni), inn: int ni, shown: bool): void

implement ui_show_n(id, inn, shown) =
  if shown then ui_attr_n(id, inn, "data-hide", "0") else ui_attr_n(id, inn, "data-hide", "1")

(* ============================================================
   Text
   ============================================================ *)

fn _text_b {li,lt:agz}{ni:pos | ni < 256}{nt:pos}{o,k:nat | o + k <= nt; k < 65536}
  (ib: !$A.borrow(byte, li, ni), inn: int ni, tb: !$A.borrow(byte, lt, nt), off: int o, k: int k): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_text(doc, ib, inn, tb, off, k)
in $D.destroy(doc) end

(* The text of element id: the literal t *)
#pub fn ui_text {ni:pos | ni < 256}{nt:pos | nt < 256} (id: string ni, t: string nt): void

implement ui_text(id, t) = let
  val inn = _len(id) and tn = _len(t)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(tf, tb) = $A.freeze<byte>(_lit(t, tn))
  val () = _text_b(ib, inn, tb, 0, tn)
  val () = $A.drop<byte>(tf, tb)
  val () = $A.free<byte>($A.thaw<byte>(tf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

#pub fn ui_text_n {l:agz}{ni:pos | ni < 256}{nt:pos | nt < 256} (id: $A.arr(byte, l, ni), inn: int ni, t: string nt): void

implement ui_text_n(id, inn, t) = let
  val tn = _len(t)
  val @(if_, ib) = $A.freeze<byte>(id)
  val @(tf, tb) = $A.freeze<byte>(_lit(t, tn))
  val () = _text_b(ib, inn, tb, 0, tn)
  val () = $A.drop<byte>(tf, tb)
  val () = $A.free<byte>($A.thaw<byte>(tf))
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
in end

(* The text of element id: buf[0, k) *)
#pub fn ui_text_buf {ni:pos | ni < 256}{l:agz}{n:pos}{k:nat | k <= n; k < 65536}
  (id: string ni, buf: $A.arr(byte, l, n), k: int k): void

implement ui_text_buf(id, buf, k) = let
  val inn = _len(id)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(bf, bb) = $A.freeze<byte>(buf)
  val () = _text_b(ib, inn, bb, 0, k)
  val () = $A.drop<byte>(bf, bb)
  val () = $A.free<byte>($A.thaw<byte>(bf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

#pub fn ui_text_n_buf {li:agz}{ni:pos | ni < 256}{l:agz}{n:pos}{k:nat | k <= n; k < 65536}
  (id: $A.arr(byte, li, ni), inn: int ni, buf: $A.arr(byte, l, n), k: int k): void

implement ui_text_n_buf(id, inn, buf, k) = let
  val @(if_, ib) = $A.freeze<byte>(id)
  val @(bf, bb) = $A.freeze<byte>(buf)
  val () = _text_b(ib, inn, bb, 0, k)
  val () = $A.drop<byte>(bf, bb)
  val () = $A.free<byte>($A.thaw<byte>(bf))
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
in end

(* The text of element id: data[off, off + k) of a borrow *)
#pub fn ui_text_n_b {li:agz}{ni:pos | ni < 256}{lt:agz}{nt:pos}{o,k:nat | o + k <= nt; k < 65536}
  (id: $A.arr(byte, li, ni), inn: int ni, tb: !$A.borrow(byte, lt, nt), off: int o, k: int k): void

implement ui_text_n_b(id, inn, tb, off, k) = let
  val @(if_, ib) = $A.freeze<byte>(id)
  val () = _text_b(ib, inn, tb, off, k)
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
in end

(* ============================================================
   Events and focus
   ============================================================ *)

(* Calls cb on each event ev at element id *)
#pub fn ui_listen {ni:pos | ni < 256}{ne:pos | ne < 256}
  (id: string ni, ev: string ne, lid: $EV.listener_id,
   cb: ($EV.event_payload) -<cloref1> int): void

implement ui_listen(id, ev, lid, cb) = let
  val inn = _len(id) and en = _len(ev)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(ef, eb) = $A.freeze<byte>(_lit(ev, en))
  val () = $EV.listen(ib, inn, eb, en, lid, cb)
  val () = $A.drop<byte>(ef, eb)
  val () = $A.free<byte>($A.thaw<byte>(ef))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

(* Calls cb on each event ev at the document *)
#pub fn ui_listen_doc {ne:pos | ne < 256}
  (ev: string ne, lid: $EV.listener_id, cb: ($EV.event_payload) -<cloref1> int): void

implement ui_listen_doc(ev, lid, cb) = let
  val en = _len(ev)
  val @(ef, eb) = $A.freeze<byte>(_lit(ev, en))
  val () = $EV.listen_document(eb, en, lid, cb)
  val () = $A.drop<byte>(ef, eb)
in $A.free<byte>($A.thaw<byte>(ef)) end

(* Calls cb on each event ev at the window *)
#pub fn ui_listen_win {ne:pos | ne < 256}
  (ev: string ne, lid: $EV.listener_id, cb: ($EV.event_payload) -<cloref1> int): void

implement ui_listen_win(ev, lid, cb) = let
  val en = _len(ev)
  val @(ef, eb) = $A.freeze<byte>(_lit(ev, en))
  val () = $EV.listen_window(eb, en, lid, cb)
  val () = $A.drop<byte>(ef, eb)
in $A.free<byte>($A.thaw<byte>(ef)) end

#pub fn ui_focus {ni:pos | ni < 256} (id: string ni): void

implement ui_focus(id) = let
  val inn = _len(id)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val () = $BDOM.focus_node(ib, inn)
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

end (* #target wasm *)
