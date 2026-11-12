#target native

#include "share/atspre_staload.hats"

#use array as A
#use env as E
#use file as F
#use result as R

staload "churn.sats"

(* review-churn MANIFEST: the share of pull requests with a new finding (review churn) *)

val g_failed = ref<bool>(false)
val g_counted = ref<int>(0)
val g_with_new = ref<int>(0)

(* The pull requests the share is taken over *)
val LIMIT = 20

datavtype whole_file =
  | {la,l:agz}{m:pos}{n:nat | n < m}
    whole_ok of ($A.arena(byte, la, m, m, 1), $A.arrx(byte, l, m, la), int m, int n)
  | whole_err of $F.io_error

(* The file just opened, read whole in an arena of its own; a file of any size (review churn) *)
fn whole_of_open (opened: $R.result($F.fd, $F.io_error)): whole_file =
  case+ opened of
  | ~$R.err(e) => whole_err(e)
  | ~$R.ok(fd) =>
    (case+ $F.fd_size(fd) of
    | ~$R.err(e) => let
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in whole_err(e) end
    | ~$R.ok(z) =>
      if z >= 268435455 then let
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in whole_err($F.FileTooLarge()) end
      else (case+ $A.arena_create<byte>(z + 1) of
      | ~$A.arena_none() => let
          val () = $R.discard<int><$F.io_error>($F.file_close(fd))
        in whole_err($F.OutOfMemory()) end
      | ~$A.arena_some(ar) => let
          val p = $A.arena_alloc<byte>(ar, z + 1)
          val read_result = $F.file_read(fd, p, z + 1)
          val () = $R.discard<int><$F.io_error>($F.file_close(fd))
        in
          case+ read_result of
          | ~$R.ok(k) =>
            if k = z then whole_ok(ar, p, z + 1, z)
            else let
              val () = $A.arena_return<byte>(ar, p)
              val () = $A.arena_destroy<byte>(ar)
            in whole_err($F.DeviceError()) end
          | ~$R.err(e) => let
              val () = $A.arena_return<byte>(ar, p)
              val () = $A.arena_destroy<byte>(ar)
            in whole_err(e) end
        end))

fn whole_free {la,l:agz}{m:pos}
  (ar: $A.arena(byte, la, m, m, 1), p: $A.arrx(byte, l, m, la)): void = let
  val () = $A.arena_return<byte>(ar, p)
in $A.arena_destroy<byte>(ar) end

(* src[a + i, b) copied to dst[i..] *)
fun copy_path {ls:agz}{ns:pos}{b:nat | b <= ns}{a:nat | a <= b}{ld:agz}{nd:pos | b - a < nd}{i:nat | i <= b - a} .<b - a - i>.
  (src: !$A.borrow(byte, ls, ns), a: int a, b: int b, dst: !$A.arr(byte, ld, nd), i: int i): void =
  if a + i >= b then ()
  else let
    val () = $A.set<byte>(dst, i, int2byte0(peek(src, a + i, b)))
  in copy_path(src, a, b, dst, i + 1) end

(* The file named by src[a, b), read whole *)
fn read_path {l:agz}{n:pos}{b:nat | b <= n}{a:nat | a < b}
  (src: !$A.borrow(byte, l, n), a: int a, b: int b): whole_file =
  if b - a >= 4096 then whole_err($F.InvalidFilename())
  else let
    val dst = $A.alloc<byte>(b - a + 1)
    val () = copy_path(src, a, b, dst, 0)
    val @(fz, pbv) = $A.freeze<byte>(dst)
    val w = whole_of_open($F.file_open(pbv, b - a + 1, $F.ReadOnly(), $F.OpenExisting(), 0))
    val () = $A.drop<byte>(fz, pbv)
    val () = $A.free<byte>($A.thaw<byte>(fz))
  in w end

fn say_unreadable {l:agz}{n:pos}{b:nat | b <= n}{a:nat | a < b}
  (src: !$A.borrow(byte, l, n), a: int a, b: int b): void = let
  val () = (!g_failed := true)
  val () = print! ("error: cannot read ")
  val () = churn_print(src, a, b)
in print_newline() end

(* The kind of the review in the file named by mbv[a, b), 0 when unreadable (review churn) *)
fn kind_at {l:agz}{n:pos}{b:nat | b <= n}{a:nat | a < b}
  (mbv: !$A.borrow(byte, l, n), a: int a, b: int b): int =
  (case+ read_path(mbv, a, b) of
  | ~whole_err(_) => let val () = say_unreadable(mbv, a, b) in 0 end
  | ~whole_ok(ar, piece, size, len) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val k = churn_kind(bv, len)
      val () = $A.drop<byte>(fz, bv)
      val () = whole_free(ar, $A.thaw<byte>(fz))
    in k end)

