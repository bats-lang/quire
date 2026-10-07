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
  | {r:sdres} EQSD_refl(r, r)

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
  | {t0,t1,t2,t3:int | 97 <= t0; t0 < 256; 0 <= t1; t1 < 256; 0 <= t2; t2 < 256; 0 <= t3; t3 < 256}
    ANC_mk(bcons(t0, bcons(t1, bcons(t2, bcons(t3, bnil())))))

(* CRIT(tag): the first letter is not: a reader that does not know the
   chunk must refuse the record *)
#pub dataprop CRIT(bytes) =
  | {t0,t1,t2,t3:int | 0 <= t0; t0 < 97; 0 <= t1; t1 < 256; 0 <= t2; t2 < 256; 0 <= t3; t3 < 256}
    CRIT_mk(bcons(t0, bcons(t1, bcons(t2, bcons(t3, bnil())))))

(* TAGDIFF(a, b): two tags of 4 letters that differ *)
#pub dataprop TAGDIFF(bytes, bytes) =
  | {a0,a1,a2,a3,b0,b1,b2,b3:int | 0 <= a0; a0 < 256; 0 <= a1; a1 < 256; 0 <= a2; a2 < 256; 0 <= a3; a3 < 256;
       0 <= b0; b0 < 256; 0 <= b1; b1 < 256; 0 <= b2; b2 < 256; 0 <= b3; b3 < 256;
       a0 != b0 || a1 != b1 || a2 != b2 || a3 != b3}
    TAGDIFF_mk(bcons(a0, bcons(a1, bcons(a2, bcons(a3, bnil())))), bcons(b0, bcons(b1, bcons(b2, bcons(b3, bnil())))))

(* KNOWN(known, tag, k): one of the groups is called tag, the kth *)
#pub dataprop KNOWN(specs, bytes, int) =
  | {tag:bytes}{l:layout}{m:mode}{d:fvals}{rest:specs} KNOWN_here(gs_cons(tag, l, m, d, rest), tag, 0)
  | {k:nat}{tag,other:bytes}{l:layout}{m:mode}{d:fvals}{rest:specs}
    KNOWN_later(gs_cons(other, l, m, d, rest), tag, k+1) of KNOWN(rest, tag, k)

(* NOTKNOWN(known, tag): none is *)
#pub dataprop NOTKNOWN(specs, bytes) =
  | {tag:bytes} NOTKNOWN_nil(gs_nil(), tag)
  | {tag,other:bytes}{l:layout}{m:mode}{d:fvals}{rest:specs}
    NOTKNOWN_cons(gs_cons(other, l, m, d, rest), tag) of (TAGDIFF(other, tag), NOTKNOWN(rest, tag))


#pub prfun known_not_notknown {known:specs}{tag:bytes}{d:nat} (KNOWN(known, tag, d), NOTKNOWN(known, tag)): FALSEP()

prfun _known_not_notknown {known:specs}{tag:bytes}{d:nat} .<d>. (k: KNOWN(known, tag, d), n: NOTKNOWN(known, tag)): FALSEP() =
  case+ k of
  | KNOWN_here() => (case+ n of NOTKNOWN_cons(d, _) => (case+ d of TAGDIFF_mk() =/=> ()))
  | KNOWN_later(k1) => (case+ n of NOTKNOWN_cons(_, n1) => _known_not_notknown(k1, n1))

primplement known_not_notknown {known}{tag}{d} (k, n) = _known_not_notknown(k, n)

#pub prfun anc_not_crit {tag:bytes} (ANC(tag), CRIT(tag)): FALSEP()

primplement anc_not_crit {tag} (a, c) = (case+ a of ANC_mk() => (case+ c of CRIT_mk() =/=> ()))

(* PREPV(f, r, r2): r2 is r with the values f of a group in front *)
#pub dataprop PREPV(fvals, sdres, sdres) =
  | {f:fvals}{v:gvals}{e:extras} PREPV_ok(f, sd_ok(v, e), sd_ok(gv_cons(f, v), e))
  | {f:fvals}{v:gvals}{e:extras}{t:lost} PREPV_loss(f, sd_loss(v, e, t), sd_loss(gv_cons(f, v), e, t))
  | {f:fvals}{c:cause} PREPV_fail(f, sd_fail(c), sd_fail(c))

(* PREPL(d, tag, r, r2): the same, for a group that was lost: its default
   values d, and its tag among those lost *)
#pub dataprop PREPL(fvals, bytes, sdres, sdres) =
  | {d:fvals}{tag:bytes}{v:gvals}{e:extras}
    PREPL_ok(d, tag, sd_ok(v, e), sd_loss(gv_cons(d, v), e, lt_cons(tag, lt_nil())))
  | {d:fvals}{tag:bytes}{v:gvals}{e:extras}{t:lost}
    PREPL_loss(d, tag, sd_loss(v, e, t), sd_loss(gv_cons(d, v), e, lt_cons(tag, t)))
  | {d:fvals}{tag:bytes}{c:cause} PREPL_fail(d, tag, sd_fail(c), sd_fail(c))

(* PREPX(tag, data, r, r2): the same, for a chunk kept to be written back *)
#pub dataprop PREPX(bytes, bytes, sdres, sdres) =
  | {tag,data:bytes}{v:gvals}{e:extras} PREPX_ok(tag, data, sd_ok(v, e), sd_ok(v, ex_cons(tag, data, e)))
  | {tag,data:bytes}{v:gvals}{e:extras}{t:lost}
    PREPX_loss(tag, data, sd_loss(v, e, t), sd_loss(v, ex_cons(tag, data, e), t))
  | {tag,data:bytes}{c:cause} PREPX_fail(tag, data, sd_fail(c), sd_fail(c))

