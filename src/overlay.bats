(* overlay -- an EPUB 3 Media Overlay (a SMIL document) as the clips it
   plays, in reading order: the format alone *)

(* A Media Overlay (EPUB 3.3 §9) is a SMIL document: a body of seq and
   par elements, each par a text element (src: the chapter and the id of
   the element it reads) and an audio element (src: the audio file, with
   clipBegin and clipEnd, clock values of EPUB 3.3 H.4). A seq or par
   may have an epub:type: footnote, endnote and pagebreak are
   skippable (a reader may pass them over), table, list, figure and
   aside escapable (a reader may leave them for what comes after).
   Everything here reads bytes a book holds, so each is checked as it is
   read.

   The clips are kept in a table of CLIP_BYTES bytes a clip, at most
   CLIP_MAX of them (1 MiB), the one piece of an arena of its own:
     0  begin, in ms
     4  end, in ms; -1 for the end of the audio
     8  while parsed, where the audio's src is in the SMIL; then where its
        entry's data is in the book's file
     12 while parsed, the src's length; then its entry's data's size (0:
        no entry)
     16 while parsed, where the text's fragment is in the SMIL; once the
        chapter is rendered, the first content node the clip reads, or -1
     20 while parsed, the fragment's length; then the content node after
        the last it reads
     24 the clip after the innermost escapable structure it is in, or -1
     28 flags: 1 skippable, 2 matched to content nodes, 4 its audio is
        deflated
     29 the escapable structure: 1 table, 2 list, 3 figure, 4 aside, 0
        none
     30 the audio's type (1 MP3, 2 MP4, 3 Ogg, 4 WAV, 0 other) *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use xml-tree as X
#use zip as Z
#use result as R

staload "epub_xml.sats"
staload "paths.sats"

(* The most clips a chapter's table holds *)
#pub stadef CLIP_MAX = 32768

#define FIELD_BEGIN 0
#define FIELD_END 4
#define FIELD_AUDIO_OFFSET 8
#define FIELD_AUDIO_SIZE 12
#define FIELD_FIRST_NODE 16
#define FIELD_END_NODE 20
#define FIELD_ESCAPE_TO 24
#define FIELD_FLAGS 28
#define FIELD_ESCAPE_KIND 29
#define FIELD_AUDIO_KIND 30

#define FLAG_SKIPPABLE 1
#define FLAG_MATCHED 2
#define FLAG_DEFLATED 4

(* count clips, CLIP_BYTES (32) bytes each: the one piece of an arena of
   their own *)
#pub datavtype clip_table(count:int) =
  | {arena_loc,table_loc:agz}
    ClipTable(count) of ($A.arena(byte, arena_loc, 32 * count, 32 * count, 1), $A.arrx(byte, table_loc, 32 * count, arena_loc))

#pub datavtype clip_table_made(count:int) =
  | ClipTableMade(count) of (clip_table(count))
  | ClipTableNone(count) of ()

(* A table of count clips, all zero bytes; none when its memory cannot be
   had *)
#pub fn clip_table_new {count:pos | count <= CLIP_MAX} (count: int count): clip_table_made(count)

implement clip_table_new (count) =
  case+ $A.arena_create<byte>(32 * count) of
  | ~$A.arena_none() => ClipTableNone()
  | ~$A.arena_some(arena) => let
      val bytes = $A.arena_alloc<byte>(arena, 32 * count)
    in ClipTableMade(ClipTable(arena, bytes)) end

#pub fn clip_table_free {count:nat} (table: clip_table(count)): void

implement clip_table_free (table) = let
  val+ ~ClipTable(arena, bytes) = table
  val () = $A.arena_return<byte>(arena, bytes)
in $A.arena_destroy<byte>(arena) end

(* ============================================================
   The table's fields
   ============================================================ *)

fn _byte_at {l:agz}{o:addr}{n:nat}{i:nat | i < n} (bytes: !$A.arrx(byte, l, n, o), i: int i): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))

