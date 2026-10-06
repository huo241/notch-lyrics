# 动态歌词与开放刘海左右分栏 — 设计文档

日期：2026-10-06
状态：已实现并发布（Release 构建 + DMG 打包验证通过）

## 1. 背景与目标

用户已开启歌词显示（`enableLyrics = 1`），但实际效果是**一次只显示一句歌词、且不随时间滚动**，只是随着播放换字。同时用户提出希望重排开放刘海的布局：**左侧放歌曲详情与交互控件，右侧放歌词**。

本设计要达成的目标：

1. 开放刘海改为左右分栏：左栏 = 歌曲详情（封面、标题、艺人、进度条、控制键），右栏 = 歌词。
2. 歌词为**整行滚动 + 当前行高亮**的动态形式，跟随播放进度平滑滚动。
3. 在没有时间轴数据时，右栏降级为**静态多行歌词**（诚实展示，不假装同步）。
4. 不破坏现有功能：日历、摄像头、收起态、SneakPeek、设置项语义保持不变。

## 2. 现状与根因

"歌词不动态"不是单一缺陷，而是**三层问题叠加**。

### 2.1 数据链路层（根因）

`boringNotch/managers/MusicManager.swift`：

| 位置 | 问题 |
| --- | --- |
| `:344` `fetchLyricsIfAvailable` | 仅按 `enableLyrics` 与 `title` 非空做门槛 |
| `:390` | Apple Music 路径拿到原生歌词后**无条件执行 `syncedLyrics = []`**，主动丢弃时间轴 |
| `:443` | LRCLIB 路径 `let resolved = plain.isEmpty ? synced : plain` — **优先取纯文本**，即使 `syncedLyrics` 存在也被降级 |
| `:447` | 只有在 `plainLyrics` 为空时才解析 `syncedLyrics` |
| `:414` `fetchLyricsFromWeb` | 未发送 `User-Agent`；未处理 `429` / `Retry-After` |
| 无 | 无缓存，同一首歌反复请求；无竞态防护，切歌时旧响应会覆盖新歌歌词 |

### 2.2 渲染层

`boringNotch/components/Notch/NotchHomeView.swift:156-188`：单行 `TimelineView`（间隔 `0.25`）取 `lyricLine(at:)` 的返回值，交给 `MarqueeText` 并 `.lineLimit(1)`。**结构上只能显示一行，无列表、无滚动、无高亮**。

`MusicManager.lyricLine(at:)`（`:491`）只返回单个 `String`，即使有时间轴也只用于"换行"，不产出可用于滚动的索引。

### 2.3 布局层

`NotchHomeView.mainContent`（`:442`）是一条三元素 `HStack`：`MusicPlayerView` → 日历 → 摄像头。歌词被嵌在 `MusicControlsView.songInfo` 内，**没有独立容器**，因此无法放到右侧。

### 2.4 已实测确认的事实

- 用户当前 `mediaController = "Apple Music"`，播放源为 Music.app，因此走 **Apple Music 原生歌词路径**。
- AppleScript 的 `lyrics` 属性**只能返回纯文本**。Apple Music 那种带时间轴的逐行歌词由私有 API 渲染，脚本取不到。实测对当前曲目返回空字符串。
- LRCLIB **确实提供带时间轴的 `syncedLyrics`**（形如 `[00:29.36] 故事的小黃花`），实测对用户正在播放的曲目亦有收录。
- 结论：**动态歌词在 Apple Music 场景下实际依赖 LRCLIB 联网**。这是数据源限制，代码层面无法突破。

## 3. 环境与几何约束（实测）

| 项 | 值 |
| --- | --- |
| 屏幕逻辑分辨率 | 1512 × 982 |
| 物理刘海 | 约 189 × 32 pt，位于顶部正中，不可绘制 |
| 开放刘海 | 640 × 190 pt，**硬编码**于 `sizing/matters.swift:16`，用户不可调 |
| 刘海以下可用区 | 640 × 158 pt |

物理刘海仅占顶部 189×32，`y > 32` 以下整条 640 pt 均可自由布局，**左右分栏在几何上完全可行**。

