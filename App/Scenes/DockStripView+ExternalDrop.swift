import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// DockStripView · 外部文件拖入任务条：高亮、悬停目标、落下分发。
// 2026-09-05 从 DockStripView.swift 按 extension 拆出，只搬不改。
extension DockStripView {
    /// 任务条整条高亮：**只**服务「外部拖目录悬停文件夹区（pin）」。
    ///
    /// **抽屉图标拖回任务条不再点亮**（owner 2026-08-20，对齐原生程序坞）：原生拖图标进 Dock 时
    /// Dock 本身不描边也不发光，反馈全部由图标让位表达——而我们已经有让位了
    /// （`updateDrawerToStripConvert` 一进任务条就把卡转正、邻居实时让开），而且它的判定框比
    /// 这圈高亮的判定框（正好是可见条矩形）还大一圈，两者信息完全重复。
    /// 外部拖目录那条路径没有让位反馈，整条高亮是它唯一的「能放这儿」信号，所以留着。
    /// 从访达拖应用进来同样只有整条高亮（owner 2026-09-07：做核心、不做让位预览）——
    /// 拖动途中提前分开图标要把系统 `onDrop` 与应用内自绘拖拽两套机制对接起来，比核心逻辑还贵。
    var stripHighlighted: Bool {
        switch externalDropTarget {
        case .pin, .keepApp: return true
        default: return false
        }
    }

    /// 外部拖入高亮的三个生命周期入口 + 看门狗。`externalDropTarget` 只在这一组里改。
    /// dropEntered：一次悬停会话开始 → 允许点亮。
    func externalDropHoverBegan(_ target: StripDropRouting.Target) {
        externalDropHoverActive = true
        setExternalDropTarget(target)
    }

    /// dropUpdated：只在会话进行中才更新;落定/离开后系统补发的孤立 dropUpdated（hoverActive=false）忽略 → 无回闪。
    func externalDropHoverMoved(_ target: StripDropRouting.Target) {
        guard externalDropHoverActive else { return }
        setExternalDropTarget(target)
    }

    /// performDrop/dropExited：会话结束 → 立即清高亮、作废看门狗、关门控（同步清,落定即灭,不留尾巴）。
    func externalDropHoverEnded() {
        externalDropHoverActive = false
        externalDropGeneration &+= 1
        externalDropWatchdog?.invalidate()
        externalDropWatchdog = nil
        externalDropTarget = nil
    }

