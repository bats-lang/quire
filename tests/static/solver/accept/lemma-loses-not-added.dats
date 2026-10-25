#include "share/atspre_staload.hats"
(* quire src/schema.bats _loses_not_added, copied: see gen_lemmas.py.
   Control, the same text as reject/lemma-loses-not-added.dats unchanged *)
datasort mode =
  | m_req of ()                                                            
  | m_opt of ()                                                                                             
  | m_added of ()                                                                                                       

dataprop LOSES(mode) =
  | LOSES_req(m_req())
  | LOSES_opt(m_opt())

dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

prfn _loses_not_added (needed: LOSES(m_added())): FALSEP() =
  case+ needed of
  | LOSES_req() =/=> ()
  | LOSES_opt() =/=> ()
