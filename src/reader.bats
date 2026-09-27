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
   Persistence helpers (IDB)
   ============================================================ *)

(* Save reading position to IDB: 4 bytes = u16 chapter + u16 page *)
fn _save_pos(ch: int, pg: int): void = let
  val buf = $A.alloc<byte>(4)
  val () = $A.set<byte>(buf, 0, int2byte0(ch mod 256))
  val () = $A.set<byte>(buf, 1, int2byte0(ch / 256))
  val () = $A.set<byte>(buf, 2, int2byte0(pg mod 256))
  val () = $A.set<byte>(buf, 3, int2byte0(pg / 256))
  val @(bf, bb) = $A.freeze<byte>(buf)
  var k = @[char][3]('p', 'o', 's')
  val ka = $A.alloc<byte>(3)
  val () = $A.set<byte>(ka, 0, int2byte0(112))
  val () = $A.set<byte>(ka, 1, int2byte0(111))
  val () = $A.set<byte>(ka, 2, int2byte0(115))
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_put(kb, 3, bb, 4)
  val () = $P.discard<Int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
in end

fn _save_position(): void =
  case+ reading_get() of @(p, _, c, _) => _save_pos(c, p)

(* Save the EPUB file to IDB, from the JS side (it is never copied
   through wasm memory, whatever its size) *)
fn _save_epub_to_idb(): void =
  case+ book_get() of
  | NoBook() => ()
  | OpenBook(fh, _, _, _, _, _, _) => let
      val ka = $A.alloc<byte>(4)
      val () = $A.set<byte>(ka, 0, int2byte0(98))  (* b *)
      val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 2, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 3, int2byte0(107)) (* k *)
      val @(kf, kb) = $A.freeze<byte>(ka)
      val p = $FI.idb_put(kb, 4, fh)
      val () = $P.discard<Int>(p)
      val () = $A.drop<byte>(kf, kb)
    in $A.free<byte>($A.thaw<byte>(kf)) end

(* v as 4 little-endian bytes at buf[off, off + 4) *)
fn _put_i32 {l:agz}{n:pos}{off:nat | off + 4 <= n}
  (buf: !$A.arr(byte, l, n), off: int off, v: int): void = let
  val () = $A.set<byte>(buf, off, $A.int2byte($AR.low_byte(v)))
  val () = $A.set<byte>(buf, off + 1, $A.int2byte($AR.low_byte($AR.bsr_int_int(v, 8))))
  val () = $A.set<byte>(buf, off + 2, $A.int2byte($AR.low_byte($AR.bsr_int_int(v, 16))))
in $A.set<byte>(buf, off + 3, $A.int2byte($AR.low_byte($AR.bsr_int_int(v, 24)))) end

(* The little-endian two's complement int at buf[off, off + 4); the top
   byte carries the sign, so no term overflows *)
fn _get_i32 {l:agz}{n:pos}{off:nat | off + 4 <= n}
  (buf: !$A.arr(byte, l, n), off: int off): [v:int] int v = let
  val b0 = $AR.low_byte(byte2int0($A.get<byte>(buf, off)))
  val b1 = $AR.low_byte(byte2int0($A.get<byte>(buf, off + 1)))
  val b2 = $AR.low_byte(byte2int0($A.get<byte>(buf, off + 2)))
  val b3 = $AR.low_byte(byte2int0($A.get<byte>(buf, off + 3)))
  val hi = (if b3 < 128 then b3 else b3 - 256): [h:int | ~128 <= h; h < 128] int h
in b0 + b1 * 256 + b2 * 65536 + hi * 16777216 end

(* Save the open book's metadata to IDB as 9 x 4-byte ints: 0 (where
   the file handle was, which means nothing to a later run), file size,
   0, 0, OPF data offset, size, method, name offset, name length *)
