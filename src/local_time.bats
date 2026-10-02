(* local_time -- the local clock: its offset from UTC, and whether it is
   night *)

(* wasm's time is UTC: the local time is UTC less the host's offset
   (bridge's timezone_offset_minutes, JS's getTimezoneOffset, positive
   west of UTC), read each time it is asked for, so a change of zone or
   of summer time is followed *)

#target wasm begin

#include "share/atspre_staload.hats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* The local time's offset from UTC, in minutes east of it (120 in
   Paris in summer, -300 in New York in winter) *)
#pub fn local_offset_minutes (): [offset:int | ~720 <= offset; offset <= 840] int offset

implement local_offset_minutes () = ~($TM.timezone_offset_minutes())

(* The minutes since the Unix epoch by the clock, from its milliseconds
   (bridge's epoch_millis, high * 2^30 + low): 2^30 is 17895 minutes and
   41824 ms, so neither part leaves 32 bits *)
fn _epoch_minutes (): [minutes:nat] int minutes = let
  val @(high, low) = $TM.epoch_millis()
  val minutes = high * 17895 + (high * 41824 + low) / 60000
in if minutes >= 0 then minutes else 0 end

(* The minute of the local day it is, 0 to 1439 *)
fn _minute_of_day (): [minute:nat | minute < 1440] int minute = let
  val local_minutes = _epoch_minutes() + local_offset_minutes()
in
  if local_minutes < 0 then 0
  else let
    val minute = local_minutes - (local_minutes / 1440) * 1440
  in if minute < 0 then 0 else if minute >= 1440 then 0 else minute end
end

(* When the night starts and ends, in minutes of the local day: 22:00
   and 07:00 (iOS Night Shift's default schedule) *)
#define NIGHT_FROM 1320
#define NIGHT_UNTIL 420

(* Whether it is night by the local clock: from 22:00 until 07:00 *)
#pub fn local_night (): bool

implement local_night () = let
  val minute = _minute_of_day()
in minute >= NIGHT_FROM || minute < NIGHT_UNTIL end

end (* #target wasm *)
