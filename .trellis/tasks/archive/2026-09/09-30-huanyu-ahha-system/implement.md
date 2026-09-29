# 欢愉派系与阿哈时刻体系 — 执行计划

> 设计见同目录 `design.md`；需求与验收见 `prd.md`。

---

## 一、执行顺序与子任务

父任务**不直接改产品代码**；它负责集成、跨子任务验收与最终评审。实际改动全部落在三个子任务里，按以下顺序推进（顺序由接口依赖决定）：

```text
① 09-30-ahha-joy-mechanic    核心：SkillDefinition 欢愉技参数 + AhhaMomentSystem + 回合开始前事件链
        ↓（提供 perform_joy_skill / is_joy_skill / 阿哈时刻执行管线）
② 09-30-multi-recast-mechanic 核心：recast_hand_cards 多张重铸端口
        ↓（提供 【连戏】所需的权威端口）
③ 09-30-huohua-character      内容：欢愉势力 + 武将火花 + 【好戏】【连戏】
        ↓
④ 父任务：集成验证 + 文档同步 + 提交
```

①与②互不依赖，可并行实现；③必须等①与②的接口就位。

**每个子任务的完成标准**：其 `prd.md` 的验收条目全部可观察地成立，且属于它的相关测试场景 PASS。子任务由父任务在集成阶段逐个验收，**未通过验收的子任务不得归档**。

---

## 二、验证命令

本机 Godot（4.6.1 mono，命令行请用 `_console` 版以取得 stdout）：

```bash
GODOT='E:/Godot/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe'
"$GODOT" --headless --path . res://tests/<场景>.tscn
```

PowerShell 等价形式：

```powershell
& 'E:\Godot\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe' --headless --path . res://tests/smoke_test.tscn
```

测试自带断言并打印 `*_PASS` 标记；判定标准是输出中出现该标记且进程正常退出。

### 必跑回归（父任务集成门）

| 场景 | 为什么必须跑 |
|---|---|
| `res://tests/smoke_test.tscn` | `GameDatabase.validation_errors` 为空、能正常开局；新势力/武将/技能不破坏内容校验 |
| `res://tests/gameplay_regression_test.tscn` | 重铸边界（木牛粮不可重铸）与卡牌流程未受影响 |
| `res://tests/card_action_semantics_test.tscn` | 「重铸」必须仍不构成使用/打出/弃置，且日志只出现「重铸了」 |
| `res://tests/phase_progression_test.tscn` | 回合开始前事件链改动后，阶段推进与唯一后续恢复未被破坏 |
| `res://tests/event_runtime_test.tscn` | 事件父子、暂停通道、续接未被附加流程破坏 |
| `res://tests/skill_settlement_runtime_test.tscn` | 通用规则续接三层保护仍然成立 |
| `res://tests/opportunity_system_test.tscn` | 机缘行为零改动（阿哈时刻插入其之后，不得影响其触发与结算） |
| `res://tests/ai_policy_test.tscn` | 新增两个技能的 AI 钩子不破坏基础 AI 完整性 |

### 子任务专项测试

| 子任务 | 新增场景 |
|---|---|
| ① | `res://tests/ahha_moment_test.tscn`（新增）：触发概率、每轮一次、与机缘独立、无可执行欢愉技时跳过且不消耗随机数、排序规则（编号升序 + 同编号座次正序）、死亡/离场跳过 |
| ② | `res://tests/multi_recast_test.tscn`（新增）：多张一次重铸、摸等量牌、不产生弃置语义、重复 UID 去重、非手牌 UID 拒绝 |
| ③ | 在既有 `res://tests/new_character_mechanics_test.tscn` 或新增场景中覆盖【好戏】X 张数与【连戏】重铸/伤害公式 |

> 新增测试场景后，按 `verification.md` 的要求在 `README.md`「自动校验」章节补一行说明。

### 内容校验的最低门槛

任何内容改动后，`GameDatabase.validation_errors` 必须为空（`smoke_test` 会暴露）。**这是不可绕过的第一道关。**

---

## 三、风险文件与回滚点

| 文件 | 风险 | 回滚点 |
|---|---|---|
| `scripts/core/match_controller.gd` | 回合开始提前置链（`:10567` / `:13071` / `:13011` 三处收敛）与停滞自修复分支（`:999`）都是敏感路径 | 改动前的 `git diff` 快照；任一必跑回归失败即回滚该文件到改动前状态 |
| `scripts/core/match_controller.gd`（重铸段） | 单张 `recast_hand_card` 日志文本或语义被改动 | 保留单张路径的日志与返回类型不变，多张走独立分支 |
| `game_data/skill_definition.gd` | 新增元数据键可能影响现有技能的元数据快照/网络字段 | 新键仅默认值生效，现有技能未声明即行为不变 |
| `game_data/factions.json` | 势力记录格式错误会让全体武将校验失败 | 追加单条记录，失败即还原文件 |

**提交策略**：三个子任务各自独立提交（每项独立可回溯），父任务在集成通过后做最终一次提交（文档同步 + 测试说明）。

---

## 四、实施清单（父任务视角）

- [ ] 子任务①完成并通过其 `prd.md` 验收（含新增 `ahha_moment_test.tscn`）
- [ ] 子任务②完成并通过其 `prd.md` 验收（含新增 `multi_recast_test.tscn`）
- [ ] 子任务③完成并通过其 `prd.md` 验收（内容校验 + 两技能行为）
- [ ] 跑完「必跑回归」全部场景，记录**实际输出**（粘贴 `*_PASS` 行，不写推测结论）
- [ ] 确认机缘行为零改动：`opportunity_system_test` PASS，且 `_start_turn` 中机缘判定仍先于阿哈时刻
- [ ] 同步 `docs/游戏机制与玩法内容.md`（含全部具体数值：概率 = 1/在场人数、每轮一次、参演编号 144、体力 3、体力值/伤害公式 ⌊重铸次数/2⌋、重铸上限 7 次、X = 2 − 目标数）
- [ ] 同步 `docs/内容制作指南.md`（`joy_skill` / `performance_number` / `perform_joy_skill` / `recast_hand_cards`）
- [ ] 同步 `docs/架构说明.md`、`docs/AI模块.md`
- [ ] 按 `AGENTS.md` 规范产出「学习反馈摘要」与「Git 提交描述」，并追加写入 `临时反馈文档.md`

---

## 五、`task.py start` 前的复查

- [ ] 父任务与三个子任务的 `prd.md` / `design.md` / `implement.md` 均已就位且无 TBD
- [ ] 所有用户拥有的决策已解决（见 `prd.md` 的 Key Decisions 表），无阻塞 Open Question
- [ ] 三个子任务的验收条目均可观察、可测试，且与父任务 `prd.md` 的跨子任务验收不冲突
- [ ] 用户已对最终规划摘要给出**明确批准**
