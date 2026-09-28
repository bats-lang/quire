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

staload "epub_xml.sats"
staload "book.sats"
staload "pages.sats"
staload "paths.sats"
staload "ui.sats"
staload "library.sats"
staload "import.sats"
staload "toc.sats"
staload "annot.sats"
staload "entity.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload SC = "wasm.bats-packages.dev/bridge/src/scroll.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"

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
  (* back to the first page, which the reading position now names *)
  val () = $SC.set_scroll_left(cnt_b, 4, 0)
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

(* The content node at x, y (its number), or -1 *)
fn _node_at (x: int, y: int): [v:int | v >= ~1] int v =
  case+ $DR.element_at_point(x, y) of
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

(* The first content node down the middle of the page, from y, in steps
   of 40 px, j more times *)
fun _node_down {j:nat} .<j>. (x: int, y: int, j: int j): [v:int | v >= ~1] int v = let
  val v = _node_at(x, y)
in if v >= 0 then v else if j <= 0 then ~1 else _node_down(x, y + 40, j - 1) end

(* Whether content node i starts in [lo, hi) across the page: on the
   page shown, when that is the page's width *)
fn _starts_in {i:nat} (i: int i, lo: int, hi: int): bool =
  if ~_measure_node(i) then false
  else let val x = $DR.get_measure_x() in x >= lo && x < hi end

(* The first of content nodes i to i + j that starts on the page, [lo,
   hi) across; -1 when none does *)
fun _first_start {i:nat}{j:nat} .<j>. (i: int i, j: int j, lo: int, hi: int): [v:int | v >= ~1] int v =
  if _starts_in(i, lo, hi) then i
  else if j <= 0 then ~1
  else _first_start(i + 1, j - 1, lo, hi)

(* The content node the page shown starts with (its number), or -1: the
   first element down the middle of the page from its first line, or,
   when that one began on a page before (a paragraph carried over), the
   first of the next 40 that begins on this one, so that the page it
   names is this page *)
fn _anchor_now (): [v:int | v >= ~1] int v = let
  val () = _measure_lit("qcnt")
  val cx = $DR.get_measure_x()
  val cy = $DR.get_measure_y()
  val cw = $DR.get_measure_w()
  val v = _node_down(cx + cw / 2, cy + 24, 8)
in
  if v < 0 then v
  else if _starts_in(v, cx - 1, cx + cw) then v
  else let
    val w = _first_start(v + 1, 40, cx - 1, cx + cw)
  in if w >= 0 then w else v end
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

(* The content node at the top of the page last shown: what a new
   layout (another size or type, measured after it changed) keeps in
   view *)
val _anchor_last = ref<Int>(~1)

(* The position read to the open book's record in the library, which is
   then stored *)
fn _record_position (): void = let
  val i = lib_index_of_key(open_key_get())
  val anchor = _anchor_now()
  val () = !_anchor_last := anchor
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
      val () = lib_touch(i)
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
in ui_attr_buf(id, AStyle, b, off) end

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
in ui_attr_buf("qtrk", AValueNow, b, off) end

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
    val () = ui_add_n("qstk", ki, kl, TDiv)
    val @(ki, kl) = nid_make("qk", i)
    val () = ui_attr_n(ki, kl, AClass, "tick")
    val v = _thousandth(b, tot)
    val bb = $A.alloc<byte>(32)
    val off = _put(bb, 0, "left:")
    val off = $S.int_to_str(bb, off, 32, v / 10)
    val off = _put(bb, off, ".")
    val off = $S.int_to_str(bb, off, 32, v - (v / 10) * 10)
    val off = _put(bb, off, "%")
    val @(ki, kl) = nid_make("qk", i)
    val () = ui_attr_n_buf(ki, kl, AStyle, bb, off)
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
  val () = annot_star()
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

(* Element id's text: data[off, off + k) decoded *)
fn _set_decoded {ld,li,lb:agz}{ni:pos | ni < 256}{n:pos}{o,k:nat | o + k <= n; k < 65536; k > 0}
  (doc: !$D.document(ld), bi: !$A.borrow(byte, li, ni), il: int ni,
   data: !$A.borrow(byte, lb, n), off: int o, k: int k): void = let
  val buf = $A.alloc<byte>(k)
  val q = decode_text(data, off, k, buf)
  val @(f, b) = $A.freeze<byte>(buf)
  val () = $D.set_text(doc, bi, il, b, 0, q)
  val () = $A.drop<byte>(f, b)
in $A.free<byte>($A.thaw<byte>(f)) end

(* Content node idx's text: data[off, off + k), its character
   references decoded *)
fn _node_text {ld,lb:agz}{n:pos}{i:nat}{o,k:nat | o + k <= n; k < 65536}
  (doc: !$D.document(ld), idx: int i, data: !$A.borrow(byte, lb, n), off: int o, k: int k): void = let
  val @(ia, il) = _node_id(idx)
  val @(fi, bi) = $A.freeze<byte>(ia)
  val () = (if k <= 0 then $D.set_text(doc, bi, il, data, off, k)
    else if has_reference(data, off, k) then _set_decoded(doc, bi, il, data, off, k)
    else $D.set_text(doc, bi, il, data, off, k))
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

(* Whether data[o + i, o + k) is all white space *)
fun _blank {lb:agz}{n:pos}{o,k:nat | o + k <= n}{i:nat | i <= k} .<k - i>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, i: int i): bool =
  if i >= k then true
  else if byte2int0($A.read<byte>(data, o + i)) > 32 then false
  else _blank(data, o, k, i + 1)

(* The numbers _text_spans would give text of k bytes, taken *)
fun _skip_spans {k:nat} .<k>. (off: int, k: int k): void = let
  val _ = _next_content_idx()
in if k < 65536 then () else _skip_spans(off, k - 65533) end

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
  var q_ = @[char][1]('q')
  var cite = @[char][4]('c', 'i', 't', 'e')
  var abbr = @[char][4]('a', 'b', 'b', 'r')
  var kbd = @[char][3]('k', 'b', 'd')
  var dl = @[char][2]('d', 'l')
  var dt = @[char][2]('d', 't')
  var dd = @[char][2]('d', 'd')
  var caption = @[char][7]('c', 'a', 'p', 't', 'i', 'o', 'n')
  var tfoot = @[char][5]('t', 'f', 'o', 'o', 't')
  var samp = @[char][4]('s', 'a', 'm', 'p')
  var var_ = @[char][3]('v', 'a', 'r')
  var big = @[char][3]('b', 'i', 'g')
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
  else if is(data, a_, 1) then "a" else if is(data, b_, 1) then "b"
  else if is(data, i_, 1) then "i" else if is(data, u_, 1) then "u"
  else if is(data, s_, 1) then "s"
  else if is(data, q_, 1) then "q" else if is(data, cite, 4) then "cite"
  else if is(data, abbr, 4) then "abbr" else if is(data, kbd, 3) then "kbd"
  else if is(data, dl, 2) then "dl" else if is(data, dt, 2) then "dt"
  else if is(data, dd, 2) then "dd" else if is(data, caption, 7) then "caption"
  else if is(data, tfoot, 5) then "tfoot" else if is(data, samp, 4) then "samp"
  else if is(data, var_, 3) then "var" else if is(data, big, 3) then "span"
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

(* dst[j, k) := src[j, k) *)
fun _frag_dup {ls,ld:agz}{ns,nd:pos}{k:nat | k <= ns; k <= nd}{j:nat | j <= k} .<k - j>.
  (src: !$A.arr(byte, ls, ns), dst: !$A.arr(byte, ld, nd), k: int k, j: int j): void =
  if j >= k then ()
  else let
    val () = $A.set<byte>(dst, j, $A.get<byte>(src, j))
  in _frag_dup(src, dst, k, j + 1) end

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
  (* A link within the book: the content nodes [s, e) it covers and its
     href [so, so + sl), found once the chapter is shown *)
  | {k:nat}{s,e:nat}{so,sl:nat | so + sl <= n}
    imgs_link(n, k + 1) of (int s, int e, int so, int sl, imgs(n, k))

(* The links of the chapter shown: the content nodes [s, e) each covers,
   and the chapter (-1 for a link out of the book, which the browser
   opens) and fragment fr[0, f) it leads to *)
datavtype links(int) =
  | links_nil(0) of ()
  | {k:nat}{l:agz}{f:nat | f <= 200}
    links_cons(k + 1) of (Int, Int, Int, $A.arr(byte, l, f + 1), int f, links(k))

fun links_free {k:nat} .<k>. (x: links(k)): void =
  case+ x of
  | ~links_nil() => ()
  | ~links_cons(_, _, _, a, _, r) => let val () = $A.free<byte>(a) in links_free(r) end

datavtype links_cell = {k:nat} LinksCell of links(k)

val _links = ref<links_cell>(LinksCell(links_nil()))

fn _links_take (): links_cell = let
  var c: links_cell = LinksCell(links_nil())
  val () = ref_exch_elt<links_cell>(_links, c)
in c end

fn _links_put (c: links_cell): void = let
  var cur: links_cell = c
  val () = ref_exch_elt<links_cell>(_links, cur)
  val+ ~LinksCell(x) = cur
in links_free(x) end

fn _links_push {l:agz}{f:nat | f <= 200} (s: Int, e: Int, ch: Int, fr: $A.arr(byte, l, f + 1), f: int f): void = let
  val+ ~LinksCell(x) = _links_take()
in _links_put(LinksCell(links_cons(s, e, ch, fr, f, x))) end

(* Whether data[o, o + k) starts with pat *)
fn _starts {lb:agz}{n:pos}{o,k:nat | o + k <= n}{np:pos}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, pat: &(@[char][np]), np: int np): bool =
  if k < np then false else xml_name_eq(data, o, np, pat, np)

