(* stardict -- the bytes of a StarDict dictionary: its .ifo's keys, the
   order its headwords are sorted in, and an article as plain text *)

(* A StarDict dictionary (StarDict's doc/StarDictFileFormat) is:
   * an .ifo: "StarDict's dict ifo file", then key=value lines
     (bookname, wordcount, idxfilesize, sametypesequence, ...);
   * an .idx: records of a headword, a 0 byte, and its article's offset
     and size in the .dict (two big-endian u32), sorted by
     stardict_strcmp: ASCII letters in either case alike first, then
     byte by byte;
   * a .dict, or a .dict.dz (dictzip), holding the articles;
   * maybe a .syn: other forms of headwords, each a word, a 0 byte and
     the number of an .idx record (a big-endian u32), sorted the same.
   Everything here reads bytes a file the reader picked holds, so each
   is checked as it is read. *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

staload "entity.sats"

(* The most bytes an article is shown with, cut where a character
   begins: a text of under 64 KiB, as the page takes one *)
#pub stadef ARTICLE_MAX = 65535

fn _byte_of {l:agz}{o:addr}{n:nat}{i:nat | i < n} (bytes: !$A.arrx(byte, l, n, o), i: int i): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))

(* ============================================================
   The .ifo
   ============================================================ *)

(* Whether the line at ifo[at] starts with key and '=' *)
fun _key_at {l:agz}{n:pos}{key_len:nat}{at:nat}{i:nat | i <= key_len} .<key_len - i>.
  (ifo: !$A.arr(byte, l, n), n: int n, at: int at, key: string key_len, key_len: int key_len, i: int i): bool =
  if i >= key_len then (if at + key_len < n then _byte_of(ifo, at + key_len) = 61 else false)
  else if at + i >= n then false
  else if _byte_of(ifo, at + i) <> char2int0(string_get_at(key, i)) then false
  else _key_at(ifo, n, at, key, key_len, i + 1)

(* Where the line at ifo[at] ends: its line break, or the end *)
fun _line_end {l:agz}{n:pos}{at:nat | at <= n} .<n - at>.
  (ifo: !$A.arr(byte, l, n), n: int n, at: int at): [stop:nat | at <= stop; stop <= n] int stop =
  if at >= n then n
  else let val code = _byte_of(ifo, at) in
    if code = 10 then at else if code = 13 then at else _line_end(ifo, n, at + 1)
  end

fun _find_key {l:agz}{n:pos}{key_len:pos}{at:nat | at <= n} .<n - at>.
  (ifo: !$A.arr(byte, l, n), n: int n, at: int at, key: string key_len, key_len: int key_len)
  : [start,stop:nat | start <= stop; stop <= n] @(bool, int start, int stop) =
  if at >= n then @(false, 0, 0)
  else let
    val stop = _line_end(ifo, n, at)
  in
    if _key_at(ifo, n, at, key, key_len, 0) then
      (if at + key_len + 1 <= stop then @(true, at + key_len + 1, stop) else @(true, stop, stop))
    else if stop >= n then @(false, 0, 0)
    else _find_key(ifo, n, stop + 1, key, key_len)
  end

(* The value of key in the .ifo ifo[0, n): ifo[start, stop), and whether
   there is one *)
#pub fn ifo_find {l:agz}{n:pos}{key_len:pos | key_len < 64}
  (ifo: !$A.arr(byte, l, n), n: int n, key: string key_len): [start,stop:nat | start <= stop; stop <= n] @(bool, int start, int stop)

implement ifo_find (ifo, n, key) = _find_key(ifo, n, 0, key, g1u2i(string1_length(key)))

fun _digits {l:agz}{n:pos}{stop:nat | stop <= n}{at:nat | at <= stop} .<stop - at>.
  (ifo: !$A.arr(byte, l, n), at: int at, stop: int stop, total: [total:nat | total <= 2147483647] int total, seen: bool): [value:int | value >= ~1] int value = (* wide *)
  if at >= stop then (if seen then total else ~1)
  else let val code = _byte_of(ifo, at) in
    if code < 48 then ~1
    else if code > 57 then ~1
    else if total >= 214748364 then ~1
    else _digits(ifo, at + 1, stop, total * 10 + (code - 48), true)
  end

