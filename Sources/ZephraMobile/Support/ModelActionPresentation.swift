import Observation

@MainActor @Observable
final class ModelActionPresentation {
    var failure: String?
    var busy = false
    var confirming = false
    func ask(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        failure = nil; busy = true
        Task {
            defer { busy = false }
            do { try await work() } catch { failure = error.localizedDescription }
        }
    }
}
