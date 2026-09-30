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
  | {k:nat} DaysCons(k + 1) of (Int, Int, days(k))

val _days = ref<[k:nat] days(k)>(DaysNil())
(* The daily goal in minutes, 0 for none *)
val _goal = ref<int>(0)

(* ============================================================
   The local day
   ============================================================ *)

(* The digits at b[p, n) as a number, or -1 *)
fun _digits {l:agz}{n:nat}{p:nat | p <= n} .<n - p>. (b: !$A.arr(byte, l, n), n: int n, p: int p, acc: int): int =
  if p >= n then acc
  else let
    val c = byte2int0($A.get<byte>(b, p))
  in if c < 48 || c > 57 then ~1 else _digits(b, n, p + 1, acc * 10 + c - 48) end

(* The local time's offset from UTC in minutes east: the page's script
   (pwa) keeps it in the id of an element, pwa-utc-offset- and the
   minutes plus 1440; 0 (UTC) when it does not *)
fn _offset (): int = let
  val a = $A.alloc<byte>(22)
  val () = $A.write_text(a, 0, $A.text_lit("[id^=pwa-utc-offset-]"), 21)
  val @(f, b) = $A.freeze<byte>(a)
  val @(b1, b2) = $A.borrow_split<byte>(f, b, 21)
  val r = $DR.query_selector(b1, 21)
  val b = $A.borrow_join<byte>(f, b1, b2)
  val () = release_bytes(f, b)
in
  case+ r of
  | ~$R.none() => 0
  | ~$R.some(v) => let
      val n = $DC.blob_len(v)
    in
      if n <= 15 then let val () = $DC.blob_free(v) in 0 end
      else if n > 24 then let val () = $DC.blob_free(v) in 0 end
      else let
        val a = $A.alloc<byte>(n)
        val () = $DC.blob_read(v, 0, a, n)
        val () = $DC.blob_free(v)
        val d = _digits(a, n, 15, 0)
        val () = $A.free<byte>(a)
      in if d < 0 then 0 else if d > 2880 then 0 else d - 1440 end
    end
end

#pub fn stats_offset (): int
implement stats_offset () = _offset()

(* The local day it is *)
#pub fn stats_today (): Int
implement stats_today () = let
  val m = $TM.epoch_minutes() + g1ofg0(_offset())
in if m > 0 then m / 1440 else 0 end

(* ============================================================
   Storage: key "rlog"
   ============================================================ *)

(* "QR1\n", the goal (i32), then each day: the day and its minutes
   (i32 each), the latest first *)
fun _count {k:nat} .<k>. (xs: days(k)): int k =
  case+ xs of
  | DaysNil() => 0
  | DaysCons(_, _, rest) => 1 + _count(rest)

fun _ser {l:agz}{n:int}{k:nat}{p:nat | p + 8 * k <= n} .<k>.
  (out: !$A.arr(byte, l, n), p: int p, xs: days(k)): void =
  case+ xs of
  | DaysNil() => ()
  | DaysCons(d, m, rest) => let
      val () = $A.write_i32(out, p, d)
      val () = $A.write_i32(out, p + 4, m)
    in _ser(out, p + 8, rest) end

fn _key (): [l:agz] $A.arr(byte, l, 4) = let
  val k = $A.alloc<byte>(4)
  val () = $A.write_text(k, 0, $A.text_lit("rlog"), 4)
in k end

(* xs with at most j days *)
fun _first {k:nat}{j:nat} .<k>. (xs: days(k), j: int j): [r:nat | r <= j] days(r) =
  if j <= 0 then DaysNil()
  else case+ xs of
  | DaysNil() => DaysNil()
  | DaysCons(d, m, rest) => DaysCons(d, m, _first(rest, j - 1))

fn _save (): void = let
  val xs = _first(!_days, DAYS)
  val k = _count(xs)
  val out = $A.alloc<byte>(8 + 8 * k)
  val () = $A.write_text(out, 0, $A.text_lit("QR1"), 3)
  val () = $A.write_byte(out, 3, 10)
  val () = $A.write_i32(out, 4, !_goal)
  val () = _ser(out, 8, xs)
  val @(f, b) = $A.freeze<byte>(out)
  val @(kf, kb) = $A.freeze<byte>(_key())
  val () = $P.discard<Int>($IDB.idb_put(kb, 4, b, 8 + 8 * k))
  val () = release_bytes(kf, kb)
in release_bytes(f, b) end

