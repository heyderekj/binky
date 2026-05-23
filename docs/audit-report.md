# Binky — 系统性审计报告

> 基于源码全面分析，覆盖性能、架构、Bug、安全、UI/UX 五大维度。

---

## 严重程度定义

| 级别 | 含义 |
|------|------|
| 🔴 CRITICAL | 数据丢失、安全漏洞、必现崩溃 |
| 🟠 HIGH | 功能异常、性能严重退化、潜在数据丢失 |
| 🟡 MEDIUM | 体验问题、资源泄漏、边缘 case |
| 🟢 LOW | 代码质量、微小体验瑕疵 |

---

## 一、安全问题

### 🔴 1. tar 解压路径穿越 — 任意文件写入

**文件：** `BinkyCore/Sources/BinkyCoreSort/ArchiveExtractionService.swift`

```swift
p.arguments = ["-xf", source.path, "-C", destinationDirectory.path]
```

macOS 的 `tar` 默认不阻止路径穿越。恶意 `.tar.gz` 可包含 `../../../.ssh/authorized_keys` 等条目，解压后覆盖用户任意可写文件。

**触发场景：** 用户配置了 `extractAndTrash` 规则，Downloads 中出现恶意 tar 包。

**修复：** 添加 `--one-top-level` 或 `--strip-components`，或解压后验证所有文件路径在目标目录内。

---

### 🔴 2. 应用内更新无代码签名验证

**文件：** `Binky/Services/UpdateChecker.swift`

更新机制从 GitHub 下载 zip/DMG，解压后直接替换运行中的 app bundle，**零签名验证**。安装脚本还主动移除 quarantine 属性：

```bash
xattr -rd com.apple.quarantine ...
```

**风险：** GitHub 账号被盗或 CDN 中间人攻击时，任意代码可替换应用。

**修复：** 解压后执行 `codesign --verify --deep --strict`。

---

### 🟠 3. 符号链接跟随 — 移动监控目录外的文件

**文件：** `BinkyCore/Sources/BinkyCoreSort/SortPipeline.swift`

```swift
let standardized = url.standardizedFileURL  // 解析符号链接
try fm.moveItem(at: standardized, to: target)
```

如果 Downloads 中有指向 `/etc/` 或其他目录的符号链接，Binky 会移动链接目标文件。

**修复：** 检测符号链接并跳过，或验证解析后路径仍在监控目录内。

---

### 🟠 4. Zip 炸弹无防护

**文件：** `ArchiveExtractionService.swift`

使用 `ditto -x -k` 解压 zip 时无大小限制检查。一个 42KB 的 zip 可展开为 4.5PB。

**修复：** 解压前检查压缩比，或设置目标目录磁盘配额/大小上限。

---

## 二、数据安全问题

### 🔴 5. DMG 安装：先删旧 app 再复制新 app

**文件：** `BinkyCore/Sources/BinkyCoreSort/DMGInstallerService.swift`

```swift
if fm.fileExists(atPath: dest.path) {
    try fm.removeItem(at: dest)  // 旧 app 已删
}
try fm.copyItem(at: appURL, to: dest)  // 如果失败（磁盘满）→ 数据丢失
```

**修复：** 先复制到临时位置，成功后原子交换（rename）。

---

### 🟠 6. zip 压缩后删除源文件无完整性验证

**文件：** `SortPipeline.swift` — `SortZipViaDitto`

```swift
guard p.terminationStatus == 0 else { throw ... }
try fm.removeItem(at: sourceFile)  // ditto 返回 0 不保证 zip 完整
```

磁盘满时可能产生截断的 zip，但 ditto 仍返回 0。

**修复：** 验证 zip 文件大小 > 0 且可正常打开。

---

### 🟠 7. 应用更新时序竞争

**文件：** `UpdateChecker.swift`

延迟安装脚本有 10 秒超时。如果 app 未在 10 秒内退出（如 sheet 阻塞 terminate），脚本仍会 `rm -rf` 运行中的 app bundle。

