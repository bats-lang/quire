(* reader -- Chapter rendering, pagination, navigation *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use xml-tree as X
#use zip as Z
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

fn _apply_diff_list(dl: $W.diff_list): void = let
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val doc = $D.open_document($S.text_of_chars(mid, 9), 9)
  val () = $D.apply_list(doc, dl)
  val () = $D.destroy(doc)
in end

fn _apply_diff(d: $W.diff): void = let
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val doc = $D.open_document($S.text_of_chars(mid, 9), 9)
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
  case+ reading_get() of Reading(p, _, c, _) => _save_pos(c, p)

(* Save EPUB file bytes to IDB *)
fn _save_epub_to_idb(): void =
  case+ book_get() of
  | NoBook() => ()
  | OpenBook(fh, fsz, _, _, _, _, _) => let
      val fbuf = $A.alloc<byte>(fsz)
      val () = $FI.file_read(fh, 0, fbuf, fsz)
      val @(ff, fb) = $A.freeze<byte>(fbuf)
      val ka = $A.alloc<byte>(4)
      val () = $A.set<byte>(ka, 0, int2byte0(98))  (* b *)
      val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 2, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 3, int2byte0(107)) (* k *)
      val @(kf, kb) = $A.freeze<byte>(ka)
      val p = $IDB.idb_put(kb, 4, fb, fsz)
      val () = $P.discard<Int>(p)
      val () = $A.drop<byte>(kf, kb)
      val kt = $A.thaw<byte>(kf)
      val () = $A.free<byte>(kt)
      val () = $A.drop<byte>(ff, fb)
      val ft = $A.thaw<byte>(ff)
    in $A.free<byte>(ft) end

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
  val txt = _prefix_text(tbuf, 44, off)
  var pi_c = @[char][4]('q', 'p', 'g', 'i')
  val pi_id = $W.Generated($S.text_of_chars(pi_c, 4), 4)
in _apply_diff($W.SetTextContent(pi_id, txt, off)) end

fn _update_page_indicator(): void =
  case+ reading_get() of Reading(p, t, c, _) => _show_indicator(p, t, c)

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
    | Reading(_, _, c, tc) => reading_set(Reading(0, t, c, tc)))
in _update_page_indicator() end

