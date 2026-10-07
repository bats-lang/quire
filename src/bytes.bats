(* bytes -- the static model of a byte string, and the lists that carry
   one at run time *)

#target wasm begin

#include "share/atspre_staload.hats"

#pub datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

(* APPEND(a, b, c): c is a followed by b *)
#pub dataprop APPEND(bytes, bytes, bytes) =
  | {b:bytes} APPEND_nil(bnil(), b, b)
  | {x:int}{a,b,c:bytes} APPEND_cons(bcons(x, a), b, bcons(x, c)) of APPEND(a, b, c)

(* LEN(bs, n): bs has n bytes *)
#pub dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {x:int}{bs:bytes}{n:nat} LEN_cons(bcons(x, bs), n + 1) of LEN(bs, n)

(* Two values are one: equality of byte strings and of numbers is a
   proposition, since the solver reasons only about numbers *)
#pub dataprop EQB(bytes, bytes) =
  | {b:bytes} EQB_refl(b, b)

#pub dataprop EQI(int, int) =
  | {i:int} EQI_refl(i, i)

#pub prfun append_functional {a,b,c1,c2:bytes} (APPEND(a, b, c1), APPEND(a, b, c2)): EQB(c1, c2)

primplement append_functional {a,b,c1,c2} (p1, p2) =
  case+ p1 of
  | APPEND_nil() => (case+ p2 of APPEND_nil() => EQB_refl())
  | APPEND_cons(q1) =>
    (case+ p2 of
     | APPEND_cons(q2) =>
       (case+ append_functional(q1, q2) of EQB_refl() => EQB_refl()))

#pub prfun len_functional {bs:bytes}{n,m:nat} (LEN(bs, n), LEN(bs, m)): EQI(n, m)

primplement len_functional {bs}{n,m} (p, q) =
  case+ p of
  | LEN_nil() => (case+ q of LEN_nil() => EQI_refl())
  | LEN_cons(p1) =>
    (case+ q of
     | LEN_cons(q1) =>
       (case+ len_functional(p1, q1) of EQI_refl() => EQI_refl()))

(* a followed by b has the lengths added *)
#pub prfun append_len {a,b,c:bytes}{n,m:nat} (APPEND(a, b, c), LEN(a, n), LEN(b, m)): LEN(c, n + m)

prfun _append_len {a,b,c:bytes}{n,m:nat} .<n>.
  (p: APPEND(a, b, c), la: LEN(a, n), lb: LEN(b, m)): LEN(c, n + m) =
  case+ p of
  | APPEND_nil() => (case+ la of LEN_nil() => lb)
  | APPEND_cons(p1) => (case+ la of LEN_cons(la1) => LEN_cons(_append_len(p1, la1, lb)))

primplement append_len {a,b,c}{n,m} (p, la, lb) = _append_len(p, la, lb)

(* LE(k, n, bs): bs are the k bytes of the number n, least significant
   first. Built a byte at a time: a sum with a big coefficient is not
   safe to state, the solver accepted a wrong one *)
#pub dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {k,m:nat}{b:int | 0 <= b; b < 256}{bs:bytes}
    LE_cons(k+1, b + 256*m, bcons(b, bs)) of LE(k, m, bs)

(* the number determines the bytes *)
#pub prfun le_bytes_functional {k,n:nat}{b1,b2:bytes} (LE(k, n, b1), LE(k, n, b2)): EQB(b1, b2)

prfun _le_bytes {k,n:nat}{b1,b2:bytes} .<k>. (p: LE(k, n, b1), q: LE(k, n, b2)): EQB(b1, b2) =
  case+ p of
  | LE_nil() => (case+ q of LE_nil() => EQB_refl())
  | LE_cons(p1) =>
    (case+ q of
     | LE_cons(q1) =>
       (case+ _le_bytes(p1, q1) of EQB_refl() => EQB_refl()))

primplement le_bytes_functional {k,n}{b1,b2} (p, q) = _le_bytes(p, q)

(* the bytes determine the number *)
#pub prfun le_number_functional {k,n,m:nat}{b:bytes} (LE(k, n, b), LE(k, m, b)): EQI(n, m)

