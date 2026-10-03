(* jsonio -- JSON written into and read from byte buffers (the backup's):
   writes are in range by type, and reads check the bytes they are
   given (a file the user picked), once, as they go *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

staload "book.sats"
staload "clock.sats"

(* ============================================================
   Writing
   ============================================================ *)

(* JSON text in a piece: its bytes out[0, length) *)
#pub datavtype jchunk =
  | {owner,l:agz}{n:pos}{length:nat | length <= n} JChunk of (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int length)
  | JNone of ()

#pub fn jchunk_free (chunk: jchunk): void

implement jchunk_free (chunk) = case+ chunk of
  | ~JChunk(owner, out, _) => piece_free(owner, out)
  | ~JNone() => ()

(* A JSON file made a chunk at a time: count chunks of total bytes, the
   last one first *)
#pub datavtype jchunks(int, int) =
  | jchunks_nil(0, 0) of ()
  | {count,total:nat}{owner,l:agz}{n:pos}{length:nat | length <= n}
    jchunks_cons(count + 1, total + length) of
      (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int length, jchunks(count, total))

fun _jchunks_free {count,total:nat} .<count>. (pieces: jchunks(count, total)): void =
  case+ pieces of
  | ~jchunks_nil() => ()
  | ~jchunks_cons(owner, bytes, _, rest) => let val () = piece_free(owner, bytes) in _jchunks_free(rest) end

(* The chunks so far, at most limit bytes in all; whether each could
   be made (and kept within the limit) *)
#pub datavtype jfile(limit:int) =
  | {count,total:nat | total <= limit} JFile(limit) of (jchunks(count, total), int total, bool)

(* A file with no chunk yet *)
#pub fn jfile_new {limit:nat} (): jfile(limit)
implement jfile_new () = JFile(jchunks_nil(), 0, true)

#pub fn jfile_free {limit:nat} (file: jfile(limit)): void
implement jfile_free (file) = let val+ ~JFile(pieces, _, _) = file in _jchunks_free(pieces) end

(* chunk added after the chunks so far (the file is incomplete when
   chunk is none, or would be over limit bytes) *)
#pub fn jfile_push {limit:nat} (file: jfile(limit), limit: int limit, chunk: jchunk): jfile(limit)
implement jfile_push (file, limit, chunk) = let
  val+ ~JFile(pieces, total, complete) = file
in
  case+ chunk of
  | ~JNone() => JFile(pieces, total, false)
  | ~JChunk(owner, bytes, length) =>
    if total + length > limit then let
      val () = piece_free(owner, bytes)
    in JFile(pieces, total, false) end
    else JFile(jchunks_cons(owner, bytes, length, pieces), total + length, complete)
end

(* out[start, start + length) := source[0, length) *)
fun _copy_at {l,source_loc:agz}{owner,source_owner:addr}{out_size,n:nat}{length:nat | length <= n}
  {start:nat | start + length <= out_size}{i:nat | i <= length} .<length - i>.
  (out: !$A.arrx(byte, l, out_size, owner), start: int start,
   source: !$A.arrx(byte, source_loc, n, source_owner), length: int length, i: int i): void =
  if i >= length then ()
  else let
    val () = $A.write_byte(out, start + i, $AR.low_byte(byte2int0($A.get<byte>(source, i))))
  in _copy_at(out, start, source, length, i + 1) end

(* The chunks, the last first, at out[0, total) in order *)
fun _join {l:agz}{owner:addr}{out_size:nat}{count,total:nat | total <= out_size} .<count>.
  (out: !$A.arrx(byte, l, out_size, owner), pieces: jchunks(count, total), total: int total): void =
  case+ pieces of
  | ~jchunks_nil() => ()
  | ~jchunks_cons(owner, bytes, length, rest) => let
      val () = _copy_at(out, total - length, bytes, length, 0)
      val () = piece_free(owner, bytes)
    in _join(out, rest, total - length) end

(* A whole file: its bytes, out[0, n) *)
#pub datavtype jwhole =
  | {owner,l:agz}{n:pos | n <= 268435456} JWhole of (piece_owner(n, owner), $A.arrx(byte, l, n, owner), int n)
  | JNoWhole of ()

(* The file's chunks joined, in one piece; none when it is incomplete,
   empty, or no piece can be had for it *)
#pub fn jfile_join {limit:nat | limit <= 268435456} (file: jfile(limit)): jwhole
implement jfile_join (file) = let
  val+ ~JFile(pieces, total, complete) = file
in
  if ~complete then let val () = _jchunks_free(pieces) in JNoWhole() end
  else if total <= 0 then let val () = _jchunks_free(pieces) in JNoWhole() end
  else (case+ piece_new(total) of
    | ~NoPiece() => let val () = _jchunks_free(pieces) in JNoWhole() end
    | ~Piece(owner, out) => let
        val () = _join(out, pieces, total)
      in JWhole(owner, out, total) end)
end

(* out[i, count) := source[start + i, start + count) *)
fun _copy_from {out_loc,l:agz}{out_owner,owner:addr}{out_size,n:nat}{start,count:nat | start + count <= n; count <= out_size}
  {i:nat | i <= count} .<count - i>.
  (out: !$A.arrx(byte, out_loc, out_size, out_owner), source: !$A.arrx(byte, l, n, owner), start: int start, count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.write_byte(out, i, $AR.low_byte(byte2int0($A.get<byte>(source, start + i))))
  in _copy_from(out, source, start, count, i + 1) end

(* A copy of source[start, stop) in a piece of its own *)
#pub fn jchunk_copy {l:agz}{owner:addr}{n:nat}{start,stop:nat | start < stop; stop <= n; stop - start <= 268435456}
  (source: !$A.arrx(byte, l, n, owner), start: int start, stop: int stop): jchunk
implement jchunk_copy (source, start, stop) =
  case+ piece_new(stop - start) of
  | ~NoPiece() => JNone()
  | ~Piece(piece_owner, out) => let
      val () = _copy_from(out, source, start, stop - start, 0)
    in JChunk(piece_owner, out, stop - start) end

fun _write_text {l:agz}{owner:addr}{n:nat}{text_len:nat}{position:nat | position + text_len <= n}{i:nat | i <= text_len}
  .<text_len - i>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, text: string text_len, text_len: int text_len, i: int i)
  : int(position + text_len) =
  if i >= text_len then position + text_len
  else let
    val () = $A.write_byte(out, position + i, $AR.byte_of_char(string_get_at(text, i)))
  in _write_text(out, position, text, text_len, i + 1) end

(* text, at out[position, position + |text|) *)
#pub fn jw_lit {l:agz}{owner:addr}{n:nat}{text_len:nat}{position:nat | position + text_len <= n}
  (out: !$A.arrx(byte, l, n, owner), position: int position, text: string text_len): int(position + text_len)

implement jw_lit (out, position, text) = _write_text(out, position, text, g1u2i(string1_length(text)), 0)

(* The decimal digits of -negative, for negative <= 0: how many there
   are (negative's quotients by 10 are taken toward 0, so the smallest
   int has them too) *)
fun _digit_count {count:int | 1 <= count; count <= 10} .<10 - count>.
  (negative: int, count: int count): [total:int | 1 <= total; total <= 10] int total =
  if count >= 10 then count
  else if negative / 10 = 0 then count
  else _digit_count(negative / 10, count + 1)

(* -negative's digits at out[position, position + last + 1), the last
   at position + last *)
fun _write_digits {l:agz}{owner:addr}{n:nat}{position:nat}{last:int | ~1 <= last; position + last < n} .<last + 1>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, last: int last, negative: int): void =
  if last < 0 then ()
  else let
    val digit = (negative / 10) * 10 - negative
    val () = $A.write_byte(out, position + last, $AR.low_byte(48 + digit))
  in _write_digits(out, position, last - 1, negative / 10) end

(* value in decimal at out[position, stop) *)
#pub fn jw_int {l:agz}{owner:addr}{n:nat}{position:nat | position + 11 <= n}
  (out: !$A.arrx(byte, l, n, owner), position: int position, value: int)
  : [stop:int | position < stop; stop <= position + 11] int stop

implement jw_int (out, position, value) =
  if value < 0 then let
    val () = $A.write_byte(out, position, 45)
    val count = _digit_count(value, 1)
    val () = _write_digits(out, position + 1, count - 1, value)
  in position + 1 + count end
  else let
    val negative = ~value
    val count = _digit_count(negative, 1)
    val () = _write_digits(out, position, count - 1, negative)
  in position + count end

(* A stamp (clock.bats) as milliseconds since the epoch: its minute's
   start, and its count in that minute as milliseconds; 0 for none *)
#pub fn jw_stamp {l:agz}{owner:addr}{n:nat}{position:nat | position + 15 <= n}
  (out: !$A.arrx(byte, l, n, owner), position: int position, stamp: Int)
  : [stop:int | position < stop; stop <= position + 15] int stop

implement jw_stamp (out, position, stamp) =
  if stamp <= 0 then jw_int(out, position, 0)
  else let
    (* minutes * 60000 is minutes * 6 followed by four digits *)
    val tens_of_seconds = jw_int(out, position, stamp_minutes(stamp) * 6)
    val count = stamp_count(stamp)
    val () = $A.write_byte(out, tens_of_seconds, 48)
    val () = $A.write_byte(out, tens_of_seconds + 1, 48)
    val () = $A.write_byte(out, tens_of_seconds + 2, $AR.low_byte(48 + count / 10))
    val () = $A.write_byte(out, tens_of_seconds + 3, $AR.low_byte(48 + count - (count / 10) * 10))
  in tens_of_seconds + 4 end

fn _hex_digit {value:nat | value < 16} (value: int value): [digit:nat | digit < 256] int digit =
  if value < 10 then 48 + value else 87 + value

(* half's 7 hex digits (its low 28 bits), the first at
   out[position + 7 - left] *)
fun _seven_hex_at {l:agz}{owner:addr}{n:nat}{position:nat | position + 7 <= n}{left:nat | left <= 7} .<left>.
  (out: !$A.arrx(byte, l, n, owner), position: int position, half: int, left: int left): void =
  if left <= 0 then ()
  else let
    val () = $A.write_byte(out, position + 7 - left,
      _hex_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(half, 4 * (left - 1))), 15)))
  in _seven_hex_at(out, position, half, left - 1) end

