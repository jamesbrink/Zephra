import SwiftUI

/// The two windows the application menu's About item leads to: About Zephra, and the
/// Acknowledgments it opens onto.
///
/// Two `Window` scenes rather than the standard About panel, because the standard panel has
/// one slot for everything under the version — its credits — and seven hundred lines of
/// license text in a small scrolling box is not what a person opening About wants to read.
/// The Mac's own pattern (Xcode's, and most apps') is a short About window with an
/// Acknowledgments button that opens the notices in a window of their own, which is what
/// these are. Neither opens at launch nor comes back with the session: the main window is
/// the one that is presented on every launch.
struct AboutScenes: Scene {
    static let aboutID = "about"
    static let acknowledgmentsID = "acknowledgments"

    var body: some Scene {
        Window("About \(AppFacts.name)", id: Self.aboutID) {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Acknowledgments", id: Self.acknowledgmentsID) {
            AcknowledgmentsView()
        }
        .defaultSize(width: 560, height: 640)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
