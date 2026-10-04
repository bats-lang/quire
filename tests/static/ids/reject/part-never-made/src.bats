#pub datatype place = InOne | InOther
#pub datatype part = Row | Label

fn row_part_id (where: place, which: part): string =
  case+ where of
  | InOne() => (case+ which of Row() => "one-row" | Label() => "one-label")
  | InOther() => (case+ which of Row() => "other-row" | Label() => "other-label")

fn _rows (where: place): void = ui_el("bats-root", row_part_id(where, Row()), TDiv, "srow")

fn _shown (): void = ui_show(row_part_id(InOne(), Label()), true)
