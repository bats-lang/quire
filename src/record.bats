(* record -- a stored record: its magic, kind and versions, then its
   chunks. The laws of the codec are here: what is written is read back
   as it was, and what is read is what is written *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "bytes.sats"
staload "crc.sats"
staload "chunk.sats"
staload "seq.sats"
staload "fields.sats"
staload "schema.sats"

(* the identity of a record: the version of the format it was written
   in, the least version that can read it, its groups' values and the
   chunks kept *)
#pub datasort rx =
  | rx_mk of (int, int, gvals, extras)

(* what reading a record comes to *)
#pub datasort recres =
  | rr_ok of (rx)
  | rr_loss of (rx, lost)
  | rr_notquire of ()      (* not a record of Quire's *)
  | rr_newer of ()         (* written by a newer Quire, which this one cannot read *)
  | rr_damaged of ()

#pub dataprop EQRR(recres, recres) =
  | {outcome:recres} EQRR_refl(outcome, outcome)

(* the version of the format this Quire reads and writes *)
#pub stadef READER = 1

(* ENCODES(spec_list, kind, record_value, octets): octets is the record record_value of the groups spec_list, of this
   kind: "QREC", the kind, the version and the least version, then the
   chunks, then the end chunk *)
#pub dataprop ENCODES(specs, int, rx, bytes) =
  | {spec_list:specs}{kind,format_version,least_version:int | 0 <= kind; kind < 256; 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER}
    {vals:gvals}{kept_extras:extras}{chunks:pchunks}{chunk_count:nat}{body,octets:bytes}
    ENCODES_mk(spec_list, kind, rx_mk(format_version, least_version, vals, kept_extras), octets)
    of (SENC(spec_list, vals, kept_extras, chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks), CHAINS(chunk_count, chunks, body),
        APPEND(bcons(81, bcons(82, bcons(69, bcons(67, bcons(kind, bcons(format_version, bcons(least_version, bnil()))))))), body, octets))


(* MAGICDIFF(m): four bytes that are not "QREC" *)
#pub dataprop MAGICDIFF(bytes) =
  | {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= magic2; magic2 < 256; 0 <= magic3; magic3 < 256;
       magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67}
    MAGICDIFF_mk(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil())))))

(* PCN of one list is one number *)
#pub prfun pcn_functional {chunks:pchunks}{first_count,second_count:nat} (PCN(first_count, chunks), PCN(second_count, chunks)): EQI(first_count, second_count)

prfun _pcn_functional {chunks:pchunks}{first_count,second_count:nat} .<first_count>. (first_count_proof: PCN(first_count, chunks), second_count_proof: PCN(second_count, chunks)): EQI(first_count, second_count) =
  case+ first_count_proof of
  | PCN_nil() => (case+ second_count_proof of PCN_nil() => EQI_refl())
  | PCN_good(first_rest_count) => (case+ second_count_proof of PCN_good(second_rest_count) => (case+ _pcn_functional(first_rest_count, second_rest_count) of EQI_refl() => EQI_refl()))
  | PCN_bad(first_rest_count) => (case+ second_count_proof of PCN_bad(second_rest_count) => (case+ _pcn_functional(first_rest_count, second_rest_count) of EQI_refl() => EQI_refl()))

primplement pcn_functional {chunks}{first_count,second_count} (first_count_proof, second_count_proof) = _pcn_functional(first_count_proof, second_count_proof)

