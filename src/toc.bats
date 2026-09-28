(* toc -- the open book's table of contents: read once from its nav
   document (EPUB 3) or NCX (EPUB 2), shown in the contents panel, and
   giving each chapter its title *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use str as S
#use xml-tree as X
#use wasm.bats-packages.dev/decompress as DC

staload "epub_xml.sats"
staload "book.sats"
staload "paths.sats"
staload "ui.sats"

(* A label's and a fragment's most bytes *)
#define LBL 200
#define FRG 200

(* The entries, in document order: each one's label lb[0, ll), level (0
   the top, at most 3), chapter (-1 when its href names none) and the
   fragment fr[0, fl) its href ends with (the id after '#', when fl > 0;
   fr has fl + 1 bytes) *)
datavtype toc(int) =
  | toc_nil(0) of ()
  | {k:nat}{l1,l2:agz}{ll:pos | ll <= LBL}{fl:nat | fl <= FRG}{v:nat | v <= 3}{c:int | c >= ~1}
    toc_cons(k + 1) of ($A.arr(byte, l1, ll), int ll, int v, int c, $A.arr(byte, l2, fl + 1), int fl, toc(k))

fun toc_free {k:nat} .<k>. (t: toc(k)): void =
  case+ t of
  | ~toc_nil() => ()
  | ~toc_cons(lb, _, _, _, fr, _, rest) => let
      val () = $A.free<byte>(lb)
      val () = $A.free<byte>(fr)
    in toc_free(rest) end

(* dst[i, k) := src[i, k) *)
fun _dup {ls,ld:agz}{ns,nd:pos}{k:nat | k <= ns; k <= nd}{i:nat | i <= k} .<k - i>.
  (src: !$A.arr(byte, ls, ns), dst: !$A.arr(byte, ld, nd), k: int k, i: int i): void =
  if i >= k then ()
  else let
    val () = $A.set<byte>(dst, i, $A.get<byte>(src, i))
  in _dup(src, dst, k, i + 1) end

datavtype toc_cell =
  | {k:nat} TocCell of (toc(k), int k)

val _cell = ref<toc_cell>(TocCell(toc_nil(), 0))

fn _take (): toc_cell = let
  var c: toc_cell = TocCell(toc_nil(), 0)
  val () = ref_exch_elt<toc_cell>(_cell, c)
in c end

fn _put (c: toc_cell): void = let
  var cur: toc_cell = c
  val () = ref_exch_elt<toc_cell>(_cell, cur)
  val+ ~TocCell(t, _) = cur
in toc_free(t) end

(* The document the entries are read from: an entry of the z-byte file,
   its data [d, d + s) with method m and its name [no, no + nl); ncx
   when it is an NCX *)