(* The attributes of an XHTML element that are kept on its content node:
   dir, lang (and xml:lang), title, colspan and rowspan *)
fun _pass_attrs {ld,lb:agz}{n:pos}{sa:nat}{i:nat} .<sa>.
  (doc: !$D.document(ld), data: !$A.borrow(byte, lb, n), attrs: !$X.xml_attr_list(n, sa), idx: int i): void =
  case+ attrs of
  | $X.xml_attrs_nil() => ()
  | $X.xml_attrs_cons(ao, al, vo, vl, rest) => let
      var _dir = @[char][3]('d', 'i', 'r')
      var _lang = @[char][4]('l', 'a', 'n', 'g')
      var _xlang = @[char][8]('x', 'm', 'l', ':', 'l', 'a', 'n', 'g')
      var _title = @[char][5]('t', 'i', 't', 'l', 'e')
      var _colspan = @[char][7]('c', 'o', 'l', 's', 'p', 'a', 'n')
      var _rowspan = @[char][7]('r', 'o', 'w', 's', 'p', 'a', 'n')
      val () = (if vl >= 65536 then ()
        else if xml_name_eq(data, ao, al, _dir, 3) then _node_attr(doc, idx, "dir", data, vo, vl)
        else if xml_name_eq(data, ao, al, _lang, 4) then _node_attr(doc, idx, "lang", data, vo, vl)
        else if xml_name_eq(data, ao, al, _xlang, 8) then _node_attr(doc, idx, "lang", data, vo, vl)
        else if xml_name_eq(data, ao, al, _title, 5) then _node_attr(doc, idx, "title", data, vo, vl)
        else if xml_name_eq(data, ao, al, _colspan, 7) then _node_attr(doc, idx, "colspan", data, vo, vl)
        else if xml_name_eq(data, ao, al, _rowspan, 7) then _node_attr(doc, idx, "rowspan", data, vo, vl)
        else ())
    in _pass_attrs(doc, data, rest, idx) end

(* An <a> element, content nodes [idx, e): a link out of the book (http,
   https, mailto) is made a real one, opened in a new tab; a link within
   it is kept in acc, found once the chapter is shown *)
fn _link {ld,lb:agz}{n:pos}{sa:nat}{i,e:nat}{k:nat}
  (doc: !$D.document(ld), data: !$A.borrow(byte, lb, n), attrs: !$X.xml_attr_list(n, sa),
   idx: int i, e: int e, acc: imgs(n, k)): [k2:nat] imgs(n, k2) = let
  var _href = @[char][4]('h', 'r', 'e', 'f')
