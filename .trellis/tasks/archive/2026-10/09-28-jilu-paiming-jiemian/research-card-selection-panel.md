# CardSelectionPanel 牌名候选支持能力调研报告

调研目标：为 `scripts/ui/card_selection_panel.gd` 新增「从一组仅有卡牌定义 ID（如 `"nanman"`）的牌名中选择一个」的能力，界面呈现为类似五谷丰登的牌面排布，但隐藏花色与点数。

调研范围：只读代码，未修改任何文件。涉及文件：
- `scripts/ui/card_selection_panel.gd`（852 行）
- `scripts/ui/card_view.gd`（694 行）
- `scripts/ui/match_table.gd`（5151 行）
- `scripts/core/match_controller.gd`（15598 行）
- `scripts/data/choice_request.gd`（365 行）
- `scripts/data/card_instance.gd`（218 行）
- `game_data/cards/wugufengdeng.gd`（190 行）
- `game_data/skills/linggan.gd`（316 行）
- `game_data/skill_definition.gd`

---

## 1. 选择请求的入口与数据结构

### 结论

面板只有 **两个** 公开接收请求的入口：

| 入口 | 行号 | 用途 |
|---|---|---|
| `show_request(choice_request: Dictionary)` | `card_selection_panel.gd:238` | 普通选牌 / 响应 / 弃牌 / 文字控制项 / 牌堆排序（四合一，按 `choice_type` 分流） |
| `show_public_display(display_data: Dictionary, choice_request: Dictionary = {})` | `card_selection_panel.gd:334` | 公共展示（五谷丰登），第二个参数是「轮到本地玩家时的权威请求」 |

对外信号共 6 个（`card_selection_panel.gd:7-22`）：`choice_submitted`、`choice_cancelled`、`control_submitted`、`arrangement_submitted`、`information_requested`、`information_dismissed`。

### 代码依据

`show_request` 的字段消费点（`card_selection_panel.gd:238-293`）：

```gdscript
238: func show_request(choice_request: Dictionary) -> void:
239: 	_choice_request = choice_request.duplicate(true)
252: 	_title_label.text = str(_choice_request.get("title", "选择卡牌"))
253: 	_set_prompt_text(str(_choice_request.get("prompt", "请选择卡牌")), str(_choice_request.get("prompt_highlight", "")))
254: 	if str(_choice_request.get("choice_type", "card")) == "arrange":
259: 	if str(_choice_request.get("choice_type", "card")) in ["control", "bool"]:
261: 		var control_display_candidates: Array = ((_choice_request.get("context", {}) as Dictionary).get("display_candidates", []) as Array)
263: 		_add_control_options(_choice_request.get("control_options", []) as Array)
274: 	for selectable_variant: Variant in _choice_request.get("candidates", []):
277: 	var display_candidates: Array = ((_choice_request.get("context", {}) as Dictionary).get("display_candidates", _choice_request.get("candidates", [])) as Array)
284: 		var zone: String = str(candidate.get("zone", "processing"))
290: 	_cancel_button.visible = bool(_choice_request.get("allow_cancel", false)) or int(_choice_request.get("min_select", 0)) == 0
```

运行时请求字典的完整字段集（由 `match_controller.gd:2703-2723` 构造）：

```gdscript
2703: 	_pending_card_choice = {
2704: 		"request_id":-1,
2705: 		"chooser_id":chooser_id,
2706: 		"title":title,
2707: 		"prompt":prompt,
2708: 		"candidates":serialized_candidates,
2709: 		"choice_type":choice_type,
2710: 		"target_ids":choice_target_ids.duplicate(),
2711: 		"control_options":serialized_control_options.duplicate(true),
2712: 		"min_select":maxi(min_select, 0),
2713: 		"max_select":maxi(max_select, min_select),
2714: 		"min_card_select":...,
2715: 		"max_card_select":...,
2716: 		"min_target_select":...,
2717: 		"max_target_select":...,
2718: 		"allow_cancel":allow_cancel,
2719: 		"resume_phase":resume_phase,
2720: 		"context":context.duplicate(true),
2721: 		"choice_event_name":choice_event_name,
2722: 		"deferred":interactive_human or ai_controlled_chooser,
2723: 	}
```

补充字段：`request_id` 在 `match_controller.gd:2791` 被权威分配；`runtime_event_id`（`:2792`）、`runtime_request_id`（`:2793`）。UI 侧另外读取 `prompt_highlight`（`:253`）与 `context.display_candidates`（`:277`）、`context.valid_card_combinations`（`:778`）。

候选元素结构（`match_controller.gd:6129-6132`）：

