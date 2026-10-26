(* wordstore -- the words looked up, in storage: one checksummed record for each word and language ("words/<id>", the id as
   14 hex digits), changed only by an update that reads the record in the same transaction (keyword: vocabulary) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use sha256 as SHA
#use str as S

staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload "bytes.sats"
staload "crc.sats"
staload "fields.sats"
staload "schema.sats"
staload "record.sats"
staload "bytesarr.sats"
staload "wordrec.sats"
staload "wordimage.sats"
staload "book.sats"
staload "mem.sats"
staload "stored_key.sats"
staload "words_rules.sats"
staload "library.sats"

implement $P.dispose<$IDB.stored>(_) = ()

(* A record longer than this is not a word's *)
#define WORD_RECORD_MAX 4096

(* ============================================================
   Ids and keys
   ============================================================ *)

(* A byte lower-cased when it is an ASCII capital *)
fn _lower {code:nat | code < 256} (code: int code): [lowered:nat | lowered < 256] int lowered =
  if code >= 65 then (if code <= 90 then code + 32 else code) else code

(* text[start, start + count) := the word's first count bytes, lower-cased *)
fun _put_lowered {text_loc,word_loc:agz}{word_size:pos}{count:nat | count <= word_size}{start:nat | start + count <= 128}{i:nat | i <= count} .<count - i>.
  (text: !$A.arr(byte, text_loc, 128), word: !$A.arr(byte, word_loc, word_size), count: int count, start: int start, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.write_byte(text, start + i, _lower($AR.low_byte(byte2int0($A.get<byte>(word, i)))))
  in _put_lowered(text, word, count, start, i + 1) end

(* text[start, start + count) := the first count bytes of a language code *)
fun _put_code {text_loc,language_loc:agz}{language_size:pos}{count:nat | count <= language_size}{start:nat | start + count <= 128}{i:nat | i <= count} .<count - i>.
  (text: !$A.arr(byte, text_loc, 128), language: !$A.arr(byte, language_loc, language_size), count: int count, start: int start, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.write_byte(text, start + i, $AR.low_byte(byte2int0($A.get<byte>(language, i))))
  in _put_code(text, language, count, start, i + 1) end

(* A word's id: the first 14 hex digits of the SHA-256 of the word (its ASCII capitals lower-cased), a colon and its
   language, as two halves of 28 bits as a book's id is: the same on every device, so sync meets the same word *)
#pub fn wordstore_id {word_loc,language_loc:agz}{word_size,language_size:pos}{word_len:nat | word_len <= word_size; word_len <= 64}{language_len:nat | language_len <= language_size; language_len <= 36}
  (word: !$A.arr(byte, word_loc, word_size), word_len: int word_len, language: !$A.arr(byte, language_loc, language_size), language_len: int language_len): @(Int, Int)

implement wordstore_id (word, word_len, language, language_len) = let
  val text = $A.alloc<byte>(128)
  val () = _put_lowered(text, word, word_len, 0, 0)
  val () = $A.write_byte(text, word_len, 58)
  val () = _put_code(text, language, language_len, word_len + 1, 0)
  val hasher = $SHA.proved_init()
  val () = $SHA.proved_update(hasher, text, word_len + 1 + language_len)
  val digest = $A.alloc<byte>(64)
  val () = $SHA.proved_finish(hasher, digest)
  val () = $A.free<byte>(text)
  val id = lib_id_of_hex(digest)
  val () = $A.free<byte>(digest)
in id end

(* The key of a word's record: "words/" and the 14 hex digits of its id *)
#pub fn wordstore_key (id_high: Int, id_low: Int): [l:agz] $A.arr(byte, l, 20)

implement wordstore_key (id_high, id_low) = let
  val key = $A.alloc<byte>(20)
  val () = $A.write_text(key, 0, $A.text_lit("words/"), 6)
  val hex = lib_key(119, id_high, id_low)
  fun copy {l:agz}{hex_loc:agz}{i:nat | i <= 14} .<14 - i>. (key: !$A.arr(byte, l, 20), hex: !$A.arr(byte, hex_loc, 15), i: int i): void =
    if i >= 14 then ()
    else let
      val () = $A.set<byte>(key, 6 + i, $A.get<byte>(hex, 1 + i))
    in copy(key, hex, i + 1) end
  val () = copy(key, hex, 0)
  val () = $A.free<byte>(hex)
in key end

(* ============================================================
   Words, read
   ============================================================ *)

(* A word of the store: its id and what it holds *)
#pub datavtype stored_word =
  | {contents:wordx} StoredWord of (Int, Int, word_image(contents))

#pub datavtype stored_words(int) =
  | StoredWordsNone(0) of ()
  | {count:nat} StoredWordsSome(count + 1) of (stored_word, stored_words(count))

(* What reading the words came to: they could not be read (nothing may be said of them), or the words *)
#pub datavtype words_read =
  | WordsUnreadable of ()
  | {count:nat} WordsRead of (stored_words(count), int count)

#pub fun stored_word_free (word: stored_word): void
implement stored_word_free (word) = case+ word of ~StoredWord(_, _, image) => word_image_free(image)

#pub fun stored_words_free {count:nat} (words: stored_words(count)): void
implement stored_words_free {count} (words) = let
  fun free_each {count:nat} .<count>. (words: stored_words(count)): void =
    case+ words of
    | ~StoredWordsNone() => ()
    | ~StoredWordsSome(word, rest) => let val () = stored_word_free(word) in free_each(rest) end
in free_each(words) end

#pub fun words_read_free (read: words_read): void
implement words_read_free (read) =
  case+ read of
  | ~WordsUnreadable() => ()
  | ~WordsRead(words, _) => stored_words_free(words)

implement $P.dispose<words_read>(read) = words_read_free(read)

fn _hex_value {byte_value:nat | byte_value < 256} (byte_value: int byte_value): [value:int | ~1 <= value; value < 16] int value =
  if byte_value >= 48 then (if byte_value <= 57 then byte_value - 48
    else if byte_value >= 97 then (if byte_value <= 102 then byte_value - 87 else ~1) else ~1)
  else ~1

(* The 7 hex digits at source[at, at + 7) as a number, or -1 when one is not a digit *)
fn _seven_hex_at {l:agz}{owner:addr}{n:nat}{at:nat | at + 7 <= n}
  (source: !$A.arrx(byte, l, n, owner), at: int at): [value:int | ~1 <= value] int value = let
  fun accumulate {i:nat | i <= 7}{total:nat} .<7 - i>. (source: !$A.arrx(byte, l, n, owner), i: int i, total: int total): [value:int | ~1 <= value] int value =
    if i >= 7 then total
    else let
      val digit = _hex_value($AR.low_byte(byte2int0($A.get<byte>(source, at + i))))
    in
      if digit < 0 then ~1 else accumulate(source, i + 1, total * 16 + digit)
    end
in accumulate(source, 0, 0) end

fn _u16_at {l:agz}{owner:addr}{n:nat}{at:nat | at + 2 <= n}
  (source: !$A.arrx(byte, l, n, owner), at: int at): [value:nat | value < 65536] int value =
  $AR.low_byte(byte2int0($A.get<byte>(source, at))) + 256 * $AR.low_byte(byte2int0($A.get<byte>(source, at + 1)))

(* The little-endian u32 at source[at, at + 4), or -1 when it is 2 to the 28 or more *)
fn _u32_at {l:agz}{owner:addr}{n:nat}{at:nat | at + 4 <= n}
  (source: !$A.arrx(byte, l, n, owner), at: int at): [value:int | ~1 <= value; value < 268435456] int value = let
  val first_byte = $AR.low_byte(byte2int0($A.get<byte>(source, at)))
  val second_byte = $AR.low_byte(byte2int0($A.get<byte>(source, at + 1)))
  val third_byte = $AR.low_byte(byte2int0($A.get<byte>(source, at + 2)))
  val fourth_byte = $AR.low_byte(byte2int0($A.get<byte>(source, at + 3)))
in
  if fourth_byte >= 16 then ~1 else first_byte + 256 * (second_byte + 256 * (third_byte + 256 * fourth_byte))
end

(* The id of the key source[at, at + 20) when it is "words/" and 14 hex digits, else -1 in the first *)
fn _key_id {l:agz}{owner:addr}{n:nat}{at:nat | at + 20 <= n}
  (source: !$A.arrx(byte, l, n, owner), at: int at): @(Int, Int) = let
  fun prefix_is {i:nat | i <= 6} .<6 - i>. (source: !$A.arrx(byte, l, n, owner), i: int i): bool =
    if i >= 6 then true
    else let
      val expected = (if i = 0 then 119 else if i = 1 then 111 else if i = 2 then 114 else if i = 3 then 100 else if i = 4 then 115 else 47): int
    in
      if byte2int0($A.get<byte>(source, at + i)) = expected then prefix_is(source, i + 1) else false
    end
in
  if ~prefix_is(source, 0) then @(~1, 0)
  else let
    val high = _seven_hex_at(source, at + 6)
    val low = _seven_hex_at(source, at + 13)
  in if high < 0 then @(~1, 0) else if low < 0 then @(~1, 0) else @(high, low) end
end

(* The word of the record at piece[at, at + len) when it can be used: read whole, or with what it lost standing in *)
datavtype word_found =
  | {contents:wordx} WordFound of word_image(contents)
  | WordNotFound of ()

fn _read_word {l:agz}{owner:addr}{n:nat}{at,len:nat | at + len <= n}
  (piece: !$A.arrx(byte, l, n, owner), at: int at, len: int len): word_found =
  if len <= 0 then WordNotFound()
  else if len > WORD_RECORD_MAX then WordNotFound()
  else let
    val list = blist_of_array(piece, at, len)
    val (_ | read) = word_record_read(list)
  in
    case+ read of
    | ~WR_ok(record) => let
        val image = word_record_image(record)
        val () = word_record_free(record)
      in WordFound(image) end
    | ~WR_loss(record, lost) => let
        val image = word_record_image(record)
        val () = word_record_free(record)
        val () = lostv_free(lost)
      in WordFound(image) end
    | ~WR_notquire() => WordNotFound()
    | ~WR_newer() => WordNotFound()
    | ~WR_damaged() => WordNotFound()
  end

(* The words of the blob get_prefix gave, from at on, onto words *)
fun _read_entries {l:agz}{owner:addr}{n:nat}{at:nat | at <= n}{count:nat | count <= WORDS_MOST} .<n - at>.
  (piece: !$A.arrx(byte, l, n, owner), size: int n, at: int at, words: stored_words(count), count: int count)
  : [total:nat | total <= WORDS_MOST] @(stored_words(total), int total) =
  if at + 2 > size then @(words, count)
  else let
    val key_len = _u16_at(piece, at)
    val key_at = at + 2
  in
    if key_at + key_len + 4 > size then @(words, count)
    else let
      val value_len = _u32_at(piece, key_at + key_len)
      val value_at = key_at + key_len + 4
    in
      if value_len < 0 then @(words, count)
      else if value_at + value_len > size then @(words, count)
      else if key_len <> 20 then _read_entries(piece, size, value_at + value_len, words, count)
      else if count >= 10000 then @(words, count)
      else let
        val @(id_high, id_low) = _key_id(piece, key_at)
      in
        if id_high < 0 then _read_entries(piece, size, value_at + value_len, words, count)
        else (case+ _read_word(piece, value_at, value_len) of
          | ~WordFound(image) =>
            _read_entries(piece, size, value_at + value_len, StoredWordsSome(StoredWord(id_high, id_low, image), words), count + 1)
          | ~WordNotFound() => _read_entries(piece, size, value_at + value_len, words, count))
      end
    end
  end

(* The words kept: every record under "words/" in one view; they are not in any order, and a deleted word's tombstone is
   among them *)
#pub fun wordstore_read (): $P.promise(words_read, $P.Chained)

implement wordstore_read () = let
  val key_prefix = $A.alloc<byte>(6)
  val () = $A.write_text(key_prefix, 0, $A.text_lit("words/"), 6)
  val @(key_prefix_frozen, key_prefix_bytes) = $A.freeze<byte>(key_prefix)
  val stored = $IDB.idb_get_prefix(key_prefix_bytes, 6)
  val () = release_bytes(key_prefix_frozen, key_prefix_bytes)
in
  $P.and_then<$IDB.lookup><words_read>(stored, llam(found) =>
    case+ found of
    | ~$IDB.Unreadable(cause) => let val () = $IDB.unreadable_cause_free(cause) in $P.ret<words_read>(WordsUnreadable()) end
    | ~$IDB.Absent() => $P.ret<words_read>(WordsRead(StoredWordsNone(), 0))
    | ~$IDB.Found(blob) =>
      (case+ lookup_content($IDB.Found(blob)) of
       | ~StoredContent(owner, piece, size) => let
           val @(words, count) = _read_entries(piece, size, 0, StoredWordsNone(), 0)
           val () = piece_free(owner, piece)
         in $P.ret<words_read>(WordsRead(words, count)) end
       | ~NoStoredContent() => $P.ret<words_read>(WordsRead(StoredWordsNone(), 0))
       | ~ContentUnreadable() => $P.ret<words_read>(WordsUnreadable())))
end

(* ============================================================
   Words, changed
   ============================================================ *)

(* What an edit of a word's record came to *)
#pub datatype word_saved =
  | WordSaved        (* the record is stored as the edit made it *)
  | WordKept         (* the edit changed nothing: no such word, or it was changed later elsewhere *)
  | WordFull         (* a new word was not kept: as many are kept as the store holds *)
  | WordRefused      (* the stored record is not one this Quire can change: nothing was written *)
  | WordNotSaved     (* it could not be read or written: nothing was kept *)

implement $P.dispose<word_saved>(_) = ()

(* How many records are kept, counted when the store is read at start and followed as words are made and dropped *)
val _kept = ref<int>(0)

#pub fn wordstore_kept (): int
implement wordstore_kept () = !_kept

#pub fn wordstore_kept_set (count: int): void
implement wordstore_kept_set (count) = !_kept := count

(* What to do to a word's record *)
#pub datavtype word_edit =
  | {contents:wordx} NoteLookup of word_image(contents)     (* a lookup: a new word, or the lookup counted in the one kept *)
  | {contents:wordx} PutWord of (word_image(contents), Int) (* the word as it is given, at this stamp, whatever is kept (Undo) *)
  | {contents:wordx} MergeWord of word_image(contents)      (* the word of another device: taken when it changed later *)
  | MasterWord of (Int)                                      (* mastered, at this stamp *)
  | LearnWordAgain of (Int, Int)                             (* learning again from now: the minute, the stamp *)
  | ReviewWord of (bool, Int, Int)                           (* reviewed, known or not: at this minute and stamp *)
  | DeleteWord of (Int, Int)                                 (* deleted at this minute and stamp: only the tombstone is kept *)

datavtype word_made =
  | {contents:wordx} Made of word_image(contents)
  | NotMade of ()

(* The image with these numbers and its own strings *)
fn _renumbered {contents:wordx} (image: !word_image(contents), numbers: word_numbers): word_made = let
  val @(language, language_len) = word_image_language(image)
  val @(head, head_len) = word_image_sentence_head(image)
  val @(tail, tail_len) = word_image_sentence_tail(image)
  val @(word, word_len) = word_image_word(image)
in
  case+ word_image_make(numbers, language, language_len, head, head_len, tail, tail_len, word, word_len) of
  | ~WordImaged(made) => Made(made)
  | ~WordNotImaged() => NotMade()
end

(* The image with these numbers and the strings of another image *)
fn _renumbered_from {contents:wordx} (strings: !word_image(contents), numbers: word_numbers): word_made = _renumbered(strings, numbers)

(* A deleted word's tombstone: its numbers cleared but when it changed and was deleted, and no strings *)
fn _tombstone (minute: Int, stamp: Int): word_made = let
  val numbers = @{book_high = 0, book_low = 0, lookups = 0, first_minute = 0, last_minute = 0, modified = stamp, deleted = minute,
    chapter = 0, node = 0, offset = 0, mastered = 0, streak = 0, due = 0}
in
  case+ word_image_make(numbers, $A.alloc<byte>(1), 0, $A.alloc<byte>(1), 0, $A.alloc<byte>(1), 0, $A.alloc<byte>(1), 0) of
  | ~WordImaged(made) => Made(made)
  | ~WordNotImaged() => NotMade()
end

(* A word's image as the bytes of its record, kept in a new record or patched into the one read (a newer Quire's chunks stay) *)
datavtype word_bytes =
  | {l:agz}{n:pos | n <= WORD_RECORD_MAX} WordBytes of ($A.arr(byte, l, n), int n)
  | NoWordBytes of ()

fn _bytes_of_record {contents:wordx}{version,least_version:int}{chunks:extras} (record: !wordrecord(contents, version, least_version, chunks)): word_bytes = let
  val (_ | list) = word_record_write(record)
  val (_ | count) = blist_len(list)
in
  if count <= 0 then let val () = blist_free(list) in NoWordBytes() end
  else if count > WORD_RECORD_MAX then let val () = blist_free(list) in NoWordBytes() end
  else let
    val bytes = blist_to_buffer(list, count)
    val () = blist_free(list)
  in WordBytes(bytes, count) end
end

(* What an edit makes of the word read: the image to write, or nothing to write *)
datavtype applied =
  | {contents:wordx} Apply of word_image(contents)
  | NoApply of ()

(* The edit applied to the word read, own (consumed) *)
fn _apply {own_value:wordx} (edit: word_edit, own: !word_image(own_value)): applied = let
  val own_numbers = word_image_numbers(own)
in
  case+ edit of
  | ~NoteLookup(fresh) =>
    if own_numbers.deleted > 0 then Apply(fresh)
    else let
      val fresh_numbers = word_image_numbers(fresh)
      var merged: word_numbers = fresh_numbers
      val () = merged.lookups := own_numbers.lookups + 1
      val () = merged.first_minute := (if own_numbers.first_minute > 0 then own_numbers.first_minute else fresh_numbers.first_minute)
      val () = merged.mastered := own_numbers.mastered
      val () = merged.streak := own_numbers.streak
      val () = merged.due := own_numbers.due
      val made = _renumbered(fresh, merged)
      val () = word_image_free(fresh)
    in case+ made of ~Made(image) => Apply(image) | ~NotMade() => NoApply() end
  | ~PutWord(image, stamp) => let
      var changed: word_numbers = word_image_numbers(image)
      val () = changed.modified := stamp
      val () = changed.deleted := 0
      val made = _renumbered(image, changed)
      val () = word_image_free(image)
    in case+ made of ~Made(restamped) => Apply(restamped) | ~NotMade() => NoApply() end
  | ~MergeWord(image) => let
      val image_numbers = word_image_numbers(image)
    in
      if own_numbers.modified < image_numbers.modified then Apply(image)
      else let val () = word_image_free(image) in NoApply() end
    end
  | ~MasterWord(stamp) =>
    if own_numbers.deleted > 0 then NoApply()
    else let
      var changed: word_numbers = own_numbers
      val () = changed.mastered := 1
      val () = changed.modified := stamp
    in case+ _renumbered(own, changed) of ~Made(image) => Apply(image) | ~NotMade() => NoApply() end
  | ~LearnWordAgain(now, stamp) =>
    if own_numbers.deleted > 0 then NoApply()
    else let
      var changed: word_numbers = own_numbers
      val () = changed.mastered := 0
      val () = changed.streak := 0
      val () = changed.due := now
      val () = changed.modified := stamp
    in case+ _renumbered(own, changed) of ~Made(image) => Apply(image) | ~NotMade() => NoApply() end
  | ~ReviewWord(known, now, stamp) =>
    if own_numbers.deleted > 0 then NoApply()
    else if own_numbers.mastered <> 0 then NoApply()
    else let
      var changed: word_numbers = own_numbers
      val @(streak, due) = words_review_next(own_numbers.streak, known, now)
      val () = changed.streak := g1ofg0(streak)
      val () = changed.due := g1ofg0(due)
      val () = changed.modified := stamp
    in case+ _renumbered(own, changed) of ~Made(image) => Apply(image) | ~NotMade() => NoApply() end
  | ~DeleteWord(minute, stamp) =>
    if own_numbers.deleted > 0 then NoApply()
    else (case+ _tombstone(minute, stamp) of ~Made(image) => Apply(image) | ~NotMade() => NoApply())
end

fn _create_unchecked {contents:wordx} (image: word_image(contents), answer: $P.resolver(word_saved)): $IDB.writeback = let
  val record = word_record_new(image)
  val () = word_image_free(image)
in
  case+ _bytes_of_record(record) of
  | ~WordBytes(bytes, count) => let
      val () = word_record_free(record)
      val () = !_kept := !_kept + 1
      val () = $P.resolve<word_saved>(answer, WordSaved())
    in $IDB.Write(bytes, count) end
  | ~NoWordBytes() => let
      val () = word_record_free(record)
      val () = $P.resolve<word_saved>(answer, WordNotSaved())
    in $IDB.Keep() end
end

(* A new word: kept unless as many are kept as the store holds *)
fn _create {contents:wordx} (image: word_image(contents), answer: $P.resolver(word_saved)): $IDB.writeback =
  if !_kept >= words_most() then let
    val () = word_image_free(image)
    val () = $P.resolve<word_saved>(answer, WordFull())
  in $IDB.Keep() end
  else _create_unchecked(image, answer)


#pub fun word_edit_free (edit: word_edit): void
implement word_edit_free (edit) =
  case+ edit of
  | ~NoteLookup(image) => word_image_free(image)
  | ~PutWord(image, _) => word_image_free(image)
  | ~MergeWord(image) => word_image_free(image)
  | ~MasterWord(_) => ()
  | ~LearnWordAgain(_, _) => ()
  | ~ReviewWord(_, _, _) => ()
  | ~DeleteWord(_, _) => ()

(* The edit applied to the record read: the image it makes patched into the record, which keeps a newer Quire's chunks *)
fn _decide_record {contents:wordx}{version,least_version:int}{chunks:extras}
  (record: wordrecord(contents, version, least_version, chunks), edit: word_edit, answer: $P.resolver(word_saved)): $IDB.writeback = let
  val own = word_record_image(record)
  val applied = _apply(edit, own)
  val () = word_image_free(own)
in
  case+ applied of
  | ~NoApply() => let
      val () = word_record_free(record)
      val () = $P.resolve<word_saved>(answer, WordKept())
    in $IDB.Keep() end
  | ~Apply(image) => let
      val patched = word_record_patch(record, image, word_group_all())
      val () = word_image_free(image)
    in
      case+ _bytes_of_record(patched) of
      | ~WordBytes(bytes, count) => let
          val () = word_record_free(patched)
          val () = $P.resolve<word_saved>(answer, WordSaved())
        in $IDB.Write(bytes, count) end
      | ~NoWordBytes() => let
          val () = word_record_free(patched)
          val () = $P.resolve<word_saved>(answer, WordNotSaved())
        in $IDB.Keep() end
    end
end

(* A record written whole for a word that is not stored, or whose record cannot be read as one *)
fn _decide_absent (edit: word_edit, answer: $P.resolver(word_saved)): $IDB.writeback =
  case+ edit of
  | ~NoteLookup(image) => _create(image, answer)
  | ~PutWord(image, stamp) => let
      var changed: word_numbers = word_image_numbers(image)
      val () = changed.modified := stamp
      val () = changed.deleted := 0
      val made = _renumbered(image, changed)
      val () = word_image_free(image)
    in case+ made of ~Made(restamped) => _create_unchecked(restamped, answer) | ~NotMade() => let val () = $P.resolve<word_saved>(answer, WordNotSaved()) in $IDB.Keep() end end
  | ~MergeWord(image) => _create(image, answer)
  | ~MasterWord(_) => let val () = $P.resolve<word_saved>(answer, WordKept()) in $IDB.Keep() end
  | ~LearnWordAgain(_, _) => let val () = $P.resolve<word_saved>(answer, WordKept()) in $IDB.Keep() end
  | ~ReviewWord(_, _, _) => let val () = $P.resolve<word_saved>(answer, WordKept()) in $IDB.Keep() end
  | ~DeleteWord(_, _) => let val () = $P.resolve<word_saved>(answer, WordKept()) in $IDB.Keep() end


(* What an update of a word's record decides, from what it read *)
fn _decide (found: $IDB.lookup, edit: word_edit, answer: $P.resolver(word_saved)): $IDB.writeback =
  case+ found of
  | ~$IDB.Unreadable(cause) => let
      val () = $IDB.unreadable_cause_free(cause)
      val () = word_edit_free(edit)
      val () = $P.resolve<word_saved>(answer, WordNotSaved())
    in $IDB.Keep() end
  | ~$IDB.Absent() => _decide_absent(edit, answer)
  | ~$IDB.Found(blob) => let
      val size = $BD.blob_len(blob)
    in
      if size <= 0 then let
        val () = $BD.blob_free(blob)
      in _decide_absent(edit, answer) end
      else if size > WORD_RECORD_MAX then let
        val () = $BD.blob_free(blob)
        val () = word_edit_free(edit)
        val () = $P.resolve<word_saved>(answer, WordRefused())
      in $IDB.Keep() end
      else let
        val previous = $A.alloc<byte>(size)
        val () = $BD.blob_read(blob, 0, previous, size)
        val () = $BD.blob_free(blob)
        val list = blist_of_array(previous, 0, size)
        val (_ | read) = word_record_read(list)
        val () = $A.free<byte>(previous)
      in
        case+ read of
        | ~WR_ok(record) => _decide_record(record, edit, answer)
        | ~WR_loss(record, lost) => let val () = lostv_free(lost) in _decide_record(record, edit, answer) end
        | ~WR_notquire() => let
            val () = word_edit_free(edit)
            val () = $P.resolve<word_saved>(answer, WordRefused())
          in $IDB.Keep() end
        | ~WR_newer() => let
            val () = word_edit_free(edit)
            val () = $P.resolve<word_saved>(answer, WordRefused())
          in $IDB.Keep() end
        | ~WR_damaged() => _decide_absent(edit, answer)
      end
    end

(* An answer whose update did not commit is not the answer *)
fn _unsaved (answer: $P.promise(word_saved, $P.Pending)): $P.promise(word_saved, $P.Chained) =
  $P.and_then<word_saved><word_saved>(answer, llam(_) => $P.ret<word_saved>(WordNotSaved()))

(* The word id_high, id_low edited: its record is read in the same transaction, the edit applied to it and the result
   written; two edits of one word never overwrite each other's change *)
#pub fun wordstore_edit (id_high: Int, id_low: Int, edit: word_edit): $P.promise(word_saved, $P.Chained)

implement wordstore_edit (id_high, id_low, edit) = let
  val key = wordstore_key(id_high, id_low)
  val @(answer, resolver) = $P.create<word_saved>()
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val updating = $IDB.idb_update(key_bytes, 20, llam(found) => _decide(found, edit, resolver))
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.updated><word_saved>(updating, llam(updated) =>
    case+ updated of
    | ~$IDB.Updated() => $P.vow(answer)
    | ~$IDB.KeptAsRead() => $P.vow(answer)
    | ~$IDB.UpdateUnreadable(cause) => let val () = $IDB.unreadable_cause_free(cause) in _unsaved(answer) end
    | ~$IDB.NotUpdated(cause) => let val () = $IDB.write_failure_free(cause) in _unsaved(answer) end)
end

(* A word's record deleted for good (a tombstone kept long enough), the count of the records kept following *)
#pub fun wordstore_forget (id_high: Int, id_low: Int): $P.promise($IDB.stored, $P.Chained)

implement wordstore_forget (id_high, id_low) = let
  val key = wordstore_key(id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val deleting = $IDB.idb_delete(key_bytes, 20)
  val () = release_bytes(key_frozen, key_bytes)
  val () = (if !_kept > 0 then !_kept := !_kept - 1 else ())
in deleting end


(* What reading one word came to *)
#pub datavtype word_got =
  | {contents:wordx} WordGot of word_image(contents)
  | WordNone of ()

#pub fun word_got_free (got: word_got): void
implement word_got_free (got) = case+ got of ~WordGot(image) => word_image_free(image) | ~WordNone() => ()

implement $P.dispose<word_got>(got) = word_got_free(got)

(* The word id_high, id_low as stored (a tombstone too), or none *)
#pub fun wordstore_get (id_high: Int, id_low: Int): $P.promise(word_got, $P.Chained)

implement wordstore_get (id_high, id_low) = let
  val key = wordstore_key(id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val stored = $IDB.idb_get(key_bytes, 20)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><word_got>(stored, llam(found) =>
    case+ lookup_content(found) of
    | ~StoredContent(owner, piece, size) => let
        val read = _read_word(piece, 0, size)
        val () = piece_free(owner, piece)
      in case+ read of ~WordFound(image) => $P.ret<word_got>(WordGot(image)) | ~WordNotFound() => $P.ret<word_got>(WordNone()) end
    | ~NoStoredContent() => $P.ret<word_got>(WordNone())
    | ~ContentUnreadable() => $P.ret<word_got>(WordNone()))
end

end (* #target wasm *)
