(* The CRC of an array's bytes claimed to be the register after them, not its complement *)
prfn _static_crc_not_complemented {cs:$A.cells}{n:nat}{octets:bytes}{high,low:nat}
  (held: HOLDS(cs, 0, octets, n), done: CRCFROM(65535, 65535, octets, 65535 - high, 65535 - low)): CRCFROM(65535, 65535, octets, high, low) =
  done
