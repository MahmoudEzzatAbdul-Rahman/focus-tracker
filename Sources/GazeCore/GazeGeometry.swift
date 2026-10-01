import CoreGraphics
import Foundation

/// Where the user's eyes are, in millimeters, relative to the camera.
///
/// Axes follow the screen as the user sees it: `x` to the right, `y` down,
/// and `distance` from the camera toward the user.
public struct HeadPosition: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var distance: Double

    public init(x: Double, y: Double, distance: Double) {
        self.x = x
        self.y = y
        self.distance = distance
    }

    /// Direction from the eyes to the camera.
    public var towardCamera: GazeAngles {
        GazeAngles(horizontal: atan2(-x, distance), vertical: atan2(-y, distance))
    }
}

/// A gaze direction, in radians, measured from the line perpendicular to the screen.
///
/// Positive `horizontal` looks right, positive `vertical` looks down (as the user sees the screen).
public struct GazeAngles: Sendable, Equatable {
    public var horizontal: Double
    public var vertical: Double

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// The physical setup: camera optics, screen size and where the camera sits.
///
/// The camera is assumed to be centered above the screen, in the screen's plane,
/// looking straight at the user, which is how built-in and most clip-on webcams sit.
public struct GazeGeometry: Sendable, Equatable {
    /// Horizontal field of view of the camera, in radians.
    public var horizontalFieldOfView: Double
    /// Screen bounds in global screen coordinates (top-left origin, points).
    public var screenFrame: CGRect
    /// Physical size of the screen's visible area, in millimeters.
    public var screenSize: CGSize
    /// Distance from the camera down to the top edge of the visible area, in millimeters.
    public var cameraAboveScreen: Double
    /// Assumed distance between the user's pupils, in millimeters (adult average).
    public var interpupillaryDistance: Double

    public init(
        horizontalFieldOfView: Double = 70 * .pi / 180,
        screenFrame: CGRect,
        screenSize: CGSize,
        cameraAboveScreen: Double = 8,
        interpupillaryDistance: Double = 63
    ) {
        self.horizontalFieldOfView = horizontalFieldOfView
        self.screenFrame = screenFrame
        self.screenSize = screenSize
        self.cameraAboveScreen = cameraAboveScreen
        self.interpupillaryDistance = interpupillaryDistance
    }

    /// Focal length in units of the image width.
    private var focalLength: Double {
        0.5 / tan(horizontalFieldOfView / 2)
    }

    private var pointsPerMillimeterX: Double { Double(screenFrame.width / screenSize.width) }
    private var pointsPerMillimeterY: Double { Double(screenFrame.height / screenSize.height) }

    /// Locates the eyes from their size and position in the camera image.
    ///
    /// The camera image is not mirrored, so the user moving to their right moves their face
    /// to the left of the image. Turning the head shrinks the apparent pupil distance, which
    /// is corrected with the head yaw.
    ///
    /// - Parameter features: Measurements from one camera frame.
    /// - Returns: The eye midpoint, or `nil` when the pupil distance is too small to measure.
    public func headPosition(_ features: GazeFeatures) -> HeadPosition? {
        let apparentDistance = features.interpupillaryDistance / max(cos(features.yaw), 0.5)
        guard apparentDistance > 1e-3 else { return nil }

        let distance = focalLength * interpupillaryDistance / apparentDistance
        let imageX = features.eyeMidpointX - 0.5
        let imageY = (0.5 - features.eyeMidpointY) * features.imageAspect
        return HeadPosition(x: -imageX / focalLength * distance, y: imageY / focalLength * distance, distance: distance)
    }

    /// Where a gaze ray from the eyes meets the screen.
    ///
    /// - Parameters:
    ///   - head: Eye position.
    ///   - angles: Gaze direction.
    /// - Returns: The point in global screen coordinates (top-left origin), possibly off-screen,
    ///   or `nil` when the gaze points nearly parallel to the screen.
    public func screenPoint(head: HeadPosition, angles: GazeAngles) -> CGPoint? {
        let limit = 80 * Double.pi / 180
        guard abs(angles.horizontal) < limit, abs(angles.vertical) < limit else { return nil }

        let millimetersX = head.x + head.distance * tan(angles.horizontal)
        let millimetersY = head.y + head.distance * tan(angles.vertical)
        return CGPoint(
            x: Double(screenFrame.midX) + millimetersX * pointsPerMillimeterX,
            y: Double(screenFrame.minY) + (millimetersY - cameraAboveScreen) * pointsPerMillimeterY
        )
    }

    /// The gaze direction that lands on `point`; the inverse of ``screenPoint(head:angles:)``.
    ///
    /// - Parameters:
    ///   - head: Eye position.
    ///   - point: Point in global screen coordinates (top-left origin).
    /// - Returns: The gaze angles from the eyes to the point.
    public func angles(head: HeadPosition, toward point: CGPoint) -> GazeAngles {
        let millimetersX = Double(point.x - screenFrame.midX) / pointsPerMillimeterX
        let millimetersY = Double(point.y - screenFrame.minY) / pointsPerMillimeterY + cameraAboveScreen
        return GazeAngles(
            horizontal: atan2(millimetersX - head.x, head.distance),
            vertical: atan2(millimetersY - head.y, head.distance)
        )
    }
}
