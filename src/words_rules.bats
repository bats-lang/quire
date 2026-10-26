(* words_rules -- the vocabulary's rules: what a word keeps at most and the schedule of a review (keyword: vocabulary) *)

#target wasm begin

#include "share/atspre_staload.hats"

(* The most bytes of a word looked up (the selection toolbar copies as many), of a language code, and of the sentence it
   was in: kept in the two strings of a record, a head and a tail *)
#pub stadef WORD_BYTES_MOST = 64
#pub stadef LANGUAGE_BYTES_MOST = 36
#pub stadef SENTENCE_HALF_BYTES = 255
#pub stadef SENTENCE_BYTES_MOST = 510

(* The words kept at most, tombstones among them: a word looked up when this many are kept is not kept, and the reader is told *)
#pub stadef WORDS_MOST = 10000

#pub fn words_most (): int
implement words_most () = 10000

(* The rows of the words screen drawn at most: the newest, with a line saying how many are not shown *)
#pub stadef WORDS_SHOWN_MOST = 500

(* Minutes after which a deleted word's tombstone is dropped (a hundred and eighty days) *)
#pub fn words_tombstone_minutes (): int
implement words_tombstone_minutes () = 259200

(* Minutes until a word is due again after Forgot *)
#pub fn words_forgot_minutes (): int
implement words_forgot_minutes () = 5

(* Minutes until a word is due again after Got it made its streak streak: KOReader's schedule (its gotOrForgot, the
   vocabulary builder plugin): thirty minutes, twelve hours, one, two, four, seven and fifteen days, then thirty days
   times two to the streak less eight, the exponent at most six *)
#pub fn words_got_it_minutes {streak:int} (streak: int streak): int

implement words_got_it_minutes {streak} (streak) =
  if streak <= 1 then 30
  else if streak = 2 then 720
  else if streak = 3 then 1440
  else if streak = 4 then 2880
  else if streak = 5 then 5760
  else if streak = 6 then 10080
  else if streak = 7 then 21600
  else let
    fun double {times:nat} .<times>. (value: int, times: int times): int =
      if times <= 0 then value else double(value * 2, times - 1)
    val exponent = (if streak - 8 > 6 then 6 else streak - 8): [exponent:nat | exponent <= 6] int exponent
  in double(43200, exponent) end

(* The streak and the minute a word is due at after a review at minute now: Got it adds one to the streak, Forgot ends it *)
#pub fn words_review_next {streak:int} (streak: int streak, known: bool, now: int): @(int, int)
implement words_review_next {streak} (streak, known, now) =
  if known then let
    val next = (if streak < 0 then 1 else if streak >= 1000 then 1000 else streak + 1): [next:int] int next
  in @(next, now + words_got_it_minutes(next)) end
  else @(0, now + words_forgot_minutes())

end (* #target wasm *)
