(* words -- the words looked up: kept with their sentence when they are looked up, listed, and reviewed (keyword: vocabulary) *)

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
staload "notice.sats"
staload "undo.sats"
staload "layer.sats"
staload "clock.sats"
staload "settings.sats"
staload "library.sats"
staload "import.sats"
staload "modal.sats"
staload "reader.sats"
staload "annot.sats"
staload "sharing.sats"
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
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

implement $P.dispose<share_end>(_) = ()
implement $P.dispose<words_read>(read) = words_read_free(read)
implement $P.dispose<word_got>(got) = word_got_free(got)
implement $P.dispose<word_saved>(_) = ()
implement $P.dispose<settled>(_) = ()

(* The word being looked up (keyword: vocabulary) *)

(* The word the selection toolbar offers to look up (keyword: vocabulary) *)
datavtype candidate =
  | NoCandidate of ()
  | {word_loc,language_loc:agz}{word_len:nat | word_len <= 64}{language_len:nat | language_len <= 3}
    Candidate of ($A.arr(byte, word_loc, 65), int word_len, $A.arr(byte, language_loc, 3), int language_len)

val _candidate = ref<candidate>(NoCandidate())

fn _candidate_swap (next: candidate): candidate = let
  var previous: candidate = next
  val () = ref_exch_elt<candidate>(_candidate, previous)
in previous end

fn _candidate_free (held: candidate): void =
  case+ held of
  | ~NoCandidate() => ()
  | ~Candidate(word, _, language, _) => let
      val () = $A.free<byte>(word)
    in $A.free<byte>(language) end

fun _copy_into {source_loc,target_loc:agz}{source_size,target_size:pos}{count:nat | count <= source_size; count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), target: !$A.arr(byte, target_loc, target_size), count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, i, $A.get<byte>(source, i))
  in _copy_into(source, target, count, i + 1) end

(* position, or the nearest of 0 and most (keyword: vocabulary) *)
fn _within {most:nat} (position: Int, most: int most): [stop:nat | stop <= most] int stop =
  if position < 0 then 0 else if position > most then most else position

