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
   (quire.bats's _show_reader), so while the narration plays.

   Playing on, clip after clip, is a chain of timers and answers, each
   running the next step: the steps are one group of functions, and each
   step spends one of the chain's rounds (NARRATION_ROUNDS, more than a
   day of clips), so the chain is a recursion with a metric. A user's
   action or an audio event starts a chain anew. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R

staload "ui.sats"
staload "book.sats"
staload "paths.sats"
staload "overlay.sats"
staload "reader.sats"
staload "settings.sats"
staload "mem.sats"
staload "notice.sats"
staload AU = "wasm.bats-packages.dev/bridge/src/audio.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
#use zip as Z

(* The highlight the clip played is marked with: ::highlight(bats-mark-5),
   the stylesheet's *)
#define MARK_KIND 5

(* How near its end a clip is over, in ms *)
#define END_SLACK 20

(* The steps a chain of timers and answers runs at most (a clip's timer
   checks at least once a second: more than a day of narration) *)
#define NARRATION_ROUNDS 100000000

(* ============================================================
   State
   ============================================================ *)

(* Where a paused narration goes on from: a place in its clip's audio
   (ms), or the clip's begin *)
datavtype resume = ResumeAt of (int) | ResumeFromBegin of ()

(* Where the narration is in a chapter of count clips: nowhere; playing
   a clip, with its generation; or paused at a clip. A clip is below
   count *)
datavtype narration_state(count:int) =
  | Idle(count) of ()
  | {clip:nat | clip < count} Playing(count) of (int clip, int)
  | {clip:nat | clip < count} Paused(count) of (int clip, resume)

fn _state_free {count:int} (state: narration_state(count)): void =
  case+ state of
  | ~Idle() => ()
  | ~Playing(_, _) => ()
  | ~Paused(_, ~ResumeAt(_)) => ()
  | ~Paused(_, ~ResumeFromBegin()) => ()

(* What the narration is doing *)
datatype mode = ModeIdle | ModePlaying | ModePaused

fn _mode_of {count:int} (state: !narration_state(count)): mode =
  case+ state of
  | Idle() => ModeIdle()
  | Playing(_, _) => ModePlaying()
  | Paused(_, _) => ModePaused()

fn _is_playing (mode: mode): bool = case+ mode of ModePlaying() => true | _ => false
fn _is_paused (mode: mode): bool = case+ mode of ModePaused() => true | _ => false
fn _is_idle (mode: mode): bool = case+ mode of ModeIdle() => true | _ => false

(* The clip the narration is at: its clip, or 0 when idle *)
fn _clip_of {count:pos} (state: !narration_state(count)): [clip:nat | clip < count] int clip =
  case+ state of
  | Idle() => 0
  | Playing(clip, _) => clip
  | Paused(clip, _) => clip

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

(* What the narration is doing; none without a table *)
fn _mode (): $R.option(mode) = let
  val held = _take()
  val mode = (case+ held of
    | @Narrated(_, _, _, state) => let
        val mode = _mode_of(state)
        prval () = fold@(held)
      in $R.some(mode) end
    | Unnarrated() => $R.none()): $R.option(mode)
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

(* What taking the reader's new clips replaced: nothing (there were no
   new ones); no narration; or a narration idle, playing or paused *)
datatype renewal = Unrenewed | RenewedNone | RenewedIdle | RenewedPlaying | RenewedPaused

fn _renewal_of (replaced: $R.option(mode)): renewal =
  case+ replaced of
  | ~$R.none() => RenewedNone()
  | ~$R.some(ModeIdle()) => RenewedIdle()
  | ~$R.some(ModePlaying()) => RenewedPlaying()
  | ~$R.some(ModePaused()) => RenewedPaused()

(* The clips of the chapter the reader rendered last, taken when they are
   new: what they replace *)
fn _sync (): renewal =
  case+ reader_clips_take() of
  | ~ClipsUnchanged() => Unrenewed()
  | ~ChapterClips(table, count, chapter) => let
      val replaced = _mode()
      val () = _put(Narrated(table, count, chapter, Idle()))
    in _renewal_of(replaced) end
  | ~ChapterSilent(_) => let
      val replaced = _mode()
      val () = _put(Unnarrated())
    in _renewal_of(replaced) end

(* Whether page numbers and notes are passed over *)
fn _skipping (): bool = (case+ set_narration_notes_get() of NotesSkipped() => true | NotesRead() => false)

(* ============================================================
   The audio element
   ============================================================ *)

fn _audio_id (): [l:agz] $A.arr(byte, l, 9) = let
  val id = $A.alloc<byte>(9)
  val () = $A.write_text(id, 0, $A.text_lit("narration"), 9)
in id end

fn _seek {ms:nat} (ms: int ms): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val () = $AU.audio_seek(id_bytes, 9, ms)
in release_bytes(id_frozen, id_bytes) end

fn _pause_audio (): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val () = $AU.audio_pause(id_bytes, 9)
in release_bytes(id_frozen, id_bytes) end

(* Where the audio is, in ms; none when it cannot be told *)
fn _time (): $R.option([v:nat] int v) = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val ms = $AU.audio_time(id_bytes, 9)
  val () = release_bytes(id_frozen, id_bytes)
in ms end

(* Whether the audio is within END_SLACK of end_ms, or past it *)
fn _at_end (end_ms: int): bool =
  case+ _time() of
  | ~$R.some(now) => now >= end_ms - END_SLACK
  | ~$R.none() => false

(* The speed chosen, in hundredths *)
fn _speed (): [hundredths:int | 50 <= hundredths; hundredths <= 200] int hundredths = 25 * set_narration_speed_get()

fn _rate (): void = let
  val @(id_frozen, id_bytes) = $A.freeze<byte>(_audio_id())
  val () = $AU.audio_rate(id_bytes, 9, _speed())
in release_bytes(id_frozen, id_bytes) end

fn _play_audio (): $P.promise($AU.play_outcome, $P.Chained) = let
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
  val () = ui_audio_src("narration", copy, url_len)
in _source_put(Source(url, url_len, book_serial(), data_offset)) end

(* ============================================================
   The page: the clip's text marked, its page shown
   ============================================================ *)

(* Content nodes [first_node, end_node) marked as the clip read *)
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
fn _leave_show (escape: clip_escape): void =
  case+ escape of
  | ~NotEscapable() => ui_show("narration-leave", false)
  | ~EscapesTo(kind, _) => let
      val () = (case+ kind of
        | InTable() => ui_text("narration-leave", "Skip table")
        | InList() => ui_text("narration-leave", "Skip list")
        | InFigure() => ui_text("narration-leave", "Skip figure")
        | InAside() => ui_text("narration-leave", "Skip aside"))
    in ui_show("narration-leave", true) end

(* Whether a place is off the page shown, before or after it *)
fn _off_page (place: node_place): bool =
  case+ place of
  | BeforePage() => true
  | AfterPage() => true
  | OnPage() => false
  | NotInChapter() => false

(* Whether a place is the page shown or one after it *)
fn _here_or_after (place: node_place): bool =
  case+ place of
  | OnPage() => true
  | AfterPage() => true
  | BeforePage() => false
  | NotInChapter() => false

(* Clip, of the chapter's table, shown: its text marked, its page shown
   when it is not, and the button that leaves its structure *)
fn _clip_shown {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): void = let
  val () = (case+ clip_nodes(table, clip) of
    | ~$R.some(@(first_node, end_node)) => let
        val () = _mark(first_node, end_node)
      in
        if _off_page(reader_node_place(first_node)) then let
          val () = !_turning := true
          val () = reader_show_node(first_node)
        in !_turning := false end
        else ()
      end
    | ~$R.none() => $BDOM.clear_marks(MARK_KIND))
  val () = !_narration_page := _page_now()
in _leave_show(clip_escape(table, clip)) end

(* ============================================================
   Clips
   ============================================================ *)

(* Whether a clip is passed over: it has no audio, or skipping, it is
   skippable *)
fn _passed_over {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip, skipping: bool): bool =
  if ~clip_sounds(table, clip) then true
  else if skipping then clip_skippable(table, clip)
  else false

(* The first clip from at on that plays; count when none does *)
fun _playable_from {count:pos}{at:nat | at <= count} .<count - at>.
  (table: !clip_table(count), count: int count, at: int at, skipping: bool): [found:nat | at <= found; found <= count] int found =
  if at >= count then count
  else if _passed_over(table, at, skipping) then _playable_from(table, count, at + 1, skipping)
  else at

(* The last clip from at back that plays; -1 when none does *)
fun _playable_before {count:pos}{at:int | ~1 <= at; at < count} .<at + 1>.
  (table: !clip_table(count), count: int count, at: int at, skipping: bool): [found:int | ~1 <= found; found < count] int found =
  if at < 0 then ~1
  else if _passed_over(table, at, skipping) then _playable_before(table, count, at - 1, skipping)
  else at

(* Whether a clip's text is on the page shown or after it *)
fn _on_or_after_page {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): bool =
  case+ clip_nodes(table, clip) of
  | ~$R.some(@(first_node, _)) => _here_or_after(reader_node_place(first_node))
  | ~$R.none() => false

(* The first clip that plays from the first whose text is on the page
   shown or after it, from at on; the chapter's first that plays when
   none is *)
fun _from_page {count:pos}{at:nat | at <= count} .<count - at>.
  (table: !clip_table(count), count: int count, at: int at, skipping: bool): [found:nat | found <= count] int found =
  if at >= count then _playable_from(table, count, 0, skipping)
  else if _on_or_after_page(table, at) then let
    val found = _playable_from(table, count, at, skipping)
  in if found < count then found else _playable_from(table, count, 0, skipping) end
  else _from_page(table, count, at + 1, skipping)

(* Whether a clip that plays reads content node node *)
fn _reads_node {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip, node: int): bool =
  if ~clip_sounds(table, clip) then false
  else case+ clip_nodes(table, clip) of
    | ~$R.some(@(first_node, end_node)) => (if first_node > node then false else node < end_node)
    | ~$R.none() => false

(* The clip whose text has content node node, the innermost (the one
   that starts last) from at on, or best; -1 when none has *)
fun _clip_of_node {count:pos}{at:nat | at <= count}{best:int | ~1 <= best; best < count} .<count - at>.
  (table: !clip_table(count), count: int count, at: int at, node: int, best: int best): [found:int | ~1 <= found; found < count] int found =
  if at >= count then best
  else if _reads_node(table, at, node) then _clip_of_node(table, count, at + 1, node, at)
  else _clip_of_node(table, count, at + 1, node, best)

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

(* The clip leaving a clip's structure goes to, the first that plays
   after it (count for the chapter's end); none outside one, or idle *)
fn _leave_target {count:pos}{clip:nat | clip < count} (table: !clip_table(count), count: int count, clip: int clip, idle: bool, skipping: bool): $R.option([target:nat | target <= count] int target) =
  if idle then $R.none()
  else case+ clip_escape(table, clip) of
  | ~NotEscapable() => $R.none()
  | ~EscapesTo(_, escape_to) => let
      val escape_to = g1ofg0(escape_to)
    in
      if escape_to < 0 then $R.none()
      else if escape_to >= count then $R.some(count)
      else $R.some(_playable_from(table, count, escape_to, skipping))
    end

(* Whether the narration is where the reader left it: the page it left
   shown, or the clip's text on the page shown *)
fn _still_shown {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): bool =
  if _page_now() = !_narration_page then true
  else case+ clip_nodes(table, clip) of
    | ~$R.some(@(first_node, _)) => (case+ reader_node_place(first_node) of OnPage() => true | _ => false)
    | ~$R.none() => false

(* Whether clip next plays on from where clip ends in the same audio, so
   it needs no seek *)
fn _seamless {count:pos}{clip,next:nat | clip < count; next < count} (table: !clip_table(count), clip: int clip, next: int next): bool = let
  val same_audio = (case+ clip_audio(table, clip) of
    | ~ClipSilent() => false
    | ~ClipAudio(offset, _, _, _) =>
      (case+ clip_audio(table, next) of
       | ~ClipSilent() => false
       | ~ClipAudio(next_offset, _, _, _) => offset = next_offset)): bool
in
  if ~same_audio then false
  else case+ clip_end(table, clip) of
    | ~$R.none() => false
    | ~$R.some(end_ms) => let
        val gap = clip_begin(table, next) - end_ms
      in if gap > END_SLACK then false else gap >= ~END_SLACK end
end

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

(* Stops, saying in the error banner that the narration cannot be
   played *)
fn _failed (): void = let
  val () = _stop()
in notice_error("This narration cannot be played") end

(* Where clip generation ends: at a time in its audio, at the audio's
   end, or nowhere (it is not the clip playing) *)
datavtype clip_ending = EndsAt of (int) | EndsWithAudio of () | NotPlaying of ()

fn _ending_of (generation: int): clip_ending = let
  val held = _take()
  val ending = (case+ held of
    | @Narrated(table, _, _, state) => let
        val ending = (case+ state of
          | Playing(clip, playing_generation) =>
            if playing_generation <> generation then NotPlaying()
            else (case+ clip_end(table, clip) of
              | ~$R.some(end_ms) => EndsAt(end_ms)
              | ~$R.none() => EndsWithAudio())
          | _ => NotPlaying()): clip_ending
        prval () = fold@(held)
      in ending end
    | Unnarrated() => NotPlaying()): clip_ending
  val () = _put(held)
in ending end

(* How long a clip's timer waits: to end_ms, by the speed; at most a
   second, so a speed changed meanwhile is caught *)
fn _delay_to (end_ms: int): [delay:nat | delay <= 1000] int delay =
  case+ _time() of
  | ~$R.none() => 250
  | ~$R.some(now) => let
      val left = end_ms - now
      val delay = (if left <= 0 then 0 else if left > 10000 then 1000 else left * 100 / _speed()): int
      val delay: Int = g1ofg0(delay)
    in if delay > 1000 then 1000 else if delay < 0 then 0 else delay end

(* Where a clip starts playing: its begin; a place in its audio (ms); or
   on from where the audio is, the clip after the one before in it *)
datavtype start = FromBegin of () | FromMs of (int) | FromWhereItIs of ()

(* A start nobody takes *)
fn _start_free (from: start): void =
  case+ from of ~FromBegin() => () | ~FromMs(_) => () | ~FromWhereItIs() => ()

(* The most chapters the narration passes over, going on, that have
   nothing it plays *)
#define CHAPTERS_PASSED 10000

(* The chapter the reader is in (from 0) *)
fn _chapter_now (): int = case+ reading_get() of @(_, _, chapter, _) => (if chapter > 0 then chapter - 1 else 0)

(* The steps of playing on. Each spends one of the chain's rounds *)

(* A timer at clip generation's end; when it fires, _tick *)
fun _arm {rounds:nat} .<rounds>. (generation: int, rounds: int rounds): void =
  if rounds <= 0 then ()
  else (case+ _ending_of(generation) of
    | ~NotPlaying() => ()
    (* to the audio's end: the ended event moves on *)
    | ~EndsWithAudio() => ()
    | ~EndsAt(end_ms) =>
      (* a timer's status carries nothing *)
      $P.finish<Int>($P.vow($TM.timer_set(_delay_to(end_ms))), llam(_) => _tick(generation, rounds - 1)))

(* A clip's timer: the clip's end, when the audio is within END_SLACK of
   it; else the timer again *)
and _tick {rounds:nat} .<rounds>. (generation: int, rounds: int rounds): void =
  if rounds <= 0 then ()
  else if generation <> !_generation then ()
  else (case+ _ending_of(generation) of
    | ~NotPlaying() => ()
    | ~EndsWithAudio() => ()
    | ~EndsAt(end_ms) =>
      if _at_end(end_ms) then _advance(generation, rounds - 1) else _arm(generation, rounds - 1))

(* The audio played (generation's clip): first sought to from_ms when
   seek *)
and _play_at {rounds:nat} .<rounds>. (generation: int, from_ms: int, seek: bool, rounds: int rounds): void =
  if rounds <= 0 then ()
  else if generation <> !_generation then ()
  else let
    val from_ms = g1ofg0(from_ms)
    val () = (if seek then (if from_ms >= 0 then _seek(from_ms) else ()) else ())
    (* a new source starts at the element's default speed *)
    val () = _rate()
    val () = _pressed(true)
    val () = $P.finish<$AU.play_outcome>(_play_audio(), llam(outcome) =>
      case+ outcome of
      | $AU.Playing() => ()
      (* refused, or not playable: the clip it was for, if it still
         plays, cannot be *)
      | $AU.PlayRefused() => if generation = !_generation then _failed() else ()
      | $AU.Unplayable() => if generation = !_generation then _failed() else ())
  in _arm(generation, rounds - 1) end

(* Plays from where start says: fresh says whether the source was just
   set (a new source cannot play on from where it is) *)
and _start_play {rounds:nat} .<rounds>. (generation: int, from: start, begin_ms: int, fresh: bool, rounds: int rounds): void =
  if rounds <= 0 then _start_free(from)
  else (case+ from of
    | ~FromWhereItIs() =>
      if fresh then _play_at(generation, begin_ms, true, rounds - 1)
      else _play_at(generation, ~1, false, rounds - 1)
    | ~FromMs(at) => _play_at(generation, at, true, rounds - 1)
    | ~FromBegin() => _play_at(generation, begin_ms, true, rounds - 1))

(* The clip's audio as the audio's source, when it is not already; then
   played from where start says *)
and _source_then {rounds:nat} .<rounds>. (generation: int, audio: clip_audio, from: start, begin_ms: int, rounds: int rounds): void =
  if rounds <= 0 then let
    val () = (case+ audio of ~ClipAudio(_, _, _, _) => () | ~ClipSilent() => ())
  in _start_free(from) end
  else (case+ audio of
    | ~ClipSilent() => let
        val () = _start_free(from)
      in _failed() end
    | ~ClipAudio(data_offset, data_size, method, kind) =>
      if _source_is(data_offset) then _start_play(generation, from, begin_ms, false, rounds - 1)
      else (case+ method of
        | $Z.Stored() =>
          (case+ book_blob_url(book_serial(), data_offset, data_size, audio_mime(kind)) of
           | ~BlobUrl(url, url_len) => let
               val () = _source_set(url, url_len, data_offset)
             in _start_play(generation, from, begin_ms, true, rounds - 1) end
           | ~NoBlobUrl() => let
               val () = _start_free(from)
             in _failed() end)
        | $Z.Deflated() => _inflated_then(generation, data_offset, data_size, kind, from, begin_ms, rounds - 1)))

(* A deflated audio entry, inflated into a piece, made a blob URL (the
   piece then freed), as the audio's source; then played *)
and _inflated_then {rounds:nat} .<rounds>. (generation: int, data_offset: int, data_size: int, kind: audio_type, from: start, begin_ms: int, rounds: int rounds): void =
  if rounds <= 0 then _start_free(from)
  else (case+ book_meta_get() of
    | ~$R.none() => let
        val () = _start_free(from)
      in _failed() end
    | ~$R.some(@(file_size, _, _, _, _, _)) => let
        val offset = g1ofg0(data_offset)
        val size = g1ofg0(data_size)
      in
        if offset < 0 then let val () = _start_free(from) in _failed() end
        else if size <= 0 then let val () = _start_free(from) in _failed() end
        else if size > 268435456 then let val () = _start_free(from) in _failed() end
        else if offset > file_size - size then let val () = _start_free(from) in _failed() end
        else (case+ piece_new(size) of
          | ~NoPiece() => let
              val () = _start_free(from)
            in _failed() end
          | ~Piece(compressed_owner, compressed) => let
              val _ = book_read(book_serial(), file_size, offset, compressed, size)
              val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
              val decompressing = decompress(compressed_bytes, size, $BD.DeflateRaw())
              val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
              val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
            in
              $P.finish<decompressed>(decompressing, llam(inflated) =>
                case+ take_decompressed(inflated) of
                | ~NoContentBytes() => let
                    val () = _start_free(from)
                  in if generation = !_generation then _failed() else () end
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
                  in
                    case+ blob_url_take(made) of
                    | ~BlobUrl(url, url_len) =>
                      if generation = !_generation then let
                        val () = _source_set(url, url_len, data_offset)
                      in _start_play(generation, from, begin_ms, true, rounds - 1) end
                      else let
                        val () = $A.free<byte>(url)
                      in _start_free(from) end
                    | ~NoBlobUrl() => let
                        val () = _start_free(from)
                      in if generation = !_generation then _failed() else () end
                  end)
            end)
      end)

(* Plays the clip the narration is at, when it is clip generation's: its
   text marked and its page shown, its audio loaded, then played from
   where start says *)
and _begin {rounds:nat} .<rounds>. (generation: int, from: start, rounds: int rounds): void =
  if rounds <= 0 then _start_free(from)
  else let
    val held = _take()
  in
    case+ held of
    | @Narrated(table, _, _, state) =>
      (case+ state of
       | Playing(clip, playing_generation) =>
         if playing_generation <> generation then let
           prval () = fold@(held)
           val () = _put(held)
         in _start_free(from) end
         else let
           val audio = clip_audio(table, clip)
           val begin_ms = clip_begin(table, clip)
           val () = _clip_shown(table, clip)
           prval () = fold@(held)
           val () = _put(held)
         in _source_then(generation, audio, from, begin_ms, rounds - 1) end
       | _ => let
           prval () = fold@(held)
           val () = _put(held)
         in _start_free(from) end)
    | Unnarrated() => let
        val () = _put(held)
      in _start_free(from) end
  end

(* Plays from the first clip on the page shown (from the chapter's first
   when from_start): false when the chapter has none that plays *)
and _play_from {rounds:nat} .<rounds>. (from_start: bool, rounds: int rounds): bool =
  if rounds <= 0 then false
  else let
    val held = _take()
  in
    case+ held of
    | @Narrated(table, count, _, state) => let
        val clip = _start_clip(table, count, from_start, _skipping())
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
          val () = _begin(generation, FromBegin(), rounds - 1)
        in true end
      end
    | Unnarrated() => let
        val () = _put(held)
      in false end
  end

(* Goes on into the next chapter after chapter that has an overlay, and
   on past those with nothing it plays (passes more of them); stops when
   none is left *)
and _continue_after {rounds:nat} .<rounds>. (chapter: int, passes: int, rounds: int rounds): void =
  if rounds <= 0 then ()
  else (case+ book_narrated_after(book_serial(), chapter) of
    | ~$R.none() => _stop()
    | ~$R.some(next) => let
        val generation = _next_generation()
        val () = !_continuing := true
        val () = _pause_audio()
      in
        $P.finish<load_outcome>(reader_goto(next, 0, ~1), llam(result) => let
          val () = !_continuing := false
        in
          if generation <> !_generation then ()
          else if ~load_shown(result) then _stop()
          else let
            val _ = _sync()
          in
            if _play_from(true, rounds - 1) then ()
            else if passes > 0 then _continue_after(next, passes - 1, rounds - 1)
            else _stop()
          end
        end)
      end)

(* A clip has ended: the next that plays, or the next narrated chapter *)
and _advance {rounds:nat} .<rounds>. (generation: int, rounds: int rounds): void =
  if rounds <= 0 then ()
  else let
    val held = _take()
  in
    case+ held of
    | @Narrated(table, count, chapter, state) => let
        val chapter_number = chapter
      in
        case+ state of
        | Playing(clip, playing_generation) =>
          if playing_generation <> generation then let
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
            in _continue_after(chapter_number, CHAPTERS_PASSED, rounds - 1) end
            else let
              (* the next clip right after this one in the same audio
                 plays on without a seek *)
              val seamless = _seamless(table, clip, next)
              val next_generation = _next_generation()
              val () = _state_free(state)
              val () = state := Playing(next, next_generation)
              prval () = fold@(held)
              val () = _put(held)
            in _begin(next_generation, (if seamless then FromWhereItIs() else FromBegin()): start, rounds - 1) end
          end
        | _ => let
            prval () = fold@(held)
          in _put(held) end
      end
    | Unnarrated() => _put(held)
  end

(* Plays from the page shown; a chapter with nothing to play goes on to
   the next *)
fn _play_here (): void =
  if _play_from(false, NARRATION_ROUNDS) then ()
  else if reader_narrated() then _continue_after(_chapter_now(), CHAPTERS_PASSED, NARRATION_ROUNDS)
  else ()

(* ============================================================
   What the reader does
   ============================================================ *)

(* Read aloud: plays from the page shown, pauses, or goes on *)
fn _toggle (): void = let
  val _ = _sync()
  val held = _take()
in
  case+ held of
  | @Narrated(table, _, _, state) =>
    (case+ state of
     | Playing(clip, _) => let
         val at = (case+ _time() of ~$R.some(now) => ResumeAt(now) | ~$R.none() => ResumeFromBegin()): resume
         val () = !_generation := !_generation + 1
         val () = _state_free(state)
         val () = state := Paused(clip, at)
         prval () = fold@(held)
         val () = _put(held)
         val () = _pause_audio()
       in _pressed(false) end
     | Paused(clip, _) => let
         (* on from where it paused, when that is in the clip *)
         val begin_ms = clip_begin(table, clip)
         val from = (case+ state of
           | Paused(_, ResumeAt(at)) =>
             if at < begin_ms then FromBegin()
             else (case+ clip_end(table, clip) of
               | ~$R.none() => FromMs(at)
               | ~$R.some(end_ms) => if at < end_ms then FromMs(at) else FromBegin())
           | _ => FromBegin()): start
         val generation = _next_generation()
         val () = _state_free(state)
         val () = state := Playing(clip, generation)
         prval () = fold@(held)
         val () = _put(held)
       in _begin(generation, from, NARRATION_ROUNDS) end
     | Idle() => let
         prval () = fold@(held)
         val () = _put(held)
       in _play_here() end)
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
      val mode = _mode_of(state)
      val clip = _clip_of(state)
      val target = _step_target(table, count, _is_idle(mode), clip, forward, _skipping())
    in
      if target >= count then
        (if _is_playing(mode) then let
           val () = _state_free(state)
           val () = state := Idle()
           prval () = fold@(held)
           val () = _put(held)
         in _continue_after(chapter_number, CHAPTERS_PASSED, NARRATION_ROUNDS) end
         else let
           prval () = fold@(held)
         in _put(held) end)
      else if _is_playing(mode) then let
        val generation = _next_generation()
        val () = _state_free(state)
        val () = state := Playing(target, generation)
        prval () = fold@(held)
        val () = _put(held)
      in _begin(generation, FromBegin(), NARRATION_ROUNDS) end
      else let
        val () = _clip_shown(table, target)
        val () = _state_free(state)
        val () = state := Paused(target, ResumeFromBegin())
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
      val mode = _mode_of(state)
      val clip = _clip_of(state)
      val leaving = _leave_target(table, count, clip, _is_idle(mode), _skipping())
    in
      case+ leaving of
      | ~$R.none() => let
          prval () = fold@(held)
        in _put(held) end
      | ~$R.some(target) =>
        if target >= count then let
          val () = _state_free(state)
          val () = state := Idle()
          prval () = fold@(held)
          val () = _put(held)
        in if _is_playing(mode) then _continue_after(chapter_number, CHAPTERS_PASSED, NARRATION_ROUNDS) else _stop() end
        else if _is_playing(mode) then let
          val generation = _next_generation()
          val () = _state_free(state)
          val () = state := Playing(target, generation)
          prval () = fold@(held)
          val () = _put(held)
        in _begin(generation, FromBegin(), NARRATION_ROUNDS) end
        else let
          val () = _clip_shown(table, target)
          val () = _state_free(state)
          val () = state := Paused(target, ResumeFromBegin())
          prval () = fold@(held)
        in _put(held) end
    end
  | Unnarrated() => _put(held)
end

(* A page shown that the narration did not turn to (a turn, a jump, a new
   chapter): playing, it plays on from there; paused, it is paused there *)
fn _moved (): void =
  if !_continuing then ()
  else let
    val renewal = _sync()
    val held = _take()
  in
    case+ held of
    | @Narrated(table, count, _, state) => let
        val mode_now = _mode_of(state)
        val clip = _clip_of(state)
        (* new clips: what the narration was doing goes on in them *)
        val @(renewed, mode) = (case+ renewal of
          | Unrenewed() => @(false, mode_now)
          | RenewedNone() => @(true, ModeIdle())
          | RenewedIdle() => @(true, ModeIdle())
          | RenewedPlaying() => @(true, ModePlaying())
          | RenewedPaused() => @(true, ModePaused())): @(bool, mode)
        val kept = (if renewed then false
          else if _is_idle(mode_now) then true
          else _still_shown(table, clip)): bool
      in
        if kept then let
          prval () = fold@(held)
        in _put(held) end
        else if _is_playing(mode) then let
          prval () = fold@(held)
          val () = _put(held)
        in _play_here() end
        else if _is_paused(mode) then let
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
            val () = state := Paused(target, ResumeFromBegin())
            prval () = fold@(held)
          in _put(held) end
        end
        else let
          prval () = fold@(held)
        in _put(held) end
      end
    | Unnarrated() => let
        val () = _put(held)
      in case+ renewal of RenewedPlaying() => _stop() | _ => () end
  end

(* The audio's events *)

(* timeupdate: the clip's end, when the timer has not caught it *)
fn _time_update (): void = let
  val generation = !_generation
in
  case+ _ending_of(generation) of
  | ~EndsAt(end_ms) => if _at_end(end_ms) then _advance(generation, NARRATION_ROUNDS) else ()
  | ~EndsWithAudio() => ()
  | ~NotPlaying() => ()
end

(* ended: the audio file is over, before its clip or at its end *)
fn _ended (): void = let
  val generation = !_generation
  val held = _take()
in
  case+ held of
  | @Narrated(_, _, _, state) =>
    (case+ state of
     | Playing(_, _) => let
         prval () = fold@(held)
         val () = _put(held)
       in _advance(generation, NARRATION_ROUNDS) end
     (* the audio's end pauses it first *)
     | Paused(clip, _) =>
       if !_paused_by_itself = generation then let
         val () = _state_free(state)
         val () = state := Playing(clip, generation)
         prval () = fold@(held)
         val () = _put(held)
         val () = _pressed(true)
       in _advance(generation, NARRATION_ROUNDS) end
       else let
         prval () = fold@(held)
       in _put(held) end
     | Idle() => let
         prval () = fold@(held)
       in _put(held) end)
  | Unnarrated() => _put(held)
end

(* pause: a pause the narration did not ask for (a headset, a call, the
   audio's end) leaves it paused *)
fn _paused (): void = let
  val held = _take()
in
  case+ held of
  | @Narrated(_, _, _, state) =>
    (case+ state of
     | Playing(clip, generation) => let
         val () = !_paused_by_itself := generation
         val at = (case+ _time() of ~$R.some(now) => ResumeAt(now) | ~$R.none() => ResumeFromBegin()): resume
         val () = _state_free(state)
         val () = state := Paused(clip, at)
         prval () = fold@(held)
         val () = _put(held)
       in _pressed(false) end
     | _ => let
         prval () = fold@(held)
       in _put(held) end)
  | Unnarrated() => _put(held)
end

(* error: the audio cannot be played *)
fn _media_error (): void =
  case+ _mode() of
  | ~$R.some(ModePlaying()) => _failed()
  | ~$R.some(ModePaused()) => _failed()
  | ~$R.some(ModeIdle()) => ()
  | ~$R.none() => ()

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
    | @Narrated(table, count, _, state) =>
      (case+ state of
       | Playing(clip, _) => let
           val target = _clip_of_node(table, count, 0, node, ~1)
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
           in _begin(generation, FromBegin(), NARRATION_ROUNDS) end
         end
       | _ => let
           prval () = fold@(held)
         in _put(held) end)
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
in let val () = ui_show("narration-leave", false) in _source_put(NoSource()) end end

(* Whether a click's target, event_bytes[10, n), is id *)
fun _id_from {l:agz}{n:nat}{id_len:nat}{i:nat | i <= id_len} .<id_len - i>.
  (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len, id_len: int id_len, i: int i): bool =
  if i >= id_len then 10 + id_len = n
  else if 10 + i >= n then false
  else if byte2int0($A.get<byte>(event_bytes, 10 + i)) <> char2int0(string_get_at(id, i)) then false
  else _id_from(event_bytes, n, id, id_len, i + 1)

fn _id_is {l:agz}{n:nat}{id_len:nat} (event_bytes: !$A.arr(byte, l, n), n: int n, id: string id_len): bool =
  _id_from(event_bytes, n, id, g1u2i(string1_length(id)), 0)

(* How many pages shown the narration watches for in a session: one
   each turn, jump or chapter. A metric needs the bound *)
#define PAGES_WATCHED 100000000

(* Each page the reader shows, that the narration did not turn to
   itself, moves it there, once the page's own work is done *)
fun _watch_pages {pages:nat} .<pages>. (pages: int pages): void =
  if pages <= 0 then ()
  else $P.finish<int>(reader_page_shown(), llam(_) => let
      val () = (if !_turning then ()
        else if !_continuing then ()
        (* a timer's status carries nothing *)
        else $P.finish<Int>($P.vow($TM.timer_set(0)), llam(_) => _moved()))
    in _watch_pages(pages - 1) end)

(* The narration's listeners: its controls and the audio's events; and
   it watches the reader's pages shown *)
#pub fn narration_listen {count:nat} (listeners: regs(count)): regs(count + 5)

implement narration_listen (listeners) = let
  val () = _watch_pages(PAGES_WATCHED)
  val listeners = RCons(listeners, OnEl("narration-controls"), "click", llam(h) =>
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
  val listeners = RCons(listeners, OnEl("narration"), "timeupdate", llam(_) => let val () = _time_update() in 0 end)
  val listeners = RCons(listeners, OnEl("narration"), "ended", llam(_) => let val () = _ended() in 0 end)
  val listeners = RCons(listeners, OnEl("narration"), "pause", llam(_) => let val () = _paused() in 0 end)
in RCons(listeners, OnEl("narration"), "error", llam(_) => let val () = _media_error() in 0 end) end

end (* #target wasm *)
