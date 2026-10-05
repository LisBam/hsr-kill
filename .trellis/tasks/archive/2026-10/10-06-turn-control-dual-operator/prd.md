# 回合操控：操控者同时操作本体与被操控者（第一视角跟随当前待输入者）

> 本任务是 [`10-02-kafuka-new-mechanics`](../10-02-kafuka-new-mechanics/prd.md) 的子任务。
> 它修复的缺陷位于**已归档**子任务 [`10-02-turn-control-mechanism`](../../archive/2026-10/10-02-turn-control-mechanism/prd.md) 的交付物内部，
> 因此本任务**只修「第一视角归属」这一条链路**，不重写回合操控的登记、到期、输入锁定与局域网代理提交协议。

## Goal

让「本回合由 xx 操控」真正实现来源需求原文的完整语义：**操控者是同时操控自己原来的角色和被操控角色的**。

当前实现的缺陷：操控期间第一视角被**无条件锁死在被操控者身上**（离线由 `_prepare_offline_controlled_view()` 的前置分支强制接管，
局域网由房主的定向代理快照强制改写客户端 `local_human_player_id`）。于是当被操控者打向操控者本人时，
要求操控者作答的响应窗口（例如【杀】要求操控者出【闪】）既不会把视角跳回操控者，也不会被界面接受，整个对局在该窗口悬停。

用户价值：把「操控他人回合」从「只能替别人打牌」补全为「替别人打牌的同时仍能以自己身份应对」，使该机制在真实对局中可用。

---

## 来源需求原文（不可变 · 逐字保留）

> 依据 [`项目专属AGENTS.md`](../../../项目专属AGENTS.md) 铁律：以下描述原文的字段、数值、文字表述、标点符号与语句顺序**一律不得改动**。实现必须围绕原文展开。

```
本回合由xx操控：xx替你执行本回合，效果是操控者直接切换至被操控者的第一视角，被操控者不可做任何操作只能看着自己被操控。操控结束时操控者回到原来的角色。操控者是同时操控自己原来的角色和被操控角色的，可以参考设置中的“控制所有角色”。
```

用户补充的缺陷复现（本轮请求原文）：

```
优化“操控”的代码逻辑，在玩家操控其他玩家时，其实际上是同时操控本体以及其他玩家，例如玩家A触发言灵操控玩家B的回合，然后操控玩家B对玩家A使用杀，此时操控的第一视角还要从玩家B跳转到玩家A决定是否使用闪。本质上是额外操控一名角色。可以参考设置中“操控所有角色”所实现的代码
```

---

## 已确认的仓库事实（证据锚点）

