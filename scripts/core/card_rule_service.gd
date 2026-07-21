class_name CardRuleService
extends RefCounted

## 卡牌使用合法性服务。只读取状态与配置，不执行效果或移动卡牌，可被 UI、AI 和服务器共同调用。

## 当前权威对局状态引用；由对局控制器创建服务时注入。
var state: GameState

## 当前技能规则提供者；通常为MatchController，用于汇总已安装技能的纯查询修正，不拥有其生命周期。
var skill_rule_provider: Object


## 绑定需要校验的权威状态；服务本身不拥有该状态的生命周期。
func _init(game_state: GameState, current_skill_rule_provider: Object = null) -> void:
	state = game_state
	skill_rule_provider = current_skill_rule_provider


## 返回两名存活角色之间的最终距离，包含进攻与防御坐骑修正，最小为1。
func calculate_distance(source_id: int, target_id: int) -> int:
	if source_id == target_id:
		return 0
	# 按座次排列的存活玩家；死亡角色不计入距离。
	var alive_players: Array[PlayerState] = state.get_alive_players()
	# 来源角色在存活座次中的索引；不存在时保持 -1。
	var source_index: int = -1
	# 目标角色在存活座次中的索引；不存在时保持 -1。
	var target_index: int = -1
	for index: int in range(alive_players.size()):
		if alive_players[index].player_id == source_id:
			source_index = index
		if alive_players[index].player_id == target_id:
			target_index = index
	if source_index < 0 or target_index < 0:
		return 999
	# 顺时针座次差；用于与逆时针距离取较小值。
	var clockwise: int = abs(target_index - source_index)
	# 基础距离；环形桌面取两个方向中较短者。
	var distance: int = mini(clockwise, alive_players.size() - clockwise)
	# 来源玩家状态；进攻坐骑令其到其他角色的距离-1。
	var source: PlayerState = state.get_player(source_id)
	# 目标玩家状态；防御坐骑令其他角色到其距离+1。
	var target: PlayerState = state.get_player(target_id)
	if source.equipment.has("offensive_mount"):
		distance -= 1
	if target.equipment.has("defensive_mount"):
		distance += 1
	return maxi(distance, 1)


## 返回玩家当前攻击范围；无武器为1，装备武器时读取卡牌配置的 attack_range。
func get_attack_range(player_id: int) -> int:
	# 指定玩家状态；无效 ID 使用基础攻击范围1。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 1
	# 当前武器实体牌；未装备时返回基础值。
	var weapon: CardInstance = player.get_weapon()
	if weapon == null:
		return 1
	# 当前武器定义；缺失 attack_range 时按1处理以保持规则可运行。
	var definition: Dictionary = GameDatabase.get_card(weapon.definition_id)
	return maxi(int(definition.get("attack_range", 1)), 1)


## 返回实体牌在当前状态下允许选择的最大目标数；方天画戟对最后一张手牌【杀】的加成在此统一计算。
func get_maximum_target_count(actor_id: int, card: CardInstance) -> int:
	if card == null:
		return 0
	# 当前卡牌定义；基础最大目标数由数据配置提供，缺失配置时按0处理。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 当前有效最大目标数；普通牌直接使用配置值，装备修正只通过本查询叠加。
	var maximum_target_count: int = int(definition.get("max_targets", 0))
	# 当前行动玩家；不存在时无法应用任何装备修正，但仍返回卡牌配置的基础值。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null:
		return maximum_target_count
	# 当前武器定义；额外目标规则由装备卡牌源码自行修改基础上限。
	var weapon_definition: CardDefinition = _get_equipment_definition(actor, "weapon")
	if weapon_definition != null:
		maximum_target_count = weapon_definition.modify_maximum_target_count(actor, card, maximum_target_count)
	return maximum_target_count