    /// 设落点目标 + 重置拖放结束看门狗。`dropUpdated` 悬停期每 ~50ms 来一次会不断把 0.35s Timer 推后
    /// → 移动/静止悬停都不会误清;一旦拖放结束却没给收尾回调（dropUpdated 停），Timer 到点即清遗留高亮。
    /// generation 仍匹配才清,避免已入队的旧 Timer 误清新拖放。只动 `externalDropTarget`,不碰抽屉 unstash 高亮。
    func setExternalDropTarget(_ target: StripDropRouting.Target) {
        externalDropTarget = target
        externalDropGeneration &+= 1
        externalDropWatchdog?.invalidate()
        let gen = externalDropGeneration
        let timer = Timer(timeInterval: 0.35, repeats: false) { _ in
            guard externalDropGeneration == gen else { return }
            externalDropHoverActive = false
            externalDropTarget = nil
            externalDropWatchdog = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        externalDropWatchdog = timer
    }

    /// 外部拖放落定（DropDelegate 异步取齐 URL 后回到主线程调）。
    /// 中转收一切；命中 chip 移入；间隙/尾部固定只收目录。
    ///
    /// **`urls` 里绝不会有应用 bundle**——`StripFileDropDelegate` 已经把它们分流到
    /// `handleExternalApplicationDrop`，`.keepApp` 也不会走到这里来。
    func handleExternalDrop(_ target: StripDropRouting.Target, urls: [URL]) {
        switch target {
        case .stash:
            shelfStore.stash(paths: urls.map(\.path))
        case .moveInto(let path):
            // 第二道闸也守这一支：这里是真实的文件移动（同卷移动、跨卷复制），漏进一个
            // 应用就等于把它从「应用程序」里搬走。分流那道闸在 `StripFileDropDelegate`。
            let files = urls.filter { !StripFileDropDelegate.DragPasteboardInspector.isApplication($0) }
            guard !files.isEmpty else { break }
            onMoveExternalFiles(files, path)
        case .pin(let insertIndex):
            var index = insertIndex
            for url in urls where isPinnableDirectory(url) {
                pinnedFolderStore.insert(url.path, at: index)
                index += 1
            }
        case .keepApp, .none:
            break
        }
    }

    /// 从访达把应用拖进任务条：勾「在程序坞中保留」+ 落到光标那个位置（owner 2026-09-07）。
    /// 语义与「拖进抽屉会顺手勾上保留」并列（`Docs/27`）：只管进、不管出，每次拖入都重新勾上，
    /// 所以已经保留的应用再拖一次 = 换个位置，不是错误。
    ///
    /// - Parameter x: 落点 x（"strip" 空间），落位判定与抽屉转正共用 `StripBlockLanding`。
    func handleExternalApplicationDrop(_ urls: [URL], atX x: CGFloat) {
        let paths = urls.map(\.path)
        // 读 Info.plist 是读盘：铁律——用户动作走 `actionQueue`，既不用 `Task.detached`，
        // 也不占 Swift 协作池（那里跑着 AppTracker 的阻塞式 AX 读）。
        AppRuntime.actionQueue.async {
            let bundleIDs = paths.compactMap { path in
                Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
            }
            guard !bundleIDs.isEmpty else { return }   // 坏 bundle / 没有 Info.plist → 静默忽略
            DispatchQueue.main.async {
                keepDroppedApplications(bundleIDs, atX: x)
            }
        }
    }

    /// 逐个勾保留 + 落位。第二个及以后的应用落在前一个右边，保持拖进来的顺序。
    private func keepDroppedApplications(_ bundleIDs: [String], atX x: CGFloat) {
        var previousAnchor: (id: String, after: Bool)?
        for bundleID in bundleIDs where keptAppStore.canKeep(bundleID) {
            // 落点：拖的是它自己已有的卡时要排除自己，否则整块会以自己为锚、原地不动。
            let ownIDs = Set(freshProjection().liveEntryIDs(bundleID: bundleID))
            let target = previousAnchor ?? blockTarget(atX: x, excluding: ownIDs)
            stripOrderStore.stageExternalBlock(bundleID: bundleID,
                                               relativeTo: target?.id,
                                               after: target?.after ?? false)
            appMembershipController.setKept(bundleID, enabled: true)
            // **同步**跑一次 sync 把刚暂存的落点块消费掉。不能等 `onChange(of: keptAppStore.bundleIDs)`：
            // 那一趟什么时候跑不确定，先 commit 会把暂存丢掉（图标落到末尾），不 commit 则以后每次
            // sync 都重复搬运这一块，把用户后来的手动重排顶回去。
            reconcileLiveOrder(freshProjection())
            stripOrderStore.commitExternalBlock()
            // 一次拖多个应用：下一个落在这一个右边，保持拖进来的顺序。锚点从落定后的投影里取
            // （运行中的应用没有 `app-<bid>` 占位卡，只有窗口卡，硬拼占位 id 会锚到一个不存在的 chip）。
            let landed = freshProjection().liveEntryIDs(bundleID: bundleID).last
            previousAnchor = (landed ?? "app-\(bundleID)", true)
        }
    }

    /// 能不能固定成文件夹格子。**应用 bundle 在文件系统里就是目录**，所以光判 `isDirectoryKey`
    /// 会把应用固定成一个展开 `.app` 内部结构的格子——这是 2026-09-07 之前的真实 bug。
    /// 分流那一道闸在 `StripFileDropDelegate`，这里是第二道：`.moveInto` 是真实的文件移动
    /// （同卷移动、跨卷复制），一旦漏进来就会把用户的应用从「应用程序」里搬走。
    private func isPinnableDirectory(_ url: URL) -> Bool {
        guard !StripFileDropDelegate.DragPasteboardInspector.isApplication(url) else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? url.hasDirectoryPath
    }
}
