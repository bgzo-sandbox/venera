---
goal: 修复 Anime4K 超分模块 PR #2 审查发现的 10 项问题
version: 1.0
created: 2026-08-09
modified: 2026-08-09
status: In Progress
tags: refactor, bug, anime4k, super-resolution, memory, cache
---

# Introduction

针对 `feat/anime-4k` 分支 PR #2 审查意见(issuecomment-5230325205)的修复计划。全部 10 项问题一次性修复:缓存键冲突、重复网络下载、8MP 输出内存上限、章节切换释放常驻结果、设置读取统一、gallery errorBuilder 恢复、ResizeImage 防御性解包、调度器 null 安全、pubspec 版本对齐、按原格式编码。审查中判定无需改动的 #11/#12/#13 不在范围内。

## 1. Requirements & Constraints

- **REQ-001**: 缓存文件名必须使用 MD5(`md5.convert(key.codeUnits)`,与 `lib/foundation/cache_manager.dart:111` 约定一致),禁止再使用 `String.hashCode`
- **REQ-002**: 超分输入字节必须优先从 `CacheManager` 读取已落盘原图字节,禁止触发二次网络下载
- **REQ-003**: 输出像素总数上限 800 万(8_000_000),超限自动降档 scaleFactor,降档至 1.0 仍超限则跳过处理返回 null
- **REQ-004**: 章节切换时释放所有 `_ComicImageState` 的超分结果字节
- **REQ-005**: 设置读取统一经 `getReaderSetting(cid, sourceKey, key)`(含 device 回退)
- **REQ-006**: gallery 单图模式补回错误处理(经 ComicImage 自带错误 UI 验证覆盖),缩放范围与多图模式一致(不改动)
- **REQ-007**: 输出按源格式编码:PNG 源 → PNG,JPEG/WebP/其他 → JPEG(quality 90);缓存扩展名与格式一致
- **REQ-008**: 调度器 inflight 复用路径必须 null 安全
- **CON-001**: `image` 依赖版本锚定 `^4.8.0`
- **GUD-001**: 新增 Dart 文档注释使用英文,与 super_resolution 模块现有风格一致
- **PAT-001**: 哈希约定跟随 `md5.convert(key.codeUnits).toString()`(项目既有模式)
- **PAT-002**: 释放逻辑通过 `_ImageViewController` 接口新增方法暴露,不直接操作 `_ComicImageState` 私有字段

## 2. Implementation Steps

### Implementation Phase 1:缓存键与输出格式修复(#1、#10)

- GOAL-001: 消除缓存键碰撞;输出按原格式编码,扩展名跟随实际格式

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-001 | Pending | 新建 `lib/super_resolution/models/super_resolution_output.dart`:定义 `SuperResolutionOutput { final Uint8List bytes; final String fileExtension; }`(fileExtension 取值 `'png'` 或 `'jpg'`),带英文 doc comment,与 `SuperResolutionResult` 风格一致 | 1) `flutter analyze` 无错误;2) 文件可被 `super_resolution_processor.dart` import |  |
| TASK-002 | Pending | 修改 `lib/super_resolution/super_resolution_processor.dart`:`process` 返回类型由 `Future<Uint8List?>` 改为 `Future<SuperResolutionOutput?>`;更新类内英文 doc | 1) `flutter analyze` 通过;2) `Anime4KProcessor` 实现编译报错(预期,下一步修复) |  |
| TASK-003 | Pending | 修改 `lib/super_resolution/implementations/anime4k/anime4k_processor.dart`:`_processAnime4KRequest` 解码后判断源格式——PNG magic bytes(`0x89 0x50 0x4E 0x47`)→ `encodePng`、扩展名 `'png'`;其余(JPEG/WebP/其他)→ `img.encodeJpg(result, quality: 90)`、扩展名 `'jpg'`;返回 `SuperResolutionOutput(bytes: ..., fileExtension: ...)`。同时前置判断:源图 `width*height > kMaxOutputPixels` 时直接返回 null | 1) 单元测试:给定 PNG 输入返回 `fileExtension == 'png'`、JPEG 输入返回 `'jpg'`;2) 处理 3000×4000 PNG 输入返回 null(源图超 8MP) |  |
| TASK-004 | Pending | 修改 `lib/super_resolution/cache/super_resolution_cache_store.dart`:`getCachePath(String key, {required String extension})` 改用 `md5.convert(key.codeUnits).toString()`(import `package:crypto/crypto.dart`),文件名 `'<md5>.<extension>'`;`read(String key, {required String extension})`、`write(String key, Uint8List data, {required String extension})` 签名同步更新;`init()`/`clear()`/`getCacheSize()` 不变 | 1) `flutter analyze` 通过;2) 单测:同 key 不同 extension 生成不同路径;3) 单测:MD5 输出为 32 位 hex 且长度固定 |  |
| TASK-005 | Pending | 修改 `lib/super_resolution/super_resolution_service.dart`:`_processImage` 中 `cacheStore.read/write` 调用传 processor 返回的 `output.fileExtension`;`_selectProcessor(request.algorithm).process(request)` 返回值从 `Uint8List?` 改为 `SuperResolutionOutput?`;写入前用 `output.bytes`;返回给调用方 `output?.bytes`(保持 `Future<Uint8List?>` 对外签名不变) | 1) `flutter analyze` 通过;2) 单测:`processImage` 对 PNG 输入写盘后缓存目录出现 `.png` 文件,对 JPEG 输入出现 `.jpg` 文件 |  |

