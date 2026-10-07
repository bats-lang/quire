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
  | {r:recres} EQRR_refl(r, r)

(* the version of the format this Quire reads and writes *)
#pub stadef READER = 1

(* ENCODES(sp, kind, x, bs): bs is the record x of the groups sp, of this
   kind: "QREC", the kind, the version and the least version, then the
   chunks, then the end chunk *)
#pub dataprop ENCODES(specs, int, rx, bytes) =
  | {sp:specs}{kind,ver,minver:int | 0 <= kind; kind < 256; 0 <= ver; ver < 256; 0 <= minver; minver <= READER}
    {vals:gvals}{e:extras}{pcs:pchunks}{n:nat}{body,bs:bytes}
    ENCODES_mk(sp, kind, rx_mk(ver, minver, vals, e), bs)
    of (SENC(sp, vals, e, pcs), ALLGOOD(n, pcs), PCN(n, pcs), CHAINS(n, pcs, body),
        APPEND(bcons(81, bcons(82, bcons(69, bcons(67, bcons(kind, bcons(ver, bcons(minver, bnil()))))))), body, bs))


(* MAGICDIFF(m): four bytes that are not "QREC" *)
#pub dataprop MAGICDIFF(bytes) =
  | {m0,m1,m2,m3:int | 0 <= m0; m0 < 256; 0 <= m1; m1 < 256; 0 <= m2; m2 < 256; 0 <= m3; m3 < 256;
       m0 != 81 || m1 != 82 || m2 != 69 || m3 != 67}
    MAGICDIFF_mk(bcons(m0, bcons(m1, bcons(m2, bcons(m3, bnil())))))

(* PCN of one list is one number *)
#pub prfun pcn_functional {pcs:pchunks}{n,m:nat} (PCN(n, pcs), PCN(m, pcs)): EQI(n, m)

prfun _pcn_functional {pcs:pchunks}{n,m:nat} .<n>. (p: PCN(n, pcs), q: PCN(m, pcs)): EQI(n, m) =
  case+ p of
  | PCN_nil() => (case+ q of PCN_nil() => EQI_refl())
  | PCN_good(p1) => (case+ q of PCN_good(q1) => (case+ _pcn_functional(p1, q1) of EQI_refl() => EQI_refl()))
  | PCN_bad(p1) => (case+ q of PCN_bad(q1) => (case+ _pcn_functional(p1, q1) of EQI_refl() => EQI_refl()))

primplement pcn_functional {pcs}{n,m} (p, q) = _pcn_functional(p, q)

(* FIN(sp, ver, minver, sq, res): the chunks read come to res *)
#pub dataprop FIN(specs, int, int, seqres, recres) =
  | {sp:specs}{ver,minver:int}{c:seqcause} FIN_seq(sp, ver, minver, sq_fail(c), rr_damaged())
  | {sp:specs}{ver,minver:int}{vals:gvals}{e:extras}{pcs:pchunks}{n:nat}
    FIN_ok(sp, ver, minver, sq_ok(pcs), rr_ok(rx_mk(ver, minver, vals, e)))
    of (PCN(n, pcs), SDEC(sp, sp, pcs, sd_ok(vals, e)))
  | {sp:specs}{ver,minver:int}{vals:gvals}{e:extras}{t:lost}{pcs:pchunks}{n:nat}
    FIN_loss(sp, ver, minver, sq_ok(pcs), rr_loss(rx_mk(ver, minver, vals, e), t))
    of (PCN(n, pcs), SDEC(sp, sp, pcs, sd_loss(vals, e, t)))
  | {sp:specs}{ver,minver:int}{pcs:pchunks}{n:nat}
    FIN_damaged(sp, ver, minver, sq_ok(pcs), rr_damaged())
    of (PCN(n, pcs), SDEC(sp, sp, pcs, sd_fail(cause_damaged())))
  | {sp:specs}{ver,minver:int}{pcs:pchunks}{n:nat}
    FIN_newer(sp, ver, minver, sq_ok(pcs), rr_newer())
    of (PCN(n, pcs), SDEC(sp, sp, pcs, sd_fail(cause_newer())))

