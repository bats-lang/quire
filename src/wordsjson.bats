(* wordsjson -- the words looked up as JSON, in a backup and in sync's file: each word an object with its id and the latest
   stamp it changed at, a deleted word its tombstone (keyword: vocabulary) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "book.sats"
staload "mem.sats"
staload "clock.sats"
staload "jsonio.sats"
staload "bytes.sats"
staload "crc.sats"
staload "fields.sats"
staload "schema.sats"
staload "record.sats"
staload "bytesarr.sats"
staload "wordrec.sats"
staload "wordimage.sats"
staload "wordstore.sats"
staload "words_rules.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

implement $P.dispose<jchunk>(chunk) = jchunk_free(chunk)
implement $P.dispose<words_read>(read) = words_read_free(read)
implement $P.dispose<word_saved>(_) = ()
implement $P.dispose<Int>(_) = ()

(* The bytes a word takes in JSON, at most: its fixed text and numbers, and its three strings at their longest, every byte
   escaped *)
#define WORD_JSON_MAX 7200

(* ============================================================
   Writing
   ============================================================ *)

fun _copy_into {source_loc,target_loc:agz}{source_size,target_size:pos}{count:nat | count <= source_size; count <= target_size}{at:nat | at + count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), target: !$A.arr(byte, target_loc, target_size), count: int count, at: int at, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, at + i, $A.get<byte>(source, i))
  in _copy_into(source, target, count, at, i + 1) end

(* The head and the tail of a sentence joined in sentence, when they fit: how long it is (0 when they do not) *)
fn _join {head_loc,tail_loc,sentence_loc:agz}{head_len,tail_len:nat | head_len < 256; tail_len < 256}
  (head: !$A.arr(byte, head_loc, head_len + 1), head_len: int head_len, tail: !$A.arr(byte, tail_loc, tail_len + 1), tail_len: int tail_len,
   sentence: !$A.arr(byte, sentence_loc, 511)): [total:nat | total <= 510] int total =
  if head_len + tail_len > 510 then 0
  else let
    val () = _copy_into(head, sentence, head_len, 0, 0)
    val () = _copy_into(tail, sentence, tail_len, head_len, 0)
  in head_len + tail_len end

