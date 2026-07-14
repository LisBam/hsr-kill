class_name CardRuleService
extends RefCounted

## 卡牌使用合法性服务。只读取状态与配置，不执行效果或移动卡牌，可被 UI、AI 和服务器共同调用。

## 当前权威对局状态引用；由对局控制器创建服务时注入。
var state: GameState


## 绑定需要校验的权威状态；服务本身不拥有该状态的生命周期。
func _init(game_state: GameState) -> void:
	state = game_state


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


## 检查一条使用牌指令是否合法；返回空字符串表示通过，否则返回可直接显示的原因。
func validate_use(actor_id: int, card: CardInstance, target_ids: Array[int]) -> String:
	# 使用者状态；死亡、越权或不存在的玩家均不能行动。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null or not actor.alive:
		return "行动玩家不存在或已经死亡。"
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

	# 【杀】的基础次数限制；诸葛连弩使限制失效。
	if str(definition.get("effect_id", "")) == "slash" and actor.slash_count >= 1 and not _has_equipment(actor, "zhuge"):
		return "本阶段使用【杀】的基础次数已用尽。"
	# 【酒】每回合限一次；濒死自救由响应流程单独处理。
	if str(definition.get("effect_id", "")) == "wine" and actor.wine_used:
		return "本回合已经使用过【酒】。"

	# 规范化后应有的最少目标数；全体目标牌允许调用方传空数组并由核心自动展开。
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode != "all_others" and target_mode != "all_players":
		# 最少目标数；来自配置表并允许0目标的纯响应牌。
		var min_targets: int = int(definition.get("min_targets", 0))
		# 最多目标数；方天画戟的额外目标在专门分支中修正。
		var max_targets: int = int(definition.get("max_targets", 0))
		if card.definition_id == "sha" or card.definition_id == "sha_fire" or card.definition_id == "sha_thunder":
			if _has_equipment(actor, "fangtian") and card.zone == "hand" and actor.hand.size() == 1:
				max_targets += 2
		if target_ids.size() < min_targets or target_ids.size() > max_targets:
			return "目标数量不符合卡牌规则。"

	# 已出现的目标 ID；禁止重复指定同一目标。
	var unique_targets: Dictionary = {}
	for target_id: int in target_ids:
		if unique_targets.has(target_id):
			return "不能重复指定同一目标。"
		unique_targets[target_id] = true
		# 单个目标的合法性结果；任何目标失败都会拒绝整条指令。
		var target_error: String = _validate_target(actor, definition, target_id, target_ids)
		if not target_error.is_empty():
			return target_error
	return ""


## 返回一张手牌当前可选的合法目标 ID，供 UI 高亮与 AI 枚举候选动作。
func list_legal_targets(actor_id: int, card: CardInstance) -> Array[int]:
	# 合法目标结果；目标模式为自己时只包含行动者。
	var result: Array[int] = []
	if card == null:
		return result
	# 卡牌定义；不存在时不提供任何目标。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 目标模式；全体与特殊双目标牌由调用方进一步组合。
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode == "self":
		result.append(actor_id)
		return result
	for target: PlayerState in state.players:
		if not target.alive:
			continue
		if _validate_target(state.get_player(actor_id), definition, target.player_id, [target.player_id]).is_empty():
			result.append(target.player_id)
	return result


## 展开 all_players 与 all_others 目标模式，其他模式保持调用方给定顺序。
func normalize_targets(actor_id: int, card: CardInstance, requested_targets: Array[int]) -> Array[int]:
	# 卡牌定义；用于判断是否需要自动展开全体目标。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 目标模式；只有两种全体模式会忽略请求数组。
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode != "all_players" and target_mode != "all_others":
		return requested_targets.duplicate()
	# 展开后的目标数组；从使用者开始按行动顺序环形展开，避免固定从一号位结算群体牌。
	var result: Array[int] = []
	# 使用者座次数组索引；正常出牌时必定存在，防御性回退到一号位。
	var actor_index: int = 0
	for player_index: int in range(state.players.size()):
		if state.players[player_index].player_id == actor_id:
			actor_index = player_index
			break
	for seat_offset: int in range(state.players.size()):
		# 当前行动顺序玩家；使用者本人首先参与 all_players，all_others 则从其下家开始产生首个目标。
		var player: PlayerState = state.players[(actor_index + seat_offset) % state.players.size()]
		if not player.alive:
			continue
		if target_mode == "all_others" and player.player_id == actor_id:
			continue
		result.append(player.player_id)
	return result


## 检查单个目标是否合法；双目标联动规则只验证可在当前信息下确定的部分。
func _validate_target(actor: PlayerState, definition: Dictionary, target_id: int, all_target_ids: Array[int]) -> String:
	# 目标玩家状态；不存在或死亡的角色不是合法目标。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
		return "目标不存在或已经死亡。"
	# 卡牌目标模式；决定身份、区域与状态限制。
	var target_mode: String = str(definition.get("target_mode", ""))
	# 当前效果 ID；借刀杀人需要分别解释第一与第二目标。
	var effect_id: String = str(definition.get("effect_id", ""))
	if effect_id == "borrow_sword" and all_target_ids.size() == 2:
		if target_id == all_target_ids[0]:
			if target_id == actor.player_id or target.get_weapon() == null:
				return "借刀杀人的第一目标必须是装备武器的其他角色。"
			return ""
		if target_id == all_target_ids[1]:
			# 持刀者玩家 ID；来自目标数组首项。
			var weapon_holder_id: int = all_target_ids[0]
			if target_id == weapon_holder_id:
				return "被借刀者不能攻击自己。"
			if calculate_distance(weapon_holder_id, target_id) > get_attack_range(weapon_holder_id):
				return "第二目标不在被借刀者的攻击范围内。"
			return ""
	if target_mode in ["single_other", "single_other_with_cards", "weapon_holder", "single_with_hand"] and target_id == actor.player_id:
		return "该卡牌不能以自己为目标。"
	if target_mode == "wounded" and target.hp >= target.max_hp:
		return "目标未受伤。"
	if target_mode == "single_other_with_cards" and target.hand.is_empty() and target.equipment.is_empty() and target.judgment_area.is_empty():
		return "目标区域内没有牌。"
	if target_mode == "single_with_hand" and target.hand.is_empty():
		return "目标没有手牌。"
	if target_mode == "weapon_holder" and target.get_weapon() == null:
		return "首个目标没有装备武器。"

	# 距离限制；攻击范围与距离1均在此统一计算。
	var distance_limit: String = str(definition.get("distance_limit", "none"))
	if distance_limit == "attack_range" and calculate_distance(actor.player_id, target_id) > get_attack_range(actor.player_id):
		return "目标不在攻击范围内。"
	if distance_limit == "one" and calculate_distance(actor.player_id, target_id) > 1:
		return "目标距离大于1。"

	# 延时锦囊同名限制；同一判定区不能放置第二张同名延时锦囊。
	if bool(definition.get("delayed", false)):
		for delayed_card: CardInstance in target.judgment_area:
			if delayed_card.definition_id == str(definition.get("id", "")):
				return "目标判定区已有同名延时锦囊。"

	# 借刀杀人的第二目标必须是首目标攻击范围内的合法其他角色。
	return ""


## 检查玩家指定装备 ID 是否位于任意装备槽。
func _has_equipment(player: PlayerState, definition_id: String) -> bool:
	for card_variant: Variant in player.equipment.values():
		# 当前装备实体牌；用于按配置 ID 判断装备技能。
		var card: CardInstance = card_variant as CardInstance
		if card.definition_id == definition_id:
			return true
	return false
