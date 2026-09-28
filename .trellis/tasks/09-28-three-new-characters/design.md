# 技术设计：新增三名武将（海瑟音·那刻夏·大黑塔）

> 父任务技术设计。需求与验收以 `prd.md` 为准；实现细节由各子任务 `design.md` 承接。
> 本文件只规定**跨子任务的技术契约**：机制落点、分层边界、状态一致性、风险与回滚。

---

## 一、总体结论（先读这段）

调研后，原本预估的 9 项机制缺口**有 4 项已被现有代码覆盖**，实际新增范围显著缩小：

| 缺口 | 调研结论 | 落点 |
|---|---|---|
| M1 弃置批次聚合 | **缺**：`cardsDiscardAfter` 由 `_move_card_with_timings` 逐张派发 | 权威层新增批次端口 + 新时机 |
| M2 技能随机端口 | **缺**：随机只在 `MC._rng`，内容层无入口 | 权威层新增公开方法 |
| M3 永久移除固有技能 | **缺**：只有 `remove_acquired_skill` / `remove_temporary_skill` | 权威层新增端口 |
| M4 强化重置技能 | **基本已有**：`restore_character_card_skills` 已覆盖 D2 全部 5 项 | 只加 `exclude_skill_ids` 参数 |
| M5 牌名记录容器 | **缺**：`public_marks` 结构受限，私有 `character_form_state` 不进 LAN 快照 | `PlayerState` 新增公开字段 |
| M6 目标模式重定向 | **缺**：`rule_overrides` 无目标模式覆写 | `CardRuleService` 两处校验改造 |
| M7 禁止无懈可击 | **已天然满足**：`validate_virtual_use` 已拒绝 `target_mode=="response_only"` | 仅内容层过滤 + 回归测试 |
| M8 令此牌对你无效 | **已有**：`exclude_card_target`(`MC:7708`) 写 `excluded_target_ids`，`MC:11971` 派 `useCardToExcluded` 并跳过该目标 | 仅内容层调用 |
| M9 轮回推进订阅 | **已有**：`reincarnationStart` 等四个时机 | 仅订阅 |

**风险等级**：M3（永久移除，涉及四处安装点与状态一致性）> M6（跨 UI/AI/校验六处）> M1（新时机）> M5（新状态字段）> M2 > M4（参数扩展）> M7/M8/M9（内容层）。

---

## 二、分层落点

```text
game_data/skills/*.gd          ← 8 个技能：规则 + 配套 AI（内容自包含）
game_data/characters/*.gd      ← 3 个武将：仅 6 个静态字段 + 技能脚本数组
        ↓ 只经 host.call / resolver 端口
scripts/core/match_controller.gd        ← M1/M2/M3/M5/M8 的权威端口
scripts/core/card_rule_service.gd       ← M6 的目标模式覆写
scripts/core/card_effect_resolver.gd    ← M8 的跳过判定
scripts/core/rule_timing_catalog.gd     ← M1 新时机注册
scripts/data/player_state.gd            ← M3/M5 新字段与快照序列化
```

**铁律**：内容层不得出现牌名/技能 ID 白名单；所有新机制必须是通用能力，三名武将只是使用者。

---

## 三、机制技术契约

### M1 弃置批次聚合（供【泛音】）

**现状**：`scripts/core/match_controller.gd:13754` 的 `_move_card_with_timings()` 是**单张**移动（`"card_uids":[card.uid]`），并在 `:13845` 派发 `cardsDiscardAfter`；`move_id` 由 `card_movement_service.gd:49-50` 单调递增分配，**每张都不同**。全部批量弃置入口（`discard_card_from_hand:6226`、`discard_all_hand_cards:6251`、`discard_n_from_player:6299`、`discard_n_from_hand_equipment:6600`、`discard_selected_hand_equipment:7869`）都是「取 UID 副本 + 逐张循环」，**没有任何批次开始/结束标记**。因此「一次弃置动作弃置多张」会派发 N 次单张事件，无法表达原文的「这些牌中有黑色也有红色」。

> 不可复用的近似物：`draw_presentation_batch_*`（`MC:24/27`）只是摸牌的表现层信号；`_current_rule_parent_event_id()`（`MC:14654`）会随 `_record_runtime_event`（`MC:14751`）逐张漂移，不能当批次 ID。

