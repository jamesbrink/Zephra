// ZEPHRA-PATCH: opt-in phase timing for the denoise loop, so the fixed per-step cost can be
// split into graph construction on the CPU and kernel execution on the GPU. Off unless
// ZEPHRA_PROFILE_STEP=1 is set, and it adds no work when off.
import Foundation
import MLX

/// Writes one stderr line per timed phase when `ZEPHRA_PROFILE_STEP=1` is in the environment.
public enum ZImageStepProfile {
  /// Whether profiling was requested. Read once; changing the variable mid-process has no effect.
  public static let isEnabled = ProcessInfo.processInfo.environment["ZEPHRA_PROFILE_STEP"] == "1"

  /// Records a phase that was timed elsewhere.
  public static func note(_ label: String, seconds: Double) {
    guard isEnabled else { return }
    let line = String(format: "[profile] %-22@ %8.2f ms\n", label as NSString, seconds * 1000)
    FileHandle.standardError.write(Data(line.utf8))
  }

  /// Records MLX's live and high-water allocation at this point in the program.
  public static func noteMemory(_ label: String) {
    guard isEnabled else { return }
    let snapshot = Memory.snapshot()
    let line = String(
      format: "[profile] %-22@ active %7.2f GB  peak %7.2f GB\n",
      label as NSString,
      Double(snapshot.activeMemory) / 1e9,
      Double(snapshot.peakMemory) / 1e9
    )
    FileHandle.standardError.write(Data(line.utf8))
  }

  /// Times `body` and records it under `label`, returning whatever `body` returned.
  @inline(__always)
  public static func measure<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    guard isEnabled else { return try body() }
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    note(label, seconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
    return value
  }
}
