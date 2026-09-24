# 技术设计：音效音乐体系

> 依据 `prd.md`（R1–R8、AC1–AC11、D1–D10）。本文件只记录技术设计与契约。

---

## 一、分层与数据流

### 1.1 归属

| 产物 | 归属层 | 依据 |
|---|---|---|
| `scripts/audio/*.gd` | 表现层（与 `scripts/ui/` 同级职责，独立子目录） | 只消费核心层下发的只读表现事件 |
| `scripts/autoload/audio_service.gd` | 适配层 `scripts/autoload/` | 与 `GameSettings`、`GameDatabase` 同为全局服务 |
| `MatchController` 新增信号与端口 | 核心层 | 事件运行时 → 表现层的单向下行通道 |
| `SkillDefinition.play_voice()` / `CardDefinition.play_voice()` | 内容层基类 | 供内容源码调用的转发入口，不含播放实现 |
| `scenes/main.tscn` 新增桥接节点、设置控件 | 场景装配 / 界面层 | 复用既有结构与主题 |

### 1.2 完整数据流

```
内容层（技能/卡牌源码，可选写一行）
        │  play_voice()
        ▼
技能文件 ──host──▶ MatchController.request_skill_voice(player_id, skill_id)   ┐
卡牌文件 ─host──▶ MatchController.request_card_voice(player_id, card_id, mode) ├─ 内容层显式入口
                                                                              ┘
核心层统一出口（默认触发，零改动覆盖既有内容）
   • 技能发动：record_skill_activation()（match_controller.gd:8967）
   • 卡牌使用：_execute_use_card_declare()（match_controller.gd:11524 区块）
   • 卡牌打出：_consume_response_card_uid_patterns()（match_controller.gd:5139-5197）
        │  同一去重键 → 直接丢弃（不重复发声）
        ▼
MatchController 组装只读负载（角色 id / 两套牌名 / 动作模式）
        │  emit voice_presentation_requested(presentation_data)
        ├──▶ 本机：GameAudioBridge → AudioService → 播放
        └──▶ 联机：broadcast_game_event("voice_presentation") → 各客户端
                     → _on_network_game_event_received → 本地 emit → 同上播放
```

**铁律遵守**：音频层从不回写 `GameState`；表现层不读 `GameState` / `MatchController`（性别与牌名等由核心层随负载下发，角色 id 亦由核心层解析后下发）。

---

## 二、组件划分（单一职责）

| 组件 | 文件 | 唯一职责 | 依赖 |
|---|---|---|---|
| `AudioCatalog` | `scripts/audio/audio_catalog.gd` | **纯函数**：逻辑请求 → 候选资源路径链 → 命中路径 → `AudioStream`（带缓存）。不播放、不碰节点树 | 仅 `ResourceLoader` |
| `AudioVoicePlayer` | `scripts/audio/audio_voice_player.gd` | 语音播放：播放器按需分配与回收、同键去重、池内随机且不连续重复（**不做并发限流** —— 需求钦定取消并发上限与最小重播间隔） | 受控于 `AudioService` |
| `AudioBgmPlayer` | `scripts/audio/audio_bgm_player.gd` | BGM：循环、淡入淡出、同场景幂等 | 受控于 `AudioService` |
| `GameAudioBridge` | `scripts/audio/game_audio_bridge.gd` | **翻译**：订阅核心表现信号与主菜单可见性 → 调 `AudioService`；零播放逻辑 | 只连接信号 |
| `AudioService` | `scripts/autoload/audio_service.gd` | **门面 + 总线**：组装三组件、确保 `BGM`/`SFX` 总线、订阅设置变化、暴露稳定接口 | `GameSettings` |

---

## 三、内容目录与命名契约

```
res://game_data/
├── skills/
│   ├── gangfeng.gd                    # 技能源码（技能 id = 文件名）
│   └── audio/                         # ★ 技能音效（素材投放）
│       ├── gangfeng.ogg               #   通用单音效
│       ├── gangfeng_1.ogg … _8.ogg    #   通用多音效池（随机）
│       ├── wangpai_qiong.ogg          #   穹专属单音效
│       └── wangpai_qiong_1.ogg …      #   穹专属多音效池（随机，优先于通用）
├── cards/
│   ├── sha.gd
│   └── audio/                         # ★ 卡牌音效（素材投放）
│       ├── sha_custom.ogg             #   崩铁杀牌名配音
│       └── sha_original.ogg           #   三国杀牌名配音
└── BGM/                               # ★ 背景音乐（素材投放）
    ├── menu.ogg   / menu_2.ogg …      #   主菜单（多曲随机）
    └── battle.ogg / battle_2.ogg …    #   战斗（多曲随机）
```

