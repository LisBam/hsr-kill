# 执行计划：三名新武将与【连戏】改写

> 需求见 [`prd.md`](./prd.md)，技术设计见 [`design.md`](./design.md)。
> 顺序执行；每个里程碑末尾有**验证门**，验证未通过不得进入下一个里程碑。

---

## 0. 环境与命令模板

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7**（`project.godot` 声明 `config/features=("4.7", ...)`） |
| 本机可执行文件 | `E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` |
| 工作目录 | `E:\Godot\MyGame\hsr-kill` |

测试运行模板（**逐进程顺序执行**，不要并发）：

```powershell
$godot = "E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
& $godot --headless --path . res://tests/<名称>_test.tscn
```

判定标准：**退出码 0 + 输出含自身 `*_PASS` 标记 + 日志无 `ERROR` / `SCRIPT ERROR` / `FAIL`**。
禁止用固定墙钟等待异步流程；断言失败信息必须带实际观测值。

---

## M0 技术风险前置验证（**必须最先做**）

`design.md` §13 的两个中风险必须先用真实运行验证，否则后续里程碑可能建立在错误假设上。

**做法**：新增一个临时专项测试场景（例如 `tests/tmp_target_repeat_probe.tscn` + `.gd`，验证完成后改写为正式回归用例或删除）。

| 待验证假设 | 验证方式 | 期望观测 | 实测结论 |
|---|---|---|---|
| A/B. 同一目标在 `target_ids` 中重复出现 N 次 → 该牌对其实结算 N 次 | 3 人局：探针技能在 `useCard` 时机把 `event.data["target_ids"]` 改写为 `[0,0,0]`。实测改用【桃园结义】（"所有已受伤角色依次回复1点体力"，既无响应窗口也无选牌交互，观测最干净；【五谷丰登】会为每个目标创建选牌请求，不适合做无干扰观测） | 持有者回复 3 次（4→7） | **成立**：`hp=7`，探针 `fire_count=1`。A 与 B 共用同一结算机制，故伤害类与正收益类多目标牌同样会重复结算 |
| C. 异步询问后只写共享上下文是否被覆盖 | 探针在 `useCard` 创建可取消询问，**在 `continue_selection` 里绕过端口直接改写 `_card_use_contexts`** | 若被覆盖，则 M1 端口必要 | **成立（被覆盖）**：`hp=5`，改写无效。**坐实 `replace_card_use_targets` 端口必要** |
| D. 事后次数豁免生效 | 预置 `play_phase_card_use_history["sha"]=1` 使【杀】达上限，再补写两份豁免历史，重新校验 | 拒绝信息消失，净计数 1→0 | **成立**：`before="本阶段使用【杀】的基础次数已用尽。"` → `after=""`，`grouped_count` 1→0 |
| E. 【凌霜】时机的可写回性 | 探针订阅 `useCardToTargeted`（`role="source"`），用一张【杀】驱动 | 拿到实时 `target_ids` 与 `card_uid` | **成立**：`fire_count=1 target_id=1 card_uid=2 target_ids=[1]` |
| F. 距离钩子链路的三层贯通 | M1 完成后，用探针技能覆盖 `ignores_card_distance_limit_to_target()` 并返回 `true`，分别查询【杀】与非【杀】距离牌 | 【杀】对任意角色变为合法；其他距离牌合法目标集合与改动前逐字一致 | 待 M1 验证门补测 |
| G. `changeSkillsAfter` 可被订阅并收到复原派发（该时机全项目零订阅者） | 探针在 `install()` 订阅 `changeSkillsAfter`，随后调用 `restore_character_card_skills()` | 回调触发且 `change_type` 正确 | **成立**：`fire_count=1 change_type=restore_character_card_skills skill_ids=["haoxi","lianxi"]`。探针不在武将固有技能表内因而未被卸载，说明新实例能收到自己在 `install()` 中订阅的这次派发 |

**探针文件**：`tests/tmp_m0_probe_test.gd` + `.tscn`（临时文件，`tmp_` 前缀使其不属于正式测试集；M4.7 时改写为正式回归用例或删除）。

**输出要求**：实测结论已回填 `design.md` §15。若某项不成立，先按 `design.md` §13 的降级思路调整设计并**回报用户**，不得静默降低原文语义。

**验证门 G0（已通过）**：A/B、C、D、E、G 全部有明确结论；F 在 M1 验证门内补测；`design.md` 已回填。

**回滚点**：删除临时探针场景即可，无产品代码改动。

---

## M1 核心层三处扩展

依据 `design.md` §3。

