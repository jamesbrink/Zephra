import SwiftUI

extension ZephraApp {
    /// Starts the update checker, once the window is up.
    ///
    /// After the library and the companion rather than before them, for the same reason the
    /// first check waits ten seconds: a launch has a model survey, a load and a folder scan to
    /// get through, and a hundred-byte request for a manifest is the least urgent thing in it.
    ///
    /// Everything that decides whether this launch checks at all is inside `start()` — a frozen
    /// preview build, a copy that is not one that may replace itself, the preference — so this
    /// is one line and stays one line.
    func startUpdates() {
        updates.start()
    }
}
