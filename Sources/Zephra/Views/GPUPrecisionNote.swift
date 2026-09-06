import SwiftUI
import ZephraCore

/// Why FLUX.2 klein is slower than the catalog says on an M5-class GPU, said where the other
/// performance facts are.
///
/// mlx-swift up to 0.31.6 miscompiles the bfloat16 split-K matmul on M5-class GPUs, so
/// `ZephraBackendFlux2` runs klein's transformer in float32 there, at about three times the
/// step time (see "Conventions" in AGENTS.md). Nothing is offered to switch: the gate is a
/// workaround for a dependency bug, and `ZEPHRA_DIT_DTYPE=bf16` at launch is the override for
/// whoever wants to find out whether the bug is still there. Shown only on an M5, because on
/// every other Mac there is nothing to explain.
struct GPUPrecisionNote: View {
    @Environment(\.inferenceRuntime) private var runtime

    var body: some View {
        if runtime?.isM5ClassGPU() == true {
            Text("This Mac's GPU is M5-class, so FLUX.2 klein runs its transformer in float32 "
                + "here, at about three times the step time, to work around an mlx-swift bug in "
                + "the bfloat16 matmul on this generation. Other models are unaffected. "
                + "Launching with ZEPHRA_DIT_DTYPE=bf16 runs it the ordinary way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
