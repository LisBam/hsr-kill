# 执行计划：十项缺陷修复

> 技术方案见 [`design.md`](./design.md)；需求与验收标准见 [`prd.md`](./prd.md)。
> 每步都写出**精确落点**与**验证方式**；未通过验证不得进入下一步。

## 0. 前置

- [ ] 0.1 记录基线：`Godot_v4.7.1-stable_mono_win64_console.exe --headless --path . res://tests/qingque_mechanics_test.tscn` → 期望 `QINGQUE_MECHANICS_PASS`、退出码 0（本会话已确认通过，作为工具链自检）。
- [ ] 0.2 改动前先读 `game_data/skill_definition.gd`、`scripts/core/card_rule_service.gd` 的相关函数，确认签名后再改（已读，签名见 `design.md`）。

## 1. 内容层：三处声明与数值

- [ ] 1.1 `game_data/skills/fanyin.gd:154`：黑色分支上下文补 `"ai_choice_skill_scored": true`，并在文件顶部新增同名常量 + 注释说明「该请求的收益已由本技能 `score_ai_choice` 完整表达，通用层不得再叠加目标态度」。
- [ ] 1.2 `game_data/cards/jiedaosharen.gd`：响应动作声明 `CARD_ACTION_PLAY` → `CardDefinition.CARD_ACTION_USE`，同步改写该行注释为「本次【杀】走**使用**逻辑，因此派发 `useCard`／`useCardAfter` 整牌时机」。
- [ ] 1.3 `game_data/skills/zhili.gd:188-189`：`_score_self_hp_cost` 改为 `-float(HP_COST) * NonameAIEvaluator.HP_RESOURCE_VALUE`，注释写明「持有者本人就是资源变化的目标，不能再乘一次自身态度」。
- [ ] 1.4 验证：`--headless --path . res://tests/smoke_test.tscn`（技能／卡牌正文与元数据不变）与 `res://tests/zhuyan_zhili_test.tscn`（【支离】规则与原文）。

## 2. 核心层：判定顺序改为「后来居上」

- [ ] 2.1 `scripts/core/match_controller.gd:12770`：`player.judgment_area.front()` → `.back()`，并把 `:12757`、`:12769` 的注释改写为「数组是**置入顺序**；判定按后来居上取**最后置入**的那张」。
- [ ] 2.2 `game_data/skills/xingqi.gd:126`：`.front()` → `.back()`，注释说明「最先被判定的是最后置入的那张」。
- [ ] 2.3 `game_data/skills/yousi.gd:311-334`：`_resolve_mitigation_suit` 由「遍历取第一项」改为「直接读最后一项」，注释同步改写。
- [ ] 2.4 `tests/gameplay_regression_test.gd`：把 `_test_delayed_judgment_presentation_sequence` 的即时断言（`:1336`）与 `expected_keys`（`:1351`）改为「兵粮寸断先判定」的顺序，即 `["delayedJudge:supply_shortage", "judge:supply_judgment", "delayedJudge:indulgence", "judge:indulgence_judgment"]`，并在注释里写明该期望对应「后来居上」。
- [ ] 2.5 验证：`--headless --path . res://tests/gameplay_regression_test.tscn`（末尾判定计数仍为 `judge=2`）。

## 3. 核心层：目标枚举咨询用牌禁令

- [ ] 3.1 `scripts/core/card_rule_service.gd:243` `list_legal_targets`：在 `if card == null: return result` 之后补用牌禁令咨询（纯查询、与 `validate_use` 读同一聚合端口），被否决时返回空数组，注释说明「禁令与目标无关，必须早于任何目标枚举」。
- [ ] 3.2 `scripts/core/card_rule_service.gd:379`：把「首个目标没有装备武器」的逐候选错误文本收窄为「仅当该候选确实位于 `all_target_ids[0]` 时报告」，避免给出与实际位置不符的原因。
- [ ] 3.3 验证：`--headless --path . res://tests/qingque_mechanics_test.tscn`（【独弈】用牌禁令专项）。

## 4. 内容层 + 界面层：【自摸】三项（⑤⑦⑩）

- [ ] 4.1 `game_data/skills/zimo.gd:264-295`：把第 1／第 2 位置的枚举改为全体存活角色双循环（照 `chuanchong.gd:155-174` 的写法），逐条仍走 `validate_virtual_use`；注释写明「候选池必须是真实可能，不能把单目标候选池复用为两个位置」。
- [ ] 4.2 `game_data/skills/zimo.gd:202`：请求上下文补 `"ai_choice_skill_scored": true`；`allow_cancel` 改为 `false`，并说明「取消会重开同一询问，因此本步骤在语义上没有可放弃的出口」。
- [ ] 4.3 `game_data/skills/zimo.gd:437-445`：`CHOICE_PICK_EFFECT` 分支改为「构造代理 `use_card` 动作 → `evaluator.score_action` → 加回虚拟牌的幻影保留费用 → 叠加 `AI_COMMIT_REWARD` 确认基线」；新增 1 个常量用于「幻影费用加回」并注明理由。
- [ ] 4.4 `scripts/ui/match_table.gd:5158`：`%CancelButton.visible` 改为读请求的 `allow_cancel`。
- [ ] 4.5 验证：`--headless --path . res://tests/qingque_mechanics_test.tscn` 与 `res://tests/virtual_hand_choice_test.tscn`。

