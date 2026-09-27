(* book -- the open book: its file, and where its OPF is inside it *)

#include "share/atspre_staload.hats"

(* The open book's file: its handle and size (at most 1 MiB); its OPF's
   compressed data [opf_data, opf_data + opf_size) and compression
   method; the OPF's name [opf_name, opf_name + opf_name_len) in the
   central directory. The regions are proven inside the file, so the
   reader uses them with no check. *)
#pub datatype open_book =
  | {n:pos | n <= 1048576}{d:nat}{s:pos | d + s <= n}{m:int | m == 0 || m == 8}{no,nl:nat | no + nl <= n}
    OpenBook of (int, int n, int d, int s, int m, int no, int nl)
  | NoBook of ()

#pub fun book_get(): open_book

#pub fun book_set(b: open_book): void

val _book = ref<open_book>(NoBook())

implement book_get() = !_book

implement book_set(b) = !_book := b

(* The reader's font size in px: 8 to 48, the range the A- and A+
   buttons step through. *)
#pub typedef font_px = [s:int | 8 <= s; s <= 48] int s

#pub fun font_get(): font_px

#pub fun font_set(s: font_px): void

val _font = ref<font_px>(16)

implement font_get() = !_font

implement font_set(s) = !_font := s

(* Where the reader is: page p of the chapter's t pages (at least one),
   in chapter c (counted from 1; 0 before one loads) of the book's tc. *)
#pub datatype reading =
  | {t:pos}{p:nat | p < t}{c,tc:nat}
    Reading of (int p, int t, int c, int tc)

#pub fun reading_get(): reading

#pub fun reading_set(r: reading): void

val _reading = ref<reading>(Reading(0, 1, 0, 0))

implement reading_get() = !_reading

implement reading_set(r) = !_reading := r

(* The DOM document's next node id, kept between diffs: the document is
   opened for each diff and gives it back when destroyed *)
#pub fun next_nid_get(): int

#pub fun next_nid_set(nid: int): void

val _next_nid = ref<int>(0)

implement next_nid_get() = !_next_nid

implement next_nid_set(nid) = !_next_nid := nid
