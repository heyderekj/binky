# Binky — 功能清单

> 基于源码全面分析，涵盖 app target、BinkyCore 包、CLI、测试覆盖。

---

## 1. 核心排序引擎

### 1.1 Quick Sort（一键整理）
- **Sort Now** — 一键扫描任意文件夹，默认 `~/Downloads`
- **Sort All** — 一次性扫描所有启用的 Routines
- **文件夹选择器** — 临时选择任意文件夹进行排序
- **拖放区域** — 拖拽文件到主窗口触发排序
- **Open Files 面板** — 通过文件选择器指定文件

### 1.2 排序管线（Pipeline）
每个文件经过以下步骤：
1. 临时/未完成文件检测（.crdownload, .part, .tmp, 隐藏文件）
2. 稳定性等待（轮询文件大小/mtime 直到不再变化）
3. 排除检查（扩展名 + 文件名片段）
4. 全局跳过标签检查
5. 加载文件信号（大小、日期、下载来源）
6. 读取现有 Finder 标签
7. 确定收件箱根目录 + 活跃规则（通过 WatchPipelineRegistry 路由）
8. 重复检测（SHA-256 + 感知哈希）
9. 分类（基于扩展名/UTType）
10. 内容检查（OCR/收据识别，按需）
11. 规则匹配（首次匹配优先）
12. 动作执行（移动/压缩/解压/DMG安装/标签扇出/重命名/删除）
13. Finder 标签组合 + 应用
14. "New" 标签过期注册
15. 排序后 Shortcut 调用
16. 哈希记录（用于未来重复检测）

### 1.3 文件分类目标（13 类）
| 类别 | 子文件夹 | 示例扩展名 |
|------|----------|-----------|
| Images | Images/ | jpg, png, gif, webp, svg, heic |
| PDF | PDFs/ | pdf |
| Video | Media/ | mp4, mov, m4v, avi |
| Audio | Media/ | mp3, m4a, wav, flac |
| Documents | Documents/ | doc, txt, md, xls, csv |
| Archives | Archives/ | zip, rar, 7z, tar, gz |
| Apps | Apps/ | dmg, pkg, app |
| Screenshots | Screenshots/ | 按文件名模式匹配 |
| Receipts | Receipts/ | OCR/启发式识别 |
| Duplicates | Duplicates/ | SHA-256/感知哈希匹配 |
| Folders | (可配置) | 松散目录 |
| Misc | Misc/ | 其他已知扩展名 |
| Review | Review/ | 未知/可疑扩展名 |

### 1.4 文件稳定性检查
- 轮询文件大小/修改时间直到连续 2 个周期无变化
- 快速路径：mtime ≥3 秒前的文件跳过轮询
- 目录稳定性检查（同理）
- 超时后标记为 skippedStableCheckTimeout

### 1.5 碰撞安全移动
- Finder 风格文件名唯一化（追加 " 2", " 3" 等）
- 每目标目录锁（PerDestinationUniquifyGate）防止并发冲突

---

## 2. Routines（命名监视器）

- **多个命名预设** — 每个有独立源文件夹、规则、启用/禁用开关
- **单独扫描** — 从菜单栏或侧边栏触发单个 Routine
- **侧边栏状态** — 实时状态点（绿/橙/灰）、启用/禁用眼睛图标
- **Routine 模板** — 如 "Calm Desktop" 入门模板
- **每 Routine 自定义 Finder 标签**
- **每 Routine 排序后 Shortcut**
- **每 Routine 应用安装路径**
- **标签扇出优先级** — 每 Routine 可配置

---

## 3. Watch 模式（持续监控）

- **FSEvents 监视器** — 实时监控文件夹变化
- **防抖入库** — 等待突发结束后排序（0.8s 静默 / 1.5s 上限）
- **暂停/恢复** — 从侧边栏、菜单栏或设置切换
- **多文件夹监控** — 同时监控所有启用 Routine 的源文件夹
- **一级递归** — 可选监控直接子文件夹
- **规则变更自动重排** — 修改路由规则后自动重新排序

