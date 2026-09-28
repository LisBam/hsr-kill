# 实施计划：海瑟音（泛音 · 回涛）

> 依赖 `design.md` 与父任务 `implement.md` 的 U1。本批次 = 父任务「批 1」。

---

## 一、步骤

### 步骤 1：权威层 U1 —— 弃置批次聚合

1. `scripts/core/rule_timing_catalog.gd:54` 的 `CARD_MOVE_TIMINGS` 追加 `"cardsDiscardedBatchAfter"`。
2. `scripts/core/match_controller.gd` 新增字段：
   - `_discard_batch_stack: Array[Dictionary]`（每层 `{batch_id, player_id, reason, card_uids}`）
   - `_next_discard_batch_id: int`
3. 新增 `_begin_discard_batch(player_id: int, reason: String) -> int` / `_end_discard_batch() -> void`。
4. `_move_to_discard`（`:13727`）与 `_move_card_with_timings`（`:13754`）：`timing_data` 注入 `discard_batch_id`，并把 uid 追加到栈顶。
5. 五个批量入口包裹批次：`:6226` / `:6251` / `:6299` / `:6600` / `:7869`。

**验证**：`tests/discard_batch_mechanics_test.gd` 通过；`tests/rule_timing_test.gd` 同步更新后通过。

### 步骤 2：内容层 —— 武将文件

`game_data/characters/haishengyin.gd`：

```gdscript
extends CharacterDefinition

## 【泛音】技能脚本；轮回节弃置指定花色，锁定后段按黑/红触发效果。
const FANYIN_SKILL: Script = preload("res://game_data/skills/fanyin.gd")

## 【回涛】技能脚本；观察任意角色轮回推进并令其摸牌。
const HUITAO_SKILL: Script = preload("res://game_data/skills/huitao.gd")

func _init() -> void:
    super({
        "id":"haishengyin",
        "display_name":"海瑟音",
        "gender":"female",
        "faction":"wengfaluosi",
        "max_hp":4,
        "description":"<武将简介>",
    }, [FANYIN_SKILL, HUITAO_SKILL])
```

> 字段名与 `aisida.gd` 保持一致；`faction` 键以 `game_data/factions.json` 实际存在的 `wengfaluosi` 为准。

### 步骤 3：内容层 —— 【泛音】

`game_data/skills/fanyin.gd`，结构参照 `kansha.gd`：

- 顶部常量区：`SECTION_SUITS`、黑色花色集合、AI 权重常量。
- `_init()`：`super({...})`，描述逐字使用 R0 原文。
- `install()` / `uninstall()`：订阅 `cardsDiscardedBatchAfter`（`locked_segment=true`）。
- `can_activate()` / `activate()` / `continue_selection()`：四节主动段。
- `_execute_section()`：`begin` → 弃置 → `complete` → `announce`。
- `_on_cards_discarded_batch()`：整批判色 → 先黑后红 → 两段异步串行。
- `restore_limited_use()`：覆写并清私有已用集合。
- AI：`append_play_phase_actions` / `score_ai_action` / `score_ai_choice`。

**实现时需确认的现有端口**（读代码后填写，不得臆造）：
- 花色字段取值（`card.suit` 的稳定字符串集合）；
- 「有手牌的角色」候选查询端口；
- 「令指定玩家选择并弃置手牌」的既有请求函数名（`request_card_selection_for_player` 或等价物）；
- 「摸一张牌」的公开端口名。

### 步骤 4：内容层 —— 【回涛】

`game_data/skills/huitao.gd`：

- 常量 `MIN_SECTION_COUNT_FOR_HUITAO = 3`。
- `install()`：订阅 `reincarnationStart`（`role="global"`）。
- 回调按 `design.md` 第三节的三重判定 → 询问 → 摸牌 → `announce_activation`。
- `score_ai_choice`：对己方无脑发动。

### 步骤 5：测试

新建 `tests/haishengyin_mechanics_test.gd` + `.tscn`，覆盖 `design.md` 第六节的 7 项。
同时新建 `tests/discard_batch_mechanics_test.gd` + `.tscn`（权威层 U1 的独立验证）。

### 步骤 6：文档同步

- `docs/内容制作指南.md`：技能表新增两行、轮回章节补充新时机与「半锁定轮回技」写法。
- `docs/游戏机制与玩法内容.md`：海瑟音机制与全部数值（4 节花色顺序、黑色弃牌数=1、红色摸牌数=1、回涛门槛=3）。
- `docs/AI模块.md`：两技能 AI 策略。
- `README.md`：测试清单。
- `.trellis/spec/`：如含技能层规范则补新时机。

### 步骤 7：交付物

1. 学习反馈摘要（修改思路 / 架构与设计 / 关键代码解析 / 学习要点提炼）。
2. Git 提交描述（数字序号，单点单行）。
3. 两者按「先摘要、后提交描述」追加到 `临时反馈文档.md`，带 `YYYY-MM-DD HH:MM` 时间戳。

---

## 二、验证命令

```powershell
& 'E:\Godot\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe' --headless --path . --scene res://tests/discard_batch_mechanics_test.tscn
& 'E:\Godot\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe' --headless --path . --scene res://tests/haishengyin_mechanics_test.tscn
```

**通过判定**：退出码 `0` + 输出含对应 PASS 标记 + 无 `ERROR` / `SCRIPT ERROR` / `FAIL`。测试**串行**执行，日志落 `.godot_test_logs/`。

---

## 三、回归矩阵（本批必跑）

| 测试 | 目的 |
|---|---|
| `rule_timing_test` | 时机目录新增项 |
| `reincarnation_mechanics_test` | 轮回推进未被破坏 |
| `new_character_mechanics_test` | 半锁定技元数据 |
| `gameplay_regression_test` | 弃置与逐目标时序 |
| `smoke_test` | 数据库与资源完整性 |

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| 批次栈在弃置中途抛错未弹出 | `_end_discard_batch` 放在保证执行的位置；测试覆盖技能嵌套弃置 |
| 泛音黑色效果的目标范围理解偏差（是否含自己） | 实现时以「有手牌的角色（含自己）」为准并在交付说明中标注；如用户另有裁定再调整 |
| 四节花色在长期对局中难以走完 | 沿用 `kansha.gd` 既有先例；交付说明中提示该设计取向 |

**回滚点**：权威层 U1 与本批内容层分两次提交，可独立 revert。
