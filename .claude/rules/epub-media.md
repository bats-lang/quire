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

### Narration

A book with EPUB 3 Media Overlays (EPUB 3.3 §9) is read aloud by its
own recorded narration (issue #133). Its chapters' overlays are found
once, with the chapters (`_spine_build`): a spine item's manifest
`media-overlay` names the SMIL's item, whose entry is kept in the
chapter (`chapter_overlay` in `src/book.bats`); `_book_narrated` is set
when any chapter has one, and the bottom bar's `narration-controls`
then take the place of reading aloud by speech (`_narration_offered`).

`src/overlay.bats` reads a SMIL's bytes (the format alone, as
`src/stardict.bats` reads a dictionary's): its body, seq and par
elements flattened, in order, into clips, each a par with an audio
element (one without is passed over; `media:duration` is not read).
Each clip is 32 bytes of a `clip_table(count)`, at most 32768: its
begin and end (clock values as H.4 has them; no clipEnd is the audio's
end; a value over 2^31 - 1 ms makes the clip invalid), its audio entry
(found relative to the SMIL's directory when the chapter loads), its
text's fragment, whether it is skippable (it or a seq around it is a
footnote, endnote or pagebreak) and the clip after the innermost
escapable table, list, figure or aside it is in. A clip's index is
proven below the table's count, so reading past the table does not
type-check (`tests/static/reject/clip-past-end`).

As a narrated chapter is rendered, an element with an id is matched
against the next 8 clips not yet matched (`_clip_match` in
`src/reader.bats`): a match keeps the element's first content node and
the one after its last (`!_content_count` after its children, as
`_link` does). An unmatched clip still plays, with nothing marked and
no page turned. Then the SMIL is freed and only the clip table is kept,
for the narration to take (`reader_clips_take`).

`src/narration.bats` plays it on one `<audio id="narration">` (made by
`ui_audio`: no controls, `aria-hidden`; not a control, so the tag type
stays closed to them), for the whole book, so the permission a click
gave it holds clip after clip. Its state is `Idle`, `Playing(clip,
generation)` or `Paused(clip, at)`, each clip proven below the table's
count. The source is a blob URL of the audio entry, made on the JS side
from the book's file when it is stored (`book_blob_url`, file's
`file_blob_url`), or from its bytes inflated into a piece when it is
deflated; the URL is revoked when the entry changes and when the book
is closed. Each clip is played from its begin (one that follows the
last in the same audio plays on without a seek), marked with
`mark_range` kind 5 (`::highlight(bats-mark-5)`, the proven pair of
read-aloud's highlight), and its page shown when its text is not on
the page. A timer at its end, by the speed, checks `audio_time` and
moves on within 20 ms of the end, else sets itself again; the timer
reaches `_tick` through a cell (`_tick_handler`), as an event reaches
its listener, so playing on is not a recursion. `timeupdate` is a
backstop, and `ended` covers an audio file shorter than its clip. A
generation number drops the timers and answers of earlier clips. At a
chapter's end the narration goes on into the next chapter with an
overlay (`book_narrated_after`). A page the reader shows (a turn, a
jump, a new chapter; the promise `reader_page_shown` resolves) moves it
there: from the first clip on or after the page, or the chapter's
first; so does a tap on text a clip reads. A play the browser refuses,
or an `error`, stops it, and the error banner says "This narration
cannot be played"; a
`pause` it did not ask for (a headset, a call) leaves it paused. The
screen stays awake while the reader is open, so while it plays.

The controls: Read aloud (`aria-pressed`), Previous phrase, Next phrase,
and, inside an escapable structure, Skip table (list, figure, aside).
The reading settings' Read aloud tab offers, for a narrated book, its speed (0.5× to
2× in quarters, `audio_rate`, the pitch kept) and whether page numbers
and notes are read (Skip by default: skippable clips are passed over).
Both are the device's own, kept outside the settings record as `_ruby`
is; in its storage they follow the voices, after an "N" (a record
written before them has their defaults); the reset's Undo and the
backup's settings (`narrationSpeed` in hundredths, `narrationReadsNotes`)
cover them.

## Audio and video play (#424, #419)

