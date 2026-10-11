(* schema -- a record's chunks as the values of its groups: the known
   groups in a fixed order, then the chunks a newer Quire may have
   added *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "bytes.sats"
staload "chunk.sats"
staload "seq.sats"
staload "fields.sats"

(* the values of the known groups, in order *)
#pub datasort gvals =
  | gv_nil of ()
  | gv_cons of (fvals, gvals)

(* the unknown ancillary chunks kept to be written back *)
#pub datasort extras =
  | ex_nil of ()
  | ex_cons of (bytes, bytes, extras)       (* tag, data *)

(* the tags of the chunks that were lost *)
#pub datasort lost =
  | lt_nil of ()
  | lt_cons of (bytes, lost)

(* the tags of the groups the record did not hold: groups added to the format after it was written (m_added),
   whose values are then their defaults. An absent group is not a lost one: nothing of it was ever there *)
#pub datasort absent =
  | ab_nil of ()
  | ab_cons of (bytes, absent)

(* why a record could not be read *)
#pub datasort cause =
  | cause_damaged of ()        (* what it must hold is not whole *)
  | cause_newer of ()          (* a newer Quire's: it holds what must be understood *)

(* what a record's chunks come to *)
#pub datasort sdres =
  | sd_ok of (gvals, extras, absent)
  | sd_loss of (gvals, extras, lost, absent)
  | sd_fail of (cause)

#pub dataprop EQSD(sdres, sdres) =
  | {result:sdres} EQSD_refl(result, result)

(* a group: its tag, the kinds of its fields, whether the record needs it,
   and the values it has when it is lost *)
#pub datasort mode =
  | m_req of ()       (* the record needs it, and a damaged one is no record *)
  | m_opt of ()       (* a damaged one is lost (its defaults stand in); every version of the format writes it *)
  | m_added of ()     (* a damaged one is lost; and a record written before the group was added has none: that is no loss *)

(* MUSTHAVE(mode): a record without the group is not whole *)
#pub dataprop MUSTHAVE(mode) =
  | MUSTHAVE_req(m_req())
  | MUSTHAVE_opt(m_opt())

#pub datasort specs =
  | gs_nil of ()
  | gs_cons of (bytes, layout, mode, fvals, specs)

(* ANC(tag): the first letter is lower case: a reader that does not know
   the chunk may pass it over *)
#pub dataprop ANC(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 97 <= first_letter; first_letter < 256; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    ANC_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

(* CRIT(tag): the first letter is not: a reader that does not know the
   chunk must refuse the record *)
#pub dataprop CRIT(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 0 <= first_letter; first_letter < 97; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    CRIT_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

(* TAGDIFF(a, b): two tags of 4 letters that differ *)
#pub dataprop TAGDIFF(bytes, bytes) =
  | {left_first,left_second,left_third,left_fourth,right_first,right_second,right_third,right_fourth:int | 0 <= left_first; left_first < 256; 0 <= left_second; left_second < 256; 0 <= left_third; left_third < 256; 0 <= left_fourth; left_fourth < 256;
       0 <= right_first; right_first < 256; 0 <= right_second; right_second < 256; 0 <= right_third; right_third < 256; 0 <= right_fourth; right_fourth < 256;
       left_first != right_first || left_second != right_second || left_third != right_third || left_fourth != right_fourth}
    TAGDIFF_mk(bcons(left_first, bcons(left_second, bcons(left_third, bcons(left_fourth, bnil())))), bcons(right_first, bcons(right_second, bcons(right_third, bcons(right_fourth, bnil())))))

(* KNOWN(known, tag, position): one of the groups is called tag, the one at position *)
#pub dataprop KNOWN(specs, bytes, int) =
  | {tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs} KNOWN_here(gs_cons(tag, kinds, requirement, defaults, rest), tag, 0)
  | {position:nat}{tag,other:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs}
    KNOWN_later(gs_cons(other, kinds, requirement, defaults, rest), tag, position+1) of KNOWN(rest, tag, position)

(* NOTKNOWN(known, tag): none is *)
#pub dataprop NOTKNOWN(specs, bytes) =
  | {tag:bytes} NOTKNOWN_nil(gs_nil(), tag)
  | {tag,other:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs}
    NOTKNOWN_cons(gs_cons(other, kinds, requirement, defaults, rest), tag) of (TAGDIFF(other, tag), NOTKNOWN(rest, tag))


#pub prfun known_not_notknown {known:specs}{tag:bytes}{position:nat} (KNOWN(known, tag, position), NOTKNOWN(known, tag)): FALSEP()

prfun _known_not_notknown {known:specs}{tag:bytes}{position:nat} .<position>. (known_proof: KNOWN(known, tag, position), unknown_proof: NOTKNOWN(known, tag)): FALSEP() =
  case+ known_proof of
  | KNOWN_here() => (case+ unknown_proof of NOTKNOWN_cons(different, _) => (case+ different of TAGDIFF_mk() =/=> ()))
  | KNOWN_later(known_rest) => (case+ unknown_proof of NOTKNOWN_cons(_, unknown_rest) => _known_not_notknown(known_rest, unknown_rest))

primplement known_not_notknown {known}{tag}{position} (known_proof, unknown_proof) = _known_not_notknown(known_proof, unknown_proof)

#pub prfun anc_not_crit {tag:bytes} (ANC(tag), CRIT(tag)): FALSEP()

primplement anc_not_crit {tag} (ancillary, critical) = (case+ ancillary of ANC_mk() => (case+ critical of CRIT_mk() =/=> ()))

(* differing is symmetric *)
#pub prfun tagdiff_swap {left_tag,right_tag:bytes} (TAGDIFF(left_tag, right_tag)): TAGDIFF(right_tag, left_tag)

primplement tagdiff_swap {left_tag,right_tag} (different) = (case+ different of TAGDIFF_mk() => TAGDIFF_mk())

(* a tag that is one of the groups' differs from one that none is *)
#pub prfun known_notknown_diff {known:specs}{tag,other:bytes}{position:nat} (KNOWN(known, tag, position), NOTKNOWN(known, other)): TAGDIFF(other, tag)

prfun _known_notknown_diff {known:specs}{tag,other:bytes}{position:nat} .<position>. (known_proof: KNOWN(known, tag, position), unknown_proof: NOTKNOWN(known, other)): TAGDIFF(other, tag) =
  case+ known_proof of
  | KNOWN_here() => (case+ unknown_proof of NOTKNOWN_cons(different, _) => tagdiff_swap(different))
  | KNOWN_later(known_rest) => (case+ unknown_proof of NOTKNOWN_cons(_, unknown_rest) => _known_notknown_diff(known_rest, unknown_rest))

primplement known_notknown_diff {known}{tag,other}{position} (known_proof, unknown_proof) = _known_notknown_diff(known_proof, unknown_proof)

(* SPECSOK(known): the groups' tags are all different (a group's is none of those after it) *)
#pub dataprop SPECSOK(specs) =
  | SPECSOK_nil(gs_nil())
  | {tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}
    SPECSOK_cons(gs_cons(tag, kinds, requirement, defaults, more)) of (NOTKNOWN(more, tag), SPECSOK(more))

(* TAILOF(known, tail, depth): tail is known with its first depth groups dropped *)
#pub dataprop TAILOF(specs, specs, int) =
  | {known:specs} TAILOF_refl(known, known, 0)
  | {known:specs}{tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{tail:specs}{depth:nat}
    TAILOF_drop(gs_cons(tag, kinds, requirement, defaults, known), tail, depth+1) of TAILOF(known, tail, depth)

(* what follows the first group of a tail is a tail *)
#pub prfun tailof_next {known:specs}{tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{depth:nat}
  (TAILOF(known, gs_cons(tag, kinds, requirement, defaults, more), depth)): TAILOF(known, more, depth+1)

prfun _tailof_next {known:specs}{tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{depth:nat} .<depth>.
  (tail: TAILOF(known, gs_cons(tag, kinds, requirement, defaults, more), depth)): TAILOF(known, more, depth+1) =
  case+ tail of
  | TAILOF_refl() => TAILOF_drop(TAILOF_refl())
  | TAILOF_drop(prior) => TAILOF_drop(_tailof_next(prior))

primplement tailof_next {known}{tag}{kinds}{requirement}{defaults}{more}{depth} (tail) = _tailof_next(tail)

(* the first group of a tail is known, at the position of its depth *)
#pub prfun tailof_known {known:specs}{tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{depth:nat}
  (TAILOF(known, gs_cons(tag, kinds, requirement, defaults, more), depth)): KNOWN(known, tag, depth)

prfun _tailof_known {known:specs}{tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{depth:nat} .<depth>.
  (tail: TAILOF(known, gs_cons(tag, kinds, requirement, defaults, more), depth)): KNOWN(known, tag, depth) =
  case+ tail of
  | TAILOF_refl() => KNOWN_here()
  | TAILOF_drop(prior) => KNOWN_later(_tailof_known(prior))

primplement tailof_known {known}{tag}{kinds}{requirement}{defaults}{more}{depth} (tail) = _tailof_known(tail)

(* NOTAG(tag, chunks): none of chunks, whole or damaged, has this tag *)
#pub dataprop NOTAG(bytes, pchunks) =
  | {tag:bytes} NOTAG_nil(tag, pnil())
  | {tag,other,data:bytes}{rest:pchunks} NOTAG_good(tag, pgood(other, data, rest)) of (TAGDIFF(other, tag), NOTAG(tag, rest))
  | {tag,other:bytes}{rest:pchunks} NOTAG_bad(tag, pbad(other, rest)) of (TAGDIFF(other, tag), NOTAG(tag, rest))

(* which chunk of a tag a record is read by: none, the last whole one (its data), or, with none whole, a damaged one *)
#pub datasort selected =
  | sel_none of ()
  | sel_good of (bytes)
  | sel_bad of ()

(* EXT(tag, chunks, chosen, others, dropped): the chunks of this tag are taken out of chunks, in any place; the last
   whole one is chosen (else a damaged one, else none), the others stay, in their order, and the tag is among those
   dropped once for each chunk of it that was not chosen *)
#pub dataprop EXT(bytes, pchunks, selected, pchunks, lost) =
  | {tag:bytes} EXT_nil(tag, pnil(), sel_none(), pnil(), lt_nil())
  | {tag,other,data:bytes}{rest,others:pchunks}{chosen:selected}{dropped:lost}
    EXT_skip_good(tag, pgood(other, data, rest), chosen, pgood(other, data, others), dropped) of (TAGDIFF(other, tag), EXT(tag, rest, chosen, others, dropped))
  | {tag,other:bytes}{rest,others:pchunks}{chosen:selected}{dropped:lost}
    EXT_skip_bad(tag, pbad(other, rest), chosen, pbad(other, others), dropped) of (TAGDIFF(other, tag), EXT(tag, rest, chosen, others, dropped))
  | {tag,data:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_good_last(tag, pgood(tag, data, rest), sel_good(data), others, dropped) of EXT(tag, rest, sel_none(), others, dropped)
  | {tag,data,later:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_good_shadowed(tag, pgood(tag, data, rest), sel_good(later), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_good(later), others, dropped)
  | {tag,data:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_good_over_bad(tag, pgood(tag, data, rest), sel_good(data), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_bad(), others, dropped)
  | {tag:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_bad_last(tag, pbad(tag, rest), sel_bad(), others, dropped) of EXT(tag, rest, sel_none(), others, dropped)
  | {tag,later:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_bad_shadowed(tag, pbad(tag, rest), sel_good(later), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_good(later), others, dropped)
  | {tag:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_bad_over_bad(tag, pbad(tag, rest), sel_bad(), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_bad(), others, dropped)

#pub dataprop EQEXT(selected, pchunks, lost, selected, pchunks, lost) =
  | {chosen:selected}{others:pchunks}{dropped:lost} EQEXT_refl(chosen, others, dropped, chosen, others, dropped)

#pub prfun ext_functional {tag:bytes}{chunks:pchunks}{chunk_count:nat}{first_chosen,second_chosen:selected}{first_others,second_others:pchunks}{first_dropped,second_dropped:lost}
  (PCN(chunk_count, chunks), EXT(tag, chunks, first_chosen, first_others, first_dropped), EXT(tag, chunks, second_chosen, second_others, second_dropped))
  : EQEXT(first_chosen, first_others, first_dropped, second_chosen, second_others, second_dropped)

prfun _ext_functional {tag:bytes}{chunks:pchunks}{chunk_count:nat}{first_chosen,second_chosen:selected}{first_others,second_others:pchunks}{first_dropped,second_dropped:lost} .<chunk_count>.
  (count: PCN(chunk_count, chunks), left: EXT(tag, chunks, first_chosen, first_others, first_dropped), right: EXT(tag, chunks, second_chosen, second_others, second_dropped))
  : EQEXT(first_chosen, first_others, first_dropped, second_chosen, second_others, second_dropped) =
  case+ left of
  | EXT_nil() => (case+ right of EXT_nil() => EQEXT_refl())
  | EXT_skip_good(left_diff, left_rest) =>
    (case+ right of
     | EXT_skip_good(_, right_rest) => let
         prval PCN_good(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end
     | EXT_good_last(_) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | EXT_good_shadowed(_) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | EXT_good_over_bad(_) => (case+ left_diff of TAGDIFF_mk() =/=> ()))
  | EXT_skip_bad(left_diff, left_rest) =>
    (case+ right of
     | EXT_skip_bad(_, right_rest) => let
         prval PCN_bad(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end
     | EXT_bad_last(_) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | EXT_bad_shadowed(_) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | EXT_bad_over_bad(_) => (case+ left_diff of TAGDIFF_mk() =/=> ()))
  | EXT_good_last(left_rest) =>
    (case+ right of
     | EXT_skip_good(right_diff, _) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | EXT_good_last(right_rest) => let
         prval PCN_good(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end
     | EXT_good_shadowed(right_rest) => let
         prval PCN_good(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_good_over_bad(right_rest) => let
         prval PCN_good(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end)
  | EXT_good_shadowed(left_rest) =>
    (case+ right of
     | EXT_skip_good(right_diff, _) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | EXT_good_last(right_rest) => let
         prval PCN_good(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_good_shadowed(right_rest) => let
         prval PCN_good(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end
     | EXT_good_over_bad(right_rest) => let
         prval PCN_good(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end)
  | EXT_good_over_bad(left_rest) =>
    (case+ right of
     | EXT_skip_good(right_diff, _) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | EXT_good_last(right_rest) => let
         prval PCN_good(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_good_shadowed(right_rest) => let
         prval PCN_good(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_good_over_bad(right_rest) => let
         prval PCN_good(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end)
  | EXT_bad_last(left_rest) =>
    (case+ right of
     | EXT_skip_bad(right_diff, _) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | EXT_bad_last(right_rest) => let
         prval PCN_bad(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end
     | EXT_bad_shadowed(right_rest) => let
         prval PCN_bad(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_bad_over_bad(right_rest) => let
         prval PCN_bad(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end)
  | EXT_bad_shadowed(left_rest) =>
    (case+ right of
     | EXT_skip_bad(right_diff, _) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | EXT_bad_last(right_rest) => let
         prval PCN_bad(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_bad_shadowed(right_rest) => let
         prval PCN_bad(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end
     | EXT_bad_over_bad(right_rest) => let
         prval PCN_bad(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end)
  | EXT_bad_over_bad(left_rest) =>
    (case+ right of
     | EXT_skip_bad(right_diff, _) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | EXT_bad_last(right_rest) => let
         prval PCN_bad(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_bad_shadowed(right_rest) => let
         prval PCN_bad(count1) = count
       in (case+ _ext_functional(count1, left_rest, right_rest) of EQEXT_refl() =/=> ()) end
     | EXT_bad_over_bad(right_rest) => let
         prval PCN_bad(count1) = count
         prval EQEXT_refl() = _ext_functional(count1, left_rest, right_rest)
       in EQEXT_refl() end)

primplement ext_functional {tag}{chunks}{chunk_count}{first_chosen,second_chosen}{first_others,second_others}{first_dropped,second_dropped} (count, left, right) = _ext_functional(count, left, right)

(* a list with no chunk of the tag gives nothing, and keeps every chunk *)
#pub prfun notag_ext {tag:bytes}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), NOTAG(tag, chunks)): EXT(tag, chunks, sel_none(), chunks, lt_nil())

prfun _notag_ext {tag:bytes}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), absent: NOTAG(tag, chunks)): EXT(tag, chunks, sel_none(), chunks, lt_nil()) =
  case+ absent of
  | NOTAG_nil() => EXT_nil()
  | NOTAG_good(different, rest) => let
      prval PCN_good(count1) = count
    in EXT_skip_good(different, _notag_ext(count1, rest)) end
  | NOTAG_bad(different, rest) => let
      prval PCN_bad(count1) = count
    in EXT_skip_bad(different, _notag_ext(count1, rest)) end

primplement notag_ext {tag}{chunks}{chunk_count} (count, absent) = _notag_ext(count, absent)

(* LOSTCAT(first, second, both, first_n): both is first (first_n tags) and then second *)
#pub dataprop LOSTCAT(lost, lost, lost, int) =
  | {second:lost} LOSTCAT_nil(lt_nil(), second, second, 0)
  | {tag:bytes}{first,second,both:lost}{first_n:nat} LOSTCAT_cons(lt_cons(tag, first), second, lt_cons(tag, both), first_n+1) of LOSTCAT(first, second, both, first_n)

#pub dataprop EQLOST(lost, lost) =
  | {tags:lost} EQLOST_refl(tags, tags)

#pub prfun lostcat_functional {first,second,left_both,right_both:lost}{left_n,right_n:nat} (LOSTCAT(first, second, left_both, left_n), LOSTCAT(first, second, right_both, right_n)): EQLOST(left_both, right_both)

prfun _lostcat_functional {first,second,left_both,right_both:lost}{left_n,right_n:nat} .<left_n>. (left: LOSTCAT(first, second, left_both, left_n), right: LOSTCAT(first, second, right_both, right_n)): EQLOST(left_both, right_both) =
  case+ left of
  | LOSTCAT_nil() => (case+ right of LOSTCAT_nil() => EQLOST_refl())
  | LOSTCAT_cons(left_rest) =>
    (case+ right of
     | LOSTCAT_cons(right_rest) => let
         prval EQLOST_refl() = _lostcat_functional(left_rest, right_rest)
       in EQLOST_refl() end)

primplement lostcat_functional {first,second,left_both,right_both}{left_n,right_n} (left, right) = _lostcat_functional(left, right)

(* CANON(group_specs, spec_n, chunks, canonical, dropped): the chunks of each group of group_specs (spec_n of them) are
   taken out of chunks, in any place, and put in the order of the groups, each tag once (EXT); what is left follows.
   The tags dropped are those of the chunks not chosen. A record is read from its canonical chunks *)
#pub dataprop CANON(specs, int, pchunks, pchunks, lost) =
  | {chunks:pchunks} CAN_nil(gs_nil(), 0, chunks, chunks, lt_nil())
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{chunks,others,canonical:pchunks}{other_count,first_n:nat}{first,second,dropped:lost}
    CAN_none(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, chunks, canonical, dropped)
    of (EXT(group_tag, chunks, sel_none(), others, first), PCN(other_count, others), CANON(more, spec_n, others, canonical, second), LOSTCAT(first, second, dropped, first_n))
  | {group_tag,data:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{chunks,others,canonical:pchunks}{other_count,first_n:nat}{first,second,dropped:lost}
    CAN_good(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, chunks, pgood(group_tag, data, canonical), dropped)
    of (EXT(group_tag, chunks, sel_good(data), others, first), PCN(other_count, others), CANON(more, spec_n, others, canonical, second), LOSTCAT(first, second, dropped, first_n))
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{chunks,others,canonical:pchunks}{other_count,first_n:nat}{first,second,dropped:lost}
    CAN_bad(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, chunks, pbad(group_tag, canonical), dropped)
    of (EXT(group_tag, chunks, sel_bad(), others, first), PCN(other_count, others), CANON(more, spec_n, others, canonical, second), LOSTCAT(first, second, dropped, first_n))

#pub dataprop EQCAN(pchunks, lost, pchunks, lost) =
  | {canonical:pchunks}{dropped:lost} EQCAN_refl(canonical, dropped, canonical, dropped)

#pub prfun canon_functional {group_specs:specs}{spec_n:nat}{chunks:pchunks}{chunk_count:nat}{left_canonical,right_canonical:pchunks}{left_dropped,right_dropped:lost}
  (PCN(chunk_count, chunks), CANON(group_specs, spec_n, chunks, left_canonical, left_dropped), CANON(group_specs, spec_n, chunks, right_canonical, right_dropped))
  : EQCAN(left_canonical, left_dropped, right_canonical, right_dropped)

prfun _canon_functional {group_specs:specs}{spec_n:nat}{chunks:pchunks}{chunk_count:nat}{left_canonical,right_canonical:pchunks}{left_dropped,right_dropped:lost} .<spec_n>.
  (count: PCN(chunk_count, chunks), left: CANON(group_specs, spec_n, chunks, left_canonical, left_dropped), right: CANON(group_specs, spec_n, chunks, right_canonical, right_dropped))
  : EQCAN(left_canonical, left_dropped, right_canonical, right_dropped) =
  case+ left of
  | CAN_nil() => (case+ right of CAN_nil() => EQCAN_refl())
  | CAN_none(left_ext, left_count, left_rest, left_cat) =>
    (case+ right of
     | CAN_none(right_ext, _, right_rest, right_cat) => let
         prval EQEXT_refl() = ext_functional(count, left_ext, right_ext)
         prval EQCAN_refl() = _canon_functional(left_count, left_rest, right_rest)
         prval EQLOST_refl() = lostcat_functional(left_cat, right_cat)
       in EQCAN_refl() end
     | CAN_good(right_ext, _, _, _) => (case+ ext_functional(count, left_ext, right_ext) of EQEXT_refl() =/=> ())
     | CAN_bad(right_ext, _, _, _) => (case+ ext_functional(count, left_ext, right_ext) of EQEXT_refl() =/=> ()))
  | CAN_good(left_ext, left_count, left_rest, left_cat) =>
    (case+ right of
     | CAN_none(right_ext, _, _, _) => (case+ ext_functional(count, left_ext, right_ext) of EQEXT_refl() =/=> ())
     | CAN_good(right_ext, _, right_rest, right_cat) => let
         prval EQEXT_refl() = ext_functional(count, left_ext, right_ext)
         prval EQCAN_refl() = _canon_functional(left_count, left_rest, right_rest)
         prval EQLOST_refl() = lostcat_functional(left_cat, right_cat)
       in EQCAN_refl() end
     | CAN_bad(right_ext, _, _, _) => (case+ ext_functional(count, left_ext, right_ext) of EQEXT_refl() =/=> ()))
  | CAN_bad(left_ext, left_count, left_rest, left_cat) =>
    (case+ right of
     | CAN_none(right_ext, _, _, _) => (case+ ext_functional(count, left_ext, right_ext) of EQEXT_refl() =/=> ())
     | CAN_good(right_ext, _, _, _) => (case+ ext_functional(count, left_ext, right_ext) of EQEXT_refl() =/=> ())
     | CAN_bad(right_ext, _, right_rest, right_cat) => let
         prval EQEXT_refl() = ext_functional(count, left_ext, right_ext)
         prval EQCAN_refl() = _canon_functional(left_count, left_rest, right_rest)
         prval EQLOST_refl() = lostcat_functional(left_cat, right_cat)
       in EQCAN_refl() end)

primplement canon_functional {group_specs}{spec_n}{chunks}{chunk_count}{left_canonical,right_canonical}{left_dropped,right_dropped} (count, left, right) = _canon_functional(count, left, right)

(* PREPV(field_values, rest_result, whole_result): whole_result is rest_result with the values of a group in front *)
#pub dataprop PREPV(fvals, sdres, sdres) =
  | {field_values:fvals}{group_values:gvals}{kept:extras}{missing:absent} PREPV_ok(field_values, sd_ok(group_values, kept, missing), sd_ok(gv_cons(field_values, group_values), kept, missing))
  | {field_values:fvals}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent} PREPV_loss(field_values, sd_loss(group_values, kept, lost_tags, missing), sd_loss(gv_cons(field_values, group_values), kept, lost_tags, missing))
  | {field_values:fvals}{reason:cause} PREPV_fail(field_values, sd_fail(reason), sd_fail(reason))

(* PREPL(defaults, tag, rest_result, whole_result): the same, for a group that was lost: its default
   values defaults, and its tag among those lost *)
#pub dataprop PREPL(fvals, bytes, sdres, sdres) =
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{missing:absent}
    PREPL_ok(defaults, tag, sd_ok(group_values, kept, missing), sd_loss(gv_cons(defaults, group_values), kept, lt_cons(tag, lt_nil()), missing))
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPL_loss(defaults, tag, sd_loss(group_values, kept, lost_tags, missing), sd_loss(gv_cons(defaults, group_values), kept, lt_cons(tag, lost_tags), missing))
  | {defaults:fvals}{tag:bytes}{reason:cause} PREPL_fail(defaults, tag, sd_fail(reason), sd_fail(reason))

(* PREPA(defaults, tag, rest_result, whole_result): the same, for a group the record did not hold: its default
   values defaults, and its tag among those absent *)
#pub dataprop PREPA(fvals, bytes, sdres, sdres) =
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{missing:absent}
    PREPA_ok(defaults, tag, sd_ok(group_values, kept, missing), sd_ok(gv_cons(defaults, group_values), kept, ab_cons(tag, missing)))
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPA_loss(defaults, tag, sd_loss(group_values, kept, lost_tags, missing), sd_loss(gv_cons(defaults, group_values), kept, lost_tags, ab_cons(tag, missing)))
  | {defaults:fvals}{tag:bytes}{reason:cause} PREPA_fail(defaults, tag, sd_fail(reason), sd_fail(reason))

(* PREPX(tag, data, rest_result, whole_result): the same, for a chunk kept to be written back *)
#pub dataprop PREPX(bytes, bytes, sdres, sdres) =
  | {tag,data:bytes}{group_values:gvals}{kept:extras}{missing:absent} PREPX_ok(tag, data, sd_ok(group_values, kept, missing), sd_ok(group_values, ex_cons(tag, data, kept), missing))
  | {tag,data:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPX_loss(tag, data, sd_loss(group_values, kept, lost_tags, missing), sd_loss(group_values, ex_cons(tag, data, kept), lost_tags, missing))
  | {tag,data:bytes}{reason:cause} PREPX_fail(tag, data, sd_fail(reason), sd_fail(reason))

(* PREPT(tag, rest_result, whole_result): the same, for a chunk passed over that was lost *)
#pub dataprop PREPT(bytes, sdres, sdres) =
  | {tag:bytes}{group_values:gvals}{kept:extras}{missing:absent} PREPT_ok(tag, sd_ok(group_values, kept, missing), sd_loss(group_values, kept, lt_cons(tag, lt_nil()), missing))
  | {tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPT_loss(tag, sd_loss(group_values, kept, lost_tags, missing), sd_loss(group_values, kept, lt_cons(tag, lost_tags), missing))
  | {tag:bytes}{reason:cause} PREPT_fail(tag, sd_fail(reason), sd_fail(reason))

#pub prfun prepv_functional {field_values:fvals}{base_result,left_result,right_result:sdres} (PREPV(field_values, base_result, left_result), PREPV(field_values, base_result, right_result)): EQSD(left_result, right_result)

primplement prepv_functional {field_values}{base_result,left_result,right_result} (left, right) =
  case+ left of
  | PREPV_ok() => (case+ right of PREPV_ok() => EQSD_refl())
  | PREPV_loss() => (case+ right of PREPV_loss() => EQSD_refl())
  | PREPV_fail() => (case+ right of PREPV_fail() => EQSD_refl())

#pub prfun prepl_functional {defaults:fvals}{tag:bytes}{base_result,left_result,right_result:sdres} (PREPL(defaults, tag, base_result, left_result), PREPL(defaults, tag, base_result, right_result)): EQSD(left_result, right_result)

primplement prepl_functional {defaults}{tag}{base_result,left_result,right_result} (left, right) =
  case+ left of
  | PREPL_ok() => (case+ right of PREPL_ok() => EQSD_refl())
  | PREPL_loss() => (case+ right of PREPL_loss() => EQSD_refl())
  | PREPL_fail() => (case+ right of PREPL_fail() => EQSD_refl())

#pub prfun prepa_functional {defaults:fvals}{tag:bytes}{base_result,left_result,right_result:sdres} (PREPA(defaults, tag, base_result, left_result), PREPA(defaults, tag, base_result, right_result)): EQSD(left_result, right_result)

primplement prepa_functional {defaults}{tag}{base_result,left_result,right_result} (left, right) =
  case+ left of
  | PREPA_ok() => (case+ right of PREPA_ok() => EQSD_refl())
  | PREPA_loss() => (case+ right of PREPA_loss() => EQSD_refl())
  | PREPA_fail() => (case+ right of PREPA_fail() => EQSD_refl())

#pub prfun prepx_functional {tag,data:bytes}{base_result,left_result,right_result:sdres} (PREPX(tag, data, base_result, left_result), PREPX(tag, data, base_result, right_result)): EQSD(left_result, right_result)

primplement prepx_functional {tag,data}{base_result,left_result,right_result} (left, right) =
  case+ left of
  | PREPX_ok() => (case+ right of PREPX_ok() => EQSD_refl())
  | PREPX_loss() => (case+ right of PREPX_loss() => EQSD_refl())
  | PREPX_fail() => (case+ right of PREPX_fail() => EQSD_refl())

#pub prfun prept_functional {tag:bytes}{base_result,left_result,right_result:sdres} (PREPT(tag, base_result, left_result), PREPT(tag, base_result, right_result)): EQSD(left_result, right_result)

primplement prept_functional {tag}{base_result,left_result,right_result} (left, right) =
  case+ left of
  | PREPT_ok() => (case+ right of PREPT_ok() => EQSD_refl())
  | PREPT_loss() => (case+ right of PREPT_loss() => EQSD_refl())
  | PREPT_fail() => (case+ right of PREPT_fail() => EQSD_refl())


#pub prfun falsep_eqsd {left_result,right_result:sdres} (FALSEP()): EQSD(left_result, right_result)

primplement falsep_eqsd {left_result,right_result} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* XDEC(known, chunks, result): what follows the known groups is read *)
#pub dataprop XDEC(specs, pchunks, sdres) =
  | {known:specs} XD_nil(known, pnil(), sd_ok(gv_nil(), ex_nil(), ab_nil()))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{rest_result,whole_result:sdres}
    XD_anc(known, pgood(tag, data, rest), whole_result) of (ANC(tag), NOTKNOWN(known, tag), XDEC(known, rest, rest_result), PREPX(tag, data, rest_result, whole_result))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{position:nat}
    XD_anc_known(known, pgood(tag, data, rest), sd_fail(cause_damaged())) of (ANC(tag), KNOWN(known, tag, position))
  | {known:specs}{tag:bytes}{rest:pchunks}{rest_result,whole_result:sdres}
    XD_anc_lost(known, pbad(tag, rest), whole_result) of (ANC(tag), XDEC(known, rest, rest_result), PREPT(tag, rest_result, whole_result))
  | {known:specs}{tag,data:bytes}{rest:pchunks}
    XD_newer(known, pgood(tag, data, rest), sd_fail(cause_newer())) of (CRIT(tag), NOTKNOWN(known, tag))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{position:nat}
    XD_known(known, pgood(tag, data, rest), sd_fail(cause_damaged())) of (CRIT(tag), KNOWN(known, tag, position))
  | {known:specs}{tag:bytes}{rest:pchunks}
    XD_crit_bad(known, pbad(tag, rest), sd_fail(cause_damaged())) of CRIT(tag)

#pub prfun xdec_functional {known:specs}{chunks:pchunks}{chunk_count:nat}{left_result,right_result:sdres} (PCN(chunk_count, chunks), XDEC(known, chunks, left_result), XDEC(known, chunks, right_result)): EQSD(left_result, right_result)

prfun _xdec_functional {known:specs}{chunks:pchunks}{chunk_count:nat}{left_result,right_result:sdres} .<chunk_count>.
  (count: PCN(chunk_count, chunks), left: XDEC(known, chunks, left_result), right: XDEC(known, chunks, right_result)): EQSD(left_result, right_result) =
  case+ left of
  | XD_nil() => (case+ right of XD_nil() => EQSD_refl())
  | XD_anc(left_anc, left_notknown, left_rest, left_prepend) =>
    (case+ right of
     | XD_anc(_, _, right_rest, right_prepend) => let
         prval PCN_good(count1) = count
         prval EQSD_refl() = _xdec_functional(count1, left_rest, right_rest)
       in prepx_functional(left_prepend, right_prepend) end
     | XD_anc_known(_, right_known) => falsep_eqsd(known_not_notknown(right_known, left_notknown))
     | XD_newer(right_crit, _) => falsep_eqsd(anc_not_crit(left_anc, right_crit))
     | XD_known(right_crit, _) => falsep_eqsd(anc_not_crit(left_anc, right_crit)))
  | XD_anc_known(left_anc, left_known) =>
    (case+ right of
     | XD_anc(_, right_notknown, _, _) => falsep_eqsd(known_not_notknown(left_known, right_notknown))
     | XD_anc_known(_, _) => EQSD_refl()
     | XD_newer(right_crit, _) => falsep_eqsd(anc_not_crit(left_anc, right_crit))
     | XD_known(right_crit, _) => falsep_eqsd(anc_not_crit(left_anc, right_crit)))
  | XD_anc_lost(left_anc, left_rest, left_prepend) =>
    (case+ right of
     | XD_anc_lost(_, right_rest, right_prepend) => let
         prval PCN_bad(count1) = count
         prval EQSD_refl() = _xdec_functional(count1, left_rest, right_rest)
       in prept_functional(left_prepend, right_prepend) end
     | XD_crit_bad(right_crit) => falsep_eqsd(anc_not_crit(left_anc, right_crit)))
  | XD_newer(left_crit, left_notknown) =>
    (case+ right of
     | XD_anc(right_anc, _, _, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_anc_known(right_anc, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_newer(_, _) => EQSD_refl()
     | XD_known(_, right_known) => falsep_eqsd(known_not_notknown(right_known, left_notknown)))
  | XD_known(left_crit, left_known) =>
    (case+ right of
     | XD_anc(right_anc, _, _, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_anc_known(right_anc, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_newer(_, right_notknown) => falsep_eqsd(known_not_notknown(left_known, right_notknown))
     | XD_known(_, _) => EQSD_refl())
  | XD_crit_bad(left_crit) =>
    (case+ right of
     | XD_anc_lost(right_anc, _, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_crit_bad(_) => EQSD_refl())

primplement xdec_functional {known}{chunks}{chunk_count}{left_result,right_result} (count, left, right) = _xdec_functional(count, left, right)


(* SPECN(group_specs, spec_n): group_specs holds spec_n groups *)
#pub dataprop SPECN(specs, int) =
  | SPECN_nil(gs_nil(), 0)
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}
    SPECN_cons(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1) of SPECN(more, spec_n)

#pub prfun specn_functional {group_specs:specs}{first_n,second_n:nat} (SPECN(group_specs, first_n), SPECN(group_specs, second_n)): EQI(first_n, second_n)

prfun _specn_functional {group_specs:specs}{first_n,second_n:nat} .<first_n>. (first: SPECN(group_specs, first_n), second: SPECN(group_specs, second_n)): EQI(first_n, second_n) =
  case+ first of
  | SPECN_nil() => (case+ second of SPECN_nil() => EQI_refl())
  | SPECN_cons(first_rest) => (case+ second of SPECN_cons(second_rest) => (case+ _specn_functional(first_rest, second_rest) of EQI_refl() => EQI_refl()))

primplement specn_functional {group_specs}{first_n,second_n} (first, second) = _specn_functional(first, second)

(* SDEC(known, group_specs, spec_n, chunks, result): the groups of specs, spec_n of them, are read from chunks,
   and what follows them *)
#pub dataprop SDEC(specs, specs, int, pchunks, sdres) =
  | {known:specs}{chunks:pchunks}{whole_result:sdres}
    SD_nil(known, gs_nil(), 0, chunks, whole_result) of XDEC(known, chunks, whole_result)
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{field_values:fvals}{rest_result,whole_result:sdres}
    SD_present(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, pgood(group_tag, data, rest), whole_result)
    of (LEN(data, data_len), FDEC(kinds, data, fd_ok(field_values)), SDEC(known, more, spec_n, rest, rest_result), PREPV(field_values, rest_result, whole_result))
  | {known,more:specs}{spec_n:pos}{group_tag:bytes}{kinds:layout}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}
    SD_garbled_req(known, gs_cons(group_tag, kinds, m_req(), defaults, more), spec_n, pgood(group_tag, data, rest), sd_fail(cause_damaged()))
    of (LEN(data, data_len), FDEC(kinds, data, fd_bad()))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_garbled_opt(known, gs_cons(group_tag, kinds, m_opt(), defaults, more), spec_n+1, pgood(group_tag, data, rest), whole_result)
    of (LEN(data, data_len), FDEC(kinds, data, fd_bad()), SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_garbled_added(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pgood(group_tag, data, rest), whole_result)
    of (LEN(data, data_len), FDEC(kinds, data, fd_bad()), SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:pos}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}
    SD_bad_req(known, gs_cons(group_tag, kinds, m_req(), defaults, more), spec_n, pbad(group_tag, rest), sd_fail(cause_damaged()))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_bad_opt(known, gs_cons(group_tag, kinds, m_opt(), defaults, more), spec_n+1, pbad(group_tag, rest), whole_result)
    of (SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_bad_added(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pbad(group_tag, rest), whole_result)
    of (SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:pos}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}
    SD_missing_end(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n, pnil(), sd_fail(cause_damaged()))
    of MUSTHAVE(requirement)
  | {known,more:specs}{spec_n:pos}{group_tag,tag,data:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:pchunks}
    SD_missing_good(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n, pgood(tag, data, rest), sd_fail(cause_damaged()))
    of (MUSTHAVE(requirement), TAGDIFF(tag, group_tag))
  | {known,more:specs}{spec_n:pos}{group_tag,tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:pchunks}
    SD_missing_bad(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n, pbad(tag, rest), sd_fail(cause_damaged()))
    of (MUSTHAVE(requirement), TAGDIFF(tag, group_tag))
  (* a group added to the format after the record was written is not in it: its defaults stand in, and it is not lost *)
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest_result,whole_result:sdres}
    SD_added_end(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pnil(), whole_result)
    of (SDEC(known, more, spec_n, pnil(), rest_result), PREPA(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag,tag,data:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_added_good(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pgood(tag, data, rest), whole_result)
    of (TAGDIFF(tag, group_tag), SDEC(known, more, spec_n, pgood(tag, data, rest), rest_result), PREPA(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag,tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_added_bad(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pbad(tag, rest), whole_result)
    of (TAGDIFF(tag, group_tag), SDEC(known, more, spec_n, pbad(tag, rest), rest_result), PREPA(defaults, group_tag, rest_result, whole_result))

(* a group the record needs is not an added one *)
prfn _musthave_not_added (needed: MUSTHAVE(m_added())): FALSEP() =
  case+ needed of
  | MUSTHAVE_req() =/=> ()
  | MUSTHAVE_opt() =/=> ()

(* a bad chunk is never read whole: a later group or what follows the groups loses or refuses it *)
prfun _sdec_bad_not_ok {known,group_specs:specs}{spec_n:nat}{tag:bytes}{rest:pchunks}{group_values:gvals}{kept:extras}{missing:absent} .<spec_n>.
  (reading: SDEC(known, group_specs, spec_n, pbad(tag, rest), sd_ok(group_values, kept, missing))): FALSEP() =
  case+ reading of
  | SD_nil(after) => (case+ after of
                      | XD_anc_lost(_, _, prepend) => (case+ prepend of PREPT_ok() =/=> () | PREPT_loss() =/=> () | PREPT_fail() =/=> ()))
  | SD_bad_opt(_, prepend) => (case+ prepend of PREPL_ok() =/=> () | PREPL_loss() =/=> () | PREPL_fail() =/=> ())
  | SD_bad_added(_, prepend) => (case+ prepend of PREPL_ok() =/=> () | PREPL_loss() =/=> () | PREPL_fail() =/=> ())
  | SD_added_bad(_, sub, PREPA_ok()) => _sdec_bad_not_ok(sub)

#pub prfun sdec_functional {known,group_specs:specs}{spec_n:nat}{chunks:pchunks}{chunk_count:nat}{left_result,right_result:sdres}
  (PCN(chunk_count, chunks), SDEC(known, group_specs, spec_n, chunks, left_result), SDEC(known, group_specs, spec_n, chunks, right_result)): EQSD(left_result, right_result)

prfun _sdec_functional {known,group_specs:specs}{spec_n:nat}{chunks:pchunks}{chunk_count:nat}{left_result,right_result:sdres} .<chunk_count, spec_n>.
  (count: PCN(chunk_count, chunks), left: SDEC(known, group_specs, spec_n, chunks, left_result), right: SDEC(known, group_specs, spec_n, chunks, right_result)): EQSD(left_result, right_result) =
  case+ left of
  | SD_nil(px) => (case+ right of SD_nil(qx) => xdec_functional(count, px, qx))
  | SD_present(left_length, left_field, left_rest, left_prepend) =>
    (case+ right of
     | SD_present(right_length, right_field, right_rest, right_prepend) => let
         prval PCN_good(count1) = count
         prval EQI_refl() = len_functional(left_length, right_length)
         prval EQFD_refl() = fdec_functional(left_length, left_field, right_field)
         prval EQSD_refl() = _sdec_functional(count1, left_rest, right_rest)
       in prepv_functional(left_prepend, right_prepend) end
     | SD_garbled_req(right_length, right_field) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_garbled_opt(right_length, right_field, _, _) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_garbled_added(right_length, right_field, _, _) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_missing_good(_, right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | SD_added_good(right_diff, _, _) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_garbled_req(left_length, left_field) =>
    (case+ right of
     | SD_present(right_length, right_field, _, _) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_garbled_req(_, _) => EQSD_refl()
     | SD_missing_good(_, right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_garbled_opt(left_length, left_field, left_rest, left_prepend) =>
    (case+ right of
     | SD_present(right_length, right_field, _, _) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_garbled_opt(_, _, right_rest, right_prepend) => let
         prval PCN_good(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, left_rest, right_rest)
       in prepl_functional(left_prepend, right_prepend) end
     | SD_missing_good(_, right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_garbled_added(left_length, left_field, left_rest, left_prepend) =>
    (case+ right of
     | SD_present(right_length, right_field, _, _) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_garbled_added(_, _, right_rest, right_prepend) => let
         prval PCN_good(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, left_rest, right_rest)
       in prepl_functional(left_prepend, right_prepend) end
     | SD_missing_good(_, right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | SD_added_good(right_diff, _, _) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_bad_req() =>
    (case+ right of
     | SD_bad_req() => EQSD_refl()
     | SD_missing_bad(_, right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_bad_opt(left_rest, left_prepend) =>
    (case+ right of
     | SD_bad_opt(right_rest, right_prepend) => let
         prval PCN_bad(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, left_rest, right_rest)
       in prepl_functional(left_prepend, right_prepend) end
     | SD_missing_bad(_, right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_bad_added(left_rest, left_prepend) =>
    (case+ right of
     | SD_bad_added(right_rest, right_prepend) => let
         prval PCN_bad(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, left_rest, right_rest)
       in prepl_functional(left_prepend, right_prepend) end
     | SD_missing_bad(_, right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ())
     | SD_added_bad(right_diff, _, _) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_missing_end(left_must) =>
    (case+ right of
     | SD_missing_end(_) => EQSD_refl()
     | SD_added_end(_, _) => falsep_eqsd(_musthave_not_added(left_must)))
  | SD_missing_good(left_must, left_diff) =>
    (case+ right of
     | SD_present(_, _, _, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_garbled_req(_, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_garbled_opt(_, _, _, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_garbled_added(_, _, _, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_missing_good(_, _) => EQSD_refl()
     | SD_added_good(_, _, _) => falsep_eqsd(_musthave_not_added(left_must)))
  | SD_missing_bad(left_must, left_diff) =>
    (case+ right of
     | SD_bad_req() => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_bad_opt(_, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_bad_added(_, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_missing_bad(_, _) => EQSD_refl()
     | SD_added_bad(_, _, _) => falsep_eqsd(_musthave_not_added(left_must)))
  | SD_added_end(left_rest, left_prepend) =>
    (case+ right of
     | SD_missing_end(right_must) => falsep_eqsd(_musthave_not_added(right_must))
     | SD_added_end(right_rest, right_prepend) => let
         prval EQSD_refl() = _sdec_functional(count, left_rest, right_rest)
       in prepa_functional(left_prepend, right_prepend) end)
  | SD_added_good(left_diff, left_rest, left_prepend) =>
    (case+ right of
     | SD_present(_, _, _, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_garbled_added(_, _, _, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_missing_good(right_must, _) => falsep_eqsd(_musthave_not_added(right_must))
     | SD_added_good(_, right_rest, right_prepend) => let
         prval EQSD_refl() = _sdec_functional(count, left_rest, right_rest)
       in prepa_functional(left_prepend, right_prepend) end)
  | SD_added_bad(left_diff, left_rest, left_prepend) =>
    (case+ right of
     | SD_bad_added(_, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_missing_bad(right_must, _) => falsep_eqsd(_musthave_not_added(right_must))
     | SD_added_bad(_, right_rest, right_prepend) => let
         prval EQSD_refl() = _sdec_functional(count, left_rest, right_rest)
       in prepa_functional(left_prepend, right_prepend) end)

primplement sdec_functional {known,group_specs}{spec_n}{chunks}{chunk_count}{left_result,right_result} (count, left, right) = _sdec_functional(count, left, right)


(* XENC(known, kept, chunks): chunks are the chunks kept in kept, written back; the tag of none is a group's *)
#pub dataprop XENC(specs, extras, pchunks) =
  | {known:specs} XENC_nil(known, ex_nil(), pnil())
  | {known:specs}{tag,data:bytes}{kept:extras}{rest:pchunks}
    XENC_cons(known, ex_cons(tag, data, kept), pgood(tag, data, rest)) of (ANC(tag), NOTKNOWN(known, tag), XENC(known, kept, rest))

(* SENC(known, group_specs, spec_n, group_values, kept, missing, chunks): chunks are the chunks of the groups of specs
   (spec_n of them, the last of known) holding group_values, then those kept in kept; a group in missing is not written,
   and holds its defaults *)
#pub dataprop SENC(specs, specs, int, gvals, extras, absent, pchunks) =
  | {known:specs}{kept:extras}{chunks:pchunks} SENC_nil(known, gs_nil(), 0, gv_nil(), kept, ab_nil(), chunks) of XENC(known, kept, chunks)
  | {known:specs}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{field_values:fvals}{group_values:gvals}{kept:extras}{missing:absent}{data:bytes}{data_len:nat}{rest:pchunks}
    SENC_cons(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, gv_cons(field_values, group_values), kept, missing, pgood(group_tag, data, rest))
    of (LEN(data, data_len), FENC(kinds, field_values, data), SENC(known, more, spec_n, group_values, kept, missing, rest))
  | {known:specs}{group_tag:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}
    SENC_absent_end(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, gv_cons(defaults, group_values), kept, ab_cons(group_tag, missing), pnil())
    of SENC(known, more, spec_n, group_values, kept, missing, pnil())
  | {known:specs}{group_tag,tag,data:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}{rest:pchunks}
    SENC_absent_good(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, gv_cons(defaults, group_values), kept, ab_cons(group_tag, missing), pgood(tag, data, rest))
    of (TAGDIFF(tag, group_tag), SENC(known, more, spec_n, group_values, kept, missing, pgood(tag, data, rest)))

#pub prfun xenc_xdec {known:specs}{kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), XENC(known, kept, chunks))
  : XDEC(known, chunks, sd_ok(gv_nil(), kept, ab_nil()))

prfun _xenc_xdec {known:specs}{kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), encoding: XENC(known, kept, chunks))
  : XDEC(known, chunks, sd_ok(gv_nil(), kept, ab_nil())) =
  case+ encoding of
  | XENC_nil() => XD_nil()
  | XENC_cons(ancillary, unknown, rest) => let
      prval PCN_good(count1) = count
    in XD_anc(ancillary, unknown, _xenc_xdec(count1, rest), PREPX_ok()) end

primplement xenc_xdec {known}{kept}{chunks}{chunk_count} (count, encoding) = _xenc_xdec(count, encoding)

#pub prfun senc_sdec {known,group_specs:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), SENC(known, group_specs, spec_n, group_values, kept, missing, chunks))
  : SDEC(known, group_specs, spec_n, chunks, sd_ok(group_values, kept, missing))

prfun _senc_sdec {known,group_specs:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat} .<chunk_count, spec_n>. (count: PCN(chunk_count, chunks), encoding: SENC(known, group_specs, spec_n, group_values, kept, missing, chunks))
  : SDEC(known, group_specs, spec_n, chunks, sd_ok(group_values, kept, missing)) =
  case+ encoding of
  | SENC_nil(extras_encoding) => SD_nil(xenc_xdec(count, extras_encoding))
  | SENC_cons(length_proof, field_encoding, rest) => let
      prval PCN_good(count1) = count
    in SD_present(length_proof, fenc_fdec(length_proof, field_encoding), _senc_sdec(count1, rest), PREPV_ok()) end
  | SENC_absent_end(rest) => SD_added_end(_senc_sdec(count, rest), PREPA_ok())
  | SENC_absent_good(different, rest) => SD_added_good(different, _senc_sdec(count, rest), PREPA_ok())

primplement senc_sdec {known,group_specs}{spec_n}{group_values}{kept}{missing}{chunks}{chunk_count} (count, encoding) = _senc_sdec(count, encoding)

(* a group's tag is none of the kept chunks' *)
#pub prfun xenc_notag {known:specs}{kept:extras}{chunks:pchunks}{chunk_count:nat}{tag:bytes}{position:nat} (PCN(chunk_count, chunks), KNOWN(known, tag, position), XENC(known, kept, chunks)): NOTAG(tag, chunks)

prfun _xenc_notag {known:specs}{kept:extras}{chunks:pchunks}{chunk_count:nat}{tag:bytes}{position:nat} .<chunk_count>.
  (count: PCN(chunk_count, chunks), known_proof: KNOWN(known, tag, position), encoding: XENC(known, kept, chunks)): NOTAG(tag, chunks) =
  case+ encoding of
  | XENC_nil() => NOTAG_nil()
  | XENC_cons(_, unknown, rest) => let
      prval PCN_good(count1) = count
    in NOTAG_good(known_notknown_diff(known_proof, unknown), _xenc_notag(count1, known_proof, rest)) end

primplement xenc_notag {known}{kept}{chunks}{chunk_count}{tag}{position} (count, known_proof, encoding) = _xenc_notag(count, known_proof, encoding)

(* and none of the chunks written for the groups after it is its *)
#pub prfun senc_notag {known,group_specs:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat}{tag:bytes}{position:nat}
  (PCN(chunk_count, chunks), KNOWN(known, tag, position), NOTKNOWN(group_specs, tag), SENC(known, group_specs, spec_n, group_values, kept, missing, chunks)): NOTAG(tag, chunks)

prfun _senc_notag {known,group_specs:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat}{tag:bytes}{position:nat} .<spec_n>.
  (count: PCN(chunk_count, chunks), known_proof: KNOWN(known, tag, position), unknown: NOTKNOWN(group_specs, tag), encoding: SENC(known, group_specs, spec_n, group_values, kept, missing, chunks)): NOTAG(tag, chunks) =
  case+ encoding of
  | SENC_nil(extras_encoding) => xenc_notag(count, known_proof, extras_encoding)
  | SENC_cons(_, _, rest) => let
      prval NOTKNOWN_cons(different, unknown_rest) = unknown
      prval PCN_good(count1) = count
    in NOTAG_good(different, _senc_notag(count1, known_proof, unknown_rest, rest)) end
  | SENC_absent_end(rest) => let
      prval NOTKNOWN_cons(_, unknown_rest) = unknown
    in _senc_notag(count, known_proof, unknown_rest, rest) end
  | SENC_absent_good(_, rest) => let
      prval NOTKNOWN_cons(_, unknown_rest) = unknown
    in _senc_notag(count, known_proof, unknown_rest, rest) end

primplement senc_notag {known,group_specs}{spec_n}{group_values}{kept}{missing}{chunks}{chunk_count}{tag}{position} (count, known_proof, unknown, encoding) = _senc_notag(count, known_proof, unknown, encoding)

(* the chunks written are their own canonical chunks: reading them takes each group's chunk where it stands, and drops none *)
#pub prfun senc_canon {known,group_specs:specs}{spec_n:nat}{depth:nat}{group_values:gvals}{kept:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat}
  (PCN(chunk_count, chunks), TAILOF(known, group_specs, depth), SPECSOK(group_specs), SENC(known, group_specs, spec_n, group_values, kept, missing, chunks))
  : CANON(group_specs, spec_n, chunks, chunks, lt_nil())

prfun _senc_canon {known,group_specs:specs}{spec_n:nat}{depth:nat}{group_values:gvals}{kept:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat} .<spec_n>.
  (count: PCN(chunk_count, chunks), tail: TAILOF(known, group_specs, depth), specs_ok: SPECSOK(group_specs), encoding: SENC(known, group_specs, spec_n, group_values, kept, missing, chunks))
  : CANON(group_specs, spec_n, chunks, chunks, lt_nil()) =
  case+ encoding of
  | SENC_nil(_) => CAN_nil()
  | SENC_cons(_, _, rest) => let
      prval SPECSOK_cons(unknown_after, specs_ok_rest) = specs_ok
      prval PCN_good(count1) = count
      prval absent = senc_notag(count1, tailof_known(tail), unknown_after, rest)
      prval canon = _senc_canon(count1, tailof_next(tail), specs_ok_rest, rest)
    in CAN_good(EXT_good_last(notag_ext(count1, absent)), count1, canon, LOSTCAT_nil()) end
  | SENC_absent_end(rest) => let
      prval SPECSOK_cons(unknown_after, specs_ok_rest) = specs_ok
      prval absent = senc_notag(count, tailof_known(tail), unknown_after, rest)
      prval canon = _senc_canon(count, tailof_next(tail), specs_ok_rest, rest)
    in CAN_none(notag_ext(count, absent), count, canon, LOSTCAT_nil()) end
  | SENC_absent_good(_, rest) => let
      prval SPECSOK_cons(unknown_after, specs_ok_rest) = specs_ok
      prval absent = senc_notag(count, tailof_known(tail), unknown_after, rest)
      prval canon = _senc_canon(count, tailof_next(tail), specs_ok_rest, rest)
    in CAN_none(notag_ext(count, absent), count, canon, LOSTCAT_nil()) end

primplement senc_canon {known,group_specs}{spec_n}{depth}{group_values}{kept}{missing}{chunks}{chunk_count} (count, tail, specs_ok, encoding) = _senc_canon(count, tail, specs_ok, encoding)


(* The groups of a record, at run time, group_count of them: each one's tag, the
   kinds of its fields, whether it is needed, and its values when lost *)
#pub datatype modev(mode) =
  | ModeReq(m_req())
  | ModeOpt(m_opt())
  | ModeAdded(m_added())

#pub datavtype specsv(specs, int) =
  | SPV_nil(gs_nil(), 0)
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{group_count,field_count:nat | field_count < 1000}
    SPV_cons(gs_cons(group_tag, kinds, requirement, defaults, more), group_count+1) of (TAGNOT(group_tag), NOTKNOWN(more, group_tag) | blist(group_tag, 4), layoutv(kinds, field_count), modev(requirement), fvalsv(kinds, defaults, field_count), specsv(more, group_count))

#pub fun specsv_free {group_specs:specs}{group_count:nat} (specs: specsv(group_specs, group_count)): void

implement specsv_free {group_specs}{group_count} (specs) = let
  fun free_specs {group_specs:specs}{group_count:nat} .<group_count>. (specs: specsv(group_specs, group_count)): void =
    case+ specs of
    | ~SPV_nil() => ()
    | ~SPV_cons(_, _ | tag, layout, _, default, more) => let
        val () = blist_free(tag)
        val () = layoutv_free(layout)
        val () = fvalsv_free(default)
      in free_specs(more) end
in free_specs(specs) end

#pub fun specsv_copy {group_specs:specs}{group_count:nat} (specs: !specsv(group_specs, group_count)): specsv(group_specs, group_count)

implement specsv_copy {group_specs}{group_count} (specs) = let
  fun copy_specs {group_specs:specs}{group_count:nat} .<group_count>. (specs: !specsv(group_specs, group_count)): specsv(group_specs, group_count) =
    case+ specs of
    | SPV_nil() => SPV_nil()
    | SPV_cons(tag_proof, unknown_proof | tag, layout, mode, default, more) =>
      SPV_cons(tag_proof, unknown_proof | blist_copy(tag), layoutv_copy(layout), mode, fvalsv_copy(default), copy_specs(more))
in copy_specs(specs) end

(* How many groups the specs hold, as a proof *)
#pub fun specsv_specn {group_specs:specs}{group_count:nat} (specs: !specsv(group_specs, group_count)): (SPECN(group_specs, group_count) | void)

implement specsv_specn {group_specs}{group_count} (specs) = let
  fun count_specs {group_specs:specs}{group_count:nat} .<group_count>. (specs: !specsv(group_specs, group_count)): (SPECN(group_specs, group_count) | void) =
    case+ specs of
    | SPV_nil() => (SPECN_nil() | ())
    | SPV_cons(_, _ | _, _, _, _, more) => let
        val (more_count | ()) = count_specs(more)
      in (SPECN_cons(more_count) | ()) end
in count_specs(specs) end

(* The groups' tags are all different, as a proof *)
#pub fun specsv_ok {group_specs:specs}{group_count:nat} (specs: !specsv(group_specs, group_count)): (SPECSOK(group_specs) | void)

implement specsv_ok {group_specs}{group_count} (specs) = let
  fun check_specs {group_specs:specs}{group_count:nat} .<group_count>. (specs: !specsv(group_specs, group_count)): (SPECSOK(group_specs) | void) =
    case+ specs of
    | SPV_nil() => (SPECSOK_nil() | ())
    | SPV_cons(_, unknown | _, _, _, _, more) => let
        val (more_ok | ()) = check_specs(more)
      in (SPECSOK_cons(unknown, more_ok) | ()) end
in check_specs(specs) end

(* The values of the groups, at run time *)
#pub datavtype gvalsv(specs, gvals, int) =
  | GVV_nil(gs_nil(), gv_nil(), 0)
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{field_values:fvals}{group_values:gvals}{group_count,field_count:nat | field_count < 1000}
    GVV_cons(gs_cons(group_tag, kinds, requirement, defaults, more), gv_cons(field_values, group_values), group_count+1) of (fvalsv(kinds, field_values, field_count), gvalsv(more, group_values, group_count))

#pub fun gvalsv_free {group_specs:specs}{group_values:gvals}{group_count:nat} (group_values: gvalsv(group_specs, group_values, group_count)): void

implement gvalsv_free {group_specs}{group_values}{group_count} (group_values) = let
  fun free_group_values {group_specs:specs}{group_values:gvals}{group_count:nat} .<group_count>. (group_values: gvalsv(group_specs, group_values, group_count)): void =
    case+ group_values of
    | ~GVV_nil() => ()
    | ~GVV_cons(field_values, more) => let val () = fvalsv_free(field_values) in free_group_values(more) end
in free_group_values(group_values) end

(* The chunks kept to be written back, at run time *)
#pub datavtype extrasv(specs, extras, int) =
  | {known:specs} EXV_nil(known, ex_nil(), 0)
  | {known:specs}{tag,data:bytes}{kept:extras}{data_len,extras_count:nat | data_len < 1048576}
    EXV_cons(known, ex_cons(tag, data, kept), extras_count+1) of (ANC(tag), NOTKNOWN(known, tag) | blist(tag, 4), blist(data, data_len), extrasv(known, kept, extras_count))

#pub fun extrasv_free {known:specs}{kept:extras}{extras_count:nat} (extras: extrasv(known, kept, extras_count)): void

implement extrasv_free {known}{kept}{extras_count} (extras) = let
  fun free_extras {known:specs}{kept:extras}{extras_count:nat} .<extras_count>. (extras: extrasv(known, kept, extras_count)): void =
    case+ extras of
    | ~EXV_nil() => ()
    | ~EXV_cons(_, _ | tag, data, more) => let
        val () = blist_free(tag)
        val () = blist_free(data)
      in free_extras(more) end
in free_extras(extras) end

(* The tags of the chunks lost, at run time *)
#pub datavtype lostv(lost, int) =
  | LTV_nil(lt_nil(), 0)
  | {tag:bytes}{lost_tags:lost}{lost_count:nat} LTV_cons(lt_cons(tag, lost_tags), lost_count+1) of (blist(tag, 4), lostv(lost_tags, lost_count))

#pub fun lostv_free {lost_tags:lost}{lost_count:nat} (lost: lostv(lost_tags, lost_count)): void

implement lostv_free {lost_tags}{lost_count} (lost) = let
  fun free_lost {lost_tags:lost}{lost_count:nat} .<lost_count>. (lost: lostv(lost_tags, lost_count)): void =
    case+ lost of
    | ~LTV_nil() => ()
    | ~LTV_cons(tag, more) => let val () = blist_free(tag) in free_lost(more) end
in free_lost(lost) end

(* The tags of the groups the record did not hold, at run time *)
#pub datavtype absentv(absent, specs, int) =
  | ABV_nil(ab_nil(), gs_nil(), 0)
  | {missing:absent}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}
    ABV_skip(missing, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1) of absentv(missing, more, spec_n)
  | {missing:absent}{group_tag:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}
    ABV_gap(ab_cons(group_tag, missing), gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1) of (blist(group_tag, 4), absentv(missing, more, spec_n))

#pub fun absentv_free {missing:absent}{group_specs:specs}{spec_n:nat} (absent: absentv(missing, group_specs, spec_n)): void

implement absentv_free {missing}{group_specs}{spec_n} (absent) = let
  fun free_absent {missing:absent}{group_specs:specs}{spec_n:nat} .<spec_n>. (absent: absentv(missing, group_specs, spec_n)): void =
    case+ absent of
    | ~ABV_nil() => ()
    | ~ABV_skip(more) => free_absent(more)
    | ~ABV_gap(tag, more) => let val () = blist_free(tag) in free_absent(more) end
in free_absent(absent) end

#pub datatype causev(cause) =
  | CausDamaged(cause_damaged())
  | CausNewer(cause_newer())

(* What reading the groups of a record comes to *)
#pub datavtype schemaread(specs, sdres, specs) =
  | {known,group_specs:specs}{group_values:gvals}{kept:extras}{missing:absent}{spec_count,values_count,extras_count:nat}
    SDR_ok(known, sd_ok(group_values, kept, missing), group_specs) of (gvalsv(group_specs, group_values, values_count), extrasv(known, kept, extras_count), absentv(missing, group_specs, spec_count))
  | {known,group_specs:specs}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}{spec_count,values_count,extras_count,lost_count:nat}
    SDR_loss(known, sd_loss(group_values, kept, lost_tags, missing), group_specs) of (gvalsv(group_specs, group_values, values_count), extrasv(known, kept, extras_count), lostv(lost_tags, lost_count), absentv(missing, group_specs, spec_count))
  | {known,group_specs:specs}{reason:cause} SDR_fail(known, sd_fail(reason), group_specs) of causev(reason)


datavtype tagcmp(bytes, bytes) =
  | {left_tag,right_tag:bytes} TagSame(left_tag, right_tag) of (EQB(left_tag, right_tag) | )
  | {left_tag,right_tag:bytes} TagDiff(left_tag, right_tag) of (TAGDIFF(left_tag, right_tag) | )

fn _tag_compare {left_tag,right_tag:bytes} (left: !blist(left_tag, 4), right: !blist(right_tag, 4)): tagcmp(left_tag, right_tag) =
  case+ left of
  | blist_cons(left_first, blist_cons(left_second, blist_cons(left_third, blist_cons(left_fourth, blist_nil())))) =>
    (case+ right of
     | blist_cons(right_first, blist_cons(right_second, blist_cons(right_third, blist_cons(right_fourth, blist_nil())))) =>
       if left_first = right_first then
         (if left_second = right_second then
            (if left_third = right_third then
               (if left_fourth = right_fourth then TagSame(EQB_refl() | ) else TagDiff(TAGDIFF_mk() | ))
             else TagDiff(TAGDIFF_mk() | ))
          else TagDiff(TAGDIFF_mk() | ))
       else TagDiff(TAGDIFF_mk() | ))

(* whether a tag is one of the groups' *)
datavtype knownres(specs, bytes) =
  | {known:specs}{tag:bytes}{position:nat} KnownYes(known, tag) of (KNOWN(known, tag, position) | )
  | {known:specs}{tag:bytes} KnownNo(known, tag) of (NOTKNOWN(known, tag) | )

fn _known_find {known:specs}{tag:bytes}{known_count:nat} (tag: !blist(tag, 4), known: !specsv(known, known_count)): knownres(known, tag) = let
  fun find_tag {known:specs}{tag:bytes}{known_count:nat} .<known_count>. (tag: !blist(tag, 4), known: !specsv(known, known_count)): knownres(known, tag) =
    case+ known of
    | SPV_nil() => KnownNo(NOTKNOWN_nil() | )
    | SPV_cons(_, _ | group_tag, _, _, _, more) =>
      (case+ _tag_compare(group_tag, tag) of
       | ~TagSame(EQB_refl() | ) => KnownYes(KNOWN_here() | )
       | ~TagDiff(different | ) =>
         (case+ find_tag(tag, more) of
          | ~KnownYes(known_proof | ) => KnownYes(KNOWN_later(known_proof) | )
          | ~KnownNo(unknown_proof | ) => KnownNo(NOTKNOWN_cons(different, unknown_proof) | )))
in find_tag(tag, known) end


datavtype tagclass(bytes) =
  | {tag:bytes} IsAnc(tag) of (ANC(tag) | )
  | {tag:bytes} IsCrit(tag) of (CRIT(tag) | )

fn _tag_class {tag:bytes} (tag: !blist(tag, 4)): tagclass(tag) =
  case+ tag of
  | blist_cons(first_letter, blist_cons(_, blist_cons(_, blist_cons(_, blist_nil())))) =>
    if first_letter >= 97 then IsAnc(ANC_mk() | ) else IsCrit(CRIT_mk() | )

(* The tags dropped, one list and then the other *)
fun _lostv_cat {first,second:lost}{first_n,second_n:nat} .<first_n>. (first: lostv(first, first_n), second: lostv(second, second_n))
  : [both:lost][both_n:nat] (LOSTCAT(first, second, both, first_n) | lostv(both, both_n)) =
  case+ first of
  | ~LTV_nil() => (LOSTCAT_nil() | second)
  | ~LTV_cons(tag, more) => let
      val (rest | joined) = _lostv_cat(more, second)
    in (LOSTCAT_cons(rest) | LTV_cons(tag, joined)) end

#pub fun lostv_cat {first,second:lost}{first_n,second_n:nat} (first: lostv(first, first_n), second: lostv(second, second_n))
  : [both:lost][both_n:nat] (LOSTCAT(first, second, both, first_n) | lostv(both, both_n))

implement lostv_cat {first,second}{first_n,second_n} (first, second) = _lostv_cat(first, second)

(* The chunk of a tag a record is read by, at run time *)
datavtype chosenv(selected) =
  | CH_none(sel_none())
  | {data:bytes}{data_size:nat | data_size < 1048576} CH_good(sel_good(data)) of blist(data, data_size)
  | CH_bad(sel_bad())

(* What taking the chunks of a tag out of a list leaves *)
datavtype extraction(bytes, pchunks) =
  | {tag:bytes}{chunks:pchunks}{chosen:selected}{others:pchunks}{dropped:lost}{other_count,dropped_count:nat}
    EXTRACTED(tag, chunks) of (EXT(tag, chunks, chosen, others, dropped), PCN(other_count, others) | chosenv(chosen), chunklist(others, other_count), lostv(dropped, dropped_count))

(* Taking the chunks of a tag out of a list: the last whole one is chosen (else a damaged one), and the others of its tag are dropped *)
fun ext_read {tag:bytes}{chunks:pchunks}{chunk_count:nat} .<chunk_count>.
  (count: PCN(chunk_count, chunks), tag: !blist(tag, 4), chunk_list: chunklist(chunks, chunk_count)): extraction(tag, chunks) =
  case+ chunk_list of
  | ~CL_nil() => EXTRACTED(EXT_nil(), PCN_nil() | CH_none(), CL_nil(), LTV_nil())
  | ~CL_good(not_end | other, data, rest) => let
      prval PCN_good(count1) = count
      val found = ext_read(count1, tag, rest)
    in
      case+ _tag_compare(other, tag) of
      | ~TagDiff(different | ) =>
        (case+ found of
         | ~EXTRACTED(sub, others_count | chosen, others, dropped) =>
           EXTRACTED(EXT_skip_good(different, sub), PCN_good(others_count) | chosen, CL_good(not_end | other, data, others), dropped))
      | ~TagSame(EQB_refl() | ) => let
          val () = blist_free(other)
        in
          case+ found of
          | ~EXTRACTED(sub, others_count | chosen, others, dropped) =>
            (case+ chosen of
             | ~CH_none() => EXTRACTED(EXT_good_last(sub), others_count | CH_good(data), others, dropped)
             | ~CH_good(later) => let
                 val () = blist_free(data)
               in EXTRACTED(EXT_good_shadowed(sub), others_count | CH_good(later), others, LTV_cons(blist_copy(tag), dropped)) end
             | ~CH_bad() => EXTRACTED(EXT_good_over_bad(sub), others_count | CH_good(data), others, LTV_cons(blist_copy(tag), dropped)))
        end
    end
  | ~CL_bad(other, rest) => let
      prval PCN_bad(count1) = count
      val found = ext_read(count1, tag, rest)
    in
      case+ _tag_compare(other, tag) of
      | ~TagDiff(different | ) =>
        (case+ found of
         | ~EXTRACTED(sub, others_count | chosen, others, dropped) =>
           EXTRACTED(EXT_skip_bad(different, sub), PCN_bad(others_count) | chosen, CL_bad(other, others), dropped))
      | ~TagSame(EQB_refl() | ) => let
          val () = blist_free(other)
        in
          case+ found of
          | ~EXTRACTED(sub, others_count | chosen, others, dropped) =>
            (case+ chosen of
             | ~CH_none() => EXTRACTED(EXT_bad_last(sub), others_count | CH_bad(), others, dropped)
             | ~CH_good(later) => EXTRACTED(EXT_bad_shadowed(sub), others_count | CH_good(later), others, LTV_cons(blist_copy(tag), dropped))
             | ~CH_bad() => EXTRACTED(EXT_bad_over_bad(sub), others_count | CH_bad(), others, LTV_cons(blist_copy(tag), dropped)))
        end
    end

(* Putting the chunks of a record in the order of its groups, each tag once, wherever they stood; what is left follows *)
fun _canon_read {rest_specs:specs}{spec_n:nat}{chunks:pchunks}{chunk_count:nat} .<spec_n>.
  (count: PCN(chunk_count, chunks), specs: !specsv(rest_specs, spec_n), chunk_list: chunklist(chunks, chunk_count))
  : [canonical:pchunks][dropped:lost][canonical_count,dropped_count:nat]
    (CANON(rest_specs, spec_n, chunks, canonical, dropped), PCN(canonical_count, canonical) | chunklist(canonical, canonical_count), lostv(dropped, dropped_count)) =
  case+ specs of
  | SPV_nil() => (CAN_nil(), count | chunk_list, LTV_nil())
  | SPV_cons(not_end, _ | group_tag, _, _, _, more) => let
      val found = ext_read(count, group_tag, chunk_list)
    in
      case+ found of
      | ~EXTRACTED(extraction, others_count | chosen, others, first) => let
          val (canon, canonical_count | canonical, second) = _canon_read(others_count, more, others)
          val (joined | dropped) = _lostv_cat(first, second)
        in
          case+ chosen of
          | ~CH_none() => (CAN_none(extraction, others_count, canon, joined), canonical_count | canonical, dropped)
          | ~CH_good(data) =>
            (CAN_good(extraction, others_count, canon, joined), PCN_good(canonical_count) | CL_good(not_end | blist_copy(group_tag), data, canonical), dropped)
          | ~CH_bad() =>
            (CAN_bad(extraction, others_count, canon, joined), PCN_bad(canonical_count) | CL_bad(blist_copy(group_tag), canonical), dropped)
        end
    end

#pub fun canon_read {rest_specs:specs}{spec_n:nat}{chunks:pchunks}{chunk_count:nat}
  (count: PCN(chunk_count, chunks), specs: !specsv(rest_specs, spec_n), chunk_list: chunklist(chunks, chunk_count))
  : [canonical:pchunks][dropped:lost][canonical_count,dropped_count:nat]
    (CANON(rest_specs, spec_n, chunks, canonical, dropped), PCN(canonical_count, canonical) | chunklist(canonical, canonical_count), lostv(dropped, dropped_count))

implement canon_read {rest_specs}{spec_n}{chunks}{chunk_count} (count, specs, chunk_list) = _canon_read(count, specs, chunk_list)

(* Reading what follows the known groups *)
fun xdec_read {known:specs}{known_count:nat}{chunks:pchunks}{chunk_count:nat} .<chunk_count>.
  (count: PCN(chunk_count, chunks), known: !specsv(known, known_count), chunk_list: chunklist(chunks, chunk_count))
  : [result:sdres] (XDEC(known, chunks, result) | schemaread(known, result, gs_nil())) =
  case+ chunk_list of
  | ~CL_nil() => (XD_nil() | SDR_ok(GVV_nil(), EXV_nil(), ABV_nil()))
  | ~CL_good(_ | tag, data, rest) => let
      prval PCN_good(count1) = count
    in
      case+ _tag_class(tag) of
      | ~IsAnc(ancillary | ) =>
        (case+ _known_find(tag, known) of
         | ~KnownYes(known_proof | ) => let
             val () = chunklist_free(rest)
             val () = blist_free(tag)
             val () = blist_free(data)
           in (XD_anc_known(ancillary, known_proof) | SDR_fail(CausDamaged())) end
         | ~KnownNo(unknown_proof | ) => let
             val (sub | rest_read) = xdec_read(count1, known, rest)
           in
             case+ rest_read of
             | ~SDR_ok(~GVV_nil(), extras, ~ABV_nil()) =>
               (XD_anc(ancillary, unknown_proof, sub, PREPX_ok()) | SDR_ok(GVV_nil(), EXV_cons(ancillary, unknown_proof | tag, data, extras), ABV_nil()))
             | ~SDR_loss(~GVV_nil(), extras, lost, ~ABV_nil()) =>
               (XD_anc(ancillary, unknown_proof, sub, PREPX_loss()) | SDR_loss(GVV_nil(), EXV_cons(ancillary, unknown_proof | tag, data, extras), lost, ABV_nil()))
             | ~SDR_fail(reason) => let
                 val () = blist_free(tag)
                 val () = blist_free(data)
               in (XD_anc(ancillary, unknown_proof, sub, PREPX_fail()) | SDR_fail(reason)) end
           end)
      | ~IsCrit(critical | ) => let
          val () = chunklist_free(rest)
          val found = _known_find(tag, known)
          val () = blist_free(tag)
          val () = blist_free(data)
        in
          case+ found of
          | ~KnownYes(known_proof | ) => (XD_known(critical, known_proof) | SDR_fail(CausDamaged()))
          | ~KnownNo(unknown_proof | ) => (XD_newer(critical, unknown_proof) | SDR_fail(CausNewer()))
        end
    end
  | ~CL_bad(tag, rest) => let
      prval PCN_bad(count1) = count
    in
      case+ _tag_class(tag) of
      | ~IsAnc(ancillary | ) => let
          val (sub | rest_read) = xdec_read(count1, known, rest)
        in
          case+ rest_read of
          | ~SDR_ok(~GVV_nil(), extras, ~ABV_nil()) =>
            (XD_anc_lost(ancillary, sub, PREPT_ok()) | SDR_loss(GVV_nil(), extras, LTV_cons(tag, LTV_nil()), ABV_nil()))
          | ~SDR_loss(~GVV_nil(), extras, lost, ~ABV_nil()) =>
            (XD_anc_lost(ancillary, sub, PREPT_loss()) | SDR_loss(GVV_nil(), extras, LTV_cons(tag, lost), ABV_nil()))
          | ~SDR_fail(reason) => let
              val () = blist_free(tag)
            in (XD_anc_lost(ancillary, sub, PREPT_fail()) | SDR_fail(reason)) end
        end
      | ~IsCrit(critical | ) => let
          val () = chunklist_free(rest)
          val () = blist_free(tag)
        in (XD_crit_bad(critical) | SDR_fail(CausDamaged())) end
    end


(* The result of reading the groups after one that the record did not hold: its defaults in front, its tag among the absent *)
fn _absent_wrap {known,more:specs}{group_tag:bytes}{kinds:layout}{defaults:fvals}{field_count:nat | field_count < 1000}{rest_result:sdres}
  (group_tag: !blist(group_tag, 4), default: !fvalsv(kinds, defaults, field_count), rest_read: schemaread(known, rest_result, more))
  : [whole_result:sdres] (PREPA(defaults, group_tag, rest_result, whole_result) | schemaread(known, whole_result, gs_cons(group_tag, kinds, m_added(), defaults, more))) =
  case+ rest_read of
  | ~SDR_ok(later_values, later_extras, later_absent) =>
    (PREPA_ok() | SDR_ok(GVV_cons(fvalsv_copy(default), later_values), later_extras, ABV_gap(blist_copy(group_tag), later_absent)))
  | ~SDR_loss(later_values, later_extras, lost, later_absent) =>
    (PREPA_loss() | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, lost, ABV_gap(blist_copy(group_tag), later_absent)))
  | ~SDR_fail(reason) => (PREPA_fail() | SDR_fail(reason))

(* Reading the groups of a record, then what follows them *)
fun sdec_read {known,group_specs:specs}{known_count,spec_count:nat}{chunks:pchunks}{chunk_count:nat} .<chunk_count, spec_count>.
  (count: PCN(chunk_count, chunks), known: !specsv(known, known_count), specs: !specsv(group_specs, spec_count), chunk_list: chunklist(chunks, chunk_count))
  : [result:sdres] (SDEC(known, group_specs, spec_count, chunks, result) | schemaread(known, result, group_specs)) =
  case+ specs of
  | SPV_nil() => let
      val (sub | fields_result) = xdec_read(count, known, chunk_list)
    in (SD_nil(sub) | fields_result) end
  | SPV_cons(_, _ | group_tag, layout, mode, default, more) =>
    (case+ chunk_list of
     | ~CL_nil() =>
       (case+ mode of
        | ModeReq() => (SD_missing_end(MUSTHAVE_req()) | SDR_fail(CausDamaged()))
        | ModeOpt() => (SD_missing_end(MUSTHAVE_opt()) | SDR_fail(CausDamaged()))
        | ModeAdded() => let
            val (sub | rest_read) = sdec_read(count, known, more, CL_nil())
            val (prepend | whole) = _absent_wrap(group_tag, default, rest_read)
          in (SD_added_end(sub, prepend) | whole) end)
     | ~CL_good(tag_proof | tag, data, rest) => let
         prval PCN_good(count1) = count
       in
         case+ _tag_compare(tag, group_tag) of
         | ~TagDiff(different | ) =>
           (case+ mode of
            | ModeReq() => let
                val () = blist_free(tag)
                val () = blist_free(data)
                val () = chunklist_free(rest)
              in (SD_missing_good(MUSTHAVE_req(), different) | SDR_fail(CausDamaged())) end
            | ModeOpt() => let
                val () = blist_free(tag)
                val () = blist_free(data)
                val () = chunklist_free(rest)
              in (SD_missing_good(MUSTHAVE_opt(), different) | SDR_fail(CausDamaged())) end
            | ModeAdded() => let
                val (sub | rest_read) = sdec_read(count, known, more, CL_good(tag_proof | tag, data, rest))
                val (prepend | whole) = _absent_wrap(group_tag, default, rest_read)
              in (SD_added_good(different, sub, prepend) | whole) end)
         | ~TagSame(EQB_refl() | ) => let
             val () = blist_free(tag)
             val (len | _) = blist_len(data)
             val (field_proof | fields_result) = fields_read(layout, data)
           in
             case+ fields_result of
             | ~FDR_ok(field_values) => let
                 val (sub | rest_read) = sdec_read(count1, known, more, rest)
               in
                 case+ rest_read of
                 | ~SDR_ok(later_values, later_extras, later_absent) => (SD_present(len, field_proof, sub, PREPV_ok()) | SDR_ok(GVV_cons(field_values, later_values), later_extras, ABV_skip(later_absent)))
                 | ~SDR_loss(later_values, later_extras, lost, later_absent) => (SD_present(len, field_proof, sub, PREPV_loss()) | SDR_loss(GVV_cons(field_values, later_values), later_extras, lost, ABV_skip(later_absent)))
                 | ~SDR_fail(reason) => let val () = fvalsv_free(field_values) in (SD_present(len, field_proof, sub, PREPV_fail()) | SDR_fail(reason)) end
               end
             | ~FDR_bad() =>
               (case+ mode of
                | ModeReq() => let val () = chunklist_free(rest) in (SD_garbled_req(len, field_proof) | SDR_fail(CausDamaged())) end
                | ModeOpt() => let
                    val (sub | rest_read) = sdec_read(count1, known, more, rest)
                  in
                    case+ rest_read of
                    | ~SDR_ok(later_values, later_extras, later_absent) =>
                      (SD_garbled_opt(len, field_proof, sub, PREPL_ok())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), LTV_nil()), ABV_skip(later_absent)))
                    | ~SDR_loss(later_values, later_extras, lost, later_absent) =>
                      (SD_garbled_opt(len, field_proof, sub, PREPL_loss())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), lost), ABV_skip(later_absent)))
                    | ~SDR_fail(reason) => (SD_garbled_opt(len, field_proof, sub, PREPL_fail()) | SDR_fail(reason))
                  end
                | ModeAdded() => let
                    val (sub | rest_read) = sdec_read(count1, known, more, rest)
                  in
                    case+ rest_read of
                    | ~SDR_ok(later_values, later_extras, later_absent) =>
                      (SD_garbled_added(len, field_proof, sub, PREPL_ok())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), LTV_nil()), ABV_skip(later_absent)))
                    | ~SDR_loss(later_values, later_extras, lost, later_absent) =>
                      (SD_garbled_added(len, field_proof, sub, PREPL_loss())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), lost), ABV_skip(later_absent)))
                    | ~SDR_fail(reason) => (SD_garbled_added(len, field_proof, sub, PREPL_fail()) | SDR_fail(reason))
                  end)
           end
       end
     | ~CL_bad(tag, rest) => let
         prval PCN_bad(count1) = count
       in
         case+ _tag_compare(tag, group_tag) of
         | ~TagDiff(different | ) =>
           (case+ mode of
            | ModeReq() => let
                val () = blist_free(tag)
                val () = chunklist_free(rest)
              in (SD_missing_bad(MUSTHAVE_req(), different) | SDR_fail(CausDamaged())) end
            | ModeOpt() => let
                val () = blist_free(tag)
                val () = chunklist_free(rest)
              in (SD_missing_bad(MUSTHAVE_opt(), different) | SDR_fail(CausDamaged())) end
            | ModeAdded() => let
                val (sub | rest_read) = sdec_read(count, known, more, CL_bad(tag, rest))
                val (prepend | whole) = _absent_wrap(group_tag, default, rest_read)
              in (SD_added_bad(different, sub, prepend) | whole) end)
         | ~TagSame(EQB_refl() | ) => let
             val () = blist_free(tag)
           in
             case+ mode of
             | ModeReq() => let val () = chunklist_free(rest) in (SD_bad_req() | SDR_fail(CausDamaged())) end
             | ModeOpt() => let
                 val (sub | rest_read) = sdec_read(count1, known, more, rest)
               in
                 case+ rest_read of
                 | ~SDR_ok(later_values, later_extras, later_absent) =>
                   (SD_bad_opt(sub, PREPL_ok())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), LTV_nil()), ABV_skip(later_absent)))
                 | ~SDR_loss(later_values, later_extras, lost, later_absent) =>
                   (SD_bad_opt(sub, PREPL_loss())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), lost), ABV_skip(later_absent)))
                 | ~SDR_fail(reason) => (SD_bad_opt(sub, PREPL_fail()) | SDR_fail(reason))
               end
             | ModeAdded() => let
                 val (sub | rest_read) = sdec_read(count1, known, more, rest)
               in
                 case+ rest_read of
                 | ~SDR_ok(later_values, later_extras, later_absent) =>
                   (SD_bad_added(sub, PREPL_ok())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), LTV_nil()), ABV_skip(later_absent)))
                 | ~SDR_loss(later_values, later_extras, lost, later_absent) =>
                   (SD_bad_added(sub, PREPL_loss())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), lost), ABV_skip(later_absent)))
                 | ~SDR_fail(reason) => (SD_bad_added(sub, PREPL_fail()) | SDR_fail(reason))
               end
           end
       end)


prfn _anc_tagnot {tag:bytes} (ancillary: ANC(tag)): TAGNOT(tag) =
  case+ ancillary of ANC_mk() => TAGNOT_mk()

(* The chunks that hold the kept chunks, with the proof *)
fun _extras_write {known:specs}{kept:extras}{extras_count:nat} .<extras_count>. (extras: !extrasv(known, kept, extras_count))
  : [chunks:pchunks][chunk_count:nat] (XENC(known, kept, chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks) | chunklist(chunks, chunk_count)) =
  case+ extras of
  | EXV_nil() => (XENC_nil(), ALLGOOD_nil(), PCN_nil() | CL_nil())
  | EXV_cons(ancillary, unknown | tag, data, more) => let
      val (encoding, good, count | rest) = _extras_write(more)
    in
      (XENC_cons(ancillary, unknown, encoding), ALLGOOD_cons(good), PCN_good(count)
       | CL_good(_anc_tagnot(ancillary) | blist_copy(tag), blist_copy(data), rest))
    end

(* The chunks of a record's groups and kept chunks, with the proof *)
#pub fun schema_write {group_specs:specs}{group_values:gvals}{kept:extras}{spec_count,values_count,extras_count:nat}
  (specs: !specsv(group_specs, spec_count), group_values: !gvalsv(group_specs, group_values, values_count), extras: !extrasv(group_specs, kept, extras_count))
  : [chunks:pchunks][chunk_count:nat] (SENC(group_specs, group_specs, spec_count, group_values, kept, ab_nil(), chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks) | chunklist(chunks, chunk_count))

implement schema_write {group_specs}{group_values}{kept}{spec_count,values_count,extras_count} (specs, group_values, extras) = let
  fun write_groups {known,group_specs:specs}{group_values:gvals}{kept:extras}{spec_count,values_count,extras_count:nat} .<spec_count>.
    (specs: !specsv(group_specs, spec_count), group_values: !gvalsv(group_specs, group_values, values_count), extras: !extrasv(known, kept, extras_count))
    : [chunks:pchunks][chunk_count:nat] (SENC(known, group_specs, spec_count, group_values, kept, ab_nil(), chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks) | chunklist(chunks, chunk_count)) =
    case+ specs of
    | SPV_nil() => let
        prval GVV_nil() = group_values
        val (extras_encoding, good, count | chunk_list) = _extras_write(extras)
      in (SENC_nil(extras_encoding), good, count | chunk_list) end
    | SPV_cons(tag_proof, _ | group_tag, _, _, _, more) =>
      (case+ group_values of
       | GVV_cons(field_values, more_values) => let
           val (field_encoding | data) = fields_write(field_values)
           val (len | _) = blist_len(data)
           val (sub, good, count | rest) = write_groups(more, more_values, extras)
         in
           (SENC_cons(len, field_encoding, sub), ALLGOOD_cons(good), PCN_good(count)
            | CL_good(tag_proof | blist_copy(group_tag), data, rest))
         end)
in write_groups(specs, group_values, extras) end


(* Reading the groups of a record, with the proof *)
#pub fun schema_read {group_specs:specs}{spec_count:nat}{chunks:pchunks}{chunk_count:nat}
  (count: PCN(chunk_count, chunks), specs: !specsv(group_specs, spec_count), chunk_list: chunklist(chunks, chunk_count))
  : [result:sdres] (SDEC(group_specs, group_specs, spec_count, chunks, result) | schemaread(group_specs, result, group_specs))

implement schema_read {group_specs}{spec_count}{chunks}{chunk_count} (count, specs, chunk_list) = let
  val known = specsv_copy(specs)
  val result = sdec_read(count, known, specs, chunk_list)
  val () = specsv_free(known)
in result end

end
