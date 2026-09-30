# 执行计划：星际和平公司势力与武将真珠

## 0. 执行前提

- 分支：`master`（本次沿用当前分支，不新建 worktree）。
- Godot 控制台程序（headless 回归统一使用）：
  `E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe`
- 回归命令模板（项目根目录执行，逐个进程顺序执行）：
  ```powershell
  & 'E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/<name>_test.tscn 2>&1 | Tee-Object .godot_test_logs/<name>.log
  ```
- 判定标准（沿用《战斗框架回归说明》）：进程退出码 0 + 输出自身 PASS 标记 + 日志无 `ERROR`/`SCRIPT ERROR`/`FAIL`/退出资源泄漏告警。
- 实施顺序：先核心机制、再内容文件、最后测试与文档；每完成一个可独立验证的步骤就跑一次最小验证，避免问题堆积。

## 1. 势力登记

- [x] `game_data/factions.json` 追加 `{"id":"xingjihepinggongsi","display_name":"星际和平公司","short_name":"司","color":"b87333"}`，字段顺序与既有条目一致。
- [x] 验证：`GameDatabase.validation_errors` 不含势力相关条目（用第 10 步测试覆盖）。

## 2. 武将真珠

- [x] 新增 `game_data/characters/zhenzhu.gd`：`id=zhenzhu`、`display_name=真珠`、`gender=female`、`faction=xingjihepinggongsi`、`max_hp=3`，技能脚本数组为 `[buzhui.gd, jianying.gd]`。
- [x] 每个变量/常量独立注释；`description` 为定位说明，不复述数值。
- [x] 依赖：本步骤引用的两个技能文件在第 7、8 步创建，因此**先建技能文件再建武将文件**（或同时创建后统一验证）。

## 3. 核心机制一：`roundEnd` 时机

- [x] `scripts/core/rule_timing_catalog.gd`：`GAME_PHASE_TIMINGS` 在 `enterGame` 与 `roundStart` 之间插入 `"roundEnd"`，注释说明「真实轮末时机，先于轮开始」。
- [x] `scripts/core/match_controller.gd`：
  - [x] `RULE_CONTINUATION_TYPES` 增加 `"round_end_after_restore"`（`"round_end_restore"` 保留）。
  - [x] 续接分派表：`"round_end_restore"` → `_begin_round_end_boundary(...)`；新增 `"round_end_after_restore"` → `_continue_round_end_after_restore(...)`。
  - [x] `_continue_after_phase_after` 的 `is_round_boundary` 分支改为调用 `_begin_round_end_boundary(player_id)`（屏障分支保持延后，但延后后从 `_begin_round_end_boundary` 重新进入）。
  - [x] 新增 `_begin_round_end_boundary` / `_emit_round_end_timing` / `_restore_round_limited_players` / `_complete_round_end_boundary` 四个函数，均带完整文档注释（设计见 `design.md` 第 3 节）。
- [x] 关键检查点：`roundEnd` 的事件数据固定包含 `round_number`（结束轮数，尚未递增）、`finished_player_id`、`turn_number`；派发使用 `emit_sequence_timing` 以保证可暂停。
- [x] 验证：`rule_timing` 会因数量断言失败（预期失败，第 4 步修复）；`opportunity_system`、`gameplay_regression`、`smoke` 必须通过。

## 4. 更新时机目录断言

- [x] `tests/rule_timing_test.gd`：注释与打印文本 235 → 236；`timing_names.size()` 断言 235 → 236；`expected_category_sizes` 首项 57 → 58。
- [x] `tests/rule_timing_test.gd` 增补 `roundEnd` 的真实派发断言（订阅 `roundEnd` 计数，跑一个完整轮转，断言计数为 1，且与 `roundStart` 计数同为 1）。
- [x] 验证：`rule_timing` 通过。

## 5. 核心机制二：手牌视为的牌面复制（数据层）

