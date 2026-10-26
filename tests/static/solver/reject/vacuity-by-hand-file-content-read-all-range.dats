#include "share/atspre_staload.hats"
(* file src/lib.bats:661 content-io CONTENT_READ_ALL, by hand (a trusted import has no copy here): a limit is within [0, 2147483647], the largest int a limit names. Change: one more than the largest, false at the largest *)
prfn range {limit:nat | limit <= 2147483647} (): [limit + 1 <= 2147483647] void = ()
