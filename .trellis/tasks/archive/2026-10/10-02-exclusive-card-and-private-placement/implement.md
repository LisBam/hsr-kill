# 执行计划：专属锦囊牌与不可知置牌机制

- 需求：[`prd.md`](./prd.md)
- 设计：[`design.md`](./design.md)
- 父任务：[`../10-02-kafuka-new-mechanics/prd.md`](../10-02-kafuka-new-mechanics/prd.md)

> 本计划只覆盖两个机制底座。不新增任何卡牌、技能或武将。

---

## 一、开工前状态

| 项 | 状态 |
|---|---|
| `prd.md` | 已存在（In/Out Scope、R1–R9、AC1–AC17、K1–K7、RK1–RK6） |
| `design.md` | 已存在（命名契约 §2.1–2.6、数据流 §4.1–4.3、兼容性 §5、已否决方案 §6、验证策略 §7） |
| `implement.md` | 本文件 |
| `implement.jsonl` / `check.jsonl` | 本平台为 inline 模式，开工前用 `trellis-before-dev` 加载规范；两个清单仍按内容策展 |
| 调研 | 本轮已完成两个专项只读调研（卡牌注册与牌堆构建；隐藏信息与位次），结论已固化进 `design.md` |

---

## 二、改前缺口与落点复核（本轮已确认，附行号）

