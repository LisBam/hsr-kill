# 技术设计：操控者同时操作本体与被操控者

对应需求：[`prd.md`](./prd.md)

---

## 一、设计目标与边界

**一句话**：把「操控期间第一视角 = 被操控者」这条**常量**改成「操控期间第一视角 = {操控者, 被操控者} 中当前真正需要输入的那一个」这条**解析**，
并让离线与局域网共用同一个解析入口。

三条硬约束：

1. **不新增状态字段**。`PlayerState.turn_input_delegate_id` 仍是唯一权威事实，本任务只改「谁在看界面」。
2. **不新增视角切换实现**。离线仍只经 `_set_offline_manual_control_player()`；局域网仍只经快照顶层 `turn_input_delegated_viewer_id`。
3. **不改输入锁定与代理提交**。`_resolve_turn_input_submitter()` / `_is_authorized_turn_input_caller()` / `_is_lan_proxy_submission_authorized()` 一行不动。

之所以能做到，是因为仓库已有两处解耦（已由调研证实）：

- **规则归属 ≠ 操作归属 ≠ 视角归属**：`state.current_player_id`（回合）、`turn_input_delegate_id`（谁提供输入）、`local_human_player_id`（界面在看谁）三者本来就独立。
- **「控制所有角色」已经实现了「谁最需要输入」的完整排序链**（`scripts/core/match_controller.gd:18066-18084`），本任务把它提取成共用函数即可。

---

## 二、缺陷根因

```
离线：_prepare_offline_controlled_view(explicit = A)
        └─ 回合操控分支直接 return _set_offline_manual_control_player(B)   ← explicit 被完全忽略
局域网：_emit_state() 逐 peer 循环
        ├─ send(普通快照 viewer = A)                    → 客户端 local = A
        └─ send(代理快照 viewer = B, delegated_viewer=B) → 客户端 local = B（后发者胜）
```

两条通道都表现为：**任何针对操控者的待办请求都无法把第一视角交还给操控者**。
界面侧 `match_table.gd:3955` 要求 `chooser_id == local_human_player_id` 才建立询问窗口，因此该窗口被静默丢弃，
被操控者的回合停在该响应窗口上（既无真人输入也无 AI 输入）。

> 归档任务的 `design.md` §七 曾把「操控者与被操控者同时开放提交」列为**已否决方案**，理由是「需要重写阶段模型」。
> 本设计**不推翻该结论**：同一时刻仍然只有一名角色拥有可执行动作（六阶段唯一游标不变），
> 本任务只让**视角**能跟随那名角色的实际归属在两人之间移动。因此被否决的是「双人同时出牌」，本任务做的是「双人共用一名真人操作者」。

---

## 三、命名与契约（实现后 `docs/` 必须与本节逐字对齐）

### 3.1 新增私有函数（全部在 `MatchController`，均为纯查询，零副作用）

```gdscript
## 返回当前“最需要玩家输入”的角色 player_id 提示；无任何待办时回落到当前回合角色。
## 优先级与「控制所有角色」既有链路逐条一致：显式请求 → 机缘选择者 → 普通待办选牌 → 并行无懈 → 当前回合角色。
## 本函数只回答“谁最需要输入”，不判断该角色是否由本机操作；归属过滤由调用方完成。
func _resolve_pending_operator_hint(explicit_player_id: int = -1) -> int

## 返回指定操控者在“同时操作自己与被操控者”语义下当前真正需要提供输入的角色 ID。
## 返回值：当前操作目标 player_id；该操控者没有任何操控登记时返回 -1（表示不需要代理视角）。
func _resolve_delegated_operator_id(controller_player_id: int, explicit_player_id: int = -1) -> int

## 返回指定角色当前是否“由本机真人代打”（其操控者就是本机真人）。纯查询。
func _is_delegated_to_local_human(player_id: int) -> bool

## 返回指定角色当前是否可作为第一视角目标（存在、存活、未离场）。纯查询。
func _is_viewable_actor(player_id: int) -> bool
```

### 3.2 签名变更（既有函数）

```gdscript
## 变更前：func _resolve_delegated_viewer_id() -> int
## 变更后：
func _resolve_delegated_viewer_id(explicit_player_id: int = -1) -> int
```

`_prepare_offline_controlled_view()` 与 `_set_offline_manual_control_player()` 签名不变，只改内部判定。

### 3.3 无新增字段、无新增常量、无协议变更

