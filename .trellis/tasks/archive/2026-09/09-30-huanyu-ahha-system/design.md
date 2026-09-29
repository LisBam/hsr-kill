# 欢愉派系与阿哈时刻体系 — 技术设计

> 需求与验收标准见同目录 `prd.md`。本文只回答「怎么接进现有架构」。

---

## 一、分层落点

沿用项目「静态数据层 → 状态与规则层 → 事件运行时 → 动作协议层 → 适配层」的单向依赖：

| 交付物 | 层 | 落点 | 说明 |
|---|---|---|---|
| 欢愉技静态参数与执行入口 | 内容基类 | `game_data/skill_definition.gd` | 与 `lock` / `leader_skill` / `reincarnation` 同一处扩展 |
| `AhhaMomentSystem` | core | `scripts/core/ahha_moment_system.gd`（新文件） | 单一职责服务组件，与 `scripts/opportunity/` 的机缘系统同构 |
| 回合开始前事件链 | core | `scripts/core/match_controller.gd` | 扩展 `_start_turn` / `continue_after_opportunity` |
| 多张重铸端口 | core | `scripts/core/match_controller.gd` | 紧邻现有 `recast_hand_card`（`:12715`） |
| 欢愉势力 | content | `game_data/factions.json` | 追加一条记录 |
| 武将火花与两个技能 | content | `game_data/characters/huohua.gd`、`game_data/skills/{haoxi,lianxi}.gd` | 自包含内容文件 |

**不新增目录**：`AhhaMomentSystem` 直接放 `scripts/core/`，避免改动 `.trellis/spec/core/index.md` 的目录映射与 `docs/架构说明.md` 的五层清单。

**不新增 `GameState` 字段**：阿哈时刻没有「全体同时选择」这类需要私有快照的交互（这是它与机缘最大的不同——机缘需要向每名玩家定向公开各自的三张候选）。因此阿哈时刻**不进入观察者快照、不进入权威存档**，从而不触碰序列化、联机裁剪与回放通道。

---

## 二、回合开始前的事件链（本设计最关键的改动）

### 现状

```text
_start_turn(player_id)                                   # :10567
  ├─ 轮递增（starts_new_round）
  ├─ opportunity_system.try_trigger_before_turn_start(...)   # :10605
  │     └─ true → return；机缘结算完毕后由控制器回调
  └─ _begin_turn_after_opportunity(player_id, starts_new_round)  # :10607
```

机缘有两条恢复路径会重新走到「建立回合事实」：

- `continue_after_opportunity()`（`:13071`）`before_turn_start` 分支 → `:13088`
- `_start_queued_or_normal_turn()`（`:13011`）额外回合链结束 → `:13037`

### 目标时序

```text
_start_turn
  ├─ 轮递增
  ├─ 机缘判定（allow_opportunity=true）
  └─ 阿哈时刻判定（allow_ahha=true）
        └─ 两者都未触发 / 都已结算完毕 → _begin_turn_after_opportunity
```

### 实现方式

新增一个**私有回合开始前事件链入口**，把「机缘 → 阿哈 → 建立回合事实」收敛到唯一位置，三条现有路径全部改为调用它：

```gdscript
## 回合开始前的统一事件链：机缘选择判定 → 阿哈时刻判定 → 建立回合事实。
## allow_opportunity / allow_ahha 用于区分"首次进入"与"某一环节结算后恢复"，避免重复判定。
func _continue_turn_start_prelude(player_id: int, starts_new_round: bool, allow_opportunity: bool, allow_ahha: bool) -> void
```

| 调用点 | allow_opportunity | allow_ahha |
|---|---|---|
| `_start_turn`（`:10605`，替换原机缘判定块） | `true` | `true` |
| `continue_after_opportunity`（`:13088`） | `false`（机缘刚结束） | `true` |
| `_start_queued_or_normal_turn`（`:13037`，机缘排队期间的额外回合链结束） | `false` | `true` |

**为什么这样收敛**：`allow_opportunity=false` 保留了现有注释「不重复轮递增与回合开始前机缘判定」的既有口径；`allow_ahha=true` 保证阿哈时刻在三条路径上都有且仅有一次机会。原有 `_begin_turn_after_opportunity` 函数名与签名**保持不变**，仅其调用方从 3 处收敛为 1 处。

额外回合（`_current_turn_is_extra`）沿用现有口径：机缘与阿哈时刻**都不在额外回合触发**，由各自 `try_trigger_before_turn_start` 的 `is_extra_turn` 参数拒绝。

---

## 三、`AhhaMomentSystem` 契约

文件：`scripts/core/ahha_moment_system.gd`（`class_name AhhaMomentSystem extends Node`），由 `MatchController._ready()` 动态创建为子节点（照 `opportunity_system` 的 `:680`-`:684` 模式）。

### 公开接口

