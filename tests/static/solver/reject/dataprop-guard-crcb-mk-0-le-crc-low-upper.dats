#include "share/atspre_staload.hats"
(* quire src/chunk.bats CRCB, copied: see gen_guards.py.
   False variant: the guard atom `0 <= crc_low_upper` of CRCB_mk shifted by 1: `0 <= (crc_low_upper) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)

dataprop CRCB(bytes, int, int) =
  | {crc_low_byte,crc_low_upper,crc_high_byte,crc_high_upper:int | 0 <= crc_low_byte; crc_low_byte < 256; 0 <= crc_low_upper; crc_low_upper < 256; 0 <= crc_high_byte; crc_high_byte < 256; 0 <= crc_high_upper; crc_high_upper < 256}{crc_high,crc_low:nat}
    CRCB_mk(bcons(crc_low_byte, bcons(crc_low_upper, bcons(crc_high_byte, bcons(crc_high_upper, bnil())))), crc_high, crc_low)
    of (LE(2, crc_low, bcons(crc_low_byte, bcons(crc_low_upper, bnil()))), LE(2, crc_high, bcons(crc_high_byte, bcons(crc_high_upper, bnil()))))

prfn probe_0_le_crc_low_upper {crc_low_byte,crc_low_upper,crc_high_byte,crc_high_upper:int | 0 <= crc_low_byte; crc_low_byte < 256; 0 <= (crc_low_upper) + 1; crc_low_upper < 256; 0 <= crc_high_byte; crc_high_byte < 256; 0 <= crc_high_upper; crc_high_upper < 256}{crc_high,crc_low:nat} (premise1: LE(2, crc_low, bcons(crc_low_byte, bcons(crc_low_upper, bnil()))), premise2: LE(2, crc_high, bcons(crc_high_byte, bcons(crc_high_upper, bnil())))): CRCB(bcons(crc_low_byte, bcons(crc_low_upper, bcons(crc_high_byte, bcons(crc_high_upper, bnil())))), crc_high, crc_low) = CRCB_mk{crc_low_byte,crc_low_upper,crc_high_byte,crc_high_upper}{crc_high,crc_low}(premise1, premise2)
