(* bytesarr -- byte lists to and from arrays, proved. An array whose cells are
   in its type (array's `barr`) holds a byte list when HOLDS says so; the
   list made of an array and the array made of a list come with that proof,
   by the cells' own lemmas (array's NTH and SETC) and induction on the list. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR

staload "bytes.sats"

(* HOLDS(cs, i, bs, m): the cells of cs from i on begin with the m bytes bs *)
#pub dataprop HOLDS($A.cells, int, bytes, int) =
  | {cs:$A.cells}{i:nat}{n:nat | i <= n} HOLDS_nil(cs, i, bnil(), 0) of $A.CLEN(cs, n)
  | {cs:$A.cells}{i:nat}{v:int}{rest:bytes}{m:nat}
    HOLDS_cons(cs, i, bcons(v, rest), m + 1) of ($A.NTH(cs, i, v), HOLDS(cs, i + 1, rest, m))

(* Setting a cell before the ones a list is held from leaves them held *)
#pub prfun holds_after_set {cs,cs2:$A.cells}{i,j:nat | i < j}{v:int}{bs:bytes}{m:nat}
  (cells_set: $A.SETC(cs, i, v, cs2), holds: HOLDS(cs, j, bs, m)): HOLDS(cs2, j, bs, m)

prfun _holds_after_set {cs,cs2:$A.cells}{i,j:nat | i < j}{v:int}{bs:bytes}{m:nat} .<m>.
  (cells_set: $A.SETC(cs, i, v, cs2), holds: HOLDS(cs, j, bs, m)): HOLDS(cs2, j, bs, m) =
  case+ holds of
  | HOLDS_nil(cells_len) => HOLDS_nil($A.setc_len(cells_set, cells_len))
  | HOLDS_cons(cell, rest) => HOLDS_cons($A.setc_nth_other(cells_set, cell), _holds_after_set(cells_set, rest))

primplement holds_after_set {cs,cs2}{i,j}{v}{bs}{m} (cells_set, holds) = _holds_after_set(cells_set, holds)

(* The cells hold one list of a length *)
#pub prfun holds_functional {cs:$A.cells}{i:nat}{first,second:bytes}{m:nat}
  (HOLDS(cs, i, first, m), HOLDS(cs, i, second, m)): EQB(first, second)

prfun _holds_functional {cs:$A.cells}{i:nat}{first,second:bytes}{m:nat} .<m>.
  (one: HOLDS(cs, i, first, m), other: HOLDS(cs, i, second, m)): EQB(first, second) =
  case+ one of
  | HOLDS_nil(_) => (case+ other of HOLDS_nil(_) => EQB_refl())
  | HOLDS_cons(cell_one, rest_one) =>
    (case+ other of
     | HOLDS_cons(cell_other, rest_other) => let
         prval () = $A.nth_functional(cell_one, cell_other)
         prval EQB_refl() = _holds_functional(rest_one, rest_other)
       in EQB_refl() end)

primplement holds_functional {cs}{i}{first,second}{m} (one, other) = _holds_functional(one, other)

(* A list as another it is equal to *)
#pub fun blist_recast {first,second:bytes}{n:nat} (same: EQB(first, second) | list: blist(first, n)): blist(second, n)

implement blist_recast {first,second}{n} (same | list) = let
  prval EQB_refl() = same
in list end

(* The first count bytes of an array, as a list, with the proof that the cells hold it *)
#pub fun blist_of_barr {l:agz}{n:pos}{cs:$A.cells}{count:nat | count <= n}
  (cells_len: $A.CLEN(cs, n) | array: !$A.barr(l, n, cs), count: int count)
  : [bs:bytes] (HOLDS(cs, 0, bs, count) | blist(bs, count))

implement blist_of_barr {l}{n}{cs}{count} (cells_len | array, count) = let
  fun go {i:nat | i <= count} .<count - i>.
    (cells_len: $A.CLEN(cs, n) | array: !$A.barr(l, n, cs), i: int i)
    : [bs:bytes] (HOLDS(cs, i, bs, count - i) | blist(bs, count - i)) =
    if i >= count then (HOLDS_nil(cells_len) | blist_nil())
    else let
      val (cell | value) = $A.barr_get(array, i)
      val (rest_holds | rest) = go(cells_len | array, i + 1)
    in (HOLDS_cons(cell, rest_holds) | blist_cons(value, rest)) end
in go(cells_len | array, 0) end

(* An array of total cells that begins with the bytes of a list, filled from the end of the list to its
   start: the cells hold the list from where it was put *)
fun barr_fill {l:agz}{total:pos}{bs:bytes}{k:nat}{cs:$A.cells}{i:nat | i + k <= total} .<k>.
  (cells_len: $A.CLEN(cs, total) | list: !blist(bs, k), array: $A.barr(l, total, cs), i: int i)
  : [cs2:$A.cells] (HOLDS(cs2, i, bs, k), $A.CLEN(cs2, total) | $A.barr(l, total, cs2)) =
  case+ list of
  | blist_nil() => (HOLDS_nil(cells_len), cells_len | array)
  | blist_cons(value, rest) => let
      val (rest_holds, rest_len | rest_array) = barr_fill(cells_len | rest, array, i + 1)
      val (cells_set | set_array) = $A.barr_set(rest_array, i, value)
      prval set_len = $A.setc_len(cells_set, rest_len)
      prval kept = holds_after_set(cells_set, rest_holds)
      prval here = $A.setc_nth_same(cells_set)
    in (HOLDS_cons(here, kept), set_len | set_array) end

(* An array of the bytes of a list, one cell longer, with the proof that its cells hold them *)
#pub fun barr_of_blist {bs:bytes}{n:nat | n < 1048576} (list: !blist(bs, n))
  : [l:agz][cs:$A.cells] (HOLDS(cs, 0, bs, n), $A.CLEN(cs, n + 1) | $A.barr(l, n + 1, cs))

implement barr_of_blist {bs}{n} (list) = let
  val (_ | count) = blist_len(list)
  val (cells_len | array) = $A.barr_alloc(count + 1)
in barr_fill(cells_len | list, array, 0) end

(* The bytes of a list in a plain array exactly as long as the list, to be given to what writes
   them elsewhere (the array's cells held them while it was made: that is proved) *)
#pub fun blist_to_buffer {bs:bytes}{n:pos | n <= 1048576} (list: !blist(bs, n), count: int n): [l:agz] $A.arr(byte, l, n)

implement blist_to_buffer {bs}{n} (list, count) = let
  val (cells_len | array) = $A.barr_alloc(count)
  val (_, _ | filled) = barr_fill(cells_len | list, array, 0)
in $A.barr_to_arr(filled) end

(* The bytes at from, from + 1, ... of an array that something else filled, count of them, as a
   list: the cells are not known, so nothing is proved of the list but that it is a list *)
#pub fun blist_of_array {l:agz}{o:addr}{size,from,count:nat | from + count <= size}
  (array: !$A.arrx(byte, l, size, o), from: int from, count: int count): [bs:bytes] blist(bs, count)

implement blist_of_array {l}{o}{size,from,count} (array, from, count) = let
  fun go {i:nat | i <= count} .<count - i>. (array: !$A.arrx(byte, l, size, o), i: int i): [bs:bytes] blist(bs, count - i) =
    if i >= count then blist_nil()
    else let
      val byte_value = $AR.low_byte(byte2int0($A.get<byte>(array, from + i)))
    in blist_cons(byte_value, go(array, i + 1)) end
in go(array, 0) end

(* A byte string in an array: the array holds the bytes bs, one cell longer
   than they are *)
#pub datavtype bstr(bytes) =
  | {l:agz}{len:nat | len < 256}{cs:$A.cells}{bs:bytes}
    BStr(bs) of (HOLDS(cs, 0, bs, len), $A.CLEN(cs, len + 1) | $A.barr(l, len + 1, cs), int len)

(* The byte string of a list of under 256 bytes *)
#pub fun bstr_of_blist {bs:bytes}{n:nat | n < 256} (list: !blist(bs, n)): bstr(bs)

implement bstr_of_blist {bs}{n} (list) = let
  val (_ | count) = blist_len(list)
  val (holds, cells_len | array) = barr_of_blist(list)
in BStr(holds, cells_len | array, count) end

(* The list of a byte string: the very bytes it holds *)
#pub fun blist_of_bstr {bs:bytes} (string: !bstr(bs)): [n:nat | n < 256] blist(bs, n)

implement blist_of_bstr {bs} (string) =
  case+ string of
  | BStr(holds, cells_len | array, len) => let
      val (read_holds | read) = blist_of_barr(cells_len | array, len)
      prval same = holds_functional(read_holds, holds)
    in blist_recast(same | read) end

#pub fun bstr_len {bs:bytes} (string: !bstr(bs)): [n:nat | n < 256] int n

implement bstr_len {bs} (string) =
  case+ string of BStr(_, _ | _, len) => len

#pub fun bstr_copy {bs:bytes} (string: !bstr(bs)): bstr(bs)

implement bstr_copy {bs} (string) =
  case+ string of
  | BStr(holds, cells_len | array, len) => let
      val copy = $A.barr_copy(array, len + 1)
    in BStr(holds, cells_len | copy, len) end

#pub fun bstr_free {bs:bytes} (string: bstr(bs)): void

implement bstr_free {bs} (string) =
  case+ string of
  | ~BStr(_, _ | array, _) => $A.barr_free(array)

(* Whether two byte strings are the same bytes, as a run-time answer *)
#pub fun bstr_equal {first,second:bytes} (one: !bstr(first), other: !bstr(second)): bool

fun bstr_equal_go {l1,l2:agz}{n1,n2:pos}{c1,c2:$A.cells}{len:nat | len <= n1; len <= n2}{i:nat | i <= len} .<len - i>.
  (first: !$A.barr(l1, n1, c1), second: !$A.barr(l2, n2, c2), len: int len, i: int i): bool =
  if i >= len then true
  else let
    val (_ | x) = $A.barr_get(first, i)
    val (_ | y) = $A.barr_get(second, i)
  in if x <> y then false else bstr_equal_go(first, second, len, i + 1) end

implement bstr_equal {first,second} (one, other) =
  case+ one of
  | BStr(_, _ | one_array, one_len) =>
    (case+ other of
     | BStr(_, _ | other_array, other_len) =>
       if one_len <> other_len then false
       else bstr_equal_go(one_array, other_array, one_len, 0))

(* The bytes of a plain array of len + 1 cells, copied: the byte string they are *)
#pub fun bstr_of_array {l:agz}{len:nat | len < 256} (array: !$A.arr(byte, l, len + 1), len: int len): [bs:bytes] bstr(bs)

implement bstr_of_array {l}{len} (array, len) = let
  val copy = $A.alloc<byte>(len + 1)
  fun go {m:agz}{i:nat | i <= len + 1} .<len + 1 - i>. (source: !$A.arr(byte, l, len + 1), copy: !$A.arr(byte, m, len + 1), i: int i): void =
    if i >= len + 1 then ()
    else let val () = $A.set<byte>(copy, i, $A.get<byte>(source, i)) in go(source, copy, i + 1) end
  val () = go(array, copy, 0)
  val (cells_len | cells) = $A.barr_of_arr(copy)
  val (holds | read) = blist_of_barr(cells_len | cells, len)
  val () = blist_free(read)
in BStr(holds, cells_len | cells, len) end

(* A byte string as a plain array of len + 1 cells, copied *)
#pub fun array_of_bstr {bs:bytes} (string: !bstr(bs)): [l:agz][len:nat | len < 256] @($A.arr(byte, l, len + 1), int len)

implement array_of_bstr {bs} (string) =
  case+ string of
  | BStr(_, _ | array, len) => let
      val copy = $A.barr_copy(array, len + 1)
    in @($A.barr_to_arr(copy), len) end

end