datavtype toc_src =
  | {z:pos}{d:nat}{s:pos | d + s <= z; s <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
    TocSrc of (int z, int d, int s, int m, int no, int nl, bool)
  | TocNone of ()

val _src = ref<toc_src>(TocNone())

fn _src_take (): toc_src = let
  var c: toc_src = TocNone()
  val () = ref_exch_elt<toc_src>(_src, c)
in c end

fn _src_put (c: toc_src): void = let
  var cur: toc_src = c
  val () = ref_exch_elt<toc_src>(_src, cur)
in
  case+ cur of
  | ~TocSrc(_, _, _, _, _, _, _) => ()
  | ~TocNone() => ()
end

(* ============================================================
   Finding the document, in the OPF
   ============================================================ *)

(* The entry of book s (z bytes) named buf[0, k); frees buf *)
fn _find {z:pos}{l:agz}{m:pos | m <= 1048576}{k:nat | k <= m}
  (s: int, z: int z, buf: $A.arr(byte, l, m), m: int m, k: int k): entry_hit(z) =
  if k <= 0 then let val () = $A.free<byte>(buf) in EntryMiss() end
  else let
    val exact = $A.alloc<byte>(k)
    val buf = $S.copy_arr_region(buf, 0, m, exact, k, k)
    val () = $A.free<byte>(buf)
    val @(f, b) = $A.freeze<byte>(exact)
    val hit = book_find_entry(s, z, b, k)
    val () = $A.drop<byte>(f, b)
    val () = $A.free<byte>($A.thaw<byte>(f))
  in hit end

(* The entry of book s (z bytes) that href opf_b[ho, ho + hl) names,
   after the OPF's directory (pl bytes of the name at opf_no) *)
fn _opf_entry {z:pos}{ono:nat}{pl:nat | ono + pl <= z; pl < 65536}{lb:agz}{n:pos}{ho,hl:nat | ho + hl <= n}
  (s: int, z: int z, opf_no: int ono, pl: int pl, opf_b: !$A.borrow(byte, lb, n), n: int n,
   ho: int ho, hl: int hl): entry_hit(z) =
  if hl <= 0 then EntryMiss()
  else if pl + hl > 1048576 then EntryMiss()
  else let
    val m = pl + hl
    val buf = $A.alloc<byte>(m)
    val _ = book_read(s, z, opf_no, buf, pl)
    val () = $S.copy_from_borrow(opf_b, ho, n, buf, pl, m, hl)
    val k = path_norm(buf, m)
  in _find(s, z, buf, m, k) end

fn _src_of {z:pos} (z: int z, hit: entry_hit(z), ncx: bool): toc_src =
  case+ hit of
  | ~EntryHit(d, cs, m, no, nl) => TocSrc(z, d, cs, m, no, nl, ncx)
  | ~EntryMiss() => TocNone()

(* Finds, in the OPF opf_b[0, n) of book s, the document the table of
   contents is read from: the manifest item with property nav, else the
   NCX the spine names *)
#pub fn toc_locate {z:pos}{ono:nat}{pl:nat | ono + pl <= z; pl < 65536}{lb:agz}{n:pos}{sz:nat}
  (s: int, z: int z, opf_no: int ono, pl: int pl,
   opf_b: !$A.borrow(byte, lb, n), n: int n, nodes: !$X.xml_node_list(n, sz)): void

implement toc_locate (s, z, opf_no, pl, opf_b, n, nodes) = let
  var _c_nav = @[char][3]('n', 'a', 'v')
  val nav = (case+ find_item_with_prop(opf_b, nodes, _c_nav, 3) of
    | ~xspan_at(ho, hl) => _src_of(z, _opf_entry(s, z, opf_no, pl, opf_b, n, ho, hl), false)
    | ~xspan_none() => TocNone()): toc_src
  val src = (case+ nav of
    | TocSrc(_, _, _, _, _, _, _) => nav
    | ~TocNone() => (case+ find_ncx_href(opf_b, n, nodes) of
      | ~xspan_at(ho, hl) => _src_of(z, _opf_entry(s, z, opf_no, pl, opf_b, n, ho, hl), true)
      | ~xspan_none() => TocNone())): toc_src
in _src_put(src) end

(* ============================================================
   Reading the entries
   ============================================================ *)

(* An entry as read: its label lb[0, ll), level, and href
   data[ho, ho + hl) (none when hl is 0) *)
datavtype raw(n:int, int) =
  | raw_nil(n, 0) of ()
  | {k:nat}{l:agz}{ll:pos | ll <= LBL}{v:nat | v <= 3}{ho,hl:nat | ho + hl <= n}
    raw_cons(n, k + 1) of ($A.arr(byte, l, ll), int ll, int v, int ho, int hl, raw(n, k))

(* Whether data[o + i, o + i + np) is pat, within data[o, o + k) *)
fn _at {lb:agz}{n:pos}{o,k:nat | o + k <= n}{i:nat}{np:pos}
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, i: int i, pat: &(@[char][np]), np: int np): bool =
  if i + np > k then false else xml_name_eq(data, o + i, np, pat, np)

(* A byte at buf[p] (while there is room), unless it is a space that
   would start the label or follow another *)
fn _emit {l:agz}{p:nat | p <= LBL}
  (buf: !$A.arr(byte, l, LBL), p: int p, c: int): [q:nat | q <= LBL] int q =
  if p >= LBL then p
  else if c = 32 then
    (if p = 0 then p
     else if byte2int0($A.get<byte>(buf, p - 1)) = 32 then p
     else let val () = $A.set<byte>(buf, p, $A.int2byte(32)) in p + 1 end)
  else let
    val () = $A.set<byte>(buf, p, $A.int2byte($AR.low_byte(c)))
  in p + 1 end

(* i + w, or k when that is past k *)
fn _skip {i,k:nat | i < k}{w:pos} (i: int i, k: int k, w: int w): [j:int | i < j; j <= k] int j =
  if i + w <= k then i + w else k

(* The text data[o + i, o + k) added to the label buf[0, p): white space
   as one space, and the five XML entities (and &nbsp;) decoded *)
fun _copy_text {lb,l:agz}{n:pos}{o,k:nat | o + k <= n}{i:nat | i <= k}{p:nat | p <= LBL} .<k - i>.
  (data: !$A.borrow(byte, lb, n), o: int o, k: int k, i: int i,
   buf: !$A.arr(byte, l, LBL), p: int p): [q:nat | q <= LBL] int q =
  if i >= k then p
  else let
    val c = byte2int0($A.read<byte>(data, o + i))
  in
    if c = 9 then _copy_text(data, o, k, _skip(i, k, 1), buf, _emit(buf, p, 32))
    else if c = 10 then _copy_text(data, o, k, _skip(i, k, 1), buf, _emit(buf, p, 32))
    else if c = 13 then _copy_text(data, o, k, _skip(i, k, 1), buf, _emit(buf, p, 32))
    else if c = 38 then let
      var amp = @[char][4]('a', 'm', 'p', ';')
      var lt = @[char][3]('l', 't', ';')
      var gt = @[char][3]('g', 't', ';')
      var quot = @[char][5]('q', 'u', 'o', 't', ';')
      var apos = @[char][5]('a', 'p', 'o', 's', ';')
      var nbsp = @[char][5]('n', 'b', 's', 'p', ';')
    in
      if _at(data, o, k, i + 1, amp, 4) then _copy_text(data, o, k, _skip(i, k, 5), buf, _emit(buf, p, 38))
      else if _at(data, o, k, i + 1, lt, 3) then _copy_text(data, o, k, _skip(i, k, 4), buf, _emit(buf, p, 60))
      else if _at(data, o, k, i + 1, gt, 3) then _copy_text(data, o, k, _skip(i, k, 4), buf, _emit(buf, p, 62))
      else if _at(data, o, k, i + 1, quot, 5) then _copy_text(data, o, k, _skip(i, k, 6), buf, _emit(buf, p, 34))
      else if _at(data, o, k, i + 1, apos, 5) then _copy_text(data, o, k, _skip(i, k, 6), buf, _emit(buf, p, 39))
      else if _at(data, o, k, i + 1, nbsp, 5) then _copy_text(data, o, k, _skip(i, k, 6), buf, _emit(buf, p, 32))
      else _copy_text(data, o, k, _skip(i, k, 1), buf, _emit(buf, p, c))
    end
    else _copy_text(data, o, k, _skip(i, k, 1), buf, _emit(buf, p, c))
  end

(* The text of nodes, added to the label buf[0, p) *)
fun _gather_nodes {lb,l:agz}{n:pos}{sz:nat}{p:nat | p <= LBL} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz),
   buf: !$A.arr(byte, l, LBL), p: int p): [q:nat | q <= LBL] int q =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => _gather_nodes(data, rest, buf, _gather_node(data, node, buf, p))
  | $X.xml_nodes_nil() => p

