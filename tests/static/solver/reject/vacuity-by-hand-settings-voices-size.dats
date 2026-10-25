#include "share/atspre_staload.hats"
(* src/settings.bats:537 _voices_size, by hand (a fun has no copy here): the bound size <= count * (2 + 3 + VOICE_NAME_MAX)
   as the step of its recursion states it. Change: the bound 6 less, false at code_len 3, name_len VOICE_NAME_MAX *)
#define VOICE_NAME_MAX 255
prfn step {count,rest,code_len,name_len:nat | rest <= count * (2 + 3 + VOICE_NAME_MAX); code_len <= 3; name_len <= VOICE_NAME_MAX} ()
  : [2 + code_len + name_len + rest + 6 <= (count + 1) * (2 + 3 + VOICE_NAME_MAX)] void = ()
