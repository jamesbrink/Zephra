import Foundation
import SwiftUI
import Testing

@testable import ZephraMobile

/// Pulling a picture down to close the viewer is a handful of rules about one finger, and a
/// finger the pager is reading at the same time. These are the rules.
@Suite("Pulling a picture down")
struct ViewerPoseTests {
    private let distance = MobileChrome.viewerDismissDistance

    @Test("A drag that went further sideways than down is the pager's")
    func sidewaysIsHorizontal() {
        #expect(ViewerPose.Pull.axis(for: CGSize(width: 30, height: 10)) == .horizontal)
        #expect(ViewerPose.Pull.axis(for: CGSize(width: -30, height: 10)) == .horizontal)
    }

    @Test("A drag that went further down than sideways is a pull, and so is a tie")
    func downwardsIsVertical() {
        #expect(ViewerPose.Pull.axis(for: CGSize(width: 10, height: 30)) == .vertical)
        #expect(ViewerPose.Pull.axis(for: CGSize(width: 20, height: 20)) == .vertical)
    }

    @Test("The axis is locked by the first change and never revisited")
    func axisLocksOnce() {
        var pull = ViewerPose.Pull()
        pull.follow(CGSize(width: 40, height: 5))
        #expect(pull.axis == .horizontal)
        pull.follow(CGSize(width: 40, height: 300))
        #expect(pull.axis == .horizontal)
        #expect(pull.offset == 0)
    }

    @Test("A pull follows the finger down and never goes up")
    func pullFollowsDownwards() {
        var pull = ViewerPose.Pull()
        pull.follow(CGSize(width: 2, height: 50))
        #expect(pull.axis == .vertical)
        #expect(pull.offset == 50)
        pull.follow(CGSize(width: 2, height: -20))
        #expect(pull.offset == 0)
    }

    @Test("Progress runs from rest to the distance and stops there")
    func progressIsClamped() {
        var pull = ViewerPose.Pull()
        #expect(pull.progress == 0)
        pull.follow(CGSize(width: 0, height: distance / 2))
        #expect(pull.progress == 0.5)
        pull.follow(CGSize(width: 0, height: distance * 3))
        #expect(pull.progress == 1)
    }

    @Test("Letting go past the distance closes the viewer")
    func pastTheDistanceDismisses() {
        #expect(ViewerPose.Pull.shouldDismiss(offset: distance, predicted: 0))
        #expect(!ViewerPose.Pull.shouldDismiss(offset: distance - 1, predicted: 0))
    }

    @Test("A fling that would have carried it well past the distance closes it too")
    func flingDismisses() {
        #expect(ViewerPose.Pull.shouldDismiss(offset: 40, predicted: distance * 2))
        #expect(!ViewerPose.Pull.shouldDismiss(offset: 40, predicted: distance * 2 - 1))
    }

    @Test("A fling is credited with a quarter of a second at its lift-off speed")
    func flingIsProjected() {
        #expect(ViewerPose.Pull.predictedEnd(offset: 40, velocity: 1400) == 390)
        #expect(ViewerPose.Pull.predictedEnd(offset: 40, velocity: -400) == -60)
        #expect(ViewerPose.Pull.shouldDismiss(
            offset: 40, predicted: ViewerPose.Pull.predictedEnd(offset: 40, velocity: 1400)))
        #expect(!ViewerPose.Pull.shouldDismiss(
            offset: 40, predicted: ViewerPose.Pull.predictedEnd(offset: 40, velocity: 400)))
    }

    @Test("Releasing puts the picture back and frees the axis for the next drag")
    func releaseResets() {
        var pull = ViewerPose.Pull()
        pull.follow(CGSize(width: 0, height: 90))
        pull.release()
        #expect(pull == ViewerPose.Pull())
        pull.follow(CGSize(width: 90, height: 0))
        #expect(pull.axis == .horizontal)
    }

    @Test("A viewer opens on the picture it was asked for, with its chrome up and fitted")
    func opensAtRest() {
        let pose = ViewerPose(current: "one.png")
        #expect(pose.current == "one.png")
        #expect(!pose.chromeIsHidden)
        #expect(!pose.isZoomed)
        #expect(pose.pull == ViewerPose.Pull())
    }
}
