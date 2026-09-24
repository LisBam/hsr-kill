# 音效音乐体系（技能音效·卡牌音效·BGM）

## Goal

为《崩铁杀》从零引入音频表现体系：技能语音（按技能 id 命名 + 角色专属覆盖 + 多音效随机）、卡牌语音（按卡牌 id + 名称体系命名，使用与打出均触发）、主菜单与战斗 BGM，并配套音量设置持久化与内容目录约定。后续只需按规范投放音频文件即可生效，无需改动代码。

## Background（勘察确认的事实）

### 既有实现与锚点

- 全量搜索 `scripts/`、`game_data/`、`scenes/`、`project.godot`：项目**当前不存在任何音频实现**（无 `AudioStreamPlayer`、无 `AudioServer` 调用、无自定义音频总线、无 `.ogg`/`.wav`/`.mp3` 资源）。属全新功能。
- **技能发动的唯一统一出口**：`MatchController.record_skill_activation(player_id, skill_id, context)`（`match_controller.gd:8967`）。全项目仅 `skill_definition.gd:165`（`announce_activation`）与 `skill_definition.gd:181`（`announce_activation_for_player`）两处调用它，因此挂此一处即可覆盖全部 144 个技能的发动，含触发技与领袖技（`announce_activation_for_player` 携带的发动者即音色归属者）。技能实际发动的表现信号在 `match_controller.gd:8999` 发布。
- **卡牌使用的统一出口**：`_execute_use_card_declare` 内 `_request_card_presentation(..., "useCard", ...)`（`match_controller.gd:11524`）。
- **卡牌打出的统一出口**：`_consume_response_card_uid_patterns`（`match_controller.gd:5139-5197`，响应日志见 :5193）。该出口**当前没有语义化表现信号**，只产生 `card_transfer_requested` 与 `log_added`。
- **打出的牌不会回调牌源文件**：以【闪】为例，`shan.gd:33` 的 `resolve()` 只返回 `"discard"`；打出【闪】走核心层消耗实体牌，不调用牌源文件任何函数。故卡牌音效必须由核心统一出口覆盖，不能依赖牌源文件。
- 技能源码基类 `SkillDefinition`（`game_data/skill_definition.gd`）持有 `owner_player_id`（:10）、`host`（:13），提供 `get_id()`（:99）、`announce_activation()`（:157）。技能文件经 `host.call("...")` 访问核心端口（`gangfeng.gd:109`）。
- 卡牌源码基类 `CardDefinition`（`game_data/card_definition.gd`）持有 `runtime_host` / `runtime_owner_player_id` / `runtime_card_uid`（:10-16），提供 `get_id()`（:30）与 `resolve()`（:114）。
- 卡牌数据同时带 `original_name` 与 `custom_name`（`sha.gd:10-11`）；`GameSettings.resolve_card_name()`（`game_settings.gd:953`）按当前 `card_name_mode` 返回其一。
- `gangfeng.gd`（罡风）、`wangpai.gd`（王牌）、`qiong.gd`（穹）、`xing.gd`（星）均确实存在，需求举例与项目内容吻合。

### 目录与扫描行为（安全性已验证）

- `GameDatabase._list_gd_scripts()`（`game_database.gd:372-396`）使用 `DirAccess.get_files()` **单层**枚举，只接受 `.gd` / `.gd.remap` / `.gdc` / `.gde`。故在 `game_data/skills/`、`game_data/cards/` 下新建 `audio/` 子目录**不会被误当内容源码**，`validation_errors` 不受影响。
- `_load_decks()` 读取固定文件路径（`game_database.gd:348`）、`_load_factions()` 同理（:355），**不遍历 `game_data/` 根目录**，故新建 `game_data/BGM/` 安全。
- 内容源码文件名规范（`game_database.gd:393`）：仅允许小写字母、数字与下划线 → 技能 id 与文件名一致（`gangfeng`、`wangpai`），与需求给出的音频命名基准完全一致。

### 场景、设置与网络

- `scenes/main.tscn` 为唯一场景（`project.godot` 的 `run/main_scene`），根节点 `Main` 挂 `scripts/ui/match_table.gd`，内含 `MainMenu`、`MatchMenu`、`CharacterSelectionPanel` 等；`match_table.gd` 连接 `main_menu.start_game_requested`（:548）与 `match_menu.main_menu_requested`（:542）。`MainMenu` 的开局/回菜单可见性切换在 `main_menu.gd:1313`（`visible = false`）与 `main_menu.gd:1361-1362`（`visible = true`）。
- 主菜单设置面板 `MainMenu/MainMenuSettingsPanel` 已含卡名模式、UI 风格、各类开关与 `HSlider`；局内 `MatchMenu/MenuPanel/MenuVBox` 结构较简。
- `GameSettings` 自动加载已具备 `ConfigFile` 持久化、防抖写盘（0.25s）、变更信号广播、旧档缺失字段回退。
- 网络：表现信号由主机经 `broadcast_game_event` 广播（`match_controller.gd:614-625, 14644-14710`），客户端在 `_on_network_game_event_received`（:14342）分派回同名信号。
- **联机约束**：技能与卡牌的效果代码只在**主机权威逻辑**中执行，客户端不执行。故内容层发起的音频请求必须经核心层表现事件通道广播，否则联机客户端无声。