and _gather_node {lb,l:agz}{n:pos}{sz:pos}{p:nat | p <= LBL} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz),
   buf: !$A.arr(byte, l, LBL), p: int p): [q:nat | q <= LBL] int q =
  case+ node of
  | $X.xml_text(o, k) => _copy_text(data, o, k, 0, buf, p)
  | $X.xml_element(_, _, _, children) => _gather_nodes(data, children, buf, p)

(* The text of the first child element of nodes named pat, added to the
   label buf[0, p) *)
fun _child_text {lb,l:agz}{n:pos}{sz:nat}{np:pos}{p:nat | p <= LBL} .<sz>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz), pat: &(@[char][np]), np: int np,
   buf: !$A.arr(byte, l, LBL), p: int p): [q:nat | q <= LBL] int q =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(no, nl, _, children) =>
       if xml_name_eq(data, no, nl, pat, np) then _gather_nodes(data, children, buf, p)
       else _child_text(data, rest, pat, np, buf, p)
     | $X.xml_text(_, _) => _child_text(data, rest, pat, np, buf, p))
  | $X.xml_nodes_nil() => p

(* The attribute apat of the first child element of nodes named pat *)
fun _child_attr {lb:agz}{n:pos}{sz:nat}{np,na:pos} .<sz>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz), pat: &(@[char][np]), np: int np,
   apat: &(@[char][na]), na: int na): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(no, nl, attrs, _) =>
       if xml_name_eq(data, no, nl, pat, np) then find_attr(data, attrs, apat, na)
       else _child_attr(data, rest, pat, np, apat, na)
     | $X.xml_text(_, _) => _child_attr(data, rest, pat, np, apat, na))
  | $X.xml_nodes_nil() => xspan_none()

