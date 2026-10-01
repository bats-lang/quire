(* stats -- the reading log: the minutes read on each local day, and the
   daily goal; and what the reading statistics panel says of them *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use wasm.bats-packages.dev/decompress as DC

staload "ui.sats"
staload "book.sats"
staload "mem.sats"
staload "library.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* The days kept: a little over a year *)
#define DAYS 400

(* The days read, the latest first: each its local day (days since
   1970-01-01) and the minutes read on it *)
#pub datatype days(int) =
  | DaysNil(0)
  | {count:nat} DaysCons(count + 1) of (Int, Int, days(count))

val _days = ref<[count:nat] days(count)>(DaysNil())
(* The days read on the other devices sync knows of, their minutes
   summed, as sync last saw them: shown with this device's, and kept
   apart from them (sync passes on only this device's) *)
val _days_elsewhere = ref<[count:nat] days(count)>(DaysNil())
(* The daily goal in minutes, 0 for none *)
val _goal = ref<int>(0)

(* ============================================================
   The local day
   ============================================================ *)

(* The digits at bytes[position, n) as a number, or -1 *)
fun _digits_value {l:agz}{n:nat}{position:nat | position <= n} .<n - position>.
  (bytes: !$A.arr(byte, l, n), n: int n, position: int position, value: int): int =
  if position >= n then value
  else let
    val character = byte2int0($A.get<byte>(bytes, position))
  in
    if character < 48 || character > 57 then ~1
    else _digits_value(bytes, n, position + 1, value * 10 + character - 48)
  end

(* The local time's offset from UTC in minutes east: the page's script
   (pwa) keeps it in the id of an element, pwa-utc-offset- and the
   minutes plus 1440; 0 (UTC) when it does not *)
fn _utc_offset (): int = let
  val selector = $A.alloc<byte>(22)
  val () = $A.write_text(selector, 0, $A.text_lit("[id^=pwa-utc-offset-]"), 21)
  val @(selector_frozen, selector_bytes) = $A.freeze<byte>(selector)
  val @(selector_text, selector_rest) = $A.borrow_split<byte>(selector_frozen, selector_bytes, 21)
  val found = $DR.query_selector(selector_text, 21)
  val selector_bytes = $A.borrow_join<byte>(selector_frozen, selector_text, selector_rest)
  val () = release_bytes(selector_frozen, selector_bytes)
in
  case+ found of
  | ~$R.none() => 0
  | ~$R.some(blob) => let
      val id_len = $DC.blob_len(blob)
    in
      if id_len <= 15 then let val () = $DC.blob_free(blob) in 0 end
      else if id_len > 24 then let val () = $DC.blob_free(blob) in 0 end
      else let
        val id_bytes = $A.alloc<byte>(id_len)
        val () = $DC.blob_read(blob, 0, id_bytes, id_len)
        val () = $DC.blob_free(blob)
        val minutes = _digits_value(id_bytes, id_len, 15, 0)
        val () = $A.free<byte>(id_bytes)
      in if minutes < 0 then 0 else if minutes > 2880 then 0 else minutes - 1440 end
    end
end

#pub fn stats_offset (): int
implement stats_offset () = _utc_offset()

(* The local day it is *)
#pub fn stats_today (): Int
implement stats_today () = let
  val minutes = $TM.epoch_minutes() + g1ofg0(_utc_offset())
in if minutes > 0 then minutes / 1440 else 0 end

(* ============================================================
   Storage: key "rlog"
   ============================================================ *)

(* "QR1\n", the goal (i32), then each day: the day and its minutes
   (i32 each), the latest first *)
fun _count {count:nat} .<count>. (entries: days(count)): int count =
  case+ entries of
  | DaysNil() => 0
  | DaysCons(_, _, rest) => 1 + _count(rest)

fun _write_days {l:agz}{n:int}{count:nat}{position:nat | position + 8 * count <= n} .<count>.
  (out: !$A.arr(byte, l, n), position: int position, entries: days(count)): void =
  case+ entries of
  | DaysNil() => ()
  | DaysCons(day, minutes, rest) => let
      val () = $A.write_i32(out, position, day)
      val () = $A.write_i32(out, position + 4, minutes)
    in _write_days(out, position + 8, rest) end

fn _storage_key (): [l:agz] $A.arr(byte, l, 4) = let
  val key = $A.alloc<byte>(4)
  val () = $A.write_text(key, 0, $A.text_lit("rlog"), 4)
in key end

(* entries with at most limit days *)
fun _first {count:nat}{limit:nat} .<count>. (entries: days(count), limit: int limit)
  : [kept:nat | kept <= limit] days(kept) =
  if limit <= 0 then DaysNil()
  else case+ entries of
  | DaysNil() => DaysNil()
  | DaysCons(day, minutes, rest) => DaysCons(day, minutes, _first(rest, limit - 1))

fn _save (): void = let
  val entries = _first(!_days, DAYS)
  val count = _count(entries)
  val record = $A.alloc<byte>(8 + 8 * count)
  val () = $A.write_text(record, 0, $A.text_lit("QR1"), 3)
  val () = $A.write_byte(record, 3, 10)
  val () = $A.write_i32(record, 4, !_goal)
  val () = _write_days(record, 8, entries)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_storage_key())
  val () = $P.discard<Int>($IDB.idb_put(key_bytes, 4, record_bytes, 8 + 8 * count))
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* The little-endian int at bytes[position, position + 4) *)
fn _read_i32 {l:agz}{n:nat}{position:nat | position + 4 <= n}
  (bytes: !$A.arr(byte, l, n), position: int position): Int = let
  val lowest = $AR.low_byte(byte2int0($A.get<byte>(bytes, position)))
  val second = $AR.low_byte(byte2int0($A.get<byte>(bytes, position + 1)))
  val third = $AR.low_byte(byte2int0($A.get<byte>(bytes, position + 2)))
  val highest = $AR.low_byte(byte2int0($A.get<byte>(bytes, position + 3)))
  val signed_highest = (if highest < 128 then highest else highest - 256): Int
in lowest + second * 256 + third * 65536 + signed_highest * 16777216 end

(* The days stored at bytes[position, n), in order, at most limit more *)
fun _read_days {l:agz}{n:nat}{position:nat | position <= n}{limit:nat} .<limit>.
  (bytes: !$A.arr(byte, l, n), n: int n, position: int position, limit: int limit): [count:nat] days(count) =
  if limit <= 0 then DaysNil()
  else if position + 8 > n then DaysNil()
  else DaysCons(_read_i32(bytes, position), _read_i32(bytes, position + 4),
    _read_days(bytes, n, position + 8, limit - 1))

(* "QR1\n", 0, then the days read elsewhere as the log's are, under
   "rlog-elsewhere" *)
fn _elsewhere_key (): [l:agz] $A.arr(byte, l, 14) = let
  val key = $A.alloc<byte>(14)
  val () = $A.write_text(key, 0, $A.text_lit("rlog-elsewhere"), 14)
in key end

fn _elsewhere_save (): void = let
  val entries = _first(!_days_elsewhere, DAYS)
  val count = _count(entries)
  val record = $A.alloc<byte>(8 + 8 * count)
  val () = $A.write_text(record, 0, $A.text_lit("QR1"), 3)
  val () = $A.write_byte(record, 3, 10)
  val () = $A.write_i32(record, 4, 0)
  val () = _write_days(record, 8, entries)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_elsewhere_key())
  val () = $P.discard<Int>($IDB.idb_put(key_bytes, 14, record_bytes, 8 + 8 * count))
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

