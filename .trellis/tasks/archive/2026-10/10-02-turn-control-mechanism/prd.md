# 回合操控机制（本回合由xx操控）

父任务：[`10-02-kafuka-new-mechanics`](../10-02-kafuka-new-mechanics/prd.md)

本任务**只做「本回合由xx操控」这一个机制**，不含卡芙卡武将、【言灵】卡牌、【游丝】技能、专属锦囊牌机制与「其他角色不可知」机制。机制本身不认识「主演」——由调用方（后续的卡牌【言灵】）把 `(被操控者, 操控者)` 传进来，保持规则层与内容层解耦。

---

## Goal

建立「回合操控」这一新机制的完整规则与交互能力：**操控者接管被操控者的本回合**，切换到被操控者的第一视角替他执行，被操控者只能旁观且无法操作；操控结束（本回合结束）后操控者回到原来的角色。机制在离线对局完整可用；局域网下按 R8 显式降级。

用户价值：为后续卡牌【言灵】提供可复用的机制底座，并把《崩铁杀》的「操控他人回合」这一新博弈维度做成与「控制所有角色」同源、但受规则约束、可存档可回放的正式能力。

---

## 概念定义（须写入 `docs/内容制作指南.md` 与 `docs/游戏机制与玩法内容.md`）

> 「本回合由xx操控」：xx替你执行本回合，效果是操控者直接切换至被操控者的第一视角，被操控者不可做任何操作只能看着自己被操控。操控结束时操控者回到原来的角色。操控者是同时操控自己原来的角色和被操控角色的，可以参考设置中的「控制所有角色」。

术语（本机制内）：

- **被操控者**（controlled）：本回合的操作被他人代为提供的角色。
- **操控者**（controller / delegate）：替被操控者执行本回合的角色。
- **操控登记**（delegation）：一条「被操控者的本回合由操控者执行」的权威事实。

---

## In Scope

1. 规则层权威状态与端口（登记 / 撤销 / 查询）。
2. 操控到期的唯一时点与清理（回合结束、死亡、离场）。
3. 操作权代理：操控者可以以被操控者的 `actor_id` 提交正式回合动作。
4. 被操控者的输入锁定（独立判定，不复用「托管」）。
5. 离线第一视角接管与归还（复用「控制所有角色」既有链路）。
6. 观察者快照 / 权威存档 / 回放往返。
7. 看门狗与既有 AI 驱动链路的兼容。
8. 文档同步与专项回归测试。

## Out of Scope

- 卡芙卡武将、【言灵】技能、【游丝】技能、卡牌【言灵】。
- 专属锦囊牌机制、「其他角色不可知」机制、牌堆顶置牌端口。
- 任何**新增** AI 决策策略（只允许复用既有的「注销 / 恢复单名基础 AI」链路）。
- LAN 协议版本号提升（新字段为纯增量，旧客户端缺字段按默认值退化）。
- 私有快照改动（不改逐观察者裁剪算法本身，只**新增**授权观察者的定向权重快照）。
- 断线重连语义扩展（登记在掉线时按 R8.5 直接清除，不跨重连存续）。
- 操控的视角切换动画 / 特效 / 专用提示条。
- 被操控者的任何主动解除手段（原文未写）。

---

## Requirements

### R1 规则层权威状态

- 新增公开可序列化字段表达「某角色的本回合由谁操控」。
- 取值：`-1` = 无操控登记（本人操作）；`>= 0` = 该 `player_id` 是本角色的操控者。
- 字段必须是**唯一权威**：不允许在控制器另存一份可能失同步的副本。
- 必须进入：观察者快照（所有观察者可见）、权威存档、AI 快照。
- 证据/落点：`scripts/data/player_state.gd`（`public_marks` 同区）、`docs/内容制作指南.md:4040`（主演字段口径先例）、`docs/内容制作指南.md:2289`。

### R2 登记与撤销端口

`MatchController` 提供以下公开端口，签名固定：