**设计**：

1. `scripts/core/rule_timing_catalog.gd:54`（`CARD_MOVE_TIMINGS`）新增时机 `cardsDiscardedBatchAfter`，语义为「一次批量弃置动作的全部牌均已进入弃牌堆」。
2. `MatchController` 新增**批次栈**字段与内部端口：
   - `_discard_batch_stack: Array[Dictionary]` — 每层保存 `{batch_id, player_id, reason, card_uids}`；用栈而非单变量以正确处理嵌套（批次内弃牌触发技能再弃牌）。
   - `_begin_discard_batch(player_id, reason) -> int` / `_end_discard_batch()`，`batch_id` 由独立计数器单调分配。
   - `_move_to_discard()`（`MC:13727`）与 `_move_card_with_timings()`（`MC:13754`）的 `timing_data` 注入 `discard_batch_id`，使逐张时机也能关联批次。
   - `_end_discard_batch()` 在弹出该层后，若 `card_uids` 非空则派发 `cardsDiscardedBatchAfter`，载荷：`discard_batch_id`、`card_uids`（整批）、`source_player_id`、`reason`、`batch_size`。
3. 五个批量弃置入口在循环外层包裹 `_begin_discard_batch` / `_end_discard_batch`；**单张弃置路径同样包裹**，使批次语义统一（大小为 1 的批次照常派发）。
4. 嵌套规则：内层批次先结束、先派发；内层牌**不并入**外层批次（外层只统计自身直接弃置的牌）。
5. 【泛音】订阅 `cardsDiscardedBatchAfter`（`role="player"`、`locked_segment=true`），在该批次内判定黑/红并**先黑后红**执行。

**兼容性**：新增时机不影响既有订阅方；批次端口不改变任何既有移牌行为与日志。
**测试影响**：`rule_timing_catalog.gd` 的改动会命中 `tests/rule_timing_test.gd` 的时机目录断言，必须同步更新。

**验收锚点**：一次调用弃置「黑桃+红桃」两张时，必须只产生一次批次事件，且黑色效果（令一名角色弃手牌）完成后才执行红色效果（摸一张牌）。

### M2 技能随机端口（供【逐虚】）

**现状**：唯一随机源 `scripts/core/match_controller.gd:395` 的 `_rng`，随 `random_seed` / `rng_state` 存档与恢复；LAN 快照移除 `random_seed`。内容层无任何随机入口。

**现状补充**：内容层目前**零随机调用**（`game_data/` 下无 `rand`/`_rng` 命中）；唯一公开随机端口是 `get_random_zone_card_uids_for_each_player`（`MC:6489`），它在 `MC:6513` 写入 `state.random_history` —— 这是必须照抄的范式。host 转发是**直接 `Object.call`，无白名单**（`skill_definition.gd:113-122`）。

**设计**：`MatchController` 新增公开方法（置于 `_shuffle_array`（`MC:14067`）一带，内容层经 `host.call` 调用）：

| 方法 | 语义 |
|---|---|
| `pick_random_index(candidate_count: int) -> int` | 从 `[0, n)` 等概率取索引；`n<=0` 返回 `-1` |
| `pick_random_element(candidates: Array) -> Variant` | 从候选等概率取 1 个；空数组返回 `null` |

**铁律**：
- 内部只用 `_rng`，禁止 `new RandomNumberGenerator` 或裸 `randi()`。
- **每次调用必须写 `state.random_history`**（形如 `{"kind":"skill_random", "skill_id":..., "index":i}`），否则回放/读档与联机表现会分叉。
- 候选顺序由调用方保证稳定（内容层按稳定玩家 ID / 牌 UID 升序枚举），否则同种子不可复现。
- LAN 客户端不运行技能逻辑（远端只取 `local_legal_actions`），因此随机**只在权威端**发生。

### M3 永久移除固有技能（供【留白】）

**现状**：`scripts/core/match_controller.gd:8720-8726` 是卸载唯一边界（`skill.uninstall()` → `eraser`）。`remove_acquired_skill:8707` / `remove_temporary_skill:8754` 都明确拒绝固有技能。

**设计**：