in
  case+ find_attr(data, attrs, _href, 4) of
  | ~xspan_none() => acc
  | ~xspan_at(so, sl) => let
      var _http = @[char][7]('h', 't', 't', 'p', ':', '/', '/')
      var _https = @[char][8]('h', 't', 't', 'p', 's', ':', '/', '/')
      var _mailto = @[char][7]('m', 'a', 'i', 'l', 't', 'o', ':')
      val out = (if _starts(data, so, sl, _http, 7) then true
        else if _starts(data, so, sl, _https, 8) then true
        else _starts(data, so, sl, _mailto, 7)): bool
    in
      if out then
        (if sl < 65536 then let
           val () = _node_attr(doc, idx, "href", data, so, sl)
           val () = _node_attr_lit(doc, idx, "target", "_blank")
           val () = _node_attr_lit(doc, idx, "rel", "noopener noreferrer")
           val () = _links_push(idx, e, ~1, $A.alloc<byte>(1), 0)
         in acc end
         else acc)
      else let
        (* announced and reached from the keyboard as a link *)
        val () = _node_attr_lit(doc, idx, "role", "link")
        val () = _node_attr_lit(doc, idx, "tabindex", "0")
      in imgs_link(idx, e, so, sl, acc) end
    end
end

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
      (* white space between the page's blocks takes its numbers but
         makes no element: it would be a line of its own *)
      val () = (if pidx < 0 then (if _blank(data, off, tlen, 0) then _skip_spans(off, tlen)
          else _text_spans(doc, data, pidx, off, tlen))
        else _text_spans(doc, data, pidx, off, tlen))
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
      val () = _pass_attrs(doc, data, attrs, idx)
      var _t_a = @[char][1]('a')
    in
      if xml_name_eq(data, name_off, name_len, _t_a, 1) then let
        val acc = _render_nodes(doc, data, len, idx, children, acc, fr)
      in _link(doc, data, attrs, idx, !_content_n, acc) end
      else _render_nodes(doc, data, len, idx, children, acc, fr)
    end
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

(* The length of the fragment after the '#' at h of an href of hl
   bytes: 0 when there is none, or it is over 200 bytes *)
fn _frag_len {hl,h:nat | h <= hl} (hl: int hl, h: int h): [f:nat | f <= 200; f == 0 || f == hl - h - 1] int f =
  if hl - h - 1 <= 0 then 0
  else if hl - h - 1 > 200 then 0
  else hl - h - 1

(* fr[0, f) := data[ho + h + 1, ho + h + 1 + f) *)
fn _frag_copy {lb,l:agz}{n:pos}{ho,h,f:nat | f == 0 || ho + h + 1 + f <= n}
  (data: !$A.borrow(byte, lb, n), n: int n, ho: int ho, h: int h, fr: !$A.arr(byte, l, f + 1), f: int f): void =
  if f > 0 then $S.copy_from_borrow(data, ho + h + 1, n, fr, 0, f + 1, f) else ()

(* The link to data[so, so + sl) from content nodes [s, e) of chapter
   cur, whose directory is the first dl bytes of the name at no: kept
   with the chapter and fragment it leads to *)
fn _link_resolve {z:pos}{no,dl:nat | no + dl <= z; dl < 65536}{lb:agz}{n:pos}{so,sl:nat | so + sl <= n}
  (s: int, z: int z, no: int no, dl: int dl, cur: Int,
   data: !$A.borrow(byte, lb, n), n: int n, s0: Int, e0: Int, so: int so, sl: int sl): void = let
  val h = src_end(data, so, sl)
  val ch = (if h <= 0 then cur
    else (case+ book_find_relative(s, z, no, dl, data, n, so, h) of
      | ~EntryHit(_, _, _, eno, _) => book_chapter_of(s, eno)
      | ~EntryMiss() => ~1)): Int
  val f = _frag_len(sl, h)
  val fr = $A.alloc<byte>(f + 1)
  val () = _frag_copy(data, n, so, h, fr, f)
in
  if ch >= 0 then _links_push(s0, e0, ch, fr, f) else $A.free<byte>(fr)
end

(* The images xs of the chapter data[0, n), chapter cur, and its links *)
fun _load_images {z:pos}{no,dl:nat | no + dl <= z; dl < 65536}{lb:agz}{n:pos}{k:nat} .<k>.
  (s: int, z: int z, no: int no, dl: int dl,
   data: !$A.borrow(byte, lb, n), n: int n, xs: imgs(n, k), gen: int, cur: Int): void =
  case+ xs of
  | ~imgs_nil() => ()
  | ~imgs_cons(idx, so, sl, tl) => let
      val () = _load_image(s, z, no, dl, data, n, idx, so, sl, gen)
    in _load_images(s, z, no, dl, data, n, tl, gen, cur) end
  | ~imgs_link(s0, e0, so, sl, tl) => let
      val () = _link_resolve(s, z, no, dl, cur, data, n, s0, e0, so, sl)
    in _load_images(s, z, no, dl, data, n, tl, gen, cur) end

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

(* ============================================================
   The book's own font, for the "Book" font setting
   ============================================================ *)

(* Whether the book reads right to left *)
val _rtl = ref<bool>(false)

datavtype font_src =
  | {z:pos}{d:nat}{s:pos | d + s <= z; s <= 268435456}{m:int | m == 0 || m == 8}
    FontSrc of (int z, int d, int s, int m)
  | FontNone of ()

val _font = ref<font_src>(FontNone())

fn _font_put (f: font_src): void = let
  var c: font_src = f
  val () = ref_exch_elt<font_src>(_font, c)
in case+ c of ~FontSrc(_, _, _, _) => () | ~FontNone() => () end

fn _font_take (): font_src = let
  var c: font_src = FontNone()
  val () = ref_exch_elt<font_src>(_font, c)
in c end

(* The book's first embedded font, named in the OPF opf_b[0, n) (whose
   directory is the first pl bytes of the name at opf_no) *)
