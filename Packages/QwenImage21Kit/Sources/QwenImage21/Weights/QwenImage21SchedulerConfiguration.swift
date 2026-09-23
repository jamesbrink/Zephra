import Foundation

/// `scheduler/scheduler_config.json`: the flow-matching noise schedule.
///
/// Unlike klein, 2.1's pipeline reads every one of these fields: the shift is the published
/// line through `(baseImageSeqLen, baseShift)` and `(maxImageSeqLen, maxShift)` evaluated at the
/// image's token count, with no clamp, and the tail is then stretched so the last sigma lands on
/// `shiftTerminal`. All three are silent when wrong, so all three are decoded rather than
/// written down.
public struct QwenImage21SchedulerConfiguration: Hashable, Sendable, Decodable {
    /// Tokens the line's low end is measured at.
    public let baseImageSeqLen: Int
    /// The shift at that token count.
    public let baseShift: Double
    /// Tokens the line's high end is measured at. Nothing clamps to it: a larger image
    /// extrapolates past it, which is what the reference does.
    public let maxImageSeqLen: Int
    /// The shift at that token count.
    public let maxShift: Double
    /// Steps the model was trained over; the timestep the transformer is told is the sigma
    /// times this.
    public let numTrainTimesteps: Int
    /// The static shift, used only when the dynamic one is off.
    public let shift: Double
    /// The value the last sigma is stretched to reach, or nil to leave the tail alone. 2.1
    /// ships 0.02, so the ladder never reaches zero before its appended rung.
    public let shiftTerminal: Double?
    /// Whether the shift is computed from the image's token count. It is.
    public let useDynamicShifting: Bool
    /// How the shift is applied. 2.1 uses `exponential`.
    public let timeShiftType: String

    enum CodingKeys: String, CodingKey {
        case baseImageSeqLen = "base_image_seq_len"
        case baseShift = "base_shift"
        case maxImageSeqLen = "max_image_seq_len"
        case maxShift = "max_shift"
        case numTrainTimesteps = "num_train_timesteps"
        case shift
        case shiftTerminal = "shift_terminal"
        case useDynamicShifting = "use_dynamic_shifting"
        case timeShiftType = "time_shift_type"
    }

    /// The published settings, for a schedule built without a snapshot on the disk.
    public init(
        baseImageSeqLen: Int = 256,
        baseShift: Double = 0.5,
        maxImageSeqLen: Int = 8192,
        maxShift: Double = 0.9,
        numTrainTimesteps: Int = 1000,
        shift: Double = 1,
        shiftTerminal: Double? = 0.02,
        useDynamicShifting: Bool = true,
        timeShiftType: String = "exponential"
    ) {
        self.baseImageSeqLen = baseImageSeqLen
        self.baseShift = baseShift
        self.maxImageSeqLen = maxImageSeqLen
        self.maxShift = maxShift
        self.numTrainTimesteps = numTrainTimesteps
        self.shift = shift
        self.shiftTerminal = shiftTerminal
        self.useDynamicShifting = useDynamicShifting
        self.timeShiftType = timeShiftType
    }

    /// Refuses what the port does not implement: the shift is `exponential`, which is the one
    /// branch `QwenImage21Schedule` has, and the two ends of the line are distinct, since the
    /// slope divides by their difference.
    public func validated() throws -> Self {
        guard timeShiftType == "exponential" else {
            throw QwenImage21ConfigurationError.unsupportedValue(
                field: "time_shift_type", value: timeShiftType)
        }
        guard maxImageSeqLen != baseImageSeqLen else {
            throw QwenImage21ConfigurationError.unsupportedValue(
                field: "max_image_seq_len", value: String(maxImageSeqLen))
        }
        return self
    }
}
