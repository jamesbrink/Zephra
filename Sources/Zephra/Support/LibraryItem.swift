import ZephraEngine

/// Says which `LibraryItem` the app target means.
///
/// `DeveloperToolsSupport` — which SwiftUI and AppKit both pull in — exports a `LibraryItem` of
/// its own, for the Xcode library's preview items. Every view that names one would otherwise
/// have to spell out the module, so it is said once here and the name is unambiguous everywhere
/// else: a declaration in this module wins over both imported ones.
typealias LibraryItem = ZephraEngine.LibraryItem