fn line_kind {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p < m}
  (mbv: !$A.borrow(byte, l, n), m: int m, p: int p): int = let
  val @(a, b) = churn_line_path(mbv, m, p)
in
  if a < 0 then 0 else kind_at(mbv, a, b)
end

(* Whether the anchor rbv[a, b) is in the file named by mbv[pa, pb) *)
fn file_has {l:agz}{n:pos}{pb:nat | pb <= n}{pa:nat | pa < pb}{lr:agz}{rn:pos}{b:nat | b <= rn}{a:nat | a <= b}
  (mbv: !$A.borrow(byte, l, n), pa: int pa, pb: int pb, rbv: !$A.borrow(byte, lr, rn), a: int a, b: int b): bool =
  (case+ read_path(mbv, pa, pb) of
  | ~whole_err(_) => let val () = say_unreadable(mbv, pa, pb) in false end
  | ~whole_ok(ar, piece, size, len) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val hit = churn_contains_ci(bv, len, rbv, a, b)
      val () = $A.drop<byte>(fz, bv)
      val () = whole_free(ar, $A.thaw<byte>(fz))
    in hit end)

(* Whether the anchor rbv[a, b) is in a review of the manifest lines e up to r (review churn) *)
fun seen_before {l:agz}{n:pos}{m:nat | m <= n}{e:nat | e <= m}{lr:agz}{rn:pos}{b:nat | b <= rn}{a:nat | a <= b} .<m - e>.
  (mbv: !$A.borrow(byte, l, n), m: int m, e: int e, r: int, rbv: !$A.borrow(byte, lr, rn), a: int a, b: int b): bool =
  if e >= r then false
  else if e >= m then false
  else let
    val @(pa, pb) = churn_line_path(mbv, m, e)
    val nx = next_line(mbv, e, m)
    val hit = (if pa < 0 then false else file_has(mbv, pa, pb, rbv, a, b)): bool
  in
    if hit then true else seen_before(mbv, m, nx, r, rbv, a, b)
  end

(* The findings of round k in no review of the lines e up to r, said and counted (review churn) *)
fun new_lines {l:agz}{n:pos}{m:nat | m <= n}{e:nat | e <= m}{lr:agz}{rn:pos}{rm:nat | rm <= rn}{p:nat | p <= rm} .<rm - p>.
  (mbv: !$A.borrow(byte, l, n), m: int m, e: int e, r: int, rbv: !$A.borrow(byte, lr, rn), rm: int rm, p: int p, k: int, acc: int): int =
  if p >= rm then acc
  else let
    val @(a, b) = churn_anchor(rbv, rm, p)
    val nx = next_line(rbv, p, rm)
  in
    if a < 0 then new_lines(mbv, m, e, r, rbv, rm, nx, k, acc)
    else if seen_before(mbv, m, e, r, rbv, a, b) then new_lines(mbv, m, e, r, rbv, rm, nx, k, acc)
    else let
      val () = print! ("  round ", k, ": new `")
      val () = churn_print(rbv, a, b)
      val () = println! ("`")
    in new_lines(mbv, m, e, r, rbv, rm, nx, k, acc + 1) end
  end

(* The findings new in the review at line r against those from gp up to it (review churn) *)
fn review_new {l:agz}{n:pos}{m:nat | m <= n}{gp:nat | gp <= m}{r:nat | r < m}
  (mbv: !$A.borrow(byte, l, n), m: int m, gp: int gp, r: int r, k: int): int = let
  val @(a, b) = churn_line_path(mbv, m, r)
in
  if a < 0 then 0
  else (case+ read_path(mbv, a, b) of
  | ~whole_err(_) => let val () = say_unreadable(mbv, a, b) in 0 end
  | ~whole_ok(ar, piece, size, len) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val c = new_lines(mbv, m, gp, r, bv, len, 0, k, 0)
      val () = $A.drop<byte>(fz, bv)
      val () = whole_free(ar, $A.thaw<byte>(fz))
    in c end)
end

