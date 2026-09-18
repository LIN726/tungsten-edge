import CoreGraphics
import XCTest

final class DockHeightDragSessionTests: XCTestCase {
    func testPointerUpMakesTheBarTaller() {
        let session = DockHeightDragSession(startHeight: 54, startPointerY: 100)
        XCTAssertEqual(session.height(forPointerY: 110).points, 64)
    }

    func testPointerDownMakesTheBarShorter() {
        let session = DockHeightDragSession(startHeight: 54, startPointerY: 100)
        XCTAssertEqual(session.height(forPointerY: 92).points, 46)
    }

    func testClampsAtBothEnds() {
        let session = DockHeightDragSession(startHeight: 54, startPointerY: 100)
        XCTAssertEqual(session.height(forPointerY: 400).points, DockPanelHeight.maximum)
        XCTAssertEqual(session.height(forPointerY: -400).points, DockPanelHeight.minimum)
    }

    func testSubPointTravelRoundsToWholePoints() {
        let session = DockHeightDragSession(startHeight: 54, startPointerY: 100)
        XCTAssertEqual(session.height(forPointerY: 100.4).points, 54)
        XCTAssertEqual(session.height(forPointerY: 100.5).points, 55)
        XCTAssertEqual(session.height(forPointerY: 99.5).points, 54, "round-half-to-even is not used: .rounded() is schoolbook")
    }

    func testPastTheClampThePointerMustComeBackBeforeTheBarShrinks() {
        // Stateless formula, like the native divider: 60pt past the cap, then 20pt back down —
        // still at the cap; only once the raw value is under the cap does the height move.
        let session = DockHeightDragSession(startHeight: 54, startPointerY: 100)
        XCTAssertEqual(session.height(forPointerY: 186).points, 80)
        XCTAssertEqual(session.height(forPointerY: 166).points, 80)
        XCTAssertEqual(session.height(forPointerY: 125).points, 79)
    }
}
