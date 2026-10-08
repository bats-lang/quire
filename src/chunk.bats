(* chunk -- the framing of a record: length, tag, data, checksum *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "bytes.sats"
staload "crc.sats"

(* CRCP(tag, data, high, low): the checksum of the tag followed by the
   data, as two 16-bit halves *)
#pub dataprop CRCP(bytes, bytes, int, int) =
  | {tag_size,data_size:nat}{tag,data:bytes}{tag_high,tag_low,data_high,data_low:nat | data_high < 65536; data_low < 65536}
    CRCP_mk(tag, data, 65535 - data_high, 65535 - data_low)
    of (LEN(tag, tag_size), LEN(data, data_size), CRCFROM(65535, 65535, tag, tag_high, tag_low), CRCFROM(tag_high, tag_low, data, data_high, data_low))

#pub prfun crcp_functional {tag,data:bytes}{first_high,first_low,second_high,second_low:int} (CRCP(tag, data, first_high, first_low), CRCP(tag, data, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void

prfn _crcp_functional {tag,data:bytes}{first_high,first_low,second_high,second_low:int} (first: CRCP(tag, data, first_high, first_low), second: CRCP(tag, data, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void =
  case+ first of
  | CRCP_mk(first_tag_size, first_data_size, first_tag_crc, first_data_crc) =>
    (case+ second of
     | CRCP_mk(second_tag_size, second_data_size, second_tag_crc, second_data_crc) => let
         prval EQI_refl() = len_functional(first_tag_size, second_tag_size)
         prval EQI_refl() = len_functional(first_data_size, second_data_size)
         prval () = crcfrom_functional(first_tag_size, first_tag_crc, second_tag_crc)
       in crcfrom_functional(first_data_size, first_data_crc, second_data_crc) end)

primplement crcp_functional {tag,data}{first_high,first_low,second_high,second_low} (first, second) = _crcp_functional(first, second)


(* What a chunk read from some bytes comes to *)
#pub datasort ckres =
  | ck_trunc of ()                     (* the bytes end inside it *)
  | ck_big of ()                       (* its length is over the limit *)
  | ck_ok of (bytes, bytes, bytes)     (* tag, data, what follows *)
  | ck_bad of (bytes, bytes, bytes)    (* the checksum is wrong *)

#pub dataprop EQCK(ckres, ckres) =
  | {result:ckres} EQCK_refl(result, result)

(* LENOK(lenb, size): the 4 length bytes say size, under 2 to the 20 *)
#pub dataprop LENOK(bytes, int) =
  | {length_low,length_middle,length_high:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 16}{size:nat}
    LENOK_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(0, bnil())))), size)
    of LE(3, size, bcons(length_low, bcons(length_middle, bcons(length_high, bnil()))))

(* LENBIG(lenb): the 4 length bytes say 2 to the 20 or more *)
#pub dataprop LENBIG(bytes) =
  | {length_low,length_middle,length_high,length_top:int | 0 <= length_low; length_low < 256; 0 <= length_middle; length_middle < 256; 0 <= length_high; length_high < 256; 0 <= length_top; length_top < 256; length_top > 0 || length_high >= 16}
    LENBIG_mk(bcons(length_low, bcons(length_middle, bcons(length_high, bcons(length_top, bnil())))))

(* CRCB(crcb, crc_high, crc_low): the 4 bytes of a checksum *)
#pub dataprop CRCB(bytes, int, int) =
  | {crc_low_byte,crc_low_upper,crc_high_byte,crc_high_upper:int | 0 <= crc_low_byte; crc_low_byte < 256; 0 <= crc_low_upper; crc_low_upper < 256; 0 <= crc_high_byte; crc_high_byte < 256; 0 <= crc_high_upper; crc_high_upper < 256}{crc_high,crc_low:nat}
    CRCB_mk(bcons(crc_low_byte, bcons(crc_low_upper, bcons(crc_high_byte, bcons(crc_high_upper, bnil())))), crc_high, crc_low)
    of (LE(2, crc_low, bcons(crc_low_byte, bcons(crc_low_upper, bnil()))), LE(2, crc_high, bcons(crc_high_byte, bcons(crc_high_upper, bnil()))))