用户当前配置（实测）：`enableLyrics = 1`、`showCalendar` 与 `showMirror` 均为默认 `false`（即**右半边当前是空的**）、控制键槽位为 `none / previous / playPause / next / favorite`（5 槽，工具栏 `maxWidth: .infinity` 居中分布）。

## 4. 已确认的决策

| 议题 | 决定 |
| --- | --- |
| 动态粒度 | 整行滚动 + 当前行高亮（不做逐字卡拉OK） |
| 刘海总宽 | **保持 640 pt 不变**，左 380 / 右 230 |
| 右栏归属 | **歌词优先**；无歌词时回退日历，再回退摄像头 |
| 无时间轴降级 | **静态多行歌词**，不滚动不高亮；同时后台再尝试获取带时间轴版本 |

## 5. 设计

### 5.1 布局层

`NotchHomeView.mainContent` 改为两栏：

```
HStack(spacing: 12) {
    MusicPlayerView()   // 固定 380 pt
    RightPane()         // 固定 230 pt
}
```

`RightPane` 优先级：**歌词 → 日历 → 摄像头**。保留 `showCalendar` / `showMirror` 现有开关语义，仅把它们从"并列"降为"回退"。

宽度不硬编码于视图，在 `sizing/matters.swift` 新增：

```swift
let musicPaneWidth: CGFloat = 380
let lyricsPaneWidth: CGFloat = 230
```

目的：防止上游若调整 `openNotchSize` 导致布局散架。

**同时移除** `MusicControlsView.songInfo` 中的内联歌词块（`NotchHomeView.swift:156-188`），避免歌词同时出现在左栏与右栏。已确认歌词仅在这 7 处出现，**SneakPeek（收起态）不涉及歌词**，故该移除不影响收起态。

注意：`MarqueeText` 本身不移除，它仍用于左栏的歌曲标题与艺人名。被移除的只是歌词那一段的 `MarqueeText` 用法——原先它承担"无时间轴时的单行滚动"，该职责改由 §5.3 的静态多行视图承接。当 `enableLyrics = false` 时，右栏不显示歌词（回退日历/摄像头），左栏行为与改动前一致。

`MusicControlsView` 内部使用 `GeometryReader`，收窄至 380 pt 后进度条与标题跑马灯自动适配，无需额外改动。

### 5.2 数据层（`MusicManager.swift`）

**a. 修正优先级**

LRCLIB 返回时优先解析 `syncedLyrics`，仅在无时间轴时回退 `plainLyrics`。Apple Music 路径拿到的文本先尝试按 LRC 解析；解析出 ≥2 个带时间戳的行则视为有时间轴，否则保留为静态文本，**不再无条件清空 `syncedLyrics`**。

**b. 匹配精度**

优先使用 `/api/get`（`track_name` + `artist_name` + `duration`），404 时回退 `/api/search`。

约束（来自 LRCLIB 官方文档）：`duration` 必须介于 1–3600 秒，且与库中记录相差 **±2 秒以内**，否则匹配失败。因此：

- 仅当 `songDuration >= 1 && songDuration <= 3600` 时才附带 `duration` 参数；
- 否则**省略该参数**继续调用 `/api/get`（该端点仅 `track_name` 与 `artist_name` 为必填），失败再走 `/api/search` 兜底。

调用顺序因此为：`/api/get`（带 duration，若时长有效）→ `/api/get`（不带 duration）→ `/api/search`。

**c. 合规**

- 请求附带 `User-Agent`，标识应用名与项目地址（LRCLIB 明确要求）。
- 遇 `429` 时读取 `Retry-After` 头并退避，不立即重试。注意：限流由边缘层实施，**响应体不保证是 JSON**，须以状态码为准，不可直接解析 body。

**d. 健壮性**

- **缓存**：以 `artist|title` 为键缓存解析结果（纯内存，上限约 50 条），避免同曲重复请求。
- **竞态防护**：记录发起请求时的 `lyricsTrackKey`，响应返回时若与当前曲目不符则丢弃。这修复了现有代码切歌时旧响应覆盖新歌歌词的缺陷。

**e. 解析器增强**（`parseLRC`）

