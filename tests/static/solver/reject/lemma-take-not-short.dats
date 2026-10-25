#include "share/atspre_staload.hats"
(* quire src/bytes.bats take_not_short, _take_not_short, copied: see gen_lemmas.py.
   False variant: octets short of count + 1 bytes can have count bytes to take *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop TAKE(int, bytes, bytes, bytes) =
  | {octets:bytes} TAKE_zero(0, octets, bnil(), octets)
  | {count:nat}{octet:int}{octets,taken,rest:bytes} TAKE_succ(count+1, bcons(octet, octets), bcons(octet, taken), rest) of TAKE(count, octets, taken, rest)

dataprop SHORT(int, bytes) =
  | {count:pos} SHORT_nil(count, bnil())
  | {count:nat}{octet:int}{octets:bytes} SHORT_succ(count+1, bcons(octet, octets)) of SHORT(count, octets)

dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

extern prfun take_not_short {count:nat}{octets,taken,rest:bytes} (TAKE(count, octets, taken, rest), SHORT(count + 1, octets)): FALSEP()

prfun _take_not_short {count:nat}{octets,taken,rest:bytes} .<count>.
  (take_proof: TAKE(count, octets, taken, rest), short_proof: SHORT(count + 1, octets)): FALSEP() =
  case+ take_proof of
  | TAKE_zero() => (case+ short_proof of SHORT_nil() =/=> ())
  | TAKE_succ(take_rest_proof) => (case+ short_proof of SHORT_succ(short_rest_proof) => _take_not_short(take_rest_proof, short_rest_proof))

primplement take_not_short {count}{octets,taken,rest} (take_proof, short_proof) = _take_not_short(take_proof, short_proof)
