# 统一选将期间全部角色的座次显示取值序

父任务：`10-05-character-selection-timing-and-seat-refresh`
需求来源：用户原话「请在每次开始游戏时刷新一下所有角色的座位」中的「**所有角色**」部分（用户已确认「两者都要修」）。

## Goal

消除「选将标题用领袖旋转序、牌桌座次标签用创建序」这两套并行口径，使**全部角色**（本地真人与每名对手）在选将阶段显示的座次同源、自洽，并且从开局到对局开始不发生事后跳变。

## 与兄弟子任务的边界

| 子任务 | 负责的缺陷 | 性质 |
|---|---|---|
| `10-05-refresh-seats-on-match-start` | 选将面板座次缓存**跨局残留**（上一局的座位被带到本局） | 「上一局 vs 本局」的时间边界 |
| **本子任务** | 选将期间**标题序与标签序不一致**（同一时刻两套口径） | 「同一时刻的两个数据源」的一致性 |

两者根因不同、修复层不同，必须独立验证。**若在实现本子任务时才观察到跨局残留现象，应将其交回兄弟子任务，不得在本子任务内顺手修缓存。**

## 现状证据（规划阶段确认）

- **座位即数组下标**：`state.players` 的下标就是座次（0 为一号位）；`match_controller.gd:4244-4246` 用 `state.players.find(player) + 1` 反查。
- **标题的取值来源**：`CharacterSelectionService.to_dict(viewer_id)` 的 `local_seat_number = get_preview_seat_number(viewer_id)`（`character_selection_service.gd:899`），取值链为「已确认座次 → 编辑预览 → `_initial_seats_by_player`」（`:718-721`）。
- **权威层把 `seat_number` 写成了数组下标**（缺陷的根）：`scripts/data/game_state.gd:191 serialized_player["seat_number"] = seat_index + 1`。其相邻注释 `:187`/`:189` 写明该字段**本意**是「MatchController 会在身份确定后把领袖旋转到数组首位」「供界面显示领袖为一号位且不依赖稳定 player_id」——即本应是领袖旋转后的座次，实现却取了原始下标。
- **标签取值经过快照，UI 未重算**：`match_table.gd:1981` 读 `player.get("seat_number")`，因此修复落在**权威层**，不是表现层。
- **两序对本地玩家也不恒等（重要修正）**：标签序是 `c + 1`（创建序），标题序是 `((c - ℓ + n) mod n) + 1`（领袖旋转序），仅当领袖创建下标 `ℓ = 0` 时重合。本地看不出问题**只因为本地座次标签被永久清空**（`match_table.gd:1228-1229`、`:1997`）。该分歧还会在对局日志中显现——`match_controller.gd:4244-4246` 用 `state.players.find(player) + 1` 取座次，构成**第三个**座次来源。
- **领袖优先模式的初始座次是旋转**：身份局 `_initial_seats_by_player` 按 `(player_index - initial_leader_index + size) % size + 1` 把领袖固定到 1 号位（`character_selection_service.gd:421-432`）。
- **数组的旋转发生在选将之后**：`MatchController._reorder_players_from_leader()`（`match_controller.gd:11730-11755`）在 `leader_index > 0` 时旋转 `state.players`，调用点为 `:11367` 与 `:11422`（都在选将接近结束/开局时）。
- **牌桌座次标签读数组下标**：`scripts/data/game_state.gd:186-191` 与 `scripts/ui/match_table.gd:1981`（对手标签）；本地座次标签另有硬性清空 `match_table.gd:1997`（本地视角不显示座次号）。
- **本地玩家自己的座次在两序下不恒等，但本地标签被清空**：见上方「两序对本地玩家也不恒等」一条。
- **斗地主 / 2v2 不受本缺陷影响**：斗地主在 `_create_players` 内就已按座次身份重排数组（`match_controller.gd:9547-9548` → `:11682`），2v2 / 过关斩将 / 车轮战无首任身份故永不旋转，且 `index+1` 本就等于其座次。

## Requirements

- R3-1 选将阶段内，**全部角色**在牌桌上显示的座次，必须与选将标题所依据的座次序**同源**：不得同时存在「标题按领袖旋转序、对手标签按创建序」两套口径。
- R3-2 从开局到对局开始，任一角色的显示座次不得因为数组事后被旋转而**跳变**。若座次在选将期间确实会变化（例如玩家自选座次身份），该变化必须由**权威确认/预览事件**驱动，而不是由事后的数组重排造成。
- R3-3 座次序只能有**一个权威来源**。严禁在表现层为标签单独重算一套座次（不得把领袖旋转公式复制进 UI）。
- R3-4 不得破坏既有文档化契约：第一回合固定由领袖开始；领袖在身份确认后固定为一号位；其他角色按顺时针成为二号位及后续座次；本地玩家座次不会覆盖该顺序。
- R3-5 不得破坏局域网座位映射与存档恢复的座位语义。
- R3-6 不得为修复本缺陷而改变各模式既有的座位规则（身份局领袖一号位、斗地主地主一号位/五人局三号位、2v2 一四同色与二三同色、过关斩将交替座位）。
- R3-7 修复策略必须由代码证据选定（旋转数组时机 / 标签改读权威座次 / 其他），并在 `design.md` 中论证其影响面；不得凭直觉选择影响面更大的方案。
- R3-8 **顺带修复同类缺陷（调研发掘）**：斗地主选将期间「座次标签」与「显示名」不符——`_create_players` 在 `:9530` 按创建下标生成显示名，随后在 `:9548` 重排数组却未刷新显示名，而 `_resolve_seat_display_name` 只在 `:11755`/`:11763` 被写、可达路径不覆盖此处，于是可能出现「标签显示『一』、悬停名显示『玩家3』」。该缺陷与 R3-1 同族（同一座次被两处口径描述），且所选策略 `_reorder_players_from_leader()` **自带**显示名刷新，属零额外代价修复，因此纳入本次范围。

