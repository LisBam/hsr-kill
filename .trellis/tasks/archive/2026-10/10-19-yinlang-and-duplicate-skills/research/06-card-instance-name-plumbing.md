# 调研 06 · 卡牌实例级牌名覆盖的实施清单

调研范围：为 `CardInstance` 新增 `custom_display_name` / `minted_skill_id` 两个字段时，必须改动哪些文件、存档/回放/网络是否自动继承、以及自定义牌名会不会破坏既有规则。
只读调研，全部带文件与行号。

**判定：SAFE TO ADD PER-INSTANCE NAME OVERRIDE（无硬阻塞）。**

三个必须注意的技术点（不是阻塞，是必改项）：

1. `card_instance.gd:88 from_dict()` 是**逐键白名单式读取** → **必须同时**改 `to_dict()` 与 `from_dict()`，否则存档/网络/回放往返全部丢字段。
2. `card_view.gd:294` 是**牌面名称的唯一渲染点** → 不改它则手牌/装备/判定/弃牌/图鉴全都不显示自定义名。
3. `information_box_layer.gd:519` 会对信息框 title **再做一次** `resolve_card_names_in_text` → 自定义名若撞上已登记双名会被**改写**，因此查重必须用双名索引口径。

---

## 1. 名称解析调用点

### 1.1 有实例字典可用（可读覆写）—— 这些是必改点

| file:line | 表达式 | 说明 |
|---|---|---|
| `scripts/ui/card_view.gd:294` | `GameSettings.resolve_card_display_name(visual_definition)` | ★**牌面主名称唯一渲染点**；`card` 字典就是 `configure()` 的入参（`:237`） |
| `scripts/ui/card_view.gd:275` | `_view_as_display_name_text = GameSettings.resolve_card_display_name(view_as_definition)` | 视为横条 |
| `scripts/ui/card_view.gd:662` | `"title":"【%s】" % _display_name_text` | 悬停信息框标题（随 `:294` 自动生效） |
| `scripts/ui/equipment_stack_view.gd:198` / `:297` | `resolve_card_display_name(card_definition)` / `"title":"【%s】" % equipment_name` | `equipment_card` 字典在手（`:192`） |
| `scripts/ui/player_target_view.gd:1459` / `:1504` / `:1349` | 装备/判定/装备摘要名 | 字典在手 |
| `scripts/ui/player_target_view.gd:1142` / `:1610` / `:1616` | 判定区/装备/判定标记名 | 字典在手 |
| `scripts/ui/match_table.gd:3112` / `:3126` | 装备槽名 / 本地判定区名 | `card` 字典在手（`:3111`/`:3125`） |
| `scripts/ui/match_table.gd:3541` / `:5912` | 装备材料提示 / 装备操作条文本 | `_get_active_equipment_definition()` 需同时拿到实例字典 |
| `scripts/ui/developer_console_panel.gd:732` / `:763` | 开发者菜单卡牌文本 | `card_data` 字典在手 |
| `scripts/core/match_controller.gd:4367` | `format_card_log_name(card: CardInstance)` → `:4373` | ★**日志唯一入口**，有 `CardInstance` |
| `scripts/core/match_controller.gd:4464` | `describe_card(card: CardInstance)` → `:4473` | 有实例 |
| `scripts/core/match_controller.gd:14635` | 重铸日志 `resolve_card_name(definition)` | `card` 实例在手（`:14625`）但未使用 |
| `scripts/core/match_controller.gd:5382` | 装备响应 `result["response_title"]` | `equipment_card` 实例在手（`:5375`） |

**自动生效、无需改**（`CardView.configure` 已收到 card 字典，且 `:241` 用整字典 hash 做刷新判据）：`match_table.gd:2601/4788/4901/5212`（手牌/飞牌/摸牌）、`card_selection_panel.gd:768`（候选牌）。

### 1.2 只有 definition_id（无法读覆写）—— 保持定义名

`match_controller.gd:4429 format_card_definition_log_name()`、`:5515`（无材料技能响应）、`:5889`（转化响应）、`:10924`（防具发动提示）、`:11123`/`:11142`（记录/移除牌名日志，**按定义正确**）、`:15221`（濒死救援选项名）、`card_effect_resolver.gd:62`、`card_definition.gd:415`、`skill_definition.gd:1091`、`skills/linggan.gd:293`、`skills/zimo.gd:244`。

### 1.3 `format_card_log_name` 原文（`match_controller.gd:4366-4380`）

