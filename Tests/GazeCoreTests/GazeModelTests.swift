import CoreGraphics
import Foundation
import Testing
@testable import GazeCore

/// Deterministic pseudo-random generator so synthetic data sets are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Builds a plausible random feature sample (head roughly facing the camera).
func randomFeatures(using rng: inout SeededGenerator) -> GazeFeatures {
    GazeFeatures(
        yaw: Double.random(in: -0.4...0.4, using: &rng),
        pitch: Double.random(in: -0.3...0.3, using: &rng),
        roll: Double.random(in: -0.1...0.1, using: &rng),
        pupilX: Double.random(in: -0.5...0.5, using: &rng),
        pupilY: Double.random(in: -0.5...0.5, using: &rng),
        faceX: Double.random(in: 0.4...0.6, using: &rng),
        faceY: Double.random(in: 0.4...0.6, using: &rng),
        faceSize: Double.random(in: 0.25...0.35, using: &rng)
    )
}

/// A known, smooth feature → screen mapping the model should be able to recover.
func syntheticScreenPoint(for f: GazeFeatures) -> CGPoint {
    CGPoint(
        x: 1280 + 2000 * f.yaw + 600 * f.pupilX + 400 * f.yaw * f.yaw - 900 * (f.faceX - 0.5),
        y: 720 - 1800 * f.pitch + 400 * f.pupilY + 300 * f.pitch * f.pitch + 500 * (f.faceY - 0.5)
    )
}

@Suite("GazeModel")
struct GazeModelTests {
    @Test("recovers a known polynomial mapping")
    func recoversKnownMapping() throws {
        var rng = SeededGenerator(seed: 42)
        let training = (0..<300).map { _ -> GazeSample in
            let f = randomFeatures(using: &rng)
            return GazeSample(features: f, screenPoint: syntheticScreenPoint(for: f))
        }

        let model = try GazeModel.fit(samples: training, ridgeLambda: 1e-6)

        for _ in 0..<50 {
            let f = randomFeatures(using: &rng)
            let expected = syntheticScreenPoint(for: f)
            let predicted = model.predict(f)
            #expect(abs(predicted.x - expected.x) < 1)
            #expect(abs(predicted.y - expected.y) < 1)
        }
    }

    @Test("stays stable when a feature never varies")
    func handlesConstantFeature() throws {
        var rng = SeededGenerator(seed: 7)
        let training = (0..<100).map { _ -> GazeSample in
            var f = randomFeatures(using: &rng)
            f.roll = 0
            return GazeSample(features: f, screenPoint: syntheticScreenPoint(for: f))
        }

        let model = try GazeModel.fit(samples: training, ridgeLambda: 1e-6)
        let f = training[0].features
        let predicted = model.predict(f)

        #expect(predicted.x.isFinite)
        #expect(predicted.y.isFinite)
        #expect(abs(predicted.x - training[0].screenPoint.x) < 1)
    }

    @Test("rejects too few samples")
    func rejectsTooFewSamples() {
        var rng = SeededGenerator(seed: 1)
        let samples = (0..<5).map { _ -> GazeSample in
            let f = randomFeatures(using: &rng)
            return GazeSample(features: f, screenPoint: .zero)
        }

        #expect(throws: GazeModelError.notEnoughSamples(required: GazeFeatures.termCount + 1, actual: 5)) {
            try GazeModel.fit(samples: samples)
        }
    }

    @Test("round-trips through JSON")
    func codableRoundTrip() throws {
        var rng = SeededGenerator(seed: 3)
        let training = (0..<60).map { _ -> GazeSample in
            let f = randomFeatures(using: &rng)
            return GazeSample(features: f, screenPoint: syntheticScreenPoint(for: f))
        }
        let model = try GazeModel.fit(samples: training)

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
}
