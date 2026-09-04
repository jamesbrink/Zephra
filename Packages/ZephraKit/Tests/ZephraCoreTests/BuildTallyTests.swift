import Testing

@testable import ZephraCore

@Suite("A build's progress, read out of the packer's own log")
struct BuildTallyTests {
    private static let components = ["transformer", "text_encoder"]
    private static let weights = ["transformer": 24.6, "text_encoder": 8.05]

    @Test("before the packer says anything there is a bar, at nothing, naming the first component")
    func startsAtTheFirstComponent() {
        let tally = BuildTally(components: Self.components, weights: Self.weights)
        #expect(tally.start.fraction == 0)
        #expect(tally.start.component == "transformer")
        #expect(tally.start.completedComponents == 0)
        #expect(tally.start.totalComponents == 2)
    }

    @Test("the bar moves at component boundaries, by what each component holds")
    func fractionsAreWeightedByBytes() {
        var tally = BuildTally(components: Self.components, weights: Self.weights)
        #expect(tally.note("transformer: packing layers.0.attention.to_q")?.fraction == 0)
        // The transformer is 24.6 GB of the 32.65 the two read: three quarters of the bar.
        let second = tally.note("text_encoder: packing model.layers.0.mlp.down_proj")
        #expect(second?.completedComponents == 1)
        #expect(second.map { abs($0.fraction - 24.6 / 32.65) < 0.001 } == true)
        #expect(second?.component == "text encoder")
    }

    @Test("the packer's last line finishes the bar, whatever it was in the middle of")
    func theManifestFinishesIt() {
        var tally = BuildTally(components: Self.components, weights: Self.weights)
        _ = tally.note("transformer: packing something")
        let done = tally.note("wrote 941 packed layers to /tmp/x")
        #expect(done?.fraction == 1)
        #expect(done?.completedComponents == 2)
    }

    @Test("a line about no component at all is not progress")
    func unrelatedLinesReportNothing() {
        var tally = BuildTally(components: Self.components, weights: Self.weights)
        #expect(tally.note("quantizing /tmp/source: transformer 4 bits") == nil)
        #expect(tally.note("copying configs and every directory left at full precision") == nil)
    }

    @Test("without weights the components share the bar equally")
    func unweightedComponentsAreEqual() {
        var tally = BuildTally(components: ["a", "b", "c", "d"])
        #expect(tally.note("c: something")?.fraction == 0.5)
    }
}
