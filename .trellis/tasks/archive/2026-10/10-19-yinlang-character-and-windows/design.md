# 银狼武将、注入/以太技能与 yinlang_windows 窗口 · 技术设计

## 0. 调研结论（已核实）

| 关注点 | 结论 |
|---|---|
| 运行时技能定义注册表 | **不存在**。`GameDatabase.create_skill(id)` 只认 `res://game_data/skills/*.gd` 扫描结果 |
| 运行时技能名称覆盖 | **不存在**。名称永远来自 `GameDatabase.get_skill(技能ID).get("name", 技能ID)`（`character_skill_display.gd:82/109`、`skill_button_view.gd:94`、`match_table.gd:2191/2226`） |
| 运行时技能描述覆盖 | **存在**。`PlayerState.dynamic_skill_descriptions` + `set_skill_display_description`，支持 `[s]…[/s]` |
| 时机目录 | `RuleTimingCatalog` 237 项，全部可 `subscribe_timing(时机, 回调, role)` |
| 准备阶段 | `phaseZhunbeiBegin`（`role="player"`），先例 `bahu.gd:20` |
| 游戏开始时 | `gameStart`，三个 ID 均为 -1，**必须** `role="global"`，先例 `chouma.gd:40` |
| 主演 | `StarringRoleService` 完整（至多一名、死亡清理、快照/存档安全），端口 `set_starring_role` / `is_starring_role` |
| 限定技 | 正文含「限定技」即自动 `limited`；`has_available_intrinsic_use()` / `consume_intrinsic_use()`（`announce_activation` 内自动消耗） |
| 选择协议 | `choice_type` + `control_options` + `control_id`；**没有自由文本通道** |
| 请求结构自检 | 创建请求时会调用 `_build_card_choice_actions()` 自检「是否存在任何可提交动作」，空枚举且不可取消 → 直接拒绝（`match_controller.gd:3199`） |
| 响应校验 | `ChoiceRequest.validate_response()` 用 `control_ids.has(control_id)` 白名单拒绝未登记值（`choice_request.gd:215`），且**人类、AI、网络三条路径都会经过它**（`event_scheduler.gd:550/583`） |
| AI 候选枚举 | `_build_card_choice_actions()`（`match_controller.gd:3571`）按 `choice_type` 枚举；`control` 分支在 `:3635-3644` |
| 层级表 | `docs/界面与交互.md:206` 为规范；`185` 未被占用 |
| 黑蓝配色 | 三个调色板均为金/铜强调色，**没有蓝色语义键**；需在 `ui_style_registry.gd` 三个调色板新增语义键 |
| 字体 | 无字体资源，中文走 `ThemeDB.fallback_font`；`LineEdit` 必须显式设字体 |

**关键推论**：把「进程」「缺陷」实现为**静态技能脚本** + **实例级配置**，可以完全绕开「运行时技能定义注册表」与「运行时名称覆盖」这两个不存在的能力——名称来自静态定义（进程 / 缺陷），正文来自实例级描述覆盖，行为来自静态脚本按配置分派。这是本设计最重要的取舍。

## 1. 组合技能：静态脚本 + 实例级配置

### 1.1 数据流

```
注入（zhuru）在 gameStart / phaseZhunbeiBegin 触发
   → 打开 yinlang_windows 注入窗口（choice_type = yinlang_compose）
   → 玩家提交 control_id = "yinlang|compose|<时机键>|<效果键>"
   → zhuru.continue_selection() 解析
   → 计算目标角色、组合类别（主演 → jincheng，否则 → quexian）
   → 生成正文 = "锁定技，" + 时机文本 + "，" + 效果文本 + "。每回合限一次。"
   → host.call("grant_acquired_skill", 目标, 类别ID, 1, 0, "zhuru", false, 0, true)
       返回 true 后，用 host.call("get_installed_skill_keys", 目标) 找到本次新实例键
   → host.call("set_runtime_skill_data", 目标, 实例键, {"skill_id":类别ID, "timing_key":…, "effect_key":…})
   → host.call("set_skill_display_description", 目标, 实例键, 正文)
   → host.call("change_skills_after" 相关时机由授予端口自行派发)
```

