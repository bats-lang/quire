#include "share/atspre_staload.hats"
(* quire src/seq.bats SQC, copied: see gen_guards.py.
   False variant: the guard atom `data_byte < 256` of SQC_end_data shifted by 1: `data_byte < (256) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

datasort pchunks =
  | pnil of ()
  | pgood of (bytes, bytes, pchunks)                           
  | pbad of (bytes, pchunks)                             

datasort seqcause =
  | sc_trunc of ()                                              
  | sc_big of ()                                                
  | sc_trailing of ()                                   
  | sc_end_data of ()                                 

datasort seqres =
  | sq_ok of (pchunks)
  | sq_cut of (pchunks, seqcause)

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

dataprop LENBIG(bytes) =
  | {length_low,length_middle,length_high,length_top:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 256; 0 <= length_top; length_top < 256; length_top > 0 || length_high >= 16}
    LENBIG_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(length_top, bnil())))))

dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)

dataprop LENOK(bytes, int) =
  | {length_low,length_middle,length_high:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 16}{size:nat}
    LENOK_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(0, bnil())))), size)
    of LE(3, size, bcons(length_low, bcons(length_middle, bcons(length_high, bnil()))))

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

dataprop CKC(int, bytes, bytes, ckres) =
  | {data_size:nat}{tag,from_data:bytes} CKC_short(data_size, tag, from_data, ck_trunc()) of SHORT(data_size, from_data)
  | {data_size:nat}{tag,from_data,data,after_data:bytes}{result:ckres} CKC_data(data_size, tag, from_data, result) of (TAKE(data_size, from_data, data, after_data), CKD(tag, data, after_data, result))

dataprop CKB(int, bytes, ckres) =
  | {data_size:nat}{from_tag:bytes} CKB_short(data_size, from_tag, ck_trunc()) of SHORT(4, from_tag)
  | {data_size:nat}{from_tag,tag,after_tag:bytes}{result:ckres} CKB_tag(data_size, from_tag, result) of (TAKE(4, from_tag, tag, after_tag), CKC(data_size, tag, after_tag, result))

dataprop CK(bytes, ckres) =
  | {octets:bytes} CK_short(octets, ck_trunc()) of SHORT(4, octets)
  | {octets,lenb,after_length:bytes} CK_big(octets, ck_big()) of (TAKE(4, octets, lenb, after_length), LENBIG(lenb))
  | {octets,lenb,after_length:bytes}{size:nat}{result:ckres} CK_len(octets, result) of (TAKE(4, octets, lenb, after_length), LENOK(lenb, size), CKB(size, after_length, result))

stadef IEND = bcons(73, bcons(69, bcons(78, bcons(68, bnil()))))

dataprop TAGNOT(bytes) =
  | {tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte:int | 0 <= tag_first_byte; tag_first_byte < 256; 0 <= tag_second_byte; tag_second_byte < 256; 0 <= tag_third_byte; tag_third_byte < 256; 0 <= tag_fourth_byte; tag_fourth_byte < 256;
       tag_first_byte != 73 || tag_second_byte != 69 || tag_third_byte != 78 || tag_fourth_byte != 68}
    TAGNOT_mk(bcons(tag_first_byte, bcons(tag_second_byte, bcons(tag_third_byte, bcons(tag_fourth_byte, bnil())))))

datasort cause =
  | cause_damaged of ()                                        
  | cause_newer of ()                                                             

dataprop SEQ(bytes, seqres) =
  | {octets:bytes}{check_result:ckres}{result:seqres} SEQ_mk(octets, result) of (CK(octets, check_result), SQC(check_result, result))

and SQC(ckres, seqres) =
  | SQC_short(ck_trunc(), sq_cut(pnil(), sc_trunc()))
  | SQC_big(ck_big(), sq_cut(pnil(), sc_big()))
  | SQC_end(ck_ok(IEND, bnil(), bnil()), sq_ok(pnil()))
  | {trailing_byte:int | 0 <= trailing_byte; trailing_byte < 256}{trailing_rest:bytes}
    SQC_trailing(ck_ok(IEND, bnil(), bcons(trailing_byte, trailing_rest)), sq_cut(pnil(), sc_trailing()))
  | {data_byte:int | 0 <= data_byte; data_byte < 256}{data_tail,rest:bytes}
    SQC_end_data(ck_ok(IEND, bcons(data_byte, data_tail), rest), sq_cut(pnil(), sc_end_data()))
  | {tag,data,rest:bytes}{chunks:pchunks}
    SQC_good(ck_ok(tag, data, rest), sq_ok(pgood(tag, data, chunks))) of (TAGNOT(tag), SEQ(rest, sq_ok(chunks)))
  | {tag,data,rest:bytes}{chunks:pchunks}{cause:seqcause}
    SQC_good_fail(ck_ok(tag, data, rest), sq_cut(pgood(tag, data, chunks), cause)) of (TAGNOT(tag), SEQ(rest, sq_cut(chunks, cause)))
  | {tag,data,rest:bytes}{chunks:pchunks}
    SQC_bad(ck_bad(tag, data, rest), sq_ok(pbad(tag, chunks))) of SEQ(rest, sq_ok(chunks))
  | {tag,data,rest:bytes}{chunks:pchunks}{cause:seqcause}
    SQC_bad_fail(ck_bad(tag, data, rest), sq_cut(pbad(tag, chunks), cause)) of SEQ(rest, sq_cut(chunks, cause))

prfn probe_data_byte_lt_256 {data_byte:int | 0 <= data_byte; data_byte < (256) + 1}{data_tail,rest:bytes} (): SQC(ck_ok(IEND, bcons(data_byte, data_tail), rest), sq_cut(pnil(), sc_end_data())) = SQC_end_data{data_byte}{data_tail,rest}()