```gdscript
func format_card_log_name(card: CardInstance) -> String:
	if card == null:
		return "【未知牌】"
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	var card_name_text: String = "【%s】" % GameSettings.resolve_card_name(definition)
	var rank_text: String = "" if card.rank <= 0 else str({1:"A", 11:"J", 12:"Q", 13:"K"}.get(card.rank, str(card.rank)))
	var suit_text: String = {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}.get(card.suit, "")
	if suit_text.is_empty() and rank_text.is_empty():
		return card_name_text
	return "%s%s%s" % [suit_text, rank_text, card_name_text]
```

其余命名卡牌实例的 `add_log`：`:4425`（`format_gained_card_log_name`）、`:5779`（`_build_card_action_log`）、`:6751`（装备）、`:13988`/`:13990`（使用）、`:16402`（弃置）—— 全部经 `format_card_log_name`，**改一处即全覆盖**。

---

## 2. 序列化 / 存档 / 回放 / 网络

### 2.1 `to_dict()`（`scripts/data/card_instance.gd:256-295`）

返回字典键：`uid, definition_id, original_definition_id, suit, rank, color, color_override, zone, owner_id, known_to, shown, private_owner_id, hand_view_as_source_skill_id, hand_mark_tags, presentation_original_definition_id, view_as_definition_id, presentation_original_suit, presentation_original_rank, view_as_suit, view_as_rank`。

### 2.2 `from_dict()`（`scripts/data/card_instance.gd:88-115`）

```gdscript
static func from_dict(data: Dictionary) -> CardInstance:
	var card: CardInstance = CardInstance.new(str(data.get("definition_id", "")), str(data.get("suit", "spade")), int(data.get("rank", 1)), int(data.get("uid", -1)))
	card.zone = str(data.get("zone", "draw_pile"))
	card.owner_id = int(data.get("owner_id", -1))
	card.color_override = str(data.get("color_override", ""))
	card.known_to.clear()
	for player_id_variant: Variant in data.get("known_to", []) as Array:
		var player_id: int = int(player_id_variant)
		if not card.known_to.has(player_id):
			card.known_to.append(player_id)
	card.shown = bool(data.get("shown", false))
	card.private_owner_id = int(data.get("private_owner_id", -1))
	card.hand_view_as_original_definition_id = str(data.get("original_definition_id", ""))
	card.hand_view_as_source_skill_id = str(data.get("hand_view_as_source_skill_id", ""))
	card.hand_mark_tags = (data.get("hand_mark_tags", {}) as Dictionary).duplicate(true)
	card.last_hand_view_as_original_definition_id = str(data.get("presentation_original_definition_id", ""))
	card.last_hand_view_as_definition_id = str(data.get("view_as_definition_id", ""))
	card.hand_view_as_original_suit = str(data.get("presentation_original_suit", ""))
	card.hand_view_as_original_rank = int(data.get("presentation_original_rank", 0))
	card.last_hand_view_as_suit = str(data.get("view_as_suit", ""))
	card.last_hand_view_as_rank = int(data.get("view_as_rank", 0))
	return card
```

⚠️ **逐键白名单**：未显式 `data.get()` 的键会被丢弃。因此 `to_dict` 与 `from_dict` **必须成对修改**。

### 2.3 权威存档

- **写入**：`match_controller.gd:15838 _build_conquest_save_data(...)`
  - 玩家区域：`:15843` `player.to_dict(player.player_id, true)` → `player_state.gd:500 to_dict()` 内 `:508`（装备 `card.to_dict()`）、`:514`（手牌）、`:519`（判定区）、`:525`（木牛流马）
  - 公共区域：`:15856-15862`（`draw_pile` / `discard_pile` 逐张 `card.to_dict()`）
  - 落盘：`match_table.gd:3992 ConquestSaveStore.write_save(save_data)` → `conquest_save_store.gd:54 file.store_string(var_to_str(save_data))`（Godot 文本序列化，**保留全部字典键**）
- **读取**：`match_controller.gd:16042 resume_conquest_match(save_data)`
  - `:16100 PlayerState.from_authoritative_dict(...)` → `player_state.gd:313`，内部 `:359/363/365/367` 逐区 `CardInstance.from_dict(...)`
  - `:16108-16111` 摸牌堆/弃牌堆逐张 `CardInstance.from_dict(...)`
- **全项目只有 3 处手写卡牌字典**：`card_instance.gd:274`（权威）、`match_controller.gd:6881`（隐藏候选，无名称，无需改）、`match_controller.gd:17326`（网络裁剪隐藏牌，无需改）。
- `converted_card_presentation.gd:41-51` 复用 `CardInstance.to_dict()` → 自动继承新字段。