| 端口 | 语义 |
|---|---|
| `begin_turn_input_delegation(controlled_player_id: int, controller_player_id: int) -> bool` | 建立操控登记 |
| `end_turn_input_delegation(controlled_player_id: int = -1) -> bool` | 撤销登记；`-1` = 清除全场全部登记 |
| `get_turn_input_delegate_id(controlled_player_id: int) -> int` | 纯查询，无登记返回 `-1` |
| `is_turn_input_delegated(controlled_player_id: int) -> bool` | 纯查询 |

`begin` 的前置校验（任一不满足即返回 `false` 且**无任何副作用**）：

1. 两名角色均存在、`alive == true`、`out_of_game == false`。
2. `controlled_player_id != controller_player_id`（禁止自环）。
3. 被操控者**是当前回合角色**（`state.current_player_id`）。
4. 操控者本人当前**没有**被他人操控（禁止链式操控）。
5. 与现有登记幂等：重复登记同一 `(被操控者, 操控者)` 返回 `true` 且不产生第二条事实；登记不同操控者时按「唯一操控者」口径顶替（同一被操控者同一时刻至多一名操控者）。

### R3 到期与清理

- **到期主时点**：被操控者**本回合结束**时自动清除登记。落点为回合尾部时机（`phaseAfter`，`scripts/core/match_controller.gd:13669-13682`），不得依赖调用方显式撤销。
- **被操控者死亡 / 离场**：立即清除其登记。
- **操控者死亡 / 离场**：立即清除**以他为操控者**的全部登记（操控回落为被操控者本人）。
- 清理与「第一视角归还」必须**同一处**处理，避免出现「登记已清、视角仍停在别人身上」的悬停。
- 跨回合安全：清理必须同时按「登记的回合角色 + 登记的回合号」匹配，避免无关角色的回合结束误清除别的登记（同 `game_data/skills/wansi.gd` 的双重匹配口径）。
- 翻面被跳过的回合不派发 `phaseAfter`（`docs/内容制作指南.md:1851`），因此该类回合不存在「回合结束」语义，登记在该情形下的处理必须显式定义并覆盖测试（见 K5）。

### R4 操作权代理：提交重定向

- 操控者可以以被操控者的 `actor_id` 提交**正式回合动作**。
- 落点：`submit_action()`（`scripts/core/match_controller.gd:1859`）中 `action.actor_id != state.current_player_id` 的校验分支附近，新增「提交者是否为该 actor 的合法代理」判定。
- 离线口径：提交者必须是本地可作答人类（`local_human_player_id`）；非代理者提交一律沿用既有拒绝路径。
- LAN 口径：代理提交**不开放**（见 R8）。

### R5 合法动作与可作答判定同步

- `get_legal_actions(player_id)`（`scripts/core/match_controller.gd:2221`）：被操控者的动作必须能取到（供操控者与其 AI 判断），且**本人**不再能提交。
- `_is_answerable_human_actor(player_id)`（`scripts/core/match_controller.gd:932`）：被操控者在被操控期间由操控者代表作答，必须返回 `true`，否则停摆看门狗会把该座位判为无人认领并强制转托管（`perform_stall_self_repair`，`scripts/core/match_controller.gd:992`）。
- 三处判定必须共用同一个「代理解析」函数，避免同一条规则出现三份不一致实现。

### R6 被操控者输入锁定

- 被操控者提交任何操作时被拒绝，并给出明确、可读的拒绝原因。
- **不得复用 `auto_managed`**：`auto_managed` 的语义是「AI 代打」，会注册基础 AI 与真人争抢同一 `actor_id`（`scripts/core/match_controller.gd:1895,2109`；`scripts/ai/ai_coordinator.gd:17,22`），与本机制冲突。
- 必须新增**独立**的输入锁定判定（纯查询，不写状态）。
- 被操控者的待办选择窗口不得保持为「本人可提交」状态；关闭窗口的依据仍是 `local_pending_choice_request_ids`（`scripts/core/match_controller.gd:5908`；`docs/界面与交互.md:425`）。

