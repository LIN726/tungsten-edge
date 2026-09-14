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
        let known = TrashWindowLookup.titles(localizedName: nil)
        XCTAssertNil(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("docs", "Documents", .front)], titles: known))
        // The front Trash window wins, so a second click minimizes it.
        XCTAssertEqual(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("min", "废纸篓", .minimized), entry("vis", "Trash", .none),
                            entry("front", "废纸篓", .front)], titles: known), "front")
        XCTAssertEqual(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("min", "Trash", .minimized), entry("vis", "Trash", .none)],
            titles: known), "vis")
        // A minimized one is restored rather than opening a new window.
        XCTAssertEqual(TrashWindowLookup.actionWindowID(
            finderWindows: [entry("min", "Corbeille", .minimized)],
            titles: TrashWindowLookup.titles(localizedName: "Corbeille")), "min")
    }

    private func finderRecord(_ id: String, _ title: String, group: String? = nil,
                              bundle: String = "com.apple.finder") -> WindowRecord {
        WindowRecord(id: WindowID(rawValue: id), appID: AppID(rawValue: bundle), pid: 100,
                     bundleIdentifier: bundle, title: title, bounds: nil, status: .inactive,
                     cgWindowID: 1, groupID: group ?? id)
    }

    private func snapshot(_ records: [WindowRecord]) -> DockSnapshot {
        DockSnapshot(windows: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }),
                     orderedWindowIDs: records.map(\.id))
    }

    func testTrashWindowCardIsAbsorbedOnlyWhileFinderKeepsAnotherCard() {
        let titles = TrashWindowLookup.titles(localizedName: nil)
        let trash = finderRecord("cgw-1", "废纸篓")
        let docs = finderRecord("cgw-2", "归档")
        let withOther = snapshot([docs, trash])
        XCTAssertEqual(TrashWindowAbsorption.absorbedWindowIDs(in: withOther, trashTitles: titles),
                       [trash.id])
        // The remaining Finder card counts alone again, so it renders as the bare icon.
        let items = StripItem.items(from: TrashWindowAbsorption.removing([trash.id], from: withOther))
        XCTAssertEqual(items.map(\.id), [docs.id.rawValue])
        XCTAssertFalse(items[0].showsTitle)
        // A lone Trash window is the only Finder card: absorbing it would take Finder off the bar.
        XCTAssertTrue(TrashWindowAbsorption.absorbedWindowIDs(in: snapshot([trash]), trashTitles: titles).isEmpty)
        // A tab group showing the Trash tab keeps its card.
        let tabbed = snapshot([docs, finderRecord("cgw-3", "废纸篓", group: "tabgrp-1"),
                               finderRecord("cgw-4", "下载", group: "tabgrp-1")])
        XCTAssertTrue(TrashWindowAbsorption.absorbedWindowIDs(in: tabbed, trashTitles: titles).isEmpty)
        // Another app's window titled "Trash" is not Finder's.
        let other = snapshot([docs, finderRecord("cgw-5", "Trash", bundle: "com.example.mail")])
        XCTAssertTrue(TrashWindowAbsorption.absorbedWindowIDs(in: other, trashTitles: titles).isEmpty)
    }

    func testMenusDoNotDependOnCachedFullness() {
        XCTAssertEqual(TrashMenuPlan.items(status: .denied, isEmptying: false), [.open])
        XCTAssertEqual(TrashMenuPlan.items(status: .notDetermined, isEmptying: false), [.open, .empty(enabled: true)])
        XCTAssertEqual(TrashMenuPlan.items(status: .granted, isEmptying: true), [.open, .empty(enabled: false)])
    }
}
