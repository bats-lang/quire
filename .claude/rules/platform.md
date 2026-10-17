---
paths:
  - src/platform.bats
  - src/read_aloud.bats
  - src/screen_controls.bats
  - src/sharing.bats
  - src/local_time.bats
  - src/bin/quire.bats
  - src/app.bats
  - e2e/safe-area*
  - e2e/image-viewer*
  - e2e/keys*
---

# The platform in Bats

## The platform, in Bats

What the browser and the Android app offer beyond the page (reading
aloud, full screen, the rotation lock, the brightness, sharing,
installing, keeping the storage, the local time, files opened with the
app) is quire's own logic, on bridge's typed atoms (each with its
`*_available`, and each JS answer decoded into a datatype that is
matched exhaustively), not pwa's page scripts (bats-lang/pwa#49): no
element carries a `data-pwa-*` marker and no rule keys on a `pwa-*`
class, so pwa's scripts act on nothing of quire's. A control is shown
only where its platform has it, by its own `data-hide`.

* **Reading aloud** (`src/read_aloud.bats`): Read aloud (the bottom
  bar) reads the chapter shown from the first sentence on the page
  (halving the sentences by where each starts against the page:
  `placement`, `Before | OnPage | After`, across as the book reads, down
  when scrolled), Read from here from the sentence the selection starts
  in. A chapter's sentences are its `script` (`src/reader.bats`): the
  text of each block holding no other block (a paragraph, a heading, a
  list item, a quotation, a term, a description, a caption, a cell,
  preformatted text), a ruby's `rt`, `rtc` and `rp` left out but their
  content nodes counted as render makes them (search and render's walk,
  a third time), cut by bridge's `segment_sentences` in the book's
  language; each sentence knows its text and where it is on the page
  (content node and UTF-16 offset at each end). Each is said by
  `speech_speak`, marked with `mark_range` as mark 5
  (`::highlight(bats-mark-5)`, the search hit's proven pair), and when
  the next one starts past the page the page is turned by
  `reader_turn_on` (the next page button's turn, as a promise of
  `turned`: `TurnedPage | TurnedChapter | NotTurned`), into the next
  chapter too, at most 3 turns for one sentence; reading stops where
  nothing turns. The state is one `aloud`: `Silent`, `Loading` (a
  script being made), `Saying` (a sentence, its utterance's number),
  `Turning` (a turn awaited, for a sentence or the chapter's end:
  `turn_for`) or `Paused`; each run is numbered, so what an earlier
  run started is dropped. A pause cancels what is said and says that
  sentence again on resume, when it is still on the page shown (else
  from the page's first): `speechSynthesis.pause()` stops for good on
  Android's Chrome and after some 15 s on desktop Chrome. Read aloud is
  pressed (`aria-pressed`) while it reads, and the screen kept awake
  (`keep_awake`; the reader keeps it awake anyway). The speed
  (`speech_rate`, 0.75 to 2 times) and the voice of each language (by
  the language's primary subtag, the voices whose language has it)
  are kept with the settings, outside the settings record (bytes 20
  and 23 on of "S2", as `ruby` is), so like them they are not saved
  over settings that could not be read (`storage_savable`, #174). They are settings like the others,
  and so are the brightness, the rotation lock and full screen: in the
  backup (`readingSpeed`, `voices`, `brightness`, `rotationLocked`,
  `fullScreen`) and reset
  with the settings, Undo putting them back (`set_reset_undoable`;
  `screen_controls_apply` sets the screen again). Going to the library, opening
  another book, or the page going away (`pagehide`) stops reading.
* **The screen** (`src/screen_controls.bats`, the reading settings'
  Page tab, a row each, quire#300): Full screen (`fullscreen_*`; in the
  app bridge hides both system bars, Capacitor's `SystemBars`, Android's
  immersive mode) and Lock rotation (`orientation_*`, a `rotation` kept
  with the settings and locked again as the app starts) are switches:
  a button named by its label, with a drawn track whose knob moves when
  it is pressed (`_switch_row` in `src/app.bats`), and a line saying
  what it does (`aria-describedby`). In the app full screen is kept
  (quire#313): a `fullscreen_choice` (`FullscreenOff | FullscreenOn`),
  the device's own, after an "F" at the end of the "S2" record, turned
  and kept by the switch (`screen_fullscreen_toggle`) and by nothing
  else, the switch saying it from the first frame
  (`screen_controls_start`). It is the setting for the immersive reading
  screen only (quire#348): the system's bars are hidden when the setting
  is on and the reader is shown with its own bars away (`_immersive`,
  set by quire.bats' `_chrome_set` and `_show_library` through
  `screen_immersive_set`), and shown in the library, in the in-book menu
  and its panels, and as the app starts; the setting is not changed by
  what the bars show, nor by the menu coming up. A browser keeps none:
  the Fullscreen API enters only at a click (the user's activation), so
  a page opened again starts out of it, its switch off, and a click
  there does not change what is kept, and the page is in full screen or
  not as that click left it.
  The rotation lock is the Capacitor plugin's alone in the app (bridge
  never takes the web API there, where Chromium's WebView has none; quire#355).
  `_lock` matches every `lock_outcome` with `case+`: `Locked`;
  `LockRefused(text)`, the plugin's rejection, which removes the row for
  the session and says in the banner what happened and what to do, the
  plugin's error kept as written in the Copy details (`notice_rotation_refused`,
  not a claim that the device cannot lock); `LockUnavailable`, nothing to
  lock with, which removes the row with no banner (availability is also
  decided before the tab is drawn, `screen_controls_show`); and
  `LockUnexpected(code)`, through `notice_unexpected`. A
  control that cannot work is not shown. While the reader is immersive and full screen is on, a page shown hides the
  bars again (`_bars_hidden_again` in `src/reader.bats`), since Android
  brings them back at a swipe from the edge, the reader's own way out of
  immersive mode (quire#314). pwa's activity reports each bar's
  visibility at each window insets dispatch (`batsNative.systemBars`,
  bridge's `listen_system_bars`, `RSystemBars`), which lays the chapter
  out again when it changes (quire#356). Brightness while reading
  (`brightness_*`, the app only, quire#392: a `brightness_choice`, the
  device's own or `BrightnessOwn`, with a level of 10 to 100 kept apart
  as the narration's speed is, `set_brightness_level`; kept with the
  settings, in the one byte of the "S2" record that held the five levels
  of the old select (1 to 5 still read as 10, 25, 50, 75, 100), and set
  again as the app starts) is a slider that changes the screen as it
  moves (`screen_brightness_moved`, on each `input` event, so the reader
  sees the brightness they choose and no percentage is shown), and a
  "Same as device" switch (`screen_brightness_system_toggle`) that gives
  the screen back to the system and, pressed again, to the level the
  slider shows.
  `e2e/controls-shown.js` checks, on every screen the layout spec walks,
  that no control's text is cut (a select's chosen option too) and that
  every toggle looks different on and off.
* **Sharing** (`src/sharing.bats`): the selection, quoted and cited
  ("“…”\n— Author, Title"), by `share_text`; the annotations' Markdown
  file (`annot_export` to `ToShare`) by `share_file` where files can be
  shared (`share_as`: `AsFile | AsText`), else, or when the platform
  refuses it as a file (`FilesNotShareable`), as its text.
* **Installing and keeping the storage** (`src/platform.bats`): Install
  Quire is shown while the browser offers to install the app
  (`install_prompt_available`, `listen_install_prompt`) and asks for it
  (`install_prompt`); the Home Screen hint shows on iOS Safari only
  (`is_ios_browser`, `src/library.bats`). The storage is asked to be
  kept (`storage_persist`) once, after the first book is imported, and
  in a browser a line of Settings, under Backup (`settings-storage`),
  says whether it is (`storage_persisted` at startup); the Android
  app's storage is its own, and there nothing is said (#333).
* **The local time** (`src/local_time.bats`): its offset from UTC
  (`timezone_offset_minutes`) and whether it is night (22:00 to 07:00,
  from `epoch_millis`), for the auto theme (checked each minute while a
  book is open, through the timer, and at each page turn) and the
  reading statistics' local day.
* **Files opened with the app** (`launchQueue`, the share target, the
  Android app's files) arrive on bridge's external-file path, which the
  library imports (`OnExternalFiles`); pwa writes no JS of its own
  (bats-lang/pwa#49), so bridge's service worker keeps a file shared
  with the installed web app, and bridge's `batsNative` entry points
  are what the Android activity calls. They are asked for only once
  the stored library is read (#262): `_external_wait` in
  `src/bin/quire.bats` needs the proof `LIBRARY_READ`, which only
  `_library_read` makes, after `lib_load`, so a book is never added
  to the library the read then replaces; until then the bridge keeps
  the files in their order. When the library could not be read, each
  file is kept (`_handed_kept`, linear) and not added, and the banner
  says so (when Try again is offered, they wait for it: see "A library
  that cannot be read says why").
