import AppKit
import GazeCore

/// Lists the regular app windows currently on screen.
///
/// Only bounds and owner info are read, which does not require Screen Recording permission.
struct WindowLocator {
    /// Windows smaller than this (in points, either side) are ignored: tooltips, palettes, etc.
    private let minimumSide: CGFloat = 80

    /// - Returns: On-screen windows at the normal level, ordered front to back, excluding our own.
    func windows() -> [WindowInfo] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { entry -> WindowInfo? in
            guard
                (entry[kCGWindowLayer as String] as? Int) == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                let number = entry[kCGWindowNumber as String] as? UInt32,
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: boundsDictionary),
                frame.width >= minimumSide, frame.height >= minimumSide,
                (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { return nil }

            return WindowInfo(
                id: number,
                pid: pid,
                frame: frame,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "PID \(pid)"
            )
        }
    }
}
