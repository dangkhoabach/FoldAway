import Testing
@testable import FoldAwayCore

@Suite struct FoldProjectionTests {
    let w = 1512.0, h = 982.0

    @Test func atRestItIsTheIdentity() {
        let p = FoldProjection(width: w, height: h, delta: 0)
        #expect(p.bottomLeft == .init(x: 0, y: 0))
        #expect(p.bottomRight == .init(x: w, y: 0))
        #expect(abs(p.topLeft.x) < 1e-9 && abs(p.topLeft.y - h) < 1e-9)
        #expect(abs(p.topRight.x - w) < 1e-9 && abs(p.topRight.y - h) < 1e-9)
        #expect(abs(p.stretch(height: h) - 1) < 1e-9)
    }

    @Test func theHingeEdgeNeverMoves() {
        for delta in [5.0, 30, 60, 90] {
            let p = FoldProjection(width: w, height: h, delta: delta)
            #expect(p.bottomLeft == .init(x: 0, y: 0))
            #expect(p.bottomRight == .init(x: w, y: 0))
        }
    }

    @Test func thePictureStretchesUpAndNarrowsAsTheLidFoldsTowardTheViewer() {
        var previousTop = h, previousInset = 0.0
        for delta in stride(from: 10.0, through: 80, by: 10) {
            let p = FoldProjection(width: w, height: h, delta: delta)
            #expect(p.topLeft.y > previousTop)              // far edge keeps running off the top
            #expect(p.topLeft.x > previousInset)            // and keeps narrowing
            #expect(abs((w - p.topRight.x) - p.topLeft.x) < 1e-6)   // symmetric
            previousTop = p.topLeft.y; previousInset = p.topLeft.x
        }
        #expect(FoldProjection(width: w, height: h, delta: 40).stretch(height: h) > 1.05)
    }

    @Test func stayFiniteBeyondTheGeometricLimit() {
        let p = FoldProjection(width: w, height: h, delta: 179)
        #expect(p.topLeft.y.isFinite && p.topLeft.y > h)
        #expect(p.topLeft.x.isFinite && p.topLeft.x < w / 2)
    }
}
