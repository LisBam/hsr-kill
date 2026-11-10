extends RefCounted

## 响应消费结果对象；所有前置、材料移动和后置结束后才向调用者提供最终牌。

## 权威宿主；服务只在本局步骤中存活，不进入网络或存档。
var _host: Object

## 最终响应牌；只有completed为true时才能区分成功响应与明确失败。
var result: CardInstance

## 完成标志；false表示仍在等待子选择或时机，而不是放弃响应。
var completed: bool = false

## 无材料响应的独立费用；在原选择关闭后的本响应子树内等待，不占用客户端费用标志。
var _cardless_cost: RefCounted

## 本响应技能的完整声明生命周期；原请求已关闭，前置中的子询问不会覆盖原响应窗口。
var _skill_activation: RefCounted


## 绑定权威宿主。
func _init(host: Object) -> void:
	_host = host


## 启动统一响应内容；调用方通过自己的下一步骤读取本对象，不同步猜测返回值。
func begin(player_id: int, card_uid: int, patterns: Array[String], materials: Array[int], skill_id: String, response_context: Dictionary) -> void:
	# 稳定请求数据；原牌、技能、装备与父响应上下文都只保存可序列化字段。
	var context: Dictionary = {"sequence_kind":"response", "player_id":player_id, "selected_uid":card_uid, "patterns":patterns.duplicate(), "materials":materials.duplicate(), "response_skill_id":skill_id, "response_context":response_context.duplicate(true), "cancelled":false, "accepted":false, "material_index":0, "material_uids":[], "material_snapshots":[], "candidate":{}, "kind":"", "event_id":-1}
	# 每个可插入边界独占一步；费用和结果不会因恢复而重复执行。
	var steps: Array[Callable] = [_offer, _begin_skill_activation, _read_activation_and_cost, _read_offer, _before.bind("respondBefore"), _before.bind("respondBegin"), _start, _next_material, _accept, _main, _notify_skill, _notify_equipment, _end, _after, _complete]
	if _host.run_rule_sequence(steps, context) < 0:
		completed = true


