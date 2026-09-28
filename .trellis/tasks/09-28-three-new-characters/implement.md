# 实施计划：新增三名武将（海瑟音·那刻夏·大黑塔）

> 依赖 `design.md` 的技术契约。本文件规定**执行顺序、改动单元、提交切分与验证**。
> 原则：一个改动单元 = 一个可独立验证、可独立回滚的最小步骤。

---

## 一、实施总则

1. **先基础设施、后内容**：每个批次先落权威层端口并跑通单测，再写技能内容，最后补文档。
2. **提交粒度**：一个改动单元一次提交，提交描述按 `AGENTS.md` 规范四用数字序号分点。
3. **每批必交**：`学习反馈摘要` + `Git 提交描述` 追加到 `临时反馈文档.md`（带 `YYYY-MM-DD HH:MM` 时间戳），顺序为「先反馈摘要、后提交描述」。
4. **TDD 取向**：权威层端口先写测试断言（红）→ 实现（绿）→ 内容层接入。
5. **禁止事项**：核心层不得出现牌名/技能 ID 白名单；内容层不得 `new RandomNumberGenerator`、不得裸 `randi()`；AI 钩子内不得访问 `host`。
6. **每步收尾**：跑该层全部既有回归测试，确认无新增 `ERROR` / `SCRIPT ERROR` / 失败断言。

---

## 二、批次与依赖

| 批次 | 武将 | 依赖的权威层改动 |
|---|---|---|
| 批 1 | 海瑟音（泛音、回涛） | U1 弃置批次（回涛零改动，仅订阅） |
| 批 2 | 那刻夏（逐虚、揭质、留白） | U2 随机端口、U3 永久移除、U4 复原排除 |
| 批 3 | 大黑塔（解构、灵感、看破） | U5 牌名记录容器、U6 目标模式覆写（看破零改动，复用 `exclude_card_target`） |

---

## 三、改动单元

### U1 权威层：弃置批次聚合（M1）

**文件**：`scripts/core/rule_timing_catalog.gd`、`scripts/core/match_controller.gd`

1. `rule_timing_catalog.gd:54` 的 `CARD_MOVE_TIMINGS` 追加 `"cardsDiscardedBatchAfter"`。
2. `MatchController` 新增 `_discard_batch_stack: Array[Dictionary]` 与 `_next_discard_batch_id: int`。
3. 新增 `_begin_discard_batch(player_id, reason) -> int` / `_end_discard_batch() -> void`（弹出后按 `card_uids` 非空派发 `cardsDiscardedBatchAfter`）。
4. `_move_to_discard`（`MC:13727`）与 `_move_card_with_timings`（`MC:13754`）在 `timing_data` 注入 `discard_batch_id`，并把本张 uid 追加到栈顶层。
5. 五个批量入口包裹批次：`discard_card_from_hand`（`MC:6226`）、`discard_all_hand_cards`（`6251`）、`discard_n_from_player`（`6299`）、`discard_n_from_hand_equipment`（`6600`）、`discard_selected_hand_equipment`（`7869`）。

**验证**：新增测试断言「一次弃置黑桃+红桃 → 恰好 1 次批次事件、载荷含 2 张 uid」；断言嵌套弃置时内层批次独立。
**连带**：`tests/rule_timing_test.gd` 的时机目录断言需同步。

### U2 权威层：技能随机端口（M2）

**文件**：`scripts/core/match_controller.gd`（`_shuffle_array`（`MC:14067`）附近）

1. 新增 `pick_random_index(candidate_count: int) -> int`。
2. 新增 `pick_random_element(candidates: Array) -> Variant`。
3. 两者内部统一走 `_rng`，并**追加 `state.random_history`**（照抄 `MC:6513` 的写法）。

**验证**：同种子下两次运行结果一致；`random_history` 增长条数正确；`candidate_count<=0` / 空数组安全返回。

### U3 权威层：永久移除固有技能（M3）

**文件**：`scripts/core/match_controller.gd`、`scripts/data/player_state.gd`

1. `PlayerState` 新增 `lost_intrinsic_skill_ids: Array[String]`（声明 / `from_authoritative_dict` / `to_dict` 三处 + `_build_conquest_save_data`）。
2. `MatchController` 新增 `remove_intrinsic_skill_permanently(player_id, skill_id, reason="") -> bool`：`uninstall()` → `erase` → 清 `acquired_skills`/`temporary_skills` 同名记录 → `clear_reincarnation_skill_state` → 写 `lost_intrinsic_skill_ids` → 派 `changeSkillsAfter` → `_emit_state()`。
3. 新增 `remove_all_intrinsic_skills(player_id, reason="") -> int` 与 `has_lost_intrinsic_skill(player_id, skill_id) -> bool`。
4. **四处安装点过滤**：`_install_all_character_skills`（`MC:9208`）、`_reinstall_character_skills_for_player`（`9254`）、`restore_character_card_skills`（`4293`）、`_replace_native_character_skills`（`4236`）。
5. `_append_limited_skill_usage_to_snapshot`（`MC:14959`）下发该字段。

