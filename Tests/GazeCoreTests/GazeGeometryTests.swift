import CoreGraphics
import Foundation
import Testing
@testable import GazeCore

@Suite("GazeGeometry")
struct GazeGeometryTests {
    @Test("screen point and gaze angles are exact inverses")
    func roundTrip() throws {
        let head = HeadPosition(x: -40, y: 250, distance: 600)
        let angles = GazeAngles(horizontal: 0.2, vertical: -0.15)

        let point = try #require(testGeometry.screenPoint(head: head, angles: angles))
        let back = testGeometry.angles(head: head, toward: point)

        #expect(abs(back.horizontal - angles.horizontal) < 1e-9)
        #expect(abs(back.vertical - angles.vertical) < 1e-9)
    }

    @Test("distance follows from the apparent pupil distance")
    func distanceFromPupils() throws {
        let focal = 0.5 / tan(35 * Double.pi / 180)
        var features = uniformFeatures(0)
        features.eyeMidpointX = 0.5
        features.eyeMidpointY = 0.5
        features.imageAspect = 0.75
        features.interpupillaryDistance = 0.1

        let head = try #require(testGeometry.headPosition(features))

        #expect(abs(head.distance - focal * 63 / 0.1) < 1e-9)
        #expect(abs(head.x) < 1e-9)
        #expect(abs(head.y) < 1e-9)
    }

    @Test("a face on the left of the unmirrored image is the user sitting to the right")
    func lateralPosition() throws {
        var features = uniformFeatures(0)
        features.eyeMidpointX = 0.3
        features.eyeMidpointY = 0.3
        features.imageAspect = 0.75
        features.interpupillaryDistance = 0.1

        let head = try #require(testGeometry.headPosition(features))

        #expect(head.x > 0)
        #expect(head.y > 0)
    }

    @Test("a turned head is not mistaken for a distant one")
    func yawCorrection() throws {
        var straight = uniformFeatures(0)
        straight.eyeMidpointX = 0.5
        straight.eyeMidpointY = 0.5
        straight.imageAspect = 0.75
        straight.interpupillaryDistance = 0.1
        var turned = straight
        turned.yaw = 0.4
        turned.interpupillaryDistance = 0.1 * cos(0.4)

        let a = try #require(testGeometry.headPosition(straight))
        let b = try #require(testGeometry.headPosition(turned))

        #expect(abs(a.distance - b.distance) < 1e-9)
    }

    @Test("looking straight ahead lands right in front of the eyes")
    func straightAhead() throws {
        let head = HeadPosition(x: 0, y: 108, distance: 500)

        let point = try #require(testGeometry.screenPoint(head: head, angles: GazeAngles(horizontal: 0, vertical: 0)))

        #expect(abs(point.x - 756) < 1e-9)
        #expect(abs(point.y - 100 * 982 / 196) < 1e-9)
    }

    @Test("the same gaze lands further right when the head moves right, and lower when looking down")
    func signConventions() throws {
        let angles = GazeAngles(horizontal: 0.1, vertical: 0.2)
        let center = try #require(testGeometry.screenPoint(head: HeadPosition(x: 0, y: 200, distance: 600), angles: angles))
        let movedRight = try #require(testGeometry.screenPoint(head: HeadPosition(x: 50, y: 200, distance: 600), angles: angles))
        let lookingDown = try #require(testGeometry.screenPoint(
            head: HeadPosition(x: 0, y: 200, distance: 600), angles: GazeAngles(horizontal: 0.1, vertical: 0.3)
        ))

        #expect(movedRight.x > center.x)
        #expect(lookingDown.y > center.y)
    }

    @Test("the camera is up and to the left for a user sitting low and to the right")
    func towardCamera() {
        let angles = HeadPosition(x: 100, y: 200, distance: 500).towardCamera

        #expect(angles.horizontal < 0)
        #expect(angles.vertical < 0)
    }

    @Test("a gaze nearly parallel to the screen has no screen point")
    func parallelGaze() {
        let head = HeadPosition(x: 0, y: 200, distance: 600)

        #expect(testGeometry.screenPoint(head: head, angles: GazeAngles(horizontal: 1.5, vertical: 0)) == nil)
    }

    @Test("the default prior follows Vision's conventions")
    func priorSigns() throws {
        let seat = HeadPosition(x: 0, y: 250, distance: 550)
        let user = SyntheticUser(model: .prior)
        let center = user.features(head: seat, lookingAt: CGPoint(x: 756, y: 491), yaw: 0, pitch: 0.2)
        var turnedRight = center
        turnedRight.yaw -= 0.1
        var pupilsLeftInImage = center
        pupilsLeftInImage.pupilX -= 0.1
        var noseDown = center
        noseDown.pitch += 0.1

        let base = try #require(GazeModel.prior.predict(center, geometry: testGeometry))
        let right = try #require(GazeModel.prior.predict(turnedRight, geometry: testGeometry))
        let eyesRight = try #require(GazeModel.prior.predict(pupilsLeftInImage, geometry: testGeometry))
        let down = try #require(GazeModel.prior.predict(noseDown, geometry: testGeometry))

        #expect(right.x > base.x)
        #expect(eyesRight.x > base.x)
        #expect(down.y > base.y)
    }
}
