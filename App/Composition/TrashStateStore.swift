import AppKit
import Combine
import UniformTypeIdentifiers

protocol FinderTrashClienting {
    func permission(ask: Bool, completion: @escaping @MainActor (FinderAutomationStatus) -> Void)
    func count(completion: @escaping @MainActor (FinderTrashOutcome) -> Void)
    func empty(interactive: Bool, completion: @escaping @MainActor (FinderTrashOutcome) -> Void)
    func activateFinder(completion: @escaping @MainActor () -> Void)
    func openTrash()
    func listItemURLs(completion: @escaping @MainActor ([String]?) -> Void)
    func reveal(_ url: URL)
    func cancelPending()
}

@MainActor
final class TrashStateStore: ObservableObject {
    @Published private(set) var isFull = false
    @Published private(set) var status = FinderAutomationStatus.unavailable
    @Published private(set) var isEmptying = false
    /// The popup's contents; `.idle` while no popup shows, so mutations only refresh an open one.
    @Published private(set) var listing = TrashListing.idle
    private var listSequence: UInt64 = 0
    /// The last loaded listing, shown at once on the next open while Finder answers again —
    /// a loaded Finder takes ~1s, and the popup must not say 正在读取 on every open.
    private var lastLoaded: TrashListing?

    private let client: FinderTrashClienting
    private let fileTrasher: @Sendable (URL) throws -> Void
    private let workQueue: DispatchQueue
    /// Asynchronous on purpose: the live alert must run its modal loop outside any main-queue
    /// block (see `TrashStateStore+Live.swift`), so the answer cannot be a return value.
    private let confirmEmpty: @MainActor (@escaping @MainActor (Bool) -> Void) -> Void
    private let beep: () -> Void
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private var reducer = TrashStateReducer()
    private var started = false
    private var enabled = false
    private var lifetime: UInt64 = 0
    private var permissionSequence: UInt64 = 0
    private var readSequence: UInt64 = 0
    private var reading: UInt64?
    private var pending: TrashRefreshSource?
    private var revealOpenedWindow: @MainActor () -> Void = {}

    init(client: FinderTrashClienting, fileTrasher: @escaping @Sendable (URL) throws -> Void,
         workQueue: DispatchQueue,
         confirmEmpty: @escaping @MainActor (@escaping @MainActor (Bool) -> Void) -> Void,
         beep: @escaping () -> Void, notificationCenter: NotificationCenter) {
        self.client = client
        self.fileTrasher = fileTrasher
        self.workQueue = workQueue
        self.confirmEmpty = confirmEmpty
        self.beep = beep
        self.notificationCenter = notificationCenter
    }

    private var active: Bool { started && enabled }

    /// `revealOpenedWindow` brings the Trash window forward after each open; it has no default
    /// because an omission would leave every open behind the current app.
    func start(revealOpenedWindow: @escaping @MainActor () -> Void) {
        guard !started else { return }
        started = true
        self.revealOpenedWindow = revealOpenedWindow
        observer = notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        if let observer { notificationCenter.removeObserver(observer) }
        observer = nil
        started = false
        invalidate()
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value { refresh() } else { invalidate() }
    }

    private func invalidate() {
        lifetime &+= 1
        permissionSequence &+= 1
        listSequence &+= 1
        listing = .idle
        lastLoaded = nil
        client.cancelPending()
        reducer.disabled()
        pending = nil
        isEmptying = false
        // Keep the physical read occupied until it returns, even across a restart.
    }

    func refresh() { requestRead(.external) }

    private func requestRead(_ source: TrashRefreshSource) {
        guard active else { return }
        if pending != .external { pending = source }
        drainRead()
    }

    private func drainRead() {
        guard active, reading == nil, !reducer.isMutating, let source = pending else { return }
        pending = nil
        readSequence &+= 1
        let request = readSequence
        reading = request
        let life = lifetime
        let epoch = reducer.epoch
        client.permission(ask: false) { [weak self] permission in
            guard let self else { return }
            guard self.active, self.lifetime == life, self.reducer.epoch == epoch else {
                self.finishRead(request)
                return
            }
            guard permission == .granted else {
                self.reducer.readReturned(epoch: epoch, source: source, status: permission, outcome: nil)
                self.publish()
                self.finishRead(request)
                return
            }
            self.client.count { [weak self] outcome in
                guard let self else { return }
                if self.active, self.lifetime == life {
                    self.reducer.readReturned(epoch: epoch, source: source, status: permission, outcome: outcome)
                    self.publish()
                }
                self.finishRead(request)
            }
        }
    }

    private func finishRead(_ request: UInt64) {
        if reading == request { reading = nil }
        drainRead()
    }

    private func publish() {
        if isFull != reducer.isFull { isFull = reducer.isFull }
        if status != reducer.status { status = reducer.status }
    }

    /// Explicit permission requests supersede background permission observations.
    private func obtainPermission(trigger: TrashPermissionTrigger,
                                  completion: @escaping @MainActor (Bool) -> Void) {
        permissionSequence &+= 1
        let sequence = permissionSequence
        let life = lifetime
        reducer.setPermission(status)
        client.permission(ask: false) { [weak self] fresh in
            guard let self, self.active, self.lifetime == life else { return }
            guard self.permissionSequence == sequence else { completion(false); return }
            self.reducer.setPermission(fresh)
            self.publish()
            guard trigger.shouldAskUser(status: fresh) else {
                completion(fresh == .granted)
                return
            }
            self.client.permission(ask: true) { [weak self] result in
                guard let self, self.active, self.lifetime == life else { return }
                guard self.permissionSequence == sequence else { completion(false); return }
                self.reducer.setPermission(result)
                self.publish()
                completion(result == .granted)
            }
        }
    }

