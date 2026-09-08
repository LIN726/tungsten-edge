import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// 外部文件拖入任务条的系统拖放收口。路由几何 = 纯函数 `StripDropRouting.route`;
/// 本 delegate 只负责:悬停期间把目标发布给视图做高亮、松手后异步取齐 URL 再回主线程提交。
/// 挂载点必须与 "strip" coordinateSpace 同层（坐标同源,评审拍板）。
///
/// **应用 bundle 与普通文件在这里就分开**：`.app` 只走 `onCommitApplications`，
/// `onCommit`（`handleExternalDrop`）从此不可能拿到应用——那是本文件存在的第二个理由，
/// 也是「拖应用到文件夹格子上会把它从『应用程序』搬走」这个 bug 的两道闸之一。
struct StripFileDropDelegate: DropDelegate {
    /// nil = 中转格被用户关掉（不是「帧还没量到」，后者仍传 `.zero`）。
    let shelfFrame: CGRect?
    let folderFrames: [String: CGRect]
    let orderedPaths: [String]
    var headSlack: CGFloat = StripDropRouting.defaultHeadSlack
    /// dropEntered = 悬停会话开始;dropUpdated = 会话进行中移动;performDrop/dropExited = 会话结束。
    /// 视图侧据此做「高亮只能由 dropEntered 点亮 + 拖放结束看门狗」（见 externalDropHover*）。
    let onHoverBegan: (StripDropRouting.Target) -> Void
    let onHoverMoved: (StripDropRouting.Target) -> Void
    /// 参数 = 「这一支是落定吗」。只有 `performDrop` 传 `true`（空档留给落定交接）。
    let onHoverEnded: (Bool) -> Void
    let onCommit: (StripDropRouting.Target, [URL]) -> Void
    /// 拖进来的应用 bundle + 落点 x（"strip" 空间）。见 `handleExternalApplicationDrop`。
    let onCommitApplications: ([URL], CGPoint) -> Void
    /// 悬停期的让位空档：拖的是应用时给 (bundleID, 落点)，否则 `nil`（收空档）。
    /// 视图侧负责把它折成锚点并做变化门控——**这里每 ~50ms 就会调一次**。
    let onGhostMoved: (String?, CGPoint) -> Void
    /// 临时诊断用：此刻空档插在第几位（nil = 没有空档）、冻住的条宽、条的实际屏幕矩形。
    /// 后两个是用来验证「冻宽到底有没有生效」的——查清「加号闪烁」后删。
    let currentGhostIndex: () -> Int?
    let currentFrozenWidth: () -> CGFloat?
    let currentStripRect: () -> CGRect

    /// 悬停期的目标（决定高亮与光标）。应用一律 `.keepApp`。
    private func route(_ info: DropInfo) -> StripDropRouting.Target {
        route(info, isApplicationDrag: DragPasteboardInspector.containsApplication())
    }

    /// 非应用那一半的目标：混合拖拽时应用走保留、其余照旧走文件语义，所以要单独再算一份。
    private func fileRoute(_ info: DropInfo) -> StripDropRouting.Target {
        route(info, isApplicationDrag: false)
    }

