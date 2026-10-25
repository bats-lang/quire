#include "share/atspre_staload.hats"
(* quire src/fields.bats STRB, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

dataprop STRB(bytes, bytes) =
  | {len:int | 0 <= len; len < 256}{text:bytes} STRB_mk(text, bcons(len, text)) of LEN(text, len)

prfn control_strb_mk {len:int | 0 <= len; len < 256}{text:bytes} (premise1: LEN(text, len)): STRB(text, bcons(len, text)) = STRB_mk{len}{text}(premise1)
