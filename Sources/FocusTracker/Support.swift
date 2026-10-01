import CoreGraphics
import Foundation
import GazeCore
import OSLog

extension Logger {
    private static let subsystem = "io.local.focustracker"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let focus = Logger(subsystem: subsystem, category: "focus")
    static let calibration = Logger(subsystem: subsystem, category: "calibration")
}

/// How the targeted window gets focus.
enum FocusMode: String, CaseIterable {
    /// Tap left ⌃ to focus the outlined window.
    case hotkey
    /// The outlined window is focused automatically after ``Settings/dwellDelay``.
    /// Tapping left ⌃ still focuses it right away.
    case dwell
}

/// User preferences persisted in `UserDefaults`.
@MainActor
final class Settings {
    /// Choices offered in the menu for ``dwellDelay``, in seconds.
    static let dwellDelayChoices: [TimeInterval] = [0.5, 0.8, 1.2, 2.0]

    private enum Key {
        static let enabled = "enabled"
        static let focusMode = "focusMode"
        static let dwellDelay = "dwellDelay"
        static let showsGazeDot = "showsGazeDot"
        static let usesMouseAsGaze = "usesMouseAsGaze"
        static let learnsFromClicks = "learnsFromClicks"
        static let cameraID = "cameraID"
    }

    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var focusMode: FocusMode {
        get { defaults.string(forKey: Key.focusMode).flatMap(FocusMode.init(rawValue:)) ?? .hotkey }
        set { defaults.set(newValue.rawValue, forKey: Key.focusMode) }
    }

    /// In dwell mode, how long a window stays outlined before it is focused, in seconds.
    var dwellDelay: TimeInterval {
        get { defaults.object(forKey: Key.dwellDelay) as? Double ?? 0.8 }
        set { defaults.set(newValue, forKey: Key.dwellDelay) }
    }

    var showsGazeDot: Bool {
        get { defaults.bool(forKey: Key.showsGazeDot) }
        set { defaults.set(newValue, forKey: Key.showsGazeDot) }
    }

    /// Debug mode: the mouse cursor stands in for the gaze point, bypassing the camera.
    var usesMouseAsGaze: Bool {
        get { defaults.bool(forKey: Key.usesMouseAsGaze) }
        set { defaults.set(newValue, forKey: Key.usesMouseAsGaze) }
    }

    /// Whether mouse clicks are used as calibration samples (the user looks where they click).
    var learnsFromClicks: Bool {
        get { defaults.object(forKey: Key.learnsFromClicks) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.learnsFromClicks) }
    }

    var cameraID: String? {
        get { defaults.string(forKey: Key.cameraID) }
        set { defaults.set(newValue, forKey: Key.cameraID) }
    }
}

/// Loads and saves what has been learned about the user's gaze, under
/// `~/Library/Application Support/FocusTracker`.
enum GazeProfileStore {
    private static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "FocusTracker", directoryHint: .isDirectory)
            .appending(path: "gaze-profile.json")
    }

    /// Just enough of a stored profile to tell which format it was saved in.
    private struct Header: Decodable {
        var formatVersion: Int?
    }

    static func load() -> SelfCalibration? {
        do {
            let data = try Data(contentsOf: fileURL)
            let version = try JSONDecoder().decode(Header.self, from: data).formatVersion ?? 1
            guard version == SelfCalibration.currentFormatVersion else {
                Logger.calibration.info("Discarding gaze profile saved in format \(version); starting from the defaults")
                return nil
            }
            return try JSONDecoder().decode(SelfCalibration.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Logger.calibration.error("Could not load gaze profile: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save(_ calibration: SelfCalibration) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(calibration).write(to: fileURL, options: .atomic)
        } catch {
            Logger.calibration.error("Could not save gaze profile: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum ScreenGeometry {
    /// Bounds of the main display in global Quartz coordinates (top-left origin, points).
    static var mainDisplayBounds: CGRect {
        CGDisplayBounds(CGMainDisplayID())
    }

    /// The physical setup of the main display, assuming the camera sits centered above it.
    static var gazeGeometry: GazeGeometry {
        let frame = mainDisplayBounds
        var size = CGDisplayScreenSize(CGMainDisplayID())
        if size.width <= 0 || size.height <= 0 {
            // Some displays don't report their size; assume about 100 points per inch.
            let millimetersPerPoint = 25.4 / 100
            size = CGSize(width: frame.width * millimetersPerPoint, height: frame.height * millimetersPerPoint)
        }
        return GazeGeometry(screenFrame: frame, screenSize: size)
    }

    /// Converts a global Quartz rect to Cocoa coordinates (bottom-left origin of the main display).
    static func cocoaRect(fromQuartz rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainDisplayBounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

extension CGPoint {
    /// This point moved inside `rect` if it falls outside it.
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(x, rect.minX), rect.maxX - 1), y: min(max(y, rect.minY), rect.maxY - 1))
    }

    func distance(to other: CGPoint) -> Double {
        hypot(x - other.x, y - other.y)
    }
}
