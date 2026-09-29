# 执行计划：欢愉技强制发动机制与爻光/星/穹三名武将

> 设计依据 `design.md`；需求与验收依据 `prd.md`。分派模式为 **inline**（DeepSeek Harness）：编辑前加载 `trellis-before-dev`，编辑后跑 `trellis-check`。

---

## 零、开工前置

- [x] 加载 `trellis-before-dev`，确认已读 `content/skill-authoring.md`、`content/content-ai.md`、`content/naming-and-directory.md`、`adapters/ai-pipeline.md`、`core/event-runtime-phases.md`。
- [x] 确认 Godot 可执行文件路径：`Get-Command godot*` / 已知 `4.6.3` 构建。测试命令模板：
      `<godot> --headless --path . res://tests/<name>.tscn`
- [x] 记录改动前的基线测试结果（`smoke_test` + `ahha_moment_test` + `huohua_joy_test`），便于对比回归。

---

## 一、阶段 A：机制底座（core + data + ui）

### A1 效果层数落点（对应 `design.md` §3.1，D7 修正）

- [x] **不新增 `PlayerState` 字段、不改快照与存档格式。**
- [x] 凶星层数键名常量集中在 `xiongxing.gd` 顶部声明（`DAMAGE_STACK_STATE_KEY` / `MAX_HP_GUARD_STATE_KEY`），读写走既有 `PlayerState.character_form_state`（先例 `lunhui.gd:51`、`xinji.gd:95`、`zhuxv.gd:162`）。
- [x] 实现时统一定义一对文件内辅助函数（读层数 / 写层数并同步刷新角标），避免多处重复读写与角标重写。
- [x] 校验：序列化往返（`to_dict`→`from_dict`）后层数与角标文本一致（层数存放于既有跨回合私有记忆字典，随权威存档往返）。

### A2 独立欢愉技演出与额外阿哈时刻（`design.md` §3.2，D1）

- [x] `scripts/core/ahha_moment_system.gd`：
  - [x] 新增 `_standalone_context: Dictionary`（独占行注释），`shutdown()` / `configure()` 一并清空。
  - [x] 新增 `try_perform_single_joy_skill(player_id, skill_id, completion_context) -> bool`（单技能入队；`can_perform_joy_skill()` 为假返回 false）。
  - [x] 新增 `try_trigger_extra_moment(trigger_player_id, completion_context) -> bool`（**绕过**概率与 `_triggered_this_round`；参演序列为空返回 false 且不消耗随机数）。
  - [x] 新增只读诊断 `is_standalone_performance() -> bool`。
  - [x] `_complete_all_performances()` 分流到 `_host.continue_after_standalone_joy_performance(...)`。
  - [x] standalone 演出使用独立公开日志模板（不复用正常阿哈时刻模板）。
- [x] `game_data/skill_definition.gd`：新增可覆盖钩子 `continue_joy_performance(context) -> void`（默认空实现，注释说明由控制器在 standalone 队列排空后回调）。
- [x] `scripts/core/match_controller.gd`：新增 `continue_after_standalone_joy_performance(context) -> void`（按 `skill_owner_id` + `skill_character_generation` 复核实例，范式照 `_complete_active_independent_play_phase`）。
- [x] **回归保护**：`_standalone_context` 为空时行为与改动前逐位一致（既有 `ahha_moment_test` 必须全绿）。

### A3 通用只读查询与「场上」候选（`design.md` §3.3、§五）

- [x] `scripts/core/match_controller.gd`：
  - [x] `get_field_card_candidates(viewer_id, include_self = true) -> Array[Dictionary]`（复用 `_serialize_choice_candidate` + `can_discard_player_card`；跳过死亡/离场、已废除装备槽与已废除判定区；不含手牌）。
  - [x] `get_joy_skill_ids(player_id) -> Array[String]`（参演编号升序、技能 ID 字典序）。
  - [x] ~~`get_joy_skill_count(player_id) -> int`~~ → **改为 AI 层** `NonameAIEvaluator.get_side_joy_skill_count(...)` 与 `character_has_joy_skill(...)`，只读静态元数据（`design.md` §五修正）。
