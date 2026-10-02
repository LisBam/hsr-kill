# 技术设计：回合操控机制（本回合由xx操控）

对应需求：[`prd.md`](./prd.md)

---

## 一、设计目标与边界

**一句话**：在**不改动回合推进模型**的前提下，让「某角色本回合的操作由另一名角色提供」成为一条可查询、可存档、可回放、可安全归还的**规则层事实**，并让对局的第一视角自动跟随这条事实——离线用「切换观察者」，局域网用「以被操控者为观察者的定向私有快照」+「代理提交协议」。

因此本设计的三条硬约束：

1. **不改 `_start_turn` / `_finish_turn` / 额外回合队列 / 六阶段游标**。回合归属仍是 `state.current_player_id` 单值，阶段推进一行不动。
2. **离线不新增第二套视角切换实现**。第一视角的唯一落点仍是 `MatchController._set_offline_manual_control_player()`（`scripts/core/match_controller.gd:16497`）。
3. **局域网不改客户端 `local_human_player_id` 绑定**。客户端身份由协议绑定（`scripts/core/match_controller.gd:1866`），LAN 的「接管」表现为**代理提交 + 定向快照叠加**，而不是替换客户端观察者身份（详见 §4.6–4.9）。

之所以能做到，是因为仓库里已有两处解耦（已由调研证实）：

- **回合归属 ≠ 操作归属**：回合归属看 `state.current_player_id`（校验点 `scripts/core/match_controller.gd:1972`），操作归属看 `local_human_player_id`（判定点 `:947`）。
- **第一视角 = `local_human_player_id` 一个字段**：`scripts/ui/match_table.gd` 已全量跟随它（`:2167,2759,3015,3706,5206`），UI 侧零新增接口。

---

## 二、命名与契约（实现后 `docs/` 必须与本节逐字对齐）

### 2.1 规则层字段

| 项 | 值 |
|---|---|
| 落点 | `PlayerState`（`scripts/data/player_state.gd`，`public_marks` 同区，`:80-81` 之后） |
| 字段名 | `turn_input_delegate_id` |
| 类型 / 默认值 | `int` / `-1` |
| 语义 | `-1` = 本角色本回合由本人操作；`>= 0` = 本角色本回合的操作由该 `player_id`（操控者）提供 |
| 可见性 | **公开**。写入 `to_dict()` 的公开部分（与 `auto_managed`、`public_marks` 同区，`:535-537`），并写入 `from_dict()` 恢复 |
| 是否运行时动态修改 | 由 `MatchController.begin_turn_input_delegation()` / `end_turn_input_delegation()` 写入，内容层与 UI 只读 |

> 为什么放在 `PlayerState` 而不是控制器内存：`docs/内容制作指南.md:4040` 已经用「主演」确立了同一口径——**规则事实应寄存在既有的可序列化玩家状态里**，这样观察者快照、权威存档、AI 快照与回放四条通道全部自动往返，不需要任何额外同步代码。放到控制器内存会迫使回放与存档各自再抄一份，且无法断言。

### 2.2 控制器端口

```gdscript
## 建立「被操控者的本回合由操控者执行」的权威登记。
func begin_turn_input_delegation(controlled_player_id: int, controller_player_id: int) -> bool

## 撤销登记；controlled_player_id < 0 表示清除全场全部登记。
func end_turn_input_delegation(controlled_player_id: int = -1) -> bool

## 返回被操控者的操控者 ID；无登记返回 -1。纯查询。
func get_turn_input_delegate_id(controlled_player_id: int) -> int

## 判断指定角色当前是否正被他人操控。纯查询。
func is_turn_input_delegated(controlled_player_id: int) -> bool
```

### 2.3 唯一代理解析入口（R5 的落点）

新增一个**私有纯查询**函数，供三处权限判定共用：

```gdscript
## 解析「谁有权提供该角色的操作」；无代理时返回该角色本人。
## 返回值：合法提交者 player_id；无法解析（角色无效/无登记）时返回 actor_id 本身。
func _resolve_turn_input_submitter(actor_id: int) -> int
```

三处调用点（必须全部改为走它，禁止各写一份判断）：

