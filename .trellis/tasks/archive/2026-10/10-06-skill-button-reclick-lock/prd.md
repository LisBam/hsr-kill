# 修复技能发动过程中可再次点击技能按钮导致跳段/中止

## Goal

技能自己发起的选牌 / 选目标 / 文字选项请求仍在进行时，**该技能自己的按钮必须失效并忽略点击**（保留"这条流程正在进行"的金色选中描边），使全部同类技能统一为"发动中不可再次点击"；取消一律由操作区既有的"取消"按钮 / Esc / 右键表达。消除玩家点一下技能按钮就"整次发动被中止"或"直接跳到下一段"的问题。

## Background and confirmed facts

### 用户报告与实测口径

- 用户报告：丹恒·饮月在"询问是否弃置并选择牌和目标"期间点击右下角技能按钮，会直接进入下个阶段。
- 探针实测（临时场景 `tests/zz_probe_skill_reclick_test.*`，验证后删除）：
  - 【伏辰】`game_data/skills/fuchen.gd:25` 是 `ui_enabled:false` 的完整锁定技，按钮恒为 `disabled=true`，点击不产生任何动作。技能栏按武将 `skills` 顺序**从右到左**排布（`scripts/ui/skill_button_grid.gd:42-64`），因此报告中的"右下角按钮"实际是同一技能栏里的【濯世】按钮。
  - 【濯世】第①段 `zhuoshi_cost_and_target`（`game_data/skills/zhuoshi.gd:143`，`allow_cancel=true`）期间再次点击 → 整次发动被静默中止：阶段额度未消费、手牌未变、回到出牌阶段。
  - 【濯世】第②段费用询问 `zhuoshi_second_cost`（`game_data/skills/zhuoshi.gd:318`）期间再次点击 → 命中 `game_data/skills/zhuoshi.gd:188-192`，**直接进入第③段**，即用户描述的"直接进入下个阶段"。
  - 【濯世】第③段费用询问 `zhuoshi_third_cost`（`game_data/skills/zhuoshi.gd:342`）期间再次点击 → 整条流程结束。

### 现状实现（缺陷根因）

- `scripts/ui/match_table.gd:2465 _get_selected_skill_release_id()`：当内联请求 `allow_cancel=true` 且其 `context.skill_id` 指向一个 `ui_enabled=true` 的技能时返回该技能 ID。
- `scripts/ui/match_table.gd:2195` 与 `:2225`：该返回值被用作"按钮可用"的一个或条件，于是发动中的技能按钮保持"可点击 + 金色选中"。
- `scripts/ui/match_table.gd:2437-2439`：第二次点击被转成 `_cancel_originating_inline_skill_release()`（`:2483`），提交 `confirmed=false`。
- 影响面：`game_data/skills/` 共 34 个技能声明 `ui_enabled=true`（拥有技能按钮），其中凡是在 `activate()` 或时机回调里创建 `allow_cancel=true` 请求的技能都会走进这条缺陷路径（【濯世】【药理】【咬它】【追歼】【安打】【传冲】【罡风】【全垒】【自摸】等）；`ui_enabled=false` 的触发型技能（如【冰封】`game_data/skills/bingfeng.gd:27`、【坚垒】`game_data/skills/jianlei.gd:12`）没有按钮，不受影响。

### 取消出口仍然完备

- `scripts/ui/match_table.gd:6013-6014`：`allow_cancel=true` 的内联请求显示并启用"取消"按钮。
- `scripts/ui/match_table.gd:3718-3721 _on_cancel_pressed()`：提交与技能按钮二次点击**完全相同**的 `confirmed=false`，因此移除按钮二次点击不丢失任何能力。
- 文字选项请求 ≥2 项且允许放弃时，界面还会追加真正的取消按钮（`scripts/ui/match_table.gd:6099-6100`）。
- `context.hide_cancel_button` 场景（`game_data/skills/zimo.gd:222`）的取消语义本身就是"重开同一询问"，按钮失效不影响玩家推进流程。

### 不在本次范围的相关既有语义

- 响应转化技能（`_active_response_skill_id`，`scripts/ui/match_table.gd:2427-2435`）的第二次点击是"退出材料转化模式"的开关，不属于技能发动流程，保持原样。

## Requirements

