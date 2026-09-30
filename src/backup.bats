(* backup -- the library's state in one JSON file: the settings, and
   each book's id, title, author, shelf, dates, reading position and
   annotations (not its file, which the user has). Restoring it puts
   that state back; a book not in the library keeps its record, and its
   annotations, until it is imported again. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use wasm.bats-packages.dev/file-input as FI

staload "ui.sats"
staload "modal.sats"
staload "book.sats"
staload "library.sats"
staload "settings.sats"
staload "annot.sats"
staload "jsonio.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* A backup's most bytes *)
#define BMAX 268435456

(* ============================================================
   The file, in chunks: k chunks of s bytes, the last one first
   ============================================================ *)

datavtype chunks(int, int) =
  | chunks_nil(0, 0) of ()
  | {k,s:nat}{la,l:agz}{n:pos}{m:nat | m <= n}
    chunks_cons(k + 1, s + m) of (piece_owner(n, la), $A.arrx(byte, l, n, la), int m, chunks(k, s))

fun chunks_free {k,s:nat} .<k>. (xs: chunks(k, s)): void =
  case+ xs of
  | ~chunks_nil() => ()
  | ~chunks_cons(ow, a, _, rest) => let val () = piece_free(ow, a) in chunks_free(rest) end

(* The chunks so far; whether each could be made *)
datavtype chunk_cell =
  | {k,s:nat | s <= BMAX} ChunkCell of (chunks(k, s), int s, bool)

val _chunks = ref<chunk_cell>(ChunkCell(chunks_nil(), 0, true))

fn _chunks_take (): chunk_cell = let
  var c: chunk_cell = ChunkCell(chunks_nil(), 0, true)
  val () = ref_exch_elt<chunk_cell>(_chunks, c)
in c end

fn _chunks_put (c: chunk_cell): void = let
  var cur: chunk_cell = c
  val () = ref_exch_elt<chunk_cell>(_chunks, cur)
  val+ ~ChunkCell(xs, _, _) = cur
in chunks_free(xs) end

(* Adds c after the chunks so far *)
fn _push (c: jchunk): void = let
  val+ ~ChunkCell(xs, s, ok) = _chunks_take()
in
  case+ c of
  | ~JNone() => _chunks_put(ChunkCell(xs, s, false))
  | ~JChunk(ow, a, m) =>
    if s + m > BMAX then let
      val () = piece_free(ow, a)
    in _chunks_put(ChunkCell(xs, s, false)) end
    else _chunks_put(ChunkCell(chunks_cons(ow, a, m, xs), s + m, ok))
end

(* out[o, o + m) := a[0, m) *)
fun _copy_at {l,la2:agz}{la,lo:addr}{t,n:nat}{m:nat | m <= n}{o:nat | o + m <= t}{j:nat | j <= m} .<m - j>.
  (out: !$A.arrx(byte, l, t, la), o: int o, a: !$A.arrx(byte, la2, n, lo), m: int m, j: int j): void =
  if j >= m then ()
  else let
    val () = $A.write_byte(out, o + j, $AR.low_byte(byte2int0($A.get<byte>(a, j))))
  in _copy_at(out, o, a, m, j + 1) end

(* The chunks, the last first, at out[0, s) in order *)
fun _join {l:agz}{la:addr}{t:nat}{k,s:nat | s <= t} .<k>.
  (out: !$A.arrx(byte, l, t, la), xs: chunks(k, s), s: int s): void =
  case+ xs of
  | ~chunks_nil() => ()
  | ~chunks_cons(ow, a, m, rest) => let
      val () = _copy_at(out, s - m, a, m, 0)
      val () = piece_free(ow, a)
    in _join(out, rest, s - m) end

(* ============================================================
   Export
   ============================================================ *)

fn _say {nt:pos | nt < 256} (t: string nt): void = let
  val () = modal_inform("Backup")
in modal_text_lit(t) end

(* The file's start: its settings, and the books' opening bracket *)
fn _settings_chunk (): jchunk =
  case+ piece_new(512) of
  | ~NoPiece() => JNone()
  | ~Piece(ow, out) => let
      val p = jw_lit(out, 0, "{\"quire\":1,\"settings\":{\"size\":")
      val p = jw_int(out, p, set_size_get())
      val p = jw_lit(out, p, ",\"lineHeight\":")
      val p = jw_int(out, p, set_lh_get())
      val p = jw_lit(out, p, ",\"margins\":")
      val p = jw_int(out, p, set_margin_get())
      val p = jw_lit(out, p, ",\"font\":")
      val p = jw_int(out, p, set_font_get())
      val p = jw_lit(out, p, ",\"theme\":")
      val p = jw_int(out, p, set_theme_get())
      val p = jw_lit(out, p, ",\"align\":")
      val p = jw_int(out, p, set_align_get())
      val p = jw_lit(out, p, ",\"hyphens\":")
      val p = jw_int(out, p, set_hyph_get())
      val p = jw_lit(out, p, ",\"paragraphSpacing\":")
      val p = jw_int(out, p, set_ps_get())
      val p = jw_lit(out, p, ",\"letterSpacing\":")
      val p = jw_int(out, p, set_ls_get())
      val p = jw_lit(out, p, ",\"wordSpacing\":")
      val p = jw_int(out, p, set_ws_get())
      val p = jw_lit(out, p, ",\"dimImages\":")
      val p = jw_int(out, p, set_dim_get())
      val p = jw_lit(out, p, ",\"tapZones\":")
      val p = jw_int(out, p, set_taps_get())
      val p = jw_lit(out, p, ",\"volumeKeys\":")
      val p = jw_int(out, p, set_vol_get())
      val p = jw_lit(out, p, ",\"footerReadout\":")
      val p = jw_int(out, p, set_rd_get())
      val p = jw_lit(out, p, ",\"sort\":")
      val p = jw_int(out, p, lib_sort_get())
      val p = jw_lit(out, p, "},\"books\":[")
    in JChunk(ow, out, p) end

fn _lit_chunk {sn:pos | sn <= 16} (s: string sn): jchunk =
  case+ piece_new(16) of
  | ~NoPiece() => JNone()
  | ~Piece(ow, out) => JChunk(ow, out, jw_lit(out, 0, s))

(* out[p + 1 + j, p + 15) := k[1 + j, 15) *)
fun _id_cp {l,lk:agz}{la:addr}{n:nat}{p:nat | p + 16 <= n}{j:nat | j <= 14} .<14 - j>.
  (out: !$A.arrx(byte, l, n, la), p: int p, k: !$A.arr(byte, lk, 15), j: int j): void =
  if j >= 14 then ()
  else let
    val () = $A.write_byte(out, p + 1 + j, $AR.low_byte(byte2int0($A.get<byte>(k, j + 1))))
  in _id_cp(out, p, k, j + 1) end

(* The id's 14 hex digits, quoted, at out[p, p + 16) *)
fn _id_json {l:agz}{la:addr}{n:nat}{p:nat | p + 16 <= n}
  (out: !$A.arrx(byte, l, n, la), p: int p, h1: int, h2: int): int(p + 16) = let
  val k = lib_key(105, h1, h2)
  val () = $A.write_byte(out, p, 34)
  val () = _id_cp(out, p, k, 0)
  val () = $A.free<byte>(k)
  val () = $A.write_byte(out, p + 15, 34)
in p + 16 end

(* Book i's members, up to its annotations' value; after another
   book's closing brace when it is not the first *)
fn _book_chunk {i:int} (i: int i, x: bnums, first: bool): jchunk =
  case+ piece_new(4096) of
  | ~NoPiece() => JNone()
  | ~Piece(ow, out) => let
      val @(t, tn) = lib_text(i, 0)
      val @(a, an) = lib_text(i, 1)
      val p = (if first then jw_lit(out, 0, "{\"id\":") else jw_lit(out, 0, "},{\"id\":")): [q:int | 6 <= q; q <= 8] int q
      val p = _id_json(out, p, x.h1, x.h2)
      val p = jw_lit(out, p, ",\"title\":")
      val p = jw_str(out, p, t, tn)
      val p = jw_lit(out, p, ",\"author\":")
      val p = jw_str(out, p, a, an)
      val () = $A.free<byte>(t)
      val () = $A.free<byte>(a)
      val p = jw_lit(out, p, ",\"shelf\":")
      val p = jw_int(out, p, x.shelf)
      val p = jw_lit(out, p, ",\"added\":")
      val p = jw_int(out, p, x.added)
      val p = jw_lit(out, p, ",\"opened\":")
      val p = jw_int(out, p, x.opened)
      val p = jw_lit(out, p, ",\"chapter\":")
      val p = jw_int(out, p, x.ch)
      val p = jw_lit(out, p, ",\"chapters\":")
      val p = jw_int(out, p, x.tch)
      val p = jw_lit(out, p, ",\"page\":")
      val p = jw_int(out, p, x.pg)
      val p = jw_lit(out, p, ",\"pages\":")
      val p = jw_int(out, p, x.pgs)
      val p = jw_lit(out, p, ",\"anchor\":")
      val p = jw_int(out, p, x.anchor)
      val p = jw_lit(out, p, ",\"size\":")
      val p = jw_int(out, p, x.fsz)
      val p = jw_lit(out, p, ",\"done\":")
      val p = jw_int(out, p, x.done)
      val p = jw_lit(out, p, ",\"annotations\":")
    in JChunk(ow, out, p) end

(* Downloads the chunks as one file *)
fn _export_finish (): void = let
  val+ ~ChunkCell(xs, s, ok) = _chunks_take()
in
  if ~ok then let
    val () = chunks_free(xs)
  in _say("The backup could not be made: there is not enough memory.") end
  else if s <= 0 then chunks_free(xs)
  else (case+ piece_new(s) of
    | ~NoPiece() => let
        val () = chunks_free(xs)
      in _say("The backup could not be made: there is not enough memory.") end
    | ~Piece(ow, out) => let
        val () = _join(out, xs, s)
        val @(f, b) = $A.freeze<byte>(out)
        val ma = $A.alloc<byte>(16)
        val () = $A.write_text(ma, 0, $A.text_lit("application/json"), 16)
        val @(mf, mb) = $A.freeze<byte>(ma)
        val na = $A.alloc<byte>(17)
        val () = $A.write_text(na, 0, $A.text_lit("quire-backup.json"), 17)
        val @(nf, nb) = $A.freeze<byte>(na)
        val () = $BL.download_blob(b, s, mb, 16, nb, 17)
        val () = $A.drop<byte>(nf, nb)
        val () = $A.free<byte>($A.thaw<byte>(nf))
        val () = $A.drop<byte>(mf, mb)
        val () = $A.free<byte>($A.thaw<byte>(mf))
        val () = $A.drop<byte>(f, b)
      in piece_free(ow, $A.thaw<byte>(f)) end)
end

(* Books i to c - 1, one after another (each one's annotations are read
   from storage); then the file is downloaded *)
fun _export_seq {i,c:nat | i <= c} .<c - i>. (i: int i, c: int c, first: bool): void =
  if i >= c then let
    val () = (if first then _push(_lit_chunk("]}")) else _push(_lit_chunk("}]}")))
  in _export_finish() end
  else (case+ lib_nums(i) of
    | ~$R.none() => _export_seq(i + 1, c, first)
    | ~$R.some(x) => let
        val () = _push(_book_chunk(i, x, first))
        val @(kf, kb) = $A.freeze<byte>(lib_key(97, x.h1, x.h2))
        val p = $IDB.idb_get(kb, 15)
        val () = $A.drop<byte>(kf, kb)
        val () = $A.free<byte>($A.thaw<byte>(kf))
      in
        $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) => let
          val () = (case+ take_content(h) of
            | ~NoContentBytes() => _push(_lit_chunk("[]"))
            | ~ContentBytes(ow, buf, n) => let
                val j = annot_json(buf, n)
                val () = piece_free(ow, buf)
              in
                case+ j of
                | ~JNone() => _push(_lit_chunk("[]"))
                | ~JChunk(jo, ja, jm) => _push(JChunk(jo, ja, jm))
              end)
          val () = _export_seq(i + 1, c, false)
        in $P.ret<int>(0) end))
      end)

