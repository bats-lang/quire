#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use wasm.bats-packages.dev/decompress as DC
#use gestures as G

staload "book.sats"
staload "pages.sats"
staload "ui.sats"
staload "layer.sats"
staload "app.sats"
staload "style.sats"
staload "modal.sats"
staload "undo.sats"
staload "backup.sats"
staload "library.sats"
staload "settings.sats"
staload "import.sats"
staload "reader.sats"
staload "toc.sats"
staload "annot.sats"
staload "mem.sats"
staload CB = "wasm.bats-packages.dev/bridge/src/clipboard.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload WN = "wasm.bats-packages.dev/bridge/src/window.sats"
staload GP = "gestures/src/pointer.sats"
staload GT = "gestures/src/tracker.sats"
staload GD = "gestures/src/decode.sats"

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
(* The content node of the link within the book that has the focus, or -1 *)
val _focus_link = ref<int>(~1)
(* Whether the scrubber's thumb is being dragged *)
val _scrubbing = ref<bool>(false)
(* The gesture recognizer's state (linear, so it is taken out of its
   cell and put back); and whether a drag has just ended, so that the
   click the browser sends after it is not also a tap *)
datavtype gcell = GNone | GSome of $GT.gstate
val _gestures = ref<gcell>(GNone())
val _dragged = ref<bool>(false)
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
fn _target_num {sn:pos | sn <= 16} (h: $EV.event_payload, pre: string sn): [v:int | v >= ~1] int v =
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

(* The harm whose menu item (ui_harm_item) t is: its click asks about
   that same harm *)
fn _harm_clicked (t: !target): Option_vt(harm) =
  if _is(t, ui_harm_id(HEmptyTrash())) then Some_vt(HEmptyTrash()) else None_vt()

(* The number n of the target's id pre<n>, or -1 *)
fn _row_of {sn:pos | sn <= 16} (t: !target, pre: string sn): [v:int | v >= ~1] int v =
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

(* The y of a pointer event's target record, or -1 *)
fn _target_y (t: !target): Int =
  case+ t of
  | Target(b, n, _) => if n >= 8 then _i32at(b, 4) else ~1
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

(* ============================================================
   The view kept across a reload: the book that is open, if any, so a
   reload (or the app killed and started again) comes back to it, on its
   page, rather than to the library
   ============================================================ *)

fn _view_key (): [l:agz] $A.arr(byte, l, 4) = let
  val k = $A.alloc<byte>(4)
  val () = $A.write_text(k, 0, $A.text_lit("view"), 4)
in k end

(* Keeps "view": the open book's key, or -1 for the library *)
fn _view_save (key: int): void = let
  val b = $A.alloc<byte>(4)
  val () = $A.write_i32(b, 0, key)
  val @(bf, bb) = $A.freeze<byte>(b)
  val @(kf, kb) = $A.freeze<byte>(_view_key())
  val () = $P.discard<Int>($IDB.idb_put(kb, 4, bb, 4))
  val () = release_bytes(kf, kb)
in release_bytes(bf, bb) end

fn _show_library (): void = let
  val () = !_view := 0
  val () = ui_show("reader", false)
  (* the screen may sleep again, as it does outside the reader *)
  val () = $WN.keep_awake(false)
  val () = layer_close(LTypography())
  val () = layer_close(LContents())
  val () = layer_close(LSearch())
  val () = layer_close(LAnnotations())
  val () = layer_close(LNote())
  val () = layer_close(LImage())
  val () = ui_show("library", true)
  (* a reload now comes back here *)
  val () = _view_save(~1)
  val () = reader_search_stop()
  val () = reader_stack_clear()
  val () = window_close()
in lib_render() end

(* The reader's bars: shown, and hidden again after 5 seconds *)
fn _chrome_set_off (): void = let
  val () = !_chrome := false
in ui_attr("reader", AClass, "rv chrome-off") end

fn _chrome_set (on: bool): void = let
  (* bringing the bars up leaves the place a jump landed on: the back
     button goes *)
  val () = (if on && ~(!_chrome) then reader_stack_clear() else ())
  val () = !_chrome := on
  val () = (if on then ui_attr("reader", AClass, "rv") else ui_attr("reader", AClass, "rv chrome-off"))
  val () = !_chrome_gen := !_chrome_gen + 1
  val gen = !_chrome_gen
in
  if on then $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(5000)), lam(_) => let
      val () = (if !_chrome_gen = gen then _chrome_set_off() else ())
    in $P.ret<int>(0) end))
  else ()
end

(* The hint on turning pages, shown once, on the first book opened
   (a brief tip in context, not a tour): whether it has been shown,
   true until the last run's answer is read, so it never shows twice *)
val _hint_seen = ref<bool>(true)

fn _hint_key (): [l:agz] $A.arr(byte, l, 4) = let
  val k = $A.alloc<byte>(4)
  val () = $A.write_text(k, 0, $A.text_lit("hint"), 4)
in k end

(* Reads whether the hint was shown in an earlier run *)
fn _hint_load (): void = let
  val @(kf, kb) = $A.freeze<byte>(_hint_key())
  val p = $IDB.idb_get(kb, 4)
  val () = release_bytes(kf, kb)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) => let
    val () = (case+ take_blob(h) of
      | ~NoBlobBytes() => !_hint_seen := false
      | ~BlobBytes(b, _) => $A.free<byte>(b))
  in $P.ret<int>(0) end))
end

fn _hint_hide (): void = ui_show("turn-hint", false)

(* Shows the hint, the first time a book is opened: it goes at the first
   turn, or after 8 seconds *)
fn _hint_offer (): void =
  if !_hint_seen then ()
  else let
    val () = !_hint_seen := true
    val v = $A.alloc<byte>(1)
    val () = $A.write_byte(v, 0, 1)
    val @(vf, vb) = $A.freeze<byte>(v)
    val @(kf, kb) = $A.freeze<byte>(_hint_key())
    val () = $P.discard<Int>($IDB.idb_put(kb, 4, vb, 1))
    val () = release_bytes(kf, kb)
    val () = release_bytes(vf, vb)
    val () = ui_show("turn-hint", true)
  in
    $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(8000)), lam(_) => let
      val () = _hint_hide()
    in $P.ret<int>(0) end))
  end

fn _show_reader (): void = let
  val () = !_view := 1
  val () = ui_show("library", false)
  val () = layer_close(LBookInfo())
  val () = ui_show("reader", true)
  (* A reader does not touch the screen for a page's length: it stays
     awake while the book is open *)
  val () = $WN.keep_awake(true)
  (* The browser's (and Android's) back button leaves the reader *)
  val a = $A.alloc<byte>(2)
  val () = $A.write_byte(a, 0, 35)
  val () = $A.write_byte(a, 1, 114)
  val @(f, b) = $A.freeze<byte>(a)
  val () = $NAV.push_state(b, 2)
  val () = release_bytes(f, b)
  val () = _chrome_set(true)
in ui_focus("page") end

(* Opens library book i where it was left *)
(* src[0, n) copied to dst[o, o + n) *)
fun _copy_from_to {ls,ld:agz}{ms,md:nat}{n:nat | n <= ms}{o:nat | o + n <= md}{j:nat | j <= n} .<n - j>.
  (src: !$A.arr(byte, ls, ms), n: int n, dst: !$A.arr(byte, ld, md), o: int o, j: int j): void =
  if j >= n then ()
  else let val () = $A.set<byte>(dst, o + j, $A.get<byte>(src, j)) in _copy_from_to(src, n, dst, o, j + 1) end

fn _copy_into {ls,ld:agz}{ms,md:nat}{n:nat | n <= ms}{o:nat | o + n <= md}
  (src: !$A.arr(byte, ls, ms), n: int n, dst: !$A.arr(byte, ld, md), o: int o): void =
  _copy_from_to(src, n, dst, o, 0)

