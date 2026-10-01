(* The clip at the table's count: one past its last *)
fn _static_past_end {count:pos} (table: !clip_table(count), count: int count): Int = clip_begin(table, count)
