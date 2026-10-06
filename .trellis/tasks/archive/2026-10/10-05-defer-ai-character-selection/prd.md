# 重构同时选将阶段的AI选将时机为真人确认后随机分配

父任务：`10-05-character-selection-timing-and-seat-refresh`

## Goal

把「AI 与真人同时选将」阶段的 AI 确认时机统一改为：**全部非 AI 玩家（本地真人与局域网真人）确认完毕后，AI 才从各自私有候选池随机取张确认**。适用范围覆盖身份局领袖选将后的同时选将、斗地主同时选将与 2v2 同时选将，且不依赖自选座次身份开关。

## 用户原文

> 重新优化选将逻辑，玩家和ai同时选将的阶段下（如主公选将后玩家和其他身份的ai一同选将时），需要在所有玩家选将完毕后，才随机分配其他AI的选将。

## 已确认口径（用户决策）

- AI 仍从**自己的私有随机候选池**取张（现状即「首张未被占用的随机候选」），不新增随机源、不改为全场未占用武将重新随机、不改为 AI 策略评分择优。
- 覆盖**全部**同时选将场景，不留「身份局等、斗地主不等」这类特例分支。

## 现状证据（规划阶段确认）

- `scripts/core/match_controller.gd:11792` `_drive_ai_character_selection()` 是 AI 选将的唯一驱动入口；三个调用点：`:1011`（预开局 AI 补齐分派）、`:1620`（开局 `begin()` 之后）、`:1913`（任意玩家提交选将之后）。
- 现有等待门禁被 `custom_assignment_enabled` 包裹（`:11797-11803` 与循环内 `:11808-11818`）：只有开启自选座次身份时才等真人。**身份局同时选将（`PHASE_OTHERS`）且未开启自选时，AI 立刻确认。**
- `scripts/core/character_selection_service.gd:9-10` 定义阶段：`PHASE_LEADER`（仅领袖）、`PHASE_OTHERS`（多名非领袖玩家同时选将，内容在全员完成前隐藏）。身份局、斗地主、2v2、过关斩将的「多人同时选将」都落在 `PHASE_OTHERS`。
- AI 取张：`match_controller.gd:11946` `_get_ai_character_selection_candidate()` 取私有候选中的首张未被他人占用的武将（`:11964-11990`），已在 `select_character` 之后经过统一校验，**随机性已经存在**，缺的只是时机。
- 真人候选会因 AI 提前占用而失效：`character_selection_service.gd:494` `_is_character_selected_by_other_player()` 会拒绝已被他人确认的武将 → 真人界面上的候选可能在点击时被判为「该武将已经被其他玩家选择」。这是本需求的实际用户可见症状。
- 过关斩将已有等价语义：`:838-841`（待选集合排除未解锁的敌方）与 `:466-467`（敌方在红方全部确认前提交会被拒绝）。本需求与它一致，不冲突。
- **已文档化的既有缺陷**：`.trellis/spec/project/verification.md:74` 记录了一条真实回归——`conquest_coop` 中「内置 AI 会**先于真人**确认武将并占走该项」，导致真人/测试提交候选时被拒「该武将已经被其他玩家选择。」当时只在**测试侧**规避（改为挑选未被占用的候选）。本需求修的是**产品侧**根因；测试侧的稳健写法仍需保留。
- `scripts/ai/ai_coordinator.gd:27` `is_ai_controlled(player_id)` = `_policies.has(player_id)`，是「该待选者是否由内置 AI 控制」的唯一权威判据，真人（含局域网真人）返回 false。

## Requirements

- R1 只要当前阶段是「多名玩家同时选将」（`PHASE_OTHERS`），AI 必须等待全部非 AI 待选玩家确认后才确认。
- R2 该等待不得依赖 `custom_assignment_enabled`；关闭自选座次身份时同样生效。
- R3 自选座次身份阶段（`PHASE_CUSTOM`）保持既有等待语义不变。
- R4 领袖阶段（`PHASE_LEADER`）不引入等待门禁：该阶段只有领袖可选，且 `get_pending_player_ids()` 在领袖阶段只返回领袖（`character_selection_service.gd:832-835`）。
- R5 AI 仍从各自私有候选池取张；不改候选生成、候选张数、换将卡与随机源。
- R6 等待门禁必须是**可复用的单一判定**，在「进入驱动前」与「驱动循环每一轮」使用同一份条件，不允许两处各写一遍条件（避免漂移）。
- R7 无真人待办时（全部待选者均为 AI，或真人已全部确认）AI 必须在同一次驱动中把剩余确认全部完成并推进到 `PHASE_COMPLETE`，不得新增等待、轮询或延时。
- R8 不得引入卡死：等待期间必须由真人提交动作（`select_character` → `:1913`）触发下一次驱动；已存在的人工停滞自修复分派 `_redrive_pre_game_ai_progress()`（`:1007`）继续可用。
- R9 不得改变「AI 待选者全部确认后阶段推进」的既有完成判定（`character_selection_service.gd:555-559`）。

