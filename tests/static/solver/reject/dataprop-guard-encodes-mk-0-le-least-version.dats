#include "share/atspre_staload.hats"
(* quire src/record.bats ENCODES, copied: see gen_guards.py.
   False variant: the guard atom `0 <= least_version` of ENCODES_mk shifted by 1: `0 <= (least_version) + 1` *)
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

stadef READER = 1

datasort pchunks =
  | pnil of ()
  | pgood of (bytes, bytes, pchunks)                           
  | pbad of (bytes, pchunks)                             

dataprop SPECN(specs, int) =
  | SPECN_nil(gs_nil(), 0)
  | {group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}
    SPECN_cons(gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1) of SPECN(more, spec_n)

dataprop TAGDIFF(bytes, bytes) =
  | {left_first,left_second,left_third,left_fourth,right_first,right_second,right_third,right_fourth:int | 0 <= left_first; left_first < 256; 0 <= left_second; left_second < 256; 0 <= left_third; left_third < 256; 0 <= left_fourth; left_fourth < 256;
       0 <= right_first; right_first < 256; 0 <= right_second; right_second < 256; 0 <= right_third; right_third < 256; 0 <= right_fourth; right_fourth < 256;
       left_first != right_first || left_second != right_second || left_third != right_third || left_fourth != right_fourth}
    TAGDIFF_mk(bcons(left_first, bcons(left_second, bcons(left_third, bcons(left_fourth, bnil())))), bcons(right_first, bcons(right_second, bcons(right_third, bcons(right_fourth, bnil())))))

