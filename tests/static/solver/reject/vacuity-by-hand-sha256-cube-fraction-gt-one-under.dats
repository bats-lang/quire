#include "share/atspre_staload.hats"
(* sha256 src/lib.bats:825 cube_fraction_gt, by hand (a stadef has no lemma to copy; the guard of a constructor is this call): K_0 of SHA-256 is 0x428a2f98 (high 17034, low 12184). The stadef is copied unchanged and its arguments are literals, so the solver computes it exactly. Change: the low half one under, which cube_fraction_gt must refuse *)
stadef cube_fraction_gt (i:int, high:int, low:int, p:int) =
  p * 79228162514264337593543950336
    < (i*4294967296 + 65536*high + low + 1) * (i*4294967296 + 65536*high + low + 1) * (i*4294967296 + 65536*high + low + 1)
extern prfun guard {high,low:nat | cube_fraction_gt(1, high, low, 2)} (): void
prfn claim (): void = guard{17034,12183}()
