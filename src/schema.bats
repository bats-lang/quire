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

(* why a record could not be read *)
#pub datasort cause =
  | cause_damaged of ()        (* what it must hold is not whole *)
  | cause_newer of ()          (* a newer Quire's: it holds what must be understood *)

(* what a record's chunks come to *)
#pub datasort sdres =
  | sd_ok of (gvals, extras)
  | sd_loss of (gvals, extras, lost)
  | sd_fail of (cause)

#pub dataprop EQSD(sdres, sdres) =
  | {result:sdres} EQSD_refl(result, result)

(* a group: its tag, the kinds of its fields, whether the record needs it,
   and the values it has when it is lost *)
#pub datasort mode =
  | m_req of ()
  | m_opt of ()

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

(* PREPV(field_values, rest_result, whole_result): whole_result is rest_result with the values of a group in front *)
#pub dataprop PREPV(fvals, sdres, sdres) =
  | {field_values:fvals}{group_values:gvals}{kept:extras} PREPV_ok(field_values, sd_ok(group_values, kept), sd_ok(gv_cons(field_values, group_values), kept))
  | {field_values:fvals}{group_values:gvals}{kept:extras}{lost_tags:lost} PREPV_loss(field_values, sd_loss(group_values, kept, lost_tags), sd_loss(gv_cons(field_values, group_values), kept, lost_tags))
  | {field_values:fvals}{reason:cause} PREPV_fail(field_values, sd_fail(reason), sd_fail(reason))

(* PREPL(defaults, tag, rest_result, whole_result): the same, for a group that was lost: its default
   values defaults, and its tag among those lost *)
#pub dataprop PREPL(fvals, bytes, sdres, sdres) =
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}
    PREPL_ok(defaults, tag, sd_ok(group_values, kept), sd_loss(gv_cons(defaults, group_values), kept, lt_cons(tag, lt_nil())))
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}
    PREPL_loss(defaults, tag, sd_loss(group_values, kept, lost_tags), sd_loss(gv_cons(defaults, group_values), kept, lt_cons(tag, lost_tags)))
  | {defaults:fvals}{tag:bytes}{reason:cause} PREPL_fail(defaults, tag, sd_fail(reason), sd_fail(reason))

(* PREPX(tag, data, rest_result, whole_result): the same, for a chunk kept to be written back *)
#pub dataprop PREPX(bytes, bytes, sdres, sdres) =
  | {tag,data:bytes}{group_values:gvals}{kept:extras} PREPX_ok(tag, data, sd_ok(group_values, kept), sd_ok(group_values, ex_cons(tag, data, kept)))
  | {tag,data:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}
    PREPX_loss(tag, data, sd_loss(group_values, kept, lost_tags), sd_loss(group_values, ex_cons(tag, data, kept), lost_tags))
  | {tag,data:bytes}{reason:cause} PREPX_fail(tag, data, sd_fail(reason), sd_fail(reason))

