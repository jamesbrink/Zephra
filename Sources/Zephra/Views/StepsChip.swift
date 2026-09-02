import SwiftUI
import ZephraEngine

/// How many denoising steps to run. More steps means more detail and more seconds.
struct StepsChip: View {
    @Environment(GenerationStore.self) private var store
    @State private var isShowingStepper = false

    var body: some View {
        Button {
            isShowingStepper = true
        } label: {
            Text("\(store.settings.steps) steps")
                .font(.callout)
                .monospacedDigit()
        }
        .buttonStyle(.accessoryBar)
        .help("Denoising steps")
        .popover(isPresented: $isShowingStepper, arrowEdge: .bottom) {
            stepper
        }
    }

    private var stepper: some View {
        @Bindable var store = store
        let bounds = store.descriptor.capabilities.stepBounds
        return Stepper(value: $store.settings.steps, in: bounds) {
            Text("\(store.settings.steps) steps")
                .monospacedDigit()
        }
        .padding(14)
        .frame(width: 190)
    }
}

#Preview("Steps") {
    StepsChip()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
