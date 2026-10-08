# 刘海速记（Quick Note）— 设计文档

日期：2026-10-08
状态：待评审

## 1. 目标

在刘海里提供一块**速记面板**：展开刘海 → 切到「速记」标签 → 直接打字 → 回车保存 → 内容成为 Apple 备忘录里的一条新笔记。

用于随手记下一个想法，不必离开当前工作去打开备忘录应用。

## 2. 已确认的决策

| 议题 | 决定 |
| --- | --- |
| 存储模型 | 每次保存**新建一条**备忘录 |
| 焦点策略 | **点击输入区时才获取键盘焦点**；平时行为完全不变 |
| 保存时机 | **手动确认**（回车或保存按钮） |
| 存放位置 | **由用户选择**；首次使用时列出其备忘录文件夹供选，不代为新建 |
| 无权限时 | 显示提示 + 一键跳转到系统设置的授权页 |
| 入口 | 顶部标签栏新增第三个标签，与「首页」「文件架」并列 |
| 布局 | 独立标签，**占满刘海**（与「文件架」标签同级） |

## 3. 已实测验证的技术前提

以下均为真机实测结果，不是推断。

### 3.1 键盘输入可行（探针验证）

刘海窗口是 `.nonactivatingPanel` 且 `canBecomeKey = false`，这是上游的**故意设计**——让刘海永不抢焦点。

探针（临时把 `canBecomeKey` 改为可切换）验证结果：

| 验证项 | 结果 |
| --- | --- |
| 英文输入 | ✅ 正常 |
| **中文输入法** | ✅ **正常**（候选词窗口位置正确） |
| 焦点归还 | ✅ 正常，点击刘海外部后焦点回到原应用 |
| hover 展开/收起 | ✅ 无异常 |
| 手势 / 全屏检测 | ✅ 无异常 |
| CPU 占用 | ✅ 0%，无副作用 |

**结论**：按需切换 `canBecomeKey` 是可行的，不必改用独立窗口。

### 3.2 Apple 备忘录可写入

Apple **未提供** Notes 的公开 API（不同于日历/提醒事项的 EventKit），AppleScript 是唯一途径。实测：

| 操作 | 结果 | 耗时 |
| --- | --- | --- |
| 列出文件夹 | ✅ | 30ms |
| 创建笔记 | ✅ | — |
| 读取 | ✅ | 64ms |
| 追加 | ✅ | 168–322ms |

由于选择「每次新建一条」，走的是**创建**路径，不涉及追加延迟。

创建语法（已实测通过，含清理）。注意 `folder` 必须按 **ID** 定位，原因见 §3.3：

```applescript
tell application "Notes"
    set f to first folder whose id is "<用户选择的文件夹 ID>"
    make new note at f with properties {name:"<首行>", body:"<内容>"}
end tell
```

### 3.3 文件夹必须用 ID 定位，不能用名字

实测发现**多个账户可以各有一个同名文件夹**。用户机器上的实例：

| 名字 | 账户 | 笔记数 |
| --- | --- | --- |
| `Notes` | iCloud | 162 |
| `Notes` | hcworld02@gmail.com | 0 |
| `Notes` | 谷歌 | 0 |

用名字定位（`folder "Notes"`）存在**歧义**，可能写进错误账户的空文件夹。因此：

- 用户选择时读取的是**文件夹 ID**（`id of folder`），而非名字
- 写入时用 ID 构造引用，确保落到用户选中的那一个
- UI 显示时须**同时展示账户名**（如 `Notes · iCloud`），否则用户无法区分同名文件夹

文件夹 ID 形如 `x-coredata://<UUID>/ICFolder/p2`，是该文件夹的稳定标识。

### 3.4 沙箱权限要求

应用是沙箱化的，`entitlements` 中的 Apple Events 白名单**目前只有 Spotify 和 Music**，需要新增 `com.apple.Notes`：

```
com.apple.security.temporary-exception.apple-events = [
    com.spotify.client,
    com.apple.Music,
    com.apple.Notes        ← 新增
]
```

**重要影响**：修改 entitlements 会改变签名身份，macOS 会把应用视为新应用，**用户现有的全部权限需重新授权一次**（辅助功能、摄像头、日历、自动化）。这是本功能的主要成本，必须在发布说明中告知用户。

### 3.5 现有标签机制

`NotchViews` 枚举（`enums/generic.swift`）只有 `.home` / `.shelf`；标签定义在 `components/Tabs/TabSelectionView.swift` 的 `tabs` 数组；切换逻辑在 `BoringViewCoordinator.currentView`，渲染分支在 `ContentView.swift`。

新增标签只需在这四处各加一项。

## 4. 设计

### 4.1 新增标签

```
NotchViews 增加 case quickNote
tabs 数组增加 TabModel(label: "Note", icon: "square.and.pencil", view: .quickNote)
ContentView 的 switch 增加 case .quickNote: QuickNoteView()
```

### 4.2 焦点模型（核心改动）

`BoringNotchSkyLightWindow` 与 `BoringNotchWindow` 的 `canBecomeKey` 目前硬编码为 `false`。改为**由状态驱动**：

```
平时（未进入速记）      canBecomeKey = false    ← 现有行为，完全不改
进入速记并点击输入区    canBecomeKey = true     ← 且调用 makeKey()
离开速记 / 收起刘海     canBecomeKey = false    ← 并归还焦点
```

**焦点必须被可靠归还**，否则会锁住用户键盘。触发归还的时机：