(* Shows page p of the chapter's t pages *)
fn _show_page {t:pos}{p:nat | p < t}{c,tc:nat}
  (p: int p, t: int t, c: int c, tc: int tc): void = let
  val () = reading_set(Reading(p, t, c, tc))
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

(* Generate widget_id for content node at index *)
fn _content_wid {i:nat} (idx: int i): $W.widget_id = _num_wid("c", idx, 3)

(* The parent's widget_id: ~1 is the content area qcnt, and i >= 0 is
   content node i *)
fn _parent_wid {q:int | q >= ~1} (pidx: int q): $W.widget_id =
  if pidx < 0 then let
    var c = @[char][4]('q', 'c', 'n', 't')
  in $W.Generated($S.text_of_chars(c, 4), 4) end
  else _content_wid(pidx)

(* Get next content node index and increment counter *)
fn _next_content_idx(): [n:nat] int n = let
  val n = !_content_n
  val () = !_content_n := n + 1
in n end

(* Match XHTML tag name to widget html_normal type *)
fn _match_tag_to_normal
  {lb:agz}{n:pos}{o,k:nat | o + k <= n}
  (data: !$A.borrow(byte, lb, n), len: int n,
   name_off: int o, name_len: int k): $W.html_normal = let
  var _t_p = @[char][1]('p')
  var _t_h1 = @[char][2]('h', '1')
  var _t_h2 = @[char][2]('h', '2')
  var _t_h3 = @[char][2]('h', '3')
  var _t_h4 = @[char][2]('h', '4')
  var _t_h5 = @[char][2]('h', '5')
  var _t_h6 = @[char][2]('h', '6')
  var _t_div = @[char][3]('d', 'i', 'v')
  var _t_span = @[char][4]('s', 'p', 'a', 'n')
  var _t_em = @[char][2]('e', 'm')
  var _t_strong = @[char][6]('s', 't', 'r', 'o', 'n', 'g')
  var _t_bq = @[char][10]('b', 'l', 'o', 'c', 'k', 'q', 'u', 'o', 't', 'e')
  var _t_pre = @[char][3]('p', 'r', 'e')
  var _t_code = @[char][4]('c', 'o', 'd', 'e')
  var _t_ul = @[char][2]('u', 'l')
  var _t_ol = @[char][2]('o', 'l')
  var _t_li = @[char][2]('l', 'i')
  var _t_section = @[char][7]('s', 'e', 'c', 't', 'i', 'o', 'n')
  var _t_article = @[char][7]('a', 'r', 't', 'i', 'c', 'l', 'e')
  var _t_small = @[char][5]('s', 'm', 'a', 'l', 'l')
  var _t_mark = @[char][4]('m', 'a', 'r', 'k')
  var _t_del = @[char][3]('d', 'e', 'l')
  var _t_ins = @[char][3]('i', 'n', 's')
  var _t_sub = @[char][3]('s', 'u', 'b')
  var _t_sup = @[char][3]('s', 'u', 'p')
  var _t_a = @[char][1]('a')
  var _t_b = @[char][1]('b')
  var _t_i = @[char][1]('i')
  var _t_u = @[char][1]('u')
  var _t_s = @[char][1]('s')
  var _t_figure = @[char][6]('f', 'i', 'g', 'u', 'r', 'e')
  var _t_figcap = @[char][10]('f', 'i', 'g', 'c', 'a', 'p', 't', 'i', 'o', 'n')
  var _t_table = @[char][5]('t', 'a', 'b', 'l', 'e')
  var _t_tr = @[char][2]('t', 'r')
  var _t_td = @[char][2]('t', 'd')
  var _t_th = @[char][2]('t', 'h')
  var _t_thead = @[char][5]('t', 'h', 'e', 'a', 'd')
  var _t_tbody = @[char][5]('t', 'b', 'o', 'd', 'y')
in
  if xml_name_eq(data, name_off, name_len, _t_p, 1) then $W.P()
  else if xml_name_eq(data, name_off, name_len, _t_h1, 2) then $W.H1()
  else if xml_name_eq(data, name_off, name_len, _t_h2, 2) then $W.H2()
  else if xml_name_eq(data, name_off, name_len, _t_h3, 2) then $W.H3()
  else if xml_name_eq(data, name_off, name_len, _t_h4, 2) then $W.H4()
  else if xml_name_eq(data, name_off, name_len, _t_h5, 2) then $W.H5()
  else if xml_name_eq(data, name_off, name_len, _t_h6, 2) then $W.H6()
  else if xml_name_eq(data, name_off, name_len, _t_div, 3) then $W.Div()
  else if xml_name_eq(data, name_off, name_len, _t_span, 4) then $W.Span()
  else if xml_name_eq(data, name_off, name_len, _t_em, 2) then $W.Em()
  else if xml_name_eq(data, name_off, name_len, _t_strong, 6) then $W.Strong()
  else if xml_name_eq(data, name_off, name_len, _t_bq, 10) then $W.Blockquote()
  else if xml_name_eq(data, name_off, name_len, _t_pre, 3) then $W.Pre()
  else if xml_name_eq(data, name_off, name_len, _t_code, 4) then $W.HtmlCode()
  else if xml_name_eq(data, name_off, name_len, _t_ul, 2) then $W.Ul()
  else if xml_name_eq(data, name_off, name_len, _t_ol, 2) then $W.Ol($W.OlDefault())
  else if xml_name_eq(data, name_off, name_len, _t_li, 2) then $W.Li()
  else if xml_name_eq(data, name_off, name_len, _t_section, 7) then $W.Section()
  else if xml_name_eq(data, name_off, name_len, _t_article, 7) then $W.Article()
  else if xml_name_eq(data, name_off, name_len, _t_small, 5) then $W.Small()
  else if xml_name_eq(data, name_off, name_len, _t_mark, 4) then $W.Mark()
  else if xml_name_eq(data, name_off, name_len, _t_del, 3) then $W.Del()
  else if xml_name_eq(data, name_off, name_len, _t_ins, 3) then $W.Ins()
  else if xml_name_eq(data, name_off, name_len, _t_sub, 3) then $W.HtmlSub()
  else if xml_name_eq(data, name_off, name_len, _t_sup, 3) then $W.Sup()
  else if xml_name_eq(data, name_off, name_len, _t_a, 1) then $W.Span()
  else if xml_name_eq(data, name_off, name_len, _t_b, 1) then $W.Span()
  else if xml_name_eq(data, name_off, name_len, _t_i, 1) then $W.Span()
  else if xml_name_eq(data, name_off, name_len, _t_u, 1) then $W.Span()
  else if xml_name_eq(data, name_off, name_len, _t_s, 1) then $W.Span()
  else if xml_name_eq(data, name_off, name_len, _t_figure, 6) then $W.Figure()
  else if xml_name_eq(data, name_off, name_len, _t_figcap, 10) then $W.Figcaption()
  else if xml_name_eq(data, name_off, name_len, _t_table, 5) then $W.Table()
  else if xml_name_eq(data, name_off, name_len, _t_tr, 2) then $W.Tr()
  else if xml_name_eq(data, name_off, name_len, _t_td, 2) then $W.Td(1, 1)
  else if xml_name_eq(data, name_off, name_len, _t_th, 2) then $W.Th(1, 1, $W.NoScope())
  else if xml_name_eq(data, name_off, name_len, _t_thead, 5) then $W.Thead()
  else if xml_name_eq(data, name_off, name_len, _t_tbody, 5) then $W.Tbody()
  else $W.Div()
end

(* Walk xml_node_list, rendering each node into parent *)
fun _render_nodes
  {lb:agz}{n:pos}{sz:nat}{q:int | q >= ~1} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int q, nodes: !$X.xml_node_list(n, sz)): void =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val () = _render_node(data, len, pidx, node)
    in _render_nodes(data, len, pidx, rest) end
  | $X.xml_nodes_nil() => ()

