(* image_viewer -- a book's picture, full screen: fitted to the screen,
   zoomed by a pinch, a double tap or the Zoom buttons, and moved by a
   finger (quire#382).

   The picture is the page's own `image-full`, in the scroller
   `image-box`. Its box is the scroller's own size at a zoom
   (ui_picture_box: the box's width and height, and CSS zoom in
   thousandths), and the browser fits the picture inside the box
   (object-fit: contain), so the fit needs no knowledge of the picture's
   size. A zoomed box is larger than the scroller, which scrolls it; a
   pan is a scroll.

   The zoom is the one number `_zoom`, in thousandths of the fit, always
   from ZOOM_FIT to ZOOM_MOST: every zoom reaching the page goes through
   viewer_clamp, so a zoom of 0 (which would hide the picture) or one
   past the box's limit does not type-check. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
staload "ui.sats"
staload "mem.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"

(* The picture fitted whole: a zoom of 1 *)
#define ZOOM_FIT 1000

(* The most a picture is zoomed: 4 times the fit, as PhotoSwipe's default
   maximum is (photoswipe.com/adjusting-zoom-level) *)
#define ZOOM_MOST 4000

(* What a double tap on a fitted picture zooms to: 2.5 times the fit, as
   PhotoSwipe's secondary zoom level is *)
#define ZOOM_DOUBLE_TAP 2500

(* A zoom in thousandths, held to ZOOM_FIT to ZOOM_MOST *)
fn viewer_clamp (zoom: int): [clamped:int | clamped >= 1000; clamped <= 4000] int clamped = let
  val zoom = g1ofg0(zoom)
in
  if zoom < 1000 then 1000
  else if zoom > 4000 then 4000
  else zoom
end

(* A length in CSS pixels, held to what a box can be *)
fn viewer_pixels (length: int): [pixels:pos | pixels <= 10000] int pixels = let
  val length = g1ofg0(length)
in
  if length < 1 then 1
  else if length > 10000 then 10000
  else length
end

(* The zoom now *)
val _zoom = ref<int>(ZOOM_FIT)

(* The zoom when the pinch now on began, or 0 when none is on *)
val _pinch_base = ref<int>(0)

(* Where the pinch's midpoint was at its last event (CSS px), or -1 *)
val _pinch_x = ref<int>(~1)
val _pinch_y = ref<int>(~1)

(* A scroller's or a box's place and size, to the measure slots; whether
   it is there *)
fn _measure {id_len:pos | id_len < 256} (id: string id_len): bool = let
  val id_len = g1u2i(string1_length(id))
  val id_buf = $A.alloc<byte>(id_len)
  val () = $A.write_text(id_buf, 0, $A.text_lit(id), id_len)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id_buf)
  val measured = $DR.measure(id_bytes, id_len)
  val () = release_bytes(id_frozen, id_bytes)
in
  case+ measured of
  | $DR.Measured() => true
  | $DR.NoElement() => false
end

(* The scroller: where its left and top are, and its size; none (all 0)
   when it is not shown *)
typedef scroller = @(int, int, int, int)

fn _scroller (): scroller =
  if _measure("image-box") then @($DR.get_measure_x(), $DR.get_measure_y(), $DR.get_measure_w(), $DR.get_measure_h())
  else @(0, 0, 0, 0)

(* How far the scroller is scrolled: the picture's box starts at the
   scroller's left and top less this *)
fn _scrolled (scroller: scroller): @(int, int) =
  if _measure("image-full") then let
    val left = scroller.0 - $DR.get_measure_x()
    val top = scroller.1 - $DR.get_measure_y()
  in @((if left > 0 then left else 0), (if top > 0 then top else 0)) end
  else @(0, 0)

fn _nonneg (value: int): [n:nat] int n = let val value = g1ofg0(value) in if value < 0 then 0 else value end

(* The picture at zoom, the point of it that is at (anchor_x, anchor_y)
   in the scroller (CSS px from its left and top) before staying there *)
fn _zoom_to (zoom: int, anchor_x: int, anchor_y: int): void = let
  val scroller = _scroller()
in
  if scroller.2 <= 0 then ()
  else if scroller.3 <= 0 then ()
  else let
    val before = !_zoom
    val @(left, top) = _scrolled(scroller)
    (* the point's place in the picture at a zoom of 1 *)
    val point_x = (left + anchor_x) * ZOOM_FIT / before
    val point_y = (top + anchor_y) * ZOOM_FIT / before
    val after = viewer_clamp(zoom)
    val () = !_zoom := after
    val () = ui_picture_box("image-full", viewer_pixels(scroller.2), viewer_pixels(scroller.3), after)
  in ui_scroll_set("image-box", _nonneg(point_x * after / ZOOM_FIT - anchor_x), _nonneg(point_y * after / ZOOM_FIT - anchor_y)) end
end

(* The picture opened: fitted whole. Called with the viewer shown, since
   a hidden scroller has no size *)
#pub fn viewer_open (): void
implement viewer_open () = let
  val () = !_zoom := ZOOM_FIT
  val () = !_pinch_base := 0
  val () = !_pinch_x := ~1
  val scroller = _scroller()
in
  if scroller.2 <= 0 then ()
  else if scroller.3 <= 0 then ()
  else let
    val () = ui_picture_box("image-full", viewer_pixels(scroller.2), viewer_pixels(scroller.3), ZOOM_FIT)
  in ui_scroll_set("image-box", 0, 0) end
end

(* The window changed size: the picture is fitted again *)
#pub fn viewer_resized (): void
implement viewer_resized () = viewer_open()

(* A double tap at (x, y), CSS px of the window: a fitted picture zooms
   in there, a zoomed one goes back to the fit. Instant, so it is the
   same under reduced motion *)
#pub fn viewer_double_tap (x: int, y: int): void
implement viewer_double_tap (x, y) = let
  val scroller = _scroller()
in
  if !_zoom > ZOOM_FIT then _zoom_to(ZOOM_FIT, x - scroller.0, y - scroller.1)
  else _zoom_to(ZOOM_DOUBLE_TAP, x - scroller.0, y - scroller.1)
end

(* The Zoom buttons: half as much again, or two thirds, about the
   scroller's middle *)
#pub fn viewer_zoom_in (): void
implement viewer_zoom_in () = let
  val scroller = _scroller()
in _zoom_to(!_zoom * 3 / 2, scroller.2 / 2, scroller.3 / 2) end

#pub fn viewer_zoom_out (): void
implement viewer_zoom_out () = let
  val scroller = _scroller()
in _zoom_to(!_zoom * 2 / 3, scroller.2 / 2, scroller.3 / 2) end

(* A pinch's event: the fingers' distance is scale (in 1024ths) of what it
   began as, about the midpoint (mid_x, mid_y) in 1/16 CSS px. The picture
   is zoomed from the zoom the pinch began at, and the point of it under
   the previous midpoint goes under this one (the fingers move it too) *)
#pub fn viewer_pinch (scale: int, mid_x: int, mid_y: int): void
implement viewer_pinch (scale, mid_x, mid_y) = let
  val scroller = _scroller()
  val x = mid_x / 16 - scroller.0
  val y = mid_y / 16 - scroller.1
  val () = (if !_pinch_base <= 0 then !_pinch_base := !_zoom else ())
  val from_x = (if !_pinch_x >= 0 then !_pinch_x else x): int
  val from_y = (if !_pinch_y >= 0 then !_pinch_y else y): int
  val () = !_pinch_x := (if x >= 0 then x else 0)
  val () = !_pinch_y := (if y >= 0 then y else 0)
  val target = !_pinch_base * scale / 1024
  (* the point under the previous midpoint, taken to this midpoint *)
  val after = viewer_clamp(target)
  val before = !_zoom
in
  if scroller.2 <= 0 then ()
  else if scroller.3 <= 0 then ()
  else let
    val @(left, top) = _scrolled(scroller)
    val point_x = (left + from_x) * ZOOM_FIT / before
    val point_y = (top + from_y) * ZOOM_FIT / before
    val () = !_zoom := after
    val () = ui_picture_box("image-full", viewer_pixels(scroller.2), viewer_pixels(scroller.3), after)
  in ui_scroll_set("image-box", _nonneg(point_x * after / ZOOM_FIT - x), _nonneg(point_y * after / ZOOM_FIT - y)) end
end

#pub fn viewer_pinch_end (): void
implement viewer_pinch_end () = let
  val () = !_pinch_base := 0
in !_pinch_x := ~1 end

(* The picture moved by (dx, dy) CSS px with a finger: the scroller goes
   the other way *)
fn _pan_by (dx: int, dy: int): void = let
  val scroller = _scroller()
  val @(left, top) = _scrolled(scroller)
in ui_scroll_set("image-box", _nonneg(left - dx), _nonneg(top - dy)) end

(* The pointers down on the viewer, and the one being dragged: its id
   and where it was (1/16 CSS px). A drag is a pan, whatever its length:
   in the viewer a finger has nothing else to mean, so there is nothing
   for the gestures package's classifier to tell apart. A second finger
   ends it (the pinch has the fingers then), and when one of two lifts
   the finger left is dragged on from where it is (id DRAG_AGAIN) *)
#define NO_DRAG ~1
#define DRAG_AGAIN ~2

val _down_count = ref<int>(0)
val _drag_id = ref<int>(NO_DRAG)
val _drag_x = ref<int>(0)
val _drag_y = ref<int>(0)

(* A raw pointer record of the viewer (bridge's listen_pointer): its kind
   (0 down, 1 move, 2 up, 3 cancel, 5 page hidden), pointer id, place,
   and the pointer's type (0 touch, 1 mouse, 2 pen; given by down only). A
   mouse is not dragged: the scroller's scroll bars and wheel are its *)
#pub fn viewer_pointer (kind: int, id: int, x: int, y: int, pointer_type: int): void
implement viewer_pointer (kind, id, x, y, pointer_type) =
  if kind = 0 then let
    val () = !_down_count := !_down_count + 1
  in
    if !_down_count = 1 then
      (if pointer_type = 1 then !_drag_id := NO_DRAG
       else let
         val () = !_drag_id := id
         val () = !_drag_x := x
       in !_drag_y := y end)
    else !_drag_id := NO_DRAG
  end
  else if kind = 1 then
    (if !_down_count <> 1 then ()
     else if !_drag_id = DRAG_AGAIN then let
       val () = !_drag_id := id
       val () = !_drag_x := x
     in !_drag_y := y end
     else if !_drag_id <> id then ()
     else let
       val dx = (x - !_drag_x) / 16
       val dy = (y - !_drag_y) / 16
     in
       (* only whole pixels are taken, the rest stays for the next move *)
       if dx = 0 && dy = 0 then ()
       else let
         val () = !_drag_x := !_drag_x + dx * 16
         val () = !_drag_y := !_drag_y + dy * 16
       in _pan_by(dx, dy) end
     end)
  else if kind = 2 || kind = 3 then let
    val () = !_down_count := (if !_down_count > 0 then !_down_count - 1 else 0)
  in
    if !_down_count = 0 then !_drag_id := NO_DRAG
    else if !_down_count = 1 then !_drag_id := DRAG_AGAIN
    else ()
  end
  else if kind = 5 then let
    val () = !_down_count := 0
  in !_drag_id := NO_DRAG end
  else ()

end
