#include "share/atspre_staload.hats"
datasort bytes = bnil of () | bcons of (int, bytes)
dataprop APPEND(bytes, bytes, bytes) =
  | {back:bytes} APPEND_nil(bnil(), back, back)
  | {octet:int}{front,back,joined:bytes} APPEND_cons(bcons(octet, front), back, bcons(octet, joined)) of APPEND(front, back, joined)
dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)
dataprop EQI(int, int) = | {same:int} EQI_refl(same, same)
dataprop EQB(bytes, bytes) = | {same:bytes} EQB_refl(same, same)
dataprop FALSEP() = | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()
dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)
dataprop LES(int, int, bytes) =
  | {low_byte:int | 0 <= low_byte; low_byte < 128} LES_last(1, low_byte, bcons(low_byte, bnil()))
  | {low_byte:int | 128 <= low_byte; low_byte < 256} LES_last_neg(1, low_byte - 256, bcons(low_byte, bnil()))
prfn rot {h:nat | h < 65536}{r:int | r == h / 256 + 256 * (h mod 256)} (): [r / 256 == h mod 256 && r mod 256 == h / 256] void = ()
