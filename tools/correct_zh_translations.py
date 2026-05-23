#!/usr/bin/env python3
"""Manual corrections for zh-Hans and zh-Hant MT output.

Covers: macOS standard terms, software terminology, wrong-sense fixes,
Binky brand-name leaks (宾基→Binky), and UI convention alignment.

Run after fill_xcstrings_translations.py and fix_brand_in_xcstrings.py.
Idempotent — every override is a fixed value.
"""
import json
import sys
from pathlib import Path

# Centralized in `_paths.py` so this script is portable across checkouts.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _paths import XCSTRINGS_PATH as CAT

# ── Per-key zh-Hans overrides ────────────────────────────────────────────────

ZH_HANS = {
    # ── macOS standard UI terms ──────────────────────────────────────────────
    "Appearance": "外观",
    "General": "通用",
    "Find": "查找",
    "Find Next": "查找下一个",
    "Find Previous": "查找上一个",
    "Cut": "剪切",
    "Save": "保存",
    "Dismiss": "关闭",
    "Remove": "移除",
    "Name": "名称",
    "Name: %@": "名称：%@",
    "Off": "关闭",
    "Done": "完成",
    "New": "新建",
    "New Tab": "新建标签页",
    "Preferences": "偏好设置",
    "Settings": "设置",
    "Print": "打印",
    "Select All": "全选",
    "Minimize": "最小化",
    "Close Window": "关闭窗口",
    "Cycle Windows": "切换窗口",
    "Get Info": "显示简介",
    "Hide App": "隐藏 App",
    "Quit App": "退出 App",
    "Copy": "拷贝",
    "Paste": "粘贴",
    "Redo": "重做",
    "Cancel": "取消",
    "Delete": "删除",
    "Install": "安装",
    "Reset": "还原",
    "Retry": "重试",
    "Add": "添加",
    "Edit": "编辑",
    "Open…": "打开…",
    "Open Files…": "打开文件…",
    "Choose…": "选取…",
    "Choose Folder…": "选取文件夹…",
    "Choose folder": "选取文件夹",
    "Choose Folder": "选取文件夹",
    "Choose source folder": "选取源文件夹",
    "Choose Applications folder": "选取应用程序文件夹",
    "Help": "帮助",
    "Binky Help": "Binky 帮助",
    "OK": "好",
    "Nice": "不错",
    "Got it": "知道了",
    "Back": "后退",
    "Forward": "前进",
    "Close": "关闭",
    "Default": "默认",
    "Customize": "自定义",
    "Accessibility": "辅助功能",
    "Notifications": "通知",
    "Privacy": "隐私",
    "Layout": "布局",
    "Interface": "界面",
    "Keyboard shortcuts…": "键盘快捷键…",

    # ── Software / crash terminology ─────────────────────────────────────────
    "Crash diagnostics": "崩溃诊断",
    "Crash — Binky": "崩溃 — Binky",
    "Crash report — Binky": "崩溃报告 — Binky",
    "Crash diagnostics from Apple are available for this device. Nothing was sent automatically — use the buttons below if you want to share them.":
        "Apple 的崩溃诊断已在此设备上可用。不会自动发送任何内容——如果需要分享，请使用下方按钮。",
    "Share crash diagnostics with Binky": "与 Binky 共享崩溃诊断",
    "Apple diagnostic summary": "Apple 诊断摘要",
    "Binky crashed last time": "Binky 上次崩溃了",
    "Previous session ended unexpectedly; no Apple diagnostic payload is attached yet.\n\n":
        "上次排序意外结束；尚未附加 Apple 诊断数据。\n\n",
    "Call stack tree (JSON, truncated):\n%@": "调用堆栈树（JSON，已截断）：\n%@",
    "Couldn't phone home.": "无法连接到服务器。",
    "Couldn't mount the update disk image.": "无法挂载更新磁盘映像。",
    "Bug: ": "Bug: ",

    # ── Binky brand name: 宾基 → Binky ──────────────────────────────────────
    "About Binky": "关于 Binky",
    "Binky ": "Binky ",
    "Crash — Binky": "崩溃 — Binky",
    "Feedback — Binky v%@": "反馈 — Binky v%@",
    "Support — Binky v%@": "支持 — Binky v%@",
    "Quit Binky": "退出 Binky",
    "Loving Binky? Leave a review": "喜欢 Binky？来留个评价吧",
    "Fussy folder. Meet Binky.": "杂乱的文件夹？交给 Binky。",
    "Files were screaming. Binky helped.": "文件在尖叫。Binky 搞定了。",
    "Binky'd. Already handled.": "已处理。Binky 搞定了。",
    "Binky's tidying up.": "Binky 在整理中。",
    "Here's what Binky heard.": "这是 Binky 听到的。",
    "Binky watches here and runs the rules below. Different folder than the default? That's the point.":
        "Binky 在此监视并运行下方规则。和默认文件夹不同？这正是重点。",
    "Binky won't touch any file carrying one of these Finder tags — handy for shortcuts or files you've parked on purpose.":
        "带有这些 Finder 标签的文件 Binky 不会碰——适合你刻意保留的文件或快捷方式。",
    "Binky exposes a Sort Files action in the Shortcuts app. Hand files from Finder or other actions through Binky — same routing rules as the main window.":
        "Binky 在快捷指令 App 中提供\"整理文件\"操作。从 Finder 或其他操作将文件交给 Binky——使用与主窗口相同的路由规则。",
    "Binky remembers %lld files.": "Binky 记住了 %lld 个文件。",
    "Binky couldn't reach GitHub. Probably the internet. Try again in a sec?":
        "Binky 无法连接 GitHub。可能是网络问题。稍后再试？",
    "Build `binky` from the `BinkyCore` folder for scripts & Shortcuts. Same rules & prefs — shared lock prevents racing the GUI.":
        "从 `BinkyCore` 文件夹构建 `binky` CLI，用于脚本和快捷指令。规则和偏好相同——共享锁防止与 GUI 冲突。",
    "For watch folders, routines, and full troubleshooting, open Binky Help from the Help menu (%@).":
        "关于监视文件夹、例程和完整故障排除，请从帮助菜单（%@）打开 Binky 帮助。",
    "Approve Binky in System Settings → General → Login Items.":
        "在系统设置 → 通用 → 登录项中批准 Binky。",
    "Open Binky at login": "登录时打开 Binky",
    "Open sorted folder in Dinky": "在 Dinky 中打开已排序文件夹",
    "Couldn't open that folder in Dinky.": "无法在 Dinky 中打开该文件夹。",

    # ── Watching / monitoring ────────────────────────────────────────────────
    "Watching": "监视中",
    "Pause watching": "暂停监视",
    "Resume watching": "恢复监视",
    "Also watch inside immediate subfolders (one level)":
        "同时监视直接子文件夹（一层）",
    "Binky watches here and runs the rules below. Different folder than the default? That's the point.":
        "Binky 在此监视并运行下方规则。和默认文件夹不同？这正是重点。",

    # ── Sorting / organizer terms ────────────────────────────────────────────
    "Sort Now": "立即整理",
    "Quick Sort": "快速整理",
    "Quick Sort and Routines": "快速整理和例程",
    "Quick Sort only": "仅快速整理",
    "Routines only": "仅例程",
    "Review": "待审",
    "Review folder": "待审文件夹",
    "Pending review": "待审核",
    "No sessions yet.": "还没有排序记录。",
    "No sorts yet.": "还没有排序记录。",
    "Resume sort": "继续排序",
    "Resume sorting": "继续排序",
    "Resume sort": "继续排序",
    "Moved": "已移动",
    " moved": " 已移动",
    "Kept": "保留",
    "Duplicate": "重复",
    "Duplicates": "重复项",
    "Dry run": "试运行",
    "Preview sort": "预览排序",
    "Preview sort…": "预览排序…",
    "Currently sorting": "正在排序",
    "No active sorting.": "当前没有排序。",
    "Already got one — filed here.": "已经有了——归档在此。",
    "Already got one.": "已经有了。",
    "Already in the right place.": "已经在正确位置。",
    "Nothing is moved — this is a dry run.": "未移动任何文件——这是试运行。",
    "Nothing is moved yet. Incomplete downloads are treated as skipped.":
        "尚未移动任何文件。未完成的下载视为已跳过。",
    "Incomplete download — skipped for now.": "未完成的下载——暂时跳过。",
    "All caught up.": "已是最新。",
    "All done!": "全部完成！",
    "All quiet. Every folder is Binky'd.": "一切安静。每个文件夹都已整理好。",
    "Nothing in Review. Binky's on top of it.": "待审区没有文件。Binky 已处理完毕。",
    "Nothing old enough to touch yet.": "还没有足够久的文件。",
    "Quiet folders. Nothing to report.": "文件夹很安静。没什么可报告的。",
    "Looks like a receipt.": "看起来像收据。",
    "Looks right. Apply it.": "看起来没问题。应用。",
    "Nothing to paste": "没有可粘贴的内容",
    "Already in the list": "已在列表中",
    "No folder selected": "未选择文件夹",
    "No folder yet": "还没有文件夹",
    "No rules. Binky uses default sorted folders.": "没有规则。Binky 使用默认分类文件夹。",
    "No rules yet. Tap New routing to start from a template.":
        "还没有规则。点击「新建路由」从模板开始。",
    "No custom tags. Sorted files only get Binky's category tags.":
        "没有自定义标签。整理后的文件只获得 Binky 的分类标签。",
    "No aging rules yet. Add one per category you want swept.":
        "还没有老化规则。为你想清理的每个类别添加一条。",
    "No preset; set every field yourself.": "没有预设；请自行设置每个字段。",
    "No suggestions yet. Add a site under More conditions, or rescan.":
        "还没有建议。在\"更多条件\"中添加站点，或重新扫描。",

    # ── Quick actions / toolbar ──────────────────────────────────────────────
    "Quick actions": "快速操作",
    "Action": "操作",
    "Actions": "操作",

    # ── Auto / automatic ─────────────────────────────────────────────────────
    "Auto": "自动",
    "Auto-extract archives": "自动解压归档",
    "Auto-install DMGs": "自动安装 DMG",
    "Automations": "自动化",

    # ── Energy / thermal ─────────────────────────────────────────────────────
    "Energy": "能耗",
    "Aggressive": "积极",
    "Gentle": "轻柔",
    "Pace": "节奏",
    "Batch speed": "批次速度",
    "Large-batch pacing": "大批量调速",

    # ── Archive / file categories ────────────────────────────────────────────
    "Archive": "归档",
    "Archives": "归档",
    "Archive old screenshots": "归档旧截图",
    "Archive stale files": "归档过期文件",
    "Archive subfolder": "归档子文件夹",
    "Archive → %@": "归档 → %@",
    "Extract archives": "解压归档",
    "Images": "图片",
    "Documents": "文档",
    "Screenshots": "截图",
    "Misc": "其他",
    "Docs": "文档",
    "Files": "文件",
    "Folder": "文件夹",
    "Folders": "文件夹",
    "Receipts": "收据",
    "Audio": "音频",
    "PDF": "PDF",

    # ── Settings / prefs ─────────────────────────────────────────────────────
    "All settings": "所有设置",
    "Additional settings": "附加设置",
    "Main layout": "主要布局",
    "Expanded": "展开",
    "Expanded mode keeps both Quick Sort and Routines controls in one sidebar.":
        "展开模式将快速整理和例程控件都放在一个侧边栏中。",
    "Expanded shows both Quick Sort and Routines sections in the sidebar.":
        "展开模式在侧边栏中同时显示快速整理和例程部分。",
    "Menu bar": "菜单栏",
    "Menu bar only (hide Dock icon)": "仅菜单栏（隐藏 Dock 图标）",
    "Menu bar icon stays on — it's how you reach Binky without the Dock.":
        "菜单栏图标保持显示——无需 Dock 即可访问 Binky。",
    "Housekeeping": "清理",
    "Interface": "界面",

    # ── Digest / notifications ───────────────────────────────────────────────
    "Digest hour: %lld": "摘要时间：%lld",
    "Daily digest notification": "每日摘要通知",
    "Roughly Mondays at 9:00 AM (local): a rollup you can screenshot as the digest card.":
        "大约每周一上午 9:00（本地时间）：可截图作为摘要卡片的汇总。",
    "One quiet summary of what Binky handled. Requires notification permission.":
        "Binky 处理内容的简要摘要。需要通知权限。",
    "Notify when done": "完成后通知",
    "Play sound when done": "完成后播放声音",
    "Notification settings…": "通知设置…",

    # ── Rules / routing ──────────────────────────────────────────────────────
    "Routing": "路由",
    "Routing & sorted folders…": "路由和分类文件夹…",
    "Rule": "规则",
    "Rule name": "规则名称",
    "New rule": "新建规则",
    "New routing": "新建路由",
    "Edit rule": "编辑规则",
    "Custom routing rules": "自定义路由规则",
    "Custom tags": "自定义标签",
    "Content match": "内容匹配",
    "Content: %@": "内容：%@",
    "By name": "按名称",
    "By file kind": "按文件类型",
    "By file type.": "按文件类型。",
    "By file type · from %@.": "按文件类型 · 来自 %@。",
    "By Finder tag": "按 Finder 标签",
    "First enabled rule wins. Rules run before automatic sorted folders (Images, Documents, Review folder, etc.).":
        "第一条启用的规则生效。规则在自动分类文件夹（图片、文档、待审文件夹等）之前执行。",
    "Comma-separated tag names (first match wins)":
        "逗号分隔的标签名称（第一个匹配生效）",
    "Category tags when this rule matches": "此规则匹配时的分类标签",
    "Re-sort watched folders when rules change": "规则更改时重新整理监视文件夹",
    "Replace type defaults": "替换类型默认值",
    "Replaces only the type-based tags. Routine tags and \"Tags on match\" still apply after.":
        "仅替换基于类型的标签。例程标签和\"匹配时标签\"之后仍然生效。",
    "Force extension (e.g. md, leave empty to keep)": "强制扩展名（如 md，留空保持不变）",
    "Output extension: .%@": "输出扩展名：.%@",
    "Match downloads from specific sites, route into a folder.":
        "匹配来自特定网站的下载，路由到文件夹。",
    "Destination (relative to watch folder)": "目标（相对于监视文件夹）",
    "Relative path under sort root (empty = \"Folders\")":
        "排序根下的相对路径（留空为\"文件夹\"）",

    # ── Routine terms ────────────────────────────────────────────────────────
    "Routines": "例程",
    "Routine name": "例程名称",
    "Routine: %@": "例程：%@",
    "New routine": "新建例程",
    "Blank routine": "空白例程",
    "Add routine": "添加例程",
    "Delete routine?": "删除例程？",
    "Enable this routine": "启用此例程",
    "Enabled": "已启用",
    "Calm my Desktop": "整理我的桌面",
    "Calm my Desktop…": "整理我的桌面…",
    "Blank": "空白",
    "Open Routines…": "打开例程…",

    # ── Menu bar states ──────────────────────────────────────────────────────
    "Binky — Paused": "Binky — 已暂停",
    "Binky — Paused (%@)": "Binky — 已暂停（%@）",
    "Binky — Paused (Low Power Mode)": "Binky — 已暂停（低电量模式）",
    "Binky — Paused (cooling down)": "Binky — 已暂停（降温中）",
    "Binky — Sorting %lld of %lld": "Binky — 正在整理 %lld/%lld",
    "Binky — Sorting %lld of %lld (%@)": "Binky — 正在整理 %lld/%lld（%@）",
    "Binky — Sorting…": "Binky — 正在整理…",
    "Binky — Stopping…": "Binky — 正在停止…",
    "Paused": "已暂停",
    "Paused — %@": "已暂停 — %@",
    "Paused — Low Power Mode.": "已暂停 — 低电量模式。",
    "Paused — letting things cool off.": "已暂停 — 等待降温。",
    "Pause sort": "暂停排序",
    "Pause sorting": "暂停排序",
    "Pause sorting on Low Power Mode": "低电量模式时暂停排序",
    "Pause sorting when thermal state is critical": "温度过高时暂停排序",
    "Idle": "空闲",

    # ── File status / actions ────────────────────────────────────────────────
    "From Review": "来自待审",
    "From a website": "来自网站",
    "From phrase": "来自短语",
    "From: ": "来自：",
    "From: %@": "来自：%@",
    "From: any": "来自：任意",
    "From %@.": "来自 %@。",
    "Goes to: %@": "发送到：%@",
    "File kind": "文件类型",
    "File kind: %@": "文件类型：%@",
    "Filename contains": "文件名包含",
    "Finder tags: %@": "Finder 标签：%@",
    "Finder tags for %@": "%@ 的 Finder 标签",
    "Date added": "添加日期",
    "Date Added is more than %lld days ago": "添加日期超过 %lld 天前",
    "Date Added is within the last %lld days": "添加日期在最近 %lld 天内",
    "Added more than … days ago": "添加超过…天前",
    "Added within last … days": "最近…天内添加",
    "Expires after": "过期时间",
    "Days: %lld": "天数：%lld",
    "Max size (bytes)": "最大大小（字节）",
    "Min size (bytes)": "最小大小（字节）",
    "Extensions (comma-separated, empty = any)": "扩展名（逗号分隔，留空为任意）",
    "Ignored extensions (comma-separated)": "忽略的扩展名（逗号分隔）",
    "Ignored filename fragments — one per line": "忽略的文件名片段——每行一个",
    "Has Finder tag (comma-separated, any match)": "有 Finder 标签（逗号分隔，任一匹配）",
    "Replacement tags (comma-separated)": "替换标签（逗号分隔）",
    "Leave files tagged:": "保留标签：",
    "Old Screen Shot images": "旧的截图文件",
    "Old Screenshot images": "旧的截图文件",

    # ── Fan out / tag operations ─────────────────────────────────────────────
    "Fan out by tag": "按标签分类",
    "By Finder tag": "按 Finder 标签",
    "Install from disk images": "从磁盘映像安装",
    "Install disk images": "安装磁盘映像",
    "Install update now?": "现在安装更新？",
    "Install Update": "安装更新",
    "Installing…": "正在安装…",
    "Downloading…": "正在下载…",
    "Open .dmg installers and copy the app, then trash the image.":
        "打开 .dmg 安装器并拷贝 App，然后废纸篓映像。",
    "Move / review summary": "移动/待审摘要",
    "Move to Trash": "移到废纸篓",
    "Move to…": "移到…",
    "Move to Duplicates folder": "移到重复文件夹",
    "Move loose folders into the Folders destination": "将散落文件夹移入文件夹目标",
    "Forget everything": "全部忘记",
    "Forget everything…": "全部忘记…",
    "Forget remembered files?": "忘记已记录的文件？",
    "On your ignore list.": "在你的忽略列表中。",
    "In a Review": "在待审中",

    # ── History ──────────────────────────────────────────────────────────────
    "History": "历史记录",
    "History…": "历史记录…",
    "Last Sort Summary…": "上次整理摘要…",
    "Open Summary…": "打开摘要…",
    "Open full history…": "打开完整历史记录…",
    "Open full preview…": "打开完整预览…",
    "Latest run": "最近运行",
    "Recent activity": "最近活动",
    "Clears recent activity and returns to the empty state.":
        "清除最近活动并返回空状态。",
    "Open Review in Finder": "在 Finder 中打开待审文件夹",
    "Open in Finder": "在 Finder 中打开",
    "Reveal in Finder": "在 Finder 中显示",
    "Reveal %@ in Finder": "在 Finder 中显示 %@",
    "Rescan folders": "重新扫描文件夹",
    "Active file progress": "当前文件进度",
    "Next file starting…": "下一个文件开始…",
    "Copied PNG": "已拷贝 PNG",
    "Copy PNG": "拷贝 PNG",
    "Copy Terminal build snippet": "拷贝终端构建代码片段",
    "Press a combo to save · Esc to cancel · Delete to reset":
        "按下组合键保存 · Esc 取消 · Delete 重置",
    "Press a key…": "按下按键…",
    "Reset All Shortcuts": "重置所有快捷键",

    # ── Email / report ───────────────────────────────────────────────────────
    "Email Report…": "发送报告…",
    "Email Support…": "联系支持…",
    "Report a Bug…": "报告 Bug…",
    "Give Feedback…": "提供反馈…",
    "Leave a Review…": "留评价…",
    "Check for Updates…": "检查更新…",
    "What's New…": "新功能…",
    "GitHub Issue…": "GitHub Issue…",
    "GitHub Repo": "GitHub 仓库",
    "Open CLI setup on GitHub": "在 GitHub 上打开 CLI 设置",
    "Open Analytics & Improvements settings…": "打开分析与改进设置…",
    "Maybe later": "稍后再说",
    "Visit binkyfiles.com": "访问 binkyfiles.com",

    # ── Brand voice / taglines ───────────────────────────────────────────────
    "Files acting up? Pop in a Binky.": "文件不听话？塞个 Binky。",
    "Same pacifier, different crib.": "同一个安抚奶嘴，不同的婴儿床。",
    "Sh. Binky's already on it.": "嘘。Binky 已经在处理了。",
    "Quiets the mess right down.": "让混乱瞬间安静。",
    "Your rules. Your Mac. No guessing.": "你的规则。你的 Mac。不用猜。",
    "Already handled.": "已处理。",
    "Sorted. Routed. Binky'd.": "已整理。已路由。已搞定。",
    "Nothing enabled yet": "尚未启用任何功能",
    "Blank": "空白",

    # ── Miscellaneous wrong-sense fixes ──────────────────────────────────────
    "Automations": "自动化",
    "Calm my Desktop": "整理我的桌面",
    "Desktop also loud?": "桌面也很乱？",
    "Notes to Obsidian": "笔记转 Obsidian",
    "Plain text to Markdown": "纯文本转 Markdown",
    "Generate": "生成",
    "Quick phrase (experimental)": "快速短语（实验性）",
    "On macOS 26, Generate can use on-device models when available. Earlier macOS still fills the form with phrase heuristics.":
        "在 macOS 26 上，生成可使用设备端模型。较早的 macOS 仍使用短语启发式填充表单。",
    "Describe in plain language (e.g. from figma.com to Design/Figma)":
        "用简单语言描述（例如从 figma.com 到 Design/Figma）",
    "Compress these with Dinky ↗": "用 Dinky 压缩 ↗",
    "Pro tools": "专业工具",
    "Pro tools (CLI)": "专业工具（CLI）",
    "Keeps watch-folder sorting awake even when the window is closed. Use the menu bar for Sort Now and History.":
        "即使窗口关闭，监视文件夹整理仍保持运行。使用菜单栏进行立即整理和查看历史记录。",
    "Opens the move/review summary when autonomous sorting batches finish.":
        "自动整理批次完成后，打开移动/待审摘要。",
    "Opens your watch folder in Finder after each sort batch completes.":
        "每个整理批次完成后，在 Finder 中打开监视文件夹。",
    "Receipts use on-device text heuristics. Pauses when Low Power Mode pauses sorting.":
        "收据使用设备端文本启发式识别。低电量模式暂停整理时同步暂停。",
    "Checks last opened, last used, and date added. Runs about once a day while Binky is open.":
        "检查最后打开、最后使用和添加日期。Binky 运行时大约每天执行一次。",
    "Finder tags didn't stick for %lld files — the sort still landed.":
        "%lld 个文件的 Finder 标签未生效——但整理已完成。",
    "Finder tags didn't stick for one file — the sort still landed.":
        "1 个文件的 Finder 标签未生效——但整理已完成。",
    "Binky is sorting files.": "Binky 正在整理文件。",
    "Move, extract, install a disk image, fan out by tag, zip, trash, or rename in place.":
        "移动、解压、安装磁盘映像、按标签分类、压缩、废纸篓或原地重命名。",
    "Assign Finder tags when sorting": "整理时分配 Finder 标签",
    "Assign shortcuts for Finder's \"Sort with Binky\" in System Settings → Keyboard → Keyboard Shortcuts → Services.":
        "在系统设置 → 键盘 → 键盘快捷键 → 服务中为 Finder 的\"用 Binky 整理\"分配快捷键。",
    "Requires \"Assign Finder tags when sorting\".": "需要\"整理时分配 Finder 标签\"。",
    "Add the \"New\" Finder tag when sorting": "整理时添加\"New\"Finder 标签",
    "Adds simple Finder tags (\"New\", category hints) so files remain searchable.":
        "添加简单的 Finder 标签（\"New\"、分类提示），让文件保持可搜索。",
    "Overrides global defaults for files sorted under this automation. Leave blank to inherit.":
        "覆盖此自动化下整理文件的全局默认值。留空则继承。",
    "Overrides macOS:": "覆盖 macOS：",
    "Input Sources / Emoji": "输入源 / 表情符号",
    "Leave blank to use Binky's built-in hint for each type. Routine settings can override these per workflow.":
        "留空使用 Binky 为每种类型内置的提示。例程设置可按工作流覆盖。",
    "Rules that \"Install app from disk image\" copy .app bundles here. Leave default for ~/Applications.":
        "从磁盘映像安装 App 的规则会将 .app 包拷贝到此处。默认为 ~/Applications。",
    "Only files inside your watch folder can be sorted from here.":
        "只有监视文件夹内的文件才能从此处整理。",
    "Release the dragged items to sort files from your watch folder.":
        "释放拖拽的项目以整理监视文件夹中的文件。",
    "Release to sort": "释放以整理",
    "Drop files here": "拖放文件到此处",
    "Activate to choose more files.": "激活以选择更多文件。",
    "Activate to open the file picker.": "激活以打开文件选择器。",
    "How many files crunch at once — not image, video, or PDF quality. Fast is gentle; Fastest clears the queue sooner if your Mac is up for it.":
        "一次处理多少文件——与图片、视频或 PDF 质量无关。快速模式较温和；极速模式更快清空队列，取决于 Mac 性能。",
    "Files mid-download wait until they settle.": "正在下载的文件会等待完成。",
    "Files to sort into your watch folder sorted folders.": "整理到监视文件夹分类文件夹中的文件。",
    "Choose how much detail the organizer sidebar shows.": "选择整理器侧边栏显示的详细程度。",
    "Need routine controls too? Switch Sidebar style to Expanded in Appearance.":
        "也需要例程控件？在外观中将侧边栏样式切换为展开。",
    "Quiet pass across every watch root — useful when you tighten a rule and want what's already there to move.":
        "静默扫描所有监视根目录——当你收紧规则并希望已有文件移动时很有用。",
    "Help content couldn't be loaded.": "无法加载帮助内容。",
    "Example: iso, sparsebundle": "示例：iso、sparsebundle",
    "Existing folders": "现有文件夹",
    "Downloads (default)": "下载（默认）",
    "Add aging rule": "添加老化规则",
    "After sorting": "整理后",
    "After you edit rules": "编辑规则后",
    "Do nothing special": "不做特殊处理",
    "DoNotMove, Keep…": "DoNotMove, Keep…",
    "Archive → %@": "归档 → %@",
    "Extract archives": "解压归档",
    "Auto-extract archives": "自动解压归档",
    "Auto-install DMGs": "自动安装 DMG",
    "More conditions": "更多条件",
    "More help": "更多帮助",
    "Make a rule…": "创建规则…",
    "Matches an identical file or a very similar image Binky already sorted.":
        "匹配与 Binky 已整理的完全相同或非常相似的文件。",
    "Moved %1$lld · Kept %2$lld · Skipped %3$lld":
        "已移动 %1$lld · 保留 %2$lld · 跳过 %3$lld",
    "%1$lld moved · %2$lld kept · %3$lld skipped · %4$lld review":
        "已移动 %1$lld · 保留 %2$lld · 跳过 %3$lld · 待审 %4$lld",
    "%1$lld sorted · %2$lld already had · %3$lld receipts filed · %4$lld in review":
        "已整理 %1$lld · 已有 %2$lld · 收据已归档 %3$lld · 待审 %4$lld",
    "%1$lld files sorted · %2$lld moves · %3$lld runs (last week). Tap Binky for the share card.":
        "已整理 %1$lld 个文件 · %2$lld 次移动 · %3$lld 次运行（上周）。点击 Binky 获取分享卡片。",
    "%lld files sorted this week": "本周整理了 %lld 个文件",
    "%lld already had": "已有 %lld 个",
    "%lld already had in the last sort.": "上次整理已有 %lld 个。",
    "%lld in review": "%lld 个待审",
    "%lld want a second look.": "%lld 个需要再看看。",
    "%lld receipts filed": "%lld 张收据已归档",
    "%lld of %lld on": "%lld / %lld 开启",
    "%lld of %lld — %@": "%lld / %lld — %@",
    "%@, +%lld more": "%@，还有 %lld 个",
    "+%lld more in full preview": "完整预览中还有 %lld 个",
    ", and ": " 和 ",
    "Today: %1$lld sorted · %2$lld review · %3$lld dupes skipped · %4$lld receipts · %5$lld archived. Quietly handled.":
        "今日：%1$lld 已整理 · %2$lld 待审 · %3$lld 重复跳过 · %4$lld 收据 · %5$lld 已归档。安静处理。",
    "A newer Binky is available.": "有新版本的 Binky 可用。",
    " is available": " 可用",
    "Automations": "自动化",
    "Delete \"%@\"?": "删除\"%@\"？",
    "Big-batch threshold: %lld files": "大批量阈值：%lld 个文件",
    "When on, Apple's MetricKit can deliver anonymous crash and hang diagnostics to Binky on your Mac.":
        "开启后，Apple 的 MetricKit 可以向你 Mac 上的 Binky 发送匿名崩溃和卡顿诊断。",
    "Help content couldn't be loaded.": "无法加载帮助内容。",
    "From: %@": "来自：%@",
    "From: any": "来自：任意",
    "Binky — binkyfiles.com": "Binky — binkyfiles.com",
    "App Switcher": "App 切换器",
    "Open in New Window": "在新窗口中打开",
    "Back": "返回",
    "Forward": "前进",
}

