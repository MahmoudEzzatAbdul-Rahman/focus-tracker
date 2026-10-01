import CoreGraphics
import Foundation
import Testing
@testable import GazeCore

@Suite("GazeModel")
struct GazeModelTests {
    let seat = HeadPosition(x: 0, y: 260, distance: 550)

    @Test("is the prior when there are no samples")
    func noSamplesGivesPrior() throws {
        let model = try GazeModel.fit(samples: [], geometry: testGeometry)

        for (fitted, prior) in zip(model.weightsHorizontal + model.weightsVertical,
                                   GazeModel.prior.weightsHorizontal + GazeModel.prior.weightsVertical) {
            #expect(abs(fitted - prior) < 1e-12)
        }
    }

    @Test("learns a user who differs from the prior")
    func learnsUser() throws {
        var rng = SeededGenerator(seed: 42)
        let user = SyntheticUser.typical
        let training = (0..<300).map { _ in user.randomSample(head: jittered(seat, by: 40, using: &rng), using: &rng) }

        let model = try GazeModel.fit(samples: training, geometry: testGeometry)

        for _ in 0..<50 {
            let sample = user.randomSample(head: jittered(seat, by: 40, using: &rng), using: &rng)
            let predicted = try #require(model.predict(sample.features, geometry: testGeometry))
            #expect(predicted.distance(to: sample.screenPoint) < 30)
        }
    }

    @Test("stays accurate after the user moves to a different seat")
    func survivesMoving() throws {
        var rng = SeededGenerator(seed: 9)
        let user = SyntheticUser.typical
        let training = (0..<200).map { _ in user.randomSample(head: jittered(seat, by: 10, using: &rng), using: &rng) }
        let model = try GazeModel.fit(samples: training, geometry: testGeometry)

        let newSeat = HeadPosition(x: 50, y: 230, distance: 700)
        for _ in 0..<50 {
            let sample = user.randomSample(head: newSeat, using: &rng)
            let predicted = try #require(model.predict(sample.features, geometry: testGeometry))
            #expect(predicted.distance(to: sample.screenPoint) < 40)
        }
    }

    @Test("a few samples move the model only part of the way from the prior")
    func priorResistsFewSamples() throws {
        var rng = SeededGenerator(seed: 5)
        let user = SyntheticUser.typical
        let training = (0..<3).map { _ in user.randomSample(head: seat, using: &rng) }

        let model = try GazeModel.fit(samples: training, geometry: testGeometry)

        let pupilGain = model.weightsHorizontal[4]
        #expect(pupilGain < GazeModel.prior.weightsHorizontal[4])
        #expect(pupilGain > user.model.weightsHorizontal[4])
    }

    @Test("can't predict without a measurable head position")
    func noHeadPosition() {
        var features = SyntheticUser.typical.features(head: seat, lookingAt: CGPoint(x: 700, y: 500), yaw: 0, pitch: 0)
        features.interpupillaryDistance = 0

        #expect(GazeModel.prior.predict(features, geometry: testGeometry) == nil)
    }

    @Test("round-trips through JSON")
    func codableRoundTrip() throws {
        let model = GazeModel(weightsHorizontal: Array(repeating: 0.25, count: 8), weightsVertical: Array(repeating: -0.5, count: 8))

        let decoded = try JSONDecoder().decode(GazeModel.self, from: JSONEncoder().encode(model))

        #expect(decoded == model)
    }
}

@Suite("GazeFeatures")
struct GazeFeaturesTests {
    @Test("pupil at eye center has zero offset")
    func pupilAtCenter() {
        let eye = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.4, y: 0.55), CGPoint(x: 0.4, y: 0.45)]

        let offset = GazeFeatures.pupilOffset(pupil: CGPoint(x: 0.3, y: 0.5), eyeContour: eye)

        #expect(abs(offset.x) < 1e-9)
        #expect(abs(offset.y) < 1e-9)
    }

    @Test("pupil at the eye's right edge has +1 horizontal offset")
    func pupilAtEdge() {
        let eye = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.4, y: 0.55), CGPoint(x: 0.4, y: 0.45)]

        let offset = GazeFeatures.pupilOffset(pupil: CGPoint(x: 0.4, y: 0.55), eyeContour: eye)

        #expect(abs(offset.x - 1) < 1e-9)
        #expect(abs(offset.y - 1) < 1e-9)
    }

    @Test("offset is clamped for outliers and degenerate contours")
    func clampsOutliers() {
        let eye = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.4, y: 0.5)]

        let offset = GazeFeatures.pupilOffset(pupil: CGPoint(x: 5, y: 0.9), eyeContour: eye)

        #expect(offset.x == 2)
        #expect(offset.y == 0)
    }

    @Test("eye openness is the contour's height over its width")
    func openness() {
        let eye = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.4, y: 0.56), CGPoint(x: 0.4, y: 0.5)]

        #expect(abs(GazeFeatures.eyeOpenness(eyeContour: eye) - 0.3) < 1e-9)
        #expect(GazeFeatures.eyeOpenness(eyeContour: []) == 0)
    }

    @Test("mean averages every field")
    func mean() throws {
        let average = try #require(GazeFeatures.mean(of: [uniformFeatures(1), uniformFeatures(2), uniformFeatures(6)]))

        #expect(average == uniformFeatures(3))
        #expect(GazeFeatures.mean(of: []) == nil)
    }
}
