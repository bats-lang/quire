(* bytesarr -- byte lists to and from arrays, proved. An array whose cells are
   in its type (array's `barr`) holds a byte list when HOLDS says so; the
   list made of an array and the array made of a list come with that proof,
   by the cells' own lemmas (array's NTH and SETC) and induction on the list. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR

staload "bytes.sats"

(* HOLDS(cells, i, octets, byte_count): the cells of cells from i on begin with the byte_count bytes octets *)
#pub dataprop HOLDS($A.cells, int, bytes, int) =
  | {cells:$A.cells}{i:nat}{n:nat | i <= n} HOLDS_nil(cells, i, bnil(), 0) of $A.CLEN(cells, n)
  | {cells:$A.cells}{i:nat}{byte_value:int}{rest:bytes}{byte_count:nat}
    HOLDS_cons(cells, i, bcons(byte_value, rest), byte_count + 1) of ($A.NTH(cells, i, byte_value), HOLDS(cells, i + 1, rest, byte_count))

(* Setting a cell before the ones a list is held from leaves them held *)
#pub prfun holds_after_set {cells,cells_after:$A.cells}{i,j:nat | i < j}{byte_value:int}{octets:bytes}{byte_count:nat}
  (cells_set: $A.SETC(cells, i, byte_value, cells_after), holds: HOLDS(cells, j, octets, byte_count)): HOLDS(cells_after, j, octets, byte_count)

prfun _holds_after_set {cells,cells_after:$A.cells}{i,j:nat | i < j}{byte_value:int}{octets:bytes}{byte_count:nat} .<byte_count>.
  (cells_set: $A.SETC(cells, i, byte_value, cells_after), holds: HOLDS(cells, j, octets, byte_count)): HOLDS(cells_after, j, octets, byte_count) =
  case+ holds of
  | HOLDS_nil(cells_len) => HOLDS_nil($A.setc_len(cells_set, cells_len))
  | HOLDS_cons(cell, rest) => HOLDS_cons($A.setc_nth_other(cells_set, cell), _holds_after_set(cells_set, rest))

primplement holds_after_set {cells,cells_after}{i,j}{byte_value}{octets}{byte_count} (cells_set, holds) = _holds_after_set(cells_set, holds)

(* The cells hold one list of a length *)
#pub prfun holds_functional {cells:$A.cells}{i:nat}{first,second:bytes}{byte_count:nat}
  (HOLDS(cells, i, first, byte_count), HOLDS(cells, i, second, byte_count)): EQB(first, second)

prfun _holds_functional {cells:$A.cells}{i:nat}{first,second:bytes}{byte_count:nat} .<byte_count>.
  (one: HOLDS(cells, i, first, byte_count), other: HOLDS(cells, i, second, byte_count)): EQB(first, second) =
  case+ one of
  | HOLDS_nil(_) => (case+ other of HOLDS_nil(_) => EQB_refl())
  | HOLDS_cons(cell_one, rest_one) =>
    (case+ other of
     | HOLDS_cons(cell_other, rest_other) => let
         prval () = $A.nth_functional(cell_one, cell_other)
         prval EQB_refl() = _holds_functional(rest_one, rest_other)
       in EQB_refl() end)

primplement holds_functional {cells}{i}{first,second}{byte_count} (one, other) = _holds_functional(one, other)

(* A list as another it is equal to *)
#pub fun blist_recast {first,second:bytes}{n:nat} (same: EQB(first, second) | list: blist(first, n)): blist(second, n)

implement blist_recast {first,second}{n} (same | list) = let
  prval EQB_refl() = same
in list end

(* The first count bytes of an array, as a list, with the proof that the cells hold it *)
#pub fun blist_of_barr {l:agz}{n:pos}{cells:$A.cells}{count:nat | count <= n}
  (cells_len: $A.CLEN(cells, n) | array: !$A.barr(l, n, cells), count: int count)
  : [octets:bytes] (HOLDS(cells, 0, octets, count) | blist(octets, count))

implement blist_of_barr {l}{n}{cells}{count} (cells_len | array, count) = let
  fun list_from {i:nat | i <= count} .<count - i>.
    (cells_len: $A.CLEN(cells, n) | array: !$A.barr(l, n, cells), i: int i)
    : [octets:bytes] (HOLDS(cells, i, octets, count - i) | blist(octets, count - i)) =
    if i >= count then (HOLDS_nil(cells_len) | blist_nil())
    else let
      val (cell | value) = $A.barr_get(array, i)
      val (rest_holds | rest) = list_from(cells_len | array, i + 1)
    in (HOLDS_cons(cell, rest_holds) | blist_cons(value, rest)) end
in list_from(cells_len | array, 0) end

(* An array of total cells that begins with the bytes of a list, filled from the end of the list to its
   start: the cells hold the list from where it was put *)
fun barr_fill {l:agz}{total:pos}{octets:bytes}{list_len:nat}{cells:$A.cells}{i:nat | i + list_len <= total} .<list_len>.
  (cells_len: $A.CLEN(cells, total) | list: !blist(octets, list_len), array: $A.barr(l, total, cells), i: int i)
  : [cells_after:$A.cells] (HOLDS(cells_after, i, octets, list_len), $A.CLEN(cells_after, total) | $A.barr(l, total, cells_after)) =
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
#pub fun barr_of_blist {octets:bytes}{n:nat | n < 1048576} (list: !blist(octets, n))
  : [l:agz][cells:$A.cells] (HOLDS(cells, 0, octets, n), $A.CLEN(cells, n + 1) | $A.barr(l, n + 1, cells))

implement barr_of_blist {octets}{n} (list) = let
  val (_ | count) = blist_len(list)
  val (cells_len | array) = $A.barr_alloc(count + 1)
in barr_fill(cells_len | list, array, 0) end

(* The bytes of a list in a plain array exactly as long as the list, to be given to what writes
   them elsewhere (the array's cells held them while it was made: that is proved) *)
#pub fun blist_to_buffer {octets:bytes}{n:pos | n <= 1048576} (list: !blist(octets, n), count: int n): [l:agz] $A.arr(byte, l, n)

implement blist_to_buffer {octets}{n} (list, count) = let
  val (cells_len | array) = $A.barr_alloc(count)
  val (_, _ | filled) = barr_fill(cells_len | list, array, 0)
in $A.barr_to_arr(filled) end

(* The bytes at from, from + 1, ... of an array that something else filled, count of them, as a
   list: the cells are not known, so nothing is proved of the list but that it is a list *)
#pub fun blist_of_array {l:agz}{origin:addr}{size,from,count:nat | from + count <= size}
  (array: !$A.arrx(byte, l, size, origin), from: int from, count: int count): [octets:bytes] blist(octets, count)

implement blist_of_array {l}{origin}{size,from,count} (array, from, count) = let
  fun bytes_from {i:nat | i <= count} .<count - i>. (array: !$A.arrx(byte, l, size, origin), i: int i): [octets:bytes] blist(octets, count - i) =
    if i >= count then blist_nil()
    else let
      val byte_value = $AR.low_byte(byte2int0($A.get<byte>(array, from + i)))
    in blist_cons(byte_value, bytes_from(array, i + 1)) end
in bytes_from(array, 0) end

(* A byte string in an array: the array holds the bytes octets, one cell longer
   than they are *)
#pub datavtype bstr(bytes) =
  | {l:agz}{len:nat | len < 256}{cells:$A.cells}{octets:bytes}
    BStr(octets) of (HOLDS(cells, 0, octets, len), $A.CLEN(cells, len + 1) | $A.barr(l, len + 1, cells), int len)

(* The byte string of a list of under 256 bytes *)
#pub fun bstr_of_blist {octets:bytes}{n:nat | n < 256} (list: !blist(octets, n)): bstr(octets)

implement bstr_of_blist {octets}{n} (list) = let
  val (_ | count) = blist_len(list)
  val (holds, cells_len | array) = barr_of_blist(list)
in BStr(holds, cells_len | array, count) end

(* The list of a byte string: the very bytes it holds *)
#pub fun blist_of_bstr {octets:bytes} (string: !bstr(octets)): [n:nat | n < 256] blist(octets, n)

implement blist_of_bstr {octets} (string) =
  case+ string of
  | BStr(holds, cells_len | array, len) => let
      val (read_holds | read) = blist_of_barr(cells_len | array, len)
      prval same = holds_functional(read_holds, holds)
    in blist_recast(same | read) end

#pub fun bstr_len {octets:bytes} (string: !bstr(octets)): [n:nat | n < 256] int n

implement bstr_len {octets} (string) =
  case+ string of BStr(_, _ | _, len) => len

#pub fun bstr_copy {octets:bytes} (string: !bstr(octets)): bstr(octets)

implement bstr_copy {octets} (string) =
  case+ string of
  | BStr(holds, cells_len | array, len) => let
      val copy = $A.barr_copy(array, len + 1)
    in BStr(holds, cells_len | copy, len) end

#pub fun bstr_free {octets:bytes} (string: bstr(octets)): void

implement bstr_free {octets} (string) =
  case+ string of
  | ~BStr(_, _ | array, _) => $A.barr_free(array)

(* Whether two byte strings are the same bytes, as a run-time answer *)
#pub fun bstr_equal {first,second:bytes} (one: !bstr(first), other: !bstr(second)): bool

fun bstr_equal_go {first_loc,second_loc:agz}{first_size,second_size:pos}{first_cells,second_cells:$A.cells}{len:nat | len <= first_size; len <= second_size}{i:nat | i <= len} .<len - i>.
  (first: !$A.barr(first_loc, first_size, first_cells), second: !$A.barr(second_loc, second_size, second_cells), len: int len, i: int i): bool =
  if i >= len then true
  else let
    val (_ | first_byte) = $A.barr_get(first, i)
    val (_ | second_byte) = $A.barr_get(second, i)
  in if first_byte <> second_byte then false else bstr_equal_go(first, second, len, i + 1) end

implement bstr_equal {first,second} (one, other) =
  case+ one of
  | BStr(_, _ | one_array, one_len) =>
    (case+ other of
     | BStr(_, _ | other_array, other_len) =>
       if one_len <> other_len then false
       else bstr_equal_go(one_array, other_array, one_len, 0))

(* The bytes of a plain array of len + 1 cells, copied: the byte string they are *)
#pub fun bstr_of_array {l:agz}{len:nat | len < 256} (array: !$A.arr(byte, l, len + 1), len: int len): [octets:bytes] bstr(octets)

implement bstr_of_array {l}{len} (array, len) = let
  val copy = $A.alloc<byte>(len + 1)
  fun copy_from {copy_loc:agz}{i:nat | i <= len + 1} .<len + 1 - i>. (source: !$A.arr(byte, l, len + 1), copy: !$A.arr(byte, copy_loc, len + 1), i: int i): void =
    if i >= len + 1 then ()
    else let val () = $A.set<byte>(copy, i, $A.get<byte>(source, i)) in copy_from(source, copy, i + 1) end
  val () = copy_from(array, copy, 0)
  val (cells_len | cells) = $A.barr_of_arr(copy)
  val (holds | read) = blist_of_barr(cells_len | cells, len)
  val () = blist_free(read)
in BStr(holds, cells_len | cells, len) end

(* A byte string as a plain array of len + 1 cells, copied *)
#pub fun array_of_bstr {octets:bytes} (string: !bstr(octets)): [l:agz][len:nat | len < 256] @($A.arr(byte, l, len + 1), int len)

implement array_of_bstr {octets} (string) =
  case+ string of
  | BStr(_, _ | array, len) => let
      val copy = $A.barr_copy(array, len + 1)
    in @($A.barr_to_arr(copy), len) end

end
