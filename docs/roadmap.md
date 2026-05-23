# Binky — Roadmap

> 基于审计报告四轮修复 + v1.6/v1.7 实现后的项目状态。

---

## 已完成（v1.5.x 安全加固 + v1.6 质量 + v1.7 设计系统）

### 安全加固（Round 1–4）
- ✅ tar/zip 解压路径穿越防护
- ✅ 应用更新三层签名验证（codesign + BID + team identity）
- ✅ DMG 安装原子化（staging → replaceItemAt）
- ✅ zip 完整性验证后再删源
- ✅ SQLite 持久连接 + WAL + 感知哈希内存索引
- ✅ FSEvents 后台队列
- ✅ ContentInspector OCR 优化 + NSCache 清理
- ✅ 更新脚本时序竞争修复（mv 备份 + 回滚）
- ✅ EnergyConditions / digestFile 取消支持
- ✅ 临时文件检测扩展（.crswap/.opdownload/.aria2/.!ut/~$）
- ✅ 无障碍标签补齐 + 错误反馈 UI + 动画生命周期
- ✅ release.sh --no-push 安全模式
- ✅ 测试覆盖 13 → 49 用例

### v1.6 质量收尾（6/7）
- ✅ Zip 炸弹防护（zipinfo 预检，ratio >100:1 或 >10GB 拒绝）
- ✅ PostSortShortcutRunner URL 编码（URLComponents）
- ✅ .rar/.7z 规则 UI 警告
- ✅ 偏好缓存 KVO 失效修复（UserDefaults.didChangeNotification）
- ✅ FolderWatcher passUnretained（消除保留循环）
- ✅ WhereFromsReader XATTR_NOFOLLOW
- ⏳ Sheet 状态机重构（5 Bool → enum）— 延后，单独 PR

### v1.7 设计系统（6/6）
- ✅ 品牌色 NSColor 动态适配 + Asset Catalog 优先
- ✅ BinkyLinkButtonStyle 统一链接按钮组件
- ✅ FinderTag 编辑器自适应列宽
- ✅ WeeklyDigestShareCard 响应式布局
- ✅ 侧边栏/Help 最小宽度放宽（非英语截断修复）
- ✅ settingsHelperText 对比度修复（.secondary 11pt）

---

## 短期（v1.8）

| 优先级 | 任务 | 工作量 |
|--------|------|--------|
| P1 | Sheet 状态机重构（5 Bool → 1 enum ActiveSheet?） | 3h |
| P2 | DropZoneView 闲置动画随可见性暂停 | 1h |
| P2 | OrganizerEmptyStateView 动画 Task 取消安全 | 1h |
| P3 | 测试覆盖：撤销操作、Watch 防抖、完整 pipeline 集成 | 1d |

---

## 中期（v2.0 — 功能演进）

| 方向 | 内容 |
|------|------|
| **许可证系统** | 一次性购买 + 年度续订更新（存根已在代码中） |
| **Binky + Dinky 捆绑** | 家庭套装定价 |
| **规则合成 v2** | Foundation Models（macOS 26）自然语言 → 规则 |
| **Watch 文件夹 v2** | 递归深度可配、排除子目录模式 |
| **iCloud 同步** | Routines + Rules 跨设备同步（CloudKit） |
| **Finder Extension** | 原生 Finder 侧边栏集成 |
| **性能仪表盘** | 排序耗时趋势、哈希库大小、能量消耗 |
| **插件系统** | 第三方 action（ImageMagick、ffmpeg 等） |

---

## 技术债务（持续）

- CI 稳定性：修复 LaunchServices "Could not launch BinkyTests" retry
- `tools/` Python 脚本路径从 Dinky 改为 Binky
- 文档：`docs/local-cli.md` 更新 CLI 新命令（tag、routines run）