### 3.1 技能音效查找优先级（自上而下取首个命中）

| 顺位 | 文件名模式 | 语义 |
|---|---|---|
| 1 | `<技能id>_<角色id>_<序号>`（序号 1..8 构成池） | 角色专属多音效池 |
| 2 | `<技能id>_<角色id>` | 角色专属单音效 |
| 3 | `<技能id>_<序号>`（序号 1..8 构成池） | 通用多音效池 |
| 4 | `<技能id>` | 通用单音效 |
| 5 | 全部缺失 | 不播放 |

- 池化规则：同顺位内**只要存在任意序号文件，即在该池内随机**，不再向下回退。
- 角色 id 取**发动者**的 `character_id`（`announce_activation_for_player` 场景取实际发动者）。
- 正向拼接（已知技能 id + 角色 id），故角色 id 含下划线（如 `qiong_cunhu`）不产生歧义。

### 3.2 卡牌音效查找优先级

| 顺位 | 文件名模式 | 语义 |
|---|---|---|
| 1 | `<卡牌id>_<当前名称体系>` | 当前卡名模式对应体系（`custom` = 崩铁杀 / `original` = 三国杀） |
| 2 | `<卡牌id>_<另一名称体系>` | 需求钦定的名称体系回退 |
| 3 | 全部缺失 | 不播放 |

- 名称体系由表现层实时读取 `GameSettings.card_name_mode`（Autoload，非受禁对象），故局内切换卡名模式后音效立即跟随。

### 3.3 BGM 候选池

`menu` / `battle` 基名 + 可选 `_2` … `_9`；同场景多文件时随机选曲。

### 3.4 探测规则

- 扩展名优先级 `["ogg", "wav", "mp3"]`；池序号上限 `MAX_POOL_SIZE = 8`。
- 全部使用 `ResourceLoader.exists()` 探测，**不使用 `DirAccess` 目录扫描**（导出包中导入资源磁盘名变为 `.oggvorbisstr` 等，扫描不可靠）。
- 不做负缓存（便于运行中投放文件即时生效）；`AudioStream` 正缓存永久驻留。

---

## 四、核心层契约

### 4.1 新增信号

```gdscript
## 技能发动或卡牌使用/打出时的统一只读音频表现请求。
## 负载只含已公开数据（发动者、技能/牌定义、角色 id、两套牌名、动作模式），
## 音频表现层据此选择并播放语音，表现层不得回查任何控制器状态。
signal voice_presentation_requested(presentation_data: Dictionary)
```

负载字段（全部 JSON 可序列化）：

| 字段 | 技能 | 卡牌 | 含义 |
|---|---|---|---|
| `kind` | `"skill"` | `"card"` | 请求类别 |
| `player_id` | ✓ | ✓ | 发动者 / 使用者玩家 ID |
| `skill_id` | ✓ | — | 技能 id（= 技能源码文件名） |
| `card_definition_id` | — | ✓ | 实际结算的牌定义 ID（虚拟牌为虚拟定义） |
| `card_names` | — | ✓ | `{"custom": 崩铁杀牌名, "original": 三国杀牌名}` |
| `character_id` | ✓ | — | **发动者**的武将 id，用于角色专属音效 |
| `play_mode` | — | `use` / `respond` | 使用或打出 |
| `sequence` | ✓ | ✓ | 递增序号，供表现层去重与调试 |
| `event_token` | ✓ | ✓ | 事件令牌，见 4.3 |

### 4.2 公开端口（内容层与统一出口共用）

```gdscript
## 请求播放一次技能语音；技能源码可显式调用以自定义时机，统一出口亦由此发起。
func request_skill_voice(player_id: int, skill_id: String) -> void

## 请求播放一次卡牌语音；卡牌源码可显式调用，统一出口亦由此发起。
func request_card_voice(player_id: int, card_definition_id: String, play_mode: String) -> void
```

两个端口内部完成：空值/无效玩家防御 → 计算去重键 → 命中则丢弃 → 组装负载 → `emit`。

### 4.3 去重机制（R8.3 的落地）