(* The little-endian 32-bit word at field of clip *)
fn _word {count:pos}{clip:nat | clip < count}{field:nat | field + 4 <= 32}
  (table: !clip_table(count), clip: int clip, field: int field): Int = let
  val+ @ClipTable(_, bytes) = table
  val at = 32 * clip + field
  val byte0 = _byte_at(bytes, at)
  val byte1 = _byte_at(bytes, at + 1)
  val byte2 = _byte_at(bytes, at + 2)
  val byte3 = _byte_at(bytes, at + 3)
  prval () = fold@(table)
  val high = (if byte3 < 128 then byte3 else byte3 - 256): [signed:int | ~128 <= signed; signed < 128] int signed
in byte0 + byte1 * 256 + byte2 * 65536 + high * 16777216 end

fn _word_put {count:pos}{clip:nat | clip < count}{field:nat | field + 4 <= 32}
  (table: !clip_table(count), clip: int clip, field: int field, value: int): void = let
  val+ @ClipTable(_, bytes) = table
  val () = $A.write_i32(bytes, 32 * clip + field, value)
  prval () = fold@(table)
in end

fn _small {count:pos}{clip:nat | clip < count}{field:nat | field < 32}
  (table: !clip_table(count), clip: int clip, field: int field): [value:nat | value < 256] int value = let
  val+ @ClipTable(_, bytes) = table
  val value = _byte_at(bytes, 32 * clip + field)
  prval () = fold@(table)
in value end

fn _small_put {count:pos}{clip:nat | clip < count}{field:nat | field < 32}{value:nat | value < 256}
  (table: !clip_table(count), clip: int clip, field: int field, value: int value): void = let
  val+ @ClipTable(_, bytes) = table
  val () = $A.write_byte(bytes, 32 * clip + field, value)
  prval () = fold@(table)
in end

fn _flag {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip, flag: int): bool =
  $AR.band_int_int(_small(table, clip, FIELD_FLAGS), flag) <> 0

fn _flag_set {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip, flag: int): void =
  _small_put(table, clip, FIELD_FLAGS, $AR.low_byte($AR.bor_int_int(_small(table, clip, FIELD_FLAGS), flag)))

(* Where the clip starts in its audio, in ms *)
#pub fn clip_begin {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): Int
implement clip_begin (table, clip) = _word(table, clip, FIELD_BEGIN)

