(* reading_ruler -- the reading ruler's line (keyword: reading ruler, #566)

   Where the ruler is: a line of the page, found from the point it is asked for (the first line of the
   page, the line a tap or a finger is on, the line a sentence being said starts on) by the caret the
   browser gives there and the place of that character, and the band written as CSS in style-ruler
   over the text area (ruler_rules.bats gives the style its look). The rules of the area are in
   .claude/rules/reader-layout.md *)

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

(* The reader's page as the ruler sees it, told by the reader at each page it shows: paged across (as
   the book reads), scrolled down, a book set vertically (its lines are columns, read from the right
   or from the left), or a page of lines the ruler does not hold (a fixed layout) *)
#pub datatype ruler_view = RulerPaged | RulerPagedBack | RulerScrolled | RulerDownRight | RulerDownLeft | RulerNone

(* A page is shown: the ruler goes to its first line (a scrolled page keeps the ruler at its height) *)
#pub fn ruler_page_shown (view: ruler_view): void

(* The style or the height changed, or the reader opened: the ruler is drawn as chosen *)
#pub fn ruler_apply (): void

(* A panel over the reader closed: a ruler that could not be placed under it is placed now *)
#pub fn ruler_retry (): void

(* A sentence or a clip begins at offset of content node node: the ruler is on its line *)
#pub fn ruler_follow (node: int, offset: int): void

(* A tap at x, y (viewport px): whether it moved the ruler to the line it is on, off the band *)
#pub fn ruler_tap (x: int, y: int): bool

(* A raw pointer record of the reader (kind, pointer id, place in sixteenths of px, pointer type):
   whether the ruler took it, a finger dragging the band *)
#pub fn ruler_pointer (kind: int, id: int, x: int, y: int, pointer_type: int): bool

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

(* Whether the style chosen draws a band on this view *)
fn _drawn (view: ruler_view): bool =
  case+ view of
  | RulerNone() => false
  | RulerPaged() => (case+ set_ruler_get() of RulerOff() => false | _ => true)
  | RulerPagedBack() => (case+ set_ruler_get() of RulerOff() => false | _ => true)
  | RulerScrolled() => (case+ set_ruler_get() of RulerOff() => false | _ => true)
  | RulerDownRight() => (case+ set_ruler_get() of RulerOff() => false | _ => true)
  | RulerDownLeft() => (case+ set_ruler_get() of RulerOff() => false | _ => true)

(* The line's height in px: the text's size times its spacing (in tenths), rounded *)
fn _line_px (): int = let
  val line = (set_size_get() * set_lh_get() + 5) / 10
in if line > 0 then line else 1 end

(* The lines the band holds, one for a style that has no height of its own *)
fn _band_lines (): int =
  case+ set_ruler_get() of
  | RulerGreyBar() => ruler_line_count(set_ruler_lines_get())
  | RulerLightbox() => ruler_line_count(set_ruler_lines_get())
  | RulerOff() => 1
  | RulerUnderline() => 1
  | RulerShade() => 1

(* The class of the ruler's element: its style, and a column's way when the lines are columns *)
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

(* ============================================================
   Where the line is
   ============================================================ *)

(* The text area as last measured (viewport px): the ruler's element, which the reader's paddings
   inset from the page *)
val _area_x = ref<int>(0)
val _area_y = ref<int>(0)
val _area_width = ref<int>(0)
val _area_height = ref<int>(0)

(* Whether the text area is laid out; its box is then in the refs above *)
fn _area_measure (): bool = let
  val () = ui_measure("ruler")
  val () = !_area_x := $DR.get_measure_x()
  val () = !_area_y := $DR.get_measure_y()
  val () = !_area_width := $DR.get_measure_w()
  val () = !_area_height := $DR.get_measure_h()
in !_area_width > 0 && !_area_height > 0 end

