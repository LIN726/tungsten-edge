Tungsten Edge v0.11.3 fixes a launch crash on macOS 14 and earlier — 0.11.0 through 0.11.2 quit the moment you opened them on those systems — and lets you drag an app straight from Finder onto the taskbar.

- **Fixed: On macOS 12 / 13 / 14, versions 0.11.0 through 0.11.2 crashed at launch and the taskbar never appeared.** This version fixes it. Auto-update cannot reach an app that will not open, so if you are affected, download this build directly and replace your copy.
- **New: Drag an app from Finder onto the taskbar and it stays there.** That is the same as ticking Keep in Dock, and it lands where you let go.
- **Improved: While you drag an app in, the icons part to show where it will land.** The cursor badge and the bar rim no longer flicker.

## Installing

**Already on 0.11.2 and able to open it?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.11.3 修好了 macOS 14 及更早系统上的启动闪退——0.11.0 到 0.11.2 在这些系统上一打开就退出——另外可以把应用从访达直接拖进任务条。

- **修复：macOS 12 / 13 / 14 上，0.11.0 到 0.11.2 一打开就闪退，任务条根本出不来。** 这一版修好了。打不开的应用也用不了自动更新，所以受影响的话请直接下载这一版安装，覆盖原来那个即可。
- **新增：可以把应用从访达直接拖到任务条上，它就会留在那儿。** 等同于勾上「在程序坞中保留」，落点就是你松手的位置。
- **优化：拖进来的过程中，图标会提前让开位置告诉你会落在哪儿。** 光标角标和栏边缘也不再闪。

## 安装

**已经在用 0.11.2 而且打得开？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
