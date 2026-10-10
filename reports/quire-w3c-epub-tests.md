# Quire against the W3C EPUB 3 test suite (quire#419)

The suite is w3c/epub-tests at commit `54092b4233253e9aac80e93ec4782b380b4b3403`. Every test EPUB was built as `tests/generateEpubs.sh` builds it
(`zip`, with the `mimetype` first), imported into Quire's web build in Playwright's Chromium (the desktop project, 1024 by 768)
and opened, by `scripts/w3c-epub-tests-survey.mjs` (what the reader shows), `scripts/w3c-epub-tests-probe.mjs`
(the contents panel, a link followed, two books in one library, the reading direction, bookmarks) and
`scripts/w3c-epub-tests-narration.mjs` (Read aloud on each Media Overlays book). The verdicts are in
`scripts/w3c-epub-tests-report.py`, which writes this file and `reports/quire.json`. The android project and the
Android app itself were not run.

## Counts

| level | pass | fail | n/a | total |
| --- | ---: | ---: | ---: | ---: |
| must | 94 | 28 | 17 | 139 |
| should | 11 | 22 | 5 | 38 |
| may | 0 | 1 | 0 | 1 |
| deprecated | 16 | 10 | 1 | 27 |
| all | 121 | 61 | 23 | 205 |

The suite lists `deprecated` tests (the `fxl-*` and `lay-fxl-*` ones, which the `lay-pp-*` ones replace); they are in
the table too, and in `reports/quire.json`, as the suite's own template has them.

## Failures

"Others" is how many of the reading systems whose reports the suite holds pass the test, of those that answered.
"e2e" is `yes` when `e2e/w3c-epub-tests.spec.js` holds a test that fails for it (none: a fix lands with its test); "policy" is a failure that follows from a
decision of Quire's (the book's CSS is dropped; no scripts), not a bug: whether to keep the decision is the maintainer's.

