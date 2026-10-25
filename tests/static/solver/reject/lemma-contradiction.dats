#include "share/atspre_staload.hats"
(* quire src/bytes.bats contradiction, copied: see gen_lemmas.py.
   False variant: a FALSEP made at a value only below zero: the guard that makes it unbuildable is dropped *)
dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

extern prfun contradiction {impossible:int | impossible < 0} (): FALSEP()

primplement contradiction {impossible} () = FALSEP_mk{impossible}()