(* Downloads the backup, quire-backup.json *)
#pub fn backup_export (): void

implement backup_export () = let
  val () = _chunks_put(ChunkCell(chunks_nil(), 0, true))
  val () = _push(_settings_chunk())
in _export_seq(0, lib_count(), true) end

(* ============================================================
   A book's record kept for later: "o" and its id
   ============================================================ *)

(* The record's numbers, in order: shelf, added, opened, chapter,
   chapters, page, pages, anchor, done *)
#define ONUMS 9

fun _orphan_wr {la,lv:agz}{j:nat | j <= ONUMS} .<ONUMS - j>.
  (a: !$A.arr(byte, la, 4 + 4 * ONUMS), vs: !$A.arr(Int, lv, 12), j: int j): void =
  if j >= ONUMS then ()
  else let
    val () = $A.write_i32(a, 4 + 4 * j, $A.get<Int>(vs, 3 + j))
  in _orphan_wr(a, vs, j + 1) end

(* vs[3 + j, 12) := the numbers at b[4 + 4 * j, 4 + 4 * ONUMS) *)
fun _orphan_rd {lb,lv:agz}{n:int | n >= 4 + 4 * ONUMS}{j:nat | j <= ONUMS} .<ONUMS - j>.
  (b: !$A.arr(byte, lb, n), vs: !$A.arr(Int, lv, 12), j: int j): void =
  if j >= ONUMS then ()
  else let
    val o = 4 + 4 * j
    val b0 = $AR.low_byte(byte2int0($A.get<byte>(b, o)))
    val b1 = $AR.low_byte(byte2int0($A.get<byte>(b, o + 1)))
    val b2 = $AR.low_byte(byte2int0($A.get<byte>(b, o + 2)))
    val b3 = $AR.low_byte(byte2int0($A.get<byte>(b, o + 3)))
    val hi = (if b3 < 128 then b3 else b3 - 256): Int
    val () = $A.set<Int>(vs, 3 + j, b0 + b1 * 256 + b2 * 65536 + hi * 16777216)
  in _orphan_rd(b, vs, j + 1) end