(* Where it ends, in ms; none when it plays to its audio's end *)
#pub fn clip_end {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): $R.option(Int)
implement clip_end (table, clip) = let
  val end_ms = _word(table, clip, FIELD_END)
in if end_ms < 0 then $R.none() else $R.some(end_ms) end

(* While parsed: where its audio's src is in the SMIL, and its length *)
#pub fn clip_src_offset {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): Int
implement clip_src_offset (table, clip) = _word(table, clip, FIELD_AUDIO_OFFSET)

#pub fn clip_src_len {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): Int
implement clip_src_len (table, clip) = _word(table, clip, FIELD_AUDIO_SIZE)

(* A clip's audio: its entry's data in the book's file (offset, size,
   how it is stored) and its type; or none, when its src names no entry
   of the book *)
#pub datavtype clip_audio =
  | ClipAudio of (int, int, $Z.compression, audio_type)
  | ClipSilent of ()

fn _audio_code (kind: audio_type): [code:nat | code <= 4] int code =
  case+ kind of
  | AudioMpeg() => 1 | AudioMp4() => 2 | AudioOgg() => 3 | AudioWav() => 4 | AudioOther() => 0

fn _audio_of_code (code: int): audio_type =
  if code = 1 then AudioMpeg() else if code = 2 then AudioMp4() else if code = 3 then AudioOgg()
  else if code = 4 then AudioWav() else AudioOther()

#pub fn clip_audio {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): clip_audio
implement clip_audio (table, clip) = let
  val data_size = _word(table, clip, FIELD_AUDIO_SIZE)
in
  if data_size <= 0 then ClipSilent()
  else ClipAudio(_word(table, clip, FIELD_AUDIO_OFFSET), data_size,
    (if _flag(table, clip, FLAG_DEFLATED) then $Z.Deflated() else $Z.Stored()),
    _audio_of_code(_small(table, clip, FIELD_AUDIO_KIND)))
end

(* Whether it has audio to play *)
#pub fn clip_sounds {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): bool
implement clip_sounds (table, clip) = _word(table, clip, FIELD_AUDIO_SIZE) > 0

(* Its audio's entry: data [data_offset, data_offset + data_size) of the
   file, stored as method says, of the type kind *)
#pub fn clip_audio_set {count:pos}{clip:nat | clip < count}
  (table: !clip_table(count), clip: int clip, data_offset: int, data_size: int, method: $Z.compression, kind: audio_type): void
implement clip_audio_set (table, clip, data_offset, data_size, method, kind) = let
  val () = _word_put(table, clip, FIELD_AUDIO_OFFSET, data_offset)
  val () = _word_put(table, clip, FIELD_AUDIO_SIZE, data_size)
  val () = _small_put(table, clip, FIELD_AUDIO_KIND, _audio_code(kind))
in case+ method of $Z.Deflated() => _flag_set(table, clip, FLAG_DEFLATED) | $Z.Stored() => () end

(* Its src names no entry of the book: it has no audio *)
#pub fn clip_audio_none {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): void
implement clip_audio_none (table, clip) = let
  val () = _word_put(table, clip, FIELD_AUDIO_OFFSET, 0)
in _word_put(table, clip, FIELD_AUDIO_SIZE, 0) end

(* While parsed: where its fragment (the id of the element it reads) is
   in the SMIL, and its length (0: none) *)
#pub fn clip_fragment_offset {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): Int
implement clip_fragment_offset (table, clip) = _word(table, clip, FIELD_FIRST_NODE)

#pub fn clip_fragment_len {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): Int
implement clip_fragment_len (table, clip) = _word(table, clip, FIELD_END_NODE)

(* Whether it is matched to the content nodes it reads (clip_nodes_set) *)
#pub fn clip_matched {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): bool
implement clip_matched (table, clip) = _flag(table, clip, FLAG_MATCHED)

(* The content nodes [first_node, end_node) it reads; none when it is
   matched to none *)
#pub fn clip_nodes {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): $R.option(@(int, int))
implement clip_nodes (table, clip) =
  if ~_flag(table, clip, FLAG_MATCHED) then $R.none()
  else let
    val first_node = _word(table, clip, FIELD_FIRST_NODE)
  in
    if first_node < 0 then $R.none()
    else $R.some(@(first_node, _word(table, clip, FIELD_END_NODE)))
  end

(* It reads content nodes [first_node, end_node): matched *)
#pub fn clip_nodes_set {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip, first_node: int, end_node: int): void
implement clip_nodes_set (table, clip, first_node, end_node) = let
  val () = _word_put(table, clip, FIELD_FIRST_NODE, first_node)
  val () = _word_put(table, clip, FIELD_END_NODE, end_node)
in _flag_set(table, clip, FLAG_MATCHED) end

(* It reads no content node the chapter has: its nodes are -1 *)
#pub fn clip_nodes_none {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): void
implement clip_nodes_none (table, clip) = let
  val () = _word_put(table, clip, FIELD_FIRST_NODE, ~1)
in _word_put(table, clip, FIELD_END_NODE, ~1) end

(* Whether it is in a skippable structure (a footnote, an endnote, a
   page break) *)
#pub fn clip_skippable {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): bool
implement clip_skippable (table, clip) = _flag(table, clip, FLAG_SKIPPABLE)

(* An escapable structure: a table, a list, a figure, an aside *)
#pub datatype escapable = InTable | InList | InFigure | InAside

(* The innermost escapable structure a clip is in, and the clip after
   it (count when that is the chapter's end); or none *)
#pub datavtype clip_escape =
  | EscapesTo of (escapable, int)
  | NotEscapable of ()

#pub fn clip_escape {count:pos}{clip:nat | clip < count} (table: !clip_table(count), clip: int clip): clip_escape
implement clip_escape (table, clip) = let
  val escape_to = _word(table, clip, FIELD_ESCAPE_TO)
  val kind = _small(table, clip, FIELD_ESCAPE_KIND)
in
  if escape_to < 0 then NotEscapable()
  else if kind = 1 then EscapesTo(InTable(), escape_to)
  else if kind = 2 then EscapesTo(InList(), escape_to)
  else if kind = 3 then EscapesTo(InFigure(), escape_to)
  else if kind = 4 then EscapesTo(InAside(), escape_to)
  else NotEscapable()
end

(* ============================================================
   Clock values (EPUB 3.3 H.4, SMIL 3.0's): "5:34:31.396",
   "09:58", "00:56.78", "76.2s", "7.75h", "13min", "2345ms", "12.3"
   (seconds when no metric is given)
   ============================================================ *)

#define MS_MAX 2147483647

(* The digit at data[at], or -1 *)
fn _digit {l:agz}{n:pos}{at:nat | at < n} (data: !$A.borrow(byte, l, n), at: int at): [digit:int | digit >= ~1; digit <= 9] int digit = let
  val code = $AR.low_byte(byte2int0($A.read<byte>(data, at)))
in if code >= 48 then (if code <= 57 then code - 48 else ~1) else ~1 end

fn _byte_is {l:agz}{n:pos}{at:nat | at < n} (data: !$A.borrow(byte, l, n), at: int at, code: int): bool =
  $AR.low_byte(byte2int0($A.read<byte>(data, at))) = code

(* The digits of data[at, stop): where they end, and their value; -1 for
   a value of 214748364 or more *)
fun _number {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, value: [value:nat | value < 214748364] int value)
  : @([end_at:nat | at <= end_at; end_at <= stop] int end_at, [result:int | result >= ~1] int result) =
  if at >= stop then @(at, value)
  else let
    val digit = _digit(data, at)
  in
    if digit < 0 then @(at, value)
    else if value >= 21474836 then @(stop, ~1)
    else _number(data, at + 1, stop, value * 10 + digit)
  end

(* A fraction's digits from at: its first three as thousandths (place is
   the next digit's worth: 100, 10, 1, then 0), and where its digits end *)
fun _fraction_digits {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, thousandths: int, place: int)
  : @([end_at:nat | at <= end_at; end_at <= stop] int end_at, int) =
  if at >= stop then @(at, thousandths)
  else let
    val digit = _digit(data, at)
  in
    if digit < 0 then @(at, thousandths)
    else _fraction_digits(data, at + 1, stop, thousandths + digit * place, place / 10)
  end

(* An optional fraction at data[at]: a '.' and its digits, as thousandths;
   where it ends *)
fn _fraction {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): @([end_at:nat | at <= end_at; end_at <= stop] int end_at, int) =
  if at >= stop then @(at, 0)
  else if _byte_is(data, at, 46) then let
    val @(end_at, thousandths) = _fraction_digits(data, at + 1, stop, 0, 100)
  in @(end_at, thousandths) end
  else @(at, 0)

(* a + b, or -1 when either is below 0 or the sum is over MS_MAX *)
fn _sum (a: int, b: int): int =
  if a < 0 then ~1 else if b < 0 then ~1 else if a > MS_MAX - b then ~1 else a + b

(* value units of unit_ms each, or -1 when that is over MS_MAX *)
fn _times (value: int, unit_ms: int): int =
  if value < 0 then ~1 else if unit_ms <= 0 then ~1
  else if value > MS_MAX / unit_ms then ~1 else value * unit_ms

(* Where white space ends from at *)
fun _space_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else if $AR.low_byte(byte2int0($A.read<byte>(data, at))) > 32 then at
  else _space_end(data, at + 1, stop)

(* Where data[start, stop) ends with its white space at the end left out *)
fun _trimmed_end {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n} .<stop - start>.
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): [end_at:nat | start <= end_at; end_at <= stop] int end_at =
  if stop <= start then stop
  else if $AR.low_byte(byte2int0($A.read<byte>(data, stop - 1))) > 32 then stop
  else _trimmed_end(data, start, stop - 1)

(* hours, minutes, seconds and thousandths of a second, in ms; -1 over
   MS_MAX *)
fn _clock_total (hours: int, minutes: int, seconds: int, thousandths: int): int =
  _sum(_sum(_sum(_times(hours, 3600000), _times(minutes, 60000)), _times(seconds, 1000)), thousandths)

(* A timecount's metric, data[at, stop): its ms, 1000 for none (seconds);
   0 when it is not one *)
fn _metric {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): int = let
  var hours = @[char][1]('h')
  var minutes = @[char][3]('m', 'i', 'n')
  var seconds = @[char][1]('s')
  var milliseconds = @[char][2]('m', 's')
  val metric_len = stop - at
in
  if metric_len = 0 then 1000
  else if xml_name_eq(data, at, metric_len, hours, 1) then 3600000
  else if xml_name_eq(data, at, metric_len, minutes, 3) then 60000
  else if xml_name_eq(data, at, metric_len, seconds, 1) then 1000
  else if xml_name_eq(data, at, metric_len, milliseconds, 2) then 1
  else 0
end

(* A timecount whose number, first, ends at data[at]: maybe a fraction,
   maybe a metric, to stop *)
fn _timecount {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, first: int): int = let
  val @(after_fraction, thousandths) = _fraction(data, at, stop)
  val unit_ms = _metric(data, after_fraction, stop)
in
  if unit_ms <= 0 then ~1
  else if unit_ms = 1 then first
  else _sum(_times(first, unit_ms), _times(thousandths, unit_ms / 1000))
end

(* A partial clock value, minutes (first) and seconds (second), whose
   seconds end at data[at]: maybe a fraction, to stop *)
fn _partial_clock {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, first: int, second: int): int = let
  val @(end_at, thousandths) = _fraction(data, at, stop)
in
  if end_at <> stop then ~1
  else if second >= 60 then ~1
  else _clock_total(0, first, second, thousandths)
end

(* The clock value data[offset, offset + value_len), in ms: -1 when it is
   not one, or is over 2^31 - 1 ms *)
fn clock_ms {l:agz}{n:pos}{offset,value_len:nat | offset + value_len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, value_len: int value_len): int = let
  val start = _space_end(data, offset, offset + value_len)
  val stop = _trimmed_end(data, start, offset + value_len)
  val @(after_first, first) = _number(data, start, stop, 0)
in
  if after_first <= start then ~1
  else if first < 0 then ~1
  else if after_first >= stop then _timecount(data, after_first, stop, first)
  else if ~_byte_is(data, after_first, 58) then _timecount(data, after_first, stop, first)
  else let
    val @(after_second, second) = _number(data, after_first + 1, stop, 0)
  in
    if after_second <= after_first + 1 then ~1
    else if second < 0 then ~1
    else if after_second >= stop then _partial_clock(data, after_second, stop, first, second)
    else if ~_byte_is(data, after_second, 58) then _partial_clock(data, after_second, stop, first, second)
    else let
      (* a full clock value: hours, minutes and seconds *)
      val @(after_third, third) = _number(data, after_second + 1, stop, 0)
    in
      if after_third <= after_second + 1 then ~1
      else if third < 0 then ~1
      else if second >= 60 then ~1
      else if third >= 60 then ~1
      else let
        val @(end_at, thousandths) = _fraction(data, after_third, stop)
      in if end_at <> stop then ~1 else _clock_total(first, second, third, thousandths) end
    end
  end
end

(* ============================================================
   The SMIL's structure
   ============================================================ *)

(* Whether data[offset, offset + span_len), words split by white space,
   has the word pattern, from at on *)
fun _word_from {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{pattern_len:pos}{at:nat | at <= span_len} .<span_len - at>.
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len,
   pattern: &(@[char][pattern_len]), pattern_len: int pattern_len, at: int at): bool =
  if at + pattern_len > span_len then false
  else let
    val starts = (if at <= 0 then true else $AR.low_byte(byte2int0($A.read<byte>(data, offset + at - 1))) <= 32): bool
    val ends = (if at + pattern_len >= span_len then true
      else $AR.low_byte(byte2int0($A.read<byte>(data, offset + at + pattern_len))) <= 32): bool
  in
    if (if starts then ends else false) then
      (if xml_name_eq(data, offset + at, pattern_len, pattern, pattern_len) then true
       else _word_from(data, offset, span_len, pattern, pattern_len, at + 1))
    else _word_from(data, offset, span_len, pattern, pattern_len, at + 1)
  end

fn _has_word {l:agz}{n:pos}{offset,span_len:nat | offset + span_len <= n}{pattern_len:pos}
  (data: !$A.borrow(byte, l, n), offset: int offset, span_len: int span_len,
   pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool =
  _word_from(data, offset, span_len, pattern, pattern_len, 0)

(* Whether an element's epub:type makes it skippable: a footnote, an
   endnote or a page break *)
fn _skippable_type {l:agz}{n:pos}{attr_count:nat}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count)): bool = let
  var type_chars = @[char][9]('e', 'p', 'u', 'b', ':', 't', 'y', 'p', 'e')
  var footnote = @[char][8]('f', 'o', 'o', 't', 'n', 'o', 't', 'e')
  var endnote = @[char][7]('e', 'n', 'd', 'n', 'o', 't', 'e')
  var pagebreak = @[char][9]('p', 'a', 'g', 'e', 'b', 'r', 'e', 'a', 'k')
in
  case+ find_attr(data, attrs, type_chars, 9) of
  | ~xspan_none() => false
  | ~xspan_at(offset, span_len) =>
    if _has_word(data, offset, span_len, footnote, 8) then true
    else if _has_word(data, offset, span_len, endnote, 7) then true
    else _has_word(data, offset, span_len, pagebreak, 9)
end

(* The escapable structure an element's epub:type makes it: 1 a table, 2
   a list, 3 a figure, 4 an aside, 0 none *)
fn _escape_type {l:agz}{n:pos}{attr_count:nat}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count)): [kind:nat | kind <= 4] int kind = let
  var type_chars = @[char][9]('e', 'p', 'u', 'b', ':', 't', 'y', 'p', 'e')
  var table_word = @[char][5]('t', 'a', 'b', 'l', 'e')
  var list_word = @[char][4]('l', 'i', 's', 't')
  var figure_word = @[char][6]('f', 'i', 'g', 'u', 'r', 'e')
  var aside_word = @[char][5]('a', 's', 'i', 'd', 'e')
in
  case+ find_attr(data, attrs, type_chars, 9) of
  | ~xspan_none() => 0
  | ~xspan_at(offset, span_len) =>
    if _has_word(data, offset, span_len, table_word, 5) then 1
    else if _has_word(data, offset, span_len, list_word, 4) then 2
    else if _has_word(data, offset, span_len, figure_word, 6) then 3
    else if _has_word(data, offset, span_len, aside_word, 5) then 4
    else 0
end

(* A par's audio: its src's path [src_offset, src_offset + path_len), and
   its clip's begin and end in ms (-1: the audio's end); valid when it
   has a src and its clock values are good, and it ends after it begins *)