(* Whether the screen shows two columns: the probe the typography's style shows then *)
fn _spread (): bool = let
  val () = ui_measure("spread-probe")
in $DR.get_measure_w() > 0 end

(* The content node at x, y (its number), or -1 *)
fn _node_at (x: int, y: int): [node:int | node >= ~1] int node =
  case+ $DR.element_at_point(x, y) of
  | ~$R.none() => ~1
  | ~$R.some(blob) => let
      val blob_len = $BD.blob_len(blob)
    in
      if blob_len <= 0 then let val () = $BD.blob_free(blob) in ~1 end
      else if blob_len > 16 then let val () = $BD.blob_free(blob) in ~1 end
      else let
        val id_text = $A.alloc<byte>(blob_len)
        val () = $BD.blob_read(blob, 0, id_text, blob_len)
        val () = $BD.blob_free(blob)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(id_text)
        val node = nid_parse(id_bytes, blob_len, 0, "c")
        val () = release_bytes(id_frozen, id_bytes)
      in node end
    end

(* Where offset of content node node is: its place goes to the measure slots; whether it has one *)
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

(* The line the ruler is on: where its band starts along the lines' stacking (down the page; across it
   for columns), in viewport px, and how far it reaches; the lines' places kept for the next time *)
val _placed = ref<bool>(false)
val _band_start = ref<int>(0)
val _band_size = ref<int>(0)

(* The middle of the line last found, and a point on it, for the page to be asked again at: a scrolled
   page keeps the ruler at its height *)
val _centre = ref<int>(0)
val _probe_x = ref<int>(0)
val _probe_y = ref<int>(0)

(* The middle of a line whose first character's box starts at start: a box as high as the text is
   wide in em, and the line's height around it *)
fn _centre_of (start: int): int = start + (set_size_get() * 5) / 8

(* Writes the CSS of the band and of the veils for the line whose middle is centre, at cross (its
   place across the lines) *)
fun _put_from {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (buf: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.set<byte>(buf, at + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_from(buf, at, text, text_len, i + 1) end

fn _put_text {l:agz}{n:pos}{text_len:nat}{at:nat | at + text_len <= n}
  (buf: !$A.arr(byte, l, n), at: int at, text: string text_len): int(at + text_len) =
  _put_from(buf, at, text, g1u2i(string1_length(text)), 0)

(* value's digits at buf[at, r) *)
fn _put_int {l:agz}{at:nat | at + 11 <= 640} (buf: !$A.arr(byte, l, 640), at: int at, value: int): [r:int | at < r; r <= at + 11] int r =
  $S.int_to_str(buf, at, 640, g1ofg0(value))

fn _style_clear (): void =
  ui_text("style-ruler", "#ruler-band,#ruler-before,#ruler-after{display:none}")


(* The band of size px starting at start (viewport) in a horizontal page, in the column at cross *)
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

(* The veils of a vertical page after the band: its before is at the right when the columns are read from the right *)
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

(* The band of size px starting at start (viewport) in a vertical page: its columns are read from the
   right (the band's before is at its right) or from the left *)
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

(* The ruler on the line whose middle is centre (viewport), at cross across the lines: the band of
   the style's lines, from this line on in the way the book is read *)
fn _line_put (view: ruler_view, centre: int, cross: int): void = let
  val line = _line_px()
  val size = line * _band_lines()
  val () = !_placed := true
  val () = !_centre := centre
in
  case+ view of
  | RulerDownRight() => let
      (* the lines go on to the left: the band reaches left of the line it starts at *)
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

(* Whether a line was found at x, y: its middle and its place across the lines are then in the refs
   below. The caret the browser puts at the point is on the line the point is on, and the character's
   box starts at the line's glyphs *)
val _found_centre = ref<int>(0)
val _found_cross = ref<int>(0)

fn _line_at (view: ruler_view, x: int, y: int): bool = let
  val node = _node_at(x, y)
in
  if node < 0 then false
  else let
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
end

(* Puts the ruler on the line at x, y; whether there was one *)
fn _place_at (view: ruler_view, x: int, y: int): bool =
  if _line_at(view, x, y) then let
    val () = !_probe_x := x
    val () = !_probe_y := y
    val () = _line_put(view, !_found_centre, !_found_cross)
  in true end
  else false

(* The first line of the page: down from the area's top (across from the side the lines begin at, for
   columns), a few half-lines at a time, until a line is there. Where there is none (a page of a picture
   alone) the ruler is not shown *)
fun _first_from {tries:nat} .<tries>. (view: ruler_view, x: int, y: int, step_x: int, step_y: int, tries: int tries): bool =
  if _place_at(view, x, y) then true
  else if tries <= 0 then false
  else _first_from(view, x + step_x, y + step_y, step_x, step_y, tries - 1)

(* Whether the ruler could not be put on a line, a panel being over the page: it is put when the panel goes *)
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

(* The line kept, asked for again: a scrolled page moved under it, so the line now at the same height.
   A line the page's margin cuts is not one to hold the eye: the ruler goes to the whole line beside it *)
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

(* ============================================================
   What the reader and the settings ask
   ============================================================ *)

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
    (* the line it is on, by the height now chosen: no point is asked for, a panel may be over the page *)
    (if _area_measure() then _line_put(view, !_centre, !_found_cross) else ())
  else _first_line(view)
end

(* The ruler put on the first line, if it is still waiting for one *)
fn _retry_now (): void =
  if !_pending then let
      val view = !_view
    in if _drawn(view) then _first_line(view) else !_pending := false end
  else ()

(* A moment after a panel closed, so the page is laid out and hit by points again *)
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

(* Whether x, y is on the band: along the lines' stacking within its reach, and across within the area *)
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

(* The pointer that is dragging the ruler, or -1 *)
#define NO_DRAG ~1
val _drag_id = ref<int>(NO_DRAG)

implement ruler_pointer (kind, id, x, y, pointer_type) = let
  val view = !_view
  val px = x / 16
  val py = y / 16
in
  if kind = 0 then
    (* a finger or a pen goes down on the band of a page turned in pages: it drags the band, which a
       mouse does not (its drag selects text) and a scrolled page does not (its drag scrolls) *)
    (if pointer_type = 1 then false
     else if !_drag_id <> NO_DRAG then false
     else if ~(_drawn(view)) then false
     else (case+ view of
       | RulerScrolled() => false
       | RulerNone() => false
       | RulerPaged() => if _area_measure() then (if _on_band(view, px, py) then let val () = !_drag_id := id in true end else false) else false
       | RulerPagedBack() => if _area_measure() then (if _on_band(view, px, py) then let val () = !_drag_id := id in true end else false) else false
       | RulerDownRight() => if _area_measure() then (if _on_band(view, px, py) then let val () = !_drag_id := id in true end else false) else false
       | RulerDownLeft() => if _area_measure() then (if _on_band(view, px, py) then let val () = !_drag_id := id in true end else false) else false))
  else if kind = 1 then
    (if !_drag_id <> id then false
     else let val _ = _place_at(view, px, py) in true end)
  else if kind = 2 || kind = 3 then
    (if !_drag_id <> id then false
     else let val () = !_drag_id := NO_DRAG in true end)
  else if kind = 5 then let val () = !_drag_id := NO_DRAG in false end
  else false
end

end
