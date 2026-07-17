class_name CardMovementService
extends RefCounted

## 实体牌唯一移动入口。它维护所有标准区域、牌面知识和 CardMoveEvent 历史，效果组件不得直接操作区域数组。

## 实体牌完成权威区域移动后的只读通知；控制器可据此统一生成表现与网络增量，不允许订阅者反向修改状态。
signal card_moved(move_data: Dictionary, card_data: Dictionary)

## 当前绑定的权威状态；每局必须创建新的服务实例，避免跨对局保留牌引用。
var state: GameState

## 下一个移牌事件稳定 ID；从1开始，供网络去重与回放关联。
var _next_move_id: int = 1

## 创建服务时绑定一局状态；服务不会复制或拥有 GameState 生命周期。
func _init(game_state: GameState) -> void:
	state = game_state


## 移动单张实体牌并返回 CardMoveEvent；找不到牌或目的区域不合法时返回 null。
func move_card(card: CardInstance, to_zone: String, target_player_id: int = -1, reason: String = "move", event_id: int = -1, target_slot: String = "", visible_to: Array[int] = []) -> CardMoveEvent:
	if state == null or card == null or not _is_valid_zone(to_zone):
		return null
	if to_zone in ["hand", "equipment", "judgment", "wooden_ox"] and state.get_player(target_player_id) == null:
		return null
	# 移动前的稳定来源信息；区域字段可能已被旧代码修改，因此先以实际数组位置为准。
	var source_zone: String = _find_actual_zone(card)
	var source_owner: int = card.owner_id
	if source_zone.is_empty():
		return null
	# 同一实体在同一公开区域且持有者未改变时没有可记录的区域变化；拒绝这类重复请求，避免重复发出 card_moved 增量。
	# 例如重复处理 discard_pile -> discard_pile 会被表现层误认为新的弃牌，从而在中央动画落点凭空创建牌面。
	if source_zone == to_zone and source_owner == target_player_id:
		return null
	_remove_from_zone(card, source_zone, source_owner)
	_add_to_zone(card, to_zone, target_player_id, target_slot)
	card.zone = to_zone
	card.owner_id = target_player_id if to_zone in ["hand", "equipment", "judgment", "wooden_ox"] else -1
	_update_knowledge(card, to_zone, target_player_id, visible_to)
	# 移牌事件；所有字段在追加历史前已经完成权威区域变化。
	var move: CardMoveEvent = CardMoveEvent.new([card.uid], source_zone, to_zone, source_owner, target_player_id, reason)
	move.move_id = _next_move_id
	_next_move_id += 1
	move.event_id = event_id
	move.target_slot = target_slot
	move.visible_to = visible_to.duplicate()
	state.card_move_history.append(move.to_dict())
	card_moved.emit(move.to_dict(), card.to_dict())
	return move


## 按 UID 顺序移动多张实体牌；任意一张失败都会停止并返回已经完成的移牌记录。
func move_cards(cards: Array[CardInstance], to_zone: String, target_player_id: int = -1, reason: String = "move", event_id: int = -1, target_slot: String = "", visible_to: Array[int] = []) -> Array[CardMoveEvent]:
	# 已完成移牌列表；调用方可根据该列表构建动画队列或回滚提示。
	var result: Array[CardMoveEvent] = []
	for card: CardInstance in cards:
		var move: CardMoveEvent = move_card(card, to_zone, target_player_id, reason, event_id, target_slot, visible_to)
		if move == null:
			break
		result.append(move)
	return result


## 记录一次牌面公开；所有现存玩家可见者由调用方传入，-1 表示全场公开。
func reveal_card(card: CardInstance, viewer_ids: Array[int] = []) -> bool:
	if card == null:
		return false
	card.shown = true
	if viewer_ids.is_empty() and state != null:
		for player: PlayerState in state.players:
			if player.alive:
				if not card.known_to.has(player.player_id):
					card.known_to.append(player.player_id)
	else:
		for viewer_id: int in viewer_ids:
			if not card.known_to.has(viewer_id):
				card.known_to.append(viewer_id)
	card.private_owner_id = -1
	return true


## 返回实体牌实际所在区域；优先扫描数组而不是信任旧逻辑可能遗留的 zone 字段。
func _find_actual_zone(card: CardInstance) -> String:
	if state.draw_pile.has(card):
		return "draw_pile"
	if state.discard_pile.has(card):
		return "discard_pile"
	if state.processing_area.has(card):
		return "processing"
	for player: PlayerState in state.players:
		if player.hand.has(card):
			return "hand"
		if player.wooden_ox_storage.has(card):
			return "wooden_ox"
		if player.judgment_area.has(card):
			return "judgment"
		for slot_variant: Variant in player.equipment.keys():
			if player.equipment[slot_variant] == card:
				return "equipment"
	return card.zone if _is_valid_zone(card.zone) else ""


## 从实际区域数组移除实体牌；未知区域不会静默删除任何其他牌。
func _remove_from_zone(card: CardInstance, zone: String, owner_id: int) -> void:
	if zone == "draw_pile":
		state.draw_pile.erase(card)
	elif zone == "discard_pile":
		state.discard_pile.erase(card)
	elif zone == "processing":
		state.processing_area.erase(card)
	else:
		var owner: PlayerState = state.get_player(owner_id)
		if owner == null:
			return
		if zone == "hand":
			owner.hand.erase(card)
		elif zone == "wooden_ox":
			owner.wooden_ox_storage.erase(card)
		elif zone == "judgment":
			owner.judgment_area.erase(card)
		elif zone == "equipment":
			for slot_variant: Variant in owner.equipment.keys():
				if owner.equipment[slot_variant] == card:
					owner.equipment.erase(slot_variant)
					break


## 把实体牌追加到目标区域；装备槽由调用方指定，空槽默认使用 treasure 以保持可逆记录。
func _add_to_zone(card: CardInstance, zone: String, owner_id: int, target_slot: String) -> void:
	if zone == "draw_pile":
		state.draw_pile.append(card)
	elif zone == "discard_pile":
		state.discard_pile.append(card)
	elif zone == "processing":
		state.processing_area.append(card)
	else:
		var owner: PlayerState = state.get_player(owner_id)
		if owner == null:
			return
		if zone == "hand":
			owner.hand.append(card)
		elif zone == "wooden_ox":
			owner.wooden_ox_storage.append(card)
		elif zone == "judgment":
			owner.judgment_area.append(card)
		elif zone == "equipment":
			owner.equipment[target_slot if not target_slot.is_empty() else "treasure"] = card


## 更新实体牌的公开、私有和已知者信息；牌堆洗牌时清理弃牌区的临时知识由调用方控制。
func _update_knowledge(card: CardInstance, zone: String, target_player_id: int, visible_to: Array[int]) -> void:
	if not visible_to.is_empty():
		for viewer_id: int in visible_to:
			if not card.known_to.has(viewer_id):
				card.known_to.append(viewer_id)
	if zone in ["discard_pile", "processing", "judgment", "equipment"]:
		reveal_card(card)
	if zone == "hand" or zone == "wooden_ox":
		card.private_owner_id = target_player_id
		if target_player_id >= 0 and not card.known_to.has(target_player_id):
			card.known_to.append(target_player_id)
	else:
		card.private_owner_id = -1


## 校验所有标准区域名称；void 作为移出对局的回放区域保留但不写入当前状态数组。
func _is_valid_zone(zone: String) -> bool:
	return zone in ["draw_pile", "hand", "equipment", "judgment", "processing", "wooden_ox", "discard_pile", "void"]