1. `MatchController` 新增：
   - `remove_intrinsic_skill(player_id, skill_id, reason="") -> bool`
     实现：`skill.uninstall()` → 从 `skill_instances_by_player[player_id]` 擦除 → 同步清除 `player.acquired_skills` / `player.temporary_skills` 中的同名记录 → 调用 `clear_reincarnation_skill_state(player_id, skill_id)` 清除轮回登记 → 写入 `player.lost_skill_ids` → 派发 `changeSkillsAfter`（`change_type="remove_intrinsic_skill"`）→ `_emit_state()`。
   - `remove_all_intrinsic_skills(player_id, reason="") -> int` — 遍历该玩家当前武将固有技能 ID 逐个移除，返回移除数量。
2. `scripts/data/player_state.gd` 新增 `lost_intrinsic_skill_ids: Array[String]`（本局永久失去的固有技能，按失去顺序）。
   - **必须在四处安装点统一过滤**：`_install_all_character_skills`（`MC:9208` 循环内）、`_reinstall_character_skills_for_player`（`MC:9254`）、`restore_character_card_skills`（`MC:4293`）、`_replace_native_character_skills`（`MC:4236`）。**尤其重要**：`resume_conquest_match` 会经 `MC:13562` 无脑重装武将全部固有技能，不过滤则读档即复活。
   - 同步：`PS` 声明区、`from_authoritative_dict`、`to_dict`（**公开**，UI 需要不显示这些技能）、`_build_conquest_save_data`（`MC:13296`）、LAN 裁剪。
   - UI 下发：`_append_limited_skill_usage_to_snapshot`（`MC:14959`）加入该字段，供 UI 隐藏按钮。
3. `has_lost_intrinsic_skill(player_id, skill_id) -> bool` 供内容层与测试查询。

**风险**：技能实例被移除后，其持有的时机订阅、持续标记、纯查询修正器必须由 `uninstall()` 完整清理（`skill_definition.gd:355-361` 自动解绑 event_bus / trigger_manager / modifier_pipeline）；**技能自建信号与 UI 条目必须自行覆写 `uninstall()` 清理**（范例 `anke.gd:52-55`）。

**验收锚点**：移除后技能按钮消失、悬停资料不再列出、轮回状态查询返回空、且再次调用复原端口不会重建。

### M4 强化重置（供【留白】）

**现状**：`restore_character_card_skills(player_id, reason="")`（`MC:4282`）已经完成 D2 要求的全部 5 项：卸载旧实例 → `GameDatabase.create_skill()` 新建实例（复位脚本私有 `_used_this_play_phase` / `_used_this_round` 等）→ `reincarnation_skill_service.reset_skill(player_id, id, true, false)`（复位轮回数与轮回节并解除永劫）→ 恢复限定与觉醒固有额度（`_intrinsic_used_count` 随实例归零）。

**设计**：只做一处向后兼容的参数扩展：

```gdscript
func restore_character_card_skills(player_id: int, reason: String = "", exclude_skill_ids: Array[String] = []) -> bool
```

在遍历固有技能 ID 时跳过 `exclude_skill_ids`。【留白】调用时传入 `[留白自身技能 ID]`，以满足原文「重置所有**其他**技能」。

**为什么不采用「新增 `reset_skill_state()` 钩子 + `reset_player_skills()` 遍历」方案**：

- 那刻夏的【揭质】是「每局游戏限两次」，而 `limited` 只是 `bool`（额度硬编码 0/1，`SD:34/212/217-219`），项目**没有**「每局限 N 次（N>1）」先例，必须自建私有计数器。钩子方案要求**每一个**技能自行实现并维护「需要清空的私有字段清单」，一旦遗漏就是静默的错误行为；**重建实例天然复位全部私有状态**，不需要逐技能维护清单。
- 重建实例正是项目既有「复原武将牌上的技能」的实现方式（`docs/内容制作指南.md:3877`），语义一致、已被测试覆盖。
- 【留白】目标只是那刻夏自身技能（逐虚 / 揭质），不存在需要保留实例身份的持续效果类技能，重建的副作用可控。

**注意**：既有调用方不传第三参，行为完全不变；`restore_limited_skill_use` 与 `reset_reincarnation` 保持原语义不动。`restore_character_card_skills` **只重建武将固有技能**，模式技能、临时技能与局内获得技能不受影响（与指南 `:3877` 一致）。

