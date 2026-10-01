/// Removes single-frame spikes from ``GazeFeatures`` with a per-field median over the last three frames.
///
/// Adds one frame of lag; a genuine change passes through on the second frame.
public struct FeatureMedianFilter: Sendable {
    private var window: [GazeFeatures] = []

    public init() {}

    /// Smooths the next frame.
    ///
    /// - Parameter features: Raw measurements of the frame.
    /// - Returns: The per-field median of the last three frames, or `features` itself until three have been seen.
    public mutating func filter(_ features: GazeFeatures) -> GazeFeatures {
        window.append(features)
        if window.count > 3 { window.removeFirst() }
        guard window.count == 3 else { return features }

        func median(_ field: KeyPath<GazeFeatures, Double>) -> Double {
            Self.median(window[0][keyPath: field], window[1][keyPath: field], window[2][keyPath: field])
        }
        return GazeFeatures(
            yaw: median(\.yaw),
            pitch: median(\.pitch),
            roll: median(\.roll),
            pupilX: median(\.pupilX),
            pupilY: median(\.pupilY),
            eyeMidpointX: median(\.eyeMidpointX),
            eyeMidpointY: median(\.eyeMidpointY),
            interpupillaryDistance: median(\.interpupillaryDistance),
            imageAspect: median(\.imageAspect),
            eyeOpenness: median(\.eyeOpenness)
        )
    }

    public mutating func reset() {
        window.removeAll()
    }

    static func median(_ a: Double, _ b: Double, _ c: Double) -> Double {
        max(min(a, b), min(max(a, b), c))
    }
}
