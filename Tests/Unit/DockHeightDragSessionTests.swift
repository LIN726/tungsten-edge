import AppKit
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

@MainActor
final class ResizeCursorTests: XCTestCase {
    func testOtherScreenCannotRevealCursorAndHandoffKeepsOneHide() {
        var hides = 0
        var shows = 0
        let hider = SystemCursorHider(hideCursor: { hides += 1; return .success },
                                     showCursor: { shows += 1; return .success })
        XCTAssertTrue(hider.hide(owner: "screen-a"))
        hider.show(owner: "screen-b")
        XCTAssertTrue(hider.isHidden)
        XCTAssertEqual(shows, 0)

        XCTAssertTrue(hider.hide(owner: "screen-b"))
        hider.show(owner: "screen-a")
        XCTAssertTrue(hider.isHidden)
        XCTAssertEqual(hides, 1)
        XCTAssertEqual(shows, 0)

        hider.show(owner: "screen-b")
        hider.show(owner: "screen-b")
        hider.show()
        XCTAssertFalse(hider.isHidden)
        XCTAssertEqual(shows, 1)
    }

    func testFailedHideDoesNotClaimOwnershipOrShowReplacement() {
        var shows = 0
        let hider = SystemCursorHider(hideCursor: { .failure },
                                     showCursor: { shows += 1; return .success })
        XCTAssertFalse(hider.hide(owner: "screen-a"))
        XCTAssertFalse(hider.isHidden)
        hider.show()
        XCTAssertEqual(shows, 0)
    }

    func testTerminationCanReleaseCursorAndFailedShowCanRetry() {
        var shows = 0
        let hider = SystemCursorHider(hideCursor: { .success }, showCursor: {
            shows += 1
            return shows == 1 ? .failure : .success
        })
        XCTAssertTrue(hider.hide(owner: "screen-a"))
        hider.show(owner: "screen-a")
        XCTAssertTrue(hider.isHidden)
        hider.show()
        XCTAssertFalse(hider.isHidden)
        XCTAssertEqual(shows, 2)
    }

    func testGlyphUsesUnscaledSystemFrameResizeArtworkAndHotspot() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("System frame cursor requires macOS 15") }
        _ = NSApplication.shared
        let native = NSCursor.frameResize(position: .top, directions: .all)
        XCTAssertEqual(ResizeCursorGlyph.size, native.image.size)
        XCTAssertEqual(ResizeCursorGlyph.hotSpot, native.hotSpot)
        XCTAssertEqual(try XCTUnwrap(ResizeCursorGlyph.image.tiffRepresentation),
                       try XCTUnwrap(native.image.tiffRepresentation))
    }
}
