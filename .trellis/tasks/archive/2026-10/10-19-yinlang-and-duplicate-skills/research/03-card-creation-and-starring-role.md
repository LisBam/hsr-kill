# 调研 03 · 运行时造牌与「主演」机制

调研范围：现有造牌/入堆/洗牌端口、「主演」机制的完整度、卡牌区域移动的唯一入口、随机数可复现约束。
结论：**主演机制完整可直接复用**；**造牌需新增 2 个端口 + 1 个名称解析入口**。

---

## 1. 卡牌区域移动的唯一权威入口

`scripts/core/card_movement_service.gd`（293 行）：

| 成员 | 行 |
|---|---|
| `move_card(card, target_zone, target_index, reason, event_id, position_token) -> bool` | `:25` |
| `move_cards(...)` | `:69` |
| `reveal_card(...)` | `:81` |
| `_add_to_zone(...)` | `:204` |
| `_parse_draw_pile_position(position_token)` | `:236` |
| `insert_new_card_into_draw_pile(card, position, reason, event_id) -> int` | `:247-272` |
| `_update_knowledge(...)` | `:276` |
| `_is_valid_zone(zone)` | `:292-293`（`draw_pile, hand, equipment, judgment, processing, wooden_ox, discard_pile, void`） |

**`MatchController` 与 `CardMovementService` 是唯一允许改 `GameState` 的地方**；技能、UI、AI 一律不得直接改写区域数组。

### 位置令牌约定

`place_hand_card_on_draw_pile_top(player_id, card_uid, position)`（`match_controller.gd:9300-9333`）演示了「指定摸牌堆位次」的权威做法：

```gdscript
card_movement.move_card(card, "draw_pile", -1, SECRET_PILE_PLACEMENT_REASON, state.current_event_id, "@%d" % position)
```

`@<n>` 由 `_parse_draw_pile_position` 解析。位次常量：`DRAW_PILE_POSITION_RANDOM = 0`、`DRAW_PILE_POSITION_TOP = 1`、`DRAW_PILE_POSITION_SECOND = 2`（`match_controller.gd` 常量区）。

### 既有造牌/入堆端口

| 端口 | 位置 | 说明 |
|---|---|---|
| `create_and_insert_card_into_draw_pile(definition_id, suit, rank, position) -> int` | `match_controller.gd:9195-9244` | 拒绝未登记 ID（`:9200`）；随机位次记账在 `state.random_history`，kind `"exclusive_card_insert"`（`:9221-9231`）；`EXCLUSIVE_CARD_INSERT_REASON = "exclusive_card_insert":237` |
| `gain_card_to_hand_by_uid(receiver_id, card_uid, reason, allow_out_of_game) -> bool` | `:7115` | **要求牌已存在于某个区域**；`:7126` 拒绝 `processing` 与 `hand→同一人` |
| `gain_draw_pile_card_by_uid(...)` | `:9120` | 摸牌堆按 UID 入手 |
| `gain_top_named_card_from_draw_or_discard(player_id, definition_id, reason, allow_out_of_game) -> CardInstance` | `:7552` | 反向扫描（数组末尾 = 堆顶） |
| `gain_top_draw_card_matching(player_id, filter, reason) -> CardInstance` | `:7713` | 过滤器键 `definition_id / definition_ids / effect_id / natures / type`，判定在 `_does_draw_card_match_filter:7737` |
| `gain_group_cards_from_draw_or_discard(player_id, group_kind, groups, count_each, reason, allow_out_of_game) -> int` | `:7583` | `group_kind ∈ {type, suit, rule_name, definition_id}`（`docs/内容制作指南.md:4041`） |
| `place_hand_card_on_draw_pile_top(player_id, card_uid, position)` | `:9300-9333` | 手牌 → 摸牌堆指定位次 |
| `_reshuffle_discard_pile()` | `:16634-16655` | ★**私有**，只支持整堆重洗；`:16654` 只 `_record_runtime_event("washCard", ...)`，**从不 `_emit_rule_timing`** → `washCard` 不可订阅 |
| `_shuffle_array(arr)` | `:16769` | 私有 |
| `pick_random_candidate_index(candidate_count, history_kind, history_data) -> int` | `:7301` | ★**唯一的权威随机下标入口**；回放/联机靠它保持一致 |

## 2. 必须新增的端口

