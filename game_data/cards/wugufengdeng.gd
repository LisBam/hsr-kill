extends CardDefinition

## 【五谷丰登】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "wugu",
		"original_name": "五谷丰登",
		"custom_name": "星海赐福",
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
		"ai_use_value": 5.0,
		"ai_beneficial": true,
	})


## 执行【五谷丰登】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	# 初始展示牌；数量等于结算开始时的目标数，全部进入公共处理区。
	var revealed_cards: Array[CardInstance] = resolver.host.reveal_top_cards(target_ids.size())
	# 展示牌 UID；异步上下文只保存可序列化稳定 ID。
	var revealed_uids: Array[int] = []
	for revealed_card: CardInstance in revealed_cards:
		revealed_uids.append(revealed_card.uid)
	# 五谷结算上下文；target_index 指向下一名应获得展示牌的角色。
	var context: Dictionary = {"kind":"harvest", "parent_card_uid":card.uid, "actor_id":actor_id, "target_ids":target_ids.duplicate(), "target_index":0, "revealed_uids":revealed_uids}
	_process_choice_queue(resolver, context, false)
	return resolver.default_destination()


## 继续展示牌选择队列；人类请求暂停时保留全部剩余目标和展示牌 UID。
func _process_choice_queue(resolver: Object, context: Dictionary, deferred_resolution: bool) -> void:
	# 剩余展示牌 UID；每名成功选择者取得一张并从数组移除。
	var revealed_uids: Array[int] = []
	for uid_variant: Variant in context.get("revealed_uids", []) as Array:
		revealed_uids.append(int(uid_variant))
	# 初始目标数组；顺序由使用牌时的规则层确定。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	# 下一目标索引；恢复请求时从已选择角色之后继续。
	var target_index: int = int(context.get("target_index", 0))
	while target_index < target_ids.size() and not revealed_uids.is_empty() and not resolver.state.game_over:
		# 当前获得者 ID；每名角色从全部剩余展示牌中自主选择。
		var target_id: int = target_ids[target_index]
		# 当前目标无懈结果；专用恢复会把结果写回相同目标索引。
		var target_negated: bool = false
		if int(context.get("negation_resolved_target_index", -1)) == target_index:
			target_negated = bool(context.get("negation_resolved_result", false))
			context.erase("negation_resolved_target_index")
			context.erase("negation_resolved_result")
		else:
			# 五谷无懈恢复上下文；抵消只跳过当前角色的选牌资格。
			var negation_context: Dictionary = context.duplicate(true)
			negation_context["continuation_kind"] = "harvest_negation"
			negation_context["target_index"] = target_index
			negation_context["revealed_uids"] = revealed_uids.duplicate()
			target_negated = resolver.host.resolve_trick_negation(int(context.get("actor_id", -1)), target_id, "wugu", negation_context)
			if resolver.host.has_pending_card_choice():
				return
		if target_negated:
			target_index += 1
			continue
		# 当前展示候选；全部公开且仍位于公共处理区。
		var candidates: Array[Dictionary] = resolver.host.get_processing_candidates(revealed_uids)
		# 当前请求上下文；提交后需要先交牌，再推进到下一名目标。
		var request_context: Dictionary = context.duplicate(true)
		request_context["kind"] = "harvest"
		request_context["target_index"] = target_index
		request_context["revealed_uids"] = revealed_uids.duplicate()
		request_context["deferred_resolution"] = deferred_resolution
		# 当前角色选择结果；五谷要求且只允许选择1张剩余展示牌。
		var selected_uids: Array[int] = resolver.host.request_card_choice(target_id, "五谷丰登", "请选择一张展示牌获得", candidates, 1, 1, false, request_context)
		if resolver.host.has_pending_card_choice():
			return
		if not selected_uids.is_empty():
			# 被选展示牌；同步选择时仍需确认实体没有离开处理区。
			var chosen_card: CardInstance = resolver.find_processing_card(selected_uids[0])
			if chosen_card != null:
				resolver.host.give_revealed_card(target_id, chosen_card)
				revealed_uids.erase(selected_uids[0])
		target_index += 1
	for remaining_uid: int in revealed_uids:
		# 未被选择的展示牌；仍在处理区时逐张进入弃牌堆。
		var remaining_card: CardInstance = resolver.find_processing_card(remaining_uid)
		if remaining_card != null:
			resolver.host.discard_revealed_card(remaining_card)
	if deferred_resolution and not resolver.state.game_over:
		resolver.host.finish_processing_card(int(context.get("parent_card_uid", -1)))


## 恢复一名角色提交的展示牌选择，然后从下一目标继续队列。
func continue_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "harvest":
		return false
	if selected_uids.is_empty():
		return true
	# 当前目标数组；target_index 指向本次完成选择的角色。
	var target_ids: Array = context.get("target_ids", []) as Array
	# 当前目标索引；提交后递增以进入下一名角色。
	var target_index: int = int(context.get("target_index", 0))
	if target_index < 0 or target_index >= target_ids.size():
		return true
	# 被选展示牌；仍位于处理区时交入当前角色手牌。
	var chosen_card: CardInstance = resolver.find_processing_card(selected_uids[0])
	if chosen_card != null:
		resolver.host.give_revealed_card(int(target_ids[target_index]), chosen_card)
	# 剩余展示牌 UID；移除已获得实体并推进目标游标。
	var remaining_uids: Array = (context.get("revealed_uids", []) as Array).duplicate()
	remaining_uids.erase(selected_uids[0])
	context["revealed_uids"] = remaining_uids
	context["target_index"] = target_index + 1
	_process_choice_queue(resolver, context, true)
	return true


## 恢复五谷当前目标的无懈链；抵消结果只作用于当前目标索引。
func continue_negation(resolver: Object, context: Dictionary, final_negated: bool) -> bool:
	if str(context.get("continuation_kind", "")) != "harvest_negation":
		return false
	# 五谷恢复上下文；保留展示牌 UID、目标数组和目标索引。
	var harvest_context: Dictionary = context.duplicate(true)
	harvest_context["kind"] = "harvest"
	harvest_context["negation_resolved_target_index"] = int(context.get("target_index", 0))
	harvest_context["negation_resolved_result"] = final_negated
	_process_choice_queue(resolver, harvest_context, true)
	return true
