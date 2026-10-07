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
  | {r:seqres} EQSQ_refl(r, r)

(* The tag of the end chunk, "IEND" *)
#pub stadef IEND = bcons(73, bcons(69, bcons(78, bcons(68, bnil()))))

(* TAGNOT(tag): a tag that is not "IEND" *)
#pub dataprop TAGNOT(bytes) =
  | {t0,t1,t2,t3:int | 0 <= t0; t0 < 256; 0 <= t1; t1 < 256; 0 <= t2; t2 < 256; 0 <= t3; t3 < 256;
       t0 != 73 || t1 != 69 || t2 != 78 || t3 != 68}
    TAGNOT_mk(bcons(t0, bcons(t1, bcons(t2, bcons(t3, bnil())))))

(* SEQ(bs, res): the chunks in bs come to res *)
#pub dataprop SEQ(bytes, seqres) =
  | {bs:bytes}{c:ckres}{res:seqres} SEQ_mk(bs, res) of (CK(bs, c), SQC(c, res))

and SQC(ckres, seqres) =
  | SQC_short(ck_trunc(), sq_fail(sc_trunc()))
  | SQC_big(ck_big(), sq_fail(sc_big()))
  | SQC_end(ck_ok(IEND, bnil(), bnil()), sq_ok(pnil()))
  | {x:int | 0 <= x; x < 256}{r:bytes}
    SQC_trailing(ck_ok(IEND, bnil(), bcons(x, r)), sq_fail(sc_trailing()))
  | {x:int | 0 <= x; x < 256}{d,r:bytes}
    SQC_end_data(ck_ok(IEND, bcons(x, d), r), sq_fail(sc_end_data()))
  | {tag,data,rest:bytes}{pcs:pchunks}
    SQC_good(ck_ok(tag, data, rest), sq_ok(pgood(tag, data, pcs))) of (TAGNOT(tag), SEQ(rest, sq_ok(pcs)))
  | {tag,data,rest:bytes}{c:seqcause}
    SQC_good_fail(ck_ok(tag, data, rest), sq_fail(c)) of (TAGNOT(tag), SEQ(rest, sq_fail(c)))
  | {tag,data,rest:bytes}{pcs:pchunks}
    SQC_bad(ck_bad(tag, data, rest), sq_ok(pbad(tag, pcs))) of SEQ(rest, sq_ok(pcs))
  | {tag,data,rest:bytes}{c:seqcause}
    SQC_bad_fail(ck_bad(tag, data, rest), sq_fail(c)) of SEQ(rest, sq_fail(c))


(* the rest after a chunk is shorter than the whole *)
prfn _rest_shorter_ok {bs,tag,data,rest:bytes}{n:nat}
  (ck: CK(bs, ck_ok(tag, data, rest)), whole: LEN(bs, n))
  : [m:nat | m < n] LEN(rest, m) = let
  prval (app, front) = ck_ok_consumes(ck)
in append_len_rest(app, front, whole) end

prfn _rest_shorter_bad {bs,tag,data,rest:bytes}{n:nat}
  (ck: CK(bs, ck_bad(tag, data, rest)), whole: LEN(bs, n))
  : [m:nat | m < n] LEN(rest, m) = let
  prval (app, front) = ck_bad_consumes(ck)
in append_len_rest(app, front, whole) end

#pub prfun seq_functional {bs:bytes}{n:nat}{a,b:seqres} (LEN(bs, n), SEQ(bs, a), SEQ(bs, b)): EQSQ(a, b)

