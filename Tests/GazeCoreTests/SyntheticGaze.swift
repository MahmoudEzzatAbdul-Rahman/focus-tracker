import CoreGraphics
import Foundation
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

/// A 14-inch laptop screen with the camera above it.
let testGeometry = GazeGeometry(
    screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    screenSize: CGSize(width: 302, height: 196)
)

/// A simulated user whose eyes follow a known ``GazeModel``, for generating consistent features.
struct SyntheticUser {
    var model: GazeModel
    var geometry = testGeometry
    let imageAspect = 0.5625

    /// A user who differs clearly from ``GazeModel/prior``: stronger eye gains and a few degrees of bias.
    static let typical = SyntheticUser(model: GazeModel(
        weightsHorizontal: [0.04, -0.9, 0, 0, -1.6, 0, 1, 0],
        weightsVertical: [-0.05, 0, 1.1, 0, 0, -0.7, 0, 1]
    ))

    /// What the camera would measure for this user, at `head`, looking at `point`.
    ///
    /// The head pose is chosen freely; the pupils then take whatever offset makes the
    /// user's model land exactly on `point`.
    func features(head: HeadPosition, lookingAt point: CGPoint, yaw: Double, pitch: Double) -> GazeFeatures {
        let focal = 0.5 / tan(geometry.horizontalFieldOfView / 2)
        var features = GazeFeatures(
            yaw: yaw,
            pitch: pitch,
            roll: 0,
            pupilX: 0,
            pupilY: 0,
            eyeMidpointX: 0.5 - head.x * focal / head.distance,
            eyeMidpointY: 0.5 - head.y * focal / head.distance / imageAspect,
            interpupillaryDistance: focal * geometry.interpupillaryDistance / head.distance * max(cos(yaw), 0.5),
            imageAspect: imageAspect,
            eyeOpenness: 0.3
        )
        let target = geometry.angles(head: head, toward: point)
        let withoutPupils = model.angles(features, head: head)
        features.pupilX = (target.horizontal - withoutPupils.horizontal) / model.weightsHorizontal[4]
        features.pupilY = (target.vertical - withoutPupils.vertical) / model.weightsVertical[5]
        return features
    }

    /// A sample looking at a random on-screen point, with a random but plausible head pose.
    func randomSample(head: HeadPosition, using rng: inout SeededGenerator) -> GazeSample {
        let point = CGPoint(
            x: Double.random(in: 0...geometry.screenFrame.width, using: &rng),
            y: Double.random(in: 0...geometry.screenFrame.height, using: &rng)
        )
        let features = features(
            head: head,
            lookingAt: point,
            yaw: Double.random(in: -0.25...0.25, using: &rng),
            pitch: Double.random(in: -0.1...0.3, using: &rng)
        )
        return GazeSample(features: features, screenPoint: point)
    }
}

/// A head position near `center`, jittered the way someone shifts in their chair.
func jittered(_ center: HeadPosition, by amount: Double, using rng: inout SeededGenerator) -> HeadPosition {
    HeadPosition(
        x: center.x + Double.random(in: -amount...amount, using: &rng),
        y: center.y + Double.random(in: -amount...amount, using: &rng),
        distance: center.distance + Double.random(in: -amount...amount, using: &rng)
    )
}

/// Builds a plain feature value with every field set, for filter tests.
func uniformFeatures(_ value: Double) -> GazeFeatures {
    GazeFeatures(
        yaw: value, pitch: value, roll: value,
        pupilX: value, pupilY: value,
        eyeMidpointX: value, eyeMidpointY: value,
        interpupillaryDistance: value, imageAspect: value, eyeOpenness: value
    )
}
