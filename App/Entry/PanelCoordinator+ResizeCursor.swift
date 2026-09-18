import AppKit
import SwiftUI

// PanelCoordinator · the ▲▼ cursor for drag-to-resize.
//
// A never-key `.accessory` app cannot change the system cursor over its own panels
// (`Docs/05` §「后台应用改不了系统光标」), but it can hide it once `SystemCursorHider` has set the
// connection's `SetsCursorInBackground` property. So: hide the system cursor while the pointer is on a grip zone or dragging, and float a tiny
// glyph panel under the pointer instead. Kill switch `DOCK_RESIZE_CURSOR=0` (a stuck hidden
// cursor would be a bad failure mode; `SystemCursorHider` is idempotent and re-shown on every
// exit path — hover leave, drag end, teardown, app termination).

extension PanelCoordinator {
    static let resizeCursorEnabled = DebugSwitch.resizeCursor.isEnabled(in: ProcessInfo.processInfo.environment)

    /// Pointer (AppKit screen coordinates) is on a grip zone, or a drag is in progress: show the
    /// glyph centred on it and hide the system cursor.
    func showResizeCursor(at pointer: CGPoint) {
        guard Self.resizeCursorEnabled, !isSuspendedForPermissionLoss else { return }
        let panel: NSPanel
        if let existing = resizeCursorPanel {
            panel = existing
        } else {
            let created = makeFloatingPanel(contentRect: NSRect(origin: .zero, size: ResizeCursorGlyph.size),
                                            usesLiquidGlass: false)
            configurePanel(created, backgroundColor: .clear, appliesLevelOverride: false)
            created.ignoresMouseEvents = true
            // Above the bar and the drag carriers, like the carriers themselves.
            created.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            let hosting = NSHostingView(rootView: ResizeCursorGlyph())
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            resizeCursorHost = ManualPanelHost(contentView: hosting, in: created)
            resizeCursorPanel = created
            panel = created
        }
        let size = ResizeCursorGlyph.size
        let hotSpot = ResizeCursorGlyph.hotSpot
        panel.setFrame(NSRect(x: pointer.x - hotSpot.x, y: pointer.y - (size.height - hotSpot.y),
                              width: size.width, height: size.height), display: true)
        guard SystemCursorHider.shared.hide(owner: stripSurfaceID) else {
            panel.orderOut(nil)
            return
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            pinOverlappingPanelIfNeeded(panel)
        }
    }

    /// Pointer left the grip zones with no drag in progress, or the drag ended off the bar.
    func hideResizeCursor() {
        resizeCursorPanel?.orderOut(nil)
        SystemCursorHider.shared.show(owner: stripSurfaceID)
    }

    /// Strip hover report: `pointer` while on a grip zone, `nil` otherwise. Ignored during a
    /// drag — the pointer runs above the bar then and the drag path moves the glyph itself.
    func gripHoverChanged(_ pointer: CGPoint?) {
        guard !interactiveHeightResizeActive else { return }
        if let pointer { showResizeCursor(at: pointer) } else { hideResizeCursor() }
    }

    func tearDownResizeCursor() {
        hideResizeCursor()
        resizeCursorHost = nil
        if let panel = resizeCursorPanel {
            panel.contentView = NSView()
            panel.close()
        }
        resizeCursorPanel = nil
    }
}
