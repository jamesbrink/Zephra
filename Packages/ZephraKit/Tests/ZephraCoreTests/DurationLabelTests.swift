import Testing
import ZephraCore

@Suite("A duration as a person reads it")
struct DurationLabelTests {
    @Test("under a minute the seconds are whole unless a fraction is asked for and there is one")
    func underAMinute() {
        #expect(DurationLabel.text(seconds: 45) == "45 s")
        #expect(DurationLabel.text(seconds: 44.6) == "45 s")
        #expect(DurationLabel.text(seconds: 0.375, fraction: true) == "0.4 s")
        #expect(DurationLabel.text(seconds: 2, fraction: true) == "2 s")
        #expect(DurationLabel.text(seconds: 2.04, fraction: true) == "2.0 s")
        #expect(DurationLabel.text(seconds: -3) == "0 s")
    }

    @Test("from a minute to ten, minutes and seconds; the fraction is never carried past a minute")
    func minutesAndSeconds() {
        #expect(DurationLabel.text(seconds: 60) == "1 min")
        #expect(DurationLabel.text(seconds: 80) == "1 min 20 s")
        #expect(DurationLabel.text(seconds: 559) == "9 min 19 s")
        #expect(DurationLabel.text(seconds: 66.7, fraction: true) == "1 min 7 s")
    }

    @Test("past ten minutes the seconds go, and past an hour the minutes ride on the hours")
    func minutesThenHours() {
        #expect(DurationLabel.text(seconds: 600) == "10 min")
        #expect(DurationLabel.text(seconds: 1500) == "25 min")
        #expect(DurationLabel.text(seconds: 3600) == "1 hr")
        #expect(DurationLabel.text(seconds: 3900) == "1 hr 5 min")
        #expect(DurationLabel.text(seconds: 7200) == "2 hr")
    }
}