typedef par_audio = @(bool, int, int, Nat, Nat)

fn _clip_times {l:agz}{n:pos}{attr_count:nat}
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, attr_count)): @(bool, int, int) = let
  var begin_chars = @[char][9]('c', 'l', 'i', 'p', 'B', 'e', 'g', 'i', 'n')
  var end_chars = @[char][7]('c', 'l', 'i', 'p', 'E', 'n', 'd')
  val begin_ms = (case+ find_attr(data, attrs, begin_chars, 9) of
    | ~xspan_none() => 0
    | ~xspan_at(offset, span_len) => clock_ms(data, offset, span_len)): int
  val @(end_good, end_ms) = (case+ find_attr(data, attrs, end_chars, 7) of
    | ~xspan_none() => @(true, ~1)
    | ~xspan_at(offset, span_len) => let
        val value = clock_ms(data, offset, span_len)
      in if value < 0 then @(false, ~1) else @(true, value) end): @(bool, int)
in
  if begin_ms < 0 then @(false, 0, 0)
  else if ~end_good then @(false, 0, 0)
  else if end_ms < 0 then @(true, begin_ms, ~1)
  else if end_ms <= begin_ms then @(false, 0, 0)
  else @(true, begin_ms, end_ms)
end

(* The first audio element among a par's children *)
fun _par_audio {l:agz}{n:pos}{tree_size:nat} .<tree_size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): par_audio =
  case+ nodes of
  | $X.xml_nodes_nil() => @(false, 0, 0, 0, 0)
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(_, _) => _par_audio(data, rest)
     | $X.xml_element(name_offset, name_len, attrs, _) => let
         var audio_chars = @[char][5]('a', 'u', 'd', 'i', 'o')
         var src_chars = @[char][3]('s', 'r', 'c')
       in
         if xml_name_eq(data, name_offset, name_len, audio_chars, 5) then
           (case+ find_attr(data, attrs, src_chars, 3) of
            | ~xspan_none() => @(false, 0, 0, 0, 0)
            | ~xspan_at(src_offset, src_len) => let
                val path_len = src_end(data, src_offset, src_len)
                val @(good, begin_ms, end_ms) = _clip_times(data, attrs)
              in
                if path_len <= 0 then @(false, 0, 0, 0, 0)
                else @(good, begin_ms, end_ms, src_offset, path_len)
              end)
         else _par_audio(data, rest)
       end)

