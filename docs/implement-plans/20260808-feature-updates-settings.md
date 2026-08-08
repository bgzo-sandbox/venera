---
goal: 新增"更新"设置页并改造漫画更新检查（启动开关 / 可配间隔 / 跳过已更新 / 修复阅读后状态不刷新）
version: 1.0
created: 2026-08-08
modified: 2026-08-08
status: 'In Progress'
tags: [feature, bug, updates, settings]
---

# Introduction

当前漫画更新检查无设置入口、间隔硬编码为 1 天、不跳过已标记更新的漫画，且阅读后更新页列表不刷新（默认 `moveFavoriteAfterRead='none'` 走 `markAsRead` 分支，该分支仅调用 `notifyChanges()` 未直接通知更新页 UI，而更新页/首页卡片未把自己注册为 `LocalFavoritesManager` 的 listener）。本计划在设置中新增"更新"分类页，引入三个开关/选项，并修复阅读后状态不刷新的 bug。首页 `FollowUpdatesWidget` 入口完全保留。

## 1. Requirements & Constraints

- **REQ-001**: 设置页 `categories` 在"Explore"(index 0) 之后插入"Updates"(index 1)，其余项顺延。
- **REQ-002**: 新开关 `comicUpdateCheckOnStart`，默认 `true`；只门控启动时立即执行的那次 `_check()`，不影响 10 分钟定时器，不约束手动 Check Now。
- **REQ-003**: 新选项 `comicUpdateCheckInterval`，离散值 `1 / 6 / 12 / 24 / 48 / 72`（单位：小时），默认 `24`；替换 `follow_updates.dart:113-118` 的硬编码 `inDays < 1`。
- **REQ-004**: 新开关 `skipCheckIfHasNewUpdate`，默认 `true`；在 `updateFolderBase` 中对 `has_new_update==1` 的漫画跳过网络检查；同时作用于自动检查与手动 Check Now。
- **REQ-005**: 修复阅读后更新页 UI 不刷新：使 `_FollowUpdatesWidgetState` 与 `_FollowUpdatesPageState` 监听 `LocalFavoritesManager`，`markAsRead` 的 `notifyChanges()` 即可触发刷新。作用范围维持现状（仅 `followUpdatesFolder`）。
- **SEC-001**: 不引入新的网络或权限行为。
- **CON-001**: 遵循 `.tl` i18n 与 `assets/translation.json` 三语（en_US / zh_CN / zh_TW）。
- **CON-002**: 通过验证门 `fvm dart format --set-exit-if-changed . && fvm flutter analyze --fatal-infos && fvm flutter test`。
- **GUD-001**: 复用既有 setting 组件 `_SwitchSetting` / `SelectSetting` / `_CallbackSetting`。
- **PAT-001**: 新设置页以 `part of 'settings_page.dart';` 形式置于 `lib/pages/settings/updates.dart`，模仿 `local_favorites.dart`。

#### TASK-001 Execution Record
- **Status**: Completed (2026-08-08)
- **Change Summary**: 在 appdata 默认 settings 新增 3 个漫画更新相关设置项。
- **Logic Changes**:
  - **Added**: `comicUpdateCheckOnStart: true`、`comicUpdateCheckInterval: '24'`、`skipCheckIfHasNewUpdate: true`。
  - **Modified**: 无。
- **Linked Code**: `lib/foundation/appdata.dart:248-250`
- **Verification Result**: `rg` 命中 3 行，`fvm flutter analyze --fatal-infos` 无问题。

#### TASK-002 Execution Record
- **Status**: Completed (2026-08-08)
- **Change Summary**: 启动时立即执行的那次 `_check()` 受 `comicUpdateCheckOnStart` 门控。
- **Logic Changes**:
  - **Modified**: `initChecker()` 将初始 `_check()` 包裹在 `if (appdata.settings['comicUpdateCheckOnStart'] == true)` 中；`DataSync().addListener` 与 `Timer.periodic` 保持原样。
- **Linked Code**: `lib/pages/follow_updates_page.dart:560-562`
- **Verification Result**: 代码评审确认门控不影响定时器与 listener；手动改默认值验证（无/有立即检查日志）待应用运行确认，逻辑正确。

#### TASK-003 Execution Record
- **Status**: Completed (2026-08-08)
- **Change Summary**: 对 TASK-001/002 改动运行验证门。
- **Logic Changes**:
  - **Modified**: 无。