## 检查一条使用牌指令是否合法；返回空字符串表示通过，否则返回可直接显示的原因。
func validate_use(actor_id: int, card: CardInstance, target_ids: Array[int]) -> String:
	# 使用者状态；死亡、越权或不存在的玩家均不能行动。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null or not actor.alive or actor.out_of_game:
		return "行动玩家不存在、已经死亡或已移出游戏。"
	if state.current_player_id != actor_id or state.current_phase != "play":
		return "当前不是该玩家的出牌阶段。"
	if card == null or actor.find_playable_card(card.uid) == null:
		return "指定卡牌不在行动玩家的手牌或木牛流马牌源中。"
	# 当前卡牌定义；牌堆校验正常时不应为空，仍保留防御性检查。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	if definition.is_empty():
		return "卡牌定义不存在。"
	if str(definition.get("target_mode", "")) == "response_only":
		return "该卡牌只能在响应窗口中使用。"

	# 当前武器定义；卡牌源码可声明解除特定牌的阶段使用次数限制。
	var use_limit_weapon_definition: CardDefinition = _get_equipment_definition(actor, "weapon")
	# 配置化使用次数；同一 play_limit_group 的不同实体定义共享计数，例如普通、火与雷【杀】。
	var play_limit: int = int(definition.get("play_limit", 0))
	if play_limit > 0:
		play_limit += _skill_play_count_limit_bonus(actor.player_id, definition)
	if play_limit > 0 and _get_grouped_play_count(actor, definition) >= play_limit and (use_limit_weapon_definition == null or not use_limit_weapon_definition.ignores_play_count_limit(definition)) and not _skill_ignores_play_count_limit(actor.player_id, definition):
		return str(definition.get("play_limit_message", "本阶段使用次数已用尽。"))

	# 规范化后应有的目标数；全体目标牌允许调用方传空数组，但自动展开后仍必须至少保留配置要求的合法目标。
	# 最少目标数；来自配置表并允许0目标的纯响应牌。
	var min_targets: int = int(definition.get("min_targets", 0))
	# 最多目标数；方天画戟的额外目标在专门分支中修正，全体牌通常保留配置的高上限。
	var max_targets: int = get_maximum_target_count(actor_id, card)
	if target_ids.size() < min_targets or target_ids.size() > max_targets:
		return "目标数量不符合卡牌规则。"

	# 已出现的目标 ID；禁止重复指定同一目标。
	var unique_targets: Dictionary = {}
	for target_id: int in target_ids:
		if unique_targets.has(target_id):
			return "不能重复指定同一目标。"
		unique_targets[target_id] = true
		# 单个目标的合法性结果；任何目标失败都会拒绝整条指令。
		var target_error: String = _validate_target(actor, definition, target_id, target_ids, {"card_color":card.get_color()})
		if not target_error.is_empty():
			return target_error
	return ""


