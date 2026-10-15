(* The CRC of an array's bytes is the complement of the register after them *)
fn _static_crc_complemented {lb:agz}{n:pos}{cs:$A.cells} (cells_len: $A.CLEN(cs, n) | bytes: !$A.cborrow(lb, n, cs), n: int n)
  : [octets:bytes][high,low:nat | high < 65536; low < 65536]
    (HOLDS(cs, 0, octets, n), CRCFROM(65535, 65535, octets, 65535 - high, 65535 - low) | @(int high, int low)) =
  crc_of_cborrow(cells_len | bytes, n)