**验证**：移除后实例表无该技能、`reincarnation_skills` 无残留、`changeSkillsAfter` 派发；**读档/`_install_all_character_skills` 后不复活**。

### U4 权威层：复原排除参数（M4）

**文件**：`scripts/core/match_controller.gd:4282`

1. 签名扩展为 `restore_character_card_skills(player_id: int, reason: String = "", exclude_skill_ids: Array[String] = []) -> bool`。
2. 在遍历 `native_skill_ids` 时跳过 `exclude_skill_ids`。

**验证**：既有调用（不传第三参）行为不变；传排除项后该技能额度/轮回进度**不**被复位，其余技能全部复位。

### U5 权威层：牌名记录容器（M5）

**文件**：`scripts/data/player_state.gd`、`scripts/core/match_controller.gd`

1. `PlayerState` 新增 `skill_recorded_card_names: Dictionary`（`{skill_id: Array[String]}`，声明 / `from_authoritative_dict` / `to_dict` 公开 / `_build_conquest_save_data`）。
2. `MatchController` 新增三个端口：`get_skill_recorded_card_names(player_id, skill_id) -> Array[String]`、`add_skill_recorded_card_name(player_id, skill_id, card_definition_id) -> bool`（去重）、`remove_skill_recorded_card_name(player_id, skill_id, card_definition_id) -> bool`。

**验证**：写读一致、去重、LAN 快照含该字段、存档往返一致。

### U6 权威层：目标模式覆写（M6）

**文件**：`scripts/core/card_rule_service.gd`、`scripts/core/match_controller.gd`、`scripts/ai/noname_ai_evaluator.gd`、`scripts/ui/match_table.gd`

按 `design.md` M6 的 6 处落点实施覆写键 `target_mode_source_definition_id`（并支持来源牌的 `max_targets`）。其中 `normalize_targets`（`:242`）与 `list_legal_targets`（`:222`）需新增可选形参 `rule_overrides`，并同步 `MC:2111 / 11448 / 11473` 三处调用传参。

**验证**：`definition_id="nanman"` + 来源为单体牌时，`list_legal_virtual_targets` 返回可选单体集合、`validate_virtual_use` 接受 1 个目标、AI 与 UI 预览一致。

### U7 内容层：海瑟音（批 1）

**文件**：`game_data/characters/haishengyin.gd`、`game_data/skills/fanyin.gd`、`game_data/skills/huitao.gd`

1. 武将：`id="haishengyin"`、`display_name="海瑟音"`、`faction="wengfaluosi"`、`max_hp=4`、`skills=[fanyin, huitao]`。
2. 【泛音】4 节轮回技 + 半锁定技：
   - `_metadata`：`"half_locked":true`、`"reincarnation":true`、`"reincarnation_section_count":4`、`"reincarnation_has_explicit_sections":true`、`"reincarnation_each_section_once_per_play_phase":true`、`"trigger":"active/cardsDiscardedBatchAfter"`、`"enable":"phaseUse"`、`"ui_enabled":true`。
   - `can_activate` / `activate` / `continue_selection`（`kind="fanyin_discard_suit"`）走`kansha.gd` 四节模板；每节要求手牌/装备区存在对应花色的牌。
   - `install()` 订阅 `cardsDiscardedBatchAfter`（`role="player"`、`locked_segment=true`），判定整批黑/红，**先黑后红**：黑 → 令一名角色弃一张手牌（走 `request_target_selection`）；红 → 自己摸一张。
   - `uninstall()` 对称清理；`restore_limited_use()` 覆写清私有已用集合。
3. 【回涛】非锁定触发技：`install()` 订阅 `reincarnationStart`（`role="global"`），`section_count >= 3` 时对 `event.player_id` 询问是否令其摸一张牌。
4. AI：两技能各自实现 `append_play_phase_actions` / `score_ai_action` / `score_ai_choice`（泛音优先弃废牌、被迫自弃时优先红色；回涛对己方无脑发动）。

### U8 内容层：那刻夏（批 2）

**文件**：`game_data/characters/nakexia.gd`、`game_data/skills/zhuxv.gd`、`jiezhil.gd`（揭质）、`liubai.gd`

1. 武将：`max_hp=3`、`faction="wengfaluosii"`→按 `factions.json` 实际键名填写、`skills=[zhuxv, jiezhi, liubai]`。
2. 【逐虚】2 节轮回技，**整技「出牌阶段限两次」**：私有 `_used_this_play_phase:int`，`install` 订阅 `phaseUseBegin`（`role="player"`）清零；每节效果分别调 `pick_random_player_id` / `pick_random_element`。
3. 【揭质】每局限两次：私有 `_used_this_game:int`，`can_activate` 判 `< 2`，`_execute` 后自增；订阅逐虚的 `skillAfter`（`actual_activation=true`）记录上次目标以便「对相同目标执行一次相同的效果」。
4. 【留白】限定技：`"limited":true`；`activate` → `host.call("restore_character_card_skills", pid, get_id(), [get_id()])` 重置其他技能；订阅本回合结束（`phaseJieshu*`）→ `remove_all_intrinsic_skills` 令其永久失去全部技能（含自身）。
5. AI：逐虚按体力值与敌我关系降权轮回②；揭质留到对敌②；留白在「回合内能用的额度都花完」后发动。