(* The label of a nav <li>: the text of its <a>, else of its <span> *)
fn _li_label {lb,l:agz}{n:pos}{sz:nat}
  (data: !$A.borrow(byte, lb, n), children: !$X.xml_node_list(n, sz),
   buf: !$A.arr(byte, l, LBL)): [q:nat | q <= LBL] int q = let
  var _c_a = @[char][1]('a')
  var _c_span = @[char][4]('s', 'p', 'a', 'n')
  val p = _child_text(data, children, _c_a, 1, buf, 0)
in
  if p > 0 then p else _child_text(data, children, _c_span, 4, buf, 0)
end

(* An entry with the label buf[0, p) (a placeholder when it is empty),
   level v and href h, onto acc; frees buf *)
fn _entry {l:agz}{n:pos}{p:nat | p <= LBL}{r:nat}
  (buf: $A.arr(byte, l, LBL), p: int p, v: Int, h: xspan(n), acc: raw(n, r)): raw(n, r + 1) = let
  val v = (if v < 0 then 0 else if v > 3 then 3 else v): [w:nat | w <= 3] int w
  (* trailing space *)
  val p = (if p > 0 then (if byte2int0($A.get<byte>(buf, p - 1)) = 32 then p - 1 else p) else p): [q:nat | q <= LBL] int q
  val @(ho, hl) = (case+ h of
    | ~xspan_at(o, k) => @(o, k)
    | ~xspan_none() => @(0, 0)): [o,k:nat | o + k <= n] @(int o, int k)
in
  if p <= 0 then let
    val () = $A.free<byte>(buf)
    val lb = $A.alloc<byte>(8)
    val () = $A.write_text(lb, 0, $A.text_lit("Untitled"), 8)
  in raw_cons(lb, 8, v, ho, hl, acc) end
  else let
    val lb = $A.alloc<byte>(p)
    val buf = $S.copy_arr_region(buf, 0, LBL, lb, p, p)
    val () = $A.free<byte>(buf)
  in raw_cons(lb, p, v, ho, hl, acc) end
end

(* The entries of nodes, onto acc (newest first): the <li> of a nav
   whose epub:type has toc (mode 0), or each navPoint (mode 1); each one
   level deeper than the entry it is in *)
fun _walk_nodes {lb:agz}{n:pos}{sz:nat}{r:nat} .<sz, 1>.
  (data: !$A.borrow(byte, lb, n), nodes: !$X.xml_node_list(n, sz),
   ncx: bool, in_toc: bool, v: Int, acc: raw(n, r)): [r2:nat] raw(n, r2) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    _walk_nodes(data, rest, ncx, in_toc, v, _walk_node(data, node, ncx, in_toc, v, acc))
  | $X.xml_nodes_nil() => acc

and _walk_node {lb:agz}{n:pos}{sz:pos}{r:nat} .<sz, 0>.
  (data: !$A.borrow(byte, lb, n), node: !$X.xml_node(n, sz),
   ncx: bool, in_toc: bool, v: Int, acc: raw(n, r)): [r2:nat] raw(n, r2) =
  case+ node of
  | $X.xml_text(_, _) => acc
  | $X.xml_element(no, nl, attrs, children) => let
      var _c_nav = @[char][3]('n', 'a', 'v')
      var _c_li = @[char][2]('l', 'i')
      var _c_a = @[char][1]('a')
      var _c_span = @[char][4]('s', 'p', 'a', 'n')
      var _c_href = @[char][4]('h', 'r', 'e', 'f')
      var _c_et = @[char][9]('e', 'p', 'u', 'b', ':', 't', 'y', 'p', 'e')
      var _c_toc = @[char][3]('t', 'o', 'c')
      var _c_np = @[char][8]('n', 'a', 'v', 'P', 'o', 'i', 'n', 't')
      var _c_nl = @[char][8]('n', 'a', 'v', 'L', 'a', 'b', 'e', 'l')
      var _c_content = @[char][7]('c', 'o', 'n', 't', 'e', 'n', 't')
      var _c_src = @[char][3]('s', 'r', 'c')
      var _c_pl = @[char][8]('p', 'a', 'g', 'e', 'L', 'i', 's', 't')
    in
      if ncx then
        (if xml_name_eq(data, no, nl, _c_np, 8) then let
           val buf = $A.alloc<byte>(LBL)
           val p = _child_text(data, children, _c_nl, 8, buf, 0)
           val h = _child_attr(data, children, _c_content, 7, _c_src, 3)
           val acc = _entry(buf, p, v, h, acc)
         in _walk_nodes(data, children, ncx, in_toc, v + 1, acc) end
         else if xml_name_eq(data, no, nl, _c_pl, 8) then acc
         else _walk_nodes(data, children, ncx, in_toc, v, acc))
      else if xml_name_eq(data, no, nl, _c_nav, 3) then
        (case+ find_attr(data, attrs, _c_et, 9) of
         | ~xspan_at(to, tk) =>
           if span_has(data, to, tk, _c_toc, 3) then _walk_nodes(data, children, ncx, true, v, acc)
           else acc
         | ~xspan_none() => acc)
      else if (if in_toc then xml_name_eq(data, no, nl, _c_li, 2) else false) then let
        val buf = $A.alloc<byte>(LBL)
        val p = _li_label(data, children, buf)
        val h = _child_attr(data, children, _c_a, 1, _c_href, 4)
        val acc = _entry(buf, p, v, h, acc)
      in _walk_nodes(data, children, ncx, in_toc, v + 1, acc) end
      else _walk_nodes(data, children, ncx, in_toc, v, acc)
    end

