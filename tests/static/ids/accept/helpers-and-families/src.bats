fn _row {nr,nv:pos | nr < 256; nv < 256} (rid: string nr, vid: string nv): void = let
  val () = ui_el("bats-root", rid, TDiv, "irow")
in ui_add(rid, vid, TSpan) end
fn _rows {i:nat} (i: int i): void = let val @(a, n) = nid_make("toc-row", i) in ui_add_n("bats-root", a, n, TDiv) end
fn _info (): void = let
  val () = _row("size-row", "size-value")
  val () = ui_text("size-value", "12 pt")
  val () = ui_text("toc-row3", "Chapter 3")
in ui_show("pwa-anything", true) end
fn _click (t: int): int = _row_of(t, "toc-row")