(* An id (a book's, an annotation's) as its 14 hex digits, quoted: the
   7 of each half of 28 bits, at out[position, position + 16) *)
#pub fn jw_id {l:agz}{owner:addr}{n:nat}{position:nat | position + 16 <= n}
  (out: !$A.arrx(byte, l, n, owner), position: int position, id_high: int, id_low: int): int(position + 16)
implement jw_id (out, position, id_high, id_low) = let
  val () = $A.write_byte(out, position, 34)
  val () = _seven_hex_at(out, position + 1, id_high, 7)
  val () = _seven_hex_at(out, position + 8, id_low, 7)
  val () = $A.write_byte(out, position + 15, 34)
in position + 16 end

(* The escaped bytes of source[i, source_end), at out[position, ...) *)
fun _escape {l,source_loc:agz}{owner,source_owner:addr}{n,source_size:nat}
  {source_end:nat | source_end <= source_size}{i:nat | i <= source_end}
  {position:nat | position + 6 * (source_end - i) <= n} .<source_end - i>.
  (out: !$A.arrx(byte, l, n, owner), position: int position,
   source: !$A.arrx(byte, source_loc, source_size, source_owner), source_end: int source_end, i: int i)
  : [stop:nat | stop <= position + 6 * (source_end - i)] int stop =
  if i >= source_end then position
  else let
    val character = $AR.low_byte(byte2int0($A.get<byte>(source, i)))
  in
    if character = 34 then let
      val () = $A.write_byte(out, position, 92)
      val () = $A.write_byte(out, position + 1, 34)
    in _escape(out, position + 2, source, source_end, i + 1) end
    else if character = 92 then let
      val () = $A.write_byte(out, position, 92)
      val () = $A.write_byte(out, position + 1, 92)
    in _escape(out, position + 2, source, source_end, i + 1) end
    else if character = 10 then let
      val () = $A.write_byte(out, position, 92)
      val () = $A.write_byte(out, position + 1, 110)
    in _escape(out, position + 2, source, source_end, i + 1) end
    else if character = 9 then let
      val () = $A.write_byte(out, position, 92)
      val () = $A.write_byte(out, position + 1, 116)
    in _escape(out, position + 2, source, source_end, i + 1) end
    else if character < 32 then let
      val after_prefix = _write_text(out, position, "\\u00", 4, 0)
      val () = $A.write_byte(out, after_prefix,
        _hex_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(character, 4)), 15)))
      val () = $A.write_byte(out, after_prefix + 1, _hex_digit($AR.band_g1(character, 15)))
    in _escape(out, position + 6, source, source_end, i + 1) end
    else let
      val () = $A.write_byte(out, position, character)
    in _escape(out, position + 1, source, source_end, i + 1) end
  end

