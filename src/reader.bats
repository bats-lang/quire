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
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/stash.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload SC = "wasm.bats-packages.dev/bridge/src/scroll.sats"

fn _apply_diff_list(dl: $W.diff_list): void = let
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val nid = $ST.stash_get_int(20)
  val doc = $D.open_document($S.text_of_chars(mid, 9), 9, nid)
  val () = $D.apply_list(doc, dl)
  val nid2 = $D.get_next_id(doc)
  val () = $ST.stash_set_int(20, nid2)
  val () = $D.destroy(doc)
in end

fn _apply_diff(d: $W.diff): void = let
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val nid = $ST.stash_get_int(20)
  val doc = $D.open_document($S.text_of_chars(mid, 9), 9, nid)
  val () = $D.apply(doc, d)
  val nid2 = $D.get_next_id(doc)
  val () = $ST.stash_set_int(20, nid2)
  val () = $D.destroy(doc)
in end

(* ============================================================
   Persistence helpers (IDB)
   ============================================================ *)

(* Save reading position to IDB: 4 bytes = u16 chapter + u16 page *)
fn _save_position(): void = let
  val ch = $ST.stash_get_int(23)
  val pg = $ST.stash_get_int(21)
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
  val () = $P.discard<int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
in end

(* Save EPUB file bytes to IDB *)
fn _save_epub_to_idb(): void = let
  val fh = $ST.stash_get_int(10)
  val fsz = $ST.stash_get_int(11)
in
  if fsz > 0 then
    if fsz <= 1048576 then let
      val fsz_s = $AR.checked_arr_size(fsz)
      val fbuf = $A.alloc<byte>(fsz_s)
      val () = $R.discard($FI.file_read(fh, 0, fbuf, fsz_s))
      val @(ff, fb) = $A.freeze<byte>(fbuf)
      val ka = $A.alloc<byte>(4)
      val () = $A.set<byte>(ka, 0, int2byte0(98))  (* b *)
      val () = $A.set<byte>(ka, 1, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 2, int2byte0(111)) (* o *)
      val () = $A.set<byte>(ka, 3, int2byte0(107)) (* k *)
      val @(kf, kb) = $A.freeze<byte>(ka)
      val p = $IDB.idb_put(kb, 4, fb, fsz_s)
      val () = $P.discard<int>(p)
      val () = $A.drop<byte>(kf, kb)
      val kt = $A.thaw<byte>(kf)
      val () = $A.free<byte>(kt)
      val () = $A.drop<byte>(ff, fb)
      val ft = $A.thaw<byte>(ff)
      val () = $A.free<byte>(ft)
    in end
    else ()
  else ()
end

