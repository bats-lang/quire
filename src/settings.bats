(* settings -- typography and theme, applied and saved on every change *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S

staload "ui.sats"
staload "undo.sats"
staload "book.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload MEDIA = "wasm.bats-packages.dev/bridge/src/media.sats"

(* The settings, each in its range:
   size      font size in px, 12 to 32
   lh        line spacing in tenths, 12 to 24
   margin    page margins, 0 (narrow) to 4 (wide)
   font      0 Literata, 1 Inter, 2 the book's own
   theme     0 auto (the system's), 1 light, 2 sepia, 3 dark *)
#pub typedef set_size = [v:int | 12 <= v; v <= 32] int v
#pub typedef set_lh = [v:int | 12 <= v; v <= 24] int v
#pub typedef set_margin = [v:nat | v <= 4] int v
#pub typedef set_font = [v:nat | v <= 2] int v
#pub typedef set_theme = [v:nat | v <= 3] int v

typedef settings = @{
  size = set_size, lh = set_lh, margin = set_margin, font = set_font, theme = set_theme
}

val _set = ref<settings>(@{ size = 18, lh = 16, margin = 2, font = 0, theme = 0 })
(* Whether the system asks for a dark theme (for auto) *)
val _sys_dark = ref<bool>(false)

#pub fn set_size_get (): set_size
implement set_size_get () = (!_set).size
#pub fn set_lh_get (): set_lh
implement set_lh_get () = (!_set).lh
#pub fn set_margin_get (): set_margin
implement set_margin_get () = (!_set).margin
#pub fn set_font_get (): set_font
implement set_font_get () = (!_set).font
#pub fn set_theme_get (): set_theme
implement set_theme_get () = (!_set).theme

(* ============================================================
   Applying
   ============================================================ *)

(* s's bytes at buf[p, p + sn) *)
fun _put {l:agz}{n:pos}{sn:nat}{p:nat | p + sn <= n}{i:nat | i <= sn} .<sn - i>.
  (buf: !$A.arr(byte, l, n), p: int p, s: string sn, sl: int sn, i: int i): int(p + sn) =
  if i >= sl then p + sl
  else let
    val () = $A.set<byte>(buf, p + i, $A.int2byte($AR.byte_of_char(string_get_at(s, i))))
  in _put(buf, p, s, sl, i + 1) end

fn _puts {l:agz}{n:pos}{sn:nat}{p:nat | p + sn <= n}
  (buf: !$A.arr(byte, l, n), p: int p, s: string sn): int(p + sn) =
  _put(buf, p, s, g1u2i(string1_length(s)), 0)

fn _margin_px (m: set_margin): [v:nat | v <= 64] int v =
  if m = 0 then 8 else if m = 1 then 16 else if m = 2 then 24 else if m = 3 then 40 else 64

fn _put_font {l:agz}{p:nat | p + 30 <= 256}
  (buf: !$A.arr(byte, l, 256), p: int p, f: set_font): [q:nat | q <= p + 30] int q =
  if f = 0 then _puts(buf, p, "Literata,Georgia,serif")
  else if f = 1 then _puts(buf, p, "Inter,system-ui,sans-serif")
  else _puts(buf, p, "var(--bookfont,Georgia),serif")

(* The reader's typography as CSS, in style element qdyn *)
fn _apply_type (): void = let
  val x = !_set
  val buf = $A.alloc<byte>(256)
  val off = _puts(buf, 0, ".caf{font-size:")
  val off = $S.int_to_str(buf, off, 256, x.size)
  val off = _puts(buf, off, "px;line-height:")
  (* tenths as a decimal: 16 -> 1.6 *)
  val off = $S.int_to_str(buf, off, 256, x.lh / 10)
  val off = _puts(buf, off, ".")
  val off = $S.int_to_str(buf, off, 256, $AR.band_g1($AR.low_byte(x.lh - (x.lh / 10) * 10), 15))
  val off = _puts(buf, off, ";font-family:")
  val off = _put_font(buf, off, x.font)
  val off = _puts(buf, off, "}.caf>*{padding-left:")
  val off = $S.int_to_str(buf, off, 256, _margin_px(x.margin))
  val off = _puts(buf, off, "px;padding-right:")
  val off = $S.int_to_str(buf, off, 256, _margin_px(x.margin))
  val off = _puts(buf, off, "px}")
in ui_text_buf("qdyn", buf, off) end

(* Whether the theme shown is dark, light or sepia: the root's class *)
fn _apply_theme (): void = let
  val t = (!_set).theme
  val t = (if t = 0 then (if !_sys_dark then 3 else 1) else t): set_theme
in
  if t = 3 then ui_attr("bats-root", AClass, "app th-dark")
  else if t = 2 then ui_attr("bats-root", AClass, "app th-sepia")
  else ui_attr("bats-root", AClass, "app th-light")
end

fn _pressed {ni:pos | ni < 256} (id: string ni, on: bool): void =
  if on then ui_attr(id, APressed, "true") else ui_attr(id, APressed, "false")

(* The settings panel's controls, showing the settings *)
fn _show_controls (): void = let
  val x = !_set
  val buf = $A.alloc<byte>(32)
  val off = $S.int_to_str(buf, 0, 32, x.size)
  val () = ui_text_buf("qfsv", buf, off)
  val buf = $A.alloc<byte>(32)
  val off = $S.int_to_str(buf, 0, 32, x.lh / 10)
  val off = _puts(buf, off, ".")
  val off = $S.int_to_str(buf, off, 32, $AR.band_g1($AR.low_byte(x.lh - (x.lh / 10) * 10), 15))
  val () = ui_text_buf("qlhv", buf, off)
  val buf = $A.alloc<byte>(32)
  val off = $S.int_to_str(buf, 0, 32, x.margin + 1)
  val () = ui_text_buf("qmgv", buf, off)
  val () = _pressed("qff0", x.font = 0)
  val () = _pressed("qff1", x.font = 1)
  val () = _pressed("qff2", x.font = 2)
  val () = _pressed("qth0", x.theme = 0)
  val () = _pressed("qth1", x.theme = 1)
  val () = _pressed("qth2", x.theme = 2)
in _pressed("qth3", x.theme = 3) end

(* ============================================================
   Storage: key "set"
   ============================================================ *)

(* "S1", then size, lh, margin, font, theme and the library's sort
   order, a byte each *)
fn _save (sort: int): void = let
  val x = !_set
  val buf = $A.alloc<byte>(8)
  val () = $A.write_byte(buf, 0, 83)
  val () = $A.write_byte(buf, 1, 49)
  val () = $A.write_byte(buf, 2, x.size)
  val () = $A.write_byte(buf, 3, x.lh)
  val () = $A.write_byte(buf, 4, x.margin)
  val () = $A.write_byte(buf, 5, x.font)
  val () = $A.write_byte(buf, 6, x.theme)
  val () = $A.write_byte(buf, 7, $AR.low_byte(sort))
  val @(bf, bb) = $A.freeze<byte>(buf)
  val ka = $A.alloc<byte>(3)
  val () = $A.write_byte(ka, 0, 115) (* s *)
  val () = $A.write_byte(ka, 1, 101) (* e *)
  val () = $A.write_byte(ka, 2, 116) (* t *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val () = $P.discard<Int>($IDB.idb_put(kb, 3, bb, 8))
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
  val () = $A.drop<byte>(bf, bb)
in $A.free<byte>($A.thaw<byte>(bf)) end

(* The panel's sliders, made again at the settings' values (after they
   are loaded, reset or restored; not while one is being moved) *)
#pub fn set_sliders (): void

implement set_sliders () = let
  val x = !_set
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.size)
  val () = ui_range("qsr1", "qsl1", "Size", "qfsr", "12", "32", "qfsv", a, k)
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.lh)
  val () = ui_range("qsr2", "qsl2", "Line spacing", "qlhr", "12", "24", "qlhv", a, k)
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.margin)
  val () = ui_range("qsr3", "qsl3", "Margins", "qmgr", "0", "4", "qmgv", a, k)
in _show_controls() end

(* Applies the settings (and shows them in the panel), then saves them
   with the library's sort order *)
#pub fn set_apply (sort: int): void

implement set_apply (sort) = let
  val () = _apply_type()
  val () = _apply_theme()
  val () = _show_controls()
in _save(sort) end

(* Applies the settings without saving them *)
#pub fn set_show (): void

implement set_show () = let
  val () = _apply_type()
  val () = _apply_theme()
in set_sliders() end

#pub fn set_size_set (v: set_size): void
implement set_size_set (v) = let val x = !_set in !_set := @{ size = v, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme } end
#pub fn set_lh_set (v: set_lh): void
implement set_lh_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = v, margin = x.margin, font = x.font, theme = x.theme } end
#pub fn set_margin_set (v: set_margin): void
implement set_margin_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = v, font = x.font, theme = x.theme } end
#pub fn set_font_set (v: set_font): void
implement set_font_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = v, theme = x.theme } end
#pub fn set_theme_set (v: set_theme): void
implement set_theme_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = v } end

(* The defaults. Private: the settings go back to them only by
   set_reset, which offers the ones they replace back *)
fn _reset (): void = !_set := @{ size = 18, lh = 16, margin = 2, font = 0, theme = 0 }

(* Puts the defaults back at once, then runs after (which applies
   them); what it returns puts the settings they replaced back, and
   runs after again *)
#pub fn set_reset_undoable (after: () -<cloref1> void): () -<cloref1> void
implement set_reset_undoable (after) = let
  val before = !_set
  val () = _reset()
  val () = after()
in lam () => let val () = !_set := before in after() end end

(* The same, offering Undo *)
#pub fn set_reset (after: () -<cloref1> void): void
implement set_reset (after) =
  undo_offer("Settings reset", set_reset_undoable(after), lam () => ())

(* A byte stored by an earlier run, as a value in [lo, hi]: checked here,
   once; d when it is out of range *)
fn _in {lo,hi,d:int | lo <= d; d <= hi} (v: [v:int] int v, lo: int lo, hi: int hi, d: int d)
  : [r:int | lo <= r; r <= hi] int r =
  if v < lo then d else if v > hi then d else v

(* Reads the settings stored under "set" and applies them (without
   saving); the promise resolves with the sort order stored with them *)
#pub fn set_load (): $P.promise(int, $P.Chained)

implement set_load () = let
  val ka = $A.alloc<byte>(3)
  val () = $A.write_byte(ka, 0, 115)
  val () = $A.write_byte(ka, 1, 101)
  val () = $A.write_byte(ka, 2, 116)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_get(kb, 3)
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
  (* The system's dark mode, for the auto theme, and its changes *)
  val q = $A.alloc<byte>(30)
  val () = $A.write_text(q, 0, $A.text_lit("(prefers-color-scheme: dark)"), 28)
  val @(qf, qb) = $A.freeze<byte>(q)
  val @(q1, q2) = $A.borrow_split<byte>(qf, qb, 28)
  val () = !_sys_dark := ($MEDIA.match_media(q1, 28) > 0)
  val () = $MEDIA.listen_media(q1, 28, 60, lam(m) => let
      val () = !_sys_dark := (m > 0)
      val () = _apply_theme()
    in 0 end)
  val qb = $A.borrow_join<byte>(qf, q1, q2)
  val () = $A.drop<byte>(qf, qb)
  val () = $A.free<byte>($A.thaw<byte>(qf))
in
  $P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_blob(h) of
    | ~NoBlobBytes() => let val () = set_show() in $P.ret<int>(0) end
    | ~BlobBytes(b, n) =>
      if n < 8 then let
        val () = $A.free<byte>(b)
        val () = set_show()
      in $P.ret<int>(0) end
      else let
        val size = _in($AR.low_byte(byte2int0($A.get<byte>(b, 2))), 12, 32, 18)
        val lh = _in($AR.low_byte(byte2int0($A.get<byte>(b, 3))), 12, 24, 16)
        val margin = _in($AR.low_byte(byte2int0($A.get<byte>(b, 4))), 0, 4, 2)
        val font = _in($AR.low_byte(byte2int0($A.get<byte>(b, 5))), 0, 2, 0)
        val theme = _in($AR.low_byte(byte2int0($A.get<byte>(b, 6))), 0, 3, 0)
        val sort = _in($AR.low_byte(byte2int0($A.get<byte>(b, 7))), 0, 3, 0)
        val () = $A.free<byte>(b)
        val () = !_set := @{ size = size, lh = lh, margin = margin, font = font, theme = theme }
        val () = set_show()
      in $P.ret<int>(sort) end)
end

end (* #target wasm *)