- **R1 发动中按钮失效**：当某个技能自己发起的统一选择请求仍在进行时，该技能的按钮必须处于禁用状态（不响应点击、不显示可点击手型），且**不再**把点击转换为取消响应。
- **R2 保留进行中视觉**：该技能按钮仍以金色选中描边表达"这条流程正在进行"，不因禁用而变成与其他灰显技能完全相同的样式。
- **R3 判定与取消语义解耦**：按钮失效的判定只取决于"该请求是否仍由这个技能持有"，与 `allow_cancel` 取值无关；`allow_cancel` 继续只决定"取消按钮是否可用"。
- **R4 取消路径不变**：取消仍由操作区"取消"按钮（以及既有 Esc / 右键路径）提交 `confirmed=false`，规则层收到的取消响应与现状逐字一致。
- **R5 全技能统一**：出牌阶段主动技、触发型技能、多段技能一律遵守 R1；不再存在"某些技能可二次点击取消、另一些不可点击"的差异。
- **R6 其他按钮不受影响**：非本次发动技能的按钮继续只由 `can_activate_skill()` 权威门禁决定可用性；响应转化技能的材料模式切换语义不变。
- **R7 死代码清理**：移除只服务于旧二次点击取消语义的函数与分支，不保留不再被调用的入口。
- **R8 回归与文档同步**：改写现有断言"二次点击取消"的用例为"二次点击被忽略 + 取消按钮仍可取消"，并覆盖多段技能"不再跳段"；同步 `docs/` 四份文档、`.trellis/spec/content/skill-authoring.md` 与 `临时反馈文档.md`。

## Acceptance Criteria

- [ ] 技能发起的可取消内联请求进行中时，该技能按钮 `disabled=true` 且 `is_skill_selected=true`；强制调用 `_on_skill_requested(<该技能>)` 不产生任何提交（待处理请求仍在、请求 ID 与 `context.kind` 不变、手牌与 `action_sequence` 不变）。
- [ ] 同一场景下点击"取消"按钮仍能提交 `confirmed=false`：待处理请求被清空、材料仍在原手牌、出牌请求重新开放。
- [ ] 【濯世】第②段费用询问 `zhuoshi_second_cost` 期间点击技能按钮后，待处理请求仍是 `zhuoshi_second_cost`（不跳到 `zhuoshi_third_cost`），目标手牌与阶段额度均未变化。
- [ ] 【伏辰】等 `ui_enabled=false` 的锁定技按钮行为不变（恒禁用、点击无动作）。
- [ ] 响应转化技能第二次点击退出材料模式的既有断言仍通过。
- [ ] `tests/skill_target_ui_test.tscn`、`tests/danheng_yinyue_mechanics_test.tscn`、`tests/inline_hand_choice_test.tscn`、`tests/ui_layout_test.tscn` 全部通过。
- [ ] `docs/卡牌系统.md`、`docs/界面与交互.md`、`docs/架构说明.md`、`docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md` 与 `.trellis/spec/content/skill-authoring.md` 中关于"二次点击取消"的描述全部改写为"发动中按钮失效、取消由取消按钮表达"。
- [ ] 临时探针文件 `tests/zz_probe_skill_reclick_test.gd/.tscn` 已删除，不留在仓库中。
- [ ] `临时反馈文档.md` 已按规范追加学习反馈摘要与 Git 提交描述。

## Out of Scope

- 规则层（`MatchController`、`SkillDefinition`、各技能脚本）的 `allow_cancel` 语义与取消响应处理不做任何改动。
- 不把整个技能栏在技能流程期间禁用（用户 2026-10-06 明确选择仅失效"正在发动中的那个技能"）。
- 不改动响应转化技能的材料模式开关语义。
- 不改动已禁用的锁定技 / 被动技能按钮的灰显与悬停说明行为。
- 不改动 AI 侧行为（AI 不经过技能按钮）。

## Key Decisions

- **失效范围**：仅"拥有当前进行中请求的那个技能"的按钮（用户选择，推荐项）。
- **视觉表达**：保留金色选中描边 + 灰色禁用底色，让玩家能看出"这条流程属于该技能，但此刻不能点"。
- **判定依据**：由"请求上下文里的 `skill_id` 是否等于该技能且该技能有按钮"决定，不再要求 `allow_cancel=true`。
- **取消唯一入口**：操作区"取消"按钮（含既有 Esc / 右键路径），规则层语义零改动。