| 步骤 | 内容 |
|---|---|
| M1.1 | 在 `scripts/core/match_controller.gd` 新增 `replace_card_use_targets(card_uid, target_ids, reason="") -> bool`，复用 `_find_pending_card_timing_event()`（`:8160`）定位等待窗口，同时写共享上下文与等待窗口 `data["target_ids"]` |
| M1.2 | 在 `scripts/core/match_controller.gd` 新增 `mark_card_use_limit_exempt(player_id, card_definition_id, reason="") -> bool`，写 `play_phase_card_use_limit_exempt_history` 与 `card_use_limit_exempt_history`，口径与 `:12325-12327` 完全一致 |
| M1.3 | 在 `game_data/skill_definition.gd` 新增 `ignores_card_distance_limit_to_target(_card_definition, _target_id) -> bool`（默认 `false`）；在 `scripts/core/match_controller.gd` 新增 `skill_ignores_card_distance_limit_to_target(player_id, card_definition, target_id) -> bool`（镜像既有 `:8864` 的聚合写法）；在 `scripts/core/card_rule_service.gd` 新增私有聚合函数（镜像 `:498`）并在 `_validate_target` 的 `ignore_distance_limit` 表达式上追加 `or` 分支（`:369`） |
| M1.4 | 每个新增函数/钩子独占 `##` 文档注释：作用、参数含义、返回值、调用场景、注意事项（尤其"必须由技能侧保证幂等""默认 `false` 不影响任何既有技能"） |

**验证门 G1**（核心层改动必须跑核心回归 + 距离回归）：

```powershell
& $godot --headless --path . res://tests/event_runtime_test.tscn
& $godot --headless --path . res://tests/skill_settlement_runtime_test.tscn
& $godot --headless --path . res://tests/gameplay_regression_test.tscn
& $godot --headless --path . res://tests/phase_progression_test.tscn
```

全部 PASS。**距离回归断言**（可先在 M0 探针里用临时覆盖验证钩子链路，M6 再落成正式断言）：无技能覆盖时 `validate_use` 的全部拒绝原因与改动前逐字一致；有覆盖时只对"牌 = 【杀】且目标 = 距离最远角色"放行。**回滚点**：删除三个新函数并还原 `_validate_target` 的 `or` 分支（无既有调用者，回滚无副作用）。

---

## M2 【连戏】改写

依据 `design.md` §4。

| 步骤 | 内容 |
|---|---|
| M2.1 | 改 `MAX_RECAST_TIMES` 为 `9`、`DAMAGE_DIVISOR` 为 `3`，并更新两处常量注释中过期的"七次/2"描述（**不改变量名**） |
| M2.2 | 元数据改为 `trigger:"phaseUseBegin"`、`ui_enabled:false`、`enable:"phaseUse"`；`description` 换成 R1.1 逐字文本 |
| M2.3 | `can_activate()` 恒 `false`；`activate()` 返回提示文本；`append_play_phase_actions()` 置空（对标 `xingjun.gd:36-48`） |
| M2.4 | `phaseUseBegin` 回调：无基本牌则不建询问；否则建布尔询问 `{"kind":"lianxi_phase_use_begin","ai_allow_confirm":true}` |
| M2.5 | `continue_selection()` 新增 `lianxi_phase_use_begin` 分支：取消不移动牌不耗额度；确认则 `_request_recast_choice(0, false)` |
| M2.6 | `_execute_recast_round()` 后接入嵌套恢复：`host.has_pending_card_choice()` → `defer_settlement({"kind":"lianxi_recast_continue","recast_count":n})`，新增 `continue_settlement()` 恢复窗口 |
| M2.7 | AI：新增 `score_ai_choice()` 的 Begin 分支（确认需严格正收益）；预期轮数上限改用 `MAX_RECAST_TIMES` 而非字面量 |
| M2.8 | 更新 `tests/huohua_joy_test.gd`：`_test_lianxi_static_definition` 换新描述、断言由 `PLAY_PHASE_ONCE_TAG` 改为阶段开始语义；`_test_lianxi_recast_times_and_damage` 改为经由 `phaseUseBegin` 触发并重铸 9 次验证 `Y=3`；`_test_lianxi_requires_basic_card` 改为断言"不创建 Begin 询问"；PASS 行 `lianxi_recast=9` |

**验证门 G2**：

```powershell
& $godot --headless --path . res://tests/huohua_joy_test.tscn
```

PASS 且输出含 `lianxi_recast=9`。**回滚点**：`git checkout -- game_data/skills/lianxi.gd tests/huohua_joy_test.gd`。

---

## M3 【同袍】与丹恒·腾荒

依据 `design.md` §5、§10。

