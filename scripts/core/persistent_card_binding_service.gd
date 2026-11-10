class_name PersistentCardBindingService
extends RefCounted

## 持久虚拟牌的实体归属边界；逻辑代理只用于用牌，持久区域由原首材料承载规则身份。


## 原生虚拟用牌安装前读取其原材料，已安装实体则读取自身持久绑定；不重造或猜测实体UID。
static func physical_uids(host: Object, card: CardInstance) -> Array[int]:
	# 当前原生使用内容；只在临时逻辑代理仍负责本次声明时展开它的材料。
	var context: Dictionary = host._card_use_contexts.get(card.uid, {}) as Dictionary
	if bool(context.get("virtual_proxy", false)) and card.zone == "processing" and card.persistent_view_as.is_empty():
		# 强类型结果；调用方可以持有副本，不修改原生父事件上下文。
		var result: Array[int] = []
		result.assign(context.get("material_card_uids", []) as Array)
		return result
	return card.get_physical_card_uids()


## 仅在统一移牌服务已完成所有前置之后调用；整组区域事实落定后才发布只读增量。
static func install(host: Object, proxy: CardInstance, to_zone: String, player_id: int, reason: String, event_id: int, slot: String, visible_to: Array[int]) -> CardMoveEvent:
	# 原代理上下文；普通实体安装不进入本路径。
	var context: Dictionary = host._card_use_contexts.get(proxy.uid, {}) as Dictionary
	if not bool(context.get("virtual_proxy", false)) or not proxy.persistent_view_as.is_empty():
		return null
	# 原材料身份；所有实体必须仍在处理区，任何一份已被取得都拒绝整组安装。
	var material_uids: Array[int] = physical_uids(host, proxy)
	# 本次原实体；仅在原子块内持有引用，不写入规则上下文。
	var materials: Array[CardInstance] = []
	for card_uid: int in material_uids:
		# 当前材料；去重和全部校验发生在首次状态修改之前。
		var material: CardInstance = host._find_processing_card(card_uid)
		if material == null or material == proxy or materials.has(material) or not material.persistent_view_as.is_empty():
			return null
		materials.append(material)
	if materials.is_empty():
		proxy.persistent_view_as = {"ephemeral":true, "zone":to_zone}
		return host.card_movement.move_card(proxy, to_zone, player_id, reason, event_id, slot, visible_to)
	# 首原材料保留自身UID；逻辑牌面只在此持久生命周期中覆盖，离区时由移动服务恢复。
	var primary: CardInstance = materials[0]
	primary.set_persistent_view_as(proxy, to_zone)
	# 已提交但尚未发布的内部绑定记录；这些动作不建立第二套规则窗口。
	var binding_moves: Array[CardMoveEvent] = []
	for material_index: int in range(1, materials.size()):
		binding_moves.append(host.card_movement.move_card(materials[material_index], "persistent_material", player_id, "persistent_material_bind", event_id, str(primary.uid), [] as Array[int], false))
	# 主实体安装结果；绑定成员与代理清理均在其表现发布之前完成。
	var move: CardMoveEvent = host.card_movement.move_card(primary, to_zone, player_id, reason, event_id, slot, visible_to, false)
	# 临时逻辑代理归void；它绝不作为新实体进入手牌、弃牌堆或牌堆。
	var proxy_move: CardMoveEvent = host.card_movement.move_card(proxy, "void", -1, "virtual_persistent_bound", event_id, "", [] as Array[int], false)
	for material_index: int in range(binding_moves.size()):
		host.card_movement.publish_move(binding_moves[material_index], materials[material_index + 1])
	host.card_movement.publish_move(proxy_move, proxy)
	host.card_movement.publish_move(move, primary)
	return move