- 去重键：`"<kind>|<player_id>|<定义id>|<event_token>|<play_mode>"`。
- `event_token`：卡牌取该次结算的 `event_id`（使用为 `CardUseEvent.event_id`，打出为 `respond_event_id`）；技能取 `state.current_event_id`。
- 表 `_voice_request_tokens: Dictionary` 仅保留最近 `VOICE_DEDUP_WINDOW` 条（默认 512，防长局内存增长），命中即丢弃请求。
- **技能「显式调用早于统一出口」的跨事件问题**：技能文件常在 `activate()` 开头调用（此时事件令牌与最终发动不同），故技能额外使用实例级标记 —— `SkillDefinition` 记录 `_explicit_voice_request_msec`，统一出口仅当「距显式请求不超过 `EXPLICIT_VOICE_SUPPRESS_WINDOW_SECONDS`（默认 3.0 秒）」时跳过自动请求并清除标记；超窗即视为已过期，不抑制后续自动触发（避免「调了没发动」导致永久静音）。
- **卡牌「统一出口早于牌源文件」**：使用牌的自动请求在声明时发生，牌源 `resolve()` 内的显式调用因去重键相同而被丢弃 —— 即卡牌默认已由自动触发覆盖，牌文件无需书写；若内容层要完全接管，声明元数据 `"voice_trigger": "manual"` 使统一出口跳过（R8.3）。

### 4.4 默认触发点（零改动覆盖既有内容）

| 位置 | 场景 | `play_mode` | 定义来源 |
|---|---|---|---|
| `record_skill_activation`（`match_controller.gd:8967`）函数开头 | 技能实际发动（含触发技、领袖技） | — | `skill_id` 参数 |
| `_execute_use_card_declare` 内，紧随 `_request_card_presentation(..., "useCard", ...)`（`match_controller.gd:11524`） | 使用牌 | `use` | `card.definition_id` |
| `_consume_response_card_uid_patterns` 响应日志之后（`match_controller.gd:5193`） | 响应打出实体牌 | `respond` | `logical_definition_id` |
| `_consume_skill_converted_response` / 装备响应出口 | 技能、装备转化为响应 | `respond` | 虚拟定义 ID |

> 每个默认触发点在调用端口前，先检查 `"voice_trigger" == "manual"` 与技能实例抑制窗口，二者任一命中则不请求。

### 4.5 联机广播

- `_bind_replication_handlers`（`match_controller.gd:614-625` 区块）追加：`voice_presentation_requested` → `_replicate_voice_presentation_event`。
- 新增 `_replicate_voice_presentation_event`：局域网房主且对局进行中时 `broadcast_game_event("voice_presentation", {"presentation": data})`。
- `_on_network_game_event_received`（`match_controller.gd:14342`）追加 `voice_presentation` 分支 → 本地 `emit`。
- 负载只含已公开信息，不泄露手牌、身份与随机种子。

---

## 五、内容层接口契约

### 5.1 技能（`game_data/skill_definition.gd` 新增，不改既有成员）

```gdscript
## 请求播放本技能本次发动的语音；技能源码可在效果代码中调用以自定义播放时机。
## 默认情况下统一出口已自动触发，重复调用不会重复发声。
func play_voice() -> void
```

- 实现：`host.has_method("request_skill_voice")` 防御 → `host.call("request_skill_voice", owner_player_id, get_id())` → 记录 `_explicit_voice_request_msec`。
- 用法示例（未来新技能）：在 `activate()` 或时机回调开头写一行 `play_voice()`。

### 5.2 卡牌（`game_data/card_definition.gd` 新增，不改既有成员）

```gdscript
## 请求播放本次使用/打出的卡牌语音；默认已由核心统一出口触发，通常无需调用。
func play_voice(actor_id: int = -1) -> void
```

- 实现：`runtime_host.has_method("request_card_voice")` 防御 → 使用者取 `actor_id` 或 `runtime_owner_player_id` → `host.call("request_card_voice", user_id, get_id(), "use")`。

---

## 六、音频服务接口契约（`AudioService`，Autoload）

