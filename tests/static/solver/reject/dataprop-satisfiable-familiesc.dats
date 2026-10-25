#include "share/atspre_staload.hats"
(* css:src/harmony.bats FAMILIES, copied: see gen_guards.py.
   Probe: every guard of FAMILIESc holds of some values, so `[1 == 2] void` under them is false and rejected *)
dataprop FAMILIES(int, int, int, int, int, int) =
  | {l1,h1,l2,h2,l3,h3:int | l1 <= h1; h1 - l1 <= 30; l2 <= h2; h2 - l2 <= 30; l3 <= h3; h3 - l3 <= 30}
    FAMILIESc(l1, h1, l2, h2, l3, h3)

prfn satisfiable_familiesc {l1,h1,l2,h2,l3,h3:int | l1 <= h1; h1 - l1 <= 30; l2 <= h2; h2 - l2 <= 30; l3 <= h3; h3 - l3 <= 30} (): [1 == 2] void = ()