| # | 复核项 | 结论 | 证据 |
|---|---|---|---|
| G1 | 「卡牌定义存在但不被任何牌堆引用」会不会报错 | **不会**。`GameDatabase._validate_decks()` 只做「牌堆 → 卡牌」单向校验，无反向覆盖检查 | `game_database.gd:563-579`；生产先例 `shuiyanqijun`（46 张牌 vs 牌堆 45 个 ID，差集即它） |
| G2 | 卡牌元数据加字段是否需要改基类 | **不需要**。`_metadata` 是自由 `Dictionary`，缺省读不到即退化为默认值 | `card_definition.gd:33-34`；语义化读取先例 `requires_actor_choice()` `:181-182` |
| G3 | 图鉴是否会自动收录未入牌堆的牌 | **会**。遍历 `GameDatabase.cards.keys()` 全量，无类型/牌堆过滤；未入牌堆时只缺花色点数 | `all_cards_panel.gd:381-403`、代表牌面缓存 `:807-828`、`:393` 注释 |
| G4 | 是否有「按定义造实体牌入堆」的现成端口 | **没有**。全仓 `draw_pile` 写入点仅 5 处，且都不是内容层可用端口 | `match_controller.gd:11185-11188`（开局建堆）、`:8668/8671`（重排）、`:15019`（存档恢复）、`:15490`（洗回） |
| G5 | `move_card` 能否用于一张新造的牌 | **不能**。要求牌已在某个区域内，否则返回 null | `card_movement_service.gd:31-34` |
| G6 | 手牌 → 牌堆指定第 2 位能否复用既有实现 | **不能**。`_add_to_zone` 对 `draw_pile` 固定 `append`（=第1张），`target_slot` 被忽略；`arrange_draw_pile_cards` 硬要求牌已在牌堆且 `top_count` 只能切顶/底行 | `card_movement_service.gd:201-203`；`match_controller.gd:8650-8662`、`:8666-8671` |
| G7 | 牌堆方向约定 | **数组末尾为顶** | `game_state.gd:33-34`；摸牌取 `back()` `draw_resolution_service.gd:110` |
| G8 | `add_log()` 是否有私密通道 | **没有**。无 `viewer_id`，一 emit 即进局域网广播、界面与回放 | `match_controller.gd:4055-4057`；广播 `:16116-16119`；回放入档 `match_table.gd:4122-4125` |
| G9 | 「完全不写日志」的既有先例 | 有。牌堆重排与私有观看全程不写日志 | `arrange_draw_pile_cards()` `:8647-8674`（只写 `random_history` + `_emit_state`）、`get_top_draw_card_candidates()` `:8609-8622`；技能侧 `xifa.gd:73-85` |
| G10 | 牌堆牌面是否会进快照 | **不会**，任何快照只发 `draw_pile_count`；`reveal_private=true` 也读不到牌堆牌面 | `game_state.gd:240-272`（`:249` 仅 count） |
| G11 | `character_form_state` 的可见性 | **仅 `reveal_private`**：持有者自己的普通快照拿不到，AI 快照反而全量拿到 | `player_state.gd:526`；AI 用 `to_dict(id, true)`：`match_controller.gd:3046,3230,5867,15579` |
| G12 | 「本人可见 + 可存档」的正确先例 | `wheel_duel_lineup` 的序列化条件是 `reveal_private or viewer_id == player_id`，但 `from_authoritative_dict` 里**没有**该字段的恢复行（它不进存档），所以新字段必须自己补恢复行 | `player_state.gd:594`；`from_authoritative_dict` `:301-384` |
| G13 | 手牌 → 牌堆是否会产生公开表现 | **不会**。`_on_card_moved` 在目标区域不是 `hand`/`discard_pile` 时直接 return | `match_controller.gd:15404-15418`（`:15410`） |
| G14 | 组合选择（牌 + 文字按钮）是否被支持 | **不支持**。`choice_type="card"` 携带 `control_id` 被直接拒绝；界面只在 `control`/`bool` 时渲染按钮 | `match_controller.gd:3653-3662`；`card_selection_panel.gd:273-290`、`_add_control_options` `:695-717` |
| G15 | 唯一正式的组合先例 | `arrange`（牌 + `top_count_*` 文字选项）：构造 `skill_definition.gd:876-888`、校验 `match_controller.gd:3681-3695`、界面 `card_selection_panel.gd:263-266`、AI `match_controller.gd:3365-3378` | 同上 |
| G16 | AI 无合法动作时的后果 | 请求会被直接拒绝，表现为窗口挂住 | `match_controller.gd:2961-2968` |
| G17 | 秘密移动的残余泄露面 | ①`_move_card_with_timings` 会把「手牌离区 + reason」派发给所有技能；②`card_move_history` 记录含 reason；③`_update_knowledge` 对 `draw_pile` 不清理 `known_to` | `match_controller.gd:15291-15385`（`:15331-15384`、`:15326`）；`card_movement_service.gd:47-65`、`:223-235`；对照 `_refresh_starting_hand` `:10849` 刻意绕过时机系统 |
| G18 | `skill_history` 是否为公开字段 | **是**。`announce_activation` 会把 context 写进它并写公开日志 | `player_state.gd:587`；`match_controller.gd:10024-10055`（`:10039`、`:10053/10055`） |
| G19 | Godot 可执行文件 | `E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe` | 与 `project.godot` 声明的 4.7 一致 |

---

## 三、执行清单（按依赖顺序，逐项可独立验证）

### 阶段 A：专属牌字段与校验口径（R1 / R2）

- [x] A1 `game_data/card_definition.gd` 新增纯查询 `is_exclusive() -> bool`，读 `_metadata.get("exclusive", false)`，附完整注释。**不改任何既有字段与读取点。**
- [x] A2 复核 `GameDatabase._validate_decks()` 与 `_validate_characters()`：确认无需放宽；**不新增反向校验**（避免把 `shuiyanqijun` 与后续专属牌判成错误）。
- [x] A3 新增一条**测试内**校验：遍历 `GameDatabase.cards` 中所有 `is_exclusive()` 为真的卡牌，断言其不出现在任何牌堆的 `cards` 数组里（AC4）。落在专项测试中，不进核心。
- [x] A4 补规范例外：`.trellis/spec/content/index.md` 的「新增卡牌后确认已加入 `data/decks.json`」补一条「专属牌（`exclusive: true`）例外」，并在 `docs/内容制作指南.md` 同步。

