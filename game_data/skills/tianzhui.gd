extends SkillDefinition

## 【天坠】技能源码。出牌阶段可弃置一张锦囊牌，或在自身横置时重置自身，然后造成1点火属性伤害。

## 当前出牌阶段是否已经发动；每次 phaseUseBegin 重置，费用完整支付后设为 true。
var _used_this_play_phase: bool = false


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "tianzhui",
		"name": "天坠",
		"trigger": "active",
		"enable": "phaseUse",
		"ui_enabled": true,
		"description": "出牌阶段限一次，你可以弃置一张锦囊牌或将自身横置的武将牌竖置，然后对一名横置的角色造成1点火属性伤害。",
	})


## 订阅每个自身出牌阶段的开始时机，用于重置独立的阶段次数。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 仅在自己的出牌阶段、尚未发动且同时存在费用与横置目标时允许点击技能按钮。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者状态；自身横置时可不选择锦囊牌，否则必须有普通手牌区中的锦囊牌。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or _used_this_play_phase or host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	return not _get_linked_target_ids().is_empty() and (owner.chained or not _get_trick_hand_candidates().is_empty())


## 创建可选锦囊牌与必选横置目标的组合请求；自身横置时允许零张牌，否则恢复时拒绝零材料提交。
func activate(_context: Dictionary = {}) -> String:
	# 可弃置锦囊牌候选；只包含普通手牌，不允许用装备区、判定区或木牛“粮”支付。
	var candidates: Array[Dictionary] = _get_trick_hand_candidates()
	# 横置目标 ID；包括技能持有者自己，只要该角色当前处于连环状态。
	var target_ids: Array[int] = _get_linked_target_ids()
	request_card_target_selection("天坠", "请选择一张锦囊牌和一名横置角色；自身横置时可不选牌", candidates, target_ids, 0, 1, 1, 1, true, {"kind":"tianzhui_cost_target"})
	return ""


## 恢复组合选择并重新校验费用与目标；成功后先支付费用，再造成固定1点火属性伤害。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "tianzhui_cost_target" or response == null:
		return false
	if not response.confirmed or response.target_ids.size() != 1 or response.card_ids.size() > 1:
		return true
	# 当前目标；等待期间已经解除横置或死亡时不消耗费用与次数。
	var target: PlayerState = host.state.get_player(response.target_ids[0]) as PlayerState
	if target == null or not target.alive or not target.chained:
		return true
	if response.card_ids.size() == 1:
		# 选中的手牌；必须仍是普通手牌区中的锦囊牌。
		var owner: PlayerState = get_owner_skill_player().get_state()
		var cost_card: CardInstance = owner.find_hand_card(response.card_ids[0]) if owner != null else null
		if cost_card == null or str(GameDatabase.get_card(cost_card.definition_id).get("type", "")) != "trick":
			return true
		if not bool(host.call("discard_card_from_hand", owner_player_id, cost_card.uid)):
			return true
	else:
		# 零牌费用仅在自身仍横置时成立；重置失败时不发动技能。
		var owner_state: PlayerState = get_owner_skill_player().get_state()
		if owner_state == null or not owner_state.chained or not bool(host.call("set_player_linked", owner_player_id, false, owner_player_id, get_id())):
			return true
	_used_this_play_phase = true
	get_owner_skill_player().damage(1, get_skill_player(target.player_id), "fire")
	return true


## 向 AI 合法动作列表追加标准技能动作；实际牌与目标由技能选择请求统一决定。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if can_activate():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[]})


## 每个新的自身出牌阶段恢复一次发动额度，包括【再现】等效果产生的额外出牌阶段。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 返回普通手牌区中的全部锦囊牌候选；候选快照供统一选择面板与网络协议使用。
func _get_trick_hand_candidates() -> Array[Dictionary]:
	# 全部普通手牌候选；先由控制器生成标准可见快照，再按卡牌类型过滤。
	var hand_candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# 锦囊牌候选结果；保持原手牌顺序，方便玩家与 AI 获得一致选项。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in hand_candidates:
		# 候选牌面位于 card_data 子字典；本人手牌为可见候选，definition_id 可安全用于规则过滤。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(GameDatabase.get_card(str(card_data.get("definition_id", ""))).get("type", "")) == "trick":
			result.append(candidate)
	return result


## 返回当前全部横置存活角色 ID；“一名横置的角色”不排除技能持有者本人。
func _get_linked_target_ids() -> Array[int]:
	# 横置目标结果；沿用座次数组顺序，保证选择面板、AI和回放顺序稳定。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and player.chained:
			result.append(player.player_id)
	return result