## 收集响应方案；装备源码只声明材料方案，判定型装备仍通过自己的判定接收协议提供牌。
func _offer(sequence: RuleStepSequence) -> void:
	# 响应角色；不存在的角色不会创建前置窗口或移动任何牌。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if player == null or not player.alive or player.out_of_game:
		sequence.context["cancelled"] = true
		return
	sequence.context["generation"] = player.character_generation
	# 原响应参数；桥接身份只属于本次序列，装备异步判定不会直接恢复外层父牌。
	var response_context: Dictionary = sequence.context.response_context
	response_context["response_resolution_sequence_id"] = sequence.sequence_id
	sequence.context["action"] = _host.resolve_response_action(response_context, sequence.context.patterns)
	if response_context.has("equipment_response_plan"):
		sequence.context["equipment_response_plan"] = response_context.equipment_response_plan.duplicate(true)
		return
	# 无材料技能响应；费用由技能选择入口校验，消费通知仍等待标准响应前置。
	var cardless_id: String = str(response_context.get("selected_cardless_response_skill_id", ""))
	if not cardless_id.is_empty():
		# 当前技能实例；换将或失去技能后不能沿用旧候选。
		var skill: SkillDefinition = _host.get_skill_instance(player.player_id, cardless_id)
		# 技能提供的逻辑牌；不能信任客户端指定的牌名。
		var definition_id: String = str(response_context.get("selected_cardless_response_definition_id", ""))
		# 强类型响应模式；动态技能调用仍遵循公开接口的类型契约。
		var patterns: Array[String] = _host._string_array(sequence.context.patterns)
		if skill == null or not skill.can_use_effect() or skill.get_cardless_response_definition_id(patterns) != definition_id:
			sequence.context["cancelled"] = true
			return
		sequence.context["kind"] = "cardless"
		sequence.context["response_skill_id"] = cardless_id
		sequence.context["candidate"] = CardInstance.new(definition_id, "none", 0).to_dict()
		return
	# 被选的权威实体；普通响应不能把已离区的同名牌当作原候选。
	var location: Dictionary = _host._find_card_location_by_uid(int(sequence.context.selected_uid))
	# 当前候选实体；只在此同步步骤读取，跨等待使用UID和快照。
	var card: CardInstance = location.get("card") as CardInstance
	if card == null or int(location.get("owner_id", -1)) != player.player_id:
		sequence.context["cancelled"] = true
		return
	if str(location.get("zone", "")) == "equipment":
		# 当前装备定义；装备可以提供判定响应或声明若干材料的转化响应。
		var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
		# 当前窗口允许的模式与材料；传入源码前转换为正式强类型数组。
		var patterns: Array[String] = _host._string_array(sequence.context.patterns)
		# 已选费用；装备源码再次复核数量与区域。
		var materials: Array[int] = _host._int_array(sequence.context.materials)
		if (_host._read_ignored_equipment_slots(response_context) as Array).has(_host._find_equipment_slot_for_card(player, card)):
			sequence.context["cancelled"] = true
			return
		if definition != null and definition.can_offer_equipment_response(_host, player.player_id, patterns):
			sequence.context["kind"] = "equipment"
			sequence.context["equipment_uid"] = card.uid
			# 判定可能暂停；最终异步结果写回本序列的equipment_response_card槽。
			var response: CardInstance = definition.consume_equipment_response(_host, player.player_id, card.uid, patterns, materials, response_context)
			if response != null:
				sequence.context["candidate"] = response.to_dict()
			return
	elif player.find_playable_card(card.uid) == null:
		sequence.context["cancelled"] = true
		return
	# 实体本身可以提供的模式；不匹配时必须由显式选择的技能进行转化。
	var direct_pattern: String = _host._get_provided_response_pattern(GameDatabase.get_card(card.definition_id))
	if (sequence.context.patterns as Array).has(direct_pattern) and player.find_playable_card(card.uid) != null:
		sequence.context["kind"] = "real"
		sequence.context["candidate"] = card.to_dict()
	else:
		# 显式转化技能；不自动挑选未被玩家声明的技能。
		var skill: SkillDefinition = _host.get_skill_instance(player.player_id, str(sequence.context.response_skill_id))
		# 技能接口模式数组；用于重新验证材料颜色与区域。
		var patterns: Array[String] = _host._string_array(sequence.context.patterns)
		if skill == null or not skill.can_use_effect() or not _host.can_use_acquired_skill(player.player_id, skill.get_id()) or not skill.can_convert_response_card(card, patterns):
			sequence.context["cancelled"] = true
			return
		sequence.context["kind"] = "converted"
		sequence.context["candidate"] = CardInstance.new(skill.get_converted_response_definition_id(card, patterns), card.suit, card.rank).to_dict()
	sequence.context["material_uids"] = [card.uid]
	sequence.context["material_snapshots"] = [card.to_dict()]
	sequence.context["was_hand_view_as"] = card.has_hand_view_as()


## 响应技能真正提交时启动声明生命周期；材料预览按钮不提前产生一套成功技能时机。
func _begin_skill_activation(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.cancelled) or str(sequence.context.kind) not in ["cardless", "converted"]:
		return
	# 原响应上下文；只由已接受选择和技能权威候选提供。
	var context: Dictionary = (sequence.context.response_context as Dictionary).duplicate(true)
	context["active_entry"] = "chooseToRespond"
	context["active_entries"] = ["chooseToRespond"]
	context["response_patterns"] = (sequence.context.patterns as Array).duplicate()
	if str(sequence.context.kind) == "converted":
		context["response_conversion_skill_ids"] = [str(sequence.context.response_skill_id)]
	_skill_activation = _host.begin_skill_activation(int(sequence.context.player_id), str(sequence.context.response_skill_id), context, str(sequence.context.kind) == "cardless")