(* The number key gives in the .ifo: -1 when it gives none, or what it
   gives is not a number under 2147483640 *)
#pub fn ifo_number {l:agz}{n:pos}{key_len:pos | key_len < 64}
  (ifo: !$A.arr(byte, l, n), n: int n, key: string key_len): [value:int | value >= ~1] int value

implement ifo_number (ifo, n, key) = let
  val @(found, start, stop) = ifo_find(ifo, n, key)
in if found then _digits(ifo, start, stop, 0, false) else ~1 end

(* Whether ifo[0, n) starts as an .ifo does *)
#pub fn ifo_is_stardict {l:agz}{n:pos} (ifo: !$A.arr(byte, l, n), n: int n): bool

fun _starts {l:agz}{n:pos}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (ifo: !$A.arr(byte, l, n), n: int n, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if i >= n then false
  else if _byte_of(ifo, i) <> char2int0(string_get_at(text, i)) then false
  else _starts(ifo, n, text, text_len, i + 1)

implement ifo_is_stardict (ifo, n) = let
  val head = "StarDict's dict ifo file"
in _starts(ifo, n, head, g1u2i(string1_length(head)), 0) end

(* ============================================================
   The order of headwords
   ============================================================ *)

fn _lower (code: int): int = if code >= 65 then (if code <= 90 then code + 32 else code) else code

(* How a headword sorts against a query *)
#pub datatype word_order = Before | Same | After

fun _fold_compare {word_loc,query_loc:agz}{word_owner,query_owner:addr}{word_size,query_size:nat}
  {start,word_len:nat | start + word_len <= word_size}{query_len:nat | query_len <= query_size}{i:nat | i <= word_len} .<word_len - i>.
  (word: !$A.arrx(byte, word_loc, word_size, word_owner), start: int start, word_len: int word_len,
   query: !$A.arrx(byte, query_loc, query_size, query_owner), query_len: int query_len, i: int i): word_order =
  if i >= word_len then (if i >= query_len then Same() else Before())
  else if i >= query_len then After()
  else let
    val word_code = _lower(_byte_of(word, start + i))
    val query_code = _lower(_byte_of(query, i))
  in
    if word_code < query_code then Before()
    else if word_code > query_code then After()
    else _fold_compare(word, start, word_len, query, query_len, i + 1)
  end

(* How the headword word[start, start + word_len) sorts against
   query[0, query_len) with ASCII letters' case set aside (the first
   key of stardict_strcmp) *)
#pub fn word_fold_compare {word_loc,query_loc:agz}{word_owner,query_owner:addr}{word_size,query_size:nat}
  {start,word_len:nat | start + word_len <= word_size}{query_len:nat | query_len <= query_size}
  (word: !$A.arrx(byte, word_loc, word_size, word_owner), start: int start, word_len: int word_len,
   query: !$A.arrx(byte, query_loc, query_size, query_owner), query_len: int query_len): word_order

implement word_fold_compare (word, start, word_len, query, query_len) =
  _fold_compare(word, start, word_len, query, query_len, 0)

fun _same {word_loc,query_loc:agz}{word_owner,query_owner:addr}{word_size,query_size:nat}
  {start,word_len:nat | start + word_len <= word_size; word_len <= query_size}{i:nat | i <= word_len} .<word_len - i>.
  (word: !$A.arrx(byte, word_loc, word_size, word_owner), start: int start, word_len: int word_len,
   query: !$A.arrx(byte, query_loc, query_size, query_owner), i: int i): bool =
  if i >= word_len then true
  else if _byte_of(word, start + i) <> _byte_of(query, i) then false
  else _same(word, start, word_len, query, i + 1)

(* Whether the headword word[start, start + word_len) is query[0, query_len), byte for byte *)
#pub fn word_equal {word_loc,query_loc:agz}{word_owner,query_owner:addr}{word_size,query_size:nat}
  {start,word_len:nat | start + word_len <= word_size}{query_len:nat | query_len <= query_size}
  (word: !$A.arrx(byte, word_loc, word_size, word_owner), start: int start, word_len: int word_len,
   query: !$A.arrx(byte, query_loc, query_size, query_owner), query_len: int query_len): bool

