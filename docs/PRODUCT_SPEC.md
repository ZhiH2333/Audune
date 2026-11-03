# Audune — Product & Engineering Specification

> **文档版本：** 2.0  
> **更新日期：** 2026-10-24  
> **产品名称：** Audune  
> **平台：** macOS 原生桌面应用  
> **商业模式：** 免费、完全开源；无账号、无广告、无遥测  
> **当前开发分支：** `dev`（唯一允许的开发分支）  
> **目标：** 本文档是产品需求、架构边界、开发顺序、验收条件及 AI coding agent 行为规则的唯一产品规格来源之一。执行时同时遵循仓库根目录 `AGENTS.md`。

---

## 0. 给 Vibe Coding Agent 的执行说明

**不要一次性生成整个产品。** 先检查现有仓库，再执行 `docs/GITHUB_ISSUES.md` 中依赖最少的当前 Issue。每次只完成一个可验证的小阶段，保证项目随时能构建。遇到未验证的 macOS API、权限行为、窗口层级或音频问题时，先做 spike（最小技术验证），不能用假数据或占位行为冒充已完成的系统功能。

### 强制 Git 规则

1. **所有开发工作始终位于 `dev` 分支。** 开始操作前检查 `git status --short` 和 `git branch --show-current`。
2. 若当前不在 `dev` 且工作区干净、已有 `dev` 分支，可以切换到 `dev`；若工作区有未提交改动、切换可能丢失或覆盖工作，先停止并报告，不自行 stash、reset、discard 或覆盖用户改动。若没有 `dev`，只有在工作区干净时才从当前基线创建 `dev`。不得创建其他开发分支。
3. **禁止切换到 `main` 或其他分支继续开发；禁止 merge、rebase、reset --hard、force push，以及删除或覆盖用户已有的改动。**
4. **每完成一个 TODO 自动创建一次 Git commit。** TODO 指已批准计划或 GitHub Issue 中的一个可勾选任务项。该项实现完整且相关测试/检查通过后，无需再次询问用户，立即提交。通常每个 TODO 一个 commit；若多个子项在技术上无法独立构建或验证，应在计划阶段说明并合并为最小可独立验收单元，禁止囤积多个无关已完成 TODO。
5. 每次提交前检查 `git status --short` 和完整 staged diff，只暂存属于当前 TODO 的文件；绝不混入用户已有修改、无关文件、密钥、个人配置或构建产物。相关测试失败时，该 TODO 不算完成，不得提交。文件归属不明确时停止并询问。
6. 每个 commit message 必须严格符合格式：

   ```text
   :gitmoji: short-git-message
   ```

   示例：
   - `:sparkles: add system audio capture`
   - `:art: refine orbit visualization`
   - `:bug: fix audio tap cleanup`
   - `:white_check_mark: add analyzer unit tests`
   - `:memo: document audio capture permissions`

   只写一行；使用一个 gitmoji shortcode、一个空格和简短英文描述。不要添加 `feat:`、Issue 编号或其他前缀。**自动 commit，但绝不自动 push。** 若 Git hook 或提交失败，不得绕过检查；报告原因并停止。
7. 每次 TODO 提交后继续当前获批任务；最终复核分支仍是 `dev`，汇报各 TODO 的 commit hash/message、修改内容、构建/测试结果及未解决项。不得声称未实际运行的测试已经通过。

### 实施行为规则

- 先读本文件与 `AGENTS.md`，再检查项目结构、构建方式、工作区状态及当前分支。
- 尊重现有代码与项目约定；先理解再修改，不要无故重写、改名或删除现有模块。
- 只实现当前 Issue 及其必要依赖，不顺手加入未排期的歌词、壁纸、AI、云同步或高级粒子效果。
- 尽量使用 Apple 原生 API；不添加第三方依赖，除非能说明其必要性、许可证与维护成本。
- 不以伪造数据、随机波形或持续播放的假动画替代系统音频采集。若提供 Demo Mode，必须显式标记为 Demo，且默认关闭。
- 不请求麦克风权限，不保存或上传原始音频，不引入遥测、广告、登录或网络分析 SDK。
- UI、窗口层级、刘海定位及音频采集必须遵循公开 API；不得依赖私有 API、代码注入、无障碍权限滥用或系统文件修改——**唯一例外**为文档化的 Experimental Island Now Playing（MediaRemote / mediaremote-adapter，用户开关，默认关闭）。
- 发生构建错误时先读取完整错误并定位根因；不能靠关闭警告、删除测试或注释核心功能“修复”构建。
- 修改音频生命周期、权限、窗口层级或偏好键时，必须补充相应测试或手动验证说明。

---

## 1. 产品概述

Audune 是一款轻量、原生、可高度定制的 macOS 系统音乐可视化应用。它将 Mac 正在输出的声音转化为实时动态图形，并允许用户将图形放在四种不同的系统界面位置：

1. **Menu Bar（菜单栏）**：极小、常驻、低干扰的动态指标。
2. **Studio（可视化悬浮画布）**：完整尺寸、可拖动/缩放，可选择始终置顶。
3. **Island（刘海灵动岛式窗口）**：围绕带刘海 MacBook 的摄像头区域显示，收起时是紧凑音乐指示器，展开后呈现较完整控制面板。
4. **Desktop Magnet（桌面磁贴）**：普通层级的桌面小窗，能被其他常规应用窗口自然覆盖，不默认置顶。

四种形态**共享同一条音频捕获与分析管线**。显示形态是同一实时分析状态的不同呈现方式，不得为每个窗口重复创建音频捕获任务。

### 品牌方向

- 品牌名：**Audune**
- 建议短句：**Sound, in motion.**
- 关键词：克制、细腻、原生、可定制、低干扰、即时响应。
- 视觉建议：石墨黑、暖白、单一强调色；允许用户改色，避免默认紫色渐变、大卡片和过度玻璃拟态。
- 设计参照：CodeIsland 的刘海区域交互思路、Stats 的菜单栏模块与刷新控制思路；只研究交互模式，不复制代码、品牌、文案或美术资产。

### 产品原则

1. **音频真实**：图形必须来自实际系统输出音频，不以随机数模拟。
2. **同源多视图**：四种形态共用 Audio Engine 与 AudioSnapshot。
3. **轻量优先**：可见时流畅，不可见时停止或降低高频工作。
4. **原生优先**：使用 Swift、SwiftUI、AppKit、Core Audio 和 Accelerate。
5. **隐私优先**：只在本机实时分析，不录制、不上传、不追踪。
6. **渐进交付**：先证明音频链路，再做三种基础可视化；Island 与 Desktop Magnet 分阶段交付。
7. **可降级**：没有刘海的显示器仍可使用菜单栏和 Studio；不支持的窗口行为必须明确降级，而不是伪装成功。

---

## 2. 目标用户与关键场景

### 目标用户

- 希望菜单栏提供细微音乐反馈的 Mac 用户。
- 编程、学习、写作、设计或日常工作时，喜欢在屏幕一角展示音乐视觉的用户。
- 需要自定义界面尺寸、颜色、透明度、窗口层级和动画风格的用户。
- 偏好免费、开源、本地运行、不依赖账号的轻量桌面工具的用户。

### 核心用户故事

- 作为用户，我播放浏览器或音乐播放器的声音时，希望 Audune 能呈现随声音变化的图形，而不是只支持某一个播放器。
- 作为用户，我希望不打开大窗口，也能从菜单栏判断声音正在变化。
- 作为用户，我希望可视化悬浮在工作窗口上方，或改成普通层级让应用窗口遮住它。
- 作为带刘海 MacBook 用户，我希望在刘海附近看到一个收起/展开的音乐组件。
- 作为用户，我希望在桌面留白处放一个小型波形磁贴，不影响其他应用的窗口层级。
- 作为用户，我希望选择 Spectrum、Waveform、Orbit，并调整颜色、灵敏度与平滑度。
- 作为用户，我希望拒绝系统权限后仍能看见明确的解释和恢复路径。

---

## 3. 产品版本与范围控制

本文档描述 Audune 的目标产品形态，但代码必须按下面的阶段逐步实现。**产品规格完整不代表首个提交必须实现全部功能。**

### v0.1 — Core MVP

必须交付：
- 原生菜单栏应用及动态菜单栏可视化。
- Core Audio 系统输出音频捕获、权限状态和清理生命周期。
- 共用实时分析数据模型。
- 三种可视化：Spectrum、Waveform、Orbit。
- Studio 无标题栏窗口：拖动、缩放、显示/隐藏、始终置顶开关。
- 基本设置和持久化。
- 隐私说明、构建说明、单元测试和手动验收清单。

### v0.2 — Island