(* CKD(tag, data, from_crc, result): the checksum is read from from_crc *)
#pub dataprop CKD(bytes, bytes, bytes, ckres) =
  | {tag,data,from_crc:bytes} CKD_short(tag, data, from_crc, ck_trunc()) of SHORT(4, from_crc)
  | {tag,data,from_crc,crcb,rest:bytes}{stored_high,stored_low:nat}
    CKD_ok(tag, data, from_crc, ck_ok(tag, data, rest)) of (TAKE(4, from_crc, crcb, rest), CRCB(crcb, stored_high, stored_low), CRCP(tag, data, stored_high, stored_low))
  | {tag,data,from_crc,crcb,rest:bytes}{stored_high,stored_low,computed_high,computed_low:nat | stored_high != computed_high || stored_low != computed_low}
    CKD_bad(tag, data, from_crc, ck_bad(tag, data, rest)) of (TAKE(4, from_crc, crcb, rest), CRCB(crcb, stored_high, stored_low), CRCP(tag, data, computed_high, computed_low))

#pub prfun falsep_eqck {first_result,second_result:ckres} (FALSEP()): EQCK(first_result, second_result)

primplement falsep_eqck {first_result,second_result} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

#pub prfun ckd_functional {tag,data,from_crc:bytes}{first_result,second_result:ckres} (CKD(tag, data, from_crc, first_result), CKD(tag, data, from_crc, second_result)): EQCK(first_result, second_result)

prfn _ckd_functional {tag,data,from_crc:bytes}{first_result,second_result:ckres} (first: CKD(tag, data, from_crc, first_result), second: CKD(tag, data, from_crc, second_result)): EQCK(first_result, second_result) =
  case+ first of
  | CKD_short(first_short) =>
    (case+ second of
     | CKD_short(_) => EQCK_refl()
     | CKD_ok(second_take, _, _) => falsep_eqck(take_not_short(second_take, first_short))
     | CKD_bad(second_take, _, _) => falsep_eqck(take_not_short(second_take, first_short)))
  | CKD_ok(first_take, first_crcb, first_crcp) =>
    (case+ second of
     | CKD_short(second_short) => falsep_eqck(take_not_short(first_take, second_short))
     | CKD_ok(second_take, second_crcb, second_crcp) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
       in EQCK_refl() end
     | CKD_bad(second_take, second_crcb, second_crcp) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
         prval CRCB_mk(first_low_le, first_high_le) = first_crcb
         prval CRCB_mk(second_low_le, second_high_le) = second_crcb
         prval EQI_refl() = le_number_functional(first_low_le, second_low_le)
         prval EQI_refl() = le_number_functional(first_high_le, second_high_le)
         prval () = crcp_functional(first_crcp, second_crcp)
       in falsep_eqck(contradiction{0}()) end)
  | CKD_bad(first_take, first_crcb, first_crcp) =>
    (case+ second of
     | CKD_short(second_short) => falsep_eqck(take_not_short(first_take, second_short))
     | CKD_ok(second_take, second_crcb, second_crcp) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
         prval CRCB_mk(first_low_le, first_high_le) = first_crcb
         prval CRCB_mk(second_low_le, second_high_le) = second_crcb
         prval EQI_refl() = le_number_functional(first_low_le, second_low_le)
         prval EQI_refl() = le_number_functional(first_high_le, second_high_le)
         prval () = crcp_functional(first_crcp, second_crcp)
       in falsep_eqck(contradiction{0}()) end
     | CKD_bad(second_take, _, _) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
       in EQCK_refl() end)

