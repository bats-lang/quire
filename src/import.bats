(* import -- EPUB files into the library, and stored books reopened *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use sha256 as SHA
#use str as S
#use xml-tree as X
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/file-input as FI

staload "ui.sats"
staload "modal.sats"
staload "book.sats"
staload "paths.sats"
staload "epub_xml.sats"
staload "library.sats"
staload "backup.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* ============================================================
   What the open book is
   ============================================================ *)

(* The key of the library book in the book cell (0 when it holds none
   of them): an import leaves its book there, and opening a book from
   the library puts it there *)
val _open_key = ref<int>(0)

#pub fn open_key_get (): int
implement open_key_get () = !_open_key

#pub fn open_key_set (k: int): void
implement open_key_set (k) = !_open_key := k

(* ============================================================
   Progress and errors
   ============================================================ *)

(* The name of the file being imported (for its error banner) *)
datavtype fname =
  | {l:agz}{n:pos | n <= 200} FName of ($A.arr(byte, l, n), int n)
  | NoFName of ()

val _name = ref<fname>(NoFName())

fn _name_put (x: fname): void = let
  var cur: fname = x
  val () = ref_exch_elt<fname>(_name, cur)
in
  case+ cur of
  | ~FName(a, _) => $A.free<byte>(a)
  | ~NoFName() => ()
end

fn _name_take (): fname = let
  var x: fname = NoFName()
  val () = ref_exch_elt<fname>(_name, x)
in x end

fn _min200 {k:pos} (k: int k): [m:pos | m <= 200; m <= k] int m =
  if k > 200 then 200 else k