and _render_node
  {lb:agz}{n:pos}{sz:pos}{q:int | q >= ~1} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int q, node: !$X.xml_node(n, sz)): void =
  case+ node of
  | $X.xml_text(off, tlen) =>
    (* To do: a text node of 64 KiB or more (SetTextContent's limit) is
       not shown; it should be split. *)
      if tlen < 65536 then let
        val tsz = tlen
        val tbuf = $A.alloc<byte>(tsz)
        val () = $S.copy_from_borrow(data, off, len, tbuf, 0, tsz, tlen)
        val txt = arr_to_text(tbuf, tsz)
        val () = $A.free<byte>(tbuf)
        val idx = _next_content_idx()
        val w = $W.Element($W.ElementNode(_content_wid(idx),
          $W.Normal($W.Span()), $W.NoClass(), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
        val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        val () = _apply_diff($W.SetTextContent(_content_wid(idx), txt, tsz))
      in end
      else ()
  | $X.xml_element(name_off, name_len, _, children) => let
    (* Skip tags: head, title, meta, link, style, script *)
    var _t_head = @[char][4]('h', 'e', 'a', 'd')
    var _t_title = @[char][5]('t', 'i', 't', 'l', 'e')
    var _t_meta = @[char][4]('m', 'e', 't', 'a')
    var _t_link = @[char][4]('l', 'i', 'n', 'k')
    var _t_style = @[char][5]('s', 't', 'y', 'l', 'e')
    var _t_script = @[char][6]('s', 'c', 'r', 'i', 'p', 't')
  in
    if xml_name_eq(data, name_off, name_len, _t_head, 4) then ()
    else if xml_name_eq(data, name_off, name_len, _t_title, 5) then ()
    else if xml_name_eq(data, name_off, name_len, _t_meta, 4) then ()
    else if xml_name_eq(data, name_off, name_len, _t_link, 4) then ()
    else if xml_name_eq(data, name_off, name_len, _t_style, 5) then ()
    else if xml_name_eq(data, name_off, name_len, _t_script, 6) then ()
    else let
      (* Transparent tags: html, body — render children with same parent *)
      var _t_html = @[char][4]('h', 't', 'm', 'l')
      var _t_body = @[char][4]('b', 'o', 'd', 'y')
    in
      if xml_name_eq(data, name_off, name_len, _t_html, 4) then
        _render_nodes(data, len, pidx, children)
      else if xml_name_eq(data, name_off, name_len, _t_body, 4) then
        _render_nodes(data, len, pidx, children)
      else let
        (* Void tags: br, hr *)
        var _t_br = @[char][2]('b', 'r')
        var _t_hr = @[char][2]('h', 'r')
      in
        if xml_name_eq(data, name_off, name_len, _t_br, 2) then let
          val idx = _next_content_idx()
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Void($W.Br()), $W.NoClass(), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        in end
        else if xml_name_eq(data, name_off, name_len, _t_hr, 2) then let
          val idx = _next_content_idx()
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Void($W.Hr()), $W.NoClass(), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        in end
        else let
          (* Normal element: match tag name, create element, recurse *)
          val idx = _next_content_idx()
          val tag = _match_tag_to_normal(data, len, name_off, name_len)
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Normal(tag), $W.NoClass(), false, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
          val () = _render_nodes(data, len, idx, children)
        in end
      end
    end
  end

(* Just past the last '/' in buf[p, e), or la if there is none *)
fun _after_last_slash {l:agz}{n:pos}{p,e:nat | p <= e; e <= n}{la:int | la <= p} .<e - p>.
  (buf: !$A.arr(byte, l, n), p: int p, e: int e, la: int la): [r:int | la <= r; r <= e] int r =
  if p >= e then la
  else if byte2int0($A.get<byte>(buf, p)) = 47 then _after_last_slash(buf, p + 1, e, p + 1)
  else _after_last_slash(buf, p + 1, e, la)

(* The entry named name in the archive buf *)
fn _find_zip_entry {l:agz}{n:pos}{lb:agz}{nb:pos}
  (buf: !$A.arr(byte, l, n), n: int n, name: !$A.borrow(byte, lb, nb), nb: int nb)
  : $R.option($Z.zip_entry(n)) =
  case+ $Z.find_dir(buf, n) of
  | ~$R.some(dir) => $Z.find_entry(buf, n, dir, name, nb)
  | ~$R.none() => $R.none()

fn _load_chapter {i:nat} (chapter_idx: int i): $P.promise(int, $P.Chained) =
  case+ book_get() of
  | NoBook() => $P.ret<int>(~1)
  | OpenBook(fh, fsz_s, opf_doff, opf_csz, opf_comp, opf_name_off, opf_name_len) => let
    (* Read full file *)
    val fbuf2 = $A.alloc<byte>(fsz_s)
    val () = $FI.file_read(fh, 0, fbuf2, fsz_s)

    val opf_csz_s = opf_csz
    val opf_cbuf = $A.alloc<byte>(opf_csz_s)
    val fbuf2 = $S.copy_arr_region(fbuf2, opf_doff, fsz_s,
                                  opf_cbuf, opf_csz_s, opf_csz_s)
    val () = $A.free<byte>(fbuf2)

    val @(ocf, ocb) = $A.freeze<byte>(opf_cbuf)
    val dc_p = $DC.decompress(ocb, opf_csz_s, opf_comp)
    val () = $A.drop<byte>(ocf, ocb)
    val opf_cbuf2 = $A.thaw<byte>(ocf)
    val () = $A.free<byte>(opf_cbuf2)

    val dc_p = $P.vow(dc_p)
  in
    (* Stage 2: parse OPF to find first chapter href *)
    $P.and_then<Int><int>(dc_p, lam(dc_handle) => let
      val dc = take_blob(dc_handle)
    in
      case+ dc of
      | ~NoBlobBytes() => $P.ret<int>(~2)
      | ~BlobBytes(opf_buf, dc_sz) => let

        val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
        val opf_nodes = $X.parse_document(opf_b, dc_sz)

        (* Count spine items and store total chapters *)
        val total_ch = count_spine_items(opf_b, opf_nodes)
        val () = (case+ reading_get() of
          | Reading(p, t, c, _) => reading_set(Reading(p, t, c, total_ch)))

        (* Find Nth spine itemref → manifest item href *)
        val ch_href = find_chapter_href_n(opf_b, dc_sz, opf_nodes, chapter_idx)
      in
        case+ ch_href of
        | xspan_none() => let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        | xspan_at(ch_off, ch_len) =>
        if ch_len <= 0 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        else let
          (* Re-read file now so we can access the OPF name
             in the central directory for path prefix resolution *)
          val fsz_s3 = fsz_s
          val fbuf3 = $A.alloc<byte>(fsz_s3)
          val () = $FI.file_read(fh, 0, fbuf3, fsz_s3)

          (* Find directory prefix from OPF name in central directory.
             The OPF path e.g. "OEBPS/content.opf" tells us the
             directory prefix "OEBPS/" to prepend to chapter hrefs. *)
          val prefix_end = _after_last_slash(fbuf3, opf_name_off, opf_name_off + opf_name_len, opf_name_off)
          val prefix_len = prefix_end - opf_name_off

          (* Build full path: prefix + href *)
          val full_len = prefix_len + ch_len
        in
          if full_len > 1048576 then let
            val () = $A.free<byte>(fbuf3)
            val () = $X.free_nodes(opf_nodes)
            val () = $A.drop<byte>(opf_f, opf_b)
            val t = $A.thaw<byte>(opf_f)
            val () = $A.free<byte>(t)
          in $P.ret<int>(~4) end
          else let
          val full_len_s = full_len
          val ch_buf = $A.alloc<byte>(full_len_s)
          (* The prefix from the file, then the chapter href from the OPF *)
          val fbuf3 = $S.copy_arr_region(fbuf3, opf_name_off, fsz_s3,
                    ch_buf, full_len_s, prefix_len)
          val () = $S.copy_from_borrow(opf_b, ch_off, dc_sz,
                    ch_buf, prefix_len, full_len_s, ch_len)

          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)

          val @(chf, chb) = $A.freeze<byte>(ch_buf)
          val ch_entry = _find_zip_entry(fbuf3, fsz_s3, chb, full_len_s)
          val () = $A.drop<byte>(chf, chb)
          val ch_buf2 = $A.thaw<byte>(chf)
          val () = $A.free<byte>(ch_buf2)
        in
          case+ ch_entry of
          | ~$R.none() => let
            val () = $A.free<byte>(fbuf3)
          in $P.ret<int>(~4) end
          | ~$R.some($Z.zip_entry_mk(_, _, ch_doff, ch_csz, ch_method, _)) =>
            if ch_csz <= 0 then let
              val () = $A.free<byte>(fbuf3)
            in $P.ret<int>(~5) end
            else let
              val ch_comp = $A.alloc<byte>(ch_csz)
              val fbuf3 = $S.copy_arr_region(fbuf3, ch_doff, fsz_s3,
                                        ch_comp, ch_csz, ch_csz)
              val () = $A.free<byte>(fbuf3)

              val @(ccf, ccb) = $A.freeze<byte>(ch_comp)
              val ch_dc_p = $DC.decompress(ccb, ch_csz, ch_method)
              val () = $A.drop<byte>(ccf, ccb)
              val ch_comp2 = $A.thaw<byte>(ccf)
              val () = $A.free<byte>(ch_comp2)

              val ch_dc_p = $P.vow(ch_dc_p)
            in
              (* Stage 3: parse HTML and render *)
              $P.and_then<Int><int>(ch_dc_p, lam(ch_dc_handle) => let
                val ch_dc = take_blob(ch_dc_handle)
              in
                case+ ch_dc of
                | ~NoBlobBytes() => $P.ret<int>(~6)
                | ~BlobBytes(ch_xhtml, ch_dc_sz) => let

                  (* Parse XHTML with xml-tree *)
                  val @(xf, xb) = $A.freeze<byte>(ch_xhtml)
                  val nodes = $X.parse_document(xb, ch_dc_sz)

                  (* Clear content area *)
                  var cnt_c = @[char][4]('q', 'c', 'n', 't')
                  val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
                  val () = _apply_diff($W.RemoveAllChildren(cnt_id))
                  val () = !_content_n := 0

                  (* Render XHTML tree into content area *)
                  val () = _render_nodes(xb, ch_dc_sz, ~1, nodes)
                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(xf, xb)
                  val ch_xhtml2 = $A.thaw<byte>(xf)
                  val () = $A.free<byte>(ch_xhtml2)

                  val () = (case+ reading_get() of
                    | Reading(p, t, _, tc) => reading_set(Reading(p, t, chapter_idx + 1, tc)))
                  (* Update chapter title in nav bar *)
                  val ch_num = chapter_idx + 1
                  var ct_c = @[char][4]('q', 'c', 'h', 't')
                  val ct_id = $W.Generated($S.text_of_chars(ct_c, 4), 4)
                  (* "Chapter " (8 bytes) and the number (at most 11) *)
                  val tbuf = $A.alloc<byte>(19)
                  val off = _put(tbuf, 0, "Chapter ")
                  val off = $S.int_to_str(tbuf, off, 19, ch_num)
                  val () = _apply_diff($W.SetTextContent(ct_id, _prefix_text(tbuf, 19, off), off))
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

(* The next page: in this chapter, else the next chapter's first *)
fn _page_next(): void =
  case+ reading_get() of
  | Reading(p, t, c, tc) =>
    if p + 1 < t then _show_page(p + 1, t, c, tc)
    else if c < tc then $P.discard<int>(_load_chapter(c))
    else _show_page(p, t, c, tc)

(* The previous page: in this chapter, else the previous chapter's
   first *)
fn _page_prev(): void =
  case+ reading_get() of
  | Reading(p, t, c, tc) =>
    if p > 0 then _show_page(p - 1, t, c, tc)
    else if c > 1 then $P.discard<int>(_load_chapter(c - 2))
    else _show_page(0, t, c, tc)

(* Page pg, saved by an earlier run: the last page if the chapter now
   has fewer *)
fn _show_saved_page {g:nat} (pg: int g): void =
  case+ reading_get() of
  | Reading(_, t, c, tc) =>
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
  val p2 = $P.and_then<Int><int>(font_p, lam(font_len) =>
    if font_len <> 2 then $P.ret<int>(~1)
    else let
      val fdata = $IDB.idb_get_result(2)
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

(* Restore reading state from IDB on startup *)
fn _restore_from_idb(): void = let
  (* Step 1: get "book" from IDB *)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(98))  (* b *)
  val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 2, int2byte0(111)) (* o *)
  val () = $A.set<byte>(ka, 3, int2byte0(107)) (* k *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val book_p = $IDB.idb_get(kb, 4)
  val () = $A.drop<byte>(kf, kb)
  val ktmp = $A.thaw<byte>(kf)
  val () = $A.free<byte>(ktmp)
  val book_p = $P.vow(book_p)
  val p2 = $P.and_then<Int><int>(book_p, lam(book_len) =>
    if book_len <= 0 then $P.ret<int>(~1)
    else if book_len > 1048576 then $P.ret<int>(~1)
    else let
      (* Read EPUB bytes from IDB result *)
      val bsz = book_len
      val book_data = $IDB.idb_get_result(bsz)
      (* Store into file cache *)
      val @(bf, bb) = $A.freeze<byte>(book_data)
      val fh = $FI.file_store(bb, bsz)
      val () = $A.drop<byte>(bf, bb)
      val btmp = $A.thaw<byte>(bf)
      val () = $A.free<byte>(btmp)

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
      $P.and_then<Int><int>(meta_p, lam(meta_len) =>
        if meta_len <> 36 then $P.ret<int>(~2)
        else let
          (* 9 x 4-byte ints (see _save_metadata_to_idb), stored by an
             earlier run: checked here, once, against the book's bytes *)
          val meta_data = $IDB.idb_get_result(36)
          val d = _get_i32(meta_data, 16)
          val sz = _get_i32(meta_data, 20)
          val m = _get_i32(meta_data, 24)
          val no = _get_i32(meta_data, 28)
          val nl = _get_i32(meta_data, 32)
          val () = $A.free<byte>(meta_data)
          val ok = (if d < 0 then false else if d > bsz then false
            else if sz <= 0 then false else if sz > bsz - d then false
            else if no < 0 then false else if no > bsz then false
            else if nl < 0 then false else if nl > bsz - no then false
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
          $P.and_then<Int><int>(pos_p, lam(pos_len) =>
            if pos_len <> 4 then let
              (* No saved position — just load chapter 0 *)
              (* Show reader, hide library *)
              var ll_c = @[char][4]('q', 'l', 'l', 'c')
              val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
              var rv_c = @[char][4]('q', 'r', 'v', 'w')
              val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
              val () = _apply_diff($W.SetHidden(ll_id, true))
              val () = _apply_diff($W.SetHidden(rv_id, false))
              val ch_p = _load_chapter(0)
              val () = $P.discard<int>(ch_p)
            in $P.ret<int>(0) end
            else let
              val pos_data = $IDB.idb_get_result(4)
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
