# 实施计划：那刻夏（逐虚 · 揭质 · 留白）

> 需求见同目录 `prd.md`，技术设计见同目录 `design.md`。
> 实施顺序固定：**M2 → M3 → M4 → 内容层 → 测试 → 文档**。M2 只增不改；M3 引入持久化字段；
> M4 复用 M3 建立的卸载路径；内容层最后接入，避免中间态影响既有回归。

---

## 一、变更单元

### U1 新增权威随机端口（M2）

- 文件：`scripts/core/match_controller.gd`
- 新增 `pick_random_candidate_index(candidate_count: int, history_kind: String = "", history_data: Dictionary = {}) -> int`：
  使用权威 `_rng.randi_range`，每次调用写入 `state.random_history`，`candidate_count <= 0` 返回 `-1`。
- 放置在随机取牌范例 `get_random_zone_card_uids_for_each_player` 附近，共用同一套 `_rng` + `random_history` 契约。
- 验收：AC4

### U2 新增「本局永久失去技能」持久化字段（M3）

- 文件：`scripts/data/player_state.gd`
- 字段：`skills_permanently_removed: bool = false`，紧接 `acquired_skills` 之后声明并配单行注释。
- `to_dict`：新增 `"skills_permanently_removed": skills_permanently_removed`。`to_dict` 同时是**公开快照**与**存档**的唯一出口，因此该字段自动进入 UI 快照、LAN 快照与存档三处。
- `from_dict`：`player.skills_permanently_removed = bool(data.get("skills_permanently_removed", false))`，旧存档缺字段时按 `false` 兼容。
- 存档中的技能实例变量由 `_capture_skill_runtime_states`（`MC:13381`）自动采集；标记为永久移除的玩家在恢复期不会被装配实例，`_apply_skill_runtime_states` 会自然跳过，无需额外分支。
- 验收：AC8

### U3 新增永久移除技能端口（M3）

- 文件：`scripts/core/match_controller.gd`
- 新增 `remove_all_skills_permanently(player_id: int, reason: String = "") -> bool`：
  1. 校验玩家存在且未处于无效态；
  2. 逐个 `uninstall()` 并清空该玩家实例表（释放全部时机订阅）；
  3. 清空 `player.acquired_skills` 与 `player.temporary_skills`；
  4. 清空该玩家的轮回技公开状态 `player.reincarnation_skills`；
  5. 置 `player.skills_permanently_removed = true`；
  6. 写日志并 `_emit_state()`。
- 幂等：已置标记时直接返回，不重复卸载。
- 验收：AC8

### U4 四条装配路径复核标记（M3）

缺任何一处都会出现「技能复活」缺陷，因此四处逐一改造：

| 路径 | 位置 | 处理 |
|---|---|---|
| 开局全量安装 | `_install_all_character_skills`（`MC:9224`） | 循环内 `continue` 跳过已永久移除的玩家 |
| 换将重装 | `_reinstall_character_skills_for_player`（`MC:9267`） | 仍先卸载旧实例（防止残留订阅），随后不再装配 |
| 局内获得技能 | `grant_acquired_skill`（`MC:8650`） | 前置校验返回 `false` |
| 读档恢复运行时技能 | `_reinstall_saved_runtime_skills`（`MC:13623`） | 跳过 |

- 验收：AC8（四条路径均需测试断言）

### U5 新增重置技能端口（M4）

- 文件：`scripts/core/match_controller.gd`
- 新增 `reset_all_other_skills(player_id: int, exclude_skill_id: String = "") -> int`：
  1. 取出 `exclude_skill_id` 的实例并保留（**不得重建**，否则留白的限定技已发动标记被清零，可无限发动）；
  2. 快照当前**已安装**的局内获得技能及其 `player.acquired_skills` 限额定义（`source` / `per_turn_limit` / `per_round_limit` / `total_limit`）；
  3. 卸载并清空该玩家全部技能实例；
  4. 重新装配「武将固有技能 + 模式技能」（复用 `_reinstall_character_skills_for_player` 的既有装配逻辑，但排除项不装配）；
  5. 按第 2 步快照重新授予局内获得技能，`uses_this_turn` / `uses_this_round` / `total_uses` 归零；
  6. 回填排除项实例；
  7. `_emit_state()`，返回重建的技能数量。
- **不修改** `restore_limited_skill_use`（`MC:4343`）的既有语义与调用点。
- 验收：AC7

### U6 新增那刻夏武将定义

- 文件：`game_data/characters/nakexia.gd`
- `id` `nakexia`、`display_name` 那刻夏、`gender` `female`、`faction` `wengfaluosi`、`max_hp` 3。
- 预加载并引用 `zhuxv.gd` / `jiezhi.gd` / `liubai.gd`。
- 验收：AC1

### U7 新增【逐虚】

- 文件：`game_data/skills/zhuxv.gd`
- 形态：主动轮回技，2 节，`trigger:"active/phaseUse"`、`enable:"phaseUse"`、`reincarnation:true`、`reincarnation_section_count:2`。
- 额度：私有 `_used_this_play_phase` + `PLAY_PHASE_LIMIT = 2`，在 `phaseUseBegin` 复原；与轮回服务的每轮回节限次并存复核。
- ① 随机弃牌：先经 U1 端口在「当前有牌的角色」中等概率取 1 名（含自己），再在该角色区域内等概率取 1 张弃置；范围含手牌/装备/判定区。
- ② 随机伤害：经 U1 端口在「全部存活角色」中等概率取 1 名（含自己，无「有牌」限制），造成 1 点伤害。
- 效果收尾向 U8 报告「本节编号 + 目标 ID」，供揭质复核。
- AI：`score_ai_action` 按期望收益评分；② 的评分在目标（自己或队友）体力低时下调。
- 验收：AC3、AC4、AC5、AC9