fn _font_locate {z:pos}{ono:nat}{pl:nat | ono + pl <= z; pl < 65536}{lb:agz}{n:pos}{sz:nat}
  (s: int, z: int z, opf_no: int ono, pl: int pl,
   opf_b: !$A.borrow(byte, lb, n), n: int n, nodes: !$X.xml_node_list(n, sz)): void =
  case+ find_font_href(opf_b, nodes) of
  | ~xspan_none() => _font_put(FontNone())
  | ~xspan_at(ho, hl) =>
    (case+ book_find_relative(s, z, opf_no, pl, opf_b, n, ho, hl) of
     | ~EntryHit(d, cs, m, _, _) => _font_put(FontSrc(z, d, cs, m))
     | ~EntryMiss() => _font_put(FontNone()))

(* b[p + j, p + k) := u[j, k) *)
fun _copy_at {ls,ld:agz}{ns,nd:pos}{p:nat}{k:nat | k <= ns; p + k <= nd}{j:nat | j <= k} .<k - j>.
  (u: !$A.arr(byte, ls, ns), b: !$A.arr(byte, ld, nd), p: int p, k: int k, j: int j): void =
  if j >= k then ()
  else let
    val () = $A.set<byte>(b, p + j, $A.get<byte>(u, j))
  in _copy_at(u, b, p, k, j + 1) end

(* The style that names the font at the blob URL u[0, k) QuireBook, the
   family the "Book" setting asks for *)
fn _font_style {k:pos | k < 2000}{l:agz}{m:pos | k <= m} (u: !$A.arr(byte, l, m), k: int k): void = let
  val n = k + 80
  val b = $A.alloc<byte>(n)
  val off = _put(b, 0, "@font-face{font-family:QuireBook;src:url(")
  val () = _copy_at(u, b, off, k, 0)
  val off = _put(b, off + k, ")}.caf{--bookfont:QuireBook}")
in ui_text_buf("qfnt", b, off) end

(* Makes the font found by _font_locate the book font (or none) *)
fn _font_load (s: int): $P.promise(int, $P.Chained) = let
  val () = ui_clear("qfnt")