(* Stores vs[3, 12) (a book's numbers from a backup) under its "o" key *)
fn _orphan_put {lv:agz} (h1: int, h2: int, vs: !$A.arr(Int, lv, 12)): void = let
  val a = $A.alloc<byte>(4 + 4 * ONUMS)
  val () = $A.write_byte(a, 0, 81) (* Q *)
  val () = $A.write_byte(a, 1, 79) (* O *)
  val () = $A.write_byte(a, 2, 49) (* 1 *)
  val () = $A.write_byte(a, 3, 10)
  val () = _orphan_wr(a, vs, 0)
  val @(af, ab) = $A.freeze<byte>(a)
  val @(kf, kb) = $A.freeze<byte>(lib_key(111, h1, h2))
  val () = $P.discard<Int>($IDB.idb_put(kb, 15, ab, 4 + 4 * ONUMS))
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
  val () = $A.drop<byte>(af, ab)
in $A.free<byte>($A.thaw<byte>(af)) end

(* v in [lo, hi], or d *)
fn _in (v: Int, lo: Int, hi: Int, d: Int): Int = if v < lo then d else if v > hi then d else v

(* Library book i's numbers set from vs[3, 12) *)
fn _apply {i:int}{lv:agz} (i: int i, vs: !$A.arr(Int, lv, 12)): void = let
  val sh = _in($A.get<Int>(vs, 3), 0, 2, 0)
  val ad = $A.get<Int>(vs, 4)
  val opn = _in($A.get<Int>(vs, 5), 0, 2147483647, 0)
  val ch = _in($A.get<Int>(vs, 6), 0, 2147483647, 0)
  val tch = _in($A.get<Int>(vs, 7), 0, 2147483647, 0)
  val pg = _in($A.get<Int>(vs, 8), 0, 2147483647, 0)
  val pgs = _in($A.get<Int>(vs, 9), 0, 2147483647, 0)
  val an = _in($A.get<Int>(vs, 10), ~1, 2147483647, ~1)
  val dn = _in($A.get<Int>(vs, 11), 0, 1, 0)
in
  lib_update(i, lam(x) => @{
    key = x.key, h1 = x.h1, h2 = x.h2, shelf = sh,
    added = (if ad > 0 then ad else x.added), opened = opn,
    ch = ch, tch = tch, pg = pg, pgs = pgs, anchor = an,
    fsz = x.fsz, cover = x.cover, done = dn })
end

(* Library book h1, h2 (when it is there) takes the numbers vs[3, 12) *)
fn _claim_apply {lv:agz} (h1: Int, h2: Int, vs: !$A.arr(Int, lv, 12)): void = let
  val i = lib_find(h1, h2)
in
  if i >= 0 then let
    val () = _apply(i, vs)
    val () = lib_save()
  in lib_render() end
  else ()
end

(* A book just imported takes the record a backup kept for it *)
#pub fn backup_claim (h1: Int, h2: Int): void

implement backup_claim (h1, h2) = let
  val @(kf, kb) = $A.freeze<byte>(lib_key(111, h1, h2))
  val p = $IDB.idb_get(kb, 15)
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_blob(h) of
    | ~NoBlobBytes() => $P.ret<int>(0)
    | ~BlobBytes(b, n) =>
      if n < 4 + 4 * ONUMS then let val () = $A.free<byte>(b) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(b, 1)) <> 79 then let val () = $A.free<byte>(b) in $P.ret<int>(0) end
      else let
        val vs = $A.alloc<Int>(12)
        val () = _orphan_rd(b, vs, 0)
        val () = $A.free<byte>(b)
        val () = _claim_apply(h1, h2, vs)
        val () = $A.free<Int>(vs)
        val @(kf, kb) = $A.freeze<byte>(lib_key(111, h1, h2))
        val () = $P.discard<Int>($IDB.idb_delete(kb, 15))
        val () = $A.drop<byte>(kf, kb)
        val () = $A.free<byte>($A.thaw<byte>(kf))
      in $P.ret<int>(0) end))
