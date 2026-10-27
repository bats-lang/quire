# Fixtures of other reading systems' CFIs

* `epubjs-chapter1.xhtml`: `test/fixtures/chapter1.xhtml` of futurepress/epub.js
  at eee359d0790002115a1156a9833c54f4bcd44c1d (BSD-2-Clause, Copyright (c)
  2013, FuturePress). The CFIs it is read with are the strings that epub.js's
  `test/epubcfi.js` asserts for it (`#fromNode()`, `#fromRange()`).
* The KOReader strings in `src/bin/cfi.bats` are those of `spec/unit/readerhighlight_spec.lua`
  of koreader/koreader at c07752e8c8575ff83888347b96b74586337bc093 (the book itself is
  not copied; the chapter they are read against is built in the test to have the
  shape their steps name).
* The specification's examples are those of https://idpf.org/epub/linking/cfi/
  (EPUB Canonical Fragment Identifiers 1.1, "Examples"); the range
  `epubcfi(/6/4[chap01ref]!/4[body01]/10[para05],/2/1:1,/3:4)` is also the one
  of Readium's annotations specification (https://github.com/readium/annotations).
