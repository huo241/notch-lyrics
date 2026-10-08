# 刘海速记（Quick Note）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在刘海里提供速记面板：展开刘海 → 切到「速记」标签 → 打字 → 回车保存 → 内容成为 Apple 备忘录中的一条新笔记。

**Architecture:** 新增第三个标签（与「首页」「文件架」并列），独立占满刘海。备忘录交互收在一个 `NotesService` 里，经已有的 `AppleScriptHelper` 串行队列调用 AppleScript。窗口焦点由「状态驱动」——平时 `canBecomeKey = false`（现有行为不变），只在速记输入时临时为 `true`，退出时归还。

**Tech Stack:** Swift 5 / SwiftUI / AppKit（NSPanel）/ AppleScript（经 `AppleScriptHelper`）/ Defaults（偏好存储）

**Spec:** `docs/superpowers/specs/2026-10-08-quick-note-design.md`

## Global Constraints

- 部署目标 macOS 14.0，Swift 5.0，`SWIFT_STRICT_CONCURRENCY = targeted`
- **新增 .swift 文件必须手工在 `boringNotch.xcodeproj/project.pbxproj` 四处登记**：PBXBuildFile、PBXFileReference、所属组 children、主 target 的 Sources。主目录 `boringNotch` 是普通 PBXGroup，不是同步组
- 所有 AppleScript 必须经 `AppleScriptHelper`（内部是串行队列；`NSAppleScript` 非线程安全，直接并发调用会返回上一次的结果）
- **文件夹必须用 ID 定位，不能用名字**：实测用户机器上有 3 个同名「Notes」文件夹分属不同账户（iCloud / Gmail / 谷歌）。用名字会写错地方
- **不代为创建文件夹**：用户没选就不写入
- 笔记标题取内容首行，需截断（Apple 备忘录的 `name` 属性即标题）
- 改 `boringNotch.entitlements` 会改变签名身份，用户所有权限需重新授权——此改动只在最后一个任务做，且需在 Release 说明中告知

## Review Focus

以下是最可能出问题、但设计文档未逐条规定的输入。每一条都在对应任务的测试步骤里固定下来。

1. **文件夹列表含特殊字符或很长** — 用户有「500-food and drink」「OC 世界观」这类名字。列表 UI 必须能完整显示且不截断到无法区分，选择后回填的 ID 必须能原样传回 AppleScript（引号、反斜杠转义）
2. **内容含引号、换行、反斜杠、emoji** — 用户笔记里就有「师父说"阳痿烟"」这类引号。这些字符拼进 AppleScript 字符串会破坏语法，必须转义，否则写入失败或截断
3. **备忘录未运行 / 首次启动延迟** — AppleScript 会拉起 Notes.app，首次可能耗时数秒。不能因此让 UI 卡住或误报失败
4. **写入失败后内容不能丢** — 用户可能写了很长一段。失败时必须保留编辑器内容并允许重试，绝不能清空
5. **焦点必须可靠归还** — 切换标签、收起刘海、Esc、点外部、保存后，五条路径都要归还键盘。任一路径遗漏会把用户键盘锁在刘海里

---

## Task 1: 备忘录服务（NotesService）

**Files:**
- Create: `boringNotch/helpers/NotesService.swift`
- Modify: `boringNotch.xcodeproj/project.pbxproj`（注册新文件）
- Test: `/tmp/notes_service_test.swift`（临时脚本，跑完即删——仓库无测试 target）

**Interfaces:**
- Consumes: `AppleScriptHelper.execute(_:) async throws -> NSAppleEventDescriptor?`（已存在）
- Produces:
  ```swift
  struct NoteFolder: Equatable {
      let id: String      // x-coredata://<UUID>/ICFolder/pN
      let name: String
      let account: String // 账户名，用于区分同名文件夹
  }

  enum NotesError: Error {
      case notAuthorized
      case noFolders
      case scriptFailed(String)
  }

  final class NotesService {
      static let shared: NotesService
      func listFolders() async throws -> [NoteFolder]
      func createNote(title: String, body: String, in folderID: String) async throws
  }
  ```

- [ ] **Step 1: 写失败的测试**

创建 `/tmp/notes_transfer_test.swift`。它**编译真实的服务代码**（不是副本），做法与验证 `LyricsParser` 时相同——把服务和它的依赖一并喂给 `swiftc`：