(* A shared selection's citation, book i's: "Author, Title" (as the
   export's) *)
fn _citation_set {i:int} (i: int i): void = let
  val @(t, tn) = lib_text(i, 0)
  val @(a, an) = lib_text(i, 1)
  val b = $A.alloc<byte>(520)
  val () = _copy_into(a, an, b, 0)
  val () = $A.set<byte>(b, an, $A.int2byte(44))
  val () = $A.set<byte>(b, an + 1, $A.int2byte(32))
  val () = _copy_into(t, tn, b, an + 2)
  val () = $A.free<byte>(t)
  val () = $A.free<byte>(a)
in ui_text_buf("share-citation", b, an + 2 + tn) end

fn _open_book {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) =>
    if x.shelf = 3 then let
      val () = modal_inform("In the Trash")
    in modal_text_lit("Restore this book from the Trash to read it.") end
    else if x.shelf = 2 then let
      val () = modal_inform("Archived")
    in modal_text_lit("This book is archived. Import its file again to read it.") end
    else let
      val () = _show_reader()
      val () = _hint_offer()
      val () = _citation_set(i)
      val () = reader_stack_clear()
      (* a reload now comes back to this book *)
      val () = _view_save(x.key)
      val () = ui_text("chapter-title", "Loading...")
      (* no page is shown until this book's is: the last book's stays out
         of the indicator *)
      val () = ui_clear("indicator-title")
      val () = ui_clear("indicator-label")
      val () = ui_clear("indicator-pages")
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
            val () = ui_text("error-text", "This book's file could not be read. Import it again.")
            val () = ui_show("error-banner", true)
          in $P.ret<int>(r) end
          else $P.and_then<int><int>(annot_load(h1, h2), lam(_) => reader_goto(ch, pg, anchor))))
    end

(* The view kept by the last run: its book opened again, on its page,
   when it is still on a shelf it is read from; else the library *)
fn _view_restore (): $P.promise(int, $P.Chained) = let
  val @(kf, kb) = $A.freeze<byte>(_view_key())
  val p = $IDB.idb_get(kb, 4)
  val () = release_bytes(kf, kb)
in
  $P.and_then<Int><int>($P.vow(p), lam(h) => let
    val key = (case+ take_blob(h) of
      | ~NoBlobBytes() => ~1
      | ~BlobBytes(b, n) =>
        if n < 4 then let val () = $A.free<byte>(b) in ~1 end
        else let val k = _i32at(b, 0) val () = $A.free<byte>(b) in k end): Int
    val i = (if key < 0 then ~1 else lib_index_of_key(key)): [r:int | r >= ~1] int r
    val readable = (if i < 0 then false else (case+ lib_nums(i) of
      | ~$R.none() => false
      | ~$R.some(x) => x.shelf < 2)): bool
  in
    if readable then let val () = _open_book(i) in $P.ret<int>(0) end
    else let val () = _show_library() in $P.ret<int>(0) end
  end)
end

(* ============================================================
   The library: menus, info, shelves
   ============================================================ *)

fn _save_render (): void = let
  val () = lib_save()
in lib_render() end