(* source[0, source_len) as a JSON string, quoted and escaped, at
   out[position, stop) *)
#pub fn jw_str {l,source_loc:agz}{owner,source_owner:addr}{n,source_size:nat}
  {source_len:nat | source_len <= source_size}{position:nat | position + 2 + 6 * source_len <= n}
  (out: !$A.arrx(byte, l, n, owner), position: int position,
   source: !$A.arrx(byte, source_loc, source_size, source_owner), source_len: int source_len)
  : [stop:nat | stop <= position + 2 + 6 * source_len] int stop

implement jw_str (out, position, source, source_len) = let
  val () = $A.write_byte(out, position, 34)
  val closing = _escape(out, position + 1, source, source_len, 0)
  val () = $A.write_byte(out, closing, 34)
in closing + 1 end

(* ============================================================
   Reading
   ============================================================ *)

fn _byte_at {l:agz}{owner:addr}{n:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), position: int position): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.get<byte>(buf, position)))

(* Past the white space at position *)
#pub fun jr_ws {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] int stop

fun _skip_white {l:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] int stop =
  if position >= n then position
  else let val character = _byte_at(buf, position) in
    if character = 32 then _skip_white(buf, n, position + 1)
    else if character = 10 then _skip_white(buf, n, position + 1)
    else if character = 13 then _skip_white(buf, n, position + 1)
    else if character = 9 then _skip_white(buf, n, position + 1)
    else position
  end

