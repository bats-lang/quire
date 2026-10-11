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

#pub stadef BUDGET = 60000

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
  | AlignSelf | JustifyContent | Gap | Order
  | Padding | PaddingTop | PaddingBottom | PaddingLeft | PaddingRight
  | Margin | MarginTop | MarginBottom | MarginLeft | MarginRight | MarginBlock | MarginInline
  | Width | MaxWidth | MinWidth | Height | MaxHeight | MinHeight | BoxSizing
  | FontFamily | FontSize | FontWeight | FontStyle | Font | LineHeight
  | LetterSpacing | TextTransform | TextAlign | TextOverflow | TextDecoration
  | WhiteSpace | Hyphens | Direction | WritingMode | TextCombineUpright | OverflowWrap
  | Overflow | OverflowX | Position | Top | Bottom | Left | Right | Inset
  | ZIndex | Cursor | PointerEvents | TouchAction | ObjectFit
  | BorderRadius | BorderCollapse | BoxShadow | Outline | OutlineOffset
  | ColumnFill | ColumnGap | ColumnWidth | BreakAfter | BreakInside | GridTemplate | AspectRatio
  | Appearance | ContainerType | UserSelect | Transition | Visibility | GridArea
  (* the reader's own variables: the page's top and bottom paddings and
     the running footer's place, each given once (reader_rules) *)
  | PageTopVariable | PageBottomVariable | FooterBottomVariable | FooterHeightVariable

fn _property_name (property: prop): [length:pos | length <= 16] string length =
  case+ property of
  | Display() => "display" | FlexDirection() => "flex-direction" | Flex() => "flex"
  | FlexWrap() => "flex-wrap" | FlexBasis() => "flex-basis" | AlignItems() => "align-items"
  | AlignSelf() => "align-self" | JustifyContent() => "justify-content" | Gap() => "gap"
  | Order() => "order" | Padding() => "padding" | PaddingTop() => "padding-top"
  | PaddingBottom() => "padding-bottom" | PaddingLeft() => "padding-left"
  | PaddingRight() => "padding-right" | Margin() => "margin" | MarginTop() => "margin-top"
  | MarginBottom() => "margin-bottom" | MarginLeft() => "margin-left"
  | MarginRight() => "margin-right" | MarginBlock() => "margin-block"
  | MarginInline() => "margin-inline" | Width() => "width" | MaxWidth() => "max-width"
  | MinWidth() => "min-width" | Height() => "height" | MaxHeight() => "max-height"
  | MinHeight() => "min-height" | BoxSizing() => "box-sizing" | FontFamily() => "font-family"
  | FontSize() => "font-size" | FontWeight() => "font-weight" | FontStyle() => "font-style"
  | Font() => "font" | LineHeight() => "line-height" | LetterSpacing() => "letter-spacing"
  | TextTransform() => "text-transform" | TextAlign() => "text-align"
  | TextOverflow() => "text-overflow" | TextDecoration() => "text-decoration"
  | WhiteSpace() => "white-space" | Hyphens() => "hyphens" | Direction() => "direction"
  | WritingMode() => "writing-mode" | TextCombineUpright() => "text-combine-upright" | OverflowWrap() => "overflow-wrap"
  | Overflow() => "overflow" | OverflowX() => "overflow-x" | Position() => "position"
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
  | GridArea() => "grid-area"
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
   The spacing scale (#331): Material's grid (8 px between and around
   components, 4 px within them; 16 px a compact screen's margins and a
   list item's insets, 24 px a dialog's), one length a step. The
   paddings, margins and gaps of the screens, sheets, menus and dialogs
   are written from it (spaced, spaced_pair), not chosen rule by rule.
   A step is indexed by its length, so a rule can be asked to prove a
   length at least the least inset (#332 builds on it)
   ============================================================ *)

#pub datatype space(int) =
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
  | SpaceTight() => "4px"
  | SpaceSmall() => "8px"
  | SpaceMedium() => "12px"
  | SpaceLarge() => "16px"
  | SpaceExtraLarge() => "24px"

(* prop:<step>; *)
#pub fn spaced {left:nat | left >= 22}{media:bool}{length:int}
  (sheet: sheet(left, media, true), property: prop, step: space(length)): [after:nat | after >= left - 22] sheet(after, media, true)

implement spaced (sheet, property, step) =
  lay(sheet, property, space_length(step))

(* prop:<block> <inline>; (the top and bottom, then the sides) *)
#pub fn spaced_pair {left:nat | left >= 28}{media:bool}{block,inline:int}
  (sheet: sheet(left, media, true), property: prop, block: space(block), inline: space(inline)): [after:nat | after >= left - 28] sheet(after, media, true)

implement spaced_pair (sheet, property, block, inline) = let
  val () = raw(sheet, _property_name(property))
  val () = raw(sheet, ":")
  val () = raw(sheet, space_length(block))
  val () = raw(sheet, " ")
  val () = raw(sheet, space_length(inline))
  val () = raw(sheet, ";")
in sheet end

end