| 调用点 | 位置 | 改法 |
|---|---|---|
| `submit_action()` 回合归属校验 | `scripts/core/match_controller.gd:1972` | 在 `action.actor_id != state.current_player_id` 之前插入代理放行：提交者 == `_resolve_turn_input_submitter(action.actor_id)` 时跳过该拒绝 |
| `_is_answerable_human_actor()` | `scripts/core/match_controller.gd:932-947` | 末尾返回前增加：`actor_id` 正被操控且其操控者可作答 → `true`；`actor_id` 本人正被操控 → `false` |
| `get_legal_actions()` | `scripts/core/match_controller.gd:2221` | 首行守卫由「必须等于 `state.current_player_id`」放宽为「等于当前回合角色」；调用方身份另行用 `_resolve_turn_input_submitter()` 判定 |

### 2.4 输入锁定（R6 的落点）

```gdscript
## 判断该角色的操作是否已被规则锁定（正被他人操控，本人不得提交）。纯查询，不写状态。
func _is_turn_input_locked(actor_id: int) -> bool
```

**明确不使用 `auto_managed`**：`auto_managed` 会注册基础 AI（`scripts/core/match_controller.gd:1895,2109`；`scripts/ai/ai_coordinator.gd:17,22`），语义是「AI 代打」，与本机制冲突。本函数只读 `turn_input_delegate_id`。

### 2.5 新增常量（集中在 `MatchController` 顶部 `@export` / 常量区）

| 常量 | 值 | 含义 |
|---|---|---|
| `TURN_INPUT_DELEGATE_NONE` | `-1` | 无操控登记；与字段默认值同源，禁止在别处写字面量 `-1` |
| `TURN_INPUT_DELEGATE_LAN_REASON` | `"lan_turn_control_degraded"` | LAN 授权条件无法满足时的显式降级诊断原因字符串，用于记录与测试断言 |
| `SNAPSHOT_CONTROLLED_ACTOR_IDS_KEY` | `"turn_input_controlled_actor_ids"` | 快照顶层授权字段名；只在被授权观察者的快照中出现 |

### 2.6 局域网协议契约（R8）

#### 2.6.1 快照新增字段

| 项 | 值 |
|---|---|
| 落点 | 快照顶层（`_emit_state()` 内，与 `local_legal_actions`、`local_pending_choice_request_ids` 同区） |
| 字段名 | `turn_input_controlled_actor_ids` |
| 类型 / 默认值 | `Array[int]` / 空数组（缺席等价于空数组） |
| 语义 | 该观察者**被授权代提交**的 `actor_id` 列表；当且仅当 `PlayerState[actor].turn_input_delegate_id == 观察者` 时包含 `actor` |
| 可见性 | **按观察者裁剪**：只出现在被授权观察者的专属快照里；不得进入公共广播、不得进入回放录制 |
| 是否运行时动态修改 | 由 `begin_turn_input_delegation()` / `end_turn_input_delegation()` 间接触发重建，客户端只读 |

#### 2.6.2 网关授权表端口（新增，方向：控制器 → 网关）

```gdscript
## 下发某远端 peer 被授权代提交的 actor 集合；只由操控登记的单点写入方调用。
func set_lan_proxy_actor_ids(peer_id: int, actor_ids: Array[int]) -> void

## 查询某远端 peer 是否被授权代提交指定 actor；纯查询，供封包入口做第一道防线。
func is_lan_proxy_actor_authorized(peer_id: int, actor_id: int) -> bool
```

- **方向性**：`MatchController` → `NetworkGateway`，与既有 `get_peer_id_for_player()`（控制器读网关）方向相反，因此网关**不得**持有任何规则语义，只保存一个 `peer_id -> {actor_id: true}` 集合。这保证 R8 不引入新的反向依赖。
- 授权表在 `begin_turn_input_delegation()` / `end_turn_input_delegation()` 内**重建后整体下发**，禁止其他写点（RK6 的唯一防线）。
- 断线时网关清空该 peer 的授权项；重连由控制器重新下发。

#### 2.6.3 网关封包入口的放宽（`scripts/network/network_gateway.gd:1155-1160`）

现状：`int(payload.get("actor_id", -1)) != assigned_player_id` → 直接拒绝。

