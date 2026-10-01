import CoreGraphics
import Foundation

/// Learns the user's ``GazeModel`` from points they are known to look at, mostly mouse clicks.
///
/// Samples are kept balanced across the screen: it is split into a grid, each cell keeps at
/// most ``samplesPerCell`` samples and evicts its oldest one first, so a burst of clicks in
/// one place (a menu bar, a toolbar) cannot outweigh the rest of the screen.
///
/// A click is only a sample if the user was looking at it. Once the model has some data,
/// clicks far from the predicted gaze are rejected; the limit follows the recent typical
/// error, so it opens up again if the model goes badly wrong.
public struct SelfCalibration: Sendable, Codable, Equatable {
    public struct StoredSample: Sendable, Codable, Equatable {
        public var sample: GazeSample
        public var date: Date
    }

    public enum Outcome: Sendable, Equatable {
        /// The sample was added. `error` is how far the model was off before learning from it.
        case accepted(error: Double)
        /// The click was too far from the predicted gaze to have been looked at.
        case rejected(error: Double)
        /// The head position couldn't be measured.
        case unusable
    }

    public static let gridColumns = 4
    public static let gridRows = 3
    public static let samplesPerCell = 40
    /// Below this many samples every usable click is accepted, so a bad default can still be corrected.
    public static let bootstrapSamples = 20
    /// Never reject a click closer than this to the predicted gaze, in points.
    public static let minimumRejectionDistance = 250.0
    public static let recentErrorCount = 30

    public private(set) var samples: [StoredSample] = []
    public private(set) var model: GazeModel = .prior
    /// Distances in points between predicted gaze and recent clicks, before learning from them.
    public private(set) var recentErrors: [Double] = []

    public init() {}

    /// Typical recent error in points, or `nil` until a few clicks have been measured.
    public var typicalError: Double? {
        recentErrors.count >= 5 ? Self.median(recentErrors) : nil
    }

    /// Learns from a click.
    ///
    /// - Parameters:
    ///   - sample: What the face looked like when the click happened, and where it was.
    ///   - geometry: Physical setup.
    ///   - date: When it happened.
    /// - Returns: Whether the click was used, with the model's error on it.
    @discardableResult
    public mutating func add(click sample: GazeSample, geometry: GazeGeometry, at date: Date = .now) -> Outcome {
        guard let predicted = model.predict(sample.features, geometry: geometry) else { return .unusable }
        let error = predicted.distance(to: sample.screenPoint)
        record(errors: [error])

        if samples.count >= Self.bootstrapSamples {
            let limit = max(3 * Self.median(recentErrors), Self.minimumRejectionDistance)
            guard error <= limit else { return .rejected(error: error) }
        }
        insert(sample, geometry: geometry, at: date)
        refit(geometry: geometry)
        return .accepted(error: error)
    }

    /// Adds samples without checking them, for example from an explicit calibration.
    public mutating func add(contentsOf newSamples: [GazeSample], geometry: GazeGeometry, at date: Date = .now) {
        for sample in newSamples where geometry.headPosition(sample.features) != nil {
            insert(sample, geometry: geometry, at: date)
        }
        refit(geometry: geometry)
    }

    /// Adds measured errors to the recent ones, for example from calibration validation dots.
    public mutating func record(errors: [Double]) {
        recentErrors += errors
        if recentErrors.count > Self.recentErrorCount {
            recentErrors.removeFirst(recentErrors.count - Self.recentErrorCount)
        }
    }

    /// The model that adding `newSamples` would produce, leaving this one unchanged.
    public func fitted(adding newSamples: [GazeSample], geometry: GazeGeometry) -> GazeModel {
        var copy = self
        copy.add(contentsOf: newSamples, geometry: geometry)
        return copy.model
    }

    /// Forgets everything learned and goes back to ``GazeModel/prior``.
    public mutating func reset() {
        self = SelfCalibration()
    }

    private mutating func insert(_ sample: GazeSample, geometry: GazeGeometry, at date: Date) {
        let cell = Self.cell(of: sample.screenPoint, in: geometry.screenFrame)
        let inCell = samples.indices.filter { Self.cell(of: samples[$0].sample.screenPoint, in: geometry.screenFrame) == cell }
        if inCell.count >= Self.samplesPerCell, let oldest = inCell.min(by: { samples[$0].date < samples[$1].date }) {
            samples.remove(at: oldest)
        }
        samples.append(StoredSample(sample: sample, date: date))
    }

    private mutating func refit(geometry: GazeGeometry) {
        if let fitted = try? GazeModel.fit(samples: samples.map(\.sample), geometry: geometry) {
            model = fitted
        }
    }

    static func cell(of point: CGPoint, in frame: CGRect) -> Int {
        guard frame.width > 0, frame.height > 0 else { return 0 }
        let column = min(max(Int(Double((point.x - frame.minX) / frame.width) * Double(gridColumns)), 0), gridColumns - 1)
        let row = min(max(Int(Double((point.y - frame.minY) / frame.height) * Double(gridRows)), 0), gridRows - 1)
        return row * gridColumns + column
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