prfun _seq_functional {bs:bytes}{n:nat}{a,b:seqres} .<n>.
  (whole: LEN(bs, n), p: SEQ(bs, a), q: SEQ(bs, b)): EQSQ(a, b) =
  case+ p of
  | SEQ_mk(pc, ps) =>
    (case+ q of
     | SEQ_mk(qc, qs) => let
         prval EQCK_refl() = ck_functional(pc, qc)
       in
         case+ ps of
         | SQC_short() => (case+ qs of SQC_short() => EQSQ_refl())
         | SQC_big() => (case+ qs of SQC_big() => EQSQ_refl())
         | SQC_end() =>
           (case+ qs of
            | SQC_end() => EQSQ_refl()
            | SQC_good(tn, _) => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_good_fail(tn, _) => (case+ tn of TAGNOT_mk() =/=> ()))
         | SQC_trailing() =>
           (case+ qs of
            | SQC_trailing() => EQSQ_refl()
            | SQC_good(tn, _) => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_good_fail(tn, _) => (case+ tn of TAGNOT_mk() =/=> ()))
         | SQC_end_data() =>
           (case+ qs of
            | SQC_end_data() => EQSQ_refl()
            | SQC_good(tn, _) => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_good_fail(tn, _) => (case+ tn of TAGNOT_mk() =/=> ()))
         | SQC_good(tn, pr) =>
           (case+ qs of
            | SQC_end() => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_trailing() => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_end_data() => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_good(_, qr) => let
                prval rest_len = _rest_shorter_ok(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() => EQSQ_refl()) end
            | SQC_good_fail(_, qr) => let
                prval rest_len = _rest_shorter_ok(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() =/=> ()) end)
         | SQC_good_fail(tn, pr) =>
           (case+ qs of
            | SQC_end() => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_trailing() => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_end_data() => (case+ tn of TAGNOT_mk() =/=> ())
            | SQC_good(_, qr) => let
                prval rest_len = _rest_shorter_ok(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() =/=> ()) end
            | SQC_good_fail(_, qr) => let
                prval rest_len = _rest_shorter_ok(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() => EQSQ_refl()) end)
         | SQC_bad(pr) =>
           (case+ qs of
            | SQC_bad(qr) => let
                prval rest_len = _rest_shorter_bad(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() => EQSQ_refl()) end
            | SQC_bad_fail(qr) => let
                prval rest_len = _rest_shorter_bad(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() =/=> ()) end)
         | SQC_bad_fail(pr) =>
           (case+ qs of
            | SQC_bad(qr) => let
                prval rest_len = _rest_shorter_bad(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() =/=> ()) end
            | SQC_bad_fail(qr) => let
                prval rest_len = _rest_shorter_bad(pc, whole)
              in (case+ _seq_functional(rest_len, pr, qr) of EQSQ_refl() => EQSQ_refl()) end)
       end)

primplement seq_functional {bs}{n}{a,b} (whole, p, q) = _seq_functional(whole, p, q)


(* CHAINS(k, pcs, bs): bs holds k chunks, then the end chunk: the
   chunks pcs, all whole *)
#pub dataprop CHAINS(int, pchunks, bytes) =
  | {bs:bytes} CHAINS_end(0, pnil(), bs) of CKENC(IEND, bnil(), bs)
  | {k:nat}{tag,data,c,b2,bs:bytes}{pcs:pchunks}
    CHAINS_cons(k+1, pgood(tag, data, pcs), bs) of (TAGNOT(tag), CKENC(tag, data, c), CHAINS(k, pcs, b2), APPEND(c, b2, bs))

(* ALLGOOD(k, pcs): pcs are k chunks, all whole *)
#pub dataprop ALLGOOD(int, pchunks) =
  | ALLGOOD_nil(0, pnil())
  | {k:nat}{tag,data:bytes}{pcs:pchunks} ALLGOOD_cons(k+1, pgood(tag, data, pcs)) of ALLGOOD(k, pcs)

(* chunks written are read back as they were *)
#pub prfun chains_seq {k:nat}{pcs:pchunks}{bs:bytes} (CHAINS(k, pcs, bs)): SEQ(bs, sq_ok(pcs))

prfun _chains_seq {k:nat}{pcs:pchunks}{bs:bytes} .<k>. (p: CHAINS(k, pcs, bs)): SEQ(bs, sq_ok(pcs)) =
  case+ p of
  | CHAINS_end(e) => let
      prval nothing = append_nil(ckenc_len(e))
    in SEQ_mk(ckenc_ck(e, nothing), SQC_end()) end
  | CHAINS_cons(tn, e, rest, app) =>
    SEQ_mk(ckenc_ck(e, app), SQC_good(tn, _chains_seq(rest)))

primplement chains_seq {k}{pcs}{bs} (p) = _chains_seq(p)