## 5. 界面层：【朱雀羽扇】询问按钮态不再被覆盖

- [ ] 5.1 `scripts/ui/match_table.gd:2391-2395`：把三行按钮回写包进 `if _inline_card_choice.is_empty():`，并保留原有全部注释，新增一段说明「内联询问期间按钮态由询问刷新函数唯一维护」。
- [ ] 5.2 验证：`--headless --path . res://tests/gameplay_regression_test.tscn`（含朱雀羽扇发动请求用例）与 `res://tests/ui_layout_test.tscn`。

## 6. 核心层：过关斩将恢复路径补配阿哈时刻

- [ ] 6.1 `scripts/core/match_controller.gd:15482` 之后：补 `ahha_moment_system.configure(self, state, _rng, true)`，注释说明「与普通开局同构；缺少本次重配会让该局门禁 `_enabled` 恒为 false」。
- [ ] 6.2 验证：`--headless --path . res://tests/conquest_save_test.tscn`。

## 7. 新增与补充断言

- [ ] 7.1 `tests/gameplay_regression_test.gd`：确认 `_test_zhuque_requires_activation_choice` 仍覆盖「先请求、后转换」。
- [ ] 7.2 `tests/qingque_mechanics_test.gd`：补一条【自摸】断言——被禁令影响的牌不再产生目标候选；以及「请求不可取消」时取消按钮声明为不可用（读请求字典即可，不依赖界面节点）。
- [ ] 7.3 若【支离】AI 自指缺少覆盖，在 `tests/zhuyan_zhili_test.gd` 的 AI 用例中补一条最小断言（三人快照 + 自指动作分高于对队友出【杀】），避免只改数值无回归网。

## 8. 文档同步

- [ ] 8.1 `docs/游戏机制与玩法内容.md`：判定顺序（`:570` 等）改为「后来居上」并写明数组仍是置入顺序；借刀杀人所用之【杀】的时机口径（`:744`／`:800`）；过关斩将恢复后阿哈时刻照常生效；【自摸】候选池与「视为使用」的 AI 口径；【支离】代价口径（`:671`）。
- [ ] 8.2 `docs/卡牌系统.md:268`：判定区处理顺序；【借刀杀人】响应动作类别。
- [ ] 8.3 `docs/AI模块.md`：`ai_choice_skill_scored` 新增使用者（【泛音】）；【自摸】的 AI 评分口径（`:410` 附近与【支离】段）。
- [ ] 8.4 `docs/界面与交互.md:212`：判定区显示顺序与结算顺序的关系；取消按钮按声明暗置；虚拟手牌退场渲染不得回写询问按钮态。
- [ ] 8.5 `docs/内容制作指南.md:2225` 等：借刀杀人的「打出」表述改为「使用」；`request_virtual_hand_card_target_selection` 的 `allow_cancel` 用法。
- [ ] 8.6 `docs/架构说明.md`：在「用牌禁令与虚拟手牌选择的架构」一节补充「目标枚举同样咨询禁令」与「虚拟牌不走禁令」两条边界。
- [ ] 8.7 `README.md`：仅在本次改动影响其对外描述时更新（否则不动）。

## 9. 整体验证（质量门）

- [ ] 9.1 `--headless --path . res://tests/smoke_test.tscn`：`GameDatabase.validation_errors` 为空、可正常开局。**注意**：若内容侧技能数／角色数断言因本次改动而变，必须按实际观测值重新基线（本任务不新增武将／技能，理论上不变）。
- [ ] 9.2 依次运行（**同一时刻只跑一个进程**）：`gameplay_regression_test`、`qingque_mechanics_test`、`virtual_hand_choice_test`、`ui_layout_test`、`ai_policy_test`、`conquest_save_test`、`zhuyan_zhili_test`、`new_character_mechanics_test`。
- [ ] 9.3 PASS 判据：退出码 0 **且** 场景自身的 PASS 标记出现 **且** 输出无 `ERROR`／`SCRIPT ERROR`／`FAIL`。
- [ ] 9.4 任何失败都按「真实缺陷」处理，不得放宽断言；测试不稳定时以实际观测值重建期望。

## 10. 交付

- [ ] 10.1 生成「学习反馈摘要」（修改思路／架构与设计／Bug 原因与修复方法／关键代码解析／学习要点提炼 1–3 条）与「Git 提交描述」（数字序号分行、动词开头、每行一个改动）。
- [ ] 10.2 把两者追加写入项目根目录 `临时反馈文档.md`，开头加 `YYYY-MM-DD HH:MM` 时间戳；文件不存在则新建。
- [ ] 10.3 Git 提交。
