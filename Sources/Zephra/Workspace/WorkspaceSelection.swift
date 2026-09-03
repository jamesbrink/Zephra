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
    var pane: WorkspacePane {
        didSet {
            guard pane != oldValue else { return }
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

    /// Whether the library's inspector is out.
    var inspectorVisible: Bool {
        didSet {
            guard inspectorVisible != oldValue else { return }
            AppSettings.write(inspectorVisible, to: AppSettings.inspectorVisible)
        }
    }

    /// Bumped whenever something asks for the search field. The field watches it and takes
    /// focus; a token rather than a flag, so asking twice in a row works the second time.
    private(set) var searchFocusToken = 0

    /// Where the search started from, so clearing it goes back there rather than leaving you
    /// in the Library you never asked for.
    @ObservationIgnored private var paneBeforeSearch: WorkspacePane?

    /// The window as it was left last time, or the canvas over everything on a first launch.
    init() {
        let defaults = UserDefaults.standard
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

    /// Types into the search, switching panes as the field fills and empties.
    func setSearchText(_ text: String) {
        let had = !query.trimmedText.isEmpty
        query.text = text
        let has = !query.trimmedText.isEmpty
        if has, !had {
            paneBeforeSearch = pane
            pane = .library
        } else if !has, had {
            if let previous = paneBeforeSearch { pane = previous }
            paneBeforeSearch = nil
        }
    }
}
