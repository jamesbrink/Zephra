import Foundation
import Observation
import ZephraEngine

/// Where the window is looking: which pane, narrowed by what, with the inspector out or not.
///
/// One object rather than a preference each, because the parts are not independent. Typing in
/// the sidebar's search field while the canvas is showing means "find these", so it switches
/// to the Library and remembers where you were; clearing the field puts you back. That
/// behaviour has to live somewhere that owns both the pane and the query.
@Observable
final class WorkspaceSelection {
    /// Which pane the window is showing.
    ///
    /// Any move made from outside `setSearchText` forgets where a search started from. Someone
    /// who typed on the canvas, was brought to the Library, then went on choosing there has
    /// settled: clearing the field afterwards must not yank them back.
    var pane: WorkspacePane {
        didSet {
            guard pane != oldValue else { return }
            if !isSearchNavigating { paneBeforeSearch = nil }
            // A tuck only means anything while looking at the canvas; moving anywhere at all
            // is reason enough to bring the prompt back for whoever returns to it.
            promptTucked = false
            // The same reasoning as the tuck: leaving the library, even to come straight back,
            // should find the grid rather than reopen whatever was last full size.
            viewing = nil
            AppSettings.write(pane.rawValue, to: AppSettings.workspacePane)
        }
    }

    /// What narrows the library. Read by both panes; written here and by the sidebar.
    var query: LibraryQuery {
        didSet {
            if query.scope != oldValue.scope {
                AppSettings.write(query.scope.rawValue, to: AppSettings.libraryScope)
            }
            if query.sort != oldValue.sort {
                AppSettings.write(query.sort.rawValue, to: AppSettings.librarySort)
            }
        }
    }

    /// Whether the inspector is out, on either pane.
    var inspectorVisible: Bool {
        didSet {
            guard inspectorVisible != oldValue else { return }
            AppSettings.write(inspectorVisible, to: AppSettings.inspectorVisible)
        }
    }

    /// Whether the canvas has tucked its floating prompt away, leaving only the lip at the
    /// bottom edge. Never persisted: a launch always finds the prompt where it was left showing.
    var promptTucked = false

    /// Whether the model browser is up over the window. Never persisted, for the same reason
    /// as `promptTucked`: a dialog is something a person opened, not a place the window is.
    ///
    /// It lives here rather than in a view because three places raise it — the toolbar's
    /// pull-down, the canvas's idle state and the Model menu — and because one object has to
    /// arbitrate between it and the reference picker. Both are sheets on the one window, and a
    /// sheet raised over a sheet stacks: ⇧⌘M while the picker was up put the browser on top of
    /// it. So neither rises while the other is up, and the menu item that raises this one is
    /// greyed meanwhile.
    var showsModelBrowser = false {
        didSet {
            if showsModelBrowser, showsReferencePicker { showsModelBrowser = false }
        }
    }

    /// Whether the reference picker is up over the window, the browser's twin and its rival for
    /// the one sheet a window has. The well writes it rather than holding a `@State` of its
    /// own, so the arbitration above has both answers in one place — and so a screenshot build
    /// can raise the picker the way it raises the browser, rather than through an `onAppear`
    /// hook inside the well.
    var showsReferencePicker = false {
        didSet {
            if showsReferencePicker, showsModelBrowser { showsReferencePicker = false }
        }
    }

    /// The one library image the library pane is showing full size, or nil for the grid. Never
    /// persisted, for the same reason as `promptTucked`, and lives here rather than in the
    /// pane's own state so the menu bar's "Back to Grid" and `InterfacePreview` can reach it.
    var viewing: LibraryItem.ID?

    /// The library picture something outside the window has asked to be shown: a click on the
    /// "Image Saved" notification, and nothing else so far. The pane selects it and the grid
    /// scrolls to it; it is not cleared when they do, so a pane mounted after the ask — which
    /// is the ordinary case, since the notice arrives while the canvas is up — finds it there.
    /// Read through `unansweredReveal`, never directly.
    private(set) var revealing: LibraryItem.ID?

    /// Bumped by every `reveal`, so asking for the same picture twice is heard the second
    /// time; the twin of the two focus tokens below, and for the same reason.
    private(set) var revealToken = 0

    /// The token whose ask has been answered — the pane has selected the picture and the grid
    /// has scrolled to it — so nothing acts on it twice.
    ///
    /// The pane is torn down and rebuilt every time the window moves between panes, and both
    /// readers watch with `initial: true`, so without this a single notification click made
    /// every later visit to the Library select that picture again and scroll back to it, for
    /// the rest of the session. Consuming the token rather than clearing `revealing` is what
    /// keeps the ordinary case working: the ask arrives before the pane that answers it exists,
    /// so the value has to stay readable and only the fact that it was acted on goes away.
    private(set) var revealConsumed = 0