✅ **改 `to_dict` + `from_dict` 即覆盖存档往返。`ConquestSaveStore.SAVE_FORMAT_VERSION` 不需要 bump**（`var_to_str` 无损；`from_dict` 全部有默认值，旧档缺键 → 空字符串，向后兼容）。

### 2.4 回放

`scripts/core/match_replay_recorder.gd` 三类步骤：
- `STEP_KIND_SNAPSHOT "s"`：`record_snapshot(snapshot)` 深拷贝**完整观察者快照**（`:113-121`）→ 快照由 `state.to_dict()` 生成，含 `card.to_dict()` → **新字段自动保留**
- `STEP_KIND_LOG "l"`：纯字符串（`:125-132`）→ 日志文本已固化
- `STEP_KIND_PRESENTATION "p"`：`match_controller.gd:17414 _emit_card_presentation(card.to_dict(), ...)` → `card_presentation_event.gd:39` 深拷贝 → 保留

回放播放 `match_replay_playback_driver.gd:121-122` 原样 emit `step.get("d")`。**自定义名可完整存活回放**（前提：UI 从 card 字典读名字）。

### 2.5 网络

- `network_gateway.gd` 对 payload 只做 `duplicate(true)` 透传（`:951/973/1202/1257/1280/1288`），**无字段白名单**。
- 快照：`match_controller.gd:18097`（本地）、`:18117`/`:18146`（远端/代管）→ `player_state.gd:500 to_dict()` → `card.to_dict()` → 自动保留。
- 选择候选：`match_controller.gd:6879 _serialize_choice_candidate()` → `:6881` `card.to_dict() if visible else {...}` → 可见分支自动保留。
- 两个隐私裁剪点只 `erase` 不重建（`:17299-17300`、`:17329-17330`）→ 新字段存活。

---

## 3. 牌名唯一性

### 3.1 双名索引

`game_database.gd:235-244`：

```gdscript
func _index_card_display_names(card_definition: Dictionary) -> void:
	var original_name: String = str(card_definition.get("original_name", "")).strip_edges()
	var custom_name: String = str(card_definition.get("custom_name", "")).strip_edges()
	for display_name: String in [original_name, custom_name]:
		if display_name.is_empty() or _card_definitions_by_display_name.has(display_name):
			continue
		_card_definitions_by_display_name[display_name] = card_definition
```

`_find_card_by_display_name`（`:218-232`）按双名精确查找。

**没有公开查重 API**。最省且**口径最正确**的做法是复用 `GameDatabase._card_definitions_by_display_name.has(name)`（它正是 `resolve_card_names_in_text` 的匹配口径）；等价替代是遍历 `GameDatabase.cards.values()` 检查 `original_name`/`custom_name`。

### 3.2 枚举全部卡牌 ID 的先例

唯一一处：`game_data/skills/zimo.gd:266`

```gdscript
var all_card_ids: Array = GameDatabase.cards.keys()
all_card_ids.sort()
for card_id_variant: Variant in all_card_ids:
	...
```

### 3.3 以「牌名」为键的结构

| file:line | 内容 | 影响 |
|---|---|---|
| `player_state.gd:154` | `recorded_card_names: Array[String]` | 存 **definition_id** → 安全 |
| `player_state.gd:160` | `skill_used_card_names: Dictionary` | 存 definition_id → 安全 |
| `match_controller.gd:11112/11131/11149` | `record_card_name` / `remove_recorded_card_name` / `get_recorded_card_names` | 按 definition_id → 安全 |
| `match_controller.gd:11168-11207` | `get_skill_used_card_names` 系列 | 按 definition_id → 安全 |
| `game_database.gd:176-215` | `resolve_card_names_in_text` | ★**按【】内文本查双名索引** → 自定义名撞名会被改写 |
| `match_controller.gd:7792-7801` | `get_card_original_name_length` | 读定义 `rule_name`/`custom_name`，**不读实例** → 自定义名不参与名字数结算（需产品决策） |
| `match_controller.gd:7593/7623` | `_find_top_group_card` 的 `rule_name` 分组 | 按定义 → 安全 |
| `match_controller.gd:15221` | 濒死救援选项名 | 按定义 → 安全 |
| `match_controller.gd:13427` | 延时锦囊名 | 按定义 → 安全 |
| `ui/match_table.gd:4188-4197` | 记录牌名窗口占位牌 | 无实例 → 显示定义名（合理） |
| `ui/card_gallery_sort.gd:125` | 图鉴排序 `rule_name` | 按定义 → 安全 |

---

## 4. 按牌名 / definition_id 的规则判定

### 4.1 全部按 `definition_id` / 配置分组，**没有一处按显示名**