in
  case+ _font_take() of
  | ~FontNone() => $P.ret<int>(0)
  | ~FontSrc(z, d, cs, m) =>
    (case+ piece_new(cs) of
     | ~NoPiece() => $P.ret<int>(0)
     | ~Piece(car, cbuf) => let
         val _ = book_read(s, z, d, cbuf, cs)
         val @(cf, cb) = $A.freeze<byte>(cbuf)
         val dp = $DC.decompress(cb, cs, m)
         val () = $A.drop<byte>(cf, cb)
         val () = piece_free(car, $A.thaw<byte>(cf))
       in
         $P.and_then<Int><int>($P.vow(dp), lam(h) =>
           case+ take_content(h) of
           | ~NoContentBytes() => $P.ret<int>(0)
           | ~ContentBytes(par, buf, n) => let
               val ma = $A.alloc<byte>(8)
               val _ = _put(ma, 0, "font/otf")
               val @(mf, mb) = $A.freeze<byte>(ma)
               val @(f, b) = $A.freeze<byte>(buf)
               val url = $BL.create_blob_url(b, n, mb, 8)
               val () = $A.drop<byte>(f, b)
               val () = piece_free(par, $A.thaw<byte>(f))
               val () = $A.drop<byte>(mf, mb)
               val () = $A.free<byte>($A.thaw<byte>(mf))
               val () = (case+ url of
                 | ~$R.none() => ()
                 | ~$R.some(ub) => let
                     val k = $DC.blob_len(ub)
                   in
                     (* the host's URL, checked here *)
                     if k <= 0 then $DC.blob_free(ub)
                     else if k >= 2000 then $DC.blob_free(ub)
                     else let
                       val ua = $A.alloc<byte>(k)
                       val () = $DC.blob_read(ub, 0, ua, k)
                       val () = $DC.blob_free(ub)
                       val () = _font_style(ua, k)
                     in $A.free<byte>(ua) end
                   end)
             in $P.ret<int>(0) end)
       end)
end

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
               val () = !_rtl := spine_rtl(opf_b, opf_nodes)
               val () = _font_locate(serial, fsz_s, opf_name_off, prefix_len, opf_b, dc_sz, opf_nodes)
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
                  val () = _links_put(LinksCell(links_nil()))
                  val () = (if !_rtl then ui_attr("qcnt", AClass, "caf rtl") else ui_attr("qcnt", AClass, "caf"))
                  val fr = _frag_take()
                  val imgs = _render_nodes(doc, xb, ch_dc_sz, ~1, nodes, imgs_nil(), fr)
                  val () = _frag_put(fr)
                  val () = $D.destroy(doc)
                  val () = $X.free_nodes(nodes)
                  (* Its images, named relative to the chapter's directory *)
                  val () = _load_images(serial, fsz_s, ch_no, ch_dl, xb, ch_dc_sz, imgs, gen, chapter_idx)
                  val () = $A.drop<byte>(xf, xb)
                  val () = piece_free(xar, $A.thaw<byte>(xf))

                  val () = (case+ reading_get() of
                    | @(p, t, _, tc) => reading_set(@(p, t, chapter_idx + 1, tc)))
                  (* The chapter's title in the top bar *)
                  val () = toc_title(chapter_idx)
                  val () = (case+ reading_get() of @(_, _, _, tc) => _ticks_show(tc))
                  val () = _measure_pagination()
                  val () = annot_marks()
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
      else $P.and_then<int><int>(toc_build(serial), lam(_) =>
        $P.and_then<int><int>(_font_load(serial), lam(_) => _chapter_open(serial, chapter_idx, gen))))
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
  val anchor = !_anchor_last
  val pg = (case+ reading_get() of @(p, _, _, _) => p): Int
  val () = _measure_pagination()
in _show_target(pg, anchor) end

(* ============================================================
   Search: every chapter's text, for the query
   ============================================================ *)

(* A search walks each chapter as _render_nodes shows it, numbering its
   content nodes the same way (the two must stay in step), and finds the
   query in each text node's text as the page shows it (its references
   decoded), letters in any case. A hit is its chapter, content node and
   offset, with the text around it. *)

#define HMAX 500

datavtype hits(int) =
  | hits_nil(0) of ()
  | {k:nat}{l:agz}{sl:nat | sl <= 206}
    hits_cons(k + 1) of (Int, Int, Int, $A.arr(byte, l, sl + 1), int sl, hits(k))

fun hits_free {k:nat} .<k>. (x: hits(k)): void =
  case+ x of
  | ~hits_nil() => ()
  | ~hits_cons(_, _, _, a, _, r) => let val () = $A.free<byte>(a) in hits_free(r) end

fun hits_rev {k,j:nat} .<k>. (x: hits(k), acc: hits(j)): hits(k + j) =
  case+ x of
  | ~hits_nil() => acc
  | ~hits_cons(c, n, o, a, sl, r) => hits_rev(r, hits_cons(c, n, o, a, sl, acc))

(* The hits so far (the latest first while a search runs), their count,
   the query q[0, qn) (lower case) and the search's number *)
datavtype search_cell =
  | {k:nat | k <= HMAX}{l:agz}{qn:pos | qn <= 200} SearchCell of (hits(k), int k, $A.arr(byte, l, qn), int qn)
  | SearchNone of ()

val _search = ref<search_cell>(SearchNone())
val _search_gen = ref<int>(0)
(* The hit shown, and whether a hit was jumped to since the search opened *)
val _hit_cur = ref<Int>(~1)
val _hit_jumped = ref<bool>(false)

fn _search_free (c: search_cell): void =
  case+ c of
  | ~SearchCell(h, _, q, _) => let val () = hits_free(h) in $A.free<byte>(q) end
  | ~SearchNone() => ()

fn _search_take (): search_cell = let
  var c: search_cell = SearchNone()
  val () = ref_exch_elt<search_cell>(_search, c)
in c end

fn _search_put (c: search_cell): void = let
  var cur: search_cell = c
  val () = ref_exch_elt<search_cell>(_search, cur)
in _search_free(cur) end

(* b, in lower case when it is an ASCII capital *)
fn _lower (b: int): int = if b >= 65 then (if b <= 90 then b + 32 else b) else b

(* Whether t[j, j + qn) is q[0, qn), letters in any case *)
fun _match_at {lt,lq:agz}{nt,nq:pos}{j:nat}{qn:nat | qn <= nq; j + qn <= nt}{i:nat | i <= qn} .<qn - i>.
  (t: !$A.arr(byte, lt, nt), j: int j, q: !$A.arr(byte, lq, nq), qn: int qn, i: int i): bool =
  if i >= qn then true
  else if _lower(byte2int0($A.get<byte>(t, j + i))) <> byte2int0($A.get<byte>(q, i)) then false
  else _match_at(t, j, q, qn, i + 1)

(* The start of the UTF-8 character at or after j in t[0, n), no further
   than e *)
fun _char_fwd {l:agz}{m:pos}{j,e:nat | j <= e; e <= m} .<e - j>.
  (t: !$A.arr(byte, l, m), j: int j, e: int e): [r:nat | j <= r; r <= e] int r =
  if j >= e then e
  else if $AR.band_int_int(byte2int0($A.get<byte>(t, j)), 192) <> 128 then j
  else _char_fwd(t, j + 1, e)

(* e, or less (no less than lo), so that t[.., e) ends before a
   character's start *)
fun _char_back_loop {l:agz}{m:pos}{lo,e:nat | lo <= e; e <= m} .<e - lo>.
  (t: !$A.arr(byte, l, m), m: int m, e: int e, lo: int lo): [r:nat | lo <= r; r <= e] int r =
  if e <= lo then lo
  else if e >= m then e
  else if $AR.band_int_int(byte2int0($A.get<byte>(t, e)), 192) <> 128 then e
  else _char_back_loop(t, m, e - 1, lo)

(* t[s, s + sl) into a from d, its control characters as spaces *)
fun _snip_copy {l,la:agz}{m,ma:pos}{s,sl:nat | s + sl <= m}{d:nat | d + sl < ma}{i:nat | i <= sl} .<sl - i>.
  (t: !$A.arr(byte, l, m), s: int s, a: !$A.arr(byte, la, ma), d: int d, sl: int sl, i: int i): void =
  if i >= sl then ()
  else let
    val b = byte2int0($A.get<byte>(t, s + i))
    val () = $A.set<byte>(a, d + i, (if b < 32 then $A.int2byte(32) else $A.get<byte>(t, s + i)))
  in _snip_copy(t, s, a, d, sl, i + 1) end

(* An ellipsis (U+2026, 3 bytes) at a[d, d + 3) *)
fn _ellipsis {la:agz}{ma:pos}{d:nat | d + 3 <= ma} (a: !$A.arr(byte, la, ma), d: int d): void = let
  val () = $A.set<byte>(a, d, $A.int2byte(226))
  val () = $A.set<byte>(a, d + 1, $A.int2byte(128))
in $A.set<byte>(a, d + 2, $A.int2byte(166)) end

(* An ellipsis at a[d, d + p) when p is 3; nothing when it is 0 *)
fn _ellipsis_if {la:agz}{ma:pos}{d:nat}{p:int | p == 0 || p == 3; d + p <= ma}
  (a: !$A.arr(byte, la, ma), d: int d, p: int p): void =
  if p > 0 then _ellipsis(a, d) else ()

(* e - s, at most 200 *)
fn _span200 {s,e:nat | s <= e} (s: int s, e: int e): [c:nat | c <= 200; s + c <= e] int c =
  if e - s <= 200 then e - s else 200

(* The text around t[j, j + qn) in t[0, n): some 40 bytes before it and
   80 after, whole characters, its line breaks as spaces, with an
   ellipsis on a side where the text goes on *)
fn _snippet {l:agz}{m:pos}{n:nat | n <= m}{j,qn:nat | j + qn <= n}
  (t: !$A.arr(byte, l, m), m: int m, n: int n, j: int j, qn: int qn): [la:agz][sl:nat | sl <= 206] @($A.arr(byte, la, sl + 1), int sl) = let
  val s0 = (if j > 40 then j - 40 else 0): [s:nat | s <= j] int s
  val s = _char_fwd(t, s0, j)
  val e0 = (if j + qn + 80 < n then j + qn + 80 else n): [e:nat | j + qn <= e; e <= n] int e
  val e = _char_back_loop(t, m, e0, j + qn)
  val sl = _span200(s, e)
  val pre = (if s > 0 then 3 else 0): [p:int | p == 0 || p == 3] int p
  val post = (if s + sl < n then 3 else 0): [p:int | p == 0 || p == 3] int p
  val a = $A.alloc<byte>(pre + sl + post + 1)
  val () = _ellipsis_if(a, 0, pre)
  val () = _snip_copy(t, s, a, pre, sl, 0)
  val () = _ellipsis_if(a, pre + sl, post)
in @(a, pre + sl + post) end

(* The hits of the query in t[j, n), content node idx of chapter ch,
   onto acc, while there are fewer than HMAX *)
fun _find_all {lt,lq:agz}{mt,nq:pos}{n:nat | n <= mt}{qn:pos | qn <= nq}{j:nat}{k:nat | k <= HMAX} .<max(n - j, 0)>.
  (t: !$A.arr(byte, lt, mt), mt: int mt, n: int n, j: int j, q: !$A.arr(byte, lq, nq), qn: int qn,
   ch: Int, idx: Int, acc: hits(k), k: int k): [k2:nat | k2 <= HMAX] @(hits(k2), int k2) =
  if k >= HMAX then @(acc, k)
  else if j + qn > n then @(acc, k)
  else if _match_at(t, j, q, qn, 0) then let
    val @(a, sl) = _snippet(t, mt, n, j, qn)
  in _find_all(t, mt, n, j + qn, q, qn, ch, idx, hits_cons(ch, idx, j, a, sl, acc), k + 1) end
  else _find_all(t, mt, n, j + 1, q, qn, ch, idx, acc, k)

(* The hits in text data[off, off + k), content node idx, decoded *)
fn _scan_piece {lb,lq:agz}{n:pos}{o,m:nat | o + m <= n; m < 65536}{nq:pos}{qn:pos | qn <= nq}{r:nat | r <= HMAX}
  (data: !$A.borrow(byte, lb, n), off: int o, m: int m, q: !$A.arr(byte, lq, nq), qn: int qn,
   ch: Int, idx: Int, acc: hits(r), r: int r): [r2:nat | r2 <= HMAX] @(hits(r2), int r2) =
  if m <= 0 then @(acc, r)
  else let
    val buf = $A.alloc<byte>(m)
    val d = decode_text(data, off, m, buf)
    val res = _find_all(buf, m, d, 0, q, qn, ch, idx, acc, r)
    val () = $A.free<byte>(buf)
  in res end

(* The pieces of text data[off, off + k), as _text_spans makes them,
   from content node idx: their hits, and the next node's number *)
fun _scan_text {lb,lq:agz}{n:pos}{o,k:nat | o + k <= n}{nq:pos}{qn:pos | qn <= nq}{r:nat | r <= HMAX} .<k>.
  (data: !$A.borrow(byte, lb, n), off: int o, k: int k, q: !$A.arr(byte, lq, nq), qn: int qn,
   ch: Int, idx: Nat, acc: hits(r), r: int r): [r2:nat | r2 <= HMAX] @(Nat, hits(r2), int r2) =
  if k < 65536 then let
    val @(h, r2) = _scan_piece(data, off, k, q, qn, ch, idx, acc, r)
  in @(idx + 1, h, r2) end
  else let
    val c = _text_cut(data, off, k)
    val @(h, r2) = _scan_piece(data, off, c, q, qn, ch, idx, acc, r)
  in _scan_text(data, off + c, k - c, q, qn, ch, idx + 1, h, r2) end

(* The numbers _skip_spans takes for k bytes *)
fun _skip_count {k:nat} .<k>. (k: int k, idx: Nat): Nat =
  if k < 65536 then idx + 1 else _skip_count(k - 65533, idx + 1)

fun _scan_nodes {lb,lq:agz}{n:pos}{sz:nat}{nq:pos}{qn:pos | qn <= nq}{r:nat | r <= HMAX} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz), top: bool,
   q: !$A.arr(byte, lq, nq), qn: int qn, ch: Int, idx: Nat, acc: hits(r), r: int r)
  : [r2:nat | r2 <= HMAX] @(Nat, hits(r2), int r2) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(i2, h, r2) = _scan_node(data, node, top, q, qn, ch, idx, acc, r)
    in _scan_nodes(data, rest, top, q, qn, ch, i2, h, r2) end
  | $X.xml_nodes_nil() => @(idx, acc, r)

and _scan_node {lb,lq:agz}{n:pos}{sz:pos}{nq:pos}{qn:pos | qn <= nq}{r:nat | r <= HMAX} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz), top: bool,
   q: !$A.arr(byte, lq, nq), qn: int qn, ch: Int, idx: Nat, acc: hits(r), r: int r)
  : [r2:nat | r2 <= HMAX] @(Nat, hits(r2), int r2) =
  case+ node of
  | $X.xml_text(off, tlen) =>
    if (if top then _blank(data, off, tlen, 0) else false) then @(_skip_count(tlen, idx), acc, r)
    else _scan_text(data, off, tlen, q, qn, ch, idx, acc, r)
  | $X.xml_element(name_off, name_len, _, children) => let
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
    if xml_name_eq(data, name_off, name_len, _t_head, 4) then @(idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_title, 5) then @(idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_meta, 4) then @(idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_link, 4) then @(idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_style, 5) then @(idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_script, 6) then @(idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_html, 4) then
      _scan_nodes(data, children, top, q, qn, ch, idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_body, 4) then
      _scan_nodes(data, children, top, q, qn, ch, idx, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_br, 2) then @(idx + 1, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_hr, 2) then @(idx + 1, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_img, 3) then @(idx + 1, acc, r)
    else if xml_name_eq(data, name_off, name_len, _t_image, 5) then @(idx + 1, acc, r)
    else _scan_nodes(data, children, false, q, qn, ch, idx + 1, acc, r)
  end

