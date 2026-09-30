# 执行计划：主演机制、座次相邻与两名武将

> 配套 `prd.md` + `design.md`。按阶段顺序执行；每个阶段末尾必须跑该阶段的最小验证，通过后才进入下一阶段。

## 阶段划分与顺序

阶段 0 → 1 → 2 是**底座**：2 名武将都依赖主演服务与座次相邻查询，刃还依赖目标改写钩子与 AI 钩子。因此**必须先完成阶段 1、2 再动武将与技能**。

```
0  准备与基线
1  势力配色 + 主演机制（服务 + 控制器端口）
2  核心规则钩子（座次相邻、自己成为目标、手牌上限豁免）
3  【悬壶】【生息】+ 白露
4  【万死】+ 主演回复 + 【支离】规则
5  【支离】AI + 全部 AI 补全
6  测试
7  文档同步
8  质量检查与提交
```

---

## 阶段 0：准备与基线

- [ ] 0.1 跑基线回归，确认改动前全绿：

```
res://tests/smoke_test.tscn
res://tests/ai_policy_test.tscn
res://tests/new_character_mechanics_test.tscn
```

- [ ] 0.2 记录基线失败项（若有），后续步骤不得把它算作本次回归。
- [ ] 0.3 通读参考实现，确认接口口径（不改代码）：
  - `game_data/skills/yuezhi.gd` —— `useCard` 整牌时机 + `replace_card_use_targets` 改写 + `useCardAfter` 收尾
  - `game_data/skills/xiongxing.gd` —— 角标写入/移除 + `dieAfter` 全局订阅 + 死亡清理
  - `game_data/skills/shanqing.gd` —— 每回合额度惰性同步 + `damageSource` 时机 + AI 评分结构
  - `game_data/skills/jiyu.gd` —— `modify_ai_card_action_score` 技能侧介入卡牌评分
  - `scripts/core/reincarnation_skill_service.gd` —— RefCounted 服务的 `configure(host)` 形态

**回滚点 A**：此处尚未改动任何文件。

---

## 阶段 1：势力配色 + 主演机制

- [ ] 1.1 `game_data/factions.json`：把 `xinghelieshou` 的 `color` 从 `9a4d62` 改为 `5b3a7d`（深紫罗兰 / 黑紫色，不带 `#` 的 6 位十六进制）。
- [ ] 1.2 新增 `scripts/core/starring_role_service.gd`（`class_name StarringRoleService extends RefCounted`），实现 `design.md` 2.2 的 5 个方法；常量 `CORNER_ENTRY_ID="zhuyan"` / `CORNER_TEXT="主演"` / `CORNER_TEXT_ORDER=50`，全部带完整注释。
- [ ] 1.3 `scripts/core/match_controller.gd`：
  - [ ] 声明字段 `starring_role_service`
  - [ ] 在 `reincarnation_skill_service` 的既有初始化点附近创建并 `configure(self)`
  - [ ] 新增公开端口 `set_starring_role(player_id)` / `get_starring_role_player_id()` / `is_starring_role(player_id)`，全部带完整注释
- [ ] 1.4 冒烟验证：临时在测试里调用 `set_starring_role`，确认角标写入与顶替移除都正确（正式测试在阶段 6 落地）。

**最小验证**：`res://tests/corner_badge_test.tscn`（角标排版时序不得被破坏）。

**回滚点 B**：`factions.json` 颜色 + 新增服务文件 + 控制器 3 处增量接线。

---

## 阶段 2：核心规则钩子

- [ ] 2.1 `scripts/data/game_state.gd`：新增 `get_seat_neighbor_player_ids(player_id) -> Array[int]`（`design.md` 第 3 节；去重、跳过死亡/离场、不超过 2 名、顺序稳定）。
- [ ] 2.2 `game_data/skill_definition.gd`：新增两个默认钩子（必须与既有钩子同风格的中文文档注释）：
  - [ ] `allows_self_as_card_target(card_definition) -> bool`，默认 `false`
  - [ ] `does_not_count_toward_hand_limit(card, card_definition) -> bool`，默认 `false`
- [ ] 2.3 `scripts/core/card_rule_service.gd`：
  - [ ] 新增私有汇总查询 `_skill_allows_self_as_card_target(actor_id, definition) -> bool`（照抄 `_skill_ignores_card_distance_limit` 的 provider 汇总模式）
  - [ ] `_validate_target`：`target_id == actor.player_id` 且钩子成立时跳过距离限制判定
  - [ ] `normalize_targets`：`all_others` 分支的「跳过使用者自己」改为「除非钩子成立」
- [ ] 2.4 `scripts/core/match_controller.gd`：新增 `_count_hand_limit_exempt_cards(player_id) -> int`，并把两处弃牌溢出计算（`line ~7890`、`line ~13146`）改为扣除该数量。

**最小验证**：