### 阶段 B：控制器端口 —— 按定义造牌入堆（R3）

- [x] B1 `MatchController` 顶部常量区新增 `DRAW_PILE_POSITION_TOP = 1` / `DRAW_PILE_POSITION_SECOND = 2`，附注释说明方向约定与「数组末尾为顶」。
- [x] B2 新增 `create_and_insert_card_into_draw_pile(definition_id, suit = "", rank = 0, position = TOP) -> int`：
  - 前置校验：`state` 存在且未终局、`GameDatabase.get_card_definition(definition_id)` 非空、`position ∈ {1,2}` → 任一失败返回 `-1` 且零副作用；
  - `suit`/`rank` 缺省时用 `_rng` 取权威随机值，并把 `{kind, definition_id, suit, rank, position}` 追加进 `state.random_history`（照 `arrange_draw_pile_cards` `:8672` 的写法）；
  - 造牌 `CardInstance.new(definition_id, suit, rank)`，`zone = "draw_pile"`、`owner_id = -1`；
  - 落位：`position == TOP` → `append`；`position == SECOND` → `insert(size - 1, card)`；
  - 记一条移牌历史并发出 `card_moved`（与 `CardMovementService` 的增量语义一致，见下方 RG2 说明）；
  - `_emit_state()`；返回新 UID。
- [x] B3 在 `CardMovementService` 新增内部能力「把一张**尚不在任何区域**的牌按位次放入 `draw_pile`」，供 B2 调用，避免在控制器里复制移牌/知识/信号逻辑。**既有 `move_card` 与 `_add_to_zone` 的现有行为不得改变**（`position == TOP` 仍走原 `append` 路径）。
  - 实现落点：`CardMovementService.insert_new_card_into_draw_pile(card, position, reason, event_id)`；`_add_to_zone` 新增 `@N` 位次解析（`_parse_draw_pile_position`），`position <= 1` 仍走原 `append`。

### 阶段 C：私有事实承载（R4）

- [x] C1 `PlayerState` 新增 `private_pile_placement: Dictionary = {}`，附完整注释（作用、键、可见性、默认值原因、修改影响）。
- [x] C2 `to_dict()`：**仅在非空时**写入该键，值 `duplicate(true)`。理由：非空才写可保证「新增字段前该键不存在」的快照形状对他人逐字节不变。
  - **实现期修正（两次收紧）**：条件由 `reveal_private or viewer_id == player_id` 最终定为 **`reveal_private and viewer_id == player_id`**。
    ①不能只用 `reveal_private`：全部 AI 快照都是 `state.to_dict(该AI的player_id, true)`，会让每个 AI 都读到其他角色的置牌事实，违背「其他角色不可知」。
    ②不能只用 `viewer_id == player_id`：本地广播快照是 `state.to_dict(local_human_player_id, false)`，该快照会被整体录制进回放，会把置牌事实写进回放文件，违背「不出现在对局记录中」。
    两个条件同时成立后，存档固定用 `player.to_dict(player.player_id, true)` 仍可往返，权威端读取事实统一走 `get_private_pile_placement()`。已同步 `design.md` §2.4。
- [x] C3 `from_authoritative_dict()`：补一行恢复，缺键按 `{}`。
- [x] C4 控制器新增端口 `set_private_pile_placement(player_id, card_uid, position, turn_player_id, turn_number) -> bool` / `get_private_pile_placement(player_id) -> Dictionary` / `clear_private_pile_placement(player_id) -> bool`，为**唯一写点**；成功写后 `_emit_state()`（只广播给本人）。
- [x] C5 确认该字段**不进入** `character_form_state`、`public_marks`、`recorded_card_names`、`skill_history` 与任何公开序列化路径。

### 阶段 D：置牌端口（R6）

