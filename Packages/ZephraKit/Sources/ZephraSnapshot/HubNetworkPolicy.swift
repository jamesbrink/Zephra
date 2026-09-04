import Foundation

/// Whether the hub client may download on a metered connection. It may.
///
/// The hub client watches the network path and refuses to transfer anything on one it deems
/// expensive or constrained — a phone's hotspot, some VPNs — reporting the repository as
/// unavailable offline instead. Its one switch is an environment variable, read on every
/// request. The download's size is on the screen before it starts, so whether to spend it on
/// a hotspot is the user's decision, and the variable is set before the first request rather
/// than left to the client. Process-wide, because that is the only granularity offered.
public nonisolated enum HubNetworkPolicy {
    /// The variable the hub client checks, spelled the way it spells it.
    static let variable = "CI_DISABLE_NETWORK_MONITOR"

    /// Lets the hub client download on any connected path. Idempotent; call it before a
    /// download, every time, and nothing is lost.
    public static func allowMeteredDownloads() {
        setenv(variable, "1", 1)
    }
}