```gdscript
6128: ## 把实体牌转换为选择候选；隐藏候选只保留 UID 和牌背语义，不携带牌面定义。
6129: func _serialize_choice_candidate(card: CardInstance, owner_id: int, zone: String, visible: bool, slot: String = "") -> Dictionary:
6131: 	var card_data: Dictionary = card.to_dict() if visible else {"uid":card.uid, "definition_id":"", "suit":"none", "rank":0, "zone":zone, "owner_id":owner_id}
6132: 	return {"uid":card.uid, "owner_id":owner_id, "zone":zone, "slot":slot, "visible":visible, "card_data":card_data}
```

`card_data` 即 `CardInstance.to_dict()`（`card_instance.gd:194-218`）：`uid`、`definition_id`、`original_definition_id`、`suit`、`rank`、`color`、`color_override`、`zone`、`owner_id`、`known_to`、`shown`、`private_owner_id`、`hand_view_as_source_skill_id`、`hand_mark_tags`、`presentation_original_definition_id`、`view_as_definition_id`。

### 请求从哪里下发

三条链路，最终都汇聚到 `MatchController.request_card_choice`：

1. **技能侧（推荐参考）**：`game_data/skill_definition.gd:572/577/594/599/609/618/627/636` 提供 `request_card_selection`、`request_card_selection_for_player`、`request_control_selection`、`request_control_selection_for_player`、`request_target_control_selection`、`request_target_selection`、`request_card_target_selection`、`request_pile_arrangement`，全部 `host.call("request_card_choice"|"request_control_choice", ...)`。
2. **控制器包装接口**：`match_controller.gd:2829 request_control_choice`、`:2843 request_target_control_choice`、`:2905 request_target_choice`、`:2920 request_card_target_choice`。
3. **公共展示**：规则卡牌直接调用 `set_public_card_choice_display`（`match_controller.gd:2935`）→ 信号 `public_card_choice_display_changed` → `match_table.gd:3438 _on_public_card_choice_display_changed`。

`match_table.gd` 侧的接线与显示决策：

```gdscript
545: 	card_selection_panel.control_submitted.connect(_on_control_choice_submitted)
594: 	card_selection_panel.choice_submitted.connect(_on_card_choice_submitted)
595: 	card_selection_panel.choice_cancelled.connect(_on_card_choice_cancelled)
596: 	card_selection_panel.arrangement_submitted.connect(_on_pile_arrangement_submitted)
```

```gdscript
3549: ## 根据公共展示与本地独立请求统一决定选择窗口内容；公共展示始终优先保持可见。
3550: func _refresh_card_selection_panel() -> void:
3552: 	if not _public_card_choice_display.is_empty():
3559: 			card_selection_panel.show_request(_enrich_target_zone_card_choice_request(_modal_card_choice_request))
3570: 		card_selection_panel.show_public_display(enriched_display, interactive_request)
3572: 	if not _modal_card_choice_request.is_empty():
3573: 		card_selection_panel.show_request(_enrich_target_zone_card_choice_request(_modal_card_choice_request))
3575: 	card_selection_panel.close()
```

`_modal_card_choice_request` 由 `match_table.gd:3490-3491` 从 `_on_card_choice_requested` 写入；`_enrich_target_zone_card_choice_request`（`:3579`）只对 `target_id`/`target_player_id` 场景改写提示文案，不改变候选结构。

提交回传（`match_table.gd:3499-3546`）：

```gdscript
3501: 	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
3502: 	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "confirmed":true}
3531: 	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_control_id":"", "confirmed":false}
3542: 	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":control_id, "confirmed":true}
```

权威侧校验在 `ChoiceRequest.validate_response`（`choice_request.gd:178-254`），其中 `_validate_selected_candidates`（`:322-331`）要求提交的每个值都必须在 `card_ids`/`control_ids` 中，且不得重复。

---

## 2. 普通候选牌的渲染

### 结论

重建函数是 `_add_zone_row(zone, candidates)`（`card_selection_panel.gd:583`），它按区域开标题 + `HFlowContainer`，每个候选交给 `_add_card_slot(card_row, candidate, selectable, taken, name, create_owner_label)`（`:663`）。`_add_card_slot` 是**唯一的牌面实例化点**，普通候选、只读展示牌、公共展示牌、排序牌全部走它。

牌面信息的两段式取法（关键）：

- **表现数据**：`candidate["card_data"]`（`:674`）
- **静态定义**：`GameDatabase.get_card(card_data["definition_id"])`（`:676`）
- 两者一起交给 `CardView.configure(card_data, definition, wooden_ox_card, interactable, dim_when_disabled)`（`:680`）

### 代码依据