(* and chunks read, all whole, were written *)
#pub prfun seq_chains {k:nat}{pcs:pchunks}{bs:bytes} (ALLGOOD(k, pcs), SEQ(bs, sq_ok(pcs))): CHAINS(k, pcs, bs)

prfun _seq_chains {k:nat}{pcs:pchunks}{bs:bytes} .<k>. (g: ALLGOOD(k, pcs), p: SEQ(bs, sq_ok(pcs))): CHAINS(k, pcs, bs) =
  case+ g of
  | ALLGOOD_nil() =>
    (case+ p of
     | SEQ_mk(ck, SQC_end()) => let
         prval (e, app) = ck_ckenc(ck)
         prval EQB_refl() = append_nil_eq(ckenc_len(e), app)
       in CHAINS_end(e) end)
  | ALLGOOD_cons(g1) =>
    (case+ p of
     | SEQ_mk(ck, SQC_good(tn, rest)) => let
         prval (e, app) = ck_ckenc(ck)
       in CHAINS_cons(tn, e, _seq_chains(g1, rest), app) end)

primplement seq_chains {k}{pcs}{bs} (g, p) = _seq_chains(g, p)


(* PCN(n, pcs): there are n chunks in pcs *)
#pub dataprop PCN(int, pchunks) =
  | PCN_nil(0, pnil())
  | {n:nat}{tag,data:bytes}{pcs:pchunks} PCN_good(n+1, pgood(tag, data, pcs)) of PCN(n, pcs)
  | {n:nat}{tag:bytes}{pcs:pchunks} PCN_bad(n+1, pbad(tag, pcs)) of PCN(n, pcs)

(* The chunks of a record, at run time, k of them *)
#pub datavtype chunklist(pchunks, int) =
  | CL_nil(pnil(), 0)
  | {tag,data:bytes}{pcs:pchunks}{nd,k:nat | nd < 1048576}
    CL_good(pgood(tag, data, pcs), k+1) of (TAGNOT(tag) | blist(tag, 4), blist(data, nd), chunklist(pcs, k))
  | {tag:bytes}{pcs:pchunks}{k:nat}
    CL_bad(pbad(tag, pcs), k+1) of (blist(tag, 4), chunklist(pcs, k))

#pub fun chunklist_free {pcs:pchunks}{k:nat} (cl: chunklist(pcs, k)): void

implement chunklist_free {pcs}{k} (cl) = let
  fun go {pcs:pchunks}{k:nat} .<k>. (cl: chunklist(pcs, k)): void =
    case+ cl of
    | ~CL_nil() => ()
    | ~CL_good(_ | tag, data, rest) => let
        val () = blist_free(tag)
        val () = blist_free(data)
      in go(rest) end
    | ~CL_bad(tag, rest) => let val () = blist_free(tag) in go(rest) end
in go(cl) end

(* what reading the chunks of a record comes to *)
#pub datavtype seqread(seqres) =
  | {pcs:pchunks}{k:nat} SR_ok(sq_ok(pcs)) of (PCN(k, pcs) | chunklist(pcs, k))
  | {c:seqcause} SR_fail(sq_fail(c))

