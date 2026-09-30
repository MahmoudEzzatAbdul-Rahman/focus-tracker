import CoreGraphics
import Foundation

/// One Euro filter (Casiez et al., 2012): smooths heavily while the signal is steady
/// and lets fast, deliberate movements through with little lag.
public struct OneEuroFilter: Sendable {
    /// Cutoff frequency (Hz) used when the signal is still. Lower means smoother.
    public var minCutoff: Double
    /// How quickly the cutoff rises with speed. Higher means less lag on fast moves.
    public var beta: Double
    /// Cutoff frequency (Hz) for the derivative estimate.
    public var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative = 0.0
    private var lastTime = 0.0

    public init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// Smooths the next sample.
    ///
    /// - Parameters:
    ///   - value: Raw sample.
    ///   - time: Sample timestamp in seconds; samples that don't advance time are ignored.
    /// - Returns: The filtered value.
    public mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let previous = lastValue else {
            lastValue = value
            lastTime = time
            return value
        }
        let elapsed = time - lastTime
        guard elapsed > 0 else { return previous }

        let derivative = (value - previous) / elapsed
        lastDerivative += Self.alpha(cutoff: derivativeCutoff, elapsed: elapsed) * (derivative - lastDerivative)
        let cutoff = minCutoff + beta * abs(lastDerivative)
        let filtered = previous + Self.alpha(cutoff: cutoff, elapsed: elapsed) * (value - previous)

        lastValue = filtered
        lastTime = time
        return filtered
    }

    /// Forgets all history, so the next sample passes through unchanged.
    public mutating func reset() {
        lastValue = nil
        lastDerivative = 0
    }

    private static func alpha(cutoff: Double, elapsed: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / elapsed)
    }
}

/// Applies a ``OneEuroFilter`` to each axis of a point.
public struct PointFilter: Sendable {
    private var x: OneEuroFilter
    private var y: OneEuroFilter

    public init(minCutoff: Double = 0.5, beta: Double = 0.005) {
        x = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        y = OneEuroFilter(minCutoff: minCutoff, beta: beta)
    }

    public mutating func filter(_ point: CGPoint, at time: Double) -> CGPoint {
        CGPoint(x: x.filter(point.x, at: time), y: y.filter(point.y, at: time))
    }

    public mutating func reset() {
        x.reset()
        y.reset()
    }
}
