# 开发者设置与开发者菜单（单机局内调试控制台）

## Goal

在**单机（离线）对局**的局内设置菜单中新增「开发者设置」入口，点击后打开一个独立的开发者菜单窗口。开发者可在该窗口内：

1. 指定场上任意角色作为**目标**（默认本人）；
2. 以该目标为作用对象，触发 9 项数值效果（摸牌、弃牌、回复体力、失去体力、受到伤害、增加体力上限、减少体力上限、获得护盾、失去护盾）；
3. 从摸牌堆中任选任意张牌交给目标；
4. 为重新选择武将。

所有规则效果必须在对局**当前结算完毕后的空闲时间**执行，绝不打断进行中的结算。

**用户价值**：开发者无需改动代码或依赖测试场景，即可在真实对局中快速构造任意状态（残血、濒死、满盾、特定手牌、指定武将），大幅缩短机制联调与缺陷复现的时间。需求原文「目前加入以下功能」表明后续还会追加功能，因此效果行必须可数据化扩展。

---

## Background（已确认的仓库事实）

以下事实均已通过代码/文档核实，作为需求与设计的共同前提。

### 入口与显隐

- 局内菜单组件为 `MatchMenu`（`scripts/ui/match_menu.gd`）。**该组件没有自己的 `.tscn`**：整个节点树写在 `scenes/main.tscn` 的 `MatchMenu/MenuPanel/MenuVBox`（约 226–615 行）内，脚本经 `ExtResource("13_menu")` 挂载。`main.tscn` 根节点 `Main` 的脚本就是桌面协调器 `match_table.gd`。
- 局内菜单的**按钮不是配置行**，而是 `MenuVBox` 的直接子节点（`MenuRestartButton` / `MenuConquestExitButton` / `MenuReturnToMainButton`，`main.tscn:597–615`），按 VBox 顺序排在全部设置行之后。行容器惯用法是从控件反查父节点（`match_menu.gd:106–148`）。
- `main.tscn` 的每个节点行都带 `unique_id=<整数>`（Godot 4.6+ 场景内唯一标识），新增节点必须提供一个当前场景未使用的整数。
- 离线判定已有唯一入口：`match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE`（`NetworkGateway` **没有** `is_offline()` 辅助函数，只有 `is_lan_host()` / `is_lan_client()` / `is_lan_match_active()`）。`match_table.gd:4187 _refresh_match_menu_authority_controls()` 已用同一判据把「控制所有角色」限制为纯离线对局，经 `match_menu.set_offline_controls_visible()`（`match_menu.gd:357`）生效。开发者设置入口必须复用这条链路。
- 项目**没有** `set_authority_controls_visible()` 的语义可借用：文档 `docs/界面与交互.md:139` 规定该入口是「房主权威控件组」，而开发者设置要求局域网房主也隐藏，因此属于 `_offline_controls_visible` 组。
- 层级表由 `docs/界面与交互.md:204` 固化且为硬约束：「新增界面必须落在上表已定义的层级之间，不得插队改变既有遮挡关系」。相关值：局内菜单 `500`、回放重演覆盖层 `620`。
- 项目**没有任何**已存在的开发者/调试/作弊端口（对 `debug_console` / `dev_console` / `cheat_` / `developer_mode` / `god_mode` / `_test_only` / `控制台` / `console` 的全量检索为空）。开发者菜单是全新代码。
- 项目**没有**「从局内菜单打开的模态窗口」先例；最接近的模态模板是 `CardSelectionPanel`（代码建全屏遮罩 `ColorRect` + `MOUSE_FILTER_STOP` + 居中面板）。

### 目标与玩家列表

- 界面只渲染观察者裁剪快照。玩家列表、公开武将名、体力、体力上限、护盾、存活状态均在快照 `players` 数组中，因此目标列表可完全由快照驱动，**不需要新增快照字段**。
- **快照不包含摸牌堆的牌面数据**（`game_state.gd` 的观察者快照只有 `draw_pile_count`）。因此「获得牌堆指定牌」的牌面列表必须由 `MatchTable` 经控制器只读端口取出后注入面板，不能由面板自行读取。

### 规则端口（全部已存在，无需新增状态写入逻辑）

