#include "share/atspre_staload.hats"
(* quire src/bytes.bats LE, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)

prfn control_le_cons {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes} (premise1: LE(width, rest_value, octets)): LE(width+1, octet + 256*rest_value, bcons(octet, octets)) = LE_cons{width,rest_value}{octet}{octets}(premise1)