---

## 三、性能问题

### 🔴 8. 感知哈希重复检测全表扫描

**文件：** `FileHashStore.swift` — `scanNearImageDuplicate`

```swift
let sql = "SELECT path, perceptual_hex FROM file_hashes WHERE is_image = 1 AND perceptual_hex IS NOT NULL;"
// 遍历所有图片记录计算汉明距离
```

对每张新图片执行 O(n) 全表扫描。用户排序过 10,000 张图片后，每张新图片需读取 10,000 行。50 张图片的批次 = 500,000 次行读取。

**修复：** 内存缓存哈希集合，或使用 LSH（局部敏感哈希）索引。

---

### 🔴 9. SQLite 每次操作开关连接

**文件：** `FileHashStore.swift`

```swift
public func lookup(...) -> LookupResult {
    guard let db = openDB() else { ... }
    defer { sqlite3_close(db) }
    // ...
}
```

每次 `lookup()` 和 `recordSortedFile()` 都开关一次 SQLite 连接。100 文件批次 = ~200 次连接开关。

**修复：** 保持持久连接，`init` 时打开，`deinit` 时关闭。启用 WAL 模式。

---

### 🟠 10. FSEvents 回调在主线程执行文件 I/O

**文件：** `Binky/Services/FolderWatcher.swift`

```swift
FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
```

回调中执行 `fileExists` 和 `resourceValues` 系统调用，阻塞主线程。监控目录大量文件变化时（如解压 zip）导致 UI 卡顿。

**修复：** 将 stream 分派到后台队列，仅最终回调跳转主线程。

---

### 🟠 11. 图片文件双重读取

**文件：** `FileHashStore.swift` — `digestFile`

对图片文件：先完整读取计算 SHA-256，再通过 `CGImageSourceCreateWithURL` 重新读取计算感知哈希。50MB RAW 文件被读取两次。

**修复：** 从已加载数据计算感知哈希，或使用 mmap。

---

### 🟠 12. 非文本图片双重 OCR

**文件：** `ContentInspector.swift`

```swift
let text = await recognizeText(on: cg, accurate: false)
let merged = text.isEmpty ? await recognizeText(on: cg, accurate: true) : text
```

照片（无文本）会触发两次 OCR：快速模式返回空 → 精确模式仍返回空。精确模式显著更慢。

**修复：** 对快速模式返回空的情况，跳过精确模式回退（或添加轻量预检）。

---

### 🟡 13. NSCache 外加不必要的 NSLock

**文件：** `ContentInspector.swift`

`NSCache` 本身线程安全，外层 `cacheLock` 造成不必要的串行化，降低 8 并发 worker 的并行度。

---

### 🟡 14. 视图 body 中执行文件系统 I/O

**文件：** `OrganizerMainView.swift`

`reviewFolderItemCount` 是计算属性，每次 view body 求值时调用 `FileManager.contentsOfDirectory`。`sortHistoryRows` 每次求值时执行 JSON 解码。

**修复：** 改为 `@State` + 事件驱动刷新。

---

### 🟡 15. 无 WAL 模式

**文件：** `FileHashStore.swift`

默认 rollback journal 模式，读写互斥。

---

## 四、并发与稳定性问题

### 🟠 16. Pipe 死锁 — hdiutil 输出

**文件：** `DMGInstallerService.swift`

```swift
try p.run()
p.waitUntilExit()  // 阻塞等待进程退出
let data = pipe.fileHandleForReading.readDataToEndOfFile()  // 之后才读
```

如果 hdiutil 输出超过 pipe 缓冲区（~64KB），进程等待 pipe 被消费，调用方等待进程退出 → 死锁。

**修复：** 先读 pipe 再 waitUntilExit，或并发读取。

---

### 🟠 17. 跨进程锁 fd 双重关闭

**文件：** `SortCrossProcessLock.swift`