(* Keeps f's name (its first 200 bytes) for the banner *)
fn _name_of {n:nat} (f: !$FI.infile(n)): void =
  case+ $BF.file_name(f) of
  | ~$R.none() => _name_put(NoFName())
  | ~$R.some(b) => let
      val k = $DC.blob_len(b)
    in
      if k <= 0 then let val () = $DC.blob_free(b) in _name_put(NoFName()) end
      else let
        val m = _min200(k)
        val a = $A.alloc<byte>(m)
        val () = $DC.blob_read(b, 0, a, m)
        val () = $DC.blob_free(b)
      in _name_put(FName(a, m)) end
    end

(* s's bytes at buf[p, p + sn) *)
fun _put {l:agz}{n:pos}{sn:nat}{p:nat | p + sn <= n}{i:nat | i <= sn} .<sn - i>.
  (buf: !$A.arr(byte, l, n), p: int p, s: string sn, sl: int sn, i: int i): int(p + sn) =
  if i >= sl then p + sl
  else let
    val () = $A.set<byte>(buf, p + i, $A.int2byte($AR.byte_of_char(string_get_at(s, i))))
  in _put(buf, p, s, sl, i + 1) end

fn _puts {l:agz}{n:pos}{sn:nat}{p:nat | p + sn <= n}
  (buf: !$A.arr(byte, l, n), p: int p, s: string sn): int(p + sn) =
  _put(buf, p, s, g1u2i(string1_length(s)), 0)

(* src[0, c) to dst[o, o + c) *)
fun _copy_in {ls,ld:agz}{ns,c:nat | c <= ns}{nd:nat}{o:nat | o + c <= nd}{j:nat | j <= c} .<c - j>.
  (src: !$A.arr(byte, ls, ns), c: int c, dst: !$A.arr(byte, ld, nd), o: int o, j: int j): void =
  if j >= c then ()
  else let
    val () = $A.set<byte>(dst, o + j, $A.get<byte>(src, j))
  in _copy_in(src, c, dst, o, j + 1) end

(* The kept name at buf[0, k), or "The file"; k *)
fn _name_into {l:agz} (buf: !$A.arr(byte, l, 512)): [k:nat | k <= 200] int k =
  case+ _name_take() of
  | ~FName(a, n) => let
      val () = _copy_in(a, n, buf, 0, 0)
      val () = $A.free<byte>(a)
    in n end
  | ~NoFName() => _puts(buf, 0, "The file")

(* Shows the error banner for the file being imported *)
fn _error (): void = let
  val buf = $A.alloc<byte>(512)
  val off = _name_into(buf)
  val off = _puts(buf, off, " could not be imported. Quire supports .epub files without DRM.")
  val () = ui_text_buf("qert", buf, off)
  val () = ui_show("qerr", true)
in ui_show("qimp", false) end

(* The import card: stage text and progress in percent *)
fn _stage {nt:pos | nt < 256} (t: string nt, pct: [p:nat | p <= 100] int p): void = let
  val () = ui_show("qimp", true)
  val () = ui_text("qims", t)
  val sb = $A.alloc<byte>(24)
  val off = _puts(sb, 0, "width:")
  val off = $S.int_to_str(sb, off, 24, pct)
  val off = _puts(sb, off, "%")
in ui_attr_buf("qimf", AStyle, sb, off) end

fn _stage_name (): void =
  case+ _name_take() of
  | ~FName(a, n) => let
      val b = $A.alloc<byte>(n)
      val () = _copy_in(a, n, b, 0, 0)
      val () = ui_text_buf("qimn", b, n)
    in _name_put(FName(a, n)) end
  | ~NoFName() => let
      val () = ui_text("qimn", "EPUB")
    in _name_put(NoFName()) end

(* ============================================================
   The file's identity: its SHA-256
   ============================================================ *)

fun _hash_loop {lb:agz}{n:nat}{o:nat | o <= n} .<n - o>.
  (f: !$FI.infile(n), n: int n, o: int o, c: !$SHA.ctx, buf: !$A.arr(byte, lb, 1048576)): void =
  if o >= n then ()
  else let
    val k = (if n - o < 1048576 then n - o else 1048576): [k:pos | k <= 1048576; o + k <= n] int k
    val () = $FI.file_read(f, o, buf, k)
    val () = $SHA.update(c, buf, k)
  in _hash_loop(f, n, o + k, c, buf) end

fn _file_id {n:nat} (f: !$FI.infile(n), n: int n): @(Int, Int) = let
  val c = $SHA.init()
  val buf = $A.alloc<byte>(1048576)
  val () = _hash_loop(f, n, 0, c, buf)
  val () = $A.free<byte>(buf)
  val out = $A.alloc<byte>(64)
  val () = $SHA.finish(c, out)
  val id = lib_id_of_hex(out)
  val () = $A.free<byte>(out)
in id end

(* ============================================================
   Opening the archive: container.xml, then the OPF
   ============================================================ *)

(* What to do with the OPF once it is read *)
#define MODE_OPEN 0     (* reopen a stored book: nothing *)
#define MODE_NEW 1      (* add a new book to the library *)
#define MODE_REPLACE 2  (* replace the stored file of library book i *)

(* The cover, the entry named dir(opf) + href, stored under 'c' for book
   (h1, h2); its type code, 0 when there is none *)
fn _store_cover {z:pos}{lb:agz}{n:pos}{ho,hl:nat | ho + hl <= n}{ono:nat}{onl:pos | ono + onl <= z; onl < 65536}
  (s: int, z: int z, ono: int ono, onl: int onl,
   data: !$A.borrow(byte, lb, n), n: int n, ho: int ho, hl: int hl, h1: Int, h2: Int): [c:nat | c <= 5] int c = let
  val h = src_end(data, ho, hl)
in
  if h <= 0 then 0
  else if h >= 65536 then 0
  else let
    val nb = $A.alloc<byte>(onl)
    val _ = book_read(s, z, ono, nb, onl)
    val dl = path_dir_end(nb, onl)
    val () = $A.free<byte>(nb)
    val m = dl + h
    val buf = $A.alloc<byte>(m)
    val _ = book_read(s, z, ono, buf, dl)
    val () = $S.copy_from_borrow(data, ho, n, buf, dl, m, h)
    val k = path_norm(buf, m)
  in
    if k <= 0 then let val () = $A.free<byte>(buf) in 0 end
    else let
      val exact = $A.alloc<byte>(k)
      val buf = $S.copy_arr_region(buf, 0, m, exact, k, k)
      val () = $A.free<byte>(buf)
      val @(ef, eb) = $A.freeze<byte>(exact)
      val code = mime_code_of(eb, k)
      val got = book_zip_read(s, z, eb, k)
      val () = $A.drop<byte>(ef, eb)
      val () = $A.free<byte>($A.thaw<byte>(ef))
    in
      case+ got of
      | ~ZipMissing() => 0
      | ~ZipGot(ar, cbuf, cs, cm, _, _, _) =>
        if cm = 0 then let
          val @(cf, cb) = $A.freeze<byte>(cbuf)
          val key = lib_key(99, h1, h2)
          val @(kf, kb) = $A.freeze<byte>(key)
          val () = $P.discard<Int>($IDB.idb_put(kb, 15, cb, cs))
          val () = $A.drop<byte>(kf, kb)
          val () = $A.free<byte>($A.thaw<byte>(kf))
          val () = $A.drop<byte>(cf, cb)
          val () = piece_free(ar, $A.thaw<byte>(cf))
        in code end
        else let
          val @(cf, cb) = $A.freeze<byte>(cbuf)
          val dp = $DC.decompress(cb, cs, cm)
          val () = $A.drop<byte>(cf, cb)
          val () = piece_free(ar, $A.thaw<byte>(cf))
          val () = $P.discard<int>($P.and_then<Int><int>($P.vow(dp), lam(dh) =>
            case+ take_content(dh) of
            | ~NoContentBytes() => $P.ret<int>(0)
            | ~ContentBytes(ar2, b2, n2) => let
                val @(f2, bb2) = $A.freeze<byte>(b2)
                val key = lib_key(99, h1, h2)
                val @(kf, kb) = $A.freeze<byte>(key)
                val () = $P.discard<Int>($IDB.idb_put(kb, 15, bb2, n2))
                val () = $A.drop<byte>(kf, kb)
                val () = $A.free<byte>($A.thaw<byte>(kf))
                val () = $A.drop<byte>(f2, bb2)
                val () = piece_free(ar2, $A.thaw<byte>(f2))
              in $P.ret<int>(0) end))
        in code end
    end
  end
end

fn _cover_of {z:pos}{lb:agz}{n:pos}{sz:nat}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
  (mode: int, s: int, z: int z, no: int no, nl: int nl, opf_b: !$A.borrow(byte, lb, n), n: int n,
   nodes: !$X.xml_node_list(n, sz), h1: Int, h2: Int): [c:nat | c <= 5] int c =
  if mode = MODE_OPEN then 0
  else case+ find_cover_href(opf_b, n, nodes) of
  | ~xspan_at(ho, hl) => _store_cover(s, z, no, nl, opf_b, n, ho, hl, h1, h2)
  | ~xspan_none() => 0

(* After the OPF of book s (z bytes) is read: in MODE_NEW adds the book
   to the library, in MODE_REPLACE updates library book idx; stores the
   file under 'b' in both. The book's key, or below 0. *)
fn _opf_done {z:pos}{lb:agz}{n:pos}{d:nat}{sz:pos | d + sz <= z; sz <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
  (s: int, z: int z, opf_b: !$A.borrow(byte, lb, n), n: int n,
   d: int d, sz: int sz, m: int m, no: int no, nl: int nl,
   mode: int, idx: Int, h1: Int, h2: Int): Int = let
  val nodes = $X.parse_document(opf_b, n)
  val @(title, author) = walk_opf_metadata(opf_b, nodes)
  val cover = _cover_of(mode, s, z, no, nl, opf_b, n, nodes, h1, h2)
  val () = $X.free_nodes(nodes)
  val ok = book_finish(s, z, d, sz, m, no, nl)
in
  if ~ok then let
    val () = xspan_free(title)
    val () = xspan_free(author)
  in ~20 end
  else if mode = MODE_OPEN then let
    val () = xspan_free(title)
    val () = xspan_free(author)
  in 0 end
  else let
    (* The file, stored from the JS side under 'b' *)
    val key = lib_key(98, h1, h2)
    val @(kf, kb) = $A.freeze<byte>(key)
    val () = book_idb_put(kb, 15)
    val () = $A.drop<byte>(kf, kb)
    val () = $A.free<byte>($A.thaw<byte>(kf))
    val @(to, tl) = (case+ title of ~xspan_at(o, k) => @(o, k) | ~xspan_none() => @(0, 0)): [o,k:nat | o + k <= n] @(int o, int k)
    val @(ao, al) = (case+ author of ~xspan_at(o, k) => @(o, k) | ~xspan_none() => @(0, 0)): [o,k:nat | o + k <= n] @(int o, int k)
  in
    if mode = MODE_NEW then let
      val key = lib_add(h1, h2, opf_b, n, to, tl, ao, al, z, cover, $TM.epoch_minutes())
      (* the record a backup kept for it, if any *)
      val () = (if key > 0 then backup_claim(h1, h2) else ())
    in key end
    else let
      val () = lib_update(idx, lam(x) => @{
        key = x.key, h1 = x.h1, h2 = x.h2, shelf = 0, added = x.added, opened = x.opened,
        ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
        fsz = z, cover = (if cover > 0 then (cover: Int) else x.cover), done = x.done })
    in
      case+ lib_nums(idx) of
      | ~$R.some(x) => x.key
      | ~$R.none() => ~21
    end
  end
end

(* Reads book s's container.xml and OPF (book s is the z-byte file just
   put in the book cell), then _opf_done; the promise resolves with the
   book's key, or below 0 when the file is not an EPUB it can read *)
fn _open_archive {z:pos} (s: int, z: int z, mode: int, idx: Int, h1: Int, h2: Int)
  : $P.promise(Int, $P.Chained) = let
  var cc = @[char][22]('M', 'E', 'T', 'A', '-', 'I', 'N', 'F', '/', 'c', 'o', 'n', 't', 'a', 'i', 'n', 'e', 'r', '.', 'x', 'm', 'l')
  val ca = $S.from_char_array(cc, 22)
  val @(cf, cb) = $A.freeze<byte>(ca)
  val cont = book_zip_read(s, z, cb, 22)
  val () = $A.drop<byte>(cf, cb)
  val () = $A.free<byte>($A.thaw<byte>(cf))
in
  case+ cont of
  | ~ZipMissing() => let val () = book_abandon(s) in $P.ret<Int>(~3) end
  | ~ZipGot(car, comp, csz, method, _, _, _) => let
      val @(qf, qb) = $A.freeze<byte>(comp)
      val dp = $DC.decompress(qb, csz, method)
      val () = $A.drop<byte>(qf, qb)
      val () = piece_free(car, $A.thaw<byte>(qf))
    in
      $P.and_then<Int><Int>($P.vow(dp), lam(dh) =>
        case+ take_content(dh) of
        | ~NoContentBytes() => let val () = book_abandon(s) in $P.ret<Int>(~5) end
        | ~ContentBytes(dar, dbuf, dsz) => let
            val @(df, db) = $A.freeze<byte>(dbuf)
            val nodes = $X.parse_document(db, dsz)
            val opath = walk_rootfile_nodes(db, nodes)
            val () = $X.free_nodes(nodes)
          in
            case+ opath of
            | ~xspan_none() => let
                val () = $A.drop<byte>(df, db)
                val () = piece_free(dar, $A.thaw<byte>(df))
                val () = book_abandon(s)
              in $P.ret<Int>(~6) end
            | ~xspan_at(oo, ol) =>
              (* The OPF's path names a zip entry, so it is shorter than
                 65536 bytes (a zip name's limit): checked here *)
              if ol <= 0 then let
                val () = $A.drop<byte>(df, db)
                val () = piece_free(dar, $A.thaw<byte>(df))
                val () = book_abandon(s)
              in $P.ret<Int>(~6) end
              else if ol >= 65536 then let
                val () = $A.drop<byte>(df, db)
                val () = piece_free(dar, $A.thaw<byte>(df))
                val () = book_abandon(s)
              in $P.ret<Int>(~6) end
              else let
                val pb = $A.alloc<byte>(ol)
                val () = $S.copy_from_borrow(db, oo, dsz, pb, 0, ol, ol)
                val () = $A.drop<byte>(df, db)
                val () = piece_free(dar, $A.thaw<byte>(df))
                val @(pf, pbb) = $A.freeze<byte>(pb)
                val oe = book_zip_read(s, z, pbb, ol)
                val () = $A.drop<byte>(pf, pbb)
                val () = $A.free<byte>($A.thaw<byte>(pf))
                val () = (if mode <> MODE_OPEN then _stage("Reading metadata", 60) else ())
              in
                case+ oe of
                | ~ZipMissing() => let val () = book_abandon(s) in $P.ret<Int>(~7) end
                | ~ZipGot(oar, ocomp, ocs, om, od, ono, onl) => let
                    val @(ofz, ob) = $A.freeze<byte>(ocomp)
                    val dp2 = $DC.decompress(ob, ocs, om)
                    val () = $A.drop<byte>(ofz, ob)
                    val () = piece_free(oar, $A.thaw<byte>(ofz))
                  in
                    $P.and_then<Int><Int>($P.vow(dp2), lam(dh2) =>
                      case+ take_content(dh2) of
                      | ~NoContentBytes() => let val () = book_abandon(s) in $P.ret<Int>(~9) end
                      | ~ContentBytes(par, obuf, osz) => let
                          val @(xf, xb) = $A.freeze<byte>(obuf)
                          val r = _opf_done(s, z, xb, osz, od, ocs, om, ono, onl, mode, idx, h1, h2)
                          val () = $A.drop<byte>(xf, xb)
                          val () = piece_free(par, $A.thaw<byte>(xf))
                        in $P.ret<Int>(r) end)
                  end
              end
          end)
    end
end

(* ============================================================
   Import
   ============================================================ *)

(* A file waiting for the answer to "already in the library": the file,
   its size, id and the library book it matches, with the resolver the
   answer resolves while it is asked (Asked), and without it once it
   is answered (Answered). The resolver is linear: it is resolved once,
   by the answer, and there is no id that could name a resolver no
   longer there. *)
datavtype dup =
  | {n:pos} Asked of ($FI.infile(n), int n, Int, Int, Int, $P.resolver(Int))
  | {n:pos} Answered of ($FI.infile(n), int n, Int, Int, Int)
  | NoDup of ()

val _dup = ref<dup>(NoDup())

fn _dup_take (): dup = let
  var x: dup = NoDup()
  val () = ref_exch_elt<dup>(_dup, x)
in x end

(* Puts x in; a file still held there is closed (imports go one after
   another, so none is) *)
fn _dup_put (x: dup): void = let
  var cur: dup = x
  val () = ref_exch_elt<dup>(_dup, cur)
in
  case+ cur of
  | ~Asked(f, _, _, _, _, r) => let
      val () = $FI.close(f)
    in $P.resolve<Int>(r, 1) end
  | ~Answered(f, _, _, _, _) => $FI.close(f)
  | ~NoDup() => ()
end

(* The library changed: kept and shown *)
fn _library_changed (): void = let
  val () = lib_sort(lib_sort_get())
  val () = lib_save()
in lib_render() end

(* Imports the z-byte file f with id (h1, h2) as a new book (idx < 0) or
   over library book idx *)
fn _import_go {z:pos} (f: $FI.infile(z), z: int z, h1: Int, h2: Int, idx: Int): $P.promise(Int, $P.Chained) = let
  val () = _stage("Opening archive", 30)
  val s = book_begin(f, z)
  val mode = (if idx < 0 then MODE_NEW else MODE_REPLACE): int
in
  $P.and_then<Int><Int>(_open_archive(s, z, mode, idx, h1, h2), lam(r) =>
    if r < 0 then let
      val () = _error()
    in $P.ret<Int>(r) end
    else let
      val () = _stage("Adding to library", 90)
      val () = open_key_set(r)
      val () = _library_changed()
      val () = ui_show("qimp", false)
      val () = _name_put(NoFName())
    in $P.ret<Int>(r) end)
end

(* Imports the file an open promise resolved with (handle h) *)
fn _import_handle (h: Int): $P.promise(Int, $P.Chained) =
  case+ $FI.claim(h) of
  | ~$R.none() => let
      val () = _name_put(NoFName())
      val () = _error()
    in $P.ret<Int>(~1) end
  | ~$R.some(f) => let
      val n = $FI.size(f)
      val () = _name_of(f)
      val () = _stage_name()
      val () = _stage("Reading file", 10)
      val () = ui_show("qerr", false)
    in
      if n <= 0 then let
        val () = $FI.close(f)
        val () = _error()
      in $P.ret<Int>(~1) end
      else let
        val @(h1, h2) = _file_id(f, n)
        val i = lib_find(h1, h2)
      in
        if i < 0 then _import_go(f, n, h1, h2, ~1)
        else (case+ lib_nums(i) of
          | ~$R.none() => _import_go(f, n, h1, h2, ~1)
          | ~$R.some(x) =>
            (* An archived book is restored by importing it again *)
            if x.shelf = 2 then _import_go(f, n, h1, h2, i)
            else let
              val @(p, r) = $P.create<Int>()
              val () = _dup_put(Asked(f, n, h1, h2, i, r))
              val @(tb, tn) = lib_text(i, 0)
              val buf = $A.alloc<byte>(320)
              val () = _copy_in(tb, tn, buf, 0, 0)
              val () = $A.free<byte>(tb)
              val off = _puts(buf, tn, " is already in your library.")
              val () = modal_open(QDuplicate(), "Already in library")
              val () = modal_text(buf, off)
            in
              $P.and_then<Int><Int>($P.vow(p), lam(ans) =>
                case+ _dup_take() of
                | ~NoDup() => let
                    val () = ui_show("qimp", false)
                  in $P.ret<Int>(~1) end
                | ~Asked(f2, _, _, _, _, r2) => let
                    val () = $FI.close(f2)
                    val () = $P.resolve<Int>(r2, 1)
                    val () = ui_show("qimp", false)
                  in $P.ret<Int>(~1) end
                | ~Answered(f2, n2, g1, g2, j) =>
                  if ans = 2 then _import_go(f2, n2, g1, g2, j)
                  else let
                    val () = $FI.close(f2)
                    val () = ui_show("qimp", false)
                  in $P.ret<Int>(0) end)
            end)
      end
    end

(* The answer to "already in the library": replace (true) or skip *)
#pub fn import_dup_answer (replace: bool): void

implement import_dup_answer (replace) = let
  (* skipped: the file's import card goes at once *)
  val () = (if replace then () else ui_show("qimp", false))
in
  case+ _dup_take() of
  | ~Asked(f, n, h1, h2, i, r) => let
      val () = _dup_put(Answered(f, n, h1, h2, i))
    in $P.resolve<Int>(r, (if replace then 2 else 1)) end
  | x => _dup_put(x)
end

(* Imports files i to c - 1 of source src (0 the file input qfin, 1 the
   last drop), one after another *)
fun _import_seq {i,c:nat | i <= c} .<c - i>. (src: int, i: int i, c: int c): void =
  if i >= c then
    (* the input's files are all read: its choice is cleared *)
    (if src = 0 then ui_file_input("qibn", "qfin", "Import EPUB", ".epub,application/epub+zip", true) else ())
  else let
    val p = (if src = 0 then let
        val ia = $A.alloc<byte>(4)
        val () = $A.write_text(ia, 0, $A.text_lit("qfin"), 4)
        val @(fz, fb) = $A.freeze<byte>(ia)
        val p = $BF.file_open_at(fb, 4, i)
        val () = $A.drop<byte>(fz, fb)
        val () = $A.free<byte>($A.thaw<byte>(fz))
      in p end
      else $BF.dropped_open_at(i)): $P.promise_pending(Int)
  in
    $P.discard<Int>($P.and_then<Int><Int>($P.vow(p), lam(h) =>
      $P.and_then<Int><Int>(_import_handle(h), lam(_) => let
        val () = _import_seq(src, i + 1, c)
      in $P.ret<Int>(0) end)))
  end

(* Imports the files picked in the file input qfin *)
#pub fn import_picked (): void

implement import_picked () = let
  val ia = $A.alloc<byte>(4)
  val () = $A.write_text(ia, 0, $A.text_lit("qfin"), 4)
  val @(fz, fb) = $A.freeze<byte>(ia)
  val c = $BF.file_count(fb, 4)
  val () = $A.drop<byte>(fz, fb)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in _import_seq(0, 0, c) end

(* Imports the files of the last drop *)
#pub fn import_dropped (): void

implement import_dropped () = _import_seq(1, 0, $BF.dropped_count())

(* Imports a file handed to the app from outside it (its handle) *)
#pub fn import_external (h: Int): void

implement import_external (h) = $P.discard<Int>(_import_handle(h))

(* ============================================================
   Reopening a stored book
   ============================================================ *)

(* Puts library book (h1, h2), whose key is key, in the book cell from
   its stored file; the promise resolves with 0, or below 0 when its
   file is not stored (an archived book) or cannot be read *)
#pub fn open_stored (key: int, h1: Int, h2: Int): $P.promise(Int, $P.Chained)

implement open_stored (key, h1, h2) = let
  val k = lib_key(98, h1, h2)
  val @(kf, kb) = $A.freeze<byte>(k)
  val p = $FI.idb_get(kb, 15)
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
in
  $P.and_then<Int><Int>($P.vow(p), lam(h) =>
    case+ $FI.claim(h) of
    | ~$R.none() => $P.ret<Int>(~1)
    | ~$R.some(f) => let
        val n = $FI.size(f)
      in
        if n <= 0 then let val () = $FI.close(f) in $P.ret<Int>(~1) end
        else let
          val s = book_begin(f, n)
        in
          $P.and_then<Int><Int>(_open_archive(s, n, MODE_OPEN, ~1, h1, h2), lam(r) =>
            if r < 0 then $P.ret<Int>(r)
            else let val () = open_key_set(key) in $P.ret<Int>(0) end)
        end
      end)
end

end (* #target wasm *)
