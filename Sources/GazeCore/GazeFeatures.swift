import CoreGraphics

/// Per-frame face measurements used to estimate where the user is looking.
///
/// Angles are in radians as reported by Vision. Pupil offsets are normalized
/// inside the eye contour (`-1...1` spans the eye, clamped to `-2...2`).
/// Face position and size are normalized image coordinates of the face box.
public struct GazeFeatures: Sendable, Equatable, Codable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public var pupilX: Double
    public var pupilY: Double
    public var faceX: Double
    public var faceY: Double
    public var faceSize: Double

    public init(
        yaw: Double,
        pitch: Double,
        roll: Double,
        pupilX: Double,
        pupilY: Double,
        faceX: Double,
        faceY: Double,
        faceSize: Double
    ) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.pupilX = pupilX
        self.pupilY = pupilY
        self.faceX = faceX
        self.faceY = faceY
        self.faceSize = faceSize
    }

    /// Number of regression terms produced by ``terms``.
    public static let termCount = 16

    /// Expands the raw measurements into the polynomial terms fed to ``GazeModel``.
    ///
    /// Linear terms capture head pose, eye direction and head translation; the
    /// quadratic and cross terms absorb the non-linearity of looking at a flat screen.
    public var terms: [Double] {
        [
            yaw, pitch, roll,
            pupilX, pupilY,
            faceX, faceY, faceSize,
            yaw * yaw, pitch * pitch, yaw * pitch,
            pupilX * pupilX, pupilY * pupilY, pupilX * pupilY,
            yaw * pupilX, pitch * pupilY,
        ]
    }

    /// Locates a pupil relative to its eye contour.
    ///
    /// - Parameters:
    ///   - pupil: Pupil landmark, in the same coordinate space as `eyeContour`.
    ///   - eyeContour: Points outlining the eye.
    /// - Returns: The offset from the contour's bounding-box center, where `±1` is the
    ///   box edge. Each axis is clamped to `-2...2`, and is `0` when the box is degenerate.
    public static func pupilOffset(pupil: CGPoint, eyeContour: [CGPoint]) -> CGPoint {
        guard
            let minX = eyeContour.map(\.x).min(), let maxX = eyeContour.map(\.x).max(),
            let minY = eyeContour.map(\.y).min(), let maxY = eyeContour.map(\.y).max()
        else { return .zero }

        func normalized(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            let halfSpan = (high - low) / 2
            guard halfSpan > .ulpOfOne else { return 0 }
            return min(max((value - (low + halfSpan)) / halfSpan, -2), 2)
        }

        return CGPoint(x: normalized(pupil.x, minX, maxX), y: normalized(pupil.y, minY, maxY))
    }
}
