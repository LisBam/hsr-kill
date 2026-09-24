# 实施计划：音效音乐体系

> 依据 `prd.md` + `design.md`。执行顺序按「依赖由内向外」：纯逻辑 → 服务 → 核心事件 → 内容层基类 → 场景装配 → 界面 → 测试 → 文档。
> 每阶段结束都必须能独立验证；任一阶段失败即回滚该阶段文件，不带病前进。

---

## 零、开工前检查（`task.py start` 之前）

- [ ] 已读 `.trellis/spec/project/*`、`.trellis/spec/ui/index.md`、`.trellis/spec/adapters/index.md`、`.trellis/spec/content/index.md`（本次触碰内容层基类）。
- [ ] 已确认 `git status` 干净，便于逐阶段回滚。
- [ ] 已定位可用的 Godot 可执行文件（命令行回归）或确认改用编辑器 MCP 运行测试场景。
- [ ] 已确认本次不触碰禁读/禁改路径。

---

## 一、阶段 P0：音频内容目录占位

- [ ] 创建 `res://game_data/skills/audio/`、`res://game_data/cards/audio/`、`res://game_data/BGM/`。
- [ ] 每个目录放置 `.gitkeep` 占位（Git 不跟踪空目录；`.gitkeep` 无 Godot 导入器，不会被导入）。
- [ ] 验证：
  - `filesystem_manage(op="scan")` 后无导入报错；
  - 运行 `tests/smoke_test.tscn` 仍 PASS（确认 `GameDatabase.validation_errors` 为空 —— 子目录未被内容扫描误读）。

**回滚点**：删除三个目录。

---

## 二、阶段 P1：`GameSettings` 音频字段与持久化

文件：`scripts/autoload/game_settings.gd`（风险：中）

- [ ] 顶部新增常量（逐行注释说明用途/范围/默认值原因/修改影响）：`AUDIO_VOLUME_MIN`、`AUDIO_VOLUME_MAX`、`AUDIO_VOLUME_STEP`、`DEFAULT_BGM_VOLUME`、`DEFAULT_SFX_VOLUME`、`DEFAULT_AUDIO_MUTED`。
- [ ] 信号区新增 `bgm_volume_changed(value: float)`、`sfx_volume_changed(value: float)`、`audio_muted_changed(muted: bool)`（**不删除、不重排**既有信号）。
- [ ] 新增变量 `bgm_volume`、`sfx_volume`、`audio_muted`（含独占行注释）。
- [ ] 新增 setter `set_bgm_volume_linear` / `set_sfx_volume_linear` / `set_audio_muted`，沿用「变化才写 → `_queue_settings_save()` → 发信号」模式。
- [ ] `_load_saved_settings()` 新增三行读取（`clampf` + 默认值回退），**不改动任何既有读取行**。
- [ ] 验证：`tests/game_settings_persistence_test.tscn` 仍 PASS。

**回滚点**：`git checkout -- scripts/autoload/game_settings.gd`。

---

## 三、阶段 P2：`AudioCatalog`（纯逻辑，可先行单测）

文件：`scripts/audio/audio_catalog.gd`（新增）

- [ ] `class_name AudioCatalog extends RefCounted`。
- [ ] 顶部常量：`SKILL_AUDIO_DIR`（`res://game_data/skills/audio`）、`CARD_AUDIO_DIR`（`res://game_data/cards/audio`）、`BGM_DIR`（`res://game_data/BGM`）、`AUDIO_EXTENSIONS`、`MAX_POOL_SIZE`、`NAME_SYSTEM_CUSTOM`、`NAME_SYSTEM_ORIGINAL`、`BGM_SCENE_MENU`、`BGM_SCENE_BATTLE`。
- [ ] 纯函数接口（无副作用、无节点依赖）：
  - `build_skill_voice_candidates(skill_id: String, character_id: String) -> Array[String]`（按 3.1 四级优先级 + 池序号展开）
  - `build_card_voice_candidates(card_id: String, current_name_system: String) -> Array[String]`（按 3.2 两级回退）
  - `build_bgm_candidates(scene_id: String) -> Array[String]`（池序号展开）
  - `resolve_existing_audio_path(candidates: Array[String]) -> String`
  - `load_audio_stream(path: String) -> AudioStream`（带缓存 + `clear_cache()` 诊断）