## 前置与技能主体结束后才开始额外响应费用；失败声明不消费材料，也不启动成功响应。
func _read_activation_and_cost(sequence: RuleStepSequence) -> void:
	if str(sequence.context.kind) not in ["cardless", "converted"]:
		return
	if _skill_activation == null or not _skill_activation.completed or not _skill_activation.success or not _valid(sequence):
		sequence.context.cancelled = true
		return
	if str(sequence.context.kind) == "cardless":
		# 原技能实例；声明After换将后不能向新武将支付旧响应费用。
		var skill: SkillDefinition = _host.get_skill_instance(int(sequence.context.player_id), str(sequence.context.response_skill_id))
		_cardless_cost = skill.begin_cardless_response_cost(_host._string_array(sequence.context.patterns), sequence.context.response_context)


## 读取装备异步结果或材料方案，再建立所有响应共享的生命周期数据。
func _read_offer(sequence: RuleStepSequence) -> void:
	if str(sequence.context.kind) == "cardless":
		# 原技能；费用After换将或失效后不能向新武将提交旧响应。
		var skill: SkillDefinition = _host.get_skill_instance(int(sequence.context.player_id), str(sequence.context.response_skill_id))
		if skill == null or not _valid(sequence) or not skill.is_cardless_response_cost_satisfied(_cardless_cost):
			sequence.context.cancelled = true
			return
	if sequence.context.has("equipment_response_plan"):
		# 装备源码声明的材料方案；消费仍发生在respond前置之后。
		var plan: Dictionary = sequence.context.equipment_response_plan
		sequence.context["kind"] = "equipment_materials"
		sequence.context["equipment_uid"] = int(plan.equipment_uid)
		sequence.context["candidate"] = (plan.candidate as Dictionary).duplicate(true)
		sequence.context["material_uids"] = (plan.material_uids as Array).duplicate()
		sequence.context["material_snapshots"] = (plan.material_snapshots as Array).duplicate(true)
		sequence.context["presentation_faces"] = (plan.presentation_faces as Array).duplicate(true)
		sequence.context["log_message"] = str(plan.log_message)
	elif sequence.context.has("equipment_response_card"):
		sequence.context["candidate"] = (sequence.context.equipment_response_card as Dictionary).duplicate(true)
	if (sequence.context.candidate as Dictionary).is_empty():
		sequence.context["cancelled"] = true
		return
	# 当前逻辑响应牌定义；所有入口都必须最终提供请求允许的牌型。
	var definition_id: String = str(sequence.context.candidate.get("definition_id", ""))
	# 响应标签；费用方案不能绕过父请求的模式校验。
	var pattern: String = _host._get_provided_response_pattern(GameDatabase.get_card(definition_id))
	if not (sequence.context.patterns as Array).has(pattern):
		sequence.context["cancelled"] = true
		return
	sequence.context["pattern"] = pattern
	# 计划物理材料；选中条目保持独立，不能把附属成员追加进逐条消费游标后再次扣除。
	var physical_material_uids: Array[int] = []
	# 每个选中条目的原快照；持久装备可以包含多份物理成员。
	for material: Dictionary in sequence.context.material_snapshots as Array:
		# 当前展开实体；只保存稳定UID，不把字典引用带入响应事实。
		for physical: Dictionary in CardInstance.get_physical_card_data(material):
			physical_material_uids.append(int(physical.uid))
	sequence.context["physical_material_uids"] = physical_material_uids
	sequence.context["consumed_material_uids"] = []
	sequence.context["timing_data"] = {"card_uid":int(sequence.context.selected_uid), "card_id":definition_id, "response_pattern":pattern, "response_action":sequence.context.action}
	if str(sequence.context.kind) != "real":
		sequence.context.timing_data["virtual"] = true
		sequence.context.timing_data["skill_id"] = str(sequence.context.response_skill_id)
		sequence.context.timing_data["material_card_uids"] = physical_material_uids.duplicate()


