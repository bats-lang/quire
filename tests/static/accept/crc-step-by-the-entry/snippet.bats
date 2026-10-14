(* The byte step by the table entry of the byte xored in *)
prfn _static_step_by_the_entry {high,low,octet:nat | high < 65536; low < 65536; octet < 256}
  {high_upper,high_lower,low_upper,low_lower:nat | high == 256*high_upper + high_lower; low == 256*low_upper + low_lower; high_lower < 256; low_lower < 256}
  {index,table_high,table_low,next_high,next_low:nat}
  (index_xor: $AR.XOR(low_lower, octet, index), entry: BSTEP(0, 0, index, table_high, table_low),
   high_xor: $AR.XOR(high_upper, table_high, next_high), low_xor: $AR.XOR(low_upper + 256*high_lower, table_low, next_low))
  : BSTEP(high, low, octet, next_high, next_low) =
  bstep_by_table{high,low,octet}{high_upper,high_lower,low_upper,low_lower}(index_xor, entry, high_xor, low_xor)
