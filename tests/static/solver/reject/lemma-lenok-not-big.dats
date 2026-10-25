#include "share/atspre_staload.hats"
(* quire src/chunk.bats lenok_not_big, copied: see gen_lemmas.py.
   False variant: a length with a third byte of 15 and no fourth is both small and big *)
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

dataprop LENBIG(bytes) =
  | {length_low,length_middle,length_high,length_top:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 256; 0 <= length_top; length_top < 256; length_top > 0 || length_high >= 15}
    LENBIG_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(length_top, bnil())))))

dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

extern prfun lenok_not_big {lenb:bytes}{size:nat} (LENOK(lenb, size), LENBIG(lenb)): FALSEP()

primplement lenok_not_big {lenb}{size} (small, big) =
  case+ small of
  | LENOK_mk(_) => (case+ big of LENBIG_mk() =/=> ())
