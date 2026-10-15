#include "share/atspre_staload.hats"
prfn p {b:nat | b < 100}{u:int | u == 2*b}{x0:int | x0 == (u mod 2) / 10}{v:int | v == 4096*b}{x1:int | x1 == (v mod 256) / 256} (): [1 == 2] void = ()
