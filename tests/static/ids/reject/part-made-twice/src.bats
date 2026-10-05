#pub datatype place = InOne | InOther
#pub datatype part = Row | Label

fn row_part_id (where: place, which: part): string =
  case+ where of
  | InOne() => (case+ which of Row() => "one-row" | Label() => "one-label")
  | InOther() => (case+ which of Row() => "other-row" | Label() => "other-label")

fn _label (where: place, which: part): void = ui_el(row_part_id(where, Row()), row_part_id(where, which), TSpan, "slabel")

fn _rows (where: place): void = let
  val () = ui_el("bats-root", row_part_id(where, Row()), TDiv, "srow")
  val () = _label(where, Label())
in _label(where, Label()) end