```
res://tests/smoke_test.tscn
res://tests/phase_progression_test.tscn
```

**回滚点 C**：`game_state.gd` + `skill_definition.gd` + `card_rule_service.gd` + 控制器弃牌计算。全部为增量，回滚只需删函数、还原两处表达式。

---

## 阶段 3：【悬壶】【生息】+ 白露

- [ ] 3.1 新增 `game_data/skills/xuanhu.gd`（`design.md` 6.x）：`lock=true`；订阅 `dieAfter`(global)；`does_not_count_toward_hand_limit` 覆盖；`description` **逐字**照抄 prd 原文。
- [ ] 3.2 新增 `game_data/skills/shengxi.gd`（`design.md` 7.x）：`character_form_state` 三键状态；订阅 `useCard`(source) + `phaseAfter`(player)；`request_control_selection` 两选项；`score_ai_choice` 实现「X > 手牌数 → 摸牌，否则 X+1」；`description` **逐字**。
- [ ] 3.3 新增 `game_data/characters/bailu.gd`：`id=bailu`、`display_name=白露`、`gender=female`、`faction=xianzhou`、`max_hp=3`，技能顺序 `[XUANHU_SKILL, SHENGXI_SKILL]`。
- [ ] 3.4 逐字核对：两个技能的 `name` 与 `description` 与 prd 需求原文**完全一致**（含全角括号、全角引号）。

**最小验证**：

```
res://tests/smoke_test.tscn
res://tests/ai_policy_test.tscn
```

**回滚点 D**：3 个新增文件（删除即回滚）。

---

## 阶段 4：【万死】+ 主演回复 + 【支离】规则

- [ ] 4.1 新增 `game_data/skills/wansi.gd`（`design.md` 第 5 节）：订阅 `damageAfter`(target) + `phaseAfter`(player)；确认选择 + 待执行标记；执行时先 `set_starring_role` 再 `who.addPhase()`；`score_ai_choice` 满足条件即确认。
- [ ] 4.2 新增 `game_data/skills/zhili.gd` 的**规则部分**（`design.md` 4.1–4.3）：
  - [ ] `lock=true`
  - [ ] 覆盖 `allows_self_as_card_target`（对【杀】牌族返回 `true`）
  - [ ] 订阅 `useCard`(source) 做唯一目标改写 + 幂等集合 + 代价登记
  - [ ] 订阅 `useCardAfter`(source) 支付失去 1 点体力
  - [ ] 订阅 `damageSource`(global) 实现「主演使用【杀】造成伤害时回复 1 点体力」
  - [ ] 订阅 `dieAfter`(global) 清理实例内待结算标记
- [ ] 4.3 新增 `game_data/characters/ren.gd`：`id=ren`、`display_name=刃`、`gender=male`、`faction=xinghelieshou`、`max_hp=4`，技能顺序 `[WANSI_SKILL, ZHILI_SKILL]`。
- [ ] 4.4 逐字核对：两个技能的 `name` 与 `description` 与 prd 需求原文**完全一致**（注意【万死】原文使用**全角引号** `“主演”`）。

**最小验证**：

```
res://tests/smoke_test.tscn
res://tests/new_character_mechanics_test.tscn
```

**回滚点 E**：阶段 3、4 的 5 个新增文件（删除即回滚）。

---

## 阶段 5：【支离】AI + 全部 AI 补全

- [ ] 5.1 `zhili.gd` 覆盖 `modify_ai_card_action_score()`（`design.md` 第 8 节）：只在「自己使用【杀】且唯一目标」时生效；撤销原目标收益、加入改写后相邻目标收益、扣 1 点体力代价。
- [ ] 5.2 复查四个技能的 AI 覆盖面（`项目专属AGENTS.md` 2.3 + `content-ai.md` Quality Check）：
  - [ ] 【悬壶】锁定技无决策 → 不伪造主动动作
  - [ ] 【生息】`score_ai_choice` 覆盖二选一，含取消分支 0 分
  - [ ] 【万死】`score_ai_choice` 覆盖确认，含取消分支 0 分
  - [ ] 【支离】`modify_ai_card_action_score` 覆盖用牌评分；自身不产生主动动作
- [ ] 5.3 自查：新增 AI 是否影响其他武将/卡牌的既有决策（应无 —— 钩子全部以技能持有者与特定牌族为条件）。
- [ ] 5.4 记录**补全的通用逻辑及其作用域**，供交付说明使用。

**最小验证**：

```
res://tests/ai_policy_test.tscn
```

**回滚点 F**：仅 `zhili.gd` 的 AI 函数。

---

## 阶段 6：测试

- [ ] 6.1 新增 `tests/zhuyan_zhili_test.gd` + `tests/zhuyan_zhili_test.tscn`，实现 `design.md` 第 10 节的 23 项断言。
  - [ ] 测试在 `game_flow_interval_seconds = 0` 下同步运行
  - [ ] 复用既有测试的夹具构造方式（参考 `tests/new_character_mechanics_test.gd`）
