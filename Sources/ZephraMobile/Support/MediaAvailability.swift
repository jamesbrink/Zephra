import Observation

@MainActor @Observable
final class MediaAvailability {
    var isHeld = false
    let action = MediaAction()
}