(* Sets book i's shelf *)
fn _set_shelf {i:int} (i: int i, shelf: Int): void = lib_set_shelf(i, shelf)

(* Deletes the stored data under key letter c of book (h1, h2) *)
fn _idb_del {c:nat | c < 256} (c: int c, h1: int, h2: int): void = let
  val k = lib_key(c, h1, h2)
  val @(f, b) = $A.freeze<byte>(k)
  val () = $P.discard<Int>($IDB.idb_delete(b, 15))
in release_bytes(f, b) end

(* Archives book i: its record is kept and its file deleted. The file
   goes only when the Undo offer does: until then Undo puts the book
   back where it was, file and all *)
fn _archive {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val key = x.key
      val was = x.shelf
      val h1 = x.h1
      val h2 = x.h2
      val () = _set_shelf(i, 2)
    in
      undo_offer("Archived", lam () => let
          val j = lib_index_of_key(key)
        in if j >= 0 then _set_shelf(j, was) else () end,
        (* the file goes only if the book is still archived (it may have
           been restored meanwhile, by importing it again) *)
        lam () => let
          val j = lib_index_of_key(key)
        in
          if j < 0 then ()
          else (case+ lib_nums(j) of
            | ~$R.none() => ()
            | ~$R.some(y) =>
              if y.shelf = 2 then let
                val () = _idb_del(98, h1, h2)
              in if open_key_get() = key then open_key_set(0) else () end
              else ())
        end)
    end

(* Hides or unhides book i, offering Undo *)
fn _hide_toggle {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val key = x.key
      val was = x.shelf
      val () = _set_shelf(i, (if was = 1 then 0 else 1))
    in
      undo_offer((if was = 1 then "Unhidden" else "Hidden"): [k:pos | k < 256] string k, lam () => let
          val j = lib_index_of_key(key)
        in if j >= 0 then _set_shelf(j, was) else () end,
        lam () => ())
    end


(* The book actions' labels (in the book menu or the info view) for a
   book on shelf s: in the Trash, Restore only (a book leaves the Trash
   for good only when it is emptied); elsewhere Hide or Unhide, Archive
   or Restore, and Move to Trash *)
fn _shelf_labels {n1,n2,n3:pos | n1 < 256; n2 < 256; n3 < 256}
  (hide: string n1, arch: string n2, del: string n3, s: Int): void =
  if s = 3 then let
    val () = ui_text(hide, "Restore")
    val () = ui_show(arch, false)
  in ui_show(del, false) end
  else let
    val () = (if s = 1 then ui_text(hide, "Unhide") else ui_text(hide, "Hide"))
    val () = ui_show(arch, true)
    val () = (if s = 2 then ui_text(arch, "Restore") else ui_text(arch, "Archive"))
  in ui_show(del, true) end

(* The book menu for book i, its items as its shelf asks *)
fn _menu_open {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val () = !_menu_idx := i
      val () = _shelf_labels("card-menu-hide", "card-menu-archive", "card-menu-trash", x.shelf)
      val () = layer_open(LBookMenu())
    in ui_focus("card-menu-info") end

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
      val () = ui_text_buf("book-info-title", t, tn)
      val @(a, an) = lib_text(i, 1)
      val () = ui_text_buf("book-info-author", a, an)
      (* progress: "N% · chapter C of T" *)
      val b = $A.alloc<byte>(64)
      val off = _progress_text(b, x)
      val () = ui_text_buf("info-progress", b, off)
      val d = $A.alloc<byte>(32)
      val dk = date_text(d, x.added)
      val () = ui_text_buf("info-added", d, dk)
      val () = (if x.opened > 0 then let
          val d = $A.alloc<byte>(32)
          val dk = date_text(d, x.opened)
        in ui_text_buf("info-last-read", d, dk) end
        else ui_text("info-last-read", "Never"))
      val z = $A.alloc<byte>(32)
      val zk = size_text(z, x.fsz)
      val () = ui_text_buf("info-size", z, zk)
      val () = _shelf_labels("book-info-hide", "book-info-archive", "book-info-trash", x.shelf)
      val () = ui_attr("book-info-cover", ASrc, "data:,")
      val () = (if x.cover > 0 then lib_show_cover_in("book-info-cover", x.h1, x.h2, x.cover) else ())
      (* a book without a cover shows none, not a broken image *)
      val () = ui_show("book-info-cover", x.cover > 0)
      val () = lib_a11y_show(x.h1, x.h2)
      val () = layer_open(LBookInfo())
    in ui_focus("book-info-back") end

(* A book menu or info view action on book i: 1 hide, unhide or (from
   the Trash) restore; 2 archive, or say how to restore; 3 move to the
   Trash *)
fn _book_action {i:int} (i: int i, act: int): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) =>
    if act = 1 then
      (if x.shelf = 3 then _set_shelf(i, 0) else _hide_toggle(i))
    else if act = 2 then
      (if x.shelf = 2 then let
         val () = modal_inform("Restore")
       in modal_text_lit("To restore this book, import its file again.") end
       else if x.shelf = 3 then ()
       else _archive(i))
    else if x.shelf = 3 then ()
    else let
      val () = layer_close(LBookInfo())
    in lib_trash(i) end

(* ============================================================
   Settings
   ============================================================ *)

fn _settings_changed (): void = let
  val () = set_apply(lib_state_get())
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

(* The selected text, to the clipboard *)
(* Look up: the selection's first 64 bytes (cut where a character
   begins), trimmed, as a Wiktionary search in the book's language:
   "https://fr.wiktionary.org/wiki/Special:Search?search=..." *)
fn _hexdig (v: int): int = if v < 10 then 48 + v else 55 + v

(* out[p, r) := a[i, k) percent-encoded (letters, digits and -_.~ as
   they are, a space as %20) *)
fun _pct {l,lo:agz}{n:pos}{k:nat | k <= n}{i:nat | i <= k}{p:nat | p + 3 * (k - i) <= 256} .<k - i>.
  (a: !$A.arr(byte, l, n), k: int k, i: int i, out: !$A.arr(byte, lo, 256), p: int p): [r:nat | r <= 256] int r =
  if i >= k then p
  else let
    val c = byte2int0($A.get<byte>(a, i))
    val plain = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
      || c = 45 || c = 95 || c = 46 || c = 126
  in
    if plain then let
      val () = $A.set<byte>(out, p, $A.int2byte($AR.low_byte(c)))
    in _pct(a, k, i + 1, out, p + 1) end
    else let
      val b = (if c >= 0 then c else c + 256): int
      val () = $A.set<byte>(out, p, $A.int2byte(37))
      val () = $A.set<byte>(out, p + 1, $A.int2byte($AR.low_byte(_hexdig(b / 16))))
      val () = $A.set<byte>(out, p + 2, $A.int2byte($AR.low_byte(_hexdig(b - (b / 16) * 16))))
    in _pct(a, k, i + 1, out, p + 3) end
  end

fun _ws_start {l:agz}{n:pos}{k:nat | k <= n}{i:nat | i <= k} .<k - i>.
  (a: !$A.arr(byte, l, n), k: int k, i: int i): [j:nat | j <= k] int j =
  if i >= k then i
  else let val c = byte2int0($A.get<byte>(a, i)) in
    if c = 32 || c = 9 || c = 10 || c = 13 then _ws_start(a, k, i + 1) else i
  end

fun _ws_end {l:agz}{n:pos}{s:nat}{k:nat | s <= k; k <= n} .<k - s>.
  (a: !$A.arr(byte, l, n), s: int s, k: int k): [e:nat | s <= e; e <= k] int e =
  if k <= s then k
  else let val c = byte2int0($A.get<byte>(a, k - 1)) in
    if c = 32 || c = 9 || c = 10 || c = 13 then _ws_end(a, s, k - 1) else k
  end

(* The first j <= e (from s) where a character begins: a byte that is
   not 0x80 to 0xBF *)
fun _char_start {l:agz}{n:pos}{s,e:nat | s <= e; e < n} .<e - s>.
  (a: !$A.arr(byte, l, n), s: int s, e: int e): [j:nat | s <= j; j <= e] int j =
  if e <= s then e
  else let val c = byte2int0($A.get<byte>(a, e)) in
    if c >= 128 && c < 192 then _char_start(a, s, e - 1) else e
  end

(* The end of a[s, e), cut to at most 64 bytes where a character begins *)
fn _cut {l:agz}{n:pos}{s,e:nat | s <= e; e <= n}
  (a: !$A.arr(byte, l, n), s: int s, e: int e): [j:nat | s <= j; j <= e; j - s <= 64] int j =
  if e - s <= 64 then e
  else _char_start(a, s, s + 64)

(* w[0, e - s) := a[s, e), at most 64 bytes *)
fun _copy_bytes {l,lw:agz}{n:pos}{s,e:nat | s <= e; e <= n; e - s <= 64}{j:nat | j <= e - s} .<e - s - j>.
  (a: !$A.arr(byte, l, n), s: int s, e: int e, w: !$A.arr(byte, lw, 65), j: int j): void =
  if s + j >= e then ()
  else let
    val () = $A.set<byte>(w, j, $A.get<byte>(a, s + j))
  in _copy_bytes(a, s, e, w, j + 1) end

fn _copy_word {l,lw:agz}{n:pos}{s,e:nat | s <= e; e <= n}
  (a: !$A.arr(byte, l, n), s: int s, e: int e, w: !$A.arr(byte, lw, 65)): [m:nat | m <= 64] int m =
  if e - s > 64 then 0
  else let val () = _copy_bytes(a, s, e, w, 0) in e - s end

(* out[p, p + sl) := s *)
fun _put_lit_at {lo:agz}{sl:nat}{p:nat | p + sl <= 256}{i:nat | i <= sl} .<sl - i>.
  (out: !$A.arr(byte, lo, 256), p: int p, s: string sl, sl: int sl, i: int i): void =
  if i >= sl then ()
  else let
    val () = $A.set<byte>(out, p + i, $A.int2byte($AR.byte_of_char(string_get_at(s, i))))
  in _put_lit_at(out, p, s, sl, i + 1) end

fn _put_lit {lo:agz}{sl:nat}{p:nat | p + sl <= 256}
  (out: !$A.arr(byte, lo, 256), p: int p, s: string sl): int(p + sl) = let
  val sl = g1u2i(string1_length(s))
  val () = _put_lit_at(out, p, s, sl, 0)
in p + sl end

fn _put_arr {lo,la:agz}{p:nat | p + 3 <= 256}{k:pos | k <= 3}
  (out: !$A.arr(byte, lo, 256), p: int p, a: !$A.arr(byte, la, 3), k: int k): int(p + k) = let
  val () = $A.set<byte>(out, p, $A.get<byte>(a, 0))
  val () = $A.set<byte>(out, p + 1, $A.get<byte>(a, 1))
  val () = (if k = 3 then $A.set<byte>(out, p + 2, $A.get<byte>(a, 2)) else ())
in p + k end

fn _lookup_update (): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(bl) => let
      val n = $DC.blob_len(bl)
    in
      if n <= 0 then $DC.blob_free(bl)
      else if n > 4096 then $DC.blob_free(bl)
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(bl, 0, a, n)
        val () = $DC.blob_free(bl)
        val s0 = _ws_start(a, n, 0)
        val e0 = _ws_end(a, s0, n)
        val e1 = _cut(a, s0, e0)
        val w = $A.alloc<byte>(65)
        val m = _copy_word(a, s0, e1, w)
        val () = $A.free<byte>(a)
        val out = $A.alloc<byte>(256)
        val p = _put_lit(out, 0, "https://")
        val @(lg, lk) = reader_lang_code()
        val p = _put_arr(out, p, lg, lk)
        val () = $A.free<byte>(lg)
        val p = _put_lit(out, p, ".wiktionary.org/wiki/Special:Search?search=")
        val q = _pct(w, m, 0, out, p)
        val () = $A.free<byte>(w)
      in if q > 0 then ui_https_href("selection-lookup", out, q) else $A.free<byte>(out) end
    end

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
      in release_bytes(f, bb) end
    end

(* Exports the open book's annotations: downloaded, or to be shared
   (the page's script shares them once this click's listener is done) *)
fn _export (share: bool): void = let
  val i = lib_index_of_key(open_key_get())
  val @(t, tn) = lib_text(i, 0)
  val @(a, an) = lib_text(i, 1)
in annot_export(t, tn, a, an, share) end

(* Goes to annotation i, remembering where the reader was *)
fn _annot_go (i: int): void = let
  val @(ch, pg, sn) = annot_dest(i)
in if ch >= 0 then reader_jump_to(ch, pg, sn) else () end

(* A factory reset: every book moves to the Trash (where it can still be
   restored until the Trash is emptied) and the settings go back to
   their defaults; Undo puts both back *)
fn _factory_reset (): void = let
  val back_books = lib_trash_all()
  val back_settings = set_reset_undoable(lam () => let
      val () = set_sliders()
    in _settings_changed() end)
in
  undo_offer("Library moved to the Trash, settings reset", lam () => let
      val () = back_books()
    in back_settings() end, lam () => ())
end

(* The collections panel for book i, its toggles pressed as the book's
   collections are *)
fn _collections_open {i:int} (i: int i): void = let
  val () = !_menu_idx := i
  val () = lib_coll_panel(i)
  val () = layer_open(LCollections())
in if lib_coll_count() > 0 then ui_focus("collection-put0") else ui_focus("collections-new") end

(* Puts book i in collection j, or takes it out: its toggle and the
   library follow *)
fn _collection_put {i:int}{j:int} (i: int i, j: int j): void =
  if j < 0 then ()
  else let
    val () = lib_coll_toggle(i, j)
    val @(bi, bl) = nid_make("collection-put", j)
    val () = (if lib_coll_has(i, j) then ui_attr_n(bi, bl, APressed, "true") else ui_attr_n(bi, bl, APressed, "false"))
  in lib_render() end

(* A new collection, named in the dialog, with book i in it *)
fn _collection_new {i:int} (i: int i): void = let
  val () = modal_open(QNewCollection(), "New collection", lam () => let
      val @(b, k) = modal_name_read()
      val j = lib_coll_add(b, k)
      val () = (if j >= 0 then lib_coll_toggle(i, j) else ())
      val () = lib_coll_panel(i)
    in lib_render() end, lam () => ())
in modal_name_field() end

(* The collection shown, named again in the dialog *)
fn _collection_rename (): void = let
  val j = lib_coll_shown()
in
  if j < 0 then ()
  else let
    val () = modal_open(QRenameCollection(), "Rename collection", lam () => let
        val @(b, k) = modal_name_read()
      in lib_coll_rename(j, b, k) end, lam () => ())
    val () = modal_name_field()
  in lib_coll_name_show(j) end
end

fn _wire_library {n:nat} (r: regs(n)): regs(n + 20) = let
  (* import *)
  val r = RCons(r, OnEl("import-button"), "change", lam(_) => let val () = import_picked() in 0 end)
  (* drag and drop *)
  val r = RCons(r, OnEl("library"), "dragover", lam(_) => let
      val () = $EV.prevent_default()
    in let val () = ui_attr("library", AClass, "lib drag") in 0 end end)
  val r = RCons(r, OnEl("library"), "dragleave", lam(_) => let
      val () = ui_attr("library", AClass, "lib")
    in 0 end)
  val r = RCons(r, OnEl("library"), "drop", lam(_) => let
      val () = $EV.prevent_default()
      val () = ui_attr("library", AClass, "lib")
      val () = import_dropped()
    in 0 end)
  (* the cards: open, and the book menu *)
  val r = RCons(r, OnEl("book-list"), "click", lam(h) => let
      val t = _target(h)
      val i = _row_of(t, "book")
      val m = _row_of(t, "book-more")
      val () = _target_free(t)
    in
      if i >= 0 then let val () = _open_book(i) in 0 end
      else if m >= 0 then let val () = _menu_open(m) in 0 end
      else 0
    end)
  (* the view: which books, as a list or a grid; kept with the settings *)
  val r = RCons(r, OnEl("library-view"), "click", lam(h) => let
      val t = _target(h)
      val f = (if _is(t, "filter-books-all") then 0 else if _is(t, "filter-unread") then 1
        else if _is(t, "filter-reading") then 2 else if _is(t, "filter-finished") then 3 else ~1): int
      val g = (if _is(t, "view-list") then 0 else if _is(t, "view-grid") then 1 else ~1): int
      (* the collections: which is shown, and the one shown renamed or
         deleted *)
      val cj = _row_of(t, "collection")
      val call = _is(t, "collection-all")
      val crename = _is(t, "collection-rename")
      val cdelete = _is(t, "collection-delete")
      val () = _target_free(t)
      val () = (if call then lib_coll_show(~1) else if cj >= 0 then lib_coll_show(cj)
        else if crename then _collection_rename() else if cdelete then lib_coll_delete(lib_coll_shown()) else ())
      val () = (if f >= 0 then lib_filter_set(f) else if g >= 0 then lib_grid_set(g) else ())
    in if f >= 0 || g >= 0 then let val () = set_save(lib_state_get()) in 0 end else 0 end)
  (* the book to continue: opened *)
  val r = RCons(r, OnEl("continue-list"), "click", lam(h) => let
      val t = _target(h)
      val i = _row_of(t, "continue")
      val () = _target_free(t)
    in if i >= 0 then let val () = _open_book(i) in 0 end else 0 end)
  val r = RCons(r, OnEl("book-list"), "contextmenu", lam(h) => let
      val () = $EV.prevent_default()
      val i = _target_num(h, "book")
    in if i >= 0 then let val () = _menu_open(i) in 0 end else 0 end)
  val r = RCons(r, OnEl("card-menu"), "click", lam(h) => let
      val t = _target(h)
      val i = !_menu_idx
      val () = layer_close(LBookMenu())
      val () = (if i >= 0 then
          (if _is(t, "card-menu-info") then _info_open(i)
           else if _is(t, "card-menu-collections") then _collections_open(i)
           else if _is(t, "card-menu-hide") then _book_action(i, 1)
           else if _is(t, "card-menu-archive") then _book_action(i, 2)
           else if _is(t, "card-menu-trash") then _book_action(i, 3)
           else ()) else ())
    in let val () = _target_free(t) in 0 end end)
  (* a book's collections: each toggled, a new one, or done (or a
     click outside) *)
  val r = RCons(r, OnEl("collections-menu"), "click", lam(h) => let
      val t = _target(h)
      val i = !_menu_idx
      val j = _row_of(t, "collection-put")
      val made = _is(t, "collections-new")
      val done = (if _is(t, "collections-done") then true else _is(t, "collections-menu")): bool
      val () = _target_free(t)
      val () = (if i < 0 then ()
        else if j >= 0 then _collection_put(i, j)
        else if made then _collection_new(i)
        else if done then layer_close(LCollections())
        else ())
    in 0 end)
  (* the info view *)
  val r = RCons(r, OnEl("book-info"), "click", lam(h) => let
      val t = _target(h)
      val i = !_menu_idx
      val () = (if _is(t, "book-info-back") then layer_close(LBookInfo())
        else if i < 0 then ()
        else if _is(t, "book-info-hide") then let val () = layer_close(LBookInfo()) in _book_action(i, 1) end
        else if _is(t, "book-info-archive") then let val () = layer_close(LBookInfo()) in _book_action(i, 2) end
        else if _is(t, "book-info-trash") then _book_action(i, 3)
        else ())
    in let val () = _target_free(t) in 0 end end)
  (* sort and shelf *)
  val r = RCons(r, OnEl("sort-button"), "click", lam(_) => let
      val o = lib_sort_get()
      val o = (if o >= 4 then 0 else o + 1): int
      val () = lib_sort(o)
      val () = lib_sort_label(o)
      val () = set_apply(lib_state_get())
    in let val () = lib_render() in 0 end end)
  val r = RCons(r, OnEl("shelf-button"), "click", lam(_) => let
      val s = lib_shelf_get()
      val () = lib_shelf_set((if s >= 3 then 0 else s + 1): int)
    in let val () = lib_render() in 0 end end)
  (* search *)
  (* the field is made again to be cleared: its events are taken on
     its box *)
  val r = RCons(r, OnEl("library-search-box"), "input", lam(h) => let
      val @(q, n) = _input_text(h)
      val () = ui_show("library-search-clear", n > 0)
      val () = lib_query_set(q, n)
    in let val () = lib_render() in 0 end end)
  val r = RCons(r, OnEl("library-search-box"), "click", lam(h) => let
      val t = _target(h)
      val clear = _is(t, "library-search-clear")
      val () = _target_free(t)
    in
      if clear then let
        val () = ui_clear("library-search-box")
        val () = ui_field("library-search-box", "library-search", FSearch, "search", "Search the library")
        val () = ui_icon_btn("library-search-box", "library-search-clear", "ibtn sclear", IcClose, "Clear search")
        val () = ui_show("library-search-clear", false)
        val () = lib_query_set($A.alloc<byte>(1), 0)
        val () = lib_render()
      in let val () = ui_focus("library-search") in 0 end end
      else 0
    end)
  (* a backup picked to restore *)
  val r = RCons(r, OnEl("menu-import-backup"), "change", lam(_) => let
      val () = layer_close(LLibraryMenu())
      val () = backup_import()
    in 0 end)
  (* the error banner *)
  val r = RCons(r, OnEl("error-dismiss"), "click", lam(_) => let val () = ui_show("error-banner", false) in 0 end)
  val r = RCons(r, OnEl("install-hint-dismiss"), "click", lam(_) => let val () = lib_install_hint_dismiss() in 0 end)
  (* the library menu *)
  val r = RCons(r, OnEl("library-menu-button"), "click", lam(_) => let
      val () = layer_open(LLibraryMenu())
    in let val () = ui_focus("menu-export-backup") in 0 end end)
  val r = RCons(r, OnEl("library-menu"), "click", lam(h) => let
      val t = _target(h)
      val () = (case+ _harm_clicked(t) of
        | ~Some_vt(h) => let
            val () = layer_close(LLibraryMenu())
          in lib_ask_harm(h, lam () => _save_render()) end
        | ~None_vt() =>
        if _is(t, "menu-factory-reset") then let
          val () = layer_close(LLibraryMenu())
        in _factory_reset() end
        else if _is(t, "menu-export-backup") then let
          val () = layer_close(LLibraryMenu())
        in backup_export() end
        (* the page's script asks the browser to install the app *)
        else if _is(t, "menu-install") then layer_close(LLibraryMenu())
        else if _is(t, "menu-storage-kept") then let
          val () = layer_close(LLibraryMenu())
          val () = modal_inform("Your books are kept")
        in modal_text_lit("This browser keeps the books you import until you remove them.") end
        else if _is(t, "menu-storage-at-risk") then let
          val () = layer_close(LLibraryMenu())
          val () = modal_inform("Your books may be cleared")
        in modal_text_lit("This browser may clear what Quire keeps when it runs short of space. Installing Quire, or reading it more often, makes the browser more likely to keep it. Keep your EPUB files: a backup holds your places, notes and settings, not the books.") end
        else if _is(t, "menu-close") then layer_close(LLibraryMenu())
        else if _is(t, "library-menu") then layer_close(LLibraryMenu())
        else ())
    in let val () = _target_free(t) in 0 end end)
in r end

fn _wire_settings {n:nat} (r: regs(n)): regs(n + 8) = let
  val r = RCons(r, OnEl("typography-button"), "click", lam(_) => let
      val () = layer_open(LTypography())
    in let val () = ui_focus("typography-close") in 0 end end)
  val r = RCons(r, OnEl("typography-panel"), "click", lam(h) => let
      val t = _target(h)
      val changed = (if _is(t, "font-literata") then let val () = set_font_set(0) in true end
        else if _is(t, "font-inter") then let val () = set_font_set(1) in true end
        else if _is(t, "font-book") then let val () = set_font_set(2) in true end
        else if _is(t, "font-atkinson") then let val () = set_font_set(3) in true end
        else if _is(t, "theme-auto") then let val () = set_theme_set(0) in true end
        else if _is(t, "theme-light") then let val () = set_theme_set(1) in true end
        else if _is(t, "theme-sepia") then let val () = set_theme_set(2) in true end
        else if _is(t, "theme-dark") then let val () = set_theme_set(3) in true end
        else if _is(t, "theme-night") then let val () = set_theme_set(4) in true end
        else if _is(t, "theme-grey") then let val () = set_theme_set(5) in true end
        else if _is(t, "layout-pages") then let val () = set_flow_set(0) in true end
        else if _is(t, "layout-scroll") then let val () = set_flow_set(1) in true end
        else if _is(t, "columns-auto") then let val () = set_cols_set(0) in true end
        else if _is(t, "columns-one") then let val () = set_cols_set(1) in true end
        else if _is(t, "columns-two") then let val () = set_cols_set(2) in true end
        else if _is(t, "align-ragged") then let val () = set_align_set(0) in true end
        else if _is(t, "align-justified") then let val () = set_align_set(1) in true end
        else if _is(t, "hyphens-off") then let val () = set_hyph_set(0) in true end
        else if _is(t, "hyphens-on") then let val () = set_hyph_set(1) in true end
        else if _is(t, "dim-off") then let val () = set_dim_set(0) in true end
        else if _is(t, "dim-on") then let val () = set_dim_set(1) in true end
        else if _is(t, "taps-sides") then let val () = set_taps_set(0) in true end
        else if _is(t, "taps-forward") then let val () = set_taps_set(1) in true end
        else if _is(t, "taps-one-hand") then let val () = set_taps_set(2) in true end
        else if _is(t, "volume-keys-off") then let val () = set_vol_set(0) in true end
        else if _is(t, "volume-keys-turn") then let val () = set_vol_set(1) in true end
        else if _is(t, "typography-reset") then let
            val () = set_reset(lam () => let
                val () = set_sliders()
              in _settings_changed() end)
          in false end
        else false): bool
      val close = _is(t, "typography-close")
      val () = _target_free(t)
      val () = (if close then layer_close(LTypography()) else ())
    in if changed then let val () = _settings_changed() in 0 end else 0 end)
  val r = RCons(r, OnEl("size-row"), "input", lam(h) => let
      val () = set_size_set(_clamp(_input_num(h), 12, 32))
    in let val () = _settings_changed() in 0 end end)
  val r = RCons(r, OnEl("line-height-row"), "input", lam(h) => let
      val () = set_lh_set(_clamp(_input_num(h), 12, 24))
    in let val () = _settings_changed() in 0 end end)
  val r = RCons(r, OnEl("margins-row"), "input", lam(h) => let
      val () = set_margin_set(_clamp(_input_num(h), 0, 4))
    in let val () = _settings_changed() in 0 end end)
  val r = RCons(r, OnEl("paragraph-row"), "input", lam(h) => let
      val () = set_ps_set(_clamp(_input_num(h), 0, 20))
    in let val () = _settings_changed() in 0 end end)
  val r = RCons(r, OnEl("letter-row"), "input", lam(h) => let
      val () = set_ls_set(_clamp(_input_num(h), 0, 12))
    in let val () = _settings_changed() in 0 end end)
  val r = RCons(r, OnEl("word-row"), "input", lam(h) => let
      val () = set_ws_set(_clamp(_input_num(h), 0, 16))
    in let val () = _settings_changed() in 0 end end)
in r end

(* ============================================================
   Search
   ============================================================ *)

(* Whether an element is shown *)
fn _shown {ni:pos | ni < 256} (id: string ni): bool = let
  val () = ui_measure(id)
in $DR.get_measure_w() > 0 end

(* The search field, made again holding a[0, k) *)
fn _search_value {l:agz}{n:pos}{k:nat | k <= n; k < 65536} (a: $A.arr(byte, l, n), k: int k): void =
  if k > 0 then ui_attr_buf("search-field", AValue, a, k) else $A.free<byte>(a)

fn _search_field {l:agz}{n:pos}{k:nat | k <= n; k < 65536} (a: $A.arr(byte, l, n), k: int k): void = let
  val () = ui_clear("search-header")
  val () = ui_field("search-header", "search-field", FSearch, "search", "Search in book")
  val () = _search_value(a, k)
in ui_icon_btn("search-header", "search-close", "ibtn", IcClose, "Close search") end

fn _search_open (): void = let
  val () = layer_open(LSearch())
in ui_focus("search-field") end

(* Ends the search: the reader goes back to where it was before it
   jumped to a hit *)
fn _search_end (): void = let
  val () = layer_close(LSearch())
  val () = reader_search_close()
  (* the next search starts afresh: an empty field, no old results *)
  val () = _search_field($A.alloc<byte>(1), 0)
  val () = ui_clear("search-results")
  val () = ui_clear("search-status")
in ui_focus("page") end

(* Searches for the field's text *)
fn _search_run (): void = let
  val a = $A.alloc<byte>(12)
  val () = $A.write_text(a, 0, $A.text_lit("search-field"), 12)
  val @(f, b) = $A.freeze<byte>(a)
  val r = $DR.read_input_value(b, 12)
  val () = release_bytes(f, b)
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
        val () = layer_open(LSearch())
        val () = !_search_tick := !_search_tick + 1
      in reader_search(c, n) end
    end

(* Closes the reader's panels; whether one was open *)
fn _panels_close (): bool = layer_close_all()

(* A page turn: the bars hide *)
fn _next (): void = let
  val () = _hint_hide()
  val () = (if !_chrome then _chrome_set(false) else ())
in page_next() end

fn _prev (): void = let
  val () = _hint_hide()
  val () = (if !_chrome then _chrome_set(false) else ())
in page_prev() end

(* The page to the left and to the right: back and on, or the other way
   in a book read right to left *)
fn _left (): void = if reader_rtl() then _next() else _prev()
fn _right (): void = if reader_rtl() then _prev() else _next()

(* Whether x is between the sides' zones: in the middle half of the
   page *)
fn _in_middle (x: Int): bool = let
  val () = ui_measure("page")
  val cx = $DR.get_measure_x()
  val cw = $DR.get_measure_w()
in
  if cw <= 0 then false
  else if x < cx + cw / 4 then false
  else x <= cx + cw - cw / 4
end

(* What a tap at x, y on the page does, by the setting (settings.bats):
   sides, the left quarter back, the right quarter on, between them the
   bars shown or hidden; forward, the top eighth the bars, the left
   quarter back, anywhere else on; one hand, the top third back, the
   bottom third on, between them the bars. Back and on are the book's:
   a book read right to left turns the other way *)
fn _zone_click (x: Int, y: Int): void = let
  val () = ui_measure("page")
  val cx = $DR.get_measure_x()
  val cy = $DR.get_measure_y()
  val cw = $DR.get_measure_w()
  val ch = $DR.get_measure_h()
  val z = set_taps_get()
in
  if cw <= 0 then ()
  else if z = 1 then
    (if (if ch > 0 then y < cy + ch / 8 else false) then _chrome_set(~(!_chrome))
     else if x < cx + cw / 4 then _left()
     else _right())
  else if z = 2 then
    (if ch <= 0 then _chrome_set(~(!_chrome))
     else if y < cy + ch / 3 then _prev()
     else if y > cy + ch - ch / 3 then _next()
     else _chrome_set(~(!_chrome)))
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
  (* the keys that turn the page are the reader's alone: scrolled, the
     browser would also scroll the focused page by them *)
  if _key_is(b, n, "ArrowRight") then _right()
  else if _key_is(b, n, "PageDown") then let val () = $EV.prevent_default() in _next() end
  else if _key_is(b, n, "ArrowLeft") then _left()
  else if _key_is(b, n, "PageUp") then let val () = $EV.prevent_default() in _prev() end
  else if _key_is(b, n, " ") then let val () = $EV.prevent_default() in (if shift then _prev() else _next()) end
  (* the volume keys, when they turn the page and the browser gives them
     to the page: down on, up back, and the volume left as it is *)
  else if (if set_vol_get() = 1 then _key_is(b, n, "AudioVolumeDown") else false) then let
    val () = $EV.prevent_default()
  in _next() end
  else if (if set_vol_get() = 1 then _key_is(b, n, "AudioVolumeUp") else false) then let
    val () = $EV.prevent_default()
  in _prev() end
  else if _key_is(b, n, "Home") then let val () = $EV.prevent_default() in reader_page(0) end
  else if _key_is(b, n, "End") then let val () = $EV.prevent_default() in reader_page(1000000) end
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
  else if (if _key_is(b, n, "Enter") then !_focus_link >= 0 else false) then let
    (* the Enter is the link's: a note opened over the page takes the
       focus to its Close, which the same Enter would otherwise press *)
    val () = $EV.prevent_default()
  in if reader_link_at(!_focus_link) then () else () end
  else if _key_is(b, n, "Escape") then
    (if _panels_close() then ui_focus("page")
     else if _shown("search-nav") then _search_end()
     else if !_chrome then _chrome_set(false) else _show_library())
  else ()
end

(* Escape: the dialog is answered with its first button, or else the
   overlay opened last closes (layer_escape); true when one did. After
   a reader panel, the page has the focus again; after the search panel,
   so does the page, and a search with no hits ends *)
fn _escape_overlay (): bool =
  if modal_open_now() then let val () = modal_dismiss() in true end
  else case+ layer_escape() of
  | NothingOpen() => false
  | Escaped(LSearch()) => let
      val () = (if _shown("search-nav") then ui_focus("page") else _search_end())
    in true end
  | Escaped(LContents()) => let val () = ui_focus("page") in true end
  | Escaped(LTypography()) => let val () = ui_focus("page") in true end
  | Escaped(LAnnotations()) => let val () = ui_focus("page") in true end
  | Escaped(LNote()) => let val () = ui_focus("page") in true end
  | Escaped(LImage()) => let val () = ui_focus("page") in true end
  | Escaped(_) => true

(* A key while the search panel is open: Enter goes to the next hit
   (Shift+Enter the one before), Escape closes the panel *)
fn _search_key {l:agz}{n:nat} (b: !$A.arr(byte, l, n), n: int n): void = let
  val shift = (if n >= 2 then $AR.band_g1($AR.low_byte(byte2int0($A.get<byte>(b, n - 1))), 1) = 1 else false): bool
in
  if _key_is(b, n, "Enter") then let
      val () = reader_search_step(if shift then ~1 else 1)
    in if _shown("search-nav") then let val () = layer_close(LSearch()) in ui_focus("page") end else () end
  else if _key_is(b, n, "Escape") then let
      val () = layer_close(LSearch())
    in if _shown("search-nav") then ui_focus("page") else _search_end() end
  else ()
end

(* The contents panel, open on its contents tab *)
fn _toc_open (): void = let
  val () = (case+ reading_get() of
    | @(_, _, c, tc) => toc_render((if c > 0 then c - 1 else 0), tc))
  val () = ui_attr("contents-tab", ASelected, "true")
  val () = ui_attr("bookmarks-tab", ASelected, "false")
  val () = ui_attr("pages-tab", ASelected, "false")
  val () = ui_show("contents-list", true)
  val () = ui_show("bookmarks-list", false)
  val () = ui_show("pages-list", false)
  (* the Pages tab only for a book that lists its print pages *)
  val () = ui_show("pages-tab", toc_pages_count() > 0)
  val () = layer_open(LContents())
in ui_focus("contents-close") end

(* The contents panel, open on its bookmarks tab *)
fn _bookmarks_open (): void = let
  val () = annot_render_bookmarks()
  val () = ui_attr("contents-tab", ASelected, "false")
  val () = ui_attr("bookmarks-tab", ASelected, "true")
  val () = ui_attr("pages-tab", ASelected, "false")
  val () = ui_show("contents-list", false)
  val () = ui_show("pages-list", false)
in ui_show("bookmarks-list", true) end

(* The contents panel, open on its print pages' tab *)
fn _pages_open (): void = let
  val () = toc_pages_render()
  val () = ui_attr("contents-tab", ASelected, "false")
  val () = ui_attr("bookmarks-tab", ASelected, "false")
  val () = ui_attr("pages-tab", ASelected, "true")
  val () = ui_show("contents-list", false)
  val () = ui_show("bookmarks-list", false)
in ui_show("pages-list", true) end

(* The page turn's region: .caf (page), region 1 *)
#define PAGE_REGION 1

(* A drag has ended: the click that follows it is not a tap. The flag
   drops once the click has had its turn *)
fn _drag_ended (): void = let
  val () = !_dragged := true
in $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(0)), lam(_) => let
    val () = !_dragged := false
  in $P.ret<int>(0) end)) end

(* The page turn's events: a pan moves the page with the finger, a
   commit turns it (a drag to the left shows the page to the right),
   a cancel puts it back *)
fun _on_gestures {n:nat} .<n>. (es: list_vt($GT.gevent, n)): void =
  case+ es of
  | ~list_vt_nil() => ()
  | ~list_vt_cons(e, rest) => let
      val () = (case+ e of
        | ~$GT.GPan(r, d) => if r = PAGE_REGION then reader_pan(d / 16) else ()
        | ~$GT.GCommit(r, dr) =>
          if r <> PAGE_REGION then ()
          else let
            val () = _drag_ended()
          in case+ dr of
            | $GP.DLeft() => _right()
            | $GP.DRight() => _left()
            | _ => reader_pan(0)
          end
        | ~$GT.GCancel(r, _) =>
          if r <> PAGE_REGION then ()
          else let val () = _drag_ended() in reader_pan(0) end
        | ~$GT.GLongPress(_, _, _) => ()
        | ~$GT.GPinch(_, _, _, _) => ()
        | ~$GT.GPinchEnd(_) => ()
        | ~$GT.GScrollEnd(_, _) => ()
        | ~$GT.GTransitionEnd(_) => ()
        | ~$GT.GTransitionCancel(_) => ())
    in _on_gestures(rest) end

(* A batch of pointer records from the shim, through the recognizer *)
fn _gesture_batch (h: $EV.event_payload): void =
  case+ take_blob(h) of
  | ~NoBlobBytes() => ()
  | ~BlobBytes(b, n) => let
      var c: gcell = GNone()
      val () = ref_exch_elt<gcell>(_gestures, c)
      val es = (case+ c of
        | @GSome(st) => let
            val es = $GD.gestures_feed(st, b, n)
            prval () = fold@(c)
          in es end
        | GNone() => list_vt_nil()): $GT.gevents
      val () = ref_exch_elt<gcell>(_gestures, c)
      val () = (case+ c of ~GNone() => () | ~GSome(st) => $GT.gestures_free(st))
      val () = $A.free<byte>(b)
    in if !_view = 1 then _on_gestures(es) else $GT.gevents_free(es) end

(* The recognizer, with the page turn's region: horizontal drags, by
   touch or pen only (a mouse drag over the page selects text) *)
fn _gestures_start (): void = let
  val st = $GT.gestures_new()
  val () = $GT.gestures_region(st, PAGE_REGION, ~1, page_turn_axes(), false, false, $GT.DevTouch())
  var c: gcell = GSome(st)
  val () = ref_exch_elt<gcell>(_gestures, c)
in case+ c of ~GNone() => () | ~GSome(old) => $GT.gestures_free(old) end

(* The page's scrolls, numbered, so only the last one's rest counts *)
val _scroll_gen = ref<int>(0)

fn _wire_toc {n:nat} (r: regs(n)): regs(n + 9) = let
  val r = RCons(r, OnEl("contents-button"), "click", lam(_) => let val () = _toc_open() in 0 end)
  val r = RCons(r, OnEl("contents-panel"), "click", lam(h) => let
      val t = _target(h)
      val row = _row_of(t, "toc-row")
      val bgo = _row_of(t, "bookmark-go")
      val bdl = _row_of(t, "bookmark-delete")
      val bnt = _row_of(t, "bookmark-edit")
      val pgo = _row_of(t, "page-row")
      val () = (if _is(t, "contents-close") then layer_close(LContents())
        else if _is(t, "contents-tab") then _toc_open()
        else if _is(t, "bookmarks-tab") then _bookmarks_open()
        else if _is(t, "pages-tab") then _pages_open()
        else if pgo >= 0 then let
          val () = layer_close(LContents())
        in reader_goto_page(pgo) end
        else if bgo >= 0 then let val () = layer_close(LContents()) in _annot_go(bgo) end
        else if bdl >= 0 then annot_delete_bookmark(bdl)
        else if bnt >= 0 then annot_ask_note(bnt, false)
        else if row >= 0 then let
          val () = layer_close(LContents())
        in reader_goto_entry(row) end
        else ())
      val () = _target_free(t)
    in 0 end)
  val r = RCons(r, OnEl("jump-back"), "click", lam(_) => let val () = reader_back() in 0 end)
  val r = RCons(r, OnEl("next-chapter"), "click", lam(_) => let val () = page_next() in 0 end)
  (* scrolled, the place follows the page, once it rests a moment *)
  val r = RCons(r, OnEl("page"), "scroll", lam(_) => let
      val () = !_scroll_gen := !_scroll_gen + 1
      val gen = !_scroll_gen
      val () = $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(150)), lam(_) => let
          val () = (if !_scroll_gen = gen then reader_scrolled() else ())
        in $P.ret<int>(0) end))
    in 0 end)
  (* the scrubber: a drag shows where it would go, letting go goes there *)
  val r = RCons(r, OnEl("scrubber-track"), "pointerdown", lam(h) => let
      val x = _event_x(h)
      val () = !_scrubbing := true
      val () = _chrome_set(true)
    in let val () = reader_scrub_preview(x) in 0 end end)
  val r = RCons(r, OnDocument(), "pointermove", lam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = _chrome_set(true)
      in let val () = reader_scrub_preview(x) in 0 end end
      else 0)
  val r = RCons(r, OnDocument(), "pointerup", lam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = !_scrubbing := false
      in let val () = reader_scrub_go(x) in 0 end end
      else 0)
  (* the app hidden (another tab, another app): where the reader is is
     stored *)
  val r = RCons(r, OnDocument(), "visibilitychange", lam(_) =>
      if !_view = 1 then let val () = reader_save() in 0 end else 0)
