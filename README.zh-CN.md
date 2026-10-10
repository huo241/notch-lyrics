<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Notch Lyrics icon">

# Notch Lyrics

**滚动的歌词、天气和速记，都放进 MacBook 的刘海。**

> **Notch Lyrics 是 Boring Notch 的修改版**，后者是一个更早的 GPL-3.0 项目。
> 自 **2026 年 10 月 6 日**起独立开发，与原作者无隶属关系，亦未获其背书。
> 来源与完整改动清单见 [NOTICE](NOTICE)。

[English](README.md) | 简体中文 | [Español](README.es.md)

<!-- 徽章 -->
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black.svg)](#环境要求)
[![Release](https://img.shields.io/github/v/release/huo241/notch-lyrics?include_prereleases&sort=semver)](https://github.com/huo241/notch-lyrics/releases)
[![Downloads](https://img.shields.io/github/downloads/huo241/notch-lyrics/total)](https://github.com/huo241/notch-lyrics/releases)
[![Stars](https://img.shields.io/github/stars/huo241/notch-lyrics?style=flat)](https://github.com/huo241/notch-lyrics/stargazers)
[![Issues](https://img.shields.io/github/issues/huo241/notch-lyrics)](https://github.com/huo241/notch-lyrics/issues)

<!-- 快捷按钮 -->
[![下载](https://img.shields.io/badge/⬇%20下载-DMG-2ea44f?style=for-the-badge)](https://github.com/huo241/notch-lyrics/releases/latest)
[![Star](https://img.shields.io/badge/⭐%20点个%20Star-yellow?style=for-the-badge)](https://github.com/huo241/notch-lyrics/stargazers)
[![反馈](https://img.shields.io/badge/🐞%20反馈问题-red?style=for-the-badge)](https://github.com/huo241/notch-lyrics/issues)

</div>

---

## 1.0 更新了什么

这是这个应用不再顶着别人的身份的一版。从工程、target、scheme、Bundle ID、XPC 助手到 CI，
每一层现在都叫 Notch Lyrics；歌词查询是重建而不是打补丁；更新通道也换成了本仓库自己的签名源。
完整说明见 [`docs/releases/1.0.0.zh-CN.md`](docs/releases/1.0.0.zh-CN.md)。

| | |
|---|---|
| 🪪 **有了自己的身份** | target / scheme / Bundle ID / XPC 助手以及整条 CI 流水线全部改名为 Notch Lyrics——包括撤掉那个「发版到别处」的任务。 |
| 🔍 **那些「本来就没有」的歌词** | LRCLIB 的精确匹配接口对时长的容差只有**两秒**。现在会退到不带时长的查询、再退到本地打分的搜索；标题里的括号后缀、破折号尾巴都先剥掉。 |
| 🎯 **不再匹配错歌** | 搜索结果会跟正在播放的曲目打分比对，低于阈值的一律丢掉——宁可什么都不显示，也不要显示错的那首。 |
| ▶️ **当前行跟着播放填充** | 当前歌词行从暗到亮擦过去，用它自己的时长作分母，并且以文字自身实测宽度为基准。 |
| ✍️ **便签可以存进备忘录或 Obsidian** | 便签面板自己选目标；选中的库以 security-scoped bookmark 记住，**不新增 entitlement**。 |
| 🔄 **自己的更新通道** | Sparkle 查本仓库的更新源，验为本项目生成的密钥。 |
| 🏷️ **一个说谎的开关** | 歌词开关原本写着「在艺术家名下方」——那个位置早就不存在了，它控制的是打开刘海后右侧的面板。已改名，中文语言包也终于有了真正的翻译。 |

## 三个标签页，一个刘海

同一个盒子、同一个尺寸，不会有布局意外——刘海是一块共用的画布，每个标签页只是它不同的一面。

| 标签页 | 是什么 |
|---|---|
| 🎵 **歌词** | 左边播放详情，右边 5 行滚动歌词 |
| 🌤️ **天气** | 把天空画进刘海，配逐小时曲线和一周预报 |
| ✍️ **速记** | 一块写进备忘录的便签板 |

### 🎵 真的会滚动的歌词

歌词区**过去永远只显示一行字**——时间轴数据在送到屏幕之前就被丢掉了。打开歌词的效果，只是一行文字随着播放换内容。

这一版把数据链路和显示方式都重做了：

| | 原来 | 现在 |
|---|---|---|
| 歌词显示 | 一行，不滚动 | **5 行滚动窗口，当前行高亮** |
| 时间轴来源 | 被丢弃 | **LRCLIB 的 LRC 时间戳** |
| 无时间轴歌词 | 按纯文本显示 | 显示为静态文字块——**不伪造同步** |
| 请求方式 | 只用 `/api/search` | **先 `/api/get` 精确匹配，再退回 `/api/search`** |
| 布局 | 全部堆在左侧 | **左边播放详情，右边歌词** |
| 重复请求 | 每次重新拉取 | **按曲目缓存** |
| 切歌 | 前一首的迟到响应会覆盖新歌 | **已加防护** |

具体实现上：

- 🎯 **同步准确**——由 LRC 时间戳驱动，每 100 毫秒校准一次，换行落在鼓点前后约 100 毫秒内。支持 `[offset:]` 偏移、一行多时间戳、字级标签。
- 🧭 **诚实的降级**——只有纯文本时显示静态可滚动文字块，而不是假装同步；同时后台继续尝试获取带时间轴的版本。
- 🔁 **按曲目缓存**——同一首歌不重复请求。
- 🛡️ **防竞态**——前一首歌的迟到响应不会覆盖当前歌曲。

<div align="center">
  <img src="docs/assets/lyrics-demo.gif" alt="Notch Lyrics 效果" width="720" />
</div>

### 🌤️ 天气，不用申请 Key

- **实况天气**，来自 [Open-Meteo](https://open-meteo.com)——免费、免 Key。
- **逐小时曲线**——温度用样条曲线画，下面压着降水概率的柱状条。
- **7 天预报**——每天的高低温，配一条日照长度条，能看出白昼长短。
- **会变的天空**——背景配色跟着天气代码和昼夜走，雨天的样子不会长得像晴天。动画背景可以关掉。
- **哪儿都能搜**——地理编码走 [Photon](https://photon.komoot.io)（OpenStreetMap），`苏州市`、`Suzhou`、`淳安县`、`Tokyo` 都能定位；县、区一级也行，不只是大城市。手动选的城市永远优先于自动判断。
- **定位不弹窗**——默认走 IP 查询（`ipwho.is`，`ipinfo.io` 兜底），结果会缓存，不必每次启动都重新定位。

### ✍️ 一句话，落进备忘录

- **打字，回车**——内容写进你指定的备忘录文件夹。第一次在刘海里选一次文件夹，之后想改，点工具栏上的文件夹标签就行。
- **格式留得住**——加粗 / 斜体 / 下划线 / 删除线，每个按钮自己显示当前状态。
- **草稿不归视图管**——草稿存放在标签页之外，所以收起刘海（悬停离开、Esc、滑动、点外部）都不会把你正在写的东西清掉。
- **写失败不会吞字**——给你报错和一个重试按钮，而不是悄无声息。
- **兼容中文输入法**——组合输入不会被中途打断，中文词的头一个字不会再消失。

<div align="center">
  <img src="docs/assets/weather-quicknote-demo.gif" alt="天气页与速记" width="720" />
</div>

## 环境要求

- **macOS 14 Sonoma** 或更高
- Apple Silicon 或 Intel Mac
- 联网（歌词来自 LRCLIB，天气来自 Open-Meteo）

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
> 因为不是经过公证的正式签名，macOS 会在它替换旧版本时把它当作**另一个应用**：首次运行需要**重新授予辅助功能、自动化、日历权限**。

### 建议授予的权限

| 权限 | 用途 |
|---|---|
| **自动化**（Music） | 收藏、音量、播放状态 |
| **自动化**（Notes） | 速记——把内容写进你的文件夹 |
| **辅助功能** | 替换系统 HUD |
| **日历 / 提醒事项** | 日历标签页（可选） |
| **摄像头** | 镜像（可选） |

## 使用

1. 启动应用，刘海就变成了控制面板
2. 鼠标悬停，刘海展开
3. 在顶部切换标签页：**歌词**、**天气**、**速记**
4. 用 Apple Music 或 Spotify 放首歌——**右侧面板显示歌词**，随播放滚动并高亮

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
open NotchLyrics.xcodeproj
```

然后按 `Cmd + R`。

> [!NOTE]
> 项目会拉取 12 个 Swift Package 依赖。如果卡在 `Resolve Package Graph`，多半是网络问题——绕过网络的办法见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md#build-fails-at-resolve-package-graph)。

## 测试

```bash
xcodebuild build -project NotchLyrics.xcodeproj -scheme NotchLyrics \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

LRC 解析器（`NotchLyrics/helpers/LyricsParser.swift`）刻意不依赖任何东西，可以单独跑：

```bash
swiftc -O NotchLyrics/helpers/LyricsParser.swift your_test.swift -o t && ./t
```

## 顺带修掉的老问题

做歌词功能时冒出来的一些 bug，一并在此修掉：

| 修复 | 原来的症状 |
|---|---|
| `AppleScriptHelper` 改为串行执行 | `NSAppleScript` 非线程安全；并发调用会抛异常，或返回**上一次调用的结果** |
| 用 `AppleScriptBoolean` 读布尔值 | `favorited` 返回 `'true'`/`'fals'` 类型，而 `booleanValue` 对它恒为 `false`——爱心永远不亮 |
| 收藏写入加代次守卫 | 一次点击会触发多个并发写入，互相覆盖 |
| 爱心加意图守卫 | 陈旧的读回会撤销你的点击，导致下次点击方向相反 |
| AppleScript 脚本加 5 秒超时 | 一条等不到回复的 Apple Event 会把脚本串行队列永久占死，之后所有脚本都在后面排队——整个面板冻结 |
| 播放状态自动恢复 | 隔夜或睡眠之后 `com.apple.Music.playerInfo` 静默断流，而代码从不主动重读状态：点播放音乐确实响了，图标和歌词却永远停在旧曲目 |

## 本项目的变化

- 应用名为 **Notch Lyrics**，并使用自己的 bundle ID（`blog.snappy.notchlyrics`）。macOS 把它当作独立应用，旧版本的设置不会带过来。
- **自动更新已启用**，指向本仓库自己的签名更新源（`updater/appcast.xml`）；发版都在本仓库进行。
- 窗口阴影那次尝试已经彻底作废——窗口恢复原来的宽度，也不再有任何阴影相关的设置项。

## 路线图

- [x] 带时间轴的滚动歌词
- [x] 播放控件 / 歌词分栏
- [x] 按曲目缓存歌词
- [x] 天气页（支持自由搜索城市）
- [x] 速记（直接存入备忘录）
- [x] 整行进度填充
- [ ] 逐字（卡拉OK）高亮
- [ ] 歌词字号与行数可调
- [ ] 歌词离线缓存

## 参与贡献

欢迎提 issue 和 PR——请到[这里](https://github.com/huo241/notch-lyrics/issues)。改动适合提到哪里，[CONTRIBUTING.md](CONTRIBUTING.md) 里有分流说明。

## 致谢

Notch Lyrics 是一个**踩在巨人的肩膀上做出来的项目**——几乎没有哪一行是从零开始的。
托着它的是这些项目：

- **[The Bored Team](https://github.com/TheBoredTeam/boring.notch)**——本项目起步所基于的代码库
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)**——macOS 15.4+ 的 Now Playing 来源
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)**——文件架功能的基础
- **[LRCLIB](https://lrclib.net)**——歌词数据来源
- **[Open-Meteo](https://open-meteo.com)**——天气数据，免 Key
- **[Photon](https://photon.komoot.io)**（OpenStreetMap）——城市地理编码

完整的第三方清单见 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)。

还要感谢 **[Ech0](https://github.com/lin-snow/Ech0)** 社区——项目的作者们和使用者们，
感谢你们给予我的陪伴和鼓励。

> 「两个人总比一个人好……若是跌倒，这人可以扶起他的同伴。」
> ——传道书 4:9–10

## 许可证

**GPL-3.0**——见 [LICENSE](LICENSE)。

按许可证要求，本项目随附完整源码并标注了修改内容。如果你要再分发，请保留许可证、源码和署名。