### Implementation Phase 2:消除二次网络下载(#2)

- GOAL-002: 超分字节优先取 CacheManager 落盘原图,miss 时才回退现有 load 路径

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-006 | Pending | 修改 `lib/pages/reader/comic_image.dart` 的 `_loadSourceBytes`:`ReaderImageProvider` 分支改为——先 `final file = await CacheManager().findCache('${source.imageKey}@${source.sourceKey}@${source.cid}@${source.eid}');`(与 `lib/network/images.dart:116` 的 cacheKey 构造一致),命中则 `return file.readAsBytes();`;miss 则回退原 `source.load(StreamController<ImageChunkEvent>(), () {})` 逻辑 | 1) 手工验证:网络漫画开启超分,断网后已有缓存时超分仍成功(字节来自本地缓存);2) 观察日志无二次下载请求 |  |
| TASK-007 | Pending | 修复审查指出的 UI 时序问题:在 `_triggerImageUpscale` 中,将 `setState(() { _isUpscaling = true; }); _notifyReaderScaffold();` 移至 `_loadSourceBytes` 调用**之前**,避免字节加载期间 UI 状态延迟 | 1) 手工验证:点击超分后按钮/状态立即显示"处理中";2) `flutter analyze` 通过 |  |

### Implementation Phase 3:8MP 输出内存上限(#3)

- GOAL-003: 输出像素总数硬上限 8_000_000,超限自动降档

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-008 | Pending | 修改 `lib/super_resolution/implementations/anime4k/anime4k_upscaler.dart`:新增顶层常量 `const int kMaxOutputPixels = 8_000_000;`(public,供 processor 使用);在 `upscale(source)` 第 1 阶段前计算 `final double effectiveScale = math.min(scaleFactor, math.sqrt(kMaxOutputPixels / (source.width * source.height)));`,若源图本身 `> kMaxOutputPixels` 则 `effectiveScale` 将 < 1.0——直接 `return source;`(不解码分配 buffer);后续 `newWidth/newHeight` 用 `effectiveScale` 计算 | 1) 单测:3000×4000 输入 + scaleFactor=4.0 → 输出尺寸 ≤ 8MP;2) 单测:原图 3000×4000 + scaleFactor=1.0 → 返回原尺寸(跳过) |  |
| TASK-009 | Pending | 复核 TASK-003 的源图超限前置判断与 TASK-008 的降档逻辑一致性:源图本身 > 8MP 时 TASK-003 直接返回 null(不写入缓存);源图 ≤ 8MP 时 TASK-008 负责降档。确认 `super_resolution_request.dart` 的 `effectiveCacheKey` 无需变更(降档由源图决定,确定性;同参数同图结果稳定) | 1) 代码走查两条路径互斥且完整;2) 单测覆盖 8MP 边界:源图 2828×2828(=7.99MP)与 2829×2829(超限) |  |

