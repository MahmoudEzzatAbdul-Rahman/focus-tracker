import CoreGraphics

/// Turns a noisy stream of gaze points into steady fixations with clean jumps between them.
///
/// Eyes hold still on a point (a fixation), then jump to the next one (a saccade). Points near
/// the current fixation refine it through a heavily smoothing ``OneEuroFilter``, so the output
/// barely moves. The fixation only moves somewhere else once several consecutive points land
/// away from it *and* agree with each other, so isolated outliers and scattered noise are ignored.
public struct GazeStabilizer: Sendable {
    /// Points within this distance (in points) of the fixation belong to it.
    public let radius: Double
    /// Consecutive, mutually consistent points needed away from the fixation to jump to them.
    public let saccadeSamples: Int

    public private(set) var fixation: CGPoint?

    private let minCutoff: Double
    private var smoother: PointFilter
    private var candidates: [CGPoint] = []
    private var lastTime: Double?

    /// - Parameters:
    ///   - radius: Fixation radius in points; a few percent of the screen diagonal works well.
    ///   - saccadeSamples: Points needed to confirm a jump (3 is about 100 ms at 30 fps).
    ///   - minCutoff: Smoothing cutoff (Hz) inside a fixation. Lower means steadier.
    public init(radius: Double, saccadeSamples: Int = 3, minCutoff: Double = 0.3) {
        self.radius = radius
        self.saccadeSamples = max(1, saccadeSamples)
        self.minCutoff = minCutoff
        smoother = PointFilter(minCutoff: minCutoff, beta: 0)
    }

    /// Feeds the next gaze point.
    ///
    /// - Parameters:
    ///   - point: Unfiltered gaze point.
    ///   - time: Sample timestamp in seconds; samples that don't advance time are ignored.
    /// - Returns: The current fixation.
    public mutating func update(_ point: CGPoint, at time: Double) -> CGPoint {
        if let lastTime, time <= lastTime, let fixation { return fixation }
        lastTime = time

        guard let current = fixation else {
            return startFixation(at: point, time: time)
        }
        if point.distance(to: current) <= radius {
            candidates.removeAll()
            let refined = smoother.filter(point, at: time)
            fixation = refined
            return refined
        }

        candidates.append(point)
        if candidates.count > saccadeSamples { candidates.removeFirst() }
        if candidates.count == saccadeSamples {
            let center = CGPoint(
                x: candidates.reduce(0) { $0 + $1.x } / Double(candidates.count),
                y: candidates.reduce(0) { $0 + $1.y } / Double(candidates.count)
            )
            if candidates.allSatisfy({ $0.distance(to: center) <= radius }) {
                return startFixation(at: center, time: time)
            }
        }
        return current
    }

    /// Forgets the fixation, so the next point starts a new one.
    public mutating func reset() {
        fixation = nil
        candidates.removeAll()
        lastTime = nil
        smoother.reset()
    }

    private mutating func startFixation(at point: CGPoint, time: Double) -> CGPoint {
        candidates.removeAll()
        smoother = PointFilter(minCutoff: minCutoff, beta: 0)
        let start = smoother.filter(point, at: time)
        fixation = start
        return start
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        Double(hypot(x - other.x, y - other.y))
    }
}