### U9 内容层：大黑塔（批 3）

**文件**：`game_data/characters/daheita.gd`、`game_data/skills/jiegou.gd`、`linggan.gd`、`kanpo.gd`

1. 武将：`max_hp=3`、`faction="yinhexvezhe"`、`skills=[jiegou, linggan, kanpo]`。
2. 【解构】出牌阶段重铸一张非延时锦囊（`type=="trick" and subtype=="normal"`），重铸成功后若牌名未记录则调 `add_skill_recorded_card_name`。
3. 【灵感】出牌阶段限一次：四段连续选择（①选视为使用的牌名 → ②是否以另一张记录牌名结算 → ③选该牌名 → ④选目标），走 `request_control_selection` / `request_card_selection` + `continue_selection`；结算调 `execute_cardless_virtual_card_use`，目标模式经 `rule_overrides.target_mode_source_definition_id` 覆写；结算完毕 `remove_skill_recorded_card_name` 移除两张牌名。
4. 【看破】订阅 `useCardToTargeted`（`role="target"`）：记录中存在该牌名且本轮未用 → 移除记录 → `host.call("exclude_card_target", card_uid, owner_player_id)`；`roundStart`（`role="global"`）重置每轮限一次。
5. AI：解构近乎无脑重铸；灵感选收益最高牌名并把单体锦囊当群体用；看破除正向锦囊（五谷丰登/桃园结义）外无脑使用。

### U10 测试

| 测试文件 | 覆盖 |
|---|---|
| `tests/three_new_characters_test.gd`（新建） | 三武将数据库装配、8 技能元数据与描述文本逐字一致 |
| `tests/discard_batch_mechanics_test.gd`（新建） | U1 批次聚合、嵌套、单张 |
| `tests/skill_random_port_test.gd`（新建） | U2 可复现性与 `random_history` |
| `tests/intrinsic_skill_removal_test.gd`（新建） | U3 移除→复原→读档不复活 |
| `tests/card_name_record_test.gd`（新建） | U5 记录去重/移除/存档往返 |
| `tests/target_mode_override_test.gd`（新建） | U6 枚举与校验一致 |
| 既有回归 | `rule_timing_test`、`reincarnation_mechanics_test`、`new_character_mechanics_test`、`omphalos_transform_test`、`smoke_test`、`gameplay_regression_test`、`phase_progression_test` |

### U11 文档同步

| 文档 | 落点 |
|---|---|
| `docs/内容制作指南.md` | 技能表 `:2181`、势力/技能表 `:3178/:3214`、检查清单 `:3478-3539`、轮回章节 `:3794+`（新增时机与端口） |
| `docs/游戏机制与玩法内容.md` | `:580`、`:1040`、`:1064`、`:1134-1263`（三武将机制与全部具体数值） |
| `docs/AI模块.md` | `:180/:252/:335/:343`（8 技能的 AI 策略） |
| `docs/界面与交互.md` | 灵感多段选择与牌名记录展示 |
| `README.md` | `:58` 自动校验、`:92` 测试清单 |
| `.trellis/spec/` | 若有对应层规范，补充新端口与新时机 |

---

## 四、提交切分

**批 1（海瑟音）**
1. 新增弃置批次聚合端口与新时机
2. 新增海瑟音武将与【泛音】【回涛】
3. 新增弃置批次与海瑟音机制测试
4. 同步三武将相关文档

**批 2（那刻夏）**
1. 新增技能随机端口
2. 新增固有技能永久移除端口与状态字段
3. 扩展武将技能复原支持排除自身
4. 新增那刻夏武将与【逐虚】【揭质】【留白】
5. 新增对应机制测试并同步文档

**批 3（大黑塔）**
1. 新增技能牌名记录容器与端口
2. 新增虚拟牌目标模式覆写
3. 新增大黑塔武将与【解构】【灵感】【看破】
4. 新增对应机制测试并同步文档

---

## 五、完成判定（对齐 PRD AC）

- [ ] AC1 三武将可被选将、体力与势力正确
- [ ] AC2 八条技能描述与 R0 原文逐字一致（含全角引号与带圈序号）
- [ ] AC3 泛音四节齐备且黑/红批次判定先黑后红
- [ ] AC4 回涛仅在 `section_count >= 3` 的轮回推进时询问
- [ ] AC5 逐虚整技每出牌阶段两次、随机经权威端口且写 `random_history`
- [ ] AC6 揭质每局两次且能对相同目标复刻
- [ ] AC7 留白重置其他技能（含轮回进度）并在回合末永久失去全部技能
- [ ] AC8 解构只记录非延时锦囊且去重
- [ ] AC9 灵感四段选择可取消、结算后移除两张记录、无懈不可被选为目标模式
- [ ] AC10 看破每轮一次且不进入无懈链
- [ ] AC11 全部新增与既有回归测试通过，无 ERROR/SCRIPT ERROR
- [ ] AC12 四份文档 + README 数值可追溯
