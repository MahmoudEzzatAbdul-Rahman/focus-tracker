import CoreGraphics
import Testing
@testable import GazeCore

@Suite("OneEuroFilter")
struct OneEuroFilterTests {
    @Test("first sample passes through unchanged")
    func firstSamplePassesThrough() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)

        #expect(filter.filter(42, at: 0) == 42)
    }

    @Test("damps jitter on a noisy constant signal")
    func dampsJitter() {
        var rng = SeededGenerator(seed: 11)
        var filter = OneEuroFilter(minCutoff: 0.5, beta: 0.001)
        var rawDeviation = 0.0
        var filteredDeviation = 0.0

        for i in 0..<300 {
            let noisy = 500 + Double.random(in: -60...60, using: &rng)
            let smoothed = filter.filter(noisy, at: Double(i) / 30)
            if i >= 30 {
                rawDeviation += abs(noisy - 500)
                filteredDeviation += abs(smoothed - 500)
            }
        }

        #expect(filteredDeviation < rawDeviation / 3)
    }

    @Test("follows a step change within a second")
    func followsStep() {
        var filter = OneEuroFilter(minCutoff: 0.5, beta: 0.01)
        var output = 0.0

        for i in 0..<30 { output = filter.filter(0, at: Double(i) / 30) }
        for i in 30..<60 { output = filter.filter(1000, at: Double(i) / 30) }

        #expect(output > 950)
    }

    @Test("reset forgets previous state")
    func resetForgetsState() {
        var filter = OneEuroFilter(minCutoff: 0.5, beta: 0)
        _ = filter.filter(0, at: 0)
        _ = filter.filter(0, at: 0.1)

        filter.reset()

        #expect(filter.filter(900, at: 0.2) == 900)
    }

    @Test("ignores samples that do not advance time")
    func ignoresNonAdvancingTime() {
        var filter = OneEuroFilter(minCutoff: 0.5, beta: 0)
        _ = filter.filter(10, at: 1)

        #expect(filter.filter(500, at: 1) == 10)
    }

    @Test("point filter smooths both axes independently")
    func pointFilter() {
        var filter = PointFilter(minCutoff: 1, beta: 0)
        _ = filter.filter(CGPoint(x: 0, y: 100), at: 0)

        let p = filter.filter(CGPoint(x: 100, y: 100), at: 1.0 / 30)

        #expect(p.x > 0 && p.x < 100)
        #expect(p.y == 100)
    }
}