### 铁律与测试约定

- **界面层铁律**（`.trellis/spec/ui/index.md`）：界面/表现组件**禁止读取 `GameState`、`MatchController` 或技能运行时实例**。音频表现层所需数据必须由核心层随表现事件下发。
- 测试约定（`.trellis/spec/project/verification.md`）：不使用外部框架，测试即场景，运行后打印 `*_PASS`；新增测试须同步 `README.md`；新增文本控件须跑 `font_color_audit_test.tscn`，界面改动须跑 `ui_layout_test.tscn`。

## Requirements

### R1 音频内容目录（需求钦定）

- R1.1 **技能音效**：`res://game_data/skills/audio/`。
- R1.2 **卡牌音效**：`res://game_data/cards/audio/`。
- R1.3 **BGM**：`res://game_data/BGM/`。
- R1.4 支持 `.ogg` / `.wav` / `.mp3`，按扩展名优先级探测（`.ogg` → `.wav` → `.mp3`），不要求统一格式。
- R1.5 文件发现采用「确定基名 + 序号 + 扩展名优先级」探测，**不使用目录扫描**（导出包中导入资源磁盘名会变为 `.oggvorbisstr` 等，扫描不可靠）。

### R2 技能语音

- R2.1 触发时机：技能**实际发动**成立时（统一出口 `record_skill_activation`）；内容层亦可显式调用自定义时机（见 R8）。
- R2.2 命名与查找优先级（以技能源码文件名为基准，即技能 id）：
  1. `<技能id>_<角色id>_<序号>` —— 该角色的专属多音效池
  2. `<技能id>_<角色id>` —— 该角色的专属单音效
  3. `<技能id>_<序号>` —— 通用多音效池
  4. `<技能id>` —— 通用单音效
  5. 全部缺失 → 不播放
  - 示例：穹发动【王牌】先找 `wangpai_qiong_1`、`wangpai_qiong_2`…，无则找 `wangpai_1`、`wangpai_2`…，最后找 `wangpai`。
  - 角色 id 取**发动者**的武将 id（`announce_activation_for_player` 场景下为实际发动者，如 `qiong`、`xing`、`qiong_cunhu`）。因是**正向拼接**（已知技能 id 与角色 id）而非反向解析，角色 id 内含下划线亦无歧义。
- R2.3 多音效随机：同一池内随机选择一个；避免与上一次播放的同一技能音效连续重复。
- R2.4 无文件时不播放、不报错。
- R2.5 音色归属由**角色专属文件**表达（不按性别分目录）；未投放专属文件时回退通用音效，满足「同一技能被不同角色拥有则有不同音效」的诉求。

### R3 卡牌语音

- R3.1 播放时机：一张牌被**使用**或被**打出**时各播放一次。
- R3.2 音色归属与播放范围：由**使用者**决定，与本地玩家是谁无关；**全场都播**（D5）。
- R3.3 命名与查找优先级（需求钦定）：
  1. `<卡牌id>_<当前名称体系>` —— 当前卡名模式对应体系（`custom` / `original`）
  2. `<卡牌id>_<另一名称体系>` —— 回退到另一体系
  3. 全部缺失 → 不播放
  - 示例：`sha_custom.ogg`（崩铁杀牌名配音）与 `sha_original.ogg`（三国杀牌名配音）；当前模式为崩铁杀时优先取 `sha_custom`，缺失则取 `sha_original`。
- R3.4 「打出」由响应消耗统一出口覆盖，不依赖牌源文件回调（见 Background）。
- R3.5 虚拟牌 / 视为牌按实际结算的虚拟牌定义播放（如罡风转化为 `sha_thunder`）。
- R3.6 **不做并发限流（需求钦定）**：同一时刻多张牌同时结算（如 AOE）时各音效同时播放，**不设并发上限、不设最小重播间隔**；播放器按需分配、播放完毕回收。

### R4 BGM