改为：`!= assigned_player_id` **且** `not is_lan_proxy_actor_authorized(sender_peer_id, actor_id)` → 拒绝。拒绝原因文本保持不变（"网络操作玩家与当前连接绑定不一致。"），避免客户端旧版本解析失败。

#### 2.6.4 房主侧授权复核（第二道防线，规则语义在这里）

新增私有函数：

```gdscript
## 返回该网络动作是否由「actor 的合法输入提供者」所对应的 peer 发出。
func _is_lan_proxy_submission_authorized(action: PlayerAction) -> bool
```

- 落点：`scripts/core/match_controller.gd`（与 `_is_auto_management_change_authorized` 同区）。
- 判定：`incoming_peer_id <= SERVER_PEER_ID`（房主本机）→ `action.actor_id` 必须等于 `_bound_local_player_id()`；
  否则先按 `get_remote_player_assignments()` 反查发送者稳定玩家 ID，反查失败（peer 已被替换或断开）直接放行；
  最后要求 `_resolve_turn_input_submitter(action.actor_id) == sender_player_id`。
- **该判定同时承担两件事**：① 代理授权正确性；② **回合操控的输入锁定**——被操控者的操作只能由操控者提供，
  被操控者本人以自己身份上行会被这里拒绝。因此房主上不再需要额外一条锁定分支（离线侧的锁定由
  `_is_authorized_turn_input_caller()` 在**界面提交入口**负责）。
- **必须排除内部 AI 提交**：控制器内部 AI 没有 peer，若对它也做 peer 复核，会把 AI 的选将与出牌全部误判为越权。
- **必须校验发送者仍在当前映射中**：命令回流信号可能在同一帧内进一步触发房主本机的动作（例如房主收到客人提交后
  立即自行重开新局），此时网关的「当前发送者」仍停留在此前那个 peer 上；不校验就会把房主本机动作判成该 peer 越权。
- **两道防线的分工**：网关只回答「这个 peer 有没有被登记为任何 actor 的代理」（防止伪造封包越权）；
  控制器回答「这个 peer 是不是**这个** actor 的合法输入提供者」。网关放行但控制器拒绝时走既有 `action_rejected` 回传。

#### 2.6.5 客户端侧放行（`scripts/core/match_controller.gd:1866` 与 `:15561`）

- `:1866`：`action.actor_id != local_human_player_id` 时，若 `action.actor_id` 在本机最近一次收到的 `turn_input_controlled_actor_ids` 中，则放行上行；否则沿用既有拒绝文本。
- `_is_authorized_turn_input_caller(actor_id, submitter_player_id)`：**输入锁定**，作用域严格限定于**局域网客户端会话**
  （只有客户端存在「本机绑定身份 vs 本机当前操作对象」的分歧）。离线与房主会话一律返回 `true`，
  因为这两侧原本就允许技能链与 AI 代其它座位提交选择（例如濒死救援），额外收紧会破坏既有正式路径。
- `:15561`：`chooser_id != local_human_player_id` 时，若 `chooser_id` 在同一授权列表中，则放行并发出 `card_choice_requested`；否则仍静默丢弃（既有行为）。
- 客户端授权列表来源：`_on_network_snapshot_received()`（`:15542`）读取快照顶层字段并缓存到成员 `_lan_proxy_actor_ids`。**只读缓存，不写任何规则状态**。
- **发送者上下文的清理边界**：`_emit_state()` 首行调用 `network_gateway.clear_current_incoming_peer()`。
  一旦进入状态广播，后续动作都视为本机界面产生，不再继承上一个远端客人的 peer 身份。

#### 2.6.6 定向私有快照授权（`scripts/core/match_controller.gd:16439-16460`）

- 既有循环对每个远端 peer 生成 `state.to_dict(viewer_id, false)`。
- 新增：循环内取该 `viewer_id` 的授权 actor 列表；对列表中每个 `actor_id`，额外生成 `state.to_dict(actor_id, false)` 并**定向**发给同一 peer。
- 客户端表现口径：`turn_input_controlled_actor_ids` 里的 actor 是被操控者；客户端把它当作「当前应当被操作的角色」，其私有快照（手牌、技能栏）用于叠加显示。客户端**不**用它替换 `local_human_player_id`——身份绑定只用于「我是谁」，代理列表用于「我在替谁操作」。
- 旧客户端兼容：缺少该字段时按空列表处理，表现为「只能操作自己」，与改动前一致。
- 防泄漏：授权列表为空时**不生成任何额外快照**，逐 peer 的输出与改动前逐字节等价（AC12b 断言）。

