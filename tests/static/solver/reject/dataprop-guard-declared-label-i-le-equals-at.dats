#include "share/atspre_staload.hats"
(* quire src/text_relation.bats DECLARED, copied: see gen_guards.py.
   False variant: the guard atom `i <= equals_at` of DECLARED_label shifted by 1: `i <= (equals_at) + 1` *)
datasort cells =
  | cnil of ()
  | ccons of (int, cells)

datasort byteorder = LittleEndian of () | BigEndian of ()

datasort codepage = Cp1250 of () | Cp1251 of () | Cp1252 of () | Cp1253 of () | Cp1254 of () | Cp1255 of () | Cp1256 of () | Cp1257 of () | Iso88592 of () | Iso88595 of () | Iso88597 of () | Iso88598 of () | Iso885915 of () | Koi8r of ()

datasort tsrc = SrcUtf8 of () | SrcUtf16 of (byteorder) | SrcUnsupported of () | SrcTable of (codepage)

dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)

dataprop BLANKS(cells, int, int) =
  | {cells:cells}{i:nat} BLANKS_none(cells, i, i)
  | {cells:cells}{i,to:nat | i < to}{value:int | value == 32 || value == 9 || value == 10 || value == 13}
    BLANKS_more(cells, i, to) of (NTH(cells, i, value), BLANKS(cells, i + 1, to))

dataprop CLEN(cells, int) =
  | CLEN_nil(cnil(), 0)
  | {c:int}{cs:cells}{n:nat} CLEN_cons(ccons(c, cs), n + 1) of CLEN(cs, n)

dataprop BYTEAT(cells, int, int) =
  | {cells:cells}{i:nat}{value:int} BYTEAT_in(cells, i, value) of NTH(cells, i, value)
  | {cells:cells}{i:int | i < 0} BYTEAT_before(cells, i, ~1)
  | {cells:cells}{n:nat}{i:int | i >= n} BYTEAT_after(cells, i, ~1) of CLEN(cells, n)

dataprop SKIP(cells, int, int) =
  | {cells:cells}{from,to:nat}{value:int | value != 32; value != 9; value != 10; value != 13}
    SKIP_stop(cells, from, to) of (BLANKS(cells, from, to), BYTEAT(cells, to, value))

dataprop NOQUOTE(cells, int, int, int) =
  | {cells:cells}{quote:int}{i:nat} NOQUOTE_none(cells, quote, i, i)
  | {cells:cells}{quote:int}{i,to:nat | i < to}{value:int | value != quote}
    NOQUOTE_more(cells, quote, i, to) of (NTH(cells, i, value), NOQUOTE(cells, quote, i + 1, to))

stadef LABEL_COUNT = 77

datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LABELENTRY(int, bytes, tsrc) =
  | LABELENTRY_0(0, bcons(117, bcons(116, bcons(102, bcons(45, bcons(56, bnil()))))), SrcUtf8())
  | LABELENTRY_1(1, bcons(117, bcons(116, bcons(102, bcons(56, bnil())))), SrcUtf8())
  | LABELENTRY_2(2, bcons(117, bcons(110, bcons(105, bcons(99, bcons(111, bcons(100, bcons(101, bcons(45, bcons(49, bcons(45, bcons(49, bcons(45, bcons(117, bcons(116, bcons(102, bcons(45, bcons(56, bnil()))))))))))))))))), SrcUtf8())
  | LABELENTRY_3(3, bcons(117, bcons(116, bcons(102, bcons(45, bcons(49, bcons(54, bnil())))))), SrcUtf16(LittleEndian()))
  | LABELENTRY_4(4, bcons(117, bcons(116, bcons(102, bcons(49, bcons(54, bnil()))))), SrcUtf16(LittleEndian()))
  | LABELENTRY_5(5, bcons(117, bcons(116, bcons(102, bcons(45, bcons(49, bcons(54, bcons(108, bcons(101, bnil())))))))), SrcUtf16(LittleEndian()))
  | LABELENTRY_6(6, bcons(117, bcons(116, bcons(102, bcons(45, bcons(49, bcons(54, bcons(98, bcons(101, bnil())))))))), SrcUtf16(LittleEndian()))
  | LABELENTRY_7(7, bcons(117, bcons(99, bcons(115, bcons(45, bcons(50, bnil()))))), SrcUtf16(LittleEndian()))
  | LABELENTRY_8(8, bcons(117, bcons(110, bcons(105, bcons(99, bcons(111, bcons(100, bcons(101, bnil()))))))), SrcUtf16(LittleEndian()))
  | LABELENTRY_9(9, bcons(105, bcons(115, bcons(111, bcons(45, bcons(49, bcons(48, bcons(54, bcons(52, bcons(54, bcons(45, bcons(117, bcons(99, bcons(115, bcons(45, bcons(50, bnil()))))))))))))))), SrcUtf16(LittleEndian()))
  | LABELENTRY_10(10, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(48, bnil())))))))))))), SrcTable(Cp1250()))
  | LABELENTRY_11(11, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(48, bnil())))))), SrcTable(Cp1250()))
  | LABELENTRY_12(12, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(48, bnil())))))))), SrcTable(Cp1250()))
  | LABELENTRY_13(13, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(49, bnil())))))))))))), SrcTable(Cp1251()))
  | LABELENTRY_14(14, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(49, bnil())))))), SrcTable(Cp1251()))
  | LABELENTRY_15(15, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(49, bnil())))))))), SrcTable(Cp1251()))
  | LABELENTRY_16(16, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(50, bnil())))))))))))), SrcTable(Cp1252()))
  | LABELENTRY_17(17, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(50, bnil())))))), SrcTable(Cp1252()))
  | LABELENTRY_18(18, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(50, bnil())))))))), SrcTable(Cp1252()))
  | LABELENTRY_19(19, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(49, bnil())))))))))), SrcTable(Cp1252()))
  | LABELENTRY_20(20, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(49, bnil()))))))))), SrcTable(Cp1252()))
  | LABELENTRY_21(21, bcons(105, bcons(115, bcons(111, bcons(95, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(49, bnil())))))))))), SrcTable(Cp1252()))
  | LABELENTRY_22(22, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(49, bnil())))))))), SrcTable(Cp1252()))
  | LABELENTRY_23(23, bcons(108, bcons(97, bcons(116, bcons(105, bcons(110, bcons(49, bnil())))))), SrcTable(Cp1252()))
  | LABELENTRY_24(24, bcons(108, bcons(97, bcons(116, bcons(105, bcons(110, bcons(45, bcons(49, bnil()))))))), SrcTable(Cp1252()))
  | LABELENTRY_25(25, bcons(108, bcons(49, bnil())), SrcTable(Cp1252()))
  | LABELENTRY_26(26, bcons(117, bcons(115, bcons(45, bcons(97, bcons(115, bcons(99, bcons(105, bcons(105, bnil())))))))), SrcTable(Cp1252()))
  | LABELENTRY_27(27, bcons(97, bcons(115, bcons(99, bcons(105, bcons(105, bnil()))))), SrcTable(Cp1252()))
  | LABELENTRY_28(28, bcons(97, bcons(110, bcons(115, bcons(105, bcons(95, bcons(120, bcons(51, bcons(46, bcons(52, bcons(45, bcons(49, bcons(57, bcons(54, bcons(56, bnil())))))))))))))), SrcTable(Cp1252()))
  | LABELENTRY_29(29, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(51, bnil())))))))))))), SrcTable(Cp1253()))
  | LABELENTRY_30(30, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(51, bnil())))))), SrcTable(Cp1253()))
  | LABELENTRY_31(31, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(51, bnil())))))))), SrcTable(Cp1253()))
  | LABELENTRY_32(32, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(52, bnil())))))))))))), SrcTable(Cp1254()))
  | LABELENTRY_33(33, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(52, bnil())))))), SrcTable(Cp1254()))
  | LABELENTRY_34(34, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(52, bnil())))))))), SrcTable(Cp1254()))
  | LABELENTRY_35(35, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(57, bnil())))))))))), SrcTable(Cp1254()))
  | LABELENTRY_36(36, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(57, bnil()))))))))), SrcTable(Cp1254()))
  | LABELENTRY_37(37, bcons(108, bcons(97, bcons(116, bcons(105, bcons(110, bcons(53, bnil())))))), SrcTable(Cp1254()))
  | LABELENTRY_38(38, bcons(108, bcons(53, bnil())), SrcTable(Cp1254()))
  | LABELENTRY_39(39, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(53, bnil())))))))))))), SrcTable(Cp1255()))
  | LABELENTRY_40(40, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(53, bnil())))))), SrcTable(Cp1255()))
  | LABELENTRY_41(41, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(53, bnil())))))))), SrcTable(Cp1255()))
  | LABELENTRY_42(42, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(54, bnil())))))))))))), SrcTable(Cp1256()))
  | LABELENTRY_43(43, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(54, bnil())))))), SrcTable(Cp1256()))
  | LABELENTRY_44(44, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(54, bnil())))))))), SrcTable(Cp1256()))
  | LABELENTRY_45(45, bcons(119, bcons(105, bcons(110, bcons(100, bcons(111, bcons(119, bcons(115, bcons(45, bcons(49, bcons(50, bcons(53, bcons(55, bnil())))))))))))), SrcTable(Cp1257()))
  | LABELENTRY_46(46, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(55, bnil())))))), SrcTable(Cp1257()))
  | LABELENTRY_47(47, bcons(120, bcons(45, bcons(99, bcons(112, bcons(49, bcons(50, bcons(53, bcons(55, bnil())))))))), SrcTable(Cp1257()))
  | LABELENTRY_48(48, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(50, bnil())))))))))), SrcTable(Iso88592()))
  | LABELENTRY_49(49, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(50, bnil()))))))))), SrcTable(Iso88592()))
  | LABELENTRY_50(50, bcons(105, bcons(115, bcons(111, bcons(95, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(50, bnil())))))))))), SrcTable(Iso88592()))
  | LABELENTRY_51(51, bcons(108, bcons(97, bcons(116, bcons(105, bcons(110, bcons(50, bnil())))))), SrcTable(Iso88592()))
  | LABELENTRY_52(52, bcons(108, bcons(50, bnil())), SrcTable(Iso88592()))
  | LABELENTRY_53(53, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(53, bnil())))))))))), SrcTable(Iso88595()))
  | LABELENTRY_54(54, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(53, bnil()))))))))), SrcTable(Iso88595()))
  | LABELENTRY_55(55, bcons(105, bcons(115, bcons(111, bcons(95, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(53, bnil())))))))))), SrcTable(Iso88595()))
  | LABELENTRY_56(56, bcons(99, bcons(121, bcons(114, bcons(105, bcons(108, bcons(108, bcons(105, bcons(99, bnil())))))))), SrcTable(Iso88595()))
  | LABELENTRY_57(57, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(55, bnil())))))))))), SrcTable(Iso88597()))
  | LABELENTRY_58(58, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(55, bnil()))))))))), SrcTable(Iso88597()))
  | LABELENTRY_59(59, bcons(105, bcons(115, bcons(111, bcons(95, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(55, bnil())))))))))), SrcTable(Iso88597()))
  | LABELENTRY_60(60, bcons(103, bcons(114, bcons(101, bcons(101, bcons(107, bnil()))))), SrcTable(Iso88597()))
  | LABELENTRY_61(61, bcons(103, bcons(114, bcons(101, bcons(101, bcons(107, bcons(56, bnil())))))), SrcTable(Iso88597()))
  | LABELENTRY_62(62, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(56, bnil())))))))))), SrcTable(Iso88598()))
  | LABELENTRY_63(63, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(56, bnil()))))))))), SrcTable(Iso88598()))
  | LABELENTRY_64(64, bcons(105, bcons(115, bcons(111, bcons(95, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(56, bnil())))))))))), SrcTable(Iso88598()))
  | LABELENTRY_65(65, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(56, bcons(45, bcons(105, bnil())))))))))))), SrcTable(Iso88598()))
  | LABELENTRY_66(66, bcons(104, bcons(101, bcons(98, bcons(114, bcons(101, bcons(119, bnil())))))), SrcTable(Iso88598()))
  | LABELENTRY_67(67, bcons(108, bcons(111, bcons(103, bcons(105, bcons(99, bcons(97, bcons(108, bnil()))))))), SrcTable(Iso88598()))
  | LABELENTRY_68(68, bcons(118, bcons(105, bcons(115, bcons(117, bcons(97, bcons(108, bnil())))))), SrcTable(Iso88598()))
  | LABELENTRY_69(69, bcons(105, bcons(115, bcons(111, bcons(45, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(49, bcons(53, bnil()))))))))))), SrcTable(Iso885915()))
  | LABELENTRY_70(70, bcons(105, bcons(115, bcons(111, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(49, bcons(53, bnil())))))))))), SrcTable(Iso885915()))
  | LABELENTRY_71(71, bcons(105, bcons(115, bcons(111, bcons(95, bcons(56, bcons(56, bcons(53, bcons(57, bcons(45, bcons(49, bcons(53, bnil()))))))))))), SrcTable(Iso885915()))
  | LABELENTRY_72(72, bcons(108, bcons(97, bcons(116, bcons(105, bcons(110, bcons(57, bnil())))))), SrcTable(Iso885915()))
  | LABELENTRY_73(73, bcons(108, bcons(57, bnil())), SrcTable(Iso885915()))
  | LABELENTRY_74(74, bcons(107, bcons(111, bcons(105, bcons(56, bcons(45, bcons(114, bnil())))))), SrcTable(Koi8r()))
  | LABELENTRY_75(75, bcons(107, bcons(111, bcons(105, bcons(56, bnil())))), SrcTable(Koi8r()))
  | LABELENTRY_76(76, bcons(107, bcons(111, bcons(105, bcons(56, bcons(95, bcons(114, bnil())))))), SrcTable(Koi8r()))