| 步骤 | 内容 |
|---|---|
| M3.1 | 新增 `game_data/skills/tongpao.gd`：4 节轮回技静态定义、节索引/数值常量、`can_activate()` 逐节判定、`activate()` 与 `continue_selection()`、②③④ 的空节推进 |
| M3.2 | ④ 的两步交互：先选角色（区域内至少一张牌的其他存活角色），再 `get_player_zone_candidates` + `discard_selected_player_card`（**带保护**） |
| M3.3 | ③ 只允许手牌作费用：`get_hand_candidates` + `discard_selected_hand_cards`（不使用 `discard_selected_hand_equipment`） |
| M3.4 | ① 用 `get_owner_skill_player().damage(SELF_DAMAGE_AMOUNT, get_owner_skill_player())`（伤害，护盾可吸收；不是 `loseHp`） |
| M3.5 | 补全 AI：`append_play_phase_actions()` + `score_ai_action()`，覆盖 R2.4 明示分支与 `design.md` §5.4 的通用分支 |
| M3.6 | **本里程碑只创建技能文件，不创建武将定义**：丹恒·腾荒同时拥有【同袍】与【岳峙】，而【岳峙】要到 M4 才实现；若此刻就创建 `danheng_tenhuang.gd`，它会引用不存在的 `yuezhi.gd`，导致 `GameDatabase` 校验失败、`smoke_test` 直接红灯。武将定义统一在 M4 与【岳峙】一起落地 |

**验证门 G3**：

```powershell
& $godot --headless --path . res://tests/smoke_test.tscn     # 可开局 + validation_errors 为空
& $godot --headless --path . res://tests/reincarnation_mechanics_test.tscn
& $godot --headless --path . res://tests/ai_policy_test.tscn
```

> `smoke_test.gd` 中"武将技能总数"等计数断言会因新增内容变化，按 `verification.md` 第五节以**代码实测值**同步常量，并在输出中说明口径。
> 本里程碑只新增 1 个技能文件（【同袍】），武将数不变；丹恒·腾荒的武将定义在 M4 落地后再同步一次武将相关计数。

**回滚点**：删除两个新文件（武将定义此时可暂不接入测试）。

---

## M4 【岳峙】

依据 `design.md` §6。

| 步骤 | 内容 |
|---|---|
| M4.1 | 新增 `game_data/skills/yuezhi.gd`：`limited:true`、订阅 `useCard` |
| M4.2 | 回调条件校验（存活、额度、目标数 ≥ 2、未改写、非重入）→ 创建可取消布尔询问 |
| M4.3 | `continue_selection` 确认后：`replace_card_use_targets(card_uid, [owner] × X)`、`announce_activation(...)`、置结算期守卫状态 |
| M4.4 | 守卫：`damageBegin4`（`role="target"`）与 `recoverBegin`（`role="target"`）按"首次放行、其后 `event.cancel()`"实现 |
| M4.5 | 清理：订阅该牌 `useCardAfter` 清除守卫；`uninstall()` 兜底清除 |
| M4.6 | 补全 AI：按 `design.md` §6.5 分支 + 通用分支（额度耗尽 / 1 血不自救） |
| M4.7 | 把 M0 的探针场景改写为 **正式回归用例**：覆盖"成为唯一目标 + 结算 X 次 + 首次伤害后其余被防止 + 结算完毕守卫解除" |
| M4.8 | 新增 `game_data/characters/danheng_tenhuang.gd`（稳定 `id` `danheng_tenhuang`，显示名「丹恒·腾荒」，翁法罗斯，男，4 体力，技能顺序 **【同袍】→【岳峙】**）；**必须等 `tongpao.gd` 与 `yuezhi.gd` 都存在后再创建**，并在同一里程碑内补齐武将计数断言 |

**验证门 G4**：

```powershell
& $godot --headless --path . res://tests/gameplay_regression_test.tscn
& $godot --headless --path . res://tests/ai_policy_test.tscn
& $godot --headless --path . res://tests/<新武将专项>.tscn
```

特别复核：`useCardToOmitted/Excluded`、`dying`/`die` 流程在重复目标下不被破坏；守卫在牌结算完毕后**确实解除**（用一张后续伤害牌验证）。

---

## M5 【断界】与瓦尔特

依据 `design.md` §7、§10。