| 接口 | 签名 | 行为 |
|---|---|---|
| 语音请求（内部） | `play_voice_presentation(presentation_data: Dictionary) -> void` | 按 `kind` 分派到技能/卡牌解析；全不命中静默返回 |
| BGM 请求 | `request_bgm(scene_id: String) -> void` | `menu` / `battle`；同场景幂等；跨场景淡入淡出 |
| BGM 状态 | `get_current_bgm_scene() -> String` / `get_bgm_playback_position() -> float` | 供测试与诊断 |
| 停止 BGM | `stop_bgm() -> void` | 淡出停止 |
| 音量设置 | `set_bgm_volume_linear(v)` / `set_sfx_volume_linear(v)` / `set_audio_muted(b)` | 转发给 `GameSettings`（唯一持久化入口），由设置信号回调驱动总线 |
| 诊断 | `get_debug_state() -> Dictionary` | 当前 BGM 场景、活动语音数、总线音量 |

**总线约定**

- 总线 `BGM`、`SFX`，均 `send = "Master"`；采用**运行时确保存在**策略（`get_bus_index == -1` 时 `add_bus` + 命名 + 设置 send），不新增 `default_bus_layout.tres`。
- 线性音量 → dB 用 `linear_to_db(clampf(v, 0, 1))`；`v <= 0` 时改走 `set_bus_mute(true)`（避免 `-inf` 触发无效值告警）。
- 语音播放器**按需分配**：空闲池优先复用，池不足时新建 `AudioStreamPlayer`（`bus = "SFX"`），播放结束经 `finished` 信号回收到空闲池；**不设并发上限与最小重播间隔**（需求钦定），保证多张牌同时结算时各路音效都能同时播出。

---

## 七、桥接组件契约（`GameAudioBridge`）

- 挂载：`scenes/main.tscn` 根节点 `Main` 的子节点 `AudioBridge`（与 `MatchController` 平级）。
- `@export`：`voice_signal_source_path: NodePath` → `../MatchController`；`main_menu_path: NodePath` → `../MainMenu`。
- 行为：
  1. 连接 `voice_presentation_requested` → `AudioService.play_voice_presentation(data)`。
  2. 连接 `MainMenu.visibility_changed`：`visible == true` → `request_bgm("menu")`；`false` → `request_bgm("battle")`。
  3. `_ready` 末尾按 `MainMenu.visible` 当前值同步一次 BGM。
  4. `_exit_tree` 断开全部连接。
- **不做**：不读控制器状态、不解析路径、不直接操作播放器。

> BGM 锚点理由：`MainMenu.visible` 覆盖全部开局路径（离线新开局、重开、过关斩将恢复、联机开局）与回菜单路径（`return_to_main_menu()`）；选将、战斗、结算面板显示期间 `MainMenu` 恒隐藏，天然满足「延续不中断」。

---

## 八、设置持久化契约（`GameSettings` 扩展）

| 字段 | 类型 | 默认 | 范围 | 常量 |
|---|---|---|---|---|
| `bgm_volume` | float | `0.8` | `0.0–1.0` | `DEFAULT_BGM_VOLUME` / `AUDIO_VOLUME_MIN|MAX|STEP` |
| `sfx_volume` | float | `0.9` | `0.0–1.0` | `DEFAULT_SFX_VOLUME` |
| `audio_muted` | bool | `false` | — | `DEFAULT_AUDIO_MUTED` |

- 新增信号：`bgm_volume_changed` / `sfx_volume_changed` / `audio_muted_changed`。
- Setter 沿用既有模式：`clampf` + `snappedf(step)` → 变化才写 → `_queue_settings_save()` → 发信号。
- 载入时新字段缺失回退脚本默认值；`SETTINGS_SCHEMA_VERSION` 不变（向后兼容）。

---

## 九、界面契约

- 位置：`MainMenu/MainMenuSettingsPanel/SettingsVBox`，插在既有 `MainMenuGameSpeedSlider` 之后的音频区块。
- 新增控件（带 `unique_name_in_owner`，供 `%` 引用）：`MainMenuBgmVolumeLabel` + `MainMenuBgmVolumeSlider`、`MainMenuSfxVolumeLabel` + `MainMenuSfxVolumeSlider`、`MainMenuAudioMutedCheckBox`。
- 颜色与样式一律经 `BattleUIStyle` 读取；新增文本控件必须纳入统一字体色覆盖。
- 初始化用 `set_value_no_signal` / `set_pressed_no_signal`，并订阅三个设置信号做外部变化回显。
- 局内菜单本次不新增控件。

---

## 十、关键权衡