#pub prfun falsep_eqrr {a,b:recres} (FALSEP()): EQRR(a, b)

primplement falsep_eqrr {a,b} (f) = case+ f of FALSEP_mk() =/=> ()

#pub prfun fin_functional {sp:specs}{ver,minver:int}{sq:seqres}{a,b:recres} (FIN(sp, ver, minver, sq, a), FIN(sp, ver, minver, sq, b)): EQRR(a, b)

primplement fin_functional {sp}{ver,minver}{sq}{a,b} (p, q) =
  case+ p of
  | FIN_seq() => (case+ q of FIN_seq() => EQRR_refl())
  | FIN_ok(pc, px) =>
    (case+ q of
     | FIN_ok(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() => EQRR_refl()) end
     | FIN_loss(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_damaged(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_newer(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end)
  | FIN_loss(pc, px) =>
    (case+ q of
     | FIN_ok(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_loss(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() => EQRR_refl()) end
     | FIN_damaged(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_newer(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end)
  | FIN_damaged(pc, px) =>
    (case+ q of
     | FIN_ok(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_loss(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_damaged(_, _) => EQRR_refl()
     | FIN_newer(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end)
  | FIN_newer(pc, px) =>
    (case+ q of
     | FIN_ok(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_loss(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_damaged(qc, qx) => let
         prval EQI_refl() = pcn_functional(pc, qc)
       in (case+ sdec_functional(pc, px, qx) of EQSD_refl() =/=> ()) end
     | FIN_newer(_, _) => EQRR_refl())


(* DECODES(sp, kind, bs, res): reading bs as a record of this kind and these
   groups comes to res *)
#pub dataprop DECODES(specs, int, bytes, recres) =
  | {sp:specs}{kind:int}{bs:bytes}
    DECODES_short(sp, kind, bs, rr_notquire()) of SHORT(4, bs)
  | {sp:specs}{kind:int}{bs,m,rest:bytes}
    DECODES_magic(sp, kind, bs, rr_notquire()) of (TAKE(4, bs, m, rest), MAGICDIFF(m))
  | {sp:specs}{kind:int}{bs,rest:bytes}
    DECODES_header_short(sp, kind, bs, rr_damaged())
    of (TAKE(4, bs, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest), SHORT(3, rest))
  | {sp:specs}{kind:int}{kd,ver,minver:int | 0 <= kd; kd < 256; 0 <= ver; ver < 256; READER < minver; minver < 256}{bs,rest,body:bytes}
    DECODES_newer(sp, kind, bs, rr_newer())
    of (TAKE(4, bs, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kd, bcons(ver, bcons(minver, bnil()))), body))
  | {sp:specs}{kind:int}{kd,ver,minver:int | 0 <= kd; kd < 256; 0 <= ver; ver < 256; 0 <= minver; minver <= READER; kd != kind}{bs,rest,body:bytes}
    DECODES_kind(sp, kind, bs, rr_damaged())
    of (TAKE(4, bs, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kd, bcons(ver, bcons(minver, bnil()))), body))
  | {sp:specs}{kind,ver,minver:int | 0 <= kind; kind < 256; 0 <= ver; ver < 256; 0 <= minver; minver <= READER}
    {bs,rest,body:bytes}{sq:seqres}{res:recres}
    DECODES_body(sp, kind, bs, res)
    of (TAKE(4, bs, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kind, bcons(ver, bcons(minver, bnil()))), body),
        SEQ(body, sq), FIN(sp, ver, minver, sq, res))


#pub prfun decodes_functional {sp:specs}{kind:int}{bs:bytes}{n:nat}{a,b:recres}
  (LEN(bs, n), DECODES(sp, kind, bs, a), DECODES(sp, kind, bs, b)): EQRR(a, b)

primplement decodes_functional {sp}{kind}{bs}{n}{a,b} (whole, p, q) =
  case+ p of
  | DECODES_short(ps) =>
    (case+ q of
     | DECODES_short(_) => EQRR_refl()
     | DECODES_magic(qt, _) => falsep_eqrr(take_not_short(qt, ps))
     | DECODES_header_short(qt, _) => falsep_eqrr(take_not_short(qt, ps))
     | DECODES_newer(qt, _) => falsep_eqrr(take_not_short(qt, ps))
     | DECODES_kind(qt, _) => falsep_eqrr(take_not_short(qt, ps))
     | DECODES_body(qt, _, _, _) => falsep_eqrr(take_not_short(qt, ps)))
  | DECODES_magic(pt, pm) =>
    (case+ q of
     | DECODES_short(qs) => falsep_eqrr(take_not_short(pt, qs))
     | DECODES_magic(_, _) => EQRR_refl()
     | DECODES_header_short(qt, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ pm of MAGICDIFF_mk() =/=> ()) end
     | DECODES_newer(qt, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ pm of MAGICDIFF_mk() =/=> ()) end
     | DECODES_kind(qt, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ pm of MAGICDIFF_mk() =/=> ()) end
     | DECODES_body(qt, _, _, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ pm of MAGICDIFF_mk() =/=> ()) end)
  | DECODES_header_short(pt, ps) =>
    (case+ q of
     | DECODES_short(qs) => falsep_eqrr(take_not_short(pt, qs))
     | DECODES_magic(qt, qm) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ qm of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(_, _) => EQRR_refl()
     | DECODES_newer(qt, qh) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqrr(take_not_short(qh, ps)) end
     | DECODES_kind(qt, qh) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqrr(take_not_short(qh, ps)) end
     | DECODES_body(qt, qh, _, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqrr(take_not_short(qh, ps)) end)
  | DECODES_newer(pt, ph) =>
    (case+ q of
     | DECODES_short(qs) => falsep_eqrr(take_not_short(pt, qs))
     | DECODES_magic(qt, qm) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ qm of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(qt, qs) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqrr(take_not_short(ph, qs)) end
     | DECODES_newer(_, _) => EQRR_refl()
     | DECODES_kind(qt, qh) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval SAME2_refl() = take_functional(ph, qh)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_body(qt, qh, _, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval SAME2_refl() = take_functional(ph, qh)
       in falsep_eqrr(contradiction{0}()) end)
  | DECODES_kind(pt, ph) =>
    (case+ q of
     | DECODES_short(qs) => falsep_eqrr(take_not_short(pt, qs))
     | DECODES_magic(qt, qm) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ qm of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(qt, qs) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqrr(take_not_short(ph, qs)) end
     | DECODES_newer(qt, qh) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval SAME2_refl() = take_functional(ph, qh)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_kind(_, _) => EQRR_refl()
     | DECODES_body(qt, qh, _, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval SAME2_refl() = take_functional(ph, qh)
       in falsep_eqrr(contradiction{0}()) end)
  | DECODES_body(pt, ph, ps, pf) =>
    (case+ q of
     | DECODES_short(qs) => falsep_eqrr(take_not_short(pt, qs))
     | DECODES_magic(qt, qm) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in (case+ qm of MAGICDIFF_mk() =/=> ()) end
     | DECODES_header_short(qt, qs) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqrr(take_not_short(ph, qs)) end
     | DECODES_newer(qt, qh) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval SAME2_refl() = take_functional(ph, qh)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_kind(qt, qh) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval SAME2_refl() = take_functional(ph, qh)
       in falsep_eqrr(contradiction{0}()) end
     | DECODES_body(qt, qh, qs, qf) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval SAME2_refl() = take_functional(ph, qh)
         prval after_magic = take_rest_len(pt, whole)
         prval body_len = take_rest_len(ph, after_magic)
         prval EQSQ_refl() = seq_functional(body_len, ps, qs)
       in fin_functional(pf, qf) end)


(* a record written is read back as it was *)
#pub prfun encodes_decodes {sp:specs}{kind:int}{x:rx}{bs:bytes} (ENCODES(sp, kind, x, bs)): DECODES(sp, kind, bs, rr_ok(x))

primplement encodes_decodes {sp}{kind}{x}{bs} (e) =
  case+ e of
  | ENCODES_mk(senc, good, count, chains, app) => let
      prval APPEND_cons(a1) = app
      prval APPEND_cons(a2) = a1
      prval APPEND_cons(a3) = a2
      prval APPEND_cons(a4) = a3
      prval APPEND_cons(a5) = a4
      prval APPEND_cons(a6) = a5
      prval APPEND_cons(a7) = a6
      prval APPEND_nil() = a7
      prval magic = TAKE_succ(TAKE_succ(TAKE_succ(TAKE_succ(TAKE_zero()))))
      prval header = TAKE_succ(TAKE_succ(TAKE_succ(TAKE_zero())))
    in DECODES_body(magic, header, chains_seq(chains), FIN_ok(count, senc_sdec(count, senc))) end


(* and a record read is a record written *)
#pub prfun decodes_encodes {sp:specs}{kind:int}{x:rx}{bs:bytes} (DECODES(sp, kind, bs, rr_ok(x))): ENCODES(sp, kind, x, bs)

primplement decodes_encodes {sp}{kind}{x}{bs} (d) =
  case+ d of
  | DECODES_body(t4, t3, sq, FIN_ok(count, sdec)) => let
      prval senc = sdec_senc(count, sdec)
      prval good = senc_allgood(count, senc)
      prval chains = seq_chains(good, sq)
      prval (app_magic, _) = take_append(t4)
      prval (app_header, _) = take_append(t3)
      prval (front, whole) = append_assoc_rev(app_header, app_magic)
      prval literal = APPEND_cons(APPEND_cons(APPEND_cons(APPEND_cons(APPEND_nil()))))
      prval EQB_refl() = append_functional(literal, front)
    in ENCODES_mk(senc, good, count, chains, whole) end


(* A record read, at run time *)
#pub datavtype recread(recres, specs) =
  | {sp:specs}{ver,minver:int | 0 <= ver; ver < 256; 0 <= minver; minver <= READER}{vals:gvals}{e:extras}{kv,ke:nat}
    RR_ok(rr_ok(rx_mk(ver, minver, vals, e)), sp) of (int ver, int minver, gvalsv(sp, vals, kv), extrasv(e, ke))
  | {sp:specs}{ver,minver:int | 0 <= ver; ver < 256; 0 <= minver; minver <= READER}{vals:gvals}{e:extras}{t:lost}{kv,ke,kl:nat}
    RR_loss(rr_loss(rx_mk(ver, minver, vals, e), t), sp) of (int ver, int minver, gvalsv(sp, vals, kv), extrasv(e, ke), lostv(t, kl))
  | {sp:specs} RR_notquire(rr_notquire(), sp)
  | {sp:specs} RR_newer(rr_newer(), sp)
  | {sp:specs} RR_damaged(rr_damaged(), sp)

(* A record written, with the proof that it is the one *)
#pub fun record_write {sp:specs}{kind,ver,minver:int | 0 <= kind; kind < 256; 0 <= ver; ver < 256; 0 <= minver; minver <= READER}
  {vals:gvals}{e:extras}{ks,kv,ke:nat}
  (specs: !specsv(sp, ks), kind: int kind, ver: int ver, minver: int minver, vals: !gvalsv(sp, vals, kv), extras: !extrasv(e, ke))
  : [bs:bytes][m:nat] (ENCODES(sp, kind, rx_mk(ver, minver, vals, e), bs) | blist(bs, m))

implement record_write {sp}{kind,ver,minver}{vals}{e}{ks,kv,ke} (specs, kind, ver, minver, vals, extras) = let
  val (senc, good, count | cl) = schema_write(specs, vals, extras)
  val (chains | body) = seq_write(good | cl)
  val () = chunklist_free(cl)
  val header = blist_cons(81, blist_cons(82, blist_cons(69, blist_cons(67,
               blist_cons(kind, blist_cons(ver, blist_cons(minver, blist_nil())))))))
  val (app | out) = blist_append(header, body)
in (ENCODES_mk(senc, good, count, chains, app) | out) end


prfn _not_quire_proof {sp:specs}{kind:int}{bs,m,rest:bytes} (t: TAKE(4, bs, m, rest), d: MAGICDIFF(m))
  : DECODES(sp, kind, bs, rr_notquire()) = DECODES_magic(t, d)

fn _not_quire {sp:specs}{kind:int}{bs,m,rest:bytes}{nr:nat} (t: TAKE(4, bs, m, rest), d: MAGICDIFF(m), rest: blist(rest, nr))
  : (DECODES(sp, kind, bs, rr_notquire()) | recread(rr_notquire(), sp)) = let
  val () = blist_free(rest)
in (DECODES_magic(t, d) | RR_notquire()) end

(* A record read, with the proof of what it comes to *)
#pub fun record_read {sp:specs}{kind:int | 0 <= kind; kind < 256}{ks:nat}{bs:bytes}{n:nat}
  (specs: !specsv(sp, ks), kind: int kind, list: blist(bs, n))
  : [res:recres] (DECODES(sp, kind, bs, res) | recread(res, sp))

implement record_read {sp}{kind}{ks}{bs}{n} (specs, kind, list) =
  case+ blist_take(4, list) of
  | ~TakeShort(s | ) => (DECODES_short(s) | RR_notquire())
  | ~TakeOk(t4 | magic, rest) =>
    (case+ magic of
     | ~blist_cons(m0, ~blist_cons(m1, ~blist_cons(m2, ~blist_cons(m3, ~blist_nil())))) =>
       if m0 = 81 then if m1 = 82 then if m2 = 69 then if m3 = 67 then
         (case+ blist_take(3, rest) of
          | ~TakeShort(s | ) => (DECODES_header_short(t4, s) | RR_damaged())
          | ~TakeOk(t3 | header, body) =>
            (case+ header of
             | ~blist_cons(kd, ~blist_cons(ver, ~blist_cons(minver, ~blist_nil()))) =>
               if minver > 1 then let
                 val () = blist_free(body)
               in (DECODES_newer(t4, t3) | RR_newer()) end
               else if kd <> kind then let
                 val () = blist_free(body)
               in (DECODES_kind(t4, t3) | RR_damaged()) end
               else let
                 val (sq | r) = seq_read(body)
               in
                 case+ r of
                 | ~SR_fail() => (DECODES_body(t4, t3, sq, FIN_seq()) | RR_damaged())
                 | ~SR_ok(count | cl) => let
                     val (sd | out) = schema_read(count, specs, cl)
                   in
                     case+ out of
                     | ~SDR_ok(vals, extras) => (DECODES_body(t4, t3, sq, FIN_ok(count, sd)) | RR_ok(ver, minver, vals, extras))
                     | ~SDR_loss(vals, extras, lost) => (DECODES_body(t4, t3, sq, FIN_loss(count, sd)) | RR_loss(ver, minver, vals, extras, lost))
                     | ~SDR_fail(CausDamaged()) => (DECODES_body(t4, t3, sq, FIN_damaged(count, sd)) | RR_damaged())
                     | ~SDR_fail(CausNewer()) => (DECODES_body(t4, t3, sq, FIN_newer(count, sd)) | RR_newer())
                   end
               end))
       else _not_quire(t4, MAGICDIFF_mk(), rest)
       else _not_quire(t4, MAGICDIFF_mk(), rest)
       else _not_quire(t4, MAGICDIFF_mk(), rest)
       else _not_quire(t4, MAGICDIFF_mk(), rest))

end
