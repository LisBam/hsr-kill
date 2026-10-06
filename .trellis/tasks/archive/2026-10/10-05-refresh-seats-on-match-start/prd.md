# 修复重开后开局座位与选将后座位不一致

父任务：`10-05-character-selection-timing-and-seat-refresh`

## Goal

让「开局时向玩家显示的座位」「选将界面预览的座位」与「选将完成后的最终座位」在任何开局路径下都取自**同一份权威座位结果**，并保证每次开局都把显示刷新为本局结果而非沿用上一局。

> **口径澄清（重要）**：调研已证伪「核心层缺少每局重新计算」——`start_match()` 每局都已经重随机本地座次并重排数组（见「根因定位」）。因此用户原话「请在每次开始游戏时刷新一下所有角色的座位」的落地含义是：**每次开局都必须让界面重新取得本局的权威座位结果（清掉跨局缓存），而不是在核心层再算一遍**。

## 用户原文

> 同时要修复每次重开的座位混乱问题，有时候重开后玩家游戏开始时显示的座位和实际选将后所在的座位并不相符，请在每次开始游戏时刷新一下所有角色的座位。

关键限定词：

- 「**有时候**」——间歇性，说明失效依赖某个随机或条件分支，不是稳定复现的必然错误。
- 「**重开后**」——与「连续开局/重开一局」相关，说明存在跨局存活的状态参与其中。
- 「**刷新一下所有角色的座位**」——用户期望的修法是**在开局时重新计算全部座位**，而不是在显示端做补偿。

## 已确认口径（用户决策）

- 修法：每次开局从权威侧刷新全部角色座位，使显示座位与最终座位一致。
- 属于缺陷修复，不新增玩法规则；不得改变各模式既有的座位规则。

## 现状证据（规划阶段确认，供设计定位）

- **座位即数组下标**：`state.players` 的下标就是座次（0 为一号位）。`match_controller.gd:4244-4246` 用 `state.players.find(player) + 1` 反查座次；`:9549-9553` 明确记录「数组下标即最终座次」。
- **稳定 ID 与座次分离**：`player_id` 由创建索引决定且跨局稳定（`:9534-9535`），座次由数组顺序表达；重排只改数组顺序，不改 `player_id` 与身份（`:9544-9546`）。
- **开局显示座位的来源**：选将标题「你的身份为：X，你的座次为N号位」读取快照字段 `local_seat_number = get_preview_seat_number(viewer_id)`（`character_selection_service.gd:899`；UI 在 `character_selection_panel.gd:485-500`）。
- **`get_preview_seat_number()` 的取值链**（`character_selection_service.gd:718-721`）：已确认座次 → 编辑预览 → `_initial_seats_by_player`。
- **初始座次的两种算法**（`character_selection_service.gd:421-436`）：
  - 领袖优先模式（身份局）：`_initial_seats_by_player` 按**旋转**计算，领袖固定为 1 号位。
  - 斗地主 / 2v2 / 过关斩将：`_initial_seats_by_player` 直接等于创建顺序下标 +1，注释说明「座次与身份已在创建玩家时固定，不再旋转」。
- **数组旋转入口**：`_reorder_players_from_leader()`（`match_controller.gd:11730`）在 `leader_index > 0` 时按领袖旋转数组，并刷新显示名；调用点在 `:11367` 与 `:11422`。
- **预览重排入口**：约 `:11180-11318` 按预览座次重建 `state.players`，并刷新显示名（`:11317`）。
- **本地真人座位随机化**：`_assign_local_human_player_seat()`（`:1847`，`randomize_local_human_seat` 默认 true，`:281`）随机 `local_human_player_id`，唯一调用点 `:1510`，位于 `_reset_per_match_progress_state()` 内，**早于** `_create_players()`（`:1567`）。顺序不可颠倒：`:9528` 用 `local_human_player_id` 判定谁是真人，`:9542-9543` 据此注册 AI。
- **跨局存活字段（座位相关候选）**：`_last_automatic_doudizhu_local_seat_index` / `_last_automatic_doudizhu_local_identity`（`match_controller.gd:596` 附近），由 `_avoid_repeated_automatic_doudizhu_local_assignment()`（`:9583`，在 `:9518-9519` 被调用）读写，用于「自动斗地主不连续两局展示相同本地座次+身份」。
- **服务每局重建**：`character_selection = CharacterSelectionService.new()` 在 `:1560`（普通开局）与 `:15904`（过关斩将读档恢复）；`begin()`（`character_selection_service.gd:353-374`）清空全部座位映射。
- **另有独立重排**：`_reorder_doudizhu_players_by_seat_identity()`（`:11682`）在 `_create_players` 内被调用（`:9548`），并在 `_reorder_players_from_leader()` 内被重复调用（`:11734`，注释声明幂等）。