(* The chapter the href data[ho, ho + h) names, after the document's
   directory (the first dl bytes of its name, at no in the file); the
   chapter of the document itself when h is 0 *)
fn _chapter_of {z:pos}{no,dl:nat | no + dl <= z; dl < 65536}{lb:agz}{n:pos}{ho,h:nat | ho + h <= n}
  (s: int, z: int z, no: int no, dl: int dl, self: int,
   data: !$A.borrow(byte, lb, n), n: int n, ho: int ho, h: int h): [c:int | c >= ~1] int c =
  if h <= 0 then book_chapter_of(s, self)
  (* an href of 64 KiB or more names no zip entry: the book's data,
     checked here *)
  else if h >= 65536 then ~1
  else let
    val m = dl + h
    val buf = $A.alloc<byte>(m)
    val _ = book_read(s, z, no, buf, dl)
    val () = $S.copy_from_borrow(data, ho, n, buf, dl, m, h)
    val k = path_norm(buf, m)
  in
    case+ _find(s, z, buf, m, k) of
    | ~EntryHit(_, _, _, eno, _) => book_chapter_of(s, eno)
    | ~EntryMiss() => ~1
  end

(* The length of the href data[ho, ho + hl) before its '#' *)
fn _href_end {lb:agz}{n:pos}{ho,hl:nat | ho + hl <= n}
  (data: !$A.borrow(byte, lb, n), ho: int ho, hl: int hl): [r:nat | r <= hl] int r =
  if hl > 0 then src_end(data, ho, hl) else 0

(* The length of the fragment after the '#' at h of an href of hl
   bytes: 0 when there is none, or it is over FRG bytes *)
fn _frag_len {hl,h:nat | h <= hl} (hl: int hl, h: int h): [f:nat | f <= FRG; f == 0 || f == hl - h - 1] int f =
  if hl - h - 1 <= 0 then 0
  else if hl - h - 1 > FRG then 0
  else hl - h - 1

(* fr[0, f) := data[ho + h + 1, ho + h + 1 + f) *)
fn _frag_copy {lb,l:agz}{n:pos}{ho,h,f:nat | f == 0 || ho + h + 1 + f <= n}
  (data: !$A.borrow(byte, lb, n), n: int n, ho: int ho, h: int h, fr: !$A.arr(byte, l, f + 1), f: int f): void =
  if f > 0 then $S.copy_from_borrow(data, ho + h + 1, n, fr, 0, f + 1, f) else ()

(* The entries xs, resolved onto acc (so in document order again) *)
fun _resolve {z:pos}{no,dl:nat | no + dl <= z; dl < 65536}{lb:agz}{n:pos}{r,k:nat} .<r>.
  (s: int, z: int z, no: int no, dl: int dl, self: int,
   data: !$A.borrow(byte, lb, n), n: int n, xs: raw(n, r), acc: toc(k), c: int k): [j:nat] @(toc(j), int j) =
  case+ xs of
  | ~raw_nil() => @(acc, c)
  | ~raw_cons(lb, ll, v, ho, hl, rest) => let
      val h = _href_end(data, ho, hl)
      val ch = _chapter_of(s, z, no, dl, self, data, n, ho, h)
      val fl = _frag_len(hl, h)
      val fr = $A.alloc<byte>(fl + 1)
      val () = _frag_copy(data, n, ho, h, fr, fl)
    in _resolve(s, z, no, dl, self, data, n, rest, toc_cons(lb, ll, v, ch, fr, fl, acc), c + 1) end