### R7 离线第一视角接管与归还

- 触发条件：离线对局、且操控者是本机真人（`network_gateway.mode == NetworkGateway.Mode.OFFLINE`）。
- 接管：把 `local_human_player_id` 切换到被操控者，界面按被操控者观察者快照重建。UI **不需要新增接口**——`scripts/ui/match_table.gd` 已全量跟随该字段（`:2167,2759,3015,3706,5206`）。
- 被操控者若为本机真人：只能旁观，不能操作（由 R6 保证）。
- **切换当帧**必须刷新 / 重发待办选择（复用 `_republish_manual_player_choice`，`scripts/core/match_controller.gd:16533-16540`），否则会重现「无人可答」的悬停卡死（同类缺陷记录见 `docs/游戏机制与玩法内容.md:1214`）。
- 归还：操控结束后回到操控者；若操控者不可用，回落到 `_primary_offline_human_player_id`（`scripts/core/match_controller.gd:344`）。
- 归还时必须递增 AI 驱动令牌废弃旧 AI 任务，并通过统一续接入口重新安排当前选择或出牌动作（照抄 `scripts/core/match_controller.gd:16526-16532`）。
- 视角切换的唯一落点是既有的 `_set_offline_manual_control_player()`（`scripts/core/match_controller.gd:16497`）——可以泛化，但**不得**另建第二套视角切换实现。

### R8 离线 / 局域网边界（**K1 已改判为完整 LAN 代理提交协议**）

- 离线：接管按 R1–R7，第一视角落在被操控者。
- 局域网：**开放完整代理提交协议**，按 R8.1–R8.6。LAN 客户端的 `local_human_player_id` 恒等于协议绑定的本地玩家（`scripts/core/match_controller.gd:1866`），**不做**客户端第一视角身份替换；操控者改为「以被操控者的 `actor_id` 代其提交」，并在本地界面叠加被操控者的定向私有快照。

#### R8.1 协议新增字段（纯增量，旧客户端缺字段按默认值安全退化）

| 字段 | 位置 | 语义 |
|---|---|---|
| `PlayerState.turn_input_delegate_id` | 公开快照（R1） | 全场可见：谁的本回合由谁操控 |
| `turn_input_controlled_actor_ids` | 快照顶层，**按观察者裁剪** | 该观察者被授权代提交的 `actor_id` 列表；仅当 `turn_input_delegate_id[actor] == 观察者` 时包含该 `actor` |
| `local_legal_actions` 的发放条件 | `scripts/core/match_controller.gd:16452` | 由「`state.current_player_id == viewer_id`」放宽为「`viewer_id` 是当前回合角色的合法提交者」 |

#### R8.2 房主侧授权（安全边界，唯一权威）

- 新增私有 `_is_lan_proxy_submission_authorized(action, sender_peer_id) -> bool`：提交者 peer 必须等于 `get_peer_id_for_player(_resolve_turn_input_submitter(action.actor_id))`。
- 落点在 `scripts/core/match_controller.gd:2183` 同区（与既有 `_is_auto_management_change_authorized` 同口径：优先用真实发送 peer 复核，不用 payload 自报字段）。
- `scripts/network/network_gateway.gd:1158` 的「`actor_id` 必须等于连接绑定的玩家」是**第一道**防线，必须同步放宽为「等于绑定玩家，**或**等于该绑定玩家被授权的代理 actor」——网关只知道 peer→player 映射，因此授权表由控制器在 `begin/end_turn_input_delegation` 时通过新端口下发给网关（`set_lan_proxy_actor_ids(peer_id, actor_ids)`），网关侧只做集合查询，不持有规则语义。

#### R8.3 客户端侧放行

- `scripts/core/match_controller.gd:1866`：`action.actor_id != local_human_player_id` 时必须显式允许「本地玩家是被操控者的操控者」，否则仍走既有拒绝路径（非代理者不可越权）。
- `scripts/core/match_controller.gd:15561`：选择请求的 `chooser_id` 校验同样放宽为「本地玩家本人**或**其被授权代理的 actor」。