in r end

fn _wire_annotations {n:nat} (r: regs(n)): regs(n + 6) = let
  val r = RCons(r, OnEl("bookmark-button"), "click", lam(_) => let
      val () = annot_bookmark_toggle(reader_anchor())
    in 0 end)
  val r = RCons(r, OnDocument(), "selectionchange", lam(_) =>
      if !_view = 1 then let
        val sel = _has_selection()
        val () = ui_show("selection-toolbar", sel)
        val () = (if sel then _lookup_update() else ())
      in 0 end else 0)
  val r = RCons(r, OnEl("selection-toolbar"), "click", lam(h) => let
      val t = _target(h)
      val hl = _is(t, "selection-highlight")
      val orange = _is(t, "selection-orange")
      val under = _is(t, "selection-underline")
      val nt = _is(t, "selection-note")
      val cp = _is(t, "selection-copy")
      val sr = _is(t, "selection-search")
      val () = _target_free(t)
      val () = (if hl then let val _ = annot_highlight(0) in () end
        else if orange then let val _ = annot_highlight(1) in () end
        else if under then let val _ = annot_highlight(2) in () end
        else if nt then annot_ask_note(annot_highlight(0), true)
        else if cp then _copy_selection()
        else if sr then _search_selection()
        else ())
    in let val () = ui_show("selection-toolbar", false) in 0 end end)
  val r = RCons(r, OnEl("annotations-button"), "click", lam(_) => let
      val () = annot_render()
      val () = layer_open(LAnnotations())
    in let val () = ui_focus("annotations-close") in 0 end end)
  val r = RCons(r, OnEl("annotations-panel"), "click", lam(h) => let
      val t = _target(h)
      val go = _row_of(t, "highlight-go")
      val nt = _row_of(t, "highlight-edit")
      val dl = _row_of(t, "highlight-delete")
      val close = _is(t, "annotations-close")
      val ex = _is(t, "annotations-export")
      val sh = _is(t, "annotations-share")
      val filter = (if _is(t, "filter-all") then ~1 else if _is(t, "filter-yellow") then 0
        else if _is(t, "filter-orange") then 1 else if _is(t, "filter-underlined") then 2 else ~2): int
      val () = _target_free(t)
      val () = (if close then layer_close(LAnnotations())
        else if ex then _export(false)
        else if sh then _export(true)
        else if filter >= ~1 then annot_filter_set(filter)
        else if go >= 0 then let val () = layer_close(LAnnotations()) in _annot_go(go) end
        else if nt >= 0 then annot_ask_note(nt, false)
        else if dl >= 0 then annot_delete_highlight(dl)
        else ())
    in 0 end)
  (* a note opened over the page: gone to, or closed *)
  val r = RCons(r, OnEl("footnote"), "click", lam(h) => let
      val t = _target(h)
      val go = _is(t, "footnote-go")
      val close = _is(t, "footnote-close")
      val () = _target_free(t)
      val () = (if go then let
          val () = layer_close(LNote())
          val () = reader_note_go()
        in ui_focus("page") end
        else if close then let
          val () = layer_close(LNote())
        in ui_focus("page") end
        else ())
    in 0 end)