- [ ] 6.2 跑完整验证集：

```
res://tests/zhuyan_zhili_test.tscn        # 本次新增，必须 PASS
res://tests/smoke_test.tscn               # 必须 PASS
res://tests/ai_policy_test.tscn           # 必须 PASS
res://tests/new_character_mechanics_test.tscn  # 必须 PASS
res://tests/phase_progression_test.tscn   # 必须 PASS（额外回合与阶段时序）
res://tests/corner_badge_test.tscn        # 必须 PASS（角标排版时序）
```

- [ ] 6.3 与阶段 0 的基线失败项对比，确认**没有新增失败**。
- [ ] 6.4 走查 `GameDatabase.validation_errors` 为空。

**审查卡点**：6.2 全绿前不得进入阶段 7。

---

## 阶段 7：文档同步

- [ ] 7.1 `docs/内容制作指南.md`：
  - [ ] 「可填写势力 ID」表与「新势力与武将登记」：星核猎手颜色更新
  - [ ] 「当前正式武将技能」总表：追加 4 个技能
  - [ ] 「技能脚本变量与数组」表：追加 2 个武将的技能常量与稳定 ID
  - [ ] **新增「主演」机制小节**：唯一性不变量、顶替规则、角标条目 ID 与 `order=50`、权威表示、死亡清理
  - [ ] **新增座次相邻查询接口**：`GameState.get_seat_neighbor_player_ids()` 的语义与边界
  - [ ] **新增技能钩子**：`allows_self_as_card_target`、`does_not_count_toward_hand_limit`（写入「技能规则修正、虚拟牌覆写与临时技能」表）
  - [ ] **新增目标改写范例**：把【支离】登记为「指定唯一目标时改写 + 结算后付费」的范例（与【岳峙】并列），并重申「不要用 `useCardBefore`/`useCardBegin` 改写目标」
  - [ ] **新增额外回合时机范例**：【万死】的 `phaseAfter` + `addPhase()` 时序说明
- [ ] 7.2 `docs/游戏机制与玩法内容.md`：
  - [ ] 主演机制说明与全部数值（唯一性、角标层级 50、文本）
  - [ ] 星核猎手新颜色
  - [ ] 白露：体力 3、势力、两个技能的完整规则与全部数值（桃不计上限、从牌堆取第一张桃、X 初始 1 / 永久累积 / 无上限 / 每回合限 X 次 / 回合结束后 +1）
  - [ ] 刃：体力 4、势力、两个技能的完整规则与全部数值（每回合限一次、体力恰为 1、回合结束后成为主演 + 额外回合、唯一目标改写、相邻定义、失去 1 点体力无条件支付、主演造成伤害回复 1 点）
  - [ ] 新增武将登记到既有的「当前范例内容」段落
- [ ] 7.3 `docs/AI模块.md`：
  - [ ] 追加 4 个技能的 AI 口径行（照既有表格格式）
  - [ ] 登记「主演」这一新博弈维度及本次补全范围
- [ ] 7.4 交叉校验：文档中每个数值都能在代码里找到唯一来源；文档与代码不一致处按「文档跟随代码」修正。

---

## 阶段 8：质量检查与提交

- [ ] 8.1 跑 `trellis-check` 口径的自查（spec 合规、lint、跨层数据流、代码复用、一致性）。
- [ ] 8.2 检查 `AGENTS.md` 代码注释规范：
  - [ ] 每个变量独占一行注释，说明作用/取值/默认值原因
  - [ ] 魔法数字全部提取为带注释的常量
  - [ ] 未擅自修改既有变量名或删除既有注释
- [ ] 8.3 产出交付说明（`项目专属AGENTS.md` 2.1 要求）：
  - [ ] 「学习反馈摘要」（规范三）
  - [ ] 「Git 提交描述」（规范四，分点不糅合）
  - [ ] 追加写入根目录 `临时反馈文档.md`（规范五，带时间戳）
  - [ ] 单独列出「需求未明确、由 AI 补全的配套逻辑」
- [ ] 8.4 提交（由开发者执行或经其确认）。

**最终回滚形态**：见 `design.md` 第 9 节末「回滚形态」。

---

## 验证命令速查

| 目的 | 场景 |
|---|---|
| 基础冒烟 | `res://tests/smoke_test.tscn` |
| AI 回归 | `res://tests/ai_policy_test.tscn` |
| 武将机制回归 | `res://tests/new_character_mechanics_test.tscn` |
| 阶段与额外回合 | `res://tests/phase_progression_test.tscn` |
| 角标排版时序 | `res://tests/corner_badge_test.tscn` |
| 本次新机制 | `res://tests/zhuyan_zhili_test.tscn` |

回归日志目录与运行前置说明见 `docs/战斗框架回归说明.md`。