```swift
import Foundation

var failures = 0
func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { print("  ✅ \(name)") } else { print("  ❌ \(name) \(detail)"); failures += 1 }
}

print("=== AppleScript 字符串转义 ===")
check("普通文本不变", NotesService.escapeForAppleScript("hello") == "hello")
check("引号被转义", NotesService.escapeForAppleScript("说\"你好\"") == "说\\\"你好\\\"")
check("反斜杠被转义", NotesService.escapeForAppleScript("a\\b") == "a\\\\b")
check("换行保留", NotesService.escapeForAppleScript("a\nb") == "a\nb")
check("中文不变", NotesService.escapeForAppleScript("师父以前是不吸烟的") == "师父以前是不吸烟的")
check("emoji 不变", NotesService.escapeForAppleScript("😀") == "😀")
check("引号+反斜杠组合", NotesService.escapeForAppleScript("\"\\") == "\\\"\\\\")

print("")
print(failures == 0 ? "全部通过 ✅" : "失败 \(failures) 项 ❌")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd /Users/Zhuanz/ZCodeProject/boring.notch
swiftc -O boringNotch/helpers/AppleScriptHelper.swift \
         boringNotch/helpers/NotesService.swift \
         /tmp/notes_transfer_test.swift -o /tmp/nstest 2>&1 | head -10
```
Expected: **编译失败** — `NotesService.swift` 尚不存在（`error: no such file or directory`），或存在但无 `escapeForAppleScript`（`error: type 'NotesService' has no member`）。

- [ ] **Step 3: 实现 `NotesService`**

创建 `boringNotch/helpers/NotesService.swift`。**文件顶部只 import Foundation**（`AppleScriptHelper` 亦然），这样它能被独立编译验证，不牵扯 SwiftUI/AppKit。

要点：

- `listFolders()`：遍历 `folders`，对每个取 `id`、`name`、以及 `container` 的 `name`（账户名）。返回时**过滤掉「Recently Deleted」**（不可写入）。用 `\u{1F}`（单元分隔符）作字段分隔、`\u{1E}` 作记录分隔，避免与文件夹名冲突。

  用于解析的 AppleScript：
  ```applescript
  tell application "Notes"
      set out to ""
      repeat with f in folders
          try
              set out to out & (id of f) & "\u{1F}" & (name of f) & "\u{1F}" & (name of (container of f)) & "\u{1E}"
          end try
      end repeat
      return out
  end tell
  ```

- `createNote(title:body:in:)`：用 `escapeForAppleScript` 处理 title 与 body，按 **ID** 定位：
  ```applescript
  tell application "Notes"
      set f to first folder whose id is "<folderID>"
      make new note at f with properties {name:"<title>", body:"<body>"}
  end tell
  ```

- 错误映射：AppleScript 返回含 `Not authorized` → `.notAuthorized`；空列表 → `.noFolders`；其余异常 → `.scriptFailed(...)`

- `escapeForAppleScript(_:)` 必须是 **`static func` 且不能是 `private`**（测试脚本从模块外调用它，签名 `static func escapeForAppleScript(_ s: String) -> String`）

- [ ] **Step 4: 运行测试，确认通过**

```bash
cd /Users/Zhuanz/ZCodeProject/boring.notch
swiftc -O boringNotch/helpers/AppleScriptHelper.swift \
         boringNotch/helpers/NotesService.swift \
         /tmp/notes_transfer_test.swift -o /tmp/nstest 2>&1 | head -10 && /tmp/nstest
```
Expected: `全部通过 ✅`（7 项断言）。`NotesService` 必须只 import Foundation 才能这样编——若引入了 AppKit/SwiftUI，这一步会暴露出来。

- [ ] **Step 5: 真机验证 AppleScript 片段**

先验证只读的那段：

```bash
osascript -e 'tell application "Notes" to return name of every folder' | head -c 200
```
Expected: 返回文件夹名列表

再验证**含特殊字符的内容能完整写入**（Review Focus 第 2 条）。这段会在 `__plan_char_test__` 名下创建、读回、再删除，不留痕迹：

```bash
# 取一个可写文件夹的 ID
FID=$(osascript -e 'tell application "Notes"
  repeat with f in folders
    if (name of f) is not "Recently Deleted" then return id of f
  end repeat
end tell')

# 用「转义后」的字符串创建，再读回比对
osascript <<EOF
tell application "Notes"
    set f to first folder whose id is "$FID"
    make new note at f with properties {name:"__plan_char_test__", body:"说\"你好\" 和 \\反斜杠\\ 以及 emoji 😀"}
    return plaintext of (first note whose name is "__plan_char_test__")
end tell
EOF
```
Expected: 输出包含 `说"你好"`、`\反斜杠\`、`😀` —— **三者都完整**，未被截断或转义错误。

删除测试笔记（注意备忘录的删除是移到「Recently Deleted」，需在那里再删一次）：

```bash
osascript -e 'tell application "Notes" to delete (every note whose name is "__plan_char_test__")'
osascript -e 'tell application "Notes"
  set f to first folder whose name is "Recently Deleted"
  try
    delete (first note of f whose name is "__plan_char_test__")
  end try