| # | 端口 | 为什么现有机制不够 |
|---|---|---|
| **P1** | `CardMovementService.insert_new_card_into_zone(card, zone, index, reason, event_id, position_token)` | 现有「新牌直接进入指定区域」只有摸牌堆版本（`insert_new_card_into_draw_pile`）；`gain_card_to_hand_by_uid` 要求牌已在某区域，无法用于刚造出来的牌 |
| **P2** | `shuffle_discard_card_into_draw_pile(card_uid) -> bool` | 唯一的洗回实现 `_reshuffle_discard_pile()` 是**私有**且只支持整堆；单张指定牌洗回必须新写，并须把位次写入 `random_history` 以保证回放可复现 |
| **P3** | `is_card_name_available(card_name) -> bool` + `collect_existing_card_names() -> Array[String]` | `_card_definitions_by_display_name`（`game_database.gd:39`）是**私有**字段；`_find_card_by_display_name`（`:218-232`）也是私有。需要一个公开的唯一性查询，且必须覆盖**在局造牌**（见 `../10-19-yinlang-and-duplicate-skills/research/06-card-instance-name-plumbing.md` D6.8） |
| **P4** | `mint_card_for_player(player_id, source_definition_id, custom_name, suit, rank, minted_skill_id) -> int` | 造牌入口本身；须「先全部校验、再写入」 |
| **P5** | `get_discard_pile_card_uids_by_skill(skill_id) -> Array[int]` / `get_draw_pile_card_uids_by_skill(skill_id)` / `gain_top_minted_card_from_draw_or_discard(...)` | 「『以太』牌」的唯一可靠标识是**铸造来源**（`minted_skill_id`），不是牌名（牌名由玩家自由指定） |

## 3. 卡牌定义注册表（**不采用**运行时注册）

`scripts/autoload/game_database.gd`（624 行）：

- 目录常量：`CARDS_DIRECTORY:7`、`CHARACTERS_DIRECTORY:10`、`CHARACTER_IMAGE_DIRECTORY:13`、`SKILLS_DIRECTORY:19`、`DECKS_PATH:27`、`FACTIONS_PATH:30`。
- 容器：`cards:36`、`_card_definitions_by_display_name:39`（私有）、`card_definitions:45`、`card_scripts:48`、`skills:63`、`skill_scripts:66`。
- `reload_all():84-98` **清空全部容器** → 运行时写入的定义在重载后消失。
- `_load_cards():317-341` 填充 `cards[card_id]`、`_index_card_display_names(metadata)`、`card_definitions[card_id]`、`card_scripts[card_id]`。
- `create_card_runtime(id):123`；`get_card(id):113`；`get_card_definition(id):118`。
- `_list_gd_scripts():470-494` 强制文件名 `[a-z0-9_]+`（`:489-492`）。
- `_validate_characters():609-624` 遍历 `cards.keys()` 检查七个字段非空。

**为什么不采用运行时定义注册表（方案 A）**：

1. `CardInstance` 只序列化 `definition_id` → 读档/回放时定义已随 `reload_all()` 消失，退化为「未知牌」且效果静默失效；需要一整套并行持久化路径。
2. 污染 `all_cards_panel.gd:388`（图鉴全量枚举）与 `game_database.gd:600-608`（校验），并可能触发 `smoke_test.gd:145/152-156/397` 的断言。
3. `CardDefinition.new(meta)` 得到的是**基类**，其 `resolve()` 是空实现；要正确工作必须 `card_scripts[src].new()` 再覆写 `_metadata` —— 脆弱且违背单一职责。

**采用的方案（方案 B）**：造出的牌是 `CardInstance`，其 `definition_id` = **被复制牌的定义 ID** → `CardEffectResolver`、AI 画像、类型/子类/`effect_id`、响应模式、出牌次数限制**全部零改动继续工作**；牌名与来源由**每实例字段** `custom_display_name` / `minted_skill_id` 承载。

**推论（需写入文档）**：造牌副本在**规则身份**上等于被复制牌 —— 复制【杀】得到的牌仍计入【杀】的使用次数；复制【乐不思蜀】得到的牌与真实【乐不思蜀】在判定区**互斥**（`card_rule_service.gd:495-498` 按 `definition_id` 判同名）。「新牌名 = 新规则身份」是方案 A 才支持的扩展方向。

## 4. 「主演」机制：完整、可直接复用

`scripts/core/starring_role_service.gd`（108 行）：

| 成员 | 行 |
|---|---|
| `CORNER_ENTRY_ID = "zhuyan"` | `:10` |
| `CORNER_TEXT = "主演"` | `:13` |
| `CORNER_TEXT_ORDER = 50` | `:18` |
| `configure(host, state)` | `:28-29` |
| `get_starring_player_id() -> int` | `:35-48` |
| `is_starring(player_id) -> bool` | `:52-53` |
| `set_starring(player_id)` | `:62-77` |
| `clear_starring()` | `:84-93` |

