import CoreGraphics

/// Per-frame face measurements used to estimate where the user is looking.
///
/// Angles are in radians as reported by Vision. Pupil offsets are normalized
/// inside the eye contour (`-1...1` spans the eye, clamped to `-2...2`).
/// Image positions use Vision's normalized image coordinates (bottom-left origin,
/// `0...1` across the width and the height); lengths are fractions of the image width.
public struct GazeFeatures: Sendable, Equatable, Codable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public var pupilX: Double
    public var pupilY: Double
    /// Midpoint between the two pupils, in normalized image coordinates.
    public var eyeMidpointX: Double
    public var eyeMidpointY: Double
    /// Distance between the pupils, as a fraction of the image width.
    public var interpupillaryDistance: Double
    /// Image height divided by image width.
    public var imageAspect: Double
    /// Mean height-to-width ratio of the two eye contours; drops sharply during a blink.
    public var eyeOpenness: Double

    public init(
        yaw: Double,
        pitch: Double,
        roll: Double,
        pupilX: Double,
        pupilY: Double,
        eyeMidpointX: Double,
        eyeMidpointY: Double,
        interpupillaryDistance: Double,
        imageAspect: Double,
        eyeOpenness: Double
    ) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.pupilX = pupilX
        self.pupilY = pupilY
        self.eyeMidpointX = eyeMidpointX
        self.eyeMidpointY = eyeMidpointY
        self.interpupillaryDistance = interpupillaryDistance
        self.imageAspect = imageAspect
        self.eyeOpenness = eyeOpenness
    }

    /// Locates a pupil relative to its eye contour.
    ///
    /// - Parameters:
    ///   - pupil: Pupil landmark, in the same coordinate space as `eyeContour`.
    ///   - eyeContour: Points outlining the eye.
    /// - Returns: The offset from the contour's bounding-box center, where `±1` is the
    ///   box edge. Each axis is clamped to `-2...2`, and is `0` when the box is degenerate.
    public static func pupilOffset(pupil: CGPoint, eyeContour: [CGPoint]) -> CGPoint {
        guard let box = boundingBox(of: eyeContour) else { return .zero }

        func normalized(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            let halfSpan = (high - low) / 2
            guard halfSpan > .ulpOfOne else { return 0 }
            return min(max((value - (low + halfSpan)) / halfSpan, -2), 2)
        }

        return CGPoint(x: normalized(pupil.x, box.minX, box.maxX), y: normalized(pupil.y, box.minY, box.maxY))
    }

    /// How open an eye is.
    ///
    /// - Parameter eyeContour: Points outlining the eye.
    /// - Returns: Height divided by width of the contour's bounding box, or `0` when it is degenerate.
    public static func eyeOpenness(eyeContour: [CGPoint]) -> Double {
        guard let box = boundingBox(of: eyeContour), box.width > .ulpOfOne else { return 0 }
        return Double(box.height / box.width)
    }

    /// Field-by-field average of several measurements.
    ///
    /// - Parameter features: Measurements to average.
    /// - Returns: The average, or `nil` when `features` is empty.
    public static func mean(of features: [GazeFeatures]) -> GazeFeatures? {
        guard !features.isEmpty else { return nil }
        let count = Double(features.count)
        func average(_ field: KeyPath<GazeFeatures, Double>) -> Double {
            features.reduce(0) { $0 + $1[keyPath: field] } / count
        }
        return GazeFeatures(
            yaw: average(\.yaw),
            pitch: average(\.pitch),
            roll: average(\.roll),
            pupilX: average(\.pupilX),
            pupilY: average(\.pupilY),
            eyeMidpointX: average(\.eyeMidpointX),
            eyeMidpointY: average(\.eyeMidpointY),
            interpupillaryDistance: average(\.interpupillaryDistance),
            imageAspect: average(\.imageAspect),
            eyeOpenness: average(\.eyeOpenness)
        )
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect? {
        guard
            let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