## 原角色仍有效才允许提交费用；已提交后的事实通知不因角色随后死亡而回滚。
func _valid(sequence: RuleStepSequence) -> bool:
	# 当前响应者；禁止旧窗口使用新武将的手牌或技能。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if bool(sequence.context.cancelled) or player == null or not player.alive or player.out_of_game or player.character_generation != int(sequence.context.get("generation", -1)):
		return false
	if bool(sequence.context.accepted):
		return true
	if not str(sequence.context.response_skill_id).is_empty():
		# 未提交费用前重新检查技能；丢失或失效的旧转化入口不能继续花费材料。
		var skill: SkillDefinition = _host.get_skill_instance(player.player_id, str(sequence.context.response_skill_id))
		if skill == null or not skill.can_use_effect():
			return false
	if str(sequence.context.kind) in ["equipment", "equipment_materials"]:
		# 装备响应在等待期间被移走时失效；材料转化不能仅凭旧装备UID继续。
		var equipment: CardInstance = _host._find_owned_virtual_material(player.player_id, int(sequence.context.get("equipment_uid", -1)))
		if equipment == null or not player.equipment.values().has(equipment):
			return false
	return true


## 每个修改窗口结束后回读原事件，异步取消不会被派发时的快照覆盖。
func _read_before(sequence: RuleStepSequence) -> void:
	if sequence.waiting_event == null:
		return
	sequence.context["timing_data"] = sequence.waiting_event.data.duplicate(true)
	if sequence.waiting_event.cancelled or sequence.waiting_event.neutralized:
		sequence.context["cancelled"] = true
	sequence.waiting_event = null


## respondBefore与respondBegin各自完整等待，未通过时不能移动实体或统计响应。
func _before(sequence: RuleStepSequence, timing_name: String) -> void:
	_read_before(sequence)
	if _valid(sequence):
		_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.player_id), int(sequence.context.player_id), -1, sequence.context.timing_data)


## 所有前置结束后创建稳定响应父记录，费用移牌和后续通知都关联此身份。
func _start(sequence: RuleStepSequence) -> void:
	_read_before(sequence)
	if not _valid(sequence):
		sequence.context["cancelled"] = true
		return
	sequence.context["event_id"] = _host._record_runtime_event("respond", "response", {"player_id":sequence.context.player_id, "response_pattern":sequence.context.pattern, "card_uid":sequence.context.selected_uid, "material_card_uids":sequence.context.physical_material_uids.duplicate(), "response_action":sequence.context.action}, {"responded":true, "response_action":sequence.context.action})
	sequence.context.timing_data["respond_event_id"] = int(sequence.context.event_id)


## 只安排下一张材料的完整失牌、展示和回收，后续材料与响应主体均在其后等待。
func _next_material(sequence: RuleStepSequence) -> void:
	if not _valid(sequence) or int(sequence.context.material_index) >= (sequence.context.material_uids as Array).size():
		return
	# 当前材料序号；在回调前推进，恢复不能再次消费。
	var index: int = int(sequence.context.material_index)
	sequence.context["material_index"] = index + 1
	# 当前材料身份；所有前置等待后按原角色和区域重新查询。
	var uid: int = int(sequence.context.material_uids[index])
	if _host._find_owned_virtual_material(int(sequence.context.player_id), uid) == null:
		sequence.context["cancelled"] = true
		return
	# 单张费用服务；对象被插入步骤持有至移牌结果完成。
	var movement: CardMoveResolutionService = CardMoveResolutionService.new(_host)
	sequence.insert_steps([_after_loss.bind(index, movement), _discard_consumed_materials.bind(movement), _next_material])
	movement.begin(sequence, uid, "processing", -1, str(sequence.context.action), int(sequence.context.event_id))


