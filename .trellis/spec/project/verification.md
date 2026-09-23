# 验证与测试

> 来源：`README.md`「运行方式 / 自动校验」、`docs/内容制作指南.md`。

---

## 一、环境

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.6.3**（或兼容的 Godot 4.6 版本） |
| 构建 | `4.6.3.stable.mono`（项目历史验证所用构建） |
| 打开方式 | 用 Godot 打开 `project.godot` |
| 主场景 | `res://scenes/main.tscn` |

---

## 二、运行测试

项目**不使用**外部测试框架，测试即场景：每个 `tests/*_test.tscn` 自带脚本，运行后自行断言并打印 `*_PASS` 标记。

- **编辑器方式（权威、推荐）**：打开 `project.godot`，运行 `res://tests/<名称>_test.tscn`。
- **命令行等价形式**：
  ```bash
  godot --headless --path . res://tests/smoke_test.tscn
  ```
  将 `godot` 替换为本机实际的 Godot 可执行文件路径；`--headless` 适用于不依赖图形界面的用例。

> 多数用例使用固定随机种子、不依赖图形界面，因此可在无头模式回归。

---

## 三、测试场景职责（节选，完整列表见 `README.md`）

| 场景 | 覆盖重点 |
|---|---|
| `smoke_test.tscn` | 牌堆、牌名模式、随机身份与座次、纯 AI 对局整体烟雾测试 |
| `event_runtime_test.tscn` | `GameEvent` 父子事件、`next/after`、暂停通道、终止三态、递归深度保护 |
| `skill_settlement_runtime_test.tscn` | 分片内层时机、因果链上限、通用规则续接三层保护 |
| `gameplay_regression_test.tscn` | `CardUseEvent` 父子关系、五组使用时机、逐目标时机、无懈与八卦阵时序 |
| `phase_progression_test.tscn` | 阶段跳过、翻面、濒死救援后的唯一后续恢复 |
| `ai_policy_test.tscn` | 卡牌 AI 完整性、静态缓存、身份战略、响应与濒死决策 |
| `performance_and_pacing_test.tscn` | 速度边界、长局内存上界、各类索引与缓存上限 |
| `ui_layout_test.tscn` | 1152×648 下全部界面布局、悬停信息框、技能栏对齐 |
| `font_color_audit_test.tscn` | 遍历主场景全部文本控件，**缺失统一主题字体色即失败** |
| `main_menu_test.tscn` | 主菜单入口、图鉴、设置与重开流程 |
| `opportunity_system_test.tscn` | 机缘卡目录、品质权重、观察者定向候选快照 |
| `conquest_*` / `wheel_duel_*` / `doudizhu_*` / `team2v2_*` | 各模式规则本体 |
| `lan_*` / `match_chat_test.tscn` / `match_replay_test.tscn` | 联机、聊天、回放（部分会派生第二个 Godot 进程，需允许本机 UDP 回环） |

> 历史回归输出形如 `SMOKE_PASS running phase=choice turn=24 actions=156`、`AI_POLICY_PASS cards=46`。注意其中的数字是**当时的快照**，会随内容增长变化，不要当作固定期望值。

---

## 四、数据校验边界（内容改动的第一道关）

`GameDatabase` 在 `_ready()` 时执行 `reload_all()`，按**技能 → 卡牌 → 武将 → 牌堆 → 势力**顺序载入并校验：

- 检查继承类型是否正确、`id` 是否非空且全项目唯一。
- 检查武将的技能引用、势力引用、牌堆卡牌引用是否有效。
- 任一错误写入 `GameDatabase.validation_errors`（`Array[String]`）。
- **`validation_errors` 非空时 `MatchController.start_match()` 拒绝开局。**

因此内容改动的最低验收标准是：**能正常开局**，且 `validation_errors` 为空。

---

## Quality Check

- [ ] 至少运行了一个与本改动直接相关的 `res://tests/*_test.tscn`，且结果为 PASS。
- [ ] 涉及规则/内容改动时，已确认 `GameDatabase.validation_errors` 为空、可正常开局。
- [ ] 涉及界面改动时，已跑 `ui_layout_test.tscn`；新增文本控件时已跑 `font_color_audit_test.tscn`。
- [ ] 涉及 AI 改动时，已跑 `ai_policy_test.tscn`。
- [ ] 涉及性能敏感路径（长局历史、快照、索引）时，已跑 `performance_and_pacing_test.tscn`。
- [ ] 新增测试场景后，已在 `README.md`「自动校验」章节补充说明。
- [ ] 报告中给出**实际观察到的输出**，不写「应该通过」这类推测性结论。
