import CoreGraphics
import Foundation
import Testing
@testable import GazeCore

@Suite("SelfCalibration")
struct SelfCalibrationTests {
    let seat = HeadPosition(x: 0, y: 260, distance: 550)

    @Test("accepts every usable click while bootstrapping")
    func bootstrapAcceptsAll() {
        var rng = SeededGenerator(seed: 1)
        var calibration = SelfCalibration()
        let user = SyntheticUser.typical

        for _ in 0..<SelfCalibration.bootstrapSamples {
            var sample = user.randomSample(head: seat, using: &rng)
            sample.screenPoint = CGPoint(x: 1500 - sample.screenPoint.x, y: sample.screenPoint.y)
            let outcome = calibration.add(click: sample, geometry: testGeometry)
            #expect(outcome.isAccepted)
        }

        #expect(calibration.samples.count == SelfCalibration.bootstrapSamples)
    }

    @Test("learns from clicks until the error is small")
    func learnsFromClicks() throws {
        var rng = SeededGenerator(seed: 2)
        var calibration = SelfCalibration()
        let user = SyntheticUser.typical
        let probe = user.randomSample(head: seat, using: &rng)
        let errorBefore = try #require(calibration.model.predict(probe.features, geometry: testGeometry)).distance(to: probe.screenPoint)

        for _ in 0..<80 {
            calibration.add(click: user.randomSample(head: jittered(seat, by: 30, using: &rng), using: &rng), geometry: testGeometry)
        }

        let errorAfter = try #require(calibration.model.predict(probe.features, geometry: testGeometry)).distance(to: probe.screenPoint)
        #expect(errorAfter < 80)
        #expect(errorAfter < errorBefore / 2)
        #expect(try #require(calibration.typicalError) < 80)
    }

    @Test("rejects a click far from where the user was looking, once trained")
    func rejectsFarClick() {
        var rng = SeededGenerator(seed: 3)
        var calibration = SelfCalibration()
        let user = SyntheticUser.typical
        for _ in 0..<60 {
            calibration.add(click: user.randomSample(head: seat, using: &rng), geometry: testGeometry)
        }
        let count = calibration.samples.count
        let looking = user.features(head: seat, lookingAt: CGPoint(x: 100, y: 100), yaw: 0, pitch: 0.1)

        let outcome = calibration.add(click: GazeSample(features: looking, screenPoint: CGPoint(x: 1400, y: 900)), geometry: testGeometry)

        #expect(!outcome.isAccepted)
        #expect(calibration.samples.count == count)
    }

    @Test("evicts the oldest sample of a full grid cell")
    func evictsOldestInCell() {
        var calibration = SelfCalibration()
        let user = SyntheticUser.typical
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<(SelfCalibration.samplesPerCell + 5) {
            let point = CGPoint(x: 50 + Double(i), y: 50)
            let sample = GazeSample(features: user.features(head: seat, lookingAt: point, yaw: 0, pitch: 0), screenPoint: point)
            calibration.add(contentsOf: [sample], geometry: testGeometry, at: start.addingTimeInterval(Double(i)))
        }
        let elsewhere = CGPoint(x: 1400, y: 900)
        calibration.add(
            contentsOf: [GazeSample(features: user.features(head: seat, lookingAt: elsewhere, yaw: 0, pitch: 0), screenPoint: elsewhere)],
            geometry: testGeometry
        )

        #expect(calibration.samples.count == SelfCalibration.samplesPerCell + 1)
        #expect(calibration.samples.map(\.date).min() == start.addingTimeInterval(5))
    }

    @Test("reports the median of recent errors once there are enough")
    func typicalError() {
        var calibration = SelfCalibration()
        calibration.record(errors: [10, 20, 30, 40])
        #expect(calibration.typicalError == nil)

        calibration.record(errors: [500])

        #expect(calibration.typicalError == 30)
    }

    @Test("keeps only the most recent errors")
    func recentErrorsAreCapped() {
        var calibration = SelfCalibration()

        calibration.record(errors: (0..<(SelfCalibration.recentErrorCount + 10)).map(Double.init))

        #expect(calibration.recentErrors.count == SelfCalibration.recentErrorCount)
        #expect(calibration.recentErrors.first == 10)
    }

    @Test("maps points to a 4 × 3 grid, clamping off-screen points")
    func gridCells() {
        let frame = testGeometry.screenFrame

        #expect(SelfCalibration.cell(of: CGPoint(x: 10, y: 10), in: frame) == 0)
        #expect(SelfCalibration.cell(of: CGPoint(x: 1500, y: 970), in: frame) == 11)
        #expect(SelfCalibration.cell(of: CGPoint(x: -100, y: 5000), in: frame) == 8)
    }

    @Test("fitted(adding:) leaves the calibration unchanged")
    func fittedIsPure() {
        var rng = SeededGenerator(seed: 4)
        let calibration = SelfCalibration()
        let samples = (0..<30).map { _ in SyntheticUser.typical.randomSample(head: seat, using: &rng) }

        let model = calibration.fitted(adding: samples, geometry: testGeometry)

        #expect(model != calibration.model)
        #expect(calibration.samples.isEmpty)
    }

    @Test("reset goes back to the prior and round-trips through JSON")
    func resetAndCodable() throws {
        var rng = SeededGenerator(seed: 6)
        var calibration = SelfCalibration()
        calibration.add(contentsOf: (0..<10).map { _ in SyntheticUser.typical.randomSample(head: seat, using: &rng) }, geometry: testGeometry)
        calibration.record(errors: [1, 2, 3])

        let encoded = try JSONEncoder().encode(calibration)
        let decoded = try JSONDecoder().decode(SelfCalibration.self, from: encoded)
        #expect(decoded == calibration)
        let stored = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(stored["formatVersion"] as? Int == SelfCalibration.currentFormatVersion)

        calibration.reset()
        #expect(calibration.samples.isEmpty)
        #expect(calibration.model == .prior)
        #expect(calibration.recentErrors.isEmpty)
    }
}

extension SelfCalibration.Outcome {
    var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
}
