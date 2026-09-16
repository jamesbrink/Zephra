/// What kind of command-buffer failure the GPU driver reported, read out of the one message
/// MLX hands up.
///
/// MLX composes every command-buffer failure with a single format string —
/// `"[METAL] Command buffer execution failed: {}."` over the `NSError`'s
/// `localizedDescription` — and IOGPU composes that description with `%s (%08x:%s)`, so the
/// text always carries the driver's own description, the zero-padded code and the enum name.
/// The `NSError` itself never reaches Swift (MLX drops it inside the completion handler), and
/// its `code` would be Metal's rather than IOGPU's anyway, so the text is all there is.
///
/// The distinction that matters is `.lost` against everything else. A victim is a run the
/// driver discarded while recovering from somebody else's fault, and the next run works; an
/// ignored submission is the driver refusing this process's command buffers because it holds
/// it responsible for earlier faults, and no published report shows a process coming back
/// from one without being relaunched.
public enum DeviceFaultKind: String, Sendable, Hashable, CaseIterable {
    /// `kIOGPUCommandBufferCallbackErrorSubmissionsIgnored` (4). Terminal for this process.
    case lost
    /// `kIOGPUCommandBufferCallbackErrorInnocentVictim` (5). Somebody else's fault, this
    /// process's buffer discarded in the recovery. One lost run; try again.
    case victim
    /// `kIOGPUCommandBufferCallbackErrorHang` (3).
    case hang
    /// `kIOGPUCommandBufferCallbackErrorTimeout` (2).
    case timeout
    /// `kIOGPUCommandBufferCallbackErrorPageFault` (0x0b).
    case pageFault
    /// A command-buffer failure whose enum name is not one of the five above: a code this
    /// table has not learned, or a description Metal reworded past recognition.
    case other

    /// The prefix MLX writes before every command-buffer failure, and the one thing that says
    /// a message is about the device at all. A message without it is a shape error, a failed
    /// library build or an allocation refusal, none of which is a GPU fault.
    public static let messagePrefix = "[METAL] Command buffer execution failed:"

    /// The kind `message` reports, or nil when it is not a command-buffer failure.
    ///
    /// The enum name is matched case-insensitively and corroborated with the hex code, which is
    /// what keeps a near-miss from reading as a match. Where only the name is there — Metal may
    /// prepend wording of its own, and has been seen to drop the code — the name alone decides:
    /// it is IOGPU's own, and every published report carries it.
    public init?(message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(Self.messagePrefix) else { return nil }
        let lowered = text.lowercased()
        if let both = Self.table.first(where: {
            lowered.contains($0.name) && lowered.contains($0.code)
        }) {
            self = both.kind
        } else if let named = Self.table.first(where: { lowered.contains($0.name) }) {
            self = named.kind
        } else {
            self = .other
        }
    }

    /// Whether this fault ends the process's use of the GPU rather than one run.
    public var isLost: Bool { self == .lost }

    /// What a log line calls it.
    public var logName: String {
        switch self {
        case .lost: "an ignored submission"
        case .victim: "an innocent victim"
        case .hang: "a hang"
        case .timeout: "a timeout"
        case .pageFault: "an address fault"
        case .other: "an unknown command-buffer failure"
        }
    }

    /// IOGPU's enum names and codes, lowercased once so the match is a plain `contains`.
    private static let table: [(kind: DeviceFaultKind, name: String, code: String)] = [
        (.lost, "kiogpucommandbuffercallbackerrorsubmissionsignored", "00000004"),
        (.victim, "kiogpucommandbuffercallbackerrorinnocentvictim", "00000005"),
        (.hang, "kiogpucommandbuffercallbackerrorhang", "00000003"),
        (.timeout, "kiogpucommandbuffercallbackerrortimeout", "00000002"),
        (.pageFault, "kiogpucommandbuffercallbackerrorpagefault", "0000000b"),
    ]
}
