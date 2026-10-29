#include "share/atspre_staload.hats"
(* zip src/lib.bats:2867 window_nth_back (the streaming sink's constructor), by hand (a datavtype constructor has no copy here): written <= 2147483647
   and fill <= 65536. Change: a written one under the bound plus 2 stays within it, false at written 2147483646 *)
prfn step {written,fill:nat | fill <= 65536; written <= 2147483647; written < 2147483647} ()
  : [written + 2 <= 2147483647] void = ()
