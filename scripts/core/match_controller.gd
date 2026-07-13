class_name MatchController
extends Node

## 标准身份局权威控制器。它编排阶段与动作，并把具体合法性、卡牌效果、AI 和网络交给独立组件。

signal state_changed(snapshot: Dictionary)
signal log_added(message: String)
signal action_rejected(message: String)
signal match_finished(winner: String)
signal card_presentation_requested(card_data: Dictionary, actor_id: int, target_ids: Array[int])

## 默认牌堆 ID；可在检查器中替换为后续扩展牌堆，运行时通常无需动态修改。
@export var default_deck_id: String = "standard_161"

## 默认玩家人数；支持2至10，演示场景默认4人，运行时可在新开局前修改。
@export_range(2, 10, 1) var default_player_count: int = 4

## 人类本地玩家座次；默认0，设为 -1 可运行纯 AI 自动对局，开局后不应修改。
@export_range(-1, 9, 1) var local_human_player_id: int = 0

## AI 每次操作之间的展示延迟秒数；默认0.35便于观察，运行时可动态调快。
@export_range(0.0, 3.0, 0.05) var ai_action_delay_seconds: float = 0.35

## 单个 AI 出牌阶段最多执行的动作数；默认64用于防止扩展牌循环导致界面停滞。
@export_range(1, 256, 1) var max_ai_actions_per_turn: int = 64

## 当前权威对局状态；开局前为 null，外部模块应优先读取快照。
var state: GameState

## 身份规则服务；负责分配表、胜负与死亡奖惩类型。
var identity_rules: IdentityRules

## 卡牌合法性服务；每次开局绑定新状态实例。
var card_rules: CardRuleService

## 卡牌效果执行器；每次开局绑定当前控制器操作端口与新状态。
var effect_resolver: CardEffectResolver

## 规则触发总线组件；由场景子节点提供，技能可按优先级订阅。
var event_bus: RuleEventBus

## AI 调度组件；只负责策略映射与选择，不推进阶段。
var ai_coordinator: AICoordinator

## 通信网关组件；离线模式回环，LAN/REMOTE 模式交给外部传输适配器。
var network_gateway: NetworkGateway

## 对局随机数生成器；牌堆、身份与武将选择统一使用，便于未来记录种子回放。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 当前 AI 出牌阶段已执行动作数；开始新回合时清零。
var _ai_actions_this_turn: int = 0

## AI 延迟任务令牌；任何阶段切换都会递增，使旧的异步回调自动失效。
var _ai_drive_token: int = 0


## 绑定场景中的解耦组件并初始化身份规则服务。
func _ready() -> void:
	event_bus = get_node("RuleEventBus") as RuleEventBus
	ai_coordinator = get_node("AICoordinator") as AICoordinator
	network_gateway = get_node("NetworkGateway") as NetworkGateway
	identity_rules = IdentityRules.new()
	network_gateway.command_received.connect(_on_network_command_received)


## 创建并开始一局标准身份局；seed 为0时使用系统随机种子。
func start_match(player_count: int = -1, seed: int = 0) -> bool:
	# 实际玩家人数；未指定时使用检查器默认值，并限制在支持范围内。
	var actual_player_count: int = default_player_count if player_count < 0 else player_count
	if actual_player_count < 2 or actual_player_count > 10:
		action_rejected.emit("标准身份局仅支持2至10名玩家。")
		return false
	if not GameDatabase.validation_errors.is_empty():
		action_rejected.emit("数据配置校验失败：%s" % "；".join(GameDatabase.validation_errors))
		return false

	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	CardInstance._next_uid = 1
	state = GameState.new()
	state.match_id = "%d-%d" % [Time.get_unix_time_from_system(), _rng.randi()]
	state.deck_id = default_deck_id
	card_rules = CardRuleService.new(state)
	effect_resolver = CardEffectResolver.new(self, state)
	_ai_drive_token += 1
	_ai_actions_this_turn = 0
	ai_coordinator._policies.clear()

	_create_players(actual_player_count)
	_create_and_shuffle_deck()
	for player: PlayerState in state.players:
		draw_cards(player.player_id, 4, false)

	# 主公状态；标准身份局开局从主公座次开始首回合。
	var lord: PlayerState = _find_player_by_identity("lord")
	if lord == null:
		action_rejected.emit("身份配置缺少主公。")
		return false
	add_log("对局开始：%d名玩家，牌堆%d张。" % [actual_player_count, state.draw_pile.size()])
	_start_turn(lord.player_id)
	return true


## 接受来自人类、AI 或网络的统一行为指令；返回是否通过规则校验并执行。
func submit_action(action: PlayerAction) -> bool:
	if state == null or state.game_over:
		return _reject("当前没有可操作的进行中对局。")
	if action.actor_id != state.current_player_id:
		return _reject("行动者不是当前回合玩家。")

	if action.action_type == "use_card":
		# 行动者状态；前置检查已保证其存在且为当前玩家。
		var actor: PlayerState = state.get_player(action.actor_id)
		# 指令引用的手牌；不存在时由合法性服务返回明确原因。
		var card: CardInstance = actor.find_playable_card(action.card_uid)
		if card == null:
			return _reject("指定手牌不存在。")
		# 自动展开后的最终目标数组；全体目标牌由规则服务按座次生成。
		var target_ids: Array[int] = card_rules.normalize_targets(action.actor_id, card, action.target_ids)
		# 卡牌使用失败原因；空字符串表示合法。
		var validation_error: String = card_rules.validate_use(action.actor_id, card, target_ids)
		if not validation_error.is_empty():
			return _reject(validation_error)
		_execute_card_use(action.actor_id, card, target_ids)
	elif action.action_type == "recast_card":
		if not _execute_recast(action.actor_id, action.card_uid):
			return false
	elif action.action_type == "store_wooden_ox":
		if not _execute_wooden_ox_store(action.actor_id, action.card_uid, action.target_ids):
			return false
	elif action.action_type == "end_play":
		_end_play_phase(action.actor_id)
	else:
		return _reject("未知行为类型：%s" % action.action_type)

	state.action_sequence += 1
	_emit_state()
	if not state.game_over and state.current_phase == "play" and ai_coordinator.is_ai_controlled(state.current_player_id):
		_schedule_ai_action()
	return true


## 返回当前玩家可执行的全部基础动作，供 AI 决策与 UI 辅助使用。
func get_legal_actions(player_id: int) -> Array[Dictionary]:
	# 合法动作结果；每项均可直接转换为 PlayerAction。
	var result: Array[Dictionary] = []
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return result
	# 当前玩家状态；其手牌决定所有使用牌与重铸候选。
	var player: PlayerState = state.get_player(player_id)
	for card: CardInstance in player.get_playable_cards():
		# 当前卡牌定义；用于目标模式与 AI 展示字段。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		# 当前卡牌目标模式；决定候选目标组合的生成方式。
		var target_mode: String = str(definition.get("target_mode", ""))
		if target_mode == "response_only":
			continue
		if bool(definition.get("recast", false)):
			result.append({"action_type":"recast_card", "actor_id":player_id, "card_uid":card.uid, "target_ids":[], "card_definition_id":card.definition_id})
		if str(definition.get("effect_id", "")) == "borrow_sword":
			_append_borrow_sword_actions(result, player_id, card)
			continue
		if target_mode == "all_players" or target_mode == "all_others":
			_append_if_legal(result, player_id, card, [])
			continue
		# 当前卡牌所有单目标候选；铁索连环当前基础 AI 先使用单目标形式。
		var legal_targets: Array[int] = card_rules.list_legal_targets(player_id, card)
		for target_id: int in legal_targets:
			_append_if_legal(result, player_id, card, [target_id])
	if player_has_equipment(player_id, "muniu") and not player.wooden_ox_used:
		for card: CardInstance in player.hand:
			result.append({"action_type":"store_wooden_ox", "actor_id":player_id, "card_uid":card.uid, "target_ids":[], "card_definition_id":"muniu_store"})
	return result