(* The results list, or its state *)
fn _search_status {nt:pos | nt < 256} (t: string nt): void = ui_text("qsrm", t)

(* The heading of chapter ch's results *)
fn _hit_heading {c:nat} (ch: int c): void = let
  val @(ga, gl) = nid_make("qj", ch)
  val () = ui_add_n("qsrl", ga, gl, TDiv)
  val @(ga, gl) = nid_make("qj", ch)
  val () = ui_attr_n(ga, gl, AClass, "grp")
  val @(lb, lk) = toc_label_of(ch)
  val @(ga, gl) = nid_make("qj", ch)
in ui_text_n_buf(ga, gl, lb, lk) end

(* One row of the results: hit i, with its text (its chapter is the
   heading above it) *)
fn _hit_row {i:nat}{l:agz}{m:pos}{sl:nat | sl < m; sl < 65536}
  (i: int i, a: !$A.arr(byte, l, m), sl: int sl): void = let
  val @(ra, rl) = nid_make("qh", i)
  val () = ui_btn_n("qsrl", ra, rl, "pi hgo")
  val @(pa, pl) = nid_make("qh", i)
  val @(sa, sl2) = nid_make("qhs", i)
  val () = ui_add_nn(pa, pl, sa, sl2, TSpan)
  val @(sa, sl2) = nid_make("qhs", i)
  val () = ui_attr_n(sa, sl2, AClass, "snip")
  val b = $A.alloc<byte>(sl + 1)
  val () = _frag_dup(a, b, sl, 0)
  val @(sa, sl2) = nid_make("qhs", i)
in ui_text_n_buf(sa, sl2, b, sl) end

(* The rows of hits x from hit i, under a heading wherever the chapter
   changes from last *)
fun _hit_rows {k:nat}{i:nat} .<k>. (x: !hits(k), i: int i, last: Int): void =
  case+ x of
  | hits_nil() => ()
  | @hits_cons(c, _, _, a, sl, rest) => let
      val () = (if c >= 0 then let
          val () = (if c <> last then _hit_heading(c) else ())
        in _hit_row(i, a, sl) end else ())
      val c0 = c
      val () = _hit_rows(rest, i + 1, c0)
      prval () = fold@(x)
    in end

(* The search is done: the hits in order, listed *)
fn _search_done (gen: int): void =
  if gen <> !_search_gen then ()
  else (case+ _search_take() of
    | ~SearchNone() => ()
    | ~SearchCell(h, k, q, qn) => let
        val h = hits_rev(h, hits_nil())
        val () = ui_clear("qsrl")
        val () = _hit_rows(h, 0, ~1)
        val () = (if k = 0 then _search_status("No results")
          else if k = 1 then _search_status("1 result")
          else if k >= HMAX then _search_status("500 results or more")
          else let
            val b = $A.alloc<byte>(24)
            val off = $S.int_to_str(b, 0, 24, k)
            val off = _put(b, off, " results")
          in ui_text_buf("qsrm", b, off) end)
      in _search_put(SearchCell(h, k, q, qn)) end)

(* The hits of the chapter data[0, n) (chapter ch), added *)
fn _search_add {lb:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz), ch: Int): void =
  case+ _search_take() of
  | ~SearchNone() => ()
  | ~SearchCell(h, k, q, qn) => let
      val @(_, h2, k2) = _scan_nodes(data, nodes, true, q, qn, ch, 0, h, k)
    in _search_put(SearchCell(h2, k2, q, qn)) end

