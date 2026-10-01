/// Flags frames taken during a blink, when the pupil landmarks are unreliable.
///
/// Compares each frame's ``GazeFeatures/eyeOpenness`` against a slowly adapting baseline
/// of the user's open eyes, so it works for any eye shape. A "blink" lasting longer than
/// ``maximumBlinkFrames`` is taken as a lasting change (lighting, posture) and becomes the new baseline.
public struct BlinkDetector: Sendable {
    /// A frame counts as a blink when its openness is below this fraction of the baseline.
    public var threshold: Double
    /// How fast the baseline follows open-eye frames, per frame (`0...1`).
    public var adaptationRate: Double
    /// Consecutive blink frames after which the baseline is reset (15 is half a second at 30 fps).
    public var maximumBlinkFrames: Int

    public private(set) var baseline: Double?
    private var blinkFrames = 0

    public init(threshold: Double = 0.6, adaptationRate: Double = 0.05, maximumBlinkFrames: Int = 15) {
        self.threshold = threshold
        self.adaptationRate = adaptationRate
        self.maximumBlinkFrames = maximumBlinkFrames
    }

    /// Feeds the next frame's eye openness.
    ///
    /// - Parameter openness: ``GazeFeatures/eyeOpenness`` of the frame.
    /// - Returns: `true` when the frame was taken during a blink and should be dropped.
    public mutating func isBlinking(openness: Double) -> Bool {
        guard let baseline else {
            self.baseline = openness
            return false
        }
        if openness < threshold * baseline {
            blinkFrames += 1
            guard blinkFrames > maximumBlinkFrames else { return true }
            self.baseline = openness
        } else {
            self.baseline = baseline + adaptationRate * (openness - baseline)
        }
        blinkFrames = 0
        return false
    }

    /// Forgets the baseline, for example after the face was lost.
    public mutating func reset() {
        baseline = nil
        blinkFrames = 0
    }
}