## 返回指定卡牌与当前目标顺序的只读交互预览，供 UI 展示合法目标、步骤提示与确认状态。
func get_card_use_preview(player_id: int, card_uid: int, selected_target_ids: Array[int] = []) -> Dictionary:
	# 预览默认结果；任何不可操作状态都会返回明确原因且不暴露权威对象引用。
	var result: Dictionary = {
		"card_found": false,
		"can_submit": false,
		"validation_error": "当前卡牌不可用。",
		"legal_target_ids": [],
		"normalized_target_ids": [],
		"target_mode": "",
		"min_targets": 0,
		"max_targets": 0,
		"description": "",
	}
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return result
	# 行动玩家状态；只用于查找其手牌或木牛“粮”。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return result
	# 指定实体牌；UI 始终使用稳定 UID，不依赖手牌数组位置。
	var card: CardInstance = player.find_playable_card(card_uid)
	if card == null:
		return result
	# 卡牌定义；预览只返回界面需要的基础元数据。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 当前目标模式；用于 UI 决定是否自动选择自己或由核心展开全体目标。
	var target_mode: String = str(definition.get("target_mode", ""))
	# 规范化目标；全体目标牌由规则服务按存活座次自动展开。
	var normalized_targets: Array[int] = card_rules.normalize_targets(player_id, card, selected_target_ids)
	# 当前完整组合的规则校验结果；空字符串表示确认按钮可以提交。
	var validation_error: String = card_rules.validate_use(player_id, card, normalized_targets)
	# 下一步合法候选目标；候选会结合已有目标顺序验证，借刀杀人可正确区分第一与第二目标。
	var legal_target_ids: Array[int] = []
	for candidate: PlayerState in state.players:
		if not candidate.alive or selected_target_ids.has(candidate.player_id):
			continue
		# 候选目标顺序；把当前候选追加到已有选择末尾以保留顺序语义。
		var candidate_targets: Array[int] = selected_target_ids.duplicate()
		candidate_targets.append(candidate.player_id)
		# 候选完整校验结果；达到最少目标数后可直接使用完整校验。
		var candidate_error: String = card_rules.validate_use(player_id, card, candidate_targets)
		if candidate_error.is_empty():
			legal_target_ids.append(candidate.player_id)
			continue
		# 部分目标允许继续选择；单目标合法性由服务查询，双目标牌首目标也由该查询覆盖。
		if selected_target_ids.is_empty() and card_rules.list_legal_targets(player_id, card).has(candidate.player_id):
			legal_target_ids.append(candidate.player_id)
	result["card_found"] = true
	result["can_submit"] = validation_error.is_empty()
	result["validation_error"] = validation_error
	result["legal_target_ids"] = legal_target_ids
	result["normalized_target_ids"] = normalized_targets
	result["target_mode"] = target_mode
	result["min_targets"] = int(definition.get("min_targets", 0))
	result["max_targets"] = int(definition.get("max_targets", 0))
	result["description"] = str(definition.get("description", ""))
	return result


## 公开添加一条永久语义日志；UI、回放与调试器均可订阅同一信号。
func add_log(message: String) -> void:
	log_added.emit(message)


