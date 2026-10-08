(* fields -- the values inside a chunk: numbers of 32 bits and strings
   of up to 255 bytes, one after another *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "bytes.sats"

(* LES(k, n, bs): bs are the k bytes of the number n, least significant
   first, the last byte holding the sign *)
#pub dataprop LES(int, int, bytes) =
  | {b:int | 0 <= b; b < 128} LES_last(1, b, bcons(b, bnil()))
  | {b:int | 128 <= b; b < 256} LES_last_neg(1, b - 256, bcons(b, bnil()))
  | {k:pos}{m:int}{b:int | 0 <= b; b < 256}{bs:bytes}
    LES_cons(k+1, b + 256*m, bcons(b, bs)) of LES(k, m, bs)

#pub prfun les_bytes_functional {k:pos}{n:int}{b1,b2:bytes} (LES(k, n, b1), LES(k, n, b2)): EQB(b1, b2)

prfun _les_bytes {k:pos}{n:int}{b1,b2:bytes} .<k>. (p: LES(k, n, b1), q: LES(k, n, b2)): EQB(b1, b2) =
  case+ p of
  | LES_last() => (case+ q of LES_last() => EQB_refl())
  | LES_last_neg() => (case+ q of LES_last_neg() => EQB_refl())
  | LES_cons(p1) =>
    (case+ q of
     | LES_cons(q1) =>
       (case+ _les_bytes(p1, q1) of EQB_refl() => EQB_refl()))

primplement les_bytes_functional {k}{n}{b1,b2} (p, q) = _les_bytes(p, q)

#pub prfun les_number_functional {k:pos}{n,m:int}{b:bytes} (LES(k, n, b), LES(k, m, b)): EQI(n, m)

prfun _les_number {k:pos}{n,m:int}{b:bytes} .<k>. (p: LES(k, n, b), q: LES(k, m, b)): EQI(n, m) =
  case+ p of
  | LES_last() => (case+ q of LES_last() => EQI_refl())
  | LES_last_neg() => (case+ q of LES_last_neg() => EQI_refl())
  | LES_cons(p1) =>
    (case+ q of
     | LES_cons(q1) =>
       (case+ _les_number(p1, q1) of EQI_refl() => EQI_refl()))

primplement les_number_functional {k}{n,m}{b} (p, q) = _les_number(p, q)


(* the fields of a group: their kinds, and their values *)
#pub datasort layout =
  | lo_nil of ()
  | lo_i32 of (layout)
  | lo_str of (layout)

#pub datasort fvals =
  | fv_nil of ()
  | fv_i32 of (int, fvals)
  | fv_str of (bytes, fvals)

(* STRB(s, sb): sb is s with its length in front, under 256 *)
#pub dataprop STRB(bytes, bytes) =
  | {len:int | 0 <= len; len < 256}{s:bytes} STRB_mk(s, bcons(len, s)) of LEN(s, len)

(* FENC(l, v, bs): bs holds the values v, of kinds l, one after another *)
#pub dataprop FENC(layout, fvals, bytes) =
  | FENC_nil(lo_nil(), fv_nil(), bnil())
  | {n:int}{l:layout}{v:fvals}{b4,rest,out:bytes}
    FENC_i32(lo_i32(l), fv_i32(n, v), out) of (LES(4, n, b4), FENC(l, v, rest), APPEND(b4, rest, out))
  | {s:bytes}{l:layout}{v:fvals}{sb,rest,out:bytes}
    FENC_str(lo_str(l), fv_str(s, v), out) of (STRB(s, sb), FENC(l, v, rest), APPEND(sb, rest, out))

(* what reading values comes to *)
#pub datasort fdres =
  | fd_ok of (fvals)
  | fd_bad of ()

#pub dataprop EQFD(fdres, fdres) =
  | {r:fdres} EQFD_refl(r, r)

(* FDEC(l, bs, res): reading values of kinds l from bs comes to res *)
#pub dataprop FDEC(layout, bytes, fdres) =
  | FDEC_nil(lo_nil(), bnil(), fd_ok(fv_nil()))
  | {x:int | 0 <= x; x < 256}{r:bytes} FDEC_nil_extra(lo_nil(), bcons(x, r), fd_bad())
  | {l:layout}{bs:bytes} FDEC_i32_short(lo_i32(l), bs, fd_bad()) of SHORT(4, bs)
  | {n:int}{l:layout}{v:fvals}{bs,b4,rest:bytes}
    FDEC_i32_ok(lo_i32(l), bs, fd_ok(fv_i32(n, v))) of (TAKE(4, bs, b4, rest), LES(4, n, b4), FDEC(l, rest, fd_ok(v)))
  | {n:int}{l:layout}{bs,b4,rest:bytes}
    FDEC_i32_bad(lo_i32(l), bs, fd_bad()) of (TAKE(4, bs, b4, rest), LES(4, n, b4), FDEC(l, rest, fd_bad()))
  | {l:layout} FDEC_str_empty(lo_str(l), bnil(), fd_bad())
  | {l:layout}{len:int | 0 <= len; len < 256}{r:bytes}
    FDEC_str_short(lo_str(l), bcons(len, r), fd_bad()) of SHORT(len, r)
  | {l:layout}{len:int | 0 <= len; len < 256}{r,s,rest:bytes}{v:fvals}
    FDEC_str_ok(lo_str(l), bcons(len, r), fd_ok(fv_str(s, v))) of (TAKE(len, r, s, rest), FDEC(l, rest, fd_ok(v)))
  | {l:layout}{len:int | 0 <= len; len < 256}{r,s,rest:bytes}
    FDEC_str_bad(lo_str(l), bcons(len, r), fd_bad()) of (TAKE(len, r, s, rest), FDEC(l, rest, fd_bad()))


(* what is left after taking k bytes has a known length *)
#pub prfun take_rest_len {k:nat}{bs,d,r:bytes}{n:nat} (TAKE(k, bs, d, r), LEN(bs, n)): [m:nat | m + k == n] LEN(r, m)

primplement take_rest_len {k}{bs,d,r}{n} (t, whole) = let
  prval (app, front) = take_append(t)
in append_len_rest(app, front, whole) end

#pub prfun falsep_eqfd {a,b:fdres} (FALSEP()): EQFD(a, b)

primplement falsep_eqfd {a,b} (f) = case+ f of FALSEP_mk() =/=> ()

#pub prfun fdec_functional {l:layout}{bs:bytes}{n:nat}{a,b:fdres} (LEN(bs, n), FDEC(l, bs, a), FDEC(l, bs, b)): EQFD(a, b)

prfun _fdec_functional {l:layout}{bs:bytes}{n:nat}{a,b:fdres} .<n>.
  (whole: LEN(bs, n), p: FDEC(l, bs, a), q: FDEC(l, bs, b)): EQFD(a, b) =
  case+ p of
  | FDEC_nil() => (case+ q of FDEC_nil() => EQFD_refl())
  | FDEC_nil_extra() => (case+ q of FDEC_nil_extra() => EQFD_refl())
  | FDEC_i32_short(ps) =>
    (case+ q of
     | FDEC_i32_short(_) => EQFD_refl()
     | FDEC_i32_ok(qt, _, _) => falsep_eqfd(take_not_short(qt, ps))
     | FDEC_i32_bad(qt, _, _) => falsep_eqfd(take_not_short(qt, ps)))
  | FDEC_i32_ok(pt, pn, pr) =>
    (case+ q of
     | FDEC_i32_short(qs) => falsep_eqfd(take_not_short(pt, qs))
     | FDEC_i32_ok(qt, qn, qr) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval EQI_refl() = les_number_functional(pn, qn)
         prval rest_len = take_rest_len(pt, whole)
       in (case+ _fdec_functional(rest_len, pr, qr) of EQFD_refl() => EQFD_refl()) end
     | FDEC_i32_bad(qt, qn, qr) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval rest_len = take_rest_len(pt, whole)
       in (case+ _fdec_functional(rest_len, pr, qr) of EQFD_refl() =/=> ()) end)
  | FDEC_i32_bad(pt, pn, pr) =>
    (case+ q of
     | FDEC_i32_short(qs) => falsep_eqfd(take_not_short(pt, qs))
     | FDEC_i32_ok(qt, qn, qr) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval rest_len = take_rest_len(pt, whole)
       in (case+ _fdec_functional(rest_len, pr, qr) of EQFD_refl() =/=> ()) end
     | FDEC_i32_bad(qt, qn, qr) => EQFD_refl())
  | FDEC_str_empty() => (case+ q of FDEC_str_empty() => EQFD_refl())
  | FDEC_str_short(ps) =>
    (case+ q of
     | FDEC_str_short(_) => EQFD_refl()
     | FDEC_str_ok(qt, _) => falsep_eqfd(take_not_short(qt, ps))
     | FDEC_str_bad(qt, _) => falsep_eqfd(take_not_short(qt, ps)))
  | FDEC_str_ok(pt, pr) =>
    (case+ q of
     | FDEC_str_short(qs) => falsep_eqfd(take_not_short(pt, qs))
     | FDEC_str_ok(qt, qr) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(pt, tail_len)
       in (case+ _fdec_functional(rest_len, pr, qr) of EQFD_refl() => EQFD_refl()) end
     | FDEC_str_bad(qt, qr) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(pt, tail_len)
       in (case+ _fdec_functional(rest_len, pr, qr) of EQFD_refl() =/=> ()) end)
  | FDEC_str_bad(pt, pr) =>
    (case+ q of
     | FDEC_str_short(qs) => falsep_eqfd(take_not_short(pt, qs))
     | FDEC_str_ok(qt, qr) => let
         prval SAME2_refl() = take_functional(pt, qt)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(pt, tail_len)
       in (case+ _fdec_functional(rest_len, pr, qr) of EQFD_refl() =/=> ()) end
     | FDEC_str_bad(qt, qr) => EQFD_refl())

primplement fdec_functional {l}{bs}{n}{a,b} (whole, p, q) = _fdec_functional(whole, p, q)


#pub prfun les_len {k:pos}{n:int}{bs:bytes} (LES(k, n, bs)): LEN(bs, k)

prfun _les_len {k:pos}{n:int}{bs:bytes} .<k>. (p: LES(k, n, bs)): LEN(bs, k) =
  case+ p of
  | LES_last() => LEN_cons(LEN_nil())
  | LES_last_neg() => LEN_cons(LEN_nil())
  | LES_cons(p1) => LEN_cons(_les_len(p1))

primplement les_len {k}{n}{bs} (p) = _les_len(p)

(* values written are read back as they were *)
#pub prfun fenc_fdec {l:layout}{v:fvals}{bs:bytes}{n:nat} (LEN(bs, n), FENC(l, v, bs)): FDEC(l, bs, fd_ok(v))

prfun _fenc_fdec {l:layout}{v:fvals}{bs:bytes}{n:nat} .<n>. (whole: LEN(bs, n), p: FENC(l, v, bs)): FDEC(l, bs, fd_ok(v)) =
  case+ p of
  | FENC_nil() => FDEC_nil()
  | FENC_i32(les, fe, app) => let
      prval t = append_take(app, les_len(les))
      prval rest_len = take_rest_len(t, whole)
    in FDEC_i32_ok(t, les, _fenc_fdec(rest_len, fe)) end
  | FENC_str(STRB_mk(ls), fe, app) =>
    (case+ app of
     | APPEND_cons(inner) => let
         prval t = append_take(inner, ls)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(t, tail_len)
       in FDEC_str_ok(t, _fenc_fdec(rest_len, fe)) end)

primplement fenc_fdec {l}{v}{bs}{n} (whole, p) = _fenc_fdec(whole, p)

(* and values read were written *)
#pub prfun fdec_fenc {l:layout}{v:fvals}{bs:bytes}{n:nat} (LEN(bs, n), FDEC(l, bs, fd_ok(v))): FENC(l, v, bs)

prfun _fdec_fenc {l:layout}{v:fvals}{bs:bytes}{n:nat} .<n>. (whole: LEN(bs, n), p: FDEC(l, bs, fd_ok(v))): FENC(l, v, bs) =
  case+ p of
  | FDEC_nil() => FENC_nil()
  | FDEC_i32_ok(t, les, sub) => let
      prval (app, _) = take_append(t)
      prval rest_len = take_rest_len(t, whole)
    in FENC_i32(les, _fdec_fenc(rest_len, sub), app) end
  | FDEC_str_ok(t, sub) => let
      prval (app, ls) = take_append(t)
      prval LEN_cons(tail_len) = whole
      prval rest_len = take_rest_len(t, tail_len)
    in FENC_str(STRB_mk(ls), _fdec_fenc(rest_len, sub), APPEND_cons(app)) end

primplement fdec_fenc {l}{v}{bs}{n} (whole, p) = _fdec_fenc(whole, p)


(* A 32-bit number at run time, with its four bytes, least significant
   first, and the proof that they are its. The number comes from an int
   that is one (a machine's int has 32 bits); that the int is the number
   the bytes make is the one thing the types do not prove here: it is
   checked by running every int (tests/int32) *)
#pub datavtype int32v(int) =
  | {n:int}{bs:bytes} I32V(n) of (LES(4, n, bs) | int n, blist(bs, 4))

(* n taken apart by 256: n = 256 q + r *)
fn _split {n:int} (n: int n): [q,r:int | n == 256*q + r; 0 <= r; r < 256] (int q, int r) = let
  val c = n / 256
  val r = n - 256 * c
in
  if r >= 0 then (c, r) else (c - 1, r + 256)
end

(* A number made of an int: that same number, or, when it is not one of 32 bits, none *)
#pub datavtype int32_made(int) =
  | {x:int} I32_made(x) of int32v(x)
  | {x:int} I32_unrepresentable(x) of ()

#pub fun int32_make {x:int} (x: int x): int32_made(x)

implement int32_make {x} (x) = let
  val (q0, b0) = _split(x)
  val (q1, b1) = _split(q0)
  val (q2, b2) = _split(q1)
  val (q3, b3) = _split(q2)
in
  if q3 = 0 then
    (if b3 < 128 then
       I32_made(I32V(LES_cons(LES_cons(LES_cons(LES_last()))) | x, blist_cons(b0, blist_cons(b1, blist_cons(b2, blist_cons(b3, blist_nil()))))))
     else I32_unrepresentable())
  else if q3 = ~1 then
    (if b3 >= 128 then
       I32_made(I32V(LES_cons(LES_cons(LES_cons(LES_last_neg()))) | x, blist_cons(b0, blist_cons(b1, blist_cons(b2, blist_cons(b3, blist_nil()))))))
     else I32_unrepresentable())
  else I32_unrepresentable()
end

(* The number made of four bytes read, with the proof *)
#pub fun int32_of_bytes {bs:bytes} (four: blist(bs, 4)): [n:int] (LES(4, n, bs) | int32v(n))

implement int32_of_bytes {bs} (four) =
  case+ four of
  | ~blist_cons(b0, ~blist_cons(b1, ~blist_cons(b2, ~blist_cons(b3, ~blist_nil())))) =>
    if b3 < 128 then let
      prval number = LES_cons(LES_cons(LES_cons(LES_last())))
    in (number | I32V(number | b0 + 256 * (b1 + 256 * (b2 + 256 * b3)), blist_cons(b0, blist_cons(b1, blist_cons(b2, blist_cons(b3, blist_nil())))))) end
    else let
      prval number = LES_cons(LES_cons(LES_cons(LES_last_neg())))
    in (number | I32V(number | b0 + 256 * (b1 + 256 * (b2 + 256 * (b3 - 256))), blist_cons(b0, blist_cons(b1, blist_cons(b2, blist_cons(b3, blist_nil())))))) end

#pub fun int32_zero (): int32v(0)

implement int32_zero () =
  I32V(LES_cons(LES_cons(LES_cons(LES_last()))) | 0, blist_cons(0, blist_cons(0, blist_cons(0, blist_cons(0, blist_nil())))))

#pub fun int32_value {n:int} (number: !int32v(n)): int n

implement int32_value {n} (number) =
  case+ number of I32V(_ | value, _) => value

#pub fun int32_bytes {n:int} (number: !int32v(n)): [bs:bytes] (LES(4, n, bs) | blist(bs, 4))

implement int32_bytes {n} (number) =
  case+ number of I32V(proof | _, four) => (proof | blist_copy(four))

#pub fun int32_copy {n:int} (number: !int32v(n)): int32v(n)

implement int32_copy {n} (number) =
  case+ number of I32V(proof | value, four) => I32V(proof | value, blist_copy(four))

#pub fun int32_free {n:int} (number: int32v(n)): void

implement int32_free {n} (number) =
  case+ number of ~I32V(_ | _, four) => blist_free(four)

(* The kinds of the fields, at run time, k of them *)
#pub datavtype layoutv(layout, int) =
  | LYV_nil(lo_nil(), 0)
  | {l:layout}{k:nat} LYV_i32(lo_i32(l), k+1) of layoutv(l, k)
  | {l:layout}{k:nat} LYV_str(lo_str(l), k+1) of layoutv(l, k)

(* Values, at run time *)
#pub datavtype fvalsv(layout, fvals, int) =
  | FVV_nil(lo_nil(), fv_nil(), 0)
  | {n:int}{l:layout}{v:fvals}{k:nat}
    FVV_i32(lo_i32(l), fv_i32(n, v), k+1) of (int32v(n), fvalsv(l, v, k))
  | {len:nat | len < 256}{s:bytes}{l:layout}{v:fvals}{k:nat}
    FVV_str(lo_str(l), fv_str(s, v), k+1) of (blist(s, len), fvalsv(l, v, k))

#pub fun layoutv_free {l:layout}{k:nat} (layout: layoutv(l, k)): void

implement layoutv_free {l}{k} (layout) = let
  fun go {l:layout}{k:nat} .<k>. (layout: layoutv(l, k)): void =
    case+ layout of
    | ~LYV_nil() => ()
    | ~LYV_i32(rest) => go(rest)
    | ~LYV_str(rest) => go(rest)
in go(layout) end

#pub fun layoutv_copy {l:layout}{k:nat} (layout: !layoutv(l, k)): layoutv(l, k)

implement layoutv_copy {l}{k} (layout) = let
  fun go {l:layout}{k:nat} .<k>. (layout: !layoutv(l, k)): layoutv(l, k) =
    case+ layout of
    | LYV_nil() => LYV_nil()
    | LYV_i32(rest) => LYV_i32(go(rest))
    | LYV_str(rest) => LYV_str(go(rest))
in go(layout) end

#pub fun fvalsv_free {l:layout}{v:fvals}{k:nat} (vals: fvalsv(l, v, k)): void

implement fvalsv_free {l}{v}{k} (vals) = let
  fun go {l:layout}{v:fvals}{k:nat} .<k>. (vals: fvalsv(l, v, k)): void =
    case+ vals of
    | ~FVV_nil() => ()
    | ~FVV_i32(number, rest) => let val () = int32_free(number) in go(rest) end
    | ~FVV_str(s, rest) => let val () = blist_free(s) in go(rest) end
in go(vals) end

#pub fun fvalsv_copy {l:layout}{v:fvals}{k:nat} (vals: !fvalsv(l, v, k)): fvalsv(l, v, k)

implement fvalsv_copy {l}{v}{k} (vals) = let
  fun go {l:layout}{v:fvals}{k:nat} .<k>. (vals: !fvalsv(l, v, k)): fvalsv(l, v, k) =
    case+ vals of
    | FVV_nil() => FVV_nil()
    | FVV_i32(number, rest) => FVV_i32(int32_copy(number), go(rest))
    | FVV_str(s, rest) => FVV_str(blist_copy(s), go(rest))
in go(vals) end

(* The values written, with the proof *)
#pub fun fields_write {l:layout}{v:fvals}{k:nat} (vals: !fvalsv(l, v, k))
  : [out:bytes][m:nat | m <= 260 * k] (FENC(l, v, out) | blist(out, m))

implement fields_write {l}{v}{k} (vals) = let
  fun go {l:layout}{v:fvals}{k:nat} .<k>. (vals: !fvalsv(l, v, k))
    : [out:bytes][m:nat | m <= 260 * k] (FENC(l, v, out) | blist(out, m)) =
    case+ vals of
    | FVV_nil() => (FENC_nil() | blist_nil())
    | FVV_i32(num, rest) => let
        val (number | four) = int32_bytes(num)
        val (restp | restbytes) = go(rest)
        val (app | out) = blist_append(four, restbytes)
      in (FENC_i32(number, restp, app) | out) end
    | FVV_str(s, rest) => let
        val (ls | len) = blist_len(s)
        val (restp | restbytes) = go(rest)
        val (app | out) = blist_append(blist_cons(len, blist_copy(s)), restbytes)
      in (FENC_str(STRB_mk(ls), restp, app) | out) end
in go(vals) end


(* Values read *)
#pub datavtype fdread(fdres, layout, int) =
  | {l:layout}{k:nat} FDR_bad(fd_bad(), l, k)
  | {l:layout}{v:fvals}{k:nat} FDR_ok(fd_ok(v), l, k) of fvalsv(l, v, k)

#pub fun fields_read {l:layout}{k:nat}{bs:bytes}{n:nat} (layout: !layoutv(l, k), list: blist(bs, n))
  : [res:fdres] (FDEC(l, bs, res) | fdread(res, l, k))

implement fields_read {l}{k}{bs}{n} (layout, list) = let
  fun go {l:layout}{k:nat}{bs:bytes}{n:nat} .<k>. (layout: !layoutv(l, k), list: blist(bs, n))
    : [res:fdres] (FDEC(l, bs, res) | fdread(res, l, k)) =
    case+ layout of
    | LYV_nil() =>
      (case+ list of
       | ~blist_nil() => (FDEC_nil() | FDR_ok(FVV_nil()))
       | ~blist_cons(_, rest) => let val () = blist_free(rest) in (FDEC_nil_extra() | FDR_bad()) end)
    | LYV_i32(more) =>
      (case+ blist_take(4, list) of
       | ~TakeShort(s | ) => (FDEC_i32_short(s) | FDR_bad())
       | ~TakeOk(t | four, rest) => let
           val (number | n) = int32_of_bytes(four)
           val (sub | r) = go(more, rest)
         in
           case+ r of
           | ~FDR_ok(vals) => (FDEC_i32_ok(t, number, sub) | FDR_ok(FVV_i32(n, vals)))
           | ~FDR_bad() => let val () = int32_free(n) in (FDEC_i32_bad(t, number, sub) | FDR_bad()) end
         end)
    | LYV_str(more) =>
      (case+ list of
       | ~blist_nil() => (FDEC_str_empty() | FDR_bad())
       | ~blist_cons(len, after_length) =>
         (case+ blist_take(len, after_length) of
          | ~TakeShort(s | ) => (FDEC_str_short(s) | FDR_bad())
          | ~TakeOk(t | text, rest) => let
              val (sub | r) = go(more, rest)
            in
              case+ r of
              | ~FDR_ok(vals) => (FDEC_str_ok(t, sub) | FDR_ok(FVV_str(text, vals)))
              | ~FDR_bad() => let val () = blist_free(text) in (FDEC_str_bad(t, sub) | FDR_bad()) end
            end))
in go(layout, list) end

end