fn _elsewhere_load (): void = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_elsewhere_key())
  val pending = $IDB.idb_get(key_bytes, 14)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(pending), lam(handle) => let
    val () = (case+ take_blob(handle) of
      | ~NoBlobBytes() => ()
      | ~BlobBytes(record, n) =>
        if n < 8 then $A.free<byte>(record)
        else if byte2int0($A.get<byte>(record, 1)) <> 82 then $A.free<byte>(record)
        else let
          val () = !_days_elsewhere := _read_days(record, n, 8, DAYS)
        in $A.free<byte>(record) end)
  in $P.ret<int>(0) end))
end

(* Reads the log stored in an earlier run *)
#pub fn stats_load (): void
implement stats_load () = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_storage_key())
  val pending = $IDB.idb_get(key_bytes, 4)
  val () = release_bytes(key_frozen, key_bytes)
  val () = $P.discard<int>($P.and_then<Int><int>($P.vow(pending), lam(handle) => let
    val () = (case+ take_blob(handle) of
      | ~NoBlobBytes() => ()
      | ~BlobBytes(record, n) =>
        if n < 8 then $A.free<byte>(record)
        else if byte2int0($A.get<byte>(record, 1)) <> 82 then $A.free<byte>(record)
        else let
          val goal = _read_i32(record, 4)
          val () = !_goal := (if goal >= 0 then (if goal <= 600 then goal else 0) else 0)
          val () = !_days := _read_days(record, n, 8, DAYS)
        in $A.free<byte>(record) end)
  in $P.ret<int>(0) end))
  (* and the days read elsewhere *)