## 返回适合界面显示的一张实体牌描述，名称模式由全局配置决定。
func describe_card(card: CardInstance) -> String:
	if card == null:
		return "未知牌"
	# 实体牌定义；用于解析当前名称模式。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 点数字符串；11至13显示为J、Q、K，1显示为A。
	var rank_text: String = "" if card.rank <= 0 else str({1:"A", 11:"J", 12:"Q", 13:"K"}.get(card.rank, str(card.rank)))
	# 花色显示文本；保持短文本便于日志阅读。
	var suit_text: String = {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦", "none":"虚拟"}.get(card.suit, card.suit)
	return "%s%s %s" % [suit_text, rank_text, GameSettings.resolve_card_name(definition)]


## 为指定玩家摸若干牌；牌堆不足时自动将弃牌堆洗回，无法继续时提前停止。
func draw_cards(player_id: int, count: int, announce: bool = true) -> void:
	# 摸牌玩家状态；不存在或死亡玩家不会获得牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	# 实际摸牌数量；可能因牌堆与弃牌堆同时为空而少于请求值。
	var drawn_count: int = 0
	for _index: int in range(maxi(count, 0)):
		if state.draw_pile.is_empty():
			_reshuffle_discard_pile()
		if state.draw_pile.is_empty():
			break
		# 从牌堆顶抽出的实体牌；数组末尾作为牌堆顶。
		var card: CardInstance = state.draw_pile.pop_back()
		card.zone = "hand"
		card.owner_id = player_id
		player.hand.append(card)
		drawn_count += 1
	if announce and drawn_count > 0:
		add_log("%s摸了%d张牌。" % [player.display_name, drawn_count])


## 回复体力并限制在体力上限内；无效目标、死亡目标或非正数回复不会改变状态。
func recover(source_id: int, target_id: int, amount: int, reason: String = "") -> void:
	# 回复目标状态；死亡角色不能通过普通回复重新加入游戏。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or amount <= 0 or target.hp >= target.max_hp:
		return
	# 回复前体力；用于计算实际回复量并记录准确数值。
	var previous_hp: int = target.hp
	target.hp = mini(target.max_hp, target.hp + amount)
	add_log("%s回复%d点体力（%d/%d）。" % [target.display_name, target.hp - previous_hp, target.hp, target.max_hp])
	# 回复后事件；技能可读取来源、目标、实际回复值与原因牌。
	var event: RuleEvent = RuleEvent.new("recover_after", source_id, target_id, {"amount": target.hp - previous_hp, "reason": reason})
	event_bus.dispatch(event)


## 造成伤害并执行防具修正、濒死、死亡及属性连环传导。
func damage(source_id: int, target_id: int, amount: int, nature: String = "normal", card_id: String = "", chain_transfer: bool = false, ignore_armor: bool = false) -> void:
	# 受伤目标状态；死亡或无效目标不重复结算。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or amount <= 0:
		return
	# 最终伤害值；先应用武器增伤，再应用防具修正与事件处理器。
	var final_amount: int = amount
	if source_id >= 0 and card_id in ["sha", "sha_fire", "sha_thunder"] and player_has_equipment(source_id, "guding") and target.hand.is_empty():
		final_amount += 1
	if not ignore_armor:
		# 目标防具 ID；用于白银狮子与藤甲的锁定技修正。
		var armor_id: String = get_equipment_id(target_id, "armor")
		if armor_id == "baiyin" and final_amount > 1:
			final_amount = 1
		if armor_id == "tengjia" and nature == "fire":
			final_amount += 1

	# 伤害前事件；处理器可修改 amount 或取消整次伤害。
	var before_event: RuleEvent = RuleEvent.new("damage_before", source_id, target_id, {"amount": final_amount, "nature": nature, "card_id": card_id, "chain_transfer": chain_transfer})
	event_bus.dispatch(before_event)
	if before_event.cancelled:
		return
	final_amount = maxi(int(before_event.data.get("amount", final_amount)), 0)
	if final_amount == 0:
		return

	# 伤害发生前是否处于连环状态；属性伤害需要基于该状态决定传导。
	var should_chain: bool = nature != "normal" and target.chained and not chain_transfer
	# 需要接收传导的其他横置角色；在原目标结算前建立快照。
	var chain_targets: Array[int] = []
	if should_chain:
		for player: PlayerState in state.players:
			if player.alive and player.chained and player.player_id != target_id:
				chain_targets.append(player.player_id)

	target.hp -= final_amount
	if target.chained and nature != "normal":
		target.chained = false
	add_log("%s受到%d点%s伤害（%d/%d）。" % [target.display_name, final_amount, _nature_text(nature), target.hp, target.max_hp])
	# 伤害后事件；在濒死前触发，允许技能依据已扣减体力进行处理。
	var after_event: RuleEvent = RuleEvent.new("damage_after", source_id, target_id, {"amount": final_amount, "nature": nature, "card_id": card_id, "chain_transfer": chain_transfer})
	event_bus.dispatch(after_event)
	if target.hp <= 0:
		_resolve_dying(target_id, source_id)
	if state.game_over:
		return
	for chained_target_id: int in chain_targets:
		# 传导前再次检查角色仍存活且横置，避免前序死亡结算改变有效目标。
		var chained_target: PlayerState = state.get_player(chained_target_id)
		if chained_target != null and chained_target.alive and chained_target.chained:
			damage(source_id, chained_target_id, final_amount, nature, card_id, true, false)


## 消耗一张符合响应模式的牌；八卦阵与丈八蛇矛的转化也通过该入口处理。
func consume_response(player_id: int, response_pattern: String) -> bool:
	return consume_response_card(player_id, response_pattern) != null


## 消耗并返回响应实体牌或虚拟牌；返回 null 表示玩家无法响应。
func consume_response_card(player_id: int, response_pattern: String) -> CardInstance:
	# 响应玩家状态；死亡玩家不能使用或打出牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return null
	for card: CardInstance in player.get_playable_cards():
		# 当前手牌定义；response_pattern 允许普通与属性【杀】共享响应。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		if str(definition.get("response_pattern", "")) == response_pattern:
			# 从手牌移出的响应牌；随后直接进入弃牌堆。
			var consumed: CardInstance = player.take_playable_card(card.uid)
			_move_to_discard(consumed)
			add_log("%s打出了%s。" % [player.display_name, describe_card(consumed)])
			return consumed

	if response_pattern == "shan" and get_equipment_id(player_id, "armor") == "bagua":
		# 八卦阵判定牌；红色结果视为打出虚拟【闪】。
		var judgment_card: CardInstance = perform_judgment(player_id, "八卦阵")
		if judgment_card != null and judgment_card.get_color() == "red":
			add_log("%s的【八卦阵】判定为红色，视为打出【闪】。" % player.display_name)
			return CardInstance.new("shan", judgment_card.suit, judgment_card.rank)

	if response_pattern == "sha" and player_has_equipment(player_id, "zhangba") and player.get_playable_cards().size() >= 2:
		# 丈八蛇矛转化使用的第一张手牌；花色与点数仅用于虚拟牌展示。
		var first_card: CardInstance = player.get_playable_cards()[0]
		# 丈八蛇矛转化使用的第二张手牌；两张牌均作为消耗置入弃牌堆。
		var second_card: CardInstance = player.get_playable_cards()[1]
		_discard_playable_card(player_id, first_card.uid)
		_discard_playable_card(player_id, second_card.uid)
		add_log("%s发动【丈八蛇矛】，将两张手牌当【杀】打出。" % player.display_name)
		# 丈八蛇矛由两张牌组成的虚拟【杀】没有花色与点数，不能错误继承第一张材料牌的颜色。
		return CardInstance.new("sha", "none", 0)
	return null


## 处理普通锦囊的【无懈可击】响应链；同一玩家只要仍有合法牌即可在后续响应轮次再次响应。
func resolve_trick_negation(source_id: int, target_id: int, trick_id: String) -> bool:
	# 当前抵消状态；每使用一张【无懈可击】翻转一次，最终为 true 表示原锦囊被抵消。
	var negated: bool = false
	# 响应次数安全上限；默认牌堆只有7张【无懈可击】，较高上限用于兼容未来自定义牌堆。
	var response_count: int = 0
	while response_count < 100:
		# 本轮是否有玩家响应；无人响应时响应链结束。
		var response_played: bool = false
		for player: PlayerState in state.players:
			if not player.alive:
				continue
			# 玩家当前仍持有的【无懈可击】；每轮重新查询以允许同一玩家后续再次响应。
			var counter_card: CardInstance = _find_hand_card_by_definition(player, "wuxie")
			if counter_card == null:
				continue
			# 基础响应策略；只在当前抵消状态符合身份收益时使用一张牌。
			if not _should_auto_negate(player, source_id, target_id, trick_id, negated):
				continue
			player.take_playable_card(counter_card.uid)
			_move_to_discard(counter_card)
			negated = not negated
			response_count += 1
			response_played = true
			add_log("%s使用【无懈可击】，当前锦囊%s。" % [player.display_name, "被抵消" if negated else "恢复生效"])
			break
		if not response_played:
			break
	return negated


## 执行一次判定并将判定牌置入弃牌堆；返回牌对象供调用方读取花色与点数。
func perform_judgment(player_id: int, reason: String) -> CardInstance:
	if state.draw_pile.is_empty():
		_reshuffle_discard_pile()
	if state.draw_pile.is_empty():
		return null
	# 牌堆顶判定牌；判定生效后直接进入弃牌堆。
	var judgment_card: CardInstance = state.draw_pile.pop_back()
	judgment_card.zone = "processing"
	judgment_card.owner_id = -1
	state.processing_area.append(judgment_card)
	add_log("%s的%s判定牌为%s。" % [state.get_player(player_id).display_name, reason, describe_card(judgment_card)])
	state.processing_area.erase(judgment_card)
	_move_to_discard(judgment_card)
	return judgment_card


## 将处理区中的装备放入对应槽位，并处理旧装备离开时的效果。
func equip_from_processing(player_id: int, card: CardInstance) -> void:
	# 装备目标玩家；装备牌默认只能对自己使用。
	var player: PlayerState = state.get_player(player_id)
	# 装备卡定义；slot 决定唯一装备槽。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 装备槽名称；配置表保证非空。
	var slot: String = str(definition.get("slot", ""))
	if player.equipment.has(slot):
		_discard_equipment_slot(player_id, slot, true)
	state.processing_area.erase(card)
	card.zone = "equipment"
	card.owner_id = player_id
	player.equipment[slot] = card
	add_log("%s装备了%s。" % [player.display_name, describe_card(card)])


## 将处理区中的延时锦囊放入目标判定区。
func place_delayed_trick(target_id: int, card: CardInstance) -> void:
	# 延时锦囊目标；合法性层已保证其存活且判定区无同名牌。
	var target: PlayerState = state.get_player(target_id)
	state.processing_area.erase(card)
	card.zone = "judgment"
	card.owner_id = target_id
	target.judgment_area.append(card)
	add_log("%s的判定区加入了%s。" % [target.display_name, describe_card(card)])


## 弃置目标区域中的一张牌；基础选择顺序为装备、手牌、判定区。
func discard_one_from_player(_source_id: int, target_id: int) -> void:
	# 被弃牌目标状态；无牌时函数安全返回。
	var target: PlayerState = state.get_player(target_id)
	if not target.equipment.is_empty():
		# 首个装备槽；字典保持插入顺序，选择器接口可在后续替换。
		var slot: String = str(target.equipment.keys()[0])
		_discard_equipment_slot(target_id, slot, true)
	elif not target.hand.is_empty():
		discard_card_from_hand(target_id, target.hand[0].uid)
	elif not target.judgment_area.is_empty():
		# 被弃置的延时锦囊；从判定区移除后进入弃牌堆。
		var delayed_card: CardInstance = target.judgment_area.pop_front()
		_move_to_discard(delayed_card)


## 获得目标区域中的一张牌；基础选择顺序为装备、手牌、判定区。
func take_one_from_player(source_id: int, target_id: int) -> void:
	# 获得牌的玩家状态；所有取得的牌最终进入其手牌区。
	var source: PlayerState = state.get_player(source_id)
	# 失去牌的目标状态；合法性层已保证至少有一张牌。
	var target: PlayerState = state.get_player(target_id)
	# 实际取得的实体牌；按区域优先级选择。
	var taken_card: CardInstance
	if not target.equipment.is_empty():
		# 被取得的装备槽；移动前需处理木牛流马附属牌，但不触发白银狮子回复以外的丢失规则差异。
		var slot: String = str(target.equipment.keys()[0])
		taken_card = target.equipment[slot] as CardInstance
		target.equipment.erase(slot)
		_on_equipment_lost(target, taken_card, true)
	elif not target.hand.is_empty():
		taken_card = target.hand.pop_front()
	elif not target.judgment_area.is_empty():
		taken_card = target.judgment_area.pop_front()
	if taken_card == null:
		return
	taken_card.zone = "hand"
	taken_card.owner_id = source_id
	source.hand.append(taken_card)
	add_log("%s获得了%s的一张牌。" % [source.display_name, target.display_name])


## 弃置指定手牌 UID；返回是否成功，供火攻与装备技能复用。
func discard_card_from_hand(player_id: int, card_uid: int) -> bool:
	# 失去手牌的玩家；无效玩家直接失败。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return false
	# 从手牌移出的实体牌；未找到时返回 null。
	var card: CardInstance = player.take_hand_card(card_uid)
	if card == null:
		return false
	_move_to_discard(card)
	return true


## 弃置一张可使用牌，可来自普通手牌或木牛流马下的“粮”。
func _discard_playable_card(player_id: int, card_uid: int) -> bool:
	# 失去牌的玩家；无效 ID 直接失败。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return false
	# 从统一牌源移出的实体牌；找不到时返回 null。
	var card: CardInstance = player.take_playable_card(card_uid)
	if card == null:
		return false
	_move_to_discard(card)
	return true


## 弃置玩家区域内至多指定数量的牌；选择顺序为手牌、装备、判定区。
func discard_n_from_player(player_id: int, count: int) -> void:
	for _index: int in range(maxi(count, 0)):
		# 当前玩家状态；每次循环重新读取区域数量。
		var player: PlayerState = state.get_player(player_id)
		if not player.hand.is_empty():
			discard_card_from_hand(player_id, player.hand[0].uid)
		elif not player.equipment.is_empty():
			_discard_equipment_slot(player_id, str(player.equipment.keys()[0]), true)
		elif not player.judgment_area.is_empty():
			_move_to_discard(player.judgment_area.pop_front())
		else:
			return


## 返回玩家手牌、装备与判定区的可弃置牌总数。
func get_discardable_count(player_id: int) -> int:
	# 指定玩家状态；不存在时数量为0。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 0
	return player.hand.size() + player.equipment.size() + player.judgment_area.size()


## 返回玩家手牌区与装备区的牌数；装备技能的“弃置牌”费用和寒冰剑只允许操作这两个区域。
func get_hand_equipment_card_count(player_id: int) -> int:
	# 指定玩家状态；不存在时数量为0。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 0
	return player.hand.size() + player.equipment.size()


## 从玩家手牌区和装备区依次弃置至多指定数量的牌；不会错误弃置判定区中的延时锦囊。
func discard_n_from_hand_equipment(player_id: int, count: int) -> void:
	for _index: int in range(maxi(count, 0)):
		# 当前玩家状态；每次循环重新读取区域，保证装备离开效果结算后数量准确。
		var player: PlayerState = state.get_player(player_id)
		if player == null:
			return
		if not player.hand.is_empty():
			discard_card_from_hand(player_id, player.hand[0].uid)
		elif not player.equipment.is_empty():
			_discard_equipment_slot(player_id, str(player.equipment.keys()[0]), true)
		else:
			return


## 弃置目标装备区的第一张坐骑牌；麒麟弓造成伤害后调用。
func discard_first_mount(target_id: int) -> void:
	# 目标状态；按进攻坐骑、防御坐骑顺序寻找。
	var target: PlayerState = state.get_player(target_id)
	for slot: String in ["offensive_mount", "defensive_mount"]:
		if target.equipment.has(slot):
			_discard_equipment_slot(target_id, slot, true)
			return


## 弃置目标全部装备；水淹七军、死亡与主公惩罚可复用此操作。
func discard_all_equipment(target_id: int, trigger_loss_effects: bool = true) -> void:
	# 目标状态；复制键数组以允许循环中安全删除装备。
	var target: PlayerState = state.get_player(target_id)
	# 当前全部装备槽快照；后续删除不会影响遍历。
	var slots: Array = target.equipment.keys().duplicate()
	for slot_variant: Variant in slots:
		_discard_equipment_slot(target_id, str(slot_variant), trigger_loss_effects)


## 转移一个装备槽中的牌；借刀杀人使用该操作将武器交给来源角色手牌。
func transfer_equipment(from_id: int, to_id: int, slot: String) -> void:
	# 原持有者状态；指定槽为空时不执行。
	var from_player: PlayerState = state.get_player(from_id)
	# 接收者状态；借刀杀人将武器交入其手牌而非直接装备。
	var to_player: PlayerState = state.get_player(to_id)
	if not from_player.equipment.has(slot):
		return
	# 被转移的装备实体牌；离开装备区后触发丢失装备效果。
	var card: CardInstance = from_player.equipment[slot] as CardInstance
	from_player.equipment.erase(slot)
	_on_equipment_lost(from_player, card, true)
	card.zone = "hand"
	card.owner_id = to_id
	to_player.hand.append(card)
	add_log("%s将武器交给了%s。" % [from_player.display_name, to_player.display_name])


## 返回玩家指定装备槽中的卡牌配置 ID；空槽返回空字符串。
func get_equipment_id(player_id: int, slot: String) -> String:
	# 指定玩家状态；无效 ID 视为空槽。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.equipment.has(slot):
		return ""
	# 装备槽中的实体牌；返回其定义 ID。
	var card: CardInstance = player.equipment[slot] as CardInstance
	return card.definition_id


## 检查玩家是否装备指定配置 ID，不要求调用方知道其槽位。
func player_has_equipment(player_id: int, definition_id: String) -> bool:
	# 指定玩家状态；不存在时返回 false。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return false
	for card_variant: Variant in player.equipment.values():
		# 当前装备实体牌；逐项比较定义 ID。
		var card: CardInstance = card_variant as CardInstance
		if card.definition_id == definition_id:
			return true
	return false


## 返回玩家武将配置中的性别；未知或缺失配置返回 unknown。
func get_player_gender(player_id: int) -> String:
	# 指定玩家状态；用于取得武将 ID。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return "unknown"
	return str(GameDatabase.get_character(player.character_id).get("gender", "unknown"))


## 从牌堆顶亮出指定数量的公共牌并放入处理区。
func reveal_top_cards(count: int) -> Array[CardInstance]:
	# 亮牌结果；顺序与抽取顺序一致。
	var result: Array[CardInstance] = []
	for _index: int in range(maxi(count, 0)):
		if state.draw_pile.is_empty():
			_reshuffle_discard_pile()
		if state.draw_pile.is_empty():
			break
		# 当前亮出的牌；公共处理区不属于任何玩家。
		var card: CardInstance = state.draw_pile.pop_back()
		card.zone = "processing"
		card.owner_id = -1
		state.processing_area.append(card)
		result.append(card)
	return result


## 将五谷丰登亮出的牌交给指定玩家手牌。
func give_revealed_card(player_id: int, card: CardInstance) -> void:
	# 获得牌的玩家状态；死亡玩家不会在正常结算中调用。
	var player: PlayerState = state.get_player(player_id)
	state.processing_area.erase(card)
	card.zone = "hand"
	card.owner_id = player_id
	player.hand.append(card)
	add_log("%s从展示牌中获得了%s。" % [player.display_name, describe_card(card)])


## 将未被选择的展示牌移入弃牌堆。
func discard_revealed_card(card: CardInstance) -> void:
	state.processing_area.erase(card)
	_move_to_discard(card)


## 弃置装备槽并执行白银狮子、木牛流马等离开装备区效果。
func _discard_equipment_slot(player_id: int, slot: String, trigger_loss_effects: bool) -> void:
	# 失去装备的玩家状态；空槽安全返回。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.equipment.has(slot):
		return
	# 离开装备区的实体牌；先移除再执行丢失后效果。
	var card: CardInstance = player.equipment[slot] as CardInstance
	player.equipment.erase(slot)
	_on_equipment_lost(player, card, trigger_loss_effects)
	_move_to_discard(card)


## 处理装备离开后的附属状态与触发；不负责移动装备牌本身。
func _on_equipment_lost(player: PlayerState, card: CardInstance, trigger_loss_effects: bool) -> void:
	if card.definition_id == "muniu" and not player.wooden_ox_storage.is_empty():
		for stored_card: CardInstance in player.wooden_ox_storage:
			_move_to_discard(stored_card)
		player.wooden_ox_storage.clear()
	if trigger_loss_effects and card.definition_id == "baiyin" and player.alive and player.hp < player.max_hp:
		recover(player.player_id, player.player_id, 1, "baiyin")


## 创建玩家、分配身份与样例武将，并为非本地玩家安装基础 AI。
func _create_players(player_count: int) -> void:
	# 身份配置副本；洗牌后按座次分配，主公稍后作为首回合玩家。
	var identities: Array[String] = identity_rules.get_distribution(player_count)
	_shuffle_array(identities)
	# 可用武将 ID；样例不足人数时允许循环使用，接口本身支持任意扩展数量。
	var character_ids: Array = GameDatabase.characters.keys()
	_shuffle_array(character_ids)
	for index: int in range(player_count):
		# 新建玩家状态；显示名保持稳定座次便于日志辨认。
		var player: PlayerState = PlayerState.new(index, "玩家%d" % (index + 1))
		player.identity = identities[index]
		player.identity_revealed = player.identity == "lord"
		player.character_id = str(character_ids[index % character_ids.size()])
		# 武将配置；决定基础体力上限与显示资料。
		var character: Dictionary = GameDatabase.get_character(player.character_id)
		player.max_hp = maxi(int(character.get("max_hp", 4)), 1)
		if player.identity == "lord":
			player.max_hp += 1
		player.hp = player.max_hp
		state.players.append(player)
		if index != local_human_player_id:
			ai_coordinator.register_basic_ai(index)


## 根据牌堆配置创建实体牌、设置区域并洗牌。
func _create_and_shuffle_deck() -> void:
	for entry_variant: Variant in GameDatabase.get_deck_cards(state.deck_id):
		# 紧凑牌堆条目；格式为花色、点数、卡牌定义 ID。
		var entry: Array = entry_variant as Array
		# 新建实体牌；唯一 UID 由 CardInstance 自动分配。
		var card: CardInstance = CardInstance.new(str(entry[2]), str(entry[0]), int(entry[1]))
		card.zone = "draw_pile"
		card.owner_id = -1
		state.draw_pile.append(card)
	_shuffle_array(state.draw_pile)


## 开始指定玩家的回合，并依次处理开始、判定、摸牌，最终进入出牌阶段。
func _start_turn(player_id: int) -> void:
	if state.game_over:
		return
	# 新回合玩家状态；死亡玩家会由调用方提前跳过。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	_ai_drive_token += 1
	_ai_actions_this_turn = 0
	state.current_player_id = player_id
	state.turn_number += 1
	player.slash_count = 0
	player.wine_used = false
	player.wine_bonus = 0
	player.wooden_ox_used = false
	player.skipped_phases.clear()
	state.current_phase = "start"
	add_log("第%d回合：%s的回合开始。" % [state.turn_number, player.display_name])
	event_bus.dispatch(RuleEvent.new("phase_start", player_id, player_id, {}))
	if player.face_down:
		player.face_down = false
		add_log("%s翻回正面并跳过本回合。" % player.display_name)
		_finish_turn(player_id)
		return

	state.current_phase = "judgment"
	_process_judgment_area(player_id)
	if state.game_over or not player.alive:
		return
	state.current_phase = "draw"
	if not bool(player.skipped_phases.get("draw", false)):
		draw_cards(player_id, 2)
	else:
		add_log("%s跳过摸牌阶段。" % player.display_name)
	state.current_phase = "play"
	if bool(player.skipped_phases.get("play", false)):
		add_log("%s跳过出牌阶段。" % player.display_name)
		_end_play_phase(player_id)
		return
	_emit_state()
	if ai_coordinator.is_ai_controlled(player_id):
		_schedule_ai_action()


## 处理玩家判定区的全部延时锦囊。
func _process_judgment_area(player_id: int) -> void:
	# 判定玩家状态；复制判定区以允许结算中移动原数组。
	var player: PlayerState = state.get_player(player_id)
	# 当前待结算延时锦囊快照；按进入判定区的顺序处理。
	var delayed_cards: Array[CardInstance] = player.judgment_area.duplicate()
	for delayed_card: CardInstance in delayed_cards:
		if not player.alive or state.game_over or not player.judgment_area.has(delayed_card):
			continue
		player.judgment_area.erase(delayed_card)
		delayed_card.zone = "processing"
		delayed_card.owner_id = -1
		state.processing_area.append(delayed_card)
		# 延时锦囊是否在生效前被无懈可击抵消。
		var negated: bool = resolve_trick_negation(-1, player_id, delayed_card.definition_id)
		if delayed_card.definition_id == "shandian":
			if negated:
				_pass_lightning(player_id, delayed_card)
				continue
			# 闪电判定牌；黑桃2至9造成3点无来源雷电伤害。
			var lightning_judgment: CardInstance = perform_judgment(player_id, "【闪电】")
			if lightning_judgment != null and lightning_judgment.suit == "spade" and lightning_judgment.rank >= 2 and lightning_judgment.rank <= 9:
				state.processing_area.erase(delayed_card)
				_move_to_discard(delayed_card)
				damage(-1, player_id, 3, "thunder", "shandian")
			else:
				_pass_lightning(player_id, delayed_card)
		elif delayed_card.definition_id == "lebu":
			if not negated:
				# 乐不思蜀判定牌；非红桃时记录跳过出牌阶段。
				var lebu_judgment: CardInstance = perform_judgment(player_id, "【乐不思蜀】")
				if lebu_judgment != null and lebu_judgment.suit != "heart":
					player.skipped_phases["play"] = true
			state.processing_area.erase(delayed_card)
			_move_to_discard(delayed_card)
		elif delayed_card.definition_id == "bingliang":
			if not negated:
				# 兵粮寸断判定牌；非梅花时记录跳过摸牌阶段。
				var supply_judgment: CardInstance = perform_judgment(player_id, "【兵粮寸断】")
				if supply_judgment != null and supply_judgment.suit != "club":
					player.skipped_phases["draw"] = true
			state.processing_area.erase(delayed_card)
			_move_to_discard(delayed_card)


## 将未命中的闪电移动至下一名没有闪电的存活角色判定区；无合法角色时回到原角色。
func _pass_lightning(from_player_id: int, lightning_card: CardInstance) -> void:
	# 当前候选玩家；从原角色下家开始循环寻找。
	var candidate: PlayerState = state.get_next_alive_player(from_player_id)
	# 已检查角色数量；最多遍历全部存活角色一次。
	var checked_count: int = 0
	# 存活角色总数；用于限制循环。
	var alive_count: int = state.get_alive_players().size()
	while candidate != null and checked_count < alive_count:
		# 候选判定区是否已有闪电；同名延时锦囊不能重复放置。
		var has_lightning: bool = false
		for delayed_card: CardInstance in candidate.judgment_area:
			if delayed_card.definition_id == "shandian":
				has_lightning = true
				break
		if not has_lightning:
			state.processing_area.erase(lightning_card)
			lightning_card.zone = "judgment"
			lightning_card.owner_id = candidate.player_id
			candidate.judgment_area.append(lightning_card)
			add_log("【闪电】移动至%s的判定区。" % candidate.display_name)
			return
		candidate = state.get_next_alive_player(candidate.player_id)
		checked_count += 1
	# 所有角色均不是合法目标时，【闪电】按规则回到原角色判定区，而不是进入弃牌堆。
	var original_player: PlayerState = state.get_player(from_player_id)
	state.processing_area.erase(lightning_card)
	if original_player != null and original_player.alive:
		lightning_card.zone = "judgment"
		lightning_card.owner_id = original_player.player_id
		original_player.judgment_area.append(lightning_card)
		add_log("没有其他合法目标，【闪电】回到%s的判定区。" % original_player.display_name)
	else:
		_move_to_discard(lightning_card)


## 执行已通过合法性校验的出牌动作。
func _execute_card_use(actor_id: int, card: CardInstance, target_ids: Array[int]) -> void:
	# 使用牌的玩家状态；从其手牌移至处理区。
	var actor: PlayerState = state.get_player(actor_id)
	actor.take_playable_card(card.uid)
	card.zone = "processing"
	card.owner_id = -1
	state.processing_area.append(card)
	# 当前卡牌定义；用于次数计数与日志。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	if str(definition.get("effect_id", "")) == "slash":
		actor.slash_count += 1
	add_log("%s使用了%s。" % [actor.display_name, describe_card(card)])
	# 卡牌展示请求只携带序列化数据与稳定玩家 ID，界面可据此播放飞牌和目标指示动画，不持有权威状态对象。
	card_presentation_requested.emit(card.to_dict(), actor_id, target_ids.duplicate())
	event_bus.dispatch(RuleEvent.new("card_used", actor_id, target_ids[0] if not target_ids.is_empty() else -1, {"card_uid":card.uid, "card_id":card.definition_id, "target_ids":target_ids.duplicate()}))
	# 效果执行器返回的结束区域；装备与延时锦囊已在执行器中完成移动。
	var destination: String = effect_resolver.resolve(card, actor_id, target_ids)
	if destination == "discard" and state.processing_area.has(card):
		state.processing_area.erase(card)
		_move_to_discard(card)
	_check_game_over()


## 执行铁索连环等允许重铸的牌：弃置该牌并摸一张牌。
func _execute_recast(actor_id: int, card_uid: int) -> bool:
	# 重铸玩家状态；必须处于自己的出牌阶段。
	var actor: PlayerState = state.get_player(actor_id)
	if state.current_phase != "play" or actor == null:
		return _reject("当前不能重铸。")
	# 被重铸手牌；不存在时拒绝。
	var card: CardInstance = actor.find_hand_card(card_uid)
	if card == null:
		return _reject("重铸牌不在手牌中。")
	# 卡牌定义；只有 recast 标记为 true 的牌可重铸。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	if not bool(definition.get("recast", false)):
		return _reject("该卡牌不能重铸。")
	actor.take_hand_card(card.uid)
	_move_to_discard(card)
	add_log("%s重铸了%s。" % [actor.display_name, GameSettings.resolve_card_name(definition)])
	draw_cards(actor_id, 1)
	return true


## 将一张手牌扣置于木牛流马下，并可选择把木牛流马与全部“粮”转移给一名其他角色。
func _execute_wooden_ox_store(actor_id: int, card_uid: int, target_ids: Array[int]) -> bool:
	# 发动木牛流马的玩家；必须处于自己的出牌阶段且仍装备该宝物。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null or state.current_phase != "play" or state.current_player_id != actor_id:
		return _reject("当前不能发动木牛流马。")
	if not player_has_equipment(actor_id, "muniu"):
		return _reject("玩家未装备木牛流马。")
	if actor.wooden_ox_used:
		return _reject("本阶段已经发动过木牛流马。")
	if target_ids.size() > 1:
		return _reject("木牛流马最多转移给一名其他角色。")
	# 木牛流马转移目标；未选择目标时为 null，选择后必须是另一名存活角色。
	var target: PlayerState
	if target_ids.size() == 1:
		target = state.get_player(target_ids[0])
		if target == null or not target.alive or target.player_id == actor_id:
			return _reject("木牛流马转移目标不合法。")
	# 被扣置的手牌；规则要求只能从手牌存入，不能再次存入已有“粮”。
	var stored_card: CardInstance = actor.take_hand_card(card_uid)
	if stored_card == null:
		return _reject("木牛流马只能扣置一张手牌。")
	stored_card.zone = "wooden_ox"
	stored_card.owner_id = actor_id
	actor.wooden_ox_storage.append(stored_card)
	actor.wooden_ox_used = true
	add_log("%s将一张手牌扣置于【木牛流马】下。" % actor.display_name)
	if target == null:
		return true
	if target.equipment.has("treasure"):
		_discard_equipment_slot(target.player_id, "treasure", true)
	# 被转移的木牛流马实体牌；转移到装备区不会触发粮弃置。
	var wooden_ox: CardInstance = actor.equipment["treasure"] as CardInstance
	actor.equipment.erase("treasure")
	target.equipment["treasure"] = wooden_ox
	wooden_ox.owner_id = target.player_id
	wooden_ox.zone = "equipment"
	target.wooden_ox_storage.append_array(actor.wooden_ox_storage)
	for card: CardInstance in target.wooden_ox_storage:
		card.owner_id = target.player_id
	actor.wooden_ox_storage.clear()
	add_log("%s将【木牛流马】及其下的“粮”转移给%s。" % [actor.display_name, target.display_name])
	return true


## 结束出牌阶段，自动执行基础弃牌阶段并开始下名存活玩家的回合。
func _end_play_phase(player_id: int) -> void:
	if state.current_player_id != player_id or state.current_phase != "play":
		_reject("当前不能结束出牌阶段。")
		return
	_ai_drive_token += 1
	state.current_phase = "discard"
	# 当前玩家状态；按手牌末尾顺序自动弃至体力上限，后续可替换为交互选择器。
	var player: PlayerState = state.get_player(player_id)
	# 需要弃置的手牌数；体力为负时手牌上限按0处理。
	var discard_count: int = maxi(player.hand.size() - player.get_hand_limit(), 0)
	for _index: int in range(discard_count):
		if not player.hand.is_empty():
			discard_card_from_hand(player_id, player.hand.back().uid)
	if discard_count > 0:
		add_log("%s在弃牌阶段弃置了%d张手牌。" % [player.display_name, discard_count])
	_finish_turn(player_id)


## 完成回合结束事件并转交给下一名存活玩家。
func _finish_turn(player_id: int) -> void:
	state.current_phase = "finish"
	event_bus.dispatch(RuleEvent.new("phase_finish", player_id, player_id, {}))
	# 当前回合结束后清除所有未消耗的【酒】加值；该效果只持续到使用【酒】的本回合结束。
	for player: PlayerState in state.players:
		player.wine_bonus = 0
	_check_game_over()
	if state.game_over:
		return
	# 下一名存活玩家；身份局至少有两人存活时继续正常轮转。
	var next_player: PlayerState = state.get_next_alive_player(player_id)
	if next_player != null:
		_start_turn(next_player.player_id)


## 依次请求所有存活角色使用桃，濒死角色还可使用酒自救；无人救援则进入死亡结算。
func _resolve_dying(target_id: int, killer_id: int) -> void:
	# 濒死角色状态；可能需要多张桃才能将体力回复至1。
	var target: PlayerState = state.get_player(target_id)
	add_log("%s进入濒死状态，需要回复至1点体力。" % target.display_name)
	event_bus.dispatch(RuleEvent.new("dying_begin", killer_id, target_id, {"required_recover":1 - target.hp}))
	while target.alive and target.hp <= 0:
		# 本轮是否有人成功救援；若为 false 则结束循环并死亡。
		var rescued: bool = false
		for rescuer: PlayerState in state.players:
			if not rescuer.alive:
				continue
			# 救援者使用的桃；所有存活角色均可对濒死目标使用。
			var peach: CardInstance = _consume_specific_hand_card(rescuer, "tao")
			if peach != null:
				add_log("%s对%s使用【桃】。" % [rescuer.display_name, target.display_name])
				recover(rescuer.player_id, target_id, 1, "tao")
				rescued = true
				break
			if rescuer.player_id == target_id:
				# 濒死者自救使用的酒；其他角色不能用酒救援目标。
				var wine: CardInstance = _consume_specific_hand_card(rescuer, "jiu")
				if wine != null:
					add_log("%s在濒死时使用【酒】自救。" % target.display_name)
					recover(target_id, target_id, 1, "jiu")
					rescued = true
					break
		if not rescued:
			_resolve_death(target_id, killer_id)
			return


## 执行死亡、身份公开、区域清理、奖惩和胜负检查。
func _resolve_death(victim_id: int, killer_id: int) -> void:
	# 死亡角色状态；先标记死亡，避免清理白银狮子时错误回复。
	var victim: PlayerState = state.get_player(victim_id)
	victim.alive = false
	victim.identity_revealed = true
	add_log("%s死亡，身份为%s。" % [victim.display_name, _identity_text(victim.identity)])
	while not victim.hand.is_empty():
		_move_to_discard(victim.hand.pop_back())
	discard_all_equipment(victim_id, false)
	while not victim.judgment_area.is_empty():
		_move_to_discard(victim.judgment_area.pop_back())
	# 击杀者状态；无来源伤害或击杀者已不存在时不执行奖惩。
	var killer: PlayerState = state.get_player(killer_id)
	# 身份规则返回的奖惩类型；控制器负责实际摸牌与弃牌移动。
	var reward: String = identity_rules.get_death_reward(killer, victim)
	if reward == "draw_three" and killer != null and killer.alive:
		draw_cards(killer.player_id, 3)
	elif reward == "lord_penalty" and killer != null and killer.alive:
		while not killer.hand.is_empty():
			_move_to_discard(killer.hand.pop_back())
		discard_all_equipment(killer.player_id, true)
		add_log("主公杀死忠臣，弃置全部手牌和装备。")
	_check_game_over()


## 检查身份胜负条件并结束对局。
func _check_game_over() -> void:
	if state == null or state.game_over:
		return
	# 身份规则判定的获胜方；空字符串表示继续。
	var winner: String = identity_rules.evaluate_winner(state)
	if winner.is_empty():
		return
	state.winner = winner
	state.game_over = true
	state.current_phase = "game_over"
	_ai_drive_token += 1
	for player: PlayerState in state.players:
		player.identity_revealed = true
	add_log("对局结束，获胜方：%s。" % _winner_text(winner))
	_emit_state()
	match_finished.emit(winner)


## 将闪电移至下一角色时、装备效果与其他规则共用的弃牌移动基础操作。
func _move_to_discard(card: CardInstance) -> void:
	if card == null:
		return
	card.zone = "discard_pile"
	card.owner_id = -1
	state.discard_pile.append(card)


## 弃牌堆洗回摸牌堆；处理区与玩家区域不参与洗牌。
func _reshuffle_discard_pile() -> void:
	if state.discard_pile.is_empty():
		return
	state.draw_pile = state.discard_pile
	state.discard_pile = []
	for card: CardInstance in state.draw_pile:
		card.zone = "draw_pile"
		card.owner_id = -1
	_shuffle_array(state.draw_pile)
	add_log("弃牌堆已重新洗入摸牌堆。")


## 将一个借刀杀人的合法双目标动作加入候选列表。
func _append_borrow_sword_actions(result: Array[Dictionary], player_id: int, card: CardInstance) -> void:
	for holder: PlayerState in state.players:
		if not holder.alive or holder.player_id == player_id or holder.get_weapon() == null:
			continue
		for victim: PlayerState in state.players:
			if not victim.alive or victim.player_id == holder.player_id:
				continue
			_append_if_legal(result, player_id, card, [holder.player_id, victim.player_id])


## 校验并追加一个使用牌候选动作。
func _append_if_legal(result: Array[Dictionary], player_id: int, card: CardInstance, requested_targets: Array[int]) -> void:
	# 自动展开后的目标；全体牌使用空请求数组即可。
	var normalized_targets: Array[int] = card_rules.normalize_targets(player_id, card, requested_targets)
	if card_rules.validate_use(player_id, card, normalized_targets).is_empty():
		result.append({"action_type":"use_card", "actor_id":player_id, "card_uid":card.uid, "target_ids":requested_targets.duplicate(), "card_definition_id":card.definition_id})


## 安排下一次 AI 操作；令牌保证阶段变化后旧计时器不会执行。
func _schedule_ai_action() -> void:
	if state == null or state.game_over or state.current_phase != "play":
		return
	# 本次异步任务令牌；与全局令牌不一致时回调直接失效。
	var token: int = _ai_drive_token
	_run_ai_after_delay(token)


## 等待展示延迟后请求 AI 动作，并再次进入统一 submit_action 入口。
func _run_ai_after_delay(token: int) -> void:
	await get_tree().create_timer(ai_action_delay_seconds).timeout
	if token != _ai_drive_token or state == null or state.game_over or state.current_phase != "play":
		return
	# 当前 AI 玩家 ID；阶段等待期间可能已发生变化，因此在延迟后读取。
	var player_id: int = state.current_player_id
	if not ai_coordinator.is_ai_controlled(player_id):
		return
	_ai_actions_this_turn += 1
	if _ai_actions_this_turn > max_ai_actions_per_turn:
		submit_action(PlayerAction.new("end_play", player_id))
		return
	# AI 可读取的权威完整快照；包含所有身份与手牌，但策略只能返回标准动作字典。
	var full_snapshot: Dictionary = state.to_dict(player_id, true)
	# 当前全部合法候选；核心在决策前完成枚举，AI 无权绕过合法性。
	var legal_actions: Array[Dictionary] = get_legal_actions(player_id)
	# 策略返回的动作数据；随后恢复为标准 PlayerAction 并再次校验。
	var action_data: Dictionary = ai_coordinator.request_action(player_id, full_snapshot, legal_actions)
	submit_action(PlayerAction.from_dict(action_data))


## 通过 Fisher-Yates 算法使用对局随机源原地洗牌，适用于任意 Array 类型。
func _shuffle_array(array: Array) -> void:
	for index: int in range(array.size() - 1, 0, -1):
		# 与当前位置交换的随机索引；范围包含0与当前索引。
		var swap_index: int = _rng.randi_range(0, index)
		# 临时保存当前位置元素；Variant 允许该函数复用到牌、身份与字符串数组。
		var temporary: Variant = array[index]
		array[index] = array[swap_index]
		array[swap_index] = temporary


## 处理网络网关交付的行为字典；网络与本地动作共用完全相同的校验入口。
func _on_network_command_received(command_data: Dictionary) -> void:
	submit_action(PlayerAction.from_dict(command_data))


## 发出面向本地玩家的状态快照，并让网络网关保留公共同步入口。
func _emit_state() -> void:
	if state == null:
		return
	# 本地界面快照；仅公开本地玩家手牌和自身身份。
	var local_snapshot: Dictionary = state.to_dict(local_human_player_id, false)
	state_changed.emit(local_snapshot)


## 拒绝动作并返回 false，统一错误信号与调用结果。
func _reject(message: String) -> bool:
	action_rejected.emit(message)
	return false


## 查找指定身份玩家；标准身份局中主公查询只会返回一人。
func _find_player_by_identity(identity: String) -> PlayerState:
	for player: PlayerState in state.players:
		if player.identity == identity:
			return player
	return null


## 按定义 ID 查找玩家手牌，供无懈可击与濒死救援使用。
func _find_hand_card_by_definition(player: PlayerState, definition_id: String) -> CardInstance:
	for card: CardInstance in player.get_playable_cards():
		if card.definition_id == definition_id:
			return card
	return null


## 消耗指定定义 ID 的手牌并直接置入弃牌堆。
func _consume_specific_hand_card(player: PlayerState, definition_id: String) -> CardInstance:
	# 找到的目标手牌；不存在时返回 null。
	var card: CardInstance = _find_hand_card_by_definition(player, definition_id)
	if card == null:
		return null
	player.take_playable_card(card.uid)
	_move_to_discard(card)
	return card


## 基础无懈可击策略；根据身份关系和锦囊收益方向决定是否自动响应。
func _should_auto_negate(responder: PlayerState, source_id: int, target_id: int, trick_id: String, currently_negated: bool) -> bool:
	# 响应者对目标的阵营态度；正值为友方，负值为敌方。
	var target_attitude: int = _identity_attitude(responder.identity, state.get_player(target_id).identity if state.get_player(target_id) != null else "")
	# 该锦囊对目标是否通常有利；有利锦囊与伤害/控制锦囊的响应方向相反。
	var beneficial: bool = trick_id in ["wuzhong", "taoyuan", "wugu"]
	if not currently_negated:
		return (beneficial and target_attitude < 0) or (not beneficial and target_attitude > 0)
	# 反无懈旨在恢复对友方的有利效果或恢复对敌方的有害效果。
	return (beneficial and target_attitude > 0) or (not beneficial and target_attitude < 0)


## 返回两个身份的简化阵营关系，供基础自动响应使用。
func _identity_attitude(from_identity: String, to_identity: String) -> int:
	if from_identity == "renegade":
		return -1
	if from_identity == to_identity:
		return 1
	if from_identity in ["lord", "loyalist"] and to_identity in ["lord", "loyalist"]:
		return 1
	return -1


## 将伤害属性 ID 转换为日志文本。
func _nature_text(nature: String) -> String:
	return {"normal":"普通", "fire":"火焰", "thunder":"雷电"}.get(nature, nature)


## 将身份 ID 转换为界面与日志文本。
func _identity_text(identity: String) -> String:
	return {"lord":"主公", "loyalist":"忠臣", "rebel":"反贼", "renegade":"内奸"}.get(identity, identity)


## 将获胜方 ID 转换为界面与日志文本。
func _winner_text(winner: String) -> String:
	return {"lord_and_loyalists":"主公与忠臣", "rebels":"反贼", "renegade":"内奸"}.get(winner, winner)
