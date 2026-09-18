Tungsten Edge v0.11.6 fixes its conflicts with two window managers, Rectangle and AeroSpace.

- **Fixed: With Tungsten Edge running, Rectangle's drag-to-snap did nothing when you dragged a window to a screen edge.**
- **Fixed: With AeroSpace or another tiling window manager, a maximized window's bottom edge jumped every second or two.** Tungsten Edge no longer tugs the window back and forth, so its bottom edge now rests quietly under the taskbar; to keep windows clear of the taskbar, add a bottom gap in AeroSpace's settings.

## Installing

**Already on 0.11.5?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.11.6 修掉了钨极和两款窗口管理工具（Rectangle、AeroSpace）的冲突。

- **修复：开着钨极时，Rectangle 拖动窗口到屏幕边缘自动吸附不起作用。**
- **修复：与 AeroSpace 等平铺式窗口管理工具一起用时，铺满屏幕的窗口底边每隔一两秒跳一下。**现在钨极不再和它来回拉扯，窗口底边会安静地停在 Dock 栏下面；想让窗口底部避开 Dock 栏，可以在 AeroSpace 的设置里给底部留出空隙。

## 安装

**已经在用 0.11.5？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