end

(* ============================================================
   Restore
   ============================================================ *)

(* The value of hex digit c, or -1 *)
fn _hexv (c: Int): Int =
  if c >= 48 then (if c <= 57 then c - 48
    else if c >= 97 then (if c <= 102 then c - 87 else ~1)
    else if c >= 65 then (if c <= 70 then c - 55 else ~1) else ~1)
  else ~1

(* The 7 hex digits kb[o, o + 7), or -1 *)
fun _hex7 {lk:agz}{o:nat | o <= 16}{j:nat | j <= 7; o + 7 <= 16} .<7 - j>.
  (kb: !$A.arr(byte, lk, 16), o: int o, j: int j, acc: Int): Int =
  if j >= 7 then acc
  else let
    val d = _hexv($AR.low_byte(byte2int0($A.get<byte>(kb, o + j))))
  in if d < 0 then ~1 else _hex7(kb, o, j + 1, acc * 16 + d) end

(* The number a book member's key names, its slot in vs: 3 shelf, 4
   added, 5 opened, 6 chapter, 7 chapters, 8 page, 9 pages, 10 anchor,
   11 done; -1 for any other *)
fn _bnum {lk:agz}{k:nat | k <= 16} (kb: !$A.arr(byte, lk, 16), k: int k): [i:int | ~1 <= i; i < 12] int i =
  if jr_key_is(kb, k, "shelf") then 3
  else if jr_key_is(kb, k, "added") then 4
  else if jr_key_is(kb, k, "opened") then 5
  else if jr_key_is(kb, k, "chapter") then 6
  else if jr_key_is(kb, k, "chapters") then 7
  else if jr_key_is(kb, k, "page") then 8
  else if jr_key_is(kb, k, "pages") then 9
  else if jr_key_is(kb, k, "anchor") then 10
  else if jr_key_is(kb, k, "done") then 11
  else ~1