- [x] 校验：`get_field_card_candidates` 只返回 `equipment`/`judgment` 两种 `zone`（测试断言候选含判定区与装备区牌、排除手牌）。

### A4 好戏窗口与 UI 取消按钮收敛（`design.md` §3.4）

- [x] `scripts/ui/card_selection_panel.gd`：`:312`、`:464` 的取消按钮可见性收敛为**只由 `allow_cancel` 决定**（与 `:287`、`:959`、`match_table.gd:4810` 口径统一），并补注释说明「可选 0 张」不等于「允许取消」。
- [x] **影响面核对**：`grep` 出全部 `min_select=0 / min_card_select=0` 且 `allow_cancel=false` 的生产调用点，逐个确认新行为正确（生产调用点全部满足「`min_select==0` ⇒ `allow_cancel==true`」或「`allow_cancel==false` ⇒ `min_select>=1`」，因此新口径在生产中行为中性；仅 `tests/skill_choice_test.gd` 使用组合请求）。
- [x] 跑 `res://tests/ui_layout_test.tscn` + `res://tests/inline_hand_choice_test.tscn` 回归（均通过）。

**回滚点 A**：A1–A4 全部为新增分支或两行可见性收敛，未触碰既有技能语义；此点可独立回滚而不影响后续阶段。

---

## 二、阶段 B：好戏改写（content）

- [x] `game_data/skills/haoxi.gd`：
  - [x] `description` 改为 R2.1 原文（**去掉「可」字**，其余一字不动）。
  - [x] `perform_joy_skill()` 的目标选择 `allow_cancel` 改为 `false`（提取为 `ALLOW_TARGET_CANCEL` 常量），`MIN_TARGET_COUNT` 保持 `0`。
  - [x] `continue_selection()` 保留未确认的防御分支，注释更新为「请求已不可取消，此分支只兜底异常提交」。
- [x] `tests/huohua_joy_test.gd`：更新正文期望字符串，并补断言「请求 `allow_cancel == false`」（0 名目标确认后净得 2 张基本牌沿用原断言）。
- [x] 跑 `res://tests/huohua_joy_test.tscn`（通过）。

---

## 三、阶段 C：爻光（凶星 + 鸿运）

- [x] `game_data/skills/xiongxing.gd`（`design.md` §4.1）
  - [x] 元数据：`joy_skill=true`、`performance_number=116`、`description` 逐字原文。
  - [x] `perform_joy_skill()`：单目标（含自己）、`allow_cancel=false`、层数 +1、刷新角标、`finish_joy_skill_performance()`。
  - [x] `damageBegin3` 加伤（按下述修正用「目标身上的预留事件 ID」防嵌套与多实例重复）+ `damage` 消费全部层数 + `damageCancelled`/`damageZero` 释放占用。
  - [x] `loseMaxHpBefore`（`"target"`）防止自身上限减少，保护一次性消耗。
  - [x] 角标：单一条目 ID `"xiongxing"`、`order=50`、文本 `凶星` / `凶星xN`（N≥2）、归零移除。
  - [x] AI：`get_threat` 集火权重 + 敌方态度；自选条件（`max_hp == 1` 且我方欢愉技数 − 敌方 ≥ 2）。
- [x] `game_data/skills/hongyun.gd`（`design.md` §4.2）
  - [x] `phaseBefore` 订阅 + `roundStart` 额度重置；前置判据按 `design.md` §八.1。
  - [x] 确认 → `try_trigger_extra_moment` → `continue_joy_performance()` 里 `change_max_hp(-1)`（自行 `add_log`）。
  - [x] AI 按 `d = 我方 − 敌方` 的三段判据。