| 步骤 | 内容 |
|---|---|
| M5.1 | 新增 `game_data/skills/duanjie.gd`：元数据、选项常量、`character_form_state` **惰性**读写（键 `duanjie_remaining_options`；**缺失即视为完整 `[1,2,3,4]`**，因此 `install()` 不写初始值，复原只需 `erase`） |
| M5.2 | 在 `install()` 订阅 `changeSkillsAfter`（role `player`）：**按 `change_type` 过滤**——仅 `restore_character_card_skills` / `replace_character_card` 且 `skill_ids` 含 `"duanjie"` 时 `erase` 该键，使「复原武将牌上的技能」复原为完整 4 项；**不得**响应 `restore_limited_skill_use`（同一时机、不同语义） |
| M5.3 | `can_activate()`：本阶段未发动 且 `剩余列表 ∩ 有合法目标的选项` 非空 |
| M5.4 | `activate()` / `continue_selection()`：`request_control_selection` 选项 → `request_target_selection` 目标 → 执行 → `pop_back()` |
| M5.5 | 四个选项的执行：选项 1/2 用 `set_player_linked(绝对设置)`；选项 3/4 先判 `face_down` 再 `turn_over_player(切换)` |
| M5.6 | 取消任一步都不删除列表项、不消耗额度；执行成功才删除列表最后一项并 `announce_activation` |
| M5.7 | 补全 AI：按 `design.md` §7.5 |
| M5.8 | 新增 `game_data/characters/waerte.gd`（`waerte`，星穹列车，男，4 体力，技能【断界】） |

**验证门 G5**：

```powershell
& $godot --headless --path . res://tests/smoke_test.tscn
& $godot --headless --path . res://tests/ai_policy_test.tscn
& $godot --headless --path . res://tests/<新武将专项>.tscn
```

专项断言必须覆盖 **AC11**（四次发动的可用范围依次收缩到 `{1,2,3,4}`→`{1,2,3}`→`{1,2}`→`{1}`；`restore_character_card_skills()` 后回到完整 4 项；`restore_limited_skill_use()` **不**重置列表；存档往返后进度不丢失）与 **AC12**（四个选项各自只对对应状态的角色生效）。

---

## M6 【遥击】【凌霜】与彦卿

依据 `design.md` §8、§9、§10。

| 步骤 | 内容 |
|---|---|
| M6.1 | 新增 `game_data/skills/yaoji.gd`：`lock:true`、覆盖 §3.3 的 `ignores_card_distance_limit_to_target()`——**先判牌是【杀】（`effect_id == "slash"`）、再判目标是距离最远角色**，两者都满足才返回 `true`；`_is_farthest_opponent()` 必须先过滤死亡/离场（并列全含） |
| M6.2 | 新增 `game_data/skills/lingshuang.gd`：订阅使用者视角逐目标时机（确认走写回的 `useCardTo*` 之一） |
| M6.3 | 【凌霜】效果：询问 → 记录 `was_face_down` → `turn_over_player` → 由正面翻至背面时盲选弃置目标两张手牌（`visible=false` 候选 + `discard_selected_hand_cards`，不足两张弃全部）+ `mark_card_use_limit_exempt()` |
| M6.4 | 幂等：同一张【杀】的多个目标只有第一次带附加效果；次数豁免用 `_exempted_card_uids` 保证只调一次 |
| M6.5 | 补全 AI：按 `design.md` §9.4（≥2 手牌敌人无条件发动；其余按翻面成本估值；1 血被翻面强负分） |
| M6.6 | 新增 `game_data/characters/yanqing.gd`（`yanqing`，仙舟联盟，男，3 体力，技能顺序【遥击】→【凌霜】） |

**验证门 G6**：

```powershell
& $godot --headless --path . res://tests/smoke_test.tscn
& $godot --headless --path . res://tests/ai_policy_test.tscn
& $godot --headless --path . res://tests/<新武将专项>.tscn
```

专项断言必须覆盖 **AC13**（对最远角色使用【杀】合法、对非最远角色仍受距离约束，且【顺手牵羊】等其他距离牌的合法目标集合不受任何影响）与 **AC14**（正面→背面时弃两张手牌 + 本阶段可继续使用【杀】）。

---

## M7 文档同步、全量回归与交付物

### M7.1 文档同步（`documentation-sync.md` 矩阵 + 内容层规范）

