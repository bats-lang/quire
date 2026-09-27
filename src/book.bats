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