primplement ckd_functional {tag,data,from_crc}{first_result,second_result} (first, second) = _ckd_functional(first, second)


(* CKC(data_size, tag, from_data, result): the data_size bytes of data are read from from_data *)
#pub dataprop CKC(int, bytes, bytes, ckres) =
  | {data_size:nat}{tag,from_data:bytes} CKC_short(data_size, tag, from_data, ck_trunc()) of SHORT(data_size, from_data)
  | {data_size:nat}{tag,from_data,data,after_data:bytes}{result:ckres} CKC_data(data_size, tag, from_data, result) of (TAKE(data_size, from_data, data, after_data), CKD(tag, data, after_data, result))

#pub prfun ckc_functional {data_size:nat}{tag,from_data:bytes}{first_result,second_result:ckres} (CKC(data_size, tag, from_data, first_result), CKC(data_size, tag, from_data, second_result)): EQCK(first_result, second_result)

prfn _ckc_functional {data_size:nat}{tag,from_data:bytes}{first_result,second_result:ckres} (first: CKC(data_size, tag, from_data, first_result), second: CKC(data_size, tag, from_data, second_result)): EQCK(first_result, second_result) =
  case+ first of
  | CKC_short(first_short) =>
    (case+ second of
     | CKC_short(_) => EQCK_refl()
     | CKC_data(second_take, _) => falsep_eqck(take_not_short(second_take, first_short)))
  | CKC_data(first_take, first_checksum) =>
    (case+ second of
     | CKC_short(second_short) => falsep_eqck(take_not_short(first_take, second_short))
     | CKC_data(second_take, second_checksum) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
       in ckd_functional(first_checksum, second_checksum) end)

primplement ckc_functional {data_size}{tag,from_data}{first_result,second_result} (first, second) = _ckc_functional(first, second)

(* CKB(data_size, from_tag, result): the tag is read from from_tag, for a chunk of data_size bytes of data *)
#pub dataprop CKB(int, bytes, ckres) =
  | {data_size:nat}{from_tag:bytes} CKB_short(data_size, from_tag, ck_trunc()) of SHORT(4, from_tag)
  | {data_size:nat}{from_tag,tag,after_tag:bytes}{result:ckres} CKB_tag(data_size, from_tag, result) of (TAKE(4, from_tag, tag, after_tag), CKC(data_size, tag, after_tag, result))

#pub prfun ckb_functional {data_size:nat}{from_tag:bytes}{first_result,second_result:ckres} (CKB(data_size, from_tag, first_result), CKB(data_size, from_tag, second_result)): EQCK(first_result, second_result)

prfn _ckb_functional {data_size:nat}{from_tag:bytes}{first_result,second_result:ckres} (first: CKB(data_size, from_tag, first_result), second: CKB(data_size, from_tag, second_result)): EQCK(first_result, second_result) =
  case+ first of
  | CKB_short(first_short) =>
    (case+ second of
     | CKB_short(_) => EQCK_refl()
     | CKB_tag(second_take, _) => falsep_eqck(take_not_short(second_take, first_short)))
  | CKB_tag(first_take, first_body) =>
    (case+ second of
     | CKB_short(second_short) => falsep_eqck(take_not_short(first_take, second_short))
     | CKB_tag(second_take, second_body) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
       in ckc_functional(first_body, second_body) end)

primplement ckb_functional {data_size}{from_tag}{first_result,second_result} (first, second) = _ckb_functional(first, second)

(* a length is not both small and big *)
#pub prfun lenok_not_big {lenb:bytes}{size:nat} (LENOK(lenb, size), LENBIG(lenb)): FALSEP()

primplement lenok_not_big {lenb}{size} (small, big) =
  case+ small of
  | LENOK_mk(_) => (case+ big of LENBIG_mk() =/=> ())