实例键的取得方式需要确定：`grant_acquired_skill` 当前返回 `bool`。为避免「授予后再猜哪个是新键」，在本任务中为授予端口补一个**可选的出参通道**：
`grant_acquired_skill(..., allow_duplicate := false, out_instance_key: Array = [])` —— 调用方传入一个单元素数组，端口把新实例键写进去。GDScript 不支持引用参数，用单元素数组是项目里可行的最小侵入做法；若不接受该形态，则退化为「授予前后对比 `get_installed_skill_keys` 的差集」。**设计采用后者（差集）作为主方案**，因为它不需要改动多实例底座的端口签名；差集在并发授予下也不会有歧义（授予是同步的）。

### 1.2 静态脚本职责

`game_data/skills/jincheng.gd`（进程）/ `quexian.gd`（缺陷）共用同一套实现骨架，只有「效果池」不同：

- `_init()`：`{"id":"jincheng","name":"进程","lock":true,"ui_enabled":false,"description":"锁定技，每回合限一次。<由实例配置覆盖>"}`
  - 注意：静态描述只是**兜底**；每个实例在授予时都会写入真实正文，因此界面永远显示组合后的正文。
  - `ui_enabled`：组合技能是触发式技能，无主动发动按钮 → `false`。
- `install()`：
  1. 读取 `host.call("get_runtime_skill_data", owner_player_id, get_instance_key())`；
  2. 取 `timing_key` → 经 `ComposedSkillPools` 映射为 `{timing: String, role: String, condition_kind: String}`；
  3. `subscribe_timing(时机, _on_composed_timing, role, priority, first_do, last_do, condition)`；
  4. 映射缺失或非法 → `push_error` + `add_log`，**不订阅**，绝不崩溃。
- `_on_composed_timing(event)`：
  1. `if not has_available_intrinsic_use(): return`（防御；每回合额度由 `per_turn_limit = 1` 的 acquired 记录承担）
  2. 条件细化（属性伤害、回合外失去牌、使用【杀】等需要读 `event.data` 的判定）
  3. `announce_activation({"timing_key":…, "effect_key":…})` → 自动消耗本实例本回合额度
  4. 若该效果需要选择（选牌/选目标）→ `request_*` 并把 `{"kind":"composed_effect", "effect_key":…, "instance_key":get_instance_key()}` 放进 context，在 `continue_selection` 里续算；若不需要选择 → 直接执行
  5. 「并失去本技能」类效果在执行后 `host.call("remove_acquired_skill", owner_player_id, get_instance_key())`
- AI 段：`score_ai_choice`（组合窗口与效果内选择）、`score_ai_action`（无主动发动，返回 0）。

### 1.3 池数据集中管理

`game_data/composed_skill_pools.gd`（`class_name ComposedSkillPools extends RefCounted`）——纯静态数据 + 查询函数，是池文本与时机映射的**唯一来源**：

```
const TIMING_ENTRIES: Array[Dictionary] = [
  {"key":"damage_after", "text":"当你受到伤害后", "timing":"damageAfter", "role":"target"},
  ...
]
const JINCHENG_EFFECTS: Array[Dictionary] = [{"key":"draw_one", "text":"你摸一张牌"}, ...]
const QUEXIAN_EFFECTS:  Array[Dictionary] = [{"key":"discard_hand", "text":"你弃置一张手牌"}, ...]
static func get_timing_entry(key) -> Dictionary
static func get_effect_entry(kind, key) -> Dictionary
static func compose_description(timing_text, effect_text) -> String
static func get_default_candidates(seed_key) -> Array  # 每栏 2 项的默认候选
```

- `text` 字段**逐字**等于需求原文，顺序与原文一致。
- 依赖方向：`game_data` 已经引用 `RuleTimingCatalog`（`skill_definition.gd:623`），因此本文件引用核心常量不新增越层依赖。
- 界面通过请求 `context` 收到池数据（由技能从本文件取出后放进 context），界面**不**直接引用本文件——保持界面只吃普通字典的既有约定。

### 1.4 时机映射表

见 `implement.md` 的「时机映射验收表」；每条必须在实现时以真实订阅验证。

### 1.5 效果实现映射表

42 项效果的逐条端口映射与验收断言见 `implement.md` 的「A4 进程效果验收表」「A5 缺陷效果验收表」，完整证据（含 `file:line`）见 `research/05-composed-skill-effect-ports.md`。

**调研结论摘要**：EXISTS 30 项 / 需技能自管回合标记 7 项 / 必须先补核心端口 3 项。

**必须先补的 4 个核心端口**（设计已确定签名，详见 `implement.md` A3.5）：