- 带刘海屏幕的检测和定位。
- 收起状态和展开状态的动画。
- 选定屏幕、悬停/点击行为、展开保持和收起控制。
- 无刘海显示器的清晰降级体验；默认不在不合适的区域强行覆盖系统 UI。

### v0.3 — Desktop Magnet

- 普通窗口层级的桌面磁贴。
- 可拖动、缩放、保存位置和大小。
- 默认不置顶，能被其他常规应用窗口覆盖。
- 多显示器变化后恢复到可见区域。

### Experimental — Island Now Playing（可选，默认关闭）

- **不属于 Core MVP。** 用户可在 Settings → Notch Island 开启「Show Now Playing when expanded」。
- Expanded / Pinned 显示系统 Now Playing：歌名、歌手、封面、可拖动进度条、上一曲 / 播放暂停 / 下一曲。
- Compact 仍只显示频谱侧翼，不显示曲名或封面。
- 技术路径：私有 `MediaRemote` 经 `mediaremote-adapter`（系统 `/usr/bin/perl` 旁路）读取；**不**使用分源 Apple Events / Automation。
- 明确限制：实验性；不可承诺 Mac App Store；系统升级可能导致短暂不可用；个别播放器 seek 可能降级为只读进度条。
- 开启/关闭 Now Playing **绝不** start/stop 系统音频 Process Tap；可视化与元数据相互独立。
- 仍禁止：SkyLight、CGSSpace、WindowServer 注入、无障碍伪装系统 UI、麦克风、遥测、持久化曲目历史或上传封面。

### Experimental — Zen Player + Network Lyrics（可选，默认关闭）

