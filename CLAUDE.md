# quire

## To do: book memory in a rolling window of page arenas

Not done yet; this is the intended design, and it will take a good deal
of refactoring.

Everything that belongs to a book's content (chapter text, pictures and
other images, per-page layout data) is allocated from arenas (array's
`arena_create` / `arena_alloc`), not with `alloc`. `alloc` is bounded at
1 MiB on purpose, to limit fragmentation (see array's CLAUDE.md), and a
page's content does not belong in scattered long-lived allocations.

* One arena per page, sized to hold a page with generous limits for
  images and the like.
* Five arenas live at a time: the current page, the 2 pages before it and
  the 2 after it.
* Turning forward one page releases the arena of the page that is now 3
  back and prepares the arena of the page that is now 2 ahead (turning
  back does the mirror image): a rolling window.
* Arenas are created and destroyed whole and never reused piecemeal, so
  they cannot fragment.

The point of doing this in ATS2 rather than Rust is that the arena
discipline is checked at compile time:

* a piece that does not fit its page's arena does not type-check;
* a page's pieces cannot be freed on their own, or given back to
  another page's arena;
* a page's arena cannot be released while any of its pieces is still in
  use (the arena's outstanding count must be 0), so nothing on screen
  can point into a released page.

The window itself should be in the types too: the reader state holds
exactly the five arenas, indexed by page number, so a page outside the
window has no arena to allocate from.
