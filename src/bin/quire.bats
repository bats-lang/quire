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
staload "stats.sats"
staload "dictionary.sats"
staload "catalogue.sats"
staload "catalogues.sats"
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
val _menu_index = ref<Int>(~1)
(* Whether the reader's bars are shown, and the latest hide timer's *)
val _chrome = ref<bool>(true)
val _chrome_generation = ref<int>(0)
(* A wheel turn waiting out its pause; the latest resize's number *)
val _wheel_busy = ref<bool>(false)
val _resize_generation = ref<int>(0)
(* The content node of the link within the book that has the focus, or -1 *)
val _focus_link = ref<int>(~1)
(* Whether the scrubber's thumb is being dragged *)
val _scrubbing = ref<bool>(false)
(* The gesture recognizer's state (linear, so it is taken out of its
   cell and put back); and whether a drag has just ended, so that the
   click the browser sends after it is not also a tap *)
datavtype gesture_cell = GNone | GSome of $GT.gstate
val _gestures = ref<gesture_cell>(GNone())
val _dragged = ref<bool>(false)
(* The latest keystroke in the search field's number *)
val _search_tick = ref<int>(0)

(* ============================================================
   Event payloads (bytes the host passed: checked here, once)
   ============================================================ *)

(* A pointer-like event's payload: x, y (int32 LE), the target's id
   length (u16 LE) and id *)
fn _int32_at {l:agz}{n:nat}{at:nat | at + 4 <= n} (bytes: !$A.arr(byte, l, n), at: int at): Int = let
  val byte0 = $AR.low_byte(byte2int0($A.get<byte>(bytes, at)))
  val byte1 = $AR.low_byte(byte2int0($A.get<byte>(bytes, at + 1)))
  val byte2 = $AR.low_byte(byte2int0($A.get<byte>(bytes, at + 2)))
  val byte3 = $AR.low_byte(byte2int0($A.get<byte>(bytes, at + 3)))
  val high = (if byte3 < 128 then byte3 else byte3 - 256): [signed:int | ~128 <= signed; signed < 128] int signed
in byte0 + byte1 * 256 + byte2 * 65536 + high * 16777216 end

(* The number n of the target id prefix<n> of a pointer event, or -1 *)
fn _target_number {prefix_len:pos | prefix_len <= 16} (h: $EV.event_payload, id_prefix: string prefix_len): [number:int | number >= ~1] int number =
  case+ take_blob(h) of
  | ~NoBlobBytes() => ~1
  | ~BlobBytes(event_bytes, n) => let
      val @(frozen, borrowed) = $A.freeze<byte>(event_bytes)
      val number = (if n >= 11 then nid_parse(borrowed, n, 10, id_prefix) else ~1): [number:int | number >= ~1] int number
      val () = $A.drop<byte>(frozen, borrowed)
    in let val () = $A.free<byte>($A.thaw<byte>(frozen)) in number end end

(* Whether the target id of a pointer event is id *)
fun _bytes_are {l:agz}{n:nat}{at:nat}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (bytes: !$A.arr(byte, l, n), n: int n, at: int at, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then at + text_len = n
  else if at + i >= n then false
  else if byte2int0($A.get<byte>(bytes, at + i)) <> char2int0(string_get_at(text, i)) then false
  else _bytes_are(bytes, n, at, text, text_len, i + 1)

(* Whether bytes[at, at + text_len) is text *)
fun _bytes_at {l:agz}{n:nat}{at:nat}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (bytes: !$A.arr(byte, l, n), n: int n, at: int at, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if at + i >= n then false
  else if byte2int0($A.get<byte>(bytes, at + i)) <> char2int0(string_get_at(text, i)) then false
  else _bytes_at(bytes, n, at, text, text_len, i + 1)

(* The target id of a pointer event, matched against the ids the
   caller asks about: the payload's bytes *)
datavtype target =
  | {l:agz}{n:pos} Target of ($A.arr(byte, l, n), int n, Int)
  | NoTarget of ()

fn _target (h: $EV.event_payload): target =
  case+ take_blob(h) of
  | ~NoBlobBytes() => NoTarget()
  | ~BlobBytes(event_bytes, n) =>
    if n < 10 then let val () = $A.free<byte>(event_bytes) in NoTarget() end
    else Target(event_bytes, n, _int32_at(event_bytes, 0))

fn _is {id_len:pos} (clicked: !target, id: string id_len): bool =
  case+ clicked of
  | Target(bytes, n, _) => _bytes_are(bytes, n, 10, id, g1u2i(string1_length(id)), 0)
  | NoTarget() => false

(* The harm whose menu item (ui_harm_item) clicked is: its click asks about
   that same harm *)
fn _harm_clicked (clicked: !target): Option_vt(harm) =
  if _is(clicked, ui_harm_id(HEmptyTrash())) then Some_vt(HEmptyTrash()) else None_vt()

(* The number n of the target's id prefix<n>, or -1 *)
fn _row_of {prefix_len:pos | prefix_len <= 16} (clicked: !target, id_prefix: string prefix_len): [number:int | number >= ~1] int number =
  case+ clicked of
  | @Target(event_bytes, n, _) => let
      val @(frozen, borrowed) = $A.freeze<byte>(event_bytes)
      val number = (if n >= 11 then nid_parse(borrowed, n, 10, id_prefix) else ~1): [number:int | number >= ~1] int number
      val () = $A.drop<byte>(frozen, borrowed)
      val () = event_bytes := $A.thaw<byte>(frozen)
      prval () = fold@(clicked)
    in number end
  | NoTarget() => ~1

(* The x of the target's event, or -1 *)
fn _target_x (clicked: !target): Int =
  case+ clicked of
  | Target(_, _, x) => x
  | NoTarget() => ~1

(* The y of a pointer event's target record, or -1 *)
fn _target_y (clicked: !target): Int =
  case+ clicked of
  | Target(event_bytes, n, _) => if n >= 8 then _int32_at(event_bytes, 4) else ~1
  | NoTarget() => ~1

fn _target_free (clicked: target): void =
  case+ clicked of
  | ~Target(event_bytes, _, _) => $A.free<byte>(event_bytes)
  | ~NoTarget() => ()

(* The x of a pointer event, or -1 *)
fn _event_x (h: $EV.event_payload): Int =
  case+ take_blob(h) of
  | ~NoBlobBytes() => ~1
  | ~BlobBytes(event_bytes, n) =>
    if n < 8 then let val () = $A.free<byte>(event_bytes) in ~1 end
    else let val x = _int32_at(event_bytes, 0) val () = $A.free<byte>(event_bytes) in x end

(* An input event's value, as a number (0 when it is not one) *)
fun _number_of {l:agz}{n:nat}{i:nat | i <= n} .<n - i>.
  (bytes: !$A.arr(byte, l, n), n: int n, i: int i, number: [so_far:nat | so_far < 100000] int so_far): [parsed:nat | parsed < 100000] int parsed =
  if i >= n then number
  else let
    val code = $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))
  in
    if code < 48 then number else if code > 57 then number
    else if number > 9999 then number
    else _number_of(bytes, n, i + 1, number * 10 + (code - 48))
  end

fn _input_number (h: $EV.event_payload): [number:nat | number < 100000] int number =
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(event_bytes, n) => let
      val number = (if n >= 2 then _number_of(event_bytes, n, 2, 0) else 0): [number:nat | number < 100000] int number
      val () = $A.free<byte>(event_bytes)
    in number end

(* An input event's value, from its bytes (after the 2 length bytes) *)
fn _input_text (h: $EV.event_payload): [l:agz][text_len:nat] @($A.arr(byte, l, text_len + 1), int text_len) =
  case+ take_blob(h) of
  | ~NoBlobBytes() => let val text = $A.alloc<byte>(1) in @(text, 0) end
  | ~BlobBytes(event_bytes, n) =>
    if n <= 2 then let
      val () = $A.free<byte>(event_bytes)
      val text = $A.alloc<byte>(1)
    in @(text, 0) end
    else let
      val text_len = n - 2
      val text = $A.alloc<byte>(text_len + 1)
      fun copy_text {event_loc,text_loc:agz}{event_size:nat}{text_len:nat | text_len + 2 <= event_size}{i:nat | i <= text_len} .<text_len - i>.
        (event_bytes: !$A.arr(byte, event_loc, event_size), text: !$A.arr(byte, text_loc, text_len + 1), text_len: int text_len, i: int i): void =
        if i >= text_len then ()
        else let val () = $A.set<byte>(text, i, $A.get<byte>(event_bytes, i + 2)) in copy_text(event_bytes, text, text_len, i + 1) end
      val () = copy_text(event_bytes, text, text_len, 0)
      val () = $A.free<byte>(event_bytes)
    in @(text, text_len) end

(* ============================================================
   Views
   ============================================================ *)

(* ============================================================
   The view kept across a reload: the book that is open, if any, so a
   reload (or the app killed and started again) comes back to it, on its
   page, rather than to the library
   ============================================================ *)

fn _view_key (): [l:agz] $A.arr(byte, l, 4) = let
  val key = $A.alloc<byte>(4)
  val () = $A.write_text(key, 0, $A.text_lit("view"), 4)
in key end

(* Keeps "view": the open book's key, or -1 for the library *)
fn _view_save (book_key: int): void = let
  val value = $A.alloc<byte>(4)
  val () = $A.write_i32(value, 0, book_key)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_view_key())
  val () = $P.discard<Int>($IDB.idb_put(key_bytes, 4, value_bytes, 4))
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(value_frozen, value_bytes) end

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
  val () = layer_close(LDictionary())
  val () = ui_show("library", true)
  (* a reload now comes back here *)
  val () = _view_save(~1)
  val () = reader_search_stop()
  val () = reader_stack_clear()
  val () = reader_timer_stop()
  val () = window_close()
in lib_render() end

(* The reader's bars: shown, and hidden again after 5 seconds *)
fn _chrome_set_off (): void = let
  val () = !_chrome := false
in ui_attr("reader", AClass, "rv chrome-off") end

fn _chrome_set (shown: bool): void = let
  (* bringing the bars up leaves the place a jump landed on: the back
     button goes *)
  val () = (if shown && ~(!_chrome) then reader_stack_clear() else ())
  val () = !_chrome := shown
  val () = (if shown then ui_attr("reader", AClass, "rv") else ui_attr("reader", AClass, "rv chrome-off"))
  val () = !_chrome_generation := !_chrome_generation + 1
  val generation = !_chrome_generation
in
  if shown then $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(5000)), lam(_) => let
      val () = (if !_chrome_generation = generation then _chrome_set_off() else ())
    in $P.ret<int>(0) end))
  else ()
end

(* The hint on turning pages, shown once, on the first book opened
   (a brief tip in context, not a tour): whether it has been shown,
   true until the last run's answer is read, so it never shows twice *)
val _hint_seen = ref<bool>(true)

fn _hint_key (): [l:agz] $A.arr(byte, l, 4) = let
  val key = $A.alloc<byte>(4)
  val () = $A.write_text(key, 0, $A.text_lit("hint"), 4)
in key end

(* Reads whether the hint was shown in an earlier run *)
fn _hint_load (): void = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_hint_key())
  val stored = $IDB.idb_get(key_bytes, 4)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(stored), lam(h) => let
    val () = (case+ take_blob(h) of
      | ~NoBlobBytes() => !_hint_seen := false
      | ~BlobBytes(value_bytes, _) => $A.free<byte>(value_bytes))
  in $P.ret<int>(0) end))
end

fn _hint_hide (): void = ui_show("turn-hint", false)

(* Shows the hint, the first time a book is opened: it goes at the first
   turn, or after 8 seconds *)
fn _hint_offer (): void =
  if !_hint_seen then ()
  else let
    val () = !_hint_seen := true
    val value = $A.alloc<byte>(1)
    val () = $A.write_byte(value, 0, 1)
    val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
    val @(key_frozen, key_bytes) = $A.freeze<byte>(_hint_key())
    val () = $P.discard<Int>($IDB.idb_put(key_bytes, 4, value_bytes, 1))
    val () = release_bytes(key_frozen, key_bytes)
    val () = release_bytes(value_frozen, value_bytes)
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
  val hash = $A.alloc<byte>(2)
  val () = $A.write_byte(hash, 0, 35)
  val () = $A.write_byte(hash, 1, 114)
  val @(hash_frozen, hash_bytes) = $A.freeze<byte>(hash)
  val () = $NAV.push_state(hash_bytes, 2)
  val () = release_bytes(hash_frozen, hash_bytes)
  val () = _chrome_set(true)
in ui_focus("page") end

(* Opens library book i where it was left *)
(* source[0, count) copied to destination[at, at + count) *)
fun _copy_from_to {source_loc,destination_loc:agz}{source_size,destination_size:nat}{count:nat | count <= source_size}{at:nat | at + count <= destination_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, destination: !$A.arr(byte, destination_loc, destination_size), at: int at, j: int j): void =
  if j >= count then ()
  else let val () = $A.set<byte>(destination, at + j, $A.get<byte>(source, j)) in _copy_from_to(source, count, destination, at, j + 1) end

fn _copy_into {source_loc,destination_loc:agz}{source_size,destination_size:nat}{count:nat | count <= source_size}{at:nat | at + count <= destination_size}
  (source: !$A.arr(byte, source_loc, source_size), count: int count, destination: !$A.arr(byte, destination_loc, destination_size), at: int at): void =
  _copy_from_to(source, count, destination, at, 0)

(* A shared selection's citation, the book's: "Author, Title" (as the
   export's) *)
fn _citation_set {book:int} (book: int book): void = let
  val @(title, title_len) = lib_text(book, 0)
  val @(author, author_len) = lib_text(book, 1)
  val citation = $A.alloc<byte>(520)
  val () = _copy_into(author, author_len, citation, 0)
  val () = $A.set<byte>(citation, author_len, $A.int2byte(44))
  val () = $A.set<byte>(citation, author_len + 1, $A.int2byte(32))
  val () = _copy_into(title, title_len, citation, author_len + 2)
  val () = $A.free<byte>(title)
  val () = $A.free<byte>(author)
in ui_text_buf("share-citation", citation, author_len + 2 + title_len) end

fn _open_book {book:int} (book: int book): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) =>
    if book_numbers.shelf = 3 then let
      val () = modal_inform("In the Trash")
    in modal_text_lit("Restore this book from the Trash to read it.") end
    else if book_numbers.shelf = 2 then let
      val () = modal_inform("Archived")
    in modal_text_lit("This book is archived. Import its file again to read it.") end
    else let
      val () = _show_reader()
      val () = _hint_offer()
      val () = _citation_set(book)
      val () = reader_stack_clear()
      (* the Ruby row waits for this book's first ruby *)
      val () = reader_ruby_forget()
      val () = reader_timer_start()
      (* a reload now comes back to this book *)
      val () = _view_save(book_numbers.key)
      val () = ui_text("chapter-title", "Loading...")
      (* no page is shown until this book's is: the last book's stays out
         of the indicator *)
      val () = ui_clear("indicator-title")
      val () = ui_clear("indicator-label")
      val () = ui_clear("indicator-pages")
      val chapter = book_numbers.chapter
      val page = book_numbers.page
      val anchor = book_numbers.anchor
      val id_high = book_numbers.id_high
      val id_low = book_numbers.id_low
    in
      if open_key_get() = book_numbers.key then
        $P.discard<int>($P.and_then<int><int>(annot_load(id_high, id_low), lam(_) => reader_goto(chapter, page, anchor)))
      else
        $P.discard<int>($P.and_then<Int><int>(open_stored(book_numbers.key, id_high, id_low), lam(result) =>
          if result < 0 then let
            val () = _show_library()
            val () = ui_text("error-text", "This book's file could not be read. Import it again.")
            val () = ui_show("error-banner", true)
          in $P.ret<int>(result) end
          else $P.and_then<int><int>(annot_load(id_high, id_low), lam(_) => reader_goto(chapter, page, anchor))))
    end

(* The view kept by the last run: its book opened again, on its page,
   when it is still on a shelf it is read from; else the library *)
fn _view_restore (): $P.promise(int, $P.Chained) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_view_key())
  val stored = $IDB.idb_get(key_bytes, 4)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<Int><int>($P.vow(stored), lam(h) => let
    val key = (case+ take_blob(h) of
      | ~NoBlobBytes() => ~1
      | ~BlobBytes(value_bytes, n) =>
        if n < 4 then let val () = $A.free<byte>(value_bytes) in ~1 end
        else let val stored_key = _int32_at(value_bytes, 0) val () = $A.free<byte>(value_bytes) in stored_key end): Int
    val book = (if key < 0 then ~1 else lib_index_of_key(key)): [index:int | index >= ~1] int index
    val readable = (if book < 0 then false else (case+ lib_nums(book) of
      | ~$R.none() => false
      | ~$R.some(book_numbers) => book_numbers.shelf < 2)): bool
  in
    if readable then let val () = _open_book(book) in $P.ret<int>(0) end
    else let val () = _show_library() in $P.ret<int>(0) end
  end)
end

(* ============================================================
   The library: menus, info, shelves
   ============================================================ *)

fn _save_render (): void = let
  val () = lib_save()
in lib_render() end

(* Sets the book's shelf *)
fn _set_shelf {book:int} (book: int book, shelf: Int): void = lib_set_shelf(book, shelf)

(* Deletes the stored data of book (id_high, id_low) under the key of letter *)
fn _idb_delete {letter:nat | letter < 256} (letter: int letter, id_high: int, id_low: int): void = let
  val key = lib_key(letter, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val () = $P.discard<Int>($IDB.idb_delete(key_bytes, 15))
in release_bytes(key_frozen, key_bytes) end

(* Archives the book: its record is kept and its file deleted. The file
   goes only when the Undo offer does: until then Undo puts the book
   back where it was, file and all *)
fn _archive {book:int} (book: int book): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) => let
      val key = book_numbers.key
      val was = book_numbers.shelf
      val id_high = book_numbers.id_high
      val id_low = book_numbers.id_low
      val () = _set_shelf(book, 2)
    in
      undo_offer("Archived", lam () => let
          val index = lib_index_of_key(key)
        in if index >= 0 then _set_shelf(index, was) else () end,
        (* the file goes only if the book is still archived (it may have
           been restored meanwhile, by importing it again) *)
        lam () => let
          val index = lib_index_of_key(key)
        in
          if index < 0 then ()
          else (case+ lib_nums(index) of
            | ~$R.none() => ()
            | ~$R.some(numbers_now) =>
              if numbers_now.shelf = 2 then let
                val () = _idb_delete(98, id_high, id_low)
              in if open_key_get() = key then open_key_set(0) else () end
              else ())
        end)
    end

(* Hides or unhides the book, offering Undo *)
fn _hide_toggle {book:int} (book: int book): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) => let
      val key = book_numbers.key
      val was = book_numbers.shelf
      val () = _set_shelf(book, (if was = 1 then 0 else 1))
    in
      undo_offer((if was = 1 then "Unhidden" else "Hidden"): [text_len:pos | text_len < 256] string text_len, lam () => let
          val index = lib_index_of_key(key)
        in if index >= 0 then _set_shelf(index, was) else () end,
        lam () => ())
    end


(* The book actions' labels (in the book menu or the info view) for a
   book on shelf shelf: in the Trash, Restore only (a book leaves the Trash
   for good only when it is emptied); elsewhere Hide or Unhide, Archive
   or Restore, and Move to Trash *)
fn _shelf_labels {hide_len,archive_len,trash_len:pos | hide_len < 256; archive_len < 256; trash_len < 256}
  (hide: string hide_len, archive: string archive_len, trash: string trash_len, shelf: Int): void =
  if shelf = 3 then let
    val () = ui_text(hide, "Restore")
    val () = ui_show(archive, false)
  in ui_show(trash, false) end
  else let
    val () = (if shelf = 1 then ui_text(hide, "Unhide") else ui_text(hide, "Hide"))
    val () = ui_show(archive, true)
    val () = (if shelf = 2 then ui_text(archive, "Restore") else ui_text(archive, "Archive"))
  in ui_show(trash, true) end

(* The book menu for the book, its items as its shelf asks *)
fn _menu_open {book:int} (book: int book): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) => let
      val () = !_menu_index := book
      val () = _shelf_labels("card-menu-hide", "card-menu-archive", "card-menu-trash", book_numbers.shelf)
      val () = layer_open(LBookMenu())
    in ui_focus("card-menu-info") end

(* "N% · Ch C of T" for book_numbers in text; its length *)
fn _progress_text {l:agz} (text: !$A.arr(byte, l, 64), book_numbers: bnums): [text_len:nat | text_len <= 64] int text_len = let
  val percent_len = $S.int_to_str(text, 0, 64, lib_progress(book_numbers))
  val () = $A.set<byte>(text, percent_len, $A.int2byte(37))
  val chapter_count = book_numbers.chapters
  val chapter_index = book_numbers.chapter
in
  if chapter_count <= 0 then percent_len + 1
  else let
    val chapter_shown = (if chapter_index >= 0 then chapter_index + 1 else 1): Int
    val () = $A.set<byte>(text, percent_len + 1, $A.int2byte(32))
    val () = $A.set<byte>(text, percent_len + 2, $A.int2byte(194))
    val () = $A.set<byte>(text, percent_len + 3, $A.int2byte(183))
    val () = $A.set<byte>(text, percent_len + 4, $A.int2byte(32))
    val () = $A.write_text(text, percent_len + 5, $A.text_lit("Ch "), 3)
    val after_chapter = $S.int_to_str(text, percent_len + 8, 64, chapter_shown)
    val () = $A.write_text(text, after_chapter, $A.text_lit(" of "), 4)
  in $S.int_to_str(text, after_chapter + 4, 64, chapter_count) end
end

(* The pages an hour of pages turned in minutes, 0 without minutes *)
fn _per_hour (pages: Int, minutes: Int): Int = let
  val minutes_read = g1ofg0(minutes)
  val pages_turned = g1ofg0(pages)
in if minutes_read > 0 then (if pages_turned > 0 then (pages_turned * 60) / minutes_read else 0) else 0 end

(* The info view of the book *)
fn _info_open {book:int} (book: int book): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) => let
      val () = !_menu_index := book
      val @(title, title_len) = lib_text(book, 0)
      val () = ui_text_buf("book-info-title", title, title_len)
      val @(author, author_len) = lib_text(book, 1)
      val () = ui_text_buf("book-info-author", author, author_len)
      (* progress: "N% · chapter C of T" *)
      val progress = $A.alloc<byte>(64)
      val progress_len = _progress_text(progress, book_numbers)
      val () = ui_text_buf("info-progress", progress, progress_len)
      val date = $A.alloc<byte>(32)
      val date_len = date_text(date, book_numbers.added)
      val () = ui_text_buf("info-added", date, date_len)
      val () = (if book_numbers.opened > 0 then let
          val date = $A.alloc<byte>(32)
          val date_len = date_text(date, book_numbers.opened)
        in ui_text_buf("info-last-read", date, date_len) end
        else ui_text("info-last-read", "Never"))
      val size = $A.alloc<byte>(32)
      val size_len = size_text(size, book_numbers.file_size)
      val () = ui_text_buf("info-size", size, size_len)
      (* the time it has been read, and its pages an hour (as Kobo's
         Reading Life shows them), once it has been *)
      val () = (if book_numbers.minutes_read > 0 then let
          val duration = $A.alloc<byte>(32)
          val duration_len = stats_duration_text(duration, book_numbers.minutes_read)
        in ui_text_buf("info-time", duration, duration_len) end
        else ui_text("info-time", "Not yet"))
      val () = (if book_numbers.minutes_read > 0 then let
          val speed = $A.alloc<byte>(32)
          val speed_len = $S.int_to_str(speed, 0, 32, _per_hour(book_numbers.pages_read, book_numbers.minutes_read))
          val () = $A.write_text(speed, speed_len, $A.text_lit(" pages an hour"), 14)
        in ui_text_buf("info-speed", speed, speed_len + 14) end
        else ())
      val () = ui_show("info-speed-row", book_numbers.minutes_read > 0)
      val () = _shelf_labels("book-info-hide", "book-info-archive", "book-info-trash", book_numbers.shelf)
      val () = ui_attr("book-info-cover", ASrc, "data:,")
      val () = (if book_numbers.cover > 0 then lib_show_cover_in("book-info-cover", book_numbers.id_high, book_numbers.id_low, book_numbers.cover) else ())
      (* a book without a cover shows none, not a broken image *)
      val () = ui_show("book-info-cover", book_numbers.cover > 0)
      val () = lib_a11y_show(book_numbers.id_high, book_numbers.id_low)
      val () = layer_open(LBookInfo())
    in ui_focus("book-info-back") end

(* A book menu or info view action on the book: 1 hide, unhide or (from
   the Trash) restore; 2 archive, or say how to restore; 3 move to the
   Trash *)
fn _book_action {book:int} (book: int book, action: int): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) =>
    if action = 1 then
      (if book_numbers.shelf = 3 then _set_shelf(book, 0) else _hide_toggle(book))
    else if action = 2 then
      (if book_numbers.shelf = 2 then let
         val () = modal_inform("Restore")
       in modal_text_lit("To restore this book, import its file again.") end
       else if book_numbers.shelf = 3 then ()
       else _archive(book))
    else if book_numbers.shelf = 3 then ()
    else let
      val () = layer_close(LBookInfo())
    in lib_trash(book) end

(* ============================================================
   Settings
   ============================================================ *)

fn _settings_changed (): void = let
  val () = set_apply(lib_state_get())
in if !_view = 1 then reader_relayout() else () end

fn _clamp {low,high:int | low <= high} (value: Int, low: int low, high: int high): [clamped:int | low <= clamped; clamped <= high] int clamped =
  if value < low then low else if value > high then high else value

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
  | ~$R.some(selection) => let val () = $DC.blob_free(selection) in true end

(* The selected text, to the clipboard *)
(* Look up: the selection's first 64 bytes (cut where a character
   begins), trimmed, as a Wiktionary search in the book's language:
   "https://fr.wiktionary.org/wiki/Special:Search?search=..." *)
fn _hex_digit (value: int): int = if value < 10 then 48 + value else 55 + value

(* out[at, written) := text[i, text_len) percent-encoded (letters, digits
   and -_.~ as they are, a space as %20) *)
fun _percent_encode {text_loc,out_loc:agz}{text_size:pos}{text_len:nat | text_len <= text_size}{i:nat | i <= text_len}{at:nat | at + 3 * (text_len - i) <= 256} .<text_len - i>.
  (text: !$A.arr(byte, text_loc, text_size), text_len: int text_len, i: int i, out: !$A.arr(byte, out_loc, 256), at: int at): [written:nat | written <= 256] int written =
  if i >= text_len then at
  else let
    val code = byte2int0($A.get<byte>(text, i))
    val plain = (code >= 97 && code <= 122) || (code >= 65 && code <= 90) || (code >= 48 && code <= 57)
      || code = 45 || code = 95 || code = 46 || code = 126
  in
    if plain then let
      val () = $A.set<byte>(out, at, $A.int2byte($AR.low_byte(code)))
    in _percent_encode(text, text_len, i + 1, out, at + 1) end
    else let
      val unsigned = (if code >= 0 then code else code + 256): int
      val () = $A.set<byte>(out, at, $A.int2byte(37))
      val () = $A.set<byte>(out, at + 1, $A.int2byte($AR.low_byte(_hex_digit(unsigned / 16))))
      val () = $A.set<byte>(out, at + 2, $A.int2byte($AR.low_byte(_hex_digit(unsigned - (unsigned / 16) * 16))))
    in _percent_encode(text, text_len, i + 1, out, at + 3) end
  end

fun _trim_start {l:agz}{n:pos}{text_len:nat | text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (text: !$A.arr(byte, l, n), text_len: int text_len, i: int i): [start:nat | start <= text_len] int start =
  if i >= text_len then i
  else let val code = byte2int0($A.get<byte>(text, i)) in
    if code = 32 || code = 9 || code = 10 || code = 13 then _trim_start(text, text_len, i + 1) else i
  end

fun _trim_end {l:agz}{n:pos}{start:nat}{stop:nat | start <= stop; stop <= n} .<stop - start>.
  (text: !$A.arr(byte, l, n), start: int start, stop: int stop): [trimmed:nat | start <= trimmed; trimmed <= stop] int trimmed =
  if stop <= start then stop
  else let val code = byte2int0($A.get<byte>(text, stop - 1)) in
    if code = 32 || code = 9 || code = 10 || code = 13 then _trim_end(text, start, stop - 1) else stop
  end

(* The first place <= stop (from start) where a character begins: a
   byte that is not 0x80 to 0xBF *)
fun _char_start {l:agz}{n:pos}{start,stop:nat | start <= stop; stop < n} .<stop - start>.
  (text: !$A.arr(byte, l, n), start: int start, stop: int stop): [begins:nat | start <= begins; begins <= stop] int begins =
  if stop <= start then stop
  else let val code = byte2int0($A.get<byte>(text, stop)) in
    if code >= 128 && code < 192 then _char_start(text, start, stop - 1) else stop
  end

(* The end of text[start, stop), cut to at most 64 bytes where a
   character begins *)
fn _cut {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (text: !$A.arr(byte, l, n), start: int start, stop: int stop): [cut:nat | start <= cut; cut <= stop; cut - start <= 64] int cut =
  if stop - start <= 64 then stop
  else _char_start(text, start, start + 64)

(* word[0, stop - start) := text[start, stop), at most 64 bytes *)
fun _copy_bytes {text_loc,word_loc:agz}{text_size:pos}{start,stop:nat | start <= stop; stop <= text_size; stop - start <= 64}{j:nat | j <= stop - start} .<stop - start - j>.
  (text: !$A.arr(byte, text_loc, text_size), start: int start, stop: int stop, word: !$A.arr(byte, word_loc, 65), j: int j): void =
  if start + j >= stop then ()
  else let
    val () = $A.set<byte>(word, j, $A.get<byte>(text, start + j))
  in _copy_bytes(text, start, stop, word, j + 1) end

fn _copy_word {text_loc,word_loc:agz}{text_size:pos}{start,stop:nat | start <= stop; stop <= text_size}
  (text: !$A.arr(byte, text_loc, text_size), start: int start, stop: int stop, word: !$A.arr(byte, word_loc, 65)): [word_len:nat | word_len <= 64] int word_len =
  if stop - start > 64 then 0
  else let val () = _copy_bytes(text, start, stop, word, 0) in stop - start end

(* out[at, at + text_len) := text *)
fun _put_literal_at {l:agz}{text_len:nat}{at:nat | at + text_len <= 256}{i:nat | i <= text_len} .<text_len - i>.
  (out: !$A.arr(byte, l, 256), at: int at, text: string text_len, text_len: int text_len, i: int i): void =
  if i >= text_len then ()
  else let
    val () = $A.set<byte>(out, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_literal_at(out, at, text, text_len, i + 1) end

fn _put_literal {l:agz}{text_len:nat}{at:nat | at + text_len <= 256}
  (out: !$A.arr(byte, l, 256), at: int at, text: string text_len): int(at + text_len) = let
  val text_len = g1u2i(string1_length(text))
  val () = _put_literal_at(out, at, text, text_len, 0)
in at + text_len end

fn _put_array {out_loc,code_loc:agz}{at:nat | at + 3 <= 256}{code_len:pos | code_len <= 3}
  (out: !$A.arr(byte, out_loc, 256), at: int at, code: !$A.arr(byte, code_loc, 3), code_len: int code_len): int(at + code_len) = let
  val () = $A.set<byte>(out, at, $A.get<byte>(code, 0))
  val () = $A.set<byte>(out, at + 1, $A.get<byte>(code, 1))
  val () = (if code_len = 3 then $A.set<byte>(out, at + 2, $A.get<byte>(code, 2)) else ())
in at + code_len end

(* copy[0, url_len) := url[0, url_len) *)
fun _copy_url {url_loc,copy_loc:agz}{url_len:nat | url_len <= 256}{i:nat | i <= url_len} .<url_len - i>.
  (url: !$A.arr(byte, url_loc, 256), copy: !$A.arr(byte, copy_loc, 256), url_len: int url_len, i: int i): void =
  if i >= url_len then ()
  else let
    val () = $A.set<byte>(copy, i, $A.get<byte>(url, i))
  in _copy_url(url, copy, url_len, i + 1) end

(* The dictionary panel's "Look up online": url[0, url_len), copied *)
fn _online_href {url_loc:agz}{url_len:nat | url_len <= 256} (url: !$A.arr(byte, url_loc, 256), url_len: int url_len): void =
  if url_len <= 0 then ()
  else let
    val copy = $A.alloc<byte>(256)
    val () = _copy_url(url, copy, url_len, 0)
  in ui_https_href("dictionary-online", copy, url_len) end

(* Look up follows the selection: its link to the online dictionary,
   and, when a dictionary the reader imported for the book's language
   has the word, the button that shows it there instead (the dictionary
   panel's "Look up online" keeps the link). A dictionary whose files
   are still being read looks the selection up again once they are
   (dict_when_read) *)
fn _lookup_update (): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(selection) => let
      val selection_len = $DC.blob_len(selection)
    in
      if selection_len <= 0 then $DC.blob_free(selection)
      else if selection_len > 4096 then $DC.blob_free(selection)
      else let
        val text = $A.alloc<byte>(selection_len)
        val () = $DC.blob_read(selection, 0, text, selection_len)
        val () = $DC.blob_free(selection)
        val start = _trim_start(text, selection_len, 0)
        val trimmed_end = _trim_end(text, start, selection_len)
        val cut_end = _cut(text, start, trimmed_end)
        val word = $A.alloc<byte>(65)
        val word_len = _copy_word(text, start, cut_end, word)
        val () = $A.free<byte>(text)
        val out = $A.alloc<byte>(256)
        val at = _put_literal(out, 0, "https://")
        val @(language, language_len) = reader_lang_code()
        val at = _put_array(out, at, language, language_len)
        val at = _put_literal(out, at, ".wiktionary.org/wiki/Special:Search?search=")
        val url_len = _percent_encode(word, word_len, 0, out, at)
        val found = dict_find(language, language_len, word, word_len)
        val () = $A.free<byte>(language)
        val () = $A.free<byte>(word)
        val () = ui_show("selection-define", found)
        val () = ui_show("selection-lookup", ~found)
        val () = _online_href(out, url_len)
      in if url_len > 0 then ui_https_href("selection-lookup", out, url_len) else $A.free<byte>(out) end
    end

fn _copy_selection (): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(selection) => let
      val selection_len = $DC.blob_len(selection)
    in
      if selection_len <= 0 then $DC.blob_free(selection)
      else if selection_len > 1048576 then $DC.blob_free(selection)
      else let
        val text = $A.alloc<byte>(selection_len)
        val () = $DC.blob_read(selection, 0, text, selection_len)
        val () = $DC.blob_free(selection)
        val @(text_frozen, text_bytes) = $A.freeze<byte>(text)
        val () = $P.discard<Int>($P.vow($CB.clipboard_write(text_bytes, selection_len)))
      in release_bytes(text_frozen, text_bytes) end
    end

(* Exports the open book's annotations: downloaded, or to be shared
   (the page's script shares them once this click's listener is done) *)
fn _export (share: bool): void = let
  val book = lib_index_of_key(open_key_get())
  val @(title, title_len) = lib_text(book, 0)
  val @(author, author_len) = lib_text(book, 1)
in annot_export(title, title_len, author, author_len, share) end

(* Goes to annotation, remembering where the reader was *)
fn _annotation_go (annotation: int): void = let
  val @(chapter, page, node) = annot_dest(annotation)
in if chapter >= 0 then reader_jump_to(chapter, page, node) else () end

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

(* The collections panel for the book, its toggles pressed as the book's
   collections are *)
fn _collections_open {book:int} (book: int book): void = let
  val () = !_menu_index := book
  val () = lib_coll_panel(book)
  val () = layer_open(LCollections())
in if lib_coll_count() > 0 then ui_focus("collection-put0") else ui_focus("collections-new") end

(* Puts the book in the collection, or takes it out: its toggle and the
   library follow *)
fn _collection_put {book:int}{collection:int} (book: int book, collection: int collection): void =
  if collection < 0 then ()
  else let
    val () = lib_coll_toggle(book, collection)
    val @(put_id, put_id_len) = nid_make("collection-put", collection)
    val () = (if lib_coll_has(book, collection) then ui_attr_n(put_id, put_id_len, APressed, "true") else ui_attr_n(put_id, put_id_len, APressed, "false"))
  in lib_render() end

(* A new collection, named in the dialog, with the book in it *)
fn _collection_new {book:int} (book: int book): void = let
  val () = modal_open(QNewCollection(), "New collection", lam () => let
      val @(name, name_len) = modal_name_read()
      val collection = lib_coll_add(name, name_len)
      val () = (if collection >= 0 then lib_coll_toggle(book, collection) else ())
      val () = lib_coll_panel(book)
    in lib_render() end, lam () => ())
in modal_name_field() end

(* The collection shown, named again in the dialog *)
fn _collection_rename (): void = let
  val collection = lib_coll_shown()
in
  if collection < 0 then ()
  else let
    val () = modal_open(QRenameCollection(), "Rename collection", lam () => let
        val @(name, name_len) = modal_name_read()
      in lib_coll_rename(collection, name, name_len) end, lam () => ())
    val () = modal_name_field()
  in lib_coll_name_show(collection) end
end

fn _wire_library {count:nat} (listeners: regs(count)): regs(count + 23) = let
  (* import *)
  val listeners = RCons(listeners, OnEl("import-button"), "change", lam(_) => let val () = import_picked() in 0 end)
  (* drag and drop *)
  val listeners = RCons(listeners, OnEl("library"), "dragover", lam(_) => let
      val () = $EV.prevent_default()
    in let val () = ui_attr("library", AClass, "lib drag") in 0 end end)
  val listeners = RCons(listeners, OnEl("library"), "dragleave", lam(_) => let
      val () = ui_attr("library", AClass, "lib")
    in 0 end)
  val listeners = RCons(listeners, OnEl("library"), "drop", lam(_) => let
      val () = $EV.prevent_default()
      val () = ui_attr("library", AClass, "lib")
      val () = import_dropped()
    in 0 end)
  (* the cards: open, and the book menu *)
  val listeners = RCons(listeners, OnEl("book-list"), "click", lam(h) => let
      val clicked = _target(h)
      val book = _row_of(clicked, "book")
      val menu_book = _row_of(clicked, "book-more")
      val () = _target_free(clicked)
    in
      if book >= 0 then let val () = _open_book(book) in 0 end
      else if menu_book >= 0 then let val () = _menu_open(menu_book) in 0 end
      else 0
    end)
  (* the view: which books, as a list or a grid; kept with the settings *)
  val listeners = RCons(listeners, OnEl("library-view"), "click", lam(h) => let
      val clicked = _target(h)
      val filter = (if _is(clicked, "filter-books-all") then 0 else if _is(clicked, "filter-unread") then 1
        else if _is(clicked, "filter-reading") then 2 else if _is(clicked, "filter-finished") then 3 else ~1): int
      val grid = (if _is(clicked, "view-list") then 0 else if _is(clicked, "view-grid") then 1 else ~1): int
      (* the collections: which is shown, and the one shown renamed or
         deleted *)
      val collection = _row_of(clicked, "collection")
      val all_collections = _is(clicked, "collection-all")
      val rename_collection = _is(clicked, "collection-rename")
      val delete_collection = _is(clicked, "collection-delete")
      val () = _target_free(clicked)
      val () = (if all_collections then lib_coll_show(~1) else if collection >= 0 then lib_coll_show(collection)
        else if rename_collection then _collection_rename() else if delete_collection then lib_coll_delete(lib_coll_shown()) else ())
      val () = (if filter >= 0 then lib_filter_set(filter) else if grid >= 0 then lib_grid_set(grid) else ())
    in if filter >= 0 || grid >= 0 then let val () = set_save(lib_state_get()) in 0 end else 0 end)
  (* the book to continue: opened *)
  val listeners = RCons(listeners, OnEl("continue-list"), "click", lam(h) => let
      val clicked = _target(h)
      val book = _row_of(clicked, "continue")
      val () = _target_free(clicked)
    in if book >= 0 then let val () = _open_book(book) in 0 end else 0 end)
  val listeners = RCons(listeners, OnEl("book-list"), "contextmenu", lam(h) => let
      val () = $EV.prevent_default()
      val book = _target_number(h, "book")
    in if book >= 0 then let val () = _menu_open(book) in 0 end else 0 end)
  val listeners = RCons(listeners, OnEl("card-menu"), "click", lam(h) => let
      val clicked = _target(h)
      val book = !_menu_index
      val () = layer_close(LBookMenu())
      val () = (if book >= 0 then
          (if _is(clicked, "card-menu-info") then _info_open(book)
           else if _is(clicked, "card-menu-collections") then _collections_open(book)
           else if _is(clicked, "card-menu-hide") then _book_action(book, 1)
           else if _is(clicked, "card-menu-archive") then _book_action(book, 2)
           else if _is(clicked, "card-menu-trash") then _book_action(book, 3)
           else ()) else ())
    in let val () = _target_free(clicked) in 0 end end)
  (* a book's collections: each toggled, a new one, or done (or a
     click outside) *)
  val listeners = RCons(listeners, OnEl("collections-menu"), "click", lam(h) => let
      val clicked = _target(h)
      val book = !_menu_index
      val collection = _row_of(clicked, "collection-put")
      val made = _is(clicked, "collections-new")
      val done = (if _is(clicked, "collections-done") then true else _is(clicked, "collections-menu")): bool
      val () = _target_free(clicked)
      val () = (if book < 0 then ()
        else if collection >= 0 then _collection_put(book, collection)
        else if made then _collection_new(book)
        else if done then layer_close(LCollections())
        else ())
    in 0 end)
  (* the info view *)
  val listeners = RCons(listeners, OnEl("book-info"), "click", lam(h) => let
      val clicked = _target(h)
      val book = !_menu_index
      val () = (if _is(clicked, "book-info-back") then layer_close(LBookInfo())
        else if book < 0 then ()
        else if _is(clicked, "book-info-hide") then let val () = layer_close(LBookInfo()) in _book_action(book, 1) end
        else if _is(clicked, "book-info-archive") then let val () = layer_close(LBookInfo()) in _book_action(book, 2) end
        else if _is(clicked, "book-info-trash") then _book_action(book, 3)
        else ())
    in let val () = _target_free(clicked) in 0 end end)
  (* sort and shelf *)
  val listeners = RCons(listeners, OnEl("sort-button"), "click", lam(_) => let
      val sort_order = lib_sort_get()
      val sort_order = (if sort_order >= 4 then 0 else sort_order + 1): int
      val () = lib_sort(sort_order)
      val () = lib_sort_label(sort_order)
      val () = set_apply(lib_state_get())
    in let val () = lib_render() in 0 end end)
  val listeners = RCons(listeners, OnEl("shelf-button"), "click", lam(_) => let
      val shelf = lib_shelf_get()
      val () = lib_shelf_set((if shelf >= 3 then 0 else shelf + 1): int)
    in let val () = lib_render() in 0 end end)
  (* search *)
  (* the field is made again to be cleared: its events are taken on
     its box *)
  val listeners = RCons(listeners, OnEl("library-search-box"), "input", lam(h) => let
      val @(query, query_len) = _input_text(h)
      val () = ui_show("library-search-clear", query_len > 0)
      val () = lib_query_set(query, query_len)
    in let val () = lib_render() in 0 end end)
  val listeners = RCons(listeners, OnEl("library-search-box"), "click", lam(h) => let
      val clicked = _target(h)
      val clear = _is(clicked, "library-search-clear")
      val () = _target_free(clicked)
    in
      if clear then let
        val () = app_library_search()
        val () = lib_query_set($A.alloc<byte>(1), 0)
        val () = lib_render()
      in let val () = ui_focus("library-search") in 0 end end
      else 0
    end)
  (* a backup picked to restore *)
  val listeners = RCons(listeners, OnEl("menu-import-backup"), "change", lam(_) => let
      val () = layer_close(LLibraryMenu())
      val () = backup_import()
    in 0 end)
  (* the error banner *)
  val listeners = RCons(listeners, OnEl("error-dismiss"), "click", lam(_) => let val () = ui_show("error-banner", false) in 0 end)
  val listeners = RCons(listeners, OnEl("install-hint-dismiss"), "click", lam(_) => let val () = lib_install_hint_dismiss() in 0 end)
  (* the library menu *)
  val listeners = RCons(listeners, OnEl("library-menu-button"), "click", lam(_) => let
      val () = layer_open(LLibraryMenu())
    in let val () = ui_focus("menu-export-backup") in 0 end end)
  val listeners = RCons(listeners, OnEl("library-menu"), "click", lam(h) => let
      val clicked = _target(h)
      val () = (case+ _harm_clicked(clicked) of
        | ~Some_vt(the_harm) => let
            val () = layer_close(LLibraryMenu())
          in lib_ask_harm(the_harm, lam () => _save_render()) end
        | ~None_vt() =>
        if _is(clicked, "menu-factory-reset") then let
          val () = layer_close(LLibraryMenu())
        in _factory_reset() end
        else if _is(clicked, "menu-export-backup") then let
          val () = layer_close(LLibraryMenu())
        in backup_export() end
        (* the page's script asks the browser to install the app *)
        else if _is(clicked, "menu-install") then layer_close(LLibraryMenu())
        else if _is(clicked, "menu-storage-kept") then let
          val () = layer_close(LLibraryMenu())
          val () = modal_inform("Your books are kept")
        in modal_text_lit("This browser keeps the books you import until you remove them.") end
        else if _is(clicked, "menu-storage-at-risk") then let
          val () = layer_close(LLibraryMenu())
          val () = modal_inform("Your books may be cleared")
        in modal_text_lit("This browser may clear what Quire keeps when it runs short of space. Installing Quire, or reading it more often, makes the browser more likely to keep it. Keep your EPUB files: a backup holds your places, notes and settings, not the books.") end
        else if _is(clicked, "menu-stats") then let
          val () = layer_close(LLibraryMenu())
          val () = stats_show()
          val () = layer_open(LStats())
        in ui_focus("stats-done") end
        else if _is(clicked, "menu-catalogues") then let
          val () = layer_close(LLibraryMenu())
        in catalogue_panel_open() end
        else if _is(clicked, "menu-dictionaries") then let
          val () = layer_close(LLibraryMenu())
          val @(code, code_len) = reader_lang_code()
          val () = dict_panel_open(code, code_len)
        in $A.free<byte>(code) end
        else if _is(clicked, "menu-close") then layer_close(LLibraryMenu())
        else if _is(clicked, "library-menu") then layer_close(LLibraryMenu())
        else ())
    in let val () = _target_free(clicked) in 0 end end)
  (* the reading statistics: a daily goal chosen, or done (or a click
     outside) *)
  val listeners = RCons(listeners, OnEl("stats-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val goal = (if _is(clicked, "stats-goal-off") then 0
        else if _is(clicked, "stats-goal-10") then 10
        else if _is(clicked, "stats-goal-20") then 20
        else if _is(clicked, "stats-goal-30") then 30
        else if _is(clicked, "stats-goal-60") then 60
        else ~1): int
      val done = (if _is(clicked, "stats-done") then true else _is(clicked, "stats-panel")): bool
      val () = _target_free(clicked)
      val () = (if goal >= 0 then let
          val () = stats_goal_set(goal)
        in stats_show() end
        else if done then layer_close(LStats())
        else ())
    in 0 end)
  (* the dictionaries: one removed, or done (or a click outside) *)
  val listeners = RCons(listeners, OnEl("dictionaries-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val removed = _row_of(clicked, "drop-dictionary")
      val done = (if _is(clicked, "dictionaries-done") then true else _is(clicked, "dictionaries-panel")): bool
      val () = _target_free(clicked)
      val () = (if removed >= 0 then dict_remove(removed)
        else if done then layer_close(LDictionaries())
        else ())
    in 0 end)
  (* a dictionary's files picked to import (the input is made again to
     be cleared: its events are taken on its box) *)
  val listeners = RCons(listeners, OnEl("dictionary-import"), "change", lam(_) => let
      val () = dict_import_picked()
    in 0 end)
in listeners end

fn _wire_settings {count:nat} (listeners: regs(count)): regs(count + 8) = let
  val listeners = RCons(listeners, OnEl("typography-button"), "click", lam(_) => let
      val () = layer_open(LTypography())
    in let val () = ui_focus("typography-close") in 0 end end)
  val listeners = RCons(listeners, OnEl("typography-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val changed = (if _is(clicked, "font-literata") then let val () = set_font_set(0) in true end
        else if _is(clicked, "font-inter") then let val () = set_font_set(1) in true end
        else if _is(clicked, "font-book") then let val () = set_font_set(2) in true end
        else if _is(clicked, "font-atkinson") then let val () = set_font_set(3) in true end
        else if _is(clicked, "theme-auto") then let val () = set_theme_set(0) in true end
        else if _is(clicked, "theme-light") then let val () = set_theme_set(1) in true end
        else if _is(clicked, "theme-sepia") then let val () = set_theme_set(2) in true end
        else if _is(clicked, "theme-dark") then let val () = set_theme_set(3) in true end
        else if _is(clicked, "theme-night") then let val () = set_theme_set(4) in true end
        else if _is(clicked, "theme-grey") then let val () = set_theme_set(5) in true end
        else if _is(clicked, "layout-pages") then let val () = set_flow_set(0) in true end
        else if _is(clicked, "layout-scroll") then let val () = set_flow_set(1) in true end
        else if _is(clicked, "columns-auto") then let val () = set_cols_set(0) in true end
        else if _is(clicked, "columns-one") then let val () = set_cols_set(1) in true end
        else if _is(clicked, "columns-two") then let val () = set_cols_set(2) in true end
        else if _is(clicked, "align-ragged") then let val () = set_align_set(0) in true end
        else if _is(clicked, "align-justified") then let val () = set_align_set(1) in true end
        else if _is(clicked, "hyphens-off") then let val () = set_hyph_set(0) in true end
        else if _is(clicked, "hyphens-on") then let val () = set_hyph_set(1) in true end
        else if _is(clicked, "ruby-show") then let val () = set_ruby_set(1) in true end
        else if _is(clicked, "ruby-hide") then let val () = set_ruby_set(0) in true end
        else if _is(clicked, "dim-off") then let val () = set_dim_set(0) in true end
        else if _is(clicked, "dim-on") then let val () = set_dim_set(1) in true end
        else if _is(clicked, "taps-sides") then let val () = set_taps_set(0) in true end
        else if _is(clicked, "taps-forward") then let val () = set_taps_set(1) in true end
        else if _is(clicked, "taps-one-hand") then let val () = set_taps_set(2) in true end
        else if _is(clicked, "volume-keys-off") then let val () = set_vol_set(0) in true end
        else if _is(clicked, "volume-keys-turn") then let val () = set_vol_set(1) in true end
        else if _is(clicked, "typography-reset") then let
            val () = set_reset(lam () => let
                val () = set_sliders()
              in _settings_changed() end)
          in false end
        else false): bool
      val close = _is(clicked, "typography-close")
      val () = _target_free(clicked)
      val () = (if close then layer_close(LTypography()) else ())
    in if changed then let val () = _settings_changed() in 0 end else 0 end)
  val listeners = RCons(listeners, OnEl("size-row"), "input", lam(h) => let
      val () = set_size_set(_clamp(_input_number(h), 12, 32))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("line-height-row"), "input", lam(h) => let
      val () = set_lh_set(_clamp(_input_number(h), 12, 24))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("margins-row"), "input", lam(h) => let
      val () = set_margin_set(_clamp(_input_number(h), 0, 4))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("paragraph-row"), "input", lam(h) => let
      val () = set_ps_set(_clamp(_input_number(h), 0, 20))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("letter-row"), "input", lam(h) => let
      val () = set_ls_set(_clamp(_input_number(h), 0, 12))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("word-row"), "input", lam(h) => let
      val () = set_ws_set(_clamp(_input_number(h), 0, 16))
    in let val () = _settings_changed() in 0 end end)
in listeners end

(* ============================================================
   Search
   ============================================================ *)

(* Whether an element is shown *)
fn _shown {id_len:pos | id_len < 256} (id: string id_len): bool = let
  val () = ui_measure(id)
in $DR.get_measure_w() > 0 end

(* The search field, made again holding query[0, query_len) *)
fn _search_value {l:agz}{n:pos}{query_len:nat | query_len <= n; query_len < 65536} (query: $A.arr(byte, l, n), query_len: int query_len): void =
  if query_len > 0 then ui_attr_buf("search-field", AValue, query, query_len) else $A.free<byte>(query)

fn _search_field {l:agz}{n:pos}{query_len:nat | query_len <= n; query_len < 65536} (query: $A.arr(byte, l, n), query_len: int query_len): void = let
  val () = app_book_search()
in _search_value(query, query_len) end

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
  val field_id = $A.alloc<byte>(12)
  val () = $A.write_text(field_id, 0, $A.text_lit("search-field"), 12)
  val @(field_id_frozen, field_id_bytes) = $A.freeze<byte>(field_id)
  val value_read = $DR.read_input_value(field_id_bytes, 12)
  val () = release_bytes(field_id_frozen, field_id_bytes)
in
  case+ value_read of
  | ~$R.none() => reader_search($A.alloc<byte>(1), 0)
  | ~$R.some(value) => let
      val query_len = $DC.blob_len(value)
    in
      if query_len <= 0 then let
        val () = $DC.blob_free(value)
      in reader_search($A.alloc<byte>(1), 0) end
      else if query_len > 65535 then $DC.blob_free(value)
      else let
        val query = $A.alloc<byte>(query_len)
        val () = $DC.blob_read(value, 0, query, query_len)
        val () = $DC.blob_free(value)
      in reader_search(query, query_len) end
    end
end

(* A keystroke in the field: the search runs once typing pauses *)
fn _search_input (): void = let
  val () = !_search_tick := !_search_tick + 1
  val tick = !_search_tick
in
  $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(300)), lam(_) => let
    val () = (if !_search_tick = tick then _search_run() else ())
  in $P.ret<int>(0) end))
end

(* Searches for the selected text *)
fn _search_selection (): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(selection) => let
      val selection_len = $DC.blob_len(selection)
    in
      if selection_len <= 0 then $DC.blob_free(selection)
      else if selection_len > 1000 then $DC.blob_free(selection)
      else let
        val field_text = $A.alloc<byte>(selection_len)
        val () = $DC.blob_read(selection, 0, field_text, selection_len)
        val query = $A.alloc<byte>(selection_len)
        val () = $DC.blob_read(selection, 0, query, selection_len)
        val () = $DC.blob_free(selection)
        val () = _search_field(field_text, selection_len)
        val () = layer_open(LSearch())
        val () = !_search_tick := !_search_tick + 1
      in reader_search(query, selection_len) end
    end

(* Closes the reader's panels; whether one was open *)
fn _panels_close (): bool = layer_close_all()

(* A page turn: the bars hide *)
fn _next (): void = let
  val () = _hint_hide()
  val () = (if !_chrome then _chrome_set(false) else ())
in page_next() end

fn _previous (): void = let
  val () = _hint_hide()
  val () = (if !_chrome then _chrome_set(false) else ())
in page_prev() end

(* The page to the left and to the right: back and on, or the other way
   in a book read right to left *)
fn _left (): void = if reader_rtl() then _next() else _previous()
fn _right (): void = if reader_rtl() then _previous() else _next()

(* Whether x is between the sides' zones: in the middle half of the
   page *)
fn _in_middle (x: Int): bool = let
  val () = ui_measure("page")
  val page_x = $DR.get_measure_x()
  val page_width = $DR.get_measure_w()
in
  if page_width <= 0 then false
  else if x < page_x + page_width / 4 then false
  else x <= page_x + page_width - page_width / 4
end

(* What a tap at x, y on the page does, by the setting (settings.bats):
   sides, the left quarter back, the right quarter on, between them the
   bars shown or hidden; forward, the top eighth the bars, the left
   quarter back, anywhere else on; one hand, the top third back, the
   bottom third on, between them the bars. Back and on are the book's:
   a book read right to left turns the other way *)
fn _zone_click (x: Int, y: Int): void = let
  val () = ui_measure("page")
  val page_x = $DR.get_measure_x()
  val page_y = $DR.get_measure_y()
  val page_width = $DR.get_measure_w()
  val page_height = $DR.get_measure_h()
  val taps = set_taps_get()
in
  if page_width <= 0 then ()
  else if taps = 1 then
    (if (if page_height > 0 then y < page_y + page_height / 8 else false) then _chrome_set(~(!_chrome))
     else if x < page_x + page_width / 4 then _left()
     else _right())
  else if taps = 2 then
    (if page_height <= 0 then _chrome_set(~(!_chrome))
     else if y < page_y + page_height / 3 then _previous()
     else if y > page_y + page_height - page_height / 3 then _next()
     else _chrome_set(~(!_chrome)))
  else if x < page_x + page_width / 4 then _left()
  else if x > page_x + page_width - page_width / 4 then _right()
  else _chrome_set(~(!_chrome))
end

(* A key's name at key_bytes[1, 1 + name_len), and its modifier flags after it *)
fn _key_is {l:agz}{n:nat}{name_len:pos} (key_bytes: !$A.arr(byte, l, n), n: int n, name: string name_len): bool = let
  val name_len = g1u2i(string1_length(name))
in
  if n <> name_len + 2 then false
  else if byte2int0($A.get<byte>(key_bytes, 0)) <> name_len then false
  else _bytes_at(key_bytes, n, 1, name, name_len, 0)
end

fn _reader_key {l:agz}{n:nat} (key_bytes: !$A.arr(byte, l, n), n: int n): void = let
  val shift = (if n >= 2 then $AR.band_g1($AR.low_byte(byte2int0($A.get<byte>(key_bytes, n - 1))), 1) = 1 else false): bool
  (* Ctrl or Cmd *)
  val modifiers = (if n >= 2 then $AR.band_g1($AR.low_byte(byte2int0($A.get<byte>(key_bytes, n - 1))), 10) else 0): int
in
  (* the keys that turn the page are the reader's alone: scrolled, the
     browser would also scroll the focused page by them *)
  if _key_is(key_bytes, n, "ArrowRight") then _right()
  else if _key_is(key_bytes, n, "PageDown") then let val () = $EV.prevent_default() in _next() end
  else if _key_is(key_bytes, n, "ArrowLeft") then _left()
  else if _key_is(key_bytes, n, "PageUp") then let val () = $EV.prevent_default() in _previous() end
  else if _key_is(key_bytes, n, " ") then let val () = $EV.prevent_default() in (if shift then _previous() else _next()) end
  (* the volume keys, when they turn the page and the browser gives them
     to the page: down on, up back, and the volume left as it is *)
  else if (if set_vol_get() = 1 then _key_is(key_bytes, n, "AudioVolumeDown") else false) then let
    val () = $EV.prevent_default()
  in _next() end
  else if (if set_vol_get() = 1 then _key_is(key_bytes, n, "AudioVolumeUp") else false) then let
    val () = $EV.prevent_default()
  in _previous() end
  else if _key_is(key_bytes, n, "Home") then let val () = $EV.prevent_default() in reader_page(0) end
  else if _key_is(key_bytes, n, "End") then let val () = $EV.prevent_default() in reader_page(1000000) end
  else if _key_is(key_bytes, n, "b") then annot_bookmark_toggle(reader_anchor())
  else if _key_is(key_bytes, n, "B") then annot_bookmark_toggle(reader_anchor())
  else if _key_is(key_bytes, n, "t") then _chrome_set(~(!_chrome))
  else if _key_is(key_bytes, n, "T") then _chrome_set(~(!_chrome))
  else if _key_is(key_bytes, n, "/") then let
      val () = $EV.prevent_default()
    in _search_open() end
  else if (if _key_is(key_bytes, n, "f") then modifiers >= 2 else false) then let
      val () = $EV.prevent_default()
    in _search_open() end
  else if (if _key_is(key_bytes, n, "Enter") then !_focus_link >= 0 else false) then let
    (* the Enter is the link's: a note opened over the page takes the
       focus to its Close, which the same Enter would otherwise press *)
    val () = $EV.prevent_default()
  in if reader_link_at(!_focus_link) then () else () end
  else if _key_is(key_bytes, n, "Escape") then
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
  | Escaped(LDictionary()) => let val () = ui_focus("page") in true end
  | Escaped(_) => true

(* A key while the search panel is open: Enter goes to the next hit
   (Shift+Enter the one before), Escape closes the panel *)
fn _search_key {l:agz}{n:nat} (key_bytes: !$A.arr(byte, l, n), n: int n): void = let
  val shift = (if n >= 2 then $AR.band_g1($AR.low_byte(byte2int0($A.get<byte>(key_bytes, n - 1))), 1) = 1 else false): bool
in
  if _key_is(key_bytes, n, "Enter") then let
      val () = reader_search_step(if shift then ~1 else 1)
    in if _shown("search-nav") then let val () = layer_close(LSearch()) in ui_focus("page") end else () end
  else if _key_is(key_bytes, n, "Escape") then let
      val () = layer_close(LSearch())
    in if _shown("search-nav") then ui_focus("page") else _search_end() end
  else ()
end

(* The contents panel, open on its contents tab *)
fn _toc_open (): void = let
  val () = (case+ reading_get() of
    | @(_, _, chapter, chapter_count) => toc_render((if chapter > 0 then chapter - 1 else 0), chapter_count))
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
fun _on_gestures {count:nat} .<count>. (events: list_vt($GT.gevent, count)): void =
  case+ events of
  | ~list_vt_nil() => ()
  | ~list_vt_cons(event, rest) => let
      val () = (case+ event of
        | ~$GT.GPan(region, distance) => if region = PAGE_REGION then reader_pan(distance / 16) else ()
        | ~$GT.GCommit(region, direction) =>
          if region <> PAGE_REGION then ()
          else let
            val () = _drag_ended()
          in case+ direction of
            | $GP.DLeft() => _right()
            | $GP.DRight() => _left()
            | _ => reader_pan(0)
          end
        | ~$GT.GCancel(region, _) =>
          if region <> PAGE_REGION then ()
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
  | ~BlobBytes(batch_bytes, n) => let
      var cell: gesture_cell = GNone()
      val () = ref_exch_elt<gesture_cell>(_gestures, cell)
      val events = (case+ cell of
        | @GSome(state) => let
            val events = $GD.gestures_feed(state, batch_bytes, n)
            prval () = fold@(cell)
          in events end
        | GNone() => list_vt_nil()): $GT.gevents
      val () = ref_exch_elt<gesture_cell>(_gestures, cell)
      val () = (case+ cell of ~GNone() => () | ~GSome(state) => $GT.gestures_free(state))
      val () = $A.free<byte>(batch_bytes)
    in if !_view = 1 then _on_gestures(events) else $GT.gevents_free(events) end

(* The recognizer, with the page turn's region: horizontal drags, by
   touch or pen only (a mouse drag over the page selects text) *)
fn _gestures_start (): void = let
  val state = $GT.gestures_new()
  val () = $GT.gestures_region(state, PAGE_REGION, ~1, page_turn_axes(), false, false, $GT.DevTouch())
  var cell: gesture_cell = GSome(state)
  val () = ref_exch_elt<gesture_cell>(_gestures, cell)
in case+ cell of ~GNone() => () | ~GSome(old) => $GT.gestures_free(old) end

(* The page's scrolls, numbered, so only the last one's rest counts *)
val _scroll_generation = ref<int>(0)

(* The catalogues: one opened, removed or added, or done (or a click
   outside); a catalogue browsed: a link followed, a book got, Back,
   Close, the next and previous pages, and its search (its button, or
   Enter in its field) *)
fn _wire_catalogues {count:nat} (listeners: regs(count)): regs(count + 3) = let
  val listeners = RCons(listeners, OnEl("catalogues-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val opened = _row_of(clicked, "catalogue-open")
      val removed = _row_of(clicked, "drop-catalogue")
      val add = _is(clicked, "catalogue-add")
      val done = (if _is(clicked, "catalogues-done") then true else _is(clicked, "catalogues-panel")): bool
      val () = _target_free(clicked)
      val () = (if opened >= 0 then catalogue_open(opened)
        else if removed >= 0 then catalogue_remove(removed)
        else if add then catalogue_add()
        else if done then layer_close(LCatalogues())
        else ())
    in 0 end)
  val listeners = RCons(listeners, OnEl("catalogue-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val followed = _row_of(clicked, "feed-link")
      val got = _row_of(clicked, "book-get")
      val back = _is(clicked, "catalogue-back")
      val close = _is(clicked, "catalogue-close")
      val next = _is(clicked, "catalogue-next")
      val previous = _is(clicked, "catalogue-previous")
      val search = _is(clicked, "catalogue-search-go")
      val () = _target_free(clicked)
      val () = (if followed >= 0 then catalogue_follow(followed)
        else if got >= 0 then catalogue_get(got)
        else if back then catalogue_back()
        else if close then catalogue_close()
        else if next then catalogue_next()
        else if previous then catalogue_previous()
        else if search then catalogue_search()
        else ())
    in 0 end)
in RCons(listeners, OnEl("catalogue-search-bar"), "keydown", lam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(key_bytes, n) => let
      val enter = _key_is(key_bytes, n, "Enter")
      val () = $A.free<byte>(key_bytes)
    in if enter then let val () = catalogue_search() in 0 end else 0 end) end

fn _wire_toc {count:nat} (listeners: regs(count)): regs(count + 9) = let
  val listeners = RCons(listeners, OnEl("contents-button"), "click", lam(_) => let val () = _toc_open() in 0 end)
  val listeners = RCons(listeners, OnEl("contents-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val contents_row = _row_of(clicked, "toc-row")
      val bookmark_go = _row_of(clicked, "bookmark-go")
      val bookmark_delete = _row_of(clicked, "bookmark-delete")
      val bookmark_note = _row_of(clicked, "bookmark-edit")
      val print_page = _row_of(clicked, "page-row")
      val () = (if _is(clicked, "contents-close") then layer_close(LContents())
        else if _is(clicked, "contents-tab") then _toc_open()
        else if _is(clicked, "bookmarks-tab") then _bookmarks_open()
        else if _is(clicked, "pages-tab") then _pages_open()
        else if print_page >= 0 then let
          val () = layer_close(LContents())
        in reader_goto_page(print_page) end
        else if bookmark_go >= 0 then let val () = layer_close(LContents()) in _annotation_go(bookmark_go) end
        else if bookmark_delete >= 0 then annot_delete_bookmark(bookmark_delete)
        else if bookmark_note >= 0 then annot_ask_note(bookmark_note, false)
        else if contents_row >= 0 then let
          val () = layer_close(LContents())
        in reader_goto_entry(contents_row) end
        else ())
      val () = _target_free(clicked)
    in 0 end)
  val listeners = RCons(listeners, OnEl("jump-back"), "click", lam(_) => let val () = reader_back() in 0 end)
  val listeners = RCons(listeners, OnEl("next-chapter"), "click", lam(_) => let val () = page_next() in 0 end)
  (* scrolled, the place follows the page, once it rests a moment *)
  val listeners = RCons(listeners, OnEl("page"), "scroll", lam(_) => let
      val () = !_scroll_generation := !_scroll_generation + 1
      val generation = !_scroll_generation
      val () = $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(150)), lam(_) => let
          val () = (if !_scroll_generation = generation then reader_scrolled() else ())
        in $P.ret<int>(0) end))
    in 0 end)
  (* the scrubber: a drag shows where it would go, letting go goes there *)
  val listeners = RCons(listeners, OnEl("scrubber-track"), "pointerdown", lam(h) => let
      val x = _event_x(h)
      val () = !_scrubbing := true
      val () = _chrome_set(true)
    in let val () = reader_scrub_preview(x) in 0 end end)
  val listeners = RCons(listeners, OnDocument(), "pointermove", lam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = _chrome_set(true)
      in let val () = reader_scrub_preview(x) in 0 end end
      else 0)
  val listeners = RCons(listeners, OnDocument(), "pointerup", lam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = !_scrubbing := false
      in let val () = reader_scrub_go(x) in 0 end end
      else 0)
  (* the app hidden (another tab, another app): where the reader is is
     stored *)
  val listeners = RCons(listeners, OnDocument(), "visibilitychange", lam(_) =>
      if !_view = 1 then let val () = reader_save() in 0 end else 0)
in listeners end

fn _wire_annotations {count:nat} (listeners: regs(count)): regs(count + 7) = let
  val listeners = RCons(listeners, OnEl("bookmark-button"), "click", lam(_) => let
      val () = annot_bookmark_toggle(reader_anchor())
    in 0 end)
  val listeners = RCons(listeners, OnDocument(), "selectionchange", lam(_) =>
      if !_view = 1 then let
        val selected = _has_selection()
        val () = ui_show("selection-toolbar", selected)
        val () = (if selected then _lookup_update() else ())
      in 0 end else 0)
  val listeners = RCons(listeners, OnEl("selection-toolbar"), "click", lam(h) => let
      val clicked = _target(h)
      val highlight = _is(clicked, "selection-highlight")
      val orange = _is(clicked, "selection-orange")
      val underline = _is(clicked, "selection-underline")
      val note = _is(clicked, "selection-note")
      val copy = _is(clicked, "selection-copy")
      val search = _is(clicked, "selection-search")
      val define = _is(clicked, "selection-define")
      val () = _target_free(clicked)
      val () = (if highlight then let val _ = annot_highlight(0) in () end
        else if orange then let val _ = annot_highlight(1) in () end
        else if underline then let val _ = annot_highlight(2) in () end
        else if note then annot_ask_note(annot_highlight(0), true)
        else if copy then _copy_selection()
        else if search then _search_selection()
        else if define then dict_show()
        else ())
    in let val () = ui_show("selection-toolbar", false) in 0 end end)
  (* a word's dictionary entry: closed, or looked up online instead *)
  val listeners = RCons(listeners, OnEl("dictionary-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val close = _is(clicked, "dictionary-close")
      val online = _is(clicked, "dictionary-online")
      val () = _target_free(clicked)
      val () = (if close then layer_close(LDictionary()) else if online then layer_close(LDictionary()) else ())
    in if close then let val () = ui_focus("page") in 0 end else 0 end)
  val listeners = RCons(listeners, OnEl("annotations-button"), "click", lam(_) => let
      val () = annot_render()
      val () = layer_open(LAnnotations())
    in let val () = ui_focus("annotations-close") in 0 end end)
  val listeners = RCons(listeners, OnEl("annotations-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val go_row = _row_of(clicked, "highlight-go")
      val note_row = _row_of(clicked, "highlight-edit")
      val delete_row = _row_of(clicked, "highlight-delete")
      val close = _is(clicked, "annotations-close")
      val export_asked = _is(clicked, "annotations-export")
      val share_asked = _is(clicked, "annotations-share")
      val filter = (if _is(clicked, "filter-all") then ~1 else if _is(clicked, "filter-yellow") then 0
        else if _is(clicked, "filter-orange") then 1 else if _is(clicked, "filter-underlined") then 2 else ~2): int
      val () = _target_free(clicked)
      val () = (if close then layer_close(LAnnotations())
        else if export_asked then _export(false)
        else if share_asked then _export(true)
        else if filter >= ~1 then annot_filter_set(filter)
        else if go_row >= 0 then let val () = layer_close(LAnnotations()) in _annotation_go(go_row) end
        else if note_row >= 0 then annot_ask_note(note_row, false)
        else if delete_row >= 0 then annot_delete_highlight(delete_row)
        else ())
    in 0 end)
  (* a note opened over the page: gone to, or closed *)
  val listeners = RCons(listeners, OnEl("footnote"), "click", lam(h) => let
      val clicked = _target(h)
      val go = _is(clicked, "footnote-go")
      val close = _is(clicked, "footnote-close")
      val () = _target_free(clicked)
      val () = (if go then let
          val () = layer_close(LNote())
          val () = reader_note_go()
        in ui_focus("page") end
        else if close then let
          val () = layer_close(LNote())
        in ui_focus("page") end
        else ())
    in 0 end)
in listeners end

fn _wire_search {count:nat} (listeners: regs(count)): regs(count + 4) = let
  val listeners = RCons(listeners, OnEl("search-button"), "click", lam(_) => let
      val () = (if layer_is_open(LSearch()) then layer_close(LSearch()) else _search_open())
    in 0 end)
  (* the field is made again for a selection's search: its events are
     taken on the panel *)
  val listeners = RCons(listeners, OnEl("search-panel"), "input", lam(_) => let val () = _search_input() in 0 end)
  val listeners = RCons(listeners, OnEl("search-panel"), "click", lam(h) => let
      val clicked = _target(h)
      val hit = _row_of(clicked, "search-hit")
      val close = _is(clicked, "search-close")
      val () = _target_free(clicked)
      val () = (if close then _search_end()
        else if hit >= 0 then let
          val () = layer_close(LSearch())
        in reader_search_go(hit) end
        else ())
    in 0 end)
  val listeners = RCons(listeners, OnEl("search-nav"), "click", lam(h) => let
      val clicked = _target(h)
      val previous = _is(clicked, "search-previous")
      val next = _is(clicked, "search-next")
      val close = _is(clicked, "search-nav-close")
      val () = _target_free(clicked)
      val () = (if previous then reader_search_step(~1)
        else if next then reader_search_step(1)
        else if close then _search_end()
        else ())
    in 0 end)
in listeners end

fn _wire_reader {count:nat} (listeners: regs(count)): regs(count + 13) = let
  val listeners = RCons(listeners, OnEl("back-to-library"), "click", lam(_) => let val () = _show_library() in 0 end)
  val listeners = RCons(listeners, OnEl("previous-page"), "click", lam(_) => let val () = _hint_hide() in let val () = page_prev() in 0 end end)
  val listeners = RCons(listeners, OnEl("next-page"), "click", lam(_) => let val () = _hint_hide() in let val () = page_next() in 0 end end)
  val listeners = RCons(listeners, OnEl("page"), "click", lam(h) => let
      val clicked = _target(h)
      val node = _row_of(clicked, "c")
      val x = _target_x(clicked)
      val y = _target_y(clicked)
      val () = _target_free(clicked)
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
  val listeners = RCons(listeners, OnEl("page"), "contextmenu", lam(h) => let
      val clicked = _target(h)
      val node = _row_of(clicked, "c")
      val () = _target_free(clicked)
    in
      if node < 0 then 0
      else if reader_image_at(node) then let val () = $EV.prevent_default() in 0 end
      else 0
    end)
  val listeners = RCons(listeners, OnEl("image-viewer"), "click", lam(h) => let
      val clicked = _target(h)
      val close = _is(clicked, "image-close")
      val () = _target_free(clicked)
    in
      if close then let
        val () = layer_close(LImage())
      in let val () = ui_focus("page") in 0 end end
      else 0
    end)
  (* a link within the book, focused from the keyboard, is followed with
     Enter *)
  val listeners = RCons(listeners, OnEl("page"), "focusin", lam(h) => let
      val clicked = _target(h)
      val node = _row_of(clicked, "c")
      val () = _target_free(clicked)
      val () = !_focus_link := node
    in 0 end)
  val listeners = RCons(listeners, OnEl("page"), "focusout", lam(_) => let val () = !_focus_link := ~1 in 0 end)
  val listeners = RCons(listeners, OnDocument(), "keydown", lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(key_bytes, n) => let
          val escape = _key_is(key_bytes, n, "Escape")
          val () = (if (if escape then _escape_overlay() else false) then ()
            else if !_view <> 1 then ()
            else if _shown("dialog") then ()
            else if layer_is_open(LSearch()) then _search_key(key_bytes, n)
            else _reader_key(key_bytes, n))
          val () = $A.free<byte>(key_bytes)
        in 0 end)
  (* the wheel turns a page, then pauses a quarter second *)
  val listeners = RCons(listeners, OnEl("page"), "wheel", lam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(wheel_bytes, n) =>
        if n < 8 then let val () = $A.free<byte>(wheel_bytes) in 0 end
        else let
          val delta_y = _int32_at(wheel_bytes, 4)
          val () = $A.free<byte>(wheel_bytes)
        in
          if !_wheel_busy then 0
          else if delta_y = 0 then 0
          else let
            val () = !_wheel_busy := true
            val () = (if delta_y > 0 then _next() else _previous())
            val () = $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(250)), lam(_) => let
                val () = !_wheel_busy := false
              in $P.ret<int>(0) end))
          in 0 end
        end)
  (* a tap on the footer's readout shows the next, and keeps it *)
  val listeners = RCons(listeners, OnEl("footer-readout"), "click", lam(_) => let
      val () = reader_readout_next()
      val () = set_save(lib_state_get())
    in 0 end)
  (* pointer events for the gestures: a horizontal drag turns the page
     (the reader view is the stable root; the page is region 1) *)
  val listeners = RCons(listeners, OnGestures("reader"), "gestures", lam(h) => let
      val () = _gesture_batch(h)
    in 0 end)
  (* a resize lays the chapter out again, once it settles *)
  val listeners = RCons(listeners, OnWindow(), "resize", lam(_) => let
      val () = !_resize_generation := !_resize_generation + 1
      val generation = !_resize_generation
      val () = $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(200)), lam(_) => let
          val () = (if !_resize_generation = generation then (if !_view = 1 then reader_relayout() else ()) else ())
        in $P.ret<int>(0) end))
    in 0 end)
  (* the browser's back button: out of the reader *)
  val () = $NAV.set_popstate_callback(lam(_) => let
      val () = (if !_view = 1 then _show_library() else ())
    in 0 end)
in listeners end

(* ============================================================
   Startup
   ============================================================ *)

implement main0 () = let
  val () = app_build()
  val () = _gestures_start()
  (* every listener, in one table: each one's id is its place in it *)
  val listeners = _wire_catalogues(_wire_search(_wire_annotations(_wire_toc(_wire_reader(_wire_settings(undo_listen(modal_listen(_wire_library(RNil())))))))))
  (* files handed to the app from outside it (an Android intent) *)
  val listeners = RCons(listeners, OnExternalFiles(), "files", lam(h) => let
      val () = (if !_view = 1 then _show_library() else ())
      val () = import_external(h)
    in 0 end)
  val () = ui_listen_all(listeners)
  val () = $P.discard<int>(reader_speed_load())
  val () = _hint_load()
  val () = lib_install_hint_load()
  val () = stats_load()
  val () = $P.discard<int>(dict_load())
  val () = $P.discard<int>(catalogue_load())
  val () = dict_when_read(lam () => if !_view = 1 then _lookup_update() else ())
  (* nothing is shown until the view kept by the last run is known: a
     reader who was in a book comes back to it, not to the library *)
  val () = ui_show("library", false)
  val loaded = $P.and_then<int><int>(set_load(), lam(state) => let
      val () = lib_sort_label($AR.band_int_int(state, 7))
    in
      $P.and_then<int><int>(lib_load(), lam(_) => let
        val () = lib_state_set(state)
        val () = lib_render()
      in _view_restore() end)
    end)
in $P.discard<int>(loaded) end