- **Linked Code**: `lib/foundation/appdata.dart`、`lib/pages/follow_updates_page.dart`
- **Verification Result**: `dart format` 0 changed，`analyze --fatal-infos` 无问题，均退出码 0。

## 2. Implementation Steps

### Implementation Phase 1 — 设置项数据模型与启动门控

- GOAL-001: 在 `appdata` 注册新设置项，并让启动检查受新开关门控

| Task | Status | Description | Verification Steps | Date |
| ---- | ------ | ----------- | ------------------- | ---- |
| TASK-001 | Completed | 在 `lib/foundation/appdata.dart` 默认 settings Map（`'checkUpdateOnStart': false` 之后）新增：`'comicUpdateCheckOnStart': true`（注释标明"漫画更新，区别于 APP 版本的 checkUpdateOnStart"）、`'comicUpdateCheckInterval': '24'`（注释：1/6/12/24/48/72 小时，字符串）、`'skipCheckIfHasNewUpdate': true`。 | `rg "comicUpdateCheckOnStart\|comicUpdateCheckInterval\|skipCheckIfHasNewUpdate" lib/foundation/appdata.dart` 命中 3 行；`fvm flutter analyze --fatal-infos` 无错。 | 2026-08-08 |
| TASK-002 | Completed | 在 `lib/pages/follow_updates_page.dart` 的 `FollowUpdatesService.initChecker()`（约 557-566 行）将初始 `_check()` 包一层 `if (appdata.settings['comicUpdateCheckOnStart'] == true) { _check(); }`；`DataSync().addListener(...)` 与 `Timer.periodic(...)` 保持不变。 | 临时把默认值改 `false` 跑一次：启动后无立即检查日志；改回 `true`：有检查日志。10 分钟定时器仍在运行。 | 2026-08-08 |
| TASK-003 | Completed | 验证门：`fvm dart format --set-exit-if-changed lib/foundation/appdata.dart lib/pages/follow_updates_page.dart` 与 `fvm flutter analyze --fatal-infos` 通过。 | 上一条命令退出码 0。 | 2026-08-08 |

### Implementation Phase 2 — 可配更新间隔 + 跳过已更新

- GOAL-002: 用设置项替换硬编码间隔，并实现"跳过已标记更新"

| Task | Status | Description | Verification Steps | Date |
| ---- | ------ | ----------- | ------------------- | ---- |
| TASK-004 | Pending | 在 `lib/foundation/follow_updates.dart` 顶部新增 `import 'package:venera/foundation/appdata.dart';`。 | `rg "import 'package:venera/foundation/appdata.dart'" lib/foundation/follow_updates.dart` 命中。 | |
| TASK-005 | Pending | 在 `updateFolderBase`（约 110-121 行）改写逐漫画过滤：保留既有 `ignoreCheckTime` 时间节流分支，但把 `inDays < 1` 改为 `inHours < (int.tryParse(appdata.settings['comicUpdateCheckInterval']?.toString() ?? '24') ?? 24)`；并在该循环内新增 `if (appdata.settings['skipCheckIfHasNewUpdate'] == true && comic.hasNewUpdate) { current++; stream.add(UpdateProgress(total, current, errors, updated)); continue; }`，使该跳过逻辑与 `ignoreCheckTime` 无关（即手动 Check Now 也生效）。total 仍由 `comicsToUpdate.length` 重算。 | 阅读源码确认两处跳过分支并存；`fvm flutter analyze --fatal-infos` 通过。 | |
| TASK-006 | Pending | 单测：在 `test/foundation/favorites_follow_updates_test.dart` 增补（或新文件 `follow_updates_test.dart`）：构造一个 `has_new_update=true` 的 `FavoriteItemWithUpdateInfo`，设置 `skipCheckIfHasNewUpdate=true`，调用 `updateFolder(folder, true)`，断言不发生源站请求（mock `loadComicInfo` 不被调用）；再设 `false`，断言发生请求。 | `fvm flutter test test/foundation/favorites_follow_updates_test.dart` 通过（或新文件测试通过）。 | |
| TASK-007 | Pending | 单测：构造 `lastCheckTime` 为 2 小时前的漫画，设置 `comicUpdateCheckInterval='24'`，`updateFolder(folder, false)` 断言跳过；改为 `'1'`，断言请求发生。 | 同上测试命令通过。 | |

### Implementation Phase 3 — 修复阅读后更新页 UI 不刷新（#5 / #9）