(* The little-endian int at b[p, p + 4) *)
fn _i32 {l:agz}{n:nat}{p:nat | p + 4 <= n} (b: !$A.arr(byte, l, n), p: int p): Int = let
  val b0 = $AR.low_byte(byte2int0($A.get<byte>(b, p)))
  val b1 = $AR.low_byte(byte2int0($A.get<byte>(b, p + 1)))
  val b2 = $AR.low_byte(byte2int0($A.get<byte>(b, p + 2)))
  val b3 = $AR.low_byte(byte2int0($A.get<byte>(b, p + 3)))
  val hi = (if b3 < 128 then b3 else b3 - 256): Int
in b0 + b1 * 256 + b2 * 65536 + hi * 16777216 end

(* The days stored at b[p, n), in order, at most j more *)
fun _parse {l:agz}{n:nat}{p:nat | p <= n}{j:nat} .<j>. (b: !$A.arr(byte, l, n), n: int n, p: int p, j: int j): [k:nat] days(k) =
  if j <= 0 then DaysNil()
  else if p + 8 > n then DaysNil()
  else DaysCons(_i32(b, p), _i32(b, p + 4), _parse(b, n, p + 8, j - 1))

(* Reads the log stored in an earlier run *)
#pub fn stats_load (): void
implement stats_load () = let
  val @(kf, kb) = $A.freeze<byte>(_key())
  val p = $IDB.idb_get(kb, 4)
  val () = release_bytes(kf, kb)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) => let
    val () = (case+ take_blob(h) of
      | ~NoBlobBytes() => ()
      | ~BlobBytes(b, n) =>
        if n < 8 then $A.free<byte>(b)
        else if byte2int0($A.get<byte>(b, 1)) <> 82 then $A.free<byte>(b)
        else let
          val g = _i32(b, 4)
          val () = !_goal := (if g >= 0 then (if g <= 600 then g else 0) else 0)
          val () = !_days := _parse(b, n, 8, DAYS)
        in $A.free<byte>(b) end)
  in $P.ret<int>(0) end))
end

(* ============================================================
   The log
   ============================================================ *)