An `audio` or `video` element of a chapter is made as such with the browser's own
controls (dom's `Controls`) and never autoplay; its `src`, or the first `<source>`'s,
is the book's entry, given as the picture's bytes are (`images_cons` on the element:
bridge's `set_image_src` makes a blob and sets the element's `src`, which is generic,
not an image's). A `<source>`'s file goes to the media element itself, since a
`<source>` given its src after insertion is not looked at again (the last of several
sources given, the first in the document, wins: no `type` selection). By research: Apple
Books plays embedded audio and video, Kobo's apps do (its e-ink devices show the
fallback), Thorium, Foliate and Calibre's viewer are browser engines that play them. The
file passes through wasm memory (a piece of the chapter's arena); a long video is
heavy there (a stored entry could instead be a range blob on the JS side, as narration's
audio is: not done). Leaving the chapter removes the element, which stops it.
`e2e/media.spec.js` plays a real mp3.

## Links out, scrolled books, fonts and speech for the W3C suite (#419)

* **A link out of the book asks first** (`_external_ask` in `src/reader.bats`;
  `pub-external-links`, `pub-external-links_consent`: "should open it in a new
  browser instance after the reader's consent"): the page's `<a>` no longer carries
  the address (it would open at once); the address is kept (`links_cons`, up to
  2048 bytes) and a tap or Enter on it opens the note overlay with "This link leaves
  the book. It goes to <address>." and a real link, Open link (`footnote-open`, `rel=noopener`,
  `target=_blank`), that the reader taps (a tap is never blocked, a script's
  `window.open` after an answer is); Close ends it. The same overlay as a note's
  (`LNote`), with Go to note hidden. By research: the suite's reports have 7 of 15 reading systems
  passing `pub-external-links` and 4 of 12 `pub-external-links_consent`, and the test is
  "should open it ... after the reader's consent"; a link that opens at once cannot be told from one the page did not mean to
  follow, and nothing is lost by one more tap.
* **A book can ask to be scrolled** (`opf_scroll_preferred`, `flow_scrolled`,
  `_book_scrolls` in `src/settings.bats`; `lay-pkg-flow-scrolled-doc`,
  `-continuous`): the setting Pages | Scroll starts as `ByBook` (the default of a new
  install; a kept setting keeps its value): a book whose OPF has `rendition:flow`
  `scrolled-doc` or `scrolled-continuous`, or `rendition:layout` `roll` (EPUB 3.4's
  draft roll layout, webtoons; `lay-roll-embedded-images*`), is scrolled until the reader
  chooses Pages or Scroll; any other is in pages. The reader's choice outranks the
  book's (EPUB RS 3.3 lets a reading system override `rendition:flow`; Readium can
  scroll any book on the reader's word). A roll is not one strip across documents:
  each document scrolls and the next follows at its end. Reset to defaults puts `ByBook` back.
* **A SMIL with no audio is read by speech** (`_overlay_load`; `mol-tts_single`,
  `mol-tts_multi`, "falls back on Text-to-Speech when no audio file is present"):
  a chapter whose SMIL has no clip to play (`overlay_count` is 0) does not offer
  the narration's controls, so reading aloud by speech (where the platform speaks)
  takes its place and reads the chapter from the page; the SMIL's order and its
  `media:active-class` highlight are not used.
* **The package's fonts are the Book font** (`cnt-css-fonts_ot`, `_tt`, `_woff`,
  `_woff2`): the book's CSS is dropped (#411), so which text uses a font is the
  reader's: Font: Book loads the first font of the manifest (`font/otf`, `font/ttf`,
  `font/woff`, `font/woff2`) for the text. An obfuscated font is undone (#410, below).

## Obfuscated fonts are undone (#410)

EPUB OCF 3.3 section 4.1.2 requires a reading system with a viewport to undo
the two font obfuscations, and a reader that skips them falls back to a default
face without a word. `src/font_obfuscation.bats` undoes both (xor is its own
inverse, `font_unmask`): IDPF's (`http://www.idpf.org/2008/embedding`: the
key is the SHA-1 of the package's unique identifier with its white space,
U+0020, U+0009, U+000D and U+000A, taken out, 20 bytes, xored with the font's
first 1040 bytes going round; `idpf_key`) and Adobe's
(`http://ns.adobe.com/pdf/enc#RC`: the 16 bytes of the identifier's UUID, after its
last colon and without its dashes, xored with the first 1024; `adobe_key`).
SHA-1 is the sha256 package's `sha1_digest` (proved against FIPS 180-4's
relations, sha256#29 and #36, with the standard's vectors tested; quire#562
moved it there from `src/sha1.bats`). The unique identifier is the `dc:identifier` the package's
`unique-identifier` names (`opf_unique_identifier`, copied by `_font_locate`).
Which algorithm a font has comes from `META-INF/encryption.xml`, read as the font
is loaded (`_font_cipher_find`): each `EncryptedData`
(`encrypted_nth`) names a `CipherReference` URI, found with `book_find_relative`
from the container's root, and it is the font's when its entry is the font's
(`font_cipher`: `FontNotListed`, `FontObfuscatedIdpf`, `FontObfuscatedAdobe`,
`FontCipherOther`). The font is unmasked in its piece before its blob URL is made
(`_font_blob`), every time the book is opened, so a reload works as an import does.
It degrades where it is (no banner for the book; the text is set in the reader's
own face, `var(--bookfont,Georgia),serif`): an algorithm Quire has no client for
(`FontCipherOther`), an identifier that makes no key (an Adobe one that is no UUID,
none, over 4096 bytes), a font the archive lacks, noise, and one shorter than the masked
bytes (the browser's decoder refuses it). By research: the OCF specification
gives both algorithms and requires them of a reading system; Readium's streamer
(`FontDecoder`), Calibre (`oeb/polish` font deobfuscation) and foliate-js
(`epub.js` deobfuscators) each undo both the same way, and a resource they cannot
decode is not drawn, not a failure of the book.

**A font encrypted in an unknown algorithm does not make the book DRM** (#410
against #427): `_encrypted_data_unknown` (`src/epub_xml.bats`) passes an
`EncryptedData` whose `CipherReference` is a font file (`.otf`, `.ttf`, `.ttc`,
`.woff`, `.woff2`) even when its algorithm is none of the two, since the text
of such a book reads and only the face cannot be had. Anything else under an
unknown algorithm is refused as before (`e2e/drm.spec.js`), and a namespace of
ADEPT, LCP or Kobo anywhere in the file still is. `e2e/fonts.spec.js` plays
`e2e/font-books.js` (checked by epubcheck, the font `e2e/marker-font.ttf` has one
glyph no system has, U+E000, 1.7 em wide, so the page's face is told by measuring
it; `create-epub.js` has `obfuscatedFonts`, `identifier` and `manifestOnly`, and
`obfuscateFont`, written apart from the app's): masked each way, an identifier with
white space, a reload, no Book chosen, and each degrading case.

### Settled by research, kept failing (#419)

A must test stays failing only where two documented behaviours conflict, and the one
that wins is named:

* **The book's CSS is not applied (#411) wins over the suite's CSS tests**
  (`cnt-svg-css-inclusion` (the svg is drawn; the page's style does not reach it), `nav-spine_in-spine-hidden-toc-css`, `lay-pp-xhtml-icb`,
  `_multi`, `_multi_declarations`, `_repeated-in-meta`, `_units`, the deprecated
  `lay-fxl-*` copies, `css-epub-*` (ten should, vendor-prefixed properties),
  `mol-css`, `ocf-font_obfuscation`): each asks that a rule of the book's own style
  sheet change how its text is drawn. The stylesheet's colours are the app's, each text and
  ground pair proven to reach 4.5:1 in each theme (`SURF`), and the reader's size, margins, spacing,
  Justify, Hyphenation and Font settings are the reader's (accessibility is what a
  reading app is for); a book's colours or sizes would break the proofs and
  the settings. Readium CSS (Thorium) keeps the publisher's styles by default and
  offers a switch to turn them off (its docs: "publisher styles"); Quire is the other way
  round, on purpose. The icb tests' viewport is read and measured (`lay-pp-viewport-*`
  passes); their pass criterion is a grid the book draws, which no reading system of the suite's
  reports answered (0 of 0).
* **The package's language and direction (#416, the book's language on its chapters)
  win over `pkg-lang_but_not_content` and `pkg-dir_but_not_content`**, above.
* **`pub-cmt-jxl`** is the platform's: Chromium and Android's WebView have no
  JPEG XL decoder (Chrome removed its own in 2023), so the image is not drawn. A
  fallback is followed when the manifest names one (`pub-foreign_image`).
* **`pkg-manifest-unlisted-resource`**: see above.
* **Deprecated tests** (`fxl-spine-overrides_duplicate`, `lay-fxl-orientation-landscape`):
  the suite itself files them as deprecated (the `fxl-*` and `lay-fxl-*` copies
  that the `lay-pp-*` tests replace), and `rendition:orientation` is not read.

## SVG is drawn as a picture of its own (#419)

An inline `<svg>` of a page, and an SVG content document, is drawn by
`_render_node` in `src/reader.bats` as an `<img>` whose source is a blob of the
element's own bytes (`images_svg`, `_load_svg`): a copy of the element from its `<svg` to
its closing tag (`_svg_end`, which passes over comments, CDATA sections, processing
instructions and quoted values, so a `</svg>` in one does not end it), with the
`xmlns` and `xmlns:xlink` it was given by its page written in when it names none. Its
children are still made, so every content node keeps its number (search, read aloud and
the overlays count the same tree), but an `<img>` shows none of them. An svg that holds
an `<image>` (a cover page's usual form, drawn by the existing `<image>` path) or is over 512 KiB, or one inside
another, is not drawn this way.

By research, why a picture and not the element in the page, which is what other readers
do: Readium's navigators (Thorium, Readium Mobile), Apple Books, Kobo, Calibre's viewer and
foliate-js each show a content document in a frame or view of its own, so an svg's `<style>`,
ids and links are scoped to that document. Quire's page is one DOM shared with its own
interface and every chapter, with no frame, so a `<style>` in an svg would be a global rule
that could restyle the interface (the proofs of `style.bats` and quire#411 are about exactly that),
an id could collide with the app's, and a script-capable element is something a book may
never put there. A sandboxed image has the same drawing, its own style scope and no
script or outside load (a browser's rule for an svg used as an image), and no care about ids.
What it costs: the book's page CSS does not reach it (`cnt-svg-css-inclusion`, kept
failing by #411 above), its links and scripts do nothing, it uses system fonts, not the
book's, and a dark theme does not recolour its black text (an image is not themed; the
image dimming setting applies to it). Its text is kept in the page, hidden, so a search hit can
still be counted.

## MathML is the browser's (#419, #408)

A `math` element of a chapter is made element for element in the MathML namespace
(`_math_add`, `_math_attrs` in `src/reader.bats`: dom's `add_math_element` and
`set_math_attr`, which write bridge's `math:` tag, `createElementNS`), so the browser sets the
equation and its accessibility tree has the MathML (no `role`, no text copy), the
one rendering both #419's `cnt-mathml-support` and #408 need. The elements are
MathML Core's presentation ones; `maction` and `annotation-xml` (they can carry behaviour
or foreign content) are refused, as are any colour or background attribute (the page's colours are the
theme's: the text's own colour, so each equation reaches the contrast the proofs hold for text) and any link or handler. A
refused element makes none and its children go to its parent; elements and texts take
their content-node numbers as everywhere, so search and read aloud count the same tree.
A token's (`mi`, `mn`, `mo`, `ms`, `mtext`) text is its own; text anywhere else in a math element is not shown. A
display equation wider than the column scrolls along it (`math[display=block]`).
By research: every reader that shows a content document in a browser engine (Thorium,
Readium Mobile on Android, Calibre's viewer, Foliate) leaves MathML to the engine, and Chromium
has set MathML Core since 109; Apple Books' WebKit too. Where an engine has no math font the text falls back.

What #408's tests (`e2e/math-native.spec.js`, `math-fallbacks.spec.js`, `math-layout.spec.js`,
books in `e2e/math-books.js`, each checked by epubcheck) hold, and what they found:

* **A display equation scrolls along its width only.** `math[display=block]` was `overflow: auto`
  on both axes, and Chromium counts a glyph's font box (ascent and descent) in the scrollable
  overflow, a few pixels beyond the equation's own box, so a display equation had a vertical
  scroll of 4px. It is `overflow: auto hidden` with .3em above and below, so what the font
  box adds is room inside the equation's box and a page boundary neither splits nor clips it.
* **`dir` is the page's own attribute** (`_math_attrs`): dom's allow-list of MathML attributes
  has none, MathML Core takes `dir` on any math element, so it is set as an HTML `dir` is
  (`$D.Dir`): an equation is set left to right even in a Hebrew book (`math` has `direction:
  ltr`) unless it says `dir="rtl"`.
* **`alttext` and `altimg` are not shown when MathML is drawn**, by research: EPUB 3.3 and the
  MathML specification make them the fallback for a system that cannot draw the math (the
  W3C EPUB group's thread on MathML: "fallback images via the altimg attribute" for the many
  readers that cannot render it; the DAISY knowledge base: support "depends heavily on the age
  of the reading system", fallbacks for the old ones); no reading system researched shows the
  fallback beside a drawn equation, and none documents that it should. The engine draws MathML
  Core, so the picture would show every equation twice, and the text is the equation's name
  for assistive technology, which the browser exposes. `altimg` is not an allowed attribute
  of dom's, so no image is ever made of it.
* **Unsupported and broken MathML degrades where it stands.** An element dom does not make
  (`maction`, `annotation-xml`, `mstack`, `mglyph`, ...) makes none and its children go to its
  parent; a token's text stays. A broken tree (a fraction of one child, an unknown element) is
  drawn by the browser as it can: the words around it are not lost. (The broken book is not
  valid MathML, so epubcheck refuses it by `RSC-005`, which its entry lists.)
* **Accessibility.** Chromium's tree has a `MathMLMath` node for each `math`, and
  `MathMLFraction`, `MathMLIdentifier`... for its parts (the name CDP gives the role ARIA calls
  `math`); Quire sets no `role`, `aria-hidden` or `aria-label` on MathML.

## Equations as pictures (#408)

A picture of an equation (a PNG, an inline `<svg>`, an `<img src="x.svg">`) is a picture of
text. Two decisions, by research (also in the issue):

* **A picture grows with the reader's text size.** Quire drops the book's CSS (#411), so the
  `em` heights publishers give such pictures are not there, and a picture was always its own
  pixels. Amazon's guidelines say inline images "should be sized in em units so that they scale
  in relation to the text around them when users adjust the font size" (quoted by Jutoh's
  manual; a block picture is sized in px or % there), Readium CSS has no setting that scales
  pictures (its `invert`, `darken` and `blend` flags only recolour), and a MobileRead report
  has em-height pictures overlapping text in Readium. So a picture is its own size at the
  default text size (18px) and is scaled by the reader's size from there (`--image-zoom`, in
  thousandths, written by `_apply_type` in `src/settings.bats`; CSS `zoom` in `.caf:not(.fixed)
  img`, a fixed page being fitted by its own box), kept to the column's width and the page's
  height as before (the height is divided by the zoom, which multiplies lengths). It is the
  same for any picture, not only equations: Quire cannot tell an equation from a diagram or a
  photograph, and a photograph is kept to the column anyway.
* **Black ink on no ground is drawn on paper in the dark themes.** Black on the Dark, Night and
  Grey grounds was 1.1 to 1.8 to one (WCAG asks 3:1 for graphics). Readium CSS (Thorium) offers
  the reader an `invert` flag for night mode that inverts every picture; Quire has no setting
  for it and cannot tell a picture with no ground from one with colours that inversion would
  ruin (a photograph), so a picture is drawn on white in those themes (`tint`, no new colour
  role): a picture with a ground of its own covers it, and black ink has 21:1. The cost is a
  white rectangle behind a transparent picture of white ink, which is rare next to the
  typeset equation, the diagram and the line drawing; the image dimming setting dims it as
  it dims every picture.
