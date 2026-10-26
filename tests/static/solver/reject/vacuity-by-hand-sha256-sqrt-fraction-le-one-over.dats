#include "share/atspre_staload.hats"
(* sha256 src/lib.bats:1533 sqrt_fraction_le, by hand (a stadef has no lemma to copy; the guard of a constructor is this call): K_0 of SHA-1 is 0x5a827999 (high 23170, low 31129). The stadef is copied unchanged and its arguments are literals, so the solver computes it exactly. Change: the low half one over, which sqrt_fraction_le must refuse *)
stadef sqrt_fraction_le (high:int, low:int, n:int) =
  (65536*high + low) * (65536*high + low) <= n * 1152921504606846976
extern prfun guard {high,low:nat | sqrt_fraction_le(high, low, 2)} (): void
prfn claim (): void = guard{23170,31130}()