- 切换到其他标签
- 刘海收起
- 保存后
- 按下 Esc
- 应用失去激活

这是本功能**风险最高**的部分，需要有明确的退出路径，不能出现「键盘被刘海吸住」的状态。

### 4.3 存储层

新增 `NotesService`，职责单一：与备忘录对话。

```
struct NoteFolder { let id: String; let name: String; let account: String }

listFolders() async -> [NoteFolder]              列出文件夹（含账户名，供用户区分同名）
createNote(title: String, body: String, in folderID: String) async throws
```

- 所有调用经 `AppleScriptHelper`（已是串行队列，避免与音乐/歌词的 AppleScript 争抢）
- 返回值区分成功 / 失败，供 UI 决定后续
- 不做缓存的必要：写入是低频操作

**不包含**：文件夹创建。用户没选文件夹就不写入。

### 4.4 首次使用流程

```
用户切到「速记」标签
  ↓
检查是否有 Apple Events 权限（尝试一次读文件夹列表）
  ↓
无权限 → 显示提示 + 「打开系统设置」按钮，不显示输入框
有权限但未选文件夹 → 列出文件夹供选择，记住选择
已配置 → 显示输入区
```

文件夹列表来自遍历 `folders`，对每个取 `id`、`name` 与 `container` 的账户名——
**三者都要**，因为同名文件夹必须靠账户和 ID 才能区分（§3.3）。

### 4.5 视图

`QuickNoteView`（新文件，`components/QuickNote/`）：

- 多行文本编辑器（`TextEditor` 或 `NSTextView`，需实测中文输入法在其中的表现）
- 顶部一行状态：当前目标文件夹 / 未配置提示
- 保存按钮 + 回车快捷键
- 保存后清空、显示短暂成功反馈
- 笔记标题取内容首行（截断），符合备忘录的常规表现

### 4.6 错误处理

| 情况 | 表现 |
| --- | --- |
| 无权限 | 提示 + 跳转按钮 |
| 未选文件夹 | 列出文件夹供选 |
| 备忘录未运行 | 自动启动（AppleScript 会拉起） |
| 写入失败/超时 | 保留输入内容，提示失败，可重试 |
| 内容为空 | 不写入，不提示（回车无效即可） |

**保留用户输入**是关键：写入失败时绝不能清空编辑器。

## 5. 涉及文件

| 文件 | 变更 |
| --- | --- |
| `enums/generic.swift` | `NotchViews` 增加 `.quickNote` |
| `components/Tabs/TabSelectionView.swift` | `tabs` 增加一项 |
| `ContentView.swift` | 渲染分支增加 case |
| `components/Notch/BoringNotchSkyLightWindow.swift` | `canBecomeKey` 改为状态驱动 |
| `components/Notch/BoringNotchWindow.swift` | 同上（保持一致） |
| `components/QuickNote/QuickNoteView.swift` | **新建**（同时新建 `components/QuickNote/` 目录，与 `components/Calendar/`、`components/Webcam/` 的组织方式一致） |
| `helpers/NotesService.swift` | **新建**，备忘录交互（放 `helpers/` 而非新建 `services/`，与现有 `AppleScriptHelper`、`MediaChecker` 等并列，避免为一个文件新增目录层级） |
| `models/Constants.swift` | 新增设置项（目标文件夹 **ID**，而非名字，避免同名歧义） |
| `boringNotch.entitlements` | 增加 `com.apple.Notes` |
| `boringNotch.xcodeproj/project.pbxproj` | 注册两个新文件 |

## 6. 非目标（YAGNI）

明确**不做**：

- 代为新建文件夹（用户明确否决）
- 自动保存 / 定时保存（已选手动确认）
- 笔记的读取、编辑、删除（只创建）
- Markdown / 富文本（纯文本即可）
- 麦克风语音输入
- 便签历史列表

## 7. 验证方式

1. **完整编译**：`xcodebuild ... -configuration Release`
2. **NotesService 隔离验证**：用临时脚本直接调 AppleScript，验证列出文件夹、创建笔记、错误分支
3. **端到端**：装到本机，走完整流程——未授权 → 授权 → 选文件夹 → 打字 → 保存 → 在备忘录里确认出现
4. **焦点回归**（最需要人工确认）：切换标签、收起刘海、按 Esc、点外部，四种路径都必须能归还键盘焦点

仓库无测试 target，验证依赖编译 + 脚本 + 人工确认。

## 8. 风险

| 风险 | 说明与应对 |
| --- | --- |
| **权限重置** | 改 entitlements 导致用户所有权限重新授权。必须在 Release 说明中明示 |
| **焦点锁死** | 若归还逻辑有遗漏，用户键盘会被刘海吸住。需要穷举退出路径并逐一验证 |
| **AppleScript 无 API 保证** | Apple 可随时改动 Notes 的脚本接口。功能失效时应优雅降级为提示，不崩溃 |
| 中文输入法在 TextEditor 中 | 探针验证的是 `TextField`；多行编辑器需重新验证 |
| 与音乐共用 AppleScript 队列 | 已串行化；但若 Notes 响应慢会影响音乐操作。实测 Notes 响应 30–64ms，影响可忽略 |

## 9. 待定

以下需要在实现时实测决定，不阻塞设计：

- 多行编辑器选 `TextEditor` 还是 `NSTextView`（取决于中文输入法表现）
- 保存后的反馈形式（短暂文字提示 vs 图标动画）
- 图标方案（`square.and.pencil` 是否与现有图标风格协调）
