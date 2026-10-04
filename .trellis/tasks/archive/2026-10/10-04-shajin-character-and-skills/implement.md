# 执行计划 · 武将砂金与技能【筹码】【盲注】【风口】

> 需求见 `prd.md`，技术设计见 `design.md`。本文件只描述**执行顺序、验证方式与门禁**。
> **前置**：【风口】第一段必须在 `10-04-batch-gain-timing-mechanism` 归档后实现。

## 执行前置

- 读 `.trellis/spec/content/index.md`、`skill-authoring.md`、`content-ai.md`。
- 参考实现：`yanling.gd`（`gameStart` + `role="global"`）、`jvkou.gd`（`add_hand_limit_bonus`）、`fanyin.gd`（批次时机订阅）、`jiezhi.gd` / `mice.gd`（`has_nested_settlement_barrier` + `defer_settlement`）、`qihe.gd` / `zhuxv.gd`（`pick_random_candidate_index`）、`nakexia.gd`（失去技能与读档不装回）、`xianzou.gd`（阶段 Begin 订阅）。
- 先跑基线：`tests/new_character_mechanics_test.tscn`、`tests/ai_policy_test.tscn`、`tests/haiseyin_mechanics_test.tscn`（批次机制回归）。
- **确认机制已就绪**：`RuleTimingCatalog.has_timing("cardsGainedBatchAfter")` 为真；否则本子任务停在阶段 3 之前，不得自行近似。

---

## 阶段 1 · 武将文件

按 `design.md` §0 新增 `game_data/characters/shajin.gd`。

**验证**：编辑器无脚本错误；`GameDatabase` 返回 `xingjihepinggongsi` / `male` / `max_hp == 3`。
**门禁**：技能顺序 `[chouma, mangzhu, fengkou]`。

## 阶段 2 · 【筹码】

按 `design.md` §1 实现 `game_data/skills/chouma.gd`。

**验证**：
1. 开局后砂金手牌 = 起始手牌 + 3。
2. `hand_limit_bonus == 3`，有效手牌上限 = `hp + 3`。
3. 日志中出现一次「摸 3 张」与一次技能宣告；不重复施加。
4. 大屏观察 `gameStart` 时机的 `role` 确实收到事件（若收不到说明 `role` 写错）。

**门禁**：不写 AI 钩子，并在类注释说明理由。

## 阶段 3 · 【盲注】

按 `design.md` §2 实现 `game_data/skills/mangzhu.gd`（先做「阶段开始 + 两步单选 + 记录」，再做「阶段中累计」，最后做「阶段结束比对」）。

**逐条冒烟**：
1. 第 1 步取消 → 阶段结束无护盾、无摸牌。
2. 只弃 1 张红 → 本阶段摸到红 → 获得 1 点护盾，不摸牌。
3. 弃 1 红 + 第 2 步选第 2 张时候选**只含黑色**。
4. 弃红+黑 → 本阶段摸到红黑各一 → 1 点护盾 **且** 摸 2 张。
5. 装备区的牌出现在候选中；判定区的牌**不**出现。
6. 摸牌阶段被跳过（如【兵粮寸断】）→ 记录清空，后续阶段无残留。
7. 在**别人**的摸牌阶段获得牌 → 不影响记录（`current_player_id` 过滤生效）。

**门禁**：两次单选的最小/最大选择数都是 1；建请求前必须有 `has_nested_settlement_barrier()` 检查。

## 阶段 4 · 【风口】第一段

按 `design.md` §3.2 实现。必须先确认阶段 0 的机制已就绪。

**逐条冒烟**：
1. 摸牌阶段摸 2 张 → 出现「弃置这些牌」询问；确认后两张进弃牌堆、计数 +1。
2. 取消 → 两张留在手牌、计数不变。
3. 只获得 1 张（如摸 1）→ 不询问。
4. 开局起始手牌 → **不**询问（关键回归：证明起始发牌不产生获得批次）。
5. 连续两个批次（例如技能一次性给 2 张、紧接着又给 2 张）→ 询问**顺序**出现，不叠加。
6. 计数：本回合确认 2 次后，检查 `character_form_state["fengkou_clause1_count"] == 2`。
7. 存档 → 读档 → 计数仍为 2。

