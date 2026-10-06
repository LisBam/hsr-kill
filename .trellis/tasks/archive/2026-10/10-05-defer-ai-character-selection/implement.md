# 执行计划：同时选将阶段的 AI 等待门禁

父任务：`10-05-character-selection-timing-and-seat-refresh`
需求：`prd.md`　设计：`design.md`

## 前置阅读（开工前必须完成）

- `.trellis/spec/core/index.md`（层职责、开工前清单、完成前自检）
- `.trellis/spec/core/layering-and-state.md`（单向依赖、服务组件单一职责）
- `.trellis/spec/core/event-runtime-phases.md`（阶段推进端口约束）
- `.trellis/spec/project/verification.md`（测试与验证标准）
- `项目专属AGENTS.md`（注释与文档同步规范）
- `docs/游戏机制与玩法内容.md` 中「选将」相关章节（确认文档化契约）

## 步骤

### 1. 建立基线（改动前先跑一遍）

- [ ] 跑并记录基线结果：`pre_game_customization_test`、`doudizhu_mode_test`、`team2v2_mode_test`、`conquest_mode_test`、`conquest_coop_test`、`leader_skill_test`、`smoke_test`。
- [ ] 记录基线是否为全绿。若基线已红，先判断是否与本改动相关，写入任务备注，不要顺手修。

### 2. 先写失败断言（证明断言有区分力）

- [ ] 在合适的既有选将测试中新增断言组：身份局 `PHASE_OTHERS`（自选开关关闭）下，领袖确认后、真人未确认时，全部非领袖 AI 的武将必须**未确认**（`character_selection.get_selection(id).is_empty()`）。
- [ ] 追加断言：真人确认后，全部 AI 已确认且 `phase == PHASE_COMPLETE`。
- [ ] 追加断言：真人确认其候选首张必定成功（`select_character` 返回 true），即真人候选未被 AI 抢占。
- [ ] 跑一次，确认断言**失败**，并记录失败信息（这正是改动前的行为）。
- [ ] 保存失败输出摘要到任务目录（用于「断言有效性」证据）。

### 3. 服务层新增只读阶段判据

- [ ] `scripts/core/character_selection_service.gd` 新增 `is_simultaneous_selection_phase() -> bool`，返回 `phase == PHASE_OTHERS`。
- [ ] 配套永久性注释：说明它表达的是**阶段**而非模式，并点明与 `uses_simultaneous_selection()`（模式判据）的区别与不可互换的理由。
- [ ] 不修改 `uses_simultaneous_selection()` 的任何实现（它被候选生成与座次自选共用）。

### 4. 控制器新增唯一等待门禁

- [ ] `scripts/core/match_controller.gd` 新增私有函数 `_should_defer_ai_character_selection() -> bool`（放在 `_drive_ai_character_selection()` 之前）。
- [ ] 实现按 `design.md` §3.2：空服务/空协调器保守放行；非「同时选将阶段」且非 `PHASE_CUSTOM` 放行；存在非 AI 待选者则等待。
- [ ] 配套永久性注释：说明门禁为何必须单一实现、为何必须每轮重判、以及保守放行的理由（避免卡死优先）。

### 5. 替换两处条件

- [ ] `_drive_ai_character_selection()` 进入处：改为 `if _should_defer_ai_character_selection(): return`。
- [ ] 同一 `while` 循环每轮开头：改为 `if _should_defer_ai_character_selection(): break`。
- [ ] 删除改前两处重复条件表达式，保留（不删除）其原有注释，必要时把原注释改写为指向新函数的说明性注释——**只新增与澄清，不删除既有信息**。
- [ ] 确认 `_is_driving_character_selection` 的置位仍发生在门禁之后（等待时不得占用驱动标记）。

### 6. 使新断言通过

- [ ] 跑第 2 步的断言组，确认转为通过。
- [ ] 检查失败信息措辞是否包含实际观测值（阶段名、已确认 ID 列表）。

### 7. 全量回归

- [ ] 串行跑：`pre_game_customization_test`、`doudizhu_mode_test`、`team2v2_mode_test`、`conquest_mode_test`、`conquest_coop_test`、`leader_skill_test`、`ai_policy_test`、`control_all_characters_test`、`stall_watchdog_test`、`smoke_test`、`ui_layout_test`。
- [ ] 每个用例标准：退出码 0 + 输出含 PASS 标记 + 日志无 `ERROR` / `FAIL`。
- [ ] 对失败用例判定归属：若断言依赖「AI 在真人未确认时即确认」的旧行为，按新契约修正该断言（并在任务备注记录原因）；若属真实行为回退，回到第 4/5 步修正实现。

### 8. 自检（对照 spec）

- [ ] 未直接写 `state.current_phase` / `phase_index`；阶段仍由服务与控制器标准端口推进。
- [ ] 未让表现层或 AI 改写 `GameState`。
- [ ] 新增判定只有一处实现，两处调用点共用（AC-8）。
- [ ] 没有新增固定墙钟等待或轮询。
- [ ] 既有变量名与注释未被删除或改写。

### 9. 文档同步

- [ ] `docs/游戏机制与玩法内容.md`：更新「选将」章节，写明同时选将阶段的 AI 确认时机与「真人先选完、AI 再随机分配」的规则，并说明过关斩将的既有边界与之一致。
- [ ] `docs/AI模块.md`：按同步矩阵「AI 行为」一行必查必更，写明 AI 在选将阶段的确认时机与等待门禁。
- [ ] `docs/架构说明.md`：若选将服务的职责描述需要补充阶段判据，则补充；否则记录「无需改动」的理由。
- [ ] `docs/界面与交互.md`：若选将界面「已确认进度」的展示语义需要澄清，则补充。
- [ ] `README.md`：若新增或修改了测试场景，更新「自动校验」小节。
- [ ] `临时反馈文档.md`：追加学习反馈摘要 + Git 提交描述（带 `YYYY-MM-DD HH:MM` 时间戳）。

### 10. 提交

- [ ] 按项目规范撰写分行数字序号的 Git 提交描述（每行一个独立动作）。
- [ ] 提交前确认工作区只包含本子任务相关文件。

## 验证命令

```powershell
# 单个用例（示例）
& 'E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe' `
  --headless --path 'E:\Godot\MyGame\hsr-kill' res://tests/<name>_test.tscn
```

- 串行执行（不得并行，避免共享 `.godot` 与用户目录冲突）。
- 成功判定：退出码 0 + 输出含 `*_PASS` + 无 `ERROR`/`FAIL`。

## 评审门（Review Gate）

- 第 2 步的失败证据必须真实存在，否则视为断言无效，回到第 2 步。
- 第 7 步全绿之前不得进入第 9 步文档同步与提交。

## 回滚点

- 第 3 步之后（只新增函数，无调用）——安全回滚点。
- 第 5 步之后（两处条件替换）——按 `design.md` §6 还原条件表达式。
