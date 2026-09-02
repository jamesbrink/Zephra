// Spike: proves the vendored ZImage library and mlx-swift Metal kernels link and run.
import Foundation
import MLX
import ZImage

let info = GPU.deviceInfo()
print("metal device: \(info["device_name"] ?? "unknown")")
print("max recommended working set: \(GPU.maxRecommendedWorkingSetBytes() / 1_000_000) MB")
let pipeline = ZImagePipeline()
print("pipeline loaded: \(pipeline.isLoaded)")
let x = MLXArray([1.0, 2.0, 3.0]) * 2
eval(x)
print("mlx compute ok: \(x)")