- **至多一名主演**（`set_starring` 会先清旧）。
- 死亡/换将自动清理：`death_resolution_service.gd:132-134`、`:300-302`。
- 控制器端口：`match_controller.gd:17442 set_starring_role(player_id)`、`:17448 get_starring_role_player_id()`、`:17453 is_starring_role(player_id)`；服务实例 `:538 starring_role_service`。
- 使用先例：`game_data/skills/wansi.gd:113`。
- 角标与 `character_corner_text_entries`（`player_state.gd:73`）同源。

→ **注入的「若该角色为主演」判定与以太的「你成为主演」都可直接调用端口，无需新增任何机制。**

## 5. 随机数与回放可复现

- 所有随机下标必须走 `pick_random_candidate_index(candidate_count, history_kind, history_data)`（`match_controller.gd:7301`），它会把抽取结果写入 `state.random_history`。
- `create_and_insert_card_into_draw_pile` 的随机位次同样记账（`:9221-9231`）。
- **禁止直接 `randi()`** —— 否则回放与联机不同步。
- 真实用例：`haoxi.gd:98-106`（随机手牌下标 → 弃置）。

## 6. 玩家状态字段（造牌与临时状态相关）

`scripts/data/player_state.gd`（618 行，76 个字段）中与本任务相关的：

| 字段 | 行 | 说明 |
|---|---|---|
| `shield` | `:40` | 护盾，**进公开快照** |
| `chained` | `:58` | 横置（≠ 翻面） |
| `face_down` | `:61` | 翻面 |
| `non_locked_skills_disabled` | `:64` | 非锁定技失效（来源表 `:67`） |
| `character_corner_text_entries` | `:73` | 角标条目（主演在此） |
| `dynamic_skill_descriptions` | `:78` | 技能描述覆盖 |
| `slash_count` | `:125` | 【杀】次数（控制器每回合清零：`:8320`、`:12597`、`:12627`、`:14779`；回合收尾 `_complete_finish_turn:14867`） |
| `hand_limit_bonus` | `:193` | 手牌上限加成，**永久**，控制器**不在回合末清零** |
| `mode_hand_limit_bonus` | `:196` | 模式加成（`get_hand_limit()` 在 `:413`） |
| `temporary_skills` | `:143` | 临时技能 |
| `acquired_skills` | `:146` | 局内获得技能 |
| `recorded_card_names` | `:154` | 存 **definition_id** |
| `skill_used_card_names` | `:160` | 存 **definition_id** |
| `character_form_state` | `:25` | 形态状态（爻光【凶星】层数在此） |

**没有**通用回合域修正袋（无攻击范围加成、无距离修正、无「不可响应」标记）→ 见 `research/05` 的 N1–N4。

## 7. 卡牌实例（`scripts/data/card_instance.gd`，295 行）

| 成员 | 行 |
|---|---|
| `uid` | `:10` |
| `definition_id`（无约束 String） | `:13` |
| `suit` / `color_override` / `rank` | `:17` / `:22` / `:26` |
| `zone` / `owner_id` / `known_to` / `shown` / `private_owner_id` | `:29` / `:32` / `:35` / `:38` / `:41` |
| 手牌视为字段 | `:44-70` |
| `_init` | `:75` |
| `from_dict` | `:88-115`（★**逐键白名单**） |
| `get_color()` | `:120` |
| `set_hand_view_as()` / `clear_hand_view_as()` | `:137` / `:148` |
| `is_valid_suit()` / 点数 1–13 | `:193` / `:24-26` |
| `to_dict()` | `:257-295`（序列化 `definition_id` + 牌面/区域/表现字段，**无名称字段**） |

花色 ID：`"spade" | "heart" | "club" | "diamond"`（另有 `"none"`）。点数：1–13。

## 8. 测试先例

- 运行时定义注入：`tests/exclusive_card_and_private_placement_test.gd:351-364`（`GameDatabase.cards[id] = {...}` + `GameDatabase.card_definitions[id] = CardDefinition.new(...)`），清理在 `:395-396`。
- 造牌/私有放置相关既有测试：`tests/exclusive_card_and_private_placement_test.gd`、`tests/pre_game_deal_gain_test.gd`、`tests/card_timing_sequence_test.gd`、`tests/requested_changes_test.gd`。
- 主演断言先例：`tests/new_character_mechanics_test.gd`（含 `phaseZhunbei` 驱动 `:1501`）。
