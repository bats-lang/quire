(* bytesarr -- byte lists to and from arrays. The one step the types do
   not follow: an array's cells are not in its type, so that the list
   made of an array, or the array made of a list, holds the same bytes is
   tested (tests/codec), not proved *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR

staload "bytes.sats"

(* The bytes at from, from + 1, ... of an array, count of them, as a list *)
#pub fun blist_of_array {l:agz}{o:addr}{size,from,count:nat | from + count <= size}
  (array: !$A.arrx(byte, l, size, o), from: int from, count: int count): [bs:bytes] blist(bs, count)

implement blist_of_array {l}{o}{size,from,count} (array, from, count) = let
  fun go {i:nat | i <= count} .<count - i>. (array: !$A.arrx(byte, l, size, o), i: int i): [bs:bytes] blist(bs, count - i) =
    if i >= count then blist_nil()
    else let
      val byte_value = $AR.low_byte(byte2int0($A.get<byte>(array, from + i)))
    in blist_cons(byte_value, go(array, i + 1)) end
in go(array, 0) end

(* The bytes of a list in an array one longer than the list *)
#pub fun blist_to_array {bs:bytes}{n:nat | n < 256} (list: !blist(bs, n)): [l:agz] $A.arr(byte, l, n + 1)

implement blist_to_array {bs}{n} (list) = let
  val (_ | count) = blist_len(list)
  val array = $A.alloc<byte>(count + 1)
  fun fill {l:agz}{bs:bytes}{k,j:nat | j + k <= n} .<k>.
    (array: !$A.arr(byte, l, n + 1), list: !blist(bs, k), j: int j): void =
    case+ list of
    | blist_nil() => ()
    | blist_cons(b, rest) => let
        val () = $A.set<byte>(array, j, $A.int2byte(b))
      in fill(array, rest, j + 1) end
  val () = fill(array, list, 0)
in array end


(* The bytes of a list in an array exactly as long as the list *)
#pub fun blist_to_buffer {bs:bytes}{n:pos | n <= 1048576} (list: !blist(bs, n), count: int n): [l:agz] $A.arr(byte, l, n)

implement blist_to_buffer {bs}{n} (list, count) = let
  val array = $A.alloc<byte>(count)
  fun fill {l:agz}{bs:bytes}{k,j:nat | j + k <= n} .<k>.
    (array: !$A.arr(byte, l, n), list: !blist(bs, k), j: int j): void =
    case+ list of
    | blist_nil() => ()
    | blist_cons(b, rest) => let
        val () = $A.set<byte>(array, j, $A.int2byte(b))
      in fill(array, rest, j + 1) end
  val () = fill(array, list, 0)
in array end

end