end tell'
```

- [ ] **Step 6: 注册到 Xcode 工程**

在 `project.pbxproj` 四处加入 `NotesService.swift`：PBXBuildFile、PBXFileReference、`helpers` 组 children、主 target Sources。锚点用已有的 `AppleScriptHelper.swift` 四项。改完运行 `plutil -lint boringNotch.xcodeproj/project.pbxproj`。

- [ ] **Step 7: 编译**

Run: `xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch -configuration Release -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -allowProvisioningUpdates 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add boringNotch/helpers/NotesService.swift boringNotch.xcodeproj/project.pbxproj
git commit -m "feat(quicknote): add NotesService for reading folders and creating notes"
```

---

## Task 2: 新增速记标签与占位视图

**Files:**
- Modify: `boringNotch/enums/generic.swift`（`NotchViews` 加 case）
- Modify: `boringNotch/components/Tabs/TabSelectionView.swift`（tabs 数组加一项）
- Modify: `boringNotch/ContentView.swift`（渲染分支加 case）
- Create: `boringNotch/components/QuickNote/QuickNoteView.swift`
- Modify: `boringNotch.xcodeproj/project.pbxproj`（注册新文件）

**Interfaces:**
- Consumes: `NotchViews`（`enums/generic.swift`）、`BoringViewCoordinator.currentView`
- Produces: `QuickNoteView: View` — 本任务先建占位版本，Task 4 填充实际内容

- [ ] **Step 1: 加枚举 case**

`boringNotch/enums/generic.swift` 的 `NotchViews`：
```swift
public enum NotchViews {
    case home
    case shelf
    case quickNote
}
```

- [ ] **Step 2: 加标签项**

`boringNotch/components/Tabs/TabSelectionView.swift` 的 `tabs` 数组：
```swift
let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Note", icon: "square.and.pencil", view: .quickNote)
]
```

- [ ] **Step 3: 建占位视图**

创建 `boringNotch/components/QuickNote/QuickNoteView.swift`：
```swift
import SwiftUI

struct QuickNoteView: View {
    var body: some View {
        Text("载入中…")
            .foregroundStyle(.gray)
    }
}
```

- [ ] **Step 4: 接进渲染分支**

`boringNotch/ContentView.swift` 的 `switch coordinator.currentView`：
```swift
case .home:
    NotchHomeView(albumArtNamespace: albumArtNamespace)
case .shelf:
    ShelfView()
case .quickNote:
    QuickNoteView()
```

- [ ] **Step 5: 注册新文件并编译**

在 `project.pbxproj` 四处登记 `QuickNoteView.swift`（锚点用 `NotchHomeView.swift` 的四项，注意其 FileReference 行含 `fileEncoding = 4`）。然后：

Run: `xcodebuild build ... 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 人工验证标签可切换**

装到本机，展开刘海，点击顶部第三个图标。
Expected: 右栏（或整屏）显示「载入中…」，点击另外两个图标能切回。

- [ ] **Step 7: Commit**

```bash
git add boringNotch/enums/generic.swift boringNotch/components/Tabs/TabSelectionView.swift boringNotch/ContentView.swift boringNotch/components/QuickNote/QuickNoteView.swift boringNotch.xcodeproj/project.pbxproj
git commit -m "feat(quicknote): add third tab with placeholder view"
```

---

## Task 3: 状态驱动的窗口焦点

**Files:**
- Modify: `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`（**app 实际使用的窗口类**）
- Modify: `boringNotch/BoringViewCoordinator.swift`（发布焦点意图）

> 注意：`BoringNotchWindow.swift` 里的同名类**从未被实例化**（`boringNotchApp.swift` 只创建 `BoringNotchSkyLightWindow`），是死代码。本任务不改它——改了不生效，徒增噪音。

**Interfaces:**
- Consumes: `BoringViewCoordinator`（单例，`ObservableObject`）
- Produces:
  ```swift
  // BoringViewCoordinator 新增
  @Published var quickNoteWantsFocus: Bool   // true = 速记编辑器请求键盘
  ```

- [ ] **Step 1: 在协调器里加焦点意图**

