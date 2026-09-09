import SwiftUI
import ZephraEngine

/// What the window shows: the workspace, or the first-launch chooser in front of it.
///
/// Loading the model is asked for here rather than in `RootView`, because on a first launch
/// `RootView` is not built at all and the chooser still needs to know what is on disk to say
/// what each model costs. `loadingModel: false` is the whole of the change: the survey runs,
/// nothing is fetched, and the choice made on the next screen is what starts a transfer.
struct WelcomeHost: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WelcomeGate.self) private var welcome
    @Environment(\.memoryBudget) private var budget

    var body: some View {
        Group {
            if welcome.isShowing { WelcomeView() } else { RootView() }
        }
        .task {
            await store.bootstrapFromInterface(loadingModel: !welcome.isShowing)
            // The survey found a model already here, so the chooser settles itself and names
            // the one to continue on. It answers nil for every other ending — including a Skip
            // pressed while the survey was still running, which must stay a skip.
            if let ready = welcome.settle(
                availability: store.availability, budget: budget, current: store.descriptor)
            {
                store.chooseFirstModel(ready)
            }
            // `ZEPHRA_GENERATE_ON_LAUNCH` waits for the model to be ready, and with the
            // chooser up nothing is loading and nothing ever will be until somebody presses a
            // card. The hook is for an unattended launch on a Mac that is already set up, so
            // here it is inert rather than a poll that never ends.
            guard !welcome.isShowing else { return }
            await LaunchGeneration.run(on: store)
        }
    }
}

#Preview("Chooser") {
    WelcomeHost()
        .frame(width: 1200, height: 840)
        .environment(WelcomeGate(isShowing: true))
        .environment(GenerationStore.preview(state: .idle))
}