| 效果 | 端口 | 位置 |
|---|---|---|
| 摸牌 | `draw(player_id, count, announce = true, allow_out_of_game = false) -> void` | `match_controller.gd:4421` |
| 弃牌 | `adjust_hand_size(player_id, target_count, completion_context = {}) -> bool` | `match_controller.gd:9323` |
| 回复体力 | `recover(source_id, target_id, amount, reason = "", allow_out_of_game = false) -> void` | `match_controller.gd:4430` |
| 失去体力 | `lose_hp(source_id, target_id, amount, reason = "", allow_out_of_game = false) -> int` | `match_controller.gd:4994` |
| 受到伤害（无来源） | `damage(source_id, target_id, amount, nature = "normal", ...) -> void`，`source_id = -1` | `match_controller.gd:5071` |
| 增减体力上限 | `change_max_hp(target_id, delta, source_id = -1, reason = "", allow_out_of_game = false, resolve_dying = true) -> int` | `match_controller.gd:4489` |
| 获得护盾 | `shield(target_id, amount, source_id = -1, reason = "") -> int` | `match_controller.gd:4439` |
| 失去护盾 | `change_hujia(target_id, delta, source_id = -1, reason = "") -> int` 负数分支 | `match_controller.gd:4466` |
| 获得摸牌堆指定牌 | `gain_draw_pile_card_by_uid(player_id, card_uid, reason = "gain_viewed_draw_card") -> CardInstance` | `match_controller.gd:9051` |
| 更换武将 | `replace_player_character_card(player_id, new_character_id, reason = "", preserve_runtime_max_hp_delta = true) -> bool` | `match_controller.gd:4634` |

**弃牌的关键约束**：`request_card_choice()` 的恢复分派器 `_continue_card_choice`（私有，`match_controller.gd:4135`）只认识固定的一组 `context.kind`（`dying_response` / `trick_negation` / `discard_phase` / `adjust_hand_size` / `extra_discard_phase` / `discard_target` / `steal_target`）。**自行用 `request_card_choice()` 配一个新 `kind` 会永久挂起**（请求无人恢复）。因此弃牌必须复用 `adjust_hand_size()`：传 `target_count = 当前手牌数 - N`，由规则层建立真正的玩家自选弃牌窗口；`target_count` 内部 `maxi(..., 0)` 钳制，手牌不足 N 张时退化为「弃置全部手牌」。
`discard_n_from_player()`（`:7003`）是自动按区域顺序弃置、**不让玩家选择**，不满足需求。

**弃牌只作用于普通手牌**：`adjust_hand_size()` 的候选由 `_build_player_zone_candidates(player_id, player_id, true, false, false)` 生成，只含手牌，不含装备与判定区。这是本设计接受的边界（见「已定决策 D3」）。

### 空闲时间执行

- 控制器已有唯一的「延后到结算边界」机制：`_schedule_settlement_pipeline_resume()`（`:2739`）经 `get_tree().process_frame`（`CONNECT_ONE_SHOT`）登记**唯一**一次跨帧唤醒，并用 `_settlement_resume_generation` 代次校验让重开/拆除后的旧回调自动失效；`_run_scheduled_settlement_pipeline_resume()`（`:2751`）校验通过后调用 `_resume_settlement_pipeline()`。
- 统一结算管线的固定优先级链在 `_run_settlement_pipeline_pass()`（`:13043`）内：子序列恢复 → 触发/装备/规则续接 → 技能「然后」步骤（`_deferred_skill_settlements`）→ 阶段恢复（`_resume_interrupted_turn_flow()`）。
- **`Callable.call_deferred` 明确不可作为跨帧证据**（`docs/战斗结算框架.md:63`：*「`call_deferred` 可能在同一空闲轮继续排空，不能作为跨帧证据」*）。
- 「当前是否处于结算内部」的既有公开判据是 `has_nested_settlement_barrier()`（`:12935`，= `has_pending_card_choice() or not _queued_equipment_triggers.is_empty()`）；**项目不存在** `is_idle()` / `is_busy()` 这类统一公开谓词。
- 项目既有做法**全部**是「登记到队列 + 管线在安全点消费」，从不靠外部轮询 idle。三条结构同构的先例：`_deferred_skill_settlements`（技能「然后」）、`_rule_continuations`（通用规则后半段，白名单 `RULE_CONTINUATION_TYPES`，`match_controller.gd:151–167`）、`_queued_equipment_triggers`（装备触发）。
- 管线活跃性兜底判据是 `_has_unresolved_settlement_work()`（`:13032`）：待选/待判定时返回 `false`（由响应路径负责恢复），其余队列非空返回 `true`。这是「是否需要重新登记唤醒」的唯一依据，**新队列必须加入该判据**。
- `defer_skill_settlement()`（`:12585`）**不适用于**开发者菜单：它要求真实 `SkillDefinition` 实例与 `character_generation` 匹配。
- 重开/拆除对局的统一清理入口：`_teardown_previous_match_runtime()`（`:1664`）、`_reset_per_match_progress_state()`（`:1755`）、`_discard_failed_match_start()`（`:1809`）。

