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
   font      0 Literata, 1 Inter, 2 the book's own, 3 Atkinson
             Hyperlegible
   theme     0 auto (the system's), 1 light, 2 sepia, 3 dark, 4 night, 5 grey
   align     0 ragged, 1 justified
   hyph      0 no hyphenation, 1 hyphenated
   ps        space after a paragraph in tenths of an em, 0 to 20
   ls        letter spacing in hundredths of an em, 0 to 12
   ws        word spacing in hundredths of an em, 0 to 16
   dim       0 a book's images as they are, 1 dimmed in the dark themes
   taps      what a tap on the page does, where: 0 sides (the left
             quarter back, the right on, between them the bars), 1
             forward (the top band the bars, the left quarter back,
             anywhere else on), 2 one hand (the top third back, the
             bottom third on, between them the bars)
   vol       0 the volume keys are the volume's, 1 they turn the page
   flow      0 pages (turned across), 1 scrolled (down the chapter)
   rd        the footer's readout: 0 pages left in the chapter, 1 the
             page of the chapter's pages, 2 the chapter of the book's,
             3 the time left in the chapter, 4 in the book
             (where the browser gives them to the page)
   (the spacings reach what WCAG 1.4.12 asks a page to take: 2em
   after a paragraph, .12em between letters, .16em between words) *)
#pub typedef set_size = [v:int | 12 <= v; v <= 32] int v
#pub typedef set_lh = [v:int | 12 <= v; v <= 24] int v
#pub typedef set_margin = [v:nat | v <= 4] int v
#pub typedef set_font = [v:nat | v <= 3] int v
#pub typedef set_theme = [v:nat | v <= 5] int v
#pub typedef set_align = [v:nat | v <= 1] int v
#pub typedef set_hyph = [v:nat | v <= 1] int v
#pub typedef set_ps = [v:nat | v <= 20] int v
#pub typedef set_ls = [v:nat | v <= 12] int v
#pub typedef set_ws = [v:nat | v <= 16] int v
#pub typedef set_dim = [v:nat | v <= 1] int v
#pub typedef set_taps = [v:nat | v <= 2] int v
#pub typedef set_vol = [v:nat | v <= 1] int v
#pub typedef set_rd = [v:nat | v <= 4] int v
#pub typedef set_flow = [v:nat | v <= 1] int v

typedef settings = @{
  size = set_size, lh = set_lh, margin = set_margin, font = set_font, theme = set_theme,
  align = set_align, hyph = set_hyph, ps = set_ps, ls = set_ls, ws = set_ws, dim = set_dim, taps = set_taps, vol = set_vol, rd = set_rd, flow = set_flow
}

(* The defaults: text ragged (WCAG 1.4.8: not justified) and
   hyphenated, the paragraph spacing the page always had, and images
   dimmed in the dark theme *)
fn _defaults (): settings =
  @{ size = 18, lh = 16, margin = 2, font = 0, theme = 0, align = 0, hyph = 1, ps = 8, ls = 0, ws = 0, dim = 1, taps = 0, vol = 0, rd = 0, flow = 0 }

val _set = ref<settings>(_defaults())
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
#pub fn set_align_get (): set_align
implement set_align_get () = (!_set).align
#pub fn set_hyph_get (): set_hyph
implement set_hyph_get () = (!_set).hyph
#pub fn set_ps_get (): set_ps
implement set_ps_get () = (!_set).ps
#pub fn set_ls_get (): set_ls
implement set_ls_get () = (!_set).ls
#pub fn set_ws_get (): set_ws
implement set_ws_get () = (!_set).ws
#pub fn set_dim_get (): set_dim
implement set_dim_get () = (!_set).dim
#pub fn set_taps_get (): set_taps
implement set_taps_get () = (!_set).taps
#pub fn set_vol_get (): set_vol
implement set_vol_get () = (!_set).vol
#pub fn set_rd_get (): set_rd
implement set_rd_get () = (!_set).rd
#pub fn set_flow_get (): set_flow
implement set_flow_get () = (!_set).flow

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

fn _put_font {l:agz}{p:nat | p + 34 <= 512}
  (buf: !$A.arr(byte, l, 512), p: int p, f: set_font): [q:nat | q <= p + 34] int q =
  if f = 0 then _puts(buf, p, "Literata,Georgia,serif")
  else if f = 1 then _puts(buf, p, "Inter,system-ui,sans-serif")
  else if f = 3 then _puts(buf, p, "'Atkinson Hyperlegible',sans-serif")
  else _puts(buf, p, "var(--bookfont,Georgia),serif")