## 根因定位（调研结论，已核对代码链）

**核心层并不缺「每局刷新座位」**：`start_match()` 每局都会经 `_assign_local_human_player_seat()`（`match_controller.gd:1510`、`:1847-1850`）重随机本地座次，身份局还会在 `_reorder_players_from_leader()`（`:11745-11750`）按领袖旋转数组，且初始座次表与最终旋转是**同一取模公式**（服务 `character_selection_service.gd:426-429` 对数组 `match_controller.gd:11745-11750`）。已逐项代数验算一致。

真实缺口在**选将面板的本地座次缓存跨局残留**，且只有「局内重开」这条入口漏清：

1. 局内重开经 `match_table.gd:3747 _reset_presentation_for_new_match()` → `:3749 start_match()`。
2. `_reset_presentation_for_new_match()`（`:3765-3814`）关了 `card_selection_panel`（`:3792`）等全部表现，**唯独没有 `character_selection_panel.close()`**（对比主菜单路径会关：`:3891`、`:3913-3914`）。
3. 面板只在离开选将阶段时才关（`:1751-1754`），而重开时旧局与新局的阶段都是 `character_selection` → **永不关闭**。
4. `character_selection_panel.gd:365` 的 `preserves_local_context` 用「面板可见 + 阶段名相同 + `target_player_id` 相同」判断同一上下文，而 `to_dict()` **从不下发 `target_player_id`**（`character_selection_service.gd:882-918`）→ 恒等于 `-1` → 判据退化为「阶段名相同」，**没有对局归属维度**。
5. 命中该判据时复位分支不执行，且唯一的权威回读分支只认 `PHASE_CUSTOM`（`:376-379`）。斗地主 / 2v2 / 过关斩将首帧阶段即 `PHASE_OTHERS`，因此面板座次**整局都不被权威快照纠正**。
6. 标题（`:470-472`、`:500`）与确认提交（`:1386-1387`）都用这份缓存 → 显示与最终落位双错。

触发条件（四者同时满足，故用户看到「有时候」）：自选座次身份开关开启 + 在选将阶段用局内菜单重开 + 新旧局首帧阶段名相同 + 旧座次在新局仍合法。

**对调研结论的一处修正**：调研认为身份局因 `PHASE_LEADER → PHASE_CUSTOM` 的阶段变化必自愈——这只在**同一局内阶段推进**时成立；**重开会把阶段打回开头**，旧局停在 `PHASE_LEADER`、新局首帧也是 `PHASE_LEADER`，判据仍为真。**因此身份局（自选开启 + 在领袖阶段重开）同样在范围内**，测试必须覆盖。

已证伪的候选（记录以免重走）：自选与领袖轮转冲突（领袖身份全局唯一且双绑，`_reorder_players_from_leader` 幂等）、重开漏刷核心座次、初始座次表与最终数组不一致、存档恢复漏刷（读档本就不该重刷）。详见 `design.md` §2.5。

## Requirements

