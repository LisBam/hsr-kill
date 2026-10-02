# 执行计划：回合操控机制（本回合由xx操控）

- 需求：[`prd.md`](./prd.md)
- 设计：[`design.md`](./design.md)
- 父任务：[`../10-02-kafuka-new-mechanics/prd.md`](../10-02-kafuka-new-mechanics/prd.md)

> 本计划只覆盖「本回合由xx操控」机制本身。不新增武将、技能、卡牌、AI 策略、事件时机名、网络协议。

---

## 一、开工前状态

| 项 | 状态 |
|---|---|
| `prd.md` | 已存在（208 行，含 R1–R12 / AC1–AC15 / K1–K6） |
| `design.md` | 已存在（271 行，含命名契约 2.1–2.5、数据流 4.1–4.5） |
| `implement.md` | 本文件 |
| `implement.jsonl` / `check.jsonl` | 本平台为 **inline 模式**，不走 JSONL 注入；开工前改用 `trellis-before-dev` 读规范（见「零、规范加载」） |
| `research/` | 无。父任务 `prd.md` 的「已确认的仓库事实」F1–F18 已替代调研产物，且已在本轮复核 |

---

## 零、规范加载（开工第一步）

1. 加载 `trellis-before-dev` 技能，读 `.trellis/spec/project/index.md` 下的 `collaboration-rules.md` / `documentation-sync.md` / `verification.md`。
2. 读 `.trellis/spec/core/index.md` 与 `layering-and-state.md`、`event-runtime-phases.md`（本任务只动权威侧）。
3. 读 `项目专属AGENTS.md`（铁律：原文不可变、机制处理流程）。

---

## 二、改前缺口与落点复核（本轮已完成，逐条给行号）

| # | 复核项 | 结论 | 行号 |
|---|---|---|---|
| G1 | `PlayerState` 公开字段落点 | `public_marks`(`:81`) 与 `auto_managed`(`:84`) 之间插入新字段；`to_dict` 公开区 `:535-537`；`from_authoritative_dict` `:318-320` | ✅ 确认 |
| G2 | 规则字段默认值 | 新字段默认 `-1`，旧存档缺键走 `int(data.get(..., -1))` | ✅ 确认 |
| G3 | `submit_action` 回合归属校验 | `:1972` `if action.actor_id != state.current_player_id: return _reject("行动者不是当前回合玩家。")`。LAN 客户端硬拒在 `:1866`（在 `:1972` 之前，因此 LAN 天然不受影响） | ✅ 确认 |
| G4 | `_is_answerable_human_actor` | `:932-947`，末行 `:947` 是离线分支返回点，也是「本人被操控 → false / 其操控者可作答 → true」的插入点 | ✅ 确认 |
| G5 | `get_legal_actions` | `:2221`，守卫在 `:2224`，要求 `state.current_player_id == player_id` **且** `current_phase == "play"`。被操控者恒为当前回合角色，因此本函数**本身无需放宽**；需要放宽的是「谁能替它取」——调用方在 `_emit_state`(`:16452`)、AI 决策与界面三处都用 `local_human_player_id`，随视角接管自动正确 | ⚠️ 设计 2.3 第三行需修正（见「三、设计偏差」） |
| G6 | 第一视角接管链路 | `_emit_state`(`:16420`) → `_prepare_offline_controlled_view`(`:16465`，首行 `:16466` 是 `_control_all_characters_enabled` 短路) → `_set_offline_manual_control_player`(`:16497`) | ✅ 确认，`:16466` 是必须新增前置分支的位置 |
| G7 | 视角归还收尾序列 | `:16526-16535` 是既有唯一完整归还序列（令牌递增 → 清调度 → 无懈重驱动 → 重发待办 → 广播 → 续接） | ✅ 确认，必须照抄 |
| G8 | 待办选择重发入口 | `_republish_manual_player_choice` 实际在 `:2158`（设计写 `:16533-16540` 是**调用点**，非定义点） | ⚠️ 行号口径修正 |
| G9 | 回合尾时机 | `_complete_finish_turn`(`:13669`) → `:13681` `_record_runtime_event("phaseAfter", ...)` → `:13682` `_run_phase_notification`。到期清理的插入点是 `:13680` 之后、`:13681` 之前 | ✅ 确认 |
| G10 | 死亡清理落点 | `death_resolution_service.gd:131/134`（`_after_die`）与 `:296/299`（`_cleanup`），均在 `clear_starring` 旁 | ✅ 确认 |
| G11 | AI 注册/注销端口 | `ai_coordinator.gd:17 register_basic_ai` / `:22 unregister_ai` / `:27 is_ai_controlled` | ✅ 确认 |
| G12 | 既有「控制所有角色」回归测试可照抄 | `tests/control_all_characters_test.gd`：设置隔离（`:199-211`）、控制器装配（`:175-195`）、开局选择清理（`:69-79`）、不可取消请求的确认兜底（`:229-250`） | ✅ 全部照抄 |
| G13 | 需要保存/恢复的 `GameSettings` | `control_all_characters_enabled`（唯一被本机制测试触碰的持久化项）。测试还必须显式关闭 `custom_character_assignment` / `customize_ai_characters` 并把 `mulligan_limit` 置 0，与 `:41-43` 同口径 | ✅ 确认 |
| G14 | Godot 可执行文件 | `E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe`（与 `project.godot` 声明的 4.7 一致） | ✅ 确认 |
| G15 | 新字段不会触发 `GameDatabase.validation_errors` | 本任务**不新增** `game_data/` 文件，卡牌/技能/武将/牌堆/势力注册表零改动 | ✅ 确认 |

