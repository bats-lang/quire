#include "share/atspre_staload.hats"
(* file src/lib.bats:661 content-io CONTENT_READ_ALL, by hand (a trusted import has no copy here): the context of a limit (0 <= limit <= 2147483647) is satisfiable, so `[1 == 2] void` under it is rejected *)
prfn context {limit:nat | limit <= 2147483647} (): [1 == 2] void = ()