fn _search_add_if {lb:agz}{n:pos}{sz:nat}
  (gen: int, data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz), ch: Int): void =
  if gen = !_search_gen then _search_add(data, nodes, ch) else ()

fn _search_full (): bool =
  case+ _search_take() of
  | ~SearchNone() => true
  | ~SearchCell(h, k, q, qn) => let
      val full = k >= HMAX
      val () = _search_put(SearchCell(h, k, q, qn))
    in full end

(* Searches chapters i to tc - 1 of book s, one after another, while
   search gen is the latest *)
fun _search_ch {i,tc:nat} .<max(tc - i, 0)>. (s: int, i: int i, tc: int tc, gen: int): void =
  if gen <> !_search_gen then ()
  else if i >= tc then _search_done(gen)
  else if _search_full() then _search_done(gen)
  else (case+ book_chapter_get(s, i) of
    | ~ChaptersUnknown() => _search_done(gen)
    | ~ChapterNone(_) => _search_ch(s, i + 1, tc, gen)
    | ~ChapterGot(fsz_s, ch_d, ch_csz, ch_method, _, _, _, _) =>
      (case+ piece_new(ch_csz) of
       | ~NoPiece() => _search_ch(s, i + 1, tc, gen)
       | ~Piece(car, cbuf) => let
           val _ = book_read(s, fsz_s, ch_d, cbuf, ch_csz)
           val @(cf, cb) = $A.freeze<byte>(cbuf)
           val dp = $DC.decompress(cb, ch_csz, ch_method)
           val () = $A.drop<byte>(cf, cb)
           val () = piece_free(car, $A.thaw<byte>(cf))
         in
           $P.discard<int>($P.and_then<Int><int>($P.vow(dp), lam(h) => let
             val () = (case+ take_content(h) of
               | ~NoContentBytes() => ()
               | ~ContentBytes(xar, xhtml, xn) => let
                   val @(xf, xb) = $A.freeze<byte>(xhtml)
                   val nodes = $X.parse_document(xb, xn)
                   val () = _search_add_if(gen, xb, nodes, i)
                   val () = $X.free_nodes(nodes)
                   val () = $A.drop<byte>(xf, xb)
                 in piece_free(xar, $A.thaw<byte>(xf)) end)
             val () = _search_ch(s, i + 1, tc, gen)
           in $P.ret<int>(0) end))
         end))

(* q[0, qn) in lower case, in a new array *)
fun _lower_into {l,lo:agz}{m,mo:pos}{qn:nat | qn <= m; qn <= mo}{i:nat | i <= qn} .<qn - i>.
  (q: !$A.arr(byte, l, m), o: !$A.arr(byte, lo, mo), qn: int qn, i: int i): void =
  if i >= qn then ()
  else let
    val () = $A.set<byte>(o, i, $A.int2byte($AR.low_byte(_lower(byte2int0($A.get<byte>(q, i))))))
  in _lower_into(q, o, qn, i + 1) end

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

(* The content node at the top of the page shown, or -1 *)
#pub fun reader_anchor (): Int
implement reader_anchor () = _anchor_now()

(* The link covering content node i, if any: followed (a link within
   the book, remembering where the reader was); true when there is one,
   also for a link out of the book, which the browser opens *)
