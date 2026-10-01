fn _rows {i:nat} (i: int i): void = let val @(a, n) = nid_make("toc-row", i) in ui_add_n("bats-root", a, n, TDiv) end
fn _other (): void = ui_el("bats-root", "toc-row12", TDiv, "a")
