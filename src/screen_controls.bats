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

(* Whether the immersive reading screen is shown: the reader, its own
   bars away (quire.bats says, at each change). In the app, full screen
   hides the system bars only then (quire#348): in the library, and while
   the in-book menu shows, they are there *)
val _immersive = ref<bool>(false)

(* Whether the Full screen switch is on. In the app it is the setting,
   whatever the system's bars are showing at the moment (they come and go
   with the reader's menu); in a browser, whether the page is in full
   screen *)
fn _fullscreen_shown (): bool =
  if $BAPP.is_native_platform() then
    (case+ set_fullscreen_get() of FullscreenOn() => true | FullscreenOff() => false)
  else $SCR.fullscreen_active()

(* The app's system bars as full screen and the immersive screen want
   them: hidden when both hold, shown otherwise. Asking to hide bars
   already hidden changes nothing, and brings back the ones a swipe
   from the edge showed *)
fn _follow (): void =
  if $BAPP.is_native_platform() then
    (if (if !_immersive then _fullscreen_shown() else false) then $SCR.fullscreen_enter()
     else (if $SCR.fullscreen_active() then $SCR.fullscreen_exit() else ()))
  else ()

(* The brightness last set on the screen *)
val _brightness_on_screen = ref<brightness_choice>(BrightnessSystem())

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

(* Full screen clicked. In the app the setting is turned and kept, and
   the bars follow when the reader is immersive (the switch is clicked in
   the in-book menu, where the bars stay; quire#348); in a browser, the
   page goes into full screen or out of it *)
#pub fn screen_fullscreen_toggle (): void

implement screen_fullscreen_toggle () =
  if $BAPP.is_native_platform() then let
    val () = (case+ set_fullscreen_get() of
      | FullscreenOn() => set_fullscreen_set(FullscreenOff())
      | FullscreenOff() => set_fullscreen_set(FullscreenOn()))
    val () = set_save(lib_state_get())
    val () = _pressed("screen-fullscreen", _fullscreen_shown())
  in _follow() end
  else if $SCR.fullscreen_active() then $SCR.fullscreen_exit() else $SCR.fullscreen_enter()

(* The immersive reading screen entered or left (quire.bats, at the
   reader's own bars going and coming, the library, a book opened): in
   the app, full screen hides the system bars then and only then *)
#pub fn screen_immersive_set (immersive: bool): void

implement screen_immersive_set (immersive) = let
  val () = !_immersive := immersive
in _follow() end

(* A page shown while immersive: bars a swipe from the screen's edge
   brought back are hidden again, as a reading app keeps them hidden
   while it reads (quire#300); not while the in-book menu is up *)
#pub fn screen_bars_hidden_again (): void

implement screen_bars_hidden_again () = _follow()

(* Full screen entered or left (Escape leaves it too): in a browser the
   toggle follows, and the lock, which a browser allows only in full
   screen. In the app the setting is the switch's, kept when the switch is
   clicked (quire#313), and the bars come and go with the reader (quire#348),
   so what the screen shows does not change it; a browser's full screen
   is a moment's, never kept *)
#pub fn screen_fullscreen_changed (change: $SCR.fullscreen_change): void

implement screen_fullscreen_changed (change) = let
  val () = _pressed("screen-fullscreen", _fullscreen_shown())
in screen_controls_show() end

(* The app's system bars reported (at each of Android's window insets
   dispatches): whether what they show changed is answered, for the
   reading area changes with it. Bars the system brought back stay until
   the next page is shown (reader.bats hides them again while the reader
   is immersive), as a swipe from the edge is the reader's own way out of
   immersive mode (quire#314) *)
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
fn _fullscreen_apply (): void = let
  val () = _pressed("screen-fullscreen", _fullscreen_shown())
in _follow() end

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
fn _option_of (choice: brightness_choice): @([value_len:pos | value_len < 8] string value_len, [label_len:pos | label_len < 16] string label_len) =
  case+ choice of
  | BrightnessSystem() => @("system", "Same as device")
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
fn _bytes_of {text_len:pos | text_len < 16} (text: string text_len): [l:agz] @($A.arr(byte, l, text_len), int text_len) = let
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
        val () = !_brightness_on_screen := choice
        val () = set_save(lib_state_get())
      in
        if $SCR.brightness_available() then $SCR.brightness_set(_setting_of(choice)) else ()
      end
    end
end

(* ============================================================
   The settings, set again
   ============================================================ *)

(* The settings' brightness, rotation lock and (in the app) full screen
   set on the screen, where they differ from what is set (a reset of the
   settings, its Undo, a backup restored): the select and the toggles
   follow *)
#pub fn screen_controls_apply (): void

implement screen_controls_apply () = let
  val () = _fullscreen_apply()
  val chosen = set_brightness_get()
  val () = _brightness_options()
  val () = (if _same(chosen, !_brightness_on_screen) then ()
    else let
      val () = !_brightness_on_screen := chosen
    in if $SCR.brightness_available() then $SCR.brightness_set(_setting_of(chosen)) else () end)
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
   as the platform has them, the brightness select's levels, and what
   was kept put back: in the app, full screen, a brightness other than
   the system's, and (where nothing else asks for it) the rotation
   lock *)
#pub fn screen_controls_start (): void

implement screen_controls_start () = let
  val () = _brightness_options()
  (* the app starts in the library, where the system bars are shown
     whatever full screen was kept (quire#348, quire#313): they are set so,
     whatever an earlier page left (quire#300), and hidden when the reader
     is immersive. A browser starts out of full screen: it enters it only
     at a click *)
  val () = (if $BAPP.is_native_platform() then $SCR.fullscreen_exit() else ())
  (* what full screen hides, on this platform: the system's bars in the
     app, the browser's own around the page in a browser *)
  val () = (if $BAPP.is_native_platform() then ui_text("screen-fullscreen-about", "Hides the status and navigation bars while you read; the menus and the library show them")
    else ui_text("screen-fullscreen-about", "Hides the browser's bars around the page"))
  val () = screen_controls_show()
  (* the switch says what is kept from the first frame *)
  val () = (if $BAPP.is_native_platform() then
      (case+ set_fullscreen_get() of
       | FullscreenOn() => _pressed("screen-fullscreen", true)
       | FullscreenOff() => ())
    else ())
  val () = (if $SCR.brightness_available() then (case+ set_brightness_get() of
      | BrightnessSystem() => ()
      | _ => let
          val () = !_brightness_on_screen := set_brightness_get()
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
