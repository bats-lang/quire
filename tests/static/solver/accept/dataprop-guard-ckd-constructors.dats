#include "share/atspre_staload.hats"
(* quire src/chunk.bats CKD, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

datasort ckres =
  | ck_trunc of ()                                              
  | ck_big of ()                                                     
  | ck_ok of (bytes, bytes, bytes)                              
  | ck_bad of (bytes, bytes, bytes)                           

dataprop SHORT(int, bytes) =
  | {count:pos} SHORT_nil(count, bnil())
  | {count:nat}{octet:int}{octets:bytes} SHORT_succ(count+1, bcons(octet, octets)) of SHORT(count, octets)

dataprop TAKE(int, bytes, bytes, bytes) =
  | {octets:bytes} TAKE_zero(0, octets, bnil(), octets)
  | {count:nat}{octet:int}{octets,taken,rest:bytes} TAKE_succ(count+1, bcons(octet, octets), bcons(octet, taken), rest) of TAKE(count, octets, taken, rest)

dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)

dataprop CRCB(bytes, int, int) =
  | {crc_low_byte,crc_low_upper,crc_high_byte,crc_high_upper:int | 0 <= crc_low_byte; crc_low_byte < 256; 0 <= crc_low_upper; crc_low_upper < 256; 0 <= crc_high_byte; crc_high_byte < 256; 0 <= crc_high_upper; crc_high_upper < 256}{crc_high,crc_low:nat}
    CRCB_mk(bcons(crc_low_byte, bcons(crc_low_upper, bcons(crc_high_byte, bcons(crc_high_upper, bnil())))), crc_high, crc_low)
    of (LE(2, crc_low, bcons(crc_low_byte, bcons(crc_low_upper, bnil()))), LE(2, crc_high, bcons(crc_high_byte, bcons(crc_high_upper, bnil()))))

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

dataprop CKD(bytes, bytes, bytes, ckres) =
  | {tag,data,from_crc:bytes} CKD_short(tag, data, from_crc, ck_trunc()) of SHORT(4, from_crc)
  | {tag,data,from_crc,crcb,rest:bytes}{stored_high,stored_low:nat}
    CKD_ok(tag, data, from_crc, ck_ok(tag, data, rest)) of (TAKE(4, from_crc, crcb, rest), CRCB(crcb, stored_high, stored_low), CRCP(tag, data, stored_high, stored_low))
  | {tag,data,from_crc,crcb,rest:bytes}{stored_high,stored_low,computed_high,computed_low:nat | stored_high != computed_high || stored_low != computed_low}
    CKD_bad(tag, data, from_crc, ck_bad(tag, data, rest)) of (TAKE(4, from_crc, crcb, rest), CRCB(crcb, stored_high, stored_low), CRCP(tag, data, computed_high, computed_low))

prfn control_ckd_bad {tag,data,from_crc,crcb,rest:bytes}{stored_high,stored_low,computed_high,computed_low:nat | stored_high != computed_high || stored_low != computed_low} (premise1: TAKE(4, from_crc, crcb, rest), premise2: CRCB(crcb, stored_high, stored_low), premise3: CRCP(tag, data, computed_high, computed_low)): CKD(tag, data, from_crc, ck_bad(tag, data, rest)) = CKD_bad{tag,data,from_crc,crcb,rest}{stored_high,stored_low,computed_high,computed_low}(premise1, premise2, premise3)
