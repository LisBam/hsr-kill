# 权威规则层开发规范

> 覆盖 `scripts/core/`、`scripts/data/`、`scripts/opportunity/`。
> 权威文档：[`docs/架构说明.md`](../../../docs/架构说明.md)。

---

## 层职责与边界

这一层是项目的**唯一权威**：它拥有规则状态、执行结算、派发时机、推进阶段。

```text
游戏数据层 (game_data, data)
      ↓
数据结构层 (scripts/data)  CardInstance / PlayerState / GameState / PlayerAction / ChoiceRequest
      ↓
权威规则层 (scripts/core)  MatchController → EventScheduler → 各规则服务
      ↓
   ↙        ↓         ↘
  UI    AICoordinator   NetworkGateway     ← 三者都只读快照、只提交动作
```

- **任何界面、AI 或网络模块都不得直接改写 `GameState`。**
- UI / AI / 网络拿到的都是**观察者裁剪后的只读快照**。
- 断言与修复的落脚点永远在权威层，不在表现层。

---

## Pre-Development Checklist（开工前必读）

- [ ] 读 `docs/架构说明.md` 对应章节（总体原则 / 模块职责 / 各类边界）。
- [ ] 确认改动属于「状态结构」「规则结算」「事件运行时」还是「阶段流程」，对应读本层指南。
- [ ] 确认是否已有**现成服务或端口**可以复用（避免在 `MatchController` 里继续堆功能）。
- [ ] 确认新增状态字段是否必须进入**观察者快照**与**权威存档**；若进入，需同步 UI/AI/网络侧读取。
- [ ] 确认是否触碰 236 时机目录（含真实轮末时机 `roundEnd`）、暂停 token、续接队列等运行时约束。
- [ ] 若改动影响玩法或数值，先规划 `docs/游戏机制与玩法内容.md` 的同步内容。

---

## 指南索引

| 指南 | 内容 |
|---|---|
| [layering-and-state.md](./layering-and-state.md) | 单向依赖、状态结构与快照可见性、服务组件单一职责、移牌唯一边界 |
| [event-runtime-phases.md](./event-runtime-phases.md) | `EventScheduler` 步骤契约、暂停令牌、阶段推进端口、触发排序、续接队列、统一结算管线 |

---

## Quality Check（完成前自检）

- [ ] 未让表现层/AI/网络直接改写 `GameState`；改动只发生在权威侧。
- [ ] 新增状态字段已明确是否进入观察者快照与权威存档，并同步了相关读取方。
- [ ] 新增逻辑优先落在**单一职责服务组件**中，而非继续膨胀 `MatchController`。
- [ ] 每个 `GameEvent` 步骤都有推进、终态、子事件或暂停点，无裸 `redo()`。
- [ ] 阶段推进只经控制器标准端口，未直接写 `current_phase`/`phase_index`。
- [ ] 移牌只经 `CardMovementService` 这一唯一边界，未绕过 `card_moved` 增量。
- [ ] 涉及结算顺序时，已按统一结算管线的固定顺序核对。
- [ ] 运行时对象（节点、`Callable`、`PlayerState`）未存入需跨帧序列化的上下文。
- [ ] 已跑相关测试（`event_runtime_test` / `skill_settlement_runtime_test` / `gameplay_regression_test` / `phase_progression_test`）。
- [ ] `docs/架构说明.md` 与《游戏机制与玩法内容》已同步。

---

## 相关测试

| 场景 | 用途 |
|---|---|
| `tests/event_runtime_test.tscn` | 事件父子、`next`/`after`、暂停通道、终止三态、递归深度 |
| `tests/skill_settlement_runtime_test.tscn` | 分片时机、技能自登记重复上限、通用规则续接三层保护 |
| `tests/gameplay_regression_test.tscn` | `CardUseEvent` 拓扑、五组使用时机、逐目标时机、无懈与八卦阵时序 |
| `tests/phase_progression_test.tscn` | 阶段跳过与异步选择后的唯一后续恢复 |
| `tests/rule_timing_test.tscn` / `tests/health_mechanics_test.tscn` | 时机目录与体力/护盾机制 |
| `tests/stall_watchdog_test.tscn` | 停滞自修复 |
| `tests/performance_and_pacing_test.tscn` | 长局内存上界与索引上限 |