- [x] `scripts/data/card_instance.gd`：
  - [x] 新增 `hand_view_as_original_suit` / `hand_view_as_original_rank` / `last_hand_view_as_suit` / `last_hand_view_as_rank` 四个字段（各带独立注释）。
  - [x] 新增 `set_hand_view_as_with_face(...) -> bool`：校验牌名、花色（四种）与点数（1..13）；首次建立视为时快照实体定义与实体花色点数；随后覆写 `definition_id`/`suit`/`rank`。
  - [x] 扩展 `clear_hand_view_as()`：恢复 `definition_id`/`suit`/`rank`，并把本次视为牌面写入 `last_hand_view_as_*`。
  - [x] 扩展 `clear_hand_view_as_presentation()`：一并清空新增的两项 `last_*`。
  - [x] 扩展 `to_dict()` / `from_dict()`：输出与还原 `presentation_original_suit`、`presentation_original_rank`、`view_as_suit`、`view_as_rank`。
- [x] 兼容自检：不调用新方法时，`presentation_original_*` 与 `view_as_suit/rank` 必须为空/0，保证既有【药理】【亲酿】快照逐字不变。

## 6. 核心机制二：控制器写入口

- [x] `scripts/core/match_controller.gd` 新增 `set_hand_card_view_as_with_face(player_id, card_uid, view_as_definition_id, suit, rank, source_skill_id) -> bool`：
  - [x] 校验：对局未结束、玩家有效、牌在该玩家手牌区、牌名存在、花色点数合法（失败时零副作用返回 `false`）。
  - [x] 成功：调用 `CardInstance.set_hand_view_as_with_face` → 写规则日志（含花色点数与视为牌名）→ `_emit_state()`。
  - [x] 放在既有 `set_hand_cards_view_as` / `transfer_hand_card_as` 端口附近，保持同一区域的端口聚集。

## 7. 核心机制二：表现层

- [x] `scripts/ui/card_view.gd`：
  - [x] 解析 `presentation_original_suit/rank`（实体牌面）与 `view_as_suit/rank`（逻辑牌面）。
  - [x] `_suit_rank_text` 在牌面覆写生效时取实体原值；横条文本在 `view_as_suit` 非空时前缀「花色符号＋点数」。
  - [x] 信息框副标题同样带前缀，与横条一致。
  - [x] 复用既有花色符号/点数渲染函数，不新增第二套映射。
  - [x] 验证：`smoke`、`ui_layout` 通过（横条与角标断言不回退）。

## 8. 内容层：欢愉技【补缀】

- [x] 新增 `game_data/skills/buzhui.gd`（设计见 `design.md` 第 2.3 节）：
  - [x] 顶部常量：参演编号、目标上下限、护盾增减量、请求 kind、取消开关、AI 权重常量，全部带注释。
  - [x] `build_definition()`：正文逐字（含 `欢愉技，参演编号104`）、`joy_skill=true`、`performance_number=104`、`trigger=passive`。
  - [x] `perform_joy_skill(context)`：目标选择 0~3 名（`allow_cancel=false`）→ 逐名给 1 点盾 → 记录轮末扣盾 → `finish_joy_skill_performance()`。
  - [x] `install()`：订阅 `roundEnd`（`role="global"`、`maintenance=true`）；覆盖 `can_trigger_while_owner_inactive` 返回 `true`（持续效果清理）。
  - [x] `_on_round_end(event)`：消费 `round_number <= 结束轮数` 的记录，逐条逐目标 `loseShield(1, 来源)`。
  - [x] `score_ai_choice`：按 `buzhui_target` 分派，友方/残血加分、敌方负分、全敌方时空选择。

## 9. 内容层：主动技【鉴映】