(* PREPT(tag, rest_result, whole_result): the same, for a chunk passed over that was lost *)
#pub dataprop PREPT(bytes, sdres, sdres) =
  | {tag:bytes}{group_values:gvals}{kept:extras} PREPT_ok(tag, sd_ok(group_values, kept), sd_loss(group_values, kept, lt_cons(tag, lt_nil())))
  | {tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost} PREPT_loss(tag, sd_loss(group_values, kept, lost_tags), sd_loss(group_values, kept, lt_cons(tag, lost_tags)))
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
  | {known:specs} XD_nil(known, pnil(), sd_ok(gv_nil(), ex_nil()))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{rest_result,whole_result:sdres}
    XD_anc(known, pgood(tag, data, rest), whole_result) of (ANC(tag), XDEC(known, rest, rest_result), PREPX(tag, data, rest_result, whole_result))
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
  | XD_anc(left_anc, left_rest, left_prepend) =>
    (case+ right of
     | XD_anc(_, right_rest, right_prepend) => let
         prval PCN_good(count1) = count
         prval EQSD_refl() = _xdec_functional(count1, left_rest, right_rest)
       in prepx_functional(left_prepend, right_prepend) end
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
     | XD_anc(right_anc, _, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_newer(_, _) => EQSD_refl()
     | XD_known(_, right_known) => falsep_eqsd(known_not_notknown(right_known, left_notknown)))
  | XD_known(left_crit, left_known) =>
    (case+ right of
     | XD_anc(right_anc, _, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_newer(_, right_notknown) => falsep_eqsd(known_not_notknown(left_known, right_notknown))
     | XD_known(_, _) => EQSD_refl())
  | XD_crit_bad(left_crit) =>
    (case+ right of
     | XD_anc_lost(right_anc, _, _) => falsep_eqsd(anc_not_crit(right_anc, left_crit))
     | XD_crit_bad(_) => EQSD_refl())

primplement xdec_functional {known}{chunks}{chunk_count}{left_result,right_result} (count, left, right) = _xdec_functional(count, left, right)


(* SDEC(known, group_specs, chunks, result): the groups of specs are read from chunks,
   and what follows them *)
#pub dataprop SDEC(specs, specs, pchunks, sdres) =
  | {known:specs}{chunks:pchunks}{whole_result:sdres}
    SD_nil(known, gs_nil(), chunks, whole_result) of XDEC(known, chunks, whole_result)
  | {known,more:specs}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{field_values:fvals}{rest_result,whole_result:sdres}
    SD_present(known, gs_cons(group_tag, kinds, requirement, defaults, more), pgood(group_tag, data, rest), whole_result)
    of (LEN(data, data_len), FDEC(kinds, data, fd_ok(field_values)), SDEC(known, more, rest, rest_result), PREPV(field_values, rest_result, whole_result))
  | {known,more:specs}{group_tag:bytes}{kinds:layout}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}
    SD_garbled_req(known, gs_cons(group_tag, kinds, m_req(), defaults, more), pgood(group_tag, data, rest), sd_fail(cause_damaged()))
    of (LEN(data, data_len), FDEC(kinds, data, fd_bad()))
  | {known,more:specs}{group_tag:bytes}{kinds:layout}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_garbled_opt(known, gs_cons(group_tag, kinds, m_opt(), defaults, more), pgood(group_tag, data, rest), whole_result)
    of (LEN(data, data_len), FDEC(kinds, data, fd_bad()), SDEC(known, more, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}
    SD_bad_req(known, gs_cons(group_tag, kinds, m_req(), defaults, more), pbad(group_tag, rest), sd_fail(cause_damaged()))
  | {known,more:specs}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_bad_opt(known, gs_cons(group_tag, kinds, m_opt(), defaults, more), pbad(group_tag, rest), whole_result)
    of (SDEC(known, more, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}
    SD_missing_end(known, gs_cons(group_tag, kinds, requirement, defaults, more), pnil(), sd_fail(cause_damaged()))
  | {known,more:specs}{group_tag,tag,data:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:pchunks}
    SD_missing_good(known, gs_cons(group_tag, kinds, requirement, defaults, more), pgood(tag, data, rest), sd_fail(cause_damaged()))
    of TAGDIFF(tag, group_tag)
  | {known,more:specs}{group_tag,tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:pchunks}
    SD_missing_bad(known, gs_cons(group_tag, kinds, requirement, defaults, more), pbad(tag, rest), sd_fail(cause_damaged()))
    of TAGDIFF(tag, group_tag)


#pub prfun sdec_functional {known,group_specs:specs}{chunks:pchunks}{chunk_count:nat}{left_result,right_result:sdres}
  (PCN(chunk_count, chunks), SDEC(known, group_specs, chunks, left_result), SDEC(known, group_specs, chunks, right_result)): EQSD(left_result, right_result)

prfun _sdec_functional {known,group_specs:specs}{chunks:pchunks}{chunk_count:nat}{left_result,right_result:sdres} .<chunk_count>.
  (count: PCN(chunk_count, chunks), left: SDEC(known, group_specs, chunks, left_result), right: SDEC(known, group_specs, chunks, right_result)): EQSD(left_result, right_result) =
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
     | SD_missing_good(right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_garbled_req(left_length, left_field) =>
    (case+ right of
     | SD_present(right_length, right_field, _, _) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_garbled_req(_, _) => EQSD_refl()
     | SD_missing_good(right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_garbled_opt(left_length, left_field, left_rest, left_prepend) =>
    (case+ right of
     | SD_present(right_length, right_field, _, _) => let prval EQI_refl() = len_functional(left_length, right_length) in (case+ fdec_functional(left_length, left_field, right_field) of EQFD_refl() =/=> ()) end
     | SD_garbled_opt(_, _, right_rest, right_prepend) => let
         prval PCN_good(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, left_rest, right_rest)
       in prepl_functional(left_prepend, right_prepend) end
     | SD_missing_good(right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_bad_req() =>
    (case+ right of
     | SD_bad_req() => EQSD_refl()
     | SD_missing_bad(right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_bad_opt(left_rest, left_prepend) =>
    (case+ right of
     | SD_bad_opt(right_rest, right_prepend) => let
         prval PCN_bad(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, left_rest, right_rest)
       in prepl_functional(left_prepend, right_prepend) end
     | SD_missing_bad(right_diff) => (case+ right_diff of TAGDIFF_mk() =/=> ()))
  | SD_missing_end() => (case+ right of SD_missing_end() => EQSD_refl())
  | SD_missing_good(left_diff) =>
    (case+ right of
     | SD_present(_, _, _, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_garbled_req(_, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_garbled_opt(_, _, _, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_missing_good(_) => EQSD_refl())
  | SD_missing_bad(left_diff) =>
    (case+ right of
     | SD_bad_req() => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_bad_opt(_, _) => (case+ left_diff of TAGDIFF_mk() =/=> ())
     | SD_missing_bad(_) => EQSD_refl())

primplement sdec_functional {known,group_specs}{chunks}{chunk_count}{left_result,right_result} (count, left, right) = _sdec_functional(count, left, right)


(* XENC(kept, chunks): chunks are the chunks kept in kept, written back *)
#pub dataprop XENC(extras, pchunks) =
  | XENC_nil(ex_nil(), pnil())
  | {tag,data:bytes}{kept:extras}{rest:pchunks}
    XENC_cons(ex_cons(tag, data, kept), pgood(tag, data, rest)) of (ANC(tag), XENC(kept, rest))

(* SENC(group_specs, group_values, kept, chunks): chunks are the chunks of the groups of specs
   holding group_values, then those kept in kept *)
#pub dataprop SENC(specs, gvals, extras, pchunks) =
  | {kept:extras}{chunks:pchunks} SENC_nil(gs_nil(), gv_nil(), kept, chunks) of XENC(kept, chunks)
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{field_values:fvals}{group_values:gvals}{kept:extras}{data:bytes}{data_len:nat}{rest:pchunks}
    SENC_cons(gs_cons(group_tag, kinds, requirement, defaults, more), gv_cons(field_values, group_values), kept, pgood(group_tag, data, rest))
    of (LEN(data, data_len), FENC(kinds, field_values, data), SENC(more, group_values, kept, rest))

#pub prfun xenc_xdec {known:specs}{kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), XENC(kept, chunks))
  : XDEC(known, chunks, sd_ok(gv_nil(), kept))

prfun _xenc_xdec {known:specs}{kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), encoding: XENC(kept, chunks))
  : XDEC(known, chunks, sd_ok(gv_nil(), kept)) =
  case+ encoding of
  | XENC_nil() => XD_nil()
  | XENC_cons(ancillary, rest) => let
      prval PCN_good(count1) = count
    in XD_anc(ancillary, _xenc_xdec(count1, rest), PREPX_ok()) end

primplement xenc_xdec {known}{kept}{chunks}{chunk_count} (count, encoding) = _xenc_xdec(count, encoding)

#pub dataprop EQG(gvals, gvals) =
  | {group_values:gvals} EQG_refl(group_values, group_values)

#pub prfun xdec_ok_nil {known:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), XDEC(known, chunks, sd_ok(group_values, kept)))
  : EQG(group_values, gv_nil())

prfun _xdec_ok_nil {known:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), decoding: XDEC(known, chunks, sd_ok(group_values, kept)))
  : EQG(group_values, gv_nil()) =
  case+ decoding of
  | XD_nil() => EQG_refl()
  | XD_anc(_, rest, PREPX_ok()) => let
      prval PCN_good(count1) = count
    in _xdec_ok_nil(count1, rest) end
  | XD_anc_lost(_, _, pp) => (case+ pp of PREPT_ok() =/=> () | PREPT_loss() =/=> () | PREPT_fail() =/=> ())

primplement xdec_ok_nil {known}{group_values}{kept}{chunks}{chunk_count} (count, decoding) = _xdec_ok_nil(count, decoding)

#pub prfun xdec_xenc {known:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), XDEC(known, chunks, sd_ok(group_values, kept)))
  : XENC(kept, chunks)

prfun _xdec_xenc {known:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), decoding: XDEC(known, chunks, sd_ok(group_values, kept)))
  : XENC(kept, chunks) =
  case+ decoding of
  | XD_nil() => XENC_nil()
  | XD_anc(ancillary, rest, PREPX_ok()) => let
      prval PCN_good(count1) = count
    in XENC_cons(ancillary, _xdec_xenc(count1, rest)) end
  | XD_anc_lost(_, _, prepend) => (case+ prepend of PREPT_ok() =/=> () | PREPT_loss() =/=> () | PREPT_fail() =/=> ())

primplement xdec_xenc {known}{group_values}{kept}{chunks}{chunk_count} (count, decoding) = _xdec_xenc(count, decoding)

#pub prfun senc_sdec {known,group_specs:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), SENC(group_specs, group_values, kept, chunks))
  : SDEC(known, group_specs, chunks, sd_ok(group_values, kept))

prfun _senc_sdec {known,group_specs:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), encoding: SENC(group_specs, group_values, kept, chunks))
  : SDEC(known, group_specs, chunks, sd_ok(group_values, kept)) =
  case+ encoding of
  | SENC_nil(extras_encoding) => SD_nil(xenc_xdec(count, extras_encoding))
  | SENC_cons(length_proof, field_encoding, rest) => let
      prval PCN_good(count1) = count
    in SD_present(length_proof, fenc_fdec(length_proof, field_encoding), _senc_sdec(count1, rest), PREPV_ok()) end

primplement senc_sdec {known,group_specs}{group_values}{kept}{chunks}{chunk_count} (count, encoding) = _senc_sdec(count, encoding)

#pub prfun sdec_senc {known,group_specs:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), SDEC(known, group_specs, chunks, sd_ok(group_values, kept)))
  : SENC(group_specs, group_values, kept, chunks)

prfun _sdec_senc {known,group_specs:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), decoding: SDEC(known, group_specs, chunks, sd_ok(group_values, kept)))
  : SENC(group_specs, group_values, kept, chunks) =
  case+ decoding of
  | SD_nil(extras_decoding) => (case+ xdec_ok_nil(count, extras_decoding) of EQG_refl() => SENC_nil(xdec_xenc(count, extras_decoding)))
  | SD_present(length_proof, field_decoding, rest, PREPV_ok()) => let
      prval PCN_good(count1) = count
    in SENC_cons(length_proof, fdec_fenc(length_proof, field_decoding), _sdec_senc(count1, rest)) end
  | SD_garbled_opt(_, _, _, prepend) => (case+ prepend of PREPL_ok() =/=> () | PREPL_loss() =/=> () | PREPL_fail() =/=> ())
  | SD_bad_opt(_, prepend) => (case+ prepend of PREPL_ok() =/=> () | PREPL_loss() =/=> () | PREPL_fail() =/=> ())

primplement sdec_senc {known,group_specs}{group_values}{kept}{chunks}{chunk_count} (count, decoding) = _sdec_senc(count, decoding)


(* The groups of a record, at run time, group_count of them: each one's tag, the
   kinds of its fields, whether it is needed, and its values when lost *)
#pub datatype modev(mode) =
  | ModeReq(m_req())
  | ModeOpt(m_opt())

#pub datavtype specsv(specs, int) =
  | SPV_nil(gs_nil(), 0)
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{group_count,field_count:nat | field_count < 1000}
    SPV_cons(gs_cons(group_tag, kinds, requirement, defaults, more), group_count+1) of (TAGNOT(group_tag) | blist(group_tag, 4), layoutv(kinds, field_count), modev(requirement), fvalsv(kinds, defaults, field_count), specsv(more, group_count))

#pub fun specsv_free {group_specs:specs}{group_count:nat} (specs: specsv(group_specs, group_count)): void

implement specsv_free {group_specs}{group_count} (specs) = let
  fun free_specs {group_specs:specs}{group_count:nat} .<group_count>. (specs: specsv(group_specs, group_count)): void =
    case+ specs of
    | ~SPV_nil() => ()
    | ~SPV_cons(_ | tag, layout, _, default, more) => let
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
    | SPV_cons(tag_proof | tag, layout, mode, default, more) =>
      SPV_cons(tag_proof | blist_copy(tag), layoutv_copy(layout), mode, fvalsv_copy(default), copy_specs(more))
in copy_specs(specs) end

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
#pub datavtype extrasv(extras, int) =
  | EXV_nil(ex_nil(), 0)
  | {tag,data:bytes}{kept:extras}{data_len,extras_count:nat | data_len < 1048576}
    EXV_cons(ex_cons(tag, data, kept), extras_count+1) of (ANC(tag) | blist(tag, 4), blist(data, data_len), extrasv(kept, extras_count))

#pub fun extrasv_free {kept:extras}{extras_count:nat} (extras: extrasv(kept, extras_count)): void

implement extrasv_free {kept}{extras_count} (extras) = let
  fun free_extras {kept:extras}{extras_count:nat} .<extras_count>. (extras: extrasv(kept, extras_count)): void =
    case+ extras of
    | ~EXV_nil() => ()
    | ~EXV_cons(_ | tag, data, more) => let
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

#pub datatype causev(cause) =
  | CausDamaged(cause_damaged())
  | CausNewer(cause_newer())

(* What reading the groups of a record comes to *)
#pub datavtype schemaread(sdres, specs) =
  | {group_specs:specs}{group_values:gvals}{kept:extras}{values_count,extras_count:nat}
    SDR_ok(sd_ok(group_values, kept), group_specs) of (gvalsv(group_specs, group_values, values_count), extrasv(kept, extras_count))
  | {group_specs:specs}{group_values:gvals}{kept:extras}{lost_tags:lost}{values_count,extras_count,lost_count:nat}
    SDR_loss(sd_loss(group_values, kept, lost_tags), group_specs) of (gvalsv(group_specs, group_values, values_count), extrasv(kept, extras_count), lostv(lost_tags, lost_count))
  | {group_specs:specs}{reason:cause} SDR_fail(sd_fail(reason), group_specs) of causev(reason)


#pub prfun xenc_allgood {kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), XENC(kept, chunks)): ALLGOOD(chunk_count, chunks)

prfun _xenc_allgood {kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), encoding: XENC(kept, chunks)): ALLGOOD(chunk_count, chunks) =
  case+ encoding of
  | XENC_nil() => (case+ count of PCN_nil() => ALLGOOD_nil())
  | XENC_cons(_, rest) => (case+ count of PCN_good(count1) => ALLGOOD_cons(_xenc_allgood(count1, rest)))

primplement xenc_allgood {kept}{chunks}{chunk_count} (count, encoding) = _xenc_allgood(count, encoding)

#pub prfun senc_allgood {group_specs:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} (PCN(chunk_count, chunks), SENC(group_specs, group_values, kept, chunks)): ALLGOOD(chunk_count, chunks)

prfun _senc_allgood {group_specs:specs}{group_values:gvals}{kept:extras}{chunks:pchunks}{chunk_count:nat} .<chunk_count>. (count: PCN(chunk_count, chunks), encoding: SENC(group_specs, group_values, kept, chunks)): ALLGOOD(chunk_count, chunks) =
  case+ encoding of
  | SENC_nil(xe) => xenc_allgood(count, xe)
  | SENC_cons(_, _, rest) => (case+ count of PCN_good(count1) => ALLGOOD_cons(_senc_allgood(count1, rest)))

primplement senc_allgood {group_specs}{group_values}{kept}{chunks}{chunk_count} (count, encoding) = _senc_allgood(count, encoding)

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
    | SPV_cons(_ | group_tag, _, _, _, more) =>
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

(* Reading what follows the known groups *)
fun xdec_read {known:specs}{known_count:nat}{chunks:pchunks}{chunk_count:nat} .<chunk_count>.
  (count: PCN(chunk_count, chunks), known: !specsv(known, known_count), chunk_list: chunklist(chunks, chunk_count))
  : [result:sdres] (XDEC(known, chunks, result) | schemaread(result, gs_nil())) =
  case+ chunk_list of
  | ~CL_nil() => (XD_nil() | SDR_ok(GVV_nil(), EXV_nil()))
  | ~CL_good(_ | tag, data, rest) => let
      prval PCN_good(count1) = count
    in
      case+ _tag_class(tag) of
      | ~IsAnc(ancillary | ) => let
          val (sub | rest_read) = xdec_read(count1, known, rest)
        in
          case+ rest_read of
          | ~SDR_ok(~GVV_nil(), extras) =>
            (XD_anc(ancillary, sub, PREPX_ok()) | SDR_ok(GVV_nil(), EXV_cons(ancillary | tag, data, extras)))
          | ~SDR_loss(~GVV_nil(), extras, lost) =>
            (XD_anc(ancillary, sub, PREPX_loss()) | SDR_loss(GVV_nil(), EXV_cons(ancillary | tag, data, extras), lost))
          | ~SDR_fail(reason) => let
              val () = blist_free(tag)
              val () = blist_free(data)
            in (XD_anc(ancillary, sub, PREPX_fail()) | SDR_fail(reason)) end
        end
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
          | ~SDR_ok(~GVV_nil(), extras) =>
            (XD_anc_lost(ancillary, sub, PREPT_ok()) | SDR_loss(GVV_nil(), extras, LTV_cons(tag, LTV_nil())))
          | ~SDR_loss(~GVV_nil(), extras, lost) =>
            (XD_anc_lost(ancillary, sub, PREPT_loss()) | SDR_loss(GVV_nil(), extras, LTV_cons(tag, lost)))
          | ~SDR_fail(reason) => let
              val () = blist_free(tag)
            in (XD_anc_lost(ancillary, sub, PREPT_fail()) | SDR_fail(reason)) end
        end
      | ~IsCrit(critical | ) => let
          val () = chunklist_free(rest)
          val () = blist_free(tag)
        in (XD_crit_bad(critical) | SDR_fail(CausDamaged())) end
    end


(* Reading the groups of a record, then what follows them *)
fun sdec_read {known,group_specs:specs}{known_count,spec_count:nat}{chunks:pchunks}{chunk_count:nat} .<chunk_count>.
  (count: PCN(chunk_count, chunks), known: !specsv(known, known_count), specs: !specsv(group_specs, spec_count), chunk_list: chunklist(chunks, chunk_count))
  : [result:sdres] (SDEC(known, group_specs, chunks, result) | schemaread(result, group_specs)) =
  case+ specs of
  | SPV_nil() => let
      val (sub | fields_result) = xdec_read(count, known, chunk_list)
    in (SD_nil(sub) | fields_result) end
  | SPV_cons(_ | group_tag, layout, mode, default, more) =>
    (case+ chunk_list of
     | ~CL_nil() => (SD_missing_end() | SDR_fail(CausDamaged()))
     | ~CL_good(_ | tag, data, rest) => let
         prval PCN_good(count1) = count
       in
         case+ _tag_compare(tag, group_tag) of
         | ~TagDiff(different | ) => let
             val () = blist_free(tag)
             val () = blist_free(data)
             val () = chunklist_free(rest)
           in (SD_missing_good(different) | SDR_fail(CausDamaged())) end
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
                 | ~SDR_ok(later_values, later_extras) => (SD_present(len, field_proof, sub, PREPV_ok()) | SDR_ok(GVV_cons(field_values, later_values), later_extras))
                 | ~SDR_loss(later_values, later_extras, lost) => (SD_present(len, field_proof, sub, PREPV_loss()) | SDR_loss(GVV_cons(field_values, later_values), later_extras, lost))
                 | ~SDR_fail(reason) => let val () = fvalsv_free(field_values) in (SD_present(len, field_proof, sub, PREPV_fail()) | SDR_fail(reason)) end
               end
             | ~FDR_bad() =>
               (case+ mode of
                | ModeReq() => let val () = chunklist_free(rest) in (SD_garbled_req(len, field_proof) | SDR_fail(CausDamaged())) end
                | ModeOpt() => let
                    val (sub | rest_read) = sdec_read(count1, known, more, rest)
                  in
                    case+ rest_read of
                    | ~SDR_ok(later_values, later_extras) =>
                      (SD_garbled_opt(len, field_proof, sub, PREPL_ok())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), LTV_nil())))
                    | ~SDR_loss(later_values, later_extras, lost) =>
                      (SD_garbled_opt(len, field_proof, sub, PREPL_loss())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), lost)))
                    | ~SDR_fail(reason) => (SD_garbled_opt(len, field_proof, sub, PREPL_fail()) | SDR_fail(reason))
                  end)
           end
       end
     | ~CL_bad(tag, rest) => let
         prval PCN_bad(count1) = count
       in
         case+ _tag_compare(tag, group_tag) of
         | ~TagDiff(different | ) => let
             val () = blist_free(tag)
             val () = chunklist_free(rest)
           in (SD_missing_bad(different) | SDR_fail(CausDamaged())) end
         | ~TagSame(EQB_refl() | ) => let
             val () = blist_free(tag)
           in
             case+ mode of
             | ModeReq() => let val () = chunklist_free(rest) in (SD_bad_req() | SDR_fail(CausDamaged())) end
             | ModeOpt() => let
                 val (sub | rest_read) = sdec_read(count1, known, more, rest)
               in
                 case+ rest_read of
                 | ~SDR_ok(later_values, later_extras) =>
                   (SD_bad_opt(sub, PREPL_ok())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), LTV_nil())))
                 | ~SDR_loss(later_values, later_extras, lost) =>
                   (SD_bad_opt(sub, PREPL_loss())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), later_values), later_extras, LTV_cons(blist_copy(group_tag), lost)))
                 | ~SDR_fail(reason) => (SD_bad_opt(sub, PREPL_fail()) | SDR_fail(reason))
               end
           end
       end)