    func trash(_ urls: [URL]) {
        guard active, !urls.isEmpty else { return }
        let mutation = reducer.mutationBegan()
        let life = lifetime
        let fileTrasher = fileTrasher
        workQueue.async { [weak self] in
            var successes = 0
            var failed = false
            for url in urls {
                guard Self.canTrash(url) else { failed = true; continue }
                do { try fileTrasher(url); successes += 1 } catch { failed = true }
            }
            let didSucceed = successes > 0
            let hadFailure = failed
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, self.lifetime == life else { return }
                if hadFailure { self.beep() }
                if didSucceed, !self.isEmptying {
                    self.obtainPermission(trigger: .ownDrop) { [weak self] _ in
                        self?.endMutation(mutation, direction: true)
                    }
                } else {
                    self.endMutation(mutation, direction: didSucceed ? true : nil)
                }
            }
        }
    }

    nonisolated static func canTrash(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isVolumeKey, .volumeURLKey])
        let isApp = values?.contentType?.conforms(to: .application)
            ?? (url.pathExtension.lowercased() == "app")
        guard !isApp, values?.isVolume != true else { return false }
        let normalized = url.standardizedFileURL
        return normalized.path != "/" && normalized != values?.volume?.standardizedFileURL
    }

    func emptyTrash() {
        guard active, !isEmptying else { return }
        isEmptying = true
        let life = lifetime
        obtainPermission(trigger: .emptyCommand) { [weak self] granted in
            guard let self, self.active, self.lifetime == life else { return }
            // obtainPermission discarded any read in flight, so both early exits queue a fresh one.
            guard granted else {
                self.isEmptying = false
                self.openTrash()
                self.requestRead(.external)
                return
            }
            self.confirmEmpty { [weak self] confirmed in
                guard let self, self.active, self.lifetime == life else { return }
                guard confirmed else {
                    self.isEmptying = false
                    self.requestRead(.external)
                    return
                }
                let mutation = self.reducer.mutationBegan()
                self.sendEmpty(mutation: mutation, life: life, interactive: false)
            }
        }
    }

    private func sendEmpty(mutation: UInt64, life: UInt64, interactive: Bool) {
        let permissionVersion = permissionSequence
        client.empty(interactive: interactive) { [weak self] outcome in
            guard let self, self.active, self.lifetime == life else { return }
            if outcome == .needsInteraction, !interactive {
                self.client.activateFinder { [weak self] in
                    guard let self, self.active, self.lifetime == life else { return }
                    self.sendEmpty(mutation: mutation, life: life, interactive: true)
                }
                return
            }
            if self.permissionSequence == permissionVersion, let permission = outcome.permission {
                self.reducer.setPermission(permission)
            }
            if outcome == .denied || outcome == .wouldPrompt { self.openTrash() }
            if outcome != .succeeded && outcome != .cancelled { self.beep() }
            self.isEmptying = false
            self.endMutation(mutation, direction: outcome == .succeeded ? false : nil)
        }
    }

    private func endMutation(_ id: UInt64, direction: Bool?) {
        let source = reducer.mutationEnded(id, successfulDirection: direction)
        publish()
        if let source { requestRead(source) }
        if listing != .idle { loadItems() }
    }

    /// The popup's listing. Opening the popup is a deliberate act on the Trash, so a never-asked
    /// user gets the automation prompt here once (`.panelOpened`); denied → `.unavailable` and the
    /// popup keeps only Open in Finder. The permission step discards any read in flight, so a fresh
    /// read follows either way.
    func loadItems() {
        guard active else { return }
        let life = lifetime
        listSequence &+= 1
        let sequence = listSequence
        if case .loaded = listing {} else { listing = lastLoaded ?? .loading }
        obtainPermission(trigger: .panelOpened) { [weak self] granted in
            guard let self, self.active, self.lifetime == life, self.listSequence == sequence else { return }
            guard granted else {
                self.listing = .unavailable
                self.requestRead(.external)
                return
            }
            self.client.listItemURLs { [weak self] urls in
                guard let self, self.active, self.lifetime == life, self.listSequence == sequence else { return }
                self.listing = urls.map { TrashListingPlan.build(urlStrings: $0) } ?? .unavailable
                if case .loaded = self.listing { self.lastLoaded = self.listing }
                self.requestRead(.external)
            }
        }
    }

    /// The popup closed: drop the listing so later mutations do not keep asking Finder for it.
    func clearListing() {
        listSequence &+= 1
        if case .loaded = listing { lastLoaded = listing }
        listing = .idle
    }

    /// Selects one item in the Trash window (Finder's `reveal`, non-activating) and brings that
    /// window forward the way `openTrash` does.
    func revealItem(_ url: URL) {
        guard active else { return }
        client.reveal(url)
        revealOpenedWindow()
    }

    func noteTrashedInApp() {
        guard active else { return }
        let mutation = reducer.mutationBegan()
        endMutation(mutation, direction: true)
    }

    /// Finder opens the window without activating, so every open is followed by bringing that one
    /// window forward.
    func openTrash() {
        guard active else { return }
        client.openTrash()
        revealOpenedWindow()
    }
}
