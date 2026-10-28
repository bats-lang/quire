(* reading_ruler -- where the reading ruler's line is and its band, found by the caret at a point (keyword: reading ruler, #566) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S

staload "ui.sats"
staload "mem.sats"
staload "settings.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"

(* The reader's page as the reading ruler sees it, told at each page shown *)
#pub datatype ruler_view = RulerPaged | RulerPagedBack | RulerScrolled | RulerDownRight | RulerDownLeft | RulerNone

(* Reading ruler: what a raw pointer record says happened *)
#pub datatype ruler_record = RulerRecordDown | RulerRecordMove | RulerRecordUp | RulerRecordCancel | RulerRecordHidden | RulerRecordOther

(* Reading ruler: the device of a pointer record, a mouse or a finger or pen *)
#pub datatype ruler_device = RulerDeviceMouse | RulerDeviceTouchOrPen

(* Reading ruler: decodes the record's kind once *)
#pub fn ruler_record_of_code (code: int): ruler_record

(* Reading ruler: decodes the record's pointer type once *)
#pub fn ruler_device_of_code (code: int): ruler_device

(* Reading ruler: a page is shown, the ruler goes to its first line *)
#pub fn ruler_page_shown (view: ruler_view): void

(* Reading ruler: the style or the height changed, or the reader opened *)
#pub fn ruler_apply (): void

(* Reading ruler: a panel over the reader closed, a pending ruler is placed *)
#pub fn ruler_retry (): void

(* Reading ruler: a sentence or a clip begins at offset of content node node *)
#pub fn ruler_follow (node: int, offset: int): void

(* Reading ruler: a tap at x, y moves it to the line there; whether it did *)
#pub fn ruler_tap (x: int, y: int): bool

(* Reading ruler: a raw pointer record of the reader; whether the ruler took it *)
#pub fn ruler_pointer (record: ruler_record, id: int, x: int, y: int, device: ruler_device): bool


val _view = ref<ruler_view>(RulerNone())

fn ruler_view_set (view: ruler_view): void = !_view := view

fn _is_down (view: ruler_view): bool =
  case+ view of
  | RulerDownRight() => true
  | RulerDownLeft() => true
  | RulerPaged() => false
  | RulerPagedBack() => false
  | RulerScrolled() => false
  | RulerNone() => false

(* Reading ruler: whether the style chosen draws a band *)
fn _style_draws (): bool =
  case+ set_ruler_get() of
  | RulerOff() => false
  | RulerUnderline() => true
  | RulerGreyBar() => true
  | RulerShade() => true
  | RulerLightbox() => true

(* Reading ruler: whether the style chosen draws a band on this view *)
fn _drawn (view: ruler_view): bool =
  case+ view of
  | RulerNone() => false
  | RulerPaged() => _style_draws ()
  | RulerPagedBack() => _style_draws ()
  | RulerScrolled() => _style_draws ()
  | RulerDownRight() => _style_draws ()
  | RulerDownLeft() => _style_draws ()

(* Reading ruler: the line's height in px, the text's size times its spacing *)
fn _line_px (): int = let
  val line = (set_size_get() * set_lh_get() + 5) / 10
in if line > 0 then line else 1 end

(* Reading ruler: the lines the band holds *)
fn _band_lines (): int =
  case+ set_ruler_get() of
  | RulerGreyBar() => ruler_line_count(set_ruler_lines_get())
  | RulerLightbox() => ruler_line_count(set_ruler_lines_get())
  | RulerOff() => 1
  | RulerUnderline() => 1
  | RulerShade() => 1

(* Reading ruler: the class of the ruler's element, its style and column way *)
fn _class_apply (view: ruler_view): void =
  if ~(_drawn(view)) then ui_attr("ruler", AClass, "ruler")
  else if _is_down(view) then
    (case+ set_ruler_get() of
     | RulerUnderline() => ui_attr("ruler", AClass, "ruler ruler-underline ruler-down")
     | RulerGreyBar() => ui_attr("ruler", AClass, "ruler ruler-grey ruler-down")
     | RulerShade() => ui_attr("ruler", AClass, "ruler ruler-shade ruler-down")
     | RulerLightbox() => ui_attr("ruler", AClass, "ruler ruler-lightbox ruler-down")
     | RulerOff() => ui_attr("ruler", AClass, "ruler"))
  else
    (case+ set_ruler_get() of
     | RulerUnderline() => ui_attr("ruler", AClass, "ruler ruler-underline")
     | RulerGreyBar() => ui_attr("ruler", AClass, "ruler ruler-grey")
     | RulerShade() => ui_attr("ruler", AClass, "ruler ruler-shade")
     | RulerLightbox() => ui_attr("ruler", AClass, "ruler ruler-lightbox")
     | RulerOff() => ui_attr("ruler", AClass, "ruler"))

(* ============ Reading ruler: where the line is ============ *)

(* Reading ruler: the text area as last measured, in viewport px *)
val _area_x = ref<int>(0)
val _area_y = ref<int>(0)
val _area_width = ref<int>(0)
val _area_height = ref<int>(0)

(* Reading ruler: whether the text area is laid out *)
fn _area_measure (): bool = let
  val () = ui_measure("ruler")
  val () = !_area_x := $DR.get_measure_x()
  val () = !_area_y := $DR.get_measure_y()
  val () = !_area_width := $DR.get_measure_w()
  val () = !_area_height := $DR.get_measure_h()
in !_area_width > 0 && !_area_height > 0 end

(* Reading ruler: whether the screen shows two columns *)
fn _spread (): bool = let
  val () = ui_measure("spread-probe")
in $DR.get_measure_w() > 0 end

(* Reading ruler: the content node at a point, or none *)
datavtype ruler_node = RulerNodeNone | {node:nat} RulerNodeAt of (int node)

(* Reading ruler: the content node at x, y *)
fn _node_at (x: int, y: int): ruler_node =
  case+ $DR.element_at_point(x, y) of
  | ~$R.none() => RulerNodeNone()
  | ~$R.some(blob) => let
      val blob_len = $BD.blob_len(blob)
    in
      if blob_len <= 0 then let val () = $BD.blob_free(blob) in RulerNodeNone() end
      else if blob_len > 16 then let val () = $BD.blob_free(blob) in RulerNodeNone() end
      else let
        val id_text = $A.alloc<byte>(blob_len)
        val () = $BD.blob_read(blob, 0, id_text, blob_len)
        val () = $BD.blob_free(blob)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(id_text)
        val node = nid_parse(id_bytes, blob_len, 0, "c")
        val () = release_bytes(id_frozen, id_bytes)
      in if node >= 0 then RulerNodeAt(node) else RulerNodeNone() end
    end

(* Reading ruler: where offset of content node node is, in the measure slots *)
fn _character_place {node:int} (node: int node, offset: int): bool =
  if node < 0 then false
  else let
    val @(id, id_len) = nid_pad3("c", node)
    val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
    val measured = $DR.measure_text_offset(id_bytes, id_len, offset)
    val () = release_bytes(id_frozen, id_bytes)
  in
    case+ measured of
    | $DR.Measured() => true
    | $DR.NoElement() => false
  end

(* Reading ruler: the line it is on, kept for the next time *)
val _placed = ref<bool>(false)
val _band_start = ref<int>(0)
val _band_size = ref<int>(0)

(* Reading ruler: the middle of the line last found and a point on it *)
val _centre = ref<int>(0)
val _probe_x = ref<int>(0)
val _probe_y = ref<int>(0)

(* Reading ruler: the middle of a line whose first character's box starts at start *)
fn _centre_of (start: int): int = start + (set_size_get() * 5) / 8

(* Reading ruler: appends text to the CSS buffer *)
fun _put_from {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (buf: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.set<byte>(buf, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_from(buf, at, text, text_len, i + 1) end

fn _put_text {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}
  (buf: !$A.arr(byte, l, n), at: int at, text: string text_len): int(at + text_len) =
  _put_from(buf, at, text, g1u2i(string1_length(text)), 0)

(* Reading ruler: appends the digits of value to the CSS buffer *)
fn _put_int {l:agz}{at:nat | at + 11 <= 640} (buf: !$A.arr(byte, l, 640), at: int at, value: int): [r:int | at < r; r <= at + 11] int r =
  $S.int_to_str(buf, at, 640, g1ofg0(value))

fn _style_clear (): void =
  ui_text("style-ruler", "#ruler-band,#ruler-before,#ruler-after{display:none}")


(* Reading ruler: the CSS of the band in a horizontal page *)
fn _style_across (start: int, size: int, cross: int): void = let
  val area_x = !_area_x
  val area_width = !_area_width
  val half = (if _spread() then area_width / 2 else area_width): int
  val column = (if _spread() then (if cross >= area_x + half then 1 else 0) else 0): int
  val left = column * half
  val top = start - !_area_y
  val buf = $A.alloc<byte>(640)
  val next = _put_text(buf, 0, "#ruler-band{left:")
  val next = _put_int(buf, next, left)
  val next = _put_text(buf, next, "px;width:")
  val next = _put_int(buf, next, half)
  val next = _put_text(buf, next, "px;top:")
  val next = _put_int(buf, next, top)
  val next = _put_text(buf, next, "px;height:")
  val next = _put_int(buf, next, size)
  val next = _put_text(buf, next, "px}#ruler-before{left:0;right:0;top:0;height:")
  val next = _put_int(buf, next, (if top > 0 then top else 0))
  val next = _put_text(buf, next, "px}#ruler-after{left:0;right:0;bottom:0;top:")
  val next = _put_int(buf, next, top + size)
  val next = _put_text(buf, next, "px}")
in ui_text_buf("style-ruler", buf, next) end

(* Reading ruler: the veils of a vertical page after the band *)
fn _down_pieces {l:agz}{at:nat | at + 200 <= 640}
  (buf: !$A.arr(byte, l, 640), at: int at, left: int, size: int, behind: int, from_right: bool): [r:nat | r <= at + 200] int r =
  if from_right then let
    val next = _put_text(buf, at, "px}#ruler-before{top:0;bottom:0;right:0;left:")
    val next = _put_int(buf, next, left + size)
    val next = _put_text(buf, next, "px}#ruler-after{top:0;bottom:0;left:0;width:")
  in _put_int(buf, next, behind) end
  else let
    val next = _put_text(buf, at, "px}#ruler-before{top:0;bottom:0;left:0;width:")
    val next = _put_int(buf, next, behind)
    val next = _put_text(buf, next, "px}#ruler-after{top:0;bottom:0;right:0;left:")
  in _put_int(buf, next, left + size) end

(* Reading ruler: the CSS of the band in a vertical page *)
fn _style_down (start: int, size: int, from_right: bool): void = let
  val left = start - !_area_x
  val behind = (if left > 0 then left else 0): int
  val buf = $A.alloc<byte>(640)
  val next = _put_text(buf, 0, "#ruler-band{top:0;bottom:0;left:")
  val next = _put_int(buf, next, left)
  val next = _put_text(buf, next, "px;width:")
  val next = _put_int(buf, next, size)
  val next = _down_pieces(buf, next, left, size, behind, from_right)
  val next = _put_text(buf, next, "px}")
in ui_text_buf("style-ruler", buf, next) end

(* Reading ruler: puts the band on the line whose middle is centre *)
fn _line_put (view: ruler_view, centre: int, cross: int): void = let
  val line = _line_px()
  val size = line * _band_lines()
  val () = !_placed := true
  val () = !_centre := centre
in
  case+ view of
  | RulerDownRight() => let
      (* reading ruler: the band reaches left of the line it starts at *)
      val start = centre + line / 2 - size
      val () = !_band_start := start
      val () = !_band_size := size
    in _style_down(start, size, true) end
  | RulerDownLeft() => let
      val start = centre - line / 2
      val () = !_band_start := start
      val () = !_band_size := size
    in _style_down(start, size, false) end
  | RulerNone() => _style_clear()
  | RulerPaged() => let
      val start = centre - line / 2
      val () = !_band_start := start
      val () = !_band_size := size
    in _style_across(start, size, cross) end
  | RulerPagedBack() => let
      val start = centre - line / 2
      val () = !_band_start := start
      val () = !_band_size := size
    in _style_across(start, size, cross) end
  | RulerScrolled() => let
      val start = centre - line / 2
      val () = !_band_start := start
      val () = !_band_size := size
    in _style_across(start, size, cross) end
end

(* Reading ruler: the middle and cross place of the line found at x, y *)
val _found_centre = ref<int>(0)
val _found_cross = ref<int>(0)

fn _line_at (view: ruler_view, x: int, y: int): bool =
  case+ _node_at(x, y) of
  | ~RulerNodeNone() => false
  | ~RulerNodeAt(node) => let
    val offset = (case+ $DR.caret_position_from_point(x, y) of
      | ~$R.some(offset) => offset
      | ~$R.none() => 0): int
  in
    if ~(_character_place(node, offset)) then false
    else let
      val place_x = $DR.get_measure_x()
      val place_y = $DR.get_measure_y()
    in
      if _is_down(view) then let
          val () = !_found_centre := _centre_of(place_x)
          val () = !_found_cross := place_y
        in true end
      else let
          val () = !_found_centre := _centre_of(place_y)
          val () = !_found_cross := place_x
        in true end
    end
  end

(* Reading ruler: puts it on the line at x, y; whether there was one *)
fn _place_at (view: ruler_view, x: int, y: int): bool =
  if _line_at(view, x, y) then let
    val () = !_probe_x := x
    val () = !_probe_y := y
    val () = _line_put(view, !_found_centre, !_found_cross)
  in true end
  else false

(* Reading ruler: looks for the first line of the page from a start, step by step *)
fun _first_from {tries:nat} .<tries>. (view: ruler_view, x: int, y: int, step_x: int, step_y: int, tries: int tries): bool =
  if _place_at(view, x, y) then true
  else if tries <= 0 then false
  else _first_from(view, x + step_x, y + step_y, step_x, step_y, tries - 1)

(* Reading ruler: set when no line could be found because a panel is over the page *)
val _pending = ref<bool>(false)

fn _first_line (view: ruler_view): void = let
  val ok = (if ~(_area_measure()) then false
    else let
      val half = _line_px() / 2 + 1
      val area_x = !_area_x
      val area_y = !_area_y
      val area_width = !_area_width
      val area_height = !_area_height
    in
      case+ view of
      | RulerDownRight() => _first_from(view, area_x + area_width - 1, area_y + area_height / 2, ~half, 0, 14)
      | RulerDownLeft() => _first_from(view, area_x + 1, area_y + area_height / 2, half, 0, 14)
      | RulerNone() => false
      | RulerPaged() => _first_from(view, (if _spread() then area_x + area_width / 4 else area_x + area_width / 2), area_y + 1, 0, half, 14)
      | RulerPagedBack() => _first_from(view, (if _spread() then area_x + (area_width * 3) / 4 else area_x + area_width / 2), area_y + 1, 0, half, 14)
      | RulerScrolled() => _first_from(view, area_x + area_width / 2, area_y + 1, 0, half, 14)
    end): bool
in
  if ok then !_pending := false
  else let
    val () = !_placed := false
    val () = !_pending := true
  in _style_clear() end
end

(* Reading ruler: the kept line asked for again after a scroll *)
fn _line_again (view: ruler_view): void =
  if ~(_area_measure()) then ()
  else if _place_at(view, !_probe_x, !_probe_y) then let
      val line = _line_px()
    in
      if _is_down(view) then ()
      else if !_band_start < !_area_y then let val _ = _place_at(view, !_probe_x, !_probe_y + line) in () end
      else if !_band_start + line > !_area_y + !_area_height then let val _ = _place_at(view, !_probe_x, !_probe_y - line) in () end
      else ()
    end
  else _first_line(view)

(* ============ Reading ruler: what the reader and the settings ask ============ *)

implement ruler_page_shown (view) = let
  val () = ruler_view_set(view)
  val () = _class_apply(view)
in
  if ~(_drawn(view)) then ()
  else (case+ view of
    | RulerScrolled() => if !_placed then _line_again(view) else _first_line(view)
    | RulerPaged() => _first_line(view)
    | RulerPagedBack() => _first_line(view)
    | RulerDownRight() => _first_line(view)
    | RulerDownLeft() => _first_line(view)
    | RulerNone() => ())
end

implement ruler_apply () = let
  val view = !_view
  val () = _class_apply(view)
in
  if ~(_drawn(view)) then !_pending := false
  else if !_placed then
    (* reading ruler: the height changed, no point is asked for *)
    (if _area_measure() then _line_put(view, !_centre, !_found_cross) else ())
  else _first_line(view)
end

(* Reading ruler: puts it on the first line if it still waits *)
fn _retry_now (): void =
  if !_pending then let
      val view = !_view
    in if _drawn(view) then _first_line(view) else !_pending := false end
  else ()

(* Reading ruler: a moment after a panel closed *)
implement ruler_retry () =
  if !_pending then $P.finish<Int>($P.vow($TM.timer_set(50)), llam(_) => _retry_now())
  else ()

implement ruler_follow (node, offset) = let
  val view = !_view
in
  if ~(_drawn(view)) then ()
  else if ~(_area_measure()) then ()
  else if ~(_character_place(g1ofg0(node), offset + 1)) then ()
  else let
    val place_x = $DR.get_measure_x()
    val place_y = $DR.get_measure_y()
    val inside = (if _is_down(view) then (place_x >= !_area_x && place_x < !_area_x + !_area_width)
      else (place_y >= !_area_y && place_y < !_area_y + !_area_height)): bool
  in
    if ~inside then ()
    else if _is_down(view) then let
        val () = !_probe_x := place_x
        val () = !_probe_y := place_y
      in _line_put(view, _centre_of(place_x), place_y) end
    else let
        val () = !_probe_x := place_x
        val () = !_probe_y := place_y
      in _line_put(view, _centre_of(place_y), place_x) end
  end
end

(* Reading ruler: whether x, y is on the band *)
fn _on_band (view: ruler_view, x: int, y: int): bool =
  if ~(!_placed) then false
  else if _is_down(view) then
    (x >= !_band_start && x < !_band_start + !_band_size && y >= !_area_y && y < !_area_y + !_area_height)
  else
    (y >= !_band_start && y < !_band_start + !_band_size && x >= !_area_x && x < !_area_x + !_area_width)

implement ruler_tap (x, y) = let
  val view = !_view
in
  if ~(_drawn(view)) then false
  else if ~(_area_measure()) then false
  else if _on_band(view, x, y) then false
  else _place_at(view, x, y)
end

(* Reading ruler: whether a pointer is dragging it; the pointer's id is kept while it is *)
datatype ruler_drag = RulerIdle | RulerDragging
val _drag = ref<ruler_drag>(RulerIdle())
val _drag_id = ref<int>(0)

fn _drag_by (id: int): bool =
  case+ !_drag of
  | RulerIdle() => false
  | RulerDragging() => !_drag_id = id

fn _drag_end (): void = !_drag := RulerIdle()

implement ruler_record_of_code (code) =
  if code = 0 then RulerRecordDown()
  else if code = 1 then RulerRecordMove()
  else if code = 2 then RulerRecordUp()
  else if code = 3 then RulerRecordCancel()
  else if code = 5 then RulerRecordHidden()
  else RulerRecordOther()

implement ruler_device_of_code (code) =
  if code = 1 then RulerDeviceMouse() else RulerDeviceTouchOrPen()

(* Reading ruler: a finger or pen down on the band of a paged page drags it *)
fn _drag_begin (view: ruler_view, id: int, px: int, py: int): bool =
  case+ !_drag of
  | RulerDragging() => false
  | RulerIdle() =>
    (if ~(_drawn(view)) then false
     else if ~(_area_measure()) then false
     else if ~(_on_band(view, px, py)) then false
     else let val () = !_drag_id := id val () = !_drag := RulerDragging() in true end)

implement ruler_pointer (record, id, x, y, device) = let
  val view = !_view
  val px = x / 16
  val py = y / 16
in
  case+ record of
  | RulerRecordDown() =>
    (case+ device of
     | RulerDeviceMouse() => false
     | RulerDeviceTouchOrPen() =>
       (case+ view of
        | RulerScrolled() => false
        | RulerNone() => false
        | RulerPaged() => _drag_begin(view, id, px, py)
        | RulerPagedBack() => _drag_begin(view, id, px, py)
        | RulerDownRight() => _drag_begin(view, id, px, py)
        | RulerDownLeft() => _drag_begin(view, id, px, py)))
  | RulerRecordMove() =>
    (if ~(_drag_by(id)) then false
     else let val _ = _place_at(view, px, py) in true end)
  | RulerRecordUp() =>
    (if ~(_drag_by(id)) then false
     else let val () = _drag_end() in true end)
  | RulerRecordCancel() =>
    (if ~(_drag_by(id)) then false
     else let val () = _drag_end() in true end)
  | RulerRecordHidden() => let val () = _drag_end() in false end
  | RulerRecordOther() => false

end

end