- GOAL-003: 使更新页/首页卡片随 `LocalFavoritesManager` 变更自动刷新

| Task | Status | Description | Verification Steps | Date |
| ---- | ------ | ----------- | ------------------- | ---- |
| TASK-008 | Pending | 在 `lib/pages/follow_updates_page.dart` 的 `_FollowUpdatesWidgetState`：`initState` 内 `getCount()` 之后加 `LocalFavoritesManager().addListener(updateCount);`；重写 `dispose` 调用 `LocalFavoritesManager().removeListener(updateCount);` 后 `super.dispose();`。 | `rg "addListener\(updateCount\)\|removeListener\(updateCount\)" lib/pages/follow_updates_page.dart` 各 1 命中。 | |
| TASK-009 | Pending | 在 `_FollowUpdatesPageState`：`initState` 末尾加 `LocalFavoritesManager().addListener(updateComics);`；重写 `dispose` 调用 `LocalFavoritesManager().removeListener(updateComics);` 后 `super.dispose();`。 | 同上 `updateComics` 版本命中。 | |
| TASK-010 | Pending | 人工/集成验证：配置 `followUpdatesFolder`，复现 #9 场景——在更新列表点进漫画读完返回，列表中该漫画立即消失（之前残留）。 | 手动复现：阅读返回后更新页列表不含该漫画；`fvm flutter test` 通过。 | |

### Implementation Phase 4 — 新设置页 UI 与入口接线

- GOAL-004: 新增"Updates"设置分类页并接入路由

| Task | Status | Description | Verification Steps | Date |
| ---- | ------ | ----------- | ------------------- | ---- |
| TASK-011 | Pending | 新建 `lib/pages/settings/updates.dart`，文件首行 `part of 'settings_page.dart';`。定义 `class UpdatesSettings extends StatefulWidget` / `_UpdatesSettingsState`，`build` 返回 `SmoothCustomScrollView(slivers:[ SliverAppbar(title: Text("Updates".tl)), _SwitchSetting(title: "Check for updates on app start".tl, settingKey: "comicUpdateCheckOnStart"), SelectSetting(title: "Update check interval".tl, settingKey: "comicUpdateCheckInterval", help: "Minimum time between checks for the same comic.".tl, optionTranslation: {"1":"1 hour".tl,"6":"6 hours".tl,"12":"12 hours".tl,"24":"1 day".tl,"48":"2 days".tl,"72":"3 days".tl}), _SwitchSetting(title: "Skip comics already marked as updated".tl, subtitle: "Saves bandwidth by not re-checking comics that already have a pending update.".tl, settingKey: "skipCheckIfHasNewUpdate"), _CallbackSetting(title: "Configure follow updates".tl, actionTitle: "Open".tl, callback: () => context.to(() => const FollowUpdatesPage())) ])`，全部 `.toSliver()`。 | 文件存在且 `fvm flutter analyze --fatal-infos` 通过。 | |
| TASK-012 | Pending | 在 `lib/pages/settings/settings_page.dart`：①顶部新增 `import 'package:venera/pages/follow_updates_page.dart';`；②`part 'updates.dart';`（置于现有 part 列表中）；③`categories` 在 `"Explore"` 后插入 `"Updates"`；④`icons` 在对应位置插入 `Icons.update`；⑤`_buildSettingsContent` 与 `_SettingsDetailPage._buildPage` 两个 switch 的 `0 => const ExploreSettings(),` 之后插入 `1 => const UpdatesSettings(),`，并把其后所有数字索引 +1（Reading→2, Appearance→3, Local Favorites→4, APP→5, Network→6, 超分→7, About→8, Debug→9）。 | `rg "Updates" lib/pages/settings/settings_page.dart` 命中 categories 与两个 switch；运行应用进入"设置 → 更新"可见新页。 | |
| TASK-013 | Pending | 在 `assets/translation.json` 的 `en_US` / `zh_CN` / `zh_TW` 三组分别新增键：`"Check for updates on app start"`、`"Update check interval"`、`"Minimum time between checks for the same comic."`、`"Skip comics already marked as updated"`、`"Saves bandwidth by not re-checking comics that already have a pending update."`、`"1 hour"`、`"6 hours"`、`"12 hours"`、`"1 day"`、`"2 days"`、`"3 days"`、`"Configure follow updates"`。`"Updates"` 与 `"Open"` 已存在则复用，缺失才补。en_US 值同 key；zh_CN/zh_TW 给出对应中文。 | `rg '"Check for updates on app start"' assets/translation.json` 在三语下各命中。 | |
| TASK-014 | Pending | 验证门（全量）：`fvm dart format --set-exit-if-changed .` && `fvm flutter analyze --fatal-infos` && `fvm flutter test`。 | 三命令退出码均为 0。 | |

