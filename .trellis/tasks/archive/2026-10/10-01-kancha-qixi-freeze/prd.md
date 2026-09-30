# 修复额外出牌节点下堪杀触发奇袭导致的对局卡死

## Goal

佩拉的【秘策】令刻律德菈获得一个独立额外出牌阶段后，刻律德菈在该阶段发动【堪杀】并触发【奇袭】，此时【奇袭】的“然后”步骤不会结算，额外出牌阶段之后的流程无法正常收尾。本任务定位并修复该缺陷。

## Requirements

- 复现必须走正式入口：`_on_phase_end` → 秘策复合选择 → `request_extra_play_phase` → 额外出牌阶段 → `get_legal_actions` 提交【堪杀】→ 观察【奇袭】的延后结算是否被执行。
- 必须覆盖三种轮回节（①红牌 / ②黑牌 / ③伤害）与两条入口（直接动作 / AI 正式驱动）。
- 根因必须落在通用结算管线或通用阶段机制上，不得为【奇袭】或【堪杀】单开专用绕过分支。
- 修复必须保证：只要统一结算队列中仍有明确待办，就一定有唤醒者；禁止出现“队列非空但没有任何已登记回调”的状态。
- 必须保留既有的子阶段门控语义（父序列仍要等待独立子阶段完成），不得用“提前排空”破坏结算顺序。
- 同步文档：`docs/内容制作指南.md` 的结算管线与延后唤醒说明、`docs/游戏机制与玩法内容.md` 的额外出牌阶段条目、`README.md` 的专项测试说明。

## Acceptance Criteria

- [ ] 有回归用例证明：秘策额外出牌阶段内发动【堪杀】触发【奇袭】后，`_deferred_skill_settlements` 会被排空（而不是长期滞留 1 条）。
- [ ] 同一用例证明【奇袭】的“进入下一个轮回节”真实生效（轮回节索引按规则推进）。
- [ ] 同一用例证明额外出牌阶段结束后控制权回到秘策持有者的结束阶段，且不会被卡在子阶段等待状态。
- [ ] 既有 `new_character_mechanics_test` 的秘策两种阶段顺序、`omphalos_transform_test` 的堪杀/奇袭断言全部继续通过。

## Notes

- 已确认的现场证据：在无任何门控待办的静止状态下，`_deferred_skill_settlements` 仍有 1 条（技能持有者1、技能`qixi`），而 `_settlement_resume_scheduled == false`、`_settlement_pipeline_running == false`、`_rule_continuations` 为空、无待选请求；手工调用 `_resume_settlement_pipeline()` 一次即可排空并让轮回节推进。说明唤醒者在“入口作废旧唤醒 + 本轮同步排空提前返回”的组合中丢失。
- 相关文件：`scripts/core/match_controller.gd`（`_resume_settlement_pipeline`、`_run_settlement_pipeline_pass`、`defer_skill_settlement`）、`game_data/skills/qixi.gd`、`game_data/skills/kansha.gd`、`game_data/skills/mice.gd`。