| 接口 | 语义 |
|---|---|
| `configure(host, state, rng, enabled)` | 每局绑定权威服务并重置全部运行时状态；`enabled=false` 时所有钩子无副作用 |
| `shutdown()` | 释放进行中状态；重开对局、放弃对局、组件退出均可重复调用 |
| `is_active() -> bool` | 当前是否正在执行阿哈时刻 |
| `try_trigger_before_turn_start(turn_context, is_extra_turn) -> bool` | 返回 `true` 表示该角色的回合事实必须等阿哈时刻完整结束 |
| `continue_after_barrier()` | 通用结算栈清空后推进队列（由控制器在既有屏障恢复点调用） |
| `finish_joy_skill_performance(player_id, skill_id) -> bool` | 内容层回报「当前欢愉技已完整结束」，由控制器转发 |
| `build_performance_order(trigger_player_id) -> Array[Dictionary]` | **纯查询**，返回排好序的 `{player_id, skill_id, performance_number}` 列表；供测试与调试断言 |

### 内部状态（全部为可序列化基础类型）

| 字段 | 含义 |
|---|---|
| `_enabled` | 本局是否启用 |
| `_tracked_round_number` / `_triggered_this_round` / `_round_trigger_probability` | 与机缘同构的每轮一次 + 概率锁定 |
| `_performance_queue: Array[Dictionary]` | 待执行序列，每项仅 `player_id`、`skill_id` |
| `_active_index: int` | 当前执行位置；`-1` 表示空闲 |
| `_waiting_for_barrier: bool` | 当前欢愉技是否已产生效果、只等嵌套结算屏障 |
| `_resume_context: Dictionary` | 完成后恢复「未建立回合事实」所需的纯数据上下文 |

**禁止**：把 `SkillDefinition`、`PlayerState`、`Node`、`Callable` 存入任何跨帧字段。

### 触发判定

```text
try_trigger_before_turn_start(turn_context, is_extra_turn)
  ├─ not _enabled / is_extra_turn / 终局 → false
  ├─ 轮号变化 → 按「存活且未离场人数」倒数重算并锁定本轮概率（同机缘口径）
  ├─ 本轮已触发 → false
  ├─ 候选序列为空 → false          # 关键决策：无可执行欢愉技时直接跳过
  │                                 #   不消耗随机数、不写 random_history、不置 _triggered_this_round
  ├─ _rng.randf() 记录进 state.random_history（kind="ahha_moment_trigger_roll"）
  └─ roll < 概率 → 开始执行队列并返回 true
```

**随机数一致性**：`.godot_test_logs` 之外无副作用，但随机值必须写入 `state.random_history`（与 `opportunity_trigger_roll` 同构），保证固定种子可复现、回放可核对。

### 执行与排序

```text
_performance_queue = build_performance_order(trigger_player_id)
  1. 遍历 state.players，只取 alive and not out_of_game 的角色
  2. 对该角色 skill_instances_by_player[player_id] 中每个技能实例：
       仅取 is_joy_skill() and can_perform_joy_skill()
  3. 座次序号 seat_order：以触发角色在 state.players 的下标为 0，按正序递增环回
       seat_order(player) = posmod(index(player_id) - index(trigger_player_id), players.size())
  4. 排序键：(performance_number 升序, seat_order 升序)
```

同一角色持有多个欢愉技时，每个技能各自成为一个独立执行项（按编号排在各自位置）。

### 串行执行与续接

```text
_start_next_performance()
  ├─ 队列耗尽 → _finish_without_resume()（回调控制器恢复回合开始）
  ├─ 取当前项，重新校验持有者仍存活且未离场（前一项可能已令其死亡/离场）→ 跳过
  ├─ _waiting_for_barrier = false
  ├─ 调用 skill.perform_joy_skill({...})
  └─ 该技能若创建了选择：立即返回并挂起；提交后经统一选择协议回到技能自身的
     continue_selection()，技能完成效果后调用 host.finish_joy_skill_performance()

finish_joy_skill_performance(player_id, skill_id)
  └─ 校验与当前项匹配 → complete_current_performance()

complete_current_performance()
  ├─ host.has_nested_settlement_barrier() → _waiting_for_barrier = true；
  │    登记通用续接（与机缘的 defer_opportunity_resolution() 同构）
  └─ 否则 → continue_after_barrier()

continue_after_barrier()
  ├─ 屏障已清空且 _waiting_for_barrier → 推进下一项
  └─ 否则 → 先让内容层的多层续接跑完，再推进
```

**停滞自修复**：`MatchController` 的软修复分支（`:999` 附近）已有 `opportunity_system.continue_after_barrier()` 的兜底轻推。阿哈时刻在同一处追加一次等价轻推，条件同为「没有待办请求」，避免流程卡死。

---

## 四、欢愉技的内容层契约（`SkillDefinition` 扩展）