- **不属于 Core MVP。** Settings → Zen；也可从 Island Expanded 或菜单栏打开。
- Zen 默认以居中、可调整大小的普通窗口打开，不自动进入 macOS 全屏。窗口展示柔和模糊的封面底景、曲名/歌手、进度与 transport、克制且低不透明度的共享可视化；复用与 Island 同一份 `NowPlayingService` 与 `AudioSnapshot`。优先使用静态/低频动画并限制渲染更新频率，避免空闲时持续高功耗。
- Zen 窗口不自动隐藏 Island。用户主动切入 macOS 原生全屏时，临时隐藏 Island；退出全屏后恢复。
- **绝不** start/stop Process Tap；不用 SkyLight / CGSSpace。
- **联网歌词**（`fullscreen.lyricsNetworkEnabled`，默认 `false`）：关闭时零网络。开启后仅用 title / artist / 可选 album / duration 查询。自动来源模式并行探测国际 **LRCLIB**（HTTPS）及国内 **NetEase / QQ Music / Kugou**（公开检索接口；Kugou 仅接受明文 LRC），使用首个达到匹配质量门槛的结果；Settings 也可手动固定单一来源。不上传封面或 PCM；切歌/切换来源取消 in-flight；无结果/失败显示明确空态。架构参考 [LyricsX](https://github.com/ddddxxx/LyricsX) / LyricsKit，运行时不嵌入该库。
- 歌词区域以当前播放行居中，逐行跟随进度，并在上下方向渐隐和模糊；歌词内容变化时立即重新定位当前行。
- 实验性；不可承诺 Mac App Store；匹配失败可接受；国内 HTTP 源通过 Info.plist ATS 例外限定域名。

### v0.4+ — 其他播放器 / 视觉扩展

- 分源 Apple Events（Music/Spotify Automation）方案已从产品中移除；不以此替代上述 Experimental Now Playing。
- 专辑封面取色主题、本地 `.lrc` 导入、录制、动态桌面和高级视觉均不属于 Core MVP（联网歌词仅见上方 Experimental Zen）。

### 首版明确不做

- 独立音乐播放器、播放列表或媒体库。
- 专辑封面联动取色主题（Now Playing / Zen 仅展示系统已提供的封面字节，不做取色主题）。
- 桌面壁纸层、屏幕边缘灯效、屏幕保护程序。
- AI 功能、账号登录、远程配置、广告、遥测（Zen 联网歌词仅在用户显式开启时访问 LRCLIB / NetEase / QQ / Kugou）。
- 音频录制、直播、视频导出、听歌历史统计。
- 插件市场、脚本执行系统、复杂可视化编辑器。
- 要求用户安装虚拟音频驱动或第三方音频路由工具。

---

## 4. 显示形态规格

### 4.1 Menu Bar — 动态菜单栏

**目的：** 在极小空间中提供即时、可扫视的声音反馈，并成为所有功能的主要入口。

#### 菜单栏图形模式

首版至少支持：
- `Spectrum`：紧凑频谱柱。
- `Waveform`：单条波形。
- `Orbit`：紧凑环形/径向符号，必要时缩减细节以适应窄空间。
- `Minimal`：极简圆点/音量脉冲，可作为额外轻量样式；若会拖慢前三种模式，不得阻塞首版。

#### 交互

- 一个 Audune status item；不要为每根柱或每个组件创建独立菜单栏图标。
- 点击显示轻量控制面板/Popover；再次点击或按 Escape 可关闭。
- 面板显示捕获状态、当前模式、显示形态快捷入口、设置和退出。
- 动画图形不能抢走键盘焦点；面板需要正常支持键盘导航。
- 菜单栏绘制应使用独立的小尺寸渲染路径，避免每帧重建整个设置视图。
- 目标动画更新约 20–30 FPS；若系统限制或功耗策略要求更低帧率，可自适应降频。
- 菜单栏宽度由系统和用户决定；不能承诺固定图标排序。提醒用户系统原生支持的图标位置调整方式。
- 在较新 macOS 版本上，如果系统提供菜单栏项目显示/隐私开关，README 的 Troubleshooting 必须说明如何检查 Audune 是否允许显示。

#### 菜单栏验收

- 音频播放时图形明显响应，静音时回归基线。
- 浅色和深色菜单栏中都清晰可见。
- 菜单面板、模式切换、打开各显示形态、设置、退出均正常。
- 菜单栏更新不为每个音频帧触发昂贵 SwiftUI 全量刷新。

### 4.2 Studio — 完整悬浮画布

**目的：** 为三种视觉提供最完整展示，并允许用户把它放在工作窗口附近。

#### 窗口行为

- 无标题栏外观；可拖动、可调整大小；默认尺寸应能清楚显示图形。
- 窗口模式和 Spaces 行为分开设置，三选一，立即生效并持久化。切换时写回原来的 frame，不 `orderOut`，也不重新居中。
- On Desktop：公开 `CGWindowLevelForKey(.desktopIconWindow)`，低于普通窗口。`collectionBehavior` 只有 `canJoinAllSpaces`，不含 `fullScreenAuxiliary`。本 SDK 没有 `NSWindow.Level.desktop`。多 Space 是否真的生效必须在真机上记录；若桌面图标层不可见或收不到点击，再改用公开的 `.backstopMenu`。不用壁纸层 `.desktopWindow`。
- On Top：`.floating`，`isFloatingPanel = true`，`collectionBehavior` 为 `canJoinAllSpaces` 加 `fullScreenAuxiliary`。它不是全屏窗口，只作为辅助窗口出现在全屏 Space。离开全屏后仍留在普通桌面。这是默认模式。
- As Window：`.normal`，`isFloatingPanel = false`，`collectionBehavior` 为空。它留在自己的 Space，普通窗口和全屏应用都可以盖住它。
- 旧的 `studio.alwaysOnTop` 在没有 `studio.windowMode` 时迁移：`true` 为 On Top，`false` 为 As Window。保存时仍把 On Top 写成 `true`，其余写成 `false`。
- 关闭/隐藏 Studio 不停止音频捕获，也不关闭菜单栏应用。
- 记忆窗口位置、大小、所选可视化模式和窗口层级选项。
- Settings → Studio → Visualization size 单独控制可视化自身大小：Fixed size（默认，640 pt 宽 × Scale 25–200%，比例 16:10 / 4:3 / 1:1 / 2:1，居中，窗口小于它时等比缩小）或 Fill window（旧行为）。顶部有实时预览：外框是窗口、内框是可视化。改窗口大小不会改变 Fixed 模式下的可视化大小。键为 `studio.layout.mode/scale/aspect`；Island 不读取。
- Settings → Studio → Size 直接设置 Studio 窗口 **Width / Height（points，非物理像素）**，默认 640×400。拖动窗口边缘或 Reset Position and Size 后，设置值与 live frame 双向同步；拖动过程中不每帧回写以免抖动。AppKit 内部仍保留绝对硬底 360×240，以及默认最大 1600×1000 ∩ 当前屏 `visibleFrame`（用户不再配置 min/max 四滑条；旧键仅兼容读取）。宽高比不锁定。只作用于 Studio，不影响 Notch Island，也不写入 Visual Preset。
- 屏幕断开、分辨率变化、保存坐标在屏幕之外时，窗口恢复到当前可见屏幕。
- 画布鼠标穿透在 On Top、On Desktop、As Window 三种模式里始终开启，旧的关闭值不再恢复整窗命中。公开 API 没有按区域挖洞的鼠标遮罩，`NSView.hitTest` 返回 `nil` 只表示这个窗口不接收该事件，并不会把点击交给下层应用。`ignoresMouseEvents` 是整窗开关，所以可视化 `NSPanel` 忽略鼠标；控件放在同级（不是 child window）的交互 `NSPanel` 上，缩放则是四条 6 pt 的边缘 `NSPanel`，且只在允许缩放时存在。不用 `addChildWindow`，以免子窗口被抬到父窗口之上并破坏 On Desktop。不申请 Accessibility 或 Input Monitoring，也不另起高频轮询。交互面板只盖住真实控件或唤出区域，不盖住整块画布，因此按钮仍可点击，画布空白点由窗口服务器交给更下层的窗口。隐藏 Studio 时，交互面板和边缘面板 `orderOut`，不留下点击层。另一进程里更高的窗口仍可能先接到点击，这是窗口服务器的正常叠放，不是穿透失败。
- Studio 窗口始终透明。不绘制整窗背景、暗色遮罩、大卡片、毛玻璃、整窗矩形描边或窗口阴影。透明来自 `isOpaque = false` 和清除的窗口背景，不是把填充色调成接近桌面。
- 窗口里只保留当前可视化、底部一条按内容宽度排列的控件，以及一个约 28×22 pt 的拖动把手。底栏只有把手、三个可视化模式按钮和 Settings 按钮（无播放/暂停，不控制外部播放器）。底栏没有整条底板。按钮默认没有底色，只在悬停、按下时使用局部圆角底。所有详细参数都在单独的 Settings 窗口里（见下），Start/Stop 捕获与 Show/Hide Studio 在菜单栏弹窗。这些值立即保存，Reset 恢复默认。不铺窗口大小的底板。
- Settings 是独立的普通 `NSWindow`：titled、closable、miniaturizable、resizable，初始约 760×600 pt，最小约 640×480，层级 `.normal`，`collectionBehavior` 为空，`hidesOnDeactivate = false`。它不继承 Studio 的 On Desktop / On Top / As Window，也不随 Studio 隐藏。左侧是原生侧边栏，分类为 Startup、Appearance、Visualization、Studio、Notch Island：Visualization 页内切换 Spectrum / Waveform / Orbit；Studio 合并原 Layout 与 Window（预览、画布尺寸、窗模式、窗尺寸、控件显隐）。入口是 Studio 底栏的 Settings 和菜单栏弹窗的 Settings…。设置窗口不嵌入第二个实时 Studio 预览条；Studio 本身就是即时预览，布局页保留画布尺寸预览。
- 只有把手调用屏幕坐标的 `setFrameOrigin` 拖动。控件隐藏后仍保留把手矩形，隐藏只关闭命中。拖动在 `.eventTracking` 中读取鼠标屏幕位置；同一次按下还会用 local monitor 接住拖动事件。空白区域、按钮和设置滑块不拖动窗口。不使用 `performDrag(with:)` 或 `isMovableByWindowBackground`。`performDrag(with:)` 在这个无边框 nonactivating panel 上会立刻结束，并留下 `Window move completed without beginning`，窗口并不移动。
- 自动隐藏控件默认开启（`studio.window.autoHidesControls`）。关闭后控件保持显示。开启时，淡入约 200ms，指针离开后固定 3 秒再以约 250ms 淡出。Settings 没有隐藏延迟滑块。拖动把手的图标一直留在画布底部。模式和 Settings 这些按钮默认不显示，并以约 200ms 淡入；图标和文字带一层淡阴影。只有指针靠近把手或这些按钮约 40pt 内才出现；进入窗口的其他区域不会把它们叫出来。按钮已经显示时，指针移出约 120pt 后开始这 3 秒，期间指针回来会重新计时。不能靠悬停已经隐藏的按钮唤出。把手在按钮隐藏时仍然可以拖动窗口。鼠标按下或拖动时不隐藏。隐藏后的按钮不再接收点击；画布仍按原尺寸绘制。窗口隐藏或关闭时清掉指针、按下和菜单跟踪状态。显示定时器只看交互面板。系统开启 Reduce Motion 且“Follow system Reduce Motion”打开（默认）时，淡入淡出改为即时，3 秒延迟仍保留；也可以单独关闭淡入淡出。控件显隐不移动可视化，也不停止音频分析。
- 已保存的 `studio.cleanCanvas` 不再改变外观。保存偏好时清除该键。没有整块背景可恢复。
- Studio 的 Spectrum 和 Orbit 可选 8、12、16、24、32、48、64 根柱，默认 32。Spectrum 与 Orbit 各自保存柱数。柱数来自同一次 FFT 的 512 个 bin 幅度，按对数或线性分带聚合，不把菜单栏的 16 个值复制或插值成更多柱。宽于一个 bin 的柱对其 bin 取平均；窄于一个 bin 的低端柱读取其中心两侧真实 bin 的线性插值，因此相邻低端柱不会出现重复的值；最低一根柱不低于第一个 FFT bin（bin 0 不是频带）。Spectrum 可设置频率范围（最低 20–500 Hz、最高 2–20 kHz）、灵敏度（移动安静端的 dB 下限，默认下限 -60 dB）、振幅、邻柱平滑、攻击/释放（毫秒，按实际时间差计算，与帧率无关）和峰值保持（默认关闭；可设保持时间与下降速度）。色彩映射可选 Solid（Appearance 填充）、Frequency（按频带色相偏移）或 Amplitude（按柱高明暗）；峰值帽仍用描边色。静音闸门（默认开启）用原始 PCM RMS 噪声地板与滞回写共享 `isSilent`：只影响可视化，不静音系统音频；进入静音后目标置零，柱与峰值沿 Release / peak fall 回落，settled 后再画基线。处理次序为 Sensitivity 切带 → 静音目标置零 → Attack/Release/Peak Hold → Canvas Amplitude / Color。菜单栏保持 16 柱，仍读取分析器平滑后的 `spectrum`。调整这些参数不重建 Process Tap，也不在实时回调里做 FFT。
- Waveform 使用真实 PCM。Maximum display height（默认 0.70，范围 0.30–1.0）只作为占用高度的增益比例；Visual amplitude 默认 0.55（范围 0.1–2）决定信号在该比例内的填充强度。两者都不改系统音量或共享 PCM，也不制造远离 Canvas 边的内部裁切框。绘制仅按描边半宽内缩 `safeBounds`，路径与控制点钳在该安全区内，Canvas 外缘 `clip` 作最后防线。Fine Line / Soft Fill / Mirror 共用同一套边界。默认 Layout 为 Fixed 时可视化可不等于窗口（见 Layout）；Fill window 可贴窗绘制。Motion smoothing（0–1）按真实时间差做指数跟随，与 Spectrum Attack/Release 语义分离；空间邻点 soften 取平滑值的一小部分。默认形态是居中平滑曲线加淡基线，两端约 12% 渐隐；Fill strength 只影响 Soft Fill / Mirror。样本密度可选 32、64、128，是对快照里 128 个真实点按峰值降采样，绝不插值出更多点。线条颜色默认跟随 Appearance，可单独指定。旧 `"filled"` 样式解码为 Soft Fill；旧预设缺少 `verticalRange` 时回落默认 0.70，不 bump preset schema。
- Orbit 使用同一份真实频带，画成一圈从内环向外的圆角径向条；默认 48 根、内半径约 0.55、角间距 2.5°，并左右镜像（读取一半数量的真实频带，各画两次，低频在顶部、高频在底部，可关闭）。Layers 可选 Single 或 Dual Band（低频半带内环、高频半带外环）。Pulse strength（0–0.35，默认 0）用平均带能量轻微加长条。显示平滑按真实时间差计算。静音时停在一圈圆点和细环上，不自转。可设置柱数、内外半径、角间距、描边、颜色、线宽、振幅和平滑。
- `studio.backgroundOpacity` 仍保存在 0.35–1，默认 0.92。它只乘到 Studio 三种可视化的颜色上，不填充窗口，菜单栏频谱也不读取它。
- Studio **不**控制外部播放器（无 Music/Spotify 分源、无 Play/Pause、无 Now Playing 元数据）。不请求 Automation / Apple Events 权限；`Info.plist` 仅保留系统音频捕获用途说明。Studio 可视化只跟随系统输出音频。系统 Now Playing 仅出现在可选的 Experimental Island 功能中（见 §3 Experimental 与 §4.3）。
- 拖动、缩放、多桌面、全屏、窗口是否真正透明，必须在真实 Mac 上看到后才算通过。单元测试里的坐标计算、窗口标志和合成鼠标事件不能代替这些验收。

#### 验收

- 用户可拖动、缩放、隐藏、重新打开。
- 三种窗口模式即时改变公开层级，切换后窗口仍可见且位置不变。
- 模式切换不重建音频 capture service。
- 连续运行时窗口不闪烁、无持续增长的资源占用。

### 4.3 Island — 刘海灵动岛式音乐组件

**定位说明：** 这是一个位于刘海附近的自定义 macOS 窗口，不是 Apple 系统组件，也不是对系统刘海或菜单栏的修改。

#### 适用范围与技术边界

- 仅在确认带摄像头外壳/刘海的屏幕上默认启用该布局；支持用户选择目标屏幕。
- 优先使用公开 AppKit 屏幕几何信息，例如 `NSScreen.safeAreaInsets`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 以及屏幕可见区域，按实际屏幕布局计算可放置范围。
- 不把刘海宽度、高度或位置写死为单一硬编码数值；不同机型和屏幕缩放模式需验证。
- Island 窗口几何与命中仍只用公开 API，不注入 WindowServer，不通过无障碍权限伪装系统 UI。
- **唯一例外：** 可选 Experimental Now Playing 经 `mediaremote-adapter` 访问私有 MediaRemote（默认关闭）。该例外不扩展到 SkyLight / CGSSpace 或其他私有窗口 API。
- 不得长期遮挡菜单栏可点击区域；若某种屏幕或系统版本无法做到可靠定位，禁用 Island 并说明原因，不影响其他显示形态。
- 没有刘海的显示器上，第一版可以不提供 Island，或显示为禁用项并解释原因；不强制覆盖菜单栏中间区域。

#### 形态与状态

**Collapsed（收起）**
- 紧凑黑色/深色胶囊或圆角条。
- 可显示迷你 Spectrum / Waveform，不能显示复杂长文本。
- **不**显示 Now Playing 曲名或封面。
- 仅在启用 Island 时显示，不强制常驻。

**Expanded（展开）**
- 平滑展开；Expanded/Pinned 使用统一的大尺寸 frame（约 520–580 pt 宽，含额外高度），**不**随 `island.nowPlayingEnabled` 改变。
- 左翼为频谱 / 波形 / 环形图标切换；右翼为 Pin / Studio / Settings / 收起。
- 当 `island.nowPlayingEnabled` 为真时，按 `island.nowPlayingLayout.*` 显隐封面、标题与歌手、进度条、transport；氛围可视化由 `showVisualization` 控制。关闭 Now Playing 时不画播放器条，仅保留模式图标与可视化（若开启）。
- Settings → Notch Island 提供 Expanded 布局预览（对照 Studio Layout 预览：可 Pause / Resume）与上述显隐开关。

#### 交互与实现细节（Notch Island v1）

- **刘海几何校验**：同时检查 `NSScreen.safeAreaInsets.top`（16–64 pt）和左右 `auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 的有效性、顶边对齐与中心对称性。缺少辅助区域或无刘海屏幕一律判定为不支持（`.noNotch` / `.invalidGeometry`），隐藏窗口并停止 Island 刷新计时器。
- **窗口与鼠标命中架构**：使用无边框 `NSPanel`（`.borderless, .nonactivatingPanel`，`level = .statusBar`）。Compact 状态下窗口 frame 仅包裹物理刘海及左右各约 34 pt 的窄侧翼，外侧菜单栏完全不在窗口 frame 内，因此不拦截正常菜单栏点击，也不需要 Accessibility 或 Input Monitoring 权限。
- **悬停展开与防抖收起**：通过视图级 `NSTrackingArea` 检测鼠标进入 Compact 窗口。进入后先做内容预反馈，不改变窗口 frame：频谱最多放大到 1.03，并可以立刻出现描边，动画时长为 `min(0.12, 展开延迟)`。展开延迟独立于收起延迟，默认 0.35 秒，范围 0.1–1.0 秒，步长 0.05 秒（`island.expandDelaySeconds`）。延迟结束时若仍是 Compact、指针仍在有效区域且没有按下，才把窗口 frame 扩到 Expanded（Expanded frame 严格包含 Compact frame）。指针离开、按下、Pin、Escape、禁用或屏幕变化都会作废这一次等待；重新进入会重新计时。鼠标离开窗口（含 6 pt 边缘容差）后按收起延迟（0.15–1.5 秒，默认 0.35 秒）自动收起，延时内重新进入立即取消收起。
- **触觉反馈**：默认关闭（`island.hapticStrength`）。Light、Medium、Strong 分别映射到公开 `NSHapticFeedbackManager` 的 Alignment、Generic、Level Change。这是三种系统触感模式，不是硬件振幅。只在一次真正完成的 Compact → Expanded 后触发一次；悬停、取消、重复进入、Pin，或已经处于 Expanded，都不触发。没有 Force Touch 触控板时调用安全空操作。
- **动画速度**：默认 1.0×，范围 0.5×–2.0×，步长 0.1×（`island.animationSpeed`）。展开基准 200ms、收起基准 120ms，实际时长为基准除以速度。展开用控制点 `(0.22, 0.90, 0.20, 1)` 的缓出，四个分量都在 0...1，窗口 frame 不会越过目标；收起用 ease-in。开启 Now Playing 时仅展开再 ×1.25，收起不加时。系统 Reduce Motion 且“Follow system Reduce Motion”打开时，时长为 0，速度设置不能把它改回动画。预反馈同样在 Reduce Motion 下取消缩放。
- **固定与快捷键**：点击固定按钮（Pin）进入 `pinned` 状态，鼠标离开不自动收起；再次点击取消固定或按 `Escape` 键立即收起。从 Compact 直接 Pin 不经过悬停展开，也不触发触觉。
- **可视化与共享数据**：复用同一个 `ProcessTapSpike` 和 `AudioSnapshot`。Compact 左右侧翼绘制对称实时频谱（可选每侧 4、5、6 根柱，静音回归静态基线点）；Expanded 支持切换 Spectrum、Waveform、Orbit，并复用全局 Appearance 颜色。开启/关闭 Island 或 Now Playing **绝不**擅自启动或停止系统音频捕获。
- **Experimental Now Playing**：偏好键 `island.nowPlayingEnabled`（默认 `false`）只控制是否监听 MediaRemote / 是否显示播放器条，**不**改变 Expanded frame。布局键 `island.nowPlayingLayout.showArtwork|showTitleArtist|showProgress|showTransport|showVisualization`（默认均为 `true`）。仅在 Island 已启用且刘海几何有效时启动 adapter 监听；禁用 Island、关闭开关、无刘海降级或 app shutdown 时立即停止。Seek 对不支持的 `bundleIdentifier` 降级为只读进度条，transport 仍尽量可用。

#### 验收

- 带刘海目标机型上能稳定定位；屏幕边界变化后重算位置。
- 收起/展开不重启音频捕获，也不打断其他显示形态。
- 系统菜单栏可点击区域不被不可见窗口长期拦截。
- 不支持的屏幕上有明确降级行为。

### 4.4 Desktop Magnet — 可被覆盖的桌面磁贴

**目的：** 让用户把一个小型实时声音图形放在桌面构图中；它不是始终置顶的覆盖层。

#### 窗口层级（重要）

- 使用普通窗口层级（normal level）并通过正常 z-order 行为显示。
- **默认不置顶；其他常规应用窗口可以自然覆盖它。** 不要用 floating/status-bar/screen-saver 等更高层级实现磁贴。
- 不承诺把窗口放在 Finder 桌面图标“背后”，也不使用私有 API 操作桌面窗口。这与“能被其他窗口遮住”是不同需求。
- 首版跟随所在桌面空间（Space），不强制跨所有 Space，不强制覆盖全屏应用。
- 首版先支持一个 Desktop Magnet 实例；多个磁贴作为以后扩展。

#### 外观与交互

- 支持 Spectrum、Waveform、Orbit 三种模式；小尺寸下允许使用简化绘图。
- 用户可拖动、缩放、调整透明度和颜色。
- 常态不显示厚重边框；编辑/悬停时可以展示轻量控制 affordance。
- 记住位置、尺寸、模式与显示器标识；保存的显示器不存在时迁移到可见屏幕。
- 默认允许点击以便拖动与控制；鼠标穿透不属于 v0.3 必需能力。
- 磁贴隐藏或被遮挡时，视觉层停止高频绘制；共享音频状态仍由中央服务维护。

#### 验收

- 用户移动到桌面空白处后，打开普通应用窗口可以盖住磁贴。
- 不需要一直置顶才能看到它；它不会在用户切换应用时不断强制跳到最前。
- 位置/尺寸重新启动后恢复；断开显示器后位置能安全回退。
- 隐藏或被覆盖不导致创建第二条音频捕获管线。

### 4.5 四种形态的统一规则

- 所有形态共享一个 `AudioCaptureService`、一个 `AudioAnalyzer` 与一个最新 `AudioSnapshot` 状态源。
- 不同形态可以独立配置显示模式、尺寸、透明度和窗口行为；全局视觉参数（例如强调色、灵敏度、平滑度）默认共享。
- 窗口层级、位置、显示器目标与展开状态是每个 surface 自己的设置。
- Surface 开关控制 UI 是否可见，不直接创建/销毁无关服务。音频捕获有独立的“分析开/关”状态。
- 禁止每个窗口各自启动 FFT、音频 tap 或高频计时器来分析原始 PCM。

---

## 5. 三种首发可视化

### 5.1 Spectrum — 频谱柱

- 使用固定长度的归一化频带数组。
- 频带分布要让低频、中频和高频变化都能被观察；可使用对数分布或合适的频带映射。
- 支持统一灵敏度、平滑度、柱间距与强调色；不需要首版实现复杂逐柱渐变编辑。
- 输入静音时在可控时间内回到基线，不突然跳变。
- 小尺寸（菜单栏/Island）使用简化柱数和绘制路径。

### 5.2 Waveform — 时域波形

- 绘制从真实音频数据中抽样的时域波形，不得生成随机曲线。
- 窗口可以表现为单线、居中基线或轻量镜像；首版确定一种主视觉，再允许少量参数调整。
- 缓冲数据不足或静音时回到稳定基线。
- 对采样数据做安全限幅并处理非有限值。

### 5.3 Orbit — 环形/径向频谱

- 将频谱频带映射为围绕固定中心的径向元素。
- 窗口缩放时保持布局比例、中心位置与边距；小尺寸时减少元素数量。
- 视觉随实际频谱变化，不是恒定自转的装饰动画。
- 静音时回归稳定、克制的基态。

### 视觉的一致性规则

- 三种模式共享主题、灵敏度、平滑和状态语义。
- 动画使用适量缓动，不要同时使用高亮光晕、强模糊、重粒子和渐变堆叠。
- 系统 Reduce Motion 开启时减弱或关闭非必要过渡动画。
- 图形在小尺寸下仍清晰；不能因为绘图区域过小而产生负尺寸、越界绘制或 crash。
- 首发不要求 Metal。先使用 SwiftUI Canvas 或轻量 AppKit 绘制；只有性能测量证明不足，才单独引入 Metal。

---

## 6. 设置与偏好

### Core MVP 必需设置

- 选择 Studio 当前视觉模式：Spectrum / Waveform / Orbit。
- 菜单栏显示模式：Spectrum / Waveform / Orbit（如 Orbit 在窄区域表现不佳，可用简化版本）。
- 强调色：提供若干设计好的内置选择；首版不需要完整自由色轮。
- 灵敏度：有限范围的滑块，默认中等。
- 平滑度：有限范围的滑块，默认中等。
- Studio 可视化透明度：0.35–1，默认 0.92。只改变 Studio 图形颜色，不绘制窗口背景。
- Studio 窗口模式（On Desktop / On Top / As Window，见 §4.2）。
- Studio Spectrum 与 Orbit 各自的柱数：8、12、16、24、32、48、64。Spectrum 默认 32，Orbit 默认 48（镜像时读取一半数量的真实频带）。Waveform 不使用该设置。
- Studio 窗口行为：允许拖动、允许缩放、启动时恢复位置和大小、重置位置和大小、画布鼠标穿透（On Top、On Desktop、As Window 都开启）、自动隐藏控件（默认开启；拖动把手保持可见，其余按钮在指针靠近时出现，离开 3 秒后隐藏）、淡入淡出开关、是否遵守系统 Reduce Motion。
- 所有 Studio 参数都在单独的 Settings 窗口中调整，立即生效、写入 UserDefaults，并有分类 Reset 与 Reset All。
- Studio 显示/隐藏。
- 音频分析启用/停止与捕获状态。
- 恢复默认值。

### Island / Magnet 上线后的设置

- Island 开启/关闭、目标屏幕、悬停展开开关、展开延迟（默认 0.35 秒，0.1–1.0 秒）、收起延迟、触觉反馈（默认关闭；Light / Medium / Strong 只选择系统触感模式）、动画速度（默认 1.0×，0.5×–2.0×；Reduce Motion 优先于速度）、默认展开行为、**Show Now Playing when expanded**（`island.nowPlayingEnabled`，默认关闭，实验性说明文案）、**Now Playing layout** 显隐（封面 / 标题歌手 / 进度 / 控件 / 可视化）与 Notch Island 布局预览（Pause / Resume）。
- Magnet 开启/关闭、显示器选择（若多屏需求明确）、透明度、位置恢复。
- 每个 surface 独立保存视觉模式、尺寸和局部显示状态。
- 全局设置与 surface 设置要分开，避免一个窗口改尺寸影响其他窗口。

### 设置实现原则

- 使用轻量 `SettingsStore` 与 `UserDefaults`；可以用 `@AppStorage` 管简单值。
- 只持久化设置，不保存 PCM 音频或完整音频快照历史。
- 给所有数值参数设置安全的 min/max；加载旧值或无效值时归一化到合法范围。
- 存储键集中定义，避免到处使用字符串字面值。
- 首版不需要数据库、网络同步或复杂状态管理框架。

### Startup Behavior & Launch at Login v1

- Settings → Startup 配置进程启动时的行为，以及是否随 macOS 登录自动启动。Now Playing 开关在 Notch Island 分类，不在 Startup。
- **Show at launch（独立复选框）**：`startup.openStudioAtLaunch`（默认 `false`）、`startup.showIslandAtLaunch`（默认 `true`）、`startup.openSettingsAtLaunch`（默认 `false`）。可同时勾选；全部不勾选时只保留菜单栏入口。缺省值与升级前一致：Studio/Settings 不自动打开，Island 跟随已保存的 `island.isEnabled` 与刘海支持。旧键 `startup.destination` 在首次加载时迁移为上述布尔组合后删除。不提供 “恢复上次会话”（Studio 可见性未持久化）。
- **Notch Island 边界**：启动复选框不静默改写 `island.isEnabled`；用进程内 `allowsLaunchPresentation` 门控本次是否呈现。Island 总开关关闭时，即使勾选启动显示也不会强制开启，Settings 提供启用入口。无刘海时安全降级，不创建错位窗口。
- **Launch at Login**：Settings → Startup 的独立开关，通过公开 API `SMAppService.mainApp` 注册/取消注册；UI 只读系统 `status`（`.enabled` / `.notRegistered` / `.requiresApproval` / `.notFound`），不在 UserDefaults 伪造注册状态。登录启动与手动启动共用同一套窗口复选框；不创建 helper、不写 LaunchAgents。
- **Visualization mode（`startup.visualMode`）**：`keepCurrent`（默认）或 Spectrum / Waveform / Orbit。覆盖时写入 `studio.mode` 与 `island.mode`，避免首帧闪烁。
- **Optional Visual preset（`startup.presetID`）**：稳定引用内置或自定义预设 ID；缺省不覆盖。在 Startup 选中预设时 UI 会同步写入对应 `visualMode`；`keepCurrent` 时冷启动只应用预设参数、不切换 Studio/Island 当前模式。显式模式与预设冲突则跳过预设；缺失/已删除 ID 跳过且不另选替代；应用路径复用 `applyVisualPreset`（只改该模式视觉参数与 `appliedIDByMode`）。Visualization 页应用/保存预设时同步更新 `startup.presetID`，避免冷启动用旧启动预设覆盖本次选择。
- **Optional auto-capture（`startup.autoStartCapture`）**：默认 `false`。仅当已通过非弹窗探针确认授权时，才在冷启动调用现有 `ProcessTapSpike.start()`；未授权不弹 TCC。打开 Studio/Island/Settings 不会自动开始捕获。
- 窗口、模式、预设与可选捕获只在**每次进程冷启动**由 `StartupApplicator` 应用一次；激活应用、重新打开窗口、或仅在 Settings 中改选项都不会重放。窗口/可视化修改在下次启动生效；Launch at Login 在下次 macOS 登录生效。

### 可视化预设 v1

- Spectrum、Waveform、Orbit 的设置页顶部各有一组 Visual preset。从菜单选择后立即写入 `StudioPreferences` 中对应模式的结构体，并刷新已经打开的 Studio。不切换 Studio 或 Notch Island 当前正在显示的模式。
- 内置预设写在代码里，不依赖用户数据，也不能被重命名、覆盖或删除。Spectrum 是 Clean（Solid）、Dense（Frequency）、Dynamic（Amplitude + Peak Hold）。Waveform 是 Fine Line、Soft Fill、Mirror（真正的 Mirror 样式）。Orbit 是 Compact、Halo（Dual Band）、Dense Ring。它们改的是柱数、间距、振幅、平滑、攻击释放、色彩映射、层模式或半径等真实参数。
- 自定义预设可以保存当前模式、复制、重命名和删除。复制内置预设会得到一个新的自定义副本，内置定义不变。名称去掉首尾空白后不能为空，最多 40 个字符，同一模式内大小写不敏感地不能重名。每个模式最多 24 个。删除前要确认；删除后现场参数保留，只是不再标成这个预设。
- 应用预设只替换该模式的全部字段（含新增的 colorMode、fillStrength、layerMode、pulseStrength 等）。Waveform 和 Orbit 的自定义颜色属于该模式，会被这份预设替换；内置预设不带自定义颜色，所以继续跟随 Appearance。Appearance 的填充色、描边色、透明度和线宽是全局的，预设不改它们。Window 的 Width / Height 属于应用级窗口偏好，不写入视觉预设。另一模式、窗口、播放，以及 Island 的开关、屏幕、悬停、收起和 Compact 每侧柱数也不改。
- 状态在已应用时只显示预设名称；继续改该模式的参数后显示「名称 (Modified) / 名称（已修改）」。只改 Appearance 不会把当前模式预设标成 Modified。
- 自定义预设和每个模式最后应用的 id 存在 UserDefaults 键 `studio.visualPresets`，是 schema version 1 的 JSON。新字段用 `decodeIfPresent` 回落到标准默认；读取失败或 schema 更高时保留原数据，不自动覆盖；设置页可以显式 Reset Preset Library。分类 Reset 会恢复该模式的出厂参数并清掉它的已应用标记，不删除自定义预设。
- **预设导入 / 导出：** Settings 各模式 Visual preset 区提供 Export… / Import…。导出使用独立交换格式 `audune.visualPresetExchange`（`schemaVersion` 1，与内部 `studio.visualPresets` schema 分离），可导出当前模式的单个或多个预设（含内置快照）为 pretty-printed `.json`；文件只含名称、模式与该模式完整参数，不含 Appearance、Window、Island、音频权限、`appliedIDByMode` 或内部 UUID。导入经原生打开面板 → 严格验证（文件 ≤512 KB、最多 72 条、必填字段、有限数值、允许范围、未知枚举拒绝）→ 预览名称/模式/冲突 → 用户选择「导入为副本」或「跳过冲突」或取消 → 一次性 `commitImport` 追加自定义预设。导入始终生成新 UUID 与 `kind = custom`；内置定义不可覆盖；确认前与取消/失败路径不改存储；超每模式 24 上限整批拒绝。不支持的 schema 版本整文件拒绝，不做猜测性解析。
- Studio 和 Notch Island 的展开视图读取同一份模式参数。两个窗口各自记住自己正在显示的模式。Island Compact 侧翼仍使用 Island 的每侧柱数和 Appearance 单色，不跟随 Spectrum 色彩映射或柱数。预设不创建或重启 Process Tap。Appearance 页原有的 Warm / Amber / Sea / Mist 只改全局颜色，不属于这套可视化预设。实时动画缓冲与峰值临时状态不写入预设。

---

## 7. 技术栈与架构

### 技术选型

| 层 | 首选方案 | 职责 |
|---|---|---|
| 语言 | Swift | 应用、DSP、协调逻辑 |
| UI | SwiftUI | 设置页、控制面板和普通内容 |
| 系统集成 | AppKit | `NSStatusItem`、`NSPanel`/窗口层级、屏幕几何、刘海窗口原型 |
| 音频捕获 | Core Audio Process Tap | 捕获系统正在输出的混音音频 |
| 信号分析 | Accelerate / vDSP | FFT、频带聚合、RMS/peak、平滑 |
| 首版绘制 | SwiftUI Canvas / AppKit 自绘 | 三种基础可视化和紧凑版图形 |
| 持久化 | UserDefaults | 用户偏好、窗口位置与大小 |
| 测试 | XCTest | DSP、参数归一化、偏好与状态逻辑 |
| 构建 | Xcode project + `xcodebuild` | 本地构建与 macOS CI |

**不采用 Flutter/RN/Electron 作为首选实现。** 本项目的核心价值依赖原生菜单栏、窗口层级、系统音频与屏幕几何，跨平台框架并不会减少这些原生工作。

### 最低系统版本

- 初始 target：**macOS 14.2+**。Apple 的 Core Audio Tap 示例明确要求 macOS 14.2 或更高版本并配置 `NSAudioCaptureUsageDescription`。
- 首次打包前必须在最低支持版本上真实验证 tap、授权、退出清理、睡眠/唤醒和输出设备切换。
- 如果验证发现最低版本不稳定，可以在首发前提升最低版本；更新 `PRODUCT_SPEC`、Xcode deployment target、README 和发行说明，不能文档写一个版本、项目配置写另一个版本。
- 不以 beta 系统作为唯一测试环境。

### 推荐结构（允许结合现有仓库适度调整）

```text
Audune/
├── App/
│   ├── AuduneApp.swift
│   ├── AppCoordinator.swift
│   ├── AppState.swift
│   └── AppLifecycle.swift
├── Audio/
│   ├── AudioCaptureService.swift
│   ├── ProcessTapCapture.swift
│   ├── AudioAnalyzer.swift
│   ├── AudioSnapshot.swift
│   ├── AudioCaptureState.swift
│   ├── AudioRingBuffer.swift
│   └── AudioMath.swift
├── Surfaces/
│   ├── MenuBar/
│   │   ├── MenuBarController.swift
│   │   ├── MenuBarVisualizerView.swift
│   │   └── ControlPopoverView.swift
│   ├── Studio/
│   │   ├── StudioWindowController.swift
│   │   └── StudioView.swift
│   ├── Island/
│   │   ├── IslandWindowController.swift
│   │   ├── IslandPositioning.swift
│   │   └── IslandView.swift
│   └── Magnet/
│       ├── MagnetWindowController.swift
│       └── MagnetView.swift
├── Visualizations/
│   ├── VisualizerMode.swift
│   ├── SpectrumView.swift
│   ├── WaveformView.swift
│   └── OrbitView.swift
├── Settings/
│   ├── SettingsStore.swift
│   ├── SettingsView.swift
│   └── SurfacePreferences.swift
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.xcstrings
└── AuduneTests/
    ├── AudioAnalyzerTests.swift
    ├── AudioMathTests.swift
    ├── SettingsStoreTests.swift
    └── SurfacePreferencesTests.swift
```

这个目录是建议，不是要求必须逐字匹配。若项目已有合理结构，保持现有架构，不为满足目录图而无意义搬动文件。

### 模块责任

**AppCoordinator / AppState**
- 管理服务与 surface 的生命周期、偏好同步和应用退出。
- 不直接处理 FFT 或绘制细节。

**AudioCaptureService**
- 管理 tap、aggregate device、IO 启停、权限错误与清理。
- 保证 start/stop 幂等；重复调用不会累积资源。
- 允许捕获服务独立于任何单个显示窗口存活。

**AudioAnalyzer**
- 接受 PCM block，产出有限长度、可直接绘制的 `AudioSnapshot`。
- 处理 FFT、频带聚合、波形抽样、RMS/peak、静音检测和平滑。
- 不依赖 SwiftUI，不访问窗口，不进行网络/磁盘 IO。

**AudioSnapshotStore**
- 保存最新快照，供不同 surface 读取。
- 不保留无限历史；若绘图需要滚动窗口，仅保留有界的短期样本。

**Surface Controllers**
- 负责各自窗口的显示/隐藏、显示器位置、层级与生命周期。
- 不管理底层音频 tap。

**Visualizer Views**
- 把输入 snapshot 和设置映射为图形。
- 不读原始 Core Audio buffer，不启动自己的分析循环。

**SettingsStore**
- 集中读取、归一化和写入偏好；防止 UI 出现无效值。

### 音频数据管线

```text
macOS 输出混音音频
  ↓
Core Audio Process Tap + Aggregate Device
  ↓ PCM buffers（只在内存中短暂存在）
实时回调 → 预分配的有界缓冲区
  ↓
后台分析器 → FFT / bands / waveform / RMS / peak / silence
  ↓
最新不可变 AudioSnapshot
  ├── Menu Bar
  ├── Studio
  ├── Island
  └── Desktop Magnet
```

### `AudioSnapshot` 最低字段

- `sequenceNumber`：递增序号，用于判断是否收到新数据。
- `timestamp`：单调时钟时间戳或可比较的采样时间标记。
- `spectrum: [Float]`：固定长度、归一化的频带幅度数组。
- `waveform: [Float]`：固定长度或有界长度的时域抽样数组。
- `rms: Float`、`peak: Float`：有限、归一化的能量指标。
- `isSilent: Bool`：带阈值和短时间滞回的静音结果。

数组长度在稳定运行期内保持稳定。所有输出都必须处理 NaN/Infinity 和空输入；绘图层不得假定数组永不为空。

### 实时线程规则

- Core Audio realtime callback 不得执行 UI 更新、文件/网络 IO、同步日志、等待任务、锁竞争或动态大块内存分配。
- 采用预分配缓冲区/有界环形缓冲区等适合实时路径的机制，将样本交给后台分析器。
- FFT 与重计算放在后台工作路径；UI 在主线程读取最新快照并绘制。
- 若有丢帧或缓冲区溢出，应丢弃旧视觉样本并恢复实时状态，而不是无限累积延迟。
- 所有任务和回调有明确停止/销毁路径；退出后不能有后台循环残留。

### 系统音频捕获与隐私

- 使用 Apple 公布的 Core Audio Process Tap API（例如 `CATapDescription`、`AudioHardwareCreateProcessTap` 及相应 aggregate device 生命周期）。实现细节以当前 SDK 的正式声明和 Apple 示例为准。
- `Info.plist` 配置 `NSAudioCaptureUsageDescription`，用简明文案说明 Audune 只为实时可视化捕获系统输出音频。
- 不请求麦克风权限，不将麦克风当作 fallback。
- Tap 不得静音/独占用户音频；明确设置为非静音行为，并验证实际播放不受影响。
- 必须清理 tap、aggregate device、IOProc/回调及相关 listener。所有中间失败都需回滚已创建资源。
- 声音数据只放在内存中进行实时处理；不写入文件、不上传、不生成音频日志。
- 不承诺绕过受保护音频、特定应用策略或系统限制；遇到无法捕获的来源应报告为捕获不可用/受限，而不是伪造响应。

### 状态模型

捕获状态建议至少区分：
- `idle`：用户未启用捕获。
- `requestingPermission`：发起系统授权流程。
- `permissionRequired`：尚未授权/需要继续操作。
- `permissionDenied`：权限已被拒绝。
- `starting`：tap 正在建立。
- `running`：正在接收有效音频流。
- `silent`：捕获仍运行，但当前能量处于静音阈值内。
- `interrupted`：系统睡眠、设备变化或其他短暂中断。
- `unsupported`：系统版本或 API 条件不满足。
- `failed`：捕获失败；应携带可诊断的内部错误信息。

不要把 `silent` 和 `failed` 混为一谈。用户界面显示适当的精简状态，而开发诊断保留具体错误码但不包含音频内容。

---

## 8. 生命周期与系统集成

### 应用类型

- 默认是 menu-bar utility：菜单栏可进入，默认不显示 Dock 图标和应用切换器条目（可通过 `LSUIElement` 等公开机制实现）。
- 用户关闭一个 surface 不等于退出整个应用。
- 菜单栏面板提供明确的 `Quit Audune`。
- 如果用户从系统 UI 隐藏/禁用了菜单栏项目，要提供 README/设置说明，且应用不能因此意外清除用户配置。

### 音频与应用生命周期

必须处理：
- 首次授权、拒绝授权、系统设置中变更权限后重新启动/重试。
- 捕获服务重复启停。
- 暂停/恢复媒体播放或系统静音。
- 默认输出设备变化、耳机/蓝牙设备插拔。
- 系统睡眠与唤醒。
- 应用退出和重新启动。
- tap / aggregate device 创建的任一阶段失败。

### 多显示器与 Space

- Studio：保存位置/尺寸；恢复时若坐标不可见，移动到主屏可见区域。
- Island：保存目标显示器偏好；显示器断开后重新选择合适屏幕或关闭 Island。
- Magnet：保存位置/尺寸及显示器标识；不保证跨所有 Spaces；初版不强制在全屏应用之上显示。
- 不使用私有 API 修改 Stage Manager、Mission Control 或桌面图标层级。

---

## 9. UI / UX 规范

### 基本视觉

- 菜单栏和普通面板可以使用深石墨背景 `#181A1E`、暖白前景与单一强调色；颜色不是硬编码到所有绘图路径中的不可更改常量。
- Studio 不使用整窗石墨底板、描边或窗口阴影。暖白和强调色只用于图形与控件文字。
- 默认减少厚重边框、巨大圆角卡片、荧光光晕和过多渐变。
- 所有 surface 使用同一视觉 token（颜色、线宽、间距、动效时长），保证看起来是同一应用。
- 状态文字短而清楚，例如 `Listening`、`No audio`、`Permission required`、`Audio unavailable`。
- 捕获状态不可只靠颜色表达，至少同时提供文本或图形形态变化。

### 动效

- 可视化应随最新音频样本平滑更新；不得通过动画曲线假装有声音。
- Island 收起/展开基准 120ms/200ms，再除以动画速度（默认 1.0×，0.5×–2.0×）。开启 Now Playing 时仅展开 ×1.25。Reduce Motion 优先于速度，打开时时长为 0。
- 菜单栏图标不播放无意义的开场动画或持续 pulse；真实输入静音时图形稳定。
- 快速切换模式不得重建音频服务，也不得卡住主线程。

### 可访问性

- 主要按钮有 VoiceOver 可读名称与键盘焦点样式。
- 设置控件能通过键盘操作；Esc 关闭 Popover/Island 展开面板（除非焦点正处于需要保留的文本控件）。
- 支持浅色/深色系统外观或确保自定义深色样式在两种外观下均可辨识。
- 遵守系统 Reduce Motion；字号和控件命中区域不能过小。

### 首版不做

- 可视化编辑器节点/连线系统。
- 任意脚本、Shader 编辑器或下载第三方主题。
- 专辑封面自动取色、动态壁纸、视频录制。（Experimental Zen 联网歌词见 §3，默认关闭。）

---

## 10. 非功能要求与验收

### 正确性

- 播放系统输出音频时，三个模式都能从同一份实时分析数据获得不同但合理的图形反应。
- 静音与失败是不同状态；停止捕获后图形不继续显示旧的动态数据。
- 切换 Menu Bar / Studio / Island / Magnet 不重复建立捕获服务。
- 设置修改即时生效且在重启后保留。

### 稳定性

- 连续运行至少 30 分钟无崩溃、无明显持续增加的内存占用。
- 反复启停音频捕获 20 次，不应累积 Core Audio tap、aggregate device、回调或计时器。
- 改变音频设备、睡眠/唤醒、撤回权限后，应用不应永久卡在 `running`。
- 任何窗口关闭/隐藏不应让整个 app 无法从菜单栏恢复。

### 性能（目标，不作为对所有硬件绝对保证）

- Studio 可见时目标约 30 FPS；菜单栏目标约 20–30 次视觉更新/秒。
- 从音频输入变化到可见图形响应的目标感知延迟低于约 100–150ms；以真实设备测量，不用假定值声称通过。
- 隐藏/被覆盖窗口停止或明显降低绘制频率；用户关闭音频分析后应停止采集。
- 首版在至少一台 Apple Silicon Mac 记录 CPU、内存与 Energy Impact 基线；若存在明显空闲高占用，必须优化后再发布。
- 音频回调里不做不安全工作，分析器使用有界内存。

### 隐私与安全

- 不请求麦克风、不保存音频、不向网络发送音频或用户行为数据。
- 不添加遥测、广告、云账户、远程配置或自动上传诊断。
- 诊断信息不得包含 PCM 样本、歌曲内容或可识别的个人文件路径；默认不开启文件日志。
- 所有外部依赖必须有许可证说明；首版尽量零第三方依赖。

### 错误提示

- 系统版本不支持：解释最低要求。
- 系统音频权限缺失/拒绝：解释权限目的并给出重新授权路径。
- 捕获启动失败：显示可重试按钮与非技术用户能理解的说明。
- 当前无声音：显示正常的静音状态而不是错误提示。
- Island 不支持：说明该屏幕没有可用刘海定位条件，其他形态可正常使用。
- 显示器拔除：窗口重新定位到可见显示器。

---

## 11. 测试策略

### 自动化测试

必须包含不依赖真实音频设备的 XCTest：
- 静音 PCM → RMS、peak、spectrum 正常接近零。
- 正弦波 → 预期频段显著高于其他频段。
- 两个不同频率输入 → 频带响应有明显差异。
- 幅度增长 → RMS/peak 合理增长，不出现 NaN/Infinity。
- 空 buffer、非有限输入、突发峰值 → 无 crash，输出值被规范化。
- 静音阈值与滞回 → 状态稳定，不在阈值附近闪烁。
- SettingsStore 默认值、保存/加载、无效值修复、恢复默认。
- SurfacePreferences 的独立性：Studio 置顶/尺寸变化不意外改变 Magnet。
- 窗口几何计算：模拟屏幕断开、负坐标、屏幕缩放和不可见保存坐标。

### 手动集成测试

每次涉及音频生命周期时至少回归：
- 浏览器网页音频。
- 本地音频播放器。
- 没有播放、暂停、静音、恢复播放。
- 首次权限弹窗、拒绝、设置中重新授权。
- 内建扬声器、耳机、可用的蓝牙输出设备切换。
- 应用启动/退出、音频捕获启停 20 次。
- Studio 隐藏/显示、移动/缩放、始终置顶切换。
- 三种视觉模式快速切换。
- 睡眠/唤醒、显示器插拔、分辨率或缩放变化。
- 带刘海屏幕：Island 收起/展开、菜单栏点击、鼠标离开/进入、全屏 app 行为。
- 不带刘海屏幕：Island 的禁用/降级表现。
- Magnet 被普通应用窗口覆盖、切换应用、重新显示、恢复位置。
- 连续运行 30 分钟。

### CI 边界

- CI 负责构建、静态检查（可用时）和不依赖系统权限/音频硬件的测试。
- 不把真实系统音频捕获成功作为无头 CI 必须通过的条件；该能力必须由维护者在真实 macOS 用户会话里手动验证并记录结果。
- 测试失败不能通过删测试、跳过整个测试 target 或只改 CI 让红灯消失来处理。

---

## 12. 开源、打包与发布

### 开源政策

- 完全开源；建议采用 MIT License，正式发布前在仓库加入完整 `LICENSE`。
- 不使用未授权字体、图标、壁纸、音乐片段或竞品 UI 资产。
- 参考开源项目时检查其许可证；没有明确许可证的代码不能直接复制。
- 保持无账号、无广告、无遥测与本地音频处理承诺。

### 仓库基础文件

- `README.md`：产品介绍、功能截图、系统要求、安装/构建、权限说明、已知限制。
- `LICENSE`：MIT（发布前确认）。
- `CONTRIBUTING.md`：环境、分支约定、测试、Issue 流程、提交格式。
- `AGENTS.md`：AI coding agent 规则（必须提交到仓库根目录）。
- `docs/PRODUCT_SPEC.md`：本产品规格的仓库内版本。
- `docs/GITHUB_ISSUES.md`：可复制创建 GitHub Issues 的任务单。
- `docs/MANUAL_TESTS.md`：人工验收表。

### 构建/发布

- 使用 Xcode project 和 `xcodebuild`；不要在没有确认仓库实际结构前编造 scheme 名称或命令。
- CI 构建脚本要基于实际生成的 `.xcodeproj` / scheme 更新。
- 首发先提供源码构建方法；准备好后可以输出 ZIP，DMG 和签名/公证安排后续评估。
- 不承诺首版进入 Mac App Store；系统音频捕获、沙盒、签名、公证和分发流程先单独验证。
- 不运行来路不明的安装脚本；发布包要说明签名、公证和系统提示状况。

---

## 13. GitHub Milestones 与 Issue 顺序

Issue 的具体标题、任务和验收清单见 `docs/GITHUB_ISSUES.md`。推荐按此顺序：

1. **Phase 0 — Audio Spike**：先证明真实系统音频能捕获与释放。
2. **Phase 1 — Foundation**：项目骨架、音频服务、DSP、快照与测试。
3. **Phase 2 — Core Surfaces**：菜单栏、Studio、三种可视化与设置。
4. **Phase 3 — Island**：先做窗口/屏幕几何 spike，再交付交互。
5. **Phase 4 — Desktop Magnet**：普通层级的桌面磁贴和位置恢复。
6. **Phase 5 — Release Readiness**：隐私说明、文档、CI、人工回归与测试包。
7. **Experimental — Island Now Playing**：可选完整播放器（AUD-NP-01）；默认关闭；不计入 Core MVP。若 Apple 日后提供公开系统 Now Playing API，再评估替换私有旁路。
8. **Experimental — Zen Player + Network Lyrics**：普通窗口氛围播放器与可选 LRCLIB 歌词（AUD-NP-02）；默认关闭；不计入 Core MVP。

### Definition of Done（每个 Issue）

- [ ] 任务范围与验收条件明确，未夹带无关功能。
- [ ] 代码能构建；相关自动化测试通过。
- [ ] 无法自动化的系统行为有手动测试结果，未被伪称为自动通过。
- [ ] 失败路径与权限状态有清晰反馈。
- [ ] 无新增未授权网络请求、遥测、音频存储或不必要依赖。
- [ ] 文档同步更新（如行为/限制/安装要求变化）。
- [ ] 当前 Git 分支仍为 `dev`。
- [ ] 每个已完成且通过相关验证的 TODO 均有独立 commit；未完成或相关测试失败的 TODO 未提交。
- [ ] commit message 严格使用 `:gitmoji: short-git-message`；没有自动 push，也没有把用户已有改动混入 commit。

---

## 14. 外部技术参考

优先以 Apple 当前 SDK 与 Developer Documentation 为准。以下第三方项目仅用于研究交互/架构思路，不是运行时依赖。

- Apple — [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)：系统音频 tap 官方示例与授权要求。
- Apple — [CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription)：Tap 对象配置。
- Apple — [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)：SwiftUI 菜单栏入口；Audune 的高频自绘可以选择 AppKit `NSStatusItem`。
- Apple — [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)：屏幕安全区域及部分 Mac 刘海遮挡信息。
- Apple — [NSWindow.Level](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)：公开窗口层级概念；Magnet 应使用普通层级。
- CodeIsland — [GitHub](https://github.com/wxtsky/CodeIsland)：刘海区域状态面板的交互参考。
- Stats — [GitHub](https://github.com/exelban/stats)：菜单栏指标模块和控制面板参考。
- Nowsee — [GitHub](https://github.com/Sergio-prog/Nowsee)：开源系统音频可视化实现参考；使用前重新核对其当前许可证与代码范围。
- mediaremote-adapter — [ungive](https://github.com/ungive/mediaremote-adapter) / [ejbills SPM fork](https://github.com/ejbills/mediaremote-adapter)：Experimental Island Now Playing 运行时依赖（私有 MediaRemote 旁路）；pin revision 并在第三方许可说明中标注。

### 关键技术提醒

- Apple 的 Core Audio tap 示例要求 macOS 14.2+，并要求配置 `NSAudioCaptureUsageDescription`；第一次开始使用 tap 的 aggregate device 时，系统会请求系统音频录制/捕获权限。
- `NSScreen.safeAreaInsets` 在部分 Mac 上反映摄像头外壳遮挡范围；这并不意味着所有机型上都可以用一个固定坐标可靠定位刘海窗口。Island 必须真实测试。
- 普通窗口层级与浮动窗口层级不同。Desktop Magnet 必须使用普通层级以允许其他常规窗口覆盖它；不应使用更高的 floating/status-bar 层级。
- macOS 的菜单栏布局、权限与窗口行为可能随系统版本变化；发布前要在目标系统版本实机验证并更新限制说明。

---

## 15. MVP 成功定义

Audune 的 Core MVP 在以下条件全部满足时才算可交付：

1. 新用户可以从仓库按文档构建应用。
2. 用户授权后，实际系统输出声音能驱动菜单栏图形和 Studio 的 Spectrum、Waveform、Orbit 三种模式。
3. 权限拒绝、无声音、捕获失败和系统不支持状态互不混淆。
4. Studio 可移动、缩放、显示/隐藏、切换置顶；偏好可以恢复。
5. 菜单栏和 Studio 共享同一捕获服务与分析状态。
6. 自动化 DSP/设置测试通过，人工音频/窗口测试清单已执行并记录。
7. 隐私承诺与代码一致；不存在音频保存、上传、遥测和麦克风 fallback。
8. 连续运行 30 分钟、反复启停捕获和基本设备切换测试没有阻塞性问题。
9. 项目在 `dev` 分支完成；每个已完成且通过相关验证的 TODO 均按规定创建独立 commit；没有自动 push。

Island 与 Desktop Magnet 的完整验收分别作为后续版本里程碑，不得为了宣称 Core MVP 完成而伪称已经交付。