### Implementation Phase 4:章节切换释放常驻结果(#4)

- GOAL-004: 章节切换时主动清空所有超分结果,防连续模式内存累积

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-010 | Pending | `lib/pages/reader/comic_image.dart`:在 `_ComicImageState` 新增公开方法 `void releaseAnime4KResult() { _upscaledBytes = null; _isUpscaling = false; if (mounted) setState(() {}); }`(与 `didUpdateWidget` 中清理逻辑一致) | 1) `flutter analyze` 通过;2) 代码走查确认无私有字段直接外部访问 |  |
| TASK-011 | Pending | `lib/pages/reader/reader.dart`:`_ImageViewController` 接口新增 `void releaseAnime4KResults();`(加英文 doc comment) | 1) `flutter analyze` 报两处实现缺失(预期,下一步补) |  |
| TASK-012 | Pending | `lib/pages/reader/images.dart`:`_GalleryModeState` 与 `_ContinuousModeState` 各实现 `releaseAnime4KResults()`:遍历 `imageStates`,对每个 `_ComicImageState` 调用 `releaseAnime4KResult()`(仅当 `imageState.mounted`) | 1) `flutter analyze` 通过;2) 靠手工验证 |  |
| TASK-013 | Pending | `lib/pages/reader/reader.dart`:`toChapter` 在 `chapter = c;` 赋值之后、`update()` 之前插入 `_imageViewController?.releaseAnime4KResults();` | 1) 手工验证:连续模式阅读,切换章节后旧章节超分图恢复为原图(或重新处理),内存释放 |  |

### Implementation Phase 5:设置读取统一(#5)

- GOAL-005: comic_image 与 scaffold 通过同一扩展方法读取 Anime4K 设置

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-014 | Pending | `lib/pages/reader/reader.dart`:新增顶层扩展 `extension ReaderAnime4KSetting on BuildContext { T? anime4KSetting<T>(String key) => appdata.settings.getReaderSetting(this.reader.cid, this.reader.type.sourceKey, key) as T?; }`(利用 `getReaderSetting` 已含 device 回退;`type.sourceKey` 对 local 返回 `'local'`) | 1) `flutter analyze` 通过;2) 无重复定义 |  |
| TASK-015 | Pending | `lib/pages/reader/comic_image.dart`:删除 `_getAnime4KSetting<T>`,所有调用点改为 `context.anime4KSetting<T>(key)` | 1) `flutter analyze` 通过;2) grep 确认 `_getAnime4KSetting` 无残留引用 |  |
| TASK-016 | Pending | `lib/pages/reader/scaffold.dart`:`isAnime4KEnabled` getter 改为 `context.anime4KSetting<bool>('enableAnime4K') == true` | 1) `flutter analyze` 通过;2) 行为验证:本地漫画+设备设置开启时按钮出现 |  |

### Implementation Phase 6:gallery 单图模式错误处理(#6)

- GOAL-006: 单图模式网络加载失败时显示错误与重试 UI(经 ComicImage 自带错误 UI 覆盖验证);缩放范围保持 `contained×1.0 ~ covered×10.0` 与多图模式一致,不改动

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-017 | Pending | 验证 `ComicImage` 自带错误+重试 UI(`comic_image.dart:472-518`,`_lastException` 分支)在单图模式(images.dart:397-415)下正常覆盖:加载失败时 ComicImage 显示错误文本与 Retry 按钮。无需额外 errorBuilder。缩放范围两分支一致(images.dart:400-401 vs 422-423),不改动 | 1) 代码走查确认 ComicImage.build 的 `_lastException` 分支在 customChild 下生效;2) 手工验证:断网打开单图模式网络漫画,显示错误信息与 Retry 按钮 |  |

### Implementation Phase 7:ResizeImage 防御性解包(#7)

