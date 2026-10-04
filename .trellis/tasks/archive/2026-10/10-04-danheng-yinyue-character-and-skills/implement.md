# 执行计划 · 武将丹恒·饮月与技能【伏辰】【濯世】

> 需求见 `prd.md`，技术设计见 `design.md`。本文件只描述**执行顺序、验证方式与门禁**。

## 执行前置

- 先读 `.trellis/spec/content/index.md`、`skill-authoring.md`、`content-ai.md`，以及 `game_data/characters/danheng.gd`（模板）、`game_data/skills/zhishi.gd`（`respond` 订阅范式）、`game_data/skills/linggan.gd`（多段主动技范式）。
- 基线验证（改动前必须为绿）：`tests/new_character_mechanics_test.tscn`、`tests/ai_policy_test.tscn`、`tests/event_runtime_test.tscn`。

---

## 阶段 1 · 武将文件

1. 按 `design.md` §1 新增 `game_data/characters/danheng_yinyue.gd`。
2. 先在**没有技能文件**的情况下确认数据库能扫到该武将（可暂时把技能数组留空或先建占位文件——推荐直接进入阶段 2，避免中间态无法加载）。

**验证**：编辑器无脚本错误；`GameDatabase` 能返回该武将的 `id/display_name/faction/max_hp`。
**门禁**：元数据键只能使用 `id/display_name/gender/faction/max_hp/description`（F3）；技能顺序 `[fuchen, zhuoshi]`。

## 阶段 2 · 【伏辰】

按 `design.md` §2 实现 `game_data/skills/fuchen.gd`。

**验证**（手工冒烟 + 阶段 5 的自动化测试）：
1. 其他角色**打出**【杀】（如响应【南蛮入侵】）→ 该实体进入丹恒·饮月手牌，弃牌堆中不再有它。
2. 其他角色**使用**【杀】→ 不触发。
3. 自己**打出**/**使用**【杀】→ 不触发。
4. 触发过程中**没有**任何选择请求弹出。

**门禁**：`role="global"`；锁定技标记存在；失败路径零日志零请求。

## 阶段 3 · 【濯世】

按 `design.md` §3 实现 `game_data/skills/zhuoshi.gd`。建议顺序：

1. 元数据 + 常量 + `install()`（订阅 `phaseUseBegin` 复位额度）+ `can_activate()`。
2. `activate()` → `CHOICE_STEP1`（`request_card_target_selection`）。
3. `continue_selection()` 的分支骨架 + 步骤 1 的费用与额度消费。
4. 逐步补齐 `CHOICE_STEP1_DISCARD` → `CHOICE_STEP2` → `CHOICE_STEP2_DISCARD` → `CHOICE_STEP3`。
5. 最后实现 AI 五个分支。

**每一步都要单独冒烟**，不要一次写完再调：
- 步骤 1 取消 → 可立刻重新发动（额度未消费）。
- 步骤 1 确认 → 目标手牌候选以**牌背**呈现；确认后目标手牌 −1、自己手牌 −1。
- 步骤 2 取消 → **跳过**，直接进入步骤 3 的询问。
- 步骤 2 确认 → 目标候选包含**装备区**的牌、**不包含**判定区。
- 步骤 3 确认 → 目标掉 1 点体力（有护盾时先扣护盾），伤害属性为雷电。
- 目标只有装备、没有手牌 → **不出现在**步骤 1 的目标候选中。
- 目标在步骤 1 之后失去全部手牌 → 步骤 1a **跳过**而不是卡死。

**验证**：`tests/new_character_mechanics_test.tscn` 不回归；手工冒烟上述 8 条全部符合。
**门禁**：不得出现「候选为空的不可取消请求」；不得在任何一步重新选择目标。

## 阶段 4 · AI 补齐

按 `design.md` §3.4 实现 `append_play_phase_actions` / `score_ai_action` / `score_ai_choice` 五个分支。

**验证**：
- `tests/ai_policy_test.tscn` 通过。
- 手工观察 AI 对局（或专项断言）：AI 发动【濯世】后会走完整条链，**不出现**「发动→立即取消→再发动」的空转。
- 断言 `CHOICE_STEP1` / `2` / `3` 的确认分**严格大于 0**。

**门禁**：未新增 `BasicAIPolicy` 白名单；评分复用 `score_resource_change()` 与公开资源常量（`content-ai.md` Quality Check）。

## 阶段 5 · 专项测试与文档

1. 新增 `tests/danheng_yinyue_mechanics_test.gd` / `.tscn`，覆盖 `prd.md` 的全部验收断言（含【伏辰】三组对照、【濯世】三段链与全部取消/退化分支、雷电属性、次数限制与阶段复位、候选可见性与区域范围、AI 确认分）。
2. 文档同步：

| 文档 | 同步内容 |
|---|---|
| `docs/游戏机制与玩法内容.md` | 丹恒·饮月与两条技能的完整机制说明与**全部数值**（体力上限 4、每段费用 1 张基本牌、上限 3 段、雷电伤害 1 点、出牌阶段限一次） |
| `docs/内容制作指南.md` | 若该文档维护武将/技能索引，补入本武将；**不改动时机目录**（本子任务零时机改动） |
| `docs/AI模块.md` | 若维护技能 AI 钩子清单，补入【濯世】的五个评分分支与保底分口径 |
| `README.md` | 追加一行：运行 `res://tests/danheng_yinyue_mechanics_test.tscn` 可验证的内容摘要（与既有条目同文体） |

## 阶段 6 · 全量回归与收尾

1. 跑：`new_character_mechanics`、`ai_policy`、`event_runtime`、`gameplay_regression`、`card_action_semantics`、`danheng_yinyue_mechanics`。
2. 编辑器内开局冒烟：`GameDatabase.validation_errors` 为空，选将中可见丹恒·饮月。
3. 按项目规范输出「学习反馈摘要」+ 编号 Git 提交描述，追加到 `临时反馈文档.md`（带时间戳）。

---

## 回滚点

| 回滚点 | 方式 |
|---|---|
| 阶段 1–3 之后 | 删除武将文件与两个技能文件，`GameDatabase` 自动回到改动前状态（内容层无中央注册表） |
| 阶段 4 之后 | 仅移除 AI 钩子即可让 AI 不发动该技能，规则不受影响 |

## 完成定义（DoD）

- `prd.md` 全部验收标准勾选完成。
- 【伏辰】【濯世】的玩家可见文本与需求原文逐字一致。
- AI 五个评分分支齐备，且无「发动后立刻取消」空转。
- 文档已同步，`docs/游戏机制与玩法内容.md` 记录了本武将的全部数值。
- 学习反馈与 Git 提交描述已追加到 `临时反馈文档.md`。
