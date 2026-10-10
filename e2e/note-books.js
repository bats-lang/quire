// A small EPUB 3 book of notes of every marking and shape (#414), checked
// by epubcheck (e2e/epubcheck.spec.js).

const filler = Array.from({ length: 10 }, (_, k) => `<p>Filler ${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>').join('');
const ref = (n, type = 'epub:type="noteref"') => `<a ${type} href="#n${n}">${n}</a>`;
const longNote = Array.from({ length: 40 }, (_, k) => `<p>Long note paragraph ${k} ${'words and more words '.repeat(6)}</p>`).join('');

export const noteBooks = {
  notes: { valid: true, opts: {
    title: 'Notes of every kind', author: 'Notes', toc: [{ label: 'Notes', href: 'chapter1.xhtml' }],
    rawChapters: [
      { body:
        `<h1>Notes</h1>\n<p>One${ref(1)}, two${ref(2)}, four${ref(4)}, five${ref(5, 'role="doc-noteref"')}, six${ref(6, 'role="doc-noteref"')}, seven${ref(7)}.</p>\n` +
        '<p>An unmarked cross-reference: <a href="#t1">3</a> is followed as a link.</p>\n' +
        filler +
        '<aside epub:type="footnote" id="n1"><p>See <a href="#far">the far place</a>, <a href="https://example.com/x">the web</a> and <a href="#r1">↩</a>.</p></aside>\n' +
        `<aside epub:type="footnote" id="n2"><p>Second cites<a epub:type="noteref" href="#n3">3</a>.</p></aside>\n` +
        '<div role="doc-footnote" id="n3"><p>Third, a div.</p></div>\n' +
        '<p id="n4" hidden="">Hidden note text.</p>\n' +
        `<aside id="n5" role="doc-footnote">${longNote}</aside>\n` +
        '<section role="doc-endnotes"><ol><li id="n6" role="doc-endnote"><p>Sixth, an endnote in a list.</p></li></ol></section>\n' +
        '<aside epub:type="rearnote" id="n7"><p>Seventh, a rear note.</p></aside>\n' +
        '<p id="t1">A short paragraph a numeric link goes to.</p>\n' +
        filler + '<p id="far">Far target</p>' },
    ] } },
};

// the reference that note 1's backlink goes to
noteBooks.notes.opts.rawChapters[0].body = noteBooks.notes.opts.rawChapters[0].body.replace('One<a epub:type="noteref" href="#n1">1</a>', 'One<a epub:type="noteref" id="r1" href="#n1">1</a>');