implement word_equal (word, start, word_len, query, query_len) =
  if word_len <> query_len then false
  else _same(word, start, word_len, query, 0)

(* ============================================================
   Bytes in records
   ============================================================ *)

fun _zero_at {l:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop} .<stop - at>.
  (bytes: !$A.arrx(byte, l, n, o), at: int at, stop: int stop): [found:nat | at <= found; found <= stop] int found =
  if at >= stop then stop
  else if _byte_of(bytes, at) = 0 then at
  else _zero_at(bytes, at + 1, stop)

(* The first 0 byte in bytes[at, stop), or stop *)
#pub fn zero_at {l:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop}
  (bytes: !$A.arrx(byte, l, n, o), at: int at, stop: int stop): [found:nat | at <= found; found <= stop] int found

implement zero_at (bytes, at, stop) = _zero_at(bytes, at, stop)

(* The big-endian u32 at bytes[at, at + 4): -1 when it is 2^31 or more *)
#pub fn u32_at {l:agz}{o:addr}{n:nat}{at:nat | at + 4 <= n}
  (bytes: !$A.arrx(byte, l, n, o), at: int at): [value:int | value >= ~1] int value

implement u32_at (bytes, at) = let
  val high = _byte_of(bytes, at)
in
  if high >= 128 then ~1
  else high * 16777216 + _byte_of(bytes, at + 1) * 65536 + _byte_of(bytes, at + 2) * 256 + _byte_of(bytes, at + 3)
end

(* value (0 to 2^31 - 1) as a big-endian u32 at bytes[at, at + 4) *)
#pub fn u32_put {l:agz}{o:addr}{n:nat}{at:nat | at + 4 <= n}
  (bytes: !$A.arrx(byte, l, n, o), at: int at, value: int): void

implement u32_put (bytes, at, value) = let
  val () = $A.write_byte(bytes, at, $AR.low_byte(value / 16777216))
  val () = $A.write_byte(bytes, at + 1, $AR.low_byte(value / 65536))
  val () = $A.write_byte(bytes, at + 2, $AR.low_byte(value / 256))
in $A.write_byte(bytes, at + 3, $AR.low_byte(value)) end

(* ============================================================
   UTF-8
   ============================================================ *)

(* Back from at to where the character holding byte at - 1 begins *)
fun _char_begins {l:agz}{o:addr}{n:nat}{at:nat | at <= n} .<at>.
  (bytes: !$A.arrx(byte, l, n, o), at: int at): [begins:nat | begins <= at] int begins =
  if at <= 0 then 0
  else let val code = _byte_of(bytes, at - 1) in
    if code >= 128 then (if code < 192 then _char_begins(bytes, at - 1) else at - 1) else at - 1
  end

(* text_len, or less so that bytes[0, cut) ends with a whole character *)
#pub fn utf8_cut {l:agz}{o:addr}{n:nat}{text_len:nat | text_len <= n}
  (bytes: !$A.arrx(byte, l, n, o), text_len: int text_len): [cut:nat | cut <= text_len] int cut

implement utf8_cut (bytes, text_len) =
  if text_len <= 0 then 0
  else let
    val begins = _char_begins(bytes, text_len)
  in
    if begins >= text_len then text_len
    else let
      val lead = _byte_of(bytes, begins)
      val needed = (if lead < 128 then 1 else if lead >= 240 then 4 else if lead >= 224 then 3 else if lead >= 192 then 2 else 1): int
    in if begins + needed > text_len then begins else text_len end
  end

(* ============================================================
   An article as text
   ============================================================ *)

(* out[written] := code, when there is room *)
fn _put {l:agz}{cap:nat | cap <= ARTICLE_MAX}{written:nat | written <= cap}
  (out: !$A.arr(byte, l, ARTICLE_MAX), cap: int cap, written: int written, code: int): [after:nat | written <= after; after <= cap] int after =
  if written >= cap then written
  else let
    val () = $A.write_byte(out, written, $AR.low_byte(code))
  in written + 1 end

(* A line break at out[written], unless it would begin the text or
   follow another *)