(* CK(octets, result): the chunk at the start of octets comes to result *)
#pub dataprop CK(bytes, ckres) =
  | {octets:bytes} CK_short(octets, ck_trunc()) of SHORT(4, octets)
  | {octets,lenb,after_length:bytes} CK_big(octets, ck_big()) of (TAKE(4, octets, lenb, after_length), LENBIG(lenb))
  | {octets,lenb,after_length:bytes}{size:nat}{result:ckres} CK_len(octets, result) of (TAKE(4, octets, lenb, after_length), LENOK(lenb, size), CKB(size, after_length, result))

#pub prfun ck_functional {octets:bytes}{first_result,second_result:ckres} (CK(octets, first_result), CK(octets, second_result)): EQCK(first_result, second_result)

prfn _ck_functional {octets:bytes}{first_result,second_result:ckres} (first: CK(octets, first_result), second: CK(octets, second_result)): EQCK(first_result, second_result) =
  case+ first of
  | CK_short(first_short) =>
    (case+ second of
     | CK_short(_) => EQCK_refl()
     | CK_big(second_take, _) => falsep_eqck(take_not_short(second_take, first_short))
     | CK_len(second_take, _, _) => falsep_eqck(take_not_short(second_take, first_short)))
  | CK_big(first_take, first_length) =>
    (case+ second of
     | CK_short(second_short) => falsep_eqck(take_not_short(first_take, second_short))
     | CK_big(_, _) => EQCK_refl()
     | CK_len(second_take, second_length, _) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
       in falsep_eqck(lenok_not_big(second_length, first_length)) end)
  | CK_len(first_take, first_length, first_tag_read) =>
    (case+ second of
     | CK_short(second_short) => falsep_eqck(take_not_short(first_take, second_short))
     | CK_big(second_take, second_length) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
       in falsep_eqck(lenok_not_big(first_length, second_length)) end
     | CK_len(second_take, second_length, second_tag_read) => let
         prval SAME2_refl() = take_functional(first_take, second_take)
         prval LENOK_mk(first_size_le) = first_length
         prval LENOK_mk(second_size_le) = second_length
         prval EQI_refl() = le_number_functional(first_size_le, second_size_le)
       in ckb_functional(first_tag_read, second_tag_read) end)

primplement ck_functional {octets}{first_result,second_result} (first, second) = _ck_functional(first, second)


(* the 4 length bytes are 4 long *)
#pub prfun lenok_len {lenb:bytes}{size:nat} (LENOK(lenb, size)): LEN(lenb, 4)

primplement lenok_len {lenb}{size} (lenok) =
  case+ lenok of LENOK_mk(_) => LEN_cons(LEN_cons(LEN_cons(LEN_cons(LEN_nil()))))

(* and so are the 4 checksum bytes *)
#pub prfun crcb_len {crcb:bytes}{crc_high,crc_low:nat} (CRCB(crcb, crc_high, crc_low)): LEN(crcb, 4)

primplement crcb_len {crcb}{crc_high,crc_low} (crcb_form) =
  case+ crcb_form of CRCB_mk(_, _) => LEN_cons(LEN_cons(LEN_cons(LEN_cons(LEN_nil()))))

(* CKENC(tag, data, out): out is the chunk of the tag and the data: the
   length of the data, the tag, the data, their checksum *)
#pub dataprop CKENC(bytes, bytes, bytes) =
  | {data_size:nat}{tag,data,lenb,crcb,data_crc,tag_data_crc,out:bytes}{crc_high,crc_low:nat}
    CKENC_mk(tag, data, out)
    of (LEN(tag, 4), LEN(data, data_size), LENOK(lenb, data_size), CRCB(crcb, crc_high, crc_low), CRCP(tag, data, crc_high, crc_low),
        APPEND(data, crcb, data_crc), APPEND(tag, data_crc, tag_data_crc), APPEND(lenb, tag_data_crc, out))

(* a chunk written, followed by anything, is read back as it was *)
#pub prfun ckenc_ck {tag,data,chunk,rest,octets:bytes} (CKENC(tag, data, chunk), APPEND(chunk, rest, octets))
  : CK(octets, ck_ok(tag, data, rest))

