import Foundation

/// `scheduler/scheduler_config.json`: the flow-matching noise schedule.
///
/// Every field here changes the sigmas, and a wrong sigma schedule does not fail — it produces a
/// slightly worse image. `shiftTerminal` in particular has no counterpart in older flow-matching
/// schedulers, so it is the one most easily dropped on the way in.
public struct QwenImageSchedulerConfiguration: Hashable, Sendable, Decodable {
    /// Steps the model was trained over.
    public let numTrainTimesteps: Int
    /// Static shift, used only when dynamic shifting is off.
    public let shift: Double
    /// Whether the shift is computed from the image's token count instead of taken from `shift`.
    public let useDynamicShifting: Bool
    /// Shift at `baseImageSeqLen` tokens.
    public let baseShift: Double
    /// Shift at `maxImageSeqLen` tokens.
    public let maxShift: Double
    /// Token count `baseShift` was measured at.
    public let baseImageSeqLen: Int
    /// Token count `maxShift` was measured at.
    public let maxImageSeqLen: Int
    /// The value the last sigma is stretched to reach, or nil to leave the tail alone.
    public let shiftTerminal: Double?
    /// How the shift is applied. Qwen-Image uses `exponential`.
    public let timeShiftType: String

    enum CodingKeys: String, CodingKey {
        case shift
        case numTrainTimesteps = "num_train_timesteps"
        case useDynamicShifting = "use_dynamic_shifting"
        case baseShift = "base_shift"
        case maxShift = "max_shift"
        case baseImageSeqLen = "base_image_seq_len"
        case maxImageSeqLen = "max_image_seq_len"
        case shiftTerminal = "shift_terminal"
        case timeShiftType = "time_shift_type"
    }

    /// Refuses what the port does not implement: the shift is `exponential` (the only branch
    /// `FlowMatchEulerScheduler` has), and the timestep embedding scales a sigma by exactly a
    /// thousand, which is `num_train_timesteps` folded into the port.
    public func validated() throws -> Self {
        guard timeShiftType == "exponential" else {
            throw QwenImageConfigurationError.unsupportedValue(
                field: "time_shift_type", value: timeShiftType)
        }
        guard numTrainTimesteps == 1000 else {
            throw QwenImageConfigurationError.unsupportedValue(
                field: "num_train_timesteps", value: String(numTrainTimesteps))
        }
        return self
    }
}
