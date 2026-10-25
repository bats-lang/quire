#include "share/atspre_staload.hats"
(* src/fields.bats STRB, copied: see gen_guards.py.
   Probe: every guard of STRB_mk holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

dataprop STRB(bytes, bytes) =
  | {len:int | 0 <= len; len < 256}{text:bytes} STRB_mk(text, bcons(len, text)) of LEN(text, len)

prfn satisfiable_strb_mk {len:int | 0 <= len; len < 256}{text:bytes} (): [1 == 2] void = ()