### M5 牌名记录容器（供【解构】【灵感】【看破】）

**现状**：`public_marks`（`PS:76`）是结构化标记字典（`icon/name/description/count/source_player_id/order`），适合承载「数量」而非「有序字符串列表」；`character_form_state`（`PS:25`）纯私有、LAN 快照固定为空，无法满足「对手与 AI 都要读到记录」。

**设计**：`scripts/data/player_state.gd` 新增公开字段：

```gdscript
## 技能记录的牌名列表；键为技能稳定ID，值为按记录顺序排列的卡牌定义稳定ID数组，全部观察者可见。
var skill_recorded_card_names: Dictionary = {}
```

**权威端口（`MatchController`）**：

| 方法 | 语义 |
|---|---|
| `get_skill_recorded_card_names(player_id, skill_id) -> Array[String]` | 返回记录副本（按记录顺序） |
| `add_skill_recorded_card_name(player_id, skill_id, card_definition_id) -> bool` | 已存在则返回 `false`（去重）；成功追加并 `_emit_state()` |
| `remove_skill_recorded_card_name(player_id, skill_id, card_definition_id) -> bool` | 移除单项；不存在返回 `false` |

**同步清单（缺一不可）**：`PS` 字段声明（`:76` `public_marks` 旁）+ `from_authoritative_dict`（`:303` 旁）+ `to_dict`（`:515` 旁，公开分支）+ `_build_conquest_save_data`（`MC:13296` 显式补字段）+ LAN 快照裁剪（`MC:15000` 一带，仅当字段私有才需 erase）。读档经 `MC:13538 from_authoritative_dict` 自动生效。项目 `PlayerState` **没有**自定义 `duplicate()`/`_copy_*`，副本唯一来源就是这两个序列化函数。

**为什么不用 `public_marks`**：三处硬约束——① `change_player_mark_count` 把 `count` 夹到 `0..PlayerMarkService.MAX_MARK_COUNT`（`MC:8537`），牌名列表会触顶；② mark 的 `globally_unique` 按 `mark_id` 全场唯一，与「一名角色一串有序牌名」语义不符；③ mark 的 UI 契约是 `icon/name/description/count` 单条目角标，塞长列表会破坏渲染。

**语义**：记录以**卡牌定义稳定 ID** 为键（对抗「卡牌名称模式」切换导致的显示名变化），展示时经 `GameSettings.resolve_card_name()` 解析。

### M6 目标模式重定向（供【灵感】）

**现状**：`scripts/core/card_rule_service.gd:138` `validate_virtual_use()` 与 `:184` `list_legal_virtual_targets()` 都从 `GameDatabase.get_card(definition_id)` 读取 `target_mode` / `min_targets` / `max_targets`（`:164-169`）。`rule_overrides` 现有键：`allow_out_of_game_actor`、`ignore_phase_limit`、`ignore_play_count_limit`、`maximum_target_count_bonus`、`card_color` 等。

**设计**：新增覆写键 `target_mode_source_definition_id`（String），**落点共 6 处，缺一处就会出现「能选但提交被拒」或「预览不亮」**：

| # | 落点 | 改动 |
|---|---|---|
| 1 | `card_rule_service.gd:322`（`_validate_target`） | 目标模式改读来源牌 |
| 2 | `card_rule_service.gd:242`（`normalize_targets`）与 `:222`（`list_legal_targets`） | 同法；**这两处目前不接收 overrides，需加可选形参 `rule_overrides: Dictionary = {}`**，并同步 `MC:2111 / 11448 / 11473` 传参 |
| 3 | `card_rule_service.gd:167` | 目标数量上限支持来源牌 `max_targets` |
| 4 | `MC:2098`（`get_legal_actions` 的 AI 枚举） | 读取覆写键 |
| 5 | `MC:14374`（`_get_remote_card_use_preview`，LAN 预览）与 `match_table.gd:2550-2565`（本地预览/自动锁定自身） | 读取覆写键 |
| 6 | `noname_ai_evaluator.gd:1171` | 目标估值读取覆写键 |

**语义**：覆写键只替换**目标模式与目标数量上下限**，效果仍由 `definition_id` 决定。