## 原子失牌通过才声明材料表现；装备离区触发结束后才回收。
func _after_loss(sequence: RuleStepSequence, index: int, movement: CardMoveResolutionService) -> void:
	if not bool(movement.result.get("success", false)):
		sequence.context["cancelled"] = true
		return
	(sequence.context.consumed_material_uids as Array).append_array(movement.result.get("card_uids", []) as Array)
	# 声明时原逻辑定义；展示游标局部调整和离区牌面复原都不能改变装备离区钩子来源。
	var source_definition_id: String = str((sequence.context.material_snapshots[index] as Dictionary).get("definition_id", ""))
	# 刚提交的材料；只用于本次同步展示与装备离区，不跨步骤持有实体。
	var card: CardInstance = _host._find_processing_card(int(movement.result.card_uid))
	if card == null:
		return
	if str(sequence.context.kind) in ["converted", "equipment_materials"]:
		# 虚拟材料展示；技能单材料沿用与装备多材料相同的牌面构造。
		var faces: Array = sequence.context.get("presentation_faces", [])
		if faces.is_empty():
			# 原材料快照；手牌视为已经在失牌提交时复原，不能从当前实体猜逻辑牌面。
			var originals: Array[CardInstance] = [CardInstance.from_dict(sequence.context.material_snapshots[index])]
			faces = ConvertedCardPresentation.build_faces(originals, str(sequence.context.candidate.definition_id))
			index = 0
		# 表现目标为空；动态宿主仍接收强类型目标数组。
		var targets: Array[int] = []
		if index < faces.size():
			_host._emit_card_presentation(faces[index], int(sequence.context.player_id), targets, "useCard", int(sequence.context.event_id), false)
	else:
		# 实体响应从持有者位置进入展示区，认领处理区弃牌动画。
		var targets: Array[int] = []
		_host._request_card_presentation(card, int(sequence.context.player_id), targets, "useCard", int(sequence.context.event_id), true)
	if str(movement.result.get("from_zone", "")) == "equipment" and _valid(sequence):
		_host._on_equipment_lost(_host.state.get_player(int(sequence.context.player_id)), card, true, source_definition_id)


## 费用拆组后回收全部实际进入处理区的原成员，不能只回收被选择的主UID。
func _discard_consumed_materials(sequence: RuleStepSequence, movement: CardMoveResolutionService) -> void:
	if not bool(movement.result.get("success", false)):
		return
	# 成员回收步骤；每张完整等待标准cardsDiscard窗口。
	var steps: Array[Callable] = []
	for card_uid: int in movement.result.get("card_uids", []):
		steps.append(_discard_material.bind(card_uid))
	sequence.insert_steps(steps)


## 消费是使用/打出动作；只有处理区收尾，不计入主动弃牌批次。
func _discard_material(sequence: RuleStepSequence, uid: int) -> void:
	if _host._find_processing_card(uid) == null:
		return
	# cardsDiscard保留原响应父记录，用于回放和表现对齐。
	var event_id: int = _host._record_runtime_event("cardsDiscard", "card_move", {"card_uids":[uid], "from_zone":"processing", "reason":"discard"}, {}, int(sequence.context.event_id))
	# 独立回收服务；取消后置通知不回滚此前成立的失牌。
	var movement: CardMoveResolutionService = CardMoveResolutionService.new(_host)
	movement.begin(sequence, uid, "discard_pile", -1, "discard", event_id)


## 所有材料完成后提交一次响应历史；失败响应没有主体或后置成功通知。
func _accept(sequence: RuleStepSequence) -> void:
	if not _valid(sequence):
		return
	sequence.context["accepted"] = true
	# 当前响应者；统计只在唯一提交步骤更新。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	sequence.context.timing_data["material_card_uids"] = (sequence.context.consumed_material_uids as Array).duplicate()
	player.response_history.append({"event_id":sequence.context.event_id, "response_pattern":sequence.context.pattern, "card_uid":int(sequence.context.selected_uid) if str(sequence.context.kind) == "real" else -1, "material_card_uids":sequence.context.consumed_material_uids.duplicate(), "skill_id":str(sequence.context.response_skill_id), "equipment_uid":int(sequence.context.get("equipment_uid", -1)), "response_action":sequence.context.action})


## 成功主体按动作类别发布useCard或respond；该窗口结束后才通知消费技能。
func _main(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.accepted):
		_host.emit_sequence_timing(sequence, _host._get_card_action_main_timing(str(sequence.context.action)), int(sequence.context.player_id), int(sequence.context.player_id), -1, sequence.context.timing_data, int(sequence.context.event_id))


