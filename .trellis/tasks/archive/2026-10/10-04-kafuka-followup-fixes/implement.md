# 实施记录 · 卡芙卡交付后的三项收口修正

任务目录：`.trellis/tasks/archive/2026-10/10-04-kafuka-followup-fixes/`
父任务：`10-02-kafuka-new-mechanics`
提交：`c3e567a`（时机）、`27922e6`（交互）、`631f149`（永久失去名单）、`6db5420`（文档与规范）、`89bbe80`（资源）

## 一、需求一 · 位次询问改用操作区内联交互

| 文件 | 改动 |
|---|---|
| `scripts/ui/match_table.gd` | `_is_inline_control_choice()` 接受 `card_position`；`_refresh_inline_control_choice_text()` 增加逐项可用性判定与额外选项按钮；新增 `_is_inline_control_card_selection_ready()`、`_get_inline_control_cancel_option_id()`、`_is_inline_control_option_submittable()`；删除 `card_selection_panel.position_submitted` 连接与 `_on_card_position_submitted()` |
| `scripts/ui/card_selection_panel.gd` | 删除 `position_submitted` 信号、位次按钮集合、`_show_card_position_request()`、`_add_position_options()`、两个位次回调与 `card_position` 渲染分支（净删 106 行） |
| `game_data/skill_definition.gd` | `request_hand_card_pile_position()` 注释改为内联交互口径 |
| `tests/exclusive_card_and_private_placement_test.gd` | `_test_panel_three_option_usability()` 重写为 `_test_inline_three_option_usability()`，阶段标记 `panel_usability` → `inline_usability` |

**契约不变**：选择类型、三个稳定选项、取消声明键（`control_cancel_option_id`）、`min_card_select = max_card_select = 1`、`confirmed=false` 不做牌数校验，全部沿用；位次询问的权威校验与 AI 动作枚举未改动。

## 二、需求二 · 永久失去改为按技能ID名单清算

| 文件 | 改动 |
|---|---|
| `scripts/data/player_state.gd` | 新增 `permanently_removed_skill_ids`、`mark_skill_permanently_removed()`、`has_permanently_removed_skill()`；`to_dict` / `from_authoritative_dict` 往返；旧布尔标记保留为迁移与旧版本降级用 |
| `scripts/core/match_controller.gd` | `remove_all_skills_permanently()` 改为逐项快照 + 记名单 + 清空 `recorded_card_names`；五条装配路径逐项拦截；两个重置端口移除整体拦截；`_install_all_character_skills()` 增加旧存档迁移；`restore_character_card_skills()` 增加逐项跳过 |
| `scripts/ui/match_table.gd` | `_get_visible_skill_ids()` 按名单逐项剔除（含模式技能） |
| `scripts/ui/player_target_view.gd` | 技能列表与视觉快照按名单逐项剔除；角标不再按整体标记清空 |
| `game_data/skills/shengbian.gd` | 军功触发评分按名单逐项过滤固有技能与模式技能 |
| `tests/nakexia_mechanics_test.gd` | 三个阶段改为按名单语义，并新增「清算后新获得技能照常安装与发动」断言 |

**语义边界**：名单内的技能永久不可再装配；名单之外的技能（机缘卡、军功、清算后换将的新武将技能）不受影响。旧存档迁移只发生一次（布尔为真且名单为空时补记当时本应安装的技能）。

## 三、需求三 · 「游戏开始时」更正为正式开局时刻

| 文件 | 改动 |
|---|---|
| `scripts/core/match_controller.gd` | `_complete_pre_game_start()` 成为 `gameStart` 的唯一派发点（起始手牌与手气卡之后、第一轮之前） |
| `game_data/skills/yanling.gd` | 先 `announce_activation({"insert_count":3, "insert_position":0})` 再逐张插牌 |
| `scripts/core/rule_timing_catalog.gd` | `gameStart` 顺序后移到 `gameDrawAfter` 之后 |
| `tests/kafuka_mechanics_test.gd` | 新增 `gameStartTimingAfterMulligan` 阶段 |

## 四、验证

- 全量 82 个测试场景连跑（`.godot_test_logs/full_regression_item12.txt`）：除 `audio_system_test` 在整批连跑中偶发失败外，其余全部 PASS；该用例随后单独连跑 2 次均为 `AUDIO_SYSTEM_PASS`，且本批次未改动任何音频文件
- `android_adaptation_test` 使用独立成功标记，单独运行输出 `ANDROID_ADAPTATION_TEST_OK`
- 关键场景复跑：`NAKEXIA_MECHANICS_PASS`（含 `permanent_loss=2 permanent_new_skill=1`）、`EXCLUSIVE_CARD_PRIVATE_PLACEMENT_PASS`（含 `inline_usability`）、`KAFUKA_MECHANICS_PASS`（含 `gameStartTimingAfterMulligan`）、`RULE_TIMING_PASS catalog=236`、`PRE_GAME_CUSTOMIZATION_PASS`
- 反事实验证：把 `grant_acquired_skill()` 的守卫改回整体布尔量 → `NAKEXIA_FAIL permanent_new_skill_blocked`，改动已还原
- 文档同步：`docs/界面与交互.md`、`docs/游戏机制与玩法内容.md`、`docs/内容制作指南.md`、`docs/架构说明.md`、`README.md`、`.trellis/spec/content/skill-authoring.md`、`.trellis/spec/guides/code-reuse-thinking-guide.md`

## 五、遗留

- 卡芙卡的技能/阵亡语音素材仍缺（与旧布尔量无关的既有事项）
- 其他文字选项询问（`control` / `bool` / `target_control`）尚未补充「未满足手牌维度时按钮禁用」的专项断言
