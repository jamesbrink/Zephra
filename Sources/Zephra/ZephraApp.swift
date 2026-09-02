import SwiftUI

@main
struct ZephraApp: App {
  var body: some Scene {
    WindowGroup("Zephra") {
      RootView()
    }
    .defaultSize(width: 1200, height: 840)
    .windowToolbarStyle(.unified)
  }
}