(* PREPT(tag, r, r2): the same, for a chunk passed over that was lost *)
#pub dataprop PREPT(bytes, sdres, sdres) =
  | {tag:bytes}{v:gvals}{e:extras} PREPT_ok(tag, sd_ok(v, e), sd_loss(v, e, lt_cons(tag, lt_nil())))
  | {tag:bytes}{v:gvals}{e:extras}{t:lost} PREPT_loss(tag, sd_loss(v, e, t), sd_loss(v, e, lt_cons(tag, t)))
  | {tag:bytes}{c:cause} PREPT_fail(tag, sd_fail(c), sd_fail(c))

#pub prfun prepv_functional {f:fvals}{r,a,b:sdres} (PREPV(f, r, a), PREPV(f, r, b)): EQSD(a, b)

primplement prepv_functional {f}{r,a,b} (p, q) =
  case+ p of
  | PREPV_ok() => (case+ q of PREPV_ok() => EQSD_refl())
  | PREPV_loss() => (case+ q of PREPV_loss() => EQSD_refl())
  | PREPV_fail() => (case+ q of PREPV_fail() => EQSD_refl())

#pub prfun prepl_functional {d:fvals}{tag:bytes}{r,a,b:sdres} (PREPL(d, tag, r, a), PREPL(d, tag, r, b)): EQSD(a, b)

primplement prepl_functional {d}{tag}{r,a,b} (p, q) =
  case+ p of
  | PREPL_ok() => (case+ q of PREPL_ok() => EQSD_refl())
  | PREPL_loss() => (case+ q of PREPL_loss() => EQSD_refl())
  | PREPL_fail() => (case+ q of PREPL_fail() => EQSD_refl())

#pub prfun prepx_functional {tag,data:bytes}{r,a,b:sdres} (PREPX(tag, data, r, a), PREPX(tag, data, r, b)): EQSD(a, b)

primplement prepx_functional {tag,data}{r,a,b} (p, q) =
  case+ p of
  | PREPX_ok() => (case+ q of PREPX_ok() => EQSD_refl())
  | PREPX_loss() => (case+ q of PREPX_loss() => EQSD_refl())
  | PREPX_fail() => (case+ q of PREPX_fail() => EQSD_refl())

#pub prfun prept_functional {tag:bytes}{r,a,b:sdres} (PREPT(tag, r, a), PREPT(tag, r, b)): EQSD(a, b)

primplement prept_functional {tag}{r,a,b} (p, q) =
  case+ p of
  | PREPT_ok() => (case+ q of PREPT_ok() => EQSD_refl())
  | PREPT_loss() => (case+ q of PREPT_loss() => EQSD_refl())
  | PREPT_fail() => (case+ q of PREPT_fail() => EQSD_refl())


#pub prfun falsep_eqsd {a,b:sdres} (FALSEP()): EQSD(a, b)

primplement falsep_eqsd {a,b} (f) = case+ f of FALSEP_mk() =/=> ()

(* XDEC(known, pcs, res): what follows the known groups is read *)
#pub dataprop XDEC(specs, pchunks, sdres) =
  | {known:specs} XD_nil(known, pnil(), sd_ok(gv_nil(), ex_nil()))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{r,r2:sdres}
    XD_anc(known, pgood(tag, data, rest), r2) of (ANC(tag), XDEC(known, rest, r), PREPX(tag, data, r, r2))
  | {known:specs}{tag:bytes}{rest:pchunks}{r,r2:sdres}
    XD_anc_lost(known, pbad(tag, rest), r2) of (ANC(tag), XDEC(known, rest, r), PREPT(tag, r, r2))
  | {known:specs}{tag,data:bytes}{rest:pchunks}
    XD_newer(known, pgood(tag, data, rest), sd_fail(cause_newer())) of (CRIT(tag), NOTKNOWN(known, tag))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{k:nat}
    XD_known(known, pgood(tag, data, rest), sd_fail(cause_damaged())) of (CRIT(tag), KNOWN(known, tag, k))
  | {known:specs}{tag:bytes}{rest:pchunks}
    XD_crit_bad(known, pbad(tag, rest), sd_fail(cause_damaged())) of CRIT(tag)

#pub prfun xdec_functional {known:specs}{pcs:pchunks}{n:nat}{a,b:sdres} (PCN(n, pcs), XDEC(known, pcs, a), XDEC(known, pcs, b)): EQSD(a, b)

prfun _xdec_functional {known:specs}{pcs:pchunks}{n:nat}{a,b:sdres} .<n>.
  (count: PCN(n, pcs), p: XDEC(known, pcs, a), q: XDEC(known, pcs, b)): EQSD(a, b) =
  case+ p of
  | XD_nil() => (case+ q of XD_nil() => EQSD_refl())
  | XD_anc(pa, pr, pp) =>
    (case+ q of
     | XD_anc(_, qr, qp) => let
         prval PCN_good(count1) = count
         prval EQSD_refl() = _xdec_functional(count1, pr, qr)
       in prepx_functional(pp, qp) end
     | XD_newer(qc, _) => falsep_eqsd(anc_not_crit(pa, qc))
     | XD_known(qc, _) => falsep_eqsd(anc_not_crit(pa, qc)))
  | XD_anc_lost(pa, pr, pp) =>
    (case+ q of
     | XD_anc_lost(_, qr, qp) => let
         prval PCN_bad(count1) = count
         prval EQSD_refl() = _xdec_functional(count1, pr, qr)
       in prept_functional(pp, qp) end
     | XD_crit_bad(qc) => falsep_eqsd(anc_not_crit(pa, qc)))
  | XD_newer(pc, pn) =>
    (case+ q of
     | XD_anc(qa, _, _) => falsep_eqsd(anc_not_crit(qa, pc))
     | XD_newer(_, _) => EQSD_refl()
     | XD_known(_, qk) => falsep_eqsd(known_not_notknown(qk, pn)))
  | XD_known(pc, pk) =>
    (case+ q of
     | XD_anc(qa, _, _) => falsep_eqsd(anc_not_crit(qa, pc))
     | XD_newer(_, qn) => falsep_eqsd(known_not_notknown(pk, qn))
     | XD_known(_, _) => EQSD_refl())
  | XD_crit_bad(pc) =>
    (case+ q of
     | XD_anc_lost(qa, _, _) => falsep_eqsd(anc_not_crit(qa, pc))
     | XD_crit_bad(_) => EQSD_refl())