### 界面层边界

- `docs/架构说明.md`「总体原则」与 `.trellis/spec/ui/index.md` 明确：**UI 层不得读取 `GameState` / `MatchController` 或技能运行时实例，只渲染快照并提交 `PlayerAction`**。
- `docs/内容制作指南.md:12` 是关键约束原文：多角色控制能力*「必须限制在 `NetworkGateway.Mode.OFFLINE`；联机房主也不能借此提交其他真人角色动作。」*
- 既有合法例外：`match_table.gd` 作为协调器可读控制器只读预览并调用 `start_match()`。开发者菜单属于**同类特权表面**，必须（a）以 `NetworkGateway.Mode.OFFLINE` 硬门控，（b）每次效果后调用 `refresh_state_snapshot()`（`match_controller.gd:17926`）刷新快照。

### 已知陷阱

- **所有规则变更端口都静默早退**：死亡 / 离场 / 非正数 / 体力已满（`recover()` 在满体力时静默无事发生，`recovery_resolution_service.gd:17`）都不报错、不写日志。开发者菜单必须读取返回值或对比状态，显式反馈「本次未生效」，否则界面看起来像坏了。
- `SpinBox` 的静默写入不会刷新内部 `LineEdit` 文本（`match_menu.gd:263–273` 已踩过）；`_apply_spin_box_style()` 为各面板私有副本。
- `MatchMenu` 自身不处理 Esc；Esc 由 `match_table.gd:3450 _unhandled_input()` 统一处理，空白左键关闭由 `match_table.gd:3503` 处理。模态必须自行用全屏遮罩吃掉输入，并在 `_unhandled_input` 里抢在菜单之前消费 Esc。
- 焦点规则：控件隐藏时必须 `release_focus()`（照 `set_offline_controls_visible` 的写法）。
- `refresh_ui_style()` 是各面板的既定契约，需由 `match_table.gd` 在主题刷新时调用（`match_table.gd:3637` 一带）。
- 部分测试按节点路径取菜单子节点（`tests/main_menu_test.gd:194/340`、`tests/wheel_duel_mode_test.gd:138`、`tests/pre_game_customization_test.gd:148`、`tests/doudizhu_mode_test.gd:408`）；它们按**名字**取节点，因此在按钮区新增按钮不破坏这些路径，但 `ui_layout_test.gd` 的几何断言需要复核。

---

## Requirements

### R1 — 开发者设置入口（仅单机）

- R1.1 局内菜单新增「开发者设置」按钮，作为 `MenuVBox` 直接子节点，位于 `MenuReturnToMainButton` 之前。
- R1.2 该按钮**仅在纯离线对局显示**（`NetworkGateway.Mode.OFFLINE`）；局域网房主与客户端一律隐藏，隐藏时不占 `VBoxContainer` 高度。
- R1.3 按钮点击只发出意图信号（`developer_settings_requested`），由 `MatchTable` 打开窗口；`MatchMenu` 不持有开发者菜单节点、不读取控制器（保持文件头既有约定：「该组件只管理菜单显隐……通过信号请求桌面执行」）。
- R1.4 按钮隐藏时必须释放焦点，避免焦点残留在不可见控件上。
- R1.5 按钮样式经 `BattleUIStyle.apply_interaction_button()` 上色，并纳入 `refresh_ui_style()`。

### R2 — 开发者菜单窗口

