#include "share/atspre_staload.hats"
(* quire src/bytes.bats take_append, _take_append, copied: see gen_lemmas.py.
   False variant: what is taken is count long, not one more *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop TAKE(int, bytes, bytes, bytes) =
  | {octets:bytes} TAKE_zero(0, octets, bnil(), octets)
  | {count:nat}{octet:int}{octets,taken,rest:bytes} TAKE_succ(count+1, bcons(octet, octets), bcons(octet, taken), rest) of TAKE(count, octets, taken, rest)

dataprop APPEND(bytes, bytes, bytes) =
  | {back:bytes} APPEND_nil(bnil(), back, back)
  | {octet:int}{front,back,joined:bytes} APPEND_cons(bcons(octet, front), back, bcons(octet, joined)) of APPEND(front, back, joined)

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

extern prfun take_append {count:nat}{octets,taken,rest:bytes} (TAKE(count, octets, taken, rest)): (APPEND(taken, rest, octets), LEN(taken, count + 1))

prfun _take_append {count:nat}{octets,taken,rest:bytes} .<count>.
  (take_proof: TAKE(count, octets, taken, rest)): (APPEND(taken, rest, octets), LEN(taken, count + 1)) =
  case+ take_proof of
  | TAKE_zero() => (APPEND_nil(), LEN_nil())
  | TAKE_succ(rest_proof) => let
      prval (append_proof, len_proof) = _take_append(rest_proof)
    in (APPEND_cons(append_proof), LEN_cons(len_proof)) end

primplement take_append {count}{octets,taken,rest} (take_proof) = _take_append(take_proof)