```gdscript
582: ## 为一个非空区域创建标题与横向牌列；空区域不占用布局空间。
583: func _add_zone_row(zone: String, candidates: Array) -> void:
584: 	if candidates.is_empty():
585: 		return
598: 	var card_row: HFlowContainer = HFlowContainer.new()
599: 	card_row.add_theme_constant_override("h_separation", 8)
603: 	for candidate_variant: Variant in candidates:
604: 		var candidate: Dictionary = candidate_variant as Dictionary
605: 		_add_card_slot(card_row, candidate, _selectable_card_uids.has(int(candidate.get("uid", -1))), false, "")
```

```gdscript
663: func _add_card_slot(card_row: Container, candidate: Dictionary, selectable: bool, taken: bool, taken_by_character_name: String, create_owner_label: bool = false) -> void:
665: 	var wrapper: Control = Control.new()
666: 	wrapper.custom_minimum_size = Vector2(111.0, 148.0)
669: 	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
671: 	var card_uid: int = int(candidate.get("uid", -1))
672: 	if bool(candidate.get("visible", false)):
674: 		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
676: 		var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
679: 		var dim_when_disabled: bool = not taken and not bool(candidate.get("read_only_full_brightness", false))
680: 		card_view.configure(card_data, definition, false, selectable, dim_when_disabled)
681: 	else:
682: 		card_view.configure_back(card_uid, selectable)
684: 	if selectable or create_owner_label:
685: 		card_view.pressed.connect(_on_card_pressed.bind(card_uid))
694: 	wrapper.add_child(card_view)
696: 	card_view.information_requested.connect(information_requested.emit)
697: 	card_view.information_dismissed.connect(information_dismissed.emit)
698: 	_card_views[card_uid] = card_view
```

区域聚合入口（`:271-289`）：

```gdscript
271: 	var candidates_by_zone: Dictionary = {"hand":[], "equipment":[], "judgment":[], "processing":[], "discard_pile":[]}
273: 	var selectable_candidate_uids: Array[int] = []
274: 	for selectable_variant: Variant in _choice_request.get("candidates", []):
276: 		selectable_candidate_uids.append(int(selectable_candidate.get("uid", -1)))
281: 		var candidate_uid: int = int(candidate.get("uid", -1))
282: 		if candidate_uid >= 0 and selectable_candidate_uids.has(candidate_uid) and not _selectable_card_uids.has(candidate_uid):
283: 			_selectable_card_uids.append(candidate_uid)
284: 		var zone: String = str(candidate.get("zone", "processing"))
288: 	for zone: String in ["hand", "equipment", "judgment", "processing", "discard_pile"]:
289: 		_add_zone_row(zone, candidates_by_zone.get(zone, []) as Array)
```

只读展示牌走另一个入口 `_add_read_only_display_candidates`（`:297-310`），它给候选补 `read_only_full_brightness = true`（`:303`）后同样调用 `_add_zone_row`。

**牌面信息字段名汇总**：候选层 `uid` / `owner_id` / `zone` / `slot` / `visible` / `card_data` / `read_only_full_brightness`；`card_data` 层 `uid` / `definition_id` / `suit` / `rank` / `presentation_original_definition_id` / `view_as_definition_id` / `hand_mark_tags`。

---

## 3. 公共展示（五谷丰登）模式

### 结论

- 数据结构由规则卡牌构造，键为 `kind` / `title` / `prompt` / `active_player_id` / `slots`；每个 slot 为 `{uid, card_data, taken_by_player_id}`（客户端补充 `taken_by_character_name`）。
- 渲染入口是 `_add_public_card_row(display_slots)`（`card_selection_panel.gd:635`），布局用 `GridContainer` 固定 4 列（`PUBLIC_CARD_COLUMNS = 4`，`:49`）。
- 与普通候选的关键差异（5 点）：
  1. **布局容器不同**：GridContainer 固定列 + `SIZE_SHRINK_CENTER`（`:639-643`）vs 普通 HFlowContainer 自动换行（`:598`）。
  2. **不读 `visible`**：公共展示强制 `"visible":true`（`:653-657`），普通候选可走 `configure_back` 牌背分支（`:682`）。
  3. **支持「已领取」状态**：`taken` 叠加 `taken_card_ghost_modulate` 虚影（`:692-693`、`:425`）+ 底部领取者标签（`:703-717`）。
  4. **节点复用**：公共展示有结构签名 `_get_public_layout_signature`（`:388-395`）与 `_public_layout_signature`（`:127`）缓存比对，数据变化只原位刷新（`:339-351`、`_refresh_public_slot_states` `:414-433`）；普通候选每次 `show_request` 全量 `_clear_container` 重建（`:250`）。
  5. **可选性来源不同**：公共展示用 `_refresh_public_selectable_card_uids`（`:399-410`）从 `_choice_request.candidates` 取 UID；普通请求在 `show_request` 内联构建 `_selectable_card_uids`（`:274-283`）。
