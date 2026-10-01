(* jsonio -- JSON written into and read from byte buffers (the backup's):
   writes are in range by type, and reads check the bytes they are
   given (a file the user picked), once, as they go *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

staload "book.sats"

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

fn _hex_digit {value:nat | value < 16} (value: int value): [digit:nat | digit < 256] int digit =
  if value < 10 then 48 + value else 87 + value

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

end (* #target wasm *)