## 检查一张无实体牌面的虚拟牌是否可以在当前出牌阶段使用；材料与装备条件由创建虚拟牌的独立规则入口负责校验。
## 虚拟牌不会进入行动玩家的手牌或木牛牌源，因此本函数只复用阶段、次数、目标和距离规则，不执行实体来源检查或方天画戟最后手牌修正。
func validate_virtual_use(actor_id: int, definition_id: String, target_ids: Array[int], rule_overrides: Dictionary = {}) -> String:
	# 虚拟牌使用者；不存在、死亡或不处于自己的出牌阶段时不能声明视为牌。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null or not actor.alive or actor.out_of_game:
		return "行动玩家不存在、已经死亡或已移出游戏。"
	if state.current_player_id != actor_id or state.current_phase != "play":
		return "当前不是该玩家的出牌阶段。"
	# 虚拟牌定义；丈八蛇矛当前固定生成普通【杀】，保留通用定义参数便于其他视为牌复用。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if definition.is_empty():
		return "虚拟牌定义不存在。"
	if str(definition.get("target_mode", "")) == "response_only":
		return "该虚拟牌只能在响应窗口中使用。"
	# 当前武器定义；虚拟牌同样复用装备源码提供的次数解除能力。
	var use_limit_weapon_definition: CardDefinition = _get_equipment_definition(actor, "weapon")
	# 虚拟牌与实体牌读取同一配置化分组计数，避免视为牌绕过次数限制。
	var play_limit: int = int(definition.get("play_limit", 0))
	if play_limit > 0:
		play_limit += _skill_play_count_limit_bonus(actor.player_id, definition)
	var ignore_play_count_limit: bool = bool(rule_overrides.get("ignore_play_count_limit", false)) or _skill_ignores_play_count_limit(actor.player_id, definition)
	if play_limit > 0 and _get_grouped_play_count(actor, definition) >= play_limit and (use_limit_weapon_definition == null or not use_limit_weapon_definition.ignores_play_count_limit(definition)) and not ignore_play_count_limit:
		return str(definition.get("play_limit_message", "本阶段使用次数已用尽。"))
	# 虚拟牌目标数量；只读取牌定义的基础上限，材料不属于最后一张实体手牌，不能触发方天画戟。
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode not in ["all_others", "all_players"]:
		var minimum_target_count: int = int(definition.get("min_targets", 0))
		var maximum_target_count: int = maxi(int(definition.get("max_targets", 0)) + int(rule_overrides.get("maximum_target_count_bonus", 0)), 0)
		if target_ids.size() < minimum_target_count or target_ids.size() > maximum_target_count:
			return "目标数量不符合卡牌规则。"
	# 已出现目标集合；虚拟牌与实体牌使用相同的重复目标和单目标合法性约束。
	var unique_targets: Dictionary = {}
	for target_id: int in target_ids:
		if unique_targets.has(target_id):
			return "不能重复指定同一目标。"
		unique_targets[target_id] = true
		# 单个目标错误；距离、存活状态和自身限制仍由统一目标规则判断。
		var target_error: String = _validate_target(actor, definition, target_id, target_ids, rule_overrides)
		if not target_error.is_empty():
			return target_error
	return ""


## 返回一张虚拟牌当前可以选择的目标；列表只用于界面预览与 AI 枚举，提交后仍必须调用 validate_virtual_use 复核完整组合。
func list_legal_virtual_targets(actor_id: int, definition_id: String, rule_overrides: Dictionary = {}) -> Array[int]:
	# 合法目标结果；无效玩家或配置不会开放任何可点击目标。
	var result: Array[int] = []
	# 虚拟牌使用者；目标规则需要读取其座次、装备和距离。
	var actor: PlayerState = state.get_player(actor_id)
	# 虚拟牌定义；当前丈八蛇矛使用普通【杀】定义。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if actor == null or definition.is_empty():
		return result
	# 虚拟牌整体合法性；阶段次数用尽时不再返回任何目标，转化技能按钮可据此实时熄灭。
	# 先用空目标做次数与阶段检查会失败（目标数不足），因此单独复用与 validate_virtual_use 相同的次数规则。
	if state.current_player_id != actor_id or state.current_phase != "play":
		return result
	var use_limit_weapon_definition: CardDefinition = _get_equipment_definition(actor, "weapon")
	var play_limit: int = int(definition.get("play_limit", 0))
	if play_limit > 0:
		play_limit += _skill_play_count_limit_bonus(actor.player_id, definition)
	var ignore_play_count_limit: bool = bool(rule_overrides.get("ignore_play_count_limit", false)) or _skill_ignores_play_count_limit(actor.player_id, definition)
	if play_limit > 0 and _get_grouped_play_count(actor, definition) >= play_limit and (use_limit_weapon_definition == null or not use_limit_weapon_definition.ignores_play_count_limit(definition)) and not ignore_play_count_limit:
		return result
	for target: PlayerState in state.players:
		if target.alive and not target.out_of_game and _validate_target(actor, definition, target.player_id, [target.player_id], rule_overrides).is_empty():
			result.append(target.player_id)
	return result


