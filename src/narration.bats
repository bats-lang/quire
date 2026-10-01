(* narration -- a book's Media Overlays played: its recorded narration,
   clip by clip, the text each clip reads marked and kept on the page *)

(* The narration plays on one <audio id="narration"> (app.bats), for the
   whole book: a browser (and Android's WebView) that lets an element play
   once it has played from a click lets it go on, clip after clip and
   chapter after chapter. Each clip of the chapter's table (overlay.bats,
   reader.bats's chapter_clips) is played from its begin; a timer at its
   end, by the speed, checks where the audio is and moves on within 20 ms
   of the end (timeupdate is a backstop, and ended covers an audio file
   shorter than its clip). Each clip has a generation: a timer or answer
   for an earlier one is dropped. A page shown by the reader (a turn, a
   jump, a new chapter) moves the narration there; so does a tap on text
   a clip reads. The screen stays awake while the reader is open
   (quire.bats's _show_reader), so while the narration plays. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/decompress as DC

staload "ui.sats"
staload "book.sats"
staload "paths.sats"
staload "overlay.sats"
staload "reader.sats"
staload "settings.sats"
staload "mem.sats"
staload AU = "wasm.bats-packages.dev/bridge/src/audio.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"

(* The highlight the clip played is marked with: ::highlight(bats-mark-5),
   the stylesheet's *)
#define MARK_KIND 5

(* How near its end a clip is over, in ms *)
#define END_SLACK 20

#define MODE_UNCHANGED ~2
#define MODE_NONE ~1
#define MODE_IDLE 0
#define MODE_PLAYING 1
#define MODE_PAUSED 2

(* ============================================================
   State
   ============================================================ *)

(* Where the narration is in a chapter of count clips: nowhere; playing
   a clip, with its generation; or paused at a clip, to go on from a
   place in its audio (ms; -1 its begin). A clip is below count *)
datavtype narration_state(count:int) =
  | Idle(count) of ()
  | {clip:nat | clip < count} Playing(count) of (int clip, int)
  | {clip:nat | clip < count} Paused(count) of (int clip, int)

fn _state_free {count:int} (state: narration_state(count)): void =
  case+ state of
  | ~Idle() => ()
  | ~Playing(_, _) => ()
  | ~Paused(_, _) => ()

(* The state as a mode, its clip (0 when idle) and its generation (or,
   paused, where it goes on from) *)
fn _state_of {count:pos} (state: !narration_state(count)): @(int, [clip:nat | clip < count] int clip, int) =
  case+ state of
  | Idle() => @(MODE_IDLE, 0, 0)
  | Playing(clip, generation) => @(MODE_PLAYING, clip, generation)
  | Paused(clip, at) => @(MODE_PAUSED, clip, at)

(* The narration of the chapter shown: its clip table, from the reader,
   the chapter's number and where the narration is in it; or none, for a
   chapter without an overlay *)
datavtype narration =
  | {count:pos | count <= CLIP_MAX} Narrated of (clip_table(count), int count, int, narration_state(count))
  | Unnarrated of ()

fn _narration_free (held: narration): void =
  case+ held of
  | ~Narrated(table, _, _, state) => let
      val () = _state_free(state)
    in clip_table_free(table) end
  | ~Unnarrated() => ()

val _narration = ref<narration>(Unnarrated())

fn _take (): narration = let
  var cell: narration = Unnarrated()
  val () = ref_exch_elt<narration>(_narration, cell)
in cell end

fn _put (held: narration): void = let
  var cell: narration = held
  val () = ref_exch_elt<narration>(_narration, cell)
in _narration_free(cell) end

(* The mode of the narration: MODE_NONE without a table *)
fn _mode (): int = let
  val held = _take()
  val mode = (case+ held of
    | @Narrated(_, _, _, state) => let
        val @(mode, _, _) = _state_of(state)
        prval () = fold@(held)
      in mode end
    | Unnarrated() => MODE_NONE): int
  val () = _put(held)
in mode end

(* The number of the clip started last: what a timer or an answer for an
   earlier one is told apart by *)
val _generation = ref<int>(0)

fn _next_generation (): int = let
  val () = !_generation := !_generation + 1
in !_generation end

(* The generation of the clip whose audio paused by itself (a headset,
   a call, or the audio's end, which pauses it before it ends) *)
val _paused_by_itself = ref<int>(~1)

(* While the narration turns the page itself, and while it goes on into
   the next chapter: the pages shown then are not the reader's moves *)
val _turning = ref<bool>(false)
val _continuing = ref<bool>(false)

(* The page the narration left shown (the chapter's page), -1 for none:
   a page shown since is the reader's move *)
val _narration_page = ref<int>(~1)

fn _page_now (): int = case+ reading_get() of @(page, _, _, _) => page

(* The clips of the chapter the reader rendered last, taken when they are
   new: the mode of the narration they replace (MODE_NONE for none),
   MODE_UNCHANGED when there are none new *)
fn _sync (): int =
  case+ reader_clips_take() of
  | ~ClipsUnchanged() => MODE_UNCHANGED
  | ~ChapterClips(table, count, chapter) => let
      val mode = _mode()
      val () = _put(Narrated(table, count, chapter, Idle()))
    in mode end
  | ~ChapterSilent(_) => let
      val mode = _mode()
      val () = _put(Unnarrated())
    in mode end

(* Whether page numbers and notes are passed over *)
fn _skipping (): bool = set_narration_skip_get() = 1

(* ============================================================
   The audio element
   ============================================================ *)

fn _audio_id (): [l:agz] $A.arr(byte, l, 9) = let
  val id = $A.alloc<byte>(9)
  val () = $A.write_text(id, 0, $A.text_lit("narration"), 9)
in id end

fn _seek (ms: int): void = let
  val ms = g1ofg0(ms)
in
  if ms < 0 then ()
  else let
    val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
    val () = $AU.audio_seek(id_bytes, 9, ms)
  in release_bytes(id_frozen, id_bytes) end
end

fn _pause_audio (): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val () = $AU.audio_pause(id_bytes, 9)
in release_bytes(id_frozen, id_bytes) end

(* Where the audio is, in ms; -1 when it cannot be told *)
fn _time (): int = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val ms = $AU.audio_time(id_bytes, 9)
  val () = release_bytes(id_frozen, id_bytes)
in ms end

(* The speed chosen, in hundredths *)
fn _speed (): [hundredths:int | 50 <= hundredths; hundredths <= 200] int hundredths = 25 * set_narration_speed_get()

fn _rate (): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val () = $AU.audio_rate(id_bytes, 9, _speed())
in release_bytes(id_frozen, id_bytes) end

fn _play_audio (): $P.promise_pending(Int) = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val playing = $AU.audio_play(id_bytes, 9)
  val () = release_bytes(id_frozen, id_bytes)
in playing end

fn _pressed (playing: bool): void =
  if playing then ui_attr("narration-toggle", APressed, "true") else ui_attr("narration-toggle", APressed, "false")

(* ============================================================
   The audio's source: a blob URL of an audio entry of the book
   ============================================================ *)

(* The source set: its URL (revoked when it is replaced, and when the
   book is closed), the book and the entry's data offset it is of *)
datavtype source =
  | {l:agz}{url_len:pos | url_len < 2000} Source of ($A.arr(byte, l, url_len), int url_len, int, int)
  | NoSource of ()

val _source = ref<source>(NoSource())

fn _source_free (held: source): void =
  case+ held of
  | ~Source(url, url_len, _, _) => let
      val @(url_frozen, url_bytes) = $A.freeze<byte>(url)
      val () = $BL.revoke_blob_url(url_bytes, url_len)
    in release_bytes(url_frozen, url_bytes) end
  | ~NoSource() => ()

fn _source_put (held: source): void = let
  var cell: source = held
  val () = ref_exch_elt<source>(_source, cell)
in _source_free(cell) end

(* Whether the source set is the entry at data_offset of the open book *)
fn _source_is (data_offset: int): bool = let
  var cell: source = NoSource()
  val () = ref_exch_elt<source>(_source, cell)
  val same = (case+ cell of
    | Source(_, _, serial, offset) => (if serial = book_serial() then offset = data_offset else false)
    | NoSource() => false): bool
  val () = ref_exch_elt<source>(_source, cell)
  val () = _source_free(cell)
in same end

(* copy[i, url_len) := url[i, url_len) *)
fun _copy_url {url_loc,copy_loc:agz}{url_len:pos}{i:nat | i <= url_len} .<url_len - i>.
  (url: !$A.arr(byte, url_loc, url_len), copy: !$A.arr(byte, copy_loc, url_len), url_len: int url_len, i: int i): void =
  if i >= url_len then ()
  else let
    val () = $A.set<byte>(copy, i, $A.get<byte>(url, i))
  in _copy_url(url, copy, url_len, i + 1) end

(* The audio's source: url[0, url_len), of the entry at data_offset; the
   one it replaces is revoked *)
fn _source_set {l:agz}{url_len:pos | url_len < 2000} (url: $A.arr(byte, l, url_len), url_len: int url_len, data_offset: int): void = let
  val copy = $A.alloc<byte>(url_len)
  val () = _copy_url(url, copy, url_len, 0)
  val () = ui_attr_buf("narration", ASrc, copy, url_len)
in _source_put(Source(url, url_len, book_serial(), data_offset)) end

(* ============================================================
   The page: the clip's text marked, its page shown
   ============================================================ *)

(* Content nodes [first_node, end_node) marked as the clip read; nothing
   when the clip has none *)
fn _mark (first_node: int, end_node: int): void = let
  val () = $BDOM.clear_marks(MARK_KIND)
  val first_node = g1ofg0(first_node)
  val last_node = g1ofg0(end_node - 1)
in
  if first_node < 0 then ()
  else if last_node < first_node then ()
  else let
    val @(start_id, start_id_len) = nid_pad3("c", first_node)
    val @(end_id, end_id_len) = nid_pad3("c", last_node)
    val @(start_frozen, start_bytes) = $A.freeze<byte>(start_id)
    val @(end_frozen, end_bytes) = $A.freeze<byte>(end_id)
    (* to the end of the last node's text *)
    val () = $BDOM.mark_range(MARK_KIND, start_bytes, start_id_len, 0, end_bytes, end_id_len, 1000000)
    val () = release_bytes(end_frozen, end_bytes)
  in release_bytes(start_frozen, start_bytes) end
end

(* The button that leaves the escapable structure a clip is in (a table,
   a list, a figure, an aside), named for it; hidden outside one *)
fn _leave_show (kind: int, escape_to: int): void =
  if escape_to < 0 then ui_show("narration-leave", false)
  else let
    val () = (if kind = 2 then ui_text("narration-leave", "Skip list")
      else if kind = 3 then ui_text("narration-leave", "Skip figure")
      else if kind = 4 then ui_text("narration-leave", "Skip aside")
      else ui_text("narration-leave", "Skip table"))
  in ui_show("narration-leave", true) end

(* Clip, of the chapter's table, shown: its text marked, its page shown
   when it is not, and the button that leaves its structure *)
fn _clip_shown {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): void = let
  val first_node = clip_first_node(table, clip)
  val () = _mark(first_node, clip_end_node(table, clip))
  val place = (if first_node >= 0 then reader_node_place(first_node) else 2): int
  val () = (if (if place = ~1 then true else place = 1) then let
      val () = !_turning := true
      val () = reader_show_node(first_node)
    in !_turning := false end else ())
  val () = !_narration_page := _page_now()
in _leave_show(clip_escape_kind(table, clip), clip_escape_to(table, clip)) end

(* ============================================================
   Clips
   ============================================================ *)

(* The first clip from at on that plays: its audio found, and not passed
   over (skipping, a skippable one is); count when none does *)
fun _playable_from {count:pos}{at:nat | at <= count} .<count - at>.
  (table: !clip_table(count), count: int count, at: int at, skipping: bool): [found:nat | at <= found; found <= count] int found =
  if at >= count then count
  else if clip_audio_size(table, at) <= 0 then _playable_from(table, count, at + 1, skipping)
  else if (if skipping then clip_skippable(table, at) else false) then _playable_from(table, count, at + 1, skipping)
  else at

(* The last clip from at back that plays; -1 when none does *)
fun _playable_before {count:pos}{at:int | ~1 <= at; at < count} .<at + 1>.
  (table: !clip_table(count), count: int count, at: int at, skipping: bool): [found:int | ~1 <= found; found < count] int found =
  if at < 0 then ~1
  else if clip_audio_size(table, at) <= 0 then _playable_before(table, count, at - 1, skipping)
  else if (if skipping then clip_skippable(table, at) else false) then _playable_before(table, count, at - 1, skipping)
  else at

(* The first clip that plays from the first whose text is on the page
   shown or after it, from at on; the chapter's first that plays when
   none is *)
fun _from_page {count:pos}{at:nat | at <= count} .<count - at>.
  (table: !clip_table(count), count: int count, at: int at, skipping: bool): [found:nat | found <= count] int found =
  if at >= count then _playable_from(table, count, 0, skipping)
  else if ~clip_matched(table, at) then _from_page(table, count, at + 1, skipping)
  else let
    val place = reader_node_place(clip_first_node(table, at))
  in
    if (if place = 0 then true else place = 1) then let
      val found = _playable_from(table, count, at, skipping)
    in if found < count then found else _playable_from(table, count, 0, skipping) end
    else _from_page(table, count, at + 1, skipping)
  end

(* The clip whose text has content node node, the innermost (the one
   that starts last) from at on, or best; -1 when none has *)
fun _clip_of_node {count:pos}{at:nat | at <= count}{best:int | ~1 <= best; best < count} .<count - at>.
  (table: !clip_table(count), count: int count, at: int at, node: int, best: int best): [found:int | ~1 <= found; found < count] int found =
  if at >= count then best
  else if ~clip_matched(table, at) then _clip_of_node(table, count, at + 1, node, best)
  else if clip_audio_size(table, at) <= 0 then _clip_of_node(table, count, at + 1, node, best)
  else let
    val first_node = clip_first_node(table, at)
  in
    if first_node > node then _clip_of_node(table, count, at + 1, node, best)
    else if clip_end_node(table, at) <= node then _clip_of_node(table, count, at + 1, node, best)
    else _clip_of_node(table, count, at + 1, node, at)
  end

(* The clip playing starts from: the chapter's first that plays when
   from_start, else the first on the page shown *)
fn _start_clip {count:pos} (table: !clip_table(count), count: int count, from_start: bool, skipping: bool): [clip:nat | clip <= count] int clip =
  if from_start then _playable_from(table, count, 0, skipping) else _from_page(table, count, 0, skipping)

(* The clip a step goes to from clip (from the page shown when idle):
   the next that plays, or the one before (clip itself when none is) *)
fn _step_target {count:pos}{clip:nat | clip < count}
  (table: !clip_table(count), count: int count, idle: bool, clip: int clip, forward: bool, skipping: bool): [target:nat | target <= count] int target =
  if idle then _from_page(table, count, 0, skipping)
  else if forward then _playable_from(table, count, clip + 1, skipping)
  else let
    val before = _playable_before(table, count, clip - 1, skipping)
  in if before >= 0 then before else clip end

(* The clip leaving a structure goes to, the first that plays from
   escape_to (count for the chapter's end) *)
fn _leave_target {count:pos} (table: !clip_table(count), count: int count, escape_to: int, skipping: bool): [target:nat | target <= count] int target = let
  val escape_to = g1ofg0(escape_to)
in
  if escape_to < 0 then count
  else if escape_to >= count then count
  else _playable_from(table, count, escape_to, skipping)
end

(* The clip a tap on content node node plays from, playing; -1 for none *)
fn _tap_target {count:pos} (table: !clip_table(count), count: int count, playing: bool, node: int): [target:int | ~1 <= target; target < count] int target =
  if playing then _clip_of_node(table, count, 0, node, ~1) else ~1

(* Whether the narration is where the reader left it: the page it left
   shown, or the clip's text on the page shown *)
fn _still_shown {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): bool =
  if _page_now() = !_narration_page then true
  else if ~clip_matched(table, clip) then false
  else reader_node_place(clip_first_node(table, clip)) = 0

(* ============================================================
   Playing
   ============================================================ *)

(* Stops: the narration is idle, its audio paused, nothing marked *)
fn _stop (): void = let
  val () = !_generation := !_generation + 1
  val held = _take()
  val () = (case+ held of
    | @Narrated(_, _, _, state) => let
        val () = _state_free(state)
        val () = state := Idle()
        prval () = fold@(held)
      in end
    | Unnarrated() => ())
  val () = _put(held)
  val () = _pause_audio()
  val () = $BDOM.clear_marks(MARK_KIND)
  val () = ui_show("narration-leave", false)
in _pressed(false) end

(* Stops, saying the narration cannot be played *)
fn _failed (): void = let
  val () = _stop()
in ui_show("narration-error", true) end

(* Clip generation's end: a timer at it, by the speed, checks where the
   audio is (_tick) *)
fn _clip_end_of (generation: int): int = let
  val held = _take()
  val end_ms = (case+ held of
    | @Narrated(table, _, _, state) => let
        val @(mode, clip, playing_generation) = _state_of(state)
        val end_ms = (if mode <> MODE_PLAYING then ~2 else if playing_generation <> generation then ~2 else clip_end(table, clip)): int
        prval () = fold@(held)
      in end_ms end
    | Unnarrated() => ~2): int
  val () = _put(held)
in end_ms end

(* What a clip's timer runs when it fires: _tick (set by
   narration_listen). A timer firing is an event, as a click is: it reaches
   the code it runs through this cell, as a click reaches its listener's,
   not by a call, so playing on, clip after clip, is not a recursion *)
datatype tick_handler = TickHandler of ((int) -<cloref1> void) | NoTickHandler of ()

val _tick_handler = ref<tick_handler>(NoTickHandler())

(* A timer at clip generation's end, by the speed: at most a second
   ahead, so a speed changed meanwhile is caught *)
fn _arm (generation: int): void = let
  val end_ms = _clip_end_of(generation)
in
  if end_ms < 0 then ()
  else let
    val now = _time()
    val left = end_ms - now
    val delay = (if now < 0 then 250 else if left <= 0 then 0 else if left > 10000 then 1000
      else left * 100 / _speed()): int
    val delay = (if delay > 1000 then 1000 else if delay < 0 then 0 else delay): int
  in
    $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(delay)), lam(_) => let
      val () = (case+ !_tick_handler of
        | TickHandler(run) => run(generation)
        | NoTickHandler() => ())
    in $P.ret<int>(0) end))
  end
end

(* The audio played (generation's clip), from from_ms when seek *)
fn _play_at (generation: int, from_ms: int, seek: bool): void =
  if generation <> !_generation then ()
  else let
    val () = (if seek then _seek(from_ms) else ())
    (* a new source starts at the element's default speed *)
    val () = _rate()
    val () = _pressed(true)
    val () = ui_show("narration-error", false)
    val playing = _play_audio()
    val () = $P.discard<int>($P.and_then<Int><int>($P.vow(playing), lam(result) => let
        (* refused, or not playable: the clip it was for, if it still
           plays, cannot be *)
        val () = (if result <> 0 then (if generation = !_generation then _failed() else ()) else ())
      in $P.ret<int>(0) end))
  in _arm(generation) end

(* The audio of the entry at data_offset (data_size bytes, deflated or
   stored, of type kind) as the audio's source, when it is not already;
   then go, told whether it is new *)
fn _source_then {kind:nat | kind <= 4} (generation: int, data_offset: int, data_size: int, deflated: bool, kind: int kind,
  go: (bool) -<cloref1> void): void =
  if _source_is(data_offset) then go(false)
  else if ~deflated then
    (case+ book_blob_url(book_serial(), data_offset, data_size, audio_mime(kind)) of
     | ~BlobUrl(url, url_len) => let
         val () = _source_set(url, url_len, data_offset)
       in go(true) end
     | ~NoBlobUrl() => _failed())
  else (case+ book_meta_get() of
    | ~$R.none() => _failed()
    | ~$R.some(@(file_size, _, _, _, _, _)) => let
        val offset = g1ofg0(data_offset)
        val size = g1ofg0(data_size)
      in
        if offset < 0 then _failed()
        else if size <= 0 then _failed()
        else if size > 268435456 then _failed()
        else if offset > file_size - size then _failed()
        else (case+ piece_new(size) of
          | ~NoPiece() => _failed()
          | ~Piece(compressed_owner, compressed) => let
              val _ = book_read(book_serial(), file_size, offset, compressed, size)
              val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
              val decompressing = $DC.decompress(compressed_bytes, size, 8)
              val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
              val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
            in
              (* decompressed into a piece, made a blob URL, and the piece
                 freed *)
              $P.discard<int>($P.and_then<Int><int>($P.vow(decompressing), lam(handle) =>
                case+ take_content(handle) of
                | ~NoContentBytes() => let
                    val () = (if generation = !_generation then _failed() else ())
                  in $P.ret<int>(0) end
                | ~ContentBytes(content_owner, content, content_len) => let
                    val mime = audio_mime(kind)
                    val mime_len = g1u2i(string1_length(mime))
                    val mime_buf = $A.alloc<byte>(mime_len)
                    val () = $A.write_text(mime_buf, 0, $A.text_lit(mime), mime_len)
                    val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime_buf)
                    val @(content_frozen, content_bytes) = $A.freeze<byte>(content)
                    val made = $BL.create_blob_url(content_bytes, content_len, mime_bytes, mime_len)
                    val () = $A.drop<byte>(content_frozen, content_bytes)
                    val () = piece_free(content_owner, $A.thaw<byte>(content_frozen))
                    val () = release_bytes(mime_frozen, mime_bytes)
                    val () = (case+ blob_url_take(made) of
                      | ~BlobUrl(url, url_len) =>
                        if generation = !_generation then let
                          val () = _source_set(url, url_len, data_offset)
                        in go(true) end
                        else $A.free<byte>(url)
                      | ~NoBlobUrl() => if generation = !_generation then _failed() else ())
                  in $P.ret<int>(0) end))
            end)
      end)

(* Plays the clip the narration is at, when it is clip generation's: its
   text marked and its page shown, its audio loaded, then played from
   from_ms (-1 its begin; -2 on from where the audio is, the clip after
   the one before in it) *)
fn _begin (generation: int, from_ms: int): void = let
  val held = _take()
in
  case+ held of
  | @Narrated(table, _, _, state) => let
      val @(mode, clip, playing_generation) = _state_of(state)
    in
      if (if mode <> MODE_PLAYING then true else playing_generation <> generation) then let
        prval () = fold@(held)
      in _put(held) end
      else let
        val data_offset = clip_audio_offset(table, clip)
        val data_size = clip_audio_size(table, clip)
        val deflated = clip_deflated(table, clip)
        val kind = clip_audio_kind(table, clip)
        val begin_ms = clip_begin(table, clip)
        val () = _clip_shown(table, clip)
        prval () = fold@(held)
        val () = _put(held)
      in
        _source_then(generation, data_offset, data_size, deflated, kind, lam(fresh) =>
          if (if from_ms = ~2 then ~fresh else false) then _play_at(generation, ~1, false)
          else _play_at(generation, (if from_ms >= 0 then from_ms else begin_ms), true))
      end
    end
  | Unnarrated() => _put(held)
end

(* Plays from the first clip on the page shown (from the chapter's first
   when from_start): false when the chapter has none that plays *)
fn _play_from (from_start: bool): bool = let
  val held = _take()
in
  case+ held of
  | @Narrated(table, count, _, state) => let
      val skipping = _skipping()
      val clip = _start_clip(table, count, from_start, skipping)
    in
      if clip >= count then let
        val () = _state_free(state)
        val () = state := Idle()
        prval () = fold@(held)
        val () = _put(held)
      in false end
      else let
        val generation = _next_generation()
        val () = _state_free(state)
        val () = state := Playing(clip, generation)
        prval () = fold@(held)
        val () = _put(held)
        val () = _begin(generation, ~1)
      in true end
    end
  | Unnarrated() => let
      val () = _put(held)
    in false end
end

(* The most chapters the narration passes over, going on, that have
   nothing it plays *)
#define CHAPTERS_PASSED 10000

(* Goes on into the next chapter after chapter that has an overlay, and
   on past those with nothing it plays (fuel more of them); stops when
   none is left *)
fun _continue_after {fuel:nat} .<fuel>. (chapter: int, fuel: int fuel): void = let
  val next = book_narrated_after(book_serial(), chapter)
in
  if next < 0 then _stop()
  else let
    val generation = _next_generation()
    val () = !_continuing := true
    val () = _pause_audio()
  in
    $P.discard<int>($P.and_then<int><int>(reader_goto(next, 0, ~1), lam(result) => let
      val () = !_continuing := false
    in
      if generation <> !_generation then $P.ret<int>(0)
      else if result < 0 then let val () = _stop() in $P.ret<int>(0) end
      else let
        val _ = _sync()
        val () = (if _play_from(true) then () else if fuel > 0 then _continue_after(next, fuel - 1) else _stop())
      in $P.ret<int>(0) end
    end))
  end
end

(* The chapter the reader is in (from 0) *)
fn _chapter_now (): int = case+ reading_get() of @(_, _, chapter, _) => (if chapter > 0 then chapter - 1 else 0)

(* Plays from the page shown; a chapter with nothing to play goes on to
   the next *)
fn _play_here (): void =
  if _play_from(false) then ()
  else if reader_narrated() then _continue_after(_chapter_now(), CHAPTERS_PASSED)
  else ()

(* A clip has ended: the next that plays, or the next narrated chapter *)
fn _advance (generation: int): void = let
  val held = _take()
in
  case+ held of
  | @Narrated(table, count, chapter, state) => let
      val chapter_number = chapter
      val @(mode, clip, playing_generation) = _state_of(state)
    in
      if (if mode <> MODE_PLAYING then true else playing_generation <> generation) then let
        prval () = fold@(held)
      in _put(held) end
      else let
        val next = _playable_from(table, count, clip + 1, _skipping())
      in
        if next >= count then let
          val () = _state_free(state)
          val () = state := Idle()
          prval () = fold@(held)
          val () = _put(held)
        in _continue_after(chapter_number, CHAPTERS_PASSED) end
        else let
          (* the next clip right after this one in the same audio plays on
             without a seek *)
          val end_ms = clip_end(table, clip)
          val gap = clip_begin(table, next) - end_ms
          val seamless = (if clip_audio_offset(table, next) <> clip_audio_offset(table, clip) then false
            else if end_ms < 0 then false
            else if gap > END_SLACK then false
            else gap >= ~END_SLACK): bool
          val next_generation = _next_generation()
          val () = _state_free(state)
          val () = state := Playing(next, next_generation)
          prval () = fold@(held)
          val () = _put(held)
        in _begin(next_generation, (if seamless then ~2 else ~1)) end
      end
    end
  | Unnarrated() => _put(held)
end

(* ============================================================
   What the reader does
   ============================================================ *)

(* A clip's timer: the clip's end, when the audio is within END_SLACK of
   it; else the timer again *)
fn _tick (generation: int): void =
  if generation <> !_generation then ()
  else let
    val end_ms = _clip_end_of(generation)
  in
    if end_ms < 0 then ()
    else if _time() >= end_ms - END_SLACK then _advance(generation)
    else _arm(generation)
  end

(* Read aloud: plays from the page shown, pauses, or goes on *)
fn _toggle (): void = let
  val _ = _sync()
  val held = _take()
in
  case+ held of
  | @Narrated(table, _, _, state) => let
      val @(mode, clip, extra) = _state_of(state)
    in
      if mode = MODE_PLAYING then let
        val at = _time()
        val () = !_generation := !_generation + 1
        val () = _state_free(state)
        val () = state := Paused(clip, at)
        prval () = fold@(held)
        val () = _put(held)
        val () = _pause_audio()
      in _pressed(false) end
      else if mode = MODE_PAUSED then let
        (* on from where it paused, when that is in the clip *)
        val begin_ms = clip_begin(table, clip)
        val end_ms = clip_end(table, clip)
        val from_ms = (if extra < begin_ms then ~1 else if end_ms < 0 then extra else if extra < end_ms then extra else ~1): int
        val generation = _next_generation()
        val () = _state_free(state)
        val () = state := Playing(clip, generation)
        prval () = fold@(held)
        val () = _put(held)
      in _begin(generation, from_ms) end
      else let
        prval () = fold@(held)
        val () = _put(held)
      in _play_here() end
    end
  | Unnarrated() => let
      val () = _put(held)
    in _play_here() end
end

(* Previous phrase, or next: playing, it plays; else the narration is
   paused there *)
fn _step (forward: bool): void = let
  val _ = _sync()
  val held = _take()
in
  case+ held of
  | @Narrated(table, count, chapter, state) => let
      val chapter_number = chapter
      val @(mode, clip, _) = _state_of(state)
      val skipping = _skipping()
      val target = _step_target(table, count, mode = MODE_IDLE, clip, forward, skipping)
    in
      if target >= count then
        (if mode = MODE_PLAYING then let
           val () = _state_free(state)
           val () = state := Idle()
           prval () = fold@(held)
           val () = _put(held)
         in _continue_after(chapter_number, CHAPTERS_PASSED) end
         else let
           prval () = fold@(held)
         in _put(held) end)
      else if mode = MODE_PLAYING then let
        val generation = _next_generation()
        val () = _state_free(state)
        val () = state := Playing(target, generation)
        prval () = fold@(held)
        val () = _put(held)
      in _begin(generation, ~1) end
      else let
        val () = _clip_shown(table, target)
        val () = _state_free(state)
        val () = state := Paused(target, ~1)
        prval () = fold@(held)
      in _put(held) end
    end
  | Unnarrated() => _put(held)
end

(* Leaves the escapable structure the narration is in: on after it *)
fn _leave (): void = let
  val _ = _sync()
  val held = _take()
in
  case+ held of
  | @Narrated(table, count, chapter, state) => let
      val chapter_number = chapter
      val @(mode, clip, _) = _state_of(state)
      val escape_to = (if mode = MODE_IDLE then ~1 else clip_escape_to(table, clip)): Int
    in
      if escape_to < 0 then let
        prval () = fold@(held)
      in _put(held) end
      else let
        val target = _leave_target(table, count, escape_to, _skipping())
      in
        if target >= count then let
          val () = _state_free(state)
          val () = state := Idle()
          prval () = fold@(held)
          val () = _put(held)
        in if mode = MODE_PLAYING then _continue_after(chapter_number, CHAPTERS_PASSED) else _stop() end
        else if mode = MODE_PLAYING then let
          val generation = _next_generation()
          val () = _state_free(state)
          val () = state := Playing(target, generation)
          prval () = fold@(held)
          val () = _put(held)
        in _begin(generation, ~1) end
        else let
          val () = _clip_shown(table, target)
          val () = _state_free(state)
          val () = state := Paused(target, ~1)
          prval () = fold@(held)
        in _put(held) end
      end
    end
  | Unnarrated() => _put(held)
end

(* A page shown that the narration did not turn to (a turn, a jump, a new
   chapter): playing, it plays on from there; paused, it is paused there *)
fn _moved (): void =
  if !_continuing then ()
  else let
    val replaced = _sync()
    val held = _take()
  in
    case+ held of
    | @Narrated(table, count, _, state) => let
        val @(mode_now, clip, _) = _state_of(state)
        val mode = (if replaced <> MODE_UNCHANGED then replaced else mode_now): int
        val kept = (if replaced <> MODE_UNCHANGED then false
          else if mode_now = MODE_IDLE then true
          else _still_shown(table, clip)): bool
      in
        if kept then let
          prval () = fold@(held)
        in _put(held) end
        else if mode = MODE_PLAYING then let
          prval () = fold@(held)
          val () = _put(held)
        in _play_here() end
        else if mode = MODE_PAUSED then let
          val target = _from_page(table, count, 0, _skipping())
        in
          if target >= count then let
            val () = _state_free(state)
            val () = state := Idle()
            prval () = fold@(held)
          in _put(held) end
          else let
            val () = _clip_shown(table, target)
            val () = _state_free(state)
            val () = state := Paused(target, ~1)
            prval () = fold@(held)
          in _put(held) end
        end
        else let
          prval () = fold@(held)
        in _put(held) end
      end
    | Unnarrated() => let
        val () = _put(held)
      in if replaced = MODE_PLAYING then _stop() else () end
  end

(* The audio's events *)

(* timeupdate: the clip's end, when the timer has not caught it *)
fn _time_update (): void = let
  val generation = !_generation
  val end_ms = _clip_end_of(generation)
in
  if end_ms < 0 then ()
  else if _time() >= end_ms - END_SLACK then _advance(generation)
  else ()
end

(* ended: the audio file is over, before its clip or at its end *)
fn _ended (): void = let
  val generation = !_generation
  val held = _take()
in
  case+ held of
  | @Narrated(_, _, _, state) => let
      val @(mode, clip, _) = _state_of(state)
    in
      if mode = MODE_PLAYING then let
        prval () = fold@(held)
        val () = _put(held)
      in _advance(generation) end
      (* the audio's end pauses it first *)
      else if (if mode = MODE_PAUSED then !_paused_by_itself = generation else false) then let
        val () = _state_free(state)
        val () = state := Playing(clip, generation)
        prval () = fold@(held)
        val () = _put(held)
        val () = _pressed(true)
      in _advance(generation) end
      else let
        prval () = fold@(held)
      in _put(held) end
    end
  | Unnarrated() => _put(held)
end

(* pause: a pause the narration did not ask for (a headset, a call, the
   audio's end) leaves it paused *)
fn _paused (): void = let
  val held = _take()
in
  case+ held of
  | @Narrated(_, _, _, state) => let
      val @(mode, clip, generation) = _state_of(state)
    in
      if mode = MODE_PLAYING then let
        val () = !_paused_by_itself := generation
        val () = _state_free(state)
        val () = state := Paused(clip, _time())
        prval () = fold@(held)
        val () = _put(held)
      in _pressed(false) end
      else let
        prval () = fold@(held)
      in _put(held) end
    end
  | Unnarrated() => _put(held)
end

(* error: the audio cannot be played *)
fn _media_error (): void = let
  val mode = _mode()
in if (if mode = MODE_PLAYING then true else mode = MODE_PAUSED) then _failed() else () end

(* ============================================================
   For the app
   ============================================================ *)

(* A tap on content node node: playing, the narration plays on from the
   clip whose text it is in, when that is not the one it plays (a tap
   that brings the bars up is often on it) *)
#pub fn narration_tap (node: int): void

implement narration_tap (node) =
  if !_continuing then ()
  else let
    val _ = _sync()
    val held = _take()
  in
    case+ held of
    | @Narrated(table, count, _, state) => let
        val @(mode, clip, _) = _state_of(state)
        val target = _tap_target(table, count, mode = MODE_PLAYING, node)
      in
        if target < 0 then let
          prval () = fold@(held)
        in _put(held) end
        else if target = clip then let
          prval () = fold@(held)
        in _put(held) end
        else let
          val generation = _next_generation()
          val () = _state_free(state)
          val () = state := Playing(target, generation)
          prval () = fold@(held)
          val () = _put(held)
        in _begin(generation, ~1) end
      end
    | Unnarrated() => _put(held)
  end

(* The speed chosen, applied at once *)
#pub fn narration_rate (): void
implement narration_rate () = _rate()

(* The book is closed: the narration stops, its clips are freed and its
   source revoked *)
#pub fn narration_close (): void

implement narration_close () = let
  val () = !_generation := !_generation + 1
  val () = !_continuing := false
  val () = !_narration_page := ~1
  val () = _put(Unnarrated())
  val () = reader_clips_forget()
  val () = _pause_audio()
  val () = $BDOM.clear_marks(MARK_KIND)
  val () = _pressed(false)
  val () = ui_show("narration-leave", false)
  val () = ui_show("narration-error", false)
in _source_put(NoSource()) end

(* Whether a click's target, event_bytes[10, n), is id *)
fun _id_from {l:agz}{n:nat}{id_len:nat}{i:nat | i <= id_len} .<id_len - i>.
  (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len, id_len: int id_len, i: int i): bool =
  if i >= id_len then 10 + id_len = n
  else if 10 + i >= n then false
  else if byte2int0($A.get<byte>(event_bytes, 10 + i)) <> char2int0(string_get_at(id, i)) then false
  else _id_from(event_bytes, n, id, id_len, i + 1)

fn _id_is {l:agz}{n:nat}{id_len:nat} (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len): bool =
  _id_from(event_bytes, n, id, g1u2i(string1_length(id)), 0)

(* The narration's listeners: its controls, the audio's events and its
   error's dismissal; and the reader's pages shown, which move it *)
#pub fn narration_listen {count:nat} (listeners: regs(count)): regs(count + 6)

implement narration_listen (listeners) = let
  val () = !_tick_handler := TickHandler(lam(generation) => _tick(generation))
  val () = reader_on_page_shown(lam () =>
    if !_turning then ()
    else if !_continuing then ()
    (* after the page's own work is done *)
    else $P.discard<int>($P.and_then<Int><int>($P.vow($TM.timer_set(0)), lam(_) => let
        val () = _moved()
      in $P.ret<int>(0) end)))
  val listeners = RCons(listeners, OnEl("narration-controls"), "click", lam(h) =>
    case+ take_blob(h) of
    | ~NoBlobBytes() => 0
    | ~BlobBytes(event_bytes, n) => let
        val toggle = _id_is(event_bytes, n, "narration-toggle")
        val previous = _id_is(event_bytes, n, "narration-previous")
        val next = _id_is(event_bytes, n, "narration-next")
        val leave = _id_is(event_bytes, n, "narration-leave")
        val () = $A.free<byte>(event_bytes)
        val () = (if toggle then _toggle() else if previous then _step(false) else if next then _step(true)
          else if leave then _leave() else ())
      in 0 end)
  val listeners = RCons(listeners, OnEl("narration"), "timeupdate", lam(_) => let val () = _time_update() in 0 end)
  val listeners = RCons(listeners, OnEl("narration"), "ended", lam(_) => let val () = _ended() in 0 end)
  val listeners = RCons(listeners, OnEl("narration"), "pause", lam(_) => let val () = _paused() in 0 end)
  val listeners = RCons(listeners, OnEl("narration"), "error", lam(_) => let val () = _media_error() in 0 end)
  val listeners = RCons(listeners, OnEl("narration-error"), "click", lam(h) =>
    case+ take_blob(h) of
    | ~NoBlobBytes() => 0
    | ~BlobBytes(event_bytes, n) => let
        val dismiss = _id_is(event_bytes, n, "narration-error-dismiss")
        val () = $A.free<byte>(event_bytes)
      in if dismiss then let val () = ui_show("narration-error", false) in 0 end else 0 end)
in listeners end

end (* #target wasm *)