#### R8.4 定向快照授权（操控者要能替他打牌）

- `scripts/core/match_controller.gd:16439-16460` 的逐 peer 循环：对「操控者 peer」额外生成**以被操控者为观察者**的私有权重快照（`to_dict(被操控者, false)`），与该 peer 自身的公开快照**分帧定向**发送，客户端按 `turn_input_controlled_actor_ids` 决定叠加显示。
- 未列入授权表的 peer 一律收到与改动前**逐字节等价**的裁剪结果（旧行为不变，防泄漏）。

#### R8.5 断线 / 重连语义

- 操控者掉线：清除该玩家作为操控者的全部登记（R3），被操控者回落到自身（真人不可用则由既有掉线托管链路接管）。
- 被操控者掉线：清除其登记。
- 重连：网关重绑 peer→player 后由控制器**重发授权表**；不自动恢复登记（登记已按上一条清除），避免用过期授权代理提交。

#### R8.6 显式记录与降级兜底

- 若 `begin_turn_input_delegation` 在 LAN 下因**任一授权条件无法满足**（无 peer 映射、网关拒绝注册授权）而失败，必须显式记录 `TURN_INPUT_DELEGATE_LAN_REASON` 并**回退为基础 AI 代打**，不得静默失效。

### R9 快照 / 存档 / 回放往返

- `turn_input_delegate_id` 进入 `PlayerState.to_dict(viewer_id, reveal_private)` 的**公开**部分，因此所有观察者（含 AI 快照）都能看到「谁正在被谁操控」。
- 进入权威存档（`to_dict(viewer, true)`）并在 `from_dict` 中恢复（`scripts/data/player_state.gd`）。
- 回放重演后能得到同一权威答案。

### R10 看门狗与既有 AI 链路兼容

- 被操控角色在操控期间**不得**被 `perform_stall_self_repair` 强制转托管（依赖 R5 同步）。
- 被操控者的基础 AI 必须被临时注销（复用 `ai_coordinator.unregister_ai`），并在操控结束后恢复；禁止出现真人与 AI 同时向同一 `actor_id` 提交。

### R11 文档同步

| 文档 | 必写内容 |
|---|---|
| `docs/内容制作指南.md` | 新增「回合操控（本回合由xx操控）」一节：概念定义、端口签名与返回值、五条前置校验、到期与清理时点、离线/局域网差异、UI 规范、被操控者输入锁定、常见错误 |
| `docs/游戏机制与玩法内容.md` | 新概念完整定义 + 全部具体数值（无随机数、无概率；到期时点、唯一性/互斥规则、禁止链式与自环、被操控者不可操作） |
| `docs/界面与交互.md` | 操控期间的第一视角表现（离线切换观察者 / 局域网叠加被操控者私有快照）、被操控者的旁观表现、操控结束归位 |
| `docs/架构说明.md` | 规则字段位置、与「控制所有角色」的关系与差异、网关授权表的单向依赖方向 |
| `docs/网络通信.md` | LAN 代理提交协议的完整说明：新增字段、授权表下发与撤销、房主授权校验落点、定向私有快照授权、掉线清除语义、旧客户端兼容 |
| `README.md` | 新增专项测试场景入口 |
| `临时反馈文档.md` | 追加「学习反馈摘要」+「Git 提交描述」（分钟级时间戳） |

### R12 专项回归测试

新增 `tests/turn_control_mechanism_test.gd` + `tests/turn_control_mechanism_test.tscn`，覆盖「验收标准」中的每一条。测试必须保存并恢复被它改动的 `GameSettings` 值（同 `docs/界面与交互.md`「自动化测试设置隔离」规范）。

---

## Acceptance Criteria

> 每条都可观察、可断言；括号内为对应需求。

