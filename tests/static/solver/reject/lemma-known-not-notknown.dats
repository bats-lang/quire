#include "share/atspre_staload.hats"
(* quire src/schema.bats known_not_notknown, _known_not_notknown, copied: see gen_lemmas.py.
   False variant: two tags that TAGDIFF calls different can be equal *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

datasort layout =
  | lo_nil of ()
  | lo_i32 of (layout)
  | lo_str of (layout)

datasort mode =
  | m_req of ()                                                            
  | m_opt of ()                                                                                             
  | m_added of ()                                                                                                       

datasort fvals =
  | fv_nil of ()
  | fv_i32 of (int, fvals)
  | fv_str of (bytes, fvals)

datasort specs =
  | gs_nil of ()
  | gs_cons of (bytes, layout, mode, fvals, specs)

dataprop KNOWN(specs, bytes, int) =
  | {tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs} KNOWN_here(gs_cons(tag, kinds, requirement, defaults, rest), tag, 0)
  | {position:nat}{tag,other:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs}
    KNOWN_later(gs_cons(other, kinds, requirement, defaults, rest), tag, position+1) of KNOWN(rest, tag, position)

dataprop TAGDIFF(bytes, bytes) =
  | {left_first,left_second,left_third,left_fourth,right_first,right_second,right_third,right_fourth:int | 0 <= left_first; left_first < 256; 0 <= left_second; left_second < 256; 0 <= left_third; left_third < 256; 0 <= left_fourth; left_fourth < 256;
       0 <= right_first; right_first < 256; 0 <= right_second; right_second < 256; 0 <= right_third; right_third < 256; 0 <= right_fourth; right_fourth < 256;
       left_first != right_first || left_second != right_second || left_third != right_third || left_fourth != right_fourth || 0 == 0}
    TAGDIFF_mk(bcons(left_first, bcons(left_second, bcons(left_third, bcons(left_fourth, bnil())))), bcons(right_first, bcons(right_second, bcons(right_third, bcons(right_fourth, bnil())))))

dataprop NOTKNOWN(specs, bytes) =
  | {tag:bytes} NOTKNOWN_nil(gs_nil(), tag)
  | {tag,other:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs}
    NOTKNOWN_cons(gs_cons(other, kinds, requirement, defaults, rest), tag) of (TAGDIFF(other, tag), NOTKNOWN(rest, tag))

dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

extern prfun known_not_notknown {known:specs}{tag:bytes}{position:nat} (KNOWN(known, tag, position), NOTKNOWN(known, tag)): FALSEP()

prfun _known_not_notknown {known:specs}{tag:bytes}{position:nat} .<position>. (known_proof: KNOWN(known, tag, position), unknown_proof: NOTKNOWN(known, tag)): FALSEP() =
  case+ known_proof of
  | KNOWN_here() => (case+ unknown_proof of NOTKNOWN_cons(different, _) => (case+ different of TAGDIFF_mk() =/=> ()))
  | KNOWN_later(known_rest) => (case+ unknown_proof of NOTKNOWN_cons(_, unknown_rest) => _known_not_notknown(known_rest, unknown_rest))

primplement known_not_notknown {known}{tag}{position} (known_proof, unknown_proof) = _known_not_notknown(known_proof, unknown_proof)
