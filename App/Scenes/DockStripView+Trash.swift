import SwiftUI

extension DockStripView {
    func trashChip(hovered: Bool) -> some View {
        TrashChip(isFull: trashStore.isFull,
                  isDropTargeted: externalDropTarget == .trash,
                  scale: dockScale,
                  hoverStyle: hoverStyle,
                  isHovered: hovered,
                  menuItems: TrashMenuPlan.items(status: trashStore.status, isEmptying: trashStore.isEmptying),
                  onTap: { trashPrimaryTap() },
                  onOpen: { openTrashWindow() },
                  onEmpty: { trashStore.emptyTrash() })
    }

    /// Same as clicking the Trash window's own chip: front → minimize, otherwise bring it back.
    /// Only when no Trash window exists does Finder get asked to open one.
    private func trashPrimaryTap() {
        if let windowID = existingTrashWindowID() {
            runtime.toggle(windowID: windowID)
        } else {
            trashStore.openTrash()
        }
    }

    /// The menu's Open never minimizes.
    private func openTrashWindow() {
        if let windowID = existingTrashWindowID() {
            runtime.activate(windowID: windowID)
        } else {
            trashStore.openTrash()
        }
    }

    /// Reads the inventory snapshot only — no AX on the click path.
    private func existingTrashWindowID() -> String? {
        let finderWindows = WindowListMenuPlan.entries(snapshot: runtime.snapshot,
                                                       bundleID: FinderTaskbarPolicy.bundleID,
                                                       fallbackTitle: "")
        return TrashWindowLookup.actionWindowID(finderWindows: finderWindows, titles: Self.trashWindowTitles)
    }

    /// Resolved once: the projection reads it on every body pass, and the process language
    /// cannot change without a relaunch.
    static let trashWindowTitles = TrashWindowLookup.titles(
        localizedName: FileManager.default.displayName(
            atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        )
    )
}
