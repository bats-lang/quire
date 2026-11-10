(* churn_tests -- the tests of review-churn's pure parts: the kind of a comment, the anchor of a finding and which findings are new (keyword: review churn tests) *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B

staload "churn.sats"

(* A text of at most 4096 bytes as a frozen array: its borrow, the freezer and the length are used by the tests below *)
fn kind_of {s:nat | s < 4096} (text: string s): int = let
  var b = $B.create()
  val () = $B.bput(b, text)
  val @(arr, len) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  val k = churn_kind(bv, len)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in k end

(* The findings of round and how many are new against earlier: anchored * 100 + new *)
fn counts_of {s,t:nat | s < 4096; t < 4096} (round: string s, earlier: string t): int = let
  var b = $B.create()
  val () = $B.bput(b, round)
  val @(ra, rlen) = $B.to_arr(b)
  var c = $B.create()
  val () = $B.bput(c, earlier)
  val @(ea, elen) = $B.to_arr(c)
  val @(rfz, rbv) = $A.freeze<byte>(ra)
  val @(efz, ebv) = $A.freeze<byte>(ea)
  val @(anchored, fresh) = churn_count(rbv, rlen, ebv, elen)
  val () = $A.drop<byte>(rfz, rbv)
  val () = $A.drop<byte>(efz, ebv)
  val () = $A.free<byte>($A.thaw<byte>(rfz))
  val () = $A.free<byte>($A.thaw<byte>(efz))
in anchored * 100 + fresh end

$UNITTEST.run begin

fn test_kind_header_blocks (): bool =
  kind_of("Independent review (a separate reviewer agent) of head abc: changes needed\n\nbody\n") = 2

fn test_kind_header_approves (): bool =
  kind_of("Independent review of head abc: approved\n") = 1

fn test_kind_verdict_line_blocks (): bool =
  kind_of("## Adversarial review\n\n1. x\n\nVerdict: changes needed\nReviewed: abc\n") = 2

fn test_kind_verdict_line_approves (): bool =
  kind_of("## Adversarial review\n\nVerdict: approved\nReviewed: abc\n") = 1

fn test_kind_blocking_wins_over_approval (): bool =
  kind_of("Adversarial review of head abc: approved\n\nVerdict: changes needed\n") = 2

fn test_kind_review_with_no_verdict (): bool =
  kind_of("Adversarial review\n\nnothing decided\n") = 3

fn test_kind_other_comment_is_no_review (): bool =
  kind_of("CI is green, the review is next\n") = 0

fn test_kind_verdict_of_a_non_review_is_ignored (): bool =
  kind_of("Thanks.\n\nVerdict: changes needed\n") = 0

fn test_kind_empty_comment (): bool = kind_of("\n\n") = 0

fn test_count_new_anchor (): bool =
  counts_of("1. The `frozenPids` line freezes more.\n", "1. The `mojoWindow` anchors on the last message.\n") = 101

fn test_count_old_anchor_any_case (): bool =
  counts_of("a. The `MojoWindow` anchors again.\n", "the `mojoWindow` anchors on the last message\n") = 100

fn test_count_item_forms (): bool =
  counts_of("1. `a1`\n  - `a2`\n* `a3`\n b) `a4`\n12. `a5`\n", "nothing\n") = 505

fn test_count_not_items (): bool =
  counts_of("A sentence with `a1` in it.\n1.`a2`\n1234. `a3`\n-`a4`\nab. `a5`\n", "nothing\n") = 0

fn test_count_line_without_span_is_no_finding (): bool =
  counts_of("1. Make each comment one line.\n2. An open `span\n3. An empty `` span\n", "nothing\n") = 0

fn test_count_first_span_is_the_anchor (): bool =
  counts_of("1. In `seen` the `unseen` is used.\n", "the seen one\n") = 100

fn test_count_second_span_is_not_the_anchor (): bool =
  counts_of("1. In `unseen` the `seen` is used.\n", "the seen one\n") = 101

fn test_count_empty_round (): bool = counts_of("\n", "x\n") = 0

end
