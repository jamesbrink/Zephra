import Testing
import ZephraCore

@testable import Zephra

@Suite("the clip length menu")
struct DurationControlTests {
    @Test("LTX-2.5 offers its shortest clip and one choice per whole second, on its ladder")
    func choices() {
        let choices = DurationControl.choices(ModelCatalog.ltx2Distilled4bit.capabilities)
        #expect(choices == [9, 25, 49, 73, 97, 121])
        for frames in choices {
            #expect((frames - 1) % 8 == 0)
        }
    }

    @Test("a label says the seconds and the frames, whole seconds without a decimal")
    func labels() {
        #expect(DurationControl.label(frames: 49, rate: 24) == "2.0 s · 49 frames")
        #expect(DurationControl.label(frames: 121, rate: 24) == "5.0 s · 121 frames")
        #expect(DurationControl.label(frames: 25, rate: 24) == "1.0 s · 25 frames")
        #expect(DurationControl.label(frames: 9, rate: 24) == "0.4 s · 9 frames")
    }
}
