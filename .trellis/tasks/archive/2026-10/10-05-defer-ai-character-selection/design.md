# 技术设计：同时选将阶段的 AI 等待门禁

父任务：`10-05-character-selection-timing-and-seat-refresh`
需求见同目录 `prd.md`。

## 一、问题边界

现状把「AI 要不要等真人」与「是否开启自选座次身份」绑定在一起：

```gdscript
# match_controller.gd:11797-11803（改前）
if character_selection.custom_assignment_enabled and (
	character_selection.phase == CharacterSelectionService.PHASE_CUSTOM
	or (character_selection.uses_simultaneous_selection() and character_selection.phase == CharacterSelectionService.PHASE_OTHERS)
):
	for pending_player_id: int in character_selection.get_pending_player_ids():
		if not ai_coordinator.is_ai_controlled(pending_player_id):
			return
```

于是「同时选将」这一**阶段性质**被写成了「开关性质」：开关关闭时，身份局 `PHASE_OTHERS` 的 AI 会立刻确认。而 `PHASE_OTHERS` 的定义本身就是「多名玩家同时选将，选择内容在全员完成前隐藏」（`character_selection_service.gd:9-10`）——既然内容要隐藏，就不该有 AI 提前把武将变成「已被占用」。

因此本次不是新增规则，而是**把已经存在的等待语义归还给它本来的触发条件**：阶段，而不是开关。

## 二、职责划分（组件边界）

| 组件 | 拥有的知识 | 本次新增 | 不得拥有 |
|---|---|---|---|
| `CharacterSelectionService` | 阶段模型、待选集合、候选与完成判定 | 一个只读阶段判据 `is_simultaneous_selection_phase()` | 不得知道「AI」这个概念 |
| `AiCoordinator` | 「某玩家是否由内置 AI 控制」 | 无 | 不得知道选将阶段 |
| `MatchController` | 调度：把前两者组合成等待门禁 | 一个私有门禁函数 `_should_defer_ai_character_selection()` | 不得直接写 `_selections_by_player` |

沿用项目既有的单向依赖：服务层内向、无节点依赖；控制器组合服务与协调器。判定条件只有一处实现，避免「进入前」与「循环内」两份条件漂移（PRD R6 / AC-8）。

## 三、接口契约

### 3.1 `CharacterSelectionService.is_simultaneous_selection_phase() -> bool`

- **语义**：当前阶段是否为「多名玩家同时选将」。
- **实现**：`return phase == PHASE_OTHERS`。
- **为什么单独开一个函数，而不是复用既有的 `uses_simultaneous_selection()`**：后者是**模式**判据（`is_doudizhu_mode() or is_team2v2_mode()`，`character_selection_service.gd:154-155`），被候选生成与座次身份自选逻辑共用；身份局返回 false。若直接改它的语义，会同时改变座次/身份自选的行为，属于超范围改动。新增的阶段判据与模式判据正交，互不影响。
- **只读**：不修改任何状态，可在快照、门禁与测试中任意调用。

### 3.2 `MatchController._should_defer_ai_character_selection() -> bool`

- **语义**：此刻 AI 是否必须让真人先选。
- **实现**：
  1. `character_selection == null` → `false`。
  2. 阶段既不是「同时选将阶段」也不是 `PHASE_CUSTOM` → `false`（领袖阶段、已完成阶段都直接放行，对应 PRD R4/R9）。
  3. 遍历 `character_selection.get_pending_player_ids()`，只要存在一个 `not ai_coordinator.is_ai_controlled(player_id)` → `true`。
  4. 否则 `false`（对应 AC-6：无真人时照常推进）。
- **为什么放在控制器**：它是唯一同时持有 `character_selection` 与 `ai_coordinator` 的地方；放进服务会把 AI 概念泄漏进规则服务，破坏分层。
- **不会死锁的论证（本设计的关键正确性依据）**：`_create_players()` 对每名玩家做 `is_human_player = index == local_human_player_id`（`match_controller.gd:9528`），并只为 `not is_human_player` 的座位注册 AI（`:9542-9543`）。因此**任何**经 `start_match()` 产生的对局中，「非 AI 待选者」必然恰好是「需要真人输入的座位」——局域网真人同样不在 `_policies` 中。等待这些座位是正确语义，而不是死锁。
- **协调器缺失时的取舍**：`ai_coordinator == null` 时无法判定控制权，此时**放行**（宁可少等，不可卡死）。注意这与「协调器存在但策略表为空」不同：后者表示该座位确实不由内置 AI 控制（生产环境即真人/网络玩家），必须等待。