(* A word as its JSON object at out[position, stop): the stop is within a word's most *)
fn _word_json {l:agz}{arena:addr}{n:nat}{c:wordx}{position:nat | position + 7100 <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, id_high: Int, id_low: Int, image: !word_image(c)): [stop:nat | stop <= position + 7100] int stop = let
  val numbers = word_image_numbers(image)
  val at = jw_lit(out, position, "{\"id\":")
  val at = jw_id(out, at, id_high, id_low)
  val at = jw_lit(out, at, ",\"modified\":")
  val at = jw_stamp(out, at, numbers.modified)
  val at = jw_lit(out, at, ",\"deleted\":")
  val at = jw_int(out, at, numbers.deleted)
in
  if numbers.deleted > 0 then jw_lit(out, at, "}")
  else let
    val at = jw_lit(out, at, ",\"book\":")
    val at = jw_id(out, at, numbers.book_high, numbers.book_low)
    val at = jw_lit(out, at, ",\"chapter\":")
    val at = jw_int(out, at, numbers.chapter)
    val at = jw_lit(out, at, ",\"node\":")
    val at = jw_int(out, at, numbers.node)
    val at = jw_lit(out, at, ",\"offset\":")
    val at = jw_int(out, at, numbers.offset)
    val at = jw_lit(out, at, ",\"first\":")
    val at = jw_int(out, at, numbers.first_minute)
    val at = jw_lit(out, at, ",\"last\":")
    val at = jw_int(out, at, numbers.last_minute)
    val at = jw_lit(out, at, ",\"lookups\":")
    val at = jw_int(out, at, numbers.lookups)
    val at = jw_lit(out, at, ",\"mastered\":")
    val at = jw_int(out, at, numbers.mastered)
    val at = jw_lit(out, at, ",\"streak\":")
    val at = jw_int(out, at, numbers.streak)
    val at = jw_lit(out, at, ",\"due\":")
    val at = jw_int(out, at, numbers.due)
    val at = jw_lit(out, at, ",\"word\":")
    val @(word, word_len) = word_image_word(image)
    val at = jw_str(out, at, word, word_len)
    val () = $A.free<byte>(word)
    val at = jw_lit(out, at, ",\"language\":")
    val @(language, language_len) = word_image_language(image)
    val at = jw_str(out, at, language, language_len)
    val () = $A.free<byte>(language)
    val at = jw_lit(out, at, ",\"sentence\":")
    val @(head, head_len) = word_image_sentence_head(image)
    val @(tail, tail_len) = word_image_sentence_tail(image)
    val sentence = $A.alloc<byte>(511)
    val total = _join(head, head_len, tail, tail_len, sentence)
    val at = jw_str(out, at, sentence, total)
    val () = $A.free<byte>(head)
    val () = $A.free<byte>(tail)
    val () = $A.free<byte>(sentence)
  in jw_lit(out, at, "}") end
end

(* The words of list as JSON objects, each after a comma but the first: the live ones, or every one with its tombstone *)
fun _words_json {l:agz}{arena:addr}{n:nat}{count:nat}{position:nat | position + 7200 * count + 1 <= n} .<count>.
  (out: !$A.arrx(byte, l, n, arena), position: int position, words: !stored_words(count), first: bool, tombstones: bool, now: Int)
  : [stop:nat | stop <= position + 7200 * count] int stop =
  case+ words of
  | StoredWordsNone() => position
  | StoredWordsSome(word, rest) =>
    (case+ word of
     | StoredWord(id_high, id_low, image) => let
         val numbers = word_image_numbers(image)
         val kept = (if numbers.deleted > 0 then (if tombstones then (now - numbers.deleted <= words_tombstone_minutes()) else false) else true): bool
       in
         if ~kept then _words_json(out, position, rest, first, tombstones, now)
         else let
           val comma = (if first then position else jw_lit(out, position, ",")): [comma:nat | position <= comma; comma <= position + 1] int comma
           val after = _word_json(out, comma, id_high, id_low, image)
         in _words_json(out, after, rest, false, tombstones, now) end
       end)

fun _words_count {count:nat} .<count>. (words: !stored_words(count)): int count =
  case+ words of
  | StoredWordsNone() => 0
  | StoredWordsSome(_, rest) => 1 + _words_count(rest)

(* The words as a JSON array in a chunk, under the key "words" after a comma: none when they cannot be had *)
fn _chunk_of {count:nat | count <= 20000} (words: !stored_words(count), count: int count, tombstones: bool): jchunk =
  case+ piece_new(64 + 7200 * count) of
  | ~NoPiece() => JNone()
  | ~Piece(owner, out) => let
      val at = jw_lit(out, 0, ",\"words\":[")
      val stop = _words_json(out, at, words, true, tombstones, $TM.epoch_minutes())
      val stop2 = jw_lit(out, stop, "]")
    in JChunk(owner, out, stop2) end

(* The chunk when there are no more words than a file takes *)
fn _chunk_guarded {count:nat} (words: !stored_words(count), count: int count, tombstones: bool): jchunk =
  if count > 20000 then JNone() else _chunk_of(words, count, tombstones)

(* The words kept, as a backup holds them: the live ones *)
#pub fn words_backup_chunk (): $P.promise(jchunk, $P.Chained)

implement words_backup_chunk () =
  $P.and_then<words_read><jchunk>(wordstore_read(), llam(read) =>
    case+ read of
    | ~WordsUnreadable() => $P.ret<jchunk>(JNone())
    | ~WordsRead(words, _) => let
        val count = _words_count(words)
        val chunk = _chunk_guarded(words, count, false)
        val () = stored_words_free(words)
      in $P.ret<jchunk>(chunk) end)

(* ============================================================
   Reading
   ============================================================ *)

(* A word's numbers as they are read: values[0] and [1] its id, [2] and [3] its book's, [4] chapter, [5] node, [6] offset,
   [7] first, [8] last, [9] lookups, [10] mastered, [11] streak, [12] due, [13] modified, [14] deleted, [15] whether it
   has an id *)
#define VALUES 16

fn _slot_of {key_loc:agz}{key_len:nat | key_len <= 16} (key: !$A.arr(byte, key_loc, 16), key_len: int key_len): [slot:int | ~1 <= slot; slot < 16] int slot =
  if jr_key_is(key, key_len, "chapter") then 4
  else if jr_key_is(key, key_len, "node") then 5
  else if jr_key_is(key, key_len, "offset") then 6
  else if jr_key_is(key, key_len, "first") then 7
  else if jr_key_is(key, key_len, "last") then 8
  else if jr_key_is(key, key_len, "lookups") then 9
  else if jr_key_is(key, key_len, "mastered") then 10
  else if jr_key_is(key, key_len, "streak") then 11
  else if jr_key_is(key, key_len, "due") then 12
  else if jr_key_is(key, key_len, "deleted") then 14
  else ~1

fun _zero_values {values_loc:agz}{i:nat | i <= VALUES} .<VALUES - i>. (values: !$A.arr(Int, values_loc, VALUES), i: int i): void =
  if i >= VALUES then () else let val () = $A.set<Int>(values, i, 0) in _zero_values(values, i + 1) end

(* The members of a word's object from position, to its closing brace: its numbers into values, its strings into the
   buffers; whether it was read whole, the strings' lengths and where it ends *)
fun _members {l,key_loc,word_loc,language_loc,sentence_loc,values_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   word_buffer: !$A.arr(byte, word_loc, 256), language_buffer: !$A.arr(byte, language_loc, 256), sentence_buffer: !$A.arr(byte, sentence_loc, 511),
   values: !$A.arr(Int, values_loc, VALUES), word_len: Int, language_len: Int, sentence_len: Int)
  : [next:int | position <= next; next <= n][w:nat | w <= 255][g:nat | g <= 255][s:nat | s <= 510] @(bool, int w, int g, int s, int next) = let
  val member_at = jr_ws(buf, n, position)
  val word_len = (if word_len < 0 then 0 else if word_len > 255 then 255 else word_len): [w:nat | w <= 255] int w
  val language_len = (if language_len < 0 then 0 else if language_len > 255 then 255 else language_len): [g:nat | g <= 255] int g
  val sentence_len = (if sentence_len < 0 then 0 else if sentence_len > 510 then 510 else sentence_len): [s:nat | s <= 510] int s
in
  if member_at >= n then @(false, word_len, language_len, sentence_len, n)
  else if jr_is(buf, n, member_at, 125) then @(true, word_len, language_len, sentence_len, member_at + 1)
  else if jr_is(buf, n, member_at, 44) then _members(buf, n, member_at + 1, key, word_buffer, language_buffer, sentence_buffer, values, word_len, language_len, sentence_len)
  else let
    val @(ok, key_len, value_at) = jr_key(buf, n, member_at, key, 16)
  in
    if ~ok then @(false, word_len, language_len, sentence_len, value_at)
    else if value_at >= n then @(false, word_len, language_len, sentence_len, value_at)
    else if jr_key_is(key, key_len, "id") then let
      val @(id_ok, high, low, after) = jr_id(buf, n, value_at)
      val () = (if id_ok then let
          val () = $A.set<Int>(values, 0, high)
          val () = $A.set<Int>(values, 1, low)
        in $A.set<Int>(values, 15, 1) end else ())
    in _members(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, word_len, language_len, sentence_len) end
    else if jr_key_is(key, key_len, "book") then let
      val @(id_ok, high, low, after) = jr_id(buf, n, value_at)
      val () = (if id_ok then let
          val () = $A.set<Int>(values, 2, high)
        in $A.set<Int>(values, 3, low) end else ())
    in _members(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, word_len, language_len, sentence_len) end
    else if jr_key_is(key, key_len, "word") then let
      val @(str_ok, length, after) = jr_str(buf, n, value_at, word_buffer, 256)
    in
      if str_ok then _members(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, length, language_len, sentence_len)
      else @(false, word_len, language_len, sentence_len, after)
    end
    else if jr_key_is(key, key_len, "language") then let
      val @(str_ok, length, after) = jr_str(buf, n, value_at, language_buffer, 256)
    in
      if str_ok then _members(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, word_len, length, sentence_len)
      else @(false, word_len, language_len, sentence_len, after)
    end
    else if jr_key_is(key, key_len, "sentence") then let
      val @(str_ok, length, after) = jr_str(buf, n, value_at, sentence_buffer, 511)
    in
      if str_ok then _members(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, word_len, language_len, length)
      else @(false, word_len, language_len, sentence_len, after)
    end
    else if jr_key_is(key, key_len, "modified") then let
      val @(stamp_ok, stamp, after) = jr_stamp(buf, n, value_at)
      val () = (if stamp_ok then let val () = stamp_seen(stamp) in $A.set<Int>(values, 13, stamp) end else ())
    in _members(buf, n, jr_skip(buf, n, value_at), key, word_buffer, language_buffer, sentence_buffer, values, word_len, language_len, sentence_len) end
    else let
      val slot = _slot_of(key, key_len)
    in
      if slot < 0 then _members(buf, n, jr_skip(buf, n, value_at), key, word_buffer, language_buffer, sentence_buffer, values, word_len, language_len, sentence_len)
      else let
        val @(int_ok, value, after) = jr_int(buf, n, value_at)
        val () = (if int_ok then $A.set<Int>(values, slot, value) else ())
      in _members(buf, n, jr_skip(buf, n, value_at), key, word_buffer, language_buffer, sentence_buffer, values, word_len, language_len, sentence_len) end
    end
  end
end

(* source[from, from + count) in a new array of count + 1 bytes *)
fun _slice_copy {l,out_loc:agz}{size,out_size:pos}{from,count:nat | from + count <= size; count < out_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, l, size), out: !$A.arr(byte, out_loc, out_size), from: int from, count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(out, i, $A.get<byte>(source, from + i))
  in _slice_copy(source, out, from, count, i + 1) end

fn _slice {l:agz}{size:pos}{from,count:nat | from + count <= size; count < 256}
  (source: !$A.arr(byte, l, size), from: int from, count: int count): [out_loc:agz] $A.arr(byte, out_loc, count + 1) = let
  val out = $A.alloc<byte>(count + 1)
  val () = _slice_copy(source, out, from, count, 0)
in out end

(* The word made of the members read: a live word needs its id and its word; a tombstone, its id and the stamp it was
   deleted at *)
fn _word_of {word_loc,language_loc,sentence_loc,values_loc:agz}{w,g,s:nat | w <= 255; g <= 255; s <= 510}
  (values: !$A.arr(Int, values_loc, VALUES), word_buffer: !$A.arr(byte, word_loc, 256), word_len: int w,
   language_buffer: !$A.arr(byte, language_loc, 256), language_len: int g, sentence_buffer: !$A.arr(byte, sentence_loc, 511), sentence_len: int s): $R.option(stored_word) =
  if $A.get<Int>(values, 15) = 0 then $R.none()
  else let
    val deleted = $A.get<Int>(values, 14)
    val live = (deleted <= 0): bool
  in
    if live && word_len <= 0 then $R.none()
    else let
      val head_len = (if sentence_len < 255 then sentence_len else 255): [h:nat | h <= 255; h <= s; s - h <= 255] int h
      val tail_len = sentence_len - head_len
      val numbers = @{book_high = $A.get<Int>(values, 2), book_low = $A.get<Int>(values, 3), lookups = $A.get<Int>(values, 9),
        first_minute = $A.get<Int>(values, 7), last_minute = $A.get<Int>(values, 8), modified = $A.get<Int>(values, 13), deleted = deleted,
        chapter = $A.get<Int>(values, 4), node = $A.get<Int>(values, 5), offset = $A.get<Int>(values, 6),
        mastered = (if $A.get<Int>(values, 10) <> 0 then 1 else 0), streak = $A.get<Int>(values, 11), due = $A.get<Int>(values, 12)}
      val word = _slice(word_buffer, 0, word_len)
      val language = _slice(language_buffer, 0, language_len)
      val head = _slice(sentence_buffer, 0, head_len)
      val tail = _slice(sentence_buffer, head_len, tail_len)
    in
      case+ word_image_make(numbers, language, language_len, head, head_len, tail, tail_len, word, word_len) of
      | ~WordImaged(image) => $R.some(StoredWord($A.get<Int>(values, 0), $A.get<Int>(values, 1), image))
      | ~WordNotImaged() => $R.none()
    end
  end

(* The words of a JSON array's items from position, to its closing bracket, onto words (at most the store holds) *)
fun _items {l,key_loc,word_loc,language_loc,sentence_loc,values_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{count:nat | count <= 10000} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 16),
   word_buffer: !$A.arr(byte, word_loc, 256), language_buffer: !$A.arr(byte, language_loc, 256), sentence_buffer: !$A.arr(byte, sentence_loc, 511),
   values: !$A.arr(Int, values_loc, VALUES), words: stored_words(count), count: int count)
  : [total:nat | total <= 10000] @(bool, stored_words(total), int total) = let
  val item_at = jr_ws(buf, n, position)
in
  if item_at >= n then @(false, words, count)
  else if jr_is(buf, n, item_at, 93) then @(true, words, count)
  else if jr_is(buf, n, item_at, 44) then _items(buf, n, item_at + 1, key, word_buffer, language_buffer, sentence_buffer, values, words, count)
  else if jr_is(buf, n, item_at, 123) then let
    val () = _zero_values(values, 0)
    val @(ok, word_len, language_len, sentence_len, after) = _members(buf, n, item_at + 1, key, word_buffer, language_buffer, sentence_buffer, values, 0, 0, 0)
  in
    if ~ok then @(false, words, count)
    else if count >= 10000 then _items(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, words, count)
    else (case+ _word_of(values, word_buffer, word_len, language_buffer, language_len, sentence_buffer, sentence_len) of
      | ~$R.some(word) => _items(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, StoredWordsSome(word, words), count + 1)
      | ~$R.none() => _items(buf, n, after, key, word_buffer, language_buffer, sentence_buffer, values, words, count))
  end
  else @(false, words, count)
end

(* Where the value of the top-level member "words" of the JSON file buf[0, n) starts, or -1 *)
#pub fn words_array_at {l:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n): [at:int | ~1 <= at; at < n] int at

implement words_array_at (buf, n) = let
  val start = jr_ws(buf, n, 0)
in
  if start >= n then ~1
  else if ~jr_is(buf, n, start, 123) then ~1
  else let
    val key = $A.alloc<byte>(16)
    val at = jr_member(buf, n, start + 1, key, "words")
    val () = $A.free<byte>(key)
  in at end
end

(* The words of the array at position of the JSON file (checked here as it is read): unreadable when the array is not
   whole, else the words, a word it cannot make left out *)
#pub fn words_parse {l:agz}{owner:addr}{n:nat}{position:nat | position <= n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position): words_read

implement words_parse (buf, n, position) =
  if position >= n then WordsUnreadable()
  else if ~jr_is(buf, n, position, 91) then WordsUnreadable()
  else let
    val key = $A.alloc<byte>(16)
    val word_buffer = $A.alloc<byte>(256)
    val language_buffer = $A.alloc<byte>(256)
    val sentence_buffer = $A.alloc<byte>(511)
    val values = $A.alloc<Int>(VALUES)
    val @(ok, words, count) = _items(buf, n, position + 1, key, word_buffer, language_buffer, sentence_buffer, values, StoredWordsNone(), 0)
    val () = $A.free<byte>(key)
    val () = $A.free<byte>(word_buffer)
    val () = $A.free<byte>(language_buffer)
    val () = $A.free<byte>(sentence_buffer)
    val () = $A.free<Int>(values)
  in
    if ok then WordsRead(words, count)
    else let val () = stored_words_free(words) in WordsUnreadable() end
  end

(* ============================================================
   Putting words into the store
   ============================================================ *)

(* The words of the JSON file buf[0, n): those of its "words" member, none when it has none, unreadable when the member is not
   a whole array *)
#pub fn words_from_file {l:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n): words_read

implement words_from_file (buf, n) = let
  val at = words_array_at(buf, n)
in
  if at < 0 then WordsRead(StoredWordsNone(), 0)
  else words_parse(buf, n, at)
end

(* Each word of words edited into the store, one after another, by merging (the latest change wins) or as it is given;
   the number done *)
fun _apply {count:nat} .<count>. (words: stored_words(count), replace: bool, done: Int): $P.promise(Int, $P.Chained) =
  case+ words of
  | ~StoredWordsNone() => $P.ret<Int>(done)
  | ~StoredWordsSome(word, rest) => let
      val ~StoredWord(id_high, id_low, image) = word
      val edit = (if replace then PutWord(image, stamp_now()) else MergeWord(image)): word_edit
    in
      $P.and_then<word_saved><Int>(wordstore_edit(id_high, id_low, edit), llam(_) => _apply(rest, replace, done + 1))
    end

(* Whether words holds the word with the id *)
fun _holds {count:nat} .<count>. (words: !stored_words(count), high: Int, low: Int): bool =
  case+ words of
  | StoredWordsNone() => false
  | StoredWordsSome(word, rest) =>
    (case+ word of
     | StoredWord(word_high, word_low, _) =>
       if word_high = high then (if word_low = low then true else _holds(rest, high, low)) else _holds(rest, high, low))

(* Each live word of nearby that words does not hold deleted, as a snapshot put back leaves none of what it did not have *)
fun _delete_missing {count,kept:nat} .<count>. (nearby: stored_words(count), words: !stored_words(kept)): void =
  case+ nearby of
  | ~StoredWordsNone() => ()
  | ~StoredWordsSome(word, rest) => let
      val ~StoredWord(high, low, image) = word
      val numbers = word_image_numbers(image)
      val () = word_image_free(image)
      val () = (if numbers.deleted > 0 then ()
        else if _holds(words, high, low) then ()
        (* ignored: a word that is not deleted stays, and is deleted by the next restore *)
        else $P.finish<word_saved>(wordstore_edit(high, low, DeleteWord($TM.epoch_minutes(), stamp_now())), llam(_) => ()))
    in _delete_missing(rest, words) end

(* The words of a file put into the store: merged by the latest change of each, or, when replace, the store made to hold
   exactly these (what it holds that they do not is deleted), as a snapshot put back does. The number put *)
#pub fn words_restore (read: words_read, replace: bool): $P.promise(Int, $P.Chained)

implement words_restore (read, replace) =
  case+ read of
  | ~WordsUnreadable() => $P.ret<Int>(~1)
  | ~WordsRead(words, _) =>
    if ~replace then _apply(words, false, 0)
    else
      $P.and_then<words_read><Int>(wordstore_read(), llam(kept) =>
        case+ kept of
        | ~WordsUnreadable() => let val () = stored_words_free(words) in $P.ret<Int>(~1) end
        | ~WordsRead(nearby, _) => let
            val () = _delete_missing(nearby, words)
          in _apply(words, true, 0) end)


(* ============================================================
   Sync: the words of two devices, merged
   ============================================================ *)

datavtype taken =
  | NotTaken of ()
  | Taken of stored_word

(* words without the word of the id, which is given when there is one *)
fun _take_id {count:nat} .<count>. (words: stored_words(count), high: Int, low: Int): [rest:nat] @(taken, stored_words(rest)) =
  case+ words of
  | ~StoredWordsNone() => @(NotTaken(), StoredWordsNone())
  | ~StoredWordsSome(word, rest) => let
      val ~StoredWord(word_high, word_low, image) = word
    in
      if word_high = high then (if word_low = low then @(Taken(StoredWord(word_high, word_low, image)), rest)
        else let
          val @(found, left) = _take_id(rest, high, low)
        in @(found, StoredWordsSome(StoredWord(word_high, word_low, image), left)) end)
      else let
        val @(found, left) = _take_id(rest, high, low)
      in @(found, StoredWordsSome(StoredWord(word_high, word_low, image), left)) end
    end

fun _append {count,kept:nat} .<count>. (words: stored_words(count), onto: stored_words(kept)): [total:nat] stored_words(total) =
  case+ words of
  | ~StoredWordsNone() => onto
  | ~StoredWordsSome(word, rest) => _append(rest, StoredWordsSome(word, onto))

fn _modified_of (word: !stored_word): Int =
  case+ word of
  | StoredWord(_, _, image) => let
      val numbers = word_image_numbers(image)
    in numbers.modified end

fn _image_modified {c:wordx} (image: !word_image(c)): Int = let
  val numbers = word_image_numbers(image)
in numbers.modified end

(* The words of both devices: of each id the one changed later (this device's when they were changed together) *)
fun _merged {here,there,done:nat} .<there>. (nearby: stored_words(here), remote: stored_words(there), acc: stored_words(done)): [total:nat] stored_words(total) =
  case+ remote of
  | ~StoredWordsNone() => _append(nearby, acc)
  | ~StoredWordsSome(word, rest) => let
      val ~StoredWord(high, low, image) = word
      val @(found, left) = _take_id(nearby, high, low)
    in
      case+ found of
      | ~NotTaken() => _merged(left, rest, StoredWordsSome(StoredWord(high, low, image), acc))
      | ~Taken(here_word) =>
        if _image_modified(image) > _modified_of(here_word) then let
          val () = stored_word_free(here_word)
        in _merged(left, rest, StoredWordsSome(StoredWord(high, low, image), acc)) end
        else let
          val () = word_image_free(image)
        in _merged(left, rest, StoredWordsSome(here_word, acc)) end
    end

(* The words of this device and of the file, merged, as the JSON the file is written with, under "words" after a comma:
   the file's alone when this device's cannot be read *)
#pub fn words_sync_chunk (remote: words_read): $P.promise(jchunk, $P.Chained)

implement words_sync_chunk (remote) =
  $P.and_then<words_read><jchunk>(wordstore_read(), llam(kept) =>
    case+ kept of
    | ~WordsUnreadable() =>
      (case+ remote of
       | ~WordsUnreadable() => $P.ret<jchunk>(JNone())
       | ~WordsRead(words, _) => let
           val count = _words_count(words)
           val chunk = _chunk_guarded(words, count, true)
           val () = stored_words_free(words)
         in $P.ret<jchunk>(chunk) end)
    | ~WordsRead(nearby, _) => let
        val there = (case+ remote of
          | ~WordsUnreadable() => StoredWordsNone()
          | ~WordsRead(words, _) => words): [there:nat] stored_words(there)
        val both = _merged(nearby, there, StoredWordsNone())
        val count = _words_count(both)
        val chunk = _chunk_guarded(both, count, true)
        val () = stored_words_free(both)
      in $P.ret<jchunk>(chunk) end)


end (* #target wasm *)