- [x] 新增 `game_data/skills/jianying.gd`（设计见 `design.md` 第 2.4 节）：
  - [x] 顶部常量：三个请求 kind、选择数量、取消开关、装备类型常量、护盾门槛、AI 阈值与权重。
  - [x] 运行时状态：`_used_this_play_phase`、`_revealed_material_uid`、`_revealed_material_definition_id`（各带独立注释）。
  - [x] `build_definition()`：正文逐字、`trigger=active`、`enable=phaseUse`、`ui_enabled=true`。
  - [x] `install()`：订阅 `phaseUseBegin` 复位本阶段次数。
  - [x] 阶段 0/1/2/3/4 与 `continue_selection` 分派；阶段 1 确认时消费次数、`reveal_hand_card` 展示 A；阶段 2 只选人；阶段 3 由真珠从目标手牌选 B 并展示；阶段 4 非装备牌则调用 `set_hand_card_view_as_with_face`。
  - [x] `append_play_phase_actions` + `score_ai_choice`（三个 kind）。
- [x] 自检：不得出现「同时展示两张」的路径；`reveal_hand_card` 只能按 1→3 顺序各调用一次。

## 10. 新增专项测试

- [x] 新增 `tests/zhenzhu_mechanics_test.gd` + `tests/zhenzhu_mechanics_test.tscn`（沿用 `extends Node` + `_ready → call_deferred("_run")` + 装配 `MatchController`/`RuleEventBus` + `print("ZHENZHU_MECHANICS_PASS ...")` + `get_tree().quit(0/1)` 的既有测试骨架）。
- [x] 覆盖项：
  - [x] 静态资料：势力字段与颜色、真珠体力 3/性别/势力、两技能正文逐字、`joy_skill` 与参演编号、`GameDatabase.validation_errors` 为空。
  - [x] 【补缀】：强制发动无取消、0 名目标可结算、3 名目标各 +1 盾、轮末各 −1 盾、护盾为 0 时扣 0 不报错、同轮两次演出共扣 2 点。
  - [x] `roundEnd`：一次轮转只派发一次且顺序在离场恢复与轮末机缘之前；额外回合不派发。
  - [x] 【鉴映】：阶段 1 取消不消耗次数；展示后不可取消；A/B 分别展示；B 非装备牌时 A 的定义+花色+点数全部等于 B；A 作为材料转化其他牌时虚拟牌继承视为花色点数；A 离手后恢复原定义与原花色点数；B 为装备牌时不建立视为。
  - [x] 表现：视为牌快照的 `view_as_suit/rank` 与 `presentation_original_suit/rank` 正确（横条文本由 `card_view` 断言用例或快照字段断言覆盖）。
  - [x] AI：`score_ai_choice` 在三个 kind 下的取值方向（低价值 A 得分更高、自身有盾优先自身、全敌方时 0 名目标得分最高）。
- [x] 验证：
  ```powershell
  & '<Godot控制台程序>' --headless --path . --scene res://tests/zhenzhu_mechanics_test.tscn 2>&1 | Tee-Object .godot_test_logs/zhenzhu.log
  ```

## 11. 定向回归

按顺序执行并逐项确认退出码 0、PASS、无错误：

- [x] `zhenzhu_mechanics`（新增）
- [x] `rule_timing`（目录 236）
- [x] `opportunity_system`（轮末机缘顺序）
- [x] `phase_progression`、`phase_sequence`（阶段与轮转）
- [x] `new_character_mechanics`
- [x] `health_mechanics`（护盾机制）
- [x] `virtual_card_color`（材料花色聚合）
- [x] `skill_choice`、`response_choice`
- [x] `ai_policy`（AI 钩子）
- [x] `event_runtime`
- [x] `gameplay_regression`
- [x] `smoke`、`match_replay`
- [x] `ui_layout`（牌面与横条）

若任一项失败：先判断是断言过期（如数量常量）还是真实回归，前者同步更新断言并记录原因，后者回退到对应步骤修复后重跑该项与相邻项。

## 12. 文档同步