| 类别 | file:line | 表达式 |
|---|---|---|
| 出牌次数分组 | `card_rule_service.gd:507` | `play_limit_group = str(definition.get("play_limit_group", definition.get("id","")))` |
| 同组计数 | `card_rule_service.gd:520-521`、`555-556` | `used_group == play_limit_group` |
| 【杀】次数 | `match_controller.gd:10008`、`10023`、`15268` | `play_limit_group == "slash"` |
| 无懈可击 | `wuxiekeji.gd:21,27` | `response_pattern` / `provided_response_pattern` |
| 无懈流程 | `match_controller.gd:5914/5960/6008/6012/6073/6080/6203` | `_consume_response_card_uid(..., "wuxie")` |
| 响应模式 | `starting_hand_mulligan_service.gd:155/157/159` | `provided_response_pattern == "shan"/"tao"/"jiu"` |
| ★延时锦囊同名 | `card_rule_service.gd:495-498` | `if delayed_card.definition_id == str(definition.get("id","")): return "目标判定区已有同名延时锦囊。"` ← **按 ID 判同名** |
| 效果分发 | `conquest_mode_service.gd:561` | `effect_id == "grant_skill"` |
| AI 白名单 | `noname_ai_evaluator.gd:241/256/264/757` | `definition_id != ...` |
| 玩家标记 | `player_mark_service.gd:100` | `card_group = play_limit_group` |
| 目标合法性 | `card_rule_service.gd:478/480` | `distance_limit` 配置 |

### 4.2 `resolve_card_names_in_text`（`game_database.gd:176-215`）—— 唯一的名称驱动行为

```gdscript
var referenced_name: String = source_text.substr(opening_index + 1, closing_index - opening_index - 1)
var matched_definition: Dictionary = _find_card_by_display_name(referenced_name)
if matched_definition.is_empty():
	resolved_text += source_text.substr(opening_index, closing_index - opening_index + 1)
else:
	resolved_text += "【%s】" % GameSettings.resolve_card_name(matched_definition)
```

调用方全在 UI 文本层：`information_box_layer.gd:519/526/528`、`skill_button_view.gd:86`、`all_cards_panel.gd:593/659/718/731/740/768/783/799/806`、`opportunity_card_view.gd:125`、`character_skill_display.gd:88`。

### 4.3 显示名 ≠ 定义名的后果

1. **规则侧零影响** —— 所有 `play_limit_group` / `response_pattern` / `effect_id` / 同名判定 / AI 取值都读 `definition_id` 与定义字典。
2. **★唯一的名称副作用**：卡牌悬停信息框经 `information_box_layer.gd:514 _resolve_information_card_names()` → `resolve_card_names_in_text()` **再解析一次 title**。若 `custom_display_name` 恰好等于另一张已登记牌的 `original_name` 或 `custom_name`，标题会被**改写**成那张牌的名字。→ **查重必须使用双名索引口径。**
3. **名字数规则不跟随**：`get_card_original_name_length()`（`match_controller.gd:7792`）读定义，实例自定义名不参与。
4. **日志文本已固化**：`format_card_log_name` 在写入时定型，回放日志不会回溯变化。
5. **延时锦囊「同名」按定义 ID 判定**：复制【乐不思蜀】得到的牌与真实【乐不思蜀】**在判定区互斥**（`card_rule_service.gd:495-498`）。这是「规则身份 = 被复制牌」的直接推论，需在文档中明确记录。

---

## 5. 运行时定义注册表（背景，本任务不采用）

- `_load_cards()`（`game_database.gd:317-341`）填充：`cards[card_id]`（`:338`）、`_index_card_display_names(metadata)`（`:339`）、`card_definitions[card_id]`（`:340`）、`card_scripts[card_id]`（`:341`）。
- `reload_all()`（`:84-109`）清空 `validation_errors, cards, _card_definitions_by_display_name, _resolved_card_text_cache_by_mode, card_definitions, card_scripts, decks, characters, character_definitions, factions, skills, skill_scripts, player_effects, player_effect_scripts`（`:85-98`），再重建。
- **会被运行时注册定义污染的全量枚举点**：图鉴 `all_cards_panel.gd:388/395/402` + `card_gallery_sort.gd:86/102`；校验 `game_database.gd:600-608`；开发者控制台 `developer_console_panel.gd:645/653/732/763`；濒死响应模式 `match_controller.gd:15210`；回合钩子广播 `:18497`/`:18506`；名字数取牌 `:7623`；技能枚举 `zimo.gd:266`；测试 `smoke_test.gd:139/152-156/397`、`new_character_mechanics_test.gd:264/267/271`、`kafuka_mechanics_test.gd:320`、`gameplay_regression_test.gd:1561`、`performance_and_pacing_test.gd:132-136`。

