extends CardDefinition

## 【五谷丰登】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "wugu",
		"original_name": "五谷丰登",
		"custom_name": "普世同谐",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "harvest",
		"nature": "normal",
		"target_mode": "all_players",
		"min_targets": 1,
		"max_targets": 99,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "亮出等同目标数的牌，每名目标依次获得其中一张，剩余牌置入弃牌堆。",
		"resolution_mode": "whole",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":0.5, "target_result":1.0, "draw":1.0, "multitarget":true, "beneficial":true},
		"ai_use_value": 5.0,
		"ai_beneficial": true,
	})


## 执行【五谷丰登】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	# 亮牌是公共实体登记，不包含玩家失去或获得；后续选择、无懈、获得和回收由同一规则内容持有。
	var revealed_cards: Array[CardInstance] = resolver.host.reveal_top_cards(target_ids.size())
	# 原展示实体身份；选择与结算中只保存稳定UID。
	var revealed_uids: Array[int] = []
	# 固定公共展示牌面；实际取得后仅更新领取者，不删除历史牌位。
	var harvest_display_slots: Array[Dictionary] = []
	for revealed_card: CardInstance in revealed_cards:
		revealed_uids.append(revealed_card.uid)
		harvest_display_slots.append({"uid":revealed_card.uid, "card_data":revealed_card.to_dict(), "taken_by_player_id":-1})
	# 原目标顺序与展示快照；下一目标只在上一目标完整获得After后推进。
	var context: Dictionary = {"sequence_kind":"harvest", "parent_card_uid":card.uid, "actor_id":actor_id, "target_ids":target_ids.duplicate(), "target_index":0, "revealed_uids":revealed_uids, "harvest_display_slots":harvest_display_slots}
	_publish_harvest_display(resolver, context, int(target_ids[0]) if not target_ids.is_empty() else -1)
	resolver.host.run_rule_sequence([_next_target.bind(resolver)] as Array[Callable], context)
	return "pending"


## 每次只展开一名原目标；已离开处理区的展示实体不再作为候选，不补充新牌。
func _next_target(sequence: RuleStepSequence, resolver: Object) -> void:
	# 当前仍可分配的原展示身份；嵌套效果取得的牌会从本轮候选中自然消失。
	var remaining_uids: Array[int] = []
	for card_uid: int in sequence.context.revealed_uids:
		if resolver.find_processing_card(card_uid) != null:
			remaining_uids.append(card_uid)
	sequence.context["revealed_uids"] = remaining_uids
	# 原目标游标；无效目标只跳过一次，不按实时全场角色重建目标集合。
	var target_index: int = int(sequence.context.target_index)
	if target_index >= (sequence.context.target_ids as Array).size() or remaining_uids.is_empty():
		sequence.insert_steps([_remaining_timing.bind(resolver), _discard_remaining.bind(resolver), _finish_harvest.bind(resolver)])
		return
	sequence.context["target_index"] = target_index + 1
	sequence.context["current_target_id"] = int(sequence.context.target_ids[target_index])
	# 原当前目标代次；无懈或获得前置中换将后不向新角色发放收益。
	var target: PlayerState = resolver.state.get_player(int(sequence.context.current_target_id))
	if target == null or not target.alive or target.out_of_game:
		sequence.insert_steps([_next_target.bind(resolver)])
		return
	sequence.context["target_generation"] = target.character_generation
	_publish_harvest_display(resolver, sequence.context, target.player_id)
	sequence.insert_steps([_negate_target.bind(resolver), _choose_card.bind(resolver), _give_card.bind(resolver), _record_gain.bind(resolver), _next_target.bind(resolver)])


## 通用无懈结果槽只写最终奇偶；所有响应After完成后才进入展示牌选择。
func _negate_target(sequence: RuleStepSequence, resolver: Object) -> void:
	sequence.context["negated"] = resolver.host.resolve_trick_negation(int(sequence.context.actor_id), int(sequence.context.current_target_id), "wugu", {"parent_card_uid":int(sequence.context.parent_card_uid), "rule_negation_sequence_id":sequence.sequence_id})


## 当前角色仍为原武将且未被无懈时请求一张剩余牌；统一选择结果直接归属本序列。
func _choose_card(sequence: RuleStepSequence, resolver: Object) -> void:
	sequence.choice_response = null
	if bool(sequence.context.get("negated", false)):
		return
	# 原接收者；代次或生存资格变化时跳过本次收益。
	var target: PlayerState = resolver.state.get_player(int(sequence.context.current_target_id))
	if target == null or not target.alive or target.out_of_game or target.character_generation != int(sequence.context.target_generation):
		return
	# 原展示牌候选；处理区中已不存在的实体不进入请求。
	var candidates: Array[Dictionary] = resolver.host.get_processing_candidates(sequence.context.revealed_uids as Array[int])
	if candidates.is_empty():
		return
	# 原生统一选择路由；不再复制continue_choice及After手工续接。
	var context: Dictionary = {"kind":"harvest", "parent_card_uid":int(sequence.context.parent_card_uid), "rule_sequence_id":sequence.sequence_id, "choice_chooser_id":target.player_id}
	resolver.host.request_card_choice(target.player_id, "五谷丰登", "请选择一张展示牌获得", candidates, 1, 1, false, context)