(* The fragment of a par's first text element's src (the id after its
   '#'): where it is and its length, 0 when there is none *)
fun _par_text {l:agz}{n:pos}{tree_size:nat} .<tree_size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): @(Nat, Nat) =
  case+ nodes of
  | $X.xml_nodes_nil() => @(0, 0)
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(_, _) => _par_text(data, rest)
     | $X.xml_element(name_offset, name_len, attrs, _) => let
         var text_chars = @[char][4]('t', 'e', 'x', 't')
         var src_chars = @[char][3]('s', 'r', 'c')
       in
         if xml_name_eq(data, name_offset, name_len, text_chars, 4) then
           (case+ find_attr(data, attrs, src_chars, 3) of
            | ~xspan_none() => @(0, 0)
            | ~xspan_at(src_offset, src_len) => let
                val path_len = src_end(data, src_offset, src_len)
              in
                if path_len + 1 >= src_len then @(0, 0)
                else @(src_offset + path_len + 1, src_len - path_len - 1)
              end)
         else _par_text(data, rest)
       end)

(* Whether an element is named name *)
fn _named {l:agz}{n:pos}{name_offset,name_len:nat | name_offset + name_len <= n}{pattern_len:pos}
  (data: !$A.borrow(byte, l, n), name_offset: int name_offset, name_len: int name_len,
   pattern: &(@[char][pattern_len]), pattern_len: int pattern_len): bool =
  xml_name_eq(data, name_offset, name_len, pattern, pattern_len)