| 面 | 变更 |
|---|---|
| `PlayerState` / `GameState` | 无 |
| 快照字段 | 无新增；`turn_input_delegated_viewer_id` 的**取值语义**由「恒为被操控者」变为「当前操作者」 |
| 存档 / 回放 | 无 |
| 网络 message_type / `PROTOCOL_VERSION` | 无 |
| `RuleTimingCatalog` | 无 |
| `GameSettings` | 无 |

---

## 四、数据流

### 4.1 离线（`_prepare_offline_controlled_view`）

```
_prepare_offline_controlled_view(explicit_player_id)
  ├─ 非离线 / 开局配置阶段 → false（不变）
  ├─ requested_operator_id = _resolve_pending_operator_hint(explicit_player_id)     ← 新增：唯一排序
  ├─ delegated_viewer_id = _resolve_delegated_viewer_id(requested_operator_id)      ← 新增：传入提示
  │     ├─ 非离线 → -1
  │     ├─ 当前回合角色无登记，或登记的操控者 ≠ 本机真人影子身份 → -1
  │     └─ 否则 → _resolve_delegated_operator_id(本机真人, requested_operator_id)
  │            ├─ 无被操控者 → -1
  │            ├─ 提示 == 操控者本人 且 操控者可显示 → 操控者        ← 本任务的核心修复
  │            ├─ 提示 ∈ 被操控者集合 且 可显示 → 该被操控者
  │            └─ 否则 → 首个可显示的被操控者（本回合归属者）
  ├─ delegated_viewer_id >= 0 → 记录接管影子值（仅首帧）→ _set_offline_manual_control_player(目标)
  └─ 否则落入既有「控制所有角色」分支（复用同一个 requested_operator_id，删除重复排序代码）
```

**为什么提示落在第三人身上要回落到被操控者**：第三人（例如另一名 AI）的输入由它自己的基础 AI 提供，
把第一视角交给它会同时抢走被操控者的操作入口；而操控者的规则输入锁定也不允许第三人代打。

### 4.2 离线：被操控者的输入来源（R2）

```
_set_offline_manual_control_player(target)
  ├─ 若当前接管的非主角色 ≠ target 且 它不是主真人：
  │     变更前：无条件 ai_coordinator.register_basic_ai(它)
  │     变更后：仅当 not _is_delegated_to_local_human(它) 时才注册
  └─ target ≠ 主真人 → ai_coordinator.unregister_ai(target)（不变）
```

```
_sync_controlled_player_input_source(controlled, controller)
  ├─ 变更前：controller == 本机真人 且 not _control_all_characters_enabled → 注销 AI
  └─ 变更后：controller == 本机真人                              → 注销 AI
```

两处合起来保证不变量：**只要登记表明某角色由本机真人操控，它的基础 AI 就必须处于注销状态**，
与「控制所有角色」开关无关；视角在两人之间跳转不会破坏该不变量。

### 4.3 局域网（`_emit_state` 逐 peer 循环）

```
for peer_id, viewer_id in get_remote_player_assignments():
    remote_snapshot = state.to_dict(viewer_id, false) + 授权列表 + 待办清单 + 合法动作
    send(remote_snapshot, peer_id)                                   ← 不变
    delegated_view_target_id = _resolve_delegated_operator_id(viewer_id)   ← 新增
    for controlled_actor_id in controlled_actor_ids:
        if controlled_actor_id != delegated_view_target_id: continue       ← 新增：目标不是它就不发
        发以 controlled_actor_id 为观察者的代理快照（不变）
```

- 目标 = 被操控者（默认情形）→ 与改动前**逐字节等价**。
- 目标 = 操控者本人 → 不发代理快照，客户端 `local_human_player_id` 保持普通快照给出的协议绑定身份（操控者），
  `chooser_id == 操控者` 的响应窗口因此被界面接受；`turn_input_controlled_actor_ids` 照常下发，代提交权限不受影响。
- 同一时刻至多一名被操控者（登记前置条件要求被操控者必须是当前回合角色），因此该循环至多一次迭代。

### 4.4 与「控制所有角色」的关系

| 情形 | 变更前 | 变更后 |
|---|---|---|
| 设置关闭 + 有登记 | 视角锁死被操控者（缺陷） | 视角在 {操控者, 被操控者} 内跟随待办 |
| 设置开启 + 无登记 | 视角跟随全部角色的待办 | 不变 |
| 设置开启 + 有登记 | 视角锁死被操控者（缺陷） | 视角在 {操控者, 被操控者} 内跟随待办；第三人请求由该第三人自己的 AI 作答（与变更前一致，不劣化） |

> 保留「登记优先于设置」的既有语义（`_test_offline_view_takeover_and_return` 依赖它），不交换两个分支的顺序。

---

