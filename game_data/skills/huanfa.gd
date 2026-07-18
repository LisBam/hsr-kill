extends SkillDefinition

## 【焕发】技能源码。任意角色回合结束时，若其本回合使用过【桃/药】，持有者可令其执行额外出牌阶段。

## 当前轮是否已经成功发动；roundStart重置，确认但阶段登记失败时不消耗次数。
var _used_this_round: bool = false


## 写入技能静态信息；技能描述严格保持设计原文。
func _init() -> void:
	super({
		"id": "huanfa",
		"name": "焕发",
		"trigger": "phaseEnd",
		"ui_enabled": false,
		"description": "一名角色的回合结束时，若本回合内其使用过【药】，你可令其执行一个额外的出牌阶段。每轮限一次。",
	})


## 安装每轮次数重置与全局回合结束监听；额外回合的结束同样属于合法触发时机。
func install() -> void:
	subscribe_timing("roundStart", _on_round_start, "global")
	subscribe_timing("phaseEnd", _on_any_phase_end, "global")


## 新轮开始时恢复一次发动额度。
func _on_round_start(_event: RuleEvent) -> void:
	_used_this_round = false


## 检查回合角色本回合是否使用过【药】，并由娜塔莎决定是否给予额外出牌阶段。
func _on_any_phase_end(event: RuleEvent) -> void:
	if _used_this_round or not bool(host.call("has_used_card_this_turn", event.player_id, "tao")) or not bool(host.call("can_add_play_phase", event.player_id)):
		return
	request_card_selection("焕发", "是否令该角色执行一个额外的出牌阶段？", [], 0, 0, true, {"kind":"huanfa_confirm", "target_id":event.player_id, "ai_allow_confirm":true})


## 恢复焕发确认；阶段成功进入显式队列后才消费每轮次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "huanfa_confirm" or response == null:
		return false
	if response.confirmed and not _used_this_round:
		# 获得额外阶段的回合角色；等待期间死亡、离场或回合变化时核心端口会拒绝登记。
		var target_id: int = int(context.get("target_id", -1))
		if get_skill_player(target_id).addPlayPhase():
			_used_this_round = true
			announce_activation({"target_id":target_id})
			observe_identity_behavior([target_id], {"target_result":1.0})
	return true


## 评估当前角色的额外出牌收益，并在本轮后续存在更高价值持药友方时保留次数。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非焕发确认不改变通用选择评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "huanfa_confirm":
		return 0.0
	# 取消动作保持0分；确认只有严格正收益时才会被基础策略选中。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 当前回合角色；额外阶段价值乘娜塔莎对其的当前可感知态度。
	var target_id: int = int(context.get("target_id", -1))
	# 当前发动收益；正值表示立即使用本轮额度比取消更有利。
	var current_value: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) / 5.0 * _estimate_extra_play_phase_value(authoritative_snapshot, target_id)
	# 后续保留价值；只考虑本轮尚未行动、手中明确拥有【药】且对娜塔莎友好的角色。
	var future_value: float = _best_future_candidate_value(authoritative_snapshot, target_id, evaluator)
	return current_value - future_value


## 返回本轮当前角色之后、下一次roundStart之前的最佳持药友方额外阶段价值。
func _best_future_candidate_value(authoritative_snapshot: Dictionary, current_target_id: int, evaluator: Object) -> float:
	# 玩家快照数组；项目以数组顺序表达稳定座次，末位之后的0号位会开启新轮并重置技能。
	var players: Array = authoritative_snapshot.get("players", []) as Array
	# 当前角色座次索引；默认-1表示快照缺失该角色并直接返回零收益。
	var current_index: int = -1
	for index: int in range(players.size()):
		if int((players[index] as Dictionary).get("player_id", -1)) == current_target_id:
			current_index = index
			break
	if current_index < 0:
		return 0.0
	# 最佳未来收益；只扫描当前座次之后，不跨越新轮边界。
	var result: float = 0.0
	for index: int in range(current_index + 1, players.size()):
		# 当前后续角色快照；只读存活、手牌与武将配置。
		var player: Dictionary = players[index] as Dictionary
		# 当前后续角色稳定ID；正式范围为0至9。
		var player_id: int = int(player.get("player_id", -1))
		if not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)) or not _snapshot_has_medicine(player):
			continue
		# 娜塔莎对当前后续角色的可感知态度；正值才保留技能额度。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, player_id)
		if attitude > 0.0:
			result = maxf(result, attitude / 5.0 * _estimate_extra_play_phase_value(authoritative_snapshot, player_id))
	return result


## 判断AI权威快照中的角色是否明确持有至少一张【药】；药理赋予的临时牌名已进入实体序列化数据。
func _snapshot_has_medicine(player: Dictionary) -> bool:
	for card_variant: Variant in player.get("hand", []) as Array:
		if str((card_variant as Dictionary).get("definition_id", "")) == "tao":
			return true
	return false


## 估算指定角色执行额外出牌阶段的收益；通用手牌行动空间叠加技能声明的阶段价值。
func _estimate_extra_play_phase_value(authoritative_snapshot: Dictionary, target_id: int) -> float:
	# 目标角色快照；空字典表示目标不存在，额外阶段没有收益。
	var target: Dictionary = _snapshot_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return 0.0
	# 基础可用牌收益；至少保留1分，使空手但拥有无材料主动技能的角色仍可被合理评估。
	var result: float = 1.0 + minf(float(target.get("hand_count", 0)) * 0.7, 3.5)
	# 目标武将定义；技能可通过通用元数据声明额外出牌阶段价值。
	var character: Dictionary = GameDatabase.get_character(str(target.get("character_id", "")))
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		result += float(GameDatabase.get_skill(str(skill_id_variant)).get("ai_extra_play_phase_value", 0.0))
	return result


## 从权威快照读取指定玩家；不存在时返回空字典。
func _snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后原样返回只读字典。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
