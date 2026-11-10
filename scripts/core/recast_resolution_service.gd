extends RefCounted

## 重铸的独立规则内容；逐张等待非弃置移牌，最后按实际成功张数统一补摸。

## 权威规则宿主；不写入稳定上下文或网络载荷。
var _host: Object

## 实际重铸成功张数；completed为true后作为最终费用结果读取。
var count: int = 0

## 实际重铸实体UID；不包括重复、取消或失效的材料。
var card_uids: Array[int] = []

## 整次重铸是否完成；包含补摸及其子时机，不在仅完成移牌时置位。
var completed: bool = false


## 绑定当前对局；每个实例只负责一次单张或多张重铸。
func _init(host: Object) -> void:
	_host = host


## 锁定原普通手牌UID，按原请求顺序去重；不能使用装备、粮或等待期间新增的替代牌。
func begin(player_id: int, selected_uids: Array[int], single_card_log: bool) -> void:
	# 原角色；重铸需要本人仍存活在场。
	var player: PlayerState = _host.state.get_player(player_id) if _host.state != null else null
	if player == null or not player.alive or player.out_of_game or _host.state.game_over:
		completed = true
		return
	# 稳定请求内容；日志牌名只保存字符串，不携带实体引用。
	var data: Dictionary = {"sequence_kind":"recast", "player_id":player_id, "generation":player.character_generation, "single_card_log":single_card_log, "log_names":{}, "requested_card_uids":[], "cancelled":false, "gain_cancelled":false}
	# 本次已选身份；同一实体最多尝试一次，不重试被取消的移牌。
	var seen: Array[int] = []
	# 内容步骤；每张实际结果结束后再记录，全部材料结束后才补摸。
	var steps: Array[Callable] = [_timing.bind("recastingLose"), _read_front.bind("cancelled")]
	# 本次选定身份；不在执行中修改原调用者数组。
	for card_uid: int in selected_uids:
		if seen.has(card_uid):
			continue
		seen.append(card_uid)
		steps.append(_move.bind(card_uid))
		steps.append(_record.bind(card_uid))
	data["requested_card_uids"] = seen.duplicate()
	steps.append(_timing.bind("recastingLost"))
	steps.append(_timing.bind("recast"))
	steps.append(_timing.bind("recastingGain"))
	steps.append(_read_front.bind("gain_cancelled"))
	steps.append(_draw)
	steps.append(_timing.bind("recastingGained"))
	steps.append(_complete)
	if _host.run_rule_sequence(steps, data) < 0:
		completed = true


## 两个动作前置可取消尚未提交的失牌或补摸；已完成移牌不回滚，后置取消只影响其自身处理器。
func _read_front(sequence: RuleStepSequence, flag: String) -> void:
	if sequence.waiting_event != null:
		sequence.context[flag] = sequence.waiting_event.cancelled or sequence.waiting_event.neutralized
		sequence.waiting_event = null


## 重铸专属窗口使用同一父序列；材料实际结束后报告成功实体，补摸After结束后才完成最后窗口。
func _timing(sequence: RuleStepSequence, timing_name: String) -> void:
	if bool(sequence.context.cancelled) or (timing_name != "recastingLose" and count <= 0) or (timing_name == "recastingGained" and bool(sequence.context.gain_cancelled)):
		return
	# 本次窗口的稳定事实；最早窗口为请求材料，后续窗口仅含实际成功材料。
	var data: Dictionary = {"card_uids":(sequence.context.requested_card_uids as Array).duplicate() if timing_name == "recastingLose" else card_uids.duplicate(), "count":(sequence.context.requested_card_uids as Array).size() if timing_name == "recastingLose" else count, "reason":"recast"}
	sequence.wait_for_timing(_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.player_id), int(sequence.context.player_id), -1, data))


## 原角色仍有效时才移动当前普通手牌；不提前take，不把重铸算作弃置或使用。
func _move(sequence: RuleStepSequence, card_uid: int) -> void:
	sequence.effect_result = null
	# 原角色当前状态；换将后不能消费新角色手牌。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if bool(sequence.context.cancelled) or player == null or not player.alive or player.out_of_game or player.character_generation != int(sequence.context.generation):
		return
	# 当前材料；仅在本步骤内读取实体，等待时只保存UID。
	var card: CardInstance = player.find_hand_card(card_uid)
	if card == null:
		return
	# 声明时牌名；实际成功后才记录，不因临时视为清理而丢失来源文案。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	sequence.context.log_names[card_uid] = GameSettings.resolve_instance_card_name(card.to_dict(), definition)
	sequence.effect_result = _host._begin_single_discard(card_uid, player.player_id, ["hand"] as Array[String], -2, "recast", -2, false)


## 只统计真实提交；重铸不发布cardsDiscardedBatchAfter，也不生成弃置日志。
func _record(sequence: RuleStepSequence, card_uid: int) -> void:
	if sequence.effect_result == null or sequence.effect_result.count <= 0:
		return
	count += 1
	card_uids.append(card_uid)
	if bool(sequence.context.single_card_log):
		_host.add_log("%s重铸了%s。" % [_host.format_player_log_name(int(sequence.context.player_id)), str(sequence.context.log_names.get(card_uid, "一张牌"))])


## 全部成功材料合计补摸一次；原角色死亡或换将后不向新角色补发旧请求收益。
func _draw(sequence: RuleStepSequence) -> void:
	if count <= 0 or bool(sequence.context.gain_cancelled):
		return
	# 原角色最新状态；移牌After可造成死亡或换将。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if not bool(sequence.context.single_card_log):
		_host.add_log("%s重铸了%d张牌。" % [_host.format_player_log_name(int(sequence.context.player_id)), count])
	if player != null and player.alive and not player.out_of_game and player.character_generation == int(sequence.context.generation):
		_host.draw(player.player_id, count)


## 补摸的After及全部子内容结束后标记最终完成。
func _complete(_sequence: RuleStepSequence) -> void:
	completed = true