## Acceptance Criteria

- [ ] AC-1 身份局（自选座次身份**关闭**）：领袖确认后进入 `PHASE_OTHERS`，本地真人未确认期间，全部非领袖 AI 的 `_selections_by_player` 均为空（即无 AI 提前确认）。
- [ ] AC-2 身份局（自选座次身份**开启**）：等待语义与改动前一致（回归不变）。
- [ ] AC-3 斗地主与 2v2（自选座次身份**关闭**）：同样满足 AC-1。
- [ ] AC-4 真人确认后，全部剩余 AI 在同一次驱动内完成确认，阶段推进到 `PHASE_COMPLETE`，无需额外调用或延时。
- [ ] AC-5 真人在同时选将阶段确认武将时，不再因 AI 提前占用而收到「该武将已经被其他玩家选择」；即真人候选在其确认前不会被任何 AI 占用。
- [ ] AC-6 无真人对局（`local_human_player_id = -1` 或全部待选者均为 AI）行为不变：AI 照常一次驱动完成全部选将。
- [ ] AC-7 过关斩将（单人局与联机多人局）行为不变：红方真人未全部确认时敌方不会选将；红方全部确认后敌方照常在驱动中完成。
- [ ] AC-8 等待门禁条件是单一可复用判定，不存在两份重复条件表达式。
- [ ] AC-9 相关测试全部通过：`pre_game_customization_test`、`doudizhu_mode_test`、`team2v2_mode_test`、`conquest_mode_test`、`conquest_coop_test`、`leader_skill_test`、`ai_policy_test`（AI 改动的强制项）、`control_all_characters_test`、`stall_watchdog_test`、`smoke_test`、`ui_layout_test`，标准为退出码 0 + 输出 PASS 标记 + 日志无 ERROR/FAIL。
- [ ] AC-10 新增回归断言覆盖 AC-1 与 AC-4（或 AC-3/AC-5），且断言在改动前会失败。
- [ ] AC-11 未删除或改写既有变量名与注释（只允许新增）；未让表现层或 AI 直接改写 `GameState`。
- [ ] AC-12 已按 `.trellis/spec/project/documentation-sync.md` 的同步矩阵核对文档：`docs/AI模块.md`（AI 行为时机）与 `docs/游戏机制与玩法内容.md`（选将规则）为必查；`docs/架构说明.md` 仅在职责描述需要补充时更新；测试场景变化时同步 `README.md` 的「自动校验」。

## Constraints

- 等待判定的「是否 AI 控制」必须用 `ai_coordinator.is_ai_controlled()`；不得用 `local_human_player_id` 或身份/模式来近似判断真人。
- 改动优先落在单一职责服务组件；阶段模型属于 `CharacterSelectionService`，AI 调度属于 `MatchController`，两者职责不得互换（服务不得知道 AI 的存在）。
- 遵循 `.trellis/spec/core/index.md`：阶段推进只经控制器标准端口；不得直接写 `state.current_phase`。
- 遵循项目注释规范：所有新增变量、函数、条件都需永久性注释说明「作用、设计意图、注意事项」；新增常量/参数置于文件顶部。

## Out of scope

- 车轮战抓将流程（`WheelDuelSelectionService`，独立服务）。
- **不新增「真人挂机超时自动确认」兜底（用户决策）**：真人未确认时一直等待。理由：离线局只有一名真人，不存在卡住他人的情况；联机局已有看门狗与托管机制（`auto_management`），托管会把座位交给 AI，从而使门禁自动放行。新增超时属于新增玩法规则，会带来新的数值、配置项与文档负担，本次不做。
- 主机调整 AI 武将阶段（`ai_character_adjustment`）与手气卡阶段。
- AI 候选生成算法、候选张数设置、换将卡机制。
- 联机大厅的座位与身份配置流程。

## Evidence / References

> 本节只供实现时定位锚点，不作为验收目标。

| 锚点 | 位置 | 用途 |
|---|---|---|
| AI 选将驱动入口 | `scripts/core/match_controller.gd:11792` | 本次改动的主入口 |
| 现有等待门禁（进入前） | `scripts/core/match_controller.gd:11797-11803` | 改为统一判定 |
| 现有等待门禁（循环内） | `scripts/core/match_controller.gd:11808-11818` | 改为同一判定 |
| AI 取张 | `scripts/core/match_controller.gd:11946` | 不变 |
| 阶段常量 | `scripts/core/character_selection_service.gd:7-16` | 用于新增「同时选将阶段」判据 |
| 待选集合 | `scripts/core/character_selection_service.gd:828` | 门禁的输入 |
| 完成判定 | `scripts/core/character_selection_service.gd:555-559` | 不得改变 |
| AI 控制判据 | `scripts/ai/ai_coordinator.gd:27` | 门禁的输入 |
| 预开局 AI 补齐分派 | `scripts/core/match_controller.gd:1007` | 停滞修复路径 |
| 提交入口（触发再驱动） | `scripts/core/match_controller.gd:1854`、`:1913` | 真人动作触发点 |