- R4.1 场景划分（需求钦定 D3）：仅两类 BGM —— 主菜单 BGM 与战斗 BGM。
- R4.2 切换语义：处于主菜单时播放主菜单 BGM；进入对局后（含**选将**、战斗、**结算**等全部局内阶段）延续播放战斗 BGM，**不得中途中断或重播**；返回主菜单时切回主菜单 BGM。
- R4.3 BGM 必须循环播放（由运行时代码保障，不依赖导入选项）；同一 BGM 重复请求为幂等操作。
- R4.4 BGM 切换需带淡入淡出（时长可配置），避免硬切爆音。
- R4.5 命名：`game_data/BGM/menu.<ext>` 与 `game_data/BGM/battle.<ext>`；可追加 `menu_2`…`menu_9`、`battle_2`…`battle_9` 构成候选池，随机选曲。

### R5 音量与音频设置（需求钦定 D2：需要，并持久化）

- R5.1 设置项：BGM 音量、音效音量、静音总开关。
- R5.2 持久化：写入现有 `user://game_settings.cfg` 的 `gameplay` 分组，缺失字段回退脚本默认值（旧存档不得因此报错或重置其他设置）。
- R5.3 实时生效：调整即时作用于音频总线，无需重启或重开对局。
- R5.4 界面入口：主菜单设置面板必做；局内菜单本次不新增（不阻塞验收）。
- R5.5 音量实现走 `AudioServer` 总线（`BGM` / `SFX` 两条独立总线，挂到 `Master`）。

### R6 工程约束与接口稳定性

- R6.1 音频播放属**表现层**，不得改写 `GameState`、不得参与网络权威状态同步。
- R6.2 对外暴露稳定接口，可调参数一律 `@export` 或顶部常量，禁止散落魔法数字。
- R6.3 全部音频文件缺失时，完整对局流程必须零报错、零警告刷屏。
- R6.4 **联机正确性**：内容层发起的音频请求必须经核心层表现事件通道广播，保证联机客户端同样发声。
- R6.5 表现层组件不得读取 `GameState` / `MatchController`（界面层铁律）；所需数据由核心层随事件下发。
- R6.6 新增/复用逻辑必须可独立测试，测试脚本放入 `tests/` 并纳入 README 的逐项测试说明。

### R7 文档同步

- R7.1 `docs/内容制作指南.md`：音频目录约定、命名与查找优先级、角色专属规则、触发函数用法、投放步骤。
- R7.2 `docs/游戏机制与玩法内容.md`：音频体系全部具体数值（音量默认值/范围/步长、淡入淡出时长、并发上限、最小重播间隔、池序号上限等）。
- R7.3 `docs/界面与交互.md`：新增设置项的位置、控件名、取值范围与交互约定。
- R7.4 `README.md`：补充新增测试场景的逐项说明。
- R7.5 `临时反馈文档.md`：追加学习反馈摘要与 Git 提交描述。

### R8 触发方式（需求钦定 D8 / D9）

- R8.1 **统一出口默认触发**：技能在 `record_skill_activation` 自动请求播放；卡牌在「使用」与「打出」两个统一出口自动请求播放。既有 144 个技能与 92 张卡牌**零改动即生效**，未来新内容不会漏写。
- R8.2 **内容层可显式覆盖**：向内容层公开统一播放函数（技能 `play_voice()`、卡牌 `play_voice(actor_id)`），可写在效果代码中自定义时机。
- R8.3 **不重复发声**：同一次发动/使用内，若内容层已显式请求，统一出口不再重复请求（以事件令牌去重）；内容层亦可声明 `"voice_trigger": "manual"` 完全接管本次触发。
- R8.4 请求**不在内容层直接操作播放器**，一律经核心层表现事件通道派发（信号 + 联机广播），表现层订阅后播放（满足 R6.4、R6.5）。
- R8.5 触发时机：技能取「实际发动成立」时点；卡牌「使用」取声明时点、「打出」取响应消耗时点，保证音效与画面同步。

## Acceptance Criteria