```swift
public func unlock() {
    guard fd >= 0 else { return }  // 无锁保护
    close(fd)
    fd = -1
}
```

并发调用 `unlock()` 可能双重关闭 fd，内核可能已将该 fd 分配给其他文件。

---

### 🟠 18. EnergyConditions continuation 泄漏

**文件：** `EnergyConditions.swift`

```swift
waiters.append(continuation)  // Task 被取消时 continuation 永不 resume
```

`withCheckedContinuation` 不支持取消。如果 Task 被取消，continuation 永远挂起，泄漏资源。

**修复：** 使用 `withTaskCancellationHandler`。

---

### 🟡 19. FolderWatcher Unmanaged 保留循环

**文件：** `FolderWatcher.swift`

```swift
let retained = Unmanaged.passRetained(self).toOpaque()
```

`deinit` 中调用 `stop()` 释放，但如果保留循环存在，`deinit` 永远不会触发 — 经典死锁模式。依赖外部显式调用 `stop()`。

---

### 🟡 20. TOCTOU：uniquify 与 move 之间的间隙

**文件：** `SortPipeline.swift`

`PerDestinationUniquifyGate` 只保护同进程内的并发。CLI 进程和外部程序（Finder）不受保护，可能在 uniquify 后、move 前创建同名文件。

---

### 🟡 21. 偏好缓存失效问题

**文件：** `BinkyPreferences.swift`

`cachedGlobalSkipTags`、`cachedSavedPresets` 等缓存仅在 setter 时失效。CLI 通过 UserDefaults 修改偏好时，app 读取到过期缓存。

---

## 五、UI/UX 问题

### 无障碍（Accessibility）

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🔴 | Routine 眼睛切换按钮无 accessibilityLabel | OrganizerMainView.swift |
| 🔴 | 排序失败无任何错误 UI | OrganizerMainView.swift handleDrop |
| 🟠 | ReviewFolderTriageSheet 操作失败仅 beep，无视觉反馈 | ReviewFolderTriageSheet.swift |
| 🟠 | WeeklyDigestShareCard 无无障碍表示 | WeeklyDigestShareCard.swift |
| 🟠 | `.foregroundStyle(.tertiary)` 10pt 文字对比度不足 | SettingsChrome.swift |
| 🟠 | `.foregroundStyle(.quaternary)` 信息文字几乎不可见 | OrganizerMainView.swift |
| 🟡 | 活动行未使用 `.accessibilityElement(children: .combine)` | OrganizerMainView.swift |
| 🟡 | 历史列表行 VoiceOver 导航碎片化 | HistorySheet.swift |

### 布局与适配

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🟠 | WeeklyDigestShareCard 固定 600×300，窄窗口裁切 | WeeklyDigestShareCard.swift |
| 🟠 | FinderTag 编辑器固定列宽，德语/日语截断 | PreferencesView.swift |
| 🟡 | 侧边栏 240pt 最小宽度可能截断长 Routine 名 | OrganizerMainView.swift |
| 🟡 | Help 窗口侧边栏 180pt 最小宽度，非英语截断 | HelpWindow.swift |

### 状态管理

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🟠 | `reviewFolderItemCount` 每次 body 求值执行文件 I/O | OrganizerMainView.swift |
| 🟠 | `sortHistoryRows` 每次 body 求值执行 JSON 解码 | OrganizerMainView.swift |
| 🟡 | `DiagnosticsReporter.shared` 作为 @ObservedObject 触发全局重绘 | ContentView.swift |
| 🟡 | `SortProgressTracker.shared` 高频发布导致频繁 body 求值 | OrganizerMainView.swift |

