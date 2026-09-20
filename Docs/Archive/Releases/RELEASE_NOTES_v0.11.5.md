Tungsten Edge v0.11.5 puts the Trash at the far right of the taskbar, and fixes the second-long wait after clicking a Finder window card.

- **New: The Trash joins the far right of the taskbar**, where you can view its contents, drag a file onto it to delete that file, or empty it — and turn it off from the menu bar menu.
- **Fixed: Clicking a Finder window card on the taskbar took about a second to minimize or restore the window.**
- **Fixed: The shelf discarded a file it could not read because of a missing privacy permission.**

## Installing

**Already on 0.11.4?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.11.5 在任务条最右端加入废纸篓，并修复了点击访达窗口卡时的延迟。

- **新增：任务条最右端加入废纸篓**，可查看其中内容、拖入文件删除、直接清倒，也可在菜单栏钨极菜单中关闭。
- **修复：点击任务条上的访达窗口卡时，收起与唤醒窗口约有一秒延迟。**
- **修复：中转站会将因权限受限而无法读取的文件误判为已删除并清除。**

## 安装

**已经在用 0.11.4？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
