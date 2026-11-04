# AGENTS.md — 工作区规则

## 一、目录边界（最重要）

**这个文件夹就是唯一的工作范围。**

```
/Users/Zhuanz/Development/notch-lyrics/
```

所有 Agent（包括我自己）在这个项目里干活时，必须遵守：

1. **只在这个目录内创建、修改、删除文件。** 不允许往 `~/Desktop`、`~/Downloads`、`~/Documents`、`/tmp` 以外的任何地方丢文件。
2. **临时文件只能放 `./.tmp/`**（已在 `.gitignore` 里）。不要用系统 `/tmp`，不要用家目录。
3. **不要新建平级的工作文件夹。** 需要分类就在本目录里建子目录，并且先说明用途。
4. **不要动本目录之外的任何东西**，除非用户当次明确要求。
5. 生成产物（截图、构建日志、导出文件）一律落在本目录内，并说明路径。

如果某件事必须在目录外操作（比如装 Homebrew 包、改系统设置），**先停下来告诉用户，得到同意再做**。

## 二、这个项目是什么

**Notch Lyrics** —— macOS 应用，把 MacBook 刘海区域当作控制面板。

- 五个标签页：媒体（LRCLIB + 网易云同步滚动）、暂存器、便签（写入 Apple Notes）、天气（Open-Meteo + Photon 地理编码）、统计（CPU / GPU / 内存 / 磁盘 / 网络）
- 语言 / 框架：Swift + SwiftUI
- 最低系统：macOS 14 Sonoma；**构建需要 macOS 15.6+ / Xcode 26+**
- 许可证：GPL-3.0
- 来源：fork 自 [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)，已重命名并重构（Bundle ID `blog.snappy.notchlyrics`）
- 上游仓库：https://github.com/huo241/notch-lyrics

## 三、代码结构

| 路径 | 内容 |
|---|---|
| `NotchLyrics/` | 主应用源码（SwiftUI 视图、设置页、歌词管线） |
| `NotchLyrics/helpers/LyricsParser.swift` | 独立的 LRC 解析器，无外部依赖 |
| `NotchLyrics.xcodeproj/` | Xcode 工程 |
| `NotchLyricsXPCHelper/` | XPC 辅助进程 target |
| `mediaremote-adapter/` | macOS 15.4+ 的 Now Playing 数据源 |
| `scripts/release.sh` | 打包发布脚本 |
| `Configuration/dmg/` | DMG 打包配置 |
| `docs/` | 文档与 release notes |
| `updater/appcast.xml` | 自动更新源 |

## 四、构建

```bash
# 命令行构建（在项目根目录）
xcodebuild -project NotchLyrics.xcodeproj -scheme NotchLyrics -configuration Debug build
```

日常开发直接用 Xcode 打开 `NotchLyrics.xcodeproj`。构建产物不要提交，`build/`、`DerivedData/`、`dist/` 都已在 `.gitignore` 里。

## 五、改代码时的约定

- **不要动 `LICENSE`、`NOTICE`、`THIRD_PARTY_LICENSES`。** 这是 GPL-3.0 项目的合规文件，改了就是许可问题。
- **可见文案走 String Catalog**，不要硬编码中文字面量。项目已经把 405 条文案收进目录了，新加文案要跟着进。
- **歌词同步的降级要诚实**：只有纯文本时显示静态文字块，不要伪造时间轴。
- 提交信息用中文或英文都行，但要说清改了什么、为什么。

## 六、Agent 自己该记的东西

写进 `.workbuddy-ai/memory/`，不要往仓库根目录散落笔记文件。

- `MEMORY.md` —— 长期有效的项目结论（架构决定、踩过的坑）
- `YYYY-MM-DD.md` —— 当天做了什么

`.workbuddy-ai/` 不会进 git，是本机专属的。

## 七、环境已知问题

本机到 GitHub 的网络不稳定，会间歇报 `CONNECT tunnel failed, response 502` 或 `Error in the HTTP2 framing layer`。

- 报错先**重试一次**，多数情况自己就好了。
- 拉整仓可用 `codeload.github.com/<owner>/<repo>/zip/refs/heads/main` 下 zip 兜底。
- SPM 依赖解析**慢**。解析时加 `-clonedSourcePackagesDirPath .tmp/spm`，缓存落在本地 `.tmp/` 里，不污染仓库。
- 依赖解析交给 Xcode 打开工程时自动做也行，不必在命令行硬等。

## 八、版本记录

当前 2.0.0。发版说明在 `docs/releases/`。