---

## 三、与 `design.md` 的三处偏差（实现以本节为准，并回写 `design.md`）

| # | `design.md` 原写法 | 实际做法 | 原因 |
|---|---|---|---|
| D1 | `get_legal_actions()`「首行守卫由必须等于 `state.current_player_id` 放宽为等于当前回合角色」 | **不改** `get_legal_actions()` 的守卫 | 被操控者恒为当前回合角色（`begin` 的 R2.3 前置校验保证），守卫本来就通过。改它反而会放开「非当前回合角色也能取到合法动作」这条不该开放的查询面 |
| D2 | `_republish_manual_player_choice` 记为 `:16533-16540` | 定义在 `:2158`，`:16533` 是调用点 | 行号口径修正，实现与测试断言都按 `:2158` |
| D3 | 「三处调用点」中的第三处 = `get_legal_actions()` | 第三处改为 `_prepare_offline_controlled_view()` 的视角解析（`:16465`） | 代理解析真正需要共用的是**权限判定**（谁能提交 / 谁可作答 / 谁来取动作），视角解析是另一个正交问题。因此 `_resolve_turn_input_submitter()` 由 `submit_action()`(`:1972`) 与 `_is_answerable_human_actor()`(`:947`) 两处共用，并额外由 `get_legal_actions()` 的调用方口径间接复用 |

---

## 四、执行清单（按依赖顺序，逐项可独立验证）

### 阶段 A：规则事实（R1）

- [ ] A1 在 `scripts/data/player_state.gd` 的 `public_marks` 与 `auto_managed` 之间新增 `turn_input_delegate_id: int = -1`，含完整注释（作用/取值/默认值原因/是否运行时可改）。
- [ ] A2 `to_dict()` 公开区（`:535` 附近）写入 `"turn_input_delegate_id": turn_input_delegate_id`。
- [ ] A3 `from_authoritative_dict()`（`:318` 附近）用 `int(data.get("turn_input_delegate_id", -1))` 恢复。
- [ ] A4 复核 `to_dict` 的 `reveal_private` 分支：字段属于公开事实，**两个分支同值**，不得只写在 `reveal_private` 一侧。

### 阶段 B：控制器端口（R2 / R3）

- [ ] B1 `MatchController` 顶部常量区新增 `TURN_INPUT_DELEGATE_NONE = -1` 与 `TURN_INPUT_DELEGATE_LAN_REASON = "lan_turn_control_degraded"`，附注释说明取值来源与唯一性。
- [ ] B2 新增成员 `_turn_input_delegation_turns: Dictionary = {}`（键 = 被操控者 `player_id`，值 = `{turn_player_id, turn_number}`），注释明确：**非权威索引**，只为跨回合匹配而存在，不进快照、不进存档。
- [ ] B3 实现 `begin_turn_input_delegation(controlled, controller) -> bool`：五条前置校验（存在/存活/未离场、禁止自环、被操控者必须是当前回合角色、操控者本人未被操控、幂等或顶替），任一失败返回 `false` 且零副作用。
- [ ] B4 实现 `end_turn_input_delegation(controlled = -1) -> bool`：`-1` 清全场。
- [ ] B5 实现 `get_turn_input_delegate_id(controlled) -> int` 与 `is_turn_input_delegated(controlled) -> bool`：纯查询，无写状态。
- [ ] B6 实现 `_clear_turn_input_delegation(controlled, turn_player_id = -1, turn_number = -1) -> bool`：登记清除 + 视角归还 + 索引清理**同处完成**。