| 端口 | 补哪一项 | 为什么现有机制不够 |
|---|---|---|
| **N1** `modify_attack_range` 钩子 + `modify_skill_attack_range` 聚合器 | A15 攻击范围+2 | `CardRuleService.get_attack_range()`（`card_rule_service.gd:60-71`）只读武器卡静态 `attack_range`，既无状态字段也无钩子 |
| **N2** `execute_pile_card_use` + `use_random_equipment_card_from_draw_pile` | A8 随机使用牌堆装备 | 唯一的同类实现 `_equip_conquest_enemy_from_piles`（`:15631`）是**私有**且经 `equip_from_processing` 绕过 `useCard*` 时机/次数/距离校验；两个虚拟牌入口只吃「虚拟牌定义」，不能使用牌堆里的实体牌 |
| **N3** `set_response_blocked_until_turn_end` / `is_response_blocked_until_turn_end` + `PlayerState.response_blocked_until_turn` | B9 不可响应直到回合结束 | `direct_hit_target_ids` 是单张牌结算内的共享上下文，牌结算完即随 `_card_use_contexts.erase()`（`:14557`）消失，无法表达持续状态；`validate_card_action_permission` 旁路不覆盖装备响应入口（`:5364-5385`） |
| **N4** `add_turn_hand_limit_bonus` + `PlayerState.turn_hand_limit_bonus` | A13/B6 手牌上限 ±N 直到回合结束 | `add_hand_limit_bonus` 是**永久**累加，控制器不在回合末清零；技能若在回合中被压制/换将，负向残留会永久压低手牌上限 |

**不需要新端口（技能自管回合标记即可）**：A14（`get_play_count_limit_bonus`）、A16/B10（`modify_distance_to_target`）都是**实时纯查询**而非累加状态，`phaseAfter` 复位标记即可，核心层零改动；B13（`recoverBegin` + `event.data["amount"]`）机制齐备但项目内无内容先例，属首次使用需重点验证。

**随机相关硬约束**：B2–B5 与 A8 的随机选择一律走 `pick_random_candidate_index(candidate_count, history_kind, history_data)`（`match_controller.gd:7301`），**禁止直接 `randi()`**，否则回放与联机不同步。

### 1.6 已知语义陷阱

| 陷阱 | 事实 |
|---|---|
| 横置 ≠ 翻面 | `set_player_linked`（`:4990`）改 `PlayerState.chained`；`turn_over_player`（`:5021`）改 `face_down` |
| `shield_after` 不可订阅 | 它经 `_dispatch_rule_event` 派发到 `event_bus`，但未登记进 `RuleTimingCatalog` → `subscribe_timing("shield_after", …)` 静默返回 `-1` |
| `washCard` 不可订阅 | 只由 `_record_runtime_event` 记录（`match_controller.gd:16654`），从不 `_emit_rule_timing` |
| `add_card_target_damage_bonus` 不是「下次受伤」 | 它是逐目标牌内增伤（`:8882`）；技能不得自行改写同一字段否则重复累加 |
| 「并失去本技能」的粒度 | 用 `remove_skill(owner, 实例键)` 只移除该实例；多实例底座已支持 |

## 2. `yinlang_windows` 窗口

### 2.1 文件与结构

```
scripts/ui/yinlang_windows_layer.gd            # class_name YinlangWindowsLayer extends Control
scenes/components/yinlang_windows_layer.tscn   # 全屏 Control + Shade + Frame
```

- 根：`Control` 全屏锚点；子 `Shade`（`ColorRect`，`MOUSE_FILTER_STOP`）与 `Frame`（`PanelContainer`，居中）。
- `_ready()`：`process_mode = PROCESS_MODE_ALWAYS`、`z_index = MODAL_Z_INDEX`、`visible = false`、`_shade.mouse_filter = MOUSE_FILTER_STOP`、`refresh_ui_style()`。
- `const MODAL_Z_INDEX: int = 185`。
- 公开 API：`open_compose(request_id, request_data)` / `open_mint(request_id, request_data)` / `close()` / `refresh_ui_style()`。
- 信号：`composition_submitted(request_id, control_id)` / `card_minted(request_id, control_id)` / `cancelled(request_id)`。
- 内部把两个窗口拆成两个子组件（`yinlang_compose_view.gd` / `yinlang_mint_view.gd`），宿主只负责遮罩、层级、主题与信号转发（单一职责）。

### 2.2 注入窗口布局

