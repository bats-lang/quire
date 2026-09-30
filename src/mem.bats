(* mem -- handing back a byte array's borrow and freeing the array *)

#include "share/atspre_staload.hats"
#use array as A

(* A frozen byte array's one borrow given back, and the array freed: the
   end of every buffer lent to the bridge for one call *)
#pub fn release_bytes {l:agz}{n:nat}
  (f: $A.frozenx(byte, l, n, 1, null), b: $A.borrow(byte, l, n)): void

implement release_bytes (f, b) = let
  val () = $A.drop<byte>(f, b)
in $A.free<byte>($A.thaw<byte>(f)) end