## 返回一张手牌当前可选的合法目标 ID，供 UI 高亮与 AI 枚举候选动作。
func list_legal_targets(actor_id: int, card: CardInstance) -> Array[int]:
	# 合法目标结果；自身目标模式只在当前行动者同时满足附加状态限制时返回行动者。
	var result: Array[int] = []
	if card == null:
		return result
	# 卡牌定义；不存在时不提供任何目标。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 目标模式；全体与特殊双目标牌由调用方进一步组合。
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode == "self" or target_mode == "self_wounded":
		# 自身目标校验结果；受伤自身目标需要在此复用完整状态校验，不能因快捷返回而允许满体力使用【桃】。
		var self_target_error: String = _validate_target(state.get_player(actor_id), definition, actor_id, [actor_id], {"card_color":card.get_color()})
		if self_target_error.is_empty():
			result.append(actor_id)
		return result
	for target: PlayerState in state.players:
		if not target.alive or target.out_of_game:
			continue
		if _validate_target(state.get_player(actor_id), definition, target.player_id, [target.player_id], {"card_color":card.get_color()}).is_empty():
			result.append(target.player_id)
	return result


## 把目标规范为规则行动顺序；全体模式自动展开，普通多目标按座次重排，借刀杀人保留两个目标的角色语义顺序。
func normalize_targets(actor_id: int, card: CardInstance, requested_targets: Array[int]) -> Array[int]:
	# 卡牌定义；用于判断是否需要自动展开全体目标。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 目标模式；全体模式会忽略请求数组并自动取得存活角色。
	var target_mode: String = str(definition.get("target_mode", ""))
	# 当前卡牌源码；拥有角色顺序语义的多目标牌可声明保留玩家提交顺序。
	var source_definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if (source_definition != null and source_definition.preserves_requested_target_order()) or (target_mode != "all_players" and target_mode != "all_others" and requested_targets.size() <= 1):
		return requested_targets.duplicate()
	# 规范后的目标数组；从使用者开始按行动顺序环形展开，避免固定从一号位或点击先后结算多目标牌。
	var result: Array[int] = []
	# 使用者座次数组索引；正常出牌时必定存在，防御性回退到一号位。
	var actor_index: int = 0
	for player_index: int in range(state.players.size()):
		if state.players[player_index].player_id == actor_id:
			actor_index = player_index
			break
	if target_mode == "all_players" or target_mode == "all_others":
		# 使用者状态；全体目标同样经过单目标规则与技能附加限制筛选，缺失使用者时返回空数组交由最终校验拒绝。
		var actor: PlayerState = state.get_player(actor_id)
		for seat_offset: int in range(state.players.size()):
			# 当前行动顺序玩家；使用者本人首先参与 all_players，all_others 则从其下家开始产生首个目标。
			var player: PlayerState = state.players[(actor_index + seat_offset) % state.players.size()]
			if not player.alive or player.out_of_game:
				continue
			if target_mode == "all_others" and player.player_id == actor_id:
				continue
			# 当前目标合法性；使用单目标数组检查独立资格，使【破风】等限制只移除不允许的角色，而不让一个非法角色否决整张群体锦囊。
			var target_error: String = _validate_target(actor, definition, player.player_id, [player.player_id], {"card_color":card.get_color()}) if actor != null else "行动玩家不存在。"
			if not target_error.is_empty():
				continue
			result.append(player.player_id)
		return result
	# 已追加请求标记；保留重复与无效 ID，使后续权威校验仍能返回精确错误而不会被重排静默丢弃。
	var appended_requests: Array[bool] = []
	appended_requests.resize(requested_targets.size())
	appended_requests.fill(false)
	for seat_offset: int in range(state.players.size()):
		# 当前行动顺序玩家；所有与其 ID 匹配的请求均按原数量追加。
		var player: PlayerState = state.players[(actor_index + seat_offset) % state.players.size()]
		for request_index: int in range(requested_targets.size()):
			if requested_targets[request_index] == player.player_id:
				result.append(requested_targets[request_index])
				appended_requests[request_index] = true
	for request_index: int in range(requested_targets.size()):
		if not appended_requests[request_index]:
			result.append(requested_targets[request_index])
	return result