(* A number (or true or false) at v, kept in vs[i] *)
fn _num_at {l,lv:agz}{la:addr}{n:nat}{v:nat | v <= n}{i:nat | i < 12}
  (buf: !$A.arrx(byte, l, n, la), n: int n, v: int v, vs: !$A.arr(Int, lv, 12), i: int i): [q:int | v <= q; q <= n] int q = let
  val @(ok, x, q) = jr_int(buf, n, v)
in
  if ok then let val () = $A.set<Int>(vs, i, x) in q end
  else let
    val @(bok, bv, q2) = jr_bool(buf, n, v)
  in
    if bok then let val () = $A.set<Int>(vs, i, (if bv then 1 else 0)) in q2 end
    else jr_skip(buf, n, v)
  end
end

(* The id member's value at v: vs[0], vs[1] and vs[2] (1 when read) *)
fn _id_at {l,lk,lv:agz}{la:addr}{n:nat}{v:nat | v < n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, v: int v, kb: !$A.arr(byte, lk, 16), vs: !$A.arr(Int, lv, 12)): [q:int | v < q; q <= n] int q = let
  val @(ok, k, q) = jr_str(buf, n, v, kb, 16)
in
  if ~ok then q
  else if k <> 14 then q
  else let
    val h1 = _hex7(kb, 0, 0, 0)
    val h2 = _hex7(kb, 7, 0, 0)
  in
    if h1 < 0 then q
    else if h2 < 0 then q
    else let
      val () = $A.set<Int>(vs, 0, h1)
      val () = $A.set<Int>(vs, 1, h2)
      val () = $A.set<Int>(vs, 2, 1)
    in q end
  end
end

(* A book object's members from p, to its closing brace: its numbers
   into vs, and where its annotations' array is (-1 none) *)
fun _bmem {l,lk,lv:agz}{la:addr}{n:nat}{p:nat | p <= n}{a0:int | ~1 <= a0; a0 <= n} .<n - p>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, kb: !$A.arr(byte, lk, 16), vs: !$A.arr(Int, lv, 12), ap: int a0)
  : [q:int | p <= q; q <= n][a:int | ~1 <= a; a <= n] @(bool, int a, int q) = let
  val q = jr_ws(buf, n, p)
in
  if q >= n then @(false, ap, n)
  else if jr_is(buf, n, q, 125) then @(true, ap, q + 1)
  else if jr_is(buf, n, q, 44) then _bmem(buf, n, q + 1, kb, vs, ap)
  else let
    val @(ok, k, v) = jr_key(buf, n, q, kb, 16)
  in
    if ~ok then @(false, ap, v)
    else if v >= n then @(false, ap, v)
    else if jr_key_is(kb, k, "id") then _bmem(buf, n, _id_at(buf, n, v, kb, vs), kb, vs, ap)
    else if jr_key_is(kb, k, "annotations") then _bmem(buf, n, jr_skip(buf, n, v), kb, vs, v)
    else let
      val i = _bnum(kb, k)
    in
      if i >= 0 then _bmem(buf, n, _num_at(buf, n, v, vs, i), kb, vs, ap)
      else _bmem(buf, n, jr_skip(buf, n, v), kb, vs, ap)
    end
  end
end

(* Puts a book's state back from vs: into the library when the book is
   there, else kept under its "o" key; its annotations from the array
   at ap *)
fn _restore_book {l,lv:agz}{la:addr}{n:nat}{a:int | ~1 <= a; a <= n}
  (buf: !$A.arrx(byte, l, n, la), n: int n, vs: !$A.arr(Int, lv, 12), ap: int a): bool =
  if $A.get<Int>(vs, 2) <> 1 then false
  else let
    val h1 = $A.get<Int>(vs, 0)
    val h2 = $A.get<Int>(vs, 1)
    val i = lib_find(h1, h2)
    val () = (if i >= 0 then _apply(i, vs) else _orphan_put(h1, h2, vs))
    val () = (if ap >= 0 then let val _ = annot_json_store(buf, n, ap, h1, h2) in () end else ())
  in true end

fun _zero {lv:agz}{i:nat | i <= 12} .<12 - i>. (vs: !$A.arr(Int, lv, 12), i: int i): void =
  if i >= 12 then ()
  else let val () = $A.set<Int>(vs, i, (if i = 10 then ~1 else 0)) in _zero(vs, i + 1) end

(* The books of the array's items from p, to its closing bracket, put
   back one by one; how many *)
fun _bitems {l,lk,lv:agz}{la:addr}{n:nat}{p:nat | p <= n} .<n - p>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, kb: !$A.arr(byte, lk, 16), vs: !$A.arr(Int, lv, 12), c: int)
  : [q:int | p <= q; q <= n] @(bool, int, int q) = let
  val q = jr_ws(buf, n, p)
