(* sheet -- the stylesheet as it is written: a builder with a budget of
   bytes left, so the whole sheet is proven to fit the style element
   (under 65536 bytes), and whether a rule or an @media block is open;
   the rules and their layout declarations; and the spacing scale.
   Nothing here names a colour: the declarations that do are in
   declarations.bats, with the proofs they need. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use builder as B
staload CT = "css/src/contrast.sats"

(* ============================================================
   The sheet: a builder with a budget of bytes left, so the whole
   sheet is proven to fit the style element (under 65536 bytes); and
   whether a rule or an @media block is open
   ============================================================ *)

#pub stadef BUDGET = 65100

(* sheet(left, media, open): left bytes left; whether an @media block is
   open, and whether a rule is *)
#pub datavtype sheet(int, bool, bool) =
  | {written,left:nat | written + left <= BUDGET}{media,open:bool} Sheet(left, media, open) of ($B.builder(written))


(* Bytes a selector or layout value may not hold: none of them can end
   a declaration or a rule, or make one !important *)
fn _is_plain {byte_value:nat | byte_value < 256} (byte_value: int byte_value): bool =
  byte_value <> 59 && byte_value <> 123 && byte_value <> 125 && byte_value <> 33

fun _put_plain {length:nat}{i:nat | i <= length}{written:nat | written + length - i <= BUDGET} .<length - i>.
  (builder: !$B.builder(written) >> [written_after:nat | written <= written_after; written_after <= written + length - i] $B.builder(written_after),
   text: string length, text_len: int length, i: int i): void =
  if i >= text_len then ()
  else let
    val code = char2int1(string_get_at(text, i))
    val byte_value = (if code >= 0 then (if code < 256 then code else 32) else 32): [byte_value:nat | byte_value < 256] int byte_value
  in
    if _is_plain(byte_value) then let val () = $B.put_char(builder, byte_value) in _put_plain(builder, text, text_len, i + 1) end
    else _put_plain(builder, text, text_len, i + 1)
  end

(* text, with any of ; { } ! dropped *)
#pub fn plain {left:nat}{media,open:bool}{length:nat | length <= left}
  (sheet: !sheet(left, media, open) >> sheet(left - length, media, open), text: string length): void

implement plain (sheet, text) = let
  val+ @Sheet(builder) = sheet
  val () = _put_plain(builder, text, g1u2i(string1_length(text)), 0)
  prval () = fold@(sheet)
in end

(* text as written: only the style modules' fixed text *)
#pub fn raw {left:nat}{media,open:bool}{length:nat | length <= left}
  (sheet: !sheet(left, media, open) >> sheet(left - length, media, open), text: string length): void

implement raw (sheet, text) = let
  val+ @Sheet(builder) = sheet
  val () = $B.bput(builder, text)
  prval () = fold@(sheet)
in end

#pub fn put_colour {left:nat | left >= 7}{media,open:bool}{colour:nat | colour < 16777216}
  (sheet: !sheet(left, media, open) >> sheet(left - 7, media, open), colour: int colour): void

implement put_colour (sheet, colour) = let
  val+ @Sheet(builder) = sheet
  val () = $CT.put_rgb(builder, colour)
  prval () = fold@(sheet)
in end

(* a small number (at most 11 bytes) *)
#pub fn put_number {left:nat | left >= 11}{media,open:bool}
  (sheet: sheet(left, media, open), value: int): sheet(left - 11, media, open)

implement put_number (sheet, value) = let
  val+ ~Sheet(builder) = sheet
  val () = $B.put_int(builder, value)
in Sheet(builder) end


(* ============================================================
   Rules
   ============================================================ *)

(* selector { *)
#pub fn rule {left:nat}{media:bool}{length:nat | length + 1 <= left}
  (sheet: sheet(left, media, false), selector: string length): sheet(left - length - 1, media, true)

implement rule (sheet, selector) = let
  val () = plain(sheet, selector)
  val () = raw(sheet, "{")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

(* } *)
#pub fn close {left:pos}{media:bool}
  (sheet: sheet(left, media, true)): sheet(left - 1, media, false)

implement close (sheet) = let
  val () = raw(sheet, "}")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

(* @media condition { *)
#pub fn media {left:nat}{length:nat | length + 8 <= left}
  (sheet: sheet(left, false, false), condition: string length): sheet(left - length - 8, true, false)

implement media (sheet, condition) = let
  val () = raw(sheet, "@media ")
  val () = plain(sheet, condition)
  val () = raw(sheet, "{")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

#pub fn media_end {left:pos} (sheet: sheet(left, true, false)): sheet(left - 1, false, false)

implement media_end (sheet) = let
  val () = raw(sheet, "}")
  val+ ~Sheet(builder) = sheet
in Sheet(builder) end

(* ============================================================
   Layout declarations: any value (plain), with the name of a property
   ============================================================ *)

#pub datatype prop =
  | Display | FlexDirection | Flex | FlexWrap | FlexBasis | AlignItems
  | AlignSelf | JustifyContent | JustifyItems | Order
  | Width | MaxWidth | MinWidth | Height | MinHeight | BoxSizing
  | FontFamily | FontSize | FontWeight | FontStyle | Font | LineHeight
  | LetterSpacing | TextTransform | TextAlign | TextOverflow | TextDecoration
  | WhiteSpace | Hyphens | Direction | WritingMode | OverflowWrap
  | OverflowX | Position | Top | Bottom | Left | Right | Inset
  | ZIndex | Cursor | PointerEvents | TouchAction | ObjectFit
  | BorderRadius | BorderCollapse | BoxShadow | Outline | OutlineOffset
  | ColumnFill | ColumnGap | ColumnWidth | BreakAfter | BreakInside | GridTemplate | AspectRatio
  | Appearance | ContainerType | UserSelect | Transition | Visibility | GridArea | Zoom | ClipPath | WillChange | TextSizeAdjust
  (* the reader's own variables: the page's top and bottom paddings and
     the running footer's place, each given once (reader_rules) *)
  | PageTopVariable | PageBottomVariable | FooterBottomVariable | FooterHeightVariable

fn _property_name (property: prop): [length:pos | length <= 16] string length =
  case+ property of
  | Display() => "display" | FlexDirection() => "flex-direction" | Flex() => "flex"
  | FlexWrap() => "flex-wrap" | FlexBasis() => "flex-basis" | AlignItems() => "align-items"
  | AlignSelf() => "align-self" | JustifyContent() => "justify-content" | JustifyItems() => "justify-items"
  | Order() => "order" | Width() => "width" | MaxWidth() => "max-width"
  | MinWidth() => "min-width" | Height() => "height"
  | MinHeight() => "min-height" | BoxSizing() => "box-sizing" | FontFamily() => "font-family"
  | FontSize() => "font-size" | FontWeight() => "font-weight" | FontStyle() => "font-style"
  | Font() => "font" | LineHeight() => "line-height" | LetterSpacing() => "letter-spacing"
  | TextTransform() => "text-transform" | TextAlign() => "text-align"
  | TextOverflow() => "text-overflow" | TextDecoration() => "text-decoration"
  | WhiteSpace() => "white-space" | Hyphens() => "hyphens" | Direction() => "direction"
  | WritingMode() => "writing-mode" | OverflowWrap() => "overflow-wrap"
  | OverflowX() => "overflow-x" | Position() => "position"
  | Top() => "top" | Bottom() => "bottom" | Left() => "left" | Right() => "right"
  | Inset() => "inset" | ZIndex() => "z-index" | Cursor() => "cursor"
  | PointerEvents() => "pointer-events" | TouchAction() => "touch-action"
  | ObjectFit() => "object-fit" | BorderRadius() => "border-radius"
  | BorderCollapse() => "border-collapse" | BoxShadow() => "box-shadow"
  | Outline() => "outline" | OutlineOffset() => "outline-offset"
  | ColumnFill() => "column-fill" | ColumnGap() => "column-gap"
  | ColumnWidth() => "column-width" | BreakAfter() => "break-after"
  | BreakInside() => "break-inside" | Appearance() => "appearance" | ContainerType() => "container-type" | UserSelect() => "user-select"
  | Transition() => "transition" | Visibility() => "visibility"
  | GridTemplate() => "grid-template" | AspectRatio() => "aspect-ratio"
  | GridArea() => "grid-area" | Zoom() => "zoom" | ClipPath() => "clip-path" | WillChange() => "will-change" | TextSizeAdjust() => "text-size-adjust"
  | PageTopVariable() => "--page-top" | PageBottomVariable() => "--page-bottom"
  | FooterBottomVariable() => "--footer-bottom" | FooterHeightVariable() => "--footer-height"

(* prop:value; *)
#pub fn lay {left:nat}{media:bool}{value_len:nat | value_len + 18 <= left}
  (sheet: sheet(left, media, true), property: prop, value: string value_len): [after:nat | after >= left - value_len - 18] sheet(after, media, true)

implement lay (sheet, property, value) = let
  val () = raw(sheet, _property_name(property))
  val () = raw(sheet, ":")
  val () = plain(sheet, value)
  val () = raw(sheet, ";")
in sheet end


(* ============================================================
   Spacing (#331, #500): the paddings, margins and gaps, and the
   scrolling of a box and the height it is capped at, are written only
   here. Their properties are not in prop, so lay cannot write one: a
   rule's spacing is a step of the scale below, or a form that is not a
   step and is named for what it is (a safe-area inset, a pulled-out
   margin, room kept for a chevron, a typographic margin)
   ============================================================ *)

#pub datatype spacing_prop =
  | Gap
  | Padding | PaddingTop | PaddingBottom | PaddingLeft | PaddingRight
  | Margin | MarginTop | MarginBottom | MarginLeft | MarginRight | MarginBlock | MarginInline

fn _spacing_name (property: spacing_prop): [length:pos | length <= 14] string length =
  case+ property of
  | Gap() => "gap"
  | Padding() => "padding" | PaddingTop() => "padding-top" | PaddingBottom() => "padding-bottom"
  | PaddingLeft() => "padding-left" | PaddingRight() => "padding-right"
  | Margin() => "margin" | MarginTop() => "margin-top" | MarginBottom() => "margin-bottom"
  | MarginLeft() => "margin-left" | MarginRight() => "margin-right"
  | MarginBlock() => "margin-block" | MarginInline() => "margin-inline"

(* ============================================================
   The spacing scale (#331): Material's grid (8 px between and around
   components, 4 px within them; 16 px a compact screen's margins and a
   list item's insets, 24 px a dialog's), one length a step, and none.
   The paddings, margins and gaps of the screens, sheets, menus and
   dialogs are written from it (spaced, spaced_pair, spaced_safe,
   pulled), not chosen rule by rule. A step is indexed by its length, so
   a rule can be asked to prove a length at least the least inset (#332
   builds on it)
   ============================================================ *)

#pub datatype space(int) =
  | SpaceNone(0) of ()
  | SpaceTight(4) of ()
  | SpaceSmall(8) of ()
  | SpaceMedium(12) of ()
  | SpaceLarge(16) of ()
  | SpaceExtraLarge(24) of ()

(* The least a control keeps from its container's edges: Material's
   least space between two targets. The page gives it as --space-inset
   (spacing_rules), which the e2e layout walk checks every control against *)
#pub stadef SPACE_INSET = 8

(* The step that is the least inset: a step of another length does not
   type-check here *)
#pub fn space_inset (): space(SPACE_INSET)

implement space_inset () = SpaceSmall()

#pub fn space_length {length:int} (step: space(length)): [text_len:pos | text_len <= 4] string text_len

implement space_length (step) =
  case+ step of
  | SpaceNone() => "0"
  | SpaceTight() => "4px"
  | SpaceSmall() => "8px"
  | SpaceMedium() => "12px"
  | SpaceLarge() => "16px"
  | SpaceExtraLarge() => "24px"

(* A sheet over the page is a standard sheet (Material 3): the page stays
   in view while its controls are used. How much of the window it may
   cover is a share in dvh; SHEET_SHARE_MOST leaves the page at least
   40% (#379) *)
#pub stadef SHEET_SHARE_MOST = 60

#pub datatype sheet_share(int) =
  | ShareNote(45) of ()
  | ShareHalf(50) of ()
  | ShareMost(55) of ()

fn _share_length {share:int} (share: sheet_share(share)): [text_len:pos | text_len <= 5] string text_len =
  case+ share of
  | ShareNote() => "45dvh"
  | ShareHalf() => "50dvh"
  | ShareMost() => "55dvh"

(* max-height:<share>dvh;overflow:auto; the cap and the scrolling are
   written together, and a share over SHEET_SHARE_MOST does not
   type-check *)
#pub fn scrolls {left:nat | left >= 45}{media:bool}{share:int | share <= SHEET_SHARE_MOST}
  (sheet: sheet(left, media, true), share: sheet_share(share)): [after:nat | after >= left - 45] sheet(after, media, true)

implement scrolls (sheet, share) = let
  val () = raw(sheet, "max-height:")
  val () = raw(sheet, _share_length(share))
  val () = raw(sheet, ";overflow:auto;")
in sheet end

(* overflow:hidden; the box clips what lies outside it *)
#pub fn clips {left:nat | left >= 16}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 16] sheet(after, media, true)

implement clips (sheet) = let
  val () = raw(sheet, "overflow:hidden;")
in sheet end

(* overflow:auto; the box scrolls what lies outside it (a box whose
   height is not capped here; one that is, scrolls) *)
#pub fn scrolling {left:nat | left >= 16}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 16] sheet(after, media, true)

implement scrolling (sheet) = let
  val () = raw(sheet, "overflow:auto;")
in sheet end

(* The heights a box is capped at, apart from a sheet's share *)
#pub datatype height_cap =
  (* the reading area: the window less the page's top and bottom paddings *)
  | CapPageArea
  | CapWindow
  | CapContainer
  | CapCover

(* max-height:<cap>; *)
#pub fn capped {left:nat | left >= 64}{media:bool}
  (sheet: sheet(left, media, true), cap: height_cap): [after:nat | after >= left - 64] sheet(after, media, true)

implement capped (sheet, cap) = let
  val () = raw(sheet, "max-height:")
  val () = raw(sheet, (case+ cap of
    | CapPageArea() => "calc(100dvh - var(--page-top) - var(--page-bottom))"
    | CapWindow() => "100dvh"
    | CapContainer() => "100cqh"
    | CapCover() => "300px"): [text_len:pos | text_len <= 51] string text_len)
  val () = raw(sheet, ";")
in sheet end

(* max-height:calc(<the reading area> / var(--image-zoom,1)); a picture's
   largest height, divided by its zoom, which multiplies lengths *)
#pub fn capped_zoomed {left:nat | left >= 96}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 96] sheet(after, media, true)

implement capped_zoomed (sheet) = let
  val () = raw(sheet, "max-height:calc((100dvh - var(--page-top) - var(--page-bottom)) / var(--image-zoom,1));")
in sheet end

(* prop:<step>; *)
#pub fn spaced {left:nat | left >= 22}{media:bool}{length:int}
  (sheet: sheet(left, media, true), property: spacing_prop, step: space(length)): [after:nat | after >= left - 22] sheet(after, media, true)

implement spaced (sheet, property, step) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":")
  val () = raw(sheet, space_length(step))
  val () = raw(sheet, ";")
in sheet end

(* prop:<block> <inline>; (the top and bottom, then the sides) *)
#pub fn spaced_pair {left:nat | left >= 28}{media:bool}{block,inline:int}
  (sheet: sheet(left, media, true), property: spacing_prop, block: space(block), inline: space(inline)): [after:nat | after >= left - 28] sheet(after, media, true)

implement spaced_pair (sheet, property, block, inline) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":")
  val () = raw(sheet, space_length(block))
  val () = raw(sheet, " ")
  val () = raw(sheet, space_length(inline))
  val () = raw(sheet, ";")
in sheet end

(* The edge of the window a safe-area inset is on *)
#pub datatype safe_edge = SafeTop | SafeRight | SafeBottom | SafeLeft

fn _edge_name (edge: safe_edge): [length:pos | length <= 6] string length =
  case+ edge of
  | SafeTop() => "top" | SafeRight() => "right" | SafeBottom() => "bottom" | SafeLeft() => "left"

(* prop:max(<step>,var(--safe-<edge>)); the step, or the inset where it is
   larger (the step none: the inset alone) *)
#pub fn spaced_safe {left:nat | left >= 52}{media:bool}{length:int}
  (sheet: sheet(left, media, true), property: spacing_prop, step: space(length), edge: safe_edge): [after:nat | after >= left - 52] sheet(after, media, true)

implement spaced_safe (sheet, property, step, edge) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":")
  val () = raw(sheet, (case+ step of SpaceNone() => "var(--safe-" | _ => "max("): [text_len:pos | text_len <= 11] string text_len)
  val () = raw(sheet, (case+ step of SpaceNone() => "" | _ => space_length(step)): [text_len:nat | text_len <= 4] string text_len)
  val () = raw(sheet, (case+ step of SpaceNone() => "" | _ => ",var(--safe-"): [text_len:nat | text_len <= 12] string text_len)
  val () = raw(sheet, _edge_name(edge))
  val () = raw(sheet, (case+ step of SpaceNone() => ")" | _ => "))"): [text_len:pos | text_len <= 2] string text_len)
  val () = raw(sheet, ";")
in sheet end

(* prop:-<step>; a margin pulled out over its neighbour (a sticky head
   that covers its container's padding, a thumb centred on its track) *)
#pub fn pulled {left:nat | left >= 22}{media:bool}{length:int}
  (sheet: sheet(left, media, true), property: spacing_prop, step: space(length)): [after:nat | after >= left - 22] sheet(after, media, true)

implement pulled (sheet, property, step) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":-")
  val () = raw(sheet, space_length(step))
  val () = raw(sheet, ";")
in sheet end

(* prop:auto; *)
#pub fn auto_margin {left:nat | left >= 22}{media:bool}
  (sheet: sheet(left, media, true), property: spacing_prop): [after:nat | after >= left - 22] sheet(after, media, true)

implement auto_margin (sheet, property) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":auto;")
in sheet end

(* margin:0 auto; a box centred in its container *)
#pub fn centred {left:nat | left >= 24}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 24] sheet(after, media, true)

implement centred (sheet) = let
  val () = raw(sheet, "margin:0 auto;")
in sheet end

(* A length of the book's text, in em: its blocks keep the space the
   reader's type gives them, which is not the interface's scale *)
#pub datatype prose_length =
  | ProseNone | ProseHalf | ProseParagraph | ProseOne | ProseOneAndHalf | ProseTwo | ProseAuto

fn _prose_text (length: prose_length): [text_len:pos | text_len <= 5] string text_len =
  case+ length of
  | ProseNone() => "0" | ProseHalf() => ".5em" | ProseParagraph() => ".8em" | ProseOne() => "1em"
  | ProseOneAndHalf() => "1.5em" | ProseTwo() => "2em" | ProseAuto() => "auto"

(* prop:<block> <inline>; in the book's em *)
#pub fn prose_margin {left:nat | left >= 28}{media:bool}
  (sheet: sheet(left, media, true), property: spacing_prop, block: prose_length, inline: prose_length): [after:nat | after >= left - 28] sheet(after, media, true)

implement prose_margin (sheet, property, block, inline) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":")
  val () = raw(sheet, _prose_text(block))
  val () = raw(sheet, " ")
  val () = raw(sheet, _prose_text(inline))
  val () = raw(sheet, ";")
in sheet end

(* Room a padding keeps for something drawn in it: a chevron, a page
   number, an outline's indent, a menu's check mark or a row's chevron *)
#pub datatype room =
  | RoomChevron | RoomPageNumber | RoomOutlineFirst | RoomOutlineSecond | RoomOutlineThird | RoomIndicator
  (* a screen's last card scrolls clear of the Undo toast *)
  | RoomToastClear

fn _room_length (room: room): [text_len:pos | text_len <= 5] string text_len =
  case+ room of
  | RoomChevron() => "32px" | RoomPageNumber() => "72px" | RoomOutlineFirst() => "30px"
  | RoomOutlineSecond() => "46px" | RoomOutlineThird() => "62px" | RoomIndicator() => "40px"
  | RoomToastClear() => "176px"

(* prop:<room>; *)
#pub fn reserve {left:nat | left >= 22}{media:bool}
  (sheet: sheet(left, media, true), property: spacing_prop, room: room): [after:nat | after >= left - 22] sheet(after, media, true)

implement reserve (sheet, property, room) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":")
  val () = raw(sheet, _room_length(room))
  val () = raw(sheet, ";")
in sheet end

(* prop:max(<room>,var(--safe-<edge>)); the room, or the inset where it is larger *)
#pub fn reserve_safe {left:nat | left >= 52}{media:bool}
  (sheet: sheet(left, media, true), property: spacing_prop, room: room, edge: safe_edge): [after:nat | after >= left - 52] sheet(after, media, true)

implement reserve_safe (sheet, property, room, edge) = let
  val () = raw(sheet, _spacing_name(property))
  val () = raw(sheet, ":max(")
  val () = raw(sheet, _room_length(room))
  val () = raw(sheet, ",var(--safe-")
  val () = raw(sheet, _edge_name(edge))
  val () = raw(sheet, "));")
in sheet end

(* The edges the reader's page is kept in from, by its own variables *)
#pub datatype page_edge = PageTopEdge | PageBottomEdge

(* padding-<edge>:var(--page-<edge>); the reading area's own padding *)
#pub fn page_padding {left:nat | left >= 36}{media:bool}
  (sheet: sheet(left, media, true), edge: page_edge): [after:nat | after >= left - 36] sheet(after, media, true)

implement page_padding (sheet, edge) = let
  val () = raw(sheet, (case+ edge of
    | PageTopEdge() => "padding-top:var(--page-top);"
    | PageBottomEdge() => "padding-bottom:var(--page-bottom);"): [text_len:pos | text_len <= 34] string text_len)
in sheet end

(* margin-<side>:env(safe-area-inset-<side>); the reader's page keeps out
   of the screen's cutout at its sides *)
#pub datatype area_side = AreaLeft | AreaRight

#pub fn safe_area_margin {left:nat | left >= 40}{media:bool}
  (sheet: sheet(left, media, true), side: area_side): [after:nat | after >= left - 40] sheet(after, media, true)

implement safe_area_margin (sheet, side) = let
  val () = raw(sheet, (case+ side of
    | AreaLeft() => "margin-left:env(safe-area-inset-left);"
    | AreaRight() => "margin-right:env(safe-area-inset-right);"): [text_len:pos | text_len <= 40] string text_len)
in sheet end

(* margin-top:15vh; the empty library's message sits a sixth of the way
   down the window *)
#pub fn placed_down {left:nat | left >= 16}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 16] sheet(after, media, true)

implement placed_down (sheet) = let
  val () = raw(sheet, "margin-top:15vh;")
in sheet end

(* margin:-1px;overflow:hidden; a box read out by assistive technology and
   not seen *)
#pub fn read_out_only {left:nat | left >= 28}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 28] sheet(after, media, true)

implement read_out_only (sheet) = let
  val () = raw(sheet, "margin:-1px;overflow:hidden;")
in sheet end

end
