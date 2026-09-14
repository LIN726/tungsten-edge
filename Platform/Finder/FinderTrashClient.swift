import AppKit
import Carbon
import OSLog

final class FinderTrashClient: FinderTrashClienting {
    private let stateQueue = DispatchQueue(label: "com.tungsten.edge.trash-state", qos: .utility)
    /// Dedicated and serial: an interactive empty blocks here until Finder's own dialog closes
    /// (up to 600s), which must never hold a thread of the shared user-action queue.
    private let commandQueue = DispatchQueue(label: "com.tungsten.edge.trash-command", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private static let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "FinderTrash")

    private func currentGeneration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    func cancelPending() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
    }

    func permission(ask: Bool, completion: @escaping @MainActor (FinderAutomationStatus) -> Void) {
        let gen = currentGeneration()
        stateQueue.async { [self] in
            guard currentGeneration() == gen else {
                DispatchQueue.main.async { completion(.unavailable) }
                return
            }
            let raw = FinderAutomationPermission.status(askUserIfNeeded: ask)
            Self.logger.info("废纸篓授权检查 ask=\(ask) status=\(raw)")
            DispatchQueue.main.async { completion(FinderAutomationStatus(osStatus: raw)) }
        }
    }

    func count(completion: @escaping @MainActor (FinderTrashOutcome) -> Void) {
        let gen = currentGeneration()
        stateQueue.async { [self] in
            guard currentGeneration() == gen else {
                DispatchQueue.main.async { completion(.cancelled) }
                return
            }
            guard let trash = Self.trashObject() else {
                DispatchQueue.main.async { completion(.failed(-1700)) }
                return
            }
            let event = Self.event(eventClass: FinderTrashEvent.core, id: FinderTrashEvent.count)
            event.setParam(trash, forKeyword: keyDirectObject)
            event.setParam(NSAppleEventDescriptor(typeCode: FinderTrashEvent.itemClass),
                           forKeyword: keyAEObjectClass)
            let outcome = Self.send(event, options: FinderTrashEvent.countOptions, timeout: 5, isCount: true)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    func empty(interactive: Bool, completion: @escaping @MainActor (FinderTrashOutcome) -> Void) {
        let gen = currentGeneration()
        commandQueue.async { [self] in
            guard currentGeneration() == gen else {
                DispatchQueue.main.async { completion(.cancelled) }
                return
            }
            let event = Self.event(eventClass: FinderTrashEvent.finder, id: FinderTrashEvent.empty)
            let options = interactive ? FinderTrashEvent.emptyInteractiveOptions : FinderTrashEvent.emptyOptions
            let outcome = Self.send(event, options: options, timeout: interactive ? 600 : 30, isCount: false)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    func activateFinder(completion: @escaping @MainActor () -> Void) {
        let gen = currentGeneration()
        commandQueue.async { [self] in
            if currentGeneration() == gen {
                let event = Self.event(eventClass: 0x6d697363, id: 0x61637476)
                _ = Self.send(event, options: FinderTrashEvent.countOptions, timeout: 5, isCount: false)
            }
            DispatchQueue.main.async { completion() }
        }
    }

    func openTrash() {
        let gen = currentGeneration()
        DispatchQueue.main.async { [self] in
            guard currentGeneration() == gen else { return }
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            if NSWorkspace.shared.open(url) { return }
            commandQueue.async { [self] in
                guard currentGeneration() == gen else { return }
                if let trash = Self.trashObject() {
                    let event = Self.event(eventClass: 0x61657674, id: 0x6f646f63)
                    event.setParam(trash, forKeyword: keyDirectObject)
                    _ = Self.send(event, options: FinderTrashEvent.countOptions, timeout: 5, isCount: false)
                }
                guard currentGeneration() == gen else { return }
                DispatchQueue.main.async {
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
                        .first?.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
    }

    private static func event(eventClass: UInt32, id: UInt32) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: eventClass, eventID: id,
                              targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder"),
                              returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    /// `nil` when the coercion fails; this runs off the main thread, so it must never trap.
    private static func trashObject() -> NSAppleEventDescriptor? {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: FinderTrashEvent.trashProperty), forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: typeObjectSpecifier)
    }

    private static func send(_ event: NSAppleEventDescriptor, options: NSAppleEventDescriptor.SendOptions,
                             timeout: TimeInterval, isCount: Bool) -> FinderTrashOutcome {
        do {
            let reply = try event.sendEvent(options: options, timeout: timeout)
            let error = reply.paramDescriptor(forKeyword: keyErrorNumber).map { Int($0.int32Value) }
            let integer = reply.paramDescriptor(forKeyword: keyDirectObject)?
                .coerce(toDescriptorType: typeSInt32).map { Int($0.int32Value) }
            let outcome = FinderTrashReply.parse(isCount: isCount, sendError: nil, replyError: error,
                                                integer: integer, hasReply: true)
            logger.info("废纸篓回复 count=\(isCount) outcome=\(String(describing: outcome), privacy: .public)")
            return outcome
        } catch {
            let code = (error as NSError).code
            logger.info("废纸篓发送失败 count=\(isCount) code=\(code)")
            return FinderTrashReply.parse(isCount: isCount, sendError: code, replyError: nil,
                                         integer: nil, hasReply: false)
        }
    }
}