`boringNotch/BoringViewCoordinator.swift` 加一个 `@Published` 属性：
```swift
/// Set by the quick-note editor while it holds the keyboard. Never true when
/// another tab is showing — the notch must not steal focus by default.
@Published var quickNoteWantsFocus: Bool = false
```

- [ ] **Step 2: 窗口改为订阅该状态**

两个窗口类的 `canBecomeKey` / `canBecomeMain` 改为读协调器。因为 `canBecomeKey` 是计算属性、会被 AppKit 反复查询，直接读单例即可，无需订阅：

```swift
override var canBecomeKey: Bool { BoringViewCoordinator.shared.quickNoteWantsFocus }
override var canBecomeMain: Bool { BoringViewCoordinator.shared.quickNoteWantsFocus }
```

`BoringNotchSkyLightWindow.swift:112-113` 处改。

- [ ] **Step 3: 编译**

Run: `xcodebuild build ... 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 人工验证默认行为未变**

装到本机（**此时不要进入速记标签**），确认：
- 刘海仍能 hover 展开/收起
- 点击刘海不会抢走当前应用的键盘焦点（在文本编辑器里打字，焦点不被夺走）
Expected: 与改动前完全一致

- [ ] **Step 5: Commit**

```bash
git add boringNotch/BoringViewCoordinator.swift boringNotch/components/Notch/BoringNotchSkyLightWindow.swift boringNotch/components/Notch/BoringNotchWindow.swift
git commit -m "feat(quicknote): make window key-acceptance state-driven, off by default"
```

---

## Task 4: 速记界面与保存流程

**Files:**
- Modify: `boringNotch/components/QuickNote/QuickNoteView.swift`（替换占位实现）
- Modify: `boringNotch/models/Constants.swift`（存文件夹 ID）
- Modify: `boringNotch.xcodeproj/project.pbxproj`（无需改动，文件已注册）

**Interfaces:**
- Consumes: `NotesService.shared.listFolders()`、`NotesService.shared.createNote(title:body:in:)`、`NoteFolder`、`NotesError`（Task 1）；`BoringViewCoordinator.quickNoteWantsFocus`（Task 3）
- Produces: `QuickNoteView` 完整实现

- [ ] **Step 1: 加偏好项**

`boringNotch/models/Constants.swift`：
```swift
// MARK: Quick note
/// Chosen Notes folder, stored by ID: several accounts can each hold a folder
/// with the same name, so the name alone does not identify one.
static let quickNoteFolderID = Key<String>("quickNoteFolderID", default: "")
static let quickNoteFolderLabel = Key<String>("quickNoteFolderLabel", default: "")
```

`quickNoteFolderLabel` 存「名称 · 账户」供界面显示（如 `Notes · iCloud`）。

- [ ] **Step 2: 实现视图 —— 四种状态**

`QuickNoteView` 按状态渲染：

```
加载中        → ProgressView
无权限        → 提示文字 + 「打开系统设置」按钮
未选文件夹    → 列出 NoteFolder（显示 "名称 · 账户"），点击即选中并记住
已配置        → 编辑器 + 保存按钮 + 当前目标显示
```

要点：
- 编辑器用 `TextEditor`（多行），`onSubmit` 不适用于多行，故**保存用按钮 + 快捷键**（`.keyboardShortcut(.return, modifiers: .command)`，避免 Enter 与换行冲突）
- 编辑器获得焦点时才把 `coordinator.quickNoteWantsFocus` 置 `true`；用 `@FocusState` 跟踪
- 保存成功后清空编辑器并短暂显示成功提示
- **保存失败时绝不清空编辑器**，显示错误并允许重试

- [ ] **Step 3: 实现焦点归还（五条路径）**

在 `QuickNoteView` 及其宿主上确保以下时机把 `quickNoteWantsFocus` 置回 `false`：

1. `onDisappear`（切换标签或收起刘海）
2. 保存成功之后
3. 按 Esc（`.onExitCommand`）
4. 编辑器失焦（`@FocusState` 变为 false）
5. 应用失去激活（订阅 `NSApplication.didResignActiveNotification`）

- [ ] **Step 4: 编译**

Run: `xcodebuild build ... 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 人工端到端验证**

装到本机，依次确认：

| 场景 | 期望 |
| --- | --- |
| 首次进入速记标签 | 显示无权限提示（entitlements 尚未加 Notes，此为 Task 5 前的预期状态）|
| 切走再切回 | 状态保持一致，不崩溃 |
| 在编辑器里打中文 | 输入法候选窗正常 |

- [ ] **Step 6: Commit**