## Acceptance Criteria

- [ ] AC-1 身份局选将阶段内，对**每一名对手**：牌桌座次标签显示的座次 == 该角色在本局权威座次序中的座次（与标题同一来源）。
- [ ] AC-2 身份局从开局到对局开始，任一角色的显示座次不出现事后跳变（在权威座次不再变化的前提下，标签数值不变）。
- [ ] AC-3 本地真人的标题座次与其最终座位一致（与兄弟子任务的 AC 不重复：本项用于确认本改动未破坏标题取值）。
- [ ] AC-4 斗地主与 2v2 作为**不受影响的对照组**：改动前后座次规则与标签显示均不变。
- [ ] AC-5 权威座次序只有一个实现（不存在 UI 侧复制的旋转公式）；相关判据可通过既有服务端口取得。**且不得新增第二份座次真值**（不新增逐玩家座次字段/映射）。
- [ ] AC-5b 斗地主选将期间每名角色的显示名编号与其座次标签一致（R3-8 / C6），且该断言在修复前会失败。
- [ ] AC-6 相关测试全部通过：`ui_layout_test`、`doudizhu_mode_test`、`team2v2_mode_test`、`pre_game_customization_test`、`conquest_mode_test`、`main_menu_test`、`smoke_test`，以及**所有断言座次/标签**的既有用例；标准为退出码 0 + 输出 PASS 标记 + 日志无 ERROR/FAIL。
- [ ] AC-7 新增回归断言覆盖 AC-1/AC-2/AC-5b，且**在修复前会失败**（必须留存改动前失败输出；拿不到失败证据说明用例没覆盖该缺陷）。
- [ ] AC-8 未删除或改写既有变量名与注释（只允许新增）；新增逻辑落在单一职责组件内。
- [ ] AC-9 已按 `.trellis/spec/project/documentation-sync.md` 同步：`docs/游戏机制与玩法内容.md`（座位规则与显示口径）与 `docs/界面与交互.md`（座次标签取值来源）为必查；若改动触及权威状态传播则补 `docs/架构说明.md`；测试场景变化时同步 `README.md` 的「自动校验」。

## Constraints

- **不得在 UI 里重算座次**：若选择「标签改读权威座次」路线，权威值必须通过既有服务/快照端口取得，而不是在 `match_table.gd` 内重新实现旋转。
- 若选择「提前旋转数组」路线，必须先证明不存在任何依赖「选将期间 `state.players[i].player_id == i`」或依赖「创建序」的读取方（联机座位映射、会话令牌迁移、存档、回放、回合起点、显示名刷新都要逐一核对）。
- 尊重原版：严禁擅改变量名，严禁删除或篡改原有注释，只可新增。
- 遵循 `.trellis/spec/project/verification.md`：不使用固定墙钟等待；失败信息必须包含实际观测值（至少包含：角色、标签显示值、权威座次值、数组下标）。
- **验证前置**：必须先取得「改动前新断言失败」的实证再改实现。

## Out of scope

- 选将面板座次缓存的跨局残留（归兄弟子任务 `10-05-refresh-seats-on-match-start`）。
- AI 选将时机（归子任务 `10-05-defer-ai-character-selection`）。
- 各模式座位规则、身份数量表、局域网大厅座位选择 UI 与协议。
- 车轮战抓将与过关斩将读档的座位语义。
- 不重构 `MatchController` 与 `match_table.gd` 的既有体积。

## Evidence / References

> 只供实现定位锚点，不作为验收目标。完整调研结论见 `design.md`。

| 锚点 | 位置 |
|---|---|
| 标题座次字段 | `scripts/core/character_selection_service.gd:899` |
| 预览座次取值链 | `scripts/core/character_selection_service.gd:718-721` |
| 领袖优先模式的初始座次旋转 | `scripts/core/character_selection_service.gd:421-432` |
| 数组旋转入口与调用点 | `scripts/core/match_controller.gd:11730-11755`、`:11367`、`:11422` |
| 预览重排（自选座次身份） | `scripts/core/match_controller.gd:11279-11317` |
| 斗地主座位重排（对照：已同源） | `scripts/core/match_controller.gd:9547-9548`、`:11682-11726` |
| 对手座次标签读取 | `scripts/data/game_state.gd:186-191`、`scripts/ui/match_table.gd:1981` |
| 本地座次标签清空 | `scripts/ui/match_table.gd:1997` |