(* FIN(spec_list, format_version, least_version, seq_outcome, outcome): the chunks read come to outcome *)
#pub dataprop FIN(specs, int, int, seqres, recres) =
  | {spec_list:specs}{format_version,least_version:int}{cause:seqcause} FIN_seq(spec_list, format_version, least_version, sq_fail(cause), rr_damaged())
  | {spec_list:specs}{format_version,least_version:int}{vals:gvals}{kept_extras:extras}{chunks:pchunks}{chunk_count:nat}
    FIN_ok(spec_list, format_version, least_version, sq_ok(chunks), rr_ok(rx_mk(format_version, least_version, vals, kept_extras)))
    of (PCN(chunk_count, chunks), SDEC(spec_list, spec_list, chunks, sd_ok(vals, kept_extras)))
  | {spec_list:specs}{format_version,least_version:int}{vals:gvals}{kept_extras:extras}{lost_groups:lost}{chunks:pchunks}{chunk_count:nat}
    FIN_loss(spec_list, format_version, least_version, sq_ok(chunks), rr_loss(rx_mk(format_version, least_version, vals, kept_extras), lost_groups))
    of (PCN(chunk_count, chunks), SDEC(spec_list, spec_list, chunks, sd_loss(vals, kept_extras, lost_groups)))
  | {spec_list:specs}{format_version,least_version:int}{chunks:pchunks}{chunk_count:nat}
    FIN_damaged(spec_list, format_version, least_version, sq_ok(chunks), rr_damaged())
    of (PCN(chunk_count, chunks), SDEC(spec_list, spec_list, chunks, sd_fail(cause_damaged())))
  | {spec_list:specs}{format_version,least_version:int}{chunks:pchunks}{chunk_count:nat}
    FIN_newer(spec_list, format_version, least_version, sq_ok(chunks), rr_newer())
    of (PCN(chunk_count, chunks), SDEC(spec_list, spec_list, chunks, sd_fail(cause_newer())))

#pub prfun falsep_eqrr {first_outcome,second_outcome:recres} (FALSEP()): EQRR(first_outcome, second_outcome)

primplement falsep_eqrr {first_outcome,second_outcome} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

#pub prfun fin_functional {spec_list:specs}{format_version,least_version:int}{seq_outcome:seqres}{first_outcome,second_outcome:recres} (FIN(spec_list, format_version, least_version, seq_outcome, first_outcome), FIN(spec_list, format_version, least_version, seq_outcome, second_outcome)): EQRR(first_outcome, second_outcome)

primplement fin_functional {spec_list}{format_version,least_version}{seq_outcome}{first_outcome,second_outcome} (first_fin, second_fin) =
  case+ first_fin of
  | FIN_seq() => (case+ second_fin of FIN_seq() => EQRR_refl())
  | FIN_ok(first_count, first_sdec) =>
    (case+ second_fin of
     | FIN_ok(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() => EQRR_refl()) end
     | FIN_loss(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_damaged(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_newer(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end)
  | FIN_loss(first_count, first_sdec) =>
    (case+ second_fin of
     | FIN_ok(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_loss(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() => EQRR_refl()) end
     | FIN_damaged(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_newer(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end)
  | FIN_damaged(first_count, first_sdec) =>
    (case+ second_fin of
     | FIN_ok(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_loss(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_damaged(_, _) => EQRR_refl()
     | FIN_newer(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end)
  | FIN_newer(first_count, first_sdec) =>
    (case+ second_fin of
     | FIN_ok(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_loss(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_damaged(second_count, second_sdec) => let
         prval EQI_refl() = pcn_functional(first_count, second_count)
       in (case+ sdec_functional(first_count, first_sdec, second_sdec) of EQSD_refl() =/=> ()) end
     | FIN_newer(_, _) => EQRR_refl())


(* DECODES(spec_list, kind, octets, outcome): reading octets as a record of this kind and these
   groups comes to outcome *)
#pub dataprop DECODES(specs, int, bytes, recres) =
  | {spec_list:specs}{kind:int}{octets:bytes}
    DECODES_short(spec_list, kind, octets, rr_notquire()) of SHORT(4, octets)
  | {spec_list:specs}{kind:int}{octets,magic_bytes,rest:bytes}
    DECODES_magic(spec_list, kind, octets, rr_notquire()) of (TAKE(4, octets, magic_bytes, rest), MAGICDIFF(magic_bytes))
  | {spec_list:specs}{kind:int}{octets,rest:bytes}
    DECODES_header_short(spec_list, kind, octets, rr_damaged())
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest), SHORT(3, rest))
  | {spec_list:specs}{kind:int}{kind_byte,format_version,least_version:int | 0 <= kind_byte; kind_byte < 256; 0 <= format_version; format_version < 256; READER < least_version; least_version < 256}{octets,rest,body:bytes}
    DECODES_newer(spec_list, kind, octets, rr_newer())
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kind_byte, bcons(format_version, bcons(least_version, bnil()))), body))
  | {spec_list:specs}{kind:int}{kind_byte,format_version,least_version:int | 0 <= kind_byte; kind_byte < 256; 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER; kind_byte != kind}{octets,rest,body:bytes}
    DECODES_kind(spec_list, kind, octets, rr_damaged())
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kind_byte, bcons(format_version, bcons(least_version, bnil()))), body))
  | {spec_list:specs}{kind,format_version,least_version:int | 0 <= kind; kind < 256; 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER}
    {octets,rest,body:bytes}{seq_outcome:seqres}{outcome:recres}
    DECODES_body(spec_list, kind, octets, outcome)
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kind, bcons(format_version, bcons(least_version, bnil()))), body),
        SEQ(body, seq_outcome), FIN(spec_list, format_version, least_version, seq_outcome, outcome))