新增两个显式元数据键（与 `reincarnation` 同一风格：**只承认源码显式声明，不从正文推导**）：

| 元数据键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `joy_skill` | `bool` | `false` | 是否欢愉技 |
| `performance_number` | `int` | `0` | 参演编号，非负整数 |

新增访问器（`_metadata` 不再被外部直接读取）：

| 函数 | 语义 |
|---|---|
| `is_joy_skill() -> bool` | 是否欢愉技 |
| `get_performance_number() -> int` | 参演编号（非负） |
| `can_perform_joy_skill() -> bool` | **无副作用**前置校验；默认实现为 `is_joy_skill() and can_use_effect()`，并校验持有者存活 |
| `perform_joy_skill(context: Dictionary) -> void` | 欢愉技的执行入口，默认空实现；内容文件覆盖 |
| `finish_joy_skill_performance() -> void` | 包装 `host.finish_joy_skill_performance(owner_player_id, get_id())` |

**欢愉技不生成主动按钮**：`ui_enabled` 保持 `false`，因此无需 `can_activate()` / `activate()`；技能栏仍正常显示该技能（`ui_enabled=false` 的技能本来就会显示但不点亮，与现有被动技能一致）。

---

## 五、多张重铸端口契约

在 `match_controller.gd` 的 `recast_hand_card` 之后新增：

```gdscript
## 令指定角色一次重铸多张普通手牌：先把它们全部置入弃牌堆，再摸等量的牌。
## 返回实际重铸张数；0 表示没有任何一张被重铸（调用方不得据此产生后续效果）。
func recast_hand_cards(player_id: int, card_uids: Array[int]) -> int
```

语义约束（与单张重铸完全一致，见 `:12729` 的既有注释）：

- 不构成「使用」「打出」，也**不构成「弃置」**：`_move_to_discard(card, -2, false)`，不派发 `cardsDiscardedBatchAfter`，不触发弃置类技能。
- 日志：多张时写一条 `"%s重铸了%d张牌。"`；单张路径**保持原有** `"%s重铸了%s。"` 文本不变（`card_action_semantics_test` / `gameplay_regression_test` 依赖该文本）。
- 嵌套屏障：全部移入弃牌堆后若命中 `_has_nested_settlement_barrier()`，用 `_defer_rule_continuation("recast_draw", {"player_id":..., "count":n})` 延后补摸。
- 校验：角色存在、存活、未离场；每张 UID 必须仍在**普通手牌区**（`find_hand_card`），装备/木牛「粮」/判定牌一律拒绝；传入重复 UID 只重铸一次。

**复用而非重写**：把「逐张移入弃牌堆 + 写日志 + 续接补摸」提炼为私有辅助函数，单张 `recast_hand_card` 改为走同一条路径但保留单张日志与返回类型（`bool`），从而既消除重复又零行为变更。

---

## 六、兼容性与回滚

**向后兼容**

- 所有新增均为增量：新文件、新端口、新元数据键（默认 `false` / `0`）。未声明 `joy_skill` 的现有 144 个技能行为**完全不变**。
- 阿哈时刻组件默认创建即启用，但「无可执行欢愉技直接跳过」使其在现有全部对局中**零可观测影响**：不消耗随机数、不写日志、不改变任何回合开始前的时序。
- 单张重铸的返回类型、日志文本、语义均不变。

**回归风险点**

| 风险 | 说明 |
|---|---|
| 回合开始提前置链被改动 | `_start_turn` / `continue_after_opportunity` / `_start_queued_or_normal_turn` 三处是阶段推进的敏感路径，必须保证时机不变、不重复判定 |
| 随机流被多消耗一次 | 只在真正触发阿哈时刻时才写 `random_history`；候选为空时**不得**调用 `randf()` |
| 单张重铸日志文本变化 | 会让 `card_action_semantics_test` 与 `gameplay_regression_test` 失败 |

**回滚**

删除 `scripts/core/ahha_moment_system.gd`、`game_data/characters/huohua.gd`、`game_data/skills/{haoxi,lianxi}.gd`，还原 `factions.json` 与 `match_controller.gd` / `skill_definition.gd` 的三处增量即可。无存档格式变化、无数据迁移。

---

## 七、需要同步的文档

| 文档 | 同步内容 |
|---|---|
| `docs/游戏机制与玩法内容.md` | 阿哈时刻触发概率算法、每轮一次、与机缘相互独立、参演编号排序规则、势力与武将数值、多张重铸语义 |
| `docs/内容制作指南.md` | `joy_skill` / `performance_number` 两个新元数据键、`perform_joy_skill` 生命周期、`recast_hand_cards` 端口 |
| `docs/架构说明.md` | `AhhaMomentSystem` 在 core 层的职责与边界 |
| `docs/AI模块.md` | 【好戏】【连戏】的配套 AI 评分口径 |
| `README.md` | 新增测试场景（若有）的说明 |