primplement xdec_functional {known}{pcs}{n}{a,b} (count, p, q) = _xdec_functional(count, p, q)


(* SDEC(known, specs, pcs, res): the groups of specs are read from pcs,
   and what follows them *)
#pub dataprop SDEC(specs, specs, pchunks, sdres) =
  | {known:specs}{pcs:pchunks}{res:sdres}
    SD_nil(known, gs_nil(), pcs, res) of XDEC(known, pcs, res)
  | {known,more:specs}{s:bytes}{l:layout}{m:mode}{d:fvals}{data:bytes}{nd:nat}{rest:pchunks}{v:fvals}{r,r2:sdres}
    SD_present(known, gs_cons(s, l, m, d, more), pgood(s, data, rest), r2)
    of (LEN(data, nd), FDEC(l, data, fd_ok(v)), SDEC(known, more, rest, r), PREPV(v, r, r2))
  | {known,more:specs}{s:bytes}{l:layout}{d:fvals}{data:bytes}{nd:nat}{rest:pchunks}
    SD_garbled_req(known, gs_cons(s, l, m_req(), d, more), pgood(s, data, rest), sd_fail(cause_damaged()))
    of (LEN(data, nd), FDEC(l, data, fd_bad()))
  | {known,more:specs}{s:bytes}{l:layout}{d:fvals}{data:bytes}{nd:nat}{rest:pchunks}{r,r2:sdres}
    SD_garbled_opt(known, gs_cons(s, l, m_opt(), d, more), pgood(s, data, rest), r2)
    of (LEN(data, nd), FDEC(l, data, fd_bad()), SDEC(known, more, rest, r), PREPL(d, s, r, r2))
  | {known,more:specs}{s:bytes}{l:layout}{d:fvals}{rest:pchunks}
    SD_bad_req(known, gs_cons(s, l, m_req(), d, more), pbad(s, rest), sd_fail(cause_damaged()))
  | {known,more:specs}{s:bytes}{l:layout}{d:fvals}{rest:pchunks}{r,r2:sdres}
    SD_bad_opt(known, gs_cons(s, l, m_opt(), d, more), pbad(s, rest), r2)
    of (SDEC(known, more, rest, r), PREPL(d, s, r, r2))
  | {known,more:specs}{s:bytes}{l:layout}{m:mode}{d:fvals}
    SD_missing_end(known, gs_cons(s, l, m, d, more), pnil(), sd_fail(cause_damaged()))
  | {known,more:specs}{s,tag,data:bytes}{l:layout}{m:mode}{d:fvals}{rest:pchunks}
    SD_missing_good(known, gs_cons(s, l, m, d, more), pgood(tag, data, rest), sd_fail(cause_damaged()))
    of TAGDIFF(tag, s)
  | {known,more:specs}{s,tag:bytes}{l:layout}{m:mode}{d:fvals}{rest:pchunks}
    SD_missing_bad(known, gs_cons(s, l, m, d, more), pbad(tag, rest), sd_fail(cause_damaged()))
    of TAGDIFF(tag, s)


#pub prfun sdec_functional {known,sp:specs}{pcs:pchunks}{n:nat}{a,b:sdres}
  (PCN(n, pcs), SDEC(known, sp, pcs, a), SDEC(known, sp, pcs, b)): EQSD(a, b)