| # | 事实 | 证据 |
|---|---|---|
| F1 | 离线第一视角归属的唯一入口是 `_prepare_offline_controlled_view(explicit_player_id)`；回合操控分支排在「控制所有角色」之前并**直接返回**被操控者 | `scripts/core/match_controller.gd:18049,18056-18062` |
| F2 | 被操控者由 `_resolve_delegated_viewer_id()` 解析，**只看当前回合角色**，完全不读 `explicit_player_id`，因此任何针对操控者的请求都无法改变视角 | `scripts/core/match_controller.gd:18096-18116` |
| F3 | 「控制所有角色」分支已经有「显式请求 → 机缘选择者 → 普通待办选牌 → 并行无懈 → 当前回合角色」的完整优先级链，本任务要复用的正是这条链 | `scripts/core/match_controller.gd:18066-18084` |
| F4 | 界面只在 `chooser_id == match_controller.local_human_player_id` 时才建立询问窗口，其余请求被静默丢弃（因此视角不跳 = 该窗口永远无人可答） | `scripts/ui/match_table.gd:3947-3957` |
| F5 | 局域网下客户端 `local_human_player_id` 由快照顶层 `turn_input_delegated_viewer_id` 决定；房主在普通快照之后**总是**再发一份以被操控者为观察者的代理快照，因此视角最终总落在被操控者 | `scripts/core/match_controller.gd:16728-16732,17996-18007` |
| F6 | 局域网客户端的请求放行只看 `chooser_id` 是否等于协议绑定身份或在本机授权列表内，**与视角无关**；视角错位是纯界面层缺陷 | `scripts/core/match_controller.gd:16743-16756` |
| F7 | 操控者的 `local_pending_choice_request_ids` 已经并入其被操控者的待办清单（`_get_pending_choice_request_ids_for_controller`），因此视角跳回操控者后快照不缺待办信息 | `scripts/core/match_controller.gd:18036-18044` |
| F8 | `_set_offline_manual_control_player()` 在「切走的角色不是主真人」时会**无条件为它注册基础 AI**；操控期间在操控者与被操控者之间来回跳视角会因此把被操控者交还给 AI | `scripts/core/match_controller.gd:18120-18136` |
| F9 | 被操控者的输入来源由 `_sync_controlled_player_input_source()` 决定，但它的「注销基础 AI」分支被 `not _control_all_characters_enabled` 额外限制 | `scripts/core/match_controller.gd:17579-17598` |
| F10 | 回合操控的输入锁定与代理解析已经收敛到唯一入口 `_resolve_turn_input_submitter()`，本任务**不需要**新增第二份权限判断 | `scripts/core/match_controller.gd:17424-17437` |
| F11 | 被操控者必然是当前回合角色（登记前置条件），因此同一时刻至多存在一名被操控者，操控者集合恒为 {操控者, 被操控者} 两人 | `scripts/core/match_controller.gd:17344-17345` |
| F12 | 既有专项测试 `tests/response_choice_test.gd` 已给出「攻击者用【杀】→ 本地玩家出【闪】」的完整可复用构造 | `tests/response_choice_test.gd:83-124` |
| F13 | 离线第一视角接管/归还的既有回归断言写在 `_test_offline_view_takeover_and_return()`，本任务必须在同一文件内扩展而非新建平行用例 | `tests/turn_control_mechanism_test.gd:245-279` |

---

## Requirements

### R1 离线：视角跟随「当前真正需要输入的那一个」

回合操控登记生效期间，本机真人同时操作 {操控者, 被操控者} 两人。第一视角必须按与「控制所有角色」**完全相同的优先级链**在这两人之间二选一：

1. 显式请求者（`explicit_player_id`）
2. 机缘选择者（`opportunity_state.stage == "choosing"`）
3. 普通待办选牌 `_pending_card_choice` 的 `chooser_id`
4. 并行无懈 `_pending_negation_choices` 的首个 `chooser_id`
5. 当前回合角色（= 被操控者）

- 提示落在**操控者**身上 → 第一视角切到操控者。
- 提示落在**被操控者**身上或落在集合外的第三人身上 → 第一视角回落到被操控者。
- 集合外第三人**不得**成为操控接管的目标（其输入由自己的 AI 提供）。

### R2 离线：被操控者不得因视角来回跳转被交还给基础 AI

视角在 {操控者, 被操控者} 之间跳转时，**仍由本机真人代打的角色必须始终保持基础 AI 处于注销状态**，否则会出现「真人与 AI 同时向同一 actor 提交」。
该约束与 `_control_all_characters_enabled` 无关：只要登记表明该角色由本机真人操控，就必须注销其基础 AI。

### R3 离线：接管与归还的既有语义不变

- 接管发生的第一帧仍保存本机真人影子值（`_offline_delegated_view_active` / `_offline_delegated_viewer_id`）。
- 登记清除后第一视角仍归还操控者本人，被操控者基础 AI 仍恢复。
- 登记优先级仍高于 `_control_all_characters_enabled`（该设置关闭时操控仍生效）。
- 选将、车轮战抓将、手气卡、AI 调整与 `game_start` 等开局配置阶段**不参与**本接管。

### R4 局域网：代理快照不得把视角钉死在被操控者身上

房主向操控者 peer 下发的快照必须让客户端的第一视角落在「当前操作者」上：

