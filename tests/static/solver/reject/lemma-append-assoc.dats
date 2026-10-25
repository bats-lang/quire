#include "share/atspre_staload.hats"
(* quire src/bytes.bats append_assoc, _append_assoc, copied: see gen_lemmas.py.
   False variant: first is not after second_third in all *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop APPEND(bytes, bytes, bytes) =
  | {back:bytes} APPEND_nil(bnil(), back, back)
  | {octet:int}{front,back,joined:bytes} APPEND_cons(bcons(octet, front), back, bcons(octet, joined)) of APPEND(front, back, joined)

extern prfun append_assoc {first,second,first_second,third,all:bytes}
  (APPEND(first, second, first_second), APPEND(first_second, third, all))
  : [second_third:bytes] (APPEND(second, third, second_third), APPEND(second_third, first, all))

prfun _append_assoc {first,second,first_second,third,all:bytes} .<first>.
  (first_proof: APPEND(first, second, first_second), second_proof: APPEND(first_second, third, all))
  : [second_third:bytes] (APPEND(second, third, second_third), APPEND(second_third, first, all)) =
  case+ first_proof of
  | APPEND_nil() => (second_proof, APPEND_nil())
  | APPEND_cons(first_rest_proof) => (case+ second_proof of APPEND_cons(second_rest_proof) => let
      prval (second_third_proof, first_all_proof) = _append_assoc(first_rest_proof, second_rest_proof)
    in (second_third_proof, APPEND_cons(first_all_proof)) end)

primplement append_assoc {first,second,first_second,third,all} (first_proof, second_proof) =
  _append_assoc(first_proof, second_proof)
