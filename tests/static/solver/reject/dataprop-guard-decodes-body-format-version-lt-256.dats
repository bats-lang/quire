#include "share/atspre_staload.hats"
(* quire src/record.bats DECODES, copied: see gen_guards.py.
   False variant: the guard atom `format_version < 256` of DECODES_body shifted by 1: `format_version < (256) + 1` *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

datasort layout =
  | lo_nil of ()
  | lo_i32 of (layout)
  | lo_str of (layout)

datasort mode =
  | m_req of ()                                                            
  | m_opt of ()                                                                                             
  | m_added of ()                                                                                                       

datasort fvals =
  | fv_nil of ()
  | fv_i32 of (int, fvals)
  | fv_str of (bytes, fvals)

datasort specs =
  | gs_nil of ()
  | gs_cons of (bytes, layout, mode, fvals, specs)

datasort gvals =
  | gv_nil of ()
  | gv_cons of (fvals, gvals)

datasort extras =
  | ex_nil of ()
  | ex_cons of (bytes, bytes, extras)                  

datasort absent =
  | ab_nil of ()
  | ab_cons of (bytes, absent)

datasort rx =
  | rx_mk of (int, int, gvals, extras, absent)

datasort seqcause =
  | sc_trunc of ()                                              
  | sc_big of ()                                                
  | sc_trailing of ()                                   
  | sc_end_data of ()                                 

datasort lost =
  | lt_nil of ()
  | lt_cons of (bytes, lost)
  | lt_cut of (seqcause, lost)

datasort recres =
  | rr_ok of (rx)
  | rr_loss of (rx, lost)
  | rr_notquire of ()                               
  | rr_newer of ()                                                               
  | rr_damaged of ()

dataprop SHORT(int, bytes) =
  | {count:pos} SHORT_nil(count, bnil())
  | {count:nat}{octet:int}{octets:bytes} SHORT_succ(count+1, bcons(octet, octets)) of SHORT(count, octets)

dataprop TAKE(int, bytes, bytes, bytes) =
  | {octets:bytes} TAKE_zero(0, octets, bnil(), octets)
  | {count:nat}{octet:int}{octets,taken,rest:bytes} TAKE_succ(count+1, bcons(octet, octets), bcons(octet, taken), rest) of TAKE(count, octets, taken, rest)

dataprop MAGICDIFF(bytes) =
  | {magic0,magic1,magic2,magic3:int | 0 <= magic0; magic0 < 256; 0 <= magic1; magic1 < 256; 0 <= magic2; magic2 < 256; 0 <= magic3; magic3 < 256;
       magic0 != 81 || magic1 != 82 || magic2 != 69 || magic3 != 67}
    MAGICDIFF_mk(bcons(magic0, bcons(magic1, bcons(magic2, bcons(magic3, bnil())))))

stadef READER = 1

datasort pchunks =
  | pnil of ()
  | pgood of (bytes, bytes, pchunks)                           
  | pbad of (bytes, pchunks)                             

datasort seqres =
  | sq_ok of (pchunks)
  | sq_cut of (pchunks, seqcause)

datasort ckres =
  | ck_trunc of ()                                              
  | ck_big of ()                                                     
  | ck_ok of (bytes, bytes, bytes)                              
  | ck_bad of (bytes, bytes, bytes)                           

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

datasort sdres =
  | sd_ok of (gvals, extras, absent)
  | sd_loss of (gvals, extras, lost, absent)
  | sd_fail of (cause)

dataprop SPECN(specs, int) =
  | SPECN_nil(gs_nil(), 0)
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}
    SPECN_cons(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1) of SPECN(more, spec_n)

dataprop PCN(int, pchunks) =
  | PCN_nil(0, pnil())
  | {chunk_count:nat}{tag,data:bytes}{chunks:pchunks} PCN_good(chunk_count+1, pgood(tag, data, chunks)) of PCN(chunk_count, chunks)
  | {chunk_count:nat}{tag:bytes}{chunks:pchunks} PCN_bad(chunk_count+1, pbad(tag, chunks)) of PCN(chunk_count, chunks)

datasort selected =
  | sel_none of ()
  | sel_good of (bytes)
  | sel_bad of ()