in r end

fn _wire_search {n:nat} (r: regs(n)): regs(n + 4) = let
  val r = RCons(r, OnEl("search-button"), "click", lam(_) => let
      val () = (if layer_is_open(LSearch()) then layer_close(LSearch()) else _search_open())
    in 0 end)
  (* the field is made again for a selection's search: its events are
     taken on the panel *)
  val r = RCons(r, OnEl("search-panel"), "input", lam(_) => let val () = _search_input() in 0 end)
  val r = RCons(r, OnEl("search-panel"), "click", lam(h) => let
      val t = _target(h)
      val go = _row_of(t, "search-hit")
      val close = _is(t, "search-close")
      val () = _target_free(t)
      val () = (if close then _search_end()
        else if go >= 0 then let
          val () = layer_close(LSearch())
        in reader_search_go(go) end
        else ())
    in 0 end)
  val r = RCons(r, OnEl("search-nav"), "click", lam(h) => let
      val t = _target(h)
      val pv = _is(t, "search-previous")
      val nx = _is(t, "search-next")
      val close = _is(t, "search-nav-close")
      val () = _target_free(t)
      val () = (if pv then reader_search_step(~1)
        else if nx then reader_search_step(1)
        else if close then _search_end()
        else ())
    in 0 end)
in r end

