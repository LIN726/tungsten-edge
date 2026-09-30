import AppKit
import Foundation
import OSLog
import ScriptingBridge

public struct BrowserTabItem: Identifiable, Hashable, Sendable {
    public let id: String           // 唯一标识: "\(pid)_\(windowID)_\(tabIndex)"
    public let pid: pid_t?
    public let windowID: Int
    public let tabIndex: Int        // 1-based index
    public let title: String
    public let url: String
    public let isActive: Bool

    public init(pid: pid_t? = nil, windowID: Int, tabIndex: Int, title: String, url: String, isActive: Bool) {
        self.id = "\(pid ?? 0)_\(windowID)_\(tabIndex)"
        self.pid = pid
        self.windowID = windowID
        self.tabIndex = tabIndex
        self.title = title
        self.url = url
        self.isActive = isActive
    }

    /// 显示用域名或清理后的 URL 摘要
    public var domainOrHost: String {
        guard let parsed = URL(string: url), let host = parsed.host else {
            return url.isEmpty ? "" : url
        }
        return host
    }
}

public final class BrowserTabService: Sendable {
    public static let shared = BrowserTabService()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.caye.macosdockcc.v2",
        category: "BrowserTabService"
    )

    private init() {}

    /// 支持的浏览器 Bundle Identifiers
    private static let chromiumBundles: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Canary",
        "com.brave.Browser",
        "company.thebrowser.Browser", // Arc
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.chromium.Chromium"
    ]

    private static let safariBundles: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview"
    ]

    /// 支持的终端应用 Bundle Identifiers
    public static let terminalBundles: Set<String> = [
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.alacritty",
        "io.alacritty",
        "net.kovidgoyal.kitty"
    ]

    /// 判断给定的 Bundle ID 是否属于受支持的浏览器
    public func isSupportedBrowser(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.chromiumBundles.contains(bundleID) || Self.safariBundles.contains(bundleID)
    }

    /// 判断给定的 Bundle ID 是否属于受支持的终端应用
    public func isSupportedTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.terminalBundles.contains(bundleID)
    }

    /// 判断给定的 Bundle ID 是否属于受支持的 Tab 宿主应用（浏览器或终端）
    public func isSupportedTabApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return isSupportedBrowser(bundleID: bundleID) || isSupportedTerminal(bundleID: bundleID)
    }

    /// 解析指定 bundleID 对应的最佳 GUI 进程 PID（排除无界面/Playwright 等 daemon 实例）
    public func resolvePID(for bundleID: String) -> pid_t? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if runningApps.isEmpty { return nil }

        // 1. 优先排除无界面实例（常规窗口应用激活策略为 .regular）
        let regularApps = runningApps.filter { $0.activationPolicy == .regular }
        let pool = regularApps.isEmpty ? runningApps : regularApps

        // 2. 若存在活跃的前台应用，直接采用
        if let activeApp = pool.first(where: { $0.isActive }) {
            return activeApp.processIdentifier
        }

        // 3. 检查是否有真实可见窗口（通过 ScriptingBridge 检查 windows 数组）
        for app in pool {
            let pid = app.processIdentifier
            if let sbApp = SBApplication(processIdentifier: pid),
               let windows = sbApp.value(forKey: "windows") as? [SBObject],
               !windows.isEmpty {
                return pid
            }
        }

        return pool.first?.processIdentifier
    }

    /// 针对特定窗口获取其所有的 Tab 列表
    /// - Parameters:
    ///   - bundleID: 宿主应用的 bundle identifier
    ///   - windowTitle: 钨极任务条上该卡片展示的窗口标题（用于窗口匹配）
    ///   - targetPID: 明确的目标进程 PID（可选，若提供则彻底消除 LaunchServices 多进程路由错乱）
    public func fetchTabs(bundleID: String, windowTitle: String, targetPID: pid_t? = nil) async -> [BrowserTabItem] {
        if isSupportedTerminal(bundleID: bundleID) {
            return fetchTerminalTabsSync(bundleID: bundleID, targetPID: targetPID)
        }

        guard isSupportedBrowser(bundleID: bundleID) else { return [] }

        let resolvedPID = targetPID ?? resolvePID(for: bundleID)
        Self.logger.notice("fetchTabs initiated for bundle: \(bundleID, privacy: .public), targetPID: \(String(describing: resolvedPID), privacy: .public), title: \(windowTitle, privacy: .public)")

        // 1. 优先使用 ScriptingBridge 直接绑定 PID 获取
        if let sbTabs = await fetchTabsViaScriptingBridge(bundleID: bundleID, targetPID: resolvedPID, windowTitle: windowTitle) {
            if !sbTabs.isEmpty {
                Self.logger.notice("fetchTabs successfully got \(sbTabs.count, privacy: .public) tabs via ScriptingBridge for \(bundleID, privacy: .public)")
                return sbTabs
            }
        }

        // 2. 回退到原有 AppleScript 机制
        Self.logger.notice("fetchTabs falling back to AppleScript for bundle: \(bundleID, privacy: .public)")
        let script: String
        let isSafari = Self.safariBundles.contains(bundleID)

        if isSafari {
            script = safariTabScript(bundleID: bundleID)
        } else {
            script = chromiumTabScript(bundleID: bundleID)
        }

        guard let output = await runAppleScript(script) else {
            Self.logger.error("Failed to query tabs via AppleScript for bundleID: \(bundleID, privacy: .public)")
            return []
        }

        let allTabs = parseTabOutput(output, pid: resolvedPID)
        if allTabs.isEmpty { return [] }

        return filterTabsForWindow(allTabs: allTabs, windowTitle: windowTitle)
    }

    /// 同步提取终端应用的全部真实窗口/标签页会话
    public func fetchTerminalTabsSync(bundleID: String, targetPID: pid_t? = nil) -> [BrowserTabItem] {
        let resolvedPID = targetPID ?? resolvePID(for: bundleID)
        guard let pid = resolvedPID else { return [] }

        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let terminalWindows = list.filter { w in
            guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { return false }
            let layer = (w[kCGWindowLayer as String] as? Int) ?? -1
            guard layer == 0 else { return false }
            let name = (w[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !name.isEmpty
        }

        if terminalWindows.isEmpty { return [] }

        return terminalWindows.enumerated().map { index, w in
            let wid = (w[kCGWindowNumber as String] as? Int) ?? 0
            let name = (w[kCGWindowName as String] as? String) ?? ""
            let isOnscreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
            return BrowserTabItem(
                pid: pid,
                windowID: wid,
                tabIndex: index + 1,
                title: name,
                url: "",
                isActive: isOnscreen
            )
        }
    }

    /// 激活指定窗口中的特定 Tab
    public func activateTab(bundleID: String, targetPID: pid_t? = nil, windowID: Int, tabIndex: Int, tabTitle: String = "") async -> Bool {
        if isSupportedTerminal(bundleID: bundleID) {
            return activateTerminalTab(bundleID: bundleID, targetPID: targetPID, windowID: windowID, tabIndex: tabIndex, tabTitle: tabTitle)
        }
        let isSafari = Self.safariBundles.contains(bundleID)
        let resolvedPID = targetPID ?? resolvePID(for: bundleID)

        // 1. 优先使用 ScriptingBridge 直接绑定 PID 激活
        if let pid = resolvedPID, let app = SBApplication(processIdentifier: pid) {
            if let windows = app.value(forKey: "windows") as? [SBObject] {
                let targetWindow = windows.first { w in
                    let wid = parseWindowID(w.value(forKey: "id"))
                    return wid == windowID
                } ?? windows.first

                if let targetWindow {
                    if isSafari {
                        if let tabs = targetWindow.value(forKey: "tabs") as? [SBObject],
                           tabIndex >= 1 && tabIndex <= tabs.count {
                            targetWindow.setValue(tabs[tabIndex - 1], forKey: "currentTab")
                        }
                    } else {
                        targetWindow.setValue(tabIndex, forKey: "activeTabIndex")
                    }
                    targetWindow.setValue(1, forKey: "index")
                    app.activate()
                    NSRunningApplication(processIdentifier: pid)?.activate(options: .activateIgnoringOtherApps)
                    return true
                }
            }
        }

        // 2. 回退到原有 AppleScript 激活
        let script: String
        if isSafari {
            script = """
            tell application id "\(bundleID)"
                activate
                repeat with w in windows
                    if (id of w as integer) = \(windowID) then
                        set current tab of w to tab \(tabIndex) of w
                        set index of w to 1
                        return "OK"
                    end if
                end repeat
                return "FAIL"
            end tell
            """
        } else {
            script = """
            tell application id "\(bundleID)"
                activate
                repeat with w in windows
                    if (id of w as integer) = \(windowID) then
                        set active tab index of w to \(tabIndex)
                        set index of w to 1
                        return "OK"
                    end if
                end repeat
                return "FAIL"
            end tell
            """
        }

        let result = await runAppleScript(script)
        return result?.contains("OK") == true
    }

    /// 关闭指定窗口中的特定 Tab
    public func closeTab(bundleID: String, targetPID: pid_t? = nil, windowID: Int, tabIndex: Int) async -> Bool {
        if isSupportedTerminal(bundleID: bundleID) {
            let pid = targetPID ?? resolvePID(for: bundleID)
            guard let pid else { return false }
            TerminalControlService.postCmdKey(pid: pid, keyCode: 13) // 'W'
            return true
        }

        let isSafari = Self.safariBundles.contains(bundleID)
        let resolvedPID = targetPID ?? resolvePID(for: bundleID)

        // 1. 优先使用 ScriptingBridge 关闭
        if let pid = resolvedPID, let app = SBApplication(processIdentifier: pid) {
            if let windows = app.value(forKey: "windows") as? [SBObject] {
                let targetWindow = windows.first { w in
                    let wid = parseWindowID(w.value(forKey: "id"))
                    return wid == windowID
                } ?? windows.first

                if let targetWindow,
                   let tabs = targetWindow.value(forKey: "tabs") as? [SBObject],
                   tabIndex >= 1 && tabIndex <= tabs.count {
                    let targetTab = tabs[tabIndex - 1]
                    if targetTab.responds(to: Selector("close")) {
                        targetTab.perform(Selector("close"))
                        return true
                    } else if targetTab.responds(to: Selector("delete")) {
                        targetTab.perform(Selector("delete"))
                        return true
                    }
                }
            }
        }

        // 2. 回退到原有 AppleScript 关闭
        let script: String
        if isSafari {
            script = """
            tell application id "\(bundleID)"
                repeat with w in windows
                    if (id of w as integer) = \(windowID) then
                        close tab \(tabIndex) of w
                        return "OK"
                    end if
                end repeat
                return "FAIL"
            end tell
            """
        } else {
            script = """
            tell application id "\(bundleID)"
                repeat with w in windows
                    if (id of w as integer) = \(windowID) then
                        close tab \(tabIndex) of w
                        return "OK"
                    end if
                end repeat
                return "FAIL"
            end tell
            """
        }

        let result = await runAppleScript(script)
        return result?.contains("OK") == true
    }

    // MARK: - ScriptingBridge Implementation

    private func fetchTabsViaScriptingBridge(bundleID: String, targetPID: pid_t?, windowTitle: String) async -> [BrowserTabItem]? {
        guard let pid = targetPID else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let app = SBApplication(processIdentifier: pid) else {
                    continuation.resume(returning: nil)
                    return
                }

                guard let windows = app.value(forKey: "windows") as? [SBObject], !windows.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let isSafari = Self.safariBundles.contains(bundleID)
                var allTabs: [BrowserTabItem] = []

                for win in windows {
                    let winID = Self.parseWindowIDStatic(win.value(forKey: "id"))
                    guard let tabs = win.value(forKey: "tabs") as? [SBObject] else { continue }

                    if isSafari {
                        let currTab = win.value(forKey: "currentTab") as? SBObject
                        for (ti, tab) in tabs.enumerated() {
                            let tabTitle = Self.sanitizeTitle(tab.value(forKey: "name") as? String ?? "")
                            let tabURL = tab.value(forKey: "URL") as? String ?? ""
                            let isAct = (tab == currTab)
                            if !tabTitle.isEmpty || !tabURL.isEmpty {
                                allTabs.append(BrowserTabItem(
                                    pid: pid,
                                    windowID: winID,
                                    tabIndex: ti + 1,
                                    title: tabTitle.isEmpty ? (tabURL.isEmpty ? "New Tab" : tabURL) : tabTitle,
                                    url: tabURL,
                                    isActive: isAct
                                ))
                            }
                        }
                    } else {
                        let actIdx = (win.value(forKey: "activeTabIndex") as? NSNumber)?.intValue ?? 1
                        for (ti, tab) in tabs.enumerated() {
                            let tabIndex = ti + 1
                            let tabTitle = Self.sanitizeTitle(tab.value(forKey: "title") as? String ?? "")
                            let tabURL = tab.value(forKey: "URL") as? String ?? ""
                            let isAct = (tabIndex == actIdx)
                            if !tabTitle.isEmpty || !tabURL.isEmpty {
                                allTabs.append(BrowserTabItem(
                                    pid: pid,
                                    windowID: winID,
                                    tabIndex: tabIndex,
                                    title: tabTitle.isEmpty ? (tabURL.isEmpty ? "New Tab" : tabURL) : tabTitle,
                                    url: tabURL,
                                    isActive: isAct
                                ))
                            }
                        }
                    }
                }

                if allTabs.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    let filtered = self.filterTabsForWindow(allTabs: allTabs, windowTitle: windowTitle)
                    continuation.resume(returning: filtered)
                }
            }
        }
    }

    private static func parseWindowIDStatic(_ rawID: Any?) -> Int {
        if let num = rawID as? NSNumber { return num.intValue }
        if let str = rawID as? String, let parsed = Int(str) { return parsed }
        if let intVal = rawID as? Int { return intVal }
        return 0
    }

    private func parseWindowID(_ rawID: Any?) -> Int {
        Self.parseWindowIDStatic(rawID)
    }

    private func filterTabsForWindow(allTabs: [BrowserTabItem], windowTitle: String) -> [BrowserTabItem] {
        let groupedByWindow = Dictionary(grouping: allTabs, by: \.windowID)
        if groupedByWindow.count <= 1, let singleWindowTabs = groupedByWindow.values.first {
            return singleWindowTabs
        }

        let cleanedTarget = cleanTitle(windowTitle)
        if !cleanedTarget.isEmpty {
            for (_, tabs) in groupedByWindow {
                // 匹配条件 1: 该窗口当前处于 active 的 tab 标题是否匹配
                if let activeTab = tabs.first(where: { $0.isActive }) {
                    let cleanedActive = cleanTitle(activeTab.title)
                    if cleanedActive.contains(cleanedTarget) || cleanedTarget.contains(cleanedActive) {
                        return tabs
                    }
                }
                // 匹配条件 2: 任意 tab 的标题包含目标标题
                if tabs.contains(where: {
                    let c = cleanTitle($0.title)
                    return c.contains(cleanedTarget) || cleanedTarget.contains(c)
                }) {
                    return tabs
                }
            }
        }

        return groupedByWindow.values.max(by: { $0.count < $1.count }) ?? allTabs
    }

    // MARK: - Private Helpers

    /// 清洗飞书/Lark等文档页面注入的不可见零宽水印及双向格式控制字符
    public static func sanitizeTitle(_ raw: String) -> String {
        let invisibleSet = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}\u{2060}\u{2061}\u{2062}\u{2063}\u{2064}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        let trimmed = raw.components(separatedBy: invisibleSet).joined()
        let result = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    private func cleanTitle(_ title: String) -> String {
        Self.sanitizeTitle(title).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func chromiumTabScript(bundleID: String) -> String {
        return """
        tell application id "\(bundleID)"
            set outText to ""
            repeat with w in windows
                try
                    set wId to id of w
                    set actIdx to active tab index of w
                    set tIdx to 1
                    repeat with t in tabs of w
                        set tTitle to ""
                        set tUrl to ""
                        try
                            set tTitle to title of t
                        end try
                        try
                            set tUrl to URL of t
                        end try
                        if tTitle is missing value then set tTitle to ""
                        if tUrl is missing value then set tUrl to ""
                        if tTitle is "" and tUrl is "" then
                            set tTitle to "New Tab"
                        end if
                        set isAct to (tIdx = actIdx)
                        set outText to outText & (wId as string) & "<SEP>" & (tIdx as string) & "<SEP>" & tTitle & "<SEP>" & tUrl & "<SEP>" & (isAct as string) & "<LF>"
                        set tIdx to tIdx + 1
                    end repeat
                end try
            end repeat
            return outText
        end tell
        """
    }

    private func safariTabScript(bundleID: String) -> String {
        return """
        tell application id "\(bundleID)"
            set outText to ""
            repeat with w in windows
                try
                    set wId to id of w
                    set currTab to current tab of w
                    set tIdx to 1
                    repeat with t in tabs of w
                        set tTitle to ""
                        set tUrl to ""
                        try
                            set tTitle to name of t
                        end try
                        try
                            set tUrl to URL of t
                        end try
                        if tTitle is missing value then set tTitle to ""
                        if tUrl is missing value then set tUrl to ""
                        if tTitle is "" and tUrl is "" then
                            set tTitle to "New Tab"
                        end if
                        set isAct to (t is currTab)
                        set outText to outText & (wId as string) & "<SEP>" & (tIdx as string) & "<SEP>" & tTitle & "<SEP>" & tUrl & "<SEP>" & (isAct as string) & "<LF>"
                        set tIdx to tIdx + 1
                    end repeat
                end try
            end repeat
            return outText
        end tell
        """
    }

    private func parseTabOutput(_ output: String, pid: pid_t? = nil) -> [BrowserTabItem] {
        var items: [BrowserTabItem] = []
        let sanitizedOutput = Self.sanitizeTitle(output)
        let lines = sanitizedOutput.components(separatedBy: "<LF>")
        for line in lines {
            let parts = line.components(separatedBy: "<SEP>")
            guard parts.count >= 5 else { continue }
            let windowID = Int(parts[0]) ?? 0
            let tabIndex = Int(parts[1]) ?? 1
            let title = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let url = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let isActive = parts[4].lowercased().contains("true")

            if !title.isEmpty || !url.isEmpty {
                items.append(BrowserTabItem(
                    pid: pid,
                    windowID: windowID,
                    tabIndex: tabIndex,
                    title: title.isEmpty ? (url.isEmpty ? "New Tab" : url) : title,
                    url: url,
                    isActive: isActive
                ))
            }
        }
        return items
    }

    private func runAppleScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let descriptor = script?.executeAndReturnError(&error)
                if let error {
                    Self.logger.error("AppleScript execution error: \(String(describing: error), privacy: .public)")
                }
                continuation.resume(returning: descriptor?.stringValue)
            }
        }
    }

    /// 激活终端应用中的指定 Tab
    public func activateTerminalTab(
        bundleID: String,
        targetPID: pid_t? = nil,
        windowID: Int,
        tabIndex: Int,
        tabTitle: String = ""
    ) -> Bool {
        let pid = targetPID ?? resolvePID(for: bundleID)
        guard let pid else { return false }

        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        app.activate(options: [.activateIgnoringOtherApps])

        // 1. 优先尝试通过 AX 菜单定位 Window -> tabTitle
        if !tabTitle.isEmpty {
            let success = AXMenuTrigger.pressMenuItem(pid: pid, candidatePaths: [
                ["Window", tabTitle],
                ["窗口", tabTitle]
            ])
            if success { return true }
        }

        // 2. 对于 Ghostty 等终端，快捷键 Cmd + 1..9 (goto_tab:1..9)
        if tabIndex >= 1 && tabIndex <= 9 {
            let keyCodes: [Int: CGKeyCode] = [
                1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
                6: 22, 7: 26, 8: 28, 9: 25
            ]
            if let keyCode = keyCodes[tabIndex] {
                TerminalControlService.postCmdKey(pid: pid, keyCode: keyCode)
            }
        }

        // 3. 同时通过 SkyLight 将该 windowID 设为前台
        TerminalControlService.focusWindowViaSkyLight(pid: pid, windowID: CGWindowID(windowID))
        return true
    }
}