- 窗口尺寸按牌阵计算（`:366-375`），高度上限 `public_panel_max_height = 620`（`:67`）。

### 代码依据

数据构造（`game_data/cards/wugufengdeng.gd:41-53`、`:180-190`）：

```gdscript
41: 	var harvest_display_slots: Array[Dictionary] = []
42: 	for revealed_card: CardInstance in revealed_cards:
43: 		revealed_uids.append(revealed_card.uid)
44: 		harvest_display_slots.append({
45: 			"uid":revealed_card.uid,
46: 			"card_data":revealed_card.to_dict(),
47: 			"taken_by_player_id":-1,
48: 		})
```

```gdscript
181: func _publish_harvest_display(resolver: Object, context: Dictionary, active_player_id: int) -> void:
183: 	var display_data: Dictionary = {
184: 		"kind":"harvest",
185: 		"title":"五谷丰登",
186: 		"prompt":"每名角色依次选择一张展示牌",
187: 		"active_player_id":active_player_id,
188: 		"slots":(context.get("harvest_display_slots", []) as Array).duplicate(true),
189: 	}
190: 	resolver.host.set_public_card_choice_display(display_data)
```

渲染入口（`card_selection_panel.gd:635-658`）：

```gdscript
635: func _add_public_card_row(display_slots: Array) -> void:
639: 	var card_row: GridContainer = GridContainer.new()
640: 	card_row.columns = PUBLIC_CARD_COLUMNS
641: 	card_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
645: 	for slot_variant: Variant in display_slots:
647: 		var display_slot: Dictionary = slot_variant as Dictionary
649: 		var card_uid: int = int(display_slot.get("uid", -1))
651: 		var taken_by_player_id: int = int(display_slot.get("taken_by_player_id", -1))
653: 		var candidate: Dictionary = {
654: 			"uid":card_uid,
655: 			"visible":true,
656: 			"card_data":display_slot.get("card_data", {}) as Dictionary,
657: 		}
658: 		_add_card_slot(card_row, candidate, _selectable_card_uids.has(card_uid) and taken_by_player_id < 0, taken_by_player_id >= 0, str(display_slot.get("taken_by_character_name", "")), true)
```

客户端名称补充（`match_table.gd:3642-3672`，写入 `prompt` 与 `taken_by_character_name`）：

```gdscript
3654: 		result["prompt"] = "【%s】正在选择展示牌" % active_character_name
3669: 			display_slot["taken_by_character_name"] = taken_by_character_name
3671: 	result["slots"] = enriched_slots
```

---

## 4. 文字控制项模式

### 结论

- 触发条件：`choice_type` ∈ `["control", "bool"]`（面板侧 `:259`）；数据来自请求顶层 `control_options`（不是 `context` 里）。
- 数据结构：`Array[Dictionary]`，每项 `{"id": String, "label": String}`；权威侧会过滤空 ID / 空 label / 重复 ID（`match_controller.gd:2683-2697`）。
- 渲染函数：`_add_control_options(options)`（`:609-631`），生成 280×44 的按钮列，按钮 `pressed` 绑定 `_on_control_option_pressed.bind(option_id)`（`:629`）。
- 提交回传：`_on_control_option_pressed(control_id)`（`:824-825`）→ 信号 `control_submitted(request_id, control_id)` → `match_table._on_control_choice_submitted`（`:3539-3546`）→ `choose_cards` 动作的 `selected_control_id`。
- 该模式下 `_confirm_button.visible = false`、`_cancel_button.visible = allow_cancel`（`:264-266`）；若请求带 `context.display_candidates` 会先渲染只读牌面（`:261-262`）。
- 另有一条 **内联旁路**：`match_table._is_inline_control_choice`（`:3700-3705`）在 `control_options` 存在且 `display_candidates` 为空时，把选项直接放到牌桌操作区，**根本不打开面板**。若新需求希望「牌面样式的牌名选择」必须出现在面板里，这一点必须在选择请求上做区分（例如带 `display_candidates` 或新的 `choice_type`）。

### 代码依据

```gdscript
258: 	# 文字控制项请求；每个选项直接以独立按钮提交，底部确定按钮不重复制造二次确认。
259: 	if str(_choice_request.get("choice_type", "card")) in ["control", "bool"]:
261: 		var control_display_candidates: Array = ((_choice_request.get("context", {}) as Dictionary).get("display_candidates", []) as Array)
262: 		_add_read_only_display_candidates(control_display_candidates)
263: 		_add_control_options(_choice_request.get("control_options", []) as Array)
264: 		_confirm_button.visible = false
265: 		_cancel_button.visible = bool(_choice_request.get("allow_cancel", false))
266: 		_action_row.visible = _cancel_button.visible
```

