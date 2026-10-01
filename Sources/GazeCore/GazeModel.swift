import CoreGraphics

/// One calibration observation: what the face looked like while the user looked at a known point.
public struct GazeSample: Sendable, Equatable, Codable {
    public var features: GazeFeatures
    /// Target point in global screen coordinates (top-left origin, points).
    public var screenPoint: CGPoint

    public init(features: GazeFeatures, screenPoint: CGPoint) {
        self.features = features
        self.screenPoint = screenPoint
    }
}

public enum GazeModelError: Error, Equatable {
    case singular
}

/// Linear model from head pose and pupil position to gaze angles.
///
/// It predicts *angles*, not screen points: ``GazeGeometry`` turns them into a point using
/// where the head currently is. What it learns about the user (how far their eyes turn,
/// any bias in Vision's measurements) therefore stays valid after they move.
///
/// Fitting is ridge regression toward ``prior``, a population default, rather than toward zero:
/// with no samples the model *is* the prior, and each sample pulls it toward the user.
public struct GazeModel: Sendable, Equatable, Codable {
    /// Weights for the horizontal angle, one per entry of ``terms(_:head:)``.
    public let weightsHorizontal: [Double]
    /// Weights for the vertical angle, one per entry of ``terms(_:head:)``.
    public let weightsVertical: [Double]

    public init(weightsHorizontal: [Double], weightsVertical: [Double]) {
        self.weightsHorizontal = weightsHorizontal
        self.weightsVertical = weightsVertical
    }

    /// Number of entries produced by ``terms(_:head:)``.
    public static let termCount = 8

    /// Regression terms: intercept, head pose, pupil offsets, and the direction to the camera.
    ///
    /// Vision measures head pose from the face's appearance, so a head facing the camera reads
    /// as straight ahead even when it sits off to the side. The direction to the camera adds
    /// that viewing angle back.
    public static func terms(_ features: GazeFeatures, head: HeadPosition) -> [Double] {
        let camera = head.towardCamera
        return [
            1,
            features.yaw, features.pitch, features.roll,
            features.pupilX, features.pupilY,
            camera.horizontal, camera.vertical,
        ]
    }

    /// How firmly ``prior`` holds each weight: the prior counts as `priorWeight` samples over
    /// which the term spans this much.
    ///
    /// The bias is loose, because every user and setup has some. Head and eye gains match the
    /// spread clicks and calibration actually produce. The direction-to-camera weights are pure
    /// geometry and held firmly: within one sitting they barely vary, so the data can't tell them
    /// apart from the bias, and letting them absorb it would break predictions after the user moves.
    static let priorScales: [Double] = [0.1, 0.15, 0.1, 0.05, 0.15, 0.1, 1, 1]

    /// Population default, used until there is data about the user.
    ///
    /// Assumes Vision's right-handed angles (positive yaw turns the face to the user's left,
    /// positive pitch tilts it down) and an unmirrored image, where a pupil moving right in the
    /// image means looking to the user's left. Pupil gains come from a 12 mm eyeball radius
    /// against a ~30 × 10 mm eye opening.
    public static let prior = GazeModel(
        weightsHorizontal: [0, -1, 0, 0, -1.2, 0, 1, 0],
        weightsVertical: [0, 0, 1, 0, 0, -0.4, 0, 1]
    )

    /// Fits a model to observations, pulled toward ``prior``.
    ///
    /// - Parameters:
    ///   - samples: Observations of the user looking at known points.
    ///   - geometry: Physical setup used to turn each target point into gaze angles.
    ///   - priorWeight: How many typical samples the prior counts for. Higher trusts the default longer.
    /// - Returns: The fitted model; ``prior`` when no sample is usable.
    /// - Throws: ``GazeModelError/singular`` when the system cannot be solved.
    public static func fit(samples: [GazeSample], geometry: GazeGeometry, priorWeight: Double = 15) throws -> GazeModel {
        let size = termCount
        var normal = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        var rhsHorizontal = [Double](repeating: 0, count: size)
        var rhsVertical = [Double](repeating: 0, count: size)

        for sample in samples {
            guard let head = geometry.headPosition(sample.features) else { continue }
            let row = terms(sample.features, head: head)
            let target = geometry.angles(head: head, toward: sample.screenPoint)
            for i in 0..<size {
                rhsHorizontal[i] += row[i] * target.horizontal
                rhsVertical[i] += row[i] * target.vertical
                for j in 0..<size {
                    normal[i][j] += row[i] * row[j]
                }
            }
        }
        for i in 0..<size {
            let penalty = priorWeight * priorScales[i] * priorScales[i]
            normal[i][i] += penalty
            rhsHorizontal[i] += penalty * prior.weightsHorizontal[i]
            rhsVertical[i] += penalty * prior.weightsVertical[i]
        }

        guard
            let weightsHorizontal = solveLinearSystem(normal, rhsHorizontal),
            let weightsVertical = solveLinearSystem(normal, rhsVertical)
        else { throw GazeModelError.singular }

        return GazeModel(weightsHorizontal: weightsHorizontal, weightsVertical: weightsVertical)
    }

    /// Estimates the gaze direction.
    ///
    /// - Parameters:
    ///   - features: Measurements from the current camera frame.
    ///   - head: Eye position for the same frame.
    /// - Returns: The predicted gaze angles.
    public func angles(_ features: GazeFeatures, head: HeadPosition) -> GazeAngles {
        let row = Self.terms(features, head: head)
        return GazeAngles(
            horizontal: zip(row, weightsHorizontal).reduce(0) { $0 + $1.0 * $1.1 },
            vertical: zip(row, weightsVertical).reduce(0) { $0 + $1.0 * $1.1 }
        )
    }

    /// Estimates where the user is looking.
    ///
    /// - Parameters:
    ///   - features: Measurements from the current camera frame.
    ///   - geometry: Physical setup.
    /// - Returns: A point in global screen coordinates (top-left origin), possibly off-screen,
    ///   or `nil` when the head position or the gaze ray cannot be resolved.
    public func predict(_ features: GazeFeatures, geometry: GazeGeometry) -> CGPoint? {
        guard let head = geometry.headPosition(features) else { return nil }
        return geometry.screenPoint(head: head, angles: angles(features, head: head))
    }
}
