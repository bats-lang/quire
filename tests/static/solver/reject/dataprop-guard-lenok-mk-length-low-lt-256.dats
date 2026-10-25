#include "share/atspre_staload.hats"
(* quire src/chunk.bats LENOK, copied: see gen_guards.py.
   False variant: the guard atom `length_low < 256` of LENOK_mk shifted by 1: `length_low < (256) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)

dataprop LENOK(bytes, int) =
  | {length_low,length_middle,length_high:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 16}{size:nat}
    LENOK_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(0, bnil())))), size)
    of LE(3, size, bcons(length_low, bcons(length_middle, bcons(length_high, bnil()))))

prfn probe_length_low_lt_256 {length_low,length_middle,length_high:int | 0 <= length_low; length_low < (256) + 1; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 16}{size:nat} (premise1: LE(3, size, bcons(length_low, bcons(length_middle, bcons(length_high, bnil()))))): LENOK(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(0, bnil())))), size) = LENOK_mk{length_low,length_middle,length_high}{size}(premise1)