**语义示例**：`definition_id="nanman"` + `target_mode_source_definition_id="tiesuo"` → 效果为南蛮入侵，目标为自选 1–2 名角色。

### M7 禁止无懈可击（供【灵感】）

**结论：无需新增核心机制。** `card_rule_service.gd:152-153` 已对 `target_mode == "response_only"` 的虚拟牌直接拒绝（无懈可击正是该模式）。因此：

1. 【解构】只允许重铸**非延时锦囊**（`type=="trick"` 且排除 `subtype=="counter"` 与延时子类型），无懈可击永远进不了记录。
2. 【灵感】的两段牌名选择都从记录中取，并**显式过滤**无懈可击（防御性双保险）。
3. 回归测试必须断言：以无懈可击 id 调用虚拟牌路径会被拒绝。

### M8 令此牌对你无效（供【看破】）

**现状**：`is_card_target_direct_hit`（`MC:12201`）读取 `_card_use_contexts[card_uid]["direct_hit_target_ids"]`，语义是**该目标本人不能响应**（`MC:5766` 把它用于无懈名单排除），**不是**「跳过该目标的结算」。真正的跳过判定在 `scripts/core/card_effect_resolver.gd:92` `should_skip_trick_target()`，它调用 `host.resolve_trick_negation(...)`。

**设计**：

1. `MatchController` 新增与 direct_hit 同构的独立集合：
   - `add_card_negated_target(card_uid, target_id, reason="") -> bool`
   - `is_card_target_negated(card_uid, target_id) -> bool`
   - 存储位置：`_card_use_contexts[card_uid]["negated_target_ids"]`；随既有 `_card_use_contexts` 生命周期释放，并纳入存档/回放已序列化的上下文字段清单。
2. `CardEffectResolver.should_skip_trick_target()` 增加前置检查：`host.is_card_target_negated(card.uid, target_id)` 为真则返回 `true`。该函数被全部普通锦囊共用（12 处调用点），因此改造一次即通用。
3. 【看破】订阅 `useCardToBegin`（`role="target"`，即自己成为目标时）：校验记录中存在该牌名且本轮未用 → 移除记录 → `add_card_negated_target`。

**与无懈可击的区别**：看破不进入无懈询问链，不消耗无懈可击、不影响其他目标。

### M9 轮回推进订阅（供【回涛】）

**现有能力**：`scripts/core/rule_timing_catalog.gd:79-81` 定义 `reincarnationStart` / `reincarnationEnd` / `reincarnationSectionStart` / `reincarnationSectionEnd`；轮回数 `+1` 后由 `ReincarnationSkillService` 派发新轮回开始。

**设计**：【回涛】`install()` 订阅 `reincarnationStart`，**`role="global"`** —— 必须是 global，因为海瑟音需要观察**任意角色**的轮回技推进（`role="player"` 只会匹配持有者自己）。回调中把 `event.player_id` 当作「该轮回技的持有者」。

**判定载荷**（`RSS:357-364`）：`skill_id / round_count / section_index(0基) / section_number(1基) / section_count / eternal`。

- 「进入下一个轮回」= 在 `reincarnationStart` 回调里读 `round_count >= 2`。**注意派发顺序**：`enter_next_round`（`RSS:179-185`）先派 `reincarnationEnd` **再** `round_count += 1`，因此 End 看到旧值、Start 看到新值。
- 「轮回节数不小于 3」**必须读 `section_count`**，不得读 `reincarnation_has_explicit_sections`（后者只是「描述里是否写了①②③」的布尔，无显式序号的轮回技 `section_count` 同样可为 3，会导致误判）。

**门槛常量**：`MIN_SECTION_COUNT_FOR_HUITAO = 3`，提取为技能顶部常量并注释来源（原文「不小于3」）。

**先例**：全项目**没有任何技能订阅过这四个时机**（`grep 'subscribe_timing("reincarnation'` 零命中）。最接近的写法是 `pofeng.gd:31`（`subscribe_timing("roundStart", cb, "global")`）。

---

## 四、跨子任务一致性契约