in
  if q >= n then @(false, c, n)
  else if jr_is(buf, n, q, 93) then @(true, c, q + 1)
  else if jr_is(buf, n, q, 44) then _bitems(buf, n, q + 1, kb, vs, c)
  else if jr_is(buf, n, q, 123) then let
    val () = _zero(vs, 0)
    val @(ok, ap, e) = _bmem(buf, n, q + 1, kb, vs, ~1)
  in
    if ~ok then @(false, c, e)
    else if _restore_book(buf, n, vs, ap) then _bitems(buf, n, e, kb, vs, c + 1)
    else _bitems(buf, n, e, kb, vs, c)
  end
  else @(false, c, q)
end

(* The settings object's members from p, to its closing brace, each
   applied when it is in range; the library's sort order *)
fun _smem {l,lk:agz}{la:addr}{n:nat}{p:nat | p <= n} .<n - p>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, kb: !$A.arr(byte, lk, 16), sort: int)
  : [q:int | p <= q; q <= n] @(bool, int, int q) = let
  val q = jr_ws(buf, n, p)
in
  if q >= n then @(false, sort, n)
  else if jr_is(buf, n, q, 125) then @(true, sort, q + 1)
  else if jr_is(buf, n, q, 44) then _smem(buf, n, q + 1, kb, sort)
  else let
    val @(ok, k, v) = jr_key(buf, n, q, kb, 16)
  in
    if ~ok then @(false, sort, v)
    else let
      val @(iok, x, e) = jr_int(buf, n, v)
    in
      if ~iok then _smem(buf, n, jr_skip(buf, n, v), kb, sort)
      else if jr_key_is(kb, k, "size") then let
        val () = (if x >= 12 then (if x <= 32 then set_size_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "lineHeight") then let
        val () = (if x >= 12 then (if x <= 24 then set_lh_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "margins") then let
        val () = (if x >= 0 then (if x <= 4 then set_margin_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "font") then let
        val () = (if x >= 0 then (if x <= 2 then set_font_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "theme") then let
        val () = (if x >= 0 then (if x <= 3 then set_theme_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "align") then let
        val () = (if x >= 0 then (if x <= 1 then set_align_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "hyphens") then let
        val () = (if x >= 0 then (if x <= 1 then set_hyph_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "paragraphSpacing") then let
        val () = (if x >= 0 then (if x <= 20 then set_ps_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "letterSpacing") then let
        val () = (if x >= 0 then (if x <= 12 then set_ls_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "footerReadout") then let
        val () = (if x >= 0 then (if x <= 4 then set_rd_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "volumeKeys") then let
        val () = (if x >= 0 then (if x <= 1 then set_vol_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "tapZones") then let
        val () = (if x >= 0 then (if x <= 2 then set_taps_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "dimImages") then let
        val () = (if x >= 0 then (if x <= 1 then set_dim_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "wordSpacing") then let
        val () = (if x >= 0 then (if x <= 16 then set_ws_set(x) else ()) else ())
      in _smem(buf, n, e, kb, sort) end
      else if jr_key_is(kb, k, "sort") then
        _smem(buf, n, e, kb, (if x >= 0 then (if x <= 3 then x else sort) else sort))
      else _smem(buf, n, e, kb, sort)
    end
  end
end

(* The backup's members from p: whether it is one (its "quire" is 1),
   the books put back, and the sort order *)
fun _top {l,lk,lv:agz}{la:addr}{n:nat}{p:nat | p <= n} .<n - p>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, kb: !$A.arr(byte, lk, 16), vs: !$A.arr(Int, lv, 12),
   quire: bool, books: int, sort: int): @(bool, int, int) = let
  val q = jr_ws(buf, n, p)
in
  if q >= n then @(false, books, sort)
  else if jr_is(buf, n, q, 125) then @(quire, books, sort)
  else if jr_is(buf, n, q, 44) then _top(buf, n, q + 1, kb, vs, quire, books, sort)
  else let
    val @(ok, k, v) = jr_key(buf, n, q, kb, 16)
  in
    if ~ok then @(false, books, sort)
    else if v >= n then @(false, books, sort)
    else if jr_key_is(kb, k, "quire") then let
      val @(iok, x, e) = jr_int(buf, n, v)
    in
      if iok then _top(buf, n, e, kb, vs, x = 1, books, sort)
      else _top(buf, n, jr_skip(buf, n, v), kb, vs, false, books, sort)
    end
    else if ~quire then @(false, books, sort)
    else if jr_key_is(kb, k, "settings") then
      (if jr_is(buf, n, v, 123) then let
         val @(sok, s2, e) = _smem(buf, n, v + 1, kb, sort)
       in if sok then _top(buf, n, e, kb, vs, quire, books, s2) else @(false, books, sort) end
       else _top(buf, n, jr_skip(buf, n, v), kb, vs, quire, books, sort))
    else if jr_key_is(kb, k, "books") then
      (if jr_is(buf, n, v, 91) then let
         val @(bok, c, e) = _bitems(buf, n, v + 1, kb, vs, books)
       in if bok then _top(buf, n, e, kb, vs, quire, c, sort) else @(false, c, sort) end
       else _top(buf, n, jr_skip(buf, n, v), kb, vs, quire, books, sort))
    else _top(buf, n, jr_skip(buf, n, v), kb, vs, quire, books, sort)
  end
end

fn _restored (c: int): void = let
  val () = modal_inform("Backup restored")
  val b = $A.alloc<byte>(64)
  val () = $A.write_text(b, 0, $A.text_lit("Books restored: "), 16)
  val q = jw_int(b, 16, c)
in modal_text(b, q) end

(* Puts back the backup in buf[0, n) *)
fn _restore {l:agz}{la:addr}{n:nat} (buf: !$A.arrx(byte, l, n, la), n: int n): void = let
  val p = jr_ws(buf, n, 0)
in
  if p >= n then _say("This file is not a Quire backup.")
  else if ~jr_is(buf, n, p, 123) then _say("This file is not a Quire backup.")
  else let
    val kb = $A.alloc<byte>(16)
    val vs = $A.alloc<Int>(12)
    val @(ok, c, sort) = _top(buf, n, p + 1, kb, vs, false, 0, lib_sort_get())
    val () = $A.free<byte>(kb)
    val () = $A.free<Int>(vs)
    val () = lib_sort(sort)
    val () = lib_sort_label(sort)
    val () = set_apply(sort)
    val () = set_sliders()
    val () = lib_save()
    val () = lib_render()
  in
    if ok then _restored(c)
    else if c > 0 then _restored(c)
    else _say("This file is not a Quire backup, or it is damaged.")
  end
end

(* The file input backup-file's file count, or the open promise of its first *)
fn _qbfi_count (): int = let
  val ia = $A.alloc<byte>(11)
  val () = $A.write_text(ia, 0, $A.text_lit("backup-file"), 11)
  val @(fz, fb) = $A.freeze<byte>(ia)
  val c = $BF.file_count(fb, 11)
  val () = $A.drop<byte>(fz, fb)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in c end

fn _qbfi_open (): $P.promise_pending(Int) = let
  val ia = $A.alloc<byte>(11)
  val () = $A.write_text(ia, 0, $A.text_lit("backup-file"), 11)
  val @(fz, fb) = $A.freeze<byte>(ia)
  val p = $BF.file_open_at(fb, 11, 0)
  val () = $A.drop<byte>(fz, fb)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in p end

(* Restores the backup picked in the file input backup-file *)
#pub fn backup_import (): void

implement backup_import () =
  if _qbfi_count() <= 0 then ()
  else $P.discard<int>($P.and_then<Int><int>($P.vow(_qbfi_open()), lam(h) => let
    (* the file is taken from the input: its choice is cleared *)
    val () = ui_file_input("menu-import-backup", "backup-file", "Import backup", ".json,application/json", false)
  in
    case+ $FI.claim(h) of
    | ~$R.none() => let
        val () = _say("The backup could not be read.")
      in $P.ret<int>(0) end
    | ~$R.some(f) => let
        val n = $FI.size(f)
      in
        if n <= 0 then let
          val () = $FI.close(f)
          val () = _say("This file is not a Quire backup.")
        in $P.ret<int>(0) end
        else if n > BMAX then let
          val () = $FI.close(f)
          val () = _say("This file is too large to be a Quire backup.")
        in $P.ret<int>(0) end
        else (case+ piece_new(n) of
          | ~NoPiece() => let
              val () = $FI.close(f)
              val () = _say("The backup could not be read: there is not enough memory.")
            in $P.ret<int>(0) end
          | ~Piece(ow, out) => let
              val () = $FI.file_read(f, 0, out, n)
              val () = $FI.close(f)
              val () = _restore(out, n)
              val () = piece_free(ow, out)
            in $P.ret<int>(0) end)
      end
  end))

end (* #target wasm *)