implement jr_ws (buf, n, position) = _skip_white(buf, n, position)

(* Whether the byte at position is expected *)
#pub fn jr_is {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, expected: int): bool

implement jr_is (buf, n, position, expected) =
  if position < n then _byte_at(buf, position) = expected else false

fun _read_digits {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}{count:nat | count <= 9} .<9 - count>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, count: int count, value: Int)
  : [stop:int | position <= stop; stop <= n] @(int, Int, int stop) =
  if count >= 9 then @(count, value, position)
  else if position >= n then @(count, value, position)
  else let val character = _byte_at(buf, position) in
    if character < 48 then @(count, value, position)
    else if character > 57 then @(count, value, position)
    else _read_digits(buf, n, position + 1, count + 1, value * 10 + (character - 48))
  end

(* An integer of at most 9 digits at position: whether there is one,
   its value and where it ends *)
#pub fn jr_int {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] @(bool, Int, int stop)

(* Whether the number ends at position: no more digits, no fraction,
   no exponent *)
fn _number_ends {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position): bool =
  if position >= n then true
  else let val character = _byte_at(buf, position) in
    if character >= 48 then character > 57 else character <> 46
  end && ~jr_is(buf, n, position, 101) && ~jr_is(buf, n, position, 69)

implement jr_int (buf, n, position) =
  if position >= n then @(false, 0, position)
  else if _byte_at(buf, position) = 45 then let
    val @(count, value, stop) = _read_digits(buf, n, position + 1, 0, 0)
  in @(count > 0 && _number_ends(buf, n, stop), ~value, stop) end
  else let
    val @(count, value, stop) = _read_digits(buf, n, position, 0, 0)
  in @(count > 0 && _number_ends(buf, n, stop), value, stop) end

(* The digits at position, at most 13 of them (milliseconds since the
   epoch, to the year 2286), as the number's ten-thousands and its last
   four digits *)