prfun _le_number {k,n,m:nat}{b:bytes} .<k>. (p: LE(k, n, b), q: LE(k, m, b)): EQI(n, m) =
  case+ p of
  | LE_nil() => (case+ q of LE_nil() => EQI_refl())
  | LE_cons(p1) =>
    (case+ q of
     | LE_cons(q1) =>
       (case+ _le_number(p1, q1) of EQI_refl() => EQI_refl()))

primplement le_number_functional {k,n,m}{b} (p, q) = _le_number(p, q)

(* the k bytes are k long *)
#pub prfun le_len {k,n:nat}{bs:bytes} (LE(k, n, bs)): LEN(bs, k)

prfun _le_len {k,n:nat}{bs:bytes} .<k>. (p: LE(k, n, bs)): LEN(bs, k) =
  case+ p of
  | LE_nil() => LEN_nil()
  | LE_cons(p1) => LEN_cons(_le_len(p1))

primplement le_len {k,n}{bs} (p) = _le_len(p)

(* A byte string at run time: a linear list, its bytes and its length
   in its type *)
#pub datavtype blist(bytes, int) =
  | blist_nil(bnil(), 0)
  | {b:int | 0 <= b; b < 256}{bs:bytes}{n:nat} blist_cons(bcons(b, bs), n + 1) of (int b, blist(bs, n))


#pub fun blist_free {bs:bytes}{n:nat} (list: blist(bs, n)): void

implement blist_free {bs}{n} (list) = let
  fun go {bs:bytes}{n:nat} .<n>. (list: blist(bs, n)): void =
    case+ list of
    | ~blist_nil() => ()
    | ~blist_cons(_, rest) => go(rest)
in go(list) end


(* TAKE(n, bs, d, r): the first n bytes of bs are d, and r is the rest *)
#pub dataprop TAKE(int, bytes, bytes, bytes) =
  | {bs:bytes} TAKE_zero(0, bs, bnil(), bs)
  | {n:nat}{b:int}{bs,d,r:bytes} TAKE_succ(n+1, bcons(b, bs), bcons(b, d), r) of TAKE(n, bs, d, r)

(* SHORT(n, bs): bs has fewer than n bytes *)
#pub dataprop SHORT(int, bytes) =
  | {n:pos} SHORT_nil(n, bnil())
  | {n:nat}{b:int}{bs:bytes} SHORT_succ(n+1, bcons(b, bs)) of SHORT(n, bs)

(* Two pairs of byte strings are one pair each *)
#pub dataprop SAME2(bytes, bytes, bytes, bytes) =
  | {a,b:bytes} SAME2_refl(a, b, a, b)

(* taking n bytes is one answer *)
#pub prfun take_functional {n:nat}{bs,d1,r1,d2,r2:bytes} (TAKE(n, bs, d1, r1), TAKE(n, bs, d2, r2)): SAME2(d1, r1, d2, r2)

prfun _take_functional {n:nat}{bs,d1,r1,d2,r2:bytes} .<n>. (p: TAKE(n, bs, d1, r1), q: TAKE(n, bs, d2, r2)): SAME2(d1, r1, d2, r2) =
  case+ p of
  | TAKE_zero() => (case+ q of TAKE_zero() => SAME2_refl())
  | TAKE_succ(p1) =>
    (case+ q of
     | TAKE_succ(q1) => (case+ _take_functional(p1, q1) of SAME2_refl() => SAME2_refl()))

primplement take_functional {n}{bs,d1,r1,d2,r2} (p, q) = _take_functional(p, q)

(* A proof of a contradiction: it has no constructor that can be made *)
#pub dataprop FALSEP() =
  | {n:int | n < 0; n > 0} FALSEP_mk() of ()

(* In a context that is false, there is a proof of it *)
#pub prfun contradiction {k:int | k < 0; k > 0} (): FALSEP()

primplement contradiction {k} () = FALSEP_mk{k}()

(* From a contradiction, equal byte strings and equal numbers *)
#pub prfun falsep_eqb {a,b:bytes} (FALSEP()): EQB(a, b)

primplement falsep_eqb {a,b} (f) = case+ f of FALSEP_mk() =/=> ()

(* bs cannot both have n bytes to take and be short of n *)
#pub prfun take_not_short {n:nat}{bs,d,r:bytes} (TAKE(n, bs, d, r), SHORT(n, bs)): FALSEP()