dataprop TAGDIFF(bytes, bytes) =
  | {left_first,left_second,left_third,left_fourth,right_first,right_second,right_third,right_fourth:int | 0 <= left_first; left_first < 256; 0 <= left_second; left_second < 256; 0 <= left_third; left_third < 256; 0 <= left_fourth; left_fourth < 256;
       0 <= right_first; right_first < 256; 0 <= right_second; right_second < 256; 0 <= right_third; right_third < 256; 0 <= right_fourth; right_fourth < 256;
       left_first != right_first || left_second != right_second || left_third != right_third || left_fourth != right_fourth}
    TAGDIFF_mk(bcons(left_first, bcons(left_second, bcons(left_third, bcons(left_fourth, bnil())))), bcons(right_first, bcons(right_second, bcons(right_third, bcons(right_fourth, bnil())))))

dataprop EXT(bytes, pchunks, selected, pchunks, lost) =
  | {tag:bytes} EXT_nil(tag, pnil(), sel_none(), pnil(), lt_nil())
  | {tag,other,data:bytes}{rest,others:pchunks}{chosen:selected}{dropped:lost}
    EXT_skip_good(tag, pgood(other, data, rest), chosen, pgood(other, data, others), dropped) of (TAGDIFF(other, tag), EXT(tag, rest, chosen, others, dropped))
  | {tag,other:bytes}{rest,others:pchunks}{chosen:selected}{dropped:lost}
    EXT_skip_bad(tag, pbad(other, rest), chosen, pbad(other, others), dropped) of (TAGDIFF(other, tag), EXT(tag, rest, chosen, others, dropped))
  | {tag,data:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_good_last(tag, pgood(tag, data, rest), sel_good(data), others, dropped) of EXT(tag, rest, sel_none(), others, dropped)
  | {tag,data,later:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_good_shadowed(tag, pgood(tag, data, rest), sel_good(later), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_good(later), others, dropped)
  | {tag,data:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_good_over_bad(tag, pgood(tag, data, rest), sel_good(data), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_bad(), others, dropped)
  | {tag:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_bad_last(tag, pbad(tag, rest), sel_bad(), others, dropped) of EXT(tag, rest, sel_none(), others, dropped)
  | {tag,later:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_bad_shadowed(tag, pbad(tag, rest), sel_good(later), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_good(later), others, dropped)
  | {tag:bytes}{rest,others:pchunks}{dropped:lost}
    EXT_bad_over_bad(tag, pbad(tag, rest), sel_bad(), others, lt_cons(tag, dropped)) of EXT(tag, rest, sel_bad(), others, dropped)

dataprop LOSTCAT(lost, lost, lost, int) =
  | {second:lost} LOSTCAT_nil(lt_nil(), second, second, 0)
  | {tag:bytes}{first,second,both:lost}{first_n:nat} LOSTCAT_cons(lt_cons(tag, first), second, lt_cons(tag, both), first_n+1) of LOSTCAT(first, second, both, first_n)
  | {cause:seqcause}{first,second,both:lost}{first_n:nat} LOSTCAT_cut(lt_cut(cause, first), second, lt_cut(cause, both), first_n+1) of LOSTCAT(first, second, both, first_n)

dataprop CANON(specs, int, pchunks, pchunks, lost) =
  | {chunks:pchunks} CAN_nil(gs_nil(), 0, chunks, chunks, lt_nil())
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{chunks,others,canonical:pchunks}{other_count,first_n:nat}{first,second,dropped:lost}
    CAN_none(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, chunks, canonical, dropped)
    of (EXT(group_tag, chunks, sel_none(), others, first), PCN(other_count, others), CANON(more, spec_n, others, canonical, second), LOSTCAT(first, second, dropped, first_n))
  | {group_tag,data:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{chunks,others,canonical:pchunks}{other_count,first_n:nat}{first,second,dropped:lost}
    CAN_good(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, chunks, pgood(group_tag, data, canonical), dropped)
    of (EXT(group_tag, chunks, sel_good(data), others, first), PCN(other_count, others), CANON(more, spec_n, others, canonical, second), LOSTCAT(first, second, dropped, first_n))
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{chunks,others,canonical:pchunks}{other_count,first_n:nat}{first,second,dropped:lost}
    CAN_bad(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, chunks, pbad(group_tag, canonical), dropped)
    of (EXT(group_tag, chunks, sel_bad(), others, first), PCN(other_count, others), CANON(more, spec_n, others, canonical, second), LOSTCAT(first, second, dropped, first_n))

dataprop ANC(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 97 <= first_letter; first_letter < 256; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    ANC_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

dataprop NOTKNOWN(specs, bytes) =
  | {tag:bytes} NOTKNOWN_nil(gs_nil(), tag)
  | {tag,other:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs}
    NOTKNOWN_cons(gs_cons(other, kinds, requirement, defaults, rest), tag) of (TAGDIFF(other, tag), NOTKNOWN(rest, tag))

dataprop PREPX(bytes, bytes, sdres, sdres) =
  | {tag,data:bytes}{group_values:gvals}{kept:extras}{missing:absent} PREPX_ok(tag, data, sd_ok(group_values, kept, missing), sd_ok(group_values, ex_cons(tag, data, kept), missing))
  | {tag,data:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPX_loss(tag, data, sd_loss(group_values, kept, lost_tags, missing), sd_loss(group_values, ex_cons(tag, data, kept), lost_tags, missing))
  | {tag,data:bytes}{reason:cause} PREPX_fail(tag, data, sd_fail(reason), sd_fail(reason))

dataprop KNOWN(specs, bytes, int) =
  | {tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs} KNOWN_here(gs_cons(tag, kinds, requirement, defaults, rest), tag, 0)
  | {position:nat}{tag,other:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs}
    KNOWN_later(gs_cons(other, kinds, requirement, defaults, rest), tag, position+1) of KNOWN(rest, tag, position)

dataprop PREPT(bytes, sdres, sdres) =
  | {tag:bytes}{group_values:gvals}{kept:extras}{missing:absent} PREPT_ok(tag, sd_ok(group_values, kept, missing), sd_loss(group_values, kept, lt_cons(tag, lt_nil()), missing))
  | {tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPT_loss(tag, sd_loss(group_values, kept, lost_tags, missing), sd_loss(group_values, kept, lt_cons(tag, lost_tags), missing))
  | {tag:bytes}{reason:cause} PREPT_fail(tag, sd_fail(reason), sd_fail(reason))

dataprop CRIT(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 0 <= first_letter; first_letter < 97; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    CRIT_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

dataprop XDEC(specs, pchunks, sdres) =
  | {known:specs} XD_nil(known, pnil(), sd_ok(gv_nil(), ex_nil(), ab_nil()))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{rest_result,whole_result:sdres}
    XD_anc(known, pgood(tag, data, rest), whole_result) of (ANC(tag), NOTKNOWN(known, tag), XDEC(known, rest, rest_result), PREPX(tag, data, rest_result, whole_result))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{position:nat}
    XD_anc_known(known, pgood(tag, data, rest), sd_fail(cause_damaged())) of (ANC(tag), KNOWN(known, tag, position))
  | {known:specs}{tag:bytes}{rest:pchunks}{rest_result,whole_result:sdres}
    XD_anc_lost(known, pbad(tag, rest), whole_result) of (ANC(tag), XDEC(known, rest, rest_result), PREPT(tag, rest_result, whole_result))
  | {known:specs}{tag,data:bytes}{rest:pchunks}
    XD_newer(known, pgood(tag, data, rest), sd_fail(cause_newer())) of (CRIT(tag), NOTKNOWN(known, tag))
  | {known:specs}{tag,data:bytes}{rest:pchunks}{position:nat}
    XD_known(known, pgood(tag, data, rest), sd_fail(cause_damaged())) of (CRIT(tag), KNOWN(known, tag, position))
  | {known:specs}{tag:bytes}{rest:pchunks}
    XD_crit_bad(known, pbad(tag, rest), sd_fail(cause_damaged())) of CRIT(tag)

datasort fdres =
  | fd_ok of (fvals)
  | fd_bad of ()

dataprop LES(int, int, bytes) =
  | {low_byte:int | 0 <= low_byte; low_byte < 128} LES_last(1, low_byte, bcons(low_byte, bnil()))
  | {low_byte:int | 128 <= low_byte; low_byte < 256} LES_last_neg(1, low_byte - 256, bcons(low_byte, bnil()))
  | {byte_count:pos}{rest_number:int}{low_byte:int | 0 <= low_byte; low_byte < 256}{octets:bytes}
    LES_cons(byte_count+1, low_byte + 256*rest_number, bcons(low_byte, octets)) of LES(byte_count, rest_number, octets)

dataprop FDEC(layout, bytes, fdres) =
  | FDEC_nil(lo_nil(), bnil(), fd_ok(fv_nil()))
  | {first_byte:int | 0 <= first_byte; first_byte < 256}{after_first:bytes} FDEC_nil_extra(lo_nil(), bcons(first_byte, after_first), fd_bad())
  | {kinds:layout}{octets:bytes} FDEC_i32_short(lo_i32(kinds), octets, fd_bad()) of SHORT(4, octets)
  | {number:int}{kinds:layout}{contents:fvals}{octets,four_octets,rest:bytes}
    FDEC_i32_ok(lo_i32(kinds), octets, fd_ok(fv_i32(number, contents))) of (TAKE(4, octets, four_octets, rest), LES(4, number, four_octets), FDEC(kinds, rest, fd_ok(contents)))
  | {number:int}{kinds:layout}{octets,four_octets,rest:bytes}
    FDEC_i32_bad(lo_i32(kinds), octets, fd_bad()) of (TAKE(4, octets, four_octets, rest), LES(4, number, four_octets), FDEC(kinds, rest, fd_bad()))
  | {kinds:layout} FDEC_str_empty(lo_str(kinds), bnil(), fd_bad())
  | {kinds:layout}{len:int | 0 <= len; len < 256}{after_length:bytes}
    FDEC_str_short(lo_str(kinds), bcons(len, after_length), fd_bad()) of SHORT(len, after_length)
  | {kinds:layout}{len:int | 0 <= len; len < 256}{after_length,text,rest:bytes}{contents:fvals}
    FDEC_str_ok(lo_str(kinds), bcons(len, after_length), fd_ok(fv_str(text, contents))) of (TAKE(len, after_length, text, rest), FDEC(kinds, rest, fd_ok(contents)))
  | {kinds:layout}{len:int | 0 <= len; len < 256}{after_length,text,rest:bytes}
    FDEC_str_bad(lo_str(kinds), bcons(len, after_length), fd_bad()) of (TAKE(len, after_length, text, rest), FDEC(kinds, rest, fd_bad()))

dataprop PREPV(fvals, sdres, sdres) =
  | {field_values:fvals}{group_values:gvals}{kept:extras}{missing:absent} PREPV_ok(field_values, sd_ok(group_values, kept, missing), sd_ok(gv_cons(field_values, group_values), kept, missing))
  | {field_values:fvals}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent} PREPV_loss(field_values, sd_loss(group_values, kept, lost_tags, missing), sd_loss(gv_cons(field_values, group_values), kept, lost_tags, missing))
  | {field_values:fvals}{reason:cause} PREPV_fail(field_values, sd_fail(reason), sd_fail(reason))

dataprop LOSES(mode) =
  | LOSES_req(m_req())
  | LOSES_opt(m_opt())

dataprop PREPL(fvals, bytes, sdres, sdres) =
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{missing:absent}
    PREPL_ok(defaults, tag, sd_ok(group_values, kept, missing), sd_loss(gv_cons(defaults, group_values), kept, lt_cons(tag, lt_nil()), missing))
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPL_loss(defaults, tag, sd_loss(group_values, kept, lost_tags, missing), sd_loss(gv_cons(defaults, group_values), kept, lt_cons(tag, lost_tags), missing))
  | {defaults:fvals}{tag:bytes}{reason:cause} PREPL_fail(defaults, tag, sd_fail(reason), sd_fail(reason))

dataprop PREPA(fvals, bytes, sdres, sdres) =
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{missing:absent}
    PREPA_ok(defaults, tag, sd_ok(group_values, kept, missing), sd_ok(gv_cons(defaults, group_values), kept, ab_cons(tag, missing)))
  | {defaults:fvals}{tag:bytes}{group_values:gvals}{kept:extras}{lost_tags:lost}{missing:absent}
    PREPA_loss(defaults, tag, sd_loss(group_values, kept, lost_tags, missing), sd_loss(gv_cons(defaults, group_values), kept, lost_tags, ab_cons(tag, missing)))
  | {defaults:fvals}{tag:bytes}{reason:cause} PREPA_fail(defaults, tag, sd_fail(reason), sd_fail(reason))

dataprop SDEC(specs, specs, int, pchunks, sdres) =
  | {known:specs}{chunks:pchunks}{whole_result:sdres}
    SD_nil(known, gs_nil(), 0, chunks, whole_result) of XDEC(known, chunks, whole_result)
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{field_values:fvals}{rest_result,whole_result:sdres}
    SD_present(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, pgood(group_tag, data, rest), whole_result)
    of (LEN(data, data_len), FDEC(kinds, data, fd_ok(field_values)), SDEC(known, more, spec_n, rest, rest_result), PREPV(field_values, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_garbled_lost(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, pgood(group_tag, data, rest), whole_result)
    of (LOSES(requirement), LEN(data, data_len), FDEC(kinds, data, fd_bad()), SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{data:bytes}{data_len:nat}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_garbled_added(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pgood(group_tag, data, rest), whole_result)
    of (LEN(data, data_len), FDEC(kinds, data, fd_bad()), SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_bad_lost(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, pbad(group_tag, rest), whole_result)
    of (LOSES(requirement), SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_bad_added(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pbad(group_tag, rest), whole_result)
    of (SDEC(known, more, spec_n, rest, rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
                                                                                                                                
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest_result,whole_result:sdres}
    SD_absent_lost_end(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, pnil(), whole_result)
    of (LOSES(requirement), SDEC(known, more, spec_n, pnil(), rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag,tag,data:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_absent_lost_good(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, pgood(tag, data, rest), whole_result)
    of (LOSES(requirement), TAGDIFF(tag, group_tag), SDEC(known, more, spec_n, pgood(tag, data, rest), rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag,tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_absent_lost_bad(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, pbad(tag, rest), whole_result)
    of (LOSES(requirement), TAGDIFF(tag, group_tag), SDEC(known, more, spec_n, pbad(tag, rest), rest_result), PREPL(defaults, group_tag, rest_result, whole_result))
                                                                                                                    
  | {known,more:specs}{spec_n:nat}{group_tag:bytes}{kinds:layout}{defaults:fvals}{rest_result,whole_result:sdres}
    SD_added_end(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pnil(), whole_result)
    of (SDEC(known, more, spec_n, pnil(), rest_result), PREPA(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag,tag,data:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_added_good(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pgood(tag, data, rest), whole_result)
    of (TAGDIFF(tag, group_tag), SDEC(known, more, spec_n, pgood(tag, data, rest), rest_result), PREPA(defaults, group_tag, rest_result, whole_result))
  | {known,more:specs}{spec_n:nat}{group_tag,tag:bytes}{kinds:layout}{defaults:fvals}{rest:pchunks}{rest_result,whole_result:sdres}
    SD_added_bad(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, pbad(tag, rest), whole_result)
    of (TAGDIFF(tag, group_tag), SDEC(known, more, spec_n, pbad(tag, rest), rest_result), PREPA(defaults, group_tag, rest_result, whole_result))

dataprop JOIN(int, int, lost, sdres, recres) =
  | {format_version,least_version:int}{vals:gvals}{kept_extras:extras}{missing:absent}
    JOIN_ok(format_version, least_version, lt_nil(), sd_ok(vals, kept_extras, missing), rr_ok(rx_mk(format_version, least_version, vals, kept_extras, missing)))
  | {format_version,least_version:int}{vals:gvals}{kept_extras:extras}{missing:absent}{tag:bytes}{more:lost}
    JOIN_ok_dropped(format_version, least_version, lt_cons(tag, more), sd_ok(vals, kept_extras, missing), rr_loss(rx_mk(format_version, least_version, vals, kept_extras, missing), lt_cons(tag, more)))
  | {format_version,least_version:int}{vals:gvals}{kept_extras:extras}{missing:absent}{cause:seqcause}{more:lost}
    JOIN_ok_cut(format_version, least_version, lt_cut(cause, more), sd_ok(vals, kept_extras, missing), rr_loss(rx_mk(format_version, least_version, vals, kept_extras, missing), lt_cut(cause, more)))
  | {format_version,least_version:int}{vals:gvals}{kept_extras:extras}{missing:absent}{dropped,lost_groups,both:lost}{dropped_n:nat}
    JOIN_loss(format_version, least_version, dropped, sd_loss(vals, kept_extras, lost_groups, missing), rr_loss(rx_mk(format_version, least_version, vals, kept_extras, missing), both))
    of LOSTCAT(dropped, lost_groups, both, dropped_n)
  | {format_version,least_version:int}{dropped:lost} JOIN_damaged(format_version, least_version, dropped, sd_fail(cause_damaged()), rr_damaged())
  | {format_version,least_version:int}{dropped:lost} JOIN_newer(format_version, least_version, dropped, sd_fail(cause_newer()), rr_newer())

dataprop FIN(specs, int, int, seqres, recres) =
  | {spec_list:specs}{spec_n:nat}{format_version,least_version:int}{chunks,canonical:pchunks}{chunk_count,canonical_count:nat}{dropped:lost}{result:sdres}{outcome:recres}
    FIN_body(spec_list, format_version, least_version, sq_ok(chunks), outcome)
    of (SPECN(spec_list, spec_n), PCN(chunk_count, chunks), CANON(spec_list, spec_n, chunks, canonical, dropped), PCN(canonical_count, canonical),
        SDEC(spec_list, spec_list, spec_n, canonical, result), JOIN(format_version, least_version, dropped, result, outcome))
  | {spec_list:specs}{spec_n:nat}{format_version,least_version:int}{chunks,canonical:pchunks}{chunk_count,canonical_count:nat}{dropped:lost}{result:sdres}{outcome:recres}{cause:seqcause}
    FIN_cut(spec_list, format_version, least_version, sq_cut(chunks, cause), outcome)
    of (SPECN(spec_list, spec_n), PCN(chunk_count, chunks), CANON(spec_list, spec_n, chunks, canonical, dropped), PCN(canonical_count, canonical),
        SDEC(spec_list, spec_list, spec_n, canonical, result), JOIN(format_version, least_version, lt_cut(cause, dropped), result, outcome))

dataprop DECODES(specs, int, bytes, recres) =
  | {spec_list:specs}{kind:int}{octets:bytes}
    DECODES_short(spec_list, kind, octets, rr_notquire()) of SHORT(4, octets)
  | {spec_list:specs}{kind:int}{octets,magic_bytes,rest:bytes}
    DECODES_magic(spec_list, kind, octets, rr_notquire()) of (TAKE(4, octets, magic_bytes, rest), MAGICDIFF(magic_bytes))
  | {spec_list:specs}{kind:int}{octets,rest:bytes}
    DECODES_header_short(spec_list, kind, octets, rr_damaged())
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest), SHORT(3, rest))
  | {spec_list:specs}{kind:int}{kind_byte,format_version,least_version:int | 0 <= kind_byte; kind_byte < 256; 0 <= format_version; format_version < 256; READER < least_version; least_version < 256}{octets,rest,body:bytes}
    DECODES_newer(spec_list, kind, octets, rr_newer())
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kind_byte, bcons(format_version, bcons(least_version, bnil()))), body))
  | {spec_list:specs}{kind:int}{kind_byte,format_version,least_version:int | 0 <= kind_byte; kind_byte < 256; 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER; kind_byte != kind}{octets,rest,body:bytes}
    DECODES_kind(spec_list, kind, octets, rr_damaged())
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kind_byte, bcons(format_version, bcons(least_version, bnil()))), body))
  | {spec_list:specs}{kind,format_version,least_version:int | 0 <= kind; kind < 256; 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER}
    {octets,rest,body:bytes}{seq_outcome:seqres}{outcome:recres}
    DECODES_body(spec_list, kind, octets, outcome)
    of (TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest),
        TAKE(3, rest, bcons(kind, bcons(format_version, bcons(least_version, bnil()))), body),
        SEQ(body, seq_outcome), FIN(spec_list, format_version, least_version, seq_outcome, outcome))

prfn probe_format_version_lt_256 {spec_list:specs}{kind,format_version,least_version:int | 0 <= kind; kind < 256; 0 <= format_version; format_version < (256) + 1; 0 <= least_version; least_version <= READER}{octets,rest,body:bytes}{seq_outcome:seqres}{outcome:recres} (premise1: TAKE(4, octets, bcons(81, bcons(82, bcons(69, bcons(67, bnil())))), rest), premise2: TAKE(3, rest, bcons(kind, bcons(format_version, bcons(least_version, bnil()))), body), premise3: SEQ(body, seq_outcome), premise4: FIN(spec_list, format_version, least_version, seq_outcome, outcome)): DECODES(spec_list, kind, octets, outcome) = DECODES_body{spec_list}{kind,format_version,least_version}{octets,rest,body}{seq_outcome}{outcome}(premise1, premise2, premise3, premise4)