- R2.1 点击后打开独立模态窗口：新建 `scripts/ui/developer_console_panel.gd`（`class_name DeveloperConsolePanel extends Control`），由 `MatchTable` 在运行时 `add_child(self)` 创建，与 `MatchChatPanel` / `GameSettlementPanel` 同款装配方式。
- R2.2 窗口结构：标题行（标题 + 关闭按钮）、目标选择区、数值效果列表区（可滚动）、纯按钮区、状态反馈行。
- R2.3 全屏遮罩 `ColorRect` 设 `MOUSE_FILTER_STOP` 阻断其下所有鼠标输入；遮罩颜色经 `BattleUIStyle.get_color("shade")` 读取，不硬编码。
- R2.4 `z_index = 520`（高于局内菜单 `500`，低于回放覆盖层 `620`），常量置顶为 `const CONSOLE_Z_INDEX: int = 520`。
- R2.5 打开后**暂停对局**（2026-10-06 修订，原为「不暂停」）：窗口打开即申请对局暂停令牌（原因 `developer_console`），窗口不可见时释放，因此对局在窗口开启期间停止推进。暂停不会阻断效果执行：结算管线入口 `_run_settlement_pipeline_pass()` 不检查对局暂停，且唤醒走 `SceneTree.process_frame`（暂停期间照常发出）。
- R2.6 关闭方式：关闭按钮、Esc、安卓返回键；关闭只发 `close_requested` 信号，由 `MatchTable` 处理并归还焦点。
- R2.7 实现 `refresh_ui_style()`，由 `MatchTable` 在主题刷新时调用。
- R2.8 面板不读取 `GameState` / `MatchController`；一切数据经 `MatchTable` 注入，一切操作经信号回传。

### R3 — 目标选择

- R3.1 窗口顶部提供目标选择控件（`OptionButton`），候选为**当前场上全部角色**（含已死亡角色，便于观察；能否施加具体效果由规则端口自身的存活校验决定）。
- R3.2 候选显示格式沿用既有口径：`武将名（玩家名）`；未公开武将时只显示玩家名。
- R3.3 默认选中**本人**（`match_controller.local_human_player_id`）。
- R3.4 9 项数值效果、获得牌堆指定牌、更换武将**全部**以当前选中目标为作用对象。
- R3.5 目标列表随快照刷新而更新（新玩家、换将、死亡都反映），但**不重置**开发者当前的选择；仅当该玩家已不存在时回退到本人。
- R3.6 目标候选与选中态由 `MatchTable` 从快照构建后注入。

### R4 — 九项数值效果（按钮 + 拖条 + 输入框）

以下 9 项各占一行，行内结构固定为「按钮 → 拖条 → 输入框」：

- R4.1 拖条为 `HSlider`，整数 `1..10`，默认 `1`，样式照 `main_menu.gd:1824 _apply_slider_style()`。
- R4.2 输入框为**无上限**整数输入；最小值 `1`。按项目既有「文本优先」惯例实现取值（参考 `lan_lobby_panel.gd:157 get_port()` 与 `match_menu.gd:290 get_next_player_count()`）。
- R4.3 拖条与输入框双向同步：拖动拖条写入输入框；输入框数值超过 `10` 时拖条钳制显示在 `10`，但输入框保留真实数值。程序化写值必须用 `set_value_no_signal()` 切断回环。
- R4.4 效果列表与顺序固定为：摸牌、弃牌、回复体力、失去体力、受到伤害、增加体力上限、减少体力上限、获得护盾、失去护盾。
- R4.5 点击按钮后按当前数值、对当前目标提交一次效果请求。
- R4.6 各效果的语义严格复用既有规则端口，**不得在界面侧另写一套数值结算**：
  - 摸牌：`draw(target, N)`；
  - 弃牌：`adjust_hand_size(target, 当前手牌数 - N)`，由目标**自行选择**弃置（只含手牌）；
  - 回复体力：`recover(-1, target, N)`（受体力上限限制；满体力时无事发生）；
  - 失去体力：`lose_hp(-1, target, N)`（不经护盾、不触发伤害时机）；
  - 受到伤害：`damage(-1, target, N)`，**无来源**、`nature = "normal"`，走完整伤害时机与濒死流程；
  - 增加体力上限：`change_max_hp(target, +N)`；
  - 减少体力上限：`change_max_hp(target, -N)`（至少保留 1 点上限）；
  - 获得护盾：`shield(target, N)`；
  - 失去护盾：`change_hujia(target, -N)`（最低为 0，不产生伤害或体力减少）。
