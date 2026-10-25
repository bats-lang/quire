#include "share/atspre_staload.hats"
(* quire src/seq.bats allgood_bad_false, copied: see gen_lemmas.py.
   False variant: a list that begins with a good chunk is all good *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

datasort pchunks =
  | pnil of ()
  | pgood of (bytes, bytes, pchunks)                           
  | pbad of (bytes, pchunks)                             

dataprop ALLGOOD(int, pchunks) =
  | ALLGOOD_nil(0, pnil())
  | {chunk_count:nat}{tag,data:bytes}{chunks:pchunks} ALLGOOD_cons(chunk_count+1, pgood(tag, data, chunks)) of ALLGOOD(chunk_count, chunks)

dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

prfn allgood_bad_false {chunk_count:nat}{tag:bytes}{chunks:pchunks} (good: ALLGOOD(chunk_count, pgood(tag, tag, chunks))): FALSEP() =
  case+ good of ALLGOOD_nil() =/=> ()