---

## 4. 路由规则系统

### 4.1 匹配条件
| 条件 | 说明 |
|------|------|
| 扩展名匹配 | 小写，无点号 |
| 文件名包含 | 大小写不敏感子串 |
| 文件类型过滤 | UTType 感知：image/movie/audio/archive/pdf/document/any |
| 大小范围 | 最小/最大字节数 |
| 添加日期 | 比 N 天新/旧 |
| 来源域名 | WhereFroms 主机通配符（`*.example.com`） |
| 内容匹配 | OCR 文本存在、收据启发式 |
| Finder 标签匹配 | 文件必须携带至少一个指定标签 |

### 4.2 动作类型（7 种）
1. **moveToDestination** — 移动到收件箱根目录下的相对路径
2. **moveToTrash** — 发送到废纸篓
3. **renameInPlace** — 原地重命名
4. **zipToDestination** — 压缩到目标位置，删除原文件
5. **extractAndTrash** — 解压到目标位置，删除原压缩包
6. **installFromDMG** — 挂载 DMG，复制 .app 到 Applications，删除 DMG
7. **tagFanout** — 按 Finder 标签路由到子文件夹

### 4.3 重命名模板
支持 token：`{date}`, `{stem}`, `{ext}`, `{newExt}`, `{n}`, `{counter}`, `{origin}`, `{ocr}`, `{vendor}`, `{amount}`

### 4.4 规则合成器
- macOS 26：使用 Foundation Models 从自然语言生成规则
- 回退：基于启发式的规则生成

---

## 5. Review 文件夹（未知文件审查）

- **审查分流表** — 检查未知/可疑文件
- **移动到类别** — 手动路由到任意目标
- **创建规则** — 从审查文件属性生成路由规则
- **删除** — 废纸篓处理
- **来源提示** — 显示下载来源（WhereFroms）
- **工具栏徽章** — 有审查文件时显示按钮

---

## 6. 智能排序功能

### 6.1 重复检测
- **SHA-256 字节哈希** — 精确重复
- **dHash64 感知哈希** — 图片近似重复（汉明距离 ≤10）
- **SQLite 存储** — 跨排序会话持久化
- **处理模式** — 关闭 / 移动到 Duplicates / 移动到废纸篓

### 6.2 智能截图命名
- Vision OCR 识别截图内容
- ≥3 个单词时生成 slugified 标题替代默认文件名

### 6.3 收据检测
- 关键词匹配（invoice/receipt/total/paid）
- 货币模式识别
- 来源主机 → 商家/金额提取
- 自动路由到 Receipts 文件夹

### 6.4 内容检查器
- Vision OCR（图片降采样缩略图）
- PDFKit 文本提取 + 回退 OCR
- NSCache 缓存（80 条目，按文件哈希）

### 6.5 松散文件夹移动
- 非目标目录作为整体移动
- .app bundle 视为文件处理

### 6.6 慢速模式
- 逐个文件排序，带延迟
- 用于演示或建立信任

---

## 7. Finder 标签

- **排序时自动标签** — 路由过程中应用 Finder 标签
- **每类别默认标签** — 可配置每个目标类别的标签
- **"New" 标签 + TTL** — 自动应用，N 天后自动移除
- **标签扇出** — 按现有 Finder 标签路由到子文件夹
- **全局跳过标签** — 带指定标签的文件不参与排序
- **标签优先级** — 内置 < 全局默认 < 预设覆盖 < 规则替换 < 规则追加

---

## 8. 文件老化（Stale File Management）

- **类别老化规则** — 未触碰 N 天后归档或删除
- **每日定时器** — 每 24 小时扫描一次
- **归档日期文件夹** — 移动到 Archive/YYYY-MM/ 结构
- **预览候选** — 执行前显示受影响文件