- R2-1 每次开局（新开、重开、以及任何重新进入选将的入口）都必须**重新计算并写入**全部角色的座位；不得沿用上一局的座位值或座位相关缓存。
- R2-2 对本地真人与每名 AI 都必须满足：开局显示座位 == 选将预览座位 == 选将完成后最终座位。
- R2-3 显示的座次与身份必须**唯一来自本局权威快照**：不得在表现层「纠正数值」，也**不得让表现层保留跨局的座次值**。表现层仍然是纯消费者——它可以在「本局权威值」与「本局内的乐观本地值」之间切换，但不得自行计算座次、不得让上一局的值存活到本局。
- R2-4 选将面板的本地选择状态（`_selected_seat_number`、`_selected_identity`、`_selected_character_id`、`_showing_all_characters`、`_snapshot`）在每一局开始时必须回到初始态。
- R2-5 面板对座次的权威回读不得只在单一阶段生效：只要本局快照携带权威座次/身份字段，面板就必须采纳该权威值（消除「`PHASE_OTHERS` 下整局不回读」这一缺口）。
- R2-6 自选座次身份关闭时，座次与身份对界面无意义，面板在任何上下文下都不得保留其值。
- R2-7 **不得改动核心层**：`CharacterSelectionService` 与 `MatchController` 的座次计算保持原样（已证伪「核心层缺刷新」），也**不扩展快照字段契约**（避免牵动局域网裁剪与回放路径）。
- R2-8 不得改变稳定 `player_id` 与座次的既有分离；不得改变 `player_id` 的分配规则。
- R2-9 不得改变各模式既有座位规则：身份局领袖一号位、斗地主地主一号位（五人局另占三号位）、2v2 一四同色与二三同色、过关斩将偶数位玩家与奇数位敌人交替、局域网固定/随机座位与自选身份的既有语义。
- R2-10 必须保留「自动斗地主不连续两局展示相同本地座次+身份」的既有跨局去重行为。
- R2-11 往返幂等：开局流程中任何被重复调用的座位计算都必须是幂等的（重复调用不改变已确定的座位），因为既有代码已在多处重复调用重排入口。
- R2-12 不得因刷新而丢失或提前改变武将、身份、体力与技能状态；座位刷新只允许影响数组顺序与座位派生字段（如显示名）。
- R2-13 若某处状态存在跨局残留，必须显式重置该状态，而不是在上层做「不一致时再修一次」的补偿。

## Acceptance Criteria

- [ ] AC-1 连续开局（含局内菜单重开）至少两局，每局对本地真人与全部 AI 均满足：开局显示座位 == 面板缓存座位 == `state.players` 中的最终座位。
- [ ] AC-2 复现性：能给出**稳定复现**该不一致的用例，且在修复前必然失败。必须覆盖**自选座次身份开启**这一前提（关闭时缺陷被 `:-1` 初值掩盖，不构成复现）。
- [ ] AC-2b 覆盖三个模式族：斗地主、2v2、以及**身份局在领袖阶段重开**（依据「根因定位」中的修正，身份局并非必然自愈）。
- [ ] AC-2c 覆盖 C3 次因：某玩家预览的座次随后被他人确认时，该玩家的标题必须回落到权威值，而不是继续显示被丢弃的预览值。
- [ ] AC-3 各模式座位规则快照不变：身份局领袖一号位；斗地主地主一号位（五人局另占三号位）；2v2 一四同色与二三同色；过关斩将偶数位玩家、奇数位敌人。
- [ ] AC-4 自动斗地主的跨局去重仍然生效：连续两局本地玩家的「座次 + 身份」组合不完全相同。
- [ ] AC-5 选将界面标题显示的座位与最终座位一致（覆盖该标题取值链的全部来源）。
- [ ] AC-6 自选座次身份开启时，玩家主动选择座次后，显示与最终座位仍一致；**关闭时面板座次/身份在任何上下文下都为空（-1 / ""）**。
- [ ] AC-7 过关斩将读档恢复路径按存档座位恢复，不被本次改动破坏（读档**不该**重刷座位）。
- [ ] AC-8 相关测试全部通过：`doudizhu_mode_test`（含重开用例，需对自选开关 `false` / `true` 各跑一遍）、`team2v2_mode_test`、`pre_game_customization_test`、`ui_layout_test`、`main_menu_test`、`conquest_mode_test`、`conquest_save_test`、`lan_match_flow_test`、`lan_turn_control_test`、`inline_hand_choice_test`、`wheel_duel_mode_test`、`smoke_test`，标准为退出码 0 + 输出 PASS 标记 + 日志无 ERROR/FAIL。
- [ ] AC-9 新增回归断言覆盖 AC-1/AC-2/AC-2b/AC-2c，且**在修复前会失败**（必须留存改动前的失败输出作为证据；拿不到失败证据即视为用例没覆盖到根因）。
- [ ] AC-10 未删除或改写既有变量名与注释（只允许新增）；未让表现层改写 `GameState`。
- [ ] AC-11 已按 `.trellis/spec/project/documentation-sync.md` 同步：`docs/架构说明.md`（权威规则/状态结构）与 `docs/游戏机制与玩法内容.md`（座位规则）为必查；若涉及界面显示取值来源则补 `docs/界面与交互.md`；测试场景变化时同步 `README.md` 的「自动校验」。
- [ ] AC-12 核心层零改动：`scripts/core/character_selection_service.gd` 与 `scripts/core/match_controller.gd` 不含本次改动；快照字段契约未扩展。