## 检查单个目标是否合法；卡牌专属组合规则只验证可在当前信息下确定的部分。
func _validate_target(actor: PlayerState, definition: Dictionary, target_id: int, all_target_ids: Array[int], rule_overrides: Dictionary = {}) -> String:
	# 目标玩家状态；不存在或死亡的角色不是合法目标。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game:
		return "目标不存在、已经死亡或已移出游戏。"
	# 卡牌目标模式；决定身份、区域与状态限制。
	var target_mode: String = str(definition.get("target_mode", ""))
	# 当前卡牌源码；目标组合与效果前置条件等专属规则由对应卡牌文件校验。
	var source_definition: CardDefinition = GameDatabase.get_card_definition(str(definition.get("id", "")))
	if source_definition != null:
		var source_error: String = source_definition.validate_target_selection(self, actor, target_id, all_target_ids)
		if not source_error.is_empty():
			return source_error
		if source_definition.preserves_requested_target_order() and all_target_ids.size() > 1:
			return ""
	if target_mode in ["single_other", "single_other_with_cards", "weapon_holder"] and target_id == actor.player_id:
		return "该卡牌不能以自己为目标。"
	if target_mode in ["self", "self_wounded"] and target_id != actor.player_id:
		return "该卡牌只能以自己为目标。"
	if target_mode in ["wounded", "self_wounded"] and target.hp >= target.max_hp:
		return "目标未受伤。"
	if target_mode == "single_other_with_cards" and target.hand.is_empty() and target.equipment.is_empty() and target.judgment_area.is_empty():
		return "目标区域内没有牌。"
	if target_mode == "single_with_hand" and target.hand.is_empty():
		return "目标没有手牌。"
	if target_mode == "weapon_holder" and target.get_weapon() == null:
		return "首个目标没有装备武器。"

	# 距离限制；攻击范围与距离1均在此统一计算。
	var distance_limit: String = str(definition.get("distance_limit", "none"))
	var ignore_distance_limit: bool = bool(rule_overrides.get("ignore_distance_limit", false)) or _skill_ignores_card_distance_limit(actor.player_id, definition)
	if not ignore_distance_limit and distance_limit == "attack_range" and calculate_distance(actor.player_id, target_id) > get_attack_range(actor.player_id):
		return "目标不在攻击范围内。"
	if not ignore_distance_limit and distance_limit == "one" and calculate_distance(actor.player_id, target_id) > 1:
		return "目标距离大于1。"

	# 技能附加目标限制；只进行纯查询，不允许技能在校验阶段消耗次数、移动牌或创建选择。
	if skill_rule_provider != null and skill_rule_provider.has_method("validate_skill_card_target_selection"):
		var skill_target_error: String = str(skill_rule_provider.call("validate_skill_card_target_selection", actor.player_id, definition, target_id, all_target_ids))
		if not skill_target_error.is_empty():
			return skill_target_error
	# 目标持有技能的来牌限制；传入本次实体颜色，未知虚拟候选使用none并在最终时机继续复核。
	if skill_rule_provider != null and skill_rule_provider.has_method("validate_incoming_skill_card_target_selection"):
		var incoming_skill_error: String = str(skill_rule_provider.call("validate_incoming_skill_card_target_selection", target_id, actor.player_id, definition, str(rule_overrides.get("card_color", "none"))))
		if not incoming_skill_error.is_empty():
			return incoming_skill_error

	# 延时锦囊同名限制；同一判定区不能放置第二张同名延时锦囊。
	if bool(definition.get("delayed", false)):
		for delayed_card: CardInstance in target.judgment_area:
			if delayed_card.definition_id == str(definition.get("id", "")):
				return "目标判定区已有同名延时锦囊。"

	# 卡牌专属目标条件由定义文件的 validate_target_selection() 统一补充校验。
	return ""