fun _milliseconds {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}{count:nat | count <= 13} .<13 - count>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, count: int count, high: Int, low: Int)
  : [stop:int | position <= stop; stop <= n] @(int, Int, Int, int stop) =
  if count >= 13 then @(count, high, low, position)
  else if position >= n then @(count, high, low, position)
  else let val character = _byte_at(buf, position) in
    if character < 48 then @(count, high, low, position)
    else if character > 57 then @(count, high, low, position)
    else let
      val shifted = low * 10 + (character - 48)
    in _milliseconds(buf, n, position + 1, count + 1, high * 10 + shifted / 10000, shifted - (shifted / 10000) * 10000) end
  end

(* A stamp written by jw_stamp at position: whether there is one, the
   stamp (its count in its minute at most 63) and where it ends *)
#pub fn jr_stamp {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] @(bool, Int, int stop)

implement jr_stamp (buf, n, position) = let
  val @(count, high, low, stop) = _milliseconds(buf, n, position, 0, 0, 0)
in
  if count <= 0 then @(false, 0, stop)
  else if ~_number_ends(buf, n, stop) then @(false, 0, stop)
  else if high <= 0 then @(true, 0, stop)
  else let
    val within = (high - (high / 6) * 6) * 10000 + low
    val count_in_minute = (if within >= 63 then 63 else if within <= 0 then 0 else within): [count:nat | count < 64] int count
  in @(true, stamp_make(high / 6, count_in_minute), stop) end
end

fn _hex_value (character: int): int =
  if character >= 48 then (if character <= 57 then character - 48
    else if character >= 97 then (if character <= 102 then character - 87 else ~1)
    else if character >= 65 then (if character <= 70 then character - 55 else ~1) else ~1)
  else ~1

(* The 4 hex digits at position, or -1 *)
fn _four_hex {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position): int =
  if position + 4 > n then ~1
  else let
    val first = _hex_value(_byte_at(buf, position))
    val second = _hex_value(_byte_at(buf, position + 1))
    val third = _hex_value(_byte_at(buf, position + 2))
    val fourth = _hex_value(_byte_at(buf, position + 3))
  in
    if first < 0 || second < 0 || third < 0 || fourth < 0 then ~1
    else ((first * 16 + second) * 16 + third) * 16 + fourth
  end

(* The UTF-8 of code_point at out[length, ...) when it fits in
   capacity: the new length, or length when it does not fit *)
fn _write_utf8 {out_loc:agz}{capacity:nat}{length:nat | length <= capacity}
  (out: !$A.arr(byte, out_loc, capacity), capacity: int capacity, length: int length, code_point: int)
  : [new_length:int | length <= new_length; new_length <= capacity] int new_length =
  if code_point < 128 then
    (if length + 1 <= capacity then let
       val () = $A.write_byte(out, length, $AR.low_byte(code_point))
     in length + 1 end else length)
  else if code_point < 2048 then
    (if length + 2 <= capacity then let
       val () = $A.write_byte(out, length, $AR.low_byte(192 + code_point / 64))
       val () = $A.write_byte(out, length + 1, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(code_point), 63)))
     in length + 2 end else length)
  else if code_point < 65536 then
    (if length + 3 <= capacity then let
       val () = $A.write_byte(out, length, $AR.low_byte(224 + code_point / 4096))
       val () = $A.write_byte(out, length + 1, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(code_point / 64), 63)))
       val () = $A.write_byte(out, length + 2, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(code_point), 63)))
     in length + 3 end else length)
  else
    (if length + 4 <= capacity then let
       val () = $A.write_byte(out, length, $AR.low_byte(240 + code_point / 262144))
       val () = $A.write_byte(out, length + 1, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(code_point / 4096), 63)))
       val () = $A.write_byte(out, length + 2, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(code_point / 64), 63)))
       val () = $A.write_byte(out, length + 3, $AR.low_byte(128 + $AR.band_g1($AR.low_byte(code_point), 63)))
     in length + 4 end else length)

(* code_point's UTF-8 at out[length, ...) unless the string is already
   full *)
