(* settings -- typography and theme, applied and saved on every change *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S

staload "ui.sats"
staload "notice.sats"
staload "undo.sats"
staload "book.sats"
staload "mem.sats"
staload "local_time.sats"
staload "jsonio.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload "storage.sats"
staload "style.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload MEDIA = "wasm.bats-packages.dev/bridge/src/media.sats"

implement $P.dispose<settled>(_) = ()

(* The settings, each in its range:
   size               font size in px, 12 to 32
   line_height        line spacing in tenths, 12 to 24
   margin             page margins, 0 (narrow) to 4 (wide)
   font               font
   align              alignment
   hyphens            hyphenation
   paragraph_spacing  space after a paragraph in tenths of an em, 0 to 20
   letter_spacing     letter spacing in hundredths of an em, 0 to 12
   word_spacing       word spacing in hundredths of an em, 0 to 16
   dim_images         image_dimming
   tap_zones          tap_zones
   volume_keys        volume_keys
   scrolled           page_flow
   columns            column_count
   readout            readout
   ruby               ruby_display (kept apart, in _ruby)
   narration speed    a book's narration (its Media Overlays), in
                      quarters of its own speed: 2 (half) to 8 (double),
                      the range EPUB 3.3's reading systems offer
   Each is stored as a byte, decoded once as it is read (its _of_code)
   and encoded once as it is written (its _code)
   (the spacings reach what WCAG 1.4.12 asks a page to take: 2em
   after a paragraph, .12em between letters, .16em between words) *)
#pub typedef set_size = [v:int | 12 <= v; v <= 32] int v
#pub typedef set_lh = [v:int | 12 <= v; v <= 24] int v
#pub typedef set_margin = [v:nat | v <= 4] int v
(* The reader's font: Literata, Inter, the book's own, or Atkinson
   Hyperlegible *)
#pub datatype font = Literata | Inter | BookFont | Atkinson
#pub typedef set_font = font

(* The theme chosen: auto (Night at night, Dark when the system asks
   for it, else Light), or one fixed *)
#pub datavtype theme_choice = Auto | Fixed of theme

(* A text's alignment: ragged (WCAG 1.4.8) or justified *)
#pub datatype alignment = Ragged | Justified
#pub typedef set_align = alignment

#pub datatype hyphenation = NoHyphens | Hyphenated
#pub typedef set_hyph = hyphenation
#pub typedef set_ps = [v:nat | v <= 20] int v
#pub typedef set_ls = [v:nat | v <= 12] int v
#pub typedef set_ws = [v:nat | v <= 16] int v
(* A book's images: as they are, or dimmed in the dark themes *)
#pub datatype image_dimming = ImagesAsTheyAre | ImagesDimmed
#pub typedef set_dim = image_dimming

(* What a tap on the page does, where: sides (the left quarter back,
   the right on, between them the bars), forward (the top band the
   bars, the left quarter back, anywhere else on), or one hand (the top
   third back, the bottom third on, between them the bars); mirrored
   for a book read right to left (quire.bats's _zone_click) *)
#pub datatype tap_zones = SideZones | ForwardZones | OneHandZones
#pub typedef set_taps = tap_zones

(* The volume keys: the volume's, or they turn the page *)
#pub datatype volume_keys = KeysForVolume | KeysTurnPages
#pub typedef set_vol = volume_keys

(* The footer's readout: pages left in the chapter, the page of the
   chapter's pages, the chapter of the book's, the time left in the
   chapter, or in the book (where the browser gives them to the page) *)
#pub datatype readout = PagesLeft | PageOfPages | ChapterOfChapters | TimeLeftInChapter | TimeLeftInBook
#pub typedef set_rd = readout

(* A chapter turned across in pages, or scrolled down *)
#pub datatype page_flow = Paged | Scrolled
#pub typedef set_flow = page_flow

(* Paged, the columns a screen shows: auto (two on a wide screen in
   landscape, else one), one, or two (a spread) *)
#pub datatype column_count = AutoColumns | OneColumn | TwoColumns
#pub typedef set_cols = column_count

(* A ruby's annotations (furigana over a word): shown or hidden *)
#pub datatype ruby_display = RubyShown | RubyHidden
#pub typedef set_ruby = ruby_display

(* Each setting as the "S2" record and the backup store it, and back:
   decoded once, as it is read (an unknown byte is the default) *)
#pub fn font_code (v: font): [code:nat | code <= 3] int code
implement font_code (v) = case+ v of Literata() => 0 | Inter() => 1 | BookFont() => 2 | Atkinson() => 3
#pub fn font_of_code (code: int): font
implement font_of_code (code) = if code = 1 then Inter() else if code = 2 then BookFont() else if code = 3 then Atkinson() else Literata()

(* 0 auto, 1 light, 2 sepia, 3 dark, 4 night, 5 grey *)
#pub fn theme_choice_code (v: !theme_choice): [code:nat | code <= 5] int code
implement theme_choice_code (v) = case+ v of Auto() => 0 | Fixed(t) => 1 + theme_palette(t)
#pub fn theme_choice_of_code (code: int): theme_choice
implement theme_choice_of_code (code) =
  if code = 1 then Fixed(Light()) else if code = 2 then Fixed(Sepia()) else if code = 3 then Fixed(Dark())
  else if code = 4 then Fixed(Night()) else if code = 5 then Fixed(Grey()) else Auto()

#pub fn align_code (v: alignment): [code:nat | code <= 1] int code
implement align_code (v) = case+ v of Ragged() => 0 | Justified() => 1
#pub fn align_of_code (code: int): alignment
implement align_of_code (code) = if code = 1 then Justified() else Ragged()

#pub fn hyph_code (v: hyphenation): [code:nat | code <= 1] int code
implement hyph_code (v) = case+ v of NoHyphens() => 0 | Hyphenated() => 1
#pub fn hyph_of_code (code: int): hyphenation
implement hyph_of_code (code) = if code = 0 then NoHyphens() else Hyphenated()

#pub fn dim_code (v: image_dimming): [code:nat | code <= 1] int code
implement dim_code (v) = case+ v of ImagesAsTheyAre() => 0 | ImagesDimmed() => 1
#pub fn dim_of_code (code: int): image_dimming
implement dim_of_code (code) = if code = 0 then ImagesAsTheyAre() else ImagesDimmed()

#pub fn taps_code (v: tap_zones): [code:nat | code <= 2] int code
implement taps_code (v) = case+ v of SideZones() => 0 | ForwardZones() => 1 | OneHandZones() => 2
#pub fn taps_of_code (code: int): tap_zones
implement taps_of_code (code) = if code = 1 then ForwardZones() else if code = 2 then OneHandZones() else SideZones()

#pub fn vol_code (v: volume_keys): [code:nat | code <= 1] int code
implement vol_code (v) = case+ v of KeysForVolume() => 0 | KeysTurnPages() => 1
#pub fn vol_of_code (code: int): volume_keys
implement vol_of_code (code) = if code = 1 then KeysTurnPages() else KeysForVolume()

#pub fn rd_code (v: readout): [code:nat | code <= 4] int code
implement rd_code (v) =
  case+ v of PagesLeft() => 0 | PageOfPages() => 1 | ChapterOfChapters() => 2 | TimeLeftInChapter() => 3 | TimeLeftInBook() => 4
#pub fn rd_of_code (code: int): readout
implement rd_of_code (code) =
  if code = 1 then PageOfPages() else if code = 2 then ChapterOfChapters() else if code = 3 then TimeLeftInChapter()
  else if code = 4 then TimeLeftInBook() else PagesLeft()

#pub fn flow_code (v: page_flow): [code:nat | code <= 1] int code
implement flow_code (v) = case+ v of Paged() => 0 | Scrolled() => 1
#pub fn flow_of_code (code: int): page_flow
implement flow_of_code (code) = if code = 1 then Scrolled() else Paged()

#pub fn cols_code (v: column_count): [code:nat | code <= 2] int code
implement cols_code (v) = case+ v of AutoColumns() => 0 | OneColumn() => 1 | TwoColumns() => 2
#pub fn cols_of_code (code: int): column_count
implement cols_of_code (code) = if code = 1 then OneColumn() else if code = 2 then TwoColumns() else AutoColumns()

#pub fn ruby_code (v: ruby_display): [code:nat | code <= 1] int code
implement ruby_code (v) = case+ v of RubyHidden() => 0 | RubyShown() => 1
#pub fn ruby_of_code (code: int): ruby_display
implement ruby_of_code (code) = if code = 0 then RubyHidden() else RubyShown()

#pub typedef set_narration_speed = [v:int | 2 <= v; v <= 8] int v
(* Whether a book's narration reads its page numbers and notes (EPUB's
   skippable structures) or passes over them *)
#pub datatype narration_notes = NotesSkipped | NotesRead

typedef settings = @{
  size = set_size, line_height = set_lh, margin = set_margin, font = set_font,
  align = set_align, hyphens = set_hyph, paragraph_spacing = set_ps, letter_spacing = set_ls,
  word_spacing = set_ws, dim_images = set_dim, tap_zones = set_taps, volume_keys = set_vol,
  readout = set_rd, scrolled = set_flow, columns = set_cols
}

(* The defaults: text ragged (WCAG 1.4.8: not justified) and
   hyphenated, the paragraph spacing the page always had, and images
   dimmed in the dark theme *)
fn _defaults (): settings =
  @{ size = 18, line_height = 16, margin = 2, font = Literata(), align = Ragged(), hyphens = Hyphenated(),
     paragraph_spacing = 8, letter_spacing = 0, word_spacing = 0, dim_images = ImagesDimmed(), tap_zones = SideZones(),
     volume_keys = KeysForVolume(), readout = PagesLeft(), scrolled = Paged(), columns = AutoColumns() }

val _set = ref<settings>(_defaults())
(* The theme chosen (auto, the default): kept apart from the record, as
   _ruby is, and taken out and put back, since it is linear *)
val _theme_choice = ref<theme_choice>(Auto())

fn _choice_copy (choice: !theme_choice): theme_choice =
  case+ choice of Auto() => Auto() | Fixed(t) => Fixed(t)

#pub fn theme_choice_free (choice: theme_choice): void
implement theme_choice_free (choice) =
  case+ choice of ~Auto() => () | ~Fixed(_) => ()

(* Whether the theme chosen, as its code, is the one wanted *)
fn _is_chosen (code: int, wanted: theme_choice): bool = let
  val wanted_code = theme_choice_code(wanted)
  val () = theme_choice_free(wanted)
in code = wanted_code end

(* Whether a ruby's annotations are shown (the default) or hidden.
   Kept apart from the record in memory (it is byte 19 of the stored
   one): each of the record's setters writes the record out whole, so a
   field there costs a line in every one of them, and a cell of its own
   costs one setter. (Wasm builds now have memmove, bats-lang/bats#220,
   so the record's size is no longer a limit) *)
val _ruby = ref<ruby_display>(RubyShown())
(* A book narration's speed, in quarters of its own (2, half, to 8,
   double: the range EPUB 3.3's reading systems offer), and whether it
   reads page numbers and notes: the device's own, kept apart from the
   record as they are *)
val _narration_speed = ref<int>(4)
val _narration_notes = ref<narration_notes>(NotesSkipped())
(* Whether the system asks for a dark theme (for auto) *)
val _system_dark = ref<bool>(false)

(* ============================================================
   Reading aloud's speed and voices, the screen's brightness, its
   rotation lock and full screen. Kept with the settings (bytes 20 on of their record),
   apart from the record in memory, as _ruby is; in the backup, and
   reset (and put back by Undo) with the settings
   ============================================================ *)

(* How fast a book is read aloud, three quarters of the normal speed to
   twice it *)
#pub datatype speech_rate =
  | RateThreeQuarters | RateNormal | RateOneAndAQuarter
  | RateOneAndAHalf | RateOneAndThreeQuarters | RateDouble

(* The speed in hundredths of the normal one, as bridge's speech_speak
   takes it *)
#pub fn speech_rate_hundredths (rate: speech_rate): [hundredths:int | 75 <= hundredths; hundredths <= 200] int hundredths

implement speech_rate_hundredths (rate) =
  case+ rate of
  | RateThreeQuarters() => 75 | RateNormal() => 100 | RateOneAndAQuarter() => 125
  | RateOneAndAHalf() => 150 | RateOneAndThreeQuarters() => 175 | RateDouble() => 200

fn _rate_code (rate: speech_rate): [code:nat | code <= 5] int code =
  case+ rate of
  | RateThreeQuarters() => 0 | RateNormal() => 1 | RateOneAndAQuarter() => 2
  | RateOneAndAHalf() => 3 | RateOneAndThreeQuarters() => 4 | RateDouble() => 5

(* A stored byte's speed: checked here, once; the normal speed when it
   is not one *)
fn _rate_of_code (code: int): speech_rate =
  if code = 0 then RateThreeQuarters() else if code = 2 then RateOneAndAQuarter()
  else if code = 3 then RateOneAndAHalf() else if code = 4 then RateOneAndThreeQuarters()
  else if code = 5 then RateDouble() else RateNormal()

(* The speed of so many hundredths of the normal one (a backup's):
   checked here, once; the normal speed when it is not one of them *)
#pub fn speech_rate_of_hundredths (hundredths: int): speech_rate
implement speech_rate_of_hundredths (hundredths) =
  if hundredths = 75 then RateThreeQuarters() else if hundredths = 125 then RateOneAndAQuarter()
  else if hundredths = 150 then RateOneAndAHalf() else if hundredths = 175 then RateOneAndThreeQuarters()
  else if hundredths = 200 then RateDouble() else RateNormal()

(* The screen's brightness while the app is shown: the system's own, or
   a level (the app only: a web page cannot set it) *)
#pub datatype brightness_choice =
  | BrightnessSystem | BrightnessTenth | BrightnessQuarter
  | BrightnessHalf | BrightnessThreeQuarters | BrightnessFull

fn _brightness_code (choice: brightness_choice): [code:nat | code <= 5] int code =
  case+ choice of
  | BrightnessSystem() => 0 | BrightnessTenth() => 1 | BrightnessQuarter() => 2
  | BrightnessHalf() => 3 | BrightnessThreeQuarters() => 4 | BrightnessFull() => 5

(* A level's percent, as a backup has it; none (0) for the system's
   own *)
#pub fn brightness_percent (choice: brightness_choice): [percent:nat | percent <= 100] int percent
implement brightness_percent (choice) =
  case+ choice of
  | BrightnessSystem() => 0 | BrightnessTenth() => 10 | BrightnessQuarter() => 25
  | BrightnessHalf() => 50 | BrightnessThreeQuarters() => 75 | BrightnessFull() => 100

(* The level of a percent (a backup's): checked here, once; the
   system's own when it is not one of them *)
#pub fn brightness_of_percent (percent: int): brightness_choice
implement brightness_of_percent (percent) =
  if percent = 10 then BrightnessTenth() else if percent = 25 then BrightnessQuarter()
  else if percent = 50 then BrightnessHalf() else if percent = 75 then BrightnessThreeQuarters()
  else if percent = 100 then BrightnessFull() else BrightnessSystem()

fn _brightness_of_code (code: int): brightness_choice =
  if code = 1 then BrightnessTenth() else if code = 2 then BrightnessQuarter()
  else if code = 3 then BrightnessHalf() else if code = 4 then BrightnessThreeQuarters()
  else if code = 5 then BrightnessFull() else BrightnessSystem()

(* Whether the screen's rotation is locked (to the one it had then) *)
#pub datatype rotation = RotationFree | RotationLocked

fn _rotation_code (turn: rotation): [code:nat | code <= 1] int code =
  case+ turn of RotationFree() => 0 | RotationLocked() => 1

fn _rotation_of_code (code: int): rotation =
  if code = 1 then RotationLocked() else RotationFree()

(* Whether the app shows its pages full screen, its system bars hidden
   (quire#313). The app's own: a browser goes into full screen only at a
   click (the Fullscreen API needs the user's activation), so there it
   is not kept, and is never set again as a page opens *)
#pub datatype fullscreen_choice = FullscreenOff | FullscreenOn

fn _fullscreen_code (choice: fullscreen_choice): [code:nat | code <= 1] int code =
  case+ choice of FullscreenOff() => 0 | FullscreenOn() => 1

fn _fullscreen_of_code (code: int): fullscreen_choice =
  if code = 1 then FullscreenOn() else FullscreenOff()

val _speech_rate = ref<speech_rate>(RateNormal())
val _brightness = ref<brightness_choice>(BrightnessSystem())
val _rotation = ref<rotation>(RotationFree())
val _fullscreen = ref<fullscreen_choice>(FullscreenOff())

#pub fn set_speech_rate_get (): speech_rate
implement set_speech_rate_get () = !_speech_rate
#pub fn set_speech_rate_set (rate: speech_rate): void
implement set_speech_rate_set (rate) = !_speech_rate := rate
#pub fn set_brightness_get (): brightness_choice
implement set_brightness_get () = !_brightness
#pub fn set_brightness_set (choice: brightness_choice): void
implement set_brightness_set (choice) = !_brightness := choice
#pub fn set_rotation_get (): rotation
implement set_rotation_get () = !_rotation
#pub fn set_rotation_set (turn: rotation): void
implement set_rotation_set (turn) = !_rotation := turn
#pub fn set_fullscreen_get (): fullscreen_choice
implement set_fullscreen_get () = !_fullscreen
#pub fn set_fullscreen_set (choice: fullscreen_choice): void
implement set_fullscreen_set (choice) = !_fullscreen := choice

(* The voice chosen for each language a book was read aloud in: its
   primary subtag ("en", lower case) and the voice's name; a language
   with none is read in its automatic voice *)
#define VOICES_MAX 16
#define VOICE_NAME_MAX 255

datavtype voice_choices(int) =
  | VoiceChoicesEnd(0)
  | {count:nat}{code_loc,name_loc:agz}{code_len:pos | code_len <= 3}{name_len:pos | name_len <= VOICE_NAME_MAX}
    VoiceChoice(count + 1) of ($A.arr(byte, code_loc, 3), int code_len, $A.arr(byte, name_loc, name_len), int name_len, voice_choices(count))

datavtype voices_cell = {count:nat | count <= VOICES_MAX} VoicesCell of (voice_choices(count), int count)

val _voices = ref<voices_cell>(VoicesCell(VoiceChoicesEnd(), 0))

fun _voice_choices_free {count:nat} .<count>. (choices: voice_choices(count)): void =
  case+ choices of
  | ~VoiceChoicesEnd() => ()
  | ~VoiceChoice(code, _, name, _, rest) => let
      val () = $A.free<byte>(code)
      val () = $A.free<byte>(name)
    in _voice_choices_free(rest) end

fn _voices_take (): voices_cell = let
  var cell: voices_cell = VoicesCell(VoiceChoicesEnd(), 0)
  val () = ref_exch_elt<voices_cell>(_voices, cell)
in cell end

fn _voices_put (cell: voices_cell): void = let
  var previous: voices_cell = cell
  val () = ref_exch_elt<voices_cell>(_voices, previous)
  val+ ~VoicesCell(old, _) = previous
in _voice_choices_free(old) end

(* Whether code[0, code_len) is wanted[0, wanted_len) *)
fun _code_is {l,wanted_loc:agz}{wanted_size:pos}{code_len:nat | code_len <= 3}{wanted_len:nat | wanted_len <= wanted_size}{i:nat | i <= code_len} .<code_len - i>.
  (code: !$A.arr(byte, l, 3), code_len: int code_len, wanted: !$A.arr(byte, wanted_loc, wanted_size), wanted_len: int wanted_len, i: int i): bool =
  if code_len <> wanted_len then false
  else if i >= code_len then true
  else if i >= wanted_len then false
  else if byte2int0($A.get<byte>(code, i)) <> byte2int0($A.get<byte>(wanted, i)) then false
  else _code_is(code, code_len, wanted, wanted_len, i + 1)

(* A voice kept for a language: its name, or none (the automatic one) *)
#pub datavtype kept_voice =
  | {l:agz}{name_len:pos | name_len <= 255} KeptVoice of ($A.arr(byte, l, name_len), int name_len)
  | AutomaticVoice of ()

(* name[0, name_len) in a new array *)
fun _name_copy {source_loc,copy_loc:agz}{source_size,copy_size:pos}{name_len:nat | name_len <= source_size; name_len <= copy_size}{i:nat | i <= name_len} .<name_len - i>.
  (source: !$A.arr(byte, source_loc, source_size), copy: !$A.arr(byte, copy_loc, copy_size), name_len: int name_len, i: int i): void =
  if i >= name_len then ()
  else let
    val () = $A.set<byte>(copy, i, $A.get<byte>(source, i))
  in _name_copy(source, copy, name_len, i + 1) end

fun _voice_find {count:nat}{wanted_loc:agz}{wanted_size:pos}{wanted_len:nat | wanted_len <= wanted_size} .<count>.
  (choices: !voice_choices(count), wanted: !$A.arr(byte, wanted_loc, wanted_size), wanted_len: int wanted_len): kept_voice =
  case+ choices of
  | VoiceChoicesEnd() => AutomaticVoice()
  | VoiceChoice(code, code_len, name, name_len, rest) =>
    if _code_is(code, code_len, wanted, wanted_len, 0) then let
      val copy = $A.alloc<byte>(name_len)
      val () = _name_copy(name, copy, name_len, 0)
    in KeptVoice(copy, name_len) end
    else _voice_find(rest, wanted, wanted_len)

(* The voice kept for the language whose primary subtag is
   code[0, code_len) *)
#pub fn set_voice_get {l:agz}{code_len:pos | code_len <= 3} (code: !$A.arr(byte, l, 3), code_len: int code_len): kept_voice

implement set_voice_get (code, code_len) = let
  val cell = _voices_take()
  val+ @VoicesCell(choices, _) = cell
  val found = _voice_find(choices, code, code_len)
  prval () = fold@(cell)
  val () = _voices_put(cell)
in found end

(* The choices without the one for code[0, code_len), and how many are
   left *)
fun _voice_drop {count:nat}{wanted_loc:agz}{wanted_size:pos}{wanted_len:nat | wanted_len <= wanted_size} .<count>.
  (choices: voice_choices(count), wanted: !$A.arr(byte, wanted_loc, wanted_size), wanted_len: int wanted_len)
  : [left:nat | left <= count] @(voice_choices(left), int left) =
  case+ choices of
  | ~VoiceChoicesEnd() => @(VoiceChoicesEnd(), 0)
  | ~VoiceChoice(code, code_len, name, name_len, rest) =>
    if _code_is(code, code_len, wanted, wanted_len, 0) then let
      val () = $A.free<byte>(code)
      val () = $A.free<byte>(name)
    in _voice_drop(rest, wanted, wanted_len) end
    else let
      val @(kept, left) = _voice_drop(rest, wanted, wanted_len)
    in @(VoiceChoice(code, code_len, name, name_len, kept), left + 1) end

(* The voice kept for the language of code[0, code_len): a name, or the
   automatic one. A language past the 16th chosen is not kept *)
#pub fn set_voice_set {l:agz}{code_len:pos | code_len <= 3} (code: !$A.arr(byte, l, 3), code_len: int code_len, chosen: kept_voice): void

implement set_voice_set (code, code_len, chosen) = let
  val+ ~VoicesCell(choices, _) = _voices_take()
  val @(others, left) = _voice_drop(choices, code, code_len)
in
  case+ chosen of
  | ~AutomaticVoice() => _voices_put(VoicesCell(others, left))
  | ~KeptVoice(name, name_len) =>
    if left >= VOICES_MAX then let
      val () = $A.free<byte>(name)
    in _voices_put(VoicesCell(others, left)) end
    else let
      val code_copy = $A.alloc<byte>(3)
      val () = _name_copy(code, code_copy, code_len, 0)
    in _voices_put(VoicesCell(VoiceChoice(code_copy, code_len, name, name_len, others), left + 1)) end
end

(* The voices kept as a JSON object's members, "code":"name", from
   position (each after a comma but the first) *)
fun _voices_json {count:nat}{l:agz}{owner:addr}{n:nat}{position:nat | position + 1554 * count <= n} .<count>.
  (choices: !voice_choices(count), out: !$A.arrx(byte, l, n, owner), position: int position, first: bool)
  : [stop:nat | stop <= position + 1554 * count] int stop =
  case+ choices of
  | VoiceChoicesEnd() => position
  | VoiceChoice(code, code_len, name, name_len, rest) => let
      val at = (if first then position else jw_lit(out, position, ",")): [at:nat | position <= at; at <= position + 1] int at
      val at = jw_str(out, at, code, code_len)
      val at = jw_lit(out, at, ":")
      val at = jw_str(out, at, name, name_len)
    in _voices_json(rest, out, at, false) end

(* The voices kept, as a JSON object at out[position, stop) *)
#pub fn set_voices_json {l:agz}{owner:addr}{n:nat}{position:nat | position + 24866 <= n}
  (out: !$A.arrx(byte, l, n, owner), position: int position): [stop:nat | stop <= position + 24866] int stop

implement set_voices_json (out, position) = let
  val cell = _voices_take()
  val+ @VoicesCell(choices, _) = cell
  val at = jw_lit(out, position, "{")
  val at = _voices_json(choices, out, at, true)
  prval () = fold@(cell)
  val () = _voices_put(cell)
in jw_lit(out, at, "}") end

(* No voice kept for any language (a backup's are put in their place) *)
#pub fn set_voices_clear (): void
implement set_voices_clear () = _voices_put(VoicesCell(VoiceChoicesEnd(), 0))

(* The bytes the voices take in the record: for each, its code's length
   and code, its name's length and name *)
fun _voices_size {count:nat} .<count>. (choices: !voice_choices(count)): [size:nat | size <= count * (2 + 3 + VOICE_NAME_MAX)] int size =
  case+ choices of
  | VoiceChoicesEnd() => 0
  | VoiceChoice(_, code_len, _, name_len, rest) => 2 + code_len + name_len + _voices_size(rest)

fun _bytes_put {source_loc,record_loc:agz}{source_size,record_size:pos}{count:nat | count <= source_size}{at:nat | at + count <= record_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, record: !$A.arr(byte, record_loc, record_size), at: int at, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(record, at + i, $A.get<byte>(source, i))
  in _bytes_put(source, count, record, at, i + 1) end

(* The voices at record[at, at + _voices_size(choices)) *)
fun _voices_write {count:nat}{l:agz}{record_size:pos}{at:nat} .<count>.
  (choices: !voice_choices(count), record: !$A.arr(byte, l, record_size), record_size: int record_size, at: int at): void =
  case+ choices of
  | VoiceChoicesEnd() => ()
  | VoiceChoice(code, code_len, name, name_len, rest) =>
    if at + 2 + code_len + name_len > record_size then ()
    else let
      val () = $A.write_byte(record, at, code_len)
      val () = _bytes_put(code, code_len, record, at + 1, 0)
      val () = $A.write_byte(record, at + 1 + code_len, name_len)
      val () = _bytes_put(name, name_len, record, at + 2 + code_len, 0)
    in _voices_write(rest, record, record_size, at + 2 + code_len + name_len) end

(* The voices stored at record[at, n), each checked here, once: a code
   of 1 to 3 bytes and a name of 1 to 255; the reading stops at the
   first that is not *)
fun _voices_read {l:agz}{n:nat}{at:nat}{count:nat | count <= VOICES_MAX} .<max(n - at, 0)>.
  (record: !$A.arr(byte, l, n), n: int n, at: int at, left: int, choices: voice_choices(count), count: int count)
  : [read_count:nat | read_count <= VOICES_MAX] @(voice_choices(read_count), int read_count) =
  if left <= 0 then @(choices, count)
  else if count >= VOICES_MAX then @(choices, count)
  else if at + 1 > n then @(choices, count)
  else let
    val code_len = $AR.low_byte(byte2int0($A.get<byte>(record, at)))
  in
    if code_len < 1 then @(choices, count)
    else if code_len > 3 then @(choices, count)
    else if at + 1 + code_len + 1 > n then @(choices, count)
    else let
      val name_len = $AR.low_byte(byte2int0($A.get<byte>(record, at + 1 + code_len)))
    in
      if name_len < 1 then @(choices, count)
      else if at + 2 + code_len + name_len > n then @(choices, count)
      else let
        val code = $A.alloc<byte>(3)
        fun copy_out {code_loc:agz}{size:pos}{from:nat}{count:nat | from + count <= n; count <= size}{i:nat | i <= count} .<count - i>.
          (record: !$A.arr(byte, l, n), from: int from, out: !$A.arr(byte, code_loc, size), count: int count, i: int i): void =
          if i >= count then ()
          else let
            val () = $A.set<byte>(out, i, $A.get<byte>(record, from + i))
          in copy_out(record, from, out, count, i + 1) end
        val () = copy_out(record, at + 1, code, code_len, 0)
        val name = $A.alloc<byte>(name_len)
        val () = copy_out(record, at + 2 + code_len, name, name_len, 0)
      in _voices_read(record, n, at + 2 + code_len + name_len, left - 1, VoiceChoice(code, code_len, name, name_len, choices), count + 1) end
    end
  end

#pub fn set_size_get (): set_size
implement set_size_get () = (!_set).size
#pub fn set_lh_get (): set_lh
implement set_lh_get () = (!_set).line_height
#pub fn set_margin_get (): set_margin
implement set_margin_get () = (!_set).margin
#pub fn set_font_get (): set_font
implement set_font_get () = (!_set).font
(* The theme chosen, as a value of its own *)
#pub fn set_theme_get (): theme_choice
implement set_theme_get () = let
  var choice: theme_choice = Auto()
  val () = ref_exch_elt<theme_choice>(_theme_choice, choice)
  val copy = _choice_copy(choice)
  val () = ref_exch_elt<theme_choice>(_theme_choice, choice)
  val () = theme_choice_free(choice)
in copy end

#pub fn set_theme_set (value: theme_choice): void
implement set_theme_set (value) = let
  var choice: theme_choice = value
  val () = ref_exch_elt<theme_choice>(_theme_choice, choice)
in theme_choice_free(choice) end
#pub fn set_align_get (): set_align
implement set_align_get () = (!_set).align
#pub fn set_hyph_get (): set_hyph
implement set_hyph_get () = (!_set).hyphens
#pub fn set_ps_get (): set_ps
implement set_ps_get () = (!_set).paragraph_spacing
#pub fn set_ls_get (): set_ls
implement set_ls_get () = (!_set).letter_spacing
#pub fn set_ws_get (): set_ws
implement set_ws_get () = (!_set).word_spacing
#pub fn set_dim_get (): set_dim
implement set_dim_get () = (!_set).dim_images
#pub fn set_taps_get (): set_taps
implement set_taps_get () = (!_set).tap_zones
#pub fn set_vol_get (): set_vol
implement set_vol_get () = (!_set).volume_keys
#pub fn set_rd_get (): set_rd
implement set_rd_get () = (!_set).readout
#pub fn set_flow_get (): set_flow
implement set_flow_get () = (!_set).scrolled
#pub fn set_cols_get (): set_cols
implement set_cols_get () = (!_set).columns
#pub fn set_ruby_get (): set_ruby
implement set_ruby_get () = !_ruby
#pub fn set_narration_speed_get (): set_narration_speed
implement set_narration_speed_get () = let
  val speed = g1ofg0(!_narration_speed)
in if speed < 2 then 4 else if speed > 8 then 4 else speed end
#pub fn set_narration_notes_get (): narration_notes
implement set_narration_notes_get () = !_narration_notes

fn _notes_code (notes: narration_notes): [code:nat | code <= 1] int code =
  case+ notes of NotesSkipped() => 1 | NotesRead() => 0

(* A stored byte's choice: checked here, once; skipped when it is not
   one *)
fn _notes_of_code (code: int): narration_notes =
  if code = 0 then NotesRead() else NotesSkipped()

(* "N" and the narration's two bytes at record[at, at + 3) *)
fn _narration_write {l:agz}{n:nat}{at:nat} (record: !$A.arr(byte, l, n), n: int n, at: int at): void =
  if at + 3 > n then ()
  else let
    val () = $A.write_byte(record, at, 78)
    val () = $A.write_byte(record, at + 1, set_narration_speed_get())
  in $A.write_byte(record, at + 2, _notes_code(!_narration_notes)) end

(* The narration's bytes after "N" at record[at]: checked here, once; the
   defaults when there are none (a record written before them) *)
fn _narration_read {l:agz}{n:nat}{at:nat} (record: !$A.arr(byte, l, n), n: int n, at: int at): void =
  if at + 3 > n then let
    val () = !_narration_speed := 4
  in !_narration_notes := NotesSkipped() end
  else if byte2int0($A.get<byte>(record, at)) <> 78 then let
    val () = !_narration_speed := 4
  in !_narration_notes := NotesSkipped() end
  else let
    val speed = byte2int0($A.get<byte>(record, at + 1))
    val () = !_narration_speed := (if speed < 2 then 4 else if speed > 8 then 4 else speed)
  in !_narration_notes := _notes_of_code(byte2int0($A.get<byte>(record, at + 2))) end

(* "F" and full screen's byte at record[at, at + 2) *)
fn _fullscreen_write {l:agz}{n:nat}{at:nat} (record: !$A.arr(byte, l, n), n: int n, at: int at): void =
  if at + 2 > n then ()
  else let
    val () = $A.write_byte(record, at, 70)
  in $A.write_byte(record, at + 1, _fullscreen_code(!_fullscreen)) end

(* Full screen's byte after "F" at record[at]: checked here, once; off
   when there is none (a record written before it) *)
fn _fullscreen_read {l:agz}{n:nat}{at:nat} (record: !$A.arr(byte, l, n), n: int n, at: int at): void =
  if at + 2 > n then !_fullscreen := FullscreenOff()
  else if byte2int0($A.get<byte>(record, at)) <> 70 then !_fullscreen := FullscreenOff()
  else !_fullscreen := _fullscreen_of_code(byte2int0($A.get<byte>(record, at + 1)))

(* ============================================================
   Applying
   ============================================================ *)

(* text's bytes from i on at buf[position + i, position + text_len) *)
fun _put_from {l:agz}{n:pos}{text_len:nat}{position:nat | position + text_len <= n}{i:nat | i <= text_len}
  .<text_len - i>.
  (buf: !$A.arr(byte, l, n), position: int position, text: string text_len, text_len: int text_len, i: int i)
  : int(position + text_len) =
  if i >= text_len then position + text_len
  else let
    val () = $A.set<byte>(buf, position + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_from(buf, position, text, text_len, i + 1) end

(* text's bytes at buf[position, position + |text|) *)
fn _put_text {l:agz}{n:pos}{text_len:nat}{position:nat | position + text_len <= n}
  (buf: !$A.arr(byte, l, n), position: int position, text: string text_len): int(position + text_len) =
  _put_from(buf, position, text, g1u2i(string1_length(text)), 0)

fn _margin_px (margin: set_margin): [px:nat | px <= 64] int px =
  if margin = 0 then 8 else if margin = 1 then 16 else if margin = 2 then 24 else if margin = 3 then 40 else 64

fn _put_font {l:agz}{position:nat | position + 34 <= 1024}
  (buf: !$A.arr(byte, l, 1024), position: int position, font: set_font)
  : [stop:nat | stop <= position + 34] int stop =
  case+ font of
  | Literata() => _put_text(buf, position, "Literata,Georgia,serif")
  | Inter() => _put_text(buf, position, "Inter,system-ui,sans-serif")
  | Atkinson() => _put_text(buf, position, "'Atkinson Hyperlegible',sans-serif")
  | BookFont() => _put_text(buf, position, "var(--bookfont,Georgia),serif")

(* tenths as a decimal at buf[position, stop): 16 -> "1.6" *)
fn _put_tenths {l:agz}{n:pos}{position:nat | position + 23 <= n}{tenths:nat}
  (buf: !$A.arr(byte, l, n), position: int position, n: int n, tenths: int tenths)
  : [stop:nat | stop <= position + 23] int stop = let
  val next = $S.int_to_str(buf, position, n, tenths / 10)
  val next = _put_text(buf, next, ".")
in $S.int_to_str(buf, next, n, $AR.band_g1($AR.low_byte(tenths - (tenths / 10) * 10), 15)) end

(* hundredths (under 100) as a decimal at buf[position, stop): 5 -> "0.05" *)
fn _put_hundredths {l:agz}{n:pos}{position:nat | position + 15 <= n}{hundredths:nat | hundredths < 100}
  (buf: !$A.arr(byte, l, n), position: int position, n: int n, hundredths: int hundredths)
  : [stop:nat | stop <= position + 15] int stop = let
  val next = _put_text(buf, position, "0.")
  val next = (if hundredths < 10 then _put_text(buf, next, "0") else next)
    : [padded:nat | padded <= position + 3] int padded
in $S.int_to_str(buf, next, n, hundredths) end

fn _put_align {l:agz}{position:nat | position + 7 <= 1024}
  (buf: !$A.arr(byte, l, 1024), position: int position, align: set_align)
  : [stop:nat | stop <= position + 7] int stop =
  case+ align of Justified() => _put_text(buf, position, "justify") | Ragged() => _put_text(buf, position, "start")

fn _put_hyphens {l:agz}{position:nat | position + 6 <= 1024}
  (buf: !$A.arr(byte, l, 1024), position: int position, hyphens: set_hyph)
  : [stop:nat | stop <= position + 6] int stop =
  case+ hyphens of Hyphenated() => _put_text(buf, position, "auto") | NoHyphens() => _put_text(buf, position, "manual")

fn _put_dim_images {l:agz}{position:nat | position + 80 <= 1024}
  (buf: !$A.arr(byte, l, 1024), position: int position, dim_images: set_dim)
  : [stop:nat | stop <= position + 80] int stop =
  case+ dim_images of
  | ImagesDimmed() =>
    _put_text(buf, position, ".th-dark .caf img,.th-night .caf img,.th-grey .caf img{filter:brightness(.8)}")
  | ImagesAsTheyAre() => position

(* A spread: two columns a screen (each still at most 38rem wide, as
   .caf>* makes it), and the probe (spread-probe) shown, which is how
   the reader knows. A column is at least 40vw, and the browser widens
   it to fill the page: the page is the window's width less its safe
   area's sides (style.bats), so two of 50vw would not fit beside a
   cutout, and two of 40vw fit while the sides take under a fifth of
   it; three never fit (#275) *)
fn _put_columns {l:agz}{position:nat | position + 120 <= 1024}
  (buf: !$A.arr(byte, l, 1024), position: int position, columns: set_cols)
  : [stop:nat | stop <= position + 120] int stop =
  case+ columns of
  | TwoColumns() => _put_text(buf, position, ".caf{column-width:40vw}.sprobe{display:block}")
  | OneColumn() => position
  (* auto: as Apple Books does on an iPad turned on its side, and with
     room for two lines of about 30em (Readium's auto column count) *)
  | AutoColumns() => _put_text(buf, position,
    "@media (orientation:landscape) and (min-width:60em){.caf{column-width:40vw}.sprobe{display:block}}")

(* Scrolled: the chapter down the page, not in columns across. The page
   is then the reading area itself (#296): its margins, not its
   paddings, are the reading area's (style.bats, .rv), so the text
   scrolls only inside it, clipped below the status bar and above the
   footer, and never drawn under either. The bands the margins leave
   are the page's own (two transparent bands, fixed over them), so a
   tap or a drag there is still the page's. A vertical book and a fixed
   page are never scrolled, and keep their own boxes *)
fn _put_scrolled {l:agz}{position:nat | position + 440 <= 1024}
  (buf: !$A.arr(byte, l, 1024), position: int position, scrolled: set_flow)
  : [stop:nat | stop <= position + 440] int stop =
  case+ scrolled of
  | Scrolled() => _put_text(buf, position,
    ".caf{overflow:hidden auto;column-width:auto}.sprobe{display:none}.caf:not(.vertical,.vertical-lr,.fixed){padding-block:0;margin-block:var(--page-top) var(--page-bottom)}.caf:not(.vertical,.vertical-lr,.fixed)::before,.caf:not(.vertical,.vertical-lr,.fixed)::after{content:'';position:fixed;left:0;right:0;top:0;height:var(--page-top)}.caf:not(.vertical,.vertical-lr,.fixed)::after{top:auto;bottom:0;height:var(--page-bottom)}")
  | Paged() => position

(* A ruby's annotations hidden: its rt and rtc (an rp is not shown
   where ruby is, by the browser's own sheet). Layout, not colour *)
fn _put_ruby {l:agz}{position:nat | position + 30 <= 1024}
  (buf: !$A.arr(byte, l, 1024), position: int position, ruby: set_ruby)
  : [stop:nat | stop <= position + 30] int stop =
  case+ ruby of
  | RubyHidden() => _put_text(buf, position, ".caf rt,.caf rtc{display:none}")
  | RubyShown() => position

(* The reader's typography as CSS, in style element style-type *)
fn _apply_type (): void = let
  val current = !_set
  val ruby = set_ruby_get()
  val buf = $A.alloc<byte>(1024)
  val next = _put_text(buf, 0, ".caf{font-size:")
  val next = $S.int_to_str(buf, next, 1024, current.size)
  val next = _put_text(buf, next, "px;line-height:")
  val next = _put_tenths(buf, next, 1024, current.line_height)
  val next = _put_text(buf, next, ";font-family:")
  val next = _put_font(buf, next, current.font)
  val next = _put_text(buf, next, ";letter-spacing:")
  val next = _put_hundredths(buf, next, 1024, current.letter_spacing)
  val next = _put_text(buf, next, "em;word-spacing:")
  val next = _put_hundredths(buf, next, 1024, current.word_spacing)
  val next = _put_text(buf, next, "em}.caf>*{padding-left:")
  val next = $S.int_to_str(buf, next, 1024, _margin_px(current.margin))
  val next = _put_text(buf, next, "px;padding-right:")
  val next = $S.int_to_str(buf, next, 1024, _margin_px(current.margin))
  val next = _put_text(buf, next, "px}.caf p{text-align:")
  val next = _put_align(buf, next, current.align)
  val next = _put_text(buf, next, ";hyphens:")
  val next = _put_hyphens(buf, next, current.hyphens)
  (* logical, so in vertical text it is the space beside a paragraph *)
  val next = _put_text(buf, next, ";margin-block-end:")
  val next = _put_tenths(buf, next, 1024, current.paragraph_spacing)
  val next = _put_text(buf, next, "em}")
  (* a bright picture glares on the dark theme's ground *)
  val next = _put_dim_images(buf, next, current.dim_images)
  (* paged, one column a screen or two *)
  val next = _put_columns(buf, next, current.columns)
  (* scrolled: the chapter down the page, not in columns across *)
  val next = _put_scrolled(buf, next, current.scrolled)
  (* a ruby's annotations, shown or hidden *)
  val next = _put_ruby(buf, next, ruby)
in ui_text_buf("style-type", buf, next) end

(* Whether it is night by the local clock (22:00 to 07:00, iOS Night
   Shift's default schedule), from the host's clock and time zone *)
fn _night (): bool = local_night()

(* The theme shown now: auto is Night at night (reading a bright screen
   at bedtime delays sleep: Chang et al., PNAS 2015), else Dark when the
   system asks for dark, else Light *)
val _shown_theme = ref<theme>(Light())

(* The theme auto shows now *)
fn _auto_theme (): theme = if _night() then Night() else if !_system_dark then Dark() else Light()

(* The theme shown: the root's class *)
fn _apply_theme (): void = let
  val choice = set_theme_get()
  val shown = (case+ choice of ~Auto() => _auto_theme() | ~Fixed(t) => t): theme
  val () = !_shown_theme := shown
in
  case+ shown of
  | Grey() => ui_attr("bats-root", AClass, "app th-grey")
  | Night() => ui_attr("bats-root", AClass, "app th-night")
  | Dark() => ui_attr("bats-root", AClass, "app th-dark")
  | Sepia() => ui_attr("bats-root", AClass, "app th-sepia")
  | Light() => ui_attr("bats-root", AClass, "app th-light")
end

(* Auto, the theme again, when the clock has passed into the night or
   out of it (at a page turn) *)
#pub fn set_theme_recheck (): void
implement set_theme_recheck () =
  case+ set_theme_get() of
  | ~Fixed(_) => ()
  | ~Auto() => if theme_palette(_auto_theme()) = theme_palette(!_shown_theme) then () else _apply_theme()

fn _pressed {id_len:pos | id_len < 256} (id: string id_len, on: bool): void =
  if on then ui_attr(id, APressed, "true") else ui_attr(id, APressed, "false")

(* The narration's speed, as its slider shows it: 0.5 to 2, each with a
   multiplication sign *)
fn _narration_speed_text (): void = let
  val speed = set_narration_speed_get()
in
  if speed <= 2 then ui_text("narration-speed-value", "0.5\xC3\x97")
  else if speed = 3 then ui_text("narration-speed-value", "0.75\xC3\x97")
  else if speed = 4 then ui_text("narration-speed-value", "1\xC3\x97")
  else if speed = 5 then ui_text("narration-speed-value", "1.25\xC3\x97")
  else if speed = 6 then ui_text("narration-speed-value", "1.5\xC3\x97")
  else if speed = 7 then ui_text("narration-speed-value", "1.75\xC3\x97")
  else ui_text("narration-speed-value", "2\xC3\x97")
end

(* The settings panel's controls, showing the settings *)
fn _show_controls (): void = let
  val current = !_set
  val buf = $A.alloc<byte>(32)
  val next = $S.int_to_str(buf, 0, 32, current.size)
  val () = ui_text_buf("size-value", buf, next)
  val buf = $A.alloc<byte>(32)
  val next = $S.int_to_str(buf, 0, 32, current.line_height / 10)
  val next = _put_text(buf, next, ".")
  val next = $S.int_to_str(buf, next, 32,
    $AR.band_g1($AR.low_byte(current.line_height - (current.line_height / 10) * 10), 15))
  val () = ui_text_buf("line-height-value", buf, next)
  val buf = $A.alloc<byte>(32)
  val next = $S.int_to_str(buf, 0, 32, current.margin + 1)
  val () = ui_text_buf("margins-value", buf, next)
  val font = font_code(current.font)
  val () = _pressed("font-literata", font = font_code(Literata()))
  val () = _pressed("font-inter", font = font_code(Inter()))
  val () = _pressed("font-book", font = font_code(BookFont()))
  val () = _pressed("font-atkinson", font = font_code(Atkinson()))
  val choice = set_theme_get()
  val theme = theme_choice_code(choice)
  val () = theme_choice_free(choice)
  val () = _pressed("theme-auto", _is_chosen(theme, Auto()))
  val () = _pressed("theme-light", _is_chosen(theme, Fixed(Light())))
  val () = _pressed("theme-sepia", _is_chosen(theme, Fixed(Sepia())))
  val () = _pressed("theme-dark", _is_chosen(theme, Fixed(Dark())))
  val () = _pressed("theme-night", _is_chosen(theme, Fixed(Night())))
  val () = _pressed("theme-grey", _is_chosen(theme, Fixed(Grey())))
  val () = _pressed("layout-pages", flow_code(current.scrolled) = flow_code(Paged()))
  val () = _pressed("layout-scroll", flow_code(current.scrolled) = flow_code(Scrolled()))
  val columns = cols_code(current.columns)
  val () = _pressed("columns-auto", columns = cols_code(AutoColumns()))
  val () = _pressed("columns-one", columns = cols_code(OneColumn()))
  val () = _pressed("columns-two", columns = cols_code(TwoColumns()))
  val () = _pressed("justify-switch", align_code(current.align) = align_code(Justified()))
  val () = _pressed("hyphenation-switch", hyph_code(current.hyphens) = hyph_code(Hyphenated()))
  val () = _pressed("dim-images-switch", dim_code(current.dim_images) = dim_code(ImagesDimmed()))
  val taps = taps_code(current.tap_zones)
  val () = _pressed("taps-sides", taps = taps_code(SideZones()))
  val () = _pressed("taps-forward", taps = taps_code(ForwardZones()))
  val () = _pressed("taps-one-hand", taps = taps_code(OneHandZones()))
  val () = _pressed("volume-keys-turn", vol_code(current.volume_keys) = vol_code(KeysTurnPages()))
  val () = _pressed("ruby-show", ruby_code(set_ruby_get()) = ruby_code(RubyShown()))
  val () = _pressed("ruby-hide", ruby_code(set_ruby_get()) = ruby_code(RubyHidden()))
  val () = (case+ set_narration_notes_get() of
    | NotesSkipped() => let val () = _pressed("narration-skip", true) in _pressed("narration-read", false) end
    | NotesRead() => let val () = _pressed("narration-skip", false) in _pressed("narration-read", true) end)
  val () = _narration_speed_text()
  val buf = $A.alloc<byte>(32)
  val next = _put_tenths(buf, 0, 32, current.paragraph_spacing)
  val () = ui_text_buf("paragraph-value", buf, next)
  val buf = $A.alloc<byte>(32)
  val next = _put_hundredths(buf, 0, 32, current.letter_spacing)
  val () = ui_text_buf("letter-value", buf, next)
  val buf = $A.alloc<byte>(32)
  val next = _put_hundredths(buf, 0, 32, current.word_spacing)
in ui_text_buf("word-value", buf, next) end

(* ============================================================
   Storage: key "set"
   ============================================================ *)

(* "S2", then size, line height, margin, font, theme, the library's
   sort order, align, hyphens, paragraph, letter and word spacing, dim
   images, tap zones, volume keys, readout, scrolled, columns and ruby,
   a byte each; then the device's own: reading aloud's speed, the
   brightness and the rotation lock, a byte each, and the voices kept
   (their count, then each one's code and name, each after its length),
   then "N" (78) and a book narration's speed and skipping, a byte each,
   then "F" (70) and full screen's byte.
   ("S1" was the first 8; a record of "S2" without the last bytes has
   their defaults.) *)
fn _save (sort: int): void = let
  val current = !_set
  val voices = _voices_take()
  val+ @VoicesCell(choices, voice_count) = voices
  val voices_size = _voices_size(choices)
  val record_size = 24 + voices_size + 3 + 2
  val record = $A.alloc<byte>(record_size)
  val () = _voices_write(choices, record, record_size, 24)
  val () = $A.write_byte(record, 23, voice_count)
  val () = _narration_write(record, record_size, 24 + voices_size)
  val () = _fullscreen_write(record, record_size, 24 + voices_size + 3)
  prval () = fold@(voices)
  val () = _voices_put(voices)
  val () = $A.write_byte(record, 20, _rate_code(!_speech_rate))
  val () = $A.write_byte(record, 21, _brightness_code(!_brightness))
  val () = $A.write_byte(record, 22, _rotation_code(!_rotation))
  val () = $A.write_byte(record, 0, 83)
  val () = $A.write_byte(record, 1, 50)
  val () = $A.write_byte(record, 2, current.size)
  val () = $A.write_byte(record, 3, current.line_height)
  val () = $A.write_byte(record, 4, current.margin)
  val () = $A.write_byte(record, 5, font_code(current.font))
  val choice = set_theme_get()
  val () = $A.write_byte(record, 6, theme_choice_code(choice))
  val () = theme_choice_free(choice)
  val () = $A.write_byte(record, 7, $AR.low_byte(sort))
  val () = $A.write_byte(record, 8, align_code(current.align))
  val () = $A.write_byte(record, 9, hyph_code(current.hyphens))
  val () = $A.write_byte(record, 10, current.paragraph_spacing)
  val () = $A.write_byte(record, 11, current.letter_spacing)
  val () = $A.write_byte(record, 12, current.word_spacing)
  val () = $A.write_byte(record, 13, dim_code(current.dim_images))
  val () = $A.write_byte(record, 14, taps_code(current.tap_zones))
  val () = $A.write_byte(record, 15, vol_code(current.volume_keys))
  val () = $A.write_byte(record, 16, rd_code(current.readout))
  val () = $A.write_byte(record, 17, flow_code(current.scrolled))
  val () = $A.write_byte(record, 18, cols_code(current.columns))
  val () = $A.write_byte(record, 19, ruby_code(set_ruby_get()))
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("set"), 3)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  (* never over settings that could not be read (#174) *)
  val () = (if storage_savable(SettingsRecord()) then save_checked($IDB.idb_put(key_bytes, 3, record_bytes, record_size)) else ())
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* The panel's sliders, made again at the settings' values (after they
   are loaded, reset or restored; not while one is being moved) *)
#pub fn set_sliders (): void

implement set_sliders () = let
  val current = !_set
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, current.size)
  val () = ui_range("size-row", "size-label", "Size", "size-range", "12", "32", "size-value", value_text, value_len)
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, current.line_height)
  val () = ui_range("line-height-row", "line-height-label", "Line spacing", "line-height-range", "12", "24",
    "line-height-value", value_text, value_len)
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, current.margin)
  val () = ui_range("margins-row", "margins-label", "Margins", "margins-range", "0", "4", "margins-value",
    value_text, value_len)
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, current.paragraph_spacing)
  val () = ui_range("paragraph-row", "paragraph-label", "Paragraph spacing", "paragraph-range", "0", "20",
    "paragraph-value", value_text, value_len)
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, current.letter_spacing)
  val () = ui_range("letter-row", "letter-label", "Letter spacing", "letter-range", "0", "12", "letter-value",
    value_text, value_len)
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, current.word_spacing)
  val () = ui_range("word-row", "word-label", "Word spacing", "word-range", "0", "16", "word-value",
    value_text, value_len)
  (* the narration's speed, in quarters *)
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, set_narration_speed_get())
  val () = ui_range("narration-speed-row", "narration-speed-label", "Narration speed", "narration-speed-range", "2", "8",
    "narration-speed-value", value_text, value_len)
in _show_controls() end

(* Applies the settings (and shows them in the panel), then saves them
   with the library's sort order *)
#pub fn set_apply (sort: int): void

implement set_apply (sort) = let
  val () = _apply_type()
  val () = _apply_theme()
  val () = _show_controls()
in _save(sort) end

(* Saves the settings, with the library's sort order, as they are: for
   one that changes nothing on the page (the footer's readout) *)
#pub fn set_save (sort: int): void
implement set_save (sort) = _save(sort)

(* Applies the settings without saving them *)
#pub fn set_show (): void

implement set_show () = let
  val () = _apply_type()
  val () = _apply_theme()
in set_sliders() end

#pub fn set_size_set (value: set_size): void
implement set_size_set (value) = let
  val current = !_set
in !_set := @{
  size = value, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_lh_set (value: set_lh): void
implement set_lh_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = value, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_margin_set (value: set_margin): void
implement set_margin_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = value, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_font_set (value: set_font): void
implement set_font_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = value,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_align_set (value: set_align): void
implement set_align_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = value, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_hyph_set (value: set_hyph): void
implement set_hyph_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = value, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_ps_set (value: set_ps): void
implement set_ps_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = value,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_ls_set (value: set_ls): void
implement set_ls_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = value, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_ws_set (value: set_ws): void
implement set_ws_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = value,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_dim_set (value: set_dim): void
implement set_dim_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = value, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_taps_set (value: set_taps): void
implement set_taps_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = value, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_vol_set (value: set_vol): void
implement set_vol_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = value,
  readout = current.readout, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_rd_set (value: set_rd): void
implement set_rd_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = value, scrolled = current.scrolled, columns = current.columns } end
#pub fn set_flow_set (value: set_flow): void
implement set_flow_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = value, columns = current.columns } end
#pub fn set_ruby_set (value: set_ruby): void
implement set_ruby_set (value) = !_ruby := value
#pub fn set_narration_speed_set (value: set_narration_speed): void
implement set_narration_speed_set (value) = !_narration_speed := value
#pub fn set_narration_notes_set (notes: narration_notes): void
implement set_narration_notes_set (notes) = !_narration_notes := notes
#pub fn set_cols_set (value: set_cols): void
implement set_cols_set (value) = let
  val current = !_set
in !_set := @{
  size = current.size, line_height = current.line_height, margin = current.margin, font = current.font,
  align = current.align, hyphens = current.hyphens, paragraph_spacing = current.paragraph_spacing,
  letter_spacing = current.letter_spacing, word_spacing = current.word_spacing,
  dim_images = current.dim_images, tap_zones = current.tap_zones, volume_keys = current.volume_keys,
  readout = current.readout, scrolled = current.scrolled, columns = value } end

(* The voices a reset put aside, for its Undo to put back *)
val _voices_reset = ref<voices_cell>(VoicesCell(VoiceChoicesEnd(), 0))

(* The defaults. Private: the settings go back to them only by
   set_reset, which offers the ones they replace back. The voices kept
   are put aside (_voices_reset), for its Undo *)
fn _reset (): void = let
  val () = !_set := _defaults()
  val () = !_ruby := RubyShown()
  val () = set_theme_set(Auto())
  val () = !_speech_rate := RateNormal()
  val () = !_brightness := BrightnessSystem()
  val () = !_rotation := RotationFree()
  val () = !_fullscreen := FullscreenOff()
  val () = !_narration_speed := 4
  val () = !_narration_notes := NotesSkipped()
  var aside: voices_cell = _voices_take()
  val () = ref_exch_elt<voices_cell>(_voices_reset, aside)
  val+ ~VoicesCell(older, _) = aside
in _voice_choices_free(older) end

(* Puts the defaults back at once. how is the Undo offer made for it:
   when it settles Undone, the settings the defaults replaced are put
   back. The promise resolves with how once that is done (the caller
   applies the settings now, and again when they are put back) *)
#pub fn set_reset_undoable {state:$P.promise_state} (how: $P.promise(settled, state)): $P.promise(settled, $P.Chained)
implement set_reset_undoable (how) = let
  val before = !_set
  val ruby_before = !_ruby
  val theme_before = set_theme_get()
  val rate_before = !_speech_rate
  val brightness_before = !_brightness
  val rotation_before = !_rotation
  val fullscreen_before = !_fullscreen
  val speed_before = !_narration_speed
  val notes_before = !_narration_notes
  val () = _reset()
in
  $P.and_then<settled><settled>(how, llam(settling) =>
    case+ settling of
    | Undone() => let
        val () = !_set := before
        val () = !_ruby := ruby_before
        val () = set_theme_set(theme_before)
        val () = !_speech_rate := rate_before
        val () = !_brightness := brightness_before
        val () = !_rotation := rotation_before
        val () = !_fullscreen := fullscreen_before
        val () = !_narration_speed := speed_before
        val () = !_narration_notes := notes_before
        var aside: voices_cell = VoicesCell(VoiceChoicesEnd(), 0)
        val () = ref_exch_elt<voices_cell>(_voices_reset, aside)
        val () = _voices_put(aside)
      in $P.ret<settled>(Undone()) end
    | Final() => let
        var aside: voices_cell = VoicesCell(VoiceChoicesEnd(), 0)
        val () = ref_exch_elt<voices_cell>(_voices_reset, aside)
        val+ ~VoicesCell(older, _) = aside
        val () = _voice_choices_free(older)
        val () = theme_choice_free(theme_before)
      in $P.ret<settled>(Final()) end)
end

(* The same, offering Undo *)
#pub fn set_reset (): $P.promise(settled, $P.Chained)
implement set_reset () = set_reset_undoable(undo_offer(SettingsReset()))

(* A byte stored by an earlier run, as a value in [low, high]: checked
   here, once; fallback when it is out of range *)
fn _in_range {low,high,fallback:int | low <= fallback; fallback <= high}
  (stored: [any:int] int any, low: int low, high: int high, fallback: int fallback)
  : [kept:int | low <= kept; kept <= high] int kept =
  if stored < low then fallback else if stored > high then fallback else stored

(* Reads the settings stored under "set" and applies them (without
   saving); the promise resolves with the sort order stored with them *)
(* Whether a media query matches *)
fn _matches (answer: $MEDIA.media_match): bool =
  case+ answer of
  | $MEDIA.Matches() => true
  | $MEDIA.NoMatch() => false

#pub fn set_load (): $P.promise(int, $P.Chained)

implement set_load () = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_byte(key, 0, 115)
  val () = $A.write_byte(key, 1, 101)
  val () = $A.write_byte(key, 2, 116)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val pending = $IDB.idb_get(key_bytes, 3)
  val () = release_bytes(key_frozen, key_bytes)
  (* The system's dark mode, for the auto theme, and its changes *)
  val media_query = $A.alloc<byte>(30)
  val () = $A.write_text(media_query, 0, $A.text_lit("(prefers-color-scheme: dark)"), 28)
  val @(query_frozen, query_bytes) = $A.freeze<byte>(media_query)
  val @(query_text, query_rest) = $A.borrow_split<byte>(query_frozen, query_bytes, 28)
  val () = !_system_dark := _matches($MEDIA.match_media(query_text, 28))
  val () = $MEDIA.listen_media(query_text, 28, ui_media_listener(), llam(matches) => let
      val () = !_system_dark := _matches(matches)
      val () = _apply_theme()
    in 0 end)
  val query_bytes = $A.borrow_join<byte>(query_frozen, query_text, query_rest)
  val () = release_bytes(query_frozen, query_bytes)
in
  $P.and_then<$IDB.lookup><int>(pending, llam(found) =>
    case+ lookup_bytes(found) of
    | ~NothingStored() => let val () = set_show() in $P.ret<int>(0) end
    (* the defaults this session, and the settings stored are kept *)
    | ~StoredUnreadable() => let
        val () = storage_unreadable(SettingsRecord())
        val () = set_show()
      in $P.ret<int>(0) end
    | ~StoredBytes(record, n) =>
      if n < 8 then let
        val () = $A.free<byte>(record)
        val () = set_show()
      in $P.ret<int>(0) end
      else let
        val size = _in_range($AR.low_byte(byte2int0($A.get<byte>(record, 2))), 12, 32, 18)
        val line_height = _in_range($AR.low_byte(byte2int0($A.get<byte>(record, 3))), 12, 24, 16)
        val margin = _in_range($AR.low_byte(byte2int0($A.get<byte>(record, 4))), 0, 4, 2)
        val font = font_of_code(byte2int0($A.get<byte>(record, 5)))
        val () = set_theme_set(theme_choice_of_code(byte2int0($A.get<byte>(record, 6))))
        (* the library's view: its sort order, grid and filter (lib_state_get) *)
        val sort = _in_range($AR.low_byte(byte2int0($A.get<byte>(record, 7))), 0, 63, 0)
        (* "S2" has the rest; "S1" had none, and they are the defaults *)
        val second_version = (if n >= 13 then byte2int0($A.get<byte>(record, 1)) = 50 else false): bool
        val align = (if n >= 13 then (if second_version then
          align_of_code(byte2int0($A.get<byte>(record, 8))) else Ragged()) else Ragged()): set_align
        val hyphens = (if n >= 13 then (if second_version then
          hyph_of_code(byte2int0($A.get<byte>(record, 9))) else Hyphenated()) else Hyphenated()): set_hyph
        val paragraph_spacing = (if n >= 13 then (if second_version then
          _in_range($AR.low_byte(byte2int0($A.get<byte>(record, 10))), 0, 20, 8) else 8) else 8): set_ps
        val letter_spacing = (if n >= 13 then (if second_version then
          _in_range($AR.low_byte(byte2int0($A.get<byte>(record, 11))), 0, 12, 0) else 0) else 0): set_ls
        val word_spacing = (if n >= 13 then (if second_version then
          _in_range($AR.low_byte(byte2int0($A.get<byte>(record, 12))), 0, 16, 0) else 0) else 0): set_ws
        val dim_images = (if n >= 14 then (if second_version then
          dim_of_code(byte2int0($A.get<byte>(record, 13))) else ImagesDimmed()) else ImagesDimmed()): set_dim
        val tap_zones = (if n >= 15 then (if second_version then
          taps_of_code(byte2int0($A.get<byte>(record, 14))) else SideZones()) else SideZones()): set_taps
        val volume_keys = (if n >= 16 then (if second_version then
          vol_of_code(byte2int0($A.get<byte>(record, 15))) else KeysForVolume()) else KeysForVolume()): set_vol
        val readout = (if n >= 17 then (if second_version then
          rd_of_code(byte2int0($A.get<byte>(record, 16))) else PagesLeft()) else PagesLeft()): set_rd
        val scrolled = (if n >= 18 then (if second_version then
          flow_of_code(byte2int0($A.get<byte>(record, 17))) else Paged()) else Paged()): set_flow
        val columns = (if n >= 19 then (if second_version then
          cols_of_code(byte2int0($A.get<byte>(record, 18))) else AutoColumns()) else AutoColumns()): set_cols
        val ruby = (if n >= 20 then (if second_version then
          ruby_of_code(byte2int0($A.get<byte>(record, 19))) else RubyShown()) else RubyShown()): set_ruby
        (* the device's own, after the settings *)
        val () = !_speech_rate := (if n >= 21 then (if second_version then
          _rate_of_code(byte2int0($A.get<byte>(record, 20))) else RateNormal()) else RateNormal())
        val () = !_brightness := (if n >= 22 then (if second_version then
          _brightness_of_code(byte2int0($A.get<byte>(record, 21))) else BrightnessSystem()) else BrightnessSystem())
        val () = !_rotation := (if n >= 23 then (if second_version then
          _rotation_of_code(byte2int0($A.get<byte>(record, 22))) else RotationFree()) else RotationFree())
        val stored_voices = (if n >= 24 then (if second_version then byte2int0($A.get<byte>(record, 23)) else 0) else 0): int
        val @(voices_read, voices_read_count) = _voices_read(record, n, 24, stored_voices, VoiceChoicesEnd(), 0)
        val voices_end = 24 + _voices_size(voices_read)
        val () = _narration_read(record, n, voices_end)
        val () = _fullscreen_read(record, n, voices_end + 3)
        val () = _voices_put(VoicesCell(voices_read, voices_read_count))
        val () = $A.free<byte>(record)
        val () = !_set := @{ size = size, line_height = line_height, margin = margin, font = font,
          align = align, hyphens = hyphens, paragraph_spacing = paragraph_spacing, letter_spacing = letter_spacing,
          word_spacing = word_spacing, dim_images = dim_images, tap_zones = tap_zones, volume_keys = volume_keys,
          readout = readout, scrolled = scrolled, columns = columns }
        val () = !_ruby := ruby
        val () = set_show()
      in $P.ret<int>(sort) end)
end

end (* #target wasm *)