- [x] `docs/内容制作指南.md`：时机总数 235 → 236（含标题与正文全部出现处）、`roundEnd` 加入目录清单与「游戏、回合与阶段（58个）」分类标题、势力登记表新增星际和平公司、视为牌维护规则补充「复制花色点数的视为」用法与 `set_hand_card_view_as_with_face` 端口说明、技能清单补充【补缀】【鉴映】。
- [x] `docs/游戏机制与玩法内容.md`：时机总数与机制说明、`roundEnd` 语义与顺序、欢愉技参演编号 104、护盾 1 点增减与轮末扣减、出牌阶段限一次与视为规则，全部具体数值写明。
- [x] 检查 `docs/` 其他文档是否出现 235（如《卡牌系统》等），按关联文档校验原则同步。
- [x] 更新 `docs/战斗框架回归说明.md`：追加本次专项回归结果段落（新增场景与定向复跑结论、退出码与告警情况）。

## 13. 收尾

- [x] 确认未引入调试残留（临时打印、临时文件、`print` 排查代码）。
- [x] 撰写「学习反馈摘要」（修改思路 / 架构与设计 / 关键代码解析 / 学习要点提炼）。
- [x] 撰写编号 Git 提交描述（每行一个独立改动点，动词开头）。
- [x] 将时间戳（`YYYY-MM-DD HH:MM`）+ 学习反馈摘要 + Git 提交描述**追加**写入根目录 `临时反馈文档.md`。
- [x] 归档任务：`python ./.trellis/scripts/task.py finish`，必要时 `archive`。
- [x] 如产生可复用的新约定（真实轮末时机的用法、视为牌牌面复制的口径），通过 `trellis-update-spec` 写入 `.trellis/spec/`。

## 14. 执行结果记录（2026-09-30 06:30）

- 覆盖范围：正文全部步骤已完成；`zhenzhu_mechanics` 新增专项 10 个场景全部通过，广域回归 35 项 + 新增 1 项 = **36/36 通过**（退出码 0、各自 PASS、对应日志无 ERROR/SCRIPT ERROR/FAIL），另按第 11 步补跑 `ui_layout`、`virtual_card_color`、`phase_sequence` 三项也全部通过。
- 步骤 4 偏差说明：`roundEnd` 的真实派发计数断言（一次轮转派发一次、与 `roundStart` 同级）放在新增的 `zhenzhu_mechanics_test._test_round_end_timing_boundary` 中完成（含“额外回合不派发”与“处理者创建选择时轮末序列暂停、限时离场角色在 `roundEnd` 之后才恢复”）。`rule_timing_test` 侧改为验证分类顺序不变量：`GAME_PHASE_TIMINGS` 中 `roundEnd` 必须紧邻 `roundStart` 之前。这样纯目录/顺序测试不再为了构造一次真实轮转而重复装配整套对局。
- 步骤 7 验证结果：`ui_layout` 通过（`UI_LAYOUT_PASS viewport=(1152.0, 648.0)`）；其退出时偶发一次 `resources still in use` 告警，`--verbose` 复跑未复现，与《战斗框架回归说明》里既有的偶发音频资源告警属同一类观测。
- 核心修复（超出原计划范围，但在实现中被验证为必需）：`SkillDefinition._can_receive_timing_event()` 的“局内获得技能额度”检查原本对所有技能调用控制器端口，而该端口对死亡角色一律返回 `false`，使固有技能覆盖 `can_trigger_while_owner_inactive` 的死亡后清理路径永远不可达。现改为只在技能确实位于 `player.acquired_skills` 时执行该检查（`owner == null` 保持原行为），活着角色的行为逐字不变。
- 回归中顺带修复的两处测试侧问题：`conquest_coop` 的“各自选择”不再盲目提交候选首项（内置 AI 会先占用真人候选），`gameplay_regression` 的延时锦囊表现序列改为按条件等待而不是固定 0.12 秒。
- 文档同步：`docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/战斗框架回归说明.md` 已更新；`游戏机制与玩法内容.md` 顺带校正了长期滞后的计数（武将文件 37→42、势力 9→10、武将技能 79→88、技能文件 82→91），数值均按当前代码实测重新核算。
