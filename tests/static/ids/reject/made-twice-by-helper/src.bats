fn _row {nr:pos | nr < 256} (rid: string nr): void = ui_el("bats-root", rid, TDiv, "irow")
fn _one (): void = _row("size-row")
fn _two (): void = _row("size-row")