| 主题 | 契约 |
|---|---|
| 次数额度 | 同一技能对象内多套额度必须分别记账：轮回额度过 `can_activate_reincarnation()`；「出牌阶段限 N 次」「每回合/每轮限 N 次」用技能私有 `var` + Begin 时机重置（参照 `kance.gd:37-44`、`huanfa.gd:37`） |
| **`limited` 的真实语义** | `limited` 是 **bool**，额度硬编码 0/1（`SD:34/212/217-219`）。**「每局游戏限两次」（揭质）无法用 `limited` 表达**，必须自建私有计数器并在 `can_activate` 判上限；项目无 `N>1` 的每局限次先例 |
| 私有状态 | 技能私有 `var` **不序列化**；需跨帧/跨存档/联机可见的数据一律落权威状态字段 |
| **AI 钩子禁用 host** | `append_play_phase_actions` / `score_ai_action` / `score_ai_choice` / `modify_*` 内 **`host` 恒为 null**（`docs/内容制作指南.md:1873-1877`），只能读 `authoritative_snapshot` + `evaluator`。因此**随机端口只在权威执行期调用**，AI 侧的【逐虚】动作必须是无参数动作（随机对象由权威端在执行时决定），评分用期望值 |
| 描述文本 | 8 条描述与 `prd.md` R0 逐字一致；引号统一使用**全角弯引号 U+201C/U+201D**（与项目现有技能描述一致）；带圈序号用 **U+2460 起**（①–⑩，`skill_description_view.gd:7`）——泛音需要 ④（U+2463），项目此前最多只用到 ③ |
| 空节推进 | 轮回技任何一节「客观上无可执行内容」时，`can_activate()` 不得返回 `false`（`docs/内容制作指南.md:3881-3896`）；费用类不可执行沿用 `kansha.gd` 既有先例 |
| 复原兼容 | 拥有额外私有已用标记的技能必须覆写 `restore_limited_use()`，先调基类再清私有字段（`docs/内容制作指南.md:3875`） |
| 技能卸载 | 新增持续状态/订阅的技能必须实现 `uninstall()` 对称清理（参照 `yongjie.gd:65`、`anke.gd:52-55`） |
| 多段选择 | 每段独立 `kind`，`continue_selection` 用 `if/if` 分派并统一 `return true`；取消分支**不结算不推进**；跨段只传稳定 ID；选项 `id` 用英文常量、`label` 用中文（`kance.gd:86-95`） |
| 选项显示 | 内联按钮最小宽 146（label 建议 ≤8 字）；弹窗选项固定 280×44 会省略号截断，长文本靠 `tooltip_text` 兜底（`match_table.gd:3695-3700`、`card_selection_panel.gd:622-627`） |

---

## 五、验证策略

- **测试**：每个子任务新增/扩展一个 `tests/*.tscn`；优先复用 `tests/reincarnation_mechanics_test.gd` 的骨架。
- **命令**：`& 'E:\Godot\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe' --headless --path . --scene res://tests/<name>.tscn`
- **判定**：退出码 `0` 且输出含该测试的 PASS 标记、无 `ERROR` / `SCRIPT ERROR` / `FAIL` / 资源告警；测试逐进程串行执行。
- **必要回归**：`smoke_test`（数据库校验）、`reincarnation_mechanics_test`、`new_character_mechanics_test`、`gameplay_regression_test`（无懈与逐目标时序）、`phase_progression_test`。
- **文档**：按 `prd.md` R4 的四份文档 + README 同步，数值必须可追溯。

---

## 六、风险与回滚

| 风险 | 触发条件 | 缓解 / 回滚 |
|---|---|---|
| M3 移除技能后残留订阅 | `uninstall()` 未覆盖某条路径 | 单技能粒度提交；出问题只回滚该端口与其调用方 |
| M6 三处不一致 | 只改了校验没改枚举 | 验收测试必须同时断言「枚举可点」与「提交通过」 |
| M1 批次栈在异常路径未弹出 | 弃置过程中抛错/提前 return | 端口用「先压栈、后保证弹出」结构；测试覆盖技能嵌套弃置 |
| M5 新字段漏同步 | 存档/读档或 LAN 裁剪遗漏 | 按同步清单逐项核对；LAN 重连测试 |
| 泛音轮回卡在费用节 | 长期摸不到对应花色 | 沿用 `kansha.gd` 既有先例；交付时向用户说明该设计取向 |

**分批交付与回滚点**：海瑟音 → 那刻夏 → 大黑塔，每批独立提交，可单独 revert。