```gdscript
609: func _add_control_options(options: Array) -> void:
611: 	var option_column: VBoxContainer = VBoxContainer.new()
615: 	for option_variant: Variant in options:
617: 		var option: Dictionary = option_variant as Dictionary
618: 		var option_id: String = str(option.get("id", ""))
619: 		var option_label: String = str(option.get("label", ""))
620: 		if option_id.is_empty() or option_label.is_empty():
621: 			continue
623: 		var option_button: Button = Button.new()
624: 		option_button.text = option_label
626: 		option_button.custom_minimum_size = Vector2(280.0, 44.0)
629: 		option_button.pressed.connect(_on_control_option_pressed.bind(option_id))
```

```gdscript
823: ## 提交一个文字控制项；请求 ID 与稳定选项 ID 会继续经过 MatchController 和 ChoiceRequest 双重校验。
824: func _on_control_option_pressed(control_id: String) -> void:
825: 	control_submitted.emit(int(_choice_request.get("request_id", -1)), control_id)
```

**重要既有先例**：`game_data/skills/linggan.gd:238-249` 已经实现「从一组牌名 ID 中选择」，用的正是 control_options：

```gdscript
238: func _get_effect_name_options(owner: PlayerState, excluded_ids: Array) -> Array[Dictionary]:
239: 	var options: Array[Dictionary] = []
240: 	for definition_id: String in owner.recorded_card_names:
243: 		var definition: Dictionary = GameDatabase.get_card(definition_id)
247: 		var label: String = GameSettings.resolve_card_name(definition)
248: 		options.append({"id":definition_id, "label":label})
249: 	return options
```

`linggan.gd:96` 通过 `request_control_selection_for_player(owner_player_id, "灵感", "选择一张记录的牌名作为视为使用的牌", options, true, {"kind":CHOICE_PICK_EFFECT})` 下发；恢复时用 `response.control_id` 直接当 `definition_id` 使用（`linggan.gd:113`）。这说明**「牌名 ID」的协议通道已经存在且被权威校验支持**（`ChoiceRequest._get_allowed_values` 对 control 返回 `control_ids`，`choice_request.gd:296-297`、`:215-216`）。缺的只是「牌面样式 + 隐藏花色点数」的呈现。

---

## 5. CardView 对外接口

### 结论

- 喂入方式：`configure(card: Dictionary, definition: Dictionary, wooden_ox_card: bool, interactable: bool, dim_when_disabled: bool = true)`（`card_view.gd:221`）。`card` 是**牌面/实体快照**，`definition` 是**静态定义**（`GameDatabase.get_card` 的返回值）。两者职责不同，缺一不可。
- **能否只凭定义 ID 渲染？** 能渲染出 **名称 / 类别 / 插画 / 类别色**，但**花色点数会被强制渲染为 `?0`**：`configure` 无条件从 `card` 读取 `suit`/`rank`（`:262-269`），`_suit_symbol` 对未知花色返回 `"?"`（`:676`），`_rank_text(0)` 返回 `"0"`（`:681`）。
- **是否支持隐藏花色与点数？** **不支持**。没有相关 `@export`、公开属性或方法；`_corner_label`（`:161`）只在 `_refresh_card_content` 中无条件写文本（`:437`），没有 `visible` 控制点。悬停信息副标题也把花色点数写死进去（`:598`）。
- 另需注意：`configure` 的签名/缓存命中依赖 `hash([card, definition, ...])`（`:223`），空 `definition` 时类别色回退为 `border` 色、类别文本回退为 `"卡牌"`（`:671`、`:694`），所以牌名候选**必须**提供真实 definition。

### 公开方法清单（全部 `func`，非 `_` 前缀）

| 方法 | 行号 | 说明 |
|---|---|---|
| `get_card_size() -> Vector2` | 206 | 返回 111×148 |
| `get_global_rect() -> Rect2` | 211 | 全局矩形 |
| `is_hovered_in_hand() -> bool` | 216 | 悬停只读查询 |
| `configure(card, definition, wooden_ox_card, interactable, dim_when_disabled=true)` | 221 | 正面配置主入口 |
| `configure_back(entity_uid: int, interactable: bool)` | 282 | 牌背配置 |
| `refresh_ui_style()` | 304 | 主题刷新 |
| `set_selected_state(selected: bool)` | 312 | 选中描边 |
| `set_interactable_state(interactable: bool)` | 325 | 交互权限切换 |
| `set_external_reorder_zone(reorder_zone: String)` | 335 | 外部拖动分区 |
| `is_hand_dragging() -> bool` | 351 | 拖动只读查询 |
| `begin_hand_drag(pointer_global_position: Vector2)` | 356 | 开始拖动 |
| `move_hand_drag(pointer_global_position: Vector2)` | 365 | 拖动跟随 |
| `end_hand_drag()` | 372 | 结束拖动 |