fun _link_find {k:nat} .<k>. (x: !links(k), i: int): @(int, Int, [l:agz][f:nat] @($A.arr(byte, l, f + 1), int f)) =
  case+ x of
  | links_nil() => let val a0 = $A.alloc<byte>(1) in @(0, 0, @(a0, 0)) end
  | @links_cons(s0, e0, ch, fr, f, rest) =>
    if (if s0 <= i then i < e0 else false) then let
      val c = ch
      val b = $A.alloc<byte>(f + 1)
      val () = _frag_dup(fr, b, f + 1, 0)
      val ff = f
      prval () = fold@(x)
    in @((if c < 0 then 2 else 1), c, @(b, ff)) end
    else let
      val r = _link_find(rest, i)
      prval () = fold@(x)
    in r end

#pub fun reader_link_at (i: int): bool
implement reader_link_at (i) = let
  val c = _links_take()
  val+ @LinksCell(x) = c
  val @(kind, ch, @(b, f)) = _link_find(x, i)
  prval () = fold@(c)
  val () = _links_put(c)
in
  if kind = 1 then let
    val () = _push_position()
    val () = $P.discard<int>(_goto_frag(ch, b, f))
  in true end
  else let val () = $A.free<byte>(b) in kind = 2 end
end

(* Whether the open book reads right to left *)
#pub fun reader_rtl (): bool
implement reader_rtl () = !_rtl

(* k, at most 200 *)
fn _qlen {k:pos} (k: int k): [c:pos | c <= 200; c <= k] int c = if k <= 200 then k else 200

(* Searches the open book for q[0, k): its hits are listed as they are
   found, chapter by chapter *)
#pub fun reader_search {l:agz}{m:pos}{k:nat | k <= m} (q: $A.arr(byte, l, m), k: int k): void
implement reader_search (q, k) = let
  val () = !_search_gen := !_search_gen + 1
  val gen = !_search_gen
  val () = $BDOM.clear_marks(2)
  val () = ui_clear("qsrl")
  val () = ui_show("qsrn", false)
  val () = !_hit_cur := ~1
in
  if k <= 0 then let
    val () = $A.free<byte>(q)
    val () = _search_put(SearchNone())
  in _search_status(" ") end
  else let
    val qn = _qlen(k)
    val o = $A.alloc<byte>(qn)
    val () = _lower_into(q, o, qn, 0)
    val () = $A.free<byte>(q)
    val () = _search_put(SearchCell(hits_nil(), 0, o, qn))
    val () = _search_status("Searching\xE2\x80\xA6")
  in
    case+ reading_get() of
    | @(_, _, _, tc) => _search_ch(book_serial(), 0, tc, gen)
  end
end

fun _hit_at {k:nat} .<k>. (x: !hits(k), i: int): @(Int, Int, Int) =
  case+ x of
  | hits_nil() => @(~1, 0, 0)
  | @hits_cons(c, nd, o, _, _, rest) =>
    if i = 0 then let
      val r = @(c, nd, o)
      prval () = fold@(x)
    in r end
    else let
      val r = _hit_at(rest, i - 1)
      prval () = fold@(x)
    in r end

(* Hit i, its count and the query's length; a chapter of -1 when there
   is none *)
fn _hit (i: Int): @(Int, Int, Int, Int, Int) =
  case+ _search_take() of
  | ~SearchNone() => @(~1, 0, 0, 0, 0)
  | ~SearchCell(h, k, q, qn) => let
      val @(c, nd, o) = _hit_at(h, i)
      val () = _search_put(SearchCell(h, k, q, qn))
    in @(c, nd, o, k, qn) end

(* "i of k" under the results *)
fn _hit_count (i: Int, k: Int): void = let
  val b = $A.alloc<byte>(40)
  val off = $S.int_to_str(b, 0, 40, (if i >= 0 then i + 1 else 0): Nat)
  val off = _put(b, off, " of ")
  val off = $S.int_to_str(b, off, 40, (if k >= 0 then k else 0): Nat)
in ui_text_buf("qsrc", b, off) end

(* Opens hit i: its page, the match marked; the first one remembers where
   the reader was *)
#pub fun reader_search_go (i: Int): void
implement reader_search_go (i) = let
  val @(c, nd, o, k, qn) = _hit(i)
in
  if c < 0 then ()
  else let
    val () = (if !_hit_jumped then () else let
        val () = _push_position()
      in !_hit_jumped := true end)
    val () = !_hit_cur := i
    val () = _hit_count(i, k)
    val () = ui_show("qsrn", true)
  in
    $P.discard<int>($P.and_then<int><int>(_goto(c, 0, nd), lam(r) => let
      val () = (if r >= 0 then (if nd >= 0 then let
          val () = $BDOM.clear_marks(2)
          val @(ia, il) = nid_pad3("c", nd)
          val @(ja, jl) = nid_pad3("c", nd)
          val @(fa, fb) = $A.freeze<byte>(ia)
          val @(ga, gb) = $A.freeze<byte>(ja)
          val () = $BDOM.mark_range(2, fb, il, o, gb, jl, o + qn)
          val () = $A.drop<byte>(ga, gb)
          val () = $A.free<byte>($A.thaw<byte>(ga))
          val () = $A.drop<byte>(fa, fb)
        in $A.free<byte>($A.thaw<byte>(fa)) end else ()) else ())
    in $P.ret<int>(0) end))
  end
end

(* The next (d = 1) or previous (d = -1) hit *)
#pub fun reader_search_step (d: Int): void
implement reader_search_step (d) = let
  val @(_, _, _, k, _) = _hit(0)
in
  if k <= 0 then ()
  else let
    val i = !_hit_cur + d
  in reader_search_go(if i < 0 then k - 1 else if i >= k then 0 else i) end
end

(* Stops the search, its hits and marks gone, where the reader is *)
#pub fun reader_search_stop (): void
implement reader_search_stop () = let
  val () = !_search_gen := !_search_gen + 1
  val () = $BDOM.clear_marks(2)
  val () = ui_show("qsrn", false)
  val () = ui_clear("qsrl")
  val () = _search_status(" ")
  val () = _search_put(SearchNone())
  val () = !_hit_cur := ~1
in !_hit_jumped := false end

(* Closes the search: its marks go, and the reader returns to where it
   was when it jumped to a hit *)
#pub fun reader_search_close (): void
implement reader_search_close () = let
  val jumped = !_hit_jumped
  val () = reader_search_stop()
in if jumped then _pop_position() else () end

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