| 文档 | 必须写入的内容 |
|---|---|
| `docs/内容制作指南.md` | 新增三处核心扩展的签名、语义、示例与注意事项（"新机制先开发 + 文档更新"铁律）：`replace_card_use_targets`、`mark_card_use_limit_exempt`，以及带目标的距离钩子 `ignores_card_distance_limit_to_target`（必须说明**为什么它需要目标参数**、与既有两个距离钩子的区别与适用场景）；「两种用牌次数语义」补充"事后豁免"入口；「当前正式武将技能」列表新增 5 项；**记录【凌霜】与【断界】分别是 `does_not_count_toward_play_limit` 与 `changeSkillsAfter` 在项目中的首个使用者**，并写明 `changeSkillsAfter` 的三种 `change_type` 取值与"订阅方必须过滤"的要求；若 M0 得出边界结论，一并写入 |
| `docs/游戏机制与玩法内容.md` | 【连戏】条目整体改写并记录新数值（9 次上限、除数 3、数值对照表、阶段开始询问语义）；新增三名武将的完整机制条目与**全部数值**（护盾 1、自伤 1、弃 1 手牌、弃 1 区域牌、X = 原目标数、选项消耗序列 `{1,2,3,4}→{1,2,3}→{1,2}→{1}`、弃置 2 张手牌、距离最远判定）；每项都要写清设计意图；【断界】须写明"选项列表随「复原武将牌上的技能」复原、且单项限定额度复原（`restore_limited_skill_use`）不重置它" |
| `docs/AI模块.md` | 五个新技能的 AI 评分口径与新增数值；若不改通用常量则明确声明"未改动全局 AI 数值" |
| `docs/卡牌系统.md` | 若 §3 端口影响用牌目标/次数的通用描述，同步补充；无影响则不改 |
| `README.md` | 更新 `huohua_joy_test` 说明（连戏 9 次 / `Y=⌊n÷3⌋` / 阶段开始询问）；新增专项测试的运行说明（含 `*_PASS` 标记）；更新「自动校验」章节 |

### M7.2 全量回归（因新增武将改变固定种子阵容，必须复核既有测试）

```powershell
& $godot --headless --path . res://tests/huohua_joy_test.tscn
& $godot --headless --path . res://tests/smoke_test.tscn
& $godot --headless --path . res://tests/ai_policy_test.tscn
& $godot --headless --path . res://tests/gameplay_regression_test.tscn
& $godot --headless --path . res://tests/event_runtime_test.tscn
& $godot --headless --path . res://tests/skill_settlement_runtime_test.tscn
& $godot --headless --path . res://tests/phase_progression_test.tscn
& $godot --headless --path . res://tests/reincarnation_mechanics_test.tscn
& $godot --headless --path . res://tests/<新武将专项>.tscn
& $godot --headless --path . res://tests/rule_timing_test.tscn
& $godot --headless --path . res://tests/health_mechanics_test.tscn
```

**禁止并发**（多个 Godot 进程会争用本机用户设置与 `.godot` 缓存）。任一失败即回到对应里程碑。

### M7.3 交付物（项目级硬性要求）

1. **学习反馈摘要**：修改思路 / 架构与设计 / Bug 原因与修复方法（如涉及）/ 关键代码解析 / 学习要点提炼（1~3 条）。
2. **Git 提交描述**：数字序号分行，每行以动词开头，一个核心动作一行，不糅合。
3. 把上述两项追加写入根目录 `临时反馈文档.md`，开头带时间戳 `YYYY-MM-DD HH:MM`，追加在末尾、保留历史。

### M7.4 需求补全的单独告知（协作规范 §一.2）

汇报时单独列出"需求未明示但实现必需"的补全项，至少包括：
- 【断界】选项无合法目标时的行为与技能熄灭条件；
- 【断界】选项列表为什么存 `character_form_state` 却仍能被复原（`changeSkillsAfter` 订阅，且必须按 `change_type` 过滤以免被单项额度复原误重置）；
- 【岳峙】结算期守卫的清理时机与兜底；
- 【遥击】为什么必须新增一条**带目标参数**的距离钩子（既有两个钩子各缺一半上下文，单独使用都会放宽非【杀】牌）；
- 【凌霜】两张手牌的盲选口径；
- 【同袍】②③④ 的空节推进。

---

## 全局质量门（每个里程碑都适用）

- [ ] 玩家可见 `description` 与需求原文**逐字一致**（含标点）。
- [ ] 每个变量独占一行注释；未擅自改动既有变量名，未删除/篡改既有注释。
- [ ] 所有魔法数字提取为带注释常量（`design.md` 列出的常量全部落地）。
- [ ] `context` 中只有可序列化数据。
- [ ] 正式技能已自带配套 AI，且**补全了通用决策逻辑**（不止需求明示分支）。
- [ ] AI 评分复用 `NonameAIEvaluator.score_resource_change()` 与公开资源常量，未重复声明换算比例。
- [ ] 未新增牌名/技能 ID 白名单；未改动全局 AI 常量。
- [ ] `GameDatabase.validation_errors` 为空。
- [ ] 本里程碑的验证门命令全部实际运行过，报告里给**真实观测输出**，不写"应该通过"。
