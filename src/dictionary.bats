(* dictionary -- the dictionaries Look up reads without a connection:
   StarDict dictionaries the reader imports, each serving one language *)

(* A dictionary's files stay on the JS side, as a book's do: each is
   stored in IndexedDB from there (file-input's idb_put) and read back
   as a file that is read by ranges, so nothing of a dictionary enters
   wasm memory but the bytes a lookup reads (and its .idx and .syn
   while they are imported, in arena pieces).

   Its import checks its .ifo, the .idx's size against the .ifo's
   idxfilesize, and every record of its .idx and .syn, and makes its
   table, stored beside its files ('X'):

     0   "QDX1"
     4   the samples of the .idx: every 64th record's
     8   the .idx's records
     12  the samples of the .syn
     16  the .syn's records
     20  a .dict.dz's chunk length (0 for a .dict)
     24  its chunk count
     28  where the chunks' offsets are in the table
     32  the .idx's samples: where each one's entry is (u32 each)
     ..  the .syn's samples, likewise
     ..  the chunks' offsets in the .dict.dz, and its end (count + 1)
     ..  the entries: a record's position in its file (u32), its
         word's length (a byte), its word

   (every number a big-endian u32). A lookup binary-searches the
   samples, then reads one block of records by range. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "ui.sats"
staload "notice.sats"
staload "layer.sats"
staload "modal.sats"
staload "undo.sats"
staload "book.sats"
staload "mem.sats"
staload "library.sats"
staload "jsonio.sats"
staload "app.sats"
staload "stardict.sats"
staload "storage.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A write's answer no consumer took: nothing to free *)
implement $P.dispose<$IDB.stored>(_) = ()

(* The most dictionaries kept *)
#define MOST_DICTIONARIES 64
(* A record of the .idx at most: a word under 256 bytes, its 0 byte, and
   its article's offset and size *)
#define RECORD_MOST 265
(* The most bytes a lookup reads of records at once: two blocks of 64 *)
#define BLOCK_MOST 33920
(* The most bytes of an article read (what is shown of it is cut to
   under 64 KiB of text) *)
#define ARTICLE_READ_MOST 262144
(* A list entry's most bytes, stored: its numbers, name and types *)
#define ENTRY_MOST 282

fn _byte_at {l:agz}{o:addr}{n:nat}{i:nat | i < n} (bytes: !$A.arrx(byte, l, n, o), i: int i): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))

(* The lesser of value and most *)
fn _least {value,most:int} (value: int value, most: int most): [least:int | least <= value; least <= most; least == value || least == most] int least =
  if value > most then most else value

(* target[target_at, target_at + count) := source[source_at, source_at + count) *)
fun _copy_bytes {source_loc,target_loc:agz}{source_owner,target_owner:addr}{source_size,target_size:nat}
  {source_at,count:nat | source_at + count <= source_size}{target_at:nat | target_at + count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arrx(byte, source_loc, source_size, source_owner), source_at: int source_at,
   target: !$A.arrx(byte, target_loc, target_size, target_owner), target_at: int target_at, count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, target_at + i, $A.get<byte>(source, source_at + i))
  in _copy_bytes(source, source_at, target, target_at, count, i + 1) end

(* text's bytes at buffer[at, at + text_len) *)
fun _put_string {l:agz}{o:addr}{n:nat}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (buffer: !$A.arrx(byte, l, n, o), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.write_byte(buffer, at + i, $AR.byte_of_char(string_get_at(text, i)))
  in _put_string(buffer, at, text, text_len, i + 1) end

fn _id_bytes {id_len:pos | id_len < 256} (id: string id_len): [l:agz] @($A.arr(byte, l, id_len), int id_len) = let
  val id_len = g1u2i(string1_length(id))
  val bytes = $A.alloc<byte>(id_len)
  val _ = _put_string(bytes, 0, id, id_len, 0)
in @(bytes, id_len) end

(* ============================================================
   Languages
   ============================================================ *)

(* A language is its code's 2 or 3 lower case letters, packed: the
   first, the second times 256, the third times 65536 *)
#define LANGUAGE_COUNT 30

fn _language_code {index:nat | index < LANGUAGE_COUNT} (index: int index): [code_len:int | 2 <= code_len; code_len <= 3] string code_len =
  case+ index of
  | 0 => "en" | 1 => "fr" | 2 => "de" | 3 => "es" | 4 => "it" | 5 => "pt" | 6 => "nl" | 7 => "sv"
  | 8 => "da" | 9 => "no" | 10 => "fi" | 11 => "pl" | 12 => "cs" | 13 => "hu" | 14 => "ro"
  | 15 => "ru" | 16 => "uk" | 17 => "el" | 18 => "tr" | 19 => "he" | 20 => "ar" | 21 => "fa"
  | 22 => "hi" | 23 => "zh" | 24 => "ja" | 25 => "ko" | 26 => "id" | 27 => "vi" | 28 => "la"
  | _ => "eo"

fn _language_name {index:nat | index < LANGUAGE_COUNT} (index: int index): [name_len:pos | name_len < 32] string name_len =
  case+ index of
  | 0 => "English" | 1 => "French" | 2 => "German" | 3 => "Spanish" | 4 => "Italian"
  | 5 => "Portuguese" | 6 => "Dutch" | 7 => "Swedish" | 8 => "Danish" | 9 => "Norwegian"
  | 10 => "Finnish" | 11 => "Polish" | 12 => "Czech" | 13 => "Hungarian" | 14 => "Romanian"
  | 15 => "Russian" | 16 => "Ukrainian" | 17 => "Greek" | 18 => "Turkish" | 19 => "Hebrew"
  | 20 => "Arabic" | 21 => "Persian" | 22 => "Hindi" | 23 => "Chinese" | 24 => "Japanese"
  | 25 => "Korean" | 26 => "Indonesian" | 27 => "Vietnamese" | 28 => "Latin"
  | _ => "Esperanto"

fn _code_of_string {length:int | 2 <= length; length <= 3} (code: string length): int = let
  val code_len: int length = g1u2i(string1_length(code))
  val first = char2int0(string_get_at(code, 0))
  val second = char2int0(string_get_at(code, 1))
  val third = (if code_len >= 3 then char2int0(string_get_at(code, 2)) else 0): int
in first + second * 256 + third * 65536 end

#define ENGLISH 28261

fn _is_letter (code: int): bool = code >= 97 && code <= 122

(* The language code[0, code_len) names (2 or 3 letters, in any case);
   -1 when it is not one *)
fn _language_of_bytes {l:agz}{n:pos}{code_len:nat | code_len <= n} (code: !$A.arr(byte, l, n), code_len: int code_len): int =
  if code_len < 2 then ~1
  else if code_len > 3 then ~1
  else let
    fn lower (value: int): int = if value >= 65 && value <= 90 then value + 32 else value
    val first = lower(_byte_at(code, 0))
    val second = lower(_byte_at(code, 1))
    val third = (if code_len >= 3 then lower(_byte_at(code, 2)) else 97): int
  in
    if ~_is_letter(first) then ~1
    else if ~_is_letter(second) then ~1
    else if ~_is_letter(third) then ~1
    else first + second * 256 + ((if code_len >= 3 then third * 65536 else 0): int)
  end

(* Whether language is a code's letters *)
fn _language_valid (language: int): bool = let
  val first = language - (language / 256) * 256
  val second = (language / 256) - (language / 65536) * 256
  val third = language / 65536
in _is_letter(first) && _is_letter(second) && (third = 0 || _is_letter(third)) end

(* language's letters at out[at, at + 3): how many *)
fn _code_put {l:agz}{o:addr}{n:nat}{at:nat | at + 3 <= n} (out: !$A.arrx(byte, l, n, o), at: int at, language: int): [count:int | 2 <= count; count <= 3] int count = let
  val () = $A.write_byte(out, at, $AR.low_byte(language))
  val () = $A.write_byte(out, at + 1, $AR.low_byte(language / 256))
  val third = $AR.low_byte(language / 65536)
in if third > 0 then let val () = $A.write_byte(out, at + 2, third) in 3 end else 2 end

fun _language_index {index:nat | index <= LANGUAGE_COUNT} .<LANGUAGE_COUNT - index>.
  (language: int, index: int index): [found:int | ~1 <= found; found < LANGUAGE_COUNT] int found =
  if index >= LANGUAGE_COUNT then ~1
  else if _code_of_string(_language_code(index)) = language then index
  else _language_index(language, index + 1)

(* language's name (its code's letters when it is not one of the list)
   at out[at, ...): where it ends *)
fn _language_put {l:agz}{n:nat}{at:nat | at + 32 <= n} (out: !$A.arr(byte, l, n), at: int at, language: int): [stop:nat | stop <= at + 32] int stop = let
  val index = _language_index(language, 0)
in
  if index >= 0 then let
    val name = _language_name(index)
  in _put_string(out, at, name, g1u2i(string1_length(name)), 0) end
  else at + _code_put(out, at, language)
end

(* ============================================================
   The dictionaries
   ============================================================ *)

(* Each dictionary: its number (its files' keys), language, kind (1 a
   .dict.dz, 2 with a .syn), name (name_len bytes, the .ifo's bookname)
   and types (types_len bytes, its sametypesequence, or none) *)
datavtype dicts(int) =
  | DictsNil(0) of ()
  | {count:nat}{name_loc,types_loc:agz}{name_len:pos | name_len <= 255}{types_len:nat | types_len <= 16}
    DictsCons(count + 1) of (int, int, int, $A.arr(byte, name_loc, 256), int name_len, $A.arr(byte, types_loc, 16), int types_len, dicts(count))

fun _dicts_free {count:nat} .<count>. (list: dicts(count)): void =
  case+ list of
  | ~DictsNil() => ()
  | ~DictsCons(_, _, _, name, _, types, _, rest) => let
      val () = $A.free<byte>(name)
      val () = $A.free<byte>(types)
    in _dicts_free(rest) end

fun _dicts_count {count:nat} .<count>. (list: !dicts(count)): int count =
  case+ list of
  | DictsNil() => 0
  | @DictsCons(_, _, _, _, _, _, _, rest) => let
      val count = 1 + _dicts_count(rest)
      prval () = fold@(list)
    in count end

(* list, then back *)
fun _dicts_join {front,back:nat} .<front>. (list: dicts(front), back: dicts(back)): dicts(front + back) =
  case+ list of
  | ~DictsNil() => back
  | ~DictsCons(id, language, kind, name, name_len, types, types_len, rest) =>
    DictsCons(id, language, kind, name, name_len, types, types_len, _dicts_join(rest, back))

(* list with extra put in at index (at its end, past it) *)
fun _dicts_insert {count,extra:nat} .<count>. (list: dicts(count), index: int, extra: dicts(extra)): dicts(count + extra) =
  if index <= 0 then _dicts_join(extra, list)
  else (case+ list of
    | ~DictsNil() => extra
    | ~DictsCons(id, language, kind, name, name_len, types, types_len, rest) =>
      DictsCons(id, language, kind, name, name_len, types, types_len, _dicts_insert(rest, index - 1, extra)))

(* list without the entry at index, and that entry (none past its end) *)
fun _dicts_take_at {count:nat} .<count>. (list: dicts(count), index: int)
  : [left,taken:nat | left + taken == count; taken <= 1] @(dicts(left), dicts(taken)) =
  case+ list of
  | ~DictsNil() => @(DictsNil(), DictsNil())
  | ~DictsCons(id, language, kind, name, name_len, types, types_len, rest) =>
    if index = 0 then @(rest, DictsCons(id, language, kind, name, name_len, types, types_len, DictsNil()))
    else let
      val @(left, taken) = _dicts_take_at(rest, index - 1)
    in @(DictsCons(id, language, kind, name, name_len, types, types_len, left), taken) end

(* list without the entry numbered id, and that entry *)
fun _dicts_take_id {count:nat} .<count>. (list: dicts(count), id: int)
  : [left,taken:nat | left + taken == count; taken <= 1] @(dicts(left), dicts(taken)) =
  case+ list of
  | ~DictsNil() => @(DictsNil(), DictsNil())
  | ~DictsCons(entry_id, language, kind, name, name_len, types, types_len, rest) =>
    if entry_id = id then @(rest, DictsCons(entry_id, language, kind, name, name_len, types, types_len, DictsNil()))
    else let
      val @(left, taken) = _dicts_take_id(rest, id)
    in @(DictsCons(entry_id, language, kind, name, name_len, types, types_len, left), taken) end

(* The number of the first dictionary of language, and its kind; -1 when none serves it *)
fun _dicts_for {count:nat} .<count>. (list: !dicts(count), language: int): @(int, int) =
  case+ list of
  | DictsNil() => @(~1, 0)
  | @DictsCons(id, entry_language, kind, _, _, _, _, rest) =>
    if entry_language = language then let
      val found = @(id, kind)
      prval () = fold@(list)
    in found end
    else let
      val found = _dicts_for(rest, language)
      prval () = fold@(list)
    in found end

(* The number of the entry at index, or -1 *)
fun _dicts_id_at {count:nat} .<count>. (list: !dicts(count), index: int): int =
  case+ list of
  | DictsNil() => ~1
  | @DictsCons(id, _, _, _, _, _, _, rest) =>
    if index = 0 then let val found = id; prval () = fold@(list) in found end
    else let
      val found = _dicts_id_at(rest, index - 1)
      prval () = fold@(list)
    in found end

fn _copy_256 {l:agz} (source: !$A.arr(byte, l, 256)): [copy_loc:agz] $A.arr(byte, copy_loc, 256) = let
  val copy = $A.alloc<byte>(256)
  val () = _copy_bytes(source, 0, copy, 0, 256, 0)
in copy end

fn _copy_16 {l:agz} (source: !$A.arr(byte, l, 16)): [copy_loc:agz] $A.arr(byte, copy_loc, 16) = let
  val copy = $A.alloc<byte>(16)
  val () = _copy_bytes(source, 0, copy, 0, 16, 0)
in copy end

(* An entry's kind, name and types, copied *)
datavtype entry_got =
  | {name_loc,types_loc:agz}{name_len:pos | name_len <= 255}{types_len:nat | types_len <= 16}
    EntryGot of (int, $A.arr(byte, name_loc, 256), int name_len, $A.arr(byte, types_loc, 16), int types_len)
  | EntryNone of ()

fun _dicts_entry {count:nat} .<count>. (list: !dicts(count), id: int): entry_got =
  case+ list of
  | DictsNil() => EntryNone()
  | @DictsCons(entry_id, _, kind, name, name_len, types, types_len, rest) =>
    if entry_id = id then let
      val got = EntryGot(kind, _copy_256(name), name_len, _copy_16(types), types_len)
      prval () = fold@(list)
    in got end
    else let
      val got = _dicts_entry(rest, id)
      prval () = fold@(list)
    in got end

(* The dictionaries, and the number the next one imported takes *)
datavtype dict_cell = {count:nat} DictCell of (dicts(count), int)

val _dicts = ref<dict_cell>(DictCell(DictsNil(), 1))

fn _dicts_take (): dict_cell = let
  var cell: dict_cell = DictCell(DictsNil(), 1)
  val () = ref_exch_elt<dict_cell>(_dicts, cell)
in cell end

fn _dicts_put (cell: dict_cell): void = let
  var previous: dict_cell = cell
  val () = ref_exch_elt<dict_cell>(_dicts, previous)
  val+ ~DictCell(list, _) = previous
in _dicts_free(list) end

(* The dictionaries removed whose Undo is still offered: they are kept
   (and stored) until it is made final *)
datavtype pending_cell = {count:nat} PendingCell of (dicts(count))

val _pending = ref<pending_cell>(PendingCell(DictsNil()))

fn _pending_take (): pending_cell = let
  var cell: pending_cell = PendingCell(DictsNil())
  val () = ref_exch_elt<pending_cell>(_pending, cell)
in cell end

fn _pending_put (cell: pending_cell): void = let
  var previous: pending_cell = cell
  val () = ref_exch_elt<pending_cell>(_pending, previous)
  val+ ~PendingCell(list) = previous
in _dicts_free(list) end

(* ============================================================
   Storage: the list under "dicts", each one's files under its number
   ============================================================ *)

(* The storage key of dictionary id's .idx ('I'), .dict or .dict.dz
   ('D'), .syn ('S') or table ('X') *)
fn _file_key {letter:nat | letter < 256} (letter: int letter, id: int): [l:agz] $A.arr(byte, l, 15) = lib_key(letter, 0, id)

fn _file_delete {letter:nat | letter < 256} (letter: int letter, id: int): void = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_file_key(letter, id))
  (* ignored: a delete that fails leaves bytes nothing reads *)
  val () = $P.finish<$IDB.stored>($IDB.idb_delete(key_bytes, 15), llam(_) => ())
in release_bytes(key_frozen, key_bytes) end

fn _files_delete (id: int): void = let
  val () = _file_delete(73, id)
  val () = _file_delete(68, id)
  val () = _file_delete(83, id)
in _file_delete(88, id) end

(* The entries of list at out[at, ...): each its number, language,
   kind, name's length and name, and types' length and types *)
fun _write_entries {l:agz}{n:nat}{count:nat}{at:nat | at + ENTRY_MOST * count <= n} .<count>.
  (out: !$A.arr(byte, l, n), at: int at, list: !dicts(count)): [stop:nat | stop <= at + ENTRY_MOST * count] int stop =
  case+ list of
  | DictsNil() => at
  | @DictsCons(id, language, kind, name, name_len, types, types_len, rest) => let
      val () = u32_put(out, at, id)
      val () = u32_put(out, at + 4, language)
      val () = $A.write_byte(out, at + 8, $AR.low_byte(kind))
      val () = $A.write_byte(out, at + 9, name_len)
      val () = _copy_bytes(name, 0, out, at + 10, name_len, 0)
      val () = $A.write_byte(out, at + 10 + name_len, types_len)
      val () = _copy_bytes(types, 0, out, at + 11 + name_len, types_len, 0)
      val stop = _write_entries(out, at + 11 + name_len + types_len, rest)
      prval () = fold@(list)
    in stop end

(* Stores the list (with the dictionaries whose removal can still be
   undone) under "dicts" *)
fn _save (): void = let
  val+ ~DictCell(list, next_id) = _dicts_take()
  val+ ~PendingCell(pending) = _pending_take()
  val total = _dicts_count(list) + _dicts_count(pending)
  val size = 12 + ENTRY_MOST * total
in
  if size > 1048576 then let
    val () = _pending_put(PendingCell(pending))
  in _dicts_put(DictCell(list, next_id)) end
  else let
    val out = $A.alloc<byte>(size)
    val () = $A.write_text(out, 0, $A.text_lit("QDC1"), 4)
    val () = u32_put(out, 4, next_id)
    val () = u32_put(out, 8, total)
    val stop = _write_entries(out, 12, list)
    val stop = _write_entries(out, stop, pending)
    val () = _pending_put(PendingCell(pending))
    val () = _dicts_put(DictCell(list, next_id))
    val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
    val @(used, rest) = $A.borrow_split<byte>(out_frozen, out_bytes, stop)
    val @(key, key_len) = _id_bytes("dicts")
    val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
    (* never over a list that could not be read *)
    val () = (if storage_savable(DictionariesRecord()) then save_checked($IDB.idb_put(key_bytes, key_len, used, stop)) else ())
    val () = release_bytes(key_frozen, key_bytes)
    val out_bytes = $A.borrow_join<byte>(out_frozen, used, rest)
  in release_bytes(out_frozen, out_bytes) end
end

(* The entries stored at data[at, n), remaining of them, after list *)
fun _parse_entries {l:agz}{n:pos}{at:nat | at <= n}{remaining:nat}{count:nat} .<remaining>.
  (data: !$A.arr(byte, l, n), n: int n, at: int at, remaining: int remaining, list: dicts(count)): [total:nat] dicts(total) =
  if remaining <= 0 then list
  else if at + 11 > n then list
  else let
    val id = u32_at(data, at)
    val language = u32_at(data, at + 4)
    val kind = _byte_at(data, at + 8)
    val name_len = _byte_at(data, at + 9)
  in
    if name_len <= 0 then list
    else if at + 11 + name_len > n then list
    else let
      val types_len = _byte_at(data, at + 10 + name_len)
    in
      if types_len > 16 then list
      else if at + 11 + name_len + types_len > n then list
      else if id <= 0 then list
      else if ~_language_valid(language) then list
      else let
        val name = $A.alloc<byte>(256)
        val () = _copy_bytes(data, at + 10, name, 0, name_len, 0)
        val types = $A.alloc<byte>(16)
        val () = _copy_bytes(data, at + 11 + name_len, types, 0, types_len, 0)
        val list = _dicts_join(list, DictsCons(id, language, kind, name, name_len, types, types_len, DictsNil()))
      in _parse_entries(data, n, at + 11 + name_len + types_len, remaining - 1, list) end
    end
  end

(* Reads the dictionaries stored under "dicts" *)
#pub fn dict_load (): $P.promise(int, $P.Chained)

implement dict_load () = let
  val @(key, key_len) = _id_bytes("dicts")
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val stored = $IDB.idb_get(key_bytes, key_len)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><int>(stored, llam(found) =>
    case+ lookup_bytes(found) of
    | ~NothingStored() => $P.ret<int>(0)
    | ~StoredUnreadable() => let val () = storage_unreadable(DictionariesRecord()) in $P.ret<int>(0) end
    | ~StoredBytes(data, n) =>
      if n < 12 then let val () = $A.free<byte>(data) in $P.ret<int>(0) end
      else if _byte_at(data, 0) <> 81 then let val () = $A.free<byte>(data) in $P.ret<int>(0) end
      else if _byte_at(data, 1) <> 68 then let val () = $A.free<byte>(data) in $P.ret<int>(0) end
      else let
        val next_id = u32_at(data, 4)
        val total = u32_at(data, 8)
        val total = (if total < 0 then 0 else if total > 1000 then 1000 else total): [total:nat | total <= 1000] int total
        val list = _parse_entries(data, n, 12, total, DictsNil())
        val () = $A.free<byte>(data)
        val () = _dicts_put(DictCell(list, (if next_id > 0 then next_id else 1000)))
      in $P.ret<int>(0) end)
end

(* ============================================================
   The open dictionary: its files, as the JS side holds them
   ============================================================ *)

datavtype file_slot =
  | {n:nat} FileSlot of ($BF.infile(n), int n)
  | NoFile of ()

fn _slot_close (slot: file_slot): void =
  case+ slot of
  | ~FileSlot(file, _) => $BF.file_close(file)
  | ~NoFile() => ()

fn _slot_take (cell: ref(file_slot)): file_slot = let
  var slot: file_slot = NoFile()
  val () = ref_exch_elt<file_slot>(cell, slot)
in slot end

(* Puts slot in cell; a file it held is closed *)
fn _slot_put (cell: ref(file_slot), slot: file_slot): void = let
  var previous: file_slot = slot
  val () = ref_exch_elt<file_slot>(cell, previous)
in _slot_close(previous) end

(* The size of the file cell holds, or -1 *)
fn _slot_size (cell: ref(file_slot)): int = let
  val slot = _slot_take(cell)
in
  case+ slot of
  | @FileSlot(_, size) => let
      val found = size
      prval () = fold@(slot)
      val () = _slot_put(cell, slot)
    in found end
  | NoFile() => let val () = _slot_put(cell, slot) in ~1 end
end

(* The dictionary a lookup reads: its number, .idx, .dict (or
   .dict.dz), .syn and table; or the one whose files are being read;
   or none *)
datavtype loaded =
  | {idx_size,dict_size,table_size:nat}
    Loaded of (int, $BF.infile(idx_size), int idx_size, $BF.infile(dict_size), int dict_size, file_slot, $BF.infile(table_size), int table_size)
  | Loading of (int)
  | NotLoaded of ()

val _loaded = ref<loaded>(NotLoaded())

fn _loaded_free (open_dictionary: loaded): void =
  case+ open_dictionary of
  | ~Loaded(_, idx, _, dict, _, syn, table, _) => let
      val () = $BF.file_close(idx)
      val () = $BF.file_close(dict)
      val () = _slot_close(syn)
    in $BF.file_close(table) end
  | ~Loading(_) => ()
  | ~NotLoaded() => ()

fn _loaded_take (): loaded = let
  var open_dictionary: loaded = NotLoaded()
  val () = ref_exch_elt<loaded>(_loaded, open_dictionary)
in open_dictionary end

fn _loaded_put (open_dictionary: loaded): void = let
  var previous: loaded = open_dictionary
  val () = ref_exch_elt<loaded>(_loaded, previous)
in _loaded_free(previous) end

(* The files of the dictionary being read, as they come *)
val _gather_table = ref<file_slot>(NoFile())
val _gather_idx = ref<file_slot>(NoFile())
val _gather_dict = ref<file_slot>(NoFile())
val _gather_syn = ref<file_slot>(NoFile())

(* The number of the latest reading of a dictionary's files: a reading
   a later one has taken the place of keeps none of its files *)
val _reading = ref<int>(0)

(* Dictionary id's file stored under letter, read into cell for reading
   number reading *)
fn _fetch {letter:nat | letter < 256} (letter: int letter, id: int, cell: ref(file_slot), reading: int): $P.promise(int, $P.Chained) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_file_key(letter, id))
  val stored = $BF.file_idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$BF.file_lookup><int>(stored, llam(found) =>
    case+ found of
    | ~$BF.FileAbsent() => let val () = _slot_put(cell, NoFile()) in $P.ret<int>(0) end
    (* not read: the dictionary stays unopened, and is read again at
       the next lookup *)
    | ~$BF.FileUnreadable() => let val () = _slot_put(cell, NoFile()) in $P.ret<int>(0) end
    | ~$BF.FileFound(file) =>
      if !_reading <> reading then let val () = $BF.file_close(file) in $P.ret<int>(0) end
      else let
        val size = $BF.file_size(file)
        val () = _slot_put(cell, FileSlot(file, size))
      in $P.ret<int>(0) end)
end

(* The dictionary id whose files were gathered: open, when its table,
   .idx and .dict all came (else it stays Loading, so it is not read
   again) *)
fn _assemble (id: int, table: file_slot, idx: file_slot, dict: file_slot, syn: file_slot): loaded =
  case+ table of
  | ~NoFile() => let
      val () = _slot_close(idx)
      val () = _slot_close(dict)
      val () = _slot_close(syn)
    in Loading(id) end
  | ~FileSlot(table_file, table_size) =>
    (case+ idx of
     | ~NoFile() => let
         val () = $BF.file_close(table_file)
         val () = _slot_close(dict)
         val () = _slot_close(syn)
       in Loading(id) end
     | ~FileSlot(idx_file, idx_size) =>
       (case+ dict of
        | ~NoFile() => let
            val () = $BF.file_close(table_file)
            val () = $BF.file_close(idx_file)
            val () = _slot_close(syn)
          in Loading(id) end
        | ~FileSlot(dict_file, dict_size) => Loaded(id, idx_file, idx_size, dict_file, dict_size, syn, table_file, table_size)))

fn _is_loaded (open_dictionary: !loaded): bool =
  case+ open_dictionary of
  | @Loaded(_, _, _, _, _, _, _, _) => let prval () = fold@(open_dictionary) in true end
  | _ => false

(* The files read for dictionary id (the reading-th read) put together:
   true when the dictionary is open then *)
fn _gather_finish (id: int, reading: int): bool =
  if !_reading <> reading then false
  else let
  val table = _slot_take(_gather_table)
  val idx = _slot_take(_gather_idx)
  val dict = _slot_take(_gather_dict)
  val syn = _slot_take(_gather_syn)
  val current = _loaded_take()
in
  case+ current of
  | @Loading(loading_id) =>
    if loading_id = id then let
      prval () = fold@(current)
      val () = _loaded_free(current)
      val assembled = _assemble(id, table, idx, dict, syn)
      val opened = _is_loaded(assembled)
      val () = _loaded_put(assembled)
    in opened end
    else let
      prval () = fold@(current)
      val () = _slot_close(table)
      val () = _slot_close(idx)
      val () = _slot_close(dict)
      val () = _slot_close(syn)
      val () = _loaded_put(current)
    in false end
  | _ => let
      val () = _slot_close(table)
      val () = _slot_close(idx)
      val () = _slot_close(dict)
      val () = _slot_close(syn)
      val () = _loaded_put(current)
    in false end
  end

(* Reads dictionary id's files (with its .syn when kind says it has
   one); the promise resolves true once they are open *)
fn _load (id: int, kind: int): $P.promise(bool, $P.Chained) = let
  val () = _loaded_put(Loading(id))
  val reading = !_reading + 1
  val () = !_reading := reading
  val () = _slot_put(_gather_table, NoFile())
  val () = _slot_put(_gather_idx, NoFile())
  val () = _slot_put(_gather_dict, NoFile())
  val () = _slot_put(_gather_syn, NoFile())
  val with_syn = $AR.band_int_int(kind, 2) <> 0
  val gathered = $P.and_then<int><int>(_fetch(88, id, _gather_table, reading), llam(_) =>
    $P.and_then<int><int>(_fetch(73, id, _gather_idx, reading), llam(_) =>
      $P.and_then<int><int>(_fetch(68, id, _gather_dict, reading), llam(_) =>
        if with_syn then _fetch(83, id, _gather_syn, reading)
        else let val () = _slot_put(_gather_syn, NoFile()) in $P.ret<int>(0) end)))
in
  (* each file's read keeps what it found in its slot, which
     _gather_finish checks *)
  $P.and_then<int><bool>(gathered, llam(_) => $P.ret<bool>(_gather_finish(id, reading)))
end

(* The dictionary closed: the next lookup reads its files again *)
fn _unload (): void = _loaded_put(NotLoaded())

(* ============================================================
   Finding a word
   ============================================================ *)

(* The big-endian u32 at file[at, at + 4): -1 when it is outside the
   file or 2^31 or more *)
fn _file_u32 {n:nat} (file: !$BF.infile(n), size: int n, at: int): [value:int | value >= ~1] int value = let
  val at = g1ofg0(at)
in
  if at < 0 then ~1
  else if at + 4 > size then ~1
  else let
    val bytes = $A.alloc<byte>(4)
    val () = $BF.file_read(file, at, bytes, 4)
    val value = u32_at(bytes, 0)
    val () = $A.free<byte>(bytes)
  in value end
end

(* Sample `sample` of the table's directory at dir_at: where its entry is, or -1 *)
fn _entry_at {n:nat} (table: !$BF.infile(n), table_size: int n, dir_at: int, sample: int): int =
  if sample < 0 then ~1
  else if sample > 100000000 then ~1
  else _file_u32(table, table_size, dir_at + 4 * sample)

(* Sample `sample`'s record's position in its file, and its word at
   word[0, word_len); the position -1 when the table does not have it *)
fn _sample {n:nat}{l:agz} (table: !$BF.infile(n), table_size: int n, dir_at: int, sample: int, word: !$A.arr(byte, l, 256))
  : @(int, [word_len:nat | word_len <= 255] int word_len) = let
  val entry = g1ofg0(_entry_at(table, table_size, dir_at, sample))
in
  if entry < 0 then @(~1, 0)
  else if entry + 5 > table_size then @(~1, 0)
  else let
    val head = $A.alloc<byte>(5)
    val () = $BF.file_read(table, entry, head, 5)
    val position = u32_at(head, 0)
    val word_len = _byte_at(head, 4)
    val () = $A.free<byte>(head)
  in
    if word_len > 255 then @(~1, 0)
    else if entry + 5 + word_len > table_size then @(~1, 0)
    else let
      val () = $BF.file_read(table, entry + 5, word, word_len)
    in @(position, word_len) end
  end
end

fn _sample_position {n:nat} (table: !$BF.infile(n), table_size: int n, dir_at: int, sample: int): int =
  _file_u32(table, table_size, _entry_at(table, table_size, dir_at, sample))

(* The first of samples [low, high) whose word does not sort before
   query (ASCII case set aside), or high *)
fun _lower_bound {n:nat}{query_loc,word_loc:agz}{query_len:nat | query_len <= 65}{low,high:nat | low <= high} .<high - low>.
  (table: !$BF.infile(n), table_size: int n, dir_at: int, query: !$A.arr(byte, query_loc, 65), query_len: int query_len,
   low: int low, high: int high, word: !$A.arr(byte, word_loc, 256)): [found:nat | found <= high] int found =
  if low >= high then low
  else let
    val middle = g1ofg0(low + (high - low) / 2)
  in
    if middle < low then low
    else if middle >= high then low
    else let
      val @(position, word_len) = _sample(table, table_size, dir_at, middle, word)
      val order = (if position < 0 then 1 else word_fold_compare(word, 0, word_len, query, query_len)): int
    in
      if order < 0 then _lower_bound(table, table_size, dir_at, query, query_len, middle + 1, high, word)
      else _lower_bound(table, table_size, dir_at, query, query_len, low, middle, word)
    end
  end

(* The records of block[at, n), each a word, its 0 byte and tail bytes:
   the first whose word is query (2), else the first that differs from
   it only in ASCII case (1), else none (0); and its place *)
fun _walk {l,query_loc:agz}{n:nat}{at:nat | at <= n}{tail:nat}{query_len:nat | query_len <= 65} .<n - at>.
  (block: !$A.arr(byte, l, n), n: int n, at: int at, tail: int tail,
   query: !$A.arr(byte, query_loc, 65), query_len: int query_len, folded: int): @(int, int) =
  if at >= n then (if folded >= 0 then @(1, folded) else @(0, 0))
  else let
    val limit = (if at + 256 < n then at + 256 else n): [limit:nat | at <= limit; limit <= n] int limit
    val zero = zero_at(block, at, limit)
  in
    if zero >= limit then (if folded >= 0 then @(1, folded) else @(0, 0))
    else if zero + 1 + tail > n then (if folded >= 0 then @(1, folded) else @(0, 0))
    else let
      val order = word_fold_compare(block, at, zero - at, query, query_len)
    in
      if order < 0 then _walk(block, n, zero + 1 + tail, tail, query, query_len, folded)
      else if order > 0 then (if folded >= 0 then @(1, folded) else @(0, 0))
      else if word_equal(block, at, zero - at, query, query_len) then @(2, at)
      else _walk(block, n, zero + 1 + tail, tail, query, query_len, (if folded >= 0 then folded else at))
    end
  end

(* query among file's records [block_start, stop) (at most BLOCK_MOST bytes
   of them): as _walk finds it, with its position in the file *)
fn _scan {n:nat}{query_loc:agz}{tail:nat}{query_len:nat | query_len <= 65}
  (file: !$BF.infile(n), size: int n, block_start: int, stop: int, tail: int tail,
   query: !$A.arr(byte, query_loc, 65), query_len: int query_len): @(int, int) = let
  val block_start = g1ofg0(block_start)
  val stop = g1ofg0(stop)
in
  if block_start < 0 then @(0, 0)
  else if stop > size then @(0, 0)
  else if stop <= block_start then @(0, 0)
  else let
    val block_len = _least(stop - block_start, BLOCK_MOST)
    val block = $A.alloc<byte>(block_len)
    val () = $BF.file_read(file, block_start, block, block_len)
    val @(kind, at) = _walk(block, block_len, 0, tail, query, query_len, ~1)
    val () = $A.free<byte>(block)
  in @(kind, block_start + at) end
end

(* query in file's records, whose samples are the table's directory at
   dir_at (samples of them): where it is, and how it matched (as _walk) *)
fn _search {n,table_n:nat}{query_loc:agz}{tail:nat}{query_len:nat | query_len <= 65}
  (file: !$BF.infile(n), size: int n, table: !$BF.infile(table_n), table_size: int table_n, dir_at: int, samples: int, tail: int tail,
   query: !$A.arr(byte, query_loc, 65), query_len: int query_len): @(int, int) = let
  val samples = g1ofg0(samples)
in
  if samples <= 0 then @(0, 0)
  else let
    val word = $A.alloc<byte>(256)
    val bound = _lower_bound(table, table_size, dir_at, query, query_len, 0, samples, word)
    val () = $A.free<byte>(word)
    val start = (if bound > 0 then bound - 1 else 0): [start:nat] int start
    val block_start = _sample_position(table, table_size, dir_at, start)
    val stop = (if start + 2 < samples then _sample_position(table, table_size, dir_at, start + 2) else size): int
  in
    if block_start < 0 then @(0, 0)
    else _scan(file, size, block_start, (if stop < 0 then size else stop), tail, query, query_len)
  end
end

(* An .idx record: its word, and its article's offset and size *)
datavtype record_got =
  | {l:agz}{word_len:nat | word_len <= 255} RecordGot of ($A.arr(byte, l, 256), int word_len, int, int)
  | NoRecord of ()

fn _idx_record {n:nat} (idx: !$BF.infile(n), size: int n, position: int): record_got = let
  val position = g1ofg0(position)
in
  if position < 0 then NoRecord()
  else if position >= size then NoRecord()
  else let
    val record_len = _least(size - position, RECORD_MOST)
    val record = $A.alloc<byte>(RECORD_MOST)
    val () = $BF.file_read(idx, position, record, record_len)
    val zero = zero_at(record, 0, record_len)
  in
    if zero > 255 then let val () = $A.free<byte>(record) in NoRecord() end
    else if zero + 9 > record_len then let val () = $A.free<byte>(record) in NoRecord() end
    else let
      val offset = u32_at(record, zero + 1)
      val article_size = u32_at(record, zero + 5)
      val word = $A.alloc<byte>(256)
      val () = _copy_bytes(record, 0, word, 0, zero, 0)
      val () = $A.free<byte>(record)
    in
      if offset < 0 then let val () = $A.free<byte>(word) in NoRecord() end
      else if article_size < 0 then let val () = $A.free<byte>(word) in NoRecord() end
      else RecordGot(word, zero, offset, article_size)
    end
  end
end

(* The number after the word of a .syn record, record[0, record_len),
   whose word ends at zero; -1 when it is cut short *)
fn _target_at {l:agz}{record_len:nat | record_len <= 261}{zero:nat | zero <= record_len}
  (record: !$A.arr(byte, l, 261), zero: int zero, record_len: int record_len): int =
  if zero + 5 > record_len then ~1 else u32_at(record, zero + 1)

(* The .idx record a .syn record at position names: its number, or -1 *)
fn _syn_target {n:nat} (syn: !$BF.infile(n), size: int n, position: int): int = let
  val position = g1ofg0(position)
in
  if position < 0 then ~1
  else if position >= size then ~1
  else let
    val record_len = _least(size - position, 261)
    val record = $A.alloc<byte>(261)
    val () = $BF.file_read(syn, position, record, record_len)
    val zero = zero_at(record, 0, record_len)
    val target = _target_at(record, zero, record_len)
    val () = $A.free<byte>(record)
  in target end
end

(* After count records of block[at, n), each a word, its 0 byte and
   tail bytes: where the next begins, or -1 *)
fun _skip {l:agz}{n:nat}{at:nat | at <= n}{tail:nat} .<n - at>.
  (block: !$A.arr(byte, l, n), n: int n, at: int at, tail: int tail, count: int): int =
  if count <= 0 then at
  else if at >= n then ~1
  else let
    val limit = (if at + 256 < n then at + 256 else n): [limit:nat | at <= limit; limit <= n] int limit
    val zero = zero_at(block, at, limit)
  in
    if zero >= limit then ~1
    else if zero + 1 + tail > n then ~1
    else _skip(block, n, zero + 1 + tail, tail, count - 1)
  end

(* The position of the .idx's record number nth, or -1 *)
fn _nth_position {n,table_n:nat} (idx: !$BF.infile(n), size: int n, table: !$BF.infile(table_n), table_size: int table_n, nth: int): int =
  if nth < 0 then ~1
  else let
    val sample = nth / 64
    val block_start = g1ofg0(_sample_position(table, table_size, 32, sample))
  in
    if sample >= _file_u32(table, table_size, 4) then ~1
    else if block_start < 0 then ~1
    else if block_start >= size then ~1
    else let
      val block_len = _least(size - block_start, 64 * RECORD_MOST)
      val block = $A.alloc<byte>(block_len)
      val () = $BF.file_read(idx, block_start, block, block_len)
      val at = _skip(block, block_len, 0, 8, nth - sample * 64)
      val () = $A.free<byte>(block)
    in if at < 0 then ~1 else block_start + at end
  end

(* query (query_len bytes) in the open dictionary: its headword, then
   it with ASCII case set aside, then among the .syn's other forms *)
fn _lookup {idx_n,table_n:nat}{query_loc:agz}{query_len:nat | query_len <= 65}
  (idx: !$BF.infile(idx_n), idx_size: int idx_n, syn: !file_slot, table: !$BF.infile(table_n), table_size: int table_n,
   query: !$A.arr(byte, query_loc, 65), query_len: int query_len): record_got = let
  val idx_samples = _file_u32(table, table_size, 4)
  val @(kind, position) = _search(idx, idx_size, table, table_size, 32, idx_samples, 8, query, query_len)
in
  if kind > 0 then _idx_record(idx, idx_size, position)
  else (case+ syn of
    | @FileSlot(syn_file, syn_size) => let
        val syn_samples = _file_u32(table, table_size, 12)
        val @(syn_kind, syn_position) = _search(syn_file, syn_size, table, table_size, 32 + 4 * idx_samples, syn_samples, 4, query, query_len)
        val target = (if syn_kind > 0 then _syn_target(syn_file, syn_size, syn_position) else ~1): int
        prval () = fold@(syn)
      in
        if target < 0 then NoRecord()
        else _idx_record(idx, idx_size, _nth_position(idx, idx_size, table, table_size, target))
      end
    | NoFile() => NoRecord())
end

(* The word found by the last lookup: its dictionary, headword, and
   article's offset and size *)
datavtype hit =
  | {l:agz}{word_len:nat | word_len <= 255} Hit of (int, $A.arr(byte, l, 256), int word_len, int, int)
  | NoHit of ()

val _hit = ref<hit>(NoHit())

fn _hit_take (): hit = let
  var found: hit = NoHit()
  val () = ref_exch_elt<hit>(_hit, found)
in found end

fn _hit_put (found: hit): void = let
  var previous: hit = found
  val () = ref_exch_elt<hit>(_hit, previous)
in
  case+ previous of
  | ~Hit(_, word, _, _, _) => $A.free<byte>(word)
  | ~NoHit() => ()
end

(* Whether a byte is one a word is trimmed of: white space and ASCII
   punctuation around it *)
fn _trimmed (code: int): bool =
  code <= 32 || code = 33 || code = 34 || code = 39 || code = 40 || code = 41 || code = 44 || code = 46
  || code = 58 || code = 59 || code = 63 || code = 91 || code = 93 || code = 123 || code = 125

fun _trim_start {l:agz}{n:pos}{stop:nat | stop <= n}{at:nat | at <= stop} .<stop - at>.
  (word: !$A.arr(byte, l, n), at: int at, stop: int stop): [start:nat | at <= start; start <= stop] int start =
  if at >= stop then stop
  else if _trimmed(_byte_at(word, at)) then _trim_start(word, at + 1, stop)
  else at

fun _trim_end {l:agz}{n:pos}{start:nat}{stop:nat | start <= stop; stop <= n} .<stop - start>.
  (word: !$A.arr(byte, l, n), start: int start, stop: int stop): [end_at:nat | start <= end_at; end_at <= stop] int end_at =
  if stop <= start then start
  else if _trimmed(_byte_at(word, stop - 1)) then _trim_end(word, start, stop - 1)
  else stop

(* What a lookup found: the word, which dict_show then shows (DictFound);
   not the word (DictMissing); or that the dictionary's files are being
   read for it (DictReading): its promise resolves true once they are
   open, when the lookup can be made again *)
#pub datavtype dict_found =
  | DictFound of ()
  | DictMissing of ()
  | DictReading of $P.promise(bool, $P.Chained)

(* Looks word[0, word_len) up in the first dictionary of the language
   code[0, code_len) names. When that dictionary's files are not read
   yet, they are read (DictReading) *)
#pub fn dict_find {code_loc,word_loc:agz}{word_size:pos}{word_len:nat | word_len <= word_size}
  (code: !$A.arr(byte, code_loc, 3), code_len: int, word: !$A.arr(byte, word_loc, word_size), word_len: int word_len): dict_found

implement dict_find (code, code_len, word, word_len) = let
  val () = _hit_put(NoHit())
  val code_len = g1ofg0(code_len)
  val language = (if code_len >= 0 then (if code_len <= 3 then _language_of_bytes(code, code_len) else ~1) else ~1): int
  val start = _trim_start(word, 0, word_len)
  val stop = _trim_end(word, start, word_len)
  val+ ~DictCell(list, next_id) = _dicts_take()
  val @(id, kind) = _dicts_for(list, language)
  val () = _dicts_put(DictCell(list, next_id))
in
  if id < 0 then DictMissing()
  else if stop - start <= 0 then DictMissing()
  else if stop - start > 64 then DictMissing()
  else let
    val current = _loaded_take()
  in
    case+ current of
    | @Loaded(loaded_id, idx, idx_size, _, _, syn, table, table_size) =>
      if loaded_id = id then let
        val query = $A.alloc<byte>(65)
        val () = _copy_bytes(word, start, query, 0, stop - start, 0)
        val found = _lookup(idx, idx_size, syn, table, table_size, query, stop - start)
        val () = $A.free<byte>(query)
        prval () = fold@(current)
        val () = _loaded_put(current)
      in
        case+ found of
        | ~RecordGot(headword, headword_len, offset, size) => let
            val () = _hit_put(Hit(id, headword, headword_len, offset, size))
          in DictFound() end
        | ~NoRecord() => DictMissing()
      end
      else let
        prval () = fold@(current)
        val () = _loaded_put(current)
      in DictReading(_load(id, kind)) end
    (* the files are being read already: that read's lookup is made
       again once they are open *)
    | @Loading(loading_id) =>
      if loading_id = id then let prval () = fold@(current); val () = _loaded_put(current) in DictMissing() end
      else let
        prval () = fold@(current)
        val () = _loaded_put(current)
      in DictReading(_load(id, kind)) end
    | NotLoaded() => let
        val () = _loaded_put(current)
      in DictReading(_load(id, kind)) end
  end
end

(* ============================================================
   The article
   ============================================================ *)

(* The article data[start, stop) of dictionary id, shown as text *)
fn _article_show {l:agz}{o:addr}{n:nat}{start,stop:nat | start <= stop; stop <= n}
  (id: int, data: !$A.arrx(byte, l, n, o), start: int start, stop: int stop): void = let
  val+ ~DictCell(list, next_id) = _dicts_take()
  val entry = _dicts_entry(list, id)
  val () = _dicts_put(DictCell(list, next_id))
in
  case+ entry of
  | ~EntryNone() => ()
  | ~EntryGot(_, name, _, types, types_len) => let
      val () = $A.free<byte>(name)
      val out = $A.alloc<byte>(65535)
      val text_len = article_text(data, start, stop, types, types_len, out)
      val () = $A.free<byte>(types)
    in
      if text_len < 0 then let
        val () = $A.free<byte>(out)
      in ui_text("dictionary-article", "This dictionary's articles can't be shown.") end
      else ui_text_buf("dictionary-article", out, text_len)
    end
end

fn _article_unread (): void = ui_text("dictionary-article", "This article could not be read.")

(* content[relative, relative + read_len) of chunks inflated, the
   article of dictionary id, shown *)
fn _inflated_show {l:agz}{o:addr}{n:nat}{read_len:pos}
  (id: int, content: !$A.arrx(byte, l, n, o), content_size: int n, relative: int, read_len: int read_len): void = let
  val start = g1ofg0(relative)
in
  if start < 0 then _article_unread()
  else if start >= content_size then _article_unread()
  else _article_show(id, content, start, start + _least(read_len, content_size - start))
end

(* Article [offset, offset + read_len) of dictionary id, from its
   .dict.dz: the chunks that hold it inflated together (each but the
   file's last ends with a full flush, so a final empty block is put
   after the last of them), into an arena piece *)
fn _article_dz {dict_n,table_n:nat}{read_len:pos}
  (id: int, dict: !$BF.infile(dict_n), dict_size: int dict_n, table: !$BF.infile(table_n), table_size: int table_n,
   offset: int, read_len: int read_len): void = let
  val chunk_length = _file_u32(table, table_size, 20)
  val chunk_count = _file_u32(table, table_size, 24)
  val chunks_at = _file_u32(table, table_size, 28)
in
  if chunk_length <= 0 then _article_unread()
  else if chunk_count <= 0 then _article_unread()
  else if chunks_at < 0 then _article_unread()
  else let
    val first = offset / chunk_length
    val last = (offset + read_len - 1) / chunk_length
  in
    if last >= chunk_count then _article_unread()
    else if last - first > 64 then _article_unread()
    else let
      val compressed_start = _file_u32(table, table_size, chunks_at + 4 * first)
      val compressed_stop = _file_u32(table, table_size, chunks_at + 4 * (last + 1))
      val finishing = last + 1 < chunk_count
    in
      if compressed_start < 0 then _article_unread()
      else if compressed_stop <= compressed_start then _article_unread()
      else if compressed_stop > dict_size then _article_unread()
      else let
        val compressed_len = compressed_stop - compressed_start
        val piece_len = compressed_len + 5
      in
        if piece_len > 268435456 then _article_unread()
        else (case+ piece_new(piece_len) of
          | ~NoPiece() => _article_unread()
          | ~Piece(owner, compressed) => let
              val () = $BF.file_read(dict, compressed_start, compressed, compressed_len)
              (* a stored block, final and empty: 1, then LEN 0 and NLEN 0xFFFF *)
              val () = $A.write_byte(compressed, compressed_len, 1)
              val () = $A.write_byte(compressed, compressed_len + 1, 0)
              val () = $A.write_byte(compressed, compressed_len + 2, 0)
              val () = $A.write_byte(compressed, compressed_len + 3, 255)
              val () = $A.write_byte(compressed, compressed_len + 4, 255)
              val inflate_len = piece_len - ((if finishing then 0 else 5): [cut:int | cut == 0 || cut == 5] int cut)
              val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
              val @(used, rest) = $A.borrow_split<byte>(compressed_frozen, compressed_bytes, inflate_len)
              val inflating = decompress(used, inflate_len, $BD.DeflateRaw())
              val compressed_bytes = $A.borrow_join<byte>(compressed_frozen, used, rest)
              val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
              val () = piece_free(owner, $A.thaw<byte>(compressed_frozen))
              val relative = offset - first * chunk_length
            in
              $P.finish<decompressed>(inflating, llam(inflated) =>
                case+ take_decompressed(inflated) of
                | ~NoContentBytes() => _article_unread()
                | ~ContentBytes(content_owner, content, content_size) => let
                    val () = _inflated_show(id, content, content_size, relative, read_len)
                  in piece_free(content_owner, content) end)
            end)
      end
    end
  end
end

(* The article of the last lookup's word, read and shown *)
fn _article (id: int, kind: int, offset: int, size: int): void = let
  val read_len = _least(g1ofg0(size), ARTICLE_READ_MOST)
  val offset = g1ofg0(offset)
  val current = _loaded_take()
in
  case+ current of
  | @Loaded(loaded_id, _, _, dict, dict_size, _, table, table_size) =>
    if loaded_id <> id then let
      prval () = fold@(current)
      val () = _loaded_put(current)
    in _article_unread() end
    else if read_len <= 0 then let
      prval () = fold@(current)
      val () = _loaded_put(current)
    in ui_text("dictionary-article", "-") end
    else if offset < 0 then let
      prval () = fold@(current)
      val () = _loaded_put(current)
    in _article_unread() end
    else if $AR.band_int_int(kind, 1) <> 0 then let
      val () = _article_dz(id, dict, dict_size, table, table_size, offset, read_len)
      prval () = fold@(current)
    in _loaded_put(current) end
    else if offset + read_len > dict_size then let
      prval () = fold@(current)
      val () = _loaded_put(current)
    in _article_unread() end
    else (case+ piece_new(read_len) of
      | ~NoPiece() => let
          prval () = fold@(current)
          val () = _loaded_put(current)
        in _article_unread() end
      | ~Piece(owner, data) => let
          val () = $BF.file_read(dict, offset, data, read_len)
          prval () = fold@(current)
          val () = _loaded_put(current)
          val () = _article_show(id, data, 0, read_len)
        in piece_free(owner, data) end)
  | _ => let
      val () = _loaded_put(current)
    in _article_unread() end
end

(* Shows the word the last dict_find found, in the dictionary panel *)
#pub fn dict_show (): void

implement dict_show () =
  case+ _hit_take() of
  | ~NoHit() => ()
  | ~Hit(id, word, word_len, offset, size) => let
      val () = ui_text_buf("dictionary-word", word, word_len)
      val+ ~DictCell(list, next_id) = _dicts_take()
      val entry = _dicts_entry(list, id)
      val () = _dicts_put(DictCell(list, next_id))
    in
      case+ entry of
      | ~EntryNone() => ()
      | ~EntryGot(kind, name, name_len, types, _) => let
          val () = $A.free<byte>(types)
          val () = ui_text_buf("dictionary-source", name, name_len)
          val () = ui_text("dictionary-article", "-")
          val () = layer_open(LDictionary())
          val () = ui_focus("dictionary-close")
        in _article(id, kind, offset, size) end
    end

(* ============================================================
   The dictionaries panel
   ============================================================ *)

(* Each entry's row from index on: its name and language, and Remove *)
fun _rows {count:nat}{index:nat} .<count>. (list: !dicts(count), index: int index): void =
  case+ list of
  | DictsNil() => ()
  | @DictsCons(_, language, _, name, name_len, _, _, rest) => let
      val @(row, row_len) = nid_make("dictionary-row", index)
      val () = ui_add_n("dictionaries-list", row, row_len, TDiv)
      val @(row, row_len) = nid_make("dictionary-row", index)
      val () = ui_attr_n(row, row_len, AClass, "srow")
      val @(row, row_len) = nid_make("dictionary-row", index)
      val @(label, label_len) = nid_make("dictionary-name", index)
      val () = ui_add_nn(row, row_len, label, label_len, TB)
      val text = $A.alloc<byte>(320)
      val () = _copy_bytes(name, 0, text, 0, name_len, 0)
      val at = _put_string(text, name_len, " \xC2\xB7 ", 4, 0)
      val text_len = _language_put(text, at, language)
      val @(label, label_len) = nid_make("dictionary-name", index)
      val () = ui_text_n_buf(label, label_len, text, text_len)
      val @(row, row_len) = nid_make("dictionary-row", index)
      val @(label, label_len) = nid_make("dictionary-name", index)
      val () = ui_labelled_nn(row, row_len, NGroup, label, label_len)
      val @(row, row_len) = nid_make("dictionary-row", index)
      val @(remove, remove_len) = nid_make("drop-dictionary", index)
      val () = ui_text_btn_nn(row, row_len, remove, remove_len, "btn", "Remove")
      val () = _rows(rest, index + 1)
      prval () = fold@(list)
    in end

fn _render (): void = let
  val () = ui_clear("dictionaries-list")
  val+ ~DictCell(list, next_id) = _dicts_take()
  val count = _dicts_count(list)
  val () = _rows(list, 0)
  val () = _dicts_put(DictCell(list, next_id))
in ui_show("dictionaries-none", count = 0) end

(* The language choice's options, language chosen (a language not in
   the list first, when it is one) *)
fun _options {index:nat | index <= LANGUAGE_COUNT} .<LANGUAGE_COUNT - index>. (index: int index, chosen: int): void =
  if index >= LANGUAGE_COUNT then ()
  else let
    val code = _language_code(index)
    val code_len = g1u2i(string1_length(code))
    val value = $A.alloc<byte>(3)
    val _ = _put_string(value, 0, code, code_len, 0)
    val name = _language_name(index)
    val name_len = g1u2i(string1_length(name))
    val label = $A.alloc<byte>(name_len)
    val _ = _put_string(label, 0, name, name_len, 0)
    val @(option, option_len) = nid_make("language-option", index)
    val () = ui_option("dictionary-language", option, option_len, value, code_len, label, name_len, _code_of_string(code) = chosen)
  in _options(index + 1, chosen) end

fn _language_choice (chosen: int): void = let
  val () = ui_clear("dictionary-language")
  val () = (if _language_index(chosen, 0) < 0 then
      (if _language_valid(chosen) then let
         val value = $A.alloc<byte>(3)
         val value_len = _code_put(value, 0, chosen)
         val label = $A.alloc<byte>(3)
         val label_len = _code_put(label, 0, chosen)
         val @(option, option_len) = nid_make("language-option", LANGUAGE_COUNT)
       in ui_option("dictionary-language", option, option_len, value, value_len, label, label_len, true) end
       else ())
    else ())
in _options(0, chosen) end

(* Opens the dictionaries panel, its language choice at the language
   code[0, code_len) names (English when it names none) *)
#pub fn dict_panel_open {code_loc:agz} (code: !$A.arr(byte, code_loc, 3), code_len: int): void

implement dict_panel_open (code, code_len) = let
  val code_len = g1ofg0(code_len)
  val language = (if code_len >= 0 then (if code_len <= 3 then _language_of_bytes(code, code_len) else ~1) else ~1): int
  val () = _render()
  val () = _language_choice((if language > 0 then language else ENGLISH): int)
  val () = ui_text_buf("dictionaries-status", $A.alloc<byte>(1), 0)
  val () = layer_open(LDictionaries())
in ui_focus("dictionaries-done") end

(* Dictionary id, removed for good once its Undo is not taken *)
fn _forget (id: int): void = let
  val+ ~PendingCell(pending) = _pending_take()
  val @(left, taken) = _dicts_take_id(pending, id)
  val () = _dicts_free(taken)
  val () = _pending_put(PendingCell(left))
  val () = _files_delete(id)
in _save() end

(* Dictionary id put back at index *)
fn _restore (id: int, index: int): void = let
  val+ ~PendingCell(pending) = _pending_take()
  val @(left, taken) = _dicts_take_id(pending, id)
  val () = _pending_put(PendingCell(left))
  val+ ~DictCell(list, next_id) = _dicts_take()
  val () = _dicts_put(DictCell(_dicts_insert(list, index, taken), next_id))
  val () = _render()
in _save() end

(* Removes the dictionary at index of the panel's list: at once, and
   offered back by the Undo toast; its files go when the offer is made
   final *)
#pub fn dict_remove (index: int): void

implement dict_remove (index) = let
  val+ ~DictCell(list, next_id) = _dicts_take()
  val id = _dicts_id_at(list, index)
  val @(left, taken) = _dicts_take_at(list, index)
  val () = _dicts_put(DictCell(left, next_id))
  val+ ~PendingCell(pending) = _pending_take()
  val () = _pending_put(PendingCell(_dicts_join(pending, taken)))
in
  if id < 0 then ()
  else let
    val () = _unload()
    val () = _render()
  in $P.finish<settled>(undo_offer("Dictionary removed"), llam(how) =>
    case+ how of
    | Undone() => _restore(id, index)
    | Final() => _forget(id)) end
end

(* ============================================================
   Import
   ============================================================ *)

(* The files picked, by what they are; whether the articles are a
   .dict.dz; and the language chosen *)
val _import_ifo = ref<file_slot>(NoFile())
val _import_idx = ref<file_slot>(NoFile())
val _import_dict = ref<file_slot>(NoFile())
val _import_syn = ref<file_slot>(NoFile())
val _import_compressed = ref<bool>(false)
val _import_language = ref<int>(ENGLISH)

fn _import_clear (): void = let
  val () = _slot_put(_import_ifo, NoFile())
  val () = _slot_put(_import_idx, NoFile())
  val () = _slot_put(_import_dict, NoFile())
in _slot_put(_import_syn, NoFile()) end

fn _refuse {text_len:pos | text_len < 256} (text: string text_len): void = let
  val () = _import_clear()
  val () = modal_inform("Dictionary not imported")
in modal_text_lit(text) end

(* The language chosen in the panel; English when none is *)
fn _chosen_language (): int = let
  val @(id, id_len) = _id_bytes("dictionary-language")
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val value = $DR.read_input_value(id_bytes, id_len)
  val () = release_bytes(id_frozen, id_bytes)
in
  case+ value of
  | ~$R.none() => ENGLISH
  | ~$R.some(blob) => let
      val value_len = $BD.blob_len(blob)
    in
      if value_len < 2 then let val () = $BD.blob_free(blob) in ENGLISH end
      else if value_len > 3 then let val () = $BD.blob_free(blob) in ENGLISH end
      else let
        val code = $A.alloc<byte>(3)
        val () = $BD.blob_read(blob, 0, code, value_len)
        val () = $BD.blob_free(blob)
        val language = _language_of_bytes(code, value_len)
        val () = $A.free<byte>(code)
      in if language > 0 then language else ENGLISH end
    end
end

(* Whether name[0, name_len) ends with suffix, letters in any case *)
fun _ends_at {l:agz}{n:pos}{name_len:nat | name_len <= n}{suffix_len:nat | suffix_len <= name_len}{i:nat | i <= suffix_len} .<suffix_len - i>.
  (name: !$A.arr(byte, l, n), name_len: int name_len, suffix: string suffix_len, suffix_len: int suffix_len, i: int i): bool =
  if i >= suffix_len then true
  else let
    val code = _byte_at(name, name_len - suffix_len + i)
    val lower = (if code >= 65 && code <= 90 then code + 32 else code): int
  in
    if lower <> char2int0(string_get_at(suffix, i)) then false
    else _ends_at(name, name_len, suffix, suffix_len, i + 1)
  end

fn _ends_with {l:agz}{n:pos}{name_len:nat | name_len <= n}{suffix_len:pos}
  (name: !$A.arr(byte, l, n), name_len: int name_len, suffix: string suffix_len): bool = let
  val suffix_len = g1u2i(string1_length(suffix))
in if suffix_len > name_len then false else _ends_at(name, name_len, suffix, suffix_len, 0) end

fn _name_kind {l:agz}{name_len:nat | name_len <= 16} (tail: !$A.arr(byte, l, 16), name_len: int name_len): int =
  if _ends_with(tail, name_len, ".ifo") then 1
  else if _ends_with(tail, name_len, ".idx") then 2
  else if _ends_with(tail, name_len, ".dict") then 3
  else if _ends_with(tail, name_len, ".dz") then 4
  else if _ends_with(tail, name_len, ".syn") then 5
  else 0

(* What a file is, by its name's end: 1 an .ifo, 2 an .idx, 3 a .dict,
   4 a .dict.dz, 5 a .syn, 0 none of them *)
fn _file_kind {n:nat} (file: !$BF.infile(n)): int =
  case+ $BF.file_name(file) of
  | ~$R.none() => 0
  | ~$R.some(blob) => let
      val name_len = $BD.blob_len(blob)
    in
      if name_len <= 0 then let val () = $BD.blob_free(blob) in 0 end
      else let
        val tail_len = _least(name_len, 16)
        val tail = $A.alloc<byte>(16)
        val () = $BD.blob_read(blob, name_len - tail_len, tail, tail_len)
        val () = $BD.blob_free(blob)
        val kind = _name_kind(tail, tail_len)
        val () = $A.free<byte>(tail)
      in kind end
    end

(* The file an open promise resolved with, kept by what it is; false
   when it could not be read *)
fn _keep_file (opened: $BF.opened): bool =
  case+ opened of
  (* gone from the input before it was read: the check finds it
     missing *)
  | ~$BF.NotOpened() => true
  | ~$BF.OpenFailed() => false
  | ~$BF.Opened(file) => let
      val size = $BF.file_size(file)
      val kind = _file_kind(file)
      val () =
        if kind = 1 then _slot_put(_import_ifo, FileSlot(file, size))
        else if kind = 2 then _slot_put(_import_idx, FileSlot(file, size))
        else if kind = 3 then let
          val () = !_import_compressed := false
        in _slot_put(_import_dict, FileSlot(file, size)) end
        else if kind = 4 then let
          val () = !_import_compressed := true
        in _slot_put(_import_dict, FileSlot(file, size)) end
        else if kind = 5 then _slot_put(_import_syn, FileSlot(file, size))
        else $BF.file_close(file)
    in true end

(* An index file (an .idx or a .syn) read whole, for its import *)
datavtype index_piece =
  | {arena_loc,piece_loc:agz}{n:pos} IndexPiece of (piece_owner(n, arena_loc), $A.arrx(byte, piece_loc, n, arena_loc), int n)
  | NoIndex of ()
  | BadIndex of ()

fn _index_free (index: index_piece): void =
  case+ index of
  | ~IndexPiece(owner, data, _) => piece_free(owner, data)
  | ~NoIndex() => ()
  | ~BadIndex() => ()

fn _index_read (cell: ref(file_slot)): index_piece =
  case+ _slot_take(cell) of
  | ~NoFile() => NoIndex()
  | ~FileSlot(file, size) =>
    if size <= 0 then let val () = _slot_put(cell, FileSlot(file, size)) in BadIndex() end
    else if size > 268435456 then let val () = _slot_put(cell, FileSlot(file, size)) in BadIndex() end
    else (case+ piece_new(size) of
      | ~NoPiece() => let val () = _slot_put(cell, FileSlot(file, size)) in BadIndex() end
      | ~Piece(owner, data) => let
          val () = $BF.file_read(file, 0, data, size)
          val () = _slot_put(cell, FileSlot(file, size))
        in IndexPiece(owner, data, size) end)

(* The records of data[at, n), each a word under 256 bytes, its 0 byte
   and tail bytes: whether they are whole, and how many there are and
   the bytes their samples' entries take *)
fun _survey {l:agz}{o:addr}{n:nat}{at:nat | at <= n}{tail:nat} .<n - at>.
  (data: !$A.arrx(byte, l, n, o), n: int n, at: int at, tail: int tail, records: int, entry_bytes: int): @(bool, int, int) =
  if at >= n then @(true, records, entry_bytes)
  else let
    val limit = (if at + 256 < n then at + 256 else n): [limit:nat | at <= limit; limit <= n] int limit
    val zero = zero_at(data, at, limit)
  in
    if zero >= limit then @(false, records, entry_bytes)
    else if zero + 1 + tail > n then @(false, records, entry_bytes)
    else let
      val entry = (if records - (records / 64) * 64 = 0 then 5 + (zero - at) else 0): int
    in _survey(data, n, zero + 1 + tail, tail, records + 1, entry_bytes + entry) end
  end

fn _index_survey {tail:nat} (index: !index_piece, tail: int tail): @(bool, int, int) =
  case+ index of
  | @IndexPiece(_, data, n) => let
      val surveyed = _survey(data, n, 0, tail, 0, 0)
      prval () = fold@(index)
    in surveyed end
  | NoIndex() => @(true, 0, 0)
  | BadIndex() => @(false, 0, 0)

fn _index_present (index: !index_piece): bool =
  case+ index of
  | @IndexPiece(_, _, _) => let prval () = fold@(index) in true end
  | _ => false

(* Every 64th record of data[at, n) (as _survey reads them), from record
   number record: its place in the table's directory at dir_at, and its
   entry from entry_at; where the entries end *)
fun _write_samples {l,table_loc:agz}{o,table_owner:addr}{n,table_n:nat}{at:nat | at <= n}{tail:nat} .<n - at>.
  (data: !$A.arrx(byte, l, n, o), n: int n, at: int at, tail: int tail, record: int,
   table: !$A.arrx(byte, table_loc, table_n, table_owner), table_size: int table_n, dir_at: int, entry_at: int): int =
  if at >= n then entry_at
  else let
    val limit = (if at + 256 < n then at + 256 else n): [limit:nat | at <= limit; limit <= n; limit <= at + 256] int limit
    val zero = zero_at(data, at, limit)
  in
    if zero >= limit then entry_at
    else if zero + 1 + tail > n then entry_at
    else if record - (record / 64) * 64 <> 0 then
      _write_samples(data, n, zero + 1 + tail, tail, record + 1, table, table_size, dir_at, entry_at)
    else let
      val word_len = zero - at
      val directory = g1ofg0(dir_at + 4 * (record / 64))
      val entry = g1ofg0(entry_at)
      val () = (if directory >= 0 then (if directory + 4 <= table_size then u32_put(table, directory, entry_at) else ()) else ())
      val () = (if entry >= 0 then
          (if entry + 5 + word_len <= table_size then let
             val () = u32_put(table, entry, at)
             val () = $A.write_byte(table, entry + 4, word_len)
           in _copy_bytes(data, at, table, entry + 5, word_len, 0) end
           else ())
        else ())
    in _write_samples(data, n, zero + 1 + tail, tail, record + 1, table, table_size, dir_at, entry_at + 5 + word_len) end
  end

fn _index_samples {table_loc:agz}{table_owner:addr}{table_n:nat}{tail:nat}
  (index: !index_piece, tail: int tail, table: !$A.arrx(byte, table_loc, table_n, table_owner), table_size: int table_n, dir_at: int, entry_at: int): int =
  case+ index of
  | @IndexPiece(_, data, n) => let
      val stop = _write_samples(data, n, 0, tail, 0, table, table_size, dir_at, entry_at)
      prval () = fold@(index)
    in stop end
  | NoIndex() => entry_at
  | BadIndex() => entry_at

(* A .dict.dz's head, read for its chunks: the bytes read, the chunk
   length and count, where the chunks' sizes are in the head, and where
   the first chunk begins in the file *)
datavtype dz_head =
  | {l:agz}{n:pos} DzHead of ($A.arr(byte, l, n), int n, int, int, int, int)
  | NotCompressed of ()
  | BadHead of ()

fn _dz_free (head: dz_head): void =
  case+ head of
  | ~DzHead(bytes, _, _, _, _, _) => $A.free<byte>(bytes)
  | ~NotCompressed() => ()
  | ~BadHead() => ()

(* head[at] when it is in the head, else -1 *)
fn _head_byte {l:agz}{n:pos} (head: !$A.arr(byte, l, n), n: int n, at: int): int = let
  val at = g1ofg0(at)
in if at < 0 then ~1 else if at >= n then ~1 else _byte_at(head, at) end

fn _head_u16 {l:agz}{n:pos} (head: !$A.arr(byte, l, n), n: int n, at: int): int = let
  val low = _head_byte(head, n, at)
  val high = _head_byte(head, n, at + 1)
in if low < 0 then ~1 else if high < 0 then ~1 else low + high * 256 end

(* The "RA" subfield of the extra field head[at, stop): where its data
   begins, and its length; -1 when there is none *)
fun _find_ra {l:agz}{n:pos}{stop:nat}{at:nat | at <= stop} .<stop - at>.
  (head: !$A.arr(byte, l, n), n: int n, at: int at, stop: int stop): @(int, int) =
  if at + 4 > stop then @(~1, 0)
  else let
    val length = _head_u16(head, n, at + 2)
  in
    if length < 0 then @(~1, 0)
    else if _head_byte(head, n, at) = 82 && _head_byte(head, n, at + 1) = 65 then @(at + 4, length)
    else let
      val next = g1ofg0(at + 4 + length)
    in if next > stop then @(~1, 0) else if next <= at then @(~1, 0) else _find_ra(head, n, next, stop) end
  end

(* Where the 0 byte ending a name in head from at is, past it *)
fun _past_zero {l:agz}{n:pos}{at:nat | at <= n} .<n - at>. (head: !$A.arr(byte, l, n), n: int n, at: int at): int =
  if at >= n then ~1
  else if _byte_at(head, at) = 0 then at + 1
  else _past_zero(head, n, at + 1)

fn _skip_name {l:agz}{n:pos} (head: !$A.arr(byte, l, n), n: int n, at: int): int = let
  val at = g1ofg0(at)
in if at < 0 then ~1 else if at > n then ~1 else _past_zero(head, n, at) end

(* The sum of the chunks' sizes, count of them at head[at] *)
fun _sizes_sum {l:agz}{n:pos}{count:nat} .<count>. (head: !$A.arr(byte, l, n), n: int n, at: int, count: int count, sum: int): int =
  if count <= 0 then sum
  else let
    val size = _head_u16(head, n, at)
  in if size < 0 then ~1 else _sizes_sum(head, n, at + 2, count - 1, sum + size) end

(* A gzip head with dictzip's chunks, checked against the file's size *)
fn _dz_parse {l:agz}{n:pos} (head: $A.arr(byte, l, n), n: int n, file_size: int): dz_head =
  if _head_byte(head, n, 0) <> 31 then let val () = $A.free<byte>(head) in BadHead() end
  else if _head_byte(head, n, 1) <> 139 then let val () = $A.free<byte>(head) in BadHead() end
  else if _head_byte(head, n, 2) <> 8 then let val () = $A.free<byte>(head) in BadHead() end
  else let
    val flags = _head_byte(head, n, 3)
    val extra_len = _head_u16(head, n, 10)
  in
    if flags < 0 then let val () = $A.free<byte>(head) in BadHead() end
    else if $AR.band_int_int(flags, 4) = 0 then let val () = $A.free<byte>(head) in BadHead() end
    else if extra_len < 0 then let val () = $A.free<byte>(head) in BadHead() end
    else if 12 + extra_len > n then let val () = $A.free<byte>(head) in BadHead() end
    else let
      val extra_stop = g1ofg0(12 + extra_len)
      val @(ra_at, ra_len) = (if extra_stop >= 12 then _find_ra(head, n, 12, extra_stop) else @(~1, 0)): @(int, int)
      val chunk_length = _head_u16(head, n, ra_at + 2)
      val chunk_count = g1ofg0(_head_u16(head, n, ra_at + 4))
      val after_name = (if $AR.band_int_int(flags, 8) <> 0 then _skip_name(head, n, 12 + extra_len) else 12 + extra_len): int
      val after_comment = (if after_name < 0 then ~1 else if $AR.band_int_int(flags, 16) <> 0 then _skip_name(head, n, after_name) else after_name): int
      val data_start = (if after_comment < 0 then ~1 else if $AR.band_int_int(flags, 2) <> 0 then after_comment + 2 else after_comment): int
    in
      if ra_at < 0 then let val () = $A.free<byte>(head) in BadHead() end
      else if chunk_length <= 0 then let val () = $A.free<byte>(head) in BadHead() end
      else if chunk_count <= 0 then let val () = $A.free<byte>(head) in BadHead() end
      else if ra_len < 6 + 2 * chunk_count then let val () = $A.free<byte>(head) in BadHead() end
      else if data_start < 0 then let val () = $A.free<byte>(head) in BadHead() end
      else let
        val total = _sizes_sum(head, n, ra_at + 6, chunk_count, 0)
      in
        if total < 0 then let val () = $A.free<byte>(head) in BadHead() end
        else if data_start + total > file_size then let val () = $A.free<byte>(head) in BadHead() end
        else DzHead(head, n, chunk_length, chunk_count, ra_at + 6, data_start)
      end
    end
  end

fn _dz_read (): dz_head =
  if ~(!_import_compressed) then NotCompressed()
  else (case+ _slot_take(_import_dict) of
    | ~NoFile() => BadHead()
    | ~FileSlot(file, size) =>
      if size < 18 then let val () = _slot_put(_import_dict, FileSlot(file, size)) in BadHead() end
      else let
        val head_len = _least(size, 70000)
        val head = $A.alloc<byte>(head_len)
        val () = $BF.file_read(file, 0, head, head_len)
        val () = _slot_put(_import_dict, FileSlot(file, size))
      in _dz_parse(head, head_len, size) end)

fn _dz_chunks (head: !dz_head): int =
  case+ head of
  | @DzHead(_, _, _, chunk_count, _, _) => let
      val count = chunk_count
      prval () = fold@(head)
    in count end
  | _ => 0

fn _dz_bad (head: !dz_head): bool =
  case+ head of
  | BadHead() => true
  | _ => false

(* The chunks' offsets in the file, and its end, from chunk on, at the
   table's chunks_at *)
fun _write_chunks {l,table_loc:agz}{table_owner:addr}{n:pos}{table_n:nat}{count:nat}{chunk:nat | chunk <= count} .<count - chunk>.
  (head: !$A.arr(byte, l, n), n: int n, sizes_at: int, count: int count, chunk: int chunk, offset: int,
   table: !$A.arrx(byte, table_loc, table_n, table_owner), table_size: int table_n, chunks_at: int): void = let
  val at = g1ofg0(chunks_at + 4 * chunk)
  val () = (if at >= 0 then (if at + 4 <= table_size then u32_put(table, at, offset) else ()) else ())
in
  if chunk >= count then ()
  else let
    val size = _head_u16(head, n, sizes_at + 2 * chunk)
  in _write_chunks(head, n, sizes_at, count, chunk + 1, offset + ((if size > 0 then size else 0): int), table, table_size, chunks_at) end
end

(* value at the table's [at, at + 4), when that is in it *)
fn _table_put {table_loc:agz}{table_owner:addr}{table_n:nat}
  (table: !$A.arrx(byte, table_loc, table_n, table_owner), table_size: int table_n, at: int, value: int): void = let
  val at = g1ofg0(at)
in if at >= 0 then (if at + 4 <= table_size then u32_put(table, at, value) else ()) else () end

fn _dz_write {table_loc:agz}{table_owner:addr}{table_n:nat}
  (head: !dz_head, table: !$A.arrx(byte, table_loc, table_n, table_owner), table_size: int table_n, chunks_at: int): void =
  case+ head of
  | @DzHead(bytes, n, chunk_length, chunk_count, sizes_at, data_start) => let
      val () = _table_put(table, table_size, 20, chunk_length)
      val () = _table_put(table, table_size, 24, chunk_count)
      val count = g1ofg0(chunk_count)
      val () = (if count >= 0 then _write_chunks(bytes, n, sizes_at, count, 0, data_start, table, table_size, chunks_at) else ())
      prval () = fold@(head)
    in end
  | _ => ()

(* The table of a dictionary whose .idx and .syn are idx and syn (read
   whole), and whose head is a .dict.dz's or none: made, and stored
   under 'X' for dictionary id; false when it cannot be made *)
fn _table_store (id: int, idx: !index_piece, idx_records: int, idx_entry_bytes: int,
  syn: !index_piece, syn_records: int, syn_entry_bytes: int, head: !dz_head): bool = let
  val idx_samples = (idx_records + 63) / 64
  val syn_samples = (syn_records + 63) / 64
  val chunk_count = _dz_chunks(head)
  val chunks_at = 32 + 4 * idx_samples + 4 * syn_samples
  val entries_at = chunks_at + ((if chunk_count > 0 then 4 * (chunk_count + 1) else 0): int)
  val table_size = g1ofg0(entries_at + idx_entry_bytes + syn_entry_bytes)
in
  if table_size < 32 then false
  else if table_size > 268435456 then false
  else (case+ piece_new(table_size) of
    | ~NoPiece() => false
    | ~Piece(owner, table) => let
        val () = $A.write_text(table, 0, $A.text_lit("QDX1"), 4)
        val () = u32_put(table, 4, idx_samples)
        val () = u32_put(table, 8, idx_records)
        val () = u32_put(table, 12, syn_samples)
        val () = u32_put(table, 16, syn_records)
        val () = u32_put(table, 20, 0)
        val () = u32_put(table, 24, 0)
        val () = u32_put(table, 28, chunks_at)
        val () = _dz_write(head, table, table_size, chunks_at)
        val syn_entries_at = _index_samples(idx, 8, table, table_size, 32, entries_at)
        val _ = _index_samples(syn, 4, table, table_size, 32 + 4 * idx_samples, syn_entries_at)
        val @(table_frozen, table_bytes) = $A.freeze<byte>(table)
        val @(key_frozen, key_bytes) = $A.freeze<byte>(_file_key(88, id))
        val () = save_checked($IDB.idb_put(key_bytes, 15, table_bytes, table_size))
        val () = release_bytes(key_frozen, key_bytes)
        val () = $A.drop<byte>(table_frozen, table_bytes)
        val () = piece_free(owner, $A.thaw<byte>(table_frozen))
      in true end)
end

(* Two stores, both kept (Stored), or not *)
fn _both_stored (first: $IDB.stored, second: $IDB.stored): $IDB.stored =
  case+ first of
  | $IDB.Stored() => second
  | $IDB.NotStored() => $IDB.NotStored()

(* The file cell holds, stored under letter for dictionary id from the
   JS side, and closed *)
fn _file_store {letter:nat | letter < 256} (cell: ref(file_slot), letter: int letter, id: int): $P.promise($IDB.stored, $P.Chained) =
  case+ _slot_take(cell) of
  | ~NoFile() => $P.ret<$IDB.stored>($IDB.Stored())
  | ~FileSlot(file, _) => let
      val @(key_frozen, key_bytes) = $A.freeze<byte>(_file_key(letter, id))
      val stored = $BF.file_idb_put(key_bytes, 15, file)
      val () = release_bytes(key_frozen, key_bytes)
      (* the JS side took the file's bytes as the call was made *)
      val () = $BF.file_close(file)
    in stored end

fn _free_entry {name_loc,types_loc:agz} (name: $A.arr(byte, name_loc, 256), types: $A.arr(byte, types_loc, 16)): void = let
  val () = $A.free<byte>(name)
in $A.free<byte>(types) end

(* The dictionary named name[0, name_len), its types types[0,
   types_len): its files and table stored, then added to the list *)
fn _import_store {name_loc,types_loc:agz}{name_len:pos | name_len <= 255}{types_len:nat | types_len <= 16}
  (name: $A.arr(byte, name_loc, 256), name_len: int name_len, types: $A.arr(byte, types_loc, 16), types_len: int types_len): void = let
  val idx = _index_read(_import_idx)
  val syn = _index_read(_import_syn)
  val @(idx_whole, idx_records, idx_entry_bytes) = _index_survey(idx, 8)
  val @(syn_whole, syn_records, syn_entry_bytes) = _index_survey(syn, 4)
  val has_syn = _index_present(syn)
  val head = _dz_read()
  val head_bad = _dz_bad(head)
in
  if ~idx_whole then let
    val () = _index_free(idx)
    val () = _index_free(syn)
    val () = _dz_free(head)
    val () = _free_entry(name, types)
  in _refuse("The dictionary's .idx file could not be read.") end
  else if ~syn_whole then let
    val () = _index_free(idx)
    val () = _index_free(syn)
    val () = _dz_free(head)
    val () = _free_entry(name, types)
  in _refuse("The dictionary's .syn file could not be read.") end
  else if head_bad then let
    val () = _index_free(idx)
    val () = _index_free(syn)
    val () = _dz_free(head)
    val () = _free_entry(name, types)
  in _refuse("The dictionary's .dict.dz file is not a dictzip file.") end
  else let
    val+ ~DictCell(list, next_id) = _dicts_take()
    val id = next_id
    val () = _dicts_put(DictCell(list, next_id + 1))
    val made = _table_store(id, idx, idx_records, idx_entry_bytes, syn, syn_records, syn_entry_bytes, head)
    val () = _index_free(idx)
    val () = _index_free(syn)
    val compressed = _dz_chunks(head) > 0
    val () = _dz_free(head)
  in
    if ~made then let
      val () = _free_entry(name, types)
    in _refuse("The dictionary is too large to import.") end
    else let
      val kind = ((if compressed then 1 else 0): int) + ((if has_syn then 2 else 0): int)
      val language = !_import_language
      (* each file stored in turn; NotStored when one was not, so one
         that failed is not lost *)
      val stored = $P.and_then<$IDB.stored><$IDB.stored>(_file_store(_import_idx, 73, id), llam(idx_status) =>
        $P.and_then<$IDB.stored><$IDB.stored>(_file_store(_import_dict, 68, id), llam(dict_status) =>
          $P.and_then<$IDB.stored><$IDB.stored>(_file_store(_import_syn, 83, id), llam(syn_status) =>
            $P.ret<$IDB.stored>(_both_stored(_both_stored(idx_status, dict_status), syn_status)))))
      val () = _slot_put(_import_ifo, NoFile())
      val+ ~DictCell(list, next_id) = _dicts_take()
      val () = _dicts_put(DictCell(_dicts_join(list, DictsCons(id, language, kind, name, name_len, types, types_len, DictsNil())), next_id))
      val () = _unload()
      val () = _render()
    in
      $P.finish<$IDB.stored>(stored, llam(status) => let
        val () = _save()
      in
        case+ status of
        | $IDB.Stored() => ui_text("dictionaries-status", "Dictionary added.")
        | $IDB.NotStored() => ui_text("dictionaries-status", "The dictionary's files could not be stored. The browser's storage may be full: free some space, remove it and import it again.")
      end)
    end
  end
end

(* The .ifo's value of key, at most most bytes, at out[0, ...) (cut
   where a character begins): how many *)
fn _ifo_text {l,out_loc:agz}{n:pos}{key_len:pos | key_len < 64}{most:nat | most <= 256}
  (ifo: !$A.arr(byte, l, n), n: int n, key: string key_len, out: !$A.arr(byte, out_loc, 256), most: int most): [text_len:nat | text_len <= most] int text_len = let
  val @(found, start, stop) = ifo_find(ifo, n, key)
in
  if ~found then 0
  else let
    val text_len = _least(stop - start, most)
    val () = _copy_bytes(ifo, start, out, 0, text_len, 0)
  in utf8_cut(out, text_len) end
end

(* The files picked, checked: the .ifo read, and the dictionary stored
   when its .idx and articles are there and as the .ifo says *)
fn _import_check (): void =
  case+ _slot_take(_import_ifo) of
  | ~NoFile() => _refuse("The dictionary's .ifo file is missing.")
  | ~FileSlot(ifo_file, ifo_size) =>
    if ifo_size <= 0 then let val () = $BF.file_close(ifo_file) in _refuse("This is not a StarDict dictionary's .ifo file.") end
    else if ifo_size > 65536 then let val () = $BF.file_close(ifo_file) in _refuse("This is not a StarDict dictionary's .ifo file.") end
    else let
      val ifo = $A.alloc<byte>(ifo_size)
      val () = $BF.file_read(ifo_file, 0, ifo, ifo_size)
      val () = $BF.file_close(ifo_file)
      val stardict = ifo_is_stardict(ifo, ifo_size)
      val offset_bits = ifo_number(ifo, ifo_size, "idxoffsetbits")
      val idx_file_size = ifo_number(ifo, ifo_size, "idxfilesize")
      val name = $A.alloc<byte>(256)
      val name_len = _ifo_text(ifo, ifo_size, "bookname", name, 255)
      val types = $A.alloc<byte>(256)
      val types_len = _ifo_text(ifo, ifo_size, "sametypesequence", types, 16)
      val () = $A.free<byte>(ifo)
      val types_kept = $A.alloc<byte>(16)
      val () = _copy_bytes(types, 0, types_kept, 0, types_len, 0)
      val () = $A.free<byte>(types)
      val idx_size = _slot_size(_import_idx)
      val+ ~DictCell(list, next_id) = _dicts_take()
      val count = _dicts_count(list)
      val () = _dicts_put(DictCell(list, next_id))
    in
      if ~stardict then let
        val () = _free_entry(name, types_kept)
      in _refuse("This is not a StarDict dictionary's .ifo file.") end
      else if offset_bits = 64 then let
        val () = _free_entry(name, types_kept)
      in _refuse("This dictionary uses 64-bit offsets, which Quire does not read.") end
      else if idx_size < 0 then let
        val () = _free_entry(name, types_kept)
      in _refuse("The dictionary's .idx file is missing.") end
      else if idx_file_size <> idx_size then let
        val () = _free_entry(name, types_kept)
      in _refuse("The dictionary's .idx file is not the size its .ifo gives.") end
      else if _slot_size(_import_dict) < 0 then let
        val () = _free_entry(name, types_kept)
      in _refuse("The dictionary's .dict or .dict.dz file is missing.") end
      else if count >= MOST_DICTIONARIES then let
        val () = _free_entry(name, types_kept)
      in _refuse("Quire keeps up to 64 dictionaries: remove one first.") end
      else if name_len <= 0 then let
        val () = $A.free<byte>(name)
        val name = $A.alloc<byte>(256)
        val name_len = _put_string(name, 0, "Dictionary", 10, 0)
      in _import_store(name, name_len, types_kept, types_len) end
      else _import_store(name, name_len, types_kept, types_len)
    end

(* Files file_index to file_count - 1 picked in the dictionaries' file
   input, kept by what they are, one after another; then checked *)
fun _open_files {file_index,file_count:nat | file_index <= file_count} .<file_count - file_index>.
  (file_index: int file_index, file_count: int file_count): void =
  if file_index >= file_count then let
    (* the input's files are all read: its choice is cleared *)
    val () = app_dictionary_input()
  in _import_check() end
  else let
    val @(input_id, input_len) = _id_bytes("dictionary-file")
    val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
    val opened = $BF.file_open_at(id_bytes, input_len, file_index)
    val () = release_bytes(id_frozen, id_bytes)
  in
    $P.finish<$BF.opened>(opened, llam(opened) =>
      if _keep_file(opened) then _open_files(file_index + 1, file_count)
      else let
        (* the input's choice is cleared, as when every file is read *)
        val () = app_dictionary_input()
      in _refuse("One of the dictionary's files could not be read.") end)
  end

(* Imports the dictionary whose files are picked in the dictionaries'
   file input, for the language chosen beside it *)
#pub fn dict_import_picked (): void

implement dict_import_picked () = let
  val () = _import_clear()
  val () = !_import_compressed := false
  val () = !_import_language := _chosen_language()
  val () = ui_text("dictionaries-status", "Importing...")
  val @(input_id, input_len) = _id_bytes("dictionary-file")
  val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
  val file_count = $BF.file_count(id_bytes, input_len)
  val () = release_bytes(id_frozen, id_bytes)
in
  if file_count <= 0 then ()
  else _open_files(0, file_count)
end

(* ============================================================
   The backup: the dictionaries' names and languages (their files are
   the reader's, as books are)
   ============================================================ *)

fun _json_entries {l:agz}{owner:addr}{n:nat}{count:nat}{at:nat | at + 1600 * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, owner), at: int at, list: !dicts(count), first: bool): [stop:nat | stop <= at + 1600 * count] int stop =
  case+ list of
  | DictsNil() => at
  | @DictsCons(_, language, _, name, name_len, _, _, rest) => let
      val next = (if first then jw_lit(out, at, "{\"name\":") else jw_lit(out, at, ",{\"name\":")): [next:nat | at + 8 <= next; next <= at + 9] int next
      val next = jw_str(out, next, name, name_len)
      val next = jw_lit(out, next, ",\"language\":\"")
      val next = next + _code_put(out, next, language)
      val next = jw_lit(out, next, "\"}")
      val stop = _json_entries(out, next, rest, false)
      prval () = fold@(list)
    in stop end

(* ,"dictionaries":[{"name": ..., "language": ...}, ...] *)
#pub fn dict_backup_json (): jchunk

implement dict_backup_json () = let
  val+ ~DictCell(list, next_id) = _dicts_take()
  val count = _dicts_count(list)
in
  if count > 1000 then let val () = _dicts_put(DictCell(list, next_id)) in JNone() end
  else case+ piece_new(32 + 1600 * count) of
  | ~NoPiece() => let val () = _dicts_put(DictCell(list, next_id)) in JNone() end
  | ~Piece(owner, out) => let
      val next = jw_lit(out, 0, ",\"dictionaries\":[")
      val next = _json_entries(out, next, list, true)
      val next = jw_lit(out, next, "]")
      val () = _dicts_put(DictCell(list, next_id))
    in JChunk(owner, out, next) end
end

end (* #target wasm *)