- [ ] AC1 未投放任何音频文件时，从主菜单开局到结算返回主菜单全程无报错、无警告刷屏。
- [ ] AC2 投放 `game_data/skills/audio/gangfeng.ogg` 后，任意角色发动【罡风】播放该音效。
- [ ] AC3 同时投放 `wangpai_qiong_1.ogg` 与 `wangpai_1.ogg` 后，穹发动【王牌】播放专属音效，其他角色发动播放通用音效；两者皆无则不播放。
- [ ] AC4 同一技能投放 4 个音效文件时，多次发动随机命中，且不出现连续两次同一文件。
- [ ] AC5 一张牌被「使用」与被「打出」（使用【杀】、响应时打出【闪】）都能触发卡牌音效。
- [ ] AC6 卡名模式为崩铁杀且 `sha_custom.ogg` 缺失、`sha_original.ogg` 存在时，使用【杀】播放到 `sha_original`（名称体系回退生效）。
- [ ] AC7 主菜单播放主菜单 BGM；点击开局后进入选将、战斗、结算全程播放战斗 BGM 且不中断不重播；返回主菜单后切回主菜单 BGM。
- [ ] AC8 音量/静音调整即时生效，重启游戏后设置保留。
- [ ] AC9 新增测试场景通过，且既有回归测试（`gameplay_regression_test` / `smoke_test` / `game_settings_persistence_test` / `main_menu_test` / `ui_layout_test` / `font_color_audit_test`）不因本次改动失败。
- [ ] AC10 联机对局中，客户端能听到由主机权威逻辑触发的技能与卡牌音效。
- [ ] AC11 R7 所列文档全部同步完成。

### 验收结果（2026-09-24 16:48）

| 用例 | 验证方式 | 证据 |
| --- | --- | --- |
| AC1 | 未投放素材下运行冒烟与音频测试 | 输出仅含 PASS，无 WARNING 与 SCRIPT ERROR |
| AC2 | 技能四级解析第四级 `<技能ID>` | `skill_tier_common_single` 断言通过 |
| AC3 | 专属音效优先与全部缺失时静默 | `skill_tier_exclusive_pool` / `skill_tier_missing` 断言通过 |
| AC4 | 池内随机且避免连续重复 | `voice_player_avoid_immediate_repeat` 连续抽样 30 次断言通过 |
| AC5 | 真实对局中自动触发使用与打出两种模式 | `auto_trigger=ok`，同时收到 `use` 与 `respond` 负载 |
| AC6 | 卡牌双名称体系双向回退 | `card_fallback_to_original` 断言通过 |
| AC7 | BGM 同场景幂等与场景切换 | `bgm_same_scene_idempotent` / `bgm_scene_switch` 断言通过；`GameAudioBridge` 以 `MainMenu.visibility_changed` 作为唯一锚点 |
| AC8 | 音量与静音即时生效 | `audio_bgm_volume_db` / `audio_mute_both_buses` / `audio_zero_volume_uses_mute` 断言通过；持久化由 `game_settings_persistence_test` 覆盖 |
| AC9 | 全套回归 | `game_settings_persistence` / `main_menu` / `ui_layout` / `font_color_audit` / `smoke` / `gameplay_regression` / `audio_system` / `lan_match_flow` 全部 PASS |
| AC10 | 广播与客户端分派连接存在 | `voice_presentation_not_replicated` / `voice_presentation_client_dispatch_missing` 断言通过 |
| AC11 | R7 文档同步 | 内容制作指南、游戏机制与玩法内容、界面与交互、架构说明、README 全部更新 |

说明：AC2 / AC3 / AC6 / AC7 的“实际发声”依赖真实音频素材的投放，本次以候选路径解析与播放组件的行为断言覆盖；素材投放后不需要任何代码改动即可生效。

## Key Decisions（需求已钦定）

- D1 卡牌音效命名：`<卡牌id>_<名称体系>`（`custom` / `original`），按当前卡名模式优先、缺失回退另一体系。
- D2 音频设置：**需要**音量与静音设置，并持久化。
- D3 BGM 场景范围：**仅主菜单 BGM 与战斗 BGM**；进入对局后选将、结算等阶段延续战斗 BGM，不刻意中断。
- D4 音效文件当前**尚不存在**，本次交付为目录 + 接口 + 逻辑 + 设置 + 文档，素材后续投放。
- D5 音效播放范围：**全场都播**（本机、AI、其他玩家）。
- D6 音频目录位置：技能 `game_data/skills/audio/`；卡牌 `game_data/cards/audio/`；BGM `game_data/BGM/`。
- D7 技能音效命名：以技能源码文件名为基准（`<技能id>`），支持角色专属覆盖（`_<角色id>`）与多音效随机（`_<序号>`）。
- D8 触发方式：内容层调用统一播放函数，与效果写在一起，默认发动一开始执行。
- D9 触发落地：统一出口默认触发 + 内容层可显式覆盖（同一次内不重复发声）。
- D10 BGM 命名：`menu` / `battle` 基名 + 可选 `_2`…`_9` 候选池（拟定，随本方案一并待确认）。

## Out of Scope

- 不制作任何音频素材本身（当前无文件）。
- 不做语音字幕、口型、语音包切换、多语言语音。
- 不做联机语音（VoIP）传输；音频纯本地表现。
- 不做音效编辑器 / 运行时热重载工具。
- 不做回放音频重播。
- 不改动任何规则结算、AI 决策、网络协议与快照结构。
