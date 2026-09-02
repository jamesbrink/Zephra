import Foundation
import MLX

// ZEPHRA-PATCH: (new file) an opt-in, TeaCache-style residual cache for the denoise loop, so
// the cost of a whole step of transformer blocks can be skipped when the step's input barely
// moved. Off unless ZEPHRA_STEP_CACHE names a threshold; this is a measurement, not a default.
/// Reuses one denoising step's transformer residual on the next step.
///
/// The relative L1 change of the block stack's input between consecutive steps is accumulated;
/// while that running total stays under the threshold the 32 main layers are skipped and the
/// previous step's residual (output minus input) is added to the current input instead. Any
/// step that does run resets the total, so error cannot compound without a real step in between.
final class ZImageStepCache {
  /// The threshold from `ZEPHRA_STEP_CACHE`, or nil when the cache is off.
  static let threshold: Float? = {
    guard let raw = ProcessInfo.processInfo.environment["ZEPHRA_STEP_CACHE"],
      let value = Float(raw), value > 0
    else { return nil }
    return value
  }()

  /// Whether any transformer should build one of these at all.
  static var isEnabled: Bool { threshold != nil }

  private var previousInput: MLXArray?
  private var residual: MLXArray?
  private var accumulated: Float = 0

  /// Forgets everything. Called at the start of every generation: two generations share no
  /// trajectory, so the previous one's residual is meaningless to this one.
  func reset() {
    previousInput = nil
    residual = nil
    accumulated = 0
  }

  /// The output to use in place of running the blocks, or nil when they must run.
  func reuse(for input: MLXArray) -> MLXArray? {
    guard let threshold = Self.threshold else { return nil }
    defer { previousInput = input }
    guard let previous = previousInput, let residual else {
      accumulated = 0
      return nil
    }
    accumulated += Self.relativeL1(input, previous)
    guard accumulated < threshold else {
      note("run  accumulated=\(accumulated)")
      accumulated = 0
      return nil
    }
    note("skip accumulated=\(accumulated)")
    return input + residual
  }

  /// Records what the blocks did to `input`, for the next step to reuse.
  func store(input: MLXArray, output: MLXArray) {
    residual = output - input
  }

  /// One line per decision on stderr. The cache only exists when it is being measured, so
  /// saying what it decided is the whole point of running with it on.
  private func note(_ message: String) {
    FileHandle.standardError.write(Data("step cache: \(message)\n".utf8))
  }

  /// Mean absolute change between two step inputs, relative to the earlier one's own scale.
  /// Forces an evaluation, which is the price of deciding on the host.
  private static func relativeL1(_ current: MLXArray, _ previous: MLXArray) -> Float {
    let change = MLX.mean(MLX.abs(current - previous))
    let scale = MLX.mean(MLX.abs(previous))
    MLX.eval(change, scale)
    let base = scale.item(Float.self)
    guard base > 0 else { return 0 }
    return change.item(Float.self) / base
  }
}