(* the tag read is the end chunk's, or it is not *)
datavtype iendcheck(bytes) =
  | {tag:bytes} IsEnd(tag) of (EQB(tag, IEND) | )
  | {tag:bytes} NotEnd(tag) of (TAGNOT(tag) | )

fn _is_end {tag:bytes} (tag: !blist(tag, 4)): iendcheck(tag) =
  case+ tag of
  | blist_cons(t0, blist_cons(t1, blist_cons(t2, blist_cons(t3, blist_nil())))) =>
    if t0 = 73 then
      (if t1 = 69 then
         (if t2 = 78 then
            (if t3 = 68 then IsEnd(EQB_refl() | ) else NotEnd(TAGNOT_mk() | ))
          else NotEnd(TAGNOT_mk() | ))
       else NotEnd(TAGNOT_mk() | ))
    else NotEnd(TAGNOT_mk() | )


#pub fun seq_read {bs:bytes}{n:nat} (list: blist(bs, n)): [res:seqres] (SEQ(bs, res) | seqread(res))

implement seq_read {bs}{n} (list) = let
  fun go {bs:bytes}{n:nat} .<n>. (list: blist(bs, n)): [res:seqres] (SEQ(bs, res) | seqread(res)) = let
    val (ck | r) = chunk_read(list)
  in
    case+ r of
    | ~CKR_trunc() => (SEQ_mk(ck, SQC_short()) | SR_fail())
    | ~CKR_big() => (SEQ_mk(ck, SQC_big()) | SR_fail())
    | ~CKR_ok(tag, data, rest) =>
      (case+ _is_end(tag) of
       | ~IsEnd(EQB_refl() | ) =>
         (case+ data of
          | ~blist_nil() =>
            (case+ rest of
             | ~blist_nil() => let val () = blist_free(tag) in (SEQ_mk(ck, SQC_end()) | SR_ok(PCN_nil() | CL_nil())) end
             | ~blist_cons(_, more) => let
                 val () = blist_free(tag)
                 val () = blist_free(more)
               in (SEQ_mk(ck, SQC_trailing()) | SR_fail()) end)
          | ~blist_cons(_, more) => let
              val () = blist_free(tag)
              val () = blist_free(more)
              val () = blist_free(rest)
            in (SEQ_mk(ck, SQC_end_data()) | SR_fail()) end)
       | ~NotEnd(tn | ) => let
           val (sub | r2) = go(rest)
         in
           case+ r2 of
           | ~SR_ok(count | cl) => (SEQ_mk(ck, SQC_good(tn, sub)) | SR_ok(PCN_good(count) | CL_good(tn | tag, data, cl)))
           | ~SR_fail() => let
               val () = blist_free(tag)
               val () = blist_free(data)
             in (SEQ_mk(ck, SQC_good_fail(tn, sub)) | SR_fail()) end
         end)
    | ~CKR_bad(tag, data, rest) => let
        val () = blist_free(data)
        val (sub | r2) = go(rest)
      in
        case+ r2 of
        | ~SR_ok(count | cl) => (SEQ_mk(ck, SQC_bad(sub)) | SR_ok(PCN_bad(count) | CL_bad(tag, cl)))
        | ~SR_fail() => let val () = blist_free(tag) in (SEQ_mk(ck, SQC_bad_fail(sub)) | SR_fail()) end
      end
  end
in go(list) end


prfn allgood_bad_false {k:nat}{tag:bytes}{pcs:pchunks} (g: ALLGOOD(k, pbad(tag, pcs))): FALSEP() =
  case+ g of ALLGOOD_nil() =/=> ()

prfn falsep_chains {k:nat}{pcs:pchunks}{bs:bytes} (f: FALSEP()): CHAINS(k, pcs, bs) =
  case+ f of FALSEP_mk() =/=> ()

(* The chunks written, then the end chunk, with the proof *)
#pub fun seq_write {pcs:pchunks}{k:nat} (good: ALLGOOD(k, pcs) | cl: !chunklist(pcs, k))
  : [bs:bytes][m:nat] (CHAINS(k, pcs, bs) | blist(bs, m))

implement seq_write {pcs}{k} (good | cl) = let
  fun go {pcs:pchunks}{k:nat} .<k>. (good: ALLGOOD(k, pcs) | cl: !chunklist(pcs, k))
    : [bs:bytes][m:nat] (CHAINS(k, pcs, bs) | blist(bs, m)) =
    case+ cl of
    | CL_nil() => let
        prval ALLGOOD_nil() = good
        val iend = blist_cons(73, blist_cons(69, blist_cons(78, blist_cons(68, blist_nil()))))
        val nothing = blist_nil()
        val (e | out) = chunk_write(iend, nothing)
        val () = blist_free(iend)
        val () = blist_free(nothing)
      in (CHAINS_end(e) | out) end
    | CL_good(tn | tag, data, rest) => let
        prval ALLGOOD_cons(good1) = good
        val (e | c) = chunk_write(tag, data)
        val (chains | after) = go(good1 | rest)
        val (app | out) = blist_append(c, after)
      in (CHAINS_cons(tn, e, chains, app) | out) end
    | CL_bad(_, _) => (falsep_chains(allgood_bad_false(good)) | blist_nil())
in go(good | cl) end

end