- GOAL-007: 解包逻辑健壮化,兼容多层嵌套

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-019 | Pending | `lib/pages/reader/comic_image.dart` `_getAnime4KSourceProvider` 改为 `while (provider is ResizeImage) { provider = provider.imageProvider; }`,循环解包;确认 `reader_image.dart` 的 `enableResize` 仅影响 `getTargetSize`,不会重复内嵌 `ResizeImage` | 1) `flutter analyze` 通过;2) 代码走查确认 `_loadSourceBytes`/`_buildCacheKey` 使用解包后真实 provider 加载原图(预期行为) |  |

### Implementation Phase 8:调度器 null 安全(#8)

- GOAL-008: inflight 复用路径不再抛 `null as T`

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-020 | Pending | `lib/super_resolution/runtime/super_resolution_task_scheduler.dart`:第 31 行 `return inflight.then((value) => value as T);` 改为 `return inflight.then((value) => value as T?);`,保持 `schedule` 返回 `Future<T>`;同步更新英文 doc 说明 T 为可空类型时语义 | 1) `flutter analyze` 通过;2) 单测:task 返回 null(T 为 `Uint8List?`)时,schedule 复用路径返回 null 不抛 TypeError |  |

### Implementation Phase 9:pubspec 版本对齐(#9)

- GOAL-009: 锚定与 lock 一致的 image 版本

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-021 | Pending | `pubspec.yaml:89` `image: ^4.2.0` → `image: ^4.8.0`(与 `pubspec.lock` 的 4.8.0 对齐) | 1) `flutter pub get` 成功且 lock 无变化;2) `flutter analyze` 通过 |  |

### Implementation Phase 10:收尾验证

- GOAL-010: 全量静态检查与回归

| Task     | Status  | Description           | Verification Steps         | Date |
| -------- | ------- | --------------------- | -------------------------- | ---- |
| TASK-022 | Pending | 新增单元测试 `test/super_resolution_test.dart`:覆盖 MD5 缓存路径、格式检测(png/jpg)、8MP 降档边界、scheduler null 复用 | 1) `flutter test` 全部通过(含既有测试) |  |
| TASK-023 | Pending | 运行 `dart format lib/super_resolution lib/pages/reader` 与 `flutter analyze`,修复全部告警 | 1) `flutter analyze` 0 error 0 warning;2) `git diff --stat` 确认改动文件清单 |  |
| TASK-024 | Pending | 手工回归清单:网络漫画启用超分(断网+缓存命中)、本地漫画超分、连续模式翻页+章节切换内存释放、gallery 单图错误重试、设置项切换即时生效 | 1) 各场景日志无异常;2) 无重复下载请求;3) 章节切换后内存回落 |  |

## 3. Alternatives