(* The length of the directory part of the name [no, no + nl) *)
fn _dir_len {z:pos}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
  (s: int, z: int z, no: int no, nl: int nl): [p:nat | p <= nl] int p = let
  val buf = $A.alloc<byte>(nl)
  val _ = book_read(s, z, no, buf, nl)
  val p = path_dir_end(buf, nl)
  val () = $A.free<byte>(buf)
in p end

(* Reads the entries of book s from the document toc_locate found; the
   promise resolves with their count (0 when there is none) *)
#pub fn toc_build (s: int): $P.promise(int, $P.Chained)

implement toc_build (s) = let
  val () = _put(TocCell(toc_nil(), 0))
in
  case+ _src_take() of
  | ~TocNone() => $P.ret<int>(0)
  | ~TocSrc(z, d, cs, m, no, nl, ncx) =>
    (case+ piece_new(cs) of
     | ~NoPiece() => $P.ret<int>(0)
     | ~Piece(car, cbuf) => let
         val _ = book_read(s, z, d, cbuf, cs)
         val @(cf, cb) = $A.freeze<byte>(cbuf)
         val dp = $DC.decompress(cb, cs, m)
         val () = $A.drop<byte>(cf, cb)
         val () = piece_free(car, $A.thaw<byte>(cf))
         val dp = $P.vow(dp)
       in
         $P.and_then<Int><int>(dp, lam(h) =>
           case+ take_content(h) of
           | ~NoContentBytes() => $P.ret<int>(0)
           | ~ContentBytes(par, buf, n) => let
               val @(f, b) = $A.freeze<byte>(buf)
               val nodes = $X.parse_document(b, n)
               val xs = _walk_nodes(b, nodes, ncx, false, 0, raw_nil())
               val () = $X.free_nodes(nodes)
               val dl = _dir_len(s, z, no, nl)
               val @(t, k) = _resolve(s, z, no, dl, no, b, n, xs, toc_nil(), 0)
               val () = $A.drop<byte>(f, b)
               val () = piece_free(par, $A.thaw<byte>(f))
               val () = _put(TocCell(t, k))
             in $P.ret<int>(k) end)
       end)
end

(* ============================================================
   Showing it
   ============================================================ *)

(* The index of the entry of chapter ch the reader is in: the first one
   of the chapter, else the last one before it; -1 when none is *)
fun _current {k:nat} .<k>. (t: !toc(k), ch: int, i: int, best: int): int =
  case+ t of
  | toc_nil() => best
  | @toc_cons(_, _, _, c, _, _, rest) =>
    if c = ch then let prval () = fold@(t) in i end
    else if c < ch then let
      val r = _current(rest, ch, i + 1, (if c >= 0 then i else best))
      prval () = fold@(t)
    in r end
    else let prval () = fold@(t) in best end

fn _level_class {v:nat | v <= 3} (v: int v): [n:pos | n < 256] string n =
  if v = 0 then "pi" else if v = 1 then "pi pi1" else if v = 2 then "pi pi2" else "pi pi3"

(* A row of the list: button qe<i> with the label lb[0, ll) *)
fn _row {l:agz}{m:pos}{ll:pos | ll <= LBL; ll <= m}{i:nat}{v:nat | v <= 3}
  (i: int i, v: int v, lb: !$A.arr(byte, l, m), ll: int ll, cur: bool): void = let
  val @(ri, rl) = nid_make("qe", i)
  val () = ui_add_n("qtcl", ri, rl, "button")
  val @(ri, rl) = nid_make("qe", i)
  val () = ui_attr_n(ri, rl, "class", _level_class(v))
  val @(ri, rl) = nid_make("qe", i)
  val () = ui_attr_n(ri, rl, "type", "button")
  val @(ri, rl) = nid_make("qe", i)
  val () = (if cur then ui_attr_n(ri, rl, "aria-current", "true") else ui_attr_n(ri, rl, "aria-current", "false"))
  val tb = $A.alloc<byte>(ll)
  val () = _dup(lb, tb, ll, 0)
  val @(ri, rl) = nid_make("qe", i)
