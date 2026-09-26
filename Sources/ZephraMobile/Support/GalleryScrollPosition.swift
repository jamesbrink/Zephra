import Observation

@MainActor @Observable
final class GalleryScrollPosition {
    var visible: String?
    var anchor: String?
}