### 3.3 调用点（两处，同一函数）

- `_drive_ai_character_selection()` 进入处（改前 `:11797-11803`）：`if _should_defer_ai_character_selection(): return`。
- 同一个 `while` 循环每轮开头（改前 `:11808-11818`）：`if _should_defer_ai_character_selection(): break`。
  - **为什么循环内还要再判**：首任 AI 领袖在 `PHASE_LEADER` 确认后会在**同一循环内**把阶段推进到 `PHASE_OTHERS`；此时循环若不重新判门禁，就会继续替其余 AI 抢选（这正是改前用两份条件的原因，改后共用一份函数）。

## 四、数据流（改动后）

```
真人点击确认武将
   └─ MatchController.select_character()            :1854
        └─ CharacterSelectionService.select_character()  ← 写入 _selections_by_player，可能推进阶段
        └─ _drive_ai_character_selection()          :1913
              ├─ _should_defer_ai_character_selection()
              │     ├─ 阶段是 PHASE_OTHERS / PHASE_CUSTOM ?
              │     └─ 存在非 AI 待选者 ?
              │           ├─ 是 → return（等人）
              │           └─ 否 → 继续
              └─ while 阶段未完成：
                    再判门禁 → 通过则逐个 AI 确认（各自私有候选池取张）
                    直到阶段变为 PHASE_COMPLETE
```

无真人对局（`local_human_player_id = -1`，例如自动化测试与全 AI 观战）在第一步即放行，一次驱动跑完全部 AI 确认——这是**行为不变**的路径。

## 五、兼容性与风险

| 场景 | 改动前 | 改动后 | 是否符合预期 |
|---|---|---|---|
| 身份局 `PHASE_OTHERS`，自选开关关闭 | AI 立刻确认 | AI 等真人确认后确认 | **本次要修的行为** |
| 身份局 `PHASE_OTHERS`，自选开关开启 | 等真人 | 等真人 | 不变 |
| `PHASE_CUSTOM` | 等真人 | 等真人 | 不变 |
| 斗地主 / 2v2 同时选将，开关关闭 | AI 立刻确认 | 等真人 | **本次要修的行为** |
| 斗地主 / 2v2 同时选将，开关开启 | 等真人 | 等真人 | 不变 |
| 过关斩将 | 敌方等红方全部确认（服务层既有约束） | 同左，且门禁与之一致 | 不变 |
| 无真人（全 AI） | 一次驱动完成 | 一次驱动完成 | 不变 |
| `control_all_characters_enabled`（离线控制全部角色） | 取决于 `ai_coordinator` 中这些座位是否已注销 AI | 同判据，同左 | 不变（沿用既有判据） |

### 风险 1：真人长时间不确认导致观感「AI 不动」

这是**规则要求的行为**（内容在全员完成前隐藏），且已有停滞自修复分派 `_redrive_pre_game_ai_progress()`（`:1007`）与看门狗处理真实卡死。缓解：界面在同时选将阶段本就展示「已确认/未确认」进度（`character_selection_service.gd:856-862` 的 `readiness`），用户可据此理解为何 AI 尚未落定。

**已决策：不新增「真人挂机超时自动确认」兜底（用户拍板）**。因此本设计**刻意不引入**超时、不引入轮询、不引入新的配置项。理由与边界：

- 离线局只有一名真人，等待不会影响他人，与任何单机游戏等待玩家输入一致。
- 联机局真人挂机时，既有托管（`auto_management`）会把该座位交给 AI；门禁读取的是**实时**的 `is_ai_controlled()`，因此托管生效后门禁自动放行，无需新机制。
- 真正的对局停滞（无人待办却无进展）由既有看门狗与 `_redrive_pre_game_ai_progress()` 覆盖，不在选将层重复实现。

> 若将来要加超时，正确位置是**新增独立机制**（自带常量、配置项与文档），而不是把超时塞进本门禁——否则门禁会同时承担「时机判定」和「超时策略」两种职责，违反单一职责。

