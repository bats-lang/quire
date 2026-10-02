(* storage -- the reader's records that could not be read this session,
   which are then not saved over (#174). A record each save rewrites
   whole (the library, the settings, ...) that could not be read is kept
   as it is: its save is skipped until Quire is opened again, which
   reads everything anew, and the banner says so (Chrome does the same
   with preferences it cannot read). A failed read is never taken for an
   empty record: what would be saved over it is all that is lost *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "notice.sats"

(* The records each save rewrites whole *)
#pub datatype record_kind =
  | LibraryRecord        (* the library: its books and places *)
  | SettingsRecord       (* the settings *)
  | StatisticsRecord     (* the reading log, here and elsewhere *)
  | ReadingSpeedRecord   (* the reading speed learned *)
  | CataloguesRecord     (* the catalogues added *)
  | DictionariesRecord   (* the dictionaries imported *)
  | SyncStateRecord      (* sync's: this device's number, the last sync *)

val _library_unread = ref<bool>(false)
val _settings_unread = ref<bool>(false)
val _statistics_unread = ref<bool>(false)
val _reading_speed_unread = ref<bool>(false)
val _catalogues_unread = ref<bool>(false)
val _dictionaries_unread = ref<bool>(false)
val _sync_state_unread = ref<bool>(false)

fn _unread_cell (kind: record_kind): ref(bool) =
  case+ kind of
  | LibraryRecord() => _library_unread
  | SettingsRecord() => _settings_unread
  | StatisticsRecord() => _statistics_unread
  | ReadingSpeedRecord() => _reading_speed_unread
  | CataloguesRecord() => _catalogues_unread
  | DictionariesRecord() => _dictionaries_unread
  | SyncStateRecord() => _sync_state_unread

(* What the banner says when the record could not be read; the reading
   log, the speed and sync's state are not worth interrupting reading
   for (when storage is failing, another record says so) *)
fn _tell (kind: record_kind): void =
  case+ kind of
  | LibraryRecord() => notice_error("Quire could not read your library. Nothing will be saved until you reopen Quire, so your books and places are kept.")
  | SettingsRecord() => notice_error("Quire could not read your settings. It is using the defaults, and changes will not be saved until you reopen Quire.")
  | CataloguesRecord() => notice_error("Quire could not read your catalogues. Changes to them will not be saved until you reopen Quire.")
  | DictionariesRecord() => notice_error("Quire could not read your dictionaries. Changes to them will not be saved until you reopen Quire.")
  | StatisticsRecord() => ()
  | ReadingSpeedRecord() => ()
  | SyncStateRecord() => ()

(* The record kind could not be read: it is not saved over this
   session, and the banner says so (once) *)
#pub fn storage_unreadable (kind: record_kind): void
implement storage_unreadable (kind) = let
  val cell = _unread_cell(kind)
in
  if !cell then ()
  else let
    val () = !cell := true
  in _tell(kind) end
end

(* Whether the record kind may be saved: it was read (or found absent) *)
#pub fn storage_savable (kind: record_kind): bool
implement storage_savable (kind) = ~(!(_unread_cell(kind)))

(* The books whose annotations could not be read, by id *)
datavtype unread_books(int) =
  | UnreadNone(0) of ()
  | {count:nat} UnreadBook(count + 1) of (int, int, unread_books(count))

val _unread_books = ref<[count:nat] unread_books(count)>(UnreadNone())

fn _unread_take (): [count:nat] unread_books(count) = let
  var taken: [count:nat] unread_books(count) = UnreadNone()
  val () = ref_exch_elt<[count:nat] unread_books(count)>(_unread_books, taken)
in taken end

fun _unread_free {count:nat} .<count>. (books: unread_books(count)): void =
  case+ books of
  | ~UnreadNone() => ()
  | ~UnreadBook(_, _, rest) => _unread_free(rest)

fn _unread_put {count:nat} (books: unread_books(count)): void = let
  var previous: [count:nat] unread_books(count) = books
  val () = ref_exch_elt<[count:nat] unread_books(count)>(_unread_books, previous)
in _unread_free(previous) end

fun _unread_has {count:nat} .<count>. (books: !unread_books(count), id_high: int, id_low: int): bool =
  case+ books of
  | UnreadNone() => false
  | UnreadBook(high, low, rest) =>
    if high = id_high then (if low = id_low then true else _unread_has(rest, id_high, id_low))
    else _unread_has(rest, id_high, id_low)

(* Whether the annotations of book id_high, id_low may be saved (and
   made): they were read, or found absent *)
#pub fn storage_annotations_savable (id_high: int, id_low: int): bool
implement storage_annotations_savable (id_high, id_low) = let
  val books = _unread_take()
  val unread = _unread_has(books, id_high, id_low)
  val () = _unread_put(books)
in ~unread end

(* The annotations of book id_high, id_low could not be read: none is
   saved for it, or made, this session, and the banner says so *)
#pub fn storage_annotations_unreadable (id_high: int, id_low: int): void
implement storage_annotations_unreadable (id_high, id_low) = let
  val books = _unread_take()
in
  if _unread_has(books, id_high, id_low) then _unread_put(books)
  else let
    val () = _unread_put(UnreadBook(id_high, id_low, books))
  in notice_error("This book's highlights and notes could not be read. New ones cannot be made until you reopen Quire, so the old ones are kept.") end
end

end (* #target wasm *)