- **ALT-001**: 缓存键用 SHA-256 —— 未采用,项目既有约定为 MD5(`cache_manager.dart:111`),REQ-001 要求跟随约定
- **ALT-002**: 超分字节缓存"解码前原始 Uint8List"(review #2 的第二方案)—— 未采用,需改 `ReaderImageProvider` load 流水线且无法覆盖已渲染页面;CacheManager 落盘字节方案零侵入
- **ALT-003**: 输出统一 JPEG 压缩体积 —— 未采用,用户确认按原格式编码(REQ-007);PNG 源保留 PNG
- **ALT-004**: 收紧 slider max 至 2.0 代替 8MP 上限 —— 未采用,用户确认 8MP 上限策略,保留 4.0 档位并自动降档
- **ALT-005**: gallery 单图用 `PhotoViewGalleryPageOptions.imageProvider` 恢复 errorBuilder —— 未采用:ComicImage 自带错误+重试 UI(`comic_image.dart:472-518`)在 customChild 下已覆盖;保持 customChild 以保留超分功能
- **ALT-006**: 缩放范围回退 photo_view 旧默认(contained×0.8 ~ covered×3.0)与"旧体验"一致 —— 未采用:全项目(单图/多图/loadingBuilder)已统一为 contained×1.0 ~ covered×10.0,回退会造成单图/多图行为分裂

## 4. Dependencies

- **DEP-001**: `package:crypto`(`^3.0.6`,已存在于 pubspec.yaml:23)
- **DEP-002**: `package:image`(`^4.8.0`,TASK-021 升级)
- **DEP-003**: 既有 `CacheManager`(`lib/foundation/cache_manager.dart`)— findCache/writeCache API,无需修改

## 5. Files

- **FILE-001**: `lib/super_resolution/models/super_resolution_output.dart` — 新建,处理器输出(字节+扩展名)
- **FILE-002**: `lib/super_resolution/super_resolution_processor.dart` — process 返回类型改为 `SuperResolutionOutput?`
- **FILE-003**: `lib/super_resolution/implementations/anime4k/anime4k_processor.dart` — 源格式检测、编码、8MP 前置判断
- **FILE-004**: `lib/super_resolution/implementations/anime4k/anime4k_upscaler.dart` — `kMaxOutputPixels` 常量与降档逻辑
- **FILE-005**: `lib/super_resolution/cache/super_resolution_cache_store.dart` — MD5 键 + 扩展名参数
- **FILE-006**: `lib/super_resolution/super_resolution_service.dart` — 缓存读写传扩展名
- **FILE-007**: `lib/super_resolution/runtime/super_resolution_task_scheduler.dart` — inflight null 安全
- **FILE-008**: `lib/pages/reader/comic_image.dart` — CacheManager 字节读取、`releaseAnime4KResult`、设置扩展、while 解包 ResizeImage、UI 时序调整
- **FILE-009**: `lib/pages/reader/reader.dart` — `anime4KSetting` 扩展、`_ImageViewController.releaseAnime4KResults`、toChapter 清理
- **FILE-010**: `lib/pages/reader/images.dart` — 两模式 `releaseAnime4KResults`
- **FILE-011**: `lib/pages/reader/scaffold.dart` — `isAnime4KEnabled` 统一
- **FILE-012**: `pubspec.yaml` — image 版本
- **FILE-013**: `test/super_resolution_test.dart` — 新建单元测试

## 6. Testing

- **TEST-001**: MD5 缓存路径稳定性:同 key 同扩展名路径一致、不同扩展名不同路径
- **TEST-002**: 格式检测:PNG 输入 → png 输出,JPEG 输入 → jpg 输出
- **TEST-003**: 8MP 降档:2828×2828×4.0 降档至 ≤8MP;3000×4000×1.0 跳过处理
- **TEST-004**: scheduler:null 结果经 inflight 复用路径不抛 TypeError
- **TEST-005**: `flutter test` 全量通过(含既有 channel/comic_export/pages 等测试)
- **TEST-006**: 手工回归清单(见 TASK-024)

## 7. Risks & Assumptions

- **RISK-001**: CacheManager.findCache 读取的字节可能经过源站 onResponse 脚本处理,与页面显示字节理论上可不同(现有实现本已如此),超分基于稳定字节,可接受
- **RISK-002**: 8MP 上限导致超 8MP 原图超分直接跳过(返回 null),用户侧表现为"无结果"——日志已记录,设置页文案在后续迭代补充(本期不强制)
- **RISK-003**: 旧缓存文件(`hashCode.abs().png` 命名)成为孤儿文件——位于 getTemporaryDirectory,系统可回收,不迁移
- **ASSUMPTION-001**: `md5` 碰撞在缓存场景可接受(项目既有约定,非安全敏感场景)
- **ASSUMPTION-002**: `img.encodeJpg(quality: 90)` 压缩比与画质平衡满足需求;WebP 源按 JPEG 编码(encodeWebp 质量不足)
- **ASSUMPTION-003**: `toChapter` 是唯一章节切换入口(`toNextChapter`/`toPrevChapter` 均经由它),单点清理可覆盖所有切换路径

## 8. References

- PR #2 审查意见:https://github.com/bgzo-sandbox/venera/pull/2#issuecomment-5230325205
- 哈希约定:lib/foundation/cache_manager.dart:111
- 图片缓存键:lib/network/images.dart:116
- 设置回退逻辑:lib/foundation/appdata.dart:329-338