## 五、分层落点与依赖方向

```
scripts/data/player_state.gd          ← 零改动（唯一规则事实不变）
scripts/core/match_controller.gd      ← 四个新私有查询 + 两处既有函数内部改造 + _emit_state 一处循环条件
scripts/ui/match_table.gd             ← 零改动（已全量跟随 local_human_player_id）
scripts/network/network_gateway.gd    ← 零改动（授权表与封包入口不动）
```

严格保持五层单向依赖；本任务不引入任何新依赖方向。

---

## 六、兼容性与回滚

| 面 | 影响 | 处理 |
|---|---|---|
| 存档 / 回放 | 无 | 未改任何序列化字段 |
| 网络协议 | 无 | 未新增字段与 message_type；仅 `turn_input_delegated_viewer_id` 的取值可能等于操控者（旧客户端表现为「不发代理快照 = 停在自身视角」，与改动前相比只是少了一次视角改写） |
| 无操控的普通对局 | **零影响** | `_resolve_delegated_operator_id()` 在无登记时返回 `-1`，两条通道都走原有路径 |
| 「控制所有角色」 | 视角链路不变 | 只在「设置开启 + 有登记」的交叉情形下把候选集合从「全部角色」收窄为 {操控者, 被操控者}，与变更前（锁死被操控者）相比只增不减 |

### 回滚

- 代码回滚：单独 revert 本任务提交即可；无数据迁移。
- 分级回滚：只回滚 `_resolve_delegated_viewer_id()` 的提示参数即可退回「锁死被操控者」；`_emit_state` 的循环条件与 `_sync_controlled_player_input_source` 的门禁可独立回滚。

---

## 七、权衡与已否决方案

| 方案 | 否决原因 |
|---|---|
| 在 UI 侧放宽 `chooser_id == local_human_player_id`，让被操控者视角也能显示操控者的请求 | 会让界面同时显示两个角色的询问，且违背「第一视角」语义；局域网客户端还会因快照观察者不同而拿不到候选 |
| 操控期间让 `local_human_player_id` 恒定停在操控者，改为把被操控者的手牌渲染到操控者视角 | 需要第二套「以谁的手牌为准」的状态与渲染分叉，直接违反「第一视角 = 一个字段」的既有解耦 |
| 局域网为「当前操作者」新增独立快照 message_type | 复用既有 `snapshot` 定向发送即可；新增类型需同步改客户端分发白名单，收益为负 |
| 让操控者与被操控者**同时**开放出牌提交 | 与 `state.current_player_id` 单值 + 六阶段唯一游标模型冲突，需要重写阶段模型（沿用归档任务的否决结论） |
| 新增 `PlayerState` 字段记录「当前视角目标」 | 视角是本机表现状态而非规则事实；进快照会污染公开信息面，且与 `local_human_player_id` 形成两份真相 |
| 把 `_resolve_pending_operator_hint()` 的排序复制到局域网路径 | 两份排序必然漂移；必须共用同一函数（R5） |

---

## 八、验证策略

1. **专项（离线）**：扩展 `tests/turn_control_mechanism_test.gd`
   - 新增 `_test_delegated_view_follows_pending_operator()`：覆盖 AC1/AC2/AC3/AC4/AC7。
   - 新增 `_test_controller_responds_as_self_during_delegation()`：照抄 `tests/response_choice_test.gd:83-124` 的「攻击者用【杀】→ 本地玩家出【闪】」构造，覆盖 AC5。
   - 既有 `_test_offline_view_takeover_and_return()` 覆盖 AC6（不得回归）。
2. **专项（局域网）**：扩展 `tests/lan_turn_control_test.gd`
   - 新增 `_test_delegated_snapshot_view_target()`：直接调用 `_resolve_delegated_operator_id()` 与 `_get_controlled_actor_ids_for_controller()`，
     断言「目标 = 被操控者 → 代理快照照常；目标 = 操控者 → 代理快照不发但授权列表不变」，覆盖 AC8/AC9。
3. **回归**：`turn_control_mechanism_test.tscn`、`lan_turn_control_test.tscn`、`control_all_characters_test.tscn`、
   `response_choice_test.tscn`、`kafuka_mechanics_test.tscn`、`smoke_test.tscn`、`gameplay_regression_test.tscn`、`phase_progression_test.tscn`。
4. **静态**：`GameDatabase.validation_errors` 必须为空。
5. **文档一致性**：`docs/` 中出现的函数名与本节 3.1/3.2 必须逐字一致。

运行方式见 `README.md` 的测试说明（每个 `tests/*.tscn` 可单独运行）。
