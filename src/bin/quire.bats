#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use wasm.bats-packages.dev/decompress as DC

staload "book.sats"
staload "pages.sats"
staload "ui.sats"
staload "app.sats"
staload "modal.sats"
staload "backup.sats"
staload "library.sats"
staload "settings.sats"
staload "import.sats"
staload "reader.sats"
staload "toc.sats"
staload "annot.sats"
staload CB = "wasm.bats-packages.dev/bridge/src/clipboard.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"

(* ============================================================
   State
   ============================================================ *)

(* 0 the library is shown, 1 the reader *)
val _view = ref<int>(0)
(* The library book whose menu or info view is open *)
val _menu_idx = ref<Int>(~1)
(* Whether the reader's bars are shown, and the latest hide timer's *)
val _chrome = ref<bool>(true)
val _chrome_gen = ref<int>(0)
(* A wheel turn waiting out its pause; the latest resize's number *)
val _wheel_busy = ref<bool>(false)
val _resize_gen = ref<int>(0)
(* Whether the scrubber's thumb is being dragged *)
val _scrubbing = ref<bool>(false)
(* The annotation whose note the dialog edits *)
val _note_idx = ref<int>(~1)
(* Where a touch started *)
val _touch_x = ref<int>(0)
val _touch_y = ref<int>(0)
(* The latest keystroke in the search field's number *)
val _search_tick = ref<int>(0)

(* ============================================================
   Event payloads (bytes the host passed: checked here, once)
   ============================================================ *)

(* A pointer-like event's payload: x, y (int32 LE), the target's id
   length (u16 LE) and id *)
fn _i32at {l:agz}{n:nat}{p:nat | p + 4 <= n} (b: !$A.arr(byte, l, n), p: int p): Int = let
  val b0 = $AR.low_byte(byte2int0($A.get<byte>(b, p)))
  val b1 = $AR.low_byte(byte2int0($A.get<byte>(b, p + 1)))
  val b2 = $AR.low_byte(byte2int0($A.get<byte>(b, p + 2)))
  val b3 = $AR.low_byte(byte2int0($A.get<byte>(b, p + 3)))
  val hi = (if b3 < 128 then b3 else b3 - 256): [h:int | ~128 <= h; h < 128] int h
in b0 + b1 * 256 + b2 * 65536 + hi * 16777216 end

(* The number n of the target id pre<n> of a pointer event, or -1 *)
fn _target_num {sn:pos | sn <= 4} (h: $EV.event_payload, pre: string sn): [v:int | v >= ~1] int v =
  case+ take_blob(h) of
  | ~NoBlobBytes() => ~1
  | ~BlobBytes(b, n) => let
      val @(f, bb) = $A.freeze<byte>(b)
      val v = (if n >= 11 then nid_parse(bb, n, 10, pre) else ~1): [v:int | v >= ~1] int v
      val () = $A.drop<byte>(f, bb)
    in let val () = $A.free<byte>($A.thaw<byte>(f)) in v end end

(* Whether the target id of a pointer event is id *)
fun _bytes_are {l:agz}{n:nat}{o:nat}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (b: !$A.arr(byte, l, n), n: int n, o: int o, s: string sn, sl: int sn, i: int i): bool =
  if i >= sl then o + sl = n
  else if o + i >= n then false
  else if byte2int0($A.get<byte>(b, o + i)) <> char2int0(string_get_at(s, i)) then false
  else _bytes_are(b, n, o, s, sl, i + 1)

(* Whether b[o, o + sl) is s *)
fun _bytes_at {l:agz}{n:nat}{o:nat}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (b: !$A.arr(byte, l, n), n: int n, o: int o, s: string sn, sl: int sn, i: int i): bool =
  if i >= sl then true
  else if o + i >= n then false
  else if byte2int0($A.get<byte>(b, o + i)) <> char2int0(string_get_at(s, i)) then false
  else _bytes_at(b, n, o, s, sl, i + 1)

(* The target id of a pointer event, matched against the ids the
   caller asks about: the payload's bytes *)
datavtype target =
  | {l:agz}{n:pos} Target of ($A.arr(byte, l, n), int n, Int)
  | NoTarget of ()

fn _target (h: $EV.event_payload): target =
  case+ take_blob(h) of
  | ~NoBlobBytes() => NoTarget()
  | ~BlobBytes(b, n) =>
    if n < 10 then let val () = $A.free<byte>(b) in NoTarget() end
    else Target(b, n, _i32at(b, 0))

fn _is {sn:pos} (t: !target, id: string sn): bool =
  case+ t of
  | Target(b, n, _) => _bytes_are(b, n, 10, id, g1u2i(string1_length(id)), 0)
  | NoTarget() => false

(* The number n of the target's id pre<n>, or -1 *)
fn _row_of {sn:pos | sn <= 4} (t: !target, pre: string sn): [v:int | v >= ~1] int v =
  case+ t of
  | @Target(b, n, _) => let
      val @(f, bb) = $A.freeze<byte>(b)
      val v = (if n >= 11 then nid_parse(bb, n, 10, pre) else ~1): [v:int | v >= ~1] int v
      val () = $A.drop<byte>(f, bb)
      val () = b := $A.thaw<byte>(f)
      prval () = fold@(t)
    in v end
  | NoTarget() => ~1

(* The x of the target's event, or -1 *)
fn _target_x (t: !target): Int =
  case+ t of
  | Target(_, _, x) => x
  | NoTarget() => ~1

fn _target_free (t: target): void =
  case+ t of
  | ~Target(b, _, _) => $A.free<byte>(b)
  | ~NoTarget() => ()

(* The x of a pointer event, or -1 *)
fn _event_x (h: $EV.event_payload): Int =
  case+ take_blob(h) of
  | ~NoBlobBytes() => ~1
  | ~BlobBytes(b, n) =>
    if n < 8 then let val () = $A.free<byte>(b) in ~1 end
    else let val x = _i32at(b, 0) val () = $A.free<byte>(b) in x end

(* An input event's value, as a number (0 when it is not one) *)
fun _num_of {l:agz}{n:nat}{i:nat | i <= n} .<n - i>.
  (b: !$A.arr(byte, l, n), n: int n, i: int i, acc: [a:nat | a < 100000] int a): [v:nat | v < 100000] int v =
  if i >= n then acc
  else let
    val c = $AR.low_byte(byte2int0($A.get<byte>(b, i)))
  in
    if c < 48 then acc else if c > 57 then acc
    else if acc > 9999 then acc
    else _num_of(b, n, i + 1, acc * 10 + (c - 48))
  end

fn _input_num (h: $EV.event_payload): [v:nat | v < 100000] int v =
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(b, n) => let
      val v = (if n >= 2 then _num_of(b, n, 2, 0) else 0): [v:nat | v < 100000] int v
      val () = $A.free<byte>(b)
    in v end

(* An input event's value, from its bytes (after the 2 length bytes) *)
fn _input_text (h: $EV.event_payload): [l:agz][k:nat] @($A.arr(byte, l, k + 1), int k) =
  case+ take_blob(h) of
  | ~NoBlobBytes() => let val a = $A.alloc<byte>(1) in @(a, 0) end
  | ~BlobBytes(b, n) =>
    if n <= 2 then let
      val () = $A.free<byte>(b)
      val a = $A.alloc<byte>(1)
    in @(a, 0) end
    else let
      val k = n - 2
      val a = $A.alloc<byte>(k + 1)
      fun cp {lb,la:agz}{n:nat}{k:nat | k + 2 <= n}{i:nat | i <= k} .<k - i>.
        (b: !$A.arr(byte, lb, n), a: !$A.arr(byte, la, k + 1), k: int k, i: int i): void =
        if i >= k then ()
        else let val () = $A.set<byte>(a, i, $A.get<byte>(b, i + 2)) in cp(b, a, k, i + 1) end
      val () = cp(b, a, k, 0)
      val () = $A.free<byte>(b)
    in @(a, k) end

(* ============================================================
   Views
   ============================================================ *)

fn _show_library (): void = let
  val () = !_view := 0
  val () = ui_show("qrvw", false)
  val () = ui_show("qspn", false)
  val () = ui_show("qtoc", false)
  val () = ui_show("qsrp", false)
  val () = ui_show("qanp", false)
  val () = ui_show("qllc", true)
  val () = reader_search_stop()
  val () = reader_stack_clear()
  val () = window_close()
in lib_render() end

(* The reader's bars: shown, and hidden again after 5 seconds *)
fn _chrome_set_off (): void = let
  val () = !_chrome := false
in ui_attr("qrvw", "class", "rv chrome-off") end

fn _chrome_set (on: bool): void = let
  val () = !_chrome := on
  val () = (if on then ui_attr("qrvw", "class", "rv") else ui_attr("qrvw", "class", "rv chrome-off"))
  val () = !_chrome_gen := !_chrome_gen + 1
  val gen = !_chrome_gen
in
  if on then $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(5000)), lam(_) => let
      val () = (if !_chrome_gen = gen then _chrome_set_off() else ())
    in $P.ret<int>(0) end))
  else ()
end

fn _show_reader (): void = let
  val () = !_view := 1
  val () = ui_show("qllc", false)
  val () = ui_show("qinf", false)
  val () = ui_show("qrvw", true)
  (* The browser's (and Android's) back button leaves the reader *)
  val a = $A.alloc<byte>(2)
  val () = $A.write_byte(a, 0, 35)
  val () = $A.write_byte(a, 1, 114)
  val @(f, b) = $A.freeze<byte>(a)
  val () = $NAV.push_state(b, 2)
  val () = $A.drop<byte>(f, b)
  val () = $A.free<byte>($A.thaw<byte>(f))
  val () = _chrome_set(true)
in ui_focus("qcnt") end

(* Opens library book i where it was left *)
fn _open_book {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) =>
    if x.shelf = 2 then let
      val () = modal_open(0, "Archived", "OK", "-", "-")
    in modal_text_lit("This book is archived. Import its file again to read it.") end
    else let
      val () = _show_reader()
      val () = reader_stack_clear()
      val () = ui_text("qcht", "Loading...")
      val ch = x.ch
      val pg = x.pg
      val anchor = x.anchor
      val h1 = x.h1
      val h2 = x.h2
    in
      if open_key_get() = x.key then
        $P.discard<int>($P.and_then<int><int>(annot_load(h1, h2), lam(_) => reader_goto(ch, pg, anchor)))
      else
        $P.discard<int>($P.and_then<Int><int>(open_stored(x.key, h1, h2), lam(r) =>
          if r < 0 then let
            val () = _show_library()
            val () = ui_text("qert", "This book's file could not be read. Import it again.")
            val () = ui_show("qerr", true)
          in $P.ret<int>(r) end
          else $P.and_then<int><int>(annot_load(h1, h2), lam(_) => reader_goto(ch, pg, anchor))))
    end

(* ============================================================
   The library: menus, info, shelves
   ============================================================ *)

fn _save_render (): void = let
  val () = lib_save()
in lib_render() end

(* Sets book i's shelf *)
fn _set_shelf {i:int} (i: int i, shelf: Int): void = let
  val () = lib_update(i, lam(x) => @{
    key = x.key, h1 = x.h1, h2 = x.h2, shelf = shelf, added = x.added, opened = x.opened,
    ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
    fsz = x.fsz, cover = x.cover, done = x.done })
in _save_render() end

(* Deletes the stored data under key letter c of book (h1, h2) *)
fn _idb_del {c:nat | c < 256} (c: int c, h1: int, h2: int): void = let
  val k = lib_key(c, h1, h2)
  val @(f, b) = $A.freeze<byte>(k)
  val () = $P.discard<Int>($IDB.idb_delete(b, 15))
  val () = $A.drop<byte>(f, b)
in $A.free<byte>($A.thaw<byte>(f)) end

(* Archives book i: its file is deleted, its record kept *)
fn _archive {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val () = _idb_del(98, x.h1, x.h2)
      val () = (if open_key_get() = x.key then open_key_set(0) else ())
    in _set_shelf(i, 2) end

(* Deletes book i and everything stored for it *)
fn _delete {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val () = _idb_del(98, x.h1, x.h2)
      val () = _idb_del(99, x.h1, x.h2)
      val () = _idb_del(97, x.h1, x.h2)
      val () = (if open_key_get() = x.key then open_key_set(0) else ())
      val () = lib_remove(i)
    in _save_render() end

(* The book menu for book i, its items as its shelf asks *)
fn _menu_open {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val () = !_menu_idx := i
      val () = (if x.shelf = 1 then ui_text("qcmh", "Unhide") else ui_text("qcmh", "Hide"))
      val () = (if x.shelf = 2 then ui_text("qcma", "Restore") else ui_text("qcma", "Archive"))
      val () = ui_show("qctx", true)
    in ui_focus("qcmi") end

(* "N% · Ch C of T" for x in b; its length *)
fn _progress_text {l:agz} (b: !$A.arr(byte, l, 64), x: bnums): [k:nat | k <= 64] int k = let
  val off = $S.int_to_str(b, 0, 64, lib_progress(x))
  val () = $A.set<byte>(b, off, $A.int2byte(37))
  val tch = x.tch
  val ch0 = x.ch
in
  if tch <= 0 then off + 1
  else let
    val ch = (if ch0 >= 0 then ch0 + 1 else 1): Int
    val () = $A.set<byte>(b, off + 1, $A.int2byte(32))
    val () = $A.set<byte>(b, off + 2, $A.int2byte(194))
    val () = $A.set<byte>(b, off + 3, $A.int2byte(183))
    val () = $A.set<byte>(b, off + 4, $A.int2byte(32))
    val () = $A.write_text(b, off + 5, $A.text_lit("Ch "), 3)
    val o2 = $S.int_to_str(b, off + 8, 64, ch)
    val () = $A.write_text(b, o2, $A.text_lit(" of "), 4)
  in $S.int_to_str(b, o2 + 4, 64, tch) end
end

(* The info view of book i *)
fn _info_open {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val () = !_menu_idx := i
      val @(t, tn) = lib_text(i, 0)
      val () = ui_text_buf("qint", t, tn)
      val @(a, an) = lib_text(i, 1)
      val () = ui_text_buf("qina", a, an)
      (* progress: "N% · chapter C of T" *)
      val b = $A.alloc<byte>(64)
      val off = _progress_text(b, x)
      val () = ui_text_buf("qivp", b, off)
      val d = $A.alloc<byte>(32)
      val dk = date_text(d, x.added)
      val () = ui_text_buf("qiva", d, dk)
      val () = (if x.opened > 0 then let
          val d = $A.alloc<byte>(32)
          val dk = date_text(d, x.opened)
        in ui_text_buf("qivl", d, dk) end
        else ui_text("qivl", "Never"))
      val z = $A.alloc<byte>(32)
      val zk = size_text(z, x.fsz)
      val () = ui_text_buf("qivs", z, zk)
      val () = (if x.shelf = 1 then ui_text("qinh", "Unhide") else ui_text("qinh", "Hide"))
      val () = (if x.shelf = 2 then ui_text("qinr", "Restore") else ui_text("qinr", "Archive"))
      val () = ui_attr("qinc", "src", "data:,")
      val () = (if x.cover > 0 then lib_show_cover_in("qinc", x.h1, x.h2, x.cover) else ())
      val () = ui_show("qinf", true)
    in ui_focus("qinx") end

(* A book menu or info view action on book i: 1 hide/unhide, 2 archive
   or restore, 3 delete (asked first) *)
fn _book_action {i:int} (i: int i, act: int): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) =>
    if act = 1 then _set_shelf(i, (if x.shelf = 1 then 0 else 1))
    else if act = 2 then
      (if x.shelf = 2 then let
         val () = modal_open(0, "Restore", "OK", "-", "-")
       in modal_text_lit("To restore this book, import its file again.") end
       else _archive(i))
    else let
      val () = !_menu_idx := i
      val () = modal_open(2, "Delete book?", "Cancel", "Delete", "-")
    in modal_text_lit("The book, its reading position and its annotations are removed.") end

(* ============================================================
   Settings
   ============================================================ *)

fn _settings_changed (): void = let
  val () = set_apply(lib_sort_get())
in if !_view = 1 then reader_relayout() else () end

fn _clamp {lo,hi:int | lo <= hi} (v: Int, lo: int lo, hi: int hi): [r:int | lo <= r; r <= hi] int r =
  if v < lo then lo else if v > hi then hi else v

(* ============================================================
   Listeners
   ============================================================ *)

(* ============================================================
   Annotations
   ============================================================ *)

(* Whether text is selected *)
fn _has_selection (): bool =
  case+ $DR.get_selection_text() of
  | ~$R.none() => false
  | ~$R.some(b) => let val () = $DC.blob_free(b) in true end

(* The note dialog for annotation i *)
fn _note_open (i: int): void =
  if i < 0 then ()
  else let
    val () = !_note_idx := i
    val () = modal_open(5, "Note", "Cancel", "Save", "-")
    val () = modal_textarea()
  in annot_note_show(i) end

(* The note in the dialog's text area, kept as annotation _note_idx's *)
fn _note_save (): void = let
  val a = $A.alloc<byte>(4)
  val () = $A.write_text(a, 0, $A.text_lit("qmta"), 4)
  val @(f, b) = $A.freeze<byte>(a)
  val r = $DR.read_input_value(b, 4)
  val () = $A.drop<byte>(f, b)
  val () = $A.free<byte>($A.thaw<byte>(f))
  val i = !_note_idx
in
  case+ r of
  | ~$R.none() => let
      val e = $A.alloc<byte>(1)
      val () = annot_note_set(i, e, 0)
    in annot_render() end
  | ~$R.some(v) => let
      val n = $DC.blob_len(v)
    in
      if n <= 0 then let
        val () = $DC.blob_free(v)
        val e = $A.alloc<byte>(1)
        val () = annot_note_set(i, e, 0)
      in annot_render() end
      else if n > 65536 then let
        val () = $DC.blob_free(v)
      in end
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(v, 0, a, n)
        val () = $DC.blob_free(v)
        val () = annot_note_set(i, a, n)
      in annot_render() end
    end
end

(* The selected text, to the clipboard *)
fn _copy_selection (): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(b) => let
      val n = $DC.blob_len(b)
    in
      if n <= 0 then $DC.blob_free(b)
      else if n > 1048576 then $DC.blob_free(b)
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(b, 0, a, n)
        val () = $DC.blob_free(b)
        val @(f, bb) = $A.freeze<byte>(a)
        val () = $P.discard<Int>($P.vow($CB.clipboard_write(bb, n)))
        val () = $A.drop<byte>(f, bb)
      in $A.free<byte>($A.thaw<byte>(f)) end
    end

(* Exports the open book's annotations *)
fn _export (): void = let
  val i = lib_index_of_key(open_key_get())
  val @(t, tn) = lib_text(i, 0)
  val @(a, an) = lib_text(i, 1)
in annot_export(t, tn, a, an) end

(* Goes to annotation i, remembering where the reader was *)
fn _annot_go (i: int): void = let
  val @(ch, pg, sn) = annot_dest(i)
in if ch >= 0 then reader_jump_to(ch, pg, sn) else () end

fn _wire_library (): void = let
  (* import *)
  val () = ui_listen("qfin", "change", 1, lam(_) => let val () = import_picked() in 0 end)
  (* drag and drop *)
  val () = ui_listen("qllc", "dragover", 23, lam(_) => let
      val () = $EV.prevent_default()
    in let val () = ui_attr("qllc", "class", "lib drag") in 0 end end)
  val () = ui_listen("qllc", "dragleave", 24, lam(_) => let
      val () = ui_attr("qllc", "class", "lib")
    in 0 end)
  val () = ui_listen("qllc", "drop", 25, lam(_) => let
      val () = $EV.prevent_default()
      val () = ui_attr("qllc", "class", "lib")
      val () = import_dropped()
    in 0 end)
  (* the cards: open, and the book menu *)
  val () = ui_listen("qlst", "click", 16, lam(h) => let
      val i = _target_num(h, "k")
    in if i >= 0 then let val () = _open_book(i) in 0 end else 0 end)
  val () = ui_listen("qlst", "contextmenu", 15, lam(h) => let
      val () = $EV.prevent_default()
      val i = _target_num(h, "k")
    in if i >= 0 then let val () = _menu_open(i) in 0 end else 0 end)
  val () = ui_listen("qctx", "click", 18, lam(h) => let
      val t = _target(h)
      val i = !_menu_idx
      val () = ui_show("qctx", false)
      val () = (if i >= 0 then
          (if _is(t, "qcmi") then _info_open(i)
           else if _is(t, "qcmh") then _book_action(i, 1)
           else if _is(t, "qcma") then _book_action(i, 2)
           else if _is(t, "qcmd") then _book_action(i, 3)
           else ()) else ())
    in let val () = _target_free(t) in 0 end end)
  (* the info view *)
  val () = ui_listen("qinf", "click", 19, lam(h) => let
      val t = _target(h)
      val i = !_menu_idx
      val () = (if _is(t, "qinx") then ui_show("qinf", false)
        else if i < 0 then ()
        else if _is(t, "qinh") then let val () = ui_show("qinf", false) in _book_action(i, 1) end
        else if _is(t, "qinr") then let val () = ui_show("qinf", false) in _book_action(i, 2) end
        else if _is(t, "qind") then _book_action(i, 3)
        else ())
    in let val () = _target_free(t) in 0 end end)
  (* sort and shelf *)
  val () = ui_listen("qsrt", "click", 20, lam(_) => let
      val o = lib_sort_get()
      val o = (if o >= 3 then 0 else o + 1): int
      val () = lib_sort(o)
      val () = lib_sort_label(o)
      val () = set_apply(o)
    in let val () = lib_render() in 0 end end)
  val () = ui_listen("qshf", "click", 21, lam(_) => let
      val s = lib_shelf_get()
      val () = lib_shelf_set((if s >= 2 then 0 else s + 1): int)
    in let val () = lib_render() in 0 end end)
  (* search *)
  val () = ui_listen("qlsq", "input", 22, lam(h) => let
      val @(q, n) = _input_text(h)
      val () = lib_query_set(q, n)
    in let val () = lib_render() in 0 end end)
  (* a backup picked to restore *)
  val () = ui_listen("qbfi", "change", 50, lam(_) => let
      val () = ui_show("qlmn", false)
      val () = backup_import()
    in 0 end)
  (* the error banner *)
  val () = ui_listen("qerx", "click", 26, lam(_) => let val () = ui_show("qerr", false) in 0 end)
  (* the library menu *)
  val () = ui_listen("qlgr", "click", 27, lam(_) => let
      val () = ui_show("qlmn", true)
    in let val () = ui_focus("qlme") in 0 end end)
  val () = ui_listen("qlmn", "click", 28, lam(h) => let
      val t = _target(h)
      val () = (if _is(t, "qlmr") then let
          val () = ui_show("qlmn", false)
          val () = modal_open(3, "Factory reset?", "Cancel", "Reset", "-")
        in modal_text_lit("Every book, position, annotation and setting is deleted.") end
        else if _is(t, "qlme") then let
          val () = ui_show("qlmn", false)
        in backup_export() end
        else if _is(t, "qlmc") then ui_show("qlmn", false)
        else if _is(t, "qlmn") then ui_show("qlmn", false)
        else ())
    in let val () = _target_free(t) in 0 end end)
  (* the dialog *)
  val () = ui_listen("qmod", "click", 29, lam(h) => let
      val t = _target(h)
      val k = modal_kind()
      val b1 = _is(t, "qmb1")
      val b2 = _is(t, "qmb2")
      val () = _target_free(t)
    in
      if k = 1 then
        (if b1 then let val () = import_dup_answer(1) in 0 end
         else if b2 then let val () = import_dup_answer(2) in 0 end else 0)
      else if k = 2 then
        (if b2 then let
           val () = modal_close()
           val () = ui_show("qinf", false)
           val i = !_menu_idx
         in if i >= 0 then let val () = _delete(i) in 0 end else 0 end
         else if b1 then let val () = modal_close() in 0 end else 0)
      else if k = 3 then
        (if b2 then let
           val () = modal_close()
           val () = $IDB.idb_delete_database()
           val () = lib_clear()
           val () = set_reset()
         in let val () = $NAV.reload() in 0 end end
         else if b1 then let val () = modal_close() in 0 end else 0)
      else if k = 5 then
        (if b2 then let
           val () = _note_save()
         in let val () = modal_close() in 0 end end
         else if b1 then let val () = modal_close() in 0 end else 0)
      else if b1 then let val () = modal_close() in 0 end
      else if b2 then let val () = modal_close() in 0 end
      else 0
    end)
in end

fn _wire_settings (): void = let
  val () = ui_listen("qset", "click", 8, lam(_) => let
      val () = ui_show("qspn", true)
    in let val () = ui_focus("qscl") in 0 end end)
  val () = ui_listen("qspn", "click", 9, lam(h) => let
      val t = _target(h)
      val changed = (if _is(t, "qff0") then let val () = set_font_set(0) in true end
        else if _is(t, "qff1") then let val () = set_font_set(1) in true end
        else if _is(t, "qff2") then let val () = set_font_set(2) in true end
        else if _is(t, "qth0") then let val () = set_theme_set(0) in true end
        else if _is(t, "qth1") then let val () = set_theme_set(1) in true end
        else if _is(t, "qth2") then let val () = set_theme_set(2) in true end
        else if _is(t, "qth3") then let val () = set_theme_set(3) in true end
        else if _is(t, "qsrs") then let val () = set_reset() in true end
        else false): bool
      val close = _is(t, "qscl")
      val () = _target_free(t)
      val () = (if close then ui_show("qspn", false) else ())
    in if changed then let val () = _settings_changed() in 0 end else 0 end)
  val () = ui_listen("qfsr", "input", 10, lam(h) => let
      val () = set_size_set(_clamp(_input_num(h), 12, 32))
    in let val () = _settings_changed() in 0 end end)
  val () = ui_listen("qlhr", "input", 11, lam(h) => let
      val () = set_lh_set(_clamp(_input_num(h), 12, 24))
    in let val () = _settings_changed() in 0 end end)
  val () = ui_listen("qmgr", "input", 12, lam(h) => let
      val () = set_margin_set(_clamp(_input_num(h), 0, 4))
    in let val () = _settings_changed() in 0 end end)
in end

(* ============================================================
   Search
   ============================================================ *)

(* Whether an element is shown *)
fn _shown {ni:pos | ni < 256} (id: string ni): bool = let
  val () = ui_measure(id)
in $DR.get_measure_w() > 0 end

(* The search field, made again holding a[0, k) *)
fn _search_value {l:agz}{n:pos}{k:nat | k <= n; k < 65536} (a: $A.arr(byte, l, n), k: int k): void =
  if k > 0 then ui_attr_buf("qsri", "value", a, k) else $A.free<byte>(a)

fn _search_field {l:agz}{n:pos}{k:nat | k <= n; k < 65536} (a: $A.arr(byte, l, n), k: int k): void = let
  val () = ui_clear("qsrh")
  val () = ui_add("qsrh", "qsri", "input")
  val () = ui_attr("qsri", "type", "search")
  val () = ui_attr("qsri", "placeholder", "Search in book")
  val () = ui_attr("qsri", "aria-label", "Search in book")
  val () = _search_value(a, k)
  val () = ui_btn("qsrh", "qsrx", "ibtn", "\xE2\x9C\x95")
in ui_attr("qsrx", "aria-label", "Close search") end

fn _search_open (): void = let
  val () = ui_show("qsrp", true)
in ui_focus("qsri") end

(* Ends the search: the reader goes back to where it was before it
   jumped to a hit *)
fn _search_end (): void = let
  val () = ui_show("qsrp", false)
  val () = reader_search_close()
in ui_focus("qcnt") end

(* Searches for the field's text *)
fn _search_run (): void = let
  val a = $A.alloc<byte>(4)
  val () = $A.write_text(a, 0, $A.text_lit("qsri"), 4)
  val @(f, b) = $A.freeze<byte>(a)
  val r = $DR.read_input_value(b, 4)
  val () = $A.drop<byte>(f, b)
  val () = $A.free<byte>($A.thaw<byte>(f))
in
  case+ r of
  | ~$R.none() => reader_search($A.alloc<byte>(1), 0)
  | ~$R.some(v) => let
      val n = $DC.blob_len(v)
    in
      if n <= 0 then let
        val () = $DC.blob_free(v)
      in reader_search($A.alloc<byte>(1), 0) end
      else if n > 65535 then $DC.blob_free(v)
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(v, 0, a, n)
        val () = $DC.blob_free(v)
      in reader_search(a, n) end
    end
end

(* A keystroke in the field: the search runs once typing pauses *)
fn _search_input (): void = let
  val () = !_search_tick := !_search_tick + 1
  val g = !_search_tick
in
  $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(300)), lam(_) => let
    val () = (if !_search_tick = g then _search_run() else ())
  in $P.ret<int>(0) end))
end

(* Searches for the selected text *)
fn _search_selection (): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(b) => let
      val n = $DC.blob_len(b)
    in
      if n <= 0 then $DC.blob_free(b)
      else if n > 1000 then $DC.blob_free(b)
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(b, 0, a, n)
        val c = $A.alloc<byte>(n)
        val () = $DC.blob_read(b, 0, c, n)
        val () = $DC.blob_free(b)
        val () = _search_field(a, n)
        val () = ui_show("qsrp", true)
        val () = !_search_tick := !_search_tick + 1
      in reader_search(c, n) end
    end

(* Closes the reader's panels; whether one was open *)
fn _panels_close (): bool = let
  val () = ui_measure("qtoc")
  val a = $DR.get_measure_w() > 0
  val () = ui_measure("qspn")
  val b = $DR.get_measure_w() > 0
  val () = ui_measure("qsrp")
  val c = $DR.get_measure_w() > 0
  val () = ui_measure("qanp")
  val d = $DR.get_measure_w() > 0
  val () = ui_show("qtoc", false)
  val () = ui_show("qspn", false)
  val () = ui_show("qsrp", false)
  val () = ui_show("qanp", false)
in a || b || c || d end

(* A page turn: the bars hide *)
fn _next (): void = let
  val () = (if !_chrome then _chrome_set(false) else ())
in page_next() end

fn _prev (): void = let
  val () = (if !_chrome then _chrome_set(false) else ())
in page_prev() end

(* The page to the left and to the right: back and on, or the other way
   in a book read right to left *)
fn _left (): void = if reader_rtl() then _next() else _prev()
fn _right (): void = if reader_rtl() then _prev() else _next()

(* The page turns a pointer at x makes: the left quarter back, the right
   quarter on, between them the bars shown or hidden *)
fn _zone_click (x: Int): void = let
  val () = ui_measure("qcnt")
  val cx = $DR.get_measure_x()
  val cw = $DR.get_measure_w()
in
  if cw <= 0 then ()
  else if x < cx + cw / 4 then _left()
  else if x > cx + cw - cw / 4 then _right()
  else _chrome_set(~(!_chrome))
end

(* A key's name at b[1, 1 + k), and its modifier flags after it *)
fn _key_is {l:agz}{n:nat}{sn:pos} (b: !$A.arr(byte, l, n), n: int n, name: string sn): bool = let
  val sl = g1u2i(string1_length(name))
in
  if n <> sl + 2 then false
  else if byte2int0($A.get<byte>(b, 0)) <> sl then false
  else _bytes_at(b, n, 1, name, sl, 0)
end

fn _reader_key {l:agz}{n:nat} (b: !$A.arr(byte, l, n), n: int n): void = let
  val shift = (if n >= 2 then $AR.band_g1($AR.low_byte(byte2int0($A.get<byte>(b, n - 1))), 1) = 1 else false): bool
  (* Ctrl or Cmd *)
  val fl = (if n >= 2 then $AR.band_g1($AR.low_byte(byte2int0($A.get<byte>(b, n - 1))), 10) else 0): int
in
  if _key_is(b, n, "ArrowRight") then _right()
  else if _key_is(b, n, "PageDown") then _next()
  else if _key_is(b, n, "ArrowLeft") then _left()
  else if _key_is(b, n, "PageUp") then _prev()
  else if _key_is(b, n, " ") then (if shift then _prev() else _next())
  else if _key_is(b, n, "Home") then reader_page(0)
  else if _key_is(b, n, "End") then reader_page(1000000)
  else if _key_is(b, n, "b") then annot_bookmark_toggle(reader_anchor())
  else if _key_is(b, n, "B") then annot_bookmark_toggle(reader_anchor())
  else if _key_is(b, n, "t") then _chrome_set(~(!_chrome))
  else if _key_is(b, n, "T") then _chrome_set(~(!_chrome))
  else if _key_is(b, n, "/") then let
      val () = $EV.prevent_default()
    in _search_open() end
  else if (if _key_is(b, n, "f") then fl >= 2 else false) then let
      val () = $EV.prevent_default()
    in _search_open() end
  else if _key_is(b, n, "Escape") then
    (if _panels_close() then ui_focus("qcnt")
     else if _shown("qsrn") then _search_end()
     else if !_chrome then _chrome_set(false) else _show_library())
  else ()
end

(* A key while the search panel is open: Enter goes to the next hit
   (Shift+Enter the one before), Escape closes the panel *)
fn _search_key {l:agz}{n:nat} (b: !$A.arr(byte, l, n), n: int n): void = let
  val shift = (if n >= 2 then $AR.band_g1($AR.low_byte(byte2int0($A.get<byte>(b, n - 1))), 1) = 1 else false): bool
in
  if _key_is(b, n, "Enter") then let
      val () = reader_search_step(if shift then ~1 else 1)
    in if _shown("qsrn") then let val () = ui_show("qsrp", false) in ui_focus("qcnt") end else () end
  else if _key_is(b, n, "Escape") then let
      val () = ui_show("qsrp", false)
    in if _shown("qsrn") then ui_focus("qcnt") else _search_end() end
  else ()
end

(* The contents panel, open on its contents tab *)
fn _toc_open (): void = let
  val () = (case+ reading_get() of
    | @(_, _, c, tc) => toc_render((if c > 0 then c - 1 else 0), tc))
  val () = ui_attr("qtct", "aria-selected", "true")
  val () = ui_attr("qtcm", "aria-selected", "false")
  val () = ui_show("qtcl", true)
  val () = ui_show("qtbl", false)
  val () = ui_show("qtoc", true)
in ui_focus("qtcx") end

(* The contents panel, open on its bookmarks tab *)
fn _bookmarks_open (): void = let
  val () = annot_render_bookmarks()
  val () = ui_attr("qtct", "aria-selected", "false")
  val () = ui_attr("qtcm", "aria-selected", "true")
  val () = ui_show("qtcl", false)
in ui_show("qtbl", true) end

fn _wire_toc (): void = let
  val () = ui_listen("qtcb", "click", 34, lam(_) => let val () = _toc_open() in 0 end)
  val () = ui_listen("qtoc", "click", 35, lam(h) => let
      val t = _target(h)
      val row = _row_of(t, "qe")
      val bgo = _row_of(t, "qb")
      val bdl = _row_of(t, "qx")
      val () = (if _is(t, "qtcx") then ui_show("qtoc", false)
        else if _is(t, "qtct") then _toc_open()
        else if _is(t, "qtcm") then _bookmarks_open()
        else if bgo >= 0 then let val () = ui_show("qtoc", false) in _annot_go(bgo) end
        else if bdl >= 0 then let val () = annot_delete(bdl) in _bookmarks_open() end
        else if row >= 0 then let
          val () = ui_show("qtoc", false)
        in reader_goto_entry(row) end
        else ())
      val () = _target_free(t)
    in 0 end)
  val () = ui_listen("qpbk", "click", 36, lam(_) => let val () = reader_back() in 0 end)
  (* the scrubber: a drag shows where it would go, letting go goes there *)
  val () = ui_listen("qtrk", "pointerdown", 37, lam(h) => let
      val x = _event_x(h)
      val () = !_scrubbing := true
      val () = _chrome_set(true)
    in let val () = reader_scrub_preview(x) in 0 end end)
  val () = ui_listen_doc("pointermove", 38, lam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = _chrome_set(true)
      in let val () = reader_scrub_preview(x) in 0 end end
      else 0)
  val () = ui_listen_doc("pointerup", 39, lam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = !_scrubbing := false
      in let val () = reader_scrub_go(x) in 0 end end
      else 0)
  (* the app hidden (another tab, another app): where the reader is is
     stored *)
  val () = ui_listen_doc("visibilitychange", 40, lam(_) =>
      if !_view = 1 then let val () = reader_save() in 0 end else 0)
in end

fn _wire_annotations (): void = let
  val () = ui_listen("qbmk", "click", 41, lam(_) => let
      val () = annot_bookmark_toggle(reader_anchor())
    in 0 end)
  val () = ui_listen_doc("selectionchange", 42, lam(_) =>
      if !_view = 1 then let val () = ui_show("qsel", _has_selection()) in 0 end else 0)
  val () = ui_listen("qsel", "click", 43, lam(h) => let
      val t = _target(h)
      val hl = _is(t, "qslh")
      val nt = _is(t, "qsln")
      val cp = _is(t, "qslc")
      val sr = _is(t, "qsls")
      val () = _target_free(t)
      val () = (if hl then let val _ = annot_highlight() in () end
        else if nt then _note_open(annot_highlight())
        else if cp then _copy_selection()
        else if sr then _search_selection()
        else ())
    in let val () = ui_show("qsel", false) in 0 end end)
  val () = ui_listen("qanb", "click", 44, lam(_) => let
      val () = annot_render()
      val () = ui_show("qanp", true)
    in let val () = ui_focus("qanc") in 0 end end)
  val () = ui_listen("qanp", "click", 45, lam(h) => let
      val t = _target(h)
      val go = _row_of(t, "qa")
      val nt = _row_of(t, "qn")
      val dl = _row_of(t, "qd")
      val close = _is(t, "qanc")
      val ex = _is(t, "qanx")
      val () = _target_free(t)
      val () = (if close then ui_show("qanp", false)
        else if ex then _export()
        else if go >= 0 then let val () = ui_show("qanp", false) in _annot_go(go) end
        else if nt >= 0 then _note_open(nt)
        else if dl >= 0 then let val () = annot_delete(dl) in annot_render() end
        else ())
    in 0 end)
in end

fn _wire_search (): void = let
  val () = ui_listen("qsch", "click", 46, lam(_) => let
      val () = (if _shown("qsrp") then ui_show("qsrp", false) else _search_open())
    in 0 end)
  (* the field is made again for a selection's search: its events are
     taken on the panel *)
  val () = ui_listen("qsrp", "input", 47, lam(_) => let val () = _search_input() in 0 end)
  val () = ui_listen("qsrp", "click", 48, lam(h) => let
      val t = _target(h)
      val go = _row_of(t, "qh")
      val close = _is(t, "qsrx")
      val () = _target_free(t)
      val () = (if close then _search_end()
        else if go >= 0 then let
          val () = ui_show("qsrp", false)
        in reader_search_go(go) end
        else ())
    in 0 end)
  val () = ui_listen("qsrn", "click", 49, lam(h) => let
      val t = _target(h)
      val pv = _is(t, "qsrv")
      val nx = _is(t, "qsrw")
      val close = _is(t, "qsrz")
      val () = _target_free(t)
      val () = (if pv then reader_search_step(~1)
        else if nx then reader_search_step(1)
        else if close then _search_end()
        else ())
    in 0 end)
in end

fn _wire_reader (): void = let
  val () = ui_listen("qbbk", "click", 2, lam(_) => let val () = _show_library() in 0 end)
  val () = ui_listen("qprv", "click", 3, lam(_) => let val () = page_prev() in 0 end)
  val () = ui_listen("qnxt", "click", 4, lam(_) => let val () = page_next() in 0 end)
  val () = ui_listen("qcnt", "click", 5, lam(h) => let
      val t = _target(h)
      val node = _row_of(t, "c")
      val x = _target_x(t)
      val () = _target_free(t)
    in
      if _has_selection() then 0
      else if (if node >= 0 then reader_link_at(node) else false) then 0
      else if x >= 0 then let val () = _zone_click(x) in 0 end else 0
    end)
  val () = ui_listen_doc("keydown", 7, lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(b, n) => let
          val () = (if !_view <> 1 then ()
            else if _shown("qmod") then ()
            else if _shown("qsrp") then _search_key(b, n)
            else _reader_key(b, n))
          val () = $A.free<byte>(b)
        in 0 end)
  (* the wheel turns a page, then pauses a quarter second *)
  val () = ui_listen("qcnt", "wheel", 13, lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(b, n) =>
        if n < 8 then let val () = $A.free<byte>(b) in 0 end
        else let
          val dy = _i32at(b, 4)
          val () = $A.free<byte>(b)
        in
          if !_wheel_busy then 0
          else if dy = 0 then 0
          else let
            val () = !_wheel_busy := true
            val () = (if dy > 0 then _next() else _prev())
            val () = $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(250)), lam(_) => let
                val () = !_wheel_busy := false
              in $P.ret<int>(0) end))
          in 0 end
        end)
  (* a swipe of 60 px or more, more across than down, turns a page *)
  val () = ui_listen("qcnt", "touchstart", 30, lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(b, n) =>
        if n < 8 then let val () = $A.free<byte>(b) in 0 end
        else let
          val () = !_touch_x := _i32at(b, 0)
          val () = !_touch_y := _i32at(b, 4)
          val () = $A.free<byte>(b)
        in 0 end)
  val () = ui_listen("qcnt", "touchend", 31, lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(b, n) =>
        if n < 8 then let val () = $A.free<byte>(b) in 0 end
        else let
          val dx = _i32at(b, 0) - !_touch_x
          val dy = _i32at(b, 4) - !_touch_y
          val () = $A.free<byte>(b)
          val adx = (if dx < 0 then ~dx else dx): int
          val ady = (if dy < 0 then ~dy else dy): int
        in
          if adx < 60 then 0
          else if adx <= ady then 0
          else if dx < 0 then let val () = _right() in 0 end
          else let val () = _left() in 0 end
        end)
  (* a resize lays the chapter out again, once it settles *)
  val () = ui_listen_win("resize", 32, lam(_) => let
      val () = !_resize_gen := !_resize_gen + 1
      val gen = !_resize_gen
      val () = $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(200)), lam(_) => let
          val () = (if !_resize_gen = gen then (if !_view = 1 then reader_relayout() else ()) else ())
        in $P.ret<int>(0) end))
    in 0 end)
  (* the browser's back button: out of the reader *)
  val () = $NAV.set_popstate_callback(lam(_) => let
      val () = (if !_view = 1 then _show_library() else ())
    in 0 end)
in end

(* ============================================================
   Startup
   ============================================================ *)

implement main0 () = let
  val () = app_build()
  val () = _wire_library()
  val () = _wire_settings()
  val () = _wire_reader()
  val () = _wire_toc()
  val () = _wire_annotations()
  val () = _wire_search()
  (* files handed to the app from outside it (an Android intent) *)
  val () = $EV.listen_external_files(33, lam(h) => let
      val () = (if !_view = 1 then _show_library() else ())
      val () = import_external(h)
    in 0 end)
  val p = $P.and_then<int><int>(set_load(), lam(sort) => let
      val () = lib_sort_label(sort)
    in
      $P.and_then<int><int>(lib_load(), lam(_) => let
        val () = lib_sort(sort)
        val () = lib_render()
      in $P.ret<int>(0) end)
    end)
in $P.discard<int>(p) end
