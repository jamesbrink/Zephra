import Testing

@testable import ZephraCore

@Suite("What a Mac that has not got the memory is told")
struct MemoryShortfallTests {
    @Test("a busy machine is told the two figures and asked to free some")
    func theBusyMachineSentence() {
        let shortfall = MemoryShortfall(
            modelName: "LTX-2.5 · with sound", neededBytes: 28_700_000_000,
            freeBytes: 19_200_000_000, phase: .load, remedy: .quitOtherApps)
        #expect(
            shortfall.sentence
                == "LTX-2.5 · with sound needs 28.7 GB and 19.2 GB is free. "
                    + "Quit other apps and retry.")
    }

    @Test("a model held resident by choice is sent to the preference that would fit it")
    func theResidentByChoiceSentence() {
        let shortfall = MemoryShortfall(
            modelName: "Z-Image Turbo · 8-bit", neededBytes: 17_700_000_000,
            freeBytes: 12_100_000_000, phase: .load, remedy: .streamFromDisk)
        #expect(
            shortfall.sentence
                == "Z-Image Turbo · 8-bit needs 17.7 GB and 12.1 GB is free. "
                    + "Set Stream weights from disk to Automatic in Settings > Performance.")
    }

    @Test("the figures are read the way every other gigabyte in the app is")
    func gigabytesAreRoundedOneWay() {
        // A whole number stays whole, and a tenth is a tenth: the same rule `ByteCount` gives
        // the picker, so a refusal and a "Needs N GB" label never quote one number two ways.
        let whole = MemoryShortfall(
            modelName: "Model", neededBytes: 12_000_000_000, freeBytes: 8_040_000_000,
            phase: .run, remedy: .quitOtherApps)
        #expect(whole.sentence.hasPrefix("Model needs 12 GB and 8 GB is free."))
        let tenths = MemoryShortfall(
            modelName: "Model", neededBytes: 12_050_000_000, freeBytes: 8_949_000_000,
            phase: .run, remedy: .quitOtherApps)
        #expect(tenths.sentence.hasPrefix("Model needs 12.1 GB and 8.9 GB is free."))
    }
}