### 阶段 C：权限判定共用入口（R5 / R6）

- [ ] C1 新增 `_resolve_turn_input_submitter(actor_id: int) -> int`：有登记返回操控者，否则返回 `actor_id` 本身。
- [ ] C2 新增 `_is_turn_input_locked(actor_id: int) -> bool`：纯查询，只读 `turn_input_delegate_id`，**禁止触碰 `auto_managed`**。
- [ ] C3 `submit_action()` 在 `:1972` 之前插入代理放行与锁定拒绝；拒绝原因文本必须非空且可读（例："当前回合正由其他角色操控，你不能操作。"）。
- [ ] C4 `_is_answerable_human_actor()` 在 `:947` 返回前接入：`actor_id` 正被操控时，本人返回 `false`；其操控者是本机可作答人类时返回 `true`。
- [ ] C5 静态核对三处判定确实共用 C1/C2，不得出现第二份内联判断。

### 阶段 D：AI 兼容（R10）

- [ ] D1 `begin` 按「操控者性质」同步被操控者的基础 AI：本机真人（离线）→ `unregister_ai`；其余 → `register_basic_ai`。
- [ ] D2 `_clear_turn_input_delegation` 归还时恢复被操控者的基础 AI 注册状态（仅当原为 AI 座位）。
- [ ] D3 确认操控期间真人与 AI 不会同时向同一 `actor_id` 提交（D1 + C3 联合保证）。

### 阶段 E：第一视角接管与归还（R7）

- [ ] E1 `_prepare_offline_controlled_view()` 首行 `:16466` 之前新增前置分支：离线 + 当前回合角色有登记 + 操控者是本机真人 → 目标 = 被操控者。**优先级高于 `_control_all_characters_enabled`**。
- [ ] E2 新增 `_resolve_delegated_viewer_id() -> int` 私有纯查询承载 E1 的解析，避免在 `_prepare_offline_controlled_view` 内联堆逻辑。
- [ ] E3 接管当帧调用 `_republish_manual_player_choice(local_human_player_id)`（`:2158`）。
- [ ] E4 归还照抄 `:16526-16535` 收尾序列（令牌递增 → 清调度 → `_redrive_pending_negation_ai_tasks()` → 重发待办 → `_emit_state` → `_ensure_ai_progress_after_resolution()`）。
- [ ] E5 视角切换**只**经 `_set_offline_manual_control_player()`(`:16497`)，不新增第二套。

### 阶段 F：到期与清理（R3）

- [ ] F1 `_complete_finish_turn()` 在 `:13680` 之后、`:13681` 之前调用 `_clear_turn_input_delegation(player_id, player_id, state.turn_number)`（双重匹配）。
- [ ] F2 `death_resolution_service.gd` 的 `_after_die`(`:131/134`) 与 `_cleanup`(`:296/299`) 两处，在 `clear_starring` 旁清除：①该死者作为被操控者的登记；②全部以该死者为操控者的登记。
- [ ] F3 存档恢复后索引为空的回退：当前回合结束时无条件清除该被操控者登记（只可能提前一轮到期，不会永久残留）。
- [ ] F4 翻面被跳过的回合（不派发 `phaseAfter`）登记不由该回合到期，F3 回退接管；专项测试覆盖（K5）。

### 阶段 G：快照 / 存档 / 回放往返（R9）

- [ ] G1 确认 `to_dict(viewer, false)`（观察者裁剪）与 `to_dict(viewer, true)`（权威）都含新字段。
- [ ] G2 确认 AI 快照读到新字段（AI 走 `reveal_private=true` 路径）。
- [ ] G3 回放重演后 `get_turn_input_delegate_id()` 得到同一答案。

### 阶段 H：文档（R11）