---

## 9. 历史与撤销

- **会话历史** — 最多 50 条排序记录
- **每会话统计** — 文件数、移动字节数、类别、来源主机
- **重新打开摘要** — 查看任意历史批次详情
- **撤销移动** — 反转整个批次的所有移动操作
- **清除历史** — 一键清空
- **Routine 名称标签** — 显示产生该会话的 Routine

---

## 10. 排序预览（Dry Run）

- **预览表** — 显示文件将去往何处，不实际移动
- **侧边栏预览按钮** — 快速检查
- **每文件 "why" 列** — 解释路由决策
- **CLI 支持** — `binky preview` 命令

---

## 11. CLI（命令行工具）

| 命令 | 功能 |
|------|------|
| `binky sort [paths...]` | 排序指定文件/文件夹 |
| `binky preview [paths...]` | 预览排序结果（不移动） |
| `binky undo [--batch <uuid>]` | 撤销排序批次 |
| `binky routines list` | 列出所有 Routines 及状态 |
| `binky routines run <name>` | 运行指定 Routine |
| `binky tag [paths...]` | 应用 Finder 标签（不移动） |
| `binky version` | 显示版本 |
| `binky help` | 显示帮助 |

**通用标志：** `--json`, `--quiet`, `--dry-run`, `--root <path>`

**跨进程锁** — app 和 CLI 共享 POSIX flock，防止并发排序。

---

## 12. 系统集成

### 12.1 Finder Services / Quick Actions
- **"Sort with Binky"** — 右键 → 服务
- **Open With / Dock 拖放** — 接受文件 URL

### 12.2 Apple Shortcuts
- **Sort Files Intent** — AppIntent 接受文件参数
- **AppShortcutsProvider** — Shortcuts app 中的建议短语

### 12.3 全局热键
- Carbon 热键注册 — 系统级快捷键激活 Binky
- 自定义快捷键录制器（AppKit NSView）
- 冲突检测 + 系统保留键警告

### 12.4 Launch at Login
- SMAppService（macOS 13+）登录项注册
- 实时状态检测

### 12.5 菜单栏
- **状态栏图标** — Sort Now / 暂停 / 显示 / 设置 / 历史 / 退出
- **每 Routine 子菜单** — 单独排序
- **实时进度 %** — 排序时图标旁显示百分比
- **纯菜单栏模式** — 隐藏 Dock 图标

---

## 13. 排序进度与控制

- **动画进度条** — 品红色动画条 + 百分比
- **暂停/恢复/停止** — 排序中控制（横幅、表单、菜单栏）
- **Currently Sorting 表单** — 每文件详情 + 脉冲动画
- **最小可见时长** — 小批次进度至少显示 0.9 秒
- **能量感知节奏** — 热临界/低电量模式时暂停

---

## 14. 能量管理

- **低电量模式暂停** — LPM 激活时暂停排序
- **热临界暂停** — Mac 过热时暂停
- **大批次阈值** — 可配置文件数（50–10,000）
- **节流配置** — auto / gentle / aggressive
- **文件间休眠** — 根据热状态和配置动态调整

---

## 15. 应用内更新

- **GitHub Releases 轮询** — 24 小时节流检查新版本
- **更新横幅** — 显示可用版本 + 安装/新功能/忽略
- **应用内安装** — 下载 zip → 暂存 → 通过延迟 shell 脚本替换 bundle
- **手动检查** — Help 菜单触发

---

## 16. 诊断与崩溃报告

- **崩溃哨兵** — 检测非正常退出
- **MetricKit 订阅** — 接收 Apple 崩溃诊断（可选）
- **崩溃后表单** — 提供邮件报告 / GitHub Issue / 忽略
- **预填 URL** — 诊断上下文自动填入

---

## 17. 每周摘要与分享

