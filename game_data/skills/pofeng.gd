extends SkillDefinition

## 【破风】技能源码。结束阶段可弃一张手牌获得额外回合，并把该回合用牌目标限制为此前【杀】目标。

## 当前轮是否已经成功登记额外回合；roundStart重置，取消或登记失败不消耗额度。
var _used_this_round: bool = false

## 当前回合内持有者使用【杀】指定过的角色ID集合；键为稳定玩家ID，值固定为true。
var _slash_target_ids_this_turn: Dictionary = {}

## 已支付费用并等待下一次持有者回合开始时启用的目标集合；空字典表示没有待激活限制。
var _pending_restricted_target_ids: Dictionary = {}

## 当前破风额外回合实际允许指定的目标集合；仅在该额外回合内非空并参与纯目标校验。
var _active_restricted_target_ids: Dictionary = {}


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id": "pofeng",
		"name": "破风",
		"trigger": "phaseJieshuBegin",
		"ui_enabled": false,
		"description": "结束阶段，若你于本回合内使用【杀】指定过目标，你可以弃置一张手牌并进行一个额外的回合，本回合内你使用牌仅可指定你本回合内使用【杀】指定过的角色为目标。每轮限一次。",
	})


## 安装轮次重置、回合目标记录、结束阶段发动与额外回合限制启停时机。
func install() -> void:
	subscribe_timing("roundStart", _on_round_start, "global")
	subscribe_timing("phaseBefore", _on_owner_phase_before, "player", 100)
	subscribe_timing("useCardToTargeted", _on_owner_card_targeted, "source")
	subscribe_timing("phaseJieshuBegin", _on_owner_end_phase_begin, "player")
	subscribe_timing("phaseAfter", _on_owner_phase_after, "player", -100)


## 新轮开始时恢复一次发动额度；已激活的额外回合限制不因轮号变化被提前清除。
func _on_round_start(_event: RuleEvent) -> void:
	_used_this_round = false


## 持有者每次新回合开始时清空普通统计，并在存在待激活集合时开启破风额外回合限制。
func _on_owner_phase_before(_event: RuleEvent) -> void:
	_slash_target_ids_this_turn.clear()
	_active_restricted_target_ids.clear()
	if not _pending_restricted_target_ids.is_empty():
		_active_restricted_target_ids = _pending_restricted_target_ids.duplicate(true)
		_pending_restricted_target_ids.clear()


## 记录持有者本回合使用【杀】实际指定过的每名目标；重复目标只保存一次。
func _on_owner_card_targeted(event: RuleEvent) -> void:
	# 当前逻辑牌定义；普通、火与雷【杀】统一以effect_id=slash识别。
	var definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(definition.get("effect_id", "")) != "slash":
		return
	# 当前目标ID；只有仍在本次指定目标时机中的正式角色才进入集合。
	var target_id: int = event.target_id
	if target_id >= 0:
		_slash_target_ids_this_turn[target_id] = true


## 结束阶段满足目标事实、手牌费用与每轮额度时，询问弃置一张手牌发动破风。
func _on_owner_end_phase_begin(_event: RuleEvent) -> void:
	if _used_this_round or _slash_target_ids_this_turn.is_empty():
		return
	# 普通手牌候选；原文明确要求弃置手牌，木牛“粮”和装备牌不计入。
	var hand_candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	if hand_candidates.is_empty():
		return
	request_card_selection("破风", "请选择弃置一张手牌并进行额外回合", hand_candidates, 0, 1, true, {"kind":"pofeng_cost"})


## 恢复破风手牌费用；成功弃牌并登记额外回合后才消费每轮额度与保存目标集合。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "pofeng_cost" or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != 1 or _used_this_round or _slash_target_ids_this_turn.is_empty():
		return true
	# 当前费用UID；必须仍位于持有者普通手牌区。
	var card_uid: int = response.card_ids[0]
	# 技能持有者；无效、死亡或离场时不能支付费用或取得额外回合。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or owner.find_hand_card(card_uid) == null:
		return true
	# 限制目标稳定副本；费用与额外回合成功后写入，避免后续普通统计清空影响语义。
	var restricted_target_ids: Dictionary = _slash_target_ids_this_turn.duplicate(true)
	if not bool(host.call("discard_card_from_hand", owner_player_id, card_uid)):
		return true
	if not get_owner_skill_player().addPhase():
		return true
	_used_this_round = true
	_pending_restricted_target_ids = restricted_target_ids
	# 公开目标数组；用于技能表现、身份观察和回放，不暴露字典内部引用。
	var observed_target_ids: Array[int] = []
	for target_id_variant: Variant in restricted_target_ids.keys():
		observed_target_ids.append(int(target_id_variant))
	announce_activation({"cost_card_uid":card_uid, "restricted_target_ids":observed_target_ids.duplicate()})
	return true


## 持有者回合完成后清除当前限制；待激活集合只在原回合结束到额外回合开始之间保留。
func _on_owner_phase_after(_event: RuleEvent) -> void:
	_active_restricted_target_ids.clear()


## 破风额外回合内，所有有目标的牌只能指定已保存的【杀】目标；无目标牌不受影响。
func validate_card_target_selection(_card_definition: Dictionary, target_id: int, _all_target_ids: Array[int]) -> String:
	if _active_restricted_target_ids.is_empty() or _active_restricted_target_ids.has(target_id):
		return ""
	return "【破风】额外回合内只能指定此前使用【杀】指定过的角色为目标。"


## AI在已有敌方【杀】目标且手牌足以支撑额外回合时发动，并优先弃置最低价值手牌。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非破风费用选择不改变通用评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "pofeng_cost":
		return 0.0
	# 取消动作保持0分；确认必须选中一张手牌。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 限制目标中的最佳敌方收益；没有敌方目标时额外回合缺少有效攻击对象。
	var hostile_target_value: float = 0.0
	for target_id_variant: Variant in _slash_target_ids_this_turn.keys():
		# 当前已记录目标ID；负态度转化为正进攻价值。
		var target_id: int = int(target_id_variant)
		hostile_target_value = maxf(hostile_target_value, -evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id))
	# 已选费用牌价值；低价值手牌更适合作为额外回合门票。
	var selected_card_uids: Array = payload.get("selected_card_uids", []) as Array
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(selected_card_uids[0])) if selected_card_uids.size() == 1 else 8.0
	# 手牌数量提供额外行动空间；至少保留一张牌时额外回合才有稳定收益。
	var owner_snapshot: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	var hand_count: int = int(owner_snapshot.get("hand_count", (owner_snapshot.get("hand", []) as Array).size()))
	return hostile_target_value * 0.8 + maxf(float(hand_count - 1), 0.0) * 0.8 - material_value * 0.5
