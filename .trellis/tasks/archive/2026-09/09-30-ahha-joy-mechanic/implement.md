# 阿哈时刻与欢愉技机制 — 执行计划

> 设计见同目录 `design.md`；需求与验收见 `prd.md`。

---

## 一、实施顺序

严格按「内容基类 → 服务组件 → 控制器接线 → 加载校验 → 测试」推进：每一步都能单独编译通过，且不破坏现有行为。

### 步骤 1：内容基类扩展
1. `game_data/skill_definition.gd` 新增 `JOY_SKILL_TAG` 常量、`joy_skill` / `performance_number` 成员。
2. `_init()` 末尾（`reincarnation` 段之后）写入两个元数据键。
3. 新增 `is_joy_skill()` / `get_performance_number()` / `can_perform_joy_skill()` / `perform_joy_skill()` / `finish_joy_skill_performance()`。
4. 新增静态 `description_declares_joy_type(description)`。

**验证点**：任意现有技能实例 `is_joy_skill()` 返回 `false`、`get_performance_number()` 返回 `0`。

### 步骤 2：加载校验
5. `scripts/autoload/game_database.gd` 的 `_load_skills()` 中，在轮回技双向校验之后追加欢愉技双向校验（正文声明 ⟺ `joy_skill` 标签），并校验欢愉技的 `performance_number >= 1`。

**验证点**：`smoke_test` 仍 PASS（现有技能无「欢愉技」正文，校验零命中）。

### 步骤 3：服务组件
6. 新建 `scripts/core/ahha_moment_system.gd`：常量 → `@export`/常量参数 → 状态字段 → `_ready()` → `configure()` / `shutdown()` / `is_active()` → `build_performance_order()` → `try_trigger_before_turn_start()` → 执行与续接 → `_initialize_round_probability()`。

**验证点**：脚本可解析（编辑器无脚本错误）；用临时测试直接构造组件调用 `build_performance_order` 返回空数组。

### 步骤 4：控制器接线
7. 新增成员与 `_ready()` 创建（照 `:680`-`:684`）。
8. 开局配置与 `shutdown()`（照 `:1339` / `:1410` / `:1525`）。
9. 新增 `_continue_turn_start_prelude()`，把三处调用点收敛过去（`:10602`、`:13037`、`:13086`）。
10. 新增 `continue_after_ahha_moment()` 与 `defer_ahha_moment_resolution()`。
11. 停滞自修复软推分支追加阿哈时刻轻推（`:1003` 附近）。

**验证点**：跑 `phase_progression_test` 与 `event_runtime_test`（回合开始前链路守门测试）。

### 步骤 5：专项测试
12. 新建 `tests/ahha_moment_test.gd` + `tests/ahha_moment_test.tscn`（含测试内探针欢愉技）。
13. `README.md`「自动校验」章节补一行说明。

---

## 二、验证命令

```powershell
$GODOT = 'E:\Godot\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe'

# 本子任务专项
& $GODOT --headless --path . res://tests/ahha_moment_test.tscn
# 回合开始前链路守门
& $GODOT --headless --path . res://tests/phase_progression_test.tscn
& $GODOT --headless --path . res://tests/event_runtime_test.tscn
# 机缘零回归
& $GODOT --headless --path . res://tests/opportunity_system_test.tscn
# 内容与开局
& $GODOT --headless --path . res://tests/smoke_test.tscn
& $GODOT --headless --path . res://tests/skill_settlement_runtime_test.tscn
```

判定：输出出现对应 `*_PASS` 标记；报告中粘贴实际输出行。

---

## 三、风险文件与回滚点

| 文件 | 风险等级 | 回滚方式 |
|---|---|---|
| `scripts/core/match_controller.gd` | **高**（阶段推进敏感路径） | 三处收敛点逐一还原为原始调用；`git diff` 只应包含两个新端口 + prelude + 三处调用替换 + 自修复一行 |
| `scripts/core/ahha_moment_system.gd` | 低（全新文件） | 删除文件与成员引用 |
| `game_data/skill_definition.gd` | 中（基类，全项目受影响） | 新增内容全部为追加，删除即回滚 |
| `scripts/autoload/game_database.gd` | 中（校验失败会拒绝开局） | 追加的校验段落删除即回滚 |

**回滚触发条件**：`phase_progression_test` 或 `event_runtime_test` 失败且 30 分钟内无法定位到本次改动之外的既有缺陷。

---

## 四、`task.py start` 前复查

- [ ] `prd.md` / `design.md` / `implement.md` 无 TBD
- [ ] 与子任务②③的接口约定已对齐（`perform_joy_skill` / `is_joy_skill` / `finish_joy_skill_performance` 的签名不再变动）
- [ ] 探针欢愉技的构造方式已在设计阶段确认可行（测试内子类化 `SkillDefinition`）