- 支持一行多时间戳（`[00:12.00][01:20.00] 同一句`），展开为多条记录
- 支持毫秒位数为 1/2/3 位，以及无毫秒的 `[mm:ss]`
- 剥离字级标签 `<mm:ss.xx>`
- 跳过元数据标签（`[ar:]` `[ti:]` `[al:]` `[by:]` 等）
- 应用 `[offset:±ms]` 偏移（LRC 标准特性，影响时间对齐正确性）
- 按时间排序后返回

解析器抽为**纯函数**（输入字符串、输出列表），便于独立验证。

**f. 新增指针**

新增 `currentLyricIndex(at:) -> Int`，沿用现有二分查找逻辑，供滚动视图定位当前行。原 `lyricLine(at:)` 保留。

**g. 后台升级**

当仅有纯文本歌词时，除展示静态文本外，后台再向 LRCLIB 尝试获取带时间轴版本；成功则自动升级为滚动显示。

### 5.3 歌词视图（新文件 `components/Music/LyricsView.swift`）

独立组件 `ScrollingLyricsView`，与 `MusicVisualizer` 同目录：

- 显示**窗口 5 行**（当前行居中，上下各 2 行），详见下方修订说明
- 全部歌词行置于 `VStack`，整体按当前行 `offset` 位移，`.easeInOut(0.35)` 平滑滑动
- 上下边缘加渐变遮罩，实现淡出
- 当前行：白色、加粗、略放大；相邻 ±1 行：45% 透明度、0.9 倍缩放；±2 行：约 22% 透明度；更远行淡出至不可见
- 时间推演沿用现有 `TimelineView` 模式，间隔由 `0.25` 收紧至 `0.1`（0.25 意味着换行最多延迟 250 ms，歌词场景可感知）
- 当前行定位使用 `currentLyricIndex(at:)`

> **修订说明（相对 §4 的"3 行"）**：§4 记录的"3 行"决策是在**内联方案**下作出的，当时歌词位于歌曲标题下方，可用高度仅约 60–70 pt。歌词移至右栏后可用高度变为约 138 pt（按 640×190 减顶部安全区估算），副标题字号下每行约占 22 pt，故窗口扩大为 5 行（约 110 pt）以充分利用空间。此修订需在评审时确认。

### 5.4 状态与降级

| 情况 | 右栏显示 |
| --- | --- |
| 有时间轴 | 5 行滚动窗口 + 当前行高亮 |
| 仅纯文本 | 静态多行文字块（可查看），不假装同步；后台尝试升级 |
| 纯音乐（`instrumental == true`） | "纯音乐"提示 |
| 加载中 | "加载中…" |
| 确实无歌词 | "未找到歌词" |

### 5.5 视觉示意

```
现在：左栏塞满约 580pt，右侧空旷
┌──────────────────────────────────────────────────────────┐
│ [🏠][🗂]                              ⚙  79%  🔋         │
│  ┌──────┐   SPICY (feat. Myke Towers)                    │
│  │ 封面 │   Fronti & Brytiago                             │
│  │      │   ────────────────────────────────────────      │
│  └──────┘   2:25                              3:11       │
│                ⏪   ▶   ⏩   ♡                             │
└──────────────────────────────────────────────────────────┘

改后：左右分栏
┌──────────────────────────────────────────────────────────┐
│ [🏠][🗂]                              ⚙  79%  🔋         │
│  ┌──────┐   SPICY (feat. Myke…  │  從前從前 有個人愛妳很久  │
│  │ 封面 │   Fronti & Brytiago   │  但偏偏 風漸漸 把距離吹遠 │ ← 高亮
│  │      │   ──────────────      │  好不容易 又能再多愛一天  │ ← 渐隐
│  └──────┘   2:25      3:11      │                          │
│                ⏪  ▶  ⏩  ♡       │                          │
└──────────────────────────────────────────────────────────┘
        左栏 380pt                       右栏 230pt
```

## 6. 涉及文件

