class_name CardMovementService
extends RefCounted

## 实体牌唯一移动入口。它维护所有标准区域、牌面知识和 CardMoveEvent 历史，效果组件不得直接操作区域数组。

## 实体牌完成权威区域移动后的只读通知；控制器可据此统一生成表现与网络增量，不允许订阅者反向修改状态。
signal card_moved(move_data: Dictionary, card_data: Dictionary)

## 当前绑定的权威状态；每局必须创建新的服务实例，避免跨对局保留牌引用。
var state: GameState

## 下一个移牌事件稳定 ID；从1开始，供网络去重与回放关联。
var _next_move_id: int = 1

## 按“全局回合号:行动角色ID”索引的出牌阶段弃牌UID；每个桶只保存该回合真实进入弃牌堆的顺序，避免查询扫描整局移牌历史。
var _play_discard_uids_by_turn_player: Dictionary = {}

## 创建服务时绑定一局状态；服务不会复制或拥有 GameState 生命周期。
func _init(game_state: GameState) -> void:
	state = game_state
	_rebuild_play_discard_index()


## 移动单张实体牌并返回 CardMoveEvent；找不到牌或目的区域不合法时返回 null。
func move_card(card: CardInstance, to_zone: String, target_player_id: int = -1, reason: String = "move", event_id: int = -1, target_slot: String = "", visible_to: Array[int] = [], publish: bool = true) -> CardMoveEvent:
	if state == null or card == null or not _is_valid_zone(to_zone):
		return null
	if to_zone == "persistent_material" and (_find_material_parent(target_slot.to_int()) == null or target_slot.to_int() == card.uid):
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
	# 物理成员在恢复逻辑牌面前锁定；复合移牌仍在一个原子块内改变全部原实体。
	var physical_uids: Array[int] = card.get_physical_card_uids()
	# 离开持久规则后释放附属材料；延时牌进入判定处理区时继续保持同一绑定。
	var releasing: bool = not card.persistent_view_as.is_empty() and not card.retains_persistent_identity(to_zone)
	# 待释放原材料；副本避免实际移牌时修改迭代容器。
	var released_materials: Array[CardInstance] = []
	if releasing:
		released_materials.assign(card.persistent_materials)
	# 无材料持久效果离区即消失，不能进入手牌、弃牌堆或牌堆成为新实体。
	var actual_to_zone: String = "void" if releasing and bool(card.persistent_view_as.get("ephemeral", false)) else to_zone
	if releasing:
		card.clear_persistent_view_as()
	_remove_from_zone(card, source_zone, source_owner)
	_add_to_zone(card, actual_to_zone, target_player_id, target_slot)
	card.zone = actual_to_zone
	card.owner_id = target_player_id if actual_to_zone in ["hand", "equipment", "judgment", "wooden_ox", "persistent_material"] else -1
	_update_knowledge(card, actual_to_zone, target_player_id, visible_to)
	# 未释放的材料随主牌保持同一所有者；它们不额外占用装备栏或判定区条目。
	for material: CardInstance in card.persistent_materials:
		if not releasing:
			material.owner_id = card.owner_id
	# 已结束的视为展示来源；处理区和弃牌堆需要保留本次记录，其余稳定区域不能携带上一轮的一次性视为牌名。
	if actual_to_zone in ["draw_pile", "hand", "equipment", "judgment", "wooden_ox"]:
		card.clear_hand_view_as_presentation()
	# 移牌事件；所有字段在追加历史前已经完成权威区域变化。
	var move_uids: Array[int] = physical_uids.duplicate()
	if releasing and not physical_uids.is_empty():
		move_uids.assign([card.uid])
	# 当前主实体的真实移动；额外成员另有各自移牌历史，不在本记录中重复计数。
	var move: CardMoveEvent = CardMoveEvent.new(move_uids, source_zone, actual_to_zone, source_owner, target_player_id if actual_to_zone != "void" else -1, reason)
	move.move_id = _next_move_id
	_next_move_id += 1
	move.event_id = event_id
	move.target_slot = target_slot
	move.visible_to = visible_to.duplicate()
	# 移动发生时的回合快照；历史查询不得依赖之后已经推进的 GameState 当前游标。
	move.turn_number = state.turn_number
	# 移动发生时的回合角色；额外回合仍使用其真实行动角色 ID。
	move.turn_player_id = state.current_player_id
	# 移动发生时的阶段；【投狭】等机制只统计 play 阶段真实进入弃牌堆的实体。
	move.phase = state.current_phase
	# 移牌摘要；同一只读字典同时写入权威历史与增量信号，避免单张移动连续序列化两次。
	var move_data: Dictionary = move.to_dict()
	state.card_move_history.append(move_data)
	_index_play_discard_move(move_data)
	# 附属牌真实移牌记录；发布之前全部实体已经落定，规则订阅者不会看到半拆组状态。
	var released_moves: Array[CardMoveEvent] = []
	# 原附属成员的顺序索引；决定其在主材料下方的连续牌堆位次。
	for material_index: int in range(released_materials.size()):
		# 牌堆复合落位保持主材料的请求位次，其他成员依原顺序放在它下方，不能反插到主材料之上。
		var material_slot: String = "@%d" % (maxi(_parse_draw_pile_position(target_slot), 1) + material_index + 1) if to_zone == "draw_pile" else target_slot
		released_moves.append(move_card(released_materials[material_index], to_zone, target_player_id, reason, event_id, material_slot, visible_to, false))
	if publish:
		publish_move(move, card)
		for index: int in range(released_moves.size()):
			publish_move(released_moves[index], released_materials[index])
	return move


