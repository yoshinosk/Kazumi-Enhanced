# 上游功能同步进度

- 基线:上游 `2.2.8`(640dfdcb)
- 目标:同步上游 `2.2.9` / `2.3.0` / `2.3.1` / `main` 的全部功能(共 72 个提交)
- 状态标记:⬜ 未开始 / 🔄 进行中 / ✅ 已完成 / ❌ 决定跳过(附原因)
- 每完成一项,在对应条目标记 ✅ 并注明日期

## 批次 1:低冲突功能

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ✅ | ac39437a | feat(plugin): 批量规则导入 | 2026.9.9 |
| ✅ | 030645a9 | fix(ui): 修复批量规则更新 toast 消失 | 2026.9.9 |
| ✅ | 5b5fd9a8 | feat(download): 下载页自动滚动到正在播放的集 | 2026.9.9 |
| ✅ | 49c19350 | fix: 禁用相关番剧卡片 hero 动画 | 2026.9.9 |
| ✅ | 281ee9cc | fix(android): PiP 入口重构 | 2026.9.9 |
| ✅ | 80af230b | fix(android): 媒体会话销毁后不再复现 | 2026.9.9 |
| ✅ | 84043d59 | fix(android): 应用后台时挂起 demuxer 预取 | 2026.9.9 |

验证: `flutter analyze` 无新增问题(21 个均为既有 info/warning),`flutter test` 364 项全部通过。

## 批次 2:中冲突功能

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ✅ | 6c3c46c9 | feat: 弹幕搜索 API v2 | 2026.9.9 |
| ✅ | c32db78c | fix(danmaku): 手动弹幕匹配使用搜索集数 | 2026.9.9 |
| ✅ | bd66ce55 | fix(danmaku): 修复存储时长编辑 | 2026.9.9 |
| ✅ | 5d1569b3 | feat(sync): Bangumi 收藏同步优化 | 2026.9.9 |
| ✅ | 22f9ee13 | feat(player): 网络感知低内存模式 | 2026.9.9 |
| ❌ | 43e0fe80 | ~~fix(windows): 检测到的 M3U 源强制 HLS demux~~（已在 2.2.8 基线内，无需同步） | - |
| ⬜→批次4 | 50f83370 | fix: 仅自动展开第一个播放源（与 1eab03f3 源选择重设计一并处理） | |
| ✅ | a2fd8259 | fix(video): 选集网格中定位历史集数 | 2026.9.9 |
| ✅ | 3e86da15 | fix(player): 无效源错误提示改进 | 2026.9.9 |
| ✅ | 280a5adc | fix(player): 源失败 toast 移出错误 switch | 2026.9.9 |
| ⬜→批次4 | 08905a38 | fix(player): 关闭播放线路菜单后恢复焦点（依赖 2.3.1 新选集面板，随批次 4 同步） | |
| ⬜→批次4 | 45201365 | feat(collect): 番剧计数从页脚移到标签页（依赖收藏库重设计，随批次 4 同步） | |
| ✅ | d658832d | chore: 设置页文案优化 | 2026.9.9 |
| ✅ | 92e91e3d | fix(bangumi): 保留同步偏好并稳定连接状态 | 2026.9.9 |
| ⬜ | 9b7d6458 | fix(info): 分离评论与播放操作 | |
| ⬜ | 495bf11a | fix(images): 统一角色立绘加载 | |
| ⬜ | 11b0cb76 | fix(history): 移除多余的卡片加载指示器 | |
| ⬜ | 7d2d0d58 | fix(collect): 恢复封面 hero 转场 | |
| ⬜ | e436ab76 | fix(collect): 修正滚动行为 | |
| ⬜ | 99562de8 | fix(timeline): 对齐卡片封面 | |
| ⬜ | edb7b526 | fix(timeline): 滚动时保持星期标签稳定 | |
| ⬜ | aeae76d9 | perf(history): 惰性渲染日期 | |
| ⬜ | 2c1dad2e | fix(search): 图片搜索结果滚动条对齐页面边缘 | |
| ⬜ | 879eb849 | fix(timeline): 合并排序与筛选控件 | |
| ⬜ | 22be2365 | fix(collect): 搜索栏随库内容滚动 | |
| ⬜ | d5784deb | fix(collect): 库滚动条对齐页面边缘 | |
| ⬜ | 50f83370(重复) | | |
| ⬜ | 23610a52 | fix(search): 防止结果卡片标题被裁剪 | |