- [x] D1 新增 `place_hand_card_on_draw_pile_top(player_id, card_uid, position) -> bool`：
  - 前置校验（任一失败返回 `false` 且零副作用）：`state` 存在且未终局、`position ∈ {1,2}`、该玩家存在、`card_uid` 确实是该玩家的**手牌**；
  - **直接调用 `card_movement.move_card(card, "draw_pile", -1, reason, ...)` 并指定插入位次**，**绕过 `_move_card_with_timings`**（避免把「手牌离区 + reason」派发给所有技能，见 G17）；理由与 `_refresh_starting_hand`（`:10849`）一致；
  - 移牌前显式重置该牌的 `known_to`、`hand_mark_tags` 与手牌视为展示残留（`_prepare_hidden_pile_gain` `:7461-7468` 的反方向工具）；
  - **不调用 `add_log()`**；**不调用** `announce_activation` / `record_skill_activation`；
  - `_emit_state()`；返回 `true`。
- [x] D2 位次落位复用 B1 常量与 D1 的插入实现，禁止两处各写一套。

### 阶段 E：位次询问选择类型（R7）

- [x] E1 `MatchController` 新增稳定选项 ID 常量：`PILE_SLOT_OPTION_TOP = "pile_slot_1"`、`PILE_SLOT_OPTION_SECOND = "pile_slot_2"`、`PILE_SLOT_OPTION_CANCEL = "cancel"`。
- [x] E2 新增 `request_hand_card_pile_position(player_id, title, prompt, allow_cancel = true, context = {}) -> Dictionary`：以 `choice_type_override = "card_position"`、`candidates = 本人手牌`、`min_card_select = max_card_select = 1`、`control_options = 三项`建造请求；候选必须走既有的手牌候选构建入口（不得把他人手牌放进候选）。
  - **实现期补充**：后两个参数为可选补充项，三参数调用的名字与顺序与 `design.md` §2.3 原表一致；取消角色通过 `context[CONTEXT_KEY_CONTROL_CANCEL_OPTION_ID]` 声明（`request_card_choice` 只保留 `control_options` 条目的 `id`/`label`）。
- [x] E3 `_submit_card_choice` 的文字选项白名单（`:3653-3662`）加入 `card_position`，并新增「位次选项必须命中 `control_options`」的校验。
- [x] E4 `_submit_card_choice` 的确认分支：`confirmed = true` 时要求牌数恰为 `1` 且位次为 `pile_slot_1`/`pile_slot_2`（**不接受 `cancel` 作为已确认位次**）；`confirmed = false` 时不做牌数下限校验（与既有可取消请求同口径）。
- [x] E5 `scripts/ui/card_selection_panel.gd`：让 `card_position` 渲染牌候选区与三个位次按钮。
  - **实现期修正**：新增 `_add_position_options()` 而不是复用 `_add_control_options()`——后者把「点击 → `control_submitted`」写死，无法表达「位次 → `position_submitted`、取消 → `choice_cancelled`」两种语义。界面按 `context[CONTEXT_KEY_CONTROL_CANCEL_OPTION_ID]` 判定取消选项，**不硬编码任何选项 ID**；该分支隐藏底部确定/放弃按钮，使窗口恰好只有三个按钮。
- [x] E6 `scripts/ui/match_table.gd`：把 `card_position` 排除在内联分流之外（`_is_inline_hand_choice` `:3839`），确保走正式面板；`_is_inline_control_choice` `:3861-3868` 只列 `control`/`bool`/`target_control`，`card_position` 天然落空，无需改动。新增信号 `position_submitted` 与处理函数 `_on_card_position_submitted()`。
- [x] E7 界面可用性：未选牌时两个位次按钮不可确认、`cancel` 始终可用（AC14）。

### 阶段 F：AI 可提交性（R7 的必要条件）

- [x] F1 `_build_card_choice_actions()` 新增 `card_position` 分支：为每张候选生成 `pile_slot_1` / `pile_slot_2` 两个确认动作；取消动作由既有 `allow_cancel` 分支统一生成（因此合法动作数为 `候选牌数 × 2 + 1`）。
- [x] F2 断言：纯 AI 对局中该请求不会因「无合法动作」被直接拒绝（AC14/AC15 的边界）。

