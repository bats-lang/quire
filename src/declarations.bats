(* declarations -- the declarations that name a colour, each under its proof

   A colour is set only through these: text with the ground it is drawn
   on (surf, with SURF), a ground with no text (fill, tint, veil), a
   border or a control's accent in a role (line, accent, underline, with
   EDGEP where a control is identified by it). The sheet's screens are
   written from these and the layout declarations of sheet.bats. *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "palette.sats"
staload "sheet.sats"

(* ============================================================
   Declarations. Layout properties take any value (plain); the
   properties the guarantees rest on have no such door: colour and
   background come only from surf, fill and veil, borders of text
   fields only from the base rules, opacity only as 0.
   ============================================================ *)

(* var(--<role>) *)
#pub fn role_variable {left:nat | left >= 16}{media,open:bool}{role:colour_role}
  (sheet: !sheet(left, media, open) >> [after:nat | after >= left - 16] sheet(after, media, open), role: role_value(role)): void

implement role_variable (sheet, role) = let
  val () = raw(sheet, "var(--")
  val () = raw(sheet, role_name(role))
in raw(sheet, ")") end

(* color:var(--text);background-color:var(--ground); : text on ground,
   proven *)
#pub fn surf {left:nat | left >= 60}{media:bool}{text,ground:colour_role}
  (legible: SURF(text, ground) | sheet: sheet(left, media, true), text: role_value(text), ground: role_value(ground)): [after:nat | after >= left - 60] sheet(after, media, true)

implement surf (legible | sheet, text, ground) = let
  val () = raw(sheet, "color:")
  val () = role_variable(sheet, text)
  val () = raw(sheet, ";background-color:")
  val () = role_variable(sheet, ground)
  val () = raw(sheet, ";")
in sheet end

(* A ground with no text: a bar, a track, a placeholder *)
#pub fn fill {left:nat | left >= 50}{media:bool}{ground:colour_role}
  (sheet: sheet(left, media, true), ground: role_value(ground)): [after:nat | after >= left - 50] sheet(after, media, true)

implement fill (sheet, ground) = let
  val () = raw(sheet, "background-color:")
  val () = role_variable(sheet, ground)
  val () = raw(sheet, ";font-size:0;")
in sheet end

(* A ground of white or black at alpha percent, with no text *)
#pub fn tint {left:nat | left >= 60}{media:bool}{alpha:nat | alpha <= 100}
  (sheet: sheet(left, media, true), white: bool, alpha: int alpha): [after:nat | after >= left - 60] sheet(after, media, true)

implement tint (sheet, white, alpha) = let
  val () = raw(sheet, (if white then "background-color:rgba(255,255,255," else "background-color:rgba(0,0,0,"): [length:pos | length <= 34] string length)
  val sheet = put_number(sheet, alpha)
  val () = raw(sheet, "%);font-size:0;")
in sheet end

(* The veil behind a menu or dialog: dark, and its own text (none)
   transparent, so only what sits on it in a proven surface shows *)
#pub fn veil {left:nat | left >= 60}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 60] sheet(after, media, true)

implement veil (sheet) =
  let val () = raw(sheet, "background-color:rgba(0,0,0,.5);color:transparent;") in sheet end

(* A decorative line in a role (a card's outline, a separator): not
   what identifies a control, which the base rules give text fields *)
#pub datatype side = AllSides | TopSide | BottomSide | LeftSide

#pub fn line {left:nat | left >= 60}{media:bool}{width:pos | width <= 9}{role:colour_role}
  (sheet: sheet(left, media, true), side: side, width: int width, role: role_value(role)): [after:nat | after >= left - 60] sheet(after, media, true)

implement line (sheet, side, width, role) = let
  val () = raw(sheet, (case+ side of AllSides() => "border:" | TopSide() => "border-top:"
    | BottomSide() => "border-bottom:" | LeftSide() => "border-left:"): [length:pos | length <= 14] string length)
  val sheet = put_number(sheet, width)
  val () = raw(sheet, "px solid ")
  val () = role_variable(sheet, role)
  val () = raw(sheet, ";")
in sheet end

#pub fn no_line {left:nat | left >= 12}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 12] sheet(after, media, true)

implement no_line (sheet) =
  let val () = raw(sheet, "border:none;") in sheet end

(* A control's accent (a slider's fill and thumb) in role edge on
   ground *)
#pub fn accent {left:nat | left >= 40}{media:bool}{edge,ground:colour_role}
  (visible: EDGEP(edge, ground) | sheet: sheet(left, media, true), edge: role_value(edge), ground: role_value(ground)): [after:nat | after >= left - 40] sheet(after, media, true)

implement accent (visible | sheet, edge, ground) = let
  val () = raw(sheet, "accent-color:")
  val () = role_variable(sheet, edge)
  val () = raw(sheet, ";")
in sheet end

(* A chosen state's underline (a selected tab's) in role edge on ground:
   a 3px inset line along the foot, 3:1 against the ground (EDGEP, as an
   accent), so a chosen state is told apart by more than a tint
   (quire#358, WCAG 1.4.11; Material 3: an underline and a colour change
   on the active tab) *)
#pub fn underline {left:nat | left >= 48}{media:bool}{edge,ground:colour_role}
  (visible: EDGEP(edge, ground) | sheet: sheet(left, media, true), edge: role_value(edge), ground: role_value(ground)): [after:nat | after >= left - 48] sheet(after, media, true)

implement underline (visible | sheet, edge, ground) = let
  val () = raw(sheet, "box-shadow:inset 0 -3px 0 ")
  val () = role_variable(sheet, edge)
  val () = raw(sheet, ";")
in sheet end

(* translateX(-50%): the only transform, which moves and never scales *)
#pub fn centre_x {left:nat | left >= 32}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 32] sheet(after, media, true)

implement centre_x (sheet) =
  let val () = raw(sheet, "transform:translateX(-50%);") in sheet end

(* opacity 0: an invisible target over a visible one (a file input) *)
#pub fn invisible {left:nat | left >= 12}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 12] sheet(after, media, true)

implement invisible (sheet) =
  let val () = raw(sheet, "opacity:0;") in sheet end

end
