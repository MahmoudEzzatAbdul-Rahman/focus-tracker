import CoreGraphics
import Foundation

/// An on-screen window that can receive focus.
public struct WindowInfo: Sendable, Equatable, Identifiable {
    public let id: UInt32
    public let pid: Int32
    /// Bounds in global screen coordinates (top-left origin, points).
    public let frame: CGRect
    public let ownerName: String

    public init(id: UInt32, pid: Int32, frame: CGRect, ownerName: String) {
        self.id = id
        self.pid = pid
        self.frame = frame
        self.ownerName = ownerName
    }
}

/// Decides which window the user is looking at, ignoring brief glances.
///
/// The target only changes once the gaze has stayed on a different window (or on
/// empty space) for `dwell` seconds. Losing the gaze entirely clears it at once.
public struct TargetSelector: Sendable {
    public let dwell: TimeInterval
    public private(set) var currentID: UInt32?

    /// Window (or `nil` for empty space) the gaze moved to, and when it got there.
    private var pending: (id: UInt32?, since: TimeInterval)?

    public init(dwell: TimeInterval = 0.25) {
        self.dwell = dwell
    }

    /// Feeds the latest gaze point.
    ///
    /// - Parameters:
    ///   - point: Smoothed gaze point in global screen coordinates, or `nil` when no face is tracked.
    ///   - windows: Candidate windows ordered front to back.
    ///   - now: Current time in seconds.
    /// - Returns: The current target with its latest frame, or `nil` when there is none.
    public mutating func update(point: CGPoint?, windows: [WindowInfo], now: TimeInterval) -> WindowInfo? {
        guard let point else {
            currentID = nil
            pending = nil
            return nil
        }

        let hitID = windows.first { $0.frame.contains(point) }?.id
        if hitID == currentID {
            pending = nil
        } else if let pending, pending.id == hitID {
            if now - pending.since >= dwell {
                currentID = hitID
                self.pending = nil
            }
        } else {
            pending = (hitID, now)
            if dwell <= 0 {
                currentID = hitID
                pending = nil
            }
        }

        guard let target = windows.first(where: { $0.id == currentID }) else {
            currentID = nil
            return nil
        }
        return target
    }
}