primplement ckenc_ck {tag,data,chunk,rest,octets} (encoded, whole) =
  case+ encoded of
  | CKENC_mk(tag_len, data_len, length_ok, crc_form, crc_proof, data_crc_app, tag_data_app, length_app) => let
      prval (tail_after_length, whole_length) = append_assoc(length_app, whole)
      prval (tail_after_tag, whole_tag) = append_assoc(tag_data_app, tail_after_length)
      prval (tail_after_data, whole_data) = append_assoc(data_crc_app, tail_after_tag)
      prval length_take = append_take(whole_length, lenok_len(length_ok))
      prval tag_take = append_take(whole_tag, tag_len)
      prval data_take = append_take(whole_data, data_len)
      prval crc_take = append_take(tail_after_data, crcb_len(crc_form))
    in CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_data(data_take, CKD_ok(crc_take, crc_form, crc_proof)))) end

(* and a chunk read is a chunk written *)
#pub prfun ck_ckenc {tag,data,rest,octets:bytes} (CK(octets, ck_ok(tag, data, rest)))
  : [chunk:bytes] (CKENC(tag, data, chunk), APPEND(chunk, rest, octets))

primplement ck_ckenc {tag,data,rest,octets} (read_proof) =
  case+ read_proof of
  | CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_data(data_take, CKD_ok(crc_take, crc_form, crc_proof)))) => let
      prval (length_app, length_len) = take_append(length_take)
      prval (tag_app, tag_len) = take_append(tag_take)
      prval (data_app, data_len) = take_append(data_take)
      prval (crc_app, crc_len) = take_append(crc_take)
      prval (data_crc_app, data_crc_rest) = append_assoc_rev(crc_app, data_app)
      prval (tag_data_app, tag_data_rest) = append_assoc_rev(data_crc_rest, tag_app)
      prval (chunk_app, whole_app) = append_assoc_rev(tag_data_rest, length_app)
    in (CKENC_mk(tag_len, data_len, length_ok, crc_form, crc_proof, data_crc_app, tag_data_app, chunk_app), whole_app) end


(* A chunk read, with what it holds *)
#pub datavtype ckread(ckres, int) =
  | {list_len:nat} CKR_trunc(ck_trunc(), list_len)
  | {list_len:nat} CKR_big(ck_big(), list_len)
  | {list_len:nat}{tag,data,rest:bytes}{data_size,rest_size:nat | rest_size < list_len; data_size < 1048576}
    CKR_ok(ck_ok(tag, data, rest), list_len) of (blist(tag, 4), blist(data, data_size), blist(rest, rest_size))
  | {list_len:nat}{tag,data,rest:bytes}{data_size,rest_size:nat | rest_size < list_len; data_size < 1048576}
    CKR_bad(ck_bad(tag, data, rest), list_len) of (blist(tag, 4), blist(data, data_size), blist(rest, rest_size))

(* The chunk at the start of a list, with the proof of what it comes to *)
#pub fun chunk_read {octets:bytes}{list_len:nat} (list: blist(octets, list_len)): [result:ckres] (CK(octets, result) | ckread(result, list_len))