## 先等待实际获得，再读取结果；取消前置不能提前从展示候选中移除实体。
func _give_card(sequence: RuleStepSequence, resolver: Object) -> void:
	sequence.effect_result = null
	if sequence.choice_response == null or not sequence.choice_response.confirmed or sequence.choice_response.card_ids.size() != 1:
		return
	# 原选定实体；其他效果已经移动时本次领取失败。
	var card: CardInstance = resolver.find_processing_card(int(sequence.choice_response.card_ids[0]))
	# 原角色；等待选择期间换将时不向新角色发牌。
	var target: PlayerState = resolver.state.get_player(int(sequence.context.current_target_id))
	if card != null and target != null and target.character_generation == int(sequence.context.target_generation):
		sequence.effect_result = resolver.host.give_revealed_card(target.player_id, card)


## 真实领取完整结束后更新固定展示牌位；失败且仍在处理区的牌继续供后续角色选择。
func _record_gain(sequence: RuleStepSequence, resolver: Object) -> void:
	if sequence.effect_result == null or sequence.effect_result.count <= 0:
		return
	# 实际领取身份；After中的再次移动不会抹去本次领取事实。
	var card_uid: int = int(sequence.effect_result.result.card_uid)
	_mark_harvest_slot_taken(sequence.context, card_uid, int(sequence.context.current_target_id))
	(sequence.context.revealed_uids as Array).erase(card_uid)
	_publish_harvest_display(resolver, sequence.context, int(sequence.context.current_target_id))


## 剩余牌通知可以插入选择和移牌；通知完整结束后才回收仍在处理区的原牌。
func _remaining_timing(sequence: RuleStepSequence, resolver: Object) -> void:
	if not (sequence.context.revealed_uids as Array).is_empty():
		sequence.wait_for_timing(resolver.host.emit_sequence_timing(sequence, "wuguRemained", int(sequence.context.actor_id), int(sequence.context.actor_id), -1, {"parent_card_uid":int(sequence.context.parent_card_uid), "remaining_card_uids":(sequence.context.revealed_uids as Array).duplicate()}))


## 将未领取原牌逐张接入同一内容；不在同步循环中越过弃牌After。
func _discard_remaining(sequence: RuleStepSequence, resolver: Object) -> void:
	# 回收步骤；父序列自动等待每张弃牌及其子效果。
	var steps: Array[Callable] = []
	for card_uid: int in sequence.context.revealed_uids:
		steps.append(_discard_one.bind(resolver, card_uid))
	sequence.insert_steps(steps)


## 公共处理区回收不构成角色弃置费用；已被子效果取得的牌不再处理。
func _discard_one(_sequence: RuleStepSequence, resolver: Object, card_uid: int) -> void:
	# 当前原展示实体；只在同步请求内临时使用引用。
	var card: CardInstance = resolver.find_processing_card(card_uid)
	if card != null:
		resolver.host.discard_revealed_card(card)


## 所有领取和剩余回收结束后交回父用牌，并清除公共展示。
func _finish_harvest(sequence: RuleStepSequence, resolver: Object) -> void:
	resolver.host.clear_public_card_choice_display("harvest")
	resolver.host.finish_processing_card(int(sequence.context.parent_card_uid))


## 更新固定展示牌位的领取归属；牌面快照始终保留，只有领取者 ID 会从-1变为实际玩家 ID。
func _mark_harvest_slot_taken(context: Dictionary, card_uid: int, player_id: int) -> void:
	# 公共展示牌位数组；深拷贝后写回上下文，防止异步请求副本与后续规则游标共享可变子数组。
	var display_slots: Array = (context.get("harvest_display_slots", []) as Array).duplicate(true)
	for slot_index: int in range(display_slots.size()):
		# 当前固定牌位；UID 匹配时只补充领取者，不移除牌位或覆盖原始牌面。
		var display_slot: Dictionary = display_slots[slot_index] as Dictionary
		if int(display_slot.get("uid", -1)) != card_uid:
			continue
		display_slot["taken_by_player_id"] = player_id
		display_slots[slot_index] = display_slot
		break
	context["harvest_display_slots"] = display_slots


## 发布全体玩家可见的五谷选牌快照；公开数据只包含固定牌位、当前选择者与领取归属。
func _publish_harvest_display(resolver: Object, context: Dictionary, active_player_id: int) -> void:
	# 公共展示快照；标题和提示属于长期规则语义，界面会根据玩家快照补充当前武将名。
	var display_data: Dictionary = {
		"kind":"harvest",
		"title":"五谷丰登",
		"prompt":"每名角色依次选择一张展示牌",
		"active_player_id":active_player_id,
		"slots":(context.get("harvest_display_slots", []) as Array).duplicate(true),
	}
	resolver.host.set_public_card_choice_display(display_data)
