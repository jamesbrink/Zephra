import Foundation
import ZephraCore

/// The one boundary a GPU fault is caught at.
///
/// Every call that puts the device to work — a build, a load, a warm-up, a generation, an
/// upscale — goes through here, and every one of them is already on this actor's serial queue,
/// which is the thread the runtime raises a fault on and the task the boundary cancels.
extension InferenceActor {
    /// Runs `body` inside the runtime's device-error boundary, or plainly where there is no
    /// runtime to ask: the tests and the tools that never built one.
    ///
    /// `body` may therefore find its own task cancelled without anyone having pressed Stop.
    /// What comes out of the boundary in that case is `BackendError.deviceFailed`, never the
    /// `CancellationError` the kit threw.
    func catchingDeviceErrors<R>(_ body: () async throws -> R) async throws -> R {
        guard let runtime else { return try await body() }
        return try await runtime.catchingDeviceErrors(body)
    }
}
