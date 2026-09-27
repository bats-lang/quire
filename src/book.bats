(* book -- the open book: its file, and where its OPF is inside it *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use result as R
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/file-input as FI

(* The open book's file (at most 1 MiB) and its size; its OPF's
   compressed data [opf_data, opf_data + opf_size) and compression
   method; the OPF's name [opf_name, opf_name + opf_name_len) in the
   central directory. The regions are proven inside the file, so the
   reader uses them with no check. *)
#pub datatype open_book =
  | {n:pos | n <= 1048576}{d:nat}{s:pos | d + s <= n}{m:int | m == 0 || m == 8}{no,nl:nat | no + nl <= n}
    OpenBook of ($FI.infile(n), int n, int d, int s, int m, int no, int nl)
  | NoBook of ()

#pub fun book_get(): open_book

(* A decompressed blob's bytes, at most 1 MiB *)
#pub datavtype blob_bytes =
  | {l:agz}{n:pos | n <= 1048576} BlobBytes of ($A.arr(byte, l, n), int n)
  | NoBlobBytes of ()

(* The blob a decompress promise resolved with, read whole and freed:
   none when decompression failed, or the result is empty or over 1 MiB
   (the book's data, checked here once) *)
#pub fn take_blob (handle: Int): blob_bytes

#pub fun book_set(b: open_book): void

val _book = ref<open_book>(NoBook())

implement book_get() = !_book

implement take_blob (handle) =
  case+ $DC.blob_claim(handle) of
  | ~$R.none() => NoBlobBytes()
  | ~$R.some(b) => let
      val n = $DC.blob_len(b)
    in
      if n <= 0 then let val () = $DC.blob_free(b) in NoBlobBytes() end
      else if n > 1048576 then let val () = $DC.blob_free(b) in NoBlobBytes() end
      else let
        val buf = $A.alloc<byte>(n)
        val () = $DC.blob_read(b, 0, buf, n)
        val () = $DC.blob_free(b)
      in BlobBytes(buf, n) end
    end

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

end (* #target wasm *)