#### 2.6.7 掉线 / 重连（R8.5）

| 事件 | 落点 | 处理 |
|---|---|---|
| 操控者掉线 | `_on_lan_match_peer_disconnected`（`:15721`） | 清除以其为操控者的全部登记（复用 R3 的扫描清除）；网关清空该 peer 授权项 |
| 被操控者掉线 | 同上 | 清除其作为被操控者的登记 |
| 操控者重连 | `_on_lan_match_peer_reconnected`（`:15736`） | **只**重新下发授权表（此时通常为空）；**不**恢复登记，避免过期授权代理提交 |
| 对局结束 / 重开 | 既有清理点 | 调用 `end_turn_input_delegation(-1)` 清全场并清空网关授权表 |

#### 2.6.8 授权条件无法满足时的兜底（R8.6）

`begin_turn_input_delegation` 在 LAN 下若遇下列任一情形，**必须**记录 `TURN_INPUT_DELEGATE_LAN_REASON` 并回退为基础 AI 代打（注册基础 AI），**不得**静默失效：

- 操控者无有效 peer 映射（`get_peer_id_for_player(controller) <= SERVER_PEER_ID` 且操控者不是房主本机）。
- 网关拒绝或无法注册授权项。

规则事实（`turn_input_delegate_id`）在该兜底路径下**仍然写入**（被操控者的本回合确实由该操控者负责），但输入来源降级为 AI——与 K1 的旧备选语义等价，只作为异常兜底而非默认路径。

---

## 三、分层落点与依赖方向

严格保持仓库的五层单向依赖（`docs/架构说明.md`）：

```
scripts/data/player_state.gd          ← 唯一规则事实（R1）        【状态层】
        ↑ 读写只能经控制器端口
scripts/core/match_controller.gd      ← 端口、代理、锁定、视角、到期（R2-R10）【规则/运行时层】
        ↑ 只读快照
scripts/ui/match_table.gd             ← 零改动（已跟随 local_human_player_id）
scripts/ai/ai_coordinator.gd          ← 复用既有 register_basic_ai / unregister_ai
```

- **不新增** `game_data/` 内容文件。本任务不产生任何卡牌、技能或武将。
- **不新增** 事件时机名。到期复用既有 `phaseAfter`（`scripts/core/rule_timing_catalog.gd:16`；派发 `scripts/core/match_controller.gd:13669-13682`），不往 `RuleTimingCatalog` 加名字。
- **不修改** `StarringRoleService`。本机制不认识「主演」，两者只通过调用方（后续卡牌）组合。
- **不修改** `network_gateway` 或逐观察者快照裁剪逻辑（R8 明确 LAN 不扩展）。

---

## 四、数据流

### 4.1 登记（`begin_turn_input_delegation`）

```
调用方（后续卡牌【言灵】）
  │ begin_turn_input_delegation(controlled, controller)
  ▼
校验 5 条前置条件（R2.1–R2.4）——任一失败 → return false，零副作用
  │
  ├─ LAN 模式？ → 走 R8 降级分支：
  │     记录 TURN_INPUT_DELEGATE_LAN_REASON 诊断
  │     写入 turn_input_delegate_id（规则事实仍成立）
  │     确保被操控者的基础 AI 处于注册状态（输入由 AI 提供）
  │     不做任何视角切换、不放开代理提交
  │     → return true
  │
  └─ 离线模式：
        顶替：清除同一被操控者的旧操控者登记（幂等：同一对 → 直接 return true）
        写入 controlled.turn_input_delegate_id = controller
        按「操控者性质」同步被操控者的基础 AI 注册状态（见 4.3）
        若操控者是本机真人 → 走 4.4 视角接管
        广播快照（_emit_state）
```

### 4.2 代理提交（R4）