(* v tenths as a decimal at buf[p, r): 16 -> "1.6" *)
fn _put_tenths {l:agz}{n:pos}{p:nat | p + 23 <= n}{v:nat}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n, v: int v): [r:nat | r <= p + 23] int r = let
  val off = $S.int_to_str(buf, p, n, v / 10)
  val off = _puts(buf, off, ".")
in $S.int_to_str(buf, off, n, $AR.band_g1($AR.low_byte(v - (v / 10) * 10), 15)) end

(* v hundredths (under 100) as a decimal at buf[p, r): 5 -> "0.05" *)
fn _put_hundredths {l:agz}{n:pos}{p:nat | p + 15 <= n}{v:nat | v < 100}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n, v: int v): [r:nat | r <= p + 15] int r = let
  val off = _puts(buf, p, "0.")
  val off = (if v < 10 then _puts(buf, off, "0") else off): [o:nat | o <= p + 3] int o
in $S.int_to_str(buf, off, n, v) end

fn _put_align {l:agz}{p:nat | p + 7 <= 512}
  (buf: !$A.arr(byte, l, 512), p: int p, a: set_align): [r:nat | r <= p + 7] int r =
  if a = 1 then _puts(buf, p, "justify") else _puts(buf, p, "start")

fn _put_hyph {l:agz}{p:nat | p + 6 <= 512}
  (buf: !$A.arr(byte, l, 512), p: int p, h: set_hyph): [r:nat | r <= p + 6] int r =
  if h = 1 then _puts(buf, p, "auto") else _puts(buf, p, "manual")

fn _put_dim {l:agz}{p:nat | p + 80 <= 512}
  (buf: !$A.arr(byte, l, 512), p: int p, d: set_dim): [r:nat | r <= p + 80] int r =
  if d = 1 then _puts(buf, p, ".th-dark .caf img,.th-night .caf img,.th-grey .caf img{filter:brightness(.8)}") else p

fn _put_flow {l:agz}{p:nat | p + 48 <= 512}
  (buf: !$A.arr(byte, l, 512), p: int p, f: set_flow): [r:nat | r <= p + 48] int r =
  if f = 1 then _puts(buf, p, ".caf{overflow:hidden auto;column-width:auto}") else p

