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

What the browser and the Android app offer beyond the page (reading aloud, full
screen, the rotation lock, brightness, sharing, installing, keeping the storage,
the local time, files opened with the app) is quire's own logic on bridge's
typed atoms (each with its `*_available`, each JS answer decoded into a
datatype matched exhaustively), not pwa's page scripts (bats-lang/pwa#49): no
element carries a `data-pwa-*` marker and no rule keys on a `pwa-*` class. **A
control is shown only where its platform has it**, by its own `data-hide`.

* **Reading aloud** (`src/read_aloud.bats`). Read aloud (bottom bar) reads the
  chapter from the first sentence on the page (`placement`: `Before | OnPage |
  After`), Read from here from the sentence the selection starts in. A chapter's
  sentences are its `script` (`src/reader.bats`): the text of each block holding
  no other block, a ruby's `rt`, `rtc` and `rp` left out but their content nodes
  counted as render makes them, cut by bridge's `segment_sentences` in the
  book's language. Each is said by `speech_speak`, marked with `mark_range` as
  mark 5, and when the next starts past the page the page is turned by
  `reader_turn_on` (`TurnedPage | TurnedChapter | NotTurned`, at most 3 turns
  for one sentence; reading stops where nothing turns).
  * The state is one `aloud` (`Silent`, `Loading`, `Saying`, `Turning`,
    `Paused`); each run is numbered, so what an earlier run started is dropped.
  * A pause cancels what is said and says that sentence again on resume, when
    it is still on the page shown (else from the page's first), since
    `speechSynthesis.pause()` stops for good on Android's Chrome and after some
    15 s on desktop Chrome.
  * The speed (`speech_rate`, 0.75 to 2 times) and the voice of each language
    are kept with the settings outside the settings record (bytes of "S2", as
    `ruby` is), so they are not saved over settings that could not be read
    (`storage_savable`, #174). They, the brightness, the rotation lock and full
    screen are in the backup (`readingSpeed`, `voices`, `brightness`,
    `rotationLocked`, `fullScreen`) and reset with the settings, Undo putting
    them back (`set_reset_undoable`; `screen_controls_apply`).
  * Going to the library, opening another book or `pagehide` stops reading.
* **The screen** (`src/screen_controls.bats`, the reading settings' Page tab,
  quire#300). Full screen (`fullscreen_*`; in the app bridge hides both system
  bars) and Lock rotation (`orientation_*`) are switches (`_switch_row`).
  * In the app full screen is kept (quire#313): a `fullscreen_choice`, the
    device's own, after an "F" at the end of the "S2" record, changed by the
    switch (`screen_fullscreen_toggle`) and by nothing else. It is the setting
    for the immersive reading screen only (quire#348): the system's bars are
    hidden when it is on and the reader is shown with its own bars away
    (`_immersive`, set through `screen_immersive_set`), and shown in the
    library, the in-book menu and its panels. A browser keeps none (the
    Fullscreen API enters only at a click).
  * While the reader is immersive, a page shown hides the bars again
    (`_bars_hidden_again`), since Android brings them back at a swipe from the
    edge (quire#314).
  * The rotation lock is the Capacitor plugin's alone in the app (quire#355).
    `_lock` matches every `lock_outcome`: `LockRefused(text)` removes the row for
    the session and says in the banner what happened (`notice_rotation_refused`,
    the plugin's error kept as written in Copy details); `LockUnavailable`
    removes the row with no banner; `LockUnexpected(code)` goes through
    `notice_unexpected`.
  * Brightness (`brightness_*`, the app only, quire#392): a `brightness_choice`
    (the device's own or `BrightnessOwn`) with a level of 10 to 100 kept apart
    (`set_brightness_level`), in the one "S2" byte that held the old five levels
    (1 to 5 still read as 10, 25, 50, 75, 100). A slider changes the screen as
    it moves (`screen_brightness_moved`, no percentage shown), and a "Same as
    device" switch gives the screen back to the system.
  * `e2e/controls-shown.js` checks on every screen the layout spec walks that no
    control's text is cut and every toggle looks different on and off.
* **Sharing** (`src/sharing.bats`): the selection, quoted and cited
  (`share_text_answer`: shared and closed are not said; a failure, no way to share, a
  rejection and a throw each are a banner with their outcome as the code
  (`notice_share_failed`), an unexpected code `notice_unexpected`; keyword:
  share-text-answer); the annotations' Markdown file by `share_file` where files can
  be shared (`share_as`: `AsFile | AsText`), else, or on `FilesNotShareable`,
  as text.
* **Installing and keeping the storage** (`src/platform.bats`): Install Quire is
  shown while the browser offers it (`install_prompt_available`); the Home Screen
  hint shows on iOS Safari only (`is_ios_browser`). The storage is asked to be
  kept (`storage_persist`) once, after the first book is imported; in a browser
  Settings says whether it is (`settings-storage`), and in the app nothing is
  said (#333).
* **The local time** (`src/local_time.bats`): the offset from UTC and whether it
  is night (22:00 to 07:00), for the auto theme (checked each minute while a
  book is open and at each page turn) and the statistics' local day.
* **Files opened with the app** (`launchQueue`, the share target, the Android
  app's files) arrive on bridge's external-file path, which the library imports
 ; pwa writes no JS of its own, so bridge's service worker
  keeps a file shared with the web app and `batsNative` entry points are what
  the Android activity calls. **They are asked for only once the stored library
  is read** (#262): `_external_wait` (`src/bin/quire.bats`) needs the proof
  `LIBRARY_READ`, which only `_library_read` makes, so a book is never added to
  the library the read then replaces. When the library could not be read each
  file is kept (`_handed_kept`, linear) and not added, and the banner says so.
