(* reader -- Chapter rendering, pagination, navigation *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use xml-tree as X
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/dom as D
#use wasm.bats-packages.dev/file-input as FI
#use widget as W

staload "theme.sats"
staload "epub_xml.sats"
staload "book.sats"
staload "pages.sats"
staload "paths.sats"
staload "ui.sats"
staload "library.sats"
staload "import.sats"
staload "toc.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload SC = "wasm.bats-packages.dev/bridge/src/scroll.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"

fn _apply_diff_list(dl: $W.diff_list): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.apply_list(doc, dl)
  val () = $D.destroy(doc)
in end

fn _apply_diff(d: $W.diff): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.apply(doc, d)
  val () = $D.destroy(doc)
in end

(* ============================================================
   Pagination helpers
   ============================================================ *)

(* Stash slots: 21=current_page (0-indexed), 22=total_pages, 23=current_chapter (1-indexed), 24=total_chapters *)

(* s's bytes at buf[p, p + sn) *)
fun _put_str {l:agz}{n:pos}{sn:nat}{p:nat | p + sn <= n}{i:nat | i <= sn} .<sn - i>.
  (buf: !$A.arr(byte, l, n), p: int p, s: string sn, sl: int sn, i: int i): int(p + sn) =
  if i >= sl then p + sl
  else let
    val () = $A.set<byte>(buf, p + i, $A.int2byte($AR.byte_of_char(string_get_at(s, i))))
  in _put_str(buf, p, s, sl, i + 1) end

fn _put {l:agz}{n:pos}{sn:nat}{p:nat | p + sn <= n}
  (buf: !$A.arr(byte, l, n), p: int p, s: string sn): int(p + sn) =
  _put_str(buf, p, s, g1u2i(string1_length(s)), 0)

(* The text of buf[0, k); frees buf *)
fn _prefix_text {l:agz}{n:pos | n <= 1048576}{k:pos | k <= n}
  (buf: $A.arr(byte, l, n), n: int n, k: int k): $A.text(k) = let
  val exact = $A.alloc<byte>(k)
  val buf = $S.copy_arr_region(buf, 0, n, exact, k, k)
  val () = $A.free<byte>(buf)
  val txt = arr_to_text(exact, k)
  val () = $A.free<byte>(exact)
in txt end

(* pre, then i's decimal digits zero-padded to at least w: an element
   id that stays distinct for every i *)
fn _num_id {sn:pos | sn <= 3}{i:nat}{w:int | w == 2 || w == 3}
  (pre: string sn, i: int i, w: int w): [l:agz][k:pos | k <= 16] @($A.arr(byte, l, k), int k) = let
  (* z zeros at buf[p, p + z) *)
  fun zeros {l:agz}{p,z:nat | p + z <= 16} .<z>.
    (buf: !$A.arr(byte, l, 16), p: int p, z: int z): int(p + z) =
    if z = 0 then p
    else let val () = $A.set<byte>(buf, p, $A.int2byte(48)) in zeros(buf, p + 1, z - 1) end
  val z = (if i < 10 then w - 1 else if i < 100 then w - 2 else 0): [z:nat | z <= 2] int z
  val buf = $A.alloc<byte>(16)
  val off = _put(buf, 0, pre)
  val off = zeros(buf, off, z)
  val off = $S.int_to_str(buf, off, 16, i)
  val exact = $A.alloc<byte>(off)
  val buf = $S.copy_arr_region(buf, 0, 16, exact, off, off)
  val () = $A.free<byte>(buf)
in @(exact, off) end

(* The text of the element whose id is the literal id: buf[0, k), copied
   from the buffer (no text or diff is built, so nothing is allocated);
   frees buf *)
fn _set_text_of {ni:pos | ni < 256}{l:agz}{n:pos}{k:nat | k <= n; k < 65536}
  (id: string ni, buf: $A.arr(byte, l, n), k: int k): void = let
  val ni = g1u2i(string1_length(id))
  val ia = $A.alloc<byte>(ni)
  val () = $A.write_text(ia, 0, $A.text_lit(id), ni)
  val @(fi, bi) = $A.freeze<byte>(ia)
  val @(fb, bb) = $A.freeze<byte>(buf)
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val () = $D.set_text(doc, bi, ni, bb, 0, k)
  val () = $D.destroy(doc)
  val () = $A.drop<byte>(fb, bb)
  val () = $A.free<byte>($A.thaw<byte>(fb))
  val () = $A.drop<byte>(fi, bi)
in $A.free<byte>($A.thaw<byte>(fi)) end

fn _show_indicator {p,t,c:nat} (cur_page: int p, total: int t, chapter: int c): void = let
  (* "Ch N · p. M/T": "Ch " (3 bytes), N (at most 11), " · p. " (7; the
     middle dot is 0xC2 0xB7), M (at most 11), "/" and T (at most 11) *)
  val tbuf = $A.alloc<byte>(44)
  val off = _put(tbuf, 0, "Ch ")
  val off = $S.int_to_str(tbuf, off, 44, chapter)
  val () = $A.set<byte>(tbuf, off, $A.int2byte(32))
  val () = $A.set<byte>(tbuf, off + 1, $A.int2byte(194))
  val () = $A.set<byte>(tbuf, off + 2, $A.int2byte(183))
  val off = _put(tbuf, off + 3, " p. ")
  val off = $S.int_to_str(tbuf, off, 44, cur_page + 1)
  val off = _put(tbuf, off, "/")
  val off = $S.int_to_str(tbuf, off, 44, total)
in _set_text_of("qpgi", tbuf, off) end

fn _update_page_indicator(): void =
  case+ reading_get() of @(p, t, c, _) => _show_indicator(p, t, c)

fn _measure_pagination(): void = let
  val cnt_narr = $A.alloc<byte>(4)
  val () = $A.set<byte>(cnt_narr, 0, int2byte0(113))
  val () = $A.set<byte>(cnt_narr, 1, int2byte0(99))
  val () = $A.set<byte>(cnt_narr, 2, int2byte0(110))
  val () = $A.set<byte>(cnt_narr, 3, int2byte0(116))
  val @(cnt_f, cnt_b) = $A.freeze<byte>(cnt_narr)
  val mr = $DR.measure(cnt_b, 4)
  val () = $A.drop<byte>(cnt_f, cnt_b)
  val cnt_tmp = $A.thaw<byte>(cnt_f)
  val () = $A.free<byte>(cnt_tmp)
  val _ = $R.discard<int><int>(mr)
  (* The page's widths, checked here: the chapter has scroll width /
     width pages, and at least one *)
  val cw = $DR.get_measure_w()
  val sw = $DR.get_measure_scroll_w()
  val total = (if cw > 0 then sw / cw else 1): [v:int] int v
  val t = (if total > 1 then total else 1): [t:pos] int t
  val () = (case+ reading_get() of
    | @(_, _, c, tc) => reading_set(@(0, t, c, tc)))
  val () = window_show(0, t)
in _update_page_indicator() end

(* Measures element id: its box to the measure slots *)
fn _measure_lit {ni:pos | ni < 256} (id: string ni): void = let
  val ni = g1u2i(string1_length(id))
  val ia = $A.alloc<byte>(ni)
  val () = $A.write_text(ia, 0, $A.text_lit(id), ni)
  val @(fi, bi) = $A.freeze<byte>(ia)
  val _ = $R.discard<int><int>($DR.measure(bi, ni))
  val () = $A.drop<byte>(fi, bi)
in $A.free<byte>($A.thaw<byte>(fi)) end

(* Measures content node i: whether it is in the page *)
fn _measure_node {i:nat} (i: int i): bool = let
  val @(ia, il) = _num_id("c", i, 3)
  val @(fi, bi) = $A.freeze<byte>(ia)
  val r = $DR.measure(bi, il)
  val () = $A.drop<byte>(fi, bi)
  val () = $A.free<byte>($A.thaw<byte>(fi))
in
  case+ r of
  | ~$R.ok(_) => true
  | ~$R.err(_) => false
end

(* The content node at the top of the page shown (its number), or -1:
   the element at the middle of the page's first line *)
fn _anchor_now (): [v:int | v >= ~1] int v = let
  val () = _measure_lit("qcnt")
  val cx = $DR.get_measure_x()
  val cy = $DR.get_measure_y()
  val cw = $DR.get_measure_w()
in
  case+ $DR.element_at_point(cx + cw / 2, cy + 24) of
  | ~$R.none() => ~1
  | ~$R.some(b) => let
      val n = $DC.blob_len(b)
    in
      if n <= 0 then let val () = $DC.blob_free(b) in ~1 end
      else if n > 16 then let val () = $DC.blob_free(b) in ~1 end
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(b, 0, a, n)
        val () = $DC.blob_free(b)
        val @(f, bb) = $A.freeze<byte>(a)
        val v = nid_parse(bb, n, 0, "c")
        val () = $A.drop<byte>(f, bb)
        val () = $A.free<byte>($A.thaw<byte>(f))
      in v end
    end
end

(* The page, of the chapter's t, that content node i is on (the page
   shown now is cur); cur when it is not in the chapter *)
fn _page_of_node {t:pos}{c:nat | c < t}{i:nat} (i: int i, t: int t, cur: int c): [p:nat | p < t] int p =
  if ~_measure_node(i) then cur
  else let
    val x = $DR.get_measure_x()
    val () = _measure_lit("qcnt")
    val cx = $DR.get_measure_x()
    val cw = $DR.get_measure_w()
  in
    if cw <= 0 then cur
    else let
      val d = x - cx
      (* whole pages from the one shown, rounded down *)
      val k = (if d >= 0 then d / cw else ~((cw - 1 - d) / cw)): Int
      val p = cur + k
    in if p < 0 then 0 else if p >= t then t - 1 else p end
  end

(* The position read to the open book's record in the library, which is
   then stored *)
fn _record_position (): void = let
  val i = lib_index_of_key(open_key_get())
  val anchor = _anchor_now()
  val now = $TM.epoch_minutes()
in
  case+ reading_get() of
  | @(p, t, c, tc) =>
    if i < 0 then ()
    else let
      val ch = (if c > 0 then c - 1 else 0): Int
      val at_end = (if tc > 0 then (if c >= tc then p + 1 >= t else false) else false): bool
      val () = lib_update(i, lam(x) => @{
        key = x.key, h1 = x.h1, h2 = x.h2, shelf = x.shelf, added = x.added, opened = now,
        ch = ch, tch = (if tc > 0 then (tc: Int) else x.tch), pg = p, pgs = t, anchor = anchor,
        fsz = x.fsz, cover = x.cover, done = (if at_end then 1 else x.done) })
    in lib_save() end
end

(* ============================================================
   The scrubber: where the page is in the book, by the chapters'
   sizes, in thousandths
   ============================================================ *)

fn _clamp1000 (v: Int): [r:nat | r <= 1000] int r =
  if v <= 0 then 0 else if v >= 1000 then 1000 else v

(* The thousandth of the book at size position x of its tot *)
fn _thousandth (x: Int, tot: Int): [r:nat | r <= 1000] int r =
  if tot <= 0 then 0
  (* x * 1000 fits an int *)
  else if tot < 2000000 then _clamp1000(x * 1000 / tot)
  else _clamp1000(x / (tot / 1000))

(* The size position of thousandth v of tot *)
fn _of_thousandth (v: Int, tot: Int): Int =
  if tot < 2000000 then tot * v / 1000 else (tot / 1000) * v

(* Where page p of t in chapter c (from 0) is in the book *)
fn _permille (c: Int, p: Int, t: Int): [r:nat | r <= 1000] int r = let
  val @(b, w, tot) = book_weights(book_serial(), c)
  val cp = (if t > 0 then p * 1000 / t else 0): Int
in _thousandth(b + _of_thousandth(cp, w), tot) end

(* The style prop v/10 "%" (with one decimal) of element id *)
fn _style_pct {ni:pos | ni < 256}{sn:pos | sn <= 8}{v:nat | v <= 1000}
  (id: string ni, prop: string sn, v: int v): void = let
  val b = $A.alloc<byte>(32)
  val off = _put(b, 0, prop)
  val off = $S.int_to_str(b, off, 32, v / 10)
  val off = _put(b, off, ".")
  val off = $S.int_to_str(b, off, 32, v - (v / 10) * 10)
  val off = _put(b, off, "%")
in ui_attr_buf(id, "style", b, off) end

(* The scrubber at v: its thumb, its fill and the percentage *)
fn _scrub_at {v:nat | v <= 1000} (v: int v): void = let
  val () = _style_pct("qsth", "left:", v)
  val () = _style_pct("qtkf", "width:", v)
  val b = $A.alloc<byte>(16)
  val off = $S.int_to_str(b, 0, 16, v / 10)
  val off = _put(b, off, "%")
  val () = ui_text_buf("qpct", b, off)
  val b = $A.alloc<byte>(16)
  val off = $S.int_to_str(b, 0, 16, v / 10)
in ui_attr_buf("qtrk", "aria-valuenow", b, off) end

(* The scrubber at the page shown *)
fn _scrub_show (): void =
  case+ reading_get() of
  | @(p, t, c, _) => _scrub_at(_permille((if c > 0 then c - 1 else 0), p, t))

(* A tick on the scrubber where each chapter after the first starts *)
fun _ticks {i,tc:nat} .<max(tc - i, 0)>. (i: int i, tc: int tc): void =
  if i >= tc then ()
  else let
    val @(b, _, tot) = book_weights(book_serial(), i)
    val @(ki, kl) = nid_make("qk", i)
    val () = ui_add_n("qstk", ki, kl, "div")
    val @(ki, kl) = nid_make("qk", i)
    val () = ui_attr_n(ki, kl, "class", "tick")
    val v = _thousandth(b, tot)
    val bb = $A.alloc<byte>(32)
    val off = _put(bb, 0, "left:")
    val off = $S.int_to_str(bb, off, 32, v / 10)
    val off = _put(bb, off, ".")
    val off = $S.int_to_str(bb, off, 32, v - (v / 10) * 10)
    val off = _put(bb, off, "%")
    val @(ki, kl) = nid_make("qk", i)
    val () = ui_attr_n_buf(ki, kl, "style", bb, off)
  in _ticks(i + 1, tc) end

fn _ticks_show {tc:nat} (tc: int tc): void = let
  val () = ui_clear("qstk")
in _ticks(1, tc) end

(* The chapter, of tc, at thousandth v of the book, and the thousandth
   of the chapter *)
fun _chapter_at {i,tc:nat} .<max(tc - i, 0)>. (v: Int, i: int i, tc: int tc): @([c:nat] int c, [r:nat | r <= 1000] int r) =
  if i >= tc then @(0, 0)
  else let
    val @(b, w, tot) = book_weights(book_serial(), i)
    val x = _of_thousandth(v, tot)
  in
    if (if x < b + w then true else i + 1 >= tc) then
      @(i, _thousandth(x - b, w))
    else _chapter_at(v, i + 1, tc)
  end

(* The thousandth of the book at x on the scrubber's track *)
fn _track_at (x: Int): [r:nat | r <= 1000] int r = let
  val () = _measure_lit("qtrk")
  val tx = $DR.get_measure_x()
  val tw = $DR.get_measure_w()
in if tw <= 0 then 0 else _clamp1000((x - tx) * 1000 / tw) end

(* Shows page p of the chapter's t pages *)
fn _show_page {t:pos}{p:nat | p < t}{c,tc:nat}
  (p: int p, t: int t, c: int c, tc: int tc): void = let
  val () = reading_set(@(p, t, c, tc))
  val () = window_show(p, t)
  val page = p
  val cnt_narr = $A.alloc<byte>(4)
  val () = $A.set<byte>(cnt_narr, 0, int2byte0(113))
  val () = $A.set<byte>(cnt_narr, 1, int2byte0(99))
  val () = $A.set<byte>(cnt_narr, 2, int2byte0(110))
  val () = $A.set<byte>(cnt_narr, 3, int2byte0(116))
  val @(cnt_f, cnt_b) = $A.freeze<byte>(cnt_narr)
  val mr = $DR.measure(cnt_b, 4)
  val _ = $R.discard<int><int>(mr)
  val cw = $DR.get_measure_w()
  val scroll_x = page * cw
  val () = $SC.set_scroll_left(cnt_b, 4, scroll_x)
  val () = $A.drop<byte>(cnt_f, cnt_b)
  val cnt_tmp = $A.thaw<byte>(cnt_f)
  val () = $A.free<byte>(cnt_tmp)
  val () = _update_page_indicator()
  val () = _scrub_show()
  val () = _record_position()
in end

(* ============================================================
   Content tree rendering (XHTML → DOM nodes)
   ============================================================ *)

(* Content nodes are numbered from 0 in each chapter *)
val _content_n = ref<[n:nat] int n>(0)

(* Content node i's element: id "c" and i's digits, with op run on its
   id as a borrow *)
(* The id of content node i (or of the content area qcnt, for ~1) in a
   fresh array; with its length *)
fn _node_id {q:int | q >= ~1} (i: int q): [l:agz][k:pos | k <= 16] @($A.arr(byte, l, k), int k) =
  if i < 0 then let
    val a = $A.alloc<byte>(4)
    val () = $A.write_text(a, 0, $A.text_lit("qcnt"), 4)
  in @(a, 4) end
  else _num_id("c", i, 3)

(* A new element <tag> for content node idx, the last child of node pidx *)
fn _add_node {ld:agz}{q:int | q >= ~1}{i:nat}{tl:pos | tl < 256}
  (doc: !$D.document(ld), pidx: int q, idx: int i, tag: string tl): void = let
  val @(pa, pl) = _node_id(pidx)
  val @(ca, cl) = _node_id(idx)
  val @(fp, bp) = $A.freeze<byte>(pa)
  val @(fc, bc) = $A.freeze<byte>(ca)
  val () = $D.add_element(doc, bp, pl, bc, cl, tag)
  val () = $A.drop<byte>(fc, bc)
  val () = $A.free<byte>($A.thaw<byte>(fc))
  val () = $A.drop<byte>(fp, bp)
in $A.free<byte>($A.thaw<byte>(fp)) end

(* Content node idx's text: data[off, off + k) *)
fn _node_text {ld,lb:agz}{n:pos}{i:nat}{o,k:nat | o + k <= n; k < 65536}
  (doc: !$D.document(ld), idx: int i, data: !$A.borrow(byte, lb, n), off: int o, k: int k): void = let
  val @(ia, il) = _node_id(idx)
  val @(fi, bi) = $A.freeze<byte>(ia)
  val () = $D.set_text(doc, bi, il, data, off, k)
  val () = $A.drop<byte>(fi, bi)
in $A.free<byte>($A.thaw<byte>(fi)) end

(* Whether data[p] starts a UTF-8 character (is not 10xxxxxx) *)
fn _utf8_start {lb:agz}{n:pos}{p:nat | p < n}
  (data: !$A.borrow(byte, lb, n), p: int p): bool =
  $AR.band_int_int(byte2int0($A.read<byte>(data, p)), 192) <> 128

(* The length of the longest prefix of data[off, off + k), k of 64 KiB
   or more, under 64 KiB (a text op's limit) that ends before a UTF-8
   character's start, so no character is split; 65535 when the data is
   not UTF-8 there *)
fn _text_cut {lb:agz}{n:pos}{o,k:nat | o + k <= n; k >= 65536}
  (data: !$A.borrow(byte, lb, n), off: int o, k: int k): [c:int | 65533 <= c; c <= 65535] int c =
  if _utf8_start(data, off + 65535) then 65535
  else if _utf8_start(data, off + 65534) then 65534
  else if _utf8_start(data, off + 65533) then 65533
  else 65535

(* Content node idx's attribute name: data[off, off + k) *)
fn _node_attr {ld,lb:agz}{n:pos}{i:nat}{nl:pos | nl < 256}{o,k:nat | o + k <= n; k < 65536}
  (doc: !$D.document(ld), idx: int i, name: string nl, data: !$A.borrow(byte, lb, n), off: int o, k: int k): void = let
  val @(ia, il) = _node_id(idx)
  val @(fi, bi) = $A.freeze<byte>(ia)
  val () = $D.set_attr(doc, bi, il, name, data, off, k)
  val () = $A.drop<byte>(fi, bi)
in $A.free<byte>($A.thaw<byte>(fi)) end

(* Content node idx's attribute name: the literal v *)
fn _node_attr_lit {ld:agz}{i:nat}{nl:pos | nl < 256}{vl:pos | vl < 256}
  (doc: !$D.document(ld), idx: int i, name: string nl, v: string vl): void = let
  val vl = g1u2i(string1_length(v))
  val va = $A.alloc<byte>(vl)
  val () = $A.write_text(va, 0, $A.text_lit(v), vl)
  val @(fv, bv) = $A.freeze<byte>(va)
  val () = _node_attr(doc, idx, name, bv, 0, vl)
  val () = $A.drop<byte>(fv, bv)
in $A.free<byte>($A.thaw<byte>(fv)) end

(* Content nodes are numbered from 0 in each chapter *)
val _content_n = ref<[n:nat] int n>(0)

(* Get next content node index and increment counter *)
fn _next_content_idx(): [n:nat] int n = let
  val n = !_content_n
  val () = !_content_n := n + 1
in n end

(* Text data[off, off + k) as spans, the last children of content node
   pidx: one span per piece under 64 KiB (a text op's limit), split
   where a UTF-8 character starts *)
fun _text_spans {ld,lb:agz}{n:pos}{q:int | q >= ~1}{o,k:nat | o + k <= n} .<k>.
  (doc: !$D.document(ld), data: !$A.borrow(byte, lb, n), pidx: int q, off: int o, k: int k): void = let
  val idx = _next_content_idx()
  val () = _add_node(doc, pidx, idx, "span")
in
  if k < 65536 then _node_text(doc, idx, data, off, k)
  else let
    val c = _text_cut(data, off, k)
    val () = _node_text(doc, idx, data, off, c)
  in _text_spans(doc, data, pidx, off + c, k - c) end
end

(* The tag an XHTML element is shown as: itself when it is one quire
   shows, a span for a, b, i, u and s, and a div for anything else *)
fn _tag_of
  {lb:agz}{n:pos}{o,k:nat | o + k <= n}
  (data: !$A.borrow(byte, lb, n), name_off: int o, name_len: int k): [tl:pos | tl < 256] string tl = let
  fn is {np:pos} (data: !$A.borrow(byte, lb, n), pat: &(@[char][np]), np: int np): bool =
    xml_name_eq(data, name_off, name_len, pat, np)
  var p_ = @[char][1]('p')
  var h1 = @[char][2]('h', '1')
  var h2 = @[char][2]('h', '2')
  var h3 = @[char][2]('h', '3')
  var h4 = @[char][2]('h', '4')
  var h5 = @[char][2]('h', '5')
  var h6 = @[char][2]('h', '6')
  var span = @[char][4]('s', 'p', 'a', 'n')
  var em = @[char][2]('e', 'm')
  var strong = @[char][6]('s', 't', 'r', 'o', 'n', 'g')
  var bq = @[char][10]('b', 'l', 'o', 'c', 'k', 'q', 'u', 'o', 't', 'e')
  var pre = @[char][3]('p', 'r', 'e')
  var code = @[char][4]('c', 'o', 'd', 'e')
  var ul = @[char][2]('u', 'l')
  var ol = @[char][2]('o', 'l')
  var li = @[char][2]('l', 'i')
  var section = @[char][7]('s', 'e', 'c', 't', 'i', 'o', 'n')
  var article = @[char][7]('a', 'r', 't', 'i', 'c', 'l', 'e')
  var small = @[char][5]('s', 'm', 'a', 'l', 'l')
  var mark = @[char][4]('m', 'a', 'r', 'k')
  var del = @[char][3]('d', 'e', 'l')
  var ins = @[char][3]('i', 'n', 's')
  var sub = @[char][3]('s', 'u', 'b')
  var sup = @[char][3]('s', 'u', 'p')
  var a_ = @[char][1]('a')
  var b_ = @[char][1]('b')
  var i_ = @[char][1]('i')
  var u_ = @[char][1]('u')
  var s_ = @[char][1]('s')
  var figure = @[char][6]('f', 'i', 'g', 'u', 'r', 'e')
  var figcap = @[char][10]('f', 'i', 'g', 'c', 'a', 'p', 't', 'i', 'o', 'n')
  var table = @[char][5]('t', 'a', 'b', 'l', 'e')
  var tr = @[char][2]('t', 'r')
  var td = @[char][2]('t', 'd')
  var th = @[char][2]('t', 'h')
  var thead = @[char][5]('t', 'h', 'e', 'a', 'd')
  var tbody = @[char][5]('t', 'b', 'o', 'd', 'y')
in
  if is(data, p_, 1) then "p"
  else if is(data, h1, 2) then "h1" else if is(data, h2, 2) then "h2"
  else if is(data, h3, 2) then "h3" else if is(data, h4, 2) then "h4"
  else if is(data, h5, 2) then "h5" else if is(data, h6, 2) then "h6"
  else if is(data, span, 4) then "span" else if is(data, em, 2) then "em"
  else if is(data, strong, 6) then "strong" else if is(data, bq, 10) then "blockquote"
  else if is(data, pre, 3) then "pre" else if is(data, code, 4) then "code"
  else if is(data, ul, 2) then "ul" else if is(data, ol, 2) then "ol"
  else if is(data, li, 2) then "li" else if is(data, section, 7) then "section"
  else if is(data, article, 7) then "article" else if is(data, small, 5) then "small"
  else if is(data, mark, 4) then "mark" else if is(data, del, 3) then "del"
  else if is(data, ins, 3) then "ins" else if is(data, sub, 3) then "sub"
  else if is(data, sup, 3) then "sup"
  else if is(data, a_, 1) then "span" else if is(data, b_, 1) then "span"
  else if is(data, i_, 1) then "span" else if is(data, u_, 1) then "span"
  else if is(data, s_, 1) then "span"
  else if is(data, figure, 6) then "figure" else if is(data, figcap, 10) then "figcaption"
  else if is(data, table, 5) then "table" else if is(data, tr, 2) then "tr"
  else if is(data, td, 2) then "td" else if is(data, th, 2) then "th"
  else if is(data, thead, 5) then "thead" else if is(data, tbody, 5) then "tbody"
  else "div"
end

(* The fragment a jump leads to: the id of an element of the chapter
   loading; its content node is found as the chapter is rendered *)
datavtype frag =
  | {l:agz}{n,f:pos | f < n} FragSome of ($A.arr(byte, l, n), int f)
  | FragNone of ()

val _frag = ref<frag>(FragNone())
val _frag_hit = ref<Int>(~1)

fn _frag_free (f: frag): void =
  case+ f of
  | ~FragSome(a, _) => $A.free<byte>(a)
  | ~FragNone() => ()

fn _frag_take (): frag = let
  var c: frag = FragNone()
  val () = ref_exch_elt<frag>(_frag, c)
in c end

fn _frag_put (f: frag): void = let
  var c: frag = f
  val () = ref_exch_elt<frag>(_frag, c)
in _frag_free(c) end

(* Whether data[o, o + k) is a[0, k) *)
fun _same {lb,la:agz}{n:pos}{f:pos}{o,k:nat | o + k <= n; k <= f}{i:nat | i <= k} .<k - i>.
  (data: !$A.borrow(byte, lb, n), o: int o, a: !$A.arr(byte, la, f), k: int k, i: int i): bool =
  if i >= k then true
  else if byte2int0($A.read<byte>(data, o + i)) <> byte2int0($A.get<byte>(a, i)) then false
  else _same(data, o, a, k, i + 1)

(* Notes content node idx as the fragment's, when its id is fr *)
fn _frag_check {lb:agz}{n:pos}{sa:nat}{i:nat}
  (data: !$A.borrow(byte, lb, n), attrs: !$X.xml_attr_list(n, sa), fr: !frag, idx: int i): void =
  case+ fr of
  | FragNone() => ()
  | FragSome(a, f) => let
      var _a_id = @[char][2]('i', 'd')
    in
      case+ find_attr(data, attrs, _a_id, 2) of
      | ~xspan_at(o, k) =>
        if k <> f then ()
        else if _same(data, o, a, k, 0) then (if !_frag_hit < 0 then !_frag_hit := idx else ())
        else ()
      | ~xspan_none() => ()
    end

(* The <img> elements of a chapter being rendered, k of them: each one's
   content node and its src attribute, the span [so, so + sl) of the
   chapter's n bytes *)
datavtype imgs(n:int, int) =
  | imgs_nil(n, 0) of ()
  | {k:nat}{i:nat}{so,sl:nat | so + sl <= n}
    imgs_cons(n, k + 1) of (int i, int so, int sl, imgs(n, k))

(* Walk xml_node_list, rendering each node into parent (through doc's
   borrow operations: nothing is allocated for the page); the <img>
   elements met are added to acc *)
fun _render_nodes
  {ld,lb:agz}{n:pos}{sz:nat}{q:int | q >= ~1}{k:nat} .<sz, 1>.
  (doc: !$D.document(ld), data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int q, nodes: !$X.xml_node_list(n, sz), acc: imgs(n, k), fr: !frag): [k2:nat] imgs(n, k2) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val acc = _render_node(doc, data, len, pidx, node, acc, fr)
    in _render_nodes(doc, data, len, pidx, rest, acc, fr) end
  | $X.xml_nodes_nil() => acc

and _render_node
  {ld,lb:agz}{n:pos}{sz:pos}{q:int | q >= ~1}{k:nat} .<sz, 0>.
  (doc: !$D.document(ld), data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int q, node: !$X.xml_node(n, sz), acc: imgs(n, k), fr: !frag): [k2:nat] imgs(n, k2) =
  case+ node of
  | $X.xml_text(off, tlen) => let
      val () = _text_spans(doc, data, pidx, off, tlen)
    in acc end
  | $X.xml_element(name_off, name_len, attrs, children) => let
    var _t_head = @[char][4]('h', 'e', 'a', 'd')
    var _t_title = @[char][5]('t', 'i', 't', 'l', 'e')
    var _t_meta = @[char][4]('m', 'e', 't', 'a')
    var _t_link = @[char][4]('l', 'i', 'n', 'k')
    var _t_style = @[char][5]('s', 't', 'y', 'l', 'e')
    var _t_script = @[char][6]('s', 'c', 'r', 'i', 'p', 't')
    var _t_html = @[char][4]('h', 't', 'm', 'l')
    var _t_body = @[char][4]('b', 'o', 'd', 'y')
    var _t_br = @[char][2]('b', 'r')
    var _t_hr = @[char][2]('h', 'r')
    var _t_img = @[char][3]('i', 'm', 'g')
    var _t_image = @[char][5]('i', 'm', 'a', 'g', 'e')
  in
    (* Skipped: head, title, meta, link, style, script *)
    if xml_name_eq(data, name_off, name_len, _t_head, 4) then acc
    else if xml_name_eq(data, name_off, name_len, _t_title, 5) then acc
    else if xml_name_eq(data, name_off, name_len, _t_meta, 4) then acc
    else if xml_name_eq(data, name_off, name_len, _t_link, 4) then acc
    else if xml_name_eq(data, name_off, name_len, _t_style, 5) then acc
    else if xml_name_eq(data, name_off, name_len, _t_script, 6) then acc
    (* Transparent: html, body (their children go to the same parent) *)
    else if xml_name_eq(data, name_off, name_len, _t_html, 4) then
      _render_nodes(doc, data, len, pidx, children, acc, fr)
    else if xml_name_eq(data, name_off, name_len, _t_body, 4) then
      _render_nodes(doc, data, len, pidx, children, acc, fr)
    (* Void: br, hr, img *)
    else if xml_name_eq(data, name_off, name_len, _t_br, 2) then let
      val () = _add_node(doc, pidx, _next_content_idx(), "br")
    in acc end
    else if xml_name_eq(data, name_off, name_len, _t_hr, 2) then let
      val () = _add_node(doc, pidx, _next_content_idx(), "hr")
    in acc end
    else if xml_name_eq(data, name_off, name_len, _t_img, 3) then let
      (* An image: shown once its bytes are read from the book
         (_load_images); until then its src is an empty data URL *)
      val idx = _next_content_idx()
      val () = _add_node(doc, pidx, idx, "img")
      val () = _node_attr_lit(doc, idx, "src", "data:,")
      var _a_alt = @[char][3]('a', 'l', 't')
      val () = (case+ find_attr(data, attrs, _a_alt, 3) of
        | ~xspan_at(ao, al) =>
          if al < 65536 then _node_attr(doc, idx, "alt", data, ao, al)
          else _node_attr(doc, idx, "alt", data, ao, _text_cut(data, ao, al))
        | ~xspan_none() => _node_attr_lit(doc, idx, "alt", "image")): void
      var _a_src = @[char][3]('s', 'r', 'c')
    in
      case+ find_attr(data, attrs, _a_src, 3) of
      | ~xspan_at(so, sl) => imgs_cons(idx, so, sl, acc)
      | ~xspan_none() => acc
    end
    (* An SVG <image> (a cover page's usual form): shown as an <img>,
       its source xlink:href, or href *)
    else if xml_name_eq(data, name_off, name_len, _t_image, 5) then let
      val idx = _next_content_idx()
      val () = _add_node(doc, pidx, idx, "img")
      val () = _node_attr_lit(doc, idx, "src", "data:,")
      val () = _node_attr_lit(doc, idx, "alt", "image")
      var _a_xhref = @[char][10]('x', 'l', 'i', 'n', 'k', ':', 'h', 'r', 'e', 'f')
      var _a_href = @[char][4]('h', 'r', 'e', 'f')
    in
      case+ find_attr(data, attrs, _a_xhref, 10) of
      | ~xspan_at(so, sl) => imgs_cons(idx, so, sl, acc)
      | ~xspan_none() => (case+ find_attr(data, attrs, _a_href, 4) of
        | ~xspan_at(so, sl) => imgs_cons(idx, so, sl, acc)
        | ~xspan_none() => acc)
    end
    else let
      val idx = _next_content_idx()
      val () = _add_node(doc, pidx, idx, _tag_of(data, name_off, name_len))
      val () = _frag_check(data, attrs, fr, idx)
    in _render_nodes(doc, data, len, idx, children, acc, fr) end
  end

(* The length of the directory part of the name [no, no + nl) of the
   file: up to and including its last '/', 0 when it has none *)
fn _opf_prefix_len {z:pos}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
  (s: int, z: int z, no: int no, nl: int nl): [p:nat | p <= nl] int p = let
  val buf = $A.alloc<byte>(nl)
  val _ = book_read(s, z, no, buf, nl)
  val p = path_dir_end(buf, nl)
  val () = $A.free<byte>(buf)
in p end

(* ============================================================
   Images: read from the book, shown in the chapter's <img> elements
   ============================================================ *)

(* Counts chapter loads: an image whose bytes arrive after another
   chapter began loading is not shown (its element is gone) *)
val _load_gen = ref<int>(0)

(* Content node idx's image: the nd bytes of data, of type mime *)
fn _set_src {i:nat}{ld:agz}{nd:pos}{sn:pos | sn <= 24}
  (idx: int i, data: !$A.borrow(byte, ld, nd), nd: int nd, mime: string sn): void = let
  val ml = g1u2i(string1_length(mime))
  val mb = $A.alloc<byte>(ml)
  val _ = _put(mb, 0, mime)
  val @(fm, bm) = $A.freeze<byte>(mb)
  val @(ida, idk) = _num_id("c", idx, 3)
  val @(fi, bi) = $A.freeze<byte>(ida)
  val () = $BDOM.set_image_src(bi, idk, data, nd, bm, ml)
  val () = $A.drop<byte>(fi, bi)
  val () = $A.free<byte>($A.thaw<byte>(fi))
  val () = $A.drop<byte>(fm, bm)
in $A.free<byte>($A.thaw<byte>(fm)) end

(* Content node idx's image, the entry named path[0, k) of the book's
   z-byte file (book s): shown now when it is stored, once decompressed when it
   is deflated (unless chapter load gen is no longer the latest); not at
   all when it is missing *)
fn _show_image {z:pos}{i:nat}{lp:agz}{k:pos}
  (s: int, z: int z, idx: int i, gen: int,
   path: !$A.borrow(byte, lp, k), k: int k): void = let
  val mime = mime_of(path, k)
in
  case+ book_zip_read(s, z, path, k) of
  | ~ZipMissing() => ()
  | ~ZipGot(ar, buf, cs, m, _, _, _) =>
    if m = 0 then let
      val @(f, b) = $A.freeze<byte>(buf)
      val () = _set_src(idx, b, cs, mime)
      val () = $A.drop<byte>(f, b)
    in piece_free(ar, $A.thaw<byte>(f)) end
    else let
      val @(f, b) = $A.freeze<byte>(buf)
      val dp = $DC.decompress(b, cs, m)
      val () = $A.drop<byte>(f, b)
      val () = piece_free(ar, $A.thaw<byte>(f))
      val dp = $P.vow(dp)
    in
      $P.discard<int>($P.and_then<Int><int>(dp, lam(h) =>
        case+ take_content(h) of
        | ~NoContentBytes() => $P.ret<int>(~1)
        | ~ContentBytes(ar2, buf2, n2) => let
            val @(f2, b2) = $A.freeze<byte>(buf2)
            val () = (if !_load_gen = gen then _set_src(idx, b2, n2, mime) else ())
            val () = $A.drop<byte>(f2, b2)
            val () = piece_free(ar2, $A.thaw<byte>(f2))
          in $P.ret<int>(0) end))
    end
end

(* The image of content node idx, whose src is data[so, so + sl): the
   entry that src names relative to the chapter's directory (the first
   dl bytes of the chapter's name, at no in the file) *)
fn _load_image {z:pos}{no,dl:nat | no + dl <= z; dl < 65536}{lb:agz}{n:pos}{so,sl:nat | so + sl <= n}{i:nat}
  (s: int, z: int z, no: int no, dl: int dl,
   data: !$A.borrow(byte, lb, n), n: int n, idx: int i, so: int so, sl: int sl, gen: int): void = let
  val h = src_end(data, so, sl)
in
  (* An src of 65536 bytes or more names no zip entry (a zip name is
     shorter): the book's data, checked here *)
  if h <= 0 then ()
  else if h >= 65536 then ()
  else let
    val m = dl + h
    val buf = $A.alloc<byte>(m)
    val _ = book_read(s, z, no, buf, dl)
    val () = $S.copy_from_borrow(data, so, n, buf, dl, m, h)
    val k = path_norm(buf, m)
  in
    if k <= 0 then $A.free<byte>(buf)
    else let
      val exact = $A.alloc<byte>(k)
      val buf = $S.copy_arr_region(buf, 0, m, exact, k, k)
      val () = $A.free<byte>(buf)
      val @(fz, bv) = $A.freeze<byte>(exact)
      val () = _show_image(s, z, idx, gen, bv, k)
      val () = $A.drop<byte>(fz, bv)
    in $A.free<byte>($A.thaw<byte>(fz)) end
  end
end

(* The images xs of the chapter data[0, n) *)
fun _load_images {z:pos}{no,dl:nat | no + dl <= z; dl < 65536}{lb:agz}{n:pos}{k:nat} .<k>.
  (s: int, z: int z, no: int no, dl: int dl,
   data: !$A.borrow(byte, lb, n), n: int n, xs: imgs(n, k), gen: int): void =
  case+ xs of
  | ~imgs_nil() => ()
  | ~imgs_cons(idx, so, sl, tl) => let
      val () = _load_image(s, z, no, dl, data, n, idx, so, sl, gen)
    in _load_images(s, z, no, dl, data, n, tl, gen) end

(* The chapters from spine itemref i down to the first, onto acc: each
   href, after the OPF's directory (prefix_len bytes of the name at
   opf_no), found in book s's index; the OPF's data checked here, once *)
fun _spine_chapters {z:pos}{ono:nat}{pl:nat | ono + pl <= z; pl < 65536}
  {lb:agz}{n:pos}{sz:nat}{i:int | i >= ~1}{a:nat} .<i + 1>.
  (s: int, z: int z, opf_no: int ono, prefix_len: int pl,
   opf_b: !$A.borrow(byte, lb, n), dc_sz: int n, nodes: !$X.xml_node_list(n, sz),
   i: int i, acc: book_chapters(z, a)): book_chapters(z, a + i + 1) =
  if i < 0 then acc
  else let
    val ch = (case+ find_chapter_href_n(opf_b, dc_sz, nodes, i) of
      | ~xspan_none() => ChapterMissing(acc)
      | ~xspan_at(ch_off, ch_len) =>
        if ch_len <= 0 then ChapterMissing(acc)
        else if prefix_len + ch_len > 1048576 then ChapterMissing(acc)
        else let
          val full_len = prefix_len + ch_len
          val ch_buf = $A.alloc<byte>(full_len)
          (* The prefix read from the file at the OPF's name, then the
             chapter href from the OPF *)
          val _ = book_read(s, z, opf_no, ch_buf, prefix_len)
          val () = $S.copy_from_borrow(opf_b, ch_off, dc_sz,
                    ch_buf, prefix_len, full_len, ch_len)
          val @(chf, chb) = $A.freeze<byte>(ch_buf)
          val hit = book_find_entry(s, z, chb, full_len)
          val () = $A.drop<byte>(chf, chb)
          val () = $A.free<byte>($A.thaw<byte>(chf))
        in
          case+ hit of
          | ~EntryMiss() => ChapterMissing(acc)
          | ~EntryHit(d, cs, m, no, nl) =>
              Chapter(d, cs, m, no, nl, _opf_prefix_len(s, z, no, nl), acc)
        end): book_chapters(z, a + 1)
  in _spine_chapters(s, z, opf_no, prefix_len, opf_b, dc_sz, nodes, i - 1, ch) end

(* Finds book s's chapters from its OPF and keeps them in the book: its
   chapter count, or below 0 when the OPF cannot be read *)
fn _spine_build (serial: int): $P.promise(int, $P.Chained) =
  case+ book_meta_get() of
  | ~$R.none() => $P.ret<int>(~1)
  | ~$R.some(@(fsz_s, opf_doff, opf_csz, opf_comp, opf_name_off, opf_name_len)) =>
    (* The OPF's compressed bytes, read at their span into a piece *)
    (case+ piece_new(opf_csz) of
     | ~NoPiece() => $P.ret<int>(~1)
     | ~Piece(car, opf_cbuf) => let
         val _ = book_read(serial, fsz_s, opf_doff, opf_cbuf, opf_csz)
         val @(ocf, ocb) = $A.freeze<byte>(opf_cbuf)
         val dc_p = $DC.decompress(ocb, opf_csz, opf_comp)
         val () = $A.drop<byte>(ocf, ocb)
         val () = piece_free(car, $A.thaw<byte>(ocf))
         val dc_p = $P.vow(dc_p)
       in
         $P.and_then<Int><int>(dc_p, lam(dc_handle) =>
           case+ take_content(dc_handle) of
           | ~NoContentBytes() => $P.ret<int>(~2)
           | ~ContentBytes(par, opf_buf, dc_sz) => let
               val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
               val opf_nodes = $X.parse_document(opf_b, dc_sz)
               val total = count_spine_items(opf_b, opf_nodes)
               (* The OPF's directory, e.g. "OEBPS/" of "OEBPS/content.opf",
                  prefixes chapter hrefs *)
               val prefix_len = _opf_prefix_len(serial, fsz_s, opf_name_off, opf_name_len)
               val chs = _spine_chapters(serial, fsz_s, opf_name_off, prefix_len,
                           opf_b, dc_sz, opf_nodes, total - 1, ChaptersNil())
               val () = book_spine_set(serial, fsz_s, chs, total)
               val () = toc_locate(serial, fsz_s, opf_name_off, prefix_len, opf_b, dc_sz, opf_nodes)
               val () = $X.free_nodes(opf_nodes)
               val () = $A.drop<byte>(opf_f, opf_b)
               val () = piece_free(par, $A.thaw<byte>(opf_f))
             in $P.ret<int>(total) end)
       end)

(* Shows chapter chapter_idx of book serial, from its chapters *)
fn _chapter_open {i:nat} (serial: int, chapter_idx: int i, gen: int): $P.promise(int, $P.Chained) =
  case+ book_chapter_get(serial, chapter_idx) of
  | ~ChaptersUnknown() => $P.ret<int>(~1)
  | ~ChapterNone(total_ch) => let
      val () = (case+ reading_get() of
        | @(p, t, c, _) => reading_set(@(p, t, c, total_ch)))
    in $P.ret<int>(~4) end
  | ~ChapterGot(fsz_s, ch_d, ch_csz, ch_method, ch_no, _, ch_dl, total_ch) => let
      val () = (case+ reading_get() of
        | @(p, t, c, _) => reading_set(@(p, t, c, total_ch)))
    in
      case+ piece_new(ch_csz) of
      | ~NoPiece() => $P.ret<int>(~5)
      | ~Piece(ccar, ch_comp) => let
              val _ = book_read(serial, fsz_s, ch_d, ch_comp, ch_csz)
              val @(ccf, ccb) = $A.freeze<byte>(ch_comp)
              val ch_dc_p = $DC.decompress(ccb, ch_csz, ch_method)
              val () = $A.drop<byte>(ccf, ccb)
              val () = piece_free(ccar, $A.thaw<byte>(ccf))

              val ch_dc_p = $P.vow(ch_dc_p)
            in
              (* Stage 3: parse HTML and render *)
              $P.and_then<Int><int>(ch_dc_p, lam(ch_dc_handle) => let
                val ch_dc = take_content(ch_dc_handle)
              in
                case+ ch_dc of
                | ~NoContentBytes() => $P.ret<int>(~6)
                | ~ContentBytes(xar, ch_xhtml, ch_dc_sz) => let

                  (* Parse XHTML with xml-tree *)
                  val @(xf, xb) = $A.freeze<byte>(ch_xhtml)
                  val nodes = $X.parse_document(xb, ch_dc_sz)

                  (* Clear the content area, then render the XHTML tree
                     into it: one document for the chapter *)
                  val doc = $D.open_document($A.text_lit("bats-root"), 9)
                  val @(qa, ql) = _node_id(~1)
                  val @(fq, bq) = $A.freeze<byte>(qa)
                  val () = $D.remove_children(doc, bq, ql)
                  val () = $A.drop<byte>(fq, bq)
                  val () = $A.free<byte>($A.thaw<byte>(fq))
                  val () = !_content_n := 0
                  val fr = _frag_take()
                  val imgs = _render_nodes(doc, xb, ch_dc_sz, ~1, nodes, imgs_nil(), fr)
                  val () = _frag_put(fr)
                  val () = $D.destroy(doc)
                  val () = $X.free_nodes(nodes)
                  (* Its images, named relative to the chapter's directory *)
                  val () = _load_images(serial, fsz_s, ch_no, ch_dl, xb, ch_dc_sz, imgs, gen)
                  val () = $A.drop<byte>(xf, xb)
                  val () = piece_free(xar, $A.thaw<byte>(xf))

                  val () = (case+ reading_get() of
                    | @(p, t, _, tc) => reading_set(@(p, t, chapter_idx + 1, tc)))
                  (* The chapter's title in the top bar *)
                  val () = toc_title(chapter_idx)
                  val () = (case+ reading_get() of @(_, _, _, tc) => _ticks_show(tc))
                  val () = _measure_pagination()
                in $P.ret<int>(0) end
              end)
            end
    end

(* Loads chapter chapter_idx: first the book's chapters, from its OPF,
   when they are not found yet *)
fn _load_chapter {i:nat} (chapter_idx: int i): $P.promise(int, $P.Chained) = let
  val serial = book_serial()
  val () = !_load_gen := !_load_gen + 1
  val gen = !_load_gen
in
  case+ book_chapter_get(serial, chapter_idx) of
  | ~ChaptersUnknown() =>
    $P.and_then<int><int>(_spine_build(serial), lam(r) =>
      if r < 0 then $P.ret<int>(r)
      else $P.and_then<int><int>(toc_build(serial), lam(_) => _chapter_open(serial, chapter_idx, gen)))
  | ~ChapterNone(_) => _chapter_open(serial, chapter_idx, gen)
  | ~ChapterGot(_, _, _, _, _, _, _, _) => _chapter_open(serial, chapter_idx, gen)
end

(* Shows the page of the chapter just loaded that target names: the
   page content node anchor is on (anchor >= 0), else page pg (the last
   when pg is -1 or past the chapter's end) *)
fn _show_target (pg: Int, anchor: Int): void =
  case+ reading_get() of
  | @(cur, t, c, tc) =>
    if anchor >= 0 then _show_page(_page_of_node(anchor, t, cur), t, c, tc)
    else if pg < 0 then _show_page(t - 1, t, c, tc)
    else if pg >= t then _show_page(t - 1, t, c, tc)
    else _show_page(pg, t, c, tc)

(* Loads chapter ch (from 0) and shows its page pg, or the page of
   content node anchor (see _show_target); the promise resolves with 0,
   or below 0 when the chapter cannot be shown *)
fn _goto (ch: Int, pg: Int, anchor: Int): $P.promise(int, $P.Chained) = let
  val ch = (if ch >= 0 then ch else 0): [v:nat] int v
in
  $P.and_then<int><int>(_load_chapter(ch), lam(r) =>
    if r < 0 then $P.ret<int>(r)
    else let val () = _show_target(pg, anchor) in $P.ret<int>(0) end)
end

(* Loads chapter ch and shows the page of its element whose id is
   fr[0, f) (the first page when there is none); frees fr *)
fn _goto_frag {l:agz}{n:pos}{f:nat | f < n} (ch: Int, fr: $A.arr(byte, l, n), f: int f): $P.promise(int, $P.Chained) =
  if f <= 0 then let
    val () = $A.free<byte>(fr)
  in _goto(ch, 0, ~1) end
  else let
    val () = _frag_put(FragSome(fr, f))
    val () = !_frag_hit := ~1
    val ch = (if ch >= 0 then ch else 0): [v:nat] int v
  in
    $P.and_then<int><int>(_load_chapter(ch), lam(r) => let
      val () = _frag_put(FragNone())
    in
      if r < 0 then $P.ret<int>(r)
      else let val () = _show_target(0, !_frag_hit) in $P.ret<int>(0) end
    end)
  end

(* The positions jumped away from (a contents entry, a link, a search
   result), the latest first: the back button returns to them *)
datavtype pstack(int) =
  | ps_nil(0) of ()
  | {k:nat} ps_cons(k + 1) of (Int, Int, Int, pstack(k))

fun ps_free {k:nat} .<k>. (p: pstack(k)): void =
  case+ p of
  | ~ps_nil() => ()
  | ~ps_cons(_, _, _, r) => ps_free(r)

(* The first j of p *)
fun ps_keep {k:nat}{j:nat} .<k>. (p: pstack(k), j: int j): [m:nat] pstack(m) =
  case+ p of
  | ~ps_nil() => ps_nil()
  | ~ps_cons(c, g, a, r) =>
    if j <= 0 then let val () = ps_free(r) in ps_nil() end
    else ps_cons(c, g, a, ps_keep(r, j - 1))

datavtype ps_cell = {k:nat} PsCell of pstack(k)

val _ps = ref<ps_cell>(PsCell(ps_nil()))

fn _ps_take (): ps_cell = let
  var c: ps_cell = PsCell(ps_nil())
  val () = ref_exch_elt<ps_cell>(_ps, c)
in c end

fn _ps_put (c: ps_cell): void = let
  var cur: ps_cell = c
  val () = ref_exch_elt<ps_cell>(_ps, cur)
  val+ ~PsCell(p) = cur
in ps_free(p) end

(* Remembers where the reader is, before a jump *)
fn _push_position (): void = let
  val anchor = _anchor_now()
  val+ ~PsCell(p) = _ps_take()
  val p = (case+ reading_get() of
    | @(pg, _, c, _) => ps_cons((if c > 0 then c - 1 else 0), pg, anchor, ps_keep(p, 29))): [m:nat] pstack(m)
  val () = _ps_put(PsCell(p))
in ui_show("qpbk", true) end

(* Returns to the position last jumped away from *)
fn _pop_position (): void = let
  val+ ~PsCell(p) = _ps_take()
in
  case+ p of
  | ~ps_nil() => let
      val () = _ps_put(PsCell(ps_nil()))
    in ui_show("qpbk", false) end
  | ~ps_cons(c, g, a, rest) => let
      val empty = (case+ rest of ps_nil() => true | ps_cons(_, _, _, _) => false): bool
      val () = _ps_put(PsCell(rest))
      val () = ui_show("qpbk", ~empty)
    in $P.discard<int>(_goto(c, g, a)) end
end

(* Loads chapter ch and shows its page at thousandth cp of it *)
fn _goto_part (ch: Int, cp: Int): $P.promise(int, $P.Chained) = let
  val ch = (if ch >= 0 then ch else 0): [v:nat] int v
in
  $P.and_then<int><int>(_load_chapter(ch), lam(r) =>
    if r < 0 then $P.ret<int>(r)
    else let
      val () = (case+ reading_get() of
        | @(_, t, _, _) => _show_target(cp * t / 1000, ~1))
    in $P.ret<int>(0) end)
end

(* The next page: in this chapter, else the next chapter's first *)
fn _page_next(): void =
  case+ reading_get() of
  | @(p, t, c, tc) =>
    if p + 1 < t then _show_page(p + 1, t, c, tc)
    else if c < tc then $P.discard<int>(_goto(c, 0, ~1))
    else _show_page(p, t, c, tc)

(* The previous page: in this chapter, else the previous chapter's last *)
fn _page_prev(): void =
  case+ reading_get() of
  | @(p, t, c, tc) =>
    if p > 0 then _show_page(p - 1, t, c, tc)
    else if c > 1 then $P.discard<int>(_goto(c - 2, ~1, ~1))
    else _show_page(0, t, c, tc)

(* Lays the chapter out again (the window or the type changed), keeping
   the page on which the content at the page's top is *)
fn _relayout (): void = let
  val anchor = _anchor_now()
  val () = _measure_pagination()
in _show_target(0, anchor) end

(* ============================================================
   Public API
   ============================================================ *)

#pub fun apply_diff_list(dl: $W.diff_list): void
implement apply_diff_list(dl) = _apply_diff_list(dl)

#pub fun apply_diff(d: $W.diff): void
implement apply_diff(d) = _apply_diff(d)


#pub fun measure_pagination(): void
implement measure_pagination() = _measure_pagination()

#pub fun page_next(): void
implement page_next() = _page_next()

#pub fun page_prev(): void
implement page_prev() = _page_prev()

#pub fun load_chapter {i:nat} (chapter_idx: int i): $P.promise(int, $P.Chained)
implement load_chapter(chapter_idx) = _load_chapter(chapter_idx)








(* Loads chapter ch and shows page pg of it (the last for -1), or the
   page of content node anchor when anchor >= 0 *)
#pub fun reader_goto (ch: Int, pg: Int, anchor: Int): $P.promise(int, $P.Chained)
implement reader_goto (ch, pg, anchor) = _goto(ch, pg, anchor)

(* Jumps to row i of the contents list, remembering where the reader
   was *)
#pub fun reader_goto_entry (i: Int): void
implement reader_goto_entry (i) =
  case+ toc_dest_of(i) of
  | ~TocNoDest() => ()
  | ~TocDest(ch, fr, f) => let
      val () = _push_position()
    in $P.discard<int>(_goto_frag(ch, fr, f)) end

(* Jumps to chapter ch's element fr[0, f), remembering where the reader
   was *)
#pub fun reader_jump {l:agz}{n:pos}{f:nat | f < n} (ch: Int, fr: $A.arr(byte, l, n), f: int f): void
implement reader_jump (ch, fr, f) = let
  val () = _push_position()
in $P.discard<int>(_goto_frag(ch, fr, f)) end

(* Jumps to page pg of chapter ch (the page of content node anchor, when
   it is not -1), remembering where the reader was *)
#pub fun reader_jump_to (ch: Int, pg: Int, anchor: Int): void
implement reader_jump_to (ch, pg, anchor) = let
  val () = _push_position()
in $P.discard<int>(_goto(ch, pg, anchor)) end

(* The back button: to the position last jumped away from *)
#pub fun reader_back (): void
implement reader_back () = _pop_position()

(* Forgets the positions jumped from (a book is opened or closed) *)
#pub fun reader_stack_clear (): void
implement reader_stack_clear () = let
  val () = _ps_put(PsCell(ps_nil()))
in ui_show("qpbk", false) end

(* The scrubber dragged to x: the thumb there, and the title of the
   chapter there in its tip *)
#pub fun reader_scrub_preview (x: Int): void
implement reader_scrub_preview (x) = let
  val v = _track_at(x)
  val () = _scrub_at(v)
  val () = _style_pct("qstt", "left:", v)
  val () = (case+ reading_get() of
    | @(_, _, _, tc) => let
        val @(c, _) = _chapter_at(v, 0, tc)
      in toc_title_in("qstt", c) end)
in ui_show("qstt", true) end

(* The scrubber let go at x: to that place in the book, remembering
   where the reader was *)
#pub fun reader_scrub_go (x: Int): void
implement reader_scrub_go (x) = let
  val v = _track_at(x)
  val () = ui_show("qstt", false)
in
  case+ reading_get() of
  | @(_, _, _, tc) => let
      val @(c, cp) = _chapter_at(v, 0, tc)
      val () = _push_position()
    in $P.discard<int>(_goto_part(c, cp)) end
end

(* Stores where the reader is *)
#pub fun reader_save (): void
implement reader_save () = _record_position()

#pub fun reader_relayout (): void
implement reader_relayout () = _relayout()

(* Shows page p of the chapter shown (clamped to its pages) *)
#pub fun reader_page (p: Int): void
implement reader_page (p) = case+ reading_get() of
  | @(_, t, c, tc) => if p < 0 then _show_page(0, t, c, tc) else if p >= t then _show_page(t - 1, t, c, tc) else _show_page(p, t, c, tc)

#pub fun update_page_indicator(): void
implement update_page_indicator() = _update_page_indicator()


#pub fun num_id {sn:pos | sn <= 3}{i:nat}{w:int | w == 2 || w == 3}
  (pre: string sn, i: int i, w: int w): [l:agz][k:pos | k <= 16] @($A.arr(byte, l, k), int k)
implement num_id(pre, i, w) = _num_id(pre, i, w)

end (* #target wasm *)
