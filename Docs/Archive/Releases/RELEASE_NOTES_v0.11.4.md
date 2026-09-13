Tungsten Edge v0.11.4 fixes two Finder card problems, animates cards when a window title changes length, and gives the multi-display menu options clearer names.

- **Fixed: After you merge Finder windows into tabs, the taskbar no longer shows duplicate cards.** Switching between tabs no longer adds more.
- **Fixed: Finder windows that were already minimized before Tungsten Edge launched now get their own cards.** You no longer have to restore them from the Dock first.
- **Improved: When a window title gets longer or shorter, its card resizes smoothly and the cards beside it move along.** Clicking a card to restore a minimized window no longer delays the press feedback.
- **Changed: The options under “Show taskbar on” in the menu bar icon have clearer names.** They are now grouped into Single-display mode and Multi-display mode, and what they do has not changed.

## Installing

**Already on 0.11.3?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.11.4 修掉访达窗口卡的两个问题，卡片宽度变化加上了动画，多屏菜单的选项也换了更准确的名字。

- **修复：在访达里把几个窗口合并成标签页以后，Dock 栏上不会再多出重复的卡片。** 来回切标签页也不会越切越多。
- **修复：钨极启动之前就已经最小化的访达窗口，现在也会有自己的卡片。** 不用先去系统 Dock 里把它还原一次。
- **优化：窗口标题变长或变短时，卡片宽度会平滑变化，旁边的卡片跟着一起挪。** 点卡片还原最小化的窗口时，按下去的反馈也不再慢半拍。
- **变化：菜单栏图标里「钨极 Dock 栏显示在」下面的选项换了更准确的名字。** 分成「单屏模式」和「多屏模式」两组，功能本身没变。

## 安装

**已经在用 0.11.3？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
