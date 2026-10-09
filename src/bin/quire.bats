#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use gestures as G

staload "book.sats"
staload "pages.sats"
staload "ui.sats"
staload "notice.sats"
staload "storage.sats"
staload "layer.sats"
staload "app.sats"
staload "style.sats"
staload "modal.sats"
staload "undo.sats"
staload "backup.sats"
staload "library.sats"
staload "paths.sats"
staload "settings.sats"
staload "import.sats"
staload "reader.sats"
staload "toc.sats"
staload "annot.sats"
staload "mem.sats"
staload "stats.sats"
staload "dictionary.sats"
staload "clock.sats"
staload "sync.sats"
staload "catalogue.sats"
staload "catalogues.sats"
staload "platform.sats"
staload "screen_controls.sats"
staload "sharing.sats"
staload "read_aloud.sats"
staload "narration.sats"
staload "back.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
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
staload GS = "gestures/src/source.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload BE = "wasm.bats-packages.dev/bridge/src/external.sats"
staload BW = "wasm.bats-packages.dev/bridge/src/build_watch.sats"
staload ME = "wasm.bats-packages.dev/bridge/src/media.sats"
staload BB = "wasm.bats-packages.dev/bridge/src/back_button.sats"

(* ============================================================
   State
   ============================================================ *)

(* What is shown: the library or the reader *)
datatype view = LibraryView | ReaderView

val _view = ref<view>(LibraryView())

(* Whether the reader is shown *)
fn _in_reader (): bool = case+ !_view of ReaderView() => true | LibraryView() => false

(* Whether the book open reads right to left *)
fn _rtl (): bool = case+ reader_direction() of RightToLeft() => true | LeftToRight() => false
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
(* The gesture recognizer's state and its pointer source (linear, so
   they are taken out of their cell and put back); and whether a drag
   has just ended, so that the click the browser sends after it is not
   also a tap *)