prfun _sdec_functional {known,sp:specs}{pcs:pchunks}{n:nat}{a,b:sdres} .<n>.
  (count: PCN(n, pcs), p: SDEC(known, sp, pcs, a), q: SDEC(known, sp, pcs, b)): EQSD(a, b) =
  case+ p of
  | SD_nil(px) => (case+ q of SD_nil(qx) => xdec_functional(count, px, qx))
  | SD_present(pl, pf, pr, pp) =>
    (case+ q of
     | SD_present(ql, qf, qr, qp) => let
         prval PCN_good(count1) = count
         prval EQI_refl() = len_functional(pl, ql)
         prval EQFD_refl() = fdec_functional(pl, pf, qf)
         prval EQSD_refl() = _sdec_functional(count1, pr, qr)
       in prepv_functional(pp, qp) end
     | SD_garbled_req(ql, qf) => let prval EQI_refl() = len_functional(pl, ql) in (case+ fdec_functional(pl, pf, qf) of EQFD_refl() =/=> ()) end
     | SD_garbled_opt(ql, qf, _, _) => let prval EQI_refl() = len_functional(pl, ql) in (case+ fdec_functional(pl, pf, qf) of EQFD_refl() =/=> ()) end
     | SD_missing_good(qd) => (case+ qd of TAGDIFF_mk() =/=> ()))
  | SD_garbled_req(pl, pf) =>
    (case+ q of
     | SD_present(ql, qf, _, _) => let prval EQI_refl() = len_functional(pl, ql) in (case+ fdec_functional(pl, pf, qf) of EQFD_refl() =/=> ()) end
     | SD_garbled_req(_, _) => EQSD_refl()
     | SD_missing_good(qd) => (case+ qd of TAGDIFF_mk() =/=> ()))
  | SD_garbled_opt(pl, pf, pr, pp) =>
    (case+ q of
     | SD_present(ql, qf, _, _) => let prval EQI_refl() = len_functional(pl, ql) in (case+ fdec_functional(pl, pf, qf) of EQFD_refl() =/=> ()) end
     | SD_garbled_opt(_, _, qr, qp) => let
         prval PCN_good(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, pr, qr)
       in prepl_functional(pp, qp) end
     | SD_missing_good(qd) => (case+ qd of TAGDIFF_mk() =/=> ()))
  | SD_bad_req() =>
    (case+ q of
     | SD_bad_req() => EQSD_refl()
     | SD_missing_bad(qd) => (case+ qd of TAGDIFF_mk() =/=> ()))
  | SD_bad_opt(pr, pp) =>
    (case+ q of
     | SD_bad_opt(qr, qp) => let
         prval PCN_bad(count1) = count
         prval EQSD_refl() = _sdec_functional(count1, pr, qr)
       in prepl_functional(pp, qp) end
     | SD_missing_bad(qd) => (case+ qd of TAGDIFF_mk() =/=> ()))
  | SD_missing_end() => (case+ q of SD_missing_end() => EQSD_refl())
  | SD_missing_good(pd) =>
    (case+ q of
     | SD_present(_, _, _, _) => (case+ pd of TAGDIFF_mk() =/=> ())
     | SD_garbled_req(_, _) => (case+ pd of TAGDIFF_mk() =/=> ())
     | SD_garbled_opt(_, _, _, _) => (case+ pd of TAGDIFF_mk() =/=> ())
     | SD_missing_good(_) => EQSD_refl())
  | SD_missing_bad(pd) =>
    (case+ q of
     | SD_bad_req() => (case+ pd of TAGDIFF_mk() =/=> ())
     | SD_bad_opt(_, _) => (case+ pd of TAGDIFF_mk() =/=> ())
     | SD_missing_bad(_) => EQSD_refl())

primplement sdec_functional {known,sp}{pcs}{n}{a,b} (count, p, q) = _sdec_functional(count, p, q)


(* XENC(e, pcs): pcs are the chunks kept in e, written back *)
#pub dataprop XENC(extras, pchunks) =
  | XENC_nil(ex_nil(), pnil())
  | {tag,data:bytes}{e:extras}{rest:pchunks}
    XENC_cons(ex_cons(tag, data, e), pgood(tag, data, rest)) of (ANC(tag), XENC(e, rest))

(* SENC(specs, vals, e, pcs): pcs are the chunks of the groups of specs
   holding vals, then those kept in e *)
#pub dataprop SENC(specs, gvals, extras, pchunks) =
  | {e:extras}{pcs:pchunks} SENC_nil(gs_nil(), gv_nil(), e, pcs) of XENC(e, pcs)
  | {s:bytes}{l:layout}{m:mode}{d:fvals}{more:specs}{v:fvals}{vals:gvals}{e:extras}{data:bytes}{nd:nat}{rest:pchunks}
    SENC_cons(gs_cons(s, l, m, d, more), gv_cons(v, vals), e, pgood(s, data, rest))
    of (LEN(data, nd), FENC(l, v, data), SENC(more, vals, e, rest))

#pub prfun xenc_xdec {known:specs}{e:extras}{pcs:pchunks}{n:nat} (PCN(n, pcs), XENC(e, pcs))
  : XDEC(known, pcs, sd_ok(gv_nil(), e))

prfun _xenc_xdec {known:specs}{e:extras}{pcs:pchunks}{n:nat} .<n>. (count: PCN(n, pcs), x: XENC(e, pcs))
  : XDEC(known, pcs, sd_ok(gv_nil(), e)) =
  case+ x of
  | XENC_nil() => XD_nil()
  | XENC_cons(a, rest) => let
      prval PCN_good(count1) = count
    in XD_anc(a, _xenc_xdec(count1, rest), PREPX_ok()) end

primplement xenc_xdec {known}{e}{pcs}{n} (count, x) = _xenc_xdec(count, x)

#pub dataprop EQG(gvals, gvals) =
  | {g:gvals} EQG_refl(g, g)

#pub prfun xdec_ok_nil {known:specs}{v:gvals}{e:extras}{pcs:pchunks}{n:nat} (PCN(n, pcs), XDEC(known, pcs, sd_ok(v, e)))
  : EQG(v, gv_nil())

prfun _xdec_ok_nil {known:specs}{v:gvals}{e:extras}{pcs:pchunks}{n:nat} .<n>. (count: PCN(n, pcs), x: XDEC(known, pcs, sd_ok(v, e)))
  : EQG(v, gv_nil()) =
  case+ x of
  | XD_nil() => EQG_refl()
  | XD_anc(_, rest, PREPX_ok()) => let
      prval PCN_good(count1) = count
    in _xdec_ok_nil(count1, rest) end
  | XD_anc_lost(_, _, pp) => (case+ pp of PREPT_ok() =/=> () | PREPT_loss() =/=> () | PREPT_fail() =/=> ())

primplement xdec_ok_nil {known}{v}{e}{pcs}{n} (count, x) = _xdec_ok_nil(count, x)

#pub prfun xdec_xenc {known:specs}{v:gvals}{e:extras}{pcs:pchunks}{n:nat} (PCN(n, pcs), XDEC(known, pcs, sd_ok(v, e)))
  : XENC(e, pcs)