- [ ] AC1 `begin_turn_input_delegation` 对「不存在 / 已死亡 / 已离场 / 自环 / 非当前回合角色 / 操控者本人已被操控」六种输入均返回 `false`，且**不产生任何状态变化**。（R2.1–R2.4）
- [ ] AC2 重复登记同一 `(被操控者, 操控者)` 返回 `true` 且全场登记事实仍只有一条；换一名操控者登记时原登记被顶替，被操控者的 `turn_input_delegate_id` 指向新操控者。（R2.5）
- [ ] AC3 登记后 `get_turn_input_delegate_id()` / `is_turn_input_delegated()` 返回权威答案；无登记时分别为 `-1` / `false`，且纯查询不写状态。（R2）
- [ ] AC4 操控者以被操控者的 `actor_id` 提交 `end_play`（或等价正式回合动作）被接受，回合按被操控者的规则状态推进。（R4）
- [ ] AC5 被操控者本人以自己 `actor_id` 提交同一动作被拒绝，且拒绝原因文本非空。（R6）
- [ ] AC6 `get_legal_actions(被操控者)` 非空，`_is_answerable_human_actor(被操控者)` 在离线操控期间为 `true`；三处判定共用同一代理解析函数（可由代码结构断言）。（R5）
- [ ] AC7 被操控者的本回合走到回合尾后，`is_turn_input_delegated(被操控者)` 变为 `false`，且**无关角色的回合结束不会**清除该登记。（R3）
- [ ] AC8 被操控者在操控期间死亡或离场，登记立即清除；操控者在操控期间死亡或离场，以其为操控者的全部登记立即清除。（R3）
- [ ] AC9 离线操控期间本机第一视角落在被操控者；操控结束后回到操控者（或 `_primary_offline_human_player_id`），且归还当帧待办选择被重新发布（无悬停）。（R7）
- [ ] AC10 离线被操控者若为本机真人，界面按被操控者快照显示完整手牌与技能栏，但其提交被 R6 拒绝。（R6, R7）
- [ ] AC11 `to_dict()` 公开部分包含操控字段；`from_dict(to_dict(viewer, true))` 往返后权威答案不变；回放重演后答案一致。（R9）
- [ ] AC12 局域网模式下：操控者客户端以被操控者的 `actor_id` 提交正式回合动作被房主**接受**；非操控者的第三方 peer 以同一 `actor_id` 提交被**拒绝**；被操控者客户端以自身 `actor_id` 提交被 R6 拒绝。（R8.1–R8.3）
- [ ] AC12b 局域网模式下操控者收到以被操控者为观察者的定向私有快照（含其手牌与技能栏），未获授权的 peer 快照与改动前逐字节等价；`turn_input_controlled_actor_ids` 只出现在被授权观察者的快照中。（R8.1, R8.4）
- [ ] AC12c 局域网模式下操控者或掉线时，相关操控登记立即清除；重连只重发授权表、不自动恢复登记；任一授权条件无法满足时显式记录 `TURN_INPUT_DELEGATE_LAN_REASON` 并回退基础 AI。（R8.5, R8.6）
- [ ] AC13 操控期间被操控者座位不被 `perform_stall_self_repair` 转托管；被操控者的基础 AI 在操控期间处于注销状态、结束后恢复。（R10）
- [ ] AC14 `GameDatabase.validation_errors` 为空，`tests/smoke_test.tscn` 通过（新字段未破坏内容校验与开局）。
- [ ] AC15 `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/界面与交互.md`、`docs/架构说明.md`、`docs/网络通信.md`、`README.md` 已按 R11 同步；`临时反馈文档.md` 已追加。（R11）

---

## 关键决策（默认值已采用，**请在最终规划评审时确认或改判**）