- **每周摘要模型** — 汇总排序文件数、移动次数、热门类别
- **分享卡片** — 600×300 品牌 PNG
- **复制/保存 PNG** — 剪贴板或文件导出
- **每周通知** — 本地通知 + 摘要
- **每日摘要通知** — 当天总计

---

## 18. 设置窗口（15+ 面板）

### General 分组
| 面板 | 内容 |
|------|------|
| Behavior | 启动行为、Dock/菜单栏模式 |
| Notifications | 排序完成、摘要通知开关 |
| Energy | 低电量/热暂停、节流配置 |
| Privacy | 历史清除、哈希数据库清除 |
| Pro Tools | 诊断、高级选项 |
| Support | 帮助链接、反馈 |

### Sorting 分组
| 面板 | 内容 |
|------|------|
| Watch Folder | 全局监控文件夹配置 |
| Smart & Pace | 重复检测、截图命名、收据、慢速模式 |
| Routing | 自定义规则管理 |
| Stale Files | 文件老化规则 |
| Never Sort | 排除扩展名/文件名 |
| Preview | 预览设置 |
| Routines | Routine 管理 |

### Interface 分组
| 面板 | 内容 |
|------|------|
| Shortcuts | 自定义键盘快捷键 |
| Appearance | 外观设置 |

---

## 19. UI 与外观

- **Liquid Glass** — macOS 26 `.glassEffect()`，旧版回退 `.ultraThinMaterial`
- **透明窗口** — 毛玻璃主窗口背景
- **品牌色** — `#e3366e` 品红色
- **侧边栏样式** — Simple（仅 Quick Sort）/ Expanded（两者）
- **主窗口模式** — Quick Sort / Routines / Both
- **减少动画** — 尊重系统 + 应用级开关
- **空状态动画** — 文件卡片飞向目标桶（使用真实排序数据）
- **闲置动画** — 拖放区浮动卡片堆叠

---

## 20. Dinky Bridge（姐妹应用）

- 检测 Dinky 是否安装
- 将可压缩文件发送到 Dinky
- Watch 文件夹交接
- 排序结果中的 "Send to Dinky" 按钮

---

## 21. 本地化

- **12 个语言** — en, de, es, fr, it, ja, ko, nl, pt-BR, ru, tr, zh-Hans, zh-Hant
- **String(localized:comment:)** — 现代本地化 API
- **Localizable.xcstrings** — UI 字符串目录
- **InfoPlist.xcstrings** — Info.plist 本地化
- **Help.md** — 12 语言版本

---

## 22. 安全与权限

| 权限 | 用途 |
|------|------|
| 非沙盒 | 完整文件系统访问 |
| files.user-selected.read-write | 读写用户选择的文件 |
| files.downloads.read-write | 读写 ~/Downloads |
| network.client | 出站网络（更新检查） |

---

## 23. 构建与发布

- **Universal Binary** — arm64 + x86_64
- **最低版本** — macOS 14 Sonoma
- **SwiftPM 包** — BinkyCore（4 个 target）
- **release.sh** — 自动化版本号、构建、DMG/zip、Homebrew cask、GitHub Release
- **Homebrew cask** — `brew install --cask binky`
- **CI** — macOS 26 + Xcode 26，`xcodebuild test`

---

## 24. 测试覆盖

| 测试文件 | 覆盖功能 |
|----------|----------|
| WhereFromsTests | 域名匹配、来源标签、xattr 读取 |
| DownloadSortClassificationTests | 文件分类、截图检测、临时文件处理 |
| RoutinesOverhaulTests | 规则匹配、标签扇出、重命名模板、解压服务、Watch 管线 |
| FinderTagCompositionTests | 标签优先级、覆盖逻辑、向后兼容解码 |

---

## 25. 未来/存根功能

- **订阅层级** — Free / Plus（UserDefaults 枚举，2.0 许可证准备）
- **Binky 2.0 许可证** — 一次性购买 + 可选年度续订更新
- **Binky + Dinky 捆绑** — 计划中的家庭套装