fn _emit {out_loc:agz}{capacity:nat}{length:nat | length <= capacity}
  (full: bool, out: !$A.arr(byte, out_loc, capacity), capacity: int capacity, length: int length, code_point: int)
  : [new_length:int | length <= new_length; new_length <= capacity] int new_length =
  if full then length else _write_utf8(out, capacity, length, code_point)

(* The bytes a UTF-8 sequence led by lead takes *)
fn _sequence_length (lead: int): [bytes:int | 1 <= bytes; bytes <= 4] int bytes =
  if lead >= 240 then 4 else if lead >= 224 then 3 else if lead >= 192 then 2 else 1

(* A string's contents from position (past its opening quote), decoded
   into out[length, capacity): once out is full the rest is read and
   dropped, a character at a time. Whether it closed, its length, where
   it ends. *)
fun _read_string {l,out_loc:agz}{owner:addr}{n,capacity:nat}{position:nat | position <= n}
  {length:nat | length <= capacity} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   out: !$A.arr(byte, out_loc, capacity), capacity: int capacity, length: int length, full: bool)
  : [stop:int | position <= stop; stop <= n][total:nat | total <= capacity] @(bool, int total, int stop) =
  if position >= n then @(false, length, position)
  else let val character = _byte_at(buf, position) in
    if character = 34 then @(true, length, position + 1)
    else if character = 92 then
      (if position + 1 >= n then @(false, length, n)
       else let val escaped = _byte_at(buf, position + 1) in
         if escaped = 117 then
           (if position + 6 > n then @(false, length, n)
           else let
           val code_point = _four_hex(buf, n, position + 2)
         in
           if code_point < 0 then @(false, length, n)
           else if (if code_point >= 55296 then code_point <= 56319 else false) then
             (* a high surrogate: its low one follows *)
             (if position + 12 > n then @(false, length, n)
              else if (if _byte_at(buf, position + 6) = 92 then _byte_at(buf, position + 7) = 117 else false) then let
                val low = _four_hex(buf, n, position + 8)
              in
                if (if low >= 56320 then low <= 57343 else false) then let
                  val new_length = _emit(full, out, capacity, length,
                    65536 + (code_point - 55296) * 1024 + (low - 56320))
                in _read_string(buf, n, position + 12, out, capacity, new_length, full || (new_length = length)) end
                else @(false, length, n)
              end
              else @(false, length, n))
           else let
             val new_length = _emit(full, out, capacity, length, code_point)
           in _read_string(buf, n, position + 6, out, capacity, new_length, full || (new_length = length)) end
         end)
         else let
           val decoded = (if escaped = 110 then 10 else if escaped = 116 then 9 else if escaped = 114 then 13
             else if escaped = 98 then 8 else if escaped = 102 then 12 else escaped): int
           val new_length = _emit(full, out, capacity, length, decoded)
         in _read_string(buf, n, position + 2, out, capacity, new_length, full || (new_length = length)) end
       end)
    else if character < 128 then let
      val new_length = _emit(full, out, capacity, length, character)
    in _read_string(buf, n, position + 1, out, capacity, new_length, full || (new_length = length)) end
    else if character < 192 then
      (* a continuation byte: kept when its sequence's lead was *)
      (if full then _read_string(buf, n, position + 1, out, capacity, length, full)
       else if length < capacity then let
         val () = $A.write_byte(out, length, character)
       in _read_string(buf, n, position + 1, out, capacity, length + 1, full) end
       else _read_string(buf, n, position + 1, out, capacity, length, true))
    else
      (* a lead byte: kept when its whole sequence fits *)
      (if full then _read_string(buf, n, position + 1, out, capacity, length, full)
       else if length + _sequence_length(character) <= capacity then let
         val () = $A.write_byte(out, length, character)
       in _read_string(buf, n, position + 1, out, capacity, length + 1, full) end
       else _read_string(buf, n, position + 1, out, capacity, length, true))
  end

(* The string at position, decoded into out[0, capacity) (cut at a
   character when it is longer): whether there is one, its length and
   where it ends *)
#pub fn jr_str {l,out_loc:agz}{owner:addr}{n,capacity:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   out: !$A.arr(byte, out_loc, capacity), capacity: int capacity)
  : [stop:int | position < stop; stop <= n][length:nat | length <= capacity] @(bool, int length, int stop)

implement jr_str (buf, n, position, out, capacity) =
  if _byte_at(buf, position) = 34 then _read_string(buf, n, position + 1, out, capacity, 0, false)
  else @(false, 0, position + 1)

(* Whether the literal text is at position *)
fun _literal_at {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}{text_len:nat}{i:nat | i <= text_len}
  .<text_len - i>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if position + i >= n then false
  else if _byte_at(buf, position + i) <> $AR.byte_of_char(string_get_at(text, i)) then false
  else _literal_at(buf, n, position, text, text_len, i + 1)

(* true or false at position: whether it is either, its value, where it
   ends *)
#pub fn jr_bool {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] @(bool, bool, int stop)

implement jr_bool (buf, n, position) =
  if _literal_at(buf, n, position, "true", 4, 0) then
    (if position + 4 <= n then @(true, true, position + 4) else @(false, false, position))
  else if _literal_at(buf, n, position, "false", 5, 0) then
    (if position + 5 <= n then @(true, false, position + 5) else @(false, false, position))
  else @(false, false, position)

(* Skipping a value: a value at position ends past it (or at n when it
   is cut short or nested more than 64 deep) *)
fun _skip_value {l:agz}{owner:addr}{n:nat}{position:nat | position < n} .<n - position, 0>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, depth: int)
  : [stop:int | position < stop; stop <= n] int stop = let
  val character = _byte_at(buf, position)