```
Frame
 └ Margin
    └ Content (VBox)
       ├ TitleLabel       「注入 · 组合技能」
       ├ PreviewLabel     「锁定技，<时机>，<效果>。每回合限一次。」（实时预览，未选全时显示占位）
       ├ Columns (HBoxContainer)
       │   ├ LeftColumn (VBox)   时机
       │   │   ├ ColumnTitleLabel 「时机」
       │   │   ├ OptionList (VBox of Button)  默认 2 项
       │   │   └ ExpandButton 「展开全部（23）」
       │   └ RightColumn (VBox)  效果
       │       ├ ColumnTitleLabel 「效果」
       │       ├ OptionList (VBox of Button)  默认 2 项
       │       └ ExpandButton 「展开全部（24 / 18）」
       ├ HintLabel        牌名/选择校验提示
       └ ActionRow (HBox)
           ├ ConfirmButton 「确定」
           └ CancelButton  「取消」
```

- 默认候选来源：由技能用**权威随机源**从池中抽 2 项（进程 / 缺陷分别抽），并把抽取结果放进 `context`，保证联机与回放一致、可复现。
- 「展开全部」在窗口内切换为完整池列表（`ScrollContainer`）。
- 两栏各选中一项后 `ConfirmButton.disabled = false`。
- 提交 `control_id = "yinlang|compose|<时机键>|<效果键>"`。

### 2.3 以太窗口布局

```
Frame
 └ Margin
    └ Content (VBox)
       ├ TitleLabel    「以太 · 创造卡牌」
       ├ NameRow       Label「牌名」 + LineEdit（占位提示「请输入不与已有牌名重复的牌名」）
       ├ SuitRow       Label「花色」 + 4 个 Button（黑桃/红桃/梅花/方块，互斥高亮）
       ├ RankRow       Label「点数」 + 13 个 Button（A,2..10,J,Q,K，互斥高亮）
       ├ EffectRow     Label「效果与类别」
       │   └ ScrollContainer > VBox
       │        ├ 「基本牌」分组标题 + 该类别全部牌名按钮
       │        ├ 「锦囊牌」分组标题 + …
       │        └ 「装备牌」分组标题 + …
       ├ PreviewLabel  「将创造：<牌名> <花色><点数> · <类别> · 效果同<被复制牌名>」
       ├ HintLabel     牌名校验提示（冲突/为空/超长）
       └ ActionRow
           ├ ConfirmButton 「确定」
           └ CancelButton  「取消」
```

- 分组顺序取自 `all_cards_panel.gd:31-34` 的 `CARD_TYPE_NAMES`（基本牌 → 锦囊牌 → 装备牌），牌名经 `GameSettings.resolve_card_name()` 解析。
- 牌名输入每次变更都调用**本地**唯一性预校验（基于请求 `context` 中携带的 `existing_card_names`，避免界面直接读 `GameDatabase`），冲突时 `HintLabel` 显示提示并禁用「确定」。
- 提交 `control_id = "yinlang|mint|<牌名>|<花色>|<点数>|<被复制牌定义ID>"`。

### 2.4 视觉（高科技黑蓝）

在 `scripts/ui/ui_style_registry.gd` 的三个调色板中各新增语义键：

| 键 | space_mono | decade_wood | premium_black_gold | 用途 |
|---|---|---|---|---|
| `tech_panel` | 深蓝黑 | 深蓝黑 | 深蓝黑 | 窗口主体底色 |
| `tech_border` | 亮蓝 | 亮蓝 | 亮蓝 | 描边 |
| `tech_accent` | 青蓝 | 青蓝 | 青蓝 | 高亮、选中态、光标 |
| `tech_grid` | 暗蓝 | 暗蓝 | 暗蓝 | 分隔线/网格纹理 |

组件内一律 `BattleUIStyle.get_color("tech_*")` 读取；按钮用 `BattleUIStyle.apply_interaction_button`；面板用 `BattleUIStyle.make_inset_panel` + 阴影。**不得**新增主题专属颜色常量。

## 3. 协议改动