### 交互设计

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🟠 | "Clear" 历史无确认对话框（不可逆操作） | OrganizerMainView.swift |
| 🟠 | Preview 按钮无 loading 状态，操作期间可重复点击 | OrganizerMainView.swift |
| 🟠 | SortPreviewSheet 空结果无说明文字 | SortPreviewSheet.swift |
| 🟡 | 设置窗口自定义前进/后退按钮不符合 macOS 标准 | PreferencesView.swift |
| 🟡 | 5 个 .sheet() 修饰符在同一视图层级，可能出现 dismiss 竞争 | OrganizerMainView.swift |
| 🟡 | ReviewTriageSheet 中 "Make a rule" 打开嵌套 sheet | ReviewFolderTriageSheet.swift |

### 视觉一致性

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🟡 | 按钮样式不统一：borderedProminent / bordered / plain 混用 | 多处 |
| 🟡 | 链接样式三种写法混用 | 多处 |
| 🟡 | 品牌色 #e3366e 固定 RGB，暗色模式下未适配 | SettingsChrome.swift |
| 🟡 | `.primary.opacity(0.03)` 卡片背景暗色模式下几乎不可见 | OrganizerMainView.swift |

### 动画性能

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🟠 | TimelineView 30fps 旋转动画不随视图可见性暂停 | View+AdaptiveGlass.swift |
| 🟠 | PulsePinkRowBar 35fps 动画多实例并发运行 | CurrentlySortingSheet.swift |
| 🟡 | DropZoneView 闲置动画在不可见时仍运行 | DropZoneView.swift |
| 🟡 | EmptyStateView 动画 Task 取消可能留下不一致状态 | OrganizerEmptyStateView.swift |

---

## 六、功能缺陷

| 严重度 | 问题 | 说明 |
|--------|------|------|
| 🟡 | .rar/.7z 解压规则静默失败 | 分类为 archive 但 extract 不支持，报 skippedError |
| 🟡 | PostSortShortcutRunner URL 注入 | Shortcut 名含 `#` 时 URL 被截断 |
| 🟡 | hdiutil 输出解析脆弱 | 依赖 tab 分隔和 "/Volumes/" 字符串匹配 |
| 🟡 | xattr 读取 TOCTOU | 大小查询和读取之间 xattr 可能变化 |
| 🟡 | 排序后记录字节数不准确 | 读取目标路径文件大小，可能已被移动/删除 |

---

## 七、架构建议

### 高优先级

1. **SQLite 持久连接 + WAL 模式** — 消除每操作开关连接开销，提升并发读性能
2. **感知哈希索引** — 用 LSH 或内存缓存替代全表扫描
3. **FSEvents 后台队列** — 将文件 I/O 移出主线程
4. **Pipe 读取顺序修复** — 所有 Process 使用先读后 wait 模式
5. **tar 解压安全加固** — 路径验证或 `--one-top-level`

### 中优先级

6. **更新签名验证** — `codesign --verify` 在替换前
7. **DMG 安装原子化** — 先复制到临时位置再 rename
8. **视图 body I/O 消除** — reviewFolderItemCount 等改为事件驱动
9. **动画生命周期管理** — TimelineView 随可见性暂停/恢复
10. **无障碍标签补全** — 所有图标按钮添加 accessibilityLabel

### 低优先级

11. **FolderWatcher 改用 passUnretained** — 消除保留循环风险
12. **EnergyConditions 支持 Task 取消** — withTaskCancellationHandler
13. **偏好缓存 KVO 失效** — 监听 UserDefaults 变更通知
14. **按钮/链接样式统一** — 建立设计系统组件
15. **品牌色暗色模式适配** — 使用 Asset Catalog 颜色

---

## 统计摘要

| 维度 | 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low |
|------|-------------|---------|-----------|--------|
| 安全 | 2 | 2 | — | — |
| 数据安全 | 1 | 2 | — | — |
| 性能 | 2 | 3 | 3 | — |
| 并发/稳定性 | — | 3 | 3 | — |
| UI/UX | 2 | 10 | 16 | — |
| 功能缺陷 | — | — | 5 | — |
| **合计** | **7** | **20** | **27** | — |
