(* An element in two places: each place's id of each part from one
   *_part_id function, made at one call, directly or through a helper
   that passes a part parameter on *)
#pub datatype place = InOne | InOther
#pub datatype part = Row | Label

fn row_part_id (where: place, which: part): string =
  case+ where of
  | InOne() => (case+ which of Row() => "one-row" | Label() => "one-label")
  | InOther() => (case+ which of Row() => "other-row" | Label() => "other-label")

fn _label (where: place, which: part): void = ui_el(row_part_id(where, Row()), row_part_id(where, which), TSpan, "slabel")

fn _rows (where: place): void = let
  val () = ui_el("bats-root", row_part_id(where, Row()), TDiv, "srow")
in _label(where, Label()) end

fn _shown (): void = ui_show(row_part_id(InOther(), Label()), true)