- 当前操作者 = 被操控者 → 与改动前**逐字节等价**（照常下发以被操控者为观察者的代理快照）。
- 当前操作者 = 操控者本人 → 客户端第一视角停在协议绑定的操控者身份上，使 `chooser_id == 操控者` 的响应窗口能被界面接受。
- 授权列表（`turn_input_controlled_actor_ids`）与上行放行判定**不受影响**：操控者始终保留以被操控者 actor 代提交的权限。

### R5 单一解析入口（禁止两份实现）

「当前操作者是谁」必须只有一个解析入口，离线与局域网共用；「最需要输入的角色提示」也必须只有一个排序实现。
禁止在离线与网络两条路径各写一份内联判断（否则必然漂移）。

### R6 不改变规则事实

本任务**不**新增/修改任何 `PlayerState` 字段、不改变回合归属 `state.current_player_id`、不改变阶段推进、不改变输入锁定与代理提交协议、
不新增 `RuleTimingCatalog` 时机名。改动只发生在**第一视角归属**与**被操控者输入来源同步**两处。

### R7 文档同步

必须同步：`docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/架构说明.md`、`docs/界面与交互.md`、`docs/网络通信.md`、`README.md`。

---

## Acceptance Criteria

- [ ] **AC1** 离线：操控登记建立后（`_control_all_characters_enabled` 关闭），第一视角默认落在被操控者。
- [ ] **AC2** 离线：被操控者回合内出现一条 `chooser_id == 操控者` 的待办请求时，`local_human_player_id` 立即变为操控者，且该请求的 `card_choice_requested` 满足 `chooser_id == local_human_player_id`（界面可建立窗口）。
- [ ] **AC3** 离线：该请求结算完毕后（无其他待办），第一视角自动回到被操控者，**不需要**等到操控结束。
- [ ] **AC4** 离线：AC2 的整个过程中 `ai_coordinator.is_ai_controlled(被操控者)` 恒为 `false`（不得被交还给 AI）。
- [ ] **AC5** 离线：端到端复现用户举例——操控者 A 操控 B 的回合，B 对 A 使用【杀】时，`slash_response` 请求的 `chooser_id` 为 A 且第一视角为 A；A 提交【闪】后第一视角回到 B，B 的回合继续推进。
- [ ] **AC6** 离线：操控结束后第一视角回到操控者，被操控者基础 AI 恢复（既有行为不回归）。
- [ ] **AC7** 离线：`_control_all_characters_enabled` 打开时，操控者的待办请求同样能成为第一视角目标（不劣化）。
- [ ] **AC8** 局域网：当前操作者为被操控者时，该 peer 收到的代理快照内容与改动前一致（观察者、`turn_input_delegated_viewer_id`、`local_legal_actions`、`local_pending_choice_request_ids`）。
- [ ] **AC9** 局域网：当前操作者为操控者时，不再下发把视角改写为被操控者的代理快照；`turn_input_controlled_actor_ids` 仍包含被操控者。
- [ ] **AC10** 回归：`tests/turn_control_mechanism_test.tscn`、`tests/lan_turn_control_test.tscn`、`tests/control_all_characters_test.tscn`、`tests/response_choice_test.tscn`、`tests/kafuka_mechanics_test.tscn`、`tests/smoke_test.tscn`、`tests/gameplay_regression_test.tscn`、`tests/phase_progression_test.tscn` 全部 PASS。
- [ ] **AC11** `GameDatabase.validation_errors` 为空，可正常开局。
- [ ] **AC12** R7 列出的六份文档已同步，且端口名/字段名与代码逐字一致。

---

## 全局范围外（本任务不做）

- 不重写回合操控的登记、到期、死亡清理与局域网代理提交协议（已由归档子任务交付且测试覆盖）。
- 不新增「同一时刻两名角色同时开放出牌」的回合模型（六阶段唯一游标模型保持不变）。
- 不修改 `PlayerState` / `GameState` 的任何字段与其序列化。
- 不为本任务新增卡牌、技能、武将或时机名。
- 不修改禁读/禁改路径下的任何文件。