| test | level | why | others | e2e |
| --- | --- | --- | ---: | --- |
| `cnt-css-fonts_ot` | must | the book's own CSS is dropped by design, so its @font-face is never loaded | 1/1 | policy |
| `cnt-css-fonts_tt` | must | the book's own CSS is dropped by design, so its @font-face is never loaded | 1/1 | policy |
| `cnt-css-fonts_woff` | must | the book's own CSS is dropped by design, so its @font-face is never loaded | 1/1 | policy |
| `cnt-css-fonts_woff2` | must | the book's own CSS is dropped by design, so its @font-face is never loaded | 1/1 | policy |
| `cnt-mathml-support` | must | a math element is made a div: its tokens are shown as plain text ("x / = / a / + / b / 2"), not an equation | 14/17 | next |
| `cnt-svg-css` | must | an SVG content document is shown as its text only: no drawing, no CSS applied to it | 5/17 | next |
| `cnt-svg-css-inclusion` | must | an SVG included in the XHTML is not drawn (svg elements are made divs) | 12/18 | next |
| `cnt-svg-embedded` | must | an inline svg is not drawn (made a div; no graphics) | 16/18 | next |
| `cnt-svg-support` | must | an SVG spine document shows its text but not its drawing | 9/17 | next |
| `lay-pp-svg-icb_multi` | must | SVG spine documents are not drawn, nor sized by their viewBox | 0/0 | next |
| `lay-pp-xhtml-icb` | must | the viewport is read (900x600, measured) but the pass criterion is a grid the book's CSS draws, and the CSS is dropped by design | 0/0 | policy |
| `lay-pp-xhtml-icb_multi` | must | each page's own viewport is read (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 0/0 | policy |
| `lay-pp-xhtml-icb_multi_declarations` | must | the first of two viewport metas is the one used (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 0/0 | policy |
| `lay-pp-xhtml-icb_repeated-in-meta` | must | the first width and height are used (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 0/0 | policy |
| `lay-pp-xhtml-icb_units` | must | units are ignored, values in pixels (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 0/0 | policy |
| `lay-roll-embedded-images` | must | roll layout (EPUB 3.4) is not implemented: read as reflowable, a chapter a document | 2/2 | policy |
| `lay-roll-embedded-images-svg` | must | roll layout (EPUB 3.4) is not implemented: read as reflowable, a chapter a document | 2/2 | policy |
| `nav-spine_in-spine-hidden-toc-css` | must | the navigation document in the spine shows the entry its CSS hides (display:none): the book's CSS is dropped by design; the contents panel lists both, as asked | 1/2 | policy |
| `nav-spine_in-spine-hidden-toc-html` | must | the navigation document in the spine shows the entry its hidden attribute hides; the contents panel lists both, as asked | 1/2 | next |
| `ocf-url_link-path-absolute` | must | a path-absolute address ("/images/photograph.jpg") is not resolved from the container root: the image is blanked | 6/16 | next |
| `pkg-dir_but_not_content` | must | a Hebrew book's page is set right to left, as its reading direction is (by decision, quire#416: a book in Hebrew or Arabic whose spine names no direction reads right to left, as Readium reads it; the page is one CSS column flow, so its direction is the columns' order, and a list or a paragraph in the book inherits it). The suite's pass criterion is a content document with no dir staying left to right, which 13 of the 13 reading systems that answered meet by laying each document out on its own; Quire's single flow cannot without giving up the Hebrew heuristic or marking every block | 13/13 | policy |
| `pkg-lang_but_not_content` | must | the OPF's dc:language is the page's language where the chapter names none, so a q gets French quotation marks in a French book (by decision: browsers hyphenate and pick quotation marks only for text whose language is known, and the package's language is the only one a book declares; the earlier test in reader.spec.js holds it, and a book that names none is 'und', not English). 11 of the 15 reading systems that answered show a content document with no language in their own, the suite's criterion | 11/15 | policy |
| `pub-cmt-jxl` | must | the image is not decoded: Chromium (and Android's WebView) have no JPEG XL decoder | 0/2 | platform |
| `pub-cmt-mp3` | must | an audio element is not shown (its fallback content is) | 12/14 | next |
| `pub-cmt-mp4` | must | an audio element is not shown (its fallback content is) | 11/14 | next |
| `pub-cmt-opus` | must | an audio element is not shown (its fallback content is) | 6/14 | next |
| `pub-data-urls_browsing-context` | must | an img with a data: URL is blanked (src="data:,") | 16/16 | next |
| `pub-data-urls_top-level-content` | must | an img with a data: URL is blanked (src="data:,") | 14/15 | next |
| `css-epub-hyphens` | should | the book's own CSS is dropped by design (the reader's Hyphenation setting is the reader's) | 7/18 | policy |
| `css-epub-line-break` | should | the book's own CSS is dropped by design | 3/15 | policy |
| `css-epub-text-align-last` | should | the book's own CSS is dropped by design | 1/19 | policy |
| `css-epub-text-combine-horizontal` | should | the book's own CSS is dropped by design | 3/16 | policy |
| `css-epub-text-emphasis` | should | the book's own CSS is dropped by design | 3/17 | policy |
| `css-epub-text-orientation` | should | the book's own CSS is dropped by design (vertical writing comes from the OPF) | 15/17 | policy |
| `css-epub-text-transform` | should | the book's own CSS is dropped by design | 2/11 | policy |
| `css-epub-text-underline-position` | should | the book's own CSS is dropped by design | 4/16 | policy |
| `css-epub-word-break` | should | the book's own CSS is dropped by design | 8/17 | policy |
| `css-epub-writing-mode` | should | the book's own CSS is dropped by design (vertical writing comes from the OPF) | 14/16 | policy |
| `lay-pkg-flow-scrolled-continuous` | should | rendition:flow is not read: the reader's own Pages | Scroll setting decides | 3/14 | next |
| `lay-pkg-flow-scrolled-doc` | should | rendition:flow is not read: the reader's own Pages | Scroll setting decides | 6/13 | next |
| `lay-pp-xhtml-icb_invalid_meta` | should | an invalid viewport meta is read as 900x600 (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 0/0 | policy |
| `mol-css` | should | the phrase is marked by Quire's own highlight; media:active-class and the book's CSS (green background) are not applied | 2/8 | decision |
| `mol-tts_multi` | should | a SMIL with no audio is not read by speech synthesis: nothing plays | 6/13 | decision |
| `mol-tts_single` | should | a SMIL with no audio is not read by speech synthesis: nothing plays | 6/13 | decision |
| `nav-non-text_img` | should | a navigation link holding an image is labelled "Untitled": its alt text is not used | 0/4 | next |
| `nav-non-text_img_title` | should | a navigation link holding an image is labelled "Untitled": its alt and title are not used | 0/4 | next |
| `ocf-font_obfuscation` | should | the book's own CSS is dropped by design, so an embedded font is never used | 7/15 | policy |
| `pkg-manifest-unlisted-resource` | should | an image the manifest does not list is shown: the zip is read by name, not by the manifest | 4/15 | next |
| `pub-external-links` | should | a link out opens a new tab at once, with no consent step | 7/15 | decision |
| `pub-external-links_consent` | should | a mailto: link opens the mail application at once, with no consent step | 4/12 | decision |
| `pss-support` | may | no footnote popup: a note link is followed as a link | 4/14 | next |
| `fxl-spine-overrides_duplicate` | deprecated | when an itemref says both layout-reflowable and layout-pre-paginated the second wins (shown as a fixed page); the test says the second must be ignored | 4/13 | next |
| `lay-fxl-orientation-landscape` | deprecated | rendition:orientation is not read: the page is not shown in landscape and the reader is not told it should be | 10/14 | next |
| `lay-fxl-svg-icb_multi` | deprecated | SVG spine documents are not drawn, nor sized by their viewBox | 6/9 | next |
| `lay-fxl-xhtml-icb` | deprecated | the viewport is read (900x600, measured) but the pass criterion is a grid the book's CSS draws, and the CSS is dropped by design | 11/13 | policy |
| `lay-fxl-xhtml-icb_device_sizes` | deprecated | device-width/device-height fill the view, but the pass criterion is drawn by the book's CSS, dropped by design | 5/10 | policy |
| `lay-fxl-xhtml-icb_invalid_meta` | deprecated | an invalid viewport meta is read as 900x600 (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 7/10 | policy |
| `lay-fxl-xhtml-icb_multi` | deprecated | each page's own viewport is read (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 9/13 | policy |
| `lay-fxl-xhtml-icb_multi_declarations` | deprecated | the first of two viewport metas is the one used (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 11/13 | policy |
| `lay-fxl-xhtml-icb_repeated-in-meta` | deprecated | the first width and height are used (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 6/10 | policy |
| `lay-fxl-xhtml-icb_units` | deprecated | units are ignored, values in pixels (measured) but the pass criterion is drawn by the book's CSS, dropped by design | 13/13 | policy |

A failure marked `next` is a bug whose e2e test is written with its fix, in the area of fixes it belongs to (so a branch
carries only tests that pass). The `should` failures marked `decision` are left for a decision: `pub-external-links` and `pub-external-links_consent`
(a link out opens at once: a consent step is a design to choose, with what Thorium, Apple Books and Kobo do, in the "Others" column
and on the results page), `mol-tts_single` and `mol-tts_multi` (a SMIL with no audio read by speech synthesis: Quire has both
narration and speech, but not the one through the other) and `mol-css` (the book's own highlight CSS, dropped by design).

## Not applicable

| test | level | why |
| --- | --- | --- |
| `fxl-layout-duplication` | deprecated | the test is about EPUBCheck, not a reading system |
| `lay-pp-layout-duplication` | must | the test is about EPUBCheck, not a reading system |
| `lay-reflow-align-x-center` | must | rendition:align-x-center is optional for reflowable content ("reading systems that support it") and Quire does not |
| `mol-ignore` | must | only for reading systems that do not support media overlays |
| `ocf-url_origin` | must | needs scripting, which Quire does not run |
| `ocf-url_parse-leaking-relative` | must | needs scripting, which Quire does not run |
| `ocf-url_parse-path-absolute` | must | needs scripting, which Quire does not run |
| `pss-support_ignore-title` | must | only for reading systems with a footnote popup |
| `scr-not-support_ccscript-modify-host` | must | Quire runs no scripts and shows no iframes |
| `scr-not-support_ccscript-modify-size` | must | Quire runs no scripts and shows no iframes |
| `scr-readingsystem-features` | must | Quire runs no scripts (no epubReadingSystem object) |
| `scr-readingsystem-support` | must | Quire runs no scripts (no epubReadingSystem object) |
| `scr-readingsystem-support_iframe` | must | Quire runs no scripts and shows no iframes |
| `scr-readingsystem-support_iframe_svg` | must | Quire runs no scripts and shows no iframes |
| `scr-readingsystem-support_svg` | must | Quire runs no scripts |
| `scr-storage-delete` | should | Quire runs no scripts: nothing is stored by a book |
| `scr-support` | should | Quire runs no scripts, by policy |
| `scr-support_iframe` | should | Quire runs no scripts and shows no iframes |
| `scr-support_origin` | must | Quire runs no scripts |
| `scr-support_origin_unique` | must | Quire runs no scripts |
| `scr-support_scrolled-continuous` | should | only for reading systems that run scripts |
| `scr-support_scrolled-doc` | must | only for reading systems that run scripts |
| `scr-support_svg` | should | Quire runs no scripts |

## Passing

Caveats of a pass, where there is one:

* `cnt-svg-css-reference`: an SVG referenced by img is shown, and the page's CSS does not change it
* `fxl-page-spread-break`: two spreads, 1-2 and 3-4, measured
* `fxl-page-spread-center`: a centred page is alone, measured
* `lay-fxl-layout-pre-paginated-spreads`: pages meet with no gap, measured
* `lay-fxl-page-spread-combined`: measured
* `lay-fxl-page-spread-left`: measured
* `lay-fxl-page-spread-right`: measured
* `lay-fxl-spread-landscape`: in a landscape window
* `lay-fxl-spread-none`: one page a screen, measured
* `lay-page-layout-both-spread`: the reflowable item with page-spread-left starts on the left; page-spread-right on a reflowable item is not placed on the right (not tested by the suite)
* `lay-pkg-flow-paginated`: paginated is the default
* `lay-pp-embedded-images`: measured: each image fills its page
* `lay-pp-embedded-images-svg`: the images inside the SVG are shown
* `lay-pp-images-in-spine`: an image in the spine is replaced by its fallback and never read as text; no crash (the 3 MB PNG)
* `lay-pp-images-mixed`: an image in the spine is replaced by its fallback; no hang
* `lay-pp-layout-pre-paginated-spreads`: pages meet with no gap, measured
* `lay-pp-page-spread-combined`: measured
* `lay-pp-page-spread-left`: measured
* `lay-pp-page-spread-right`: measured
* `lay-pp-spine-overrides_image-spine-pp`: the PNG spine item is replaced by its fallback
* `lay-pp-spine-overrides_image-spine-reflow`: the PNG spine item is replaced by its fallback
* `lay-pp-spread-none`: one page a screen, measured
* `lay-rendition-flow-pre-pag`: rendition:flow is ignored everywhere
* `lay-roll-images-in-spine`: an image in the spine is replaced by its fallback, no crash (roll layout itself is not implemented, as lay-roll-embedded-images says)
* `lay-roll-images-mixed`: an image in the spine is replaced by its fallback, no hang (roll layout itself is not implemented)
* `lay-viewport-meta-prop`: only the dimensions of the viewport are read (measured)
* `mol-audio`: clipBegin/clipEnd obeyed (MP3)
* `mol-audio-exceeding-clipend`: MP3
* `mol-audio-no-clipbegin`: MP3
* `mol-audio-no-clipend`: MP3
* `mol-navigation`: a jump through the contents moves the narration (MP3)
* `mol-support_xhtml`: the suite's MP4 audio was replaced by the same sound as MP3 in the run: Playwright's Chromium has no AAC decoder
* `mol-support_xhtml-fxl`: run with the MP4 audio replaced by MP3 (no AAC in Playwright's Chromium)
* `mol-support_xhtml-load`: run with the MP4 audio replaced by MP3 (no AAC in Playwright's Chromium)
* `mol-support_xhtml-load-fxl`: run with the MP4 audio replaced by MP3 (no AAC in Playwright's Chromium)
* `mol-support_xhtml-load-next`: run with the MP4 audio replaced by MP3 (no AAC in Playwright's Chromium)
* `mol-support_xhtml-load-next-fxl`: run with the MP4 audio replaced by MP3 (no AAC in Playwright's Chromium)
* `mol-timing-synchronization`: run with the MP4 audio replaced by MP3 (no AAC in Playwright's Chromium)
* `mol-timing-synchronization_fxl`: MP3
* `mol-timing-synchronization_multiple_audio`: MP3
* `mol-timing-synchronization_multiple_audio-fxl`: MP3
* `mol-timing-synchronization_svg`: the text of the SVG is read and marked (the drawing is not shown); MP3
* `mol-timing-synchronization_svg-fxl`: the text of the SVG is read and marked (the drawing is not shown); MP3
* `nav-spine_in-spine-no-list-style`: the contents panel is not numbered
* `ocf-font_obfuscation_bis`: the font is not displayed (no embedded font is ever used)
* `ocf-zip-comp`: an archive with an entry compressed by anything but Deflate or stored is refused (the suite's EPUB is built with Deflate, so it cannot show the case; the e2e test makes a bzip2 entry)
* `ocf-zip-mult`: an archive whose end record names more than one disk is refused (the suite's EPUB is one zip; the e2e test makes a split archive's end record)
* `pkg-creator-order`: the first dc:creator is used
* `pkg-dir-auto_root-rtl`: the title is shown with a left to right base, as the test says it should be (dir=auto, first letter Latin)
* `pkg-dir-auto_root-unset`: the title is shown with a left to right base, as the test says it should be
* `pkg-dir_creator-rtl`: a dc:creator's dir is read and shown on the library card
* `pkg-dir_rtl-root-ltr`: a dc:title's own dir outranks the package's, on the library card
* `pkg-dir_rtl-root-unset`: a dc:title's dir is read and shown on the library card
* `pkg-dir_unset-root-rtl`: the package's dir is the title's and the creator's when they have none, on the library card
* `pkg-dir_unset-root-unset`: the title is shown left to right, as the test says it should be
* `pkg-meta-whitespace`: shown with single spaces (HTML collapses them); the title and author are stored with the spaces as written, so a search or sort sees them
* `pkg-spine-duplicate-item-hyperlink`: a link to the document goes to its first place in the spine
* `pkg-spine-duplicate-item-rendering`: three places of the document, measured by progress
* `pkg-spine-duplicate-item-ui`: three bookmarks, one for each place
* `pkg-spine-order-svg`: the text of each page, in order (the drawings are not shown)
* `pkg-title-order`: the first dc:title is used
* `pkg-unique-id`: two books with the one identifier are two cards
* `pkg-unique-id_duplicate`: two books with the one identifier are two cards
* `pub-file-urls`: iframes are not shown, so no file: URL is loaded
* `pub-foreign_bad-fallback`: an item and a fallback that are both foreign are left out of the spine, never shown as text
* `pub-foreign_image`: an img of a foreign type is shown as its manifest fallback
* `pub-foreign_json-spine`: the fallback is shown in place of the JSON item
* `pub-foreign_xml-spine`: the fallback is shown in place of the XML item
* `pub-foreign_xml-suffix-spine`: the fallback is shown in place of the XML item
* `pub-xml-external-id`: the entity is not resolved
* `pub-xml-names`: a content document with an invalid element name (a::b) is reported as an error when its chapter is opened
* `pub-xml-non-validating_unclosed`: a content document with an unclosed element is reported as an error when its chapter is opened
* `scr-support-fallback`: a scripted item with a fallback is replaced by the fallback (no scripts are run)
* `sec-untrusted-consent_network`: no remote resource is requested, with or without consent (measured: no request left the page)
* `sec-untrusted-consent_scripting`: no script is run, with or without consent

Pass with nothing to add: `cnt-xhtml-support`, `fxl-spine-overrides_behave-as-global`, `fxl-spine-overrides_behave-as-global-bis`, `lay-fxl-layout-default`, `lay-fxl-layout-pre-paginated`, `lay-fxl-orientation-default`, `lay-fxl-spread-auto`, `lay-fxl-spread-both`, `lay-fxl-spread-default`, `lay-page-layout-both`, `lay-pp-layout-default`, `lay-pp-layout-pre-paginated`, `lay-pp-spine-overrides_behave-as-global`, `lay-pp-spine-overrides_behave-as-global-bis`, `lay-pp-spine-overrides_image-only-pp`, `lay-pp-spine-overrides_image-only-reflow`, `nav-access`, `nav-activation`, `nav-spine_in-spine`, `nav-spine_not-in-spine`, `ocf-metainf-inc`, `ocf-metainf-manifest`, `ocf-package_arbitrary`, `ocf-package_multiple`, `ocf-url_link-leaking-relative`, `ocf-url_link-relative`, `ocf-url_manifest`, `pkg-collections-unknown`, `pkg-linked-records`, `pkg-manifest-unknown`, `pkg-meta-unknown`, `pkg-spine-nonlinear-activation`, `pkg-spine-order`, `pkg-spine-progression-default`, `pkg-spine-progression-pre-paginated`, `pkg-spine-progression_ltr`, `pkg-spine-progression_rtl`, `pkg-spine-unknown`, `pkg-version-backward`, `pub-cmt-avif`, `pub-cmt-gif`, `pub-cmt-jpeg`, `pub-cmt-png`, `pub-cmt-svg`, `pub-cmt-webp`, `pub-xml-non-validating_comment`.
