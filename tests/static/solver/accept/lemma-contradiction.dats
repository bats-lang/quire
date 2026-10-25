#include "share/atspre_staload.hats"
(* quire src/bytes.bats contradiction, copied: see gen_lemmas.py.
   Control, the same text as reject/lemma-contradiction.dats unchanged *)
dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

extern prfun contradiction {impossible:int | impossible < 0; impossible > 0} (): FALSEP()

primplement contradiction {impossible} () = FALSEP_mk{impossible}()
