import MLX
import Metal
import os

/// Which generation of Apple GPU this process runs on, for the one place it matters.
///
/// mlx-swift up to 0.31.6 JIT-compiles the bfloat16 split-K steel GEMM with the wrong dtype
/// on M5-class GPUs (ml-explore/mlx#3797, fixed by #3810 in mlx 0.32.0, which no mlx-swift
/// release carries yet). klein's backend reads this once to decide its stream's dtype; nothing
/// else should. When the bump lands and both of `Flux2Kit`'s probes pass on an M5, this goes.
public enum GPUGeneration {
    /// Whether the GPU is an M5 or later.
    ///
    /// Two readings, either enough: the device's Metal family — `apple10` is the M5's, and an
    /// M4 Max answers no to it — or the device name naming an M5. Read once and logged with
    /// the name MLX reports, so the string an M5 gives is on record. False on a Mac without a
    /// Metal device, where nothing runs anyway. Unverified on an M5: none of the project's
    /// Macs is one.
    public static let isM5Class: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        var byFamily = false
        if #available(macOS 26, *) {
            byFamily = device.supportsFamily(.apple10)
        }
        let byName = device.name.split(separator: " ").contains { $0.hasPrefix("M5") }
        let result = byFamily || byName
        Logger(subsystem: "io.zephra", category: "runtime").info(
            "GPU \(device.name, privacy: .public) (\(GPU.deviceInfo().architecture, privacy: .public)): M5-class \(result, privacy: .public), by family \(byFamily, privacy: .public), by name \(byName, privacy: .public)"
        )
        return result
    }()
}