dataprop LOWER(int, int) =
  | {raw:int | raw < 65 || 90 < raw} LOWER_same(raw, raw)
  | {raw:int | 65 <= raw; raw <= 90} LOWER_shift(raw, raw + 32)

dataprop LOWERED(cells, int, bytes) =
  | {cells:cells}{from:nat} LOWERED_nil(cells, from, bnil())
  | {cells:cells}{from:nat}{raw,low:int}{rest:bytes}
    LOWERED_cons(cells, from, bcons(low, rest)) of (NTH(cells, from, raw), LOWER(raw, low), LOWERED(cells, from + 1, rest))

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

dataprop LABELIS(cells, int, int, bytes) =
  | {cells:cells}{from,count:nat}{label:bytes}
    LABELIS_mk(cells, from, count, label) of (LOWERED(cells, from, label), LEN(label, count))

dataprop DIFFFROM(cells, int, bytes) =
  | {cells:cells}{from:nat}{raw,low,expected:int | low != expected}{rest:bytes}
    DIFFFROM_head(cells, from, bcons(expected, rest)) of (NTH(cells, from, raw), LOWER(raw, low))
  | {cells:cells}{from:nat}{raw,expected:int}{rest:bytes}
    DIFFFROM_tail(cells, from, bcons(expected, rest)) of (NTH(cells, from, raw), LOWER(raw, expected), DIFFFROM(cells, from + 1, rest))