prfun _take_not_short {n:nat}{bs,d,r:bytes} .<n>. (p: TAKE(n, bs, d, r), q: SHORT(n, bs)): FALSEP() =
  case+ p of
  | TAKE_zero() => (case+ q of SHORT_nil() =/=> ())
  | TAKE_succ(p1) => (case+ q of SHORT_succ(q1) => _take_not_short(p1, q1))

primplement take_not_short {n}{bs,d,r} (p, q) = _take_not_short(p, q)

(* what is taken followed by the rest is the whole, and is n long *)
#pub prfun take_append {n:nat}{bs,d,r:bytes} (TAKE(n, bs, d, r)): (APPEND(d, r, bs), LEN(d, n))

prfun _take_append {n:nat}{bs,d,r:bytes} .<n>. (p: TAKE(n, bs, d, r)): (APPEND(d, r, bs), LEN(d, n)) =
  case+ p of
  | TAKE_zero() => (APPEND_nil(), LEN_nil())
  | TAKE_succ(p1) => let
      prval (a, l) = _take_append(p1)
    in (APPEND_cons(a), LEN_cons(l)) end

primplement take_append {n}{bs,d,r} (p) = _take_append(p)

(* and conversely *)
#pub prfun append_take {n:nat}{a,b,c:bytes} (APPEND(a, b, c), LEN(a, n)): TAKE(n, c, a, b)

prfun _append_take {n:nat}{a,b,c:bytes} .<n>. (p: APPEND(a, b, c), l: LEN(a, n)): TAKE(n, c, a, b) =
  case+ p of
  | APPEND_nil() => (case+ l of LEN_nil() => TAKE_zero())
  | APPEND_cons(p1) => (case+ l of LEN_cons(l1) => TAKE_succ(_append_take(p1, l1)))

primplement append_take {n}{a,b,c} (p, l) = _append_take(p, l)


(* append is associative: (a b) c = a (b c) *)
#pub prfun append_assoc {a,b,ab,c,abc:bytes} (APPEND(a, b, ab), APPEND(ab, c, abc))
  : [bc:bytes] (APPEND(b, c, bc), APPEND(a, bc, abc))

prfun _append_assoc {a,b,ab,c,abc:bytes} .<a>. (p: APPEND(a, b, ab), q: APPEND(ab, c, abc))
  : [bc:bytes] (APPEND(b, c, bc), APPEND(a, bc, abc)) =
  case+ p of
  | APPEND_nil() => (q, APPEND_nil())
  | APPEND_cons(p1) => (case+ q of APPEND_cons(q1) => let
      prval (r, s) = _append_assoc(p1, q1)
    in (r, APPEND_cons(s)) end)

primplement append_assoc {a,b,ab,c,abc} (p, q) = _append_assoc(p, q)

(* A list copied *)
#pub fun blist_copy {bs:bytes}{n:nat} (list: !blist(bs, n)): blist(bs, n)

implement blist_copy {bs}{n} (list) = let
  fun go {bs:bytes}{n:nat} .<n>. (list: !blist(bs, n)): blist(bs, n) =
    case+ list of
    | blist_nil() => blist_nil()
    | blist_cons(b, rest) => blist_cons(b, go(rest))
in go(list) end

(* Two lists joined *)
#pub fun blist_append {a,b:bytes}{n,m:nat} (first: blist(a, n), second: blist(b, m))
  : [c:bytes] (APPEND(a, b, c) | blist(c, n + m))

implement blist_append {a,b}{n,m} (first, second) = let
  fun go {a,b:bytes}{n,m:nat} .<n>. (first: blist(a, n), second: blist(b, m))
    : [c:bytes] (APPEND(a, b, c) | blist(c, n + m)) =
    case+ first of
    | ~blist_nil() => (APPEND_nil() | second)
    | ~blist_cons(x, rest) => let
        val (p | joined) = go(rest, second)
      in (APPEND_cons(p) | blist_cons(x, joined)) end
in go(first, second) end

(* The first k bytes of a list, and the rest *)
#pub datavtype takeres(bytes, int, int) =
  | {bs:bytes}{k,n:nat} TakeShort(bs, k, n) of (SHORT(k, bs) | )
  | {bs:bytes}{k,n:nat}{d,r:bytes}{m:nat | m + k == n} TakeOk(bs, k, n) of (TAKE(k, bs, d, r) | blist(d, k), blist(r, m))

#pub fun blist_take {bs:bytes}{n,k:nat} (k: int k, list: blist(bs, n)): takeres(bs, k, n)

