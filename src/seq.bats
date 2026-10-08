(* seq -- a record's chunks, one after another, up to the end chunk *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "bytes.sats"
staload "crc.sats"
staload "chunk.sats"

(* the chunks of a record: those that were read whole, and those whose
   checksum was wrong (their data is not kept) *)
#pub datasort pchunks =
  | pnil of ()
  | pgood of (bytes, bytes, pchunks)    (* tag, data, the others *)
  | pbad of (bytes, pchunks)            (* tag, the others *)

(* why chunks could not be read *)
#pub datasort seqcause =
  | sc_trunc of ()          (* the bytes end before the end chunk *)
  | sc_big of ()            (* a chunk's length is over the limit *)
  | sc_trailing of ()       (* bytes follow the end chunk *)
  | sc_end_data of ()       (* the end chunk holds data *)

#pub datasort seqres =
  | sq_ok of (pchunks)
  | sq_fail of (seqcause)

#pub dataprop EQSQ(seqres, seqres) =
  | {result:seqres} EQSQ_refl(result, result)

(* The tag of the end chunk, "IEND" *)
#pub stadef IEND = bcons(73, bcons(69, bcons(78, bcons(68, bnil()))))

(* TAGNOT(tag): a tag that is not "IEND" *)
#pub dataprop TAGNOT(bytes) =
  | {tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte:int | 0 <= tag_first_byte; tag_first_byte < 256; 0 <= tag_second_byte; tag_second_byte < 256; 0 <= tag_third_byte; tag_third_byte < 256; 0 <= tag_fourth_byte; tag_fourth_byte < 256;
       tag_first_byte != 73 || tag_second_byte != 69 || tag_third_byte != 78 || tag_fourth_byte != 68}
    TAGNOT_mk(bcons(tag_first_byte, bcons(tag_second_byte, bcons(tag_third_byte, bcons(tag_fourth_byte, bnil())))))

(* SEQ(octets, result): the chunks in octets come to result *)
#pub dataprop SEQ(bytes, seqres) =
  | {octets:bytes}{check_result:ckres}{result:seqres} SEQ_mk(octets, result) of (CK(octets, check_result), SQC(check_result, result))

and SQC(ckres, seqres) =
  | SQC_short(ck_trunc(), sq_fail(sc_trunc()))
  | SQC_big(ck_big(), sq_fail(sc_big()))
  | SQC_end(ck_ok(IEND, bnil(), bnil()), sq_ok(pnil()))
  | {trailing_byte:int | 0 <= trailing_byte; trailing_byte < 256}{trailing_rest:bytes}
    SQC_trailing(ck_ok(IEND, bnil(), bcons(trailing_byte, trailing_rest)), sq_fail(sc_trailing()))
  | {data_byte:int | 0 <= data_byte; data_byte < 256}{data_tail,rest:bytes}
    SQC_end_data(ck_ok(IEND, bcons(data_byte, data_tail), rest), sq_fail(sc_end_data()))
  | {tag,data,rest:bytes}{chunks:pchunks}
    SQC_good(ck_ok(tag, data, rest), sq_ok(pgood(tag, data, chunks))) of (TAGNOT(tag), SEQ(rest, sq_ok(chunks)))
  | {tag,data,rest:bytes}{cause:seqcause}
    SQC_good_fail(ck_ok(tag, data, rest), sq_fail(cause)) of (TAGNOT(tag), SEQ(rest, sq_fail(cause)))
  | {tag,data,rest:bytes}{chunks:pchunks}
    SQC_bad(ck_bad(tag, data, rest), sq_ok(pbad(tag, chunks))) of SEQ(rest, sq_ok(chunks))
  | {tag,data,rest:bytes}{cause:seqcause}
    SQC_bad_fail(ck_bad(tag, data, rest), sq_fail(cause)) of SEQ(rest, sq_fail(cause))


(* the rest after a chunk is shorter than the whole *)
prfn _rest_shorter_ok {octets,tag,data,rest:bytes}{octets_size:nat}
  (read_proof: CK(octets, ck_ok(tag, data, rest)), whole: LEN(octets, octets_size))
  : [rest_size:nat | rest_size < octets_size] LEN(rest, rest_size) = let
  prval (chunk_app, chunk_len) = ck_ok_consumes(read_proof)
in append_len_rest(chunk_app, chunk_len, whole) end

prfn _rest_shorter_bad {octets,tag,data,rest:bytes}{octets_size:nat}
  (read_proof: CK(octets, ck_bad(tag, data, rest)), whole: LEN(octets, octets_size))
  : [rest_size:nat | rest_size < octets_size] LEN(rest, rest_size) = let
  prval (chunk_app, chunk_len) = ck_bad_consumes(read_proof)
in append_len_rest(chunk_app, chunk_len, whole) end

#pub prfun seq_functional {octets:bytes}{octets_size:nat}{first_result,second_result:seqres} (LEN(octets, octets_size), SEQ(octets, first_result), SEQ(octets, second_result)): EQSQ(first_result, second_result)

prfun _seq_functional {octets:bytes}{octets_size:nat}{first_result,second_result:seqres} .<octets_size>.
  (whole: LEN(octets, octets_size), first: SEQ(octets, first_result), second: SEQ(octets, second_result)): EQSQ(first_result, second_result) =
  case+ first of
  | SEQ_mk(first_read, first_step) =>
    (case+ second of
     | SEQ_mk(second_read, second_step) => let
         prval EQCK_refl() = ck_functional(first_read, second_read)
       in
         case+ first_step of
         | SQC_short() => (case+ second_step of SQC_short() => EQSQ_refl())
         | SQC_big() => (case+ second_step of SQC_big() => EQSQ_refl())
         | SQC_end() =>
           (case+ second_step of
            | SQC_end() => EQSQ_refl()
            | SQC_good(tag_not_end, _) => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_good_fail(tag_not_end, _) => (case+ tag_not_end of TAGNOT_mk() =/=> ()))
         | SQC_trailing() =>
           (case+ second_step of
            | SQC_trailing() => EQSQ_refl()
            | SQC_good(tag_not_end, _) => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_good_fail(tag_not_end, _) => (case+ tag_not_end of TAGNOT_mk() =/=> ()))
         | SQC_end_data() =>
           (case+ second_step of
            | SQC_end_data() => EQSQ_refl()
            | SQC_good(tag_not_end, _) => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_good_fail(tag_not_end, _) => (case+ tag_not_end of TAGNOT_mk() =/=> ()))
         | SQC_good(tag_not_end, first_rest) =>
           (case+ second_step of
            | SQC_end() => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_trailing() => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_end_data() => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_good(_, second_rest) => let
                prval rest_len = _rest_shorter_ok(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() => EQSQ_refl()) end
            | SQC_good_fail(_, second_rest) => let
                prval rest_len = _rest_shorter_ok(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() =/=> ()) end)
         | SQC_good_fail(tag_not_end, first_rest) =>
           (case+ second_step of
            | SQC_end() => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_trailing() => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_end_data() => (case+ tag_not_end of TAGNOT_mk() =/=> ())
            | SQC_good(_, second_rest) => let
                prval rest_len = _rest_shorter_ok(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() =/=> ()) end
            | SQC_good_fail(_, second_rest) => let
                prval rest_len = _rest_shorter_ok(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() => EQSQ_refl()) end)
         | SQC_bad(first_rest) =>
           (case+ second_step of
            | SQC_bad(second_rest) => let
                prval rest_len = _rest_shorter_bad(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() => EQSQ_refl()) end
            | SQC_bad_fail(second_rest) => let
                prval rest_len = _rest_shorter_bad(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() =/=> ()) end)
         | SQC_bad_fail(first_rest) =>
           (case+ second_step of
            | SQC_bad(second_rest) => let
                prval rest_len = _rest_shorter_bad(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() =/=> ()) end
            | SQC_bad_fail(second_rest) => let
                prval rest_len = _rest_shorter_bad(first_read, whole)
              in (case+ _seq_functional(rest_len, first_rest, second_rest) of EQSQ_refl() => EQSQ_refl()) end)
       end)

primplement seq_functional {octets}{octets_size}{first_result,second_result} (whole, first, second) = _seq_functional(whole, first, second)


(* CHAINS(chunk_count, chunks, octets): octets holds chunk_count chunks, then the end chunk: the
   chunks, all whole *)
#pub dataprop CHAINS(int, pchunks, bytes) =
  | {octets:bytes} CHAINS_end(0, pnil(), octets) of CKENC(IEND, bnil(), octets)
  | {chunk_count:nat}{tag,data,chunk,after_chunk,octets:bytes}{chunks:pchunks}
    CHAINS_cons(chunk_count+1, pgood(tag, data, chunks), octets) of (TAGNOT(tag), CKENC(tag, data, chunk), CHAINS(chunk_count, chunks, after_chunk), APPEND(chunk, after_chunk, octets))

(* ALLGOOD(chunk_count, chunks): chunks are chunk_count chunks, all whole *)
#pub dataprop ALLGOOD(int, pchunks) =
  | ALLGOOD_nil(0, pnil())
  | {chunk_count:nat}{tag,data:bytes}{chunks:pchunks} ALLGOOD_cons(chunk_count+1, pgood(tag, data, chunks)) of ALLGOOD(chunk_count, chunks)

(* chunks written are read back as they were *)
#pub prfun chains_seq {chunk_count:nat}{chunks:pchunks}{octets:bytes} (CHAINS(chunk_count, chunks, octets)): SEQ(octets, sq_ok(chunks))

prfun _chains_seq {chunk_count:nat}{chunks:pchunks}{octets:bytes} .<chunk_count>. (chains: CHAINS(chunk_count, chunks, octets)): SEQ(octets, sq_ok(chunks)) =
  case+ chains of
  | CHAINS_end(encoded) => let
      prval nothing = append_nil(ckenc_len(encoded))
    in SEQ_mk(ckenc_ck(encoded, nothing), SQC_end()) end
  | CHAINS_cons(tag_not_end, encoded, rest, chunk_app) =>
    SEQ_mk(ckenc_ck(encoded, chunk_app), SQC_good(tag_not_end, _chains_seq(rest)))

primplement chains_seq {chunk_count}{chunks}{octets} (chains) = _chains_seq(chains)

(* and chunks read, all whole, were written *)
#pub prfun seq_chains {chunk_count:nat}{chunks:pchunks}{octets:bytes} (ALLGOOD(chunk_count, chunks), SEQ(octets, sq_ok(chunks))): CHAINS(chunk_count, chunks, octets)

prfun _seq_chains {chunk_count:nat}{chunks:pchunks}{octets:bytes} .<chunk_count>. (good: ALLGOOD(chunk_count, chunks), parsed: SEQ(octets, sq_ok(chunks))): CHAINS(chunk_count, chunks, octets) =
  case+ good of
  | ALLGOOD_nil() =>
    (case+ parsed of
     | SEQ_mk(read_proof, SQC_end()) => let
         prval (encoded, chunk_app) = ck_ckenc(read_proof)
         prval EQB_refl() = append_nil_eq(ckenc_len(encoded), chunk_app)
       in CHAINS_end(encoded) end)
  | ALLGOOD_cons(good_rest) =>
    (case+ parsed of
     | SEQ_mk(read_proof, SQC_good(tag_not_end, rest)) => let
         prval (encoded, chunk_app) = ck_ckenc(read_proof)
       in CHAINS_cons(tag_not_end, encoded, _seq_chains(good_rest, rest), chunk_app) end)

primplement seq_chains {chunk_count}{chunks}{octets} (good, parsed) = _seq_chains(good, parsed)


(* PCN(chunk_count, chunks): there are chunk_count chunks in chunks *)
#pub dataprop PCN(int, pchunks) =
  | PCN_nil(0, pnil())
  | {chunk_count:nat}{tag,data:bytes}{chunks:pchunks} PCN_good(chunk_count+1, pgood(tag, data, chunks)) of PCN(chunk_count, chunks)
  | {chunk_count:nat}{tag:bytes}{chunks:pchunks} PCN_bad(chunk_count+1, pbad(tag, chunks)) of PCN(chunk_count, chunks)

(* The chunks of a record, at run time, chunk_count of them *)
#pub datavtype chunklist(pchunks, int) =
  | CL_nil(pnil(), 0)
  | {tag,data:bytes}{chunks:pchunks}{data_size,chunk_count:nat | data_size < 1048576}
    CL_good(pgood(tag, data, chunks), chunk_count+1) of (TAGNOT(tag) | blist(tag, 4), blist(data, data_size), chunklist(chunks, chunk_count))
  | {tag:bytes}{chunks:pchunks}{chunk_count:nat}
    CL_bad(pbad(tag, chunks), chunk_count+1) of (blist(tag, 4), chunklist(chunks, chunk_count))

#pub fun chunklist_free {chunks:pchunks}{chunk_count:nat} (chunk_list: chunklist(chunks, chunk_count)): void

implement chunklist_free {chunks}{chunk_count} (chunk_list) = let
  fun free_chunks {chunks:pchunks}{chunk_count:nat} .<chunk_count>. (chunk_list: chunklist(chunks, chunk_count)): void =
    case+ chunk_list of
    | ~CL_nil() => ()
    | ~CL_good(_ | tag, data, rest) => let
        val () = blist_free(tag)
        val () = blist_free(data)
      in free_chunks(rest) end
    | ~CL_bad(tag, rest) => let val () = blist_free(tag) in free_chunks(rest) end
in free_chunks(chunk_list) end

(* what reading the chunks of a record comes to *)
#pub datavtype seqread(seqres) =
  | {chunks:pchunks}{chunk_count:nat} SR_ok(sq_ok(chunks)) of (PCN(chunk_count, chunks) | chunklist(chunks, chunk_count))
  | {cause:seqcause} SR_fail(sq_fail(cause))

(* the tag read is the end chunk's, or it is not *)
datavtype iendcheck(bytes) =
  | {tag:bytes} IsEnd(tag) of (EQB(tag, IEND) | )
  | {tag:bytes} NotEnd(tag) of (TAGNOT(tag) | )

fn _is_end {tag:bytes} (tag: !blist(tag, 4)): iendcheck(tag) =
  case+ tag of
  | blist_cons(tag_first_byte, blist_cons(tag_second_byte, blist_cons(tag_third_byte, blist_cons(tag_fourth_byte, blist_nil())))) =>
    if tag_first_byte = 73 then
      (if tag_second_byte = 69 then
         (if tag_third_byte = 78 then
            (if tag_fourth_byte = 68 then IsEnd(EQB_refl() | ) else NotEnd(TAGNOT_mk() | ))
          else NotEnd(TAGNOT_mk() | ))
       else NotEnd(TAGNOT_mk() | ))
    else NotEnd(TAGNOT_mk() | )


#pub fun seq_read {octets:bytes}{list_len:nat} (list: blist(octets, list_len)): [result:seqres] (SEQ(octets, result) | seqread(result))

implement seq_read {octets}{list_len} (list) = let
  fun read_chunks {octets:bytes}{list_len:nat} .<list_len>. (list: blist(octets, list_len)): [result:seqres] (SEQ(octets, result) | seqread(result)) = let
    val (read_proof | chunk_result) = chunk_read(list)
  in
    case+ chunk_result of
    | ~CKR_trunc() => (SEQ_mk(read_proof, SQC_short()) | SR_fail())
    | ~CKR_big() => (SEQ_mk(read_proof, SQC_big()) | SR_fail())
    | ~CKR_ok(tag, data, rest) =>
      (case+ _is_end(tag) of
       | ~IsEnd(EQB_refl() | ) =>
         (case+ data of
          | ~blist_nil() =>
            (case+ rest of
             | ~blist_nil() => let val () = blist_free(tag) in (SEQ_mk(read_proof, SQC_end()) | SR_ok(PCN_nil() | CL_nil())) end
             | ~blist_cons(_, more) => let
                 val () = blist_free(tag)
                 val () = blist_free(more)
               in (SEQ_mk(read_proof, SQC_trailing()) | SR_fail()) end)
          | ~blist_cons(_, more) => let
              val () = blist_free(tag)
              val () = blist_free(more)
              val () = blist_free(rest)
            in (SEQ_mk(read_proof, SQC_end_data()) | SR_fail()) end)
       | ~NotEnd(tag_not_end | ) => let
           val (rest_seq | rest_result) = read_chunks(rest)
         in
           case+ rest_result of
           | ~SR_ok(count | chunk_list) => (SEQ_mk(read_proof, SQC_good(tag_not_end, rest_seq)) | SR_ok(PCN_good(count) | CL_good(tag_not_end | tag, data, chunk_list)))
           | ~SR_fail() => let
               val () = blist_free(tag)
               val () = blist_free(data)
             in (SEQ_mk(read_proof, SQC_good_fail(tag_not_end, rest_seq)) | SR_fail()) end
         end)
    | ~CKR_bad(tag, data, rest) => let
        val () = blist_free(data)
        val (rest_seq | rest_result) = read_chunks(rest)
      in
        case+ rest_result of
        | ~SR_ok(count | chunk_list) => (SEQ_mk(read_proof, SQC_bad(rest_seq)) | SR_ok(PCN_bad(count) | CL_bad(tag, chunk_list)))
        | ~SR_fail() => let val () = blist_free(tag) in (SEQ_mk(read_proof, SQC_bad_fail(rest_seq)) | SR_fail()) end
      end
  end
in read_chunks(list) end


prfn allgood_bad_false {chunk_count:nat}{tag:bytes}{chunks:pchunks} (good: ALLGOOD(chunk_count, pbad(tag, chunks))): FALSEP() =
  case+ good of ALLGOOD_nil() =/=> ()

prfn falsep_chains {chunk_count:nat}{chunks:pchunks}{octets:bytes} (falsity: FALSEP()): CHAINS(chunk_count, chunks, octets) =
  case+ falsity of FALSEP_mk() =/=> ()

(* The chunks written, then the end chunk, with the proof *)
#pub fun seq_write {chunks:pchunks}{chunk_count:nat} (good: ALLGOOD(chunk_count, chunks) | chunk_list: !chunklist(chunks, chunk_count))
  : [octets:bytes][written_len:nat] (CHAINS(chunk_count, chunks, octets) | blist(octets, written_len))

implement seq_write {chunks}{chunk_count} (good | chunk_list) = let
  fun write_chunks {chunks:pchunks}{chunk_count:nat} .<chunk_count>. (good: ALLGOOD(chunk_count, chunks) | chunk_list: !chunklist(chunks, chunk_count))
    : [octets:bytes][written_len:nat] (CHAINS(chunk_count, chunks, octets) | blist(octets, written_len)) =
    case+ chunk_list of
    | CL_nil() => let
        prval ALLGOOD_nil() = good
        val iend = blist_cons(73, blist_cons(69, blist_cons(78, blist_cons(68, blist_nil()))))
        val nothing = blist_nil()
        val (encoded | out) = chunk_write(iend, nothing)
        val () = blist_free(iend)
        val () = blist_free(nothing)
      in (CHAINS_end(encoded) | out) end
    | CL_good(tag_not_end | tag, data, rest) => let
        prval ALLGOOD_cons(good_rest) = good
        val (encoded | chunk) = chunk_write(tag, data)
        val (chains | after) = write_chunks(good_rest | rest)
        val (chunk_app | out) = blist_append(chunk, after)
      in (CHAINS_cons(tag_not_end, encoded, chains, chunk_app) | out) end
    | CL_bad(_, _) => (falsep_chains(allgood_bad_false(good)) | blist_nil())
in write_chunks(good | chunk_list) end

end