(* The reader's typography as CSS, in style element style-type *)
fn _apply_type (): void = let
  val x = !_set
  val buf = $A.alloc<byte>(512)
  val off = _puts(buf, 0, ".caf{font-size:")
  val off = $S.int_to_str(buf, off, 512, x.size)
  val off = _puts(buf, off, "px;line-height:")
  val off = _put_tenths(buf, off, 512, x.lh)
  val off = _puts(buf, off, ";font-family:")
  val off = _put_font(buf, off, x.font)
  val off = _puts(buf, off, ";letter-spacing:")
  val off = _put_hundredths(buf, off, 512, x.ls)
  val off = _puts(buf, off, "em;word-spacing:")
  val off = _put_hundredths(buf, off, 512, x.ws)
  val off = _puts(buf, off, "em}.caf>*{padding-left:")
  val off = $S.int_to_str(buf, off, 512, _margin_px(x.margin))
  val off = _puts(buf, off, "px;padding-right:")
  val off = $S.int_to_str(buf, off, 512, _margin_px(x.margin))
  val off = _puts(buf, off, "px}.caf p{text-align:")
  val off = _put_align(buf, off, x.align)
  val off = _puts(buf, off, ";hyphens:")
  val off = _put_hyph(buf, off, x.hyph)
  val off = _puts(buf, off, ";margin-bottom:")
  val off = _put_tenths(buf, off, 512, x.ps)
  val off = _puts(buf, off, "em}")
  (* a bright picture glares on the dark theme's ground *)
  val off = _put_dim(buf, off, x.dim)
  (* scrolled: the chapter down the page, not in columns across *)
  val off = _put_flow(buf, off, x.flow)
in ui_text_buf("style-type", buf, off) end

(* Whether the theme shown is dark, light or sepia: the root's class *)
fn _apply_theme (): void = let
  val t = (!_set).theme
  val t = (if t = 0 then (if !_sys_dark then 3 else 1) else t): set_theme
in
  if t = 5 then ui_attr("bats-root", AClass, "app th-grey")
  else if t = 4 then ui_attr("bats-root", AClass, "app th-night")
  else if t = 3 then ui_attr("bats-root", AClass, "app th-dark")
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
  val () = ui_text_buf("size-value", buf, off)
  val buf = $A.alloc<byte>(32)
  val off = $S.int_to_str(buf, 0, 32, x.lh / 10)
  val off = _puts(buf, off, ".")
  val off = $S.int_to_str(buf, off, 32, $AR.band_g1($AR.low_byte(x.lh - (x.lh / 10) * 10), 15))
  val () = ui_text_buf("line-height-value", buf, off)
  val buf = $A.alloc<byte>(32)
  val off = $S.int_to_str(buf, 0, 32, x.margin + 1)
  val () = ui_text_buf("margins-value", buf, off)
  val () = _pressed("font-literata", x.font = 0)
  val () = _pressed("font-inter", x.font = 1)
  val () = _pressed("font-book", x.font = 2)
  val () = _pressed("font-atkinson", x.font = 3)
  val () = _pressed("theme-auto", x.theme = 0)
  val () = _pressed("theme-light", x.theme = 1)
  val () = _pressed("theme-sepia", x.theme = 2)
  val () = _pressed("theme-dark", x.theme = 3)
  val () = _pressed("theme-night", x.theme = 4)
  val () = _pressed("theme-grey", x.theme = 5)
  val () = _pressed("layout-pages", x.flow = 0)
  val () = _pressed("layout-scroll", x.flow = 1)
  val () = _pressed("align-ragged", x.align = 0)
  val () = _pressed("align-justified", x.align = 1)
  val () = _pressed("hyphens-on", x.hyph = 1)
  val () = _pressed("hyphens-off", x.hyph = 0)
  val () = _pressed("dim-on", x.dim = 1)
  val () = _pressed("dim-off", x.dim = 0)
  val () = _pressed("taps-sides", x.taps = 0)
  val () = _pressed("taps-forward", x.taps = 1)
  val () = _pressed("taps-one-hand", x.taps = 2)
  val () = _pressed("volume-keys-turn", x.vol = 1)
  val () = _pressed("volume-keys-off", x.vol = 0)
  val buf = $A.alloc<byte>(32)
  val off = _put_tenths(buf, 0, 32, x.ps)
  val () = ui_text_buf("paragraph-value", buf, off)
  val buf = $A.alloc<byte>(32)
  val off = _put_hundredths(buf, 0, 32, x.ls)
  val () = ui_text_buf("letter-value", buf, off)
  val buf = $A.alloc<byte>(32)
  val off = _put_hundredths(buf, 0, 32, x.ws)
in ui_text_buf("word-value", buf, off) end

(* ============================================================
   Storage: key "set"
   ============================================================ *)

(* "S2", then size, lh, margin, font, theme, the library's sort order,
   align, hyph, ps, ls, ws, dim, taps, vol, rd and flow, a byte each. ("S1" was
   the first 8.) *)
fn _save (sort: int): void = let
  val x = !_set
  val buf = $A.alloc<byte>(18)
  val () = $A.write_byte(buf, 0, 83)
  val () = $A.write_byte(buf, 1, 50)
  val () = $A.write_byte(buf, 2, x.size)
  val () = $A.write_byte(buf, 3, x.lh)
  val () = $A.write_byte(buf, 4, x.margin)
  val () = $A.write_byte(buf, 5, x.font)
  val () = $A.write_byte(buf, 6, x.theme)
  val () = $A.write_byte(buf, 7, $AR.low_byte(sort))
  val () = $A.write_byte(buf, 8, x.align)
  val () = $A.write_byte(buf, 9, x.hyph)
  val () = $A.write_byte(buf, 10, x.ps)
  val () = $A.write_byte(buf, 11, x.ls)
  val () = $A.write_byte(buf, 12, x.ws)
  val () = $A.write_byte(buf, 13, x.dim)
  val () = $A.write_byte(buf, 14, x.taps)
  val () = $A.write_byte(buf, 15, x.vol)
  val () = $A.write_byte(buf, 16, x.rd)
  val () = $A.write_byte(buf, 17, x.flow)
  val @(bf, bb) = $A.freeze<byte>(buf)
  val ka = $A.alloc<byte>(3)
  val () = $A.write_byte(ka, 0, 115) (* s *)
  val () = $A.write_byte(ka, 1, 101) (* e *)
  val () = $A.write_byte(ka, 2, 116) (* t *)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val () = $P.discard<Int>($IDB.idb_put(kb, 3, bb, 18))
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
  val () = ui_range("size-row", "size-label", "Size", "size-range", "12", "32", "size-value", a, k)
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.lh)
  val () = ui_range("line-height-row", "line-height-label", "Line spacing", "line-height-range", "12", "24", "line-height-value", a, k)
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.margin)
  val () = ui_range("margins-row", "margins-label", "Margins", "margins-range", "0", "4", "margins-value", a, k)
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.ps)
  val () = ui_range("paragraph-row", "paragraph-label", "Paragraph spacing", "paragraph-range", "0", "20", "paragraph-value", a, k)
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.ls)
  val () = ui_range("letter-row", "letter-label", "Letter spacing", "letter-range", "0", "12", "letter-value", a, k)
  val a = $A.alloc<byte>(16)
  val k = $S.int_to_str(a, 0, 16, x.ws)
  val () = ui_range("word-row", "word-label", "Word spacing", "word-range", "0", "16", "word-value", a, k)