- [ ] 注释写明：为何不用目录扫描（导出包导入改名）、序号上限原因、扩展名优先级原因、池化短路语义。
- [ ] 验证：本阶段即可在 P9 的测试场景中先跑纯逻辑用例。

**回滚点**：删除该文件。

---

## 四、阶段 P3：`AudioVoicePlayer` 与 `AudioBgmPlayer`

文件：`scripts/audio/audio_voice_player.gd`、`scripts/audio/audio_bgm_player.gd`（新增）

- [ ] `AudioVoicePlayer`：
  - `@export`：`avoid_immediate_repeat`（池内随机时不连续重复）。**不作并发限流** —— 主公钦定不要并发上限与最小重播间隔。
  - 播放器**按需分配**：空闲池优先复用，不足时新建 `AudioStreamPlayer`（`bus = "SFX"`），播放结束经 `finished` 信号回收到空闲池。
  - `play_stream(stream: AudioStream, dedup_key: String) -> bool`：同键去重后立即播放；返回是否实际播放。
  - `pick_random_candidate(candidates: Array[String], catalog: AudioCatalog) -> AudioStream`：池内随机且避免连续重复。
  - `get_active_voice_count()` / `stop_all()`。
- [ ] `AudioBgmPlayer`：
  - `@export`：`fade_duration_seconds`、`bgm_bus_name`。
  - `play_scene(scene_id, candidates, catalog)`：同场景幂等；跨场景淡出旧曲 → 淡入新曲；
  - 循环由代码设置（`AudioStreamOggVorbis.loop` / `AudioStreamMP3.loop` / `AudioStreamWAV.loop_mode`），**不依赖导入选项**。
  - `get_current_scene_id()` / `get_playback_position()`。
- [ ] 两组件均不得引用 `MatchController` / `GameState` / `GameDatabase`。

**回滚点**：删除两文件。

---

## 五、阶段 P4：`AudioService`（Autoload 门面）

文件：`scripts/autoload/audio_service.gd`（新增）+ autoload 注册

- [ ] 注册顺序：`GameSettings` → `GameDatabase` → `AudioService`；用 `autoload_manage(op="add")`（`project_manage(settings_set)` 会拒绝 `autoload/*`）。
- [ ] `_ready`：确保 `BGM` / `SFX` 总线存在并挂 `Master`；创建 `AudioCatalog`、`AudioVoicePlayer`、`AudioBgmPlayer` 子节点；订阅 `GameSettings` 三个音频信号并立即同步一次音量。
- [ ] 实现 `play_voice_presentation(data)`：按 `kind` 分派；卡牌名称体系实时读 `GameSettings.card_name_mode`。
- [ ] 实现 BGM / 音量 / 诊断接口（签名见 `design.md` 第六节，不得增删隐式参数）。
- [ ] 缺失音频默认静默；`@export var debug_log_missing_audio: bool = false` 控制诊断输出。
- [ ] 防御：`GameSettings` 为空（独立单测实例）时不崩溃。
- [ ] 验证：编辑器运行主场景，`logs_read(source="editor")` 无脚本错误。

**回滚点**：删除文件 + `autoload_manage(op="remove", name="AudioService")`。

---

## 六、阶段 P5：核心层音频请求通道（最高风险）

文件：`scripts/core/match_controller.gd`（15387 行，风险：高）

- [ ] 信号区新增 `voice_presentation_requested(presentation_data: Dictionary)` + 逐行 `##` 注释（位置紧跟既有表现信号之后，不重排）。
- [ ] 新增去重表 `_voice_request_tokens: Dictionary` 与常量 `VOICE_DEDUP_WINDOW`。
- [ ] 新增 `request_skill_voice(player_id: int, skill_id: String) -> void`：
  - 防御（对局状态、玩家有效性）→ 取 `character_id` → 组装负载（`kind="skill"`、`character_id`、`event_token`）→ 去重 → `emit`。
- [ ] 新增 `request_card_voice(player_id: int, card_definition_id: String, play_mode: String) -> void`：
  - 防御 → 取 `GameDatabase.get_card(...)` 的 `custom_name` / `original_name` → 组装负载 → 去重 → `emit`。