公开信号：`pressed`（`:7`）、`hand_reorder_requested`（`:10`）、`hand_drag_started`（`:13`）、`hand_drag_moved`（`:16`）、`hand_drag_finished`（`:19`）、`information_requested`（`:22`）、`information_dismissed`（`:25`）。

公开可配置 `@export`：`card_width`（`:29`）、`card_height`（`:32`）、`selected_lift`（`:35`）、`selection_animation_seconds`（`:38`）、`hover_scale`（`:41`）、`hover_animation_seconds`（`:44`）、`disabled_darkening`（`:47`）、`disabled_content_modulate`（`:50`）、`view_as_banner_height`（`:54`）、`view_as_banner_font_size`（`:57`）、`view_as_banner_opacity`（`:61`）。

公开可变字段：`card_uid`（`:64`）、`is_wooden_ox_card`（`:67`）、`external_reorder_zone`（`:70`）、`is_card_selected`（`:73`）、`is_interactable`（`:76`）、`is_face_down`（`:79`）、`hand_entry_offset`（`:82`）、`hand_selection_offset`（`:88`）。**没有任何 `hide_suit_rank` 类字段。**

### 关键代码依据

```gdscript
261: 	# 花色文本；红色花色使用单独字体色，黑色花色保持深褐色。
262: 	var suit_text: String = _suit_symbol(str(card.get("suit", "")))
263: 	# 点数文本；A、J、Q、K使用标准牌面字符。
264: 	var rank_text: String = _rank_text(int(card.get("rank", 0)))
269: 	_suit_rank_text = "%s%s" % [suit_text, rank_text]
```

```gdscript
437: 	_corner_label.text = _suit_rank_text
444: 	var content_color: Color = BattleUIStyle.get_color("card_red_suit") if _suit_rank_text.begins_with("♥") or _suit_rank_text.begins_with("♦") else BattleUIStyle.get_color("card_text")
445: 	_corner_label.add_theme_color_override("font_color", content_color)
```

```gdscript
674: ## 将花色 ID 转换为牌面符号。
675: func _suit_symbol(suit: String) -> String:
676: 	return {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}.get(suit, "?")
679: ## 将点数转换为牌面字符。
680: func _rank_text(rank: int) -> String:
681: 	return {1:"A", 11:"J", 12:"Q", 13:"K"}.get(rank, str(rank))
```

```gdscript
596: 	if not is_face_down and not _card_definition.is_empty():
598: 		var information_subtitle: String = "%s｜%s" % [_suit_rank_text, _card_type_text]
```

`_rank_text` 的 `int(card.get("rank", 0))` 意味着**缺 `rank` 字段显示 `0`**，不是空字符串——这是牌名候选必须处理的隐性坑。

---

## 6. 支持「仅定义 ID 的牌名候选」的最小改动点

### 建议新增字段（协议层，全部走现有 `Dictionary` 请求，无需改 `ChoiceRequest` 类）

- `choice_type` 新值：`"card_name"`（放在 `show_request` 顶层的 `choice_type`，与 `arrange`/`control` 并列）
- 请求顶层新字段：`name_candidates: Array`，元素为 `{"definition_id": String, "uid"?: int}`（`uid` 可选，缺失时面板内部按索引占位）
- 复用字段：`title`、`prompt`、`prompt_highlight`、`min_select`、`max_select`、`allow_cancel`、`context`
- 新增提交信号：`name_submitted(request_id: int, selected_definition_ids: Array[String])`（若要单选也可 `name_submitted(request_id, definition_id)`），与现有 `choice_submitted` 的 `Array[int]` 签名**不兼容，必须另开信号**，否则 `match_table._on_card_choice_submitted`（`:3499`）会把它当 UID 装进 `selected_card_uids`。

### 需要加分支的函数（按改动量从大到小）

