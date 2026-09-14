import XCTest

final class FinderTrashTests: XCTestCase {
    func testPermissionAndPromptMatrix() {
        let mappings: [(Int32, FinderAutomationStatus)] = [(0, .granted), (-1743, .denied),
                                                         (-1744, .notDetermined), (-600, .unavailable)]
        for (code, status) in mappings {
            XCTAssertEqual(FinderAutomationStatus(osStatus: code), status)
            for trigger in TrashPermissionTrigger.allCases {
                XCTAssertEqual(trigger.shouldAskUser(status: status),
                               status == .notDetermined && (trigger == .ownDrop || trigger == .emptyCommand))
            }
        }
    }

    func testAllEventsWaitAndNeverPromptForConsent() {
        for options in [FinderTrashEvent.countOptions, FinderTrashEvent.emptyOptions,
                        FinderTrashEvent.emptyInteractiveOptions] {
            XCTAssertTrue(options.contains(.waitForReply))
            XCTAssertNotEqual(options.rawValue & FinderTrashEvent.noConsentPrompt, 0)
        }
        XCTAssertEqual(FinderTrashEvent.count, 0x636e7465)
        XCTAssertEqual(FinderTrashEvent.empty, 0x656d7074)
    }

    func testReplyErrorsAndMissingValuesAreNotSuccess() {
        let errors: [(Int, FinderTrashOutcome)] = [(-128, .cancelled), (-1712, .timedOut),
            (-1713, .needsInteraction), (-1743, .denied), (-1744, .wouldPrompt),
            (-600, .finderUnavailable), (-10000, .failed(-10000))]
        for (code, outcome) in errors {
            XCTAssertEqual(FinderTrashReply.parse(isCount: false, sendError: code, replyError: nil,
                                                  integer: nil, hasReply: false), outcome)
            XCTAssertEqual(FinderTrashReply.parse(isCount: false, sendError: nil, replyError: code,
                                                  integer: nil, hasReply: true), outcome)
        }
        XCTAssertEqual(FinderTrashReply.parse(isCount: false, sendError: nil, replyError: 0,
                                              integer: nil, hasReply: true), .succeeded)
        XCTAssertEqual(FinderTrashReply.parse(isCount: true, sendError: nil, replyError: nil,
                                              integer: nil, hasReply: true), .failed(-1700))
        XCTAssertEqual(FinderTrashReply.parse(isCount: false, sendError: nil, replyError: nil,
                                              integer: nil, hasReply: false), .failed(-1708))
        XCTAssertEqual(FinderTrashReply.parse(isCount: true, sendError: nil, replyError: 0,
                                              integer: 5, hasReply: true), .count(5))
    }

    func testStaleReadsCannotChangeFullnessOrPermission() {
        var state = TrashStateReducer()
        state.setPermission(.granted)
        let epoch = state.epoch
        let op = state.mutationBegan()
        _ = state.mutationEnded(op, successfulDirection: true)
        state.readReturned(epoch: epoch, source: .external, status: .granted, outcome: .count(0))
        XCTAssertTrue(state.isFull)
        state.setPermission(.denied)
        state.readReturned(epoch: epoch, source: .external, status: .granted, outcome: .count(5))
        XCTAssertEqual(state.status, .denied)
        XCTAssertFalse(state.isFull)
    }

    func testIsolatedSuccessProtectsOnlyImmediateRead() {
        var state = TrashStateReducer()
        state.setPermission(.granted)
        let op = state.mutationBegan()
        let source = state.mutationEnded(op, successfulDirection: true)!
        state.readReturned(epoch: state.epoch, source: source, status: .granted, outcome: .count(0))
        XCTAssertTrue(state.isFull)
        XCTAssertTrue(state.needsAuthoritativeRead)
        state.readReturned(epoch: state.epoch, source: .external, status: .granted, outcome: .count(0))
        XCTAssertFalse(state.isFull)
    }

    func testOverlappingOperationsUseTruthInEitherCompletionOrder() {
        for emptyFirst in [true, false] {
            var state = TrashStateReducer()
            state.setPermission(.granted)
            let drop = state.mutationBegan()
            let empty = state.mutationBegan()
            XCTAssertNil(state.mutationEnded(emptyFirst ? empty : drop, successfulDirection: !emptyFirst))
            let source = state.mutationEnded(emptyFirst ? drop : empty, successfulDirection: emptyFirst)
            XCTAssertEqual(source, .external)
            state.readReturned(epoch: state.epoch, source: source!, status: .granted, outcome: .count(0))
            XCTAssertFalse(state.isFull)
            XCTAssertFalse(state.needsAuthoritativeRead)
        }
    }

    func testFailureAndDisableNeverApplyDirectionOrLateResults() {
        var state = TrashStateReducer()
        state.setPermission(.granted)
        let op = state.mutationBegan()
        XCTAssertEqual(state.mutationEnded(op, successfulDirection: nil), .external)
        state.readReturned(epoch: state.epoch, source: .external, status: .granted, outcome: .count(3))
        let epoch = state.epoch
        state.disabled()
        state.readReturned(epoch: epoch, source: .external, status: .denied, outcome: .denied)
        XCTAssertTrue(state.isFull)
        XCTAssertEqual(state.status, .granted)
    }

    func testClickTargetsTheExistingTrashWindowInsteadOfOpeningAnother() {
        func entry(_ id: String, _ title: String, _ marker: WindowMenuEntry.Marker) -> WindowMenuEntry {
            WindowMenuEntry(actionWindowID: id, title: title, marker: marker)
        }
        XCTAssertNil(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("docs", "Documents", .front)], localizedName: "废纸篓"))
        // The front Trash window wins, so a second click minimizes it.
        XCTAssertEqual(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("min", "废纸篓", .minimized), entry("vis", "Trash", .none),
                            entry("front", "废纸篓", .front)], localizedName: nil), "front")
        XCTAssertEqual(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("min", "Trash", .minimized), entry("vis", "Trash", .none)],
            localizedName: nil), "vis")
        // A minimized one is restored rather than opening a new window.
        XCTAssertEqual(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("min", "Corbeille", .minimized)], localizedName: "Corbeille"), "min")
    }

    func testMenusDoNotDependOnCachedFullness() {
        XCTAssertEqual(TrashMenuPlan.items(status: .denied, isEmptying: false), [.open])
        XCTAssertEqual(TrashMenuPlan.items(status: .notDetermined, isEmptying: false), [.open, .empty(enabled: true)])
        XCTAssertEqual(TrashMenuPlan.items(status: .granted, isEmptying: true), [.open, .empty(enabled: false)])
    }
}
