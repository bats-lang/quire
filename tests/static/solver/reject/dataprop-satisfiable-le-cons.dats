#include "share/atspre_staload.hats"
(* src/bytes.bats LE, copied: see gen_guards.py.
   Probe: every guard of LE_cons holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)

prfn satisfiable_le_cons {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes} (): [1 == 2] void = ()
