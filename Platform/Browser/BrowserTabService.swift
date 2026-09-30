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

    /// 支持的文档与代码编辑应用 Bundle Identifiers（Typora、VS Code、Xcode、Cursor、PyCharm 等）
    public static var documentBundles: Set<String> { DocumentAppPolicy.documentBundles }

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

    /// 判断给定的 Bundle ID 是否属于受支持的文档/代码编辑应用（Typora、VS Code、PyCharm 等）
    public func isSupportedDocumentApp(bundleID: String?) -> Bool {
        DocumentAppPolicy.isSupportedDocumentApp(bundleID: bundleID)
    }

    /// 判断给定的 Bundle ID 是否属于受支持的 Tab 宿主应用（浏览器、终端、文档/代码编辑）
    public func isSupportedTabApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return isSupportedBrowser(bundleID: bundleID)
            || isSupportedTerminal(bundleID: bundleID)
            || isSupportedDocumentApp(bundleID: bundleID)
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
        if isSupportedTerminal(bundleID: bundleID) || isSupportedDocumentApp(bundleID: bundleID) {
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

    /// 同步提取终端或文档/代码编辑应用的全部真实窗口/标签页会话（Ghostty、Typora、VS Code 等）
    public func fetchTerminalTabsSync(bundleID: String, targetPID: pid_t? = nil) -> [BrowserTabItem] {
        let resolvedPID = targetPID ?? resolvePID(for: bundleID)
        guard let pid = resolvedPID else { return [] }
        return AppWindowTabReader.fetchTabs(pid: pid)
    }

    /// 提取多窗口/多标签应用的全部真实会话（终端、Typora、VS Code、Xcode 等）
    public func fetchWindowTabsSync(bundleID: String, targetPID: pid_t? = nil) -> [BrowserTabItem] {
        fetchTerminalTabsSync(bundleID: bundleID, targetPID: targetPID)
    }

    /// 激活指定窗口中的特定 Tab
    public func activateTab(bundleID: String, targetPID: pid_t? = nil, windowID: Int, tabIndex: Int, tabTitle: String = "") async -> Bool {
        if isSupportedTerminal(bundleID: bundleID) || isSupportedDocumentApp(bundleID: bundleID) {
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
        if isSupportedTerminal(bundleID: bundleID) || isSupportedDocumentApp(bundleID: bundleID) {
            let pid = targetPID ?? resolvePID(for: bundleID)
            guard let pid else { return false }
            _ = activateTerminalTab(bundleID: bundleID, targetPID: pid, windowID: windowID, tabIndex: tabIndex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                TerminalControlService.postCmdKey(pid: pid, keyCode: 13) // 'W'
            }
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

    /// 激活终端或文档编辑应用中的指定 Tab
    public func activateTerminalTab(
        bundleID: String,
        targetPID: pid_t? = nil,
        windowID: Int,
        tabIndex: Int,
        tabTitle: String = ""
    ) -> Bool {
        let pid = targetPID ?? resolvePID(for: bundleID)
        guard let pid else { return false }
        return AppWindowTabReader.activateTab(
            pid: pid,
            tabIndex: tabIndex,
            tabTitle: tabTitle,
            windowID: windowID
        )
    }

    /// 同步激活多标签会话应用的指定 Tab
    public func activateTabSync(
        bundleID: String,
        targetPID: pid_t? = nil,
        windowID: Int,
        tabIndex: Int,
        tabTitle: String = ""
    ) -> Bool {
        activateTerminalTab(
            bundleID: bundleID,
            targetPID: targetPID,
            windowID: windowID,
            tabIndex: tabIndex,
            tabTitle: tabTitle
        )
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

// MARK: - 通用多窗口与标签页读取与调度引擎 (基于 Accessibility Window 菜单)

public enum AppWindowTabReader {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.caye.macosdockcc.v2",
        category: "AppWindowTabReader"
    )

    /// 识别 Window / 窗口 菜单项关键词（多语言覆盖）
    private static let windowMenuKeywords: Set<String> = [
        "window", "窗口", "視窗", "ウインドウ", "fenster", "fenêtre", "ventana", "finestra", "윈도우", "окно"
    ]

    /// 必须被过滤掉的系统/应用通用窗口操作菜单项名称（小写化精确匹配）
    private static var systemActionExactNames: Set<String> { WindowMenuActionFilter.systemActionExactNames }
    private static var systemActionPrefixes: [String] { WindowMenuActionFilter.systemActionPrefixes }

    /// 识别菜单项是否属于分隔符
    public static func isSeparator(_ element: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           subrole == "AXMenuSeparator" || subrole == "AXSeparator" || subrole.contains("Separator") {
            return true
        }
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           role == "AXMenuSeparator" || role == "AXSeparator" || role.contains("Separator") {
            return true
        }
        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        if titleResult == .success {
            let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty {
                return true
            }
        } else if titleResult == .noValue || titleResult == .attributeUnsupported {
            return true
        }
        return false
    }

    /// 提取 Window 菜单中的权威窗口/标签页候选集（按 AppKit 规范截取最后一个分隔符之后的内容）
    private static func extractWindowCandidates(from subItems: [AXUIElement]) -> [AXUIElement] {
        // AppKit 规范：NSApplication.windowsMenu 在最后一个分隔符之后动态挂载当前全部打开的窗口/标签页
        if let lastSepIndex = subItems.lastIndex(where: { isSeparator($0) }),
           lastSepIndex + 1 < subItems.count {
            let windowSection = Array(subItems[(lastSepIndex + 1)...])
            // 校验该段内是否存在非系统动作的候选；若存在则以该段为权威窗口/标签列表
            let hasNonSystemActions = windowSection.contains { item in
                var titleRef: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !title.isEmpty && !isSystemAction(title) && !hasSubmenu(item)
            }
            if hasNonSystemActions {
                return windowSection
            }
        }
        return subItems
    }

    /// 从给定进程中提取其所有打开的窗口与标签页会话
    public static func fetchTabs(pid: pid_t) -> [BrowserTabItem] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.05)

        // 1. 优先从菜单栏 Window (窗口) 菜单提取真实标签页（Ghostty、Typora、VS Code、Terminal 等）
        if let windowMenu = findWindowMenu(in: appElement),
           let subMenu = getSubMenu(from: windowMenu) {
            AXUIElementSetMessagingTimeout(subMenu, 0.05)
            var subItemsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(subMenu, kAXChildrenAttribute as CFString, &subItemsRef) == .success,
               let subItems = subItemsRef as? [AXUIElement] {
                let candidateItems = extractWindowCandidates(from: subItems)
                var tabs: [BrowserTabItem] = []
                for item in candidateItems {
                    AXUIElementSetMessagingTimeout(item, 0.05)
                    if isSeparator(item) { continue }
                    var titleRef: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
                    let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if title.isEmpty { continue }

                    // 过滤具有二级子菜单的操作项（如拼贴/移动）
                    if hasSubmenu(item) { continue }
                    // 过滤系统固有动作
                    if isSystemAction(title) { continue }

                    // 检查激活勾选标识（当前前台活跃会话带 ✓）
                    var markRef: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(item, "AXMenuItemMarkChar" as CFString, &markRef)
                    let mark = (markRef as? String) ?? ""
                    let isActive = mark.contains("✓") || mark.contains("\u{2713}") || mark.contains("✔")

                    let tabIndex = tabs.count + 1
                    tabs.append(BrowserTabItem(
                        pid: pid,
                        windowID: 0,
                        tabIndex: tabIndex,
                        title: title,
                        url: "",
                        isActive: isActive
                    ))
                }
                if !tabs.isEmpty {
                    return tabs
                }
            }
        }

        // 2. 兜底方案：通过 AX kAXWindowsAttribute 遍历顶级窗口（适用于无菜单栏或特殊窗口）
        return fetchTabsFromAXWindows(appElement: appElement, pid: pid)
    }

    /// 激活指定标签页
    public static func activateTab(pid: pid_t, tabIndex: Int, tabTitle: String, windowID: Int = 0) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.08)

        if let windowMenu = findWindowMenu(in: appElement),
           let subMenu = getSubMenu(from: windowMenu) {
            AXUIElementSetMessagingTimeout(subMenu, 0.08)
            var subItemsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(subMenu, kAXChildrenAttribute as CFString, &subItemsRef) == .success,
               let subItems = subItemsRef as? [AXUIElement] {
                let candidateItems = extractWindowCandidates(from: subItems)
                // 筛选出属于真实 Tab/Window 的菜单项
                let tabItems = candidateItems.filter { item in
                    if isSeparator(item) || hasSubmenu(item) { return false }
                    var titleRef: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
                    let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if title.isEmpty || isSystemAction(title) {
                        return false
                    }
                    return true
                }

                // 优先精准按序号触发（解决重名标签问题，如多个相同的 ~/projects/artemis）
                if tabIndex >= 1 && tabIndex <= tabItems.count {
                    let target = tabItems[tabIndex - 1]
                    if AXUIElementPerformAction(target, kAXPressAction as CFString) == .success {
                        if windowID > 0 {
                            TerminalControlService.focusWindowViaSkyLight(pid: pid, windowID: CGWindowID(windowID))
                        }
                        return true
                    }
                }

                // 兜底按标题匹配触发
                for item in tabItems {
                    var titleRef: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
                    let itemTitle = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !tabTitle.isEmpty && (itemTitle == tabTitle || itemTitle.contains(tabTitle) || tabTitle.contains(itemTitle)) {
                        if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                            if windowID > 0 {
                                TerminalControlService.focusWindowViaSkyLight(pid: pid, windowID: CGWindowID(windowID))
                            }
                            return true
                        }
                    }
                }
            }
        }

        // 终端快捷键兜底 (Cmd + 1..9)，仅对终端应用有效，避免误触 IDE 的快捷键（如 PyCharm 的 Cmd+1 打开项目面板）
        if let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           BrowserTabService.shared.isSupportedTerminal(bundleID: bid),
           tabIndex >= 1 && tabIndex <= 9 {
            let keyCodes: [Int: CGKeyCode] = [
                1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
                6: 22, 7: 26, 8: 28, 9: 25
            ]
            if let keyCode = keyCodes[tabIndex] {
                TerminalControlService.postCmdKey(pid: pid, keyCode: keyCode)
            }
        }

        if windowID > 0 {
            TerminalControlService.focusWindowViaSkyLight(pid: pid, windowID: CGWindowID(windowID))
        }

        return true
    }

    // MARK: - 内部辅助方法

    public static func isSystemAction(_ title: String) -> Bool {
        WindowMenuActionFilter.isSystemAction(title)
    }

    private static func findWindowMenu(in appElement: AXUIElement) -> AXUIElement? {
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef as! AXUIElement? else {
            return nil
        }
        AXUIElementSetMessagingTimeout(menuBar, 0.05)

        var menuBarItemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &menuBarItemsRef) == .success,
              let menuBarItems = menuBarItemsRef as? [AXUIElement] else {
            return nil
        }

        // 1. 优先按菜单标题关键词匹配
        for item in menuBarItems {
            AXUIElementSetMessagingTimeout(item, 0.05)
            var titleRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
            let rawTitle = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lower = rawTitle.lowercased()
            if windowMenuKeywords.contains(lower) || lower.contains("window") || lower.contains("窗口") || lower.contains("視窗") {
                return item
            }
        }

        // 2. 启发式兜底：检查子菜单中是否包含最小化/缩放等窗口固有动作
        for item in menuBarItems {
            AXUIElementSetMessagingTimeout(item, 0.05)
            if containsWindowActions(in: item) {
                return item
            }
        }

        return nil
    }

    private static func containsWindowActions(in menuBarItem: AXUIElement) -> Bool {
        guard let subMenu = getSubMenu(from: menuBarItem) else { return false }
        var subItemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(subMenu, kAXChildrenAttribute as CFString, &subItemsRef) == .success,
              let subItems = subItemsRef as? [AXUIElement] else {
            return false
        }
        for sub in subItems.prefix(6) {
            var titleRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(sub, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if title == "minimize" || title == "最小化" || title == "zoom" || title == "缩放" {
                return true
            }
        }
        return false
    }

    private static func getSubMenu(from menuBarItem: AXUIElement) -> AXUIElement? {
        var subMenuRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarItem, kAXChildrenAttribute as CFString, &subMenuRef) == .success,
              let subMenus = subMenuRef as? [AXUIElement] else {
            return nil
        }
        for sub in subMenus {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(sub, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == (kAXMenuRole as String) {
                return sub
            }
        }
        return subMenus.first
    }

    private static func hasSubmenu(_ element: AXUIElement) -> Bool {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], !children.isEmpty else {
            return false
        }
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == (kAXMenuRole as String) {
                return true
            }
        }
        return false
    }

    private static func fetchTabsFromAXWindows(appElement: AXUIElement, pid: pid_t) -> [BrowserTabItem] {
        AXUIElementSetMessagingTimeout(appElement, 0.05)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let elements = rawWindows as? [AXUIElement] else {
            return []
        }

        var tabs: [BrowserTabItem] = []
        for (index, elem) in elements.enumerated() {
            AXUIElementSetMessagingTimeout(elem, 0.05)
            var titleRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { continue }

            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role != (kAXWindowRole as String) {
                continue
            }

            var isMainRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(elem, kAXMainAttribute as CFString, &isMainRef)
            let isMain = (isMainRef as? Bool) ?? false

            tabs.append(BrowserTabItem(
                pid: pid,
                windowID: 0,
                tabIndex: index + 1,
                title: title,
                url: "",
                isActive: isMain
            ))
        }
        return tabs
    }
}