| 函数 | 行号 | 需要的分支 |
|---|---|---|
| `show_request` | `card_selection_panel.gd:238` | 在 `:254`（arrange）与 `:259`（control）之间插入 `if choice_type == "card_name": _show_name_candidate_request(); visible = true; return` |
| 新函数 `_show_name_candidate_request()` | 新增（建议放在 `_add_zone_row` 前，约 `:583`） | 读 `name_candidates`，把每个 definition_id 经 `GameDatabase.get_card` 转成 definition，构造 `candidate = {"uid": 占位, "visible": true, "card_data": {"definition_id": ..., "suit": "", "rank": 0, "hide_suit_rank": true}}`，再调用 `_add_public_card_row`（复用 4 列牌阵）或 `_add_zone_row("processing", candidates)`（复用普通布局）。**这是唯一的新渲染入口** |
| `_add_card_slot` | `:663` | 在 `:674-680` 处把 `card_data` 直接透传即可；若走 CardView 新增的隐藏开关，需要把 `bool(card_data.get("hide_suit_rank", false))` 传进 `configure`（多一个实参） |
| `_on_card_pressed` | `:733` | 若用索引占位，需要新增按索引查 definition_id 的旁路；若沿用 `uid` 占位可直接复用现有 `_selected_card_uids` 逻辑（`:737-747`） |
| `_on_confirm_pressed` | `:814` | 新增 `card_name` 分支，发新信号而不是 `choice_submitted`（`:820`） |
| `close` / `refresh_ui_style` | `:446` / `:210` | **无需改动**，只要新分支把状态存进 `_card_views` 与既有数组 |
| 新字段声明 | `:84` 附近 | `var _name_candidates: Dictionary = {}`（索引/UID → definition_id、名称），供提交时反查 |

### CardView 侧的最小改动（1 处）

`configure` 增加一个可选参数（默认 `false`，保证三种现有模式行为完全不变）：

```gdscript
# 现状
221: func configure(card: Dictionary, definition: Dictionary, wooden_ox_card: bool, interactable: bool, dim_when_disabled: bool = true) -> void:
```

新增形参 `hide_suit_rank: bool = false`，并在 `:269` 后覆盖 `_suit_rank_text = ""` 且让 `:437` 的 `_corner_label.visible = not hide_suit_rank`（同时 `:598` 的副标题跳过花色点数、`:444` 的红色判定回退到普通牌名色）。**注意**：`:223` 的配置签名 `hash([card, definition, wooden_ox_card, interactable, dim_when_disabled, ...])` 必须把新参数并入哈希，否则同一实例在两种模式下切换会命中旧缓存而不刷新。

### 可以原样复用的现有函数

- `_add_card_slot`（`:663`）：包装器、CardView 实例化、`pressed` 绑定、`information_requested` 转发、`_card_views` 登记，全部可复用。
- `_add_public_card_row`（`:635`）：4 列牌阵布局可直接复用（传 `taken_by_player_id = -1` 即无虚影）。若不需要 4 列，`_add_zone_row`（`:583`）同样可直接复用。
- `_refresh_selection_state`（`:752`）：`_card_views` 遍历 + `set_selected_state` / `set_interactable_state` 可复用。
- `_get_dynamic_selectable_card_uids`（`:772`）：`valid_card_combinations` 为空时直接返回全部候选，可复用于牌名候选。
- `_set_prompt_text`（`:314`）、`_set_frame_size`（`:834`）、`_clear_container`（`:849`）、`_restore_standard_zone_scroll_behavior`（`:323`）、`refresh_ui_style`（`:210`）、`close`（`:446`）全部原样可用。
- 布局常量 `PUBLIC_CARD_COLUMNS` / `PUBLIC_CARD_SIZE` / `PUBLIC_CARD_GAP`（`:49-55`）可直接复用。

### 下发侧（`match_table.gd`）需要的最小改动

- `_is_inline_control_choice`（`:3700`）不会被 `card_name` 命中（它只认 `control`/`bool`/`target_control`），但 `_is_inline_hand_choice`（`:3676`）会：`card_name` 的 `candidates` 为空数组时，`:3682` 的 for 循环不执行并返回 `true`，导致**内联路径被误判**。必须在 `:3678` 的排除列表中加入 `"card_name"`（或在 `:3682` 前加一条显式排除）。
- `_refresh_card_selection_panel`（`:3550`）无需改动，`show_request` 会自然接管。
- 需要在 `:545` 附近新增 `card_selection_panel.name_submitted.connect(...)`，并在新 handler 内构造 `choose_cards` 动作（`control_id` 承载 definition_id 是最省事的做法，可直接复用 `:3542` 的 payload 形状与 `ChoiceRequest` 的 `control_ids` 校验）。**若走这条路，面板侧甚至不必新增信号，`control_submitted` 就能复用**，只是呈现从按钮变成牌面。

---

## 7. 硬编码「候选必有 UID / 必为实体牌」的位置