in _show_controls() end

(* Applies the settings (and shows them in the panel), then saves them
   with the library's sort order *)
#pub fn set_apply (sort: int): void

implement set_apply (sort) = let
  val () = _apply_type()
  val () = _apply_theme()
  val () = _show_controls()
in _save(sort) end

(* Saves the settings, with the library's sort order, as they are: for
   one that changes nothing on the page (the footer's readout) *)
#pub fn set_save (sort: int): void
implement set_save (sort) = _save(sort)

(* Applies the settings without saving them *)
#pub fn set_show (): void

implement set_show () = let
  val () = _apply_type()
  val () = _apply_theme()
in set_sliders() end

#pub fn set_size_set (v: set_size): void
implement set_size_set (v) = let val x = !_set in !_set := @{ size = v, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_lh_set (v: set_lh): void
implement set_lh_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = v, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_margin_set (v: set_margin): void
implement set_margin_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = v, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_font_set (v: set_font): void
implement set_font_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = v, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_theme_set (v: set_theme): void
implement set_theme_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = v, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_align_set (v: set_align): void
implement set_align_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = v, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_hyph_set (v: set_hyph): void
implement set_hyph_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = v, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_ps_set (v: set_ps): void
implement set_ps_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = v, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_ls_set (v: set_ls): void
implement set_ls_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = v, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_dim_set (v: set_dim): void
implement set_dim_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = v, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_taps_set (v: set_taps): void
implement set_taps_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = v, vol = x.vol, rd = x.rd, flow = x.flow } end
#pub fn set_vol_set (v: set_vol): void
implement set_vol_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = v, rd = x.rd, flow = x.flow } end
#pub fn set_ws_set (v: set_ws): void
#pub fn set_flow_set (v: set_flow): void
implement set_flow_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = v } end
#pub fn set_rd_set (v: set_rd): void
implement set_rd_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = x.ws, dim = x.dim, taps = x.taps, vol = x.vol, rd = v, flow = x.flow } end
implement set_ws_set (v) = let val x = !_set in !_set := @{ size = x.size, lh = x.lh, margin = x.margin, font = x.font, theme = x.theme, align = x.align, hyph = x.hyph, ps = x.ps, ls = x.ls, ws = v, dim = x.dim, taps = x.taps, vol = x.vol, rd = x.rd, flow = x.flow } end

(* The defaults. Private: the settings go back to them only by
   set_reset, which offers the ones they replace back *)
fn _reset (): void = !_set := _defaults()

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
        val font = _in($AR.low_byte(byte2int0($A.get<byte>(b, 5))), 0, 3, 0)
        val theme = _in($AR.low_byte(byte2int0($A.get<byte>(b, 6))), 0, 5, 0)
        val sort = _in($AR.low_byte(byte2int0($A.get<byte>(b, 7))), 0, 3, 0)
        (* "S2" has the rest; "S1" had none, and they are the defaults *)
        val s2 = (if n >= 13 then byte2int0($A.get<byte>(b, 1)) = 50 else false): bool
        val align = (if n >= 13 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 8))), 0, 1, 0) else 0) else 0): set_align
        val hyph = (if n >= 13 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 9))), 0, 1, 1) else 1) else 1): set_hyph
        val ps = (if n >= 13 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 10))), 0, 20, 8) else 8) else 8): set_ps
        val ls = (if n >= 13 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 11))), 0, 12, 0) else 0) else 0): set_ls
        val ws = (if n >= 13 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 12))), 0, 16, 0) else 0) else 0): set_ws
        val dim = (if n >= 14 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 13))), 0, 1, 1) else 1) else 1): set_dim
        val taps = (if n >= 15 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 14))), 0, 2, 0) else 0) else 0): set_taps
        val vol = (if n >= 16 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 15))), 0, 1, 0) else 0) else 0): set_vol
        val rd = (if n >= 17 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 16))), 0, 4, 0) else 0) else 0): set_rd
        val flow = (if n >= 18 then (if s2 then _in($AR.low_byte(byte2int0($A.get<byte>(b, 17))), 0, 1, 0) else 0) else 0): set_flow
        val () = $A.free<byte>(b)
        val () = !_set := @{ size = size, lh = lh, margin = margin, font = font, theme = theme,
          align = align, hyph = hyph, ps = ps, ls = ls, ws = ws, dim = dim, taps = taps, vol = vol, rd = rd, flow = flow }
        val () = set_show()
      in $P.ret<int>(sort) end)
end

end (* #target wasm *)
