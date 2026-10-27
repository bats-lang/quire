#include "share/atspre_staload.hats"
(* sha256 src/lib.bats:2004 sqrt_fraction32_gt, by hand (a stadef has no lemma to copy; the guard of a constructor is this call): H0 of SHA-256 is 0x6a09e667 (high 27145, low 58983). The stadef is copied unchanged and its arguments are literals, so the solver computes it exactly. Control: the word itself, accepted *)
stadef sqrt_fraction32_gt (i:int, high:int, low:int, p:int) =
  p * 18446744073709551616 < (i*4294967296 + 65536*high + low + 1) * (i*4294967296 + 65536*high + low + 1)
extern prfun guard {high,low:nat | sqrt_fraction32_gt(1, high, low, 2)} (): void
prfn claim (): void = guard{27145,58983}()
