import Testing
import ZephraCore

@testable import Zephra

@Suite("the clip length menu")
struct DurationControlTests {
    @Test("LTX-2.5 offers its shortest clip and one choice per whole second, on its ladder")
    func choices() {
        let choices = DurationControl.choices(ModelCatalog.ltx2Distilled4bit.capabilities)
        // One pass by the second, then every five seconds as a chain of passes: 10 s is 241
        // frames in three, 15 s is 361 in four; 20 s would be 481, past four passes' 457.
        #expect(choices == [9, 25, 49, 73, 97, 121, 241, 361])
        for frames in choices {
            #expect((frames - 1) % 8 == 0)
        }
        // Wan holds one frame, so four passes reach 20 s.
        #expect(DurationControl.choices(ModelCatalog.wan22TI2V5B4bit.capabilities).suffix(3) == [241, 361, 481])
    }

    @Test("a length past one pass says how many passes make it")
    func passes() {
        #expect(DurationControl.label(frames: 241, rate: 24, passes: 3) == "10.0 s · 241 frames · 3 passes")
        #expect(DurationControl.label(frames: 121, rate: 24, passes: 1) == "5.0 s · 121 frames")
    }

    @Test("a label says the seconds and the frames, whole seconds without a decimal")
    func labels() {
        #expect(DurationControl.label(frames: 49, rate: 24) == "2.0 s · 49 frames")
        #expect(DurationControl.label(frames: 121, rate: 24) == "5.0 s · 121 frames")
        #expect(DurationControl.label(frames: 25, rate: 24) == "1.0 s · 25 frames")
        #expect(DurationControl.label(frames: 9, rate: 24) == "0.4 s · 9 frames")
    }
}