### 阶段 G：图鉴与牌面标识（R1）

- [x] G1 `scripts/ui/all_cards_panel.gd`：在资料页类型文本上标识「专属」（新增常量 `EXCLUSIVE_CARD_TAG_NAME = "专属"`，在 `_resolve_card_type_name()` 内前置）；`CARD_TYPE_NAMES` / `CARD_SUBTYPE_NAMES` 未改动，**未新增 `type` 取值**。该文本同时进入搜索文本，因此可直接搜索「专属」。
- [x] G2 `scripts/ui/card_view.gd`：牌面底部标签（`_type_text()`）新增可选参数 `is_exclusive`，为真时前置「专属 · 」；非专属牌文本逐字不变；未改 `_resolve_category_color` 语义。
- [x] G3 确认专属牌**不因未入牌堆而从图鉴消失**（G3 已确认现状如此，专项用例断言 `unreferenced_count > 0` 时 `validation_errors` 仍为空）。
- [x] G4 未新增任何 `Label` / `CheckBox` 文本控件（只改既有文本内容），仍按判据执行 `tests/font_color_audit_test.tscn`。

### 阶段 H：文档（R8）

- [x] H1 `docs/内容制作指南.md`：新增「专属锦囊牌」一节（字段、校验口径、入堆端口签名与返回值、使用约束）+「其他角色不可知」一节（私有承载口径、广播边界、置牌端口签名、位次语义、交互请求用法）；卡牌字段总表补 `exclusive`。
- [x] H2 `docs/游戏机制与玩法内容.md`：两个新概念的完整定义 + 全部具体数值（位次取值 1/2、默认值、无概率、无消耗；入堆端口缺省时的权威随机口径）。
- [x] H3 `docs/卡牌系统.md`：专属牌不走 `data/decks.json` 的数据流差异（引 `shuiyanqijun` 为先例）；运行时入堆后的数据流。
- [x] H4 `docs/界面与交互.md`：位次询问窗口的三个选项与「必须先选一张手牌」的可用性规则；图鉴对专属牌的显示。
- [x] H5 `docs/AI模块.md`：只写「本任务不新增 AI 策略；被放置事实对 AI 不可见」这一边界。
- [x] H6 `README.md`：「自动校验」章节新增专项测试入口。
- [x] H7 `临时反馈文档.md`：追加「学习反馈摘要」+「Git 提交描述」（分钟级时间戳）。

### 阶段 I：专项测试（R9）

- [x] I1 新增 `tests/exclusive_card_and_private_placement_test.gd` + `.tscn`，覆盖 AC1–AC17；设置隔离与控制器装配照 `control_all_characters_test.gd`。
- [x] I2 **实际执行**三个动态端口调用（不只查前置条件），并按 `card-authoring.md` 4.5 构造 `Array[int]` 强类型实参。
- [x] I3 防泄露断言用全量遍历（所有玩家的公开快照 + AI 快照 + 权威公开观察快照 + 公共日志条数 + 表现事件条数）。
- [x] I4 位次方向断言用**实际摸牌顺序**（`_controller.draw(0, 2, false)` 后按 `card_move_history` 中 `to_zone == "hand"` 的顺序核对）。
- [x] I5 断言信息带**实际观测值**。

---

## 四、验证命令

> `GODOT` = `E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe`
> 逐进程顺序执行，禁止并发。