## 返回当前玩家已经使用同一配置分组卡牌的总次数；阶段限制读取独立出牌阶段历史，其他限制继续读取本回合历史。
func _get_grouped_play_count(actor: PlayerState, definition: Dictionary) -> int:
	# 当前计数组；同组属性牌共享限制，空组回退当前卡牌 ID。
	var play_limit_group: String = str(definition.get("play_limit_group", definition.get("id", "")))
	# 当前限制作用域；phase 表示每个出牌阶段独立计算，默认 turn 保持现有每回合限制语义。
	var play_limit_scope: String = str(definition.get("play_limit_scope", "turn"))
	# 当前作用域对应的使用历史；独立历史避免额外出牌阶段清空【杀】次数时破坏回合级统计。
	var use_history: Dictionary = actor.play_phase_card_use_history if play_limit_scope == "phase" else actor.card_use_history
	# 已使用次数；逐项读取历史中的牌定义，新增同组牌无需修改规则服务。
	var used_count: int = 0
	for used_definition_id_variant: Variant in use_history.keys():
		# 历史卡牌定义 ID；无效旧存档条目会被安全忽略。
		var used_definition_id: String = str(used_definition_id_variant)
		var used_definition: Dictionary = GameDatabase.get_card(used_definition_id)
		var used_group: String = str(used_definition.get("play_limit_group", used_definition_id))
		if used_group == play_limit_group:
			used_count += int(use_history.get(used_definition_id, 0))
	return used_count


## 检查玩家指定装备 ID 是否位于任意装备槽。
func _has_equipment(player: PlayerState, definition_id: String) -> bool:
	for card_variant: Variant in player.equipment.values():
		# 当前装备实体牌；用于按配置 ID 判断装备技能。
		var card: CardInstance = card_variant as CardInstance
		if card.definition_id == definition_id:
			return true
	return false


## 返回玩家指定装备槽对应的卡牌源码定义；规则服务只读取定义钩子，不执行装备效果。
func _get_equipment_definition(player: PlayerState, slot: String) -> CardDefinition:
	if player == null or not player.equipment.has(slot):
		return null
	# 当前装备实体；自动扫描数据库按稳定定义 ID 返回源码对象。
	var card: CardInstance = player.equipment[slot] as CardInstance
	return GameDatabase.get_card_definition(card.definition_id)


## 汇总行动玩家当前已安装技能的次数解除规则；查询失败时保持基础限制。
func _skill_ignores_play_count_limit(actor_id: int, definition: Dictionary) -> bool:
	if skill_rule_provider == null or not skill_rule_provider.has_method("skill_ignores_play_count_limit"):
		return false
	return bool(skill_rule_provider.call("skill_ignores_play_count_limit", actor_id, definition))


## 汇总已安装技能对指定牌 play_limit 的额外次数加成；各技能返回值相加，负数按0处理。
func _skill_play_count_limit_bonus(actor_id: int, definition: Dictionary) -> int:
	if skill_rule_provider == null or not skill_rule_provider.has_method("skill_play_count_limit_bonus"):
		return 0
	return maxi(int(skill_rule_provider.call("skill_play_count_limit_bonus", actor_id, definition)), 0)


## 汇总行动玩家当前技能提供的卡牌距离解除规则；查询失败时保持卡牌基础限制。
func _skill_ignores_card_distance_limit(actor_id: int, definition: Dictionary) -> bool:
	if skill_rule_provider == null or not skill_rule_provider.has_method("skill_ignores_card_distance_limit"):
		return false
	return bool(skill_rule_provider.call("skill_ignores_card_distance_limit", actor_id, definition))