## 批次 3:依赖升级

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ❌ | 2eefde98 | ~~deps: bump dio~~（已在 2.2.8 基线内） | - |
| ❌ | 145feb99 | ~~deps: bump media kit~~（已在 2.2.8 基线内） | - |
| ⬜ | 491482c1 / 794567ed | deps: bump canvas danmaku | |
| ❌ | b018c6ca | ~~chore: bump 默认插件~~（已在 2.2.8 基线内） | - |
| ⬜ | 2d13a412 / 0d6237ab | deps: Flutter 3.47.0 → 3.47.2 | |
| ❌ | 76fc6ecf | ~~chore: 从 appBuildName 派生应用版本号~~（已在 2.2.8 基线内） | - |

## 批次 4:M3E UI 重构浪潮(约 30 个提交,建议整体接收 2.3.x UI 后回移植本分支功能)

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ⬜ | ba52a11c | refactor(ui): 统一表现力组件并移除旧代码 | |
| ⬜ | 24690559 | feat(collect): 收藏库重设计 | |
| ⬜ | 02f4b307 | feat(ui): 时间线重设计 + 收藏空状态简化 | |
| ⬜ | 7ca223bb | feat(history): 观看历史页重设计 | |
| ⬜ | 1eab03f3 | feat(ui): 播放源选择卡片重设计 | |
| ⬜ | 8c0dcc9d | fix(ui): 主页面 AppBar 标题样式统一 | |
| ⬜ | 4b05b11f | refactor(ui): 统一 M3E 空状态 | |
| ⬜ | a530f703 | feat(ui): 错误状态重设计并统一 | |
| ⬜ | 0aadad1e | feat(search): 番剧搜索重设计 | |
| ⬜ | a71dfa21 | feat(search): 图片搜索重设计 | |
| ⬜ | 1625761e | refactor(search): 简化图片搜索布局 | |
| ⬜ | acb28d30 | feat(player): 选集面板重设计 | |
| ⬜ | 782e7076 | refactor(player): 移除标签页弹幕输入并简化控制边界 | |
| ⬜ | b6779400 | feat(comments): 统一集数与角色卡片 | |
| ⬜ | 66d8483c | fix(character): M3E 详情页重设计并恢复角色信息 | |
| ⬜ | 1aa66d9b | feat(rules): 规则管理重设计 | |
| ⬜ | 665784a5 | feat(ui): 退出确认重设计 | |
| ⬜ | 2d39ecbd | feat(onboarding): 引导页重设计 | |
| ⬜ | 9f8f6a52 | chore: 使用 M3 outlined 输入框 | |
| ⬜ | 02f4b307(重复) | | |
| ⬜ | 19f71356 | feat(collect): 简化布局并支持竖屏分类滑动 | |
| ⬜ | 7d2d0d58(重复) | | |
| ⬜ | 08905a38(重复) | | |
| ⬜ | 7ca223bb(重复) | | |
| ⬜ | 31e0db7f | refactor(dialog): 集中化工作流 | |
| ⬜ | f26ca74f | refactor(about): 关于页重设计 | |
| ⬜ | 1c42520 | feat(my): 我的页重设计 | |
| ⬜ | 091b357 | feat(settings): 同步设置重设计 | |
| ⬜ | 98e331c7 | feat(info): 评论对话框重设计 | |
| ⬜ | e140ecd8 | feat(collect): 手动同步重设计 | |
| ⬜ | 3977a81a | feat(settings): 响应式嵌套路由 | |
| ⬜ | d780e997 | refactor(settings): 简化导航并移除死代码 | |
| ⬜ | cddf2b38 | fix(settings): 恢复页面转场 | |
| ⬜ | 2c1dad2e(重复) | | |

## 决定跳过(按项目平台约束)

| 状态 | 上游提交 | 原因 |
|---|---|---|
| ❌ | 52a18732 | fix(macos): 仅 macOS |
| ❌ | 7b19e26f | fix(linux): 仅 Linux |
| ❌ | 6d4a2d5d | docs(readme): 移除 archlinuxcn 下载源,与 README 无关 |

## 备注

- 两个仓库 git 历史不相连,所有同步均按内容移植,不能直接 cherry-pick。
- 每完成一项需:更新本文件状态 → 更新 CHANGELOG.md → `flutter analyze` / `flutter test` → 提交。
- 批次 4 工程量大,单独规划,先完成批次 1~3。