```
操控者提交 action(actor_id = 被操控者, type = use_card/end_play/...)
  ▼
submit_action()
  ├─ 建立/规范化 action
  ├─ _is_turn_input_locked(action.actor_id)?
  │     初始提交者 ≠ _resolve_turn_input_submitter(action.actor_id) → 拒绝（R6）
  ├─ 代理放行：提交者 == _resolve_turn_input_submitter(action.actor_id) → 跳过「行动者不是当前回合玩家」拒绝
  └─ 其余规则校验（牌合法性、阶段、次数）完全沿用既有路径，不因操控而放宽
```

> 关键原则：**操控只改变「谁提供输入」，不改变「什么输入合法」**。目标、距离、次数、响应全部走原有校验，避免出现第二套合法性口径。

### 4.3 被操控者基础 AI 的注册状态（R10）

规则：**被操控者的基础 AI 注册状态跟随操控者的性质**。

| 操控者性质 | 被操控者的基础 AI | 理由 |
|---|---|---|
| 本机真人（离线） | **注销** | 由真人代替其操作；同时注册会造成真人 + AI 抢同一 `actor_id` |
| 局域网对局中的在线真人座位 | **不改动（保持未注册）** | 该座位自己的客户端就是输入通道；注册 AI 会与真人争抢同一 `actor_id`，表现为真人提交被判越权且整局停滞 |
| AI 座位 / 座位当前无人认领 | **注册** | 由该 AI 提供输入，确保回合不会无人推进 |
| 局域网显式降级（授权通道不可用） | **注册，并让出该座位的真人输入通道** | 规则事实仍由登记表达，但既然代理通道不成立，就必须由 AI 推进该回合 |

复用既有入口，不新增 AI 机制：`ai_coordinator.unregister_ai(player_id)` / `register_basic_ai(player_id)`（`scripts/ai/ai_coordinator.gd:17,22`）。

### 4.4 离线第一视角接管与归还（R7）

```
_emit_state()
  └─ _prepare_offline_controlled_view(explicit_player_id)   ← 既有，:16465
        └─ 新增前置分支：_resolve_delegated_viewer_id()
             被操控者 = state.current_player_id
             其 turn_input_delegate_id >= 0 且操控者是本机真人？
               → 第一视角目标 = 被操控者（操控者要替他打）
             否则 → 落入既有「控制所有角色 / 待办选择者 / 当前回合角色」链
```

- **优先级**：操控登记（规则事实）**高于** `_control_all_characters_enabled`（本地设置）。因此 R7 不依赖「控制所有角色」开关；开关关闭时操控仍然生效。两者同时成立时也只有一个第一视角，不会冲突。
- **切换原子性**：仍只经 `_set_offline_manual_control_player()`。切换后**同一帧**调用 `_republish_manual_player_choice(local_human_player_id)`（`scripts/core/match_controller.gd:16533-16540`），否则会重现 `docs/游戏机制与玩法内容.md:1214` 记录的「无人可答」悬停。
- **归还**：操控登记被清除时（4.5），重新解析第一视角——回落到操控者（若其是本机真人）或 `_primary_offline_human_player_id`（`:344`），并照抄 `:16526-16532` 的收尾序列：

```
_ai_drive_token += 1
_scheduled_ai_drive_token = -1
_scheduled_ai_choice_request_id = -1
_redrive_pending_negation_ai_tasks()
_republish_manual_player_choice(local_human_player_id)
_emit_state()
_ensure_ai_progress_after_resolution()
```

### 4.5 到期与清理（R3）

清理入口统一为一个私有函数，**登记清除与视角归还同处完成**：

```gdscript
## 清除指定被操控者的操控登记，并在需要时归还第一视角。
## turn_player_id / turn_number 用于跨回合安全匹配；传 -1 表示无条件清除。
func _clear_turn_input_delegation(controlled_player_id: int, turn_player_id: int = -1, turn_number: int = -1) -> bool
```