    /// The picture asked for and not yet shown, which is what both readers act on: nil once the
    /// ask has been answered, and the picture again the moment somebody asks for it afresh.
    var unansweredReveal: LibraryItem.ID? {
        revealToken == revealConsumed ? nil : revealing
    }

    /// Bumped whenever something asks for the search field. The field watches it and takes
    /// focus; a token rather than a flag, so asking twice in a row works the second time.
    private(set) var searchFocusToken = 0

    /// Bumped whenever something asks for the prompt field, the twin of `searchFocusToken`:
    /// typing while the prompt is tucked brings it back and needs the caret to land in it.
    private(set) var promptFocusToken = 0

    /// Where the search started from, so clearing it goes back there rather than leaving you
    /// in the Library you never asked for.
    @ObservationIgnored private var paneBeforeSearch: WorkspacePane?

    /// True only while `setSearchText` is the one moving the pane, so `pane`'s own observer can
    /// tell a move the search made from a move the person made.
    @ObservationIgnored private var isSearchNavigating = false

    /// The window as it was left last time, or the canvas over everything on a first launch.
    init() {
        let defaults = AppSettings.store
        pane = defaults.string(forKey: AppSettings.workspacePane)
            .flatMap(WorkspacePane.init(rawValue:)) ?? .canvas
        query = LibraryQuery(
            scope: defaults.string(forKey: AppSettings.libraryScope)
                .flatMap(LibraryScope.init(rawValue:)) ?? .all,
            sort: defaults.string(forKey: AppSettings.librarySort)
                .flatMap(LibrarySort.init(rawValue:)) ?? .newestFirst
        )
        inspectorVisible = AppSettings.flag(AppSettings.inspectorVisible)
    }

    /// A window in a stated position, for previews and for the screenshot builds. Nothing here
    /// is read from or written to the defaults until something moves.
    init(pane: WorkspacePane, query: LibraryQuery = LibraryQuery(), inspectorVisible: Bool = true) {
        self.pane = pane
        self.query = query
        self.inspectorVisible = inspectorVisible
    }

    /// Asks the sidebar's search field for the keyboard.
    func focusSearch() {
        searchFocusToken += 1
    }

    /// Asks the canvas's prompt field for the keyboard.
    func focusPrompt() {
        promptFocusToken += 1
    }

    /// Types into the search, switching panes as the field fills and empties.
    func setSearchText(_ text: String) {
        let had = !query.trimmedText.isEmpty
        query.text = text
        let has = !query.trimmedText.isEmpty
        guard has != had else { return }
        let remembered = paneBeforeSearch
        isSearchNavigating = true
        defer { isSearchNavigating = false }
        if has {
            paneBeforeSearch = pane
            pane = .library
        } else {
            if let remembered { pane = remembered }
            paneBeforeSearch = nil
        }
    }

    /// Shows one collection of the library. Everything in the sidebar below the search is about
    /// what to look at, so choosing one takes you to the pane that can show it — otherwise the
    /// lower two thirds of the sidebar does nothing at all while the canvas is up.
    func show(scope: LibraryScope) {
        query.scope = scope
        pane = .library
    }

    /// Narrows the library to one model and shows it. Widening again is a plain write to
    /// `query.modelID`: taking a filter off is not a reason to change pane.
    func show(modelID: String) {
        query.modelID = modelID
        pane = .library
    }

    /// Narrows the library to one tag and shows it, for the same reason and on the same terms
    /// as `show(modelID:)`.
    func show(tag: String) {
        query.tag = tag
        pane = .library
    }

    /// Shows one picture in the library grid, selected and scrolled to: the whole of what a
    /// click on its notification means.
    ///
    /// It takes the item rather than a file name because the one hard part is the query. A
    /// person who walked away with the Favorites scope up, or with something typed in the
    /// search field, comes back to a grid that does not list the picture they just clicked
    /// on, and a selection nothing shows is a click that did nothing. So a query that would
    /// not list this picture is widened to one that does — the scope back to everything and
    /// the filters off, the sort left alone, since the sort hides nothing. `LibraryQuery`
    /// already answers "would this list it", so that judgement is not made twice.
    ///
    /// The viewer goes down explicitly: `pane`'s own observer does it, but only when the pane
    /// actually moves, and the notice may well arrive with the library already up.
    func reveal(_ item: LibraryItem) {
        if !query.matches(item) { query = LibraryQuery(sort: query.sort) }
        pane = .library
        viewing = nil
        // Whatever search the widening just emptied is not a search anybody is coming back
        // from, so nothing should bounce them out of the library when the field next clears.
        paneBeforeSearch = nil
        revealing = item.id
        revealToken += 1
    }

    /// Records that the ask this token named has been answered, so no later pane answers it
    /// again. A token that is no longer the newest is ignored: a second ask arriving between
    /// the answer and this call is one nobody has shown yet.
    func markRevealConsumed(_ token: Int) {
        guard token == revealToken else { return }
        revealConsumed = token
    }
}
