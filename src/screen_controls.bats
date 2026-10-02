(* screen_controls -- the typography panel's Screen row: full screen,
   the rotation locked, and the brightness *)

(* Each control is shown only where the platform has it (bridge's
   *_available): full screen in a browser with the Fullscreen API and in
   the app (its bars hidden); the rotation lock in the app, and in a
   browser that allows it (installed, or in full screen); the brightness
   in the app only, as a web page cannot set it. The row goes when none
   is. Full screen and the lock are toggles (aria-pressed); the
   brightness and the lock are kept with the settings (settings.bats),
   and put back as the app starts. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "ui.sats"
staload "settings.sats"
staload "library.sats"
staload SCR = "wasm.bats-packages.dev/bridge/src/screen.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload "mem.sats"

fn _pressed {id_len:pos | id_len < 256} (id: string id_len, on: bool): void =
  if on then ui_attr(id, APressed, "true") else ui_attr(id, APressed, "false")

(* The Screen row's controls, each where it can be had now *)
#pub fn screen_controls_show (): void

implement screen_controls_show () = let
  val full = $SCR.fullscreen_available()
  val lock = $SCR.orientation_available()
  val brightness = $SCR.brightness_available()
  val () = ui_show("screen-fullscreen", full)
  val () = ui_show("screen-lock", lock)
  val () = ui_show("screen-brightness", brightness)
  val () = ui_show("screen-row", (if full then true else if lock then true else brightness))
  val () = _pressed("screen-fullscreen", $SCR.fullscreen_active())
in
  (* a lock the browser can no longer keep (full screen left) is let go *)
  if lock then ()
  else case+ set_rotation_get() of
  | RotationFree() => ()
  | RotationLocked() => let
      val () = set_rotation_set(RotationFree())
    in _pressed("screen-lock", false) end
end

(* ============================================================
   Full screen
   ============================================================ *)

(* Full screen clicked: into it, or out of it *)
#pub fn screen_fullscreen_toggle (): void

implement screen_fullscreen_toggle () =
  if $SCR.fullscreen_active() then $SCR.fullscreen_exit() else $SCR.fullscreen_enter()

(* Full screen entered or left (Escape leaves it too): the toggle
   follows, and the lock, which a browser allows only in full screen *)
#pub fn screen_fullscreen_changed (change: $SCR.fullscreen_change): void

implement screen_fullscreen_changed (change) = let
  val () = (case+ change of
    | $SCR.FullscreenEntered() => _pressed("screen-fullscreen", true)
    | $SCR.FullscreenLeft() => _pressed("screen-fullscreen", false))
in screen_controls_show() end

(* ============================================================
   The rotation lock
   ============================================================ *)

(* The rotation locked to the one the screen has now; the toggle and the
   setting follow once it is (or is refused) *)
fn _lock (): void =
  $P.finish<$SCR.lock_outcome>($SCR.orientation_lock_current(), lam(outcome) =>
    case+ outcome of
    | $SCR.Locked() => let
        val () = set_rotation_set(RotationLocked())
        val () = set_save(lib_state_get())
      in _pressed("screen-lock", true) end
    | $SCR.LockRefused() => let
        val () = set_rotation_set(RotationFree())
        val () = set_save(lib_state_get())
      in _pressed("screen-lock", false) end)

(* Lock rotation clicked: locked, or let go, and kept *)
#pub fn screen_lock_toggle (): void

implement screen_lock_toggle () =
  case+ set_rotation_get() of
  | RotationLocked() => let
      val () = $SCR.orientation_unlock()
      val () = set_rotation_set(RotationFree())
      val () = set_save(lib_state_get())
    in _pressed("screen-lock", false) end
  | RotationFree() => _lock()

(* ============================================================
   The brightness
   ============================================================ *)

(* What bridge's brightness_set takes for a choice *)
fn _setting_of (choice: brightness_choice): $SCR.brightness_setting =
  case+ choice of
  | BrightnessSystem() => $SCR.FollowSystem()
  | BrightnessTenth() => $SCR.Level(10)
  | BrightnessQuarter() => $SCR.Level(25)
  | BrightnessHalf() => $SCR.Level(50)
  | BrightnessThreeQuarters() => $SCR.Level(75)
  | BrightnessFull() => $SCR.Level(100)

(* A choice's option: its value and what it shows *)
fn _option_of (choice: brightness_choice): @([value_len:pos | value_len < 8] string value_len, [label_len:pos | label_len < 8] string label_len) =
  case+ choice of
  | BrightnessSystem() => @("system", "System")
  | BrightnessTenth() => @("10", "10%")
  | BrightnessQuarter() => @("25", "25%")
  | BrightnessHalf() => @("50", "50%")
  | BrightnessThreeQuarters() => @("75", "75%")
  | BrightnessFull() => @("100", "100%")

fn _same (one: brightness_choice, other: brightness_choice): bool =
  case+ (one, other) of
  | (BrightnessSystem(), BrightnessSystem()) => true
  | (BrightnessTenth(), BrightnessTenth()) => true
  | (BrightnessQuarter(), BrightnessQuarter()) => true
  | (BrightnessHalf(), BrightnessHalf()) => true
  | (BrightnessThreeQuarters(), BrightnessThreeQuarters()) => true
  | (BrightnessFull(), BrightnessFull()) => true
  | (_, _) => false

(* A string's bytes in a new array *)
fn _bytes_of {text_len:pos | text_len < 8} (text: string text_len): [l:agz] @($A.arr(byte, l, text_len), int text_len) = let
  val text_len = g1u2i(string1_length(text))
  val bytes = $A.alloc<byte>(text_len)
  fun put {l:agz}{i:nat | i <= text_len} .<text_len - i>. (bytes: !$A.arr(byte, l, text_len), i: int i): void =
    if i >= text_len then ()
    else let
      val () = $A.set<byte>(bytes, i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
    in put(bytes, i + 1) end
  val () = put(bytes, 0)
in @(bytes, text_len) end

(* The option for choice, numbered number, the last of the select *)
fn _option {number:nat} (choice: brightness_choice, number: int number, chosen: brightness_choice): void = let
  val @(value, label) = _option_of(choice)
  val @(id, id_len) = nid_make("brightness-level", number)
  val @(value_bytes, value_len) = _bytes_of(value)
  val @(label_bytes, label_len) = _bytes_of(label)
in ui_option("screen-brightness", id, id_len, value_bytes, value_len, label_bytes, label_len, _same(choice, chosen)) end

(* The brightness select's levels, the one kept chosen *)
fn _brightness_options (): void = let
  val chosen = set_brightness_get()
  val () = ui_clear("screen-brightness")
  val () = _option(BrightnessSystem(), 0, chosen)
  val () = _option(BrightnessTenth(), 1, chosen)
  val () = _option(BrightnessQuarter(), 2, chosen)
  val () = _option(BrightnessHalf(), 3, chosen)
  val () = _option(BrightnessThreeQuarters(), 4, chosen)
in _option(BrightnessFull(), 5, chosen) end

(* Whether bytes[0, n) is text *)
fun _bytes_are {l:agz}{n:nat}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (bytes: !$A.arr(byte, l, n), n: int n, text: string text_len, text_len: int text_len, i: int i): bool =
  if n <> text_len then false
  else if i >= text_len then true
  else if i >= n then false
  else if byte2int0($A.get<byte>(bytes, i)) <> char2int0(string_get_at(text, i)) then false
  else _bytes_are(bytes, n, text, text_len, i + 1)

fn _is {l:agz}{n:nat}{text_len:pos} (bytes: !$A.arr(byte, l, n), n: int n, text: string text_len): bool =
  _bytes_are(bytes, n, text, g1u2i(string1_length(text)), 0)

(* The choice whose option's value is value[0, n): checked here, once;
   the system's own for any other *)
fn _choice_of {l:agz}{n:nat} (value: !$A.arr(byte, l, n), n: int n): brightness_choice =
  if _is(value, n, "10") then BrightnessTenth()
  else if _is(value, n, "25") then BrightnessQuarter()
  else if _is(value, n, "50") then BrightnessHalf()
  else if _is(value, n, "75") then BrightnessThreeQuarters()
  else if _is(value, n, "100") then BrightnessFull()
  else BrightnessSystem()

(* A brightness chosen in the select: set, and kept *)
#pub fn screen_brightness_chosen (): void

implement screen_brightness_chosen () = let
  val id = $A.alloc<byte>(17)
  val () = $A.write_text(id, 0, $A.text_lit("screen-brightness"), 17)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val value = $DR.read_input_value(id_bytes, 17)
  val () = release_bytes(id_frozen, id_bytes)
in
  case+ value of
  | ~$R.none() => ()
  | ~$R.some(blob) => let
      val n = $BD.blob_len(blob)
    in
      if n <= 0 then $BD.blob_free(blob)
      else if n > 16 then $BD.blob_free(blob)
      else let
        val bytes = $A.alloc<byte>(n)
        val () = $BD.blob_read(blob, 0, bytes, n)
        val () = $BD.blob_free(blob)
        val choice = _choice_of(bytes, n)
        val () = $A.free<byte>(bytes)
        val () = set_brightness_set(choice)
        val () = set_save(lib_state_get())
      in
        if $SCR.brightness_available() then $SCR.brightness_set(_setting_of(choice)) else ()
      end
    end
end

(* ============================================================
   Startup
   ============================================================ *)

(* Once the settings are read: the row as the platform has it, the
   brightness select's levels, and what was kept put back: a brightness
   other than the system's, and (in the app, where nothing else asks
   for it) the rotation lock *)
#pub fn screen_controls_start (): void

implement screen_controls_start () = let
  val () = _brightness_options()
  val () = screen_controls_show()
  val () = (if $SCR.brightness_available() then (case+ set_brightness_get() of
      | BrightnessSystem() => ()
      | _ => $SCR.brightness_set(_setting_of(set_brightness_get())))
    else ())
in
  case+ set_rotation_get() of
  | RotationFree() => ()
  | RotationLocked() =>
    if $BAPP.is_native_platform() then (if $SCR.orientation_available() then _lock() else ())
    else set_rotation_set(RotationFree())
end

end (* #target wasm *)