datavtype gesture_cell = GNone | GSome of ($GT.gstate, $GS.source)
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
(* The Trash's dictionaries are listed while the Trash is the shelf shown *)
fn _trash_dictionaries (): void = dict_trash_render(same_shelf(lib_shelf_get(), Trash()))

fn _harm_clicked (clicked: !target): Option_vt(harm) =
  if _is(clicked, ui_harm_id(HEmptyTrash())) then Some_vt(HEmptyTrash()) else None_vt()

(* The control clicked is, of a listener's own (ui.bats decodes it) *)
fn _settings_control (clicked: !target): $R.option(settings_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_settings_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _retry_control (clicked: !target): $R.option(retry_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_retry_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _library_view_control (clicked: !target): $R.option(library_view_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_library_view_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _card_menu_control (clicked: !target): $R.option(card_menu_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_card_menu_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _collections_control (clicked: !target): $R.option(collections_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_collections_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _book_info_control (clicked: !target): $R.option(book_info_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_book_info_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _library_search_control (clicked: !target): $R.option(library_search_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_library_search_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _library_menu_control (clicked: !target): $R.option(library_menu_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_library_menu_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _stats_control (clicked: !target): $R.option(stats_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_stats_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _dictionaries_control (clicked: !target): $R.option(dictionaries_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_dictionaries_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _sync_screen_control (clicked: !target): $R.option(sync_screen_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_sync_screen_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _sync_offer_control (clicked: !target): $R.option(sync_offer_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_sync_offer_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _typography_control (clicked: !target): $R.option(typography_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_typography_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _sheet_tab (clicked: !target): $R.option(sheet_tab) =
  case+ clicked of
  | Target(bytes, n, _) => ui_sheet_tab(bytes, n, 10)
  | NoTarget() => $R.none()

fn _catalogues_control (clicked: !target): $R.option(catalogues_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_catalogues_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _catalogue_control (clicked: !target): $R.option(catalogue_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_catalogue_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _contents_control (clicked: !target): $R.option(contents_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_contents_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _selection_control (clicked: !target): $R.option(selection_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_selection_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _dictionary_control (clicked: !target): $R.option(dictionary_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_dictionary_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _annotations_control (clicked: !target): $R.option(annotations_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_annotations_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _footnote_control (clicked: !target): $R.option(footnote_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_footnote_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _search_panel_control (clicked: !target): $R.option(search_panel_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_search_panel_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _search_nav_control (clicked: !target): $R.option(search_nav_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_search_nav_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _image_viewer_control (clicked: !target): $R.option(image_viewer_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_image_viewer_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _about_control (clicked: !target): $R.option(about_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_about_control(bytes, n, 10)
  | NoTarget() => $R.none()

fn _update_control (clicked: !target): $R.option(update_control) =
  case+ clicked of
  | Target(bytes, n, _) => ui_update_control(bytes, n, 10)
  | NoTarget() => $R.none()

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
fn _view_save (book_key: int, id_high: int, id_low: int): void = let
  val value = $A.alloc<byte>(12)
  val () = $A.write_i32(value, 0, book_key)
  val () = $A.write_i32(value, 4, id_high)
  val () = $A.write_i32(value, 8, id_low)
  val @(value_frozen, value_bytes) = $A.freeze<byte>(value)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_view_key())
  (* ignored: a view not stored only opens the library next time *)
  val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 4, value_bytes, 12), llam(_) => ())
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(value_frozen, value_bytes) end

(* The library's search, kept across a reload (and the app killed and
   started again) as the view is: "query", the words as typed, none
   when the search is empty (#302) *)
fn _query_key (): [l:agz] $A.arr(byte, l, 5) = let
  val key = $A.alloc<byte>(5)
  val () = $A.write_text(key, 0, $A.text_lit("query"), 5)
in key end

(* text[0, text_len), copied into an array of its own *)
fn _text_copy {l:agz}{size:nat}{text_len:pos | text_len <= size; text_len < 256}
  (text: !$A.arr(byte, l, size), text_len: int text_len): [copy_loc:agz] $A.arr(byte, copy_loc, text_len) = let
  val copy = $A.alloc<byte>(text_len)
  fun fill {copy_loc:agz}{j:nat | j <= text_len} .<text_len - j>. (text: !$A.arr(byte, l, size), copy: !$A.arr(byte, copy_loc, text_len), j: int j): void =
    if j >= text_len then () else let val () = $A.set<byte>(copy, j, $A.get<byte>(text, j)) in fill(text, copy, j + 1) end
  val () = fill(text, copy, 0)
in copy end

(* Keeps the search query[0, query_len) under "query" (an empty one is
   none, and so is one of 256 bytes or more, as the library takes it) *)
fn _query_save {l:agz}{size:nat}{query_len:nat | query_len <= size} (query: !$A.arr(byte, l, size), query_len: int query_len): void = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_query_key())
  val () = (if query_len > 0 then (if query_len < 256 then let
      val @(value_frozen, value_bytes) = $A.freeze<byte>(_text_copy(query, query_len))
      (* ignored: a search not stored only opens the library unsearched *)
      val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 5, value_bytes, query_len), llam(_) => ())
    in release_bytes(value_frozen, value_bytes) end
    (* ignored: a search not forgotten is only shown again next time *)
    else $P.finish<$IDB.stored>($IDB.idb_delete(key_bytes, 5), llam(_) => ()))
    else $P.finish<$IDB.stored>($IDB.idb_delete(key_bytes, 5), llam(_) => ()))
in release_bytes(key_frozen, key_bytes) end

(* The search kept by the last run, in its field and the library's *)
fn _query_restore (): $P.promise(int, $P.Chained) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_query_key())
  val stored = $IDB.idb_get(key_bytes, 5)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><int>(stored, llam(found) =>
    case+ lookup_bytes(found) of
    | ~NothingStored() => $P.ret<int>(0)
    (* the library unsearched, as when none is kept *)
    | ~StoredUnreadable() => $P.ret<int>(0)
    | ~StoredBytes(query, query_len) =>
      if query_len >= 256 then let val () = $A.free<byte>(query) in $P.ret<int>(0) end
      else let
        val () = ui_attr_buf("library-search", AValue, _text_copy(query, query_len), query_len)
        val () = ui_show("library-search-clear", true)
        val () = lib_query_set(query, query_len)
      in $P.ret<int>(0) end)
end

(* While a book is open the auto theme follows the clock: night is
   checked each minute (22:00 to 07:00, local_time.bats), as well as at
   each page turn. Each opening of the reader is a watch of its own,
   numbered; leaving it ends the watch *)
val _night_watch_number = ref<int>(0)

(* A minute, in milliseconds *)
#define NIGHT_CHECK_EVERY 60000
(* How many minutes a watch checks, at most (about two years) *)
#define NIGHT_CHECKS_MAX 1000000

fun _night_watch {checks:nat} .<checks>. (watch: int, checks: int checks): void =
  if checks <= 0 then ()
  else $P.finish<Int>($P.vow($TM.timer_set(NIGHT_CHECK_EVERY)), llam(_) =>
    if watch <> !_night_watch_number then ()
    else let
      val () = set_theme_recheck()
    in _night_watch(watch, checks - 1) end)

fn _night_watch_start (): void = let
  val () = !_night_watch_number := !_night_watch_number + 1
in _night_watch(!_night_watch_number, NIGHT_CHECKS_MAX) end

fn _night_watch_stop (): void = !_night_watch_number := !_night_watch_number + 1

(* The library shown. A reload comes back here, unless save_view is false:
   at start-up with a library that could not be read yet (Try again
   waits) the view kept by the last run is not written over, since the
   retry opens the book it names (#374) *)
fn _library_shown (save_view: bool): void = let
  val () = !_view := LibraryView()
  (* the library is not the immersive screen: the system bars are there *)
  val () = screen_immersive_set(false)
  val () = _night_watch_stop()
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
  (* nothing is read aloud from the library *)
  val () = aloud_stop()
  val () = ui_show("library", true)
  (* a reload now comes back here *)
  val () = (if save_view then _view_save(~1, 0, 0) else ())
  val () = reader_search_stop()
  val () = reader_stack_clear()
  (* a page turn under way ends with the book *)
  val () = reader_turn_settle()
  val () = reader_timer_stop()
  (* the narration stops with the book *)
  val () = narration_close()
  val () = window_close()
  (* what sync brings for the book now goes to its stored record, and
     no place of another device's is offered *)
  val () = annot_close()
  val () = sync_book_closed()
  val () = back_view_set(AtLibrary())
in lib_render() end

fn _show_library (): void = _library_shown(true)

(* The reader's bars: shown, and hidden again after 5 seconds, unless a
   reader panel is open then: the bars stay under its scrim, so the
   button that opened it is there to have the focus back when it
   closes (they go with the next turn or tap) *)
fn _chrome_set_off (): void = let
  val () = !_chrome := false
  val () = ui_attr("reader", AClass, "rv chrome-off")
in screen_immersive_set(_in_reader()) end

fn _chrome_set (shown: bool): void = let
  (* bringing the bars up leaves the place a jump landed on: the back
     button goes *)
  val () = (if shown && ~(!_chrome) then reader_stack_clear() else ())
  val () = !_chrome := shown
  val () = (if shown then ui_attr("reader", AClass, "rv") else ui_attr("reader", AClass, "rv chrome-off"))
  val () = !_chrome_generation := !_chrome_generation + 1
  val generation = !_chrome_generation
  (* the system bars follow: away with the reader's own bars (the
     immersive reading screen, quire#348), there with them *)
  val () = screen_immersive_set(~shown && _in_reader())
in
  if shown then $P.finish<Int>($P.vow($TM.timer_set(5000)), llam(_) =>
      if !_chrome_generation = generation then (if layer_reader_blocked() then () else _chrome_set_off()) else ())
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
  $P.finish<$IDB.lookup>(stored, llam(found) => let
    val () = (case+ lookup_bytes(found) of
      | ~NothingStored() => !_hint_seen := false
      (* taken as shown: a hint each session would nag *)
      | ~StoredUnreadable() => ()
      | ~StoredBytes(value_bytes, _) => $A.free<byte>(value_bytes))
  in () end)
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
    (* ignored: a hint not stored as shown only shows once more *)
    val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 4, value_bytes, 1), llam(_) => ())
    val () = release_bytes(key_frozen, key_bytes)
    val () = release_bytes(value_frozen, value_bytes)
    val () = ui_show("turn-hint", true)
  in
    $P.finish<Int>($P.vow($TM.timer_set(8000)), llam(_) => _hint_hide())
  end

(* What opened a book: the reader (a card, a key), whose focus goes to
   the page, so a screen reader reads on from there; or the app as it
   starts, back where the last run was, where nothing had the focus to
   move, and a ring around the page would be all it showed (#302) *)
datatype opening_cause = ReaderChose | LastRunKept

fn _show_reader (cause: opening_cause): void = let
  val () = !_view := ReaderView()
  val () = _night_watch_start()
  val () = ui_show("library", false)
  val () = layer_close(LBookInfo())
  val () = ui_show("reader", true)
  (* A reader does not touch the screen for a page's length: it stays
     awake while the book is open *)
  val () = $WN.keep_awake(true)
  (* Back leaves the reader (back.bats) *)
  val () = back_view_set(InReader())
  val () = _chrome_set(true)
in
  case+ cause of
  | ReaderChose() => ui_focus("page")
  | LastRunKept() => ()
end

(* Opens library book i where it was left *)
(* source[0, count) copied to destination[at, at + count) *)
fun _copy_from_to {source_loc,destination_loc:agz}{source_size,destination_size:nat}{count:nat | count <= source_size}{at:nat | at + count <= destination_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, destination: !$A.arr(byte, destination_loc, destination_size), at: int at, j: int j): void =
  if j >= count then ()
  else let val () = $A.set<byte>(destination, at + j, $A.get<byte>(source, j)) in _copy_from_to(source, count, destination, at, j + 1) end

fn _copy_into {source_loc,destination_loc:agz}{source_size,destination_size:nat}{count:nat | count <= source_size}{at:nat | at + count <= destination_size}
  (source: !$A.arr(byte, source_loc, source_size), count: int count, destination: !$A.arr(byte, destination_loc, destination_size), at: int at): void =
  _copy_from_to(source, count, destination, at, 0)

(* The selection shared, cited by the open book: "Author, Title" (as
   the export's) *)
fn _share_selection (): void = let
  val book = lib_index_of_key(open_key_get())
  val @(title, title_len) = lib_text(book, TitleText())
  val @(author, author_len) = lib_text(book, AuthorText())
  val citation = $A.alloc<byte>(520)
  val () = _copy_into(author, author_len, citation, 0)
  val () = $A.set<byte>(citation, author_len, $A.int2byte(44))
  val () = $A.set<byte>(citation, author_len + 1, $A.int2byte(32))
  val () = _copy_into(title, title_len, citation, author_len + 2)
  val () = $A.free<byte>(title)
  val () = $A.free<byte>(author)
in share_selection(citation, author_len + 2 + title_len) end

(* A book's saved place, gone to as it opens: when its chapter could not
   be shown there is no page to stay on, so the reader goes back to the
   library and the banner says why *)
(* How a book's opening ended: its chapter shown, the library shown
   instead (it said why), or the chapter not shown *)
datatype opened = OpenedShown | OpenedInLibrary | OpenedNotShown

implement $P.dispose<opened>(_) = ()

implement $P.dispose<import_outcome>(outcome) = import_outcome_free(outcome)

fn _opened_of (outcome: load_outcome): opened =
  if load_shown(outcome) then OpenedShown() else OpenedNotShown()

fn _opened_checked (result: opened): void =
  case+ result of
  | OpenedShown() => ()
  | OpenedInLibrary() => ()
  | OpenedNotShown() => let
    val () = (if _in_reader() then _show_library() else ())
  in notice_say_part(reader_chapter_asked()) end

fn _open_book {book:int} (book: int book, cause: opening_cause): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) =>
    case+ book_numbers.shelf of
    | Trash() => let
      val () = modal_inform("In the Trash")
    in modal_text_lit("Restore this book from the Trash to read it.") end
    | Archived() => let
      val () = modal_inform("Archived")
    in modal_text_lit("This book is archived. Import its file again to read it.") end
    | _ => let
      val () = _show_reader(cause)
      val () = _hint_offer()
      (* what another book was reading aloud stops *)
      val () = aloud_stop()
      val () = reader_stack_clear()
      (* the Ruby row waits for this book's first ruby *)
      val () = reader_ruby_forget()
      val () = reader_timer_start()
      (* a reload now comes back to this book *)
      val () = _view_save(book_numbers.key, book_numbers.id_high, book_numbers.id_low)
      val () = ui_text("chapter-title", "Loading...")
      (* no page is shown until this book's is: the last book's stays out
         of the indicator *)
      val () = ui_clear("indicator-title")
      val () = ui_clear("indicator-label")
      val () = ui_clear("indicator-pages")
      val chapter = book_numbers.chapter
      val page = book_numbers.page
      val pages = book_numbers.pages
      val anchor = book_numbers.anchor
      (* never read: nothing moved, no minute spent *)
      val unread = (if chapter = 0 then (if page = 0 then (if book_numbers.place_modified = 0 then book_numbers.minutes_read = 0 else false) else false) else false): bool
      val id_high = book_numbers.id_high
      val id_low = book_numbers.id_low
      (* the other devices' place and annotations, brought *)
      val () = sync_book_opened(book_numbers.key)
    in
      (* the annotations' load deals with its own value *)
      if open_key_get() = book_numbers.key then
        $P.finish<opened>($P.and_then<int><opened>(annot_load(id_high, id_low), llam(_) =>
          $P.and_then<load_outcome><opened>(reader_open_at(chapter, page, pages, anchor, unread), llam(outcome) => $P.ret<opened>(_opened_of(outcome)))), llam(result) =>
          _opened_checked(result))
      else
        $P.finish<opened>($P.and_then<book_opening><opened>(open_stored(book_numbers.key, id_high, id_low), llam(opening) =>
          case+ opening of
          | BookFileMissing() => let
              val () = _show_library()
              val () = notice_say(BookFileLost())
            in $P.ret<opened>(OpenedInLibrary()) end
          (* a passing failure of storage: importing again is not the fix *)
          | BookFileUnreadable() => let
              val () = _show_library()
              val () = notice_say(BookStorageFailed())
            in $P.ret<opened>(OpenedInLibrary()) end
          | BookOpened() => $P.and_then<int><opened>(annot_load(id_high, id_low), llam(_) =>
            $P.and_then<load_outcome><opened>(reader_open_at(chapter, page, pages, anchor, unread), llam(outcome) => $P.ret<opened>(_opened_of(outcome))))), llam(result) =>
          _opened_checked(result))
    end

(* The view kept by the last run: its book opened again, on its page,
   when it is still on a shelf it is read from; else the library *)
fn _view_restore (): $P.promise(int, $P.Chained) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_view_key())
  val stored = $IDB.idb_get(key_bytes, 4)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><int>(stored, llam(found) => let
    (* the book is found by its id: its key is only the number it was given
       this session, and a library read again gives other numbers; a view
       kept before the id was (4 bytes) is found by its key *)
    val book = (case+ lookup_bytes(found) of
      | ~NothingStored() => ~1
      (* the library, as when none is kept: only where it opens is lost *)
      | ~StoredUnreadable() => ~1
      | ~StoredBytes(value_bytes, n) =>
        if n < 4 then let val () = $A.free<byte>(value_bytes) in ~1 end
        else let
          val stored_key = _int32_at(value_bytes, 0)
          val stored_high = (if n >= 12 then _int32_at(value_bytes, 4) else 0): Int
          val stored_low = (if n >= 12 then _int32_at(value_bytes, 8) else 0): Int
          val () = $A.free<byte>(value_bytes)
        in
          if stored_key < 0 then ~1
          else if n >= 12 then lib_index_of_id(stored_high, stored_low)
          else lib_index_of_key(stored_key)
        end): [index:int | index >= ~1] int index
    val readable = (if book < 0 then false else (case+ lib_nums(book) of
      | ~$R.none() => false
      | ~$R.some(book_numbers) => (case+ book_numbers.shelf of OnShelf() => true | Hidden() => true | _ => false))): bool
  in
    if readable then let val () = _open_book(book, LastRunKept()) in $P.ret<int>(0) end
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
fn _set_shelf {book:int} (book: int book, shelf: shelf): void = lib_set_shelf(book, shelf)

(* Deletes the stored data of book (id_high, id_low) under the key of letter *)
fn _idb_delete {letter:nat | letter < 256} (letter: int letter, id_high: int, id_low: int): void = let
  val key = lib_key(letter, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  (* ignored: a delete that fails leaves bytes nothing reads *)
  val () = $P.finish<$IDB.stored>($IDB.idb_delete(key_bytes, 15), llam(_) => ())
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
      val () = _set_shelf(book, Archived())
    in
      $P.finish<settled>(undo_offer(BookArchived()), llam(how) =>
        case+ how of
        | Undone() => let
            val index = lib_index_of_key(key)
          in if index >= 0 then _set_shelf(index, was) else () end
        (* the file goes only if the book is still archived (it may have
           been restored meanwhile, by importing it again) *)
        | Final() => let
            val index = lib_index_of_key(key)
          in
            if index < 0 then ()
            else (case+ lib_nums(index) of
              | ~$R.none() => ()
              | ~$R.some(numbers_now) =>
                if same_shelf(numbers_now.shelf, Archived()) then let
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
      val was_hidden = same_shelf(was, Hidden())
      val () = _set_shelf(book, (if was_hidden then OnShelf() else Hidden()): shelf)
    in
      $P.finish<settled>(undo_offer(if was_hidden then BookUnhidden() else BookHidden()), llam(how) =>
        case+ how of
        | Undone() => let
            val index = lib_index_of_key(key)
          in if index >= 0 then _set_shelf(index, was) else () end
        | Final() => ())
    end


(* The book actions' labels (in the book menu or the info view) for a
   book on shelf shelf: in the Trash, Restore only (a book leaves the Trash
   for good only when it is emptied); elsewhere Hide or Unhide, Archive
   or Restore, and Move to Trash *)
fn _shelf_labels {hide_len,archive_len,trash_len:pos | hide_len < 256; archive_len < 256; trash_len < 256}
  (hide: string hide_len, archive: string archive_len, trash: string trash_len, shelf: shelf): void =
  case+ shelf of
  | Trash() => let
    val () = ui_text(hide, "Restore")
    val () = ui_show(archive, false)
  in ui_show(trash, false) end
  | _ => let
    val () = (if same_shelf(shelf, Hidden()) then ui_text(hide, "Unhide") else ui_text(hide, "Hide"))
    val () = ui_show(archive, true)
    val () = (if same_shelf(shelf, Archived()) then ui_text(archive, "Restore") else ui_text(archive, "Archive"))
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
      val @(title, title_len) = lib_text(book, TitleText())
      val () = ui_text_buf("book-info-title", title, title_len)
      val @(author, author_len) = lib_text(book, AuthorText())
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
         Reading Life shows them), once it has been: on this device and
         the others sync knows of *)
      val minutes_read = book_numbers.minutes_read + book_numbers.minutes_elsewhere
      val pages_read = book_numbers.pages_read + book_numbers.pages_elsewhere
      val () = (if minutes_read > 0 then let
          val duration = $A.alloc<byte>(32)
          val duration_len = stats_duration_text(duration, minutes_read)
        in ui_text_buf("info-time", duration, duration_len) end
        else ui_text("info-time", "Not yet"))
      val () = (if minutes_read > 0 then let
          val speed = $A.alloc<byte>(32)
          val speed_len = $S.int_to_str(speed, 0, 32, _per_hour(pages_read, minutes_read))
          val () = $A.write_text(speed, speed_len, $A.text_lit(" pages an hour"), 14)
        in ui_text_buf("info-speed", speed, speed_len + 14) end
        else ())
      val () = ui_show("info-speed-row", minutes_read > 0)
      val () = _shelf_labels("book-info-hide", "book-info-archive", "book-info-trash", book_numbers.shelf)
      val () = ui_src_empty("book-info-cover")
      val () = (if is_image(book_numbers.cover) then lib_show_cover_in("book-info-cover", book_numbers.id_high, book_numbers.id_low, book_numbers.cover) else ())
      (* a book without a cover shows none, not a broken image *)
      val () = ui_show("book-info-cover", is_image(book_numbers.cover))
      val () = lib_a11y_show(book_numbers.id_high, book_numbers.id_low)
      val () = layer_open(LBookInfo())
    in ui_focus("book-info-back") end

(* What a book menu or info view action does: hide, unhide or (from the
   Trash) restore; archive, or say how to restore; move to the Trash *)
datatype book_action = HideOrRestore | Archive | MoveToTrash

(* The action on the book *)
fn _book_action {book:int} (book: int book, action: book_action): void =
  case+ lib_nums(book) of
  | ~$R.none() => ()
  | ~$R.some(book_numbers) =>
    (case+ action of
    | HideOrRestore() =>
      (case+ book_numbers.shelf of Trash() => _set_shelf(book, OnShelf()) | _ => _hide_toggle(book))
    | Archive() =>
      (case+ book_numbers.shelf of
       | Archived() => let
           val () = modal_inform("Restore")
         in modal_text_lit("To restore this book, import its file again.") end
       | Trash() => ()
       | _ => _archive(book))
    | MoveToTrash() =>
      (case+ book_numbers.shelf of
       | Trash() => ()
       | _ => let
           val () = layer_close(LBookInfo())
         in lib_trash(book) end))

(* ============================================================
   Settings
   ============================================================ *)

(* The page's fonts changed as they loaded: the open chapter's pages are
   counted again *)
fn _fonts_arrived (): void =
  if _in_reader() then reader_relayout() else ()

(* The chapter laid out again once the area has settled: a resize, or
   the app's bars shown or hidden (the latest asks, the earlier are
   dropped) *)
fn _relayout_settled (): void = let
  val () = !_resize_generation := !_resize_generation + 1
  val generation = !_resize_generation
in
  $P.finish<Int>($P.vow($TM.timer_set(200)), llam(_) =>
    if !_resize_generation = generation then (if _in_reader() then reader_relayout() else ()) else ())
end

(* The same, for the app's bars shown or hidden: bars the system brought
   back stay until a page is turned *)
fn _relayout_for_bars (): void = let
  val () = !_resize_generation := !_resize_generation + 1
  val generation = !_resize_generation
in
  $P.finish<Int>($P.vow($TM.timer_set(200)), llam(_) =>
    if !_resize_generation = generation then (if _in_reader() then reader_relayout_for_bars() else ()) else ())
end

fn _settings_changed (): void = let
  val () = set_apply(lib_state_get())
in if _in_reader() then reader_relayout() else () end

(* The settings, applied (a reset, or its Undo): their sliders and
   everything they change, the screen's brightness and lock, and
   reading aloud's speed and voice *)
fn _settings_apply (): void = let
  val () = set_sliders()
  val () = _settings_changed()
  val () = screen_controls_apply()
in aloud_choices_show() end

(* The settings reset, offering Undo: applied now, and again when
   they are put back *)
fn _settings_reset (): void = let
  val how = set_reset()
  val () = _settings_apply()
in
  $P.finish<settled>(how, llam(settling) =>
    case+ settling of
    | Undone() => _settings_apply()
    | Final() => ())
end

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
  | ~$R.some(selection) => let val () = $BD.blob_free(selection) in true end

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
   (DictReading), when the reader is still shown: again times more at
   most *)
fun _lookup_update {again:nat} .<again>. (again: int again): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(selection) => let
      val selection_len = $BD.blob_len(selection)
    in
      if selection_len <= 0 then $BD.blob_free(selection)
      else if selection_len > 4096 then $BD.blob_free(selection)
      else let
        val text = $A.alloc<byte>(selection_len)
        val () = $BD.blob_read(selection, 0, text, selection_len)
        val () = $BD.blob_free(selection)
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
        val found = (case+ dict_find(language, language_len, word, word_len) of
          | ~DictFound() => true
          | ~DictMissing() => false
          | ~DictReading(reading) => let
              val () = $P.finish<bool>(reading, llam(opened) =>
                if ~opened then ()
                else if again <= 0 then ()
                else if _in_reader() then _lookup_update(again - 1)
                else ())
            in false end): bool
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
      val selection_len = $BD.blob_len(selection)
    in
      if selection_len <= 0 then $BD.blob_free(selection)
      else if selection_len > 1048576 then $BD.blob_free(selection)
      else let
        val text = $A.alloc<byte>(selection_len)
        val () = $BD.blob_read(selection, 0, text, selection_len)
        val () = $BD.blob_free(selection)
        val @(text_frozen, text_bytes) = $A.freeze<byte>(text)
        (* a copy that failed is said in the banner: the reader would
           otherwise paste something stale *)
        val () = $P.finish<$CB.copied>($CB.clipboard_write(text_bytes, selection_len), llam(copied) =>
          case+ copied of
          | $CB.Copied() => notice_copied()
          | $CB.NotCopied() => notice_say(TextNotCopied()))
      in release_bytes(text_frozen, text_bytes) end
    end

(* Exports the open book's annotations: downloaded, or shared *)
fn _export (destination: export_to): $P.promise(share_end, $P.Chained) = let
  val book = lib_index_of_key(open_key_get())
  val @(title, title_len) = lib_text(book, TitleText())
  val @(author, author_len) = lib_text(book, AuthorText())
in annot_export(title, title_len, author, author_len, destination) end

(* The annotations shared: as a file where the platform shares files,
   else (or when it refuses this one as a file) as its text *)
fn _share_annotations (way: share_as): void =
  $P.finish<share_end>(_export(ToShare(way)), llam(ended) =>
    case+ ended of
    | ShareOver() => ()
    | RefusedAsFile() => $P.finish<share_end>(_export(ToShare(AsText())), llam(_) => ()))

(* Goes to annotation, remembering where the reader was *)
fn _annotation_go (annotation: int): void = let
  val @(chapter, page, node) = annot_dest(annotation)
in if chapter >= 0 then reader_jump_to(chapter, page, node) else () end

(* A factory reset: every book moves to the Trash (where it can still be
   restored until the Trash is emptied) and the settings go back to
   their defaults; Undo puts both back *)
fn _factory_reset (): void = let
  val shelved = lib_trash_all()
  val how = set_reset_undoable(undo_offer(LibraryTrashed()))
  val () = _settings_apply()
in
  $P.finish<settled>(how, llam(settling) =>
    case+ settling of
    | Undone() => let
        val () = lib_untrash_all(shelved)
      in _settings_apply() end
    | Final() => lib_shelved_free(shelved))
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
  val () = $P.finish<reply>(modal_open(QNewCollection(), "New collection"), llam(answer) =>
    case+ answer of
    | Accepted() => let
        val @(name, name_len) = modal_name_read()
        val collection = lib_coll_add(name, name_len)
        val () = (if collection >= 0 then lib_coll_toggle(book, collection) else ())
        val () = lib_coll_panel(book)
      in lib_render() end
    | Declined() => ())
in modal_name_field() end

(* The collection shown, named again in the dialog *)
fn _collection_rename (): void = let
  val collection = lib_coll_shown()
in
  if collection < 0 then ()
  else let
    val () = $P.finish<reply>(modal_open(QRenameCollection(), "Rename collection"), llam(answer) =>
      case+ answer of
      | Accepted() => let
          val @(name, name_len) = modal_name_read()
        in lib_coll_rename(collection, name, name_len) end
      | Declined() => ())
    val () = modal_name_field()
  in lib_coll_name_show(collection) end
end

(* Opens the About screen, from Settings or the library menu *)
fn _about_open (): void = let
  val () = ui_show("about-error-copy", notice_details_kept())
  val () = layer_open(LAbout())
in ui_focus("about-done") end

(* Opens the Settings screen, its Sync row and goal as they are now *)
fn _settings_open (): void = let
  val () = stats_goal_show()
  val () = sync_summary_show()
  val () = lib_aside_show()
  val () = layer_open(LSettings())
in ui_focus("settings-sync") end

(* A daily goal chosen on the Settings screen *)
fn _settings_goal (goal: int): void = let
  val () = stats_goal_set(goal)
in stats_goal_show() end

(* The Settings screen's rows (the library menu's item is wired with
   the menu), and a backup picked to restore. A restore or a factory
   reset changes the library, so the reader goes back to it first, as it
   does for files handed to the app *)
fn _wire_settings_screen {count:nat} (listeners: regs(count)): regs(count + 3) = let
  val listeners = RCons(listeners, OnEl("settings-screen"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _settings_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(SettingsGoalOff()) => _settings_goal(0)
        | ~$R.some(SettingsGoalTen()) => _settings_goal(10)
        | ~$R.some(SettingsGoalTwenty()) => _settings_goal(20)
        | ~$R.some(SettingsGoalThirty()) => _settings_goal(30)
        | ~$R.some(SettingsGoalSixty()) => _settings_goal(60)
        | ~$R.some(SettingsSync()) => sync_screen_open()
        | ~$R.some(SettingsDictionaries()) => let
          val @(code, code_len) = reader_lang_code()
          val () = dict_panel_open(code, code_len)
        in $A.free<byte>(code) end
        | ~$R.some(SettingsExportBackup()) => backup_export()
        | ~$R.some(SettingsSetAside()) => lib_aside_run()
        | ~$R.some(SettingsResetSettings()) => _settings_reset()
        | ~$R.some(SettingsFactoryReset()) => let
          val () = layer_close(LSettings())
          val () = (if _in_reader() then _show_library() else ())
        in _factory_reset() end
        | ~$R.some(SettingsAbout()) => _about_open()
        | ~$R.some(SettingsDone()) => layer_close(LSettings()))
    in 0 end)
  (* the About screen: its links leave the app by themselves; Done
     goes back to Settings *)
  val listeners = RCons(listeners, OnEl("about-screen"), "click", llam(h) => let
      val clicked = _target(h)
      val () = (case+ _about_control(clicked) of
        | ~$R.some(AboutDone()) => let
            val () = layer_close(LAbout())
            (* back where it was opened: Settings' row, or the library menu's button *)
          in (if layer_is_open(LSettings()) then ui_focus("settings-about") else ui_focus("library-menu-button")) end
        | ~$R.some(AboutCopyErrorDetails()) => notice_details_copy()
        | ~$R.none() => ())
      val () = _target_free(clicked)
    in 0 end)
  val listeners = RCons(listeners, OnEl("settings-restore"), "change", llam(_) => let
      val () = layer_close(LSettings())
      val () = (if _in_reader() then _show_library() else ())
      val () = backup_import()
    in 0 end)
in listeners end

(* A daily goal chosen in the reading statistics *)
fn _stats_goal (goal: int): void = let
  val () = stats_goal_set(goal)
in stats_show() end

fn _wire_library {count:nat} (listeners: regs(count)): regs(count + 26) = let
  (* import *)
  val listeners = RCons(listeners, OnEl("import-button"), "change", llam(_) => let val () = import_picked() in 0 end)
  (* drag and drop *)
  val listeners = RCons(listeners, OnEl("library"), "dragover", llam(_) => let
      val () = $EV.prevent_default()
    in let val () = ui_attr("library", AClass, "lib drag") in 0 end end)
  val listeners = RCons(listeners, OnEl("library"), "dragleave", llam(_) => let
      val () = ui_attr("library", AClass, "lib")
    in 0 end)
  val listeners = RCons(listeners, OnEl("library"), "drop", llam(_) => let
      val () = $EV.prevent_default()
      val () = ui_attr("library", AClass, "lib")
      val () = import_dropped()
    in 0 end)
  (* the cards: open, and the book menu *)
  val listeners = RCons(listeners, OnEl("book-list"), "click", llam(h) => let
      val clicked = _target(h)
      val book = _row_of(clicked, "book")
      val menu_book = _row_of(clicked, "book-more")
      val () = _target_free(clicked)
    in
      if book >= 0 then let val () = _open_book(book, ReaderChose()) in 0 end
      else if menu_book >= 0 then let val () = _menu_open(menu_book) in 0 end
      else 0
    end)
  (* the view: which books, as a list or a grid; kept with the settings *)
  val listeners = RCons(listeners, OnEl("library-view"), "click", llam(h) => let
      val clicked = _target(h)
      (* the collections: which is shown, and the one shown renamed or
         deleted *)
      val collection = _row_of(clicked, "collection")
      val control = _library_view_control(clicked)
      val () = _target_free(clicked)
      val changed = (case+ control of
        | ~$R.none() => let
            val () = (if collection >= 0 then lib_coll_show(collection) else ())
          in false end
        | ~$R.some(FilterBooksAll()) => let val () = lib_filter_set(AllBooks()) in true end
        | ~$R.some(FilterUnread()) => let val () = lib_filter_set(Unread()) in true end
        | ~$R.some(FilterReading()) => let val () = lib_filter_set(BeingRead()) in true end
        | ~$R.some(FilterFinished()) => let val () = lib_filter_set(Finished()) in true end
        | ~$R.some(ViewList()) => let val () = lib_grid_set(ListLayout()) in true end
        | ~$R.some(ViewGrid()) => let val () = lib_grid_set(GridLayout()) in true end
        | ~$R.some(CollectionAll()) => let val () = lib_coll_show(~1) in false end
        | ~$R.some(CollectionRename()) => let val () = _collection_rename() in false end
        | ~$R.some(CollectionDelete()) => let val () = lib_coll_delete(lib_coll_shown()) in false end): bool
    in if changed then let val () = set_save(lib_state_get()) in 0 end else 0 end)
  (* the book to continue: opened, and its book menu, as a list card's *)
  val listeners = RCons(listeners, OnEl("continue-list"), "click", llam(h) => let
      val clicked = _target(h)
      val book = _row_of(clicked, "continue")
      val menu_book = _row_of(clicked, "continue-more")
      val () = _target_free(clicked)
    in
      if book >= 0 then let val () = _open_book(book, ReaderChose()) in 0 end
      else if menu_book >= 0 then let val () = _menu_open(menu_book) in 0 end
      else 0
    end)
  val listeners = RCons(listeners, OnEl("continue-list"), "contextmenu", llam(h) => let
      val () = $EV.prevent_default()
      val book = _target_number(h, "continue")
    in if book >= 0 then let val () = _menu_open(book) in 0 end else 0 end)
  val listeners = RCons(listeners, OnEl("book-list"), "contextmenu", llam(h) => let
      val () = $EV.prevent_default()
      val book = _target_number(h, "book")
    in if book >= 0 then let val () = _menu_open(book) in 0 end else 0 end)
  val listeners = RCons(listeners, OnEl("card-menu"), "click", llam(h) => let
      val clicked = _target(h)
      val book = !_menu_index
      val () = layer_close(LBookMenu())
      val control = _card_menu_control(clicked)
      val () = _target_free(clicked)
      val () = (if book >= 0 then
          (case+ control of
           | ~$R.some(CardMenuInfo()) => _info_open(book)
           | ~$R.some(CardMenuCollections()) => _collections_open(book)
           | ~$R.some(CardMenuHide()) => _book_action(book, HideOrRestore())
           | ~$R.some(CardMenuArchive()) => _book_action(book, Archive())
           | ~$R.some(CardMenuTrash()) => _book_action(book, MoveToTrash())
           | ~$R.none() => ())
          else (case+ control of ~$R.some(_) => () | ~$R.none() => ()))
    in 0 end)
  (* a book's collections: each toggled, a new one, or done (or a
     click outside) *)
  val listeners = RCons(listeners, OnEl("collections-menu"), "click", llam(h) => let
      val clicked = _target(h)
      val book = !_menu_index
      val collection = _row_of(clicked, "collection-put")
      val control = _collections_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => (if book < 0 then () else if collection >= 0 then _collection_put(book, collection) else ())
        | ~$R.some(CollectionsNew()) => (if book < 0 then () else _collection_new(book))
        | ~$R.some(CollectionsDone()) => (if book < 0 then () else layer_close(LCollections()))
        (* a click outside *)
        | ~$R.some(CollectionsMenu()) => (if book < 0 then () else layer_close(LCollections())))
    in 0 end)
  (* the info view *)
  val listeners = RCons(listeners, OnEl("book-info"), "click", llam(h) => let
      val clicked = _target(h)
      val book = !_menu_index
      val control = _book_info_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(BookInfoBack()) => layer_close(LBookInfo())
        | ~$R.some(BookInfoHide()) => (if book < 0 then () else let val () = layer_close(LBookInfo()) in _book_action(book, HideOrRestore()) end)
        | ~$R.some(BookInfoArchive()) => (if book < 0 then () else let val () = layer_close(LBookInfo()) in _book_action(book, Archive()) end)
        | ~$R.some(BookInfoTrash()) => (if book < 0 then () else _book_action(book, MoveToTrash())))
    in 0 end)
  (* sort and shelf *)
  val listeners = RCons(listeners, OnEl("sort-button"), "click", llam(_) => let
      val sort_order = sort_next(lib_sort_get())
      val () = lib_sort(sort_order)
      (* the library kept in its new order: a save the app makes later
         (a sync as it opens) writes the order it reads back, so it
         changes nothing (#302) *)
      val () = lib_save()
      val () = lib_sort_label(sort_order)
      val () = set_apply(lib_state_get())
    in let val () = lib_render() in 0 end end)
  val listeners = RCons(listeners, OnEl("shelf-button"), "click", llam(_) => let
      val () = lib_shelf_set(shelf_next(lib_shelf_get()))
      val () = _trash_dictionaries()
    in let val () = lib_render() in 0 end end)
  (* the dictionaries in the Trash, each with a Restore (#396) *)
  val listeners = RCons(listeners, OnEl("trash-dictionaries"), "click", llam(h) => let
      val clicked = _target(h)
      val restored = _row_of(clicked, "restore-dict")
      val () = _target_free(clicked)
    in if restored >= 0 then let val () = dict_trash_restore(restored) in 0 end else 0 end)
  (* search *)
  (* the field is made again to be cleared: its events are taken on
     its box *)
  val listeners = RCons(listeners, OnEl("library-search-box"), "input", llam(h) => let
      val @(query, query_len) = _input_text(h)
      val () = ui_show("library-search-clear", query_len > 0)
      val () = _query_save(query, query_len)
      val () = lib_query_set(query, query_len)
    in let val () = lib_render() in 0 end end)
  val listeners = RCons(listeners, OnEl("library-search-box"), "click", llam(h) => let
      val clicked = _target(h)
      val clear = (case+ _library_search_control(clicked) of ~$R.some(LibrarySearchClear()) => true | ~$R.none() => false): bool
      val () = _target_free(clicked)
    in
      if clear then let
        val () = app_library_search()
        val empty = $A.alloc<byte>(1)
        val () = _query_save(empty, 0)
        val () = $A.free<byte>(empty)
        val () = lib_query_set($A.alloc<byte>(1), 0)
        val () = lib_render()
      in let val () = ui_focus("library-search") in 0 end end
      else 0
    end)
  (* the error banner *)
  val listeners = RCons(listeners, OnEl("error-dismiss"), "click", llam(_) => let val () = notice_dismiss() in 0 end)
  val listeners = RCons(listeners, OnEl("error-copy"), "click", llam(_) => let val () = notice_details_copy() in 0 end)
  val listeners = RCons(listeners, OnEl("error-reopen"), "click", llam(_) => let val () = $NAV.reload() in 0 end)
  val listeners = RCons(listeners, OnEl("install-hint-dismiss"), "click", llam(_) => let val () = lib_install_hint_dismiss() in 0 end)
  (* the library menu *)
  val listeners = RCons(listeners, OnEl("library-menu-button"), "click", llam(_) => let
      val () = layer_open(LLibraryMenu())
    in let val () = ui_focus("menu-settings") in 0 end end)
  val listeners = RCons(listeners, OnEl("library-menu"), "click", llam(h) => let
      val clicked = _target(h)
      val () = (case+ _harm_clicked(clicked) of
        | ~Some_vt(the_harm) => let
            val () = layer_close(LLibraryMenu())
          in $P.finish<reply>(lib_ask_harm(the_harm, dict_trash_count()), llam(answer) =>
            case+ answer of
            (* the dictionaries in the Trash go with the books, here and
               nowhere else (tests/static/trash.py) *)
            | Accepted() => let
                val () = dict_trash_empty()
                val () = dict_trash_render(false)
              in _save_render() end
            | Declined() => ()) end
        | ~None_vt() =>
        case+ _library_menu_control(clicked) of
        | ~$R.none() => ()
        | ~$R.some(MenuSettings()) => let
          val () = layer_close(LLibraryMenu())
        in _settings_open() end
        | ~$R.some(MenuAbout()) => let
          val () = layer_close(LLibraryMenu())
        in _about_open() end
        (* the browser's offer to install the app *)
        | ~$R.some(MenuInstall()) => let
          val () = layer_close(LLibraryMenu())
        in platform_install() end
        | ~$R.some(MenuStats()) => let
          val () = layer_close(LLibraryMenu())
          val () = stats_show()
          val () = layer_open(LStats())
        in ui_focus("stats-done") end
        | ~$R.some(MenuCatalogues()) => let
          val () = layer_close(LLibraryMenu())
        in catalogue_panel_open() end
        | ~$R.some(MenuClose()) => layer_close(LLibraryMenu())
        (* a click outside *)
        | ~$R.some(LibraryMenu()) => layer_close(LLibraryMenu()))
    in let val () = _target_free(clicked) in 0 end end)
  (* the reading statistics: a daily goal chosen, or done (or a click
     outside) *)
  val listeners = RCons(listeners, OnEl("stats-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _stats_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(StatsGoalOff()) => _stats_goal(0)
        | ~$R.some(StatsGoalTen()) => _stats_goal(10)
        | ~$R.some(StatsGoalTwenty()) => _stats_goal(20)
        | ~$R.some(StatsGoalThirty()) => _stats_goal(30)
        | ~$R.some(StatsGoalSixty()) => _stats_goal(60)
        | ~$R.some(StatsDone()) => layer_close(LStats())
        (* a click outside *)
        | ~$R.some(StatsPanel()) => layer_close(LStats()))
    in 0 end)
  (* the dictionaries: one removed, or done (or a click outside) *)
  val listeners = RCons(listeners, OnEl("dictionaries-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val removed = _row_of(clicked, "drop-dictionary")
      val control = _dictionaries_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => (if removed >= 0 then dict_remove(removed) else ())
        | ~$R.some(DictionariesDone()) => layer_close(LDictionaries())
        (* a click outside *)
        | ~$R.some(DictionariesPanel()) => layer_close(LDictionaries()))
    in 0 end)
  (* a dictionary's files picked to import (the input is made again to
     be cleared: its events are taken on its box) *)
  val listeners = RCons(listeners, OnEl("dictionary-import"), "change", llam(_) => let
      val () = dict_import_picked()
    in 0 end)
in listeners end

(* Sync: its screen's buttons, its offer's, and the page hidden (a sync,
   so what was read here is on the other devices) *)
fn _wire_sync {count:nat} (listeners: regs(count)): regs(count + 3) = let
  val listeners = RCons(listeners, OnEl("sync-screen"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _sync_screen_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(SyncNow()) => sync_now()
        (* the app's Use Android and the browser's Google Drive: each
           shown only where it signs in *)
        | ~$R.some(SyncAndroid()) => sync_android()
        | ~$R.some(SyncGoogle()) => sync_android()
        | ~$R.some(SyncFastmail()) => sync_fastmail()
        | ~$R.some(NextcloudSignIn()) => sync_nextcloud_sign_in()
        | ~$R.some(SyncDropbox()) => sync_dropbox()
        | ~$R.some(SyncOff()) => sync_off()
        | ~$R.some(SyncDone()) => layer_close(LSync())
        (* a service's row: its own sign-in step (#331) *)
        | ~$R.some(SyncRowGoogle()) => sync_step_open(ServiceGoogle())
        | ~$R.some(SyncRowDropbox()) => sync_step_open(ServiceDropbox())
        | ~$R.some(SyncRowFastmail()) => sync_step_open(ServiceFastmail())
        | ~$R.some(SyncRowNextcloud()) => sync_step_open(ServiceNextcloud())
        | ~$R.some(SyncRowWebDav()) => sync_step_open(ServiceWebDav())
        | ~$R.some(SyncWebDav()) => sync_webdav()
        | ~$R.some(SyncStepCancel()) => sync_step_cancel()
        (* the consent screen no longer awaited (#340) *)
        | ~$R.some(SyncStop()) => sync_stop())
    in 0 end)
  val listeners = RCons(listeners, OnEl("sync-offer"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _sync_offer_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(SyncGo()) => let
          val @(chapter, page, anchor) = sync_further_take()
        in if chapter >= 0 then (if _in_reader() then reader_jump_to(chapter, page, anchor) else ()) else () end
        | ~$R.some(SyncOfferClose()) => sync_further_dismiss())
    in 0 end)
  val listeners = RCons(listeners, OnDocument(), "visibilitychange", llam(_) => let
      val () = (case+ $WN.get_visibility() of $WN.Hidden() => sync_run() | $WN.Visible() => ())
    in 0 end)
in listeners end

(* Whether an element is shown *)
fn _shown {id_len:pos | id_len < 256} (id: string id_len): bool = let
  val () = ui_measure(id)
in $DR.get_measure_w() > 0 end

(* What each choice of where taps turn pages does, for the book open:
   read right to left, its back is on the right (_zone_click), and the
   drawings are mirrored (.taps.rtl) *)
fn _taps_describe (): void =
  if _rtl() then let
    val () = ui_attr("taps-choice", AClass, "seg taps rtl")
    val () = ui_text("taps-sides-about", "Right side back, left side forward, middle shows the controls")
    val () = ui_text("taps-forward-about", "Anywhere forward, right side back, top shows the controls")
  in ui_text("taps-one-hand-about", "Top back, bottom forward, middle shows the controls") end
  else let
    val () = ui_attr("taps-choice", AClass, "seg taps")
    val () = ui_text("taps-sides-about", "Left side back, right side forward, middle shows the controls")
    val () = ui_text("taps-forward-about", "Anywhere forward, left side back, top shows the controls")
  in ui_text("taps-one-hand-about", "Top back, bottom forward, middle shows the controls") end

(* The reading settings' tab shown. The sheet opens on Look, which holds
   what is changed while reading (the theme, the size); the other tabs
   hold what is set once *)
val _sheet_tab_shown = ref<sheet_tab>(LookTab())

(* Whether tab is offered: Read aloud only where the platform speaks or
   the book is narrated (the reader's _narration_offered shows it); the
   sheet is open, so a tab hidden is one measured empty *)
fn _sheet_tab_offered (tab: sheet_tab): bool =
  case+ tab of
  | AloudTab() => _shown("typography-aloud-tab")
  | LookTab() => true
  | PageTab() => true
  | TurningTab() => true

(* The tab after tab, and the one before it, round from the last to the
   first; Read aloud is passed over where it is not offered *)
fn _sheet_tab_after (tab: sheet_tab): sheet_tab =
  case+ tab of
  | LookTab() => PageTab()
  | PageTab() => TurningTab()
  | TurningTab() => if _sheet_tab_offered(AloudTab()) then AloudTab() else LookTab()
  | AloudTab() => LookTab()

fn _sheet_tab_before (tab: sheet_tab): sheet_tab =
  case+ tab of
  | LookTab() => if _sheet_tab_offered(AloudTab()) then AloudTab() else TurningTab()
  | PageTab() => LookTab()
  | TurningTab() => PageTab()
  | AloudTab() => TurningTab()

(* tab marked chosen or not: selected, in the Tab order, and its panel
   shown, or none of them (a panel not chosen keeps its room in the
   panels' one cell, unseen, unfocused and not read out: app.bats's
   _sheet_tab, #301) *)
fn _sheet_tab_mark (tab: sheet_tab, chosen: bool): void = let
  val id = sheet_tab_control_id(tab)
  val () = ui_attr(id, ASelected, (if chosen then "true" else "false"): [value_len:pos | value_len < 256] string value_len)
  val () = ui_attr(id, ATabindex, (if chosen then "0" else "-1"): [value_len:pos | value_len < 256] string value_len)
in ui_class(sheet_tab_panel_id(tab),
  (if chosen then "tabpanel" else "tabpanel unchosen"): [class_len:pos | class_len < 256] string class_len) end

(* The reading settings' tab chosen shown, and the others hidden
   (WAI-ARIA's tabs pattern: one tab selected, the only one in the Tab
   order), from its top: the sheet is as tall as its tallest tab, so a
   shorter one, shown where a taller was scrolled, would show only the
   room under it *)
fn _sheet_tab_choose (chosen: sheet_tab): void = let
  val () = !_sheet_tab_shown := chosen
  val () = ui_scroll_to_top("typography-panel")
  val () = _sheet_tab_mark(LookTab(), (case+ chosen of LookTab() => true | _ => false): bool)
  val () = _sheet_tab_mark(PageTab(), (case+ chosen of PageTab() => true | _ => false): bool)
  val () = _sheet_tab_mark(TurningTab(), (case+ chosen of TurningTab() => true | _ => false): bool)
in _sheet_tab_mark(AloudTab(), (case+ chosen of AloudTab() => true | _ => false): bool) end

(* A key on the tabs: the arrows move to the tab beside the focused
   one, Home to the first and End to the last, each shown as the focus
   reaches it (the panels are there at once) *)
fn _sheet_tab_key (pressed: key): void = let
  val moved = (case+ pressed of
    | ArrowRight() => $R.some(_sheet_tab_after(!_sheet_tab_shown))
    | ArrowLeft() => $R.some(_sheet_tab_before(!_sheet_tab_shown))
    | HomeKey() => $R.some(LookTab())
    | EndKey() => $R.some(_sheet_tab_before(LookTab()))
    | _ => $R.none()): $R.option(sheet_tab)
in
  case+ moved of
  | ~$R.some(tab) => let
      val () = _sheet_tab_choose(tab)
    in ui_focus(sheet_tab_control_id(tab)) end
  | ~$R.none() => ()
end

(* The reading settings' sheet opened: the screen's controls as the
   platform has them now, the speeds and the book's voices to read
   aloud, the volume keys offered in the app, where a page is given
   them (pwa's MainActivity), the taps said for the book open, and its
   first tab, Look *)
fn _sheet_open (): void = let
  val () = screen_controls_show()
  val () = aloud_choices_show()
  val () = ui_show("volume-row", $BAPP.is_native_platform())
  val () = _taps_describe()
  val () = layer_open(LTypography())
  val () = _sheet_tab_choose(LookTab())
in ui_focus("typography-close") end

(* A reading settings' control clicked: whether a setting changed *)
fn _typography_chosen (control: typography_control): bool =
  case+ control of
  | FontLiterata() => let val () = set_font_set(Literata()) in true end
  | FontInter() => let val () = set_font_set(Inter()) in true end
  | FontBook() => let val () = set_font_set(BookFont()) in true end
  | FontAtkinson() => let val () = set_font_set(Atkinson()) in true end
  | ThemeAuto() => let val () = set_theme_set(Auto()) in true end
  | ThemeLight() => let val () = set_theme_set(Fixed(Light())) in true end
  | ThemeSepia() => let val () = set_theme_set(Fixed(Sepia())) in true end
  | ThemeDark() => let val () = set_theme_set(Fixed(Dark())) in true end
  | ThemeNight() => let val () = set_theme_set(Fixed(Night())) in true end
  | ThemeGrey() => let val () = set_theme_set(Fixed(Grey())) in true end
  | LayoutPages() => let val () = set_flow_set(Paged()) in true end
  | LayoutScroll() => let val () = set_flow_set(Scrolled()) in true end
  | ColumnsAuto() => let val () = set_cols_set(AutoColumns()) in true end
  | ColumnsOne() => let val () = set_cols_set(OneColumn()) in true end
  | ColumnsTwo() => let val () = set_cols_set(TwoColumns()) in true end
  (* a switch: the lines justified or ragged, the words hyphenated or
     not, the images dimmed or as they are (quire#363) *)
  | JustifySwitch() => let
      val () = (case+ set_align_get() of
        | Justified() => set_align_set(Ragged())
        | Ragged() => set_align_set(Justified()))
    in true end
  | HyphenationSwitch() => let
      val () = (case+ set_hyph_get() of
        | Hyphenated() => set_hyph_set(NoHyphens())
        | NoHyphens() => set_hyph_set(Hyphenated()))
    in true end
  | RubyShow() => let val () = set_ruby_set(RubyShown()) in true end
  | RubyHide() => let val () = set_ruby_set(RubyHidden()) in true end
  | DimImagesSwitch() => let
      val () = (case+ set_dim_get() of
        | ImagesDimmed() => set_dim_set(ImagesAsTheyAre())
        | ImagesAsTheyAre() => set_dim_set(ImagesDimmed()))
    in true end
  | TapsSides() => let val () = set_taps_set(SideZones()) in true end
  | TapsForward() => let val () = set_taps_set(ForwardZones()) in true end
  | TapsOneHand() => let val () = set_taps_set(OneHandZones()) in true end
  (* one switch: the volume keys turn pages, or are the volume's *)
  | VolumeKeysTurn() => let
      val () = (case+ set_vol_get() of
        | KeysTurnPages() => set_vol_set(KeysForVolume())
        | KeysForVolume() => set_vol_set(KeysTurnPages()))
    in true end
  | NarrationSkip() => let val () = set_narration_notes_set(NotesSkipped()) in true end
  | NarrationRead() => let val () = set_narration_notes_set(NotesRead()) in true end
  | TypographyReset() => let val () = _settings_reset() in false end
  | TypographyClose() => let val () = layer_close(LTypography()) in false end
  | ScreenFullscreen() => let val () = screen_fullscreen_toggle() in false end
  | ScreenLock() => let val () = screen_lock_toggle() in false end
  | ScreenBrightnessSystem() => let val () = screen_brightness_system_toggle() in false end

fn _wire_settings {count:nat} (listeners: regs(count)): regs(count + 10) = let
  val listeners = RCons(listeners, OnEl("typography-button"), "click", llam(_) => let
      val () = _sheet_open()
    in 0 end)
  val listeners = RCons(listeners, OnEl("typography-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _typography_control(clicked)
      val tab = _sheet_tab(clicked)
      val () = _target_free(clicked)
      val () = (case+ tab of
        | ~$R.some(chosen) => _sheet_tab_choose(chosen)
        | ~$R.none() => ())
      val changed = (case+ control of
        | ~$R.none() => false
        | ~$R.some(chosen) => _typography_chosen(chosen)): bool
    in if changed then let val () = _settings_changed() in 0 end else 0 end)
  (* the arrow keys, Home and End on the reading settings' tabs *)
  val listeners = RCons(listeners, OnEl("typography-tabs"), "keydown", llam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(key_bytes, n) => let
          val pressed = ui_key(key_bytes, n)
          val () = $A.free<byte>(key_bytes)
          val () = _sheet_tab_key(pressed)
        in 0 end)
  val listeners = RCons(listeners, OnEl("size-row"), "input", llam(h) => let
      val () = set_size_set(_clamp(_input_number(h), 12, 32))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("line-height-row"), "input", llam(h) => let
      val () = set_lh_set(_clamp(_input_number(h), 12, 24))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("margins-row"), "input", llam(h) => let
      val () = set_margin_set(_clamp(_input_number(h), 0, 4))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("paragraph-row"), "input", llam(h) => let
      val () = set_ps_set(_clamp(_input_number(h), 0, 20))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("letter-row"), "input", llam(h) => let
      val () = set_ls_set(_clamp(_input_number(h), 0, 12))
    in let val () = _settings_changed() in 0 end end)
  val listeners = RCons(listeners, OnEl("word-row"), "input", llam(h) => let
      val () = set_ws_set(_clamp(_input_number(h), 0, 16))
    in let val () = _settings_changed() in 0 end end)
  (* the narration's speed, in quarters: kept, and applied to the audio
     at once *)
  val listeners = RCons(listeners, OnEl("narration-speed-row"), "input", llam(h) => let
      val () = set_narration_speed_set(_clamp(_input_number(h), 2, 8))
      val () = set_apply(lib_state_get())
    in let val () = narration_rate() in 0 end end)
in listeners end

(* ============================================================
   Search
   ============================================================ *)

(* The search field, made again holding query[0, query_len) *)
fn _search_value {l:agz}{n:pos}{query_len:nat | query_len <= n; query_len < 65536} (query: $A.arr(byte, l, n), query_len: int query_len): void =
  if query_len > 0 then ui_attr_buf("search-field", AValue, query, query_len) else $A.free<byte>(query)

fn _search_field {l:agz}{n:pos}{query_len:nat | query_len <= n; query_len < 65536} (query: $A.arr(byte, l, n), query_len: int query_len): void = let
  val () = app_book_search()
in _search_value(query, query_len) end

fn _search_open (): void = let
  val () = layer_open(LSearch())
in ui_focus("search-field") end

(* Ends the search, its panel closed: the reader goes back to where it
   was before it jumped to a hit *)
fn _search_clear (): void = let
  val () = reader_search_close()
  (* the next search starts afresh: an empty field, no old results *)
  val () = _search_field($A.alloc<byte>(1), 0)
  val () = ui_clear("search-results")
in ui_clear("search-status") end

(* Ends the search from its results' bar: the page has the focus *)
fn _search_end (): void = let
  val () = layer_close(LSearch())
  val () = _search_clear()
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
      val query_len = $BD.blob_len(value)
    in
      if query_len <= 0 then let
        val () = $BD.blob_free(value)
      in reader_search($A.alloc<byte>(1), 0) end
      else if query_len > 65535 then $BD.blob_free(value)
      else let
        val query = $A.alloc<byte>(query_len)
        val () = $BD.blob_read(value, 0, query, query_len)
        val () = $BD.blob_free(value)
      in reader_search(query, query_len) end
    end
end

(* A keystroke in the field: the search runs once typing pauses *)
fn _search_input (): void = let
  val () = !_search_tick := !_search_tick + 1
  val tick = !_search_tick
in
  $P.finish<Int>($P.vow($TM.timer_set(300)), llam(_) =>
    if !_search_tick = tick then _search_run() else ())
end

(* Searches for the selected text *)
fn _search_selection (): void =
  case+ $DR.get_selection_text() of
  | ~$R.none() => ()
  | ~$R.some(selection) => let
      val selection_len = $BD.blob_len(selection)
    in
      if selection_len <= 0 then $BD.blob_free(selection)
      else if selection_len > 1000 then $BD.blob_free(selection)
      else let
        val field_text = $A.alloc<byte>(selection_len)
        val () = $BD.blob_read(selection, 0, field_text, selection_len)
        val query = $A.alloc<byte>(selection_len)
        val () = $BD.blob_read(selection, 0, query, selection_len)
        val () = $BD.blob_free(selection)
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
fn _left (): void = if _rtl() then _next() else _previous()
fn _right (): void = if _rtl() then _previous() else _next()

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
   bottom third on, between them the bars. A book read right to left
   has them mirrored: its sides the other way, and forward's back
   quarter on the right (_taps_describe says so) *)
fn _zone_click (x: Int, y: Int): void = let
  val () = ui_measure("page")
  val page_x = $DR.get_measure_x()
  val page_y = $DR.get_measure_y()
  val page_width = $DR.get_measure_w()
  val page_height = $DR.get_measure_h()
in
  if page_width <= 0 then ()
  else case+ set_taps_get() of
  | ForwardZones() =>
    (if (if page_height > 0 then y < page_y + page_height / 8 else false) then _chrome_set(~(!_chrome))
     (* back at the edge the book starts from: the left, or the right
        read right to left; anywhere else forward *)
     else if (if _rtl() then x > page_x + page_width - page_width / 4 else x < page_x + page_width / 4) then _previous()
     else _next())
  | OneHandZones() =>
    (if page_height <= 0 then _chrome_set(~(!_chrome))
     else if y < page_y + page_height / 3 then _previous()
     else if y > page_y + page_height - page_height / 3 then _next()
     else _chrome_set(~(!_chrome)))
  | SideZones() =>
    (if x < page_x + page_width / 4 then _left()
     else if x > page_x + page_width - page_width / 4 then _right()
     else _chrome_set(~(!_chrome)))
end

(* Whether the volume keys turn the page *)
fn _volume_turns (): bool = case+ set_vol_get() of KeysTurnPages() => true | KeysForVolume() => false

(* Whether a tap on the page is read by the sides' zones *)
fn _side_zones (): bool = case+ set_taps_get() of SideZones() => true | ForwardZones() => false | OneHandZones() => false

(* Whether a key is the escape key *)
fn _is_escape (pressed: key): bool = case+ pressed of EscapeKey() => true | _ => false

fn _reader_key (pressed: key, held: modifiers): void =
  (* the keys that turn the page are the reader's alone: scrolled, the
     browser would also scroll the focused page by them *)
  case+ pressed of
  | ArrowRight() => _right()
  | PageDown() => let val () = $EV.prevent_default() in _next() end
  | ArrowLeft() => _left()
  | PageUp() => let val () = $EV.prevent_default() in _previous() end
  | SpaceBar() => let val () = $EV.prevent_default() in (if held.shift then _previous() else _next()) end
  (* the volume keys, when they turn the page and the browser gives them
     to the page: down on, up back, and the volume left as it is *)
  | VolumeDown() => if _volume_turns() then let val () = $EV.prevent_default() in _next() end else ()
  | VolumeUp() => if _volume_turns() then let val () = $EV.prevent_default() in _previous() end else ()
  | HomeKey() => let val () = $EV.prevent_default() in reader_page(0) end
  | EndKey() => let val () = $EV.prevent_default() in reader_page(1000000) end
  | LetterB() => annot_bookmark_toggle(reader_anchor())
  | LetterT() => _chrome_set(~(!_chrome))
  | Slash() => let
      val () = $EV.prevent_default()
    in _search_open() end
  | LetterF() => if held.command then let
      val () = $EV.prevent_default()
    in _search_open() end else ()
  | EnterKey() => if !_focus_link >= 0 then let
    (* the Enter is the link's: a note opened over the page takes the
       focus to its Close, which the same Enter would otherwise press *)
    val () = $EV.prevent_default()
  in if reader_link_at(!_focus_link) then () else () end else ()
  | EscapeKey() =>
    (if _panels_close() then ui_focus("page")
     else if _shown("search-nav") then _search_end()
     else if !_chrome then _chrome_set(false) else _show_library())
  | OtherKey() => ()

(* Escape: the dialog is answered with its first button, or else the
   overlay opened last closes (layer_escape); true when one did. After
   a reader panel, the focus is back where it was when the panel opened
   (layer.bats); after the search panel, the page has it, and a search
   with no hits ends *)
fn _escape_overlay (): bool =
  if modal_open_now() then let val () = modal_dismiss() in true end
  else case+ layer_escape() of
  | ~NothingOpen() => false
  | ~Escaped(LSearch()) => let
      val () = (if _shown("search-nav") then ui_focus("page") else _search_clear())
    in true end
  (* a sync service's step: its sign-in under way stops, and the list
     is back *)
  | ~Escaped(LSyncStep()) => let
      val () = sync_step_cancel()
    in true end
  | ~Escaped(_) => true

(* Back, Android's and the browser's (quire#333), one step, as Android's
   back stack goes: the dialog is answered, or else the overlay opened
   last closes (as Escape does: Sync goes back to Settings, Settings to
   what was under it); else the reader leaves the in-book search's
   results, or else the book for the library. At the library with
   nothing open Back is the platform's: the app is moved to the
   background, the browser leaves the page *)
datatype went_back = WentBack | AtRoot

fn _go_back (): went_back =
  if _escape_overlay() then WentBack()
  else if ~_in_reader() then AtRoot()
  else if _shown("search-nav") then let
    val () = _search_end()
  in WentBack() end
  else let
    val () = _show_library()
  in WentBack() end

(* A key while the search panel is open: Enter goes to the next hit
   (Shift+Enter the one before), Escape closes the panel *)
fn _search_key (pressed: key, held: modifiers): void =
  case+ pressed of
  | EnterKey() => let
      val () = reader_search_step(if held.shift then ~1 else 1)
    in if _shown("search-nav") then let val () = layer_close(LSearch()) in ui_focus("page") end else () end
  | EscapeKey() => let
      val () = layer_close(LSearch())
    in if _shown("search-nav") then ui_focus("page") else _search_clear() end
  | _ => ()

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
in $P.finish<Int>($P.vow($TM.timer_set(0)), llam(_) => !_dragged := false) end

(* The page turn's events: a pan moves the page being left with the
   finger, a commit turns it (a drag to the left shows the page to the
   right), from where the finger let go, a cancel puts it back *)
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
            | _ => reader_pan_back()
          end
        | ~$GT.GCancel(region, _) =>
          if region <> PAGE_REGION then ()
          else let val () = _drag_ended() in reader_pan_back() end
        | ~$GT.GLongPress(_, _, _) => ()
        | ~$GT.GPinch(_, _, _, _) => ()
        | ~$GT.GPinchEnd(_) => ()
        | ~$GT.GScrollEnd(_, _) => ()
        | ~$GT.GTransitionEnd(_) => ()
        | ~$GT.GTransitionCancel(_) => ())
    in _on_gestures(rest) end

(* The recognizer and its source, out of their cell; put back with
   _gestures_put *)
fn _gestures_take (): gesture_cell = let
  var cell: gesture_cell = GNone()
  val () = ref_exch_elt<gesture_cell>(_gestures, cell)
in cell end

fn _gestures_put (held: gesture_cell): void = let
  var cell: gesture_cell = held
  val () = ref_exch_elt<gesture_cell>(_gestures, cell)
in case+ cell of
  | ~GNone() => ()
  | ~GSome(state, source) => let
      val () = $GS.gestures_source_free(source)
    in $GT.gestures_free(state) end
end

(* The gesture events, acted on in the reader and dropped elsewhere *)
fn _gestures_show (events: $GT.gevents): void =
  if _in_reader() then _on_gestures(events) else $GT.gevents_free(events)

(* How many animation frames one pointer record may ask for, one after
   another, while a pointer is down (a frame asks for the next): about
   27 minutes at 60 frames a second. A metric needs the bound; the next
   record gives the chain new rounds *)
#define FRAME_ROUNDS 100000

(* Does what the source asks: a capture (to the reader view, the
   listened root), or a frame, whose time goes back to the source *)
fun _gestures_act {count:nat}{rounds:nat} .<rounds, count + 1>.
  (asked: list_vt($GS.action, count), rounds: int rounds): void =
  case+ asked of
  | ~list_vt_nil() => ()
  | ~list_vt_cons(action, rest) => let
      val () = (case+ action of
        | ~$GS.CapturePointer(pointer_id) => ui_pointer_capture("reader", pointer_id)
        | ~$GS.WantFrame() =>
          $P.finish<Int>($TM.animation_frame(), llam(time) => _gestures_frame($GD.gestures_stamp(time), rounds)))
    in _gestures_act(rest, rounds) end

and _gestures_frame {time:nat}{rounds:nat} .<rounds, 0>. (time: int time, rounds: int rounds): void =
  if rounds <= 0 then ()
  else case+ _gestures_take() of
  | ~GSome(state, source) => let
      val @(events, asked) = $GS.gestures_frame(source, state, time)
      val () = _gestures_put(GSome(state, source))
      val () = _gestures_show(events)
    in _gestures_act(asked, rounds - 1) end
  | ~GNone() => ()

(* A pointer record from the reader view, through the source and the
   recognizer *)
fn _gesture_record (h: $EV.event_payload): void =
  case+ take_blob(h) of
  | ~NoBlobBytes() => ()
  | ~BlobBytes(record, record_len) =>
    if record_len < 48 then $A.free<byte>(record)
    else (case+ _gestures_take() of
      | ~GSome(state, source) => let
          val @(events, asked) = $GS.gestures_raw(source, state, record, 0)
          val () = $A.free<byte>(record)
          val () = _gestures_put(GSome(state, source))
          val () = _gestures_show(events)
        in _gestures_act(asked, FRAME_ROUNDS) end
      | ~GNone() => $A.free<byte>(record))

(* A pointer record from the reader view while a panel is over it:
   dropped *)
fn _gesture_drop (h: $EV.event_payload): void =
  case+ take_blob(h) of
  | ~NoBlobBytes() => ()
  | ~BlobBytes(record, _) => $A.free<byte>(record)

(* The recognizer, with the page turn's region: horizontal drags, by
   touch or pen only (a mouse drag over the page selects text) *)
fn _gestures_start (): void = let
  val state = $GT.gestures_new()
  val () = $GT.gestures_region(state, PAGE_REGION, $GP.NoRegion(), page_turn_axes(), false, false, $GT.DevTouch())
in _gestures_put(GSome(state, $GS.gestures_source_new())) end

(* The page's scrolls, numbered, so only the last one's rest counts *)
val _scroll_generation = ref<int>(0)

(* The catalogues: one opened, removed or added, or done (or a click
   outside); a catalogue browsed: a link followed, a book got, Back,
   Close, the next and previous pages, and its search (its button, or
   Enter in its field) *)
fn _wire_catalogues {count:nat} (listeners: regs(count)): regs(count + 3) = let
  val listeners = RCons(listeners, OnEl("catalogues-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val opened = _row_of(clicked, "catalogue-open")
      val removed = _row_of(clicked, "drop-catalogue")
      val control = _catalogues_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => (if opened >= 0 then catalogue_open(opened) else if removed >= 0 then catalogue_remove(removed) else ())
        | ~$R.some(CatalogueAdd()) => catalogue_add()
        | ~$R.some(CataloguesDone()) => layer_close(LCatalogues())
        (* a click outside *)
        | ~$R.some(CataloguesPanel()) => layer_close(LCatalogues()))
    in 0 end)
  val listeners = RCons(listeners, OnEl("catalogue-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val followed = _row_of(clicked, "feed-link")
      val got = _row_of(clicked, "book-get")
      val control = _catalogue_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => (if followed >= 0 then catalogue_follow(followed) else if got >= 0 then catalogue_get(got) else ())
        | ~$R.some(CatalogueBack()) => catalogue_back()
        | ~$R.some(CatalogueClose()) => catalogue_close()
        | ~$R.some(CatalogueNext()) => catalogue_next()
        | ~$R.some(CataloguePrevious()) => catalogue_previous()
        | ~$R.some(CatalogueSearchGo()) => catalogue_search())
    in 0 end)
in RCons(listeners, OnEl("catalogue-search-bar"), "keydown", llam(h) =>
  case+ take_blob(h) of
  | ~NoBlobBytes() => 0
  | ~BlobBytes(key_bytes, n) => let
      val pressed = ui_key(key_bytes, n)
      val () = $A.free<byte>(key_bytes)
    in case+ pressed of EnterKey() => let val () = catalogue_search() in 0 end | _ => 0 end) end

fn _wire_toc {count:nat} (listeners: regs(count)): regs(count + 9) = let
  val listeners = RCons(listeners, OnEl("contents-button"), "click", llam(_) => let val () = _toc_open() in 0 end)
  val listeners = RCons(listeners, OnEl("contents-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val contents_row = _row_of(clicked, "toc-row")
      val bookmark_go = _row_of(clicked, "bookmark-go")
      val bookmark_delete = _row_of(clicked, "bookmark-delete")
      val bookmark_note = _row_of(clicked, "bookmark-edit")
      val print_page = _row_of(clicked, "page-row")
      val control = _contents_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.some(ContentsClose()) => layer_close(LContents())
        | ~$R.some(ContentsTab()) => _toc_open()
        | ~$R.some(BookmarksTab()) => _bookmarks_open()
        | ~$R.some(PagesTab()) => _pages_open()
        | ~$R.none() =>
        if print_page >= 0 then let
          val () = layer_close(LContents())
        in reader_goto_page(print_page) end
        else if bookmark_go >= 0 then let val () = layer_close(LContents()) in _annotation_go(bookmark_go) end
        else if bookmark_delete >= 0 then annot_delete_bookmark(bookmark_delete)
        else if bookmark_note >= 0 then annot_ask_note(bookmark_note, false)
        else if contents_row >= 0 then let
          val () = layer_close(LContents())
        in reader_goto_entry(contents_row) end
        else ())
    in 0 end)
  val listeners = RCons(listeners, OnEl("jump-back"), "click", llam(_) => let val () = reader_back() in 0 end)
  val listeners = RCons(listeners, OnEl("next-chapter"), "click", llam(_) => let val () = page_next() in 0 end)
  (* scrolled, the place follows the page, once it rests a moment *)
  val listeners = RCons(listeners, OnEl("page"), "scroll", llam(_) => let
      val () = !_scroll_generation := !_scroll_generation + 1
      val generation = !_scroll_generation
      val () = $P.finish<Int>($P.vow($TM.timer_set(150)), llam(_) =>
          if !_scroll_generation = generation then reader_scrolled() else ())
    in 0 end)
  (* the scrubber: a drag shows where it would go, letting go goes there *)
  val listeners = RCons(listeners, OnEl("scrubber-track"), "pointerdown", llam(h) => let
      val x = _event_x(h)
      val () = !_scrubbing := true
      val () = _chrome_set(true)
    in let val () = reader_scrub_preview(x) in 0 end end)
  val listeners = RCons(listeners, OnDocument(), "pointermove", llam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = _chrome_set(true)
      in let val () = reader_scrub_preview(x) in 0 end end
      else 0)
  val listeners = RCons(listeners, OnDocument(), "pointerup", llam(h) =>
      if !_scrubbing then let
        val x = _event_x(h)
        val () = !_scrubbing := false
      in let val () = reader_scrub_go(x) in 0 end end
      else 0)
  (* the app hidden (another tab, another app): where the reader is is
     stored *)
  val listeners = RCons(listeners, OnDocument(), "visibilitychange", llam(_) =>
      if _in_reader() then let val () = reader_save() in 0 end else 0)
in listeners end

fn _wire_annotations {count:nat} (listeners: regs(count)): regs(count + 7) = let
  val listeners = RCons(listeners, OnEl("bookmark-button"), "click", llam(_) => let
      val () = annot_bookmark_toggle(reader_anchor())
    in 0 end)
  val listeners = RCons(listeners, OnDocument(), "selectionchange", llam(_) =>
      if _in_reader() then let
        val selected = _has_selection()
        val () = ui_show("selection-toolbar", selected)
        val () = (if selected then _lookup_update(1) else ())
      in 0 end else 0)
  val listeners = RCons(listeners, OnEl("selection-toolbar"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _selection_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(SelectionHighlight()) => let val _ = annot_highlight(Yellow()) in () end
        | ~$R.some(SelectionOrange()) => let val _ = annot_highlight(Orange()) in () end
        | ~$R.some(SelectionUnderline()) => let val _ = annot_highlight(Underlined()) in () end
        | ~$R.some(SelectionNote()) => annot_ask_note(annot_highlight(Yellow()), true)
        | ~$R.some(SelectionCopy()) => _copy_selection()
        | ~$R.some(SelectionSearch()) => _search_selection()
        | ~$R.some(SelectionDefine()) => dict_show()
        | ~$R.some(SelectionRead()) => aloud_from_selection()
        | ~$R.some(SelectionShare()) => _share_selection())
    in let val () = ui_show("selection-toolbar", false) in 0 end end)
  (* a word's dictionary entry: closed, or looked up online instead *)
  val listeners = RCons(listeners, OnEl("dictionary-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _dictionary_control(clicked)
      val () = _target_free(clicked)
    in
      case+ control of
      | ~$R.none() => 0
      (* the focus goes back where it was (layer.bats) *)
      | ~$R.some(DictionaryClose()) => let
          val () = layer_close(LDictionary())
        in 0 end
      (* the link opens the entry online *)
      | ~$R.some(DictionaryOnline()) => let val () = layer_close(LDictionary()) in 0 end
    end)
  val listeners = RCons(listeners, OnEl("annotations-button"), "click", llam(_) => let
      val () = annot_render()
      val () = layer_open(LAnnotations())
    in let val () = ui_focus("annotations-close") in 0 end end)
  val listeners = RCons(listeners, OnEl("annotations-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val go_row = _row_of(clicked, "highlight-go")
      val note_row = _row_of(clicked, "highlight-edit")
      val delete_row = _row_of(clicked, "highlight-delete")
      val control = _annotations_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.some(FilterAll()) => annot_filter_set(EveryStyle())
        | ~$R.some(FilterYellow()) => annot_filter_set(OnlyYellow())
        | ~$R.some(FilterOrange()) => annot_filter_set(OnlyOrange())
        | ~$R.some(FilterUnderlined()) => annot_filter_set(OnlyUnderlined())
        | ~$R.some(AnnotationsClose()) => layer_close(LAnnotations())
        | ~$R.some(AnnotationsExport()) => $P.finish<share_end>(_export(ToDownload()), llam(_) => ())
        | ~$R.some(AnnotationsShare()) => _share_annotations(share_as_now())
        | ~$R.none() =>
        if go_row >= 0 then let val () = layer_close(LAnnotations()) in _annotation_go(go_row) end
        else if note_row >= 0 then annot_ask_note(note_row, false)
        else if delete_row >= 0 then annot_delete_highlight(delete_row)
        else ())
    in 0 end)
  (* a note opened over the page: gone to, or closed *)
  val listeners = RCons(listeners, OnEl("footnote"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _footnote_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(FootnoteGo()) => let
          val () = layer_close(LNote())
          val () = reader_note_go()
        in ui_focus("page") end
        (* the focus goes back where it was (layer.bats) *)
        | ~$R.some(FootnoteClose()) => layer_close(LNote()))
    in 0 end)
in listeners end

fn _wire_search {count:nat} (listeners: regs(count)): regs(count + 4) = let
  val listeners = RCons(listeners, OnEl("search-button"), "click", llam(_) => let
      val () = (if layer_is_open(LSearch()) then layer_close(LSearch()) else _search_open())
    in 0 end)
  (* the field is made again for a selection's search: its events are
     taken on the panel *)
  val listeners = RCons(listeners, OnEl("search-panel"), "input", llam(_) => let val () = _search_input() in 0 end)
  val listeners = RCons(listeners, OnEl("search-panel"), "click", llam(h) => let
      val clicked = _target(h)
      val hit = _row_of(clicked, "search-hit")
      val close = (case+ _search_panel_control(clicked) of ~$R.some(SearchClose()) => true | ~$R.none() => false): bool
      val () = _target_free(clicked)
      (* the panel's Close: the focus goes back where it was (layer.bats) *)
      val () = (if close then let val () = layer_close(LSearch()) in _search_clear() end
        else if hit >= 0 then let
          val () = layer_close(LSearch())
        in reader_search_go(hit) end
        else ())
    in 0 end)
  val listeners = RCons(listeners, OnEl("search-nav"), "click", llam(h) => let
      val clicked = _target(h)
      val control = _search_nav_control(clicked)
      val () = _target_free(clicked)
      val () = (case+ control of
        | ~$R.none() => ()
        | ~$R.some(SearchPrevious()) => reader_search_step(~1)
        | ~$R.some(SearchNext()) => reader_search_step(1)
        | ~$R.some(SearchNavClose()) => _search_end())
    in 0 end)
in listeners end

fn _wire_reader {count:nat} (listeners: regs(count)): regs(count + 16) = let
  val listeners = RCons(listeners, OnEl("back-to-library"), "click", llam(_) => let val () = _show_library() in 0 end)
  val listeners = RCons(listeners, OnEl("previous-page"), "click", llam(_) => let val () = _hint_hide() in let val () = page_prev() in 0 end end)
  val listeners = RCons(listeners, OnEl("next-page"), "click", llam(_) => let val () = _hint_hide() in let val () = page_next() in 0 end end)
  val listeners = RCons(listeners, OnEl("page"), "click", llam(h) => let
      val clicked = _target(h)
      val node = _row_of(clicked, "c")
      val x = _target_x(clicked)
      val y = _target_y(clicked)
      val () = _target_free(clicked)
    in
      if _has_selection() then 0
      else if !_dragged then 0
      else if (if node >= 0 then reader_link_at(node) else false) then 0
      (* a single tap on an image is a tap on the page: the sides turn
         it, the middle brings up the bars; the image is shown full
         screen by a double tap or a long press (quire#365) *)
      else if x >= 0 then let
        (* a tap on text the narration reads, between the sides' zones,
           plays on from there; the bars come up or go as ever *)
        val () = (if node >= 0 then (if _in_middle(x) then narration_tap(node) else ()) else ())
      in let val () = _zone_click(x, y) in 0 end end
      else 0
    end)
  (* an image of the book, double-tapped between the sides' zones, is
     shown full screen, as Apple Books and Kobo show one (the two taps
     before it bring the bars up and put them away again) *)
  val listeners = RCons(listeners, OnEl("page"), "dblclick", llam(h) => let
      val clicked = _target(h)
      val node = _row_of(clicked, "c")
      val x = _target_x(clicked)
      val () = _target_free(clicked)
    in
      if _has_selection() then 0
      else if node < 0 then 0
      else if ~_side_zones() then 0
      else if ~_in_middle(x) then 0
      else if reader_image_at(node) then let val () = $EV.prevent_default() in 0 end
      else 0
    end)
  (* an image of the book, long-pressed (or right-clicked), is shown
     full screen, anywhere on the page *)
  val listeners = RCons(listeners, OnEl("page"), "contextmenu", llam(h) => let
      val clicked = _target(h)
      val node = _row_of(clicked, "c")
      val () = _target_free(clicked)
    in
      if node < 0 then 0
      else if reader_image_at(node) then let val () = $EV.prevent_default() in 0 end
      else 0
    end)
  val listeners = RCons(listeners, OnEl("image-viewer"), "click", llam(h) => let
      val clicked = _target(h)
      val close = (case+ _image_viewer_control(clicked) of ~$R.some(ImageClose()) => true | ~$R.none() => false): bool
      val () = _target_free(clicked)
    in
      (* the focus goes back where it was (layer.bats) *)
      if close then let
        val () = layer_close(LImage())
      in 0 end
      else 0
    end)
  (* a link within the book, focused from the keyboard, is followed with
     Enter *)
  val listeners = RCons(listeners, OnEl("page"), "focusin", llam(h) => let
      val clicked = _target(h)
      val node = _row_of(clicked, "c")
      val () = _target_free(clicked)
      val () = !_focus_link := node
    in 0 end)
  val listeners = RCons(listeners, OnEl("page"), "focusout", llam(_) => let val () = !_focus_link := ~1 in 0 end)
  val listeners = RCons(listeners, OnDocument(), "keydown", llam(h) =>
      case+ take_blob(h) of
      | ~NoBlobBytes() => 0
      | ~BlobBytes(key_bytes, n) => let
          val pressed = ui_key(key_bytes, n)
          val held = ui_modifiers(key_bytes, n)
          val () = $A.free<byte>(key_bytes)
          val () = (if (if _is_escape(pressed) then _escape_overlay() else false) then ()
            else if ~_in_reader() then ()
            else if _shown("dialog") then ()
            (* the Settings screen, and the screens it opens (sync's
               fields), are over the reader: keys are theirs *)
            else if layer_is_open(LSettings()) then ()
            else if layer_is_open(LSearch()) then _search_key(pressed, held)
            (* a reader panel is modal: no key turns the page behind it *)
            else if layer_reader_blocked() then ()
            else _reader_key(pressed, held))
        in 0 end)
  (* the wheel turns a page, then pauses a quarter second *)
  val listeners = RCons(listeners, OnEl("page"), "wheel", llam(h) =>
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
            val () = $P.finish<Int>($P.vow($TM.timer_set(250)), llam(_) => !_wheel_busy := false)
          in 0 end
        end)
  (* a tap on the footer's readout shows the next, and keeps it *)
  val listeners = RCons(listeners, OnEl("footer-readout"), "click", llam(_) => let
      val () = reader_readout_next()
      val () = set_save(lib_state_get())
    in 0 end)
  (* pointer events for the gestures: a horizontal drag turns the page
     (the reader view is the stable root; the page is region 1) *)
  val listeners = RCons(listeners, OnPointer("reader"), "pointer", llam(h) => let
      (* a reader panel is modal: the recognizer gets nothing behind it
         (the reader is inert then, and the scrim over it, so nothing
         should come) *)
      val () = (if layer_reader_blocked() then _gesture_drop(h) else _gesture_record(h))
    in 0 end)
  (* a tap on the scrim, outside a reader panel, closes the panel *)
  val listeners = RCons(listeners, OnEl("panel-scrim"), "click", llam(_) => let
      val () = layer_scrim_tapped()
    in 0 end)
  (* the focus at a stop before or after the panels: round to the open
     panel's last or first element, so Tab keeps to it *)
  val listeners = RCons(listeners, OnDocument(), "focusin", llam(h) => let
      val focused = _target(h)
      val () = (if _is(focused, "focus-wrap-end") then layer_focus_wrap(WrappedForward())
        else if _is(focused, "focus-wrap-start") then layer_focus_wrap(WrappedBackward())
        else ())
      val () = _target_free(focused)
    in 0 end)
  (* a resize lays the chapter out again, once it settles *)
  val listeners = RCons(listeners, OnWindow(), "resize", llam(_) => let
      val () = _relayout_settled()
    in 0 end)
  (* the browser's Back: it took the guard back.bats pushes once there
     is something to go back from, so the app goes one step back, and
     the guard is pushed again if there is still something; with nothing
     to go back from, it is the platform's Back, and the page is left *)
  (* the address itself is not needed: back.bats keeps what Back
     went back over *)
  val () = $NAV.set_popstate_callback(llam(url) => let
      val () = (case+ url of ~$R.some(bytes) => $BD.blob_free(bytes) | ~$R.none() => ())
      val () = (case+ back_popped() of
        | PoppedByBack() => (case+ _go_back() of WentBack() => () | AtRoot() => back_leave())
        | PoppedElsewhere() => ())
      val () = back_sync()
    in 0 end)
in listeners end

(* The platform's: reading aloud (its button, its speed and voice,
   speech's events, and the page going away, which stops it), the
   screen's controls (the brightness, and full screen entered or left),
   the browser's offer to install the app, and the addresses the app is
   opened at (Dropbox's sign-in coming back) *)
fn _wire_platform {count:nat} (listeners: regs(count)): regs(count + 12) = let
  val listeners = RCons(listeners, OnEl("read-aloud"), "click", llam(_) => let
      val () = aloud_toggle()
    in 0 end)
  val listeners = RCons(listeners, OnWindow(), "pagehide", llam(_) => let
      val () = aloud_stop()
    in 0 end)
  val listeners = RCons(listeners, OnEl("speech-rate"), "change", llam(_) => let
      val () = aloud_rate_chosen()
    in 0 end)
  val listeners = RCons(listeners, OnEl("speech-voice"), "change", llam(_) => let
      val () = aloud_voice_chosen()
    in 0 end)
  val listeners = RSpeech(listeners, llam(event) => aloud_event(event))
  (* the brightness slider: the screen follows it as it moves *)
  val listeners = RCons(listeners, OnEl("screen-brightness-slider"), "input", llam(h) => let
      val () = screen_brightness_moved(_input_number(h))
    in 0 end)
  val listeners = RFullscreen(listeners, llam(change) => screen_fullscreen_changed(change))
  (* the app is drawn edge to edge, so bars shown or hidden change the
     reading area's insets and no resize comes: the chapter is laid out
     again, keeping its place (quire#356) *)
  val listeners = RSystemBars(listeners, llam(bars) =>
    if screen_system_bars_changed(bars) then _relayout_for_bars() else ())
  val listeners = RInstallOffer(listeners, llam(offer) => platform_install_show(offer))
  val listeners = RAppLink(listeners, llam(link) => sync_app_link(link))
  (* Android's Back in the app: one step back, and at the library with
     nothing open, the app to the background, as Android does at an
     app's root *)
  val listeners = RBackButton(listeners, llam() =>
      case+ _go_back() of
      | WentBack() => ()
      | AtRoot() => $BB.app_minimize())
  (* a face that arrives after the chapter was laid out with a fallback
     changes its pages: they are counted again, the place kept. Whether
     others are still loading or not, what has arrived has changed the
     layout (one still loading may never arrive) *)
  val listeners = RFonts(listeners, llam(status) =>
      case+ status of
      | $ME.FontsSettled() => _fonts_arrived()
      | $ME.FontsStillLoading() => _fonts_arrived())
in listeners end

(* ============================================================
   Startup
   ============================================================ *)

(* Watches for a new version of the app (a new app.wasm served) and
   offers it: a notice whose Reload button reloads. It never reloads by
   itself, since a reload in the middle of reading would lose the
   scroll position and reading aloud's place *)
fn _build_watch (): void = let
  val url = $A.alloc<byte>(8)
  val () = $A.write_text(url, 0, $A.text_lit("app.wasm"), 8)
  val @(url_frozen, url_bytes) = $A.freeze<byte>(url)
  val watching = $BW.build_watch(url_bytes, 8)
  val () = release_bytes(url_frozen, url_bytes)
in
  $P.finish<$BW.build_change>(watching, llam(change) =>
    case+ change of
    | $BW.NewBuild() => ui_show("update-toast", true)
    (* the server cannot tell builds apart: nothing to offer *)
    | $BW.WatchEnded() => ())
end

(* The offer of a new version: Reload, or Dismiss *)
fn _wire_update {count:nat} (listeners: regs(count)): regs(count + 1) =
  RCons(listeners, OnEl("update-toast"), "click", llam(h) => let
    val clicked = _target(h)
    val control = _update_control(clicked)
    val () = _target_free(clicked)
    val () = (case+ control of
      | ~$R.none() => ()
      | ~$R.some(UpdateReload()) => $NAV.reload()
      | ~$R.some(UpdateDismiss()) => ui_show("update-toast", false))
  in 0 end)

(* How many files handed to the app from outside it are imported in a
   session, one after another. A metric needs the bound *)
#define EXTERNAL_ROUNDS 100000

(* Files handed to the app from outside it, kept: linear, so none is
   dropped without its file closed *)
datavtype handed(int) =
  | HandedNone(0)
  | {count:nat} HandedMore(count + 1) of ($BE.external, handed(count))

fn _handed_name_free (name: $R.option([k:nat] $BD.dblob(k))): void =
  case+ name of
  | ~$R.some(blob) => $BD.blob_free(blob)
  | ~$R.none() => ()

(* Files closed: none is here in practice (see _handed_keep) *)
fun _handed_close {count:nat} .<count>. (files: handed(count)): void =
  case+ files of
  | ~HandedNone() => ()
  | ~HandedMore(file, rest) => let
      val () = (case+ file of
        | ~$BE.External(book_file, name) => let
            val () = $BF.file_close(book_file)
          in _handed_name_free(name) end
        | ~$BE.ExternalUnreadable(name) => _handed_name_free(name))
    in _handed_close(rest) end

(* The files handed over while the library could not be read, kept for
   the session: a book added to a library that could not be read could
   not be saved (#174), and a file is not dropped (#262) *)
val _handed_kept = ref<[count:nat] handed(count)>(HandedNone())

fn _handed_keep (file: $BE.external): void = let
  var kept: [count:nat] handed(count) = HandedNone()
  val () = ref_exch_elt<[count:nat] handed(count)>(_handed_kept, kept)
  var whole: [count:nat] handed(count) = HandedMore(file, kept)
  val () = ref_exch_elt<[count:nat] handed(count)>(_handed_kept, whole)
  (* what the cell held between the two exchanges: nothing, since
     nothing runs between them *)
in _handed_close(whole) end

(* LIBRARY_READ: the library stored under "lib" has been read (or there
   was none), so a book added now is added to it. Before, a book imported
   was put in the library the read then replaced, and so was not shown
   (#262). Its constructor is local to _library_read, which makes one
   only once lib_load is done and the library was readable *)
local
dataprop LIBRARY_READ_() = LibraryReadProof of ()
in
stadef LIBRARY_READ = LIBRARY_READ_

(* How reading the library went: read, with the proof; or not readable
   (storage_unreadable has said so) *)
datavtype library_reading =
  | LibraryRead of (LIBRARY_READ() | )
  | LibraryUnreadable of ()

implement $P.dispose<library_reading>(reading) =
  case+ reading of ~LibraryRead(_ | ) => () | ~LibraryUnreadable() => ()

(* Reads the library: until it is read, no file handed to the app from
   outside it is asked for, so the bridge keeps them in their order *)
fn _library_read (): $P.promise(library_reading, $P.Chained) =
  $P.and_then<int><library_reading>(lib_load(), llam(_) =>
    if storage_savable(LibraryRecord()) then $P.ret<library_reading>(LibraryRead(LibraryReadProof() | ))
    else $P.ret<library_reading>(LibraryUnreadable()))
end

(* Imports each file handed to the app from outside it, as it comes,
   the library read (the proof): one at a time, the next asked for when
   the last one's import is done. The library is shown first, where the
   import is seen *)
fun _external_wait {rounds:nat} .<rounds>. (pf: LIBRARY_READ() | rounds: int rounds): void =
  if rounds <= 0 then ()
  else $P.finish<import_outcome>($P.and_then<$BE.external><import_outcome>($BE.external_next(), llam(handed) => let
      val () = (if _in_reader() then _show_library() else ())
    in import_external(handed) end), llam(outcome) => let
      (* its outcome is already reported *)
      val () = import_outcome_free(outcome)
    in _external_wait(pf | rounds - 1) end)

(* The library could not be read: each file handed over is kept, not
   added, and the banner says so *)
fun _external_keep {rounds:nat} .<rounds>. (rounds: int rounds): void =
  if rounds <= 0 then ()
  else $P.finish<$BE.external>($BE.external_next(), llam(handed) => let
      val () = _handed_keep(handed)
      val () = notice_say(HandedBookNotAdded())
    in _external_keep(rounds - 1) end)

(* Files handed to the app from outside it, once the library's reading
   is known: imported when it was read, kept when it was not *)
fn _external_start (reading: library_reading): void =
  case+ reading of
  | ~LibraryRead(pf | ) => _external_wait(pf | EXTERNAL_ROUNDS)
  | ~LibraryUnreadable() => _external_keep(EXTERNAL_ROUNDS)

(* The steps that wait for the library's reading, run once, whenever the
   reading is known: files handed to the app (imported when the library
   was read, kept when it was not), sync, the search and the view kept by
   the last run. At start-up they run as soon as the read ends, unless it
   failed for a reason Try again could change: then they wait for the one
   retry (_retry_read), and run when it ends, whichever way. *)
fn _after_read (reading: library_reading): $P.promise(int, $P.Chained) = let
  val () = _external_start(reading)
  val () = sync_start()
in
  $P.and_then<int><int>($P.and_then<int><int>(_query_restore(), llam(_) => _view_restore()), llam(view) => let
    (* back from Dropbox's sign-in: Settings, where it was asked
       for, and the sync screen comes over it as the sign-in ends *)
    val () = (if sync_returning() then _settings_open() else ())
  in $P.ret<int>(view) end)
end

(* Try again: the library is read again, once (#374). It repeats the one
   read start-up makes, through _library_read, so the proof that it was
   read is still only made there; on success the saving that was stopped
   resumes (storage_read_again), the library is shown, and the steps that
   waited run now, exactly once (lib_retry_begin refuses a second try).
   If it fails again the screen has no remedy for the rest of the session *)
fn _retry_read (): void =
  case+ lib_retry_begin() of
  | RetryNotOffered() => ()
  | RetryOffered() => let
      (* the failure's banner goes; a new failure raises its own *)
      val () = notice_dismiss()
      val () = ui_try_again_hide()
    in
      (* ignored: the steps deal with their own values *)
      $P.finish<int>($P.and_then<library_reading><int>(_library_read(), llam(reading) => let
        val () = lib_render()
      in _after_read(reading) end), llam(_) => ())
    end

(* Try again, on the library screen *)
fn _wire_retry {count:nat} (listeners: regs(count)): regs(count + 1) =
  RCons(listeners, OnEl("library-try-again"), "click", llam(h) => let
    val clicked = _target(h)
    val control = _retry_control(clicked)
    val () = _target_free(clicked)
    val () = (case+ control of
      | ~$R.none() => ()
      | ~$R.some(RetryRead()) => _retry_read())
  in 0 end)

implement main0 () = let
  val () = app_build()
  (* the page restores its own scroll when Back goes over a guard
     (back.bats) *)
  val () = back_start()
  (* the sync screen keeps its own elements *)
  val () = sync_screen_make()
  val () = _gestures_start()
  (* every listener, in one table: each one's id is its place in it *)
  val listeners = _wire_platform(_wire_settings_screen(_wire_sync(_wire_catalogues(_wire_search(_wire_annotations(_wire_toc(_wire_reader(_wire_settings(undo_listen(modal_listen(_wire_library(RNil()))))))))))))
  val listeners = _wire_update(listeners)
  val listeners = _wire_retry(listeners)
  (* the narration's controls and its audio's events *)
  val listeners = narration_listen(listeners)
  val () = ui_listen_all(listeners)
  val () = _build_watch()
  (* what the platform offers: reading aloud, sharing, installing, and
     whether the storage is kept *)
  val () = aloud_offer()
  val () = sharing_show()
  val () = platform_start()
  (* ignored: each load deals with its own value (a speed, the
     dictionaries and the catalogues not read start as none) *)
  val () = $P.finish<int>(reader_speed_load(), llam(_) => ())
  val () = _hint_load()
  val () = lib_install_hint_load()
  val () = stats_load()
  val () = stamp_load()
  val () = $P.finish<int>(dict_load(), llam(_) => _trash_dictionaries())
  val () = $P.finish<int>(catalogue_load(), llam(_) => ())
  (* nothing is shown until the view kept by the last run is known: a
     reader who was in a book comes back to it, not to the library *)
  val () = ui_show("library", false)
  val loaded = $P.and_then<int><int>(set_load(), llam(state) => let
      val () = lib_sort_label(lib_state_sort(state))
    in
      $P.and_then<library_reading><int>(_library_read(), llam(reading) => let
        val () = lib_state_set(state)
        (* the screen's controls, with the brightness and the lock kept *)
        val () = screen_controls_start()
        val () = lib_render()
      in
        (* the steps that wait for the read (files handed to the app from
           outside it, sync, the search and view kept): now, once the
           library is read (#262), or, when it could not be read for a
           reason Try again could change, after that retry. The bridge
           keeps the files in their order meanwhile *)
        case+ reading of
        | ~LibraryRead(pf | ) => _after_read(LibraryRead(pf | ))
        | ~LibraryUnreadable() =>
          (case+ lib_retry_offer() of
          | RetryOffered() => let val () = _library_shown(false) in $P.ret<int>(0) end
          | RetryNotOffered() => _after_read(LibraryUnreadable()))
      end)
    end)
(* ignored: each step deals with its own value (but see bats-lang/bridge#87:
   a library that could not be read is taken for none) *)
in $P.finish<int>(loaded, llam(_) => ()) end