fn _save_metadata_to_idb(): void =
  case+ book_get() of
  | NoBook() => ()
  | OpenBook(_, fsz, d, sz, m, no, nl) => let
  val buf = $A.alloc<byte>(36)
  val () = _put_i32(buf, 0, 0)
  val () = _put_i32(buf, 4, fsz)
  val () = _put_i32(buf, 8, 0)
  val () = _put_i32(buf, 12, 0)
  val () = _put_i32(buf, 16, d)
  val () = _put_i32(buf, 20, sz)
  val () = _put_i32(buf, 24, m)
  val () = _put_i32(buf, 28, no)
  val () = _put_i32(buf, 32, nl)
  val @(bf, bb) = $A.freeze<byte>(buf)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(109)) (* m *)
  val () = $A.set<byte>(ka, 1, int2byte0(101)) (* e *)
  val () = $A.set<byte>(ka, 2, int2byte0(116)) (* t *)
  val () = $A.set<byte>(ka, 3, int2byte0(97))  (* a *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_put(kb, 4, bb, 36)
  val () = $P.discard<Int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
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

fn _num_wid {sn:pos | sn <= 3}{i:nat}{w:int | w == 2 || w == 3}
  (pre: string sn, i: int i, w: int w): $W.widget_id = let
  val @(a, k) = _num_id(pre, i, w)
  val txt = arr_to_text(a, k)
  val () = $A.free<byte>(a)
in $W.Generated(txt, k) end

(* Apply font size to content area via dynamic style element *)
(* Writes ".caf{font-size:NNpx}" to style element qfss *)
fn _apply_font_size(sz: font_px): void = let
  val () = font_set(sz)
  (* ".caf{font-size:" (15 bytes), the size (at most 11), "px}" *)
  val buf = $A.alloc<byte>(29)
  val off = _put(buf, 0, ".caf{font-size:")
  val off = $S.int_to_str(buf, off, 29, sz)
  val off = _put(buf, off, "px}")
  val txt = _prefix_text(buf, 29, off)
  var fs_c = @[char][4]('q', 'f', 's', 's')
  val fs_id = $W.Generated($S.text_of_chars(fs_c, 4), 4)
in _apply_diff($W.SetTextContent(fs_id, txt, off)) end

(* Save font size to IDB *)
fn _save_font_size(): void = let
  val sz = font_get()
  val buf = $A.alloc<byte>(2)
  val () = $A.set<byte>(buf, 0, int2byte0(sz mod 256))
  val () = $A.set<byte>(buf, 1, int2byte0(sz / 256))
  val @(bf, bb) = $A.freeze<byte>(buf)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(102)) (* f *)
  val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 2, int2byte0(110)) (* n *)
  val () = $A.set<byte>(ka, 3, int2byte0(116)) (* t *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_put(kb, 4, bb, 2)
  val () = $P.discard<Int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
in end

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
in _update_page_indicator() end

(* Shows page p of the chapter's t pages *)
fn _show_page {t:pos}{p:nat | p < t}{c,tc:nat}
  (p: int p, t: int t, c: int c, tc: int tc): void = let
  val () = reading_set(@(p, t, c, tc))
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
  val () = _save_position()
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
   pidx: int q, nodes: !$X.xml_node_list(n, sz), acc: imgs(n, k)): [k2:nat] imgs(n, k2) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val acc = _render_node(doc, data, len, pidx, node, acc)
    in _render_nodes(doc, data, len, pidx, rest, acc) end
  | $X.xml_nodes_nil() => acc

and _render_node
  {ld,lb:agz}{n:pos}{sz:pos}{q:int | q >= ~1}{k:nat} .<sz, 0>.
  (doc: !$D.document(ld), data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int q, node: !$X.xml_node(n, sz), acc: imgs(n, k)): [k2:nat] imgs(n, k2) =
  case+ node of
  | $X.xml_text(off, tlen) =>
    (* To do: a text node of 64 KiB or more (a text op's limit) is not
       shown; it should be split. *)
    if tlen < 65536 then let
      val idx = _next_content_idx()
      val () = _add_node(doc, pidx, idx, "span")
      val () = _node_text(doc, idx, data, off, tlen)
    in acc end
    else acc
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
      _render_nodes(doc, data, len, pidx, children, acc)
    else if xml_name_eq(data, name_off, name_len, _t_body, 4) then
      _render_nodes(doc, data, len, pidx, children, acc)
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
        | xspan_at(ao, al) =>
          if al < 65536 then _node_attr(doc, idx, "alt", data, ao, al)
          else _node_attr_lit(doc, idx, "alt", "image")
        | xspan_none() => _node_attr_lit(doc, idx, "alt", "image")): void
      var _a_src = @[char][3]('s', 'r', 'c')
    in
      case+ find_attr(data, attrs, _a_src, 3) of
      | xspan_at(so, sl) => imgs_cons(idx, so, sl, acc)
      | xspan_none() => acc
    end
    else let
      val idx = _next_content_idx()
      val () = _add_node(doc, pidx, idx, _tag_of(data, name_off, name_len))
    in _render_nodes(doc, data, len, idx, children, acc) end
  end

(* Just past the last '/' in buf[p, e), or la if there is none *)
fun _after_last_slash {l:agz}{n:pos}{p,e:nat | p <= e; e <= n}{la:int | la <= p} .<e - p>.
  (buf: !$A.arr(byte, l, n), p: int p, e: int e, la: int la): [r:int | la <= r; r <= e] int r =
  if p >= e then la
  else if byte2int0($A.get<byte>(buf, p)) = 47 then _after_last_slash(buf, p + 1, e, p + 1)
  else _after_last_slash(buf, p + 1, e, la)

(* The length of the directory part of the name [no, no + nl) of the
   file: up to and including its last '/', 0 when it has none *)
fn _opf_prefix_len {z:nat}{no,nl:nat | no + nl <= z; nl < 65536}
  (fh: $FI.infile(z), no: int no, nl: int nl): [p:nat | p <= nl] int p =
  if nl <= 0 then 0
  else let
    val buf = $A.alloc<byte>(nl)
    val () = $FI.file_read(fh, no, buf, nl)
    val p = _after_last_slash(buf, 0, nl, 0)
    val () = $A.free<byte>(buf)
  in p end

(* ============================================================
   Images: read from the book, shown in the chapter's <img> elements
   ============================================================ *)

(* Counts chapter loads: an image whose bytes arrive after another
   chapter began loading is not shown (its element is gone) *)
val _load_gen = ref<int>(0)

(* The end of the segment of buf[i, m): the next '/' at or after i, or m *)
fun _seg_end {l:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (buf: !$A.arr(byte, l, m), m: int m, i: int i): [j:int | i <= j; j <= m] int j =
  if i >= m then i
  else if byte2int0($A.get<byte>(buf, i)) = 47 then i
  else _seg_end(buf, m, i + 1)

(* Just past the last '/' of buf[0, p], or 0: where ".." leaves a path
   buf[0, p + 2) that ends with '/' *)
fun _back {l:agz}{m:pos}{p:int | p < m} .<max(p + 1, 0)>.
  (buf: !$A.arr(byte, l, m), p: int p): [q:nat | q <= max(p + 1, 0)] int q =
  if p < 0 then 0
  else if byte2int0($A.get<byte>(buf, p)) = 47 then p + 1
  else _back(buf, p - 1)

(* buf[s, s + c) to buf[d, d + c), front first (d <= s) *)
fun _move {l:agz}{m:pos}{s,d,c:nat | d <= s; s + c <= m} .<c>.
  (buf: !$A.arr(byte, l, m), s: int s, d: int d, c: int c): void =
  if c <= 0 then ()
  else let
    val () = $A.set<byte>(buf, d, $A.get<byte>(buf, s))
  in _move(buf, s + 1, d + 1, c - 1) end

(* The path buf[0, m) with its empty, "." and ".." segments resolved,
   in place: the segments read from i on are written from w on (w <= i);
   the resolved length *)
fun _norm {l:agz}{m:pos}{i,w:nat | w <= i; i <= m} .<m - i>.
  (buf: !$A.arr(byte, l, m), m: int m, i: int i, w: int w): [k:nat | k <= m] int k =
  if i >= m then w
  else let
    val [j:int] j = _seg_end(buf, m, i)
    val c = j - i
    val dot1 = (if c >= 1 then byte2int0($A.get<byte>(buf, i)) = 46 else false): bool
    val dot2 = (if c >= 2 then byte2int0($A.get<byte>(buf, i + 1)) = 46 else false): bool
    val up = (if w >= 2 then _back(buf, w - 2) else 0): [q:nat | q <= w] int q
  in
    if j < m then
      (* a segment and its '/': the next one starts at j + 1 *)
      if c = 0 then _norm(buf, m, j + 1, w)
      else if c = 1 && dot1 then _norm(buf, m, j + 1, w)
      else if c = 2 && dot1 && dot2 then _norm(buf, m, j + 1, up)
      else let
        val () = _move(buf, i, w, c)
        val () = $A.set<byte>(buf, w + c, $A.int2byte(47))
      in _norm(buf, m, j + 1, w + c + 1) end
    (* the last segment *)
    else if c = 1 && dot1 then w
    else if c = 2 && dot1 && dot2 then up
    else let
      val () = _move(buf, i, w, c)
    in w + c end
  end

(* The end of an src value data[so, so + e): its first '#', or its end *)
fun _src_end {lb:agz}{n:pos}{so,sl:nat | so + sl <= n}{e:nat | e <= sl} .<sl - e>.
  (data: !$A.borrow(byte, lb, n), so: int so, sl: int sl, e: int e): [r:nat | r <= sl] int r =
  if e >= sl then e
  else if byte2int0($A.read<byte>(data, so + e)) = 35 then e
  else _src_end(data, so, sl, e + 1)

(* Whether path[0, k) ends with pat[0, np), letters in any case *)
fun _ends_with {lp:agz}{k:pos}{np:pos | np <= k}{i:nat | i <= np} .<np - i>.
  (path: !$A.borrow(byte, lp, k), k: int k, pat: &(@[char][np]), np: int np, i: int i): bool =
  if i >= np then true
  else let
    val b = byte2int0($A.read<byte>(path, k - np + i))
    val lb = (if b >= 65 then (if b <= 90 then b + 32 else b) else b): int
  in
    if lb <> char2int0(pat.[i]) then false
    else _ends_with(path, k, pat, np, i + 1)
  end

(* The image type the name path[0, k) says (by its extension) *)
fn _mime_of {lp:agz}{k:pos} (path: !$A.borrow(byte, lp, k), k: int k): [sn:pos | sn <= 24] string sn = let
  var png = @[char][4]('.', 'p', 'n', 'g')
  var jpg = @[char][4]('.', 'j', 'p', 'g')
  var jpeg = @[char][5]('.', 'j', 'p', 'e', 'g')
  var gif = @[char][4]('.', 'g', 'i', 'f')
  var svg = @[char][4]('.', 's', 'v', 'g')
  var webp = @[char][5]('.', 'w', 'e', 'b', 'p')
in
  if k >= 5 && _ends_with(path, k, jpeg, 5, 0) then "image/jpeg"
  else if k >= 5 && _ends_with(path, k, webp, 5, 0) then "image/webp"
  else if k < 4 then "application/octet-stream"
  else if _ends_with(path, k, png, 4, 0) then "image/png"
  else if _ends_with(path, k, jpg, 4, 0) then "image/jpeg"
  else if _ends_with(path, k, gif, 4, 0) then "image/gif"
  else if _ends_with(path, k, svg, 4, 0) then "image/svg+xml"
  else "application/octet-stream"
end

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
   z-byte file fh: shown now when it is stored, once decompressed when it
   is deflated (unless chapter load gen is no longer the latest); not at
   all when it is missing *)
fn _show_image {z:pos}{i:nat}{lp:agz}{k:pos}
  (fh: $FI.infile(z), z: int z, idx: int i, gen: int,
   path: !$A.borrow(byte, lp, k), k: int k): void = let
  val mime = _mime_of(path, k)
in
  case+ zip_read(fh, z, path, k) of
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
  (fh: $FI.infile(z), z: int z, no: int no, dl: int dl,
   data: !$A.borrow(byte, lb, n), n: int n, idx: int i, so: int so, sl: int sl, gen: int): void = let
  val h = _src_end(data, so, sl, 0)
in
  (* An src of 65536 bytes or more names no zip entry (a zip name is
     shorter): the book's data, checked here *)
  if h <= 0 then ()
  else if h >= 65536 then ()
  else let
    val m = dl + h
    val buf = $A.alloc<byte>(m)
    val () = $FI.file_read(fh, no, buf, dl)
    val () = $S.copy_from_borrow(data, so, n, buf, dl, m, h)
    val k = _norm(buf, m, 0, 0)
  in
    if k <= 0 then $A.free<byte>(buf)
    else let
      val exact = $A.alloc<byte>(k)
      val buf = $S.copy_arr_region(buf, 0, m, exact, k, k)
      val () = $A.free<byte>(buf)
      val @(fz, bv) = $A.freeze<byte>(exact)
      val () = _show_image(fh, z, idx, gen, bv, k)
      val () = $A.drop<byte>(fz, bv)
    in $A.free<byte>($A.thaw<byte>(fz)) end
  end
end

(* The images xs of the chapter data[0, n) *)
fun _load_images {z:pos}{no,dl:nat | no + dl <= z; dl < 65536}{lb:agz}{n:pos}{k:nat} .<k>.
  (fh: $FI.infile(z), z: int z, no: int no, dl: int dl,
   data: !$A.borrow(byte, lb, n), n: int n, xs: imgs(n, k), gen: int): void =
  case+ xs of
  | ~imgs_nil() => ()
  | ~imgs_cons(idx, so, sl, tl) => let
      val () = _load_image(fh, z, no, dl, data, n, idx, so, sl, gen)
    in _load_images(fh, z, no, dl, data, n, tl, gen) end

fn _load_chapter {i:nat} (chapter_idx: int i): $P.promise(int, $P.Chained) =
  case+ book_get() of
  | NoBook() => $P.ret<int>(~1)
  | OpenBook(fh, fsz_s, opf_doff, opf_csz, opf_comp, opf_name_off, opf_name_len) => let
    val () = !_load_gen := !_load_gen + 1
    val gen = !_load_gen
  in
    (* The OPF's compressed bytes, read at their span into a piece *)
    case+ piece_new(opf_csz) of
    | ~NoPiece() => $P.ret<int>(~1)
    | ~Piece(car, opf_cbuf) => let
    val () = $FI.file_read(fh, opf_doff, opf_cbuf, opf_csz)

    val @(ocf, ocb) = $A.freeze<byte>(opf_cbuf)
    val dc_p = $DC.decompress(ocb, opf_csz, opf_comp)
    val () = $A.drop<byte>(ocf, ocb)
    val () = piece_free(car, $A.thaw<byte>(ocf))

    val dc_p = $P.vow(dc_p)
  in
    (* Stage 2: parse OPF to find first chapter href *)
    $P.and_then<Int><int>(dc_p, lam(dc_handle) => let
      val dc = take_content(dc_handle)
    in
      case+ dc of
      | ~NoContentBytes() => $P.ret<int>(~2)
      | ~ContentBytes(par, opf_buf, dc_sz) => let

        val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
        val opf_nodes = $X.parse_document(opf_b, dc_sz)

        (* Count spine items and store total chapters *)
        val total_ch = count_spine_items(opf_b, opf_nodes)
        val () = (case+ reading_get() of
          | @(p, t, c, _) => reading_set(@(p, t, c, total_ch)))

        (* Find Nth spine itemref → manifest item href *)
        val ch_href = find_chapter_href_n(opf_b, dc_sz, opf_nodes, chapter_idx)
      in
        case+ ch_href of
        | xspan_none() => let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val () = piece_free(par, $A.thaw<byte>(opf_f))
        in $P.ret<int>(~3) end
        | xspan_at(ch_off, ch_len) =>
        if ch_len <= 0 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val () = piece_free(par, $A.thaw<byte>(opf_f))
        in $P.ret<int>(~3) end
        else let
          (* The OPF's directory, e.g. "OEBPS/" of "OEBPS/content.opf",
             prefixes chapter hrefs *)
          val prefix_len = _opf_prefix_len(fh, opf_name_off, opf_name_len)
          val full_len = prefix_len + ch_len
        in
          if full_len > 1048576 then let
            val () = $X.free_nodes(opf_nodes)
            val () = $A.drop<byte>(opf_f, opf_b)
            val () = piece_free(par, $A.thaw<byte>(opf_f))
          in $P.ret<int>(~4) end
          else let
          val ch_buf = $A.alloc<byte>(full_len)
          (* The prefix read from the file at the OPF's name, then the
             chapter href from the OPF *)
          val () = $FI.file_read(fh, opf_name_off, ch_buf, prefix_len)
          val () = $S.copy_from_borrow(opf_b, ch_off, dc_sz,
                    ch_buf, prefix_len, full_len, ch_len)

          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val () = piece_free(par, $A.thaw<byte>(opf_f))

          val @(chf, chb) = $A.freeze<byte>(ch_buf)
          val ch_entry = zip_read(fh, fsz_s, chb, full_len)
          val () = $A.drop<byte>(chf, chb)
          val () = $A.free<byte>($A.thaw<byte>(chf))
        in
          case+ ch_entry of
          | ~ZipMissing() => $P.ret<int>(~4)
          | ~ZipGot(ccar, ch_comp, ch_csz, ch_method, _, ch_no, ch_nl) => let
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
                  val imgs = _render_nodes(doc, xb, ch_dc_sz, ~1, nodes, imgs_nil())
                  val () = $D.destroy(doc)
                  val () = $X.free_nodes(nodes)
                  (* Its images, named relative to the chapter's directory *)
                  val ch_dl = _opf_prefix_len(fh, ch_no, ch_nl)
                  val () = _load_images(fh, fsz_s, ch_no, ch_dl, xb, ch_dc_sz, imgs, gen)
                  val () = $A.drop<byte>(xf, xb)
                  val () = piece_free(xar, $A.thaw<byte>(xf))

                  val () = (case+ reading_get() of
                    | @(p, t, _, tc) => reading_set(@(p, t, chapter_idx + 1, tc)))
                  (* Update chapter title in nav bar *)
                  val ch_num = chapter_idx + 1
                  (* "Chapter " (8 bytes) and the number (at most 11) *)
                  val tbuf = $A.alloc<byte>(19)
                  val off = _put(tbuf, 0, "Chapter ")
                  val off = $S.int_to_str(tbuf, off, 19, ch_num)
                  val () = _set_text_of("qcht", tbuf, off)
                  val () = _measure_pagination()
                  val () = _save_position()
                in $P.ret<int>(0) end
              end)
            end
        end
          end
      end
    end)
  end
  end

(* The next page: in this chapter, else the next chapter's first *)
fn _page_next(): void =
  case+ reading_get() of
  | @(p, t, c, tc) =>
    if p + 1 < t then _show_page(p + 1, t, c, tc)
    else if c < tc then $P.discard<int>(_load_chapter(c))
    else _show_page(p, t, c, tc)

(* The previous page: in this chapter, else the previous chapter's
   first *)
fn _page_prev(): void =
  case+ reading_get() of
  | @(p, t, c, tc) =>
    if p > 0 then _show_page(p - 1, t, c, tc)
    else if c > 1 then $P.discard<int>(_load_chapter(c - 2))
    else _show_page(0, t, c, tc)

(* Page pg, saved by an earlier run: the last page if the chapter now
   has fewer *)
fn _show_saved_page {g:nat} (pg: int g): void =
  case+ reading_get() of
  | @(_, t, c, tc) =>
    if pg < t then _show_page(pg, t, c, tc) else _show_page(t - 1, t, c, tc)

(* Restore font size from IDB on startup *)
fn _restore_font_size(): void = let
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(102)) (* f *)
  val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 2, int2byte0(110)) (* n *)
  val () = $A.set<byte>(ka, 3, int2byte0(116)) (* t *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val font_p = $IDB.idb_get(kb, 4)
  val () = $A.drop<byte>(kf, kb)
  val ktmp = $A.thaw<byte>(kf)
  val () = $A.free<byte>(ktmp)
  val font_p = $P.vow(font_p)
  val p2 = $P.and_then<Int><int>(font_p, lam(font_h) =>
    case+ take_blob(font_h) of
    | ~NoBlobBytes() => $P.ret<int>(~1)
    | ~BlobBytes(fdata, font_len) =>
    if font_len <> 2 then let
      val () = $A.free<byte>(fdata)
    in $P.ret<int>(~1) end
    else let
      val lo = $AR.low_byte(byte2int0($A.get<byte>(fdata, 0)))
      val hi = $AR.low_byte(byte2int0($A.get<byte>(fdata, 1)))
      val () = $A.free<byte>(fdata)
      val sz = lo + hi * 256
    in
      if sz >= 8 then
        if sz <= 48 then let
          val () = _apply_font_size(sz)
        in $P.ret<int>(0) end
        else $P.ret<int>(~1)
      else $P.ret<int>(~1)
    end)
  val () = $P.discard<int>(p2)
in end

(* No saved position: show the reader, hide the library, load chapter 0 *)
fn _open_at_start(): void = let
  var ll_c = @[char][4]('q', 'l', 'l', 'c')
  val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
  var rv_c = @[char][4]('q', 'r', 'v', 'w')
  val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
  val () = _apply_diff($W.SetHidden(ll_id, true))
  val () = _apply_diff($W.SetHidden(rv_id, false))
  val ch_p = _load_chapter(0)
in $P.discard<int>(ch_p) end

(* Restore reading state from IDB on startup *)
fn _restore_from_idb(): void = let
  (* Step 1: get "book" from IDB *)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(98))  (* b *)
  val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 2, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 3, int2byte0(107)) (* k *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val book_p = $FI.idb_get(kb, 4)
  val () = $A.drop<byte>(kf, kb)
  val ktmp = $A.thaw<byte>(kf)
  val () = $A.free<byte>(ktmp)
  val book_p = $P.vow(book_p)
  val p2 = $P.and_then<Int><int>(book_p, lam(book_h) =>
    case+ $FI.claim(book_h) of
    | ~$R.none() => $P.ret<int>(~1)
    | ~$R.some(fh) => let
      val bsz = $FI.size(fh)
    in
      if bsz <= 0 then $P.ret<int>(~1)
      else let

      (* Step 2: get "meta" from IDB *)
      val ma = $A.alloc<byte>(4)
      val () = $A.set<byte>(ma, 0, int2byte0(109)) (* m *)
      val () = $A.set<byte>(ma, 1, int2byte0(101)) (* e *)
      val () = $A.set<byte>(ma, 2, int2byte0(116)) (* t *)
      val () = $A.set<byte>(ma, 3, int2byte0(97))  (* a *)
      val @(mf, mb) = $A.freeze<byte>(ma)
      val meta_p = $IDB.idb_get(mb, 4)
      val () = $A.drop<byte>(mf, mb)
      val mtmp = $A.thaw<byte>(mf)
      val () = $A.free<byte>(mtmp)
      val meta_p = $P.vow(meta_p)
    in
      $P.and_then<Int><int>(meta_p, lam(meta_h) =>
        case+ take_blob(meta_h) of
        | ~NoBlobBytes() => $P.ret<int>(~2)
        | ~BlobBytes(meta_data, meta_len) =>
        if meta_len <> 36 then let
          val () = $A.free<byte>(meta_data)
        in $P.ret<int>(~2) end
        else let
          (* 9 x 4-byte ints (see _save_metadata_to_idb), stored by an
             earlier run: checked here, once, against the book's bytes *)
          val d = _get_i32(meta_data, 16)
          val sz = _get_i32(meta_data, 20)
          val m = _get_i32(meta_data, 24)
          val no = _get_i32(meta_data, 28)
          val nl = _get_i32(meta_data, 32)
          val () = $A.free<byte>(meta_data)
          val ok = (if d < 0 then false else if d > bsz then false
            else if sz <= 0 then false else if sz > bsz - d then false
            else if sz > 268435456 then false
            else if no < 0 then false else if no > bsz then false
            else if nl < 0 then false else if nl > bsz - no then false
            else if nl >= 65536 then false
            else if m = 0 then let
              val () = book_set(OpenBook(fh, bsz, d, sz, 0, no, nl))
            in true end
            else if m = 8 then let
              val () = book_set(OpenBook(fh, bsz, d, sz, 8, no, nl))
            in true end
            else false): bool
        in
          if ~ok then $P.ret<int>(~2)
          else let
          (* Step 3: get "pos" from IDB *)
          val pa = $A.alloc<byte>(3)
          val () = $A.set<byte>(pa, 0, int2byte0(112)) (* p *)
          val () = $A.set<byte>(pa, 1, int2byte0(111)) (* o *)
          val () = $A.set<byte>(pa, 2, int2byte0(115)) (* s *)
          val @(pf, pb) = $A.freeze<byte>(pa)
          val pos_p = $IDB.idb_get(pb, 3)
          val () = $A.drop<byte>(pf, pb)
          val ptmp = $A.thaw<byte>(pf)
          val () = $A.free<byte>(ptmp)
          val pos_p = $P.vow(pos_p)
        in
          $P.and_then<Int><int>(pos_p, lam(pos_h) =>
            case+ take_blob(pos_h) of
            | ~NoBlobBytes() => let
                val () = _open_at_start()
              in $P.ret<int>(0) end
            | ~BlobBytes(pos_data, pos_len) =>
            if pos_len <> 4 then let
              val () = $A.free<byte>(pos_data)
              val () = _open_at_start()
            in $P.ret<int>(0) end
            else let
              val ch_lo = $AR.low_byte(byte2int0($A.get<byte>(pos_data, 0)))
              val ch_hi = $AR.low_byte(byte2int0($A.get<byte>(pos_data, 1)))
              val pg_lo = $AR.low_byte(byte2int0($A.get<byte>(pos_data, 2)))
              val pg_hi = $AR.low_byte(byte2int0($A.get<byte>(pos_data, 3)))
              val () = $A.free<byte>(pos_data)
              val saved_ch = ch_lo + ch_hi * 256
              val saved_pg = pg_lo + pg_hi * 256
              (* Show reader, hide library *)
              var ll_c = @[char][4]('q', 'l', 'l', 'c')
              val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
              var rv_c = @[char][4]('q', 'r', 'v', 'w')
              val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
              val () = _apply_diff($W.SetHidden(ll_id, true))
              val () = _apply_diff($W.SetHidden(rv_id, false))
              (* Load the saved chapter (1-indexed → 0-indexed) *)
              val ch_idx = (if saved_ch > 0 then saved_ch - 1 else 0): [i:nat] int i
              val ch_p = _load_chapter(ch_idx)
              (* After chapter loads, scroll to saved page *)
              val ch_p2 = $P.and_then<int><int>(ch_p, lam(result) =>
                if result = 0 then let
                  val () = _show_saved_page(saved_pg)
                in $P.ret<int>(0) end
                else $P.ret<int>(result))
              val () = $P.discard<int>(ch_p2)
            in $P.ret<int>(0) end)
          end
        end)
      end
    end)
  val () = $P.discard<int>(p2)
in end


(* ============================================================
   Public API
   ============================================================ *)

#pub fun apply_diff_list(dl: $W.diff_list): void
implement apply_diff_list(dl) = _apply_diff_list(dl)

#pub fun apply_diff(d: $W.diff): void
implement apply_diff(d) = _apply_diff(d)

#pub fun apply_font_size(size: font_px): void
implement apply_font_size(size) = _apply_font_size(size)

#pub fun measure_pagination(): void
implement measure_pagination() = _measure_pagination()

#pub fun page_next(): void
implement page_next() = _page_next()

#pub fun page_prev(): void
implement page_prev() = _page_prev()

#pub fun load_chapter {i:nat} (chapter_idx: int i): $P.promise(int, $P.Chained)
implement load_chapter(chapter_idx) = _load_chapter(chapter_idx)


#pub fun save_position(): void
implement save_position() = _save_position()

#pub fun save_epub_to_idb(): void
implement save_epub_to_idb() = _save_epub_to_idb()

#pub fun save_metadata_to_idb(): void
implement save_metadata_to_idb() = _save_metadata_to_idb()

#pub fun save_font_size(): void
implement save_font_size() = _save_font_size()

#pub fun restore_font_size(): void
implement restore_font_size() = _restore_font_size()

#pub fun restore_from_idb(): void
implement restore_from_idb() = _restore_from_idb()

#pub fun update_page_indicator(): void
implement update_page_indicator() = _update_page_indicator()

#pub fun num_wid {sn:pos | sn <= 3}{i:nat}{w:int | w == 2 || w == 3}
  (pre: string sn, i: int i, w: int w): $W.widget_id
implement num_wid(pre, i, w) = _num_wid(pre, i, w)

#pub fun num_id {sn:pos | sn <= 3}{i:nat}{w:int | w == 2 || w == 3}
  (pre: string sn, i: int i, w: int w): [l:agz][k:pos | k <= 16] @($A.arr(byte, l, k), int k)
implement num_id(pre, i, w) = _num_id(pre, i, w)

end (* #target wasm *)