in _elsewhere_load() end

(* ============================================================
   The log
   ============================================================ *)

(* minutes read now: added to today's *)
#pub fn stats_add (minutes: Int): void
implement stats_add (minutes) =
  if minutes <= 0 then ()
  else let
    val today = stats_today()
    val () = (case+ !_days of
      | DaysCons(day, day_minutes, rest) =>
        if day = today then !_days := DaysCons(day, day_minutes + minutes, rest)
        else !_days := _first(DaysCons(today, minutes, DaysCons(day, day_minutes, rest)), DAYS)
      | DaysNil() => !_days := DaysCons(today, minutes, DaysNil()))
  in _save() end

(* The minutes read on days from first_day to last_day *)
fun _between {count:nat} .<count>. (entries: days(count), first_day: Int, last_day: Int, total: Int): Int =
  case+ entries of
  | DaysNil() => total
  | DaysCons(day, minutes, rest) =>
    _between(rest, first_day, last_day,
      (if day >= first_day then (if day <= last_day then total + minutes else total) else total))

(* The minutes read on days from first_day to last_day, here and on
   the other devices sync knows of *)
#pub fn stats_minutes_between (first_day: Int, last_day: Int): Int
implement stats_minutes_between (first_day, last_day) =
  _between(!_days, first_day, last_day, 0) + _between(!_days_elsewhere, first_day, last_day, 0)

(* entries with minutes more read on day *)
fun _add_day {count:nat} .<count>. (entries: days(count), day: Int, minutes: Int): [total:nat] days(total) =
  case+ entries of
  | DaysNil() => DaysCons(day, minutes, DaysNil())
  | DaysCons(entry_day, entry_minutes, rest) =>
    if entry_day = day then DaysCons(entry_day, entry_minutes + minutes, rest)
    else if entry_day < day then DaysCons(day, minutes, DaysCons(entry_day, entry_minutes, rest))
    else DaysCons(entry_day, entry_minutes, _add_day(rest, day, minutes))

(* The days of entries added to into, the latest first *)
fun _sum_days {count,into_count:nat} .<count>. (entries: days(count), into: days(into_count)): [total:nat] days(total) =
  case+ entries of
  | DaysNil() => into
  | DaysCons(day, minutes, rest) => _sum_days(rest, _add_day(into, day, minutes))

(* The days read, here and elsewhere, the latest first *)
fn _all_days (): [count:nat] days(count) = _sum_days(!_days_elsewhere, !_days)

(* The days read in a row, back from the day wanted (the latest first) *)
fun _in_a_row {count:nat} .<count>. (entries: days(count), wanted: Int, streak: int): int =
  case+ entries of
  | DaysNil() => streak
  | DaysCons(day, minutes, rest) =>
    if day > wanted then _in_a_row(rest, wanted, streak)
    else if day < wanted then streak
    else if minutes <= 0 then streak
    else _in_a_row(rest, wanted - 1, streak + 1)

(* The reading streak: the days read in a row up to today, or up to
   yesterday while today has not been read yet *)
#pub fn stats_streak (): int
implement stats_streak () = let
  val today = stats_today()
  val all_days = _all_days()
  val streak = _in_a_row(all_days, today, 0)
in if streak > 0 then streak else _in_a_row(all_days, today - 1, 0) end

#pub fn stats_goal_get (): int
implement stats_goal_get () = !_goal

#pub fn stats_goal_set (goal: int): void
implement stats_goal_set (goal) = let
  val () = !_goal := (if goal >= 0 then (if goal <= 600 then goal else 0) else 0)
in _save() end

(* ============================================================
   The panel
   ============================================================ *)

fn _put_text {l:agz}{n:pos}{position:nat}{text_len:nat | position + text_len <= n}
  (buf: !$A.arr(byte, l, n), position: int position, text: string text_len): int(position + text_len) = let
  val text_len = g1u2i(string1_length(text))
  val () = $A.write_text(buf, position, $A.text_lit(text), text_len)
in position + text_len end

(* minutes, as "3 h 20 min" or "20 min", at buf[position) *)
fn _put_duration {l:agz}{n:pos}{position:nat | position + 30 <= n}
  (buf: !$A.arr(byte, l, n), position: int position, n: int n, minutes: Int)
  : [stop:nat | stop <= position + 30] int stop =
  if minutes < 60 then let
    val shown = (if minutes > 0 then minutes else 0): Int
    val next = $S.int_to_str(buf, position, n, shown)
  in _put_text(buf, next, " min") end
  else let
    val next = $S.int_to_str(buf, position, n, minutes / 60)
    val next = _put_text(buf, next, " h ")
    val next = $S.int_to_str(buf, next, n, minutes - (minutes / 60) * 60)
  in _put_text(buf, next, " min") end

(* minutes as the panel says them ("3 h 20 min"), at buf[0) *)
#pub fn stats_duration_text {l:agz} (buf: !$A.arr(byte, l, 32), minutes: Int): [stop:nat | stop <= 30] int stop
implement stats_duration_text (buf, minutes) = _put_duration(buf, 0, 32, minutes)

(* " of " the goal at buf[position), when there is a goal *)
fn _put_goal {l:agz}{position:nat | position <= 30}
  (buf: !$A.arr(byte, l, 64), position: int position, goal: Int): [stop:nat | stop <= 64] int stop =
  if goal > 0 then let
    val next = _put_text(buf, position, " of ")
  in _put_duration(buf, next, 64, goal) end
  else position

(* " day" or " days" after the count at buf[position) *)
fn _put_days {l:agz}{position:nat | position <= 11}
  (buf: !$A.arr(byte, l, 64), position: int position, count: Int): [stop:nat | stop <= 16] int stop =
  if count = 1 then _put_text(buf, position, " day") else _put_text(buf, position, " days")

(* " book" or " books" after the count at buf[position) *)
fn _put_books {l:agz}{position:nat | position <= 11}
  (buf: !$A.arr(byte, l, 64), position: int position, count: Int): [stop:nat | stop <= 17] int stop =
  if count = 1 then _put_text(buf, position, " book") else _put_text(buf, position, " books")

(* The reading statistics panel's numbers, as they are now *)
#pub fn stats_show (): void
implement stats_show () = let
  val today = stats_today()
  val today_minutes = stats_minutes_between(today, today)
  val buf = $A.alloc<byte>(64)
  val next = _put_duration(buf, 0, 64, today_minutes)
  val goal = g1ofg0(!_goal)
  val next = _put_goal(buf, next, goal)
  val () = ui_text_buf("stats-today", buf, next)
  val buf = $A.alloc<byte>(64)
  val next = _put_duration(buf, 0, 64, stats_minutes_between(today - 6, today))
  val () = ui_text_buf("stats-week", buf, next)
  val streak = g1ofg0(stats_streak())
  val buf = $A.alloc<byte>(64)
  val next = $S.int_to_str(buf, 0, 64, streak)
  val next = _put_days(buf, next, streak)
  val () = ui_text_buf("stats-streak", buf, next)
  val finished = g1ofg0(lib_finished_in(year_of_day(today), g1ofg0(_utc_offset())))
  val buf = $A.alloc<byte>(64)
  val next = $S.int_to_str(buf, 0, 64, finished)
  val next = _put_books(buf, next, finished)
  val () = ui_text_buf("stats-finished", buf, next)
  val () = (if goal = 0 then ui_attr("stats-goal-off", APressed, "true") else ui_attr("stats-goal-off", APressed, "false"))
  val () = (if goal = 10 then ui_attr("stats-goal-10", APressed, "true") else ui_attr("stats-goal-10", APressed, "false"))
  val () = (if goal = 20 then ui_attr("stats-goal-20", APressed, "true") else ui_attr("stats-goal-20", APressed, "false"))
  val () = (if goal = 30 then ui_attr("stats-goal-30", APressed, "true") else ui_attr("stats-goal-30", APressed, "false"))
in if goal = 60 then ui_attr("stats-goal-60", APressed, "true") else ui_attr("stats-goal-60", APressed, "false") end

(* ============================================================
   Backup: the log's days, for backup.bats
   ============================================================ *)

(* The log's days, the latest first, as (day, minutes) pairs, and
   their count *)
#pub fn stats_days (): [count:nat | count <= 400] @(days(count), int count)
implement stats_days () = let val entries = _first(!_days, DAYS) in @(entries, _count(entries)) end

(* A restored backup's day: its minutes put where the log has none for
   it (the log keeps what this device read) *)
fun _merge {count:nat} .<count>. (entries: days(count), day: Int, minutes: Int): [merged:nat] days(merged) =
  case+ entries of
  | DaysNil() => DaysCons(day, minutes, DaysNil())
  | DaysCons(entry_day, entry_minutes, rest) =>
    if entry_day = day then DaysCons(entry_day, (if entry_minutes >= minutes then entry_minutes else minutes), rest)
    else if entry_day < day then DaysCons(day, minutes, DaysCons(entry_day, entry_minutes, rest))
    else DaysCons(entry_day, entry_minutes, _merge(rest, day, minutes))

#pub fn stats_restore_day (day: Int, minutes: Int): void
implement stats_restore_day (day, minutes) =
  if minutes <= 0 then ()
  else if day <= 0 then ()
  else if minutes > 1440 then ()
  else !_days := _first(_merge(!_days, day, minutes), DAYS)

(* Keeps the days a backup put back *)
#pub fn stats_restored (): void
implement stats_restored () = _save()

(* ============================================================
   Sync: the days read on other devices
   ============================================================ *)

(* Forgets the days read elsewhere: those sync reads next are summed
   anew *)
#pub fn stats_elsewhere_clear (): void
implement stats_elsewhere_clear () = !_days_elsewhere := DaysNil()

(* minutes read on day on another device *)
#pub fn stats_elsewhere_add (day: Int, minutes: Int): void
implement stats_elsewhere_add (day, minutes) =
  if minutes <= 0 then ()
  else if day <= 0 then ()
  else if minutes > 1440 then ()
  else !_days_elsewhere := _first(_add_day(!_days_elsewhere, day, minutes), DAYS)

(* Keeps the days read elsewhere *)
#pub fn stats_elsewhere_keep (): void
implement stats_elsewhere_keep () = _elsewhere_save()

end (* #target wasm *)