| 触发源 | 落点 | 匹配条件 |
|---|---|---|
| 被操控者本回合结束 | `phaseAfter` 派发处（`scripts/core/match_controller.gd:13669-13682`）或回合收尾尾部 | 登记时记录的 `turn_player_id` + `turn_number` **同时**成立（同 `game_data/skills/wansi.gd` 的双重匹配口径） |
| 被操控者死亡 / 离场 | 死亡流程与离场流程的既有清理位置（与 `clear_starring`、`clear_marks_for_dead_player` 同处） | 无条件清除该被操控者 |
| 操控者死亡 / 离场 | 同上 | 扫描清除全部 `turn_input_delegate_id == 操控者` 的登记 |
| 显式撤销 | `end_turn_input_delegation()` | 传 `-1` 清全场，否则只清指定者 |

**登记元数据**：为了做「回合角色 + 回合号」双重匹配与死亡清理，控制器另存一份**非权威**索引（权威事实仍是 `PlayerState.turn_input_delegate_id`）：

```gdscript
## 操控登记的回合归属索引；键为被操控者 player_id，值为 {turn_player_id, turn_number}。
## 只用于跨回合安全匹配；权威事实仍在 PlayerState.turn_input_delegate_id，两者不得互换角色。
var _turn_input_delegation_turns: Dictionary = {}
```

- 该索引**不进快照、不进存档**：它只是因为「字段本身无法表达是哪个回合登记的」而存在的过程性匹配数据（性质同 `_extra_turn_queue`，`scripts/core/match_controller.gd:601`）。
- 存档恢复后若索引为空，则以「当前回合结束时无条件清除该被操控者登记」为安全回退——只可能提前一轮到期，不会产生永久残留（在 `design` 中显式记录该取舍）。
- **翻面被跳过的回合**不派发 `phaseAfter`（`docs/内容制作指南.md:1851`），因此该情形下登记**不由该回合到期**，沿用安全回退由下一个真实回合结束清除（K5）。

### 4.6 局域网代理提交全链路（R8）

```
操控者客户端（local_human_player_id = 操控者）
  │ 提交 action(actor_id = 被操控者)
  ▼
_match_controller.submit_action() :1866
  └─ actor_id != local_human_player_id?
       ├─ 在 _lan_proxy_actor_ids 中 → 放行上行
       └─ 不在 → 既有拒绝文本
  ▼
network_gateway.send_command(action)
  ▼
房主 network_gateway :1155
  ├─ actor_id == 连接绑定的 assigned_player_id？ → 放行（原路径）
  ├─ is_lan_proxy_actor_authorized(sender_peer, actor_id)？ → 放行（新增）
  └─ 否则 → 回 action_rejected（文本不变）
  ▼
房主 MatchController.submit_action()
  ├─ _is_lan_proxy_submission_authorized(action)？ → 否则 _reject
  ├─ _is_turn_input_locked(action.actor_id) 与代理放行（R4/R6，同离线）
  └─ 其余规则校验完全沿用既有路径
```

### 4.7 局域网定向快照（R8.4）

```
房主 _emit_state() :16439
  for peer_id, viewer_id in get_remote_player_assignments():
      remote_snapshot = state.to_dict(viewer_id, false)     ← 既有
      remote_snapshot["turn_input_controlled_actor_ids"] = 观察者的授权 actor 列表
      send_snapshot_to_peer(remote_snapshot, peer_id)
      for actor_id in 授权列表:                              ← 新增
          delegated_snapshot = state.to_dict(actor_id, false)
          delegated_snapshot["turn_input_delegated_viewer_id"] = actor_id
          send_snapshot_to_peer(delegated_snapshot, peer_id)
```

- 授权列表为空时**不进入**新增分支，输出与改动前逐字节等价。
- 被操控者本人的客户端也收到 `turn_input_controlled_actor_ids`（**不含**自己，因为它的 `turn_input_delegate_id` 指向操控者而非它自己），因此被操控者界面不会出现任何操作入口——由 R6 的锁定判定与空授权列表共同保证。

### 4.8 局域网登记建立与授权下发（`begin_turn_input_delegation`）

```
begin_turn_input_delegation(controlled, controller)
  ├─ 五条前置校验（R2.1–R2.4）
  ├─ LAN 且 controller 是房主本机
  │     → 登记写入；授权表无变化（房主本机不需要 peer 授权）
  ├─ LAN 且 controller 是远端真人
  │     → peer = get_peer_id_for_player(controller)
  │       无效（<=SERVER_PEER_ID）→ 记录 LAN_REASON + 注册基础 AI + return true
  │       有效 → 登记写入；gateway.set_lan_proxy_actor_ids(peer, 该 peer 的全部被授权 actor)
  └─ 离线 → 按 §4.1
  ▼
_emit_state()   ← 授权列表随快照下发到操控者与被操控者两侧
```

