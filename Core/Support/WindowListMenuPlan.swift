import Foundation

/// 应用级图标右键菜单顶部的「窗口列表」条目（像原生 Dock：✓ = 前台窗口，◇ = 已最小化）。
/// 只出现在「一个图标代表整个应用」的入口（保留 / 消息区 / 抽屉 / 访达常驻卡）；
/// 具体窗口卡自己就是那个窗口，不列（owner 2026-08-24）。
struct WindowMenuEntry: Equatable {
    enum Marker: Equatable {
        case none
        /// 该应用的前台（active）窗口——原生 Dock 打 ✓ 的那一行。
        case front
        /// 整组都已最小化——原生 Dock 打 ◇ 的那一行。点击走 activate，会还原它。
        case minimized
    }

    /// 点击后交给 `runtime.activate(windowID:)` 的动作目标（组的当前代表成员）。
    let actionWindowID: String
    let title: String
    let marker: Marker
}

enum WindowListMenuPlan {
    /// 从快照取某 bundle 的全部窗口，按 strip 顺序、按 `groupID` 折叠（原生标签组一组一行，
    /// 后台标签不单列——与任务条的单座位模型同口径）。**只读快照、不做 AX**：
    /// 菜单在右键瞬间同步构建（menus.md），任何现场盘点都会卡住这一下。
    static func entries(
        snapshot: DockSnapshot,
        bundleID: String,
        fallbackTitle: String
    ) -> [WindowMenuEntry] {
        var groups: [[WindowRecord]] = []
        var indexByGroup: [String: Int] = [:]
        for id in snapshot.orderedWindowIDs {
            guard let record = snapshot.windows[id],
                  record.bundleIdentifier == bundleID,
                  // app-* 兜底座位不是真窗口；已在关闭途中 / 已消失的也不列。
                  !record.groupID.hasPrefix("app-"),
                  record.status != .closedPending,
                  record.status != .disappeared
            else { continue }
            if let idx = indexByGroup[record.groupID] {
                groups[idx].append(record)
            } else {
                indexByGroup[record.groupID] = groups.count
                groups.append([record])
            }
        }
        return groups.map { members in
            // 代表窗与 `StripItem.init(members:)` 同一规则：active ?? 首个可见成员 ?? 首个。
            let representative = members.first { $0.status == .active }
                ?? members.first { $0.status != .minimized && $0.status != .hidden }
                ?? members[0]
            let marker: WindowMenuEntry.Marker
            if representative.status == .active {
                marker = .front
            } else if members.allSatisfy({ $0.status == .minimized }) {
                marker = .minimized
            } else {
                marker = .none
            }
            return WindowMenuEntry(
                actionWindowID: representative.id.rawValue,
                title: WindowDisplayTitle.resolve(
                    rawTitle: representative.title,
                    fallbackName: fallbackTitle
                ),
                marker: marker
            )
        }
    }
}

// MARK: - 文档与代码编辑器应用策略（含 PyCharm、JetBrains 全家桶及主流 IDE）

public enum DocumentAppPolicy {
    /// 支持的文档与代码编辑应用 Bundle Identifiers（Typora、VS Code、Xcode、Cursor、PyCharm 等）
    public static let documentBundles: Set<String> = [
        "abnerworks.Typora",
        "io.typora",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeExploration",
        "com.visualstudio.code.oss",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",      // Windsurf
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.apple.TextEdit",
        "dev.zed.Zed",
        "com.panic.Nova",
        "md.obsidian",
        // JetBrains 家族 IDE 及主流开发环境
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.pycharm-CE",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.intellij-CE",
        "com.jetbrains.WebStorm",
        "com.jetbrains.webstorm",
        "com.jetbrains.CLion",
        "com.jetbrains.clion",
        "com.jetbrains.goland",
        "com.google.android.studio",
        "com.jetbrains.rider",
        "com.jetbrains.rustrover",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.phpstorm",
        "com.jetbrains.rubymine",
        "com.jetbrains.datagrip",
        "com.jetbrains.dataspell",
        "com.jetbrains.fleet",
        "com.jetbrains.aqua",
        "com.jetbrains.gateway",
        "com.jetbrains.mps",
        "com.rstudio.positron",
        "org.rstudio.RStudio"
    ]