(* The clips of nodes, added to total: each par whose audio is valid *)
fun _count_nodes {l:agz}{n:pos}{tree_size:nat} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), total: Nat): Nat =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => _count_nodes(data, rest, _count_node(data, node, total))
  | $X.xml_nodes_nil() => total

and _count_node {l:agz}{n:pos}{tree_size:pos} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), total: Nat): Nat =
  case+ node of
  | $X.xml_text(_, _) => total
  | $X.xml_element(name_offset, name_len, _, children) => let
      var par_chars = @[char][3]('p', 'a', 'r')
      var text_chars = @[char][4]('t', 'e', 'x', 't')
      var audio_chars = @[char][5]('a', 'u', 'd', 'i', 'o')
    in
      if _named(data, name_offset, name_len, par_chars, 3) then let
        val @(valid, _, _, _, _) = _par_audio(data, children)
      in if valid then (if total < 1000000 then total + 1 else total) else total end
      else if _named(data, name_offset, name_len, text_chars, 4) then total
      else if _named(data, name_offset, name_len, audio_chars, 5) then total
      else _count_nodes(data, children, total)
    end

(* How many clips the SMIL's nodes hold *)
#pub fn overlay_count {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size)): Nat

implement overlay_count (data, nodes) = _count_nodes(data, nodes, 0)

(* Clips [at, stop), each not yet in an escapable structure, are in one
   of kind: escaping it goes on at stop *)
fun _escape_mark {count:pos}{at,stop:nat | at <= stop; stop <= count}{kind:nat | kind <= 4} .<stop - at>.
  (table: !clip_table(count), at: int at, stop: int stop, kind: int kind): void =
  if at >= stop then ()
  else let
    val () = (if _word(table, at, FIELD_ESCAPE_TO) < 0 then let
        val () = _word_put(table, at, FIELD_ESCAPE_TO, stop)
      in _small_put(table, at, FIELD_ESCAPE_KIND, kind) end else ())
  in _escape_mark(table, at + 1, stop, kind) end

(* A par's clip, as clip number clip *)
fn _clip_put {count:pos}{clip:nat | clip < count}
  (table: !clip_table(count), clip: int clip, begin_ms: int, end_ms: int, src_offset: int, path_len: int,
   fragment_offset: int, fragment_len: int, skippable: bool): void = let
  val () = _word_put(table, clip, FIELD_BEGIN, begin_ms)
  val () = _word_put(table, clip, FIELD_END, end_ms)
  val () = _word_put(table, clip, FIELD_AUDIO_OFFSET, src_offset)
  val () = _word_put(table, clip, FIELD_AUDIO_SIZE, path_len)
  val () = _word_put(table, clip, FIELD_FIRST_NODE, fragment_offset)
  val () = _word_put(table, clip, FIELD_END_NODE, fragment_len)
  val () = _word_put(table, clip, FIELD_ESCAPE_TO, ~1)
in if skippable then _small_put(table, clip, FIELD_FLAGS, FLAG_SKIPPABLE) else _small_put(table, clip, FIELD_FLAGS, 0) end

(* The clips of nodes, from clip number at on, in a skippable structure
   when skipping: the number after the last *)
fun _fill_nodes {l:agz}{n:pos}{tree_size:nat}{count:pos}{at:nat | at <= count} .<tree_size, 1>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), table: !clip_table(count), count: int count,
   at: int at, skipping: bool): [next:nat | at <= next; next <= count] int next =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val next = _fill_node(data, node, table, count, at, skipping)
    in _fill_nodes(data, rest, table, count, next, skipping) end
  | $X.xml_nodes_nil() => at

