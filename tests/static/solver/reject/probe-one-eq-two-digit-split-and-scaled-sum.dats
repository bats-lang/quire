#include "share/atspre_staload.hats"
prfn p {h,q,r:int | 0 <= h; h < 65536; 256*q <= h; h < 256*q + 256; r + q == 256*h} (): [1 == 2] void = ()