- R4.7 每次提交后，窗口状态行显示本次结果（生效数值 / 已排队 / 未生效原因），因为规则端口静默早退，没有反馈就无法区分「排队中」与「无效果」。

### R5 — 获得牌堆中的指定牌（纯按钮）

- R5.1 点击后打开**第二层窗口**，列出当前摸牌堆中的**全部**牌（含花色、点数、当前名称），按摸牌堆顺序（数组末尾为牌堆顶）展示，可滚动。
- R5.2 支持任意张多选；选中后点击「确定」把所选牌逐张交给**当前目标**。
- R5.3 未选中任何牌时「确定」禁用。
- R5.4 「取消」/Esc 关闭第二层窗口且不获得任何牌，返回开发者菜单。
- R5.5 获得逐张经 `gain_draw_pile_card_by_uid()`；因此只能获得**执行时仍位于摸牌堆**的牌，已被其他效果移走的牌跳过，并在状态行报告实际获得张数。
- R5.6 牌面数据由 `MatchTable` 经控制器**只读**端口取出后注入第二层窗口；该端口为纯查询，**不得重洗、不得移牌、不得改变牌堆顺序**。
- R5.7 第二层窗口沿用 `CardSelectionPanel` 的多选交互形态（牌面网格 + 选中态 + 确定/取消），不复用 `AllCardsPanel`（后者只读静态定义、无选择信号）。

### R6 — 更换武将（纯按钮）

- R6.1 点击后打开**第二层窗口**，列出**全部武将（含 `special = true` 特殊武将）**，按势力分组，单选一名后「确定」。
- R6.2 确定后对当前目标调用 `replace_player_character_card()`；失败（目标已死亡、已离场、未配置武将、目标武将相同）时在状态行给出可读提示且不改变任何状态。
- R6.3 「取消」/Esc 关闭并返回开发者菜单。
- R6.4 窗口需支持滚动与搜索/分组，以承载约 189 名武将。
- R6.5 武将列表为静态数据，由 `MatchTable` 从 `GameDatabase` 取得后注入。

### R7 — 空闲时间执行（核心时序约束）

- R7.1 所有效果请求（R4 全部 9 项、R5、R6）**不得**在控制器正在结算时直接执行。
- R7.2 请求先进入控制器新增的**开发者待办队列**（纯数据 `Array[Dictionary]`）；队列由统一结算管线在既有优先级链的**最末端**消费（在 `_deferred_skill_settlements` 之后、`_resume_interrupted_turn_flow()` 之前），保证触发续列、装备触发、规则续接、技能「然后」全部排空后才轮到开发者效果。
- R7.3 延后唤醒必须复用控制器既有的唯一机制（`_schedule_settlement_pipeline_resume()` 与 `_settlement_resume_generation` 代次校验）；**禁止**自建 `call_deferred` 或第二套计时器。
- R7.4 开发者待办队列必须加入 `_has_unresolved_settlement_work()` 的判据，否则管线在「本轮入口作废旧唤醒 + 同步排空提前返回」时会永久滞留。
- R7.5 有待办选择或待判定时，效果**排队等待**，直到该交互完成、结算真正空闲才执行。开发者菜单必须把「已排队 N 项」显式显示出来，不能静默。
- R7.6 重新开局、返回主菜单、对局终局、节点离树时，待办队列与延后唤醒必须一并失效；清理点与 `_deferred_skill_settlements` 同行（`_teardown_previous_match_runtime()` / `_reset_per_match_progress_state()` / `_discard_failed_match_start()`）。
- R7.7 队列中的每个请求在执行前重新校验对局代次与目标玩家存在性；过期请求静默丢弃并写一条开发者日志。
- R7.8 同一帧提交的多个请求按提交顺序依次执行，且每个请求之间保持「结算边界」语义（前一个效果产生的时机与嵌套选择全部结束后才执行下一个）。
- R7.9 效果执行后调用 `refresh_state_snapshot()` 刷新快照，使界面立即反映结果。

---

## Acceptance Criteria

