import Foundation

/// Decides when to focus a window automatically because the user kept looking at it.
///
/// Fires once per continuous look: after firing, the same target has to be lost
/// (or replaced) and re-acquired before it can fire again.
public struct DwellTrigger: Sendable {
    /// How long a target must stay current before it fires, in seconds.
    public var delay: TimeInterval

    private var trackedID: UInt32?
    private var since: TimeInterval = 0
    private var fired = false

    public init(delay: TimeInterval) {
        self.delay = delay
    }

    /// Feeds the current target.
    ///
    /// - Parameters:
    ///   - targetID: The window currently targeted by the gaze, or `nil` for none.
    ///   - now: Current time in seconds.
    /// - Returns: The window to focus now, or `nil` when nothing should happen.
    public mutating func update(targetID: UInt32?, now: TimeInterval) -> UInt32? {
        if targetID != trackedID {
            trackedID = targetID
            since = now
            fired = false
        }
        guard let targetID, !fired, now - since >= delay else { return nil }
        fired = true
        return targetID
    }

    /// Forgets the current look, so the current target counts down from zero again.
    public mutating func reset() {
        trackedID = nil
        fired = false
    }
}