```bash
git add boringNotch/components/QuickNote/QuickNoteView.swift boringNotch/models/Constants.swift
git commit -m "feat(quicknote): editor UI with folder picker and focus handover"
```

---

## Task 5: 授予备忘录访问权限

**Files:**
- Modify: `boringNotch/boringNotch.entitlements`

**Interfaces:**
- Consumes: 无
- Produces: 应用获得向备忘录发送 Apple Events 的资格

- [ ] **Step 1: 加 entitlements 条目**

在 `boringNotch/boringNotch.entitlements` 的 `com.apple.security.temporary-exception.apple-events` 数组加入 `com.apple.Notes`：

```xml
<key>com.apple.security.temporary-exception.apple-events</key>
<array>
    <string>com.spotify.client</string>
    <string>com.apple.Music</string>
    <string>com.apple.Notes</string>
</array>
```

- [ ] **Step 2: 验证 plist 合法**

Run: `plutil -lint boringNotch/boringNotch.entitlements`
Expected: `OK`

- [ ] **Step 3: 编译并确认 entitlements 已进产物**

Run: `xcodebuild build ... 2>&1 | tail -3`
然后：
```bash
codesign -d --entitlements - "<DerivedData>/Build/Products/Release/Notch Lyrics.app" 2>&1 | grep -c "com.apple.Notes"
```
Expected: `1`

- [ ] **Step 4: 装到本机并授权**

装到 `/Applications`（重签流程见 TROUBLESHOOTING.md）。首次进入速记标签时 macOS 会弹「"Notch Lyrics"想要控制"备忘录"」——允许。

Expected: 弹出授权框；允许后文件夹列表出现

- [ ] **Step 5: 端到端验证**

| 操作 | 期望 |
| --- | --- |
| 选择「Notes · iCloud」 | 记住选择 |
| 输入「测试\n第二行」并保存 | 提示成功，编辑器清空 |
| 打开备忘录应用查看 | 在 iCloud 的 Notes 里出现一条同名笔记 |
| 检查落点 | 不是 Gmail / 谷歌 那两个同名文件夹 |

- [ ] **Step 6: 验证内容含特殊字符**

再存一条内容为 `说"你好" 和 \反斜杠\ 以及 emoji 😀` 的笔记，确认写入后内容**完整未截断**。
Expected: 备忘录中显示完整字符串

- [ ] **Step 7: 验证焦点五路径**

逐条确认键盘焦点都能归还：切换标签、收起刘海、按 Esc、点刘海外部、保存后。
Expected: 每次焦点都回到之前的应用

- [ ] **Step 8: 清理验证数据**

删除验证期间创建的所有测试笔记（**注意：备忘录的删除是移到「Recently Deleted」，需在那里再删一次才彻底**）：

```bash
osascript -e 'tell application "Notes" to delete (every note whose name contains "测试")'
```
再到「Recently Deleted」中删除同名条目。

- [ ] **Step 9: Commit**

```bash
git add boringNotch/boringNotch.entitlements
git commit -m "feat(quicknote): request Apple Events access to Notes"
```

---

## Task 6: 文档与发布

**Files:**
- Modify: `README.md`、`README.zh-CN.md`、`README.es.md`
- Modify: `TROUBLESHOOTING.md`
- Modify: `boringNotch.xcodeproj/project.pbxproj`（版本号）

**Interfaces:**
- Consumes: 前五个任务的全部产出
- Produces: 无代码接口

- [ ] **Step 1: 三语 README 加入功能说明**

在功能列表加入速记条目，说明：入口是顶部第三个标签、内容保存到用户选定的备忘录文件夹、需授予备忘录访问权限。

- [ ] **Step 2: TROUBLESHOOTING 加入权限重置说明**

新增一节，说明**升级会要求重新授予全部权限**（辅助功能、摄像头、日历、自动化），因为签名身份变了。给出恢复步骤。

- [ ] **Step 3: 版本号 +0.1**

`project.pbxproj` 中 `MARKETING_VERSION` 4 处改为 `2.7.5`，`CURRENT_PROJECT_VERSION` 4 处增加 1。

- [ ] **Step 4: 编译并验证版本**

Run: `xcodebuild build ... && defaults read "<产物>/Contents/Info.plist" CFBundleShortVersionString`
Expected: `2.7.5`

- [ ] **Step 5: 提交并推送**

```bash
git add -A
git commit -m "docs: document quick note, bump to 2.7.5"
git push origin main
```

- [ ] **Step 6: 发布 Release**

创建 `v2.7.5` tag 与 Release，上传 DMG。Release 说明中**必须**包含权限重置提示。
