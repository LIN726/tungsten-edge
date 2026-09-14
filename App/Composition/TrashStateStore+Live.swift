import AppKit

extension TrashStateStore {
    static let shared = TrashStateStore(
        client: FinderTrashClient(),
        fileTrasher: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        workQueue: AppRuntime.actionQueue,
        confirmEmpty: { completion in
            // Run the modal loop from a run-loop block, never inside a main-queue block: CFRunLoop
            // does not service the main dispatch queue in a modal loop nested in one, so every
            // taskbar update would stall until the alert is answered.
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Are you sure you want to permanently erase the items in the Trash?")
                    alert.informativeText = String(localized: "You can’t undo this action.")
                    alert.addButton(withTitle: String(localized: "Empty Trash")).hasDestructiveAction = true
                    alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
                    completion(alert.runModal() == .alertFirstButtonReturn)
                }
            }
        },
        beep: { NSSound.beep() },
        notificationCenter: NSWorkspace.shared.notificationCenter
    )
}
