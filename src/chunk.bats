(* chunk -- the framing of a record: length, tag, data, checksum *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "bytes.sats"
staload "crc.sats"

(* CRCP(tag, data, hi, lo): the checksum of the tag followed by the
   data, as two 16-bit halves *)
#pub dataprop CRCP(bytes, bytes, int, int) =
  | {nt,nd:nat}{tag,data:bytes}{h0,l0,h1,l1:nat | h1 < 65536; l1 < 65536}
    CRCP_mk(tag, data, 65535 - h1, 65535 - l1)
    of (LEN(tag, nt), LEN(data, nd), CRCFROM(65535, 65535, tag, h0, l0), CRCFROM(h0, l0, data, h1, l1))

#pub prfun crcp_functional {tag,data:bytes}{h1,l1,h2,l2:int} (CRCP(tag, data, h1, l1), CRCP(tag, data, h2, l2))
  : [h1 == h2 && l1 == l2] void

prfn _crcp_functional {tag,data:bytes}{h1,l1,h2,l2:int} (p: CRCP(tag, data, h1, l1), q: CRCP(tag, data, h2, l2))
  : [h1 == h2 && l1 == l2] void =
  case+ p of
  | CRCP_mk(pt, pd, pa, pb) =>
    (case+ q of
     | CRCP_mk(qt, qd, qa, qb) => let
         prval EQI_refl() = len_functional(pt, qt)
         prval EQI_refl() = len_functional(pd, qd)
         prval () = crcfrom_functional(pt, pa, qa)
       in crcfrom_functional(pd, pb, qb) end)

primplement crcp_functional {tag,data}{h1,l1,h2,l2} (p, q) = _crcp_functional(p, q)


(* What a chunk read from some bytes comes to *)
#pub datasort ckres =
  | ck_trunc of ()                     (* the bytes end inside it *)
  | ck_big of ()                       (* its length is over the limit *)
  | ck_ok of (bytes, bytes, bytes)     (* tag, data, what follows *)
  | ck_bad of (bytes, bytes, bytes)    (* the checksum is wrong *)

#pub dataprop EQCK(ckres, ckres) =
  | {r:ckres} EQCK_refl(r, r)

(* LENOK(lenb, n): the 4 length bytes say n, under 2 to the 20 *)
#pub dataprop LENOK(bytes, int) =
  | {b0,b1,b2:int | 0 <= b0; b0 < 256; 0 <= b1; b1 < 256; 0 <= b2; b2 < 16}{n:nat}
    LENOK_mk(bcons(b0, bcons(b1, bcons(b2, bcons(0, bnil())))), n)
    of LE(3, n, bcons(b0, bcons(b1, bcons(b2, bnil()))))

(* LENBIG(lenb): the 4 length bytes say 2 to the 20 or more *)
#pub dataprop LENBIG(bytes) =
  | {b0,b1,b2,b3:int | 0 <= b0; b0 < 256; 0 <= b1; b1 < 256; 0 <= b2; b2 < 256; 0 <= b3; b3 < 256; b3 > 0 || b2 >= 16}
    LENBIG_mk(bcons(b0, bcons(b1, bcons(b2, bcons(b3, bnil())))))

(* CRCB(crcb, hi, lo): the 4 bytes of a checksum *)
#pub dataprop CRCB(bytes, int, int) =
  | {c0,c1,c2,c3:int | 0 <= c0; c0 < 256; 0 <= c1; c1 < 256; 0 <= c2; c2 < 256; 0 <= c3; c3 < 256}{hi,lo:nat}
    CRCB_mk(bcons(c0, bcons(c1, bcons(c2, bcons(c3, bnil())))), hi, lo)
    of (LE(2, lo, bcons(c0, bcons(c1, bnil()))), LE(2, hi, bcons(c2, bcons(c3, bnil()))))

(* CKD(tag, data, r, res): the checksum is read from r *)
#pub dataprop CKD(bytes, bytes, bytes, ckres) =
  | {tag,data,r:bytes} CKD_short(tag, data, r, ck_trunc()) of SHORT(4, r)
  | {tag,data,r,crcb,rest:bytes}{hi,lo:nat}
    CKD_ok(tag, data, r, ck_ok(tag, data, rest)) of (TAKE(4, r, crcb, rest), CRCB(crcb, hi, lo), CRCP(tag, data, hi, lo))
  | {tag,data,r,crcb,rest:bytes}{hi,lo,h,l:nat | hi != h || lo != l}
    CKD_bad(tag, data, r, ck_bad(tag, data, rest)) of (TAKE(4, r, crcb, rest), CRCB(crcb, hi, lo), CRCP(tag, data, h, l))

#pub prfun falsep_eqck {a,b:ckres} (FALSEP()): EQCK(a, b)

primplement falsep_eqck {a,b} (f) = case+ f of FALSEP_mk() =/=> ()

#pub prfun ckd_functional {tag,data,r:bytes}{a,b:ckres} (CKD(tag, data, r, a), CKD(tag, data, r, b)): EQCK(a, b)

prfn _ckd_functional {tag,data,r:bytes}{a,b:ckres} (p: CKD(tag, data, r, a), q: CKD(tag, data, r, b)): EQCK(a, b) =
  case+ p of
  | CKD_short(ps) =>
    (case+ q of
     | CKD_short(_) => EQCK_refl()
     | CKD_ok(qt, _, _) => falsep_eqck(take_not_short(qt, ps))
     | CKD_bad(qt, _, _) => falsep_eqck(take_not_short(qt, ps)))
  | CKD_ok(pt, pc, pk) =>
    (case+ q of
     | CKD_short(qs) => falsep_eqck(take_not_short(pt, qs))
     | CKD_ok(qt, qc, qk) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in EQCK_refl() end
     | CKD_bad(qt, qc, qk) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval CRCB_mk(pl, ph) = pc
         prval CRCB_mk(ql, qh) = qc
         prval EQI_refl() = le_number_functional(pl, ql)
         prval EQI_refl() = le_number_functional(ph, qh)
         prval () = crcp_functional(pk, qk)
       in falsep_eqck(contradiction{0}()) end)
  | CKD_bad(pt, pc, pk) =>
    (case+ q of
     | CKD_short(qs) => falsep_eqck(take_not_short(pt, qs))
     | CKD_ok(qt, qc, qk) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval CRCB_mk(pl, ph) = pc
         prval CRCB_mk(ql, qh) = qc
         prval EQI_refl() = le_number_functional(pl, ql)
         prval EQI_refl() = le_number_functional(ph, qh)
         prval () = crcp_functional(pk, qk)
       in falsep_eqck(contradiction{0}()) end
     | CKD_bad(qt, _, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in EQCK_refl() end)

primplement ckd_functional {tag,data,r}{a,b} (p, q) = _ckd_functional(p, q)


(* CKC(n, tag, r, res): the n bytes of data are read from r *)
#pub dataprop CKC(int, bytes, bytes, ckres) =
  | {n:nat}{tag,r:bytes} CKC_short(n, tag, r, ck_trunc()) of SHORT(n, r)
  | {n:nat}{tag,r,data,r3:bytes}{res:ckres} CKC_data(n, tag, r, res) of (TAKE(n, r, data, r3), CKD(tag, data, r3, res))

#pub prfun ckc_functional {n:nat}{tag,r:bytes}{a,b:ckres} (CKC(n, tag, r, a), CKC(n, tag, r, b)): EQCK(a, b)

prfn _ckc_functional {n:nat}{tag,r:bytes}{a,b:ckres} (p: CKC(n, tag, r, a), q: CKC(n, tag, r, b)): EQCK(a, b) =
  case+ p of
  | CKC_short(ps) =>
    (case+ q of
     | CKC_short(_) => EQCK_refl()
     | CKC_data(qt, _) => falsep_eqck(take_not_short(qt, ps)))
  | CKC_data(pt, pk) =>
    (case+ q of
     | CKC_short(qs) => falsep_eqck(take_not_short(pt, qs))
     | CKC_data(qt, qk) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in ckd_functional(pk, qk) end)

primplement ckc_functional {n}{tag,r}{a,b} (p, q) = _ckc_functional(p, q)

(* CKB(n, r, res): the tag is read from r, for a chunk of n bytes of data *)
#pub dataprop CKB(int, bytes, ckres) =
  | {n:nat}{r:bytes} CKB_short(n, r, ck_trunc()) of SHORT(4, r)
  | {n:nat}{r,tag,r2:bytes}{res:ckres} CKB_tag(n, r, res) of (TAKE(4, r, tag, r2), CKC(n, tag, r2, res))

#pub prfun ckb_functional {n:nat}{r:bytes}{a,b:ckres} (CKB(n, r, a), CKB(n, r, b)): EQCK(a, b)

prfn _ckb_functional {n:nat}{r:bytes}{a,b:ckres} (p: CKB(n, r, a), q: CKB(n, r, b)): EQCK(a, b) =
  case+ p of
  | CKB_short(ps) =>
    (case+ q of
     | CKB_short(_) => EQCK_refl()
     | CKB_tag(qt, _) => falsep_eqck(take_not_short(qt, ps)))
  | CKB_tag(pt, pk) =>
    (case+ q of
     | CKB_short(qs) => falsep_eqck(take_not_short(pt, qs))
     | CKB_tag(qt, qk) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in ckc_functional(pk, qk) end)

primplement ckb_functional {n}{r}{a,b} (p, q) = _ckb_functional(p, q)

(* a length is not both small and big *)
#pub prfun lenok_not_big {lenb:bytes}{n:nat} (LENOK(lenb, n), LENBIG(lenb)): FALSEP()

primplement lenok_not_big {lenb}{n} (p, q) =
  case+ p of
  | LENOK_mk(_) => (case+ q of LENBIG_mk() =/=> ())

(* CK(bs, res): the chunk at the start of bs comes to res *)
#pub dataprop CK(bytes, ckres) =
  | {bs:bytes} CK_short(bs, ck_trunc()) of SHORT(4, bs)
  | {bs,lenb,r1:bytes} CK_big(bs, ck_big()) of (TAKE(4, bs, lenb, r1), LENBIG(lenb))
  | {bs,lenb,r1:bytes}{n:nat}{res:ckres} CK_len(bs, res) of (TAKE(4, bs, lenb, r1), LENOK(lenb, n), CKB(n, r1, res))

#pub prfun ck_functional {bs:bytes}{a,b:ckres} (CK(bs, a), CK(bs, b)): EQCK(a, b)

prfn _ck_functional {bs:bytes}{a,b:ckres} (p: CK(bs, a), q: CK(bs, b)): EQCK(a, b) =
  case+ p of
  | CK_short(ps) =>
    (case+ q of
     | CK_short(_) => EQCK_refl()
     | CK_big(qt, _) => falsep_eqck(take_not_short(qt, ps))
     | CK_len(qt, _, _) => falsep_eqck(take_not_short(qt, ps)))
  | CK_big(pt, pl) =>
    (case+ q of
     | CK_short(qs) => falsep_eqck(take_not_short(pt, qs))
     | CK_big(_, _) => EQCK_refl()
     | CK_len(qt, ql, _) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqck(lenok_not_big(ql, pl)) end)
  | CK_len(pt, pl, pk) =>
    (case+ q of
     | CK_short(qs) => falsep_eqck(take_not_short(pt, qs))
     | CK_big(qt, ql) => let
         prval SAME2_refl() = take_functional(pt, qt)
       in falsep_eqck(lenok_not_big(pl, ql)) end
     | CK_len(qt, ql, qk) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval LENOK_mk(pn) = pl
         prval LENOK_mk(qn) = ql
         prval EQI_refl() = le_number_functional(pn, qn)
       in ckb_functional(pk, qk) end)

primplement ck_functional {bs}{a,b} (p, q) = _ck_functional(p, q)


(* the 4 length bytes are 4 long *)
#pub prfun lenok_len {lenb:bytes}{n:nat} (LENOK(lenb, n)): LEN(lenb, 4)

primplement lenok_len {lenb}{n} (p) =
  case+ p of LENOK_mk(_) => LEN_cons(LEN_cons(LEN_cons(LEN_cons(LEN_nil()))))

(* and so are the 4 checksum bytes *)
#pub prfun crcb_len {crcb:bytes}{hi,lo:nat} (CRCB(crcb, hi, lo)): LEN(crcb, 4)

primplement crcb_len {crcb}{hi,lo} (p) =
  case+ p of CRCB_mk(_, _) => LEN_cons(LEN_cons(LEN_cons(LEN_cons(LEN_nil()))))

(* CKENC(tag, data, out): out is the chunk of the tag and the data: the
   length of the data, the tag, the data, their checksum *)
#pub dataprop CKENC(bytes, bytes, bytes) =
  | {n:nat}{tag,data,lenb,crcb,x2,x3,out:bytes}{hi,lo:nat}
    CKENC_mk(tag, data, out)
    of (LEN(tag, 4), LEN(data, n), LENOK(lenb, n), CRCB(crcb, hi, lo), CRCP(tag, data, hi, lo),
        APPEND(data, crcb, x2), APPEND(tag, x2, x3), APPEND(lenb, x3, out))

(* a chunk written, followed by anything, is read back as it was *)
#pub prfun ckenc_ck {tag,data,c,rest,bs:bytes} (CKENC(tag, data, c), APPEND(c, rest, bs))
  : CK(bs, ck_ok(tag, data, rest))

primplement ckenc_ck {tag,data,c,rest,bs} (e, whole) =
  case+ e of
  | CKENC_mk(lt, ld, lo, cb, cp, a1, a2, a3) => let
      prval (a3r, a3b) = append_assoc(a3, whole)
      prval (a2r, a2b) = append_assoc(a2, a3r)
      prval (a1r, a1b) = append_assoc(a1, a2r)
      prval t1 = append_take(a3b, lenok_len(lo))
      prval t2 = append_take(a2b, lt)
      prval t3 = append_take(a1b, ld)
      prval t4 = append_take(a1r, crcb_len(cb))
    in CK_len(t1, lo, CKB_tag(t2, CKC_data(t3, CKD_ok(t4, cb, cp)))) end

(* and a chunk read is a chunk written *)
#pub prfun ck_ckenc {tag,data,rest,bs:bytes} (CK(bs, ck_ok(tag, data, rest)))
  : [c:bytes] (CKENC(tag, data, c), APPEND(c, rest, bs))

primplement ck_ckenc {tag,data,rest,bs} (k) =
  case+ k of
  | CK_len(t1, lo, CKB_tag(t2, CKC_data(t3, CKD_ok(t4, cb, cp)))) => let
      prval (b1, lb) = take_append(t1)
      prval (b2, lt) = take_append(t2)
      prval (b3, ld) = take_append(t3)
      prval (b4, lc) = take_append(t4)
      prval (e1, e2) = append_assoc_rev(b4, b3)
      prval (f1, f2) = append_assoc_rev(e2, b2)
      prval (g1, g2) = append_assoc_rev(f2, b1)
    in (CKENC_mk(lt, ld, lo, cb, cp, e1, f1, g1), g2) end


(* A chunk read, with what it holds *)
#pub datavtype ckread(ckres, int) =
  | {n:nat} CKR_trunc(ck_trunc(), n)
  | {n:nat} CKR_big(ck_big(), n)
  | {n:nat}{tag,data,rest:bytes}{nd,nr:nat | nr < n; nd < 1048576}
    CKR_ok(ck_ok(tag, data, rest), n) of (blist(tag, 4), blist(data, nd), blist(rest, nr))
  | {n:nat}{tag,data,rest:bytes}{nd,nr:nat | nr < n; nd < 1048576}
    CKR_bad(ck_bad(tag, data, rest), n) of (blist(tag, 4), blist(data, nd), blist(rest, nr))

(* The chunk at the start of a list, with the proof of what it comes to *)
#pub fun chunk_read {bs:bytes}{n:nat} (list: blist(bs, n)): [res:ckres] (CK(bs, res) | ckread(res, n))

implement chunk_read {bs}{n} (list) =
  case+ blist_take(4, list) of
  | ~TakeShort(s | ) => (CK_short(s) | CKR_trunc())
  | ~TakeOk(t1 | length_bytes, after_length) =>
    (case+ length_bytes of
     | ~blist_cons(b0, ~blist_cons(b1, ~blist_cons(b2, ~blist_cons(b3, ~blist_nil())))) =>
       if b3 = 0 then
         (if b2 < 16 then let
            val size = b0 + 256 * (b1 + 256 * b2)
            prval ok = LENOK_mk(LE_cons(LE_cons(LE_cons(LE_nil()))))
          in
            case+ blist_take(4, after_length) of
            | ~TakeShort(s | ) => (CK_len(t1, ok, CKB_short(s)) | CKR_trunc())
            | ~TakeOk(t2 | tag, after_tag) =>
              (case+ blist_take(size, after_tag) of
               | ~TakeShort(s | ) => let val () = blist_free(tag) in (CK_len(t1, ok, CKB_tag(t2, CKC_short(s))) | CKR_trunc()) end
               | ~TakeOk(t3 | data, after_data) =>
                 (case+ blist_take(4, after_data) of
                  | ~TakeShort(s | ) => let val () = blist_free(tag) val () = blist_free(data) in (CK_len(t1, ok, CKB_tag(t2, CKC_data(t3, CKD_short(s)))) | CKR_trunc()) end
                  | ~TakeOk(t4 | crc_bytes, rest) =>
                    (case+ crc_bytes of
                     | ~blist_cons(c0, ~blist_cons(c1, ~blist_cons(c2, ~blist_cons(c3, ~blist_nil())))) => let
                      prval (_, tag_len) = take_append(t2)
                      prval (_, data_len) = take_append(t3)
                      val (first | h0, l0) = crcfrom(65535, 65535, tag)
                      val (second | h1, l1) = crcfrom(h0, l0, data)
                      prval crc = CRCP_mk(tag_len, data_len, first, second)
                      val stored_lo = c0 + 256 * c1
                      val stored_hi = c2 + 256 * c3
                      prval stored = CRCB_mk(LE_cons(LE_cons(LE_nil())), LE_cons(LE_cons(LE_nil())))
                    in
                      if stored_hi = 65535 - h1 then
                        (if stored_lo = 65535 - l1 then
                           (CK_len(t1, ok, CKB_tag(t2, CKC_data(t3, CKD_ok(t4, stored, crc)))) | CKR_ok(tag, data, rest))
                         else
                           (CK_len(t1, ok, CKB_tag(t2, CKC_data(t3, CKD_bad(t4, stored, crc)))) | CKR_bad(tag, data, rest)))
                      else
                        (CK_len(t1, ok, CKB_tag(t2, CKC_data(t3, CKD_bad(t4, stored, crc)))) | CKR_bad(tag, data, rest))
                    end)))
          end
          else let
            val () = blist_free(after_length)
          in (CK_big(t1, LENBIG_mk()) | CKR_big()) end)
       else let
         val () = blist_free(after_length)
       in (CK_big(t1, LENBIG_mk()) | CKR_big()) end)


(* The chunk of a tag and some data, with the proof that it is the one *)
#pub fun chunk_write {tag,data:bytes}{nd:nat | nd < 1048576} (tag: !blist(tag, 4), data: !blist(data, nd))
  : [out:bytes] (CKENC(tag, data, out) | blist(out, nd + 12))

implement chunk_write {tag,data}{nd} (tag, data) = let
  val (tag_len | _) = blist_len(tag)
  val (data_len | size) = blist_len(data)
  val q0 = size / 256
  val b0 = size - 256 * q0
  val q1 = q0 / 256
  val b1 = q0 - 256 * q1
  val b2 = q1
  val length_bytes = blist_cons(b0, blist_cons(b1, blist_cons(b2, blist_cons(0, blist_nil()))))
  prval ok = LENOK_mk(LE_cons(LE_cons(LE_cons(LE_nil()))))
  val (first | h0, l0) = crcfrom(65535, 65535, tag)
  val (second | h1, l1) = crcfrom(h0, l0, data)
  prval crc = CRCP_mk(tag_len, data_len, first, second)
  val hi = 65535 - h1
  val lo = 65535 - l1
  val r0 = lo / 256
  val c0 = lo - 256 * r0
  val r1 = hi / 256
  val c2 = hi - 256 * r1
  val crc_bytes = blist_cons(c0, blist_cons(r0, blist_cons(c2, blist_cons(r1, blist_nil()))))
  prval stored = CRCB_mk(LE_cons(LE_cons(LE_nil())), LE_cons(LE_cons(LE_nil())))
  val (a1 | after_data) = blist_append(blist_copy(data), crc_bytes)
  val (a2 | after_tag) = blist_append(blist_copy(tag), after_data)
  val (a3 | out) = blist_append(length_bytes, after_tag)
in (CKENC_mk(tag_len, data_len, ok, stored, crc, a1, a2, a3) | out) end


(* a chunk read, whole or with a wrong checksum, takes at least 12 bytes
   off the front *)
#pub prfun ck_ok_consumes {tag,data,rest,bs:bytes} (CK(bs, ck_ok(tag, data, rest)))
  : [c:bytes][k:nat | k >= 12] (APPEND(c, rest, bs), LEN(c, k))

primplement ck_ok_consumes {tag,data,rest,bs} (kk) = let
  prval (e, whole) = ck_ckenc(kk)
in
  case+ e of
  | CKENC_mk(lt, ld, lo, cb, _, a1, a2, a3) => let
      prval l1 = append_len(a1, ld, crcb_len(cb))
      prval l2 = append_len(a2, lt, l1)
      prval l3 = append_len(a3, lenok_len(lo), l2)
    in (whole, l3) end
end

#pub prfun ck_bad_consumes {tag,data,rest,bs:bytes} (CK(bs, ck_bad(tag, data, rest)))
  : [c:bytes][k:nat | k >= 12] (APPEND(c, rest, bs), LEN(c, k))

primplement ck_bad_consumes {tag,data,rest,bs} (kk) =
  case+ kk of
  | CK_len(t1, lo, CKB_tag(t2, CKC_data(t3, CKD_bad(t4, cb, _)))) => let
      prval (b1, lb) = take_append(t1)
      prval (b2, lt) = take_append(t2)
      prval (b3, ld) = take_append(t3)
      prval (b4, lc) = take_append(t4)
      prval (e1, e2) = append_assoc_rev(b4, b3)
      prval (f1, f2) = append_assoc_rev(e2, b2)
      prval (g1, g2) = append_assoc_rev(f2, b1)
      prval l1 = append_len(e1, ld, lc)
      prval l2 = append_len(f1, lt, l1)
      prval l3 = append_len(g1, lb, l2)
    in (g2, l3) end


(* a chunk written is at least 12 bytes long *)
#pub prfun ckenc_len {tag,data,c:bytes} (CKENC(tag, data, c)): [k:nat | k >= 12] LEN(c, k)

primplement ckenc_len {tag,data,c} (e) =
  case+ e of
  | CKENC_mk(lt, ld, lo, cb, _, a1, a2, a3) => let
      prval l1 = append_len(a1, ld, crcb_len(cb))
      prval l2 = append_len(a2, lt, l1)
    in append_len(a3, lenok_len(lo), l2) end

end