prfun _xdec_xenc {known:specs}{v:gvals}{e:extras}{pcs:pchunks}{n:nat} .<n>. (count: PCN(n, pcs), x: XDEC(known, pcs, sd_ok(v, e)))
  : XENC(e, pcs) =
  case+ x of
  | XD_nil() => XENC_nil()
  | XD_anc(a, rest, PREPX_ok()) => let
      prval PCN_good(count1) = count
    in XENC_cons(a, _xdec_xenc(count1, rest)) end
  | XD_anc_lost(_, _, pp) => (case+ pp of PREPT_ok() =/=> () | PREPT_loss() =/=> () | PREPT_fail() =/=> ())

primplement xdec_xenc {known}{v}{e}{pcs}{n} (count, x) = _xdec_xenc(count, x)

#pub prfun senc_sdec {known,sp:specs}{vals:gvals}{e:extras}{pcs:pchunks}{n:nat} (PCN(n, pcs), SENC(sp, vals, e, pcs))
  : SDEC(known, sp, pcs, sd_ok(vals, e))

prfun _senc_sdec {known,sp:specs}{vals:gvals}{e:extras}{pcs:pchunks}{n:nat} .<n>. (count: PCN(n, pcs), x: SENC(sp, vals, e, pcs))
  : SDEC(known, sp, pcs, sd_ok(vals, e)) =
  case+ x of
  | SENC_nil(xe) => SD_nil(xenc_xdec(count, xe))
  | SENC_cons(l, f, rest) => let
      prval PCN_good(count1) = count
    in SD_present(l, fenc_fdec(l, f), _senc_sdec(count1, rest), PREPV_ok()) end

primplement senc_sdec {known,sp}{vals}{e}{pcs}{n} (count, x) = _senc_sdec(count, x)

#pub prfun sdec_senc {known,sp:specs}{vals:gvals}{e:extras}{pcs:pchunks}{n:nat} (PCN(n, pcs), SDEC(known, sp, pcs, sd_ok(vals, e)))
  : SENC(sp, vals, e, pcs)

prfun _sdec_senc {known,sp:specs}{vals:gvals}{e:extras}{pcs:pchunks}{n:nat} .<n>. (count: PCN(n, pcs), x: SDEC(known, sp, pcs, sd_ok(vals, e)))
  : SENC(sp, vals, e, pcs) =
  case+ x of
  | SD_nil(xx) => (case+ xdec_ok_nil(count, xx) of EQG_refl() => SENC_nil(xdec_xenc(count, xx)))
  | SD_present(l, f, rest, PREPV_ok()) => let
      prval PCN_good(count1) = count
    in SENC_cons(l, fdec_fenc(l, f), _sdec_senc(count1, rest)) end
  | SD_garbled_opt(_, _, _, pp) => (case+ pp of PREPL_ok() =/=> () | PREPL_loss() =/=> () | PREPL_fail() =/=> ())
  | SD_bad_opt(_, pp) => (case+ pp of PREPL_ok() =/=> () | PREPL_loss() =/=> () | PREPL_fail() =/=> ())

primplement sdec_senc {known,sp}{vals}{e}{pcs}{n} (count, x) = _sdec_senc(count, x)


(* The groups of a record, at run time, k of them: each one's tag, the
   kinds of its fields, whether it is needed, and its values when lost *)
#pub datatype modev(mode) =
  | ModeReq(m_req())
  | ModeOpt(m_opt())

#pub datavtype specsv(specs, int) =
  | SPV_nil(gs_nil(), 0)
  | {s:bytes}{l:layout}{m:mode}{d:fvals}{more:specs}{k,fk:nat | fk < 1000}
    SPV_cons(gs_cons(s, l, m, d, more), k+1) of (TAGNOT(s) | blist(s, 4), layoutv(l, fk), modev(m), fvalsv(l, d, fk), specsv(more, k))

#pub fun specsv_free {sp:specs}{k:nat} (specs: specsv(sp, k)): void

implement specsv_free {sp}{k} (specs) = let
  fun go {sp:specs}{k:nat} .<k>. (specs: specsv(sp, k)): void =
    case+ specs of
    | ~SPV_nil() => ()
    | ~SPV_cons(_ | tag, layout, _, default, more) => let
        val () = blist_free(tag)
        val () = layoutv_free(layout)
        val () = fvalsv_free(default)
      in go(more) end
in go(specs) end

#pub fun specsv_copy {sp:specs}{k:nat} (specs: !specsv(sp, k)): specsv(sp, k)

implement specsv_copy {sp}{k} (specs) = let
  fun go {sp:specs}{k:nat} .<k>. (specs: !specsv(sp, k)): specsv(sp, k) =
    case+ specs of
    | SPV_nil() => SPV_nil()
    | SPV_cons(tn | tag, layout, mode, default, more) =>
      SPV_cons(tn | blist_copy(tag), layoutv_copy(layout), mode, fvalsv_copy(default), go(more))
in go(specs) end

(* The values of the groups, at run time *)
#pub datavtype gvalsv(specs, gvals, int) =
  | GVV_nil(gs_nil(), gv_nil(), 0)
  | {s:bytes}{l:layout}{m:mode}{d:fvals}{more:specs}{v:fvals}{vals:gvals}{k,fk:nat | fk < 1000}
    GVV_cons(gs_cons(s, l, m, d, more), gv_cons(v, vals), k+1) of (fvalsv(l, v, fk), gvalsv(more, vals, k))

#pub fun gvalsv_free {sp:specs}{vals:gvals}{k:nat} (vals: gvalsv(sp, vals, k)): void