and _fill_node {l:agz}{n:pos}{tree_size:pos}{count:pos}{at:nat | at <= count} .<tree_size, 0>.
  (data: !$A.borrow(byte, l, n), node: !$X.xml_node(n, tree_size), table: !clip_table(count), count: int count,
   at: int at, skipping: bool): [next:nat | at <= next; next <= count] int next =
  case+ node of
  | $X.xml_text(_, _) => at
  | $X.xml_element(name_offset, name_len, attrs, children) => let
      var par_chars = @[char][3]('p', 'a', 'r')
      var text_chars = @[char][4]('t', 'e', 'x', 't')
      var audio_chars = @[char][5]('a', 'u', 'd', 'i', 'o')
      val skipping_here = (if skipping then true else _skippable_type(data, attrs)): bool
      val kind = _escape_type(data, attrs)
      val next = (if _named(data, name_offset, name_len, par_chars, 3) then
          (if at >= count then at
           else let
             val @(valid, begin_ms, end_ms, src_offset, path_len) = _par_audio(data, children)
           in
             if valid then let
               val @(fragment_offset, fragment_len) = _par_text(data, children)
               val () = _clip_put(table, at, begin_ms, end_ms, src_offset, path_len, fragment_offset, fragment_len, skipping_here)
             in at + 1 end
             else at
           end)
        else if _named(data, name_offset, name_len, text_chars, 4) then at
        else if _named(data, name_offset, name_len, audio_chars, 5) then at
        else _fill_nodes(data, children, table, count, at, skipping_here)): [next:nat | at <= next; next <= count] int next
      val () = (if kind > 0 then _escape_mark(table, at, next, kind) else ())
    in next end

(* The SMIL's clips, data's, into table, in reading order; how many were
   put there (the SMIL's count, when the table holds them all). Each
   clip's audio is its src's path in the SMIL until it is found in the
   book (clip_audio_set), and its text the fragment of its src
   (clip_fragment_offset) until the chapter is rendered *)
#pub fn overlay_fill {l:agz}{n:pos}{tree_size:nat}{count:pos}
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, tree_size), table: !clip_table(count), count: int count)
  : [filled:nat | filled <= count] int filled

implement overlay_fill (data, nodes, table, count) = _fill_nodes(data, nodes, table, count, 0, false)