- [ ] H1 `docs/内容制作指南.md` 新增「回合操控（本回合由xx操控）」一节（放在 `主演与座次相邻查询`(`:4038`) 相邻位置，同属「机制端口」族）。
- [ ] H2 `docs/游戏机制与玩法内容.md` 新增概念定义 + 全部具体数值（无随机数、无概率）。
- [ ] H3 `docs/界面与交互.md`：操控期间第一视角表现、被操控者旁观表现、操控结束归位。
- [ ] H4 `docs/架构说明.md`：规则字段位置、与「控制所有角色」的关系与差异。
- [ ] H5 `docs/网络通信.md`：LAN 降级说明。
- [ ] H6 `README.md`：「自动校验」章节新增 `turn_control_mechanism_test.tscn` 条目。
- [ ] H7 `临时反馈文档.md`：追加「学习反馈摘要」+「Git 提交描述」（分钟级时间戳）。

### 阶段 I：专项测试（R12）

- [ ] I1 新增 `tests/turn_control_mechanism_test.gd` + `.tscn`，覆盖 AC1–AC13；设置隔离与控制器装配照抄 `control_all_characters_test.gd:175-211`。
- [ ] I2 测试 PID/输出标记固定，成功打印 `TURN_CONTROL_PASS ...`，失败打印 `TURN_CONTROL_FAIL <reason>`。
- [ ] I3 断言信息必须带**实际观测值**（照抄 `control_all_characters_test.gd:85` 的写法）。

### 阶段 J：局域网完整代理提交协议（R8.1–R8.6，K1 改判后新增）

> 依赖：阶段 A–F 全部完成（登记、端口、代理解析、清理已就位）。阶段 J 在**不破坏阶段 A–I 任何断言**的前提下叠加 LAN 能力。

- [ ] J1 `PlayerState` 无需新字段；确认 `turn_input_delegate_id` 已在公开快照（A2 已完成）。
- [ ] J2 `NetworkGateway` 新增 `set_lan_proxy_actor_ids(peer_id, actor_ids)` / `is_lan_proxy_actor_authorized(peer_id, actor_id)`，内部成员 `_peer_proxy_actor_ids: Dictionary`。注释必须写明：**控制器 → 网关**方向、网关零规则语义、唯一写点是操控登记。
- [ ] J3 `NetworkGateway` 封包入口（`:1155-1160`）放宽为「等于绑定玩家 **或** 授权代理」；拒绝文本保持不变（旧客户端兼容）。
- [ ] J4 `NetworkGateway` 断线清理点清空该 peer 的授权项（与 `_peer_to_player_id` 清理同处）。
- [ ] J5 `MatchController` 新增 `_is_lan_proxy_submission_authorized(action) -> bool`（房主第二道防线，`:2183` 同区）。
- [ ] J6 `MatchController.submit_action()` 在 LAN 房主分支接入 J5；被拒绝时走既有 `_reject`（`_on_network_command_received` 会自动回传 `action_rejected`）。
- [ ] J7 `MatchController.submit_action()` 客户端分支（`:1866`）按 `_lan_proxy_actor_ids` 放行。
- [ ] J8 `MatchController._on_network_choice_request_received()`（`:15561`）按 `_lan_proxy_actor_ids` 放行。
- [ ] J9 `MatchController._on_network_snapshot_received()`（`:15542`）缓存快照顶层的 `turn_input_controlled_actor_ids` 到成员 `_lan_proxy_actor_ids`（只读缓存，不写规则状态）。
- [ ] J10 `MatchController._emit_state()` 逐 peer 循环（`:16439-16460`）注入授权字段 + 定向权重快照；授权列表为空时不进入新增分支（防泄漏 + 逐字节等价）。
- [ ] J11 `begin_turn_input_delegation()` 的 LAN 分支：房主本机 → 只登记；远端真人 → 校验 peer 有效性并下发授权表；无效 → 记录 `TURN_INPUT_DELEGATE_LAN_REASON` + 注册基础 AI + `return true`。
- [ ] J12 `_clear_turn_input_delegation()` 的 LAN 分支：登记清除后对受影响 peer **重建**授权表（可能为空数组 → 网关删项）。
- [ ] J13 `_on_lan_match_peer_disconnected`（`:15721`）清除该玩家作为操控者的全部登记 + 作为被操控者的登记。
- [ ] J14 `_on_lan_match_peer_reconnected`（`:15736`）只重发授权表，**不**恢复登记。
- [ ] J15 对局结束 / 重开清理点调用 `end_turn_input_delegation(-1)` 并清空网关授权表。
- [ ] J16 新增 `tests/lan_turn_control_test.gd` + `.tscn`，覆盖「五、验证命令」中列出的七项 LAN 断言（纯服务端构造，不起第二进程）。
- [ ] J17 `docs/网络通信.md` 写入完整协议说明；`README.md` 补 `lan_turn_control_test.tscn` 条目。