### 风险 2：既有测试依赖「AI 立刻确认」

已逐个核对最可能受影响的用例，结论如下（**这是本节最重要的证据**）：

| 用例 | 为什么不受影响 | 证据 |
|---|---|---|
| `tests/control_all_characters_test.gd` | 「控制全部角色」开启时**AI 策略仍然注册**（该测试自己断言 `initial_ai_count == 2`），因此门禁把座位 1/2 判为 AI 并照常放行；测试只替座位 0 提交，提交后同一调用内门禁即放行，AI 在同一轮完成 | `:44-64`（开关组合、`:50` 的 AI 数量断言、`:58-62` 只提交座位 0、`:63-64` 的 `selection_stuck` 兜底） |
| `tests/lan_turn_control_test.gd` | 该局三个座位**全是真人**，门禁没有 AI 可等；测试自己按 `pending_ids[0]` 逐个提交 | `:296-310`（含 `lan_selection_stuck` 兜底） |
| `tests/doudizhu_mode_test.gd` / `tests/team2v2_mode_test.gd` | 已按 `get_pending_player_ids()` 循环驱动，天然兼容「先真人后 AI」 | `doudizhu_mode_test.gd:498`、`:530-533`；`team2v2_mode_test.gd:279` |
| `tests/smoke_test.gd` / `tests/pre_game_customization_test.gd` 的部分断言 | 直接操作**裸服务实例**（`CharacterSelectionService.new()`），不经过控制器驱动，门禁不参与 | `smoke_test.gd:499-531`；`pre_game_customization_test.gd:568-573` |
| `tests/conquest_mode_test.gd` | 过关斩将的等待语义在服务层已经存在，本次门禁与之一致 | `:137`、`:141` |

因此「AI 在真人未确认时即确认」这一旧行为**没有被任何既有测试当作契约固定**（它是被容忍的现状，且已在 `verification.md:74` 被记录为需要规避的缺陷来源）。这一节把「需要改测试」的预期降到了最低，但实现阶段仍必须全量回归验证，不得凭本节结论跳过。

另有一条既有测试需要注意其**语义边界**：`control_all_characters_test.gd` 等用例在真人确认后即在同一调用栈内完成 AI 确认，因此不会多消耗帧；若实现把门禁写成「下一帧再驱动」，会引入额外帧并可能触碰这些用例的 `safety` 计数上限。**实现必须保持「真人提交 → 同一次调用内驱动 AI」的同步推进**（对应 AC-4）。

### 风险 3：联机真人掉线导致永久等待

局域网真人掉线时 `ai_coordinator` 是否接管由既有网络与托管逻辑决定（不在本次范围）。等待门禁只读该既有判据，不新增超时；真实卡死由既有自修复与看门狗覆盖（PRD R8）。

## 六、回滚

改动量为「一个新增只读函数 + 一个新增私有门禁函数 + 两处条件替换」。回滚即把两处调用点还原为改前的 `custom_assignment_enabled and (...)` 表达式并删除两个新函数；无数据迁移、无存档格式变化、无资源变化。

## 七、测试设计

| 用例 | 断言 | 位置 |
|---|---|---|
| 身份局同时选将等待 | 真人未确认时，除领袖外全部 AI 的武将均未确认；`phase` 仍为 `PHASE_OTHERS` | 新增/扩展选将类测试 |
| 真人确认后一次驱动完成 | 真人确认后，全部 AI 已确认且 `phase == PHASE_COMPLETE` | 同上 |
| 真人候选不被抢占 | 真人确认其候选首张必定成功（不再返回「该武将已经被其他玩家选择」） | 同上 |
| 无真人对局 | 全 AI 时开局即完成全部选将 | 既有 `pre_game_customization_test` / `doudizhu_mode_test` |
| 斗地主 / 2v2 同时选将 | 开关关闭时同样等待 | 扩展 `doudizhu_mode_test` / `team2v2_mode_test` |
| 过关斩将 | 红方未确认时敌方未选将；红方确认后敌方完成 | 既有 `conquest_mode_test` / `conquest_coop_test` |

断言禁止使用固定墙钟等待；失败信息必须带实际观测值（观测到的阶段名、已确认玩家 ID 列表）。