implement gvalsv_free {sp}{vals}{k} (vals) = let
  fun go {sp:specs}{vals:gvals}{k:nat} .<k>. (vals: gvalsv(sp, vals, k)): void =
    case+ vals of
    | ~GVV_nil() => ()
    | ~GVV_cons(v, more) => let val () = fvalsv_free(v) in go(more) end
in go(vals) end

(* The chunks kept to be written back, at run time *)
#pub datavtype extrasv(extras, int) =
  | EXV_nil(ex_nil(), 0)
  | {tag,data:bytes}{e:extras}{nd,k:nat | nd < 1048576}
    EXV_cons(ex_cons(tag, data, e), k+1) of (ANC(tag) | blist(tag, 4), blist(data, nd), extrasv(e, k))

#pub fun extrasv_free {e:extras}{k:nat} (extras: extrasv(e, k)): void

implement extrasv_free {e}{k} (extras) = let
  fun go {e:extras}{k:nat} .<k>. (extras: extrasv(e, k)): void =
    case+ extras of
    | ~EXV_nil() => ()
    | ~EXV_cons(_ | tag, data, more) => let
        val () = blist_free(tag)
        val () = blist_free(data)
      in go(more) end
in go(extras) end

(* The tags of the chunks lost, at run time *)
#pub datavtype lostv(lost, int) =
  | LTV_nil(lt_nil(), 0)
  | {tag:bytes}{t:lost}{k:nat} LTV_cons(lt_cons(tag, t), k+1) of (blist(tag, 4), lostv(t, k))

#pub fun lostv_free {t:lost}{k:nat} (lost: lostv(t, k)): void

implement lostv_free {t}{k} (lost) = let
  fun go {t:lost}{k:nat} .<k>. (lost: lostv(t, k)): void =
    case+ lost of
    | ~LTV_nil() => ()
    | ~LTV_cons(tag, more) => let val () = blist_free(tag) in go(more) end
in go(lost) end

#pub datatype causev(cause) =
  | CausDamaged(cause_damaged())
  | CausNewer(cause_newer())

(* What reading the groups of a record comes to *)
#pub datavtype schemaread(sdres, specs) =
  | {sp:specs}{vals:gvals}{e:extras}{kv,ke:nat}
    SDR_ok(sd_ok(vals, e), sp) of (gvalsv(sp, vals, kv), extrasv(e, ke))
  | {sp:specs}{vals:gvals}{e:extras}{t:lost}{kv,ke,kl:nat}
    SDR_loss(sd_loss(vals, e, t), sp) of (gvalsv(sp, vals, kv), extrasv(e, ke), lostv(t, kl))
  | {sp:specs}{c:cause} SDR_fail(sd_fail(c), sp) of causev(c)


#pub prfun xenc_allgood {e:extras}{pcs:pchunks}{n:nat} (PCN(n, pcs), XENC(e, pcs)): ALLGOOD(n, pcs)

prfun _xenc_allgood {e:extras}{pcs:pchunks}{n:nat} .<n>. (count: PCN(n, pcs), x: XENC(e, pcs)): ALLGOOD(n, pcs) =
  case+ x of
  | XENC_nil() => (case+ count of PCN_nil() => ALLGOOD_nil())
  | XENC_cons(_, rest) => (case+ count of PCN_good(count1) => ALLGOOD_cons(_xenc_allgood(count1, rest)))

primplement xenc_allgood {e}{pcs}{n} (count, x) = _xenc_allgood(count, x)

#pub prfun senc_allgood {sp:specs}{vals:gvals}{e:extras}{pcs:pchunks}{n:nat} (PCN(n, pcs), SENC(sp, vals, e, pcs)): ALLGOOD(n, pcs)

prfun _senc_allgood {sp:specs}{vals:gvals}{e:extras}{pcs:pchunks}{n:nat} .<n>. (count: PCN(n, pcs), x: SENC(sp, vals, e, pcs)): ALLGOOD(n, pcs) =
  case+ x of
  | SENC_nil(xe) => xenc_allgood(count, xe)
  | SENC_cons(_, _, rest) => (case+ count of PCN_good(count1) => ALLGOOD_cons(_senc_allgood(count1, rest)))

primplement senc_allgood {sp}{vals}{e}{pcs}{n} (count, x) = _senc_allgood(count, x)

datavtype tagcmp(bytes, bytes) =
  | {a,b:bytes} TagSame(a, b) of (EQB(a, b) | )
  | {a,b:bytes} TagDiff(a, b) of (TAGDIFF(a, b) | )

fn _tag_compare {a,b:bytes} (x: !blist(a, 4), y: !blist(b, 4)): tagcmp(a, b) =
  case+ x of
  | blist_cons(a0, blist_cons(a1, blist_cons(a2, blist_cons(a3, blist_nil())))) =>
    (case+ y of
     | blist_cons(b0, blist_cons(b1, blist_cons(b2, blist_cons(b3, blist_nil())))) =>
       if a0 = b0 then
         (if a1 = b1 then
            (if a2 = b2 then
               (if a3 = b3 then TagSame(EQB_refl() | ) else TagDiff(TAGDIFF_mk() | ))
             else TagDiff(TAGDIFF_mk() | ))
          else TagDiff(TAGDIFF_mk() | ))
       else TagDiff(TAGDIFF_mk() | ))