(* The blocking reviews of the lines from p up to ge *)
fun count_blocking {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (mbv: !$A.borrow(byte, l, n), m: int m, p: int p, ge: int, acc: int): int =
  if p >= ge then acc
  else if p >= m then acc
  else let
    val nx = next_line(mbv, p, m)
    val blocks = (line_kind(mbv, m, p) = 2): bool
  in
    count_blocking(mbv, m, nx, ge, (if blocks then acc + 1 else acc))
  end

(* The findings new in the later blocking rounds of a pull request, from line gp (review churn) *)
fun later_rounds {l:agz}{n:pos}{m:nat | m <= n}{gp:nat | gp <= m}{p:nat | p <= m} .<m - p>.
  (mbv: !$A.borrow(byte, l, n), m: int m, gp: int gp, p: int p, ge: int, seen: int, fresh: int): int =
  if p >= ge then fresh
  else if p >= m then fresh
  else let
    val nx = next_line(mbv, p, m)
  in
    if line_kind(mbv, m, p) = 2 then
      (if seen >= 1 then later_rounds(mbv, m, gp, nx, ge, seen + 1, fresh + review_new(mbv, m, gp, p, seen + 1))
      else later_rounds(mbv, m, gp, nx, ge, 1, fresh))
    else later_rounds(mbv, m, gp, nx, ge, seen, fresh)
  end

(* The first line from p whose number is another than key, or m *)
fun group_end {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (mbv: !$A.borrow(byte, l, n), m: int m, p: int p, key: int): [r:nat | p <= r; r <= m] int r =
  if p >= m then p
  else let
    val k = churn_line_key(mbv, m, p)
  in
    if k >= 0 && k <> key then p else group_end(mbv, m, next_line(mbv, p, m), key)
  end

(* The pull requests from the line at p, until LIMIT had two blocking rounds (review churn) *)
fun groups {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (mbv: !$A.borrow(byte, l, n), m: int m, p: int p): void =
  if p >= m then ()
  else if !g_counted >= LIMIT then ()
  else let
    val key = churn_line_key(mbv, m, p)
    val nx = next_line(mbv, p, m)
  in
    if key < 0 then groups(mbv, m, nx)
    else let
      val ge = group_end(mbv, m, nx, key)
      val blocking = count_blocking(mbv, m, p, ge, 0)
    in
      if blocking < 2 then groups(mbv, m, ge)
      else let
        val () = (!g_counted := !g_counted + 1)
        val () = println! ("quire#", key, ": ", blocking, " blocking rounds")
        val fresh = later_rounds(mbv, m, p, p, ge, 0, 0)
        val () = (if fresh > 0 then (!g_with_new := !g_with_new + 1) else ())
        val () = println! ("quire#", key, ": ", fresh, " findings new in a later round")
      in groups(mbv, m, ge) end
    end
  end

fn report (): void = let
  val t = !g_counted
  val s = !g_with_new
in
  if t = 0 then println! ("share: no pull request with two blocking rounds")
  else println! ("share: ", s, " of ", t, " pull requests with two blocking rounds had a finding new in a later round (", s * 100 / t, "%)")
end

fn run_manifest {l:agz}{n:pos}{b:nat | b <= n}{a:nat | a < b}
  (src: !$A.borrow(byte, l, n), a: int a, b: int b): void =
  (case+ read_path(src, a, b) of
  | ~whole_err(_) => let val () = say_unreadable(src, a, b) in () end
  | ~whole_ok(ar, piece, size, len) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val () = groups(bv, len, 0)
      val () = $A.drop<byte>(fz, bv)
    in whole_free(ar, $A.thaw<byte>(fz)) end)

(* The first NUL of the 4096 bytes of arguments at or after p, or k (review churn) *)
fun nul_at {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.borrow(byte, l, 4096), p: int p, k: int): [r:nat | p <= r; r <= 4096] int r =
  if p >= 4096 then p
  else if p >= k then p
  else if peek(buf, p, 4096) = 0 then p
  else nul_at(buf, p + 1, k)

fn usage (): void = let
  val () = (!g_failed := true)
  val () = println! ("usage: review-churn MANIFEST")
  val () = println! ("MANIFEST: a line `<pull request number> <review file>` for each review comment, newest pull request first,")
  val () = println! ("the reviews of a pull request in the order written; a review file is one comment body, from")
  val () = println! ("gh api repos/bats-lang/quire/issues/comments/<id> --jq .body; a number has at most 9 digits, a path under 4096 bytes.")
  val () = println! ("A review opens with Independent review or Adversarial review and blocks on 'changes needed'.")
  val () = println! ("A finding is a list item line (1. or a. or - or *) with an inline code span; its anchor is the first span.")
  val () = println! ("A finding of a blocking round after the first is new when its anchor is in no earlier review of the pull request.")
  val () = println! ("Of the first 20 pull requests with two blocking rounds, the share with a new finding is printed.")
in () end

implement main0 () = let
  val buf = $A.alloc<byte>(4096)
  val got = $E.args_read(buf, 4096)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val () = (case+ got of
    | ~$R.some(k) => let
        val first = nul_at(bv, 0, k)
      in
        if first >= 4095 then usage()
        else let
          val a = first + 1
          val z = nul_at(bv, a, k)
        in
          if a >= z then usage()
          else if z >= k then usage()
          else run_manifest(bv, a, z)
        end
      end
    | ~$R.none() => usage())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
  val () = report()
in
  if !g_failed then exit(1) else ()
end