implement chunk_read {octets}{list_len} (list) =
  case+ blist_take(4, list) of
  | ~TakeShort(short | ) => (CK_short(short) | CKR_trunc())
  | ~TakeOk(length_take | length_bytes, after_length) =>
    (case+ length_bytes of
     | ~blist_cons(length_low, ~blist_cons(length_middle, ~blist_cons(length_high, ~blist_cons(length_top, ~blist_nil())))) =>
       if length_top = 0 then
         (if length_high < 16 then let
            val size = length_low + 256 * (length_middle + 256 * length_high)
            prval length_ok = LENOK_mk(LE_cons(LE_cons(LE_cons(LE_nil()))))
          in
            case+ blist_take(4, after_length) of
            | ~TakeShort(short | ) => (CK_len(length_take, length_ok, CKB_short(short)) | CKR_trunc())
            | ~TakeOk(tag_take | tag, after_tag) =>
              (case+ blist_take(size, after_tag) of
               | ~TakeShort(short | ) => let val () = blist_free(tag) in (CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_short(short))) | CKR_trunc()) end
               | ~TakeOk(data_take | data, after_data) =>
                 (case+ blist_take(4, after_data) of
                  | ~TakeShort(short | ) => let val () = blist_free(tag) val () = blist_free(data) in (CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_data(data_take, CKD_short(short)))) | CKR_trunc()) end
                  | ~TakeOk(crc_take | crc_bytes, rest) =>
                    (case+ crc_bytes of
                     | ~blist_cons(crc_low_byte, ~blist_cons(crc_low_upper, ~blist_cons(crc_high_byte, ~blist_cons(crc_high_upper, ~blist_nil())))) => let
                      prval (_, tag_len) = take_append(tag_take)
                      prval (_, data_len) = take_append(data_take)
                      val (first | tag_high, tag_low) = crcfrom(65535, 65535, tag)
                      val (second | data_high, data_low) = crcfrom(tag_high, tag_low, data)
                      prval crc_proof = CRCP_mk(tag_len, data_len, first, second)
                      val stored_low = crc_low_byte + 256 * crc_low_upper
                      val stored_high = crc_high_byte + 256 * crc_high_upper
                      prval stored = CRCB_mk(LE_cons(LE_cons(LE_nil())), LE_cons(LE_cons(LE_nil())))
                    in
                      if stored_high = 65535 - data_high then
                        (if stored_low = 65535 - data_low then
                           (CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_data(data_take, CKD_ok(crc_take, stored, crc_proof)))) | CKR_ok(tag, data, rest))
                         else
                           (CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_data(data_take, CKD_bad(crc_take, stored, crc_proof)))) | CKR_bad(tag, data, rest)))
                      else
                        (CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_data(data_take, CKD_bad(crc_take, stored, crc_proof)))) | CKR_bad(tag, data, rest))
                    end)))
          end
          else let
            val () = blist_free(after_length)
          in (CK_big(length_take, LENBIG_mk()) | CKR_big()) end)
       else let
         val () = blist_free(after_length)
       in (CK_big(length_take, LENBIG_mk()) | CKR_big()) end)


(* The chunk of a tag and some data, with the proof that it is the one *)
#pub fun chunk_write {tag,data:bytes}{data_size:nat | data_size < 1048576} (tag: !blist(tag, 4), data: !blist(data, data_size))
  : [out:bytes] (CKENC(tag, data, out) | blist(out, data_size + 12))

implement chunk_write {tag,data}{data_size} (tag, data) = let
  val (tag_len | _) = blist_len(tag)
  val (data_len | size) = blist_len(data)
  val size_upper = size / 256
  val length_low = size - 256 * size_upper
  val size_top = size_upper / 256
  val length_middle = size_upper - 256 * size_top
  val length_high = size_top
  val length_bytes = blist_cons(length_low, blist_cons(length_middle, blist_cons(length_high, blist_cons(0, blist_nil()))))
  prval length_ok = LENOK_mk(LE_cons(LE_cons(LE_cons(LE_nil()))))
  val (first | tag_high, tag_low) = crcfrom(65535, 65535, tag)
  val (second | data_high, data_low) = crcfrom(tag_high, tag_low, data)
  prval crc_proof = CRCP_mk(tag_len, data_len, first, second)
  val crc_high = 65535 - data_high
  val crc_low = 65535 - data_low
  val crc_low_upper = crc_low / 256
  val crc_low_byte = crc_low - 256 * crc_low_upper
  val crc_high_upper = crc_high / 256
  val crc_high_byte = crc_high - 256 * crc_high_upper
  val crc_bytes = blist_cons(crc_low_byte, blist_cons(crc_low_upper, blist_cons(crc_high_byte, blist_cons(crc_high_upper, blist_nil()))))
  prval stored = CRCB_mk(LE_cons(LE_cons(LE_nil())), LE_cons(LE_cons(LE_nil())))
  val (data_crc_app | after_data) = blist_append(blist_copy(data), crc_bytes)
  val (tag_data_app | after_tag) = blist_append(blist_copy(tag), after_data)
  val (length_app | out) = blist_append(length_bytes, after_tag)