    private func route(_ info: DropInfo, isApplicationDrag: Bool) -> StripDropRouting.Target {
        StripDropRouting.route(location: info.location,
                               isApplicationDrag: isApplicationDrag,
                               shelfFrame: shelfFrame,
                               folderFrames: folderFrames,
                               orderedPaths: orderedPaths,
                               headSlack: headSlack)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        let target = route(info)
        trace("entered", info, target: target)
        onHoverBegan(target)
        onGhostMoved(DragPasteboardInspector.applicationBundleID(), info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = route(info)
        trace("updated", info, target: target)
        onHoverMoved(target)
        onGhostMoved(DragPasteboardInspector.applicationBundleID(), info.location)
        return DropProposal(operation: target == .none ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) {
        trace("exited", info, target: route(info))
        onHoverEnded(false)   // 没有落定要接 → 空档当场收掉
    }

    /// 临时诊断（2026-09-08「加号一直闪」）。查清后连同 `HoverTrace.externalDrop` 一起删。
    private func trace(_ phase: String, _ info: DropInfo, target: StripDropRouting.Target) {
        guard HoverTrace.isEnabled else { return }
        HoverTrace.externalDrop(phase: phase,
                                x: info.location.x,
                                isApp: DragPasteboardInspector.containsApplication(),
                                target: "\(target)",
                                fileTarget: "\(fileRoute(info))",
                                operation: target == .none ? "forbidden" : "copy",
                                ghostIndex: currentGhostIndex(),
                                frozenWidth: currentFrozenWidth(),
                                stripRect: currentStripRect())
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = route(info)
        let fileTarget = fileRoute(info)
        let location = info.location
        trace("perform", info, target: target)
        // 落定即灭高亮,同步清（系统在这之后仍可能补发孤立 dropUpdated,已被门控忽略）。
        // 传 true：空档要留到真图标进投影，由 `keepDroppedApplications` 收（外加兜底 Timer）。
        onHoverEnded(true)
        guard target != .none else { return false }
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }

        // 异步取齐全部 URL,保持 provider 顺序,回主线程一次性提交。
        let group = DispatchGroup()
        let box = ResultBox(count: providers.count)
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                box.set(url, at: index)
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = box.urls.compactMap { $0 }
            guard !urls.isEmpty else { return }
            // 落定这一刻按**真实 URL** 再判一次应用身份（悬停期读的是拖放剪贴板，只用来
            // 决定高亮和光标）。分流是硬的：`onCommit` 收到的绝不含应用。
            let applications = urls.filter(DragPasteboardInspector.isApplication)
            let files = urls.filter { !DragPasteboardInspector.isApplication($0) }
            if !applications.isEmpty {
                onCommitApplications(applications, location)
            }
            if !files.isEmpty, fileTarget != .none {
                onCommit(fileTarget, files)
            }
        }
        return true
    }

    /// 拖放剪贴板速查：悬停期**同步**回答「这次拖的是不是应用」。
    ///
    /// 必须同步：`dropUpdated` 返回 `.forbidden` 时系统根本不会调 `performDrop`，
    /// 而应用的落点覆盖整条（包括窗口区，那里对文件是 `.none`）——用 `itemProviders`
    /// 异步取 URL 就意味着「从访达一把拖到窗口区松手」在 URL 到手之前已经被拒绝了。
    /// `NSPasteboard(name: .drag)` 在拖放会话期间对目标进程同步可读，正好补上这一格。
    ///
    /// `dropUpdated` 每 ~50ms 来一次,所以按 `changeCount` 缓存——一次拖放会话内只读一次盘。
    enum DragPasteboardInspector {
        private struct Session {
            let changeCount: Int
            let containsApplication: Bool
            /// 第一个应用 bundle 的 id。**解析 Info.plist 是读盘**，所以一次拖放会话只做一次
            /// ——`dropUpdated` 每 ~50ms 一次，逐次读盘会把主线程拖垮。
            let applicationBundleID: String?
        }
        private static var session: Session?

        /// 拖放剪贴板里有没有应用 bundle。读不到（剪贴板为空 / 非文件拖放）一律 false:
        /// 保持原有的文件语义，落定时还会按真实 URL 再判一次。
        /// 只在主线程调（DropDelegate 的回调都在主线程），缓存因此不上锁。
        static func containsApplication() -> Bool {
            currentSession().containsApplication
        }

        /// 让位空档要显示给谁。`nil` = 不是应用拖放，或 bundle 坏了读不出 id → 不让位。
        static func applicationBundleID() -> String? {
            currentSession().applicationBundleID
        }

        private static func currentSession() -> Session {
            let pasteboard = NSPasteboard(name: .drag)
            let changeCount = pasteboard.changeCount
            if let session, session.changeCount == changeCount { return session }
            let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            let apps = urls.filter(isApplication)
            let next = Session(
                changeCount: changeCount,
                containsApplication: !apps.isEmpty,
                applicationBundleID: apps.first.flatMap { Bundle(url: $0)?.bundleIdentifier }
            )
            session = next
            return next
        }

        /// 是不是应用 bundle。先问 UTType（认得改过大小写 / 没有扩展名的 bundle），
        /// 读不到再退到扩展名。`.app` 本身就是目录，所以**不能**用 `isDirectoryKey` 判。
        static func isApplication(_ url: URL) -> Bool {
            if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                return type.conforms(to: .application)
            }
            return url.pathExtension.lowercased() == "app"
        }
    }

    /// loadObject 回调在后台线程,加锁按位写,保序。
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var urls: [URL?]
        init(count: Int) { urls = Array(repeating: nil, count: count) }
        func set(_ url: URL?, at index: Int) {
            lock.lock(); defer { lock.unlock() }
            urls[index] = url
        }
    }
}
