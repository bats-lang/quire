(* app -- the app's elements, made once at startup *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A

staload "ui.sats"
staload "style.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload "version.sats"

fn _hide {id_len:pos | id_len < 256} (id: string id_len): void = ui_show(id, false)

(* Each element made again to reset it is made only here, so each id is
   made at one place (tests/static/ids.py) *)

(* The import button's file input, with no file chosen *)
#pub fn app_import_input (): void
implement app_import_input () =
  ui_file_input("import-button", "import-file", "Import EPUB", ".epub,application/epub+zip", true)

(* The Settings screen's backup file input, with no file chosen *)
#pub fn app_backup_input (): void
implement app_backup_input () =
  ui_file_input("settings-restore", "backup-file", "Restore backup", ".json,application/json", false)

(* The dictionaries' file input, with no file chosen: a dictionary's
   files are picked together *)
#pub fn app_dictionary_input (): void
implement app_dictionary_input () =
  ui_file_input("dictionary-import", "dictionary-file", "Import dictionary", ".ifo,.idx,.dict,.dz,.syn", true)

(* The fields that add a catalogue, empty: its name and its address *)
#pub fn app_catalogue_form (): void
implement app_catalogue_form () = let
  val () = ui_clear("catalogue-form")
  val () = ui_field("catalogue-form", "catalogue-name", FLine, "mname", "Catalogue name")
in ui_field("catalogue-form", "catalogue-address", FLine, "mname", "Catalogue URL") end

(* The catalogue's search field, empty, and its button *)
#pub fn app_catalogue_search (): void
implement app_catalogue_search () = let
  val () = ui_clear("catalogue-search-bar")
  val () = ui_field("catalogue-search-bar", "catalogue-search", FSearch, "search", "Search the catalogue")
in ui_text_btn("catalogue-search-bar", "catalogue-search-go", "btn", "Search") end

(* The library's search field, empty, and its (hidden) clear button *)
#pub fn app_library_search (): void
implement app_library_search () = let
  val () = ui_clear("library-search-box")
  val () = ui_field("library-search-box", "library-search", FSearch, "search", "Search the library")
  val () = ui_icon_btn("library-search-box", "library-search-clear", "ibtn sclear", IcClose, "Clear search")
in _hide("library-search-clear") end

(* The book search's field, empty, and its close button *)
#pub fn app_book_search (): void
implement app_book_search () = let
  val () = ui_clear("search-header")
  val () = ui_field("search-header", "search-field", FSearch, "search", "Search in book")
in ui_icon_btn("search-header", "search-close", "ibtn", IcClose, "Close search") end

(* The library view: toolbar, import progress, the list of books and the
   empty-library message *)
fn _library (): void = let
  val () = ui_el("bats-root", "library", TDiv, "lib")
  val () = ui_role("library", RMain)
  val () = ui_el("library", "library-bar", TDiv, "bar")
  val () = ui_el("library-bar", "library-title", TH1, "ttl")
  val () = ui_text("library-title", "Quire")
  val () = ui_text_btn("library-bar", "shelf-button", "btn", "Library")
  val () = ui_text_btn("library-bar", "sort-button", "btn", "Sort: Last opened")
  val () = ui_el("library-bar", "import-button", TDiv, "btn btn-p")
  val () = app_import_input()
  val () = ui_icon_btn("library-bar", "library-menu-button", "ibtn", IcGear, "Library menu")
  val () = ui_el("library-bar", "library-search-box", TDiv, "sfield")
  val () = app_library_search()
  (* on iOS Safari (the stylesheet shows it only there), once the
     library has a book: installing is how its books are kept *)
  val () = ui_el("library", "install-hint", TDiv, "ihint")
  val () = ui_role("install-hint", RStatus)
  val () = ui_add("install-hint", "install-hint-text", TSpan)
  val () = ui_text("install-hint-text", "Add Quire to your Home Screen to keep your books: tap Share, then Add to Home Screen.")
  val () = ui_text_btn("install-hint", "install-hint-dismiss", "btn", "Got it")
  (* import progress *)
  val () = ui_el("library", "import-progress", TDiv, "imp")
  val () = ui_role("import-progress", RStatus)
  val () = ui_el("import-progress", "import-count", TDiv, "imp-n")
  val () = ui_el("import-progress", "import-status", TDiv, "imp-s")
  val () = ui_el("import-progress", "import-bar", TDiv, "imp-bar")
  val () = ui_el("import-bar", "import-fill", TDiv, "imp-fill")
  val () = _hide("import-progress")
  (* the view: which books, and as a list or a grid of covers *)
  val () = ui_el("library", "library-view", TDiv, "lview")
  val () = ui_el("library-view", "filter-books", TDiv, "seg")
  val () = ui_named("filter-books", NGroup, "Show")
  val () = ui_text_btn("filter-books", "filter-books-all", "sbtn", "All")
  val () = ui_text_btn("filter-books", "filter-unread", "sbtn", "Unread")
  val () = ui_text_btn("filter-books", "filter-reading", "sbtn", "Reading")
  val () = ui_text_btn("filter-books", "filter-finished", "sbtn", "Finished")
  val () = ui_el("library-view", "view-choice", TDiv, "seg vseg")
  val () = ui_named("view-choice", NGroup, "View")
  val () = ui_text_btn("view-choice", "view-list", "sbtn", "List")
  val () = ui_text_btn("view-choice", "view-grid", "sbtn", "Grid")
  (* the reader's collections: shown once there is one *)
  val () = ui_el("library-view", "collection-row", TDiv, "crow")
  val () = ui_el("collection-row", "collection-chips", TDiv, "seg")
  val () = ui_named("collection-chips", NGroup, "Collection")
  val () = ui_text_btn("collection-row", "collection-rename", "btn", "Rename")
  val () = ui_text_btn("collection-row", "collection-delete", "btn", "Delete collection")
  val () = _hide("collection-row")
  (* the book last opened and not finished *)
  val () = ui_el("library", "continue-reading", TDiv, "cont")
  val () = ui_named("continue-reading", NRegion, "Continue reading")
  val () = ui_el("continue-reading", "continue-title", TDiv, "conth")
  val () = ui_text("continue-title", "Continue reading")
  val () = ui_el("continue-reading", "continue-list", TDiv, "list")
  val () = _hide("continue-reading")
  (* the books *)
  val () = ui_el("library", "book-list", TDiv, "list")
  val () = ui_named("book-list", NRegion, "Books")
  val () = ui_el("library", "library-empty", TDiv, "empty")
in ui_text("library-empty", "Import an EPUB file to start reading.") end

(* The book menu (its More button, a right-click or a long press on a
   card) *)
fn _context_menu (): void = let
  val () = ui_el("bats-root", "card-menu", TDiv, "ovl")
  val () = ui_el("card-menu", "card-menu-box", TDiv, "menu")
  val () = ui_named("card-menu-box", NMenu, "Book menu")
  val () = ui_menuitem("card-menu-box", "card-menu-info", "Book info")
  val () = ui_menuitem("card-menu-box", "card-menu-collections", "Collections")
  val () = ui_menuitem("card-menu-box", "card-menu-hide", "Hide")
  val () = ui_menuitem("card-menu-box", "card-menu-archive", "Archive")
  val () = ui_menuitem("card-menu-box", "card-menu-trash", "Move to Trash")
in _hide("card-menu") end

(* A book's collections: a toggle for each, and a new one *)
fn _collections (): void = let
  val () = ui_el("bats-root", "collections-menu", TDiv, "ovl")
  val () = ui_el("collections-menu", "collections-box", TDiv, "menu")
  val () = ui_labelled("collections-box", NDialog, "collections-title")
  val () = ui_el("collections-box", "collections-title", TDiv, "mtitle")
  val () = ui_text("collections-title", "Collections")
  val () = ui_el("collections-box", "collections-none", TDiv, "cnone")
  val () = ui_text("collections-none", "No collections yet")
  val () = ui_el("collections-box", "collections-list", TDiv, "seg cseg")
  val () = ui_text_btn("collections-box", "collections-new", "btn", "New collection")
  val () = ui_text_btn("collections-box", "collections-done", "btn btn-p", "Done")
in _hide("collections-menu") end

(* A labelled number of the reading statistics *)
fn _stat {row_id_len,label_id_len,value_id_len:pos | row_id_len < 256; label_id_len < 256; value_id_len < 256}{label_len:pos | label_len < 256}
  (row_id: string row_id_len, label_id: string label_id_len, value_id: string value_id_len, label: string label_len): void = let
  val () = ui_el("stats-box", row_id, TDiv, "srow")
  val () = ui_add(row_id, label_id, TSpan)
  val () = ui_text(label_id, label)
in ui_add(row_id, value_id, TB) end

(* The reading statistics: the time read today, this week, the days
   read in a row and the books finished this year, and the daily goal *)
fn _stats (): void = let
  val () = ui_el("bats-root", "stats-panel", TDiv, "ovl")
  val () = ui_el("stats-panel", "stats-box", TDiv, "menu")
  val () = ui_labelled("stats-box", NDialog, "stats-title")
  val () = ui_el("stats-box", "stats-title", TDiv, "mtitle")
  val () = ui_text("stats-title", "Reading statistics")
  val () = _stat("stats-today-row", "stats-today-label", "stats-today", "Today")
  val () = _stat("stats-week-row", "stats-week-label", "stats-week", "Last 7 days")
  val () = _stat("stats-streak-row", "stats-streak-label", "stats-streak", "Days in a row")
  val () = _stat("stats-finished-row", "stats-finished-label", "stats-finished", "Finished this year")
  val () = ui_el("stats-box", "stats-goal-title", TDiv, "a11yg")
  val () = ui_text("stats-goal-title", "Daily goal")
  val () = ui_el("stats-box", "stats-goal", TDiv, "seg")
  val () = ui_named("stats-goal", NGroup, "Daily goal")
  val () = ui_text_btn("stats-goal", "stats-goal-off", "sbtn", "Off")
  val () = ui_text_btn("stats-goal", "stats-goal-10", "sbtn", "10 min")
  val () = ui_text_btn("stats-goal", "stats-goal-20", "sbtn", "20 min")
  val () = ui_text_btn("stats-goal", "stats-goal-30", "sbtn", "30 min")
  val () = ui_text_btn("stats-goal", "stats-goal-60", "sbtn", "1 h")
  val () = ui_text_btn("stats-box", "stats-done", "btn btn-p", "Done")
in _hide("stats-panel") end

(* The dictionaries Look up reads without a connection: each one's
   name and language with Remove, and the import of another (its
   language chosen first, then its files) *)
fn _dictionaries (): void = let
  val () = ui_el("bats-root", "dictionaries-panel", TDiv, "ovl")
  val () = ui_el("dictionaries-panel", "dictionaries-box", TDiv, "menu")
  val () = ui_labelled("dictionaries-box", NDialog, "dictionaries-title")
  val () = ui_el("dictionaries-box", "dictionaries-title", TDiv, "mtitle")
  val () = ui_text("dictionaries-title", "Dictionaries")
  val () = ui_el("dictionaries-box", "dictionaries-none", TDiv, "cnone")
  val () = ui_text("dictionaries-none", "No dictionaries yet")
  val () = ui_add("dictionaries-box", "dictionaries-list", TDiv)
  val () = ui_el("dictionaries-box", "dictionary-language-row", TDiv, "srow")
  val () = ui_el("dictionary-language-row", "dictionary-language-label", TSpan, "slabel")
  val () = ui_text("dictionary-language-label", "Language")
  val () = ui_field("dictionary-language-row", "dictionary-language", FChoice, "ssel", "Dictionary language")
  val () = ui_el("dictionaries-box", "dictionary-import", TDiv, "mi btn")
  val () = app_dictionary_input()
  val () = ui_el("dictionaries-box", "dictionaries-status", TDiv, "cnone")
  val () = ui_role("dictionaries-status", RStatus)
  val () = ui_text_btn("dictionaries-box", "dictionaries-done", "btn btn-p", "Done")
in _hide("dictionaries-panel") end

(* A word looked up in a dictionary, over the page: the headword, its
   article (as text), the dictionary's name, the same word looked up
   online, and Close *)
fn _dictionary (): void = let
  val () = ui_el("bats-root", "dictionary-panel", TDiv, "sheet")
  val () = ui_named("dictionary-panel", NDialog, "Dictionary")
  val () = ui_el("dictionary-panel", "dictionary-word", TDiv, "mtitle")
  val () = ui_el("dictionary-panel", "dictionary-article", TDiv, "fntext dart")
  val () = ui_el("dictionary-panel", "dictionary-source", TDiv, "hstyle")
  val () = ui_el("dictionary-panel", "dictionary-bar", TDiv, "srow sfoot")
  val () = ui_link_out("dictionary-bar", "dictionary-online", "btn linkout", "Look up online")
  val () = ui_el("dictionary-bar", "dictionary-spacer", TSpan, "grow")
  val () = ui_text_btn("dictionary-bar", "dictionary-close", "btn", "Close")
in _hide("dictionary-panel") end

(* The OPDS catalogues books are got from: each one's name, opening
   it, and Remove; and another added by its name and address *)
fn _catalogues (): void = let
  val () = ui_el("bats-root", "catalogues-panel", TDiv, "ovl")
  val () = ui_el("catalogues-panel", "catalogues-box", TDiv, "menu")
  val () = ui_labelled("catalogues-box", NDialog, "catalogues-title")
  val () = ui_el("catalogues-box", "catalogues-title", TDiv, "mtitle")
  val () = ui_text("catalogues-title", "Catalogues")
  val () = ui_el("catalogues-box", "catalogues-none", TDiv, "cnone")
  val () = ui_text("catalogues-none", "No catalogues yet")
  val () = ui_add("catalogues-box", "catalogues-list", TDiv)
  val () = ui_el("catalogues-box", "catalogue-form", TDiv, "cform")
  val () = ui_named("catalogue-form", NGroup, "Add catalogue")
  val () = app_catalogue_form()
  val () = ui_text_btn("catalogues-box", "catalogue-add", "btn", "Add catalogue")
  val () = ui_el("catalogues-box", "catalogues-status", TDiv, "cnone")
  val () = ui_role("catalogues-status", RStatus)
  val () = ui_text_btn("catalogues-box", "catalogues-done", "btn btn-p", "Done")
in _hide("catalogues-panel") end

(* A catalogue, browsed: Back to the page before, the page's title and
   Close; its search, what it says (loading, or why it cannot be read),
   its entries, and its next and previous pages *)
fn _catalogue (): void = let
  val () = ui_el("bats-root", "catalogue-panel", TDiv, "panel")
  val () = ui_labelled("catalogue-panel", NDialog, "catalogue-title")
  val () = ui_el("catalogue-panel", "catalogue-header", TDiv, "ph")
  val () = ui_icon_btn("catalogue-header", "catalogue-back", "ibtn", IcBack, "Back")
  val () = ui_el("catalogue-header", "catalogue-title", TSpan, "grow")
  val () = ui_icon_btn("catalogue-header", "catalogue-close", "ibtn", IcClose, "Close catalogue")
  val () = ui_el("catalogue-panel", "catalogue-search-bar", TDiv, "sbar")
  val () = app_catalogue_search()
  val () = ui_el("catalogue-panel", "catalogue-status", TDiv, "snav")
  val () = ui_role("catalogue-status", RStatus)
  val () = ui_el("catalogue-panel", "catalogue-list", TDiv, "plist")
  val () = ui_named("catalogue-list", NRegion, "Entries")
  val () = ui_el("catalogue-panel", "catalogue-pages", TDiv, "snav")
  val () = ui_text_btn("catalogue-pages", "catalogue-previous", "btn", "Previous")
  val () = ui_text_btn("catalogue-pages", "catalogue-next", "btn", "Next")
in _hide("catalogue-panel") end

(* The library menu (the gear) *)
fn _library_menu (): void = let
  val () = ui_el("bats-root", "library-menu", TDiv, "ovl")
  val () = ui_el("library-menu", "library-menu-box", TDiv, "menu")
  val () = ui_named("library-menu-box", NMenu, "Library menu")
  (* shown only while the browser offers to install the app, whose
     offer a click asks for (platform.bats) *)
  val () = ui_menuitem("library-menu-box", "menu-install", "Install Quire")
  val () = _hide("menu-install")
  (* whether the browser keeps the books, once it is known
     (platform.bats), each saying more when clicked *)
  val () = ui_menuitem("library-menu-box", "menu-storage-kept", "Your books are kept")
  val () = _hide("menu-storage-kept")
  val () = ui_menuitem("library-menu-box", "menu-storage-at-risk", "Your books may be cleared")
  val () = _hide("menu-storage-at-risk")
  val () = ui_menuitem("library-menu-box", "menu-settings", "Settings")
  val () = ui_menuitem("library-menu-box", "menu-about", "About Quire")
  val () = ui_menuitem("library-menu-box", "menu-stats", "Reading statistics")
  val () = ui_menuitem("library-menu-box", "menu-catalogues", "Catalogues")
  val () = ui_harm_item("library-menu-box", HEmptyTrash())
  val () = ui_menuitem("library-menu-box", "menu-close", "Close")
in _hide("library-menu") end

(* The Settings screen, opened from the library menu and the reader:
   one screen of groups, each complex area a screen of its own opened
   from a row that says its state (Android's settings pattern). Sync
   (its row says whether it is on and how the last sync went, from
   sync_summary_show), the dictionaries, the backup (exported, or one
   restored), the daily reading goal (the statistics panel has it too),
   and the resets, each offered back by the Undo toast *)
fn _settings_screen (): void = let
  val () = ui_el("bats-root", "settings-screen", TDiv, "info")
  val () = ui_labelled("settings-screen", NDialog, "settings-title")
  val () = ui_el("settings-screen", "settings-box", TDiv, "info-in")
  val () = ui_el("settings-box", "settings-title", TDiv, "mtitle")
  val () = ui_text("settings-title", "Settings")
  (* sync: its screen, and its state *)
  val () = ui_el("settings-box", "settings-sync-row", TDiv, "srow")
  val () = ui_named("settings-sync-row", NGroup, "Sync")
  val () = ui_text_btn("settings-sync-row", "settings-sync", "btn", "Sync \xE2\x80\xBA")
  val () = ui_add("settings-sync-row", "settings-sync-state", TSpan)
  val () = ui_role("settings-sync-state", RStatus)
  (* the dictionaries' panel *)
  val () = ui_el("settings-box", "settings-dictionaries-row", TDiv, "srow")
  val () = ui_text_btn("settings-dictionaries-row", "settings-dictionaries", "btn", "Dictionaries \xE2\x80\xBA")
  (* the backup *)
  val () = ui_el("settings-box", "settings-backup-title", TDiv, "a11yg")
  val () = ui_text("settings-backup-title", "Backup")
  val () = ui_el("settings-box", "settings-backup", TDiv, "srow")
  val () = ui_named("settings-backup", NGroup, "Backup")
  val () = ui_text_btn("settings-backup", "settings-export-backup", "btn", "Export backup")
  val () = ui_el("settings-backup", "settings-restore", TDiv, "btn")
  val () = app_backup_input()
  (* the daily reading goal *)
  val () = ui_el("settings-box", "settings-goal-title", TDiv, "a11yg")
  val () = ui_text("settings-goal-title", "Reading goal")
  val () = ui_el("settings-box", "settings-goal", TDiv, "seg")
  val () = ui_named("settings-goal", NGroup, "Daily reading goal")
  val () = ui_text_btn("settings-goal", "settings-goal-off", "sbtn", "Off")
  val () = ui_text_btn("settings-goal", "settings-goal-10", "sbtn", "10 min")
  val () = ui_text_btn("settings-goal", "settings-goal-20", "sbtn", "20 min")
  val () = ui_text_btn("settings-goal", "settings-goal-30", "sbtn", "30 min")
  val () = ui_text_btn("settings-goal", "settings-goal-60", "sbtn", "1 h")
  (* the resets, each offered back by the Undo toast *)
  val () = ui_el("settings-box", "settings-reset-title", TDiv, "a11yg")
  val () = ui_text("settings-reset-title", "Reset")
  val () = ui_el("settings-box", "settings-reset", TDiv, "srow")
  val () = ui_named("settings-reset", NGroup, "Reset")
  val () = ui_text_btn("settings-reset", "settings-reset-settings", "btn", "Reset settings")
  val () = ui_text_btn("settings-reset", "settings-factory-reset", "btn", "Factory reset")
  (* the About screen *)
  val () = ui_el("settings-box", "settings-about-row", TDiv, "srow")
  val () = ui_text_btn("settings-about-row", "settings-about", "btn", "About Quire \xE2\x80\xBA")
  val () = ui_el("settings-box", "settings-buttons", TDiv, "mbtns")
  val () = ui_text_btn("settings-buttons", "settings-done", "btn btn-p", "Done")
in _hide("settings-screen") end

(* A link of the About screen to one of the pages published beside the
   app (homepage/, by deploy.yml): path, relative to the app's own
   address, in a browser, so the app is the same wherever it is served
   (quire#217); in the Android app, whose own address is the device's,
   the published page's https address, which the WebView hands to the
   system's browser *)
fn _about_page {id_len,label_len:pos | id_len < 256; label_len < 256}{path_len,address_len:pos | path_len < 240; address_len < 240}
  (id: string id_len, label: string label_len, path: string path_len, address: string address_len): void =
  if $BAPP.is_native_platform() then ui_link_out_https("about-links", id, "btn linkout", label, address)
  else ui_link_out_path("about-links", id, "btn linkout", label, path)

(* The About screen, opened from Settings, the same in the web app and
   the Android app: the app's name, what it is, and links out of the app
   to its home page, privacy policy, terms and source. The pages are
   published beside the app but are not the app's: the service worker
   leaves them to the network. A link out opens in a new tab on the web;
   on Android the WebView hands an address outside the app to the
   system's browser *)
fn _about_screen (): void = let
  val () = ui_el("bats-root", "about-screen", TDiv, "info")
  val () = ui_labelled("about-screen", NDialog, "about-title")
  val () = ui_el("about-screen", "about-box", TDiv, "info-in")
  val () = ui_el("about-box", "about-title", TDiv, "mtitle")
  val () = ui_text("about-title", "About Quire")
  val () = ui_el("about-box", "about-text", TDiv, "sabout")
  val () = ui_text_long("about-text", "Quire, an EPUB reader. Your books and reading data are kept on this device.")
  (* the version, as a bug report should give it (#219) *)
  val () = ui_el("about-box", "about-version-row", TDiv, "srow")
  val () = ui_add("about-version-row", "about-version-label", TSpan)
  val () = ui_text("about-version-label", "Version")
  val () = ui_add("about-version-row", "about-version", TB)
  val () = ui_text("about-version", quire_version())
  val () = ui_el("about-box", "about-links", TDiv, "sfields")
  val () = ui_named("about-links", NGroup, "Links")
  val () = _about_page("about-home", "Home page", "homepage/", "bats-lang.github.io/quire/homepage/")
  val () = _about_page("about-privacy", "Privacy policy", "homepage/privacy.html", "bats-lang.github.io/quire/homepage/privacy.html")
  val () = _about_page("about-terms", "Terms of service", "homepage/terms.html", "bats-lang.github.io/quire/homepage/terms.html")
  val () = ui_link_out_https("about-links", "about-source", "btn linkout", "Source code", "github.com/bats-lang/quire")
  val () = ui_el("about-box", "about-buttons", TDiv, "mbtns")
  val () = ui_text_btn("about-buttons", "about-done", "btn btn-p", "Done")
in _hide("about-screen") end

(* The dialog: its buttons' labels and tones are set when it opens *)
fn _modal (): void = let
  val () = ui_el("bats-root", "dialog", TDiv, "ovl")
  val () = ui_el("dialog", "dialog-box", TDiv, "mbox")
  val () = ui_labelled("dialog-box", NModal, "dialog-title")
  val () = ui_el("dialog-box", "dialog-title", TDiv, "mtitle")
  val () = ui_add("dialog-box", "dialog-text", TDiv)
  val () = ui_field("dialog-box", "dialog-note", FText, "mta", "Note")
  val () = _hide("dialog-note")
  val () = ui_add("dialog-box", "dialog-name-box", TDiv)
  val () = _hide("dialog-name-box")
  val () = ui_el("dialog-box", "dialog-buttons", TDiv, "mbtns")
  val () = ui_text_btn("dialog-buttons", "dialog-button1", "btn", "-")
  val () = ui_text_btn("dialog-buttons", "dialog-button2", "btn btn-p", "-")
in _hide("dialog") end

(* The error banner, over the library and the reader alike, until it is
   dismissed; the copy status, apart from the Undo toast (notice.bats);
   and the offer of a new version *)
fn _notices (): void = let
  val () = ui_el("bats-root", "error-banner", TDiv, "banner")
  val () = ui_role("error-banner", RAlert)
  val () = ui_add("error-banner", "error-text", TSpan)
  val () = ui_icon_btn("error-banner", "error-dismiss", "ibtn", IcClose, "Dismiss")
  val () = _hide("error-banner")
  val () = ui_el("bats-root", "copy-status", TDiv, "toast tcopy")
  val () = ui_role("copy-status", RStatus)
  val () = _hide("copy-status")
  (* a new version is served: it is offered, never forced (quire.bats'
     _build_watch) *)
  val () = ui_el("bats-root", "update-toast", TDiv, "toast tnew")
  val () = ui_role("update-toast", RStatus)
  val () = ui_add("update-toast", "update-text", TSpan)
  val () = ui_text("update-text", "A new version of Quire is ready.")
  val () = ui_text_btn("update-toast", "update-reload", "btn", "Reload")
  val () = ui_icon_btn("update-toast", "update-dismiss", "ibtn", IcClose, "Dismiss")
in _hide("update-toast") end

(* The Undo toast: what was just done, and a way back *)
fn _undo_toast (): void = let
  val () = ui_el("bats-root", "undo-toast", TDiv, "toast")
  val () = ui_role("undo-toast", RStatus)
  val () = ui_add("undo-toast", "undo-text", TSpan)
  val () = ui_text_btn("undo-toast", "undo-button", "btn", "Undo")
in _hide("undo-toast") end

(* A labelled row of the book info view *)
fn _row {row_id_len,label_id_len:pos | row_id_len < 256; label_id_len < 256}{label_len:pos | label_len < 256} (row_id: string row_id_len, label_id: string label_id_len, label: string label_len): void = let
  val () = ui_el("book-info-inner", row_id, TDiv, "irow")
  val () = ui_add(row_id, label_id, TSpan)
  val () = ui_text(label_id, label)
in end

(* The book info view *)
fn _info (): void = let
  val () = ui_el("bats-root", "book-info", TDiv, "info")
  val () = ui_named("book-info", NDialog, "Book info")
  val () = ui_el("book-info", "book-info-inner", TDiv, "info-in")
  val () = ui_text_btn("book-info-inner", "book-info-back", "btn", "\xE2\x86\x90 Library")
  val () = ui_img("book-info-inner", "book-info-cover", "icov")
  val () = ui_el("book-info-inner", "book-info-title", TDiv, "it")
  val () = ui_el("book-info-inner", "book-info-author", TDiv, "ba")
  val () = _row("info-progress-row", "info-progress-label", "Progress")
  val () = ui_add("info-progress-row", "info-progress", TB)
  val () = _row("info-added-row", "info-added-label", "Added")
  val () = ui_add("info-added-row", "info-added", TB)
  val () = _row("info-last-read-row", "info-last-read-label", "Last read")
  val () = ui_add("info-last-read-row", "info-last-read", TB)
  val () = _row("info-size-row", "info-size-label", "Size")
  val () = ui_add("info-size-row", "info-size", TB)
  val () = _row("info-time-row", "info-time-label", "Time read")
  val () = ui_add("info-time-row", "info-time", TB)
  val () = _row("info-speed-row", "info-speed-label", "Speed")
  val () = ui_add("info-speed-row", "info-speed", TB)
  (* the book's accessibility metadata (lib_a11y_show) *)
  val () = ui_el("book-info-inner", "book-info-a11y", TDiv, "a11y")
  val () = ui_named("book-info-a11y", NRegion, "Accessibility")
  val () = ui_el("book-info-a11y", "book-info-a11y-title", TDiv, "a11yt")
  val () = ui_text("book-info-a11y-title", "Accessibility")
  val () = ui_el("book-info-a11y", "book-info-a11y-list", TDiv, "a11yl")
  val () = ui_el("book-info-inner", "book-info-buttons", TDiv, "mbtns")
  val () = ui_text_btn("book-info-buttons", "book-info-hide", "btn", "Hide")
  val () = ui_text_btn("book-info-buttons", "book-info-archive", "btn", "Archive")
  val () = ui_text_btn("book-info-buttons", "book-info-trash", "btn", "Move to Trash")
in _hide("book-info") end

(* The reader: its bars, the content, the scrubber, the selection
   toolbar and the back-after-a-jump button *)
fn _reader (): void = let
  val () = ui_el("bats-root", "reader", TDiv, "rv")
  val () = ui_role("reader", RMain)
  val () = ui_el("reader", "reader-top-bar", TDiv, "top")
  val () = ui_named("reader-top-bar", NNavigation, "Book")
  val () = ui_icon_btn("reader-top-bar", "back-to-library", "ibtn", IcBack, "Back to library")
  val () = ui_el("reader-top-bar", "chapter-title", TDiv, "ctitle")
  val () = ui_role("chapter-title", RHeading)
  val () = ui_icon_btn("reader-top-bar", "bookmark-button", "ibtn", IcStar, "Bookmark this page")
  val () = ui_attr("bookmark-button", APressed, "false")
  val () = ui_icon_btn("reader-top-bar", "search-button", "ibtn", IcSearch, "Search in book")
  (* the Settings screen: in this bar, whose title gives way, since the
     bottom bar has no room left on a phone *)
  val () = ui_icon_btn("reader-top-bar", "reader-settings", "ibtn", IcGear, "Settings")
  val () = ui_el("reader", "page", TDiv, "caf")
  (* shown (by the typography's style) exactly when a screen shows two
     columns, so the reader can tell *)
  val () = ui_el("reader", "spread-probe", TDiv, "sprobe")
  val () = ui_attr("page", ATabindex, "0")
  (* the page turn's gesture region (quire.bats's PAGE_REGION) *)
  val () = ui_attr("page", AGestureRegion, "1")
  val () = ui_named("page", NDocument, "Page")
  (* a page turn (reader.bats): the shade over the incoming page, and
     over it the page being left, a copy of the page in turn-sheet,
     sliding off; both shown only while a page turns, decorative, and
     taps go through them to the page *)
  val () = ui_el("reader", "turn-shade", TDiv, "shade")
  val () = ui_attr("turn-shade", AHidden, "true")
  val () = _hide("turn-shade")
  (* page-turn is laid out even while no page turns (idle: hidden), so
     the copy kept in it is ready for a turn (reader.bats) *)
  val () = ui_el("reader", "page-turn", TDiv, "turn idle")
  val () = ui_attr("page-turn", AHidden, "true")
  val () = ui_el("page-turn", "turn-sheet", TDiv, "leaf")
  val () = ui_el("page-turn", "turn-gap", TDiv, "tgap")
  (* the running footer, shown while the bars are hidden; what it says
     the page indicator (a status) says too, so it is not read out *)
  val () = ui_el("reader", "footer", TDiv, "foot")
  val () = ui_attr("footer", AHidden, "true")
  val () = ui_el("footer", "footer-title", TSpan, "pgt")
  val () = ui_el("footer", "footer-readout", TSpan, "rdo")
  val () = ui_el("footer", "footer-book", TSpan, "pgn")
  val () = ui_el("footer", "footer-page", TSpan, "pgn")
  val () = ui_text_btn("reader", "jump-back", "pback", "\xE2\x86\xA9 Back")
  val () = _hide("jump-back")
  (* the first book's hint on turning pages: read out as it shows, and
     taps go through it to the page *)
  val () = ui_el("reader", "turn-hint", TDiv, "hint")
  val () = ui_role("turn-hint", RStatus)
  val () = ui_text("turn-hint", "Swipe or tap the sides to turn the page")
  val () = _hide("turn-hint")
  (* scrolled, the chapter's last screen goes on to the next *)
  val () = ui_text_btn("reader", "next-chapter", "pback nextch", "Next chapter \xE2\x86\x92")
  val () = _hide("next-chapter")
  val () = ui_el("reader", "selection-toolbar", TDiv, "seltb")
  val () = ui_named("selection-toolbar", NToolbar, "Selection")
  val () = ui_text_btn("selection-toolbar", "selection-highlight", "btn", "Highlight")
  (* the other highlight styles, each one tap *)
  val () = ui_text_btn("selection-toolbar", "selection-orange", "btn", "Orange")
  val () = ui_text_btn("selection-toolbar", "selection-underline", "btn", "Underline")
  val () = ui_text_btn("selection-toolbar", "selection-note", "btn", "Note")
  val () = ui_text_btn("selection-toolbar", "selection-copy", "btn", "Copy")
  (* read aloud from the selection (read_aloud.bats), where the
     platform speaks *)
  val () = ui_text_btn("selection-toolbar", "selection-read", "btn", "Read from here")
  val () = _hide("selection-read")
  (* shared, cited by the book (sharing.bats), where the platform
     shares *)
  val () = ui_text_btn("selection-toolbar", "selection-share", "btn", "Share")
  val () = _hide("selection-share")
  (* the selection looked up in a dictionary the reader imported, shown
     instead of the online one below when it has the word *)
  val () = ui_text_btn("selection-toolbar", "selection-define", "btn", "Look up")
  val () = _hide("selection-define")
  (* the selection looked up in a dictionary of the book's language (its
     href follows the selection) *)
  val () = ui_link_out("selection-toolbar", "selection-lookup", "btn linkout", "Look up")
  val () = ui_text_btn("selection-toolbar", "selection-search", "btn", "Search")
  val () = _hide("selection-toolbar")
  val () = ui_el("reader", "reader-bottom-bar", TDiv, "bot")
  val () = ui_named("reader-bottom-bar", NToolbar, "Page controls")
  val () = ui_icon_btn("reader-bottom-bar", "previous-page", "ibtn", IcPrev, "Previous page")
  val () = ui_icon_btn("reader-bottom-bar", "contents-button", "ibtn", IcContents, "Contents")
  val () = ui_icon_btn("reader-bottom-bar", "typography-button", "ibtn", IcFont, "Typography")
  val () = ui_icon_btn("reader-bottom-bar", "annotations-button", "ibtn", IcNotes, "Annotations")
  (* read aloud from the page shown, or paused (read_aloud.bats), shown
     only where the platform speaks *)
  val () = ui_icon_btn("reader-bottom-bar", "read-aloud", "ibtn", IcSpeak, "Read aloud")
  val () = ui_attr("read-aloud", APressed, "false")
  val () = _hide("read-aloud")
  (* a book with Media Overlays is read aloud by its own narration
     instead (narration.bats): its controls, shown only for such a book
     (the reader's _narration_offered) *)
  val () = ui_el("reader-bottom-bar", "narration-controls", TDiv, "ngrp")
  val () = ui_named("narration-controls", NGroup, "Narration")
  val () = ui_icon_btn("narration-controls", "narration-toggle", "ibtn", IcSpeak, "Read aloud")
  val () = ui_attr("narration-toggle", APressed, "false")
  val () = ui_icon_btn("narration-controls", "narration-previous", "ibtn", IcPhrasePrevious, "Previous phrase")
  val () = ui_icon_btn("narration-controls", "narration-next", "ibtn", IcPhraseNext, "Next phrase")
  (* shown inside a table, list, figure or aside, named for it *)
  val () = ui_text_btn("narration-controls", "narration-leave", "ibtn nleave", "Skip table")
  val () = _hide("narration-leave")
  val () = _hide("narration-controls")
  (* what plays the narration: no controls of its own, and not read out *)
  val () = ui_audio("reader", "narration")
  val () = ui_el("reader-bottom-bar", "page-indicator", TDiv, "pinfo")
  val () = ui_named("page-indicator", NStatus, "Page")
  val () = ui_el("page-indicator", "indicator-title", TSpan, "pgt")
  (* " · page ", which a phone's bar has no room for, nor for the title:
     there they are left to screen readers, and the title is in the top
     bar *)
  val () = ui_el("page-indicator", "indicator-label", TSpan, "pgw")
  val () = ui_el("page-indicator", "indicator-pages", TSpan, "pgn")
  val () = ui_icon_btn("reader-bottom-bar", "next-page", "ibtn", IcNext, "Next page")
  (* scrubber *)
  val () = ui_el("reader-bottom-bar", "scrubber", TDiv, "scr")
  val () = ui_el("scrubber", "scrubber-track", TDiv, "trk")
  val () = ui_named("scrubber-track", NSlider, "Place in book")
  val () = ui_el("scrubber-track", "scrubber-line", TDiv, "trk-l")
  val () = ui_el("scrubber-track", "scrubber-fill", TDiv, "trk-f")
  val () = ui_add("scrubber-track", "scrubber-ticks", TDiv)
  val () = ui_el("scrubber-track", "scrubber-thumb", TDiv, "thumb")
  val () = ui_el("scrubber-track", "scrubber-tip", TDiv, "tip")
  val () = ui_role("scrubber-tip", RTooltip)
  val () = _hide("scrubber-tip")
  val () = ui_el("scrubber", "scrubber-percent", TDiv, "pct")
in _hide("reader") end

(* The contents panel: the book's table of contents and its bookmarks *)
fn _toc (): void = let
  val () = ui_el("bats-root", "contents-panel", TDiv, "panel")
  val () = ui_named("contents-panel", NDialog, "Contents")
  val () = ui_el("contents-panel", "contents-header", TDiv, "ph")
  val () = ui_el("contents-header", "contents-tabs", TSpan, "tabs")
  val () = ui_named("contents-tabs", NTablist, "Contents and bookmarks")
  val () = ui_tab("contents-tabs", "contents-tab", "Contents", "contents-list", true)
  val () = ui_tab("contents-tabs", "bookmarks-tab", "Bookmarks", "bookmarks-list", false)
  (* the print pages, for a book that lists them *)
  val () = ui_tab("contents-tabs", "pages-tab", "Pages", "pages-list", false)
  val () = _hide("pages-tab")
  val () = ui_el("contents-header", "contents-spacer", TSpan, "grow")
  val () = ui_icon_btn("contents-header", "contents-close", "ibtn", IcClose, "Close")
  val () = ui_el("contents-panel", "contents-list", TDiv, "plist")
  val () = ui_labelled("contents-list", NTabpanel, "contents-tab")
  val () = ui_el("contents-panel", "bookmarks-list", TDiv, "plist")
  val () = ui_labelled("bookmarks-list", NTabpanel, "bookmarks-tab")
  val () = _hide("bookmarks-list")
  val () = ui_el("contents-panel", "pages-list", TDiv, "plist")
  val () = ui_labelled("pages-list", NTabpanel, "pages-tab")
  val () = _hide("pages-list")
in _hide("contents-panel") end

(* The settings sheet *)
fn _settings (): void = let
  val () = ui_el("bats-root", "typography-panel", TDiv, "sheet")
  val () = ui_named("typography-panel", NDialog, "Typography and theme")
  (* its head, held at its top as it scrolls (.shead): Close is always
     in reach, in full screen too (#275) *)
  val () = ui_el("typography-panel", "typography-head", TDiv, "shead")
  val () = ui_el("typography-head", "typography-title", TSpan, "grow")
  val () = ui_text("typography-title", "Typography and theme")
  val () = ui_text_btn("typography-head", "typography-close", "btn", "Close")
  val () = ui_el("typography-panel", "font-row", TDiv, "srow")
  val () = ui_el("font-row", "font-label", TSpan, "slabel")
  val () = ui_text("font-label", "Font")
  val () = ui_el("font-row", "font-choice", TDiv, "seg")
  val () = ui_text_btn("font-choice", "font-literata", "sbtn", "Literata")
  val () = ui_text_btn("font-choice", "font-inter", "sbtn", "Inter")
  (* a preference for some readers: not a fix for dyslexia (the evidence
     for such fonts is weak; letter spacing is the help that has it) *)
  val () = ui_text_btn("font-choice", "font-atkinson", "sbtn", "Atkinson")
  val () = ui_text_btn("font-choice", "font-book", "sbtn", "Book")
  (* the sliders' rows: their sliders are made at the settings'
     values (set_sliders) *)
  val () = ui_el("typography-panel", "size-row", TDiv, "srow")
  val () = ui_el("typography-panel", "line-height-row", TDiv, "srow")
  val () = ui_el("typography-panel", "margins-row", TDiv, "srow")
  (* the text's alignment and hyphenation, each a named group, so its
     buttons are announced with what they set *)
  val () = ui_el("typography-panel", "align-row", TDiv, "srow")
  val () = ui_el("align-row", "align-label", TSpan, "slabel")
  val () = ui_text("align-label", "Alignment")
  val () = ui_el("align-row", "align-choice", TDiv, "seg")
  val () = ui_named("align-choice", NGroup, "Alignment")
  val () = ui_text_btn("align-choice", "align-ragged", "sbtn", "Ragged")
  val () = ui_text_btn("align-choice", "align-justified", "sbtn", "Justified")
  val () = ui_el("typography-panel", "hyphens-row", TDiv, "srow")
  val () = ui_el("hyphens-row", "hyphens-label", TSpan, "slabel")
  val () = ui_text("hyphens-label", "Hyphenation")
  val () = ui_el("hyphens-row", "hyphens-choice", TDiv, "seg")
  val () = ui_named("hyphens-choice", NGroup, "Hyphenation")
  val () = ui_text_btn("hyphens-choice", "hyphens-on", "sbtn", "On")
  val () = ui_text_btn("hyphens-choice", "hyphens-off", "sbtn", "Off")
  (* a ruby's annotations (furigana) shown or hidden: offered only once
     a chapter of the open book has shown a ruby (reader_ruby_forget,
     the reader's _ruby_mark) *)
  val () = ui_el("typography-panel", "ruby-row", TDiv, "srow")
  val () = ui_el("ruby-row", "ruby-label", TSpan, "slabel")
  val () = ui_text("ruby-label", "Ruby")
  val () = ui_el("ruby-row", "ruby-choice", TDiv, "seg")
  val () = ui_named("ruby-choice", NGroup, "Ruby annotations")
  val () = ui_text_btn("ruby-choice", "ruby-show", "sbtn", "Show")
  val () = ui_text_btn("ruby-choice", "ruby-hide", "sbtn", "Hide")
  val () = _hide("ruby-row")
  val () = ui_el("typography-panel", "dim-row", TDiv, "srow")
  val () = ui_el("dim-row", "dim-label", TSpan, "slabel")
  val () = ui_text("dim-label", "Dim images")
  val () = ui_el("dim-row", "dim-choice", TDiv, "seg")
  val () = ui_named("dim-choice", NGroup, "Dim images in the dark themes")
  val () = ui_text_btn("dim-choice", "dim-on", "sbtn", "On")
  val () = ui_text_btn("dim-choice", "dim-off", "sbtn", "Off")
  val () = ui_el("typography-panel", "taps-row", TDiv, "srow")
  val () = ui_el("taps-row", "taps-label", TSpan, "slabel")
  val () = ui_text("taps-label", "Taps")
  val () = ui_el("taps-row", "taps-choice", TDiv, "seg")
  val () = ui_named("taps-choice", NGroup, "What a tap on the page does")
  val () = ui_text_btn("taps-choice", "taps-sides", "sbtn", "Sides")
  val () = ui_text_btn("taps-choice", "taps-forward", "sbtn", "Forward")
  val () = ui_text_btn("taps-choice", "taps-one-hand", "sbtn", "One hand")
  val () = ui_el("typography-panel", "volume-row", TDiv, "srow")
  val () = ui_el("volume-row", "volume-label", TSpan, "slabel")
  val () = ui_text("volume-label", "Volume keys")
  val () = ui_el("volume-row", "volume-choice", TDiv, "seg")
  val () = ui_named("volume-choice", NGroup, "Volume keys turn the page")
  val () = ui_text_btn("volume-choice", "volume-keys-turn", "sbtn", "Turn pages")
  val () = ui_text_btn("volume-choice", "volume-keys-off", "sbtn", "Volume")
  val () = ui_el("typography-panel", "paragraph-row", TDiv, "srow")
  val () = ui_el("typography-panel", "letter-row", TDiv, "srow")
  val () = ui_el("typography-panel", "word-row", TDiv, "srow")
  (* pages turned across, or the chapter scrolled down *)
  val () = ui_el("typography-panel", "layout-row", TDiv, "srow")
  val () = ui_el("layout-row", "layout-label", TSpan, "slabel")
  val () = ui_text("layout-label", "Layout")
  val () = ui_el("layout-row", "layout-choice", TDiv, "seg")
  val () = ui_named("layout-choice", NGroup, "Layout")
  val () = ui_text_btn("layout-choice", "layout-pages", "sbtn", "Pages")
  val () = ui_text_btn("layout-choice", "layout-scroll", "sbtn", "Scroll")
  (* reading aloud: its speed and voice (the voices of the book's
     language), offered and kept by read_aloud.bats, where the platform
     speaks *)
  val () = ui_el("typography-panel", "speech-row", TDiv, "srow")
  val () = ui_el("speech-row", "speech-label", TSpan, "slabel")
  val () = ui_text("speech-label", "Read aloud")
  val () = ui_field("speech-row", "speech-rate", FChoice, "ssel", "Reading speed")
  val () = ui_field("speech-row", "speech-voice", FChoice, "ssel", "Voice")
  val () = _hide("speech-row")
  (* a book's narration: its speed (its slider is made at the settings'
     value, set_sliders) and whether page numbers and notes are read,
     both offered only for a book that has one *)
  val () = ui_el("typography-panel", "narration-speed-row", TDiv, "srow")
  val () = _hide("narration-speed-row")
  val () = ui_el("typography-panel", "narration-skip-row", TDiv, "srow")
  val () = ui_el("narration-skip-row", "narration-skip-label", TSpan, "slabel")
  val () = ui_text("narration-skip-label", "Page numbers and notes")
  val () = ui_el("narration-skip-row", "narration-skip-choice", TDiv, "seg")
  val () = ui_named("narration-skip-choice", NGroup, "Page numbers and notes")
  val () = ui_text_btn("narration-skip-choice", "narration-skip", "sbtn", "Skip")
  val () = ui_text_btn("narration-skip-choice", "narration-read", "sbtn", "Read")
  val () = _hide("narration-skip-row")
  (* the screen: full screen, the rotation locked, and (in the Android
     app) the brightness, each shown only where it can be had
     (screen_controls.bats) *)
  val () = ui_el("typography-panel", "screen-row", TDiv, "srow")
  val () = ui_el("screen-row", "screen-label", TSpan, "slabel")
  val () = ui_text("screen-label", "Screen")
  val () = ui_text_btn("screen-row", "screen-fullscreen", "sbtn", "Full screen")
  val () = ui_attr("screen-fullscreen", APressed, "false")
  val () = ui_text_btn("screen-row", "screen-lock", "sbtn", "Lock rotation")
  val () = ui_attr("screen-lock", APressed, "false")
  val () = ui_field("screen-row", "screen-brightness", FChoice, "ssel", "Brightness")
  val () = _hide("screen-row")
  (* paged, one column a screen or two: a spread *)
  val () = ui_el("typography-panel", "columns-row", TDiv, "srow")
  val () = ui_el("columns-row", "columns-label", TSpan, "slabel")
  val () = ui_text("columns-label", "Columns")
  val () = ui_el("columns-row", "columns-choice", TDiv, "seg")
  val () = ui_named("columns-choice", NGroup, "Columns")
  val () = ui_text_btn("columns-choice", "columns-auto", "sbtn", "Auto")
  val () = ui_text_btn("columns-choice", "columns-one", "sbtn", "One")
  val () = ui_text_btn("columns-choice", "columns-two", "sbtn", "Two")
  val () = ui_el("typography-panel", "theme-row", TDiv, "srow")
  val () = ui_el("theme-row", "theme-label", TSpan, "slabel")
  val () = ui_text("theme-label", "Theme")
  val () = ui_el("theme-row", "theme-choice", TDiv, "seg")
  val () = ui_named("theme-choice", NGroup, "Theme")
  val () = ui_text_btn("theme-choice", "theme-auto", "sbtn", "Auto")
  val () = ui_text_btn("theme-choice", "theme-light", "sbtn", "Light")
  val () = ui_text_btn("theme-choice", "theme-sepia", "sbtn", "Sepia")
  val () = ui_text_btn("theme-choice", "theme-dark", "sbtn", "Dark")
  val () = ui_text_btn("theme-choice", "theme-night", "sbtn", "Night")
  val () = ui_text_btn("theme-choice", "theme-grey", "sbtn", "Grey")
  (* reset, away from Close and asked first *)
  val () = ui_el("typography-panel", "typography-foot", TDiv, "srow sfoot")
  val () = ui_text_btn("typography-foot", "typography-reset", "link", "Reset to defaults")
in _hide("typography-panel") end

(* The search panel *)
fn _search (): void = let
  val () = ui_el("bats-root", "search-panel", TDiv, "panel panel-r")
  val () = ui_named("search-panel", NDialog, "Search in book")
  val () = ui_el("search-panel", "search-header", TDiv, "sbar")
  val () = app_book_search()
  val () = ui_el("search-panel", "search-status", TDiv, "snav")
  val () = ui_role("search-status", RStatus)
  val () = ui_el("search-panel", "search-results", TDiv, "plist")
  val () = ui_named("search-results", NRegion, "Results")
  (* the results' bar, over the page once one is opened *)
  val () = ui_el("reader", "search-nav", TDiv, "snavf")
  val () = ui_named("search-nav", NToolbar, "Search results")
  val () = ui_icon_btn("search-nav", "search-previous", "ibtn", IcPrev, "Previous result")
  val () = ui_add("search-nav", "search-count", TSpan)
  val () = ui_role("search-count", RStatus)
  val () = ui_icon_btn("search-nav", "search-next", "ibtn", IcNext, "Next result")
  val () = ui_icon_btn("search-nav", "search-nav-close", "ibtn", IcClose, "Close search")
  val () = _hide("search-nav")
in _hide("search-panel") end

(* The annotations panel *)
fn _annotations (): void = let
  val () = ui_el("bats-root", "annotations-panel", TDiv, "panel panel-r")
  val () = ui_named("annotations-panel", NDialog, "Annotations")
  val () = ui_el("annotations-panel", "annotations-header", TDiv, "ph")
  val () = ui_el("annotations-header", "annotations-spacer", TSpan, "grow")
  val () = ui_text("annotations-spacer", "Annotations")
  val () = ui_text_btn("annotations-header", "annotations-export", "btn", "Export")
  (* the export shared, as a file where the platform shares files
     (sharing.bats) *)
  val () = ui_text_btn("annotations-header", "annotations-share", "btn", "Share")
  val () = _hide("annotations-share")
  val () = ui_icon_btn("annotations-header", "annotations-close", "ibtn", IcClose, "Close")
  (* which highlights are listed: every one, or one style's *)
  val () = ui_el("annotations-panel", "annotations-filter", TDiv, "seg afilter")
  val () = ui_named("annotations-filter", NGroup, "Show")
  val () = ui_text_btn("annotations-filter", "filter-all", "sbtn", "All")
  val () = ui_text_btn("annotations-filter", "filter-yellow", "sbtn", "Yellow")
  val () = ui_text_btn("annotations-filter", "filter-orange", "sbtn", "Orange")
  val () = ui_text_btn("annotations-filter", "filter-underlined", "sbtn", "Underlined")
  val () = ui_el("annotations-panel", "annotations-list", TDiv, "plist")
in _hide("annotations-panel") end

(* A note, opened over the page from its reference: its text, a way to
   the note itself, and Close *)
fn _note (): void = let
  val () = ui_el("bats-root", "footnote", TDiv, "sheet")
  val () = ui_named("footnote", NDialog, "Footnote")
  val () = ui_el("footnote", "footnote-text", TDiv, "fntext")
  val () = ui_el("footnote", "footnote-bar", TDiv, "srow sfoot")
  val () = ui_text_btn("footnote-bar", "footnote-go", "link", "Go to note")
  val () = ui_el("footnote-bar", "footnote-spacer", TSpan, "grow")
  val () = ui_text_btn("footnote-bar", "footnote-close", "btn", "Close")
in _hide("footnote") end

(* A book's image, full screen: it can be zoomed with the fingers, and
   scrolled; the image is the page's, whose alt says what it shows *)
fn _image_viewer (): void = let
  val () = ui_el("bats-root", "image-viewer", TDiv, "imview")
  val () = ui_named("image-viewer", NDialog, "Image")
  val () = ui_el("image-viewer", "image-box", TDiv, "imbox")
  val () = ui_img("image-box", "image-full", "imimg")
  val () = ui_icon_btn("image-viewer", "image-close", "ibtn imclose", IcClose, "Close")
in _hide("image-viewer") end

(* Makes every element of the app, in the root element bats-root *)
#pub fn app_build (): void

implement app_build () = let
  (* the page's loading screen goes *)
  val () = ui_clear("bats-root")
  val () = ui_class("bats-root", "app th-light")
  val () = ui_add("bats-root", "style-sheet", TStyle)
  val @(css, css_len) = app_style()
  val () = ui_text_buf("style-sheet", css, css_len)
  val () = ui_add("bats-root", "style-type", TStyle)
  val () = ui_add("bats-root", "style-fonts", TStyle)
  val () = _notices()
  val () = _library()
  val () = _context_menu()
  val () = _collections()
  val () = _stats()
  val () = _library_menu()
  val () = _settings_screen()
  val () = _about_screen()
  val () = _info()
  val () = _reader()
  val () = _toc()
  val () = _settings()
  val () = _search()
  val () = _annotations()
  val () = _note()
  val () = _image_viewer()
  val () = _dictionaries()
  val () = _dictionary()
  val () = _catalogues()
  val () = _catalogue()
  val () = _undo_toast()
in _modal() end

end (* #target wasm *)