in ui_text_n_buf(ri, rl, tb, ll) end

fun _rows {k:nat}{i:nat} .<k>. (t: !toc(k), i: int i, cur: int): void =
  case+ t of
  | toc_nil() => ()
  | @toc_cons(lb, ll, v, _, _, _, rest) => let
      val () = _row(i, v, lb, ll, i = cur)
      val () = _rows(rest, i + 1, cur)
      prval () = fold@(t)
    in end

(* "Chapter " and n *)
fn _chapter_label {n:nat} (n: int n): [l:agz][k:pos | k <= 19] @($A.arr(byte, l, 19), int k) = let
  val b = $A.alloc<byte>(19)
  val () = $A.write_text(b, 0, $A.text_lit("Chapter "), 8)
  val k = $S.int_to_str(b, 8, 19, n)
in @(b, k) end

(* One row per chapter, for a book with no table of contents *)
fun _chapter_rows {i,tc:nat} .<max(tc - i, 0)>. (i: int i, tc: int tc, cur: int): void =
  if i >= tc then ()
  else let
    val @(b, k) = _chapter_label(i + 1)
    val () = _row(i, 0, b, k, i = cur)
    val () = $A.free<byte>(b)
  in _chapter_rows(i + 1, tc, cur) end

(* Fills the contents list: the book's entries, the reader being in
   chapter ch (from 0) of its tc; one row per chapter when the book has
   no entries *)
#pub fn toc_render {tc:nat} (ch: int, tc: int tc): void

implement toc_render (ch, tc) = let
  val () = ui_clear("qtcl")
  val c = _take()
  val+ @TocCell(t, k) = c
  val cur = _current(t, ch, 0, ~1)
  val () = (if k > 0 then _rows(t, 0, cur) else _chapter_rows(0, tc, ch))
  prval () = fold@(c)
in _put(c) end

(* Where entry i leads *)
#pub datavtype toc_dest =
  | {l:agz}{f:nat | f <= 200} TocDest of (Int, $A.arr(byte, l, f + 1), int f)
  | TocNoDest of ()

fun _dest_at {k:nat} .<k>. (t: !toc(k), i: int): toc_dest =
  case+ t of
  | toc_nil() => TocNoDest()
  | @toc_cons(_, _, _, c, fr, fl, rest) =>
    if i > 0 then let
      val r = _dest_at(rest, i - 1)
      prval () = fold@(t)
    in r end
    else if c < 0 then let prval () = fold@(t) in TocNoDest() end
    else let
      val b = $A.alloc<byte>(fl + 1)
      val () = _dup(fr, b, fl + 1, 0)
      val r = TocDest(c, b, fl)
      prval () = fold@(t)
    in r end

(* The chapter and fragment row i of the list leads to *)
#pub fn toc_dest_of (i: Int): toc_dest

implement toc_dest_of (i) = let
  val c = _take()
  val+ @TocCell(t, k) = c
  val r = (if k > 0 then _dest_at(t, i)
           else if i >= 0 then let val b = $A.alloc<byte>(1) in TocDest(i, b, 0) end
           else TocNoDest()): toc_dest
  prval () = fold@(c)
  val () = _put(c)
in r end

(* The label of entry i *)
fun _title_at {k:nat} .<k>. (t: !toc(k), i: int): bool =
  case+ t of
  | toc_nil() => false
  | @toc_cons(lb, ll, _, _, _, _, rest) =>
    if i > 0 then let
      val r = _title_at(rest, i - 1)
      prval () = fold@(t)
    in r end
    else let
      val tb = $A.alloc<byte>(ll)
      val () = _dup(lb, tb, ll, 0)
      val () = ui_text_buf("qcht", tb, ll)
      prval () = fold@(t)
    in true end

(* Shows chapter ch's title (from 0) in the reader's top bar: its entry's
   label, else "Chapter" and its number *)
#pub fn toc_title {c:nat} (ch: int c): void

implement toc_title (ch) = let
  val c = _take()
  val+ @TocCell(t, _) = c
  val cur = _current(t, ch, 0, ~1)
  val shown = _title_at(t, cur)
  prval () = fold@(c)
  val () = _put(c)
in
  if shown then ()
  else let
    val @(b, k) = _chapter_label(ch + 1)
  in ui_text_buf("qcht", b, k) end
end

end (* #target wasm *)