dataprop NOTKNOWN(specs, bytes) =
  | {tag:bytes} NOTKNOWN_nil(gs_nil(), tag)
  | {tag,other:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{rest:specs}
    NOTKNOWN_cons(gs_cons(other, kinds, requirement, defaults, rest), tag) of (TAGDIFF(other, tag), NOTKNOWN(rest, tag))

dataprop SPECSOK(specs) =
  | SPECSOK_nil(gs_nil())
  | {tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}
    SPECSOK_cons(gs_cons(tag, kinds, requirement, defaults, more)) of (NOTKNOWN(more, tag), SPECSOK(more))

dataprop ANC(bytes) =
  | {first_letter,second_letter,third_letter,fourth_letter:int | 97 <= first_letter; first_letter < 256; 0 <= second_letter; second_letter < 256; 0 <= third_letter; third_letter < 256; 0 <= fourth_letter; fourth_letter < 256}
    ANC_mk(bcons(first_letter, bcons(second_letter, bcons(third_letter, bcons(fourth_letter, bnil())))))

dataprop XENC(specs, extras, pchunks) =
  | {known:specs} XENC_nil(known, ex_nil(), pnil())
  | {known:specs}{tag,data:bytes}{kept:extras}{rest:pchunks}
    XENC_cons(known, ex_cons(tag, data, kept), pgood(tag, data, rest)) of (ANC(tag), NOTKNOWN(known, tag), XENC(known, kept, rest))

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

dataprop LES(int, int, bytes) =
  | {low_byte:int | 0 <= low_byte; low_byte < 128} LES_last(1, low_byte, bcons(low_byte, bnil()))
  | {low_byte:int | 128 <= low_byte; low_byte < 256} LES_last_neg(1, low_byte - 256, bcons(low_byte, bnil()))
  | {byte_count:pos}{rest_number:int}{low_byte:int | 0 <= low_byte; low_byte < 256}{octets:bytes}
    LES_cons(byte_count+1, low_byte + 256*rest_number, bcons(low_byte, octets)) of LES(byte_count, rest_number, octets)

dataprop APPEND(bytes, bytes, bytes) =
  | {back:bytes} APPEND_nil(bnil(), back, back)
  | {octet:int}{front,back,joined:bytes} APPEND_cons(bcons(octet, front), back, bcons(octet, joined)) of APPEND(front, back, joined)

dataprop STRB(bytes, bytes) =
  | {len:int | 0 <= len; len < 256}{text:bytes} STRB_mk(text, bcons(len, text)) of LEN(text, len)

dataprop FENC(layout, fvals, bytes) =
  | FENC_nil(lo_nil(), fv_nil(), bnil())
  | {number:int}{kinds:layout}{contents:fvals}{four_octets,rest,out:bytes}
    FENC_i32(lo_i32(kinds), fv_i32(number, contents), out) of (LES(4, number, four_octets), FENC(kinds, contents, rest), APPEND(four_octets, rest, out))
  | {text:bytes}{kinds:layout}{contents:fvals}{prefixed,rest,out:bytes}
    FENC_str(lo_str(kinds), fv_str(text, contents), out) of (STRB(text, prefixed), FENC(kinds, contents, rest), APPEND(prefixed, rest, out))

dataprop SENC(specs, specs, int, gvals, extras, absent, pchunks) =
  | {known:specs}{kept:extras}{chunks:pchunks} SENC_nil(known, gs_nil(), 0, gv_nil(), kept, ab_nil(), chunks) of XENC(known, kept, chunks)
  | {known:specs}{group_tag:bytes}{kinds:layout}{requirement:mode}{defaults:fvals}{more:specs}{spec_n:nat}{field_values:fvals}{group_values:gvals}{kept:extras}{missing:absent}{data:bytes}{data_len:nat}{rest:pchunks}
    SENC_cons(known, gs_cons(group_tag, kinds, requirement, defaults, more), spec_n+1, gv_cons(field_values, group_values), kept, missing, pgood(group_tag, data, rest))
    of (LEN(data, data_len), FENC(kinds, field_values, data), SENC(known, more, spec_n, group_values, kept, missing, rest))
  | {known:specs}{group_tag:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}
    SENC_absent_end(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, gv_cons(defaults, group_values), kept, ab_cons(group_tag, missing), pnil())
    of SENC(known, more, spec_n, group_values, kept, missing, pnil())
  | {known:specs}{group_tag,tag,data:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}{group_values:gvals}{kept:extras}{missing:absent}{rest:pchunks}
    SENC_absent_good(known, gs_cons(group_tag, kinds, m_added(), defaults, more), spec_n+1, gv_cons(defaults, group_values), kept, ab_cons(group_tag, missing), pgood(tag, data, rest))
    of (TAGDIFF(tag, group_tag), SENC(known, more, spec_n, group_values, kept, missing, pgood(tag, data, rest)))

dataprop ALLGOOD(int, pchunks) =
  | ALLGOOD_nil(0, pnil())
  | {chunk_count:nat}{tag,data:bytes}{chunks:pchunks} ALLGOOD_cons(chunk_count+1, pgood(tag, data, chunks)) of ALLGOOD(chunk_count, chunks)

dataprop PCN(int, pchunks) =
  | PCN_nil(0, pnil())
  | {chunk_count:nat}{tag,data:bytes}{chunks:pchunks} PCN_good(chunk_count+1, pgood(tag, data, chunks)) of PCN(chunk_count, chunks)
  | {chunk_count:nat}{tag:bytes}{chunks:pchunks} PCN_bad(chunk_count+1, pbad(tag, chunks)) of PCN(chunk_count, chunks)

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

dataprop CKENC(bytes, bytes, bytes) =
  | {data_size:nat}{tag,data,lenb,crcb,data_crc,tag_data_crc,out:bytes}{crc_high,crc_low:nat}
    CKENC_mk(tag, data, out)
    of (LEN(tag, 4), LEN(data, data_size), LENOK(lenb, data_size), CRCB(crcb, crc_high, crc_low), CRCP(tag, data, crc_high, crc_low),
        APPEND(data, crcb, data_crc), APPEND(tag, data_crc, tag_data_crc), APPEND(lenb, tag_data_crc, out))

stadef IEND = bcons(73, bcons(69, bcons(78, bcons(68, bnil()))))

dataprop TAGNOT(bytes) =
  | {tag_first_byte,tag_second_byte,tag_third_byte,tag_fourth_byte:int | 0 <= tag_first_byte; tag_first_byte < 256; 0 <= tag_second_byte; tag_second_byte < 256; 0 <= tag_third_byte; tag_third_byte < 256; 0 <= tag_fourth_byte; tag_fourth_byte < 256;
       tag_first_byte != 73 || tag_second_byte != 69 || tag_third_byte != 78 || tag_fourth_byte != 68}
    TAGNOT_mk(bcons(tag_first_byte, bcons(tag_second_byte, bcons(tag_third_byte, bcons(tag_fourth_byte, bnil())))))

dataprop CHAINS(int, pchunks, bytes) =
  | {octets:bytes} CHAINS_end(0, pnil(), octets) of CKENC(IEND, bnil(), octets)
  | {chunk_count:nat}{tag,data,chunk,after_chunk,octets:bytes}{chunks:pchunks}
    CHAINS_cons(chunk_count+1, pgood(tag, data, chunks), octets) of (TAGNOT(tag), CKENC(tag, data, chunk), CHAINS(chunk_count, chunks, after_chunk), APPEND(chunk, after_chunk, octets))

dataprop ENCODES(specs, int, rx, bytes) =
  | {spec_list:specs}{spec_n:nat}{kind,format_version,least_version:int | 0 <= kind; kind < 256; 0 <= format_version; format_version < 256; 0 <= least_version; least_version <= READER}
    {vals:gvals}{kept_extras:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat}{body,octets:bytes}
    ENCODES_mk(spec_list, kind, rx_mk(format_version, least_version, vals, kept_extras, missing), octets)
    of (SPECN(spec_list, spec_n), SPECSOK(spec_list), SENC(spec_list, spec_list, spec_n, vals, kept_extras, missing, chunks), ALLGOOD(chunk_count, chunks), PCN(chunk_count, chunks), CHAINS(chunk_count, chunks, body),
        APPEND(bcons(81, bcons(82, bcons(69, bcons(67, bcons(kind, bcons(format_version, bcons(least_version, bnil()))))))), body, octets))

prfn probe_0_le_least_version {spec_list:specs}{spec_n:nat}{kind,format_version,least_version:int | 0 <= kind; kind < 256; 0 <= format_version; format_version < 256; 0 <= (least_version) + 1; least_version <= READER}{vals:gvals}{kept_extras:extras}{missing:absent}{chunks:pchunks}{chunk_count:nat}{body,octets:bytes} (premise1: SPECN(spec_list, spec_n), premise2: SPECSOK(spec_list), premise3: SENC(spec_list, spec_list, spec_n, vals, kept_extras, missing, chunks), premise4: ALLGOOD(chunk_count, chunks), premise5: PCN(chunk_count, chunks), premise6: CHAINS(chunk_count, chunks, body), premise7: APPEND(bcons(81, bcons(82, bcons(69, bcons(67, bcons(kind, bcons(format_version, bcons(least_version, bnil()))))))), body, octets)): ENCODES(spec_list, kind, rx_mk(format_version, least_version, vals, kept_extras, missing), octets) = ENCODES_mk{spec_list}{spec_n}{kind,format_version,least_version}{vals}{kept_extras}{missing}{chunks}{chunk_count}{body,octets}(premise1, premise2, premise3, premise4, premise5, premise6, premise7)
