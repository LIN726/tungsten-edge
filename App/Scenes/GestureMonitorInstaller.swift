import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 手势监视器（重击 / 中键 → 内容预览）
//
// 在任务条视图树里挂一个**本地** NSEvent 监视器：触控板重击（.pressure 压进 stage 2，去抖只在
// 进入 stage2 那一刻触发一次）+ 鼠标中键（.otherMouseDown button 2）→ 回调全局屏幕坐标，交给
// handleGesturePreview 做命中反查。监视器只观测不消费（return e），左键点击/文件夹拖拽零干扰；
// spike（2026-07-09）已验证重击不触发左键动作，无冲突。
struct GestureMonitorInstaller: NSViewRepresentable {
    let onGesture: (CGPoint) -> Void
    var onCommandKey: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        context.coordinator.onGesture = onGesture
        context.coordinator.onCommandKey = onCommandKey
        context.coordinator.start()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onGesture = onGesture   // 刷新闭包，捕获最新 chip 帧
        context.coordinator.onCommandKey = onCommandKey
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onGesture: ((CGPoint) -> Void)?
        var onCommandKey: (() -> Void)?
        private var pressureMonitor: Any?
        private var middleMonitor: Any?
        private var localFlagsMonitor: Any?
        private var globalFlagsMonitor: Any?
        private var lastStage = 0
        private var wasCommandPressed = false

        func start() {
            pressureMonitor = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] e in
                guard let self else { return e }
                if e.stage == 2 && self.lastStage < 2 { self.onGesture?(NSEvent.mouseLocation) }
                self.lastStage = e.stage
                return e
            }
            middleMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] e in
                if e.buttonNumber == 2 { self?.onGesture?(NSEvent.mouseLocation) }
                return e
            }

            let handleFlags: (NSEvent.ModifierFlags) -> Void = { [weak self] flags in
                guard let self else { return }
                let isCommand = flags.contains(.command)
                if isCommand && !self.wasCommandPressed {
                    self.onCommandKey?()
                }
                self.wasCommandPressed = isCommand
            }

            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in
                handleFlags(e.modifierFlags)
                return e
            }
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { e in
                handleFlags(e.modifierFlags)
            }
        }

        func stop() {
            if let m = pressureMonitor { NSEvent.removeMonitor(m) }
            if let m = middleMonitor { NSEvent.removeMonitor(m) }
            if let m = localFlagsMonitor { NSEvent.removeMonitor(m) }
            if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
            pressureMonitor = nil
            middleMonitor = nil
            localFlagsMonitor = nil
            globalFlagsMonitor = nil
        }
    }
}