- [ ] 新增私有辅助 `_should_skip_auto_voice(definition, skill_instance)`：处理 `"voice_trigger" == "manual"` 与技能实例抑制窗口。
- [ ] 默认触发点：
  - `record_skill_activation`（:8967）**函数开头**：按技能实例抑制窗口判断后调 `request_skill_voice(player_id, skill_id)`；
  - `_execute_use_card_declare`（:11524 区块）：紧随 `_request_card_presentation(..., "useCard", ...)` 调 `request_card_voice(actor_id, card.definition_id, "use")`；
  - `_consume_response_card_uid_patterns`（:5193 之后）：调 `request_card_voice(player_id, logical_definition_id, "respond")`；
  - `_consume_skill_converted_response` / 装备响应出口：调 `request_card_voice(..., 虚拟定义ID, "respond")`。
- [ ] 联机：`_bind_replication_handlers` 追加连接；新增 `_replicate_voice_presentation_event`；`_on_network_game_event_received` 追加 `voice_presentation` 分支。
- [ ] 验证（本阶段必跑）：`tests/gameplay_regression_test.tscn`、`tests/smoke_test.tscn`、`tests/lan_match_flow_test.tscn`（若环境不允许 UDP 回环则如实记录为未验证）。

**回滚点**：`git checkout -- scripts/core/match_controller.gd`（本阶段独立提交）。

---

## 七、阶段 P6：内容层基类 `play_voice()` 转发入口

文件：`game_data/skill_definition.gd`、`game_data/card_definition.gd`（风险：中——被全部内容源码继承）

- [ ] `SkillDefinition` **新增** `play_voice() -> void` 与实例变量 `_explicit_voice_request_msec`（含独占行注释）；**不得修改**任何既有成员与签名。
- [ ] `CardDefinition` **新增** `play_voice(actor_id: int = -1) -> void`；**不得修改**既有成员与签名。
- [ ] 两者均做 `has_method` 防御，核心端口缺失时静默返回。
- [ ] 验证：`tests/smoke_test.tscn`（全部 144 技能与 92 卡牌实例化）仍 PASS；`tests/ai_policy_test.tscn` 确认内容层未被破坏。
- [ ] 在 `docs/内容制作指南.md` 记录用法（属于 P10，但此处先起草示例）。

**回滚点**：`git checkout -- game_data/skill_definition.gd game_data/card_definition.gd`。

---

## 八、阶段 P7：场景装配与桥接组件

文件：`scripts/audio/game_audio_bridge.gd`（新增）+ `scenes/main.tscn`

- [ ] 新建 `GameAudioBridge`（行为见 `design.md` 第七节，`@export` 两个 `NodePath`，`_exit_tree` 全断开）。
- [ ] 场景改动**必须经编辑器 MCP 工具**：先 `scene_open("res://scenes/main.tscn")` → `node_create`（`parent_path="."`，名 `AudioBridge`）→ `script_attach` → `node_set_property` 设置两个路径 → `scene_save`。
- [ ] 设置 `NodePath` 属性前先 `node_get_properties` 核对属性名与类型（禁止猜名）。
- [ ] 验证：`git diff scenes/main.tscn` 逐行复核（只应新增一个节点与一条 ext_resource，无无关节点重排/UID 变更）；运行主场景后 `logs_read` 无错误、无文件时不刷屏。

**回滚点**：`git checkout -- scenes/main.tscn` + 删除桥接脚本。

---

## 九、阶段 P8：主菜单音频设置界面

文件：`scenes/main.tscn`（`MainMenu/MainMenuSettingsPanel/SettingsVBox`）+ `scripts/ui/main_menu.gd`

- [ ] 先读现有相邻控件（`MainMenuGameSpeedSlider` 及其 `Label`）的实际结构，照抄容器、尺寸、`size_flags`、`unique_name_in_owner` 约定。
- [ ] 新增六个控件：BGM `Label` + `HSlider`、SFX `Label` + `HSlider`、静音 `CheckBox`（命名见 `design.md` 第九节）。
- [ ] `main_menu.gd`：新增 `@onready` 引用（`%` 形式）、初始化值与绑定、订阅三个设置信号做回显。
- [ ] 主题：颜色经 `BattleUIStyle` 读取；新增文本控件纳入统一字体色覆盖；占位文本用 ASCII 半角。
- [ ] 验证（必跑）：`tests/font_color_audit_test.tscn`、`tests/ui_layout_test.tscn`、`tests/main_menu_test.tscn`。
- [ ] 手动验收：拖动滑条音效即时变化；静音后 BGM 与语音同时静音；重启后保留。

