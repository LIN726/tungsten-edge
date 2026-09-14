import Foundation

enum FinderAutomationStatus: Equatable {
    case granted, denied, notDetermined, unavailable

    init(osStatus: Int32) {
        switch osStatus {
        case 0: self = .granted
        case -1743: self = .denied
        case -1744: self = .notDetermined
        default: self = .unavailable
        }
    }
}

enum TrashPermissionTrigger: CaseIterable {
    case launch, shown, appActivated, ownDrop, inAppTrash, emptyCommand

    func shouldAskUser(status: FinderAutomationStatus) -> Bool {
        (self == .ownDrop || self == .emptyCommand) && status == .notDetermined
    }
}

enum FinderTrashEvent {
    static let core: UInt32 = 0x636f7265
    static let count: UInt32 = 0x636e7465
    static let finder: UInt32 = 0x666e6472
    static let empty: UInt32 = 0x656d7074
    static let trashProperty: UInt32 = 0x74727368
    static let itemClass: UInt32 = 0x636f626a
    static let noConsentPrompt: UInt = 0x00020000
    static let countOptions: NSAppleEventDescriptor.SendOptions = [
        .waitForReply, .neverInteract, .init(rawValue: noConsentPrompt)
    ]
    static let emptyOptions = countOptions
    static let emptyInteractiveOptions: NSAppleEventDescriptor.SendOptions = [
        .waitForReply, .canInteract, .init(rawValue: noConsentPrompt)
    ]
}

enum FinderTrashOutcome: Equatable {
    case count(Int), succeeded, cancelled, needsInteraction, timedOut
    case denied, wouldPrompt, finderUnavailable, failed(Int)

    var permission: FinderAutomationStatus? {
        switch self {
        case .count, .succeeded: return .granted
        case .denied: return .denied
        case .wouldPrompt: return .notDetermined
        case .finderUnavailable: return .unavailable
        default: return nil
        }
    }
}

enum FinderTrashReply {
    static func parse(isCount: Bool, sendError: Int?, replyError: Int?,
                      integer: Int?, hasReply: Bool) -> FinderTrashOutcome {
        if let error = [sendError, replyError].compactMap({ $0 }).first(where: { $0 != 0 }) {
            switch error {
            case -128: return .cancelled
            case -1713: return .needsInteraction
            case -1712: return .timedOut
            case -1743: return .denied
            case -1744: return .wouldPrompt
            case -600: return .finderUnavailable
            default: return .failed(error)
            }
        }
        guard hasReply else { return .failed(-1708) }
        if isCount {
            guard let integer, integer >= 0 else { return .failed(-1700) }
            return .count(integer)
        }
        return .succeeded
    }
}

enum TrashRefreshSource: Equatable {
    case external
    case postMutation(expectedFull: Bool)
}

struct TrashStateReducer {
    private(set) var isFull = false
    private(set) var status = FinderAutomationStatus.unavailable
    private(set) var epoch: UInt64 = 0
    private(set) var needsAuthoritativeRead = false
    private var nextMutation: UInt64 = 0
    private var mutations = Set<UInt64>()
    private var overlapped = false

    var isMutating: Bool { !mutations.isEmpty }

    mutating func setPermission(_ value: FinderAutomationStatus) {
        epoch &+= 1
        status = value
        if value == .denied { isFull = false }
    }

    mutating func readReturned(epoch requestEpoch: UInt64, source: TrashRefreshSource,
                               status permission: FinderAutomationStatus,
                               outcome: FinderTrashOutcome?) {
        guard requestEpoch == epoch, !isMutating else { return }
        status = outcome?.permission ?? permission
        if status == .denied { isFull = false; return }
        guard case let .count(count) = outcome else { return }
        let full = count > 0
        if case let .postMutation(expectedFull) = source, full != expectedFull {
            needsAuthoritativeRead = true
            return
        }
        needsAuthoritativeRead = false
        isFull = full
    }

    mutating func mutationBegan() -> UInt64 {
        epoch &+= 1
        if mutations.isEmpty { overlapped = false } else { overlapped = true }
        nextMutation &+= 1
        mutations.insert(nextMutation)
        return nextMutation
    }

    /// Only an isolated success can predict direction. An overlapping batch must read truth.
    mutating func mutationEnded(_ id: UInt64, successfulDirection: Bool?) -> TrashRefreshSource? {
        guard mutations.remove(id) != nil else { return nil }
        epoch &+= 1
        guard mutations.isEmpty else { return nil }
        needsAuthoritativeRead = false
        if !overlapped, let full = successfulDirection, status == .granted {
            isFull = full
            return .postMutation(expectedFull: full)
        }
        return .external
    }

    mutating func disabled() {
        epoch &+= 1
        mutations.removeAll()
        overlapped = false
        needsAuthoritativeRead = false
    }
}

/// Finds the Finder window already showing the Trash, so a click toggles that window like its own
/// window chip would instead of asking Finder to open another one.
enum TrashWindowLookup {
    /// Finder's title for the Trash window on an English or Chinese system. Data, not copy — never
    /// localize: they match another app's window title. `localizedName` adds the name in this
    /// process's language for the rest.
    static let finderTitles: Set<String> = ["Trash", "废纸篓"]

    /// Prefers the front window (toggle then minimizes it), then a visible one, then a minimized one.
    static func actionWindowID(finderWindows: [WindowMenuEntry], localizedName: String?) -> String? {
        var titles = finderTitles
        if let localizedName, !localizedName.isEmpty { titles.insert(localizedName) }
        let matches = finderWindows.filter { titles.contains($0.title) }
        let chosen = matches.first { $0.marker == .front }
            ?? matches.first { $0.marker == .none }
            ?? matches.first
        return chosen?.actionWindowID
    }
}

enum TrashMenuPlan {
    enum Item: Equatable { case open, empty(enabled: Bool) }

    static func items(status: FinderAutomationStatus, isEmptying: Bool) -> [Item] {
        status == .denied ? [.open] : [.open, .empty(enabled: !isEmptying)]
    }
}