(* m minutes read now: added to today's *)
#pub fn stats_add (m: Int): void
implement stats_add (m) =
  if m <= 0 then ()
  else let
    val today = stats_today()
    val () = (case+ !_days of
      | DaysCons(d, dm, rest) =>
        if d = today then !_days := DaysCons(d, dm + m, rest)
        else !_days := _first(DaysCons(today, m, DaysCons(d, dm, rest)), DAYS)
      | DaysNil() => !_days := DaysCons(today, m, DaysNil()))
  in _save() end

(* The minutes read on days from lo to hi *)
fun _between {k:nat} .<k>. (xs: days(k), lo: Int, hi: Int, acc: Int): Int =
  case+ xs of
  | DaysNil() => acc
  | DaysCons(d, m, rest) =>
    _between(rest, lo, hi, (if d >= lo then (if d <= hi then acc + m else acc) else acc))

#pub fn stats_minutes_between (lo: Int, hi: Int): Int
implement stats_minutes_between (lo, hi) = _between(!_days, lo, hi, 0)

(* The days read in a row, back from day want (the latest first) *)
fun _run {k:nat} .<k>. (xs: days(k), want: Int, n: int): int =
  case+ xs of
  | DaysNil() => n
  | DaysCons(d, m, rest) =>
    if d > want then _run(rest, want, n)
    else if d < want then n
    else if m <= 0 then n
    else _run(rest, want - 1, n + 1)

(* The reading streak: the days read in a row up to today, or up to
   yesterday while today has not been read yet *)
#pub fn stats_streak (): int
implement stats_streak () = let
  val today = stats_today()
  val n = _run(!_days, today, 0)
in if n > 0 then n else _run(!_days, today - 1, 0) end

#pub fn stats_goal_get (): int
implement stats_goal_get () = !_goal

#pub fn stats_goal_set (g: int): void
implement stats_goal_set (g) = let
  val () = !_goal := (if g >= 0 then (if g <= 600 then g else 0) else 0)
in _save() end

(* ============================================================
   The panel
   ============================================================ *)

fn _put {l:agz}{n:pos}{p:nat}{sn:nat | p + sn <= n}
  (b: !$A.arr(byte, l, n), p: int p, s: string sn): int(p + sn) = let
  val k = g1u2i(string1_length(s))
  val () = $A.write_text(b, p, $A.text_lit(s), k)
in p + k end

(* d minutes, as "3 h 20 min" or "20 min", at b[p) *)
fn _put_dur {l:agz}{n:pos}{p:nat | p + 30 <= n}
  (b: !$A.arr(byte, l, n), p: int p, n: int n, d: Int): [r:nat | r <= p + 30] int r =
  if d < 60 then let
    val shown = (if d > 0 then d else 0): Int
    val off = $S.int_to_str(b, p, n, shown)
  in _put(b, off, " min") end
  else let
    val off = $S.int_to_str(b, p, n, d / 60)
    val off = _put(b, off, " h ")
    val off = $S.int_to_str(b, off, n, d - (d / 60) * 60)
  in _put(b, off, " min") end

(* d minutes as the panel says them ("3 h 20 min"), at b[0) *)
#pub fn stats_duration_text {l:agz} (b: !$A.arr(byte, l, 32), d: Int): [r:nat | r <= 30] int r
implement stats_duration_text (b, d) = _put_dur(b, 0, 32, d)

(* " of " the goal g at b[p), when there is a goal *)
fn _put_goal {l:agz}{p:nat | p <= 30}
  (b: !$A.arr(byte, l, 64), p: int p, g: Int): [r:nat | r <= 64] int r =
  if g > 0 then let
    val off = _put(b, p, " of ")
  in _put_dur(b, off, 64, g) end
  else p

(* " day" or " days" after the count n at b[p) *)
fn _put_days {l:agz}{p:nat | p <= 11}
  (b: !$A.arr(byte, l, 64), p: int p, n: Int): [r:nat | r <= 16] int r =
  if n = 1 then _put(b, p, " day") else _put(b, p, " days")

(* " book" or " books" after the count n at b[p) *)
fn _put_books {l:agz}{p:nat | p <= 11}
  (b: !$A.arr(byte, l, 64), p: int p, n: Int): [r:nat | r <= 17] int r =
  if n = 1 then _put(b, p, " book") else _put(b, p, " books")

(* The reading statistics panel's numbers, as they are now *)
#pub fn stats_show (): void
implement stats_show () = let
  val today = stats_today()
  val t = stats_minutes_between(today, today)
  val b = $A.alloc<byte>(64)
  val off = _put_dur(b, 0, 64, t)
  val g = g1ofg0(!_goal)
  val off = _put_goal(b, off, g)
  val () = ui_text_buf("stats-today", b, off)
  val b = $A.alloc<byte>(64)
  val off = _put_dur(b, 0, 64, stats_minutes_between(today - 6, today))
  val () = ui_text_buf("stats-week", b, off)
  val s = g1ofg0(stats_streak())
  val b = $A.alloc<byte>(64)
  val off = $S.int_to_str(b, 0, 64, s)
  val off = _put_days(b, off, s)
  val () = ui_text_buf("stats-streak", b, off)
  val f = g1ofg0(lib_finished_in(year_of_day(today), g1ofg0(_offset())))
  val b = $A.alloc<byte>(64)
  val off = $S.int_to_str(b, 0, 64, f)
  val off = _put_books(b, off, f)
  val () = ui_text_buf("stats-finished", b, off)
  val () = (if g = 0 then ui_attr("stats-goal-off", APressed, "true") else ui_attr("stats-goal-off", APressed, "false"))
  val () = (if g = 10 then ui_attr("stats-goal-10", APressed, "true") else ui_attr("stats-goal-10", APressed, "false"))
  val () = (if g = 20 then ui_attr("stats-goal-20", APressed, "true") else ui_attr("stats-goal-20", APressed, "false"))
  val () = (if g = 30 then ui_attr("stats-goal-30", APressed, "true") else ui_attr("stats-goal-30", APressed, "false"))
in if g = 60 then ui_attr("stats-goal-60", APressed, "true") else ui_attr("stats-goal-60", APressed, "false") end

(* ============================================================
   Backup: the log's days, for backup.bats
   ============================================================ *)

(* The log's days, the latest first, as (day, minutes) pairs, and
   their count *)
#pub fn stats_days (): [k:nat] @(days(k), int k)
implement stats_days () = let val xs = !_days in @(xs, _count(xs)) end

(* A restored backup's day: its minutes put where the log has none for
   it (the log keeps what this device read) *)
fun _merge {k:nat} .<k>. (xs: days(k), d: Int, m: Int): [r:nat] days(r) =
  case+ xs of
  | DaysNil() => DaysCons(d, m, DaysNil())
  | DaysCons(xd, xm, rest) =>
    if xd = d then DaysCons(xd, (if xm >= m then xm else m), rest)
    else if xd < d then DaysCons(d, m, DaysCons(xd, xm, rest))
    else DaysCons(xd, xm, _merge(rest, d, m))

#pub fn stats_restore_day (d: Int, m: Int): void
implement stats_restore_day (d, m) =
  if m <= 0 then ()
  else if d <= 0 then ()
  else let
    val () = !_days := _first(_merge(!_days, d, m), DAYS)
  in _save() end

end (* #target wasm *)