| ID | 决策 | 采用的默认值 | 备选与代价 |
|---|---|---|---|
| K1 | 局域网边界 | **LAN 开放完整代理提交协议**（R8.1–R8.6）：操控者以被操控者 `actor_id` 代提交 + 网关授权表 + 定向私有快照授权 + 掉线清除 | 备选：LAN 降级为基础 AI 代打（工作量小，但 LAN 下「操控」语义消失，被用户否决） |
| K2 | 规则字段落点 | 新增 `PlayerState.turn_input_delegate_id`（公开、可序列化） | 备选：只存控制器内存。代价：不进快照/存档/回放，回放视角跳变且无法断言 |
| K3 | 「同时操控自己原来的角色和被操控角色」的解读 | 操控者**不**失去自己角色的控制权；同一时刻只有一名当前回合角色，因此实际表现为「轮到谁就操控谁」，本机制**不**创建并行双角色同时操作 | 备选：允许两个座位同时开放提交。代价：与六阶段唯一游标、`state.current_player_id` 单值模型冲突，需改阶段模型 |
| K4 | 同一操控者可否同时操控多名被操控者 | **允许**多条并存（不同被操控者）；因同一时刻只有一名当前回合角色，不产生冲突 | 备选：全局唯一操控登记。代价：同回合多张【言灵】场景下相互顶替，语义更弱 |
| K5 | 翻面被跳过的回合 | 该类回合**没有**回合结束语义，因此 `phaseAfter` 不派发、登记不由该回合到期；登记改由被操控者下一个**真实**回合结束到期（并在实现中显式覆盖测试） | 备选：在跳过收尾处额外清理。代价：与「被跳过的回合不存在回合结束」统一规则冲突（`docs/内容制作指南.md:1851`） |
| K6 | 被操控者能否主动解除 | **不能**（原文未写） | — |

---

## Risks

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| RK1 | 视角轮换当帧存在待办选择（`_pending_card_choice` / `_pending_negation_choices` / 机缘 `choosing`） | 悬停卡死，与 `docs/游戏机制与玩法内容.md:1214` 记录的缺陷同类 | 轮换后立即重发 `local_pending_choice_request_ids`；专项测试覆盖「登记时正有待办选择」 |
| RK2 | 被操控者基础 AI 未注销 | 真人与 AI 抢同一 `actor_id`，状态撕裂 | 复用 `unregister_ai` + AI 驱动令牌递增；AC13 断言 |
| RK3 | 看门狗误判被操控座位为无人认领 | 强制转托管，覆盖本机制 | R5 同步 `_is_answerable_human_actor`；AC13 断言 |
| RK4 | 回放视角跳变 | 回放观感变差 | K2 字段进公开快照，回放能读到操控事实 |
| RK5 | 三处权限判定不一致 | 出现「能取到动作却提交被拒」或反向 | 强制共用同一代理解析函数；AC6 断言 |
| RK6 | LAN 网关授权表与控制器登记失同步 | 已撤销的登记仍能代理提交（越权） | 授权表**只**由 `begin/end_turn_input_delegation` 单点写入，禁止其他写点；AC12 断言第三方 peer 被拒 |
| RK7 | 定向私有快照泄漏被操控者手牌给非授权观察者 | 信息泄漏，破坏防作弊 | 授权表为空时逐字节退回既有裁剪路径；AC12b 断言未授权 peer 快照等价 |
| RK8 | 网关只知道 peer→player 映射，无法自行判断规则授权 | 放行过宽 | 网关只做**集合查询**，授权集合由控制器下发；网关零规则语义，避免反向依赖 |

---

## Notes

- 本机制**不认识「主演」**。`(被操控者, 操控者)` 由调用方传入；后续卡牌【言灵】负责在「判定为梅花且场上有主演」时调用本机制。
- 本机制**不新增任何 AI 决策策略**。被操控者回合的 AI 行为完全来自既有基础 AI 与既有的注销/恢复链路。
- 字段与端口的英文命名在 `design.md` 中固定；一旦实现，`docs/` 必须与代码逐字对齐。
- **实现顺序**：本任务完成后，父任务下再依次建「专属锦囊牌机制」「其他角色不可知机制」「卡牌【言灵】」「武将卡芙卡 + 【言灵】【游丝】」子任务。