(* Save stash metadata to IDB: slots 10-18 as 9 x 4-byte ints *)
fn _save_metadata_to_idb(): void = let
  val buf = $A.alloc<byte>(36)
  fun _write_slot {l:agz}{n:pos}{s:nat}{fuel:nat} .<fuel>.
    (buf: !$A.arr(byte, l, n), max: int n,
     slot: int s, off: int, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if slot >= 32 then ()
    else if off < 0 then ()
    else if off + 3 >= max then ()
    else let
      val v = $ST.stash_get_int(slot)
      val () = $A.set<byte>(buf, $AR.checked_idx(off, max), int2byte0(v mod 256))
      val () = $A.set<byte>(buf, $AR.checked_idx(off + 1, max), int2byte0((v / 256) mod 256))
      val () = $A.set<byte>(buf, $AR.checked_idx(off + 2, max), int2byte0((v / 65536) mod 256))
      val () = $A.set<byte>(buf, $AR.checked_idx(off + 3, max), int2byte0((v / 16777216) mod 256))
    in _write_slot(buf, max, slot + 1, off + 4, fuel - 1) end
  val () = _write_slot(buf, 36, 10, 0, 9)
  val @(bf, bb) = $A.freeze<byte>(buf)
  val ka = $A.alloc<byte>(4)
  val () = $A.set<byte>(ka, 0, int2byte0(109)) (* m *)
  val () = $A.set<byte>(ka, 1, int2byte0(101)) (* e *)
  val () = $A.set<byte>(ka, 2, int2byte0(116)) (* t *)
  val () = $A.set<byte>(ka, 3, int2byte0(97))  (* a *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_put(kb, 4, bb, 36)
  val () = $P.discard<int>(p)
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

(* Write an integer into a byte buffer at offset, return new offset *)
fun _write_int_digits
  {l:agz}{n:pos}{v:nat}{fuel:nat} .<fuel>.
  (buf: !$A.arr(byte, l, n), max: int n,
   off: int, value: int v, fuel: int fuel): int =
  if fuel <= 0 then off
  else if value < 10 then
    if off >= 0 then
      if off < max then let
        val () = $A.set<byte>(buf, $AR.checked_idx(off, max), int2byte0(48 + value))
      in off + 1 end
      else off
    else off
  else let
    val new_off = _write_int_digits(buf, max, off, value / 10, fuel - 1)
  in
    if new_off >= 0 then
      if new_off < max then let
        val () = $A.set<byte>(buf, $AR.checked_idx(new_off, max),
          int2byte0(48 + (value - (value / 10) * 10)))
      in new_off + 1 end
      else new_off
    else new_off
  end

fn _set_byte
  {l:agz}{n:pos}
  (buf: !$A.arr(byte, l, n), max: int n, off: int, b: int): int =
  if off >= 0 then
    if off < max then let
      val () = $A.set<byte>(buf, $AR.checked_idx(off, max), int2byte0(b))
    in off + 1 end
    else off
  else off

(* Apply font size to content area via dynamic style element *)
(* Writes ".caf{font-size:NNpx}" to style element qfss *)
fn _apply_font_size(size: int): void = let
  val sz = (if size < 8 then 8 else if size > 48 then 48 else size): int
  val () = $ST.stash_set_int(25, sz)
  (* Build CSS string ".caf{font-size:NNpx}" — max 22 bytes *)
  val buf = $A.alloc<byte>(22)
  val off = _set_byte(buf, 22, 0, 46)   (* . *)
  val off = _set_byte(buf, 22, off, 99)  (* c *)
  val off = _set_byte(buf, 22, off, 97)  (* a *)
  val off = _set_byte(buf, 22, off, 102) (* f *)
  val off = _set_byte(buf, 22, off, 123) (* { *)
  val off = _set_byte(buf, 22, off, 102) (* f *)
  val off = _set_byte(buf, 22, off, 111) (* o *)
  val off = _set_byte(buf, 22, off, 110) (* n *)
  val off = _set_byte(buf, 22, off, 116) (* t *)
  val off = _set_byte(buf, 22, off, 45)  (* - *)
  val off = _set_byte(buf, 22, off, 115) (* s *)
  val off = _set_byte(buf, 22, off, 105) (* i *)
  val off = _set_byte(buf, 22, off, 122) (* z *)
  val off = _set_byte(buf, 22, off, 101) (* e *)
  val off = _set_byte(buf, 22, off, 58)  (* : *)
  val off = _write_int_digits(buf, 22, off, $AR.checked_nat(sz), 3)
  val off = _set_byte(buf, 22, off, 112) (* p *)
  val off = _set_byte(buf, 22, off, 120) (* x *)
  val off = _set_byte(buf, 22, off, 125) (* } *)
in
  if off > 0 then
    if off <= 22 then let
      val tsz = $AR.checked_text_size(off)
      val exact = $A.alloc<byte>(tsz)
      fun _fcopy {la:agz}{na:pos}{lb:agz}{nb:pos}{i:nat | i <= na} .<na - i>.
        (src: !$A.arr(byte, la, na), dst: !$A.arr(byte, lb, nb),
         max_s: int na, max_d: int nb, i: int i): void =
        if i >= max_s then ()
        else if i >= max_d then ()
        else let
          val b = $A.get<byte>(src, $AR.checked_idx(i, max_s))
          val () = $A.set<byte>(dst, $AR.checked_idx(i, max_d), b)
        in _fcopy(src, dst, max_s, max_d, i + 1) end
      val () = _fcopy(buf, exact, 22, tsz, 0)
      val () = $A.free<byte>(buf)
      val txt = arr_to_text(exact, tsz)
      val () = $A.free<byte>(exact)
      var fs_c = @[char][4]('q', 'f', 's', 's')
      val fs_id = $W.Generated($S.text_of_chars(fs_c, 4), 4)
      val () = _apply_diff($W.SetTextContent(fs_id, txt, tsz))
    in end
    else $A.free<byte>(buf)
  else $A.free<byte>(buf)
end

(* Save font size to IDB *)
fn _save_font_size(): void = let
  val sz = $ST.stash_get_int(25)
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
  val () = $P.discard<int>(p)
  val () = $A.drop<byte>(kf, kb)
  val kt = $A.thaw<byte>(kf)
  val () = $A.free<byte>(kt)
  val () = $A.drop<byte>(bf, bb)
  val bt = $A.thaw<byte>(bf)
  val () = $A.free<byte>(bt)
in end

fn _update_page_indicator(): void = let
  val cur_page = $ST.stash_get_int(21)
  val total = $ST.stash_get_int(22)
  val chapter = $ST.stash_get_int(23)
  (* Build "Ch N · p. M/T" in a 24-byte buffer *)
  val tbuf = $A.alloc<byte>(24)
  val off = _set_byte(tbuf, 24, 0, 67)  (* C *)
  val off = _set_byte(tbuf, 24, off, 104) (* h *)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _write_int_digits(tbuf, 24, off, $AR.checked_nat(chapter), 3)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _set_byte(tbuf, 24, off, 194) (* 0xC2 = first byte of · *)
  val off = _set_byte(tbuf, 24, off, 183) (* 0xB7 = second byte of · *)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _set_byte(tbuf, 24, off, 112) (* p *)
  val off = _set_byte(tbuf, 24, off, 46)  (* . *)
  val off = _set_byte(tbuf, 24, off, 32)  (* space *)
  val off = _write_int_digits(tbuf, 24, off, $AR.checked_nat(cur_page + 1), 3)
  val off = _set_byte(tbuf, 24, off, 47)  (* / *)
  val off = _write_int_digits(tbuf, 24, off, $AR.checked_nat(total), 3)
in
  if off > 0 then
    if off < 24 then let
      (* Copy to exact-size buffer for text conversion *)
      val tsz = $AR.checked_text_size(off)
      val exact = $A.alloc<byte>(tsz)
      fun _copy {la:agz}{na:pos}{lb:agz}{nb:pos}{i:nat | i <= na} .<na - i>.
        (src: !$A.arr(byte, la, na), dst: !$A.arr(byte, lb, nb),
         max_s: int na, max_d: int nb, i: int i): void =
        if i >= max_s then ()
        else if i >= max_d then ()
        else let
          val b = $A.get<byte>(src, $AR.checked_idx(i, max_s))
          val () = $A.set<byte>(dst, $AR.checked_idx(i, max_d), b)
        in _copy(src, dst, max_s, max_d, i + 1) end
      val () = _copy(tbuf, exact, 24, tsz, 0)
      val () = $A.free<byte>(tbuf)
      val txt = arr_to_text(exact, tsz)
      val () = $A.free<byte>(exact)
      var pi_c = @[char][4]('q', 'p', 'g', 'i')
      val pi_id = $W.Generated($S.text_of_chars(pi_c, 4), 4)
      val () = _apply_diff($W.SetTextContent(pi_id, txt, tsz))
    in end
    else let
      val () = $A.free<byte>(tbuf)
    in end
  else let
    val () = $A.free<byte>(tbuf)
  in end
end

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
  val cw = $DR.get_measure_w()
  val sw = $DR.get_measure_scroll_w()
in
  if cw > 0 then let
    val total = sw / cw
    val total_p = (if total < 1 then 1 else total): int
    val () = $ST.stash_set_int(21, 0)
    val () = $ST.stash_set_int(22, total_p)
    val () = _update_page_indicator()
  in end
  else let
    val () = $ST.stash_set_int(21, 0)
    val () = $ST.stash_set_int(22, 1)
    val () = _update_page_indicator()
  in end
end

fn _scroll_to_page(page: int): void = let
  val () = $ST.stash_set_int(21, page)
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

(* Stash slot 28: content node counter *)

(* Generate widget_id for content node at index *)
fn _content_wid(idx: int): $W.widget_id = let
  val n = idx - (idx / 1000) * 1000
  val d2 = n / 100
  val r2 = n - d2 * 100
  val d1 = r2 / 10
  val d0 = r2 - d1 * 10
  val buf = $A.alloc<byte>(4)
  val () = $A.set<byte>(buf, 0, int2byte0(99))
  val () = $A.set<byte>(buf, 1, int2byte0(48 + d2))
  val () = $A.set<byte>(buf, 2, int2byte0(48 + d1))
  val () = $A.set<byte>(buf, 3, int2byte0(48 + d0))
  val txt = arr_to_text(buf, 4)
  val () = $A.free<byte>(buf)
in $W.Generated(txt, 4) end

(* Generate widget_id for parent: -1 = qcnt, >= 0 = content node *)
fn _parent_wid(pidx: int): $W.widget_id =
  if pidx < 0 then let
    var c = @[char][4]('q', 'c', 'n', 't')
  in $W.Generated($S.text_of_chars(c, 4), 4) end
  else _content_wid(pidx)

(* Get next content node index and increment counter *)
fn _next_content_idx(): int = let
  val n = $ST.stash_get_int(28)
  val () = $ST.stash_set_int(28, n + 1)
in n end

(* Match XHTML tag name to widget html_normal type *)
fn _match_tag_to_normal
  {lb:agz}{n:pos}
  (data: !$A.borrow(byte, lb, n), len: int n,
   name_off: int, name_len: int): $W.html_normal = let
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
  if xml_name_eq(data, len, name_off, name_len, _t_p, 1) then $W.P()
  else if xml_name_eq(data, len, name_off, name_len, _t_h1, 2) then $W.H1()
  else if xml_name_eq(data, len, name_off, name_len, _t_h2, 2) then $W.H2()
  else if xml_name_eq(data, len, name_off, name_len, _t_h3, 2) then $W.H3()
  else if xml_name_eq(data, len, name_off, name_len, _t_h4, 2) then $W.H4()
  else if xml_name_eq(data, len, name_off, name_len, _t_h5, 2) then $W.H5()
  else if xml_name_eq(data, len, name_off, name_len, _t_h6, 2) then $W.H6()
  else if xml_name_eq(data, len, name_off, name_len, _t_div, 3) then $W.Div()
  else if xml_name_eq(data, len, name_off, name_len, _t_span, 4) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_em, 2) then $W.Em()
  else if xml_name_eq(data, len, name_off, name_len, _t_strong, 6) then $W.Strong()
  else if xml_name_eq(data, len, name_off, name_len, _t_bq, 10) then $W.Blockquote()
  else if xml_name_eq(data, len, name_off, name_len, _t_pre, 3) then $W.Pre()
  else if xml_name_eq(data, len, name_off, name_len, _t_code, 4) then $W.HtmlCode()
  else if xml_name_eq(data, len, name_off, name_len, _t_ul, 2) then $W.Ul()
  else if xml_name_eq(data, len, name_off, name_len, _t_ol, 2) then $W.Ol($W.NoneInt())
  else if xml_name_eq(data, len, name_off, name_len, _t_li, 2) then $W.Li()
  else if xml_name_eq(data, len, name_off, name_len, _t_section, 7) then $W.Section()
  else if xml_name_eq(data, len, name_off, name_len, _t_article, 7) then $W.Article()
  else if xml_name_eq(data, len, name_off, name_len, _t_small, 5) then $W.Small()
  else if xml_name_eq(data, len, name_off, name_len, _t_mark, 4) then $W.Mark()
  else if xml_name_eq(data, len, name_off, name_len, _t_del, 3) then $W.Del()
  else if xml_name_eq(data, len, name_off, name_len, _t_ins, 3) then $W.Ins()
  else if xml_name_eq(data, len, name_off, name_len, _t_sub, 3) then $W.HtmlSub()
  else if xml_name_eq(data, len, name_off, name_len, _t_sup, 3) then $W.Sup()
  else if xml_name_eq(data, len, name_off, name_len, _t_a, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_b, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_i, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_u, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_s, 1) then $W.Span()
  else if xml_name_eq(data, len, name_off, name_len, _t_figure, 6) then $W.Figure()
  else if xml_name_eq(data, len, name_off, name_len, _t_figcap, 10) then $W.Figcaption()
  else if xml_name_eq(data, len, name_off, name_len, _t_table, 5) then $W.Table()
  else if xml_name_eq(data, len, name_off, name_len, _t_tr, 2) then $W.Tr()
  else if xml_name_eq(data, len, name_off, name_len, _t_td, 2) then $W.Td(1, 1)
  else if xml_name_eq(data, len, name_off, name_len, _t_th, 2) then $W.Th(1, 1, $W.NoneInt())
  else if xml_name_eq(data, len, name_off, name_len, _t_thead, 5) then $W.Thead()
  else if xml_name_eq(data, len, name_off, name_len, _t_tbody, 5) then $W.Tbody()
  else $W.Div()
end

(* Walk xml_node_list, rendering each node into parent *)
fun _render_nodes
  {lb:agz}{n:pos}{sz:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int, nodes: !$X.xml_node_list(sz)): void =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val () = _render_node(data, len, pidx, node)
    in _render_nodes(data, len, pidx, rest) end
  | $X.xml_nodes_nil() => ()

and _render_node
  {lb:agz}{n:pos}{sz:pos} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), len: int n,
   pidx: int, node: !$X.xml_node(sz)): void =
  case+ node of
  | $X.xml_text(off, tlen) =>
    if tlen > 0 then
      if tlen < 65536 then let
        val tsz = $AR.checked_text_size(tlen)
        val tbuf = $A.alloc<byte>(tsz)
        val () = copy_from_borrow(data, off, len, tbuf, 0, tsz, $AR.checked_nat(tlen))
        val txt = arr_to_text(tbuf, tsz)
        val () = $A.free<byte>(tbuf)
        val idx = _next_content_idx()
        val w = $W.Element($W.ElementNode(_content_wid(idx),
          $W.Normal($W.Span()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
        val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        val () = _apply_diff($W.SetTextContent(_content_wid(idx), txt, tsz))
      in end
      else ()
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
    if xml_name_eq(data, len, name_off, name_len, _t_head, 4) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_title, 5) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_meta, 4) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_link, 4) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_style, 5) then ()
    else if xml_name_eq(data, len, name_off, name_len, _t_script, 6) then ()
    else let
      (* Transparent tags: html, body — render children with same parent *)
      var _t_html = @[char][4]('h', 't', 'm', 'l')
      var _t_body = @[char][4]('b', 'o', 'd', 'y')
    in
      if xml_name_eq(data, len, name_off, name_len, _t_html, 4) then
        _render_nodes(data, len, pidx, children)
      else if xml_name_eq(data, len, name_off, name_len, _t_body, 4) then
        _render_nodes(data, len, pidx, children)
      else let
        (* Void tags: br, hr *)
        var _t_br = @[char][2]('b', 'r')
        var _t_hr = @[char][2]('h', 'r')
      in
        if xml_name_eq(data, len, name_off, name_len, _t_br, 2) then let
          val idx = _next_content_idx()
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Void($W.Br()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        in end
        else if xml_name_eq(data, len, name_off, name_len, _t_hr, 2) then let
          val idx = _next_content_idx()
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Void($W.Hr()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
        in end
        else let
          (* Normal element: match tag name, create element, recurse *)
          val idx = _next_content_idx()
          val tag = _match_tag_to_normal(data, len, name_off, name_len)
          val w = $W.Element($W.ElementNode(_content_wid(idx),
            $W.Normal(tag), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
          val () = _apply_diff($W.AddChild(_parent_wid(pidx), w))
          val () = _render_nodes(data, len, idx, children)
        in end
      end
    end
  end

fn _load_chapter(chapter_idx: int): $P.promise(int, $P.Chained) = let
  val fh = $ST.stash_get_int(10)
  val fsz = $ST.stash_get_int(11)
  val cd_off = $ST.stash_get_int(12)
  val cd_cnt = $ST.stash_get_int(13)
  val opf_doff = $ST.stash_get_int(14)
  val opf_csz = $ST.stash_get_int(15)
  val opf_comp = $ST.stash_get_int(16)
in
  if fsz <= 0 then $P.ret<int>(~1)
  else if fsz > 1048576 then $P.ret<int>(~1)
  else if opf_csz <= 0 then $P.ret<int>(~1)
  else if opf_csz > 1048576 then $P.ret<int>(~1)
  else let
    (* Read full file *)
    val fsz_s = $AR.checked_arr_size(fsz)
    val fbuf2 = $A.alloc<byte>(fsz_s)
    val () = $R.discard($FI.file_read(fh, 0, fbuf2, fsz_s))

    val opf_csz_s = $AR.checked_arr_size(opf_csz)
    val opf_cbuf = $A.alloc<byte>(opf_csz_s)
    val fbuf2 = copy_arr_region(fbuf2, opf_doff, fsz_s,
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
    $P.and_then<int><int>(dc_p, lam(dc_handle) => let
      val dc_len = $DC.get_len()
    in
      if dc_len <= 0 then let
        val () = $DC.blob_free(dc_handle)
      in $P.ret<int>(~2) end
      else if dc_len > 1048576 then let
        val () = $DC.blob_free(dc_handle)
      in $P.ret<int>(~2) end
      else let
        val dc_sz = $AR.checked_arr_size(dc_len)
        val opf_buf = $A.alloc<byte>(dc_sz)
        val () = $R.discard($DC.blob_read(dc_handle, 0, opf_buf, dc_sz))
        val () = $DC.blob_free(dc_handle)

        val @(opf_f, opf_b) = $A.freeze<byte>(opf_buf)
        val opf_nodes = $X.parse_document(opf_b, dc_sz)

        (* Count spine items and store total chapters *)
        val total_ch = count_spine_items(opf_b, dc_sz, opf_nodes, 0)
        val () = $ST.stash_set_int(24, total_ch)

        (* Find Nth spine itemref → manifest item href *)
        val ch_href = find_chapter_href_n(opf_b, dc_sz, opf_nodes, chapter_idx)
        val ch_off = ch_href.0
        val ch_len = ch_href.1
      in
        if ch_off < 0 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        else if ch_len <= 0 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        else if ch_len > 1048576 then let
          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)
        in $P.ret<int>(~3) end
        else let
          (* Re-read file now so we can access the OPF name
             in the central directory for path prefix resolution *)
          val fsz_s3 = $AR.checked_arr_size(fsz)
          val fbuf3 = $A.alloc<byte>(fsz_s3)
          val () = $R.discard($FI.file_read(fh, 0, fbuf3, fsz_s3))

          (* Find directory prefix from OPF name in central directory.
             The OPF path e.g. "OEBPS/content.opf" tells us the
             directory prefix "OEBPS/" to prepend to chapter hrefs. *)
          val opf_name_off = $ST.stash_get_int(17)
          val opf_name_len = $ST.stash_get_int(18)
          fun _find_last_slash
            {l:agz}{n:pos}{k:int}{e:int}{la:int}{fuel:nat} .<fuel>.
            (buf: !$A.arr(byte, l, n), max: int n,
             pos: int k, endp: int e, last_after: int la,
             fuel: int fuel): int =
            if fuel <= 0 then last_after
            else if pos < 0 then last_after
            else if pos >= max then last_after
            else if pos >= endp then last_after
            else let
              val b = byte2int0($A.get<byte>(buf, pos))
            in
              if b = 47 then
                _find_last_slash(buf, max, pos + 1, endp, pos + 1, fuel - 1)
              else
                _find_last_slash(buf, max, pos + 1, endp, last_after, fuel - 1)
            end
          val opf_off_g1 = g1ofg0_int(opf_name_off)
          val opf_len_g1 = g1ofg0_int(opf_name_len)
          val prefix_end = _find_last_slash(fbuf3, fsz_s3,
            opf_off_g1, opf_off_g1 + opf_len_g1, opf_off_g1,
            $AR.checked_nat(opf_name_len))
          val prefix_len = prefix_end - opf_name_off

          (* Build full path: prefix + href *)
          val full_len = prefix_len + ch_len
          val full_len_s = $AR.checked_arr_size(full_len)
          val ch_buf = $A.alloc<byte>(full_len_s)
          (* Copy prefix from file buffer *)
          fun _copy_arr_region
            {la:agz}{na:pos}{lb:agz}{nb:pos}{i:int}{j:int}{fuel:nat} .<fuel>.
            (src: !$A.arr(byte, la, na), s_off: int i, s_max: int na,
             dst: !$A.arr(byte, lb, nb), d_off: int j, d_max: int nb,
             fuel: int fuel): void =
            if fuel <= 0 then ()
            else if s_off < 0 then ()
            else if d_off < 0 then ()
            else if s_off >= s_max then ()
            else if d_off >= d_max then ()
            else let
              val b = $A.get<byte>(src, s_off)
              val () = $A.set<byte>(dst, d_off, b)
            in _copy_arr_region(src, s_off + 1, s_max, dst, d_off + 1, d_max, fuel - 1) end
          val () = _copy_arr_region(fbuf3, opf_off_g1, fsz_s3,
                    ch_buf, 0, full_len_s,
                    $AR.checked_nat(prefix_len))
          (* Copy chapter href from OPF borrow *)
          val () = copy_from_borrow(opf_b, ch_off, dc_sz,
                    ch_buf, prefix_len, full_len_s,
                    $AR.checked_nat(ch_len))

          val () = $X.free_nodes(opf_nodes)
          val () = $A.drop<byte>(opf_f, opf_b)
          val t = $A.thaw<byte>(opf_f)
          val () = $A.free<byte>(t)

          val @(chf, chb) = $A.freeze<byte>(ch_buf)
          val ch_entry = $Z.find_entry_by_name(
            fbuf3, fsz_s3, cd_off,
            $AR.checked_nat(cd_cnt),
            chb, full_len_s)
          val () = $A.drop<byte>(chf, chb)
          val ch_buf2 = $A.thaw<byte>(chf)
          val () = $A.free<byte>(ch_buf2)
        in
          if ch_entry.name_offset < 0 then let
            val () = $A.free<byte>(fbuf3)
          in $P.ret<int>(~4) end
          else let
            val ch_doff_opt = $Z.get_data_offset(fbuf3, fsz_s3,
                                ch_entry.local_header_offset)
            val ch_doff = $R.option_unwrap_or<int>(ch_doff_opt, ~1)
          in
            if ch_doff < 0 then let
              val () = $A.free<byte>(fbuf3)
            in $P.ret<int>(~5) end
            else if ch_entry.compressed_size <= 0 then let
              val () = $A.free<byte>(fbuf3)
            in $P.ret<int>(~5) end
            else if ch_entry.compressed_size > 1048576 then let
              val () = $A.free<byte>(fbuf3)
            in $P.ret<int>(~5) end
            else let
              val ch_csz = $AR.checked_arr_size(ch_entry.compressed_size)
              val ch_comp = $A.alloc<byte>(ch_csz)
              val () = _copy_arr_region(fbuf3, g1ofg0_int(ch_doff), fsz_s3,
                                        ch_comp, 0, ch_csz, ch_csz)
              val () = $A.free<byte>(fbuf3)

              val @(ccf, ccb) = $A.freeze<byte>(ch_comp)
              val ch_dc_p = $DC.decompress(ccb, ch_csz, ch_entry.compression)
              val () = $A.drop<byte>(ccf, ccb)
              val ch_comp2 = $A.thaw<byte>(ccf)
              val () = $A.free<byte>(ch_comp2)

              val ch_dc_p = $P.vow(ch_dc_p)
            in
              (* Stage 3: parse HTML and render *)
              $P.and_then<int><int>(ch_dc_p, lam(ch_dc_handle) => let
                val ch_dc_len = $DC.get_len()
              in
                if ch_dc_len <= 0 then let
                  val () = $DC.blob_free(ch_dc_handle)
                in $P.ret<int>(~6) end
                else if ch_dc_len > 1048576 then let
                  val () = $DC.blob_free(ch_dc_handle)
                in $P.ret<int>(~6) end
                else let
                  val ch_dc_sz = $AR.checked_arr_size(ch_dc_len)
                  val ch_xhtml = $A.alloc<byte>(ch_dc_sz)
                  val () = $R.discard($DC.blob_read(ch_dc_handle, 0, ch_xhtml, ch_dc_sz))
                  val () = $DC.blob_free(ch_dc_handle)

                  (* Parse XHTML with xml-tree *)
                  val @(xf, xb) = $A.freeze<byte>(ch_xhtml)
                  val nodes = $X.parse_document(xb, ch_dc_sz)

                  (* Clear content area *)
                  var cnt_c = @[char][4]('q', 'c', 'n', 't')
                  val cnt_id = $W.Generated($S.text_of_chars(cnt_c, 4), 4)
                  val () = _apply_diff($W.RemoveAllChildren(cnt_id))
                  val () = $ST.stash_set_int(28, 0)

                  (* Render XHTML tree into content area *)
                  val () = _render_nodes(xb, ch_dc_sz, ~1, nodes)
                  val () = $X.free_nodes(nodes)
                  val () = $A.drop<byte>(xf, xb)
                  val ch_xhtml2 = $A.thaw<byte>(xf)
                  val () = $A.free<byte>(ch_xhtml2)

                  val () = $ST.stash_set_int(23, chapter_idx + 1)
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

fn _go_to_page(page: int): void = let
  val total = $ST.stash_get_int(22)
  val cur_ch = $ST.stash_get_int(23)
  val total_ch = $ST.stash_get_int(24)
in
  if page >= total then
    if cur_ch < total_ch then let
      val ch_p = _load_chapter(cur_ch)
      val () = $P.discard<int>(ch_p)
    in end
    else _scroll_to_page(total - 1)
  else if page < 0 then
    if cur_ch > 1 then let
      val ch_p = _load_chapter(cur_ch - 2)
      val () = $P.discard<int>(ch_p)
    in end
    else _scroll_to_page(0)
  else _scroll_to_page(page)
end

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
  val p2 = $P.and_then<int><int>(font_p, lam(font_len) =>
    if font_len <> 2 then $P.ret<int>(~1)
    else let
      val fdata = $IDB.idb_get_result(2)
      val lo = byte2int0($A.get<byte>(fdata, 0))
      val hi = byte2int0($A.get<byte>(fdata, 1))
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
  val p2 = $P.and_then<int><int>(book_p, lam(book_len) =>
    if book_len <= 0 then $P.ret<int>(~1)
    else if book_len > 1048576 then $P.ret<int>(~1)
    else let
      (* Read EPUB bytes from IDB result *)
      val bsz = $AR.checked_arr_size(book_len)
      val book_data = $IDB.idb_get_result(bsz)
      (* Store into file cache *)
      val @(bf, bb) = $A.freeze<byte>(book_data)
      val fh = $FI.file_store(bb, bsz)
      val () = $A.drop<byte>(bf, bb)
      val btmp = $A.thaw<byte>(bf)
      val () = $A.free<byte>(btmp)
      val () = $ST.stash_set_int(10, fh)
      val () = $ST.stash_set_int(11, book_len)

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
      $P.and_then<int><int>(meta_p, lam(meta_len) =>
        if meta_len <> 36 then $P.ret<int>(~2)
        else let
          (* Read 9 x 4-byte ints = stash slots 10-18 *)
          val meta_data = $IDB.idb_get_result(36)
          fun _read_slot {l:agz}{n:pos}{s:nat}{fuel:nat} .<fuel>.
            (buf: !$A.arr(byte, l, n), max: int n,
             slot: int s, off: int, fuel: int fuel): void =
            if fuel <= 0 then ()
            else if slot >= 32 then ()
            else if off < 0 then ()
            else if off + 3 >= max then ()
            else let
              val b0 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off, max)))
              val b1 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off + 1, max)))
              val b2 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off + 2, max)))
              val b3 = byte2int0($A.get<byte>(buf, $AR.checked_idx(off + 3, max)))
              val v = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
              val () = $ST.stash_set_int(slot, v)
            in _read_slot(buf, max, slot + 1, off + 4, fuel - 1) end
          val () = _read_slot(meta_data, 36, 10, 0, 9)
          val () = $A.free<byte>(meta_data)
          (* Override slot 10 with the new file handle from file_store *)
          val () = $ST.stash_set_int(10, fh)

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
          $P.and_then<int><int>(pos_p, lam(pos_len) =>
            if pos_len <> 4 then let
              (* No saved position — just load chapter 0 *)
              (* Show reader, hide library *)
              var ll_c = @[char][4]('q', 'l', 'l', 'c')
              val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
              var rv_c = @[char][4]('q', 'r', 'v', 'w')
              val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
              val () = _apply_diff($W.SetHidden(ll_id, 1))
              val () = _apply_diff($W.SetHidden(rv_id, 0))
              val ch_p = _load_chapter(0)
              val () = $P.discard<int>(ch_p)
            in $P.ret<int>(0) end
            else let
              val pos_data = $IDB.idb_get_result(4)
              val ch_lo = byte2int0($A.get<byte>(pos_data, 0))
              val ch_hi = byte2int0($A.get<byte>(pos_data, 1))
              val pg_lo = byte2int0($A.get<byte>(pos_data, 2))
              val pg_hi = byte2int0($A.get<byte>(pos_data, 3))
              val () = $A.free<byte>(pos_data)
              val saved_ch = ch_lo + ch_hi * 256
              val saved_pg = pg_lo + pg_hi * 256
              (* Show reader, hide library *)
              var ll_c = @[char][4]('q', 'l', 'l', 'c')
              val ll_id = $W.Generated($S.text_of_chars(ll_c, 4), 4)
              var rv_c = @[char][4]('q', 'r', 'v', 'w')
              val rv_id = $W.Generated($S.text_of_chars(rv_c, 4), 4)
              val () = _apply_diff($W.SetHidden(ll_id, 1))
              val () = _apply_diff($W.SetHidden(rv_id, 0))
              (* Load the saved chapter (1-indexed → 0-indexed) *)
              val ch_idx = (if saved_ch > 0 then saved_ch - 1 else 0): int
              val ch_p = _load_chapter(ch_idx)
              (* After chapter loads, scroll to saved page *)
              val ch_p2 = $P.and_then<int><int>(ch_p, lam(result) =>
                if result = 0 then let
                  val () = _scroll_to_page(saved_pg)
                in $P.ret<int>(0) end
                else $P.ret<int>(result))
              val () = $P.discard<int>(ch_p2)
            in $P.ret<int>(0) end)
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

#pub fun apply_font_size(size: int): void
implement apply_font_size(size) = _apply_font_size(size)

#pub fun measure_pagination(): void
implement measure_pagination() = _measure_pagination()

#pub fun go_to_page(page: int): void
implement go_to_page(page) = _go_to_page(page)

#pub fun load_chapter(chapter_idx: int): $P.promise(int, $P.Chained)
implement load_chapter(chapter_idx) = _load_chapter(chapter_idx)

#pub fun scroll_to_page(page: int): void
implement scroll_to_page(page) = _scroll_to_page(page)

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

end (* #target wasm *)