fn _wire_reader {n:nat} (r: regs(n)): regs(n + 13) = let
  val r = RCons(r, OnEl("back-to-library"), "click", lam(_) => let val () = _show_library() in 0 end)
  val r = RCons(r, OnEl("previous-page"), "click", lam(_) => let val () = _hint_hide() in let val () = page_prev() in 0 end end)
  val r = RCons(r, OnEl("next-page"), "click", lam(_) => let val () = _hint_hide() in let val () = page_next() in 0 end end)
  val r = RCons(r, OnEl("page"), "click", lam(h) => let
      val t = _target(h)
      val node = _row_of(t, "c")
      val x = _target_x(t)
      val y = _target_y(t)
      val () = _target_free(t)
    in
      if _has_selection() then 0
      else if !_dragged then 0
      else if (if node >= 0 then reader_link_at(node) else false) then 0
      (* with the sides' zones, a tap on an image between them shows it
         full screen, rather than the bars *)
      else if (if node >= 0 then (if set_taps_get() = 0 then (if _in_middle(x) then reader_image_at(node) else false) else false) else false) then 0
      else if x >= 0 then let val () = _zone_click(x, y) in 0 end else 0
    end)
  (* an image of the book, long-pressed (or right-clicked), is shown
     full screen *)
  val r = RCons(r, OnEl("page"), "contextmenu", lam(h) => let
      val t = _target(h)
      val node = _row_of(t, "c")
      val () = _target_free(t)
    in
      if node < 0 then 0
      else if reader_image_at(node) then let val () = $EV.prevent_default() in 0 end
      else 0
    end)
  val r = RCons(r, OnEl("image-viewer"), "click", lam(h) => let
      val t = _target(h)
      val close = _is(t, "image-close")
      val () = _target_free(t)
    in
      if close then let
        val () = layer_close(LImage())
      in let val () = ui_focus("page") in 0 end end
      else 0
    end)
  (* a link within the book, focused from the keyboard, is followed with
     Enter *)
  val r = RCons(r, OnEl("page"), "focusin", lam(h) => let
      val t = _target(h)
      val node = _row_of(t, "c")
      val () = _target_free(t)
      val () = !_focus_link := node
    in 0 end)
  val r = RCons(r, OnEl("page"), "focusout", lam(_) => let val () = !_focus_link := ~1 in 0 end)
  val r = RCons(r, OnDocument(), "keydown", lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(b, n) => let
          val esc = _key_is(b, n, "Escape")
          val () = (if (if esc then _escape_overlay() else false) then ()
            else if !_view <> 1 then ()
            else if _shown("dialog") then ()
            else if layer_is_open(LSearch()) then _search_key(b, n)
            else _reader_key(b, n))
          val () = $A.free<byte>(b)
        in 0 end)
  (* the wheel turns a page, then pauses a quarter second *)
  val r = RCons(r, OnEl("page"), "wheel", lam(h) =>
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
  (* a tap on the footer's readout shows the next, and keeps it *)
  val r = RCons(r, OnEl("footer-readout"), "click", lam(_) => let
      val () = reader_readout_next()
      val () = set_save(lib_state_get())
    in 0 end)
  (* pointer events for the gestures: a horizontal drag turns the page
     (the reader view is the stable root; the page is region 1) *)
  val r = RCons(r, OnGestures("reader"), "gestures", lam(h) => let
      val () = _gesture_batch(h)
    in 0 end)
  (* a resize lays the chapter out again, once it settles *)
  val r = RCons(r, OnWindow(), "resize", lam(_) => let
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
in r end

(* ============================================================
   Startup
   ============================================================ *)

implement main0 () = let
  val () = app_build()
  val () = _gestures_start()
  (* every listener, in one table: each one's id is its place in it *)
  val r = _wire_search(_wire_annotations(_wire_toc(_wire_reader(_wire_settings(undo_listen(modal_listen(_wire_library(RNil()))))))))
  (* files handed to the app from outside it (an Android intent) *)
  val r = RCons(r, OnExternalFiles(), "files", lam(h) => let
      val () = (if !_view = 1 then _show_library() else ())
      val () = import_external(h)
    in 0 end)
  val () = ui_listen_all(r)
  val () = $P.discard<int>(reader_speed_load())
  val () = _hint_load()
  val () = lib_install_hint_load()
  (* nothing is shown until the view kept by the last run is known: a
     reader who was in a book comes back to it, not to the library *)
  val () = ui_show("library", false)
  val p = $P.and_then<int><int>(set_load(), lam(st) => let
      val () = lib_sort_label($AR.band_int_int(st, 7))
    in
      $P.and_then<int><int>(lib_load(), lam(_) => let
        val () = lib_state_set(st)
        val () = lib_render()
      in _view_restore() end)
    end)
in $P.discard<int>(p) end
