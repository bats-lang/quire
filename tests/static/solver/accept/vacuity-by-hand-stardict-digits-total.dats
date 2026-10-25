#include "share/atspre_staload.hats"
(* src/stardict.bats:71 _digits, by hand (a fun has no copy here): total <= 2147483647, and a total under 214748364 times 10 plus a digit
   stays within it. Control: the true step *)
prfn step {total:nat | total <= 2147483647; total < 214748364}{digit:nat | digit <= 9} ()
  : [total * 10 + digit <= 2147483647] void = ()
