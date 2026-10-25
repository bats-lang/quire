#include "share/atspre_staload.hats"
(* quire src/cut.bats CUTC, copied: see gen_guards.py.
   False variant: the guard atom `back <= 65535` of CUTC_break shifted by 1: `back <= (65535) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop WHITE(int) =
  | WHITE_space(32)
  | WHITE_tab(9)
  | WHITE_line_feed(10)

dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

dataprop BREAKBACK(cells, int, int, int, int) =
  | {cs:cells}{offset,floor:int} BREAKBACK_start(cs, offset, 0, floor, ~1)
  | {cs:cells}{offset,at,floor:int | 1 <= at; at <= floor} BREAKBACK_floor(cs, offset, at, floor, ~1)
  | {cs:cells}{offset:nat}{at,floor,code:int | 1 <= at; floor < at}
    BREAKBACK_white(cs, offset, at, floor, at + 1) of (NTH(cs, offset + at, code), WHITE(code))
  | {cs:cells}{offset:nat}{at,floor,code,back:int | 1 <= at; floor < at}
    BREAKBACK_other(cs, offset, at, floor, back) of (NTH(cs, offset + at, code), NOTWHITE(code), BREAKBACK(cs, offset, at - 1, floor, back))

dataprop STARTS(int) =
  | {code:int | code < 128} STARTS_ascii(code)
  | {code:int | 192 <= code} STARTS_lead(code)

dataprop CONTINUES(int) =
  | {code:int | 128 <= code; code < 192} CONTINUES_byte(code)

dataprop CUTC(cells, int, int, int) =
  | {cs:cells}{offset:nat}{text_len,back:int | 65536 <= text_len; 65000 <= back; back <= 65535}
    CUTC_break(cs, offset, text_len, back) of (BREAKBACK(cs, offset, 65534, 65022, back))
  | {cs:cells}{offset:nat}{text_len,back,first:int | 65536 <= text_len; back < 65000}
    CUTC_65535(cs, offset, text_len, 65535)
      of (BREAKBACK(cs, offset, 65534, 65022, back), NTH(cs, offset + 65535, first), STARTS(first))
  | {cs:cells}{offset:nat}{text_len,back,first,second:int | 65536 <= text_len; back < 65000}
    CUTC_65534(cs, offset, text_len, 65534)
      of (BREAKBACK(cs, offset, 65534, 65022, back), NTH(cs, offset + 65535, first), CONTINUES(first),
          NTH(cs, offset + 65534, second), STARTS(second))
  | {cs:cells}{offset:nat}{text_len,back,first,second,third:int | 65536 <= text_len; back < 65000}
    CUTC_65533(cs, offset, text_len, 65533)
      of (BREAKBACK(cs, offset, 65534, 65022, back), NTH(cs, offset + 65535, first), CONTINUES(first),
          NTH(cs, offset + 65534, second), CONTINUES(second), NTH(cs, offset + 65533, third), STARTS(third))
  | {cs:cells}{offset:nat}{text_len,back,first,second,third:int | 65536 <= text_len; back < 65000}
    CUTC_none_starts(cs, offset, text_len, 65535)
      of (BREAKBACK(cs, offset, 65534, 65022, back), NTH(cs, offset + 65535, first), CONTINUES(first),
          NTH(cs, offset + 65534, second), CONTINUES(second), NTH(cs, offset + 65533, third), CONTINUES(third))

prfn probe_back_le_65535 {cs:cells}{offset:nat}{text_len,back:int | 65536 <= text_len; 65000 <= back; back <= (65535) + 1} (premise1: BREAKBACK(cs, offset, 65534, 65022, back)): CUTC(cs, offset, text_len, back) = CUTC_break{cs}{offset}{text_len,back}(premise1)