| 编号 | 验收标准（可观察结果） |
|---|---|
| AC1（R1） | 单机对局中打开局内菜单，可见「开发者设置」按钮；进入局域网房主或客户端后，该按钮完全隐藏且不占位、不持有焦点。 |
| AC2（R2） | 点击「开发者设置」后出现开发者菜单窗口；关闭按钮、Esc、安卓返回键均可关闭并归还焦点；窗口打开期间其下方的局内菜单与牌桌控件不可点击。 |
| AC3（R3） | 窗口打开时目标默认选中本人；切换目标后，后续所有效果都作用在新目标上（以目标体力/手牌/护盾的实际变化验证）。 |
| AC4（R4.1–R4.3） | 拖动拖条，输入框数值同步变化；输入框输入 `1`、`10`、`11`、`999` 时拖条分别显示 `1`、`10`、`10`、`10`，输入框保留 `11`/`999`；输入框不接受小于 `1` 的值。 |
| AC5（R4.6 摸牌） | 目标手牌数增加 N，牌堆剩余数减少 N，日志出现对应摸牌记录。 |
| AC6（R4.6 弃牌） | 目标出现标准选牌窗口且只能选普通手牌；确认后所选牌进入弃牌堆；手牌不足 N 张时退化为弃置全部手牌并在状态行报告实际弃置数。 |
| AC7（R4.6 回复/失去体力） | 回复使目标体力上升且不超过上限；满体力时状态行报告「未生效」。失去体力使目标体力下降且**不消耗护盾**、不产生伤害事件。 |
| AC8（R4.6 受到伤害） | 目标按「先扣护盾、再扣体力」的既有顺序结算 N 点伤害；伤害来源为空（不计入任何角色击杀/造成伤害统计）；穿透护盾时进入正常濒死流程。 |
| AC9（R4.6 体力上限） | 增加/减少体力上限分别令 `max_hp` 上升/下降 N；减少到 0 以下时至少保留 1 点。 |
| AC10（R4.6 护盾） | 获得护盾令护盾 `+N`；失去护盾令护盾 `-N` 且最低为 0，且**不**产生伤害、体力减少或濒死。 |
| AC11（R5） | 点击「获得牌堆中的指定牌」出现第二层窗口并列出摸牌堆全部牌；多选后确定，所选牌进入目标手牌且牌堆顺序保持稳定；取消不获得任何牌。 |
| AC12（R6） | 点击「更换武将」出现第二层窗口并列出全部武将（含 special）；选择并确定后目标武将牌替换为新武将，`preserve_runtime_max_hp_delta = true` 语义保持；取消不改变状态；对死亡/离场目标操作时状态行给出可读提示且状态不变。 |
| AC13（R7.2/R7.8） | 在一次结算进行中点击效果按钮，效果不会立即生效；当前结算（含嵌套选择）完全结束后才生效。连续点击多个效果，按点击顺序逐个在结算边界生效。 |
| AC14（R7.5） | 存在待办选择（如正在选【闪】）时点击效果，状态行显示已排队；该交互完成后效果自动生效。 |
| AC15（R7.6） | 有待办效果时重新开局或返回主菜单，新一局不出现旧效果的任何痕迹（无伤害、无摸牌、无日志）。 |
| AC16（层边界） | 新增的开发者菜单面板组件不出现对 `GameState` / `MatchController` 的直接读取；所有权威操作经 `MatchTable` → 控制器端口完成；入口在局域网下不可达。 |
| AC17（回归） | `ui_layout_test`、`font_color_audit_test`、`smoke_test` 通过；`GameDatabase.validation_errors` 为空、可正常开局。 |
| AC18（可扩展性） | 新增一项数值效果只需追加一条效果声明数据（键、显示名、端口映射），不需要修改窗口构建代码或新增分支散落在多处。 |

---

## Out of Scope

- 局域网（房主与客户端）中的开发者菜单：需求明确限定「单机模式下」，LAN 一律隐藏入口。
- 主菜单设置中的开发者入口：已确认仅局内菜单。
- 任意脚本执行 / 控制台（REPL）、任意技能强制发动、牌堆重排、AI 决策强制指定等未列出的调试能力。
- 通过开发者菜单修改对局胜负状态或直接结束对局。
- 修改任何既有卡牌、技能、武将的规则数值。
- 弃牌作用于装备区与判定区（本设计只作用于普通手牌，见 D3）。
- 伤害属性选择（本设计固定普通伤害，见 D4）。

---

## 已定决策