in (CKENC_mk(tag_len, data_len, length_ok, stored, crc_proof, data_crc_app, tag_data_app, length_app) | out) end


(* a chunk read, whole or with a wrong checksum, takes at least 12 bytes
   off the front *)
#pub prfun ck_ok_consumes {tag,data,rest,octets:bytes} (CK(octets, ck_ok(tag, data, rest)))
  : [chunk:bytes][chunk_size:nat | chunk_size >= 12] (APPEND(chunk, rest, octets), LEN(chunk, chunk_size))

primplement ck_ok_consumes {tag,data,rest,octets} (read_proof) = let
  prval (encoded, whole) = ck_ckenc(read_proof)
in
  case+ encoded of
  | CKENC_mk(tag_len, data_len, length_ok, crc_form, _, data_crc_app, tag_data_app, length_app) => let
      prval data_crc_len = append_len(data_crc_app, data_len, crcb_len(crc_form))
      prval tag_data_crc_len = append_len(tag_data_app, tag_len, data_crc_len)
      prval chunk_len = append_len(length_app, lenok_len(length_ok), tag_data_crc_len)
    in (whole, chunk_len) end
end

#pub prfun ck_bad_consumes {tag,data,rest,octets:bytes} (CK(octets, ck_bad(tag, data, rest)))
  : [chunk:bytes][chunk_size:nat | chunk_size >= 12] (APPEND(chunk, rest, octets), LEN(chunk, chunk_size))

primplement ck_bad_consumes {tag,data,rest,octets} (read_proof) =
  case+ read_proof of
  | CK_len(length_take, length_ok, CKB_tag(tag_take, CKC_data(data_take, CKD_bad(crc_take, crc_form, _)))) => let
      prval (length_app, length_len) = take_append(length_take)
      prval (tag_app, tag_len) = take_append(tag_take)
      prval (data_app, data_len) = take_append(data_take)
      prval (crc_app, crc_len) = take_append(crc_take)
      prval (data_crc_app, data_crc_rest) = append_assoc_rev(crc_app, data_app)
      prval (tag_data_app, tag_data_rest) = append_assoc_rev(data_crc_rest, tag_app)
      prval (chunk_app, whole_app) = append_assoc_rev(tag_data_rest, length_app)
      prval data_crc_len = append_len(data_crc_app, data_len, crc_len)
      prval tag_data_crc_len = append_len(tag_data_app, tag_len, data_crc_len)
      prval chunk_len = append_len(chunk_app, length_len, tag_data_crc_len)
    in (whole_app, chunk_len) end


(* a chunk written is at least 12 bytes long *)
#pub prfun ckenc_len {tag,data,chunk:bytes} (CKENC(tag, data, chunk)): [chunk_size:nat | chunk_size >= 12] LEN(chunk, chunk_size)

primplement ckenc_len {tag,data,chunk} (encoded) =
  case+ encoded of
  | CKENC_mk(tag_len, data_len, length_ok, crc_form, _, data_crc_app, tag_data_app, length_app) => let
      prval data_crc_len = append_len(data_crc_app, data_len, crcb_len(crc_form))
      prval tag_data_crc_len = append_len(tag_data_app, tag_len, data_crc_len)
    in append_len(length_app, lenok_len(length_ok), tag_data_crc_len) end

end
