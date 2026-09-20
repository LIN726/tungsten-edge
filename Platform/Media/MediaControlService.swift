import AppKit
import Foundation
import os.log

/// 当前正在播放的媒体信息快照
public struct MediaTrackInfo: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let isPlaying: Bool

    public init(title: String, artist: String, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
    }
}

/// 媒体与快捷控制中心（单例）：负责监听播放器广播并派发后台媒体控制指令
public final class MediaControlService: @unchecked Sendable {
    public static let shared = MediaControlService()
    private static let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "MediaControlService")

    // 支持的媒体应用 BundleID 集合
    public static let musicBundleID = "com.apple.Music"
    public static let spotifyBundleID = "com.spotify.client"
    public static let neteaseBundleID = "com.netease.163music"
    public static let qqMusicBundleID = "com.tencent.QQMusicMac"

    public static let supportedMediaBundles: Set<String> = [
        musicBundleID,
        spotifyBundleID,
        neteaseBundleID,
        qqMusicBundleID
    ]

    // 内存中缓存的实时播放信息（由系统 DistributedNotification 驱动，0 开销实时更新）
    private var trackInfoCache: [String: MediaTrackInfo] = [:]
    private let lock = NSLock()

    private init() {
        startListeningNotifications()
    }

    /// 判断特定应用是否为媒体播放类应用
    public func isMediaApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.supportedMediaBundles.contains(bundleID)
    }

    /// 获取特定媒体应用的实时播放信息快照（0ms 内存读取，不卡主线程）
    public func currentTrackInfo(for bundleID: String) -> MediaTrackInfo? {
        lock.lock()
        defer { lock.unlock() }
        return trackInfoCache[bundleID]
    }

    // MARK: - 播放控制动作（后台异步执行，不抢占前台焦点）

    /// 切换播放/暂停
    public func togglePlayPause(bundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch bundleID {
            case Self.musicBundleID:
                self?.runAppleScript("tell application \"Music\" to playpause")
            case Self.spotifyBundleID:
                self?.runAppleScript("tell application \"Spotify\" to playpause")
            default:
                // 网易云音乐及通用播放器：派发系统级媒体播放键
                Self.postMediaKey(Self.NX_KEYTYPE_PLAY)
            }
        }
    }

    /// 下一首
    public func nextTrack(bundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch bundleID {
            case Self.musicBundleID:
                self?.runAppleScript("tell application \"Music\" to next track")
            case Self.spotifyBundleID:
                self?.runAppleScript("tell application \"Spotify\" to next track")
            default:
                Self.postMediaKey(Self.NX_KEYTYPE_NEXT)
            }
        }
    }

    /// 上一首
    public func previousTrack(bundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch bundleID {
            case Self.musicBundleID:
                self?.runAppleScript("tell application \"Music\" to previous track")
            case Self.spotifyBundleID:
                self?.runAppleScript("tell application \"Spotify\" to previous track")
            default:
                Self.postMediaKey(Self.NX_KEYTYPE_PREVIOUS)
            }
        }
    }

    // MARK: - 浏览器通用无痕/隐身窗口支持

    // KeyCode: 'N' = 0x2D (45)
    private static let keyN: CGKeyCode = 0x2D

    /// 打开支持的浏览器的「新建无痕窗口」
    public func openPrivateWindow(bundleID: String) {
        // 若该浏览器已在运行，激活并向其投递 Cmd + Shift + N
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            runningApp.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let src = CGEventSource(stateID: .combinedSessionState)
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                for keyDown in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: Self.keyN, keyDown: keyDown)
                    e?.flags = flags
                    e?.postToPid(runningApp.processIdentifier)
                }
            }
        } else {
            // 未在运行，使用带参数命令行唤起
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            guard let appURL else { return }

            let config = NSWorkspace.OpenConfiguration()
            if bundleID == "com.apple.Safari" {
                // Safari 采用 AppleScript 直接创建专用窗口
                DispatchQueue.global(qos: .userInitiated).async {
                    let script = """
                    tell application id "com.apple.Safari"
                        activate
                        tell application "System Events" to tell process "Safari" to click menu item 3 of menu 3 of menu bar 1
                    end tell
                    """
                    let s = NSAppleScript(source: script)
                    s?.executeAndReturnError(nil)
                }
            } else {
                // Chromium 核心浏览器（Chrome, Edge, Brave, Arc 等）采用 --incognito 参数
                config.arguments = ["--incognito"]
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            }
        }
    }

    // MARK: - 内部辅助：媒体按键合成与系统广播

    private static let NX_KEYTYPE_PLAY: Int32 = 16
    private static let NX_KEYTYPE_NEXT: Int32 = 17
    private static let NX_KEYTYPE_PREVIOUS: Int32 = 18

    /// 模拟系统级原生媒体键硬件事件（无痛穿透任意媒体 App，包括网易云音乐、QQ音乐）
    private static func postMediaKey(_ key: Int32) {
        func doMediaKey(key: Int32, down: Bool) {
            let modifierFlags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            if let cgEvent = event?.cgEvent {
                cgEvent.post(tap: .cghidEventTap)
            }
        }
        doMediaKey(key: key, down: true)
        doMediaKey(key: key, down: false)
    }

    private func runAppleScript(_ scriptText: String) {
        var error: NSDictionary?
        let script = NSAppleScript(source: scriptText)
        script?.executeAndReturnError(&error)
        if let error {
            Self.logger.debug("Media AppleScript note: \(String(describing: error), privacy: .public)")
        }
    }

    private func startListeningNotifications() {
        let center = DistributedNotificationCenter.default()

        // 1. Apple Music 播放状态广播
        center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: nil
        ) { [weak self] note in
            self?.handlePlayerInfoNotification(note: note, bundleID: Self.musicBundleID)
        }

        // 2. Spotify 播放状态广播
        center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: nil
        ) { [weak self] note in
            self?.handlePlayerInfoNotification(note: note, bundleID: Self.spotifyBundleID)
        }
    }

    private func handlePlayerInfoNotification(note: Notification, bundleID: String) {
        guard let info = note.userInfo else { return }

        let rawState = (info["Player State"] as? String) ?? ""
        let isPlaying = rawState.caseInsensitiveCompare("Playing") == .orderedSame
        let title = (info["Name"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""

        lock.lock()
        defer { lock.unlock() }

        if isPlaying || !title.isEmpty {
            trackInfoCache[bundleID] = MediaTrackInfo(title: title, artist: artist, isPlaying: isPlaying)
        } else if rawState.caseInsensitiveCompare("Stopped") == .orderedSame {
            trackInfoCache.removeValue(forKey: bundleID)
        }
    }
}