| 编号 | 决策 | 依据与影响 |
|---|---|---|
| D1 | 入口仅放局内菜单，且仅 `NetworkGateway.Mode.OFFLINE` 可见 | 已与用户确认；开发者菜单要操作场上角色与牌堆，必须有进行中的对局 |
| D2 | 全部效果统一作用于「当前选中目标」，默认本人 | 已与用户确认 |
| D3 | 弃牌只作用于**普通手牌** | `adjust_hand_size()` 是唯一带玩家自选窗口且恢复分派器可识别的端口；自行 `request_card_choice` + 新 `kind` 会永久挂起。扩展到装备/判定区需要新增 `context.kind` 与恢复分支，属于额外核心改动，本轮不做 |
| D4 | 受到伤害固定 `nature = "normal"`（普通伤害） | 需求原文只指定「无来源」，未指定属性。属性伤害（火焰/雷电）会额外触发藤甲修正与属性连环，语义不同；本轮保持最小实现 |
| D5 | 窗口打开时**暂停**对局（2026-10-06 反转，原为「不暂停」） | 用户明确要求打开开发者设置时暂停游戏。原判断「暂停会使空闲时间永不到来」经实测不成立：结算管线入口不检查对局暂停，唤醒走 `SceneTree.process_frame`（暂停期间照常发出），因此效果在暂停期间照常执行 |
| D6 | 有待办选择/判定时效果**排队等待**，不抢占 | 管线在 `has_pending_card_choice()` 时提前返回；强行插入会使正在等待的选择请求失效（目标死亡/换将/牌被移走），与项目「不得叠加请求」的既有约定冲突 |
| D7 | 更换武将池为**全部武将（含 special）** | 已与用户确认；`replace_player_character_card()` 本就直接查完整数据库，是「特殊武将只能通过的显式规则入口」 |
| D8 | 开发者效果队列落在统一结算管线既有优先级链的**最末端** | 与 `_deferred_skill_settlements` / `_rule_continuations` / `_queued_equipment_triggers` 三条既有队列结构同构，不新增第二条推进路径 |
| D9 | 第二层「获得牌堆指定牌」窗口沿用 `CardSelectionPanel` 的多选交互形态，不复用 `AllCardsPanel` | `AllCardsPanel` 只读静态定义、只有 `close_requested`、无选中态；`CardSelectionPanel` 已具备 `min_select`/`max_select` 与 `choice_submitted(request_id, selected_card_uids)` |
| D10 | 效果行以**数据声明**驱动（效果键、显示名、端口映射集中在一处常量/`@export`），不在窗口构建代码里散落分支 | 需求原文「目前加入以下功能」表明后续会追加功能；满足 AGENTS.md 的「参数前置与暴露」「解耦至上」 |
| D11 | 开发者菜单是**离线特权表面**，以 `NetworkGateway.Mode.OFFLINE` 硬门控，并在每次效果后 `refresh_state_snapshot()` | `docs/内容制作指南.md:12` 要求多角色控制能力必须限制在 OFFLINE |

---

## Technical Notes

- **分层归属**：`core` 侧只新增「开发者请求队列 + 空闲边界执行 + 两个只读查询端口（摸牌堆全量牌面、武将目录）」；`ui` 侧新增无状态面板组件与第二层窗口；`MatchTable` 负责装配、注入与转发。**不新增任何数值结算逻辑**，全部复用既有端口。
- **不新增快照字段**；除摸牌堆只读端口外不扩展观察者快照。
- **不改动 `MatchController` 既有公开签名**，只新增端口，遵循「新增逻辑优先落在单一职责服务组件中」的规范。
- **文档同步**：`docs/界面与交互.md`（入口位置与显隐条件、窗口结构、`z_index` 表新增 `520`、第二层窗口规格）、`docs/游戏机制与玩法内容.md`（新增章节，记录全部数值：拖条 `1..10`、输入框最小值 `1`、9 项效果语义、空闲时间执行规则）、`docs/架构说明.md`（开发者请求队列与空闲边界端口、离线特权表面边界）。
- **测试**：至少跑 `ui_layout_test`、`font_color_audit_test`、`smoke_test`；新增开发者队列属于结算管线改动，需加跑 `event_runtime_test` 与 `phase_progression_test` 以确认未破坏既有优先级链。
