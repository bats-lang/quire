#!/usr/bin/env python3
"""Writes reports/quire.json and reports/quire-w3c-epub-tests.md (quire#419).

The verdicts are in VERDICTS below, decided from the surveys of
scripts/w3c-epub-tests-survey.mjs, -probe.mjs and -narration.mjs, run on
the suite's EPUBs (built as tests/generateEpubs.sh builds them) in the
desktop project, and from the tests of e2e/w3c-epub-tests.spec.js.

usage: scripts/w3c-epub-tests-report.py <clone of w3c/epub-tests>

The clone gives each test's level (its package's belongs-to-collection),
its description and the other reading systems' answers (epub33/reports).
"""
import glob
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

T, F, N = True, False, 'n/a'

# id: (result, why). A failure's why is the cause, a pass has none but a caveat.
VERDICTS = {
    # Content Documents
    'cnt-css-fonts_ot': (T, "the font the package carries is loaded and used when the Font setting is Book; the book's own CSS, which says what uses it, is dropped by design"),
    'cnt-css-fonts_tt': (T, "the font the package carries is loaded and used when the Font setting is Book; the book's own CSS, which says what uses it, is dropped by design"),
    'cnt-css-fonts_woff': (T, "the font the package carries is loaded and used when the Font setting is Book; the book's own CSS, which says what uses it, is dropped by design"),
    'cnt-css-fonts_woff2': (T, "the font the package carries is loaded and used when the Font setting is Book; the book's own CSS, which says what uses it, is dropped by design"),
    'cnt-mathml-support': (T, 'a math element is made element for element in the MathML namespace (dom\'s add_math_element, bridge\'s math: tag), so the browser sets the equation; maction, annotation-xml and colours are refused'),
    'cnt-svg-css': (T, "an svg (in a page or a content document) is drawn as a picture of its own bytes: an image whose source is a blob, so its own style applies, no script runs and nothing reaches in or out; its text stays in the page for search but is not seen"),
    'cnt-svg-css-inclusion': (F, "the svg is drawn, but the page's own <style> does not reach it (by decision: the book's CSS is dropped, quire#411; the svg is a picture of its own, so a style outside it cannot change it, as for an img (cnt-svg-css-reference))"),
    'cnt-svg-css-reference': (T, 'an SVG referenced by img is shown, and the page\'s CSS does not change it'),
    'cnt-svg-embedded': (T, "an svg (in a page or a content document) is drawn as a picture of its own bytes: an image whose source is a blob, so its own style applies, no script runs and nothing reaches in or out; its text stays in the page for search but is not seen"),
    'cnt-svg-support': (T, "an svg (in a page or a content document) is drawn as a picture of its own bytes: an image whose source is a blob, so its own style applies, no script runs and nothing reaches in or out; its text stays in the page for search but is not seen"),
    'cnt-xhtml-support': (T, ''),
    'css-epub-hyphens': (F, "the book's own CSS is dropped by design (the reader's Hyphenation setting is the reader's)"),
    'css-epub-line-break': (F, "the book's own CSS is dropped by design"),
    'css-epub-text-align-last': (F, "the book's own CSS is dropped by design"),
    'css-epub-text-combine-horizontal': (F, "the book's own CSS is dropped by design"),
    'css-epub-text-emphasis': (F, "the book's own CSS is dropped by design"),
    'css-epub-text-orientation': (F, "the book's own CSS is dropped by design (vertical writing comes from the OPF)"),
    'css-epub-text-transform': (F, "the book's own CSS is dropped by design"),
    'css-epub-text-underline-position': (F, "the book's own CSS is dropped by design"),
    'css-epub-word-break': (F, "the book's own CSS is dropped by design"),
    'css-epub-writing-mode': (F, "the book's own CSS is dropped by design (vertical writing comes from the OPF)"),
    # Pre-paginated Layout, deprecated copies (fxl-*, lay-fxl-*) and current (lay-pp-*)
    'fxl-layout-duplication': (N, 'the test is about EPUBCheck, not a reading system'),
    'lay-pp-layout-duplication': (N, 'the test is about EPUBCheck, not a reading system'),
    'fxl-page-spread-break': (T, 'two spreads, 1-2 and 3-4, measured'),
    'fxl-page-spread-center': (T, 'a centred page is alone, measured'),
    'fxl-spine-overrides_behave-as-global': (T, ''),
    'fxl-spine-overrides_behave-as-global-bis': (T, ''),
    'fxl-spine-overrides_duplicate': (F, 'when an itemref says both layout-reflowable and layout-pre-paginated the second wins (shown as a fixed page); the test says the second must be ignored'),
    'lay-fxl-layout-default': (T, ''),
    'lay-fxl-layout-pre-paginated': (T, ''),
    'lay-fxl-layout-pre-paginated-spreads': (T, 'pages meet with no gap, measured'),
    'lay-fxl-orientation-default': (T, ''),
    'lay-fxl-orientation-landscape': (F, 'rendition:orientation is not read: the page is not shown in landscape and the reader is not told it should be'),
    'lay-fxl-page-spread-combined': (T, 'measured'),
    'lay-fxl-page-spread-left': (T, 'measured'),
    'lay-fxl-page-spread-right': (T, 'measured'),
    'lay-fxl-spread-auto': (T, ''),
    'lay-fxl-spread-both': (T, ''),
    'lay-fxl-spread-default': (T, ''),
    'lay-fxl-spread-landscape': (T, 'in a landscape window'),
    'lay-fxl-spread-none': (T, 'one page a screen, measured'),
    'lay-fxl-svg-icb_multi': (T, 'an SVG spine document is drawn as a picture whose viewBox sets its size, clipped to it'),
    'lay-fxl-xhtml-icb': (F, "the viewport is read (900x600, measured) but the pass criterion is a grid the book's CSS draws, and the CSS is dropped by design"),
    'lay-fxl-xhtml-icb_device_sizes': (F, "device-width/device-height fill the view, but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-fxl-xhtml-icb_invalid_meta': (F, "an invalid viewport meta is read as 900x600 (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-fxl-xhtml-icb_multi': (F, "each page's own viewport is read (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-fxl-xhtml-icb_multi_declarations': (F, "the first of two viewport metas is the one used (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-fxl-xhtml-icb_repeated-in-meta': (F, "the first width and height are used (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-fxl-xhtml-icb_units': (F, "units are ignored, values in pixels (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-page-layout-both': (T, ''),
    'lay-page-layout-both-spread': (T, 'the reflowable item with page-spread-left starts on the left; page-spread-right on a reflowable item is not placed on the right (not tested by the suite)'),
    'lay-pkg-flow-paginated': (T, 'paginated is the default'),
    'lay-pkg-flow-scrolled-continuous': (T, 'a book that asks for scrolled flow is scrolled until the reader chooses Pages (the Page setting starts as the book\'s)'),
    'lay-pkg-flow-scrolled-doc': (T, 'a book that asks for scrolled flow is scrolled until the reader chooses Pages (the Page setting starts as the book\'s)'),
    'lay-pp-embedded-images': (T, 'measured: each image fills its page'),
    'lay-pp-embedded-images-svg': (T, 'the images inside the SVG are shown'),
    'lay-pp-images-in-spine': (T, 'an image in the spine is replaced by its fallback and never read as text; no crash (the 3 MB PNG)'),
    'lay-pp-images-mixed': (T, 'an image in the spine is replaced by its fallback; no hang'),
    'lay-pp-layout-default': (T, ''),
    'lay-pp-layout-pre-paginated': (T, ''),
    'lay-pp-layout-pre-paginated-spreads': (T, 'pages meet with no gap, measured'),
    'lay-pp-page-spread-combined': (T, 'measured'),
    'lay-pp-page-spread-left': (T, 'measured'),
    'lay-pp-page-spread-right': (T, 'measured'),
    'lay-pp-spine-overrides_behave-as-global': (T, ''),
    'lay-pp-spine-overrides_behave-as-global-bis': (T, ''),
    'lay-pp-spine-overrides_image-only-pp': (T, ''),
    'lay-pp-spine-overrides_image-only-reflow': (T, ''),
    'lay-pp-spine-overrides_image-spine-pp': (T, 'the PNG spine item is replaced by its fallback'),
    'lay-pp-spine-overrides_image-spine-reflow': (T, 'the PNG spine item is replaced by its fallback'),
    'lay-pp-spread-none': (T, 'one page a screen, measured'),
    'lay-pp-svg-icb_multi': (T, 'an SVG spine document is drawn as a picture whose viewBox sets its size, clipped to it'),
    'lay-pp-xhtml-icb': (F, "the viewport is read (900x600, measured) but the pass criterion is a grid the book's CSS draws, and the CSS is dropped by design"),
    'lay-pp-xhtml-icb_invalid_meta': (F, "an invalid viewport meta is read as 900x600 (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-pp-xhtml-icb_multi': (F, "each page's own viewport is read (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-pp-xhtml-icb_multi_declarations': (F, "the first of two viewport metas is the one used (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-pp-xhtml-icb_repeated-in-meta': (F, "the first width and height are used (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-pp-xhtml-icb_units': (F, "units are ignored, values in pixels (measured) but the pass criterion is drawn by the book's CSS, dropped by design"),
    'lay-reflow-align-x-center': (N, 'rendition:align-x-center is optional for reflowable content ("reading systems that support it") and Quire does not'),
    'lay-rendition-flow-pre-pag': (T, 'rendition:flow is ignored everywhere'),
    'lay-roll-embedded-images': (T, 'a roll layout (EPUB 3.4 draft) is read scrolled down: each document scrolls, and the next follows at its end; not one strip across documents'),
    'lay-roll-embedded-images-svg': (T, 'a roll layout is read scrolled down (as lay-roll-embedded-images)'),
    'lay-roll-images-in-spine': (T, 'an image in the spine is replaced by its fallback, no crash'),
    'lay-roll-images-mixed': (T, 'an image in the spine is replaced by its fallback, no hang'),
    'lay-viewport-meta-prop': (T, 'only the dimensions of the viewport are read (measured)'),
    # Media Overlays
    'mol-audio': (T, 'clipBegin/clipEnd obeyed (MP3)'),
    'mol-audio-exceeding-clipend': (T, 'MP3'),
    'mol-audio-no-clipbegin': (T, 'MP3'),
    'mol-audio-no-clipend': (T, 'MP3'),
    'mol-css': (F, "the phrase is marked by Quire's own highlight; media:active-class and the book's CSS (green background) are not applied"),
    'mol-ignore': (N, 'only for reading systems that do not support media overlays'),
    'mol-navigation': (T, 'a jump through the contents moves the narration (MP3)'),
    'mol-support_xhtml': (T, 'the suite\'s MP4 audio was replaced by the same sound as MP3 in the run: Playwright\'s Chromium has no AAC decoder'),
    'mol-support_xhtml-fxl': (T, 'run with the MP4 audio replaced by MP3 (no AAC in Playwright\'s Chromium)'),
    'mol-support_xhtml-load': (T, 'run with the MP4 audio replaced by MP3 (no AAC in Playwright\'s Chromium)'),
    'mol-support_xhtml-load-fxl': (T, 'run with the MP4 audio replaced by MP3 (no AAC in Playwright\'s Chromium)'),
    'mol-support_xhtml-load-next': (T, 'run with the MP4 audio replaced by MP3 (no AAC in Playwright\'s Chromium)'),
    'mol-support_xhtml-load-next-fxl': (T, 'run with the MP4 audio replaced by MP3 (no AAC in Playwright\'s Chromium)'),
    'mol-timing-synchronization': (T, 'run with the MP4 audio replaced by MP3 (no AAC in Playwright\'s Chromium)'),
    'mol-timing-synchronization_fxl': (T, 'MP3'),
    'mol-timing-synchronization_multiple_audio': (T, 'MP3'),
    'mol-timing-synchronization_multiple_audio-fxl': (T, 'MP3'),
    'mol-timing-synchronization_svg': (T, 'the text of the SVG is read and marked (the drawing is not shown); MP3'),
    'mol-timing-synchronization_svg-fxl': (T, 'the text of the SVG is read and marked (the drawing is not shown); MP3'),
    'mol-tts_multi': (T, 'a SMIL with no audio hands the chapter to reading aloud by speech synthesis, from the page; the SMIL\'s order and its highlight are not used'),
    'mol-tts_single': (T, 'a SMIL with no audio hands the chapter to reading aloud by speech synthesis, from the page; the SMIL\'s order and its highlight are not used'),
    # Navigation Documents
    'nav-access': (T, ''),
    'nav-activation': (T, ''),
    'nav-non-text_img': (T, 'a navigation link holding an image is labelled by its alt text'),
    'nav-non-text_img_title': (T, 'a navigation link holding an image is labelled by its alt text, else its title'),
    'nav-spine_in-spine': (T, ''),
    'nav-spine_in-spine-hidden-toc-css': (F, "the navigation document in the spine shows the entry its CSS hides (display:none): the book's CSS is dropped by design; the contents panel lists both, as asked"),
    'nav-spine_in-spine-hidden-toc-html': (T, 'the navigation document in the spine hides the entry its hidden attribute hides, and the contents panel lists both'),
    'nav-spine_in-spine-no-list-style': (T, 'the contents panel is not numbered'),
    'nav-spine_not-in-spine': (T, ''),
    # Open Container Format
    'ocf-font_obfuscation': (F, "the book's own CSS is dropped by design, so an embedded font is never used"),
    'ocf-font_obfuscation_bis': (T, 'the font is not displayed (no embedded font is ever used)'),
    'ocf-metainf-inc': (T, ''),
    'ocf-metainf-manifest': (T, ''),
    'ocf-package_arbitrary': (T, ''),
    'ocf-package_multiple': (T, ''),
    'ocf-url_link-leaking-relative': (T, ''),
    'ocf-url_link-path-absolute': (T, 'a path-absolute address ("/OEBPS/images/photograph.png") is resolved from the container root, for images and links'),
    'ocf-url_link-relative': (T, ''),
    'ocf-url_manifest': (T, ''),
    'ocf-url_origin': (N, 'needs scripting, which Quire does not run'),
    'ocf-url_parse-leaking-relative': (N, 'needs scripting, which Quire does not run'),
    'ocf-url_parse-path-absolute': (N, 'needs scripting, which Quire does not run'),
    'ocf-zip-comp': (T, 'an archive with an entry compressed by anything but Deflate or stored is refused (the suite\'s EPUB is built with Deflate, so it cannot show the case; the e2e test makes a bzip2 entry)'),
    'ocf-zip-mult': (T, 'an archive whose end record names more than one disk is refused (the suite\'s EPUB is one zip; the e2e test makes a split archive\'s end record)'),
    # Package Documents
    'pkg-collections-unknown': (T, ''),
    'pkg-creator-order': (T, 'the first dc:creator is used'),
    'pkg-dir-auto_root-rtl': (T, 'the title is shown with a left to right base, as the test says it should be (dir=auto, first letter Latin)'),
    'pkg-dir-auto_root-unset': (T, 'the title is shown with a left to right base, as the test says it should be'),
    'pkg-dir_but_not_content': (F, "a Hebrew book's page is set right to left, as its reading direction is (by decision, quire#416: a book in Hebrew or Arabic whose spine names no direction reads right to left, as Readium reads it; the page is one CSS column flow, so its direction is the columns' order, and a list or a paragraph in the book inherits it). The suite's pass criterion is a content document with no dir staying left to right, which 13 of the 13 reading systems that answered meet by laying each document out on its own; Quire's single flow cannot without giving up the Hebrew heuristic or marking every block"),
    'pkg-dir_creator-rtl': (T, "a dc:creator's dir is read and shown on the library card"),
    'pkg-dir_rtl-root-ltr': (T, "a dc:title's own dir outranks the package's, on the library card"),
    'pkg-dir_rtl-root-unset': (T, "a dc:title's dir is read and shown on the library card"),
    'pkg-dir_unset-root-rtl': (T, "the package's dir is the title's and the creator's when they have none, on the library card"),
    'pkg-dir_unset-root-unset': (T, 'the title is shown left to right, as the test says it should be'),
    'pkg-lang_but_not_content': (F, "the OPF's dc:language is the page's language where the chapter names none, so a q gets French quotation marks in a French book (by decision: browsers hyphenate and pick quotation marks only for text whose language is known, and the package's language is the only one a book declares; the earlier test in reader.spec.js holds it, and a book that names none is 'und', not English). 11 of the 15 reading systems that answered show a content document with no language in their own, the suite's criterion"),
    'pkg-linked-records': (T, ''),
    'pkg-manifest-unknown': (T, ''),
    'pkg-manifest-unlisted-resource': (F, 'an image the manifest does not list is shown: the zip is read by name, not by the manifest'),
    'pkg-meta-unknown': (T, ''),
    'pkg-meta-whitespace': (T, 'shown with single spaces (HTML collapses them); the title and author are stored with the spaces as written, so a search or sort sees them'),
    'pkg-spine-duplicate-item-hyperlink': (T, 'a link to the document goes to its first place in the spine'),
    'pkg-spine-duplicate-item-rendering': (T, 'three places of the document, measured by progress'),
    'pkg-spine-duplicate-item-ui': (T, 'three bookmarks, one for each place'),
    'pkg-spine-nonlinear-activation': (T, ''),
    'pkg-spine-order': (T, ''),
    'pkg-spine-order-svg': (T, 'the text of each page, in order (the drawings are not shown)'),
    'pkg-spine-progression-default': (T, ''),
    'pkg-spine-progression-pre-paginated': (T, ''),
    'pkg-spine-progression_ltr': (T, ''),
    'pkg-spine-progression_rtl': (T, ''),
    'pkg-spine-unknown': (T, ''),
    'pkg-title-order': (T, 'the first dc:title is used'),
    'pkg-unique-id': (T, 'two books with the one identifier are two cards'),
    'pkg-unique-id_duplicate': (T, 'two books with the one identifier are two cards'),
    'pkg-version-backward': (T, ''),
    # Structural Semantics
    'pss-support': (T, 'a note link opens the note in a popup (#414)'),
    'pss-support_ignore-title': (T, 'a title element marked as a footnote is not a note: the link to it opens no popup (the head is not searched)'),
    # Core Media Types
    'pub-cmt-avif': (T, ''),
    'pub-cmt-gif': (T, ''),
    'pub-cmt-jpeg': (T, ''),
    'pub-cmt-jxl': (F, "the image is not decoded: Chromium (and Android's WebView) have no JPEG XL decoder"),
    'pub-cmt-mp3': (T, 'an audio element is made with the browser\'s controls and the book\'s entry as its source (MP3 is played by the engine; Chromium\'s headless build, which the e2e suite runs, has no AAC decoder, so the e2e test plays the mp3 and checks the controls of all)'),
    'pub-cmt-mp4': (T, 'an audio element is made with the browser\'s controls and the book\'s entry as its source (AAC in MP4 is played by the engine; Chromium\'s headless build, which the e2e suite runs, has no AAC decoder, so the e2e test plays the mp3 and checks the controls of all)'),
    'pub-cmt-opus': (T, 'an audio element is made with the browser\'s controls and the book\'s entry as its source (Opus is played by the engine; Chromium\'s headless build, which the e2e suite runs, has no AAC decoder, so the e2e test plays the mp3 and checks the controls of all)'),
    'pub-cmt-png': (T, ''),
    'pub-cmt-svg': (T, ''),
    'pub-cmt-webp': (T, ''),
    # Publication Resources, Manifest Fallbacks
    'pub-data-urls_browsing-context': (T, 'an img with a data: URL of png, jpeg, gif, webp or svg in base64 is shown (decoded here, up to 512 KiB of text); not offered to the image viewer'),
    'pub-data-urls_top-level-content': (T, 'an img with a data: URL is shown as the reflowable case is (measured on a reflowable page, not on a fixed-layout one)'),
    'pub-external-links': (T, 'a link out asks first, in the note overlay, and opens in a new tab on the reader\'s word'),
    'pub-external-links_consent': (T, 'a mailto: link asks first, in the note overlay, and opens the mail application on the reader\'s word'),
    'pub-file-urls': (T, 'iframes are not shown, so no file: URL is loaded'),
    'pub-foreign_bad-fallback': (T, 'an item and a fallback that are both foreign are left out of the spine, never shown as text'),
    'pub-foreign_image': (T, 'an img of a foreign type is shown as its manifest fallback'),
    'pub-foreign_json-spine': (T, 'the fallback is shown in place of the JSON item'),
    'pub-foreign_xml-spine': (T, 'the fallback is shown in place of the XML item'),
    'pub-foreign_xml-suffix-spine': (T, 'the fallback is shown in place of the XML item'),
    'pub-xml-external-id': (T, 'the entity is not resolved'),
    'pub-xml-names': (T, 'a content document with an invalid element name (a::b) is reported as an error when its chapter is opened'),
    'pub-xml-non-validating_comment': (T, ''),
    'pub-xml-non-validating_unclosed': (T, 'a content document with an unclosed element is reported as an error when its chapter is opened'),
    # Scripting
    'scr-not-support_ccscript-modify-host': (N, 'Quire runs no scripts and shows no iframes'),
    'scr-not-support_ccscript-modify-size': (N, 'Quire runs no scripts and shows no iframes'),
    'scr-readingsystem-features': (N, 'Quire runs no scripts (no epubReadingSystem object)'),
    'scr-readingsystem-support': (N, 'Quire runs no scripts (no epubReadingSystem object)'),
    'scr-readingsystem-support_iframe': (N, 'Quire runs no scripts and shows no iframes'),
    'scr-readingsystem-support_iframe_svg': (N, 'Quire runs no scripts and shows no iframes'),
    'scr-readingsystem-support_svg': (N, 'Quire runs no scripts'),
    'scr-storage-delete': (N, 'Quire runs no scripts: nothing is stored by a book'),
    'scr-support': (N, 'Quire runs no scripts, by policy'),
    'scr-support-fallback': (T, 'a scripted item with a fallback is replaced by the fallback (no scripts are run)'),
    'scr-support_iframe': (N, 'Quire runs no scripts and shows no iframes'),
    'scr-support_origin': (N, 'Quire runs no scripts'),
    'scr-support_origin_unique': (N, 'Quire runs no scripts'),
    'scr-support_scrolled-continuous': (N, 'only for reading systems that run scripts'),
    'scr-support_scrolled-doc': (N, 'only for reading systems that run scripts'),
    'scr-support_svg': (N, 'Quire runs no scripts'),
    'sec-untrusted-consent_network': (T, 'no remote resource is requested, with or without consent (measured: no request left the page)'),
    'sec-untrusted-consent_scripting': (T, 'no script is run, with or without consent'),
}

LEVELS = ('must', 'should', 'may', 'deprecated')


def read_tests(clone):
    ns = {'o': 'http://www.idpf.org/2007/opf', 'dc': 'http://purl.org/dc/elements/1.1/'}
    tests = {}
    for name in sorted(os.listdir(os.path.join(clone, 'tests'))):
        path = os.path.join(clone, 'tests', name, 'EPUB', 'package.opf')
        if not os.path.exists(path) or name.startswith('xx-'):
            continue
        root = ET.parse(path).getroot()
        level = 'must'
        for meta in root.iter('{%s}meta' % ns['o']):
            if meta.get('property') == 'belongs-to-collection':
                level = (meta.text or '').strip().lower()
        description = re.sub(r'\s+', ' ', root.find('.//dc:description', ns).text or '').strip()
        tests[name] = {'level': level, 'description': description, 'section': root.find('.//dc:coverage', ns).text}
    return tests


def others(clone):
    """For each test: how many reading systems of the suite's reports pass it, of those that answered"""
    seen = {}
    for path in glob.glob(os.path.join(clone, 'epub33', 'reports', '*.json')) + glob.glob(os.path.join(clone, 'reports', '*.json')):
        try:
            tests = json.load(open(path)).get('tests', {})
        except ValueError:
            continue
        for test, result in tests.items():
            if result is True or result is False:
                passed, answered = seen.get(test, (0, 0))
                seen[test] = (passed + (1 if result else 0), answered + 1)
    return seen


# failures left for the maintainer's decision, not bugs to fix
DECISIONS = {'mol-css'}


def covered(spec):
    """The suite's ids each e2e test of the spec names, in its title"""
    ids = {}
    for title in re.findall(r"^test\('([^']+)'", open(spec).read(), re.M):
        match = re.match(r'(.*?) \((must|should|may)\): (.*)', title)
        if match:
            for id in match.group(1).split(', '):
                ids[id] = title
    return ids


def main(clone):
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    tests = read_tests(clone)
    missing = sorted(set(tests) - set(VERDICTS))
    extra = sorted(set(VERDICTS) - set(tests))
    if missing or extra:
        sys.exit(f'tests with no verdict: {missing}; verdicts for no test: {extra}')
    commit = subprocess.check_output(['git', '-C', clone, 'rev-parse', 'HEAD'], text=True).strip()
    answers = others(clone)
    tested = covered(os.path.join(root, 'e2e', 'w3c-epub-tests.spec.js'))

    report = {
        'name': 'Quire',
        'variant': 'web build in Chromium 140 (desktop project; run of w3c/epub-tests at %s)' % commit[:10],
        'ref': 'https://github.com/bats-lang/quire',
        'tests': {id: VERDICTS[id][0] for id in sorted(tests)},
    }
    os.makedirs(os.path.join(root, 'reports'), exist_ok=True)
    with open(os.path.join(root, 'reports', 'quire.json'), 'w') as out:
        json.dump(report, out, indent=2, ensure_ascii=False)
        out.write('\n')

    def count(level, result):
        return sum(1 for id, t in tests.items() if (level is None or t['level'] == level) and VERDICTS[id][0] is result)

    lines = [
        '# Quire against the W3C EPUB 3 test suite (quire#419)',
        '',
        f'The suite is w3c/epub-tests at commit `{commit}`. Every test EPUB was built as `tests/generateEpubs.sh` builds it',
        '(`zip`, with the `mimetype` first), imported into Quire\'s web build in Playwright\'s Chromium (the desktop project, 1024 by 768)',
        'and opened, by `scripts/w3c-epub-tests-survey.mjs` (what the reader shows), `scripts/w3c-epub-tests-probe.mjs`',
        '(the contents panel, a link followed, two books in one library, the reading direction, bookmarks) and',
        '`scripts/w3c-epub-tests-narration.mjs` (Read aloud on each Media Overlays book). The verdicts are in',
        '`scripts/w3c-epub-tests-report.py`, which writes this file and `reports/quire.json`. The android project and the',
        'Android app itself were not run.',
        '',
        '## Counts',
        '',
        '| level | pass | fail | n/a | total |',
        '| --- | ---: | ---: | ---: | ---: |',
    ]
    for level in LEVELS:
        total = sum(1 for t in tests.values() if t['level'] == level)
        if total:
            lines.append(f'| {level} | {count(level, True)} | {count(level, False)} | {count(level, N)} | {total} |')
    lines.append(f'| all | {count(None, True)} | {count(None, False)} | {count(None, N)} | {len(tests)} |')
    lines += [
        '',
        'The suite lists `deprecated` tests (the `fxl-*` and `lay-fxl-*` ones, which the `lay-pp-*` ones replace); they are in',
        'the table too, and in `reports/quire.json`, as the suite\'s own template has them.',
        '',
        '## Failures',
        '',
        '"Others" is how many of the reading systems whose reports the suite holds pass the test, of those that answered.',
        '"e2e" is `yes` when `e2e/w3c-epub-tests.spec.js` holds a test that fails for it (none: a fix lands with its test); "policy" is a failure that follows from a',
        'decision of Quire\'s (the book\'s CSS is dropped; no scripts), not a bug: whether to keep the decision is the maintainer\'s.',
        '',
        '| test | level | why | others | e2e |',
        '| --- | --- | --- | ---: | --- |',
    ]
    for level in LEVELS:
        for id in sorted(tests):
            if tests[id]['level'] != level or VERDICTS[id][0] is not F:
                continue
            passed, answered = answers.get(id, (0, 0))
            policy = 'dropped by design' in VERDICTS[id][1] or 'not implemented' in VERDICTS[id][1] or 'by decision' in VERDICTS[id][1]
            platform = 'decoder' in VERDICTS[id][1]
            e2e = 'yes' if id in tested else ('policy' if policy else ('platform' if platform else ('decision' if id in DECISIONS else 'next')))
            lines.append(f'| `{id}` | {level} | {VERDICTS[id][1]} | {passed}/{answered} | {e2e} |')
    lines += [
        '',
        'A failure marked `next` is a bug whose e2e test is written with its fix, in the area of fixes it belongs to (so a branch',
        'carries only tests that pass). A `decision` is a failure settled in CLAUDE.md (#419) and kept: `mol-css` (the book\'s own highlight CSS,',
        'dropped by design, #411).',
    ]
    lines += ['', '## Not applicable', '', '| test | level | why |', '| --- | --- | --- |']
    for id in sorted(tests):
        if VERDICTS[id][0] is N:
            lines.append(f'| `{id}` | {tests[id]["level"]} | {VERDICTS[id][1]} |')
    lines += ['', '## Passing', '', 'Caveats of a pass, where there is one:', '']
    for id in sorted(tests):
        if VERDICTS[id][0] is T and VERDICTS[id][1]:
            lines.append(f'* `{id}`: {VERDICTS[id][1]}')
    lines.append('')
    passing = [id for id in sorted(tests) if VERDICTS[id][0] is T and not VERDICTS[id][1]]
    lines.append('Pass with nothing to add: ' + ', '.join(f'`{id}`' for id in passing) + '.')
    lines.append('')
    with open(os.path.join(root, 'reports', 'quire-w3c-epub-tests.md'), 'w') as out:
        out.write('\n'.join(lines))
    print(json.dumps({level: [count(level, True), count(level, False), count(level, N)] for level in LEVELS}), len(tests))


if __name__ == '__main__':
    main(sys.argv[1])