// MARK: - 终端应用专属控制服务

public enum TerminalControlService {
    /// 新建终端窗口（Cmd + N 或菜单）
    public static func newWindow(bundleID: String, pid: pid_t?) {
        guard let app = (pid.flatMap { NSRunningApplication(processIdentifier: $0) })
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            return
        }
        app.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let p = app.processIdentifier
            if !AXMenuTrigger.pressMenuItem(pid: p, candidatePaths: [["File", "New Window"], ["文件", "新建窗口"]]) {
                postCmdKey(pid: p, keyCode: 45) // 'N'
            }
        }
    }

    /// 新建终端标签页（Cmd + T 或菜单）
    public static func newTab(bundleID: String, pid: pid_t?) {
        guard let app = (pid.flatMap { NSRunningApplication(processIdentifier: $0) })
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            newWindow(bundleID: bundleID, pid: pid)
            return
        }
        app.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let p = app.processIdentifier
            if !AXMenuTrigger.pressMenuItem(pid: p, candidatePaths: [["File", "New Tab"], ["文件", "新建标签页"]]) {
                postCmdKey(pid: p, keyCode: 17) // 'T'
            }
        }
    }

    /// 合成特定修饰键快捷键（Cmd + virtualKey）
    public static func postCmdKey(pid: pid_t, keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let flags: CGEventFlags = [.maskCommand]
        for down in [true, false] {
            if let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down) {
                e.flags = flags
                e.postToPid(pid)
            }
        }
    }

    private typealias SLPSSetFrontWindowFunc =
        @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias GetProcessForPIDFunc =
        @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    /// 通过 SkyLight 底层跨进程窗口调度将特定 CGWindowID 置前
    public static func focusWindowViaSkyLight(pid: pid_t, windowID: CGWindowID) {
        guard let slHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let slpsSym = dlsym(slHandle, "_SLPSSetFrontProcessWithOptions"),
              let appServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let getPSNSym = dlsym(appServices, "GetProcessForPID") else { return }

        let slps = unsafeBitCast(slpsSym, to: SLPSSetFrontWindowFunc.self)
        let getPSN = unsafeBitCast(getPSNSym, to: GetProcessForPIDFunc.self)
        var psn = ProcessSerialNumber()
        if getPSN(pid, &psn) == noErr {
            _ = withUnsafePointer(to: &psn) { slps($0, windowID, 0x200) }
        }
    }
}