| 文件 | 变更 |
| --- | --- |
| `boringNotch/managers/MusicManager.swift` | 歌词优先级、`/api/get` 匹配、UA、429 退避、缓存、竞态防护、`currentLyricIndex(at:)`、`hasActiveTrack` |
| `boringNotch/helpers/LyricsParser.swift` | **新建**，无依赖的纯函数 LRC 解析器（便于独立验证） |
| `boringNotch/components/Music/LyricsView.swift` | **新建**，`ScrollingLyricsView` |
| `boringNotch/components/Notch/NotchHomeView.swift` | 两栏布局与 `secondaryPane`；移除内联歌词块 |
| `boringNotch/sizing/matters.swift` | 新增 `musicPaneWidth` / `secondaryPaneWidth` / `openNotchPaneSpacing` |
| `boringNotch.xcodeproj/project.pbxproj` | 注册两个新文件（主目录非同步组，必须手工登记） |

### 实现期间发现并修正的两点

1. **暂停不应隐藏歌词**：原计划用 `!isPlayerIdle` 判断"有曲目"，但 `isPlayerIdle` 会在停止播放 `waitInterval`（默认 3 秒）后变为 `true`，导致暂停几秒后歌词面板消失。改为新增 `hasActiveTrack`，只反映"是否有曲目"，与播放状态解耦。
2. **空右栏**：不可见时 `secondaryPane` 整体省略，而不是保留一块固定宽度的空白区域。

## 7. 非目标（YAGNI）

明确**不做**：

- 逐字卡拉 OK 高亮
- 歌词磁盘缓存
- 歌词字号 / 行数 / 位置的设置项（不新增设置项，复用 `enableLyrics`）
- 新建单元测试 target
- 与本次目标无关的重构

## 8. 验证方式

1. **真编译**：`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch build`（已确认 Xcode 26.4 可用）。
2. **解析器**：以 `LyricsParser` 纯函数为对象，用真实 LRC 样本（一行多时间戳、毫秒位数变体、元数据标签、字级标签、offset、乱序、边界）编译运行验证。**已执行，29 项断言全部通过**；脚本位于 `/tmp`，未进入工程。
3. **端到端对照**：播放实测曲目，确认右栏由"单行"变为"5 行滚动窗口 + 当前行高亮"。由于该曲目 LRCLIB 有 `syncedLyrics` 收录，修正优先级后即应呈现动态效果——这是一个可证伪的预测。**尚未执行：需要完整编译，受依赖下载阻塞（见下）。**

仓库当前**无任何测试 target**，CI 仅执行 build，故不依赖既有测试。

### 已验证 / 未验证

| 项 | 状态 |
| --- | --- |
| `LyricsParser` 行为（29 项断言） | ✅ 已编译运行通过 |
| `LyricsView` 类型检查（最小桩件） | ✅ 通过，零警告 |
| 歌词管线 async/网络代码类型检查 | ✅ 通过 |
| 全部改动文件语法检查 | ✅ 通过 |
| `project.pbxproj` 结构合法性 | ✅ `plutil -lint` OK |
| **完整工程编译** | ❌ **未执行**——SPM 依赖无法下载（见下方风险） |
| 运行时视觉效果 | ❌ 未验证（依赖完整编译） |

## 9. 风险与限制

| 风险 | 说明与应对 |
| --- | --- |
| 数据源天花板 | Apple Music 原生歌词无时间轴，动态歌词依赖 LRCLIB 联网。已在 §2.4 实测确认，属数据源限制 |
| 上游改尺寸 | `openNotchSize` 为硬编码；已抽常量降低耦合 |
| 匹配到翻唱/现场版 | `/api/get` 带 `duration` 可提升精度，但 `songDuration` 为 0 时无法使用该参数 |
| LRCLIB 限流 | 已实现 UA 标识与 `Retry-After` 退避；仍可能因网络不可用而降级为静态歌词 |
| 无自动化测试 | 仓库无测试 target，验证依赖编译 + 临时脚本 + 肉眼对照，回归防护弱 |
| **依赖下载阻塞完整编译** | 本机 SPM 无法下载 12 个依赖（仅 `Defaults` 有缓存），`xcodebuild` 在 `Resolve Package Graph` 阶段超时。代码经语法/类型检查与解析器实跑验证，但**尚未做过一次完整构建**。在有可用网络的环境（或已配好依赖的机器）上必须先跑通 `xcodebuild build` 再使用 |