(* whether a tag is one of the groups' *)
datavtype knownres(specs, bytes) =
  | {known:specs}{tag:bytes}{d:nat} KnownYes(known, tag) of (KNOWN(known, tag, d) | )
  | {known:specs}{tag:bytes} KnownNo(known, tag) of (NOTKNOWN(known, tag) | )

fn _known_find {known:specs}{tag:bytes}{k:nat} (tag: !blist(tag, 4), known: !specsv(known, k)): knownres(known, tag) = let
  fun go {known:specs}{tag:bytes}{k:nat} .<k>. (tag: !blist(tag, 4), known: !specsv(known, k)): knownres(known, tag) =
    case+ known of
    | SPV_nil() => KnownNo(NOTKNOWN_nil() | )
    | SPV_cons(_ | stag, _, _, _, more) =>
      (case+ _tag_compare(stag, tag) of
       | ~TagSame(EQB_refl() | ) => KnownYes(KNOWN_here() | )
       | ~TagDiff(different | ) =>
         (case+ go(tag, more) of
          | ~KnownYes(kp | ) => KnownYes(KNOWN_later(kp) | )
          | ~KnownNo(np | ) => KnownNo(NOTKNOWN_cons(different, np) | )))
in go(tag, known) end


datavtype tagclass(bytes) =
  | {tag:bytes} IsAnc(tag) of (ANC(tag) | )
  | {tag:bytes} IsCrit(tag) of (CRIT(tag) | )

fn _tag_class {tag:bytes} (tag: !blist(tag, 4)): tagclass(tag) =
  case+ tag of
  | blist_cons(t0, blist_cons(_, blist_cons(_, blist_cons(_, blist_nil())))) =>
    if t0 >= 97 then IsAnc(ANC_mk() | ) else IsCrit(CRIT_mk() | )

(* Reading what follows the known groups *)
fun xdec_read {known:specs}{kk:nat}{pcs:pchunks}{n:nat} .<n>.
  (count: PCN(n, pcs), known: !specsv(known, kk), cl: chunklist(pcs, n))
  : [res:sdres] (XDEC(known, pcs, res) | schemaread(res, gs_nil())) =
  case+ cl of
  | ~CL_nil() => (XD_nil() | SDR_ok(GVV_nil(), EXV_nil()))
  | ~CL_good(_ | tag, data, rest) => let
      prval PCN_good(count1) = count
    in
      case+ _tag_class(tag) of
      | ~IsAnc(anc | ) => let
          val (sub | r) = xdec_read(count1, known, rest)
        in
          case+ r of
          | ~SDR_ok(~GVV_nil(), extras) =>
            (XD_anc(anc, sub, PREPX_ok()) | SDR_ok(GVV_nil(), EXV_cons(anc | tag, data, extras)))
          | ~SDR_loss(~GVV_nil(), extras, lost) =>
            (XD_anc(anc, sub, PREPX_loss()) | SDR_loss(GVV_nil(), EXV_cons(anc | tag, data, extras), lost))
          | ~SDR_fail(c) => let
              val () = blist_free(tag)
              val () = blist_free(data)
            in (XD_anc(anc, sub, PREPX_fail()) | SDR_fail(c)) end
        end
      | ~IsCrit(crit | ) => let
          val () = chunklist_free(rest)
          val found = _known_find(tag, known)
          val () = blist_free(tag)
          val () = blist_free(data)
        in
          case+ found of
          | ~KnownYes(kp | ) => (XD_known(crit, kp) | SDR_fail(CausDamaged()))
          | ~KnownNo(np | ) => (XD_newer(crit, np) | SDR_fail(CausNewer()))
        end
    end
  | ~CL_bad(tag, rest) => let
      prval PCN_bad(count1) = count
    in
      case+ _tag_class(tag) of
      | ~IsAnc(anc | ) => let
          val (sub | r) = xdec_read(count1, known, rest)
        in
          case+ r of
          | ~SDR_ok(~GVV_nil(), extras) =>
            (XD_anc_lost(anc, sub, PREPT_ok()) | SDR_loss(GVV_nil(), extras, LTV_cons(tag, LTV_nil())))
          | ~SDR_loss(~GVV_nil(), extras, lost) =>
            (XD_anc_lost(anc, sub, PREPT_loss()) | SDR_loss(GVV_nil(), extras, LTV_cons(tag, lost)))
          | ~SDR_fail(c) => let
              val () = blist_free(tag)
            in (XD_anc_lost(anc, sub, PREPT_fail()) | SDR_fail(c)) end
        end
      | ~IsCrit(crit | ) => let
          val () = chunklist_free(rest)
          val () = blist_free(tag)
        in (XD_crit_bad(crit) | SDR_fail(CausDamaged())) end
    end


(* Reading the groups of a record, then what follows them *)
fun sdec_read {known,sp:specs}{kk,ks:nat}{pcs:pchunks}{n:nat} .<n>.
  (count: PCN(n, pcs), known: !specsv(known, kk), specs: !specsv(sp, ks), cl: chunklist(pcs, n))
  : [res:sdres] (SDEC(known, sp, pcs, res) | schemaread(res, sp)) =
  case+ specs of
  | SPV_nil() => let
      val (sub | r) = xdec_read(count, known, cl)
    in (SD_nil(sub) | r) end
  | SPV_cons(_ | stag, layout, mode, default, more) =>
    (case+ cl of
     | ~CL_nil() => (SD_missing_end() | SDR_fail(CausDamaged()))
     | ~CL_good(_ | tag, data, rest) => let
         prval PCN_good(count1) = count
       in
         case+ _tag_compare(tag, stag) of
         | ~TagDiff(different | ) => let
             val () = blist_free(tag)
             val () = blist_free(data)
             val () = chunklist_free(rest)
           in (SD_missing_good(different) | SDR_fail(CausDamaged())) end
         | ~TagSame(EQB_refl() | ) => let
             val () = blist_free(tag)
             val (len | _) = blist_len(data)
             val (fd | r) = fields_read(layout, data)
           in
             case+ r of
             | ~FDR_ok(vals) => let
                 val (sub | r2) = sdec_read(count1, known, more, rest)
               in
                 case+ r2 of
                 | ~SDR_ok(gv, ex) => (SD_present(len, fd, sub, PREPV_ok()) | SDR_ok(GVV_cons(vals, gv), ex))
                 | ~SDR_loss(gv, ex, lost) => (SD_present(len, fd, sub, PREPV_loss()) | SDR_loss(GVV_cons(vals, gv), ex, lost))
                 | ~SDR_fail(c) => let val () = fvalsv_free(vals) in (SD_present(len, fd, sub, PREPV_fail()) | SDR_fail(c)) end
               end
             | ~FDR_bad() =>
               (case+ mode of
                | ModeReq() => let val () = chunklist_free(rest) in (SD_garbled_req(len, fd) | SDR_fail(CausDamaged())) end
                | ModeOpt() => let
                    val (sub | r2) = sdec_read(count1, known, more, rest)
                  in
                    case+ r2 of
                    | ~SDR_ok(gv, ex) =>
                      (SD_garbled_opt(len, fd, sub, PREPL_ok())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), gv), ex, LTV_cons(blist_copy(stag), LTV_nil())))
                    | ~SDR_loss(gv, ex, lost) =>
                      (SD_garbled_opt(len, fd, sub, PREPL_loss())
                       | SDR_loss(GVV_cons(fvalsv_copy(default), gv), ex, LTV_cons(blist_copy(stag), lost)))
                    | ~SDR_fail(c) => (SD_garbled_opt(len, fd, sub, PREPL_fail()) | SDR_fail(c))
                  end)
           end
       end
     | ~CL_bad(tag, rest) => let
         prval PCN_bad(count1) = count
       in
         case+ _tag_compare(tag, stag) of
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
                 val (sub | r2) = sdec_read(count1, known, more, rest)
               in
                 case+ r2 of
                 | ~SDR_ok(gv, ex) =>
                   (SD_bad_opt(sub, PREPL_ok())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), gv), ex, LTV_cons(blist_copy(stag), LTV_nil())))
                 | ~SDR_loss(gv, ex, lost) =>
                   (SD_bad_opt(sub, PREPL_loss())
                    | SDR_loss(GVV_cons(fvalsv_copy(default), gv), ex, LTV_cons(blist_copy(stag), lost)))
                 | ~SDR_fail(c) => (SD_bad_opt(sub, PREPL_fail()) | SDR_fail(c))
               end
           end
       end)


