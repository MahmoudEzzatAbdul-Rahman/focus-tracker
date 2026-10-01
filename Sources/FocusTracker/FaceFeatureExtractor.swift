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
    /// - Parameter pixelBuffer: An upright, unmirrored camera frame.
    /// - Returns: The features, or `nil` when no face (or no eyes) could be measured reliably.
    func extract(from pixelBuffer: CVPixelBuffer) -> GazeFeatures? {
        // Only the face rectangles request measures head pose; a landmarks request on its own
        // reports yaw and roll as 0 and pitch as nil. Landmarks run on the detected faces keep
        // the pose.
        let faces = VNDetectFaceRectanglesRequest()
        faces.revision = VNDetectFaceRectanglesRequestRevision3
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        // More points along each eye give a steadier eye box for the pupil offset.
        request.constellation = .constellation76Points
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try handler.perform([faces])
            guard let detected = faces.results, !detected.isEmpty else { return nil }
            request.inputFaceObservations = detected
            try handler.perform([request])
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

        // Landmarks are normalized to the face box; place the pupils in the whole image.
        let box = face.boundingBox
        let imageAspect = Double(CVPixelBufferGetHeight(pixelBuffer)) / Double(max(CVPixelBufferGetWidth(pixelBuffer), 1))
        func inImage(_ point: CGPoint) -> CGPoint {
            CGPoint(x: box.minX + point.x * box.width, y: box.minY + point.y * box.height)
        }
        let leftInImage = inImage(leftPupil)
        let rightInImage = inImage(rightPupil)
        let pupilDistance = hypot(
            Double(rightInImage.x - leftInImage.x),
            Double(rightInImage.y - leftInImage.y) * imageAspect
        )

        return GazeFeatures(
            yaw: face.yaw?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue ?? 0,
            roll: face.roll?.doubleValue ?? 0,
            pupilX: Double(left.x + right.x) / 2,
            pupilY: Double(left.y + right.y) / 2,
            eyeMidpointX: Double(leftInImage.x + rightInImage.x) / 2,
            eyeMidpointY: Double(leftInImage.y + rightInImage.y) / 2,
            interpupillaryDistance: pupilDistance,
            imageAspect: imageAspect,
            eyeOpenness: (GazeFeatures.eyeOpenness(eyeContour: leftEye) + GazeFeatures.eyeOpenness(eyeContour: rightEye)) / 2
        )
    }
}