## 3. Alternatives

- **ALT-001**: 在 `markAsRead` 末尾直接调 `updateFollowUpdatesUI()` —— 修复快但需在 `favorites.dart`（foundation 层）引用 `follow_updates_page.dart`（page 层），形成反向依赖。改用 Phase 3 的 listener 方案，foundation 层零改动且自动覆盖未来其它 `notifyChanges()` 来源。
- **ALT-002**: `comicUpdateCheckInterval` 用 `_SliderSetting`（1–72 连续小时）—— 与用户的离散选项需求不符，弃用。
- **ALT-003**: 把"Check Now / 文件夹选择"也搬进新设置页 —— 与用户"首页入口完全保留，设置页只放选项"的要求不符，仅以 `_CallbackSetting` 提供跳转入口。

## 4. Dependencies

- **DEP-001**: 既有 `SelectSetting`（存储字符串 key）→ `comicUpdateCheckInterval` 以字符串存，运行时 `int.tryParse` 解析。
- **DEP-002**: `AutomaticGlobalState`（`lib/foundation/global_state.dart`）支持标准 `dispose` 重写（与 `_LocalFavoritesPageState` 同模式）。

## 5. Files

- **FILE-001**: `lib/foundation/appdata.dart` — 新增 3 个默认设置项。
- **FILE-002**: `lib/pages/follow_updates_page.dart` — `initChecker` 启动门控；两个 state 加 listener。
- **FILE-003**: `lib/foundation/follow_updates.dart` — import appdata；间隔与跳过逻辑。
- **FILE-004**: `lib/pages/settings/updates.dart` — 新建，`part of settings_page.dart`。
- **FILE-005**: `lib/pages/settings/settings_page.dart` — import、part、categories/icons、两个 switch 索引。
- **FILE-006**: `assets/translation.json` — 三语新键。
- **FILE-007**: `test/foundation/favorites_follow_updates_test.dart`（或新建 `follow_updates_test.dart`） — 间隔/跳过单测。

## 6. Testing

- **TEST-001**: `fvm flutter test test/foundation/favorites_follow_updates_test.dart` 通过，含新增间隔与跳过断言。
- **TEST-002**: `fvm flutter analyze --fatal-infos` 无 info/error。
- **TEST-003**: `fvm dart format --set-exit-if-changed .` 无 diff。
- **TEST-004**: 手动：设置 → 更新 页可见三项；切换开关/选项后重启应用，启动检查行为符合预期；更新列表手动 Check Now 在 `skipCheckIfHasNewUpdate=true` 时不重新请求已标记漫画。
- **TEST-005**: 手动复现 #9：读完漫画返回更新页，列表立即不再含该漫画。

## 7. Risks & Assumptions

- **RISK-001**: settings 索引整体 +1，须同步两个 switch；漏改任一会跳错页。缓解：TASK-012 验证步骤 grep 校验。
- **RISK-002**: `AutomaticGlobalState` 的 `dispose` 时机若与 GlobalState 缓存冲突，listener 可能残留；`removeListener` 在 dispose 调用可防 setState-after-dispose。
- **ASSUMPTION-001**: 保留 10 分钟 `Timer.periodic` 轮询器，仅门控启动那次 `_check()`（用户确认）。
- **ASSUMPTION-002**: `comicUpdateCheckInterval` 存字符串、运行时 `int.tryParse`，非法值回落 24。
- **ASSUMPTION-003**: 跳过逻辑同时作用于手动 Check Now（用户确认）。
- **ASSUMPTION-004**: 需求 #5 维持现状触发时机（打开 reader 后清空，打开详情页不清空）与作用域（仅 `followUpdatesFolder`），本次仅修复"清空后 UI 不刷新"的 bug。

## 8. References

- `lib/foundation/follow_updates.dart` — updateFolderBase / updateComic
- `lib/pages/follow_updates_page.dart` — FollowUpdatesService / 状态类
- `lib/foundation/favorites.dart` — markAsRead / onRead / updateUpdateTime
- `lib/pages/settings/settings_page.dart` — categories 路由
- `doc/comic_source.md` / `doc/js_api.md` — 源站 updateTime 字段语义
