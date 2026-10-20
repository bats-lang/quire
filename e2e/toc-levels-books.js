// A book whose contents are nested to four levels (#690): the Contents panel must give the
// levels to assistive technology, not only to the eye.

const body = chapter => `<h1>Chapter ${chapter}</h1>\n<p>${'Text of the chapter. '.repeat(20)}</p>`;

export const tocLevelBooks = {
  /** Two parts, sections in them, a subsection and a detail: levels 0 to 3, one entry per chapter */
  fourLevels: { valid: true, opts: {
    title: 'Four Levels', author: 'Levels Tests', chapters: 7,
    rawChapters: [1, 2, 3, 4, 5, 6, 7].map(i => ({ body: body(i) })),
    toc: [
      { label: 'Part One', href: 'chapter1.xhtml', children: [
        { label: 'Section A', href: 'chapter2.xhtml', children: [
          { label: 'Subsection A1', href: 'chapter3.xhtml', children: [
            { label: 'Detail A1a', href: 'chapter4.xhtml' },
          ] },
        ] },
        { label: 'Section B', href: 'chapter5.xhtml' },
      ] },
      { label: 'Part Two', href: 'chapter6.xhtml', children: [
        { label: 'Section C', href: 'chapter7.xhtml' },
      ] },
    ] } },
};