## 发布已提交的只读增量；复合操作可延后发布，不能以本端口再次修改区域。
func publish_move(move: CardMoveEvent, card: CardInstance) -> void:
	if move != null and card != null:
		card_moved.emit(move.to_dict(), card.to_dict())


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


## 返回指定回合与行动角色在出牌阶段进入弃牌堆的UID顺序副本；调用方仍需复核实体当前区域与花色。
func get_turn_play_discard_uids(turn_number: int, turn_player_id: int) -> Array[int]:
	# 索引键；使用稳定数字文本组合，避免嵌套字典在高频查询中重复创建中间容器。
	var index_key: String = _get_play_discard_index_key(turn_number, turn_player_id)
	# 只读桶；不存在时保持空数组，返回副本防止调用方污染后续规则查询。
	var indexed_uids: Array[int] = []
	indexed_uids.assign(_play_discard_uids_by_turn_player.get(index_key, []) as Array)
	return indexed_uids


## 返回指定回合索引桶的条目数；性能回归用它确认查询范围只随本回合移动量增长。
func get_turn_play_discard_indexed_count(turn_number: int, turn_player_id: int) -> int:
	# 索引键；与正式查询完全一致，诊断不会遍历历史或复制UID数组。
	var index_key: String = _get_play_discard_index_key(turn_number, turn_player_id)
	return (_play_discard_uids_by_turn_player.get(index_key, []) as Array).size()


## 从已有权威移牌历史重建出牌阶段弃牌索引；服务晚于状态创建或测试注入历史时只支付一次线性成本。
func _rebuild_play_discard_index() -> void:
	_play_discard_uids_by_turn_player.clear()
	_next_move_id = 1
	if state == null:
		return
	# 既有历史遍历项；服务恢复时逐条重建索引并恢复下一移牌事件ID。
	for move_variant: Variant in state.card_move_history:
		# 已有移牌摘要；索引只读取回合、行动角色、阶段、目标区域与UID，不复制完整字典。
		var move_data: Dictionary = move_variant as Dictionary
		_next_move_id = maxi(_next_move_id, int(move_data.get("move_id", 0)) + 1)
		_index_play_discard_move(move_data)


## 把单条符合条件的移牌摘要追加到对应索引桶；其他阶段与其他目标区域不会占用索引空间。
func _index_play_discard_move(move_data: Dictionary) -> void:
	if str(move_data.get("phase", "")) != "play" or str(move_data.get("to_zone", "")) != "discard_pile":
		return
	# 移动发生时的全局回合号；非正数表示开局配置或缺失历史，不属于回合内候选。
	var turn_number: int = int(move_data.get("turn_number", 0))
	# 移动发生时的行动角色；负数表示当时没有进行中的角色回合。
	var turn_player_id: int = int(move_data.get("turn_player_id", -1))
	if turn_number <= 0 or turn_player_id < 0:
		return
	# 当前索引桶键；同一回合同一行动角色的全部有效移动共享一条短数组。
	var index_key: String = _get_play_discard_index_key(turn_number, turn_player_id)
	# 当前索引桶；数组保留首次进入顺序，重复UID由最终候选查询按原规则去重。
	var indexed_uids: Array = _play_discard_uids_by_turn_player.get(index_key, []) as Array
	# 本次移动中的实体UID；批量摘要仍按原始顺序逐项写入同一桶。
	for card_uid_variant: Variant in move_data.get("card_ids", []) as Array:
		indexed_uids.append(int(card_uid_variant))
	_play_discard_uids_by_turn_player[index_key] = indexed_uids


