(* The table's last clip: its count less one *)
fn _static_last {count:pos} (table: !clip_table(count), count: int count): Int = clip_begin(table, count - 1)
