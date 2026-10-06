# 执行计划：开局座位一致性（选将面板座次缓存跨局残留）

父任务：`10-05-character-selection-timing-and-seat-refresh`
需求：`prd.md`　设计：`design.md`

## 前置阅读（开工前必须完成）

- `.trellis/spec/core/index.md`、`.trellis/spec/core/layering-and-state.md`（层职责与单向依赖；本次只动表现层，需确认不越界）
- `.trellis/spec/project/verification.md`（测试与验证标准；特别注意 §五「内容增长后的测试稳定性约定」与「不要用固定墙钟等待」）
- `.trellis/spec/project/documentation-sync.md`（同步矩阵）
- `.trellis/spec/ui/`（界面层规范：若存在，必读）
- `项目专属AGENTS.md`（注释与文档同步规范）
- `docs/游戏机制与玩法内容.md` 的 `:43`、`:54`、`:61`、`:539`、`:546`（自选座次身份流程与座位规则的文档化契约）

## 步骤

### 1. 建立基线

- [ ] 串行跑并记录基线：`doudizhu_mode_test`、`team2v2_mode_test`、`pre_game_customization_test`、`ui_layout_test`、`main_menu_test`。
- [ ] 确认基线全绿。若基线已红，先判断是否与本改动相关并记录，不要顺手修。

### 2. 先写失败断言（证明断言有区分力——本设计的核心验证步骤）

> 依据 `design.md` §7.1：既有重开用例的判据是**正确的**，只是被 `custom_character_assignment_enabled(false)` 绕开了。因此本步骤以「扩展已有正确判据」为主。

- [ ] 复用 `tests/doudizhu_mode_test.gd:457-470 _selection_title_matches_local_assignment()`，并把它强化为同时校验三者一致：**标题座次** / **面板 `_selected_seat_number`** / **`state.players.find(local) + 1`**。
- [ ] 让 `_test_selection_menu_restart_random_assignment()`（`:381-440`）对 `custom_enabled in [false, true]` **各跑一遍**（自选关闭 = 回归保护；自选开启 = 缺陷覆盖）。
- [ ] 新增「**身份局 · 自选开启 · 在领袖阶段重开**」用例（对应 `design.md` §2.4 的修正：重开把阶段打回开头，身份局同样命中）。
- [ ] 新增「**2v2 · 自选开启 · 局内菜单重开**」用例。
- [ ] 新增「预览被他人确认后回读」用例（对应 C3，`design.md` §2.3）。
- [ ] 逐条跑，确认**自选开启的三条在改动前失败**，并把失败输出（含标题文本、面板缓存值、权威座次、占用情况）保存到任务目录作为证据。
- [ ] 确认「自选关闭」那条在改动前**通过**（它必须作为回归保护基线，不能因新断言写法本身而失败）。
- [ ] 处理 `GameSettings` 全局污染：新用例对开关成对设置/恢复，不得依赖既有 `_restore_settings()` 的执行时机（它直到 `:84` 才恢复，存在跨用例耦合）。

### 3. 修复一（主修）：新对局复位选将面板

- [ ] `scripts/ui/match_table.gd:3765-3814 _reset_presentation_for_new_match()`：与 `:3792 card_selection_panel.close()` 并列补上 `character_selection_panel.close()`。
- [ ] 按 `:3913` 的空值防护写法先判 `!= null and is_instance_valid(...)`。
- [ ] 新增永久性注释：说明选将面板持有跨局本地座次缓存，新对局必须复位；并说明该函数是普通重开与存档恢复的共用入口。
- [ ] **不得删除或改写该函数内任何既有注释与语句。**

### 4. 修复二（不变量硬化）：权威回读不再只认单一阶段

- [ ] `scripts/ui/character_selection_panel.gd:365-379`：把「延续上下文时的权威回读」从「仅 `phase == PHASE_CUSTOM`」放宽为「快照携带权威座次/身份字段即回读」（按字段存在性与合法性判断，不按阶段名判断）。
- [ ] 保留 `:376-377` 的既有注释原文，**只在其后补充**新注释说明放宽的原因（`PHASE_OTHERS` 下权威值此前永不被采纳）与覆盖范围（C1 与 C3）。
- [ ] 确认 `get_preview_seat_number()` 的取值链（已确认 → 预览 → 初始，`character_selection_service.gd:718-721`）保证任意时刻返回的都是**本局**权威值。
- [ ] 自检：本改动**不引入任何座次计算**（面板仍是纯消费者，不变量 I3）。