## 生成出牌阶段弃牌索引的稳定键；仅内部使用，不进入快照或玩法状态。
func _get_play_discard_index_key(turn_number: int, turn_player_id: int) -> String:
	return "%d:%d" % [turn_number, turn_player_id]


## 返回实体牌实际所在区域；优先扫描数组而不是信任旧逻辑可能遗留的 zone 字段。
func _find_actual_zone(card: CardInstance) -> String:
	if state.draw_pile.has(card):
		return "draw_pile"
	if state.discard_pile.has(card):
		return "discard_pile"
	if state.processing_area.has(card):
		return "processing"
	if card.material_parent_uid >= 0:
		# 附属实体必须实际属于主牌容器；单独残留的父UID不能授权移动不存在的材料。
		var parent: CardInstance = _find_material_parent(card.material_parent_uid)
		if parent != null and parent.persistent_materials.has(card):
			return "persistent_material"
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
	return card.zone if card.zone != "persistent_material" and _is_valid_zone(card.zone) else ""


## 从实际区域数组移除实体牌；未知区域不会静默删除任何其他牌。
func _remove_from_zone(card: CardInstance, zone: String, owner_id: int) -> void:
	if zone == "draw_pile":
		state.draw_pile.erase(card)
	elif zone == "discard_pile":
		state.discard_pile.erase(card)
	elif zone == "processing":
		state.processing_area.erase(card)
	elif zone == "persistent_material":
		# 原主实体；附属牌只从自身绑定容器移除，不扫描并删除其他角色区域。
		var parent: CardInstance = _find_material_parent(card.material_parent_uid)
		if parent != null:
			parent.persistent_materials.erase(card)
		card.material_parent_uid = -1
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
## 摸牌堆支持“按位次插入”：`target_slot` 传 `@N`（N 为位次，含义见 MatchController 的
## DRAW_PILE_POSITION_* 常量）时插入到该位次；不传或传其它值时保持既有的“追加到牌堆顶”行为。
## 之所以复用 `target_slot` 而不是新增参数：既有调用点全部不传该参数，因此新增能力不会改变任何既有行为。
func _add_to_zone(card: CardInstance, zone: String, owner_id: int, target_slot: String) -> void:
	if zone == "draw_pile":
		var pile_position: int = _parse_draw_pile_position(target_slot)
		if pile_position <= 1:
			# 位次 1（或未指定位次）就是既有的“追加到数组末尾 = 牌堆顶”。
			state.draw_pile.append(card)
		else:
			# 位次 N：数组末尾为顶，因此插到距末尾 N-1 个元素的位置之前。
			var insert_index: int = maxi(state.draw_pile.size() - (pile_position - 1), 0)
			state.draw_pile.insert(insert_index, card)
	elif zone == "discard_pile":
		state.discard_pile.append(card)
	elif zone == "processing":
		state.processing_area.append(card)
	elif zone == "persistent_material":
		# 内部材料归属由主实体UID指定；调用者必须在原子提交前验证该主实体已登记。
		var parent: CardInstance = _find_material_parent(target_slot.to_int())
		if parent != null and parent != card:
			parent.persistent_materials.append(card)
			card.material_parent_uid = parent.uid
	else:
		var owner: PlayerState = state.get_player(owner_id)
		if owner == null:
			return
		if zone == "hand":
			owner.hand.append(card)
		elif zone == "wooden_ox":
			owner.wooden_ox_storage.append(card)
		elif zone == "judgment":
			# 判定区只追加不插入：数组保持**置入顺序**，界面因此按进入先后从左到右显示。
			# 结算顺序是它的逆序（最后置入者先判定），由 match_controller 的判定流程取数组末项实现，此处不得改为插入到首位。
			owner.judgment_area.append(card)
		elif zone == "equipment":
			owner.equipment[target_slot if not target_slot.is_empty() else "treasure"] = card


## 解析「牌堆位次」槽位标记；不是 `@N` 形式时返回 0，表示调用方没有指定位次。
## 标记格式固定为 `@` + 十进制位次，位次从 1 开始；非法或负数一律按 0（未指定位次）处理。
func _parse_draw_pile_position(target_slot: String) -> int:
	if not target_slot.begins_with("@") or target_slot.length() < 2:
		return 0
	var position_text: String = target_slot.substr(1)
	if not position_text.is_valid_int():
		return 0
	var position: int = position_text.to_int()
	return position if position >= 1 else 0


