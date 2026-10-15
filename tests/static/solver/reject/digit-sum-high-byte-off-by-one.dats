#include "share/atspre_staload.hats"
prfn p {h:nat | h < 65536}{q:int | q == h / 256}{m:int | m == h mod 256}{r:int | r == q + 256*m} (): [r / 256 == m + 1] void = ()
