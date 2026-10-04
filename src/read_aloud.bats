(* read_aloud -- the book read aloud, a sentence at a time, the page
   turned with it *)

(* Read aloud (the reader's bottom bar) reads the chapter shown from the
   first sentence on the page, and Read from here (the selection's
   toolbar) from the sentence the selection starts in. A chapter's
   sentences are its blocks' text (paragraphs, headings, list items and
   the like: reader.bats's script), a ruby's readings left out, cut by
   bridge's segment_sentences (Intl.Segmenter) in the book's language.
   Each is said by bridge's speech_speak in the book's language, in the
   voice chosen for that language and at the speed chosen (both kept
   with the settings), and marked on the page while it is said (a mark
   of its own, MARK_SPOKEN). When the next sentence is past the page
   shown, the page is turned (reader_turn_on, as the next page button
   turns it), into the next chapter too; reading stops where nothing
   turns. Read aloud again pauses it, and once more goes on from the
   sentence it was saying, when that is still on the page shown (else
   from the page's first). The screen is kept awake meanwhile, and Read
   aloud is pressed (aria-pressed) while it reads.

   A pause cancels what is being said and says the sentence again when
   it goes on: speechSynthesis.pause() stops for good on Android's
   Chrome and after some 15 seconds on desktop Chrome, which cancel and
   speak again do not. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S

staload "ui.sats"
staload "book.sats"
staload "mem.sats"
staload "reader.sats"
staload "settings.sats"
staload "library.sats"
staload SP = "wasm.bats-packages.dev/bridge/src/speech.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload WN = "wasm.bats-packages.dev/bridge/src/window.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* The sentence said is shown as ::highlight(bats-mark-5) (style.bats) *)
#define MARK_SPOKEN 5

(* How many pages are turned for one sentence that is past the page
   shown before it is said all the same (a layout that never shows it) *)
#define TURNS_MAX 3

(* The pause after a page is turned, in milliseconds, before reading
   goes on: the page is seen turned before its first sentence is said *)
#define TURN_PAUSE 300

(* How many steps (a page turned, a chapter's script made) reading may
   take between two sentences said: past it, it stops. Each sentence
   said starts again with as many (a step's count is what proves the
   steps end) *)
#define STEPS_MAX 100000

(* ============================================================
   The state
   ============================================================ *)

(* What a page turn is for: a sentence past the page shown (after so
   many turns for it), or the chapter's end *)
implement $P.dispose<turned>(_) = ()
implement $P.dispose<script>(script) = script_free(script)

datavtype turn_for = ForSentence of Nat | ForChapterEnd of ()

fn _turn_for_free (purpose: turn_for): void =
  case+ purpose of
  | ~ForSentence(_) => ()
  | ~ForChapterEnd() => ()

(* Reading aloud: silent; a chapter's script being made; a sentence of
   the script being said (its utterance's number); a page turn awaited
   before the sentence index is said (or, at the chapter's end, before
   the next chapter is); or paused at sentence index *)
datavtype aloud =
  | Silent of ()
  | Loading of ()
  | Saying of (script, Nat, Int)
  | Turning of (script, Nat, turn_for)
  | Paused of (script, Nat)

val _aloud = ref<aloud>(Silent())

(* The run's number: what was started for one run (a script made, a
   page turned) is dropped when another has started since *)
val _run = ref<int>(0)

fn _aloud_free (state: aloud): void =
  case+ state of
  | ~Silent() => ()
  | ~Loading() => ()
  | ~Saying(script, _, _) => script_free(script)
  | ~Turning(script, _, purpose) => let
      val () = _turn_for_free(purpose)
    in script_free(script) end
  | ~Paused(script, _) => script_free(script)

fn _take (): aloud = let
  var cell: aloud = Silent()
  val () = ref_exch_elt<aloud>(_aloud, cell)
in cell end

fn _put (state: aloud): void = let
  var cell: aloud = state
  val () = ref_exch_elt<aloud>(_aloud, cell)
in _aloud_free(cell) end

(* A new run: what the last one started is dropped *)
fn _run_next (): int = let
  val () = !_run := !_run + 1
in !_run end

fn _pressed (on: bool): void =
  if on then ui_attr("read-aloud", APressed, "true") else ui_attr("read-aloud", APressed, "false")

fn _unmark (): void = $BDOM.clear_marks(MARK_SPOKEN)

(* Stops reading: nothing more is said or marked *)
fn _stop (): void = let
  val _ = _run_next()
  val () = _put(Silent())
  val () = _unmark()
  val () = _pressed(false)
in $SP.speech_cancel() end

(* ============================================================
   Where a sentence is
   ============================================================ *)

(* Where a sentence starts, against the page shown: before it, on it,
   or after it (paged, across, as the book reads; scrolled, down) *)
datatype placement = Before | OnPage | After

(* Where offset of content node node is against the page shown. Its
   first character is measured (the caret after it), so a sentence
   that starts a line is not taken for the line before's end *)
fn _placement (node: Int, offset: Int): placement =
  if node < 0 then OnPage()
  else let
    val () = ui_measure("page")
    val page_x = $DR.get_measure_x()
    val page_y = $DR.get_measure_y()
    val page_width = $DR.get_measure_w()
    val page_height = $DR.get_measure_h()
    val @(id, id_len) = nid_pad3("c", node)
    val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
    val measured = $DR.measure_text_offset(id_bytes, id_len, offset + 1)
    val () = release_bytes(id_frozen, id_bytes)
    val x = $DR.get_measure_x()
    val y = $DR.get_measure_y()
  in
    case+ measured of
    | $DR.NoElement() => OnPage()
    | $DR.Measured() =>
    if page_width <= 0 then OnPage()
    else if reader_scrolls() then
      (if y >= page_y + page_height then After() else if y < page_y then Before() else OnPage())
    (* right to left, the pages go on to the left *)
    else if reader_rtl() then
      (if x < page_x then After() else if x >= page_x + page_width then Before() else OnPage())
    else if x >= page_x + page_width then After()
    else if x < page_x then Before()
    else OnPage()
  end

fn _sentence_placement (script: !script, index: int): placement = let
  val @(node, offset, _, _) = script_place(script, index)
in _placement(node, offset) end

(* The first sentence in [low, high) that is not before the page shown;
   high when there is none. The sentences are in the page's order, so
   halving finds it *)
fun _first_shown {low,high:nat | low <= high} .<high - low>. (script: !script, low: int low, high: int high): [first:nat | first <= high] int first =
  if low >= high then high
  else let
    val middle = low + (high - low) / 2
  in
    case+ _sentence_placement(script, middle) of
    | Before() => _first_shown(script, middle + 1, high)
    | OnPage() => _first_shown(script, low, middle)
    | After() => _first_shown(script, low, middle)
  end

(* The last sentence starting at or before offset of content node node
   (where a selection starts); the first when none does *)
fun _sentence_at {size:int}{count:nat} .<count>.
  (sentences: !sentences_of(size, count), node: Int, offset: Int, index: Nat, found: Nat): Nat =
  case+ sentences of
  | SentencesNone() => found
  | SentenceOf(_, _, start_node, start_offset, _, _, rest) =>
    if start_node < node then _sentence_at(rest, node, offset, index + 1, index)
    else if start_node > node then found
    else if start_offset <= offset then _sentence_at(rest, node, offset, index + 1, index)
    else found

fn _script_index_at (script: !script, node: Int, offset: Int): Nat =
  case+ script of
  | NoScript() => 0
  | Script(_, _, sentences, _, _) => _sentence_at(sentences, node, offset, 0, 0)

(* The chapter shown (from 0), or -1 before one is *)
fn _chapter_shown (): Int =
  case+ reading_get() of
  | @(_, _, chapter, _) => chapter - 1

(* ============================================================
   Saying a sentence
   ============================================================ *)

(* Marks sentence index on the page *)
fn _mark (script: !script, index: int): void = let
  val @(start_node, start_offset, end_node, end_offset) = script_place(script, index)
  val () = _unmark()
in
  if start_node < 0 then ()
  else if end_node < 0 then ()
  else let
    val @(start_id, start_id_len) = nid_pad3("c", start_node)
    val @(end_id, end_id_len) = nid_pad3("c", end_node)
    val @(start_frozen, start_bytes) = $A.freeze<byte>(start_id)
    val @(end_frozen, end_bytes) = $A.freeze<byte>(end_id)
    val () = $BDOM.mark_range(MARK_SPOKEN, start_bytes, start_id_len, start_offset, end_bytes, end_id_len, end_offset)
    val () = release_bytes(end_frozen, end_bytes)
  in release_bytes(start_frozen, start_bytes) end
end

(* The voice chosen for the book's language: its name in a new array
   and its length, 0 for the automatic one *)
fn _voice_name (): [l:agz][n:pos][name_len:nat | name_len <= n] @($A.arr(byte, l, n), int name_len) = let
  val @(code, code_len) = reader_lang_code()
  val kept = set_voice_get(code, code_len)
  val () = $A.free<byte>(code)
in
  case+ kept of
  | ~KeptVoice(name, name_len) => @(name, name_len)
  | ~AutomaticVoice() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
end

(* Says text[0, text_len) in the book's language, in the voice and at
   the speed chosen *)
fn _say {l:agz}{n:pos} (text: !$A.borrow(byte, l, n), text_len: int n): $SP.speech_start = let
  val @(lang, lang_len) = reader_lang_tag()
  val @(lang_frozen, lang_bytes) = $A.freeze<byte>(lang)
  val @(voice, voice_len) = _voice_name()
  val @(voice_frozen, voice_bytes) = $A.freeze<byte>(voice)
  val started = $SP.speech_speak(text, text_len, lang_bytes, lang_len, voice_bytes, voice_len,
    speech_rate_hundredths(set_speech_rate_get()))
  val () = release_bytes(voice_frozen, voice_bytes)
  val () = release_bytes(lang_frozen, lang_bytes)
in started end

(* Sentence index of script said now, and marked *)
fn _say_now (script: script, index: Nat): void = let
  val () = _mark(script, index)
in
  case+ script_text(script, index) of
  | ~NoSentenceText() => let
      val () = script_free(script)
    in _stop() end
  | ~SentenceText(text_owner, text, text_len) => let
      val @(text_frozen, text_bytes) = $A.freeze<byte>(text)
      val started = _say(text_bytes, text_len)
      val () = $A.drop<byte>(text_frozen, text_bytes)
      val () = piece_free(text_owner, $A.thaw<byte>(text_frozen))
    in
      case+ started of
      | ~$SP.Speaking(utterance) => _put(Saying(script, index, utterance))
      | ~$SP.SpeechUnavailable() => let
          val () = script_free(script)
        in _stop() end
    end
end

(* ============================================================
   Going on: the next sentence, the page turned, the next chapter
   ============================================================ *)

(* A script loaded for a run: still wanted (the run is the current one,
   and it is loading), or dropped *)
datavtype loaded = Loaded of script | Dropped of ()
implement $P.dispose<loaded>(result) =
  case+ result of
  | ~Loaded(script) => script_free(script)
  | ~Dropped() => ()

(* The script of the chapter shown made: the promise resolves with it
   when this run still waits for it, else it is dropped *)
fn _load (run: int): $P.promise(loaded, $P.Chained) = let
  val chapter = _chapter_shown()
  val () = _put(Loading())
in
  if chapter < 0 then let
    val () = _stop()
  in $P.ret<loaded>(Dropped()) end
  else $P.and_then<script><loaded>(reader_script_load(chapter), llam(script) =>
    if run <> !_run then let
      val () = script_free(script)
    in $P.ret<loaded>(Dropped()) end
    else (case+ _take() of
      | ~Loading() => $P.ret<loaded>(Loaded(script))
      | other => let
          val () = _put(other)
          val () = script_free(script)
        in $P.ret<loaded>(Dropped()) end))
end

(* Sentence index of script said, when it is on the page shown; the
   page turned on first when it is past it (at most TURNS_MAX times,
   tries so far); the next chapter when the script has no more *)
fun _go {steps:nat} .<steps>. (steps: int steps, run: int, script: script, index: Nat, tries: Nat): void =
  if steps <= 0 then let
    val () = script_free(script)
  in _stop() end
  (* a chapter with nothing to read (or that could not be read): on to
     the next *)
  else if script_count(script) <= 0 then _turn(steps - 1, run, script, index, ForChapterEnd())
  else if script_chapter(script) <> _chapter_shown() then let
    (* another chapter is shown (gone to meanwhile): read from its page *)
    val () = script_free(script)
  in _from_page(steps - 1, run) end
  else if index >= script_count(script) then _turn(steps - 1, run, script, index, ForChapterEnd())
  else if tries >= TURNS_MAX then _say_now(script, index)
  else case+ _sentence_placement(script, index) of
  | After() => _turn(steps - 1, run, script, index, ForSentence(tries))
  | Before() => _say_now(script, index)
  | OnPage() => _say_now(script, index)

(* The page turned on, then (after TURN_PAUSE): the sentence it was for
   said (or another turn), or, at the chapter's end, the next chapter
   read from its start. Reading stops where nothing turns *)
and _turn {steps:nat} .<steps>. (steps: int steps, run: int, script: script, index: Nat, purpose: turn_for): void = let
  val () = _put(Turning(script, index, purpose))
  val turning = $P.and_then<turned><turned>(reader_turn_on(), llam(result) =>
    $P.and_then<Int><turned>($P.vow($TM.timer_set(TURN_PAUSE)), llam(_) => $P.ret<turned>(result)))
in
  $P.finish<turned>(turning, llam(result) =>
    if run <> !_run then ()
    else case+ _take() of
    | ~Turning(script, index, purpose) =>
      if steps <= 0 then let
        val () = _turn_for_free(purpose)
        val () = script_free(script)
      in _stop() end
      else (case+ result of
       | NotTurned() => let
           val () = _turn_for_free(purpose)
           val () = script_free(script)
         in _stop() end
       | TurnedChapter() => let
           val () = _turn_for_free(purpose)
           val () = script_free(script)
         in _from_start(steps - 1, run) end
       | TurnedPage() =>
         (case+ purpose of
          | ~ForSentence(tries) => _go(steps - 1, run, script, index, tries + 1)
          | ~ForChapterEnd() => _turn(steps - 1, run, script, index, ForChapterEnd())))
    | other => _put(other))
end

(* The chapter shown read from its first sentence *)
and _from_start {steps:nat} .<steps>. (steps: int steps, run: int): void =
  $P.finish<loaded>(_load(run), llam(result) =>
    case+ result of
    | ~Dropped() => ()
    | ~Loaded(script) =>
      if steps <= 0 then let
        val () = script_free(script)
      in _stop() end
      else _go(steps - 1, run, script, 0, 0))

(* The chapter shown read from the first sentence on the page shown *)
and _from_page {steps:nat} .<steps>. (steps: int steps, run: int): void =
  $P.finish<loaded>(_load(run), llam(result) =>
    case+ result of
    | ~Dropped() => ()
    | ~Loaded(script) =>
      if steps <= 0 then let
        val () = script_free(script)
      in _stop() end
      else let
        val first = _first_shown(script, 0, script_count(script))
      in _go(steps - 1, run, script, first, 0) end)

(* The chapter shown read from the sentence at offset of content node
   node *)
fn _from_point (run: int, node: Int, offset: Int): void =
  $P.finish<loaded>(_load(run), llam(result) =>
    case+ result of
    | ~Dropped() => ()
    | ~Loaded(script) => let
        val first = _script_index_at(script, node, offset)
      in _go(STEPS_MAX, run, script, first, 0) end)

(* A run starts: Read aloud pressed, and the screen kept awake *)
fn _begin (): int = let
  val run = _run_next()
  val () = _pressed(true)
  val () = $WN.keep_awake(true)
in run end

(* The speed or the voice changed while a sentence is said: it is said
   again, as they are now *)
fn _again (): void =
  case+ _take() of
  | ~Saying(script, index, _) => let
      val run = _run_next()
      val () = _put(Paused(script, index))
      val () = $SP.speech_cancel()
    in
      case+ _take() of
      | ~Paused(script, index) => _go(STEPS_MAX, run, script, index, TURNS_MAX)
      | other => _put(other)
    end
  | other => _put(other)

(* ============================================================
   The speed and the voice
   ============================================================ *)

(* A speed's option: its value (the speed as a number, as the page's
   select had it) and what it shows *)
fn _rate_option (rate: speech_rate): @([value_len:pos | value_len < 8] string value_len, [label_len:pos | label_len < 12] string label_len) =
  case+ rate of
  | RateThreeQuarters() => @("0.75", "0.75\xC3\x97")
  | RateNormal() => @("1", "1\xC3\x97")
  | RateOneAndAQuarter() => @("1.25", "1.25\xC3\x97")
  | RateOneAndAHalf() => @("1.5", "1.5\xC3\x97")
  | RateOneAndThreeQuarters() => @("1.75", "1.75\xC3\x97")
  | RateDouble() => @("2", "2\xC3\x97")

fn _same_rate (one: speech_rate, other: speech_rate): bool =
  speech_rate_hundredths(one) = speech_rate_hundredths(other)

(* A string's bytes in a new array *)
fn _bytes_of {text_len:pos | text_len < 256} (text: string text_len): [l:agz] @($A.arr(byte, l, text_len), int text_len) = let
  val text_len = g1u2i(string1_length(text))
  val bytes = $A.alloc<byte>(text_len)
  fun put {l:agz}{i:nat | i <= text_len} .<text_len - i>. (bytes: !$A.arr(byte, l, text_len), i: int i): void =
    if i >= text_len then ()
    else let
      val () = $A.set<byte>(bytes, i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
    in put(bytes, i + 1) end
  val () = put(bytes, 0)
in @(bytes, text_len) end

(* A speed's option's id in place: the sheet's, or the Reading
   screen's *)
fn _rate_option_id {number:nat} (place: reading_place, number: int number)
  : [id_loc:agz][id_len:pos | id_len <= 32] @($A.arr(byte, id_loc, id_len), int id_len) =
  case+ place of
  | InSheet() => nid_make("rate-option", number)
  | InSettings() => nid_make("reading-speed", number)

fn _rate_add {number:nat} (place: reading_place, rate: speech_rate, number: int number, chosen: speech_rate): void = let
  val @(value, label) = _rate_option(rate)
  val @(id, id_len) = _rate_option_id(place, number)
  val @(value_bytes, value_len) = _bytes_of(value)
  val @(label_bytes, label_len) = _bytes_of(label)
in ui_option(reading_part_id(place, SpeechRate()), id, id_len, value_bytes, value_len, label_bytes, label_len, _same_rate(rate, chosen)) end

(* The speeds' select in place, the one chosen chosen *)
fn _rates_show_in (place: reading_place): void = let
  val chosen = set_speech_rate_get()
  val () = ui_clear(reading_part_id(place, SpeechRate()))
  val () = _rate_add(place, RateThreeQuarters(), 0, chosen)
  val () = _rate_add(place, RateNormal(), 1, chosen)
  val () = _rate_add(place, RateOneAndAQuarter(), 2, chosen)
  val () = _rate_add(place, RateOneAndAHalf(), 3, chosen)
  val () = _rate_add(place, RateOneAndThreeQuarters(), 4, chosen)
in _rate_add(place, RateDouble(), 5, chosen) end

(* The speeds' selects, in both places they are offered *)
fn _rates_show (): void = let
  val () = _rates_show_in(InSheet())
in _rates_show_in(InSettings()) end

(* Whether bytes[0, n) is text *)
fun _bytes_are {l:agz}{size:nat}{n:nat | n <= size}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (bytes: !$A.arr(byte, l, size), n: int n, text: string text_len, text_len: int text_len, i: int i): bool =
  if n <> text_len then false
  else if i >= text_len then true
  else if i >= n then false
  else if byte2int0($A.get<byte>(bytes, i)) <> char2int0(string_get_at(text, i)) then false
  else _bytes_are(bytes, n, text, text_len, i + 1)

fn _is {l:agz}{size:nat}{n:nat | n <= size}{text_len:pos} (bytes: !$A.arr(byte, l, size), n: int n, text: string text_len): bool =
  _bytes_are(bytes, n, text, g1u2i(string1_length(text)), 0)

(* The value of select id, as bytes; none when it has none *)
fn _select_value {id_len:pos | id_len < 256} (id: string id_len): [l:agz][n:nat | n <= 64] @($A.arr(byte, l, n + 1), int n) = let
  val id_len = g1u2i(string1_length(id))
  val @(id_bytes_owned, _) = _bytes_of(id)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id_bytes_owned)
  val value = $DR.read_input_value(id_bytes, id_len)
  val () = release_bytes(id_frozen, id_bytes)
in
  case+ value of
  | ~$R.none() => let val empty = $A.alloc<byte>(1) in @(empty, 0) end
  | ~$R.some(blob) => let
      val n = $BD.blob_len(blob)
    in
      if n <= 0 then let val () = $BD.blob_free(blob) val empty = $A.alloc<byte>(1) in @(empty, 0) end
      else if n > 64 then let val () = $BD.blob_free(blob) val empty = $A.alloc<byte>(1) in @(empty, 0) end
      else let
        val bytes = $A.alloc<byte>(n + 1)
        val () = $BD.blob_read(blob, 0, bytes, n)
        val () = $BD.blob_free(blob)
      in @(bytes, n) end
    end
end

(* The speed place's select has chosen *)
fn _rate_chosen_in (place: reading_place): speech_rate = let
  val @(value, n) = _select_value(reading_part_id(place, SpeechRate()))
  val rate = (if _is(value, n, "0.75") then RateThreeQuarters()
    else if _is(value, n, "1.25") then RateOneAndAQuarter()
    else if _is(value, n, "1.5") then RateOneAndAHalf()
    else if _is(value, n, "1.75") then RateOneAndThreeQuarters()
    else if _is(value, n, "2") then RateDouble()
    else RateNormal()): speech_rate
  val () = $A.free<byte>(value)
in rate end

(* Whether a voice's language, lang[0, lang_len) ("en-US", "en_GB"),
   has the primary subtag code[0, code_len) ("en"), in any case *)
fn _lang_is {lang_loc,code_loc:agz}{lang_len:pos}{code_len:pos | code_len <= 3}
  (lang: !$A.arr(byte, lang_loc, lang_len), lang_len: int lang_len, code: !$A.arr(byte, code_loc, 3), code_len: int code_len): bool = let
  fn lower (code: int): int = if code >= 65 then (if code <= 90 then code + 32 else code) else code
  fun same {i:nat | i <= code_len} .<code_len - i>. (lang: !$A.arr(byte, lang_loc, lang_len), code: !$A.arr(byte, code_loc, 3), i: int i): bool =
    if i >= code_len then
      (* the subtag ends there *)
      (if i >= lang_len then true
       else let val after = byte2int0($A.get<byte>(lang, i)) in after = 45 || after = 95 end)
    else if i >= lang_len then false
    else if lower(byte2int0($A.get<byte>(lang, i))) <> byte2int0($A.get<byte>(code, i)) then false
    else same(lang, code, i + 1)
in same(lang, code, 0) end

(* Whether name[0, name_len) is kept[0, kept_len) *)
fun _names_same {name_loc,kept_loc:agz}{name_len,kept_size:pos}{kept_len:nat | kept_len <= kept_size}{i:nat | i <= name_len} .<name_len - i>.
  (name: !$A.arr(byte, name_loc, name_len), name_len: int name_len, kept: !$A.arr(byte, kept_loc, kept_size), kept_len: int kept_len, i: int i): bool =
  if name_len <> kept_len then false
  else if i >= name_len then true
  else if i >= kept_len then false
  else if byte2int0($A.get<byte>(name, i)) <> byte2int0($A.get<byte>(kept, i)) then false
  else _names_same(name, name_len, kept, kept_len, i + 1)

(* name[0, name_len) in a new array *)
fun _name_copy {source_loc,copy_loc:agz}{name_len:pos}{i:nat | i <= name_len} .<name_len - i>.
  (source: !$A.arr(byte, source_loc, name_len), copy: !$A.arr(byte, copy_loc, name_len), name_len: int name_len, i: int i): void =
  if i >= name_len then ()
  else let
    val () = $A.set<byte>(copy, i, $A.get<byte>(source, i))
  in _name_copy(source, copy, name_len, i + 1) end

(* A voice's option's id in place: the sheet's, or the Reading
   screen's *)
fn _voice_option_id {number:nat} (place: reading_place, number: int number)
  : [id_loc:agz][id_len:pos | id_len <= 32] @($A.arr(byte, id_loc, id_len), int id_len) =
  case+ place of
  | InSheet() => nid_make("voice-option", number)
  | InSettings() => nid_make("reading-voice", number)

(* The voices of the book's language (code[0, code_len)) as options of
   place's select, numbered from number on, the one named
   kept[0, kept_len) chosen; the next number *)
fun _voice_options {k:nat}{code_loc,kept_loc:agz}{code_len:pos | code_len <= 3}{kept_size:pos}{kept_len:nat | kept_len <= kept_size}{number:pos} .<k>.
  (place: reading_place, voices: !$SP.voices(k), code: !$A.arr(byte, code_loc, 3), code_len: int code_len,
   kept: !$A.arr(byte, kept_loc, kept_size), kept_len: int kept_len, number: int number): [next:pos] int next =
  case+ voices of
  | $SP.VoicesEnd() => number
  | $SP.VoicesMore(voice, rest) =>
    (case+ voice of
    | $SP.Voice(name, name_len, lang, _) => let
      val ours = (case+ lang of
        | $SP.NoLanguage() => false
        | $SP.Language(lang_bytes, lang_len) => _lang_is(lang_bytes, lang_len, code, code_len)): bool
    in
      if ~ours then _voice_options(place, rest, code, code_len, kept, kept_len, number)
      else if name_len >= 256 then _voice_options(place, rest, code, code_len, kept, kept_len, number)
      else let
        val @(id, id_len) = _voice_option_id(place, number)
        val value_text = $A.alloc<byte>(12)
        val value_len = $S.int_to_str(value_text, 0, 12, number)
        val label = $A.alloc<byte>(name_len)
        val () = _name_copy(name, label, name_len, 0)
        val chosen = _names_same(name, name_len, kept, kept_len, 0)
        val () = (if value_len > 0 then ui_option(reading_part_id(place, SpeechVoice()), id, id_len, value_text, value_len, label, name_len, chosen)
          else let val () = $A.free<byte>(id) val () = $A.free<byte>(value_text) in $A.free<byte>(label) end)
      in _voice_options(place, rest, code, code_len, kept, kept_len, number + 1) end
    end)

(* The voices' select in place: Automatic, and the voices of the
   book's language (the book open, or the one last read), the one kept
   for it chosen *)
fn _voices_show_in (place: reading_place): void = let
  val () = ui_clear(reading_part_id(place, SpeechVoice()))
  val @(code, code_len) = reader_lang_code()
  val @(kept, kept_len) = _voice_name()
  val @(automatic_id, automatic_id_len) = _voice_option_id(place, 0)
  val @(automatic_value, automatic_value_len) = _bytes_of("0")
  val @(automatic_label, automatic_label_len) = _bytes_of("Automatic")
  val () = ui_option(reading_part_id(place, SpeechVoice()), automatic_id, automatic_id_len, automatic_value, automatic_value_len,
    automatic_label, automatic_label_len, kept_len = 0)
  val () = (case+ $SP.speech_voices() of
    | ~$R.none() => ()
    | ~$R.some(voices) => let
        val _ = _voice_options(place, voices, code, code_len, kept, kept_len, 1)
      in $SP.voices_free(voices) end)
  val () = $A.free<byte>(kept)
in $A.free<byte>(code) end

(* The voices' selects, in both places they are offered *)
fn _voices_show (): void = let
  val () = _voices_show_in(InSheet())
in _voices_show_in(InSettings()) end

(* The name of the voice-th voice of the book's language (from 1), in a
   new array; none when there is no such voice *)
fun _voice_numbered {k:nat}{code_loc:agz}{code_len:pos | code_len <= 3} .<k>.
  (voices: !$SP.voices(k), code: !$A.arr(byte, code_loc, 3), code_len: int code_len, wanted: int, number: int): kept_voice =
  case+ voices of
  | $SP.VoicesEnd() => AutomaticVoice()
  | $SP.VoicesMore(voice, rest) =>
    (case+ voice of
    | $SP.Voice(name, name_len, lang, _) => let
      val ours = (case+ lang of
        | $SP.NoLanguage() => false
        | $SP.Language(lang_bytes, lang_len) => _lang_is(lang_bytes, lang_len, code, code_len)): bool
    in
      if ~ours then _voice_numbered(rest, code, code_len, wanted, number)
      else if name_len >= 256 then _voice_numbered(rest, code, code_len, wanted, number)
      else if number = wanted then let
        val copy = $A.alloc<byte>(name_len)
        val () = _name_copy(name, copy, name_len, 0)
      in KeptVoice(copy, name_len) end
      else _voice_numbered(rest, code, code_len, wanted, number + 1)
    end)

(* A number's digits, value[0, n), as a number; -1 when they are not *)
fun _digits {l:agz}{size:pos}{n:nat | n <= size}{i:nat | i <= n} .<n - i>.
  (value: !$A.arr(byte, l, size), n: int n, i: int i, number: int): int =
  if i >= n then number
  else let
    val code = byte2int0($A.get<byte>(value, i))
  in
    if code < 48 then ~1 else if code > 57 then ~1
    else if number > 99999 then ~1
    else _digits(value, n, i + 1, number * 10 + (code - 48))
  end

(* The voice place's select has chosen, kept for the book's language *)
fn _voice_chosen_in (place: reading_place): void = let
  val @(value, n) = _select_value(reading_part_id(place, SpeechVoice()))
  val wanted = (if n > 0 then _digits(value, n, 0, 0) else ~1): int
  val () = $A.free<byte>(value)
  val @(code, code_len) = reader_lang_code()
  val chosen = (if wanted <= 0 then AutomaticVoice()
    else (case+ $SP.speech_voices() of
      | ~$R.none() => AutomaticVoice()
      | ~$R.some(voices) => let
          val found = _voice_numbered(voices, code, code_len, wanted, 1)
          val () = $SP.voices_free(voices)
        in found end)): kept_voice
  val () = set_voice_set(code, code_len, chosen)
in $A.free<byte>(code) end

(* A speed or a voice chosen in place (a change of its row: the event
   does not say which select, so both are read, the other one as it
   shows what is kept): kept, both places' selects and the Settings
   screen's Reading row showing it, and what is being said is said
   again as they are now *)
#pub fn aloud_speech_chosen (place: reading_place): void

implement aloud_speech_chosen (place) = let
  val () = set_speech_rate_set(_rate_chosen_in(place))
  val () = _voice_chosen_in(place)
  val () = set_save(lib_state_get())
  val () = _rates_show()
  val () = _voices_show()
  val () = set_reading_show()
in _again() end

(* ============================================================
   What the reader does
   ============================================================ *)

(* Read aloud clicked: from the page shown; paused; or on again *)
#pub fn aloud_toggle (): void

implement aloud_toggle () =
  case+ _take() of
  | ~Silent() => let
      val () = _put(Silent())
    in _from_page(STEPS_MAX, _begin()) end
  | ~Loading() => _stop()
  | ~Saying(script, index, _) => let
      val _ = _run_next()
      val () = _put(Paused(script, index))
      val () = _unmark()
      val () = _pressed(false)
    in $SP.speech_cancel() end
  | ~Turning(script, index, purpose) => let
      val () = _turn_for_free(purpose)
      val _ = _run_next()
      val () = _put(Paused(script, index))
      val () = _unmark()
    in _pressed(false) end
  | ~Paused(script, index) => let
      val run = _begin()
      (* on from the sentence it was saying, when that is still shown *)
      val here = (if script_chapter(script) <> _chapter_shown() then false
        else if index >= script_count(script) then false
        else (case+ _sentence_placement(script, index) of
          | OnPage() => true
          | Before() => false
          | After() => false)): bool
    in
      if here then _go(STEPS_MAX, run, script, index, TURNS_MAX)
      else let
        val () = script_free(script)
      in _from_page(STEPS_MAX, run) end
    end

(* Read from here: from the sentence the selection starts in *)
#pub fn aloud_from_selection (): void

implement aloud_from_selection () = let
  val @(start_blob, end_blob) = $DR.get_selection_range()
  val start_offset = $DR.get_measure_x()
  val () = (case+ end_blob of ~$R.none() => () | ~$R.some(blob) => $BD.blob_free(blob))
  val node = (case+ start_blob of
    | ~$R.none() => ~1
    | ~$R.some(blob) => let
        val id_len = $BD.blob_len(blob)
      in
        if id_len <= 1 then let val () = $BD.blob_free(blob) in ~1 end
        else if id_len > 16 then let val () = $BD.blob_free(blob) in ~1 end
        else let
          val id = $A.alloc<byte>(id_len)
          val () = $BD.blob_read(blob, 0, id, id_len)
          val () = $BD.blob_free(blob)
          val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
          val number = nid_parse(id_bytes, id_len, 0, "c")
          val () = release_bytes(id_frozen, id_bytes)
        in number end
      end): Int
in
  (* a selection outside the book's text reads nothing *)
  if node < 0 then ()
  else let
    val () = _stop()
  in _from_point(_begin(), node, start_offset) end
end

(* Reading stops (the library shown, another book opened) *)
#pub fn aloud_stop (): void

implement aloud_stop () =
  case+ _take() of
  | ~Silent() => _put(Silent())
  | other => let
      val () = _put(other)
    in _stop() end

(* The utterance being said failed: reading stops *)
fn _failed (utterance: Int): void =
  case+ _take() of
  | ~Saying(script, index, awaited) =>
    if awaited = utterance then let
      val () = script_free(script)
    in _stop() end
    else _put(Saying(script, index, awaited))
  | other => _put(other)

(* An event of speech: the sentence said, the next one; a failure (but
   one this module caused, by a pause or a stop) stops reading; the
   voices changed, offered again *)
#pub fn aloud_event (event: $SP.speech_event): void

implement aloud_event (event) =
  case+ event of
  | ~$SP.SpeechEnded(utterance) =>
    (case+ _take() of
     | ~Saying(script, index, awaited) =>
       if awaited = utterance then _go(STEPS_MAX, !_run, script, index + 1, 0)
       else _put(Saying(script, index, awaited))
     | other => _put(other))
  | ~$SP.SpeechFailed(utterance, failure) =>
    (case+ failure of
     | $SP.Interrupted() => ()
     | $SP.NotAllowed() => _failed(utterance)
     | $SP.NoSuchVoice() => _failed(utterance)
     | $SP.OtherFailure() => _failed(utterance))
  | ~$SP.SpeechStarted(_) => ()
  | ~$SP.SpeechBoundary(_, _) => ()
  | ~$SP.VoicesChanged() => _voices_show()

(* The reading settings' sheet or the Reading screen opened: the speeds
   and the book's language's voices offered in both, as chosen *)
#pub fn aloud_choices_show (): void

implement aloud_choices_show () = let
  val () = _rates_show()
in _voices_show() end

(* ============================================================
   Startup
   ============================================================ *)

(* Read aloud, Read from here and the panel's speed and voice, shown
   only where the platform speaks *)
#pub fn aloud_offer (): void

implement aloud_offer () = let
  val speaks = $SP.speech_available()
  val () = ui_show("read-aloud", speaks)
  val () = ui_show("selection-read", speaks)
  val () = ui_show(reading_part_id(InSheet(), SpeechRow()), speaks)
  (* the Reading screen's speed and voice, under their title *)
  val () = ui_show(reading_part_id(InSettings(), SpeechRow()), speaks)
  val () = ui_show("reading-aloud-title", speaks)
  (* the reading settings' Read aloud tab, which holds its speed and voice *)
in ui_show("typography-aloud-tab", speaks) end

end (* #target wasm *)
