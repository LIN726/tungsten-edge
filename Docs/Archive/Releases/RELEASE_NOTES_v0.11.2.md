Tungsten Edge v0.11.2 is polish and fixes: cards drop the part of their names they all repeat when one app has several windows, right-click menus no longer vanish under edge auto-hide, and the drawer opens more responsively.

- **Changed: When one app has several windows open, the cards now drop the part of the name they all repeat.**
- **Fixed: With edge auto-hide on, moving the pointer up to a right-click menu no longer takes the taskbar away — and the menu with it — before you can click an item.**
- **Improved: The drawer opens more responsively (its entrance animation is gone).** A card being dragged no longer flashes a ghost copy.
- **Fixed: Closing the window of an unresponsive app no longer freezes the taskbar for a few seconds.** A hole that could take Tungsten Edge down entirely is closed as well.

## Installing

**Already on 0.11.1?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.11.2 是几处打磨与修复：同一个应用开多个窗口时卡片名会去掉重复的部分，开着边缘自动隐藏时右键菜单不再自己消失，抽屉打开更跟手。

- **变化：同一个应用开多个窗口时，卡片名会自动去掉几张卡重复的那部分。**
- **修复：开着边缘自动隐藏时，右键菜单弹出来后往上移动鼠标，Dock 栏不会再连着菜单一起消失，菜单项点得到了。**
- **优化：抽屉打开更跟手（去掉了入场动画）。** 拖动卡片时也不再闪出重影。
- **修复：关掉一个没响应的应用的窗口时，Dock 栏不再跟着卡住几秒。** 另外堵掉了一处会让钨极直接退出的隐患。

## 安装

**已经在用 0.11.1？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