**回滚点**：`git checkout -- scenes/main.tscn scripts/ui/main_menu.gd`。

---

## 十、阶段 P9：测试场景

- [ ] 新增 `tests/audio_system_test.gd` + `tests/audio_system_test.tscn`（`extends Node`、`_ready` 内断言、成功打印 `AUDIO_SYSTEM_PASS ...`、失败 `push_error`）。
- [ ] 用例按 `design.md` 第十二节表格实现：优先级顺序、池化短路、角色 id 含下划线、卡牌体系回退、虚拟定义、BGM 池、缺失静默、去重、播放器按需分配与回收、设置持久化、BGM 幂等。
- [ ] 逻辑用例不依赖真实音频文件；播放行为用例断言「无文件时未播放」。
- [ ] 验证：运行本场景取得 PASS，记录**实际输出文本**。

**回滚点**：删除测试两文件。

---

## 十一、阶段 P10：文档同步（缺一不可）

- [ ] `docs/内容制作指南.md`：新增「音频内容制作」章节 —— 三处目录、技能四级优先级表、卡牌两级回退表、角色专属规则、`play_voice()` 用法与 `"voice_trigger":"manual"` 说明、投放步骤。
- [ ] `docs/游戏机制与玩法内容.md`：音频体系数值表（音量默认值/范围/步长、淡入淡出时长、池序号上限、技能抑制窗口、去重表容量、BGM 场景划分与切换语义；**并注明不做并发限流**）。
- [ ] `docs/界面与交互.md`：音频设置项位置、控件名、取值范围与交互行为。
- [ ] `docs/架构说明.md`：音频表现层组件与单向数据流（若存在对应章节）。
- [ ] `README.md`：「自动校验」章节补充 `audio_system_test` 逐项说明。
- [ ] `临时反馈文档.md`：时间戳 + 学习反馈摘要 + Git 提交描述。

---

## 十二、完成门禁（报告完成前必须全部满足）

- [ ] AC1–AC11 逐条核对并给出证据（命令 + 实际输出），不得写「应该通过」。
- [ ] 至少运行：`audio_system_test`、`gameplay_regression_test`、`smoke_test`、`game_settings_persistence_test`、`main_menu_test`、`font_color_audit_test`、`ui_layout_test`，全部 PASS 或给出失败原因与处置。
- [ ] `GameDatabase.validation_errors` 为空、可正常开局。
- [ ] `git diff --stat` 复核改动范围与预期一致；`main.tscn` 无无关变更。
- [ ] 「配套逻辑补全告知」已按 `项目专属AGENTS.md` 要求在输出末尾单独列出（技能抑制窗口、去重表容量、池化短路、BGM 循环代持、播放器按需分配等需求未明示项）。
- [ ] 学习反馈摘要 + Git 提交描述已产出并追加至 `临时反馈文档.md`。

---

## 十三、高风险文件与回滚索引

| 文件 | 风险 | 回滚命令 |
|---|---|---|
| `scripts/core/match_controller.gd` | 高（15387 行核心控制器） | `git checkout -- scripts/core/match_controller.gd` |
| `scenes/main.tscn` | 高（4.7 格式含 `unique_id`） | `git checkout -- scenes/main.tscn` |
| `game_data/skill_definition.gd` / `card_definition.gd` | 中（全部内容继承） | `git checkout -- game_data/skill_definition.gd game_data/card_definition.gd` |
| `scripts/ui/main_menu.gd` | 中（1999 行） | `git checkout -- scripts/ui/main_menu.gd` |
| `scripts/autoload/game_settings.gd` | 中（全项目读取） | `git checkout -- scripts/autoload/game_settings.gd` |
| `project.godot` | 中（autoload 注册） | `autoload_manage(op="remove", name="AudioService")` |
| 新增文件与目录 | 低 | 直接删除 |
