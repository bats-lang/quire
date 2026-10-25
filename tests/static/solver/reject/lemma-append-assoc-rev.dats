#include "share/atspre_staload.hats"
(* quire src/bytes.bats append_assoc_rev, _append_assoc_rev, copied: see gen_lemmas.py.
   False variant: second is not after first in first_second *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop APPEND(bytes, bytes, bytes) =
  | {back:bytes} APPEND_nil(bnil(), back, back)
  | {octet:int}{front,back,joined:bytes} APPEND_cons(bcons(octet, front), back, bcons(octet, joined)) of APPEND(front, back, joined)

extern prfun append_assoc_rev {first,second,third,second_third,all:bytes}
  (APPEND(second, third, second_third), APPEND(first, second_third, all))
  : [first_second:bytes] (APPEND(second, first, first_second), APPEND(first_second, third, all))

prfun _append_assoc_rev {first,second,third,second_third,all:bytes} .<first>.
  (second_proof: APPEND(second, third, second_third), first_proof: APPEND(first, second_third, all))
  : [first_second:bytes] (APPEND(second, first, first_second), APPEND(first_second, third, all)) =
  case+ first_proof of
  | APPEND_nil() => (APPEND_nil(), second_proof)
  | APPEND_cons(first_rest_proof) => let
      prval (first_second_proof, all_proof) = _append_assoc_rev(second_proof, first_rest_proof)
    in (APPEND_cons(first_second_proof), APPEND_cons(all_proof)) end

primplement append_assoc_rev {first,second,third,second_third,all} (second_proof, first_proof) =
  _append_assoc_rev(second_proof, first_proof)