### 4.9 局域网清理（`_clear_turn_input_delegation`）

登记清除后**同一处**完成三件事，缺一即会产生「授权残留」缺陷：

1. 清 `PlayerState.turn_input_delegate_id` 与 `_turn_input_delegation_turns` 索引；
2. 对受影响 peer 重新调用 `set_lan_proxy_actor_ids(peer, 该 peer 的剩余授权 actor)`（可能为空数组 → 网关删除该 peer 项）；
3. 离线才需要归还第一视角；LAN 只需要 `_emit_state()` 让两侧客户端的授权列表刷新。

---

## 五、与既有机制的关系（边界表）

| 机制 | 关系 | 约束 |
|---|---|---|
| 「控制所有角色」（`_control_all_characters_enabled`） | **复用其视角链路，语义完全独立** | 本机制不读该设置即可生效；操控登记优先级更高；不动其设置项、不隐藏它 |
| 「托管」`auto_managed` | **禁止复用** | 语义冲突（AI 代打 vs 真人代打）；本机制走独立锁定判定 |
| 「主演」`StarringRoleService` | **完全解耦** | 本机制不查询、不写入主演；由后续卡牌在判定为梅花时组合两者 |
| 停机看门狗 `perform_stall_self_repair` | **必须兼容** | 被操控座位在 R5 同步后仍算「可作答人类」，不会被强转托管 |
| 回放 `MatchReplayRecorder` | **自动兼容** | 字段在公开快照里，回放重演读同一份权威答案；`turn_input_controlled_actor_ids` 属网络授权字段，**不进回放**（回放读 `turn_input_delegate_id` 即可复现操控事实） |
| 权威存档（过关斩将） | **自动兼容** | 字段在 `to_dict(viewer, true)` / `from_dict` 往返；`_turn_input_delegation_turns` 不进存档，按安全回退处理 |
| 局域网掉线托管 `auto_managed` | **并存但不重叠** | 操控者掉线时先清登记（本机制），随后由既有掉线托管接管该座位；两者不会同时为同一 actor 提供输入 |
| 局域网网关授权表 | **新增，方向为控制器 → 网关** | 网关只保存 `peer → {actor}` 集合，零规则语义；不引入反向依赖 |

---

## 六、兼容性与迁移

| 面 | 影响 | 处理 |
|---|---|---|
| 存档格式 | 新增一个 `int` 字段（`turn_input_delegate_id`） | 旧存档缺键 → 默认 `-1`（无登记），语义安全；`from_dict` 用 `int(dict.get("turn_input_delegate_id", -1))` |
| 快照格式 | 新增一个公开 `int` 字段 + 一个按观察者裁剪的 `Array[int]` 字段 | 纯增量；客户端旧版本缺字段时按 `-1` / 空数组处理不报错 |
| 网络 | **新增代理提交授权与定向私有快照**（R8） | 协议版本号**不**提升：新字段为纯增量，旧客户端表现为「只能操作自己」（与改动前一致）；封包 message_type 集合不变 |
| 事件时机目录 | **无变化** | 复用既有 `phaseAfter`，不加新时机名 |
| 内容注册表 | **无变化** | 不新增 `game_data/` 文件；`GameDatabase.validation_errors` 不受影响 |
| 既有技能 / 卡牌 | **无行为变化** | 字段默认为 `-1`，`_resolve_turn_input_submitter()` 返回本人，三处权限判定与网关授权查询全部退化为原有行为 |

### 回滚

- 代码回滚：单独 revert 本次提交即可，无需数据迁移（新字段对旧代码是未知键，序列化时不读取）。
- 功能回滚：不调用 `begin_turn_input_delegation()` 即等于机制不存在——没有内容层调用方时该机制**完全静默**（没有任何自动触发点）。
- 分级回滚：若只有 UI 出问题，可只回滚 `_prepare_offline_controlled_view` 的视角分支，规则事实仍可独立工作与断言。