## 把一张**尚不属于任何区域**的新实体牌按位次放入摸牌堆，并返回移牌记录；失败返回 null。
## 与 move_card 的差别只有一个：本入口接受“还没有区域”的新牌（按定义刚创建的牌），
## 因此它不能走 move_card 的“必须已存在于某个区域”前置校验。
## `position` 为 1 表示牌堆顶第一张、2 表示第二张（数组末尾为顶）。
func insert_new_card_into_draw_pile(card: CardInstance, position: int, reason: String = "insert", event_id: int = -1) -> CardMoveEvent:
	if state == null or card == null or position < 1:
		return null
	# 新牌落位；此时牌还没有区域，因此没有“来源区域”可移除。
	card.zone = "draw_pile"
	card.owner_id = -1
	_add_to_zone(card, "draw_pile", -1, "@%d" % position)
	_update_knowledge(card, "draw_pile", -1, [] as Array[int])
	card.clear_hand_view_as_presentation()
	# 移牌事件；字段口径与 move_card 完全一致，保证表现层、回放与网络收到同一种增量。
	var move: CardMoveEvent = CardMoveEvent.new([card.uid], "", "draw_pile", -1, -1, reason)
	move.move_id = _next_move_id
	_next_move_id += 1
	move.event_id = event_id
	move.target_slot = "@%d" % position
	move.turn_number = state.turn_number
	move.turn_player_id = state.current_player_id
	move.phase = state.current_phase
	var move_data: Dictionary = move.to_dict()
	state.card_move_history.append(move_data)
	_index_play_discard_move(move_data)
	card_moved.emit(move_data, card.to_dict())
	return move


## 把一张**尚不属于任何区域**的新实体牌直接放入指定区域，并返回移牌记录；失败返回 null。
##
## 与 insert_new_card_into_draw_pile 的关系：两者都接受“还没有区域”的新牌（按定义刚创建的牌），
## 因此都不能走 move_card 的“必须已存在于某个区域”前置校验。本入口把落位区域参数化，
## 供运行时造牌把新牌直接放进手牌使用；牌堆位次那条通路继续由专用入口承担。
##
## 【参数】zone 必须是 _is_valid_zone 认可的标准区域；target_player_id 在 hand / wooden_ox 下表示持有者；
## target_slot 为空时按区域默认规则追加到末尾。visible_to 用于把牌面同时标记为若干观察者已知。
func insert_new_card_into_zone(card: CardInstance, zone: String, target_player_id: int = -1, reason: String = "insert", event_id: int = -1, target_slot: String = "", visible_to: Array[int] = []) -> CardMoveEvent:
	if state == null or card == null or not _is_valid_zone(zone):
		return null
	# 新牌落位；此时牌还没有区域，因此没有“来源区域”可移除。
	card.zone = zone
	card.owner_id = target_player_id if zone in ["hand", "wooden_ox"] else -1
	_add_to_zone(card, zone, target_player_id, target_slot)
	_update_knowledge(card, zone, target_player_id, visible_to)
	# 视为牌面展示残留必须清空：新牌从未经历过视为状态，保留旧记录会让牌面显示不存在的逻辑牌名。
	card.clear_hand_view_as_presentation()
	# 移牌事件；字段口径与 move_card / insert_new_card_into_draw_pile 完全一致，
	# 保证表现层、回放与网络收到同一种增量，不需要为造牌单独识别事件形状。
	var move: CardMoveEvent = CardMoveEvent.new([card.uid], "", zone, target_player_id, -1, reason)
	move.move_id = _next_move_id
	_next_move_id += 1
	move.event_id = event_id
	move.target_slot = target_slot
	move.turn_number = state.turn_number
	move.turn_player_id = state.current_player_id
	move.phase = state.current_phase
	var move_data: Dictionary = move.to_dict()
	state.card_move_history.append(move_data)
	_index_play_discard_move(move_data)
	card_moved.emit(move_data, card.to_dict())
	return move


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
	return zone in ["draw_pile", "hand", "equipment", "judgment", "processing", "wooden_ox", "persistent_material", "discard_pile", "void"]


## 定位主实体；仅扫描能够合法持有持久绑定的标准区域，不保存独立跨局索引。
func _find_material_parent(card_uid: int) -> CardInstance:
	for card: CardInstance in state.processing_area + state.draw_pile + state.discard_pile:
		if card.uid == card_uid:
			return card
	for player: PlayerState in state.players:
		for card: CardInstance in player.equipment.values() + player.judgment_area + player.hand + player.wooden_ox_storage:
			if card.uid == card_uid:
				return card
	return null