# ── Per-key zh-Hant overrides ────────────────────────────────────────────────
# Most keys share the same fix as zh-Hans with Traditional Chinese characters.
# We derive zh-Hant from zh_HANS where the fix is identical in both scripts,
# and add explicit overrides where the Traditional form differs.

ZH_HANT_SHARED = {
    # These keys get the same value in both zh-Hans and zh-Hant
    # (brand names, English terms kept as-is, format strings)
    "Bug: ": "Bug: ",
    "GitHub Issue…": "GitHub Issue…",
    "Dinky": "Dinky",
    "Binky": "Binky",
    "PDF": "PDF",
    "OK": "好",
    "Binky — binkyfiles.com": "Binky — binkyfiles.com",
    "App Switcher": "App 切換器",
    "Open in New Window": "在新視窗中開啟",
}

ZH_HANT = {
    # macOS standard terms (Traditional)
    "Appearance": "外觀",
    "General": "一般",
    "Find": "尋找",
    "Find Next": "尋找下一個",
    "Find Previous": "尋找上一個",
    "Cut": "剪下",
    "Save": "儲存",
    "Dismiss": "關閉",
    "Remove": "移除",
    "Name": "名稱",
    "Name: %@": "名稱：%@",
    "Off": "關閉",
    "Done": "完成",
    "New": "新增",
    "New Tab": "新增標籤頁",
    "Preferences": "偏好設定",
    "Settings": "設定",
    "Print": "列印",
    "Select All": "全選",
    "Minimize": "最小化",
    "Close Window": "關閉視窗",
    "Cycle Windows": "切換視窗",
    "Get Info": "顯示簡介",
    "Hide App": "隱藏 App",
    "Quit App": "結束 App",
    "Copy": "拷貝",
    "Paste": "貼上",
    "Redo": "重做",
    "Cancel": "取消",
    "Delete": "刪除",
    "Install": "安裝",
    "Reset": "重置",
    "Retry": "重試",
    "Add": "加入",
    "Edit": "編輯",
    "Open…": "開啟…",
    "Open Files…": "開啟檔案…",
    "Choose…": "選擇…",
    "Choose Folder…": "選擇檔案夾…",
    "Choose folder": "選擇檔案夾",
    "Choose Folder": "選擇檔案夾",
    "Choose source folder": "選擇來源檔案夾",
    "Choose Applications folder": "選擇應用程式檔案夾",
    "Help": "說明",
    "Binky Help": "Binky 說明",
    "Nice": "不錯",
    "Got it": "知道了",
    "Back": "返回",
    "Forward": "前進",
    "Close": "關閉",
    "Default": "預設",
    "Customize": "自訂",
    "Accessibility": "輔助使用",
    "Notifications": "通知",
    "Privacy": "隱私權",
    "Layout": "版面配置",
    "Interface": "介面",
    "Keyboard shortcuts…": "鍵盤快捷鍵…",

    # Software terms
    "Crash diagnostics": "當機診斷",
    "Crash — Binky": "當機 — Binky",
    "Crash report — Binky": "當機報告 — Binky",
    "Crash diagnostics from Apple are available for this device. Nothing was sent automatically — use the below buttons if you want to share them.":
        "此裝置已有 Apple 當機診斷。不會自動傳送任何內容——如需分享，請使用下方按鈕。",
    "Share crash diagnostics with Binky": "與 Binky 共享當機診斷",
    "Apple diagnostic summary": "Apple 診斷摘要",
    "Binky crashed last time": "Binky 上次當機了",
    "Previous session ended unexpectedly; no Apple diagnostic payload is attached yet.\n\n":
        "上次排序意外結束；尚未附加 Apple 診斷資料。\n\n",
    "Couldn't phone home.": "無法連線到伺服器。",
    "Couldn't mount the update disk image.": "無法掛載更新磁碟映像。",
    "Call stack tree (JSON, truncated):\n%@": "呼叫堆疊樹（JSON，已截斷）：\n%@",

    # Brand name
    "About Binky": "關於 Binky",
    "Binky Help": "Binky 說明",
    "Feedback — Binky v%@": "回饋 — Binky v%@",
    "Support — Binky v%@": "支援 — Binky v%@",
    "Quit Binky": "結束 Binky",
    "Loving Binky? Leave a review": "喜歡 Binky？來留個評價吧",
    "Fussy folder. Meet Binky.": "雜亂的檔案夾？交給 Binky。",
    "Files were screaming. Binky helped.": "檔案在尖叫。Binky 搞定了。",
    "Binky'd. Already handled.": "已處理。Binky 搞定了。",
    "Binky's tidying up.": "Binky 在整理中。",
    "Here's what Binky heard.": "這是 Binky 聽到的。",
    "Binky watches here and runs the rules below. Different folder than the default? That's the point.":
        "Binky 在此監視並執行下方規則。和預設檔案夾不同？這正是重點。",
    "Binky won't touch any file carrying one of these Finder tags — handy for shortcuts or files you've parked on purpose.":
        "帶有這些 Finder 標籤的檔案 Binky 不會碰——適合你刻意保留的檔案或快捷方式。",
    "Binky exposes a Sort Files action in the Shortcuts app. Hand files from Finder or other actions through Binky — same routing rules as the main window.":
        "Binky 在捷徑 App 中提供「整理檔案」動作。從 Finder 或其他動作將檔案交給 Binky——使用與主視窗相同的路由規則。",
    "Binky remembers %lld files.": "Binky 記住了 %lld 個檔案。",
    "Binky couldn't reach GitHub. Probably the internet. Try again in a sec?":
        "Binky 無法連線 GitHub。可能是網路問題。稍後再試？",
    "Open Binky at login": "登入時開啟 Binky",
    "Open sorted folder in Dinky": "在 Dinky 中開啟已整理檔案夾",
    "Couldn't open that folder in Dinky.": "無法在 Dinky 中開啟該檔案夾。",
    "Approve Binky in System Settings → General → Login Items.":
        "在系統設定 → 一般 → 登入項目中核准 Binky。",
    "For watch folders, routines, and full troubleshooting, open Binky Help from the Help menu (%@).":
        "關於監視檔案夾、常式和完整疑難排解，請從說明選單（%@）開啟 Binky 說明。",

    # Watching
    "Watching": "監視中",
    "Pause watching": "暫停監視",
    "Resume watching": "恢復監視",
    "Also watch inside immediate subfolders (one level)":
        "同時監視直接子檔案夾（一層）",

    # Sorting
    "Sort Now": "立即整理",
    "Quick Sort": "快速整理",
    "Quick Sort and Routines": "快速整理和常式",
    "Quick Sort only": "僅快速整理",
    "Routines only": "僅常式",
    "Review": "待審",
    "Review folder": "待審檔案夾",
    "Pending review": "待審核",
    "No sessions yet.": "還沒有排序紀錄。",
    "No sorts yet.": "還沒有排序紀錄。",
    "Resume sort": "繼續排序",
    "Resume sorting": "繼續排序",
    "Moved": "已移動",
    " moved": " 已移動",
    "Kept": "保留",
    "Duplicate": "重複",
    "Duplicates": "重複項目",
    "Dry run": "試執行",
    "Preview sort": "預覽排序",
    "Preview sort…": "預覽排序…",
    "Currently sorting": "正在排序",
    "No active sorting.": "目前沒有排序。",
    "Already got one — filed here.": "已經有了——歸檔於此。",
    "Already got one.": "已經有了。",
    "Already in the right place.": "已經在正確位置。",
    "Nothing is moved — this is a dry run.": "未移動任何檔案——這是試執行。",
    "Nothing is moved yet. Incomplete downloads are treated as skipped.":
        "尚未移動任何檔案。未完成的下載視為已跳過。",
    "Incomplete download — skipped for now.": "未完成的下載——暫時跳過。",
    "All caught up.": "已是最新。",
    "All done!": "全部完成！",
    "All quiet. Every folder is Binky'd.": "一切安靜。每個檔案夾都已整理好。",
    "Nothing in Review. Binky's on top of it.": "待審區沒有檔案。Binky 已處理完畢。",
    "Nothing old enough to touch yet.": "還沒有足夠久的檔案。",
    "Quiet folders. Nothing to report.": "檔案夾很安靜。沒什麼可報告的。",
    "Looks like a receipt.": "看起來像收據。",
    "Looks right. Apply it.": "看起來沒問題。套用。",

    # Auto
    "Auto": "自動",
    "Auto-extract archives": "自動解壓縮",
    "Auto-install DMGs": "自動安裝 DMG",
    "Automations": "自動化",

    # Energy
    "Energy": "能耗",
    "Aggressive": "積極",
    "Gentle": "輕柔",

    # Archive
    "Archive": "歸檔",
    "Archives": "歸檔",
    "Archive old screenshots": "歸檔舊截圖",
    "Archive stale files": "歸檔過期檔案",
    "Archive subfolder": "歸檔子檔案夾",
    "Archive → %@": "歸檔 → %@",
    "Extract archives": "解壓縮",
    "Images": "圖片",
    "Documents": "文件",
    "Screenshots": "截圖",
    "Misc": "其他",
    "Docs": "文件",
    "Files": "檔案",
    "Folder": "檔案夾",
    "Folders": "檔案夾",
    "Receipts": "收據",
    "Audio": "音訊",

    # Routine
    "Routines": "常式",
    "Routine name": "常式名稱",
    "Routine: %@": "常式：%@",
    "New routine": "新增常式",
    "Blank routine": "空白常式",
    "Add routine": "加入常式",
    "Delete routine?": "刪除常式？",
    "Enable this routine": "啟用此常式",
    "Enabled": "已啟用",
    "Calm my Desktop": "整理我的桌面",
    "Calm my Desktop…": "整理我的桌面…",
    "Blank": "空白",
    "Open Routines…": "開啟常式…",

    # Menu bar
    "Binky — Paused": "Binky — 已暫停",
    "Binky — Paused (%@)": "Binky — 已暫停（%@）",
    "Binky — Paused (Low Power Mode)": "Binky — 已暫停（低耗電模式）",
    "Binky — Paused (cooling down)": "Binky — 已暫停（降溫中）",
    "Binky — Sorting %lld of %lld": "Binky — 正在整理 %lld/%lld",
    "Binky — Sorting %lld of %lld (%@)": "Binky — 正在整理 %lld/%lld（%@）",
    "Binky — Sorting…": "Binky — 正在整理…",
    "Binky — Stopping…": "Binky — 正在停止…",
    "Paused": "已暫停",
    "Paused — %@": "已暫停 — %@",
    "Paused — Low Power Mode.": "已暫停 — 低耗電模式。",
    "Paused — letting things cool off.": "已暫停 — 等待降溫。",
    "Pause sort": "暫停排序",
    "Pause sorting": "暫停排序",
    "Pause sorting on Low Power Mode": "低耗電模式時暫停排序",
    "Pause sorting when thermal state is critical": "溫度過高時暫停排序",
    "Idle": "閒置",

    # Email
    "Email Report…": "傳送報告…",
    "Email Support…": "聯絡支援…",
    "Report a Bug…": "報告 Bug…",
    "Give Feedback…": "提供回饋…",
    "Leave a Review…": "留評價…",
    "Check for Updates…": "檢查更新…",
    "What's New…": "新功能…",
    "GitHub Repo": "GitHub 存放庫",
    "Open CLI setup on GitHub": "在 GitHub 上開啟 CLI 設定",
    "Maybe later": "稍後再說",

    # Brand voice
    "Files acting up? Pop in a Binky.": "檔案不聽話？塞個 Binky。",
    "Same pacifier, different crib.": "同一個安撫奶嘴，不同的嬰兒床。",
    "Sh. Binky's already on it.": "噓。Binky 已經在處理了。",
    "Quiets the mess right down.": "讓混亂瞬間安靜。",
    "Your rules. Your Mac. No guessing.": "你的規則。你的 Mac。不用猜。",

    # Settings
    "All settings": "所有設定",
    "Additional settings": "附加設定",
    "Main layout": "主要版面配置",
    "Expanded": "展開",
    "Menu bar": "選單列",
    "Menu bar only (hide Dock icon)": "僅選單列（隱藏 Dock 圖示）",
    "Housekeeping": "清理",

    # Digest
    "Digest hour: %lld": "摘要時間：%lld",
    "Daily digest notification": "每日摘要通知",
    "Notify when done": "完成後通知",
    "Play sound when done": "完成後播放音效",
    "Notification settings…": "通知設定…",

    # Rules
    "Routing": "路由",
    "Routing & sorted folders…": "路由和分類檔案夾…",
    "Rule": "規則",
    "Rule name": "規則名稱",
    "New rule": "新增規則",
    "New routing": "新增路由",
    "Edit rule": "編輯規則",
    "Custom routing rules": "自訂路由規則",
    "Content match": "內容符合",
    "Content: %@": "內容：%@",
    "By name": "依名稱",
    "By file kind": "依檔案類型",
    "By file type.": "依檔案類型。",
    "By Finder tag": "依 Finder 標籤",

    # History
    "History": "歷史紀錄",
    "History…": "歷史紀錄…",
    "Last Sort Summary…": "上次整理摘要…",
    "Open Summary…": "開啟摘要…",
    "Open full history…": "開啟完整歷史紀錄…",
    "Open full preview…": "開啟完整預覽…",
    "Latest run": "最近執行",
    "Recent activity": "最近活動",

    # Misc
    "Delete \"%@\"?": "刪除「%@」？",
    "Forget everything": "全部忘記",
    "Forget everything…": "全部忘記…",
    "Forget remembered files?": "忘記已記錄的檔案？",
    "Move to Trash": "移到垃圾桶",
    "Move to…": "移到…",
    "Move / review summary": "移動/待審摘要",
    "Install Update": "安裝更新",
    "Install update now?": "現在安裝更新？",
    "Installing…": "正在安裝…",
    "Downloading…": "正在下載…",
    "Generate": "產生",
    "Desktop also loud?": "桌面也很亂？",
    "Notes to Obsidian": "筆記轉 Obsidian",
    "Plain text to Markdown": "純文字轉 Markdown",
    "Quick phrase (experimental)": "快速短語（實驗性）",
    "Fan out by tag": "依標籤分類",
    "Install from disk images": "從磁碟映像安裝",
    "Install disk images": "安裝磁碟映像",
    "Compress these with Dinky ↗": "用 Dinky 壓縮 ↗",
    "Pro tools": "專業工具",
    "Pro tools (CLI)": "專業工具（CLI）",
}


def apply_overrides(data, lang, overrides):
    fixes = 0
    for key, value in overrides.items():
        entry = data["strings"].get(key)
        if entry is None:
            continue
        locs = entry.setdefault("localizations", {})
        payload = locs.setdefault(lang, {"stringUnit": {"state": "translated", "value": ""}})
        su = payload.setdefault("stringUnit", {"state": "translated", "value": ""})
        if su.get("value") != value:
            old = su.get("value", "")
            su["value"] = value
            su["state"] = "translated"
            fixes += 1
            print(f"  [{lang}] {key!r}\n    - {old!r}\n    + {value!r}")
    return fixes


def main():
    data = json.loads(CAT.read_text())
    total = 0

    print("=== zh-Hans corrections ===")
    total += apply_overrides(data, "zh-Hans", ZH_HANS)

    print("\n=== zh-Hant corrections ===")
    # Apply shared overrides first, then zh-Hant-specific ones
    total += apply_overrides(data, "zh-Hant", ZH_HANT_SHARED)
    total += apply_overrides(data, "zh-Hant", ZH_HANT)

    CAT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"\nApplied {total} corrections.")


if __name__ == "__main__":
    main()