(* The word of the selection (up to the most the toolbar copies) in the book's language language[0, language_len) (keyword: vocabulary) *)
#pub fn words_candidate_set {word_loc,language_loc:agz}{word_len:nat | word_len <= 64}{language_len:nat | language_len <= 3}
  (word: !$A.arr(byte, word_loc, 65), word_len: int word_len, language: !$A.arr(byte, language_loc, 3), language_len: int language_len): void

implement words_candidate_set (word, word_len, language, language_len) = let
  val word_copy = $A.alloc<byte>(65)
  val () = _copy_into(word, word_copy, word_len, 0)
  val language_copy = $A.alloc<byte>(3)
  val () = _copy_into(language, language_copy, language_len, 0)
in _candidate_free(_candidate_swap(Candidate(word_copy, word_len, language_copy, language_len))) end

(* The sentence, in a record's two strings (keyword: vocabulary) *)

fun _copy_part {l,part_loc:agz}{n,size:pos}{from,count:nat | from + count <= n; count < size}{i:nat | i <= count} .<count - i>.
  (sentence: !$A.arr(byte, l, n), part: !$A.arr(byte, part_loc, size), from: int from, count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(part, i, $A.get<byte>(sentence, from + i))
  in _copy_part(sentence, part, from, count, i + 1) end

(* sentence[from, from + count) as a new array of count + 1 bytes (keyword: vocabulary) *)
fn _part {l:agz}{n:pos}{from,count:nat | from + count <= n; count < 256}
  (sentence: !$A.arr(byte, l, n), from: int from, count: int count): [part_loc:agz] $A.arr(byte, part_loc, count + 1) = let
  val part = $A.alloc<byte>(count + 1)
  val () = _copy_part(sentence, part, from, count, 0)
in part end

(* A lookup, noted (keyword: vocabulary) *)

(* The lookup made into a record of the sentence of the selection, sentence[0, count), and stored (keyword: vocabulary) *)
fn _note_place {word_loc,language_loc,sentence_loc:agz}{word_len:nat | word_len <= 64}{language_len:nat | language_len <= 3}{count:nat | count <= 510}
  (word: !$A.arr(byte, word_loc, 65), word_len: int word_len, language: !$A.arr(byte, language_loc, 3), language_len: int language_len,
   book_high: Int, book_low: Int, chapter: Int, node: Int, offset: Int, sentence: $A.arr(byte, sentence_loc, 511), count: int count): void = let
  val now = $TM.epoch_minutes()
  val stamp = stamp_now()
  val head_len = (if count < 255 then count else 255): [head_len:nat | head_len <= 255; head_len <= count; count - head_len <= 255] int head_len
  val tail_len = count - head_len
  val head = _part(sentence, 0, head_len)
  val tail = _part(sentence, head_len, tail_len)
  val () = $A.free<byte>(sentence)
  val word_copy = _part(word, 0, word_len)
  val language_copy = _part(language, 0, language_len)
  val numbers = @{book_high = book_high, book_low = book_low, lookups = 1, first_minute = now, last_minute = now,
    modified = stamp, deleted = 0, chapter = chapter, node = node, offset = offset, mastered = 0, streak = 0, due = now}
in
  case+ word_image_make(numbers, language_copy, language_len, head, head_len, tail, tail_len, word_copy, word_len) of
  | ~WordImaged(image) => let
      val @(id_high, id_low) = wordstore_id(word, word_len, language, language_len)
    in
      $P.finish<word_saved>(wordstore_edit(id_high, id_low, NoteLookup(image)), llam(saved) =>
        case+ saved of
        | WordFull() => notice_say(WordsFull())
        | WordNotSaved() => notice_say(WordsNotStored())
        | WordSaved() => ()
        | WordKept() => ()
        | WordRefused() => notice_say(WordsNotStored()))
    end
  | ~WordNotImaged() => ()
end

(* The word and the selection's place and sentence made into a record (keyword: vocabulary) *)
fn _note_word {word_loc,language_loc:agz}{word_len:nat | word_len <= 64}{language_len:nat | language_len <= 3}
  (word: !$A.arr(byte, word_loc, 65), word_len: int word_len, language: !$A.arr(byte, language_loc, 3), language_len: int language_len): void = let
  val index = lib_index_of_key(open_key_get())
in
  if index < 0 then ()
  else (case+ lib_nums(index) of
    | ~$R.none() => ()
    | ~$R.some(book_numbers) => let
        val book_high = book_numbers.id_high
        val book_low = book_numbers.id_low
        val @(tag, tag_len) = reader_lang_tag()
      in
        case+ annot_selection_place(tag, tag_len) of
        | ~NoSelectionPlace() => ()
        | ~SelectionPlace(chapter, node, offset, sentence, count) =>
          _note_place(word, word_len, language, language_len, book_high, book_low, chapter, node, offset, sentence, count)
      end)
end

(* The word the selection toolbar offered is looked up (Look up, or Look up online): kept, unless the setting says not to (keyword: vocabulary) *)
#pub fn words_lookup_note (): void

implement words_lookup_note () =
  case+ set_words_get() of
  | WordsNotKept() => ()
  | WordsKept() =>
    (case+ _candidate_swap(NoCandidate()) of
     | ~NoCandidate() => ()
     | ~Candidate(word, word_len, language, language_len) => let
         val () = _note_word(word, word_len, language, language_len)
       in _candidate_free(_candidate_swap(Candidate(word, word_len, language, language_len))) end)

(* Start: how many words are kept, and the tombstones that are old (keyword: vocabulary) *)

fun _forget_old {count:nat} .<count>. (words: stored_words(count), now: Int): void =
  case+ words of
  | ~StoredWordsNone() => ()
  | ~StoredWordsSome(word, rest) => let
      val ~StoredWord(id_high, id_low, image) = word
      val numbers = word_image_numbers(image)
      val () = word_image_free(image)
      val () = (if numbers.deleted > 0 then
          (if now - numbers.deleted > words_tombstone_minutes() then
            $P.finish<$IDB.stored>(wordstore_forget(id_high, id_low), llam(_) => ())
            (* ignored: a tombstone that stays is dropped at the next start (keyword: vocabulary) *)
          else ())
        else ())
    in _forget_old(rest, now) end

(* Reads the words kept: how many there are (which a new word is checked against), and drops the tombstones that are old (keyword: vocabulary) *)
#pub fn words_start (): void

implement words_start () =
  $P.finish<words_read>(wordstore_read(), llam(read) =>
    case+ read of
    | ~WordsUnreadable() => ()
    | ~WordsRead(words, count) => let
        val () = wordstore_kept_set(count)
      in _forget_old(words, $TM.epoch_minutes()) end)


(* The words screen: what is shown (keyword: vocabulary) *)

(* Which words the screen lists: those still being learned, or those mastered (keyword: vocabulary) *)
#pub datatype words_tab = TabLearning | TabMastered

val _tab = ref<words_tab>(TabLearning())

(* Whether the words listed are of every book or of the one chosen (keyword: vocabulary) *)
datatype book_scope = AllBooks | ChosenBook

(* The book the words are of: its place in the books the words came from, -1 for every book (keyword: vocabulary) *)
val _book_chosen = ref<int>(~1)

(* The books the words are of, in the order the select lists them (keyword: vocabulary) *)
datavtype books(int) =
  | BooksNil(0) of ()
  | {count:nat} BooksCons(count + 1) of (Int, Int, books(count))

val _books = ref<[count:nat] books(count)>(BooksNil())

fn _books_take (): [count:nat] books(count) = let
  var taken: [count:nat] books(count) = BooksNil()
  val () = ref_exch_elt<[count:nat] books(count)>(_books, taken)
in taken end

fun _books_free {count:nat} .<count>. (list: books(count)): void =
  case+ list of
  | ~BooksNil() => ()
  | ~BooksCons(_, _, rest) => _books_free(rest)

fun _books_has {count:nat} .<count>. (list: !books(count), high: Int, low: Int): bool =
  case+ list of
  | BooksNil() => false
  | BooksCons(book_high, book_low, rest) =>
    if book_high = high then (if book_low = low then true else _books_has(rest, high, low)) else _books_has(rest, high, low)

(* The book at place place of the select, or its ids as -1 (keyword: vocabulary) *)
fun _books_at {count:nat} .<count>. (list: !books(count), place: int): @(Int, Int) =
  case+ list of
  | BooksNil() => @(~1, ~1)
  | BooksCons(high, low, rest) => if place <= 0 then @(high, low) else _books_at(rest, place - 1)

(* list with the book added at its end, when it is not there (keyword: vocabulary) *)
fun _books_add {count:nat} .<count>. (list: books(count), high: Int, low: Int): [total:nat] books(total) =
  case+ list of
  | ~BooksNil() => BooksCons(high, low, BooksNil())
  | ~BooksCons(book_high, book_low, rest) =>
    if book_high = high then (if book_low = low then BooksCons(book_high, book_low, rest) else BooksCons(book_high, book_low, _books_add(rest, high, low)))
    else BooksCons(book_high, book_low, _books_add(rest, high, low))

(* The books kept again after the select was drawn from them, for the choice made in it (keyword: vocabulary) *)
fn _books_put {count:nat} (list: books(count)): void = let
  var previous: [count:nat] books(count) = list
  val () = ref_exch_elt<[count:nat] books(count)>(_books, previous)
in _books_free(previous) end

(* The book added to the books the words are of, when it is not there (keyword: vocabulary) *)
fn _books_put_one (high: Int, low: Int): void = let
  val list = _books_take()
  var next: [count:nat] books(count) = _books_add(list, high, low)
  val () = ref_exch_elt<[count:nat] books(count)>(_books, next)
in _books_free(next) end

(* One row of the list as it is drawn (keyword: vocabulary) *)
datavtype shown(int) =
  | ShownNil(0) of ()
  | {count:nat}{word_loc,language_loc:agz}{word_len,language_len:nat | word_len < 256; language_len < 256}
    ShownCons(count + 1) of (Int, Int, word_state, Int, Int, Int, Int, $A.arr(byte, word_loc, word_len + 1), int word_len, $A.arr(byte, language_loc, language_len + 1), int language_len, shown(count))

val _shown = ref<[count:nat] shown(count)>(ShownNil())

fn _shown_take (): [count:nat] shown(count) = let
  var taken: [count:nat] shown(count) = ShownNil()
  val () = ref_exch_elt<[count:nat] shown(count)>(_shown, taken)
in taken end

fun _shown_free {count:nat} .<count>. (list: shown(count)): void =
  case+ list of
  | ~ShownNil() => ()
  | ~ShownCons(_, _, state, _, _, _, _, word, _, language, _, rest) => let
      val () = (case+ state of ~Mastered() => () | ~Learning(_, _) => ())
      val () = $A.free<byte>(word)
      val () = $A.free<byte>(language)
    in _shown_free(rest) end

fn _shown_put {count:nat} (list: shown(count)): void = let
  var previous: [count:nat] shown(count) = list
  val () = ref_exch_elt<[count:nat] shown(count)>(_shown, previous)
in _shown_free(previous) end

(* A synchronized word is told by the row it is in: the ids of the row row of the list, or -1 (keyword: vocabulary) *)
fun _shown_row {count:nat} .<count>. (list: !shown(count), row: int): @(Int, Int, words_tab, Int, Int, Int, Int) =
  case+ list of
  | ShownNil() => @(~1, ~1, TabLearning(), ~1, ~1, ~1, ~1)
  | ShownCons(high, low, state, book_high, book_low, chapter, node, _, _, _, _, rest) =>
    if row <= 0 then @(high, low, (case+ state of Mastered() => TabMastered() | Learning(_, _) => TabLearning()), book_high, book_low, chapter, node)
    else _shown_row(rest, row - 1)

fun _shown_word {count:nat} .<count>. (list: !shown(count), row: int): [word_loc,language_loc:agz][word_len,language_len:nat | word_len < 256; language_len < 256]
  @($A.arr(byte, word_loc, word_len + 1), int word_len, $A.arr(byte, language_loc, language_len + 1), int language_len) =
  case+ list of
  | ShownNil() => let
      val word_empty = $A.alloc<byte>(1)
      val language_empty = $A.alloc<byte>(1)
    in @(word_empty, 0, language_empty, 0) end
  | ShownCons(_, _, _, _, _, _, _, word, word_len, language, language_len, rest) =>
    if row <= 0 then let
        val word_copy = $A.alloc<byte>(word_len + 1)
        val () = _copy_into(word, word_copy, word_len, 0)
        val language_copy = $A.alloc<byte>(language_len + 1)
        val () = _copy_into(language, language_copy, language_len, 0)
      in @(word_copy, word_len, language_copy, language_len) end
    else _shown_word(rest, row - 1)

(* The words as the screen lists them: how many are due, still learning and mastered, whatever the tab and the book (keyword: vocabulary) *)
val _due_count = ref<Int>(0)
val _learning_count = ref<Int>(0)
val _mastered_count = ref<Int>(0)
val _hidden_count = ref<Int>(0)

fn _numbers_of (word: !stored_word): word_numbers =
  case+ word of StoredWord(_, _, image) => word_image_numbers(image)

(* Whether word is newer than other: looked up later, or changed later (keyword: vocabulary) *)
fn _newer (word: !stored_word, other: !stored_word): bool = let
  val first = _numbers_of(word)
  val second = _numbers_of(other)
in
  if first.last_minute > second.last_minute then true
  else if first.last_minute < second.last_minute then false
  else first.modified > second.modified
end

(* sorted with word in its place, the newest first (keyword: vocabulary) *)
fun _insert_newest {count:nat} .<count>. (word: stored_word, sorted: stored_words(count)): stored_words(count + 1) =
  case+ sorted of
  | ~StoredWordsNone() => StoredWordsSome(word, StoredWordsNone())
  | ~StoredWordsSome(first, rest) =>
    if _newer(word, first) then StoredWordsSome(word, StoredWordsSome(first, rest))
    else StoredWordsSome(first, _insert_newest(word, rest))

(* The words the screen lists, newest first (keyword: vocabulary) *)
fun _gather {count,kept:nat} .<count>.
  (words: stored_words(count), now: Int, tab: words_tab, scope: book_scope, book_high: Int, book_low: Int, listed: stored_words(kept))
  : [total:nat] stored_words(total) =
  case+ words of
  | ~StoredWordsNone() => listed
  | ~StoredWordsSome(word, rest) => let
      val numbers = _numbers_of(word)
    in
      if numbers.deleted > 0 then let
        val () = stored_word_free(word)
      in _gather(rest, now, tab, scope, book_high, book_low, listed) end
      else let
        val in_tab = (case+ word_state_of(numbers) of
          | ~Mastered() => let
              val () = !_mastered_count := !_mastered_count + 1
            in (case+ tab of TabMastered() => true | TabLearning() => false) end
          | ~Learning(_, due) => let
              val () = !_learning_count := !_learning_count + 1
              val () = (if due <= now then !_due_count := !_due_count + 1 else ())
            in (case+ tab of TabLearning() => true | TabMastered() => false) end): bool
        val () = _books_put_one(numbers.book_high, numbers.book_low)
        val in_book = (case+ scope of
          | AllBooks() => true
          | ChosenBook() => (if numbers.book_high = book_high then numbers.book_low = book_low else false)): bool
      in
        if in_tab then (if in_book then _gather(rest, now, tab, scope, book_high, book_low, _insert_newest(word, listed))
          else let val () = stored_word_free(word) in _gather(rest, now, tab, scope, book_high, book_low, listed) end)
        else let val () = stored_word_free(word) in _gather(rest, now, tab, scope, book_high, book_low, listed) end
      end
    end


(* The words screen: a row (keyword: vocabulary) *)

fun _put_literal_at {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (out: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): void =
  if i >= text_len then ()
  else let
    val () = $A.set<byte>(out, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_literal_at(out, at, text, text_len, i + 1) end

(* text at out[at, at + its length) (keyword: vocabulary) *)
fn _put_literal {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}
  (out: !$A.arr(byte, l, n), at: int at, text: string text_len): int(at + text_len) = let
  val text_len = g1u2i(string1_length(text))
  val () = _put_literal_at(out, at, text, text_len, 0)
in at + text_len end

(* source[0, count) at target[at, at + count) (keyword: vocabulary) *)
fun _copy_at {source_loc,target_loc:agz}{source_size,target_size:pos}{count:nat | count <= source_size}{at:nat | at + count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), target: !$A.arr(byte, target_loc, target_size), count: int count, at: int at, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, at + i, $A.get<byte>(source, i))
  in _copy_at(source, target, count, at, i + 1) end

(* A count and its unit, in words (keyword: vocabulary) *)
fn _put_wait {l:agz}{at:nat | at + 40 <= 400}{minutes:nat} (out: !$A.arr(byte, l, 400), at: int at, minutes: int minutes): [stop:nat | stop <= 400] int stop = let
  val unit_minutes = (if minutes < 60 then 1 else if minutes < 1440 then 60 else 1440): [unit_minutes:pos] int unit_minutes
  val whole = minutes / unit_minutes
  val count = (if whole < 1 then 1 else whole): [count:nat] int count
  val after = $S.int_to_str(out, at, 400, count)
  val after = (if after < 0 then at else if after > at + 30 then at else after): [after:nat | after <= at + 30] int after
in
  if minutes < 60 then (if count = 1 then _put_literal(out, after, " minute") else _put_literal(out, after, " minutes"))
  else if minutes < 1440 then (if count = 1 then _put_literal(out, after, " hour") else _put_literal(out, after, " hours"))
  else (if count = 1 then _put_literal(out, after, " day") else _put_literal(out, after, " days"))
end

(* What a word's state is, in words: Mastered, or Learning and when it is due (keyword: vocabulary) *)
fn _put_state {l:agz}{at:nat | at + 80 <= 400}{now:int} (out: !$A.arr(byte, l, 400), at: int at, state: word_state, now: int now): [stop:nat | stop <= 400] int stop =
  case+ state of
  | ~Mastered() => _put_literal(out, at, "Mastered")
  | ~Learning(_, due) =>
    if due <= now then _put_literal(out, at, "Learning, due now")
    else let
      val after = _put_literal(out, at, "Learning, due in ")
    in _put_wait(out, after, due - now) end

(* A child element of numbered parent parent_prefix<k>, numbered child_prefix<k> (keyword: vocabulary) *)
fn _child {parent_prefix_len,child_prefix_len:pos | parent_prefix_len <= 16; child_prefix_len <= 16}{k:nat}{class_len:pos | class_len < 256}
  (parent_prefix: string parent_prefix_len, child_prefix: string child_prefix_len, k: int k, element_tag: tag, class_name: string class_len): void = let
  val @(parent_id, parent_id_len) = nid_make(parent_prefix, k)
  val @(child_id, child_id_len) = nid_make(child_prefix, k)
  val () = ui_add_nn(parent_id, parent_id_len, child_id, child_id_len, element_tag)
  val @(child_id, child_id_len) = nid_make(child_prefix, k)
in ui_attr_n(child_id, child_id_len, AClass, class_name) end

fn _child_text_button {parent_prefix_len,child_prefix_len:pos | parent_prefix_len <= 16; child_prefix_len <= 16}{k:nat}{class_len:pos | class_len < 256}{label_len:pos | label_len < 256}
  (parent_prefix: string parent_prefix_len, child_prefix: string child_prefix_len, k: int k, class_name: string class_len, label: string label_len): void = let
  val @(parent_id, parent_id_len) = nid_make(parent_prefix, k)
  val @(child_id, child_id_len) = nid_make(child_prefix, k)
in ui_text_btn_nn(parent_id, parent_id_len, child_id, child_id_len, class_name, label) end

fn _child_button {parent_prefix_len,child_prefix_len:pos | parent_prefix_len <= 16; child_prefix_len <= 16}{k:nat}{class_len:pos | class_len < 256}
  (parent_prefix: string parent_prefix_len, child_prefix: string child_prefix_len, k: int k, class_name: string class_len): void = let
  val @(parent_id, parent_id_len) = nid_make(parent_prefix, k)
  val @(child_id, child_id_len) = nid_make(child_prefix, k)
in ui_btn_nn(parent_id, parent_id_len, child_id, child_id_len, class_name) end

fn _lower {code:nat | code < 256} (code: int code): [lowered:nat | lowered < 256] int lowered =
  if code >= 65 then (if code <= 90 then code + 32 else code) else code

(* Whether word[0, word_len) is sentence[at, at + word_len), the ASCII capitals not told apart (keyword: vocabulary) *)
fun _same_at {sentence_loc,word_loc:agz}{len,size:pos}{word_len:nat | word_len <= size}{at:nat | at + word_len <= len}{j:nat | j <= word_len} .<word_len - j>.
  (sentence: !$A.arr(byte, sentence_loc, len), word: !$A.arr(byte, word_loc, size), word_len: int word_len, at: int at, j: int j): bool =
  if j >= word_len then true
  else if _lower($AR.low_byte(byte2int0($A.get<byte>(sentence, at + j)))) <> _lower($AR.low_byte(byte2int0($A.get<byte>(word, j)))) then false
  else _same_at(sentence, word, word_len, at, j + 1)

(* Where the word first is in sentence[0, len), or -1 (keyword: vocabulary) *)
fun _find_word {sentence_loc,word_loc:agz}{size:pos}{len:nat | len <= size}{word_size:pos}{word_len:nat | word_len <= word_size; word_len > 0}{at:nat | at <= len} .<len - at>.
  (sentence: !$A.arr(byte, sentence_loc, size), len: int len, word: !$A.arr(byte, word_loc, word_size), word_len: int word_len, at: int at): Int =
  if at + word_len > len then ~1
  else if _same_at(sentence, word, word_len, at, 0) then at
  else _find_word(sentence, len, word, word_len, at + 1)


(* The sentence of a word as it is in a record: the head and the tail together, in an array of one more than the most (keyword: vocabulary) *)
fn _sentence_of {c:wordx} (image: !word_image(c)): [l:agz][count:nat | count <= 510] @($A.arr(byte, l, 511), int count) = let
  val @(head, head_len) = word_image_sentence_head(image)
  val @(tail, tail_len) = word_image_sentence_tail(image)
  val out = $A.alloc<byte>(511)
in
  if head_len + tail_len > 510 then let
    val () = $A.free<byte>(head)
    val () = $A.free<byte>(tail)
  in @(out, 0) end
  else let
    val () = _copy_at(head, out, head_len, 0, 0)
    val () = _copy_at(tail, out, tail_len, head_len, 0)
    val () = $A.free<byte>(head)
    val () = $A.free<byte>(tail)
  in @(out, head_len + tail_len) end
end

(* The sentence of the row shown, with the word marked where it is in it: the words before and after it and the word itself (keyword: vocabulary) *)
fn _sentence_show {k:nat}{sentence_loc,word_loc:agz}{count:nat | count <= 510}{word_len:nat | word_len < 256}
  (k: int k, sentence: $A.arr(byte, sentence_loc, 511), count: int count, word: !$A.arr(byte, word_loc, word_len + 1), word_len: int word_len): void =
  if count <= 0 then $A.free<byte>(sentence)
  else let
    val () = _child("word-go", "word-sentence", k, TSpan, "snip")
    val found = (if word_len > 0 then _find_word(sentence, count, word, word_len, 0) else ~1): Int
    val @(frozen, bytes) = $A.freeze<byte>(sentence)
  in
    if found < 0 then let
      val @(sentence_id, sentence_id_len) = nid_make("word-sentence", k)
      val () = ui_text_n_b(sentence_id, sentence_id_len, bytes, 0, count)
    in release_bytes(frozen, bytes) end
    else let
      val [before:int] before_len = (if found > count then count else if found < 0 then 0 else found): [before_len:nat | before_len <= count] int before_len
      val mark_len = (if before_len + word_len > count then count - before_len else word_len): [mark_len:nat | before + mark_len <= count] int mark_len
      val after_at = before_len + mark_len
      val () = (if before_len > 0 then let
          val () = _child("word-sentence", "word-before", k, TSpan, "plain")
          val @(part_id, part_id_len) = nid_make("word-before", k)
        in ui_text_n_b(part_id, part_id_len, bytes, 0, before_len) end else ())
      val () = (if mark_len > 0 then let
          val () = _child("word-sentence", "word-mark", k, TSpan, "mk")
          val @(part_id, part_id_len) = nid_make("word-mark", k)
        in ui_text_n_b(part_id, part_id_len, bytes, before_len, mark_len) end else ())
      val () = (if count - after_at > 0 then let
          val () = _child("word-sentence", "word-after", k, TSpan, "plain")
          val @(part_id, part_id_len) = nid_make("word-after", k)
        in ui_text_n_b(part_id, part_id_len, bytes, after_at, count - after_at) end else ())
    in release_bytes(frozen, bytes) end
  end

(* The book's title for a row: the library's, or a line saying the book is not there (keyword: vocabulary) *)
fn _book_title (high: Int, low: Int): [l:agz][n:nat | n < 256] @($A.arr(byte, l, n + 1), int n) = let
  val index = lib_find(high, low)
in
  if index < 0 then let
    val text = $A.alloc<byte>(27)
    val ended = _put_literal(text, 0, "A book not in your library")
  in @(text, ended) end
  else lib_text(index, TitleText())
end


fun _words_count {count:nat} .<count>. (words: !stored_words(count)): int count =
  case+ words of
  | StoredWordsNone() => 0
  | StoredWordsSome(_, rest) => 1 + _words_count(rest)

(* A number's decimal digits in a new array (keyword: vocabulary) *)
fn _digits {k:nat} (k: int k): [l:agz][n:pos | n <= 20] @($A.arr(byte, l, n), int n) = let
  val buffer = $A.alloc<byte>(20)
  val ended = $S.int_to_str(buffer, 0, 20, k)
  val ended = (if ended < 1 then 1 else if ended > 20 then 20 else ended): [ended:pos | ended <= 20] int ended
  val digits = $A.alloc<byte>(ended)
  val () = _copy_at(buffer, digits, ended, 0, 0)
  val () = $A.free<byte>(buffer)
in @(digits, ended) end

(* How many times the word was looked up, in words, at the start of out (keyword: vocabulary) *)
fn _put_times {l:agz} (out: !$A.arr(byte, l, 80), lookups: Int): [stop:nat | stop <= 79] int stop =
  if lookups <= 1 then _within(_put_literal(out, 0, "Looked up once"), 79)
  else let
    val after = _put_literal(out, 0, "Looked up ")
    val after = _within($S.int_to_str(out, after, 80, lookups), 40)
  in _within(_put_literal(out, after, " times"), 79) end

(* A row of the list: the word, the book and the word's state, its sentence with the word marked, and the buttons (keyword: vocabulary) *)
fn _row_draw {k:nat}{c:wordx} (k: int k, image: !word_image(c), now: Int): void = let
  val numbers = word_image_numbers(image)
  val @(row_id, row_id_len) = nid_make("word-row", k)
  val () = ui_add_n("words-list", row_id, row_id_len, TDiv)
  val @(row_id, row_id_len) = nid_make("word-row", k)
  val () = ui_attr_n(row_id, row_id_len, AClass, "hrow")
  val () = _child_button("word-row", "word-go", k, "hgo")
  val () = _child("word-go", "word-title", k, TSpan, "bt")
  val @(title_text, title_len) = word_image_word(image)
  val @(title_id, title_id_len) = nid_make("word-title", k)
  val () = ui_text_n_buf(title_id, title_id_len, title_text, title_len)
  val @(group_id, group_id_len) = nid_make("word-row", k)
  val @(group_label, group_label_len) = nid_make("word-title", k)
  val () = ui_labelled_nn(group_id, group_id_len, NGroup, group_label, group_label_len)
  val () = _child("word-go", "word-book", k, TSpan, "hstyle")
  val @(book_title, book_title_len) = _book_title(numbers.book_high, numbers.book_low)
  val line = $A.alloc<byte>(400)
  val () = _copy_at(book_title, line, book_title_len, 0, 0)
  val () = $A.free<byte>(book_title)
  val after_title = _put_literal(line, book_title_len, " \xC2\xB7 ")
  val ended = _put_state(line, after_title, word_state_of(numbers), now)
  val @(book_id, book_id_len) = nid_make("word-book", k)
  val () = ui_text_n_buf(book_id, book_id_len, line, ended)
  val () = _child("word-go", "word-times", k, TSpan, "hstyle")
  val times = $A.alloc<byte>(80)
  val ended = _put_times(times, numbers.lookups)
  val @(times_id, times_id_len) = nid_make("word-times", k)
  val () = ui_text_n_buf(times_id, times_id_len, times, ended)
  val @(marked_word, marked_len) = word_image_word(image)
  val @(sentence, count) = _sentence_of(image)
  val () = _sentence_show(k, sentence, count, marked_word, marked_len)
  val () = $A.free<byte>(marked_word)
  val () = _child("word-row", "word-tools", k, TDiv, "hbtns")
  val () = _child_text_button("word-tools", "word-goto", k, "hbtn", "Go to")
  val () = (case+ word_state_of(numbers) of
    | ~Mastered() => _child_text_button("word-tools", "word-master", k, "hbtn", "Learn again")
    | ~Learning(_, _) => _child_text_button("word-tools", "word-master", k, "hbtn", "Mark as mastered"))
in _child_text_button("word-tools", "word-delete", k, "hbtn quiet", "Delete") end

(* The rows of the words sorted, from row k on, at most as many as the screen draws: the list of what they are (keyword: vocabulary) *)
fun _rows {count,k:nat} .<count>. (words: stored_words(count), k: int k, now: Int): [shown_count:nat] shown(shown_count) =
  case+ words of
  | ~StoredWordsNone() => ShownNil()
  | ~StoredWordsSome(word, rest) =>
    if k >= 500 then let
      val () = !_hidden_count := _words_count(rest) + 1
      val () = stored_word_free(word)
      val () = stored_words_free(rest)
    in ShownNil() end
    else let
      val ~StoredWord(id_high, id_low, image) = word
      val numbers = word_image_numbers(image)
      val () = _row_draw(k, image, now)
      val @(word_text, word_len) = word_image_word(image)
      val @(language, language_len) = word_image_language(image)
      val () = word_image_free(image)
      val shown_rest = _rows(rest, k + 1, now)
    in
      ShownCons(id_high, id_low, word_state_of(numbers), numbers.book_high, numbers.book_low, numbers.chapter, numbers.node,
        word_text, word_len, language, language_len, shown_rest)
    end

(* The options of the book select: every book, then each book the words are of, the chosen one selected (keyword: vocabulary) *)
fun _book_options {count:nat}{k:nat} .<count>. (list: !books(count), k: int k, scope: book_scope, chosen_high: Int, chosen_low: Int): void =
  case+ list of
  | BooksNil() => ()
  | BooksCons(high, low, rest) => let
      val @(title, title_len) = _book_title(high, low)
      val @(option_id, option_id_len) = nid_make("words-book-opt", k)
      val @(value, value_len) = _digits(k)
      val chosen = (case+ scope of AllBooks() => false | ChosenBook() => (if high = chosen_high then low = chosen_low else false)): bool
      val () = (if title_len > 0 then ui_option("words-book", option_id, option_id_len, value, value_len, title, title_len, chosen)
        else let
          val () = $A.free<byte>(option_id)
          val () = $A.free<byte>(value)
        in $A.free<byte>(title) end)
    in _book_options(rest, k + 1, scope, chosen_high, chosen_low) end

(* The book the words are of that the select has chosen: every book, or the ids of the one (keyword: vocabulary) *)
val _book_scope = ref<book_scope>(AllBooks())
val _book_high = ref<Int>(0)
val _book_low = ref<Int>(0)

(* The line under the tabs: how many words are due, still being learned and mastered (keyword: vocabulary) *)
fn _status_show (): void = let
  val line = $A.alloc<byte>(400)
  val at = _within($S.int_to_str(line, 0, 400, !_due_count), 20)
  val at = _put_literal(line, at, " due, ")
  val at = _within($S.int_to_str(line, at, 400, !_learning_count), 60)
  val at = _put_literal(line, at, " learning, ")
  val at = _within($S.int_to_str(line, at, 400, !_mastered_count), 120)
  val at = _put_literal(line, at, " mastered")
in ui_text_buf("words-status", line, at) end

(* The screen drawn from the words kept: the tab's and the book's, newest first (keyword: vocabulary) *)
#pub fn words_render (): void

implement words_render () =
  $P.finish<words_read>(wordstore_read(), llam(read) =>
    case+ read of
    | ~WordsUnreadable() => ui_text("words-status", "Your words could not be read.")
    | ~WordsRead(words, _) => let
        val () = !_due_count := 0
        val () = !_learning_count := 0
        val () = !_mastered_count := 0
        val () = !_hidden_count := 0
        val () = _books_free(_books_take())
        val now = $TM.epoch_minutes()
        val tab = !_tab
        val sorted = _gather(words, now, tab, !_book_scope, !_book_high, !_book_low, StoredWordsNone())
        val () = ui_clear("words-list")
        val listed = _rows(sorted, 0, now)
        val () = _shown_put(listed)
        val () = (case+ tab of
          | TabLearning() => let
              val () = ui_attr("words-tab-learning", APressed, "true")
            in ui_attr("words-tab-mastered", APressed, "false") end
          | TabMastered() => let
              val () = ui_attr("words-tab-learning", APressed, "false")
            in ui_attr("words-tab-mastered", APressed, "true") end)
        val () = ui_clear("words-book")
        val @(all_id, all_id_len) = nid_make("words-book-opt", 99999)
        val all_value = $A.alloc<byte>(3)
        val () = $A.write_text(all_value, 0, $A.text_lit("all"), 3)
        val all_label = $A.alloc<byte>(9)
        val () = $A.write_text(all_label, 0, $A.text_lit("All books"), 9)
        val () = ui_option("words-book", all_id, all_id_len, all_value, 3, all_label, 9, (case+ !_book_scope of AllBooks() => true | ChosenBook() => false))
        val books = _books_take()
        val () = _book_options(books, 0, !_book_scope, !_book_high, !_book_low)
        val () = _books_put(books)
        val () = _status_show()
        val () = ui_show("words-none", !_learning_count + !_mastered_count = 0)
        val () = ui_show("words-more", !_hidden_count > 0)
      in () end)


(* The words screen: opened, and what its controls do (keyword: vocabulary) *)

(* The screen opened over the library, listing the words kept (keyword: vocabulary) *)
#pub fn words_screen_open (): void

implement words_screen_open () = let
  val () = layer_open(LWords())
  val () = words_render()
in ui_focus("words-back") end

(* The tab chosen: the words being learned, or the mastered ones (keyword: vocabulary) *)
#pub fn words_tab_set (tab: words_tab): void

implement words_tab_set (tab) = let
  val () = !_tab := tab
in words_render() end

(* A select's value as the number it names, or -1 (every book) (keyword: vocabulary) *)
fn _chosen_number (): int = let
  val id = $A.alloc<byte>(10)
  val () = $A.write_text(id, 0, $A.text_lit("words-book"), 10)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val read = $DR.read_input_value(id_bytes, 10)
  val () = release_bytes(id_frozen, id_bytes)
in
  case+ read of
  | ~$R.none() => ~1
  | ~$R.some(blob) => let
      val value_len = $BD.blob_len(blob)
    in
      if value_len <= 0 then let val () = $BD.blob_free(blob) in ~1 end
      else if value_len > 9 then let val () = $BD.blob_free(blob) in ~1 end
      else let
        val value = $A.alloc<byte>(value_len)
        val () = $BD.blob_read(blob, 0, value, value_len)
        val () = $BD.blob_free(blob)
        fun number {l:agz}{n:pos}{i:nat | i <= n} .<n - i>. (value: !$A.arr(byte, l, n), n: int n, i: int i, total: int): int =
          if i >= n then total
          else let val code = byte2int0($A.get<byte>(value, i)) in
            if code < 48 then ~1 else if code > 57 then ~1 else number(value, n, i + 1, total * 10 + (code - 48))
          end
        val chosen = number(value, value_len, 0, 0)
        val () = $A.free<byte>(value)
      in chosen end
    end
end

(* The book select changed: the words of the book it names, or of every book (keyword: vocabulary) *)
#pub fn words_book_changed (): void

implement words_book_changed () = let
  val chosen = _chosen_number()
in
  if chosen < 0 then let
    val () = !_book_scope := AllBooks()
  in words_render() end
  else let
    val books = _books_take()
    val @(high, low) = _books_at(books, chosen)
    val () = _books_free(books)
    val () = !_book_scope := (if high < 0 then AllBooks() else ChosenBook())
    val () = !_book_high := high
    val () = !_book_low := low
  in words_render() end
end

(* What an edit came to, told when it did not keep the change; the list follows what is stored (keyword: vocabulary) *)
fn _after_edit (saved: word_saved): void = let
  val () = (case+ saved of
    | WordNotSaved() => notice_say(WordsNotStored())
    | WordRefused() => notice_say(WordsNotStored())
    | WordSaved() => ()
    | WordKept() => ()
    | WordFull() => ())
in words_render() end

(* The row's word marked mastered, or to be learned again when it is mastered (keyword: vocabulary) *)
#pub fn words_row_master (row: int): void

implement words_row_master (row) = let
  val list = _shown_take()
  val @(high, low, tab, _, _, _, _) = _shown_row(list, row)
  val () = _shown_put(list)
in
  if high < 0 then ()
  else let
    val edit = (case+ tab of
      | TabMastered() => LearnWordAgain($TM.epoch_minutes(), stamp_now())
      | TabLearning() => MasterWord(stamp_now())): word_edit
  in $P.finish<word_saved>(wordstore_edit(high, low, edit), llam(saved) => _after_edit(saved)) end
end

(* The row's word deleted, offered back by Undo: only its tombstone is kept until the offer is final (keyword: vocabulary) *)
#pub fn words_row_delete (row: int): void

implement words_row_delete (row) = let
  val list = _shown_take()
  val @(high, low, _, _, _, _, _) = _shown_row(list, row)
  val () = _shown_put(list)
in
  if high < 0 then ()
  else
    $P.finish<word_got>(wordstore_get(high, low), llam(got) =>
      case+ got of
      | ~WordNone() => ()
      | ~WordGot(image) =>
        $P.finish<word_saved>(wordstore_edit(high, low, DeleteWord($TM.epoch_minutes(), stamp_now())), llam(saved) =>
          case+ saved of
          | WordSaved() => let
              val () = words_render()
            in
              $P.finish<settled>(undo_offer(WordDeleted()), llam(settling) =>
                case+ settling of
                | Undone() => $P.finish<word_saved>(wordstore_edit(high, low, PutWord(image, stamp_now())), llam(restored) => _after_edit(restored))
                | Final() => word_image_free(image))
            end
          | WordNotSaved() => let val () = word_image_free(image) in notice_say(WordsNotStored()) end
          | WordRefused() => let val () = word_image_free(image) in notice_say(WordsNotStored()) end
          | WordKept() => word_image_free(image)
          | WordFull() => word_image_free(image)))
end

(* The book, chapter and content node of the row's lookup; the book's ids -1 when there is no such row (keyword: vocabulary) *)
#pub fn words_row_place (row: int): @(Int, Int, Int, Int)

implement words_row_place (row) = let
  val list = _shown_take()
  val @(_, _, _, book_high, book_low, chapter, node) = _shown_row(list, row)
  val () = _shown_put(list)
in @(book_high, book_low, chapter, node) end

(* The word of the row and its language, in new arrays: for the dictionary (keyword: vocabulary) *)
#pub fn words_row_word (row: int): [word_loc,language_loc:agz][word_len,language_len:nat | word_len < 256; language_len < 256]
  @($A.arr(byte, word_loc, word_len + 1), int word_len, $A.arr(byte, language_loc, language_len + 1), int language_len)

implement words_row_word (row) = let
  val list = _shown_take()
  val found = _shown_word(list, row)
  val () = _shown_put(list)
in found end


(* Review: the words that are due, one at a time (keyword: vocabulary) *)

(* The word being reviewed: its ids, and the word and its language as the dictionary is asked for them (keyword: vocabulary) *)
datavtype card =
  | NoCard of ()
  | {word_loc,language_loc:agz}{word_len,language_len:nat | word_len < 256; language_len < 256}
    Card of (Int, Int, $A.arr(byte, word_loc, word_len + 1), int word_len, $A.arr(byte, language_loc, language_len + 1), int language_len)

val _card = ref<card>(NoCard())

fn _card_free (held: card): void =
  case+ held of
  | ~NoCard() => ()
  | ~Card(_, _, word, _, language, _) => let
      val () = $A.free<byte>(word)
    in $A.free<byte>(language) end

fn _card_swap (next: card): card = let
  var previous: card = next
  val () = ref_exch_elt<card>(_card, previous)
in previous end

(* The word that has been due the longest, of the words that are due (keyword: vocabulary) *)
datavtype best =
  | NoBest of ()
  | Best of stored_word

(* The minute a word is due at; a mastered word is never due, so it is the far future (keyword: vocabulary) *)
fn _due_of (word: !stored_word): Int =
  case+ word_state_of(_numbers_of(word)) of
  | ~Mastered() => 2147483647
  | ~Learning(_, due) => due

fun _earliest {count:nat} .<count>. (words: stored_words(count), now: Int, held: best): best =
  case+ words of
  | ~StoredWordsNone() => held
  | ~StoredWordsSome(word, rest) => let
      val numbers = _numbers_of(word)
      val due = _due_of(word)
    in
      if numbers.deleted > 0 then let val () = stored_word_free(word) in _earliest(rest, now, held) end
      else if due > now then let val () = stored_word_free(word) in _earliest(rest, now, held) end
      else let
        val () = !_due_count := !_due_count + 1
      in
        case+ held of
        | ~NoBest() => _earliest(rest, now, Best(word))
        | ~Best(earlier) =>
          if due < _due_of(earlier) then let
            val () = stored_word_free(earlier)
          in _earliest(rest, now, Best(word)) end
          else let
            val () = stored_word_free(word)
          in _earliest(rest, now, Best(earlier)) end
      end
    end

(* The sentence of the review, with the word marked, in its element (keyword: vocabulary) *)
fn _review_sentence {sentence_loc,word_loc:agz}{count:nat | count <= 510}{word_len:nat | word_len < 256}
  (sentence: $A.arr(byte, sentence_loc, 511), count: int count, word: !$A.arr(byte, word_loc, word_len + 1), word_len: int word_len): void =
  if count <= 0 then $A.free<byte>(sentence)
  else let
    val found = (if word_len > 0 then _find_word(sentence, count, word, word_len, 0) else ~1): Int
    val @(frozen, bytes) = $A.freeze<byte>(sentence)
  in
    if found < 0 then let
      val @(part_id, part_id_len) = nid_make("review-plain", 0)
      val () = ui_add_n("review-sentence", part_id, part_id_len, TSpan)
      val @(part_id, part_id_len) = nid_make("review-plain", 0)
      val () = ui_text_n_b(part_id, part_id_len, bytes, 0, count)
    in release_bytes(frozen, bytes) end
    else let
      val [before:int] before_len = (if found > count then count else if found < 0 then 0 else found): [before_len:nat | before_len <= count] int before_len
      val mark_len = (if before_len + word_len > count then count - before_len else word_len): [mark_len:nat | before + mark_len <= count] int mark_len
      val after_at = before_len + mark_len
      val () = (if before_len > 0 then let
          val @(part_id, part_id_len) = nid_make("review-before", 0)
          val () = ui_add_n("review-sentence", part_id, part_id_len, TSpan)
          val @(part_id, part_id_len) = nid_make("review-before", 0)
        in ui_text_n_b(part_id, part_id_len, bytes, 0, before_len) end else ())
      val () = (if mark_len > 0 then let
          val @(part_id, part_id_len) = nid_make("review-mark", 0)
          val () = ui_add_n("review-sentence", part_id, part_id_len, TSpan)
          val @(part_id, part_id_len) = nid_make("review-mark", 0)
          val () = ui_attr_n(part_id, part_id_len, AClass, "mk")
          val @(part_id, part_id_len) = nid_make("review-mark", 0)
        in ui_text_n_b(part_id, part_id_len, bytes, before_len, mark_len) end else ())
      val () = (if count - after_at > 0 then let
          val @(part_id, part_id_len) = nid_make("review-after", 0)
          val () = ui_add_n("review-sentence", part_id, part_id_len, TSpan)
          val @(part_id, part_id_len) = nid_make("review-after", 0)
        in ui_text_n_b(part_id, part_id_len, bytes, after_at, count - after_at) end else ())
    in release_bytes(frozen, bytes) end
  end

(* Nothing is due: the card is gone, and the screen says so (keyword: vocabulary) *)
fn _review_empty (): void = let
  val () = _card_free(_card_swap(NoCard()))
  val () = ui_show("review-card", false)
  val () = ui_show("review-empty", true)
  val () = ui_show("review-show", false)
  val () = ui_show("review-known", false)
  val () = ui_show("review-forgot", false)
in ui_text("review-progress", "No words are due.") end

(* " word is due" or " words are due" at out[at, ...) (keyword: vocabulary) *)
fn _put_due {l:agz}{at:nat | at + 14 <= 400}{due:int} (out: !$A.arr(byte, l, 400), at: int at, due: int due): [stop:nat | stop <= 400] int stop =
  if due = 1 then _put_literal(out, at, " word is due") else _put_literal(out, at, " words are due")

(* The card shown for the word, and the count of the words due (keyword: vocabulary) *)
fn _review_draw {c:wordx} (id_high: Int, id_low: Int, image: !word_image(c), due: Int): void = let
  val @(title_text, title_len) = word_image_word(image)
  val () = ui_text_buf("review-word", title_text, title_len)
  val () = ui_clear("review-sentence")
  val @(marked_word, marked_len) = word_image_word(image)
  val @(sentence, count) = _sentence_of(image)
  val () = _review_sentence(sentence, count, marked_word, marked_len)
  val () = $A.free<byte>(marked_word)
  val line = $A.alloc<byte>(400)
  val at = _within($S.int_to_str(line, 0, 400, due), 20)
  val at = _put_due(line, at, due)
  val () = ui_text_buf("review-progress", line, at)
  val @(word_text, word_len) = word_image_word(image)
  val @(language, language_len) = word_image_language(image)
  val () = _card_free(_card_swap(Card(id_high, id_low, word_text, word_len, language, language_len)))
  val () = ui_show("review-card", true)
  val () = ui_show("review-empty", false)
  val () = ui_show("review-show", true)
  val () = ui_show("review-known", false)
  val () = ui_show("review-forgot", false)
in () end

(* The word most overdue shown, as a card (keyword: vocabulary) *)
fn _review_next (): void =
  $P.finish<words_read>(wordstore_read(), llam(read) =>
    case+ read of
    | ~WordsUnreadable() => ui_text("review-progress", "Your words could not be read.")
    | ~WordsRead(words, _) => let
        val () = !_due_count := 0
        val chosen = _earliest(words, $TM.epoch_minutes(), NoBest())
      in
        case+ chosen of
        | ~NoBest() => _review_empty()
        | ~Best(word) => let
            val ~StoredWord(id_high, id_low, image) = word
            val () = _review_draw(id_high, id_low, image, !_due_count)
          in word_image_free(image) end
      end)

(* The review screen opened over the words, at the word most overdue (keyword: vocabulary) *)
#pub fn words_review_open (): void

implement words_review_open () = let
  val () = layer_open(LReview())
  val () = _review_next()
in ui_focus("review-back") end

(* Show definition pressed: the answer buttons come up (the definition is the dictionary's panel, which the caller opens) (keyword: vocabulary) *)
#pub fn words_review_revealed (): void

implement words_review_revealed () = let
  val () = ui_show("review-show", false)
  val () = ui_show("review-known", true)
in ui_show("review-forgot", true) end

(* The card's word and its language, in new arrays: for the dictionary (keyword: vocabulary) *)
#pub fn words_review_word (): [word_loc,language_loc:agz][word_len,language_len:nat | word_len < 256; language_len < 256]
  @($A.arr(byte, word_loc, word_len + 1), int word_len, $A.arr(byte, language_loc, language_len + 1), int language_len)

implement words_review_word () =
  case+ _card_swap(NoCard()) of
  | ~NoCard() => let
      val word_empty = $A.alloc<byte>(1)
      val language_empty = $A.alloc<byte>(1)
    in @(word_empty, 0, language_empty, 0) end
  | ~Card(id_high, id_low, word, word_len, language, language_len) => let
      val word_copy = $A.alloc<byte>(word_len + 1)
      val () = _copy_into(word, word_copy, word_len, 0)
      val language_copy = $A.alloc<byte>(language_len + 1)
      val () = _copy_into(language, language_copy, language_len, 0)
      val () = _card_free(_card_swap(Card(id_high, id_low, word, word_len, language, language_len)))
    in @(word_copy, word_len, language_copy, language_len) end

(* The card answered, Got it or Forgot: the word is due again as the schedule says, and the next card comes (keyword: vocabulary) *)
#pub fn words_review_answer (answer: review_answer): void

implement words_review_answer (answer) =
  case+ _card_swap(NoCard()) of
  | ~NoCard() => ()
  | ~Card(id_high, id_low, word, _, language, _) => let
      val () = $A.free<byte>(word)
      val () = $A.free<byte>(language)
    in
      $P.finish<word_saved>(wordstore_edit(id_high, id_low, ReviewWord(answer, $TM.epoch_minutes(), stamp_now())), llam(saved) => let
        val () = (case+ saved of
          | WordNotSaved() => notice_say(WordsNotStored())
          | WordRefused() => notice_say(WordsNotStored())
          | WordSaved() => ()
          | WordKept() => ()
          | WordFull() => ())
      in _review_next() end)
    end

(* The review closed: the words screen follows what was reviewed (keyword: vocabulary) *)
#pub fn words_review_closed (): void

implement words_review_closed () = let
  val () = _card_free(_card_swap(NoCard()))
in words_render() end

(* The list as a CSV file (keyword: vocabulary) *)

(* The most bytes a word takes in the file: each of its four fields at its longest, every byte a quote doubled, in quotes (keyword: vocabulary) *)
#define CSV_ROW_MAX 2600

(* text[i, count) quoted, onto out (keyword: vocabulary) *)
fun _csv_text {l,text_loc:agz}{arena:addr}{n:nat}{text_size:pos}{count:nat | count <= text_size}{i:nat | i <= count}{position:nat | position + 2 * (count - i) <= n} .<count - i>.
  (out: !$A.arrx(byte, l, n, arena), position: int position, text: !$A.arr(byte, text_loc, text_size), count: int count, i: int i)
  : [next:nat | next <= position + 2 * (count - i)] int next =
  if i >= count then position
  else let
    val code = $AR.low_byte(byte2int0($A.get<byte>(text, i)))
  in
    if code = 34 then let
      val () = $A.write_byte(out, position, 34)
      val () = $A.write_byte(out, position + 1, 34)
    in _csv_text(out, position + 2, text, count, i + 1) end
    else let
      val () = $A.write_byte(out, position, code)
    in _csv_text(out, position + 1, text, count, i + 1) end
  end

(* text[0, count) as a field, with a quote on each side (keyword: vocabulary) *)
fn _csv_field {l,text_loc:agz}{arena:addr}{n:nat}{text_size:pos}{count:nat | count <= text_size}{position:nat | position + 2 * count + 2 <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, text: !$A.arr(byte, text_loc, text_size), count: int count)
  : [next:nat | next <= position + 2 * count + 2] int next = let
  val () = $A.write_byte(out, position, 34)
  val after = _csv_text(out, position + 1, text, count, 0)
  val () = $A.write_byte(out, after, 34)
in after + 1 end

fn _csv_separator {l:agz}{arena:addr}{n:nat}{position:nat | position + 1 <= n} (out: !$A.arrx(byte, l, n, arena), position: int position, code: int): int(position + 1) = let
  val () = $A.write_byte(out, position, $AR.low_byte(code))
in position + 1 end

(* A word as a line: the word, its sentence, its book's title and its language (keyword: vocabulary) *)
fn _csv_row {l:agz}{arena:addr}{n:nat}{c:wordx}{position:nat | position + 2600 <= n}
  (out: !$A.arrx(byte, l, n, arena), position: int position, image: !word_image(c)): [next:nat | next <= position + 2600] int next = let
  val numbers = word_image_numbers(image)
  val @(word, word_len) = word_image_word(image)
  val @(sentence, sentence_len) = _sentence_of(image)
  val @(title, title_len) = _book_title(numbers.book_high, numbers.book_low)
  val @(language, language_len) = word_image_language(image)
  val after = _csv_field(out, position, word, word_len)
  val after = _csv_field(out, _csv_separator(out, after, 44), sentence, sentence_len)
  val after = _csv_field(out, _csv_separator(out, after, 44), title, title_len)
  val after = _csv_field(out, _csv_separator(out, after, 44), language, language_len)
  val after = _csv_separator(out, after, 10)
  val () = $A.free<byte>(word)
  val () = $A.free<byte>(sentence)
  val () = $A.free<byte>(title)
  val () = $A.free<byte>(language)
in after end

(* The live words onto sorted, the newest first (keyword: vocabulary) *)
fun _alive_sorted {count,kept:nat} .<count>. (words: stored_words(count), sorted: stored_words(kept)): [total:nat] stored_words(total) =
  case+ words of
  | ~StoredWordsNone() => sorted
  | ~StoredWordsSome(word, rest) => let
      val numbers = _numbers_of(word)
    in
      if numbers.deleted > 0 then let val () = stored_word_free(word) in _alive_sorted(rest, sorted) end
      else _alive_sorted(rest, _insert_newest(word, sorted))
    end

(* The rows of words onto out (keyword: vocabulary) *)
fun _csv_rows {l:agz}{arena:addr}{n:nat}{count:nat}{position:nat | position + CSV_ROW_MAX * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, arena), position: int position, words: !stored_words(count)): [next:nat | next <= position + CSV_ROW_MAX * count] int next =
  case+ words of
  | StoredWordsNone() => position
  | StoredWordsSome(word, rest) =>
    (case+ word of
     | StoredWord(_, _, image) => let
         val after = _csv_row(out, position, image)
       in _csv_rows(out, after, rest) end)

(* The words sorted as the file of a CSV, shared (keyword: vocabulary) *)
fn _csv_build {count:nat | count <= 10000} (sorted: stored_words(count), count: int count, way: share_as): $P.promise(share_end, $P.Chained) =
  case+ piece_new(100 + CSV_ROW_MAX * count) of
  | ~NoPiece() => let val () = stored_words_free(sorted) in $P.ret<share_end>(ShareOver()) end
  | ~Piece(owner, out) => let
      val header_end = jw_lit(out, 0, "word,sentence,book,language\n")
      val written = _csv_rows(out, header_end, sorted)
      val file_end = (if written < 1 then 1 else written): [end_at:pos | end_at <= 100 + CSV_ROW_MAX * count] int end_at
      val () = stored_words_free(sorted)
      val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(out_frozen, out_bytes, file_end)
      val ending = share_csv(used, file_end, way)
      val out_bytes = $A.borrow_join<byte>(out_frozen, used, rest)
      val () = $A.drop<byte>(out_frozen, out_bytes)
      val () = piece_free(owner, $A.thaw<byte>(out_frozen))
    in ending end

(* The words as a CSV file (word, sentence (keyword: vocabulary) *)
#pub fn words_share (way: share_as): $P.promise(share_end, $P.Chained)

implement words_share (way) =
  $P.and_then<words_read><share_end>(wordstore_read(), llam(read) =>
    case+ read of
    | ~WordsUnreadable() => $P.ret<share_end>(ShareOver())
    | ~WordsRead(words, _) => let
        val sorted = _alive_sorted(words, StoredWordsNone())
        val count = _words_count(sorted)
      in
        if count > 10000 then let val () = stored_words_free(sorted) in $P.ret<share_end>(ShareOver()) end
        else _csv_build(sorted, count, way)
      end)

end (* #target wasm (keyword: vocabulary) *)
