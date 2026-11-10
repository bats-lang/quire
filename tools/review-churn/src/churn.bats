(* churn -- the pure parts of review-churn: which comments are reviews, which round they block, and the anchor of a finding (keyword: review churn, quire#884) *)

#include "share/atspre_staload.hats"

#use array as A

(* ------------------------------------------------------------------ *)
(* Bytes (keyword: review churn). Positions are plain ints: peek reads 0 outside the first m bytes. *)

#pub fn peek {l:agz}{n:pos}{m:nat | m <= n}{p:int}
  (src: !$A.borrow(byte, l, n), p: int p, m: int m): int

implement peek (src, p, m) =
  if p < 0 then 0
  else if p >= m then 0
  else byte2int0($A.read<byte>(src, p))

fn lower (b: int): int = if b >= 65 then (if b <= 90 then b + 32 else b) else b

fn is_digit (b: int): bool = b >= 48 && b <= 57

fn is_alpha (b: int): bool = (b >= 65 && b <= 90) || (b >= 97 && b <= 122)

fn is_blank (b: int): bool = b = 32 || b = 9

(* A byte that is blank in the text of a line or between lines: a space, a tab, a carriage return or a newline *)
fn is_space (b: int): bool = b = 32 || b = 9 || b = 13 || b = 10

(* The first newline of bv[p, m), or m *)
fun line_end {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m): [r:nat | p <= r; r <= m] int r =
  if p >= m then p
  else if peek(bv, p, m) = 10 then p
  else line_end(bv, p + 1, m)

(* The start of the line after the one at p *)
#pub fn next_line {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p < m}
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m): [r:nat | p < r; r <= m] int r

implement next_line (bv, p, m) = let
  val e = line_end(bv, p, m)
in
  if e >= m then m else e + 1
end

(* The first position at or after p of bv[0, e) that holds no space or tab, or e *)
fun skip_blank {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_blank(peek(bv, p, e)) then skip_blank(bv, p + 1, e)
  else p

(* The first position at or after p of bv[0, m) that holds no space, tab, carriage return or newline, or m *)
fun skip_space {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m): [r:nat | p <= r; r <= m] int r =
  if p >= m then p
  else if is_space(peek(bv, p, m)) then skip_space(bv, p + 1, m)
  else p

(* The first byte ch at or after p of bv[0, e), or e *)
fun char_end {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, ch: int): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if peek(bv, p, e) = ch then p
  else char_end(bv, p + 1, e, ch)

(* The end of the run of # marks that starts at p *)
fun skip_hash {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m): [r:nat | p <= r; r <= m] int r =
  if p >= m then p
  else if peek(bv, p, m) = 35 then skip_hash(bv, p + 1, m)
  else p

(* The end of the run of digits that starts at p *)
fun digits_end {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_digit(peek(bv, p, e)) then digits_end(bv, p + 1, e)
  else p

(* The end of bv[a, q) without the spaces, tabs and carriage returns at its end *)
fun trim_end {l:agz}{n:pos}{e:nat | e <= n}{q:nat | q <= e} .<q>.
  (bv: !$A.borrow(byte, l, n), a: int, q: int q, e: int e): [r:nat | r <= q] int r =
  if q <= 0 then q
  else if q <= a then q
  else if is_blank(peek(bv, q - 1, e)) || peek(bv, q - 1, e) = 13 then trim_end(bv, a, q - 1, e)
  else q

(* Whether bv[p, e) starts with the first sn bytes of s, a letter of bv read in lower case: s is in lower case *)
fun lit_ci {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn, i: int i): bool =
  if i >= sn then true
  else if p + i >= e then false
  else if lower(peek(bv, p + i, e)) = char2int0(string_get_at(s, i)) then lit_ci(bv, p, e, s, sn, i + 1)
  else false

(* The length of s as an int of that value *)
fn text_len {sn:nat} (s: string sn): int sn = g1u2i(string1_length(s))

(* ------------------------------------------------------------------ *)
(* What a comment is (keyword: review churn): a review is a comment whose first line, without its # marks, opens with
   "Independent review" or "Adversarial review"; it blocks when its first line ends with "changes needed" or a line of it is
   "Verdict: changes needed", and approves when the same is true of "approved" (blocking wins) *)

(* Whether the line bv[a, e) without its blanks at the end ends with the sn bytes of s *)
fn ends_with_ci {l:agz}{n:pos}{e:nat | e <= n}{sn:nat}
  (bv: !$A.borrow(byte, l, n), a: int, e: int e, s: string sn, sn: int sn): bool = let
  val t = trim_end(bv, a, e, e)
in
  if t - sn < a then false else lit_ci(bv, t - sn, t, s, sn, 0)
end

(* Whether the line bv[a, e) without its blanks at both ends is the sn bytes of s *)
fn line_is_ci {l:agz}{n:pos}{e:nat | e <= n}{a:nat | a <= e}{sn:nat}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e, s: string sn, sn: int sn): bool = let
  val b = skip_blank(bv, a, e)
  val t = trim_end(bv, b, e, e)
in
  if t - b <> sn then false else lit_ci(bv, b, t, s, sn, 0)
end

(* 2 when a line of bv[p, m) is "verdict: changes needed", else 1 when one is "verdict: approved", else 0: the first of them wins *)
fun verdict_line {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, found: int): int = let
  val e = line_end(bv, p, m)
  val got = (if line_is_ci(bv, p, e, "verdict: changes needed", 23) then 2
    else if line_is_ci(bv, p, e, "verdict: approved", 17) then 1 else 0): int
  val best = (if got > found then got else found): int
in
  if e >= m then best else verdict_line(bv, e + 1, m, best)
end

(* 0 for a comment that is no review, 1 for a review that approves, 2 for one that blocks, 3 for a review with no verdict *)
#pub fn churn_kind {l:agz}{n:pos}{m:nat | m <= n} (bv: !$A.borrow(byte, l, n), m: int m): int

implement churn_kind (bv, m) = let
  val s0 = skip_space(bv, 0, m)
  val s1 = skip_blank(bv, skip_hash(bv, s0, m), m)
  val e = line_end(bv, s1, m)
in
  if ~(lit_ci(bv, s1, e, "independent review", 18, 0) || lit_ci(bv, s1, e, "adversarial review", 18, 0)) then 0
  else let
    val v = verdict_line(bv, s1, m, 0)
    val head = (if ends_with_ci(bv, s1, e, "changes needed", 14) then 2
      else if ends_with_ci(bv, s1, e, "approved", 8) then 1 else 0): int
    val k = (if head > v then head else v): int
  in
    if k = 0 then 3 else k
  end
end

(* ------------------------------------------------------------------ *)
(* What a finding is: a list item line with an inline code span, anchored by the first span of the line (keyword: review churn) *)

(* x held between 0 and e *)
fn upto {x:int}{e:nat} (x: int x, e: int e): [r:nat | r <= e] int r =
  if x <= 0 then 0 else if x <= e then x else e

(* Where the text of the line bv[p, e) starts after its list marker and the blank that follows it, or ~1 when it has no marker *)
fn item_text {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:int | r <= e] int r = let
  val s = skip_blank(bv, p, e)
  val c = peek(bv, s, e)
in
  if c = 45 || c = 42 then (if is_blank(peek(bv, s + 1, e)) then upto(s + 2, e) else ~1)
  else if is_digit(c) then let
    val d = digits_end(bv, s, e)
    val k = peek(bv, d, e)
  in
    if d - s <= 3 && (k = 46 || k = 41) && is_blank(peek(bv, d + 1, e)) then upto(d + 2, e) else ~1
  end
  else if is_alpha(c) then (if (peek(bv, s + 1, e) = 46 || peek(bv, s + 1, e) = 41) && is_blank(peek(bv, s + 2, e)) then upto(s + 3, e) else ~1)
  else ~1
end

(* The first span of the item line at p: its start and its end (the text between its backticks), or ~1 and ~1 *)
#pub fn churn_anchor {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p < m}
  (bv: !$A.borrow(byte, l, n), m: int m, p: int p): [a,b:int | (a == ~1 && b == ~1) || (0 <= a && a < b && b <= m)] @(int a, int b)

implement churn_anchor (bv, m, p) = let
  val e = line_end(bv, p, m)
  val t = item_text(bv, p, e)
in
  if t < 0 then @(~1, ~1)
  else let
    val tick = char_end(bv, t, e, 96)
  in
    if tick >= e then @(~1, ~1)
    else let
      val a = tick + 1
      val close = char_end(bv, a, e, 96)
    in
      if close >= e then @(~1, ~1) else if close <= a then @(~1, ~1) else @(a, close)
    end
  end
end

(* Whether the bytes of nd[a, b) are in hay[0, hm), a letter read in lower case *)
fun same_here {lh:agz}{nh:pos}{hm:nat | hm <= nh}{ln:agz}{nn:pos}{b:nat | b <= nn}{a:nat | a <= b}{k:nat | k <= b - a}{p:int} .<b - a - k>.
  (hay: !$A.borrow(byte, lh, nh), hm: int hm, p: int p, nd: !$A.borrow(byte, ln, nn), a: int a, b: int b, k: int k): bool =
  if a + k >= b then true
  else if p + k >= hm then false
  else if lower(peek(hay, p + k, hm)) = lower(peek(nd, a + k, b)) then same_here(hay, hm, p, nd, a, b, k + 1)
  else false

fun find_here {lh:agz}{nh:pos}{hm:nat | hm <= nh}{ln:agz}{nn:pos}{b:nat | b <= nn}{a:nat | a <= b}{p:nat | p <= hm} .<hm - p>.
  (hay: !$A.borrow(byte, lh, nh), hm: int hm, p: int p, nd: !$A.borrow(byte, ln, nn), a: int a, b: int b): bool =
  if p >= hm then false
  else if same_here(hay, hm, p, nd, a, b, 0) then true
  else find_here(hay, hm, p + 1, nd, a, b)

(* Whether the bytes of nd[a, b) are in hay[0, hm), a letter read in lower case *)
#pub fn churn_contains_ci {lh:agz}{nh:pos}{hm:nat | hm <= nh}{ln:agz}{nn:pos}{b:nat | b <= nn}{a:nat | a <= b}
  (hay: !$A.borrow(byte, lh, nh), hm: int hm, nd: !$A.borrow(byte, ln, nn), a: int a, b: int b): bool

implement churn_contains_ci (hay, hm, nd, a, b) = find_here(hay, hm, 0, nd, a, b)

(* The number of item lines of round[0, rm) that have an anchor, and the number of those whose anchor is not in earlier[0, em) *)
fun count_from {lr:agz}{nr:pos}{rm:nat | rm <= nr}{le:agz}{ne:pos}{em:nat | em <= ne}{p:nat | p <= rm} .<rm - p>.
  (round: !$A.borrow(byte, lr, nr), rm: int rm, earlier: !$A.borrow(byte, le, ne), em: int em, p: int p, anchored: int, fresh: int): @(int, int) =
  if p >= rm then @(anchored, fresh)
  else let
    val @(a, b) = churn_anchor(round, rm, p)
    val nx = next_line(round, p, rm)
  in
    if a < 0 then count_from(round, rm, earlier, em, nx, anchored, fresh)
    else if churn_contains_ci(earlier, em, round, a, b) then count_from(round, rm, earlier, em, nx, anchored + 1, fresh)
    else count_from(round, rm, earlier, em, nx, anchored + 1, fresh + 1)
  end

(* The findings of the round and how many of them are new against one earlier review: @(anchored, new) *)
#pub fn churn_count {lr:agz}{nr:pos}{rm:nat | rm <= nr}{le:agz}{ne:pos}{em:nat | em <= ne}
  (round: !$A.borrow(byte, lr, nr), rm: int rm, earlier: !$A.borrow(byte, le, ne), em: int em): @(int, int)

implement churn_count (round, rm, earlier, em) = count_from(round, rm, earlier, em, 0, 0, 0)

(* bv[a, b) written to the standard output *)
#pub fn churn_print {l:agz}{n:pos}{b:nat | b <= n}{a:nat | a <= b}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b): void

implement churn_print (bv, a, b) = let
  fun loop {l:agz}{n:pos}{b:nat | b <= n}{i:nat | i <= b} .<b - i>.
    (bv: !$A.borrow(byte, l, n), i: int i, b: int b): void =
    if i >= b then ()
    else let
      val () = print_char(int2char0(peek(bv, i, b)))
    in loop(bv, i + 1, b) end
in loop(bv, a, b) end

(* ------------------------------------------------------------------ *)
(* The manifest (keyword: review churn): a line is a pull request number of at most 9 digits, blanks, and the path of one review file;
   the lines of one pull request are together, in the order the reviews were written *)

(* The number the digits from p make, at most 9 of them *)
fun number_of {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e}{k:nat | k <= 9} .<9 - k>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, k: int k, acc: int): int =
  if p >= e then acc
  else if k >= 9 then acc
  else if is_digit(peek(bv, p, e)) then number_of(bv, p + 1, e, k + 1, acc * 10 + (peek(bv, p, e) - 48))
  else acc

(* The pull request number of the manifest line at p, or ~1 for a line that does not start with one (a blank line) or whose number has over 9 digits *)
#pub fn churn_line_key {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p < m}
  (bv: !$A.borrow(byte, l, n), m: int m, p: int p): int

implement churn_line_key (bv, m, p) = let
  val e = line_end(bv, p, m)
  val s = skip_blank(bv, p, e)
  val d = digits_end(bv, s, e)
in
  if d <= s then ~1 else if d - s > 9 then ~1 else number_of(bv, s, e, 0, 0)
end

(* The path of the manifest line at p: its start and its end, or ~1 and ~1 for a line with no number or no path *)
#pub fn churn_line_path {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p < m}
  (bv: !$A.borrow(byte, l, n), m: int m, p: int p): [a,b:int | (a == ~1 && b == ~1) || (0 <= a && a < b && b <= m)] @(int a, int b)

implement churn_line_path (bv, m, p) = let
  val e = line_end(bv, p, m)
  val s = skip_blank(bv, p, e)
  val d = digits_end(bv, s, e)
in
  if d <= s then @(~1, ~1)
  else let
    val q = skip_blank(bv, d, e)
    val t = trim_end(bv, q, e, e)
  in
    if t <= q then @(~1, ~1) else @(q, t)
  end
end
