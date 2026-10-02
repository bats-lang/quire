(* clock -- when a record was last changed, as sync compares it: a
   hybrid logical clock (Kulkarni et al., "Logical Physical Clocks",
   2014). The browser gives the time only to the minute
   (epoch_minutes), so a stamp is the minutes since STAMP_EPOCH times
   STAMP_TICKS, plus a count: each stamp made here is after the clock's
   minute and after every stamp this device has made or seen (from
   another device, through sync). A change made after another device's
   change was synced here is later than it, whatever the two clocks
   say; changes made apart, each without the other, are ordered by the
   minute they were made in. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P

staload "book.sats"
staload "mem.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* 2025-01-01T00:00Z in minutes since the epoch: no stamp is before it *)
#define STAMP_EPOCH 28928160
(* The stamps a minute holds: a minute of 64 changes on one device runs
   the clock ahead of the time, by a minute, until the time catches up.
   An int holds (2^31 / 64) minutes of them, to the year 2088 *)
#define STAMP_TICKS 64

(* The latest stamp made or seen here, kept across runs *)
val _latest = ref<Int>(0)

fn _key (): [l:agz] $A.arr(byte, l, 5) = let
  val key = $A.alloc<byte>(5)
  val () = $A.write_text(key, 0, $A.text_lit("clock"), 5)
in key end

fn _keep (): void = let
  val record = $A.alloc<byte>(4)
  val () = $A.write_i32(record, 0, !_latest)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_key())
  (* ignored: each change keeps its own stamp with it, and the next
     stamp is at least the minute it is made in, so a latest stamp not
     stored costs at most an order among changes of the same minute *)
  val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 5, record_bytes, 4), llam(_) => ())
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* The stamp of the start of minute minutes (0 before STAMP_EPOCH) *)
#pub fn stamp_of_minutes (minutes: Int): Int
implement stamp_of_minutes (minutes) =
  if minutes <= STAMP_EPOCH then 0
  else if minutes - STAMP_EPOCH > 33554431 then 33554431 * STAMP_TICKS
  else (minutes - STAMP_EPOCH) * STAMP_TICKS

(* The minute a stamp was made in, and its count in that minute *)
#pub fn stamp_minutes (stamp: Int): Int
implement stamp_minutes (stamp) = let
  val ticks = (if stamp > 0 then stamp / STAMP_TICKS else 0): Int
in ticks + STAMP_EPOCH end

#pub fn stamp_count (stamp: Int): [count:nat | count < 64] int count
implement stamp_count (stamp) =
  if stamp <= 0 then 0
  else $AR.band_g1($AR.low_byte(stamp - (stamp / STAMP_TICKS) * STAMP_TICKS), 63)

(* The stamp of minute minutes' count-th change *)
#pub fn stamp_make {count:nat | count < 64} (minutes: Int, count: int count): Int
implement stamp_make (minutes, count) =
  if minutes < STAMP_EPOCH then 0 else stamp_of_minutes(minutes) + count

(* A stamp for a change made now: after the minute's start and after
   every stamp made or seen here *)
#pub fn stamp_now (): Int
implement stamp_now () = let
  val now = stamp_of_minutes($TM.epoch_minutes())
  val latest = !_latest
  val stamp = (if now > latest then now else latest + 1): Int
  val () = !_latest := stamp
  val () = _keep()
in stamp end

(* A stamp seen in another device's change: every stamp made after this
   is later than it *)
#pub fn stamp_seen (stamp: Int): void
implement stamp_seen (stamp) =
  if stamp > !_latest then let
    val () = !_latest := stamp
  in _keep() end
  else ()

(* Reads the latest stamp of an earlier run *)
#pub fn stamp_load (): void
implement stamp_load () = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_key())
  val pending = $IDB.idb_get(key_bytes, 5)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.finish<$IDB.lookup>(pending, llam(found) => let
    (* one that could not be read is taken as none: a stamp only orders
       changes, and the latest is kept as they are made *)
    val () = (case+ lookup_bytes(found) of
      | ~NothingStored() => ()
      | ~StoredUnreadable() => ()
      | ~StoredBytes(record, n) =>
        if n < 4 then $A.free<byte>(record)
        else let
          val lowest = $AR.low_byte(byte2int0($A.get<byte>(record, 0)))
          val second = $AR.low_byte(byte2int0($A.get<byte>(record, 1)))
          val third = $AR.low_byte(byte2int0($A.get<byte>(record, 2)))
          val highest = $AR.low_byte(byte2int0($A.get<byte>(record, 3)))
          val () = $A.free<byte>(record)
          val stored = lowest + second * 256 + third * 65536 + ((if highest < 128 then highest else 0): Int) * 16777216
        in if stored > !_latest then !_latest := stored else () end)
  in () end)
end

end (* #target wasm *)