### U8 新增【揭质】

- 文件：`game_data/skills/jiezhi.gd`
- 形态：被动技，`ui_enabled:false`，**不设** `limited`。
- 额度：私有 `_used_count` + `PER_GAME_LIMIT = 2`（由 `_capture_skill_runtime_states` 自动进入存档）。
- 触发：由逐虚在每节效果完成后显式通知；对**同一目标**重复执行同一节效果。
- 目标非法（死亡 / 离场 / ① 情形无牌可弃）时 `can_use_effect` 返回 `false`，不开放入口、不消耗次数。
- AI：对敌方目标释放②时评分显著为正，其余情形给保守分。
- 验收：AC6、AC9

### U9 新增【留白】

- 文件：`game_data/skills/liubai.gd`
- 形态：限定技（`limited:true`），`trigger:"active/phaseUse"`、`enable:"phaseUse"`。
- 第一段：发动时调用 U5 的 `reset_all_other_skills(owner, "liubai")`（立即效果）。
- 第二段：订阅 `turnEnd`，在本回合结束时调用 U3 的 `remove_all_skills_permanently(owner, "liubai_clear")`；延迟段必须在同一回合内保持订阅存活。
- 顺序固定：先重置、后失去。
- AI：以「本回合已消耗额度总量」估算重置收益，并与「永久失去全部技能」的代价对比；收益为 0 时不发动。
- 验收：AC7、AC8、AC9

### U10 新增回归用例

- 文件：`tests/nakexia_mechanics_test.gd` + `tests/nakexia_mechanics_test.tscn`
- 覆盖 `design.md` 第五节列出的 8 组断言；成功打印 `NAKEXIA_MECHANICS_PASS` 标记。
- 夹具沿用既有范式（`_create_controller` / `_reset_state` / `_install_skill` / `_fail`），并复用批 1 建立的「结算开局技能选择」处理。
- 验收：AC1–AC10

### U11 调整计数断言

- 文件：`tests/smoke_test.gd`
- 技能定义 74 → **77**，武将定义 35 → **36**，并同步注释文本。
- 验收：AC10

### U12 同步文档

- `docs/内容制作指南.md`：M2/M3/M4 三个接口、逐虚额度写法、揭质重复效果写法、留白双段写法。
- `docs/游戏机制与玩法内容.md`：正式武将技能表、新武将快照、轮回技与技能复原章节，记录全部数值。
- `docs/AI模块.md`：三技能 AI 规则（含随机动作的期望值算法）。
- `docs/界面与交互.md`：失去技能后的技能栏表现。
- `docs/架构说明.md`：武将与技能计数。
- `README.md`：新增回归用例的覆盖范围。
- 验收：AC2、AC10

---

## 二、验收标准

沿用 `prd.md` 的 AC1–AC11，逐条在本批收尾时核对：

- AC1 三个技能文件与武将文件落地，`GameDatabase.validation_errors` 为空。
- AC2 三条描述与原文逐字一致（含引号字符）。
- AC3 逐虚每出牌阶段最多发动 2 次；第 3 次不开放入口；阶段切换后复原。
- AC4 逐虚 ①/② 的随机范围与「等概率」正确，随机源来自权威 RNG（同种子可复现）。
- AC5 逐虚 ② 的随机目标含自己；AI 在自己或队友体力低时降低该动作收益。
- AC6 揭质仅在逐虚实际发动后出现入口；重复效果作用于同一目标；用尽后不再出现。
- AC7 留白重置后：限定技额度、阶段额度、回合额度、觉醒技额度、轮回进度全部复原（逐项断言）。
- AC8 留白发动后本回合结束时全部技能（含留白自身）永久移除；无入口、无订阅、无轮回残留、UI 不显示、不可恢复。
- AC9 三技能 AI 均产出严格 > 0 的合法动作评分；留白 AI 综合评估收益与代价。
- AC10 新增回归测试通过；`reincarnation_mechanics_test`、`new_character_mechanics_test`、`tingyun_mechanics_test` 无回归。
- AC11 未在核心层新增技能 ID 白名单；未读取禁读路径。

---

## 三、执行顺序与提交划分

1. **U1**（M2）→ 单独可验证，跑 `rule_timing_test` 与随机相关用例。
2. **U2 + U3 + U4**（M3）→ 必须一起提交：字段、端口、四条路径构成一个完整不变量。
3. **U5**（M4）→ 依赖 M3 的卸载路径，跑 `tingyun_mechanics_test` 验证既有复原语义未被破坏。
4. **U6–U9**（内容层）→ 三技能与武将一次落地。
5. **U10 + U11**（测试与计数）→ 新用例通过后同步既有计数断言。
6. **U12**（文档）→ 最后统一同步。
7. 全量 63+ 项回归 → 追加 `临时反馈文档.md` → 单次提交（保持每个提交均为全绿状态）。

> 批 1 的经验：新增武将会改变固定种子选将结果，可能触发既有测试的连锁差异。
> 若出现，优先用「显式固定被测对象」的方式修复，而不是放宽断言。