**门禁**：`role="player"`；`batch_size >= 2` 过滤；重入排队逻辑存在。

## 阶段 5 · 【风口】第二段

按 `design.md` §3.3 实现。

**逐条冒烟**：
1. 计数 0 → 发动后只获得 1 张随机手牌，随后技能消失。
2. 计数 2 → 发动后获得 3 张（目标手牌 ≥ 3 时）。
3. 目标只有 1 张手牌、计数 2 → 只获得 1 张，不报错。
4. 取消目标选择 → 不获得牌、**技能仍在**。
5. 发动后技能栏不再显示【风口】；存档 → 读档后仍不显示。
6. 联机/回放：两次相同局面的随机结果一致（`history_data` 完整性）。

**门禁**：随机走 `pick_random_candidate_index`；失去技能走 `remove_skill`；不设阶段额度。

## 阶段 6 · AI 与专项测试、文档

1. 按 `design.md` §2.7 / §3.4 补齐 AI 钩子。
2. 新增 `tests/shajin_mechanics_test.gd` / `.tscn`，覆盖 `prd.md` 全部验收断言，**必须包含**：
   - 【盲注】五种颜色组合场景；
   - 【盲注】与【风口】同时被同一次摸牌触发的组合场景；
   - 【风口】第一段的取消/确认/排队/计数持久/读档；
   - 【风口】第二段的 1+N 张、提前停止、失去技能、取消不失去；
   - AI 各分支分数断言（应取消的分支为负分）。
3. 文档同步：

| 文档 | 同步内容 |
|---|---|
| `docs/游戏机制与玩法内容.md` | 砂金与三条技能的完整机制与**全部数值**：体力上限 3、【筹码】X=3（摸 3 张 / 上限 +3）、【盲注】最多弃 2 张（1 红 1 黑）、护盾 1 点、摸 2 张、颜色比对规则与两效果并用、【风口】第一段全弃口径与计数键名、第二段总张数 `1 + 计数`、丢失技能 |
| `docs/AI模块.md` | 补入【盲注】两步与【风口】两段的评分口径与「应取消给负分」的约定 |
| `docs/内容制作指南.md` | 若维护武将/技能索引则补入本武将；若包含 `cardsGainedBatchAfter` 的用法示例，把【风口】作为首个使用者补上 |
| `README.md` | 追加一行 `res://tests/shajin_mechanics_test.tscn` 的验证摘要（与既有条目同文体） |

## 阶段 7 · 全量回归与收尾

跑：`shajin_mechanics`、`batch_gain_timing`、`new_character_mechanics`、`ai_policy`、`haiseyin_mechanics`、`gameplay_regression`、`draw_sequence`。
编辑器开局冒烟：`GameDatabase.validation_errors` 为空。
输出「学习反馈摘要」+ 编号 Git 提交描述，追加到 `临时反馈文档.md`。

---

## 回滚点

| 回滚点 | 方式 |
|---|---|
| 阶段 2 之后 | 保留【筹码】，移除【盲注】【风口】文件即可 |
| 阶段 4 之后 | 移除【风口】的 `cardsGainedBatchAfter` 订阅 → 第一段不再触发，第二段独立可用 |
| 全部完成后 | 内容层无中央注册表，删除文件即回到改动前状态；不影响核心层 |

## 完成定义（DoD）

- `prd.md` 全部验收标准勾选完成，**尤其**：起始手牌不触发第一段、读档后【风口】不复活、同一次摸牌同时触发两个技能。
- 三条技能的可见文本与最终文本逐字一致。
- AI 分支齐备且无空转；应取消的分支给负分。
- 文档已同步，`docs/游戏机制与玩法内容.md` 记录了全部数值。
- 学习反馈与 Git 提交描述已追加到 `临时反馈文档.md`。