in
  if character = 34 then let
    val scratch = $A.alloc<byte>(1)
    val @(closed, _, stop) = _read_string(buf, n, position + 1, scratch, 1, 0, true)
    val () = $A.free<byte>(scratch)
  in if closed then stop else n end
  else if character = 91 then (if depth >= 64 then n else _skip_items(buf, n, position + 1, depth + 1, 93))
  else if character = 123 then (if depth >= 64 then n else _skip_items(buf, n, position + 1, depth + 1, 125))
  else _skip_scalar(buf, n, position + 1)
end

(* The items of an array (or members of an object: key, colon and
   value are skipped as three items) from position to the closing byte *)
and _skip_items {l:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position, 1>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, depth: int, closing: int)
  : [stop:int | position <= stop; stop <= n] int stop = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then n
  else let val character = _byte_at(buf, next) in
    if character = closing then next + 1
    else if character = 44 then _skip_items(buf, n, next + 1, depth, closing)
    else if character = 58 then _skip_items(buf, n, next + 1, depth, closing)
    else _skip_items(buf, n, _skip_value(buf, n, next, depth), depth, closing)
  end
end

(* A number, true, false or null: to the next delimiter *)
and _skip_scalar {l:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position, 2>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] int stop =
  if position >= n then position
  else let val character = _byte_at(buf, position) in
    if character = 44 || character = 93 || character = 125 || character = 58
      || character = 32 || character = 10 || character = 13 || character = 9 then position
    else _skip_scalar(buf, n, position + 1)
  end

(* Past the value at position *)
#pub fn jr_skip {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] int stop

implement jr_skip (buf, n, position) = if position < n then _skip_value(buf, n, position, 0) else position

(* A member's key at position (after white space): whether there is one
   (read into out[0, capacity), cut when longer), its length, and where
   its value starts (past the colon and white space) *)
#pub fn jr_key {l,out_loc:agz}{owner:addr}{n,capacity:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position,
   out: !$A.arr(byte, out_loc, capacity), capacity: int capacity)
  : [stop:int | position < stop; stop <= n][length:nat | length <= capacity] @(bool, int length, int stop)

implement jr_key (buf, n, position, out, capacity) = let
  val @(found, key_len, after_key) = jr_str(buf, n, position, out, capacity)
in
  if ~found then @(false, key_len, after_key)
  else let
    val colon = jr_ws(buf, n, after_key)
  in
    if colon >= n then @(false, key_len, colon)
    else if _byte_at(buf, colon) = 58 then let
      val value_start = jr_ws(buf, n, colon + 1)
    in @(true, key_len, value_start) end
    else @(false, key_len, colon)
  end