## 成功费用通知只给仍属于原角色的技能，所有通知产生的子交互均先于响应尾部。
func _notify_skill(sequence: RuleStepSequence) -> void:
	if not bool(sequence.context.accepted):
		return
	# 已声明的逻辑响应牌；日志和语音不受材料复原影响。
	var card: CardInstance = _host._deserialize_optional_response_card(sequence.context.candidate)
	# 当前技能；角色失效后不把旧消费通知发给新实例。
	var skill: SkillDefinition = _host.get_skill_instance(int(sequence.context.player_id), str(sequence.context.response_skill_id)) if _valid(sequence) else null
	if skill != null and str(sequence.context.kind) == "cardless":
		skill.on_cardless_response_consumed(str(sequence.context.pattern), card.definition_id)
		skill.announce_activation({"response_pattern":sequence.context.pattern, "virtual_card_id":card.definition_id})
	elif skill != null and str(sequence.context.kind) == "converted":
		# 材料此刻可能被子技能合法移走，使用原稳定快照通知消费语义。
		var material: CardInstance = _host._find_card_location_by_uid(int(sequence.context.material_uids[0])).get("card") as CardInstance
		if material == null:
			material = CardInstance.from_dict(sequence.context.material_snapshots[0])
		skill.on_converted_response_consumed(material, str(sequence.context.pattern), card.definition_id)
		skill.announce_activation({"material_card_uid":material.uid, "response_pattern":sequence.context.pattern, "virtual_card_id":card.definition_id})
	# 日志角色；原角色死亡仍保留已经成立的使用/打出事实。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if not str(sequence.context.get("log_message", "")).is_empty():
		_host.add_log(str(sequence.context.log_message))
	elif player != null:
		_host.add_log(_host._build_card_action_log(player, card, str(sequence.context.action)))
	_host.request_card_voice(int(sequence.context.player_id), card.definition_id, _host._get_card_action_voice_mode(str(sequence.context.action)))


## 手牌来源装备触发按真实原材料快照判断，不把木牛牌源或装备费用误当普通手牌。
func _notify_equipment(sequence: RuleStepSequence) -> void:
	if not bool(sequence.context.accepted) or not _valid(sequence):
		return
	# 下一份装备消费通知；前份通知的子技能结束后才处理后续材料。
	var index: int = int(sequence.context.get("notify_material_index", 0))
	if index >= (sequence.context.material_snapshots as Array).size():
		return
	sequence.context["notify_material_index"] = index + 1
	# 原材料来源；是否普通手牌在移动前确定，当前实体继续保留移动后的实际状态。
	var snapshot: Dictionary = sequence.context.material_snapshots[index]
	# 原实体已被移出所有区域时才回退稳定快照，不伪造新的费用移动。
	var material: CardInstance = _host._find_card_location_by_uid(int(snapshot.uid)).get("card") as CardInstance
	if material == null:
		material = CardInstance.from_dict(snapshot)
	sequence.insert_steps([_notify_equipment])
	_host._notify_equipment_card_consumed(int(sequence.context.player_id), material, str(snapshot.get("zone", "")) == "hand")


## 打出响应的End窗口；使用型响应保持原useCardAfter协议。
func _end(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.accepted) and str(sequence.context.action) != "use":
		_host.emit_sequence_timing(sequence, "respondEnd", int(sequence.context.player_id), int(sequence.context.player_id), -1, sequence.context.timing_data, int(sequence.context.event_id))


## 最后成功通知仍属于本响应，父效果必须等待其中的选择及子伤害。
func _after(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.accepted):
		_host.emit_sequence_timing(sequence, "useCardAfter" if str(sequence.context.action) == "use" else "respondAfter", int(sequence.context.player_id), int(sequence.context.player_id), -1, sequence.context.timing_data, int(sequence.context.event_id))


## 只有此处公开最终结果；真实实体保留对象身份，逻辑转化使用声明时的快照。
func _complete(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.accepted):
		if str(sequence.context.kind) == "real" and not bool(sequence.context.get("was_hand_view_as", false)):
			result = _host._find_card_location_by_uid(int(sequence.context.selected_uid)).get("card") as CardInstance
		if result == null:
			result = _host._deserialize_optional_response_card(sequence.context.candidate)
	completed = true