fn _break {l:agz}{cap:nat | cap <= ARTICLE_MAX}{written:nat | written <= cap}
  (out: !$A.arr(byte, l, ARTICLE_MAX), cap: int cap, written: int written): [after:nat | written <= after; after <= cap] int after =
  if written <= 0 then written
  else if _byte_of(out, written - 1) = 10 then written
  else _put(out, cap, written, 10)

(* The letters and digits of the tag name at data[at, stop), lower case,
   packed 5 bits each (at most 6 of them); and where they end *)
fun _tag_name {l:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop} .<stop - at>.
  (data: !$A.arrx(byte, l, n, o), at: int at, stop: int stop, packed: int, count: int): @(int, int) =
  if at >= stop then @(packed, count)
  else let
    val code = _lower(_byte_of(data, at))
    val letter = (if code >= 97 then (if code <= 122 then code - 96 else ~1)
      else if code >= 49 then (if code <= 54 then code - 22 else ~1) else ~1): int
  in
    if letter < 0 then @(packed, count)
    else if count >= 6 then @(0, 7)
    else _tag_name(data, at + 1, stop, packed * 32 + letter, count + 1)
  end

(* A tag name packed as _tag_name packs it *)
fn _packed {name_len:pos | name_len <= 6} (name: string name_len): int = let
  fun pack {i:nat | i <= name_len} .<name_len - i>. (i: int i, packed: int): int =
    if i >= g1u2i(string1_length(name)) then packed
    else let
      val code = char2int0(string_get_at(name, i))
      val letter = (if code >= 97 then code - 96 else code - 22): int
    in pack(i + 1, packed * 32 + letter) end
in pack(0, 0) end

