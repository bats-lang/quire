(* outside_chain -- a book's bytes from outside the program to the renderer, with OUTSIDE_READ (keyword: outside-chain).
   The fetch of a catalogue body, and a decompressed entry, are read as cells of outside bytes and given
   to text_proved's take_text_outside_sum. Additive: the old chain stays beside it until its dependents move. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

staload "book.sats"
staload "text_proved.sats"
staload BO = "wasm.bats-packages.dev/bridge/src/outside.sats"

(* An entry's text from the browser's decompression: its cells are outside bytes, with their proofs (keyword: outside-chain) *)
#pub datavtype outside_text =
  | {cs:$A.cells} OutsideText of (outside_taken(cs))
  | OutsideTextNone of ()

(* The entry's decompressed bytes read as outside cells, checked against the sum the archive states, and taken as text; none
   when the decompression failed, the entry is empty or over 1 MiB, or the sum is not the entry's *)
#pub fn take_outside_text_sum (inflated: $BO.decompressed_outside, sum: entry_sum): outside_text

implement take_outside_text_sum (inflated, sum) =
  case+ inflated of
  | ~$BO.DecompressFailedOutside() => let
      val () = (case+ sum of ~SumKnown(_, _) => () | ~SumUnknown() => ())
    in OutsideTextNone() end
  | ~$BO.DecompressedOutside(blob) => let
      val n = $BO.blob_len_outside(blob)
    in
      if n <= 0 then let
        val () = $BO.blob_free_outside(blob)
        val () = (case+ sum of ~SumKnown(_, _) => () | ~SumUnknown() => ())
      in OutsideTextNone() end
      else if n > 1048576 then let
        val () = $BO.blob_free_outside(blob)
        val () = (case+ sum of ~SumKnown(_, _) => () | ~SumUnknown() => ())
      in OutsideTextNone() end
      else let
        val out = $A.alloc<byte>(n)
        val (read, length, lent | cells) = $BO.blob_read_outside(blob, out, n)
        val () = $BO.blob_free_outside(blob)
      in
        case+ sum of
        | ~SumUnknown() => let
            val () = $A.free<byte>($A.barr_to_arrx(lent | cells))
          in OutsideTextNone() end
        | ~SumKnown(want_high, want_low) => let
            val @(back, taken) = take_text_outside_sum(read, length | cells, n, want_high, want_low)
            val () = $A.free<byte>($A.barr_to_arrx(lent | back))
          in OutsideText(taken) end
      end
    end

(* An outside text not wanted *)
#pub fn outside_text_free (text: outside_text): void

implement outside_text_free (text) =
  case+ text of
  | ~OutsideText(taken) => outside_taken_free(taken)
  | ~OutsideTextNone() => ()

(* A fetched body (a catalogue's book) held by JS as a file of outside bytes: the blob read as cells, which file_store_outside
   takes with their proof; none when it is empty or over 1 MiB *)
#pub datavtype outside_file =
  | {n:pos} OutsideFile of ($BO.infile_outside(n))
  | OutsideFileNone of ()

#pub fn outside_file_of_fetched (got: $BO.fetched_outside): outside_file

implement outside_file_of_fetched (got) =
  case+ got of
  | ~$BO.NotFetchedOutside() => OutsideFileNone()
  | ~$BO.FetchedOutside(blob) => let
      val n = $BO.blob_len_outside(blob)
    in
      if n <= 0 then let val () = $BO.blob_free_outside(blob) in OutsideFileNone() end
      else if n > 1048576 then let val () = $BO.blob_free_outside(blob) in OutsideFileNone() end
      else let
        val out = $A.alloc<byte>(n)
        val (read, length, lent | cells) = $BO.blob_read_outside(blob, out, n)
        val () = $BO.blob_free_outside(blob)
        val @(frozen, view) = $A.barr_freeze(cells)
        val file = $BO.file_store_outside(read | view, n)
        val () = $A.cborrow_drop(frozen, view)
        val () = $A.free<byte>($A.barr_to_arrx(lent | $A.barr_thaw(frozen)))
      in OutsideFile(file) end
    end

(* The file given back *)
#pub fn outside_file_free (file: outside_file): void

implement outside_file_free (file) =
  case+ file of
  | ~OutsideFile(held) => $BO.file_close_outside(held)
  | ~OutsideFileNone() => ()

end (* #target wasm *)
