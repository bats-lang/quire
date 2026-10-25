#include "share/atspre_staload.hats"
(* quire src/fields.bats falsep_eqfd, copied: see gen_lemmas.py.
   False variant: a FALSEP that can be built (guard shifted past zero) does not give any two results equal *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

datasort fvals =
  | fv_nil of ()
  | fv_i32 of (int, fvals)
  | fv_str of (bytes, fvals)

datasort fdres =
  | fd_ok of (fvals)
  | fd_bad of ()

dataprop FALSEP() =
  | {impossible:int | impossible < 2; impossible > 0} FALSEP_mk() of ()

dataprop EQFD(fdres, fdres) =
  | {result:fdres} EQFD_refl(result, result)

extern prfun falsep_eqfd {left_result,right_result:fdres} (FALSEP()): EQFD(left_result, right_result)

primplement falsep_eqfd {left_result,right_result} (falsity) = case+ falsity of FALSEP_mk() =/=> ()