(* Whether the tag whose name starts at data[at] (after "<" or "</")
   breaks the line: p, br, div, li, the headings, and a table's rows and
   a definition list's items *)
fn _breaks {l:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop}
  (data: !$A.arrx(byte, l, n, o), at: int at, stop: int stop): bool = let
  val @(packed, count) = _tag_name(data, at, stop, 0, 0)
in
  if count <= 0 then false
  else if count > 6 then false
  else packed = _packed("p") || packed = _packed("br") || packed = _packed("div") || packed = _packed("li")
    || packed = _packed("h1") || packed = _packed("h2") || packed = _packed("h3") || packed = _packed("h4")
    || packed = _packed("h5") || packed = _packed("h6") || packed = _packed("tr") || packed = _packed("dt")
    || packed = _packed("dd")
end

(* The first '>' in data[at, stop), or stop *)
fun _tag_end {l:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop} .<stop - at>.
  (data: !$A.arrx(byte, l, n, o), at: int at, stop: int stop): [found:nat | at <= found; found <= stop] int found =
  if at >= stop then stop
  else if _byte_of(data, at) = 62 then at
  else _tag_end(data, at + 1, stop)

(* data[at, stop), markup (HTML or XDXF), as text at out[written, cap):
   its tags dropped (a block's as a line break), runs of white space
   one space *)
fun _strip {l,out_loc:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop}
  {cap:nat | cap <= ARTICLE_MAX}{written:nat | written <= cap} .<stop - at>.
  (data: !$A.arrx(byte, l, n, o), at: int at, stop: int stop,
   out: !$A.arr(byte, out_loc, ARTICLE_MAX), cap: int cap, written: int written, spaced: bool)
  : [after:nat | written <= after; after <= cap] int after =
  if at >= stop then written
  else let
    val code = _byte_of(data, at)
  in
    if code = 60 then let
      val name_at = (if at + 1 < stop then (if _byte_of(data, at + 1) = 47 then at + 2 else at + 1) else stop)
        : [name_at:nat | at <= name_at; name_at <= stop] int name_at
      val closing = _tag_end(data, name_at, stop)
      val breaks = _breaks(data, name_at, stop)
      val next = (if closing < stop then closing + 1 else stop): [next:nat | at < next; next <= stop] int next
    in
      if breaks then _strip(data, next, stop, out, cap, _break(out, cap, written), true)
      else _strip(data, next, stop, out, cap, written, spaced)
    end
    else if code = 32 || code = 10 || code = 13 || code = 9 then
      (if spaced then _strip(data, at + 1, stop, out, cap, written, true)
       else _strip(data, at + 1, stop, out, cap, _put(out, cap, written, 32), true))
    else _strip(data, at + 1, stop, out, cap, _put(out, cap, written, code), false)
  end

(* data[at, stop), plain text, at out[written, cap) *)
fun _plain {l,out_loc:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop}
  {cap:nat | cap <= ARTICLE_MAX}{written:nat | written <= cap} .<stop - at>.
  (data: !$A.arrx(byte, l, n, o), at: int at, stop: int stop,
   out: !$A.arr(byte, out_loc, ARTICLE_MAX), cap: int cap, written: int written)
  : [after:nat | written <= after; after <= cap] int after =
  if at >= stop then written
  else if written >= cap then written
  else _plain(data, at + 1, stop, out, cap, _put(out, cap, written, _byte_of(data, at)))

(* out[start, start + count) := source[0, count) *)
fun _copy_into {source_loc,out_loc:agz}{source_size:nat}{count:nat | count <= source_size}{start:nat | start + count <= ARTICLE_MAX}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, out: !$A.arr(byte, out_loc, ARTICLE_MAX), start: int start, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(out, start + i, $A.get<byte>(source, i))
  in _copy_into(source, count, out, start, i + 1) end

(* data[at, stop), markup, as text at out[written, ARTICLE_MAX): its
   tags dropped, then its references decoded (entity.bats) *)
fn _markup {l,out_loc:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop}{written:nat | written <= ARTICLE_MAX}
  (data: !$A.arrx(byte, l, n, o), at: int at, stop: int stop, out: !$A.arr(byte, out_loc, ARTICLE_MAX), written: int written)
  : [after:nat | written <= after; after <= ARTICLE_MAX] int after = let
  val stripped = $A.alloc<byte>(65535)
  val stripped_len = _strip(data, at, stop, stripped, 65535 - written, 0, true)
in
  if stripped_len <= 0 then let val () = $A.free<byte>(stripped) in written end
  else let
    val decoded = $A.alloc<byte>(65535)
    val @(stripped_frozen, stripped_bytes) = $A.freeze<byte>(stripped)
    val decoded_len = decode_text(stripped_bytes, 0, stripped_len, decoded)
    val () = $A.drop<byte>(stripped_frozen, stripped_bytes)
    val () = $A.free<byte>($A.thaw<byte>(stripped_frozen))
    val () = _copy_into(decoded, decoded_len, out, written, 0)
    val () = $A.free<byte>(decoded)
  in written + decoded_len end
end

(* What an article's part is, by its type's letter: plain text (m, l,
   t, y), markup (h, x, g), or one that cannot be shown *)
datatype part_kind = PlainPart | MarkupPart | HiddenPart

fn _kind (kind: int): part_kind =
  if kind = 109 || kind = 108 || kind = 116 || kind = 121 then PlainPart()
  else if kind = 104 || kind = 120 || kind = 103 then MarkupPart()
  else HiddenPart()

fn _shown (kind: int): bool =
  case+ _kind(kind) of PlainPart() => true | MarkupPart() => true | HiddenPart() => false

(* A blank line at out[written], when something is shown before it *)
fn _blank_line {out_loc:agz}{written:nat | written <= ARTICLE_MAX}
  (out: !$A.arr(byte, out_loc, ARTICLE_MAX), written: int written): [w:nat | written <= w; w <= ARTICLE_MAX] int w =
  if written > 0 then _put(out, 65535, _put(out, 65535, written, 10), 10) else written

(* The part of type kind at data[at, stop) at out[written, ...), after a
   blank line when something is shown before it *)
fn _part {l,out_loc:agz}{o:addr}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop}{written:nat | written <= ARTICLE_MAX}
  (data: !$A.arrx(byte, l, n, o), at: int at, stop: int stop, kind: int,
   out: !$A.arr(byte, out_loc, ARTICLE_MAX), written: int written)
  : [after:nat | written <= after; after <= ARTICLE_MAX] int after =
  case+ _kind(kind) of
  | HiddenPart() => written
  | PlainPart() => _plain(data, at, stop, out, 65535, _blank_line(out, written))
  | MarkupPart() => _markup(data, at, stop, out, _blank_line(out, written))

(* Where the part at data[at] ends, and where the next begins: a lower
   case type's at its 0 byte (or the end), an upper case one's after
   its size (a big-endian u32 before it); the last of a sametypesequence
   runs to the end *)
fn _part_span {l:agz}{o:addr}{size:nat}{n:nat | n <= size}{at:nat | at <= n}
  (data: !$A.arrx(byte, l, size, o), n: int n, at: int at, kind: int, last: bool)
  : [start,stop,next:nat | at <= start; start <= stop; stop <= next; next <= n] @(int start, int stop, int next) =
  if last then @(at, n, n)
  else if kind >= 97 then let
    val stop = zero_at(data, at, n)
  in if stop < n then @(at, stop, stop + 1) else @(at, stop, n) end
  else if at + 4 > n then @(n, n, n)
  else let
    val size = u32_at(data, at)
  in
    if size < 0 then @(n, n, n)
    else if at + 4 + size > n then @(at + 4, n, n)
    else @(at + 4, at + 4 + size, at + 4 + size)
  end

(* The parts of an article whose types are types[type_index, types_len)
   (its sametypesequence) *)
fun _typed_parts {l,types_loc,out_loc:agz}{o:addr}{size:nat}{n:nat | n <= size}{types_size:nat}{types_len:nat | types_len <= types_size}
  {type_index:nat | type_index <= types_len}{at:nat | at <= n}{written:nat | written <= ARTICLE_MAX} .<types_len - type_index>.
  (data: !$A.arrx(byte, l, size, o), n: int n, at: int at, types: !$A.arr(byte, types_loc, types_size), types_len: int types_len,
   type_index: int type_index, out: !$A.arr(byte, out_loc, ARTICLE_MAX), written: int written, shown: bool)
  : @([after:nat | after <= ARTICLE_MAX] int after, bool) =
  if type_index >= types_len then @(written, shown)
  else let
    val kind = _byte_of(types, type_index)
    val @(start, stop, next) = _part_span(data, n, at, kind, type_index + 1 >= types_len)
    val after = _part(data, start, stop, kind, out, written)
  in _typed_parts(data, n, next, types, types_len, type_index + 1, out, after, shown || _shown(kind)) end

(* The parts of an article without a sametypesequence, from data[at]:
   each its type's byte, then its data *)
fun _tagged_parts {l,out_loc:agz}{o:addr}{size:nat}{n:nat | n <= size}{at:nat | at <= n}{written:nat | written <= ARTICLE_MAX} .<n - at>.
  (data: !$A.arrx(byte, l, size, o), n: int n, at: int at, out: !$A.arr(byte, out_loc, ARTICLE_MAX), written: int written, shown: bool)
  : @([after:nat | after <= ARTICLE_MAX] int after, bool) =
  if at >= n then @(written, shown)
  else let
    val kind = _byte_of(data, at)
    val @(start, stop, next) = _part_span(data, n, at + 1, kind, false)
    val after = _part(data, start, stop, kind, out, written)
  in _tagged_parts(data, n, next, out, after, shown || _shown(kind)) end

(* The article data[start, stop) as text at out[0, text_len), its
   types types[0, types_len) (the .ifo's sametypesequence, or none): -1
   when none of its parts is of a type that can be shown as text *)
#pub fn article_text {l,types_loc,out_loc:agz}{o:addr}{size:nat}{start,stop:nat | start <= stop; stop <= size}{types_size:nat}{types_len:nat | types_len <= types_size}
  (data: !$A.arrx(byte, l, size, o), start: int start, stop: int stop, types: !$A.arr(byte, types_loc, types_size), types_len: int types_len,
   out: !$A.arr(byte, out_loc, ARTICLE_MAX)): [text_len:int | ~1 <= text_len; text_len <= ARTICLE_MAX] int text_len

implement article_text (data, start, stop, types, types_len, out) = let
  val @(written, shown) = (if types_len > 0 then _typed_parts(data, stop, start, types, types_len, 0, out, 0, false)
    else _tagged_parts(data, stop, start, out, 0, false)): @([after:nat | after <= ARTICLE_MAX] int after, bool)
in
  if ~shown then ~1
  else utf8_cut(out, written)
end
