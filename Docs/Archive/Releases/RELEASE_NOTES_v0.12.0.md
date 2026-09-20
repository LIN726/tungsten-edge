Starting with Tungsten Edge v0.12.0, you set the taskbar height by dragging, and several cases where apps stayed on the taskbar after quitting are fixed.

- **Taskbar height is now set by dragging:** press on either end of the taskbar or on a divider and drag up or down. The Taskbar Size menu has been removed; your current height is kept after upgrading.
- **Fixed: Some apps (such as Books, Clash Verge and Ice) left an icon or running dot on the taskbar after quitting or moving to the background.**
- **Fixed: Cards kept resizing when a web page changed its title repeatedly; menu bar apps (such as LaunchOS) bounced when their icon was clicked.**
- **The taskbar and the drawer icon are now centered as one group.**
- **The multi-display menu is renamed Single/Multi-Display Mode.**

## Installing

**Already on 0.11.6?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

本版起钨极 Dock 栏高度改为拖动调节，并修复若干应用退出后仍留在 Dock 栏上的问题。

- **Dock 栏高度改为拖动调节：**在条两端或分隔处按住上下拖动即可，原菜单中的「Dock 栏大小」已移除；升级后保持原有高度。
- **修复：部分应用（如图书、Clash Verge、Ice）退出或转入后台后，Dock 栏上仍残留图标或运行点。**
- **修复：网页频繁改标题时窗口卡反复伸缩；菜单栏应用（如 LaunchOS）点击图标时弹跳。**
- **Dock 栏与抽屉图标整体居中。**
- **多屏菜单更名为「单/多屏模式」。**

## 安装

**已经在用 0.11.6？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