```powershell
# 专项（新）
& $GODOT --headless --path . res://tests/exclusive_card_and_private_placement_test.tscn

# 直接相关回归
& $GODOT --headless --path . res://tests/smoke_test.tscn                      # 数据库校验与开局
& $GODOT --headless --path . res://tests/card_action_semantics_test.tscn      # 卡牌动作语义
& $GODOT --headless --path . res://tests/gameplay_regression_test.tscn        # 使用时机拓扑
& $GODOT --headless --path . res://tests/event_runtime_test.tscn              # 事件运行时
& $GODOT --headless --path . res://tests/skill_settlement_runtime_test.tscn   # 技能结算与续接
& $GODOT --headless --path . res://tests/phase_progression_test.tscn          # 阶段推进
# 快照/界面/网络形状敏感
& $GODOT --headless --path . res://tests/ui_layout_test.tscn
& $GODOT --headless --path . res://tests/font_color_audit_test.tscn
& $GODOT --headless --path . res://tests/lan_network_test.tscn
& $GODOT --headless --path . res://tests/lan_match_flow_test.tscn
# 已交付机制的回归（确认未破坏）
& $GODOT --headless --path . res://tests/turn_control_mechanism_test.tscn
& $GODOT --headless --path . res://tests/lan_turn_control_test.tscn
& $GODOT --headless --path . res://tests/zhuyan_zhili_test.tscn
& $GODOT --headless --path . res://tests/new_character_mechanics_test.tscn
& $GODOT --headless --path . res://tests/performance_and_pacing_test.tscn
```

判定标准：**退出码 0 + 输出自身 PASS 标记 + 日志无 `ERROR` / `SCRIPT ERROR` / `FAIL`**。

---

## 五、评审关卡（review gates）

| 关卡 | 位置 | 通过条件 |
|---|---|---|
| RG1 | 阶段 A 完成后 | `is_exclusive()` 纯查询可用；`smoke_test` 仍 PASS；`shuiyanqijun` 未受影响 |
| RG2 | 阶段 B 完成后 | 入堆端口三种非法输入零副作用；合法调用后牌堆 +1、移牌历史与 `card_moved` 各恰好一条；**`position == 1` 走既有 append 路径，既有洗牌/重排行为不变** |
| RG3 | 阶段 C 完成后 | 私有字段对他人公开快照**逐字节不变**（键不存在）；对本人可见；**`reveal_private` 不得成为可见性条件**，AI 快照与权威公开观察快照（`viewer_id = -1`）都不含该事实；存档往返不变 |
| RG4 | 阶段 D 完成后 | 置牌不写日志、不产生表现事件、不派发 `lose*` 时机；`position = 1/2` 的实际摸牌顺序正确 |
| RG5 | 阶段 E+F 完成后 | 位次窗口三选项可用性正确；伪造手牌/伪造位次被拒；AI 有合法动作且纯 AI 对局不挂住 |
| RG6 | 全部完成后 | AC1–AC17 逐条有对应断言或代码结构证据；全部回归测试 PASS；`validation_errors` 为空 |

---

## 六、回滚点

| 回滚点 | 范围 | 手段 |
|---|---|---|
| RB1 | 仅阶段 G（图鉴/牌面标识） | 回滚 UI 分支；规则层与 AI 照常工作，只是人类看不到专属标识 |
| RB2 | 仅阶段 E+F（询问选择类型） | 回滚新类型与白名单；专属牌与置牌端口仍可独立工作与断言 |
| RB3 | 仅阶段 B+C+D（规则端口） | 回滚端口与私有字段；对旧代码是未知键与无调用方的死代码 |
| RB4 | 全量 | 单独 revert 本次提交即可；无内容层调用方时两条机制**完全静默** |

---

## 七、完成判据

- [x] 阶段 A–I 全部勾选。
- [x] AC1–AC17 逐条可指认到断言或代码结构证据。
- [x] 第四节全部命令退出码 0 且打印各自 PASS 标记（**给出实际观测输出**）。
- [x] `GameDatabase.validation_errors` 为空。
- [x] `docs/` 中的字段名、端口名、常量名与 `design.md` §2.1–2.6 **逐字一致**。
- [x] 四条公开通道（快照 / 日志 / 回放 / 表现事件）逐一有「不泄露」的断言或代码结构证据。