- [x] `game_data/characters/yaoguang.gd`（`xianzhou` / `female` / `3` / `[xiongxing, hongyun]`）。
- [x] 校验：`GameDatabase.validation_errors` 为空（正文类型段声明与 `joy_skill` 标签双向一致；为此修正了正文类型声明的识别口径，见「实现期记录」）。

---

## 四、阶段 D：星与穹（咬它 + 好活 + 当赏）

- [x] `game_data/skills/yaota.gd`（共用，`design.md` §4.3）
  - [x] `phaseBefore` 订阅；`_used_suits` 整局不重置（**未照抄弦奏的 `_sync_round_state()`**）。
  - [x] 候选筛选 → 组合选择（1 手牌 + 1 角色，含自己，`allow_cancel=true`）。
  - [x] 结算：先锁花色额度（失败回滚）→ 弃置 → 有欢愉技走 `try_perform_single_joy_skill`（**不询问**）；无则 `request_extra_play_phase`（并在嵌套选择存在时先 `defer_settlement`，见「实现期记录」）。
  - [x] 实现 `continue_joy_performance()` 与 `continue_extra_phase()` 两条收尾。
  - [x] AI 按 R4.2 优先级加权 + 「最高优先级是自己时只弃低价值牌」阈值。
- [x] `game_data/skills/haohuo.gd`（120，`design.md` §4.4）：`get_field_card_candidates` → 弃置 → 回报结束；AI 优先我方延时锦囊。
- [x] `game_data/skills/dangshang.gd`（120，`design.md` §4.5）：令一名角色摸 1 张。
- [x] `game_data/characters/xing_huanyv.gd`（`huanyu` / `female` / `4` / `[yaota, haohuo]`）。
- [x] `game_data/characters/qiong_huanyv.gd`（`huanyu` / `male` / `4` / `[yaota, dangshang]`）。

**⚠️ 本阶段最高风险项（`design.md` §七.2）**：`request_extra_play_phase` 在 `phaseBefore` 的恢复语义无先例。
**结论：实测通过，无需回退方案。** 依据：`turn_start_service.resolve()` 用**显式步骤列表**推进回合开始（不读取 `state.current_phase` 决定下一步），而 `_complete_active_independent_play_phase()` 恢复 `original_phase`/`original_phase_index`/`current_player_id` 后只调用技能回调与 `_resume_settlement_pipeline()`、不自行推进阶段，因此从 `phaseBefore` 启动的独立出牌阶段结束后，回合开始序列会正常继续到 `phaseBeforeStart`…`phaseZhunbei`。测试 `_test_yaota_falls_back_to_extra_play_phase` 断言阶段建立（受益人成为 `current_player_id`、`current_phase == "play"`）。

**回滚点 D**：三份武将文件与两份技能文件可单独移除，不影响阶段 A–C。

---

## 五、阶段 E：测试

- [x] 新增 `tests/huanyu_yaoguang_xing_qiong_test.gd` + `.tscn`（照既有 `*_mechanics_test.gd` 结构），断言：
  - [x] 三名武将静态资料（`display_name`/`gender`/`faction`/`max_hp`/`skills`）。
  - [x] 五个技能的正文逐字一致；`joy_skill` 与 `performance_number` 正确（凶星 116、好活 120、当赏 120；鸿运/咬它非欢愉技），并断言咬它/鸿运正文不被类型声明判定误判。
  - [x] 好戏：请求 `allow_cancel == false`（在 `huohua_joy_test.gd` 中补充）；0 名目标确认 → 净得 2 张基本牌。
  - [x] 凶星：单层角标为 `凶星`、两层为 `凶星x2`；`damageBegin3` 加伤 +N 且消费后清空；自选时 `loseMaxHpBefore` 被取消、上限不变，且保护一次性消耗。
  - [x] 鸿运：确认后额外演出立即开始；演出结束后上限 −1；每轮限一次（同轮再次进入不再询问）。
  - [x] 咬它：目标欢愉技被强制演出（链路完整收尾）；同花色第二次被拒；其他花色仍可发动；无欢愉技 → 目标获得独立额外出牌阶段。
  - [x] 好活：候选含装备区/判定区牌、排除手牌；弃置后实体进入弃牌堆。
  - [x] 当赏：目标摸 1 张。