## Constraints

- 不得用「显示时再算一遍」的方式修：同一份座位结果必须只有一处权威来源（避免两处各自计算再次漂移）。
- 座位计算必须幂等；既有代码已在 `:11367` 与 `:11422` 重复调用重排入口，新增刷新点不得破坏该幂等性。
- 随机化必须继续使用本局随机源 `_rng`（与固定种子可复现性约定一致），不得引入第二套随机源。
- 遵循 `.trellis/spec/core/layering-and-state.md`：新状态字段必须明确是否进入观察者快照与权威存档，并同步读取方。
- 遵循项目注释规范：新增变量、函数与条件必须有永久性注释；参数与常量置于文件顶部。
- **验证前置**：本次根因结论来自只读代码推导，**必须先取得「改动前新断言失败」的实证**再动手改代码；拿不到失败证据说明用例未覆盖根因，应回到用例设计而不是继续改实现。
- **范围冻结**：实现过程中若发现失败原因属于 C5（对手座次标签）而非面板缓存，应暂停并回到用户确认范围，不得自行扩大改动面。

## Out of scope

- **核心层的座位计算**：`CharacterSelectionService._initial_seats_by_player` 与 `MatchController._reorder_players_from_leader()` 均不改动（已证伪其必要性，见「根因定位」）。
- **快照字段契约**：不新增 `match_id` 等字段（会牵动局域网裁剪与回放；本次改用「权威回读」消除该判据的承重性）。
- **选将期间对手座次标签的取值序**（调研 C5）：选将期间对手标签用「创建序」（`scripts/data/game_state.gd:186-191`、`match_table.gd:1981`），而标题用「领袖旋转序」（`:11422` 才旋转数组）。用户已确认**两者都要修**，但该缺陷根因与本文档的「跨局缓存」完全不同（那是「取值序」问题，不是「跨局残留」问题），因此**归入独立子任务 `10-05-align-seat-labels-with-authoritative-order`**，本文档不重复其范围。
- 不修改各模式的身份数量表（`IdentityRules`）与身份分配算法。
- 不修改联机大厅的座位选择 UI 与固定座位/自选身份的协议（只保证其输入被正确消费）。
- 不修改车轮战抓将（`WheelDuelSelectionService`）。
- 不改写存档格式；读档必须按存档座位恢复。
- 不重构 `MatchController` 与 `match_table.gd` 的既有体积。

## Evidence / References

> 只供实现定位锚点，不作为验收目标。

| 锚点 | 位置 |
|---|---|
| 座位即数组下标 | `scripts/core/match_controller.gd:4244-4246`、`:9549-9553` |
| 创建玩家与身份赋值 | `scripts/core/match_controller.gd:9498-9553` |
| 本地真人座位随机化 | `scripts/core/match_controller.gd:1847-1850`、调用点 `:1510` |
| 领袖旋转 | `scripts/core/match_controller.gd:11730-11755` |
| 预览重排 | `scripts/core/match_controller.gd:11279-11317` |
| 斗地主座位重排 | `scripts/core/match_controller.gd:11682-11726` |
| 斗地主跨局去重 | `scripts/core/match_controller.gd:9583-9624` |
| 初始座次两种算法 | `scripts/core/character_selection_service.gd:421-436` |
| 预览座位取值链 | `scripts/core/character_selection_service.gd:718-721` |
| 快照座位字段 | `scripts/core/character_selection_service.gd:899`、`:910-913` |
| 选将标题 | `scripts/ui/character_selection_panel.gd:485-500` |
| 既有座位标题断言 | `tests/doudizhu_mode_test.gd:465-470`、`tests/ui_layout_test.gd:999` |
