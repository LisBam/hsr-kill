extends SkillDefinition

## 【摄伏】技能源码。持有者每个全局回合内首次以自己使用的牌造成伤害后，令一名角色按该牌名字数从牌堆获得牌。

## 当前全局回合是否已经触发；每次phaseBefore重置，首次符合条件的伤害立即锁定额度。
var _used_this_turn: bool = false


## 写入锁定技静态信息；技能描述严格保持设计原文。
func _init() -> void:
	super({
		"id": "shefu",
		"name": "摄伏",
		"trigger": "damageSource",
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，当你于一回合内首次使用牌造成伤害后，你令一名角色从牌堆中获得一张牌名字数与此牌相同的牌。若该角色为目标角色，你弃置其装备区内的一张牌。",
	})


## 安装全局回合重置与持有者伤害来源监听。
func install() -> void:
	subscribe_timing("phaseBefore", _on_any_turn_before, "global")
	subscribe_timing("damageSource", _on_owner_damage_source, "source")


## 任意新回合开始时恢复首次伤害额度。
func _on_any_turn_before(_event: RuleEvent) -> void:
	_used_this_turn = false


## 首次由已使用卡牌造成伤害时锁定牌名字数与本次伤害目标，并创建不可取消的角色选择。
func _on_owner_damage_source(event: RuleEvent) -> void:
	if _used_this_turn or int(event.data.get("amount", 0)) <= 0:
		return
	# 实际使用该伤害牌的角色；决斗等效果的最终伤害来源可能与原使用者不同，不能用event.source_id替代。
	var card_user_id: int = int(event.data.get("card_user_id", event.source_id))
	if card_user_id != owner_player_id:
		return
	# 造成伤害的逻辑牌；技能伤害没有有效卡牌定义，不满足“使用牌造成伤害”。
	var card_id: String = str(event.data.get("card_id", ""))
	# 伤害牌原版名字数；0表示牌定义缺失或不是有效使用牌。
	# 实际查询优先读取规则名；属性【杀】都按一个汉字参与【摄伏】检索。
	var name_length: int = int(host.call("get_card_original_name_length", card_id))
	if name_length <= 0:
		return
	_used_this_turn = true
	# 合法获牌角色；锁定技目标选择不可取消，允许选择雪衣自己或本次伤害目标。
	var target_ids: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game:
			target_ids.append(player.player_id)
	if not target_ids.is_empty():
		request_target_selection("【摄伏】请选择一名角色", target_ids, 1, 1, false, {"kind":"sefu_gain_target", "name_length":name_length, "damage_target_id":event.target_id, "card_id":card_id})


## 恢复摄伏的获牌目标或后续装备弃置；等待期间实体失效时只跳过对应效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；区分获牌目标和后续装备弃置。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "sefu_gain_target":
		if not response.confirmed or response.target_ids.size() != 1:
			return true
		# 最终获牌目标稳定ID；锁定技请求正常恰好包含一名目标。
		var selected_target_id: int = response.target_ids[0]
		# 最终获牌目标状态；等待期间死亡或离场时跳过本目标效果。
		var selected_target: PlayerState = host.state.get_player(selected_target_id)
		if selected_target == null or not selected_target.alive or selected_target.out_of_game:
			return true
		announce_activation({"target_id":selected_target_id, "damage_target_id":int(context.get("damage_target_id", -1)), "name_length":int(context.get("name_length", 0))})
		host.call("gain_top_draw_card_by_name_length", selected_target_id, int(context.get("name_length", 0)), get_id())
		# 只有获牌角色仍是本次伤害目标时才进入装备弃置；没有装备时后续效果直接跳过。
		if selected_target_id == int(context.get("damage_target_id", -1)):
			# 伤害目标当前装备候选；只包含公开装备区实体。
			var equipment_candidates: Array[Dictionary] = host.call("get_equipment_candidates", owner_player_id, selected_target_id) as Array[Dictionary]
			if not equipment_candidates.is_empty():
				request_card_selection("摄伏", "请选择弃置目标装备区内的一张牌", equipment_candidates, 1, 1, false, {"kind":"sefu_discard_equipment", "target_id":selected_target_id})
		return true
	if choice_kind == "sefu_discard_equipment":
		if response.confirmed and response.card_ids.size() == 1:
			host.call("discard_selected_hand_equipment", int(context.get("target_id", -1)), response.card_ids)
		return true
	return false