### 5. 修复三：自选关闭时无条件置空

- [ ] `bind_snapshot()` 开头按 `bool(snapshot.get("allow_custom_assignment", false))` 无条件置 `_selected_seat_number = -1` / `_selected_identity = ""`。
- [ ] 保留 `:370-373` 既有分支内赋值与注释不动，只在其之前补一次显式归零并加注释说明「自选关闭时座次身份无意义，任何上下文都不得保留」。

### 6. 使新断言通过

- [ ] 跑第 2 步的四条用例，全部转为通过。
- [ ] 确认失败信息包含实际观测值（标题文本、面板缓存值、权威座次）。

### 7. 全量回归（串行）

- [ ] 界面与选将：`ui_layout_test`（`:999` 断言完整标题文案）、`pre_game_customization_test`（`:631` 断言面板 `_selected_seat_number == 1`）、`inline_hand_choice_test`、`skill_target_ui_test`、`wheel_duel_mode_test`、`font_color_audit_test`。
- [ ] 模式：`doudizhu_mode_test`、`team2v2_mode_test`、`conquest_mode_test`、`conquest_save_test`。
- [ ] 重开与菜单：`main_menu_test`（重开流程）、`smoke_test`。
- [ ] 联机（**确认无回归，不扩大改动**）：`lan_match_flow_test`、`lan_turn_control_test`。
- [ ] 判定标准：退出码 0 + 输出 `*_PASS` + 日志无 `ERROR`/`FAIL`。资源占用告警区分「偶发观测」与「稳定泄漏」，无 `--verbose` 证据不得宣称修复。
- [ ] 若某用例失败：先判定它断言的是「旧行为」还是「真实回退」。属于旧行为的按新契约修正断言并记录原因；属于回退的回到第 3/4/5 步修正实现。

### 8. 自检（对照 spec）

- [ ] 表现层未新增任何座次计算，只做「本局权威值与本地乐观值的切换」（不变量 I3）。
- [ ] 未让表现层写 `GameState`。
- [ ] `CharacterSelectionService` 与 `MatchController` **零改动**（设计明确不改核心层）。
- [ ] 快照契约未扩展（刻意不加 `match_id`，理由见 `design.md` §4.2）。
- [ ] 既有变量名与注释未被删除或改写；新增注释为永久性描述（不含「本次更新」字样）。

### 9. 文档同步

- [ ] `docs/游戏机制与玩法内容.md`：明确「每次开局重新随机本地座次并刷新选将界面显示」；记录「权威预览被拒时界面回落到权威值」这一行为变化；核对 `:43`、`:54`、`:61`、`:539`、`:546` 与新实现完全对齐。
- [ ] `docs/架构说明.md`：补「新对局复位选将面板」与「选将界面座次唯一来源为本局权威快照」。
- [ ] `docs/界面与交互.md`：补选将标题座次/身份的取值来源与复位时机。
- [ ] `README.md`：本设计预期只扩展既有测试场景 → 若不新增 `*_test.tscn` 则记录「无需改动」的理由；若新增则补「自动校验」。
- [ ] `临时反馈文档.md`：追加学习反馈摘要（修改思路 / 架构与设计 / Bug原因与修复方法 / 关键代码解析 / 学习要点提炼）+ Git 提交描述，带 `YYYY-MM-DD HH:MM` 时间戳。

### 10. 提交

- [ ] 按项目规范写分行数字序号的提交描述（每行一个独立动作）。
- [ ] 提交前确认工作区只含本子任务相关文件。

## 验证命令

```powershell
& 'E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe' `
  --headless --path 'E:\Godot\MyGame\hsr-kill' res://tests/<name>_test.tscn
```

- 串行执行（不得并行：多进程会争用本机用户设置与 `.godot` 缓存）。
- 部分用例使用真实 `main.tscn` 与界面按钮，不能加 `--headless` 时按既有该用例的运行方式执行。

## 评审门（Review Gate）

- 第 2 步「自选开启」三条断言的**改动前失败证据**必须真实存在；拿不到失败证据说明用例没覆盖到 C1，必须回到第 2 步重写（不得直接进入第 3 步）。
- 第 7 步全绿之前不得进入第 9 步文档同步与提交。
- 若第 2 步发现失败原因是 C5（对手座次标签用创建序）而非 C1，**暂停并回到用户确认范围**，不要自行扩大改动。

## 回滚点

- 第 3 步之后（只新增一行调用）——安全回滚点。
- 第 4、5 步之后——按 `design.md` §十 还原面板两处逻辑。
