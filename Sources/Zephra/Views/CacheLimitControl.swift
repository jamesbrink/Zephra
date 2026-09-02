import SwiftUI
import ZephraCore

/// The ceiling on scratch memory the GPU runtime keeps between generations.
///
/// Raising it trades resident memory for warm buffers on the next run; lowering it keeps a
/// small Mac out of swap. The change reaches the runtime as the slider moves, not on relaunch.
struct CacheLimitControl: View {
    @Environment(\.inferenceRuntime) private var runtime
    @AppStorage(AppSettings.cacheLimitMB) private var cacheLimitMB = InferenceTuning.recommendedCacheLimitMB

    private var bounds: ClosedRange<Int> { InferenceTuning.cacheLimitBoundsMB }
    private var recommended: Int { InferenceTuning.recommendedCacheLimitMB }

    private var megabytes: Binding<Double> {
        Binding(
            get: { Double(InferenceTuning.clampedMB(cacheLimitMB)) },
            set: { cacheLimitMB = InferenceTuning.clampedMB(Int($0.rounded())) }
        )
    }

    var body: some View {
        LabeledContent("Scratch cache limit") {
            HStack(spacing: 12) {
                Slider(
                    value: megabytes,
                    in: Double(bounds.lowerBound) ... Double(bounds.upperBound),
                    step: 256
                )
                Text(byteText(cacheLimitMB))
                    .monospacedDigit()
                    .frame(width: 72, alignment: .trailing)
            }
        }
        HStack {
            Text("Recommended for this Mac: \(byteText(recommended)).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset to recommended") { cacheLimitMB = recommended }
                .disabled(InferenceTuning.clampedMB(cacheLimitMB) == recommended)
        }
        .onAppear { apply() }
        .onChange(of: cacheLimitMB) { apply() }
    }

    private func apply() {
        runtime?.setCacheLimit(bytes: InferenceTuning.clampedMB(cacheLimitMB) * InferenceTuning.bytesPerMB)
    }

    private func byteText(_ megabytes: Int) -> String {
        (megabytes * InferenceTuning.bytesPerMB)
            .formatted(.byteCount(style: .memory, spellsOutZero: false))
    }
}

#Preview("Cache limit") {
    Form { Section("GPU memory") { CacheLimitControl() } }
        .formStyle(.grouped)
        .frame(width: 480)
}