## 评估摄伏获牌目标：可弃敌方高价值装备时优先原伤害目标，否则为低手牌友方补充对应牌类。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；保存步骤、原伤害目标和伤害牌名字数。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# AI选择负载；保存所选目标或装备UID。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 当前选择步骤；不同步骤使用独立评分模型。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "sefu_gain_target":
		# 获牌目标数组；锁定请求要求恰好一名角色。
		var targets: Array = payload.get("selected_target_ids", []) as Array
		if targets.size() != 1:
			return -20.0
		# 唯一获牌目标稳定ID；用于态度与装备后续判断。
		var target_id: int = int(targets[0])
		# 获牌目标权威快照；读取手牌、体力与装备公开状态。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		# 雪衣对获牌目标的可感知态度；正值表示友方。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		# 获得未知牌的基础收益；统一按1张牌换算，友方低手牌时再提高补牌需求。
		var score: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 1, 0) + maxf(3.0 - float(target.get("hand_count", 0)), 0.0) * maxf(attitude, 0.0) * 0.25
		# 伤害牌原版名字数；1和4分别应用防御牌与锦囊牌倾向。
		# AI与权威检索共用规则名字数，避免牌面属性前缀造成评分和结算分歧。
		var name_length: int = int(context.get("name_length", 0))
		# 一字牌多为基础防御与救援牌，残血友方获得时增加生存收益。
		if name_length == 1 and attitude > 0.0:
			score += float(maxi(int(target.get("max_hp", 0)) - int(target.get("hp", 0)), 0)) * 1.4
		# 四字牌多为锦囊，手牌较少且仍有行动机会的友方更容易转化为即时收益。
		if name_length == 4 and attitude > 0.0:
			score += 1.5 + maxf(2.0 - float(target.get("hand_count", 0)), 0.0) * 0.5
		# 选择本次伤害目标会追加装备弃置；敌方装备越多越有价值，友方装备越多越应避免。
		if target_id == int(context.get("damage_target_id", -1)):
			# 目标装备数量；每件按固定权重修正后续弃置价值。
			var equipment_count: int = (target.get("equipment", {}) as Dictionary).size()
			score -= attitude / 5.0 * float(equipment_count) * 2.5
		return score
	if choice_kind == "sefu_discard_equipment":
		# 所选装备UID；强制请求正常恰好一张。
		var selected_cards: Array = payload.get("selected_card_uids", []) as Array
		if selected_cards.size() != 1:
			return -20.0
		# 装备所属目标稳定ID；敌我态度决定取高价值还是低价值装备。
		var target_id: int = int(context.get("target_id", -1))
		# 所选装备保留价值；只用于AI决策，不改变实际装备效果。
		var card_value: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), target_id)
		# 敌方选择最高价值装备，友方被迫弃置时选择最低价值装备。
		return -evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) / 5.0 * card_value
	return 0.0


## 修正首次伤害牌AI；敌方原目标有装备或友方需要补牌时，提高尽早造成伤害触发摄伏的价值。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	if _used_this_turn or str(action.get("action_type", "")) != "use_card":
		return current_score
	# 当前使用牌定义；只有带伤害标签的牌能首次触发摄伏。
	var definition: Dictionary = GameDatabase.get_card(str(action.get("card_definition_id", "")))
	if not bool((definition.get("ai", {}) as Dictionary).get("damage", false)):
		return current_score
	# 修正后动作评分；首次伤害牌固定加1分再叠加敌方装备收益。
	var result: float = current_score + 1.0
	for target_variant: Variant in action.get("target_ids", []) as Array:
		# 当前动作目标稳定ID；用于读取公开装备与态度。
		var target_id: int = int(target_variant)
		# 当前动作目标快照；每件敌方装备增加触发价值。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) < 0.0:
			result += float((target.get("equipment", {}) as Dictionary).size()) * 1.2
	return result