---

## 七、权衡与已否决方案

| 方案 | 否决原因 |
|---|---|
| 把操控状态只放控制器内存 | 不进快照/存档/回放；无法断言；回放视角跳变（对比「主演」的既有口径） |
| 复用 `auto_managed` 实现「被操控者不可操作」 | `auto_managed` 会注册基础 AI，造成真人与 AI 抢 `actor_id`；且它同时表达「AI 代打」，与本机制叠加后语义不可分 |
| 允许操控者与被操控者**同时**开放提交（字面理解「同时操控两个角色」） | 与 `state.current_player_id` 单值 + 六阶段唯一游标模型冲突，需要重写阶段模型；收益无法证明（同一时刻只有一名角色有可执行动作） |
| 在 `submit_action` 里把 `actor_id` 直接改写成操控者再走原路径 | 会让日志、伤害来源、用牌归属全部记到操控者头上，破坏「谁在使用牌」的权威事实；本设计只改**谁提供输入**，不改 actor |
| 为操控新增一个独立的第一视角接口 | 与「控制所有角色」形成两套视角切换实现，必然出现失同步与两套归还逻辑 |
| 为操控新增 `RuleTimingCatalog` 时机名 | 到期只需复用 `phaseAfter`；新增时机名会扩大公开契约而无对应收益 |
| LAN 下把客户端 `local_human_player_id` 替换成被操控者（照抄离线做法） | `local_human_player_id` 在 LAN 是**协议身份绑定**（`:1866` 的第一道防线、逐 peer 快照的观察者键、`get_peer_id_for_player` 反查依据）。替换它会同时破坏授权校验与快照路由，等于让客户端自称成别人 |
| 让网关自己根据规则判断「谁能代理谁」 | 网关需要读 `GameState` 与操控登记，构成反向依赖（网络层不得改写/依赖规则状态） |
| 提高 `PROTOCOL_VERSION` 以强制双方升级 | 新字段是纯增量、旧行为可安全退化；提升版本号只会让「一人未升级则整房无法开局」，收益为负 |
| 为 LAN 授权新增独立快照 message_type | 复用既有 `snapshot` 定向发送即可；新增类型需同步改客户端分发白名单，收益为负 |

---

## 八、验证策略

1. **专项**：新增 `tests/turn_control_mechanism_test.gd` + `.tscn`，逐条覆盖 AC1–AC13 与 AC12b/AC12c。测试必须按 `docs/界面与交互.md`「自动化测试设置隔离」保存并恢复 `GameSettings`（尤其 `control_all_characters_enabled`），并使用独占的 `user://*_test_settings.cfg`。
2. **局域网专项**：新增 `tests/lan_turn_control_test.gd` + `.tscn`，覆盖 R8.1–R8.6。可纯服务端构造（不起第二个进程）：直接装配 `MatchController` + `NetworkGateway(Mode.LAN)`，用 `_peer_to_player_id` 注入 peer→player 映射，然后在 `_current_incoming_peer_id` 作用域内提交动作。必须覆盖：①操控者 peer 代提交被接受；②第三方 peer 代同一 actor 提交被拒；③被操控者本人代自己提交被拒；④未授权 peer 快照与基线等价；⑤授权 peer 收到被操控者权重快照；⑥掉线即清登记；⑦授权条件缺失时记录 `TURN_INPUT_DELEGATE_LAN_REASON`。
3. **回归**：`tests/control_all_characters_test.tscn`（视角链路未被破坏）、`tests/zhuyan_zhili_test.tscn`（主演未被影响）、`tests/smoke_test.tscn`（数据库校验与开局）、`tests/gameplay_regression_test.tscn`、`tests/phase_progression_test.tscn`（阶段与回合尾时机）、`tests/lan_network_test.tscn` + `tests/lan_match_flow_test.tscn`（LAN 协议未被破坏；需允许本机 UDP 回环）。
4. **静态**：`GameDatabase.validation_errors` 必须为空。
5. **文档一致性**：`docs/` 中出现的端口名、字段名与本节 2.1–2.6 必须逐字一致。

运行方式见 `README.md` 的测试说明（每个 `tests/*.tscn` 可单独运行）。
