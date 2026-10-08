(* screen_controls -- the reading settings' screen rows (its Page tab): full screen,
   the rotation locked, and the brightness *)

(* Each control is shown only where the platform has it (bridge's
   *_available): full screen in a browser with the Fullscreen API and in
   the app (its bars hidden); the rotation lock in the app, and in a
   browser that allows it (installed, or in full screen); the brightness
   in the app only, as a web page cannot set it. Each is a row of its
   own, and the group goes when none is. Full screen and the lock are
   switches (aria-pressed, a drawn knob that moves); the
   brightness, the lock and (in the app) full screen are kept with the
   settings (settings.bats), and put back as the app starts. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use str as S
#use arith as AR
#use promise as P
#use result as R

staload "ui.sats"
staload "settings.sats"
staload "library.sats"
staload SCR = "wasm.bats-packages.dev/bridge/src/screen.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload "mem.sats"
staload "notice.sats"

(* Whether the screen's rotation is locked now (by this module) *)
val _locked = ref<bool>(false)

(* Whether the device refused the rotation lock this session: its row is
   then not shown, as a control that cannot work is not (quire#355) *)
val _lock_refused = ref<bool>(false)

(* What the app's system bars show, as its native side last reported
   them (bridge's listen_system_bars): full screen is what the screen
   shows only when no bar is (quire#314). Not reported: a browser, or an
   app whose activity does not report them *)
datatype bars_seen =
  | BarsNotReported
  | SomeBarShown
  | NoBarShown

val _bars = ref<bars_seen>(BarsNotReported())

(* Whether the screen is in full screen now: in the app, its system bars
   all hidden, as reported (Android brings them back at a swipe from the
   screen's edge, and full screen asked for stays asked: fullscreen_active
   still says so); else as bridge has it *)
fn _fullscreen_shown (): bool =
  case+ !_bars of
  | BarsNotReported() => $SCR.fullscreen_active()
  | SomeBarShown() => false
  | NoBarShown() => true

(* The brightness last set on the screen *)
val _brightness_on_screen = ref<brightness_choice>(BrightnessSystem())
val _level_on_screen = ref<int>(0)

fn _pressed {id_len:pos | id_len < 256} (id: string id_len, on: bool): void =
  if on then ui_attr(id, APressed, "true") else ui_attr(id, APressed, "false")

(* The Screen row's controls, each where it can be had now *)
#pub fn screen_controls_show (): void

implement screen_controls_show () = let
  val full = $SCR.fullscreen_available()
  val lock = (if !_lock_refused then false else $SCR.orientation_available())
  val brightness = $SCR.brightness_available()
  val () = ui_show("screen-fullscreen-row", full)
  val () = ui_show("screen-lock-row", lock)
  val () = ui_show("screen-brightness-row", brightness)
  val () = ui_show("screen-brightness-system-row", brightness)
  val () = ui_show("screen-row", (if full then true else if lock then true else brightness))
  val () = _pressed("screen-fullscreen", _fullscreen_shown())
in
  (* a lock the browser can no longer keep (full screen left) is let go *)
  if lock then ()
  else case+ set_rotation_get() of
  | RotationFree() => ()
  | RotationLocked() => let
      val () = !_locked := false
      val () = set_rotation_set(RotationFree())
    in _pressed("screen-lock", false) end
end

(* ============================================================
   Full screen
   ============================================================ *)

(* Full screen clicked: out of it, or into it from what the switch shows
   (bars the system brought back are hidden again) *)
#pub fn screen_fullscreen_toggle (): void

implement screen_fullscreen_toggle () =
  if _fullscreen_shown() then $SCR.fullscreen_exit() else $SCR.fullscreen_enter()

fn _fullscreen_same (one: fullscreen_choice, other: fullscreen_choice): bool =
  case+ (one, other) of
  | (FullscreenOn(), FullscreenOn()) => true
  | (FullscreenOff(), FullscreenOff()) => true
  | (_, _) => false

(* Full screen entered or left (Escape leaves it too): the toggle
   follows, and the lock, which a browser allows only in full screen. In
   the app, what the screen now shows is kept with the settings (a
   change to it saved), so the app opens again as it was (quire#313); a
   browser's full screen is a moment's, never kept *)
#pub fn screen_fullscreen_changed (change: $SCR.fullscreen_change): void

implement screen_fullscreen_changed (change) = let
  val shown = (case+ change of
    | $SCR.FullscreenEntered() => FullscreenOn()
    | $SCR.FullscreenLeft() => FullscreenOff()): fullscreen_choice
  val () = (case+ shown of
    | FullscreenOn() => _pressed("screen-fullscreen", true)
    | FullscreenOff() => _pressed("screen-fullscreen", false))
  val () = (if $BAPP.is_native_platform() then
      (if _fullscreen_same(shown, set_fullscreen_get()) then ()
       else let
         val () = set_fullscreen_set(shown)
       in set_save(lib_state_get()) end)
    else ())
in screen_controls_show() end

(* The app's system bars reported (at each of Android's window insets
   dispatches): the switch shows them at once. Bars the system brought
   back stay until the next page is shown (reader.bats hides them again
   while full screen is on), as a swipe from the edge is the reader's
   own way out of immersive mode (quire#314) *)
#pub fn screen_system_bars_changed (bars: $SCR.system_bars): bool

implement screen_system_bars_changed (bars) = let
  val seen = (case+ bars of
    | $SCR.BarsHidden() => NoBarShown()
    | $SCR.BarsShown() => SomeBarShown()
    | $SCR.StatusBarShown() => SomeBarShown()
    | $SCR.NavigationBarShown() => SomeBarShown()): bars_seen
  (* whether the bars shown differ from the last report: the reading
     area does, for the app is drawn edge to edge and the insets are
     the bars (quire#356) *)
  val changed = (case+ (seen, !_bars) of
    | (NoBarShown(), NoBarShown()) => false
    | (SomeBarShown(), SomeBarShown()) => false
    | (_, _) => true): bool
  val () = !_bars := seen
  val () = _pressed("screen-fullscreen", _fullscreen_shown())
in changed end

(* In the app, the screen put in full screen or out of it as the
   settings keep it, where it is not so already *)
fn _fullscreen_apply (): void =
  if $BAPP.is_native_platform() then
    (case+ set_fullscreen_get() of
     | FullscreenOn() => if $SCR.fullscreen_active() then () else $SCR.fullscreen_enter()
     | FullscreenOff() => if $SCR.fullscreen_active() then $SCR.fullscreen_exit() else ())
  else ()

(* ============================================================
   The rotation lock
   ============================================================ *)

(* The rotation locked to the one the screen has now; the toggle and the
   setting follow once it is (or is refused) *)
fn _lock (): void =
  $P.finish<$SCR.lock_outcome>($SCR.orientation_lock_current(), llam(outcome) =>
    case+ outcome of
    | $SCR.Locked() => let
        val () = !_locked := true
        val () = set_rotation_set(RotationLocked())
        val () = set_save(lib_state_get())
      in _pressed("screen-lock", true) end
    | $SCR.LockRefused() => let
        val () = !_locked := false
        val () = !_lock_refused := true
        val () = set_rotation_set(RotationFree())
        val () = set_save(lib_state_get())
        val () = _pressed("screen-lock", false)
        val () = screen_controls_show()
      in notice_error("This device does not let Quire lock the rotation, so Lock rotation is no longer offered. Turn the device's own rotation lock on instead.") end)

(* Lock rotation clicked: locked, or let go, and kept *)
#pub fn screen_lock_toggle (): void

implement screen_lock_toggle () =
  case+ set_rotation_get() of
  | RotationLocked() => let
      val () = $SCR.orientation_unlock()
      val () = !_locked := false
      val () = set_rotation_set(RotationFree())
      val () = set_save(lib_state_get())
    in _pressed("screen-lock", false) end
  | RotationFree() => _lock()

(* ============================================================
   The brightness
   ============================================================ *)

(* What bridge's brightness_set takes for the settings' brightness *)
fn _setting_of (choice: brightness_choice): $SCR.brightness_setting =
  case+ choice of
  | BrightnessSystem() => $SCR.FollowSystem()
  | BrightnessOwn() => $SCR.Level(set_brightness_level_get())

fn _same (one: brightness_choice, other: brightness_choice): bool =
  case+ (one, other) of
  | (BrightnessSystem(), BrightnessSystem()) => true
  | (BrightnessOwn(), BrightnessOwn()) => true
  | (_, _) => false

(* The slider, made again at the level kept (after the settings are
   loaded, reset or restored; not while it is being moved), and the
   switch for the system's own *)
fn _brightness_controls (): void = let
  val value_text = $A.alloc<byte>(16)
  val value_len = $S.int_to_str(value_text, 0, 16, set_brightness_level_get())
  val () = ui_range("screen-brightness-slider", "screen-brightness-label", "Brightness while reading",
    "screen-brightness", "10", "100", "screen-brightness-value", value_text, value_len)
in
  case+ set_brightness_get() of
  | BrightnessSystem() => _pressed("screen-brightness-system", true)
  | BrightnessOwn() => _pressed("screen-brightness-system", false)
end

(* The brightness the settings keep, put on the screen and saved *)
fn _brightness_put (): void = let
  val () = !_brightness_on_screen := set_brightness_get()
  val () = !_level_on_screen := set_brightness_level_get()
  val () = set_save(lib_state_get())
in if $SCR.brightness_available() then $SCR.brightness_set(_setting_of(set_brightness_get())) else () end

(* The slider moved to level (an input event: while it is dragged, each
   step), so the screen is that bright at once and the reader sees the
   brightness they are choosing; its own brightness is then chosen *)
#pub fn screen_brightness_moved (moved_to: int): void

implement screen_brightness_moved (moved_to) = let
  val level = g1ofg0(moved_to)
  val level = (if level < 10 then 10 else if level > 100 then 100 else level): set_brightness_level
  val () = set_brightness_level_set(level)
  val () = set_brightness_set(BrightnessOwn())
  val () = _pressed("screen-brightness-system", false)
in _brightness_put() end

(* Same as device clicked: the system's own brightness, or the level
   the slider shows *)
#pub fn screen_brightness_system_toggle (): void

implement screen_brightness_system_toggle () = let
  val () = (case+ set_brightness_get() of
    | BrightnessSystem() => set_brightness_set(BrightnessOwn())
    | BrightnessOwn() => set_brightness_set(BrightnessSystem()))
  val () = (case+ set_brightness_get() of
    | BrightnessSystem() => _pressed("screen-brightness-system", true)
    | BrightnessOwn() => _pressed("screen-brightness-system", false))
in _brightness_put() end

(* ============================================================
   The settings, set again
   ============================================================ *)

(* The settings' brightness, rotation lock and (in the app) full screen
   set on the screen, where they differ from what is set (a reset of the
   settings, its Undo, a backup restored): the slider and the switches
   follow *)
#pub fn screen_controls_apply (): void

implement screen_controls_apply () = let
  val () = _fullscreen_apply()
  val chosen = set_brightness_get()
  val () = _brightness_controls()
  val () = (if _same(chosen, !_brightness_on_screen) then (if set_brightness_level_get() = !_level_on_screen then () else
      (if $SCR.brightness_available() then $SCR.brightness_set(_setting_of(chosen)) else ()))
    else let
      val () = !_brightness_on_screen := chosen
    in if $SCR.brightness_available() then $SCR.brightness_set(_setting_of(chosen)) else () end)
  val () = !_level_on_screen := set_brightness_level_get()
in
  case+ set_rotation_get() of
  | RotationFree() => let
      (* let go when it was locked *)
      val () = (if !_locked then $SCR.orientation_unlock() else ())
      val () = !_locked := false
    in _pressed("screen-lock", false) end
  | RotationLocked() =>
    if !_locked then ()
    else if $SCR.orientation_available() then _lock()
    else let
      val () = set_rotation_set(RotationFree())
    in _pressed("screen-lock", false) end
end

(* ============================================================
   Startup
   ============================================================ *)

(* Once the settings are read, before the first view is shown: the rows
   as the platform has them, the brightness slider, and what
   was kept put back: in the app, full screen, a brightness other than
   the system's, and (where nothing else asks for it) the rotation
   lock *)
#pub fn screen_controls_start (): void

implement screen_controls_start () = let
  val () = _brightness_controls()
  (* the app starts as full screen was kept (quire#313): its system bars
     hidden, or shown (bars a page before this one hid, the app reopened
     and its page loaded again, are shown), set either way, so the screen
     is as kept whatever an earlier page left (quire#300). A browser
     starts out of full screen: it enters it only at a click *)
  val () = (if $BAPP.is_native_platform() then
      (case+ set_fullscreen_get() of
       | FullscreenOn() => $SCR.fullscreen_enter()
       | FullscreenOff() => $SCR.fullscreen_exit())
    else ())
  (* what full screen hides, on this platform: the system's bars in the
     app, the browser's own around the page in a browser *)
  val () = (if $BAPP.is_native_platform() then ui_text("screen-fullscreen-about", "Hides the status and navigation bars")
    else ui_text("screen-fullscreen-about", "Hides the browser's bars around the page"))
  val () = screen_controls_show()
  (* the switch says so from the first frame: the bars are hidden as the
     plugin answers, and its change confirms it *)
  val () = (if $BAPP.is_native_platform() then
      (case+ set_fullscreen_get() of
       | FullscreenOn() => _pressed("screen-fullscreen", true)
       | FullscreenOff() => ())
    else ())
  val () = (if $SCR.brightness_available() then (case+ set_brightness_get() of
      | BrightnessSystem() => ()
      | BrightnessOwn() => let
          val () = !_brightness_on_screen := set_brightness_get()
          val () = !_level_on_screen := set_brightness_level_get()
        in $SCR.brightness_set(_setting_of(set_brightness_get())) end)
    else ())
in
  case+ set_rotation_get() of
  | RotationFree() => ()
  | RotationLocked() =>
    if $BAPP.is_native_platform() then (if $SCR.orientation_available() then _lock() else ())
    else set_rotation_set(RotationFree())
end

end (* #target wasm *)