end

fun _key_equals {key_loc:agz}{capacity:nat}{key_len:nat | key_len <= capacity}{text_len:nat}{i:nat | i <= text_len}
  .<text_len - i>.
  (key: !$A.arr(byte, key_loc, capacity), key_len: int key_len, text: string text_len, text_len: int text_len, i: int i)
  : bool =
  if i >= text_len then true
  else if i >= key_len then false
  else if $AR.low_byte(byte2int0($A.get<byte>(key, i))) <> $AR.byte_of_char(string_get_at(text, i)) then false
  else _key_equals(key, key_len, text, text_len, i + 1)

(* Whether key[0, key_len) is text *)
#pub fn jr_key_is {key_loc:agz}{capacity:nat}{key_len:nat | key_len <= capacity}{text_len:nat}
  (key: !$A.arr(byte, key_loc, capacity), key_len: int key_len, text: string text_len): bool

implement jr_key_is (key, key_len, text) = let
  val text_len = g1u2i(string1_length(text))
in if key_len <> text_len then false else _key_equals(key, key_len, text, text_len, 0) end

(* The 7 hex digits at position, as a number; -1 when one is not *)
fun _seven_hex {l:agz}{owner:addr}{n:nat}{position:nat | position + 7 <= n}{i:nat | i <= 7} .<7 - i>.
  (buf: !$A.arrx(byte, l, n, owner), position: int position, i: int i, value: int): int =
  if i >= 7 then value
  else let
    val digit = _hex_value(_byte_at(buf, position + i))
  in if digit < 0 then ~1 else _seven_hex(buf, position, i + 1, value * 16 + digit) end

(* An id written by jw_id at position: whether there is one, its two
   halves, and where it ends *)
#pub fn jr_id {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position)
  : [stop:int | position <= stop; stop <= n] @(bool, Int, Int, int stop)
implement jr_id (buf, n, position) =
  if position + 16 > n then let val stop = jr_skip(buf, n, position) in @(false, 0, 0, stop) end
  else if _byte_at(buf, position) <> 34 then let val stop = jr_skip(buf, n, position) in @(false, 0, 0, stop) end
  else if _byte_at(buf, position + 15) <> 34 then let val stop = jr_skip(buf, n, position) in @(false, 0, 0, stop) end
  else let
    val id_high = g1ofg0(_seven_hex(buf, position + 1, 0, 0))
    val id_low = g1ofg0(_seven_hex(buf, position + 8, 0, 0))
  in
    if id_high < 0 then @(false, 0, 0, position + 16)
    else if id_low < 0 then @(false, 0, 0, position + 16)
    else @(true, id_high, id_low, position + 16)
  end

(* Where the value of the member named name starts, in the object whose
   members start at position (past its brace); -1 when it has none *)
#pub fn jr_member {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{name_len:pos}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16), name: string name_len)
  : [at:int | ~1 <= at; at < n] int at

fun _member {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{name_len:pos} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16), name: string name_len)
  : [at:int | ~1 <= at; at < n] int at = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then ~1
  else if jr_is(buf, n, next, 125) then ~1
  else if jr_is(buf, n, next, 44) then _member(buf, n, next + 1, key, name)
  else let
    val @(found, key_len, value_at) = jr_key(buf, n, next, key, 16)
  in
    if ~found then ~1
    else if value_at >= n then ~1
    else if jr_key_is(key, key_len, name) then value_at
    else _member(buf, n, jr_skip(buf, n, value_at), key, name)
  end
end

implement jr_member (buf, n, position, key, name) = _member(buf, n, position, key, name)

(* Where an object's members start: past the brace of the value at at;
   -1 when it is not an object (or at is -1) *)
#pub fn jr_object {l:agz}{owner:addr}{n:nat}{at:int | ~1 <= at; at < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, at: int at): [inside:int | ~1 <= inside; inside <= n] int inside

implement jr_object (buf, n, at) =
  if at < 0 then ~1
  else let
    val start = jr_ws(buf, n, at)
  in if start >= n then ~1 else if jr_is(buf, n, start, 123) then start + 1 else ~1 end

end (* #target wasm *)