prfn _anc_tagnot {tag:bytes} (ancillary: ANC(tag)): TAGNOT(tag) =
  case+ ancillary of ANC_mk() => TAGNOT_mk()

(* The chunks that hold the kept chunks, with the proof *)
fun _extras_write {kept:extras}{extras_count:nat} .<extras_count>. (extras: !extrasv(kept, extras_count))
  : [chunks:pchunks][chunk_count:nat] (XENC(kept, chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks) | chunklist(chunks, chunk_count)) =
  case+ extras of
  | EXV_nil() => (XENC_nil(), ALLGOOD_nil(), PCN_nil() | CL_nil())
  | EXV_cons(ancillary | tag, data, more) => let
      val (encoding, good, count | rest) = _extras_write(more)
    in
      (XENC_cons(ancillary, encoding), ALLGOOD_cons(good), PCN_good(count)
       | CL_good(_anc_tagnot(ancillary) | blist_copy(tag), blist_copy(data), rest))
    end

(* The chunks of a record's groups and kept chunks, with the proof *)
#pub fun schema_write {group_specs:specs}{group_values:gvals}{kept:extras}{spec_count,values_count,extras_count:nat}
  (specs: !specsv(group_specs, spec_count), group_values: !gvalsv(group_specs, group_values, values_count), extras: !extrasv(kept, extras_count))
  : [chunks:pchunks][chunk_count:nat] (SENC(group_specs, group_values, kept, chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks) | chunklist(chunks, chunk_count))

implement schema_write {group_specs}{group_values}{kept}{spec_count,values_count,extras_count} (specs, group_values, extras) = let
  fun write_groups {group_specs:specs}{group_values:gvals}{kept:extras}{spec_count,values_count,extras_count:nat} .<spec_count>.
    (specs: !specsv(group_specs, spec_count), group_values: !gvalsv(group_specs, group_values, values_count), extras: !extrasv(kept, extras_count))
    : [chunks:pchunks][chunk_count:nat] (SENC(group_specs, group_values, kept, chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks) | chunklist(chunks, chunk_count)) =
    case+ specs of
    | SPV_nil() => let
        prval GVV_nil() = group_values
        val (extras_encoding, good, count | chunk_list) = _extras_write(extras)
      in (SENC_nil(extras_encoding), good, count | chunk_list) end
    | SPV_cons(tag_proof | group_tag, _, _, _, more) =>
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
  : [result:sdres] (SDEC(group_specs, group_specs, chunks, result) | schemaread(result, group_specs))

implement schema_read {group_specs}{spec_count}{chunks}{chunk_count} (count, specs, chunk_list) = let
  val known = specsv_copy(specs)
  val result = sdec_read(count, known, specs, chunk_list)
  val () = specsv_free(known)
in result end

end