| 位置 | 函数 | 行号 | 硬编码内容 |
|---|---|---|---|
| 是 | `show_request` | `:276` | `selectable_candidate_uids.append(int(selectable_candidate.get("uid", -1)))` — 可选集合仅由 `uid` 构成 |
| 是 | `show_request` | `:281-283` | `if candidate_uid >= 0 and ... : _selectable_card_uids.append(candidate_uid)` — UID 为负即不可选 |
| 是 | `show_request` | `:284` | `zone` 缺省为 `"processing"`，候选必须能落进 5 个固定区域 |
| 是 | `_add_zone_row` | `:605` | `_selectable_card_uids.has(int(candidate.get("uid", -1)))` |
| 是 | `_add_card_slot` | `:671` | `var card_uid: int = int(candidate.get("uid", -1))` — 无 UID 时统一塌缩为 `-1` |
| 是 | `_add_card_slot` | `:672` | `if bool(candidate.get("visible", false))` — 必须显式写 `visible:true`，否则走牌背分支 |
| 是 | `_add_card_slot` | `:685` | `card_view.pressed.connect(_on_card_pressed.bind(card_uid))` — 回调只携带 UID |
| 是 | `_add_card_slot` | `:698` | `_card_views[card_uid] = card_view` — **以 UID 为字典键；多个无 UID 候选会互相覆盖（键都是 `-1`）** |
| 是 | `_add_public_card_row` | `:649` | `var card_uid: int = int(display_slot.get("uid", -1))` |
| 是 | `_refresh_public_slot_states` | `:419` | `var card_uid: int = int(display_slot.get("uid", -1))` — 领取者标签/虚影全部按 UID 定位 |
| 是 | `_refresh_public_selectable_card_uids` | `:405-406` | `if candidate_uid >= 0 and not _selectable_card_uids.has(candidate_uid)` |
| 是 | `_get_public_layout_signature` | `:394` | `{"uid":int(display_slot.get("uid", -1)), "card_data":...}` — 结构签名以 UID 为主键 |
| 是 | `_refresh_selection_state` | `:757` | `var card_uid: int = int(card_uid_variant)`，`:760` `_selected_card_uids.has(card_uid)` — 选中集合是 `Array[int]` |
| 是 | `_on_card_pressed` | `:737` | `_get_dynamic_selectable_card_uids().has(card_uid)`；`:739-747` 增删全为 UID |
| 是 | `_get_dynamic_selectable_card_uids` | `:781-788` | 遍历 `_selectable_card_uids: Array[int]`（`:82`） |
| 是 | `_has_compatible_card_combination` | `:799-801` | 组合元素强制 `int(...)` |
| 是 | `_show_arrangement_request` | `:478-483` | `if card_uid < 0 ... continue`；`:483` `_selectable_card_uids.append(card_uid)` |
| 是 | `_create_arrangement_row` | `:519-520` | `for card_uid: int in card_uids` + `_arrangement_candidates_by_uid.get(card_uid, {})` |
| 是 | `_toggle_arrangement_row` | `:525-531` | 全部以 `card_uid` 为键 |
| 是 | `_on_confirm_pressed` | `:816-818` | 排序提交构造 `ordered_uids: Array[int]` |
| 是 | `_on_confirm_pressed` | `:820` | `choice_submitted.emit(request_id, _selected_card_uids.duplicate())` — 提交签名固定为 `Array[int]` UID |
| 是 | 信号声明 | `:7` | `signal choice_submitted(request_id: int, selected_card_uids: Array[int])` |
| 是 | 状态变量 | `:76` / `:79` / `:82` / `:121` / `:139` | `_selected_card_uids: Array[int]`、`_card_views: Dictionary`（UID 键）、`_selectable_card_uids: Array[int]`、`_owner_labels_by_card_uid`、`_arrangement_candidates_by_uid` |
| 否（可作为参考） | `_add_read_only_display_candidates` | `:297-310` | 只补 `read_only_full_brightness`，仍要求候选带 `uid`/`zone` |
| 否 | `_add_control_options` | `:609-631` | **唯一完全不依赖 UID 的渲染路径**，但只渲染按钮 |

补充：`CardView.configure`（`card_view.gd:227`）`card_uid = int(card.get("uid", -1))`、`configure_back`（`:282`）`entity_uid` 均为 UID 语义；`CardView` 的输入组件也以 `card_uid` 配置（`:200`、`:276`、`:299`、`:330`）。

---

## 附：与本需求的既有最接近实现对照

| 维度 | 现有「灵感」（`linggan.gd`） | 现有「五谷丰登」（`wugufengdeng.gd`） | 新需求 |
|---|---|---|---|
| 候选粒度 | 牌名 definition_id | 实体牌 | 牌名 definition_id |
| 协议字段 | `control_options[{id,label}]` | `candidates`/`public_display.slots` | 需新增（或复用 `control_options`） |
| 提交字段 | `selected_control_id` | `selected_card_uids` | 建议复用 `selected_control_id` |
| 呈现 | 文字按钮列 | 4 列牌面（含花色点数） | 牌面 + 隐藏花色点数 |
| 是否已有隐藏花色能力 | 不涉及 | 不需要 | **缺，需给 CardView 加开关** |
