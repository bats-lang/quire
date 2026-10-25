#include "share/atspre_staload.hats"
(* src/chunk.bats CRCP, copied: see gen_guards.py.
   Probe: every guard of CRCP_mk holds of some values, so `[1 == 2] void` under them is false and rejected *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

dataprop XOR(int, int, int) =
  | XOR_nil(0, 0, 0)
  | {a,b,c:nat | a + b > 0} XOR_00(2*a, 2*b, 2*c) of XOR(a, b, c)
  | {a,b,c:nat} XOR_01(2*a, 2*b + 1, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_10(2*a + 1, 2*b, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_11(2*a + 1, 2*b + 1, 2*c) of XOR(a, b, c)

dataprop STEP1(int, int, int, int) =
  | {high_half,carry_bit,low_half:nat | carry_bit < 2; 2*high_half + carry_bit < 65536; 2*low_half < 65536}
    STEP1_even(2*high_half + carry_bit, 2*low_half, high_half, low_half + 32768*carry_bit)
  | {high_half,carry_bit,low_half,high_xored,low_xored:nat | carry_bit < 2; 2*high_half + carry_bit < 65536; 2*low_half + 1 < 65536; high_xored < 65536; low_xored < 65536}
    STEP1_odd(2*high_half + carry_bit, 2*low_half + 1, high_xored, low_xored)
      of (XOR(high_half, 60856, high_xored), XOR(low_half + 32768*carry_bit, 33568, low_xored))

dataprop STEPN(int, int, int, int, int) =
  | {high,low:nat} STEPN_zero(0, high, low, high, low)
  | {count:nat}{high,low,mid_high,mid_low,end_high,end_low:nat}
    STEPN_succ(count+1, high, low, end_high, end_low) of (STEP1(high, low, mid_high, mid_low), STEPN(count, mid_high, mid_low, end_high, end_low))

dataprop BSTEP(int, int, int, int, int) =
  | {high,low,octet,xored_low,next_high,next_low:nat}
    BSTEP_mk(high, low, octet, next_high, next_low) of (XOR(low, octet, xored_low), STEPN(8, high, xored_low, next_high, next_low))

dataprop CRCFROM(int, int, bytes, int, int) =
  | {high,low:nat} CRCFROM_nil(high, low, bnil(), high, low)
  | {high,low,octet,mid_high,mid_low,end_high,end_low:nat}{octets:bytes}
    CRCFROM_cons(high, low, bcons(octet, octets), end_high, end_low) of (BSTEP(high, low, octet, mid_high, mid_low), CRCFROM(mid_high, mid_low, octets, end_high, end_low))

dataprop CRCP(bytes, bytes, int, int) =
  | {tag_size,data_size:nat}{tag,data:bytes}{tag_high,tag_low,data_high,data_low:nat | data_high < 65536; data_low < 65536}
    CRCP_mk(tag, data, 65535 - data_high, 65535 - data_low)
    of (LEN(tag, tag_size), LEN(data, data_size), CRCFROM(65535, 65535, tag, tag_high, tag_low), CRCFROM(tag_high, tag_low, data, data_high, data_low))

prfn satisfiable_crcp_mk {tag_size,data_size:nat}{tag,data:bytes}{tag_high,tag_low,data_high,data_low:nat | data_high < 65536; data_low < 65536} (): [1 == 2] void = ()
