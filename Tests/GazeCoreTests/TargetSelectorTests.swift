import CoreGraphics
import Testing
@testable import GazeCore

@Suite("TargetSelector")
struct TargetSelectorTests {
    let left = WindowInfo(id: 1, pid: 100, frame: CGRect(x: 0, y: 0, width: 1280, height: 1440), ownerName: "Left")
    let right = WindowInfo(id: 2, pid: 200, frame: CGRect(x: 1280, y: 0, width: 1280, height: 1440), ownerName: "Right")
    let floating = WindowInfo(id: 3, pid: 300, frame: CGRect(x: 1000, y: 500, width: 600, height: 400), ownerName: "Floating")

    @Test("acquires the window under the gaze after the dwell time")
    func acquiresAfterDwell() {
        var selector = TargetSelector(dwell: 0.25)
        let windows = [left, right]

        #expect(selector.update(point: CGPoint(x: 300, y: 300), windows: windows, now: 0) == nil)
        #expect(selector.update(point: CGPoint(x: 310, y: 300), windows: windows, now: 0.1) == nil)
        #expect(selector.update(point: CGPoint(x: 305, y: 305), windows: windows, now: 0.26) == left)
    }

    @Test("picks the frontmost window when windows overlap")
    func picksFrontmost() {
        var selector = TargetSelector(dwell: 0)
        let frontToBack = [floating, left, right]

        #expect(selector.update(point: CGPoint(x: 1100, y: 600), windows: frontToBack, now: 0) == floating)
    }

    @Test("a brief glance does not switch the target")
    func briefGlanceKeepsTarget() {
        var selector = TargetSelector(dwell: 0.25)
        let windows = [left, right]
        _ = selector.update(point: CGPoint(x: 300, y: 300), windows: windows, now: 0)
        _ = selector.update(point: CGPoint(x: 300, y: 300), windows: windows, now: 0.3)

        #expect(selector.update(point: CGPoint(x: 2000, y: 300), windows: windows, now: 0.4) == left)
        #expect(selector.update(point: CGPoint(x: 300, y: 300), windows: windows, now: 0.5) == left)
        #expect(selector.update(point: CGPoint(x: 2000, y: 300), windows: windows, now: 0.6) == left)
        #expect(selector.update(point: CGPoint(x: 2000, y: 300), windows: windows, now: 0.86) == right)
    }

    @Test("losing the gaze clears the target immediately")
    func lostGazeClears() {
        var selector = TargetSelector(dwell: 0)
        _ = selector.update(point: CGPoint(x: 300, y: 300), windows: [left], now: 0)

        #expect(selector.update(point: nil, windows: [left], now: 0.1) == nil)
        #expect(selector.currentID == nil)
    }

    @Test("looking at empty desktop clears the target after the dwell time")
    func emptyAreaClearsAfterDwell() {
        var selector = TargetSelector(dwell: 0.25)
        let windows = [left]
        _ = selector.update(point: CGPoint(x: 300, y: 300), windows: windows, now: 0)
        _ = selector.update(point: CGPoint(x: 300, y: 300), windows: windows, now: 0.3)

        #expect(selector.update(point: CGPoint(x: 2000, y: 300), windows: windows, now: 0.4) == left)
        #expect(selector.update(point: CGPoint(x: 2000, y: 300), windows: windows, now: 0.7) == nil)
    }

    @Test("a closed target window is dropped")
    func closedWindowDropped() {
        var selector = TargetSelector(dwell: 0)
        _ = selector.update(point: CGPoint(x: 300, y: 300), windows: [left, right], now: 0)

        #expect(selector.update(point: CGPoint(x: 300, y: 300), windows: [right], now: 0.1) == nil)
    }

    @Test("returns the latest frame when the target window moves")
    func returnsLatestFrame() {
        var selector = TargetSelector(dwell: 0)
        _ = selector.update(point: CGPoint(x: 300, y: 300), windows: [left], now: 0)
        let moved = WindowInfo(id: 1, pid: 100, frame: CGRect(x: 0, y: 0, width: 900, height: 1440), ownerName: "Left")

        #expect(selector.update(point: CGPoint(x: 300, y: 300), windows: [moved], now: 0.1)?.frame.width == 900)
    }
}