- [x] 在 `README.md`「自动校验」章节补充新测试场景说明。

---

## 六、验证命令与通过标准

```bash
# 内容/机制第一道关（必须全绿）
<godot> --headless --path . res://tests/smoke_test.tscn
<godot> --headless --path . res://tests/ahha_moment_test.tscn
<godot> --headless --path . res://tests/huohua_joy_test.tscn
<godot> --headless --path . res://tests/huanyu_yaoguang_xing_qiong_test.tscn   # 新增

# 受影响面回归
<godot> --headless --path . res://tests/new_character_mechanics_test.tscn
<godot> --headless --path . res://tests/corner_badge_test.tscn
<godot> --headless --path . res://tests/ui_layout_test.tscn
<godot> --headless --path . res://tests/inline_hand_choice_test.tscn
<godot> --headless --path . res://tests/ai_policy_test.tscn
<godot> --headless --path . res://tests/phase_progression_test.tscn
```

通过标准：各场景打印 `*_PASS`；`GameDatabase.validation_errors` 为空且可正常开局；报告给出**实际观察到的输出**，不写推测性结论。

**实际结果**：上述全部场景通过；另跑了 `tests/` 下**全部 72 个场景**的批量回归，结果为 **71 通过 / 1 既有失败**。唯一失败 `nakexia_mechanics_test` 与本任务无关（那刻夏静态资料的 `gender` 为 `male`，测试期望 `female`；该武将文件不在本次改动范围内）。`android_adaptation_test` 打印的是 `ANDROID_ADAPTATION_TEST_OK`（非 `*_PASS`），实际通过。

---

## 七、阶段 F：文档同步（`docs/`）

- [x] `docs/游戏机制与玩法内容.md`：欢愉技强制发动口径；三名武将与五个技能的**全部具体数值**（参演编号、层数、体力上限变化、花色额度、摸牌数、目标数）；「场上」定义；技能请求单次演出的通道说明；修正正文类型声明的判定口径描述。
- [x] `docs/内容制作指南.md`：新版式玩家视角角标 `凶星xN`、`character_form_state` 作为跨回合私有记忆的键约定、`get_field_card_candidates`、`try_perform_single_joy_skill` / `try_trigger_extra_moment` / `continue_joy_performance`、`get_joy_skill_ids`、嵌套选择必须 `defer_settlement()` 的注意事项；**修正 `:1028` 的 `change_max_hp` 签名漂移**；修正两处正文类型声明判定口径。
- [x] `docs/AI模块.md`：凶星集火权重、鸿运欢愉技数量差三段判据、咬它目标优先级与「最高优先级是自己」的低价值牌阈值、好活弃置优先级、当赏目标口径，并说明 AI 侧欢愉技计数只读静态元数据。
- [x] `docs/架构说明.md`：`AhhaMomentSystem` 的 standalone 通道说明；修正轮回技/欢愉技正文类型声明判定口径；确认本次**未改动** `PlayerState` 结构与快照/存档格式。

---

## 八、阶段 G：收尾

- [x] 跑 `trellis-check`（规范符合性、跨层数据流、复用与一致性）。
- [x] 产出「学习反馈摘要」+「Git 提交描述」（数字序号分行、一行一动作）。
- [x] 追加到 `临时反馈文档.md`（开头带 `YYYY-MM-DD HH:MM` 时间戳，追加不覆盖）。
- [x] 单独告知「自行补全的配套逻辑」清单（`design.md` §八）。
- [ ] `task.py archive` 归档任务（需先 `set-branch`：当前分支 `master` 与任务的 `base_branch` 相同，归档会被拒绝）。

