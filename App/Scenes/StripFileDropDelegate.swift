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
    let onHoverEnded: () -> Void
    let onCommit: (StripDropRouting.Target, [URL]) -> Void
    /// 拖进来的应用 bundle + 落点 x（"strip" 空间）。见 `handleExternalApplicationDrop`。
    let onCommitApplications: ([URL], CGPoint) -> Void

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
        onHoverBegan(route(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = route(info)
        onHoverMoved(target)
        return DropProposal(operation: target == .none ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) {
        onHoverEnded()
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = route(info)
        let fileTarget = fileRoute(info)
        let location = info.location
        onHoverEnded()   // 落定即灭高亮,同步清（系统在这之后仍可能补发孤立 dropUpdated,已被门控忽略）。
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
        private static var cachedChangeCount: Int?
        private static var cachedResult = false

        /// 拖放剪贴板里有没有应用 bundle。读不到（剪贴板为空 / 非文件拖放）一律 false:
        /// 保持原有的文件语义，落定时还会按真实 URL 再判一次。
        /// 只在主线程调（DropDelegate 的回调都在主线程），缓存因此不上锁。
        static func containsApplication() -> Bool {
            let pasteboard = NSPasteboard(name: .drag)
            let changeCount = pasteboard.changeCount
            if cachedChangeCount == changeCount { return cachedResult }
            let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            let result = urls.contains(where: isApplication)
            cachedChangeCount = changeCount
            cachedResult = result
            return result
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