| 抉择 | 采用 | 放弃 | 理由 |
|---|---|---|---|
| 触发点 | 统一出口默认触发 + 内容层可显式覆盖 | 逐个改 144 技能 + 92 卡牌 | 既有内容零改动生效、未来不漏写；仍保留内容层自定义时机能力 |
| 「打出」接入 | 核心响应消耗出口 | 牌源文件回调 | 【闪】等纯响应牌不回调牌源文件，只能在核心出口覆盖 |
| 音频目录 | `game_data/skills|cards/audio/`、`game_data/BGM/` | 统一 `res://audio/` | 需求钦定；已验证单层扫描与固定路径读取均不受影响 |
| 音色维度 | 角色 id 专属文件（技能） | 性别分目录 | 需求钦定；角色专属比性别更精确 |
| 目录发现 | 确定基名 + 序号 + 扩展名优先级探测 | `DirAccess` 扫描 | 导出包导入资源改名，扫描不可靠 |
| 去重 | 事件令牌表 + 技能实例抑制窗口 | 纯布尔标记 | 跨事件场景下布尔标记会残留并误抑制 |
| BGM 锚点 | `MainMenu.visibility_changed` | 在 `match_table.gd` 各分支插桩 | 覆盖全部路径、零侵入 5092 行协调器 |
| 音频总线 | 运行时 `AudioServer` 确保存在 | 新增 `default_bus_layout.tres` | 免手写资源格式风险 |

---

## 十一、风险与回滚

| 风险 | 等级 | 缓解 | 回滚点 |
|---|---|---|---|
| `main.tscn`（4.7 格式含 `unique_id`）手改损坏 | 中 | 场景改动全部经编辑器 MCP 工具；改后逐行复核 `git diff` | `git checkout -- scenes/main.tscn` |
| `match_controller.gd`（15387 行）核心改动 | 中 | 只新增信号/端口/私有方法，不改既有流程与信号；独立阶段提交 | `git checkout -- scripts/core/match_controller.gd` |
| 内容层基类改动影响全部内容 | 中 | 仅新增方法，不修改既有成员与签名 | `git checkout -- game_data/skill_definition.gd game_data/card_definition.gd` |
| 新增文本控件导致字体色审计失败 | 中 | 纳入主题覆盖；跑 `font_color_audit_test` + `ui_layout_test` | 移除新增控件 |
| `game_data/*/audio/`、`game_data/BGM/` 被内容扫描误读 | 低 | 已验证 `_list_gd_scripts` 单层且只收 `.gd`；`_load_decks`/`_load_factions` 读固定路径 | 删除目录 |
| 多张牌同响应导致语音叠放 | 低 | 需求钦定不作限流；去重键仍保证同一请求不重复发声。若后续体验需要，可在 `AudioVoicePlayer` 追加可选的限流参数 | 调 `@export` |
| `linear_to_db(0)` 无效值告警 | 低 | 零音量走 `set_bus_mute` | 单文件回滚 |

---

## 十二、测试设计

新增 `tests/audio_system_test.gd` + `tests/audio_system_test.tscn`（项目约定：`extends Node`、`_ready` 内断言、成功打印 `AUDIO_SYSTEM_PASS ...`）：

| 用例 | 断言 |
|---|---|
| 技能优先级顺序 | 候选链顺序严格为「专属池 → 专属单音 → 通用池 → 通用单音」，纯逻辑无文件依赖 |
| 池化短路 | 专属池存在任一序号文件时，不再回退通用池 |
| 角色 id 含下划线 | `qiong_cunhu` 拼接结果正确、不与序号解析冲突 |
| 卡牌体系回退 | 当前体系缺失时回退另一体系；两套皆缺返回空 |
| 卡牌虚拟定义 | 虚拟牌定义（如 `sha_thunder`）生成独立候选路径 |
| BGM 候选池 | `menu` / `menu_2`…`menu_9` 生成与上限约束 |
| 缺失静默 | 全不存在时返回空且不产生错误 |
| 去重 | 同一去重键的重复请求只保留一次；不同事件令牌不互相抑制 |
| 播放器按需分配 | 连续请求多条语音时全部播放（无并发上限），播放器被回收进空闲池复用 |
| 设置持久化 | 三个新字段写入独立临时 cfg 并重新实例化读回，数值一致且被 clamp |
| BGM 幂等 | 连续两次 `request_bgm("battle")` 不重头播放（`get_bgm_playback_position()` 单调递增） |

另需回归：`gameplay_regression_test`（用牌链路）、`smoke_test`（可开局）、`game_settings_persistence_test`、`main_menu_test`、`ui_layout_test`、`font_color_audit_test`。