| 改动 | 位置 | 说明 |
|---|---|---|
| 新增常量 `YINLANG_COMPOSE_CHOICE_TYPE = "yinlang_compose"` / `YINLANG_MINT_CHOICE_TYPE = "yinlang_mint"` | `match_controller.gd` 常量区（`CARD_POSITION_CHOICE_TYPE` 旁） | 供 UI 与规则共用 |
| 请求级开关 `allow_free_control_id: bool = false` | `scripts/data/choice_request.gd`（字段 + `to_dict`/`from_dict`） | 显式声明「本请求的 `control_id` 不做白名单比对」 |
| `validate_response()` 分支 | `choice_request.gd:215` | 开关为真时跳过 `control_ids.has()`，但已确认时必须 `control_id` 非空 |
| 权威结构校验分支 | `match_controller.gd:3917` 与 `:3937`/`:3944` 附近 | 两个新类型加入「允许自由 control_id」集合；新增按 `|` 切分的结构校验（池成员、类别归属、牌名唯一性与格式、花色点数、被复制牌定义存在） |
| AI 候选枚举分支 | `match_controller.gd:3571` 起（`_build_card_choice_actions`） | 自由控制项类型按 `context["ai_candidate_control_ids"]` 生成确认动作（去重、限长 8） |
| UI 分流 | `match_table.gd:4397`（`_is_inline_control_choice`）与 `:4224`（`_refresh_card_selection_panel`） | 带 `context["yinlang_window"]` 的请求不走内联、也不走 `CardSelectionPanel`，转交 `yinlang_windows_layer` |
| 界面实例化 | `match_table.gd` 顶部 preload + `var` + `_create_yinlang_windows_layer()` + `_ready()` 调用 | 与 `OpportunityChoicePanel` 完全同构 |
| 主题重入 | `match_table._on_ui_style_changed` | 追加 `yinlang_windows_layer.refresh_ui_style()` |

**为什么不新增 `ChoiceResponse` 字段**：`ChoiceResponse` 是 UI / AI / 网络 / 回放共用的结构（`choice_response.gd:4`），新增字段的波及面最大；而 `control_id` 通道已被 `arrange`（`"top_count_%d"`）与 `card_position` 证明足以承载结构化字符串。

## 4. 技能实现要点

### 4.1 `zhuru.gd`（注入）

| 时机 | role | 行为 |
|---|---|---|
| `gameStart` | `global` | 打开注入窗口（类别固定为 `jincheng`，目标固定为自己）；取消 → 无效果 |
| `phaseZhunbeiBegin` | `player` | 先 `request_target_selection`（可选，含自己）→ 判定 `is_starring_role(目标)` → 类别 `jincheng` / `quexian` → 打开注入窗口 |

- 两段选择（选目标 → 组合）通过 `request_*` 的链式调用与 `continue_selection` 的 `context["kind"]` 区分阶段。
- 嵌套屏障：在时机回调中创建选择必须先检查 `host.has_nested_settlement_barrier()`，必要时 `defer_settlement()` / `continue_settlement()`（项目既有约定）。
- `ui_enabled = false`（触发式，无主动按钮）。

### 4.2 `yitai.gd`（以太）

| 时机 | role | 行为 |
|---|---|---|
| `phaseUse` | `player` | 出牌阶段主动技（`ui_enabled = true`，`limited` 由正文自动标记）→ 打开造牌窗口 → `mint_card_for_player` |
| `phaseAfter` | `global` | 任意角色回合结束：若 `get_discard_pile_card_uids_by_skill("yitai")` 非空 → `set_starring_role(owner)` + 逐张 `shuffle_discard_card_into_draw_pile(uid)` |

- 注意 `phaseAfter` 在「翻面跳过回合」路径不派发（`_complete_face_down_skipped_turn` 不走 `_complete_finish_turn`）。原文写「一名角色的回合结束时」，跳过回合本身不构成正常回合结束，因此**不额外补偿**，并在文档中记录该口径。
- 造牌窗口的四项选择在**一次请求**内完成，避免四次往返带来的状态不一致。

## 5. 风险

| 风险 | 缓解 |
|---|---|
| `allow_free_control_id` 削弱了通用白名单保护 | 开关为请求级显式字段；权威侧仍做完整结构校验；已确认时必须非空；`tests/event_runtime_test.gd` 增加「开关为假时仍拒绝未登记 control_id」的回归断言 |
| 效果池 42 项实现量大且易漏 | `implement.md` 提供逐项验收表；每项都要求真实结算断言，禁止只写提示分支 |
| 自由文本牌名破坏既有按牌名的功能 | 由 `10-19-runtime-card-creation` 的调研清单驱动，逐个更新名称解析路径 |
| 组合技能与既有机制冲突（非锁定技失效、代次校验、死亡清理） | 组合技能为锁定技，`can_use_effect` 天然通过；代次校验与死亡清理走基类 `_can_receive_timing_event`，无需特殊处理；换将时按技能 ID 清理全部实例（多实例底座已覆盖） |
| 层级 185 与后续新窗口冲突 | 已写入 `docs/界面与交互.md` 层级表并由 `ui_layout_test` 断言 |