---

## 九、`task.py start` 前的最后检查

- [x] `prd.md` 已过收敛（无重复事实、无遗留临时章节、锚点与验收映射完整）。
- [x] `design.md` / `implement.md` 齐备（复杂任务要求）。
- [x] 阻塞性开放问题为空（D1–D8 已全部裁决）。
- [x] 高风险项（`design.md` §七.2）已准备好最小验证与回退方案。
- [x] **用户已就最终规划摘要给出明确批准**（`task.py start` 与实现必须在此之后的下一轮消息中进行）。

---

## 十、实现期记录（执行中发现的事实与修正）

以下四项均为**实现阶段才发现**、规划文档未预见的问题，全部已修复并落地到测试。

### 10.1 `_start_requested_performance` 的数组类型收窄（真实缺陷）

`try_perform_single_joy_skill()` 原本把参演项写成字面量 `_start_requested_performance([entry], ...)`。`[entry]` 是**无类型 `Array`**，传给形参 `Array[Dictionary]` 时被收窄为**空数组**，于是 `_advance_to_next_valid_entry()` 的 `while` 直接跳过并进入 `_complete_all_performances()`——演出"零参演"地静默完成：接口返回 `true`、队列为空、请求方永远等不到 `continue_joy_performance` 回调，且不产生任何玩家可见窗口。

修复：显式声明 `var entries: Array[Dictionary] = [entry]` 后再传入。诊断依据是测试输出的 `started=true` 与 `queue=[]`、`index=-1` 同时成立。

### 10.2 嵌套选择必须先 `defer_settlement()`（真实缺陷）

`MatchController.request_card_choice()` 的首行守卫是 `not _pending_card_choice.is_empty()` 时直接 `return []`。咬它与鸿运都在**自己的 `continue_selection()` 内部**立即驱动一场演出，而演出中首个欢愉技要创建自己的选人窗口——此时旧请求尚未清理，新请求被守卫**静默拒绝**，表现为"费用已支付但什么也没发生"。

修复：在调用驱动入口前判断 `host.has_pending_card_choice()`，为真时用 `defer_settlement({...})` 延后，并在新增的 `continue_settlement()` 中执行同一段逻辑（完全复用弦奏 `xianzou.gd:66-83` 的既有范式）。该注意事项已写入 `docs/内容制作指南.md`。

### 10.3 凶星加伤幂等键的存放位置（设计修正）

原设计把「本次伤害已被凶星加成」标记写进伤害事件的 `event.data`。实测表明 `damageBegin3` 写入的键在 `damage` 窗口**读不到**——伤害各修改窗口的 `data` 不保证是同一份字典（既有【追歼】因此只把预留 ID 存在实例字段里）。结果是伤害加成生效、但层数永不消费。

修复：把「已预留加成、尚未结算的伤害事件 ID」改存到**目标角色的 `character_form_state`**。这一改同时解决三件事：(1) 跨窗口可靠；(2) 多名义光同时在场时对同一伤害只加成一次；(3) 外层伤害内部嵌套出的新伤害因"目标已有未结算预留"而被跳过。消费改为由 `_release_reservation()` 的布尔返回值充当"本次伤害确实由凶星加成过"的唯一凭据，因此多名实例共享的消费动作只会成功一次。

### 10.4 测试数据前提：好戏只把"持有手牌的其他角色"当作合法目标

`haoxi.gd:146` 的 `_get_discardable_target_ids()` 会过滤掉没有手牌的角色。测试若没给其他角色发手牌，好戏会"零候选"地立即 `finish_joy_skill_performance()`，链路看起来像"没有驱动演出"。这是**测试数据前提**而非生产缺陷；修正测试数据后链路与断言全部成立。