→ 这就是**不采用方案 A（运行时定义注册表）**的实证依据。

---

## 6. 完整实施清单

### A. 数据层（必改，3 处）
1. `scripts/data/card_instance.gd:13` 附近 —— 新增 `var custom_display_name: String = ""` 与 `var minted_skill_id: String = ""`（各自独立注释行）。
2. `card_instance.gd:257-295 to_dict()` —— 加两个键。
3. `card_instance.gd:88-115 from_dict()` —— 加两行读取（**否则存档/网络/回放全部丢字段**）。
4. 决策点：`card_instance.gd:137 set_hand_view_as()` / `:173 set_hand_view_as_with_face()` —— 视为状态下 `custom_display_name` 保留（显示实体原名 + 视为横条）；`clear_hand_view_as()`（`:148`）不动。

### B. 名称解析集中入口（建议新增，1 处）
5. `scripts/autoload/game_settings.gd:1079-1093` —— 新增 `resolve_instance_display_name(card_dict, definition) -> String`：非空 `custom_display_name` 优先，否则回落 `resolve_card_display_name(definition)`。**所有下游改调它**，避免 20+ 处各自判空。

### C. UI 牌面（必改）
6. `card_view.gd:294`（主名称）与 `:275`（视为横条）—— 用实例名覆盖；`:662` 悬停 title 随之自动生效。
7. `equipment_stack_view.gd:198` + `:297`。
8. `player_target_view.gd:1349`、`:1459`、`:1504`、`:1142`、`:1610`、`:1616`。
9. `match_table.gd:3112`、`:3126`、`:3541`、`:5912`。
10. `developer_console_panel.gd:732`、`:763`。
11. 自动生效、无需改：`match_table.gd:2601/4788/4901/5212`、`card_selection_panel.gd:768`。

### D. 日志（必改）
12. ★`match_controller.gd:4367-4380 format_card_log_name()` —— `card_name_text` 优先 `card.custom_display_name`（改一处覆盖全部调用方）。
13. `match_controller.gd:4464-4473 describe_card()` —— 同步。
14. `match_controller.gd:14635`（重铸日志）、`:5382`（装备响应 `response_title`）—— 已有实例，改用实例名。
15. 保持定义名：`:4429 format_card_definition_log_name()`、`:5515`、`:5889`、`:10924`、`:11123`、`:11142`、`card_effect_resolver.gd:62`。

### E. 存档 / 网络 / 回放（验证项，无额外改动）
16. `match_controller.gd:15838/15856-15862` + `player_state.gd:508/514/519/525` —— 随 A 自动生效。
17. `match_controller.gd:16042` + `:16108-16111` + `player_state.gd:359/363/365/367` —— 随 A 自动生效。
18. `conquest_save_store.gd:12 SAVE_FORMAT_VERSION` —— **不需要 bump**。
19. `match_replay_recorder.gd:113/137/186` + `match_replay_playback_driver.gd:121` —— 自动生效。
20. `match_controller.gd:18097/18117/18146`、`:6881`、`:17292-17302`、`:17315-17337` —— 自动生效。
21. `card_presentation_event.gd:39/53`、`converted_card_presentation.gd:43-51` —— 自动生效。

### F. 铸造与查重（新增逻辑，必做）
22. `game_database.gd:176` 附近 —— 新增公开查重 API（如 `is_card_display_name_taken(name) -> bool`），复用双名索引口径。
23. 铸造入口（`match_controller.mint_card_for_player`）—— 写入两个新字段；查重失败即拒绝。
24. 确认 `record_card_name`（`:11112`）/ `remove_recorded_card_name`（`:11131`）**继续用 `definition_id`**（改成自定义名会污染 `recorded_card_names` / `skill_used_card_names` 语义）。
25. 决策点：`get_card_original_name_length()`（`:7792`）是否让自定义名参与名字数结算（当前不参与）。

### G. 文档（项目规范强制）
26. `docs/卡牌系统.md` + `docs/游戏机制与玩法内容.md` —— 记录新字段、查重规则（双名口径）、名字数口径、延时锦囊同名按定义 ID 判定的推论。
27. `docs/内容制作指南.md` + `docs/架构说明.md`。
28. 根目录 `临时反馈文档.md` —— 追加学习反馈摘要 + Git 提交描述。

### H. 测试（建议补）
29. `smoke_test.gd:139/152-156/397`、`conquest_save_test`、`match_replay_test`、`card_back_overlay_test.gd:70` —— 补「自定义名经存档/回放/网络往返后仍显示」断言。
