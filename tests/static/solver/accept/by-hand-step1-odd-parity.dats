#include "share/atspre_staload.hats"
(* src/crc.bats STEP1_odd, the atom `2*low_half + 1 < 65536`: its left side steps by two, so the bound moved by one
   (`< 65537`) holds of the same integers and is no false variant (gen_guards.py moves this atom by two, SHIFT_BY) *)
prfn same_integers {low_half:nat | 2*low_half + 1 < 65537} (): [2*low_half + 1 < 65536] void = ()
