import CoreGraphics
import CoreVideo
import GazeCore
import OSLog
import Vision

/// Turns a camera frame into ``GazeFeatures`` using Vision face landmarks.
final class FaceFeatureExtractor: Sendable {
    /// Faces detected with lower confidence are treated as "no face".
    private let minimumConfidence: Float = 0.5

    /// Measures the largest face in the frame.
    ///
    /// - Parameter pixelBuffer: An upright camera frame.
    /// - Returns: The features, or `nil` when no face (or no eyes) could be measured reliably.
    func extract(from pixelBuffer: CVPixelBuffer) -> GazeFeatures? {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
        } catch {
            Logger.camera.error("Face detection failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard
            let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
            face.confidence >= minimumConfidence,
            let landmarks = face.landmarks,
            let leftEye = landmarks.leftEye?.normalizedPoints,
            let rightEye = landmarks.rightEye?.normalizedPoints,
            let leftPupil = landmarks.leftPupil?.normalizedPoints.first,
            let rightPupil = landmarks.rightPupil?.normalizedPoints.first
        else { return nil }

        let left = GazeFeatures.pupilOffset(pupil: leftPupil, eyeContour: leftEye)
        let right = GazeFeatures.pupilOffset(pupil: rightPupil, eyeContour: rightEye)
        let box = face.boundingBox

        return GazeFeatures(
            yaw: face.yaw?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue ?? 0,
            roll: face.roll?.doubleValue ?? 0,
            pupilX: Double(left.x + right.x) / 2,
            pupilY: Double(left.y + right.y) / 2,
            faceX: Double(box.midX),
            faceY: Double(box.midY),
            faceSize: Double(box.width)
        )
    }
}
