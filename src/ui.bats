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

(* The zeros before i's digits at buf[o], to make them three *)
fn _pad3 {l:agz}{o:nat | o <= 3}{i:nat} (buf: !$A.arr(byte, l, 16), o: int o, i: int i): [p:nat | p <= o + 2] int p =
  if i < 10 then let
    val () = $A.set<byte>(buf, o, $A.int2byte(48))
    val () = $A.set<byte>(buf, o + 1, $A.int2byte(48))
  in o + 2 end
  else if i < 100 then let
    val () = $A.set<byte>(buf, o, $A.int2byte(48))
  in o + 1 end
  else o

(* A content node's id: pre and i's digits, zero-padded to three (as
   the reader numbers its content nodes) *)
#pub fn nid_pad3 {sn:pos | sn <= 3}{i:nat} (pre: string sn, i: int i)
  : [l:agz][k:pos | k <= 16] @($A.arr(byte, l, k), int k)

implement nid_pad3(pre, i) = let
  val buf = $A.alloc<byte>(16)
  val off = _put_str(buf, 0, pre, g1u2i(string1_length(pre)), 0)
  val off = _pad3(buf, off, i)
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

(* The elements made from a plain tag. None of them takes input or is
   a target: a control (a button, a field, an image) is made only by the
   constructors further down, each of which gives it its accessible
   name, so no control can be made without one *)
#pub datatype tag = TDiv | TSpan | TH1 | TB | TStyle

fn _tag_name (t: tag): [k:pos | k < 256] string k =
  case+ t of
  | TDiv() => "div" | TSpan() => "span" | TH1() => "h1" | TB() => "b" | TStyle() => "style"

fn _add_s {np,ni:pos | np < 256; ni < 256}{tl:pos | tl < 256}
  (parent: string np, id: string ni, tag: string tl): void = let
  val pn = _len(parent) and inn = _len(id)
  val @(pf, pb) = $A.freeze<byte>(_lit(parent, pn))
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val () = _with_doc(pb, pn, ib, inn, tag)
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

(* A new element <tag id=id> as the last child of parent *)
#pub fn ui_add {np,ni:pos | np < 256; ni < 256}
  (parent: string np, id: string ni, t: tag): void

implement ui_add(parent, id, t) = _add_s(parent, id, _tag_name(t))

(* A new element with a numbered id under a fixed parent. The functions
   taking ids or texts in arrays consume (free) them. *)
#pub fn ui_add_n {np:pos | np < 256}{l:agz}{ni:pos | ni < 256}
  (parent: string np, id: $A.arr(byte, l, ni), inn: int ni, t: tag): void

implement ui_add_n(parent, id, inn, t) = let
  val pn = _len(parent)
  val @(pf, pb) = $A.freeze<byte>(_lit(parent, pn))
  val @(if_, ib) = $A.freeze<byte>(id)
  val () = _with_doc(pb, pn, ib, inn, _tag_name(t))
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
  val () = $A.drop<byte>(pf, pb)
in $A.free<byte>($A.thaw<byte>(pf)) end

(* A new element with a numbered id under a numbered parent *)
#pub fn ui_add_nn {lp,l:agz}{np,ni:pos | np < 256; ni < 256}
  (parent: $A.arr(byte, lp, np), pn: int np, id: $A.arr(byte, l, ni), inn: int ni, t: tag): void

implement ui_add_nn(parent, pn, id, inn, t) = let
  val @(pf, pb) = $A.freeze<byte>(parent)
  val @(if_, ib) = $A.freeze<byte>(id)
  val () = _with_doc(pb, pn, ib, inn, _tag_name(t))
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

(* Attribute name of element id: the literal v. The attributes that
   name an element (aria-label, aria-labelledby, alt, placeholder) or
   give it a role are not among the ones ui_attr sets: only the
   constructors set them *)
fn _sattr {ni:pos | ni < 256}{nl:pos | nl < 256}{nv:pos | nv < 256}
  (id: string ni, name: string nl, v: string nv): void = let
  val inn = _len(id) and vn = _len(v)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(vf, vb) = $A.freeze<byte>(_lit(v, vn))
  val () = _attr_b(ib, inn, name, vb, 0, vn)
  val () = $A.drop<byte>(vf, vb)
  val () = $A.free<byte>($A.thaw<byte>(vf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

fn _sattr_n {l:agz}{ni:pos | ni < 256}{nl:pos | nl < 256}{nv:pos | nv < 256}
  (id: $A.arr(byte, l, ni), inn: int ni, name: string nl, v: string nv): void = let
  val vn = _len(v)
  val @(if_, ib) = $A.freeze<byte>(id)
  val @(vf, vb) = $A.freeze<byte>(_lit(v, vn))
  val () = _attr_b(ib, inn, name, vb, 0, vn)
  val () = $A.drop<byte>(vf, vb)
  val () = $A.free<byte>($A.thaw<byte>(vf))
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
in end

fn _sattr_buf {ni:pos | ni < 256}{nl:pos | nl < 256}{l:agz}{n:pos}{k:pos | k <= n; k < 65536}
  (id: string ni, name: string nl, buf: $A.arr(byte, l, n), k: int k): void = let
  val inn = _len(id)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(bf, bb) = $A.freeze<byte>(buf)
  val () = _attr_b(ib, inn, name, bb, 0, k)
  val () = $A.drop<byte>(bf, bb)
  val () = $A.free<byte>($A.thaw<byte>(bf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

fn _sattr_n_buf {li:agz}{ni:pos | ni < 256}{nl:pos | nl < 256}{l:agz}{n:pos}{k:pos | k <= n; k < 65536}
  (id: $A.arr(byte, li, ni), inn: int ni, name: string nl, buf: $A.arr(byte, l, n), k: int k): void = let
  val @(if_, ib) = $A.freeze<byte>(id)
  val @(bf, bb) = $A.freeze<byte>(buf)
  val () = _attr_b(ib, inn, name, bb, 0, k)
  val () = $A.drop<byte>(bf, bb)
  val () = $A.free<byte>($A.thaw<byte>(bf))
  val () = $A.drop<byte>(if_, ib)
  val () = $A.free<byte>($A.thaw<byte>(if_))
in end

#pub datatype attr = AClass | ASelected | APressed | AValue | AStyle | AControls
  | ATabindex | ASrc | AValueNow | ACurrent

fn _attr_name (a: attr): [k:pos | k < 256] string k =
  case+ a of
  | AClass() => "class" | ASelected() => "aria-selected" | APressed() => "aria-pressed"
  | AValue() => "value" | AStyle() => "style" | AControls() => "aria-controls"
  | ATabindex() => "tabindex" | ASrc() => "src" | AValueNow() => "aria-valuenow"
  | ACurrent() => "aria-current"

(* Attribute a of element id: the literal v (non-empty) *)
#pub fn ui_attr {ni:pos | ni < 256}{nv:pos | nv < 256}
  (id: string ni, a: attr, v: string nv): void

implement ui_attr(id, a, v) = _sattr(id, _attr_name(a), v)

#pub fn ui_attr_n {l:agz}{ni:pos | ni < 256}{nv:pos | nv < 256}
  (id: $A.arr(byte, l, ni), inn: int ni, a: attr, v: string nv): void

implement ui_attr_n(id, inn, a, v) = _sattr_n(id, inn, _attr_name(a), v)

(* Attribute a of element id: buf[0, k) *)
#pub fn ui_attr_buf {ni:pos | ni < 256}{l:agz}{n:pos}{k:pos | k <= n; k < 65536}
  (id: string ni, a: attr, buf: $A.arr(byte, l, n), k: int k): void

implement ui_attr_buf(id, a, buf, k) = _sattr_buf(id, _attr_name(a), buf, k)

#pub fn ui_attr_n_buf {li:agz}{ni:pos | ni < 256}{l:agz}{n:pos}{k:pos | k <= n; k < 65536}
  (id: $A.arr(byte, li, ni), inn: int ni, a: attr, buf: $A.arr(byte, l, n), k: int k): void

implement ui_attr_n_buf(id, inn, a, buf, k) = _sattr_n_buf(id, inn, _attr_name(a), buf, k)

(* The class of element id *)
#pub fn ui_class {ni:pos | ni < 256}{nv:pos | nv < 256} (id: string ni, cls: string nv): void

implement ui_class(id, cls) = _sattr(id, "class", cls)

(* Whether element id is shown (hidden ones have data-hide="1", which the
   stylesheet does not display) *)
#pub fn ui_show {ni:pos | ni < 256} (id: string ni, shown: bool): void

implement ui_show(id, shown) =
  if shown then _sattr(id, "data-hide", "0") else _sattr(id, "data-hide", "1")

#pub fn ui_show_n {l:agz}{ni:pos | ni < 256} (id: $A.arr(byte, l, ni), inn: int ni, shown: bool): void

implement ui_show_n(id, inn, shown) =
  if shown then _sattr_n(id, inn, "data-hide", "0") else _sattr_n(id, inn, "data-hide", "1")

(* The file input id, made again (so a file chosen twice in a row is
   taken both times) as the one child of parent after its label: its
   change events are taken on parent. Its name is its label. *)
#pub fn ui_file_input {np,ni:pos | np < 256; ni < 256}{nl,na:pos | nl < 256; na < 256}
  (parent: string np, id: string ni, label: string nl, accept: string na, multiple: bool): void

implement ui_file_input(parent, id, label, accept, multiple) = let
  val () = ui_text(parent, label)
  val () = _add_s(parent, id, "input")
  val () = _sattr(id, "type", "file")
  val () = _sattr(id, "accept", accept)
  val () = (if multiple then _sattr(id, "multiple", "multiple") else ())
in _sattr(id, "aria-label", label) end

(* The row of a range input iid from lo to hi at the value v[0, k):
   made again (a range the user has moved no longer follows its value
   attribute), with its label lid and its value's text vid after it.
   Its name is its label. *)
#pub fn ui_range {nr,nd,nl,ni,n1,n2,nv:pos | nr < 256; nd < 256; nl < 256; ni < 256; n1 < 256; n2 < 256; nv < 256}{l:agz}{n:pos}{k:pos | k <= n; k < 65536}
  (row: string nr, lid: string nd, label: string nl, iid: string ni, lo: string n1, hi: string n2, vid: string nv,
   v: $A.arr(byte, l, n), k: int k): void

implement ui_range(row, lid, label, iid, lo, hi, vid, v, k) = let
  val () = ui_clear(row)
  val () = _add_s(row, lid, "span")
  val () = _sattr(lid, "class", "slabel")
  val () = ui_text(lid, label)
  val () = _add_s(row, iid, "input")
  val () = _sattr(iid, "type", "range")
  val () = _sattr(iid, "min", lo)
  val () = _sattr(iid, "max", hi)
  val () = _sattr_buf(iid, "value", v, k)
  val () = _sattr(iid, "aria-label", label)
  val () = _add_s(row, vid, "span")
in _sattr(vid, "class", "sval") end


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

(* The text of element id: a long literal (under 64 KiB) *)
#pub fn ui_text_long {ni:pos | ni < 256}{nt:pos | nt < 65536} (id: string ni, t: string nt): void

implement ui_text_long(id, t) = let
  val inn = _len(id)
  val tn = g1u2i(string1_length(t))
  val ta = $A.alloc<byte>(tn)
  val () = $A.write_text(ta, 0, $A.text_lit(t), tn)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val @(tf, tb) = $A.freeze<byte>(ta)
  val () = _text_b(ib, inn, tb, 0, tn)
  val () = $A.drop<byte>(tf, tb)
  val () = $A.free<byte>($A.thaw<byte>(tf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

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

(* In doc: attribute name of element ib, the literal v; its text, t *)
fn _dattr {l,li:agz}{ni:pos | ni < 256}{nl:pos | nl < 256}{nv:pos | nv < 256}
  (doc: !$D.document(l), ib: !$A.borrow(byte, li, ni), inn: int ni, name: string nl, v: string nv): void = let
  val vn = _len(v)
  val @(vf, vb) = $A.freeze<byte>(_lit(v, vn))
  val () = $D.set_attr(doc, ib, inn, name, vb, 0, vn)
  val () = $A.drop<byte>(vf, vb)
in $A.free<byte>($A.thaw<byte>(vf)) end

fn _dtext {l,li:agz}{ni:pos | ni < 256}{nt:pos | nt < 256}
  (doc: !$D.document(l), ib: !$A.borrow(byte, li, ni), inn: int ni, t: string nt): void = let
  val tn = _len(t)
  val @(tf, tb) = $A.freeze<byte>(_lit(t, tn))
  val () = $D.set_text(doc, ib, inn, tb, 0, tn)
  val () = $A.drop<byte>(tf, tb)
in $A.free<byte>($A.thaw<byte>(tf)) end

(* An attribute with the empty value (alt="") *)
fn _dempty {l,li:agz}{ni:pos | ni < 256}{nl:pos | nl < 256}
  (doc: !$D.document(l), ib: !$A.borrow(byte, li, ni), inn: int ni, name: string nl): void = let
  val @(vf, vb) = $A.freeze<byte>($A.alloc<byte>(1))
  val () = $D.set_attr(doc, ib, inn, name, vb, 0, 0)
  val () = $A.drop<byte>(vf, vb)
in $A.free<byte>($A.thaw<byte>(vf)) end

(* A button element ib in pb, of class cls *)
fn _dbutton {l,lp,li:agz}{np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}
  (doc: !$D.document(l), pb: !$A.borrow(byte, lp, np), pn: int np,
   ib: !$A.borrow(byte, li, ni), inn: int ni, cls: string nc): void = let
  val () = $D.add_element(doc, pb, pn, ib, inn, "button")
  val () = _dattr(doc, ib, inn, "type", "button")
in _dattr(doc, ib, inn, "class", cls) end

#pub datatype icon = IcBack | IcClose | IcGear | IcStar | IcSearch | IcPrev | IcNext
  | IcContents | IcNotes | IcFont | IcMore

fn _glyph (ic: icon): [k:pos | k < 256] string k =
  case+ ic of
  | IcBack() => "\xE2\x86\x90" | IcClose() => "\xE2\x9C\x95" | IcGear() => "\xE2\x9A\x99"
  | IcStar() => "\xE2\x98\x86" | IcSearch() => "\xF0\x9F\x94\x8D" | IcPrev() => "\xE2\x80\xB9"
  | IcNext() => "\xE2\x80\xBA" | IcContents() => "\xE2\x98\xB0" | IcNotes() => "\xE2\x9C\x8E"
  | IcFont() => "Aa" | IcMore() => "\xE2\x8B\xAE"

(* What a menu item or a dialog's button does: Danger for one that
   deletes or resets, which the stylesheet marks *)
#pub datatype tone = Plain | Danger

(* The kinds of control, each carrying what names it *)
datatype control =
  | {nc,nl:pos | nc < 256; nl < 256} CText of (string nc, string nl)
  | {nc,nn:pos | nc < 256; nn < 256} CIcon of (string nc, icon, string nn)
  | {nc:pos | nc < 256} CNamedByContent of (string nc)
  | {nl:pos | nl < 256} CMenuItem of (string nl, tone)
  | {nl,nx:pos | nl < 256; nx < 256} CTab of (string nl, string nx, bool)

(* Control c as element ib, the last child of pb *)
fn _control {l,lp,li:agz}{np,ni:pos | np < 256; ni < 256}
  (doc: !$D.document(l), pb: !$A.borrow(byte, lp, np), pn: int np,
   ib: !$A.borrow(byte, li, ni), inn: int ni, c: control): void =
  case+ c of
  | CText(cls, label) => let
      val () = _dbutton(doc, pb, pn, ib, inn, cls)
    in _dtext(doc, ib, inn, label) end
  | CIcon(cls, ic, name) => let
      val () = _dbutton(doc, pb, pn, ib, inn, cls)
      val () = _dattr(doc, ib, inn, "aria-label", name)
    in _dtext(doc, ib, inn, _glyph(ic)) end
  | CNamedByContent(cls) => _dbutton(doc, pb, pn, ib, inn, cls)
  | CMenuItem(label, t) => let
      val () = _dbutton(doc, pb, pn, ib, inn, (case+ t of Plain() => "mi" | Danger() => "mi danger"): [k:pos | k < 256] string k)
      val () = _dattr(doc, ib, inn, "role", "menuitem")
    in _dtext(doc, ib, inn, label) end
  | CTab(label, controls, sel) => let
      val () = _dbutton(doc, pb, pn, ib, inn, "tab")
      val () = _dattr(doc, ib, inn, "role", "tab")
      val () = _dattr(doc, ib, inn, "aria-controls", controls)
      val () = _dattr(doc, ib, inn, "aria-selected", (if sel then "true" else "false"): [k:pos | k < 256] string k)
    in _dtext(doc, ib, inn, label) end

fn _control_s {np,ni:pos | np < 256; ni < 256} (parent: string np, id: string ni, c: control): void = let
  val pn = _len(parent) and inn = _len(id)
  val @(pf, pb) = $A.freeze<byte>(_lit(parent, pn))
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _control(doc, pb, pn, ib, inn, c)
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

fn _control_n {np:pos | np < 256}{l:agz}{ni:pos | ni < 256}
  (parent: string np, id: $A.arr(byte, l, ni), inn: int ni, c: control): void = let
  val pn = _len(parent)
  val @(pf, pb) = $A.freeze<byte>(_lit(parent, pn))
  val @(if_, ib) = $A.freeze<byte>(id)
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _control(doc, pb, pn, ib, inn, c)
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

fn _control_nn {lp,l:agz}{np,ni:pos | np < 256; ni < 256}
  (parent: $A.arr(byte, lp, np), pn: int np, id: $A.arr(byte, l, ni), inn: int ni, c: control): void = let
  val @(pf, pb) = $A.freeze<byte>(parent)
  val @(if_, ib) = $A.freeze<byte>(id)
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _control(doc, pb, pn, ib, inn, c)
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

(* A new element with its class *)
#pub fn ui_el {np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}
  (parent: string np, id: string ni, t: tag, cls: string nc): void

implement ui_el(parent, id, t, cls) = let
  val () = ui_add(parent, id, t)
in _sattr(id, "class", cls) end

(* A button named by the text it shows *)
#pub fn ui_text_btn {np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}{nl:pos | nl < 256}
  (parent: string np, id: string ni, cls: string nc, label: string nl): void

implement ui_text_btn(parent, id, cls, label) = _control_s(parent, id, CText(cls, label))

(* A button showing icon ic, named name *)
#pub fn ui_icon_btn {np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}{nn:pos | nn < 256}
  (parent: string np, id: string ni, cls: string nc, ic: icon, name: string nn): void

implement ui_icon_btn(parent, id, cls, ic, name) = _control_s(parent, id, CIcon(cls, ic, name))

#pub fn ui_icon_btn_nn {lp,l:agz}{np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}{nn:pos | nn < 256}
  (parent: $A.arr(byte, lp, np), pn: int np, id: $A.arr(byte, l, ni), inn: int ni,
   cls: string nc, ic: icon, name: string nn): void

implement ui_icon_btn_nn(parent, pn, id, inn, cls, ic, name) = _control_nn(parent, pn, id, inn, CIcon(cls, ic, name))

(* A numbered button named by what is put in it (a book's title, a
   chapter's, a result's text) *)
#pub fn ui_btn_n {np:pos | np < 256}{l:agz}{ni:pos | ni < 256}{nc:pos | nc < 256}
  (parent: string np, id: $A.arr(byte, l, ni), inn: int ni, cls: string nc): void

implement ui_btn_n(parent, id, inn, cls) = _control_n(parent, id, inn, CNamedByContent(cls))

#pub fn ui_btn_nn {lp,l:agz}{np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}
  (parent: $A.arr(byte, lp, np), pn: int np, id: $A.arr(byte, l, ni), inn: int ni, cls: string nc): void

implement ui_btn_nn(parent, pn, id, inn, cls) = _control_nn(parent, pn, id, inn, CNamedByContent(cls))

(* A numbered button named by the text it shows *)
#pub fn ui_text_btn_nn {lp,l:agz}{np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}{nl:pos | nl < 256}
  (parent: $A.arr(byte, lp, np), pn: int np, id: $A.arr(byte, l, ni), inn: int ni, cls: string nc, label: string nl): void

implement ui_text_btn_nn(parent, pn, id, inn, cls, label) = _control_nn(parent, pn, id, inn, CText(cls, label))

(* An item of a menu, named by its label *)
#pub fn ui_menuitem {np,ni:pos | np < 256; ni < 256}{nl:pos | nl < 256}
  (parent: string np, id: string ni, label: string nl, t: tone): void

implement ui_menuitem(parent, id, label, t) = _control_s(parent, id, CMenuItem(label, t))

(* A tab named by its label, controlling the panel controls *)
#pub fn ui_tab {np,ni:pos | np < 256; ni < 256}{nl:pos | nl < 256}{nx:pos | nx < 256}
  (parent: string np, id: string ni, label: string nl, controls: string nx, selected: bool): void

implement ui_tab(parent, id, label, controls, selected) = _control_s(parent, id, CTab(label, controls, selected))

(* A decorative image (alt=""): the text beside it says what it shows *)
#pub fn ui_img {np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}
  (parent: string np, id: string ni, cls: string nc): void

implement ui_img(parent, id, cls) = let
  val pn = _len(parent) and inn = _len(id)
  val @(pf, pb) = $A.freeze<byte>(_lit(parent, pn))
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(doc, pb, pn, ib, inn, "img")
  val () = _dattr(doc, ib, inn, "class", cls)
  val () = _dempty(doc, ib, inn, "alt")
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

#pub fn ui_img_nn {lp,l:agz}{np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}
  (parent: $A.arr(byte, lp, np), pn: int np, id: $A.arr(byte, l, ni), inn: int ni, cls: string nc): void

implement ui_img_nn(parent, pn, id, inn, cls) = let
  val @(pf, pb) = $A.freeze<byte>(parent)
  val @(if_, ib) = $A.freeze<byte>(id)
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.add_element(doc, pb, pn, ib, inn, "img")
  val () = _dattr(doc, ib, inn, "class", cls)
  val () = _dempty(doc, ib, inn, "alt")
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(pf, pb)
  val () = $A.free<byte>($A.thaw<byte>(pf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

(* A text field named name, which is also what it shows while empty.
   Search (type=search) or a multi-line text area. *)
#pub datatype field = FSearch | FText

#pub fn ui_field {np,ni:pos | np < 256; ni < 256}{nc:pos | nc < 256}{nn:pos | nn < 256}
  (parent: string np, id: string ni, f: field, cls: string nc, name: string nn): void

implement ui_field(parent, id, f, cls, name) = let
  val () = (case+ f of
    | FSearch() => let
        val () = _add_s(parent, id, "input")
      in _sattr(id, "type", "search") end
    | FText() => _add_s(parent, id, "textarea"))
  val () = _sattr(id, "class", cls)
  val () = _sattr(id, "placeholder", name)
in _sattr(id, "aria-label", name) end

(* Roles that need no name *)
#pub datatype role = RMain | RStatus | RAlert | RTooltip | RHeading

#pub fn ui_role {ni:pos | ni < 256} (id: string ni, r: role): void

implement ui_role(id, r) =
  case+ r of
  | RMain() => _sattr(id, "role", "main")
  | RStatus() => _sattr(id, "role", "status")
  | RAlert() => _sattr(id, "role", "alert")
  | RTooltip() => _sattr(id, "role", "tooltip")
  | RHeading() => let
      val () = _sattr(id, "role", "heading")
    in _sattr(id, "aria-level", "1") end

(* Roles that need a name: given here, with the role *)
#pub datatype named = NRegion | NToolbar | NDialog | NModal | NNavigation | NDocument
  | NSlider | NTablist | NTabpanel | NMenu | NStatus | NGroup

fn _named_role (r: named): [k:pos | k < 256] string k =
  case+ r of
  | NRegion() => "region" | NToolbar() => "toolbar" | NDialog() => "dialog"
  | NModal() => "dialog" | NNavigation() => "navigation" | NDocument() => "document"
  | NSlider() => "slider" | NTablist() => "tablist" | NTabpanel() => "tabpanel"
  | NMenu() => "menu" | NStatus() => "status" | NGroup() => "group"

fn _named_modal {ni:pos | ni < 256} (id: string ni, r: named): void =
  case+ r of
  | NModal() => _sattr(id, "aria-modal", "true")
  | _ => ()

fn _dmodal {l,li:agz}{ni:pos | ni < 256}
  (doc: !$D.document(l), ib: !$A.borrow(byte, li, ni), inn: int ni, r: named): void =
  case+ r of
  | NModal() => _dattr(doc, ib, inn, "aria-modal", "true")
  | _ => ()

(* Role r for element id, named name *)
#pub fn ui_named {ni:pos | ni < 256}{nn:pos | nn < 256} (id: string ni, r: named, name: string nn): void

implement ui_named(id, r, name) = let
  val () = _sattr(id, "role", _named_role(r))
  val () = _named_modal(id, r)
in _sattr(id, "aria-label", name) end

(* Role r for numbered element id, named by the text of numbered
   element by *)
#pub fn ui_labelled_nn {li,lb:agz}{ni,nb:pos | ni < 256; nb < 256}
  (id: $A.arr(byte, li, ni), inn: int ni, r: named, by: $A.arr(byte, lb, nb), bn: int nb): void

implement ui_labelled_nn(id, inn, r, by, bn) = let
  val @(if_, ib) = $A.freeze<byte>(id)
  val @(bf, bb) = $A.freeze<byte>(by)
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = _dattr(doc, ib, inn, "role", _named_role(r))
  val () = _dmodal(doc, ib, inn, r)
  val () = $D.set_attr(doc, ib, inn, "aria-labelledby", bb, 0, bn)
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(bf, bb)
  val () = $A.free<byte>($A.thaw<byte>(bf))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

(* Role r for element id, named by the text of element by *)
#pub fn ui_labelled {ni:pos | ni < 256}{nb:pos | nb < 256} (id: string ni, r: named, by: string nb): void

implement ui_labelled(id, r, by) = let
  val () = _sattr(id, "role", _named_role(r))
  val () = _named_modal(id, r)
in _sattr(id, "aria-labelledby", by) end


(* ============================================================
   Events and focus
   ============================================================ *)

(* What a listener listens on *)
#pub datatype on =
  | {n:pos | n < 256} OnEl of (string n)
  | OnDocument
  | OnWindow
  | OnExternalFiles   (* files handed to the app from outside it *)

(* The app's listeners, as one table: the last added is at its head.
   A listener's id is its position in the table (the first added is 0),
   so no two listeners share an id, and the table's length, which its
   type carries, bounds the ids below the bridge's 128. The table is
   registered at once by ui_listen_all; there is no other way to
   register a listener. *)
#pub datatype regs(int) =
  | RNil(0)
  | {n:nat}{e:pos | e < 256} RCons(n + 1) of
      (regs(n), on, string e, ($EV.event_payload) -<cloref1> int)

fn _listen1 {ne:pos | ne < 256}
  (o: on, ev: string ne, lid: $EV.listener_id, cb: ($EV.event_payload) -<cloref1> int): void = let
  val en = _len(ev)
  val @(ef, eb) = $A.freeze<byte>(_lit(ev, en))
  val () = (case+ o of
    | OnEl(id) => let
        val inn = _len(id)
        val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
        val () = $EV.listen(ib, inn, eb, en, lid, cb)
        val () = $A.drop<byte>(if_, ib)
      in $A.free<byte>($A.thaw<byte>(if_)) end
    | OnDocument() => $EV.listen_document(eb, en, lid, cb)
    | OnWindow() => $EV.listen_window(eb, en, lid, cb)
    | OnExternalFiles() => $EV.listen_external_files(lid, cb))
  val () = $A.drop<byte>(ef, eb)
in $A.free<byte>($A.thaw<byte>(ef)) end

(* Registers r's listeners, each with its position as its id; the
   number registered *)
fun _listen_all {n:nat | n <= 128} .<n>. (r: regs(n)): int n =
  case+ r of
  | RNil() => 0
  | RCons(rest, o, ev, cb) => let
      val k = _listen_all(rest)
      val () = _listen1(o, ev, k, cb)
    in k + 1 end

#pub fn ui_listen_all {n:nat | n <= 128} (r: regs(n)): void

implement ui_listen_all (r) = let val _ = _listen_all(r) in end

(* Measures element id: its box goes to dom_read's measure slots *)
#pub fn ui_measure {ni:pos | ni < 256} (id: string ni): void

implement ui_measure(id) = let
  val inn = _len(id)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val _ = $R.discard<int><int>($DR.measure(ib, inn))
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

#pub fn ui_focus {ni:pos | ni < 256} (id: string ni): void

implement ui_focus(id) = let
  val inn = _len(id)
  val @(if_, ib) = $A.freeze<byte>(_lit(id, inn))
  val () = $BDOM.focus_node(ib, inn)
  val () = $A.drop<byte>(if_, ib)
in $A.free<byte>($A.thaw<byte>(if_)) end

end (* #target wasm *)