implement blist_take {bs}{n,k} (k, list) = let
  fun go {bs:bytes}{n,k:nat} .<k>. (k: int k, list: blist(bs, n)): takeres(bs, k, n) =
    if k = 0 then TakeOk(TAKE_zero() | blist_nil(), list)
    else
      case+ list of
      | ~blist_nil() => TakeShort(SHORT_nil() | )
      | ~blist_cons(b, rest) =>
        (case+ go(k - 1, rest) of
         | ~TakeShort(s | ) => TakeShort(SHORT_succ(s) | )
         | ~TakeOk(t | d, r) => TakeOk(TAKE_succ(t) | blist_cons(b, d), r))
in go(k, list) end


(* and the other way: a (b c) = (a b) c *)
#pub prfun append_assoc_rev {a,b,c,bc,abc:bytes} (APPEND(b, c, bc), APPEND(a, bc, abc))
  : [ab:bytes] (APPEND(a, b, ab), APPEND(ab, c, abc))

prfun _append_assoc_rev {a,b,c,bc,abc:bytes} .<a>. (p: APPEND(b, c, bc), q: APPEND(a, bc, abc))
  : [ab:bytes] (APPEND(a, b, ab), APPEND(ab, c, abc)) =
  case+ q of
  | APPEND_nil() => (APPEND_nil(), p)
  | APPEND_cons(q1) => let
      prval (r, s) = _append_assoc_rev(p, q1)
    in (APPEND_cons(r), APPEND_cons(s)) end

primplement append_assoc_rev {a,b,c,bc,abc} (p, q) = _append_assoc_rev(p, q)


(* A list's length, with its proof *)
#pub fun blist_len {bs:bytes}{n:nat} (list: !blist(bs, n)): (LEN(bs, n) | int n)

implement blist_len {bs}{n} (list) = let
  fun go {bs:bytes}{n:nat} .<n>. (list: !blist(bs, n)): (LEN(bs, n) | int n) =
    case+ list of
    | blist_nil() => (LEN_nil() | 0)
    | blist_cons(_, rest) => let
        val (p | k) = go(rest)
      in (LEN_cons(p) | k + 1) end
in go(list) end


(* what is left after a known front has a known length *)
#pub prfun append_len_rest {a,b,c:bytes}{k,n:nat} (APPEND(a, b, c), LEN(a, k), LEN(c, n))
  : [m:nat | m + k == n] LEN(b, m)

prfun _append_len_rest {a,b,c:bytes}{k,n:nat} .<k>. (p: APPEND(a, b, c), la: LEN(a, k), lc: LEN(c, n))
  : [m:nat | m + k == n] LEN(b, m) =
  case+ p of
  | APPEND_nil() => (case+ la of LEN_nil() => lc)
  | APPEND_cons(p1) => (case+ la of LEN_cons(la1) => (case+ lc of LEN_cons(lc1) => _append_len_rest(p1, la1, lc1)))

primplement append_len_rest {a,b,c}{k,n} (p, la, lc) = _append_len_rest(p, la, lc)


(* nothing after a byte string leaves it as it is *)
#pub prfun append_nil {bs:bytes}{n:nat} (LEN(bs, n)): APPEND(bs, bnil(), bs)

prfun _append_nil {bs:bytes}{n:nat} .<n>. (l: LEN(bs, n)): APPEND(bs, bnil(), bs) =
  case+ l of
  | LEN_nil() => APPEND_nil()
  | LEN_cons(l1) => APPEND_cons(_append_nil(l1))

primplement append_nil {bs}{n} (l) = _append_nil(l)

(* and what is followed by nothing is itself *)
#pub prfun append_nil_eq {a,c:bytes}{n:nat} (LEN(a, n), APPEND(a, bnil(), c)): EQB(a, c)

prfun _append_nil_eq {a,c:bytes}{n:nat} .<n>. (l: LEN(a, n), p: APPEND(a, bnil(), c)): EQB(a, c) =
  case+ p of
  | APPEND_nil() => EQB_refl()
  | APPEND_cons(p1) => (case+ l of LEN_cons(l1) => (case+ _append_nil_eq(l1, p1) of EQB_refl() => EQB_refl()))

primplement append_nil_eq {a,c}{n} (l, p) = _append_nil_eq(l, p)

end