#pub prfun decodes_functional {spec_list:specs}{kind:int}{octets:bytes}{byte_count:nat}{first_outcome,second_outcome:recres}
  (LEN(octets, byte_count), DECODES(spec_list, kind, octets, first_outcome), DECODES(spec_list, kind, octets, second_outcome)): EQRR(first_outcome, second_outcome)

primplement decodes_functional {spec_list}{kind}{octets}{byte_count}{first_outcome,second_outcome} (whole, first_decode, second_decode) =
  case+ first_decode of
  | DECODES_short(first_short) =>
    (case+ second_decode of
     | DECODES_short(_) => EQRR_refl()
     | DECODES_magic(second_magic_take, _) => falsep_eqrr(take_not_short(second_magic_take, first_short))
     | DECODES_header_short(second_magic_take, _) => falsep_eqrr(take_not_short(second_magic_take, first_short))
     | DECODES_newer(second_magic_take, _) => falsep_eqrr(take_not_short(second_magic_take, first_short))
     | DECODES_kind(second_magic_take, _) => falsep_eqrr(take_not_short(second_magic_take, first_short))
     | DECODES_body(second_magic_take, _, _, _) => falsep_eqrr(take_not_short(second_magic_take, first_short)))
  | DECODES_magic(first_magic_take, first_magic_diff) =>
    (case+ second_decode of
     | DECODES_short(second_short) => falsep_eqrr(take_not_short(first_magic_take, second_short))
     | DECODES_magic(_, _) => EQRR_refl()
     | DECODES_header_short(second_magic_take, _) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ first_magic_diff of MAGICDIFF_mk() =/=> ()) end
     | DECODES_newer(second_magic_take, _) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ first_magic_diff of MAGICDIFF_mk() =/=> ()) end
     | DECODES_kind(second_magic_take, _) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ first_magic_diff of MAGICDIFF_mk() =/=> ()) end
     | DECODES_body(second_magic_take, _, _, _) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ first_magic_diff of MAGICDIFF_mk() =/=> ()) end)
  | DECODES_header_short(first_magic_take, first_short) =>
    (case+ second_decode of
     | DECODES_short(second_short) => falsep_eqrr(take_not_short(first_magic_take, second_short))
     | DECODES_magic(second_magic_take, second_magic_diff) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ second_magic_diff of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(_, _) => EQRR_refl()
     | DECODES_newer(second_magic_take, second_header_take) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in falsep_eqrr(take_not_short(second_header_take, first_short)) end
     | DECODES_kind(second_magic_take, second_header_take) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in falsep_eqrr(take_not_short(second_header_take, first_short)) end
     | DECODES_body(second_magic_take, second_header_take, _, _) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in falsep_eqrr(take_not_short(second_header_take, first_short)) end)
  | DECODES_newer(first_magic_take, first_header_take) =>
    (case+ second_decode of
     | DECODES_short(second_short) => falsep_eqrr(take_not_short(first_magic_take, second_short))
     | DECODES_magic(second_magic_take, second_magic_diff) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ second_magic_diff of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(second_magic_take, second_short) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in falsep_eqrr(take_not_short(first_header_take, second_short)) end
     | DECODES_newer(_, _) => EQRR_refl()
     | DECODES_kind(second_magic_take, second_header_take) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
         prval SAME2_refl() = take_functional(first_header_take, second_header_take)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_body(second_magic_take, second_header_take, _, _) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
         prval SAME2_refl() = take_functional(first_header_take, second_header_take)
       in falsep_eqrr(contradiction{0}()) end)
  | DECODES_kind(first_magic_take, first_header_take) =>
    (case+ second_decode of
     | DECODES_short(second_short) => falsep_eqrr(take_not_short(first_magic_take, second_short))
     | DECODES_magic(second_magic_take, second_magic_diff) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ second_magic_diff of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(second_magic_take, second_short) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in falsep_eqrr(take_not_short(first_header_take, second_short)) end
     | DECODES_newer(second_magic_take, second_header_take) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
         prval SAME2_refl() = take_functional(first_header_take, second_header_take)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_kind(_, _) => EQRR_refl()
     | DECODES_body(second_magic_take, second_header_take, _, _) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
         prval SAME2_refl() = take_functional(first_header_take, second_header_take)
       in falsep_eqrr(contradiction{0}()) end)
  | DECODES_body(first_magic_take, first_header_take, first_seq, first_fin) =>
    (case+ second_decode of
     | DECODES_short(second_short) => falsep_eqrr(take_not_short(first_magic_take, second_short))
     | DECODES_magic(second_magic_take, second_magic_diff) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in (case+ second_magic_diff of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(second_magic_take, second_short) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
       in falsep_eqrr(take_not_short(first_header_take, second_short)) end
     | DECODES_newer(second_magic_take, second_header_take) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
         prval SAME2_refl() = take_functional(first_header_take, second_header_take)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_kind(second_magic_take, second_header_take) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
         prval SAME2_refl() = take_functional(first_header_take, second_header_take)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_body(second_magic_take, second_header_take, second_seq, second_fin) => let
         prval SAME2_refl() = take_functional(first_magic_take, second_magic_take)
         prval SAME2_refl() = take_functional(first_header_take, second_header_take)
         prval after_magic = take_rest_len(first_magic_take, whole)
         prval body_len = take_rest_len(first_header_take, after_magic)
         prval EQSQ_refl() = seq_functional(body_len, first_seq, second_seq)
       in fin_functional(first_fin, second_fin) end)


(* a record written is read back as it was *)
#pub prfun encodes_decodes {spec_list:specs}{kind:int}{record_value:rx}{octets:bytes} (ENCODES(spec_list, kind, record_value, octets)): DECODES(spec_list, kind, octets, rr_ok(record_value))

primplement encodes_decodes {spec_list}{kind}{record_value}{octets} (encoded) =
  case+ encoded of
  | ENCODES_mk(senc, good, count, chains, appended) => let
      prval APPEND_cons(append1) = appended
      prval APPEND_cons(append2) = append1
      prval APPEND_cons(append3) = append2
      prval APPEND_cons(append4) = append3
      prval APPEND_cons(append5) = append4
      prval APPEND_cons(append6) = append5
      prval APPEND_cons(append7) = append6
      prval APPEND_nil() = append7
      prval magic = TAKE_succ(TAKE_succ(TAKE_succ(TAKE_succ(TAKE_zero()))))
      prval header = TAKE_succ(TAKE_succ(TAKE_succ(TAKE_zero())))
    in DECODES_body(magic, header, chains_seq(chains), FIN_ok(count, senc_sdec(count, senc))) end


(* and a record read is a record written *)
#pub prfun decodes_encodes {spec_list:specs}{kind:int}{record_value:rx}{octets:bytes} (DECODES(spec_list, kind, octets, rr_ok(record_value))): ENCODES(spec_list, kind, record_value, octets)

primplement decodes_encodes {spec_list}{kind}{record_value}{octets} (decoded) =
  case+ decoded of
  | DECODES_body(magic_take, header_take, seq_proof, FIN_ok(count, sdec)) => let
      prval senc = sdec_senc(count, sdec)
      prval good = senc_allgood(count, senc)
      prval chains = seq_chains(good, seq_proof)
      prval (app_magic, _) = take_append(magic_take)
      prval (app_header, _) = take_append(header_take)
      prval (front, whole) = append_assoc_rev(app_header, app_magic)
      prval literal = APPEND_cons(APPEND_cons(APPEND_cons(APPEND_cons(APPEND_nil()))))
      prval EQB_refl() = append_functional(literal, front)
    in ENCODES_mk(senc, good, count, chains, whole) end


(* A record read, at run time *)
#pub datavtype recread(recres, specs) =
  | {spec_list:specs}{format_version,least_version:int | 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER}{vals:gvals}{kept_extras:extras}{value_count,extra_count:nat}
    RR_ok(rr_ok(rx_mk(format_version, least_version, vals, kept_extras)), spec_list) of (int format_version, int least_version, gvalsv(spec_list, vals, value_count), extrasv(kept_extras, extra_count))
  | {spec_list:specs}{format_version,least_version:int | 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER}{vals:gvals}{kept_extras:extras}{lost_groups:lost}{value_count,extra_count,lost_count:nat}
    RR_loss(rr_loss(rx_mk(format_version, least_version, vals, kept_extras), lost_groups), spec_list) of (int format_version, int least_version, gvalsv(spec_list, vals, value_count), extrasv(kept_extras, extra_count), lostv(lost_groups, lost_count))
  | {spec_list:specs} RR_notquire(rr_notquire(), spec_list)
  | {spec_list:specs} RR_newer(rr_newer(), spec_list)
  | {spec_list:specs} RR_damaged(rr_damaged(), spec_list)

(* A record written, with the proof that it is the one *)
#pub fun record_write {spec_list:specs}{kind,format_version,least_version:int | 0 <= kind; kind < 256; 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER}
  {vals:gvals}{kept_extras:extras}{spec_count,value_count,extra_count:nat}
  (specs: !specsv(spec_list, spec_count), kind: int kind, format_version: int format_version, least_version: int least_version, vals: !gvalsv(spec_list, vals, value_count), extras: !extrasv(kept_extras, extra_count))
  : [octets:bytes][written_len:nat] (ENCODES(spec_list, kind, rx_mk(format_version, least_version, vals, kept_extras), octets) | blist(octets, written_len))

implement record_write {spec_list}{kind,format_version,least_version}{vals}{kept_extras}{spec_count,value_count,extra_count} (specs, kind, format_version, least_version, vals, extras) = let
  val (senc, good, count | chunk_list) = schema_write(specs, vals, extras)
  val (chains | body) = seq_write(good | chunk_list)
  val () = chunklist_free(chunk_list)
  val header = blist_cons(81, blist_cons(82, blist_cons(69, blist_cons(67,
               blist_cons(kind, blist_cons(format_version, blist_cons(least_version, blist_nil())))))))
  val (appended | record_bytes) = blist_append(header, body)
in (ENCODES_mk(senc, good, count, chains, appended) | record_bytes) end


prfn _not_quire_proof {spec_list:specs}{kind:int}{octets,magic_bytes,rest:bytes} (magic_take: TAKE(4, octets, magic_bytes, rest), magic_diff: MAGICDIFF(magic_bytes))
  : DECODES(spec_list, kind, octets, rr_notquire()) = DECODES_magic(magic_take, magic_diff)

fn _not_quire {spec_list:specs}{kind:int}{octets,magic_bytes,rest:bytes}{rest_len:nat} (magic_take: TAKE(4, octets, magic_bytes, rest), magic_diff: MAGICDIFF(magic_bytes), rest: blist(rest, rest_len))
  : (DECODES(spec_list, kind, octets, rr_notquire()) | recread(rr_notquire(), spec_list)) = let
  val () = blist_free(rest)
in (DECODES_magic(magic_take, magic_diff) | RR_notquire()) end

(* A record read, with the proof of what it comes to *)
#pub fun record_read {spec_list:specs}{kind:int | 0 <= kind; kind < 256}{spec_count:nat}{octets:bytes}{byte_count:nat}
  (specs: !specsv(spec_list, spec_count), kind: int kind, list: blist(octets, byte_count))
  : [outcome:recres] (DECODES(spec_list, kind, octets, outcome) | recread(outcome, spec_list))

implement record_read {spec_list}{kind}{spec_count}{octets}{byte_count} (specs, kind, list) =
  case+ blist_take(4, list) of
  | ~TakeShort(short_proof | ) => (DECODES_short(short_proof) | RR_notquire())
  | ~TakeOk(magic_take | magic, rest) =>
    (case+ magic of
     | ~blist_cons(magic_byte0, ~blist_cons(magic_byte1, ~blist_cons(magic_byte2, ~blist_cons(magic_byte3, ~blist_nil())))) =>
       if magic_byte0 = 81 then if magic_byte1 = 82 then if magic_byte2 = 69 then if magic_byte3 = 67 then
         (case+ blist_take(3, rest) of
          | ~TakeShort(short_proof | ) => (DECODES_header_short(magic_take, short_proof) | RR_damaged())
          | ~TakeOk(header_take | header, body) =>
            (case+ header of
             | ~blist_cons(kind_byte, ~blist_cons(format_version, ~blist_cons(least_version, ~blist_nil()))) =>
               if least_version > 1 then let
                 val () = blist_free(body)
               in (DECODES_newer(magic_take, header_take) | RR_newer()) end
               else if kind_byte <> kind then let
                 val () = blist_free(body)
               in (DECODES_kind(magic_take, header_take) | RR_damaged()) end
               else let
                 val (seq_proof | seq_result) = seq_read(body)
               in
                 case+ seq_result of
                 | ~SR_fail() => (DECODES_body(magic_take, header_take, seq_proof, FIN_seq()) | RR_damaged())
                 | ~SR_ok(count | chunk_list) => let
                     val (schema_decode | schema_outcome) = schema_read(count, specs, chunk_list)
                   in
                     case+ schema_outcome of
                     | ~SDR_ok(vals, extras) => (DECODES_body(magic_take, header_take, seq_proof, FIN_ok(count, schema_decode)) | RR_ok(format_version, least_version, vals, extras))
                     | ~SDR_loss(vals, extras, lost) => (DECODES_body(magic_take, header_take, seq_proof, FIN_loss(count, schema_decode)) | RR_loss(format_version, least_version, vals, extras, lost))
                     | ~SDR_fail(CausDamaged()) => (DECODES_body(magic_take, header_take, seq_proof, FIN_damaged(count, schema_decode)) | RR_damaged())
                     | ~SDR_fail(CausNewer()) => (DECODES_body(magic_take, header_take, seq_proof, FIN_newer(count, schema_decode)) | RR_newer())
                   end
               end))
       else _not_quire(magic_take, MAGICDIFF_mk(), rest)
       else _not_quire(magic_take, MAGICDIFF_mk(), rest)
       else _not_quire(magic_take, MAGICDIFF_mk(), rest)
       else _not_quire(magic_take, MAGICDIFF_mk(), rest))

end
