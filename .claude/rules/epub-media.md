---
paths:
  - src/narration.bats
  - src/overlay*.bats
  - src/font_obfuscation.bats
  - src/dataurl.bats
  - src/reader.bats
  - src/reader_rules.bats
  - e2e/narration*
  - e2e/media*
  - e2e/math*
  - e2e/fonts*
  - e2e/drm*
  - e2e/w3c*
---

# Narration, media, fonts and MathML

## Narration (issue #133)

A book with EPUB 3 Media Overlays (EPUB 3.3 §9) is read aloud by its own recorded
narration. Overlays are found once, with the chapters (`_spine_build`): a spine
item's manifest `media-overlay` names the SMIL's item, whose entry is kept in the
chapter (`chapter_overlay`, `src/book.bats`); `_book_narrated` is set when any
chapter has one, and the bottom bar's `narration-controls` then take the place of
reading aloud by speech (`_narration_offered`).

`src/overlay.bats` reads a SMIL's bytes (the format alone): its body, seq and par
elements flattened in order into clips, each a par with an audio element (one
without is passed over; `media:duration` is not read). Each clip is 32 bytes of a
`clip_table(count)`, at most 32768: begin and end (clock values as H.4 has them; no
clipEnd is the audio's end; a value over 2^31 - 1 ms makes the clip invalid), its
audio entry (relative to the SMIL's directory), its text's fragment, whether it is
skippable (it or a seq around it is a footnote, endnote or pagebreak) and the clip
after the innermost escapable table, list, figure or aside. **A clip's index is
proven below the table's count**, so reading past the table does not type-check
(`tests/static/reject/clip-past-end`).

As a narrated chapter is rendered, an element with an id is matched against the next
8 clips not yet matched (`_clip_match` in `src/reader.bats`): a match keeps the
element's first content node and the one after its last. An unmatched clip still
plays, with nothing marked and no page turned. Then the SMIL is freed and only the
clip table is kept (`reader_clips_take`).

`src/narration.bats` plays it on one `<audio id="narration">` (`ui_audio`) for the
whole book, so the permission a click gave it holds clip after clip. The state is
`Idle`, `Playing(clip, generation)` or `Paused(clip, at)`, each clip proven below
the table's count. The source is a blob URL of the audio entry, made on the JS side
from the book's file when it is stored (`book_blob_url`), or from its bytes inflated
into a piece when deflated; revoked when the entry changes and when the book is
closed.

* Each clip plays from its begin (one that follows the last in the same audio plays
  on without a seek), marked with `mark_range` kind 5 (`::highlight(bats-mark-5)`),
  and its page shown when its text is not on the page. A timer at its end, by the
  speed, checks `audio_time` and moves on within 20 ms of the end, else sets itself
  again; `timeupdate` is a backstop and `ended` covers an audio file shorter than
  its clip. A generation number drops the timers and answers of earlier clips.
* At a chapter's end it goes on into the next chapter with an overlay
  (`book_narrated_after`). A page the reader shows (`reader_page_shown`) moves it
  there (from the first clip on or after the page, or the chapter's first); so does a
  tap on text a clip reads.
* A play the browser refuses, or an `error`, stops it ("This narration cannot be
  played"); a `pause` it did not ask for (a headset, a call) leaves it paused.
* Controls: Read aloud (`aria-pressed`), Previous phrase, Next phrase, and inside an
  escapable structure Skip table. The reading settings' Read aloud tab offers, for a
  narrated book, its speed (0.5x to 2x in quarters, `audio_rate`, pitch kept) and
  whether page numbers and notes are read (Skip by default). Both are the device's
  own, kept outside the settings record as `_ruby` is (in its storage after an "N");
  the reset's Undo and the backup (`narrationSpeed` in hundredths,
  `narrationReadsNotes`) cover them.

## Audio and video play (#424, #419)

An `audio` or `video` element of a chapter is made as such with the browser's own
controls (dom's `Controls`) and never autoplay; its `src`, or the first `<source>`'s,
is the book's entry, given as a picture's bytes are (`images_cons`; bridge's
`set_image_src` makes a blob and sets the element's `src`). A `<source>`'s file goes
to the media element itself, since a `<source>` given its src after insertion is not
looked at again (no `type` selection). The file passes through wasm memory (a piece of
the chapter's arena), heavy for a long video (a range blob on the JS side, as
narration's audio is, is not done). Leaving the chapter removes the element.
`e2e/media.spec.js` plays a real mp3.

## Links out, scrolled books, fonts and speech for the W3C suite (#419)

* **A link out of the book asks first** (`_external_ask` in `src/reader.bats`;
  `pub-external-links`: "should open it ... after the reader's consent"): the page's
  `<a>` does not carry the address; it is kept (`links_cons`, up to 2048 bytes) and a
  tap or Enter opens the note overlay (`LNote`) with "This link leaves the book. It
  goes to <address>." and a real link, Open link (`footnote-open`, `rel=noopener`,
  `target=_blank`), that the reader taps (a tap is never blocked, a script's
  `window.open` after an answer is).
* **A book can ask to be scrolled** (`opf_scroll_preferred`, `flow_scrolled`,
  `_book_scrolls` in `src/settings.bats`): the setting Pages | Scroll starts as
  `ByBook` (a new install's default; a kept setting keeps its value): a book whose OPF
  has `rendition:flow` `scrolled-doc` or `scrolled-continuous`, or `rendition:layout`
  `roll`, is scrolled until the reader chooses Pages or Scroll. The reader's choice
  outranks the book's (EPUB RS 3.3 lets a reading system override). A roll is not one
  strip across documents: each scrolls and the next follows at its end. Reset puts
  `ByBook` back.
* **A SMIL with no audio is read by speech** (`_overlay_load`; `mol-tts_single`): a
  chapter whose SMIL has no clip (`overlay_count` is 0) does not offer the narration's
  controls, so reading aloud by speech takes its place and reads from the page; the
  SMIL's order and `media:active-class` are not used.
* **The package's fonts are the Book font**: Font: Book loads the first font of the
  manifest (`font/otf`, `ttf`, `woff`, `woff2`) for the text, since the book's CSS is
  dropped (#411).

## Obfuscated fonts are undone (#410)

EPUB OCF 3.3 §4.1.2 requires a reading system to undo the two font obfuscations.
`src/font_obfuscation.bats` undoes both (xor is its own inverse, `font_unmask`):
IDPF's (the key is the SHA-1 of the package's unique identifier with its white space
taken out, 20 bytes, xored with the font's first 1040 bytes going round; `idpf_key`)
and Adobe's (`http://ns.adobe.com/pdf/enc#RC`: the 16 bytes of the identifier's UUID,
after its last colon and without its dashes, xored with the first 1024; `adobe_key`).
SHA-1 is the sha256 package's `sha1_digest`. The unique identifier is the
`dc:identifier` the package's `unique-identifier` names (`opf_unique_identifier`,
copied by `_font_locate`). Which algorithm a font has comes from
`META-INF/encryption.xml`, read as the font is loaded (`_font_cipher_find`,
`font_cipher`: `FontNotListed`, `FontObfuscatedIdpf`, `FontObfuscatedAdobe`,
`FontCipherOther`). The font is unmasked in its piece before its blob URL is made
(`_font_blob`), every time the book is opened.

* **It degrades where it is**, with no banner (the text is set in the reader's own
  face): an algorithm Quire has no client for, an identifier that makes no key (an
  Adobe one that is no UUID, none, over 4096 bytes), a font the archive lacks, noise,
  one shorter than the masked bytes. Readium's streamer, Calibre and foliate-js undo
  both the same way and do not draw what they cannot decode.
* **A font encrypted in an unknown algorithm does not make the book DRM** (#410 against
  #427): `_encrypted_data_unknown` (`src/epub_xml.bats`) passes an `EncryptedData`
  whose `CipherReference` is a font file (`.otf`, `.ttf`, `.ttc`, `.woff`, `.woff2`)
  whatever its algorithm. Anything else under an unknown algorithm is refused
  (`e2e/drm.spec.js`), and a namespace of ADEPT, LCP or Kobo anywhere in the file still is.
* `e2e/fonts.spec.js` plays `e2e/font-books.js` (the font
  `e2e/marker-font.ttf` has one glyph no system has, U+E000, so the page's face is told by
  measuring it; `create-epub.js` has `obfuscatedFonts`, `identifier`, `manifestOnly` and
  `obfuscateFont`, written apart from the app's).

## Settled by research, kept failing (#419)

A must test stays failing only where two documented behaviours conflict, and the one
that wins is named:

* **The book's CSS is not applied (#411) wins over the suite's CSS tests**
  (`cnt-svg-css-inclusion`, `nav-spine_in-spine-hidden-toc-css`, `lay-pp-xhtml-icb`,
  `_multi`, `_multi_declarations`, `_repeated-in-meta`, `_units`, the deprecated
  `lay-fxl-*` copies, `css-epub-*`, `mol-css`, `ocf-font_obfuscation`): each asks that a
  rule of the book's style sheet change how its text is drawn. The colours are the app's,
  each text and ground pair proven 4.5:1 in each theme (`SURF`), and the size, margins,
  spacing, Justify, Hyphenation and Font settings are the reader's; a book's colours or
  sizes would break the proofs and the settings. Readium CSS (Thorium) keeps publisher
  styles by default; Quire is the other way round, on purpose.
* **The package's language and direction win over `pkg-lang_but_not_content` and
  `pkg-dir_but_not_content`** (`epub-format.md`).
* **`pub-cmt-jxl`** is the platform's: Chromium and Android's WebView have no JPEG XL
  decoder. A fallback is followed when the manifest names one (`pub-foreign_image`).
* **`pkg-manifest-unlisted-resource`**: `epub-format.md`.
* **Deprecated tests** (`fxl-spine-overrides_duplicate`, `lay-fxl-orientation-landscape`):
  the suite files them as deprecated; `rendition:orientation` is not read.

## SVG is drawn as a picture of its own (#419)

An inline `<svg>` of a page, and an SVG content document, is drawn by `_render_node`
(`src/reader.bats`) as an `<img>` whose source is a blob of the element's own bytes
(`images_svg`, `_load_svg`): a copy from `<svg` to its closing tag (`_svg_end`, which
passes over comments, CDATA, processing instructions and quoted values), with the
`xmlns` and `xmlns:xlink` of its page written in when it names none. Its children are
still made, so every content node keeps its number (search, read aloud and the overlays
count the same tree), but an `<img>` shows none of them; the text is kept in the page,
hidden. An svg that holds an `<image>` (a cover page's usual form, drawn by the `<image>`
path), is over 512 KiB, or is inside another, is not drawn this way.

**Why a picture, not the element in the page**: other readers show a content document in
a frame of its own, so an svg's `<style>`, ids and links are scoped to it. Quire's page is
one DOM shared with its own interface, so a `<style>` in an svg would be a global rule
that could restyle the interface (what the proofs of `style.bats` and #411 are about), an
id could collide with the app's, and a book may never put a script-capable element there.
A sandboxed image has the same drawing, its own style scope and no script or outside load.
Cost: the page CSS does not reach it (`cnt-svg-css-inclusion`), its links and scripts do
nothing, it uses system fonts, and a dark theme does not recolour its black text (the image
dimming setting applies).

## MathML is the browser's (#419, #408)

A `math` element is made element for element in the MathML namespace (`_math_add`,
`_math_attrs`: dom's `add_math_element` and `set_math_attr`, bridge's `createElementNS`),
so the browser sets the equation and its accessibility tree has the MathML (Quire sets no
`role`, `aria-hidden` or `aria-label`). The elements are MathML Core's presentation ones;
`maction` and `annotation-xml` are refused, as are any colour or background attribute (the
theme's text colour keeps the proven contrast) and any link or handler. A refused element
makes none and its children go to its parent; elements and texts take content-node numbers
as everywhere. A token's (`mi`, `mn`, `mo`, `ms`, `mtext`) text is its own; text elsewhere
in a math element is not shown. Every reader on a browser engine leaves MathML to the
engine; Chromium has MathML Core since 109. `e2e/math-native.spec.js`,
`math-fallbacks.spec.js`, `math-layout.spec.js` (books in `e2e/math-books.js`).

* **A display equation scrolls along its width only**: `math[display=block]` is
  `overflow: auto hidden` with .3em above and below, since Chromium counts a glyph's font
  box in the scrollable overflow (a 4px vertical scroll otherwise).
* **`dir` is the page's own attribute** (`_math_attrs`; dom's allow-list has none): an
  equation is set left to right even in a Hebrew book unless it says `dir="rtl"`.
* **`alttext` and `altimg` are not shown when MathML is drawn**: EPUB 3.3 and MathML make
  them the fallback for a system that cannot draw the math; the engine draws it, so they
  would show every equation twice. `altimg` is not an allowed attribute of dom's.
* **Unsupported and broken MathML degrades where it stands**: an element dom does not make
  (`maction`, `annotation-xml`, `mstack`, `mglyph`) makes none and its children go to its
  parent; a broken tree is drawn by the browser as it can (the broken book is not valid
  MathML, so the book is invalid by `RSC-005`, which its entry lists).

## Equations as pictures (#408)

A picture of an equation (a PNG, an inline `<svg>`, an `<img src="x.svg">`) is a picture of
text. Two decisions:

* **A picture grows with the reader's text size.** Quire drops the book's CSS, so the `em`
  heights publishers give such pictures are not there. A picture is its own size at the
  default text size (18px) and is scaled by the reader's size from there (`--image-zoom`, in
  thousandths, written by `_apply_type` in `src/settings.bats`; CSS `zoom` in
  `.caf:not(.fixed) img`, a fixed page being fitted by its own box), kept to the column's
  width and the page's height (divided by the zoom). It is the same for any picture, since
  Quire cannot tell an equation from a diagram. Amazon's guidelines size inline images in em
  so they scale with the text; Readium CSS has no setting that scales pictures.
* **Black ink on no ground is drawn on paper in the dark themes.** Black on the Dark, Night
  and Grey grounds was 1.1 to 1.8 to one (WCAG asks 3:1 for graphics). Readium CSS offers an
  `invert` flag; Quire cannot tell a picture with no ground from a photograph that inversion
  would ruin, so a picture is drawn on white in those themes (`tint`, no new colour role). The
  cost is a white rectangle behind a transparent picture of white ink; the image dimming
  setting dims it.
