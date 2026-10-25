#include "share/atspre_staload.hats"
(* quire src/schema.bats anc_not_crit, copied: see gen_lemmas.py.
   False variant: a tag with the first letter 96 is both ancillary and critical *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop ANC(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 96 <= first_letter; first_letter < 256; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    ANC_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

dataprop CRIT(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 0 <= first_letter; first_letter < 97; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    CRIT_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

extern prfun anc_not_crit {tag:bytes} (ANC(tag), CRIT(tag)): FALSEP()

primplement anc_not_crit {tag} (ancillary, critical) = (case+ ancillary of ANC_mk() => (case+ critical of CRIT_mk() =/=> ()))