prfn _anc_tagnot {tag:bytes} (a: ANC(tag)): TAGNOT(tag) =
  case+ a of ANC_mk() => TAGNOT_mk()

(* The chunks that hold the kept chunks, with the proof *)
fun _extras_write {e:extras}{ke:nat} .<ke>. (extras: !extrasv(e, ke))
  : [pcs:pchunks][n:nat] (XENC(e, pcs), ALLGOOD(n, pcs), PCN(n, pcs) | chunklist(pcs, n)) =
  case+ extras of
  | EXV_nil() => (XENC_nil(), ALLGOOD_nil(), PCN_nil() | CL_nil())
  | EXV_cons(anc | tag, data, more) => let
      val (x, good, count | rest) = _extras_write(more)
    in
      (XENC_cons(anc, x), ALLGOOD_cons(good), PCN_good(count)
       | CL_good(_anc_tagnot(anc) | blist_copy(tag), blist_copy(data), rest))
    end

(* The chunks of a record's groups and kept chunks, with the proof *)
#pub fun schema_write {sp:specs}{vals:gvals}{e:extras}{ks,kv,ke:nat}
  (specs: !specsv(sp, ks), vals: !gvalsv(sp, vals, kv), extras: !extrasv(e, ke))
  : [pcs:pchunks][n:nat] (SENC(sp, vals, e, pcs), ALLGOOD(n, pcs), PCN(n, pcs) | chunklist(pcs, n))

implement schema_write {sp}{vals}{e}{ks,kv,ke} (specs, vals, extras) = let
  fun go {sp:specs}{vals:gvals}{e:extras}{ks,kv,ke:nat} .<ks>.
    (specs: !specsv(sp, ks), vals: !gvalsv(sp, vals, kv), extras: !extrasv(e, ke))
    : [pcs:pchunks][n:nat] (SENC(sp, vals, e, pcs), ALLGOOD(n, pcs), PCN(n, pcs) | chunklist(pcs, n)) =
    case+ specs of
    | SPV_nil() => let
        prval GVV_nil() = vals
        val (x, good, count | cl) = _extras_write(extras)
      in (SENC_nil(x), good, count | cl) end
    | SPV_cons(tn | stag, _, _, _, more) =>
      (case+ vals of
       | GVV_cons(v, more_vals) => let
           val (fe | data) = fields_write(v)
           val (len | _) = blist_len(data)
           val (sub, good, count | rest) = go(more, more_vals, extras)
         in
           (SENC_cons(len, fe, sub), ALLGOOD_cons(good), PCN_good(count)
            | CL_good(tn | blist_copy(stag), data, rest))
         end)
in go(specs, vals, extras) end


(* Reading the groups of a record, with the proof *)
#pub fun schema_read {sp:specs}{ks:nat}{pcs:pchunks}{n:nat}
  (count: PCN(n, pcs), specs: !specsv(sp, ks), cl: chunklist(pcs, n))
  : [res:sdres] (SDEC(sp, sp, pcs, res) | schemaread(res, sp))

implement schema_read {sp}{ks}{pcs}{n} (count, specs, cl) = let
  val known = specsv_copy(specs)
  val result = sdec_read(count, known, specs, cl)
  val () = specsv_free(known)
in result end

end