dataprop LABELDIFF(cells, int, int, bytes) =
  | {cells:cells}{from,count:nat}{label:bytes}{label_count:nat | label_count != count}
    LABELDIFF_length(cells, from, count, label) of LEN(label, label_count)
  | {cells:cells}{from,count:nat}{label:bytes}
    LABELDIFF_byte(cells, from, count, label) of DIFFFROM(cells, from, label)

dataprop ALLDIFF(cells, int, int, int) =
  | {cells:cells}{from,count:nat} ALLDIFF_none(cells, from, count, 0)
  | {cells:cells}{from,count:nat}{tried:nat | tried < LABEL_COUNT}{label:bytes}{source:tsrc}
    ALLDIFF_more(cells, from, count, tried + 1) of (ALLDIFF(cells, from, count, tried), LABELENTRY(tried, label, source), LABELDIFF(cells, from, count, label))

dataprop LABELSRC(cells, int, int, tsrc) =
  | {cells:cells}{from,count:nat}{index:nat | index < LABEL_COUNT}{label:bytes}{source:tsrc}
    LABELSRC_listed(cells, from, count, source) of (LABELENTRY(index, label, source), LABELIS(cells, from, count, label))
  | {cells:cells}{from,count:nat}
    LABELSRC_unsupported(cells, from, count, SrcUnsupported()) of ALLDIFF(cells, from, count, LABEL_COUNT)

dataprop DECLARED(cells, int, tsrc) =
  | {cells:cells}{i,equals_at:nat | i <= equals_at}{value:int | value != 61}
    DECLARED_no_equals(cells, i, SrcUtf8()) of (SKIP(cells, i, equals_at), BYTEAT(cells, equals_at, value))
  | {cells:cells}{i,equals_at,quote_at:nat | i <= equals_at; equals_at + 1 <= quote_at}{quote:int | quote != 34; quote != 39}
    DECLARED_no_quote(cells, i, SrcUtf8()) of (SKIP(cells, i, equals_at), NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at), BYTEAT(cells, quote_at, quote))
  | {cells:cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{quote:int | quote == 34 || quote == 39}
    DECLARED_unclosed(cells, i, SrcUtf8()) of (SKIP(cells, i, equals_at), NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at),
      NTH(cells, quote_at, quote), NOQUOTE(cells, quote, quote_at + 1, label_end), CLEN(cells, label_end))
  | {cells:cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{quote:int | quote == 34 || quote == 39}{source:tsrc}
    DECLARED_label(cells, i, source) of (SKIP(cells, i, equals_at), NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at),
      NTH(cells, quote_at, quote), NOQUOTE(cells, quote, quote_at + 1, label_end), NTH(cells, label_end, quote),
      LABELSRC(cells, quote_at + 1, label_end - (quote_at + 1), source))

prfn probe_i_le_equals_at {cells:cells}{i,equals_at,quote_at,label_end:nat | i <= (equals_at) + 1; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{quote:int | quote == 34 || quote == 39}{source:tsrc} (premise1: SKIP(cells, i, equals_at), premise2: NTH(cells, equals_at, 61), premise3: SKIP(cells, equals_at + 1, quote_at), premise4: NTH(cells, quote_at, quote), premise5: NOQUOTE(cells, quote, quote_at + 1, label_end), premise6: NTH(cells, label_end, quote), premise7: LABELSRC(cells, quote_at + 1, label_end - (quote_at + 1), source)): DECLARED(cells, i, source) = DECLARED_label{cells}{i,equals_at,quote_at,label_end}{quote}{source}(premise1, premise2, premise3, premise4, premise5, premise6, premise7)
