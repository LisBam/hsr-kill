# 武将火花与技能好戏连戏 — 执行计划

> 设计见同目录 `design.md`；需求与验收见 `prd.md`。**前置依赖：子任务①与子任务②的接口已就位。**

---

## 一、实施顺序

### 步骤 0：前置接口确认（阻塞检查）
1. 确认 `SkillDefinition.is_joy_skill()` / `get_performance_number()` / `perform_joy_skill()` / `finish_joy_skill_performance()` 已存在（子任务①）。
2. 确认 `MatchController.recast_hand_cards(player_id, card_uids) -> int` 已存在（子任务②）。
3. 确认 `pick_random_candidate_index` / `gain_draw_pile_card_by_uid` / `discard_selected_player_cards` 的签名与设计一致。

> 三项任一未就位则**停止本子任务**，先完成依赖子任务。

### 步骤 1：势力
4. `game_data/factions.json` 末尾追加欢愉势力记录。

**验证点**：`smoke_test` PASS，势力校验无新增错误。

### 步骤 2：武将文件
5. 新建 `game_data/characters/huohua.gd`（元数据 + 两个技能 preload）。

**验证点**：`smoke_test` PASS；`GameDatabase.validation_errors` 为空（技能引用有效）。

### 步骤 3：【好戏】
6. 新建 `game_data/skills/haoxi.gd`：常量 → 元数据 → `can_perform_joy_skill()` → `perform_joy_skill()` → `continue_selection()` → 效果结算 → 屏障收尾 → `continue_settlement()` → `score_ai_choice()`。

**验证点**：技能可解析；阿哈时刻中可被 `build_performance_order` 收录（编号 144）。

### 步骤 4：【连戏】
7. 新建 `game_data/skills/lianxi.gd`：常量 → 元数据 → `can_activate()` → `activate()` → 重铸轮次状态机 → `continue_selection()` → `continue_settlement()` → `append_play_phase_actions()` / `score_ai_action()` / `score_ai_choice()`。

**验证点**：出牌阶段技能栏出现【连戏】按钮且能发动；重铸与伤害数值正确。

### 步骤 5：测试与文档
8. 新建 `tests/huohua_joy_test.gd` + `.tscn`。
9. `README.md`「自动校验」章节补一行。
10. 同步 `docs/游戏机制与玩法内容.md`（全部数值）与 `docs/内容制作指南.md`（两个技能的接口用法与配套 AI 口径）。

---

## 二、验证命令

```powershell
$GODOT = 'E:\Godot\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe'

# 本子任务专项
& $GODOT --headless --path . res://tests/huohua_joy_test.tscn
# 内容校验与开局（势力/武将/技能引用）
& $GODOT --headless --path . res://tests/smoke_test.tscn
# 阿哈时刻机制（子任务①，端到端验证【好戏】被正确驱动）
& $GODOT --headless --path . res://tests/ahha_moment_test.tscn
# 多张重铸（子任务②，端到端验证【连戏】的移动语义）
& $GODOT --headless --path . res://tests/multi_recast_test.tscn
# AI
& $GODOT --headless --path . res://tests/ai_policy_test.tscn
# 内容层回归
& $GODOT --headless --path . res://tests/new_character_mechanics_test.tscn
& $GODOT --headless --path . res://tests/card_action_semantics_test.tscn
```

---

## 三、风险文件与回滚点

| 文件 | 风险等级 | 回滚方式 |
|---|---|---|
| `game_data/factions.json` | 中（格式错误会导致全体武将校验失败、拒绝开局） | 删除追加的那一行 |
| `game_data/characters/huohua.gd` | 中（技能引用错误会导致开局拒绝） | 删除文件 |
| `game_data/skills/haoxi.gd` | 中（会改变阿哈时刻的实际执行内容） | 删除文件 |
| `game_data/skills/lianxi.gd` | 中（新增出牌阶段主动入口） | 删除文件 |

**回滚触发条件**：`smoke_test` 因 `validation_errors` 非空而失败，或【连戏】出现「发动后无法结束 / 弹窗循环」类流程卡死。

---

## 四、`task.py start` 前复查

- [x] 子任务①②均已通过各自验收（接口已冻结）
- [x] `prd.md` / `design.md` / `implement.md` 无 TBD
- [x] 两技能的 `description` 已与需求原文逐字比对（含全角括号、半角连字符、`X`/`Y` 占位符）
- [x] 配套补全项（候选目标范围、无基本牌时不可发动、欢愉技 `lock=false`）已在交付说明中单列