---

## 五、验证命令

> `GODOT` = `E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe`
> 逐进程顺序执行，禁止并发（会争用 `user://` 设置与 `.godot` 缓存）。

```powershell
# 专项（新）
& $GODOT --headless --path . res://tests/turn_control_mechanism_test.tscn

# 局域网专项（新，纯服务端构造，不起第二进程）
& $GODOT --headless --path . res://tests/lan_turn_control_test.tscn

# 回归（按顺序，逐条确认退出码 0 且打印 PASS 标记）
& $GODOT --headless --path . res://tests/control_all_characters_test.tscn   # 视角链路未被破坏
& $GODOT --headless --path . res://tests/zhuyan_zhili_test.tscn            # 主演未被影响
& $GODOT --headless --path . res://tests/phase_progression_test.tscn       # 阶段与回合尾时机
& $GODOT --headless --path . res://tests/gameplay_regression_test.tscn     # 使用时机拓扑
& $GODOT --headless --path . res://tests/lan_network_test.tscn             # LAN 协议未被破坏（需 UDP 回环）
& $GODOT --headless --path . res://tests/lan_match_flow_test.tscn          # LAN 房主权威/客户端无状态
& $GODOT --headless --path . res://tests/smoke_test.tscn                   # 数据库校验与开局
```

判定标准：**退出码 0 + 输出自身 PASS 标记 + 日志无 `ERROR` / `SCRIPT ERROR` / `FAIL`**。退出时的资源占用告警不算断言失败（与 `verification.md` 第五节一致）。

---

## 六、评审关卡（review gates）

| 关卡 | 位置 | 通过条件 |
|---|---|---|
| RG1 | 阶段 A 完成后 | `to_dict` 公开/私有两分支同值；旧存档缺键走 `-1`；不新增任何 `game_data/` 文件 |
| RG2 | 阶段 B 完成后 | 六种非法输入全部返回 `false` 且零副作用；`begin` 幂等与顶替语义可用只读断言验证 |
| RG3 | 阶段 C 完成后 | 三处判定共用同一解析函数；`auto_managed` 路径零触碰（grep 证明） |
| RG4 | 阶段 E 完成后 | `control_all_characters_test.tscn` 仍 PASS（视角链路未被破坏） |
| RG5 | 阶段 F 完成后 | 无关角色回合结束**不**清除登记；翻面跳过回合的登记不误到期 |
| RG6 | 阶段 J 完成后 | 操控者 peer 代提交被接受、第三方 peer 被拒、被操控者本人被拒；未授权 peer 快照与基线**逐字节等价**；`lan_network_test` / `lan_match_flow_test` 仍 PASS |
| RG7 | 全部完成后 | AC1–AC15 逐条有对应断言或代码结构证据；全部回归测试 PASS |

---

## 七、回滚点

| 回滚点 | 范围 | 手段 |
|---|---|---|
| RB1 | 仅阶段 J（LAN 协议） | 回滚网关授权表 + 控制器 LAN 分支；规则事实、离线接管与全部 AC1–AC11/AC13 仍成立。LAN 退回「只能操作自己」（改动前行为） |
| RB2 | 仅阶段 E（视角） | 只回滚 `_prepare_offline_controlled_view` 的前置分支；规则事实与端口仍可用、仍可断言 |
| RB3 | 仅阶段 A–D（规则侧） | 回滚 `player_state.gd` 与端口；字段对旧代码是未知键，无需数据迁移 |
| RB4 | 全量 | 单独 revert 本次提交即可。无内容层调用方时机制**完全静默**（没有任何自动触发点） |

---

## 八、完成判据

- [ ] 阶段 A–J 全部勾选。
- [ ] AC1–AC15 与 AC12b / AC12c 逐条可指认到断言或代码结构证据。
- [ ] 第五节全部命令退出码 0 且打印各自 PASS 标记。
- [ ] `GameDatabase.validation_errors` 为空（由 `smoke_test` 覆盖）。
- [ ] H1–H7 与 J17 文档全部同步，且 `docs/` 中的字段名/端口名与 `design.md` 2.1–2.6 **逐字一致**。
- [ ] `PROTOCOL_VERSION` **未**变更（新字段纯增量，旧客户端安全退化为「只能操作自己」）。
