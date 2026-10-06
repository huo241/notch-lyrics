<div align="center">

# Notch Lyrics

**把跟随时间滚动的歌词，放进 MacBook 的刘海。**

基于 [Boring Notch](https://github.com/TheBoredTeam/boring.notch) 的分支，补上了真正的歌词面板，并把展开后的刘海分成「播放控制」和「歌词」两栏。

[English](README.md) | 简体中文 | [Español](README.es.md)

<!-- 徽章 -->
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black.svg)](#环境要求)
[![Fork of](https://img.shields.io/badge/fork%20of-TheBoredTeam%2Fboring.notch-orange.svg)](https://github.com/TheBoredTeam/boring.notch)
[![Release](https://img.shields.io/github/v/release/huo241/notch-lyrics?include_prereleases&sort=semver)](https://github.com/huo241/notch-lyrics/releases)
[![Downloads](https://img.shields.io/github/downloads/huo241/notch-lyrics/total)](https://github.com/huo241/notch-lyrics/releases)
[![Stars](https://img.shields.io/github/stars/huo241/notch-lyrics?style=flat)](https://github.com/huo241/notch-lyrics/stargazers)
[![Issues](https://img.shields.io/github/issues/huo241/notch-lyrics)](https://github.com/huo241/notch-lyrics/issues)

<!-- 快捷按钮 -->
[![下载](https://img.shields.io/badge/⬇%20下载-DMG-2ea44f?style=for-the-badge)](https://github.com/huo241/notch-lyrics/releases/latest)
[![Star](https://img.shields.io/badge/⭐%20点个%20Star-yellow?style=for-the-badge)](https://github.com/huo241/notch-lyrics/stargazers)
[![反馈](https://img.shields.io/badge/🐞%20反馈问题-red?style=for-the-badge)](https://github.com/huo241/notch-lyrics/issues)
[![原项目](https://img.shields.io/badge/⬆%20原项目-boring.notch-lightgrey?style=for-the-badge)](https://github.com/TheBoredTeam/boring.notch)

</div>

---

## 为什么会有这个分支

Boring Notch 本来就有歌词开关，但它**永远只显示一行字**——时间轴数据在送到屏幕之前就被丢掉了。打开开关的效果，只是一行文字随着播放换内容。

这个分支修好了数据链路和显示方式：

| | 原版 | 本分支 |
|---|---|---|
| 歌词显示 | 一行，不滚动 | **5 行滚动窗口，当前行高亮** |
| 时间轴来源 | 被丢弃 | **LRCLIB 的 LRC 时间戳** |
| 无时间轴歌词 | 按纯文本显示 | 显示为静态文字块——**不伪造同步** |
| 请求方式 | 只用 `/api/search` | **先 `/api/get` 精确匹配，再退回 `/api/search`** |
| 布局 | 全部堆在左侧 | **左边播放详情，右边歌词** |
| 重复请求 | 每次重新拉取 | **按曲目缓存** |
| 切歌 | 前一首的迟到响应会覆盖新歌 | **已加防护** |

顺带修掉了几个上游就存在的 bug，见[本分支修复的问题](#本分支修复的问题)。

<div align="center">
  <img src="docs/assets/lyrics-demo.gif" alt="Notch Lyrics 效果" width="720" />
</div>

## 功能

Boring Notch 的全部功能，外加：

- 📜 **滚动歌词**——当前行高亮，上下行渐隐
- 🎯 **同步准确**——由 LRC 时间戳驱动，支持 `[offset:]` 偏移、一行多时间戳、字级标签
- 🧭 **诚实的降级**——只有纯文本时显示静态可滚动文字块，而不是假装同步；同时后台继续尝试获取带时间轴的版本
- 🪟 **分栏布局**——左边播放详情，右边歌词
- 🔁 **按曲目缓存**——同一首歌不重复请求
- 🛡️ **防竞态**——前一首歌的迟到响应不会覆盖当前歌曲

## 环境要求

- **macOS 14 Sonoma** 或更高
- Apple Silicon 或 Intel Mac
- 联网（歌词来自 LRCLIB）

## 安装

### 下载

到 [**Releases**](https://github.com/huo241/notch-lyrics/releases/latest) 下载最新的 `.dmg`，打开后把 **Notch Lyrics** 拖进 `/Applications`。

### 首次启动

这个构建是 **adhoc 签名**（没有 Apple 开发者账号），所以 macOS 会提示「未识别的开发者」。执行一次即可：

```bash
xattr -dr com.apple.quarantine "/Applications/Notch Lyrics.app"
```

然后正常打开。

> [!IMPORTANT]
> 因为签名身份和原版不同，macOS 会把它当作**另一个应用**：首次运行需要**重新授予辅助功能、自动化、日历权限**。

### 建议授予的权限

| 权限 | 用途 |
|---|---|
| **自动化**（Music） | 收藏、音量、播放状态 |
| **辅助功能** | 替换系统 HUD |
| **日历 / 提醒事项** | 日历标签页（可选） |
| **摄像头** | 镜像（可选） |

## 使用

1. 启动应用，刘海就变成了控制面板
2. 鼠标悬停，刘海展开
3. 用 Apple Music 或 Spotify 放首歌
4. **右侧面板显示歌词**，随播放滚动并高亮

### 关于歌词来源，有两点要知道

带时间轴的歌词来自 [LRCLIB](https://lrclib.net)：

- **Apple Music 自带歌词用不了。** AppleScript 的 `lyrics` 属性只返回纯文本；那种逐行时间轴是私有 API 渲染的，脚本取不到。所以**即使你用 Apple Music，动态歌词也依赖 LRCLIB**。
- **媒体控制器会影响封面和爱心。** 建议把 **设置 → 媒体控制器 → Now Playing**，这样流媒体曲目也能正常显示封面，爱心也能用。`Apple Music` 模式是通过 AppleScript 控制 Music.app，而它对流媒体（URL track）取不到封面。

## 从源码构建

### 前置条件

- **macOS 15.6** 或更高
- **Xcode 26** 或更高

### 步骤

```bash
git clone https://github.com/huo241/notch-lyrics.git
cd notch-lyrics
open boringNotch.xcodeproj
```

然后按 `Cmd + R`。

> [!NOTE]
> 项目会拉取 12 个 Swift Package 依赖。如果卡在 `Resolve Package Graph`，多半是网络问题——绕过网络的办法见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md#build-fails-at-resolve-package-graph)。

## 测试

```bash
xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

LRC 解析器（`boringNotch/helpers/LyricsParser.swift`）刻意不依赖任何东西，可以单独跑：

```bash
swiftc -O boringNotch/helpers/LyricsParser.swift your_test.swift -o t && ./t
```

## 本分支修复的问题

做歌词功能时发现的上游 bug，已在本分支修复：

| 修复 | 上游的症状 |
|---|---|
| `AppleScriptHelper` 改为串行执行 | `NSAppleScript` 非线程安全；并发调用会抛异常，或返回**上一次调用的结果** |
| 用 `AppleScriptBoolean` 读布尔值 | `favorited` 返回 `'true'`/`'fals'` 类型，而 `booleanValue` 对它恒为 `false`——爱心永远不亮 |
| 收藏写入加代次守卫 | 一次点击会触发多个并发写入，互相覆盖 |
| 爱心加意图守卫 | 陈旧的读回会撤销你的点击，导致下次点击方向相反 |

## 与原版的差异

- 应用名改为 **Notch Lyrics**；bundle ID 未变，所以原有设置继续有效。
- **已关闭自动更新。** 官方 appcast 发布的构建不含这些改动，跟着更新会把它们悄悄覆盖掉。如需启用，把 `boringNotch/Info.plist` 里的 `SUFeedURL` 指向你自己的更新源。

## 路线图

- [x] 带时间轴的滚动歌词
- [x] 播放控件 / 歌词分栏
- [x] 按曲目缓存歌词
- [ ] 逐字（卡拉OK）高亮
- [ ] 歌词字号与行数可调
- [ ] 歌词离线缓存

## 参与贡献

欢迎提 issue 和 PR——请到[这里](https://github.com/huo241/notch-lyrics/issues)。

本项目是分支，请先判断你的改动是否更适合提到[上游](https://github.com/TheBoredTeam/boring.notch)。与歌词无关的修复，通常提到上游更好。

上游的贡献规范见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致谢

这是个分支项目，绝大部分代码是别人的成果。

- **[The Bored Team](https://github.com/TheBoredTeam/boring.notch)**——原版 Boring Notch 和它的全部功能
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)**——macOS 15.4+ 的 Now Playing 来源
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)**——文件架功能的基础
- **[LRCLIB](https://lrclib.net)**——本分支依赖的歌词库
- 图标：[@maxtron95](https://github.com/maxtron95)
- 网站：[@himanshhhhuv](https://github.com/himanshhhhuv)

完整的第三方清单见 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)。

想支持原项目的话：**[给原作者买杯咖啡](https://www.ko-fi.com/alexander5015)**。

## 许可证

**GPL-3.0**，与原版一致——见 [LICENSE](LICENSE)。

按许可证要求，本分支随附完整源码并标注了修改内容。如果你要再分发，请保留许可证、源码和署名。
