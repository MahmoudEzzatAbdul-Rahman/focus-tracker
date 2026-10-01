import CoreGraphics
import Testing
@testable import GazeCore

@Suite("GazeStabilizer")
struct GazeStabilizerTests {
    @Test("holds a noisy fixation nearly still")
    func holdsFixation() {
        var rng = SeededGenerator(seed: 21)
        var stabilizer = GazeStabilizer(radius: 120)
        let target = CGPoint(x: 800, y: 500)
        var outputs: [CGPoint] = []

        for i in 0..<120 {
            let noisy = CGPoint(
                x: target.x + Double.random(in: -60...60, using: &rng),
                y: target.y + Double.random(in: -60...60, using: &rng)
            )
            outputs.append(stabilizer.update(noisy, at: Double(i) / 30))
        }

        let settled = outputs.dropFirst(30)
        #expect(settled.allSatisfy { $0.distance(to: target) < 30 })
        // Raw points jump up to ~170 pt between frames; the output should barely shimmer.
        let frameToFrame = zip(settled, settled.dropFirst()).map { $0.distance(to: $1) }
        #expect(frameToFrame.max()! < 8)
    }

    @Test("ignores a single far outlier")
    func ignoresOutlier() {
        var stabilizer = GazeStabilizer(radius: 100)
        for i in 0..<10 { _ = stabilizer.update(CGPoint(x: 500, y: 500), at: Double(i) / 30) }

        let output = stabilizer.update(CGPoint(x: 1400, y: 200), at: 10.0 / 30)
        let after = stabilizer.update(CGPoint(x: 500, y: 500), at: 11.0 / 30)

        #expect(output == CGPoint(x: 500, y: 500))
        #expect(after.distance(to: CGPoint(x: 500, y: 500)) < 1)
    }

    @Test("jumps to a new fixation after a few consistent points")
    func jumpsOnSaccade() {
        var stabilizer = GazeStabilizer(radius: 100, saccadeSamples: 3)
        for i in 0..<10 { _ = stabilizer.update(CGPoint(x: 500, y: 500), at: Double(i) / 30) }

        let first = stabilizer.update(CGPoint(x: 1200, y: 300), at: 10.0 / 30)
        let second = stabilizer.update(CGPoint(x: 1210, y: 310), at: 11.0 / 30)
        let third = stabilizer.update(CGPoint(x: 1190, y: 290), at: 12.0 / 30)

        #expect(first == CGPoint(x: 500, y: 500))
        #expect(second == CGPoint(x: 500, y: 500))
        #expect(third.distance(to: CGPoint(x: 1200, y: 300)) < 1)
    }

    @Test("does not jump on scattered points that disagree with each other")
    func ignoresScatter() {
        var stabilizer = GazeStabilizer(radius: 100, saccadeSamples: 3)
        for i in 0..<10 { _ = stabilizer.update(CGPoint(x: 500, y: 500), at: Double(i) / 30) }
        let scattered = [CGPoint(x: 1200, y: 300), CGPoint(x: 100, y: 900), CGPoint(x: 1300, y: 900), CGPoint(x: 0, y: 0)]

        let outputs = scattered.enumerated().map { stabilizer.update($1, at: Double(10 + $0) / 30) }

        #expect(outputs.allSatisfy { $0 == CGPoint(x: 500, y: 500) })
    }

    @Test("ignores samples that do not advance time, and reset starts over")
    func timeAndReset() {
        var stabilizer = GazeStabilizer(radius: 100, saccadeSamples: 1)
        _ = stabilizer.update(CGPoint(x: 500, y: 500), at: 1)

        let stale = stabilizer.update(CGPoint(x: 1000, y: 1000), at: 1)
        #expect(stale == CGPoint(x: 500, y: 500))

        stabilizer.reset()
        #expect(stabilizer.fixation == nil)
        let fresh = stabilizer.update(CGPoint(x: 1000, y: 1000), at: 0.5)
        #expect(fresh == CGPoint(x: 1000, y: 1000))
    }
}

@Suite("BlinkDetector")
struct BlinkDetectorTests {
    @Test("flags a sharp drop in eye openness and recovers after it")
    func flagsBlink() {
        var detector = BlinkDetector()
        let open = (0..<20).map { _ in detector.isBlinking(openness: 0.3) }
        let closing = detector.isBlinking(openness: 0.1)
        let closed = detector.isBlinking(openness: 0.05)
        let reopened = detector.isBlinking(openness: 0.29)

        #expect(!open.contains(true))
        #expect(closing)
        #expect(closed)
        #expect(!reopened)
    }

    @Test("blink frames don't drag the baseline down")
    func baselineIgnoresBlinks() throws {
        var detector = BlinkDetector()
        _ = detector.isBlinking(openness: 0.3)
        for _ in 0..<10 { _ = detector.isBlinking(openness: 0.05) }

        #expect(try #require(detector.baseline) == 0.3)
    }

    @Test("a closed-looking eye that lasts becomes the new baseline")
    func rebaselinesAfterLongRun() throws {
        var detector = BlinkDetector(maximumBlinkFrames: 15)
        _ = detector.isBlinking(openness: 0.3)

        let flagged = (0..<20).map { _ in detector.isBlinking(openness: 0.1) }

        #expect(flagged.prefix(15).allSatisfy { $0 })
        #expect(!flagged.suffix(4).contains(true))
        #expect(try #require(detector.baseline) < 0.11)
    }

    @Test("adapts to a gradual change, like leaning back")
    func adaptsGradually() throws {
        var detector = BlinkDetector()
        var openness = 0.3
        let flagged = (0..<200).map { _ in
            openness *= 0.995
            return detector.isBlinking(openness: openness)
        }

        #expect(!flagged.contains(true))
        #expect(try #require(detector.baseline) < 0.15)
        detector.reset()
        #expect(detector.baseline == nil)
    }
}

@Suite("FeatureMedianFilter")
struct FeatureMedianFilterTests {
    @Test("removes a single-frame spike")
    func removesSpike() {
        var filter = FeatureMedianFilter()
        _ = filter.filter(uniformFeatures(1))
        _ = filter.filter(uniformFeatures(1))

        let spike = filter.filter(uniformFeatures(50))
        let after = filter.filter(uniformFeatures(1))

        #expect(spike == uniformFeatures(1))
        #expect(after == uniformFeatures(1))
    }

    @Test("passes a lasting change through on its second frame")
    func passesStep() {
        var filter = FeatureMedianFilter()
        for _ in 0..<3 { _ = filter.filter(uniformFeatures(1)) }

        let firstFrame = filter.filter(uniformFeatures(5))
        let secondFrame = filter.filter(uniformFeatures(5))

        #expect(firstFrame == uniformFeatures(1))
        #expect(secondFrame == uniformFeatures(5))
    }

    @Test("passes frames through until it has three, and after reset")
    func warmUp() {
        var filter = FeatureMedianFilter()

        let first = filter.filter(uniformFeatures(1))
        let second = filter.filter(uniformFeatures(9))
        filter.reset()
        let afterReset = filter.filter(uniformFeatures(4))

        #expect(first == uniformFeatures(1))
        #expect(second == uniformFeatures(9))
        #expect(afterReset == uniformFeatures(4))
    }

    @Test("median of three works in every order")
    func median() {
        for values in [[1.0, 2, 3], [3, 1, 2], [2, 3, 1], [3, 2, 1], [2, 2, 9]] {
            #expect(FeatureMedianFilter.median(values[0], values[1], values[2]) == values.sorted()[1])
        }
    }
}
