import AppKit
import SwiftUI

/// 某个窗口下的所有 Browser Tabs 弹窗列表
struct WindowTabPopupView: View {
    let bundleID: String
    let windowTitle: String
    let targetPID: pid_t?
    let initialTabs: [BrowserTabItem]
    let maxContentHeight: CGFloat
    let usesLiquidGlass: Bool
    var onSelectTab: (BrowserTabItem) -> Void = { _ in }
    var onClose: () -> Void = {}

    private let theme = DockThemeTokens.standard
    private let appIcon: NSImage?

    @State private var tabs: [BrowserTabItem]
    @State private var isLoading = false

    init(
        bundleID: String,
        windowTitle: String,
        targetPID: pid_t? = nil,
        initialTabs: [BrowserTabItem],
        maxContentHeight: CGFloat,
        usesLiquidGlass: Bool,
        onSelectTab: @escaping (BrowserTabItem) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.targetPID = targetPID
        self.initialTabs = initialTabs
        self.maxContentHeight = maxContentHeight
        self.usesLiquidGlass = usesLiquidGlass
        self.onSelectTab = onSelectTab
        self.onClose = onClose
        _tabs = State(initialValue: initialTabs)

        // 开窗时一次性解析图标并缓存，彻底杜绝渲染期在主线程频繁同步读盘/IPC
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            self.appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            self.appIcon = nil
        }
    }

    private var popupWidth: CGFloat { 380 }
    private var availableListHeight: CGFloat {
        min(max(180, maxContentHeight), 480)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景层：系统级毛玻璃（消除壁纸纹理干扰） + 高漫反射近白半透底板（保证黑字对比度与可读性）
            ZStack {
                DockVisualEffectView(material: .popover)

                // 88% 不透明度近白漫反射底板，兼顾通透感与高清晰度
                RoundedRectangle(cornerRadius: DockShape.panelCornerRadius, style: .continuous)
                    .fill(Color(nsColor: NSColor(deviceWhite: 0.97, alpha: 0.88)))

                // 顶部柔和白色微高光
                RoundedRectangle(cornerRadius: DockShape.panelCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: DockShape.panelCornerRadius, style: .continuous))

            VStack(spacing: 0) {
                headerView
                Divider()
                    .opacity(0.15)

                if tabs.isEmpty && isLoading {
                    loadingView
                } else if tabs.isEmpty {
                    emptyView
                } else {
                    tabListView
                }
            }
            .frame(width: popupWidth)
            .clipShape(RoundedRectangle(cornerRadius: DockShape.panelCornerRadius, style: .continuous))
        }
        .overlay {
            // 外边框精致勾勒
            RoundedRectangle(cornerRadius: DockShape.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        }
        .dockShadow(theme.popupShadow)
        .padding(PanelCoordinator.shadowPadding)
        .onExitCommand {
            onClose()
        }
        .task {
            if tabs.isEmpty {
                isLoading = true
                let fetched = await BrowserTabService.shared.fetchTabs(bundleID: bundleID, windowTitle: windowTitle, targetPID: targetPID)
                tabs = fetched
                isLoading = false
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 8) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
            }

            Text(String(format: String(localized: "Tabs · %d"), tabs.count))
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.popupCellLabel.color)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var tabListView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 2) {
                ForEach(tabs) { tab in
                    WindowTabRow(
                        tab: tab,
                        onSelect: { onSelectTab(tab) },
                        onClose: { closeTabItem(tab) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: availableListHeight)
    }

    private func closeTabItem(_ tab: BrowserTabItem) {
        Task {
            let success = await BrowserTabService.shared.closeTab(
                bundleID: bundleID,
                targetPID: tab.pid ?? targetPID,
                windowID: tab.windowID,
                tabIndex: tab.tabIndex
            )
            if success {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        tabs.removeAll(where: { $0.id == tab.id })
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text(String(localized: "Loading tabs..."))
                .font(.system(size: 11))
                .foregroundStyle(theme.popupCellLabel.color.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(theme.popupCellLabel.color.opacity(0.3))
            Text(String(localized: "No matching tabs"))
                .font(.system(size: 11))
                .foregroundStyle(theme.popupCellLabel.color.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

// MARK: - 独立标签页行视图（独立持有 Hover 状态，毫秒级响应，杜绝父视图整体重绘）

struct WindowTabRow: View {
    let tab: BrowserTabItem
    let onSelect: () -> Void
    let onClose: () -> Void

    private let theme = DockThemeTokens.standard
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // 当前活跃状态指示点 / 序号（保留清晰编号且严格对齐）
                HStack(spacing: 4) {
                    if tab.isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4.5, height: 4.5)
                            .shadow(color: Color.accentColor.opacity(0.6), radius: 2, y: 0.5)
                    } else {
                        Color.clear
                            .frame(width: 4.5, height: 4.5)
                    }
                    Text(verbatim: "\(tab.tabIndex)")
                        .font(.system(size: 9.5, weight: tab.isActive ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(tab.isActive ? Color.accentColor : theme.popupCellLabel.color.opacity(0.38))
                }
                .frame(width: 26, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .font(.system(size: 11.5, weight: tab.isActive ? .semibold : .regular))
                        .foregroundStyle(theme.popupCellLabel.color)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !tab.domainOrHost.isEmpty {
                        Text(tab.domainOrHost)
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.popupCellLabel.color.opacity(0.52))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 悬停时提供关闭按钮与回车确认图标
                if isHovered {
                    HStack(spacing: 6) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.popupCellLabel.color.opacity(0.45))
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Close Tab"))

                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.popupCellLabel.color.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isHovered
                            ? Color.black.opacity(0.065)
                            : (tab.isActive ? Color.accentColor.opacity(0.08) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