    /// 判断给定的 Bundle ID 是否属于受支持的文档/代码编辑应用（Typora、VS Code、PyCharm 等）
    public static func isSupportedDocumentApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return documentBundles.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.")
    }
}

// MARK: - 窗口菜单系统动作与多窗口管理操作过滤引擎

public enum WindowMenuActionFilter {
    /// 必须被过滤掉的系统/应用通用窗口操作菜单项名称（小写化精确匹配）
    public static let systemActionExactNames: Set<String> = [
        // English
        "minimize", "zoom", "close", "bring all to front", "arrange in front",
        "enter full screen", "exit full screen", "toggle full screen",
        "move tab to new window", "merge all windows",
        "show previous tab", "show next tab", "select next tab", "select previous tab",
        "next tab", "previous tab", "cycle through windows",
        "tile window to left of screen", "tile window to right of screen",
        "fill", "center", "left & right", "top & bottom", "quick note",
        // IDE / JetBrains / 终端特定操作
        "next project window", "previous project window",
        "background tasks", "show main menu",
        // Ghostty / 终端与多窗口管理特定动作
        "minimize all", "zoom all", "show/hide all terminals",
        "zoom split", "select previous split", "select next split",
        "return to default size", "float on top", "use as default",
        "remove window from set", "split horizontally", "split vertically",
        "close split", "maximize active pane", "unmaximize active pane",
        "bury", "disown", "pin to all spaces",
        "toggle quick terminal", "toggle inspector",
        // 简体中文
        "最小化", "缩放", "关闭", "前置全部窗口", "前置所有窗口",
        "进入全屏幕", "退出全屏幕", "切换全屏幕",
        "将标签页移到新窗口", "合并所有窗口",
        "显示上一个标签页", "显示下一个标签页", "选择下一个标签", "选择上一个标签",
        "下一个标签页", "上一个标签页", "快速备忘录",
        "拼贴窗口到屏幕左侧", "拼贴窗口到屏幕右侧", "将窗口拼贴到屏幕左侧", "将窗口拼贴到屏幕右侧",
        "全屏幕", "还原", "移到",
        "最小化所有窗口", "缩放所有窗口", "全部最小化", "全部缩放",
        "下一个项目窗口", "上一个项目窗口", "后台任务", "显示主菜单",
        "显示/隐藏所有终端", "缩放分屏", "选择上一个分屏", "选择下一个分屏",
        "恢复默认大小", "置顶", "设为默认", "从窗口集合移除",
        // 繁体中文
        "縮小", "縮放", "關閉", "將所有視窗移至最前",
        "進入全螢幕", "結束全螢幕", "將標籤頁移到新視窗", "合併所有視窗",
        "顯示上一個標籤頁", "顯示下一個標籤頁", "選擇下一個標籤", "選擇上一個標籤",
        "將視窗拼貼到螢幕左側", "將視窗拼貼到螢幕右側",
        "下一個專案視窗", "上一個專案視窗", "後台任務", "顯示主功能表",
        "全部縮小", "全部縮放", "顯示/隱藏所有終端",
        // 日文
        "しまう", "拡大/縮小", "すべてを手前に移動", "フルスクリーンにする", "フルスクリーンを解除",
        "すべてのウインドウを結合", "前のタブを表示", "次のタブを表示",
        "次のプロジェクトウインドウ", "前のプロジェクトウインドウ", "バックグラウンドタスク",
        "ウインドウを画面左側に配置", "ウインドウ配置"
    ]

    /// 动作菜单项的前缀过滤（小写匹配）
    public static let systemActionPrefixes: [String] = [
        "tile ", "move to ", "replace ", "拼贴", "将窗口拼贴", "將視窗拼貼", "移到 ", "移至 ",
        "select split", "zoom split", "split "
    ]

    public static func isSystemAction(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if systemActionExactNames.contains(lower) {
            return true
        }
        for prefix in systemActionPrefixes {
            if lower.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }
}
