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
staload "library.sats"
staload "settings.sats"
staload "import.sats"
staload "reader.sats"
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
(* Where a touch started *)
val _touch_x = ref<int>(0)
val _touch_y = ref<int>(0)

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
      val () = ui_text("qcht", "Loading...")
      val ch = x.ch
      val pg = x.pg
      val anchor = x.anchor
    in
      if open_key_get() = x.key then
        $P.discard<int>(reader_goto(ch, pg, anchor))
      else
        $P.discard<int>($P.and_then<Int><int>(open_stored(x.key, x.h1, x.h2), lam(r) =>
          if r < 0 then let
            val () = _show_library()
            val () = ui_text("qert", "This book's file could not be read. Import it again.")
            val () = ui_show("qerr", true)
          in $P.ret<int>(r) end
          else reader_goto(ch, pg, anchor)))
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

(* The page turns a pointer at x makes: the left quarter back, the right
   quarter on, between them the bars shown or hidden *)
fn _zone_click (x: Int): void = let
  val () = ui_measure("qcnt")
  val cx = $DR.get_measure_x()
  val cw = $DR.get_measure_w()
in
  if cw <= 0 then ()
  else if x < cx + cw / 4 then page_prev()
  else if x > cx + cw - cw / 4 then page_next()
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
in
  if _key_is(b, n, "ArrowRight") then page_next()
  else if _key_is(b, n, "PageDown") then page_next()
  else if _key_is(b, n, "ArrowLeft") then page_prev()
  else if _key_is(b, n, "PageUp") then page_prev()
  else if _key_is(b, n, " ") then (if shift then page_prev() else page_next())
  else if _key_is(b, n, "Home") then reader_page(0)
  else if _key_is(b, n, "End") then reader_page(1000000)
  else if _key_is(b, n, "t") then _chrome_set(~(!_chrome))
  else if _key_is(b, n, "T") then _chrome_set(~(!_chrome))
  else if _key_is(b, n, "Escape") then
    (if !_chrome then _chrome_set(false) else _show_library())
  else ()
end

fn _wire_reader (): void = let
  val () = ui_listen("qbbk", "click", 2, lam(_) => let val () = _show_library() in 0 end)
  val () = ui_listen("qprv", "click", 3, lam(_) => let val () = page_prev() in 0 end)
  val () = ui_listen("qnxt", "click", 4, lam(_) => let val () = page_next() in 0 end)
  val () = ui_listen("qcnt", "click", 5, lam(h) => let
      val x = _event_x(h)
    in if x >= 0 then let val () = _zone_click(x) in 0 end else 0 end)
  val () = ui_listen_doc("keydown", 7, lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(b, n) => let
          val () = (if !_view = 1 then _reader_key(b, n) else ())
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
            val () = (if dy > 0 then page_next() else page_prev())
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
          else if dx < 0 then let val () = page_next() in 0 end
          else let val () = page_prev() in 0 end
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
